const h = @import("hexdump.zig");
const net = @import("link_network.zig");
const Packet = h.Packet;
pub fn typeName(value: i64) []const u8 {
    return switch (value) {
        1 => "A",
        2 => "NS",
        5 => "CNAME",
        6 => "SOA",
        12 => "PTR",
        15 => "MX",
        16 => "TXT",
        28 => "AAAA",
        else => h.fmt("TYPE{d}", .{value}),
    };
}
pub fn rcodeName(value: i64) []const u8 {
    const names = [_][]const u8{ "NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused" };
    return if (value < 6) names[h.u(value)] else h.fmt("RCODE{d}", .{value});
}
const Reader = struct {
    packet: *Packet,
    bytes: []const u8,
    fn need(self: Reader, position: usize, count: usize) h.DissectionError!void {
        if (position > self.bytes.len or count > self.bytes.len - position) return self.packet.fail("dns: truncated");
    }
    fn integer(self: Reader, position: *usize, count: usize) h.DissectionError!i64 {
        try self.need(position.*, count);
        const value = net.integer(self.bytes, position.*, count);
        position.* += count;
        return value;
    }
    fn name(self: Reader, position: *usize) h.DissectionError![]const u8 {
        var cursor = position.*;
        var end: ?usize = null;
        var pointers: usize = 0;
        var labels: h.Text = .{};
        var first = true;
        while (true) {
            try self.need(cursor, 1);
            const count = self.bytes[cursor];
            if (count == 0) {
                if (end == null) end = cursor + 1;
                break;
            }
            if (count >= 192) {
                try self.need(cursor + 1, 1);
                if (end == null) end = cursor + 2;
                pointers += 1;
                if (pointers > 16) return self.packet.fail("dns: compression loop");
                const target = @as(usize, count - 192) * 256 + self.bytes[cursor + 1];
                if (target >= self.bytes.len) return self.packet.fail("dns: pointer out of range");
                cursor = target;
                continue;
            }
            if (count >= 64) return self.packet.fail("dns: bad label type");
            try self.need(cursor + 1, count);
            if (!first) labels.add(".", .{});
            first = false;
            for (self.bytes[cursor + 1 .. cursor + 1 + count]) |c| {
                if (c >= 33 and c <= 126 and c != 46 and c != 92) labels.add("{c}", .{c}) else labels.add("\\{d:0>3}", .{c});
            }
            cursor += @as(usize, count) + 1;
        }
        position.* = end.?;
        return if (first) "<root>" else labels.value();
    }
    fn ipv6(self: Reader, position: *usize) h.DissectionError![]const u8 {
        var values: [8]i64 = undefined;
        var groups: [8][]const u8 = undefined;
        for (&values, &groups) |*value, *group| {
            value.* = try self.integer(position, 2);
            group.* = h.fmt("{x}", .{value.*});
        }
        var start: ?usize = null;
        var length: usize = 1;
        var i: usize = 0;
        while (i < 8) {
            if (values[i] != 0) {
                i += 1;
                continue;
            }
            var end = i;
            while (end < 8 and values[end] == 0) end += 1;
            if (end - i > length) {
                start = i;
                length = end - i;
            }
            i = end;
        }
        return if (start) |s| h.fmt("{s}::{s}", .{ h.join(groups[0..s], ":"), h.join(groups[s + length ..],
             ":") }) else h.join(&groups, ":");
    }
};
pub fn dissect(p: *Packet, bytes: []const u8) h.DissectionError!void {
    const reader: Reader = .{ .packet = p, .bytes = bytes };
    try reader.need(0, 12);
    var position: usize = 0;
    p.put("dns.id", try reader.integer(&position, 2));
    const flags = try reader.integer(&position, 2);
    p.put("dns.flags", flags);
    p.put("dns.flags.response", (flags >> 15) & 1);
    p.put("dns.flags.opcode", (flags >> 11) & 15);
    p.put("dns.flags.rcode", flags & 15);
    var counts: [4]i64 = undefined;
    for ([_][]const u8{ "queries", "answers", "auth_rr", "add_rr" }, &counts) |name, *count| {
        count.* = try reader.integer(&position, 2);
        p.put(h.fmt("dns.count.{s}", .{name}), count.*);
    }
    for (0..h.u(counts[0])) |_| {
        const name = try reader.name(&position);
        try reader.need(position, 4);
        const type_ = try reader.integer(&position, 2);
        position += 2;
        p.set("dns.qry.name", .{ .text = name }, true);
        p.set("dns.qry.type", .{ .number = type_ }, true);
    }
    for ([_][]const u8{ "dns.answer", "dns.authority", "dns.additional" }, 0..) |section, section_index| for (0..h.u(counts[section_index + 1])) |_| {
        const owner = try reader.name(&position);
        try reader.need(position, 10);
        const type_ = try reader.integer(&position, 2);
        const class = try reader.integer(&position, 2);
        const ttl = try reader.integer(&position, 4);
        const length = h.u(try reader.integer(&position, 2));
        try reader.need(position, length);
        const end = position + length;
        var body: []const u8 = undefined;
        var address: i64 = 0;
        if (type_ == 1) {
            address = try reader.integer(&position, 4);
            body = net.ipv4(address);
        } else if (type_ == 28) body = try reader.ipv6(&position) else if (type_ == 2 or type_ == 5 or type_ == 12) body = try reader.name(&position) else if (type_ == 15) {
            const preference = try reader.integer(&position, 2);
            const name = try reader.name(&position);
            body = h.fmt("{d} {s}", .{ preference, name });
        } else if (type_ == 6) {
            const first = try reader.name(&position);
            const second = try reader.name(&position);
            var text: h.Text = .{};
            text.add("{s} {s}", .{ first, second });
            for (0..5) |_| text.add(" {d}", .{try reader.integer(&position, 4)});
            body = text.value();
        } else {
            body = h.fmt("{d} bytes", .{length});
            position = end;
        }
        if (position != end) return p.fail("dns: bad rdata length");
        p.set(section, .{ .text = h.fmt("{s} {s} {s} {d} {s}", .{ owner, typeName(type_), if (class == 1) "IN" else h.fmt("CLASS{d}",
             .{class}), ttl, body }) }, true);
        if (section_index == 0) {
            h.append(h.Answer, &p.dns_answers, .{ .type_ = type_, .body = body });
            if (type_ == 1) p.set("dns.a", .{ .number = address }, true);
        }
    };
}
