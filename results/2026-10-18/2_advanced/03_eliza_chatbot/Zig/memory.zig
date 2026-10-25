const std = @import("std");
const loader = @import("script_loader.zig");

pub const Queue = struct {
    capacity: usize,
    texts: std.ArrayList([]const u8) = .empty,
    log: std.ArrayList([]const u8) = .empty,
    pub fn copy(q: Queue) Queue { return .{ .capacity = q.capacity, .texts = loader.listCopy([]const u8, q.texts), .log = loader.listCopy([]const u8, q.log) }; }
    pub fn store(q: *Queue, prefix: []const u8, keyword: []const u8, text: []const u8) bool {
        if (loader.has(q.texts.items, text)) { loader.append([]const u8, &q.log, loader.fmt("{s} SKIP {s} {s}", .{ prefix, keyword, text })); return false; }
        if (q.texts.items.len == q.capacity) { const oldest = q.texts.orderedRemove(0); loader.append([]const u8, &q.log, loader.fmt("{s} DROP {s}", .{ prefix, oldest })); }
        loader.append([]const u8, &q.texts, text);
        loader.append([]const u8, &q.log, loader.fmt("{s} STORE {s} {s}", .{ prefix, keyword, text }));
        return true;
    }
    pub fn recall(q: *Queue, prefix: []const u8) []const u8 { const text = q.texts.orderedRemove(0); loader.append([]const u8, &q.log, loader.fmt("{s} RECALL {s}", .{ prefix, text })); return text; }
    pub fn clear(q: *Queue, prefix: []const u8) void { if (q.texts.items.len > 0) { loader.append([]const u8, &q.log, loader.fmt("{s} CLEAR {d}", .{ prefix, q.texts.items.len })); q.texts.items.len = 0; } }
};
