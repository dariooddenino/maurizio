const std = @import("std");

const Allocator = std.mem.Allocator;

/// The maximum size a leaf can reach.
const MAX_LEAF_SIZE: usize = 10;
/// The L/R imbalance ratio that triggers a rebalace operation.
/// NOTE: Since I'm always basically growing on the right, I don't think this works very well.
const REBALANCE_RATIO: f32 = 3;

const Node = struct {
    value: ?[]const u8,
    size: usize,
    full_size: usize,
    depth: usize,
    left: ?*Node,
    right: ?*Node,
    is_leaf: bool,

    fn deinit(self: *Node, allocator: Allocator) void {
        if (self.left) |left| {
            left.deinit(allocator);
        }
        if (self.right) |right| {
            right.deinit(allocator);
        }

        allocator.destroy(self);
    }

    fn createLeaf(allocator: Allocator, max_leaf_size: usize, text: []const u8) !*Node {
        if (text.len > max_leaf_size) {
            unreachable;
        }

        const node = try allocator.create(Node);

        node.* = .{
            .value = text,
            .size = text.len,
            .full_size = text.len,
            .depth = 1,
            .left = null,
            .right = null,
            .is_leaf = true,
        };

        return node;
    }

    fn createBranch(allocator: Allocator, left: *Node, right: *Node) !*Node {
        const node = try allocator.create(Node);

        node.* = .{
            .value = null,
            .size = left.full_size,
            .full_size = left.full_size + right.full_size,
            .depth = @max(left.depth, right.depth) + 1,
            .left = left,
            .right = right,
            .is_leaf = false,
        };

        return node;
    }

    /// TODO I think this can be a more general operation?
    /// i.e. this is just insert.
    fn fromText(allocator: Allocator, max_leaf_size: usize, text: []const u8) !*Node {
        if (text.len > max_leaf_size) {
            const mid_point: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(text.len)) / 2));
            const left_text = text[0..mid_point];
            const right_text = text[mid_point..];
            const left = try Node.fromText(allocator, max_leaf_size, left_text);
            const right = try Node.fromText(allocator, max_leaf_size, right_text);

            return try createBranch(allocator, left, right);
        } else {
            return try createLeaf(allocator, max_leaf_size, text);
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

    /// Gets the balance ratio of the Node
    fn getBalance(self: Node) f32 {
        if (self.is_leaf) {
            return 1;
        } else {
            var left_depth: usize = 1;
            var right_depth: usize = 1;
            if (self.left) |left| {
                left_depth = left.depth;
            }
            if (self.right) |right| {
                right_depth = right.depth;
            }

            return @as(f32, @floatFromInt(@max(left_depth, right_depth))) / @as(f32, @floatFromInt(@min(left_depth, right_depth)));
        }
    }

    /// Checks whether the Node is unbalanced
    fn isUnbalanced(self: Node, rebalance_ratio: f32) bool {
        return self.getBalance() > rebalance_ratio;
    }

    /// Saves in the buffer the whole value of the node
    fn getValue(self: Node, buffer: *std.ArrayList(u8)) !void {
        try self.getValueRange(buffer, 0, self.full_size);
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
            std.debug.print("({}|{}|{}):\n", .{ self.size, self.full_size, self.depth });
            if (self.left) |left| {
                printSpaces(depth);
                std.debug.print("L({*}):\n", .{left});
                left.print(depth + 1);
            }

            if (self.right) |right| {
                printSpaces(depth);
                std.debug.print("R({*}):\n", .{right});
                right.print(depth + 1);
            }
        }
    }
};

test "Creating a balanced Node" {
    const allocator = std.testing.allocator;

    const long_text = "Hello, Maurizio! The best text editor in the world.";

    const node = try Node.fromText(allocator, 10, long_text);
    defer node.deinit(allocator);

    // node.print(0);

    var value = std.ArrayList(u8).init(allocator);
    defer value.deinit();
    try node.getValue(&value);

    try std.testing.expectEqualStrings(long_text, value.items);
    try std.testing.expectEqual(1, node.getBalance());
}

test "Catch an unbalanced Node" {
    const allocator = std.testing.allocator;

    const leaf1 = try Node.fromText(allocator, 10, "Hello");
    const leaf2 = try Node.fromText(allocator, 10, "Hello");
    const leaf3 = try Node.fromText(allocator, 10, "Hello");

    const right = try Node.createBranch(allocator, leaf2, leaf3);

    const root = try Node.createBranch(allocator, leaf1, right);
    defer root.deinit(allocator);

    // root.print(0);

    try std.testing.expectEqual(2, root.getBalance());
    try std.testing.expect(root.isUnbalanced(1.5));
}
