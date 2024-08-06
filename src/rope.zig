const std = @import("std");
const node_dep = @import("node.zig");

const Node = node_dep.Node;
const Branch = node_dep.Branch;
const Leaf = node_dep.Leaf;

// TODO I have a memory leak triggered by the last test only
// TODO possibly node.join should accept a *Node

// TODO how much should be in Rope and how much in the single nodes?
// TODO splitting the modules doesn't work with pub, what can I do?

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
        pub fn fromString(allocator: std.mem.Allocator, string: []const u8) !Self {
            var rope = Self{
                .allocator = allocator,
                .root = null,
            };

            const leaf = try allocator.create(Node);
            leaf.* = Node.newLeaf(string);

            rope.root = leaf;

            return rope;
        }

        /// Insert a string at the given position in the Rope.
        pub fn insert(self: *Self, string: []const u8, pos: usize) !void {
            // const leaf: *Node = try self.newLeaf(string);
            if (self.root) |root| {
                const left, const right = try root.split(self.allocator, pos);

                // var left_node = try self.allocator.create(Node);
                // const right_node = try self.allocator.create(Node);
                // left_node.* = left;
                // right_node.* = right;

                // TODO Might have to change the order here
                try left.join(self.allocator, Node.newLeaf(string));
                try left.join(self.allocator, right.*);

                // var tmp = try left.join(self.allocator, Node.newLeaf(string));
                // var res = try tmp.join(self.allocator, right);
                // var res = try Node.join(&tmp, right_node);
                // const new_root = try self.allocator.create(Node);
                // new_root.* = res;

                // self.allocator.destroy(left_node);
                // self.allocator.destroy(right_node);
                // self.root = new_root;
                // self.root.?.* = res;
                self.root = left;
            } else {
                const leaf = try self.allocator.create(Node);
                leaf.* = Node.newLeaf(string);
                self.root = leaf;
            }
        }

        /// Joins the root Node with a new Node
        pub fn join(self: *Self, node: Node) !void {
            if (self.root) |root| {
                try root.join(self.allocator, node);
                // const new_root = try self.allocator.create(Node);
                // new_root.* = try root.join(node);
                // self.root = new_root;
            } else {
                const new_root = try self.allocator.create(Node);
                new_root.* = node;
                self.root = new_root;
            }
        }

        /// Split a Rope. TODO Not sure if and how will use this yet.
        /// I will get back to it.
        pub fn split(self: *Self, pos: usize) struct { Self, Self } {
            if (self.root) |root| {
                const left, const right = try root.split(pos);
                const left_node = self.allocator.create(Node);
                const right_node = self.allocator.create(Node);
                left_node.* = left;
                right_node.* = right;
                return .{
                    Self.fromNode(self.allocator, left_node),
                    Self.fromNode(self.allocator, right_node),
                };
            }
            // TODO what if the root is missing?
            unreachable;
        }

        // Gets the Rope value in a range.
        // Caller is responsible for freeing the result.
        // TODO How can I improve this?
        pub fn getValueRange(self: *Self, start: usize, end: usize) ![]const u8 {
            if (self.root) |root| {
                var buffer = std.ArrayList(u8).init(self.allocator);
                defer buffer.deinit();
                try root.getValueRange(&buffer, start, end);
                const result = try buffer.toOwnedSlice();
                return result;
            }
            return "";
        }

        /// Gets the whole Rope value
        pub fn getValue(self: *Self) ![]const u8 {
            if (self.root) |root| {
                return try self.getValueRange(0, root.getFullSize());
            }
            return "";
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
        // pub fn newLeaf(self: Self, string: []const u8) !*Node {
        //     const leaf = try self.allocator.create(Node);
        //     leaf.* = Leaf.new(string);
        //     return leaf;
        // }

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
        // fn setRoot(self: *Self, node: Node) void {
        //     self.root.* = node;
        // }

        pub fn print(self: Self) void {
            if (self.root) |root| {
                root.printNode(0);
            } else {
                std.debug.print("[EMPTY]\n", .{});
            }
        }
    };
}

test "rope" {
    _ = node_dep;
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
