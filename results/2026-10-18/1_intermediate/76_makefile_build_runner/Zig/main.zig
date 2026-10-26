const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{ Invalid, Abort };
var failure: Text = "";
var failureLocation: Text = "make";
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn trim(s: Text) Text {
    return std.mem.trim(u8, s, " ");
}
fn number(s: Text) usize {
    var result: usize = 0;
    for (s) |c| result = result * 10 + c - '0';
    return result;
}
fn numeric(s: Text) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, s: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, s);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, format, args));
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        try self.print(format ++ "\n", args);
    }
};
fn words(gpa: Allocator, s: Text) Allocator.Error![]Text {
    var list: std.ArrayList(Text) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, s, ' ');
    while (iterator.next()) |word| try list.append(gpa, word);
    return list.items;
}
fn unique(gpa: Allocator, list: []const Text) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (list) |item| if (!seen.contains(item)) {
        try seen.put(gpa, item, {});
        try result.append(gpa, item);
    };
    return result.items;
}
fn textLess(_: void, a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}
fn keys(gpa: Allocator, map: anytype) Allocator.Error![]Text {
    var list: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try list.append(gpa, key.*);
    std.mem.sort(Text, list.items, {}, textLess);
    return list.items;
}
fn join(gpa: Allocator, list: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (list, 0..) |item, i| {
        if (i > 0) try out.add(separator);
        try out.add(item);
    }
    return out.bytes.items;
}
fn lastScalar(s: Text, c: u8) ?usize {
    var i = s.len;
    while (i > 0) {
        i -= 1;
        if (s[i] == c) return i;
    }
    return null;
}
fn match(pattern: Text, word: Text) ?Text {
    const at = std.mem.findScalar(u8, pattern, '%') orelse return if (equal(pattern, word)) "" else null;
    const a = pattern[0..at];
    const b = pattern[at + 1 ..];
    if (word.len < a.len + b.len or !std.mem.startsWith(u8, word, a) or !std.mem.endsWith(u8, word, b)) return null;
    return word[a.len .. word.len - b.len];
}
fn substitute(gpa: Allocator, pattern: Text, stem: Text) Allocator.Error!Text {
    const at = std.mem.findScalar(u8, pattern, '%') orelse return pattern;
    return std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ pattern[0..at], stem, pattern[at + 1 ..] });
}
fn replacement(gpa: Allocator, word: Text, pattern: Text, value: Text) Allocator.Error!Text {
    const stem = match(pattern, word) orelse return word;
    return if (std.mem.findScalar(u8, pattern, '%') != null) try substitute(gpa, value, stem) else value;
}
fn wildcard(gpa: Allocator, pattern: Text, name: Text) Allocator.Error!bool {
    var previous = try gpa.alloc(bool, name.len + 1);
    var next = try gpa.alloc(bool, name.len + 1);
    @memset(previous, false);
    previous[0] = true;
    for (pattern) |c| {
        @memset(next, false);
        next[0] = c == '*' and previous[0];
        for (name, 0..) |n, i| {
            next[i + 1] = if (c == '*') previous[i + 1] or (n != '/' and next[i]) else previous[i] and (c == n or c == '?' and n != '/');
        }
        std.mem.swap([]bool, &previous, &next);
    }
    return previous[name.len];
}
const Function = enum { subst, patsubst, strip, findstring, filter, filter_out, sort, word, wordlist, words, firstword, lastword, dir, notdir, suffix, basename, addsuffix, addprefix, wildcard, foreach, conditional, call, value, info, warning, failure };
const FunctionInfo = struct { name: Text, kind: Function, minimum: usize, maximum: usize };
const functions = [_]FunctionInfo{
    .{ .name = "subst", .kind = .subst, .minimum = 3, .maximum = 3 },         .{ .name = "patsubst", .kind = .patsubst, .minimum = 3, .maximum = 3 },
    .{ .name = "strip", .kind = .strip, .minimum = 1, .maximum = 1 },         .{ .name = "findstring", .kind = .findstring, .minimum = 2, .maximum = 2 },
    .{ .name = "filter", .kind = .filter, .minimum = 2, .maximum = 2 },       .{ .name = "filter-out", .kind = .filter_out, .minimum = 2, .maximum = 2 },
    .{ .name = "sort", .kind = .sort, .minimum = 1, .maximum = 1 },           .{ .name = "word", .kind = .word, .minimum = 2, .maximum = 2 },
    .{ .name = "wordlist", .kind = .wordlist, .minimum = 3, .maximum = 3 },   .{ .name = "words", .kind = .words, .minimum = 1, .maximum = 1 },
    .{ .name = "firstword", .kind = .firstword, .minimum = 1, .maximum = 1 }, .{ .name = "lastword", .kind = .lastword, .minimum = 1, .maximum = 1 },
    .{ .name = "dir", .kind = .dir, .minimum = 1, .maximum = 1 },             .{ .name = "notdir", .kind = .notdir, .minimum = 1, .maximum = 1 },
    .{ .name = "suffix", .kind = .suffix, .minimum = 1, .maximum = 1 },       .{ .name = "basename", .kind = .basename, .minimum = 1, .maximum = 1 },
    .{ .name = "addsuffix", .kind = .addsuffix, .minimum = 2, .maximum = 2 }, .{ .name = "addprefix", .kind = .addprefix, .minimum = 2, .maximum = 2 },
    .{ .name = "wildcard", .kind = .wildcard, .minimum = 1, .maximum = 1 },   .{ .name = "foreach", .kind = .foreach, .minimum = 3, .maximum = 3 },
    .{ .name = "if", .kind = .conditional, .minimum = 2, .maximum = 3 },      .{ .name = "call", .kind = .call, .minimum = 1, .maximum = 0 },
    .{ .name = "value", .kind = .value, .minimum = 1, .maximum = 1 },         .{ .name = "info", .kind = .info, .minimum = 1, .maximum = 1 },
    .{ .name = "warning", .kind = .warning, .minimum = 1, .maximum = 1 },     .{ .name = "error", .kind = .failure, .minimum = 1, .maximum = 1 },
};
fn findFunction(name: Text) ?FunctionInfo {
    for (functions) |item| if (equal(name, item.name)) return item;
    return null;
}
const Variable = struct { simple: bool = false, value: Text };
const RecipeLine = struct { number: usize, text: Text };
const Recipe = std.ArrayList(RecipeLine);
const Rule = struct { target: Text, prerequisites: []const Text = &.{}, recipe: ?*Recipe = null, stem: Text = "" };
const Group = struct { targets: std.ArrayList(*Rule) = .empty, explicit: bool = true, recipe: ?*Recipe = null };
const Condition = struct { outer: bool, value: bool, otherwise: bool = false, number: usize };
const Scope = union(enum) { foreach: struct { name: Text, word: Text }, call: []const Text };
const Chosen = struct { prerequisites: []const Text = &.{}, recipe: ?*Recipe = null, stem: Text = "", source: bool = false, missing: bool = false };
const Simulator = struct {
    gpa: Allocator,
    out: *Builder,
    files: std.StringHashMapUnmanaged(usize) = .empty,
    clock: usize = 0,
    loaded: bool = false,
    variables: std.StringHashMapUnmanaged(Variable) = .empty,
    rules: std.StringHashMapUnmanaged(*Rule) = .empty,
    patterns: std.ArrayList(*Rule) = .empty,
    phony: std.StringHashMapUnmanaged(void) = .empty,
    goal: ?Text = null,
    location: Text = "make",
    scopes: std.ArrayList(Scope) = .empty,
    expanding: std.StringHashMapUnmanaged(void) = .empty,
    automatic: std.StringHashMapUnmanaged(Text) = .empty,
    fn fail(self: *Simulator, comptime format: Text, args: anytype) Error {
        failureLocation = self.location;
        failure = std.fmt.allocPrint(self.gpa, format, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn clear(self: *Simulator) void {
        self.loaded = false;
        self.variables = .empty;
        self.rules = .empty;
        self.patterns = .empty;
        self.phony = .empty;
        self.goal = null;
    }
    fn resetExpansion(self: *Simulator) void {
        self.location = "make";
        self.scopes = .empty;
        self.expanding = .empty;
        self.automatic = .empty;
    }
    fn glob(self: *Simulator, pattern: Text) Error![]Text {
        var list: std.ArrayList(Text) = .empty;
        for (try keys(self.gpa, self.files)) |name| if (try wildcard(self.gpa, pattern, name)) try list.append(self.gpa, name);
        return list.items;
    }
    fn reference(self: *Simulator, name: Text) Error!Text {
        var i = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            switch (self.scopes.items[i]) {
                .foreach => |scope| if (equal(scope.name, name)) return scope.word,
                .call => |values| if (numeric(name)) {
                    const n = number(name);
                    return if (n < values.len) values[n] else "";
                },
            }
        }
        if (self.automatic.get(name)) |value| return value;
        const v = self.variables.get(name) orelse return "";
        if (v.simple) return v.value;
        if (self.expanding.contains(name)) return self.fail("Recursive variable '{s}' references itself (eventually)", .{name});
        try self.expanding.put(self.gpa, name, {});
        defer _ = self.expanding.remove(name);
        return self.expand(v.value);
    }
    fn closing(self: *Simulator, s: Text, open: usize) Error!usize {
        const close: u8 = if (s[open] == '(') ')' else '}';
        var depth: isize = 0;
        for (open..s.len) |i| {
            if (s[i] == s[open]) {
                depth += 1;
            } else if (s[i] == close) {
                depth -= 1;
                if (depth == 0) return i;
            }
        }
        return self.fail("unterminated variable reference", .{});
    }
    fn outside(self: *Simulator, s: Text, wanted: u8) Error!?usize {
        var found: ?usize = null;
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            if (s[i] == '$') {
                if (i + 1 < s.len and (s[i + 1] == '(' or s[i + 1] == '{')) {
                    i = try self.closing(s, i + 1);
                } else if (i + 1 < s.len) {
                    i += 1;
                }
            } else if (s[i] == wanted and found == null) {
                found = i;
            }
        }
        return found;
    }
    fn expand(self: *Simulator, s: Text) Error!Text {
        var out: Builder = .{ .gpa = self.gpa };
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            if (s[i] != '$') {
                try out.bytes.append(self.gpa, s[i]);
                continue;
            }
            i += 1;
            if (i == s.len) break;
            if (s[i] == '$') {
                try out.add("$");
            } else if (s[i] == '(' or s[i] == '{') {
                const finish = try self.closing(s, i);
                const content = s[i + 1 .. finish];
                var called = false;
                if (std.mem.findScalar(u8, content, ' ')) |at| {
                    if (findFunction(content[0..at])) |function| {
                        try out.add(try self.invoke(function, std.mem.trimStart(u8, content[at + 1 ..], " "), s[i]));
                        called = true;
                    }
                }
                if (!called) {
                    const name = try self.expand(content);
                    var substituted = false;
                    if (std.mem.findScalar(u8, name, ':')) |colon| {
                        if (std.mem.findScalar(u8, name[colon + 1 ..], '=')) |offset| {
                            const eq = colon + 1 + offset;
                            var from = name[colon + 1 .. eq];
                            var to = name[eq + 1 ..];
                            if (std.mem.findScalar(u8, from, '%') == null) {
                                from = try std.fmt.allocPrint(self.gpa, "%{s}", .{from});
                                to = try std.fmt.allocPrint(self.gpa, "%{s}", .{to});
                            }
                            const list = try words(self.gpa, try self.reference(name[0..colon]));
                            for (list) |*word| word.* = try replacement(self.gpa, word.*, from, to);
                            try out.add(try join(self.gpa, list, " "));
                            substituted = true;
                        }
                    }
                    if (!substituted) try out.add(try self.reference(name));
                }
                i = finish;
            } else {
                try out.add(try self.reference(s[i .. i + 1]));
            }
        }
        return out.bytes.items;
    }
    fn invoke(self: *Simulator, function: FunctionInfo, text: Text, open: u8) Error!Text {
        var raw: std.ArrayList(Text) = .empty;
        var depth: isize = 0;
        var start: usize = 0;
        const close: u8 = if (open == '(') ')' else '}';
        for (text, 0..) |c, i| {
            if (c == open) {
                depth += 1;
            } else if (c == close) {
                depth -= 1;
            }
            if (c == ',' and depth == 0 and (function.maximum == 0 or raw.items.len + 1 < function.maximum)) {
                try raw.append(self.gpa, text[start..i]);
                start = i + 1;
            }
        }
        try raw.append(self.gpa, text[start..]);
        if (raw.items.len < function.minimum) return self.fail("insufficient number of arguments ({d}) to function '{s}'", .{ raw.items.len, function.name });
        const args = raw.items;
        const kind = function.kind;
        if (kind == .conditional) {
            if (trim(try self.expand(args[0])).len > 0) return self.expand(args[1]);
            return if (args.len > 2) try self.expand(args[2]) else "";
        }
        if (kind == .foreach) {
            const name = trim(try self.expand(args[0]));
            const list = try words(self.gpa, try self.expand(args[1]));
            var result: std.ArrayList(Text) = .empty;
            for (list) |word| {
                try self.scopes.append(self.gpa, .{ .foreach = .{ .name = name, .word = word } });
                const value = self.expand(args[2]) catch |err| {
                    _ = self.scopes.pop();
                    return err;
                };
                _ = self.scopes.pop();
                try result.append(self.gpa, value);
            }
            return join(self.gpa, result.items, " ");
        }
        for (args) |*arg| {
            arg.* = try self.expand(arg.*);
            if (kind != .subst and kind != .call) arg.* = trim(arg.*);
        }
        if (kind == .call) {
            args[0] = trim(args[0]);
            const v = self.variables.get(args[0]) orelse return "";
            if (v.simple) return v.value;
            try self.scopes.append(self.gpa, .{ .call = args });
            defer _ = self.scopes.pop();
            return self.expand(v.value);
        }
        var result: std.ArrayList(Text) = .empty;
        switch (kind) {
            .subst => {
                if (args[0].len == 0) return args[2];
                var out: Builder = .{ .gpa = self.gpa };
                var cursor: usize = 0;
                while (std.mem.find(u8, args[2][cursor..], args[0])) |offset| {
                    const at = cursor + offset;
                    try out.add(args[2][cursor..at]);
                    try out.add(args[1]);
                    cursor = at + args[0].len;
                }
                try out.add(args[2][cursor..]);
                return out.bytes.items;
            },
            .patsubst => {
                const list = try words(self.gpa, args[2]);
                for (list) |*word| word.* = try replacement(self.gpa, word.*, args[0], args[1]);
                return join(self.gpa, list, " ");
            },
            .strip => return join(self.gpa, try words(self.gpa, args[0]), " "),
            .findstring => return if (std.mem.find(u8, args[1], args[0]) != null) args[0] else "",
            .filter, .filter_out => {
                const patterns = try words(self.gpa, args[0]);
                for (try words(self.gpa, args[1])) |word| {
                    var matched = false;
                    for (patterns) |pattern| if (match(pattern, word) != null) {
                        matched = true;
                        break;
                    };
                    if (matched == (kind == .filter)) try result.append(self.gpa, word);
                }
            },
            .sort => {
                const list = try unique(self.gpa, try words(self.gpa, args[0]));
                std.mem.sort(Text, list, {}, textLess);
                return join(self.gpa, list, " ");
            },
            .word => {
                if (!numeric(args[0])) return self.fail("non-numeric first argument to 'word' function: '{s}'", .{args[0]});
                const n = number(args[0]);
                if (n == 0) return self.fail("first argument to 'word' function must be greater than 0", .{});
                const list = try words(self.gpa, args[1]);
                return if (n <= list.len) list[n - 1] else "";
            },
            .wordlist => {
                if (!numeric(args[0])) return self.fail("non-numeric first argument to 'wordlist' function: '{s}'", .{args[0]});
                if (!numeric(args[1])) return self.fail("non-numeric second argument to 'wordlist' function: '{s}'", .{args[1]});
                const a = number(args[0]);
                if (a == 0) return self.fail("invalid first argument to 'wordlist' function: '{s}'", .{args[0]});
                const list = try words(self.gpa, args[2]);
                const b = @min(number(args[1]), list.len);
                return if (a > b) "" else try join(self.gpa, list[a - 1 .. b], " ");
            },
            .words => return std.fmt.allocPrint(self.gpa, "{d}", .{(try words(self.gpa, args[0])).len}),
            .firstword, .lastword => {
                const list = try words(self.gpa, args[0]);
                return if (list.len == 0) "" else list[if (kind == .firstword) 0 else list.len - 1];
            },
            .dir, .notdir, .suffix, .basename => {
                for (try words(self.gpa, args[0])) |word| {
                    const slash = lastScalar(word, '/');
                    const dot = lastScalar(word, '.');
                    const extension = dot != null and (slash == null or dot.? > slash.?);
                    switch (kind) {
                        .dir => try result.append(self.gpa, if (slash) |at| word[0 .. at + 1] else "./"),
                        .notdir => try result.append(self.gpa, word[if (slash) |at| at + 1 else 0..]),
                        .suffix => if (extension) {
                            try result.append(self.gpa, word[dot.?..]);
                        },
                        .basename => try result.append(self.gpa, if (extension) word[0..dot.?] else word),
                        else => unreachable,
                    }
                }
            },
            .addprefix, .addsuffix => for (try words(self.gpa, args[1])) |word| {
                try result.append(self.gpa, try std.fmt.allocPrint(self.gpa, "{s}{s}", .{ if (kind == .addprefix) args[0] else word, if (kind == .addprefix) word else args[0] }));
            },
            .wildcard => for (try words(self.gpa, args[0])) |pattern| {
                try result.appendSlice(self.gpa, try self.glob(pattern));
            },
            .value => return if (self.variables.get(args[0])) |v| v.value else "",
            .info => try self.out.line("{s}", .{args[0]}),
            .warning => try self.out.line("{s}: {s}", .{ self.location, args[0] }),
            .failure => return self.fail("{s}", .{args[0]}),
            else => unreachable,
        }
        return join(self.gpa, result.items, " ");
    }
    fn register(self: *Simulator, target: Text, prerequisites: []const Text) Error!*Rule {
        const r = self.rules.get(target) orelse blk: {
            const created = try self.gpa.create(Rule);
            created.* = .{ .target = target };
            try self.rules.put(self.gpa, target, created);
            break :blk created;
        };
        var combined: std.ArrayList(Text) = .empty;
        try combined.appendSlice(self.gpa, r.prerequisites);
        try combined.appendSlice(self.gpa, prerequisites);
        r.prerequisites = try unique(self.gpa, combined.items);
        if (self.goal == null and !std.mem.startsWith(u8, target, ".")) self.goal = target;
        return r;
    }
    fn addRecipe(self: *Simulator, group: *Group, line: RecipeLine) Error!void {
        if (group.targets.items.len == 0) return;
        if (group.recipe == null) {
            const created = try self.gpa.create(Recipe);
            created.* = .empty;
            group.recipe = created;
            for (group.targets.items) |r| {
                if (group.explicit) {
                    if (r.recipe) |old| {
                        try self.out.line("Makefile:{d}: warning: overriding recipe for target '{s}'", .{ line.number, r.target });
                        try self.out.line("Makefile:{d}: warning: ignoring old recipe for target '{s}'", .{ old.items[0].number, r.target });
                    }
                }
                r.recipe = created;
            }
        }
        try group.recipe.?.append(self.gpa, line);
    }
    fn active(stack: []const Condition) bool {
        return stack.len == 0 or stack[stack.len - 1].outer and stack[stack.len - 1].value;
    }
    fn load(self: *Simulator, body: []const Text) Error!void {
        self.clear();
        self.parseBody(body) catch |err| {
            if (err != error.Invalid) return err;
            try self.out.line("{s}: *** {s}.  Stop.", .{ failureLocation, failure });
            self.clear();
            return;
        };
        self.loaded = true;
        var count: usize = 0;
        for (self.patterns.items) |r| {
            if (r.recipe != null) count += 1;
        }
        try self.out.line("Makefile loaded: lines={d} variables={d} targets={d} patterns={d} goal={s}", .{ body.len, self.variables.count(), self.rules.count(), count, self.goal orelse "(none)" });
    }
    fn parseBody(self: *Simulator, body: []const Text) Error!void {
        var current: ?*Group = null;
        var stack: std.ArrayList(Condition) = .empty;
        var index: usize = 0;
        while (index < body.len) : (index += 1) {
            const lineNumber = index + 1;
            var text = body[index];
            self.location = try std.fmt.allocPrint(self.gpa, "Makefile:{d}", .{lineNumber});
            if (std.mem.startsWith(u8, text, ">")) {
                if (!active(stack.items)) continue;
                if (current == null) return self.fail("recipe commences before first target", .{});
                try self.addRecipe(current.?, .{ .number = lineNumber, .text = std.mem.trimStart(u8, text[1..], " ") });
                continue;
            }
            while (std.mem.endsWith(u8, text, "\\") and index + 1 < body.len) {
                index += 1;
                text = try std.fmt.allocPrint(self.gpa, "{s} {s}", .{ std.mem.trimEnd(u8, text[0 .. text.len - 1], " "), std.mem.trimStart(u8, body[index], " ") });
            }
            if (std.mem.findScalar(u8, text, '#')) |at| text = text[0..at];
            text = trim(text);
            const space = std.mem.findScalar(u8, text, ' ') orelse text.len;
            const first = text[0..space];
            const rest = if (space < text.len) trim(text[space + 1 ..]) else "";
            if (equal(first, "else")) {
                if (stack.items.len == 0) return self.fail("extraneous 'else'", .{});
                const top = &stack.items[stack.items.len - 1];
                if (top.otherwise) return self.fail("only one 'else' per conditional", .{});
                top.value = !top.value;
                top.otherwise = true;
                continue;
            }
            if (equal(first, "endif")) {
                if (stack.items.len == 0) return self.fail("extraneous 'endif'", .{});
                _ = stack.pop();
                continue;
            }
            if (equal(first, "ifdef") or equal(first, "ifndef") or equal(first, "ifeq") or equal(first, "ifneq")) {
                const outer = active(stack.items);
                var value = false;
                if (outer) {
                    if (equal(first, "ifdef") or equal(first, "ifndef")) {
                        const v = self.variables.get(trim(try self.expand(rest)));
                        value = v != null and v.?.value.len > 0;
                        if (equal(first, "ifndef")) value = !value;
                    } else {
                        if (rest.len < 2 or rest[0] != '(' or rest[rest.len - 1] != ')') return self.fail("invalid syntax in conditional", .{});
                        const inside = rest[1 .. rest.len - 1];
                        var depth: isize = 0;
                        var comma: ?usize = null;
                        for (inside, 0..) |c, i| {
                            if (c == '(') {
                                depth += 1;
                            } else if (c == ')') {
                                depth -= 1;
                            } else if (c == ',' and depth == 0) {
                                comma = i;
                                break;
                            }
                        }
                        const at = comma orelse return self.fail("invalid syntax in conditional", .{});
                        const left = trim(try self.expand(inside[0..at]));
                        const right = trim(try self.expand(inside[at + 1 ..]));
                        value = equal(left, right);
                        if (equal(first, "ifneq")) value = !value;
                    }
                }
                try stack.append(self.gpa, .{ .outer = outer, .value = value, .number = lineNumber });
                continue;
            }
            if (text.len == 0 or !active(stack.items)) continue;
            const eq = try self.outside(text, '=');
            const colon = try self.outside(text, ':');
            if (eq != null and (colon == null or colon.? + 1 >= eq.?)) {
                const at = eq.?;
                var begin = at;
                var op: u8 = '=';
                if (at > 0 and std.mem.findScalar(u8, ":+?", text[at - 1]) != null) {
                    begin = at - 1;
                    op = text[at - 1];
                }
                const name = trim(text[0..begin]);
                var value = trim(text[at + 1 ..]);
                if (name.len == 0) return self.fail("empty variable name", .{});
                const old = self.variables.get(name);
                switch (op) {
                    '=' => try self.variables.put(self.gpa, name, .{ .value = value }),
                    ':' => try self.variables.put(self.gpa, name, .{ .simple = true, .value = try self.expand(value) }),
                    '?' => if (old == null) {
                        try self.variables.put(self.gpa, name, .{ .value = value });
                    },
                    '+' => {
                        if (old) |v| {
                            if (v.simple) value = try self.expand(value);
                            if (v.value.len > 0) value = try std.fmt.allocPrint(self.gpa, "{s} {s}", .{ v.value, value });
                            try self.variables.put(self.gpa, name, .{ .simple = v.simple, .value = value });
                        } else {
                            try self.variables.put(self.gpa, name, .{ .value = value });
                        }
                    },
                    else => unreachable,
                }
                current = null;
                continue;
            }
            const at = colon orelse {
                if (trim(try self.expand(text)).len > 0) return self.fail("missing separator", .{});
                continue;
            };
            const targets = try unique(self.gpa, try words(self.gpa, try self.expand(text[0..at])));
            var remainder = text[at + 1 ..];
            var inlineRecipe: ?Text = null;
            var targetPattern: ?Text = null;
            if (try self.outside(remainder, ';')) |semi| {
                inlineRecipe = std.mem.trimStart(u8, remainder[semi + 1 ..], " ");
                remainder = remainder[0..semi];
            }
            if (try self.outside(remainder, ':')) |splitAt| {
                targetPattern = trim(try self.expand(remainder[0..splitAt]));
                remainder = remainder[splitAt + 1 ..];
            }
            const prerequisites = try words(self.gpa, try self.expand(remainder));
            const group = try self.gpa.create(Group);
            group.* = .{};
            current = group;
            if (targets.len == 1 and equal(targets[0], ".PHONY")) {
                for (prerequisites) |p| try self.phony.put(self.gpa, p, {});
            } else if (targetPattern) |pattern| {
                if (std.mem.findScalar(u8, pattern, '%') == null) return self.fail("target pattern contains no '%'", .{});
                for (targets) |target| {
                    const stem = match(pattern, target);
                    if (stem == null or stem.?.len == 0) {
                        try self.out.line("Makefile:{d}: target '{s}' doesn't match the target pattern", .{ lineNumber, target });
                        continue;
                    }
                    const list = try self.gpa.alloc(Text, prerequisites.len);
                    for (prerequisites, 0..) |p, i| list[i] = try substitute(self.gpa, p, stem.?);
                    const r = try self.register(target, list);
                    r.stem = stem.?;
                    try group.targets.append(self.gpa, r);
                }
            } else {
                var count: usize = 0;
                for (targets) |target| {
                    if (std.mem.findScalar(u8, target, '%') != null) count += 1;
                }
                if (count > 0 and count != targets.len) return self.fail("mixed implicit and normal rules", .{});
                group.explicit = count == 0;
                for (targets) |target| {
                    const r = if (count > 0) blk: {
                        const created = try self.gpa.create(Rule);
                        created.* = .{ .target = target, .prerequisites = prerequisites };
                        try self.patterns.append(self.gpa, created);
                        break :blk created;
                    } else try self.register(target, prerequisites);
                    try group.targets.append(self.gpa, r);
                }
            }
            if (inlineRecipe) |command| try self.addRecipe(group, .{ .number = lineNumber, .text = command });
        }
        if (stack.items.len > 0) {
            self.location = try std.fmt.allocPrint(self.gpa, "Makefile:{d}", .{stack.items[stack.items.len - 1].number});
            return self.fail("missing 'endif'", .{});
        }
    }
    fn determine(self: *Simulator, target: Text) Error!Chosen {
        const explicit = self.rules.get(target);
        if (explicit) |r| {
            if (r.recipe != null) return .{ .prerequisites = r.prerequisites, .recipe = r.recipe, .stem = r.stem };
        }
        if (!self.phony.contains(target)) {
            var best: ?*Rule = null;
            var bestStem: Text = "";
            for (self.patterns.items) |r| {
                if (r.recipe == null) continue;
                const stem = match(r.target, target) orelse continue;
                if (stem.len == 0) continue;
                var usable = true;
                for (r.prerequisites) |p| {
                    const name = try substitute(self.gpa, p, stem);
                    if (!self.files.contains(name) and !self.rules.contains(name)) {
                        usable = false;
                        break;
                    }
                }
                if (usable and (best == null or stem.len < bestStem.len)) {
                    best = r;
                    bestStem = stem;
                }
            }
            if (best) |r| {
                var list: std.ArrayList(Text) = .empty;
                for (r.prerequisites) |p| try list.append(self.gpa, try substitute(self.gpa, p, bestStem));
                if (explicit) |e| try list.appendSlice(self.gpa, e.prerequisites);
                return .{ .prerequisites = try unique(self.gpa, list.items), .recipe = r.recipe, .stem = bestStem };
            }
        }
        if (explicit) |r| return .{ .prerequisites = r.prerequisites, .stem = r.stem };
        if (self.phony.contains(target)) return .{};
        return if (self.files.contains(target)) .{ .source = true } else .{ .missing = true };
    }
    fn touch(self: *Simulator, name: Text) Error!void {
        self.clock += 1;
        try self.files.put(self.gpa, name, self.clock);
    }
    fn execute(self: *Simulator, text: Text) Error!usize {
        const list = try words(self.gpa, text);
        if (equal(list[0], "echo")) {
            try self.out.line("{s}", .{try join(self.gpa, list[1..], " ")});
        } else if (equal(list[0], "touch")) {
            for (list[1..]) |name| try self.touch(name);
        } else if (equal(list[0], "rm")) {
            const forced = list.len > 1 and equal(list[1], "-f");
            var code: usize = 0;
            for (list[if (forced) 2 else 1..]) |pattern| {
                var names = try self.glob(pattern);
                if (names.len == 0) {
                    names = try self.gpa.alloc(Text, 1);
                    names[0] = pattern;
                }
                for (names) |name| if (!self.files.remove(name) and !forced) {
                    try self.out.line("rm: cannot remove '{s}': No such file or directory", .{name});
                    code = 1;
                };
            }
            return code;
        } else if (equal(list[0], "false")) {
            return 1;
        } else if (equal(list[0], "exit") and list.len > 1) {
            return number(list[1]);
        }
        return 0;
    }
    fn display(self: *Simulator, r: *Rule) Error!void {
        try self.out.print("{s}:", .{r.target});
        for (r.prerequisites) |p| try self.out.print(" {s}", .{p});
        try self.out.add("\n");
        if (r.recipe) |recipe| for (recipe.items) |line| {
            try self.out.line(">{s}", .{line.text});
        };
    }
    fn make(self: *Simulator, args: []const Text) Error!void {
        var options: [256]bool = @splat(false);
        var goals: std.ArrayList(Text) = .empty;
        for (args) |arg| {
            if (arg.len > 0 and arg[0] == '-') {
                for (arg[1..]) |c| {
                    if (std.mem.findScalar(u8, "nBkis", c) == null) {
                        try self.out.line("make: invalid option -- '{c}'", .{c});
                        return;
                    }
                    options[c] = true;
                }
            } else try goals.append(self.gpa, arg);
        }
        if (goals.items.len == 0) {
            if (!self.loaded) {
                try self.out.line("make: *** No targets specified and no makefile found.  Stop.", .{});
                return;
            }
            const goal = self.goal orelse {
                try self.out.line("make: *** No targets.  Stop.", .{});
                return;
            };
            try goals.append(self.gpa, goal);
        }
        var saved: std.StringHashMapUnmanaged(usize) = .empty;
        const clock = self.clock;
        if (options['n']) {
            var iterator = self.files.iterator();
            while (iterator.next()) |entry| try saved.put(self.gpa, entry.key_ptr.*, entry.value_ptr.*);
        }
        defer {
            if (options['n']) {
                self.files = saved;
                self.clock = clock;
            }
        }
        var build: Build = .{ .sim = self, .options = options };
        for (goals.items) |goal| {
            const before = build.runs;
            const result = build.target(goal, null) catch |err| {
                if (err == error.Abort) return;
                return err;
            };
            if (result == 0 and build.runs == before) {
                if (self.phony.contains(goal) or build.chosen.get(goal).?.recipe == null) {
                    try self.out.line("make: Nothing to be done for '{s}'.", .{goal});
                } else {
                    try self.out.line("make: '{s}' is up to date.", .{goal});
                }
            } else if (result == 2) {
                try self.out.line("make: Target '{s}' not remade because of errors.", .{goal});
            }
        }
    }
    fn command(self: *Simulator, line: Text, body: []const Text) Error!void {
        self.resetExpansion();
        try self.out.line("$ {s}", .{line});
        const at = std.mem.findScalar(u8, line, ' ') orelse line.len;
        const name = line[0..at];
        const text = if (at < line.len) line[at + 1 ..] else "";
        if (equal(name, "MAKEFILE")) {
            try self.load(body);
        } else if (equal(name, "MAKE")) {
            try self.make(try words(self.gpa, text));
        } else if (equal(name, "TOUCH")) {
            for (try words(self.gpa, text)) |n| try self.touch(n);
        } else if (equal(name, "RM")) {
            for (try words(self.gpa, text)) |n| if (!self.files.remove(n)) {
                try self.out.line("rm: cannot remove '{s}': No such file or directory", .{n});
            };
        } else if (equal(name, "FILES")) {
            try self.out.line("clock {d}", .{self.clock});
            for (try keys(self.gpa, self.files)) |n| try self.out.line("{s} {d}", .{ n, self.files.get(n).? });
        } else if (equal(name, "VARS")) {
            for (try keys(self.gpa, self.variables)) |n| {
                const value = trim(try self.reference(n));
                try self.out.print("{s} {s}", .{ n, if (self.variables.get(n).?.simple) ":=" else "=" });
                if (value.len > 0) try self.out.print(" {s}", .{value});
                try self.out.add("\n");
            }
        } else if (equal(name, "RULES")) {
            for (try keys(self.gpa, self.rules)) |n| try self.display(self.rules.get(n).?);
            for (self.patterns.items) |r| if (r.recipe != null) {
                try self.display(r);
            };
            if (self.phony.count() > 0) try self.out.line(".PHONY: {s}", .{try join(self.gpa, try keys(self.gpa, self.phony), " ")});
        } else if (equal(name, "EXPAND")) {
            const value = try self.expand(text);
            try self.out.line("[{s}]", .{value});
        }
    }
};
const Build = struct {
    sim: *Simulator,
    options: [256]bool,
    results: std.StringHashMapUnmanaged(u8) = .empty,
    chosen: std.StringHashMapUnmanaged(Chosen) = .empty,
    building: std.StringHashMapUnmanaged(void) = .empty,
    runs: usize = 0,
    fn target(self: *Build, name: Text, parent: ?Text) Error!u8 {
        const m = self.sim;
        const gpa = m.gpa;
        if (self.results.get(name)) |result| return result;
        const r = try m.determine(name);
        try self.chosen.put(gpa, name, r);
        if (r.missing) {
            try m.out.print("make: *** No rule to make target '{s}'", .{name});
            if (parent) |p| try m.out.print(", needed by '{s}'", .{p});
            try m.out.add(if (self.options['k']) ".\n" else ".  Stop.\n");
            try self.results.put(gpa, name, 1);
            if (!self.options['k']) return error.Abort;
            return 1;
        }
        if (r.source) {
            try self.results.put(gpa, name, 0);
            return 0;
        }
        try self.building.put(gpa, name, {});
        var failed = false;
        var prerequisites: std.ArrayList(Text) = .empty;
        for (r.prerequisites) |p| {
            if (self.building.contains(p)) {
                try m.out.line("make: Circular {s} <- {s} dependency dropped.", .{ name, p });
                continue;
            }
            try prerequisites.append(gpa, p);
            if (try self.target(p, name) != 0) failed = true;
        }
        _ = self.building.remove(name);
        if (failed) {
            try self.results.put(gpa, name, 2);
            return 2;
        }
        const time = if (m.phony.contains(name)) null else m.files.get(name);
        var newer: std.ArrayList(Text) = .empty;
        for (prerequisites.items) |p| {
            const pt = if (m.phony.contains(p)) null else m.files.get(p);
            if (self.options['B'] or time == null or pt == null or pt.? > time.?) try newer.append(gpa, p);
        }
        if (r.recipe == null or !self.options['B'] and time != null and newer.items.len == 0) {
            try self.results.put(gpa, name, 0);
            return 0;
        }
        self.runs += 1;
        try m.automatic.put(gpa, "@", name);
        try m.automatic.put(gpa, "<", if (prerequisites.items.len > 0) prerequisites.items[0] else "");
        try m.automatic.put(gpa, "^", try join(gpa, prerequisites.items, " "));
        try m.automatic.put(gpa, "?", try join(gpa, newer.items, " "));
        try m.automatic.put(gpa, "*", r.stem);
        const recipe = r.recipe.?;
        const expanded = try gpa.alloc(Text, recipe.items.len);
        for (recipe.items, 0..) |line, i| {
            m.location = try std.fmt.allocPrint(gpa, "Makefile:{d}", .{line.number});
            expanded[i] = try m.expand(line.text);
        }
        m.automatic = .empty;
        for (expanded, 0..) |text, i| {
            var pos: usize = 0;
            while (pos < text.len and std.mem.findScalar(u8, " @-", text[pos]) != null) : (pos += 1) {}
            const prefix = text[0..pos];
            const command = std.mem.trimEnd(u8, text[pos..], " ");
            if (command.len == 0) continue;
            if (self.options['n'] or std.mem.findScalar(u8, prefix, '@') == null and !self.options['s']) try m.out.line("{s}", .{command});
            if (self.options['n']) continue;
            const code = try m.execute(command);
            if (code == 0) continue;
            if (std.mem.findScalar(u8, prefix, '-') != null or self.options['i']) {
                try m.out.line("make: [Makefile:{d}: {s}] Error {d} (ignored)", .{ recipe.items[i].number, name, code });
            } else {
                try m.out.line("make: *** [Makefile:{d}: {s}] Error {d}", .{ recipe.items[i].number, name, code });
                try self.results.put(gpa, name, 1);
                if (!self.options['k']) return error.Abort;
                return 1;
            }
        }
        if (!m.phony.contains(name)) try m.touch(name);
        try self.results.put(gpa, name, 0);
        return 0;
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
    _ = lines.next();
    var out: Builder = .{ .gpa = gpa };
    var sim: Simulator = .{ .gpa = gpa, .out = &out };
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "END FILES")) break;
        const at = std.mem.findScalar(u8, line, ' ').?;
        const time = number(line[at + 1 ..]);
        try sim.files.put(gpa, line[0..at], time);
        sim.clock = @max(sim.clock, time);
    }
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "QUIT")) break;
        var body: std.ArrayList(Text) = .empty;
        if (equal(line, "MAKEFILE")) {
            while (lines.next()) |next| {
                const item = std.mem.trimEnd(u8, next, "\r");
                if (equal(item, "END MAKEFILE")) break;
                try body.append(gpa, item);
            }
        }
        sim.command(line, body.items) catch |err| {
            if (err != error.Invalid) return err;
            try out.line("{s}: *** {s}.  Stop.", .{ failureLocation, failure });
        };
    }
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
