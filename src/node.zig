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
};

pub const Leaf = struct {
    value: []const u8,
    // Size of leaf
    size: usize,
    // Full size (still size of leaf)
    full_size: usize,

    pub fn new(val: []const u8) Leaf {
        return .{
            .value = val,
            .size = val.len,
            .full_size = val.len,
        };
    }

    fn getValueRange(self: Leaf, buffer: *std.ArrayList(u8), start: usize, end: usize) error{OutOfMemory}!void {
        const len = end - start;
        if (start < self.size and len <= self.size)
            try buffer.appendSlice(self.value[start..end]);
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

    pub fn join(self: *Node, allocator: std.mem.Allocator, other: Node) !void {
        const size = self.getFullSize();
        // const size = self.getSize();
        const full_size = self.getFullSize() + other.getFullSize();
        const left = try allocator.create(Node);
        const right = try allocator.create(Node);

        left.* = self.*;
        right.* = other;
        self.* = Node{
            .branch = Branch{
                .left = left,
                .right = right,
                .size = size,
                .full_size = full_size,
            },
        };
    }

    // pub fn join(self: *Node, other: *Node) !Node {
    //     return Node{ .branch = Branch{
    //         .left = self,
    //         .right = other,
    //         .size = self.getFullSize(),
    //         .full_size = self.getFullSize() + other.getFullSize(),
    //     } };
    // }

    // pub fn split(self: *Node, allocator: std.mem.Allocator, pos: usize) !void {
    //     return switch (self.*) {
    //         .branch => |branch| {
    //             _ = branch;
    //             unreachable;
    //         },
    //         .leaf => |leaf| {
    //             if (pos >= leaf.size)
    //                 return error.OutOfBounds;

    //             const left = try allocator.create(Node);
    //             const right = try allocator.create(Node);
    //             left.* = leaf.value[0..pos];
    //             right.* = leaf.value[pos..];

    //             self.* = Node{
    //                 .branch = Branch{
    //                     .left = left,
    //                     .right = right,
    //                     .size = leaf.size,
    //                     .full_size = leaf.full_size,
    //                 },
    //             };
    //         },
    //     };
    // }

    pub fn split(self: *Node, allocator: std.mem.Allocator, pos: usize) !struct { *Node, *Node } {
        return switch (self.*) {
            .branch => |branch| {
                // We are splitting the left branch
                if (pos < branch.size) {
                    if (branch.left) |left| {
                        const new_left, var new_right = try left.split(allocator, pos);
                        if (branch.right) |right| {
                            try new_right.join(allocator, right.*);
                            // const r = try new_right.join(right);
                            return .{ new_left, new_right };
                        }
                        return .{ new_left, new_right };
                    } else {
                        return error.OutOfBounds;
                    }
                } else {
                    if (branch.right) |right| {
                        var new_left, const new_right = try right.split(allocator, pos - branch.size);
                        if (branch.left) |left| {
                            try new_left.join(allocator, left.*);
                            // const l = try new_left.join(left);
                            return .{ new_left, new_right };
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

                var left_content = leaf.value[0..pos];
                var right_content = leaf.value[pos..];

                if (pos == 0) {
                    left_content = "";
                    right_content = leaf.value;
                }
                // return .{ Leaf.new(""), Leaf.new(leaf.value) };

                // const left = leaf.value[0..pos];
                // const right = leaf.value[pos..];

                const left = try allocator.create(Node);
                const right = try allocator.create(Node);
                left.* = Node.newLeaf(left_content);
                right.* = Node.newLeaf(right_content);

                return .{ left, right };

                //             self.* = Node{
                //                 .branch = Branch{
                //                     .left = left,
                //                     .right = right,
                //                     .size = leaf.size,
                //                     .full_size = leaf.full_size,
                //                 },
                //             };

                // return .{ Leaf.new(left), Leaf.new(right) };
            },
        };
    }

    pub fn newLeaf(val: []const u8) Node {
        return .{ .leaf = Leaf.new(val) };
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

        try leaf.getValueRange(&buffer, 0, 5);
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
        const left, const right = try leaf.split(allocator, 0);

        defer allocator.destroy(left);
        defer allocator.destroy(right);

        try std.testing.expectEqualStrings("", left.leaf.value);
        try std.testing.expectEqualStrings("Hello", right.leaf.value);
    }

    // A Leaf splits correctly at the last position
    {
        var leaf: Node = Node.newLeaf("Hello");
        const left, const right = try leaf.split(allocator, 4);

        defer allocator.destroy(left);
        defer allocator.destroy(right);

        try std.testing.expectEqualStrings("Hell", left.leaf.value);
        try std.testing.expectEqualStrings("o", right.leaf.value);
    }

    // We can join leaves and build a Rope
    {
        var rope = try Rope().fromString(std.testing.allocator, "Hello,");
        defer rope.deinit();

        const leaf = Node.newLeaf(" World!");

        try rope.join(leaf);

        const leaf2 = Node.newLeaf(" And Maurizio!");
        try rope.join(leaf2);

        const result = try rope.getValue();
        defer std.testing.allocator.free(result);

        try std.testing.expectEqualStrings("Hello, World! And Maurizio!", result);
    }

    // We can insert a string in an empty Rope
    {
        var rope = Rope().init(allocator);
        defer rope.deinit();

        try rope.insert("Hello world!", 0);

        const result = try rope.getValue();
        defer allocator.free(result);

        try std.testing.expectEqualStrings("Hello world!", result);
    }

    // We can correctly insert a string at the beginning of the rope
    {
        var rope = try Rope().fromString(allocator, "Maurizio!");
        defer rope.deinit();

        rope.print();
        try rope.insert("Hello ", 0);
        rope.print();

        const result = try rope.getValue();
        defer allocator.free(result);

        try std.testing.expectEqualStrings("Hello Maurizio!", result);
    }

    // We can join two Leaves into a Node and print the result
    {
        var rope = try Rope().fromString(allocator, "Hello, Maurizio!");
        defer rope.deinit();
        try rope.insert("World and ", 7);

        const result = try rope.getValue();
        defer allocator.free(result);

        try std.testing.expectEqualStrings("Hello, World and Maurizio!", result);
    }

    // Multiple insertions work correctly
    // {
    //     var rope = try Rope().fromString(allocator, "is a cat");
    //     defer rope.deinit();

    //     try rope.insert("Maurizio ", 0);
    //     rope.print();
    //     try rope.insert("!", 16);
    //     rope.print();
    //     try rope.insert("beautiful ", 14);
    //     rope.print();

    //     const result = try rope.getValue();
    //     defer allocator.free(result);

    //     try std.testing.expectEqualStrings("Maurizio is a beautiful cat!", result);
    // }
}
