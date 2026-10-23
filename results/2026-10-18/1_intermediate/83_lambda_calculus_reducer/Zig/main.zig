const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid, NotTypable};
var failure: Text = "";
fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn member(items: []const Text, value: Text) bool { for (items) |item| if (equal(item, value)) return true; return false; }
fn lower(c: u8) bool { return c >= 'a' and c <= 'z'; }
fn upper(c: u8) bool { return c >= 'A' and c <= 'Z'; }
fn digit(c: u8) bool { return c >= '0' and c <= '9'; }
const reserved = [_]Text{ "S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV" };
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void { try self.bytes.appendSlice(self.gpa, text); }
    fn print(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        const text = try std.fmt.allocPrint(self.gpa, format, args);
        defer self.gpa.free(text);
        try self.add(text);
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void { try self.print(format ++ "\n", args); }
};
const Kind = enum { variable, macro, numeral, abstraction, application, index, constant };
const Term = struct {
    kind: Kind,
    name: Text = "",
    value: usize = 0,
    left: ?*Term = null,
    right: ?*Term = null,
    free: std.StringHashMapUnmanaged(void) = .empty,
    freeReady: bool = false,
    alive: bool = true,
    marked: bool = false,
};
const Pool = struct {
    gpa: Allocator,
    nodes: std.ArrayList(*Term) = .empty,
    available: std.ArrayList(*Term) = .empty,
    fn node(self: *Pool, term: Term) Error!*Term {
        if (self.available.pop()) |result| { result.* = term; return result; }
        const result = try self.gpa.create(Term);
        result.* = term;
        try self.nodes.append(self.gpa, result);
        return result;
    }
    fn variable(self: *Pool, name: Text) Error!*Term { return self.node(.{ .kind = .variable, .name = name }); }
    fn abstraction(self: *Pool, name: Text, body: *Term) Error!*Term { return self.node(.{ .kind = .abstraction, .name = name, .left = body }); }
    fn application(self: *Pool, function: *Term, argument: *Term) Error!*Term { return self.node(.{ .kind = .application, .left = function, .right = argument }); }
    fn constant(self: *Pool, name: Text) Error!*Term { return self.node(.{ .kind = .constant, .name = name }); }
    fn mark(term: *Term) void {
        if (term.marked) return;
        term.marked = true;
        if (term.left) |child| mark(child);
        if (term.right) |child| mark(child);
    }
    fn collect(self: *Pool, macros: std.StringHashMapUnmanaged(*Term), roots: []const *Term, current: ?*Term) Error!void {
        for (self.nodes.items) |term| term.marked = false;
        var iterator = macros.valueIterator();
        while (iterator.next()) |term| mark(term.*);
        for (roots) |term| mark(term);
        if (current) |term| mark(term);
        for (self.nodes.items) |term| if (term.alive and !term.marked) {
            term.free.deinit(std.heap.page_allocator);
            term.free = .empty;
            term.alive = false;
            try self.available.append(self.gpa, term);
        };
    }
    fn deinit(self: *Pool) void { for (self.nodes.items) |term| if (term.alive) term.free.deinit(std.heap.page_allocator); }
};
fn freeVariables(term: *Term) Error!*std.StringHashMapUnmanaged(void) {
    if (term.freeReady) return &term.free;
    if (term.kind == .variable) {
        try term.free.put(std.heap.page_allocator, term.name, {});
    } else if (term.kind == .abstraction or term.kind == .application) {
        var iterator = (try freeVariables(term.left.?)).keyIterator();
        while (iterator.next()) |name| if (term.kind != .abstraction or !equal(name.*, term.name)) try term.free.put(std.heap.page_allocator, name.*, {});
        if (term.kind == .application) {
            var right = (try freeVariables(term.right.?)).keyIterator();
            while (right.next()) |name| try term.free.put(std.heap.page_allocator, name.*, {});
        }
    }
    term.freeReady = true;
    return &term.free;
}
fn hasFree(term: *Term, name: Text) Error!bool { return (try freeVariables(term)).contains(name); }
fn sortedKeys(gpa: Allocator, set: anytype) Error![]const Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = set.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, struct { fn less(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; } }.less);
    return result.items;
}
fn printInto(term: *Term, end: bool, debruijn: bool, out: *Builder) Error!void {
    switch (term.kind) {
        .variable, .macro, .constant => try out.add(term.name),
        .index => try out.print("{d}", .{term.value}),
        .numeral => try out.print("#{d}", .{term.value}),
        .abstraction => {
            if (!end) try out.add("(");
            var body = term;
            if (!debruijn) try out.add("\\");
            var count: usize = 0;
            while (body.kind == .abstraction) {
                if (debruijn) { try out.add("\\"); } else { if (count > 0) try out.add(" "); try out.add(body.name); }
                count += 1;
                body = body.left.?;
            }
            if (!debruijn) try out.add(". ");
            try printInto(body, true, debruijn, out);
            if (!end) try out.add(")");
        },
        .application => {
            try printInto(term.left.?, false, debruijn, out);
            try out.add(" ");
            if (term.right.?.kind == .application) { try out.add("("); try printInto(term.right.?, true, debruijn, out); try out.add(")"); }
            else try printInto(term.right.?, end, debruijn, out);
        },
    }
}
fn printed(term: *Term, debruijn: bool) Error![]u8 {
    var out: Builder = .{ .gpa = std.heap.page_allocator };
    errdefer out.bytes.deinit(out.gpa);
    try printInto(term, true, debruijn, &out);
    return out.bytes.toOwnedSlice(out.gpa);
}
fn nameSequence(gpa: Allocator, index: usize) Error!Text {
    const letter: u8 = 'a' + @as(u8, @intCast(index % 26));
    return if (index < 26) try std.fmt.allocPrint(gpa, "{c}", .{letter}) else try std.fmt.allocPrint(gpa, "{c}{d}", .{ letter, index / 26 });
}
fn substitute(pool: *Pool, term: *Term, name: Text, replacement: *Term) Error!*Term {
    if (term.kind == .variable) return if (equal(term.name, name)) replacement else term;
    if (term.kind == .application) return pool.application(try substitute(pool, term.left.?, name, replacement), try substitute(pool, term.right.?, name, replacement));
    if (term.kind != .abstraction or equal(term.name, name) or !try hasFree(term.left.?, name)) return term;
    var binder = term.name;
    var body = term.left.?;
    if (try hasFree(replacement, binder)) {
        var end = binder.len;
        while (end > 0 and digit(binder[end - 1])) end -= 1;
        var index: usize = 1;
        while (true) : (index += 1) {
            const candidate = try std.fmt.allocPrint(pool.gpa, "{s}{d}", .{ binder[0..end], index });
            if (!try hasFree(replacement, candidate) and !try hasFree(body, candidate)) { binder = candidate; break; }
        }
        body = try substitute(pool, body, term.name, try pool.variable(binder));
    }
    return pool.abstraction(binder, try substitute(pool, body, name, replacement));
}
const Binding = struct { original: Text, renamed: Text };
const Canonicalizer = struct {
    pool: *Pool,
    free: *std.StringHashMapUnmanaged(void),
    bound: std.ArrayList(Binding) = .empty,
    counter: usize = 0,
    fromDB: bool = false,
    fn visit(self: *Canonicalizer, term: *Term) Error!*Term {
        if (term.kind == .variable) {
            if (!self.fromDB) {
                var i = self.bound.items.len;
                while (i > 0) { i -= 1; if (equal(self.bound.items[i].original, term.name)) return self.pool.variable(self.bound.items[i].renamed); }
            }
            return term;
        }
        if (term.kind == .index) return self.pool.variable(self.bound.items[self.bound.items.len - 1 - term.value].renamed);
        if (term.kind == .application) return self.pool.application(try self.visit(term.left.?), try self.visit(term.right.?));
        var name: Text = undefined;
        while (true) {
            name = try nameSequence(self.pool.gpa, self.counter);
            self.counter += 1;
            if (!self.free.contains(name)) break;
        }
        try self.bound.append(std.heap.page_allocator, .{ .original = term.name, .renamed = name });
        const body = try self.visit(term.left.?);
        _ = self.bound.pop();
        return self.pool.abstraction(name, body);
    }
};
fn canonical(pool: *Pool, term: *Term, fromDB: bool) Error!*Term {
    var converter: Canonicalizer = .{ .pool = pool, .free = try freeVariables(term), .fromDB = fromDB };
    defer converter.bound.deinit(std.heap.page_allocator);
    return converter.visit(term);
}
fn deBruijn(pool: *Pool, term: *Term, bound: *std.ArrayList(Text)) Error!*Term {
    if (term.kind == .variable) {
        var i = bound.items.len;
        while (i > 0) { i -= 1; if (equal(bound.items[i], term.name)) return pool.node(.{ .kind = .index, .value = bound.items.len - 1 - i }); }
        return term;
    }
    if (term.kind == .application) return pool.application(try deBruijn(pool, term.left.?, bound), try deBruijn(pool, term.right.?, bound));
    try bound.append(std.heap.page_allocator, term.name);
    const body = try deBruijn(pool, term.left.?, bound);
    _ = bound.pop();
    return pool.abstraction("", body);
}
const TokenKind = enum { variable, macro, numeral, symbol, end };
const Token = struct { kind: TokenKind, text: Text = "", column: usize, value: usize = 0 };
const Parser = struct {
    bench: *Workbench,
    tokens: []const Token,
    position: usize = 0,
    fn peek(self: *Parser) Token { return self.tokens[self.position]; }
    fn expect(self: *Parser, kind: Text) Error!Token {
        const token = self.peek();
        const matches = if (equal(kind, "variable")) token.kind == .variable else if (equal(kind, "macro")) token.kind == .macro else token.kind == .symbol and equal(token.text, kind);
        if (!matches) {
            if (equal(kind, "variable")) return self.bench.bad("column {d}: expected variable", .{token.column});
            if (equal(kind, "macro")) return self.bench.bad("column {d}: expected macro name", .{token.column});
            return self.bench.bad("column {d}: expected '{s}'", .{ token.column, kind });
        }
        self.position += 1;
        return token;
    }
    fn readTerm(self: *Parser) Error!*Term {
        var elements: std.ArrayList(*Term) = .empty;
        while (true) {
            const token = self.peek();
            if (!(token.kind == .variable or token.kind == .macro or token.kind == .numeral or equal(token.text, "("))) break;
            self.position += 1;
            var value: *Term = undefined;
            if (equal(token.text, "(")) { value = try self.readTerm(); _ = try self.expect(")"); }
            else value = try self.bench.pool.node(.{ .kind = switch (token.kind) { .variable => .variable, .macro => .macro, .numeral => .numeral, else => unreachable }, .name = token.text, .value = token.value });
            try elements.append(self.bench.scratch, value);
        }
        if (equal(self.peek().text, "\\")) {
            self.position += 1;
            var names: std.ArrayList(Text) = .empty;
            try names.append(self.bench.scratch, (try self.expect("variable")).text);
            while (self.peek().kind == .variable) try names.append(self.bench.scratch, (try self.expect("variable")).text);
            _ = try self.expect(".");
            var value = try self.readTerm();
            var i = names.items.len;
            while (i > 0) { i -= 1; value = try self.bench.pool.abstraction(names.items[i], value); }
            try elements.append(self.bench.scratch, value);
        }
        if (elements.items.len == 0) return self.bench.bad("column {d}: expected term", .{self.peek().column});
        var result = elements.items[0];
        for (elements.items[1..]) |next| result = try self.bench.pool.application(result, next);
        return result;
    }
    fn finish(self: *Parser) Error!void { const token = self.peek(); if (token.kind != .end) return self.bench.bad("column {d}: unexpected '{s}'", .{ token.column, token.text }); }
};
fn references(term: *Term, result: *std.ArrayList(Text), gpa: Allocator) Error!void {
    if (term.kind == .macro) { try result.append(gpa, term.name); }
    else if (term.kind == .abstraction) { try references(term.left.?, result, gpa); }
    else if (term.kind == .application) { try references(term.left.?, result, gpa); try references(term.right.?, result, gpa); }
}
const Step = struct { term: *Term, kind: Text };
fn etaRedex(term: *Term) Error!bool {
    return term.kind == .abstraction and term.left.?.kind == .application and term.left.?.right.?.kind == .variable and equal(term.left.?.right.?.name, term.name) and !try hasFree(term.left.?.left.?, term.name);
}
fn oneStep(pool: *Pool, term: *Term, strategy: Text, eta: bool) Error!?Step {
    if (term.kind == .application) {
        if (member(&.{ "NORMAL", "CBN" }, strategy) and term.left.?.kind == .abstraction) return Step{ .term = try substitute(pool, term.left.?.left.?, term.left.?.name, term.right.?), .kind = "beta" };
        if (try oneStep(pool, term.left.?, strategy, eta)) |step| return Step{ .term = try pool.application(step.term, term.right.?), .kind = step.kind };
        if (equal(strategy, "CBN")) return null;
        if (try oneStep(pool, term.right.?, strategy, eta)) |step| return Step{ .term = try pool.application(term.left.?, step.term), .kind = step.kind };
        if (term.left.?.kind == .abstraction and (!equal(strategy, "CBV") or term.right.?.kind == .variable or term.right.?.kind == .abstraction)) return Step{ .term = try substitute(pool, term.left.?.left.?, term.left.?.name, term.right.?), .kind = "beta" };
    } else if (term.kind == .abstraction and !member(&.{ "CBN", "CBV" }, strategy)) {
        if (equal(strategy, "NORMAL") and eta and try etaRedex(term)) return Step{ .term = term.left.?.left.?, .kind = "eta" };
        if (try oneStep(pool, term.left.?, strategy, eta)) |step| return Step{ .term = try pool.abstraction(term.name, step.term), .kind = step.kind };
        if (eta and try etaRedex(term)) return Step{ .term = term.left.?.left.?, .kind = "eta" };
    }
    return null;
}
fn termSize(term: *Term) usize { return switch (term.kind) { .variable => 1, .abstraction => 1 + termSize(term.left.?), else => 1 + termSize(term.left.?) + termSize(term.right.?) }; }
fn termDepth(term: *Term) usize { return switch (term.kind) { .variable => 1, .abstraction => 1 + termDepth(term.left.?), else => 1 + @max(termDepth(term.left.?), termDepth(term.right.?)) }; }

