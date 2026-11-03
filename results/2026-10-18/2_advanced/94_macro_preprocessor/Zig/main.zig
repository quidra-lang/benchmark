const std = @import("std");
const lex = @import("lexer.zig");
const defs = @import("definitions.zig");
const expr = @import("expression.zig");
const expansion = @import("expander.zig");
const includes = @import("include_manager.zig");
const Text = lex.Text;
const Buffer = struct { a: std.mem.Allocator, data: std.ArrayList(u8) = .empty,
    fn add(b: *Buffer, s: Text) !void { try b.data.appendSlice(b.a, s); }
    fn print(b: *Buffer, comptime f: Text, args: anytype) !void { try b.add(try std.fmt.allocPrint(b.a, f, args)); }
    fn line(b: *Buffer, s: Text) !void { try b.add(s); try b.add("\n"); }
};
const Block = struct { kind: Text, position: defs.Position, parent: bool, chosen: bool = false, active: bool = false, seen_else: bool = false, skip: ?i64 = null };
const State = struct { file: *includes.File, depth: usize, display: Text, offset: i64 = 0, blocks: std.ArrayList(Block) = .empty, segment: std.ArrayList(lex.Token) = .empty,
    fn position(s: *State, line: i64) defs.Position { return .{ .file = s.display, .line = line + s.offset }; }
    fn active(s: *State) bool { return s.blocks.items.len == 0 or s.blocks.items[s.blocks.items.len - 1].active; }
};
const Saved = struct { name: Text, definition: ?*defs.Macro };
const Header = struct { rendering: Text, name: Text, quoted: bool, next: usize };
const Processor = struct {
    a: std.mem.Allocator, manager: includes.Manager, table: std.StringHashMapUnmanaged(*defs.Macro) = .empty,
    ever: std.ArrayList(Text) = .empty, poison: std.ArrayList(Text) = .empty, saved: std.ArrayList(Saved) = .empty,
    builtins: [3]usize = .{0, 0, 0}, preprocessed: Buffer, tree: Buffer, history: Buffer, conditions: Buffer, regions: Buffer, diagnostics: Buffer,
    previous: defs.Position = .{ .file = "main.c", .line = 0 }, errors: usize = 0, warnings: usize = 0, records: [5]usize = @splat(0), region_count: usize = 0,
    pub fn diag(p: *Processor, pos: defs.Position, kind: Text, message: Text) !void { try p.diagnostics.print("{s}:{d}: {s}: {s}\n", .{pos.file, pos.line, kind, message}); if (lex.eq(kind, "error")) p.errors += 1 else p.warnings += 1; }
    fn hist(p: *Processor, pos: defs.Position, message: Text) !void { try p.history.print("{s}:{d}: {s}\n", .{pos.file, pos.line, message}); }
    fn marker(p: *Processor, pos: defs.Position, suffix: Text) !void { try p.preprocessed.print("# {d} \"{s}\"{s}\n", .{pos.line, pos.file, suffix}); p.previous = .{ .file = pos.file, .line = pos.line - 1 }; }
    fn output(p: *Processor, s: *State, physical: i64, text: Text) !void {
        const pos = s.position(physical);
        if (lex.eq(p.previous.file, pos.file) and p.previous.line < pos.line and pos.line <= p.previous.line + 8) { var k = p.previous.line + 1; while (k < pos.line) : (k += 1) try p.preprocessed.add("\n"); } else try p.marker(pos, "");
        try p.preprocessed.line(text); p.previous = pos; s.file.output_lines += 1;
    }
    fn poisonCheck(p: *Processor, s: *State, tokens: []const lex.Token) !void { for (tokens) |t| if (t.kind == .identifier and contains(p.poison.items, t.spelling)) { try p.diag(s.position(t.line), "error", try std.fmt.allocPrint(p.a, "attempt to use poisoned \"{s}\"", .{t.spelling})); }; }
    fn flush(p: *Processor, s: *State) !void {
        try p.poisonCheck(s, s.segment.items); const tokens = try expansion.expand(p.a, p, s.segment.items, s.display, s.offset); s.segment.clearRetainingCapacity(); var start: usize = 0;
        while (start < tokens.len) { var end = start + 1; while (end < tokens.len and tokens[end].line == tokens[start].line) end += 1; try p.output(s, tokens[start].line, try lex.render(p.a, tokens[start..end], true)); start = end; }
    }
    fn unused(p: *Processor, m: *defs.Macro) !void { if (m.main and m.expanded == 0 and m.tested == 0) try p.diag(m.position, "warning", try std.fmt.allocPrint(p.a, "macro \"{s}\" is not used", .{m.name})); }
    fn define(p: *Processor, tokens: []const lex.Token, pos: defs.Position, main: bool) !void {
        const parsed = try defs.parse(p.a, tokens, pos, main); const m = switch (parsed) { .message => |msg| { try p.diag(pos, "error", msg); return; }, .macro => |value| value };
        var event: Text = "define";
        if (p.table.get(m.name)) |old| {
            if (defs.identical(old, m)) { try p.hist(pos, try std.fmt.allocPrint(p.a, "identical {s}", .{try m.signature(p.a)})); return; }
            try p.unused(old); try p.diag(pos, "warning", try std.fmt.allocPrint(p.a, "\"{s}\" redefined (previous definition at {s}:{d})", .{m.name, old.position.file, old.position.line})); event = "redefine";
        }
        try p.table.put(p.a, m.name, m); try unique(p.a, &p.ever, m.name); try p.hist(pos, try std.fmt.allocPrint(p.a, "{s} {s}", .{event, try m.signature(p.a)}));
    }
    fn tested(p: *Processor, name: Text) bool { if (p.table.get(name)) |m| { m.tested += 1; return true; } return defs.builtin(name) or lex.eq(name, "__has_include"); }
    fn header(p: *Processor, tokens: []const lex.Token, index: usize, pos: defs.Position) !?Header {
        if (index >= tokens.len) return null; const t = tokens[index];
        if (t.kind == .string or t.kind == .header) return .{ .rendering = t.spelling, .name = t.spelling[1..t.spelling.len - 1], .quoted = t.kind == .string, .next = index + 1 };
        if (lex.eq(t.spelling, "<")) {
            var end = index + 1; while (end < tokens.len and !lex.eq(tokens[end].spelling, ">")) end += 1;
            if (end == tokens.len) { try p.diag(pos, "error", "missing terminating > character"); return error.InvalidHeader; }
            const name = try lex.render(p.a, tokens[index + 1..end], false); return .{ .rendering = try std.fmt.allocPrint(p.a, "<{s}>", .{name}), .name = name, .quoted = false, .next = end + 1 };
        }
        return null;
    }
    const Test = struct { value: ?i64, result: Text };
    fn testCondition(p: *Processor, s: *State, kind: Text, operands: []const lex.Token, pos: defs.Position) !Test {
        try p.poisonCheck(s, operands);
        if (!lex.eq(kind, "if") and !lex.eq(kind, "elif")) {
            if (operands.len == 0 or operands[0].kind != .identifier) { try p.diag(pos, "error", if (operands.len == 0) try std.fmt.allocPrint(p.a, "no macro name given in #{s} directive", .{kind}) else "macro names must be identifiers"); return .{ .value = null, .result = "not taken (error)" }; }
            if (operands.len > 1) try p.diag(pos, "warning", try std.fmt.allocPrint(p.a, "extra tokens at end of #{s} directive", .{kind}));
            const yes = p.tested(operands[0].spelling) != (lex.eq(kind, "ifndef") or lex.eq(kind, "elifndef")); return .{ .value = @intFromBool(yes), .result = if (yes) "taken" else "not taken" };
        }
        var replaced: std.ArrayList(lex.Token) = .empty; var i: usize = 0; var message: ?Text = null;
        while (i < operands.len) {
            const t = operands[i]; i += 1; var yes: ?bool = null;
            if (t.kind == .identifier and lex.eq(t.spelling, "defined")) {
                const paren = i < operands.len and lex.eq(operands[i].spelling, "("); if (paren) i += 1;
                if (i == operands.len or operands[i].kind != .identifier) { message = "operator \"defined\" requires an identifier"; break; }
                const name = operands[i].spelling; i += 1;
                if (paren) { if (i == operands.len or !lex.eq(operands[i].spelling, ")")) { message = "missing ')' after \"defined\""; break; } i += 1; }
                yes = p.tested(name);
            } else if (t.kind == .identifier and lex.eq(t.spelling, "__has_include")) {
                if (i == operands.len or !lex.eq(operands[i].spelling, "(")) { message = "missing '(' after \"__has_include\""; break; } i += 1;
                const h = p.header(operands, i, pos) catch |err| switch (err) { error.InvalidHeader => return .{ .value = null, .result = "not taken (error)" }, else => return err };
                if (h == null or h.?.name.len == 0) { message = "operator \"__has_include\" requires a header-name"; break; } i = h.?.next;
                if (i == operands.len or !lex.eq(operands[i].spelling, ")")) { message = "missing ')' after \"__has_include\" operand"; break; } i += 1; yes = (try p.manager.search(h.?.name, h.?.quoted)) != null;
            }
            var value = t; if (yes) |v| { value.kind = .number; value.spelling = if (v) "1" else "0"; } try replaced.append(p.a, value);
        }
        if (message) |msg| { try p.diag(pos, "error", msg); return .{ .value = null, .result = "not taken (error)" }; }
        const expanded = try expansion.expand(p.a, p, replaced.items, s.display, s.offset); var parser: expr.Parser = .{ .a = p.a, .tokens = expanded };
        const root = parser.parse(kind) catch |err| switch (err) { error.InvalidExpression => null, else => return err };
        var value: ?i64 = null;
        if (root) |r| value = try expr.evaluate(r, p, pos) else try p.diag(pos, "error", parser.message);
        const result = if (value) |v| try std.fmt.allocPrint(p.a, "{s} (value {d})", .{if (v == 0) "not taken" else "taken", v}) else "not taken (error)";
        return .{ .value = value, .result = try std.fmt.allocPrint(p.a, "{s} [{s}]", .{result, try lex.render(p.a, expanded, true)}) };
    }
    fn closeRegion(p: *Processor, s: *State, block: *Block, end: i64) !void {
        if (block.skip) |start| if (end >= start) { const count = end - start + 1; try p.regions.print("{s}:{d}-{d} lines={d}\n", .{s.display, start + s.offset, end + s.offset, count}); s.file.skipped_lines += count; p.region_count += 1; };
        block.skip = null;
    }
    fn conditional(p: *Processor, s: *State, line: lex.Line, kind: Text, ops: []const lex.Token) !void {
        const pos = s.position(line.tokens[0].line); const opening = lex.eq(kind, "if") or lex.eq(kind, "ifdef") or lex.eq(kind, "ifndef"); var depth = s.blocks.items.len; var result: Text = "";
        if (opening) {
            var b: Block = .{ .kind = kind, .position = pos, .parent = s.active() };
            if (b.parent) { const t = try p.testCondition(s, kind, ops, pos); result = t.result; b.active = t.value != null and t.value.? != 0; b.chosen = b.active; if (!b.active) b.skip = line.end + 1; } else result = "skipped";
            try s.blocks.append(p.a, b);
        } else {
            if (depth == 0) { try p.diag(pos, "error", try std.fmt.allocPrint(p.a, "#{s} without #if", .{kind})); return; } depth -= 1;
            const b = &s.blocks.items[depth]; try p.closeRegion(s, b, line.start - 1);
            if (lex.eq(kind, "endif")) { if (b.parent and ops.len > 0) try p.diag(pos, "warning", "extra tokens at end of #endif directive"); result = try std.fmt.allocPrint(p.a, "closes #{s} at line {d}", .{b.kind, b.position.line}); _ = s.blocks.pop(); }
            else {
                if (b.seen_else) try p.diag(pos, "error", try std.fmt.allocPrint(p.a, "#{s} after #else", .{kind}));
                if (lex.eq(kind, "else")) { if (b.parent and ops.len > 0) try p.diag(pos, "warning", "extra tokens at end of #else directive"); b.seen_else = true; if (b.parent) { b.active = !b.chosen; b.chosen = true; result = if (b.active) "taken" else "not taken"; } else { b.active = false; result = "skipped"; } }
                else if (!b.parent) { b.active = false; result = "skipped"; } else if (b.chosen) { b.active = false; result = "not evaluated"; }
                else { const t = try p.testCondition(s, kind, ops, pos); result = t.result; b.active = t.value != null and t.value.? != 0; b.chosen = b.active; }
                if (b.parent and !b.active) b.skip = line.end + 1;
            }
        }
        try p.conditions.print("{s}:{d}: ", .{pos.file, pos.line}); for (0..depth * 2) |_| try p.conditions.add(" "); try p.conditions.print("#{s}", .{kind}); if (ops.len > 0) try p.conditions.print(" {s}", .{try lex.render(p.a, ops, false)}); try p.conditions.print(" => {s}\n", .{result});
        const prefixes = [_]Text{"taken", "not taken", "skipped", "not evaluated", "closes"}; for (prefixes, 0..) |prefix, index| if (std.mem.startsWith(u8, result, prefix)) { p.records[index] += 1; break; };
    }
    fn include(p: *Processor, s: *State, line: lex.Line, operands: []const lex.Token, pos: defs.Position) anyerror!void {
        var tokens = operands; var h = try p.header(tokens, 0, pos);
        if (h == null and tokens.len > 0) { tokens = try expansion.expand(p.a, p, tokens, s.display, s.offset); h = try p.header(tokens, 0, pos); }
        const spec = h orelse { try p.diag(pos, "error", "#include expects \"FILENAME\" or <FILENAME>"); return; };
        if (spec.next < tokens.len) try p.diag(pos, "warning", "extra tokens at end of #include directive"); if (spec.name.len == 0) { try p.diag(pos, "error", "empty filename in #include"); return; }
        for (0..(s.depth + 1) * 2) |_| try p.tree.add(" "); try p.tree.print("{d}: ", .{line.tokens[0].line});
        const file = (try p.manager.search(spec.name, spec.quoted)) orelse { try p.tree.print("{s} [not found]\n", .{spec.rendering}); try p.diag(pos, "error", try std.fmt.allocPrint(p.a, "cannot find include file {s}", .{spec.rendering})); return; };
        try p.tree.add(file.path);
        if (file.entered > 0 and file.once) { file.skipped += 1; try p.tree.line(" [skipped: pragma once]"); return; }
        if (file.entered > 0 and file.guard != null and p.table.contains(file.guard.?)) { file.skipped += 1; try p.tree.print(" [skipped: guard {s}]\n", .{file.guard.?}); return; }
        if (s.depth + 1 > 8) { try p.tree.line(" [too deep]"); try p.diag(pos, "error", "#include nested too deeply"); return; }
        try p.tree.add("\n"); try p.marker(.{ .file = file.path, .line = 1 }, " 1"); try p.process(file, s.depth + 1); try p.marker(s.position(line.end + 1), " 2");
    }
    fn pragma(p: *Processor, s: *State, line: lex.Line, ops: []const lex.Token, pos: defs.Position) !void {
        const first = if (ops.len > 0) ops[0].spelling else "";
        if (ops.len > 0 and ops[0].kind == .identifier and lex.eq(first, "once")) { if (ops.len > 1) try p.diag(pos, "warning", "extra tokens at end of #pragma once directive"); if (s.depth == 0) try p.diag(pos, "warning", "#pragma once in main file"); s.file.once = true; }
        else if (ops.len >= 2 and lex.eq(first, "GCC") and lex.eq(ops[1].spelling, "poison")) {
            for (ops[2..]) |t| if (t.kind != .identifier) { try p.diag(pos, "error", "invalid #pragma GCC poison directive"); return; };
            for (ops[2..]) |t| { if (p.table.contains(t.spelling)) try p.diag(pos, "warning", try std.fmt.allocPrint(p.a, "poisoning existing macro \"{s}\"", .{t.spelling})); try unique(p.a, &p.poison, t.spelling); }
        } else if (ops.len > 0 and ops[0].kind == .identifier and (lex.eq(first, "push_macro") or lex.eq(first, "pop_macro"))) {
            if (ops.len != 4 or !lex.eq(ops[1].spelling, "(") or ops[2].kind != .string or !lex.eq(ops[3].spelling, ")")) { try p.diag(pos, "error", try std.fmt.allocPrint(p.a, "invalid #pragma {s} directive", .{first})); return; }
            const name = ops[2].spelling[1..ops[2].spelling.len - 1];
            if (lex.eq(first, "push_macro")) { try p.saved.append(p.a, .{ .name = name, .definition = p.table.get(name) }); try p.hist(pos, try std.fmt.allocPrint(p.a, "push {s}", .{name})); }
            else { var index = p.saved.items.len; while (index > 0) { index -= 1; if (lex.eq(p.saved.items[index].name, name)) break; } if (p.saved.items.len == 0 or !lex.eq(p.saved.items[index].name, name)) { try p.diag(pos, "warning", try std.fmt.allocPrint(p.a, "no matching push_macro for \"{s}\"", .{name})); return; } const saved = p.saved.orderedRemove(index); if (saved.definition) |m| try p.table.put(p.a, name, m) else _ = p.table.remove(name); try p.hist(pos, try std.fmt.allocPrint(p.a, "pop {s}{s}", .{name, if (saved.definition == null) " (undefined)" else ""})); }
        } else try p.output(s, line.tokens[0].line, if (ops.len == 0) "#pragma" else try std.fmt.allocPrint(p.a, "#pragma {s}", .{try lex.render(p.a, ops, false)}));
    }
    fn directive(p: *Processor, s: *State, line: lex.Line, kind: Text, operands: []const lex.Token) anyerror!void {
        const pos = s.position(line.tokens[0].line);
        if (line.tokens.len == 1) return;
        const poison_pragma = lex.eq(kind, "pragma") and operands.len >= 2 and lex.eq(operands[0].spelling, "GCC") and lex.eq(operands[1].spelling, "poison"); if (!poison_pragma) try p.poisonCheck(s, operands);
        if (lex.eq(kind, "define")) try p.define(operands, pos, s.depth == 0)
        else if (lex.eq(kind, "undef")) {
            if (try defs.nameError(p.a, operands, "undef")) |message| { try p.diag(pos, "error", message); return; }
            if (operands.len > 1) try p.diag(pos, "warning", "extra tokens at end of #undef directive"); const name = operands[0].spelling;
            const old = p.table.get(name); if (old) |m| { try p.unused(m); _ = p.table.remove(name); }
            try p.hist(pos, try std.fmt.allocPrint(p.a, "undef {s}{s}", .{name, if (old == null) " (not defined)" else ""}));
        } else if (lex.eq(kind, "include")) p.include(s, line, operands, pos) catch |err| switch (err) { error.InvalidHeader => {}, else => return err }
        else if (lex.eq(kind, "line")) {
            var ops = operands; if (ops.len == 0 or ops[0].kind != .number or !digits(ops[0].spelling)) ops = try expansion.expand(p.a, p, ops, s.display, s.offset);
            if (ops.len < 1 or ops.len > 2 or ops[0].kind != .number or !digits(ops[0].spelling) or (ops.len == 2 and ops[1].kind != .string)) { try p.diag(pos, "error", "invalid #line directive"); return; }
            const n = std.fmt.parseInt(i64, ops[0].spelling, 10) catch unreachable; if (n < 1 or n > 2147483647) { try p.diag(pos, "error", "line number out of range"); return; } s.offset = n - line.end - 1; if (ops.len == 2) s.display = ops[1].spelling[1..ops[1].spelling.len - 1];
        } else if (lex.eq(kind, "error") or lex.eq(kind, "warning")) try p.diag(pos, kind, if (operands.len == 0) try std.fmt.allocPrint(p.a, "#{s}", .{kind}) else try std.fmt.allocPrint(p.a, "#{s} {s}", .{kind, try lex.render(p.a, operands, false)}))
        else if (lex.eq(kind, "pragma")) try p.pragma(s, line, operands, pos)
        else try p.diag(pos, "error", try std.fmt.allocPrint(p.a, "invalid preprocessing directive #{s}", .{line.tokens[1].spelling}));
    }
    fn process(p: *Processor, file: *includes.File, depth: usize) anyerror!void {
        try p.manager.enter(file); var s: State = .{ .file = file, .depth = depth, .display = file.path };
        for (file.document.lines) |line| {
            const ts = line.tokens; const directive_line = ts.len > 0 and lex.eq(ts[0].spelling, "#"); const kind = if (ts.len >= 2 and ts[1].kind == .identifier) ts[1].spelling else ""; const ops = if (ts.len >= 2) ts[2..] else ts[0..0];
            const conditional_line = contains(&.{"if", "ifdef", "ifndef", "elif", "elifdef", "elifndef", "else", "endif"}, kind);
            if (directive_line and conditional_line) { try p.flush(&s); try p.conditional(&s, line, kind, ops); }
            else if (!s.active()) continue
            else if (directive_line) { try p.flush(&s); try p.directive(&s, line, kind, ops); }
            else try s.segment.appendSlice(p.a, ts);
        }
        try p.flush(&s); for (s.blocks.items) |*b| try p.closeRegion(&s, b, file.document.physical); for (s.blocks.items) |b| try p.diag(b.position, "error", try std.fmt.allocPrint(p.a, "unterminated #{s}", .{b.kind}));
    }
};
fn digits(s: Text) bool { if (s.len == 0) return false; for (s) |c| if (!std.ascii.isDigit(c)) return false; return true; }
fn contains(xs: []const Text, name: Text) bool { for (xs) |x| if (lex.eq(x, name)) return true; return false; }
fn unique(a: std.mem.Allocator, xs: *std.ArrayList(Text), name: Text) !void { if (!contains(xs.items, name)) try xs.append(a, name); }
fn less(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; }
fn references(p: *Processor, m: *defs.Macro) ![]const Text { var refs: std.ArrayList(Text) = .empty; for (m.replacement) |t| if (t.kind == .identifier and m.parameter(t.spelling) == null and p.table.contains(t.spelling)) { try unique(p.a, &refs, t.spelling); }; std.mem.sort(Text, refs.items, {}, less); return refs.items; }
fn recursive(p: *Processor, name: Text) !bool {
    var pending: std.ArrayList(Text) = .empty; try pending.appendSlice(p.a, try references(p, p.table.get(name).?)); var seen: std.ArrayList(Text) = .empty;
    while (pending.pop()) |n| { if (lex.eq(n, name)) return true; if (contains(seen.items, n)) continue; try seen.append(p.a, n); try pending.appendSlice(p.a, try references(p, p.table.get(n).?)); } return false;
}
fn save(p: *Processor) !void {
    var names: std.ArrayList(Text) = .empty; var iterator = p.table.keyIterator(); while (iterator.next()) |n| try names.append(p.a, n.*); std.mem.sort(Text, names.items, {}, less);
    var macros: Buffer = .{ .a = p.a }; try macros.line("== history =="); try macros.add(p.history.data.items); try macros.line("\n== table =="); var functions: usize = 0;
    for (names.items) |n| { const m = p.table.get(n).?; try p.unused(m); try macros.print("#define {s}", .{try m.signature(p.a)}); if (m.replacement.len > 0) try macros.print(" {s}", .{try lex.render(p.a, m.replacement, false)}); try macros.print("\n  at {s}:{d} expanded={d} tested={d} recursive={s}\n  refs:", .{m.position.file, m.position.line, m.expanded, m.tested, if (try recursive(p, n)) "yes" else "no"}); for (try references(p, m)) |ref| try macros.print(" {s}", .{ref}); try macros.add("\n"); if (m.parameters != null) functions += 1; }
    try macros.print("\nmacros={d} object_like={d} function_like={d}\nundefined:", .{names.items.len, names.items.len - functions, functions}); std.mem.sort(Text, p.ever.items, {}, less); for (p.ever.items) |n| if (!p.table.contains(n)) { try macros.print(" {s}", .{n}); }; try macros.print("\nbuiltins: __COUNTER__={d} __FILE__={d} __LINE__={d}\n", .{p.builtins[0], p.builtins[1], p.builtins[2]});
    var files: Buffer = .{ .a = p.a }; try files.line("main.c"); try files.add(p.tree.data.items); try files.line("\n== files ==");
    const ordered = try p.a.dupe(*includes.File, p.manager.order.items); std.mem.sort(*includes.File, ordered, {}, struct { fn cmp(_: void, a: *includes.File, b: *includes.File) bool { return less({}, a.path, b.path); } }.cmp);
    for (ordered) |f| try files.print("{s} entered={d} skipped={d} lines={d} output_lines={d} skipped_lines={d} guard={s} once={s}\n", .{f.path, f.entered, f.skipped, f.document.physical, f.output_lines, f.skipped_lines, f.guard orelse "-", if (f.once) "yes" else "no"});
    try files.add("\nmain.o:"); var length: usize = 7; var paths: usize = 0;
    for (p.manager.order.items) |f| { if (length + 1 + f.path.len > 76 and paths > 0) { try files.add(" \\\n "); length = 1; paths = 0; } try files.print(" {s}", .{f.path}); length += 1 + f.path.len; paths += 1; } try files.add("\n");
    try p.conditions.line("\n== skipped regions =="); try p.conditions.add(p.regions.data.items); const c = p.records; try p.conditions.print("\ndirectives={d} taken={d} not_taken={d} skipped={d} not_evaluated={d} endif={d} regions={d}\n", .{c[0] + c[1] + c[2] + c[3] + c[4], c[0], c[1], c[2], c[3], c[4], p.region_count}); try p.diagnostics.print("errors={d} warnings={d}\n", .{p.errors, p.warnings});
    for ([_]Text{"preprocessed.txt", "includes.txt", "macros.txt", "conditionals.txt", "diagnostics.txt"}, [_]Text{p.preprocessed.data.items, files.data.items, macros.data.items, p.conditions.data.items, p.diagnostics.data.items}) |name, data| { const file = try std.Io.Dir.cwd().createFile(p.manager.io, try std.fmt.allocPrint(p.a, "output/{s}", .{name}), .{}); defer file.close(p.manager.io); try file.writeStreamingAll(p.manager.io, data); }
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); const a = arena.allocator();
    var p: Processor = .{ .a = a, .manager = .{ .a = a, .io = init.io }, .preprocessed = .{ .a = a }, .tree = .{ .a = a }, .history = .{ .a = a }, .conditions = .{ .a = a }, .regions = .{ .a = a }, .diagnostics = .{ .a = a } };
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/defines.txt", a, .unlimited); var lines = std.mem.splitScalar(u8, source, '\n'); var number: i64 = 0;
    while (lines.next()) |line| { number += 1; if (line.len == 0) continue; var text: []u8 = undefined; if (std.mem.indexOfScalar(u8, line, '=')) |index| { text = try a.dupe(u8, line); text[index] = ' '; } else text = try std.fmt.allocPrint(a, "{s} 1", .{line}); const d = try lex.lex(a, try std.fmt.allocPrint(a, "{s}\n", .{text})); try p.define(d.lines[0].tokens, .{ .file = "defines.txt", .line = number }, false); }
    try p.marker(.{ .file = "main.c", .line = 1 }, ""); try p.process((try p.manager.get("main.c")).?, 0); try save(&p);
}
