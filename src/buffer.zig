const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Rope = @import("rope.zig").Rope;
const Key = vaxis.Key;
const Vaxis = vaxis.Vaxis;
const Event = @import("main.zig").Event;

// NOTE the whole way I'm handling movement is completely inefficient.
const Cursor = struct {
    x: usize = 0,
    y: usize = 0,
    // The actual position in the Rope
    pos: usize = 0,
    // TODO not used right now
    // shape: Cell.CursorShape = .block,
    // The grapheme index of the cursor. Am I actually using it?
    // grapheme_idx: usize = 0,

    pub fn toNewLine(self: *Cursor) void {
        self.y += 1;
        self.x = 0;
    }

    pub fn moveRight(self: *Cursor) void {
        self.x += 1;
    }

    pub fn moveLeft(self: *Cursor) void {
        if (self.x > 0) self.x -= 1;
    }

    pub fn moveUp(self: *Cursor) void {
        if (self.y > 0) self.y -= 1;
    }

    pub fn moveDown(self: *Cursor) void {
        self.y += 1;
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
    lines: Lines,

    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        const rope = try allocator.create(Rope);
        rope.* = try Rope.init(allocator, "");
        const cursor = try allocator.create(Cursor);
        cursor.* = Cursor{};
        const rope_l = std.ArrayList(u8).init(allocator);
        const lines = Lines.init(allocator);

        return .{
            .allocator = allocator,
            .rope = rope,
            .cursor = cursor,
            .rope_l = rope_l,
            .lines = lines,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.lines.deinit();
        self.rope.deinit();
        self.rope_l.deinit();
        self.allocator.destroy(self.rope);
        self.allocator.destroy(self.cursor);
    }

    pub fn draw(self: *Buffer, vx: Vaxis, win: vaxis.Window) !void {
        const rope_content = try self.rope.getValue();
        defer self.allocator.free(rope_content);
        // This can't be performant at all
        self.rope_l.clearAndFree();
        try self.rope_l.appendSlice(rope_content);

        const content = self.rope_l.items;

        var msg_iter = vx.unicode.graphemeIterator(content);

        // I guess the idea here is:
        // - store the lines layout
        // - get the current position of the cursor
        // -

        // Reinitialize the lines
        self.lines.clearAndFree();

        const Pos = struct { x: usize = 0, y: usize = 0 };
        var pos: Pos = .{};
        var byte_index: usize = 0;

        var index: usize = 0;
        while (msg_iter.next()) |grapheme| {
            const cluster = content[grapheme.offset..][0..grapheme.len];
            defer byte_index += cluster.len;

            const new_line = "\n";

            // Why isn't the new line char working? :/
            if (std.mem.eql(u8, cluster, new_line)) {
                if (index == content.len - 1) {
                    break;
                }
                try self.lines.append(index);
                pos.y += 1;
                pos.x = 0;
                continue;
            }

            const width = win.gwidth(cluster);
            defer pos.x +|= width;

            win.writeCell(pos.x, pos.y, .{
                .char = .{
                    .grapheme = cluster,
                    .width = width,
                },
            });

            index += 1;
            // I don't think I'm using this
            // if (index == self.cursor.grapheme_idx) self.cursor.x = pos.x;
        }
    }

    pub fn handleKey(self: *Buffer, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches(Key.backspace, .{})) {
                    // self.deleteBeforeCursor();
                    // To delete properly I have to to go from .{x, y} to pos, which I can't do right now.
                    // try self.rope.deleteLast();
                    // TODO don't try to go on new lines!
                    try self.rope.delete(self.cursor.x - 1, self.cursor.x);
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
