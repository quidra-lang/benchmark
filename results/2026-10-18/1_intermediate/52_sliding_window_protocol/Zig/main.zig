const std = @import("std");
const Text = []const u8;
const I = i64;
const keys = [_]Text{
    "PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY",
    "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION",
    "UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA",
    "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT",
};
fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn num(a: Text) I { return std.fmt.parseInt(I, a, 10) catch unreachable; }
fn ix(a: I) usize { return @intCast(a); }
fn find(a: Text, list: []const Text) ?usize {
    for (list, 0..) |b, i| if (eq(a, b)) return i;
    return null;
}
const Host = struct {
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,
    fn text(h: Host, comptime fmt: Text, args: anytype) !Text { return std.fmt.allocPrint(h.gpa, fmt, args); }
    fn line(h: Host, comptime fmt: Text, args: anytype) !void { try h.out.print(fmt ++ "\n", args); }
    fn fixed(h: Host, a: I, b: I, digits: I) !Text {
        const scale: I = if (digits == 2) 100 else 10;
        const v = @divTrunc(a * scale, b);
        return if (digits == 2) h.text("{d}.{d:0>2}", .{ @divTrunc(v, scale), @mod(v, scale) }) else h.text("{d}.{d}", .{ @divTrunc(v, scale), @mod(v, scale) });
    }
    fn time(h: Host, t: I) !Text { return if (t < 0) "-" else h.text("{d}", .{t}); }
};
const Settings = struct {
    values: [22][]const Text = @splat(&.{}),
    present: [22]bool = @splat(false),
    p: Text = "",
    trace: Text = "ALL",
    n: I = 0,
    w: I = 0,
    k: I = 0,
    timeout: I = 0,
    delay: I = 0,
    interval: I = 0,
    limit: I = 1000,
    dupack: I = 0,
    nak: bool = false,
    backoff: bool = false,
    congestion: bool = false,
    unsafe: bool = false,
    random: I = 0,
    loss: I = 0,
    corrupt: I = 0,

    fn contains(c: Settings, key: usize, value: I) bool {
        for (c.values[key]) |word| if (num(word) == value) return true;
        return false;
    }
    fn extra(c: Settings, key: usize, value: I) I {
        for (c.values[key]) |word| {
            var parts = std.mem.splitScalar(u8, word, ':');
            if (num(parts.next().?) == value) return num(parts.next().?);
        }
        return 0;
    }
    fn validate(c: *Settings, h: Host, first_error: ?Text) !?Text {
        if (first_error) |message| return message;
        for (0..6) |j| if (!c.present[j]) return try h.text("missing key {s}", .{keys[j]});
        const lo = [_]I{ 0, 1, 1, 1, 1, 1, 0, 1, 1 };
        const hi = [_]I{ 0, 60, 32, 6, 50, 10, 10, 2000, 10 };
        for (0..22) |j| {
            if (!c.present[j]) continue;
            var bad = false;
            if (j == 0) {
                bad = find(c.values[j][0], &.{ "SW", "GBN", "SR" }) == null;
            } else if (j <= 8) {
                const v = num(c.values[j][0]);
                bad = v < lo[j] or v > hi[j];
            } else if (j <= 12) {
                bad = find(c.values[j][0], &.{ "ON", "OFF" }) == null;
            } else if (j == 13) {
                bad = find(c.values[j][0], &.{ "ALL", "SENDER", "RECEIVER", "NONE" }) == null;
            } else if (j == 14) {
                const seed = num(c.values[j][0]);
                const p = num(c.values[j][1]);
                const q = num(c.values[j][2]);
                bad = seed < 1 or seed > 2147483646 or p < 0 or q < 0 or p + q > 100;
            } else {
                var seen: std.ArrayList(I) = .empty;
                for (c.values[j]) |word| {
                    var parts = std.mem.splitScalar(u8, word, ':');
                    const v = num(parts.next().?);
                    if (v < (if (j == 21) @as(I, 0) else 1) or v > (if (j == 21) @as(I, 2000) else 9999)) bad = true;
                    for (seen.items) |previous| if (v == previous) { bad = true; };
                    try seen.append(h.gpa, v);
                    if (j == 19 or j == 20) {
                        const e = num(parts.next().?);
                        if (e < 1 or e > 50) bad = true;
                    }
                }
            }
            if (bad) return try h.text("bad value for {s}", .{keys[j]});
        }
        c.p = c.values[0][0];
        c.n = num(c.values[1][0]);
        c.w = num(c.values[2][0]);
        c.k = num(c.values[3][0]);
        c.timeout = num(c.values[4][0]);
        c.delay = num(c.values[5][0]);
        if (c.present[6]) c.interval = num(c.values[6][0]);
        if (c.present[7]) c.limit = num(c.values[7][0]);
        if (c.present[8]) c.dupack = num(c.values[8][0]);
        if (c.present[9]) c.nak = eq(c.values[9][0], "ON");
        if (c.present[10]) c.backoff = eq(c.values[10][0], "ON");
        if (c.present[11]) c.congestion = eq(c.values[11][0], "ON");
        if (c.present[12]) c.unsafe = eq(c.values[12][0], "ON");
        if (c.present[13]) c.trace = c.values[13][0];
        if (c.present[14]) {
            c.random = num(c.values[14][0]);
            c.loss = num(c.values[14][1]);
            c.corrupt = num(c.values[14][2]);
        }
        if (eq(c.p, "SR") and c.present[8]) return "DUPACK not supported for SR";
        const modulus: I = @as(I, 1) << @intCast(c.k);
        const limit: I = if (eq(c.p, "SW")) 1 else if (eq(c.p, "GBN")) modulus - 1 else @divTrunc(modulus, 2);
        if (c.w > limit and (!c.unsafe or eq(c.p, "SW"))) return try h.text("window {d} exceeds limit {d} for {s}", .{ c.w, limit, c.p });
        for (0..2) |kind| {
            var smallest: I = 10000;
            for (c.values[15 + kind]) |word| if (c.contains(17 + kind, num(word))) { smallest = @min(smallest, num(word)); };
            if (smallest < 10000) return try h.text("{s} #{d} both lost and corrupted", .{ if (kind == 0) @as(Text, "data") else "control", smallest });
        }
        return null;
    }
};
const Event = struct {
    arrival: I,
    value: I,
    id: I,
    outcome: u8,
    nak: bool = false,
};
const Pair = struct { position: I, payload: I };
const Record = struct {
    tx: I = 0,
    first: I = -1,
    delivered: I = -1,
    acked: I = -1,
    timer: I = -1,
    marked: bool = false,
};
const Result = struct {
    name: Text,
    protocol: Text = "",
    status: Text = "invalid",
    delivered: I = 0,
    completion: I = 0,
    data: I = 0,
};
const Simulation = struct {
    h: Host,
    c: Settings,
    t: I = 0,
    base: I = 0,
    high: I = 0,
    next: I = 0,
    current: I = 0,
    timer: I = -1,
    duplicates: I = 0,
    receiver: I = 0,
    nak_sent: bool = false,
    cwnd: I = 1,
    threshold: I = 0,
    growth: I = 0,
    random: I = 0,
    records: [60]Record = @splat(.{}),
    data_events: std.ArrayList(Event) = .empty,
    control_events: std.ArrayList(Event) = .empty,
    buffer: std.ArrayList(Pair) = .empty,
    queue: std.ArrayList(I) = .empty,
    data: I = 0,
    resent: I = 0,
    control: I = 0,
    naks: I = 0,
    timeouts: I = 0,
    fast: I = 0,
    lost_data: I = 0,
    lost_ctrl: I = 0,
    corrupt_data: I = 0,
    corrupt_ctrl: I = 0,
    delivered: I = 0,
    errors: I = 0,
    discarded: I = 0,
    max_buffer: I = 0,
    latency: I = 0,
    fn sr(s: *Simulation) bool { return eq(s.c.p, "SR"); }
    fn modulus(s: *Simulation) I { return @as(I, 1) << @intCast(s.c.k); }
    fn effective(s: *Simulation) I { return if (s.c.congestion) @min(s.c.w, s.cwnd) else s.c.w; }
    fn log(s: *Simulation, side: Text, comptime fmt: Text, args: anytype) !void {
        if (eq(s.c.trace, "ALL") or eq(s.c.trace, side)) {
            try s.h.out.print("{d} ", .{s.t});
            try s.h.line(fmt, args);
        }
    }
    fn outcome(s: *Simulation, id: I, control: bool) u8 {
        var result: u8 = 0;
        if (s.c.random != 0) {
            s.random = @mod(48271 * s.random, 2147483647);
            const v = @mod(s.random, 100);
            result = if (v < s.c.loss) 1 else if (v < s.c.loss + s.c.corrupt) 2 else 0;
        }
        const offset: usize = @intFromBool(control);
        if (s.c.contains(15 + offset, id)) result = 1;
        if (s.c.contains(17 + offset, id)) result = 2;
        return result;
    }
    fn sendControl(s: *Simulation, a: I, nak: bool) !void {
        s.control += 1;
        if (nak) s.naks += 1;
        try s.log("RECEIVER", "{s} a={d} #{d}", .{ if (nak) @as(Text, "NAK") else "ACK", a, s.control });
        const outcome_value = s.outcome(s.control, true);
        try s.control_events.append(s.h.gpa, .{ .arrival = s.t + s.c.delay + s.c.extra(20, s.control), .value = a, .id = s.control, .outcome = outcome_value, .nak = nak });
    }
    fn deliver(s: *Simulation, payload: I) !void {
        if (payload == s.receiver) {
            try s.log("RECEIVER", "DELIVER f={d}", .{s.receiver});
            s.delivered += 1;
            s.records[ix(payload)].delivered = s.t;
            s.latency += s.t - s.records[ix(payload)].first;
        } else {
            try s.log("RECEIVER", "DELIVER f={d} wrong={d}", .{ s.receiver, payload });
            s.errors += 1;
        }
        s.receiver += 1;
        s.nak_sent = false;
    }
    fn buffered(s: *Simulation, position: I) ?usize {
        for (s.buffer.items, 0..) |pair, j| if (pair.position == position) return j;
        return null;
    }
    fn discard(s: *Simulation, seq: I) !void {
        s.discarded += 1;
        try s.log("RECEIVER", "DISCARD seq={d}", .{seq});
    }
    fn receive(s: *Simulation, e: Event) !void {
        const seq = @mod(e.value, s.modulus());
        try s.log("RECEIVER", "RECV seq={d} #{d}", .{ seq, e.id });
        if (!s.sr()) {
            if (seq == @mod(s.receiver, s.modulus())) {
                try s.deliver(e.value);
                try s.sendControl(seq, false);
            } else {
                try s.discard(seq);
                if (s.c.nak and !s.nak_sent) {
                    try s.sendControl(@mod(s.receiver, s.modulus()), true);
                    s.nak_sent = true;
                } else if (s.receiver > 0) try s.sendControl(@mod(s.receiver - 1, s.modulus()), false);
            }
            return;
        }
        const offset = @mod(seq - s.receiver, s.modulus());
        if (offset < s.c.w) {
            const position = s.receiver + offset;
            if (s.buffered(position) != null) {
                try s.discard(seq);
                try s.sendControl(seq, false);
            } else if (offset == 0) {
                try s.deliver(e.value);
                while (s.buffered(s.receiver)) |j| {
                    const pair = s.buffer.orderedRemove(j);
                    try s.deliver(pair.payload);
                }
                try s.sendControl(seq, false);
            } else {
                try s.buffer.append(s.h.gpa, .{ .position = position, .payload = e.value });
                s.max_buffer = @max(s.max_buffer, @as(I, @intCast(s.buffer.items.len)));
                try s.log("RECEIVER", "BUFFER f={d}", .{position});
                try s.sendControl(seq, false);
                if (s.c.nak and !s.nak_sent) {
                    try s.sendControl(@mod(s.receiver, s.modulus()), true);
                    s.nak_sent = true;
                }
            }
        } else {
            try s.discard(seq);
            if (@mod(s.receiver - seq, s.modulus()) <= s.c.w) try s.sendControl(seq, false);
        }
    }
    fn queued(s: *Simulation, f: I) ?usize {
        for (s.queue.items, 0..) |value, j| if (value == f) return j;
        return null;
    }
    fn enqueue(s: *Simulation, f: I) !void { if (s.queued(f) == null) try s.queue.append(s.h.gpa, f); }
    fn goBack(s: *Simulation) void {
        s.next = s.base;
        s.timer = -1;
        s.duplicates = 0;
    }
    fn increase(s: *Simulation, count: I) void {
        if (!s.c.congestion) return;
        for (0..ix(count)) |_| if (s.cwnd < s.c.w) {
            if (s.cwnd < s.threshold) {
                s.cwnd += 1;
            } else {
                s.growth += 1;
                if (s.growth == s.cwnd) {
                    s.cwnd += 1;
                    s.growth = 0;
                }
            }
        };
    }
    fn decrease(s: *Simulation, timeout: bool) void {
        if (!s.c.congestion) return;
        s.threshold = @max(@divTrunc(s.cwnd, 2), 1);
        s.cwnd = if (timeout) 1 else s.threshold;
        s.growth = 0;
    }
    fn changed(s: *Simulation, old: I, threshold: I) !void {
        if (s.c.congestion and (old != s.cwnd or threshold != s.threshold)) try s.log("SENDER", "CWND {d} ssthresh={d}", .{ s.cwnd, s.threshold });
    }
    fn controlArrival(s: *Simulation, e: Event) !void {
        const old_cwnd = s.cwnd;
        const old_threshold = s.threshold;
        const old_base = s.base;
        const f = s.base + @mod(e.value - s.base, s.modulus());
        var accepted = false;
        if (!s.sr()) {
            accepted = if (e.nak) f <= s.high else f < s.high;
            if (accepted) {
                s.base = f + (if (e.nak) @as(I, 0) else 1);
                if (s.base > old_base) {
                    s.current = s.c.timeout;
                    s.duplicates = 0;
                    for (ix(old_base)..ix(s.base)) |j| if (s.records[j].acked < 0) { s.records[j].acked = s.t; };
                }
                s.increase(s.base - old_base);
                if (e.nak) {
                    s.goBack();
                    s.decrease(false);
                } else {
                    s.next = @max(s.next, s.base);
                    s.timer = if (s.base == s.next) -1 else s.t + s.current;
                }
            }
        } else {
            accepted = f < s.high and !s.records[ix(f)].marked;
            if (accepted) {
                s.records[ix(f)].timer = -1;
                if (e.nak) {
                    try s.enqueue(f);
                    s.decrease(false);
                } else {
                    s.records[ix(f)].marked = true;
                    s.records[ix(f)].acked = s.t;
                    if (s.queued(f)) |j| _ = s.queue.orderedRemove(j);
                    while (s.base < s.high and s.records[ix(s.base)].marked) s.base += 1;
                    if (s.base > old_base) s.current = s.c.timeout;
                    s.increase(1);
                }
            }
        }
        const label: Text = if (e.nak) "NAK" else "ACK";
        if (accepted) try s.log("SENDER", "GOT{s} a={d} #{d} base={d}", .{ label, e.value, e.id, s.base }) else {
            try s.log("SENDER", "OLD{s} a={d} #{d}", .{ label, e.value, e.id });
            if (!s.sr() and !e.nak and s.c.dupack > 0 and s.base >= 1 and e.value == @mod(s.base - 1, s.modulus())) {
                s.duplicates += 1;
                if (s.duplicates == s.c.dupack) {
                    s.fast += 1;
                    try s.log("SENDER", "FASTRETX f={d}", .{s.base});
                    s.goBack();
                    s.decrease(false);
                }
            }
        }
        try s.changed(old_cwnd, old_threshold);
    }
    fn timeoutFrame(s: *Simulation, f: I) !void {
        const old = s.cwnd;
        const threshold = s.threshold;
        s.timeouts += 1;
        try s.log("SENDER", "TIMEOUT f={d}", .{f});
        if (s.sr()) {
            s.records[ix(f)].timer = -1;
            try s.enqueue(f);
        } else {
            s.goBack();
        }
        if (s.c.backoff) s.current = @min(s.current * 2, s.c.timeout * 8);
        s.decrease(true);
        try s.changed(old, threshold);
    }
    fn send(s: *Simulation, f: I) !void {
        const record = &s.records[ix(f)];
        const resend = record.tx > 0;
        if (!resend) record.first = s.t else s.resent += 1;
        record.tx += 1;
        s.data += 1;
        try s.log("SENDER", "{s} f={d} seq={d} #{d}", .{ if (resend) @as(Text, "RESEND") else "SEND", f, @mod(f, s.modulus()), s.data });
        const outcome_value = s.outcome(s.data, false);
        try s.data_events.append(s.h.gpa, .{ .arrival = s.t + s.c.delay + s.c.extra(19, s.data), .value = f, .id = s.data, .outcome = outcome_value });
    }
    fn snapshot(s: *Simulation) !void {
        var sender: [60]u8 = undefined;
        var receiver: [60]u8 = undefined;
        for (0..ix(s.c.n)) |j| {
            const f: I = @intCast(j);
            const acked = if (s.sr()) s.records[j].marked else f < s.base;
            const waiting = if (s.sr()) s.queued(f) != null else s.next <= f and f < s.high;
            const sent = if (s.sr()) f < s.high else f < s.next;
            sender[j] = if (acked) 'A' else if (waiting) 'R' else if (sent) 'O' else if (f < s.base + s.effective()) 'W' else '.';
            receiver[j] = if (f < s.receiver) 'D' else if (s.sr() and s.buffered(f) != null) 'B' else if ((s.sr() and f < s.receiver + s.c.w) or (!s.sr() and f == s.receiver)) 'W' else '.';
        }
        try s.h.line("{d} SNAPSHOT sender={s} receiver={s}", .{ s.t, sender[0..ix(s.c.n)], receiver[0..ix(s.c.n)] });
    }
    fn run(s: *Simulation, name: Text) !Result {
        s.current = s.c.timeout;
        s.threshold = s.c.w;
        s.random = s.c.random;
        try s.h.line("config: {s} n={d} w={d} k={d} T={d} d={d}", .{ s.c.p, s.c.n, s.c.w, s.c.k, s.c.timeout, s.c.delay });
        const trace = try std.ascii.allocLowerString(s.h.gpa, s.c.trace);
        try s.h.line("options: interval={d} limit={d} dupack={s} nak={s} backoff={s} congestion={s} unsafe={s} trace={s} random={s}", .{
            s.c.interval, s.c.limit,
            if (s.c.dupack == 0) "off" else try s.h.time(s.c.dupack),
            if (s.c.nak) @as(Text, "on") else "off",
            if (s.c.backoff) @as(Text, "on") else "off",
            if (s.c.congestion) @as(Text, "on") else "off",
            if (s.c.unsafe) @as(Text, "on") else "off",
            trace,
            if (s.c.random == 0) "off" else try s.h.text("{d}/{d}/{d}", .{ s.c.random, s.c.loss, s.c.corrupt }),
        });
        while (true) : (s.t += 1) {
            for (s.data_events.items) |e| if (e.arrival == s.t) {
                if (e.outcome == 0) try s.receive(e) else {
                    if (e.outcome == 1) s.lost_data += 1 else s.corrupt_data += 1;
                    try s.log("RECEIVER", "{s} data #{d}", .{ if (e.outcome == 1) @as(Text, "LOST") else "CORRUPT", e.id });
                }
            };
            for (s.control_events.items) |e| if (e.arrival == s.t) {
                if (e.outcome == 0) try s.controlArrival(e) else {
                    if (e.outcome == 1) s.lost_ctrl += 1 else s.corrupt_ctrl += 1;
                    try s.log("SENDER", "{s} {s} #{d}", .{ if (e.outcome == 1) @as(Text, "LOST") else "CORRUPT", if (e.nak) @as(Text, "nak") else "ack", e.id });
                }
            };
            const done = s.base == s.c.n;
            if (!done) {
                if (s.sr()) {
                    for (ix(s.base)..ix(s.high)) |j| if (s.records[j].timer == s.t) { try s.timeoutFrame(@intCast(j)); };
                    var frame: I = -1;
                    if (s.queue.items.len > 0) {
                        frame = s.queue.orderedRemove(0);
                    } else if (s.high < s.c.n and s.high < s.base + s.effective() and s.high * s.c.interval <= s.t) {
                        frame = s.high;
                        s.high += 1;
                    }
                    if (frame >= 0) {
                        try s.send(frame);
                        s.records[ix(frame)].timer = s.t + s.current;
                    }
                } else {
                    if (s.timer == s.t) try s.timeoutFrame(s.base);
                    if (s.next < s.c.n and s.next < s.base + s.effective() and (s.next < s.high or s.next * s.c.interval <= s.t)) {
                        try s.send(s.next);
                        s.high = @max(s.high, s.next + 1);
                        s.next += 1;
                        if (s.timer < 0) s.timer = s.t + s.current;
                    }
                }
            }
            if (s.c.contains(21, s.t)) try s.snapshot();
            if (done or s.t == s.c.limit) {
                try s.h.line("{d} {s}", .{ s.t, if (done) @as(Text, "DONE") else "ABORT" });
                break;
            }
        }
        const completed = s.base == s.c.n;
        for (s.records[0..ix(s.c.n)], 0..) |record, j| try s.h.line("frame {d}: seq={d} tx={d} first={s} delivered={s} acked={s}", .{ j, @mod(@as(I, @intCast(j)), s.modulus()), record.tx, try s.h.time(record.first), try s.h.time(record.delivered), try s.h.time(record.acked) });
        try s.h.line("totals: data={d} resent={d} control={d} nak={d} timeouts={d} fastretx={d}", .{ s.data, s.resent, s.control, s.naks, s.timeouts, s.fast });
        try s.h.line("channel: lost_data={d} lost_ctrl={d} corrupt_data={d} corrupt_ctrl={d}", .{ s.lost_data, s.lost_ctrl, s.corrupt_data, s.corrupt_ctrl });
        try s.h.line("receiver: delivered={d} errors={d} discarded={d} max_buffer={d}", .{ s.delivered, s.errors, s.discarded, s.max_buffer });
        try s.h.line("result: completion={s} goodput={s} efficiency={s}% utilization={s}% latency={s}", .{ if (completed) try s.h.time(s.t) else "-", if (completed) try s.h.fixed(s.delivered, s.t, 2) else "-", try s.h.fixed(s.delivered * 100, s.data, 1), try s.h.fixed(s.data * 100, s.t + 1, 1), if (s.delivered == 0) "-" else try s.h.fixed(s.latency, s.delivered, 2) });
        return .{ .name = name, .protocol = s.c.p, .status = if (completed) "done" else "aborted", .delivered = s.delivered, .completion = s.t, .data = s.data };
    }
};
fn readLine(r: *std.Io.Reader, a: std.mem.Allocator) !?Text {
    var b: std.Io.Writer.Allocating = .init(a); defer b.deinit();
    _ = try r.streamDelimiterEnding(&b.writer, '\n');
    if (r.bufferedLen() == 0 and b.written().len == 0) return null;
    if (r.bufferedLen() > 0) r.toss(1);
    return b.toOwnedSlice();
}
fn words(a: std.mem.Allocator, line: Text) ![]const Text {
    var list: std.ArrayList(Text) = .empty;
    var it = std.mem.splitScalar(u8, std.mem.trim(u8, line, "\r"), ' ');
    while (it.next()) |word| try list.append(a, word);
    return list.toOwnedSlice(a);
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator); defer arena.deinit();
    const a = arena.allocator(); var ib: [4096]u8 = undefined; var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib); var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    const h: Host = .{ .gpa = a, .out = &output.interface };
    const count = num(std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r"));
    var results: std.ArrayList(Result) = .empty;
    for (0..ix(count)) |_| {
        const header = try words(a, (try readLine(&input.interface, a)).?);
        const name = header[1]; var c: Settings = .{}; var problem: ?Text = null;
        while (true) {
            const w = try words(a, (try readLine(&input.interface, a)).?);
            if (eq(w[0], "END")) break;
            if (problem != null) continue;
            const key = find(w[0], &keys) orelse { problem = try h.text("unknown key {s}", .{w[0]}); continue; };
            if (c.present[key]) { problem = try h.text("duplicate key {s}", .{w[0]}); continue; }
            c.present[key] = true;
            const correct = if (key == 14) w.len == 4 else if (key >= 15) w.len >= 2 else w.len == 2;
            if (!correct) { problem = try h.text("wrong number of values for {s}", .{w[0]}); continue; }
            c.values[key] = w[1..];
        }
        try h.line("== {s} ==", .{name});
        if (try c.validate(h, problem)) |message| {
            try h.line("error: {s}", .{message}); try results.append(a, .{ .name = name });
        } else {
            var simulation: Simulation = .{ .h = h, .c = c };
            try results.append(a, try simulation.run(name));
        }
    }
    var ranked: std.ArrayList(Result) = .empty;
    for (results.items) |result| if (eq(result.status, "done")) {
        var position = ranked.items.len;
        while (position > 0) : (position -= 1) {
            const previous = ranked.items[position - 1];
            const left = result.delivered * previous.completion; const right = previous.delivered * result.completion;
            if (left < right or (left == right and result.delivered * previous.data <= previous.delivered * result.data)) break;
        }
        try ranked.insert(a, position, result);
    };
    try h.line("== ranking ==", .{});
    for (ranked.items, 0..) |result, j| try h.line("{d}. {s} {s} goodput={s} efficiency={s}%", .{ j + 1, result.name, result.protocol, try h.fixed(result.delivered, result.completion, 2), try h.fixed(result.delivered * 100, result.data, 1) });
    for (results.items) |result| if (!eq(result.status, "done")) { try h.line("- {s} {s}", .{ result.name, result.status }); };
    try h.line("== protocols ==", .{});
    for ([_]Text{ "SW", "GBN", "SR" }) |protocol| {
        var runs: I = 0; var delivered: I = 0; var ticks: I = 0; var data: I = 0;
        for (ranked.items) |result| if (eq(result.protocol, protocol)) { runs += 1; delivered += result.delivered; ticks += result.completion; data += result.data; };
        if (runs > 0) try h.line("{s}: runs={d} goodput={s} efficiency={s}%", .{ protocol, runs, try h.fixed(delivered, ticks, 2), try h.fixed(delivered * 100, data, 1) });
    }
    try output.interface.flush();
}
