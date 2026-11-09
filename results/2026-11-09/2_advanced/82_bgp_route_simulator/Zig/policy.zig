const std = @import("std");
const t = @import("topology.zig");
pub var work_allocator: std.mem.Allocator = undefined;
pub const no_export: u32 = (@as(u32, 65535) << 16) | 65281;
pub fn parseCommunity(text: []const u8) u32 {
    if (t.eq(text, "NO_EXPORT")) return no_export;
    const f = t.split(text, ':');
    return (@as(u32, @intCast(t.number(f[0]))) << 16) | @as(u32, @intCast(t.number(f[1])));
}
pub fn communityText(value: u32) []const u8 {
    return if (value == no_export) "NO_EXPORT" else t.fmt("{d}:{d}", .{ value >> 16, value & 65535 });
}
pub fn communitiesText(values: []const u32) []const u8 {
    if (values.len == 0) return "-";
    var out: t.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{s}", .{ if (i == 0) "" else ",", communityText(value) });
    return out.value();
}
fn lessCommunity(_: void, a: u32, b: u32) bool {
    return a < b;
}
pub fn parseCommunities(values: t.Names) []const u32 {
    const out = t.alloc(u32, values.len);
    for (values, out) |value, *community| community.* = parseCommunity(value);
    std.mem.sort(u32, out, {}, lessCommunity);
    var length: usize = 0;
    for (out) |value| if (length == 0 or out[length - 1] != value) {
        out[length] = value;
        length += 1;
    };
    return out[0..length];
}
pub const Direction = enum { import_route, export_route };
pub const direction_names = [_][]const u8{ "IMPORT", "EXPORT" };
pub const Condition = struct { kind: enum { prefix, contains, origin_as, length, community },
     name: []const u8 = "", value: i64 = 0, high: i64 = 0 };
