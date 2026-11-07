const std = @import("std");
const l = @import("layout.zig");
const inter = @import("interlocking.zig");
const sig = @import("signals.zig");
const tr = @import("trains.zig");
const safe = @import("safety.zig");
const Reason = struct {
    kind: enum { busy, conflict, occupied, locked, point_locked, point_failed, point_moving, point_occupied },
    index: usize = 0,
    fn same(self: Reason, other: Reason) bool {
        return self.kind == other.kind and self.index == other.index;
    }
    fn text(self: Reason, layout: *const l.Layout, interlocking: *const inter.Interlocking) []const u8 {
        return switch (self.kind) {
            .busy => "busy",
            .conflict => l.fmt("conflict {s}", .{interlocking.routes[self.index].name}),
            .occupied => l.fmt("occupied {s}", .{layout.sections[self.index].name}),
            .locked => l.fmt("locked {s}", .{layout.sections[self.index].name}),
            .point_locked, .point_failed, .point_moving, .point_occupied => l.fmt("point {s} {s}",
                 .{ layout.points[self.index].name, switch (self.kind) {
                .point_locked => "locked",
                .point_failed => "failed",
                .point_moving => "moving",
                else => "occupied",
            } }),
        };
    }
};
const Request = struct { number: i64, route: usize, time: i64, reason: ?Reason = null };
const Event = struct { time: i64, command: []const u8, arguments: l.Names };
const Part = struct { section: usize, start: i64, low: i64, high: i64 };
const Parts = struct { items: [40]Part = undefined, count: usize = 0 };
const LogRow = struct { name: []const u8, location: []const u8, scheduled: i64, actual: ?i64 };
const Simulation = struct {
    layout: l.Layout,
    interlocking: inter.Interlocking,
    trains: []tr.Train,
    planned: []const tr.Request,
    events: []const Event,
    snapshot_times: []const i64,
    end: i64,
    throw_time: i64,
    overlap_time: i64,
    time: i64 = 0,
    request_count: i64 = 0,
    dropped: i64 = 0,
    queue: std.ArrayList(Request) = .empty,
    log_lines: l.Lines = .{},
    snapshots: l.Lines = .{},
    safety: safe.Safety = .{},
    train_names: l.Names,
    fn read(io: std.Io) !Simulation {
        const layout = try l.read(io);
        const interlocking = try inter.read(io, &layout);
        const plans = try tr.read(io, &layout, &interlocking);
        var events: std.ArrayList(Event) = .empty;
        for (try l.readLines(io, "input/events.txt")) |line| {
            const f = l.words(line);
            l.append(Event, &events, .{ .time = l.number(f[0]), .command = f[1], .arguments = f[2..] });
        }
        const params = try l.readLines(io, "input/params.txt");
        const snapshots = l.words(params[3]);
        const times = l.alloc(i64, snapshots.len - 1);
        for (snapshots[1..], times) |value, *time| time.* = l.number(value);
        const names = l.alloc([]const u8, plans.trains.len);
        for (plans.trains, names) |train, *name| name.* = train.name;
        return .{ .layout = layout, .interlocking = interlocking, .trains = plans.trains, .planned = plans.requests,
             .events = events.items, .snapshot_times = times, .end = l.number(l.words(params[0])[1]),
             .throw_time = l.number(l.words(params[1])[1]), .overlap_time = l.number(l.words(params[2])[1]),
             .train_names = names };
    }
    fn log(self: *Simulation, comptime pattern: []const u8, args: anytype) void {
        self.log_lines.add("{d} {s}", .{ self.time, l.fmt(pattern, args) });
    }
    fn startThrow(self: *Simulation, index: usize, target: u8) void {
        const point = &self.layout.points[index];
        point.moving = true;
        point.target = target;
        point.completion = self.time + self.throw_time;
        self.log("MOVE {s} {c} until {d}", .{ point.name, target, point.completion.? });
    }
    fn completeThrows(self: *Simulation) void {
        for (self.layout.points) |*point| if (point.moving and point.completion == self.time) {
            point.position = point.target;
            point.moving = false;
            point.completion = null;
            point.throws += 1;
            self.log("POINT {s} {c}", .{ point.name, point.position });
        };
    }
    fn releaseApproaches(self: *Simulation) void {
        for (self.interlocking.routes, 0..) |route, index| if (route.state == .approach and route.release_time == self.time) {
            self.interlocking.release(&self.layout, index);
            self.log("TIMEOUT {s}", .{route.name});
        };
    }
    fn addRequest(self: *Simulation, index: usize, requester: []const u8) void {
        self.request_count += 1;
        self.interlocking.routes[index].requests += 1;
        self.log("REQUEST q{d} {s} {s}", .{ self.request_count, self.interlocking.routes[index].name, requester });
        l.append(Request, &self.queue, .{ .number = self.request_count, .route = index, .time = self.time });
    }
    fn cancel(self: *Simulation, index: usize) void {
        const route = &self.interlocking.routes[index];
        var removed = false;
        var position: usize = 0;
        while (position < self.queue.items.len) {
            const request = self.queue.items[position];
            if (request.route != index) {
                position += 1;
                continue;
            }
            removed = true;
            self.dropped += 1;
            self.log("DROP q{d} {s}", .{ request.number, route.name });
            _ = self.queue.orderedRemove(position);
        }
        if (removed) return;
        if (route.state == .locked) {
            route.cancels += 1;
            const signal = self.layout.signals[route.start];
            if (signal.aspect != .red and self.layout.occupied(signal.section)) {
                route.state = .approach;
                route.release_time = self.time + route.approach_time;
                self.log("CANCEL {s} approach until {d}", .{ route.name, route.release_time.? });
            } else {
                self.interlocking.release(&self.layout, index);
                self.log("CANCEL {s} released", .{route.name});
            }
        } else self.log("CANCEL {s} {s}", .{ route.name, if (route.state == .none) "none" else "refused" });
    }
    fn individualThrow(self: *Simulation, index: usize, target: u8) void {
        const point = self.layout.points[index];
        const result = if (point.locks() != 0) "locked" else if (point.failed) "failed" else if (point.moving) "moving" else if (self.layout.occupied(point.common)) "occupied" else if (point.position == target) "none" else "start";
        self.log("THROW {s} {c} {s}", .{ point.name, target, result });
        if (l.eq(result, "start")) self.startThrow(index, target);
    }
    fn executeEvents(self: *Simulation) void {
        for (self.events) |event| {
            if (event.time != self.time) continue;
            const command = event.command;
            const args = event.arguments;
            if (l.eq(command, "REQUEST")) self.addRequest(l.indexOf(self.interlocking.routes,
                 args[0]), "OPERATOR") else if (l.eq(command, "CANCEL")) self.cancel(l.indexOf(self.interlocking.routes,
                 args[0])) else if (l.eq(command, "THROW")) self.individualThrow(l.indexOf(self.layout.points,
                 args[0]), args[1][0]) else if (l.eq(command, "TCFAIL") or l.eq(command, "TCFIX")) {
                self.layout.sections[l.indexOf(self.layout.sections, args[0])].failed = l.eq(command, "TCFAIL");
                self.log("{s} {s}", .{ command, args[0] });
            } else {
                const index = l.indexOf(self.layout.points, args[0]);
                const point = &self.layout.points[index];
                point.failed = l.eq(command, "POINTFAIL");
                if (point.failed and point.moving) point.completion = null;
                self.log("{s} {s}", .{ command, args[0] });
                if (!point.failed and point.moving) self.startThrow(index, point.target);
            }
        }
    }
    fn oppositeLock(self: *const Simulation, locks: u64, direction: l.Direction) bool {
        for (self.interlocking.routes, 0..) |route, index| if (locks & l.bit(index) != 0 and route.direction != direction) return true;
        return false;
    }
    fn requestReason(self: *const Simulation, index: usize) ?Reason {
        const route = self.interlocking.routes[index];
        if (route.state != .none) return .{ .kind = .busy };
        for (route.conflicts) |other| if (inter.protected(self.interlocking.routes[other].state)) return .{ .kind = .conflict,
             .index = other };
        for (route.sections) |name| {
            const section = self.layout.sections[name];
            if (self.layout.occupied(name)) return .{ .kind = .occupied, .index = name };
            if (section.route_lock != null or self.oppositeLock(section.overlap_locks, route.direction)) return .{ .kind = .locked,
                 .index = name };
        }
        for (route.overlap) |name| {
            const section = self.layout.sections[name];
            if (self.layout.occupied(name)) return .{ .kind = .occupied, .index = name };
            const locks = section.overlap_locks | (if (section.route_lock) |r| l.bit(r) else @as(u64, 0));
            if (self.oppositeLock(locks, route.direction)) return .{ .kind = .locked, .index = name };
        }
        for (route.requirements) |req| {
            const point = self.layout.points[req.point];
            if ((if (req.position == 'N') point.reverse_locks else point.normal_locks) != 0) return .{ .kind = .point_locked,
                 .index = req.point };
            if ((!point.moving and point.position == req.position) or (point.moving and point.target == req.position)) continue;
            if (point.failed) return .{ .kind = .point_failed, .index = req.point };
            if (point.moving) return .{ .kind = .point_moving, .index = req.point };
            if (self.layout.occupied(point.common)) return .{ .kind = .point_occupied, .index = req.point };
        }
        return null;
    }
    fn judgeRequests(self: *Simulation) void {
        var position: usize = 0;
        while (position < self.queue.items.len) {
            const request = &self.queue.items[position];
            const route = &self.interlocking.routes[request.route];
            if (self.requestReason(request.route)) |reason| {
                if (request.reason == null or !request.reason.?.same(reason)) {
                    self.log("WAIT q{d} {s} {s}", .{ request.number, route.name, reason.text(&self.layout,
                         &self.interlocking) });
                    request.reason = reason;
                }
                position += 1;
                continue;
            }
            const route_index = request.route;
            const number = request.number;
            const wait = self.time - request.time;
            self.interlocking.lock(&self.layout, route_index);
            self.log("GRANT q{d} {s} wait {d}", .{ number, route.name, wait });
            route.grants += 1;
            route.wait += wait;
            route.maxwait = @max(route.maxwait, wait);
            for (route.requirements) |req| {
                const point = self.layout.points[req.point];
                if (!point.moving and point.position != req.position) self.startThrow(req.point, req.position);
            }
            _ = self.queue.orderedRemove(position);
        }
    }
    fn decideSignals(self: *Simulation) void {
        const aspects = sig.aspects(&self.layout, &self.interlocking);
        for (self.layout.signals, 0..) |*signal, index| if (signal.aspect != aspects[index]) {
            signal.aspect = aspects[index];
            self.log("SIGNAL {s} {s}", .{ signal.name, l.aspect_names[@intFromEnum(signal.aspect)] });
        };
    }
    fn occupiedParts(self: *const Simulation, train: *const tr.Train) Parts {
        var out: Parts = .{};
        if (train.state != .running) return out;
        const tail = train.head - train.length;
        for (train.path.items) |path| {
            const end = path.start + self.layout.sections[path.section].length;
            if (path.start < train.head and end > tail) {
                out.items[out.count] = .{ .section = path.section, .start = path.start, .low = @max(tail,
                     path.start), .high = @min(train.head, end) };
                out.count += 1;
            }
        }
        return out;
    }
    fn headSection(_: *const Simulation, train: *const tr.Train) tr.PathSection {
        var index = train.path.items.len;
        while (index > 0) {
            index -= 1;
            if (train.path.items[index].start < train.head) return train.path.items[index];
        }
        return train.path.items[0];
    }
    fn enter(self: *Simulation, train: *tr.Train, entered: *u16) bool {
        if (train.state == .exited) return false;
        if (train.state == .running) return true;
        const boundary = self.layout.boundaries[train.entry];
        const bit = @as(u16, 1) << @intCast(train.entry);
        if (self.time < train.entry_time or self.layout.occupied(boundary.section) or entered.* & bit != 0) return false;
        train.state = .running;
        train.direction = if (boundary.end == 'L') .up else .down;
        train.path.clearRetainingCapacity();
        l.append(tr.PathSection, &train.path, .{ .section = boundary.section, .start = 0 });
        train.head = 0;
        train.speed = train.entry_speed;
        train.entered = self.time;
        entered.* |= bit;
        self.log("ENTER {s} {s}", .{ train.name, boundary.name });
        return true;
    }
    fn reverse(self: *Simulation, train: *tr.Train, stop: *const tr.Stop) void {
        const head = self.headSection(train);
        const end = head.start + self.layout.sections[head.section].length;
        const parts = self.occupiedParts(train);
        train.path.clearRetainingCapacity();
        var index = parts.count;
        while (index > 0) {
            index -= 1;
            const part = parts.items[index];
            l.append(tr.PathSection, &train.path, .{ .section = part.section, .start = end - (part.start + self.layout.sections[part.section].length) });
        }
        train.head = end - (train.head - train.length);
        train.direction = if (train.direction == .up) .down else .up;
        self.log("REVERSE {s} {s}", .{ train.name, self.layout.sections[stop.section].name });
    }
    fn finishDwell(self: *Simulation, train: *tr.Train) bool {
        if (!train.dwelling) return true;
        const stop = train.nextStop().?;
        if (self.time < stop.arrival.? + stop.dwell or self.time < stop.scheduled_departure) return false;
        train.dwelling = false;
        train.awaiting_departure = train.stop_index;
        train.stop_index += 1;
        if (stop.turn) self.reverse(train, stop);
        return true;
    }
    fn limitDistance(self: *const Simulation, train: *tr.Train) ?i64 {
        if (train.boundary != null) return null;
        const head = self.headSection(train);
        var section = head.section;
        var distance = head.start + self.layout.sections[section].length - train.head;
        while (true) {
            if (self.layout.signalAt(section, train.direction)) |signal| if (self.layout.signals[signal].aspect == .red) return distance;
            if (train.nextStop()) |stop| if (stop.section == section) return distance;
            const beyond = self.layout.beyond(section, train.direction);
            if (beyond.kind == .boundary) return null;
            if (beyond.kind == .buffer or beyond.kind == .impassable) return distance;
            section = beyond.index;
            distance += self.layout.sections[section].length;
        }
    }
    fn passSignal(self: *Simulation, train: *tr.Train, index: usize) void {
        const signal = &self.layout.signals[index];
        var route_index: ?usize = null;
        for (self.interlocking.routes, 0..) |route, i| if (route.start == index and inter.protected(route.state)) {
            route_index = i;
            break;
        };
        self.log("PASS {s} {s} {s} {s}", .{ train.name, signal.name, l.aspect_names[@intFromEnum(signal.aspect)],
             if (route_index) |r| self.interlocking.routes[r].name else "-" });
        signal.passes += 1;
        train.passes += 1;
        if (route_index) |r| {
            self.interlocking.routes[r].state = .used;
            self.interlocking.routes[r].uses += 1;
        }
        if (signal.aspect == .red) {
            self.log("SPAD {s} {s}", .{ train.name, signal.name });
            self.safety.check(self.time, 3, l.fmt("{s} {s}", .{ train.name, signal.name }));
            train.emergency = true;
        } else self.safety.check(self.time, 3, null);
    }
    fn move(self: *Simulation, train: *tr.Train, distance: i64) void {
        var current = self.headSection(train);
        var remaining = distance;
        while (remaining > 0) {
            if (train.boundary != null) {
                train.head += remaining;
                break;
            }
            const end = current.start + self.layout.sections[current.section].length;
            if (train.head + remaining <= end) {
                train.head += remaining;
                break;
            }
            remaining -= end - train.head;
            train.head = end;
            if (self.layout.signalAt(current.section, train.direction)) |signal| self.passSignal(train, signal);
            if (train.awaiting_departure) |index| {
                const stop = &train.stops.items[index];
                if (stop.section == current.section) {
                    self.log("DEPART {s} {s}", .{ train.name, self.layout.sections[current.section].name });
                    stop.departure = self.time;
                    train.awaiting_departure = null;
                }
            }
            const beyond = self.layout.beyond(current.section, train.direction);
            if (beyond.kind == .boundary) {
                train.boundary = beyond.index;
                train.boundary_coordinate = end;
            } else {
                current = .{ .section = beyond.index, .start = end };
                l.append(tr.PathSection, &train.path, current);
            }
        }
    }
    fn afterMovement(self: *Simulation, train: *tr.Train, speed: i64, previous: i64) void {
        train.speed = speed;
        train.distance += speed;
        train.maximum_speed = @max(train.maximum_speed, speed);
        if (speed == 0) train.emergency = false;
        const head = self.headSection(train);
        const stop = train.nextStop();
        const arrived = stop != null and speed == 0 and head.section == stop.?.section and train.head == head.start + self.layout.sections[head.section].length;
        if (arrived) {
            train.dwelling = true;
            stop.?.arrival = self.time;
            self.log("ARRIVE {s} {s}", .{ train.name, self.layout.sections[head.section].name });
        }
        if (speed == 0 and !arrived) {
            train.standing += 1;
            if (previous > 0) self.log("HOLD {s} {s}", .{ train.name, self.layout.sections[head.section].name });
        }
        if (train.boundary != null and train.head - train.length >= train.boundary_coordinate) {
            train.state = .exited;
            train.exited = self.time;
            self.log("EXIT {s} {s}", .{ train.name, self.layout.boundaries[train.boundary.?].name });
        }
    }
    fn runTrains(self: *Simulation) void {
        var entered: u16 = 0;
        for (self.trains) |*train| {
            if (!self.enter(train, &entered) or !self.finishDwell(train)) continue;
            const distance = self.limitDistance(train);
            const previous = train.speed;
            const speed = tr.selectSpeed(train, distance);
            self.move(train, speed);
            self.afterMovement(train, speed, previous);
        }
    }
    fn recomputeOccupancy(self: *Simulation) void {
        for (self.layout.sections) |*section| section.occupants = 0;
        for (self.trains, 0..) |*train, index| {
            const parts = self.occupiedParts(train);
            for (parts.items[0..parts.count]) |part| self.layout.sections[part.section].occupants |= @as(u32,
                 1) << @intCast(index);
        }
    }
    fn sectionalRelease(self: *Simulation) void {
        for (self.interlocking.routes, 0..) |*route, index| {
            if (route.state != .used) continue;
            for (route.sections) |section| if (self.layout.sections[section].route_lock == index and self.layout.occupied(section)) {
                route.passed |= l.bit(section);
            };
            for (route.sections) |section| {
                if (self.layout.sections[section].route_lock != index) continue;
                if (route.passed & l.bit(section) == 0 or self.layout.occupied(section)) break;
                self.interlocking.unlockSection(&self.layout, index, section);
                self.log("RELEASE {s} {s}", .{ route.name, self.layout.sections[section].name });
            }
            var remaining = false;
            for (route.sections) |section| remaining = remaining or self.layout.sections[section].route_lock == index;
            if (!remaining) {
                self.interlocking.release(&self.layout, index);
                self.log("DONE {s}", .{route.name});
            } else if (route.overlap.len > 0 and route.overlap_locked) {
                route.overlap_counter = if (self.layout.occupied(route.sections[route.sections.len - 1])) route.overlap_counter + 1 else 0;
                if (route.overlap_counter >= self.overlap_time) {
                    self.interlocking.unlockOverlap(&self.layout, index);
                    self.log("OVERLAP {s}", .{route.name});
                }
            }
        }
    }
    fn recordStatistics(self: *Simulation) void {
        for (self.interlocking.routes) |*route| route.locked_seconds += @intFromBool(route.state != .none);
        for (self.layout.points) |*point| {
            point.locked_seconds += @intFromBool(point.locks() != 0);
            point.moving_seconds += @intFromBool(point.moving);
        }
        for (self.layout.sections, 0..) |*section, index| {
            section.occupied_seconds += @intFromBool(self.layout.occupied(index));
            section.locked_seconds += @intFromBool(section.route_lock != null or section.overlap_locks != 0);
            section.trains |= section.occupants;
        }
        for (self.layout.signals) |*signal| signal.seconds[@intFromEnum(signal.aspect)] += 1;
    }
    fn diagram(self: *Simulation) void {
        var height: usize = 0;
        var width: usize = 0;
        for (self.layout.sections) |section| {
            height = @max(height, section.row + 1);
            width = @max(width, section.last + 1);
        }
        for (self.layout.points) |point| {
            height = @max(height, point.row + 1);
            width = @max(width, point.column + 1);
        }
        for (self.layout.signals) |signal| {
            height = @max(height, signal.row + 1);
            width = @max(width, signal.column + 1);
        }
        for (self.layout.buffers) |buffer| {
            height = @max(height, buffer.row + 1);
            width = @max(width, buffer.column + 1);
        }
        for (self.layout.labels) |label| {
            height = @max(height, label.row + 1);
            width = @max(width, label.column + label.text.len);
        }
        var grid: [21][151]u8 = @splat(@splat(' '));
        for (self.layout.labels) |label| @memcpy(grid[label.row][label.column .. label.column + label.text.len],
             label.text);
        for (self.layout.sections) |section| @memset(grid[section.row][section.first .. section.last + 1],
             if (section.failed) '#' else if (section.route_lock != null) '=' else if (section.overlap_locks != 0) '~' else '-');
        for (self.trains) |*train| {
            const parts = self.occupiedParts(train);
            for (parts.items[0..parts.count]) |part| {
                const section = self.layout.sections[part.section];
                const cells = section.last - section.first + 1;
                const length = section.length;
                const left = if (train.direction == .up) part.low - part.start else length - (part.high - part.start);
                const right = if (train.direction == .up) part.high - part.start else length - (part.low - part.start);
                for (0..cells) |cell| if (left * l.n(cells) < l.n(cell + 1) * length and right * l.n(cells) > l.n(cell) * length) {
                    const character = &grid[section.row][section.first + cell];
                    character.* = if ((character.* >= 'a' and character.* <= 'z') or character.* == '*') '*' else train.symbol;
                };
            }
        }
        for (self.layout.buffers) |buffer| grid[buffer.row][buffer.column] = '|';
        for (self.layout.points) |point| grid[point.row][point.column] = if (point.detected()) point.position else '?';
        for (self.layout.signals) |signal| grid[signal.row][signal.column] = switch (signal.aspect) {
            .red => 'X',
            .yellow => 'Y',
            .green => 'G',
        };
        for (grid[0..height]) |row| self.snapshots.add("{s}", .{std.mem.trimEnd(u8, row[0..width], " ")});
    }
    fn snapshot(self: *Simulation) void {
        self.snapshots.add("SNAPSHOT {d}", .{self.time});
        self.diagram();
        for (self.trains) |*train| if (train.state == .running) {
            const parts = self.occupiedParts(train);
            var sections: l.Text = .{};
            for (parts.items[0..parts.count], 0..) |part, index| sections.add("{s}{s}", .{ if (index == 0) "" else ",",
                 self.layout.sections[part.section].name });
            if (parts.count == 0) self.snapshots.add("TRAIN {c} {s} {s} {d}", .{ train.symbol,
                 train.name, l.direction_names[@intFromEnum(train.direction)], train.speed }) else self.snapshots.add("TRAIN {c} {s} {s} {d} {s}",
                 .{ train.symbol, train.name, l.direction_names[@intFromEnum(train.direction)],
                 train.speed, sections.value() });
        };
        var text: l.Text = .{};
        text.add("ROUTES", .{});
        var count: usize = 0;
        for (self.interlocking.routes) |route| if (route.state != .none) {
            text.add(" {s}/{s}", .{ route.name, inter.state_names[@intFromEnum(route.state)] });
            count += 1;
        };
        if (count == 0) text.add(" -", .{});
        self.snapshots.add("{s}", .{text.value()});
    }
    fn trainRows(self: *const Simulation) []const LogRow {
        var rows: std.ArrayList(LogRow) = .empty;
        for (self.trains) |train| {
            l.append(LogRow, &rows, .{ .name = train.name, .location = l.fmt("enter:{s}", .{self.layout.boundaries[train.entry].name}),
                 .scheduled = train.entry_time, .actual = train.entered });
            for (train.stops.items) |stop| {
                l.append(LogRow, &rows, .{ .name = train.name, .location = l.fmt("arr:{s}",
                     .{self.layout.sections[stop.section].name}), .scheduled = stop.scheduled_arrival,
                     .actual = stop.arrival });
                l.append(LogRow, &rows, .{ .name = train.name, .location = l.fmt("dep:{s}",
                     .{self.layout.sections[stop.section].name}), .scheduled = stop.scheduled_departure,
                     .actual = stop.departure });
            }
            l.append(LogRow, &rows, .{ .name = train.name, .location = l.fmt("exit:{s}", .{self.layout.boundaries[train.exit].name}),
                 .scheduled = train.scheduled_exit, .actual = train.exited });
        }
        return rows.items;
    }
    fn trainReport(_: *const Simulation, rows: []const LogRow) l.Lines {
        var out: l.Lines = .{};
        out.add("train,location,scheduled,actual,delay", .{});
        for (rows) |row| if (row.actual) |actual| out.add("{s},{s},{d},{d},{d}", .{ row.name,
             row.location, row.scheduled, actual, actual - row.scheduled }) else out.add("{s},{s},{d},-,-",
             .{ row.name, row.location, row.scheduled });
        return out;
    }
    fn summary(self: *const Simulation, rows: []const LogRow) l.Lines {
        var out: l.Lines = .{};
        for (self.interlocking.routes) |route| out.add("ROUTE {s} {s}-{s} requests {d} grants {d} uses {d} cancels {d} wait {d} maxwait {d} locked {d}",
             .{ route.name, self.layout.signals[route.start].name, route.finish, route.requests,
             route.grants, route.uses, route.cancels, route.wait, route.maxwait, route.locked_seconds });
        for (self.layout.points) |point| out.add("POINT {s} throws {d} locked {d} moving {d} final {c}",
             .{ point.name, point.throws, point.locked_seconds, point.moving_seconds, if (point.detected()) point.position else '?' });
        for (self.layout.sections) |section| out.add("SECTION {s} occupied {d} locked {d} trains {d}",
             .{ section.name, section.occupied_seconds, section.locked_seconds, @popCount(section.trains) });
        for (self.layout.signals) |signal| out.add("SIGNAL {s} red {d} yellow {d} green {d} passes {d}",
             .{ signal.name, signal.seconds[0], signal.seconds[1], signal.seconds[2], signal.passes });
        var states: [3]usize = @splat(0);
        for (self.trains) |train| {
            states[@intFromEnum(train.state)] += 1;
            out.add("TRAIN {s} {c} {s} distance {d} maxspeed {d} standing {d} passes {d}",
                 .{ train.name, train.symbol, tr.state_names[@intFromEnum(train.state)], train.distance,
                 train.maximum_speed, train.standing, train.passes });
        }
        out.add("TRAINS total {d} exited {d} running {d} waiting {d}", .{ self.trains.len,
             states[2], states[1], states[0] });
        var on_time: i64 = 0;
        var late: i64 = 0;
        var missing: i64 = 0;
        var total_delay: i64 = 0;
        var maximum: i64 = 0;
        for (rows) |row| if (row.actual) |actual| {
            const delay = actual - row.scheduled;
            if (delay <= 0) on_time += 1 else {
                late += 1;
                total_delay += delay;
                maximum = @max(maximum, delay);
            }
        } else {
            missing += 1;
        };
        out.add("PUNCTUALITY on_time {d} late {d} missing {d} total_delay {d} max_delay {d}",
             .{ on_time, late, missing, total_delay, maximum });
        var grants: i64 = 0;
        for (self.interlocking.routes) |route| grants += route.grants;
        out.add("REQUESTS total {d} granted {d} dropped {d} pending {d}", .{ self.request_count,
             grants, self.dropped, self.queue.items.len });
        return out;
    }
    fn run(self: *Simulation, io: std.Io) !void {
        while (self.time <= self.end) : (self.time += 1) {
            self.completeThrows();
            self.releaseApproaches();
            for (self.planned) |request| if (request.time == self.time) self.addRequest(request.route,
                 self.trains[request.train].name);
            self.executeEvents();
            self.judgeRequests();
            self.decideSignals();
            self.runTrains();
            self.recomputeOccupancy();
            self.sectionalRelease();
            self.safety.inspect(self.time, &self.layout, &self.interlocking, self.train_names);
            self.recordStatistics();
            if (std.mem.indexOfScalar(i64, self.snapshot_times, self.time) != null) self.snapshot();
        }
        const rows = self.trainRows();
        try l.writeLines(io, "events.txt", self.log_lines);
        try l.writeLines(io, "snapshots.txt", self.snapshots);
        try l.writeLines(io, "train_log.csv", self.trainReport(rows));
        try l.writeLines(io, "safety.txt", self.safety.report());
        try l.writeLines(io, "summary.txt", self.summary(rows));
    }
};
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    l.allocator = arena.allocator();
    var simulation = try Simulation.read(init.io);
    try simulation.run(init.io);
}
