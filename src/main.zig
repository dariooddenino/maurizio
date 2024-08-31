const std = @import("std");
const rope = @import("rope.zig");
const vaxis = @import("vaxis");
const Buffer = @import("buffer.zig").Buffer;
const Cell = vaxis.Cell;
const Key = vaxis.Key;
const Rope = rope.Rope;
const TextArea = @import("textarea.zig").TextArea;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;

/// Set the default panic handler to vaxis panic_handler.
/// This will clean up the terminal if any panics occur
pub const panic = vaxis.panic_handler;

/// Set some scope levels for the vaxis scopes
pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .vaxis, .level = .warn },
        .{ .scope = .vaxis_parser, .level = .warn },
    },
};

/// Tagged union of all events our application will handle. These can be generated
/// by Vaxis or your own custom events
const Event = union(enum) {
    key_press: Key,
    key_release: Key,
    mouse: vaxis.Mouse,
    focus_in, // window has gained focus
    focus_out, // window has lost focus
    paste_start, // bracketed paste start
    paste_end, // bracketed paste end
    paste: []const u8, // osc 52 paste, caller must free
    color_report: vaxis.Color.Report, // osc 4, 10, 11, 12 response
    color_scheme: vaxis.Color.Scheme, // light / dark OS theme changes
    winsize: vaxis.Winsize, // window size has changed. Always sent when loop starts.
};

