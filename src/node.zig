const std = @import("std");
const time = std.time;

const Allocator = std.mem.Allocator;
const BoundedArray = std.BoundedArray;
const Timer = time.Timer;

/// The maximum size a leaf can reach.
const MAX_LEAF_SIZE: usize = 10;
/// The L/R imbalance ratio that triggers a rebalace operation.
const REBALANCE_RATIO: f32 = 1.2;

const LeafText = BoundedArray(u8, MAX_LEAF_SIZE);

// TODO
// - I think I shouldn't be using recursion here, tail recursion or stack approach.
// - BUG see failing test and follow notes.
// - BUG when closing the editor there's a memory leak
// - INSERT: I think size is fine, depth not updated
// - DELETE: I think size is fine, depth not updated
// - JOIN: No idea here
// - format node from zighelp
// - Automatic balance check and rebalance
// - There's a bit of replication between Node and Rope functionalities

pub const Node = struct {
    value: ?*LeafText,
    size: usize,
    full_size: usize,
    depth: usize,
    left: ?*Node,
    right: ?*Node,
    is_leaf: bool,

    /// Deinit the Node
    pub fn deinit(self: *Node, allocator: Allocator) void {
        if (self.left) |left| {
            left.deinit(allocator);
        }
        if (self.right) |right| {
            right.deinit(allocator);
        }
        if (self.value) |value| {
            allocator.destroy(value);
        }
        allocator.destroy(self);
    }

    pub fn createLeaf(allocator: Allocator, text: []const u8) !*Node {
        if (text.len > MAX_LEAF_SIZE) {
            unreachable;
        }

        const node = try allocator.create(Node);

        const value = try allocator.create(LeafText);

        value.* = try LeafText.fromSlice(text);

        node.* = .{
            .value = value,
            .size = text.len,
            .full_size = text.len,
            .depth = 1,
            .left = null,
            .right = null,
            .is_leaf = true,
        };

        return node;
    }

    fn createBranch(allocator: Allocator, left: *Node, right: *Node) !*Node {
        const node = try allocator.create(Node);

        node.* = .{
            .value = null,
            .size = left.full_size,
            .full_size = left.full_size + right.full_size,
            .depth = @max(left.depth, right.depth) + 1,
            .left = left,
            .right = right,
            .is_leaf = false,
        };

        return node;
    }

    /// TODO I think this can be a more general operation?
    /// i.e. is this just insert?
    fn fromText(allocator: Allocator, text: []const u8) !*Node {
        if (text.len > MAX_LEAF_SIZE) {
            const mid_point: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(text.len)) / 2));
            const left_text = text[0..mid_point];
            const right_text = text[mid_point..];
            const left = try Node.fromText(allocator, left_text);
            const right = try Node.fromText(allocator, right_text);

            return try createBranch(allocator, left, right);
        } else {
            return try createLeaf(allocator, text);
        }
    }

    /// Copies a leaf, used while splitting
    fn copyLeaf(allocator: Allocator, source: Node) !*Node {
        const value = blk: {
            if (source.value) |value| {
                break :blk value.constSlice();
            } else {
                // NOTE this looks suspicious
                break :blk "";
            }
        };

        const leaf = try Node.createLeaf(allocator, value);
        leaf.depth = source.depth;
        return leaf;
    }

    fn clone(self: Node, allocator: std.mem.Allocator) !Node {
        if (self.is_leaf) {
            // TODO awkward, I should revisit this whole split/clone algorithm
            const leaf = try Node.copyLeaf(allocator, self);
            defer allocator.destroy(leaf);
            return leaf.*;
        }

        var result = self;
        if (self.left) |left| {
            const new_left = try allocator.create(Node);
            new_left.* = try left.clone(allocator);
            result.left = new_left;
        }
        if (self.right) |right| {
            const new_right = try allocator.create(Node);
            new_right.* = try right.clone(allocator);
            result.right = new_right;
        }

        return result;
    }

    /// Joins the Node with another one.
    fn join(self: *Node, allocator: std.mem.Allocator, original_other: Node) !void {
        const other = try original_other.clone(allocator);
        if (!self.is_leaf) {
            if (self.right == null) {
                const right = try allocator.create(Node);
                right.* = other;
                self.right = right;
                return;
            }
        }

        const size = self.full_size;
        const full_size = self.full_size + other.full_size;

        const left = try allocator.create(Node);
        const right = try allocator.create(Node);

        left.* = self.*;
        right.* = other;
        self.* = Node{
            .left = left,
            .right = right,
            .size = size,
            .full_size = full_size,
            .is_leaf = false,
            .value = null,
            .depth = @max(left.depth, other.depth) + 1,
        };
    }

    /// Splits the node at the given position.
    /// NOTE: what did I mean with "the original one is left untouched?"
    /// I might have to look into the fact that I'm cloning the nodes, is it really needed?
    fn split(self: *Node, allocator: std.mem.Allocator, pos: usize) !struct { ?*Node, ?*Node } {
        if (self.is_leaf) {
            if (pos == 0) {
                const leaf = try Node.copyLeaf(allocator, self.*);
                return .{ null, leaf };
            }
            if (pos == self.size) {
                const leaf = try Node.copyLeaf(allocator, self.*);
                return .{ leaf, null };
            }

            const left_content, const right_content = blk: {
                if (self.value) |value| {
                    break :blk .{ value.constSlice()[0..pos], value.constSlice()[pos..] };
                } else {
                    break :blk .{ "", "" };
                }
            };

            const left = try Node.createLeaf(allocator, left_content);
            const right = try Node.createLeaf(allocator, right_content);

            return .{ left, right };
        } else {
            if (pos >= self.size) {
                if (self.right) |right| {
                    const split_left, const split_right = try right.split(allocator, pos - self.size);
                    if (self.left) |left| {
                        const copy_left = try allocator.create(Node);
                        copy_left.* = try left.clone(allocator);
                        if (split_left) |sl| {
                            defer sl.deinit(allocator);
                            try copy_left.join(allocator, sl.*);
                            return .{ copy_left, split_right };
                        } else {
                            return .{ copy_left, split_right };
                        }
                    } else if (split_left) |sl| {
                        // If there was no left (possible?) we just add the split as the new left.
                        return .{ sl, split_right };
                    } else {
                        unreachable;
                    }
                } else {
                    return error.OutOfBounds;
                }
            } else {
                if (self.left) |left| {
                    const split_left, const split_right = try left.split(allocator, pos);
                    if (self.right) |right| {
                        const copy_right = try allocator.create(Node);
                        copy_right.* = try right.clone(allocator);
                        if (split_right) |sr| {
                            defer copy_right.deinit(allocator);
                            try sr.join(allocator, copy_right.*);
                            return .{ split_left, sr };
                        } else {
                            return .{ split_left, copy_right };
                        }
                    } else if (split_right) |sr| {
                        return .{ split_left, sr };
                    } else {
                        unreachable;
                    }
                } else {
                    return error.OutOfBounds;
                }
            }
        }
    }

    // TODO, if we're deleting within the boundaries of a leaf we can optimize this.
    pub fn delete(self: *Node, allocator: Allocator, start: usize, end: usize) !void {
        var to_delete: ?*Node = null;
        var right: ?*Node = null;
        var new_root: ?*Node = null;

        const left, const rest = try self.split(allocator, start);

        if (rest) |rs| {
            to_delete, right = try rs.split(allocator, end - start);
            rs.deinit(allocator);
        }
        if (to_delete) |td| {
            td.deinit(allocator);
        }

        // I think it shouldn't be possible to not have a left here, but to be sure...
        if (left) |l| {
            if (right) |r| {
                try l.join(allocator, r.*);
                r.deinit(allocator);
            }
            new_root = l;
        } else if (right) |r| {
            new_root = r;
        }

        // TODO this is similar to what I do in insert, could extract
        if (new_root) |nr| {
            if (self.left) |l| {
                l.deinit(allocator);
            }
            if (self.right) |r| {
                r.deinit(allocator);
            }
            // self.deinit(allocator);
            self.* = nr.*;
            allocator.destroy(nr);
        }
    }

    /// Get the leaf at the given index, together with the relative pos
    // TODO maybe this should return an optional?
    fn getLeafAtIndex(self: *Node, pos: usize) !struct { *Node, usize } {
        if (self.is_leaf) {
            if (pos > self.size)
                return error.OutOfBounds;
            return .{ self, pos };
        } else {
            if (pos >= self.size) {
                if (self.right) |right| {
                    return right.getLeafAtIndex(pos - self.size);
                } else {
                    return error.OutOfBounds;
                }
            } else {
                if (self.left) |left| {
                    return left.getLeafAtIndex(pos);
                } else {
                    return error.OutOfBounds;
                }
            }
        }
    }

    /// Inserts a String in the given position
    pub fn insert(self: *Node, allocator: Allocator, pos: usize, text: []const u8) !void {
        // If there's some hope to fit the text in a leaf we do a check
        // NOTE disabled for now because this skips the join, thus resulting in a wrong state
        // where the sizes and depths are not correct anymore.
        // if (text.len <= MAX_LEAF_SIZE) {
        //     const target_leaf, const relative_pos = try self.getLeafAtIndex(pos);
        //     std.debug.print("\nInserting {s} at relative pos {}\n", .{ text, relative_pos });

        //     // TODO the problem is that here we're updating without splitting,
        //     // and thus without joining.
        //     // Joining is what takes care of updating the sizes/depths recursively for us.
        //     if (target_leaf.size + text.len <= MAX_LEAF_SIZE) {
        //         if (target_leaf.value) |value| {
        //             std.debug.print("LEAF VAL {s}\n", .{value.constSlice()});
        //             // if (pos != relative_pos and relative_pos == 0)
        //             //     std.debug.print("\n\nINSERTING IN TARGET LEAF AT POS {}\n\n", .{relative_pos});
        //             // For some reason this fails sometimes?
        //             // TODO this doesn't work, I have no idea why
        //             try value.insertSlice(relative_pos, text);
        //             // try value.appendSlice(text);

        //             // TODO is this enough to fix the insertion problem?
        //             target_leaf.size += text.len;
        //             target_leaf.full_size += text.len;
        //             return;
        //         } else {
        //             // NOTE probably not possible?
        //             return error.OutOfBounds;
        //         }
        //     }
        // }

        // This clones the sub nodes, so we have the original, and two halves copies
        const left_split, const right_split = try self.split(allocator, pos);

        var new_root: *Node = undefined;
        if (left_split) |left| {
            // Here we're keeping left as the new root
            new_root = left;
            const right = try Node.fromText(allocator, text);
            defer right.deinit(allocator);
            try new_root.join(allocator, right.*);
        } else {
            new_root = try Node.fromText(allocator, text);
        }

        if (right_split) |right| {
            defer right.deinit(allocator);
            try new_root.join(allocator, right.*);
        }

        // TODO this pattern is happening in multiple places
        if (self.left) |left| {
            left.deinit(allocator);
        }
        if (self.right) |right| {
            right.deinit(allocator);
        }
        if (self.value) |value| {
            allocator.destroy(value);
        }
        self.* = new_root.*;
        allocator.destroy(new_root);
    }

    pub fn append(self: *Node, allocator: Allocator, text: []const u8) !void {
        try self.insert(allocator, self.full_size, text);
    }

    /// Saves in the buffer the value of the Node in the given range.
    pub fn getValueRange(self: Node, buffer: *std.ArrayList(u8), start: usize, end: usize) !void {
        if (self.is_leaf) {
            const len = end - start;
            if (start < self.size and len <= self.size) {
                if (self.value) |value| {
                    try buffer.appendSlice(value.constSlice()[start..end]);
                } else {
                    // TODO should this error?
                    try buffer.appendSlice("");
                }
            }
        } else {
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
    }

    /// Gets the balance ratio of the Node
    pub fn getBalance(self: Node) f32 {
        if (self.is_leaf) {
            return 1;
        } else {
            var left_depth: usize = 1;
            var right_depth: usize = 1;
            if (self.left) |left| {
                left_depth = left.depth;
            }
            if (self.right) |right| {
                right_depth = right.depth;
            }

            return @as(f32, @floatFromInt(@max(left_depth, right_depth))) / @as(f32, @floatFromInt(@min(left_depth, right_depth)));
        }
    }

    /// Checks whether the Node is unbalanced
    /// A certain depth is needed before the check is performed.
    pub fn isUnbalanced(self: Node, rebalance_ratio: f32) bool {
        return self.depth > 4 and self.getBalance() > rebalance_ratio;
    }

    /// Saves in the buffer the whole value of the node
    fn getValue(self: Node, buffer: *std.ArrayList(u8)) !void {
        try self.getValueRange(buffer, 0, self.full_size);
    }

    fn printSpaces(depth: usize) void {
        for (0..depth) |_| {
            std.debug.print(" ", .{});
        }
    }

    /// Print the tree for debugging reasons.
    fn print(self: Node, depth: usize) void {
        printSpaces(depth);

        const value = blk: {
            if (self.value) |value| {
                break :blk value.constSlice();
            } else {
                // NOTE this looks suspicious
                break :blk "";
            }
        };
        if (self.is_leaf) {
            std.debug.print("({}) {s}\n", .{ self.size, value });
        } else {
            std.debug.print("({}|{}|{}):\n", .{ self.size, self.full_size, self.depth });
            if (self.left) |left| {
                printSpaces(depth);
                std.debug.print("L({*}):\n", .{left});
                left.print(depth + 1);
            }

            if (self.right) |right| {
                printSpaces(depth);
                std.debug.print("R({*}):\n", .{right});
                right.print(depth + 1);
            }
        }
    }
};

