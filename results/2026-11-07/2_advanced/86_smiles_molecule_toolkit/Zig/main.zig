const std = @import("std");
const m = @import("molecule.zig");
const parser = @import("smiles_parser.zig");
const ra = @import("rings_aromatic.zig");
const canon = @import("canonical.zig");
const search = @import("search.zig");
const system_kinds = [_][]const u8{ "isolated", "fused", "spiro", "bridged" };
const query_kinds = [_][]const u8{ "MATCH", "CONTAINS", "MATRIX", "NEAREST", "WITHIN", "COMPARE", "CLUSTER" };
fn validName(value: []const u8) bool {
    if (value.len < 1 or value.len > 32) return false;
    for (value) |character| if (!std.ascii.isAlphanumeric(character) and character != '_' and character != '-') return false;
    return true;
}
fn validNumber(value: []const u8, minimum: i64, maximum: i64) bool {
    if (value.len == 0 or (value.len > 1 and value[0] == '0')) return false;
    var number: i64 = 0;
    for (value) |character| {
        if (character < '0' or character > '9') return false;
        number = number * 10 + character - '0';
        if (number > maximum) return false;
    }
    return number >= minimum;
}
fn threshold(value: []const u8) ?search.Similarity {
    const parts = m.split(value, '/');
    if (parts.len != 2 or !validNumber(parts[0], 0, 99) or !validNumber(parts[1], 1, 99)) return null;
    const numerator = m.number(parts[0]);
    const denominator = m.number(parts[1]);
    return if (numerator <= denominator) .{ .common = numerator, .union_count = denominator } else null;
}
fn atomNumbers(atoms: []const usize, separator: []const u8) []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    for (atoms) |atom| m.append([]const u8, &parts, m.fmt("{d}", .{atom + 1}));
    return m.join(parts.items, separator);
}
fn analyze(molecule: *m.Molecule) ?m.AnalysisError {
    ra.findRings(molecule);
    for (molecule.bonds.items) |*bond| {
        if (bond.symbol != 0) bond.kind = bond.symbol else bond.kind = if (bond.ring and molecule.atoms.items[bond.first].aromatic and molecule.atoms.items[bond.second].aromatic) 4 else 1;
    }
    var needing: u512 = 0;
    for (0..molecule.atoms.items.len) |id| if (m.needsPi(molecule, id, null)) {
        needing |= m.atomBit(id);
    };
    if (ra.kekulize(molecule, needing)) |failure| return failure;
    for (molecule.atoms.items, 0..) |*atom, id| {
        const total = molecule.bondTotal(id);
        const element = molecule.elements[atom.element];
        if (atom.bracket) {
            if (total + atom.hydrogens > element.valences[element.valences.len - 1] + @as(i64,
                 @intCast(@abs(atom.charge)))) return .{ .reason = "bad valence", .column = atom.column };
        } else {
            atom.hydrogens = m.organicHydrogens(element, total) orelse return .{ .reason = "bad valence",
                 .column = atom.column };
        }
    }
    return null;
}
const Properties = struct { formula: []const u8, weight: i64, heavy: usize, rotatable: usize,
     donors: usize, acceptors: usize, lipinski: bool, charge: i64 };
