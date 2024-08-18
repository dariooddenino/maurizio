const std = @import("std");

// TODOS
// delete op
// rebalance op (join, split, delete... ?)
// - max leaf size
// - load from file
// - fromString / fromStrings should return a pointer and take the allocator
// - maybe join shouldn't copy the original string?

// NOTES
// - full_size needs to be checked, how was it behaving before?
// - does split update sizes correctly?
// - persitency of the tree -> this will impact on how nodes are handled in memory
// - is this memory model correct?
// - In this regard, join and delete modify the original node, while other operations create clones. I need consistency

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

    /// Returns the character at the given index
    pub fn index(self: Rope, pos: usize) !u8 {
        return self.root.index(pos);
    }

    /// Deletes a range from the Rope
    pub fn delete(self: *Rope, pos: usize, len: usize) !void {
        const allocator = self.allocator;
        const left, const rest = try self.root.split(allocator, pos);
        var to_delete: ?*Node = null;
        var right: ?*Node = null;
        var new_root: ?*Node = null;
        if (rest) |rs| {
            to_delete, right = try rs.split(allocator, len);
        }
        if (to_delete) |td| {
            td.deinit(allocator);
        }

        // I think it shouldn't be possible to not have a left here, but to be sure...
        if (left) |l| {
            if (right) |r| {
                try l.join(allocator, r.*);
                defer r.deinit(allocator);
                new_root = l;
            }
        } else if (right) |r| {
            new_root = r;
        }

        if (new_root) |nr| {
            self.root.deinit(allocator);
            self.root = nr;
        }
    }

    /// Convenience function to prepend a string in the Rope
    pub fn prepend(self: *Rope, string: []const u8) !void {
        try self.insert(string, 0);
    }

    /// Convenience function to insert at the end of the string
    pub fn append(self: *Rope, string: []const u8) !void {
        try self.insert(string, self.root.size);
    }

    /// Inserts a String in the given position of the Rope
    /// NOTE: I'm not entirely sure if I'm inserting in the right place.
    /// NOTE: Also, I'm copying and redeleting the whole tree on an insert operation, not efficient for sure.
    pub fn insert(self: *Rope, string: []const u8, pos: usize) !void {
        const allocator = self.allocator;
        const left_split, const right_split = try self.root.split(allocator, pos);

        var new_root: *Node = undefined;
        if (left_split) |left| {
            new_root = left;
            try new_root.join(allocator, Node.fromString(string));
        } else {
            new_root = try allocator.create(Node);
            new_root.* = Node.fromString(string);
        }

        if (right_split) |right| {
            defer right.deinit(allocator);
            try new_root.join(allocator, right.*);
        }

        self.root.deinit(allocator);
        self.root = new_root;
    }

    /// Join a new Node into the Rope
    fn joinNode(self: *Rope, other: Node) !void {
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

    /// Clones the Node and all its children
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
                        copy_left.* = try left.clone(allocator);
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

    /// Returns the character at the given index
    fn index(self: Node, pos: usize) !u8 {
        if (self.is_leaf) {
            if (pos >= self.size)
                return error.OutOfBounds;

            return self.value.?[pos];
        } else {
            if (pos >= self.size) {
                if (self.right) |right| {
                    return right.index(pos - self.size);
                } else {
                    return error.OutOfBounds;
                }
            } else {
                if (self.left) |left| {
                    return left.index(pos);
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

test "Rope" {
    const allocator = std.testing.allocator;
    // Initialize a Rope
    // {
    //     var rope = try Rope.init(allocator, "Hello");
    //     defer rope.deinit();

    //     const result = try rope.getValue();
    //     defer allocator.free(result);

    //     try std.testing.expectEqualStrings("Hello", result);
    // }
    // Index
    // {
    //     var rope = try Rope.init(allocator, "Hello");
    //     defer rope.deinit();

    //     try rope.joinNode(Node.fromString(" World!"));

    //     const char = try rope.index(6);

    //     try std.testing.expectEqual(char, 'W');
    // }
    // Splitting Nodes on the right
    // {
    //     var node = try allocator.create(Node);
    //     node.* = try Node.fromStrings(allocator, "Hello", " World!");
    //     defer node.deinit(allocator);

    //     const left, const right = try node.split(allocator, 7);

    //     if (left) |l| {
    //         defer l.deinit(allocator);
    //         var expected_left = try allocator.create(Node);
    //         expected_left.* = try Node.fromStrings(allocator, "Hello", " W");
    //         defer expected_left.deinit(allocator);
    //         try std.testing.expect(l.isEqual(expected_left.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }

    //     if (right) |r| {
    //         defer r.deinit(allocator);
    //         var expected_right = try allocator.create(Node);
    //         expected_right.* = Node.fromString("orld!");
    //         defer expected_right.deinit(allocator);
    //         try std.testing.expect(r.isEqual(expected_right.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }
    // }
    // Splitting nodes on the left
    // {
    //     var node = try allocator.create(Node);
    //     node.* = try Node.fromStrings(allocator, "Hello", " World!");
    //     defer node.deinit(allocator);

    //     const left, const right = try node.split(allocator, 3);
    //     defer left.?.deinit(allocator);
    //     defer right.?.deinit(allocator);

    //     if (left) |l| {
    //         var expected_left = try allocator.create(Node);
    //         expected_left.* = Node.fromString("Hel");
    //         defer expected_left.deinit(allocator);
    //         try std.testing.expect(l.isEqual(expected_left.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }

    //     if (right) |r| {
    //         var expected_right = try allocator.create(Node);
    //         expected_right.* = try Node.fromStrings(allocator, "lo", " World!");
    //         defer expected_right.deinit(allocator);
    //         try std.testing.expect(r.isEqual(expected_right.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }
    // }
    // Testing clone
    // {
    //     var node = try allocator.create(Node);
    //     node.* = try Node.fromStrings(allocator, "Hello", " World!");
    //     defer node.deinit(allocator);
    //     var clone = try allocator.create(Node);
    //     clone.* = try node.clone(allocator);
    //     defer clone.deinit(allocator);

    //     try std.testing.expect(node.isEqual(clone.*));
    // }
    // Bigger tree split
    // {
    //     var node_1 = try allocator.create(Node);
    //     node_1.* = try Node.fromStrings(allocator, "Hello_", "my_");
    //     defer node_1.deinit(allocator);

    //     var node_2 = try allocator.create(Node);
    //     node_2.* = try Node.fromStrings(allocator, "na", "me_i");
    //     defer node_2.deinit(allocator);

    //     var node_3 = try allocator.create(Node);
    //     node_3.* = try Node.fromStrings(allocator, "s", "_Simon");
    //     defer node_3.deinit(allocator);

    //     try node_2.join(allocator, node_3.*);
    //     try node_1.join(allocator, node_2.*);

    //     const left, const right = try node_1.split(allocator, 11);

    //     if (left) |l| {
    //         defer l.deinit(allocator);
    //         // TODO should test this as well?
    //         // var expected_left = try allocator.create(Node);
    //         // expected_left.* = Node.fromString("Hel");
    //         // defer expected_left.deinit(allocator);
    //         // try std.testing.expect(l.isEqual(expected_left.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }

    //     if (right) |r| {
    //         defer r.deinit(allocator);
    //         var expected_right = try allocator.create(Node);
    //         defer expected_right.deinit(allocator);
    //         var right_right = try allocator.create(Node);
    //         right_right.* = try Node.fromStrings(allocator, "s", "_Simon");
    //         defer right_right.deinit(allocator);
    //         expected_right.* = Node.fromString("me_i");
    //         try expected_right.join(allocator, right_right.*);
    //         try std.testing.expect(r.isEqual(expected_right.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }
    // }
    // Bigger tree split middle of leaf
    // {
    //     var node_1 = try allocator.create(Node);
    //     node_1.* = try Node.fromStrings(allocator, "Hello_", "my_");
    //     defer node_1.deinit(allocator);

    //     var node_2 = try allocator.create(Node);
    //     node_2.* = try Node.fromStrings(allocator, "na", "me_i");
    //     defer node_2.deinit(allocator);

    //     var node_3 = try allocator.create(Node);
    //     node_3.* = try Node.fromStrings(allocator, "s", "_Simon");
    //     defer node_3.deinit(allocator);

    //     try node_2.join(allocator, node_3.*);
    //     try node_1.join(allocator, node_2.*);

    //     const left, const right = try node_1.split(allocator, 12);

    //     if (left) |l| {
    //         defer l.deinit(allocator);
    //         // TODO should test this as well?
    //         // var expected_left = try allocator.create(Node);
    //         // expected_left.* = Node.fromString("Hel");
    //         // defer expected_left.deinit(allocator);
    //         // try std.testing.expect(l.isEqual(expected_left.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }

    //     if (right) |r| {
    //         defer r.deinit(allocator);
    //         var expected_right = try allocator.create(Node);
    //         defer expected_right.deinit(allocator);
    //         var right_right = try allocator.create(Node);
    //         right_right.* = try Node.fromStrings(allocator, "s", "_Simon");
    //         defer right_right.deinit(allocator);
    //         expected_right.* = Node.fromString("e_i");
    //         try expected_right.join(allocator, right_right.*);
    //         try std.testing.expect(r.isEqual(expected_right.*));
    //     } else {
    //         // NOTE print a custom message?
    //         try std.testing.expect(false);
    //     }
    // }
    // Inserting into position 0
    // {
    //     var rope = try Rope.init(allocator, "World!");
    //     defer rope.deinit();
    //     try rope.insert("Hello ", 0);

    //     var expected = try allocator.create(Node);
    //     expected.* = try Node.fromStrings(allocator, "Hello ", "World!");
    //     defer expected.deinit(allocator);

    //     try std.testing.expect(rope.root.isEqual(expected.*));
    // }
    // Inserting into last position
    // {
    //     var rope = try Rope.init(allocator, "Hello ");
    //     defer rope.deinit();
    //     try rope.insert("World!", 6);

    //     var expected = try allocator.create(Node);
    //     expected.* = try Node.fromStrings(allocator, "Hello ", "World!");
    //     defer expected.deinit(allocator);

    //     try std.testing.expect(rope.root.isEqual(expected.*));
    // }
    // Inserting in the middle of a big tree
    // {
    //     var node_1 = try allocator.create(Node);
    //     node_1.* = try Node.fromStrings(allocator, "Hello_", "my_");
    //     // defer node_1.deinit(allocator);

    //     var node_2 = try allocator.create(Node);
    //     node_2.* = try Node.fromStrings(allocator, "na", "me_i");
    //     defer node_2.deinit(allocator);

    //     var node_3 = try allocator.create(Node);
    //     node_3.* = try Node.fromStrings(allocator, "s", "_Simon");
    //     defer node_3.deinit(allocator);

    //     try node_2.join(allocator, node_3.*);
    //     try node_1.join(allocator, node_2.*);

    //     var rope = Rope{ .root = node_1, .allocator = allocator };

    //     try rope.insert("new_", 9);
    //     defer rope.deinit();

    //     const result = try rope.getValue();
    //     defer allocator.free(result);

    //     // Lazy test
    //     try std.testing.expectEqualStrings(result, "Hello_my_new_name_is_Simon");
    // }
    // Appending
    // {
    //     var rope = try Rope.init(allocator, "Hello");
    //     try rope.append(" World");
    //     defer rope.deinit();

    //     var expected = try allocator.create(Node);
    //     expected.* = try Node.fromStrings(allocator, "Hello", " World");
    //     defer expected.deinit(allocator);

    //     try std.testing.expect(rope.root.isEqual(expected.*));
    // }
    // Deleting a simple tree
    {
        var rope = try Rope.init(allocator, "Hello");
        try rope.append(" World");
        defer rope.deinit();

        try rope.delete(3, 7);

        rope.print();
    }
    // Deleting
    // {
    //     var node_1 = try allocator.create(Node);
    //     node_1.* = try Node.fromStrings(allocator, "Hello_", "my_");
    //     // defer node_1.deinit(allocator);

    //     var node_2 = try allocator.create(Node);
    //     node_2.* = try Node.fromStrings(allocator, "na", "me_i");
    //     defer node_2.deinit(allocator);

    //     var node_3 = try allocator.create(Node);
    //     node_3.* = try Node.fromStrings(allocator, "s", "_Simon");
    //     defer node_3.deinit(allocator);

    //     try node_2.join(allocator, node_3.*);
    //     try node_1.join(allocator, node_2.*);

    //     var rope = Rope{ .root = node_1, .allocator = allocator };
    //     defer rope.deinit();

    //     try rope.delete(3, 7);

    //     const result = try rope.getValue();
    //     defer allocator.free(result);

    //     try std.testing.expectEqualStrings(result, "Helame_is_Simon");
    // }
}
