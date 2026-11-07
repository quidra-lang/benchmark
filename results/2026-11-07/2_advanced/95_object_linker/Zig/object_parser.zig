const std = @import("std");
pub const Text = []const u8;
pub fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
pub fn belongs(name: Text, prefix: Text) bool { return eq(name, prefix) or (std.mem.startsWith(u8, name, prefix) and name.len > prefix.len and name[prefix.len] == '.'); }
pub fn number(s: Text) i64 { return std.fmt.parseInt(i64, s, 0) catch unreachable; }
pub const Position = struct { original: usize, merged: usize };
pub const Section = struct {
    owner: *Object, name: Text, alignment: i64, size: usize, contents: std.ArrayList(u8) = .empty,
    relocations: std.ArrayList(*Relocation) = .empty, discard: ?Text = null, output: ?usize = null, live: bool = false, address: i64 = 0,
    merged: std.ArrayList(Position) = .empty,
    pub fn location(s: *Section, offset: usize) i64 { if (belongs(s.name, ".rodata.str")) for (s.merged.items) |p| { if (p.original == offset) return s.address + @as(i64, @intCast(p.merged)); }; return s.address + @as(i64, @intCast(offset)); }
};
pub const Symbol = struct { owner: *Object, name: Text, binding: enum { local, global, weak }, kind: enum { defined, @"undefined", common }, section: ?*Section = null, offset: usize = 0, size: usize = 0, alignment: i64 = 1 };
pub const Relocation = struct { section: *Section, offset: usize, kind: enum { ABS32, REL32, ABS16, HI16, LO16, GPREL16, CALL24 }, symbol: *Symbol, addend: i64, far: bool = false, place: i64 = 0, value: i64 = 0, field: i64 = 0, target: ?i64 = null, status: enum { ok, veneer, overflow, @"undefined" } = .ok, unpaired: bool = false };
pub const Group = struct { signature: Text, sections: []*Section };
pub const Object = struct {
    name: Text, sections: std.ArrayList(*Section) = .empty, symbols: std.ArrayList(*Symbol) = .empty, groups: std.ArrayList(Group) = .empty,
    pub fn section(o: *Object, name: Text) *Section { for (o.sections.items) |s| if (eq(s.name, name)) return s; unreachable; }
    pub fn symbol(o: *Object, name: Text) *Symbol { for (o.symbols.items) |s| if (eq(s.name, name)) return s; unreachable; }
};
pub fn lines(a: std.mem.Allocator, text: Text) ![]const Text { var list: std.ArrayList(Text) = .empty; var it = std.mem.tokenizeScalar(u8, text, '\n'); while (it.next()) |line| try list.append(a, line); return list.items; }
pub fn parse(a: std.mem.Allocator, source: []const Text, index: *usize, name: Text) !*Object {
    const o = try a.create(Object); o.* = .{ .name = name };
    while (!eq(source[index.*], "end")) {
        var words = std.mem.splitScalar(u8, source[index.*], ' '); index.* += 1; const kind = words.next().?;
        if (eq(kind, "section")) {
            const s = try a.create(Section); s.* = .{ .owner = o, .name = words.next().?, .alignment = number(words.next().?), .size = @intCast(number(words.next().?)) }; try o.sections.append(a, s);
            if (!belongs(s.name, ".bss")) while (s.contents.items.len < s.size) { const hex = source[index.*][5..]; index.* += 1; var p: usize = 0; while (p < hex.len) : (p += 2) try s.contents.append(a, try std.fmt.parseInt(u8, hex[p..p + 2], 16)); };
        } else if (eq(kind, "comdat")) {
            const signature = words.next().?; var sections: std.ArrayList(*Section) = .empty; while (words.next()) |n| try sections.append(a, o.section(n)); try o.groups.append(a, .{ .signature = signature, .sections = sections.items });
        } else if (eq(kind, "symbol")) {
            const s = try a.create(Symbol); const n = words.next().?; const binding = std.meta.stringToEnum(@FieldType(Symbol, "binding"), words.next().?).?; const place = words.next().?;
            s.* = .{ .owner = o, .name = n, .binding = binding, .kind = if (eq(place, "undef")) .@"undefined" else if (eq(place, "common")) .common else .defined };
            if (s.kind == .defined) { s.section = o.section(place); s.offset = @intCast(number(words.next().?)); } else if (s.kind == .common) { s.size = @intCast(number(words.next().?)); s.alignment = number(words.next().?); }
            try o.symbols.append(a, s);
        } else if (eq(kind, "reloc")) {
            const s = o.section(words.next().?); const r = try a.create(Relocation); const offset: usize = @intCast(number(words.next().?)); const k = std.meta.stringToEnum(@FieldType(Relocation, "kind"), words.next().?).?; const symbol = o.symbol(words.next().?);
            r.* = .{ .section = s, .offset = offset, .kind = k, .symbol = symbol, .addend = number(words.next().?) }; try s.relocations.append(a, r);
        }
    }
    index.* += 1; return o;
}
