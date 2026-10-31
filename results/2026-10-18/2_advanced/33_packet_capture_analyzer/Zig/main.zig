const std = @import("std");
const h = @import("hexdump.zig");
const net = @import("link_network.zig");
const transport = @import("transport.zig");
const dns = @import("dns_app.zig");
const flows = @import("flows.zig");
const Packet = h.Packet;
const Type = enum { integer, hex2, hex4, ipv4, mac, string, presence };
const FieldSpec = struct { name: []const u8, type_: Type };
const field_specs = [_]FieldSpec{
    .{ .name = "frame.number", .type_ = .integer },
    .{ .name = "frame.time", .type_ = .integer },
    .{ .name = "frame.len", .type_ = .integer },
    .{ .name = "frame.protocols", .type_ = .string },
    .{ .name = "frame.malformed", .type_ = .string },
    .{ .name = "frame.bad_checksum", .type_ = .presence },
    .{ .name = "eth.dst", .type_ = .mac },
    .{ .name = "eth.src", .type_ = .mac },
    .{ .name = "eth.type", .type_ = .hex4 },
    .{ .name = "arp.opcode", .type_ = .integer },
    .{ .name = "arp.src.hw", .type_ = .mac },
    .{ .name = "arp.src.ip", .type_ = .ipv4 },
    .{ .name = "arp.dst.hw", .type_ = .mac },
    .{ .name = "arp.dst.ip", .type_ = .ipv4 },
    .{ .name = "ip.hdr_len", .type_ = .integer },
    .{ .name = "ip.tos", .type_ = .hex2 },
    .{ .name = "ip.len", .type_ = .integer },
    .{ .name = "ip.id", .type_ = .hex4 },
    .{ .name = "ip.flags.df", .type_ = .integer },
    .{ .name = "ip.flags.mf", .type_ = .integer },
    .{ .name = "ip.frag_offset", .type_ = .integer },
    .{ .name = "ip.ttl", .type_ = .integer },
    .{ .name = "ip.proto", .type_ = .integer },
    .{ .name = "ip.checksum", .type_ = .hex4 },
    .{ .name = "ip.checksum.status", .type_ = .string },
    .{ .name = "ip.src", .type_ = .ipv4 },
    .{ .name = "ip.dst", .type_ = .ipv4 },
    .{ .name = "ip.fragment", .type_ = .presence },
    .{ .name = "icmp.type", .type_ = .integer },
    .{ .name = "icmp.code", .type_ = .integer },
    .{ .name = "icmp.checksum", .type_ = .hex4 },
    .{ .name = "icmp.checksum.status", .type_ = .string },
    .{ .name = "icmp.id", .type_ = .integer },
    .{ .name = "icmp.seq", .type_ = .integer },
    .{ .name = "udp.srcport", .type_ = .integer },
    .{ .name = "udp.dstport", .type_ = .integer },
    .{ .name = "udp.length", .type_ = .integer },
    .{ .name = "udp.checksum", .type_ = .hex4 },
    .{ .name = "udp.checksum.status", .type_ = .string },
    .{ .name = "tcp.srcport", .type_ = .integer },
    .{ .name = "tcp.dstport", .type_ = .integer },
    .{ .name = "tcp.stream", .type_ = .integer },
    .{ .name = "tcp.seq", .type_ = .integer },
    .{ .name = "tcp.seq_raw", .type_ = .integer },
    .{ .name = "tcp.ack", .type_ = .integer },
    .{ .name = "tcp.ack_raw", .type_ = .integer },
    .{ .name = "tcp.hdr_len", .type_ = .integer },
    .{ .name = "tcp.flags", .type_ = .hex2 },
    .{ .name = "tcp.flags.fin", .type_ = .integer },
    .{ .name = "tcp.flags.syn", .type_ = .integer },
    .{ .name = "tcp.flags.rst", .type_ = .integer },
    .{ .name = "tcp.flags.psh", .type_ = .integer },
    .{ .name = "tcp.flags.ack", .type_ = .integer },
    .{ .name = "tcp.flags.urg", .type_ = .integer },
    .{ .name = "tcp.window", .type_ = .integer },
    .{ .name = "tcp.window.calc", .type_ = .integer },
    .{ .name = "tcp.checksum", .type_ = .hex4 },
    .{ .name = "tcp.checksum.status", .type_ = .string },
    .{ .name = "tcp.urgent", .type_ = .integer },
    .{ .name = "tcp.option", .type_ = .string },
    .{ .name = "tcp.options.mss", .type_ = .integer },
    .{ .name = "tcp.options.wscale", .type_ = .integer },
    .{ .name = "tcp.options.malformed", .type_ = .presence },
    .{ .name = "tcp.len", .type_ = .integer },
    .{ .name = "tcp.analysis.retransmission", .type_ = .presence },
    .{ .name = "tcp.analysis.out_of_order", .type_ = .presence },
    .{ .name = "tcp.analysis.lost_segment", .type_ = .presence },
    .{ .name = "tcp.analysis.duplicate_ack", .type_ = .presence },
    .{ .name = "dns.id", .type_ = .hex4 },
    .{ .name = "dns.flags", .type_ = .hex4 },
    .{ .name = "dns.flags.response", .type_ = .integer },
    .{ .name = "dns.flags.opcode", .type_ = .integer },
    .{ .name = "dns.flags.rcode", .type_ = .integer },
    .{ .name = "dns.count.queries", .type_ = .integer },
    .{ .name = "dns.count.answers", .type_ = .integer },
    .{ .name = "dns.count.auth_rr", .type_ = .integer },
    .{ .name = "dns.count.add_rr", .type_ = .integer },
    .{ .name = "dns.qry.name", .type_ = .string },
    .{ .name = "dns.qry.type", .type_ = .integer },
    .{ .name = "dns.answer", .type_ = .string },
    .{ .name = "dns.authority", .type_ = .string },
    .{ .name = "dns.additional", .type_ = .string },
    .{ .name = "dns.a", .type_ = .ipv4 },
    .{ .name = "data.len", .type_ = .integer },
};
const protocols = [_][]const u8{ "eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data" };
const aliases = [_][3][]const u8{ .{ "eth.addr", "eth.dst", "eth.src" }, .{ "ip.addr", "ip.src", "ip.dst" },
     .{ "udp.port", "udp.srcport", "udp.dstport" }, .{ "tcp.port", "tcp.srcport", "tcp.dstport" } };
