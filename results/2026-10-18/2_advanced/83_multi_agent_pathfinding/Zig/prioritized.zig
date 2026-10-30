const std = @import("std");
const g = @import("grid_map.zig");
const ll = @import("low_level.zig");
pub const Attempt = struct { agent: usize, path: ?g.Path, expansions: i64 };
pub const Result = struct { paths: ?g.Plan, attempts: []const Attempt, aborted: bool = false, failed: ?usize = null };
pub fn tryOrder(grid: g.Grid, agents: []const g.Agent, distances: []const []const i64, horizon: usize,
     order: []const usize, budget: *ll.Budget, work_allocator: std.mem.Allocator) Result {
    var prohibitions: ll.Prohibitions = .{};
    const paths = g.alloc(g.Path, agents.len);
    var attempts: std.ArrayList(Attempt) = .empty;
    for (order) |id| {
        const result = ll.search(grid, agents[id], distances[id], agents[id].start, 0, &prohibitions,
             horizon, budget, false, work_allocator);
        if (result.status == .aborted) return .{ .paths = null, .attempts = attempts.items, .aborted = true };
        g.append(Attempt, &attempts, .{ .agent = id, .path = if (result.status == .success) result.path else null,
             .expansions = result.expansions });
        if (result.status == .no_path) return .{ .paths = null, .attempts = attempts.items, .failed = id };
        paths[id] = result.path;
        prohibitions.reserve(result.path, 0, true);
    }
    return .{ .paths = paths, .attempts = attempts.items };
}
