const std = @import("std");

const Allocator = std.mem.Allocator;

const RopeNode = struct {
    left: ?*RopeNode,
    right: ?*RopeNode,
    text: []const u8,
    weight: usize,
    height: isize,

    pub fn init(text: []const u8) RopeNode {
        return RopeNode{
            .left = null,
            .right = null,
            .text = text,
            .weight = text.len,
            .height = 1,
        };
    }
};

const Rope = struct {
    root: ?*RopeNode,
    allocator: Allocator,
    max_text_length: usize,

    pub fn init(allocator: Allocator, max_text_length: usize) Rope {
        return Rope{
            .root = null,
            .allocator = allocator,
            .max_text_length = max_text_length,
        };
    }

    pub fn insert(self: *Rope, index: usize, text: []const u8) !void {
        var remaining_text = text;
        var insert_index = index;
        while (remaining_text.len > 0) {
            const chunk_length = if (remaining_text.len > self.max_text_length) self.max_text_length else remaining_text.len;
            const chunk = remaining_text[0..chunk_length];
            const new_node = self.createNode(chunk) catch return;
            if (self.root) |root| {
                self.root = self.insertNode(root, insert_index, new_node);
            } else {
                self.root = new_node;
            }
            remaining_text = remaining_text[chunk_length..];
            insert_index += chunk_length;
        }
    }

    pub fn delete(self: *Rope, index: usize, length: usize) !void {
        if (self.root) |root| {
            self.root = self.deleteNode(root, index, length);
        }
    }

    pub fn getText(self: *Rope, buffer: []u8) !void {
        if (self.root) |root| {
            var offset: usize = 0;
            self.collectText(root, &offset, buffer);
        }
    }

    fn createNode(self: *Rope, text: []const u8) !*RopeNode {
        const node = try self.allocator.create(RopeNode);
        node.* = RopeNode.init(text);
        return node;
    }

    fn insertNode(self: *Rope, node: *RopeNode, index: usize, new_node: *RopeNode) *RopeNode {
        if (index <= node.weight) {
            if (node.left) |left| {
                node.left = self.insertNode(left, index, new_node);
            } else {
                node.left = new_node;
            }
            node.weight += new_node.weight;
        } else {
            if (node.right) |right| {
                node.right = self.insertNode(right, index - node.weight, new_node);
            } else {
                node.right = new_node;
            }
        }
        return self.balance(node);
    }

    fn deleteNode(self: *Rope, node: *RopeNode, index: usize, length: usize) *RopeNode {
        if (index < node.weight) {
            if (node.left) |left| {
                node.left = self.deleteNode(left, index, length);
                node.weight -= length;
            }
        } else {
            if (node.right) |right| {
                node.right = self.deleteNode(right, index - node.weight, length);
            }
        }

        if (index <= node.weight and index + length > node.weight) {
            const delete_start = index - node.weight;
            const delete_end = delete_start + length;
            // TODO fix
            // const new_text = std.mem.sliceToEnd(node.text, delete_start) ++ std.mem.sliceFrom(node.text, delete_end);
            _ = delete_end;
            const new_text = "";
            node.text = new_text;
        }

        return self.balance(node);
    }

    fn collectText(self: *Rope, node: *RopeNode, offset: *usize, buffer: []u8) void {
        if (node.left) |left| {
            self.collectText(left, offset, buffer);
        }
        // TODO fix
        // std.mem.copy(u8, buffer[[offset.* .. offset][0..node.text.len], node.text);
        offset.* += node.text.len;
        if (node.right) |right| {
            self.collectText(right, offset, buffer);
        }
    }

    fn balance(self: *Rope, node: *RopeNode) *RopeNode {
        node.height = self.max(self.height(node.left), self.height(node.right)) + 1;

        const balance_factor = self.getBalance(node);

        // Left Left Case
        if (balance_factor > 1 and self.getBalance(node.left) >= 0) {
            return self.rightRotate(node);
        }

        // Left Right Case
        if (balance_factor > 1 and self.getBalance(node.left) < 0) {
            node.left = self.leftRotate(node.left);
            return self.rightRotate(node);
        }

        // Right Right Case
        if (balance_factor < -1 and self.getBalance(node.right) <= 0) {
            return self.leftRotate(node);
        }

        // Right Left Case
        if (balance_factor < -1 and self.getBalance(node.right) > 0) {
            node.right = self.rightRotate(node.right);
            return self.leftRotate(node);
        }

        return node;
    }

    fn height(self: *Rope, node: ?*RopeNode) isize {
        _ = self;
        return if (node) |n| n.height else -1;
    }

    // TODO is 0 ok?
    fn getBalance(self: *Rope, node: ?*RopeNode) isize {
        if (node) |n| {
            return self.height(n.left) - self.height(n.right);
        } else {
            return 0;
        }
    }

    fn rightRotate(self: *Rope, y: ?*RopeNode) *RopeNode {
        const x = y.?.left orelse unreachable;
        const T2 = x.right;

        // Perform rotation
        x.right = y;
        y.?.left = T2;

        // Update heights
        y.?.height = self.max(self.height(y.?.left), self.height(y.?.right)) + 1;
        x.height = self.max(self.height(x.left), self.height(x.right)) + 1;

        // Update weights
        y.?.weight = self.getWeight(y.?.left) + y.?.text.len;
        x.weight = self.getWeight(x.left) + self.getWeight(x.right) + x.text.len;

        return x;
    }

    fn leftRotate(self: *Rope, x: ?*RopeNode) *RopeNode {
        const y = x.?.right orelse unreachable;
        const T2 = y.left;

        // Perform rotation
        y.left = x;
        x.?.right = T2;

        // Update heights
        x.?.height = self.max(self.height(x.?.left), self.height(x.?.right)) + 1;
        y.height = self.max(self.height(y.left), self.height(y.right)) + 1;

        // Update weights
        x.?.weight = self.getWeight(x.?.left) + x.?.text.len;
        y.weight = self.getWeight(y.left) + self.getWeight(y.right) + y.text.len;

        return y;
    }

    fn getWeight(self: *Rope, node: ?*RopeNode) usize {
        _ = self;
        return if (node) |n| n.weight else 0;
    }

    fn max(self: *Rope, a: isize, b: isize) isize {
        _ = self;
        return if (a > b) a else b;
    }
    pub fn printTree(self: *Rope) void {
        std.debug.print("\n\n~~~\n", .{});
        if (self.root) |root| {
            self.printNode(root, 0);
        } else {
            std.debug.print("Tree is empty\n", .{});
        }
        std.debug.print("\n\n~~~\n", .{});
    }

    fn printNode(self: *Rope, node: *RopeNode, depth: usize) void {
        for (0..depth) |_| {
            std.debug.print("  ", .{});
        }
        std.debug.print("Node(text: \"{s}\", weight: {d}, height: {d})\n", .{ node.text, node.weight, node.height });
        if (node.left) |left| {
            self.printNode(left, depth + 1);
        }
        if (node.right) |right| {
            self.printNode(right, depth + 1);
        }
    }
};

test "Rope basic operations" {
    const allocator = std.testing.allocator;

    var rope = Rope.init(allocator, 10); // Set max text length to 10

    // Insert text
    try rope.insert(0, "Hello, ");
    try rope.insert(7, "world!");
    try rope.insert(13, " How are you?");

    // Buffer to collect text
    var buffer: [100]u8 = undefined;
    try rope.getText(&buffer);

    rope.printTree();

    const expected = "Hello, world! How are you?";
    const result = buffer[0..expected.len];
    try std.testing.expectEqualStrings(expected, result);

    // Delete text
    // try rope.delete(7, 6); // remove "world!"
    // try rope.getText(&buffer);
    // const expected_after_delete = "Hello,  How are you?";
    // const result_after_delete = buffer[0..expected_after_delete.len];
    // try std.testing.expectEqualStrings(expected_after_delete, result_after_delete);

    // // Insert more text
    // try rope.insert(7, "Zig ");
    // try rope.getText(&buffer);
    // const expected_after_insert = "Hello, Zig How are you?";
    // const result_after_insert = buffer[0..expected_after_insert.len];
    // try std.testing.expectEqualStrings(expected_after_insert, result_after_insert);
}
