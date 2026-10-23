const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";

fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void { try self.bytes.appendSlice(self.gpa, text); }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void { try self.print(pattern ++ "\n", args); }
};
fn split(gpa: Allocator, text: Text, separator: Text, limit: usize) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    while (limit == 0 or result.items.len + 1 < limit) {
        const offset = std.mem.find(u8, text[start..], separator) orelse break;
        try result.append(gpa, text[start..start + offset]);
        start += offset + separator.len;
    }
    try result.append(gpa, text[start..]);
    return result.items;
}
fn textLess(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; }
fn keys(gpa: Allocator, map: anytype) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, textLess);
    return result.items;
}
fn join(gpa: Allocator, parts: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (parts, 0..) |part, i| {
        if (i > 0) try out.add(separator);
        try out.add(part);
    }
    return out.bytes.items;
}
fn numeric(text: Text) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
fn numberWord(text: Text) bool {
    return text.len >= 1 and text.len <= 4 and numeric(text) and (text.len == 1 or text[0] != '0');
}
fn integer(text: Text) usize { return std.fmt.parseInt(usize, text, 10) catch unreachable; }
const Version = struct { core: [3]usize, pre: []const Text, text: Text };
fn makeVersion(gpa: Allocator, core: [3]usize, pre: []const Text) Allocator.Error!Version {
    const base = try std.fmt.allocPrint(gpa, "{d}.{d}.{d}", .{ core[0], core[1], core[2] });
    const text = if (pre.len == 0) base else try std.fmt.allocPrint(gpa, "{s}-{s}", .{ base, try join(gpa, pre, ".") });
    return .{ .core = core, .pre = pre, .text = text };
}
fn parseVersion(gpa: Allocator, text: Text) Allocator.Error!?Version {
    const fields = try split(gpa, text, "-", 2);
    const parts = try split(gpa, fields[0], ".", 0);
    if (parts.len != 3) return null;
    var core: [3]usize = undefined;
    for (parts, 0..) |part, i| {
        if (!numberWord(part)) return null;
        core[i] = integer(part);
    }
    var pre: []const Text = &.{};
    if (fields.len == 2) {
        pre = try split(gpa, fields[1], ".", 0);
        for (pre) |part| {
            if (part.len == 0) return null;
            for (part) |c| if ((c < 'a' or c > 'z') and !std.ascii.isDigit(c)) return null;
            if (numeric(part) and !numberWord(part)) return null;
        }
    }
    return try makeVersion(gpa, core, pre);
}
fn compare(a: Version, b: Version) std.math.Order {
    for (a.core, b.core) |x, y| {
        if (x != y) return if (x < y) .lt else .gt;
    }
    if (a.pre.len == 0 and b.pre.len > 0) return .gt;
    if (b.pre.len == 0 and a.pre.len > 0) return .lt;
    for (0..@min(a.pre.len, b.pre.len)) |i| {
        const x = a.pre[i];
        const y = b.pre[i];
        if (equal(x, y)) continue;
        const nx = numeric(x);
        const ny = numeric(y);
        if (nx and ny) return if (integer(x) < integer(y)) .lt else .gt;
        if (nx != ny) return if (nx) .lt else .gt;
        return std.mem.order(u8, x, y);
    }
    return if (a.pre.len < b.pre.len) .lt else if (a.pre.len > b.pre.len) .gt else .eq;
}
const Operator = enum { eq, gt, ge, lt, le };
const Comparator = struct { op: Operator, value: Version };
const Alternative = struct { comparisons: []const Comparator, prerelease: []const [3]usize };
const Constraint = struct {
    alternatives: []const Alternative, normal: Text,
    fn matches(self: *const Constraint, value: Version) bool {
        for (self.alternatives) |branch| {
            var allowed = value.pre.len == 0;
            for (branch.prerelease) |core| {
                if (std.mem.eql(usize, &core, &value.core)) { allowed = true; break; }
            }
            if (!allowed) continue;
            var valid = true;
            for (branch.comparisons) |comparison| {
                const order = compare(value, comparison.value);
                valid = switch (comparison.op) { .eq => order == .eq, .gt => order == .gt, .ge => order != .lt, .lt => order == .lt, .le => order != .gt };
                if (!valid) break;
            }
            if (valid) return true;
        }
        return false;
    }
};
fn operatorText(op: Operator) Text {
    return switch (op) { .eq => "=", .gt => ">", .ge => ">=", .lt => "<", .le => "<=" };
}
fn upperVersion(gpa: Allocator, core: [3]usize, at: usize) Allocator.Error!Version {
    var next = core;
    next[at] += 1;
    for (at + 1..3) |i| next[i] = 0;
    return makeVersion(gpa, next, &.{});
}
fn parseConstraint(gpa: Allocator, text: Text) Allocator.Error!?*Constraint {
    var alternatives: std.ArrayList(Alternative) = .empty;
    var forms: std.ArrayList(Text) = .empty;
    for (try split(gpa, text, " || ", 0)) |branch| {
        var comparisons: std.ArrayList(Comparator) = .empty;
        var prerelease: std.ArrayList([3]usize) = .empty;
        for (try split(gpa, branch, " ", 0)) |term| {
            if (term.len == 0) return null;
            var op: Text = "";
            var pattern = term;
            for ([_]Text{ ">=", "<=", ">", "<", "=", "^", "~" }) |candidate| {
                if (std.mem.startsWith(u8, term, candidate)) { op = candidate; pattern = term[candidate.len..]; break; }
            }
            var core = [_]usize{ 0, 0, 0 };
            var pre: []const Text = &.{};
            var count: usize = 0;
            if (std.mem.findScalar(u8, pattern, '-') != null) {
                const value = (try parseVersion(gpa, pattern)) orelse return null;
                if (value.pre.len == 0) return null;
                core = value.core;
                pre = value.pre;
                count = 3;
                try prerelease.append(gpa, core);
            } else {
                const parts = try split(gpa, pattern, ".", 0);
                if (parts.len > 3) return null;
                var wildcard = false;
                for (parts, 0..) |part, i| {
                    if (equal(part, "x") or equal(part, "*")) wildcard = true else {
                        if (wildcard or !numberWord(part)) return null;
                        core[i] = integer(part);
                        count += 1;
                    }
                }
            }
            const lower = try makeVersion(gpa, core, pre);
            if (count == 0) {
                if (equal(op, ">") or equal(op, "<")) try comparisons.append(gpa, .{ .op = .lt, .value = try makeVersion(gpa, .{ 0, 0, 0 }, &.{"0"}) });
            } else if (op.len == 0 or equal(op, "=")) {
                if (count == 3) try comparisons.append(gpa, .{ .op = .eq, .value = lower }) else {
                    try comparisons.append(gpa, .{ .op = .ge, .value = lower });
                    try comparisons.append(gpa, .{ .op = .lt, .value = try upperVersion(gpa, core, count - 1) });
                }
            } else if (equal(op, ">")) {
                try comparisons.append(gpa, .{ .op = if (count == 3) .gt else .ge, .value = if (count == 3) lower else try upperVersion(gpa, core, count - 1) });
            } else if (equal(op, "<=")) {
                try comparisons.append(gpa, .{ .op = if (count == 3) .le else .lt, .value = if (count == 3) lower else try upperVersion(gpa, core, count - 1) });
            } else if (equal(op, ">=") or equal(op, "<")) {
                try comparisons.append(gpa, .{ .op = if (equal(op, ">=")) .ge else .lt, .value = lower });
            } else {
                const at: usize = if (equal(op, "~")) (if (count == 1) @as(usize, 0) else 1)
                    else if (core[0] != 0 or count == 1) 0 else if (core[1] != 0 or count == 2) 1 else 2;
                try comparisons.append(gpa, .{ .op = .ge, .value = lower });
                try comparisons.append(gpa, .{ .op = .lt, .value = try upperVersion(gpa, core, at) });
            }
        }
        var form: Builder = .{ .gpa = gpa };
        for (comparisons.items, 0..) |comparison, i| {
            if (i > 0) try form.add(" ");
            try form.print("{s}{s}", .{ operatorText(comparison.op), comparison.value.text });
        }
        if (comparisons.items.len == 0) try form.add("*");
        try forms.append(gpa, form.bytes.items);
        try alternatives.append(gpa, .{ .comparisons = comparisons.items, .prerelease = prerelease.items });
    }
    const result = try gpa.create(Constraint);
    result.* = .{ .alternatives = alternatives.items, .normal = try join(gpa, forms.items, " || ") };
    return result;
}
const Pair = struct { name: Text, text: Text };
const Release = struct { name: Text, version: Version, dependencies: []const Pair, conflicts: []const Pair, yanked: bool = false };
const Installation = std.StringHashMapUnmanaged(*Release);
const Set = std.StringHashMapUnmanaged(void);
const Advisory = struct { name: Text, text: Text };
const Requirement = struct { pair: Pair, chain: []const Text };
const Snapshot = struct { requests: []const Pair, installed: Installation };
const Resolution = struct { selected: ?Installation = null, failure: []const Text = &.{} };
fn releaseLess(_: void, a: *Release, b: *Release) bool { return compare(a.version, b.version) == .gt; }
fn label(gpa: Allocator, value: *Release) Allocator.Error!Text { return std.fmt.allocPrint(gpa, "{s}@{s}", .{ value.name, value.version.text }); }
fn clone(gpa: Allocator, items: Installation) Allocator.Error!Installation {
    var result: Installation = .empty;
    var iterator = items.iterator();
    while (iterator.next()) |entry| try result.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
    return result;
}
const Resolver = struct {
    manager: *Manager, gpa: Allocator, preferred: Set, audit: bool,
    selected: Installation = .empty,
    origins: std.StringHashMapUnmanaged(Requirement) = .empty,
    failure: ?[]const Text = null, depth: usize = 0,
    fn record(self: *Resolver, requirement: Requirement, reason: Text, extra: []const Text) Allocator.Error!void {
        if (self.failure != null and self.selected.count() <= self.depth) return;
        self.depth = self.selected.count();
        var lines: std.ArrayList(Text) = .empty;
        try lines.append(self.gpa, "UNSATISFIABLE");
        for (requirement.chain) |line| try lines.append(self.gpa, try std.fmt.allocPrint(self.gpa, "  {s}", .{line}));
        try lines.append(self.gpa, try std.fmt.allocPrint(self.gpa, "  {s}", .{reason}));
        for (extra) |line| try lines.append(self.gpa, try std.fmt.allocPrint(self.gpa, "    {s}", .{line}));
        self.failure = lines.items;
    }
    fn search(self: *Resolver, todo: []const Requirement) Allocator.Error!bool {
        if (todo.len == 0) return true;
        const requirement = todo[0];
        const name = requirement.pair.name;
        const text = requirement.pair.text;
        if (self.selected.get(name)) |chosen| {
            if (self.manager.matches(chosen.version, text)) return self.search(todo[1..]);
            try self.record(requirement, try std.fmt.allocPrint(self.gpa, "{s} was selected by:", .{try label(self.gpa, chosen)}), self.origins.get(name).?.chain);
            return false;
        }
        var candidates: std.ArrayList(*Release) = .empty;
        if (self.manager.held.contains(name)) {
            const value = self.manager.installed.get(name).?;
            if (self.manager.matches(value.version, text) and try self.manager.usable(self.gpa, value, self.audit)) {
                try candidates.append(self.gpa, value);
            } else {
                try self.record(requirement, try std.fmt.allocPrint(self.gpa, "{s} is held", .{try label(self.gpa, value)}), &.{});
                return false;
            }
        } else {
            if (self.manager.registry.get(name)) |versions| {
                for (versions.items) |value| {
                    if (self.manager.matches(value.version, text) and try self.manager.usable(self.gpa, value, self.audit)) try candidates.append(self.gpa, value);
                }
            }
            if (self.preferred.contains(name)) {
                for (candidates.items, 0..) |value, i| {
                    if (self.manager.installed.get(name) == value) {
                        _ = candidates.orderedRemove(i);
                        try candidates.insert(self.gpa, 0, value);
                        break;
                    }
                }
            }
            if (candidates.items.len == 0) {
                try self.record(requirement, try std.fmt.allocPrint(self.gpa, "no version of {s} matches {s}", .{ name, text }), &.{});
                return false;
            }
        }
        for (candidates.items) |candidate| {
            var conflicting: ?Text = null;
            for (try keys(self.gpa, self.selected)) |other| {
                const chosen = self.selected.get(other).?;
                var conflict = false;
                for (candidate.conflicts) |pair| {
                    if (equal(pair.name, other) and self.manager.matches(chosen.version, pair.text)) { conflict = true; break; }
                }
                if (!conflict) {
                    for (chosen.conflicts) |pair| {
                        if (equal(pair.name, name) and self.manager.matches(candidate.version, pair.text)) { conflict = true; break; }
                    }
                }
                if (conflict) { conflicting = other; break; }
            }
            if (conflicting) |other| {
                try self.record(requirement, try std.fmt.allocPrint(self.gpa, "{s} conflicts with {s}, which was selected by:", .{
                    try label(self.gpa, candidate), try label(self.gpa, self.selected.get(other).?) }), self.origins.get(other).?.chain);
                continue;
            }
            try self.selected.put(self.gpa, name, candidate);
            try self.origins.put(self.gpa, name, requirement);
            var following: std.ArrayList(Requirement) = .empty;
            for (candidate.dependencies) |pair| {
                var chain: std.ArrayList(Text) = .empty;
                try chain.appendSlice(self.gpa, requirement.chain);
                try chain.append(self.gpa, try std.fmt.allocPrint(self.gpa, "{s} requires {s} {s}", .{ try label(self.gpa, candidate), pair.name, pair.text }));
                try following.append(self.gpa, .{ .pair = pair, .chain = chain.items });
            }
            try following.appendSlice(self.gpa, todo[1..]);
            if (try self.search(following.items)) return true;
            _ = self.selected.remove(name);
            _ = self.origins.remove(name);
        }
        return false;
    }
};
const Manager = struct {
    gpa: Allocator, out: *Builder,
    registry: std.StringHashMapUnmanaged(std.ArrayList(*Release)) = .empty,
    parsed: std.StringHashMapUnmanaged(*Constraint) = .empty,
    requests: []const Pair = &.{}, installed: Installation = .empty, held: Set = .empty,
    advisories: std.StringHashMapUnmanaged(Advisory) = .empty,
    history: std.ArrayList(Snapshot) = .empty,
    fn constraint(self: *Manager, text: Text) Error!*Constraint {
        if (self.parsed.get(text)) |value| return value;
        const value = (try parseConstraint(self.gpa, text)) orelse return bad(self.gpa, "invalid constraint '{s}'", .{text});
        try self.parsed.put(self.gpa, text, value);
        return value;
    }
    fn checkedVersion(self: *Manager, text: Text) Error!Version {
        return (try parseVersion(self.gpa, text)) orelse return bad(self.gpa, "invalid version '{s}'", .{text});
    }
    fn matches(self: *const Manager, value: Version, text: Text) bool { return self.parsed.get(text).?.matches(value); }
    fn find(self: *const Manager, name: Text, text: Text) ?*Release {
        if (self.registry.get(name)) |versions| {
            for (versions.items) |value| if (equal(value.version.text, text)) return value;
        }
        return null;
    }
    fn applicable(self: *const Manager, gpa: Allocator, value: *Release) Allocator.Error![]Text {
        var result: std.ArrayList(Text) = .empty;
        for (try keys(gpa, self.advisories)) |id| {
            const advisory = self.advisories.get(id).?;
            if (equal(advisory.name, value.name) and self.matches(value.version, advisory.text)) try result.append(gpa, id);
        }
        return result.items;
    }
    fn usable(self: *const Manager, gpa: Allocator, value: *Release, audit: bool) Allocator.Error!bool {
        return (!value.yanked or self.installed.get(value.name) == value) and (!audit or (try self.applicable(gpa, value)).len == 0);
    }
    fn display(self: *const Manager, gpa: Allocator, value: *Release) Allocator.Error!Text {
        const active = self.installed.get(value.name) == value;
        const suffix: Text = if (value.yanked and active) " (yanked, installed)" else if (value.yanked) " (yanked)" else if (active) " (installed)" else "";
        return std.fmt.allocPrint(gpa, "{s}{s}", .{ try label(gpa, value), suffix });
    }
    fn resolve(self: *Manager, scratch: Allocator, requests: []const Pair, preferred: Set, audit: bool) Allocator.Error!Resolution {
        var resolver: Resolver = .{ .manager = self, .gpa = scratch, .preferred = preferred, .audit = audit };
        var initial: std.ArrayList(Requirement) = .empty;
        for (requests) |pair| {
            const chain = try scratch.alloc(Text, 1);
            chain[0] = try std.fmt.allocPrint(scratch, "requested {s} {s}", .{ pair.name, pair.text });
            try initial.append(scratch, .{ .pair = pair, .chain = chain });
        }
        if (try resolver.search(initial.items)) return .{ .selected = resolver.selected };
        return .{ .failure = resolver.failure.? };
    }
    fn reportFailure(self: *Manager, lines: []const Text) Allocator.Error!void {
        for (lines) |line| try self.out.line("{s}", .{line});
    }
    fn plan(self: *Manager, scratch: Allocator, next: Installation) Allocator.Error!void {
        var arranged: Set = .empty;
        var added: usize = 0;
        var upgraded: usize = 0;
        var downgraded: usize = 0;
        var removed: usize = 0;
        const names = try keys(scratch, next);
        while (arranged.count() < next.count()) {
            for (names) |name| {
                if (arranged.contains(name)) continue;
                const value = next.get(name).?;
                var ready = true;
                for (value.dependencies) |pair| if (!arranged.contains(pair.name)) { ready = false; break; };
                if (!ready) continue;
                if (self.installed.get(name)) |old| {
                    if (old != value) {
                        const newer = compare(value.version, old.version) == .gt;
                        if (newer) upgraded += 1 else downgraded += 1;
                        try self.out.line("{s} {s} {s} -> {s}", .{ if (newer) @as(Text, "upgrade") else "downgrade", name, old.version.text, value.version.text });
                    }
                } else {
                    try self.out.line("install {s}", .{try label(scratch, value)});
                    added += 1;
                }
                try arranged.put(scratch, name, {});
                break;
            }
        }
        var dropping: Set = .empty;
        for (try keys(scratch, self.installed)) |name| if (!next.contains(name)) { try dropping.put(scratch, name, {}); };
        while (dropping.count() > 0) {
            for (try keys(scratch, dropping)) |name| {
                var ready = true;
                for (try keys(scratch, dropping)) |other| {
                    for (self.installed.get(other).?.dependencies) |pair| {
                        if (equal(pair.name, name)) { ready = false; break; }
                    }
                    if (!ready) break;
                }
                if (ready) {
                    try self.out.line("remove {s}", .{try label(scratch, self.installed.get(name).?)});
                    _ = dropping.remove(name);
                    removed += 1;
                    break;
                }
            }
        }
        if (added + upgraded + downgraded + removed == 0) try self.out.add("no changes\n")
        else try self.out.line("{d} installed, {d} upgraded, {d} downgraded, {d} removed", .{ added, upgraded, downgraded, removed });
    }
    fn update(self: *Manager, requests: []const Pair, installed: Installation, save: bool) Allocator.Error!void {
        if (save) try self.history.append(self.gpa, .{ .requests = try self.gpa.dupe(Pair, self.requests), .installed = try clone(self.gpa, self.installed) });
        self.requests = try self.gpa.dupe(Pair, requests);
        self.installed = try clone(self.gpa, installed);
        var keep: Set = .empty;
        var iterator = self.held.keyIterator();
        while (iterator.next()) |name| if (installed.contains(name.*)) { try keep.put(self.gpa, name.*, {}); };
        self.held = keep;
    }
    fn requested(self: *const Manager, name: Text) ?Text {
        for (self.requests) |pair| if (equal(pair.name, name)) return pair.text;
        return null;
    }
    fn parent(self: *const Manager, scratch: Allocator, name: Text) Allocator.Error!Text {
        for (try keys(scratch, self.installed)) |candidate| {
            for (self.installed.get(candidate).?.dependencies) |pair| if (equal(pair.name, name)) return candidate;
        }
        unreachable;
    }
    fn allPreferred(self: *const Manager, scratch: Allocator) Allocator.Error!Set {
        var result: Set = .empty;
        for (try keys(scratch, self.installed)) |name| try result.put(scratch, name, {});
        return result;
    }
    fn tree(self: *Manager, scratch: Allocator, root: Text, seen: *Set, text: ?Text, prefix: Text, indent: Text) Allocator.Error!void {
        const value = self.installed.get(root).?;
        try self.out.print("{s}{s}", .{ prefix, try label(scratch, value) });
        if (text) |condition| try self.out.print(" [{s}]", .{condition});
        if (seen.contains(root)) { try self.out.add(" (*)\n"); return; }
        try self.out.add("\n");
        try seen.put(scratch, root, {});
        for (value.dependencies, 0..) |pair, i| {
            const last = i + 1 == value.dependencies.len;
            const next_prefix = try std.fmt.allocPrint(scratch, "{s}{s}", .{ indent, if (last) @as(Text, "`-- ") else "|-- " });
            const next_indent = try std.fmt.allocPrint(scratch, "{s}{s}", .{ indent, if (last) @as(Text, "    ") else "|   " });
            try self.tree(scratch, pair.name, seen, pair.text, next_prefix, next_indent);
        }
    }
    fn command(self: *Manager, scratch: Allocator, line: Text) Error!void {
        const w = try split(scratch, line, " ", 0);
        const cmd = w[0];
        if (equal(cmd, "PKG")) {
            const clauses = try split(scratch, line, "; ", 0);
            const head = try split(scratch, clauses[0], " ", 0);
            const version = try self.checkedVersion(head[2]);
            if (self.find(head[1], head[2]) != null) return bad(self.gpa, "{s}@{s} is already registered", .{ head[1], head[2] });
            var dependencies: std.ArrayList(Pair) = .empty;
            var conflicts: std.ArrayList(Pair) = .empty;
            for (clauses[1..]) |clause| {
                const parts = try split(scratch, clause, " ", 3);
                _ = try self.constraint(parts[2]);
                const pair: Pair = .{ .name = parts[1], .text = parts[2] };
                if (equal(parts[0], "DEP")) try dependencies.append(self.gpa, pair) else try conflicts.append(self.gpa, pair);
            }
            const value = try self.gpa.create(Release);
            value.* = .{ .name = head[1], .version = version, .dependencies = dependencies.items, .conflicts = conflicts.items };
            var versions = self.registry.get(value.name) orelse std.ArrayList(*Release).empty;
            try versions.append(self.gpa, value);
            std.mem.sort(*Release, versions.items, {}, releaseLess);
            try self.registry.put(self.gpa, value.name, versions);
            try self.out.line("registered {s}", .{try label(scratch, value)});
        } else if (equal(cmd, "YANK") or equal(cmd, "INFO")) {
            const value = self.find(w[1], w[2]) orelse return bad(self.gpa, "{s}@{s} is not registered", .{ w[1], w[2] });
            if (equal(cmd, "YANK")) {
                if (value.yanked) return bad(self.gpa, "{s} is already yanked", .{try label(scratch, value)});
                value.yanked = true;
                try self.out.line("yanked {s}", .{try label(scratch, value)});
            } else {
                try self.out.line("{s}", .{try self.display(scratch, value)});
                for (value.dependencies) |pair| try self.out.line("  requires {s} {s}", .{ pair.name, pair.text });
                for (value.conflicts) |pair| try self.out.line("  conflicts with {s} {s}", .{ pair.name, pair.text });
                for (try self.applicable(scratch, value)) |id| try self.out.line("  advisory {s}", .{id});
            }
        } else if (equal(cmd, "COMPARE")) {
            const a = try self.checkedVersion(w[1]);
            const b = try self.checkedVersion(w[2]);
            const relation: Text = switch (compare(a, b)) { .lt => "<", .eq => "=", .gt => ">" };
            try self.out.line("{s} {s} {s}", .{ w[1], relation, w[2] });
        } else if (equal(cmd, "MATCH")) {
            const parts = try split(scratch, line, " ", 3);
            const value = try self.checkedVersion(parts[1]);
            const condition = try self.constraint(parts[2]);
            try self.out.line("{s}", .{if (condition.matches(value)) @as(Text, "yes") else "no"});
        } else if (equal(cmd, "RANGE")) {
            const condition = try self.constraint(line[6..]);
            try self.out.line("{s}", .{condition.normal});
        } else if (equal(cmd, "VERSIONS") or equal(cmd, "INSTALL") or equal(cmd, "SIMULATE")) {
            const parts = try split(scratch, line, " ", 3);
            const text: Text = if (parts.len == 3) parts[2] else "*";
            const condition = try self.constraint(text);
            const versions = self.registry.get(w[1]) orelse return bad(self.gpa, "unknown package {s}", .{w[1]});
            if (equal(cmd, "VERSIONS")) {
                var count: usize = 0;
                for (versions.items) |value| {
                    if (parts.len == 2 or condition.matches(value.version)) {
                        try self.out.line("{s}", .{try self.display(scratch, value)});
                        count += 1;
                    }
                }
                if (count == 0) try self.out.add("no matching versions\n");
            } else {
                var requests: std.ArrayList(Pair) = .empty;
                try requests.appendSlice(scratch, self.requests);
                var found = false;
                for (requests.items) |*pair| {
                    if (equal(pair.name, w[1])) { pair.text = text; found = true; break; }
                }
                if (!found) try requests.append(scratch, .{ .name = w[1], .text = text });
                const result = try self.resolve(scratch, requests.items, try self.allPreferred(scratch), false);
                if (result.selected) |selected| {
                    try self.plan(scratch, selected);
                    if (equal(cmd, "INSTALL")) try self.update(requests.items, selected, true);
                } else try self.reportFailure(result.failure);
            }
        } else if (equal(cmd, "DEPENDENTS")) {
            const selected: ?Version = if (w.len == 3) try self.checkedVersion(w[2]) else null;
            var count: usize = 0;
            for (try keys(scratch, self.registry)) |name| {
                for (self.registry.get(name).?.items) |value| {
                    for (value.dependencies) |pair| {
                        if (equal(pair.name, w[1]) and (selected == null or self.matches(selected.?, pair.text))) {
                            try self.out.line("{s} requires {s} {s}", .{ try label(scratch, value), w[1], pair.text });
                            count += 1;
                        }
                    }
                }
            }
            if (count == 0) try self.out.add("no dependents\n");
        } else if (equal(cmd, "REMOVE")) {
            if (self.requested(w[1]) == null) {
                if (self.installed.contains(w[1])) return bad(self.gpa, "{s} is required by {s}", .{ w[1], try self.parent(scratch, w[1]) });
                return bad(self.gpa, "{s} is not installed", .{w[1]});
            }
            var requests: std.ArrayList(Pair) = .empty;
            var keep: Installation = .empty;
            var queue: std.ArrayList(Text) = .empty;
            for (self.requests) |pair| {
                if (!equal(pair.name, w[1])) { try requests.append(scratch, pair); try queue.append(scratch, pair.name); }
            }
            var at: usize = 0;
            while (at < queue.items.len) : (at += 1) {
                const name = queue.items[at];
                if (keep.contains(name)) continue;
                const value = self.installed.get(name).?;
                try keep.put(scratch, name, value);
                for (value.dependencies) |pair| try queue.append(scratch, pair.name);
            }
            if (keep.contains(w[1])) {
                try self.out.line("{s} is still required by {s}", .{ try label(scratch, self.installed.get(w[1]).?), try self.parent(scratch, w[1]) });
                try self.update(requests.items, self.installed, true);
            } else {
                try self.plan(scratch, keep);
                try self.update(requests.items, keep, true);
            }
        } else if (equal(cmd, "UPGRADE")) {
            if (w.len == 2 and !self.installed.contains(w[1])) return bad(self.gpa, "{s} is not installed", .{w[1]});
            var preferred: Set = .empty;
            if (w.len == 2) { preferred = try self.allPreferred(scratch); _ = preferred.remove(w[1]); }
            const result = try self.resolve(scratch, self.requests, preferred, false);
            if (result.selected) |selected| {
                try self.plan(scratch, selected);
                try self.update(self.requests, selected, true);
            } else try self.reportFailure(result.failure);
        } else if (equal(cmd, "ROLLBACK")) {
            if (self.history.items.len == 0) return bad(self.gpa, "nothing to roll back", .{});
            const saved = self.history.pop().?;
            try self.plan(scratch, saved.installed);
            try self.update(saved.requests, saved.installed, false);
        } else if (equal(cmd, "HOLD")) {
            const value = self.installed.get(w[1]) orelse return bad(self.gpa, "{s} is not installed", .{w[1]});
            if (self.held.contains(w[1])) return bad(self.gpa, "{s} is already held", .{w[1]});
            try self.held.put(self.gpa, w[1], {});
            try self.out.line("held {s}", .{try label(scratch, value)});
        } else if (equal(cmd, "UNHOLD")) {
            if (!self.held.contains(w[1])) return bad(self.gpa, "{s} is not held", .{w[1]});
            _ = self.held.remove(w[1]);
            try self.out.line("released {s}", .{w[1]});
        } else if (equal(cmd, "WHY")) {
            const value = self.installed.get(w[1]) orelse return bad(self.gpa, "{s} is not installed", .{w[1]});
            if (self.requested(w[1]) != null) {
                try self.out.line("{s} is explicitly installed", .{try label(scratch, value)});
                return;
            }
            var previous: std.StringHashMapUnmanaged(Text) = .empty;
            var seen: Set = .empty;
            var roots: Set = .empty;
            var queue: std.ArrayList(Text) = .empty;
            for (self.requests) |pair| try roots.put(scratch, pair.name, {});
            for (try keys(scratch, roots)) |name| { try queue.append(scratch, name); try seen.put(scratch, name, {}); }
            var at: usize = 0;
            while (at < queue.items.len) : (at += 1) {
                const name = queue.items[at];
                var deps: Set = .empty;
                for (self.installed.get(name).?.dependencies) |pair| try deps.put(scratch, pair.name, {});
                for (try keys(scratch, deps)) |dep| {
                    if (!seen.contains(dep)) {
                        try seen.put(scratch, dep, {});
                        try previous.put(scratch, dep, name);
                        try queue.append(scratch, dep);
                    }
                }
            }
            var path: std.ArrayList(Text) = .empty;
            var current: ?Text = w[1];
            while (current) |name| {
                try path.append(scratch, try label(scratch, self.installed.get(name).?));
                current = previous.get(name);
            }
            std.mem.reverse(Text, path.items);
            try self.out.line("{s}", .{try join(scratch, path.items, " -> ")});
        } else if (equal(cmd, "TREE")) {
            if (w.len == 2 and !self.installed.contains(w[1])) return bad(self.gpa, "{s} is not installed", .{w[1]});
            var roots: std.ArrayList(Text) = .empty;
            if (w.len == 2) try roots.append(scratch, w[1]) else {
                for (self.requests) |pair| try roots.append(scratch, pair.name);
                std.mem.sort(Text, roots.items, {}, textLess);
            }
            if (roots.items.len == 0) try self.out.add("(empty)\n");
            var seen: Set = .empty;
            for (roots.items) |name| try self.tree(scratch, name, &seen, self.requested(name), "", "");
        } else if (equal(cmd, "OUTDATED")) {
            var count: usize = 0;
            for (try keys(scratch, self.installed)) |name| {
                const current = self.installed.get(name).?;
                var conditions: std.ArrayList(Text) = .empty;
                if (self.requested(name)) |text| try conditions.append(scratch, text);
                var iterator = self.installed.valueIterator();
                while (iterator.next()) |other| {
                    for (other.*.dependencies) |pair| if (equal(pair.name, name)) { try conditions.append(scratch, pair.text); };
                }
                var wanted: ?*Release = null;
                var latest: ?*Release = null;
                for (self.registry.get(name).?.items) |value| {
                    if (!value.yanked and value.version.pre.len == 0 and latest == null) latest = value;
                    if (wanted != null or (value.yanked and value != current)) continue;
                    var valid = true;
                    for (conditions.items) |text| if (!self.matches(value.version, text)) { valid = false; break; };
                    if (valid) wanted = value;
                }
                if (wanted.? != current or (latest != null and compare(latest.?.version, current.version) == .gt)) {
                    try self.out.line("{s} {s} {s} {s}", .{ name, current.version.text, wanted.?.version.text, if (latest) |value| value.version.text else "-" });
                    count += 1;
                }
            }
            if (count == 0) try self.out.add("all packages are up to date\n");
        } else if (equal(cmd, "LOCK")) {
            if (self.installed.count() == 0) try self.out.add("(empty)\n");
            for (try keys(scratch, self.installed)) |name| try self.out.line("{s}", .{try label(scratch, self.installed.get(name).?)});
        } else if (equal(cmd, "STATUS")) {
            if (self.requests.len == 0) try self.out.add("no requests\n");
            for (self.requests) |pair| try self.out.line("{s} {s} -> {s}", .{ pair.name, pair.text, self.installed.get(pair.name).?.version.text });
            try self.out.line("{d} installed, {d} held, {d} snapshots", .{ self.installed.count(), self.held.count(), self.history.items.len });
        } else if (equal(cmd, "ADVISORY")) {
            const parts = try split(scratch, line, " ", 4);
            if (self.advisories.contains(w[1])) return bad(self.gpa, "advisory {s} already exists", .{w[1]});
            _ = try self.constraint(parts[3]);
            try self.advisories.put(self.gpa, w[1], .{ .name = w[2], .text = parts[3] });
            try self.out.line("advisory {s} recorded", .{w[1]});
        } else if (equal(cmd, "AUDIT")) {
            if (w.len == 2) {
                const result = try self.resolve(scratch, self.requests, try self.allPreferred(scratch), true);
                if (result.selected) |selected| {
                    try self.plan(scratch, selected);
                    try self.update(self.requests, selected, true);
                } else try self.reportFailure(result.failure);
            } else {
                var count: usize = 0;
                for (try keys(scratch, self.installed)) |name| {
                    const current = self.installed.get(name).?;
                    const ids = try self.applicable(scratch, current);
                    if (ids.len == 0) continue;
                    var fix: ?*Release = null;
                    const values = self.registry.get(name).?.items;
                    var i = values.len;
                    while (i > 0) {
                        i -= 1;
                        const value = values[i];
                        if (compare(value.version, current.version) == .gt and value.version.pre.len == 0 and !value.yanked and
                            (try self.applicable(scratch, value)).len == 0) { fix = value; break; }
                    }
                    const suffix = if (fix) |value| try std.fmt.allocPrint(scratch, "fix: {s}", .{value.version.text}) else "no fix";
                    try self.out.line("{s}: {s} ({s})", .{ try label(scratch, current), try join(scratch, ids, ", "), suffix });
                    count += 1;
                }
                if (count == 0) try self.out.add("no known vulnerabilities\n");
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const count = integer(lines.next().?);
    var out: Builder = .{ .gpa = gpa };
    var manager: Manager = .{ .gpa = gpa, .out = &out };
    for (0..count) |_| {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();
        manager.command(scratch, lines.next().?) catch |err| switch (err) {
            error.Invalid => try out.line("error: {s}", .{failure}),
            else => return err,
        };
    }
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
