const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";
fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn includes(text: Text, choices: []const Text) bool {
    for (choices) |choice| if (eq(text, choice)) return true;
    return false;
}
fn bad(gpa: Allocator, comptime format: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, format, args) catch return error.OutOfMemory;
    return error.Invalid;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, format, args));
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.print(format ++ "\n", args);
    }
};
fn split(gpa: Allocator, text: Text, separator: u8) Error![]const Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = std.mem.splitScalar(u8, text, separator);
    while (iterator.next()) |part| try result.append(gpa, part);
    return result.items;
}
fn series(gpa: Allocator, prefix: Text, n: usize) Error![]const Text {
    const names = try gpa.alloc(Text, n);
    for (names, 0..) |*name, i| name.* = try std.fmt.allocPrint(gpa, "{s}{d}", .{ prefix, i });
    return names;
}
fn orderedSet(gpa: Allocator, present: []const bool) Error![]const usize {
    var result: std.ArrayList(usize) = .empty;
    for (present, 0..) |presentFlag, i| if (presentFlag) try result.append(gpa, i);
    return result.items;
}
fn setKey(gpa: Allocator, states: []const usize) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (states) |state| try out.print("{d},", .{state});
    return out.bytes.items;
}
fn emptyWord(text: Text) Text {
    return if (text.len == 0) "e" else text;
}
fn yes(value: bool) Text {
    return if (value) "yes" else "no";
}
fn symbolCharacter(c: u8) bool {
    return c >= 'a' and c <= 'z' or std.ascii.isDigit(c);
}
const Transition = struct { from: usize, symbol: u8, to: usize };
const Automaton = struct {
    gpa: Allocator,
    nfa: bool,
    states: []const Text,
    alphabet: Text,
    start: usize,
    final: []bool,
    transitions: std.ArrayList(Transition) = .empty,
    fn create(gpa: Allocator, nfa: bool, states: []const Text, alphabet: Text, start: usize) Error!*Automaton {
        const result = try gpa.create(Automaton);
        result.* = .{ .gpa = gpa, .nfa = nfa, .states = states, .alphabet = alphabet, .start = start, .final = try gpa.alloc(bool, states.len) };
        @memset(result.final, false);
        return result;
    }
    fn add(self: *Automaton, from: usize, symbol: u8, to: usize) Error!void {
        for (self.transitions.items) |t| if (t.from == from and t.symbol == symbol and t.to == to) return;
        try self.transitions.append(self.gpa, .{ .from = from, .symbol = symbol, .to = to });
    }
    fn delta(self: *const Automaton, state: usize, c: u8) usize {
        for (self.transitions.items) |t| if (t.from == state and t.symbol == c) return t.to;
        unreachable;
    }
    fn destinations(self: *const Automaton, gpa: Allocator, state: usize, c: u8) Error![]const usize {
        const present = try gpa.alloc(bool, self.states.len);
        @memset(present, false);
        for (self.transitions.items) |t| if (t.from == state and t.symbol == c) {
            present[t.to] = true;
        };
        return orderedSet(gpa, present);
    }
    fn closure(self: *const Automaton, gpa: Allocator, states: []const usize) Error![]const usize {
        const present = try gpa.alloc(bool, self.states.len);
        @memset(present, false);
        var queue: std.ArrayList(usize) = .empty;
        for (states) |state| if (!present[state]) {
            present[state] = true;
            try queue.append(gpa, state);
        };
        var i: usize = 0;
        while (i < queue.items.len) : (i += 1) for (self.transitions.items) |t| {
            if (t.from == queue.items[i] and t.symbol == 'e' and !present[t.to]) {
                present[t.to] = true;
                try queue.append(gpa, t.to);
            }
        };
        return orderedSet(gpa, present);
    }
    fn step(self: *const Automaton, gpa: Allocator, states: []const usize, c: u8) Error![]const usize {
        const present = try gpa.alloc(bool, self.states.len);
        @memset(present, false);
        for (states) |state| present[state] = true;
        var destinationsList: std.ArrayList(usize) = .empty;
        for (self.transitions.items) |t| if (present[t.from] and t.symbol == c) try destinationsList.append(gpa, t.to);
        return self.closure(gpa, destinationsList.items);
    }
    fn accepts(self: *const Automaton, states: []const usize) bool {
        for (states) |state| if (self.final[state]) return true;
        return false;
    }
    fn setText(self: *const Automaton, gpa: Allocator, states: []const usize) Error!Text {
        var out: Builder = .{ .gpa = gpa };
        try out.add("{");
        for (states, 0..) |state, i| {
            if (i > 0) try out.add(",");
            try out.add(self.states[state]);
        }
        try out.add("}");
        return out.bytes.items;
    }
    fn listText(self: *const Automaton, gpa: Allocator, states: []const usize) Error!Text {
        if (states.len == 0) return "none";
        var out: Builder = .{ .gpa = gpa };
        for (states, 0..) |state, i| {
            if (i > 0) try out.add(",");
            try out.add(self.states[state]);
        }
        return out.bytes.items;
    }
    fn summary(self: *const Automaton, out: *Builder, name: Text) Error!void {
        var count: usize = 0;
        for (self.final) |accepting| if (accepting) {
            count += 1;
        };
        try out.line("{s} {s}: alphabet={s} states={d} accepting={d} transitions={d}", .{ if (self.nfa) "NFA" else "DFA", name, self.alphabet, self.states.len, count, self.transitions.items.len });
    }
};
const Subsets = struct { automaton: *Automaton, sets: []const []const usize };
fn determinize(gpa: Allocator, a: *const Automaton) Error!Subsets {
    var sets: std.ArrayList([]const usize) = .empty;
    try sets.append(gpa, try a.closure(gpa, &.{a.start}));
    var indices: std.StringHashMapUnmanaged(usize) = .empty;
    try indices.put(gpa, try setKey(gpa, sets.items[0]), 0);
    var rows: std.ArrayList([]const usize) = .empty;
    var i: usize = 0;
    while (i < sets.items.len) : (i += 1) {
        var row: std.ArrayList(usize) = .empty;
        for (a.alphabet) |c| {
            const next = try a.step(gpa, sets.items[i], c);
            const key = try setKey(gpa, next);
            const entry = try indices.getOrPut(gpa, key);
            if (!entry.found_existing) {
                entry.value_ptr.* = sets.items.len;
                try sets.append(gpa, next);
            }
            try row.append(gpa, entry.value_ptr.*);
        }
        try rows.append(gpa, row.items);
    }
    const result = try Automaton.create(gpa, false, try series(gpa, "D", sets.items.len), a.alphabet, 0);
    for (sets.items, rows.items, 0..) |set, row, state| {
        result.final[state] = a.accepts(set);
        for (a.alphabet, row) |c, next| try result.add(state, c, next);
    }
    return .{ .automaton = result, .sets = sets.items };
}
fn graphReach(gpa: Allocator, a: *const Automaton, starts: []const usize, reverse: bool) Error![]bool {
    const present = try gpa.alloc(bool, a.states.len);
    @memset(present, false);
    var queue: std.ArrayList(usize) = .empty;
    for (starts) |state| if (!present[state]) {
        present[state] = true;
        try queue.append(gpa, state);
    };
    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) for (a.transitions.items) |t| {
        const from = if (reverse) t.to else t.from;
        const to = if (reverse) t.from else t.to;
        if (from == queue.items[i] and !present[to]) {
            present[to] = true;
            try queue.append(gpa, to);
        }
    };
    return present;
}
fn partitionText(gpa: Allocator, a: *const Automaton, blocks: []const []const usize) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (blocks, 0..) |block, i| {
        if (i > 0) try out.add(" ");
        try out.add(try a.setText(gpa, block));
    }
    return out.bytes.items;
}
const Minimized = struct { automaton: *Automaton, details: []const Text };
fn minimize(gpa: Allocator, a: *const Automaton) Error!Minimized {
    const reachable = try graphReach(gpa, a, &.{a.start}, false);
    var missing: std.ArrayList(usize) = .empty;
    var blocks: std.ArrayList(std.ArrayList(usize)) = .empty;
    var byFinal = [_]?usize{ null, null };
    for (a.states, 0..) |_, state| {
        if (!reachable[state]) {
            try missing.append(gpa, state);
            continue;
        }
        const key: usize = if (a.final[state]) 1 else 0;
        if (byFinal[key] == null) {
            byFinal[key] = blocks.items.len;
            try blocks.append(gpa, .empty);
        }
        try blocks.items[byFinal[key].?].append(gpa, state);
    }
    var details: std.ArrayList(Text) = .empty;
    try details.append(gpa, try std.fmt.allocPrint(gpa, "  unreachable: {s}", .{try a.listText(gpa, missing.items)}));
    var printedBlocks: std.ArrayList([]const usize) = .empty;
    for (blocks.items) |block| try printedBlocks.append(gpa, block.items);
    try details.append(gpa, try std.fmt.allocPrint(gpa, "  round 0: {s}", .{try partitionText(gpa, a, printedBlocks.items)}));
    var round: usize = 1;
    const membership = try gpa.alloc(usize, a.states.len);
    while (true) : (round += 1) {
        for (blocks.items, 0..) |block, index| for (block.items) |state| {
            membership[state] = index;
        };
        var next: std.ArrayList(std.ArrayList(usize)) = .empty;
        var signatures: std.StringHashMapUnmanaged(usize) = .empty;
        for (a.states, 0..) |_, state| {
            if (!reachable[state]) continue;
            var signature: std.ArrayList(usize) = .empty;
            try signature.append(gpa, membership[state]);
            for (a.alphabet) |c| try signature.append(gpa, membership[a.delta(state, c)]);
            const entry = try signatures.getOrPut(gpa, try setKey(gpa, signature.items));
            if (!entry.found_existing) {
                entry.value_ptr.* = next.items.len;
                try next.append(gpa, .empty);
            }
            try next.items[entry.value_ptr.*].append(gpa, state);
        }
        if (next.items.len == blocks.items.len) break;
        blocks = next;
        printedBlocks.clearRetainingCapacity();
        for (blocks.items) |block| try printedBlocks.append(gpa, block.items);
        try details.append(gpa, try std.fmt.allocPrint(gpa, "  round {d}: {s}", .{ round, try partitionText(gpa, a, printedBlocks.items) }));
    }
    for (blocks.items, 0..) |block, index| for (block.items) |state| {
        membership[state] = index;
    };
    var order: std.ArrayList(usize) = .empty;
    try order.append(gpa, membership[a.start]);
    var indices: std.AutoHashMapUnmanaged(usize, usize) = .empty;
    try indices.put(gpa, order.items[0], 0);
    var rows: std.ArrayList([]const usize) = .empty;
    var i: usize = 0;
    while (i < order.items.len) : (i += 1) {
        const representative = blocks.items[order.items[i]].items[0];
        var row: std.ArrayList(usize) = .empty;
        for (a.alphabet) |c| {
            const group = membership[a.delta(representative, c)];
            const entry = try indices.getOrPut(gpa, group);
            if (!entry.found_existing) {
                entry.value_ptr.* = order.items.len;
                try order.append(gpa, group);
            }
            try row.append(gpa, entry.value_ptr.*);
        }
        try rows.append(gpa, row.items);
    }
    const result = try Automaton.create(gpa, false, try series(gpa, "M", order.items.len), a.alphabet, 0);
    for (order.items, rows.items, 0..) |group, row, index| {
        result.final[index] = a.final[blocks.items[group].items[0]];
        for (a.alphabet, row) |c, next| try result.add(index, c, next);
        try details.append(gpa, try std.fmt.allocPrint(gpa, "  M{d} = {s}", .{ index, try a.setText(gpa, blocks.items[group].items) }));
    }
    return .{ .automaton = result, .details = details.items };
}
const Pair = struct { left: usize, right: usize };
const Product = struct { automaton: *Automaton, details: []const Text };
fn product(gpa: Allocator, a: *const Automaton, b: *const Automaton, command: Text) Error!Product {
    var pairs: std.ArrayList(Pair) = .empty;
    try pairs.append(gpa, .{ .left = a.start, .right = b.start });
    var indices: std.AutoHashMapUnmanaged(Pair, usize) = .empty;
    try indices.put(gpa, pairs.items[0], 0);
    var rows: std.ArrayList([]const usize) = .empty;
    var i: usize = 0;
    while (i < pairs.items.len) : (i += 1) {
        const pair = pairs.items[i];
        var row: std.ArrayList(usize) = .empty;
        for (a.alphabet) |c| {
            const next: Pair = .{ .left = a.delta(pair.left, c), .right = b.delta(pair.right, c) };
            const entry = try indices.getOrPut(gpa, next);
            if (!entry.found_existing) {
                entry.value_ptr.* = pairs.items.len;
                try pairs.append(gpa, next);
            }
            try row.append(gpa, entry.value_ptr.*);
        }
        try rows.append(gpa, row.items);
    }
    const result = try Automaton.create(gpa, false, try series(gpa, "P", pairs.items.len), a.alphabet, 0);
    var details: std.ArrayList(Text) = .empty;
    for (pairs.items, rows.items, 0..) |pair, row, index| {
        const x = a.final[pair.left];
        const y = b.final[pair.right];
        result.final[index] = eq(command, "UNION") and (x or y) or eq(command, "INTERSECT") and x and y or eq(command, "DIFF") and x and !y;
        for (a.alphabet, row) |c, next| try result.add(index, c, next);
        try details.append(gpa, try std.fmt.allocPrint(gpa, "  P{d} = ({s},{s})", .{ index, a.states[pair.left], b.states[pair.right] }));
    }
    return .{ .automaton = result, .details = details.items };
}
fn witness(gpa: Allocator, a: *const Automaton) Error!?Text {
    const Item = struct { state: usize, word: Text };
    var queue: std.ArrayList(Item) = .empty;
    try queue.append(gpa, .{ .state = a.start, .word = "" });
    const seen = try gpa.alloc(bool, a.states.len);
    @memset(seen, false);
    seen[a.start] = true;
    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const item = queue.items[i];
        if (a.final[item.state]) return item.word;
        for (a.alphabet) |c| {
            const next = a.delta(item.state, c);
            if (!seen[next]) {
                seen[next] = true;
                try queue.append(gpa, .{ .state = next, .word = try std.fmt.allocPrint(gpa, "{s}{c}", .{ item.word, c }) });
            }
        }
    }
    return null;
}
const Difference = struct { word: Text, left: bool };
fn equivalent(gpa: Allocator, a: *const Automaton, b: *const Automaton) Error!?Difference {
    const Item = struct { pair: Pair, word: Text };
    var queue: std.ArrayList(Item) = .empty;
    const initial: Pair = .{ .left = a.start, .right = b.start };
    try queue.append(gpa, .{ .pair = initial, .word = "" });
    var seen: std.AutoHashMapUnmanaged(Pair, void) = .empty;
    try seen.put(gpa, initial, {});
    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const item = queue.items[i];
        const pair = item.pair;
        if (a.final[pair.left] != b.final[pair.right]) return .{ .word = item.word, .left = a.final[pair.left] };
        for (a.alphabet) |c| {
            const next: Pair = .{ .left = a.delta(pair.left, c), .right = b.delta(pair.right, c) };
            if (!seen.contains(next)) {
                try seen.put(gpa, next, {});
                try queue.append(gpa, .{ .pair = next, .word = try std.fmt.allocPrint(gpa, "{s}{c}", .{ item.word, c }) });
            }
        }
    }
    return null;
}
const CycleSearch = struct {
    automaton: *const Automaton,
    live: []const bool,
    colors: []u8,
    fn visit(self: *CycleSearch, state: usize) bool {
        self.colors[state] = 1;
        for (self.automaton.alphabet) |c| {
            const next = self.automaton.delta(state, c);
            if (!self.live[next]) continue;
            if (self.colors[next] == 1 or self.colors[next] == 0 and self.visit(next)) return true;
        }
        self.colors[state] = 2;
        return false;
    }
};
const Language = struct { classification: Text, live: []const bool };
fn language(gpa: Allocator, a: *const Automaton) Error!Language {
    const live = try graphReach(gpa, a, try orderedSet(gpa, a.final), true);
    if (!live[a.start]) return .{ .classification = "empty", .live = live };
    const colors = try gpa.alloc(u8, a.states.len);
    @memset(colors, 0);
    var search: CycleSearch = .{ .automaton = a, .live = live, .colors = colors };
    return .{ .classification = if (search.visit(a.start)) "infinite" else "finite", .live = live };
}
const FiniteCounter = struct {
    automaton: *const Automaton,
    live: []const bool,
    memo: []?i64,
    fn count(self: *FiniteCounter, state: usize) i64 {
        if (!self.live[state]) return 0;
        if (self.memo[state]) |value| return value;
        var total: i64 = if (self.automaton.final[state]) 1 else 0;
        for (self.automaton.alphabet) |c| total += self.count(self.automaton.delta(state, c));
        self.memo[state] = total;
        return total;
    }
};
fn finiteCount(gpa: Allocator, a: *const Automaton, live: []const bool) Error!i64 {
    const memo = try gpa.alloc(?i64, a.states.len);
    @memset(memo, null);
    var counter: FiniteCounter = .{ .automaton = a, .live = live, .memo = memo };
    return counter.count(a.start);
}
fn countLength(gpa: Allocator, a: *const Automaton, n: usize) Error!i64 {
    var counts = try gpa.alloc(i64, a.states.len);
    @memset(counts, 0);
    counts[a.start] = 1;
    for (0..n) |_| {
        const next = try gpa.alloc(i64, a.states.len);
        @memset(next, 0);
        for (counts, 0..) |count, state| for (a.alphabet) |c| {
            next[a.delta(state, c)] += count;
        };
        counts = next;
    }
    var total: i64 = 0;
    for (counts, a.final) |count, accepting| if (accepting) {
        total += count;
    };
    return total;
}
const Synchronizing = struct { word: Text, state: usize };
fn synchronize(gpa: Allocator, a: *const Automaton) Error!?Synchronizing {
    const Item = struct { states: []const usize, word: Text };
    const initial = try gpa.alloc(usize, a.states.len);
    for (initial, 0..) |*state, i| state.* = i;
    var queue: std.ArrayList(Item) = .empty;
    try queue.append(gpa, .{ .states = initial, .word = "" });
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    try seen.put(gpa, try setKey(gpa, initial), {});
    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const item = queue.items[i];
        if (item.states.len == 1) return .{ .word = item.word, .state = item.states[0] };
        for (a.alphabet) |c| {
            const present = try gpa.alloc(bool, a.states.len);
            @memset(present, false);
            for (item.states) |state| present[a.delta(state, c)] = true;
            const next = try orderedSet(gpa, present);
            const key = try setKey(gpa, next);
            if (!seen.contains(key)) {
                try seen.put(gpa, key, {});
                try queue.append(gpa, .{ .states = next, .word = try std.fmt.allocPrint(gpa, "{s}{c}", .{ item.word, c }) });
            }
        }
    }
    return null;
}
const Regex = struct { kind: u8, children: []const *Regex = &.{} };
const RegexParser = struct {
    gpa: Allocator,
    source: Text,
    position: usize = 0,
    fn peek(self: *RegexParser) u8 {
        return if (self.position < self.source.len) self.source[self.position] else 0;
    }
    fn invalid(self: *RegexParser) Error {
        return bad(self.gpa, "syntax error at {d}", .{self.position + 1});
    }
    fn node(self: *RegexParser, kind: u8, children: []const *Regex) Error!*Regex {
        const result = try self.gpa.create(Regex);
        result.* = .{ .kind = kind, .children = children };
        return result;
    }
    fn atom(self: *RegexParser) Error!*Regex {
        const c = self.peek();
        if (symbolCharacter(c)) {
            self.position += 1;
            return self.node(c, &.{});
        }
        if (c == '(') {
            self.position += 1;
            const result = try self.alternation();
            if (self.peek() != ')') return self.invalid();
            self.position += 1;
            return result;
        }
        return self.invalid();
    }
    fn factor(self: *RegexParser) Error!*Regex {
        var result = try self.atom();
        while (std.mem.findScalar(u8, "*+?", self.peek()) != null and self.peek() != 0) {
            const c = self.peek();
            self.position += 1;
            result = try self.node(c, try self.gpa.dupe(*Regex, &.{result}));
        }
        return result;
    }
    fn concatenation(self: *RegexParser) Error!*Regex {
        var children: std.ArrayList(*Regex) = .empty;
        try children.append(self.gpa, try self.factor());
        while (symbolCharacter(self.peek()) or self.peek() == '(') try children.append(self.gpa, try self.factor());
        return if (children.items.len == 1) children.items[0] else self.node('.', children.items);
    }
    fn alternation(self: *RegexParser) Error!*Regex {
        var children: std.ArrayList(*Regex) = .empty;
        try children.append(self.gpa, try self.concatenation());
        while (self.peek() == '|') {
            self.position += 1;
            try children.append(self.gpa, try self.concatenation());
        }
        return if (children.items.len == 1) children.items[0] else self.node('|', children.items);
    }
};
const Part = struct { start: usize, end: usize };
const Thompson = struct {
    gpa: Allocator,
    next: usize = 0,
    transitions: std.ArrayList(Transition) = .empty,
    fn state(self: *Thompson) usize {
        const index = self.next;
        self.next += 1;
        return index;
    }
    fn add(self: *Thompson, from: usize, symbol: u8, to: usize) Error!void {
        try self.transitions.append(self.gpa, .{ .from = from, .symbol = symbol, .to = to });
    }
    fn build(self: *Thompson, tree: *const Regex) Error!Part {
        if (tree.children.len == 0) {
            const start = self.state();
            const end = self.state();
            try self.add(start, tree.kind, end);
            return .{ .start = start, .end = end };
        }
        if (tree.kind == '.') {
            var result = try self.build(tree.children[0]);
            for (tree.children[1..]) |child| {
                const part = try self.build(child);
                try self.add(result.end, 'e', part.start);
                result.end = part.end;
            }
            return result;
        }
        const start = self.state();
        if (tree.kind == '|') {
            var parts: std.ArrayList(Part) = .empty;
            for (tree.children) |child| try parts.append(self.gpa, try self.build(child));
            const end = self.state();
            for (parts.items) |part| {
                try self.add(start, 'e', part.start);
                try self.add(part.end, 'e', end);
            }
            return .{ .start = start, .end = end };
        }
        const part = try self.build(tree.children[0]);
        const end = self.state();
        try self.add(start, 'e', part.start);
        try self.add(part.end, 'e', end);
        if (tree.kind != '?') try self.add(part.end, 'e', part.start);
        if (tree.kind != '+') try self.add(start, 'e', end);
        return .{ .start = start, .end = end };
    }
};
fn regexAutomaton(gpa: Allocator, tree: *const Regex, alphabet: Text) Error!*Automaton {
    var builder: Thompson = .{ .gpa = gpa };
    const part = try builder.build(tree);
    const result = try Automaton.create(gpa, true, try series(gpa, "N", builder.next), alphabet, part.start);
    result.final[part.end] = true;
    for (builder.transitions.items) |t| try result.add(t.from, t.symbol, t.to);
    return result;
}
fn sortedAlphabet(gpa: Allocator, text: Text) Error!Text {
    const result = try gpa.dupe(u8, text);
    std.mem.sort(u8, result, {}, std.sort.asc(u8));
    return result;
}
fn stateIndex(gpa: Allocator, a: *const Automaton, name: Text) Error!usize {
    for (a.states, 0..) |state, i| if (eq(state, name)) return i;
    return bad(gpa, "unknown state {s}", .{name});
}
const Entry = struct { name: Text, automaton: *Automaton };
const countTable = [_]struct { name: Text, count: usize }{
    .{ .name = "ACCEPT", .count = 2 },  .{ .name = "CLOSURE", .count = 2 }, .{ .name = "TODFA", .count = 2 },     .{ .name = "EPSFREE", .count = 2 }, .{ .name = "MINIMIZE", .count = 2 },
    .{ .name = "EQUIV", .count = 2 },   .{ .name = "UNION", .count = 3 },   .{ .name = "INTERSECT", .count = 3 }, .{ .name = "DIFF", .count = 3 },    .{ .name = "COMPLEMENT", .count = 2 },
    .{ .name = "REVERSE", .count = 2 }, .{ .name = "CONCAT", .count = 3 },  .{ .name = "STAR", .count = 2 },      .{ .name = "ENUM", .count = 2 },    .{ .name = "COUNT", .count = 2 },
    .{ .name = "EMPTY", .count = 1 },   .{ .name = "FINITE", .count = 1 },  .{ .name = "INFO", .count = 1 },      .{ .name = "TABLE", .count = 1 },   .{ .name = "SHOW", .count = 1 },
    .{ .name = "SYNC", .count = 1 },    .{ .name = "LIST", .count = 0 },    .{ .name = "DELETE", .count = 1 },
};
const Toolkit = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Builder,
    entries: std.ArrayList(Entry) = .empty,
    fn lookup(self: *const Toolkit, name: Text) ?*Automaton {
        for (self.entries.items) |entry| if (eq(entry.name, name)) return entry.automaton;
        return null;
    }
    fn register(self: *Toolkit, name: Text, a: *Automaton, details: []const Text) Error!void {
        try self.entries.append(self.gpa, .{ .name = name, .automaton = a });
        try a.summary(self.out, name);
        for (details) |text| try self.out.line("{s}", .{text});
    }
    fn define(self: *Toolkit, command: Text, args: []const Text) Error!void {
        if (args.len < 5) return bad(self.scratch, "wrong number of arguments", .{});
        const name = args[0];
        if (self.lookup(name) != null) return bad(self.scratch, "{s} already exists", .{name});
        const states = try split(self.gpa, args[1], ',');
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        for (states) |state| {
            if (seen.contains(state)) return bad(self.scratch, "duplicate state {s}", .{state});
            try seen.put(self.scratch, state, {});
        }
        const a = try Automaton.create(self.gpa, eq(command, "NFA"), states, try sortedAlphabet(self.gpa, args[2]), 0);
        a.start = try stateIndex(self.scratch, a, args[3]);
        if (!eq(args[4], "-")) for (try split(self.scratch, args[4], ',')) |state| {
            const index = try stateIndex(self.scratch, a, state);
            if (a.final[index]) return bad(self.scratch, "duplicate state {s}", .{state});
            a.final[index] = true;
        };
        const TransitionPair = struct { state: usize, symbol: u8 };
        var triples: std.StringHashMapUnmanaged(void) = .empty;
        var pairs: std.AutoHashMapUnmanaged(TransitionPair, void) = .empty;
        for (args[5..]) |word| {
            const parts = try split(self.scratch, word, ':');
            const p = try stateIndex(self.scratch, a, parts[0]);
            const c = parts[1][0];
            if (c == 'e') {
                if (!a.nfa) return bad(self.scratch, "epsilon transition in DFA", .{});
            } else if (std.mem.findScalar(u8, a.alphabet, c) == null) return bad(self.scratch, "unknown symbol {c}", .{c});
            const q = try stateIndex(self.scratch, a, parts[2]);
            if (triples.contains(word)) return bad(self.scratch, "duplicate transition {s}", .{word});
            try triples.put(self.scratch, word, {});
            const key: TransitionPair = .{ .state = p, .symbol = c };
            if (!a.nfa and pairs.contains(key)) return bad(self.scratch, "conflicting transition {s}", .{word});
            try pairs.put(self.scratch, key, {});
            try a.add(p, c, q);
        }
        if (!a.nfa) for (states, 0..) |state, p| for (a.alphabet) |c| {
            if ((try a.destinations(self.scratch, p, c)).len == 0) return bad(self.scratch, "missing transition {s}:{c}", .{ state, c });
        };
        try self.register(name, a, &.{});
    }
    fn executeLine(self: *Toolkit, words: []const Text) Error!void {
        const command = words[0];
        const args = words[1..];
        if (eq(command, "DFA") or eq(command, "NFA")) return self.define(command, args);
        if (eq(command, "REGEX")) {
            if (args.len != 3) return bad(self.scratch, "wrong number of arguments", .{});
            if (self.lookup(args[0]) != null) return bad(self.scratch, "{s} already exists", .{args[0]});
            const alphabet = try sortedAlphabet(self.gpa, args[1]);
            for (args[2]) |c| if (symbolCharacter(c) and c != 'e' and std.mem.findScalar(u8, alphabet, c) == null) return bad(self.scratch, "unknown symbol {c}", .{c});
            var parser: RegexParser = .{ .gpa = self.scratch, .source = args[2] };
            const tree = try parser.alternation();
            if (parser.position != parser.source.len) return parser.invalid();
            try self.register(args[0], try regexAutomaton(self.gpa, tree, alphabet), &.{});
            return;
        }
        var expected: ?usize = null;
        for (countTable) |item| if (eq(item.name, command)) {
            expected = item.count;
            break;
        };
        if (expected == null) return bad(self.scratch, "unknown command {s}", .{command});
        if (args.len != expected.?) return bad(self.scratch, "wrong number of arguments", .{});
        if (eq(command, "LIST")) {
            if (self.entries.items.len == 0) try self.out.line("(none)", .{});
            for (self.entries.items) |entry| try entry.automaton.summary(self.out, entry.name);
            return;
        }
        const references: usize = if (includes(command, &.{ "EQUIV", "UNION", "INTERSECT", "DIFF", "CONCAT" })) 2 else 1;
        var autos: [2]*Automaton = undefined;
        for (args[0..references], 0..) |name, i| autos[i] = self.lookup(name) orelse return bad(self.scratch, "unknown automaton {s}", .{name});
        const creates = includes(command, &.{ "TODFA", "EPSFREE", "MINIMIZE", "UNION", "INTERSECT", "DIFF", "COMPLEMENT", "REVERSE", "CONCAT", "STAR" });
        if (creates and self.lookup(args[args.len - 1]) != null) return bad(self.scratch, "{s} already exists", .{args[args.len - 1]});
        if (includes(command, &.{ "MINIMIZE", "UNION", "INTERSECT", "DIFF", "COMPLEMENT", "SYNC" })) for (autos[0..references], args[0..references]) |a, name| if (a.nfa) return bad(self.scratch, "{s} is not a DFA", .{name});
        if (references == 2 and !eq(autos[0].alphabet, autos[1].alphabet)) return bad(self.scratch, "alphabets differ", .{});
        const a = autos[0];
        if (eq(command, "DELETE")) {
            for (self.entries.items, 0..) |entry, i| if (eq(entry.name, args[0])) {
                _ = self.entries.orderedRemove(i);
                break;
            };
            try self.out.line("deleted {s}", .{args[0]});
            return;
        }
        if (eq(command, "ACCEPT")) {
            const word = if (eq(args[1], "e")) "" else args[1];
            for (word) |c| if (std.mem.findScalar(u8, a.alphabet, c) == null) return bad(self.scratch, "unknown symbol {c}", .{c});
            var states = try a.closure(self.scratch, &.{a.start});
            var path: Builder = .{ .gpa = self.scratch };
            try path.add(if (a.nfa) try a.setText(self.scratch, states) else a.states[states[0]]);
            for (word) |c| {
                states = try a.step(self.scratch, states, c);
                try path.print(" -{c}-> {s}", .{ c, if (a.nfa) try a.setText(self.scratch, states) else a.states[states[0]] });
            }
            try self.out.line("{s} {s}", .{ if (a.accepts(states)) "ACCEPT" else "REJECT", path.bytes.items });
            return;
        }
        if (eq(command, "CLOSURE")) {
            var states: std.ArrayList(usize) = .empty;
            for (try split(self.scratch, args[1], ',')) |name| try states.append(self.scratch, try stateIndex(self.scratch, a, name));
            try self.out.line("{s}", .{try a.setText(self.scratch, try a.closure(self.scratch, states.items))});
            return;
        }
        if (eq(command, "TODFA")) {
            const result = try determinize(self.gpa, a);
            var details: std.ArrayList(Text) = .empty;
            for (result.sets, 0..) |set, i| try details.append(self.scratch, try std.fmt.allocPrint(self.scratch, "  D{d} = {s}", .{ i, try a.setText(self.scratch, set) }));
            try self.register(args[1], result.automaton, details.items);
            return;
        }
        if (eq(command, "EPSFREE")) {
            const result = try Automaton.create(self.gpa, true, a.states, a.alphabet, a.start);
            for (a.states, 0..) |_, state| {
                const closed = try a.closure(self.scratch, &.{state});
                result.final[state] = a.accepts(closed);
                for (a.alphabet) |c| for (try a.step(self.scratch, closed, c)) |next| try result.add(state, c, next);
            }
            try self.register(args[1], result, &.{});
            return;
        }
        if (eq(command, "MINIMIZE")) {
            const result = try minimize(self.gpa, a);
            try self.register(args[1], result.automaton, result.details);
            return;
        }
        if (includes(command, &.{ "UNION", "INTERSECT", "DIFF" })) {
            const result = try product(self.gpa, a, autos[1], command);
            try self.register(args[2], result.automaton, result.details);
            return;
        }
        if (eq(command, "EQUIV")) {
            const x = (try determinize(self.scratch, a)).automaton;
            const z = (try determinize(self.scratch, autos[1])).automaton;
            if (try equivalent(self.scratch, x, z)) |difference| {
                try self.out.line("NOT EQUIVALENT: {s} is accepted only by {s}", .{ emptyWord(difference.word), if (difference.left) args[0] else args[1] });
            } else try self.out.line("EQUIVALENT", .{});
            return;
        }
        if (eq(command, "COMPLEMENT")) {
            const result = try Automaton.create(self.gpa, false, a.states, a.alphabet, a.start);
            for (a.final, result.final) |original, *accepting| accepting.* = !original;
            for (a.transitions.items) |t| try result.add(t.from, t.symbol, t.to);
            try self.register(args[1], result, &.{});
            return;
        }
        if (includes(command, &.{ "REVERSE", "CONCAT", "STAR" })) {
            const concat = eq(command, "CONCAT");
            const total = if (concat) a.states.len + autos[1].states.len else a.states.len + 1;
            const result = try Automaton.create(self.gpa, true, try series(self.gpa, "N", total), a.alphabet, if (concat) a.start else 0);
            if (eq(command, "REVERSE")) {
                for (a.transitions.items) |t| try result.add(t.to + 1, t.symbol, t.from + 1);
                for (a.final, 0..) |accepting, state| if (accepting) try result.add(0, 'e', state + 1);
                result.final[a.start + 1] = true;
            } else if (eq(command, "STAR")) {
                for (a.transitions.items) |t| try result.add(t.from + 1, t.symbol, t.to + 1);
                result.final[0] = true;
                try result.add(0, 'e', a.start + 1);
                for (a.final, 0..) |accepting, state| if (accepting) {
                    result.final[state + 1] = true;
                    try result.add(state + 1, 'e', a.start + 1);
                };
            } else {
                for (a.transitions.items) |t| try result.add(t.from, t.symbol, t.to);
                const b = autos[1];
                const offset = a.states.len;
                for (b.transitions.items) |t| try result.add(t.from + offset, t.symbol, t.to + offset);
                for (a.final, 0..) |accepting, state| if (accepting) try result.add(state, 'e', b.start + offset);
                for (b.final, 0..) |accepting, state| result.final[state + offset] = accepting;
            }
            try self.register(args[args.len - 1], result, &.{});
            return;
        }
        if (eq(command, "SYNC")) {
            if (try synchronize(self.scratch, a)) |result| {
                try self.out.line("SYNCHRONIZING {s} -> {s}", .{ emptyWord(result.word), a.states[result.state] });
            } else try self.out.line("NOT SYNCHRONIZING", .{});
            return;
        }
        if (eq(command, "COUNT")) {
            const n = std.fmt.parseInt(usize, args[1], 10) catch unreachable;
            const d = (try determinize(self.scratch, a)).automaton;
            try self.out.line("{d}", .{try countLength(self.scratch, d, n)});
            return;
        }
        if (eq(command, "ENUM")) {
            const k = std.fmt.parseInt(usize, args[1], 10) catch unreachable;
            const d = (try determinize(self.scratch, a)).automaton;
            const Item = struct { state: usize, word: Text };
            var queue: std.ArrayList(Item) = .empty;
            try queue.append(self.scratch, .{ .state = d.start, .word = "" });
            var total: usize = 0;
            var accepted: std.ArrayList(Text) = .empty;
            var i: usize = 0;
            while (i < queue.items.len) : (i += 1) {
                const item = queue.items[i];
                if (d.final[item.state]) {
                    total += 1;
                    if (accepted.items.len < 50) try accepted.append(self.scratch, emptyWord(item.word));
                }
                if (item.word.len < k) for (d.alphabet) |c| try queue.append(self.scratch, .{ .state = d.delta(item.state, c), .word = try std.fmt.allocPrint(self.scratch, "{s}{c}", .{ item.word, c }) });
            }
            try self.out.print("{d}", .{total});
            for (accepted.items) |word| try self.out.print(" {s}", .{word});
            if (total > 50) try self.out.add(" ...");
            try self.out.add("\n");
            return;
        }
        if (eq(command, "EMPTY")) {
            const d = (try determinize(self.scratch, a)).automaton;
            if (try witness(self.scratch, d)) |word| {
                try self.out.line("NOT EMPTY {s}", .{emptyWord(word)});
            } else try self.out.line("EMPTY", .{});
            return;
        }
        if (eq(command, "FINITE")) {
            const d = (try determinize(self.scratch, a)).automaton;
            const result = try language(self.scratch, d);
            if (eq(result.classification, "infinite")) {
                try self.out.line("INFINITE", .{});
            } else try self.out.line("FINITE {d}", .{try finiteCount(self.scratch, d, result.live)});
            return;
        }
        if (eq(command, "INFO")) {
            var epsilon: usize = 0;
            var deterministic = true;
            var complete = true;
            for (a.transitions.items) |t| if (t.symbol == 'e') {
                epsilon += 1;
            };
            if (epsilon > 0) deterministic = false;
            for (a.states, 0..) |_, state| for (a.alphabet) |c| {
                const count = (try a.destinations(self.scratch, state, c)).len;
                if (count > 1) deterministic = false;
                if (count == 0) complete = false;
            };
            const d = (try determinize(self.scratch, a)).automaton;
            const result = try language(self.scratch, d);
            const minimal = (try minimize(self.scratch, d)).automaton;
            try a.summary(self.out, args[0]);
            try self.out.line("  epsilon transitions: {d}", .{epsilon});
            try self.out.line("  reachable: {s}", .{try a.listText(self.scratch, try orderedSet(self.scratch, try graphReach(self.scratch, a, &.{a.start}, false)))});
            try self.out.line("  live: {s}", .{try a.listText(self.scratch, try orderedSet(self.scratch, try graphReach(self.scratch, a, try orderedSet(self.scratch, a.final), true)))});
            try self.out.line("  deterministic: {s}", .{yes(deterministic)});
            try self.out.line("  complete: {s}", .{yes(complete)});
            try self.out.line("  language: {s}", .{result.classification});
            try self.out.line("  minimal DFA states: {d}", .{minimal.states.len});
            return;
        }
        if (eq(command, "SHOW")) {
            var parts: Builder = .{ .gpa = self.scratch };
            try parts.print("{s} {s} ", .{ if (a.nfa) "NFA" else "DFA", args[0] });
            for (a.states, 0..) |name, i| {
                if (i > 0) try parts.add(",");
                try parts.add(name);
            }
            try parts.print(" {s} {s} ", .{ a.alphabet, a.states[a.start] });
            const finals = try orderedSet(self.scratch, a.final);
            if (finals.len == 0) {
                try parts.add("-");
            } else for (finals, 0..) |state, i| {
                if (i > 0) try parts.add(",");
                try parts.add(a.states[state]);
            }
            const symbols = try std.fmt.allocPrint(self.scratch, "{s}e", .{a.alphabet});
            for (a.states, 0..) |name, state| for (symbols) |c| for (try a.destinations(self.scratch, state, c)) |next| try parts.print(" {s}:{c}:{s}", .{ name, c, a.states[next] });
            try self.out.line("{s}", .{parts.bytes.items});
            return;
        }
        if (eq(command, "TABLE")) {
            var epsilon = false;
            if (a.nfa) for (a.transitions.items) |t| if (t.symbol == 'e') {
                epsilon = true;
                break;
            };
            const symbols = if (epsilon) try std.fmt.allocPrint(self.scratch, "{s}e", .{a.alphabet}) else a.alphabet;
            const columns = symbols.len + 1;
            var rows: std.ArrayList([]Text) = .empty;
            const header = try self.scratch.alloc(Text, columns);
            header[0] = "";
            for (symbols, 1..) |_, i| header[i] = symbols[i - 1 .. i];
            try rows.append(self.scratch, header);
            for (a.states, 0..) |name, state| {
                const row = try self.scratch.alloc(Text, columns);
                row[0] = try std.fmt.allocPrint(self.scratch, "{s}{s}{s}", .{ if (state == a.start) "->" else "  ", if (a.final[state]) "*" else " ", name });
                for (symbols, 1..) |c, i| {
                    const destinations = try a.destinations(self.scratch, state, c);
                    row[i] = if (!a.nfa) a.states[destinations[0]] else if (destinations.len == 0) "-" else try a.setText(self.scratch, destinations);
                }
                try rows.append(self.scratch, row);
            }
            const widths = try self.scratch.alloc(usize, columns);
            @memset(widths, 0);
            for (rows.items) |row| for (row, 0..) |cell, i| {
                widths[i] = @max(widths[i], cell.len);
            };
            for (rows.items) |row| {
                var text: Builder = .{ .gpa = self.scratch };
                for (row, 0..) |cell, i| {
                    if (i > 0) try text.add("  ");
                    try text.add(cell);
                    for (0..widths[i] - cell.len) |_| try text.add(" ");
                }
                try self.out.line("{s}", .{std.mem.trimEnd(u8, text.bytes.items, " ")});
            }
            return;
        }
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const count = try std.fmt.parseInt(usize, std.mem.trim(u8, lines.next().?, "\r"), 10);
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    var unused: Builder = .{ .gpa = gpa };
    var toolkit: Toolkit = .{ .gpa = gpa, .scratch = gpa, .out = &unused };
    for (0..count) |_| {
        const source = std.mem.trimEnd(u8, lines.next().?, "\r");
        if (source[0] == '#') continue;
        var commandArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer commandArena.deinit();
        const scratch = commandArena.allocator();
        var out: Builder = .{ .gpa = scratch };
        toolkit.scratch = scratch;
        toolkit.out = &out;
        toolkit.executeLine(try split(scratch, source, ' ')) catch |err| {
            if (err != error.Invalid) return err;
            out.bytes.clearRetainingCapacity();
            try out.line("error: {s}", .{failure});
        };
        try output.interface.writeAll(out.bytes.items);
    }
    try output.interface.flush();
}
