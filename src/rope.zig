const std = @import("std");

// TODO move inside Node?
const Branch = struct {
    left: ?*Node,
    right: ?*Node,
    // Size of left subtree
    size: usize,

    /// Get the value in a given range.
    fn getValueRange(self: Branch, start: usize, end: usize) ?[]const u8 {
        const len = end - start + 1;
        if (len <= self.size)
            return self.left.?.getValueRange(start, end);

        const l = self.left.?.getValueRange(start, self.size - 1);
        // const r = self.right.?.getValueRange(0, len - self.size - 1);

        // TODO I need an allocator to combine these two...
        return l;
    }

    /// Get the whole value of the Branch.
    fn getValue(self: Branch) ?[]const u8 {
        return self.getValueRange(0, self.size);
    }
};

const Leaf = struct {
    value: []const u8,
    // Size of leaf
    size: usize,

    fn new(val: []const u8) Node {
        return .{ .leaf = .{
            .value = val,
            .size = val.len,
        } };
    }

    /// Get the value in a given range.
    /// NOTE Not sure about the return type.
    fn getValueRange(self: Leaf, start: usize, end: usize) ?[]const u8 {
        const len = end - start + 1;
        if (start < self.size and len <= self.size)
            return self.value[start..len];

        return null;
    }

    /// Get the whole value of the Leaf.
    fn getValue(self: Leaf) ?[]const u8 {
        return self.getValueRange(0, self.size - 1);
    }
};

const Node = union(enum) {
    branch: Branch,
    leaf: Leaf,

    fn getValueRange(self: Node, start: usize, end: usize) ?[]const u8 {
        switch (self) {
            inline else => |node| return node.getValueRange(start, end),
        }
    }

    fn getValue(self: Node) ?[]const u8 {
        switch (self) {
            inline else => |node| return node.getValue(),
        }
    }

    fn getSize(self: Node) usize {
        switch (self) {
            inline else => |node| return node.size,
        }
    }

    fn update(self: *Node) void {
        self.size = self.left.?.getSize() + self.right.?.getSize() + 1;
    }

    // TODO this needs an allocator as well, I'll probably have to move these operations out of here
    fn join(left: Node, right: Node) Node {
        return Node{ .branch = Branch{
            .left = left,
            .right = right,
            .size = left.getSize(),
        } };
    }

    fn split(self: *Node, pos: usize) !struct { Node, Node } {
        return switch (self.*) {
            .branch => |branch| {
                // We are splitting the left branch
                if (pos < branch.size) {
                    if (branch.left) |left| {
                        const new_left, const new_right = try left.split(pos);
                        // TODO r ropejoin new_right and self.right
                        return .{ new_left, new_right };
                    } else {
                        return error.OutOfBounds;
                    }
                } else {
                    if (branch.right) |right| {
                        const new_left, const new_right = try right.split(pos - branch.size);
                        // l ropejoin new_left self.right
                        return .{ new_left, new_right };
                    } else {
                        return error.OutOfBounds;
                    }
                }
            },
            .leaf => |leaf| {
                if (pos >= leaf.size)
                    return error.OutOfBounds;

                if (pos == 0)
                    return .{ Leaf.new(""), Leaf.new(leaf.value) };

                const left = leaf.value[0..pos];
                const right = leaf.value[pos..];

                return .{ Leaf.new(left), Leaf.new(right) };
            },
        };
    }

    fn newLeaf(val: []const u8) Node {
        return .{ .leaf = .{
            .value = val,
            .size = val.len,
        } };
    }
};

test "Node" {
    // A Leaf reports its value
    {
        var leaf = Node.newLeaf("Hello");

        try std.testing.expectEqualStrings("Hello", leaf.getValue() orelse unreachable);
    }
    // We can extract a substring from a string
    {
        var leaf = Node.newLeaf("Hello");

        try std.testing.expectEqualStrings("ello", leaf.getValueRange(1, 5) orelse unreachable);
    }

    // A Leaf splits correctly at index 0
    {
        var leaf: Node = Node.newLeaf("Hello");
        const left, const right = try leaf.split(0);

        try std.testing.expectEqualStrings("", left.leaf.value);
        try std.testing.expectEqualStrings("Hello", right.leaf.value);
    }
    // A Leaf splits correctly at the last position
    {
        var leaf: Node = Node.newLeaf("Hello");
        const left, const right = try leaf.split(4);

        try std.testing.expectEqualStrings("Hell", left.leaf.value);
        try std.testing.expectEqualStrings("o", right.leaf.value);
    }
    // We can join to Leaves into a Node and print the result
    {
        const leaf1: Node = Node.newLeaf("Hello");
        const leaf2: Node = Node.newLeaf(", World!");
        const node = Node.join(leaf1, leaf2);

        try std.testing.expectEqualStrings("Hello, World!", node.getValue() orelse unreachable);
    }
}

