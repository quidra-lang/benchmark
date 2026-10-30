const std = @import("std");
const m = @import("molecule.zig");
const Candidate = struct { sequence: []const usize, bonds: u512, order: usize };
fn canonicalRing(sequence: []const usize) []const usize {
    var first: usize = 0;
    for (sequence, 0..) |atom, index| if (atom < sequence[first]) {
        first = index;
    };
    const out = m.alloc(usize, sequence.len);
    const forward = sequence[(first + 1) % sequence.len] < sequence[(first + sequence.len - 1) % sequence.len];
    for (out, 0..) |*atom, index| atom.* = sequence[(first + (if (forward) index else sequence.len - index)) % sequence.len];
    return out;
}
fn ringLess(_: void, a: m.Ring, b: m.Ring) bool {
    if (a.len != b.len) return a.len < b.len;
    for (a, b) |first, second| if (first != second) return first < second;
    return false;
}
pub fn findRings(molecule: *m.Molecule) void {
    const count = molecule.atoms.items.len;
    var candidates: std.ArrayList(Candidate) = .empty;
    var seen: std.AutoHashMapUnmanaged(u512, void) = .empty;
    for (0..count) |root| {
        const parents = m.zero(?usize, count, null);
        const visited = m.zero(bool, count, false);
        const queue = m.alloc(usize, count);
        visited[root] = true;
        queue[0] = root;
        var read: usize = 0;
        var size: usize = 1;
        while (read < size) : (read += 1) {
            const atom = queue[read];
            for (molecule.neighbors.items[atom].items) |neighbor| if (!visited[neighbor.atom]) {
                visited[neighbor.atom] = true;
                parents[neighbor.atom] = atom;
                queue[size] = neighbor.atom;
                size += 1;
            };
        }
        const paths = m.alloc([]const usize, count);
        const masks = m.alloc(u512, count);
        for (0..count) |atom| {
            var path: std.ArrayList(usize) = .empty;
            var current: ?usize = atom;
            var mask: u512 = 0;
            while (current) |index| {
                m.append(usize, &path, index);
                mask |= m.atomBit(index);
                current = parents[index];
            }
            paths[atom] = path.items;
            masks[atom] = mask;
        }
        for (molecule.ordered) |index| {
            const bond = molecule.bonds.items[index];
            const first = bond.first;
            const second = bond.second;
            if (parents[first] == second or parents[second] == first or masks[first] & masks[second] != m.atomBit(root)) continue;
            const sequence = m.alloc(usize, paths[first].len + paths[second].len - 1);
            for (paths[first], 0..) |atom, j| sequence[paths[first].len - 1 - j] = atom;
            @memcpy(sequence[paths[first].len..], paths[second][0 .. paths[second].len - 1]);
            var bonds: u512 = 0;
            for (sequence, 0..) |atom, j| bonds |= m.atomBit(molecule.bondBetween(atom, sequence[(j + 1) % sequence.len]).?);
            if (seen.contains(bonds)) continue;
            seen.put(m.allocator, bonds, {}) catch @panic("allocation failed");
            m.append(Candidate, &candidates, .{ .sequence = sequence, .bonds = bonds, .order = candidates.items.len });
        }
    }
    std.mem.sort(Candidate, candidates.items, {}, struct {
        fn less(_: void, a: Candidate, b: Candidate) bool {
            return if (a.sequence.len == b.sequence.len) a.order < b.order else a.sequence.len < b.sequence.len;
        }
    }.less);
    var basis: [512]?u512 = @splat(null);
    var rings: std.ArrayList(m.Ring) = .empty;
    for (candidates.items) |candidate| {
        var reduced = candidate.bonds;
        while (reduced != 0) {
            const pivot: usize = 511 - @as(usize, @clz(reduced));
            if (basis[pivot]) |value| reduced ^= value else {
                basis[pivot] = reduced;
                m.append(m.Ring, &rings, canonicalRing(candidate.sequence));
                break;
            }
        }
    }
    std.mem.sort(m.Ring, rings.items, {}, ringLess);
    molecule.rings = rings.items;
    for (molecule.rings) |ring| for (ring, 0..) |atom, index| {
        molecule.ring_atoms |= m.atomBit(atom);
        molecule.bonds.items[molecule.bondBetween(atom, ring[(index + 1) % ring.len]).?].ring = true;
    };
}
fn matchSystem(molecule: *const m.Molecule, unpaired: u512, selected: *u512) bool {
    if (unpaired == 0) return true;
    const first: usize = @ctz(unpaired);
    const rest = unpaired & ~m.atomBit(first);
    for (molecule.neighbors.items[first].items) |neighbor| {
        if (rest & m.atomBit(neighbor.atom) == 0 or molecule.bonds.items[neighbor.bond].kind != 4) continue;
        const bit = m.atomBit(neighbor.bond);
        selected.* |= bit;
        if (matchSystem(molecule, rest & ~m.atomBit(neighbor.atom), selected)) return true;
        selected.* &= ~bit;
    }
    return false;
}
pub fn kekulize(molecule: *m.Molecule, needing: u512) ?m.AnalysisError {
    var remaining = needing;
    var selected: u512 = 0;
    while (remaining != 0) {
        const first: usize = @ctz(remaining);
        var system = m.atomBit(first);
        remaining &= ~system;
        var frontier = system;
        while (frontier != 0) {
            const atom: usize = @ctz(frontier);
            frontier &= ~m.atomBit(atom);
            for (molecule.neighbors.items[atom].items) |neighbor| {
                const bit = m.atomBit(neighbor.atom);
                if (remaining & bit != 0 and molecule.bonds.items[neighbor.bond].kind == 4) {
                    remaining &= ~bit;
                    system |= bit;
                    frontier |= bit;
                }
            }
        }
        if (!matchSystem(molecule, system, &selected)) return .{ .reason = "kekulization failed",
             .column = molecule.atoms.items[first].column };
    }
    for (molecule.bonds.items, 0..) |*bond, index| bond.multiplicity = if (bond.kind == 4) (if (selected & m.atomBit(index) != 0) @as(i64,
         2) else 1) else bond.kind;
    return null;
}
