const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const types = [_][]const u8{ "SINGLE", "DOUBLE", "SUITE" };
const weekdays = [_][]const u8{ "SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI" };
fn integer(s: []const u8) i64 { return std.fmt.parseInt(i64, s, 10) catch unreachable; }
fn amount(s: []const u8) i64 {
    const dot = std.mem.findScalar(u8, s, '.').?;
    return integer(s[0..dot]) * 100 + integer(s[dot + 1..]);
}
fn leap(y: i64) bool { return @mod(y, 4) == 0 and (@mod(y, 100) != 0 or @mod(y, 400) == 0); }
fn monthDays(y: i64, m: i64) i64 {
    const days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return if (m == 2 and leap(y)) 29 else days[@intCast(m - 1)];
}
fn dayNumber(y: i64, m: i64, d: i64) i64 {
    var total = d - 1;
    var year: i64 = 2000;
    while (year < y) : (year += 1) total += if (leap(year)) @as(i64, 366) else 365;
    var month: i64 = 1;
    while (month < m) : (month += 1) total += monthDays(y, month);
    return total;
}
const Status = enum { booked, inhouse, checkedout, cancelled, noshow };
const Room = struct {
    number: i64,
    kind: []const u8,
    rate: i64,
    clean: bool = true,
    blocks: std.AutoHashMapUnmanaged(i64, void) = .empty,
    occupied: std.AutoHashMapUnmanaged(i64, *Reservation) = .empty,
};
const Season = struct {
    first: i64,
    last: i64,
    percent: i64,
};
const Night = struct {
    day: i64,
    room: *Room,
    rate: i64,
};
const Extra = struct {
    name: []const u8,
    amount: i64,
};
const Reservation = struct {
    id: []const u8,
    guest: []const u8,
    room: *Room,
    first: i64,
    last: i64,
    status: Status = .booked,
    nights: std.ArrayList(Night) = .empty,
    extras: std.ArrayList(Extra) = .empty,
    deposit: i64 = 0,
    paid: i64 = 0,
    fee: i64 = 0,
    posting: ?i64 = null,
    penalty: ?Night = null,
    final_bill: ?[6]i64 = null,
    fn lodging(r: *Reservation) i64 {
        var total: i64 = 0;
        for (r.nights.items) |n| total += n.rate;
        return total;
    }
    fn extraTotal(r: *Reservation) i64 {
        var total: i64 = 0;
        for (r.extras.items) |e| total += e.amount;
        return total;
    }
};
const Waiting = struct {
    id: []const u8,
    guest: []const u8,
    kind: []const u8,
    first: i64,
    last: i64,
};
const Span = struct {
    first: i64,
    last: i64,
};
fn free(room: *Room, day: i64, except: ?*Reservation) bool {
    const occupant = room.occupied.get(day);
    return !room.blocks.contains(day) and (occupant == null or occupant == except);
}
const Hotel = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    today: i64 = dayNumber(2026, 1, 1),
    rooms: std.ArrayList(*Room) = .empty,
    reservations: std.StringArrayHashMapUnmanaged(*Reservation) = .empty,
    seasons: std.ArrayList(Season) = .empty,
    queue: std.ArrayList(Waiting) = .empty,
    used: std.StringHashMapUnmanaged(void) = .empty,
    fn fail(self: *Hotel, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn money(self: *Hotel, c: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(c);
        return std.fmt.allocPrint(self.gpa, "{d}.{d:0>2}", .{ u / 100, u % 100 });
    }
    fn date(self: *Hotel, s: []const u8) Error!i64 {
        const y = integer(s[0..4]);
        const m = integer(s[5..7]);
        const d = integer(s[8..10]);
        if (y < 2000 or y > 2099 or m < 1 or m > 12 or d < 1 or d > monthDays(y, m)) return self.fail("invalid date {s}", .{s});
        return dayNumber(y, m, d);
    }
    fn dateText(self: *Hotel, day: i64) Allocator.Error![]const u8 {
        var n = day;
        var y: i64 = 2000;
        var m: i64 = 1;
        while (n >= (if (leap(y)) @as(i64, 366) else 365)) {
            n -= if (leap(y)) @as(i64, 366) else 365;
            y += 1;
        }
        while (n >= monthDays(y, m)) {
            n -= monthDays(y, m);
            m += 1;
        }
        return std.fmt.allocPrint(self.gpa, "{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u64, @intCast(y)), @as(u64, @intCast(m)), @as(u64, @intCast(n + 1)) });
    }
    fn dated(self: *Hotel, day: i64) Allocator.Error![]const u8 { return std.fmt.allocPrint(self.gpa, "{s} {s}", .{ try self.dateText(day), weekdays[@intCast(@mod(day, 7))] }); }
    fn findRoom(self: *Hotel, number: i64) ?*Room {
        for (self.rooms.items) |r| {
            if (r.number == number) return r;
        }
        return null;
    }
    fn room(self: *Hotel, token: []const u8) Error!*Room { return self.findRoom(integer(token)) orelse return self.fail("unknown room {s}", .{token}); }
    fn reservation(self: *Hotel, id: []const u8) Error!*Reservation {
        return self.reservations.get(id) orelse return self.fail("unknown reservation {s}", .{id});
    }
    fn typeCheck(self: *Hotel, kind: []const u8) Error!void {
        for (types) |t| {
            if (std.mem.eql(u8, kind, t)) return;
        }
        return self.fail("invalid type {s}", .{kind});
    }
    fn idCheck(self: *Hotel, id: []const u8) Error!void {
        if (self.used.contains(id)) return self.fail("duplicate reservation {s}", .{id});
    }
    fn statusCheck(self: *Hotel, r: *Reservation, status: Status) Error!void {
        if (r.status != status) return self.fail("invalid status {s} {s}", .{ r.id, @tagName(r.status) });
    }
    fn range(self: *Hotel, a: []const u8, b: []const u8, stay: bool, past: bool, limit: bool) Error!Span {
        const first = try self.date(a);
        const last = try self.date(b);
        if ((stay or past) and first < self.today) return self.fail("past date {s}", .{a});
        if (if (stay) last <= first else last < first) return self.fail("invalid range {s} {s}", .{ a, b });
        const count = last - first + (if (stay) @as(i64, 0) else 1);
        if (limit and count > (if (stay) @as(i64, 30) else 31)) return self.fail("too long {d}", .{count});
        return .{ .first = first, .last = last };
    }
    fn sorted(self: *Hotel, rs: []const *Reservation, departure: bool, ids: bool) Error![]*Reservation {
        const result = try self.gpa.dupe(*Reservation, rs);
        const Order = struct {
            departure: bool,
            ids: bool,
            fn less(order: @This(), left: *Reservation, right: *Reservation) bool {
                const ad = if (order.departure) left.last else left.first;
                const bd = if (order.departure) right.last else right.first;
                if (!order.ids and ad != bd) return ad < bd;
                return std.mem.order(u8, left.id, right.id) == .lt;
            }
        };
        std.mem.sort(*Reservation, result, Order{ .departure = departure, .ids = ids }, Order.less);
        return result;
    }
    fn rate(self: *Hotel, r: *Room, day: i64) i64 {
        var p: i64 = 100;
        for (self.seasons.items) |s| {
            if (s.first <= day and day <= s.last) p = s.percent;
        }
        return @divTrunc(r.rate * p, 100);
    }
    fn price(self: *Hotel, r: *Room, first: i64, last: i64) Error!std.ArrayList(Night) {
        var result: std.ArrayList(Night) = .empty;
        var d = first;
        while (d < last) : (d += 1) try result.append(self.gpa, .{ .day = d, .room = r, .rate = self.rate(r, d) });
        return result;
    }
    fn unavailable(r: *Room, first: i64, last: i64, except: ?*Reservation) ?i64 {
        var d = first;
        while (d < last) : (d += 1) {
            if (!free(r, d, except)) return d;
        }
        return null;
    }
    fn search(self: *Hotel, kind: []const u8, first: i64, last: i64, except: ?*Reservation) ?*Room {
        for (self.rooms.items) |r| {
            if (std.mem.eql(u8, r.kind, kind) and unavailable(r, first, last, except) == null) return r;
        }
        return null;
    }
    fn inhouse(self: *Hotel, r: *Room) ?*Reservation {
        for (self.reservations.values()) |guest| {
            if (guest.status == .inhouse and guest.room == r) return guest;
        }
        return null;
    }
    fn release(r: *Reservation) void {
        for (r.nights.items) |n| {
            if (n.room.occupied.get(n.day) == r) _ = n.room.occupied.remove(n.day);
        }
    }
    fn occupy(self: *Hotel, r: *Reservation) Error!void {
        for (r.nights.items) |n| try n.room.occupied.put(self.gpa, n.day, r);
    }
    fn create(self: *Hotel, id: []const u8, guest: []const u8, room_ptr: *Room, first: i64, last: i64, indent: []const u8) Error!void {
        const r = try self.gpa.create(Reservation);
        r.* = .{ .id = id, .guest = guest, .room = room_ptr, .first = first, .last = last, .nights = try self.price(room_ptr, first, last) };
        try self.reservations.put(self.gpa, id, r);
        try self.used.put(self.gpa, id, {});
        try self.occupy(r);
        try self.out.print("{s}BOOK {s} {s} room {d} {s} {s} -> {s} nights {d} total {s}\n", .{ indent, id, guest, room_ptr.number, room_ptr.kind, try self.dateText(first), try self.dateText(last), last - first, try self.money(r.lodging()) });
    }
    fn paid(self: *Hotel, guest: []const u8) i64 {
        var total: i64 = 0;
        for (self.reservations.values()) |r| {
            if (std.mem.eql(u8, r.guest, guest)) total += r.paid;
        }
        return total;
    }
    fn tier(self: *Hotel, guest: []const u8) []const u8 {
        const points = @divTrunc(self.paid(guest), 100);
        return if (points >= 2000) "GOLD" else if (points >= 500) "SILVER" else "BRONZE";
    }
    fn bill(self: *Hotel, r: *Reservation) [6]i64 {
        const level = self.tier(r.guest);
        const lodging = r.lodging();
        const discount = @divTrunc(lodging * @as(i64, if (std.mem.eql(u8, level, "GOLD")) 10 else if (std.mem.eql(u8, level, "SILVER")) 5 else 0), 100);
        const penalty = if (r.penalty) |n| n.rate else 0;
        const extras = r.extraTotal();
        const subtotal = lodging - discount + penalty + extras;
        const tax = @divTrunc(subtotal, 10);
        return .{ lodging, discount, penalty, extras, tax, subtotal + tax };
    }
    fn deposit(self: *Hotel, r: *Reservation, total: i64) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.gpa, "deposit {s} {s} {s}", .{ try self.money(r.deposit), if (total >= r.deposit) "due" else "refund", try self.money(if (total >= r.deposit) total - r.deposit else r.deposit - total) });
    }
    fn checkout(self: *Hotel, r: *Reservation, day: i64, indent: []const u8) Error!void {
        if (day < r.last) {
            for (r.nights.items) |n| {
                if (n.day == day) {
                    r.penalty = n;
                    break;
                }
            }
            release(r);
            var count: usize = 0;
            for (r.nights.items) |n| {
                if (n.day < day) {
                    r.nights.items[count] = n;
                    count += 1;
                }
            }
            r.nights.shrinkRetainingCapacity(count);
            r.last = day;
            try self.occupy(r);
        }
        const b = self.bill(r);
        r.final_bill = b;
        r.paid = b[5];
        r.status = .checkedout;
        r.posting = day;
        r.room.clean = false;
        try self.out.print("{s}CHECKOUT {s} nights {d} lodging {s} discount {s} penalty {s} extras {s} tax {s} total {s} {s}\n", .{ indent, r.id, r.nights.items.len, try self.money(b[0]), try self.money(b[1]), try self.money(b[2]), try self.money(b[3]), try self.money(b[4]), try self.money(b[5]), try self.deposit(r, b[5]) });
    }
    fn processQueue(self: *Hotel) Error!void {
        var i: usize = 0;
        while (i < self.queue.items.len) {
            const w = self.queue.items[i];
            if (w.first < self.today) {
                _ = self.queue.orderedRemove(i);
                try self.out.print("  WAITLIST {s} expired\n", .{w.id});
            } else if (self.search(w.kind, w.first, w.last, null)) |r| {
                _ = self.queue.orderedRemove(i);
                try self.create(w.id, w.guest, r, w.first, w.last, "  ");
            } else i += 1;
        }
    }
    fn metrics(self: *Hotel, day: i64) [3]i64 {
        var result: [3]i64 = @splat(0);
        for (self.rooms.items) |r| {
            if (!r.blocks.contains(day)) result[0] += 1;
            if (r.occupied.get(day)) |guest| {
                result[1] += 1;
                for (guest.nights.items) |n| {
                    if (n.day == day and n.room == r) {
                        result[2] += n.rate;
                        break;
                    }
                }
            }
        }
        return result;
    }
    fn metricText(self: *Hotel, s: i64, k: i64, v: i64) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.gpa, "sold {d}/{d} rate {s} revenue {s} adr {s} revpar {s}", .{ k, s, if (s == 0) "n/a" else try std.fmt.allocPrint(self.gpa, "{d}%", .{@divTrunc(k * 100, s)}), try self.money(v), if (k == 0) "n/a" else try self.money(@divTrunc(v, k)), if (s == 0) "n/a" else try self.money(@divTrunc(v, s)) });
    }
    fn occupancy(self: *Hotel, kind: ?[]const u8, day: i64) Allocator.Error![]const u8 {
        var count: i64 = 0;
        var blocked: i64 = 0;
        var occupied: i64 = 0;
        for (self.rooms.items) |r| {
            if (kind != null and !std.mem.eql(u8, r.kind, kind.?)) continue;
            count += 1;
            if (r.blocks.contains(day)) blocked += 1;
            if (r.occupied.contains(day)) occupied += 1;
        }
        const available = count - blocked;
        return std.fmt.allocPrint(self.gpa, "rooms {d} blocked {d} occupied {d} rate {s}", .{ count, blocked, occupied, if (available == 0) "n/a" else try std.fmt.allocPrint(self.gpa, "{d}%", .{@divTrunc(occupied * 100, available)}) });
    }
    fn execute(self: *Hotel, a: []const []const u8) Error!void {
        const op = a[0];
        const id: []const u8 = if (a.len > 1) a[1] else "";
        if (std.mem.eql(u8, op, "ROOM")) {
            const number = integer(id);
            if (self.findRoom(number) != null) return self.fail("duplicate room {s}", .{id});
            try self.typeCheck(a[2]);
            const r = try self.gpa.create(Room);
            r.* = .{ .number = number, .kind = a[2], .rate = amount(a[3]) };
            try self.rooms.append(self.gpa, r);
            std.mem.sort(*Room, self.rooms.items, {}, struct {
                fn less(_: void, left: *Room, right: *Room) bool { return left.number < right.number; }
            }.less);
            try self.out.print("ROOM {d} {s} {s}\n", .{ number, r.kind, try self.money(r.rate) });
        } else if (std.mem.eql(u8, op, "RATE")) {
            const r = try self.room(id);
            const old = r.rate;
            r.rate = amount(a[2]);
            try self.out.print("RATE {s} {s} -> {s}\n", .{ id, try self.money(old), try self.money(r.rate) });
        } else if (std.mem.eql(u8, op, "SEASON")) {
            const span = try self.range(id, a[2], false, false, false);
            try self.seasons.append(self.gpa, .{ .first = span.first, .last = span.last, .percent = integer(a[3]) });
            try self.out.print("SEASON {d} {s} -> {s} {s}%\n", .{ self.seasons.items.len, id, a[2], a[3] });
        } else if (std.mem.eql(u8, op, "BLOCK") or std.mem.eql(u8, op, "UNBLOCK")) {
            const r = try self.room(id);
            const span = try self.range(a[2], a[3], false, true, true);
            var d = span.first;
            if (std.mem.eql(u8, op, "BLOCK")) {
                while (d <= span.last) : (d += 1) {
                    if (r.occupied.contains(d)) return self.fail("room unavailable {s} {s}", .{ id, try self.dateText(d) });
                }
            }
            var changed: usize = 0;
            d = span.first;
            while (d <= span.last) : (d += 1) {
                if (std.mem.eql(u8, op, "BLOCK")) {
                    if (!r.blocks.contains(d)) {
                        changed += 1;
                        try r.blocks.put(self.gpa, d, {});
                    }
                } else if (r.blocks.remove(d)) changed += 1;
            }
            try self.out.print("{s} {s} {s} -> {s} {s} {d}\n", .{ op, id, a[2], a[3], if (std.mem.eql(u8, op, "BLOCK")) "added" else "removed", changed });
        } else if (std.mem.eql(u8, op, "CLEAN")) {
            const r = try self.room(id);
            if (r.clean) return self.fail("already clean {s}", .{id});
            r.clean = true;
            try self.out.print("CLEAN {s}\n", .{id});
        } else if (std.mem.eql(u8, op, "TODAY")) {
            const day = try self.date(id);
            if (day < self.today) return self.fail("past date {s}", .{id});
            try self.out.print("TODAY {s}\n", .{try self.dated(day)});
            var departures: std.ArrayList(*Reservation) = .empty;
            var arrivals: std.ArrayList(*Reservation) = .empty;
            for (self.reservations.values()) |r| {
                if (r.status == .inhouse and r.last < day) try departures.append(self.gpa, r);
                if (r.status == .booked and r.first < day) try arrivals.append(self.gpa, r);
            }
            for (try self.sorted(departures.items, true, false)) |r| try self.checkout(r, r.last, "  ");
            for (try self.sorted(arrivals.items, false, false)) |r| {
                r.fee = r.nights.items[0].rate;
                r.paid = r.fee;
                r.status = .noshow;
                r.posting = r.first;
                release(r);
                try self.out.print("  NOSHOW {s} {s} fee {s} {s}\n", .{ r.id, r.guest, try self.money(r.fee), try self.deposit(r, r.fee) });
            }
            self.today = day;
        } else if (std.mem.eql(u8, op, "BOOK") or std.mem.eql(u8, op, "BOOKROOM") or std.mem.eql(u8, op, "WAITLIST")) {
            try self.idCheck(id);
            var selected: ?*Room = null;
            if (std.mem.eql(u8, op, "BOOKROOM")) {
                selected = try self.room(a[3]);
            } else try self.typeCheck(a[3]);
            const span = try self.range(a[4], a[5], true, false, true);
            if (std.mem.eql(u8, op, "BOOKROOM")) {
                if (unavailable(selected.?, span.first, span.last, null)) |d| return self.fail("room unavailable {d} {s}", .{ selected.?.number, try self.dateText(d) });
            } else selected = self.search(a[3], span.first, span.last, null);
            if (selected) |r| {
                try self.create(id, a[2], r, span.first, span.last, "");
            } else if (std.mem.eql(u8, op, "WAITLIST")) {
                try self.queue.append(self.gpa, .{ .id = id, .guest = a[2], .kind = a[3], .first = span.first, .last = span.last });
                try self.used.put(self.gpa, id, {});
                try self.out.print("WAITLIST {s} queued position {d}\n", .{ id, self.queue.items.len });
            } else return self.fail("no availability {s} {s} {s}", .{ a[3], a[4], a[5] });
        } else if (std.mem.eql(u8, op, "CANCEL")) {
            for (self.queue.items, 0..) |w, i| {
                if (std.mem.eql(u8, w.id, id)) {
                    _ = self.queue.orderedRemove(i);
                    try self.out.print("CANCEL {s} waitlist removed\n", .{id});
                    return;
                }
            }
            const r = try self.reservation(id);
            try self.statusCheck(r, .booked);
            const days = r.first - self.today;
            r.fee = if (days >= 7) 0 else if (days >= 1) @divTrunc(r.nights.items[0].rate, 2) else r.nights.items[0].rate;
            r.paid = r.fee;
            r.status = .cancelled;
            r.posting = self.today;
            release(r);
            try self.out.print("CANCEL {s} days {d} fee {s} {s}\n", .{ id, days, try self.money(r.fee), try self.deposit(r, r.fee) });
        } else if (std.mem.eql(u8, op, "MODIFY") or std.mem.eql(u8, op, "CHECKIN") or std.mem.eql(u8, op, "MOVE") or std.mem.eql(u8, op, "EXTEND") or std.mem.eql(u8, op, "CHARGE") or std.mem.eql(u8, op, "PAY") or std.mem.eql(u8, op, "CHECKOUT") or std.mem.eql(u8, op, "INVOICE")) {
            const r = try self.reservation(id);
            if (std.mem.eql(u8, op, "MODIFY")) {
                try self.statusCheck(r, .booked);
                const span = try self.range(a[2], a[3], true, false, true);
                const old = r.room;
                const selected = (if (unavailable(r.room, span.first, span.last, r) == null) r.room else self.search(r.room.kind, span.first, span.last, r)) orelse return self.fail("no availability {s} {s} {s}", .{ r.room.kind, a[2], a[3] });
                release(r);
                r.room = selected;
                r.first = span.first;
                r.last = span.last;
                r.nights = try self.price(selected, span.first, span.last);
                try self.occupy(r);
                try self.out.print("MODIFY {s} room {d} {s} {s} -> {s} nights {d} total {s}\n", .{ id, selected.number, if (selected == old) "kept" else "reassigned", a[2], a[3], span.last - span.first, try self.money(r.lodging()) });
            } else if (std.mem.eql(u8, op, "CHECKIN")) {
                try self.statusCheck(r, .booked);
                if (r.first != self.today) return self.fail("not arrival date {s} {s}", .{ id, try self.dateText(r.first) });
                if (self.inhouse(r.room)) |guest| return self.fail("room occupied {d} {s}", .{ r.room.number, guest.id });
                if (!r.room.clean) return self.fail("room dirty {d}", .{r.room.number});
                r.status = .inhouse;
                try self.out.print("CHECKIN {s} {s} room {d} until {s}\n", .{ id, r.guest, r.room.number, try self.dateText(r.last) });
            } else if (std.mem.eql(u8, op, "MOVE")) {
                try self.statusCheck(r, .inhouse);
                const dest = try self.room(a[2]);
                if (dest == r.room) return self.fail("same room {d}", .{dest.number});
                var count: usize = 0;
                for (r.nights.items) |n| {
                    if (n.day >= self.today) count += 1;
                }
                if (count == 0) return self.fail("no remaining nights {s}", .{id});
                for (r.nights.items) |n| {
                    if (n.day >= self.today and !free(dest, n.day, r)) return self.fail("room unavailable {d} {s}", .{ dest.number, try self.dateText(n.day) });
                }
                if (self.inhouse(dest)) |guest| return self.fail("room occupied {d} {s}", .{ dest.number, guest.id });
                if (!dest.clean) return self.fail("room dirty {d}", .{dest.number});
                const old = r.room;
                for (r.nights.items) |*n| {
                    if (n.day >= self.today) {
                        _ = n.room.occupied.remove(n.day);
                        n.room = dest;
                        try dest.occupied.put(self.gpa, n.day, r);
                    }
                }
                try self.out.print("MOVE {s} {d} -> {d} nights {d}\n", .{ id, old.number, dest.number, count });
                old.clean = false;
                r.room = dest;
            } else if (std.mem.eql(u8, op, "EXTEND")) {
                try self.statusCheck(r, .inhouse);
                const last = try self.date(a[2]);
                if (last <= r.last) return self.fail("invalid range {s} {s}", .{ try self.dateText(r.last), a[2] });
                if (last - r.first > 30) return self.fail("too long {d}", .{last - r.first});
                if (unavailable(r.room, r.last, last, r)) |d| return self.fail("room unavailable {d} {s}", .{ r.room.number, try self.dateText(d) });
                const nights = try self.price(r.room, r.last, last);
                try r.nights.appendSlice(self.gpa, nights.items);
                r.last = last;
                try self.occupy(r);
                try self.out.print("EXTEND {s} until {s} nights {d} total {s}\n", .{ id, a[2], r.nights.items.len, try self.money(r.lodging()) });
            } else if (std.mem.eql(u8, op, "CHARGE")) {
                try self.statusCheck(r, .inhouse);
                const m = amount(a[2]);
                if (m == 0) return self.fail("invalid amount", .{});
                try r.extras.append(self.gpa, .{ .name = a[3], .amount = m });
                try self.out.print("CHARGE {s} {s} {s} extras {s}\n", .{ id, a[3], try self.money(m), try self.money(r.extraTotal()) });
            } else if (std.mem.eql(u8, op, "PAY")) {
                if (r.status != .booked and r.status != .inhouse) return self.fail("invalid status {s} {s}", .{ id, @tagName(r.status) });
                const m = amount(a[2]);
                if (m == 0) return self.fail("invalid amount", .{});
                r.deposit += m;
                try self.out.print("PAY {s} {s} deposit {s}\n", .{ id, try self.money(m), try self.money(r.deposit) });
            } else if (std.mem.eql(u8, op, "CHECKOUT")) {
                try self.statusCheck(r, .inhouse);
                try self.checkout(r, self.today, "");
            } else {
                try self.out.print("INVOICE {s} {s} room {d} {s} {s}\n", .{ id, r.guest, r.room.number, r.room.kind, @tagName(r.status) });
                if (r.status == .cancelled or r.status == .noshow) {
                    try self.out.print("  {s} fee {s}\n  total {s}\n  {s}\n", .{ if (r.status == .cancelled) "cancellation" else "noshow", try self.money(r.fee), try self.money(r.fee), try self.deposit(r, r.fee) });
                } else {
                    for (r.nights.items) |n| try self.out.print("  {s} room {d} {s}\n", .{ try self.dated(n.day), n.room.number, try self.money(n.rate) });
                    const b = if (r.status == .checkedout) r.final_bill.? else self.bill(r);
                    try self.out.print("  lodging {s}\n  discount {s}\n", .{ try self.money(b[0]), try self.money(b[1]) });
                    if (r.penalty) |n| try self.out.print("  penalty {s} {s}\n", .{ try self.dated(n.day), try self.money(b[2]) });
                    for (r.extras.items) |e| try self.out.print("  extra {s} {s}\n", .{ e.name, try self.money(e.amount) });
                    try self.out.print("  tax {s}\n  total {s}\n  {s}\n", .{ try self.money(b[4]), try self.money(b[5]), try self.deposit(r, b[5]) });
                }
            }
        } else if (std.mem.eql(u8, op, "AVAIL")) {
            try self.typeCheck(id);
            const span = try self.range(a[2], a[3], false, false, true);
            try self.out.print("AVAIL {s} {s} -> {s}\n", .{ id, a[2], a[3] });
            var d = span.first;
            while (d <= span.last) : (d += 1) {
                var count: usize = 0;
                for (self.rooms.items) |r| {
                    if (std.mem.eql(u8, r.kind, id) and free(r, d, null)) count += 1;
                }
                try self.out.print("  {s} free {d}", .{ try self.dated(d), count });
                for (self.rooms.items) |r| {
                    if (std.mem.eql(u8, r.kind, id) and free(r, d, null)) try self.out.print(" {d}", .{r.number});
                }
                try self.out.writeByte('\n');
            }
        } else if (std.mem.eql(u8, op, "OCCUPANCY")) {
            const d = try self.date(id);
            try self.out.print("OCCUPANCY {s} {s}\n", .{ try self.dated(d), try self.occupancy(null, d) });
            for (types) |kind| {
                var count: usize = 0;
                for (self.rooms.items) |r| {
                    if (std.mem.eql(u8, r.kind, kind)) count += 1;
                }
                if (count > 0) try self.out.print("  {s} {s}\n", .{ kind, try self.occupancy(kind, d) });
            }
        } else if (std.mem.eql(u8, op, "STATS")) {
            const span = try self.range(id, a[2], false, false, true);
            var totals: [3]i64 = @splat(0);
            var d = span.first;
            try self.out.print("STATS {s} -> {s}\n", .{ id, a[2] });
            while (d <= span.last) : (d += 1) {
                const m = self.metrics(d);
                for (0..3) |i| totals[i] += m[i];
                try self.out.print("  {s} {s}\n", .{ try self.dated(d), try self.metricText(m[0], m[1], m[2]) });
            }
            try self.out.print("  total {s}\n", .{try self.metricText(totals[0], totals[1], totals[2])});
        } else if (std.mem.eql(u8, op, "ROOMS")) {
            try self.out.print("ROOMS {s} rooms {d}\n", .{ try self.dated(self.today), self.rooms.items.len });
            for (self.rooms.items) |r| {
                const guest = self.inhouse(r);
                var next: ?*Reservation = null;
                for (self.reservations.values()) |x| {
                    if (x.status == .booked and x.room == r and (next == null or x.first < next.?.first)) next = x;
                }
                try self.out.print("  {d} {s} base {s} tonight {s} {s} {s}", .{ r.number, r.kind, try self.money(r.rate), try self.money(self.rate(r, self.today)), if (r.clean) "clean" else "dirty", if (guest) |g| try std.fmt.allocPrint(self.gpa, "occupied {s}", .{g.id}) else if (r.blocks.contains(self.today)) "blocked" else "vacant" });
                if (next) |x| try self.out.print(" next {s} {s}", .{ x.id, try self.dateText(x.first) });
                try self.out.writeByte('\n');
            }
        } else if (std.mem.eql(u8, op, "LIST")) {
            var selected: std.ArrayList(*Reservation) = .empty;
            for (self.reservations.values()) |r| {
                if (std.mem.eql(u8, @tagName(r.status), id)) try selected.append(self.gpa, r);
            }
            try self.out.print("LIST {s} {d}\n", .{ id, selected.items.len });
            for (try self.sorted(selected.items, false, false)) |r| try self.out.print("  {s} {s} room {d} {s} -> {s}\n", .{ r.id, r.guest, r.room.number, try self.dateText(r.first), try self.dateText(r.last) });
        } else if (std.mem.eql(u8, op, "QUEUE")) {
            try self.out.print("QUEUE {d}\n", .{self.queue.items.len});
            for (self.queue.items, 0..) |w, i| try self.out.print("  {d} {s} {s} {s} {s} -> {s}\n", .{ i + 1, w.id, w.guest, w.kind, try self.dateText(w.first), try self.dateText(w.last) });
        } else if (std.mem.eql(u8, op, "SCHEDULE")) {
            const d = try self.date(id);
            var arrivals: std.ArrayList(*Reservation) = .empty;
            var departures: std.ArrayList(*Reservation) = .empty;
            for (self.reservations.values()) |r| {
                if (r.first == d and r.status != .cancelled) try arrivals.append(self.gpa, r);
                if (r.last == d and (r.status == .booked or r.status == .inhouse or r.status == .checkedout)) try departures.append(self.gpa, r);
            }
            try self.out.print("SCHEDULE {s} arrivals {d} departures {d}\n", .{ try self.dated(d), arrivals.items.len, departures.items.len });
            for (try self.sorted(arrivals.items, false, true)) |r| try self.out.print("  arrival {s} {s} room {d} {s}\n", .{ r.id, r.guest, r.room.number, @tagName(r.status) });
            for (try self.sorted(departures.items, false, true)) |r| try self.out.print("  departure {s} {s} room {d} {s}\n", .{ r.id, r.guest, r.room.number, @tagName(r.status) });
        } else if (std.mem.eql(u8, op, "GUEST")) {
            var count: usize = 0;
            for (self.reservations.values()) |r| {
                if (std.mem.eql(u8, r.guest, id)) count += 1;
            }
            if (count == 0) return self.fail("unknown guest {s}", .{id});
            try self.out.print("GUEST {s}\n", .{id});
            for (self.reservations.values()) |r| {
                if (!std.mem.eql(u8, r.guest, id)) continue;
                const active = r.status == .booked or r.status == .inhouse;
                try self.out.print("  {s} room {d} {s} {s} -> {s} {s} {s} {s}\n", .{ r.id, r.room.number, r.room.kind, try self.dateText(r.first), try self.dateText(r.last), @tagName(r.status), if (active) "deposit" else "paid", try self.money(if (active) r.deposit else r.paid) });
            }
            try self.out.print("  total paid {s} points {d} tier {s}\n", .{ try self.money(self.paid(id)), @divTrunc(self.paid(id), 100), self.tier(id) });
        } else if (std.mem.eql(u8, op, "REVENUE")) {
            const span = try self.range(id, a[2], false, false, false);
            var totals: [7]i64 = @splat(0);
            var counts: [3]usize = @splat(0);
            for (self.reservations.values()) |r| {
                const posting = r.posting orelse continue;
                if (posting < span.first or posting > span.last) continue;
                if (r.status == .checkedout) {
                    counts[0] += 1;
                    for (0..5) |i| totals[i] += r.final_bill.?[i];
                } else if (r.status == .cancelled) {
                    counts[1] += 1;
                    totals[5] += r.fee;
                } else if (r.status == .noshow) {
                    counts[2] += 1;
                    totals[6] += r.fee;
                }
            }
            try self.out.print("REVENUE {s} -> {s}\n", .{ id, a[2] });
            const labels = [_][]const u8{ "lodging", "discount", "penalty", "extras", "tax", "cancellation", "noshow" };
            for (0..7) |i| try self.out.print("  {s} {s}\n", .{ labels[i], try self.money(totals[i]) });
            try self.out.print("  total {s}\n  checkouts {d} cancellations {d} noshows {d}\n", .{ try self.money(totals[0] - totals[1] + totals[2] + totals[3] + totals[4] + totals[5] + totals[6]), counts[0], counts[1], counts[2] });
        }
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var ib: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var ob: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var hotel = Hotel{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var a: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |part| try a.append(gpa, part);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        hotel.out = &draft.writer;
        hotel.execute(a.items) catch |err| {
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{hotel.error_message});
                hotel.out = &output.interface;
                try hotel.processQueue();
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
        hotel.out = &output.interface;
        try hotel.processQueue();
    }
    try output.interface.flush();
}
