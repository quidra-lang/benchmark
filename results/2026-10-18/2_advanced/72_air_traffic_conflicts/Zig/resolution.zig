const d = @import("flight_plans.zig");
pub const Kind = enum { level, speed, delay };
pub const Manoeuvre = struct { name: []const u8, kind: Kind, amount: i64 };
pub fn manoeuvres(max_delay: i64) []const Manoeuvre {
    var out: @import("std").ArrayList(Manoeuvre) = .empty;
    d.append(Manoeuvre, &out, .{ .name = "level_up", .kind = .level, .amount = 10 });
    d.append(Manoeuvre, &out, .{ .name = "level_down", .kind = .level, .amount = -10 });
    d.append(Manoeuvre, &out, .{ .name = "speed_down", .kind = .speed, .amount = 0 });
    var delay: i64 = 60;
    while (delay <= max_delay) : (delay += 60) d.append(Manoeuvre, &out, .{ .name = d.fmt("delay_{d}",
         .{delay}), .kind = .delay, .amount = delay });
    return out.items;
}
pub fn propose(plan: d.Plan, manoeuvre: Manoeuvre, types: []const d.AircraftType, params: d.Params) ?d.Plan {
    var changed = plan;
    switch (manoeuvre.kind) {
        .level => {
            changed.offset += manoeuvre.amount;
            if (changed.level + changed.offset < params.level_min or changed.level + changed.offset > params.level_max) return null;
            for (changed.waypoints[1..]) |point| if (point.level) |level| {
                if (level + changed.offset < params.level_min or level + changed.offset > params.level_max) return null;
            };
        },
        .speed => {
            changed.speed = @divFloor(changed.speed * 9, 10);
            if (changed.speed < types[changed.type_index].minimum) return null;
        },
        .delay => {
            changed.delay += manoeuvre.amount;
        },
    }
    return changed;
}
pub fn priorityOrder(first: usize, second: usize, plans: []const d.Plan) [2]usize {
    const a = plans[first];
    const b = plans[second];
    const da = a.departure + a.delay;
    const db = b.departure + b.delay;
    const lower = da > db or (da == db and @import("std").mem.lessThan(u8, b.callsign, a.callsign));
    return if (lower) .{ first, second } else .{ second, first };
}
