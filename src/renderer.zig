const std = @import("std");
const vaxis = @import("vaxis");
const Color = vaxis.Cell.Color;
const Theme = @import("theme");
const themes = @import("themes");
const syntax = @import("syntax");

// Fallback mapping system between tree-sitter scope names and vscode theme scope names
pub const FallBack = struct { ts: []const u8, tm: []const u8 };
pub const fallbacks: []const FallBack = &[_]FallBack{
    .{ .ts = "namespace", .tm = "entity.name.namespace" },
    .{ .ts = "type", .tm = "entity.name.type" },
    .{ .ts = "type.defaultLibrary", .tm = "support.type" },
    .{ .ts = "struct", .tm = "storage.type.struct" },
    .{ .ts = "class", .tm = "entity.name.type.class" },
    .{ .ts = "class.defaultLibrary", .tm = "support.class" },
    .{ .ts = "interface", .tm = "entity.name.type.interface" },
    .{ .ts = "enum", .tm = "entity.name.type.enum" },
    .{ .ts = "function", .tm = "entity.name.function" },
    .{ .ts = "function.defaultLibrary", .tm = "support.function" },
    .{ .ts = "method", .tm = "entity.name.function.member" },
    .{ .ts = "macro", .tm = "entity.name.function.macro" },
    .{ .ts = "variable", .tm = "variable.other.readwrite , entity.name.variable" },
    .{ .ts = "variable.readonly", .tm = "variable.other.constant" },
    .{ .ts = "variable.readonly.defaultLibrary", .tm = "support.constant" },
    .{ .ts = "parameter", .tm = "variable.parameter" },
    .{ .ts = "property", .tm = "variable.other.property" },
    .{ .ts = "property.readonly", .tm = "variable.other.constant.property" },
    .{ .ts = "enumMember", .tm = "variable.other.enummember" },
    .{ .ts = "event", .tm = "variable.other.event" },

    // zig
    .{ .ts = "attribute", .tm = "keyword" },
    .{ .ts = "number", .tm = "constant.numeric" },
    .{ .ts = "conditional", .tm = "keyword.control.conditional" },
    .{ .ts = "operator", .tm = "keyword.operator" },
    .{ .ts = "boolean", .tm = "keyword.constant.bool" },
    .{ .ts = "string", .tm = "string.quoted" },
    .{ .ts = "repeat", .tm = "keyword.control.flow" },
    .{ .ts = "field", .tm = "variable" },
};

pub const Renderer = struct {
    win: vaxis.Window,
    theme: *const Theme,
    content: []const u8,
    syntax: *syntax,
    last_pos: usize = 0,
    col: usize = 0,
    row: usize = 0,

    /// Find a scope in the fallback list
    fn findScopeFallback(scope: []const u8) ?[]const u8 {
        for (fallbacks) |fallback| {
            if (fallback.ts.len > scope.len)
                continue;
            if (std.mem.eql(u8, fallback.ts, scope[0..fallback.ts.len]))
                return fallback.tm;
        }
        return null;
    }

    fn findScopeStyleNoFallback(theme: *const Theme, scope: []const u8) ?Theme.Token {
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

    fn getToken(ctx: *@This(), scope: []const u8) ?Theme.Token {
        return if (findScopeFallback(scope)) |tm_scope|
            findScopeStyleNoFallback(ctx.theme, tm_scope) orelse findScopeStyleNoFallback(ctx.theme, scope)
        else
            findScopeStyleNoFallback(ctx.theme, scope);
    }

    fn writeStyled(ctx: *@This(), text: []const u8, style: Theme.Style) !void {
        const style_ = .{
            .fg = Color.rgbFromUint(style.fg orelse 3),
        };

        ctx.win.writeCell(
            ctx.col,
            ctx.row,
            .{
                .style = style_,
                .char = .{ .grapheme = text },
            },
        );

        ctx.col += text.len;
    }

    fn writeLinesStyled(ctx: *@This(), text_: []const u8, style: Theme.Style) !void {
        var text = text_;

        while (std.mem.indexOf(u8, text, "\n")) |pos| {
            try ctx.writeStyled(text[0 .. pos + 1], style);
            ctx.row += 1;
            ctx.col = 0;
            text = text[pos + 1 ..];
        }
        try ctx.writeStyled(text, style);
    }

    pub fn cb(ctx: *@This(), range: syntax.Range, scope: []const u8, _: u32, idx: usize, _: *const syntax.Node) error{Stop}!void {
        if (idx > 0) return;

        if (ctx.last_pos < range.start_byte) {
            const before_segment = ctx.content[ctx.last_pos..range.start_byte];
            ctx.writeLinesStyled(before_segment, ctx.theme.editor) catch return error.Stop;
            ctx.last_pos = range.start_byte;
        }

        if (range.start_byte < ctx.last_pos) return;

        const scope_segment = ctx.content[range.start_byte..range.end_byte];

        if (ctx.getToken(scope)) |token| {
            ctx.writeLinesStyled(scope_segment, token.style) catch return error.Stop;
        } else {
            ctx.writeLinesStyled(scope_segment, ctx.theme.editor) catch return error.Stop;
        }

        ctx.last_pos = range.end_byte;
    }
};
