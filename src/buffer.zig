const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Rope = @import("rope.zig").Rope;
const Key = vaxis.Key;
const Vaxis = vaxis.Vaxis;
const Event = @import("main.zig").Event;

const treez = @import("treez");

const syntax = @import("syntax");
const Theme = @import("theme");
const themes = @import("themes");

// TODO going to new lines is slightly bugged
// TODO when crashing the terminal is not returned to normal

const XY = struct {
    x: usize = 0,
    y: usize = 0,
};

// TODO insipred by zat, I will have to rewrite all of this.
const Ctx = struct {
    win: vaxis.Window,
    cursor: *Cursor,
    theme: *const Theme,
    content: []const u8,
    syntax: *syntax,

    fn getToken(theme: *const Theme, scope: []const u8) ?Theme.Token {
        // std.debug.print("\nGETTING TOKEN {s}\n", .{scope});
        var idx = theme.tokens.len - 1;
        var done = false;
        while (!done) : (if (idx == 0) {
            done = true;
        } else {
            idx -= 1;
        }) {
            const token = theme.tokens[idx];
            const name = themes.scopes[token.id];
            if (name.len > scope.len)
                continue;
            if (std.mem.eql(u8, name, scope[0..name.len]))
                return token;
        }
        return null;
    }

    fn writeStyle(ctx: *@This(), text: []const u8, range: syntax.Range, style: Theme.Style) !void {
        // It looks like the token, and range are ok
        _ = style;
        const style_ = .{
            .fg = .{ .index = 8 },
            // .fg = Color.rgbFromUint(style.fg orelse 3),
            // .bg = Color.rgbFromUint(style.bg orelse 3),
        };

        // std.debug.print("\n applying style {} to {} {}\n", .{ style_, range.start_byte, range.end_byte });

        // const cell = ctx.win.readCell(0, 0);

        // if (cell) |c| {
        //     ctx.win.writeCell(0, 0, .{ .style = style_, .char = c.char });
        // }

        // TODO maybe I can do this not char by char...
        // for (range.start_byte..range.end_byte) |pos| {
        // const xy = ctx.cursor.customPosToXY(pos);

        const xy = ctx.cursor.customPosToXY(range.start_byte);
        // std.debug.print("\norig fg {?} vax fg {} pos {} XY {}\n", .{ style.fg, style_.fg, pos, xy });

        // const cell = ctx.win.readCell(xy.x, xy.y);

        // const relative_pos = pos - range.start_byte;
        // if (cell) |c| {
        ctx.win.writeCell(
            xy.x,
            xy.y,
            .{
                .style = style_,
                .char = .{ .grapheme = text },
            },
        );
        // }
        // }
    }

    fn cb(ctx: *@This(), range: syntax.Range, scope: []const u8, id: u32, idx: usize, _: *const syntax.Node) error{Stop}!void {
        _ = idx;
        _ = id;
        const scope_segment = ctx.content[range.start_byte..range.end_byte];
        // _ = scope;
        if (getToken(ctx.theme, scope)) |token| {
            ctx.writeStyle(scope_segment, range, token.style) catch return error.Stop;
        } else {
            // std.debug.print("\n NO STYLE \n", .{});
            ctx.writeStyle(scope_segment, range, ctx.theme.editor) catch return error.Stop;
        }

        return;
    }

    // fn getStyle(theme: *const Theme, scope: []const u8, id: u32) ?Theme.Token {
    //     _ = id;
    //     return findScopeStyle(theme, scope) orelse null;
    // }

    // fn findScopeStyle(theme: *const Theme, scope: []const u8) ?Theme.Token {
    //     // return if (findScopeFallback(scope)) |tm_scope|
    //     //     findScopeStyleNoFallback(theme, tm_scope) orelse findScopeStyleNoFallback(theme, scope)
    //     // else
    //     return findScopeStyleNoFallback(theme, scope);
    // }

    // fn findScopeStyleNoFallback(theme: *const Theme, scope: []const u8) ?Theme.Token {
    //     var idx = theme.tokens.len - 1;
    //     var done = false;
    //     while (!done) : (if (idx == 0) {
    //         done = true;
    //     } else {
    //         idx -= 1;
    //     }) {
    //         const token = theme.tokens[idx];
    //         const name = themes.scopes[token.id];
    //         if (token.id == 189) {
    //             // std.debug.print("\nscopes {any}", .{themes.scopes});
    //             //     std.debug.print("\nTOKEN {any}", .{theme.tokens});
    //         }
    //         if (name.len > scope.len)
    //             continue;
    //         if (std.mem.eql(u8, name, scope[0..name.len])) {
    //             // std.debug.print("\n token name {s} {s}\n", .{ name, scope });
    //             return token;
    //         }
    //     }
    //     return null;
    // }

    // fn findScopeFallback(scope: []const u8) ?[]const u8 {
    //     for (fallbacks) |fallback| {
    //         if (fallback.ts.len > scope.len)
    //             continue;
    //         if (std.mem.eql(u8, fallback.ts, scope[0..fallback.ts.len]))
    //             return fallback.tm;
    //     }
    //     return null;
    // }
};