const SimpleType = struct { left: ?*SimpleType = null, right: ?*SimpleType = null, link: ?*SimpleType = null };
fn resolve(value: *SimpleType) *SimpleType { if (value.link) |next| { value.link = resolve(next); return value.link.?; } return value; }
fn occurs(variableType: *SimpleType, raw: *SimpleType) bool {
    const value = resolve(raw);
    return variableType == value or value.left != null and (occurs(variableType, value.left.?) or occurs(variableType, value.right.?));
}
fn unify(rawA: *SimpleType, rawB: *SimpleType) Error!void {
    const a = resolve(rawA);
    const b = resolve(rawB);
    if (a == b) return;
    if (a.left == null) { if (occurs(a, b)) return error.NotTypable; a.link = b; return; }
    if (b.left == null) return unify(b, a);
    try unify(a.left.?, b.left.?);
    try unify(a.right.?, b.right.?);
}
const TypeBinding = struct { name: Text, value: *SimpleType };
const TypeInference = struct {
    gpa: Allocator,
    free: std.StringHashMapUnmanaged(*SimpleType) = .empty,
    bound: std.ArrayList(TypeBinding) = .empty,
    names: std.AutoHashMapUnmanaged(*SimpleType, usize) = .empty,
    fn fresh(self: *TypeInference) Error!*SimpleType { const value = try self.gpa.create(SimpleType); value.* = .{}; return value; }
    fn arrow(self: *TypeInference, left: *SimpleType, right: *SimpleType) Error!*SimpleType { const value = try self.fresh(); value.left = left; value.right = right; return value; }
    fn infer(self: *TypeInference, term: *Term) Error!*SimpleType {
        if (term.kind == .variable) {
            var i = self.bound.items.len;
            while (i > 0) { i -= 1; if (equal(self.bound.items[i].name, term.name)) return self.bound.items[i].value; }
            if (self.free.get(term.name)) |value| return value;
            const value = try self.fresh();
            try self.free.put(self.gpa, term.name, value);
            return value;
        }
        if (term.kind == .abstraction) {
            const argument = try self.fresh();
            try self.bound.append(self.gpa, .{ .name = term.name, .value = argument });
            const body = try self.infer(term.left.?);
            _ = self.bound.pop();
            return self.arrow(argument, body);
        }
        const function = try self.infer(term.left.?);
        const argument = try self.infer(term.right.?);
        const result = try self.fresh();
        try unify(function, try self.arrow(argument, result));
        return result;
    }
    fn print(self: *TypeInference, raw: *SimpleType, out: *Builder) Error!void {
        const value = resolve(raw);
        if (value.left == null) {
            const entry = try self.names.getOrPut(self.gpa, value);
            if (!entry.found_existing) entry.value_ptr.* = self.names.count() - 1;
            try out.add(try nameSequence(self.gpa, entry.value_ptr.*));
            return;
        }
        const parentheses = resolve(value.left.?).left != null;
        if (parentheses) try out.add("(");
        try self.print(value.left.?, out);
        if (parentheses) try out.add(")");
        try out.add(" -> ");
        try self.print(value.right.?, out);
    }
};
fn churchInto(pool: *Pool, term: *Term, out: *Builder) Error!void {
    if (term.kind == .abstraction and term.left.?.kind == .abstraction) {
        const outer = term.name;
        const inner = term.left.?.name;
        var body = term.left.?.left.?;
        var count: usize = 0;
        while (body.kind == .application and body.left.?.kind == .variable and equal(body.left.?.name, outer)) { count += 1; body = body.right.?; }
        if (body.kind == .variable and equal(body.name, inner)) { try out.print("{d}", .{count}); return; }
        if (term.left.?.left.?.kind == .variable and equal(term.left.?.left.?.name, outer)) { try out.add("true"); return; }
    }
    if (term.kind == .abstraction and term.left.?.kind == .application and term.left.?.left.?.kind == .application) {
        const body = term.left.?;
        const function = body.left.?.left.?;
        if (function.kind == .variable and equal(function.name, term.name) and !try hasFree(body.left.?.right.?, term.name) and !try hasFree(body.right.?, term.name)) {
            try out.add("("); try churchInto(pool, body.left.?.right.?, out); try out.add(", "); try churchInto(pool, body.right.?, out); try out.add(")"); return;
        }
    }
    try printInto(try canonical(pool, term, false), true, false, out);
}
fn abstractSKI(pool: *Pool, name: Text, term: *Term) Error!*Term {
    if (!try hasFree(term, name)) return pool.application(try pool.constant("K"), term);
    if (term.kind == .variable) return pool.constant("I");
    if (term.right.?.kind == .variable and equal(term.right.?.name, name) and !try hasFree(term.left.?, name)) return term.left.?;
    return pool.application(try pool.application(try pool.constant("S"), try abstractSKI(pool, name, term.left.?)), try abstractSKI(pool, name, term.right.?));
}
fn ski(pool: *Pool, term: *Term) Error!*Term {
    if (term.kind == .variable) return term;
    if (term.kind == .application) return pool.application(try ski(pool, term.left.?), try ski(pool, term.right.?));
    return abstractSKI(pool, term.name, try ski(pool, term.left.?));
}
fn skiStep(pool: *Pool, term: *Term) Error!?Step {
    var head = term;
    var arguments: std.ArrayList(*Term) = .empty;
    defer arguments.deinit(std.heap.page_allocator);
    while (head.kind == .application) { try arguments.append(std.heap.page_allocator, head.right.?); head = head.left.?; }
    std.mem.reverse(*Term, arguments.items);
    var result: ?*Term = null;
    var used: usize = 0;
    var kind: Text = "";
    if (head.kind == .constant) {
        if (equal(head.name, "I") and arguments.items.len >= 1) { result = arguments.items[0]; used = 1; kind = "I"; }
        else if (equal(head.name, "K") and arguments.items.len >= 2) { result = arguments.items[0]; used = 2; kind = "K"; }
        else if (equal(head.name, "S") and arguments.items.len >= 3) { result = try pool.application(try pool.application(arguments.items[0], arguments.items[2]), try pool.application(arguments.items[1], arguments.items[2])); used = 3; kind = "S"; }
    }
    if (result != null) {
        for (arguments.items[used..]) |argument| result = try pool.application(result.?, argument);
        return Step{ .term = result.?, .kind = kind };
    }
    for (arguments.items, 0..) |argument, i| if (try skiStep(pool, argument)) |step| {
        var value = head;
        for (arguments.items, 0..) |item, j| value = try pool.application(value, if (i == j) step.term else item);
        return Step{ .term = value, .kind = step.kind };
    };
    return null;
}
const Closure = struct { code: *Term, environment: []const *Closure };
fn reify(pool: *Pool, initialCode: *Term, initialEnvironment: []const *Closure, initialInside: usize) Error!*Term {
    var code = initialCode;
    var environment = initialEnvironment;
    var inside = initialInside;
    while (code.kind == .index and code.value >= inside) {
        const closure = environment[code.value - inside];
        code = closure.code;
        environment = closure.environment;
        inside = 0;
    }
    if (code.kind == .variable or code.kind == .index) return code;
    if (code.kind == .abstraction) return pool.abstraction("", try reify(pool, code.left.?, environment, inside + 1));
    return pool.application(try reify(pool, code.left.?, environment, inside), try reify(pool, code.right.?, environment, inside));
}
const Reduction = struct { term: *Term, count: usize, success: bool };
const Workbench = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Builder,
    pool: Pool,
    macros: std.StringHashMapUnmanaged(*Term) = .empty,
    roots: []const *Term = &.{},
    steps: bool = false,
    eta: bool = false,
    limit: usize = 10000,
    fn bad(self: *Workbench, comptime format: Text, args: anytype) Error {
        failure = std.fmt.allocPrint(self.gpa, format, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn initialize(self: *Workbench) Error!void {
        try self.macros.put(self.gpa, "I", try self.pool.abstraction("x", try self.pool.variable("x")));
        try self.macros.put(self.gpa, "K", try self.pool.abstraction("x", try self.pool.abstraction("y", try self.pool.variable("x"))));
        const body = try self.pool.application(try self.pool.application(try self.pool.variable("x"), try self.pool.variable("z")), try self.pool.application(try self.pool.variable("y"), try self.pool.variable("z")));
        try self.macros.put(self.gpa, "S", try self.pool.abstraction("x", try self.pool.abstraction("y", try self.pool.abstraction("z", body))));
    }
    fn lex(self: *Workbench, line: Text, text: Text, offset: usize) Error![]const Token {
        var tokens: std.ArrayList(Token) = .empty;
        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == ' ') { i += 1; continue; }
            const start = i;
            var kind: TokenKind = undefined;
            const c = text[i];
            if (std.mem.findScalar(u8, "\\.()=;", c) != null) { kind = .symbol; i += 1; }
            else if (lower(c)) { kind = .variable; while (i < text.len and (lower(text[i]) or digit(text[i]))) i += 1; }
            else if (upper(c)) { kind = .macro; while (i < text.len and (upper(text[i]) or digit(text[i]) or text[i] == '_')) i += 1; }
            else if (c == '#' and i + 1 < text.len and digit(text[i + 1])) { kind = .numeral; i += 1; while (i < text.len and digit(text[i])) i += 1; }
            else return self.bad("column {d}: unexpected character '{c}'", .{ offset + i + 1, c });
            try tokens.append(self.scratch, .{ .kind = kind, .text = text[start..i], .column = offset + start + 1, .value = if (kind == .numeral) std.fmt.parseInt(usize, text[start + 1 .. i], 10) catch unreachable else 0 });
        }
        try tokens.append(self.scratch, .{ .kind = .end, .column = line.len + 1 });
        return tokens.items;
    }
    fn expand(self: *Workbench, term: *Term) Error!*Term {
        switch (term.kind) {
            .variable => return term,
            .macro => { const value = self.macros.get(term.name) orelse return self.bad("unbound macro {s}", .{term.name}); return self.expand(value); },
            .numeral => {
                var body = try self.pool.variable("x");
                for (0..term.value) |_| body = try self.pool.application(try self.pool.variable("f"), body);
                return self.pool.abstraction("f", try self.pool.abstraction("x", body));
            },
            .abstraction => return self.pool.abstraction(term.name, try self.expand(term.left.?)),
            else => return self.pool.application(try self.expand(term.left.?), try self.expand(term.right.?)),
        }
    }
    fn refs(self: *Workbench, term: *Term) Error![]const Text { var result: std.ArrayList(Text) = .empty; try references(term, &result, self.scratch); return result.items; }
    fn depends(self: *Workbench, name: Text, target: Text, seen: *std.StringHashMapUnmanaged(void)) Error!bool {
        if (equal(name, target)) return true;
        if (seen.contains(name) or member(reserved[0..3], name)) return false;
        const term = self.macros.get(name) orelse return false;
        try seen.put(self.scratch, name, {});
        for (try self.refs(term)) |reference| if (try self.depends(reference, target, seen)) return true;
        return false;
    }
    fn show(self: *Workbench, term: *Term, db: bool) Error!void {
        const text = try printed(term, db);
        defer std.heap.page_allocator.free(text);
        try self.out.line("{s}", .{text});
    }
    fn reduce(self: *Workbench, initialTerm: *Term, strategy: Text, eta: bool, display: bool) Error!Reduction {
        var term = initialTerm;
        var count: usize = 0;
        while (true) {
            const step = (try oneStep(&self.pool, term, strategy, eta)) orelse return .{ .term = term, .count = count, .success = true };
            if (count == self.limit) return .{ .term = term, .count = count, .success = false };
            term = step.term;
            count += 1;
            if (display) {
                const text = try printed(term, false); defer std.heap.page_allocator.free(text);
                try self.out.line("step {d} ({s}): {s}", .{ count, step.kind, text });
            }
            try self.pool.collect(self.macros, self.roots, term);
        }
    }
    fn equivalent(self: *Workbench, a: *Term, b: *Term) Error!bool {
        var bound: std.ArrayList(Text) = .empty;
        defer bound.deinit(std.heap.page_allocator);
        const left = try deBruijn(&self.pool, a, &bound);
        const right = try deBruijn(&self.pool, b, &bound);
        const first = try printed(left, true); defer std.heap.page_allocator.free(first);
        const second = try printed(right, true); defer std.heap.page_allocator.free(second);
        return equal(first, second);
    }
    fn kam(self: *Workbench, term: *Term) Error!void {
        var bound: std.ArrayList(Text) = .empty;
        defer bound.deinit(std.heap.page_allocator);
        var code = try deBruijn(&self.pool, term, &bound);
        var environment: []const *Closure = &.{};
        var stack: std.ArrayList(*Closure) = .empty;
        var count: usize = 0;
        while (true) {
            const kind: Text = if (code.kind == .application) "push" else if (code.kind == .index) "access" else if (code.kind == .abstraction and stack.items.len > 0) "grab" else "";
            if (kind.len == 0) break;
            if (count == self.limit) { try self.out.line("no result within {d} transitions", .{self.limit}); return; }
            count += 1;
            if (equal(kind, "push")) {
                const closure = try self.scratch.create(Closure);
                closure.* = .{ .code = code.right.?, .environment = environment };
                try stack.append(self.scratch, closure);
                code = code.left.?;
            } else if (equal(kind, "grab")) {
                const next = try self.scratch.alloc(*Closure, environment.len + 1);
                next[0] = stack.pop().?;
                @memcpy(next[1..], environment);
                environment = next;
                code = code.left.?;
            } else { const closure = environment[code.value]; code = closure.code; environment = closure.environment; }
            if (self.steps) {
                const text = try printed(code, true); defer std.heap.page_allocator.free(text);
                try self.out.line("step {d} ({s}): {s} [env {d}, stack {d}]", .{ count, kind, text, environment.len, stack.items.len });
            }
        }
        var result = try reify(&self.pool, code, environment, 0);
        var i = stack.items.len;
        while (i > 0) { i -= 1; result = try self.pool.application(result, try reify(&self.pool, stack.items[i].code, stack.items[i].environment, 0)); }
        const text = try printed(try canonical(&self.pool, result, true), false); defer std.heap.page_allocator.free(text);
        try self.out.line("result: {s} (transitions: {d})", .{ text, count });
    }
    fn command(self: *Workbench, line: Text) Error!void {
        if (line.len == 0 or std.mem.startsWith(u8, line, "--")) return;
        const separator = std.mem.findScalar(u8, line, ' ') orelse line.len;
        const name = line[0..separator];
        const arguments = if (separator < line.len) line[separator + 1 ..] else "";
        const offset = if (separator < line.len) separator + 1 else separator;
        if (!member(&.{ "let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam" }, name)) return self.bad("unknown command {s}", .{name});
        if (member(&.{ "unlet", "macros", "steps", "eta", "limit" }, name)) {
            var parts: std.ArrayList(Text) = .empty;
            var iterator = std.mem.tokenizeScalar(u8, arguments, ' ');
            while (iterator.next()) |part| try parts.append(self.scratch, part);
            if (equal(name, "steps") or equal(name, "eta")) {
                if (parts.items.len != 1 or !member(&.{ "on", "off" }, parts.items[0])) return self.bad("bad argument", .{});
                if (equal(name, "steps")) { self.steps = equal(parts.items[0], "on"); } else self.eta = equal(parts.items[0], "on");
            } else if (equal(name, "limit")) {
                if (parts.items.len != 1 or parts.items[0].len == 0 or parts.items[0].len > 5) return self.bad("bad argument", .{});
                for (parts.items[0]) |c| if (!digit(c)) return self.bad("bad argument", .{});
                const value = std.fmt.parseInt(usize, parts.items[0], 10) catch unreachable;
                if (value < 1 or value > 10000) return self.bad("bad argument", .{});
                self.limit = value;
            } else if (equal(name, "macros")) {
                if (parts.items.len != 0) return self.bad("bad argument", .{});
                var count: usize = 0;
                for (try sortedKeys(self.scratch, self.macros)) |macroName| {
                    if (member(reserved[0..3], macroName)) continue;
                    const text = try printed(self.macros.get(macroName).?, false); defer std.heap.page_allocator.free(text);
                    try self.out.line("{s} = {s}", .{ macroName, text });
                    count += 1;
                }
                if (count == 0) try self.out.line("(none)", .{});
            } else {
                if (parts.items.len != 1 or !validMacro(parts.items[0])) return self.bad("bad argument", .{});
                const macroName = parts.items[0];
                if (member(&reserved, macroName)) return self.bad("reserved name {s}", .{macroName});
                if (!self.macros.contains(macroName)) return self.bad("unbound macro {s}", .{macroName});
                for (try sortedKeys(self.scratch, self.macros)) |other| if (member(try self.refs(self.macros.get(other).?), macroName)) return self.bad("{s} is used by {s}", .{ macroName, other });
                _ = self.macros.remove(macroName);
                try self.out.line("removed {s}", .{macroName});
            }
            return;
        }
        var parser: Parser = .{ .bench = self, .tokens = try self.lex(line, arguments, offset) };
        var targetName: Text = "";
        var strategy: Text = "NORMAL";
        if (equal(name, "let") or equal(name, "subst")) {
            targetName = (try parser.expect(if (equal(name, "let")) "macro" else "variable")).text;
            _ = try parser.expect("=");
        }
        if (equal(name, "reduce") and parser.peek().kind == .macro and member(reserved[3..], parser.peek().text)) { strategy = parser.peek().text; parser.position += 1; }
        var first = try parser.readTerm();
        var second: ?*Term = null;
        if (member(&.{ "subst", "equal", "alpha" }, name)) { _ = try parser.expect(";"); second = try parser.readTerm(); }
        try parser.finish();
        if (equal(name, "let")) {
            if (member(&reserved, targetName)) return self.bad("reserved name {s}", .{targetName});
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            for (try self.refs(first)) |reference| {
                if (try self.depends(reference, targetName, &seen)) return self.bad("recursive definition of {s}", .{targetName});
                if (!self.macros.contains(reference)) return self.bad("unbound macro {s}", .{reference});
            }
            const free = try sortedKeys(self.scratch, (try freeVariables(first)).*);
            if (free.len > 0) return self.bad("free variable {s} in definition of {s}", .{ free[0], targetName });
            const existed = self.macros.contains(targetName);
            try self.macros.put(self.gpa, targetName, first);
            try self.out.line("{s} {s}", .{ if (existed) "redefined" else "defined", targetName });
            return;
        }
        first = try self.expand(first);
        if (second) |term| second = try self.expand(term);
        var roots: std.ArrayList(*Term) = .empty;
        try roots.append(self.scratch, first);
        if (second) |term| try roots.append(self.scratch, term);
        self.roots = roots.items;
        if (equal(name, "expand")) { try self.show(first, false); }
        else if (equal(name, "subst")) { try self.show(try substitute(&self.pool, second.?, targetName, first), false); }
        else if (equal(name, "alpha")) { try self.out.line("{s}", .{if (try self.equivalent(first, second.?)) "yes" else "no"}); }
        else if (equal(name, "equal")) {
            const a = try self.reduce(first, "NORMAL", self.eta, false);
            const preserved = try self.scratch.dupe(*Term, &.{ first, second.?, a.term });
            self.roots = preserved;
            const b = try self.reduce(second.?, "NORMAL", self.eta, false);
            try self.out.line("{s}", .{if (!a.success or !b.success) "unknown" else if (try self.equivalent(a.term, b.term)) "yes" else "no"});
        } else if (equal(name, "debruijn")) {
            var bound: std.ArrayList(Text) = .empty; defer bound.deinit(std.heap.page_allocator);
            try self.show(try deBruijn(&self.pool, first, &bound), true);
        } else if (equal(name, "fv")) {
            const names = try sortedKeys(self.scratch, (try freeVariables(first)).*);
            if (names.len == 0) { try self.out.line("(none)", .{}); } else {
                for (names, 0..) |item, i| { if (i > 0) try self.out.add(" "); try self.out.add(item); }
                try self.out.add("\n");
            }
        } else if (equal(name, "size")) { try self.out.line("{d}", .{termSize(first)}); }
        else if (equal(name, "depth")) { try self.out.line("{d}", .{termDepth(first)}); }
        else if (equal(name, "type")) {
            var inference: TypeInference = .{ .gpa = self.scratch };
            const principal = inference.infer(first) catch |err| { if (err != error.NotTypable) return err; try self.out.line("not typable", .{}); return; };
            var text: Builder = .{ .gpa = std.heap.page_allocator }; defer text.bytes.deinit(text.gpa);
            try inference.print(principal, &text);
            try self.out.line("{s}", .{text.bytes.items});
        } else if (equal(name, "church")) {
            const result = try self.reduce(first, "NORMAL", false, false);
            if (!result.success) { try self.out.line("no normal form within {d} steps", .{self.limit}); } else {
                var text: Builder = .{ .gpa = std.heap.page_allocator }; defer text.bytes.deinit(text.gpa);
                try churchInto(&self.pool, try canonical(&self.pool, result.term, false), &text);
                try self.out.line("{s}", .{text.bytes.items});
            }
        } else if (equal(name, "ski")) { try self.show(try ski(&self.pool, first), false); }
        else if (equal(name, "skireduce")) {
            var value = try ski(&self.pool, first);
            var count: usize = 0;
            while (true) {
                const step = (try skiStep(&self.pool, value)) orelse {
                    const text = try printed(value, false); defer std.heap.page_allocator.free(text);
                    try self.out.line("result: {s} (steps: {d})", .{ text, count }); break;
                };
                if (count == self.limit) { try self.out.line("no normal form within {d} steps", .{self.limit}); break; }
                value = step.term;
                count += 1;
                if (self.steps) {
                    const text = try printed(value, false); defer std.heap.page_allocator.free(text);
                    try self.out.line("step {d} ({s}): {s}", .{ count, step.kind, text });
                }
                try self.pool.collect(self.macros, self.roots, value);
            }
        } else if (equal(name, "kam")) { try self.kam(first); }
        else if (equal(name, "reduce")) {
            const result = try self.reduce(first, strategy, self.eta, self.steps);
            if (!result.success) { try self.out.line("no normal form within {d} steps", .{self.limit}); } else {
                const text = try printed(try canonical(&self.pool, result.term, false), false); defer std.heap.page_allocator.free(text);
                try self.out.line("result: {s} (steps: {d})", .{ text, result.count });
            }
        }
    }
};
fn validMacro(name: Text) bool {
    if (name.len == 0 or !upper(name[0])) return false;
    for (name) |c| if (!upper(c) and !digit(c) and c != '_') return false;
    return true;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var out: Builder = .{ .gpa = std.heap.page_allocator };
    defer out.bytes.deinit(out.gpa);
    var bench: Workbench = .{ .gpa = gpa, .scratch = gpa, .out = &out, .pool = .{ .gpa = gpa } };
    defer bench.pool.deinit();
    try bench.initialize();
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "quit")) break;
        var commandArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer commandArena.deinit();
        bench.scratch = commandArena.allocator();
        bench.roots = &.{};
        bench.command(line) catch |err| { if (err != error.Invalid) return err; try out.line("error: {s}", .{failure}); };
        bench.roots = &.{};
        try bench.pool.collect(bench.macros, &.{}, null);
        try output.interface.writeAll(out.bytes.items);
        out.bytes.clearRetainingCapacity();
    }
    try output.interface.flush();
}
