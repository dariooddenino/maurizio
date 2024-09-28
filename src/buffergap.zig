const std = @import("std");

const Allocator = std.mem.Allocator;

pub const BufferGap = struct {
    allocator: Allocator,
    buffer: []u8,
    gap_start: usize,
    gap_end: usize,

    pub fn init(allocator: Allocator, text: []const u8) !BufferGap {
        const initial_capacity = @max(text.len * 2, 64);
        var buffer = try allocator.alloc(u8, initial_capacity);
        @memcpy(buffer[0..text.len], text);

        return BufferGap{
            .allocator = allocator,
            .buffer = buffer,
            .gap_start = text.len,
            .gap_end = buffer.len,
        };
    }

    pub fn deinit(self: *BufferGap) void {
        self.allocator.free(self.buffer);
    }

    pub fn getValueRange(self: *BufferGap, start: usize, end: usize) ![]const u8 {
        var result = try self.allocator.alloc(u8, end - start);
        errdefer self.allocator.free(result);

        var i: usize = 0;
        var j: usize = start;
        while (j < end) : (j += 1) {
            if (j == self.gap_start) {
                j = self.gap_end;
            }
            if (j < self.buffer.len) {
                result[i] = self.buffer[j];
                i += 1;
            }
        }

        return result[0..i];
    }

    pub fn getValue(self: *BufferGap) ![]const u8 {
        return self.getValueRange(0, self.size());
    }

    pub fn append(self: *BufferGap, text: []const u8) !void {
        try self.insert(self.size(), text);
    }

    pub fn insert(self: *BufferGap, pos: usize, text: []const u8) !void {
        try self.moveGap(pos);
        try self.ensureCapacity(text.len);
        @memcpy(self.buffer[self.gap_start .. self.gap_start + text.len], text);
        self.gap_start += text.len;
    }

    pub fn delete(self: *BufferGap, start: usize, end: usize) !void {
        try self.moveGap(end);
        const delete_len = end - start;
        self.gap_start -= delete_len;
    }

    pub fn deleteLast(self: *BufferGap) !void {
        if (self.size() > 0) {
            try self.delete(self.size() - 1, self.size());
        }
    }

    fn moveGap(self: *BufferGap, pos: usize) !void {
        if (pos < self.gap_start) {
            const move_len = self.gap_start - pos;
            @memcpy(self.buffer[self.gap_end - move_len .. self.gap_end], self.buffer[pos..self.gap_start]);
            self.gap_end -= move_len;
            self.gap_start = pos;
        } else if (pos > self.gap_start) {
            const move_len = pos - self.gap_start;
            @memcpy(self.buffer[self.gap_start .. self.gap_start + move_len], self.buffer[self.gap_end .. self.gap_end + move_len]);
            self.gap_start += move_len;
            self.gap_end += move_len;
        }
    }

    fn ensureCapacity(self: *BufferGap, additional: usize) !void {
        const gap_size = self.gap_end - self.gap_start;
        if (gap_size < additional) {
            const new_capacity = @max(self.buffer.len * 2, self.buffer.len + additional);
            var new_buffer = try self.allocator.alloc(u8, new_capacity);
            @memcpy(new_buffer[0..self.gap_start], self.buffer[0..self.gap_start]);
            @memcpy(new_buffer[new_capacity - (self.buffer.len - self.gap_end) ..], self.buffer[self.gap_end..]);
            self.gap_end = new_capacity - (self.buffer.len - self.gap_end);
            self.allocator.free(self.buffer);
            self.buffer = new_buffer;
        }
    }

    fn size(self: *BufferGap) usize {
        return self.buffer.len - (self.gap_end - self.gap_start);
    }
};