/// The application state
const Maurizio = struct {
    allocator: std.mem.Allocator,
    /// A flag for if we should quit
    should_quit: bool,
    /// The tty we are talking to
    tty: vaxis.Tty,
    /// The vaxis instance
    vx: vaxis.Vaxis,
    /// A mouse event that we will handle in the draw cycle
    mouse: ?vaxis.Mouse,
    /// Tracking the color
    color_idx: u8 = 0,
    /// One buffer for now
    buffer: *Buffer,

    pub fn init(allocator: std.mem.Allocator) !Maurizio {
        const vx = try vaxis.init(allocator, .{});
        const buffer = try allocator.create(Buffer);
        buffer.* = try Buffer.initEmpty(allocator);
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = vx,
            .mouse = null,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Maurizio) void {
        // Deinit takes an optional allocator. You can choose to pass an allocator
        // to clean up memory, or pass null if your application is shutting down
        // and let the OS clean up the memory
        self.buffer.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *Maurizio) !void {
        // Initialize the event loop. This particular loop requires intrusive init
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        try loop.init();

        // Start the event loop. Events will now be queued
        try loop.start();
        defer loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());

        // Query the terminal to detect advanced features, such as kitty keyboard
        // protocol, etc. This will automatically enable the features in the screen you are
        // in, so you will want to call it after entering the alt screen if you are a full
        // screen application. The second arg is a timeout for the terminal to send responses.
        // Typically the response will be very fast, however it could be slow on ssh connections.
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

        // Enable mouse events
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        // This is the main event loop. The basic structure is
        // 1. Handle events
        // 2. Draw application
        // 3. Render
        while (!self.should_quit) {
            // pollEvent blocks until we have an event
            loop.pollEvent();
            // tryEvent returns events until the queue is empty
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            // Draw our application after handling events
            const content = try self.buffer.rope.getValue();
            defer self.allocator.free(content);
            try self.draw(content);

            // It's best to use a buffered writer for the render method. TTY provides one, but you
            // may use your own. The provided bufferedWriter has a buffer size of 4096
            var buffered = self.tty.bufferedWriter();
            // Render the application on the screen
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    /// Update our applciation state from an event
    pub fn update(self: *Maurizio, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                // key.matches does some basic matching algorithms. Key matching can be complex in
                // the presence of kitty keyboard encodings, this will generally be a good approach.
                // There are other matching functions available for specific purposes, as well
                self.color_idx = switch (self.color_idx) {
                    255 => 0,
                    else => self.color_idx + 1,
                };
                if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    self.vx.queueRefresh();
                } else {
                    try self.handleKey(.{ .key_press = key });
                }
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
        }
    }

    fn handleKey(self: *Maurizio, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches(Key.backspace, .{})) {
                    // self.deleteBeforeCursor();
                    // To delete properly I have to to go from .{x, y} to pos, which I can't do right now.
                    try self.buffer.rope.deleteLast();
                    self.buffer.cursor.moveLeft();
                } else if (key.matches(Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) {
                    // self.deleteAfterCursor();
                } else if (key.matches(Key.left, .{}) or key.matches('b', .{ .ctrl = true })) {
                    self.buffer.cursor.moveLeft();
                } else if (key.matches(Key.right, .{}) or key.matches('f', .{ .ctrl = true })) {
                    self.buffer.cursor.moveRight();
                } else if (key.matches(Key.up, .{})) {
                    self.buffer.cursor.moveUp();
                } else if (key.matches(Key.down, .{})) {
                    self.buffer.cursor.moveDown();
                } else if (key.matches('a', .{ .ctrl = true }) or key.matches(Key.home, .{})) {
                    // self.buf.moveGapLeft(self.buf.firstHalf().len);
                } else if (key.matches('e', .{ .ctrl = true }) or key.matches(Key.end, .{})) {
                    // self.buf.moveGapRight(self.buf.secondHalf().len);
                } else if (key.matches('k', .{ .ctrl = true })) {
                    // self.deleteToEnd();
                } else if (key.matches('u', .{ .ctrl = true })) {
                    // self.deleteToStart();
                } else if (key.matches('b', .{ .alt = true }) or key.matches(Key.left, .{ .alt = true })) {
                    // self.moveBackwardWordwise();
                } else if (key.matches('f', .{ .alt = true }) or key.matches(Key.right, .{ .alt = true })) {
                    // self.moveForwardWordwise();
                } else if (key.matches('w', .{ .ctrl = true }) or key.matches(Key.backspace, .{ .alt = true })) {
                    // self.deleteWordBefore();
                } else if (key.matches('d', .{ .alt = true })) {
                    // self.deleteWordAfter();
                } else if (key.matches('s', .{ .ctrl = true })) {
                    const file = try std.fs.cwd().createFile(
                        "test_output.md",
                        .{},
                    );
                    defer file.close();
                    const content = try self.buffer.rope.getValue();
                    defer self.allocator.free(content);
                    _ = try file.writeAll(content);
                } else if (key.matches(Key.enter, .{})) {
                    try self.buffer.rope.append("\n");
                    self.buffer.cursor.toNewLine();
                } else if (key.text) |text| {
                    try self.buffer.rope.append(text);
                    // Should move to the end
                    self.buffer.cursor.moveRight();
                }
            },
            else => {},
        }
    }

    fn graphemesBeforeCursor(self: *const Maurizio, msg: []const u8) usize {
        var msg_iter = self.vx.unicode.graphemeIterator(msg);
        var i: usize = 0;
        while (msg_iter.next()) |_| {
            i += 1;
        }
        return i;
    }

    /// Draw our current state
    pub fn draw(self: *Maurizio, msg: []const u8) !void {
        // Window is a bounded area with a view to the screen. You cannot draw outside of a window's
        // bounds. They are light structures, not intended to be stored.
        const win = self.vx.window();

        if (win.width == 0) return;

        // std.debug.print("CURSOR\n: {any}", .{self.cursor});
        // const cursor_idx = self.graphemesBeforeCursor(msg);
        // self.cursor.x = cursor_idx;
        // self.cursor.y = 0;

        // Clearing the window has the effect of setting each cell to it's "default" state. Vaxis
        // applications typicallyy will be immediate mode, and you will redraw your entire
        // application during the draw cycle.
        win.clear();

        // In addition to clearing our window, we want to clear the mouse shape state since we may
        // be changing that as well
        self.vx.setMouseShape(.default);

        // const maurizio_color: usize = 233;

        // // Create a style
        // const style: vaxis.Style = .{
        //     .fg = .{ .index = maurizio_color },
        // };

        const logo_height = 6;
        const logo_width = 20;
        // Create a bordered child window
        const logo_child = win.child(.{
            // .border = .{ .where = .all, .style = style },
            .x_off = win.width - logo_width,
            .y_off = win.height - logo_height,
            .width = .{ .limit = logo_width },
            .height = .{ .limit = logo_height },
        });

        const logo_msg = "      /\\_/\\\n     ( o.o )\n      > ^ <\n M A U R I Z I O";

        var logo_row: usize = 0;
        var logo_current_col: usize = 0;
        for (logo_msg, 0..) |_, i| {
            const cell: Cell = .{
                .char = .{ .grapheme = logo_msg[i .. i + 1] },
                .style = .{
                    .fg = .{ .index = 3 },
                },
            };
            if (std.mem.eql(u8, logo_msg[i .. i + 1], "\n")) {
                logo_row += 1;
                logo_current_col = 0;
            } else {
                logo_child.writeCell(logo_current_col, logo_row, cell);
                logo_current_col += 1;
            }
        }

        const child = win.initChild(0, 0, .expand, .expand);

        var msg_iter = self.vx.unicode.graphemeIterator(msg);

        // const ellipsis: Cell.Character = .{ .grapheme = "…", .width = 1 };

        const Pos = struct { x: usize = 0, y: usize = 0 };
        var pos: Pos = .{};
        var byte_index: usize = 0;

        var index: usize = 0;
        while (msg_iter.next()) |grapheme| {
            const cluster = msg[grapheme.offset..][0..grapheme.len];
            defer byte_index += cluster.len;

            const new_line = "\n";

            // Why isn't the new line char working? :/
            if (std.mem.eql(u8, cluster, new_line)) {
                if (index == msg.len - 1) {
                    break;
                }
                pos.y += 1;
                pos.x = 0;
                continue;
            }

            const width = child.gwidth(cluster);
            defer pos.x +|= width;

            child.writeCell(pos.x, pos.y, .{
                .char = .{
                    .grapheme = cluster,
                    .width = width,
                },
            });

            index += 1;
            if (index == self.buffer.cursor.grapheme_idx) self.buffer.cursor.x = pos.x;
        }

        win.showCursor(self.buffer.cursor.x, self.buffer.cursor.y);

        // IS THIS USLESS?
        // try self.vx.render(self.tty.anyWriter());
    }
};

/// Kepp our main function small. Typycally handling arg parsing and initialization only
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        // fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }

    const allocator = gpa.allocator();

    // Initialize our application
    var app = try Maurizio.init(allocator);
    defer app.deinit();

    // Run the application
    try app.run();
}

test {
    _ = rope;
}
