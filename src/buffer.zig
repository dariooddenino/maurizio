const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Rope = @import("rope.zig").Rope;

// TODO I think I need a more general "Buffer" object to hold cursor, Rope, etc.
const Cursor = struct {
    x: usize = 0,
    y: usize = 0,
    // TODO not used right now
    shape: Cell.CursorShape = .block,
    // The grapheme index of the cursor. Am I actually using it?
    grapheme_idx: usize = 0,

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

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    rope: *Rope,
    cursor: *Cursor,

    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        const rope = try allocator.create(Rope);
        rope.* = try Rope.init(allocator, "");
        const cursor = try allocator.create(Cursor);
        cursor.* = Cursor{};

        return .{
            .allocator = allocator,
            .rope = rope,
            .cursor = cursor,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.rope.deinit();
        self.allocator.destroy(self.rope);
        self.allocator.destroy(self.cursor);
    }
};