// NOTE the whole way I'm handling movement is completely inefficient.
const Cursor = struct {
    xy: XY,
    // The actual position in the Rope
    pos: usize = 0,
    // TODO not used right now
    // shape: Cell.CursorShape = .block,
    // The grapheme index of the cursor. Am I actually using it?
    // grapheme_idx: usize = 0,
    lines: *Lines,

    pub fn updateXY(self: *Cursor) void {
        self.xy = self.posToXY();
    }

    pub fn posToXY(self: *Cursor) XY {
        return self.customPosToXY(self.pos);
        // var line_index: usize = 0;
        // var remaining_pos = self.pos;
        // for (self.lines.items, 0..) |line_length, index| {
        //     if (remaining_pos > line_length) {
        //         remaining_pos -= line_length;
        //     } else {
        //         line_index = index;
        //         break;
        //     }
        // }

        // return XY{ .x = remaining_pos, .y = line_index };
    }

    // TODO Better name?
    pub fn customPosToXY(self: *Cursor, pos: usize) XY {
        var line_index: usize = 0;
        var remaining_pos = pos;
        for (self.lines.items, 0..) |line_length, index| {
            if (remaining_pos > line_length) {
                remaining_pos -= line_length;
            } else {
                line_index = index;
                break;
            }
        }

        return XY{ .x = remaining_pos, .y = line_index };
    }

    pub fn xYToPos(self: *Cursor, xy: XY) usize {
        var curr_pos: usize = 0;
        for (self.lines.items, 0..) |line_length, i| {
            if (i < xy.y) {
                curr_pos += line_length;
            } else {
                curr_pos += xy.x;
                break;
            }
        }
        return curr_pos;
    }

    // Get the current pos, get the target pos, find the difference
    pub fn toNewLine(self: *Cursor) void {
        const xy = self.posToXY();
        const target_x = 0;
        const target_y = xy.y + 1;
        self.pos = self.xYToPos(XY{ .x = target_x, .y = target_y });
    }

    pub fn moveRight(self: *Cursor) void {
        self.pos += 1;
    }

    pub fn moveLeft(self: *Cursor) void {
        self.pos -= 1;
    }

    pub fn moveUp(self: *Cursor) void {
        const xy = self.posToXY();
        if (xy.y > 0)
            self.pos = self.xYToPos(XY{ .x = xy.x, .y = xy.y - 1 });
    }

    pub fn moveDown(self: *Cursor) void {
        const xy = self.posToXY();
        self.pos = self.xYToPos(XY{ .x = xy.x, .y = xy.y + 1 });
    }
};

/// An attempt at keeping track of how long all lines are.
// const Lines = struct {
//     allocator: std.mem.Allocator,
//     rows: std.ArrayList(usize), // Should we have more length?

//     // pub fn init(allocator: std.mem.Allocator) !RowsMeta {
//     //   const rows = std.ArrayList.init(allocator);

//     // }
// };

