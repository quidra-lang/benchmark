const std = @import("std");
const Text = []const u8;
const I = i64;
const policies = [_]Text{ "COST", "NEAREST", "ROUND", "ETA" };
const keys = [_]Text{ "FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE" };
const commands = [_]Text{ "CALL", "CANCEL", "OUT", "IN", "HOLD", "FIRE", "RESET", "WHERE", "STATUS" };
const Line = struct {
    number: usize,
    words: []const Text,
};
const Config = struct {
    floors: I = 0,
    count: usize = 0,
    capacity: I = 0,
    door: I = 0,
    starts: [8]I = @splat(0),
    lows: [8]I = @splat(0),
    highs: [8]I = @splat(0),
    homes: [8]I = @splat(0),
    policy: usize = 0,
    park: I = -1,
    patience: I = -1,
    bypass: I = 100,
    period: I = -1,
    limit: I = 1000,
    compare: [4]usize = undefined,
    comparisons: usize = 0,

    fn serves(c: Config, car: usize, a: I, b: I) bool {
        return bounded(a, c.lows[car], c.highs[car]) and bounded(b, c.lows[car], c.highs[car]);
    }
};
const Event = struct {
    time: I,
    command: usize,
    a: I = 0,
    b: I = 0,
    c: I = 0,
};
const Group = struct {
    time: I = 0,
    landing: I = 0,
    destination: I = 0,
    count: I = 0,
    waiting: I = 0,
    car: ?usize = null,
    boarded: I = 0,
    delivered: I = 0,
    lost: I = 0,
    last_board: I = 0,
    last_alight: I = 0,
    cars: [8]bool = @splat(false),
    wait_total: I = 0,
    travel_total: I = 0,
};
const Passenger = struct {
    group: usize,
    count: I,
    time: I,
};
const List = struct {
    ids: [1000]usize = undefined,
    count: usize = 0,

    fn add(list: *List, id: usize) void {
        list.ids[list.count] = id;
        list.count += 1;
    }

    fn remove(list: *List, id: usize) void {
        for (list.ids[0..list.count], 0..) |item, i| if (item == id) {
            for (i + 1..list.count) |j| list.ids[j - 1] = list.ids[j];
            list.count -= 1;
            return;
        };
    }
};
const Car = struct {
    floor: I = 0,
    direction: I = 0,
    door: I = 0,
    service: bool = true,
    idle_start: I = 0,
    calls: List = .{},
    passengers: [20]Passenger = undefined,
    riding: usize = 0,
    distance: I = 0,
    stops: I = 0,
    boarded: I = 0,
    busy: I = 0,
    energy: I = 0,

    fn load(car: *const Car) I {
        var total: I = 0;
        for (car.passengers[0..car.riding]) |entry| total += entry.count;
        return total;
    }
};
const Result = struct {
    name: Text = "",
    valid: bool = false,
    aborted: bool = false,
    policy: usize = 0,
    delivered: I = 0,
    wait_total: I = 0,
    travel_total: I = 0,
    max_wait: I = 0,
};

fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn number(s: Text) I {
    return std.fmt.parseInt(I, s, 10) catch unreachable;
}

fn index(value: I) usize {
    return @intCast(value);
}

fn bounded(value: I, low: I, high: I) bool {
    return low <= value and value <= high;
}

fn sign(value: I) I {
    return if (value > 0) 1 else if (value < 0) -1 else 0;
}

fn absolute(value: I) I {
    return if (value < 0) -value else value;
}

fn lookup(value: Text, names: []const Text) ?usize {
    for (names, 0..) |name, i| if (eq(value, name)) return i;
    return null;
}

