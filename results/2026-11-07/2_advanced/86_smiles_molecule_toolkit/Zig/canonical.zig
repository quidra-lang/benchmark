const std = @import("std");
const m = @import("molecule.zig");
const Ranked = struct { values: []usize, count: usize };
fn dense(comptime T: type, values: []const T, comptime less_value: fn (T, T) bool) Ranked {
    const order = m.alloc(usize, values.len);
    for (order, 0..) |*index, i| index.* = i;
    std.mem.sort(usize, order, values, struct {
        fn less(context: []const T, a: usize, b: usize) bool {
            return less_value(context[a], context[b]);
        }
    }.less);
    const ranks = m.alloc(usize, values.len);
    var count: usize = 0;
    var previous: ?usize = null;
    for (order) |index| {
        if (previous == null or less_value(values[previous.?], values[index]) or less_value(values[index],
             values[previous.?])) count += 1;
        ranks[index] = count;
        previous = index;
    }
    return .{ .values = ranks, .count = count };
}
fn invariantLess(a: [6]i64, b: [6]i64) bool {
    for (a, b) |x, y| if (x != y) return x < y;
    return false;
}
const Pair = struct { rank: usize, kind: u8 };
fn pairLess(_: void, a: Pair, b: Pair) bool {
    return if (a.rank == b.rank) a.kind < b.kind else a.rank < b.rank;
}
const Neighborhood = struct { rank: usize, pairs: [7]Pair = undefined, count: usize = 0 };
fn neighborhoodLess(a: Neighborhood, b: Neighborhood) bool {
    if (a.rank != b.rank) return a.rank < b.rank;
    for (a.pairs[0..@min(a.count, b.count)], b.pairs[0..@min(a.count, b.count)]) |x, y| {
        if (pairLess({}, x, y)) return true;
        if (pairLess({}, y, x)) return false;
    }
    return a.count < b.count;
}
fn scalarLess(a: usize, b: usize) bool {
    return a < b;
}
fn refine(molecule: *const m.Molecule, initial: Ranked) Ranked {
    var ranks = initial;
    while (true) {
        const values = m.alloc(Neighborhood, molecule.atoms.items.len);
        for (values, 0..) |*value, id| {
            value.* = .{ .rank = ranks.values[id] };
            for (molecule.neighbors.items[id].items) |neighbor| {
                value.pairs[value.count] = .{ .rank = ranks.values[neighbor.atom], .kind = molecule.bonds.items[neighbor.bond].kind };
                value.count += 1;
            }
            std.mem.sort(Pair, value.pairs[0..value.count], {}, pairLess);
        }
        const next = dense(Neighborhood, values, neighborhoodLess);
        if (next.count == ranks.count) return next;
        ranks = next;
    }
}
pub const Ranks = struct { values: []const usize, classes: usize };
pub fn canonicalRanks(molecule: *const m.Molecule) Ranks {
    const invariants = m.alloc([6]i64, molecule.atoms.items.len);
    for (molecule.atoms.items, invariants, 0..) |atom, *value, id| value.* = .{ m.n(molecule.degree(id)),
         molecule.elements[atom.element].number, atom.mass, atom.charge, atom.hydrogens, @intFromBool(atom.aromatic) };
    var ranks = refine(molecule, dense([6]i64, invariants, invariantLess));
    const classes = ranks.count;
    while (ranks.count != molecule.atoms.items.len) {
        var counts: [81]usize = @splat(0);
        for (ranks.values) |rank| counts[rank] += 1;
        var tied: usize = 1;
        while (counts[tied] < 2) tied += 1;
        var first: usize = 0;
        while (ranks.values[first] != tied) first += 1;
        const values = m.alloc(usize, ranks.values.len);
        for (ranks.values, values, 0..) |rank, *value, id| value.* = 2 * rank - @intFromBool(id == first);
        ranks = refine(molecule, dense(usize, values, scalarLess));
    }
    return .{ .values = ranks.values, .classes = classes };
}
pub fn atomNotation(molecule: *const m.Molecule, id: usize) []const u8 {
    const atom = molecule.atoms.items[id];
    const element = molecule.elements[atom.element];
    var symbol = element.symbol;
    var ordinary = m.isOrganic(symbol) and (!atom.aromatic or m.aromaticElement(symbol)) and atom.mass == 0 and atom.charge == 0;
    if (atom.aromatic) {
        ordinary = ordinary and m.needsPi(molecule, id, null) == m.needsPi(molecule, id, 0);
        const lower = m.dupe(u8, symbol);
        for (lower) |*character| character.* = std.ascii.toLower(character.*);
        symbol = lower;
    }
    const hydrogens = m.organicHydrogens(element, molecule.bondTotal(id));
    if (ordinary and hydrogens != null and hydrogens.? == atom.hydrogens) return symbol;
    var text: m.Text = .{};
    text.add("[", .{});
    if (atom.mass != 0) text.add("{d}", .{atom.mass});
    text.add("{s}", .{symbol});
    if (atom.hydrogens > 0) {
        text.add("H", .{});
        if (atom.hydrogens != 1) text.add("{d}", .{atom.hydrogens});
    }
    if (atom.charge != 0) {
        text.add("{s}", .{if (atom.charge > 0) "+" else "-"});
        if (@abs(atom.charge) != 1) text.add("{d}", .{@abs(atom.charge)});
    }
    text.add("]", .{});
    return text.value();
}
pub fn bondSymbol(molecule: *const m.Molecule, bond: m.Bond) []const u8 {
    const in_ring = bond.ring and molecule.atoms.items[bond.first].aromatic and molecule.atoms.items[bond.second].aromatic;
    return switch (bond.kind) {
        1 => if (in_ring) "-" else "",
        2 => "=",
        3 => "#",
        else => if (in_ring) "" else ":",
    };
}
const Writer = struct {
    molecule: *const m.Molecule,
    ranks: []const usize,
    visits: []usize,
    children: []std.ArrayList(m.Neighbor),
    closures: []bool,
    assignments: []usize,
    occupied: []bool,
    count: usize = 0,
    fn visit(self: *Writer, atom: usize, incoming: ?usize) void {
        self.count += 1;
        self.visits[atom] = self.count;
        var neighbors: [7]m.Neighbor = undefined;
        const list = self.molecule.neighbors.items[atom].items;
        @memcpy(neighbors[0..list.len], list);
        std.mem.sort(m.Neighbor, neighbors[0..list.len], self.ranks, struct {
            fn less(ranks: []const usize, a: m.Neighbor, b: m.Neighbor) bool {
                return ranks[a.atom] < ranks[b.atom];
            }
        }.less);
        for (neighbors[0..list.len]) |neighbor| {
            if (incoming == neighbor.bond or self.closures[neighbor.bond]) continue;
            if (self.visits[neighbor.atom] == 0) {
                m.append(m.Neighbor, &self.children[atom], neighbor);
                self.visit(neighbor.atom, neighbor.bond);
            } else self.closures[neighbor.bond] = true;
        }
    }
    fn write(self: *Writer, atom: usize) []const u8 {
        var text: m.Text = .{};
        text.add("{s}", .{atomNotation(self.molecule, atom)});
        var neighbors: [7]m.Neighbor = undefined;
        const list = self.molecule.neighbors.items[atom].items;
        @memcpy(neighbors[0..list.len], list);
        std.mem.sort(m.Neighbor, neighbors[0..list.len], self.visits, struct {
            fn less(visits: []usize, a: m.Neighbor, b: m.Neighbor) bool {
                return visits[a.atom] < visits[b.atom];
            }
        }.less);
        for (neighbors[0..list.len]) |neighbor| {
            if (!self.closures[neighbor.bond]) continue;
            var number = self.assignments[neighbor.bond];
            var symbol: []const u8 = "";
            if (number != 0) {
                self.assignments[neighbor.bond] = 0;
                self.occupied[number] = false;
            } else {
                number = 1;
                while (self.occupied[number]) number += 1;
                self.assignments[neighbor.bond] = number;
                self.occupied[number] = true;
                symbol = bondSymbol(self.molecule, self.molecule.bonds.items[neighbor.bond]);
            }
            text.add("{s}", .{symbol});
            if (number < 10) text.add("{d}", .{number}) else text.add("%{d:0>2}", .{number});
        }
        const children = self.children[atom].items;
        for (children, 0..) |child, index| {
            const branch = index + 1 < children.len;
            if (branch) text.add("(", .{});
            text.add("{s}{s}", .{ bondSymbol(self.molecule, self.molecule.bonds.items[child.bond]),
                 self.write(child.atom) });
            if (branch) text.add(")", .{});
        }
        return text.value();
    }
};
pub const Canonical = struct { smiles: []const u8, classes: usize };
pub fn canonicalize(molecule: *const m.Molecule) Canonical {
    const ranks = canonicalRanks(molecule);
    const count = molecule.atoms.items.len;
    const bond_count = molecule.bonds.items.len;
    var writer: Writer = .{ .molecule = molecule, .ranks = ranks.values, .visits = m.zero(usize,
         count, 0), .children = m.zero(std.ArrayList(m.Neighbor), count, .empty), .closures = m.zero(bool,
         bond_count, false), .assignments = m.zero(usize, bond_count, 0), .occupied = m.zero(bool,
         bond_count + 2, false) };
    const root = std.mem.indexOfScalar(usize, ranks.values, 1).?;
    writer.visit(root, null);
    return .{ .smiles = writer.write(root), .classes = ranks.classes };
}