fn molecularProperties(molecule: *const m.Molecule) Properties {
    const elements = molecule.elements;
    const counts = m.zero(i64, elements.len, 0);
    var hydrogens: i64 = 0;
    var weight: i64 = 0;
    var heavy: usize = 0;
    var charge: i64 = 0;
    for (molecule.atoms.items) |atom| {
        counts[atom.element] += 1;
        hydrogens += atom.hydrogens;
        const element = elements[atom.element];
        weight += if (atom.mass > 0) atom.mass * 1000 else element.weight;
        heavy += @intFromBool(!m.eq(element.symbol, "H"));
        charge += atom.charge;
    }
    const hydrogen = m.findElement(elements, "H").?;
    counts[hydrogen] += hydrogens;
    weight += hydrogens * elements[hydrogen].weight;
    const order = m.alloc(usize, elements.len);
    for (order, 0..) |*id, index| id.* = index;
    const carbon = m.findElement(elements, "C").?;
    const FormulaContext = struct { elements: []const m.Element, carbon_first: bool };
    std.mem.sort(usize, order, FormulaContext{ .elements = elements, .carbon_first = counts[carbon] > 0 }, struct {
        fn less(context: FormulaContext, a: usize, b: usize) bool {
            const first = context.elements[a].symbol;
            const second = context.elements[b].symbol;
            if (context.carbon_first) {
                const af: usize = if (m.eq(first, "C")) 0 else if (m.eq(first, "H")) 1 else 2;
                const bf: usize = if (m.eq(second, "C")) 0 else if (m.eq(second, "H")) 1 else 2;
                if (af != bf) return af < bf;
            }
            return std.mem.order(u8, first, second) == .lt;
        }
    }.less);
    var formula: m.Text = .{};
    for (order) |id| if (counts[id] > 0) {
        formula.add("{s}", .{elements[id].symbol});
        if (counts[id] != 1) formula.add("{d}", .{counts[id]});
    };
    const heavy_degrees = m.zero(usize, molecule.atoms.items.len, 0);
    var triple_ends: u128 = 0;
    for (molecule.atoms.items, 0..) |_, id| for (molecule.neighbors.items[id].items) |neighbor| if (!m.eq(elements[molecule.atoms.items[neighbor.atom].element].symbol,
         "H")) {
        heavy_degrees[id] += 1;
    };
    for (molecule.bonds.items) |bond| if (bond.multiplicity == 3) {
        triple_ends |= (@as(u128, 1) << @intCast(bond.first)) | (@as(u128, 1) << @intCast(bond.second));
    };
    var rotatable: usize = 0;
    for (molecule.bonds.items) |bond| if (bond.multiplicity == 1 and !bond.ring and heavy_degrees[bond.first] >= 2 and heavy_degrees[bond.second] >= 2 and triple_ends & ((@as(u128,
         1) << @intCast(bond.first)) | (@as(u128, 1) << @intCast(bond.second))) == 0) {
        rotatable += 1;
    };
    var donors: usize = 0;
    var acceptors: usize = 0;
    for (molecule.atoms.items, 0..) |atom, id| {
        const symbol = elements[atom.element].symbol;
        if (!m.eq(symbol, "N") and !m.eq(symbol, "O")) continue;
        acceptors += 1;
        var attached = atom.hydrogens;
        for (molecule.neighbors.items[id].items) |neighbor| attached += @intFromBool(m.eq(elements[molecule.atoms.items[neighbor.atom].element].symbol,
             "H"));
        donors += @intFromBool(attached > 0);
    }
    const violations = @as(usize, @intFromBool(weight > 500000)) + @as(usize, @intFromBool(donors > 5)) + @as(usize,
         @intFromBool(acceptors > 10));
    return .{ .formula = formula.value(), .weight = weight, .heavy = heavy, .rotatable = rotatable,
         .donors = donors, .acceptors = acceptors, .lipinski = violations <= 1, .charge = charge };
}
fn scaffoldMolecule(molecule: *const m.Molecule) ?*m.Molecule {
    if (molecule.rings.len == 0) return null;
    var remaining: u512 = 0;
    for (0..molecule.atoms.items.len) |id| remaining |= m.atomBit(id);
    while (true) {
        var leaf: ?usize = null;
        for (0..molecule.atoms.items.len) |id| {
            if (remaining & m.atomBit(id) == 0 or molecule.ring_atoms & m.atomBit(id) != 0) continue;
            var degree: usize = 0;
            for (molecule.neighbors.items[id].items) |neighbor| degree += @intFromBool(remaining & m.atomBit(neighbor.atom) != 0);
            if (degree == 1) {
                leaf = id;
                break;
            }
        }
        if (leaf) |id| remaining &= ~m.atomBit(id) else break;
    }
    var kept = remaining;
    for (0..molecule.atoms.items.len) |id| if (remaining & m.atomBit(id) != 0) {
        for (molecule.neighbors.items[id].items) |neighbor| if (remaining & m.atomBit(neighbor.atom) == 0 and molecule.bonds.items[neighbor.bond].kind == 2) {
            kept |= m.atomBit(neighbor.atom);
        };
    };
    const scaffold = m.create(m.Molecule, .{ .elements = molecule.elements });
    const renumber = m.zero(?usize, molecule.atoms.items.len, null);
    for (molecule.atoms.items, 0..) |original, id| if (kept & m.atomBit(id) != 0) {
        var atom = original;
        for (molecule.neighbors.items[id].items) |neighbor| if (kept & m.atomBit(neighbor.atom) == 0) {
            atom.hydrogens += molecule.bonds.items[neighbor.bond].multiplicity;
        };
        renumber[id] = scaffold.addAtom(atom);
    };
    for (molecule.ordered) |index| {
        const original = molecule.bonds.items[index];
        if (renumber[original.first] != null and renumber[original.second] != null) {
            const id = scaffold.addBond(renumber[original.first].?, renumber[original.second].?, original.symbol);
            scaffold.bonds.items[id].kind = original.kind;
            scaffold.bonds.items[id].multiplicity = original.multiplicity;
            scaffold.bonds.items[id].ring = original.ring;
        }
    }
    const rings = m.alloc(m.Ring, molecule.rings.len);
    for (molecule.rings, rings) |ring, *copy| {
        const atoms = m.alloc(usize, ring.len);
        for (ring, atoms) |atom, *id| {
            id.* = renumber[atom].?;
            scaffold.ring_atoms |= m.atomBit(id.*);
        }
        copy.* = atoms;
    }
    scaffold.rings = rings;
    scaffold.finalize();
    return scaffold;
}
const System = struct { rings: []const usize, atoms: usize, kind: usize };
fn ringSystems(molecule: *const m.Molecule) []const System {
    const count = molecule.rings.len;
    const sets = m.zero(u128, count, 0);
    for (molecule.rings, sets) |ring, *set| for (ring) |atom| {
        set.* |= @as(u128, 1) << @intCast(atom);
    };
    const connections = m.zero(u512, count, 0);
    const relations = m.zero(u8, count * count, 0);
    for (0..count) |first| for (first + 1..count) |second| {
        const shared = sets[first] & sets[second];
        const size = @popCount(shared);
        if (size == 0) continue;
        connections[first] |= m.atomBit(second);
        connections[second] |= m.atomBit(first);
        var relation: u8 = 1;
        if (size >= 2) {
            relation = 3;
            if (size == 2) {
                const atom: usize = @ctz(shared);
                const other: usize = @ctz(shared & ~(@as(u128, 1) << @intCast(atom)));
                if (molecule.bondBetween(atom, other) != null) relation = 2;
            }
        }
        relations[first * count + second] = relation;
    };
    var remaining: u512 = 0;
    for (0..count) |id| remaining |= m.atomBit(id);
    var systems: std.ArrayList(System) = .empty;
    while (remaining != 0) {
        const first: usize = @ctz(remaining);
        var component = m.atomBit(first);
        var frontier = component;
        remaining &= ~component;
        while (frontier != 0) {
            const ring: usize = @ctz(frontier);
            frontier &= ~m.atomBit(ring);
            const added = connections[ring] & remaining;
            remaining &= ~added;
            component |= added;
            frontier |= added;
        }
        var indices: std.ArrayList(usize) = .empty;
        var atoms: u128 = 0;
        var fused = false;
        var bridged = false;
        for (0..count) |id| if (component & m.atomBit(id) != 0) {
            m.append(usize, &indices, id);
            atoms |= sets[id];
            for (id + 1..count) |other| if (component & m.atomBit(other) != 0) {
                fused = fused or relations[id * count + other] == 2;
                bridged = bridged or relations[id * count + other] == 3;
            };
        };
        const kind: usize = if (indices.items.len == 1) 0 else if (bridged) 3 else if (fused) 1 else 2;
        m.append(System, &systems, .{ .rings = indices.items, .atoms = @popCount(atoms), .kind = kind });
    }
    return systems.items;
}
const Prepared = struct { molecule: *const m.Molecule, properties: Properties, canonical: []const u8,
     classes: usize, scaffold: ?[]const u8, systems: []const System, aromatic_rings: []const bool,
     fingerprint: search.Fingerprint };
