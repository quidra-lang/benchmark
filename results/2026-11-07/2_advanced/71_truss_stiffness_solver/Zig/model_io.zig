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
pub fn decimal(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub const Node = struct { id: i64, x: i64, y: i64 };
pub const Member = struct { id: i64, start: usize, end: usize, section: usize, material: usize, group: []const u8 };
pub const Section = struct { name: []const u8, area: f64, inertia: f64 };
pub const Material = struct { name: []const u8, young: f64, yield_stress: f64, density: f64, expansion: f64 };
pub const Support = struct { node: usize, fixed: [2]bool, prescribed: [2]f64 };
pub const LoadKind = enum { force, temperature, selfweight, settlement };
pub const Load = struct { kind: LoadKind, index: usize = 0, x: f64 = 0, y: f64 = 0 };
pub const LoadCase = struct { name: []const u8, lines: []const Load };
pub const Term = struct { index: usize, factor: f64 };
pub const Combination = struct { name: []const u8, terms: []const Term };
pub const Axle = struct { offset: i64, load: f64 };
pub const Drawing = struct { name: []const u8, magnification: i64, horizontal: i64, vertical: i64 };
pub const Settings = struct { deck: []const usize = &.{}, influence: []const usize = &.{},
     vehicle_step: i64 = 0, axles: []const Axle = &.{}, rating: []const u8 = "", deflection: []const u8 = "",
     vibration: []const u8 = "", removal: []const u8 = "", dead_factor: f64 = 0, vehicle_factor: f64 = 0,
     compression_limit: f64 = 0, tension_limit: f64 = 0, deflection_ratio: i64 = 0, modes: usize = 0,
     iterations: usize = 0, map_horizontal: i64 = 0, map_vertical: i64 = 0, drawings: []const Drawing = &.{} };
pub const Model = struct { nodes: []const Node, members: []const Member, sections: []const Section,
     materials: []const Material, supports: []const Support, cases: []const LoadCase, combinations: []const Combination,
     settings: Settings };
fn nodeIndex(nodes: []const Node, id: i64) usize {
    for (nodes, 0..) |node, i| if (node.id == id) return i;
    unreachable;
}
fn memberIndex(members: []const Member, id: i64) usize {
    for (members, 0..) |member, i| if (member.id == id) return i;
    unreachable;
}
fn nameIndex(values: anytype, name: []const u8) usize {
    for (values, 0..) |value, i| if (eq(value.name, name)) return i;
    unreachable;
}
fn csv(io: std.Io, name: []const u8) ![]const []const u8 {
    const lines = try readLines(io, fmt("input/{s}.csv", .{name}));
    return lines[1..];
}
pub fn readModel(io: std.Io) !Model {
    var nodes: std.ArrayList(Node) = .empty;
    var members: std.ArrayList(Member) = .empty;
    var sections: std.ArrayList(Section) = .empty;
    var materials: std.ArrayList(Material) = .empty;
    var supports: std.ArrayList(Support) = .empty;
    var cases: std.ArrayList(LoadCase) = .empty;
    var combinations: std.ArrayList(Combination) = .empty;
    for (try csv(io, "nodes")) |text| {
        const row = split(text, ',');
        append(Node, &nodes, .{ .id = number(row[0]), .x = number(row[1]), .y = number(row[2]) });
    }
    for (try csv(io, "sections")) |text| {
        const row = split(text, ',');
        append(Section, &sections, .{ .name = row[0], .area = decimal(row[1]), .inertia = decimal(row[2]) });
    }
    for (try csv(io, "materials")) |text| {
        const row = split(text, ',');
        append(Material, &materials, .{ .name = row[0], .young = decimal(row[1]), .yield_stress = decimal(row[2]),
             .density = decimal(row[3]), .expansion = decimal(row[4]) });
    }
    for (try csv(io, "members")) |text| {
        const row = split(text, ',');
        append(Member, &members, .{ .id = number(row[0]), .start = nodeIndex(nodes.items, number(row[1])),
             .end = nodeIndex(nodes.items, number(row[2])), .section = nameIndex(sections.items,
             row[3]), .material = nameIndex(materials.items, row[4]), .group = row[5] });
    }
    for (try csv(io, "supports")) |text| {
        const row = split(text, ',');
        append(Support, &supports, .{ .node = nodeIndex(nodes.items, number(row[0])), .fixed = .{ number(row[1]) != 0,
             number(row[2]) != 0 }, .prescribed = .{ decimal(row[3]), decimal(row[4]) } });
    }
    var loads: std.ArrayList(Load) = .empty;
    var case_name: []const u8 = "";
    for (try readLines(io, "input/loads.txt")) |text| {
        const row = words(text);
        if (eq(row[0], "LOADCASE")) {
            case_name = row[1];
            loads = .empty;
        } else if (eq(row[0], "END")) append(LoadCase, &cases, .{ .name = case_name, .lines = loads.items }) else if (eq(row[0],
             "COMBINATION")) {
            var terms: std.ArrayList(Term) = .empty;
            var i: usize = 2;
            while (i < row.len) : (i += 2) append(Term, &terms, .{ .index = nameIndex(cases.items,
                 row[i]), .factor = decimal(row[i + 1]) });
            append(Combination, &combinations, .{ .name = row[1], .terms = terms.items });
        } else if (eq(row[0], "FORCE")) append(Load, &loads, .{ .kind = .force, .index = nodeIndex(nodes.items,
             number(row[1])), .x = decimal(row[2]), .y = decimal(row[3]) }) else if (eq(row[0],
             "TEMPERATURE")) append(Load, &loads, .{ .kind = .temperature, .index = memberIndex(members.items,
             number(row[1])), .x = decimal(row[2]) }) else append(Load, &loads, .{ .kind = if (eq(row[0],
             "SELFWEIGHT")) .selfweight else .settlement });
    }
    var settings: Settings = .{};
    var influence: std.ArrayList(usize) = .empty;
    var drawings: std.ArrayList(Drawing) = .empty;
    for (try readLines(io, "input/params.txt")) |text| {
        const row = words(text);
        if (eq(row[0], "deck")) {
            const deck = alloc(usize, row.len - 1);
            for (row[1..], deck) |id, *node| node.* = nodeIndex(nodes.items, number(id));
            settings.deck = deck;
        } else if (eq(row[0], "influence")) append(usize, &influence, memberIndex(members.items,
             number(row[1]))) else if (eq(row[0], "vehicle")) {
            settings.vehicle_step = number(row[1]);
            const axles = alloc(Axle, (row.len - 2) / 2);
            for (axles, 0..) |*axle, i| axle.* = .{ .offset = number(row[2 + 2 * i]), .load = decimal(row[3 + 2 * i]) };
            settings.axles = axles;
        } else if (eq(row[0], "rating")) {
            settings.rating = row[1];
            settings.dead_factor = decimal(row[2]);
            settings.vehicle_factor = decimal(row[3]);
        } else if (eq(row[0], "slenderness")) {
            settings.compression_limit = decimal(row[1]);
            settings.tension_limit = decimal(row[2]);
        } else if (eq(row[0], "deflection")) {
            settings.deflection = row[1];
            settings.deflection_ratio = number(row[2]);
        } else if (eq(row[0], "vibration")) {
            settings.vibration = row[1];
            settings.modes = u(number(row[2]));
            settings.iterations = u(number(row[3]));
        } else if (eq(row[0], "removal")) settings.removal = row[1] else if (eq(row[0], "drawing")) append(Drawing,
             &drawings, .{ .name = row[1], .magnification = number(row[2]), .horizontal = number(row[3]),
             .vertical = number(row[4]) }) else {
            settings.map_horizontal = number(row[1]);
            settings.map_vertical = number(row[2]);
        }
    }
    settings.influence = influence.items;
    settings.drawings = drawings.items;
    return .{ .nodes = nodes.items, .members = members.items, .sections = sections.items, .materials = materials.items,
         .supports = supports.items, .cases = cases.items, .combinations = combinations.items,
         .settings = settings };
}
