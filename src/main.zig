const std = @import("std");
// const rope = @import("rope.zig");
const ropey = @import("ropey.zig");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
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
    key_press: vaxis.Key,
    key_release: vaxis.Key,
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
const MyApp = struct {
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
    /// The text input
    text_input: TextInput,

    pub fn init(allocator: std.mem.Allocator) !MyApp {
        var vx = try vaxis.init(allocator, .{});
        const text_input = TextInput.init(allocator, &vx.unicode);
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = vx,
            .mouse = null,
            .text_input = text_input,
        };
    }

    pub fn deinit(self: *MyApp) void {
        // Deinit takes an optional allocator. You can choose to pass an allocator
        // to clean up memory, or pass null if your application is shutting down
        // and let the OS clean up the memory
        self.text_input.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *MyApp) !void {
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
            self.draw();

            // It's best to use a buffered writer for the render method. TTY provides one, but you
            // may use your own. The provided bufferedWriter has a buffer size of 4096
            var buffered = self.tty.bufferedWriter();
            // Render the application on the screen
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    /// Update our applciation state from an event
    pub fn update(self: *MyApp, event: Event) !void {
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
                    try self.text_input.update(.{ .key_press = key });
                }
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
        }
    }

    /// Draw our current state
    pub fn draw(self: *MyApp) void {

        // Window is a bounded area with a view to the screen. You cannot draw outside of a window's
        // bounds. They are light structures, not intended to be stored.
        const win = self.vx.window();

        // Clearing the window has the effect of setting each cell to it's "default" state. Vaxis
        // applications typicallyy will be immediate mode, and you will redraw your entire
        // application during the draw cycle.
        win.clear();

        // In addition to clearing our window, we want to clear the mouse shape state since we may
        // be changing that as well
        self.vx.setMouseShape(.default);

        // Create a style
        const style: vaxis.Style = .{
            .fg = .{ .index = self.color_idx },
        };

        // Create a bordered child window
        const child = win.child(.{
            .x_off = win.width / 2 - 20,
            .y_off = win.height / 2 - 3,
            .width = .{ .limit = 40 },
            .height = .{ .limit = 3 },
            .border = .{ .where = .all, .style = style },
        });

        // const child = win.child(.{
        //     .x_off = (win.width / 2) - 7,
        //     .y_off = win.height / 2 + 1,
        //     .width = .{ .limit = msg.len },
        //     .height = .{ .limit = 1 },
        // });

        // mouse events are much easier to handle in the draw cycle. Windows have a helper method to
        // determine if the event occurred in the target window. This method returns null if there
        // is no mouse event, or if it occurred outside of the window
        // const style: vaxis.Style = if (child.hasMouse(self.mouse)) |_| blk: {
        //     // We handled the mouse event, so set it to null
        //     self.mouse = null;
        //     self.vx.setMouseShape(.pointer);
        //     break :blk .{ .reverse = true };
        // } else .{};

        // Print a text segment to the screen. This is a helper function which iterates over the
        // text field for graphemes. Alternatively, you can implement your own print functions and
        // use the writeCell API.
        // _ = try child.printSegment(.{ .text = msg, .style = style }, .{});

        // Draw the text input in the child window
        self.text_input.draw(child);
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
    var app = try MyApp.init(allocator);
    defer app.deinit();

    // Run the application
    try app.run();
}

test {
    // _ = rope;
    _ = ropey;
}