fn prepare(molecule: *const m.Molecule) Prepared {
    const canonical = canon.canonicalize(molecule);
    const scaffold = scaffoldMolecule(molecule);
    const aromatic = m.alloc(bool, molecule.rings.len);
    for (molecule.rings, aromatic) |ring, *flag| {
        flag.* = true;
        for (ring) |atom| flag.* = flag.* and molecule.atoms.items[atom].aromatic;
    }
    return .{ .molecule = molecule, .properties = molecularProperties(molecule), .canonical = canonical.smiles,
         .classes = canonical.classes, .scaffold = if (scaffold) |value| canon.canonicalize(value).smiles else null,
         .systems = ringSystems(molecule), .aromatic_rings = aromatic, .fingerprint = search.fingerprint(molecule) };
}
fn cloneMolecule(source: *const m.Molecule) *m.Molecule {
    const out = m.create(m.Molecule, .{ .elements = source.elements, .name = source.name, .ring_atoms = source.ring_atoms });
    for (source.atoms.items) |atom| _ = out.addAtom(atom);
    for (source.bonds.items) |bond| {
        const index = out.addBond(bond.first, bond.second, bond.symbol);
        out.bonds.items[index] = bond;
    }
    const rings = m.alloc(m.Ring, source.rings.len);
    for (source.rings, rings) |ring, *copy| copy.* = m.dupe(usize, ring);
    out.rings = rings;
    out.finalize();
    return out;
}
fn clonePrepared(source: Prepared) Prepared {
    var out = source;
    out.molecule = cloneMolecule(source.molecule);
    out.properties.formula = m.dupe(u8, source.properties.formula);
    out.canonical = m.dupe(u8, source.canonical);
    out.scaffold = if (source.scaffold) |value| m.dupe(u8, value) else null;
    const systems = m.alloc(System, source.systems.len);
    for (source.systems, systems) |system, *copy| copy.* = .{ .rings = m.dupe(usize, system.rings),
         .atoms = system.atoms, .kind = system.kind };
    out.systems = systems;
    out.aromatic_rings = m.dupe(bool, source.aromatic_rings);
    return out;
}
const Causes = std.StringHashMapUnmanaged(i64);
fn addCause(causes: *Causes, reason: []const u8) void {
    const entry = causes.getOrPut(m.allocator, reason) catch @panic("allocation failed");
    if (!entry.found_existing) entry.value_ptr.* = 0;
    entry.value_ptr.* += 1;
}
fn readMolecules(io: std.Io, elements: []const m.Element, causes: *Causes, work_allocator: std.mem.Allocator) !struct { molecules: []const Prepared,
     errors: m.Lines } {
    const lines = try m.dataLines(io, "input/molecules.smi");
    var molecules: std.ArrayList(Prepared) = .empty;
    var errors: m.Lines = .{};
    var reserved: std.StringHashMapUnmanaged(void) = .empty;
    for (lines) |record| {
        const tokens = m.split(record.line, ' ');
        if (tokens.len != 2 or tokens[0].len == 0 or !validName(tokens[1])) {
            errors.add("line {d}: bad line", .{record.number});
            addCause(causes, "bad line");
            continue;
        }
        const name = tokens[1];
        if (reserved.contains(name)) {
            errors.add("line {d} {s}: duplicate name", .{ record.number, name });
            addCause(causes, "duplicate name");
            continue;
        }
        reserved.put(m.allocator, name, {}) catch @panic("allocation failed");
        const persistent = m.allocator;
        var work: std.heap.ArenaAllocator = .init(work_allocator);
        defer work.deinit();
        m.allocator = work.allocator();
        const parsed = parser.parse(tokens[0], elements, false, parser.readAtom);
        const failure: ?m.AnalysisError = if (parsed.failure) |error_value| error_value else analyze(parsed.molecule.?);
        if (failure) |error_value| {
            m.allocator = persistent;
            errors.add("line {d} {s}: {s} at column {d}", .{ record.number, name, error_value.reason,
                 error_value.column });
            addCause(causes, error_value.reason);
            continue;
        }
        parsed.molecule.?.name = name;
        const prepared = prepare(parsed.molecule.?);
        m.allocator = persistent;
        m.append(Prepared, &molecules, clonePrepared(prepared));
    }
    var paragraph: m.Lines = .{};
    paragraph.add("MOLECULES lines={d} valid={d} errors={d}", .{ lines.len, molecules.items.len,
         errors.data.items.len });
    paragraph.extend(errors);
    return .{ .molecules = molecules.items, .errors = paragraph };
}
const Query = struct { kind: usize, id: []const u8, arguments: m.Names, pattern: ?*const m.Molecule = null,
     threshold: ?search.Similarity = null, count: usize = 0 };
