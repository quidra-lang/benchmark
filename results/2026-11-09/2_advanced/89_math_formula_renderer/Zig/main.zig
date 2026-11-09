const std = @import("std");
const b = @import("boxes.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const layout = @import("layout.zig");
const canvas = @import("canvas.zig");
const Node = parser.Node;
const Warning = lexer.Failure;
const Formula = struct { source: []const u8, elements: []const *Node = &.{}, tokens: []const lexer.Token = &.{}, failure: ?lexer.Failure = null, tag: ?lexer.Token = null, label: ?lexer.Token = null, tag_string: ?[]const u8 = null, warnings: std.ArrayList(Warning) = .empty };
const Builder = struct {
    params: layout.Params, refs: std.StringHashMap([]const u8),
    fn reference(self: Builder, name: []const u8) []const u8 { return self.refs.get(name) orelse "(??)"; }
    fn delimiter(self: Builder, child: *b.Box, left: []const u8, right: []const u8) *b.Box {
        _ = self; const wl: i64 = @intFromBool(!b.eq(left, ".")); const wr: i64 = @intFromBool(!b.eq(right, "."));
        const out = b.box(b.fmt("delim {s} {s}", .{left, right}), wl + child.w + wr, child.h, child.baseline); b.glyph(out, left, 0, child.h); out.place(child, wl, 0, ""); b.glyph(out, right, wl + child.w, child.h); return out;
    }
    fn typeset(self: Builder, n: *const Node, script: bool) *b.Box {
        const kind = n.kind;
        if (b.eq(kind, "identifier") or b.eq(kind, "number") or b.eq(kind, "symbol") or b.eq(kind, "command") or b.eq(kind, "text") or b.eq(kind, "eqref")) {
            var display = n.value;
            if (b.eq(kind, "command")) { const symbol = b.symbol(n.value[1..]).?; if (symbol.large and !script) return b.large(n.value); display = symbol.display; }
            if (b.eq(kind, "eqref")) display = self.reference(n.value);
            return b.atom(b.fmt("{s} \"{s}\"", .{if (b.eq(kind, "text") or b.eq(kind, "eqref")) kind else "atom", n.value}), display);
        }
        if (b.eq(kind, "row")) { const boxes = b.alloc(*b.Box, n.children.len); for (n.children, boxes) |child, *x| x.* = self.typeset(child, script); return layout.row(boxes, layout.gaps(n.children, layout.converted(n.children), self.params, script), "row"); }
        if (b.eq(kind, "script")) {
            const base = self.typeset(n.children[0], script); const sub = if (n.sub) |s| self.typeset(s, true) else null; const sup = if (n.sup) |s| self.typeset(s, true) else null;
            const sw: i64 = if (sub) |s| s.w else 0; const sh: i64 = if (sub) |s| s.h else 0; const pw: i64 = if (sup) |s| s.w else 0; const ph: i64 = if (sup) |s| s.h else 0;
            const bn = n.children[0]; var stacked = false;
            if (!script) { if (b.eq(bn.kind, "command")) for ([_][]const u8{ "\\sum", "\\prod", "\\lim", "\\max", "\\min" }) |s| if (b.eq(bn.value, s)) { stacked = true; break; }; if (b.eq(bn.kind, "accent") and (b.eq(bn.value, "overbrace") or b.eq(bn.value, "underbrace"))) stacked = true; }
            if (stacked) { const w = @max(base.w, @max(sw, pw)); const out = b.box("limits", w, ph + base.h + sh, ph + base.baseline); out.place(base, @divFloor(w - base.w, 2), ph, "base: "); if (sub) |s| out.place(s, @divFloor(w - sw, 2), ph + base.h, "sub: "); if (sup) |s| out.place(s, @divFloor(w - pw, 2), 0, "sup: "); return out; }
            const tp = (if (base.baseline == 0) @as(i64, -1) else 0) - ph + 1; const ts = base.h - @intFromBool(base.h - 1 - base.baseline > 0); const top = if (sup != null) @min(@as(i64, 0), tp) else 0; const bottom = if (sub != null) @max(base.h - 1, ts + sh - 1) else base.h - 1;
            const out = b.box("scripts", base.w + @max(sw, pw), bottom - top + 1, base.baseline - top); out.place(base, 0, -top, "base: "); if (sub) |s| out.place(s, base.w, ts - top, "sub: "); if (sup) |s| out.place(s, base.w, tp - top, "sup: "); return out;
        }
        if (b.eq(kind, "frac")) {
            var num = self.typeset(n.children[0], script); var den = self.typeset(n.children[1], script);
            if (script) { if (b.eq(n.children[0].kind, "row") or b.eq(n.children[0].kind, "frac")) num = self.delimiter(num, "(", ")"); if (b.eq(n.children[1].kind, "row") or b.eq(n.children[1].kind, "frac")) den = self.delimiter(den, "(", ")"); const out = layout.row(&.{num, b.atom("atom \"/\"", "/"), den}, &.{0, 0}, "slash"); out.children.items[0].role = "num: "; out.children.items[2].role = "den: "; return out; }
            const w = @max(num.w, den.w) + 2; const out = b.box("frac", w, num.h + 1 + den.h, num.h); out.place(num, @divFloor(w - num.w, 2), 0, "num: "); out.place(den, @divFloor(w - den.w, 2), num.h + 1, "den: "); out.draw(b.repeat('-', w), 0, num.h); return out;
        }
        if (b.eq(kind, "binom")) { const upper = self.typeset(n.children[0], script); const lower = self.typeset(n.children[1], script); const w = @max(upper.w, lower.w); const h = upper.h + 1 + lower.h; const out = b.box("binom", w + 2, h, upper.h); out.place(upper, 1 + @divFloor(w - upper.w, 2), 0, "upper: "); out.place(lower, 1 + @divFloor(w - lower.w, 2), upper.h + 1, "lower: "); b.glyph(out, "(", 0, h); b.glyph(out, ")", w + 1, h); return out; }
        if (b.eq(kind, "overset") or b.eq(kind, "underset")) { const a = self.typeset(n.children[0], true); const base = self.typeset(n.children[1], script); const w = @max(a.w, base.w); const over = b.eq(kind, "overset"); const out = b.box(kind, w, a.h + base.h, base.baseline + (if (over) a.h else @as(i64, 0))); if (over) { out.place(a, @divFloor(w - a.w, 2), 0, "over: "); out.place(base, @divFloor(w - base.w, 2), a.h, "base: "); } else { out.place(base, @divFloor(w - base.w, 2), 0, "base: "); out.place(a, @divFloor(w - a.w, 2), base.h, "under: "); } return out; }
        if (b.eq(kind, "sqrt") or b.eq(kind, "root")) {
            const indexed = b.eq(kind, "root"); const body = self.typeset(n.children[@intFromBool(indexed)], script); const index = if (indexed) self.typeset(n.children[0], true) else null; const e = if (index) |x| @max(@as(i64, 0), x.w - 1) else 0; const t = if (index) |x| @max(@as(i64, 0), x.h - body.h) else 0;
            const out = b.box(kind, e + body.h + 1 + body.w, body.h + 1 + t, body.baseline + 1 + t); out.draw(b.repeat('_', body.w), e + body.h + 1, t); out.draw("\\", e, body.h + t); var r: i64 = 1; while (r <= body.h) : (r += 1) out.draw("/", e + body.h - r + 1, r + t);
            if (index) |x| out.place(x, 0, body.h - x.h + t, "index: "); out.place(body, e + body.h + 1, 1 + t, if (indexed) "body: " else ""); return out;
        }
        if (b.eq(kind, "delim")) return self.delimiter(self.typeset(n.children[0], script), n.left, n.right);
        if (b.eq(kind, "matrix")) {
            const rows = n.rows.len; const columns = n.rows[0].len; const cw = b.alloc(i64, columns); const asc = b.alloc(i64, rows); const desc = b.alloc(i64, rows); @memset(cw, 0); @memset(asc, 0); @memset(desc, 0); const cells = b.alloc(*b.Box, rows * columns);
            for (n.rows, 0..) |row, i| for (row, 0..) |child, j| { const box = self.typeset(child, script); cells[i * columns + j] = box; cw[j] = @max(cw[j], box.w); asc[i] = @max(asc[i], box.baseline); desc[i] = @max(desc[i], box.h - 1 - box.baseline); };
            var w: i64 = self.params.col_gap * @as(i64, @intCast(columns - 1)); for (cw) |v| w += v; var h: i64 = self.params.row_gap * @as(i64, @intCast(rows - 1)); for (asc, desc) |a, z| h += a + z + 1;
            const plain = b.eq(n.value, "matrix"); const cases = b.eq(n.value, "cases"); const shift: i64 = if (plain) 0 else 2; const out = b.box(b.fmt("{s} rows={d} cols={d}", .{n.value, rows, columns}), w + (if (plain) @as(i64, 0) else if (cases) 2 else 4), h, @divFloor(h - 1, 2)); var y: i64 = 0;
            for (0..rows) |i| { var x: i64 = 0; for (0..columns) |j| { const cell = cells[i * columns + j]; out.place(cell, shift + x + (if (cases) @as(i64, 0) else @divFloor(cw[j] - cell.w, 2)), y + asc[i] - cell.baseline, b.fmt("cell {d},{d}: ", .{i + 1, j + 1})); x += cw[j] + self.params.col_gap; } y += asc[i] + desc[i] + 1 + self.params.row_gap; }
            if (!plain) { const left: []const u8 = if (cases) "\\{" else if (b.eq(n.value, "pmatrix")) "(" else if (b.eq(n.value, "bmatrix")) "[" else "|"; b.glyph(out, left, 0, h); if (!cases) b.glyph(out, if (b.eq(n.value, "pmatrix")) ")" else if (b.eq(n.value, "bmatrix")) "]" else "|", w + 3, h); } return out;
        }
        const child = self.typeset(n.children[0], script); const name = n.value; var w = child.w; var x: i64 = 0; const under = b.eq(name, "underbrace");
        if (b.eq(name, "hat") or b.eq(name, "dot") or b.eq(name, "tilde")) w = @max(w, 1); if (b.eq(name, "vec")) w = @max(w, 2); if (b.eq(name, "overbrace") or under) { w += 2; x = 1; }
        const out = b.box(name, w, child.h + 1, child.baseline + @intFromBool(!under)); out.place(child, x, if (under) 0 else 1, "");
        if (b.eq(name, "overline")) out.draw(b.repeat('_', w), 0, 0)
        else if (b.eq(name, "vec")) out.draw(b.fmt("{s}>", .{b.repeat('-', w - 1)}), 0, 0)
        else if (b.eq(name, "overbrace")) out.draw(b.fmt("/{s}\\", .{b.repeat('-', child.w)}), 0, 0)
        else if (under) out.draw(b.fmt("\\{s}/", .{b.repeat('-', child.w)}), 0, child.h)
        else out.draw(if (b.eq(name, "hat")) "^" else if (b.eq(name, "dot")) "." else "~", @divFloor(w - 1, 2), 0);
        return out;
    }
    fn linear(self: Builder, n: *const Node, script: bool) []const u8 {
        const k = n.kind;
        if (b.eq(k, "identifier") or b.eq(k, "number") or b.eq(k, "symbol") or b.eq(k, "text")) return n.value;
        if (b.eq(k, "command")) return b.symbol(n.value[1..]).?.display;
        if (b.eq(k, "eqref")) return self.reference(n.value);
        if (b.eq(k, "row")) { const gs = layout.gaps(n.children, layout.converted(n.children), self.params, script); var text: b.Text = .{}; for (n.children, 0..) |child, i| { if (i > 0) text.put("{s}", .{b.repeat(' ', gs[i - 1])}); text.put("{s}", .{self.linear(child, script)}); } return text.data.items; }
        if (b.eq(k, "frac")) return b.fmt("{s}/{s}", .{self.parenthesized(n.children[0], script, false), self.parenthesized(n.children[1], script, false)});
        if (b.eq(k, "binom")) return b.fmt("binom({s}, {s})", .{self.linear(n.children[0], script), self.linear(n.children[1], script)});
        if (b.eq(k, "overset") or b.eq(k, "underset")) return b.fmt("{s}({s}, {s})", .{k, self.linear(n.children[0], true), self.linear(n.children[1], script)});
        if (b.eq(k, "script")) { var text: b.Text = .{}; text.put("{s}", .{self.parenthesized(n.children[0], script, true)}); if (n.sub) |s| text.put("_{s}", .{self.parenthesized(s, true, false)}); if (n.sup) |s| text.put("^{s}", .{self.parenthesized(s, true, false)}); return text.data.items; }
        if (b.eq(k, "sqrt")) return b.fmt("sqrt({s})", .{self.linear(n.children[0], script)});
        if (b.eq(k, "root")) return b.fmt("root({s}, {s})", .{self.linear(n.children[0], true), self.linear(n.children[1], script)});
        if (b.eq(k, "delim")) return b.fmt("{s}{s}{s}", .{delimiterString(n.left), self.linear(n.children[0], script), delimiterString(n.right)});
        if (b.eq(k, "matrix")) { var text: b.Text = .{}; text.put("{s}[", .{n.value}); for (n.rows, 0..) |row, i| { if (i > 0) text.put("; ", .{}); for (row, 0..) |child, j| { if (j > 0) text.put(", ", .{}); text.put("{s}", .{self.linear(child, script)}); } } text.put("]", .{}); return text.data.items; }
        return b.fmt("{s}({s})", .{n.value, self.linear(n.children[0], script)});
    }
    fn parenthesized(self: Builder, n: *const Node, script: bool, base: bool) []const u8 { const s = self.linear(n, script); return if (b.eq(n.kind, "row") or b.eq(n.kind, "frac") or (base and b.eq(n.kind, "script"))) b.fmt("({s})", .{s}) else s; }
};
fn delimiterString(s: []const u8) []const u8 { return if (b.eq(s, ".")) "" else if (s.len == 2) s[1..] else s; }
fn delimiterTree(s: []const u8) []const u8 { return if (s.len == 1) b.fmt("'{s}'", .{s}) else s; }
fn tree(n: *const Node) []const u8 {
    const k = n.kind;
    if (b.eq(k, "identifier") or b.eq(k, "number") or b.eq(k, "command")) return n.value;
    if (b.eq(k, "symbol")) return b.fmt("'{s}'", .{n.value}); if (b.eq(k, "text")) return b.fmt("\"{s}\"", .{n.value}); if (b.eq(k, "eqref")) return b.fmt("(eqref \"{s}\")", .{n.value});
    if (b.eq(k, "script")) return if (n.sub != null and n.sup != null) b.fmt("(subsup {s} {s} {s})", .{tree(n.children[0]), tree(n.sub.?), tree(n.sup.?)}) else b.fmt("({s} {s} {s})", .{if (n.sub != null) "sub" else "sup", tree(n.children[0]), tree((n.sub orelse n.sup).?)});
    if (b.eq(k, "delim")) return b.fmt("(delim {s} {s} {s})", .{delimiterTree(n.left), delimiterTree(n.right), tree(n.children[0])});
    var text: b.Text = .{}; text.put("({s}", .{if (b.eq(k, "matrix") or b.eq(k, "accent")) n.value else k});
    if (b.eq(k, "matrix")) for (n.rows) |row| { text.put(" [", .{}); for (row, 0..) |child, j| { if (j > 0) text.put(" ", .{}); text.put("{s}", .{tree(child)}); } text.put("]", .{}); } else for (n.children) |child| text.put(" {s}", .{tree(child)});
    text.put(")", .{}); return text.data.items;
}
fn warn(nodes: []const *Node, refs: std.StringHashMap([]const u8), warnings: *std.ArrayList(Warning)) void {
    for (nodes) |n| {
        if (b.eq(n.kind, "eqref") and !refs.contains(n.value)) b.append(Warning, warnings, .{ .column = n.column, .message = b.fmt("undefined reference \"{s}\"", .{n.value}) });
        if (b.eq(n.kind, "delim") and !b.eq(n.left, ".") and !b.eq(n.right, ".")) {
            const matched = (b.eq(n.left, "(") and b.eq(n.right, ")")) or (b.eq(n.left, "[") and b.eq(n.right, "]")) or (b.eq(n.left, "|") and b.eq(n.right, "|")) or (b.eq(n.left, "\\{") and b.eq(n.right, "\\}"));
            if (!matched) b.append(Warning, warnings, .{ .column = n.right_column, .message = b.fmt("\\left{s} closed by \\right{s}", .{n.left, n.right}) });
        }
        warn(n.children, refs, warnings); if (n.sub) |s| warn(&.{s}, refs, warnings); if (n.sup) |s| warn(&.{s}, refs, warnings); for (n.rows) |row| warn(row, refs, warnings);
    }
}
const Line = struct { first: usize, end: usize, indentation: i64, width: i64 };
fn breakLines(nodes: []const *Node, boxes: []const *b.Box, ts: []const layout.Types, gaps: []const i64, params: layout.Params, mode: usize) []const Line {
    var lines: std.ArrayList(Line) = .empty; var start: usize = 0; var alignment: ?i64 = null; var relation_width: i64 = 0;
    while (start < nodes.len) {
        const indent = if (start == 0) 0 else if (alignment) |a| a + (if (ts[start].left == .relation) @as(i64, 0) else relation_width + params.rel_space) else params.indent;
        var shortest: ?Line = null; var best: ?Line = null; var width: i64 = 0;
        for (start..nodes.len) |j| {
            if (j > start) width += gaps[j - 1]; width += boxes[j].w; const end = j + 1;
            const candidate = end == nodes.len or ts[end].left == .relation or (mode >= 1 and b.eq(nodes[end].kind, "symbol") and (b.eq(nodes[end].value, "+") or b.eq(nodes[end].value, "-")) and ts[end].left == .binary) or (mode >= 2 and ts[j].right == .punctuation);
            if (candidate) { const line = Line{ .first = start, .end = end, .indentation = indent, .width = width }; if (shortest == null) shortest = line; if (indent + width <= params.width) best = line; }
        }
        const chosen = best orelse shortest.?; b.append(Line, &lines, chosen);
        if (start == 0) { var x: i64 = 0; for (0..chosen.end) |j| { if (j > 0) x += gaps[j - 1]; if (ts[j].left == .relation) { alignment = x; relation_width = boxes[j].w; break; } x += boxes[j].w; } }
        start = chosen.end;
    }
    return lines.items;
}
fn reportError(out: *b.Text, number: usize, source: []const u8, failure: lexer.Failure, warning: bool) void { out.line("formula {d}, column {d}: {s}{s}", .{number, failure.column, if (warning) "warning: " else "", failure.message}); out.line("  {s}", .{source}); out.line("{s}^", .{b.repeat(' ', @intCast(failure.column + 1))}); }
fn read(io: std.Io, path: []const u8) ![]const u8 { return std.Io.Dir.cwd().readFileAlloc(io, path, b.allocator, .unlimited); }
fn write(io: std.Io, name: []const u8, text: b.Text) !void { try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = b.fmt("output/{s}", .{name}), .data = text.data.items }); }
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa); defer arena.deinit(); b.allocator = arena.allocator();
    var params: layout.Params = .{}; var settings = std.mem.tokenizeScalar(u8, try read(init.io, "input/params.txt"), '\n');
    while (settings.next()) |line| { const sep = std.mem.indexOfScalar(u8, line, ' ').?; const value = std.fmt.parseInt(i64, line[sep + 1 ..], 10) catch unreachable; inline for (@typeInfo(layout.Params).@"struct".fields) |field| if (b.eq(field.name, line[0..sep])) { @field(params, field.name) = value; }; }
    var formulas: std.ArrayList(Formula) = .empty; var input = std.mem.splitScalar(u8, try read(init.io, "input/formulas.txt"), '\n');
    while (input.next()) |line| { if (line.len == 0) continue; const lexed = lexer.scan(line); var formula = Formula{ .source = line, .tokens = lexed.tokens, .failure = lexed.failure };
        if (formula.failure == null) formula.failure = parser.braceCheck(lexed.tokens);
        if (formula.failure == null) { var p = parser.Parser{ .tokens = lexed.tokens }; const elements = p.formula() catch null; if (elements) |list| { formula.elements = list; formula.tag = p.tag; formula.label = p.label; } else formula.failure = p.failure; }
        b.append(Formula, &formulas, formula);
    }
    var refs = std.StringHashMap([]const u8).init(b.allocator); var counter: usize = 0;
    for (formulas.items) |*formula| { if (formula.failure != null) continue; if (formula.tag) |t| formula.tag_string = b.fmt("({s})", .{t.value}) else if (formula.label != null) { counter += 1; formula.tag_string = b.fmt("({d})", .{counter}); } }
    for (formulas.items) |*formula| if (formula.failure == null) { if (formula.label) |label| { if (refs.contains(label.value)) b.append(Warning, &formula.warnings, .{ .column = label.column, .message = b.fmt("duplicate label \"{s}\"", .{label.value}) }) else refs.put(label.value, formula.tag_string.?) catch @panic("allocation failed"); } };
    const builder = Builder{ .params = params, .refs = refs }; var rendered: b.Text = .{}; var boxes_text: b.Text = .{}; var trees: b.Text = .{}; var errors: b.Text = .{}; var totals = canvas.Counts{ .kinds = std.StringHashMap(usize).init(b.allocator) };
    var valid: usize = 0; var warning_count: usize = 0; var overfull: usize = 0;
    for (formulas.items, 1..) |*formula, number| {
        if (number > 1) rendered.line("", .{}); rendered.line("formula {d}", .{number});
        if (formula.failure) |failure| { rendered.line("(error)", .{}); boxes_text.line("formula {d}: error", .{number}); trees.line("formula {d}: error", .{number}); reportError(&errors, number, formula.source, failure, false); continue; }
        valid += 1; for (formula.tokens) |token| if (b.eq(token.kind, "identifier") and b.symbol(token.value) != null) b.append(Warning, &formula.warnings, .{ .column = token.column, .message = b.fmt("{s} is a command name; write \\{s}", .{token.value, token.value}) });
        warn(formula.elements, refs, &formula.warnings); std.mem.sort(Warning, formula.warnings.items, {}, struct { fn less(_: void, a: Warning, c: Warning) bool { return a.column < c.column; } }.less);
        for (formula.warnings.items) |warning| reportError(&errors, number, formula.source, warning, true); warning_count += formula.warnings.items.len;
        const element_boxes = b.alloc(*b.Box, formula.elements.len); for (formula.elements, element_boxes) |n, *x| x.* = builder.typeset(n, false); const ts = layout.converted(formula.elements); const gaps = layout.gaps(formula.elements, ts, params, false);
        var lines: []const Line = &.{}; for (0..3) |mode| { lines = breakLines(formula.elements, element_boxes, ts, gaps, params, mode); var fits = true; for (lines) |line| if (line.indentation + line.width > params.width) { fits = false; break; }; if (fits) break; }
        var roots: std.ArrayList(b.Placement) = .empty; var width: i64 = 0; var height: i64 = 0;
        for (lines, 1..) |line, i| { const box = layout.row(element_boxes[line.first..line.end], gaps[line.first .. line.end - 1], b.fmt("line {d}", .{i})); b.append(b.Placement, &roots, .{ .box = box, .x = line.indentation, .y = height }); height += box.h; width = @max(width, line.indentation + box.w); if (line.indentation + box.w > params.width) { errors.line("formula {d}: line {d} is overfull (width {d} > {d})", .{number, i, line.indentation + box.w, params.width}); overfull += 1; } }
        if (formula.tag_string) |tag| { const last = roots.items[roots.items.len - 1]; const x = params.width - @as(i64, @intCast(tag.len)); const y = if (x >= last.x + last.box.w + 2) last.y + last.box.baseline else height; if (y == height) height += 1; b.append(b.Placement, &roots, .{ .box = b.atom(b.fmt("tag \"{s}\"", .{tag}), tag), .x = x, .y = y }); width = @max(width, x + @as(i64, @intCast(tag.len))); }
        const result = canvas.render(roots.items, width, height, &totals); for (result.rendered) |line| rendered.line("{s}", .{line}); boxes_text.line("formula {d}: lines={d} width={d} height={d} boxes={d} depth={d}", .{number, lines.len, width, height, result.count, result.depth}); boxes_text.put("{s}", .{result.boxes.data.items});
        trees.put("formula {d}:", .{number}); for (formula.elements) |n| trees.put(" {s}", .{tree(n)}); trees.put("\n", .{}); const linear = std.mem.trimEnd(u8, builder.linear(parser.node("row", formula.elements), false), " "); trees.put("  linear:", .{}); if (linear.len > 0) trees.put(" {s}", .{linear}); trees.put("\n", .{}); if (formula.tag_string) |tag| trees.line("  tag: {s}", .{tag});
    }
    boxes_text.line("summary: boxes={d} max_depth={d}", .{totals.boxes, totals.depth}); const kinds = b.alloc([]const u8, totals.kinds.count()); var ki: usize = 0; var it = totals.kinds.keyIterator(); while (it.next()) |key| { kinds[ki] = key.*; ki += 1; } std.mem.sort([]const u8, kinds, {}, struct { fn less(_: void, a: []const u8, c: []const u8) bool { return std.mem.order(u8, a, c) == .lt; } }.less); for (kinds) |kind| boxes_text.line("  {s}: {d}", .{kind, totals.kinds.get(kind).?}); errors.line("formulas={d} rendered={d} errors={d} warnings={d} overfull={d}", .{formulas.items.len, valid, formulas.items.len - valid, warning_count, overfull});
    try write(init.io, "rendered.txt", rendered); try write(init.io, "boxes.txt", boxes_text); try write(init.io, "trees.txt", trees); try write(init.io, "errors.txt", errors);
}
