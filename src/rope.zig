const std = @import("std");

// I need to think better at the Rope API, and then design how I want to handle the primitives.
// Right now I'm lacking too much context.

// TODO remove allocator from Leaf
// TODO remove getValue, which is useless.
// TODO How do I get the whole value??
// TODO Node needs to deinit by itself
// TODO probably need to store allocator inside Node.
// TODO rope hold whole length

// TODO move inside Node?
const Branch = struct {
    left: ?*Node,
    right: ?*Node,
    // Size of left subtree
    size: usize,

    /// Get the value in a given range.
    fn getValueRange(self: Branch, allocator: std.mem.Allocator, start: usize, end: usize) error{OutOfMemory}!?[]const u8 {
        const len = end - start + 1;
        if (len <= self.size)
            return self.left.?.getValueRange(allocator, start, end);

        const left = try self.left.?.getValueRange(allocator, start, self.size - 1);
        const right = try self.right.?.getValueRange(allocator, 0, len - self.size - 1);

        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        if (left) |l|
            try buf.appendSlice(l);
        if (right) |r|
            try buf.appendSlice(r);

        const res = try buf.toOwnedSlice();

        return res;
    }

    // /// Get the whole value of the Branch.
    // fn getValue(self: Branch, allocator: std.mem.Allocator) error{OutOfMemory}!?[]const u8 {
    //     return try self.getValueRange(allocator, 0, self.size);
    // }
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
    fn getValueRange(self: Leaf, _: std.mem.Allocator, start: usize, end: usize) error{OutOfMemory}!?[]const u8 {
        const len = end - start + 1;
        if (start < self.size and len <= self.size)
            return self.value[start..len];

        return null;
    }

    // /// Get the whole value of the Leaf.
    // fn getValue(self: Leaf, allocator: std.mem.Allocator) error{OutOfMemory}!?[]const u8 {
    //     return try self.getValueRange(allocator, 0, self.size - 1);
    // }
};

const Node = union(enum) {
    branch: Branch,
    leaf: Leaf,

    fn getValueRange(self: Node, allocator: std.mem.Allocator, start: usize, end: usize) !?[]const u8 {
        switch (self) {
            inline else => |node| return try node.getValueRange(allocator, start, end),
        }
    }

    // fn getValue(self: Node, allocator: std.mem.Allocator) !?[]const u8 {
    //     switch (self) {
    //         .branch => |branch| return try branch.getValue(allocator),
    //         .leaf => |leaf| return try leaf.getValue(allocator),
    //     }
    // }

    fn getSize(self: Node) usize {
        switch (self) {
            inline else => |node| return node.size,
        }
    }

    fn update(self: *Node) void {
        self.size = self.left.?.getSize() + self.right.?.getSize() + 1;
    }

    // TODO this needs an allocator as well, I'll probably have to move these operations out of here
    fn join(allocator: std.mem.Allocator, left: Node, right: Node) !Node {
        const left_node = try allocator.create(Node);
        const right_node = try allocator.create(Node);

        left_node.* = left;
        right_node.* = right;

        return Node{ .branch = Branch{
            .left = left_node,
            .right = right_node,
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

    fn printSpaces(depth: usize) void {
        for (0..depth) |_| {
            std.debug.print(" ", .{});
        }
    }

    fn printNode(node: *Node, depth: usize) void {
        printSpaces(depth);

        switch (node.*) {
            .leaf => |leaf| std.debug.print("({}) {s}\n", .{ leaf.size, leaf.value }),
            .branch => |n| {
                std.debug.print("({}):\n", .{n.size});
                if (n.left) |left| {
                    printSpaces(depth);
                    std.debug.print("L:\n", .{});
                    printNode(left, depth + 1);
                }

                if (n.right) |right| {
                    printSpaces(depth);
                    std.debug.print("R:\n", .{});
                    printNode(right, depth + 1);
                }
            },
        }
    }
};

test "Node" {
    // A Leaf reports its value
    // {
    //     var leaf = Node.newLeaf("Hello");

    //     const result = try leaf.getValue(std.testing.allocator);

    //     try std.testing.expectEqualStrings("Hello", result orelse unreachable);
    // }

    // We can extract a substring from a string
    // {
    //     var leaf = Node.newLeaf("Hello");

    //     const result = try leaf.getValueRange(std.testing.allocator, 1, 5);

    //     try std.testing.expectEqualStrings("ello", result orelse unreachable);
    // }

    // A Leaf splits correctly at index 0
    // {
    //     var leaf: Node = Node.newLeaf("Hello");
    //     const left, const right = try leaf.split(0);

    //     try std.testing.expectEqualStrings("", left.leaf.value);
    //     try std.testing.expectEqualStrings("Hello", right.leaf.value);
    // }
    // A Leaf splits correctly at the last position
    // {
    //     var leaf: Node = Node.newLeaf("Hello");
    //     const left, const right = try leaf.split(4);

    //     try std.testing.expectEqualStrings("Hell", left.leaf.value);
    //     try std.testing.expectEqualStrings("o", right.leaf.value);
    // }
    // We can join to Leaves into a Node and print the result
    {
        const leaf1: Node = Node.newLeaf("Hello");
        const leaf2: Node = Node.newLeaf(", World!");

        const allocator = std.testing.allocator;

        var rope = Rope().init(allocator);
        defer rope.deinit();
        try rope.join(leaf1);
        try rope.join(leaf2);

        const result = try rope.getValueRange(allocator, 2, 6);

        // std.debug.print("RESU:LT {any}\n", .{result});

        try std.testing.expectEqualStrings("llo", result orelse unreachable);
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

        // TODO root could not be there... this approach doesn't work
        fn join(self: *Self, node: Node) !void {
            if (self.root) |root| {
                const new_root = try Node.join(self.allocator, root.*, node);
                self.root.* = new_root;
            } else {
                self.root.* = node;
            }
        }

        pub fn getValueRange(self: *Self, start: usize, end: usize) !?[]const u8 {
            if (self.root) |root| {
                return try root.getValueRange(self.allocator, start, end);
            }
            return null;
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
    // {
    //     var rope = Rope().init(std.testing.allocator);
    //     defer rope.deinit();

    //     try std.testing.expectEqual(@as(usize, 0), rope.size());
    // }

    // Create a Rope from a String, the size should be correct
    // {
    //     var rope = try Rope().fromString(std.testing.allocator, "Maurizio");
    //     defer rope.deinit();

    //     try std.testing.expectEqual(@as(usize, 8), rope.size());
    // }

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
