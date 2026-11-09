const std = @import("std");
const l = @import("layout.zig");
const inter = @import("interlocking.zig");
pub const Stop = struct { turn: bool, section: usize, dwell: i64, scheduled_arrival: i64, scheduled_departure: i64,
     arrival: ?i64 = null, departure: ?i64 = null };
pub const PathSection = struct { section: usize, start: i64 };
pub const State = enum { waiting, running, exited };
pub const state_names = [_][]const u8{ "WAITING", "RUNNING", "EXITED" };
pub const Train = struct {
    name: []const u8,
    symbol: u8,
    length: i64,
    acceleration: i64,
    deceleration: i64,
    max_speed: i64,
    entry: usize,
    entry_time: i64,
    entry_speed: i64,
    exit: usize = 0,
    scheduled_exit: i64 = 0,
    stops: std.ArrayList(Stop) = .empty,
    stop_index: usize = 0,
    state: State = .waiting,
    direction: l.Direction = .up,
    path: std.ArrayList(PathSection) = .empty,
    head: i64 = 0,
    speed: i64 = 0,
    dwelling: bool = false,
    awaiting_departure: ?usize = null,
    emergency: bool = false,
    boundary: ?usize = null,
    boundary_coordinate: i64 = 0,
    entered: ?i64 = null,
    exited: ?i64 = null,
    distance: i64 = 0,
    maximum_speed: i64 = 0,
    standing: i64 = 0,
    passes: i64 = 0,
    pub fn nextStop(self: *Train) ?*Stop {
        return if (self.stop_index < self.stops.items.len) &self.stops.items[self.stop_index] else null;
    }
};
pub const Request = struct { time: i64, train: usize, route: usize };
pub fn read(io: std.Io, layout: *const l.Layout, interlocking: *const inter.Interlocking) !struct { trains: []Train,
     requests: []const Request } {
    var trains: std.ArrayList(Train) = .empty;
    var requests: std.ArrayList(Request) = .empty;
    for (try l.readLines(io, "input/trains.txt")) |line| {
        const f = l.words(line);
        if (l.eq(f[0], "TRAIN")) l.append(Train, &trains, .{ .name = f[1], .symbol = 'a' + @as(u8,
             @intCast(trains.items.len)), .length = l.number(f[2]), .acceleration = l.number(f[3]),
             .deceleration = l.number(f[4]), .max_speed = l.number(f[5]), .entry = l.indexOf(layout.boundaries,
             f[6]), .entry_time = l.number(f[7]), .entry_speed = l.number(f[8]) }) else {
            const index = l.indexOf(trains.items, f[1]);
            const train = &trains.items[index];
            if (l.eq(f[0], "REQUEST")) l.append(Request, &requests, .{ .time = l.number(f[3]),
                 .train = index, .route = l.indexOf(interlocking.routes, f[2]) }) else if (l.eq(f[0],
                 "STOP") or l.eq(f[0], "TURN")) l.append(Stop, &train.stops, .{ .turn = l.eq(f[0],
                 "TURN"), .section = l.indexOf(layout.sections, f[2]), .dwell = l.number(f[3]),
                 .scheduled_arrival = l.number(f[4]), .scheduled_departure = l.number(f[5]) }) else {
                train.exit = l.indexOf(layout.boundaries, f[2]);
                train.scheduled_exit = l.number(f[3]);
            }
        }
    }
    return .{ .trains = trains.items, .requests = requests.items };
}
pub fn brakingDistance(speed: i64, deceleration: i64) i64 {
    const count = @divTrunc(speed, deceleration);
    return count * speed - @divTrunc(deceleration * count * (count + 1), 2);
}
pub fn selectSpeed(train: *const Train, distance: ?i64) i64 {
    const low = @max(train.speed - train.deceleration, 0);
    if (!train.emergency) {
        var speed = @min(train.speed + train.acceleration, train.max_speed);
        while (speed >= low) : (speed -= 1) if (distance == null or speed + brakingDistance(speed,
             train.deceleration) <= distance.?) return speed;
    }
    return low;
}
