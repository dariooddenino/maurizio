const std = @import("std");

const Allocator = std.mem.Allocator;
const Node = @import("node.zig").Node;

pub const Rope = struct {
    allocator: Allocator,
    root: *Node,

    /// Initialize an empty Rope
    pub fn init(allocator: Allocator, text: []const u8) !Rope {
        const root = try Node.createLeaf(allocator, text);
        return Rope{
            .allocator = allocator,
            .root = root,
        };
    }

    /// Deinit the Rope
    pub fn deinit(self: *Rope) void {
        self.root.deinit(self.allocator);
        // self.allocator.destroy(self.root);
    }

    /// Get the value of the Rope in the given range.
    pub fn getValueRange(self: *Rope, start: usize, end: usize) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        try self.root.getValueRange(&buffer, start, end);
        const result = try buffer.toOwnedSlice();
        return result;
    }

    /// Get the full value of the Rope
    pub fn getValue(self: *Rope) ![]const u8 {
        return try self.getValueRange(0, self.root.full_size);
    }

    /// Append at the end of the Rope
    pub fn append(self: *Rope, text: []const u8) !void {
        try self.root.append(self.allocator, text);
        try self.adjust();
    }

    /// Insert in the middle of the Rope
    pub fn insert(self: *Rope, pos: usize, text: []const u8) !void {
        try self.root.insert(self.allocator, pos, text);
        try self.adjust();
    }

    /// Delete the range in the Rope
    pub fn delete(self: *Rope, start: usize, end: usize) !void {
        try self.root.delete(self.allocator, start, end);
        try self.adjust();
    }

    pub fn deleteLast(self: *Rope) !void {
        if (self.root.size > 0)
            try self.delete(self.root.full_size - 1, self.root.full_size);
    }

    /// TODO check balance and rebuild the tree if needed
    fn adjust(self: *Rope) !void {
        _ = self;
    }
};
