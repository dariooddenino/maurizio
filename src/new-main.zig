const std = @import("std");

const clap = @import("clap");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Key = vaxis.Key;
const syntax = @import("syntax");
const Theme = @import("theme");
const themes = @import("themes");

pub const panic = vaxis.panic_handler;
pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .vaxis, .level = .warn },
        .{ .scope = .vaxis_parser, .level = .warn },
    },
};

pub const Event = union(enum) {
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

const Ctx = struct {
    win: vaxis.Window,
    theme: *const Theme,
    content: []const u8,
    syntax: *syntax,
    last_pos: usize = 0,
    col: usize = 0,
    row: usize = 0,

    fn getToken(ctx: *@This(), scope: []const u8) ?Theme.Token {
        var idx = ctx.theme.tokens.len - 1;
        var done = false;
        while (!done) : (if (idx == 0) {
            done = true;
        } else {
            idx -= 1;
        }) {
            const token = ctx.theme.tokens[idx];
            const name = themes.scopes[token.id];
            if (name.len > scope.len)
                continue;
            if (std.mem.eql(u8, name, scope[0..name.len]))
                return token;
        }
        return null;
    }

    fn writeStyled(ctx: *@This(), text: []const u8, style: Theme.Style) !void {
        const style_ = .{
            .fg = Color.rgbFromUint(style.fg orelse 3),
            // .bg = Color.rgbFromUint(style.bg orelse 3),
        };

        ctx.win.writeCell(
            ctx.col,
            ctx.row,
            .{
                .style = style_,
                .char = .{ .grapheme = text },
            },
        );

        ctx.col += text.len;
    }

    fn writeLinesStyled(ctx: *@This(), text_: []const u8, style: Theme.Style) !void {
        var text = text_;

        while (std.mem.indexOf(u8, text, "\n")) |pos| {
            try ctx.writeStyled(text[0 .. pos + 1], style);
            ctx.row += 1;
            ctx.col = 0;
            text = text[pos + 1 ..];
        }
        try ctx.writeStyled(text, style);
    }

    /// TODO Starting to get there, the style is not quite right yet AND sometimes it's eating the end of the text.
    /// Could this be caused by overlapping styles?
    fn cb(ctx: *@This(), range: syntax.Range, scope: []const u8, _: u32, idx: usize, _: *const syntax.Node) error{Stop}!void {
        if (idx > 0) return;

        if (ctx.last_pos < range.start_byte) {
            const before_segment = ctx.content[ctx.last_pos..range.start_byte];
            ctx.writeLinesStyled(before_segment, ctx.theme.editor) catch return error.Stop;
            ctx.last_pos = range.start_byte;
        }

        if (range.start_byte < ctx.last_pos) return;

        const scope_segment = ctx.content[range.start_byte..range.end_byte];

        if (ctx.getToken(scope)) |token| {
            ctx.writeLinesStyled(scope_segment, token.style) catch return error.Stop;
        } else {
            ctx.writeLinesStyled(scope_segment, ctx.theme.editor) catch return error.Stop;
        }

        ctx.last_pos = range.end_byte;
    }
};

const App = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    content: []const u8,

    pub fn init(allocator: std.mem.Allocator) !App {
        const vx = try vaxis.init(allocator, .{});
        // const content: []const u8 = "const foo = (bar: int) => {\n  let baz = 2;\n  return bar + baz;\n}";
        const content: []const u8 = "pub const Foo = union(enum) {\n  foo: usize,\n};\n";
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = vx,
            .content = content,
        };
    }

    pub fn deinit(self: *App) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *App) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        try loop.init();

        try loop.start();
        defer loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());

        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        while (!self.should_quit) {
            loop.pollEvent();
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            try self.draw();

            var buffered = self.tty.bufferedWriter();
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    pub fn update(self: *App, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
        }
    }

    fn getParser(self: *App) !*syntax {
        return syntax.create_file_type(self.allocator, self.content, "zig");
    }

    pub fn draw(self: *App) !void {
        const win = self.vx.window();

        if (win.width == 0) return;

        win.clear();
        self.vx.setMouseShape(.default);

        // const child = win.initChild(0, 0, .expand, .expand);

        const lang = try self.getParser();
        defer lang.destroy();

        const theme = blk: {
            for (themes.themes) |theme| {
                if (std.mem.eql(u8, theme.name, "default")) {
                    break :blk theme;
                }
            }
            unreachable;
        };

        var ctx: Ctx = .{
            .win = win,
            .theme = &theme,
            .content = self.content,
            .syntax = lang,
        };

        try lang.render(&ctx, Ctx.cb, null);
    }
};

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

    const params = comptime clap.parseParamsComptime(
        \\-h, --help Display this help and exit.
        \\<file>...  File to open.   
    );

    const parsers = comptime .{
        .file = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{}) catch {};
        std.process.exit(1);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    // Initialize our application
    var app = try App.init(allocator);
    defer app.deinit();

    // Run the application
    try app.run();
}
