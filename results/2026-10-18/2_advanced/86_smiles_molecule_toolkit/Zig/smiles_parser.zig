const std = @import("std");
const m = @import("molecule.zig");
pub const Organic = struct { element: usize, aromatic: bool, end: usize };
pub fn readOrganic(text: []const u8, position: usize, elements: []const m.Element) ?Organic {
    if (position >= text.len) return null;
    if (position + 1 < text.len and (m.eq(text[position .. position + 2], "Cl") or m.eq(text[position .. position + 2],
         "Br"))) return .{ .element = m.findElement(elements, text[position .. position + 2]).?,
         .aromatic = false, .end = position + 2 };
    const character = text[position];
    if (std.mem.indexOfScalar(u8, "BCNOPSFI", character) != null) return .{ .element = m.findElement(elements,
         text[position .. position + 1]).?, .aromatic = false, .end = position + 1 };
    if (std.mem.indexOfScalar(u8, "bcnops", character) != null) {
        const symbol = [1]u8{std.ascii.toUpper(character)};
        return .{ .element = m.findElement(elements, &symbol).?, .aromatic = true, .end = position + 1 };
    }
    return null;
}
fn digit(character: u8) bool {
    return character >= '0' and character <= '9';
}
fn failure(reason: []const u8, column: usize) m.ParsedAtom {
    return .{ .failure = .{ .reason = reason, .column = column } };
}
pub fn readAtom(text: []const u8, start: usize, elements: []const m.Element) m.ParsedAtom {
    if (text[start] != '[') {
        const organic = readOrganic(text, start, elements) orelse return failure("unexpected character", start + 1);
        return .{ .atom = .{ .element = organic.element, .aromatic = organic.aromatic, .column = start + 1 },
             .end = organic.end };
    }
    const offset = std.mem.indexOfScalar(u8, text[start + 1 ..], ']') orelse return failure("unclosed bracket",
         start + 1);
    const end = start + 1 + offset;
    const content = text[start + 1 .. end];
    var position: usize = 0;
    while (position < content.len and digit(content[position])) : (position += 1) {}
    if (position >= 4 or (position > 0 and content[0] == '0') or position == content.len) return failure("bad bracket atom",
         start + 1);
    var atom: m.Atom = .{ .mass = if (position > 0) m.number(content[0..position]) else 0,
         .bracket = true, .column = start + 1 };
    const character = content[position];
    if (std.mem.indexOfScalar(u8, "bcnops", character) != null) {
        const symbol = [1]u8{std.ascii.toUpper(character)};
        atom.element = m.findElement(elements, &symbol).?;
        atom.aromatic = true;
        position += 1;
    } else if (character >= 'A' and character <= 'Z') {
        const pair = if (position + 1 < content.len and content[position + 1] >= 'a' and content[position + 1] <= 'z') m.findElement(elements,
             content[position .. position + 2]) else null;
        if (pair) |element| {
            atom.element = element;
            position += 2;
        } else if (m.findElement(elements, content[position .. position + 1])) |element| {
            atom.element = element;
            position += 1;
        } else return failure("unknown element", start + 1);
    } else return failure("bad bracket atom", start + 1);
    if (position + 1 < content.len and m.eq(content[position .. position + 2], "@@")) position += 2 else if (position < content.len and content[position] == '@') position += 1;
    if (position < content.len and content[position] == 'H') {
        atom.hydrogens = 1;
        position += 1;
        if (position < content.len and digit(content[position])) {
            atom.hydrogens = content[position] - '0';
            position += 1;
        }
    }
    if (position < content.len and (content[position] == '+' or content[position] == '-')) {
        atom.charge = if (content[position] == '+') 1 else -1;
        position += 1;
        if (position < content.len and content[position] >= '1' and content[position] <= '9') {
            atom.charge *= content[position] - '0';
            position += 1;
        }
    }
    if (position != content.len) return failure("bad bracket atom", start + 1);
    return .{ .atom = atom, .end = end + 1 };
}
fn symbolKind(character: u8, pattern: bool) ?u8 {
    return switch (character) {
        '-' => 1,
        '=' => 2,
        '#' => 3,
        ':' => 4,
        '~' => if (pattern) 5 else null,
        '/', '\\' => if (pattern) null else 1,
        else => null,
    };
}
const Pending = struct { kind: u8, column: usize };
const Branch = struct { atom: usize, column: usize };
const OpenRing = struct { atom: usize, kind: u8, column: usize };
pub const Result = struct { molecule: ?*m.Molecule = null, failure: ?m.AnalysisError = null };
fn reject(reason: []const u8, column: usize) Result {
    return .{ .failure = .{ .reason = reason, .column = column } };
}
pub fn parse(text: []const u8, elements: []const m.Element, comptime pattern: bool, comptime atom_reader: anytype) Result {
    const molecule = m.create(m.Molecule, .{ .elements = elements });
    var current: ?usize = null;
    var pending: ?Pending = null;
    var branches: std.ArrayList(Branch) = .empty;
    var open: [100]?OpenRing = @splat(null);
    var position: usize = 0;
    while (position < text.len) {
        const character = text[position];
        const column = position + 1;
        if (symbolKind(character, pattern)) |kind| {
            if (current == null or pending != null) return reject("misplaced bond", column);
            pending = .{ .kind = kind, .column = column };
            position += 1;
        } else if (character == '(') {
            if (current == null or pending != null or (position > 0 and text[position - 1] == '(')) return reject("misplaced branch",
                 column);
            m.append(Branch, &branches, .{ .atom = current.?, .column = column });
            position += 1;
        } else if (character == ')') {
            if (branches.items.len == 0) return reject("unmatched parenthesis", column);
            if (pending) |bond| return reject("dangling bond", bond.column);
            if (position > 0 and text[position - 1] == '(') return reject("empty branch", column);
            current = branches.pop().?.atom;
            position += 1;
        } else if (digit(character) or character == '%') {
            if (current == null) return reject("misplaced ring closure", column);
            var ring: usize = undefined;
            if (character == '%') {
                if (position + 2 >= text.len or !digit(text[position + 1]) or !digit(text[position + 2])) return reject("bad ring number",
                     column);
                ring = @as(usize, text[position + 1] - '0') * 10 + text[position + 2] - '0';
                position += 3;
            } else {
                ring = character - '0';
                position += 1;
            }
            const kind = if (pending) |bond| bond.kind else 0;
            pending = null;
            if (open[ring]) |initial| {
                if (initial.atom == current.?) return reject("self bond", column);
                if (initial.kind != 0 and kind != 0 and initial.kind != kind) return reject("ring bond mismatch",
                     column);
                if (molecule.bondBetween(initial.atom, current.?) != null) return reject("duplicate bond", column);
                _ = molecule.addBond(initial.atom, current.?, if (kind != 0) kind else initial.kind);
                open[ring] = null;
            } else open[ring] = .{ .atom = current.?, .kind = kind, .column = column };
        } else {
            const parsed = atom_reader(text, position, elements);
            if (parsed.failure) |reason| return .{ .failure = reason };
            const atom = molecule.addAtom(parsed.atom);
            if (current) |previous| _ = molecule.addBond(previous, atom, if (pending) |bond| bond.kind else 0);
            current = atom;
            pending = null;
            position = parsed.end;
        }
    }
    if (pending) |bond| return reject("dangling bond", bond.column);
    if (branches.items.len > 0) return reject("unmatched parenthesis", branches.items[0].column);
    var earliest: ?usize = null;
    for (open) |ring| if (ring) |value| {
        if (earliest == null or value.column < earliest.?) earliest = value.column;
    };
    if (earliest) |column| return reject("unclosed ring", column);
    molecule.finalize();
    return .{ .molecule = molecule };
}
