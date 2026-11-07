const std = @import("std");
const obj = @import("object_parser.zig");
const archives = @import("archive.zig");
const resolver = @import("resolver.zig");
const layout = @import("layout.zig");
const reloc = @import("relocator.zig");
const Text = obj.Text;
const Buffer = struct {
    a: std.mem.Allocator, bytes: std.ArrayList(u8) = .empty,
    fn add(b: *Buffer, s: Text) !void { try b.bytes.appendSlice(b.a, s); }
    fn print(b: *Buffer, comptime f: Text, args: anytype) !void { try b.add(try std.fmt.allocPrint(b.a, f, args)); }
    fn line(b: *Buffer, s: Text) !void { try b.add(s); try b.add("\n"); }
};
const Pair = struct { first: Text, second: Text };
const Input = struct { kind: Text, names: []const Text };
const Comdat = struct { signature: Text, keeper: Text, discarded: std.ArrayList(Text) = .empty };
const Extraction = struct { object: Text, referrer: Text, reason: Text };
fn less(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; }
fn contains(xs: []const Text, x: Text) bool { for (xs) |s| if (obj.eq(s, x)) return true; return false; }
const Linker = struct {
    a: std.mem.Allocator, io: std.Io, entry: Text = "", gc: bool = true,
    segments: std.ArrayList(layout.Segment) = .empty, outputs: std.ArrayList(layout.Output) = .empty,
    loads: std.ArrayList(Pair) = .empty, defines: std.ArrayList(Pair) = .empty, wrapped: std.ArrayList(Text) = .empty,
    inputs: std.ArrayList(Input) = .empty, checksum: ?Pair = null,
    objects: std.ArrayList(*obj.Object) = .empty, libraries: std.ArrayList(archives.Archive) = .empty,
    comdats: std.ArrayList(Comdat) = .empty, extractions: std.ArrayList(Extraction) = .empty,
    names: std.ArrayList(*resolver.Resolution) = .empty, applied: std.ArrayList(*obj.Relocation) = .empty,
    fn read(l: *Linker, name: Text) !Text { return std.Io.Dir.cwd().readFileAlloc(l.io, try std.fmt.allocPrint(l.a, "input/{s}", .{name}), l.a, .unlimited); }
    fn output(l: *Linker, name: Text) usize { for (l.outputs.items, 0..) |o, i| if (obj.eq(o.name, name)) return i; unreachable; }
    fn segment(l: *Linker, name: Text) usize { for (l.segments.items, 0..) |s, i| if (obj.eq(s.name, name)) return i; unreachable; }
    fn resolution(l: *Linker, name: Text) ?*resolver.Resolution { for (l.names.items) |r| if (obj.eq(r.name, name)) return r; return null; }
    fn isScript(l: *Linker, name: Text) bool { for (l.defines.items) |d| if (obj.eq(d.first, name)) return true; return false; }
    fn script(l: *Linker, text: Text) !void {
        for (try obj.lines(l.a, text)) |line| {
            var words = std.mem.splitScalar(u8, line, ' '); const k = words.next().?;
            if (obj.eq(k, "entry")) l.entry = words.next().?
            else if (obj.eq(k, "gc")) l.gc = obj.eq(words.next().?, "on")
            else if (obj.eq(k, "segment")) {
                var s: layout.Segment = .{ .name = words.next().?, .base = obj.number(words.next().?), .length = obj.number(words.next().?), .fill = @intCast(obj.number(words.next().?)) };
                while (words.next()) |name| { try s.outputs.append(l.a, l.outputs.items.len); try l.outputs.append(l.a, .{ .name = name, .segment = l.segments.items.len }); } try l.segments.append(l.a, s);
            } else if (obj.eq(k, "load")) try l.loads.append(l.a, .{ .first = words.next().?, .second = words.next().? })
            else if (obj.eq(k, "keep")) l.outputs.items[l.output(words.next().?)].keep = true
            else if (obj.eq(k, "sort")) l.outputs.items[l.output(words.next().?)].sorted = true
            else if (obj.eq(k, "wrap")) try l.wrapped.append(l.a, words.next().?)
            else if (obj.eq(k, "define")) { const n = words.next().?; _ = words.next(); try l.defines.append(l.a, .{ .first = n, .second = words.rest() }); }
            else if (obj.eq(k, "checksum")) l.checksum = .{ .first = words.next().?, .second = words.next().? }
            else { var ns: std.ArrayList(Text) = .empty; while (words.next()) |n| try ns.append(l.a, n); try l.inputs.append(l.a, .{ .kind = k, .names = ns.items }); }
        }
    }
    pub fn isUndefined(l: *Linker, name: Text) bool {
        if (l.isScript(name)) return false; var required = obj.eq(name, l.entry);
        for (l.objects.items) |o| for (o.symbols.items) |s| if (s.binding != .local and obj.eq(s.name, name)) { if (s.kind != .@"undefined") return false; if (s.binding == .global) required = true; };
        return required;
    }
    fn load(l: *Linker, o: *obj.Object) !void {
        for (o.groups.items) |group| {
            var found = false;
            for (l.comdats.items) |*c| if (obj.eq(c.signature, group.signature)) { try c.discarded.append(l.a, o.name); for (group.sections) |s| s.discard = "comdat"; found = true; break; };
            if (!found) try l.comdats.append(l.a, .{ .signature = group.signature, .keeper = o.name });
        }
        for (o.symbols.items) |s| {
            if (s.binding != .local and s.kind == .defined and s.section.?.discard != null) { s.kind = .@"undefined"; s.section = null; }
            if (s.kind == .@"undefined") { if (contains(l.wrapped.items, s.name)) s.name = try std.fmt.allocPrint(l.a, "__wrap_{s}", .{s.name}) else if (std.mem.startsWith(u8, s.name, "__real_") and contains(l.wrapped.items, s.name[7..])) s.name = s.name[7..]; }
        }
        try l.objects.append(l.a, o);
    }
    pub fn extract(l: *Linker, o: *obj.Object, reason: Text) !void {
        var referrer: Text = "*entry*";
        outer: for (l.objects.items) |previous| for (previous.symbols.items) |s| if (s.kind == .@"undefined" and s.binding == .global and obj.eq(s.name, reason)) { referrer = previous.name; break :outer; };
        try l.extractions.append(l.a, .{ .object = o.name, .referrer = referrer, .reason = reason }); try l.load(o);
    }
    fn scan(l: *Linker, name: Text) !usize {
        for (l.libraries.items) |*lib| if (obj.eq(lib.name, name)) return archives.scan(lib, l);
        try l.libraries.append(l.a, try archives.parse(l.a, name, try l.read(name))); return archives.scan(&l.libraries.items[l.libraries.items.len - 1], l);
    }
    fn loadInputs(l: *Linker) !void {
        for (l.inputs.items) |input| {
            if (obj.eq(input.kind, "object")) { var index: usize = 0; try l.load(try obj.parse(l.a, try obj.lines(l.a, try l.read(input.names[0])), &index, input.names[0])); }
            else if (obj.eq(input.kind, "library")) { _ = try l.scan(input.names[0]); }
            else while (true) { var count: usize = 0; for (input.names) |n| count += try l.scan(n); if (count == 0) break; };
        }
        var names: std.ArrayList(Text) = .empty;
        for (l.objects.items) |o| for (o.symbols.items) |s| { if (s.binding != .local) try resolver.unique(l.a, &names, s.name); };
        for (l.defines.items) |d| try resolver.unique(l.a, &names, d.first); std.mem.sort(Text, names.items, {}, less);
        for (names.items) |n| try l.names.append(l.a, try resolver.resolve(l.a, n, l.objects.items, l.isScript(n)));
    }
    fn mark(l: *Linker, symbol: *obj.Symbol) bool {
        var target: ?*obj.Section = null;
        if (symbol.binding == .local) target = symbol.section else { const r = l.resolution(symbol.name).?; if (r.kind == .common) { const changed = !r.live; r.live = true; return changed; } if (r.kind == .global or r.kind == .weak) target = r.definition.?.section; }
        if (target) |s| { if (s.discard != null or s.output == null) return false; const changed = !s.live; s.live = true; return changed; } return false;
    }
    fn collect(l: *Linker) !void {
        for (l.objects.items) |o| for (o.sections.items) |s| {
            if (s.discard != null) continue; for (l.outputs.items, 0..) |out, i| if (obj.belongs(s.name, out.name)) { s.output = i; break; };
            if (s.output == null) s.discard = "orphan" else s.live = !l.gc or l.outputs.items[s.output.?].keep;
        };
        for (l.names.items) |r| if (r.kind == .common) { r.live = !l.gc; };
        if (l.resolution(l.entry)) |r| { if (r.kind == .common) r.live = true else if (r.definition) |s| { _ = l.mark(s); } }
        while (true) { var changed = false; for (l.objects.items) |o| for (o.sections.items) |s| if (s.live) { for (s.relocations.items) |r| changed = l.mark(r.symbol) or changed; }; if (!changed) break; }
        for (l.objects.items) |o| for (o.sections.items) |s| { if (s.output != null and !s.live and s.discard == null) s.discard = "gc"; if (s.live) for (s.relocations.items) |r| { if (r.symbol.binding != .local) { const resolved = l.resolution(r.symbol.name).?; if (resolved.kind == .@"undefined") try resolver.unique(l.a, &resolved.unresolved, o.name); } }; };
    }
    fn component(l: *Linker, c: layout.Component) !*layout.Component { const p = try l.a.create(layout.Component); p.* = c; return p; }
    fn build(l: *Linker) !void {
        for (l.outputs.items, 0..) |*out, oi| {
            var sections: std.ArrayList(*obj.Section) = .empty;
            for (l.objects.items) |o| for (o.sections.items) |s| if (s.live and s.output == oi) { try sections.append(l.a, s); };
            if (out.sorted) { var i: usize = 1; while (i < sections.items.len) : (i += 1) { var j = i; while (j > 0 and priority(sections.items[j], out.name) < priority(sections.items[j - 1], out.name)) : (j -= 1) std.mem.swap(*obj.Section, &sections.items[j], &sections.items[j - 1]); } }
            var strings: std.ArrayList(*obj.Section) = .empty; for (sections.items) |s| if (obj.belongs(s.name, ".rodata.str")) { try strings.append(l.a, s); };
            var inserted = false;
            for (sections.items) |s| { if (obj.belongs(s.name, ".rodata.str")) { if (!inserted) try out.components.append(l.a, try layout.merged(l.a, strings.items)); inserted = true; } else try out.components.append(l.a, try l.component(.{ .kind = .input, .size = s.size, .alignment = s.alignment, .section = s })); }
            if (obj.eq(out.name, ".bss")) { var commons: std.ArrayList(*resolver.Resolution) = .empty; for (l.names.items) |r| if (r.kind == .common and r.live) { try commons.append(l.a, r); }; std.mem.sort(*resolver.Resolution, commons.items, {}, struct { fn lessCommon(_: void, x: *resolver.Resolution, y: *resolver.Resolution) bool { return if (x.alignment == y.alignment) less({}, x.name, y.name) else x.alignment > y.alignment; } }.lessCommon); for (commons.items) |r| try out.components.append(l.a, try l.component(.{ .kind = .common, .size = r.size, .alignment = r.alignment, .resolution = r })); }
            out.base_count = out.components.items.len;
        }
        while (true) {
            for (l.segments.items) |*s| layout.assign(s, l.outputs.items); var changed = false;
            for (l.objects.items) |o| for (o.sections.items) |s| if (s.live) { for (s.relocations.items) |r| {
                r.far = false; if (r.kind != .CALL24 or r.symbol.binding == .local) continue; const resolved = l.resolution(r.symbol.name).?;
                if (resolved.kind != .global and resolved.kind != .weak) continue;
                r.far = reloc.far(resolved.value().? + r.addend - s.address - @as(i64, @intCast(r.offset)));
                if (r.far and l.veneer(s.output.?, resolved.name) == null) { try l.outputs.items[s.output.?].components.append(l.a, try l.component(.{ .kind = .veneer, .size = 8, .alignment = 4, .resolution = resolved })); changed = true; }
            } };
            if (!changed) break;
            for (l.outputs.items) |*out| std.mem.sort(*layout.Component, out.components.items[out.base_count..], {}, struct { fn cmp(_: void, x: *layout.Component, y: *layout.Component) bool { return less({}, x.resolution.?.name, y.resolution.?.name); } }.cmp);
        }
        for (l.loads.items) |pair| { const source = &l.segments.items[l.segment(pair.first)]; const destination = &l.segments.items[l.segment(pair.second)]; source.paddr = layout.alignUp(destination.base + destination.used, 4); destination.used = source.paddr + @as(i64, @intCast(source.filesz)) - destination.base; }
        for (l.defines.items) |d| { var expression: Expression = .{ .linker = l, .text = d.second }; l.resolution(d.first).?.address = expression.expr(); }
    }
    fn veneer(l: *Linker, oi: usize, name: Text) ?*layout.Component { for (l.outputs.items[oi].components.items) |c| if (c.kind == .veneer and obj.eq(c.resolution.?.name, name)) return c; return null; }
    fn value(l: *Linker, s: *obj.Symbol) ?i64 { return if (s.binding == .local) s.section.?.location(s.offset) else l.resolution(s.name).?.value(); }
    fn entryAddress(l: *Linker) i64 { const r = l.resolution(l.entry) orelse return 0; return if (r.kind == .global or r.kind == .weak or r.kind == .common) r.value() orelse 0 else 0; }
    fn apply(l: *Linker) !void {
        const gp = if (l.resolution("_gp")) |r| r.address else 0;
        for (l.outputs.items) |out| for (out.components.items) |c| if (c.section) |s| { for (s.relocations.items, 0..) |r, i| { r.place = s.address + @as(i64, @intCast(r.offset)); r.unpaired = !reloc.paired(s.relocations.items, i); r.target = l.value(r.symbol); if (r.far) { r.target = l.veneer(s.output.?, r.symbol.name).?.address; r.status = .veneer; } reloc.apply(r, gp); try l.applied.append(l.a, r); } };
        for (l.segments.items) |*image_segment| {
            image_segment.image = try l.a.alloc(u8, image_segment.filesz); @memset(image_segment.image, image_segment.fill);
            for (image_segment.outputs.items) |oi| { const out = l.outputs.items[oi]; if (obj.belongs(out.name, ".bss")) continue; for (out.components.items) |c| {
                const start: usize = @intCast(c.address - image_segment.base); const target = image_segment.image[start..][0..c.size];
                switch (c.kind) { .input => @memcpy(target, c.section.?.contents.items), .merged => @memcpy(target, c.contents.items), .veneer => { @memcpy(target[0..4], &.{4, 240, 31, 229}); reloc.write(target[4..8], c.resolution.?.value().?); }, .common => unreachable }
            } }
        }
        if (l.checksum) |pair| { const s = &l.segments.items[l.segment(pair.first)]; const offset: usize = @intCast(l.resolution(pair.second).?.value().? - s.base); @memset(s.image[offset..][0..4], 0); var sum: i64 = 0; for (s.image, 0..) |byte, i| sum += @as(i64, byte) << @intCast((i % 4) * 8); reloc.write(s.image[offset..][0..4], @mod(-sum, 4294967296)); }
    }
};
fn priority(s: *obj.Section, prefix: Text) i64 { return if (obj.eq(s.name, prefix)) 65536 else obj.number(s.name[prefix.len + 1..]); }
const Expression = struct {
    linker: *Linker, text: Text, p: usize = 0,
    fn spaces(e: *Expression) void { while (e.p < e.text.len and e.text[e.p] == ' ') e.p += 1; }
    fn token(e: *Expression) Text { e.spaces(); const start = e.p; if (std.mem.indexOfScalar(u8, "(),+-", e.text[e.p]) != null) e.p += 1 else while (e.p < e.text.len and (std.ascii.isAlphanumeric(e.text[e.p]) or e.text[e.p] == '_' or e.text[e.p] == '.')) e.p += 1; return e.text[start..e.p]; }
    fn expr(e: *Expression) i64 { var v = e.term(); while (true) { e.spaces(); if (e.p == e.text.len or (e.text[e.p] != '+' and e.text[e.p] != '-')) return v; const op = e.text[e.p]; e.p += 1; const rhs = e.term(); v = if (op == '+') v + rhs else v - rhs; } }
    fn term(e: *Expression) i64 {
        const t = e.token(); if (obj.eq(t, "(")) { const v = e.expr(); _ = e.token(); return v; } if (std.ascii.isDigit(t[0])) return obj.number(t);
        e.spaces(); if (e.p == e.text.len or e.text[e.p] != '(') return e.linker.resolution(t).?.address; e.p += 1;
        if (obj.eq(t, "align")) { const v = e.expr(); _ = e.token(); const n = e.expr(); _ = e.token(); return layout.alignUp(v, n); }
        const out = e.linker.outputs.items[e.linker.output(e.token())]; _ = e.token(); return if (obj.eq(t, "start")) out.address else if (obj.eq(t, "end")) out.address + @as(i64, @intCast(out.size)) else if (obj.eq(t, "size")) @intCast(out.size) else e.linker.segments.items[out.segment].paddr + out.address - e.linker.segments.items[out.segment].base;
    }
};
fn heading(b: *Buffer, s: layout.Segment) !void { try b.print("segment {s} vaddr {x:0>8} paddr {x:0>8} filesz {d} memsz {d}", .{s.name, @as(u64, @intCast(s.base)), @as(u64, @intCast(s.paddr)), s.filesz, s.memsz}); }
fn join(b: *Buffer, names: []const Text, sep: Text) !void { if (names.len == 0) try b.add("-"); for (names, 0..) |n, i| { if (i > 0) try b.add(sep); try b.add(n); } }
fn record(b: *Buffer, kind: u8, address: usize, data: []const u8) !void {
    var sum: usize = data.len + address / 256 + address % 256 + kind; try b.print(":{X:0>2}{X:0>4}{X:0>2}", .{data.len, address, kind}); for (data) |byte| { sum += byte; try b.print("{X:0>2}", .{byte}); } try b.print("{X:0>2}\n", .{@mod(256 - @as(i64, @intCast(sum % 256)), 256)});
}
fn outputs(l: *Linker) !void {
    var image: Buffer = .{ .a = l.a }; var flash: Buffer = .{ .a = l.a }; var map: Buffer = .{ .a = l.a }; var xref: Buffer = .{ .a = l.a }; var report: Buffer = .{ .a = l.a }; var diag: Buffer = .{ .a = l.a };
    try image.print("entry {x:0>8} {s}\n", .{@as(u64, @intCast(l.entryAddress())), l.entry});
    for (l.extractions.items) |ex| try map.print("member {s} {s} {s}\n", .{ex.object, ex.referrer, ex.reason});
    for (l.comdats.items) |c| { try map.print("comdat {s} {s} ", .{c.signature, c.keeper}); try join(&map, c.discarded.items, ","); try map.add("\n"); }
    for (l.segments.items) |s| {
        try heading(&image, s); try image.add("\n"); var start: usize = 0; while (start < s.filesz) : (start += 16) { try image.print("{x:0>8}", .{@as(u64, @intCast(s.base)) + start}); for (s.image[start..@min(start + 16, s.filesz)]) |byte| try image.print(" {x:0>2}", .{byte}); try image.add("\n"); }
        try heading(&map, s); try map.print(" used {d} length {d} {d}%\n", .{s.used, s.length, @divFloor(100 * s.used, s.length)});
        for (s.outputs.items) |oi| { const o = l.outputs.items[oi]; try map.print("section {s} {x:0>8} {d} {d}\n", .{o.name, @as(u64, @intCast(o.address)), o.size, o.alignment}); for (o.components.items) |c| switch (c.kind) {
            .input => try map.print("input {x:0>8} {d} {d} {s} {s}\n", .{@as(u64, @intCast(c.address)), c.size, c.alignment, c.section.?.owner.name, c.section.?.name}),
            .merged => try map.print("merged {x:0>8} {d} sections {d} strings {d} unique {d} saved {d}\n", .{@as(u64, @intCast(c.address)), c.size, c.sources.len, c.strings, c.unique, c.saved}),
            .common => try map.print("common {x:0>8} {d} {d} {s} {s}\n", .{@as(u64, @intCast(c.address)), c.size, c.alignment, c.resolution.?.definer, c.resolution.?.name}),
            .veneer => try map.print("veneer {x:0>8} 8 {s}\n", .{@as(u64, @intCast(c.address)), c.resolution.?.name}),
        }; }
    }
    var order: std.ArrayList(usize) = .empty; for (l.segments.items, 0..) |_, i| try order.append(l.a, i);
    std.mem.sort(usize, order.items, l, struct { fn cmp(linker: *Linker, x: usize, y: usize) bool { const a = linker.segments.items[x].paddr; const b = linker.segments.items[y].paddr; return if (a == b) x < y else a < b; } }.cmp);
    var upper: i64 = 0;
    for (order.items) |i| { const s = l.segments.items[i]; var start: usize = 0; while (start < s.filesz) { const address = s.paddr + @as(i64, @intCast(start)); const n = @min(@min(16, s.filesz - start), @as(usize, @intCast(65536 - @mod(address, 65536)))); if (@divFloor(address, 65536) != upper) { upper = @divFloor(address, 65536); try record(&flash, 4, 0, &.{@intCast(@divFloor(upper, 256)), @intCast(@mod(upper, 256))}); } try record(&flash, 0, @intCast(@mod(address, 65536)), s.image[start..][0..n]); start += n; } }
    var entry_bytes: [4]u8 = undefined; reloc.write(&entry_bytes, l.entryAddress()); std.mem.reverse(u8, &entry_bytes); try record(&flash, 5, 0, &entry_bytes); try record(&flash, 1, 0, &.{});
    var orphans: std.ArrayList(Text) = .empty;
    for (l.objects.items) |o| for (o.sections.items) |s| if (s.discard) |reason| { try map.print("discard {s} {s} {d} {s}\n", .{o.name, s.name, s.size, reason}); if (obj.eq(reason, "orphan")) try resolver.unique(l.a, &orphans, s.name); };
    std.mem.sort(Text, orphans.items, {}, less);
    for (orphans.items) |name| { var count: usize = 0; for (l.objects.items) |o| for (o.sections.items) |s| { if (s.discard != null and obj.eq(s.discard.?, "orphan") and obj.eq(s.name, name)) count += 1; }; try diag.print("warning: orphan section {s} discarded from {d} object(s)\n", .{name, count}); }
    const Row = struct { address: i64, name: Text, kind: Text, definer: Text }; var rows: std.ArrayList(Row) = .empty;
    for (l.names.items) |r| {
        if (r.kind == .common and !r.live) try map.print("discard {s} COMMON({s}) {d} gc\n", .{r.definer, r.name, r.size});
        if (r.kept()) try rows.append(l.a, .{ .address = r.value().?, .name = r.name, .kind = @tagName(r.kind), .definer = r.definer });
        try xref.print("{s} {s} {s} {s} ", .{r.name, @tagName(r.kind), if (r.kind == .@"undefined" or r.kind == .weakundef) "-" else if (r.kept()) "kept" else "discarded", r.definer}); try join(&xref, r.referrers.items, ","); try xref.add("\n");
        if (r.strong.items.len >= 2) { try diag.print("error: multiple definition of {s}: ", .{r.name}); try join(&diag, r.strong.items, " "); try diag.add("\n"); }
        if (r.commons.items.len > 0 and (r.kind == .global or r.kind == .script)) try diag.print("warning: common symbol {s} overridden by {s}\n", .{r.name, r.definer});
        if (r.kind == .common) { var different = false; for (r.commons.items[1..]) |c| { if (c.size != r.commons.items[0].size or c.alignment != r.commons.items[0].alignment) different = true; } if (different) try diag.print("warning: common symbol {s} merged to size {d} align {d}\n", .{r.name, r.size, r.alignment}); }
    }
    for (l.outputs.items) |out| for (out.components.items) |c| if (c.kind == .veneer) { try rows.append(l.a, .{ .address = c.address, .name = try std.fmt.allocPrint(l.a, "__veneer_{s}", .{c.resolution.?.name}), .kind = "veneer", .definer = "*linker*" }); };
    std.mem.sort(Row, rows.items, {}, struct { fn cmp(_: void, x: Row, y: Row) bool { return if (x.address == y.address) less({}, x.name, y.name) else x.address < y.address; } }.cmp);
    for (rows.items) |r| try map.print("symbol {x:0>8} {s} {s} {s}\n", .{@as(u64, @intCast(r.address)), r.name, r.kind, r.definer});
    const en = l.resolution(l.entry); if (en == null or en.?.kind == .@"undefined" or en.?.kind == .weakundef) try diag.print("error: entry symbol {s} is undefined\n", .{l.entry});
    for (l.names.items) |r| if (r.kind == .@"undefined" and r.unresolved.items.len > 0) { try diag.print("error: undefined symbol {s} referenced by ", .{r.name}); try join(&diag, r.unresolved.items, " "); try diag.add("\n"); };
    for (l.segments.items) |s| if (s.used > s.length) { try diag.print("error: segment {s} overflows its length by {d} bytes\n", .{s.name, s.used - s.length}); };
    for (l.segments.items, 0..) |x, i| for (l.segments.items[i + 1..]) |y| { if (x.memsz > 0 and y.memsz > 0 and x.base < y.base + @as(i64, @intCast(y.memsz)) and y.base < x.base + @as(i64, @intCast(x.memsz))) try diag.print("error: segments {s} and {s} overlap\n", .{x.name, y.name}); };
    var counts: [7][4]usize = @splat(@splat(0));
    for (l.applied.items) |r| {
        counts[@intFromEnum(r.kind)][@intFromEnum(r.status)] += 1;
        try report.print("{x:0>8} {s} {s}+{d} {s} {s} {d}", .{@as(u64, @intCast(r.place)), r.section.owner.name, r.section.name, r.offset, @tagName(r.kind), r.symbol.name, r.addend});
        if (r.target) |target| { try report.print(" {x:0>8} {d} ", .{@as(u64, @intCast(target)), r.value}); switch (reloc.width(r.kind)) { 4 => try report.print("{x:0>8}", .{@as(u64, @intCast(r.field))}), 3 => try report.print("{x:0>6}", .{@as(u64, @intCast(r.field))}), else => try report.print("{x:0>4}", .{@as(u64, @intCast(r.field))}) } } else try report.add(" - - -");
        try report.print(" {s}\n", .{@tagName(r.status)});
        if (r.unpaired) try diag.print("error: unpaired HI16 at {s} {s}+{d} against {s}\n", .{r.section.owner.name, r.section.name, r.offset, r.symbol.name});
        if (r.status == .overflow) try diag.print("error: relocation overflow at {s} {s}+{d}: {s} value {d} against {s}\n", .{r.section.owner.name, r.section.name, r.offset, @tagName(r.kind), r.value, r.symbol.name});
    }
    for (counts, 0..) |c, k| try report.print("summary {s} total {d} ok {d} veneer {d} overflow {d} undefined {d}\n", .{@tagName(@as(reloc.Kind, @enumFromInt(k))), c[0] + c[1] + c[2] + c[3], c[0], c[1], c[2], c[3]});
    var errors: usize = 0; var warnings: usize = 0; var lines = std.mem.tokenizeScalar(u8, diag.bytes.items, '\n'); while (lines.next()) |line| { if (std.mem.startsWith(u8, line, "error:")) errors += 1 else if (std.mem.startsWith(u8, line, "warning:")) warnings += 1; } try diag.print("errors {d} warnings {d}\n", .{errors, warnings});
    for ([_]Text{"image.hex", "flash.ihex", "link.map", "xref.txt", "relocations.txt", "diagnostics.txt"}, [_]Text{image.bytes.items, flash.bytes.items, map.bytes.items, xref.bytes.items, report.bytes.items, diag.bytes.items}) |name, data| { const file = try std.Io.Dir.cwd().createFile(l.io, try std.fmt.allocPrint(l.a, "output/{s}", .{name}), .{}); defer file.close(l.io); try file.writeStreamingAll(l.io, data); }
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); var linker: Linker = .{ .a = arena.allocator(), .io = init.io };
    try linker.script(try linker.read("link.txt")); try linker.loadInputs(); try linker.collect(); try linker.build(); try linker.apply(); try outputs(&linker);
}
