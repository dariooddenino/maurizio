const std = @import("std");

// NOTES
// - full_size needs to be checked, how was it behaving before?
// - what should happen when splitting actually??
// - split doesn't work (see 146)
// - split doesn't update sizes correctly

pub const Rope = struct {
    allocator: std.mem.Allocator,
    root: *Node,

    /// Initialize the tree with a string
    pub fn init(allocator: std.mem.Allocator, string: []const u8) !Rope {
        const root = try allocator.create(Node);
        root.* = Node.fromString(string);
        return Rope{ .allocator = allocator, .root = root };
    }

    pub fn deinit(self: *Rope) void {
        self.root.deinit(self.allocator);
    }

    /// Join a new Node into the Rope
    fn join(self: *Rope, other: Node) !void {
        try self.root.join(self.allocator, other);
    }

    /// Print the Rope, meant for debugging reasons.
    pub fn print(self: Rope) void {
        self.root.print(0);
    }

    // Gets the Rope value in a range.
    // Caller is responsible for freeing the result.
    pub fn getValueRange(self: *Rope, start: usize, end: usize) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        try self.root.getValueRange(&buffer, start, end);
        const result = try buffer.toOwnedSlice();
        return result;
    }

    /// Get the whole Rope value
    pub fn getValue(self: *Rope) ![]const u8 {
        return try self.getValueRange(0, self.root.full_size);
    }
};

const Node = struct {
    value: ?[]const u8,
    size: usize,
    full_size: usize,
    left: ?*Node,
    right: ?*Node,
    is_leaf: bool,

    /// Creates a Leaf Node from a String
    fn fromString(string: []const u8) Node {
        return .{
            .value = string,
            .size = string.len,
            .full_size = string.len,
            .left = null,
            .right = null,
            .is_leaf = true,
        };
    }

    /// Deinits the Node an all its children
    fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        if (!self.is_leaf) {
            if (self.left) |left| {
                left.deinit(allocator);
            }
            if (self.right) |right| {
                right.deinit(allocator);
            }
        }
        allocator.destroy(self);
    }

    /// Joins the Node with another one.
    fn join(self: *Node, allocator: std.mem.Allocator, other: Node) !void {
        if (!self.is_leaf) {
            if (self.right == null) {
                const right = try allocator.create(Node);
                right.* = other;
                self.right = right;
                return;
            }
        }

        const size = self.full_size;
        const full_size = self.full_size + other.full_size;

        const left = try allocator.create(Node);
        const right = try allocator.create(Node);

        left.* = self.*;
        right.* = other;
        self.* = Node{
            .left = left,
            .right = right,
            .size = size,
            .full_size = full_size,
            .is_leaf = false,
            .value = null,
        };
    }

    fn split(self: *Node, allocator: std.mem.Allocator, pos: usize) !struct { ?*Node, ?*Node } {
        if (self.is_leaf) {
            if (pos == 0) {
                return .{
                    null,
                    self,
                };
            }
            if (pos == self.size) {
                return .{
                    self,
                    null,
                };
            }

            const left_content, const right_content = blk: {
                if (self.value) |value| {
                    break :blk .{ value[0..pos], value[pos..] };
                } else {
                    break :blk .{ "", "" };
                }
            };

            const left = try allocator.create(Node);
            const right = try allocator.create(Node);
            left.* = Node.fromString(left_content);
            right.* = Node.fromString(right_content);

            return .{ left, right };
        } else {
            // TODO I think bugged code is here, the leaves are built back in the wrong order.
            // In the first case I have to use our left as base
            if (pos >= self.size) {
                if (self.right) |right| {
                    const new_left, const new_right = try right.split(allocator, pos - self.size);
                    // TODO we have multiple problems here:
                    // the join is backwards
                    // how do we deal with all the possible combinations?
                    // what about memory?
                    if (self.left) |left| {
                        if (new_left) |nl|
                            try nl.join(allocator, left.*);
                    }
                    return .{ new_left, new_right };
                } else {
                    return error.OutOfBounds;
                }
            } else {
                if (self.left) |left| {
                    const new_left, const new_right = try left.split(allocator, pos);
                    if (self.right) |right| {
                        if (new_right) |nr|
                            try nr.join(allocator, right.*);
                    }
                    return .{ new_left, new_right };
                } else {
                    return error.OutOfBounds;
                }
            }
        }
    }

    /// Saves in the buffer the value of the Node in the given range.
    fn getValueRange(self: Node, buffer: *std.ArrayList(u8), start: usize, end: usize) !void {
        if (self.is_leaf) {
            const len = end - start;
            if (start < self.size and len <= self.size) {
                if (self.value) |value| {
                    try buffer.appendSlice(value[start..end]);
                } else {
                    // TODO should this error?
                    try buffer.appendSlice("");
                }
            }
        } else {
            const len = end - start;
            if (len <= self.size) {
                if (self.left) |left| {
                    try left.getValueRange(buffer, start, end);
                }
            } else {
                if (self.left) |left| {
                    try left.getValueRange(buffer, start, self.size);
                }
                if (self.right) |right| {
                    try right.getValueRange(buffer, 0, len - self.size);
                }
            }
        }
    }

    fn printSpaces(depth: usize) void {
        for (0..depth) |_| {
            std.debug.print(" ", .{});
        }
    }

    /// Print the tree for debugging reasons.
    fn print(self: Node, depth: usize) void {
        printSpaces(depth);

        if (self.is_leaf) {
            std.debug.print("({}) {s}\n", .{ self.size, self.value orelse "" });
        } else {
            std.debug.print("({}|{}):\n", .{ self.size, self.full_size });
            if (self.left) |left| {
                printSpaces(depth);
                std.debug.print("L:\n", .{});
                left.print(depth + 1);
            }

            if (self.right) |right| {
                printSpaces(depth);
                std.debug.print("R:\n", .{});
                right.print(depth + 1);
            }
        }
    }
};

