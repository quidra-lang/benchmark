const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const class_names = [_][]const u8{ "F", "J", "Y" };
const tier_names = [_][]const u8{ "PLATINUM", "GOLD", "SILVER", "NONE" };
fn integer(text: []const u8) usize { return std.fmt.parseInt(usize, text, 10) catch unreachable; }
fn classIndex(text: []const u8) usize { return std.mem.findScalar(u8, "FJY", text[0]).?; }
fn split(gpa: Allocator, text: []const u8, delimiter: u8) Allocator.Error![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, delimiter);
    while (it.next()) |part| try result.append(gpa, part);
    return result.items;
}
const Seat = struct { row: usize, letter: u8, cabin: usize, block: usize, kind: u8 };
const Cabin = struct { first: usize, last: usize, blocks: [][]const u8 };
const Aircraft = struct {
    name: []const u8, base: usize, limit: i64,
    cabins: [3]?Cabin = .{ null, null, null },
    seats: std.ArrayList(Seat) = .empty,
    grid: [100][26]?usize = .{.{null} ** 26} ** 100,
    exits: [100]bool = .{false} ** 100,
    blocked: [2600]bool = .{false} ** 2600,
    fn seatIndex(self: *const Aircraft, code: []const u8) ?usize {
        const row = integer(code[0..code.len - 1]);
        return self.grid[row][code[code.len - 1] - 'A'];
    }
    fn addCabin(self: *Aircraft, gpa: Allocator, c: usize, first: usize, last: usize, blocks: [][]const u8) Allocator.Error!void {
        self.cabins[c] = .{ .first = first, .last = last, .blocks = blocks };
        for (first..last + 1) |row| {
            for (blocks, 0..) |block, b| {
                for (block, 0..) |letter, x| {
                    const kind: u8 = if ((b == 0 and x == 0) or (b == blocks.len - 1 and x == block.len - 1)) 'W' else
                        if (x == 0 or x == block.len - 1) 'A' else 'M';
                    self.grid[row][letter - 'A'] = self.seats.items.len;
                    try self.seats.append(gpa, .{ .row = row, .letter = letter, .cabin = c, .block = b, .kind = kind });
                }
            }
        }
    }
    fn capacity(self: *const Aircraft, c: usize) usize {
        var count: usize = 0;
        for (self.seats.items, 0..) |s, i| {
            if (s.cabin == c and !self.blocked[i]) count += 1;
        }
        return count;
    }
};
const PassengerType = enum { ADULT, CHILD, INFANT };
const Passenger = struct {
    name: []const u8, kind: PassengerType, preference: u8, cabin: usize,
    booking: *Booking = undefined,
    seat: ?usize = null, active: bool = true,
    infant: ?*Passenger = null, guardian: ?*Passenger = null,
    fn needsSeat(self: *const Passenger) bool { return self.kind != .INFANT; }
    fn carrying(self: *const Passenger) bool { return if (self.infant) |p| p.active else false; }
};
const Booking = struct {
    pnr: []const u8, flight: *Flight, listed: []*Passenger, checked: bool = false,
    fn count(self: *const Booking) usize {
        var result: usize = 0;
        for (self.listed) |p| {
            if (p.active) result += 1;
        }
        return result;
    }
    fn hasInfants(self: *const Booking) bool {
        for (self.listed) |p| {
            if (p.active and !p.needsSeat()) return true;
        }
        return false;
    }
};
const Flight = struct {
    name: []const u8, aircraft: *Aircraft,
    limits: [3]usize,
    blocked: [2600]bool,
    occupied: [2600]?*Passenger = .{null} ** 2600,
    bookings: std.ArrayList(*Booking) = .empty,
    volunteers: std.ArrayList(*Passenger) = .empty,
    closed: bool = false,
    fn allPassengers(self: *const Flight, gpa: Allocator) Allocator.Error![]*Passenger {
        var result: std.ArrayList(*Passenger) = .empty;
        for (self.bookings.items) |b| for (b.listed) |p| {
            if (p.active) try result.append(gpa, p);
        };
        return result.items;
    }
    fn booked(self: *const Flight, c: usize) usize {
        var result: usize = 0;
        for (self.bookings.items) |b| for (b.listed) |p| {
            if (p.active and p.needsSeat() and p.cabin == c) result += 1;
        };
        return result;
    }
    fn place(self: *Flight, p: *Passenger, seat: ?usize) void {
        if (p.seat) |old| self.occupied[old] = null;
        p.seat = seat;
        if (seat) |index| self.occupied[index] = p;
    }
    fn fits(self: *const Flight, ps: []const *Passenger, ss: []const usize, c: usize, vacated: ?*Passenger) bool {
        for (ps, ss, 0..) |p, index, i| {
            const s = self.aircraft.seats.items[index];
            if (s.cabin != c or self.blocked[index]) return false;
            if (std.mem.findScalar(usize, ss[0..i], index) != null) return false;
            if (self.occupied[index]) |occupant| {
                if (std.mem.findScalar(*Passenger, ps, occupant) == null and occupant != vacated) return false;
            }
            if ((p.kind == .CHILD or p.carrying()) and self.aircraft.exits[s.row]) return false;
            if (p.carrying()) {
                const block = self.aircraft.cabins[c].?.blocks[s.block];
                for (block) |letter| {
                    const other_index = self.aircraft.grid[s.row][letter - 'A'].?;
                    if (self.occupied[other_index]) |other| {
                        if (other != p and std.mem.findScalar(*Passenger, ps, other) == null and other != vacated and other.carrying()) return false;
                    }
                }
                for (ps, ss, 0..) |other_p, other_index, j| {
                    const other_s = self.aircraft.seats.items[other_index];
                    if (j != i and other_p.carrying() and s.row == other_s.row and s.block == other_s.block) return false;
                }
            }
        }
        return true;
    }
    fn choose(self: *const Flight, p: *Passenger, c: usize) ?usize {
        var first: ?usize = null;
        for (self.aircraft.seats.items, 0..) |s, i| {
            if (!self.fits(&.{p}, &.{i}, c, null)) continue;
            if (first == null) first = i;
            if (p.preference == s.kind) return i;
        }
        return first;
    }
    fn adopt(self: *Flight, ps: []const *Passenger, ss: []const usize, c: usize) bool {
        if (!self.fits(ps, ss, c, null)) return false;
        for (ps, ss) |p, seat| self.place(p, seat);
        return true;
    }
    fn assign(self: *Flight, b: *Booking, c: usize) []const u8 {
        var passengers: [9]*Passenger = undefined;
        var k: usize = 0;
        for (b.listed) |p| {
            if (p.needsSeat()) {
                passengers[k] = p;
                k += 1;
            }
        }
        const ps = passengers[0..k];
        if (k == 1) {
            self.place(ps[0], self.choose(ps[0], c));
            return "SINGLE";
        }
        const cabin = self.aircraft.cabins[c].?;
        var candidate: [9]usize = undefined;
        for (cabin.first..cabin.last + 1) |row| {
            for (cabin.blocks) |block| {
                var x: usize = 0;
                while (x + k <= block.len) : (x += 1) {
                    for (0..k) |j| candidate[j] = self.aircraft.grid[row][block[x + j] - 'A'].?;
                    if (self.adopt(ps, candidate[0..k], c)) return "BLOCK";
                }
            }
        }
        for (cabin.first..cabin.last + 1) |row| {
            var line: [10]usize = undefined;
            var len: usize = 0;
            for (cabin.blocks) |block| for (block) |letter| {
                line[len] = self.aircraft.grid[row][letter - 'A'].?;
                len += 1;
            };
            var x: usize = 0;
            while (x + k <= len) : (x += 1) {
                if (self.adopt(ps, line[x..x + k], c)) return "ROW";
            }
        }
        for (2..k + 1) |h| {
            const width = (k + h - 1) / h;
            const height = (k + width - 1) / width;
            var row = cabin.first;
            while (row + height - 1 <= cabin.last) : (row += 1) {
                for (cabin.blocks) |block| {
                    var x: usize = 0;
                    while (x + width <= block.len) : (x += 1) {
                        for (0..k) |j| candidate[j] = self.aircraft.grid[row + j / width][block[x + j % width] - 'A'].?;
                        if (self.adopt(ps, candidate[0..k], c)) return "STACK";
                    }
                }
            }
        }
        for (ps) |p| self.place(p, self.choose(p, c));
        return "SPLIT";
    }
    fn displaySeat(self: *const Flight, gpa: Allocator, p: *const Passenger) Allocator.Error![]const u8 {
        if (!p.needsSeat()) return "LAP";
        const seat = p.seat orelse return "UNASSIGNED";
        const s = self.aircraft.seats.items[seat];
        return std.fmt.allocPrint(gpa, "{d}{c}", .{ s.row, s.letter });
    }
    fn reassign(self: *Flight, gpa: Allocator, out: *std.Io.Writer) Error!void {
        for (self.bookings.items) |b| for (b.listed) |p| {
            if (!p.active or !p.needsSeat() or p.seat != null) continue;
            if (self.choose(p, p.cabin)) |seat| {
                self.place(p, seat);
                try out.print("REASSIGNED {s} {s} {s}\n", .{ b.pnr, p.name, try self.displaySeat(gpa, p) });
            }
        };
    }
    fn remove(self: *Flight, p: *Passenger) void {
        if (!p.active) return;
        if (p.carrying()) self.remove(p.infant.?);
        if (p.guardian) |guardian| {
            guardian.infant = null;
            p.guardian = null;
        }
        self.place(p, null);
        p.active = false;
        if (std.mem.findScalar(*Passenger, self.volunteers.items, p)) |i|
            _ = self.volunteers.orderedRemove(i);
    }
};
const Airline = struct {
    gpa: Allocator,
    models: std.StringHashMapUnmanaged(*Aircraft) = .empty,
    flights: std.StringArrayHashMapUnmanaged(*Flight) = .empty,
    bookings: std.StringHashMapUnmanaged(*Booking) = .empty,
    statuses: std.StringHashMapUnmanaged(usize) = .empty,
    defining: ?*Aircraft = null,
    error_buffer: [1024]u8 = undefined, error_len: usize = 0,
    fn fail(self: *Airline, comptime fmt: []const u8, args: anytype) error{BadCommand} {
        const message = std.fmt.bufPrint(&self.error_buffer, fmt, args) catch unreachable;
        self.error_len = message.len;
        return error.BadCommand;
    }
    fn tier(self: *const Airline, name: []const u8) usize {
        return self.statuses.get(name) orelse 3;
    }
    fn findFlight(self: *Airline, name: []const u8, open: bool) Error!*Flight {
        const f = self.flights.get(name) orelse return self.fail("unknown flight {s}", .{name});
        if (open and f.closed) return self.fail("flight {s} is closed", .{name});
        return f;
    }
    fn findBooking(self: *Airline, pnr: []const u8, open: bool) Error!*Booking {
        const b = self.bookings.get(pnr) orelse return self.fail("unknown PNR {s}", .{pnr});
        if (b.count() == 0) return self.fail("unknown PNR {s}", .{pnr});
        if (open and b.flight.closed) return self.fail("flight {s} is closed", .{b.flight.name});
        return b;
    }
    fn findPassenger(self: *Airline, b: *Booking, name: []const u8) Error!*Passenger {
        for (b.listed) |p| {
            if (p.active and std.mem.eql(u8, p.name, name)) return p;
        }
        return self.fail("no passenger {s} in {s}", .{ name, b.pnr });
    }
    fn hasCabin(self: *Airline, f: *Flight, c: usize) Error!void {
        if (f.aircraft.cabins[c] == null) return self.fail("no cabin {s} on {s}", .{ class_names[c], f.name });
    }
    fn deny(self: *Airline, f: *Flight, p: *Passenger, voluntary: bool, out: *std.Io.Writer) Error!i64 {
        var value: i64 = ([_]i64{ 500, 300, 150 })[p.cabin] * @as(i64, if (voluntary) 1 else 2);
        if (p.kind == .CHILD) value = @divFloor(value, 2);
        try out.print("DENIED {s} {s} {s} {s} {d}\n", .{ @as([]const u8, if (voluntary) "VOLUNTARY" else "INVOLUNTARY"),
            p.booking.pnr, p.name, class_names[p.cabin], value });
        f.remove(p);
        _ = self;
        return value;
    }
    fn execute(self: *Airline, line: []const u8, out: *std.Io.Writer) Error!void {
        const a = try split(self.gpa, line, ' ');
        const op = a[0];
        if (std.mem.eql(u8, op, "AIRCRAFT")) {
            const model = try self.gpa.create(Aircraft);
            model.* = .{ .name = a[1], .base = integer(a[2]), .limit = @intCast(integer(a[3])) };
            self.defining = model;
        } else if (std.mem.eql(u8, op, "CABIN")) {
            try self.defining.?.addCabin(self.gpa, classIndex(a[1]), integer(a[2]), integer(a[3]), a[4..]);
        } else if (std.mem.eql(u8, op, "EXIT")) {
            for (a[1..]) |row| self.defining.?.exits[integer(row)] = true;
        } else if (std.mem.eql(u8, op, "BLOCKED")) {
            for (a[1..]) |seat| self.defining.?.blocked[self.defining.?.seatIndex(seat).?] = true;
        } else if (std.mem.eql(u8, op, "END")) {
            const model = self.defining.?;
            try self.models.put(self.gpa, model.name, model);
            self.defining = null;
            try out.print("AIRCRAFT {s}", .{model.name});
            for (model.cabins, 0..) |cabin, c| {
                if (cabin != null) try out.print(" {s} {d}", .{ class_names[c], model.capacity(c) });
            }
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, op, "FLIGHT")) {
            if (self.flights.contains(a[1])) return self.fail("duplicate flight {s}", .{a[1]});
            const model = self.models.get(a[2]) orelse return self.fail("unknown aircraft {s}", .{a[2]});
            const f = try self.gpa.create(Flight);
            f.* = .{ .name = a[1], .aircraft = model, .blocked = model.blocked,
                .limits = .{ model.capacity(0) * (100 + integer(a[3])) / 100, model.capacity(1) * (100 + integer(a[3])) / 100,
                    model.capacity(2) * (100 + integer(a[3])) / 100 } };
            try self.flights.put(self.gpa, f.name, f);
            try out.print("FLIGHT {s} {s}", .{ f.name, model.name });
            for (model.cabins, 0..) |cabin, c| {
                if (cabin != null) try out.print(" {s} {d}/{d}", .{ class_names[c], model.capacity(c), f.limits[c] });
            }
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, op, "STATUS")) {
            var value: usize = 3;
            for (tier_names, 0..) |name, i| {
                if (std.mem.eql(u8, name, a[2])) value = i;
            }
            try self.statuses.put(self.gpa, a[1], value);
            try out.print("STATUS {s} {s}\n", .{ a[1], a[2] });
        } else if (std.mem.eql(u8, op, "BOOK")) {
            if (self.bookings.contains(a[1])) return self.fail("duplicate PNR {s}", .{a[1]});
            const f = try self.findFlight(a[2], true);
            const c = classIndex(a[3]);
            try self.hasCabin(f, c);
            const ps = try self.gpa.alloc(*Passenger, a.len - 4);
            var adults: [9]*Passenger = undefined;
            var adult_count: usize = 0;
            var infants: [9]*Passenger = undefined;
            var infant_count: usize = 0;
            for (a[4..], 0..) |token, i| {
                const parts = try split(self.gpa, token, ':');
                const p = try self.gpa.create(Passenger);
                p.* = .{ .name = parts[0], .kind = std.meta.stringToEnum(PassengerType, parts[1]).?,
                    .preference = if (parts.len == 3) parts[2][0] else 0, .cabin = c };
                ps[i] = p;
                if (p.kind == .ADULT) {
                    adults[adult_count] = p;
                    adult_count += 1;
                }
                if (p.kind == .INFANT) {
                    infants[infant_count] = p;
                    infant_count += 1;
                }
                for (ps[0..i]) |previous| {
                    if (std.mem.eql(u8, previous.name, p.name)) return self.fail("duplicate name {s} in {s}", .{ p.name, a[1] });
                }
            }
            for (ps) |p| for (f.bookings.items) |b| for (b.listed) |existing| {
                if (existing.active and std.mem.eql(u8, existing.name, p.name)) return self.fail("{s} already on {s}", .{ p.name, f.name });
            };
            if (adult_count == 0) return self.fail("no adult in {s}", .{a[1]});
            if (infant_count > adult_count) return self.fail("too many infants in {s}", .{a[1]});
            if (f.booked(c) + ps.len - infant_count > f.limits[c]) return self.fail("limit exceeded for {s} {s}", .{ f.name, class_names[c] });
            for (0..infant_count) |i| {
                adults[i].infant = infants[i];
                infants[i].guardian = adults[i];
            }
            const b = try self.gpa.create(Booking);
            b.* = .{ .pnr = a[1], .flight = f, .listed = ps };
            for (ps) |p| p.booking = b;
            try self.bookings.put(self.gpa, b.pnr, b);
            try f.bookings.append(self.gpa, b);
            const method = f.assign(b, c);
            try out.print("BOOKED {s} {s} {s} {s}", .{ b.pnr, f.name, class_names[c], method });
            for (ps) |p| try out.print(" {s}:{s}", .{ p.name, try f.displaySeat(self.gpa, p) });
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, op, "SEAT")) {
            const b = try self.findBooking(a[1], true);
            const p = try self.findPassenger(b, a[2]);
            const f = b.flight;
            if (!p.needsSeat()) return self.fail("infant {s} has no seat", .{p.name});
            const found = f.aircraft.seatIndex(a[3]);
            if (found == null or f.aircraft.seats.items[found.?].cabin != p.cabin)
                return self.fail("no seat {s} in cabin {s}", .{ a[3], class_names[p.cabin] });
            const seat = found.?;
            if (f.blocked[seat]) return self.fail("seat {s} is blocked", .{a[3]});
            if (f.occupied[seat] != null) return self.fail("seat {s} is occupied", .{a[3]});
            const s = f.aircraft.seats.items[seat];
            if ((p.kind == .CHILD or p.carrying()) and f.aircraft.exits[s.row]) return self.fail("exit row {d} not allowed for {s}", .{ s.row, p.name });
            if (!f.fits(&.{p}, &.{seat}, p.cabin, null)) return self.fail("infant limit reached at {s}", .{a[3]});
            const old = try f.displaySeat(self.gpa, p);
            f.place(p, seat);
            try out.print("MOVED {s} {s} {s} -> {s}\n", .{ b.pnr, p.name, old, a[3] });
            try f.reassign(self.gpa, out);
        } else if (std.mem.eql(u8, op, "SWAP")) {
            const b = try self.findBooking(a[1], true);
            const p = try self.findPassenger(b, a[2]);
            const d = try self.findBooking(a[3], true);
            const q = try self.findPassenger(d, a[4]);
            if (p == q) return self.fail("cannot swap {s} with itself", .{p.name});
            for ([_]*Passenger{ p, q }) |person| {
                if (!person.needsSeat()) return self.fail("infant {s} has no seat", .{person.name});
            }
            if (b.flight != d.flight) return self.fail("{s} and {s} are on different flights", .{ b.pnr, d.pnr });
            if (p.cabin != q.cabin) return self.fail("{s} and {s} are in different cabins", .{ p.name, q.name });
            for ([_]*Passenger{ p, q }) |person| {
                if (person.seat == null) return self.fail("{s} has no seat", .{person.name});
            }
            const f = b.flight;
            const old = p.seat.?;
            const other = q.seat.?;
            if (!f.fits(&.{ p, q }, &.{ other, old }, p.cabin, null)) return self.fail("swap of {s} and {s} breaks seating rules", .{ p.name, q.name });
            f.place(p, null);
            f.place(q, null);
            f.place(p, other);
            f.place(q, old);
            try out.print("SWAPPED {s} {s} {s} {s} {s} {s}\n", .{ b.pnr, p.name, try f.displaySeat(self.gpa, p), d.pnr, q.name, try f.displaySeat(self.gpa, q) });
            try f.reassign(self.gpa, out);
        } else if (std.mem.eql(u8, op, "CANCEL")) {
            const b = try self.findBooking(a[1], true);
            const f = b.flight;
            const target: ?*Passenger = if (a.len == 2) null else try self.findPassenger(b, a[2]);
            var removed: std.ArrayList(*Passenger) = .empty;
            var remaining: usize = 0;
            var adults: usize = 0;
            for (b.listed) |p| {
                if (!p.active) continue;
                if (target == null or p == target or target.?.infant == p) try removed.append(self.gpa, p) else {
                    remaining += 1;
                    if (p.kind == .ADULT) adults += 1;
                }
            }
            if (target != null and remaining > 0 and adults == 0) return self.fail("{s} would have no adult", .{b.pnr});
            try out.print("CANCELLED {s}", .{b.pnr});
            for (removed.items) |p| try out.print(" {s}", .{p.name});
            try out.writeByte('\n');
            for (removed.items) |p| f.remove(p);
            try f.reassign(self.gpa, out);
        } else if (std.mem.eql(u8, op, "CHECKIN") or std.mem.eql(u8, op, "VOLUNTEER")) {
            const b = try self.findBooking(a[1], true);
            const f = b.flight;
            if (std.mem.eql(u8, op, "CHECKIN")) {
                if (b.checked) return self.fail("{s} already checked in", .{b.pnr});
                b.checked = true;
                try out.print("CHECKIN {s} {d}\n", .{ b.pnr, b.count() });
            } else {
                const p = try self.findPassenger(b, a[2]);
                if (p.kind != .ADULT or p.carrying()) return self.fail("{s} cannot volunteer", .{p.name});
                if (p.seat == null) return self.fail("{s} has no seat", .{p.name});
                if (std.mem.findScalar(*Passenger, f.volunteers.items, p) != null) return self.fail("{s} already volunteered", .{p.name});
                try f.volunteers.append(self.gpa, p);
                try out.print("VOLUNTEER {s} {s} {s}\n", .{ b.pnr, p.name, try f.displaySeat(self.gpa, p) });
            }
        } else if (std.mem.eql(u8, op, "UPGRADE")) {
            const f = try self.findFlight(a[1], true);
            var cs: [3]usize = undefined;
            var len: usize = 0;
            for (f.aircraft.cabins, 0..) |cabin, c| {
                if (cabin != null) {
                    cs[len] = c;
                    len += 1;
                }
            }
            var count: usize = 0;
            for (0..len - 1) |i| {
                const higher = cs[i];
                const lower = cs[i + 1];
                var targets: std.ArrayList(*Passenger) = .empty;
                for (try f.allPassengers(self.gpa)) |p| {
                    if (p.cabin == lower and p.kind == .ADULT and !p.carrying() and self.tier(p.name) < 3) try targets.append(self.gpa, p);
                }
                std.mem.sort(*Passenger, targets.items, @as(*const Airline, self), tierLess);
                for (targets.items) |p| {
                    if (f.booked(higher) >= f.limits[higher]) break;
                    const seat = f.choose(p, higher) orelse break;
                    const old = try f.displaySeat(self.gpa, p);
                    f.place(p, seat);
                    p.cabin = higher;
                    count += 1;
                    try out.print("UPGRADED {s} {s} {s} {s} -> {s} {s}\n", .{ p.booking.pnr, p.name, class_names[lower], old,
                        class_names[higher], try f.displaySeat(self.gpa, p) });
                }
            }
            try f.reassign(self.gpa, out);
            try out.print("UPGRADE {s} {d}\n", .{ f.name, count });
        } else if (std.mem.eql(u8, op, "CLOSE")) {
            const f = try self.findFlight(a[1], true);
            var denied: usize = 0;
            var compensation: i64 = 0;
            for (f.bookings.items) |b| {
                if (b.count() == 0 or b.checked) continue;
                try out.print("NOSHOW {s} {d}\n", .{ b.pnr, b.count() });
                for (b.listed) |p| {
                    if (p.active) f.remove(p);
                }
            }
            try f.reassign(self.gpa, out);
            for (0..3) |c| {
                var targets: std.ArrayList(*Passenger) = .empty;
                for (f.volunteers.items) |p| {
                    if (p.active and p.seat != null and p.cabin == c) try targets.append(self.gpa, p);
                }
                for (targets.items) |p| {
                    var useful = false;
                    for (try f.allPassengers(self.gpa)) |q| {
                        if (q.needsSeat() and q.seat == null and q.cabin == c and f.fits(&.{q}, &.{p.seat.?}, c, p)) {
                            useful = true;
                            break;
                        }
                    }
                    if (useful) {
                        compensation += try self.deny(f, p, true, out);
                        denied += 1;
                        try f.reassign(self.gpa, out);
                    }
                }
            }
            for (try f.allPassengers(self.gpa)) |p| {
                if (p.active and p.needsSeat() and p.seat == null) {
                    compensation += try self.deny(f, p, false, out);
                    denied += 1;
                }
            }
            f.closed = true;
            try out.print("CLOSED {s} denied {d} compensation {d}\n", .{ f.name, denied, compensation });
        } else if (std.mem.eql(u8, op, "BLOCK") or std.mem.eql(u8, op, "UNBLOCK")) {
            const f = try self.findFlight(a[1], true);
            const seat = f.aircraft.seatIndex(a[2]) orelse return self.fail("no seat {s} on {s}", .{ a[2], f.name });
            const blocking = std.mem.eql(u8, op, "BLOCK");
            if (blocking and f.blocked[seat]) return self.fail("seat {s} is blocked", .{a[2]});
            if (!blocking and !f.blocked[seat]) return self.fail("seat {s} is not blocked", .{a[2]});
            try out.print("{s} {s} {s}\n", .{ op, f.name, a[2] });
            f.blocked[seat] = blocking;
            if (blocking) {
                if (f.occupied[seat]) |p| {
                    f.place(p, null);
                    f.place(p, f.choose(p, p.cabin));
                    try out.print("DISPLACED {s} {s} {s} -> {s}\n", .{ p.booking.pnr, p.name, a[2], try f.displaySeat(self.gpa, p) });
                }
            }
            try f.reassign(self.gpa, out);
        } else if (std.mem.eql(u8, op, "INFO")) {
            const b = try self.findBooking(a[1], false);
            const f = b.flight;
            try out.print("INFO {s} {s} {d} {s}\n", .{ b.pnr, f.name, b.count(), @as([]const u8, if (b.checked) "CHECKED" else "NOT-CHECKED") });
            for (b.listed) |p| {
                if (p.active) try out.print("{s} {s} {s} {s}\n", .{ p.name, @tagName(p.kind), class_names[p.cabin], try f.displaySeat(self.gpa, p) });
            }
        } else if (std.mem.eql(u8, op, "FIND")) {
            var found: std.ArrayList(*Passenger) = .empty;
            for (self.flights.values()) |f| for (try f.allPassengers(self.gpa)) |p| {
                if (std.mem.eql(u8, p.name, a[1])) try found.append(self.gpa, p);
            };
            try out.print("FIND {s} {s} {d}\n", .{ a[1], tier_names[self.tier(a[1])], found.items.len });
            for (found.items) |p| {
                const f = p.booking.flight;
                try out.print("{s} {s} {s} {s} {s}\n", .{ f.name, p.booking.pnr, class_names[p.cabin], try f.displaySeat(self.gpa, p),
                    @as([]const u8, if (f.closed) "CLOSED" else "OPEN") });
            }
        } else {
            const f = try self.findFlight(a[1], false);
            const model = f.aircraft;
            if (std.mem.eql(u8, op, "MAP")) {
                try out.print("MAP {s}\n", .{f.name});
                for (model.cabins, 0..) |optional, c| {
                    const cabin = optional orelse continue;
                    try out.print("CABIN {s}\n   ", .{class_names[c]});
                    for (cabin.blocks, 0..) |block, b| {
                        if (b > 0) try out.writeByte(' ');
                        try out.writeAll(block);
                    }
                    try out.writeByte('\n');
                    for (cabin.first..cabin.last + 1) |row| {
                        try out.print("{d:>2} ", .{row});
                        for (cabin.blocks, 0..) |block, b| {
                            if (b > 0) try out.writeByte(' ');
                            for (block) |letter| {
                                const seat = model.grid[row][letter - 'A'].?;
                                try out.writeByte(if (f.blocked[seat]) '#' else if (f.occupied[seat] != null) 'X' else if (model.exits[row]) 'E' else '.');
                            }
                        }
                        try out.writeByte('\n');
                    }
                }
            } else if (std.mem.eql(u8, op, "MANIFEST")) {
                var seated: std.ArrayList(*Passenger) = .empty;
                var waiting: std.ArrayList(*Passenger) = .empty;
                var infants: usize = 0;
                for (try f.allPassengers(self.gpa)) |p| {
                    if (!p.needsSeat()) infants += 1 else if (p.seat == null) try waiting.append(self.gpa, p) else try seated.append(self.gpa, p);
                }
                std.mem.sort(*Passenger, seated.items, {}, seatLess);
                try out.print("MANIFEST {s} seated {d} unassigned {d} infants {d}\n", .{ f.name, seated.items.len, waiting.items.len, infants });
                try seated.appendSlice(self.gpa, waiting.items);
                for (seated.items) |p| {
                    try out.print("{s} {s} {s} {s} {s}", .{ if (p.seat == null) "---" else try f.displaySeat(self.gpa, p),
                        class_names[p.cabin], p.booking.pnr, p.name, @tagName(p.kind) });
                    if (p.carrying()) try out.print(" +{s}", .{p.infant.?.name});
                    if (self.tier(p.name) < 3) try out.print(" {s}", .{tier_names[self.tier(p.name)]});
                    if (p.booking.checked) try out.writeAll(" CHECKED");
                    if (std.mem.findScalar(*Passenger, f.volunteers.items, p) != null) try out.writeAll(" VOL");
                    try out.writeByte('\n');
                }
            } else if (std.mem.eql(u8, op, "LOADFACTOR")) {
                try out.print("LOADFACTOR {s}\n", .{f.name});
                var total_seated: usize = 0;
                var total_seats: usize = 0;
                for (model.cabins, 0..) |cabin, c| {
                    if (cabin == null) continue;
                    var seats: usize = 0;
                    var seated: usize = 0;
                    for (model.seats.items, 0..) |s, i| {
                        if (s.cabin == c and !f.blocked[i]) {
                            seats += 1;
                            if (f.occupied[i] != null) seated += 1;
                        }
                    }
                    total_seated += seated;
                    total_seats += seats;
                    try out.print("{s} {d}/{d} {d}.{d}% booked {d}/{d}\n", .{ class_names[c], seated, seats,
                        (seated * 1000 / seats) / 10, (seated * 1000 / seats) % 10, f.booked(c), f.limits[c] });
                }
                try out.print("ALL {d}/{d} {d}.{d}%\n", .{ total_seated, total_seats, (total_seated * 1000 / total_seats) / 10,
                    (total_seated * 1000 / total_seats) % 10 });
            } else if (std.mem.eql(u8, op, "BALANCE")) {
                var weight: i64 = 0;
                var moment: i64 = 0;
                for (try f.allPassengers(self.gpa)) |p| {
                    const seat = p.seat orelse continue;
                    const w: i64 = @as(i64, if (p.kind == .ADULT) 80 else 40) + @as(i64, if (p.carrying()) 10 else 0);
                    weight += w;
                    moment += w * (@as(i64, @intCast(model.seats.items[seat].row)) - @as(i64, @intCast(model.base)));
                }
                try out.print("BALANCE {s} weight {d} moment {d} limit {d} {s}\n", .{ f.name, weight, moment, model.limit,
                    @as([]const u8, if (moment < -model.limit) "NOSE-HEAVY" else if (moment > model.limit) "TAIL-HEAVY" else "OK") });
            } else if (std.mem.eql(u8, op, "AVAIL")) {
                const c = classIndex(a[2]);
                try self.hasCabin(f, c);
                var counts = [_]usize{ 0, 0, 0, 0, 0 };
                for (model.seats.items, 0..) |s, i| {
                    if (s.cabin != c or f.blocked[i] or f.occupied[i] != null) continue;
                    counts[0] += 1;
                    counts[1 + std.mem.findScalar(u8, "WMA", s.kind).?] += 1;
                    if (model.exits[s.row]) counts[4] += 1;
                }
                try out.print("AVAIL {s} {s} free {d} W {d} M {d} A {d} EXIT {d}\n", .{ f.name, class_names[c], counts[0], counts[1], counts[2], counts[3], counts[4] });
            } else if (std.mem.eql(u8, op, "BOARDING")) {
                const Entry = struct {
                    passenger: *Passenger,
                    key: [5]i64,

                    fn less(_: void, a: @This(), b: @This()) bool {
                        return std.mem.order(i64, &a.key, &b.key) == .lt;
                    }
                };
                var ordered: std.ArrayList(Entry) = .empty;
                for (try f.allPassengers(self.gpa)) |p| {
                    if (p.seat != null)
                        try ordered.append(self.gpa, .{ .passenger = p, .key = self.boardingKey(p) });
                }
                std.mem.sort(Entry, ordered.items, {}, Entry.less);
                try out.print("BOARDING {s} {d}\n", .{ f.name, ordered.items.len });
                for (ordered.items, 0..) |entry, i| {
                    const p = entry.passenger;
                    const key = entry.key;
                    const group = if (key[0] == 3) try std.fmt.allocPrint(self.gpa, "ZONE{d}", .{-key[1]}) else
                        ([_][]const u8{ "PRE", "CABIN", "TIER" })[@intCast(key[0])];
                    try out.print("{d} {s} {s} {s} {s}\n", .{ i + 1, group, try f.displaySeat(self.gpa, p), p.booking.pnr, p.name });
                }
            }
        }
    }
    fn boardingKey(self: *const Airline, p: *Passenger) [5]i64 {
        const model = p.booking.flight.aircraft;
        const s = model.seats.items[p.seat.?];
        const row: i64 = @intCast(s.row);
        if (p.booking.hasInfants()) return .{ 0, 0, row, 0, s.letter };
        if (p.cabin < 2) return .{ 1, 0, row, 0, s.letter };
        if (self.tier(p.name) < 2) return .{ 2, 0, row, 0, s.letter };
        const zone: i64 = @intCast((s.row - model.cabins[2].?.first) / 5 + 1);
        return .{ 3, -zone, @intCast(std.mem.findScalar(u8, "WMA", s.kind).?), -row, s.letter };
    }
};
fn tierLess(self: *const Airline, a: *Passenger, b: *Passenger) bool {
    return self.tier(a.name) < self.tier(b.name);
}
fn seatLess(_: void, a: *Passenger, b: *Passenger) bool {
    return a.seat.? < b.seat.?;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var airline = Airline{ .gpa = gpa };
    const count = integer((try input.interface.takeDelimiter('\n')).?);
    for (0..count) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        airline.execute(line, &draft.writer) catch |err| {
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{airline.error_buffer[0..airline.error_len]});
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
