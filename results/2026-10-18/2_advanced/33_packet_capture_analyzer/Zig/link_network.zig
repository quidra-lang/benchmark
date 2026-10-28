const h = @import("hexdump.zig");
const Packet = h.Packet;
pub fn integer(data: []const u8, position: usize, count: usize) i64 {
    var value: i64 = 0;
    for (data[position .. position + count]) |byte| value = value * 256 + byte;
    return value;
}
pub fn checksum(data: []const u8) []const u8 {
    var sum: i64 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 2) sum += @as(i64, data[i]) * 256 + if (i + 1 < data.len) @as(i64, data[i + 1]) else 0;
    while (sum > 65535) sum = (sum & 65535) + (sum >> 16);
    return if (sum == 65535) "good" else "bad";
}
pub fn mac(address: i64) []const u8 {
    var parts: [6][]const u8 = undefined;
    for (&parts, 0..) |*part, i| part.* = h.fmt("{x:0>2}", .{(address >> @as(u6, @intCast((5 - i) * 8))) & 255});
    return h.join(&parts, ":");
}
pub fn ipv4(address: i64) []const u8 {
    return h.fmt("{d}.{d}.{d}.{d}", .{ (address >> 24) & 255, (address >> 16) & 255, (address >> 8) & 255, address & 255 });
}
pub fn ethernet(p: *Packet, b: []const u8) h.DissectionError![]const u8 {
    if (b.len < 14) return p.fail("eth: truncated");
    p.put("eth.dst", integer(b, 0, 6));
    p.put("eth.src", integer(b, 6, 6));
    p.put("eth.type", integer(b, 12, 2));
    return b[14..];
}
pub fn arp(p: *Packet, b: []const u8) h.DissectionError!void {
    if (b.len < 28) return p.fail("arp: truncated");
    if (integer(b, 0, 2) != 1 or integer(b, 2, 2) != 2048 or b[4] != 6 or b[5] != 4) return p.fail("arp: unsupported format");
    p.put("arp.opcode", integer(b, 6, 2));
    p.put("arp.src.hw", integer(b, 8, 6));
    p.put("arp.src.ip", integer(b, 14, 4));
    p.put("arp.dst.hw", integer(b, 18, 6));
    p.put("arp.dst.ip", integer(b, 24, 4));
}
pub fn internet(p: *Packet, b: []const u8) h.DissectionError![]const u8 {
    if (b.len < 20) return p.fail("ip: truncated header");
    const version = b[0] / 16;
    const header = @as(usize, b[0] % 16) * 4;
    if (version != 4) return p.fail(h.fmt("ip: bad version {d}", .{version}));
    if (header < 20) return p.fail(h.fmt("ip: bad header length {d}", .{header}));
    if (b.len < header) return p.fail("ip: truncated header");
    const total = h.u(integer(b, 2, 2));
    const flags = integer(b, 6, 2);
    if (total < header) return p.fail(h.fmt("ip: bad total length {d}", .{total}));
    if (total > b.len) return p.fail(h.fmt("ip: truncated (total length {d}, available {d})", .{ total, b.len }));
    p.put("ip.hdr_len", h.n(header));
    p.put("ip.tos", b[1]);
    p.put("ip.len", h.n(total));
    p.put("ip.id", integer(b, 4, 2));
    p.put("ip.flags.df", (flags >> 14) & 1);
    p.put("ip.flags.mf", (flags >> 13) & 1);
    p.put("ip.frag_offset", @mod(flags, 8192) * 8);
    p.put("ip.ttl", b[8]);
    p.put("ip.proto", b[9]);
    p.put("ip.checksum", integer(b, 10, 2));
    p.text("ip.checksum.status", checksum(b[0..header]));
    p.put("ip.src", integer(b, 12, 4));
    p.put("ip.dst", integer(b, 16, 4));
    if (p.num("ip.flags.mf") != 0 or p.num("ip.frag_offset") != 0) p.flag("ip.fragment");
    return b[header..total];
}