// test "Creating a balanced Node" {
//     const allocator = std.testing.allocator;

//     const long_text = "Hello, Maurizio! The best text editor in the world.";

//     const node = try Node.fromText(allocator, long_text);
//     defer node.deinit(allocator);

//     var value = std.ArrayList(u8).init(allocator);
//     defer value.deinit();
//     try node.getValue(&value);

//     try std.testing.expectEqualStrings(long_text, value.items);
//     try std.testing.expectEqual(1, node.getBalance());
// }

// test "Catch an unbalanced Node" {
//     const allocator = std.testing.allocator;

//     const leaf1 = try Node.fromText(allocator, "Hello");
//     const leaf2 = try Node.fromText(allocator, "Hello");
//     const leaf3 = try Node.fromText(allocator, "Hello");
//     const leaf4 = try Node.fromText(allocator, "Hello");
//     const leaf5 = try Node.fromText(allocator, "Hello");
//     const leaf6 = try Node.fromText(allocator, "Hello");

//     const right = try Node.createBranch(allocator, leaf2, leaf3);
//     const right2 = try Node.createBranch(allocator, leaf1, right);
//     const right3 = try Node.createBranch(allocator, leaf4, right2);
//     const right4 = try Node.createBranch(allocator, leaf5, right3);

//     const root = try Node.createBranch(allocator, leaf6, right4);
//     defer root.deinit(allocator);

