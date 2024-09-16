const std = @import("std");

const Allocator = std.mem.Allocator;

// TODO
// - use a config object

/// The maximum size a leaf can reach.
const MAX_LEAF_SIZE: usize = 10;
/// The L/R imbalance ratio that triggers a rebalace operation.
const REBALANCE_RATIO: f32 = 1.2;

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

    /// Inserts a string at the given position
    // pub fn insert(self: *Node, allocator: Allocator, max_leaf_size: usize, pos: usize, text: []const u8) !void {
    // }

    fn clone(self: Node, allocator: std.mem.Allocator) !Node {
        var result = self;
        if (self.left) |left| {
            const new_left = try allocator.create(Node);
            new_left.* = try left.clone(allocator);
            result.left = new_left;
        }
        if (self.right) |right| {
            const new_right = try allocator.create(Node);
            new_right.* = try right.clone(allocator);
            result.right = new_right;
        }

        return result;
    }

    /// Joins the Node with another one.
    fn join(self: *Node, allocator: std.mem.Allocator, original_other: Node) !void {
        const other = try original_other.clone(allocator);
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
            .depth = @max(left.depth, other.depth) + 1,
        };
    }

    /// Splits the node at the given position.
    /// NOTE: what did I mean with "the original one is left untouched?"
    /// I might have to look into the fact that I'm cloning the nodes, is it really needed?
    fn split(self: *Node, allocator: std.mem.Allocator, max_leaf_size: usize, pos: usize) !struct { ?*Node, ?*Node } {
        if (self.is_leaf) {
            if (pos == 0) {
                const leaf = try allocator.create(Node);
                leaf.* = self.*;
                return .{
                    null,
                    leaf,
                };
            }
            if (pos == self.size) {
                const leaf = try allocator.create(Node);
                leaf.* = self.*;
                return .{
                    leaf,
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

            const left = try Node.createLeaf(allocator, max_leaf_size, left_content);
            const right = try Node.createLeaf(allocator, max_leaf_size, right_content);

            return .{ left, right };
        } else {
            if (pos >= self.size) {
                if (self.right) |right| {
                    const split_left, const split_right = try right.split(allocator, max_leaf_size, pos - self.size);
                    if (self.left) |left| {
                        const copy_left = try allocator.create(Node);
                        copy_left.* = try left.clone(allocator);
                        if (split_left) |sl| {
                            defer sl.deinit(allocator);
                            try copy_left.join(allocator, sl.*);
                            return .{ copy_left, split_right };
                        } else {
                            return .{ copy_left, split_right };
                        }
                    } else if (split_left) |sl| {
                        // If there was no left (possible?) we just add the split as the new left.
                        return .{ sl, split_right };
                    } else {
                        unreachable;
                    }
                } else {
                    return error.OutOfBounds;
                }
            } else {
                if (self.left) |left| {
                    const split_left, const split_right = try left.split(allocator, max_leaf_size, pos);
                    if (self.right) |right| {
                        const copy_right = try allocator.create(Node);
                        copy_right.* = try right.clone(allocator);
                        if (split_right) |sr| {
                            defer copy_right.deinit(allocator);
                            try sr.join(allocator, copy_right.*);
                            return .{ split_left, sr };
                        } else {
                            return .{ split_left, copy_right };
                        }
                    } else if (split_right) |sr| {
                        return .{ split_left, sr };
                    } else {
                        unreachable;
                    }
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
    /// A certain depth is needed before the check is performed.
    fn isUnbalanced(self: Node, rebalance_ratio: f32) bool {
        return self.depth > 4 and self.getBalance() > rebalance_ratio;
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

// TODO I need more depth in this tree to trigger the unbalance check
test "Catch an unbalanced Node" {
    const allocator = std.testing.allocator;

    const leaf1 = try Node.fromText(allocator, 10, "Hello");
    const leaf2 = try Node.fromText(allocator, 10, "Hello");
    const leaf3 = try Node.fromText(allocator, 10, "Hello");
    const leaf4 = try Node.fromText(allocator, 10, "Hello");
    const leaf5 = try Node.fromText(allocator, 10, "Hello");
    const leaf6 = try Node.fromText(allocator, 10, "Hello");

    const right = try Node.createBranch(allocator, leaf2, leaf3);
    const right2 = try Node.createBranch(allocator, leaf1, right);
    const right3 = try Node.createBranch(allocator, leaf4, right2);
    const right4 = try Node.createBranch(allocator, leaf5, right3);

    const root = try Node.createBranch(allocator, leaf6, right4);
    defer root.deinit(allocator);

    // root.print(0);

    try std.testing.expectEqual(5, root.getBalance());
    try std.testing.expect(root.isUnbalanced(3));
}

test "Splitting and rejoining a Node" {
    const allocator = std.testing.allocator;

    const text = "Hello, from Maurizio!";
    const node = try Node.fromText(allocator, 10, text);
    defer node.deinit(allocator);

    const left, const right = try node.split(allocator, 10, 8);
    if (left) |l| {
        if (right) |r| {
            // TODO check that this works fine
            // TODO do I have to update any depth when splitting (I think not)
            // TODO what about the fact that I'm cloning the nodes?
            // l.print(0);
            try l.join(allocator, r.*);
            defer l.deinit(allocator);
            defer r.deinit(allocator);
            // r.print(0);

            l.print(0);

            var value = std.ArrayList(u8).init(allocator);
            defer value.deinit();
            try l.getValue(&value);

            try std.testing.expectEqualStrings(text, value.items);
            return;
        }
    }
    unreachable;
}
