const std = @import("std");

pub const RopeNode = union(enum) {
    node: Node,
    leaf: Leaf,
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
                    self.allocator.destroy(node);
                },
            }
            self.allocator.destroy(node);
        }
    }

    pub fn deinit(self: *Rope) void {
        self.deinitNode(self.rope);
    }

    fn newLeaf(self: *Rope, string: []const u8) !*RopeNode {
        const node = try self.allocator.create(Leaf);

        node.* = .{
            .substring = string,
            .len = string.len,
        };

        return node;
    }

    fn newBranch(self: *Rope, left: *RopeNode, right: *RopeNode, len: usize) !*RopeNode {
        const node = try self.allocator.create(Node);
        node.* = .{
            .left = left,
            .right = right,
            .len = len,
        };

        return node;
    }

    pub fn insert(self: *Rope, idx: usize, string: []const u8) !void {
        // Todo, I want to split this to 128 max
        const leaf = try self.newLeaf(string);

        if (self.rope) |rope| {
            if (idx == 0) {
                const branch = try self.newBranch(leaf, rope, leaf.len);
                self.rope = branch;
            }
        } else {
            self.rope = leaf;
        }
    }

    pub fn concatenate(self: *Rope, other: Rope) void {
        const root = Node{
            .left = self.rope,
            .right = other.rope,
            .len = self.rope.len + other.rope.len,
        };

        self.rope = root;
    }
};

test "rope" {
    var rope = Rope.init(std.testing.allocator);
    defer rope.deinit();

    try std.testing.expect(1 == 1);
}
