const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Rope = @import("rope.zig").Rope;
const Key = vaxis.Key;
const Vaxis = vaxis.Vaxis;
const Event = @import("main.zig").Event;
const Renderer = @import("renderer.zig").Renderer;

const treez = @import("treez");

const syntax = @import("syntax");
const Theme = @import("theme");
const themes = @import("themes");

// TODO going to new lines is slightly bugged
// TODO when crashing the terminal is not returned to normal

const XY = struct {
    x: usize = 0,
    y: usize = 0,
};

// NOTE the whole way I'm handling movement is completely inefficient.
const Cursor = struct {
    xy: XY,
    // The actual position in the Rope
    pos: usize = 0,
    // TODO not used right now
    // shape: Cell.CursorShape = .block,
    // The grapheme index of the cursor. Am I actually using it?
    // grapheme_idx: usize = 0,
    lines: *Lines,

    pub fn updateXY(self: *Cursor) void {
        self.xy = self.posToXY();
    }

    pub fn posToXY(self: *Cursor) XY {
        return self.customPosToXY(self.pos);
        // var line_index: usize = 0;
        // var remaining_pos = self.pos;
        // for (self.lines.items, 0..) |line_length, index| {
        //     if (remaining_pos > line_length) {
        //         remaining_pos -= line_length;
        //     } else {
        //         line_index = index;
        //         break;
        //     }
        // }

        // return XY{ .x = remaining_pos, .y = line_index };
    }

    // TODO Better name?
    pub fn customPosToXY(self: *Cursor, pos: usize) XY {
        var line_index: usize = 0;
        var remaining_pos = pos;
        for (self.lines.items, 0..) |line_length, index| {
            if (remaining_pos > line_length) {
                remaining_pos -= line_length;
            } else {
                line_index = index;
                break;
            }
        }

        return XY{ .x = remaining_pos, .y = line_index };
    }

    pub fn xYToPos(self: *Cursor, xy: XY) usize {
        var curr_pos: usize = 0;
        for (self.lines.items, 0..) |line_length, i| {
            if (i < xy.y) {
                curr_pos += line_length;
            } else {
                curr_pos += xy.x;
                break;
            }
        }
        return curr_pos;
    }

    // Get the current pos, get the target pos, find the difference
    pub fn toNewLine(self: *Cursor) void {
        const xy = self.posToXY();
        const target_x = 0;
        const target_y = xy.y + 1;
        self.pos = self.xYToPos(XY{ .x = target_x, .y = target_y });
    }

    pub fn moveRight(self: *Cursor) void {
        self.pos += 1;
    }

    pub fn moveLeft(self: *Cursor) void {
        self.pos -= 1;
    }

    pub fn moveUp(self: *Cursor) void {
        const xy = self.posToXY();
        if (xy.y > 0)
            self.pos = self.xYToPos(XY{ .x = xy.x, .y = xy.y - 1 });
    }

    pub fn moveDown(self: *Cursor) void {
        const xy = self.posToXY();
        self.pos = self.xYToPos(XY{ .x = xy.x, .y = xy.y + 1 });
    }
};

/// An attempt at keeping track of how long all lines are.
// const Lines = struct {
//     allocator: std.mem.Allocator,
//     rows: std.ArrayList(usize), // Should we have more length?

//     // pub fn init(allocator: std.mem.Allocator) !RowsMeta {
//     //   const rows = std.ArrayList.init(allocator);

//     // }
// };

