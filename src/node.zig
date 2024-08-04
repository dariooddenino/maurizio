const std = @import("std");
const Rope = @import("rope.zig").Rope;

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
    {
        var leaf = Node.newLeaf("Hello");

        const result = try leaf.getValueRange(std.testing.allocator, 0, 4);

        try std.testing.expectEqualStrings("Hello", result orelse unreachable);
    }

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
    // {
    //     const leaf1: Node = Node.newLeaf("Hello");
    //     const leaf2: Node = Node.newLeaf(", World!");

    //     const allocator = std.testing.allocator;

    //     var rope = Rope().init(allocator);
    //     defer rope.deinit();
    //     try rope.join(leaf1);
    //     try rope.join(leaf2);

    //     const result = try rope.getValueRange(allocator, 2, 6);

    //     // std.debug.print("RESU:LT {any}\n", .{result});

    //     try std.testing.expectEqualStrings("llo", result orelse unreachable);
    // }
}
