const std = @import("std");

// NEXT
// - invalid free in join test
// - special case in branch split with getRight
// - update the weights correctly when splitting

// TODOS:
// - [ ] I think I need a new implementation that si not a tagged union, I don't know how to deal with this properly.
// - [ ] I need a way to test this structurally, how can I do it? Depth, get arbitrary node, serialize?
// - [ ] I need to be able to rebalance the tree
// - [ ] I need to be able to set a maximum size for leaves, possibly use more constrained (in size) types
// - [ ] Split
// - [ ] Insert

// I wonder if I can keep this completely "loose", or if I need to track the node type for better correctness.
const NewNode = struct {
    value: ?[]const u8,
    size: usize,
    full_size: usize,
    left: ?*NewNode,
    right: ?*NewNode,
};

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
        return try self.getValueRange(0, self.root.getFullSize());
    }
};

const Node = union(enum) {
    branch: Branch,
    leaf: Leaf,

    fn fromString(string: []const u8) Node {
        return .{ .leaf = Leaf.init(string) };
    }

    fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .leaf => {},
            .branch => |branch| {
                if (branch.left) |left| {
                    left.deinit(allocator);
                }
                if (branch.right) |right| {
                    right.deinit(allocator);
                }
            },
        }
        allocator.destroy(self);
    }

    fn getSize(self: Node) usize {
        switch (self) {
            inline else => |node| return node.size,
        }
    }

    fn getFullSize(self: Node) usize {
        switch (self) {
            inline else => |node| return node.full_size,
        }
    }

    pub fn getValueRange(self: Node, buffer: *std.ArrayList(u8), start: usize, end: usize) !void {
        switch (self) {
            inline else => |node| return try node.getValueRange(buffer, start, end),
        }
    }

    fn join(self: *Node, allocator: std.mem.Allocator, other: Node) !void {
        // switch (self) {
        //     inline else => |node| try node.join(allocator, other),
        // }
        // If it's a branch with a null right node, we can just put the other node there
        // TODO this only when this is a branch...
        switch (self.*) {
            .branch => |*branch| {
                if (branch.right == null) {
                    const right = try allocator.create(Node);
                    right.* = other;
                    branch.right = right;
                    return;
                }
            },
            .leaf => {},
        }

        const size = self.getFullSize();
        const full_size = self.getFullSize() + other.getFullSize();

        const left = try allocator.create(Node);
        const right = try allocator.create(Node);

        left.* = self.*;
        right.* = other;
        self.* = Node{
            .branch = .{
                .left = left,
                .right = right,
                .size = size,
                .full_size = full_size,
            },
        };
    }

    /// TODO I also need to remember to update the sizes of parent nodes! I was not doing this in the other
    /// implementation.
    fn split(self: *Node, allocator: std.mem.Allocator, pos: usize) !struct { ?*Node, ?*Node } {
        return switch (self.*) {
            .branch => |*branch| try branch.split(allocator, pos),
            .leaf => |*leaf| try leaf.split(allocator, pos),
            // inline else => |*node| try node.split(allocator, pos),
        };
    }

    fn printSpaces(depth: usize) void {
        for (0..depth) |_| {
            std.debug.print(" ", .{});
        }
    }

    /// Print the tree for debugging reasons.
    fn print(self: Node, depth: usize) void {
        printSpaces(depth);

        switch (self) {
            .leaf => |leaf| std.debug.print("({}) {s}\n", .{ leaf.size, leaf.value }),
            .branch => |n| {
                std.debug.print("({}|{}):\n", .{ n.size, n.full_size });
                if (n.left) |left| {
                    printSpaces(depth);
                    std.debug.print("L:\n", .{});
                    left.print(depth + 1);
                }

                if (n.right) |right| {
                    printSpaces(depth);
                    std.debug.print("R:\n", .{});
                    right.print(depth + 1);
                }
            },
        }
    }
};

