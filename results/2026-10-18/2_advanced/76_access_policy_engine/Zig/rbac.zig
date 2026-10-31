const std = @import("std");
const x = @import("expressions.zig");
pub const Roles = u64;
pub fn bit(role: usize) Roles {
    return @as(Roles, 1) << @intCast(role);
}
pub fn cardinality(roles: Roles) usize {
    return @popCount(roles);
}
pub const Grant = struct { role: usize, action: []const u8, resource_type: []const u8 };
pub const Constraint = struct { name: []const u8, cardinality: usize, roles: Roles };
pub const Assignment = struct { user: []const u8, role: usize, first: i64, last: i64 };
pub const Diagnostic = struct { number: usize, keyword: []const u8, message: []const u8 };
pub const RBAC = struct {
    roles: std.ArrayList([]const u8) = .empty,
    inherits: [40]Roles = @splat(0),
    grants: std.ArrayList(Grant) = .empty,
    ssd: std.ArrayList(Constraint) = .empty,
    dsd: std.ArrayList(Constraint) = .empty,
    assignments: std.ArrayList(Assignment) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    pub fn find(self: RBAC, name: []const u8) ?usize {
        for (self.roles.items, 0..) |role, i| if (x.eq(role, name)) return i;
        return null;
    }
    pub fn closure(self: RBAC, source: Roles) Roles {
        var result = source;
        while (true) {
            const previous = result;
            for (0..self.roles.items.len) |i| if (result & bit(i) != 0) {
                result |= self.inherits[i];
            };
            if (result == previous) return result;
        }
    }
    pub fn assigned(self: RBAC, user: []const u8, day: i64) Roles {
        var result: Roles = 0;
        for (self.assignments.items) |a| if (x.eq(a.user, user) and a.first <= day and day <= a.last) {
            result |= bit(a.role);
        };
        return result;
    }
    pub fn authorized(self: RBAC, user: []const u8, day: i64) Roles {
        return self.closure(self.assigned(user, day));
    }
    pub fn names(self: RBAC, source: Roles) x.Names {
        var result: std.ArrayList([]const u8) = .empty;
        for (self.roles.items, 0..) |name, i| if (source & bit(i) != 0) x.append([]const u8, &result, name);
        std.mem.sort([]const u8, result.items, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);
        return result.items;
    }
    pub fn permits(self: RBAC, role: usize, action: []const u8, resource_type: []const u8) bool {
        for (self.grants.items) |g| if (g.role == role and x.eq(g.action, action) and x.eq(g.resource_type,
             resource_type)) return true;
        return false;
    }
    fn path(self: RBAC, from: usize, to: usize) []const u8 {
        if (from == to) return self.roles.items[to];
        for (self.names(self.inherits[from])) |name| {
            const junior = self.find(name).?;
            if (self.closure(bit(junior)) & bit(to) != 0) return x.fmt("{s} > {s}", .{ self.roles.items[from],
                 self.path(junior, to) });
        }
        unreachable;
    }
    fn accept(self: *RBAC, f: x.Names) ?[]const u8 {
        const keyword = f[0];
        if (x.eq(keyword, "ROLE")) {
            if (self.find(f[1]) != null) return x.fmt("duplicate role {s}", .{f[1]});
            x.append([]const u8, &self.roles, f[1]);
        } else if (x.eq(keyword, "INHERITS")) {
            const senior = self.find(f[1]) orelse return x.fmt("unknown role {s}", .{f[1]});
            const junior = self.find(f[2]) orelse return x.fmt("unknown role {s}", .{f[2]});
            if (self.inherits[senior] & bit(junior) != 0) return x.fmt("duplicate inheritance {s} {s}",
                 .{ f[1], f[2] });
            if (self.closure(bit(junior)) & bit(senior) != 0) return x.fmt("cycle {s} > {s}",
                 .{ f[1], self.path(junior, senior) });
            self.inherits[senior] |= bit(junior);
        } else if (x.eq(keyword, "PERMIT")) {
            const role = self.find(f[1]) orelse return x.fmt("unknown role {s}", .{f[1]});
            if (self.permits(role, f[2], f[3])) return x.fmt("duplicate permission {s} {s} {s}", .{ f[1], f[2], f[3] });
            x.append(Grant, &self.grants, .{ .role = role, .action = f[2], .resource_type = f[3] });
        } else if (x.eq(keyword, "SSD") or x.eq(keyword, "DSD")) {
            const constraints = if (x.eq(keyword, "SSD")) &self.ssd else &self.dsd;
            for (constraints.items) |c| if (x.eq(c.name, f[1])) return x.fmt("duplicate constraint {s}", .{f[1]});
            const role_list = x.split(f[3], ',');
            var mask: Roles = 0;
            for (role_list) |name| {
                const role = self.find(name) orelse return x.fmt("unknown role {s}", .{name});
                mask |= bit(role);
            }
            const count = x.number(f[2]);
            if (count < 2 or count > x.n(role_list.len)) return x.fmt("bad cardinality {s} {d}", .{ f[1], count });
            x.append(Constraint, constraints, .{ .name = f[1], .cardinality = x.u(count), .roles = mask });
        } else {
            const role = self.find(f[2]) orelse return x.fmt("unknown role {s}", .{f[2]});
            const first = x.number(f[3]);
            const last = x.number(f[4]);
            if (!(1 <= first and first <= last and last <= 365)) return x.fmt("bad range {d} {d}", .{ first, last });
            for (self.ssd.items) |c| {
                var day = first;
                while (day <= last) : (day += 1) {
                    const intersection = c.roles & self.closure(self.assigned(f[1], day) | bit(role));
                    if (cardinality(intersection) >= c.cardinality) return x.fmt("ssd {s} day {d} roles {s}",
                         .{ c.name, day, x.join(self.names(intersection), ",") });
                }
            }
            x.append(Assignment, &self.assignments, .{ .user = f[1], .role = role, .first = first, .last = last });
        }
        return null;
    }
    pub fn read(self: *RBAC, io: std.Io) !void {
        const lines = try x.readLines(io, "input/rbac.txt");
        for ([_][]const u8{ "ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN" }) |keyword| for (lines,
             0..) |line, i| {
            const f = x.words(line);
            if (!x.eq(f[0], keyword)) continue;
            if (self.accept(f)) |message| x.append(Diagnostic, &self.diagnostics, .{ .number = i + 1,
                 .keyword = keyword, .message = message });
        };
        std.mem.sort(Diagnostic, self.diagnostics.items, {}, struct {
            fn less(_: void, a: Diagnostic, b: Diagnostic) bool {
                return a.number < b.number;
            }
        }.less);
    }
};
