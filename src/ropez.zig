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

    /// Create a branch Node from two strings.
    fn fromStrings(allocator: std.mem.Allocator, left_string: []const u8, right_string: []const u8) !Node {
        const left = try allocator.create(Node);
        const right = try allocator.create(Node);

        left.* = Node.fromString(left_string);
        right.* = Node.fromString(right_string);

        return .{
            .value = null,
            .size = left.size,
            .full_size = left.size + right.size,
            .left = left,
            .right = right,
            .is_leaf = false,
        };
    }

    /// Deinits the Node an all its children
    fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        // std.debug.print("\n\nDEINIT: {any}\n\n", .{self});
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

    /// Splits the node. The original one is left untouched.
    fn split(self: *Node, allocator: std.mem.Allocator, pos: usize) !struct { ?*Node, ?*Node } {
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

            const left = try allocator.create(Node);
            const right = try allocator.create(Node);
            left.* = Node.fromString(left_content);
            right.* = Node.fromString(right_content);

            return .{ left, right };
        } else {
            if (pos >= self.size) {
                if (self.right) |right| {
                    const split_left, const split_right = try right.split(allocator, pos - self.size);
                    // If only one of the two, we set it as left
                    // If both are there we join on the original left
                    // NOTE this is ugly and possibly redundant
                    if (self.left) |left| {
                        const copy_left = try allocator.create(Node);
                        copy_left.* = left.*;
                        if (split_left) |sl| {
                            defer sl.deinit(allocator);
                            try copy_left.join(allocator, sl.*);
                            return .{ copy_left, split_right };
                        } else {
                            return .{ copy_left, split_right };
                        }
                    } else if (split_left) |sl| {
                        // Here left must be null
                        return .{ sl, split_right };
                    } else {
                        // NOTE: I don't think this is can be reached.
                        return error.OutOfBounds;
                    }
                } else {
                    return error.OutOfBounds;
                }
            } else {
                if (self.left) |left| {
                    const split_left, const split_right = try left.split(allocator, pos);
                    if (self.right) |right| {
                        const copy_right = try allocator.create(Node);
                        copy_right.* = right.*;
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
                        // NOTE: I don't think this can be reached.
                        return error.OutOfBounds;
                    }
                } else {
                    return error.OutOfBounds;
                }
            }
        }
    }

    /// A naive equality test to be used for testing.
    fn isEqual(self: Node, other: Node) bool {
        const equal_props = self.size == other.size and self.full_size == other.full_size and self.is_leaf == other.is_leaf;

        var equal_value = self.value == null and other.value == null;
        if (self.value) |value| {
            if (other.value) |other_value| {
                equal_value = std.mem.eql(u8, value, other_value);
            }
        }

        // True if both are null
        var left_equal = self.left == null and other.left == null;
        var right_equal = self.right == null and other.right == null;

        if (self.left) |left| {
            if (other.left) |other_left| {
                left_equal = left.isEqual(other_left.*);
            }
        }

        if (self.right) |right| {
            if (other.right) |other_right| {
                right_equal = right.isEqual(other_right.*);
            }
        }

        return equal_props and equal_value and left_equal and right_equal;
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
    // Splitting Nodes on the right
    {
        var node = try allocator.create(Node);
        node.* = try Node.fromStrings(allocator, "Hello", " World!");
        defer node.deinit(allocator);

        const left, const right = try node.split(allocator, 7);
        defer left.?.deinit(allocator);
        defer right.?.deinit(allocator);

        if (left) |l| {
            var expected_left = try allocator.create(Node);
            expected_left.* = try Node.fromStrings(allocator, "Hello", " W");
            defer expected_left.deinit(allocator);
            try std.testing.expect(l.isEqual(expected_left.*));
        } else {
            // NOTE print a custom message?
            try std.testing.expect(false);
        }

        if (right) |r| {
            var expected_right = try allocator.create(Node);
            expected_right.* = Node.fromString("orld!");
            defer expected_right.deinit(allocator);
            try std.testing.expect(r.isEqual(expected_right.*));
        } else {
            // NOTE print a custom message?
            try std.testing.expect(false);
        }
    }
    // Splitting nodes on the left
    {
        var node = try allocator.create(Node);
        node.* = try Node.fromStrings(allocator, "Hello", " World!");
        defer node.deinit(allocator);

        const left, const right = try node.split(allocator, 3);
        defer left.?.deinit(allocator);
        defer right.?.deinit(allocator);

        if (left) |l| {
            var expected_left = try allocator.create(Node);
            expected_left.* = Node.fromString("Hel");
            defer expected_left.deinit(allocator);
            try std.testing.expect(l.isEqual(expected_left.*));
        } else {
            // NOTE print a custom message?
            try std.testing.expect(false);
        }

        if (right) |r| {
            var expected_right = try allocator.create(Node);
            expected_right.* = try Node.fromStrings(allocator, "lo", " World!");
            defer expected_right.deinit(allocator);
            try std.testing.expect(r.isEqual(expected_right.*));
        } else {
            // NOTE print a custom message?
            try std.testing.expect(false);
        }
    }
    // Bigger tree split
    {
        var node_1 = try allocator.create(Node);
        node_1.* = try Node.fromStrings(allocator, "Hello_", "my_");
        defer node_1.deinit(allocator);

        var node_2 = try allocator.create(Node);
        node_2.* = try Node.fromStrings(allocator, "na", "me_i");
        defer allocator.destroy(node_2);

        const node_3 = try Node.fromStrings(allocator, "s", "_Simon");

        try node_2.join(allocator, node_3);
        try node_1.join(allocator, node_2.*);

        const left, const right = try node_1.split(allocator, 12);
        defer left.?.deinit(allocator);
        defer right.?.deinit(allocator);

        if (left) |l| {
            l.print(0);
            // var expected_left = try allocator.create(Node);
            // expected_left.* = Node.fromString("Hel");
            // defer expected_left.deinit(allocator);
            // try std.testing.expect(l.isEqual(expected_left.*));
        } else {
            // NOTE print a custom message?
            try std.testing.expect(false);
        }

        if (right) |r| {
            var expected_right = try allocator.create(Node);
            const right_right = try Node.fromStrings(allocator, "s", "_Simon");
            expected_right.* = Node.fromString("me_i");
            try expected_right.join(allocator, right_right);
            r.print(0);
            // expected_right.print(0);
            // defer expected_right.deinit(allocator);
            try std.testing.expect(r.isEqual(expected_right.*));
        } else {
            // NOTE print a custom message?
            try std.testing.expect(false);
        }
    }
}