const Lines = std.ArrayList(usize);

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    rope: *Rope,
    // I'm using this to go around the value lifetime, but it feels so bad.
    rope_l: std.ArrayList(u8),
    cursor: *Cursor,
    lines: *Lines,
    syntax: *syntax,
    theme: *Theme,

    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        return Buffer.init(allocator, "");
    }

    // TODO I guess this should init with a theme?
    pub fn init(allocator: std.mem.Allocator, content: []const u8) !Buffer {
        const rope = try allocator.create(Rope);
        rope.* = try Rope.init(allocator, "");
        try rope.append(content);
        const lines = try allocator.create(Lines);
        lines.* = Lines.init(allocator);
        const cursor = try allocator.create(Cursor);
        const xy: XY = XY{ .x = 0, .y = 0 };
        cursor.* = Cursor{ .lines = lines, .xy = xy };
        const rope_l = std.ArrayList(u8).init(allocator);
        const theme = try allocator.create(Theme);

        var buffer: Buffer = .{
            .allocator = allocator,
            .rope = rope,
            .cursor = cursor,
            .rope_l = rope_l,
            .lines = lines,
            .syntax = undefined,
            .theme = theme,
        };

        try buffer.setTheme(null);

        try Buffer.setSyntax(&buffer);

        return buffer;
    }

    fn setTheme(self: *Buffer, m_theme: ?[]const u8) !void {
        const theme = m_theme orelse "default";

        for (themes.themes) |th| {
            if (std.mem.eql(u8, th.name, theme)) {
                self.theme.* = th;
                return;
            }
        }
        unreachable;
    }

    // TODO should have a cache
    fn setSyntax(self: *Buffer) !void {
        const syntax_ = try syntax.create_file_type(self.allocator, try self.rope.getValue(), "zig");
        self.syntax = syntax_;
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.destroy(self.cursor);
        self.lines.deinit();
        self.allocator.destroy(self.lines);
        self.rope.deinit();
        self.rope_l.deinit();
        self.allocator.destroy(self.rope);
        self.syntax.destroy();
        self.allocator.destroy(self.syntax);
        self.allocator.destroy(self.theme);
    }

    pub fn draw_(self: *Buffer, vx: Vaxis, win: vaxis.Window) !void {
        _ = self;
        _ = vx;
        _ = win;
    }

    pub fn draw(self: *Buffer, vx: Vaxis, win: vaxis.Window) !void {
        _ = vx;
        const rope_content = try self.rope.getValue();
        defer self.allocator.free(rope_content);
        // This can't be performant at all
        self.rope_l.clearAndFree();
        try self.rope_l.appendSlice(rope_content);

        const content = self.rope_l.items;

        // var msg_iter = vx.unicode.graphemeIterator(content);

        // Reinitialize the lines
        self.lines.clearAndFree();

        // const Pos = struct { x: usize = 0, y: usize = 0 };
        // var pos: Pos = .{};
        // var byte_index: usize = 0;

        // var index: usize = 0;
        // while (msg_iter.next()) |grapheme| {
        //     const cluster = content[grapheme.offset..][0..grapheme.len];
        //     defer byte_index += cluster.len;

        //     const new_line = "\n";

        //     // Why isn't the new line char working? :/
        //     if (std.mem.eql(u8, cluster, new_line)) {
        //         if (index == content.len - 1) {
        //             break;
        //         }
        //         try self.lines.append(index);
        //         pos.y += 1;
        //         pos.x = 0;
        //         continue;
        //     }

        //     self.cursor.updateXY();

        //     const width = win.gwidth(cluster);
        //     defer pos.x +|= width;

        // TODO this styling is all very random for now
        // const style = theme.editor_selection;

        // const start_row: u32 = @intCast(pos.y);
        // const start_column: u32 = @intCast(pos.x);

        // Naive range for now
        // const range: ?syntax.Range = .{
        //     .start_point = .{ .row = start_row, .column = start_column },
        //     .end_point = .{ .row = start_row, .column = start_column + 10 },
        //     // .start_point = .{ .row = @as(u32, pos.x), .column = @as(u32, pos.y) },
        //     // .end_point = .{ .row = @as(u32, pos.x), .column = @as(u32, pos.y) + 1 },
        //     .start_byte = 0,
        //     .end_byte = 0,
        // };

        // std.debug.print("RANGE: {any}\n", .{range});

        var renderer: Renderer = .{
            .win = win,
            .theme = self.theme,
            .content = content,
            .syntax = self.syntax,
            // cursor?
        };

        // _ = renderer;
        try self.syntax.render(&renderer, Renderer.cb, null);

        // NOTE: temporarily disabled just to see what happens when trying to write directly with the tokens
        // std.debug.print("POS {any}, COL {any}\n\n", .{ pos, ctx.fg });

        // win.writeCell(pos.x, pos.y, .{
        //     .char = .{
        //         .grapheme = cluster,
        //         .width = width,
        //     },
        // });

        // index += 1;
        // I don't thiColor'm using this
        // if (index == self.cursor.grapheme_idx) self.cursor.x = pos.x;

        win.showCursor(self.cursor.xy.x, self.cursor.xy.y);
        // }
    }

    pub fn handleKey(self: *Buffer, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches(Key.backspace, .{})) {
                    // self.deleteBeforeCursor();
                    // To delete properly I have to to go from .{x, y} to pos, which I can't do right now.
                    // try self.rope.deleteLast();
                    // TODO don't try to go on new lines!
                    try self.rope.delete(self.cursor.pos - 1, self.cursor.pos);
                    self.cursor.moveLeft();
                } else if (key.matches(Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) {
                    // self.deleteAfterCursor();
                } else if (key.matches(Key.left, .{}) or key.matches('b', .{ .ctrl = true })) {
                    self.cursor.moveLeft();
                } else if (key.matches(Key.right, .{}) or key.matches('f', .{ .ctrl = true })) {
                    self.cursor.moveRight();
                } else if (key.matches(Key.up, .{})) {
                    self.cursor.moveUp();
                } else if (key.matches(Key.down, .{})) {
                    self.cursor.moveDown();
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
                    const content = try self.rope.getValue();
                    defer self.allocator.free(content);
                    _ = try file.writeAll(content);
                } else if (key.matches(Key.enter, .{})) {
                    try self.rope.append("\n");
                    self.cursor.toNewLine();
                } else if (key.text) |text| {
                    try self.rope.append(text);
                    self.cursor.moveRight();
                }
            },
            else => {},
        }
    }
};
