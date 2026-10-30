const std = @import("std");
const m = @import("molecule.zig");
const parser = @import("smiles_parser.zig");
pub fn readPatternAtom(text: []const u8, position: usize, elements: []const m.Element) m.ParsedAtom {
    const character = text[position];
    if (character == '*' or character == 'A' or character == 'a') return .{ .atom = .{ .aromatic_match = if (character == '*') null else character == 'a' },
         .end = position + 1 };
    if (character == '[') {
        const offset = std.mem.indexOfScalar(u8, text[position + 1 ..], ']') orelse return .{ .failure = .{ .reason = "unclosed bracket",
             .column = position + 1 } };
        const end = position + 1 + offset;
        var choices: std.ArrayList(m.Choice) = .empty;
        for (m.split(text[position + 1 .. end], ',')) |item| {
            const organic = parser.readOrganic(item, 0, elements) orelse return .{ .failure = .{ .reason = "bad bracket atom",
                 .column = position + 1 } };
            if (organic.end != item.len) return .{ .failure = .{ .reason = "bad bracket atom",
                 .column = position + 1 } };
            m.append(m.Choice, &choices, .{ .element = organic.element, .aromatic = organic.aromatic });
        }
        return .{ .atom = .{ .choices = choices.items }, .end = end + 1 };
    }
    const organic = parser.readOrganic(text, position, elements) orelse return .{ .failure = .{ .reason = "unexpected character",
         .column = position + 1 } };
    const choices = m.alloc(m.Choice, 1);
    choices[0] = .{ .element = organic.element, .aromatic = organic.aromatic };
    return .{ .atom = .{ .choices = choices }, .end = organic.end };
}
pub fn moleculePattern(molecule: *const m.Molecule) *m.Molecule {
    const pattern = m.create(m.Molecule, .{ .elements = molecule.elements });
    for (molecule.atoms.items) |atom| {
        const choices = m.alloc(m.Choice, 1);
        choices[0] = .{ .element = atom.element, .aromatic = atom.aromatic };
        _ = pattern.addAtom(.{ .choices = choices });
    }
    for (molecule.ordered) |index| {
        const bond = molecule.bonds.items[index];
        _ = pattern.addBond(bond.first, bond.second, bond.kind);
    }
    pattern.finalize();
    return pattern;
}
fn atomMatches(pattern: m.Atom, atom: m.Atom) bool {
    if (pattern.choices) |choices| {
        for (choices) |choice| if (choice.element == atom.element and choice.aromatic == atom.aromatic) return true;
        return false;
    }
    return pattern.aromatic_match == null or pattern.aromatic_match.? == atom.aromatic;
}
pub fn bondMatches(pattern: m.Bond, target: m.Bond) bool {
    return if (pattern.symbol == 0) target.kind == 1 or target.kind == 4 else if (pattern.symbol == 5) true else pattern.symbol == target.kind;
}
pub const Embeddings = struct { count: i64 = 0, unique: usize = 0, mapping: []const usize = &.{} };
const Matcher = struct {
    pattern: *const m.Molecule,
    molecule: *const m.Molecule,
    candidates: []const bool,
    mapping: []usize,
    unique: std.AutoHashMapUnmanaged(u128, void) = .empty,
    result: Embeddings = .{},
    allocator: std.mem.Allocator,
    fn assign(self: *Matcher, index: usize, used: u128) void {
        if (index == self.pattern.atoms.items.len) {
            self.result.count += 1;
            self.unique.put(self.allocator, used, {}) catch @panic("allocation failed");
            if (self.result.mapping.len == 0) self.result.mapping = m.dupe(usize, self.mapping);
            return;
        }
        const count = self.molecule.atoms.items.len;
        for (0..count) |atom| {
            const bit = @as(u128, 1) << @intCast(atom);
            if (used & bit != 0 or !self.candidates[index * count + atom]) continue;
            var valid = true;
            for (self.pattern.neighbors.items[index].items) |neighbor| {
                if (neighbor.atom >= index) continue;
                const target = self.molecule.bondBetween(atom, self.mapping[neighbor.atom]) orelse {
                    valid = false;
                    break;
                };
                if (!bondMatches(self.pattern.bonds.items[neighbor.bond], self.molecule.bonds.items[target])) {
                    valid = false;
                    break;
                }
            }
            if (valid) {
                self.mapping[index] = atom;
                self.assign(index + 1, used | bit);
            }
        }
    }
};
pub fn embeddings(pattern: *const m.Molecule, molecule: *const m.Molecule, work_allocator: std.mem.Allocator) Embeddings {
    if (pattern.atoms.items.len > molecule.atoms.items.len) return .{};
    var arena: std.heap.ArenaAllocator = .init(work_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const count = molecule.atoms.items.len;
    const candidates = allocator.alloc(bool, pattern.atoms.items.len * count) catch @panic("allocation failed");
    for (pattern.atoms.items, 0..) |pattern_atom, index| for (molecule.atoms.items, 0..) |atom, id| {
        candidates[index * count + id] = atomMatches(pattern_atom, atom) and molecule.degree(id) >= pattern.degree(index);
    };
    var matcher: Matcher = .{ .pattern = pattern, .molecule = molecule, .candidates = candidates,
         .mapping = allocator.alloc(usize, pattern.atoms.items.len) catch @panic("allocation failed"),
         .allocator = allocator };
    matcher.assign(0, 0);
    matcher.result.unique = matcher.unique.count();
    return matcher.result;
}
pub const Fingerprint = struct {
    bits: [16]u64 = @splat(0),
    paths: i64 = 0,
    pub fn count(self: Fingerprint) usize {
        var total: usize = 0;
        for (self.bits) |word| total += @popCount(word);
        return total;
    }
};
const Fingerprinter = struct {
    molecule: *const m.Molecule,
    codes: []const i64,
    result: Fingerprint = .{},
    fn extend(self: *Fingerprinter, atom: usize, depth: usize, value: i64, used: u128) void {
        self.result.paths += 1;
        const bit = m.u(@mod(value, 1024));
        self.result.bits[bit / 64] |= @as(u64, 1) << @intCast(bit % 64);
        if (depth == 5) return;
        for (self.molecule.neighbors.items[atom].items) |neighbor| {
            const mask = @as(u128, 1) << @intCast(neighbor.atom);
            if (used & mask != 0) continue;
            var next = @mod(value * 31 + self.molecule.bonds.items[neighbor.bond].kind, 1000003);
            next = @mod(next * 31 + self.codes[neighbor.atom], 1000003);
            self.extend(neighbor.atom, depth + 1, next, used | mask);
        }
    }
};
pub fn fingerprint(molecule: *const m.Molecule) Fingerprint {
    const codes = m.alloc(i64, molecule.atoms.items.len);
    for (molecule.atoms.items, codes, 0..) |atom, *code, index| code.* = 16 * molecule.elements[atom.element].number + 8 * @as(i64,
         @intFromBool(atom.aromatic)) + m.n(molecule.degree(index));
    var printer: Fingerprinter = .{ .molecule = molecule, .codes = codes };
    for (codes, 0..) |code, index| printer.extend(index, 0, code, @as(u128, 1) << @intCast(index));
    return printer.result;
}
pub const Similarity = struct {
    common: i64,
    union_count: i64,
    pub fn less(self: Similarity, other: Similarity) bool {
        return self.common * other.union_count < other.common * self.union_count;
    }
    pub fn text(self: Similarity) []const u8 {
        var a = self.common;
        var b = self.union_count;
        while (b != 0) {
            const next = @mod(a, b);
            a = b;
            b = next;
        }
        return m.fmt("{d}/{d}", .{ @divTrunc(self.common, a), @divTrunc(self.union_count, a) });
    }
};
pub fn tanimoto(first: Fingerprint, second: Fingerprint) Similarity {
    var common: i64 = 0;
    var union_count: i64 = 0;
    for (first.bits, second.bits) |a, b| {
        common += @popCount(a & b);
        union_count += @popCount(a | b);
    }
    return .{ .common = common, .union_count = union_count };
}
