const std = @import("std");
const S = @import("stats.zig");
pub const Turn = struct { target: *Segment, weight: i64, vehicles: i64 = 0 };
pub const BusStop = struct { segment: *Segment, cell: i64, dwell: i64, buses: i64 = 0 };
pub const Segment = struct {
    id: []const u8, start: []const u8, end: []const u8, length: i64, lanes: usize, limit: i64, index: usize, cells: []i64,
    junction: ?usize = null, turns: std.ArrayList(*Turn) = .empty, stop: ?*BusStop = null,
    entered: i64 = 0, vehicle_sum: i64 = 0, speed_sum: i64 = 0, max_vehicles: i64 = 0, green_steps: i64 = 0, queue_sum: i64 = 0, max_queue: i64 = 0, failures: i64 = 0, passed: i64 = 0, blocked: i64 = 0, changes: [3]i64 = .{ 0, 0, 0 },
    pub fn row(self: *const Segment, lane: usize) []i64 { const count = S.index(self.length); return self.cells[lane * count..(lane + 1) * count]; }
    pub fn empty(self: *const Segment, lane: usize, cell: i64) bool { return self.row(lane)[S.index(cell)] == 0; }
    pub fn obstacle(self: *const Segment, lane: usize, cell: i64) bool { return self.row(lane)[S.index(cell)] == -1; }
    pub fn put(self: *Segment, lane: usize, cell: i64, value: i64) void { self.row(lane)[S.index(cell)] = value; }
    pub fn clear(self: *Segment, lane: usize, cell: i64) void { self.put(lane, cell, 0); }
    pub fn free(self: *const Segment, lane: usize, cell: i64, cap: i64) i64 { var count: i64 = 0; while (count < cap and cell + count + 1 < self.length and self.empty(lane, cell + count + 1)) count += 1; return count; }
    pub fn first(self: *const Segment, lane: usize) i64 { for (self.row(lane), 0..) |value, i| { if (value != 0) return S.int(i); } return self.length; }
    pub fn safe(self: *const Segment, lane: usize, cell: i64) bool { for (S.index(@max(0, cell - self.limit))..S.index(cell + 1)) |x| { if (!self.empty(lane, S.int(x))) return false; } return true; }
    pub fn cellsText(self: *const Segment, lane: usize, vehicles: anytype) []const u8 { const result = S.alloc(u8, S.index(self.length)); for (self.row(lane), result) |value, *ch| ch.* = if (value == 0) '.' else if (value == -1) '#' else @as(u8, @intCast('0' + vehicles[S.index(value - 1)].speed)); return result; }
};
pub const Incident = struct {
    segment: *Segment, lane: usize, cell: i64, start: usize, end: usize, state: enum { planned, active, cleared, cancelled } = .planned, active_start: usize = 0, active_end: usize = 0,
    pub fn update(self: *Incident, step: usize) ?[]const u8 { var event: ?[]const u8 = null;
        if (self.state == .active and step > self.end) { self.state = .cleared; self.segment.clear(self.lane, self.cell); event = "INCIDENT_END"; } else if (self.state == .planned and step > self.end) { self.state = .cancelled; } else if (self.state == .planned and step >= self.start and self.segment.empty(self.lane, self.cell)) { self.state = .active; self.segment.put(self.lane, self.cell, -1); self.active_start = step; event = "INCIDENT_START"; }
        if (self.state == .active) self.active_end = step; return event;
    }
};
