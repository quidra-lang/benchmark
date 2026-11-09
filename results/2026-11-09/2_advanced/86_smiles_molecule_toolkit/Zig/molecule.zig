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

pub const Names = []const []const u8;
pub fn join(values: Names, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}

pub fn zero(comptime T: type, count: usize, value: T) []T {
    const out = alloc(T, count);
    @memset(out, value);
    return out;
}
pub fn indexOf(items: anytype, name: []const u8) usize {
    for (items, 0..) |item, i| if (eq(item.name, name)) return i;
    unreachable;
}

pub const Record = struct { number: usize, line: []const u8 };
pub fn dataLines(io: std.Io, path: []const u8) ![]const Record {
    var out: std.ArrayList(Record) = .empty;
    for (try readLines(io, path), 1..) |line, index| if (line.len > 0 and line[0] != '#') append(Record,
         &out, .{ .number = index, .line = line });
    return out.items;
}
pub const Element = struct { symbol: []const u8, number: i64, weight: i64, valences: []const i64 };
pub fn readElements(io: std.Io) ![]const Element {
    var elements: std.ArrayList(Element) = .empty;
    for (try dataLines(io, "input/elements.txt")) |record| {
        const f = words(record.line);
        const values = split(f[3], ',');
        const valences = alloc(i64, values.len);
        for (values, valences) |value, *v| v.* = number(value);
        append(Element, &elements, .{ .symbol = f[0], .number = number(f[1]), .weight = number(f[2]),
             .valences = valences });
    }
    return elements.items;
}
pub fn findElement(elements: []const Element, symbol: []const u8) ?usize {
    for (elements, 0..) |element, index| if (eq(element.symbol, symbol)) return index;
    return null;
}
pub const organic = [_][]const u8{ "B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I" };
pub fn isOrganic(symbol: []const u8) bool {
    for (organic) |value| if (eq(symbol, value)) return true;
    return false;
}
pub fn aromaticElement(symbol: []const u8) bool {
    return symbol.len == 1 and std.mem.indexOfScalar(u8, "BCNOPS", symbol[0]) != null;
}
pub const AnalysisError = struct { reason: []const u8, column: usize };
pub const Choice = struct { element: usize, aromatic: bool };
pub const Atom = struct { element: usize = 0, aromatic: bool = false, mass: i64 = 0, charge: i64 = 0,
     hydrogens: i64 = 0, bracket: bool = false, column: usize = 0, choices: ?[]const Choice = null,
     aromatic_match: ?bool = null };
pub const Bond = struct { first: usize, second: usize, symbol: u8 = 0, kind: u8 = 0, multiplicity: i64 = 0,
     ring: bool = false };
pub const Neighbor = struct { atom: usize, bond: usize };
pub const Ring = []const usize;
pub fn atomBit(index: usize) u512 {
    return @as(u512, 1) << @intCast(index);
}
pub const Molecule = struct {
    elements: []const Element,
    atoms: std.ArrayList(Atom) = .empty,
    bonds: std.ArrayList(Bond) = .empty,
    neighbors: std.ArrayList(std.ArrayList(Neighbor)) = .empty,
    ordered: []const usize = &.{},
    rings: []const Ring = &.{},
    ring_atoms: u512 = 0,
    name: []const u8 = "",
    pub fn addAtom(self: *Molecule, atom: Atom) usize {
        const index = self.atoms.items.len;
        append(Atom, &self.atoms, atom);
        append(std.ArrayList(Neighbor), &self.neighbors, .empty);
        return index;
    }
    pub fn addBond(self: *Molecule, first: usize, second: usize, symbol: u8) usize {
        const index = self.bonds.items.len;
        append(Bond, &self.bonds, .{ .first = @min(first, second), .second = @max(first, second), .symbol = symbol });
        append(Neighbor, &self.neighbors.items[first], .{ .atom = second, .bond = index });
        append(Neighbor, &self.neighbors.items[second], .{ .atom = first, .bond = index });
        return index;
    }
    pub fn bondBetween(self: *const Molecule, first: usize, second: usize) ?usize {
        for (self.neighbors.items[first].items) |neighbor| if (neighbor.atom == second) return neighbor.bond;
        return null;
    }
    pub fn degree(self: *const Molecule, index: usize) usize {
        return self.neighbors.items[index].items.len;
    }
    pub fn baseTotal(self: *const Molecule, index: usize) i64 {
        var result: i64 = 0;
        const base = [5]i64{ 0, 1, 2, 3, 1 };
        for (self.neighbors.items[index].items) |neighbor| result += base[self.bonds.items[neighbor.bond].kind];
        return result;
    }
    pub fn bondTotal(self: *const Molecule, index: usize) i64 {
        var result: i64 = 0;
        for (self.neighbors.items[index].items) |neighbor| result += self.bonds.items[neighbor.bond].multiplicity;
        return result;
    }
    pub fn finalize(self: *Molecule) void {
        for (self.neighbors.items) |*list| std.mem.sort(Neighbor, list.items, {}, struct {
            fn less(_: void, a: Neighbor, b: Neighbor) bool {
                return a.atom < b.atom;
            }
        }.less);
        const ordered = alloc(usize, self.bonds.items.len);
        for (ordered, 0..) |*index, j| index.* = j;
        std.mem.sort(usize, ordered, self.bonds.items, struct {
            fn less(bonds: []Bond, a: usize, b: usize) bool {
                return if (bonds[a].first == bonds[b].first) bonds[a].second < bonds[b].second else bonds[a].first < bonds[b].first;
            }
        }.less);
        self.ordered = ordered;
    }
};
pub const ParsedAtom = struct { atom: Atom = .{}, end: usize = 0, failure: ?AnalysisError = null };
pub fn needsPi(molecule: *const Molecule, index: usize, hydrogens: ?i64) bool {
    const atom = molecule.atoms.items[index];
    const occupied = molecule.baseTotal(index) + (hydrogens orelse atom.hydrogens);
    return atom.aromatic and molecule.elements[atom.element].valences[0] + atom.charge >= occupied + 1;
}
pub fn organicHydrogens(element: Element, total: i64) ?i64 {
    for (element.valences) |valence| if (valence >= total) return valence - total;
    return null;
}
