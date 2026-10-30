const std = @import("std");
const c = @import("network.zig");
pub const ActionKind = enum { local, send, transfer, broadcast, snapshot };
pub const Action = struct { kind: ActionKind, argument: []const u8, tag: []const u8 = "", amount: i64 = 0 };
pub const Timed = struct { start: i64, period: i64, action: Action };
pub const Rule = struct { tag: []const u8, action: Action };
pub const Script = struct { balance: i64 = 0, at: std.ArrayList(Timed) = .empty, on: std.ArrayList(Rule) = .empty };
pub const Process = struct { initial: i64 = 0, balance: i64 = 0, lamport: i64 = 0, in: i64 = 0,
     out: i64 = 0, refused: i64 = 0, minimum: i64 = 0, clock: c.Vec = c.zero, broadcast: c.Vec = c.zero,
     events: std.ArrayList(usize) = .empty, delivered: std.ArrayList(usize) = .empty, hold: std.ArrayList(usize) = .empty,
     next: [6]i64 = .{ 1, 1, 1, 1, 1, 1 }, reorder: [6]std.ArrayList(usize) = [_]std.ArrayList(usize){.empty} ** 6,
     max_held: usize = 0, counts: [5]i64 = .{ 0, 0, 0, 0, 0 } };
pub const EventKind = enum { local, nofunds, send, bcast, recv };
pub const Event = struct { process: usize, local: usize, time: i64, kind: EventKind, peer: ?usize = null,
     message: ?usize = null, copy: ?usize = null, lamport: i64, balance: i64, amount: i64 = 0,
     clock: c.Vec, label: []const u8 = "" };
pub const Message = struct { source: usize, send: usize = 0, tag: []const u8, amount: i64,
     broadcast: bool, stamp: c.Vec = c.zero, copies: std.ArrayList(usize) = .empty };
pub const Copy = struct { message: usize, source: usize, destination: usize, packet: usize = 0,
     received: ?usize = null, delivery: i64 = 0, fifo_wait: bool = false, causal_wait: bool = false,
     missing: []const usize = &.{} };
pub const Packet = struct { source: usize, destination: usize, sequence: i64, dispatch: i64,
     arrival: i64, copy: ?usize = null, snapshot: ?usize = null };
fn parseAction(row: []const []const u8) Action {
    const kinds = [_]ActionKind{ .local, .send, .transfer, .broadcast, .snapshot };
    const names = [_][]const u8{ "LOCAL", "SEND", "TRANSFER", "BROADCAST", "SNAPSHOT" };
    for (names, kinds) |name, kind| if (c.eq(name, row[0])) return .{ .kind = kind, .argument = row[1],
         .tag = if (kind == .send) row[2] else "", .amount = if (kind == .transfer) c.number(row[2]) else 0 };
    unreachable;
}
pub fn load(io: std.Io, topology: c.Topology) ![]Script {
    const scripts = c.alloc(Script, topology.names.len);
    @memset(scripts, .{});
    var current: usize = 0;
    for (try c.readLines(io, "input/programs.txt")) |line| {
        const row = c.words(line);
        if (c.eq(row[0], "PROCESS")) {
            current = topology.index(row[1]);
            scripts[current].balance = c.number(row[3]);
        } else if (c.eq(row[0], "AT")) {
            const repeated = c.eq(row[2], "EVERY");
            c.append(Timed, &scripts[current].at, .{ .start = c.number(row[1]), .period = if (repeated) c.number(row[3]) else 0,
                 .action = parseAction(row[if (repeated) @as(usize, 4) else 2..]) });
        } else if (c.eq(row[0], "ON")) c.append(Rule, &scripts[current].on, .{ .tag = row[1],
             .action = parseAction(row[2..]) });
    }
    return scripts;
}
pub fn initialize(scripts: []const Script) []Process {
    const out = c.alloc(Process, scripts.len);
    for (scripts, out) |script, *state| state.* = .{ .initial = script.balance, .balance = script.balance,
         .minimum = script.balance };
    return out;
}
pub const Scheduled = struct { time: i64, process: usize, action: Action };
pub fn expand(scripts: []const Script, end: i64) []const Scheduled {
    var out: std.ArrayList(Scheduled) = .empty;
    for (scripts, 0..) |script, p| for (script.at.items) |item| {
        var time = item.start;
        while (time <= end) : (time += item.period) {
            c.append(Scheduled, &out, .{ .time = time, .process = p, .action = item.action });
            if (item.period == 0) break;
        }
    };
    return out.items;
}
pub fn balanceAtCut(process: Process, events: []const Event, count: i64) i64 {
    return if (count == 0) process.initial else events[process.events.items[c.u(count - 1)]].balance;
}