const Lines = std.ArrayList(usize);

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    rope: *Rope,
    // I'm using this to go around the value lifetime, but it feels so bad.
    rope_l: std.ArrayList(u8),
    cursor: *Cursor,
    lines: *Lines,

    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        return Buffer.init(allocator, "");
    }

    pub fn init(allocator: std.mem.Allocator, content: []const u8) !Buffer {
        const rope = try allocator.create(Rope);
        rope.* = try Rope.init(allocator, "");
        try rope.append(content);
        const lines = try allocator.create(Lines);
        lines.* = Lines.init(allocator);
        const cursor = try allocator.create(Cursor);
        const xy: XY = XY{ .x = 0, .y = 0 };
        cursor.* = Cursor{ .lines = lines, .xy = xy };
        const rope_l = std.ArrayList(u8).init(allocator);

        return .{
            .allocator = allocator,
            .rope = rope,
            .cursor = cursor,
            .rope_l = rope_l,
            .lines = lines,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.destroy(self.cursor);
        self.lines.deinit();
        self.allocator.destroy(self.lines);
        self.rope.deinit();
        self.rope_l.deinit();
        self.allocator.destroy(self.rope);
    }

    pub fn draw(self: *Buffer, vx: Vaxis, win: vaxis.Window) !void {
        const rope_content = try self.rope.getValue();
        defer self.allocator.free(rope_content);
        // This can't be performant at all
        self.rope_l.clearAndFree();
        try self.rope_l.appendSlice(rope_content);

        const content = self.rope_l.items;

        var msg_iter = vx.unicode.graphemeIterator(content);

        // I guess the idea here is:
        // - store the lines layout
        // - get the current position of the cursor
        // -

        // Reinitialize the lines
        self.lines.clearAndFree();

        // TODO ok so this builds the parser, which I have then to use somehow.
        // https://github.com/neurocyte/zat/blob/master/src/main.zig
        // it passes it together with theme to `render_file_type`.
        const lang = try self.rope.get_parser();
        // std.debug.print("parser\n\n {s} {s} {s}", .{ parser.file_type.name, parser.file_type.highlights, parser.file_type.icon });
        defer lang.destroy();

        const theme = blk: {
            for (themes.themes) |theme| {
                if (std.mem.eql(u8, theme.name, "ayu-dark")) {
                    break :blk theme;
                }
            }
            unreachable;
        };
        // std.debug.print("theme {any}\n", .{theme});
        // _ = theme;

        // std.debug.print("\n{any}\n", .{theme});

        const Pos = struct { x: usize = 0, y: usize = 0 };
        var pos: Pos = .{};
        var byte_index: usize = 0;

        var index: usize = 0;
        while (msg_iter.next()) |grapheme| {
            const cluster = content[grapheme.offset..][0..grapheme.len];
            defer byte_index += cluster.len;

            const new_line = "\n";

            // Why isn't the new line char working? :/
            if (std.mem.eql(u8, cluster, new_line)) {
                if (index == content.len - 1) {
                    break;
                }
                try self.lines.append(index);
                pos.y += 1;
                pos.x = 0;
                continue;
            }

            self.cursor.updateXY();

            const width = win.gwidth(cluster);
            defer pos.x +|= width;

            // TODO this styling is all very random for now
            // const style = theme.editor_selection;

            const start_row: u32 = @intCast(pos.y);
            const start_column: u32 = @intCast(pos.x);

            // Naive range for now
            const range: ?syntax.Range = .{
                .start_point = .{ .row = start_row, .column = start_column },
                .end_point = .{ .row = start_row, .column = start_column + 10 },
                // .start_point = .{ .row = @as(u32, pos.x), .column = @as(u32, pos.y) },
                // .end_point = .{ .row = @as(u32, pos.x), .column = @as(u32, pos.y) + 1 },
                .start_byte = 0,
                .end_byte = 0,
            };

            // std.debug.print("RANGE: {any}\n", .{range});

            var ctx: Ctx = .{
                .win = win,
                .theme = &theme,
                .content = content,
                .syntax = lang,
                .cursor = self.cursor,
            };

            _ = range;
            try lang.render(&ctx, Ctx.cb, null);

            // NOTE: temporarily disabled just to see what happens when trying to write directly with the tokens
            // std.debug.print("POS {any}, COL {any}\n\n", .{ pos, ctx.fg });

            // win.writeCell(pos.x, pos.y, .{
            //     .char = .{
            //         .grapheme = cluster,
            //         .width = width,
            //     },
            // });

            index += 1;
            // I don't thiColor'm using this
            // if (index == self.cursor.grapheme_idx) self.cursor.x = pos.x;
        }
    }

    pub fn handleKey(self: *Buffer, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches(Key.backspace, .{})) {
                    // self.deleteBeforeCursor();
                    // To delete properly I have to to go from .{x, y} to pos, which I can't do right now.
                    // try self.rope.deleteLast();
                    // TODO don't try to go on new lines!
                    try self.rope.delete(self.cursor.pos - 1, self.cursor.pos);
                    self.cursor.moveLeft();
                } else if (key.matches(Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) {
                    // self.deleteAfterCursor();
                } else if (key.matches(Key.left, .{}) or key.matches('b', .{ .ctrl = true })) {
                    self.cursor.moveLeft();
                } else if (key.matches(Key.right, .{}) or key.matches('f', .{ .ctrl = true })) {
                    self.cursor.moveRight();
                } else if (key.matches(Key.up, .{})) {
                    self.cursor.moveUp();
                } else if (key.matches(Key.down, .{})) {
                    self.cursor.moveDown();
                } else if (key.matches('a', .{ .ctrl = true }) or key.matches(Key.home, .{})) {
                    // self.buf.moveGapLeft(self.buf.firstHalf().len);
                } else if (key.matches('e', .{ .ctrl = true }) or key.matches(Key.end, .{})) {
                    // self.buf.moveGapRight(self.buf.secondHalf().len);
                } else if (key.matches('k', .{ .ctrl = true })) {
                    // self.deleteToEnd();
                } else if (key.matches('u', .{ .ctrl = true })) {
                    // self.deleteToStart();
                } else if (key.matches('b', .{ .alt = true }) or key.matches(Key.left, .{ .alt = true })) {
                    // self.moveBackwardWordwise();
                } else if (key.matches('f', .{ .alt = true }) or key.matches(Key.right, .{ .alt = true })) {
                    // self.moveForwardWordwise();
                } else if (key.matches('w', .{ .ctrl = true }) or key.matches(Key.backspace, .{ .alt = true })) {
                    // self.deleteWordBefore();
                } else if (key.matches('d', .{ .alt = true })) {
                    // self.deleteWordAfter();
                } else if (key.matches('s', .{ .ctrl = true })) {
                    const file = try std.fs.cwd().createFile(
                        "test_output.md",
                        .{},
                    );
                    defer file.close();
                    const content = try self.rope.getValue();
                    defer self.allocator.free(content);
                    _ = try file.writeAll(content);
                } else if (key.matches(Key.enter, .{})) {
                    try self.rope.append("\n");
                    self.cursor.toNewLine();
                } else if (key.text) |text| {
                    try self.rope.append(text);
                    self.cursor.moveRight();
                }
            },
            else => {},
        }
    }
};