fn findMolecule(molecules: []const Prepared, name: []const u8) ?usize {
    for (molecules, 0..) |value, index| if (m.eq(value.molecule.name, name)) return index;
    return null;
}
fn checkArguments(query: *Query, elements: []const m.Element, molecules: []const Prepared) ?[]const u8 {
    const args = query.arguments;
    const counts = [7][2]usize{ .{ 1, 1 }, .{ 2, 2 }, .{ 2, 12 }, .{ 2, 2 }, .{ 2, 2 }, .{ 2, 2 }, .{ 1, 1 } };
    if (args.len < counts[query.kind][0] or args.len > counts[query.kind][1]) return "bad arguments";
    switch (query.kind) {
        0 => {
            const parsed = parser.parse(args[0], elements, true, search.readPatternAtom);
            if (parsed.failure) |failure| return m.fmt("bad pattern {s} at column {d}", .{ failure.reason,
                 failure.column });
            query.pattern = parsed.molecule;
        },
        6 => {
            query.threshold = threshold(args[0]);
            if (query.threshold == null) return "bad threshold";
        },
        1, 2, 5 => {
            for (args) |name| if (findMolecule(molecules, name) == null) return m.fmt("unknown molecule {s}", .{name});
            for (args, 0..) |name, index| for (args[0..index]) |earlier| if (m.eq(name, earlier)) return "repeated molecule";
        },
        else => {
            if (findMolecule(molecules, args[0]) == null) return m.fmt("unknown molecule {s}", .{args[0]});
            if (query.kind == 3) {
                if (!validNumber(args[1], 1, 99)) return "bad count";
                query.count = m.u(m.number(args[1]));
            } else {
                query.threshold = threshold(args[1]);
                if (query.threshold == null) return "bad threshold";
            }
        },
    }
    return null;
}
fn readQueries(io: std.Io, elements: []const m.Element, molecules: []const Prepared, causes: *Causes) !struct { queries: []const Query,
     errors: m.Lines } {
    const lines = try m.dataLines(io, "input/queries.txt");
    var reserved: std.StringHashMapUnmanaged(void) = .empty;
    var queries: std.ArrayList(Query) = .empty;
    var errors: m.Lines = .{};
    for (lines) |record| {
        const tokens = m.split(record.line, ' ');
        const kind = tokens[0];
        const id = if (tokens.len >= 2) tokens[1] else "";
        var kind_index: ?usize = null;
        for (query_kinds, 0..) |value, index| if (m.eq(kind, value)) {
            kind_index = index;
        };
        var reason: ?[]const u8 = null;
        if (kind_index == null) reason = "unknown query" else if (!validName(id)) reason = "bad id" else if (reserved.contains(id)) reason = "duplicate id" else {
            reserved.put(m.allocator, id, {}) catch @panic("allocation failed");
            var query: Query = .{ .kind = kind_index.?, .id = id, .arguments = tokens[2..] };
            reason = checkArguments(&query, elements, molecules);
            if (reason == null) {
                m.append(Query, &queries, query);
                continue;
            }
        }
        const error_value = reason.?;
        if (m.eq(error_value, "unknown query")) errors.add("line {d}: unknown query", .{record.number}) else if (m.eq(error_value,
             "bad id")) errors.add("line {d} {s}: bad id", .{ record.number, kind }) else errors.add("line {d} {s} {s}: {s}",
             .{ record.number, kind, id, error_value });
        addCause(causes, if (std.mem.startsWith(u8, error_value, "bad pattern ")) "bad pattern" else if (std.mem.startsWith(u8,
             error_value, "unknown molecule ")) "unknown molecule" else error_value);
    }
    var paragraph: m.Lines = .{};
    paragraph.add("QUERIES lines={d} valid={d} errors={d}", .{ lines.len, queries.items.len, errors.data.items.len });
    paragraph.extend(errors);
    return .{ .queries = queries.items, .errors = paragraph };
}