//     try std.testing.expectEqual(5, root.getBalance());
//     try std.testing.expect(root.isUnbalanced(3));
// }

// test "Copying a leaf" {
//     const allocator = std.testing.allocator;

//     const text = "Hello";

//     const node1 = try Node.fromText(allocator, text);
//     const node2 = try Node.copyLeaf(allocator, node1.*);
//     defer node1.deinit(allocator);
//     defer node2.deinit(allocator);

//     // TODO this pattern is fairly annoying
//     var value = std.ArrayList(u8).init(allocator);
//     defer value.deinit();
//     try node1.getValue(&value);

//     var value2 = std.ArrayList(u8).init(allocator);
//     defer value2.deinit();
//     try node2.getValue(&value2);

//     try std.testing.expectEqualStrings(value.items, value2.items);
// }

// test "Splitting a Leaf is memory safe" {
//     const allocator = std.testing.allocator;

//     const text = [_]u8{'a'} ** MAX_LEAF_SIZE;
//     const node = try Node.fromText(allocator, &text);
//     defer node.deinit(allocator);

//     const left, const right = try node.split(allocator, @floor(@as(f32, @floatFromInt(MAX_LEAF_SIZE)) / 2.0));

//     if (left) |l| {
//         if (right) |r| {
//             defer l.deinit(allocator);
//             defer r.deinit(allocator);

