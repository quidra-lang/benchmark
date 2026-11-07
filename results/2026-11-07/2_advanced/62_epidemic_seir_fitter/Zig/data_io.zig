const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn real(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub const Group = struct { name: []const u8, population: i64, fatality: f64 };
pub const Intervention = struct { day: usize, multiplier: f64 };
pub const Scenario = struct { name: []const u8, multiplier: f64 };
pub const ContactChange = struct { name: []const u8, group: []const u8, factor: f64 };
pub const Params = struct {
    sigma: f64 = 0,
    gamma: f64 = 0,
    e0: f64 = 0,
    i0: f64 = 0,
    beta_min: f64 = 0,
    beta_max: f64 = 0,
    rho_min: f64 = 0,
    rho_max: f64 = 0,
    delta_beta: f64 = 0,
    delta_gamma: f64 = 0,
    alpha: f64 = 0,
    chi: f64 = 0,
    psi: f64 = 0,
    omega: f64 = 0,
    effect_width: f64 = 0,
    outlier: f64 = 0,
    threshold: f64 = 0,
    beta_count: usize = 0,
    rho_count: usize = 0,
    golden: usize = 0,
    rounds: usize = 0,
    nelder: usize = 0,
    holdout: usize = 0,
    death_lag: usize = 0,
    generation: usize = 0,
    horizon: usize = 0,
    milestones: []const i64 = &.{},
    scenarios: std.ArrayList(Scenario) = .empty,
    changes: std.ArrayList(ContactChange) = .empty,
};
pub const Input = struct { cases: []const i64, deaths: []const i64, groups: []const Group,
     contacts: [6][6]f64, interventions: []const Intervention, params: Params };
pub fn load(io: std.Io) !Input {
    const lines = try readLines(io, "input/cases.csv");
    const cases = alloc(i64, lines.len - 1);
    const deaths = alloc(i64, cases.len);
    for (lines[1..], 0..) |line, i| {
        const row = split(line, ',');
        cases[i] = number(row[1]);
        deaths[i] = number(row[2]);
    }
    var groups: std.ArrayList(Group) = .empty;
    var contacts: [6][6]f64 = std.mem.zeroes([6][6]f64);
    var contact_index: usize = 0;
    for (try readLines(io, "input/population.txt")) |line| {
        const row = words(line);
        if (eq(row[0], "group")) append(Group, &groups, .{ .name = row[1], .population = number(row[2]),
             .fatality = real(row[3]) }) else {
            for (row[1..], 0..) |value, h| contacts[contact_index][h] = real(value);
            contact_index += 1;
        }
    }
    var interventions: std.ArrayList(Intervention) = .empty;
    for (try readLines(io, "input/interventions.txt")) |line| {
        const row = words(line);
        append(Intervention, &interventions, .{ .day = u(number(row[0])), .multiplier = real(row[1]) });
    }
    var params: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const row = words(line);
        const key = row[0];
        if (eq(key, "sigma")) params.sigma = real(row[1]) else if (eq(key, "gamma")) params.gamma = real(row[1]) else if (eq(key,
             "initial")) {
            params.e0 = real(row[1]);
            params.i0 = real(row[2]);
        } else if (eq(key, "beta_grid")) {
            params.beta_min = real(row[1]);
            params.beta_max = real(row[2]);
            params.beta_count = u(number(row[3]));
        } else if (eq(key, "rho_grid")) {
            params.rho_min = real(row[1]);
            params.rho_max = real(row[2]);
            params.rho_count = u(number(row[3]));
        } else if (eq(key, "golden")) {
            params.golden = u(number(row[1]));
            params.rounds = u(number(row[2]));
        } else if (eq(key, "simplex")) {
            params.delta_beta = real(row[1]);
            params.delta_gamma = real(row[2]);
        } else if (eq(key, "nelder_mead")) {
            params.alpha = real(row[1]);
            params.chi = real(row[2]);
            params.psi = real(row[3]);
            params.omega = real(row[4]);
            params.nelder = u(number(row[5]));
        } else if (eq(key, "holdout")) params.holdout = u(number(row[1])) else if (eq(key,
             "effect_width")) params.effect_width = real(row[1]) else if (eq(key, "outlier")) params.outlier = real(row[1]) else if (eq(key,
             "death_lag")) params.death_lag = u(number(row[1])) else if (eq(key, "milestones")) {
            const values = alloc(i64, row.len - 1);
            for (row[1..], values) |value, *target| target.* = number(value);
            params.milestones = values;
        } else if (eq(key, "generation")) params.generation = u(number(row[1])) else if (eq(key,
             "horizon")) params.horizon = u(number(row[1])) else if (eq(key, "threshold")) params.threshold = real(row[1]) else if (eq(key,
             "scenario")) append(Scenario, &params.scenarios, .{ .name = row[1], .multiplier = real(row[2]) }) else if (eq(key,
             "contact_change")) append(ContactChange, &params.changes, .{ .name = row[1], .group = row[2],
             .factor = real(row[3]) });
    }
    return .{ .cases = cases, .deaths = deaths, .groups = groups.items, .contacts = contacts,
         .interventions = interventions.items, .params = params };
}
pub fn save(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
