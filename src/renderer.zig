const std = @import("std");
const vaxis = @import("vaxis");
const Color = vaxis.Cell.Color;
const Theme = @import("theme");
const themes = @import("themes");
const syntax = @import("syntax");
const StyleCache = @import("main.zig").StyleCache;

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

/// TODO this in zat exposes functions to set/unset styles
pub const Renderer = struct {
    win: vaxis.Window,
    theme: *const Theme,
    content: []const u8,
    syntax: *syntax,
    style_cache: *StyleCache,
    last_pos: usize = 0,
    col: usize = 0,
    row: usize = 0,
    current_line: usize,
    start_line: usize,
    end_line: usize,

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

    // TODO this is awkward, maybe the style cache should be its own struct
    pub fn styleCacheLookup(style_cache: *StyleCache, theme: *const Theme, scope: []const u8, id: u32) !?Theme.Token {
        return if (style_cache.get(id)) |sty| ret: {
            break :ret sty;
        } else ret: {
            const sty = findScopeStyle(theme, scope) orelse null;
            // skipping cache since it's broken
            // TODO: I think I need to cache the style for each theme?
            // try style_cache.put(id, sty);
            break :ret sty;
        };
    }

    fn findScopeStyle(theme: *const Theme, scope: []const u8) ?Theme.Token {
        return if (findScopeFallback(scope)) |tm_scope|
            findScopeStyleNoFallback(theme, tm_scope) orelse findScopeStyleNoFallback(theme, scope)
        else
            findScopeStyleNoFallback(theme, scope);
    }

    fn writeStyled(ctx: *@This(), text: []const u8, style: Theme.Style) !void {
        if (!(ctx.start_line <= ctx.current_line and ctx.current_line <= ctx.end_line)) return;

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
            // TODO can I merge these into one?
            ctx.row += 1;
            ctx.current_line += 1;
            ctx.col = 0;
            text = text[pos + 1 ..];
        }
        try ctx.writeStyled(text, style);
    }

    // TODO this doesn't set the background color back...

    pub fn cb(ctx: *@This(), range: syntax.Range, scope: []const u8, id: u32, idx: usize, _: *const syntax.Node) error{Stop}!void {
        if (idx > 0) return;

        if (ctx.last_pos < range.start_byte) {
            const before_segment = ctx.content[ctx.last_pos..range.start_byte];
            ctx.writeLinesStyled(before_segment, ctx.theme.editor) catch return error.Stop;
            ctx.last_pos = range.start_byte;
        }

        if (range.start_byte < ctx.last_pos) return;

        const scope_segment = ctx.content[range.start_byte..range.end_byte];
        const cached_style = styleCacheLookup(ctx.style_cache, ctx.theme, scope, id) catch {
            return error.Stop;
        };

        if (cached_style) |token| {
            ctx.writeLinesStyled(scope_segment, token.style) catch return error.Stop;
        } else {
            ctx.writeLinesStyled(scope_segment, ctx.theme.editor) catch return error.Stop;
        }

        ctx.last_pos = range.end_byte;
    }
};
