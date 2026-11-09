const obj = @import("object_parser.zig");
pub const Kind = @FieldType(obj.Relocation, "kind");
pub fn width(k: Kind) usize { return switch (k) { .ABS32, .REL32 => 4, .CALL24 => 3, else => 2 }; }
pub fn paired(relocations: []const *obj.Relocation, index: usize) bool {
    const r = relocations[index]; if (r.kind != .HI16) return true; if (index + 1 == relocations.len) return false; const next = relocations[index + 1]; return next.kind == .LO16 and next.symbol == r.symbol and next.addend == r.addend;
}
pub fn far(v: i64) bool { return v < -33554432 or v >= 33554432; }
pub fn apply(r: *obj.Relocation, gp: i64) void {
    const s = r.target orelse { r.status = .@"undefined"; return; };
    var v = s + r.addend; if (r.kind == .REL32 or r.kind == .CALL24) v -= r.place else if (r.kind == .GPREL16) v -= gp;
    r.value = v;
    const good = switch (r.kind) { .ABS32, .HI16 => v >= -2147483648 and v < 4294967296, .REL32 => v >= -2147483648 and v < 2147483648, .ABS16 => v >= -32768 and v < 65536, .GPREL16 => v >= -32768 and v < 32768, .CALL24 => !far(v), .LO16 => true };
    r.field = switch (r.kind) { .HI16 => @mod(@divFloor(@mod(v, 4294967296) + 32768, 65536), 65536), .CALL24 => @mod(@divFloor(v, 4), 16777216), else => @mod(v, @as(i64, 1) << @intCast(8 * width(r.kind))) };
    if (!good) r.status = .overflow;
    write(r.section.contents.items[r.offset..][0..width(r.kind)], r.field);
}
pub fn write(bytes: []u8, value: i64) void { for (bytes, 0..) |*byte, i| byte.* = @intCast(@mod(@divFloor(value, @as(i64, 1) << @intCast(i * 8)), 256)); }
