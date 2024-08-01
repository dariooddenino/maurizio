//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const posix = std.posix;
const process = std.process;
const unicode = std.unicode;
const log = std.log;

const spoon = @import("spoon");

// TODO should be an argument.
var term: spoon.Term = undefined;
var loop: bool = true;
var buf: [32]u8 = undefined;
var read: usize = undefined;
var empty = true;

// A single global allocator for now
var gpa = heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const MTerm = struct {
    pub fn init() !void {
        try term.init(.{});
    }

    pub fn deinit() void {
        term.deinit() catch {};
    }
};

pub fn main() !void {
    var force_legacy: bool = false;
    var mouse: bool = false;
    var it = process.ArgIteratorPosix.init();
    _ = it.next();
    while (it.next()) |arg| {
        if (mem.eql(u8, arg, "--force-legacy")) {
            force_legacy = true;
        } else if (mem.eql(u8, arg, "--mouse")) {
            mouse = true;
        } else {
            log.err("unknown option '{s}'", .{arg});
            return;
        }
    }

    try MTerm.init();
    defer MTerm.deinit();

    // const handleSigWinch = HandleSigWinch.init(term);

    try posix.sigaction(posix.SIG.WINCH, &posix.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = posix.empty_sigset,
        .flags = 0,
    }, null);

    var fds: [1]posix.pollfd = undefined;
    fds[0] = .{
        .fd = term.tty.?,
        .events = posix.POLL.IN,
        .revents = undefined,
    };

    try term.uncook(.{
        .request_kitty_keyboard_protocol = !force_legacy,
        .request_mouse_tracking = mouse,
    });

    try term.fetchSize();
    try term.setWindowTitle("maurizio", .{});
    try render();

    while (loop) {
        _ = try posix.poll(&fds, -1);

        read = try term.readInput(&buf);
        empty = false;
        try render();
    }
}

fn render() !void {
    var rc = try term.getRenderContext();
    defer rc.done() catch {};

    try rc.clear();

    try rc.moveCursorTo(0, 0);
    try rc.setAttribute(.{ .fg = .green, .reverse = true });
    var rpw = rc.restrictedPaddingWriter(term.width);
    try rpw.writer().writeAll(" MAURIZIO");
    try rpw.pad();

    try rc.moveCursorTo(1, 0);
    try rc.setAttribute(.{ .fg = .red, .bold = true });
    rpw = rc.restrictedPaddingWriter(term.width);
    try rpw.writer().writeAll(" Input demo / tester, q to exit.");
    try rpw.finish();

    try rc.moveCursorTo(3, 0);
    try rc.setAttribute(.{ .bold = true });
    if (empty) {
        rpw = rc.restrictedPaddingWriter(term.width);
        try rpw.writer().writeAll(" Press a key! Or try to paste something!");
        try rpw.finish();
    } else {
        rpw = rc.restrictedPaddingWriter(term.width);
        var writer = rpw.writer();
        try writer.writeAll(" Bytes read:    ");
        try rc.setAttribute(.{});
        try writer.print("{}", .{read});
        try rpw.finish();

        var valid_unicode = true;
        _ = unicode.Utf8View.init(buf[0..read]) catch {
            valid_unicode = false;
        };
        try rc.moveCursorTo(4, 0);
        try rc.setAttribute(.{ .bold = true });
        rpw = rc.restrictedPaddingWriter(term.width);
        writer = rpw.writer();
        try writer.writeAll(" Valid unicode: ");
        try rc.setAttribute(.{});
        if (valid_unicode) {
            try writer.writeAll("yes: \"");
            for (buf[0..read]) |c| {
                switch (c) {
                    127 => try writer.writeAll("^H"),
                    '\x1B' => try writer.writeAll("\\x1B"),
                    '\t' => try writer.writeAll("\\t"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    'a' & '\x1F' => try writer.writeAll("^a"),
                    'b' & '\x1F' => try writer.writeAll("^b"),
                    'c' & '\x1F' => try writer.writeAll("^c"),
                    'd' & '\x1F' => try writer.writeAll("^d"),
                    'e' & '\x1F' => try writer.writeAll("^e"),
                    'f' & '\x1F' => try writer.writeAll("^f"),
                    'g' & '\x1F' => try writer.writeAll("^g"),
                    'h' & '\x1F' => try writer.writeAll("^h"),
                    'k' & '\x1F' => try writer.writeAll("^k"),
                    'l' & '\x1F' => try writer.writeAll("^l"),
                    'n' & '\x1F' => try writer.writeAll("^n"),
                    'o' & '\x1F' => try writer.writeAll("^o"),
                    'p' & '\x1F' => try writer.writeAll("^p"),
                    'q' & '\x1F' => try writer.writeAll("^q"),
                    'r' & '\x1F' => try writer.writeAll("^r"),
                    's' & '\x1F' => try writer.writeAll("^s"),
                    't' & '\x1F' => try writer.writeAll("^t"),
                    'u' & '\x1F' => try writer.writeAll("^u"),
                    'v' & '\x1F' => try writer.writeAll("^v"),
                    'w' & '\x1F' => try writer.writeAll("^w"),
                    'x' & '\x1F' => try writer.writeAll("^x"),
                    'y' & '\x1F' => try writer.writeAll("^y"),
                    'z' & '\x1F' => try writer.writeAll("^z"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeByte('"');
        } else {
            try writer.writeAll("no");
        }
        try rpw.finish();

        var it = spoon.inputParser(buf[0..read]);
        var i: usize = 1;
        while (it.next()) |in| : (i += 1) {
            rpw = rc.restrictedPaddingWriter(term.width);
            writer = rpw.writer();

            try rc.moveCursorTo(5 + (i - 1), 0);

            const msg = " Input events:  ";
            if (i == 1) {
                try rc.setAttribute(.{ .bold = true });
                try writer.writeAll(msg);
                try rc.setAttribute(.{ .bold = false });
            } else {
                try writer.writeByteNTimes(' ', msg.len);
            }

            var mouse: ?struct { x: usize, y: usize } = null;

            try writer.print("{}: ", .{i});
            switch (in.content) {
                .codepoint => |cp| {
                    if (cp == 'q') {
                        loop = false;
                        return;
                    }
                    try writer.print("codepoint: {} x{X}", .{ cp, cp });
                },
                .function => |f| try writer.print("F{}", .{f}),
                .mouse => |m| {
                    mouse = .{ .x = m.x, .y = m.y };
                    try writer.print("mouse {s} {} {}", .{ @tagName(m.button), m.x, m.y });
                },
                else => try writer.writeAll(@tagName(in.content)),
            }
            if (in.mod_alt) try writer.writeAll(" +Alt");
            if (in.mod_ctrl) try writer.writeAll(" +Ctrl");
            if (in.mod_super) try writer.writeAll(" +Super");

            try rpw.finish();

            if (mouse) |m| {
                try rc.moveCursorTo(m.y, m.x);
                try rc.setAttribute(.{ .bg = .red, .bold = true });
                try rc.buffer.writer().writeByte('X');
            }
        }
    }
}

// NOTE: run doesn't work sadly, it's treated as a field instead of a function
// const HandleSigWinch = struct {
//     term: MTerm,

//     pub fn init(term: MTerm) HandleSigWinch {
//         return HandleSigWinch{ .term = term };
//     }

//     pub fn run(self: HandleSigWinch, _: c_int) callconv(.C) void {
//         self.term.fetchSize() catch {};
//         render(self.term) catch {};
//     }
// };

fn handleSigWinch(_: c_int) callconv(.C) void {
    term.fetchSize() catch {};
    render() catch {};
}
