const std = @import("std");
const h = @import("hexdump.zig");
const net = @import("link_network.zig");
const Packet = h.Packet;
pub const mark_names = [_][]const u8{ "retransmission", "out_of_order", "lost_segment", "duplicate_ack" };
pub const Endpoint = struct {
    address: i64 = 0,
    port: i64 = 0,
    fn equal(a: Endpoint, b: Endpoint) bool {
        return a.address == b.address and a.port == b.port;
    }
};
pub const Side = struct { isn: ?i64 = null, mss: ?i64 = null, ws: ?i64 = null, base: ?i64 = null,
     expected: ?i64 = null, advanced: i64 = 0, packets: i64 = 0, payload: i64 = 0, intervals: std.AutoHashMapUnmanaged([2]i64,
     void) = .empty, previous_ack: ?[4]i64 = null, marks: [4]i64 = @splat(0) };
pub const Event = struct { packet: i64, side: usize, mark: usize, sequence: i64, length: i64 };
pub const State = struct { state: []const u8, packet: i64 };
pub const Stream = struct { client: Endpoint = .{}, server: Endpoint = .{}, state: []const u8 = "",
     history: std.ArrayList(State) = .empty, start: i64 = 0, end: i64 = 0, packets: i64 = 0, bytes: i64 = 0,
     f2: i64 = 0, handshake: [3]?i64 = @splat(null), sides: [2]Side = .{ .{}, .{} }, events: std.ArrayList(Event) = .empty,
     first_close: ?usize = null };
fn mod32(value: i64) i64 {
    return @mod(value, @as(i64, 1) << 32);
}
fn recordSyn(stream: *Stream, p: *Packet, side: usize) void {
    const s = &stream.sides[side];
    s.isn = p.num("tcp.seq_raw");
    s.mss = if (p.has("tcp.options.mss")) p.num("tcp.options.mss") else null;
    s.ws = if (p.has("tcp.options.wscale")) p.num("tcp.options.wscale") else null;
    stream.handshake[if (side == 0) @as(usize, 0) else 1] = p.number;
}
pub fn track(p: *Packet, streams: *std.ArrayList(Stream)) void {
    if (!p.has("tcp.srcport")) return;
    const source: Endpoint = .{ .address = p.num("ip.src"), .port = p.num("tcp.srcport") };
    const destination: Endpoint = .{ .address = p.num("ip.dst"), .port = p.num("tcp.dstport") };
    const syn = p.num("tcp.flags.syn") != 0;
    const ack_set = p.num("tcp.flags.ack") != 0;
    const fin = p.num("tcp.flags.fin") != 0;
    const rst = p.num("tcp.flags.rst") != 0;
    var index: ?usize = null;
    var i = streams.items.len;
    while (i > 0) {
        i -= 1;
        const stream = streams.items[i];
        if ((source.equal(stream.client) and destination.equal(stream.server)) or (destination.equal(stream.client) and source.equal(stream.server))) {
            index = i;
            break;
        }
    }
    if (index == null or ((h.eq(streams.items[index.?].state, "CLOSED") or h.eq(streams.items[index.?].state,
         "RESET")) and syn and !ack_set)) {
        var stream: Stream = .{ .start = p.time };
        if (syn and ack_set) {
            stream.client = destination;
            stream.server = source;
            stream.state = "SYN_RECEIVED";
            recordSyn(&stream, p, 1);
        } else {
            stream.client = source;
            stream.server = destination;
            stream.state = if (syn) "SYN_SENT" else "ESTABLISHED";
            if (syn) recordSyn(&stream, p, 0);
        }
        h.append(State, &stream.history, .{ .state = stream.state, .packet = p.number });
        index = streams.items.len;
        h.append(Stream, streams, stream);
    }
    const stream = &streams.items[index.?];
    p.put("tcp.stream", h.n(index.?));
    const side: usize = if (source.equal(stream.client)) 0 else 1;
    const s = &stream.sides[side];
    const other = &stream.sides[1 - side];
    const sequence = p.num("tcp.seq_raw");
    const ack = p.num("tcp.ack_raw");
    if (s.base == null) s.base = sequence;
    if (ack_set and other.base == null) other.base = ack;
    const relative = mod32(sequence - s.base.?);
    const length = p.num("tcp.len") + @as(i64, @intFromBool(syn)) + @as(i64, @intFromBool(fin));
    p.put("tcp.seq", relative);
    if (ack_set) p.put("tcp.ack", mod32(ack - other.base.?));
    var mark: ?usize = null;
    if (length > 0) {
        if (s.expected != null and relative > s.expected.?) mark = 2 else if (s.expected != null and relative < s.expected.?) mark = if (s.intervals.contains(.{ relative,
             length }) or p.time - s.advanced >= 3000) @as(usize, 0) else 1;
        s.intervals.put(h.allocator, .{ relative, length }, {}) catch @panic("allocation failed");
        if (s.expected == null or relative + length > s.expected.?) {
            s.expected = relative + length;
            s.advanced = p.time;
        }
    } else if (ack_set and !rst and s.previous_ack != null and s.previous_ack.?[0] == ack and s.previous_ack.?[1] == p.num("tcp.window")) {
        mark = 3;
        s.previous_ack.?[3] += 1;
        p.duplicate_origin = s.previous_ack.?[2];
        p.duplicate_count = s.previous_ack.?[3];
    }
    if (ack_set and (mark == null or mark.? != 3)) s.previous_ack = .{ ack, p.num("tcp.window"), p.number, 0 };
    if (mark) |m| {
        p.flag(h.fmt("tcp.analysis.{s}", .{mark_names[m]}));
        s.marks[m] += 1;
        h.append(Event, &stream.events, .{ .packet = p.number, .side = side, .mark = m, .sequence = relative, .length = length });
    }
    p.put("tcp.window.calc", p.num("tcp.window") * if (stream.sides[0].ws != null and stream.sides[1].ws != null and !syn) (@as(i64,
         1) << @as(u6, @intCast(s.ws.?))) else @as(i64, 1));
    const previous = stream.state;
    if (rst) {
        if (!h.eq(previous, "CLOSED") and !h.eq(previous, "RESET")) stream.state = "RESET";
    } else if (h.eq(previous, "SYN_SENT") and side == 1 and syn and ack_set and stream.sides[0].isn != null and ack == mod32(stream.sides[0].isn.? + 1)) {
        stream.state = "SYN_RECEIVED";
        recordSyn(stream, p, 1);
    } else if (h.eq(previous, "SYN_RECEIVED") and side == 0 and ack_set and !syn and stream.sides[1].isn != null and ack == mod32(stream.sides[1].isn.? + 1)) {
        stream.state = "ESTABLISHED";
        stream.handshake[2] = p.number;
    } else if (h.eq(previous, "ESTABLISHED") and fin) {
        stream.state = "FIN_WAIT";
        stream.first_close = side;
    } else if (h.eq(previous, "FIN_WAIT") and fin and side != stream.first_close.?) {
        stream.state = "CLOSING";
        stream.f2 = mod32(sequence + p.num("tcp.len") + 1);
    } else if (h.eq(previous, "CLOSING") and side == stream.first_close.? and ack_set and ack == stream.f2) stream.state = "CLOSED";
    if (!h.eq(stream.state, previous)) h.append(State, &stream.history, .{ .state = stream.state, .packet = p.number });
    s.packets += 1;
    s.payload += p.num("tcp.len");
    stream.packets += 1;
    stream.bytes += p.length;
    stream.end = p.time;
}
pub fn endpoint(value: Endpoint, port: bool) []const u8 {
    return if (port) h.fmt("{s}:{d}", .{ net.ipv4(value.address), value.port }) else net.ipv4(value.address);
}
pub const Conversation = struct { kind: usize, a: Endpoint, b: Endpoint, first: usize, start: i64,
     end: i64, packets: [2]i64 = @splat(0), bytes: [2]i64 = @splat(0) };