//             try std.testing.expect(true);
//             return;
//         }
//     }
//     unreachable;
// }

// test "Splitting a Branch is memory safe" {
//     const allocator = std.testing.allocator;

//     const text = [_]u8{'a'} ** (MAX_LEAF_SIZE * 2);
//     const node = try Node.fromText(allocator, &text);
//     defer node.deinit(allocator);

//     const left, const right = try node.split(allocator, @floor(@as(f32, @floatFromInt(MAX_LEAF_SIZE)) / 2.0));

//     if (left) |l| {
//         if (right) |r| {
//             defer l.deinit(allocator);
//             defer r.deinit(allocator);

//             try std.testing.expect(true);
//             return;
//         }
//     }
//     unreachable;
// }

test "Splitting and rejoining a Node" {
    const allocator = std.testing.allocator;

    const text = "Hello, from Maurizio!";
    const node = try Node.fromText(allocator, text);
    defer node.deinit(allocator);

    const left, const right = try node.split(allocator, 8);
    if (left) |l| {
        if (right) |r| {
            defer l.deinit(allocator);
            defer r.deinit(allocator);

            try l.join(allocator, r.*);

            var value = std.ArrayList(u8).init(allocator);
            defer value.deinit();
            try l.getValue(&value);

            try std.testing.expectEqual(1, l.getBalance());
            try std.testing.expectEqualStrings(text, value.items);
            return;
        }
    }
    unreachable;
}

