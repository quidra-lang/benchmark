const std = @import("std");
const lex = @import("lexer.zig");
const parser = @import("parser.zig");
const vals = @import("values_fields.zig");
const builtins = @import("builtins.zig");
const streams = @import("streams.zig");
const Text = vals.Text;
const Value = vals.Value;
const Node = parser.Node;
const Array = std.StringHashMapUnmanaged(Value);
const Binding = struct { name: Text, scope: ?usize, array: bool = false, visible: bool = true };
const Slot = struct { value: Value = .{}, array: *Array };
const Function = struct { node: *Node, calls: usize = 0, active: usize = 0, depth: usize = 0 };
const Rule = struct { node: *Node, count: usize = 0, inside: bool = false };
const Issue = struct { position: lex.Position, message: Text, rank: usize = 0 };
const Buffer = struct { a: std.mem.Allocator, data: std.ArrayList(u8) = .empty,
    fn add(b: *Buffer, text: Text) !void { try b.data.appendSlice(b.a, text); }
    fn print(b: *Buffer, comptime f: Text, args: anytype) !void { try b.add(try std.fmt.allocPrint(b.a, f, args)); }
};
const Runtime = struct {
    a: std.mem.Allocator, items: []*Node, arguments: streams.Arguments, streams: streams.Streams,
    bindings: std.ArrayList(Binding) = .empty, functions: std.ArrayList(Function) = .empty, rules: std.ArrayList(Rule) = .empty,
    globals: []Slot = &.{}, locals: ?[]Slot = null, record: vals.Record = .{}, counts: [402]usize = @splat(0), statement_lines: [402]bool = @splat(false),
    issue: ?Issue = null, static_issue: ?Issue = null, phase: Text = "", return_value: Value = .{}, exit_status: i64 = 0,
    next_operand: usize = 0, current_operand: ?usize = null, current_lines: []const Text = &.{}, current_line: usize = 0,
    fn binding(r: *Runtime, name: Text, scope: ?usize, visible: bool) !usize { for (r.bindings.items, 0..) |*b, i| if (b.scope == scope and vals.eq(b.name, name)) { b.visible = b.visible or visible; return i; }; try r.bindings.append(r.a, .{ .name = name, .scope = scope, .visible = visible }); return r.bindings.items.len - 1; }
    fn function(r: *Runtime, name: Text) ?usize { for (r.functions.items, 0..) |f, i| if (vals.eq(f.node.name, name)) return i; return null; }
    fn staticError(r: *Runtime, pos: lex.Position, rank: usize, message: Text) void { const old = r.static_issue; if (old == null or pos.line < old.?.position.line or (pos.line == old.?.position.line and (pos.column < old.?.position.column or (pos.column == old.?.position.column and rank < old.?.rank)))) r.static_issue = .{ .position = pos, .message = message, .rank = rank }; }
    fn walk(r: *Runtime, n: *Node, scope: ?usize) anyerror!void {
        if (n.is("name") or n.is("array") or n.is("parameter")) {
            var local: ?usize = null; if (scope) |fi| for (r.functions.items[fi].node.params) |p| { if (vals.eq(p.name, n.name)) local = fi; };
            n.binding = try r.binding(n.name, local, true); if (r.function(n.name) != null) r.staticError(n.token.position, 2, try std.fmt.allocPrint(r.a, "function {s} used as variable", .{n.name}));
            if (n.is("array")) r.bindings.items[n.binding.?].array = true;
        }
        if (n.is("call")) {
            if (r.function(n.name)) |fi| { if (n.args.len > r.functions.items[fi].node.params.len) r.staticError(n.token.position, 4, try std.fmt.allocPrint(r.a, "too many arguments to {s}", .{n.name})); }
            else r.staticError(n.token.position, 3, try std.fmt.allocPrint(r.a, "undefined function {s}", .{n.name}));
        }
        if (isStatement(n)) r.statement_lines[n.token.position.line] = true;
        if (n.x) |x| try r.walk(x, scope); if (n.y) |y| try r.walk(y, scope); if (n.z) |z| try r.walk(z, scope); if (n.w) |w| try r.walk(w, scope); for (n.args) |child| try r.walk(child, scope);
        if (n.is("membership") or n.is("delete")) r.bindings.items[n.x.?.binding.?].array = true;
        if (n.is("for_in")) r.bindings.items[n.y.?.binding.?].array = true;
        if (n.is("builtin") and vals.eq(n.name, "split")) r.bindings.items[n.args[1].binding.?].array = true;
    }
    fn links(r: *Runtime, n: *Node) anyerror!bool {
        var changed = false;
        if (n.is("call")) if (r.function(n.name)) |fi| { for (n.args, 0..) |arg, i| { if (i >= r.functions.items[fi].node.params.len or !arg.is("name")) continue; const param = r.functions.items[fi].node.params[i]; const x = arg.binding.?; const y = param.binding.?; if (r.bindings.items[x].array != r.bindings.items[y].array) { r.bindings.items[x].array = true; r.bindings.items[y].array = true; changed = true; } } };
        if (n.x) |x| changed = try r.links(x) or changed; if (n.y) |y| changed = try r.links(y) or changed; if (n.z) |z| changed = try r.links(z) or changed; if (n.w) |w| changed = try r.links(w) or changed; for (n.args) |child| changed = try r.links(child) or changed; return changed;
    }
    fn prepare(r: *Runtime) !void {
        for (r.items) |n| if (n.is("function")) { if (r.function(n.name) != null) r.staticError(n.token.position, 0, try std.fmt.allocPrint(r.a, "function {s} redefined", .{n.name})); try r.functions.append(r.a, .{ .node = n }); } else try r.rules.append(r.a, .{ .node = n });
        for (r.functions.items, 0..) |f, fi| { for (f.node.params, 0..) |p, pi| { for (f.node.params[0..pi]) |previous| if (vals.eq(p.name, previous.name)) { r.staticError(p.token.position, 1, try std.fmt.allocPrint(r.a, "duplicate parameter {s}", .{p.name})); break; }; p.binding = try r.binding(p.name, fi, true); if (r.function(p.name) != null) r.staticError(p.token.position, 2, try std.fmt.allocPrint(r.a, "function {s} used as variable", .{p.name})); } try r.walk(f.node.x.?, fi); }
        for (r.rules.items) |rule| try r.walk(rule.node, null);
        if (r.static_issue != null) return;
        while (true) { var changed = false; for (r.items) |n| changed = try r.links(n) or changed; if (!changed) break; }
        for ([_]Text{"FS", "OFS", "ORS", "SUBSEP", "NR", "FNR", "FILENAME", "NF"}) |name| _ = try r.binding(name, null, true);
        for (r.arguments.options) |o| _ = try r.binding(o.name, null, false); for (r.arguments.operands) |o| if (o.assignment) { _ = try r.binding(o.name, null, false); };
        r.globals = try r.newSlots(); try r.setGlobal("FS", Value.string(" ")); try r.setGlobal("OFS", Value.string(" ")); try r.setGlobal("ORS", Value.string("\n")); try r.setGlobal("SUBSEP", Value.string("\x1c")); try r.setGlobal("NR", Value.number(0)); try r.setGlobal("FNR", Value.number(0)); try r.setGlobal("FILENAME", Value.string(""));
    }
    fn newSlots(r: *Runtime) ![]Slot { const slots = try r.a.alloc(Slot, r.bindings.items.len); for (slots) |*s| { const array = try r.a.create(Array); array.* = .empty; s.* = .{ .array = array }; } return slots; }
    fn globalIndex(r: *Runtime, name: Text) usize { for (r.bindings.items, 0..) |b, i| if (b.scope == null and vals.eq(b.name, name)) return i; unreachable; }
    fn global(r: *Runtime, name: Text) Value { return if (vals.eq(name, "NF")) Value.number(@intCast(r.record.fields.items.len)) else r.globals[r.globalIndex(name)].value; }
    fn setGlobal(r: *Runtime, name: Text, value: Value) !void { const index = r.globalIndex(name); r.bindings.items[index].visible = true; r.globals[index].value = value; }
    fn slot(r: *Runtime, index: usize) *Slot { return if (r.bindings.items[index].scope == null) &r.globals[index] else &r.locals.?[index]; }
    fn failure(r: *Runtime, pos: lex.Position, message: Text) error{Runtime} { r.issue = .{ .position = pos, .message = message }; return error.Runtime; }
    const Location = struct { binding: ?usize = null, subscript: ?Text = null, field: ?usize = null };
    fn key(r: *Runtime, nodes: []const *Node) !Text { var parts: std.ArrayList(Text) = .empty; for (nodes) |n| try parts.append(r.a, try (try r.eval(n)).text(r.a)); return std.mem.join(r.a, try r.global("SUBSEP").text(r.a), parts.items); }
    fn location(r: *Runtime, n: *Node) !Location {
        if (n.is("field")) { const index = (try r.eval(n.x.?)).num(); if (index < 0) return r.failure(n.token.position, "negative field index"); return .{ .field = @intCast(index) }; }
        return .{ .binding = n.binding.?, .subscript = if (n.is("array")) try r.key(n.args) else null };
    }
    fn get(r: *Runtime, loc: Location) !Value {
        if (loc.field) |k| return r.record.get(k); const index = loc.binding.?;
        if (loc.subscript) |subscript| { const array = r.slot(index).array; const entry = try array.getOrPut(r.a, subscript); if (!entry.found_existing) entry.value_ptr.* = .{}; return entry.value_ptr.*; }
        if (r.bindings.items[index].scope == null and vals.eq(r.bindings.items[index].name, "NF")) return r.global("NF"); return r.slot(index).value;
    }
    fn put(r: *Runtime, loc: Location, value: Value, pos: lex.Position) !Value {
        if (loc.field) |k| { if (k == 0) try r.record.set(r.a, try value.text(r.a), try r.global("FS").text(r.a)) else { if (k > r.record.fields.items.len) try r.record.resize(r.a, k); r.record.fields.items[k - 1] = value; try r.record.rebuild(r.a, try r.global("OFS").text(r.a)); } return r.record.get(k); }
        const index = loc.binding.?; if (loc.subscript) |subscript| { try r.slot(index).array.put(r.a, subscript, value); return value; }
        if (r.bindings.items[index].scope == null and vals.eq(r.bindings.items[index].name, "NF")) { const n = value.num(); if (n < 0) return r.failure(pos, "negative NF"); try r.record.resize(r.a, @intCast(n)); try r.record.rebuild(r.a, try r.global("OFS").text(r.a)); return r.global("NF"); }
        r.slot(index).value = value; return value;
    }
    fn arithmetic(r: *Runtime, op: Text, a: i64, b: i64, pos: lex.Position) !Value {
        if ((vals.eq(op, "/") or vals.eq(op, "%")) and b == 0) return r.failure(pos, "division by zero");
        if (vals.eq(op, "^") and b < 0) return r.failure(pos, "negative exponent");
        if (vals.eq(op, "+")) return Value.number(a + b); if (vals.eq(op, "-")) return Value.number(a - b); if (vals.eq(op, "*")) return Value.number(a * b); if (vals.eq(op, "/")) return Value.number(@divTrunc(a, b)); if (vals.eq(op, "%")) return Value.number(@rem(a, b));
        var result: i64 = 1; var base = a; var exponent: u64 = @intCast(b); while (exponent > 0) { if (exponent & 1 != 0) result *= base; exponent >>= 1; if (exponent > 0) base *= base; } return Value.number(result);
    }
    fn formatted(r: *Runtime, values: []const Value, pos: lex.Position) !Text { var issue: builtins.Issue = .invalid_format; return builtins.format(r.a, try values[0].text(r.a), values[1..], &issue) catch |err| switch (err) { error.Format => return r.failure(pos, switch (issue) { .invalid_format => "invalid format", .not_enough_arguments => "not enough arguments", .invalid_character_code => "invalid character code" }), else => return err }; }
    fn builtin(r: *Runtime, n: *Node) anyerror!Value {
        const name = n.name;
        if (vals.eq(name, "length")) { if (n.args.len == 0) return Value.number(@intCast((try r.record.zero.text(r.a)).len)); if (n.args[0].is("name") and r.bindings.items[n.args[0].binding.?].array) return Value.number(@intCast(r.slot(n.args[0].binding.?).array.count())); return Value.number(@intCast((try (try r.eval(n.args[0])).text(r.a)).len)); }
        if (vals.eq(name, "split")) { const text = try (try r.eval(n.args[0])).text(r.a); const sep = if (n.args.len == 3) try (try r.eval(n.args[2])).text(r.a) else try r.global("FS").text(r.a); const array = r.slot(n.args[1].binding.?).array; array.clearRetainingCapacity(); const pieces = try vals.split(r.a, text, sep); for (pieces, 1..) |piece, i| try array.put(r.a, try std.fmt.allocPrint(r.a, "{d}", .{i}), Value.input(piece)); return Value.number(@intCast(pieces.len)); }
        const args = try r.a.alloc(Value, n.args.len); for (n.args, 0..) |arg, i| args[i] = try r.eval(arg);
        if (vals.eq(name, "sprintf")) return Value.string(try r.formatted(args, n.token.position));
        if (vals.eq(name, "substr")) return Value.string(builtins.substr(try args[0].text(r.a), args[1].num(), if (args.len == 3) args[2].num() else null));
        if (vals.eq(name, "index")) return Value.number(builtins.index(try args[0].text(r.a), try args[1].text(r.a)));
        if (vals.eq(name, "close")) return Value.number(r.streams.close(try args[0].text(r.a))); if (vals.eq(name, "int")) return Value.number(args[0].num());
        return Value.string(try builtins.case(r.a, try args[0].text(r.a), vals.eq(name, "toupper")));
    }
    fn eval(r: *Runtime, n: *Node) anyerror!Value {
        if (n.is("number") or n.is("string")) return n.token.value; if (n.lvalue()) return r.get(try r.location(n)); if (n.is("paren")) return r.eval(n.x.?);
        if (n.is("assignment")) { const loc = try r.location(n.x.?); var value = try r.eval(n.y.?); if (!vals.eq(n.op, "=")) value = try r.arithmetic(n.op[0..1], (try r.get(loc)).num(), value.num(), n.token.position); return r.put(loc, value, n.token.position); }
        if (n.is("increment")) { const loc = try r.location(n.x.?); const old = (try r.get(loc)).num(); _ = try r.put(loc, Value.number(old + n.delta), n.token.position); return Value.number(if (n.flag) old + n.delta else old); }
        if (n.is("conditional")) return r.eval(if ((try r.eval(n.x.?)).truth()) n.y.? else n.z.?);
        if (n.is("unary")) { const value = try r.eval(n.x.?); return Value.number(if (vals.eq(n.op, "!")) @intFromBool(!value.truth()) else if (vals.eq(n.op, "-")) -value.num() else value.num()); }
        if (n.is("binary")) {
            const left = try r.eval(n.x.?); if (vals.eq(n.op, "||") and left.truth()) return Value.number(1); if (vals.eq(n.op, "&&") and !left.truth()) return Value.number(0); const right = try r.eval(n.y.?);
            if (vals.eq(n.op, "||") or vals.eq(n.op, "&&")) return Value.number(@intFromBool(right.truth()));
            if (vals.eq(n.op, "concat")) return Value.string(try std.mem.concat(r.a, u8, &.{try left.text(r.a), try right.text(r.a)}));
            if (lex.member(n.op, "< <= == != >= >")) { const order = try vals.compare(r.a, left, right); return Value.number(@intFromBool(if (vals.eq(n.op, "<")) order == .lt else if (vals.eq(n.op, "<=")) order != .gt else if (vals.eq(n.op, "==")) order == .eq else if (vals.eq(n.op, "!=")) order != .eq else if (vals.eq(n.op, ">=")) order != .lt else order == .gt)); }
            return r.arithmetic(n.op, left.num(), right.num(), n.token.position);
        }
        if (n.is("membership")) { const subscript = try r.key(n.args); return Value.number(@intFromBool(r.slot(n.x.?.binding.?).array.contains(subscript))); }
        if (n.is("builtin")) return r.builtin(n);
        if (n.is("call")) {
            const fi = r.function(n.name).?; const function_node = r.functions.items[fi].node; const locals = try r.newSlots();
            for (function_node.params, 0..) |param, i| { const parameter_binding = param.binding.?; if (r.bindings.items[parameter_binding].array) { if (i < n.args.len) locals[parameter_binding].array = r.slot(n.args[i].binding.?).array; } else if (i < n.args.len) locals[parameter_binding].value = try r.eval(n.args[i]); }
            const previous = r.locals; r.locals = locals; defer r.locals = previous; r.functions.items[fi].calls += 1; r.functions.items[fi].active += 1; r.functions.items[fi].depth = @max(r.functions.items[fi].depth, r.functions.items[fi].active); defer r.functions.items[fi].active -= 1;
            r.statement(function_node.x.?) catch |err| switch (err) { error.Return => return r.return_value, else => return err }; return .{};
        }
        if (n.is("getline")) {
            var text: ?Text = null; var status: i64 = 0;
            if (n.y) |filename| { const name = try (try r.eval(filename)).text(r.a); const read = try r.streams.getline(name); status = read.status; if (status == 1) text = read.line; }
            else if (!vals.eq(r.phase, "END")) { text = try r.nextRecord(); status = @intFromBool(text != null); }
            if (text) |line| { if (n.x) |target| { _ = try r.put(try r.location(target), Value.input(line), n.token.position); } else try r.record.set(r.a, line, try r.global("FS").text(r.a)); } return Value.number(status);
        }
        unreachable;
    }
    fn statement(r: *Runtime, n: *Node) anyerror!void {
        if (n.is("block")) { for (n.args) |child| try r.statement(child); return; } if (n.is("empty")) return; r.counts[n.token.position.line] += 1;
        if (n.is("expression_statement")) { _ = try r.eval(n.x.?); return; }
        if (n.is("if")) { if ((try r.eval(n.x.?)).truth()) try r.statement(n.y.?) else if (n.z) |other| try r.statement(other); return; }
        if (n.is("while") or n.is("do") or n.is("for")) {
            if (n.is("for")) if (n.x) |initial| { _ = try r.eval(initial); };
            var first = true;
            while (true) {
                if (!(n.is("do") and first)) { const condition = if (n.is("for")) n.y else n.x; if (condition) |c| { if (!(try r.eval(c)).truth()) break; } } first = false;
                const body = if (n.is("for")) n.w.? else n.y.?;
                r.statement(body) catch |err| switch (err) { error.Break => break, error.Continue => {}, else => return err };
                if (n.is("for")) if (n.z) |update| { _ = try r.eval(update); };
            } return;
        }
        if (n.is("for_in")) {
            const array = r.slot(n.y.?.binding.?).array; const keys = try r.a.alloc(Text, array.count()); var it = array.keyIterator(); var index: usize = 0; while (it.next()) |subscript| { keys[index] = subscript.*; index += 1; } std.mem.sort(Text, keys, {}, vals.keyLess);
            for (keys) |subscript| { _ = try r.put(try r.location(n.x.?), Value.input(subscript), n.x.?.token.position); r.statement(n.z.?) catch |err| switch (err) { error.Break => break, error.Continue => continue, else => return err }; } return;
        }
        if (n.is("break")) return error.Break; if (n.is("continue")) return error.Continue;
        if (n.is("next")) { if (vals.eq(r.phase, "BEGIN") or vals.eq(r.phase, "END")) return r.failure(n.token.position, "next used in BEGIN or END"); return error.Next; }
        if (n.is("exit")) { if (n.x) |value| r.exit_status = (try r.eval(value)).num(); return error.Exit; }
        if (n.is("return")) { r.return_value = if (n.x) |value| try r.eval(value) else .{}; return error.Return; }
        if (n.is("delete")) { const array = r.slot(n.x.?.binding.?).array; if (n.flag) { _ = array.remove(try r.key(n.args)); } else array.clearRetainingCapacity(); return; }
        if (n.is("print") or n.is("printf")) {
            var args: std.ArrayList(Value) = .empty; for (n.args) |arg| try args.append(r.a, try r.eval(arg)); var text: Text = "";
            if (n.is("printf")) text = try r.formatted(args.items, n.token.position)
            else { if (args.items.len == 0) try args.append(r.a, r.record.zero); var parts: std.ArrayList(Text) = .empty; for (args.items) |value| try parts.append(r.a, try value.text(r.a)); text = try std.mem.concat(r.a, u8, &.{try std.mem.join(r.a, try r.global("OFS").text(r.a), parts.items), try r.global("ORS").text(r.a)}); }
            var name: ?Text = null; if (n.x) |filename| { name = try (try r.eval(filename)).text(r.a); if (!streams.valid(name.?) or vals.eq(name.?, "stdout.txt") or vals.eq(name.?, "stats.txt")) return r.failure(n.redir.?.position, "invalid output file name"); }
            try r.streams.write(name, n.redir != null and vals.eq(n.redir.?.spelling, ">>"), text); return;
        }
        unreachable;
    }
    fn nextRecord(r: *Runtime) anyerror!?Text {
        while (true) {
            if (r.current_operand) |index| { if (r.current_line < r.current_lines.len) { const text = r.current_lines[r.current_line]; r.current_line += 1; r.arguments.operands[index].records += 1; try r.setGlobal("NR", Value.number(r.global("NR").num() + 1)); try r.setGlobal("FNR", Value.number(r.global("FNR").num() + 1)); return text; } r.current_operand = null; }
            if (r.next_operand == r.arguments.operands.len) return null; const index = r.next_operand; r.next_operand += 1; const operand = r.arguments.operands[index];
            if (operand.assignment) { try r.setGlobal(operand.name, Value.input(operand.value)); continue; }
            r.current_operand = index; r.current_line = 0; r.current_lines = (try r.streams.readFile(operand.name)).?; try r.setGlobal("FILENAME", Value.string(operand.name)); try r.setGlobal("FNR", Value.number(0));
        }
    }
    fn actions(r: *Runtime, phase: Text) !void { r.phase = phase; for (r.rules.items, 0..) |rule, i| if (vals.eq(rule.node.op, phase)) { r.rules.items[i].count += 1; try r.statement(rule.node.x.?); }; }
    fn records(r: *Runtime) !void {
        r.phase = "record";
        while (try r.nextRecord()) |text| {
            try r.record.set(r.a, text, try r.global("FS").text(r.a));
            for (r.rules.items, 0..) |rule, ri| {
                const n = rule.node; if (vals.eq(n.op, "BEGIN") or vals.eq(n.op, "END")) continue;
                var matches = true;
                if (vals.eq(n.op, "pattern")) matches = (try r.eval(n.args[0])).truth()
                else if (vals.eq(n.op, "range")) { if (!r.rules.items[ri].inside) r.rules.items[ri].inside = (try r.eval(n.args[0])).truth(); matches = r.rules.items[ri].inside; if (matches and (try r.eval(n.args[1])).truth()) r.rules.items[ri].inside = false; }
                if (!matches) continue; r.rules.items[ri].count += 1;
                if (n.x) |action| r.statement(action) catch |err| switch (err) { error.Next => break, else => return err }
                else try r.streams.write(null, false, try std.mem.concat(r.a, u8, &.{try r.record.zero.text(r.a), try r.global("ORS").text(r.a)}));
            }
        }
    }
    fn execute(r: *Runtime) !void {
        for (r.arguments.options) |option| try r.setGlobal(option.name, Value.input(option.value));
        var exit = false; r.actions("BEGIN") catch |err| switch (err) { error.Exit => exit = true, else => return err };
        if (!exit) { var has_records = false; for (r.rules.items) |rule| if (!vals.eq(rule.node.op, "BEGIN")) { has_records = true; }; if (has_records) r.records() catch |err| switch (err) { error.Exit => {}, else => return err }; }
        r.actions("END") catch |err| switch (err) { error.Exit => {}, else => return err };
    }
    fn stats(r: *Runtime) !Text {
        var b: Buffer = .{ .a = r.a };
        if (r.issue) |issue| try b.print("status: runtime error at {d}:{d}: {s}\n", .{issue.position.line, issue.position.column, issue.message}) else try b.print("status: exit {d}\n", .{r.exit_status});
        try b.add("[inputs]\n"); for (r.arguments.operands) |operand| if (!operand.assignment) { try b.print("{s} records={d}\n", .{operand.name, operand.records}); };
        try b.add("[getline]\n"); for (r.streams.inputs.items) |input| { if (input.ever) try b.print("{s} reads={d}\n", .{input.name, input.reads}) else try b.print("{s} missing\n", .{input.name}); }
        try b.add("[rules]\n"); for (r.rules.items) |rule| try b.print("{d}:{d} {s} count={d}\n", .{rule.node.token.position.line, rule.node.token.position.column, rule.node.op, rule.count});
        try b.add("[functions]\n"); for (r.functions.items) |f| try b.print("{s} calls={d} depth={d}\n", .{f.node.name, f.calls, f.depth});
        try b.print("[outputs]\nstdout.txt writes={d} bytes={d}\n", .{r.streams.stdout.writes, r.streams.stdout.bytes.items.len}); for (r.streams.outputs.items) |out| try b.print("{s} writes={d} bytes={d}\n", .{out.name, out.writes, out.bytes.items.len});
        try b.add("[lines]\n"); for (r.statement_lines, 0..) |present, line| if (present) { try b.print("{d} count={d}\n", .{line, r.counts[line]}); };
        var names: std.ArrayList(Text) = .empty; for (r.bindings.items) |descriptor| if (descriptor.scope == null and descriptor.visible) { try names.append(r.a, descriptor.name); }; std.mem.sort(Text, names.items, {}, struct { fn less(_: void, a: Text, c: Text) bool { return std.mem.order(u8, a, c) == .lt; } }.less);
        try b.add("[globals]\n"); for (names.items) |name| { const index = r.globalIndex(name); if (r.bindings.items[index].array) try b.print("{s} = array ({d})\n", .{name, r.globals[index].array.count()}) else try b.print("{s} = {s}\n", .{name, try vals.shown(r.a, r.global(name))}); } return b.data.items;
    }
};
fn isStatement(n: *Node) bool { return lex.member(n.kind, "if while do for for_in print printf delete next break continue exit return expression_statement"); }
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); const a = arena.allocator(); var output: streams.Streams = .{ .a = a, .io = init.io };
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/program.awk", a, .unlimited); var lexer: lex.Lexer = .{ .a = a, .source = source };
    const tokens = lexer.tokenize() catch |err| switch (err) { error.Syntax => { try output.save(try std.fmt.allocPrint(a, "status: syntax error at {d}:{d}\n", .{lexer.issue.line, lexer.issue.column})); return; }, else => return err };
    var parsing: parser.Parser = .{ .a = a, .tokens = tokens }; const items = parsing.parse() catch |err| switch (err) { error.Syntax => { try output.save(try std.fmt.allocPrint(a, "status: syntax error at {d}:{d}\n", .{parsing.issue.line, parsing.issue.column})); return; }, else => return err };
    var runtime: Runtime = .{ .a = a, .items = items, .arguments = try streams.args(a, try std.Io.Dir.cwd().readFileAlloc(init.io, "input/args.txt", a, .unlimited)), .streams = output };
    try runtime.prepare(); if (runtime.static_issue) |issue| { try runtime.streams.save(try std.fmt.allocPrint(a, "status: error at {d}:{d}: {s}\n", .{issue.position.line, issue.position.column, issue.message})); return; }
    runtime.execute() catch |err| switch (err) { error.Runtime => {}, else => return err }; try runtime.streams.save(try runtime.stats());
}
