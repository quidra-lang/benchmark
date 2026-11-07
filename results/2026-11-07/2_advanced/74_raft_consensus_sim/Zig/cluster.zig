const std = @import("std");
const r = @import("raft_node.zig");
pub const Settings = struct { nodes: usize, election_min: i64, election_max: i64, heartbeat: i64,
     batch: usize, quorum: i64, seed: i64, end: i64, retry: i64, attempts: usize, sample: i64 };
pub const ControlKind = enum { crash, restart, partition, heal, transfer };
pub const Control = struct { time: i64, kind: ControlKind, first: usize = 0, second: usize = 0,
     groups: []const []const usize = &.{} };
pub const Accepted = struct { index: usize, term: i64 };
pub const Status = enum { committed, uncommitted, lost, failed, waiting };
pub fn statusName(status: Status) []const u8 {
    return switch (status) {
        .committed => "COMMITTED",
        .uncommitted => "UNCOMMITTED",
        .lost => "LOST",
        .failed => "FAILED",
        .waiting => "WAITING",
    };
}
pub const Request = struct { number: usize, time: i64, initial_destination: usize, command: r.Command,
     scheduled: ?i64, destination: usize, attempts: usize = 0, redirects: usize = 0, accepted: ?Accepted = null,
     abandoned: bool = false, status: Status = .waiting, latency: i64 = 0, result: r.Result = .none };
pub const Input = struct { settings: Settings, controls: []const Control, requests: []Request };
pub fn readInputs(io: std.Io) !Input {
    var values: std.ArrayList(i64) = .empty;
    for (try r.readLines(io, "input/cluster.txt")) |line| for (r.words(line)[1..]) |value| r.append(i64,
         &values, r.number(value));
    const v = values.items;
    const settings: Settings = .{ .nodes = r.u(v[0]), .election_min = v[1], .election_max = v[2],
         .heartbeat = v[3], .batch = r.u(v[4]), .quorum = v[5], .seed = v[6], .end = v[7],
         .retry = v[8], .attempts = r.u(v[9]), .sample = v[10] };
    var controls: std.ArrayList(Control) = .empty;
    var requests: std.ArrayList(Request) = .empty;
    for (try r.readLines(io, "input/script.txt")) |line| {
        const row = r.words(line);
        const time = r.number(row[0]);
        if (r.eq(row[1], "REQUEST")) {
            const destination = r.u(r.number(row[2]));
            const kind: r.Operation = if (r.eq(row[3], "SET")) .set else if (r.eq(row[3], "ADD")) .add else if (r.eq(row[3],
                 "DEL")) .delete else .get;
            const command: r.Command = .{ .kind = kind, .key = row[4], .value = if (row.len == 6) r.number(row[5]) else 0 };
            r.append(Request, &requests, .{ .number = requests.items.len + 1, .time = time,
                 .initial_destination = destination, .command = command, .scheduled = time,
                 .destination = destination });
        } else {
            var control: Control = .{ .time = time, .kind = if (r.eq(row[1], "CRASH")) .crash else if (r.eq(row[1],
                 "RESTART")) .restart else if (r.eq(row[1], "PARTITION")) .partition else if (r.eq(row[1],
                 "HEAL")) .heal else .transfer };
            if (control.kind == .partition) {
                const groups = r.alloc([]const usize, row.len - 2);
                for (row[2..], groups) |text, *group| {
                    const parts = r.split(text, ',');
                    const numbers = r.alloc(usize, parts.len);
                    for (parts, numbers) |part, *node| node.* = r.u(r.number(part));
                    group.* = numbers;
                }
                control.groups = groups;
            } else if (control.kind != .heal) {
                control.first = r.u(r.number(row[2]));
                if (control.kind == .transfer) control.second = r.u(r.number(row[3]));
            }
            r.append(Control, &controls, control);
        }
    }
    return .{ .settings = settings, .controls = controls.items, .requests = requests.items };
}
