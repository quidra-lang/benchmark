const std = @import("std");
const E = @import("enrolment.zig");
const R = @import("report.zig");
pub const Room = struct { id: []const u8, capacity: i64 };
pub const Placement = struct { course: usize, room: usize, first: i64, last: i64 };
pub const Packing = struct {
    values: [100]Placement = undefined, len: usize = 0,
    pub fn slice(self: *const Packing) []const Placement { return self.values[0..self.len]; }
};
fn roomLess(_: void, a: Room, b: Room) bool { return if (a.capacity == b.capacity) std.mem.order(u8, a.id, b.id) == .lt else a.capacity < b.capacity; }
pub fn loadRooms(source: []const u8, errors: *R.Lines) []Room {
    var rooms: std.ArrayList(Room) = .empty;
    for (R.lines(source)[1..], 2..) |line, line_number| {
        const fields = R.split(line, ',');
        var duplicate = false;
        for (rooms.items) |room| { if (R.eq(room.id, fields[0])) duplicate = true; }
        const capacity = R.number(fields[1]);
        if (duplicate) errors.add("rooms.csv line {d}: duplicate room {s}", .{ line_number, fields[0] })
        else if (capacity < 1) errors.add("rooms.csv line {d}: bad capacity {s}", .{ line_number, fields[1] })
        else R.append(Room, &rooms, .{ .id = fields[0], .capacity = capacity });
    }
    std.mem.sort(Room, rooms.items, {}, roomLess);
    return rooms.items;
}
pub fn pack(rooms: []const Room, courses: []const E.Course, group: E.Indices) ?Packing {
    var remaining: [20]i64 = undefined;
    var durations = [_]i64{0} ** 20;
    for (rooms, 0..) |room, i| remaining[i] = room.capacity;
    var result: Packing = .{};
    const order = E.ordered(courses, group, null);
    for (order.slice()) |c| {
        const course = courses[c];
        var found = false;
        for (rooms, 0..) |room, i| {
            if (remaining[i] < course.size() or (durations[i] != 0 and durations[i] != course.duration)) continue;
            const first = room.capacity - remaining[i] + 1;
            result.values[result.len] = .{ .course = c, .room = i, .first = first, .last = first + course.size() - 1 };
            result.len += 1;
            remaining[i] -= course.size();
            durations[i] = course.duration;
            found = true;
            break;
        }
        if (!found) return null;
    }
    return result;
}
