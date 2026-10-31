const std = @import("std");
const R = @import("road.zig");
const S = @import("stats.zig");
pub const Class = struct { name: []const u8, vmax: i64, weight: i64, overtakes: bool, stops: bool };
pub const Vehicle = struct {
    number: usize, class: *const Class, source: usize, arrival: usize, inserted: usize = 0, exited: usize = 0, sink: []const u8 = "-", segment: ?*R.Segment = null, lane: usize = 0, cell: i64 = 0, speed: i64 = 0, turn: ?*R.Turn = null, route: std.ArrayList(*R.Segment) = .empty,
    steps: i64 = 0, distance: i64 = 0, stopped_steps: i64 = 0, stop_count: i64 = 0, lane_changes: i64 = 0, dwell: i64 = 0, completed: u32 = 0, trace: ?*S.Lines = null,
    pub fn maxSpeed(self: *const Vehicle) i64 { return @min(self.class.vmax, self.segment.?.limit); }
    pub fn place(self: *Vehicle, segment: *R.Segment, lane: usize, cell: i64) void { if (self.segment) |previous| previous.clear(self.lane, self.cell); segment.put(lane, cell, S.int(self.number)); self.segment = segment; self.lane = lane; self.cell = cell; }
    pub fn leave(self: *Vehicle) void { self.segment.?.clear(self.lane, self.cell); self.segment = null; }
    pub fn headingForStop(self: *const Vehicle) bool { const segment = self.segment orelse return false; if (!self.class.stops or (self.completed & bit(segment.index)) != 0) return false; const stop = segment.stop orelse return false; return self.cell <= stop.cell; }
    pub fn travelTime(self: *const Vehicle) i64 { return S.int(self.exited - self.inserted + 1); }
};
pub fn bit(index: usize) u32 { return @as(u32, 1) << @as(u5, @intCast(index)); }
pub fn randomSlowdown(speed: i64, previous: i64, value: i64, dawdle: i64, stopped: i64) i64 { const probability = if (previous == 0) stopped else dawdle; return if (speed > 0 and @mod(value, 1000) < probability) speed - 1 else speed; }
