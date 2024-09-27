const std = @import("std");

const rope = @import("rope.zig");
const node = @import("node.zig");
const clap = @import("clap");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Key = vaxis.Key;
const Buffer = @import("buffer.zig").Buffer;
const Rope = rope.Rope;
const TextArea = @import("textarea.zig").TextArea;
const TextInput = vaxis.widgets.TextInput;
const syntax = @import("syntax");
const Theme = @import("theme");
const themes = @import("themes");
const border = vaxis.widgets.border;

/// TODO move this into a renderer module
/// and then use it in buffer in place of that broken code.

// Fallback mapping system between tree-sitter scope names and vscode theme scope names
pub const FallBack = struct { ts: []const u8, tm: []const u8 };
pub const fallbacks: []const FallBack = &[_]FallBack{
    .{ .ts = "namespace", .tm = "entity.name.namespace" },
    .{ .ts = "type", .tm = "entity.name.type" },
    .{ .ts = "type.defaultLibrary", .tm = "support.type" },
    .{ .ts = "struct", .tm = "storage.type.struct" },
    .{ .ts = "class", .tm = "entity.name.type.class" },
    .{ .ts = "class.defaultLibrary", .tm = "support.class" },
    .{ .ts = "interface", .tm = "entity.name.type.interface" },
    .{ .ts = "enum", .tm = "entity.name.type.enum" },
    .{ .ts = "function", .tm = "entity.name.function" },
    .{ .ts = "function.defaultLibrary", .tm = "support.function" },
    .{ .ts = "method", .tm = "entity.name.function.member" },
    .{ .ts = "macro", .tm = "entity.name.function.macro" },
    .{ .ts = "variable", .tm = "variable.other.readwrite , entity.name.variable" },
    .{ .ts = "variable.readonly", .tm = "variable.other.constant" },
    .{ .ts = "variable.readonly.defaultLibrary", .tm = "support.constant" },
    .{ .ts = "parameter", .tm = "variable.parameter" },
    .{ .ts = "property", .tm = "variable.other.property" },
    .{ .ts = "property.readonly", .tm = "variable.other.constant.property" },
    .{ .ts = "enumMember", .tm = "variable.other.enummember" },
    .{ .ts = "event", .tm = "variable.other.event" },

    // zig
    .{ .ts = "attribute", .tm = "keyword" },
    .{ .ts = "number", .tm = "constant.numeric" },
    .{ .ts = "conditional", .tm = "keyword.control.conditional" },
    .{ .ts = "operator", .tm = "keyword.operator" },
    .{ .ts = "boolean", .tm = "keyword.constant.bool" },
    .{ .ts = "string", .tm = "string.quoted" },
    .{ .ts = "repeat", .tm = "keyword.control.flow" },
    .{ .ts = "field", .tm = "variable" },
};

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

    /// Find a scope in the fallback list
    fn findScopeFallback(scope: []const u8) ?[]const u8 {
        for (fallbacks) |fallback| {
            if (fallback.ts.len > scope.len)
                continue;
            if (std.mem.eql(u8, fallback.ts, scope[0..fallback.ts.len]))
                return fallback.tm;
        }
        return null;
    }

    fn findScopeStyleNoFallback(theme: *const Theme, scope: []const u8) ?Theme.Token {
        var idx = theme.tokens.len - 1;
        var done = false;
        while (!done) : (if (idx == 0) {
            done = true;
        } else {
            idx -= 1;
        }) {
            const token = theme.tokens[idx];
            const name = themes.scopes[token.id];
            if (name.len > scope.len)
                continue;
            if (std.mem.eql(u8, name, scope[0..name.len]))
                return token;
        }
        return null;
    }

    fn getToken(ctx: *@This(), scope: []const u8) ?Theme.Token {
        return if (findScopeFallback(scope)) |tm_scope|
            findScopeStyleNoFallback(ctx.theme, tm_scope) orelse findScopeStyleNoFallback(ctx.theme, scope)
        else
            findScopeStyleNoFallback(ctx.theme, scope);
    }

    fn writeStyled(ctx: *@This(), text: []const u8, style: Theme.Style) !void {
        const style_ = .{
            .fg = Color.rgbFromUint(style.fg orelse 3),
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
    buffer: *Buffer,

    pub fn init(allocator: std.mem.Allocator, content: ?[]const u8) !App {
        var vx = try vaxis.init(allocator, .{});
        const buffer = try allocator.create(Buffer);
        if (content) |c| {
            buffer.* = try Buffer.init(allocator, c);
        } else {
            buffer.* = try Buffer.initEmpty(allocator);
        }

        // vx.caps.kitty_graphics = true;
        // vx.caps.rgb = true;
        vx.sgr = .legacy;
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = vx,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *App) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.buffer.deinit();
        self.allocator.destroy(self.buffer);
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
                } else if (key.matches('l', .{ .ctrl = true })) {
                    self.vx.queueRefresh();
                } else {
                    try self.buffer.handleKey(.{ .key_press = key });
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
        }
    }

    fn getParser(self: *App) !*syntax {
        return syntax.create_file_type(self.allocator, self.buffer.rope_l.items, "zig");
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
            .content = self.buffer.rope_l.items,
            .syntax = lang,
        };

        try lang.render(&ctx, Ctx.cb, null);

        // TODO should be
        //  try self.buffer.draw(self.vx, win);
        // cursor here? probably in the buffer
        win.showCursor(self.buffer.cursor.xy.x, self.buffer.cursor.xy.y);
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

    if (res.positionals.len > 0) {
        for (res.positionals) |arg| {
            const file = try std.fs.cwd().openFile(arg, .{ .mode = .read_only });
            defer file.close();
            const content = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
            defer allocator.free(content);
            var app = try App.init(allocator, content);
            defer app.deinit();

            try app.run();
        }
    } else {
        const content: []const u8 = "pub const Foo = union(enum) {\n  foo: usize,\n};\n";
        // Initialize our application
        var app = try App.init(allocator, content);
        defer app.deinit();

        // Run the application
        try app.run();
    }
}
