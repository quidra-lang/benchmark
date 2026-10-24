const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{
    Invalid
};

var error_message: Text = "";

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn before(a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn includes(s: Text, c: u8) bool {
    return std.mem.findScalar(u8, s, c) != null;
}

fn number(s: Text) usize {
    return std.fmt.parseInt(usize, s, 10) catch unreachable;
}

fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    error_message = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}

const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, s: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, s);
    }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.print(pattern ++ "\n", args);
    }
};

fn decimal(s: Text) bool {
    if (s.len == 0 or (s.len > 1 and s[0] == '0')) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn parseAddress(s: Text) ?u32 {
    var fields = std.mem.splitScalar(u8, s, '.');
    var a: u32 = 0;
    var count: usize = 0;
    while (fields.next()) |p| {
        if (p.len > 3 or !decimal(p) or number(p) > 255 or count == 4) return null;
        a = a * 256 + @as(u32, @intCast(number(p)));
        count += 1;
    }
    return if (count == 4) a else null;
}

fn address(gpa: Allocator, a: u32) Allocator.Error!Text {
    return std.fmt.allocPrint(gpa, "{d}.{d}.{d}.{d}", .{
        a >> 24,
        (a >> 16) & 255,
        (a >> 8) & 255,
        a & 255
    });
}

fn network(a: u32, length: usize) u32 {
    return if (length == 0) 0 else a & (std.math.maxInt(u32) << @as(u5, @intCast(32 - length)));
}

const Prefix = struct {
    address: u32,
    length: usize,
    fn contains(self: Prefix, a: u32) bool {
        return network(a, self.length) == network(self.address, self.length);
    }
    fn same(a: Prefix, b: Prefix) bool {
        return a.address == b.address and a.length == b.length;
    }
    fn text(self: Prefix, gpa: Allocator) Allocator.Error!Text {
        return std.fmt.allocPrint(gpa, "{s}/{d}", .{
            try address(gpa, self.address),
            self.length
        });
    }
};

fn parsePrefix(s: Text) ?Prefix {
    const slash = std.mem.findScalar(u8, s, '/') orelse return null;
    const length = s[slash + 1..];
    if (length.len > 2 or !decimal(length) or number(length) > 32) return null;
    return .{
        .address = parseAddress(s[0..slash]) orelse return null,
        .length = number(length)
    };
}

fn checkedAddress(gpa: Allocator, s: Text) Error!u32 {
    return parseAddress(s) orelse return bad(gpa, "bad address {s}", .{
        s
    });
}

fn checkedPrefix(gpa: Allocator, s: Text) Error!Prefix {
    const p = parsePrefix(s) orelse return bad(gpa, "bad prefix {s}", .{
        s
    });
    if (network(p.address, p.length) != p.address) return bad(gpa, "host bits set in {s}", .{
        s
    });
    return p;
}

const PortRange = struct {
    lo: usize,
    hi: usize,
    any: bool = false,
    fn text(self: PortRange, gpa: Allocator) Allocator.Error!Text {
        if (self.any) return "any";
        if (self.lo == self.hi) return std.fmt.allocPrint(gpa, "{d}", .{
            self.lo
        });
        return std.fmt.allocPrint(gpa, "{d}-{d}", .{
            self.lo,
            self.hi
        });
    }
};

fn parsePorts(gpa: Allocator, s: Text) Error!PortRange {
    if (equal(s, "ANY")) return .{
        .lo = 0,
        .hi = 65535,
        .any = true
    };
    const dash = std.mem.findScalar(u8, s, '-');
    const lo = number(if (dash) |p| s[0..p] else s);
    const hi = if (dash) |p| number(s[p + 1..]) else lo;
    if (lo > 65535 or hi > 65535 or lo > hi) return bad(gpa, "bad port range {s}", .{
        s
    });
    return .{
        .lo = lo,
        .hi = hi
    };
}

const Rule = struct {
    seq: usize,
    action: Text,
    proto: Text,
    src: Prefix,
    dst: Prefix,
    sports: PortRange,
    dports: PortRange,
    established: bool,
    hits: usize = 0
};

const Pat = struct {
    proto: Text,
    inside: u32,
    inport: usize,
    outport: usize,
    last: usize
};

const Interface = struct {
    name: Text,
    prefix: Prefix,
    up: bool = true,
    outside: bool = false,
    pool: usize = 0,
    rpf: Text = "off",
    rx: usize = 0,
    tx: usize = 0,
    drop: usize = 0,
    rules: [2]std.ArrayList(*Rule) = .{
        .empty,
        .empty
    },
    defaults: [2]usize = .{
        0,
        0
    },
    mappings: std.ArrayList(*Pat) = .empty,
};

const Route = struct {
    kind: Text,
    prefix: Prefix,
    out: *Interface,
    hop: ?u32 = null,
    metric: usize,
    order: usize,
    hits: usize = 0,
    fn text(self: *const Route, gpa: Allocator) Allocator.Error!Text {
        const via = if (self.hop) |h| try std.fmt.allocPrint(gpa, " via {s}", .{
            try address(gpa, h)
        }) else "";
        return std.fmt.allocPrint(gpa, "{s} {s}{s} dev {s} metric {d}", .{
            self.kind,
            try self.prefix.text(gpa),
            via,
            self.out.name,
            self.metric
        });
    }
};

const Static = struct {
    inside: u32,
    outside: u32
};

const Forward = struct {
    out: *Interface,
    proto: Text,
    port: usize,
    inside: u32,
    inport: usize
};

const Tuple = struct {
    proto: Text,
    src: u32,
    sport: usize,
    dst: u32,
    dport: usize,
    fn same(a: Tuple, b: Tuple) bool {
        return equal(a.proto, b.proto) and a.src == b.src and a.sport == b.sport and a.dst == b.dst and a.dport == b.dport;
    }
};

const Connection = struct {
    number: usize,
    orig: Tuple,
    reply: Tuple,
    input: *Interface,
    out: *Interface,
    state: Text,
    orig_count: usize = 0,
    reply_count: usize = 0,
    last: usize = 0,
    fin: [2]bool = .{
        false,
        false
    }
};

const reasons = [_]Text {
    "down",
    "martian",
    "rpf",
    "invalid",
    "acl_in",
    "ttl",
    "noroute",
    "acl_out",
    "exhausted"
};

const Verdict = struct {
    text: Text,
    reason: usize
};

fn martian(a: u32) bool {
    return a >> 24 == 0 or a >> 24 == 127 or a >> 29 == 7;
}

fn direction(s: Text) usize {
    return if (equal(s, "IN")) 0 else 1;
}

fn protocolIndex(s: Text) usize {
    return if (equal(s, "TCP")) 0 else if (equal(s, "UDP")) 1 else 2;
}

const Router = struct {
    gpa: Allocator,
    out: Builder,
    ifaces: std.ArrayList(*Interface) = .empty,
    routes: std.ArrayList(*Route) = .empty,
    statics: std.ArrayList(Static) = .empty,
    forwards: std.ArrayList(*Forward) = .empty,
    conns: std.ArrayList(*Connection) = .empty,
    timeouts: [3]usize = .{
        300,
        60,
        30
    },
    clock: usize = 0,
    packet: usize = 0,
    connection_number: usize = 0,
    route_order: usize = 0,
    forwarded: usize = 0,
    local_count: usize = 0,
    errors: usize = 0,
    drops: [9]usize = @splat(0),
    fn interface(self: *Router, name: Text) Error!*Interface {
        for (self.ifaces.items) |i| if (equal(i.name, name)) return i;
        return bad(self.gpa, "no interface {s}", .{
            name
        });
    }
    fn localAddress(self: *Router, a: u32) ?*Interface {
        for (self.ifaces.items) |i| if (i.prefix.address == a) return i;
        return null;
    }
    fn selectRoute(self: *Router, a: u32) ?*Route {
        var best: ?*Route = null;
        for (self.routes.items) |r| {
            if (!r.out.up or !r.prefix.contains(a)) continue;
            if (best == null or r.prefix.length > best.?.prefix.length or (r.prefix.length == best.?.prefix.length and r.metric < best.?.metric)) best = r;
        }
        return best;
    }
    fn sortedInterfaces(self: *Router) Allocator.Error![]* Interface {
        const result = try self.gpa.dupe(*Interface, self.ifaces.items);
        std.mem.sort(*Interface, result, { }, struct {
            fn less(_: void, a: *Interface, b: *Interface) bool {
                return before(a.name, b.name);
            }
        }.less);
        return result;
    }
    fn acl(self: *Router, i: *Interface, d: usize, t: Tuple, existing: bool) Error!?Text {
        if (i.rules[d].items.len == 0) return null;
        const dir: Text = if (d == 0) "in" else "out";
        for (i.rules[d].items) |r| {
            if ((!equal(r.proto, "ANY") and !equal(r.proto, t.proto)) or !r.src.contains(t.src) or !r.dst.contains(t.dst) or (r.established and !existing)) continue;
            if ((equal(r.proto, "TCP") or equal(r.proto, "UDP")) and (t.sport < r.sports.lo or t.sport > r.sports.hi or t.dport < r.dports.lo or t.dport > r.dports.hi)) continue;
            r.hits += 1;
            if (equal(r.action, "PERMIT")) return null;
            if (equal(r.action, "DENY")) return try std.fmt.allocPrint(self.gpa, "DROP acl {s} {s} {d}", .{
                i.name,
                dir,
                r.seq
            });
            return try std.fmt.allocPrint(self.gpa, "REJECT acl {s} {s} {d} {s}", .{
                i.name,
                dir,
                r.seq,
                if (equal(t.proto, "TCP")) @as(Text, "tcp-reset") else "icmp-prohibited"
            });
        }
        i.defaults[d] += 1;
        return try std.fmt.allocPrint(self.gpa, "DROP acl {s} {s} default", .{
            i.name,
            dir
        });
    }
    fn dropped(self: *Router, reason: usize) Error!Verdict {
        return .{
            .text = try std.fmt.allocPrint(self.gpa, "DROP {s}", .{
                reasons[reason]
            }),
            .reason = reason
        };
    }
    fn processPacket(self: *Router, i: *Interface, t: Tuple, flags: Text, ttl: usize) Error!Verdict {
        if (!i.up) return self.dropped(0);
        if (martian(t.src) or martian(t.dst) or self.localAddress(t.src) != null) return self.dropped(1);
        if (!equal(i.rpf, "off")) {
            const back = self.selectRoute(t.src) orelse return self.dropped(2);
            if (equal(i.rpf, "strict") and back.out != i) return self.dropped(2);
        }
        const pure = equal(t.proto, "TCP") and equal(flags, "S");
        var conn: ?*Connection = null;
        var way: Text = "new";
        for (self.conns.items, 0..) |c,
        at | {
            if (c.orig.same(t)) {
                conn = c;
                way = "orig";
            } else if (c.reply.same(t)) {
                conn = c;
                way = "reply";
            }
            if (conn != null) {
                if (equal(c.state, "CLOSED") and pure) {
                    _ = self.conns.orderedRemove(at);
                    conn = null;
                    way = "new";
                }
                break;
            }
        }
        if (equal(t.proto, "TCP") and conn == null and !pure) return self.dropped(3);
        if (try self.acl(i, 0, t, conn != null)) |v| return .{
            .text = v,
            .reason = 4
        };
        var translated = t;
        var used: ?*Pat = null;
        if (i.outside) {
            var matched = false;
            for (self.statics.items) |m| if (m.outside == t.dst) {
                translated.dst = m.inside;
                matched = true;
                break;
            };
            if (!matched and t.dst == i.prefix.address) {
                for (self.forwards.items) |f| if (f.out == i and equal(f.proto, t.proto) and f.port == t.dport) {
                    translated.dst = f.inside;
                    translated.dport = f.inport;
                    matched = true;
                    break;
                };
                if (!matched) for (i.mappings.items) |m| if (equal(m.proto, t.proto) and m.outport == t.dport) {
                    translated.dst = m.inside;
                    translated.dport = m.inport;
                    used = m;
                    break;
                };
            }
        }
        if (self.localAddress(translated.dst)) |local| return .{
            .text = try std.fmt.allocPrint(self.gpa, "LOCAL {s}", .{
                local.name
            }),
            .reason = 10
        };
        if (ttl == 1) return self.dropped(5);
        const r = self.selectRoute(translated.dst) orelse return self.dropped(6);
        const o = r.out;
        if (try self.acl(o, 1, translated, conn != null)) |v| return .{
            .text = v,
            .reason = 7
        };
        if (!i.outside and o.outside) {
            var matched = false;
            for (self.statics.items) |m| if (m.inside == t.src) {
                translated.src = m.outside;
                matched = true;
                break;
            };
            if (!matched) for (self.forwards.items) |f| if (f.out == o and equal(f.proto, t.proto) and f.inside == t.src and f.inport == t.sport) {
                translated.src = o.prefix.address;
                translated.sport = f.port;
                matched = true;
                break;
            };
            if (!matched and o.pool > 0) {
                for (o.mappings.items) |m| if (equal(m.proto, t.proto) and m.inside == t.src and m.inport == t.sport) {
                    used = m;
                    break;
                };
                if (used == null) {
                    var port: usize = 20000;
                    while (port < 20000 + o.pool): (port += 1) {
                        var busy = false;
                        for (o.mappings.items) |m| if (m.outport == port) {
                            busy = true;
                        };
                        for (self.forwards.items) |f| if (f.out == o and f.port == port) {
                            busy = true;
                        };
                        if (!busy) break;
                    }
                    if (port == 20000 + o.pool) return self.dropped(8);
                    const m = try self.gpa.create(Pat);
                    m.* = .{
                        .proto = t.proto,
                        .inside = t.src,
                        .inport = t.sport,
                        .outport = port,
                        .last = self.clock
                    };
                    try o.mappings.append(self.gpa, m);
                    used = m;
                }
                translated.src = o.prefix.address;
                translated.sport = used.?.outport;
            }
        }
        if (used) |m| m.last = self.clock;
        if (conn == null) {
            self.connection_number += 1;
            const c = try self.gpa.create(Connection);
            c.* = .{
                .number = self.connection_number,
                .orig = t,
                .reply = .{
                    .proto = t.proto,
                    .src = translated.dst,
                    .sport = translated.dport,
                    .dst = translated.src,
                    .dport = translated.sport
                },
                .input = i,
                .out = o,
                .state = if (equal(t.proto, "TCP")) "SYN_SENT" else "UNREPLIED"
            };
            try self.conns.append(self.gpa, c);
            conn = c;
            way = "new";
        }
        const c = conn.?;
        if (equal(way, "reply")) c.reply_count += 1 else c.orig_count += 1;
        c.last = self.clock;
        if (!equal(t.proto, "TCP")) {
            if (equal(way, "reply")) c.state = "REPLIED";
        } else if (includes(flags, 'R')) c.state = "CLOSED" else {
            if (equal(c.state, "SYN_SENT") and equal(way, "reply") and includes(flags, 'S') and includes(flags, 'A')) c.state = "ESTABLISHED";
            if (includes(flags, 'F') and (equal(c.state, "ESTABLISHED") or equal(c.state, "FIN_WAIT"))) {
                c.fin[if (equal(way, "reply")) @as(usize, 1) else 0] = true;
                c.state = if (c.fin[0] and c.fin[1]) "CLOSED" else "FIN_WAIT";
            }
        }
        o.tx += 1;
        r.hits += 1;
        var out: Builder = .{
            .gpa = self.gpa
        };
        const via = if (r.hop) |hop| try std.fmt.allocPrint(self.gpa, "via {s}", .{
            try address(self.gpa, hop)
        }) else "direct";
        try out.print("FORWARD {s} {s} ttl={d}", .{
            o.name,
            via,
            ttl - 1
        });
        if (translated.dst != t.dst or translated.dport != t.dport) try out.print(" dnat={s}:{d}", .{
            try address(self.gpa, translated.dst),
            translated.dport
        });
        if (translated.src != t.src or translated.sport != t.sport) try out.print(" snat={s}:{d}", .{
            try address(self.gpa, translated.src),
            translated.sport
        });
        try out.print(" conn={d} {s}", .{
            c.number,
            way
        });
        return .{
            .text = out.bytes.items,
            .reason = 9
        };
    }
    fn expire(self: *Router)[2]usize {
        var removed: [2]usize = .{
            0,
            0
        };
        var at: usize = 0;
        while (at < self.conns.items.len) {
            const c = self.conns.items[at];
            var timeout = self.timeouts[protocolIndex(c.orig.proto)];
            if (equal(c.orig.proto, "TCP")) {
                if (equal(c.state, "SYN_SENT") or equal(c.state, "FIN_WAIT")) timeout = 60 else if (equal(c.state, "CLOSED")) timeout = 10;
            }
            if (self.clock - c.last >= timeout) {
                _ = self.conns.orderedRemove(at);
                removed[0] += 1;
            } else at += 1;
        }
        for (self.ifaces.items) |i| {
            at = 0;
            while (at < i.mappings.items.len) {
                const m = i.mappings.items[at];
                if (self.clock - m.last >= self.timeouts[protocolIndex(m.proto)]) {
                    _ = i.mappings.orderedRemove(at);
                    removed[1] += 1;
                } else at += 1;
            }
        }
        return removed;
    }
    fn show(self: *Router, what: Text) Error!void {
        const is = try self.sortedInterfaces();
        const gpa = self.gpa;
        if (equal(what, "IFACES")) {
            try self.out.line("show ifaces count={d}", .{
                is.len
            });
            for (is) |i| {
                try self.out.print("{s} {s} {s} {s} rpf={s}", .{
                    i.name,
                    try i.prefix.text(gpa),
                    if (i.up) @as(Text, "up") else "down",
                    if (i.outside) @as(Text, "outside") else "inside",
                    i.rpf
                });
                if (i.pool > 0) try self.out.print(" pat={d}/{d}", .{
                    i.mappings.items.len,
                    i.pool
                });
                try self.out.add("\n");
            }
        } else if (equal(what, "ROUTES")) {
            const rs = try gpa.dupe(*Route, self.routes.items);
            std.mem.sort(*Route, rs, { }, struct {
                fn less(_: void, a: *Route, b: *Route) bool {
                    if (a.prefix.address != b.prefix.address) return a.prefix.address < b.prefix.address;
                    if (a.prefix.length != b.prefix.length) return a.prefix.length < b.prefix.length;
                    if (a.metric != b.metric) return a.metric < b.metric;
                    return a.order < b.order;
                }
            }.less);
            try self.out.line("show routes count={d}", .{
                rs.len
            });
            for (rs) |r| try self.out.line("{s} hits={d}{s}", .{
                try r.text(gpa),
                r.hits,
                if (r.out.up) @as(Text, "") else " inactive"
            });
        } else if (equal(what, "ACL")) {
            var count: usize = 0;
            for (is) |i| count += i.rules[0].items.len + i.rules[1].items.len;
            try self.out.line("show acl count={d}", .{
                count
            });
            for (is) |i| for (0..2) |d| {
                const dir: Text = if (d == 0) "in" else "out";
                for (i.rules[d].items) |r| try self.out.line("acl {s} {s} {d} {s} {s} {s} {s} {s} {s}{s} hits={d}", .{
                    i.name,
                    dir,
                    r.seq,
                    r.action,
                    r.proto,
                    if (r.src.length == 0) "any" else try r.src.text(gpa),
                    try r.sports.text(gpa),
                    if (r.dst.length == 0) "any" else try r.dst.text(gpa),
                    try r.dports.text(gpa),
                    if (r.established) @as(Text, " established") else "",
                    r.hits
                });
                if (i.rules[d].items.len > 0) try self.out.line("acl {s} {s} default DENY hits={d}", .{
                    i.name,
                    dir,
                    i.defaults[d]
                });
            };
        } else if (equal(what, "NAT")) {
            var count: usize = 0;
            for (is) |i| count += i.mappings.items.len;
            try self.out.line("show nat static={d} forward={d} pat={d}", .{
                self.statics.items.len,
                self.forwards.items.len,
                count
            });
            const ss = try gpa.dupe(Static, self.statics.items);
            std.mem.sort(Static, ss, { }, struct {
                fn less(_: void, a: Static, b: Static) bool {
                    return a.inside < b.inside;
                }
            }.less);
            for (ss) |m| try self.out.line("static {s} {s}", .{
                try address(gpa, m.inside),
                try address(gpa, m.outside)
            });
            const fs = try gpa.dupe(*Forward, self.forwards.items);
            std.mem.sort(*Forward, fs, { }, struct {
                fn less(_: void, a: *Forward, b: *Forward) bool {
                    if (!equal(a.out.name, b.out.name)) return before(a.out.name, b.out.name);
                    if (a.port != b.port) return a.port < b.port;
                    return before(a.proto, b.proto);
                }
            }.less);
            for (fs) |f| try self.out.line("forward {s} {s} {d} {s}:{d}", .{
                f.out.name,
                f.proto,
                f.port,
                try address(gpa, f.inside),
                f.inport
            });
            for (is) |i| {
                const ms = try gpa.dupe(*Pat, i.mappings.items);
                std.mem.sort(*Pat, ms, { }, struct {
                    fn less(_: void, a: *Pat, b: *Pat) bool {
                        return a.outport < b.outport;
                    }
                }.less);
                for (ms) |m| try self.out.line("pat {s} {d} {s} {s}:{d} idle={d}", .{
                    i.name,
                    m.outport,
                    m.proto,
                    try address(gpa, m.inside),
                    m.inport,
                    self.clock - m.last
                });
            }
        } else if (equal(what, "CONNS")) {
            try self.out.line("show conns count={d}", .{
                self.conns.items.len
            });
            for (self.conns.items) |c| {
                const a = c.orig;
                const b = c.reply;
                try self.out.line("conn {d} {s} {s}:{d} > {s}:{d} reply {s}:{d} > {s}:{d} in={s} out={s} state={s} pkts={d}/{d} idle={d}", .{
                    c.number,
                    a.proto,
                    try address(gpa, a.src),
                    a.sport,
                    try address(gpa, a.dst),
                    a.dport,
                    try address(gpa, b.src),
                    b.sport,
                    try address(gpa, b.dst),
                    b.dport,
                    c.input.name,
                    c.out.name,
                    c.state,
                    c.orig_count,
                    c.reply_count,
                    self.clock - c.last
                });
            }
        } else {
            var dropped_count: usize = 0;
            for (self.drops) |n| dropped_count += n;
            try self.out.line("show counters packets={d} forwarded={d} local={d} dropped={d} errors={d}", .{
                self.forwarded + self.local_count + dropped_count,
                self.forwarded,
                self.local_count,
                dropped_count,
                self.errors
            });
            try self.out.add("drops");
            for (reasons, 0..) |reason,
            n | try self.out.print(" {s}={d}", .{
                reason,
                self.drops[n]
            });
            try self.out.add("\n");
            for (is) |i| try self.out.line("iface {s} rx={d} tx={d} drop={d}", .{
                i.name,
                i.rx,
                i.tx,
                i.drop
            });
        }
    }
    fn command(self: *Router, w: []const Text) Error!void {
        const cmd = w[0];
        const gpa = self.gpa;
        if (equal(cmd, "IFACE")) {
            for (self.ifaces.items) |i| if (equal(i.name, w[1])) return bad(gpa, "duplicate interface {s}", .{
                w[1]
            });
            const p = parsePrefix(w[2]) orelse return bad(gpa, "bad prefix {s}", .{
                w[2]
            });
            if (p.length < 8 or p.length > 30) return bad(gpa, "bad prefix {s}", .{
                w[2]
            });
            const net = network(p.address, p.length);
            if (p.address == net or p.address == (net | (std.math.maxInt(u32) >> @as(u5, @intCast(p.length))))) return bad(gpa, "bad host address {s}", .{
                w[2]
            });
            for (self.ifaces.items) |i| {
                const length = @min(p.length, i.prefix.length);
                if (network(p.address, length) == network(i.prefix.address, length)) return bad(gpa, "subnet overlaps {s}", .{
                    i.name
                });
            }
            const i = try gpa.create(Interface);
            i.* = .{
                .name = w[1],
                .prefix = p
            };
            try self.ifaces.append(gpa, i);
            const r = try gpa.create(Route);
            r.* = .{
                .kind = "C",
                .prefix = .{
                    .address = net,
                    .length = p.length
                },
                .out = i,
                .metric = 0,
                .order = self.route_order
            };
            self.route_order += 1;
            try self.routes.append(gpa, r);
            try self.out.line("ok iface {s} {s} network {s}/{d}", .{
                i.name,
                w[2],
                try address(gpa, net),
                p.length
            });
        } else if (equal(cmd, "UP") or equal(cmd, "DOWN")) {
            const i = try self.interface(w[1]);
            const up = equal(cmd, "UP");
            const status: Text = if (up) "up" else "down";
            if (i.up == up) return bad(gpa, "interface {s} already {s}", .{
                i.name,
                status
            });
            i.up = up;
            try self.out.line("ok {s} {s}", .{
                status,
                i.name
            });
        } else if (equal(cmd, "ROUTE")) {
            const p = try checkedPrefix(gpa, w[1]);
            var hop: ?u32 = null;
            var output: ?*Interface = null;
            if (equal(w[2], "VIA")) hop = try checkedAddress(gpa, w[3]) else output = try self.interface(w[3]);
            const metric = number(w[4]);
            if (metric < 1 or metric > 255) return bad(gpa, "bad metric {s}", .{
                w[4]
            });
            if (hop) |h| {
                if (self.localAddress(h) != null) return bad(gpa, "nexthop {s} is local", .{
                    w[3]
                });
                for (self.ifaces.items) |i| if (i.prefix.contains(h)) {
                    output = i;
                    break;
                };
                if (output == null) return bad(gpa, "nexthop {s} unreachable", .{
                    w[3]
                });
            }
            for (self.routes.items) |r| if (equal(r.kind, "S") and r.prefix.same(p) and r.out == output.?and r.hop == hop) return bad(gpa, "duplicate route {s}", .{
                w[1]
            });
            const r = try gpa.create(Route);
            r.* = .{
                .kind = "S",
                .prefix = p,
                .out = output.?,
                .hop = hop,
                .metric = metric,
                .order = self.route_order
            };
            self.route_order += 1;
            try self.routes.append(gpa, r);
            try self.out.line("ok route {s}", .{
                try r.text(gpa)
            });
        } else if (equal(cmd, "NOROUTE")) {
            const p = try checkedPrefix(gpa, w[1]);
            var count: usize = 0;
            for (self.routes.items) |r| if (equal(r.kind, "S") and r.prefix.same(p)) {
                count += 1;
            };
            if (count == 0) return bad(gpa, "no static route {s}", .{
                w[1]
            });
            var at: usize = 0;
            while (at < self.routes.items.len) {
                const r = self.routes.items[at];
                if (equal(r.kind, "S") and r.prefix.same(p)) {
                    _ = self.routes.orderedRemove(at);
                } else at += 1;
            }
            try self.out.line("ok noroute {s} removed={d}", .{
                w[1],
                count
            });
        } else if (equal(cmd, "LOOKUP")) {
            const a = try checkedAddress(gpa, w[1]);
            const selected = self.selectRoute(a);
            try self.out.line("lookup {s} {s}", .{
                w[1],
                if (selected) |r| try r.text(gpa) else "none"
            });
        } else if (equal(cmd, "ACL")) {
            const i = try self.interface(w[1]);
            const seq = number(w[3]);
            if (seq < 1 or seq > 9999) return bad(gpa, "bad sequence {s}", .{
                w[3]
            });
            const src = if (equal(w[6], "ANY")) Prefix {
                .address = 0,
                .length = 0
            } else try checkedPrefix(gpa, w[6]);
            const sports = try parsePorts(gpa, w[7]);
            const dst = if (equal(w[8], "ANY")) Prefix {
                .address = 0,
                .length = 0
            } else try checkedPrefix(gpa, w[8]);
            const dports = try parsePorts(gpa, w[9]);
            if ((equal(w[5], "ICMP") or equal(w[5], "ANY")) and (!sports.any or !dports.any)) return bad(gpa, "ports not allowed for {s}", .{
                w[5]
            });
            const d = direction(w[2]);
            for (i.rules[d].items) |r| if (r.seq == seq) return bad(gpa, "duplicate sequence {s}", .{
                w[3]
            });
            const r = try gpa.create(Rule);
            r.* = .{
                .seq = seq,
                .action = w[4],
                .proto = w[5],
                .src = src,
                .dst = dst,
                .sports = sports,
                .dports = dports,
                .established = w.len == 11
            };
            try i.rules[d].append(gpa, r);
            std.mem.sort(*Rule, i.rules[d].items, { }, struct {
                fn less(_: void, a: *Rule, b: *Rule) bool {
                    return a.seq < b.seq;
                }
            }.less);
            try self.out.line("ok acl {s} {s} {s}", .{
                i.name,
                if (d == 0) @as(Text, "in") else "out",
                w[3]
            });
        } else if (equal(cmd, "NOACL")) {
            const i = try self.interface(w[1]);
            const d = direction(w[2]);
            const dir: Text = if (d == 0) "in" else "out";
            for (i.rules[d].items, 0..) |r,
            at | if (r.seq == number(w[3])) {
                _ = i.rules[d].orderedRemove(at);
                try self.out.line("ok noacl {s} {s} {s} hits={d}", .{
                    i.name,
                    dir,
                    w[3],
                    r.hits
                });
                return;
            };
            return bad(gpa, "no rule {s} on {s} {s}", .{
                w[3],
                i.name,
                dir
            });
        } else if (equal(cmd, "NAT")) {
            if (equal(w[1], "STATIC")) {
                const a = try checkedAddress(gpa, w[2]);
                const b = try checkedAddress(gpa, w[3]);
                if (self.localAddress(a) != null) return bad(gpa, "address {s} is local", .{
                    w[2]
                });
                if (self.localAddress(b) != null) return bad(gpa, "address {s} is local", .{
                    w[3]
                });
                for (self.statics.items) |m| if (m.inside == a) return bad(gpa, "duplicate static {s}", .{
                    w[2]
                });
                for (self.statics.items) |m| if (m.outside == b) return bad(gpa, "duplicate static {s}", .{
                    w[3]
                });
                try self.statics.append(gpa, .{
                    .inside = a,
                    .outside = b
                });
                try self.out.line("ok nat static {s} {s}", .{
                    w[2],
                    w[3]
                });
                return;
            }
            const i = try self.interface(w[2]);
            if (equal(w[1], "OUTSIDE")) {
                if (i.outside) return bad(gpa, "interface {s} already outside", .{
                    i.name
                });
                i.outside = true;
                try self.out.line("ok nat outside {s}", .{
                    i.name
                });
            } else if (equal(w[1], "PAT")) {
                const count = number(w[3]);
                if (count < 1 or count > 1000) return bad(gpa, "bad pool size {s}", .{
                    w[3]
                });
                if (i.pool > 0) return bad(gpa, "pat already on {s}", .{
                    i.name
                });
                i.pool = count;
                i.outside = true;
                try self.out.line("ok nat pat {s} {s} 20000-{d}", .{
                    i.name,
                    try address(gpa, i.prefix.address),
                    19999 + count
                });
            } else {
                const port = number(w[4]);
                if (port < 1 or port > 65535) return bad(gpa, "bad port {s}", .{
                    w[4]
                });
                const a = try checkedAddress(gpa, w[5]);
                const inport = number(w[6]);
                if (inport < 1 or inport > 65535) return bad(gpa, "bad port {s}", .{
                    w[6]
                });
                if (!i.outside) return bad(gpa, "interface {s} not outside", .{
                    i.name
                });
                if (self.localAddress(a) != null) return bad(gpa, "address {s} is local", .{
                    w[5]
                });
                for (self.forwards.items) |f| if (f.out == i and equal(f.proto, w[3]) and f.port == port) return bad(gpa, "duplicate forward {s} {s} {s}", .{
                    i.name,
                    w[3],
                    w[4]
                });
                const f = try gpa.create(Forward);
                f.* = .{
                    .out = i,
                    .proto = w[3],
                    .port = port,
                    .inside = a,
                    .inport = inport
                };
                try self.forwards.append(gpa, f);
                try self.out.line("ok nat forward {s} {s} {s} {s}:{s}", .{
                    i.name,
                    w[3],
                    w[4],
                    w[5],
                    w[6]
                });
            }
        } else if (equal(cmd, "RPF")) {
            const i = try self.interface(w[1]);
            i.rpf = if (equal(w[2], "STRICT")) "strict" else if (equal(w[2], "LOOSE")) "loose" else "off";
            try self.out.line("ok rpf {s} {s}", .{
                i.name,
                i.rpf
            });
        } else if (equal(cmd, "TIMEOUT")) {
            const n = number(w[2]);
            if (n < 1 or n > 86400) return bad(gpa, "bad timeout {s}", .{
                w[2]
            });
            self.timeouts[protocolIndex(w[1])] = n;
            try self.out.line("ok timeout {s} {s}", .{
                w[1],
                w[2]
            });
        } else if (equal(cmd, "TICK")) {
            const n = number(w[1]);
            if (n < 1 or n > 86400) return bad(gpa, "bad tick {s}", .{
                w[1]
            });
            self.clock += n;
            const removed = self.expire();
            try self.out.line("ok tick time={d} expired conns={d} nat={d}", .{
                self.clock,
                removed[0],
                removed[1]
            });
        } else if (equal(cmd, "PACKET")) {
            const i = try self.interface(w[1]);
            const proto = w[2];
            const flags = w[3];
            if (!equal(proto, "TCP") and !equal(flags, "-")) return bad(gpa, "flags not allowed for {s}", .{
                proto
            });
            if (equal(proto, "TCP") and !equal(flags, "-")) {
                var seen: [256]bool = @splat(false);
                for (flags) |c| {
                    if (!includes("SAFR", c) or seen[c]) return bad(gpa, "bad flags {s}", .{
                        flags
                    });
                    seen[c] = true;
                }
            }
            const src = try checkedAddress(gpa, w[4]);
            const sp = number(w[5]);
            if (sp > 65535) return bad(gpa, "bad port {s}", .{
                w[5]
            });
            const dst = try checkedAddress(gpa, w[6]);
            const dp = number(w[7]);
            if (dp > 65535) return bad(gpa, "bad port {s}", .{
                w[7]
            });
            const ttl = number(w[8]);
            if (ttl < 1 or ttl > 255) return bad(gpa, "bad ttl {s}", .{
                w[8]
            });
            self.packet += 1;
            i.rx += 1;
            const verdict = try self.processPacket(i, .{
                .proto = proto,
                .src = src,
                .sport = sp,
                .dst = dst,
                .dport = dp
            }, flags, ttl);
            if (verdict.reason == 9) self.forwarded += 1 else if (verdict.reason == 10) self.local_count += 1 else {
                self.drops[verdict.reason] += 1;
                i.drop += 1;
            }
            try self.out.line("#{d} {s} {s} {s}:{s} > {s}:{s} {s}", .{
                self.packet,
                proto,
                flags,
                w[4],
                w[5],
                w[6],
                w[7],
                verdict.text
            });
        } else if (equal(cmd, "SHOW")) try self.show(w[1]) else if (equal(cmd, "CLEAR")) {
            if (equal(w[1], "CONNS")) {
                const c = self.conns.items.len;
                self.conns.items.len = 0;
                var m: usize = 0;
                for (self.ifaces.items) |i| {
                    m += i.mappings.items.len;
                    i.mappings.items.len = 0;
                }
                try self.out.line("ok clear conns={d} nat={d}", .{
                    c,
                    m
                });
            } else {
                self.forwarded = 0;
                self.local_count = 0;
                self.errors = 0;
                self.drops = @splat(0);
                for (self.ifaces.items) |i| {
                    i.rx = 0;
                    i.tx = 0;
                    i.drop = 0;
                    i.defaults = .{
                        0,
                        0
                    };
                    for (& i.rules) |*rs| for (rs.items) |r| {
                        r.hits = 0;
                    };
                }
                for (self.routes.items) |r| r.hits = 0;
                try self.out.add("ok clear counters\n");
            }
        }
    }
};

pub fn main(init: std.process.Init)!void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, & input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, & output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const count = number(lines.next().?);
    var router: Router = .{
        .gpa = gpa,
        .out = .{
            .gpa = gpa
        }
    };
    for (0..count) |_| {
        var words: std.ArrayList(Text) = .empty;
        var pieces = std.mem.splitScalar(u8, lines.next().?, ' ');
        while (pieces.next()) |word| try words.append(gpa, word);
        router.command(words.items) catch | err | {
            if (err != error.Invalid) return err;
            router.errors += 1;
            try router.out.line("error: {s}", .{
                error_message
            });
        };
    }
    try output.interface.writeAll(router.out.bytes.items);
    try output.interface.flush();
}
