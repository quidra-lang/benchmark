const std = @import("std");

const Allocator = std.mem.Allocator;

const Text = []const u8;

const Error = Allocator.Error || error{Invalid};
var failure: Text = "";

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}

fn number(text: Text) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}

fn timeValue(text: Text) usize {
    return number(text[0..2]) * 60 + number(text[3..5]);
}

fn timeText(gpa: Allocator, value: usize) Allocator.Error!Text {
    return std.fmt.allocPrint(gpa, "{d:0>2}:{d:0>2}", .{ value / 60, value % 60 });
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
};

fn textLess(_: void, a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn keys(gpa: Allocator, map: anytype) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, textLess);
    return result.items;
}

const Station = struct {
    id: Text,
    name: Text,
    index: usize,
    zone: usize,
    transfer: usize = 0,
    closed: bool = false,
    walks: std.StringHashMapUnmanaged(usize) = .empty,
};

const Direction = struct { stops: []const *Station, offsets: []const usize };

const Line = struct {
    id: Text,
    first: usize,
    last: usize,
    headway: usize,
    total: usize,
    stops: []const *Station,
    cumulative: []const usize,
    delay: usize = 0,
    suspended: bool = false,
    fn trains(self: *const Line) usize {
        return (self.last - self.first) / self.headway + 1;
    }
    fn firstTrain(self: *const Line, offset: usize, ready: usize) ?usize {
        const base = self.first + self.delay + offset;
        const q = if (ready > base) (ready - base + self.headway - 1) / self.headway else 0;
        return if (q < self.trains()) q else null;
    }
    fn time(self: *const Line, q: usize, offset: usize) usize {
        return self.first + self.delay + q * self.headway + offset;
    }
    fn direction(self: *const Line, gpa: Allocator, which: usize) Allocator.Error!Direction {
        if (which == 0) return .{ .stops = self.stops, .offsets = self.cumulative };
        const stops = try gpa.alloc(*Station, self.stops.len);
        const offsets = try gpa.alloc(usize, self.stops.len);
        for (stops, 0..) |*stop, i| {
            const j = stops.len - 1 - i;
            stop.* = self.stops[j];
            offsets[i] = self.total - self.cumulative[j];
        }
        return .{ .stops = stops, .offsets = offsets };
    }
};

const Kind = enum { ride, walk, stay };

const Leg = struct {
    kind: Kind,
    service: ?*Line = null,
    terminal: ?*Station = null,
    from: *Station,
    to: *Station,
    depart: usize,
    arrive: usize,
    stops: usize = 0,
};

const Label = struct { arrival: usize, journey: []const Leg };

const Labels = []?Label;

const Tariff = struct { discount: usize, window: usize, prices: []const usize };

const Departure = struct { time: usize, service: *Line, which: usize, terminal: *Station, start: *Station };

fn indexOf(stops: []const *Station, station: *Station) ?usize {
    for (stops, 0..) |candidate, i| if (candidate == station) return i;
    return null;
}

fn extend(gpa: Allocator, journey: []const Leg, leg: Leg) Allocator.Error![]const Leg {
    const result = try gpa.alloc(Leg, journey.len + 1);
    @memcpy(result[0..journey.len], journey);
    result[journey.len] = leg;
    return result;
}

fn improves(labels: Labels, target: *Station, arrival: usize) bool {
    return labels[target.index] == null or labels[target.index].?.arrival > arrival;
}

fn ride(service: *Line, d: Direction, a: usize, b: usize, depart: usize, arrive: usize) Leg {
    return .{ .kind = .ride, .service = service, .terminal = d.stops[d.stops.len - 1], .from = d.stops[a], .to = d.stops[b], .depart = depart, .arrive = arrive, .stops = b - a };
}

fn walk(a: *Station, b: *Station, depart: usize, arrive: usize) Leg {
    return .{ .kind = .walk, .from = a, .to = b, .depart = depart, .arrive = arrive };
}

fn counts(journey: []const Leg) struct { rides: usize, walks: usize } {
    var rides: usize = 0;
    var walks: usize = 0;
    for (journey) |leg| {
        if (leg.kind == .ride) rides += 1 else if (leg.kind == .walk) walks += 1;
    }
    return .{ .rides = rides, .walks = walks };
}

const Search = struct { arena: std.heap.ArenaAllocator, labels: Labels };