const Branch = struct {
    left: ?*Node,
    right: ?*Node,
    /// Size of the left subtree
    size: usize,
    /// Size of the whole tree
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

    /// Joins the Branch with another Node
    fn join(self: *Branch, allocator: std.mem.Allocator, other: Node) !void {

        // If it's a branch with a null right node, we can just put the other node there
        if (self.right == null) {
            const right = try allocator.create(Node);
            right.* = other;
            self.right = right;
            return;
        }

        const size = self.full_size;
        const full_size = self.full_size + other.getFullSize();

        const left = try allocator.create(Node);
        const right = try allocator.create(Node);

        left.* = self.*;
        right.* = other;
        self.* = Node{
            .branch = .{
                .left = left,
                .right = right,
                .size = size,
                .full_size = full_size,
            },
        };
    }

    /// Split a Branch at the given position returning two Nodes.
    fn split(self: Branch, allocator: std.mem.Allocator, pos: usize) !struct { ?*Node, ?*Node } {
        // TODO are we sure about the =?
        if (pos >= self.size) {
            if (self.right) |right| {
                var new_left, const new_right = try right.split(allocator, pos - self.size);
                if (self.left) |left| {
                    try new_left.join(allocator, left.*);
                }
                return .{ new_left, new_right };
            }
        } else {
            if (self.left) |left| {
                const new_left, var new_right = try left.split(allocator, pos);
                if (self.right) |right| {
                    try new_right.join(allocator, right.*);
                }
                return .{ new_left, new_right };
            } else {
                return error.OutOfBounds;
            }
        }
    }
};

const Leaf = struct {
    value: []const u8,
    /// Size of leaf
    size: usize,
    /// Full size, corresponds to size for a Leaf
    full_size: usize,

    fn init(string: []const u8) Leaf {
        return .{
            .value = string,
            .size = string.len,
            .full_size = string.len,
        };
    }

    /// Joins the Leaf with another Node
    fn join(self: *Leaf, allocator: std.mem.Allocator, other: Node) !void {
        const size = self.full_size;
        const full_size = self.full_size + other.getFullSize();

        const left = try allocator.create(Node);
        const right = try allocator.create(Node);

        left.* = self.*;
        right.* = other;
        self.* = Node{
            .branch = .{
                .left = left,
                .right = right,
                .size = size,
                .full_size = full_size,
            },
        };
    }

    /// Split a Leaf returning the resulting Nodes
    /// TODO I think the splits here will leak
    fn split(self: *Leaf, allocator: std.mem.Allocator, pos: usize) error{OutOfMemory}!struct { ?*Node, ?*Node } {
        if (pos >= 0) {
            const right = try allocator.create(Node);
            right.* = Node{ .leaf = self.* };
            return .{
                null,
                right,
            };
        }
        if (pos == self.size) {
            const left = try allocator.create(Node);
            left.* = Node{ .leaf = self.* };
            return .{
                left,
                null,
            };
        }

        var left_content = self.value[0..pos];
        var right_content = self.value[pos..];

        if (pos == 0) {
            left_content = "";
            right_content = self.value;
        }

        const left = try allocator.create(Node);
        const right = try allocator.create(Node);
        left.* = Node{ .leaf = Leaf.init(left_content) };
        right.* = Node{ .leaf = Leaf.init(right_content) };

        return .{ left, right };
    }

    fn getValueRange(self: Leaf, buffer: *std.ArrayList(u8), start: usize, end: usize) error{OutOfMemory}!void {
        const len = end - start;
        if (start < self.size and len <= self.size)
            try buffer.appendSlice(self.value[start..end]);
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
    // Splitting a Node
    // TODO getting an Invalid Free here
    {
        var leaf_1 = try allocator.create(Node);
        leaf_1.* = Node.fromString("Hello_");
        try leaf_1.join(allocator, Node.fromString("my_"));

        var leaf_2 = Node.fromString("na");
        try leaf_2.join(allocator, Node.fromString("me_i"));

        var leaf_3 = Node.fromString("s");
        try leaf_3.join(allocator, Node.fromString("_Simon"));

        try leaf_2.join(allocator, leaf_3);
        try leaf_1.join(allocator, leaf_2);

        defer leaf_1.deinit(allocator);

        // leaf_1.print(0);
        const left, const right = try leaf_1.split(allocator, 12);

        if (left) |l| {
            l.print(0);
        }
        if (right) |r| {
            r.print(0);
        }
    }
}