test "Inserting in a Node" {
    const allocator = std.testing.allocator;

    const text = "Hello, Maurizio!";
    const result_text = "Hello, from Maurizio!";
    const node = try Node.fromText(allocator, text);
    defer node.deinit(allocator);

    // node.print(0);

    // std.debug.print("\n==\n", .{});

    try node.insert(allocator, 7, "from ");

    // node.print(0);

    var value = std.ArrayList(u8).init(allocator);
    defer value.deinit();
    try node.getValue(&value);

    try std.testing.expectEqualStrings(result_text, value.items);
}

// NOTE all these tests are way too arbitrary. Maybe I should compare it against
// the time it takes for an array structure?
// test "Creating a big Node should take less than 15ms" {
//     const allocator = std.testing.allocator;

//     const text = [_]u8{'a'} ** (MAX_LEAF_SIZE * 1000);

//     var timer = try Timer.start();

//     const node = try Node.fromText(allocator, &text);
//     defer node.deinit(allocator);

//     const elapsed: f64 = @floatFromInt(timer.read());

//     std.debug.print("CREATE - Elapsed is: {d:.3}ms\n", .{elapsed / time.ns_per_ms});

//     // This is just an arbitrary value for now, no idea of how long this should take tbh
//     try std.testing.expect(15 > elapsed / time.ns_per_ms);
// }

// test "Inserting in a big Node should take less than 50ms" {
//     const allocator = std.testing.allocator;

//     const text = [_]u8{'a'} ** (MAX_LEAF_SIZE * 1000);

//     const node = try Node.fromText(allocator, &text);
//     defer node.deinit(allocator);

//     const insert = [_]u8{'b'} ** (MAX_LEAF_SIZE * 10);

//     var timer = try Timer.start();

//     try node.insert(allocator, 5000, &insert);

//     const elapsed: f64 = @floatFromInt(timer.read());

//     std.debug.print("INSERT - Elapsed is: {d:.3}ms\n", .{elapsed / time.ns_per_ms});

//     // This is just an arbitrary value for now, no idea of how long this should take tbh
//     try std.testing.expect(50 > elapsed / time.ns_per_ms);
// }

// test "Inserting a single character in a big Node with enough room should take less than 50ms" {
//     const allocator = std.testing.allocator;

//     const text = [_]u8{'a'} ** ((MAX_LEAF_SIZE * 1000) - 2);

//     const node = try Node.fromText(allocator, &text);
//     defer node.deinit(allocator);

//     const insert = [_]u8{'b'};

//     var timer = try Timer.start();

//     try node.insert(allocator, (MAX_LEAF_SIZE * 1000) - 2, &insert);

//     const elapsed: f64 = @floatFromInt(timer.read());

//     std.debug.print("FAST INSERT - Elapsed is: {d:.3}ms\n", .{elapsed / time.ns_per_ms});

//     // This is just an arbitrary value for now, no idea of how long this should take tbh
//     try std.testing.expect(50 > elapsed / time.ns_per_ms);
// }

// NOTE disabled for now
// test "Appending a Node with enough space shouldn't create new nodes" {
//     const allocator = std.testing.allocator;

//     const text_len: usize = @floor(@as(f32, @floatFromInt(MAX_LEAF_SIZE)) / 2.0);

//     const text = [_]u8{'a'} ** text_len;

//     const node = try Node.fromText(allocator, &text);
//     defer node.deinit(allocator);

//     try node.append(allocator, "a");

//     try std.testing.expectEqual(1, node.depth);
// }

test "Deleting from a Node" {
    const allocator = std.testing.allocator;

    const node = try Node.fromText(allocator, "Hello from Maurizio!");
    defer node.deinit(allocator);

    try node.delete(allocator, 5, 10);

    var value = std.ArrayList(u8).init(allocator);
    defer value.deinit();
    try node.getValue(&value);

    try std.testing.expectEqualStrings("Hello Maurizio!", value.items);
}

// NOTE this test was here for my fast insert optimization, which is currently disabled.
// test "Appending on a new leaf" {
//     const allocator = std.testing.allocator;

//     const node = try Node.fromText(allocator, "1234567890");
//     defer node.deinit(allocator);

//     // node.print(0);
//     try node.append(allocator, "a");
//     // node.print(0);

//     // const leaf, const pos = try node.getLeafAtIndex(11);

//     // leaf.print(0);
//     // std.debug.print("\n\nRESULT POS {}\n", .{pos});
//     try node.append(allocator, "b"); // This doesn't update the size correctly, making it fail // This doesn't update the size correctly, making it fail.
//     node.print(0);

//     var value = std.ArrayList(u8).init(allocator);
//     defer value.deinit();
//     try node.getValue(&value);

//     try std.testing.expectEqualStrings("1234567890ab", value.items);
// }
