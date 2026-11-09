const std = @import("std");
const d = @import("doc_builder.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const printer = @import("printer.zig");
const report = @import("report.zig");
const Node = parser.Node;
const Profile = struct { name: []const u8, width: usize = 80, indent: usize = 4, kr: bool = true, operators: bool = true, keyword: bool = true, cases: bool = true, braces: bool = false, blank: usize = 1, parens: bool = true, comment: usize = 0 };
const Source = struct { header: []const u8, name: []const u8, profile: []const u8, lines: std.ArrayList([]const u8) = .empty };
const Builder = struct {
    tokens: []lexer.Token, profile: Profile,
    first_function: ?*d.Doc = null, function_name: []const u8 = "",
    fn S(self: Builder) *d.Doc { return d.text(if (self.profile.operators) " " else ""); }
    fn K(self: Builder) *d.Doc { return d.text(if (self.profile.keyword) " " else ""); }
    fn O(self: Builder) *d.Doc { return d.marker(if (self.profile.operators) .line else .softline); }
    fn sep(self: Builder, blank: usize) *d.Doc { var separators: std.ArrayList(*d.Doc) = .empty; for (0..1 + @min(blank, self.profile.blank)) |_| d.append(*d.Doc, &separators, d.marker(.hardline)); return d.sequence(separators.items); }
    fn pre(self: Builder, token: usize) usize { const t = self.tokens[token]; return if (t.leading.items.len > 0) t.leading.items[0].blank else t.blank; }
    fn comments(self: Builder, comment_list: []const lexer.Comment, next_blank: ?usize) *d.Doc {
        var docs: std.ArrayList(*d.Doc) = .empty;
        for (comment_list, 0..) |comment, i| { d.append(*d.Doc, &docs, d.text(comment.value)); const b: ?usize = if (i + 1 < comment_list.len) comment_list[i + 1].blank else next_blank; if (b) |blank| d.append(*d.Doc, &docs, if (comment.own) self.sep(blank) else d.text(" ")); }
        return d.sequence(docs.items);
    }
    fn suffix(self: Builder, token: usize) *d.Doc { const trailing_comments = self.tokens[token].trailing.items; var values: std.ArrayList([]const u8) = .empty; for (trailing_comments) |c| d.append([]const u8, &values, c.value); return if (values.items.len == 0) d.text("") else d.create(d.Doc, .{ .kind = .suffix, .value = std.mem.join(d.allocator, " ", values.items) catch @panic("allocation failed") }); }
    fn T(self: Builder, token: usize) *d.Doc { return self.tokenComments(token, self.tokens[token].leading.items); }
    fn tokenComments(self: Builder, token: usize, leading: []const lexer.Comment) *d.Doc { const t = self.tokens[token]; return d.sequence(&.{self.comments(leading, t.blank), d.text(t.value), self.suffix(token)}); }
    fn opened(self: *Builder, original: *Node, k: usize) *Node {
        var n = original;
        while (self.profile.parens and n.kind == .paren and parser.level(n.children[0]) >= k and self.tokens[n.first].leading.items.len == 0 and self.tokens[n.last].leading.items.len == 0) {
            const inner = n.children[0]; var front: std.ArrayList(lexer.Comment) = .empty;
            for (self.tokens[n.first].trailing.items) |c| d.append(lexer.Comment, &front, c); for (self.tokens[inner.first].trailing.items) |c| d.append(lexer.Comment, &front, c); self.tokens[inner.first].trailing = front;
            for (self.tokens[n.last].trailing.items) |c| d.append(lexer.Comment, &self.tokens[inner.last].trailing, c);
            self.tokens[n.first].trailing = .empty; self.tokens[n.last].trailing = .empty; n = inner;
        }
        return n;
    }
    fn list(self: *Builder, n: *Node) *d.Doc {
        if (n.children.len == 0) return d.sequence(&.{self.T(n.first), self.T(n.last)});
        var list_body: std.ArrayList(*d.Doc) = .empty; d.append(*d.Doc, &list_body, d.marker(.softline));
        for (n.children, 0..) |item, i| { if (i > 0) { d.append(*d.Doc, &list_body, self.T(n.tokens[i])); d.append(*d.Doc, &list_body, d.marker(.line)); } d.append(*d.Doc, &list_body, self.construct(item)); }
        if (d.eq(self.tokens[n.first].value, "{")) { d.append(*d.Doc, &list_body, d.conditional(",", "")); const last_comma = n.tokens[n.tokens.len - 2]; if (self.tokens[last_comma].trailing_comma) d.append(*d.Doc, &list_body, self.suffix(last_comma)); }
        var force = false; for (self.tokens[n.first..n.last]) |token| if (token.trailing.items.len > 0) { force = true; break; };
        return d.child(.group, d.sequence(&.{if (force) d.marker(.break_parent) else d.text(""), self.T(n.first), d.nest(self.profile.indent, d.sequence(list_body.items)), d.marker(.softline), self.T(n.last)}));
    }
    fn block(self: *Builder, n: *Node, prefix: ?*d.Doc, switch_body: bool) *d.Doc {
        const close = self.tokens[n.last]; var split: usize = 0; for (close.leading.items, 0..) |c, i| if (c.own) { split = i + 1; };
        const h = close.leading.items[0..split]; const g = close.leading.items[split..]; var block_body: std.ArrayList(*d.Doc) = .empty;
        const items = if (switch_body) n.children[1..] else n.children;
        for (items, 0..) |item, i| { d.append(*d.Doc, &block_body, if (i == 0) d.marker(.hardline) else self.sep(self.pre(item.first))); d.append(*d.Doc, &block_body, self.construct(item)); }
        if (h.len > 0) { d.append(*d.Doc, &block_body, if (items.len > 0) self.sep(h[0].blank) else d.marker(.hardline)); d.append(*d.Doc, &block_body, self.comments(h, null)); }
        const opening = prefix orelse self.T(n.first);
        if (block_body.items.len == 0) return d.sequence(&.{opening, self.tokenComments(n.last, g)});
        const indent = if (switch_body and !self.profile.cases) 0 else self.profile.indent;
        return d.sequence(&.{opening, d.nest(indent, d.sequence(block_body.items)), d.marker(.hardline), self.tokenComments(n.last, g)});
    }
    fn body(self: *Builder, n: *Node) *d.Doc {
        if (n.kind == .block) return d.sequence(&.{if (self.profile.kr) d.text(" ") else d.marker(.hardline), self.block(n, null, false)});
        if (self.profile.braces) return d.sequence(&.{if (self.profile.kr) d.text(" ") else d.marker(.hardline), d.text("{"), d.nest(self.profile.indent, d.sequence(&.{d.marker(.hardline), self.construct(n)})), d.marker(.hardline), d.text("}")});
        return d.nest(self.profile.indent, d.sequence(&.{d.marker(.hardline), self.construct(n)}));
    }
    fn postfixPart(self: *Builder, n: *Node) *d.Doc { return switch (n.kind) { .call => self.list(n.children[1]), .index => d.sequence(&.{self.T(n.tokens[0]), self.expression(n.children[1], 0), self.T(n.tokens[1])}), .member => d.sequence(&.{self.T(n.tokens[0]), self.T(n.tokens[1])}), else => unreachable }; }
    fn expression(self: *Builder, original: *Node, k: usize) *d.Doc {
        const n = self.opened(original, k);
        switch (n.kind) {
            .atom => return self.T(n.first),
            .paren => return d.sequence(&.{self.T(n.first), self.expression(n.children[0], 0), self.T(n.last)}),
            .unary => return d.sequence(&.{self.T(n.tokens[0]), self.expression(n.children[0], 8)}),
            .binary => {
                const p = parser.level(n); var chain: std.ArrayList(*Node) = .empty; var x = n;
                while (x.kind == .binary and parser.level(x) == p) { d.append(*Node, &chain, x); x = self.opened(x.children[0], p); }
                var tail: std.ArrayList(*d.Doc) = .empty; var i = chain.items.len; while (i > 0) { i -= 1; const b = chain.items[i]; d.append(*d.Doc, &tail, self.O()); d.append(*d.Doc, &tail, self.T(b.tokens[0])); d.append(*d.Doc, &tail, self.S()); d.append(*d.Doc, &tail, self.expression(b.children[1], p + 1)); }
                return d.child(.group, d.sequence(&.{self.expression(x, p), d.nest(self.profile.indent, d.sequence(tail.items))}));
            },
            .conditional => {
                var tail: std.ArrayList(*d.Doc) = .empty; var x = n;
                while (true) { d.append(*d.Doc, &tail, self.O()); d.append(*d.Doc, &tail, self.T(x.tokens[0])); d.append(*d.Doc, &tail, self.S()); d.append(*d.Doc, &tail, self.expression(x.children[1], 0)); d.append(*d.Doc, &tail, self.O()); d.append(*d.Doc, &tail, self.T(x.tokens[1])); d.append(*d.Doc, &tail, self.S()); const g = self.opened(x.children[2], 0); if (g.kind != .conditional) { d.append(*d.Doc, &tail, self.expression(g, 0)); break; } d.append(*d.Doc, &tail, self.expression(g.children[0], 1)); x = g; }
                return d.child(.group, d.sequence(&.{self.expression(n.children[0], 1), d.nest(self.profile.indent, d.sequence(tail.items))}));
            },
            .call, .index, .member => {
                var chain: std.ArrayList(*Node) = .empty; var head = n;
                while (head.kind == .call or head.kind == .index or head.kind == .member) { d.append(*Node, &chain, head); head = self.opened(head.children[0], 8); }
                std.mem.reverse(*Node, chain.items); var segment: usize = 0; var first_call: ?usize = null; var call_segments: usize = 0; var seen = false;
                for (chain.items, 0..) |x, i| { if (x.kind == .member) { segment += 1; seen = false; } if (x.kind == .call and segment > 0 and !seen) { seen = true; call_segments += 1; if (first_call == null) { var j = i; while (chain.items[j].kind != .member) j -= 1; first_call = j; } } }
                var prefix: std.ArrayList(*d.Doc) = .empty; d.append(*d.Doc, &prefix, self.expression(head, 8)); var tail: std.ArrayList(*d.Doc) = .empty;
                for (chain.items, 0..) |x, i| { if (call_segments >= 2 and i >= first_call.?) { if (x.kind == .member) d.append(*d.Doc, &tail, d.marker(.softline)); d.append(*d.Doc, &tail, self.postfixPart(x)); } else d.append(*d.Doc, &prefix, self.postfixPart(x)); }
                if (call_segments < 2) return d.sequence(prefix.items);
                d.append(*d.Doc, &prefix, d.nest(self.profile.indent, d.sequence(tail.items))); return d.child(.group, d.sequence(prefix.items));
            },
            else => return self.construct(n),
        }
    }
    fn construct(self: *Builder, n: *Node) *d.Doc {
        switch (n.kind) {
            .atom, .paren, .unary, .binary, .conditional, .call, .index, .member => return self.expression(n, 0),
            .empty => return d.text(""),
            .list => return self.list(n),
            .parameter => { var docs: std.ArrayList(*d.Doc) = .empty; d.append(*d.Doc, &docs, self.T(n.tokens[0])); d.append(*d.Doc, &docs, d.text(" ")); for (n.tokens[1..]) |t| d.append(*d.Doc, &docs, self.T(t)); return d.sequence(docs.items); },
            .dimension => return d.sequence(&.{self.T(n.first), if (n.children.len > 0) self.expression(n.children[0], 0) else d.text(""), self.T(n.last)}),
            .declaration => {
                var docs: std.ArrayList(*d.Doc) = .empty; d.append(*d.Doc, &docs, self.T(n.tokens[0])); d.append(*d.Doc, &docs, d.text(" ")); d.append(*d.Doc, &docs, self.T(n.tokens[1]));
                for (n.children) |x| { if (x.kind != .dimension) { d.append(*d.Doc, &docs, self.S()); d.append(*d.Doc, &docs, self.T(n.tokens[2])); d.append(*d.Doc, &docs, self.S()); } d.append(*d.Doc, &docs, self.construct(x)); }
                if (d.eq(self.tokens[n.last].value, ";")) d.append(*d.Doc, &docs, self.T(n.last)); return d.sequence(docs.items);
            },
            .function => return d.sequence(&.{self.T(n.tokens[0]), d.text(" "), self.T(n.tokens[1]), self.list(n.children[0]), d.marker(.hardline), self.block(n.children[1], null, false)}),
            .block => return self.block(n, null, false),
            .assignment => return d.sequence(&.{self.expression(n.children[0], 0), self.S(), self.T(n.tokens[0]), self.S(), self.expression(n.children[1], 0)}),
            .simple => return d.sequence(&.{self.construct(n.children[0]), if (n.tokens.len > 0) self.T(n.tokens[0]) else d.text("")}),
            .return_stmt, .transfer => return d.sequence(&.{self.T(n.tokens[0]), if (n.children.len > 0) d.sequence(&.{d.text(" "), self.expression(n.children[0], 0)}) else d.text(""), self.T(n.tokens[1])}),
            .while_stmt, .if_stmt => {
                var docs: std.ArrayList(*d.Doc) = .empty; for ([_]*d.Doc{self.T(n.tokens[0]), self.K(), self.T(n.tokens[1]), self.expression(n.children[0], 0), self.T(n.tokens[2]), self.body(n.children[1])}) |x| d.append(*d.Doc, &docs, x);
                if (n.children.len == 3) { d.append(*d.Doc, &docs, if (self.profile.kr and (n.children[1].kind == .block or self.profile.braces)) d.text(" ") else d.marker(.hardline)); d.append(*d.Doc, &docs, self.T(n.tokens[3])); const other = n.children[2]; d.append(*d.Doc, &docs, if (other.kind == .if_stmt) d.sequence(&.{d.text(" "), self.construct(other)}) else self.body(other)); }
                return d.sequence(docs.items);
            },
            .for_stmt => {
                var inner: std.ArrayList(*d.Doc) = .empty; d.append(*d.Doc, &inner, self.construct(n.children[0])); d.append(*d.Doc, &inner, self.T(n.tokens[2])); if (n.children[1].kind != .empty) { d.append(*d.Doc, &inner, d.marker(.line)); d.append(*d.Doc, &inner, self.expression(n.children[1], 0)); } d.append(*d.Doc, &inner, self.T(n.tokens[3])); if (n.children[2].kind != .empty) { d.append(*d.Doc, &inner, d.marker(.line)); d.append(*d.Doc, &inner, self.construct(n.children[2])); }
                return d.sequence(&.{self.T(n.tokens[0]), self.K(), self.T(n.tokens[1]), d.child(.group, d.child(.align, d.sequence(inner.items))), self.T(n.tokens[4]), self.body(n.children[3])});
            },
            .switch_stmt => { const prefix = d.sequence(&.{self.T(n.tokens[0]), self.K(), self.T(n.tokens[1]), self.expression(n.children[0], 0), self.T(n.tokens[2]), if (self.profile.kr) d.text(" ") else d.marker(.hardline), self.T(n.tokens[3])}); return self.block(n, prefix, true); },
            .clause => {
                const iscase = d.eq(self.tokens[n.first].value, "case"); var docs: std.ArrayList(*d.Doc) = .empty; d.append(*d.Doc, &docs, self.T(n.tokens[0])); if (iscase) { d.append(*d.Doc, &docs, d.text(" ")); d.append(*d.Doc, &docs, self.expression(n.children[0], 0)); } d.append(*d.Doc, &docs, self.T(n.tokens[1])); var bodydocs: std.ArrayList(*d.Doc) = .empty;
                for (n.children[@intFromBool(iscase)..], 0..) |x, i| { d.append(*d.Doc, &bodydocs, if (i == 0) d.marker(.hardline) else self.sep(self.pre(x.first))); d.append(*d.Doc, &bodydocs, self.construct(x)); } d.append(*d.Doc, &docs, d.nest(self.profile.indent, d.sequence(bodydocs.items))); return d.sequence(docs.items);
            },
        }
    }
    fn whole(self: *Builder, items: []const *Node) *d.Doc {
        var docs: std.ArrayList(*d.Doc) = .empty;
        for (items, 0..) |x, i| {
            if (i > 0) d.append(*d.Doc, &docs, self.sep(self.pre(x.first)));
            const doc = self.construct(x); d.append(*d.Doc, &docs, doc);
            if (x.kind == .function and self.first_function == null) { self.first_function = doc; self.function_name = self.tokens[x.tokens[1]].value; }
        }
        const closing_comments = self.tokens[self.tokens.len - 1].leading.items;
        if (closing_comments.len > 0) { if (items.len > 0) d.append(*d.Doc, &docs, self.sep(closing_comments[0].blank)); d.append(*d.Doc, &docs, self.comments(closing_comments, null)); }
        return d.sequence(docs.items);
    }
};
const Result = struct { lines: []const []const u8, failure: ?lexer.Failure = null, root: ?*d.Doc = null, function: ?*d.Doc = null, function_name: []const u8 = "", comments: usize = 0 };
fn format(lines: []const []const u8, profile: Profile) Result {
    const lexed = lexer.scan(lines); if (lexed.failure) |e| return .{ .lines = lines, .failure = e };
    var p = parser.Parser{ .tokens = lexed.tokens }; const items = p.program() catch return .{ .lines = lines, .failure = p.failure };
    for (lexed.tokens) |token| for (token.leading.items) |comment| { if ((comment.own and !token.allowed) or token.trailing_comma) return .{ .lines = lines, .failure = .{ .position = comment.position, .message = "comment not allowed here" } }; };
    var builder = Builder{ .tokens = lexed.tokens, .profile = profile }; const root = builder.whole(items);
    return .{ .lines = if (items.len == 0 and lexed.tokens[lexed.tokens.len - 1].leading.items.len == 0) &.{} else printer.layout(root, profile.width, profile.comment), .root = root, .comments = lexed.comments, .function = builder.first_function, .function_name = builder.function_name };
}
fn linesOf(s: []const u8) []const []const u8 { var list: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, s, '\n'); while (it.next()) |line| d.append([]const u8, &list, line); return list.items[0 .. list.items.len - 1]; }
fn read(io: std.Io, path: []const u8) ![]const u8 { return std.Io.Dir.cwd().readFileAlloc(io, path, d.allocator, .unlimited); }
fn write(io: std.Io, name: []const u8, text: d.Text) !void { try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.data.items }); }
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa); defer arena.deinit(); d.allocator = arena.allocator();
    var profiles: std.ArrayList(Profile) = .empty;
    for (linesOf(try read(init.io, "input/style.txt"))) |s| {
        if (s.len == 0) continue; if (s[0] == '[') { d.append(Profile, &profiles, .{ .name = s[1 .. s.len - 1] }); continue; }
        const split = std.mem.indexOfScalar(u8, s, '=').?; const key = s[0..split]; const value = s[split + 1 ..]; const p = &profiles.items[profiles.items.len - 1]; const number = std.fmt.parseInt(usize, value, 10) catch 0; const yes = d.eq(value, "yes");
        if (d.eq(key, "width")) p.width = number else if (d.eq(key, "indent")) p.indent = number else if (d.eq(key, "brace_style")) p.kr = d.eq(value, "kr") else if (d.eq(key, "space_around_operators")) p.operators = yes else if (d.eq(key, "space_after_keyword")) p.keyword = yes else if (d.eq(key, "indent_case_labels")) p.cases = yes else if (d.eq(key, "add_braces")) p.braces = yes else if (d.eq(key, "max_blank_lines")) p.blank = number else if (d.eq(key, "remove_parens")) p.parens = yes else p.comment = number;
    }
    var sources: std.ArrayList(Source) = .empty;
    for (linesOf(try read(init.io, "input/sources.txt"))) |s| {
        if (std.mem.startsWith(u8, s, "=== ")) { var it = std.mem.tokenizeScalar(u8, s, ' '); _ = it.next(); const name = it.next().?; d.append(Source, &sources, .{ .header = s, .name = name, .profile = it.next().? }); }
        else d.append([]const u8, &sources.items[sources.items.len - 1].lines, s);
    }
    var formatted: d.Text = .{}; var idempotency: d.Text = .{}; var diagnostics: d.Text = .{}; var trees: d.Text = .{}; var changes: d.Text = .{};
    for (sources.items) |source| {
        var profile: Profile = undefined; for (profiles.items) |p| if (d.eq(p.name, source.profile)) { profile = p; break; };
        const original = d.alloc([]const u8, source.lines.items.len); for (original, source.lines.items) |*a, s| a.* = d.trim(s);
        const result = format(source.lines.items, profile);
        formatted.line("{s}", .{source.header}); for (if (result.failure != null) original else result.lines) |s| formatted.line("{s}", .{s}); trees.line("=== {s}", .{source.name}); changes.line("=== {s}", .{source.name});
        if (result.failure) |e| { idempotency.line("{s}: skipped (syntax error)", .{source.name}); diagnostics.line("{s}:{d}:{d}: error: {s}", .{source.name, e.position.line, e.position.column, e.message}); trees.line("syntax error", .{}); changes.line("skipped (syntax error)", .{}); continue; }
        const second = format(result.lines, profile);
        if (second.failure) |e| idempotency.line("{s}: unstable (second pass: {d}:{d}: {s})", .{source.name, e.position.line, e.position.column, e.message})
        else { var first: usize = 0; while (first < @min(result.lines.len, second.lines.len) and d.eq(result.lines[first], second.lines[first])) : (first += 1) {} if (first == result.lines.len and first == second.lines.len) idempotency.line("{s}: stable", .{source.name}) else idempotency.line("{s}: unstable at line {d}", .{source.name, first + 1}); }
        var longest: usize = 0; for (result.lines, 1..) |s, i| { longest = @max(longest, s.len); if (s.len > profile.width) diagnostics.line("{s}:{d}: warning: line too long ({d} > {d})", .{source.name, i, s.len, profile.width}); }
        const metrics = d.metrics(result.root.?); trees.line("metrics lines={d} longest={d} comments={d} groups={d} broken={d} forced={d}", .{result.lines.len, longest, result.comments, metrics.groups, metrics.broken, metrics.forced}); if (result.function) |doc| { trees.line("function {s}", .{result.function_name}); report.tree(doc, 0, &trees); } else trees.line("no function", .{}); report.diff(original, result.lines, &changes);
    }
    if (diagnostics.data.items.len == 0) diagnostics.line("no diagnostics", .{});
    try write(init.io, "formatted.txt", formatted); try write(init.io, "idempotency.txt", idempotency); try write(init.io, "diagnostics.txt", diagnostics); try write(init.io, "doc_tree.txt", trees); try write(init.io, "changes.txt", changes);
}