pub const Action = struct { kind: enum { deny, allow, local_pref, med, prepend, add, remove }, value: i64 = 0 };
pub const Rule = struct {
    name: []const u8,
    active: bool,
    owner: usize,
    direction: Direction,
    target: []const u8,
    target_neighbor: ?usize = null,
    conditions: []const Condition,
    actions: []const Action,
    hits: i64 = 0,
    pub fn has(self: Rule, kind: @FieldType(Action, "kind")) bool {
        for (self.actions) |action| if (action.kind == kind) return true;
        return false;
    }
    pub fn value(self: Rule, kind: @FieldType(Action, "kind"), default: i64) i64 {
        for (self.actions) |action| if (action.kind == kind) return action.value;
        return default;
    }
};
pub const ListEntry = struct { name: []const u8, permit: bool, prefix: t.Prefix, low: usize, high: usize };
pub const Edited = struct {
    values: []const u32,
    owned: ?[]u32 = null,
    pub fn deinit(self: Edited) void {
        if (self.owned) |values| work_allocator.free(values);
    }
};
pub fn editCommunities(values: []const u32, rule: ?*const Rule) Edited {
    const r = rule orelse return .{ .values = values };
    if (!r.has(.add) and !r.has(.remove)) return .{ .values = values };
    var edited: std.ArrayList(u32) = .empty;
    edited.appendSlice(work_allocator, values) catch @panic("allocation failed");
    for (r.actions) |action| {
        const value: u32 = @intCast(action.value);
        if (action.kind == .add) {
            if (std.mem.indexOfScalar(u32, edited.items, value) == null) edited.append(work_allocator,
                 value) catch @panic("allocation failed");
        } else if (action.kind == .remove) {
            if (std.mem.indexOfScalar(u32, edited.items, value)) |index| _ = edited.orderedRemove(index);
        }
    }
    std.mem.sort(u32, edited.items, {}, lessCommunity);
    const owned = edited.toOwnedSlice(work_allocator) catch @panic("allocation failed");
    return .{ .values = owned, .owned = owned };
}
pub const Policies = struct {
    lists: []const ListEntry,
    rules: []Rule,
    pub fn permitted(self: *const Policies, name: []const u8, prefix: t.Prefix) bool {
        for (self.lists) |entry| if (t.eq(entry.name, name) and entry.low <= prefix.length and prefix.length <= entry.high and entry.prefix.contains(prefix.address)) return entry.permit;
        return false;
    }
    fn matches(self: *const Policies, rule: Rule, owner: usize, link: t.Link, prefix: t.Prefix,
         path: []const usize, communities: []const u32) bool {
        if (!rule.active or rule.owner != owner) return false;
        if (!t.eq(rule.target, "*") and !t.eq(rule.target, link.name) and rule.target_neighbor != link.other(owner)) return false;
        for (rule.conditions) |condition| switch (condition.kind) {
            .prefix => if (!self.permitted(condition.name, prefix)) {
                return false;
            },
            .contains => if (std.mem.indexOfScalar(usize, path, t.u(condition.value)) == null) {
                return false;
            },
            .origin_as => if ((if (path.len == 0) owner else path[path.len - 1]) != t.u(condition.value)) {
                return false;
            },
            .length => if (t.n(path.len) < condition.value or t.n(path.len) > condition.high) {
                return false;
            },
            .community => if (std.mem.indexOfScalar(u32, communities, @intCast(condition.value)) == null) {
                return false;
            },
        };
        return true;
    }
    pub fn applied(self: *Policies, direction: Direction, owner: usize, link: t.Link, prefix: t.Prefix,
         path: []const usize, communities: []const u32) ?usize {
        for (self.rules, 0..) |rule, index| if (rule.direction == direction and self.matches(rule,
             owner, link, prefix, path, communities)) return index;
        return null;
    }
};
pub fn read(io: std.Io, network: *const t.Topology) !Policies {
    var lists: std.ArrayList(ListEntry) = .empty;
    var rules: std.ArrayList(Rule) = .empty;
    for (try t.readLines(io, "input/policies.txt")) |line| {
        const f = t.words(line);
        if (t.eq(f[0], "PLIST")) {
            const prefix = t.parsePrefix(f[3]);
            var low = prefix.length;
            var high = prefix.length;
            var i: usize = 4;
            while (i < f.len) : (i += 2) {
                if (t.eq(f[i], "GE")) {
                    low = t.u(t.number(f[i + 1]));
                    high = 32;
                } else high = t.u(t.number(f[i + 1]));
            }
            t.append(ListEntry, &lists, .{ .name = f[1], .permit = t.eq(f[2], "PERMIT"), .prefix = prefix,
                 .low = low, .high = high });
            continue;
        }
        var conditions: std.ArrayList(Condition) = .empty;
        var actions: std.ArrayList(Action) = .empty;
        var i: usize = 6;
        while (!t.eq(f[i], "THEN")) : (i += 2) {
            var condition: Condition = .{ .kind = .prefix };
            const kind = f[i];
            const value = f[i + 1];
            if (t.eq(kind, "PREFIX")) condition.name = value else if (t.eq(kind, "CONTAINS") or t.eq(kind,
                 "ORIGINAS")) {
                condition.kind = if (t.eq(kind, "CONTAINS")) .contains else .origin_as;
                var owner_index = network.ases.len;
                for (network.ases, 0..) |owner, index| if (owner.number == t.number(value)) {
                    owner_index = index;
                    break;
                };
                condition.value = t.n(owner_index);
            } else if (t.eq(kind, "LENGTH")) {
                const bounds = t.split(value, '-');
                condition = .{ .kind = .length, .value = t.number(bounds[0]), .high = t.number(bounds[1]) };
            } else condition = .{ .kind = .community, .value = parseCommunity(value) };
            t.append(Condition, &conditions, condition);
        }
        i += 1;
        while (i < f.len) {
            const name = f[i];
            i += 1;
            var action: Action = .{ .kind = .deny };
            if (t.eq(name, "DENY")) action.kind = .deny else if (t.eq(name, "ALLOW")) action.kind = .allow else {
                const kinds = [_]@FieldType(Action, "kind"){ .local_pref, .med, .prepend, .add, .remove };
                const names = [_][]const u8{ "LOCALPREF", "MED", "PREPEND", "ADD", "REMOVE" };
                for (names, kinds) |word, kind| if (t.eq(name, word)) {
                    action.kind = kind;
                };
                action.value = if (action.kind == .add or action.kind == .remove) parseCommunity(f[i]) else t.number(f[i]);
                i += 1;
            }
            t.append(Action, &actions, action);
        }
        const target_neighbor: ?usize = if (f[5][0] >= '0' and f[5][0] <= '9') network.asIndex(t.number(f[5])) else null;
        t.append(Rule, &rules, .{ .name = f[1], .active = t.eq(f[2], "ON"), .owner = network.asIndex(t.number(f[3])),
             .direction = if (t.eq(f[4], "IMPORT")) .import_route else .export_route, .target = f[5],
             .target_neighbor = target_neighbor, .conditions = conditions.items, .actions = actions.items });
    }
    return .{ .lists = lists.items, .rules = rules.items };
}