fn fieldType(name: []const u8) ?Type {
    for (field_specs) |field| if (h.eq(field.name, name)) return field.type_;
    for (aliases) |alias| if (h.eq(alias[0], name)) return fieldType(alias[1]);
    for (protocols) |protocol| if (h.eq(protocol, name)) return .presence;
    return null;
}
fn fieldValues(p: Packet, name: []const u8) []const h.Value {
    for (protocols) |protocol| if (h.eq(name, protocol)) {
        for (p.layers.items) |layer_name| if (h.eq(layer_name, name)) {
            const value = h.alloc(h.Value, 1);
            value[0] = .{};
            return value;
        };
        return &.{};
    };
    for (aliases) |alias| if (h.eq(name, alias[0])) {
        var values: std.ArrayList(h.Value) = .empty;
        for (p.values(alias[1])) |value| h.append(h.Value, &values, value);
        for (p.values(alias[2])) |value| h.append(h.Value, &values, value);
        return values.items;
    };
    return p.values(name);
}
fn notation(type_: Type, value: h.Value) []const u8 {
    return switch (type_) {
        .hex2 => h.fmt("0x{x:0>2}", .{value.number}),
        .hex4 => h.fmt("0x{x:0>4}", .{value.number}),
        .ipv4 => net.ipv4(value.number),
        .mac => net.mac(value.number),
        .string => value.text,
        .presence => "",
        .integer => h.decimal(value.number),
    };
}
fn valueText(p: Packet, name: []const u8) []const u8 {
    return notation(fieldType(name).?, p.values(name)[0]);
}
const Token = struct { kind: []const u8, text: []const u8, column: usize };
const FilterError = error{Filter};
const Expression = struct {
    kind: enum { or_, and_, not_, field } = .field,
    field: []const u8 = "",
    op: []const u8 = "",
    type_: Type = .integer,
    value: h.Value = .{},
    left: ?*Expression = null,
    right: ?*Expression = null,
    fn evaluate(self: Expression, p: Packet) bool {
        switch (self.kind) {
            .or_ => return self.left.?.evaluate(p) or self.right.?.evaluate(p),
            .and_ => return self.left.?.evaluate(p) and self.right.?.evaluate(p),
            .not_ => return !self.left.?.evaluate(p),
            .field => {},
        }
        const values = fieldValues(p, self.field);
        if (self.op.len == 0) return values.len > 0;
        if (values.len == 0) return false;
        for (values) |value| {
            const comparison: i8 = if (self.type_ == .string) switch (std.mem.order(u8, value.text, self.value.text)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            } else if (value.number < self.value.number) -1 else if (value.number > self.value.number) 1 else 0;
            if (h.eq(self.op, "!=")) {
                if (comparison == 0) return false;
            } else if ((h.eq(self.op, "==") and comparison == 0) or (h.eq(self.op, "<") and comparison < 0) or (h.eq(self.op,
                 ">") and comparison > 0) or (h.eq(self.op, "<=") and comparison <= 0) or (h.eq(self.op,
                 ">=") and comparison >= 0)) return true;
        }
        return h.eq(self.op, "!=");
    }
};
fn wordCharacter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '.' or c == '_' or c == ':';
}
fn digits(text: []const u8, base: u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!((c >= '0' and c <= '9') or (base == 16 and ((c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))))) return false;
    return true;
}
const Parser = struct {
    tokens: []const Token = &.{},
    position: usize = 0,
    reason: []const u8 = "",
    fn fail(self: *Parser, reason: []const u8) FilterError {
        self.reason = reason;
        return error.Filter;
    }
    fn tokenize(self: *Parser, text: []const u8) FilterError!void {
        var tokens: std.ArrayList(Token) = .empty;
        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == ' ') {
                i += 1;
                continue;
            }
            const start = i;
            if (i + 1 < text.len) {
                const pair = text[i .. i + 2];
                var found = false;
                for ([_][]const u8{ "==", "!=", "<=", ">=", "&&", "||" }) |kind| if (h.eq(pair, kind)) {
                    h.append(Token, &tokens, .{ .kind = kind, .text = pair, .column = i + 1 });
                    i += 2;
                    found = true;
                    break;
                };
                if (found) continue;
            }
            if (std.mem.indexOfScalar(u8, "()!<>", text[i]) != null) {
                h.append(Token, &tokens, .{ .kind = text[i .. i + 1], .text = text[i .. i + 1], .column = i + 1 });
                i += 1;
                continue;
            }
            if (text[i] == '"') {
                i += 1;
                while (i < text.len and text[i] != '"') i += 1;
                if (i == text.len) return self.fail(h.fmt("unterminated string at column {d}", .{start + 1}));
                i += 1;
                h.append(Token, &tokens, .{ .kind = "string", .text = text[start..i], .column = start + 1 });
                continue;
            }
            if (wordCharacter(text[i])) {
                while (i < text.len and wordCharacter(text[i])) i += 1;
                const value = text[start..i];
                h.append(Token, &tokens, .{ .kind = if (h.eq(value, "and")) "&&" else if (h.eq(value,
                     "or")) "||" else if (h.eq(value, "not")) "!" else "word", .text = value, .column = start + 1 });
                continue;
            }
            return self.fail(h.fmt("invalid character '{c}' at column {d}", .{ text[i], i + 1 }));
        }
        self.tokens = tokens.items;
    }
    fn next(self: Parser, kind: []const u8) bool {
        return self.position < self.tokens.len and h.eq(self.tokens[self.position].kind, kind);
    }
    fn take(self: *Parser) FilterError!Token {
        if (self.position == self.tokens.len) return self.fail("unexpected end of filter");
        const token = self.tokens[self.position];
        self.position += 1;
        return token;
    }
    fn unexpected(self: *Parser, token: Token) FilterError {
        return self.fail(h.fmt("unexpected '{s}' at column {d}", .{ token.text, token.column }));
    }
    fn convert(self: *Parser, type_: Type, token: Token, field: []const u8) FilterError!h.Value {
        if (type_ == .string and h.eq(token.kind, "string")) return .{ .text = token.text[1 .. token.text.len - 1] };
        if (h.eq(token.kind, "word")) {
            const text = token.text;
            if (type_ == .integer or type_ == .hex2 or type_ == .hex4) {
                if (text.len <= 15 and digits(text, 10)) return .{ .number = h.number(text) };
                if (text.len >= 3 and text.len <= 14 and h.eq(text[0..2], "0x") and digits(text[2..],
                     16)) return .{ .number = std.fmt.parseInt(i64, text[2..], 16) catch unreachable };
            }
            if (type_ == .ipv4 or type_ == .mac) {
                const ip = type_ == .ipv4;
                const parts = h.split(text, if (ip) '.' else ':');
                if (parts.len == (if (ip) @as(usize, 4) else 6)) {
                    var value: i64 = 0;
                    var valid = true;
                    for (parts) |part| {
                        if (!(if (ip) part.len >= 1 and part.len <= 3 and digits(part, 10) else part.len == 2 and digits(part,
                             16))) {
                            valid = false;
                            break;
                        }
                        const byte = std.fmt.parseInt(i64, part, if (ip) 10 else 16) catch unreachable;
                        if (byte > 255) {
                            valid = false;
                            break;
                        }
                        value = value * 256 + byte;
                    }
                    if (valid) return .{ .number = value };
                }
            }
        }
        return self.fail(h.fmt("invalid value {s} for {s}", .{ token.text, field }));
    }
    fn expression(self: *Parser) FilterError!*Expression {
        var node = try self.product();
        while (self.next("||")) {
            _ = try self.take();
            const parent = h.alloc(Expression, 1);
            parent[0] = .{ .kind = .or_, .left = node, .right = try self.product() };
            node = &parent[0];
        }
        return node;
    }
    fn product(self: *Parser) FilterError!*Expression {
        var node = try self.negation();
        while (self.next("&&")) {
            _ = try self.take();
            const parent = h.alloc(Expression, 1);
            parent[0] = .{ .kind = .and_, .left = node, .right = try self.negation() };
            node = &parent[0];
        }
        return node;
    }
    fn negation(self: *Parser) FilterError!*Expression {
        if (self.next("!")) {
            _ = try self.take();
            const node = h.alloc(Expression, 1);
            node[0] = .{ .kind = .not_, .left = try self.negation() };
            return &node[0];
        }
        const token = try self.take();
        if (h.eq(token.kind, "(")) {
            const node = try self.expression();
            const close = try self.take();
            if (!h.eq(close.kind, ")")) return self.unexpected(close);
            return node;
        }
        if (!h.eq(token.kind, "word")) return self.unexpected(token);
        const type_ = fieldType(token.text) orelse return self.fail(h.fmt("unknown field {s}", .{token.text}));
        const storage = h.alloc(Expression, 1);
        const node = &storage[0];
        node.* = .{ .field = token.text, .type_ = type_ };
        if (!(self.next("==") or self.next("!=") or self.next("<") or self.next(">") or self.next("<=") or self.next(">="))) return node;
        node.op = (try self.take()).text;
        if (type_ == .presence or (type_ == .string and !h.eq(node.op, "==") and !h.eq(node.op, "!="))) return self.fail(h.fmt("operator {s} not allowed for {s}",
             .{ node.op, node.field }));
        const value = try self.take();
        if (!h.eq(value.kind, "word") and !h.eq(value.kind, "string")) return self.unexpected(value);
        node.value = try self.convert(type_, value, node.field);
        return node;
    }
    fn parse(self: *Parser, text: []const u8) FilterError!*Expression {
        try self.tokenize(text);
        const result = try self.expression();
        if (self.position != self.tokens.len) return self.unexpected(self.tokens[self.position]);
        return result;
    }
};
fn arpLayer(p: *Packet, bytes: []const u8) h.DissectionError![]const u8 {
    try net.arp(p, bytes);
    return &.{};
}
fn dnsLayer(p: *Packet, bytes: []const u8) h.DissectionError![]const u8 {
    try dns.dissect(p, bytes);
    return &.{};
}
fn layer(p: *Packet, name: []const u8, comptime function: anytype, bytes: []const u8) []const u8 {
    h.append([]const u8, &p.layers, name);
    return function(p, bytes) catch {
        const prefix = h.fmt("{s}.", .{name});
        var iterator = p.fields.iterator();
        while (iterator.next()) |entry| if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) {
            entry.value_ptr.items.len = 0;
        };
        if (h.eq(name, "dns")) p.dns_answers.items.len = 0;
        return &.{};
    };
}
fn dissect(p: *Packet) void {
    if (p.reason != null) return;
    var payload = layer(p, "eth", net.ethernet, p.raw);
    if (p.reason != null) return;
    var remaining: []const u8 = &.{};
    if (p.num("eth.type") == 2054) {
        _ = layer(p, "arp", arpLayer, payload);
    } else if (p.num("eth.type") == 2048) {
        payload = layer(p, "ip", net.internet, payload);
        if (p.reason != null) return;
        if (p.has("ip.fragment")) remaining = payload else if (p.num("ip.proto") == 1) remaining = layer(p,
             "icmp", transport.icmp, payload) else if (p.num("ip.proto") == 17) {
            payload = layer(p, "udp", transport.udp, payload);
            if (p.reason == null) {
                if (p.num("udp.srcport") == 53 or p.num("udp.dstport") == 53) {
                    _ = layer(p, "dns", dnsLayer, payload);
                } else remaining = payload;
            }
        } else if (p.num("ip.proto") == 6) remaining = layer(p, "tcp", transport.tcp, payload) else remaining = payload;
    } else remaining = payload;
    if (p.reason == null and remaining.len > 0) {
        h.append([]const u8, &p.layers, "data");
        p.put("data.len", h.n(remaining.len));
        p.remaining = remaining;
    }
}
fn summary(p: Packet, origin: i64) []const u8 {
    const source = if (p.has("ip.src")) net.ipv4(p.num("ip.src")) else if (p.has("eth.src")) net.mac(p.num("eth.src")) else "-";
    const destination = if (p.has("ip.dst")) net.ipv4(p.num("ip.dst")) else if (p.has("eth.dst")) net.mac(p.num("eth.dst")) else "-";
    var last: []const u8 = "";
    for (p.layers.items) |name| if (!h.eq(name, "data")) {
        last = name;
    };
    var protocol: []const u8 = "DUMP";
    const protocol_names = [_][]const u8{ "ETH", "ARP", "IPv4", "ICMP", "UDP", "TCP", "DNS" };
    for (protocols[0..7], protocol_names) |name, display| if (h.eq(last, name)) {
        protocol = display;
    };
    var info: h.Text = .{};
    if (p.reason) |reason| info.add("{s}", .{reason}) else if (h.eq(last, "eth")) info.add("EtherType {s}",
         .{valueText(p, "eth.type")}) else if (h.eq(last, "arp")) {
        const opcode = p.num("arp.opcode");
        if (opcode == 1) info.add("Who has {s}? Tell {s}", .{ valueText(p, "arp.dst.ip"), valueText(p,
             "arp.src.ip") }) else if (opcode == 2) info.add("{s} is at {s}", .{ valueText(p, "arp.src.ip"),
             valueText(p, "arp.src.hw") }) else info.add("Opcode {d}", .{opcode});
    } else if (h.eq(last, "ip")) {
        if (p.has("ip.fragment")) info.add("Fragment id={s} off={s}{s}", .{ valueText(p, "ip.id"),
             valueText(p, "ip.frag_offset"), if (p.num("ip.flags.mf") != 0) " MF" else "" }) else info.add("Protocol {s}",
             .{valueText(p, "ip.proto")});
    } else if (h.eq(last, "icmp")) {
        const type_ = p.num("icmp.type");
        if (type_ == 0 or type_ == 8) info.add("Echo {s} id={s} seq={s}", .{ if (type_ == 8) "request" else "reply",
             valueText(p, "icmp.id"), valueText(p, "icmp.seq") }) else info.add("Type {d} code {s}",
             .{ type_, valueText(p, "icmp.code") });
    } else if (h.eq(last, "udp")) info.add("{s} -> {s} Len={d}", .{ valueText(p, "udp.srcport"), valueText(p,
         "udp.dstport"), p.num("udp.length") - 8 }) else if (h.eq(last, "tcp")) {
        if (p.has("tcp.analysis.retransmission")) info.add("[TCP Retransmission] ", .{}) else if (p.has("tcp.analysis.out_of_order")) info.add("[TCP Out-Of-Order] ",
             .{}) else if (p.has("tcp.analysis.lost_segment")) info.add("[TCP Previous segment not captured] ",
             .{}) else if (p.has("tcp.analysis.duplicate_ack")) info.add("[TCP Dup ACK {d}#{d}] ",
             .{ p.duplicate_origin, p.duplicate_count });
        var flags: std.ArrayList([]const u8) = .empty;
        for ([_][]const u8{ "FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR" }, 0..) |name,
             bit| if (p.num("tcp.flags") & (@as(i64, 1) << @as(u6, @intCast(bit))) != 0) h.append([]const u8,
             &flags, name);
        info.add("{s} -> {s} [{s}] Seq={s}", .{ valueText(p, "tcp.srcport"), valueText(p, "tcp.dstport"),
             if (flags.items.len == 0) "<None>" else h.join(flags.items, ", "), valueText(p, "tcp.seq") });
        if (p.num("tcp.flags.ack") != 0) info.add(" Ack={s}", .{valueText(p, "tcp.ack")});
        info.add(" Win={s} Len={s}", .{ valueText(p, "tcp.window.calc"), valueText(p, "tcp.len") });
        for (p.values("tcp.option")) |value| {
            const words = h.split(value.text, ' ');
            if (h.eq(words[0], "MSS")) info.add(" MSS={s}", .{words[1]}) else if (h.eq(words[0], "WS")) info.add(" WS={d}",
                 .{@as(i64, 1) << @as(u6, @intCast(h.number(words[1])))}) else if (h.eq(words[0],
                 "SACK_PERM")) info.add(" SACK_PERM", .{}) else if (h.eq(words[0], "TS")) info.add(" TSval={s} TSecr={s}",
                 .{ words[1], words[2] });
        }
    } else if (h.eq(last, "dns")) {
        info.add("{s} {s}", .{ if (p.num("dns.flags.response") != 0) "Response" else "Query", valueText(p, "dns.id") });
        if (p.num("dns.flags.rcode") != 0) info.add(" {s}", .{dns.rcodeName(p.num("dns.flags.rcode"))});
        for (p.values("dns.qry.name"), p.values("dns.qry.type")) |name, type_| info.add(" {s} {s}",
             .{ dns.typeName(type_.number), name.text });
        for (p.dns_answers.items) |answer| info.add(" {s} {s}", .{ dns.typeName(answer.type_), answer.body });
    }
    if (p.has("tcp.options.malformed")) info.add(" [bad TCP options]", .{});
    for ([_][]const u8{ "ip", "icmp", "udp", "tcp" }, [_][]const u8{ "IPv4", "ICMP", "UDP", "TCP" }) |name,
         display| if (h.eq(p.str(h.fmt("{s}.checksum.status", .{name})), "bad")) info.add(" [bad {s} checksum]",
         .{display});
    return h.fmt("{d} {s} {s} -> {s} {s} {d} {s}", .{ p.number, h.seconds(p.time - origin), source,
         destination, protocol, p.length, info.value() });
}
fn optional(value: ?i64) []const u8 {
    return if (value) |v| h.decimal(v) else "-";
}
const NameCount = struct { name: []const u8, count: i64 };
fn nameLess(_: void, a: NameCount, b: NameCount) bool {
    return if (a.count != b.count) a.count > b.count else std.mem.order(u8, a.name, b.name) == .lt;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    h.allocator = arena.allocator();
    const packets = try h.readCapture(init.io);
    const origin = packets[0].time;
    var streams: std.ArrayList(flows.Stream) = .empty;
    const checksum_names = [_][]const u8{ "ip", "icmp", "udp", "tcp" };
    for (packets) |*p| {
        dissect(p);
        flows.track(p, &streams);
        p.put("frame.number", p.number);
        p.put("frame.time", p.time - origin);
        p.put("frame.len", p.length);
        if (p.layers.items.len > 0) p.text("frame.protocols", h.join(p.layers.items, ":"));
        if (p.reason) |reason| p.text("frame.malformed", reason);
        for (checksum_names) |name| if (h.eq(p.str(h.fmt("{s}.checksum.status", .{name})), "bad")) p.flag("frame.bad_checksum");
    }
    var summaries: h.Lines = .{};
    var summary_lines: h.Lines = .{};
    var details: h.Lines = .{};
    for (packets) |p| {
        const line = summary(p, origin);
        summaries.add("{s}", .{line});
        summary_lines.add("{s}", .{line});
    }
    var first_detail = true;
    for (try h.readLines(init.io, "input/filters.txt")) |request| {
        if (request.len == 0 or request[0] == '#') continue;
        if (std.mem.startsWith(u8, request, "FILTER ")) {
            const text = request[7..];
            summary_lines.add("", .{});
            summary_lines.add("filter {s}", .{text});
            var parser: Parser = .{};
            const expression = parser.parse(text) catch {
                summary_lines.add("error: {s}", .{parser.reason});
                continue;
            };
            var matched: usize = 0;
            for (packets, summaries.data.items) |p, line| if (expression.evaluate(p)) {
                summary_lines.add("{s}", .{line});
                matched += 1;
            };
            summary_lines.add("matched {d} of {d}", .{ matched, packets.len });
        } else {
            if (!first_detail) details.add("", .{});
            first_detail = false;
            const number = h.number(request[7..]);
            if (number < 1 or number > h.n(packets.len)) {
                details.add("packet {d} not found", .{number});
                continue;
            }
            const p = packets[h.u(number - 1)];
            details.add("packet {d}", .{number});
            var layers: std.ArrayList([]const u8) = .empty;
            h.append([]const u8, &layers, "frame");
            for (p.layers.items) |name| h.append([]const u8, &layers, name);
            for (layers.items) |name| {
                details.add("{s}", .{name});
                const prefix = h.fmt("{s}.", .{name});
                for (field_specs) |field| if (std.mem.startsWith(u8, field.name, prefix)) {
                    for (p.values(field.name)) |value| {
                        if (field.type_ == .presence) details.add("  {s}", .{field.name}) else details.add("  {s} = {s}",
                             .{ field.name, notation(field.type_, value) });
                    }
                };
                if (h.eq(name, "data")) for (h.dumpLines(p.remaining).data.items) |line| details.add("  {s}", .{line});
            }
        }
    }
    var conversation_lines: h.Lines = .{};
    conversation_lines.add("type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration",
         .{});
    const kinds = [_][]const u8{ "ipv4", "tcp", "udp" };
    for (flows.conversations(packets)) |c| conversation_lines.add("{s},{s},{s},{d},{d},{d},{d},{d},{d},{s},{s}",
         .{ kinds[c.kind], flows.endpoint(c.a, c.kind != 0), flows.endpoint(c.b, c.kind != 0), c.packets[0] + c.packets[1],
         c.bytes[0] + c.bytes[1], c.packets[0], c.bytes[0], c.packets[1], c.bytes[1], h.seconds(c.start - origin),
         h.seconds(c.end - c.start) });
    var endpoint_lines: h.Lines = .{};
    endpoint_lines.add("address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes", .{});
    for (flows.endpoints(packets)) |e| endpoint_lines.add("{s},{d},{d},{d},{d},{d},{d}", .{ net.ipv4(e.address),
         e.packets[0] + e.packets[1], e.bytes[0] + e.bytes[1], e.packets[0], e.bytes[0], e.packets[1],
         e.bytes[1] });
    var hierarchy = std.mem.zeroes([8][2]i64);
    var checksum_counts = std.mem.zeroes([4][3]i64);
    var malformed = std.mem.zeroes([8]i64);
    var marks = std.mem.zeroes([4]i64);
    var rcodes = std.mem.zeroes([16]i64);
    var pending: std.ArrayList(usize) = .empty;
    var response_times: std.ArrayList(i64) = .empty;
    var names = std.StringHashMap(i64).init(h.allocator);
    var queries: i64 = 0;
    var responses: i64 = 0;
    var total_bytes: i64 = 0;
    for (packets, 0..) |p, index| {
        total_bytes += p.length;
        for (p.layers.items) |name| for (protocols, 0..) |protocol, i| if (h.eq(name, protocol)) {
            hierarchy[i][0] += 1;
            hierarchy[i][1] += p.length;
        };
        for (checksum_names, 0..) |name, i| {
            const field = h.fmt("{s}.checksum.status", .{name});
            if (!p.has(field)) continue;
            const status = p.str(field);
            checksum_counts[i][if (h.eq(status, "good")) @as(usize, 0) else if (h.eq(status, "bad")) 1 else 2] += 1;
        }
        if (p.reason != null) {
            if (p.layers.items.len == 0) malformed[0] += 1 else {
                const last = p.layers.items[p.layers.items.len - 1];
                for (protocols[0..7], 0..) |name, i| if (h.eq(last, name)) {
                    malformed[i + 1] += 1;
                };
            }
        }
        for (flows.mark_names, 0..) |mark, i| if (p.has(h.fmt("tcp.analysis.{s}", .{mark}))) {
            marks[i] += 1;
        };
        if (!p.has("dns.id")) continue;
        if (p.num("dns.flags.response") == 0) {
            queries += 1;
            h.append(usize, &pending, index);
            for (p.values("dns.qry.name")) |value| names.put(value.text, (names.get(value.text) orelse 0) + 1) catch @panic("allocation failed");
        } else {
            responses += 1;
            rcodes[h.u(p.num("dns.flags.rcode"))] += 1;
            for (pending.items, 0..) |query, i| {
                const q = packets[query];
                if (q.num("dns.id") == p.num("dns.id") and q.num("ip.src") == p.num("ip.dst") and q.num("ip.dst") == p.num("ip.src") and q.num("udp.srcport") == p.num("udp.dstport") and q.num("udp.dstport") == p.num("udp.srcport")) {
                    h.append(i64, &response_times, p.time - q.time);
                    _ = pending.orderedRemove(i);
                    break;
                }
            }
        }
    }
    var stats: h.Lines = .{};
    stats.add("packets {d}", .{packets.len});
    stats.add("bytes {d}", .{total_bytes});
    stats.add("duration {s}", .{h.seconds(packets[packets.len - 1].time - origin)});
    stats.add("hierarchy", .{});
    for ([_]usize{ 0, 1, 2, 3, 4, 6, 5 }, [_][]const u8{ "", "  ", "  ", "    ", "    ", "      ",
         "    " }) |index, indent| stats.add("{s}{s} {d} {d}", .{ indent, protocols[index], hierarchy[index][0],
         hierarchy[index][1] });
    stats.add("checksums", .{});
    for (checksum_names, 0..) |name, i| stats.add("{s} good {d} bad {d}{s}", .{ name, checksum_counts[i][0],
         checksum_counts[i][1], if (i == 2) h.fmt(" none {d}", .{checksum_counts[i][2]}) else "" });
    stats.add("malformed", .{});
    for ([_][]const u8{ "dump", "eth", "arp", "ip", "icmp", "udp", "tcp", "dns" }, malformed) |name,
         count| stats.add("{s} {d}", .{ name, count });
    stats.add("tcp analysis", .{});
    for (flows.mark_names, marks) |name, count| stats.add("{s} {d}", .{ name, count });
    stats.add("dns", .{});
    stats.add("queries {d}", .{queries});
    stats.add("responses {d}", .{responses});
    stats.add("transactions {d}", .{response_times.items.len});
    stats.add("unanswered {d}", .{pending.items.len});
    if (response_times.items.len == 0) stats.add("response_time -", .{}) else {
        var minimum = response_times.items[0];
        var maximum = minimum;
        for (response_times.items) |value| {
            minimum = @min(minimum, value);
            maximum = @max(maximum, value);
        }
        stats.add("response_time min {s} max {s}", .{ h.seconds(minimum), h.seconds(maximum) });
    }
    for (rcodes, 0..) |count, code| if (count > 0) stats.add("rcode {s} {d}", .{ dns.rcodeName(h.n(code)), count });
    stats.add("names", .{});
    var name_counts: std.ArrayList(NameCount) = .empty;
    var iterator = names.iterator();
    while (iterator.next()) |entry| h.append(NameCount, &name_counts, .{ .name = entry.key_ptr.*, .count = entry.value_ptr.* });
    std.mem.sort(NameCount, name_counts.items, {}, nameLess);
    for (name_counts.items) |entry| stats.add("{s} {d}", .{ entry.name, entry.count });
    var stream_lines: h.Lines = .{};
    for (streams.items, 0..) |s, index| {
        if (index > 0) stream_lines.add("", .{});
        stream_lines.add("stream {d} {s} -> {s}", .{ index, flows.endpoint(s.client, true), flows.endpoint(s.server, true) });
        stream_lines.add("packets {d} bytes {d} start {s} duration {s}", .{ s.packets, s.bytes, h.seconds(s.start - origin),
             h.seconds(s.end - s.start) });
        var states: h.Text = .{};
        for (s.history.items, 0..) |state, i| states.add("{s}{s} {d}", .{ if (i == 0) "" else ", ", state.state, state.packet });
        stream_lines.add("states {s}", .{states.value()});
        const rtt = if (s.handshake[0] != null and s.handshake[2] != null) h.seconds(packets[h.u(s.handshake[2].? - 1)].time - packets[h.u(s.handshake[0].? - 1)].time) else "-";
        stream_lines.add("handshake syn {s} syn_ack {s} ack {s} rtt {s}", .{ optional(s.handshake[0]),
             optional(s.handshake[1]), optional(s.handshake[2]), rtt });
        stream_lines.add("options client mss {s} wscale {s} server mss {s} wscale {s}", .{ optional(s.sides[0].mss),
             optional(s.sides[0].ws), optional(s.sides[1].mss), optional(s.sides[1].ws) });
        for (s.sides, 0..) |side, i| stream_lines.add("{s} packets {d} payload {d} retransmission {d} out_of_order {d} lost_segment {d} duplicate_ack {d}",
             .{ if (i == 0) "client" else "server", side.packets, side.payload, side.marks[0], side.marks[1],
             side.marks[2], side.marks[3] });
        for (s.events.items) |event| stream_lines.add("event {d} {s} {s} seq {d} len {d}", .{ event.packet,
             if (event.side == 0) "client" else "server", flows.mark_names[event.mark], event.sequence,
             event.length });
    }
    try h.writeLines(init.io, "summary.txt", summary_lines);
    try h.writeLines(init.io, "details.txt", details);
    try h.writeLines(init.io, "conversations.csv", conversation_lines);
    try h.writeLines(init.io, "endpoints.csv", endpoint_lines);
    try h.writeLines(init.io, "protocol_stats.txt", stats);
    try h.writeLines(init.io, "tcp_streams.txt", stream_lines);
}
