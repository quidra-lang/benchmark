const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const StationName = enum { GRILL, FRY, COLD, BAR };
const Course = enum { DRINK, STARTER, MAIN, DESSERT };
const State = enum { ORDERED, QUEUED, COOKING, READY, SERVED, VOID };
const Command = enum { TABLE, STAFF, SEAT, CANCEL, MOVE, MENU, STOCK, HAPPY, ITEMS, ORDER, FIRE, TICK, SERVE, RUSH, REMAKE, VOID, STATION, COMP, TRANSFER, DISCOUNT, BILL, SPLIT, PAY, CLOSE, STATUS, KITCHEN, FLOOR, REPORT };
fn integer(s: []const u8) i64 { return std.fmt.parseInt(i64, s, 10) catch unreachable; }
fn amount(s: []const u8) i64 {
    const dot = std.mem.findScalar(u8, s, '.').?;
    return integer(s[0..dot]) * 100 + integer(s[dot + 1..]);
}
fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn rounded(value: i64, rate: i64) i64 { return @divTrunc(value * rate + 50, 100); }
const Server = struct { name: []const u8, load: usize = 0, parties: i64 = 0, sales: i64 = 0, tips: i64 = 0 };
const Table = struct { number: i64, seats: usize, check: ?*Check = null };
const Waiting = struct { name: []const u8, size: usize, since: i64 };
const MenuItem = struct { name: []const u8, station: StationName, prep: i64, price: i64, course: Course, stock: ?i64 = null, served: i64 = 0 };
const Check = struct {
    party: []const u8,
    size: usize,
    table: *Table,
    server: *Server,
    seated: i64,
    orders: std.ArrayList(*Order) = .empty,
    paid: i64 = 0,
    discount: i64 = 0,
    closed: bool = false,
    fn activeCount(c: *const Check) usize {
        var n: usize = 0;
        for (c.orders.items) |o| if (o.state != .VOID) { n += 1; };
        return n;
    }
};
const Order = struct {
    id: usize,
    check: *Check,
    seat: usize,
    item: *MenuItem,
    quantity: i64,
    station: StationName,
    prep: i64,
    price: i64,
    course: Course,
    state: State = .ORDERED,
    comp: ?[]const u8 = null,
    fired: i64 = 0,
    ready: i64 = 0,
    started: bool = false,
    fn charge(o: *const Order) i64 { return if (o.comp == null) o.price * o.quantity else 0; }
};
const Station = struct {
    up: bool = true,
    queue: std.ArrayList(*Order) = .empty,
    cooking: std.ArrayList(*Order) = .empty,
    tickets: i64 = 0,
    ticket_total: i64 = 0,
    ticket_max: i64 = 0,
    remakes: i64 = 0,
};
const Totals = struct {
    subtotal: i64 = 0, discount: i64 = 0, service: i64 = 0, tax: i64 = 0, total: i64 = 0,
    fn of(c: *const Check) Totals {
        var t: Totals = .{};
        for (c.orders.items) |o| if (o.state != .VOID) { t.subtotal += o.charge(); };
        t.discount = rounded(t.subtotal, c.discount);
        const net = t.subtotal - t.discount;
        t.service = if (c.size >= 6) rounded(net, 18) else 0;
        t.tax = rounded(net, 8);
        t.total = net + t.service + t.tax;
        return t;
    }
    fn add(t: *Totals, other: Totals) void {
        t.subtotal += other.subtotal;
        t.discount += other.discount;
        t.service += other.service;
        t.tax += other.tax;
        t.total += other.total;
    }
};
const Seats = struct {
    present: [21]bool = @splat(false),
    amounts: [21]i64 = @splat(0),
    fn of(c: *const Check) Seats {
        var result: Seats = .{};
        for (c.orders.items) |o| {
            if (o.state == .VOID) continue;
            result.present[o.seat] = true;
            result.amounts[o.seat] += o.charge();
        }
        return result;
    }
};
fn allocate(values: [21]i64, present: [21]bool, rate: i64) [21]i64 {
    var result: [21]i64 = @splat(0);
    var total: i64 = 0;
    var assigned: i64 = 0;
    for (1..21) |seat| {
        if (!present[seat]) continue;
        total += values[seat];
        result[seat] = @divTrunc(values[seat] * rate, 100);
        assigned += result[seat];
    }
    var remaining = rounded(total, rate) - assigned;
    var used: [21]bool = @splat(false);
    while (remaining > 0) : (remaining -= 1) {
        var best: usize = 0;
        for (1..21) |seat| {
            if (!present[seat] or used[seat]) continue;
            if (best == 0 or @mod(values[seat] * rate, 100) > @mod(values[best] * rate, 100)) best = seat;
        }
        result[best] += 1;
        used[best] = true;
    }
    return result;
}
fn removeOrder(list: *std.ArrayList(*Order), order: *Order) void {
    for (list.items, 0..) |o, i| {
        if (o == order) { _ = list.orderedRemove(i); return; }
    }
    unreachable;
}
const Restaurant = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    time: i64 = 0,
    tables: std.AutoArrayHashMapUnmanaged(i64, *Table) = .empty,
    servers: std.StringArrayHashMapUnmanaged(*Server) = .empty,
    menu: std.StringArrayHashMapUnmanaged(*MenuItem) = .empty,
    waiting: std.ArrayList(Waiting) = .empty,
    orders: std.ArrayList(*Order) = .empty,
    stations: [4]Station = @splat(.{}),
    happy_rate: i64 = 0,
    happy_end: i64 = 0,
    covers: i64 = 0,
    parties: i64 = 0,
    turns: i64 = 0,
    stay_total: i64 = 0,
    sales: [4]i64 = @splat(0),
    totals: Totals = .{},
    cash: i64 = 0,
    card: i64 = 0,
    tips: i64 = 0,
    comps: i64 = 0,
    comp_amount: i64 = 0,
    voids: i64 = 0,
    fn fail(self: *Restaurant, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn money(self: *Restaurant, n: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(n);
        return std.fmt.allocPrint(self.gpa, "{d}.{d:0>2}", .{ u / 100, u % 100 });
    }
    fn clock(self: *Restaurant, minutes: i64) Allocator.Error![]const u8 {
        const m: u64 = @intCast(660 + minutes);
        return std.fmt.allocPrint(self.gpa, "{d:0>2}:{d:0>2}", .{ m / 60, m % 60 });
    }
    fn stationName(self: *Restaurant, token: []const u8) Error!StationName {
        return std.meta.stringToEnum(StationName, token) orelse return self.fail("unknown station {s}", .{token});
    }
    fn courseName(self: *Restaurant, token: []const u8) Error!Course {
        return std.meta.stringToEnum(Course, token) orelse return self.fail("unknown course {s}", .{token});
    }
    fn table(self: *Restaurant, token: []const u8) Error!*Table {
        return self.tables.get(integer(token)) orelse return self.fail("unknown table {s}", .{token});
    }
    fn check(self: *Restaurant, token: []const u8) Error!*Check {
        const t = try self.table(token);
        return t.check orelse return self.fail("table {s} is free", .{token});
    }
    fn order(self: *Restaurant, token: []const u8) Error!*Order {
        const id: usize = @intCast(integer(token));
        if (id == 0 or id > self.orders.items.len) return self.fail("unknown line {s}", .{token});
        return self.orders.items[id - 1];
    }
    fn item(self: *Restaurant, token: []const u8) Error!*MenuItem {
        return self.menu.get(token) orelse return self.fail("unknown item {s}", .{token});
    }
    fn unlocked(self: *Restaurant, c: *Check) Error!void {
        if (c.paid > 0) return self.fail("check for table {d} is locked", .{c.table.number});
    }
    fn modifiable(self: *Restaurant, o: *Order) Error!void {
        if (o.state == .VOID) return self.fail("#{d} is void", .{o.id});
        if (o.check.closed) return self.fail("#{d} is on a closed check", .{o.id});
        try self.unlocked(o.check);
    }
    fn validSeat(self: *Restaurant, c: *Check, seat: usize) Error!void {
        if (seat > c.size) return self.fail("seat {d} out of range for table {d}", .{ seat, c.table.number });
    }
    fn allServed(self: *Restaurant, c: *Check) Error!void {
        var count: usize = 0;
        for (c.orders.items) |o| if (o.state != .VOID and o.state != .SERVED) { count += 1; };
        if (count > 0) return self.fail("table {d} has {d} unserved items", .{ c.table.number, count });
    }
    fn chooseTable(self: *Restaurant, size: usize) ?*Table {
        var best: ?*Table = null;
        for (self.tables.values()) |t| {
            if (t.check != null or t.seats < size) continue;
            if (best == null or t.seats < best.?.seats or (t.seats == best.?.seats and t.number < best.?.number)) best = t;
        }
        return best;
    }
    fn seatParty(self: *Restaurant, party: Waiting, t: *Table) Error!*Check {
        var server = self.servers.values()[0];
        for (self.servers.values()) |s| if (s.load < server.load) { server = s; };
        const c = try self.gpa.create(Check);
        c.* = .{ .party = party.name, .size = party.size, .table = t, .server = server, .seated = self.time };
        t.check = c;
        server.load += 1;
        server.parties += 1;
        self.covers += @intCast(party.size);
        self.parties += 1;
        return c;
    }
    fn seatWaiting(self: *Restaurant) Error!void {
        var i: usize = 0;
        while (i < self.waiting.items.len) {
            const p = self.waiting.items[i];
            const t = self.chooseTable(p.size) orelse { i += 1; continue; };
            _ = self.waiting.orderedRemove(i);
            const c = try self.seatParty(p, t);
            try self.out.print("SEATED {s} {d} table {d} server {s} waited {d}\n", .{ p.name, p.size, t.number, c.server.name, self.time - p.since });
        }
    }
    fn closeCheck(self: *Restaurant, c: *Check) Error!void {
        const t = Totals.of(c);
        self.totals.add(t);
        c.server.sales += t.total;
        c.server.load -= 1;
        self.turns += 1;
        self.stay_total += self.time - c.seated;
        for (c.orders.items) |o| if (o.state != .VOID) { self.sales[@intFromEnum(o.course)] += o.charge(); };
        c.closed = true;
        c.table.check = null;
        try self.out.print("FREE table {d} {s} stayed {d}\n", .{ c.table.number, c.party, self.time - c.seated });
        try self.seatWaiting();
    }
    fn startCooking(self: *Restaurant, index: usize, time: i64) Error!void {
        const s = &self.stations[index];
        const capacity: usize = if (index == @intFromEnum(StationName.BAR)) 2 else 1;
        while (s.up and s.queue.items.len > 0 and s.cooking.items.len < capacity) {
            const o = s.queue.orderedRemove(0);
            o.state = .COOKING;
            o.started = true;
            o.ready = time + o.prep;
            try s.cooking.append(self.gpa, o);
        }
    }
    fn tick(self: *Restaurant, end: i64) Error!void {
        try self.out.print("TICK {s}\n", .{try self.clock(end)});
        while (true) {
            var next: i64 = std.math.maxInt(i64);
            for (&self.stations) |*s| for (s.cooking.items) |o| { next = @min(next, o.ready); };
            if (next > end) break;
            for (&self.stations, 0..) |*s, index| {
                std.mem.sort(*Order, s.cooking.items, {}, struct {
                    fn less(_: void, a: *Order, b: *Order) bool { return a.id < b.id; }
                }.less);
                var i: usize = 0;
                while (i < s.cooking.items.len) {
                    const o = s.cooking.items[i];
                    if (o.ready != next) { i += 1; continue; }
                    _ = s.cooking.orderedRemove(i);
                    o.state = .READY;
                    const ticket = next - o.fired;
                    s.tickets += 1;
                    s.ticket_total += ticket;
                    s.ticket_max = @max(s.ticket_max, ticket);
                    const name: StationName = @enumFromInt(index);
                    try self.out.print("READY {s} {s} #{d} {s} x{d} table {d} seat {d}\n", .{ try self.clock(next), @tagName(name), o.id, o.item.name, o.quantity, o.check.table.number, o.seat });
                }
            }
            for (0..4) |i| try self.startCooking(i, next);
        }
        self.time = end;
    }
    fn bill(self: *Restaurant, c: *Check) Error!void {
        const seats = Seats.of(c);
        try self.out.print("BILL table {d} {s} guests {d}\n", .{ c.table.number, c.party, c.size });
        for (1..21) |seat| {
            if (!seats.present[seat]) continue;
            try self.out.print("SEAT {d} {s}\n", .{ seat, try self.money(seats.amounts[seat]) });
            for (c.orders.items) |o| {
                if (o.state == .VOID or o.seat != seat) continue;
                try self.out.print("#{d} {s} x{d} {s}", .{ o.id, o.item.name, o.quantity, try self.money(o.charge()) });
                if (o.comp) |reason| try self.out.print(" COMP {s}", .{reason});
                try self.out.writeAll("\n");
            }
        }
        const t = Totals.of(c);
        try self.out.print("SUBTOTAL {s}\n", .{try self.money(t.subtotal)});
        if (c.discount > 0) try self.out.print("DISCOUNT {d}% {s}\n", .{ c.discount, try self.money(t.discount) });
        if (c.size >= 6) try self.out.print("SERVICE {s}\n", .{try self.money(t.service)});
        try self.out.print("TAX {s}\nTOTAL {s}\n", .{ try self.money(t.tax), try self.money(t.total) });
        if (c.paid > 0) try self.out.print("PAID {s}\nDUE {s}\n", .{ try self.money(c.paid), try self.money(t.total - c.paid) });
    }
    fn split(self: *Restaurant, c: *Check, args: []const []const u8) Error!void {
        const t = Totals.of(c);
        const due = t.total - c.paid;
        if (due == 0) return self.fail("nothing to split for table {d}", .{c.table.number});
        if (equal(args[0], "EVEN")) {
            const k = integer(args[1]);
            if (k > @as(i64, @intCast(c.size))) return self.fail("cannot split table {d} {d} ways", .{ c.table.number, k });
            try self.out.print("SPLIT table {d} EVEN {d} due {s}\n", .{ c.table.number, k, try self.money(due) });
            var i: i64 = 1;
            while (i <= k) : (i += 1) try self.out.print("PAYER {d} {s}\n", .{ i, try self.money(@divTrunc(due, k) + @as(i64, @intFromBool(i <= @mod(due, k)))) });
        } else {
            if (c.paid > 0) return self.fail("table {d} has payments", .{c.table.number});
            const seats = Seats.of(c);
            const discounts = allocate(seats.amounts, seats.present, c.discount);
            var net = seats.amounts;
            for (1..21) |seat| net[seat] -= discounts[seat];
            const service = allocate(net, seats.present, if (c.size >= 6) 18 else 0);
            const tax = allocate(net, seats.present, 8);
            try self.out.print("SPLIT table {d} BYSEAT total {s}\n", .{ c.table.number, try self.money(t.total) });
            for (1..21) |seat| {
                if (!seats.present[seat]) continue;
                try self.out.print("SEAT {d} subtotal {s} discount {s} service {s} tax {s} total {s}\n", .{ seat, try self.money(seats.amounts[seat]), try self.money(discounts[seat]), try self.money(service[seat]), try self.money(tax[seat]), try self.money(net[seat] + service[seat] + tax[seat]) });
            }
        }
    }
    fn report(self: *Restaurant) Error!void {
        const t = self.totals;
        const average = if (self.turns == 0) "-" else try std.fmt.allocPrint(self.gpa, "{d}", .{@divTrunc(self.stay_total, self.turns)});
        try self.out.print("REPORT {s}\nCOVERS {d} parties {d}\nTURNS {d} avg_stay {s}\nSALES DRINK {s} STARTER {s} MAIN {s} DESSERT {s}\n", .{ try self.clock(self.time), self.covers, self.parties, self.turns, average, try self.money(self.sales[0]), try self.money(self.sales[1]), try self.money(self.sales[2]), try self.money(self.sales[3]) });
        try self.out.print("TOTALS subtotal {s} discount {s} service {s} tax {s} total {s}\nPAYMENTS cash {s} card {s} tips {s}\nCOMPS {d} {s} VOIDS {d}\n", .{ try self.money(t.subtotal), try self.money(t.discount), try self.money(t.service), try self.money(t.tax), try self.money(t.total), try self.money(self.cash), try self.money(self.card), try self.money(self.tips), self.comps, try self.money(self.comp_amount), self.voids });
        const items = try self.gpa.dupe(*MenuItem, self.menu.values());
        std.mem.sort(*MenuItem, items, {}, struct {
            fn less(_: void, a: *MenuItem, b: *MenuItem) bool { return if (a.served != b.served) a.served > b.served else std.mem.order(u8, a.name, b.name) == .lt; }
        }.less);
        for (items[0..@min(3, items.len)], 0..) |m, i| {
            if (m.served > 0) try self.out.print("TOP {d} {s} {d}\n", .{ i + 1, m.name, m.served });
        }
        for (&self.stations, 0..) |*s, i| {
            const name: StationName = @enumFromInt(i);
            try self.out.print("{s} tickets {d} avg ", .{ @tagName(name), s.tickets });
            if (s.tickets == 0) try self.out.writeAll("- max -") else try self.out.print("{d} max {d}", .{ @divTrunc(s.ticket_total, s.tickets), s.ticket_max });
            try self.out.print(" remakes {d}\n", .{s.remakes});
        }
        for (self.servers.values()) |s| try self.out.print("SERVER {s} tables {d} parties {d} sales {s} tips {s}\n", .{ s.name, s.load, s.parties, try self.money(s.sales), try self.money(s.tips) });
    }
    fn execute(self: *Restaurant, a: []const []const u8) Error!void {
        const op = std.meta.stringToEnum(Command, a[0]).?;
        const id: []const u8 = if (a.len > 1) a[1] else "";
        switch (op) {
            .TABLE => {
                const number = integer(id);
                if (self.tables.contains(number)) return self.fail("table {s} already exists", .{id});
                const t = try self.gpa.create(Table);
                t.* = .{ .number = number, .seats = @intCast(integer(a[2])) };
                try self.tables.put(self.gpa, number, t);
                try self.out.print("TABLE {d} seats {d}\n", .{ number, t.seats });
                try self.seatWaiting();
            },
            .STAFF => {
                if (self.servers.contains(id)) return self.fail("{s} is already on duty", .{id});
                const s = try self.gpa.create(Server);
                s.* = .{ .name = id };
                try self.servers.put(self.gpa, id, s);
                try self.out.print("STAFF {s}\n", .{id});
            },
            .SEAT => {
                for (self.tables.values()) |t| {
                    if (t.check) |c| if (equal(c.party, id)) { return self.fail("{s} is already seated at table {d}", .{ id, t.number }); };
                }
                for (self.waiting.items) |p| if (equal(p.name, id)) { return self.fail("{s} is already waiting", .{id}); };
                const size: usize = @intCast(integer(a[2]));
                var fits = false;
                for (self.tables.values()) |t| if (t.seats >= size) { fits = true; };
                if (!fits) return self.fail("no table for party of {d}", .{size});
                if (self.servers.count() == 0) return self.fail("no server on duty", .{});
                const p = Waiting{ .name = id, .size = size, .since = self.time };
                if (self.chooseTable(size)) |t| {
                    const c = try self.seatParty(p, t);
                    try self.out.print("SEAT {s} {d} table {d} server {s}\n", .{ id, size, t.number, c.server.name });
                } else {
                    try self.waiting.append(self.gpa, p);
                    try self.out.print("WAIT {s} {d} position {d}\n", .{ id, size, self.waiting.items.len });
                }
            },
            .CANCEL => {
                var index: ?usize = null;
                for (self.waiting.items, 0..) |p, i| if (equal(p.name, id)) { index = i; break; };
                const p = self.waiting.orderedRemove(index orelse return self.fail("{s} is not waiting", .{id}));
                try self.out.print("CANCEL {s} {d} waited {d}\n", .{ id, p.size, self.time - p.since });
            },
            .MOVE => {
                const from = try self.table(id);
                const to = try self.table(a[2]);
                const c = from.check orelse return self.fail("table {s} is free", .{id});
                if (to.check != null) return self.fail("table {s} is occupied", .{a[2]});
                if (to.seats < c.size) return self.fail("table {s} is too small for {s}", .{ a[2], c.party });
                from.check = null;
                to.check = c;
                c.table = to;
                try self.out.print("MOVE {s} table {d} -> {d}\n", .{ c.party, from.number, to.number });
                try self.seatWaiting();
            },
            .MENU => {
                const station = try self.stationName(a[2]);
                const course = try self.courseName(a[5]);
                const existing = self.menu.get(id);
                const m = existing orelse try self.gpa.create(MenuItem);
                if (existing == null) m.* = .{ .name = id, .station = station, .prep = integer(a[3]), .price = amount(a[4]), .course = course } else {
                    m.station = station;
                    m.prep = integer(a[3]);
                    m.price = amount(a[4]);
                    m.course = course;
                }
                try self.menu.put(self.gpa, id, m);
                try self.out.print("MENU {s} {s} {s} {d} {s} {s}\n", .{ if (existing == null) "ADD" else "UPDATE", id, a[2], m.prep, try self.money(m.price), a[5] });
            },
            .STOCK => {
                const m = try self.item(id);
                m.stock = integer(a[2]);
                try self.out.print("STOCK {s} {d}\n", .{ id, m.stock.? });
            },
            .HAPPY => {
                self.happy_rate = integer(id);
                self.happy_end = self.time + integer(a[2]);
                try self.out.print("HAPPY {d}% until {s}\n", .{ self.happy_rate, try self.clock(self.happy_end) });
            },
            .ITEMS => {
                const items = try self.gpa.dupe(*MenuItem, self.menu.values());
                std.mem.sort(*MenuItem, items, {}, struct {
                    fn less(_: void, x: *MenuItem, y: *MenuItem) bool { return if (x.course != y.course) @intFromEnum(x.course) < @intFromEnum(y.course) else std.mem.order(u8, x.name, y.name) == .lt; }
                }.less);
                try self.out.print("ITEMS {d}\n", .{items.len});
                for (items) |m| {
                    try self.out.print("{s} {s} {s} {d} {s} ", .{ @tagName(m.course), m.name, @tagName(m.station), m.prep, try self.money(m.price) });
                    if (m.stock) |stock| try self.out.print("{d}\n", .{stock}) else try self.out.writeAll("-\n");
                }
            },
            .ORDER, .FIRE, .SERVE, .DISCOUNT, .BILL, .SPLIT, .PAY, .CLOSE, .STATUS => {
                const c = try self.check(id);
                switch (op) {
                    .ORDER => {
                        try self.unlocked(c);
                        const seat: usize = @intCast(integer(a[2]));
                        try self.validSeat(c, seat);
                        const m = try self.item(a[3]);
                        const quantity = integer(a[4]);
                        if (m.stock != null and m.stock.? < quantity) return self.fail("only {d} {s} left", .{ m.stock.?, m.name });
                        const happy = m.course == .DRINK and self.time < self.happy_end;
                        const o = try self.gpa.create(Order);
                        o.* = .{ .id = self.orders.items.len + 1, .check = c, .seat = seat, .item = m, .quantity = quantity, .station = m.station, .prep = m.prep, .price = m.price - (if (happy) rounded(m.price, self.happy_rate) else 0), .course = m.course };
                        try self.orders.append(self.gpa, o);
                        try c.orders.append(self.gpa, o);
                        try self.out.print("ORDER #{d} table {d} seat {d} {s} x{d} {s}{s}\n", .{ o.id, c.table.number, seat, m.name, quantity, try self.money(o.charge()), if (happy) " HAPPY" else "" });
                        if (m.stock) |stock| {
                            m.stock = stock - quantity;
                            if (m.stock.? == 0) try self.out.print("SOLDOUT {s}\n", .{m.name});
                        }
                    },
                    .FIRE => {
                        const course = try self.courseName(a[2]);
                        var found = false;
                        for (c.orders.items) |o| if (o.course == course and o.state == .ORDERED) { found = true; };
                        if (!found) return self.fail("nothing to fire for {s} at table {d}", .{ a[2], c.table.number });
                        if (course == .MAIN or course == .DESSERT) {
                            for (1..@intFromEnum(course)) |earlier| {
                                for (c.orders.items) |o| if (@intFromEnum(o.course) == earlier and o.state == .ORDERED) { return self.fail("fire {s} first", .{@tagName(o.course)}); };
                            }
                        }
                        try self.out.print("FIRE table {d} {s}", .{ c.table.number, a[2] });
                        for (c.orders.items) |o| {
                            if (o.course != course or o.state != .ORDERED) continue;
                            o.state = .QUEUED;
                            o.fired = self.time;
                            try self.stations[@intFromEnum(o.station)].queue.append(self.gpa, o);
                            try self.out.print(" #{d}", .{o.id});
                        }
                        try self.out.writeAll("\n");
                        for (0..4) |i| try self.startCooking(i, self.time);
                    },
                    .SERVE => {
                        var found = false;
                        for (c.orders.items) |o| if (o.state == .READY) { found = true; };
                        if (!found) return self.fail("nothing ready for table {d}", .{c.table.number});
                        try self.out.print("SERVE table {d}", .{c.table.number});
                        for (c.orders.items) |o| {
                            if (o.state != .READY) continue;
                            o.state = .SERVED;
                            o.item.served += o.quantity;
                            try self.out.print(" #{d}", .{o.id});
                        }
                        try self.out.writeAll("\n");
                    },
                    .DISCOUNT => {
                        try self.unlocked(c);
                        c.discount = integer(a[2]);
                        try self.out.print("DISCOUNT table {d} {d}%\n", .{ c.table.number, c.discount });
                    },
                    .BILL => try self.bill(c),
                    .SPLIT => try self.split(c, a[2..]),
                    .PAY => {
                        const cash = equal(a[2], "CASH");
                        if (!cash and !equal(a[2], "CARD")) return self.fail("unknown method {s}", .{a[2]});
                        try self.allServed(c);
                        const due = Totals.of(c).total - c.paid;
                        if (due == 0) return self.fail("nothing to pay for table {d}", .{c.table.number});
                        const paid = amount(a[3]);
                        const applied = @min(paid, due);
                        c.paid += applied;
                        if (cash) self.cash += applied else self.card += applied;
                        if (paid < due) {
                            try self.out.print("PAY table {d} {s} {s} remaining {s}\n", .{ c.table.number, a[2], try self.money(paid), try self.money(due - paid) });
                        } else {
                            if (!cash) { self.tips += paid - due; c.server.tips += paid - due; }
                            try self.out.print("PAY table {d} {s} {s} {s} {s}\n", .{ c.table.number, a[2], try self.money(paid), if (cash) "change" else "tip", try self.money(paid - due) });
                            try self.closeCheck(c);
                        }
                    },
                    .CLOSE => {
                        try self.allServed(c);
                        const due = Totals.of(c).total - c.paid;
                        if (due != 0) return self.fail("table {d} still owes {s}", .{ c.table.number, try self.money(due) });
                        try self.closeCheck(c);
                    },
                    .STATUS => {
                        try self.out.print("STATUS table {d} {s} guests {d} since {s}\n", .{ c.table.number, c.party, c.size, try self.clock(c.seated) });
                        for (c.orders.items) |o| {
                            try self.out.print("#{d} seat {d} {s} x{d} {s} {s}", .{ o.id, o.seat, o.item.name, o.quantity, @tagName(o.course), @tagName(o.state) });
                            if (o.state == .COOKING) try self.out.print(" until {s}", .{try self.clock(o.ready)});
                            if (o.comp) |reason| try self.out.print(" COMP {s}", .{reason});
                            try self.out.writeAll("\n");
                        }
                    },
                    else => unreachable,
                }
            },
            .TICK => try self.tick(self.time + integer(id)),
            .RUSH, .REMAKE, .VOID, .COMP, .TRANSFER => {
                const o = try self.order(id);
                const s = &self.stations[@intFromEnum(o.station)];
                switch (op) {
                    .RUSH => {
                        if (o.state != .QUEUED) return self.fail("#{d} is not queued", .{o.id});
                        removeOrder(&s.queue, o);
                        try s.queue.insert(self.gpa, 0, o);
                        try self.out.print("RUSH #{d} {s}\n", .{ o.id, @tagName(o.station) });
                    },
                    .REMAKE => {
                        if (o.check.closed) return self.fail("#{d} is on a closed check", .{o.id});
                        if (o.state != .READY and o.state != .SERVED) return self.fail("#{d} is not ready or served", .{o.id});
                        o.state = .QUEUED;
                        o.fired = self.time;
                        try s.queue.insert(self.gpa, 0, o);
                        s.remakes += 1;
                        try self.out.print("REMAKE #{d} {s} {s}\n", .{ o.id, o.item.name, @tagName(o.station) });
                        try self.startCooking(@intFromEnum(o.station), self.time);
                    },
                    .VOID => {
                        if (o.state == .VOID) return self.fail("#{d} is already void", .{o.id});
                        if (o.started) return self.fail("#{d} has already started", .{o.id});
                        if (o.state == .QUEUED) removeOrder(&s.queue, o);
                        o.state = .VOID;
                        if (o.item.stock) |stock| o.item.stock = stock + o.quantity;
                        self.voids += 1;
                        try self.out.print("VOID #{d} {s} x{d}\n", .{ o.id, o.item.name, o.quantity });
                    },
                    .COMP => {
                        try self.modifiable(o);
                        if (o.comp != null) return self.fail("#{d} is already comped", .{o.id});
                        const value = o.charge();
                        self.comps += 1;
                        self.comp_amount += value;
                        o.comp = a[2];
                        try self.out.print("COMP #{d} {s} {s} {s}\n", .{ o.id, o.item.name, try self.money(value), a[2] });
                    },
                    .TRANSFER => {
                        try self.modifiable(o);
                        const seat: usize = @intCast(integer(a[2]));
                        try self.validSeat(o.check, seat);
                        if (seat == o.seat) return self.fail("#{d} is already on seat {d}", .{ o.id, seat });
                        try self.out.print("TRANSFER #{d} seat {d} -> {d}\n", .{ o.id, o.seat, seat });
                        o.seat = seat;
                    },
                    else => unreachable,
                }
            },
            .STATION => {
                const name = try self.stationName(id);
                const s = &self.stations[@intFromEnum(name)];
                const up = equal(a[2], "UP");
                if (s.up == up) return self.fail("station {s} is {s}", .{ id, if (up) "not down" else "already down" });
                s.up = up;
                if (up) try self.startCooking(@intFromEnum(name), self.time);
                try self.out.print("STATION {s} {s}\n", .{ id, a[2] });
            },
            .KITCHEN => {
                try self.out.print("KITCHEN {s}\n", .{try self.clock(self.time)});
                for (&self.stations, 0..) |*s, i| {
                    const name: StationName = @enumFromInt(i);
                    const cooking = try self.gpa.dupe(*Order, s.cooking.items);
                    std.mem.sort(*Order, cooking, {}, struct {
                        fn less(_: void, x: *Order, y: *Order) bool { return if (x.ready != y.ready) x.ready < y.ready else x.id < y.id; }
                    }.less);
                    try self.out.print("{s} {s} cooking", .{ @tagName(name), if (s.up) "up" else "down" });
                    for (cooking) |o| try self.out.print(" #{d}@{s}", .{ o.id, try self.clock(o.ready) });
                    if (cooking.len == 0) try self.out.writeAll(" -");
                    try self.out.writeAll(" queue");
                    for (s.queue.items) |o| try self.out.print(" #{d}", .{o.id});
                    if (s.queue.items.len == 0) try self.out.writeAll(" -");
                    try self.out.writeAll("\n");
                }
            },
            .FLOOR => {
                const ordered = try self.gpa.dupe(*Table, self.tables.values());
                std.mem.sort(*Table, ordered, {}, struct {
                    fn less(_: void, x: *Table, y: *Table) bool { return x.number < y.number; }
                }.less);
                var free: usize = 0;
                for (ordered) |t| if (t.check == null) { free += 1; };
                try self.out.print("FLOOR {s} free {d} seated {d} waiting {d}\n", .{ try self.clock(self.time), free, ordered.len - free, self.waiting.items.len });
                for (ordered) |t| {
                    try self.out.print("table {d} seats {d}", .{ t.number, t.seats });
                    if (t.check) |c| {
                        try self.out.print(" {s} guests {d} server {s} since {s} items {d} total {s}", .{ c.party, c.size, c.server.name, try self.clock(c.seated), c.activeCount(), try self.money(Totals.of(c).total) });
                        if (c.paid > 0) try self.out.print(" paid {s}", .{try self.money(c.paid)});
                    } else try self.out.writeAll(" free");
                    try self.out.writeAll("\n");
                }
                for (self.waiting.items, 0..) |p, i| try self.out.print("WAITING {d} {s} {d} since {s}\n", .{ i + 1, p.name, p.size, try self.clock(p.since) });
            },
            .REPORT => try self.report(),
        }
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var restaurant = Restaurant{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var tokens: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |token| try tokens.append(gpa, token);
        restaurant.execute(tokens.items) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{restaurant.error_message});
        };
    }
    try output.interface.flush();
}
