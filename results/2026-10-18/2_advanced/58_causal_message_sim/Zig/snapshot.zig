const std = @import("std");
const c = @import("network.zig");
const p = @import("processes.zig");
pub const Record = struct { present: bool = false, time: i64 = 0, reason: []const u8 = "", balance: i64 = 0, lamport: i64 = 0, clock: c.Vec = c.zero, pending: []const usize = &.{} };
pub const Channel = struct { sent: i64 = 0, accepted: ?i64 = null, copies: std.ArrayList(usize) = .empty };
pub const Ignored = struct { process: usize, time: i64 };
pub const Snapshot = struct { name: []const u8, start: i64, complete: i64 = 0, accepted: usize = 0, records: []Record, channels: []Channel, ignored: std.ArrayList(Ignored) = .empty };
pub fn init(name: []const u8, time: i64, count: usize) *Snapshot {
    const records = c.alloc(Record, count);
    @memset(records, .{});
    const channels = c.alloc(Channel, count * count);
    @memset(channels, .{});
    return c.create(Snapshot, .{ .name = name, .start = time, .records = records, .channels = channels });
}
pub fn recordState(snapshot: *Snapshot, process: usize, state: p.Process, time: i64, reason: []const u8) void {
    snapshot.records[process] = .{ .present = true, .time = time, .reason = reason, .balance = state.balance, .lamport = state.lamport, .clock = state.clock, .pending = c.dupe(usize, state.hold.items) };
}
pub fn acceptMarker(snapshot: *Snapshot, source: usize, destination: usize, time: i64, count: usize) void {
    snapshot.channels[source * count + destination].accepted = time;
    snapshot.accepted += 1;
    if (snapshot.accepted == count * (count - 1)) snapshot.complete = time;
}
pub fn cut(snapshot: *const Snapshot) c.Vec {
    var out = c.zero;
    for (snapshot.records, 0..) |record, i| out[i] = record.clock[i];
    return out;
}
pub const Details = struct { orphans: std.ArrayList(usize) = .empty, transit: std.ArrayList(usize) = .empty, balances: i64 = 0, money: i64 = 0 };
pub fn details(values: c.Vec, processes: []const p.Process, events: []const p.Event, messages: []const p.Message, copies: []const p.Copy) Details {
    var out: Details = .{};
    for (copies, 0..) |copy, i| {
        const message = messages[copy.message];
        const sent = c.n(events[message.send].local) <= values[copy.source];
        const received = if (copy.received) |index| c.n(events[index].local) <= values[copy.destination] else false;
        if (received and !sent) c.append(usize, &out.orphans, i);
        if (sent and !received) {
            c.append(usize, &out.transit, i);
            out.money += message.amount;
        }
    }
    for (processes, 0..) |process, i| out.balances += p.balanceAtCut(process, events, values[i]);
    out.money += out.balances;
    return out;
}
