const std = @import("std");
const h = @import("hexdump.zig");
const net = @import("link_network.zig");
const Packet = h.Packet;
fn pseudo(p: *Packet, data: []const u8, protocol: u8) []const u8 {
    const result = h.alloc(u8, data.len + 12);
    var cursor: usize = 0;
    for ([_][]const u8{ "ip.src", "ip.dst" }) |field| for (0..4) |i| {
        result[cursor] = @intCast((p.num(field) >> @as(u6, @intCast((3 - i) * 8))) & 255);
        cursor += 1;
    };
    result[8] = 0;
    result[9] = protocol;
    result[10] = @intCast(data.len / 256);
    result[11] = @intCast(data.len % 256);
    @memcpy(result[12..], data);
    return result;
}
pub fn icmp(p: *Packet, b: []const u8) h.DissectionError![]const u8 {
    if (b.len < 8) return p.fail("icmp: truncated");
    p.put("icmp.type", b[0]);
    p.put("icmp.code", b[1]);
    p.put("icmp.checksum", net.integer(b, 2, 2));
    p.text("icmp.checksum.status", net.checksum(b));
    if (b[0] == 0 or b[0] == 8) {
        p.put("icmp.id", net.integer(b, 4, 2));
        p.put("icmp.seq", net.integer(b, 6, 2));
    }
    return b[8..];
}
pub fn udp(p: *Packet, b: []const u8) h.DissectionError![]const u8 {
    if (b.len < 8) return p.fail("udp: truncated");
    const length = h.u(net.integer(b, 4, 2));
    if (length < 8 or length > b.len) return p.fail(h.fmt("udp: bad length {d}", .{length}));
    p.put("udp.srcport", net.integer(b, 0, 2));
    p.put("udp.dstport", net.integer(b, 2, 2));
    p.put("udp.length", h.n(length));
    p.put("udp.checksum", net.integer(b, 6, 2));
    p.text("udp.checksum.status", if (p.num("udp.checksum") == 0) "none" else net.checksum(pseudo(p, b[0..length], 17)));
    return b[8..length];
}
pub fn tcp(p: *Packet, b: []const u8) h.DissectionError![]const u8 {
    if (b.len < 20) return p.fail("tcp: truncated header");
    const header = @as(usize, b[12] / 16) * 4;
    if (header < 20) return p.fail(h.fmt("tcp: bad header length {d}", .{header}));
    if (header > b.len) return p.fail("tcp: truncated header");
    p.put("tcp.srcport", net.integer(b, 0, 2));
    p.put("tcp.dstport", net.integer(b, 2, 2));
    p.put("tcp.seq_raw", net.integer(b, 4, 4));
    p.put("tcp.hdr_len", h.n(header));
    p.put("tcp.flags", b[13]);
    for ([_][]const u8{ "fin", "syn", "rst", "psh", "ack", "urg" }, 0..) |name, i| p.put(h.fmt("tcp.flags.{s}",
         .{name}), (b[13] >> @as(u3, @intCast(i))) & 1);
    if (b[13] & 16 != 0) p.put("tcp.ack_raw", net.integer(b, 8, 4));
    p.put("tcp.window", net.integer(b, 14, 2));
    p.put("tcp.checksum", net.integer(b, 16, 2));
    p.text("tcp.checksum.status", net.checksum(pseudo(p, b, 6)));
    p.put("tcp.urgent", net.integer(b, 18, 2));
    p.put("tcp.len", h.n(b.len - header));
    var i: usize = 20;
    while (i < header) {
        const kind = b[i];
        if (kind == 0) {
            p.set("tcp.option", .{ .text = "EOL" }, true);
            break;
        }
        if (kind == 1) {
            p.set("tcp.option", .{ .text = "NOP" }, true);
            i += 1;
            continue;
        }
        const length: usize = if (i + 1 < header) b[i + 1] else 0;
        if (length < 2 or i + length > header or (kind == 2 and length != 4) or (kind == 3 and length != 3) or (kind == 4 and length != 2) or (kind == 5 and length != 10 and length != 18 and length != 26 and length != 34) or (kind == 8 and length != 10)) {
            p.flag("tcp.options.malformed");
            break;
        }
        var option: []const u8 = undefined;
        if (kind == 2) {
            const value = net.integer(b, i + 2, 2);
            option = h.fmt("MSS {d}", .{value});
            p.put("tcp.options.mss", value);
        } else if (kind == 3) {
            option = h.fmt("WS {d}", .{b[i + 2]});
            p.put("tcp.options.wscale", b[i + 2]);
        } else if (kind == 4) option = "SACK_PERM" else if (kind == 5) {
            var text: h.Text = .{};
            text.add("SACK", .{});
            var j = i + 2;
            while (j < i + length) : (j += 8) text.add(" {d}-{d}", .{ net.integer(b, j, 4), net.integer(b, j + 4, 4) });
            option = text.value();
        } else if (kind == 8) option = h.fmt("TS {d} {d}", .{ net.integer(b, i + 2, 4), net.integer(b,
             i + 6, 4) }) else option = h.fmt("kind {d} len {d}", .{ kind, length });
        p.set("tcp.option", .{ .text = option }, true);
        i += length;
    }
    return b[header..];
}
