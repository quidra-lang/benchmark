const c = @import("network.zig");
pub fn local(lamport: *i64, clock: *c.Vec, own: usize) void {
    lamport.* += 1;
    clock[own] += 1;
}
pub fn receive(lamport: *i64, clock: *c.Vec, own: usize, sent_lamport: i64, sent: c.Vec, count: usize) void {
    lamport.* = @max(lamport.*, sent_lamport) + 1;
    for (0..count) |i| clock[i] = @max(clock[i], sent[i]);
    clock[own] += 1;
}
pub fn lessEqual(first: c.Vec, second: c.Vec, count: usize) bool {
    for (0..count) |i| if (first[i] > second[i]) return false;
    return true;
}
pub fn relation(first: c.Vec, second: c.Vec, count: usize) i64 {
    var equal = true;
    for (0..count) |i| {
        if (first[i] != second[i]) equal = false;
    }
    if (equal) return 0;
    return if (lessEqual(first, second, count)) 1 else if (lessEqual(second, first, count)) -1 else 0;
}
pub fn deliverable(stamp: c.Vec, received: c.Vec, source: usize, count: usize) bool {
    for (0..count) |i| if (if (i == source) stamp[i] != received[i] + 1 else stamp[i] > received[i]) return false;
    return true;
}
pub fn missing(stamp: c.Vec, received: c.Vec, source: usize, count: usize) []const usize {
    var out: @import("std").ArrayList(usize) = .empty;
    for (0..count) |i| if (stamp[i] > received[i] + @as(i64, @intFromBool(i == source))) c.append(usize, &out, i);
    return out.items;
}
pub fn text(vector: []const i64) []const u8 {
    var out: c.Text = .{};
    for (vector, 0..) |value, i| out.add("{s}{d}", .{ if (i > 0) "," else "", value });
    return out.value();
}
