const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
var reason: Text = "";
const type_names = [_]Text{ "A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA" };
const response_names = [_]Text{ "ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT" };
const Type = enum { a, ns, cname, soa, ptr, mx, txt, aaaa };
const ResponseKind = enum { answer, cname, referral, nodata, nxdomain, lame, timeout, servfail };
const CacheKind = enum { pos, nodata, nxdomain };
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    reason = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.print(pattern ++ "\n", args);
    }
    fn result(self: *const Builder) Text {
        return self.bytes.items;
    }
};
fn split(gpa: Allocator, text: Text, separator: u8) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    for (text, 0..) |c, i| {
        if (c == separator) {
            try result.append(gpa, text[start..i]);
            start = i + 1;
        }
    }
    try result.append(gpa, text[start..]);
    return result.items;
}
fn join(gpa: Allocator, parts: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (parts, 0..) |part, i| {
        if (i > 0) try out.add(separator);
        try out.add(part);
    }
    return out.result();
}
fn integerWord(s: Text) bool {
    if (s.len == 0 or s.len > 9 or (s.len > 1 and s[0] == '0')) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
fn number(s: Text) i64 {
    return std.fmt.parseInt(i64, s, 10) catch unreachable;
}
fn parseType(text: Text) ?Type {
    for (type_names, 0..) |name, i| if (equal(name, text)) return @fromBackingInt(@intCast(i));
    return null;
}
fn nameLength(name: Text) usize {
    if (equal(name, ".")) return 0;
    return std.mem.count(u8, name, ".");
}
fn below(name: Text, ancestor: Text) bool {
    return equal(ancestor, ".") or equal(name, ancestor) or (name.len > ancestor.len and name[name.len - ancestor.len - 1] == '.' and std.mem.endsWith(u8, name, ancestor));
}
fn nameCompare(a: Text, b: Text) std.math.Order {
    var ai: usize = if (equal(a, ".")) 0 else a.len - 1;
    var bi: usize = if (equal(b, ".")) 0 else b.len - 1;
    while (ai > 0 and bi > 0) {
        var ap = ai;
        var bp = bi;
        while (ap > 0 and a[ap - 1] != '.') ap -= 1;
        while (bp > 0 and b[bp - 1] != '.') bp -= 1;
        const order = std.mem.order(u8, a[ap..ai], b[bp..bi]);
        if (order != .eq) return order;
        ai = if (ap == 0) 0 else ap - 1;
        bi = if (bp == 0) 0 else bp - 1;
    }
    return std.math.order(ai, bi);
}
fn nameLess(_: void, a: Text, b: Text) bool {
    return nameCompare(a, b) == .lt;
}
fn ancestors(gpa: Allocator, name: Text) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var current = name;
    while (true) {
        try result.append(gpa, current);
        if (equal(current, ".")) return result.items;
        const at = std.mem.findScalar(u8, current, '.').?;
        current = current[at + 1 ..];
        if (current.len == 0) current = ".";
    }
}
fn parseName(gpa: Allocator, word: Text, origin: ?Text, wildcard: bool) Error!Text {
    if (origin != null and equal(word, "@")) return origin.?;
    if (equal(word, ".")) return ".";
    const absolute = std.mem.endsWith(u8, word, ".");
    const text = if (absolute) word[0 .. word.len - 1] else word;
    const labels = try split(gpa, text, '.');
    for (labels, 0..) |label, i| {
        if (wildcard and i == 0 and equal(label, "*")) continue;
        if (label.len == 0 or label.len > 63 or label[0] == '-' or label[label.len - 1] == '-') return bad(gpa, "bad name {s}", .{word});
        for (label) |c| if (!std.ascii.isAlphanumeric(c) and c != '-') return bad(gpa, "bad name {s}", .{word});
    }
    const lowered = try gpa.dupe(u8, text);
    for (lowered) |*c| c.* = std.ascii.toLower(c.*);
    return std.fmt.allocPrint(gpa, "{s}.{s}", .{ lowered, if (origin != null and !equal(origin.?, ".") and !absolute) origin.? else "" });
}
fn parseIPv4(gpa: Allocator, text: Text) Error!u32 {
    const fields = try split(gpa, text, '.');
    if (fields.len != 4) return bad(gpa, "bad address {s}", .{text});
    var result: u32 = 0;
    for (fields) |field| {
        if (field.len > 3 or !integerWord(field) or number(field) > 255) return bad(gpa, "bad address {s}", .{text});
        result = result * 256 + @as(u32, @intCast(number(field)));
    }
    return result;
}
fn ipv4(gpa: Allocator, address: u32) Allocator.Error!Text {
    return std.fmt.allocPrint(gpa, "{d}.{d}.{d}.{d}", .{ address >> 24, (address >> 16) & 255, (address >> 8) & 255, address & 255 });
}
fn hexGroups(gpa: Allocator, text: Text, whole: Text) Error![]u16 {
    var result: std.ArrayList(u16) = .empty;
    if (text.len == 0) return result.items;
    for (try split(gpa, text, ':')) |group| {
        if (group.len == 0 or group.len > 4) return bad(gpa, "bad address {s}", .{whole});
        for (group) |c| if (!std.ascii.isHex(c)) return bad(gpa, "bad address {s}", .{whole});
        try result.append(gpa, std.fmt.parseInt(u16, group, 16) catch unreachable);
    }
    return result.items;
}
fn parseIPv6(gpa: Allocator, text: Text) Error![8]u16 {
    var result: [8]u16 = @splat(0);
    if (std.mem.find(u8, text, "::")) |at| {
        const left = try hexGroups(gpa, text[0..at], text);
        const right = try hexGroups(gpa, text[at + 2 ..], text);
        if (left.len + right.len > 7) return bad(gpa, "bad address {s}", .{text});
        @memcpy(result[0..left.len], left);
        @memcpy(result[8 - right.len ..], right);
    } else {
        const groups = try hexGroups(gpa, text, text);
        if (groups.len != 8) return bad(gpa, "bad address {s}", .{text});
        @memcpy(result[0..], groups);
    }
    return result;
}
fn ipv6(gpa: Allocator, address: [8]u16) Allocator.Error!Text {
    var best: ?usize = null;
    var length: usize = 0;
    var i: usize = 0;
    while (i < 8) {
        if (address[i] != 0) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < 8 and address[end] == 0) end += 1;
        if (end - i >= 2 and end - i > length) {
            best = i;
            length = end - i;
        }
        i = end;
    }
    var groups: [8]Text = undefined;
    for (address, 0..) |value, j| groups[j] = try std.fmt.allocPrint(gpa, "{x}", .{value});
    if (best) |at| return std.fmt.allocPrint(gpa, "{s}::{s}", .{ try join(gpa, groups[0..at], ":"), try join(gpa, groups[at + length ..], ":") });
    return join(gpa, &groups, ":");
}
fn parseTTL(gpa: Allocator, text: Text) Error!i64 {
    if (integerWord(text)) {
        const n = number(text);
        if (n >= 1 and n <= 604800) return n;
        return bad(gpa, "bad ttl {s}", .{text});
    }
    const multipliers = [_]i64{ 604800, 86400, 3600, 60, 1 };
    var total: i64 = 0;
    var previous: ?usize = null;
    var pos: usize = 0;
    while (pos < text.len) {
        const start = pos;
        while (pos < text.len and std.ascii.isDigit(text[pos])) pos += 1;
        const digits = text[start..pos];
        if (digits.len > 3 or !integerWord(digits) or pos == text.len) return bad(gpa, "bad ttl {s}", .{text});
        const unit = std.mem.findScalar(u8, "wdhms", std.ascii.toLower(text[pos])) orelse return bad(gpa, "bad ttl {s}", .{text});
        if (previous != null and unit <= previous.?) return bad(gpa, "bad ttl {s}", .{text});
        total += number(digits) * multipliers[unit];
        previous = unit;
        pos += 1;
    }
    if (total < 1 or total > 604800) return bad(gpa, "bad ttl {s}", .{text});
    return total;
}
const Record = struct {
    owner: Text,
    ttl: i64,
    kind: Type,
    data: Text = "",
    target: Text = "",
    address: u32 = 0,
    address6: [8]u16 = @splat(0),
    preference: i64 = 0,
    minimum: i64 = 0,
    fn text(self: Record, gpa: Allocator) Allocator.Error!Text {
        return std.fmt.allocPrint(gpa, "{s} {d} {s} {s}", .{ self.owner, self.ttl, type_names[@backingInt(self.kind)], self.data });
    }
};
fn dataCompare(a: Record, b: Record) std.math.Order {
    switch (a.kind) {
        .a => return std.math.order(a.address, b.address),
        .aaaa => {
            for (a.address6, b.address6) |x, y| {
                const order = std.math.order(x, y);
                if (order != .eq) return order;
            }
            return .eq;
        },
        .ns, .cname, .ptr => return nameCompare(a.target, b.target),
        .mx => {
            const order = std.math.order(a.preference, b.preference);
            return if (order == .eq) nameCompare(a.target, b.target) else order;
        },
        else => return std.mem.order(u8, a.data, b.data),
    }
}
fn recordLess(_: void, a: Record, b: Record) bool {
    const order = nameCompare(a.owner, b.owner);
    if (order != .eq) return order == .lt;
    if (a.kind != b.kind) return @backingInt(a.kind) < @backingInt(b.kind);
    return dataCompare(a, b) == .lt;
}
fn sortedRecords(gpa: Allocator, records: []const Record) Allocator.Error![]Record {
    const result = try gpa.dupe(Record, records);
    std.mem.sort(Record, result, {}, recordLess);
    return result;
}
fn withTTL(gpa: Allocator, records: []const Record, ttl: i64) Allocator.Error![]Record {
    const result = try gpa.dupe(Record, records);
    for (result) |*record| record.ttl = ttl;
    return result;
}
const Zone = struct {
    origin: Text,
    server: u32,
    line: usize,
    records: std.ArrayList(Record) = .empty,
    fn recordsAt(self: *const Zone, gpa: Allocator, owner: Text, kind: ?Type) Allocator.Error![]Record {
        var out: std.ArrayList(Record) = .empty;
        for (self.records.items) |record| if (equal(record.owner, owner) and (kind == null or kind.? == record.kind)) {
            try out.append(gpa, record);
        };
        return sortedRecords(gpa, out.items);
    }
    fn exists(self: *const Zone, name: Text) bool {
        for (self.records.items) |record| if (below(record.owner, name)) return true;
        return false;
    }
    fn soa(self: *const Zone) ?Record {
        for (self.records.items) |record| if (record.kind == .soa) return record;
        return null;
    }
};
const Response = struct {
    kind: ResponseKind,
    referral: Text = "",
    answer: []const Record = &.{},
    authority: []const Record = &.{},
    additional: []const Record = &.{},
    message: Text = "",
    fn description(self: Response, gpa: Allocator) Allocator.Error!Text {
        if (self.kind == .referral) return std.fmt.allocPrint(gpa, "REFERRAL {s}", .{self.referral});
        if (self.kind == .cname) return std.fmt.allocPrint(gpa, "CNAME {s}", .{self.answer[0].target});
        if (self.kind == .servfail) return self.message;
        return response_names[@backingInt(self.kind)];
    }
};
const Key = struct {
    name: Text,
    kind: Type,
    fn same(a: Key, b: Key) bool {
        return a.kind == b.kind and equal(a.name, b.name);
    }
};
const Entry = struct { key: Key, kind: CacheKind, records: []const Record = &.{}, expiry: i64 };
const Stats = struct { server: u32, counts: [7]usize = @splat(0) };
const Result = struct { status: Text, answer: []const Record = &.{} };
const Resolver = struct {
    gpa: Allocator,
    out: Builder,
    roots: std.ArrayList(u32) = .empty,
    zones: std.ArrayList(*Zone) = .empty,
    current: ?*Zone = null,
    down: std.ArrayList(u32) = .empty,
    cache: std.ArrayList(Entry) = .empty,
    stats: std.ArrayList(Stats) = .empty,
    minttl: i64 = 1,
    maxttl: i64 = 86400,
    negttl: i64 = 3600,
    clock: i64 = 0,
    hits: usize = 0,
    resolutions: [4]usize = @splat(0),
    fn cached(self: *const Resolver, key: Key) ?Entry {
        for (self.cache.items) |entry| if (entry.key.same(key)) return entry;
        return null;
    }
    fn put(self: *Resolver, entry: Entry) Allocator.Error!void {
        for (self.cache.items) |*old| {
            if (old.key.same(entry.key)) {
                old.* = entry;
                return;
            }
        }
        try self.cache.append(self.gpa, entry);
    }
    fn isDown(self: *const Resolver, server: u32) bool {
        return std.mem.findScalar(u32, self.down.items, server) != null;
    }
    fn known(self: *const Resolver, server: u32) bool {
        for (self.zones.items) |zone| if (zone.server == server) return true;
        return false;
    }
    fn trace(self: *Resolver, depth: usize, comptime pattern: Text, args: anytype) Allocator.Error!void {
        for (0..2 * (depth + 1)) |_| try self.out.add(" ");
        try self.out.line(pattern, args);
    }
    fn zoneLine(self: *Resolver, words: []const Text, line: usize) Error!void {
        const gpa = self.gpa;
        if (equal(words[0], "ROOT")) {
            var pending: std.ArrayList(u32) = .empty;
            for (words[1..]) |word| {
                const address = try parseIPv4(gpa, word);
                if (std.mem.findScalar(u32, self.roots.items, address) != null or std.mem.findScalar(u32, pending.items, address) != null) return bad(gpa, "duplicate root {s}", .{word});
                try pending.append(gpa, address);
            }
            try self.roots.appendSlice(gpa, pending.items);
            return;
        }
        if (equal(words[0], "ZONE")) {
            self.current = null;
            const origin = try parseName(gpa, words[1], null, false);
            const server = try parseIPv4(gpa, words[2]);
            for (self.zones.items) |zone| if (equal(zone.origin, origin) and zone.server == server) return bad(gpa, "duplicate zone {s} at {s}", .{ origin, words[2] });
            const zone = try gpa.create(Zone);
            zone.* = .{ .origin = origin, .server = server, .line = line };
            try self.zones.append(gpa, zone);
            self.current = zone;
            return;
        }
        const zone = self.current orelse return bad(gpa, "no current zone", .{});
        const owner = try parseName(gpa, words[0], zone.origin, true);
        if (!below(owner, zone.origin)) return bad(gpa, "out of zone {s}", .{owner});
        const ttl = try parseTTL(gpa, words[1]);
        const kind = parseType(words[2]) orelse return bad(gpa, "bad type {s}", .{words[2]});
        const fields = words[3..];
        const required: usize = if (kind == .mx) 2 else if (kind == .soa) 7 else 1;
        if (kind != .txt and fields.len != required) return bad(gpa, "wrong field count", .{});
        var record: Record = .{ .owner = owner, .ttl = ttl, .kind = kind };
        switch (kind) {
            .a => {
                record.address = try parseIPv4(gpa, fields[0]);
                record.data = try ipv4(gpa, record.address);
            },
            .aaaa => {
                record.address6 = try parseIPv6(gpa, fields[0]);
                record.data = try ipv6(gpa, record.address6);
            },
            .ns, .cname, .ptr => {
                record.target = try parseName(gpa, fields[0], zone.origin, false);
                record.data = record.target;
            },
            .mx => {
                if (!integerWord(fields[0]) or number(fields[0]) > 65535) return bad(gpa, "bad preference {s}", .{fields[0]});
                record.preference = number(fields[0]);
                record.target = try parseName(gpa, fields[1], zone.origin, false);
                record.data = try std.fmt.allocPrint(gpa, "{d} {s}", .{ record.preference, record.target });
            },
            .txt => {
                record.data = try join(gpa, fields, " ");
                if (record.data.len < 2 or record.data[0] != '"' or record.data[record.data.len - 1] != '"' or std.mem.findScalar(u8, record.data[1 .. record.data.len - 1], '"') != null) return bad(gpa, "bad text {s}", .{record.data});
            },
            .soa => {
                const data = try gpa.dupe(Text, fields);
                data[0] = try parseName(gpa, fields[0], zone.origin, false);
                data[1] = try parseName(gpa, fields[1], zone.origin, false);
                for (fields[2..6]) |field| if (!integerWord(field)) return bad(gpa, "bad number {s}", .{field});
                if (!integerWord(fields[6]) or number(fields[6]) < 1 or number(fields[6]) > 86400) return bad(gpa, "bad minimum {s}", .{fields[6]});
                record.minimum = number(fields[6]);
                record.data = try join(gpa, data, " ");
            },
        }
        if (kind == .ns and std.mem.startsWith(u8, owner, "*.")) return bad(gpa, "ns at wildcard", .{});
        if (kind == .soa and !equal(owner, zone.origin)) return bad(gpa, "soa not at origin", .{});
        if (kind == .soa and zone.soa() != null) return bad(gpa, "duplicate soa", .{});
        for (zone.records.items) |old| if (equal(old.owner, owner) and old.kind == kind and equal(old.data, record.data)) return bad(gpa, "duplicate record", .{});
        for (zone.records.items) |old| if (equal(old.owner, owner) and (kind == .cname or old.kind == .cname)) return bad(gpa, "cname conflict {s}", .{owner});
        try zone.records.append(gpa, record);
    }
    fn finishZones(self: *Resolver) Error!void {
        var kept: std.ArrayList(*Zone) = .empty;
        var count: usize = 0;
        for (self.zones.items) |zone| {
            if (zone.soa() == null) try self.out.line("error line {d}: zone {s} at {s} has no soa", .{ zone.line, zone.origin, try ipv4(self.gpa, zone.server) }) else {
                try kept.append(self.gpa, zone);
                count += zone.records.items.len;
                try self.out.line("zone {s} at {s} records={d}", .{ zone.origin, try ipv4(self.gpa, zone.server), zone.records.items.len });
            }
        }
        self.zones = kept;
        self.current = null;
        try self.out.line("loaded roots={d} zones={d} records={d}", .{ self.roots.items.len, self.zones.items.len, count });
    }
    fn negative(self: *Resolver, kind: ResponseKind, zone: *Zone) Allocator.Error!Response {
        const records = try self.gpa.alloc(Record, 1);
        records[0] = zone.soa().?;
        return .{ .kind = kind, .authority = records };
    }
    fn authoritative(self: *Resolver, server: u32, name: Text, kind: Type, cut: Text) Error!Response {
        const gpa = self.gpa;
        if (self.isDown(server) or !self.known(server)) return .{ .kind = .timeout };
        var selected: ?*Zone = null;
        for (self.zones.items) |zone| {
            if (zone.server == server and below(name, zone.origin) and (selected == null or nameLength(zone.origin) > nameLength(selected.?.origin))) selected = zone;
        }
        const zone = selected orelse return .{ .kind = .lame };
        if (nameLength(zone.origin) < nameLength(cut)) return .{ .kind = .lame };
        const chain = try ancestors(gpa, name);
        var i = chain.len;
        while (i > 0) {
            i -= 1;
            const delegation = chain[i];
            if (equal(delegation, zone.origin) or !below(delegation, zone.origin)) continue;
            const ns = try zone.recordsAt(gpa, delegation, .ns);
            if (ns.len > 0) {
                var additional: std.ArrayList(Record) = .empty;
                for (ns) |record| try additional.appendSlice(gpa, try zone.recordsAt(gpa, record.target, .a));
                return .{ .kind = .referral, .referral = delegation, .authority = ns, .additional = additional.items };
            }
        }
        var records = try zone.recordsAt(gpa, name, null);
        if (records.len == 0) {
            if (zone.exists(name)) return self.negative(.nodata, zone);
            var wildcard: Text = "";
            for (chain[1..]) |ancestor| {
                if (zone.exists(ancestor)) {
                    wildcard = try std.fmt.allocPrint(gpa, "*.{s}", .{if (equal(ancestor, ".")) "" else ancestor});
                    break;
                }
            }
            records = try zone.recordsAt(gpa, wildcard, null);
            if (records.len == 0) return self.negative(.nxdomain, zone);
        }
        var answers: std.ArrayList(Record) = .empty;
        for (records) |original| {
            if (original.kind == kind) {
                var record = original;
                record.owner = name;
                try answers.append(gpa, record);
            }
        }
        if (answers.items.len > 0) return .{ .kind = .answer, .answer = try sortedRecords(gpa, answers.items) };
        if (kind != .cname) {
            for (records) |original| {
                if (original.kind == .cname) {
                    var record = original;
                    record.owner = name;
                    try answers.append(gpa, record);
                    return .{ .kind = .cname, .answer = answers.items };
                }
            }
        }
        return self.negative(.nodata, zone);
    }
    fn ask(self: *Resolver, server: u32, name: Text, kind: Type, cut: Text) Error!Response {
        const answer = try self.authoritative(server, name, kind, cut);
        for (self.stats.items) |*stats| {
            if (stats.server == server) {
                stats.counts[@backingInt(answer.kind)] += 1;
                return answer;
            }
        }
        var stats: Stats = .{ .server = server };
        stats.counts[@backingInt(answer.kind)] = 1;
        try self.stats.append(self.gpa, stats);
        return answer;
    }
    fn store(self: *Resolver, records: []const Record) Error!i64 {
        var ttl = records[0].ttl;
        for (records) |record| ttl = @min(ttl, record.ttl);
        ttl = @min(@max(ttl, self.minttl), self.maxttl);
        try self.put(.{ .key = .{ .name = records[0].owner, .kind = records[0].kind }, .kind = .pos, .records = try sortedRecords(self.gpa, records), .expiry = self.clock + ttl });
        return ttl;
    }
    fn queryAddress(self: *Resolver, server: u32, name: Text, kind: Type, cut: Text, depth: usize) Error!?Response {
        const answer = try self.ask(server, name, kind, cut);
        try self.trace(depth, "ASK {s} {s} {s} -> {s}", .{ try ipv4(self.gpa, server), name, type_names[@backingInt(kind)], try answer.description(self.gpa) });
        return if (answer.kind == .lame or answer.kind == .timeout) null else answer;
    }
    fn queryServers(self: *Resolver, name: Text, kind: Type, cut: Text, names: []const Text, roots: bool, depth: usize, resolving: []const Key) Error!?Response {
        const gpa = self.gpa;
        if (roots) {
            for (self.roots.items) |server| if (try self.queryAddress(server, name, kind, cut, depth)) |answer| return answer;
            return null;
        }
        const ordered_names = try gpa.dupe(Text, names);
        std.mem.sort(Text, ordered_names, {}, nameLess);
        for (ordered_names) |host| {
            var addresses: std.ArrayList(u32) = .empty;
            const key: Key = .{ .name = host, .kind = .a };
            const cache_entry = self.cached(key);
            if (cache_entry != null and cache_entry.?.kind == .pos) {
                for (cache_entry.?.records) |record| try addresses.append(gpa, record.address);
            } else {
                var loop = false;
                for (resolving) |pair| if (pair.same(key)) {
                    loop = true;
                    break;
                };
                if (loop) try self.trace(depth, "GLUELESS {s} -> LOOP", .{host}) else {
                    try self.trace(depth, "GLUELESS {s}", .{host});
                    const answer = try self.resolve(host, .a, depth + 1, resolving);
                    if (equal(answer.status, "NOERROR")) {
                        for (answer.answer) |record| if (record.kind == .a) {
                            try addresses.append(gpa, record.address);
                        };
                    }
                }
            }
            std.mem.sort(u32, addresses.items, {}, lessAddress);
            var previous: ?u32 = null;
            for (addresses.items) |server| {
                if (previous != null and previous.? == server) continue;
                previous = server;
                if (try self.queryAddress(server, name, kind, cut, depth)) |answer| return answer;
            }
        }
        return null;
    }
    fn lookup(self: *Resolver, name: Text, kind: Type, depth: usize, resolving: []const Key) Error!Response {
        const gpa = self.gpa;
        const key: Key = .{ .name = name, .kind = kind };
        if (self.cached(key)) |entry| {
            self.hits += 1;
            const result: Response = if (entry.kind == .pos) .{ .kind = .answer, .answer = try withTTL(gpa, entry.records, entry.expiry - self.clock) } else .{ .kind = if (entry.kind == .nodata) .nodata else .nxdomain };
            try self.trace(depth, "CACHE HIT {s} {s} -> {s}", .{ name, type_names[@backingInt(kind)], response_names[@backingInt(result.kind)] });
            return result;
        }
        for (self.cache.items) |entry| {
            if (entry.kind == .nxdomain and below(name, entry.key.name)) {
                self.hits += 1;
                try self.trace(depth, "CACHE HIT {s} {s} -> NXDOMAIN", .{ name, type_names[@backingInt(kind)] });
                return .{ .kind = .nxdomain };
            }
        }
        if (kind != .cname) {
            if (self.cached(.{ .name = name, .kind = .cname })) |entry| {
                if (entry.kind == .pos) {
                    self.hits += 1;
                    const records = try withTTL(gpa, entry.records, entry.expiry - self.clock);
                    try self.trace(depth, "CACHE HIT {s} {s} -> CNAME {s}", .{ name, type_names[@backingInt(kind)], records[0].target });
                    return .{ .kind = .cname, .answer = records };
                }
            }
        }
        var cut: Text = ".";
        var names: std.ArrayList(Text) = .empty;
        var roots = true;
        for (try ancestors(gpa, name)) |ancestor| {
            if (self.cached(.{ .name = ancestor, .kind = .ns })) |entry| {
                if (entry.kind == .pos) {
                    cut = ancestor;
                    roots = false;
                    for (entry.records) |record| try names.append(gpa, record.target);
                    self.hits += 1;
                    try self.trace(depth, "CACHE HIT {s} {s} -> REFERRAL {s}", .{ name, type_names[@backingInt(kind)], cut });
                    break;
                }
            }
        }
        while (true) {
            var answer = (try self.queryServers(name, kind, cut, names.items, roots, depth, resolving)) orelse return .{ .kind = .servfail, .message = try std.fmt.allocPrint(gpa, "SERVFAIL no server for {s}", .{cut}) };
            if (answer.kind == .referral) {
                _ = try self.store(answer.authority);
                var owners: std.ArrayList(Text) = .empty;
                for (answer.additional) |record| {
                    var found = false;
                    for (owners.items) |owner| if (equal(record.owner, owner)) {
                        found = true;
                        break;
                    };
                    if (!found) try owners.append(gpa, record.owner);
                }
                for (owners.items) |owner| {
                    var grouped: std.ArrayList(Record) = .empty;
                    for (answer.additional) |record| if (equal(owner, record.owner)) {
                        try grouped.append(gpa, record);
                    };
                    _ = try self.store(grouped.items);
                }
                cut = answer.referral;
                names = .empty;
                roots = false;
                for (answer.authority) |record| try names.append(gpa, record.target);
            } else if (answer.kind == .answer or answer.kind == .cname) {
                answer.answer = try withTTL(gpa, answer.answer, try self.store(answer.answer));
                return answer;
            } else {
                const soa = answer.authority[0];
                const ttl = @min(@min(soa.ttl, soa.minimum), self.negttl);
                try self.put(.{ .key = key, .kind = if (answer.kind == .nodata) .nodata else .nxdomain, .expiry = self.clock + ttl });
                return answer;
            }
        }
    }
    fn resolve(self: *Resolver, name: Text, kind: Type, depth: usize, resolving: []const Key) Error!Result {
        const gpa = self.gpa;
        var active: std.ArrayList(Key) = .empty;
        try active.appendSlice(gpa, resolving);
        try active.append(gpa, .{ .name = name, .kind = kind });
        var chain: std.ArrayList(Record) = .empty;
        var seen: std.ArrayList(Text) = .empty;
        try seen.append(gpa, name);
        var current = name;
        var result: Result = undefined;
        while (true) {
            const answer = try self.lookup(current, kind, depth, active.items);
            if (answer.kind == .cname) {
                const record = answer.answer[0];
                try chain.append(gpa, record);
                var loop = false;
                for (seen.items) |old| if (equal(old, record.target)) {
                    loop = true;
                    break;
                };
                if (loop) {
                    result = .{ .status = "SERVFAIL cname loop" };
                    break;
                }
                if (chain.items.len == 9) {
                    result = .{ .status = "SERVFAIL cname chain too long" };
                    break;
                }
                try seen.append(gpa, record.target);
                current = record.target;
            } else if (answer.kind == .answer) {
                try chain.appendSlice(gpa, answer.answer);
                result = .{ .status = "NOERROR", .answer = chain.items };
                break;
            } else if (answer.kind == .nodata or answer.kind == .nxdomain) {
                result = .{ .status = response_names[@backingInt(answer.kind)], .answer = chain.items };
                break;
            } else {
                result = .{ .status = answer.message };
                break;
            }
        }
        const index: usize = if (equal(result.status, "NOERROR")) 0 else if (equal(result.status, "NODATA")) 1 else if (equal(result.status, "NXDOMAIN")) 2 else 3;
        self.resolutions[index] += 1;
        return result;
    }
    fn emitResult(self: *Resolver, result: Result) Error!void {
        for (result.answer) |record| try self.out.line("answer {s}", .{try record.text(self.gpa)});
        try self.out.line("status {s}", .{result.status});
    }
    fn addressResolution(self: *Resolver, host: Text, prefix: Text) Error!void {
        const a = try self.resolve(host, .a, 0, &.{});
        const aaaa = try self.resolve(host, .aaaa, 0, &.{});
        var addresses: std.ArrayList(Text) = .empty;
        for ([_]Result{ a, aaaa }) |result| {
            if (equal(result.status, "NOERROR")) {
                for (result.answer) |record| if (record.kind == .a or record.kind == .aaaa) {
                    try addresses.append(self.gpa, record.data);
                };
            }
        }
        try self.out.line("{s} -> {s}", .{ prefix, if (addresses.items.len == 0) "no address" else try join(self.gpa, addresses.items, " ") });
    }
    fn command(self: *Resolver, words: []const Text) Error!void {
        const gpa = self.gpa;
        const cmd = words[0];
        if (equal(cmd, "RESOLVE") or equal(cmd, "MX")) {
            const name = try parseName(gpa, words[1], null, true);
            const kind = if (equal(cmd, "MX")) Type.mx else parseType(words[2]) orelse return bad(gpa, "bad type {s}", .{words[2]});
            if (equal(cmd, "MX")) try self.out.line("mx {s}", .{name}) else try self.out.line("resolve {s} {s}", .{ name, type_names[@backingInt(kind)] });
            const result = try self.resolve(name, kind, 0, &.{});
            try self.emitResult(result);
            if (equal(cmd, "MX")) {
                if (equal(result.status, "NOERROR")) {
                    for (result.answer) |record| {
                        if (record.kind == .mx) {
                            const prefix = try std.fmt.allocPrint(gpa, "exchange {d} {s}", .{ record.preference, record.target });
                            if (equal(record.target, ".")) try self.out.line("{s} -> null", .{prefix}) else try self.addressResolution(record.target, prefix);
                        }
                    }
                } else if (equal(result.status, "NODATA")) {
                    var host = name;
                    for (result.answer) |record| if (record.kind == .cname) {
                        host = record.target;
                    };
                    try self.addressResolution(host, try std.fmt.allocPrint(gpa, "implicit {s}", .{host}));
                }
            }
        } else if (equal(cmd, "REVERSE")) {
            var text: Text = undefined;
            var name: Text = undefined;
            if (std.mem.findScalar(u8, words[1], ':') != null) {
                const address = try parseIPv6(gpa, words[1]);
                text = try ipv6(gpa, address);
                var digits: Builder = .{ .gpa = gpa };
                for (address) |value| try digits.print("{x:0>4}", .{value});
                var labels: std.ArrayList(Text) = .empty;
                var i = digits.result().len;
                while (i > 0) {
                    i -= 1;
                    try labels.append(gpa, digits.result()[i .. i + 1]);
                }
                name = try std.fmt.allocPrint(gpa, "{s}.ip6.arpa.", .{try join(gpa, labels.items, ".")});
            } else {
                const address = try parseIPv4(gpa, words[1]);
                text = try ipv4(gpa, address);
                const fields = try split(gpa, text, '.');
                name = try std.fmt.allocPrint(gpa, "{s}.{s}.{s}.{s}.in-addr.arpa.", .{ fields[3], fields[2], fields[1], fields[0] });
            }
            try self.out.line("reverse {s} {s}", .{ text, name });
            try self.emitResult(try self.resolve(name, .ptr, 0, &.{}));
        } else if (equal(cmd, "QUERY") or equal(cmd, "DUMP")) {
            const server = try parseIPv4(gpa, words[1]);
            const name = try parseName(gpa, words[2], null, equal(cmd, "QUERY"));
            if (equal(cmd, "QUERY")) {
                const kind = parseType(words[3]) orelse return bad(gpa, "bad type {s}", .{words[3]});
                const answer = try self.ask(server, name, kind, ".");
                try self.out.line("query {s} {s} {s} -> {s}", .{ try ipv4(gpa, server), name, type_names[@backingInt(kind)], try answer.description(gpa) });
                for (answer.answer) |record| try self.out.line("answer {s}", .{try record.text(gpa)});
                for (answer.authority) |record| try self.out.line("authority {s}", .{try record.text(gpa)});
                for (answer.additional) |record| try self.out.line("additional {s}", .{try record.text(gpa)});
            } else {
                if (self.isDown(server) or !self.known(server)) {
                    try self.out.line("dump {s} {s} -> TIMEOUT", .{ try ipv4(gpa, server), name });
                    return;
                }
                for (self.zones.items) |zone| {
                    if (zone.server == server and equal(zone.origin, name)) {
                        try self.out.line("dump {s} {s} records={d}", .{ try ipv4(gpa, server), name, zone.records.items.len });
                        for (try sortedRecords(gpa, zone.records.items)) |record| try self.out.line("  {s}", .{try record.text(gpa)});
                        return;
                    }
                }
                try self.out.line("dump {s} {s} -> REFUSED", .{ try ipv4(gpa, server), name });
            }
        } else if (equal(cmd, "DOWN") or equal(cmd, "UP")) {
            const server = try parseIPv4(gpa, words[1]);
            const at = std.mem.findScalar(u32, self.down.items, server);
            if (equal(cmd, "DOWN")) {
                if (at != null) return bad(gpa, "server {s} already down", .{words[1]});
                try self.down.append(gpa, server);
                try self.out.line("down {s}", .{try ipv4(gpa, server)});
            } else {
                if (at == null) return bad(gpa, "server {s} not down", .{words[1]});
                _ = self.down.orderedRemove(at.?);
                try self.out.line("up {s}", .{try ipv4(gpa, server)});
            }
        } else if (equal(cmd, "SET")) {
            const key = words[1];
            if (!equal(key, "MINTTL") and !equal(key, "MAXTTL") and !equal(key, "NEGTTL")) return bad(gpa, "bad setting {s}", .{key});
            if (!integerWord(words[2]) or number(words[2]) < 1 or number(words[2]) > 604800) return bad(gpa, "bad value {s}", .{words[2]});
            const n = number(words[2]);
            const minimum = if (equal(key, "MINTTL")) n else self.minttl;
            const maximum = if (equal(key, "MAXTTL")) n else self.maxttl;
            if (minimum > maximum) return bad(gpa, "minttl above maxttl", .{});
            if (equal(key, "MINTTL")) self.minttl = n else if (equal(key, "MAXTTL")) self.maxttl = n else self.negttl = n;
            try self.out.line("set {s}={d}", .{ key, n });
        } else if (equal(cmd, "TIME")) {
            if (!integerWord(words[1]) or number(words[1]) < 1 or number(words[1]) > 1000000) return bad(gpa, "bad time {s}", .{words[1]});
            self.clock += number(words[1]);
            var expired: usize = 0;
            var i: usize = 0;
            while (i < self.cache.items.len) {
                if (self.cache.items[i].expiry <= self.clock) {
                    _ = self.cache.orderedRemove(i);
                    expired += 1;
                } else i += 1;
            }
            try self.out.line("time now={d} expired={d}", .{ self.clock, expired });
        } else if (equal(cmd, "CACHE") or equal(cmd, "FLUSH")) {
            const ancestor = if (words.len == 2) try parseName(gpa, words[1], null, false) else ".";
            var entries: std.ArrayList(Entry) = .empty;
            for (self.cache.items) |entry| if (below(entry.key.name, ancestor)) {
                try entries.append(gpa, entry);
            };
            std.mem.sort(Entry, entries.items, {}, entryLess);
            if (equal(cmd, "FLUSH")) {
                var i: usize = 0;
                while (i < self.cache.items.len) {
                    if (below(self.cache.items[i].key.name, ancestor)) {
                        _ = self.cache.orderedRemove(i);
                    } else i += 1;
                }
                try self.out.line("flush removed={d}", .{entries.items.len});
            } else {
                try self.out.line("cache entries={d}", .{entries.items.len});
                for (entries.items) |entry| {
                    if (entry.kind == .pos) {
                        for (try withTTL(gpa, entry.records, entry.expiry - self.clock)) |record| try self.out.line("  {s}", .{try record.text(gpa)});
                    } else try self.out.line("  {s} {d} {s} {s}", .{ entry.key.name, entry.expiry - self.clock, type_names[@backingInt(entry.key.kind)], if (entry.kind == .nodata) "NODATA" else "NXDOMAIN" });
                }
            }
        } else if (equal(cmd, "STATS")) {
            std.mem.sort(Stats, self.stats.items, {}, statsLess);
            var total: usize = 0;
            for (self.stats.items) |stats| for (stats.counts) |n| {
                total += n;
            };
            try self.out.line("stats queries={d} hits={d}", .{ total, self.hits });
            const labels = [_]Text{ "answer", "cname", "referral", "nodata", "nxdomain", "lame", "timeout" };
            for (self.stats.items) |stats| {
                var sent: usize = 0;
                for (stats.counts) |n| sent += n;
                try self.out.print("  {s} sent={d}", .{ try ipv4(gpa, stats.server), sent });
                for (stats.counts, labels) |n, label| try self.out.print(" {s}={d}", .{ label, n });
                try self.out.add("\n");
            }
            try self.out.line("resolutions noerror={d} nodata={d} nxdomain={d} servfail={d}", .{ self.resolutions[0], self.resolutions[1], self.resolutions[2], self.resolutions[3] });
        }
    }
    fn run(self: *Resolver, lines: []const Text) Error!void {
        var at: usize = 0;
        while (!equal(lines[at], "END ZONES")) : (at += 1) {
            self.zoneLine(try split(self.gpa, lines[at], ' '), at + 1) catch |err| {
                if (err != error.Invalid) return err;
                try self.out.line("error line {d}: {s}", .{ at + 1, reason });
            };
        }
        try self.finishZones();
        at += 1;
        while (!equal(lines[at], "END")) : (at += 1) {
            self.command(try split(self.gpa, lines[at], ' ')) catch |err| {
                if (err != error.Invalid) return err;
                try self.out.line("error line {d}: {s}", .{ at + 1, reason });
            };
        }
    }
};
fn lessAddress(_: void, a: u32, b: u32) bool {
    return a < b;
}
fn entryLess(_: void, a: Entry, b: Entry) bool {
    const order = nameCompare(a.key.name, b.key.name);
    return if (order == .eq) @backingInt(a.key.kind) < @backingInt(b.key.kind) else order == .lt;
}
fn statsLess(_: void, a: Stats, b: Stats) bool {
    return a.server < b.server;
}
pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var resolver: Resolver = .{ .gpa = gpa, .out = .{ .gpa = gpa } };
    try resolver.run(try split(gpa, text, '\n'));
    try output.interface.writeAll(resolver.out.result());
    try output.interface.flush();
}
