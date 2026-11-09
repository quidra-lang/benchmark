const std = @import("std");
const R = @import("road.zig");
const S = @import("stats.zig");
pub const Phase = struct { duration: i64, token: []const u8, greens: []const []const u8 };
pub const Junction = struct {
    node: []const u8, offset: i64, phases: []const Phase, cycle: i64, incoming: std.ArrayList(*R.Segment) = .empty,
    pub fn init(node: []const u8, offset: i64, tokens: []const []const u8) Junction { const phases = S.alloc(Phase, tokens.len); var cycle: i64 = 0; for (tokens, phases) |token, *phase| { const parts = S.split(token, ':'); phase.* = .{ .duration = S.parse(parts[0]), .token = parts[1], .greens = if (S.eq(parts[1], "-")) &.{} else S.split(parts[1], ',') }; cycle += phase.duration; } return .{ .node = node, .offset = offset, .phases = phases, .cycle = cycle }; }
    pub fn green(self: *const Junction, id: []const u8, step: usize) bool { if (self.phases.len == 0) return true; var tau = @mod(S.int(step) - 1 + self.offset, self.cycle); for (self.phases) |phase| { if (tau < phase.duration) { for (phase.greens) |segment| { if (S.eq(segment, id)) return true; } return false; } tau -= phase.duration; } unreachable; }
    pub fn planLines(self: *const Junction) S.Lines { var result: S.Lines = .{}; if (self.phases.len == 0) { result.add("JUNCTION {s} unsignalized", .{self.node}); return result; } result.add("JUNCTION {s} signal cycle {d} offset {d}", .{ self.node, self.cycle, self.offset }); var begin: i64 = 0; for (self.phases, 1..) |phase, number| { const end = begin + phase.duration - 1; result.add("  PHASE {d} {d}-{d} {s}", .{ number, begin, end, phase.token }); begin = end + 1; } return result; }
};
