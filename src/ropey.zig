const std = @import("std");

// TODOS:
// - [ ] I need a way to test this structurally, how can I do it? Depth, get arbitrary node, serialize?
// - [ ] I need to be able to rebalance the tree
// - [ ] I need to be able to set a maximum size for leaves, possibly use more constrained (in size) types
// - [ ] Split
// - [ ] Insert

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
            inline else => |node| try node.getValueRange(buffer, start, end),
        }
    }

    fn join(self: *Node, allocator: std.mem.Allocator, other: Node) !void {
        // If it's a branch with a null right node, we can just put the other node there
        // TODO this only when this is a branch...
        switch (self.*) {
            .branch => |_| {
                if (self.right == null) {
                    const right = try allocator.create(Node);
                    right.* = other;
                    self.right = right;
                    return;
                }
            },
            .leaf => {},
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

    /// TODO: I think I have to split the internal recursive version so that it returns a pair of
    /// ?*Node possibly, or at least one that can be null. I want to handle Leaves split at 0 or length
    /// without creating meaningless nodes.
    /// TODO I also need to remember to update the sizes of parent nodes! I was not doing this in the other
    /// implementation.
    /// The old implementation is just wrong, think about the steps, if pos > size, then just move further
    /// down. Possibly return a package with the updates (nodes, and sizes?) maybe in the internal
    /// function.
    fn split(self: *Node, allocator: std.mem.Allocator, pos: usize) !struct { *Node, *Node } {
        return switch (self.*) {
            .branch => |branch| {
                if (pos < branch.size) {
                    if (branch.left) |left| {
                        _ = left;
                    }
                } else {
                    if (branch.right) |right| {
                        _ = right;
                    }
                }
            },
            .leaf => |leaf| {
                _ = leaf;
            },
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
}