const Network = struct {
    gpa: Allocator,
    out: *Builder,
    stations: std.StringHashMapUnmanaged(*Station) = .empty,
    lines: std.StringHashMapUnmanaged(*Line) = .empty,
    closed: std.AutoHashMapUnmanaged(usize, void) = .empty,
    walk_count: usize = 0,
    tariff: ?Tariff = null,
    fn pair(a: *Station, b: *Station) usize {
        return @min(a.index, b.index) * 30 + @max(a.index, b.index);
    }
    fn blocked(self: *const Network, a: *Station, b: *Station) bool {
        return self.closed.contains(pair(a, b));
    }
    fn getStation(self: *Network, id: Text) Error!*Station {
        return self.stations.get(id) orelse return bad(self.gpa, "unknown station {s}", .{id});
    }
    fn getLine(self: *Network, id: Text) Error!*Line {
        return self.lines.get(id) orelse return bad(self.gpa, "unknown line {s}", .{id});
    }
    fn common(self: *Network, a: Text, b: Text) Error!struct { origin: *Station, destination: *Station } {
        const origin = try self.getStation(a);
        const destination = try self.getStation(b);
        if (origin == destination) return bad(self.gpa, "origin and destination are the same", .{});
        if (origin.closed) return bad(self.gpa, "station {s} is closed", .{a});
        if (destination.closed) return bad(self.gpa, "station {s} is closed", .{b});
        return .{ .origin = origin, .destination = destination };
    }
    fn earliest(self: *Network, gpa: Allocator, origin: *Station, start: usize) Allocator.Error!Labels {
        const labels = try gpa.alloc(?Label, self.stations.count());
        @memset(labels, null);
        labels[origin.index] = .{ .arrival = start, .journey = &.{} };
        const settled = try gpa.alloc(bool, labels.len);
        @memset(settled, false);
        const station_ids = try keys(gpa, self.stations);
        const service_ids = try keys(gpa, self.lines);
        while (true) {
            var selected: ?*Station = null;
            for (station_ids) |id| {
                const station = self.stations.get(id).?;
                if (!settled[station.index]) if (labels[station.index]) |value| {
                    if (selected == null or value.arrival < labels[selected.?.index].?.arrival) selected = station;
                };
            }
            const source = selected orelse return labels;
            settled[source.index] = true;
            const current = labels[source.index].?;
            const ready = current.arrival + if (source == origin) @as(usize, 0) else source.transfer;
            for (service_ids) |id| {
                const service = self.lines.get(id).?;
                if (service.suspended) continue;
                for (0..2) |which| {
                    const d = try service.direction(gpa, which);
                    const i = indexOf(d.stops, source) orelse continue;
                    if (i + 1 == d.stops.len) continue;
                    const q = service.firstTrain(d.offsets[i], ready) orelse continue;
                    const depart = service.time(q, d.offsets[i]);
                    for (i + 1..d.stops.len) |j| {
                        const target = d.stops[j];
                        if (self.blocked(d.stops[j - 1], target)) break;
                        if (target.closed) continue;
                        const arrival = service.time(q, d.offsets[j]);
                        if (improves(labels, target, arrival)) labels[target.index] = .{
                            .arrival = arrival,
                            .journey = try extend(gpa, current.journey, ride(service, d, i, j, depart, arrival)),
                        };
                    }
                }
            }
            for (try keys(gpa, source.walks)) |id| {
                const target = self.stations.get(id).?;
                const arrival = current.arrival + source.walks.get(id).?;
                if (!target.closed and arrival <= 1440 and improves(labels, target, arrival)) labels[target.index] = .{
                    .arrival = arrival,
                    .journey = try extend(gpa, current.journey, walk(source, target, current.arrival, arrival)),
                };
            }
        }
    }
    fn search(self: *Network, origin: *Station, start: usize) Allocator.Error!Search {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer arena.deinit();
        const labels = try self.earliest(arena.allocator(), origin, start);
        return .{ .arena = arena, .labels = labels };
    }
    fn walkStep(self: *Network, gpa: Allocator, labels: Labels, sources: []const bool, marked: []bool) Allocator.Error!void {
        const recorded = try gpa.dupe(?Label, labels);
        for (try keys(gpa, self.stations)) |id| {
            const source = self.stations.get(id).?;
            if (!sources[source.index]) continue;
            const current = recorded[source.index].?;
            for (try keys(gpa, source.walks)) |neighbor| {
                const target = self.stations.get(neighbor).?;
                const arrival = current.arrival + source.walks.get(neighbor).?;
                if (!target.closed and arrival <= 1440 and improves(labels, target, arrival)) {
                    labels[target.index] = .{ .arrival = arrival, .journey = try extend(gpa, current.journey, walk(source, target, current.arrival, arrival)) };
                    marked[target.index] = true;
                }
            }
        }
    }
    fn rounds(self: *Network, gpa: Allocator, origin: *Station, start: usize, stop: ?*Station) Allocator.Error![]Labels {
        var current = try gpa.alloc(?Label, self.stations.count());
        @memset(current, null);
        current[origin.index] = .{ .arrival = start, .journey = &.{} };
        var marked = try gpa.alloc(bool, current.len);
        @memset(marked, false);
        marked[origin.index] = true;
        const sources = try gpa.dupe(bool, marked);
        try self.walkStep(gpa, current, sources, marked);
        var result: std.ArrayList(Labels) = .empty;
        try result.append(gpa, current);
        const service_ids = try keys(gpa, self.lines);
        while (std.mem.findScalar(bool, marked, true) != null) {
            if (stop) |target| {
                if (current[target.index] != null) break;
            }
            const following = try gpa.dupe(?Label, current);
            const updated = try gpa.alloc(bool, current.len);
            const walking = try gpa.alloc(bool, current.len);
            @memset(updated, false);
            @memset(walking, false);
            for (service_ids) |id| {
                const service = self.lines.get(id).?;
                if (service.suspended) continue;
                for (0..2) |which| {
                    const d = try service.direction(gpa, which);
                    var boarded: ?usize = null;
                    var boarding: usize = 0;
                    var depart: usize = 0;
                    var prefix: []const Leg = &.{};
                    for (d.stops, 0..) |target, j| {
                        if (j > 0 and self.blocked(d.stops[j - 1], target)) boarded = null;
                        if (target.closed) continue;
                        if (boarded) |q| {
                            const arrival = service.time(q, d.offsets[j]);
                            if (improves(following, target, arrival)) {
                                following[target.index] = .{ .arrival = arrival, .journey = try extend(gpa, prefix, ride(service, d, boarding, j, depart, arrival)) };
                                walking[target.index] = true;
                                updated[target.index] = true;
                            }
                        }
                        if (j + 1 < d.stops.len and marked[target.index]) {
                            const previous = current[target.index].?;
                            const ready = previous.arrival + if (target == origin) @as(usize, 0) else target.transfer;
                            if (service.firstTrain(d.offsets[j], ready)) |candidate| {
                                if (boarded == null or candidate < boarded.?) {
                                    boarded = candidate;
                                    boarding = j;
                                    depart = service.time(candidate, d.offsets[j]);
                                    prefix = previous.journey;
                                }
                            }
                        }
                    }
                }
            }
            try self.walkStep(gpa, following, walking, updated);
            try result.append(gpa, following);
            current = following;
            marked = updated;
        }
        return result.items;
    }
    fn printJourney(self: *Network, scratch: Allocator, heading: Text, start: usize, result: Label) Allocator.Error!void {
        const count = counts(result.journey);
        try self.out.line("{s} {s} -> {s} total {d} rides {d} walks {d}", .{ heading, try timeText(scratch, start), try timeText(scratch, result.arrival), result.arrival - start, count.rides, count.walks });
        var previous = start;
        for (result.journey) |leg| {
            switch (leg.kind) {
                .ride => try self.out.line("RIDE {s} toward {s} {s} {s} -> {s} {s} wait {d} stops {d}", .{ leg.service.?.id, leg.terminal.?.id, leg.from.id, try timeText(scratch, leg.depart), leg.to.id, try timeText(scratch, leg.arrive), leg.depart - previous, leg.stops }),
                .walk => try self.out.line("WALK {s} {s} -> {s} {s}", .{ leg.from.id, try timeText(scratch, leg.depart), leg.to.id, try timeText(scratch, leg.arrive) }),
                .stay => try self.out.line("STAY {s} {s} -> {s}", .{ leg.from.id, try timeText(scratch, leg.depart), try timeText(scratch, leg.arrive) }),
            }
            previous = leg.arrive;
        }
    }
    fn segmentLines(self: *Network, gpa: Allocator, a: *Station, b: *Station) Allocator.Error![]Text {
        var result: std.ArrayList(Text) = .empty;
        for (try keys(gpa, self.lines)) |id| {
            const service = self.lines.get(id).?;
            for (1..service.stops.len) |i| {
                const x = service.stops[i - 1];
                const y = service.stops[i];
                if ((x == a and y == b) or (x == b and y == a)) {
                    try result.append(gpa, id);
                    break;
                }
            }
        }
        return result.items;
    }
    fn half(value: usize) usize {
        return (value + 19) / 20 * 10;
    }
    fn printFare(self: *Network, scratch: Allocator, origin: Text, destination: Text, start: usize, class: Text, result: Label) Allocator.Error!void {
        const Ticket = struct { leg: Leg, zones: usize, price: usize, discount: usize };
        var tickets: std.ArrayList(Ticket) = .empty;
        var total: usize = 0;
        var previous: ?usize = null;
        const tariff = self.tariff.?;
        for (result.journey) |leg| {
            if (leg.kind != .ride) continue;
            const service = leg.service.?;
            const a = indexOf(service.stops, leg.from).?;
            const b = indexOf(service.stops, leg.to).?;
            var zones: [10]bool = @splat(false);
            var zone_count: usize = 0;
            for (service.stops[@min(a, b) .. @max(a, b) + 1]) |station| {
                if (!zones[station.zone]) {
                    zones[station.zone] = true;
                    zone_count += 1;
                }
            }
            var price = tariff.prices[@min(zone_count, tariff.prices.len) - 1];
            var cap = tariff.discount;
            if (equal(class, "CHILD")) {
                price = half(price);
                cap = half(cap);
            }
            const discount = if (previous != null and leg.depart - previous.? <= tariff.window) @min(cap, price) else 0;
            total += price - discount;
            try tickets.append(scratch, .{ .leg = leg, .zones = zone_count, .price = price, .discount = discount });
            previous = leg.arrive;
        }
        try self.out.line("FARE {s} {s} {s} {s} rides {d} total {d}", .{ origin, destination, try timeText(scratch, start), class, tickets.items.len, total });
        for (tickets.items) |ticket| try self.out.line("TICKET {s} {s} {s} zones {d} price {d} discount {d} pay {d}", .{ ticket.leg.service.?.id, ticket.leg.from.id, ticket.leg.to.id, ticket.zones, ticket.price, ticket.discount, ticket.price - ticket.discount });
    }
    fn command(self: *Network, scratch: Allocator, w: []const Text) Error!void {
        const cmd = w[0];
        if (equal(cmd, "STATION")) {
            if (self.stations.contains(w[1])) return bad(self.gpa, "station {s} already exists", .{w[1]});
            const station = try self.gpa.create(Station);
            station.* = .{ .id = w[1], .zone = number(w[2]), .name = w[3], .index = self.stations.count() };
            try self.stations.put(self.gpa, station.id, station);
            try self.out.line("STATION {s} zone {s} {s}", .{ w[1], w[2], w[3] });
        } else if (equal(cmd, "LINE")) {
            if (self.lines.contains(w[1])) return bad(self.gpa, "line {s} already exists", .{w[1]});
            var stops: std.ArrayList(*Station) = .empty;
            var at: usize = 5;
            while (at < w.len) : (at += 2) try stops.append(self.gpa, try self.getStation(w[at]));
            for (stops.items, 0..) |station, i| {
                if (indexOf(stops.items[0..i], station) != null) return bad(self.gpa, "station {s} appears twice on line {s}", .{ station.id, w[1] });
            }
            const first = timeValue(w[2]);
            const last = timeValue(w[3]);
            if (first > last) return bad(self.gpa, "line {s} first departure is after last departure", .{w[1]});
            const cumulative = try self.gpa.alloc(usize, stops.items.len);
            cumulative[0] = 0;
            for (1..cumulative.len) |i| cumulative[i] = cumulative[i - 1] + number(w[4 + 2 * i]);
            const total = cumulative[cumulative.len - 1];
            if (last + total > 1440) return bad(self.gpa, "line {s} runs past 24:00", .{w[1]});
            const service = try self.gpa.create(Line);
            service.* = .{ .id = w[1], .first = first, .last = last, .headway = number(w[4]), .total = total, .stops = stops.items, .cumulative = cumulative };
            try self.lines.put(self.gpa, service.id, service);
            try self.out.line("LINE {s} stops {d} time {d} trips {d}", .{ service.id, service.stops.len, total, service.trains() });
        } else if (equal(cmd, "TRANSFER")) {
            const station = try self.getStation(w[1]);
            station.transfer = number(w[2]);
            try self.out.line("TRANSFER {s} {d}", .{ station.id, station.transfer });
        } else if (equal(cmd, "WALK")) {
            const a = try self.getStation(w[1]);
            const b = try self.getStation(w[2]);
            if (a == b) return bad(self.gpa, "walk from {s} to itself", .{a.id});
            const previous = a.walks.get(b.id);
            const minutes = number(w[3]);
            try a.walks.put(self.gpa, b.id, minutes);
            try b.walks.put(self.gpa, a.id, minutes);
            try self.out.print("WALK {s} {s} {d}", .{ a.id, b.id, minutes });
            if (previous) |old| try self.out.print(" was {d}", .{old}) else self.walk_count += 1;
            try self.out.add("\n");
        } else if (equal(cmd, "TARIFF")) {
            const prices = try self.gpa.alloc(usize, w.len - 3);
            for (w[3..], 0..) |word, i| {
                prices[i] = number(word);
                if (i > 0 and prices[i] < prices[i - 1]) return bad(self.gpa, "tariff prices must not decrease", .{});
            }
            self.tariff = .{ .discount = number(w[1]), .window = number(w[2]), .prices = prices };
            try self.out.line("TARIFF zones {d} discount {s} window {s}", .{ prices.len, w[1], w[2] });
        } else if (equal(cmd, "CLOSE") or equal(cmd, "OPEN")) {
            const a = try self.getStation(w[1]);
            const closing = equal(cmd, "CLOSE");
            if (w.len == 2) {
                if (closing and a.closed) return bad(self.gpa, "station {s} is already closed", .{a.id});
                if (!closing and !a.closed) return bad(self.gpa, "station {s} is not closed", .{a.id});
                a.closed = closing;
                try self.out.line("{s} {s}", .{ cmd, a.id });
            } else {
                const b = try self.getStation(w[2]);
                const key = pair(a, b);
                if (closing) {
                    const services = try self.segmentLines(scratch, a, b);
                    if (services.len == 0) return bad(self.gpa, "no segment {s}-{s}", .{ a.id, b.id });
                    if (self.closed.contains(key)) return bad(self.gpa, "segment {s}-{s} is already closed", .{ a.id, b.id });
                    try self.closed.put(self.gpa, key, {});
                    try self.out.print("CLOSE {s}-{s} lines", .{ a.id, b.id });
                    for (services) |id| try self.out.print(" {s}", .{id});
                    try self.out.add("\n");
                } else {
                    if (!self.closed.contains(key)) return bad(self.gpa, "segment {s}-{s} is not closed", .{ a.id, b.id });
                    _ = self.closed.remove(key);
                    try self.out.line("OPEN {s}-{s}", .{ a.id, b.id });
                }
            }
        } else if (equal(cmd, "DELAY") or equal(cmd, "SUSPEND") or equal(cmd, "RESUME")) {
            const service = try self.getLine(w[1]);
            if (equal(cmd, "DELAY")) {
                const minutes = number(w[2]);
                if (service.last + minutes + service.total > 1440) return bad(self.gpa, "line {s} runs past 24:00", .{service.id});
                service.delay = minutes;
                try self.out.line("DELAY {s} {d}", .{ service.id, minutes });
            } else {
                const suspending = equal(cmd, "SUSPEND");
                if (suspending and service.suspended) return bad(self.gpa, "line {s} is already suspended", .{service.id});
                if (!suspending and !service.suspended) return bad(self.gpa, "line {s} is not suspended", .{service.id});
                service.suspended = suspending;
                try self.out.line("{s} {s}", .{ cmd, service.id });
            }
        } else if (equal(cmd, "ROUTE") or equal(cmd, "FEWEST") or equal(cmd, "PARETO") or equal(cmd, "FARE") or
            equal(cmd, "LASTTRAIN") or equal(cmd, "ARRIVEBY") or equal(cmd, "PROFILE"))
        {
            const endpoints = try self.common(w[1], w[2]);
            const origin = endpoints.origin;
            const destination = endpoints.destination;
            if (equal(cmd, "FARE")) {
                if (!equal(w[4], "ADULT") and !equal(w[4], "CHILD")) return bad(self.gpa, "unknown fare class {s}", .{w[4]});
                if (self.tariff == null) return bad(self.gpa, "no tariff", .{});
            }
            const start = if (w.len > 3) timeValue(w[3]) else 0;
            if (equal(cmd, "PROFILE")) {
                const finish = timeValue(w[4]);
                if (start > finish) return bad(self.gpa, "empty interval {s} {s}", .{ w[3], w[4] });
                const arrivals = try scratch.alloc(?usize, finish - start + 1);
                for (arrivals, 0..) |*arrival, i| {
                    var found = try self.search(origin, start + i);
                    defer found.arena.deinit();
                    arrival.* = if (found.labels[destination.index]) |label| label.arrival else null;
                }
                var selected: std.ArrayList(usize) = .empty;
                for (arrivals, 0..) |arrival, i| {
                    if (arrival) |value| {
                        if (i + 1 == arrivals.len or arrivals[i + 1] == null or value < arrivals[i + 1].?) try selected.append(scratch, i);
                    }
                }
                try self.out.line("PROFILE {s} {s} {s} {s} count {d}", .{ origin.id, destination.id, w[3], w[4], selected.items.len });
                for (selected.items) |i| try self.out.line("{s} -> {s} total {d}", .{ try timeText(scratch, start + i), try timeText(scratch, arrivals[i].?), arrivals[i].? - start - i });
            } else if (equal(cmd, "LASTTRAIN") or equal(cmd, "ARRIVEBY")) {
                const last_train = equal(cmd, "LASTTRAIN");
                const heading = if (last_train) try std.fmt.allocPrint(scratch, "LASTTRAIN {s} {s}", .{ origin.id, destination.id }) else try std.fmt.allocPrint(scratch, "ARRIVEBY {s} {s} by {s}", .{ origin.id, destination.id, w[3] });
                var remaining: usize = if (last_train) 1440 else start;
                while (remaining > 0) {
                    remaining -= 1;
                    var found = try self.search(origin, remaining);
                    defer found.arena.deinit();
                    if (found.labels[destination.index]) |label| {
                        if (last_train or label.arrival <= start) {
                            try self.printJourney(scratch, heading, remaining, label);
                            return;
                        }
                    }
                }
                try self.out.line("{s} none", .{heading});
            } else if (equal(cmd, "FEWEST") or equal(cmd, "PARETO")) {
                const fewest = equal(cmd, "FEWEST");
                const results = try self.rounds(scratch, origin, start, if (fewest) destination else null);
                if (fewest) {
                    for (results, 0..) |labels, k| {
                        if (labels[destination.index]) |label| {
                            const heading = try std.fmt.allocPrint(scratch, "FEWEST {s} {s} trips {d}", .{ origin.id, destination.id, k });
                            try self.printJourney(scratch, heading, start, label);
                            return;
                        }
                    }
                    try self.out.line("FEWEST {s} {s} {s} unreachable", .{ origin.id, destination.id, w[3] });
                } else {
                    var options: std.ArrayList(usize) = .empty;
                    var previous: ?usize = null;
                    for (results, 0..) |labels, k| {
                        if (labels[destination.index]) |label| {
                            if (previous == null or label.arrival < previous.?) try options.append(scratch, k);
                            previous = label.arrival;
                        }
                    }
                    try self.out.line("PARETO {s} {s} {s} options {d}", .{ origin.id, destination.id, w[3], options.items.len });
                    for (options.items) |k| {
                        const heading = try std.fmt.allocPrint(scratch, "OPTION trips {d}", .{k});
                        try self.printJourney(scratch, heading, start, results[k][destination.index].?);
                    }
                }
            } else {
                var found = try self.search(origin, start);
                defer found.arena.deinit();
                if (found.labels[destination.index]) |label| {
                    if (equal(cmd, "FARE")) try self.printFare(scratch, origin.id, destination.id, start, w[4], label) else try self.printJourney(scratch, try std.fmt.allocPrint(scratch, "ROUTE {s} {s}", .{ origin.id, destination.id }), start, label);
                } else if (equal(cmd, "FARE")) try self.out.line("FARE {s} {s} {s} {s} unreachable", .{ origin.id, destination.id, w[3], w[4] }) else try self.out.line("ROUTE {s} {s} {s} unreachable", .{ origin.id, destination.id, w[3] });
            }
        } else if (equal(cmd, "VIA")) {
            const origin = try self.getStation(w[1]);
            const via = try self.getStation(w[2]);
            const destination = try self.getStation(w[3]);
            if (origin == destination) return bad(self.gpa, "origin and destination are the same", .{});
            if (via == origin or via == destination) return bad(self.gpa, "via station {s} must differ from origin and destination", .{via.id});
            for ([_]*Station{ origin, via, destination }) |station| {
                if (station.closed) return bad(self.gpa, "station {s} is closed", .{station.id});
            }
            const start = timeValue(w[4]);
            var first = try self.search(origin, start);
            defer first.arena.deinit();
            if (first.labels[via.index]) |first_label| {
                const ready = first_label.arrival + via.transfer;
                var second = try self.search(via, ready);
                defer second.arena.deinit();
                if (second.labels[destination.index]) |second_label| {
                    var journey: std.ArrayList(Leg) = .empty;
                    try journey.appendSlice(scratch, first_label.journey);
                    try journey.append(scratch, .{ .kind = .stay, .from = via, .to = via, .depart = first_label.arrival, .arrive = ready });
                    try journey.appendSlice(scratch, second_label.journey);
                    const heading = try std.fmt.allocPrint(scratch, "VIA {s} {s} {s}", .{ origin.id, via.id, destination.id });
                    try self.printJourney(scratch, heading, start, .{ .arrival = second_label.arrival, .journey = journey.items });
                    return;
                }
            }
            try self.out.line("VIA {s} {s} {s} {s} unreachable", .{ origin.id, via.id, destination.id, w[4] });
        } else if (equal(cmd, "REACH")) {
            const origin = try self.getStation(w[1]);
            if (origin.closed) return bad(self.gpa, "station {s} is closed", .{origin.id});
            const start = timeValue(w[2]);
            const duration = number(w[3]);
            var found = try self.search(origin, start);
            defer found.arena.deinit();
            var selected: std.ArrayList(*Station) = .empty;
            for (try keys(scratch, self.stations)) |id| {
                const station = self.stations.get(id).?;
                if (found.labels[station.index]) |label| {
                    if (label.arrival <= start + duration) try selected.append(scratch, station);
                }
            }
            const Less = struct {
                fn less(labels: Labels, a: *Station, b: *Station) bool {
                    const x = labels[a.index].?.arrival;
                    const y = labels[b.index].?.arrival;
                    return if (x != y) x < y else std.mem.order(u8, a.id, b.id) == .lt;
                }
            };
            std.mem.sort(*Station, selected.items, found.labels, Less.less);
            try self.out.line("REACH {s} {s} {d} count {d}", .{ origin.id, w[2], duration, selected.items.len });
            for (selected.items) |station| {
                const label = found.labels[station.index].?;
                try self.out.line("{s} {s} {s} {d} rides {d}", .{ station.id, station.name, try timeText(scratch, label.arrival), label.arrival - start, counts(label.journey).rides });
            }
        } else if (equal(cmd, "TIMETABLE")) {
            const station = try self.getStation(w[1]);
            const service = try self.getLine(w[2]);
            if (indexOf(service.stops, station) == null) return bad(self.gpa, "station {s} is not on line {s}", .{ station.id, service.id });
            const first = service.stops[0];
            const last = service.stops[service.stops.len - 1];
            if (!equal(w[3], first.id) and !equal(w[3], last.id)) return bad(self.gpa, "{s} is not a terminal of line {s}", .{ w[3], service.id });
            if (equal(station.id, w[3])) return bad(self.gpa, "no departures from {s} toward {s}", .{ station.id, w[3] });
            if (service.suspended) return bad(self.gpa, "line {s} is suspended", .{service.id});
            if (station.closed) return bad(self.gpa, "station {s} is closed", .{station.id});
            const d = try service.direction(scratch, if (equal(w[3], first.id)) 1 else 0);
            const at = indexOf(d.stops, station).?;
            const q = service.firstTrain(d.offsets[at], timeValue(w[4]));
            const count = if (q) |train| @min(number(w[5]), service.trains() - train) else 0;
            try self.out.print("TIMETABLE {s} {s} toward {s} {s} next {d}", .{ station.id, service.id, w[3], w[4], count });
            for (0..count) |i| try self.out.print(" {s}", .{try timeText(scratch, service.time(q.? + i, d.offsets[at]))});
            try self.out.add("\n");
        } else if (equal(cmd, "DEPARTURES") or equal(cmd, "ARRIVALS")) {
            const station = try self.getStation(w[1]);
            if (station.closed) return bad(self.gpa, "station {s} is closed", .{station.id});
            const departures = equal(cmd, "DEPARTURES");
            var choices: std.ArrayList(Departure) = .empty;
            for (try keys(scratch, self.lines)) |id| {
                const service = self.lines.get(id).?;
                if (service.suspended) continue;
                for (0..2) |which| {
                    const d = try service.direction(scratch, which);
                    const at = indexOf(d.stops, station) orelse continue;
                    if ((departures and at + 1 == d.stops.len) or (!departures and at == 0)) continue;
                    const q = service.firstTrain(d.offsets[at], timeValue(w[2])) orelse continue;
                    for (q..service.trains()) |train| try choices.append(scratch, .{ .time = service.time(train, d.offsets[at]), .service = service, .which = which, .terminal = d.stops[d.stops.len - 1], .start = d.stops[0] });
                }
            }
            const Less = struct {
                fn less(_: void, a: Departure, b: Departure) bool {
                    if (a.time != b.time) return a.time < b.time;
                    if (!equal(a.service.id, b.service.id)) return std.mem.order(u8, a.service.id, b.service.id) == .lt;
                    return a.which < b.which;
                }
            };
            std.mem.sort(Departure, choices.items, {}, Less.less);
            const count = @min(choices.items.len, number(w[3]));
            try self.out.line("{s} {s} {s} count {d}", .{ cmd, station.id, w[2], count });
            for (choices.items[0..count]) |choice| try self.out.line("{s} {s} {s} {s}", .{ try timeText(scratch, choice.time), choice.service.id, if (departures) @as(Text, "toward") else "from", if (departures) choice.terminal.id else choice.start.id });
        } else if (equal(cmd, "TRIP") or equal(cmd, "SHOWLINE")) {
            const service = try self.getLine(w[1]);
            if (equal(cmd, "SHOWLINE")) {
                try self.out.line("SHOWLINE {s} {s} first {s} last {s} headway {d} delay {d} trips {d}", .{ service.id, if (service.suspended) @as(Text, "suspended") else "running", try timeText(scratch, service.first), try timeText(scratch, service.last), service.headway, service.delay, service.trains() });
                for (service.stops, 0..) |station, i| {
                    try self.out.print("{d} {s} zone {d}", .{ service.cumulative[i], station.id, station.zone });
                    if (station.closed) try self.out.add(" closed");
                    if (i > 0 and self.blocked(service.stops[i - 1], station)) try self.out.add(" blocked");
                    try self.out.add("\n");
                }
            } else {
                const first = service.stops[0];
                const last = service.stops[service.stops.len - 1];
                if (!equal(w[2], first.id) and !equal(w[2], last.id)) return bad(self.gpa, "{s} is not a terminal of line {s}", .{ w[2], service.id });
                if (service.suspended) return bad(self.gpa, "line {s} is suspended", .{service.id});
                const d = try service.direction(scratch, if (equal(w[2], first.id)) 1 else 0);
                const q = service.firstTrain(0, timeValue(w[3])) orelse {
                    try self.out.line("TRIP {s} toward {s} {s} none", .{ service.id, w[2], w[3] });
                    return;
                };
                try self.out.line("TRIP {s} toward {s} {s} trip {d} departs {s}", .{ service.id, w[2], w[3], q + 1, try timeText(scratch, service.time(q, 0)) });
                for (d.stops, 0..) |station, i| {
                    try self.out.print("{s} {s}", .{ try timeText(scratch, service.time(q, d.offsets[i])), station.id });
                    if (station.closed) try self.out.add(" closed");
                    if (i > 0 and self.blocked(d.stops[i - 1], station)) try self.out.add(" blocked");
                    try self.out.add("\n");
                }
            }
        } else if (equal(cmd, "INFO")) {
            const station = try self.getStation(w[1]);
            try self.out.line("INFO {s} {s} zone {d} transfer {d} {s}", .{ station.id, station.name, station.zone, station.transfer, if (station.closed) @as(Text, "closed") else "open" });
            try self.out.add("LINES");
            var count: usize = 0;
            for (try keys(scratch, self.lines)) |id| {
                if (indexOf(self.lines.get(id).?.stops, station) != null) {
                    try self.out.print(" {s}", .{id});
                    count += 1;
                }
            }
            if (count == 0) try self.out.add(" none");
            try self.out.add("\nWALKS");
            const walks = try keys(scratch, station.walks);
            if (walks.len == 0) try self.out.add(" none");
            for (walks) |id| try self.out.print(" {s} {d}", .{ id, station.walks.get(id).? });
            try self.out.add("\n");
        } else if (equal(cmd, "STATUS")) {
            const station_ids = try keys(scratch, self.stations);
            const service_ids = try keys(scratch, self.lines);
            try self.out.line("STATUS stations {d} lines {d} walks {d}", .{ self.stations.count(), self.lines.count(), self.walk_count });
            for (station_ids) |id| {
                if (self.stations.get(id).?.closed) try self.out.line("CLOSED {s}", .{id});
            }
            for (station_ids, 0..) |a, i| {
                for (station_ids[i + 1 ..]) |b| {
                    if (self.blocked(self.stations.get(a).?, self.stations.get(b).?)) try self.out.line("CLOSED {s}-{s}", .{ a, b });
                }
            }
            for (service_ids) |id| {
                if (self.lines.get(id).?.suspended) try self.out.line("SUSPENDED {s}", .{id});
            }
            for (service_ids) |id| {
                const delay = self.lines.get(id).?.delay;
                if (delay != 0) try self.out.line("DELAYED {s} {d}", .{ id, delay });
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input_reader = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const input = try input_reader.interface.allocRemaining(gpa, .unlimited);
    var input_lines = std.mem.splitScalar(u8, input, '\n');
    const count = number(input_lines.next().?);
    var out: Builder = .{ .gpa = gpa };
    var network: Network = .{ .gpa = gpa, .out = &out };
    for (0..count) |_| {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();
        var words: std.ArrayList(Text) = .empty;
        var iterator = std.mem.splitScalar(u8, input_lines.next().?, ' ');
        while (iterator.next()) |word| try words.append(scratch, word);
        network.command(scratch, words.items) catch |err| switch (err) {
            error.Invalid => try out.line("ERROR {s}", .{failure}),
            else => return err,
        };
    }
    var output_buffer: [8192]u8 = undefined;
    var output_writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try output_writer.interface.writeAll(out.bytes.items);
    try output_writer.interface.flush();
}