test "Rope" {
    const allocator = std.testing.allocator;
    // Initialize a Rope
    {
        var rope = try Rope.init(allocator, "Hello");
        defer rope.deinit();

        const result = try rope.getValue();
        defer allocator.free(result);

        try std.testing.expectEqualStrings("Hello", result);
    }
    // Joining and splitting Nodes
    {
        var node = try allocator.create(Node);
        node.* = Node.fromString("Hello");
        try node.join(allocator, Node.fromString(" World!"));

        const left, const right = try node.split(allocator, 7);

        std.debug.print("\nSTART===\n", .{});
        node.print(0);
        std.debug.print("\nLEFT===\n", .{});
        if (left) |l|
            l.print(0);

        std.debug.print("\nRIGHT===\n", .{});
        if (right) |r|
            r.print(0);
        std.debug.print("\n===\n", .{});
        defer node.deinit(allocator);
        defer left.?.deinit(allocator);
        defer right.?.deinit(allocator);
    }
    // Splitting a Node
    // {
    //     var leaf_1 = try allocator.create(Node);
    //     leaf_1.* = Node.fromString("Hello_");
    //     try leaf_1.join(allocator, Node.fromString("my_"));

    //     var leaf_2 = Node.fromString("na");
    //     try leaf_2.join(allocator, Node.fromString("me_i"));

    //     var leaf_3 = Node.fromString("s");
    //     try leaf_3.join(allocator, Node.fromString("_Simon"));

    //     try leaf_2.join(allocator, leaf_3);
    //     try leaf_1.join(allocator, leaf_2);

    //     defer leaf_1.deinit(allocator);

    //     // leaf_1.print(0);
    //     const left, const right = try leaf_1.split(allocator, 12);

    //     if (left) |l| {
    //         l.print(0);
    //     }
    //     if (right) |r| {
    //         r.print(0);
    //     }
    // }
}
