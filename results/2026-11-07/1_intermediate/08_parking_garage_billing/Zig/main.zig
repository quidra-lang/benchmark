const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const types = [_][]const u8{ "MOTORCYCLE", "CAR", "ECAR", "VAN", "BUS" };
const kinds = [_][]const u8{ "MOTO", "COMPACT", "LARGE", "EV" };
const preferences = [_][]const usize{ &.{ 0, 1, 2 }, &.{ 1, 2 }, &.{ 3, 1, 2 }, &.{2}, &.{2} };
fn integer(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch unreachable;
}
fn index(names: []const []const u8, s: []const u8) ?usize {
    for (names, 0..) |name, i| {
        if (std.mem.eql(u8, name, s)) return i;
    }
    return null;
}
fn date(t: i64) i64 {
    return @divTrunc(t, 1440) + 1;
}
const Spot = struct {
    level: usize,
    number: usize,
    kind: usize,
    closed: bool = false,
    occupant: ?*Vehicle = null,
};
const Vehicle = struct {
    plate: []const u8,
    kind: usize,
    entry: i64,
    start: usize,
    kwh: i64 = 0,
    charge: i64 = 0,
    validation: i64 = 0,
    payment: ?[3]i64 = null,

    fn width(v: *const Vehicle) usize {
        return if (v.kind == 4) 3 else 1;
    }
};
const Waiting = struct {
    plate: []const u8,
    kind: usize,
    joined: i64,
};
const Record = struct {
    plate: []const u8,
    location: []const u8,
    kind: usize,
    entry: i64,
    exit: i64,
    fees: [6]i64,
    lost: bool,
};
const Stats = struct {
    entries: [5]i64 = @splat(0),
    exits: [5]i64 = @splat(0),
    refused: [5]i64 = @splat(0),
    revenue: [5]i64 = @splat(0),
    stays: [5]i64 = @splat(0),
};
const Garage = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    now: i64 = 0,
    peak: usize = 0,
    peak_time: ?i64 = null,
    spots: [1080]Spot = undefined,
    spot_count: usize = 0,
    levels: [9]struct { first: usize, end: usize } = undefined,
    level_count: usize = 0,
    vehicles: std.StringArrayHashMapUnmanaged(*Vehicle) = .empty,
    queue: std.ArrayList(Waiting) = .empty,
    records: std.ArrayList(Record) = .empty,
    passes: std.StringHashMapUnmanaged(i64) = .empty,
    rates: [5]i64 = .{ 100, 200, 200, 300, 600 },
    caps: [5]i64 = .{ 800, 1600, 1600, 2400, 4800 },
    amounts: [3]i64 = .{ 300, 2000, 30 },
    stats: Stats = .{},
    daily: [1000]Stats = @splat(.{}),

    fn fail(self: *Garage, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn duration(self: *Garage, t: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(t);
        return std.fmt.allocPrint(self.gpa, "{d}:{d:0>2}", .{ u / 60, u % 60 });
    }
    fn time(self: *Garage, t: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(@mod(t, 1440));
        return std.fmt.allocPrint(self.gpa, "{d}-{d:0>2}:{d:0>2}", .{ date(t), u / 60, u % 60 });
    }
    fn decimal(self: *Garage, q: i64) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.gpa, "{d}.{d}", .{ @divTrunc(q, 10), @mod(q, 10) });
    }
    fn pass(self: *Garage, plate: []const u8) bool {
        return (self.passes.get(plate) orelse 0) >= date(self.now);
    }
    fn parked(self: *Garage, plate: []const u8) Error!*Vehicle {
        return self.vehicles.get(plate) orelse return self.fail("{s} is not parked", .{plate});
    }
    fn waiting(self: *Garage, plate: []const u8) ?usize {
        for (self.queue.items, 0..) |w, i| {
            if (std.mem.eql(u8, w.plate, plate)) return i;
        }
        return null;
    }
    fn spotLabel(self: *Garage, start: usize) Allocator.Error![]const u8 {
        const s = self.spots[start];
        return std.fmt.allocPrint(self.gpa, "L{d}-{d}", .{ s.level, s.number });
    }
    fn location(self: *Garage, v: *const Vehicle) Allocator.Error![]const u8 {
        const s = self.spots[v.start];
        if (v.kind == 4) return std.fmt.allocPrint(self.gpa, "L{d}-{d}..{d}", .{ s.level, s.number, s.number + 2 });
        return self.spotLabel(v.start);
    }
    fn findSpot(self: *Garage, s: []const u8) Error!usize {
        const dash = std.mem.findScalar(u8, s, '-').?;
        const l: usize = @intCast(integer(s[1..dash]));
        const n: usize = @intCast(integer(s[dash + 1 ..]));
        if (l > self.level_count) return self.fail("unknown spot {s}", .{s});
        const level = self.levels[l - 1];
        if (n > level.end - level.first) return self.fail("unknown spot {s}", .{s});
        return level.first + n - 1;
    }
    fn free(self: *Garage, i: usize) bool {
        return !self.spots[i].closed and self.spots[i].occupant == null;
    }
    fn assign(self: *Garage, kind: usize) ?usize {
        if (kind == 4) {
            for (self.levels[0..self.level_count]) |l| {
                var i = l.first;
                while (i + 2 < l.end) : (i += 1) {
                    var ok = true;
                    for (i..i + 3) |j| {
                        if (self.spots[j].kind != 2 or !self.free(j)) ok = false;
                    }
                    if (ok) return i;
                }
            }
        } else {
            for (preferences[kind]) |k| {
                for (0..self.spot_count) |i| {
                    if (self.spots[i].kind == k and self.free(i)) return i;
                }
            }
        }
        return null;
    }
    fn park(self: *Garage, plate: []const u8, kind: usize, start: usize) Error!*Vehicle {
        const v = try self.gpa.create(Vehicle);
        v.* = .{ .plate = plate, .kind = kind, .entry = self.now, .start = start };
        try self.vehicles.put(self.gpa, plate, v);
        for (start..start + v.width()) |i| self.spots[i].occupant = v;
        self.stats.entries[kind] += 1;
        self.daily[@intCast(date(self.now))].entries[kind] += 1;
        if (self.vehicles.count() > self.peak) {
            self.peak = self.vehicles.count();
            self.peak_time = self.now;
        }
        return v;
    }
    fn refuse(self: *Garage, kind: usize, t: i64) void {
        self.stats.refused[kind] += 1;
        self.daily[@intCast(date(t))].refused[kind] += 1;
    }
    fn giveup(self: *Garage) Error!void {
        var i: usize = 0;
        while (i < self.queue.items.len) {
            const w = self.queue.items[i];
            if (self.now - w.joined >= 30) {
                _ = self.queue.orderedRemove(i);
                self.refuse(w.kind, w.joined + 30);
                try self.out.print("GIVEUP {s} {s} {s}\n", .{ w.plate, types[w.kind], try self.time(w.joined + 30) });
            } else i += 1;
        }
    }
    fn admit(self: *Garage) Error!void {
        var i: usize = 0;
        while (i < self.queue.items.len) {
            const w = self.queue.items[i];
            if (self.assign(w.kind)) |place| {
                _ = self.queue.orderedRemove(i);
                const v = try self.park(w.plate, w.kind, place);
                try self.out.print("ADMIT {s} {s} {s} waited {s}\n", .{ w.plate, types[w.kind], try self.location(v), try self.duration(self.now - w.joined) });
            } else i += 1;
        }
    }
    fn interval(self: *Garage, v: *Vehicle, a: i64, free_time: i64) [2]i64 {
        const total = self.now - a;
        if (self.pass(v.plate) or total <= free_time) return .{ 0, 0 };
        var parking: i64 = 0;
        var offset: i64 = 0;
        while (offset < total) : (offset += 1440) {
            const bill = @min(total - offset, 1440) - (if (offset == 0) free_time else @as(i64, 0));
            parking += @min(@divTrunc(bill + 29, 30) * self.rates[v.kind], self.caps[v.kind]);
        }
        return .{ parking, (date(self.now) - date(a)) * self.amounts[0] };
    }
    fn charges(self: *Garage, v: *Vehicle, lost: bool) [6]i64 {
        var parking: i64 = 0;
        var night: i64 = 0;
        var due: i64 = 0;
        const loss = if (lost) self.amounts[1] else 0;
        if (v.payment) |p| {
            const f = self.interval(v, p[0], 15);
            parking = p[1] + f[0];
            night = p[2] + f[1];
            due = f[0] + f[1];
        } else {
            const f = self.interval(v, v.entry, 15 + v.validation);
            parking = f[0];
            night = f[1];
            due = parking + night + loss + v.charge;
        }
        return .{ parking, night, loss, v.charge, parking + night + loss + v.charge, due };
    }
    fn annotation(self: *Garage, v: *Vehicle) Error!void {
        if (self.pass(v.plate)) try self.out.writeAll(" PASS");
        if (v.validation != 0) try self.out.print(" VAL {d}", .{v.validation});
        if (v.kwh != 0) try self.out.print(" KWH {d}", .{v.kwh});
        if (v.payment != null) try self.out.writeAll(" PAID");
    }
    fn ordered(self: *Garage) Error![]*Vehicle {
        const vs = try self.gpa.dupe(*Vehicle, self.vehicles.values());
        std.mem.sort(*Vehicle, vs, {}, locationLess);
        return vs;
    }
    fn feeLine(self: *Garage, label: []const u8, v: *Vehicle, f: [6]i64) Error!void {
        try self.out.print("{s} {s} {s} stay {s} parking {d} night {d} lost {d} charge {d} total {d} due {d}\n", .{
            label, v.plate, try self.location(v), try self.duration(self.now - v.entry), f[0], f[1], f[2], f[3], f[4], f[5],
        });
    }
    fn move(self: *Garage, v: *Vehicle, dest: usize) Error!void {
        const old = try self.location(v);
        self.spots[v.start].occupant = null;
        v.start = dest;
        self.spots[dest].occupant = v;
        try self.out.print("MOVE {s} {s} -> {s}\n", .{ v.plate, old, try self.location(v) });
    }
    fn execute(self: *Garage, a: []const []const u8) Error!void {
        const op = a[2];
        const args = a[3..];
        const p: []const u8 = if (args.len > 0) args[0] else "";
        if (std.mem.eql(u8, op, "LEVEL")) {
            var counts: [4]usize = undefined;
            const first = self.spot_count;
            for (0..4) |k| {
                counts[k] = @intCast(integer(args[k]));
                for (0..counts[k]) |_| {
                    self.spots[self.spot_count] = .{ .level = self.level_count + 1, .number = self.spot_count - first + 1, .kind = k };
                    self.spot_count += 1;
                }
            }
            self.levels[self.level_count] = .{ .first = first, .end = self.spot_count };
            self.level_count += 1;
            try self.out.print("LEVEL {d} spots {d} MOTO {d} COMPACT {d} LARGE {d} EV {d}\n", .{ self.level_count, self.spot_count - first, counts[0], counts[1], counts[2], counts[3] });
            try self.admit();
        } else if (std.mem.eql(u8, op, "CLOSE") or std.mem.eql(u8, op, "OPEN")) {
            const s = &self.spots[try self.findSpot(p)];
            if (std.mem.eql(u8, op, "CLOSE")) {
                if (s.closed) return self.fail("spot {s} is already closed", .{p});
                if (s.occupant) |v| return self.fail("spot {s} is occupied by {s}", .{ p, v.plate });
                s.closed = true;
            } else {
                if (!s.closed) return self.fail("spot {s} is not closed", .{p});
                s.closed = false;
            }
            try self.out.print("{s} {s} {s}\n", .{ op, p, kinds[s.kind] });
            if (std.mem.eql(u8, op, "OPEN")) try self.admit();
        } else if (std.mem.eql(u8, op, "RATE")) {
            const k = index(&types, p) orelse return self.fail("unknown type {s}", .{p});
            const r = integer(args[1]);
            const c = integer(args[2]);
            if (c < r) return self.fail("cap below rate for {s}", .{p});
            self.rates[k] = r;
            self.caps[k] = c;
            try self.out.print("RATE {s} {d} {d}\n", .{ p, r, c });
        } else if (std.mem.eql(u8, op, "FEE")) {
            const names = [_][]const u8{ "NIGHT", "LOST", "KWH" };
            const k = index(&names, p) orelse return self.fail("unknown fee {s}", .{p});
            self.amounts[k] = integer(args[1]);
            try self.out.print("FEE {s} {d}\n", .{ p, self.amounts[k] });
        } else if (std.mem.eql(u8, op, "ENTER")) {
            const k = index(&types, args[1]) orelse return self.fail("unknown type {s}", .{args[1]});
            if (self.vehicles.get(p)) |v| return self.fail("{s} is already parked at {s}", .{ p, try self.location(v) });
            if (self.waiting(p) != null) return self.fail("{s} is already waiting", .{p});
            if (self.assign(k)) |place| {
                const v = try self.park(p, k, place);
                try self.out.print("ENTER {s} {s} {s}\n", .{ p, types[k], try self.location(v) });
            } else if (self.queue.items.len < 3) {
                try self.queue.append(self.gpa, .{ .plate = p, .kind = k, .joined = self.now });
                try self.out.print("WAIT {s} {s} {d}\n", .{ p, types[k], self.queue.items.len });
            } else {
                self.refuse(k, self.now);
                try self.out.print("FULL {s} {s}\n", .{ p, types[k] });
            }
        } else if (std.mem.eql(u8, op, "LEAVE")) {
            const i = self.waiting(p) orelse return self.fail("{s} is not waiting", .{p});
            const w = self.queue.orderedRemove(i);
            try self.out.print("LEAVE {s} {s}\n", .{ p, types[w.kind] });
        } else if (std.mem.eql(u8, op, "EXIT") or std.mem.eql(u8, op, "PAY") or std.mem.eql(u8, op, "QUOTE") or std.mem.eql(u8, op, "CHARGE") or std.mem.eql(u8, op, "VALIDATE")) {
            const v = try self.parked(p);
            if (std.mem.eql(u8, op, "EXIT")) {
                const lost = args.len > 1;
                if (lost and v.payment != null) return self.fail("{s} has already paid", .{p});
                const f = self.charges(v, lost);
                try self.feeLine(op, v, f);
                try self.records.append(self.gpa, .{ .plate = p, .location = try self.location(v), .kind = v.kind, .entry = v.entry, .exit = self.now, .fees = f, .lost = lost });
                self.stats.exits[v.kind] += 1;
                self.stats.stays[v.kind] += self.now - v.entry;
                self.daily[@intCast(date(self.now))].exits[v.kind] += 1;
                self.daily[@intCast(date(self.now))].revenue[v.kind] += f[4];
                for (v.start..v.start + v.width()) |i| self.spots[i].occupant = null;
                _ = self.vehicles.swapRemove(p);
                try self.admit();
            } else if (std.mem.eql(u8, op, "QUOTE")) {
                try self.feeLine(op, v, self.charges(v, false));
            } else if (std.mem.eql(u8, op, "PAY")) {
                if (v.payment != null) return self.fail("{s} has already paid", .{p});
                const f = self.charges(v, false);
                v.payment = .{ self.now, f[0], f[1] };
                try self.out.print("PAY {s} parking {d} night {d} charge {d} total {d}\n", .{ p, f[0], f[1], f[3], f[4] });
            } else if (std.mem.eql(u8, op, "CHARGE")) {
                if (v.kind != 2) return self.fail("{s} is not an electric car", .{p});
                if (self.spots[v.start].kind != 3) return self.fail("{s} is not at a charger", .{p});
                if (v.payment != null) return self.fail("{s} has already paid", .{p});
                const kwh = integer(args[1]);
                if (v.kwh + kwh > 100) return self.fail("charge limit exceeded for {s}", .{p});
                const cost = kwh * self.amounts[2];
                v.kwh += kwh;
                v.charge += cost;
                try self.out.print("CHARGE {s} kwh {d} cost {d} stay_kwh {d} stay_cost {d}\n", .{ p, kwh, cost, v.kwh, v.charge });
            } else {
                if (v.payment != null) return self.fail("{s} has already paid", .{p});
                const n = integer(args[1]);
                if (v.validation + n > 180) return self.fail("validation limit exceeded for {s}", .{p});
                v.validation += n;
                try self.out.print("VALIDATE {s} {d} total {d}\n", .{ p, n, v.validation });
            }
        } else if (std.mem.eql(u8, op, "PASS")) {
            const last = (if (self.pass(p)) self.passes.get(p).? else date(self.now) - 1) + integer(args[1]);
            try self.passes.put(self.gpa, p, last);
            try self.out.print("PASS {s} until {d}\n", .{ p, last });
        } else if (std.mem.eql(u8, op, "UNPASS")) {
            if (!self.pass(p)) return self.fail("{s} has no pass", .{p});
            _ = self.passes.remove(p);
            try self.out.print("UNPASS {s}\n", .{p});
        } else if (std.mem.eql(u8, op, "MOVE")) {
            const v = try self.parked(p);
            if (v.kind == 4) return self.fail("bus {s} cannot be moved", .{p});
            const dest = try self.findSpot(args[1]);
            const s = self.spots[dest];
            if (dest == v.start) return self.fail("{s} is already at {s}", .{ p, args[1] });
            if (s.closed) return self.fail("spot {s} is closed", .{args[1]});
            if (s.occupant) |other| return self.fail("spot {s} is occupied by {s}", .{ args[1], other.plate });
            if (std.mem.findScalar(usize, preferences[v.kind], s.kind) == null) return self.fail("{s} cannot use {s} spot {s}", .{ types[v.kind], kinds[s.kind], args[1] });
            try self.move(v, dest);
            try self.admit();
        } else if (std.mem.eql(u8, op, "REBALANCE")) {
            var moved: usize = 0;
            for (try self.ordered()) |v| {
                if (v.kind == 4) continue;
                if (self.assign(v.kind)) |place| {
                    const pref = preferences[v.kind];
                    if (std.mem.findScalar(usize, pref, self.spots[place].kind).? < std.mem.findScalar(usize, pref, self.spots[v.start].kind).?) {
                        try self.move(v, place);
                        moved += 1;
                    }
                }
            }
            try self.out.print("REBALANCE {d}\n", .{moved});
            try self.admit();
        } else if (std.mem.eql(u8, op, "WHERE")) {
            if (self.vehicles.get(p)) |v| {
                try self.out.print("WHERE {s} {s} {s} {s} stay {s}", .{ p, try self.location(v), types[v.kind], try self.time(v.entry), try self.duration(self.now - v.entry) });
                try self.annotation(v);
                try self.out.writeByte('\n');
            } else if (self.waiting(p)) |i| {
                try self.out.print("WHERE {s} waiting {d}\n", .{ p, i + 1 });
            } else {
                var last: ?i64 = null;
                var history = std.mem.reverseIterator(self.records.items);
                while (history.next()) |r| {
                    if (std.mem.eql(u8, r.plate, p)) {
                        last = r.exit;
                        break;
                    }
                }
                if (last) |t| {
                    try self.out.print("WHERE {s} gone {s}\n", .{ p, try self.time(t) });
                } else return self.fail("unknown plate {s}", .{p});
            }
        } else if (std.mem.eql(u8, op, "LIST")) {
            const l: usize = if (args.len == 0) 0 else @intCast(integer(p));
            if (l > self.level_count) return self.fail("unknown level {d}", .{l});
            const vs = try self.ordered();
            var count: usize = 0;
            for (vs) |v| {
                if (l == 0 or self.spots[v.start].level == l) count += 1;
            }
            try self.out.print("LIST {d}\n", .{count});
            for (vs) |v| {
                if (l != 0 and self.spots[v.start].level != l) continue;
                try self.out.print("{s} {s} {s} {s}", .{ try self.location(v), v.plate, types[v.kind], try self.time(v.entry) });
                try self.annotation(v);
                try self.out.writeByte('\n');
            }
        } else if (std.mem.eql(u8, op, "MAP")) {
            try self.out.print("MAP {d}\n", .{self.level_count});
            for (self.levels[0..self.level_count], 0..) |l, level| {
                try self.out.print("L{d} ", .{level + 1});
                for (l.first..l.end) |i| {
                    if (i > l.first and (i - l.first) % 10 == 0) try self.out.writeByte(' ');
                    const s = self.spots[i];
                    try self.out.writeByte(if (s.closed) '#' else if (s.occupant != null) "MCLE"[s.kind] else "mcle"[s.kind]);
                }
                try self.out.writeByte('\n');
            }
        } else if (std.mem.eql(u8, op, "OCCUPANCY")) {
            var all_used: [4]i64 = @splat(0);
            var all_available: [4]i64 = @splat(0);
            var all_closed: i64 = 0;
            try self.out.print("OCCUPANCY vehicles {d} waiting {d}\n", .{ self.vehicles.count(), self.queue.items.len });
            for (self.levels[0..self.level_count], 0..) |l, level| {
                var used: [4]i64 = @splat(0);
                var available: [4]i64 = @splat(0);
                var closed: i64 = 0;
                for (self.spots[l.first..l.end]) |s| {
                    if (s.closed) closed += 1 else available[s.kind] += 1;
                    if (s.occupant != null) used[s.kind] += 1;
                }
                try self.out.print("L{d}", .{level + 1});
                for (0..4) |k| {
                    try self.out.print(" {s} {d}/{d}", .{ kinds[k], used[k], available[k] });
                    all_used[k] += used[k];
                    all_available[k] += available[k];
                }
                try self.out.print(" closed {d}\n", .{closed});
                all_closed += closed;
            }
            var us: i64 = 0;
            var av: i64 = 0;
            try self.out.writeAll("TOTAL");
            for (0..4) |k| {
                us += all_used[k];
                av += all_available[k];
                try self.out.print(" {s} {d}/{d}", .{ kinds[k], all_used[k], all_available[k] });
            }
            try self.out.print(" closed {d} rate {s}%\n", .{ all_closed, try self.decimal(if (av == 0) 0 else @divTrunc(us * 1000, av)) });
        } else if (std.mem.eql(u8, op, "SIGN")) {
            var counts: [5]usize = @splat(0);
            for (0..4) |k| {
                for (0..self.spot_count) |i| {
                    if (self.free(i) and std.mem.findScalar(usize, preferences[k], self.spots[i].kind) != null) counts[k] += 1;
                }
            }
            for (self.levels[0..self.level_count]) |l| {
                var run: usize = 0;
                for (l.first..l.end) |i| {
                    if (self.free(i) and self.spots[i].kind == 2)
                        run += 1
                    else {
                        counts[4] += run / 3;
                        run = 0;
                    }
                }
                counts[4] += run / 3;
            }
            try self.out.writeAll("SIGN");
            for (0..5) |k| {
                try self.out.print(" {s} ", .{types[k]});
                if (counts[k] == 0) try self.out.writeAll("FULL") else try self.out.print("{d}", .{counts[k]});
            }
            try self.out.writeByte('\n');
        } else if (std.mem.eql(u8, op, "RATES")) {
            try self.out.writeAll("RATES\n");
            for (0..5) |k| try self.out.print("{s} {d} {d}\n", .{ types[k], self.rates[k], self.caps[k] });
            try self.out.print("NIGHT {d} LOST {d} KWH {d}\n", .{ self.amounts[0], self.amounts[1], self.amounts[2] });
        } else if (std.mem.eql(u8, op, "PASSES")) {
            var ps: std.ArrayList([]const u8) = .empty;
            var it = self.passes.iterator();
            while (it.next()) |entry| {
                if (self.pass(entry.key_ptr.*)) try ps.append(self.gpa, entry.key_ptr.*);
            }
            std.mem.sort([]const u8, ps.items, {}, plateLess);
            try self.out.print("PASSES {d}\n", .{ps.items.len});
            for (ps.items) |plate| try self.out.print("{s} until {d}{s}\n", .{ plate, self.passes.get(plate).?, if (self.vehicles.get(plate) != null) " IN" else "" });
        } else if (std.mem.eql(u8, op, "OVERSTAY")) {
            const hours = integer(p);
            var vs: std.ArrayList(*Vehicle) = .empty;
            for (self.vehicles.values()) |v| {
                if (self.now - v.entry >= hours * 60) try vs.append(self.gpa, v);
            }
            std.mem.sort(*Vehicle, vs.items, {}, entryLess);
            try self.out.print("OVERSTAY {d} {d}\n", .{ hours, vs.items.len });
            for (vs.items) |v| try self.out.print("{s} {s} {s} {s} stay {s}\n", .{ try self.location(v), v.plate, types[v.kind], try self.time(v.entry), try self.duration(self.now - v.entry) });
        } else if (std.mem.eql(u8, op, "HISTORY")) {
            var count: usize = 0;
            var paid: i64 = 0;
            for (self.records.items) |r| {
                if (std.mem.eql(u8, r.plate, p)) {
                    count += 1;
                    paid += r.fees[4];
                }
            }
            if (count == 0) return self.fail("no history for {s}", .{p});
            try self.out.print("HISTORY {s} visits {d} paid {d}\n", .{ p, count, paid });
            for (self.records.items) |r| {
                if (std.mem.eql(u8, r.plate, p)) try self.out.print("{s} {s} {s} {s} {d}{s}\n", .{ try self.time(r.entry), try self.time(r.exit), r.location, types[r.kind], r.fees[4], if (r.lost) " LOST" else "" });
            }
        } else if (std.mem.eql(u8, op, "REVENUE")) {
            var totals: [6][6]i64 = @splat(@splat(0));
            for (self.records.items) |r| {
                for ([_]usize{ r.kind, 5 }) |k| {
                    totals[k][0] += 1;
                    for (0..5) |j| totals[k][j + 1] += r.fees[j];
                }
            }
            try self.out.writeAll("REVENUE\n");
            for (totals, 0..) |f, k| try self.out.print("{s} exits {d} parking {d} night {d} lost {d} charge {d} total {d}\n", .{ if (k == 5) "TOTAL" else types[k], f[0], f[1], f[2], f[3], f[4], f[5] });
        } else if (std.mem.eql(u8, op, "DAILY")) {
            const d: usize = @intCast(integer(p));
            const s = self.daily[d];
            for (0..6) |row| {
                const k: ?usize = if (row == 0) null else row - 1;
                if (row == 0) try self.out.print("DAILY {d}", .{d}) else try self.out.writeAll(types[k.?]);
                try self.out.print(" entries {d} exits {d} refused {d} revenue {d}\n", .{ statTotal(s.entries, k), statTotal(s.exits, k), statTotal(s.refused, k), statTotal(s.revenue, k) });
            }
        } else if (std.mem.eql(u8, op, "STATS")) {
            try self.out.print("STATS parked {d} peak {d} at {s}\n", .{ self.vehicles.count(), self.peak, if (self.peak_time) |t| try self.time(t) else "-" });
            for (0..6) |row| {
                const k: ?usize = if (row == 5) null else row;
                const ex = statTotal(self.stats.exits, k);
                try self.out.print("{s} entries {d} exits {d} refused {d} avg_stay {s}\n", .{ if (row == 5) "ALL" else types[row], statTotal(self.stats.entries, k), ex, statTotal(self.stats.refused, k), try self.decimal(if (ex == 0) 0 else @divTrunc(statTotal(self.stats.stays, k) * 10, ex)) });
            }
        }
    }
};
fn locationLess(_: void, a: *Vehicle, b: *Vehicle) bool {
    return a.start < b.start;
}
fn entryLess(_: void, a: *Vehicle, b: *Vehicle) bool {
    return a.entry < b.entry or (a.entry == b.entry and locationLess({}, a, b));
}
fn plateLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}
fn statTotal(values: [5]i64, k: ?usize) i64 {
    if (k) |i| return values[i];
    var sum: i64 = 0;
    for (values) |v| sum += v;
    return sum;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var ib: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var ob: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    const garage = try gpa.create(Garage);
    garage.* = .{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var tokens: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |part| try tokens.append(gpa, part);
        const a = tokens.items;
        garage.now = (integer(a[0]) - 1) * 1440 + integer(a[1][0..2]) * 60 + integer(a[1][3..5]);
        try garage.giveup();
        var draft: std.Io.Writer.Allocating = .init(gpa);
        garage.out = &draft.writer;
        garage.execute(a) catch |err| {
            garage.out = &output.interface;
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{garage.error_message});
                continue;
            }
            return err;
        };
        garage.out = &output.interface;
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
