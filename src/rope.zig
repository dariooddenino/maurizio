const std = @import("std");

pub const RopeNode = union(enum) {
    node: Node,
    leaf: Leaf,

    pub fn getLen(self: RopeNode) usize {
        switch (self) {
            inline else => |n| return n.len,
        }
    }

    fn collectNode(self: *RopeNode, buffer: *std.ArrayList(u8)) !void {
        switch (self.*) {
            .leaf => |leaf| {
                try buffer.appendSlice(leaf.substring);
            },
            .node => |node| {
                if (node.left) |left| {
                    try left.collectNode(buffer);
                }
                if (node.right) |right| {
                    try right.collectNode(buffer);
                }
            },
        }
    }
};

pub const Node = struct {
    left: ?*RopeNode,
    right: ?*RopeNode,
    len: usize = 0,
};

pub const Leaf = struct {
    substring: []const u8,
    len: usize = 0,
};

pub const Rope = struct {
    allocator: std.mem.Allocator,
    rope: ?*RopeNode,

    pub fn init(allocator: std.mem.Allocator) Rope {
        return .{
            .allocator = allocator,
            .rope = null,
        };
    }

    pub fn deinitNode(self: *Rope, m_node: ?*RopeNode) void {
        if (m_node) |node| {
            switch (node.*) {
                .leaf => {},
                .node => |n| {
                    self.deinitNode(n.left);
                    self.deinitNode(n.right);
                },
            }
            self.allocator.destroy(node);
        }
    }

    pub fn deinit(self: *Rope) void {
        self.deinitNode(self.rope);
    }

    /// Concatenate two ropes into a single one.
    /// O(1) or O(log N) time to compute the root weight.
    /// NOTE other must not be freed by the caller :/
    pub fn concat(self: *Rope, other: Rope) !void {
        const node = try self.allocator.create(RopeNode);

        node.* = RopeNode{
            .node = .{
                .left = self.rope,
                .right = other.rope,
                .len = self.rope.?.getLen(),
                // .len = self.rope.?.getLen() + other.rope.?.getLen(),
            },
        };

        self.rope = node;
    }

    /// Returns the character at position i
    /// O(log N)
    fn indexNode(node: *RopeNode, i: usize) !u8 {
        if (i < node.getLen()) {
            switch (node.*) {
                .leaf => |leaf| {
                    return leaf.substring[i];
                },
                .node => |n| {
                    if (n.left) |left| {
                        return indexNode(left, i);
                    } else {
                        // TODO better
                        std.debug.print("OUT OF NODE BOUNDS\n", .{});
                        return error.OverFlow;
                    }
                },
            }
        } else {
            switch (node.*) {
                // TODO handle better
                .leaf => |_| {
                    std.debug.print("OUT OF LEAF BOUNDS\n", .{});
                    return error.OverFlow;
                },
                .node => |n| {
                    if (n.right) |right| {
                        return indexNode(right, i - node.getLen());
                    } else {
                        // TODO better
                        std.debug.print("OUT OF NODE BOUNDS\n", .{});
                        return error.OverFlow;
                    }
                },
            }
        }
    }

    pub fn index(self: Rope, i: usize) !u8 {
        if (self.rope) |node| {
            return try indexNode(node, i);
        } else {
            // TODO something better here
            std.debug.print("[EMPTY]\n", .{});
            return error.OverFlow;
        }
    }

    /// Collect the tree into a string (?)
    pub fn collect(self: *Rope, buffer: *std.ArrayList(u8)) !void {
        if (self.rope) |node| {
            try node.collectNode(buffer);
        } else {
            return;
        }
    }

    // EXAMPLE BELOW

    fn newLeaf(self: *Rope, string: []const u8) !*RopeNode {
        const leaf = try self.allocator.create(RopeNode);

        leaf.* = RopeNode{
            .leaf = .{
                .substring = string,
                .len = string.len,
            },
        };
        // Pretty sure this is bad
        return leaf;
    }

    fn newNode(self: *Rope, left: *RopeNode, right: *RopeNode, len: usize) !*RopeNode {
        const node = try self.allocator.create(RopeNode);
        node.* = RopeNode{
            .node = .{
                .left = left,
                .right = right,
                .len = len,
            },
        };

        return node;
    }

    pub fn insert(self: *Rope, idx: usize, string: []const u8) !void {
        // Todo, I want to split this to 128 max
        const leaf = try self.newLeaf(string);

        if (self.rope) |rope| {
            if (idx == 0) {
                const node = try self.newNode(leaf, rope, leaf.getLen());
                self.rope = node;
            }
        } else {
            self.rope = leaf;
        }
    }

    fn printSpaces(depth: usize) void {
        for (0..depth) |_| {
            std.debug.print(" ", .{});
        }
    }

    fn printNode(node: *RopeNode, depth: usize) void {
        printSpaces(depth);

        switch (node.*) {
            .leaf => |leaf| std.debug.print("({}) {s}\n", .{ leaf.len, leaf.substring }),
            .node => |n| {
                std.debug.print("({}):", .{n.len});
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

    pub fn print(self: Rope) void {
        if (self.rope) |rope| {
            printNode(rope, 0);
        } else {
            std.debug.print("[EMPTY]\n", .{});
        }
    }
};

test "index" {
    var rope = Rope.init(std.testing.allocator);
    defer rope.deinit();

    try rope.insert(0, "Maurizio!");

    const m = try rope.index(0);
    try std.testing.expect(m == 'M');
}

test "concat" {
    var rope2 = Rope.init(std.testing.allocator);
    var rope1 = Rope.init(std.testing.allocator);
    defer rope1.deinit();

    try rope1.insert(0, "Hello, ");
    try rope2.insert(0, "Concatenated Maurizio!");

    try rope1.concat(rope2);

    const c = try rope1.index(7);

    try std.testing.expect('C' == c);
}

test "collect" {
    var rope = Rope.init(std.testing.allocator);
    defer rope.deinit();

    try rope.insert(0, "Maurizio");
    try rope.insert(0, "Hello, ");
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    try rope.collect(&buffer);

    try std.testing.expect(std.mem.eql(u8, buffer.items, "Hello, Maurizio"));

    var rope2 = Rope.init(std.testing.allocator);
    try rope2.insert(0, "! You beautiful cat.");

    try rope.concat(rope2);

    var buffer2 = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer2.deinit();
    try rope.collect(&buffer2);

    try std.testing.expect(std.mem.eql(u8, buffer2.items, "Hello, Maurizio! You beautiful cat."));
}
