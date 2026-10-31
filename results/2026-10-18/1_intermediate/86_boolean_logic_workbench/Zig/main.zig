const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";
fn equalText(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn includes(text: Text, list: []const Text) bool {
    for (list) |item| if (equalText(text, item)) return true;
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
fn splitWords(gpa: Allocator, text: Text) Error![]const Text {
    var list: std.ArrayList(Text) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, text, ' ');
    while (iterator.next()) |word| try list.append(gpa, word);
    return list.items;
}
const Node = struct { kind: Text, left: ?*Node = null, right: ?*Node = null };
fn makeNode(gpa: Allocator, kind: Text, left: ?*Node, right: ?*Node) Error!*Node {
    const result = try gpa.create(Node);
    result.* = .{ .kind = kind, .left = left, .right = right };
    return result;
}
fn leaf(gpa: Allocator, kind: Text) Error!*Node {
    return makeNode(gpa, kind, null, null);
}
fn negation(gpa: Allocator, child: *Node) Error!*Node {
    return makeNode(gpa, "~", child, null);
}
fn isVariable(text: Text) bool {
    return text.len == 1 and text[0] >= 'A' and text[0] <= 'Z';
}
fn validName(text: Text) bool {
    if (text.len == 0 or text.len > 8 or text[0] < 'a' or text[0] > 'z') return false;
    for (text) |c| if (!(c >= 'a' and c <= 'z' or c >= '0' and c <= '9')) return false;
    return true;
}
fn priority(kind: Text) usize {
    for ([_]Text{ "<->", "->", "|", "^", "&" }, 1..) |operator, i| if (equalText(operator, kind)) return i;
    return 0;
}
fn notationInto(node: *const Node, out: *Builder) Error!void {
    if (node.left == null) {
        try out.add(node.kind);
        return;
    }
    if (equalText(node.kind, "~")) {
        try out.add("~");
        const parentheses = priority(node.left.?.kind) > 0;
        if (parentheses) try out.add("(");
        try notationInto(node.left.?, out);
        if (parentheses) try out.add(")");
        return;
    }
    const p = priority(node.kind);
    const left = node.left.?;
    const right = node.right.?;
    const lp = priority(left.kind) > 0 and (priority(left.kind) < p or equalText(node.kind, "->") and equalText(left.kind, "->"));
    const rp = priority(right.kind) > 0 and (priority(right.kind) < p or equalText(node.kind, right.kind) and !equalText(node.kind, "->"));
    if (lp) try out.add("(");
    try notationInto(left, out);
    if (lp) try out.add(")");
    try out.print(" {s} ", .{node.kind});
    if (rp) try out.add("(");
    try notationInto(right, out);
    if (rp) try out.add(")");
}
fn notation(gpa: Allocator, node: *const Node) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    try notationInto(node, &out);
    return out.bytes.items;
}
fn sameTree(a: *const Node, b: *const Node) bool {
    return a == b or equalText(a.kind, b.kind) and (a.left == null or sameTree(a.left.?, b.left.?) and (a.right == null or sameTree(a.right.?, b.right.?)));
}
const Token = struct { text: Text, position: usize };
fn lexical(gpa: Allocator, source: Text, start: usize) Error![]const Token {
    var result: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < source.len) {
        if (source[i] == ' ') {
            i += 1;
            continue;
        }
        const begin = i;
        if (std.mem.startsWith(u8, source[i..], "<->")) {
            i += 3;
        } else if (std.mem.startsWith(u8, source[i..], "->")) {
            i += 2;
        } else if (source[i] >= 'a' and source[i] <= 'z') {
            while (i < source.len and (source[i] >= 'a' and source[i] <= 'z' or std.ascii.isDigit(source[i]))) i += 1;
        } else if (std.mem.findScalar(u8, "ABCDEFGHIJKLMNOPQRSTUVWXYZ01~&^|()", source[i]) != null) {
            i += 1;
        } else return bad(gpa, "invalid character '{c}' at {d}", .{ source[i], start + i });
        try result.append(gpa, .{ .text = source[begin..i], .position = start + begin });
    }
    return result.items;
}
const Names = std.StringHashMapUnmanaged(*Node);
const Parser = struct {
    gpa: Allocator,
    names: Names,
    tokens: []const Token,
    position: usize = 0,
    end: usize,
    fn unexpected(self: *Parser) Error {
        return if (self.position == self.tokens.len) bad(self.gpa, "unexpected end of formula at {d}", .{self.end}) else bad(self.gpa, "unexpected '{s}' at {d}", .{ self.tokens[self.position].text, self.tokens[self.position].position });
    }
    fn readUnary(self: *Parser) Error!*Node {
        if (self.position == self.tokens.len) return self.unexpected();
        const token = self.tokens[self.position];
        if (equalText(token.text, "~")) {
            self.position += 1;
            return negation(self.gpa, try self.readUnary());
        }
        if (equalText(token.text, "(")) {
            self.position += 1;
            const result = try self.expression(1);
            if (self.position == self.tokens.len or !equalText(self.tokens[self.position].text, ")")) return self.unexpected();
            self.position += 1;
            return result;
        }
        if (isVariable(token.text) or includes(token.text, &.{ "0", "1" })) {
            self.position += 1;
            return leaf(self.gpa, token.text);
        }
        if (token.text[0] >= 'a' and token.text[0] <= 'z') {
            const result = self.names.get(token.text) orelse return bad(self.gpa, "undefined name '{s}' at {d}", .{ token.text, token.position });
            self.position += 1;
            return result;
        }
        return self.unexpected();
    }
    fn expression(self: *Parser, minimum: usize) Error!*Node {
        var result = try self.readUnary();
        while (self.position < self.tokens.len) {
            const operator = self.tokens[self.position].text;
            const p = priority(operator);
            if (p < minimum) break;
            self.position += 1;
            result = try makeNode(self.gpa, operator, result, try self.expression(if (equalText(operator, "->")) p else p + 1));
        }
        return result;
    }
};
fn parse(gpa: Allocator, source: Text, start: usize, names: Names) Error!*Node {
    var parser: Parser = .{ .gpa = gpa, .names = names, .tokens = try lexical(gpa, source, start), .end = start + source.len };
    const result = try parser.expression(1);
    if (parser.position != parser.tokens.len) return parser.unexpected();
    return result;
}
fn collectVariables(node: *const Node, seen: *[26]bool) void {
    if (isVariable(node.kind)) seen[node.kind[0] - 'A'] = true;
    if (node.left) |child| collectVariables(child, seen);
    if (node.right) |child| collectVariables(child, seen);
}
fn variableList(gpa: Allocator, first: *const Node, second: ?*const Node) Error![]const Text {
    var seen: [26]bool = @splat(false);
    collectVariables(first, &seen);
    if (second) |node| collectVariables(node, &seen);
    var names: std.ArrayList(Text) = .empty;
    for (seen, 0..) |present, i| if (present) try names.append(gpa, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i .. i + 1]);
    return names.items;
}
fn treeSize(node: *const Node) usize {
    if (node.left == null) return 1;
    return 1 + treeSize(node.left.?) + (if (node.right) |child| treeSize(child) else 0);
}
fn treeDepth(node: *const Node) usize {
    if (node.left == null) return 1;
    return 1 + @max(treeDepth(node.left.?), if (node.right) |child| treeDepth(child) else 0);
}
fn truth(node: *const Node, assignment: *const [26]u8) u8 {
    if (isVariable(node.kind)) return assignment[node.kind[0] - 'A'];
    if (equalText(node.kind, "0")) return 0;
    if (equalText(node.kind, "1")) return 1;
    const a = truth(node.left.?, assignment);
    if (equalText(node.kind, "~")) return 1 - a;
    const b = truth(node.right.?, assignment);
    if (equalText(node.kind, "&")) return a & b;
    if (equalText(node.kind, "|")) return a | b;
    if (equalText(node.kind, "^")) return a ^ b;
    if (equalText(node.kind, "->")) return (1 - a) | b;
    return 1 - (a ^ b);
}
fn power2(n: usize) usize {
    return @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(n));
}
fn bitAt(row: usize, bit: usize) u8 {
    return @intCast((row >> @as(std.math.Log2Int(usize), @intCast(bit))) & 1);
}
fn truthTable(gpa: Allocator, node: *const Node, names: []const Text) Error![]u8 {
    const result = try gpa.alloc(u8, power2(names.len));
    for (result, 0..) |*value, row| {
        var assignment: [26]u8 = @splat(0);
        for (names, 0..) |name, i| assignment[name[0] - 'A'] = bitAt(row, names.len - 1 - i);
        value.* = truth(node, &assignment);
    }
    return result;
}
fn assignmentText(gpa: Allocator, names: []const Text, row: usize) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    try out.add("{");
    for (names, 0..) |name, i| {
        if (i > 0) try out.add(" ");
        try out.print("{s}={d}", .{ name, bitAt(row, names.len - 1 - i) });
    }
    try out.add("}");
    return out.bytes.items;
}
fn bitPattern(gpa: Allocator, row: usize, n: usize) Error!Text {
    const result = try gpa.alloc(u8, n);
    for (result, 0..) |*c, i| c.* = '0' + bitAt(row, n - 1 - i);
    return result;
}
fn literalCount(pattern: Text) usize {
    var result: usize = 0;
    for (pattern) |c| if (c != '-') {
        result += 1;
    };
    return result;
}
fn patternRank(c: u8) u8 {
    return if (c == '1') 0 else if (c == '0') 1 else 2;
}
fn patternLess(_: void, a: Text, b: Text) bool {
    for (a, b) |x, y| if (patternRank(x) != patternRank(y)) return patternRank(x) < patternRank(y);
    return false;
}
fn sortPatterns(patterns: []Text) void {
    std.mem.sort(Text, patterns, {}, patternLess);
}
fn flipped(gpa: Allocator, pattern: Text) Error!Text {
    const result = try gpa.dupe(u8, pattern);
    for (result) |*c| {
        if (c.* == '1') {
            c.* = '0';
        } else if (c.* == '0') c.* = '1';
    }
    return result;
}
fn termText(gpa: Allocator, pattern: Text, names: []const Text, clause: bool) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    var first = true;
    for (pattern, names) |c, name| {
        if (c == '-') continue;
        if (!first) try out.add(if (clause) " | " else " & ");
        first = false;
        if (c == '0') try out.add("~");
        try out.add(name);
    }
    if (first) try out.add(if (clause) "0" else "1");
    return out.bytes.items;
}
fn formText(gpa: Allocator, patterns: []const Text, names: []const Text, clausesMode: bool) Error!Text {
    if (patterns.len == 0) return if (clausesMode) "1" else "0";
    var out: Builder = .{ .gpa = gpa };
    for (patterns, 0..) |pattern, i| {
        if (i > 0) try out.add(if (clausesMode) " & " else " | ");
        const parentheses = clausesMode and patterns.len >= 2 and literalCount(pattern) >= 2;
        if (parentheses) try out.add("(");
        try out.add(try termText(gpa, pattern, names, clausesMode));
        if (parentheses) try out.add(")");
    }
    return out.bytes.items;
}
fn reduceNegation(gpa: Allocator, node: *Node) Error!*Node {
    if (equalText(node.kind, "0")) return leaf(gpa, "1");
    if (equalText(node.kind, "1")) return leaf(gpa, "0");
    if (equalText(node.kind, "~")) return node.left.?;
    return negation(gpa, node);
}
fn simplifyBinary(gpa: Allocator, operator: Text, a: *Node, b: *Node) Error!*Node {
    const same = sameTree(a, b);
    const complement = equalText(a.kind, "~") and sameTree(a.left.?, b) or equalText(b.kind, "~") and sameTree(b.left.?, a);
    if (equalText(operator, "&")) {
        if (equalText(a.kind, "0") or equalText(b.kind, "0")) return leaf(gpa, "0");
        if (equalText(a.kind, "1")) return b;
        if (equalText(b.kind, "1") or same) return a;
        if (complement) return leaf(gpa, "0");
    } else if (equalText(operator, "|")) {
        if (equalText(a.kind, "1") or equalText(b.kind, "1")) return leaf(gpa, "1");
        if (equalText(a.kind, "0")) return b;
        if (equalText(b.kind, "0") or same) return a;
        if (complement) return leaf(gpa, "1");
    } else if (equalText(operator, "^")) {
        if (equalText(a.kind, "0")) return b;
        if (equalText(b.kind, "0")) return a;
        if (equalText(a.kind, "1")) return reduceNegation(gpa, b);
        if (equalText(b.kind, "1")) return reduceNegation(gpa, a);
        if (same) return leaf(gpa, "0");
        if (complement) return leaf(gpa, "1");
    } else if (equalText(operator, "->")) {
        if (equalText(a.kind, "0") or equalText(b.kind, "1")) return leaf(gpa, "1");
        if (equalText(a.kind, "1")) return b;
        if (equalText(b.kind, "0")) return reduceNegation(gpa, a);
        if (same) return leaf(gpa, "1");
        if (complement) return b;
    } else {
        if (equalText(a.kind, "1")) return b;
        if (equalText(b.kind, "1")) return a;
        if (equalText(a.kind, "0")) return reduceNegation(gpa, b);
        if (equalText(b.kind, "0")) return reduceNegation(gpa, a);
        if (same) return leaf(gpa, "1");
        if (complement) return leaf(gpa, "0");
    }
    return makeNode(gpa, operator, a, b);
}
fn simplify(gpa: Allocator, node: *Node, assignments: *const [26]?Text) Error!*Node {
    if (node.left == null) {
        if (isVariable(node.kind)) {
            if (assignments[node.kind[0] - 'A']) |value| return leaf(gpa, value);
        }
        return node;
    }
    const a = try simplify(gpa, node.left.?, assignments);
    if (equalText(node.kind, "~")) return reduceNegation(gpa, a);
    return simplifyBinary(gpa, node.kind, a, try simplify(gpa, node.right.?, assignments));
}
const SignedNode = struct { node: *Node, positive: bool };
const NnfMemo = std.AutoHashMapUnmanaged(SignedNode, *Node);
fn nnf(gpa: Allocator, node: *Node, positive: bool, memo: *NnfMemo) Error!*Node {
    const key: SignedNode = .{ .node = node, .positive = positive };
    if (memo.get(key)) |result| return result;
    var result: *Node = undefined;
    if (includes(node.kind, &.{ "0", "1" })) {
        result = if (positive) node else try reduceNegation(gpa, node);
    } else if (equalText(node.kind, "~")) {
        result = try nnf(gpa, node.left.?, !positive, memo);
    } else if (includes(node.kind, &.{ "&", "|" })) {
        const operator = if (positive) node.kind else if (equalText(node.kind, "&")) "|" else "&";
        result = try makeNode(gpa, operator, try nnf(gpa, node.left.?, positive, memo), try nnf(gpa, node.right.?, positive, memo));
    } else if (equalText(node.kind, "->")) {
        result = try makeNode(gpa, if (positive) "|" else "&", try nnf(gpa, node.left.?, !positive, memo), try nnf(gpa, node.right.?, positive, memo));
    } else if (includes(node.kind, &.{ "^", "<->" })) {
        const sameSign = if (equalText(node.kind, "^")) !positive else positive;
        const a = try makeNode(gpa, "&", try nnf(gpa, node.left.?, true, memo), try nnf(gpa, node.right.?, sameSign, memo));
        const b = try makeNode(gpa, "&", try nnf(gpa, node.left.?, false, memo), try nnf(gpa, node.right.?, !sameSign, memo));
        result = try makeNode(gpa, "|", a, b);
    } else {
        result = if (positive) node else try negation(gpa, node);
    }
    try memo.put(gpa, key, result);
    return result;
}
fn dual(gpa: Allocator, node: *Node) Error!*Node {
    if (isVariable(node.kind)) return node;
    if (includes(node.kind, &.{ "0", "1" })) return reduceNegation(gpa, node);
    if (equalText(node.kind, "~")) return negation(gpa, try dual(gpa, node.left.?));
    const a = try dual(gpa, node.left.?);
    const b = try dual(gpa, node.right.?);
    if (equalText(node.kind, "->")) return makeNode(gpa, "&", try negation(gpa, a), b);
    const operator: Text = if (equalText(node.kind, "&")) "|" else if (equalText(node.kind, "|")) "&" else if (equalText(node.kind, "^")) "<->" else "^";
    return makeNode(gpa, operator, a, b);
}
fn covers(pattern: Text, row: usize) bool {
    for (pattern, 0..) |c, i| if (c != '-' and c != '0' + bitAt(row, pattern.len - 1 - i)) return false;
    return true;
}
fn patternSubset(a: Text, b: Text) bool {
    for (a, b) |x, y| if (x != '-' and x != y) return false;
    return true;
}
fn tidy(gpa: Allocator, patterns: []const Text) Error![]Text {
    var unique: std.ArrayList(Text) = .empty;
    for (patterns) |pattern| if (!includes(pattern, unique.items)) try unique.append(gpa, pattern);
    var result: std.ArrayList(Text) = .empty;
    for (unique.items, 0..) |pattern, i| {
        var redundant = false;
        for (unique.items, 0..) |other, j| if (i != j and patternSubset(other, pattern)) {
            redundant = true;
            break;
        };
        if (!redundant) try result.append(gpa, pattern);
    }
    return result.items;
}
fn mergeClauses(gpa: Allocator, a: Text, b: Text) Error!?Text {
    const result = try gpa.dupe(u8, a);
    for (result, b) |*x, y| {
        if (y == '-') continue;
        if (x.* != '-' and x.* != y) return null;
        x.* = y;
    }
    return result;
}
const ClauseMemo = std.AutoHashMapUnmanaged(*Node, []const Text);
fn clauseSet(gpa: Allocator, node: *Node, names: []const Text, memo: *ClauseMemo) Error![]const Text {
    if (memo.get(node)) |result| return result;
    var patterns: std.ArrayList(Text) = .empty;
    if (equalText(node.kind, "1")) {} else if (equalText(node.kind, "0")) {
        const empty = try gpa.alloc(u8, names.len);
        @memset(empty, '-');
        try patterns.append(gpa, empty);
    } else if (includes(node.kind, &.{ "&", "|" })) {
        const a = try clauseSet(gpa, node.left.?, names, memo);
        const b = try clauseSet(gpa, node.right.?, names, memo);
        if (equalText(node.kind, "&")) {
            try patterns.appendSlice(gpa, a);
            try patterns.appendSlice(gpa, b);
        } else for (a) |x| for (b) |y| {
            if (try mergeClauses(gpa, x, y)) |merged| try patterns.append(gpa, merged);
        };
    } else {
        const negative = equalText(node.kind, "~");
        const name = if (negative) node.left.?.kind else node.kind;
        const pattern = try gpa.alloc(u8, names.len);
        for (names, pattern) |variable, *c| c.* = if (equalText(name, variable)) (if (negative) @as(u8, '0') else '1') else '-';
        try patterns.append(gpa, pattern);
    }
    const result = try tidy(gpa, patterns.items);
    try memo.put(gpa, node, result);
    return result;
}
fn patternsTerms(gpa: Allocator, patterns: []const Text, names: []const Text) Error!Text {
    if (patterns.len == 0) return "none";
    var out: Builder = .{ .gpa = gpa };
    for (patterns, 0..) |pattern, i| {
        if (i > 0) try out.add(", ");
        try out.add(try termText(gpa, pattern, names, false));
    }
    return out.bytes.items;
}
fn minimize(gpa: Allocator, values: []const u8, dc: ?[]const u8, names: []const Text, pos: bool, out: *Builder) Error!void {
    var on: std.ArrayList(usize) = .empty;
    var stage: std.ArrayList(Text) = .empty;
    for (values, 0..) |value, row| {
        const dontCare = if (dc) |table| table[row] == 1 else false;
        if (value == 1 and !dontCare) try on.append(gpa, row);
        if (value == 1 or dontCare) try stage.append(gpa, try bitPattern(gpa, row, names.len));
    }
    var primes: std.ArrayList(Text) = .empty;
    var level: usize = 0;
    while (true) : (level += 1) {
        var used: std.StringHashMapUnmanaged(void) = .empty;
        var next: std.ArrayList(Text) = .empty;
        for (stage.items, 0..) |a, i| for (stage.items[i + 1 ..]) |b| {
            var differing: ?usize = null;
            var valid = true;
            for (a, b, 0..) |x, y, j| if (x != y) {
                if (x == '-' or y == '-' or differing != null) {
                    valid = false;
                    break;
                }
                differing = j;
            };
            if (valid and differing != null) {
                const pattern = try gpa.dupe(u8, a);
                pattern[differing.?] = '-';
                try used.put(gpa, a, {});
                try used.put(gpa, b, {});
                if (!includes(pattern, next.items)) try next.append(gpa, pattern);
            }
        };
        var count: usize = 0;
        for (stage.items) |pattern| if (!used.contains(pattern)) {
            try primes.append(gpa, pattern);
            count += 1;
        };
        if (!pos) try out.line("stage {d}: implicants {d} primes {d}", .{ level, stage.items.len, count });
        if (next.items.len == 0) break;
        stage = next;
    }
    var target: std.ArrayList(Text) = .empty;
    for (primes.items) |pattern| for (on.items) |row| {
        if (covers(pattern, row)) {
            try target.append(gpa, pattern);
            break;
        }
    };
    sortPatterns(target.items);
    var essential: std.ArrayList(Text) = .empty;
    for (on.items) |row| {
        var options: usize = 0;
        var selected: Text = "";
        for (target.items) |pattern| if (covers(pattern, row)) {
            options += 1;
            selected = pattern;
        };
        if (options == 1 and !includes(selected, essential.items)) try essential.append(gpa, selected);
    }
    sortPatterns(essential.items);
    var optional: std.ArrayList(Text) = .empty;
    for (target.items) |pattern| if (!includes(pattern, essential.items)) try optional.append(gpa, pattern);
    var best: []Text = &.{};
    var bestCount: usize = std.math.maxInt(usize);
    var bestLiterals: usize = std.math.maxInt(usize);
    for (0..power2(optional.items.len)) |mask| {
        var chosen: std.ArrayList(Text) = .empty;
        try chosen.appendSlice(gpa, essential.items);
        for (optional.items, 0..) |pattern, i| if (bitAt(mask, i) != 0) try chosen.append(gpa, pattern);
        var valid = true;
        for (on.items) |row| {
            var found = false;
            for (chosen.items) |pattern| if (covers(pattern, row)) {
                found = true;
                break;
            };
            if (!found) {
                valid = false;
                break;
            }
        }
        if (!valid) continue;
        var literals: usize = 0;
        for (chosen.items) |pattern| literals += literalCount(pattern);
        const displayed = try gpa.alloc(Text, chosen.items.len);
        for (displayed, chosen.items) |*pattern, original| pattern.* = if (pos) try flipped(gpa, original) else original;
        sortPatterns(displayed);
        var better = chosen.items.len < bestCount or chosen.items.len == bestCount and literals < bestLiterals;
        if (chosen.items.len == bestCount and literals == bestLiterals) for (displayed, best) |a, b| {
            if (!equalText(a, b)) {
                better = patternLess({}, a, b);
                break;
            }
        };
        if (better) {
            best = displayed;
            bestCount = chosen.items.len;
            bestLiterals = literals;
        }
    }
    if (pos) {
        try out.line("minimal: {s}", .{try formText(gpa, best, names, true)});
        try out.line("clauses {d} literals {d}", .{ bestCount, bestLiterals });
    } else {
        try out.line("primes: {s}", .{try patternsTerms(gpa, target.items, names)});
        try out.line("essential: {s}", .{try patternsTerms(gpa, essential.items, names)});
        try out.line("minimal: {s}", .{try formText(gpa, best, names, false)});
        try out.line("terms {d} literals {d}", .{ bestCount, bestLiterals });
    }
}
fn coefficients(gpa: Allocator, values: []const u8, n: usize) Error![]u8 {
    const result = try gpa.dupe(u8, values);
    for (0..n) |bit| for (0..result.len) |row| {
        if (bitAt(row, bit) != 0) result[row] ^= result[row ^ power2(bit)];
    };
    return result;
}
fn bitCount(value: usize) usize {
    return @popCount(value);
}
fn yes(value: bool) Text {
    return if (value) "yes" else "no";
}
const Decision = struct { variable: usize, low: usize, high: usize };
const Bdd = struct {
    gpa: Allocator,
    names: []const Text,
    nodes: std.ArrayList(Decision) = .empty,
    unique: std.AutoHashMapUnmanaged(Decision, usize) = .empty,
    fn build(self: *Bdd, level: usize, rows: []const u8) Error!usize {
        if (level == self.names.len) return rows[0];
        const low = try self.build(level + 1, rows[0 .. rows.len / 2]);
        const high = try self.build(level + 1, rows[rows.len / 2 ..]);
        if (low == high) return low;
        const key: Decision = .{ .variable = level, .low = low, .high = high };
        if (self.unique.get(key)) |index| return index;
        const index = self.nodes.items.len + 2;
        try self.nodes.append(self.gpa, key);
        try self.unique.put(self.gpa, key, index);
        return index;
    }
};
const commands = [_]Text{ "DEF", "DEFSUM", "DEL", "LIST", "PRINT", "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "NNF", "DUAL", "ANF", "SIMPLIFY", "RESTRICT", "COFACTOR", "MINIMIZE", "MINDC", "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "BDD", "CLAUSES", "DP" };
const truthCommands = [_]Text{ "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "ANF", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "KMAP", "BDD", "MINIMIZE", "MINDC", "MINPOS" };
const Workbench = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Builder,
    names: Names = .empty,
    fn define(self: *Workbench, name: Text, formula: *Node) Error!void {
        const existed = self.names.contains(name);
        try self.names.put(self.gpa, name, formula);
        try self.out.line("{s} {s} = {s}", .{ if (existed) "redefined" else "defined", name, try notation(self.scratch, formula) });
    }
    fn executeLine(self: *Workbench, source: Text) Error!void {
        const separator = std.mem.findScalar(u8, source, ' ');
        const command = if (separator) |index| source[0..index] else source;
        const argument = if (separator) |index| source[index + 1 ..] else "";
        if (!includes(command, &commands)) return bad(self.scratch, "unknown command {s}", .{command});
        if (equalText(command, "LIST")) {
            if (separator != null) return bad(self.scratch, "unexpected argument", .{});
            var names: std.ArrayList(Text) = .empty;
            var iterator = self.names.keyIterator();
            while (iterator.next()) |name| try names.append(self.scratch, name.*);
            std.mem.sort(Text, names.items, {}, struct {
                fn less(_: void, a: Text, b: Text) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.less);
            try self.out.line("names: {d}", .{names.items.len});
            for (names.items) |name| try self.out.line("{s} = {s}", .{ name, try notation(self.scratch, self.names.get(name).?) });
            return;
        }
        if (separator == null) return bad(self.scratch, "missing argument", .{});
        if (equalText(command, "DEF")) {
            const space = std.mem.findScalar(u8, argument, ' ') orelse return bad(self.scratch, "missing argument", .{});
            const name = argument[0..space];
            if (!validName(name)) return bad(self.scratch, "invalid name '{s}'", .{name});
            const formula = try parse(self.gpa, argument[space + 1 ..], name.len + 6, self.names);
            try self.define(name, formula);
            return;
        }
        if (equalText(command, "DEL")) {
            if (!validName(argument)) return bad(self.scratch, "invalid name '{s}'", .{argument});
            if (!self.names.remove(argument)) return bad(self.scratch, "undefined name '{s}'", .{argument});
            try self.out.line("deleted {s}", .{argument});
            return;
        }
        if (equalText(command, "DEFSUM")) {
            const semicolon = std.mem.findScalar(u8, argument, ';') orelse return bad(self.scratch, "missing ';'", .{});
            const words = try splitWords(self.scratch, argument[0..semicolon]);
            if (words.len == 0) return bad(self.scratch, "missing argument", .{});
            const name = words[0];
            if (!validName(name)) return bad(self.scratch, "invalid name '{s}'", .{name});
            const names = words[1..];
            if (names.len == 0) return bad(self.scratch, "bad variable list", .{});
            for (names, 0..) |variable, i| if (!isVariable(variable) or i > 0 and std.mem.order(u8, variable, names[i - 1]) != .gt) return bad(self.scratch, "bad variable list", .{});
            if (names.len >= 9) return bad(self.scratch, "too many variables: {d}", .{names.len});
            var previous: ?usize = null;
            var formula: ?*Node = null;
            for (try splitWords(self.scratch, argument[semicolon + 1 ..])) |word| {
                var valid = word.len > 0 and (equalText(word, "0") or word[0] >= '1' and word[0] <= '9');
                for (word) |c| if (!std.ascii.isDigit(c)) {
                    valid = false;
                    break;
                };
                const row = if (valid) std.fmt.parseInt(usize, word, 10) catch unreachable else 0;
                if (!valid or row >= power2(names.len) or previous != null and row <= previous.?) return bad(self.scratch, "bad minterm '{s}'", .{word});
                previous = row;
                var product: ?*Node = null;
                for (names, 0..) |variable, i| {
                    var literal = try leaf(self.gpa, variable);
                    if (bitAt(row, names.len - 1 - i) == 0) literal = try negation(self.gpa, literal);
                    product = if (product) |old| try makeNode(self.gpa, "&", old, literal) else literal;
                }
                formula = if (formula) |old| try makeNode(self.gpa, "|", old, product.?) else product.?;
            }
            try self.define(name, formula orelse try leaf(self.gpa, "0"));
            return;
        }
        var front = argument;
        var back: Text = "";
        const start = command.len + 2;
        var backStart: usize = 0;
        if (includes(command, &.{ "RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES" })) {
            const semicolon = std.mem.findScalar(u8, argument, ';') orelse return bad(self.scratch, "missing ';'", .{});
            front = argument[0..semicolon];
            back = argument[semicolon + 1 ..];
            backStart = start + semicolon + 1;
        }
        const formula = try parse(self.scratch, front, start, self.names);
        const second: ?*Node = if (includes(command, &.{ "MINDC", "EQUIV", "IMPLIES" })) try parse(self.scratch, back, backStart, self.names) else null;
        if (equalText(command, "RESTRICT")) {
            const words = try splitWords(self.scratch, back);
            if (words.len == 0) return bad(self.scratch, "missing assignment", .{});
            var assignments: [26]?Text = @splat(null);
            for (words) |word| {
                if (word.len != 3 or !isVariable(word[0..1]) or word[1] != '=' or word[2] != '0' and word[2] != '1') return bad(self.scratch, "bad assignment '{s}'", .{word});
                const index = word[0] - 'A';
                if (assignments[index] != null) return bad(self.scratch, "duplicate variable {c}", .{word[0]});
                assignments[index] = word[2..3];
            }
            try self.out.line("restricted: {s}", .{try notation(self.scratch, try simplify(self.scratch, formula, &assignments))});
            return;
        }
        if (equalText(command, "COFACTOR")) {
            const words = try splitWords(self.scratch, back);
            if (words.len != 1 or !isVariable(words[0])) return bad(self.scratch, "bad variable", .{});
            const name = words[0];
            var assignments: [26]?Text = @splat(null);
            assignments[name[0] - 'A'] = "1";
            const one = try simplify(self.scratch, formula, &assignments);
            assignments[name[0] - 'A'] = "0";
            const zero = try simplify(self.scratch, formula, &assignments);
            try self.out.line("cofactor {s}=1: {s}", .{ name, try notation(self.scratch, one) });
            try self.out.line("cofactor {s}=0: {s}", .{ name, try notation(self.scratch, zero) });
            try self.out.line("difference: {s}", .{try notation(self.scratch, try simplifyBinary(self.scratch, "^", one, zero))});
            return;
        }
        const names = try variableList(self.scratch, formula, second);
        if (includes(command, &truthCommands) and names.len >= 9) return bad(self.scratch, "too many variables: {d}", .{names.len});
        if (equalText(command, "PRINT")) {
            try self.out.line("formula: {s}", .{try notation(self.scratch, formula)});
            try self.out.add("variables:");
            if (names.len == 0) {
                try self.out.add(" none");
            } else for (names) |name| try self.out.print(" {s}", .{name});
            try self.out.line("\nsize {d} depth {d}", .{ treeSize(formula), treeDepth(formula) });
            return;
        }
        if (equalText(command, "SIMPLIFY")) {
            const assignments: [26]?Text = @splat(null);
            try self.out.line("simplified: {s}", .{try notation(self.scratch, try simplify(self.scratch, formula, &assignments))});
            return;
        }
        if (equalText(command, "NNF")) {
            var memo: NnfMemo = .empty;
            try self.out.line("nnf: {s}", .{try notation(self.scratch, try nnf(self.scratch, formula, true, &memo))});
            return;
        }
        if (equalText(command, "DUAL")) {
            try self.out.line("dual: {s}", .{try notation(self.scratch, try dual(self.scratch, formula))});
            return;
        }
        if (equalText(command, "CLAUSES") or equalText(command, "DP")) {
            var nnfMemo: NnfMemo = .empty;
            var memo: ClauseMemo = .empty;
            var set = try clauseSet(self.scratch, try nnf(self.scratch, formula, true, &nnfMemo), names, &memo);
            if (equalText(command, "CLAUSES")) {
                const ordered = try self.scratch.dupe(Text, set);
                sortPatterns(ordered);
                try self.out.line("clauses: {s}", .{try formText(self.scratch, ordered, names, true)});
                return;
            }
            const empty = try self.scratch.alloc(u8, names.len);
            @memset(empty, '-');
            try self.out.line("start: clauses {d}", .{set.len});
            for (names, 0..) |name, i| {
                if (set.len == 0 or includes(empty, set)) break;
                var p: std.ArrayList(Text) = .empty;
                var q: std.ArrayList(Text) = .empty;
                var rest: std.ArrayList(Text) = .empty;
                for (set) |pattern| {
                    if (pattern[i] == '1') {
                        try p.append(self.scratch, pattern);
                    } else if (pattern[i] == '0') {
                        try q.append(self.scratch, pattern);
                    } else try rest.append(self.scratch, pattern);
                }
                var resolvents: std.ArrayList(Text) = .empty;
                for (p.items) |a| for (q.items) |b| {
                    const x = try self.scratch.dupe(u8, a);
                    const y = try self.scratch.dupe(u8, b);
                    x[i] = '-';
                    y[i] = '-';
                    if (try mergeClauses(self.scratch, x, y)) |merged| if (!includes(merged, resolvents.items)) try resolvents.append(self.scratch, merged);
                };
                try rest.appendSlice(self.scratch, resolvents.items);
                set = try tidy(self.scratch, rest.items);
                try self.out.line("eliminate {s}: resolvents {d} clauses {d}", .{ name, resolvents.items.len, set.len });
            }
            try self.out.line("result: {s}", .{if (includes(empty, set)) "unsatisfiable" else "satisfiable"});
            return;
        }
        const values = try truthTable(self.scratch, formula, names);
        var models: std.ArrayList(usize) = .empty;
        var falseRows: std.ArrayList(usize) = .empty;
        for (values, 0..) |value, row| {
            if (value == 1) {
                try models.append(self.scratch, row);
            } else try falseRows.append(self.scratch, row);
        }
        if (equalText(command, "TABLE")) {
            for (names) |name| try self.out.print("{s} ", .{name});
            try self.out.line("| F", .{});
            for (values, 0..) |value, row| {
                for (0..names.len) |i| try self.out.print("{d} ", .{bitAt(row, names.len - 1 - i)});
                try self.out.line("| {d}", .{value});
            }
            return;
        }
        if (equalText(command, "MINTERMS") or equalText(command, "MAXTERMS")) {
            const rows = if (equalText(command, "MINTERMS")) models.items else falseRows.items;
            try self.out.add(if (equalText(command, "MINTERMS")) "minterms:" else "maxterms:");
            if (rows.len == 0) try self.out.add(" none");
            for (rows) |row| try self.out.print(" {d}", .{row});
            try self.out.add("\n");
            return;
        }
        if (equalText(command, "DNF") or equalText(command, "CNF")) {
            const cnf = equalText(command, "CNF");
            const rows = if (cnf) falseRows.items else models.items;
            var patterns: std.ArrayList(Text) = .empty;
            for (rows) |row| {
                const pattern = try bitPattern(self.scratch, row, names.len);
                try patterns.append(self.scratch, if (cnf) try flipped(self.scratch, pattern) else pattern);
            }
            try self.out.line("{s}: {s}", .{ if (cnf) "cnf" else "dnf", try formText(self.scratch, patterns.items, names, cnf) });
            return;
        }
        if (equalText(command, "ANF")) {
            var patterns: std.ArrayList(Text) = .empty;
            for (try coefficients(self.scratch, values, names.len), 0..) |coefficient, row| if (coefficient == 1) {
                const pattern = try self.scratch.dupe(u8, try bitPattern(self.scratch, row, names.len));
                for (pattern) |*c| if (c.* == '0') {
                    c.* = '-';
                };
                try patterns.append(self.scratch, pattern);
            };
            std.mem.sort(Text, patterns.items, {}, struct {
                fn less(_: void, a: Text, b: Text) bool {
                    return literalCount(a) < literalCount(b) or literalCount(a) == literalCount(b) and patternLess({}, a, b);
                }
            }.less);
            try self.out.add("anf: ");
            if (patterns.items.len == 0) try self.out.add("0");
            for (patterns.items, 0..) |pattern, i| {
                if (i > 0) try self.out.add(" ^ ");
                try self.out.add(try termText(self.scratch, pattern, names, false));
            }
            try self.out.add("\n");
            return;
        }
        if (equalText(command, "SAT")) {
            if (models.items.len == 0) {
                try self.out.line("unsatisfiable", .{});
            } else try self.out.line("satisfiable: {s}", .{try assignmentText(self.scratch, names, models.items[0])});
            return;
        }
        if (equalText(command, "TAUT")) {
            if (falseRows.items.len == 0) {
                try self.out.line("tautology", .{});
            } else try self.out.line("not a tautology: {s}", .{try assignmentText(self.scratch, names, falseRows.items[0])});
            return;
        }
        if (equalText(command, "COUNT")) {
            try self.out.line("models: {d} of {d}", .{ models.items.len, values.len });
            return;
        }
        if (equalText(command, "EQUIV") or equalText(command, "IMPLIES")) {
            const other = try truthTable(self.scratch, second.?, names);
            for (values, other, 0..) |a, b, row| {
                if (equalText(command, "EQUIV") and a != b) {
                    try self.out.line("not equivalent: {s} f={d} g={d}", .{ try assignmentText(self.scratch, names, row), a, b });
                    return;
                }
                if (equalText(command, "IMPLIES") and a == 1 and b == 0) {
                    try self.out.line("does not imply: {s}", .{try assignmentText(self.scratch, names, row)});
                    return;
                }
            }
            try self.out.line("{s}", .{if (equalText(command, "EQUIV")) "equivalent" else "implies"});
            return;
        }
        if (equalText(command, "MINIMIZE")) return minimize(self.scratch, values, null, names, false, self.out);
        if (equalText(command, "MINDC")) return minimize(self.scratch, values, try truthTable(self.scratch, second.?, names), names, false, self.out);
        if (equalText(command, "MINPOS")) {
            const inverted = try self.scratch.dupe(u8, values);
            for (inverted) |*value| value.* = 1 - value.*;
            return minimize(self.scratch, inverted, null, names, true, self.out);
        }
        if (equalText(command, "KMAP")) {
            const n = names.len;
            if (n < 2 or n > 4) return bad(self.scratch, "kmap needs 2 to 4 variables", .{});
            const p = n / 2;
            const q = n - p;
            for (names[0..p]) |name| try self.out.add(name);
            try self.out.add("\\");
            for (names[p..]) |name| try self.out.add(name);
            for (0..power2(q)) |i| try self.out.print(" {s}", .{try bitPattern(self.scratch, i ^ (i / 2), q)});
            try self.out.add("\n");
            for (0..power2(p)) |i| {
                const row = i ^ (i / 2);
                try self.out.add(try bitPattern(self.scratch, row, p));
                for (0..n + 1 - p) |_| try self.out.add(" ");
                for (0..power2(q)) |j| {
                    for (0..q) |_| try self.out.add(" ");
                    try self.out.print("{d}", .{values[row * power2(q) + (j ^ (j / 2))]});
                }
                try self.out.add("\n");
            }
            return;
        }
        if (equalText(command, "PROPS")) {
            var depends: std.ArrayList(Text) = .empty;
            var selfDual = true;
            var monotone = true;
            var linear = true;
            var symmetric = true;
            for (names, 0..) |name, i| {
                const bit = power2(names.len - 1 - i);
                for (values, 0..) |value, row| if (value != values[row ^ bit]) {
                    try depends.append(self.scratch, name);
                    break;
                };
            }
            var weights: [9]?u8 = @splat(null);
            for (values, 0..) |value, row| {
                if (value == values[values.len - 1 - row]) selfDual = false;
                for (0..names.len) |i| {
                    const bit = power2(i);
                    if (row & bit == 0 and value > values[row | bit]) monotone = false;
                }
                const weight = bitCount(row);
                if (weights[weight]) |previous| {
                    if (previous != value) symmetric = false;
                }
                weights[weight] = value;
            }
            for (try coefficients(self.scratch, values, names.len), 0..) |coefficient, row| if (coefficient == 1 and bitCount(row) > 1) {
                linear = false;
            };
            try self.out.add("depends:");
            if (depends.items.len == 0) try self.out.add(" none");
            for (depends.items) |name| try self.out.print(" {s}", .{name});
            try self.out.add("\n");
            try self.out.line("zero-preserving: {s}", .{yes(values[0] == 0)});
            try self.out.line("one-preserving: {s}", .{yes(values[values.len - 1] == 1)});
            try self.out.line("self-dual: {s}", .{yes(selfDual)});
            try self.out.line("monotone: {s}", .{yes(monotone)});
            try self.out.line("linear: {s}", .{yes(linear)});
            try self.out.line("symmetric: {s}", .{yes(symmetric)});
            return;
        }
        if (equalText(command, "BDD")) {
            var bdd: Bdd = .{ .gpa = self.scratch, .names = names };
            const root = try bdd.build(0, values);
            var paths: std.ArrayList(usize) = .empty;
            try paths.appendSlice(self.scratch, &.{ 0, 1 });
            try self.out.line("nodes: {d}", .{bdd.nodes.items.len});
            for (bdd.nodes.items, 0..) |node, i| {
                try self.out.line("{d} = ite({s}, {d}, {d})", .{ i + 2, names[node.variable], node.high, node.low });
                try paths.append(self.scratch, paths.items[node.low] + paths.items[node.high]);
            }
            try self.out.line("root: {d}", .{root});
            try self.out.line("paths: {d}", .{paths.items[root]});
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
    var workbench: Workbench = .{ .gpa = gpa, .scratch = gpa, .out = &unused };
    for (0..count) |_| {
        const source = std.mem.trimEnd(u8, lines.next().?, "\r");
        var commandArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer commandArena.deinit();
        const scratch = commandArena.allocator();
        var out: Builder = .{ .gpa = scratch };
        workbench.scratch = scratch;
        workbench.out = &out;
        workbench.executeLine(source) catch |err| {
            if (err != error.Invalid) return err;
            out.bytes.clearRetainingCapacity();
            try out.line("error: {s}", .{failure});
        };
        try output.interface.writeAll(out.bytes.items);
    }
    try output.interface.flush();
}