fn before(a: Result, b: Result) bool {
    const left = a.wait_total * b.delivered;
    const right = b.wait_total * a.delivered;
    return if (left != right) left < right else a.travel_total * b.delivered < b.travel_total * a.delivered;
}
const Host = struct {
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,

    fn text(h: *Host, comptime format: Text, args: anytype) !Text {
        return std.fmt.allocPrint(h.gpa, format, args);
    }

    fn line(h: *Host, comptime format: Text, args: anytype) !void {
        try h.out.print(format ++ "\n", args);
    }

    fn average(h: *Host, total: I, count: I) !Text {
        if (count == 0) return "-";
        const value = @divTrunc(total * 100, count);
        return h.text("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
    }

    fn optional(h: *Host, value: I, missing: Text) !Text {
        return if (value < 0) missing else try h.text("{d}", .{value});
    }

    fn averages(h: *Host, delivered: I, wait_total: I, travel_total: I, max_wait: I) !Text {
        return h.text("avg_wait={s} avg_travel={s} max_wait={s}", .{ try h.average(wait_total, delivered), try h.average(travel_total, delivered), if (delivered == 0) "-" else try h.text("{d}", .{max_wait}) });
    }

    fn groupList(h: *Host, list: List) !Text {
        if (list.count == 0) return "-";
        var buffer: std.Io.Writer.Allocating = .init(h.gpa);
        for (list.ids[0..list.count], 0..) |id, i| try buffer.writer.print("{s}G{d}", .{ if (i == 0) "" else ",", id + 1 });
        return buffer.toOwnedSlice();
    }

    fn configuration(h: *Host, lines: []const Line, c: *Config) !?Text {
        var found: [13]?Line = @splat(null);
        for (lines) |source| {
            const key = lookup(source.words[0], &keys) orelse return try h.text("unknown key {s}", .{source.words[0]});
            if (found[key] != null) return try h.text("duplicate key {s}", .{keys[key]});
            found[key] = source;
        }
        for (0..5) |key| if (found[key] == null) return try h.text("missing key {s}", .{keys[key]});
        for (found, 0..) |entry, key| {
            const source = entry orelse continue;
            const words = source.words[1..];
            const n = words.len;
            const valid_count = if (key == 4 or key == 6) n == c.count else if (key == 7) n == c.count + 1 else if (key == 12) n >= 1 and n <= 4 else n == 1;
            if (!valid_count) return try h.text("wrong number of values for {s}", .{keys[key]});
            var valid = true;
            switch (key) {
                0 => {
                    c.floors = number(words[0]);
                    valid = bounded(c.floors, 2, 50);
                },
                1 => {
                    const value = number(words[0]);
                    valid = bounded(value, 1, 8);
                    if (valid) c.count = index(value);
                },
                2 => {
                    c.capacity = number(words[0]);
                    valid = bounded(c.capacity, 1, 20);
                },
                3 => {
                    c.door = number(words[0]);
                    valid = bounded(c.door, 1, 9);
                },
                4 => for (words, 0..) |word, i| {
                    c.starts[i] = number(word);
                    valid = valid and bounded(c.starts[i], 1, c.floors);
                },
                5 => {
                    if (lookup(words[0], &policies)) |policy| c.policy = policy else valid = false;
                },
                6 => for (words, 0..) |word, i| {
                    const split = std.mem.findScalar(u8, word, ':').?;
                    c.lows[i] = number(word[0..split]);
                    c.highs[i] = number(word[split + 1..]);
                    valid = valid and c.lows[i] >= 1 and c.lows[i] < c.highs[i] and c.highs[i] <= c.floors;
                },
                7 => {
                    c.park = number(words[0]);
                    valid = bounded(c.park, 0, 100);
                    for (words[1..], 0..) |word, i| {
                        c.homes[i] = number(word);
                        valid = valid and bounded(c.homes[i], 1, c.floors);
                    }
                },
                8 => {
                    c.patience = number(words[0]);
                    valid = bounded(c.patience, 1, 1000);
                },
                9 => {
                    c.bypass = number(words[0]);
                    valid = bounded(c.bypass, 50, 100);
                },
                10 => {
                    c.period = number(words[0]);
                    valid = bounded(c.period, 1, 1000);
                },
                11 => {
                    c.limit = number(words[0]);
                    valid = bounded(c.limit, 1, 5000);
                },
                12 => {
                    c.comparisons = n;
                    var seen: [4]bool = @splat(false);
                    for (words, 0..) |word, i| {
                        if (lookup(word, &policies)) |policy| {
                            if (seen[policy]) valid = false;
                            seen[policy] = true;
                            c.compare[i] = policy;
                        } else valid = false;
                    }
                },
                else => unreachable,
            }
            if (!valid) return try h.text("bad value for {s}", .{keys[key]});
        }
        if (found[6] == null) for (0..c.count) |i| {
            c.lows[i] = 1;
            c.highs[i] = c.floors;
        };
        for (0..c.count) |i| {
            if (!bounded(c.starts[i], c.lows[i], c.highs[i])) return try h.text("car {d} starts outside its zone", .{i + 1});
            if (c.park >= 0 and !bounded(c.homes[i], c.lows[i], c.highs[i])) return try h.text("car {d} home outside its zone", .{i + 1});
        }
        return null;
    }

    fn eventProblem(h: *Host, c: Config, source: Line, last: I, groups: I, fire: bool, out: [8]bool) !?Text {
        const words = source.words;
        const command = lookup(words[1], &commands) orelse return try h.text("unknown command {s}", .{words[1]});
        const counts = [_]usize{ 3, 1, 1, 1, 2, 1, 0, 1, 0 };
        if (words.len - 2 != counts[command]) return try h.text("wrong number of arguments for {s}", .{words[1]});
        if (number(words[0]) < last) return "time goes backwards";
        const a = if (words.len > 2) number(words[2]) else 0;
        const b = if (words.len > 3) number(words[3]) else 0;
        switch (command) {
            0 => {
                if (!bounded(a, 1, c.floors) or !bounded(b, 1, c.floors)) return "bad floor";
                if (a == b) return "same floor";
                if (!bounded(number(words[4]), 1, 99)) return "bad count";
                var served = false;
                for (0..c.count) |car| served = served or c.serves(car, a, b);
                if (!served) return try h.text("no car serves {d}->{d}", .{ a, b });
                if (fire) return "fire service active";
            },
            1, 7 => if (!bounded(a, 1, groups)) {
                return "unknown group";
            },
            2, 3 => {
                if (!bounded(a, 1, @intCast(c.count))) return "bad car";
                if (out[index(a - 1)] == (command == 2)) return try h.text("car {d} already {s}", .{ a, if (command == 2) "out" else "in" });
            },
            4 => {
                if (!bounded(a, 1, @intCast(c.count))) return "bad car";
                if (!bounded(b, 1, 9)) return "bad ticks";
            },
            5 => {
                if (!bounded(a, 1, c.floors)) return "bad floor";
                if (fire) return "fire already active";
            },
            6 => if (!fire) {
                return "fire not active";
            },
            else => {},
        }
        return null;
    }

    fn validateEvents(h: *Host, c: Config, lines: []const Line) ![]Event {
        var result: std.ArrayList(Event) = .empty;
        var last: I = 0;
        var groups: I = 0;
        var fire = false;
        var out: [8]bool = @splat(false);
        for (lines) |source| {
            if (try h.eventProblem(c, source, last, groups, fire, out)) |problem| {
                try h.line("line {d}: {s}", .{ source.number, problem });
                continue;
            }
            const w = source.words;
            const command = lookup(w[1], &commands).?;
            const a = if (w.len > 2) number(w[2]) else 0;
            const b = if (w.len > 3) number(w[3]) else 0;
            const value = if (w.len > 4) number(w[4]) else 0;
            last = number(w[0]);
            if (command == 0) groups += 1;
            if (command == 2 or command == 3) out[index(a - 1)] = command == 2;
            if (command == 5 or command == 6) fire = command == 5;
            try result.append(h.gpa, .{ .time = last, .command = command, .a = a, .b = b, .c = value });
        }
        return result.items;
    }

    fn configLines(h: *Host, c: Config) !void {
        var compare: std.Io.Writer.Allocating = .init(h.gpa);
        for (c.compare[0..c.comparisons], 0..) |policy, i| try compare.writer.print("{s}{s}", .{ if (i == 0) "" else ",", policies[policy] });
        try h.line("config: floors={d} cars={d} capacity={d} door={d} policy={s} park={s} patience={s} bypass={d} period={s} limit={d} compare={s}", .{ c.floors, c.count, c.capacity, c.door, policies[c.policy], try h.optional(c.park, "off"), try h.optional(c.patience, "off"), c.bypass, try h.optional(c.period, "off"), c.limit, if (c.comparisons == 0) "-" else compare.written() });
        for (0..c.count) |i| try h.line("E{d}: start={d} zone={d}-{d} home={s}", .{ i + 1, c.starts[i], c.lows[i], c.highs[i], if (c.park < 0) "-" else try h.text("{d}", .{c.homes[i]}) });
    }

    fn simulate(h: *Host, c: Config, events: []const Event, policy: usize, logging: bool) !*Simulation {
        const simulation = try std.heap.page_allocator.create(Simulation);
        simulation.* = .{ .host = h, .config = c, .policy = policy, .logging = logging };
        for (0..c.count) |i| simulation.cars[i].floor = c.starts[i];
        try simulation.run(events);
        return simulation;
    }
};
const Simulation = struct {
    host: *Host,
    config: Config,
    policy: usize,
    logging: bool,
    groups: [1000]Group = @splat(.{}),
    ng: usize = 0,
    cars: [8]Car = @splat(.{}),
    pending: List = .{},
    fire: I = 0,
    last_round: usize = 0,
    time: I = 0,
    aborted: bool = false,
    delivered: I = 0,
    abandoned: I = 0,
    evacuated: I = 0,
    wait_total: I = 0,
    travel_total: I = 0,
    max_wait: I = 0,

    fn emit(s: *Simulation, comptime format: Text, args: anytype) !void {
        if (s.logging) {
            try s.host.out.print("{d} ", .{s.time});
            try s.host.line(format, args);
        }
    }

    fn targets(s: *Simulation, i: usize) [51]bool {
        var floors: [51]bool = @splat(false);
        const car = &s.cars[i];
        for (car.passengers[0..car.riding]) |entry| floors[index(s.groups[entry.group].destination)] = true;
        for (car.calls.ids[0..car.calls.count]) |group| floors[index(s.groups[group].landing)] = true;
        return floors;
    }

    fn bypassing(s: *Simulation, i: usize) bool {
        return s.cars[i].load() * 100 >= s.config.capacity * s.config.bypass;
    }

    fn cost(s: *Simulation, i: usize, group_index: usize) I {
        const car = &s.cars[i];
        const group = s.groups[group_index];
        const f = car.floor;
        const d = car.direction;
        const x = group.landing;
        if (s.policy == 1 or d == 0) return absolute(f - x);
        const floors = s.targets(i);
        var distance: I = 0;
        var via: I = 0;
        if (sign(group.destination - x) == d and (x - f) * d >= 0) {
            distance = absolute(x - f);
            for (1..index(s.config.floors) + 1) |target| {
                const y: I = @intCast(target);
                if (floors[target] and (y - f) * d > 0 and (x - y) * d > 0) via += 1;
            }
        } else {
            var turn = f;
            for (1..index(s.config.floors) + 1) |target| {
                const y: I = @intCast(target);
                if (floors[target]) {
                    if ((y - turn) * d > 0) turn = y;
                    if ((y - f) * d > 0) via += 1;
                }
            }
            distance = absolute(f - turn) + absolute(turn - x);
        }
        return if (s.policy == 3) distance + s.config.door * via + car.door else distance;
    }

    fn assign(s: *Simulation, group_index: usize, exclude: ?usize) !bool {
        const group = &s.groups[group_index];
        var selected: ?usize = null;
        var best_cost: I = 0;
        for (0..s.config.count) |i| {
            if ((exclude != null and exclude.? == i) or !s.cars[i].service or !s.config.serves(i, group.landing, group.destination)) continue;
            if (s.policy == 2) {
                if (selected == null) selected = i;
                if (i + 1 > s.last_round) {
                    selected = i;
                    break;
                }
            } else {
                const value = s.cost(i, group_index);
                if (selected == null or value < best_cost) {
                    selected = i;
                    best_cost = value;
                }
            }
        }
        const chosen = selected orelse return false;
        if (s.policy == 2) {
            s.last_round = chosen + 1;
            try s.emit("E{d} ASSIGN G{d}", .{ chosen + 1, group_index + 1 });
        } else try s.emit("E{d} ASSIGN G{d} cost={d}", .{ chosen + 1, group_index + 1, best_cost });
        if (group.car) |old| s.cars[old].calls.remove(group_index);
        s.cars[chosen].calls.add(group_index);
        group.car = chosen;
        return true;
    }

    fn dispatch(s: *Simulation, group: usize) !void {
        if (!try s.assign(group, null)) {
            s.pending.add(group);
            try s.emit("PENDING G{d}", .{group + 1});
        }
    }

    fn walk(s: *Simulation, i: usize, word: Text) !void {
        const group = &s.groups[i];
        if (group.car) |car| s.cars[car].calls.remove(i) else s.pending.remove(i);
        group.car = null;
        try s.emit("{s} G{d} x{d}", .{ word, i + 1, group.waiting });
        s.abandoned += group.waiting;
        group.lost += group.waiting;
        group.waiting = 0;
    }

    fn perform(s: *Simulation, event: Event) !void {
        const a = event.a;
        const b = event.b;
        switch (event.command) {
            0 => {
                const i = s.ng;
                s.ng += 1;
                s.groups[i] = .{ .time = s.time, .landing = a, .destination = b, .count = event.c, .waiting = event.c };
                try s.emit("CALL G{d} {d}->{d} x{d}", .{ i + 1, a, b, event.c });
                try s.dispatch(i);
            },
            1 => {
                if (s.groups[index(a - 1)].waiting > 0) try s.walk(index(a - 1), "CANCEL") else try s.emit("CANCEL G{d} ignored", .{a});
            },
            2 => {
                const car = &s.cars[index(a - 1)];
                car.service = false;
                try s.emit("E{d} OUT", .{a});
                const calls = car.calls;
                car.calls.count = 0;
                for (calls.ids[0..calls.count]) |i| {
                    s.groups[i].car = null;
                    try s.dispatch(i);
                }
            },
            3 => {
                const car = &s.cars[index(a - 1)];
                car.service = true;
                car.idle_start = s.time;
                try s.emit("E{d} IN", .{a});
                const pending = s.pending;
                s.pending.count = 0;
                for (pending.ids[0..pending.count]) |i| if (!try s.assign(i, null)) s.pending.add(i);
            },
            4 => {
                const car = &s.cars[index(a - 1)];
                if (car.door > 0) {
                    car.door += b;
                    try s.emit("E{d} HOLD {d}", .{ a, car.door });
                } else try s.emit("E{d} HOLD ignored", .{a});
            },
            5 => {
                s.fire = a;
                try s.emit("FIRE {d}", .{a});
                for (0..s.ng) |i| if (s.groups[i].waiting > 0) {
                    try s.walk(i, "ABANDON");
                };
            },
            6 => {
                s.fire = 0;
                try s.emit("RESET", .{});
                for (s.cars[0..s.config.count]) |*car| car.idle_start = s.time;
            },
            7 => {
                const group = s.groups[index(a - 1)];
                const place = if (group.waiting == 0) "-" else if (group.car) |car| try s.host.text("E{d}", .{car + 1}) else "pending";
                var riding: std.Io.Writer.Allocating = .init(s.host.gpa);
                var first = true;
                for (s.cars[0..s.config.count], 0..) |car, i| {
                    var people: I = 0;
                    for (car.passengers[0..car.riding]) |entry| if (entry.group == index(a - 1)) {
                        people += entry.count;
                    };
                    if (people > 0) {
                        try riding.writer.print("{s}E{d}x{d}", .{ if (first) "" else ",", i + 1, people });
                        first = false;
                    }
                }
                try s.emit("WHERE G{d} waiting={d} car={s} riding={s} delivered={d} lost={d}", .{ a, group.waiting, place, if (first) "-" else riding.written(), group.delivered, group.lost });
            },
            8 => {
                for (s.cars[0..s.config.count], 0..) |car, i| {
                    var floors: [51]bool = @splat(false);
                    for (car.passengers[0..car.riding]) |entry| floors[index(s.groups[entry.group].destination)] = true;
                    var stops: std.Io.Writer.Allocating = .init(s.host.gpa);
                    var first = true;
                    for (1..index(s.config.floors) + 1) |floor| if (floors[floor]) {
                        try stops.writer.print("{s}{d}", .{ if (first) "" else ",", floor });
                        first = false;
                    };
                    try s.emit("STATUS E{d} floor={d} dir={s} door={d} load={d} stops={s} calls={s} service={s}", .{ i + 1, car.floor, if (car.direction > 0) "up" else if (car.direction < 0) "down" else "idle", car.door, car.load(), if (first) "-" else stops.written(), try s.host.groupList(car.calls), if (car.service) "in" else "out" });
                }
                try s.emit("STATUS pending={s}", .{try s.host.groupList(s.pending)});
            },
            else => unreachable,
        }
    }

    fn direction(s: *Simulation, i: usize) I {
        const car = &s.cars[i];
        const f = car.floor;
        const d = car.direction;
        const floors = s.targets(i);
        var ahead = false;
        var behind = false;
        var first: ?usize = null;
        var same = false;
        for (1..index(s.config.floors) + 1) |target| {
            const y: I = @intCast(target);
            if (floors[target]) {
                ahead = ahead or (y - f) * d > 0;
                behind = behind or (y - f) * d < 0;
            }
        }
        if (!s.bypassing(i)) for (car.calls.ids[0..car.calls.count]) |g| {
            const group = s.groups[g];
            if (group.landing == f) {
                if (first == null) first = g;
                same = same or sign(group.destination - group.landing) == d;
            }
        };
        if (d != 0 and (ahead or same)) return d;
        if (first) |g| return sign(s.groups[g].destination - f);
        if (d != 0 and behind) return -d;
        if (d == 0 and car.calls.count > 0) return sign(s.groups[car.calls.ids[0]].landing - f);
        return 0;
    }

    fn move(s: *Simulation, i: usize, step: I) void {
        const car = &s.cars[i];
        car.energy += if (step > 0) 3 + car.load() else 1;
        car.distance += 1;
        car.floor += step;
    }

    fn openDoors(s: *Simulation, i: usize) !void {
        const car = &s.cars[i];
        const f = car.floor;
        try s.emit("E{d} OPEN {d}", .{ i + 1, f });
        car.door = s.config.door;
        car.stops += 1;
        car.energy += 2;
        var kept: usize = 0;
        for (car.passengers[0..car.riding]) |entry| {
            const group = &s.groups[entry.group];
            if (group.destination == f) {
                try s.emit("E{d} ALIGHT G{d} x{d}", .{ i + 1, entry.group + 1, entry.count });
                const wait = entry.time - group.time;
                const travel = s.time - group.time;
                group.delivered += entry.count;
                group.last_alight = s.time;
                group.wait_total += wait * entry.count;
                group.travel_total += travel * entry.count;
                s.delivered += entry.count;
                s.wait_total += wait * entry.count;
                s.travel_total += travel * entry.count;
                s.max_wait = @max(s.max_wait, wait);
            } else if (s.fire > 0) {
                try s.emit("E{d} EVACUATE G{d} x{d}", .{ i + 1, entry.group + 1, entry.count });
                group.lost += entry.count;
                s.evacuated += entry.count;
            } else {
                car.passengers[kept] = entry;
                kept += 1;
            }
        }
        car.riding = kept;
        if (s.fire > 0) return;
        const heading = s.direction(i);
        if (heading != 0) car.direction = heading;
        var boarding: List = .{};
        for (car.calls.ids[0..car.calls.count]) |g| {
            const group = s.groups[g];
            if (group.landing == f and sign(group.destination - group.landing) == heading) boarding.add(g);
        }
        for (boarding.ids[0..boarding.count]) |g| {
            const group = &s.groups[g];
            const people = @min(s.config.capacity - car.load(), group.waiting);
            if (people > 0) {
                car.passengers[car.riding] = .{ .group = g, .count = people, .time = s.time };
                car.riding += 1;
                car.boarded += people;
                group.waiting -= people;
                group.boarded += people;
                group.last_board = s.time;
                group.cars[i] = true;
                try s.emit("E{d} BOARD G{d} x{d}", .{ i + 1, g + 1, people });
            }
            if (group.waiting == 0) {
                car.calls.remove(g);
                group.car = null;
            } else {
                try s.emit("E{d} LEFT G{d} x{d}", .{ i + 1, g + 1, group.waiting });
                _ = try s.assign(g, i);
            }
        }
    }

    fn advance(s: *Simulation, i: usize) !void {
        const car = &s.cars[i];
        const old = car.floor;
        if (car.door > 0) car.door -= 1;
        if (car.door == 0) {
            const heading = if (s.fire > 0) sign(s.fire - car.floor) else s.direction(i);
            var stop = s.fire > 0 and heading == 0 and car.riding > 0;
            if (s.fire == 0) {
                for (car.passengers[0..car.riding]) |entry| stop = stop or s.groups[entry.group].destination == car.floor;
                if (!s.bypassing(i)) for (car.calls.ids[0..car.calls.count]) |g| {
                    const group = s.groups[g];
                    stop = stop or (group.landing == car.floor and sign(group.destination - group.landing) == heading);
                };
            }
            if (stop) try s.openDoors(i) else if (heading != 0) {
                car.direction = heading;
                s.move(i, heading);
            } else {
                if (car.direction != 0) {
                    try s.emit("E{d} IDLE {d}", .{ i + 1, car.floor });
                    car.direction = 0;
                    car.idle_start = s.time;
                }
                if (s.fire == 0 and car.service and s.config.park >= 0 and car.floor != s.config.homes[i] and s.time - car.idle_start >= s.config.park) {
                    s.move(i, sign(s.config.homes[i] - car.floor));
                    if (car.floor == s.config.homes[i]) try s.emit("E{d} PARK {d}", .{ i + 1, car.floor });
                }
            }
        }
        if (car.door > 0 or car.floor != old) car.busy += 1;
    }

    fn settled(s: *Simulation, i: usize) bool {
        const car = &s.cars[i];
        if (car.door > 0 or car.riding > 0 or car.calls.count > 0) return false;
        if (s.fire > 0) return car.floor == s.fire;
        return !car.service or s.config.park < 0 or car.floor == s.config.homes[i];
    }

    fn run(s: *Simulation, events: []const Event) !void {
        var next: usize = 0;
        while (true) : (s.time += 1) {
            if (s.config.patience >= 0) for (0..s.ng) |i| if (s.groups[i].waiting > 0 and s.time == s.groups[i].time + s.config.patience) {
                try s.walk(i, "ABANDON");
            };
            while (next < events.len and events[next].time == s.time) : (next += 1) try s.perform(events[next]);
            for (0..s.config.count) |i| try s.advance(i);
            var all = true;
            for (0..s.config.count) |i| all = all and s.settled(i);
            if (next == events.len and all) {
                try s.emit("END", .{});
                break;
            }
            if (s.time == s.config.limit) {
                s.aborted = true;
                try s.emit("ABORT", .{});
                break;
            }
        }
    }

    fn breakdown(s: *Simulation, key: I, period: bool) !void {
        var groups: usize = 0;
        var passengers: I = 0;
        var delivered: I = 0;
        var wait: I = 0;
        for (s.groups[0..s.ng]) |group| if ((if (period) @divTrunc(group.time, s.config.period) else group.landing) == key) {
            groups += 1;
            passengers += group.count;
            delivered += group.delivered;
            wait += group.wait_total;
        };
        if (groups == 0) return;
        if (period) try s.host.out.print("P{d} {d}-{d}:", .{ key, key * s.config.period, key * s.config.period + s.config.period - 1 }) else try s.host.out.print("F{d}:", .{key});
        try s.host.line(" groups={d} passengers={d} delivered={d} avg_wait={s}", .{ groups, passengers, delivered, try s.host.average(wait, delivered) });
    }

    fn report(s: *Simulation) !void {
        var passengers: I = 0;
        for (s.groups[0..s.ng], 0..) |group, g| {
            var car_list: std.Io.Writer.Allocating = .init(s.host.gpa);
            var first = true;
            for (group.cars[0..s.config.count], 0..) |used, i| if (used) {
                try car_list.writer.print("{s}{d}", .{ if (first) "" else ",", i + 1 });
                first = false;
            };
            const wait = if (group.boarded == group.count) try s.host.text("{d}", .{group.last_board - group.time}) else "-";
            const travel = if (group.delivered == group.count) try s.host.text("{d}", .{group.last_alight - group.time}) else "-";
            try s.host.line("G{d} t={d} {d}->{d} n={d} delivered={d} lost={d} wait={s} travel={s} cars={s}", .{ g + 1, group.time, group.landing, group.destination, group.count, group.delivered, group.lost, wait, travel, if (first) "-" else car_list.written() });
            passengers += group.count;
        }
        for (s.cars[0..s.config.count], 0..) |car, i| {
            const util = @divTrunc(car.busy * 1000, s.time + 1);
            try s.host.line("E{d} distance={d} stops={d} boarded={d} busy={d} util={d}.{d}% energy={d}", .{ i + 1, car.distance, car.stops, car.boarded, car.busy, @divTrunc(util, 10), @mod(util, 10), car.energy });
        }
        var f: I = 1;
        while (f <= s.config.floors) : (f += 1) try s.breakdown(f, false);
        if (s.config.period >= 0) {
            var p: I = 0;
            while (p <= @divTrunc(10000, s.config.period)) : (p += 1) try s.breakdown(p, true);
        }
        try s.host.line("summary: groups={d} passengers={d} delivered={d} abandoned={d} evacuated={d} {s} end={d}", .{ s.ng, passengers, s.delivered, s.abandoned, s.evacuated, try s.host.averages(s.delivered, s.wait_total, s.travel_total, s.max_wait), s.time });
    }
};

fn readLine(reader: *std.Io.Reader, gpa: std.mem.Allocator) !?Text {
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try reader.streamDelimiterEnding(&buffer.writer, '\n');
    if (reader.bufferedLen() == 0 and buffer.written().len == 0) return null;
    if (reader.bufferedLen() > 0) reader.toss(1);
    return buffer.toOwnedSlice();
}

fn words(gpa: std.mem.Allocator, line: Text) ![]const Text {
    var result: std.ArrayList(Text) = .empty;
    var it = std.mem.splitScalar(u8, line, ' ');
    while (it.next()) |word| try result.append(gpa, word);
    return result.items;
}

pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var ib: [4096]u8 = undefined;
    var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var host: Host = .{ .gpa = gpa, .out = &output.interface };
    const q = index(number(std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r")));
    var line_number: usize = 1;
    var results: [50]Result = @splat(.{});
    for (0..q) |scenario| {
        const heading = try words(gpa, std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r"));
        line_number += 1;
        results[scenario].name = heading[1];
        var settings: std.ArrayList(Line) = .empty;
        var event_lines: std.ArrayList(Line) = .empty;
        while (true) {
            const source = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
            line_number += 1;
            if (eq(source, "END")) break;
            const line: Line = .{ .number = line_number, .words = try words(gpa, source) };
            if (source[0] >= '0' and source[0] <= '9') try event_lines.append(gpa, line) else try settings.append(gpa, line);
        }
        try host.line("== {s} ==", .{heading[1]});
        var config: Config = .{};
        if (try host.configuration(settings.items, &config)) |problem| {
            try host.line("error: {s}", .{problem});
            continue;
        }
        try host.configLines(config);
        const events = try host.validateEvents(config, event_lines.items);
        const simulation = try host.simulate(config, events, config.policy, true);
        try simulation.report();
        results[scenario] = .{ .name = heading[1], .valid = true, .aborted = simulation.aborted, .policy = config.policy, .delivered = simulation.delivered, .wait_total = simulation.wait_total, .travel_total = simulation.travel_total, .max_wait = simulation.max_wait };
        std.heap.page_allocator.destroy(simulation);
        for (config.compare[0..config.comparisons]) |policy| {
            const other = try host.simulate(config, events, policy, false);
            try host.line("compare {s}: delivered={d} {s} end={d} status={s}", .{ policies[policy], other.delivered, try host.averages(other.delivered, other.wait_total, other.travel_total, other.max_wait), other.time, if (other.aborted) "abort" else "end" });
            std.heap.page_allocator.destroy(other);
        }
    }
    try host.line("== ranking ==", .{});
    var ranked: [50]usize = undefined;
    var nr: usize = 0;
    for (results[0..q], 0..) |result, i| if (result.valid and !result.aborted and result.delivered > 0) {
        var position = nr;
        while (position > 0 and before(result, results[ranked[position - 1]])) : (position -= 1) ranked[position] = ranked[position - 1];
        ranked[position] = i;
        nr += 1;
    };
    for (ranked[0..nr], 0..) |i, rank| {
        const result = results[i];
        try host.line("{d}. {s} policy={s} {s}", .{ rank + 1, result.name, policies[result.policy], try host.averages(result.delivered, result.wait_total, result.travel_total, result.max_wait) });
    }
    for (results[0..q]) |result| if (!result.valid or result.aborted or result.delivered == 0) {
        try host.line("- {s} {s}", .{ result.name, if (!result.valid) "invalid" else if (result.aborted) "aborted" else "empty" });
    };
    try host.line("== policies ==", .{});
    for (policies, 0..) |policy, p| {
        var runs: usize = 0;
        var delivered: I = 0;
        var wait: I = 0;
        var travel: I = 0;
        for (ranked[0..nr]) |i| {
            const result = results[i];
            if (result.policy == p) {
                runs += 1;
                delivered += result.delivered;
                wait += result.wait_total;
                travel += result.travel_total;
            }
        }
        if (runs > 0) try host.line("{s}: runs={d} avg_wait={s} avg_travel={s}", .{ policy, runs, try host.average(wait, delivered), try host.average(travel, delivered) });
    }
    try output.interface.flush();
}