fn appendParagraph(out: *m.Lines, lines: m.Lines) void {
    if (out.data.items.len > 0) out.add("", .{});
    out.extend(lines);
}
fn propertiesLines(molecules: []const Prepared) m.Lines {
    var out: m.Lines = .{};
    out.add("name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski", .{});
    for (molecules) |value| {
        const p = value.properties;
        out.add("{s},{s},{d}.{d:0>3},{d},{d},{d},{d},{d},{s}", .{ value.molecule.name, p.formula,
             @divTrunc(p.weight, 1000), @mod(p.weight, 1000), p.heavy, value.molecule.rings.len,
             p.rotatable, p.donors, p.acceptors, if (p.lipinski) "pass" else "fail" });
    }
    return out;
}
const TextGroup = struct { key: []const u8, members: std.ArrayList(usize) = .empty };
fn textGroups(molecules: []const Prepared, mode: usize) []TextGroup {
    var groups: std.ArrayList(TextGroup) = .empty;
    for (molecules, 0..) |value, id| {
        const key = if (mode == 0) value.canonical else if (mode == 1) value.properties.formula else value.scaffold orelse continue;
        var found: ?usize = null;
        for (groups.items, 0..) |group, index| if (m.eq(group.key, key)) {
            found = index;
            break;
        };
        if (found == null) {
            found = groups.items.len;
            m.append(TextGroup, &groups, .{ .key = key });
        }
        m.append(usize, &groups.items[found.?].members, id);
    }
    return groups.items;
}
fn memberNames(molecules: []const Prepared, ids: []const usize) []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (ids) |id| m.append([]const u8, &names, molecules[id].molecule.name);
    return m.join(names.items, ",");
}
fn canonicalLines(molecules: []const Prepared) m.Lines {
    const by_canonical = textGroups(molecules, 0);
    const by_formula = textGroups(molecules, 1);
    const by_scaffold = textGroups(molecules, 2);
    var out: m.Lines = .{};
    var canonical: m.Lines = .{};
    canonical.add("CANONICAL molecules={d} unique={d}", .{ molecules.len, by_canonical.len });
    for (molecules) |value| canonical.add("{s} {s} classes={d} charge={s}", .{ value.molecule.name,
         value.canonical, value.classes, if (value.properties.charge > 0) m.fmt("+{d}", .{value.properties.charge}) else m.fmt("{d}",
         .{value.properties.charge}) });
    appendParagraph(&out, canonical);
    var group_count: usize = 0;
    var member_count: usize = 0;
    for (by_canonical) |group| if (group.members.items.len >= 2) {
        group_count += 1;
        member_count += group.members.items.len;
    };
    var duplicates: m.Lines = .{};
    duplicates.add("DUPLICATES groups={d} molecules={d}", .{ group_count, member_count });
    var number: usize = 0;
    for (by_canonical) |group| if (group.members.items.len >= 2) {
        number += 1;
        duplicates.add("group {d} {s} members={s}", .{ number, group.key, memberNames(molecules,
             group.members.items) });
    };
    appendParagraph(&out, duplicates);
    var isomer_rows: m.Lines = .{};
    number = 0;
    for (by_formula) |group| {
        var forms: usize = 0;
        for (group.members.items, 0..) |id, index| {
            var earlier = false;
            for (group.members.items[0..index]) |other| earlier = earlier or m.eq(molecules[id].canonical,
                 molecules[other].canonical);
            forms += @intFromBool(!earlier);
        }
        if (forms >= 2) {
            number += 1;
            isomer_rows.add("isomer {d} {s} forms={d} members={s}", .{ number, group.key, forms,
                 memberNames(molecules, group.members.items) });
        }
    }
    var isomers: m.Lines = .{};
    isomers.add("ISOMERS groups={d}", .{number});
    isomers.extend(isomer_rows);
    appendParagraph(&out, isomers);
    std.mem.sort(TextGroup, by_scaffold, {}, struct {
        fn less(_: void, a: TextGroup, b: TextGroup) bool {
            return if (a.members.items.len == b.members.items.len) std.mem.order(u8, a.key,
                 b.key) == .lt else a.members.items.len > b.members.items.len;
        }
    }.less);
    var acyclic: usize = 0;
    for (molecules) |value| acyclic += @intFromBool(value.scaffold == null);
    var scaffolds: m.Lines = .{};
    scaffolds.add("SCAFFOLDS distinct={d} acyclic={d}", .{ by_scaffold.len, acyclic });
    for (by_scaffold, 1..) |group, index| scaffolds.add("scaffold {d} {s} count={d} members={s}",
         .{ index, group.key, group.members.items.len, memberNames(molecules, group.members.items) });
    appendParagraph(&out, scaffolds);
    return out;
}
fn ringLines(molecules: []const Prepared) m.Lines {
    var out: m.Lines = .{};
    var sizes: [81]usize = @splat(0);
    var kinds: [4]usize = @splat(0);
    var total_aromatic: usize = 0;
    var total_rings: usize = 0;
    var cyclic: usize = 0;
    for (molecules) |value| {
        const molecule = value.molecule;
        if (molecule.rings.len == 0) continue;
        cyclic += 1;
        var aromatic: usize = 0;
        for (value.aromatic_rings) |flag| aromatic += @intFromBool(flag);
        total_aromatic += aromatic;
        total_rings += molecule.rings.len;
        var ring_bonds: usize = 0;
        for (molecule.bonds.items) |bond| ring_bonds += @intFromBool(bond.ring);
        var lines: m.Lines = .{};
        lines.add("MOLECULE {s} atoms={d} bonds={d} rings={d} aromatic={d} systems={d} ring_atoms={d} ring_bonds={d}",
             .{ molecule.name, molecule.atoms.items.len, molecule.bonds.items.len, molecule.rings.len,
             aromatic, value.systems.len, @popCount(molecule.ring_atoms), ring_bonds });
        for (molecule.rings, value.aromatic_rings, 1..) |ring, flag, index| {
            var hetero: usize = 0;
            for (ring) |atom| hetero += @intFromBool(!m.eq(molecule.elements[molecule.atoms.items[atom].element].symbol,
                 "C"));
            lines.add("ring {d} size={d} aromatic={s} hetero={d} atoms={s}", .{ index, ring.len,
                 if (flag) "yes" else "no", hetero, atomNumbers(ring, "-") });
            sizes[ring.len] += 1;
        }
        for (value.systems, 1..) |system, index| {
            kinds[system.kind] += 1;
            lines.add("system {d} kind={s} rings={s} atoms={d}", .{ index, system_kinds[system.kind],
                 atomNumbers(system.rings, ","), system.atoms });
        }
        var doubles: std.ArrayList([]const u8) = .empty;
        for (molecule.ordered) |index| {
            const bond = molecule.bonds.items[index];
            if (bond.kind == 4 and bond.multiplicity == 2) m.append([]const u8, &doubles, m.fmt("{d}={d}",
                 .{ bond.first + 1, bond.second + 1 }));
        }
        lines.add("kekule {s}", .{if (doubles.items.len > 0) m.join(doubles.items, " ") else "-"});
        appendParagraph(&out, lines);
    }
    var summary: m.Lines = .{};
    summary.add("SUMMARY molecules={d} cyclic={d} rings={d} aromatic={d}", .{ molecules.len,
         cyclic, total_rings, total_aromatic });
    var text: m.Text = .{};
    text.add("sizes", .{});
    if (total_rings == 0) text.add(" -", .{}) else for (sizes, 0..) |count, size| if (count > 0) text.add(" {d}={d}",
         .{ size, count });
    summary.add("{s}", .{text.value()});
    summary.add("systems isolated={d} fused={d} spiro={d} bridged={d}", .{ kinds[0], kinds[1], kinds[2], kinds[3] });
    appendParagraph(&out, summary);
    return out;
}
fn substructureLines(queries: []const Query, molecules: []const Prepared, work_allocator: std.mem.Allocator) m.Lines {
    var out: m.Lines = .{};
    var patterns: usize = 0;
    var hits: usize = 0;
    var contains: usize = 0;
    var found: usize = 0;
    for (queries) |query| {
        if (query.kind != 0 and query.kind != 1) continue;
        const persistent = m.allocator;
        var arena: std.heap.ArenaAllocator = .init(work_allocator);
        defer arena.deinit();
        m.allocator = arena.allocator();
        var lines: m.Lines = .{};
        if (query.kind == 0) {
            patterns += 1;
            const pattern = query.pattern.?;
            const Hit = struct { id: usize, matched: search.Embeddings };
            var matches: std.ArrayList(Hit) = .empty;
            var total: i64 = 0;
            var top: ?Hit = null;
            for (molecules, 0..) |value, id| {
                const matched = search.embeddings(pattern, value.molecule, work_allocator);
                if (matched.count == 0) continue;
                const hit: Hit = .{ .id = id, .matched = matched };
                m.append(Hit, &matches, hit);
                total += matched.count;
                if (top == null or matched.count > top.?.matched.count) top = hit;
            }
            hits += matches.items.len;
            lines.add("MATCH {s} {s} atoms={d} bonds={d} hits={d} embeddings={d}", .{ query.id,
                 query.arguments[0], pattern.atoms.items.len, pattern.bonds.items.len, matches.items.len,
                 total });
            for (matches.items) |hit| lines.add("{s} count={d} unique={d} map={s}", .{ molecules[hit.id].molecule.name,
                 hit.matched.count, hit.matched.unique, atomNumbers(hit.matched.mapping, ",") });
            if (top) |hit| lines.add("top {s} count={d}", .{ molecules[hit.id].molecule.name, hit.matched.count });
        } else {
            contains += 1;
            const first = molecules[findMolecule(molecules, query.arguments[0]).?].molecule;
            const second = molecules[findMolecule(molecules, query.arguments[1]).?].molecule;
            const matched = search.embeddings(search.moleculePattern(first), second, work_allocator);
            if (matched.count > 0) {
                found += 1;
                lines.add("CONTAINS {s} {s} {s} result=yes count={d} unique={d} map={s}", .{ query.id,
                     first.name, second.name, matched.count, matched.unique, atomNumbers(matched.mapping,
                     ",") });
            } else lines.add("CONTAINS {s} {s} {s} result=no", .{ query.id, first.name, second.name });
        }
        m.allocator = persistent;
        appendParagraph(&out, lines);
    }
    var summary: m.Lines = .{};
    summary.add("SUMMARY patterns={d} hits={d} contains={d} found={d}", .{ patterns, hits, contains, found });
    appendParagraph(&out, summary);
    return out;
}
const Similarities = struct {
    count: usize,
    values: []search.Similarity,
    fn init(molecules: []const Prepared) Similarities {
        const values = m.alloc(search.Similarity, molecules.len * molecules.len);
        for (molecules, 0..) |first, a| for (molecules[a..], a..) |second, b| {
            const value = search.tanimoto(first.fingerprint, second.fingerprint);
            values[a * molecules.len + b] = value;
            values[b * molecules.len + a] = value;
        };
        return .{ .count = molecules.len, .values = values };
    }
    fn get(self: Similarities, a: usize, b: usize) search.Similarity {
        return self.values[a * self.count + b];
    }
};
fn similarityLines(queries: []const Query, molecules: []const Prepared, work_allocator: std.mem.Allocator) m.Lines {
    const similarities = Similarities.init(molecules);
    var out: m.Lines = .{};
    var fingerprints: m.Lines = .{};
    fingerprints.add("FINGERPRINTS molecules={d} size=1024 depth=5", .{molecules.len});
    for (molecules) |value| fingerprints.add("{s} bits={d} paths={d}", .{ value.molecule.name,
         value.fingerprint.count(), value.fingerprint.paths });
    appendParagraph(&out, fingerprints);
    for (queries) |query| {
        if (query.kind < 2) continue;
        const persistent = m.allocator;
        var arena: std.heap.ArenaAllocator = .init(work_allocator);
        defer arena.deinit();
        m.allocator = arena.allocator();
        var lines: m.Lines = .{};
        if (query.kind == 2) {
            const ids = m.alloc(usize, query.arguments.len);
            for (query.arguments, ids) |name, *id| id.* = findMolecule(molecules, name).?;
            lines.add("MATRIX {s} size={d}", .{ query.id, ids.len });
            for (ids) |first| {
                var row: m.Text = .{};
                row.add("row {s}", .{molecules[first].molecule.name});
                for (ids) |second| row.add(" {s}", .{similarities.get(first, second).text()});
                lines.add("{s}", .{row.value()});
            }
            var best_first = ids[0];
            var best_second = ids[1];
            var best = similarities.get(best_first, best_second);
            for (ids, 0..) |first, index| for (ids[index + 1 ..]) |second| {
                const value = similarities.get(first, second);
                if (best.less(value)) {
                    best_first = first;
                    best_second = second;
                    best = value;
                }
            };
            lines.add("best {s} {s} {s}", .{ molecules[best_first].molecule.name, molecules[best_second].molecule.name,
                 best.text() });
        } else if (query.kind == 3 or query.kind == 4) {
            const source = findMolecule(molecules, query.arguments[0]).?;
            var neighbors: std.ArrayList(usize) = .empty;
            for (0..molecules.len) |id| if (id != source) m.append(usize, &neighbors, id);
            const Context = struct { similarities: Similarities, source: usize };
            std.mem.sort(usize, neighbors.items, Context{ .similarities = similarities, .source = source }, struct {
                fn less(context: Context, a: usize, b: usize) bool {
                    const first = context.similarities.get(context.source, a);
                    const second = context.similarities.get(context.source, b);
                    if (first.less(second)) return false;
                    if (second.less(first)) return true;
                    return a < b;
                }
            }.less);
            var selected: std.ArrayList(usize) = .empty;
            for (neighbors.items) |id| {
                if (query.kind == 3) {
                    if (selected.items.len == query.count) break;
                } else if (similarities.get(source, id).less(query.threshold.?)) continue;
                m.append(usize, &selected, id);
            }
            if (query.kind == 3) lines.add("NEAREST {s} {s} count={d}", .{ query.id, molecules[source].molecule.name,
                 selected.items.len }) else lines.add("WITHIN {s} {s} threshold={s} count={d}",
                 .{ query.id, molecules[source].molecule.name, query.threshold.?.text(), selected.items.len });
            for (selected.items, 1..) |id, number| {
                const value = similarities.get(source, id);
                lines.add("{d} {s} {s} common={d}", .{ number, molecules[id].molecule.name,
                     value.text(), value.common });
            }
        } else if (query.kind == 5) {
            const first = findMolecule(molecules, query.arguments[0]).?;
            const second = findMolecule(molecules, query.arguments[1]).?;
            const value = similarities.get(first, second);
            lines.add("COMPARE {s} {s} {s} bits={d},{d} common={d} union={d} tanimoto={s} identical={s}",
                 .{ query.id, molecules[first].molecule.name, molecules[second].molecule.name,
                 molecules[first].fingerprint.count(), molecules[second].fingerprint.count(),
                 value.common, value.union_count, value.text(), if (m.eq(molecules[first].canonical,
                 molecules[second].canonical)) "yes" else "no" });
        } else {
            const count = molecules.len;
            const neighboring = m.zero(bool, count * count, false);
            const degree = m.zero(usize, count, 0);
            for (0..count) |first| for (0..count) |second| if (first != second and !similarities.get(first,
                 second).less(query.threshold.?)) {
                neighboring[first * count + second] = true;
                degree[first] += 1;
            };
            const order = m.alloc(usize, count);
            for (order, 0..) |*id, index| id.* = index;
            std.mem.sort(usize, order, degree, struct {
                fn less(degrees: []usize, a: usize, b: usize) bool {
                    return if (degrees[a] == degrees[b]) a < b else degrees[a] > degrees[b];
                }
            }.less);
            const assigned = m.zero(bool, count, false);
            var clusters: std.ArrayList([]const usize) = .empty;
            var singletons: usize = 0;
            for (order) |center| {
                if (assigned[center]) continue;
                var members: std.ArrayList(usize) = .empty;
                m.append(usize, &members, center);
                assigned[center] = true;
                for (0..count) |id| if (neighboring[center * count + id] and !assigned[id]) {
                    m.append(usize, &members, id);
                    assigned[id] = true;
                };
                m.append([]const usize, &clusters, members.items);
                singletons += @intFromBool(members.items.len == 1);
            }
            lines.add("CLUSTER {s} threshold={s} clusters={d} singletons={d}", .{ query.id,
                 query.threshold.?.text(), clusters.items.len, singletons });
            var number: usize = 0;
            for (clusters.items) |members| if (members.len >= 2) {
                number += 1;
                lines.add("cluster {d} centroid={s} size={d} members={s}", .{ number, molecules[members[0]].molecule.name,
                     members.len, memberNames(molecules, members) });
            };
        }
        m.allocator = persistent;
        appendParagraph(&out, lines);
    }
    return out;
}
fn causesLines(causes: *const Causes) m.Lines {
    const Cause = struct { reason: []const u8, count: i64 };
    var rows: std.ArrayList(Cause) = .empty;
    var entries = causes.iterator();
    while (entries.next()) |entry| m.append(Cause, &rows, .{ .reason = entry.key_ptr.*, .count = entry.value_ptr.* });
    std.mem.sort(Cause, rows.items, {}, struct {
        fn less(_: void, a: Cause, b: Cause) bool {
            return if (a.count == b.count) std.mem.order(u8, a.reason, b.reason) == .lt else a.count > b.count;
        }
    }.less);
    var out: m.Lines = .{};
    out.add("CAUSES kinds={d}", .{rows.items.len});
    for (rows.items) |row| out.add("{s}={d}", .{ row.reason, row.count });
    return out;
}
fn write(io: std.Io, name: []const u8, lines: m.Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var text: m.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = m.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    m.allocator = arena.allocator();
    const elements = try m.readElements(init.io);
    var causes: Causes = .empty;
    const molecules = try readMolecules(init.io, elements, &causes, init.gpa);
    const queries = try readQueries(init.io, elements, molecules.molecules, &causes);
    var errors: m.Lines = .{};
    appendParagraph(&errors, molecules.errors);
    appendParagraph(&errors, queries.errors);
    appendParagraph(&errors, causesLines(&causes));
    try write(init.io, "properties.csv", propertiesLines(molecules.molecules));
    try write(init.io, "canonical.txt", canonicalLines(molecules.molecules));
    try write(init.io, "rings.txt", ringLines(molecules.molecules));
    try write(init.io, "substructure.txt", substructureLines(queries.queries, molecules.molecules, init.gpa));
    try write(init.io, "similarity.txt", similarityLines(queries.queries, molecules.molecules, init.gpa));
    try write(init.io, "errors.txt", errors);
}