pub fn Rope() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        root: ?*Node,

        /// Initialize an empty Rope.
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .root = null,
            };
        }

        /// Create a Rope from a Node.
        /// NOTE I will have to think on how to deal memory here.
        fn fromNode(allocator: std.mem.Allocator, node: *Node) !Self {
            return Self{
                .allocator = allocator,
                .root = node,
            };
        }

        /// Create a Rope from a String.
        /// NOTE Might need this for initial tests only
        fn fromString(allocator: std.mem.Allocator, string: []const u8) !Self {
            var rope = Self{
                .allocator = allocator,
                .root = null,
            };

            const leaf: *Node = try rope.newLeaf(string);
            rope.root = leaf;

            return rope;
        }

        /// Erase the element at the given position
        // pub fn erase(self: *Self, pos: usize) !void {
        //     if (pos >= self.size())
        //         return error.OutOfBounds;

        //     self.eraseRange(pos, 1);
        // }

        // pub fn eraseRange(self: *Self, pos: usize, cnt: usize) !void {
        //     if (pos + cnt > self.getSize())
        //         return error.OutOfBounds;

        // }

        pub fn deinit(self: *Self) void {
            self.deinitNode(self.root);
        }

        /// Create a new Leaf for the Rope
        fn newLeaf(self: Self, string: []const u8) !*Node {
            const leaf = try self.allocator.create(Node);
            leaf.* = Node{
                .leaf = .{
                    .value = string,
                    .size = string.len,
                },
            };

            return leaf;
        }

        /// Insert a string at a given position in the rope.
        // pub fn insert(self: *Self, pos: usize, value: []const u8) !void {
        //     if (pos > self.size()) {
        //         // return en error
        //         return error.OutOfBounds;
        //     }

        //     if (self.root) {
        //         try insertInNode(self.root, pos, value);
        //     }
        // }

        /// Insert a string in the Node at the given position.
        // fn insertInNode(node: *Node, pos: usize, value: []const u8) !void {
        //     const p = split(node, pos);
        //     var left = p.left;
        //     var right = p.right;
        //     var new_node = createNode(value);
        //     var left_merge_result = merge(left, new_node);
        //     return merge(left_merge_result, right);
        // }

        /// Split a Rope at the given position.
        /// NOTE Do I have to clean up here afterwards??
        // fn split(self: *Self, pos: usize) !struct { Self, Self } {
        //     const left, const right = try self.splitNode(self.root, pos);
        //     // TODO Is this enough? Do I have to free something?
        //     self.root = null;
        //     const left_rope = try fromNode(self.allocator, left);
        //     const right_rope = try fromNode(self.allocator, right);
        //     return .{ left_rope, right_rope };
        // }

        /// Split a Node at the given position
        /// NOTE also need to handle the result somehow
        /// NOTE A bit awkward, maybe it should just have the allocator passed as an arg?
        // fn splitNode(self: *Self, m_node: ?*Node, pos: usize) !struct { Node, Node } {
        //     if (m_node) |node| {
        //         switch (node.*) {
        //             // We are splitting a leaf
        //             .leaf => |leaf| {
        //                 // Something went wrong here.
        //                 // NOTE maybe handle in a more graceful way
        //                 if (pos >= leaf.size) {
        //                     return error.OutOfBounds;
        //                 }
        //             },
        //             .branch => |branch| {
        //                 const left_size = node.left.getSize();
        //                 if (left_size >= pos) {} else {}
        //             },
        //         }
        //         // const left_size = node.left.getSize();
        //         // if (left_size >= pos) {
        //         //     const p = splitNode(node.left, pos);
        //         //     node.left = p.right;
        //         //     node.update();
        //         //     return .{ p.left, node };
        //         // } else {
        //         //     const p = splitNode(node.right, pos - left_size - 1);
        //         //     node.right = p.left;
        //         //     node.update();
        //         //     return .{ node, p.right };
        //         // }
        //     }
        // }

        fn deinitNode(self: *Self, m_node: ?*Node) void {
            if (m_node) |node| {
                switch (node.*) {
                    .leaf => {},
                    .branch => |branch| {
                        if (branch.left) |left| {
                            self.deinitNode(left);
                        }
                        if (branch.right) |right| {
                            self.deinitNode(right);
                        }
                    },
                }
                self.allocator.destroy(node);
            }
        }

        /// Returns the size of the tree.
        fn size(self: Self) usize {
            return if (self.root) |node| node.getSize() else 0;
        }

        /// Sets the given node as the new root.
        /// NOTE copying here, possible performance problem
        fn setRoot(self: *Self, node: Node) void {
            self.root.* = node;
        }
    };
}

test "rope" {
    // Size of an empty Rope should be 0
    {
        var rope = Rope().init(std.testing.allocator);
        defer rope.deinit();

        try std.testing.expectEqual(@as(usize, 0), rope.size());
    }

    // Create a Rope from a String, the size should be correct
    {
        var rope = try Rope().fromString(std.testing.allocator, "Maurizio");
        defer rope.deinit();

        try std.testing.expectEqual(@as(usize, 8), rope.size());
    }

    // Splitting a Rope should yield the correct result.
    // {
    //     var rope = try Rope().fromString(std.testing.allocator, "Maurizio");
    //     defer rope.deinit();

    //     var split_rope = try rope.split(2);
    //     defer split_rope[0].deinit();
    //     defer split_rope[1].deinit();

    //     try std.testing.expectEqual(@as(usize, 2), split_rope[0].size());
    //     try std.testing.expectEqual(@as(usize, 6), split_rope[1].size());
    // }
}
