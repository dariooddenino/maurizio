const std = @import("std");
const Rope = @import("rope.zig").Rope;

pub const Branch = struct {
    left: ?*Node,
    right: ?*Node,
    // Size of left subtree
    size: usize,
    // Size of the whole tree
    full_size: usize,

    fn getValueRange(self: Branch, buffer: *std.ArrayList(u8), start: usize, end: usize) error{OutOfMemory}!void {
        const len = end - start + 1;
        if (len <= self.size) {
            if (self.left) |left| {
                try left.getValueRange(buffer, start, end);
            }
        }

        if (self.left) |left| {
            try left.getValueRange(buffer, start, self.size - 1);
        }
        if (self.right) |right| {
            try right.getValueRange(buffer, 0, len - self.size - 1);
        }
    }
};

pub const Leaf = struct {
    value: []const u8,
    // Size of leaf
    size: usize,
    // Full size (still size of leaf)
    full_size: usize,

    pub fn new(val: []const u8) Node {
        return .{ .leaf = .{
            .value = val,
            .size = val.len,
            .full_size = val.len,
        } };
    }

    fn getValueRange(self: Leaf, buffer: *std.ArrayList(u8), start: usize, end: usize) error{OutOfMemory}!void {
        const len = end - start + 1;
        if (start < self.size and len <= self.size)
            try buffer.appendSlice(self.value[start..len]);
    }
};

pub const Node = union(enum) {
    branch: Branch,
    leaf: Leaf,

    pub fn getValueRange(self: Node, buffer: *std.ArrayList(u8), start: usize, end: usize) !void {
        switch (self) {
            inline else => |node| try node.getValueRange(buffer, start, end),
        }
    }

    pub fn getSize(self: Node) usize {
        switch (self) {
            inline else => |node| return node.size,
        }
    }

    pub fn getFullSize(self: Node) usize {
        switch (self) {
            inline else => |node| return node.full_size,
        }
    }

    fn update(self: *Node) void {
        self.size = self.left.?.getSize() + self.right.?.getSize() + 1;
    }

    pub fn join(self: *Node, other: *Node) !Node {
        return Node{ .branch = Branch{
            .left = self,
            .right = other,
            .size = self.getFullSize(),
            .full_size = self.getFullSize() + other.getFullSize(),
        } };
    }

    pub fn split(self: *Node, pos: usize) !struct { Node, Node } {
        return switch (self.*) {
            .branch => |branch| {
                // We are splitting the left branch
                if (pos < branch.size) {
                    if (branch.left) |left| {
                        const new_left, var new_right = try left.split(pos);
                        if (branch.right) |right| {
                            const r = try new_right.join(right);
                            return .{ new_left, r };
                        }
                        return .{ new_left, new_right };
                    } else {
                        return error.OutOfBounds;
                    }
                } else {
                    if (branch.right) |right| {
                        var new_left, const new_right = try right.split(pos - branch.size);
                        if (branch.left) |left| {
                            const l = try new_left.join(left);
                            return .{ l, new_right };
                        }
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
            .full_size = val.len,
        } };
    }

    fn printSpaces(depth: usize) void {
        for (0..depth) |_| {
            std.debug.print(" ", .{});
        }
    }

    pub fn printNode(node: *Node, depth: usize) void {
        printSpaces(depth);

        switch (node.*) {
            .leaf => |leaf| std.debug.print("({}) {s}\n", .{ leaf.size, leaf.value }),
            .branch => |n| {
                std.debug.print("({}|{}):\n", .{ n.size, n.full_size });
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
    const allocator = std.testing.allocator;
    // A Leaf reports its value
    {
        var leaf = Node.newLeaf("Hello");

        var buffer = std.ArrayList(u8).init(allocator);

        try leaf.getValueRange(&buffer, 0, 4);
        const result = try buffer.toOwnedSlice();
        defer allocator.free(result);

        try std.testing.expectEqualStrings("Hello", result);
    }

    // We can extract a substring from a string
    {
        var leaf = Node.newLeaf("Hello");

        var buffer = std.ArrayList(u8).init(allocator);
        try leaf.getValueRange(&buffer, 1, 5);
        const result = try buffer.toOwnedSlice();
        defer allocator.free(result);

        try std.testing.expectEqualStrings("ello", result);
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

    // We can join leaves and build a Rope
    {
        var rope = try Rope().fromString(std.testing.allocator, "Hello,");
        defer rope.deinit();

        const leaf = try rope.newLeaf(" World!");

        try rope.join(leaf);

        const leaf2 = try rope.newLeaf(" And Maurizio!");
        try rope.join(leaf2);

        const result = try rope.getValue();
        defer std.testing.allocator.free(result);

        try std.testing.expectEqualStrings("Hello, World! And Maurizio!", result);
    }

    // We can join on an empty rope
    // {
    //     var rope = Rope().init(allocator);
    //     defer rope.deinit();

    //     // TODO BUG here, I'm splitting wrong
    //     try rope.insert("Hello world!", 0);

    //     rope.print();

    //     const result = try rope.getValueRange(0, 2);
    //     defer allocator.free(result);

    //     try std.testing.expectEqualStrings("Hel", result);
    // }

    // We can join two Leaves into a Node and print the result
    // {
    //     var rope = try Rope().fromString(allocator, "Hello!");
    //     defer rope.deinit();
    //     // TODO BUG here, hangs forever
    //     try rope.insert(", World!", 3);

    //     rope.print();

    //     const result = try rope.getValueRange(2, 6);
    //     defer allocator.free(result);

    //     try std.testing.expectEqualStrings("llo", result);
    // }
}
