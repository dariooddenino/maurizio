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

pub const StyleCache = std.AutoHashMap(u32, ?Theme.Token);

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

const App = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: *vaxis.Vaxis,
    buffer: *Buffer,
    style_cache: *StyleCache,
    theme: *Theme,

    fn getTheme(m_theme: ?[]const u8) !Theme {
        const theme = m_theme orelse "default";

        for (themes.themes) |th| {
            if (std.mem.eql(u8, th.name, theme)) {
                return th;
            }
        }
        unreachable;
    }

    // TODO I don't like this
    fn applyTheme(vx: *vaxis.Vaxis, tty: vaxis.Tty, theme: *Theme) !void {
        try vx.setTerminalBackgroundColor(tty.anyWriter(), Color.rgbFromUint(theme.editor.bg orelse 0).rgb);
        // Possibly notify of change?
    }

    pub fn init(allocator: std.mem.Allocator, content: ?[]const u8) !App {
        const vx = try allocator.create(vaxis.Vaxis);
        vx.* = try vaxis.init(allocator, .{});
        const tty = try vaxis.Tty.init();

        const style_cache = try allocator.create(StyleCache);
        style_cache.* = StyleCache.init(allocator);

        const theme = try allocator.create(Theme);
        theme.* = try getTheme("rose-pine-dawn");
        try App.applyTheme(vx, tty, theme);

        const buffer = try allocator.create(Buffer);
        if (content) |c| {
            buffer.* = try Buffer.init(allocator, vx, style_cache, theme, c);
        } else {
            buffer.* = try Buffer.initEmpty(allocator, vx, style_cache, theme);
        }

        vx.sgr = .legacy;

        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = tty,
            .vx = vx,
            .buffer = buffer,
            .style_cache = style_cache,
            .theme = theme,
        };
    }

    pub fn deinit(self: *App) !void {
        // TODO assuming that this was black to begin with...
        try self.vx.setTerminalBackgroundColor(self.tty.anyWriter(), .{ 0, 0, 0 });
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.buffer.deinit();
        self.allocator.destroy(self.buffer);
        self.style_cache.deinit();
        self.allocator.destroy(self.style_cache);
        self.allocator.destroy(self.vx);
    }

    pub fn run(self: *App) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = self.vx,
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
                } else if (key.matches('1', .{})) {
                    const theme = try getTheme("default");
                    self.theme.* = theme;
                    try App.applyTheme(self.vx, self.tty, self.theme);
                } else if (key.matches('2', .{})) {
                    const theme = try getTheme("rose-pine-dawn");
                    self.theme.* = theme;
                    try App.applyTheme(self.vx, self.tty, self.theme);
                } else {
                    try self.buffer.handleKey(.{ .key_press = key });
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
        }
    }

    pub fn draw(self: *App) !void {
        const win = self.vx.window();

        if (win.width == 0) return;

        win.clear();
        self.vx.setMouseShape(.default);

        const child = win.initChild(0, 0, .expand, .expand);

        try self.buffer.draw(child);
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

    // TODO this should only impact content, not the whole app starting.
    if (res.positionals.len > 0) {
        for (res.positionals) |arg| {
            const file = try std.fs.cwd().openFile(arg, .{ .mode = .read_only });
            defer file.close();
            const content = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
            defer allocator.free(content);
            var app = try App.init(allocator, content);

            try app.run();
            try app.deinit();
        }
    } else {
        const content: []const u8 = "";
        // Initialize our application
        var app = try App.init(allocator, content);

        // Run the application
        try app.run();
        try app.deinit();
    }
}