fn conversationLess(_: void, a: Conversation, b: Conversation) bool {
    const ab = a.bytes[0] + a.bytes[1];
    const bb = b.bytes[0] + b.bytes[1];
    const ap = a.packets[0] + a.packets[1];
    const bp = b.packets[0] + b.packets[1];
    return if (ab != bb) ab > bb else if (ap != bp) ap > bp else if (a.kind != b.kind) a.kind < b.kind else a.first < b.first;
}
pub fn conversations(packets: []const Packet) []Conversation {
    var result: std.ArrayList(Conversation) = .empty;
    for (packets, 0..) |p, packet_index| for (0..3) |kind| {
        if (!p.has(if (kind == 0) "ip.src" else if (kind == 1) "tcp.stream" else "udp.srcport")) continue;
        const source: Endpoint = .{ .address = p.num("ip.src"), .port = if (kind == 0) 0 else p.num(if (kind == 1) "tcp.srcport" else "udp.srcport") };
        const destination: Endpoint = .{ .address = p.num("ip.dst"), .port = if (kind == 0) 0 else p.num(if (kind == 1) "tcp.dstport" else "udp.dstport") };
        var found: ?usize = null;
        for (result.items, 0..) |c, i| if (c.kind == kind and ((source.equal(c.a) and destination.equal(c.b)) or (source.equal(c.b) and destination.equal(c.a))) and (kind != 1 or packets[c.first].num("tcp.stream") == p.num("tcp.stream"))) {
            found = i;
            break;
        };
        if (found == null) {
            found = result.items.len;
            h.append(Conversation, &result, .{ .kind = kind, .a = source, .b = destination, .first = packet_index,
                 .start = p.time, .end = p.time });
        }
        const c = &result.items[found.?];
        const side: usize = if (source.equal(c.a)) 0 else 1;
        c.packets[side] += 1;
        c.bytes[side] += p.length;
        c.end = p.time;
    };
    std.mem.sort(Conversation, result.items, {}, conversationLess);
    return result.items;
}
pub const EndpointTotals = struct { address: i64, packets: [2]i64 = @splat(0), bytes: [2]i64 = @splat(0) };
fn endpointLess(_: void, a: EndpointTotals, b: EndpointTotals) bool {
    const ab = a.bytes[0] + a.bytes[1];
    const bb = b.bytes[0] + b.bytes[1];
    const ap = a.packets[0] + a.packets[1];
    const bp = b.packets[0] + b.packets[1];
    return if (ab != bb) ab > bb else if (ap != bp) ap > bp else a.address < b.address;
}
pub fn endpoints(packets: []const Packet) []EndpointTotals {
    var result: std.ArrayList(EndpointTotals) = .empty;
    for (packets) |p| if (p.has("ip.src")) {
        for (0..2) |side| {
            const address = p.num(if (side == 0) "ip.src" else "ip.dst");
            var found: ?usize = null;
            for (result.items, 0..) |item, i| if (item.address == address) {
                found = i;
                break;
            };
            if (found == null) {
                found = result.items.len;
                h.append(EndpointTotals, &result, .{ .address = address });
            }
            result.items[found.?].packets[side] += 1;
            result.items[found.?].bytes[side] += p.length;
        }
    };
    std.mem.sort(EndpointTotals, result.items, {}, endpointLess);
    return result.items;
}
