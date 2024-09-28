const std = @import("std");
const syntax = @import("syntax");

const Allocator = std.mem.Allocator;

pub const SimpleBuffer = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator, text: []const u8) !SimpleBuffer {
        var buffer = try std.ArrayList(u8).initCapacity(allocator, text.len);
        try buffer.appendSlice(text);
        return SimpleBuffer{
            .allocator = allocator,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *SimpleBuffer) void {
        self.buffer.deinit();
    }

    pub fn getValueRange(self: *SimpleBuffer, start: usize, end: usize) ![]const u8 {
        if (start > end or end > self.buffer.items.len) {
            return error.OutOfBounds;
        }
        const slice = self.buffer.items[start..end];
        const result = try self.allocator.alloc(u8, slice.len);
        @memcpy(result, slice);
        return result;
    }

    pub fn getValue(self: *SimpleBuffer) ![]const u8 {
        return try self.getValueRange(0, self.buffer.items.len);
    }

    pub fn append(self: *SimpleBuffer, text: []const u8) !void {
        try self.buffer.appendSlice(text);
    }

    pub fn insert(self: *SimpleBuffer, pos: usize, text: []const u8) !void {
        if (pos > self.buffer.items.len) {
            return error.OutOfBounds;
        }
        try self.buffer.insertSlice(pos, text);
    }

    pub fn delete(self: *SimpleBuffer, start: usize, end: usize) !void {
        if (start > end or end > self.buffer.items.len) {
            return error.OutOfBounds;
        }
        const remove_len = end - start;
        self.buffer.replaceRange(start, remove_len, &[_]u8{}) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
            };
        };
    }

    pub fn deleteLast(self: *SimpleBuffer) !void {
        if (self.buffer.items.len > 0) {
            _ = self.buffer.pop();
        }
    }

    // This function is not needed for ArrayList, but included for API compatibility
    fn adjust(self: *SimpleBuffer) !void {
        _ = self;
    }
};
