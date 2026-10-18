const std = @import("std");

fn account(name: []const u8) usize {
    const names = [_][]const u8{ "Nina", "Leo", "Emma" };
    for (names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name))
            return i;
    }
    unreachable;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const names = [_][]const u8{ "Nina", "Leo", "Emma" };
    var balances = [_]u32{ 12000, 3500, 800 };
    const commands = [_][]const u8{
        "deposit Emma 1200",
        "withdraw Leo 4000",
        "transfer Nina Leo 5000",
        "withdraw Leo 4000",
        "transfer Emma Nina 2500",
        "transfer Emma Nina 2000",
        "withdraw Emma 300",
        "deposit Nina 750",
        "transfer Leo Emma 3200",
        "withdraw Nina 9800"
    };
    for (commands, 0..) |command, k| {
        var parts = std.mem.splitScalar(u8, command, ' ');
        const op = parts.next().?;
        const source = account(parts.next().?);
        var destination: usize = 0;
        const transfer = std.mem.eql(u8, op, "transfer");
        if (transfer)
            destination = account(parts.next().?);
        const amount = try std.fmt.parseInt(u32, parts.next().?, 10);
        var success = true;
        if (std.mem.eql(u8, op, "deposit")) {
            balances[source] += amount;
        } else if (balances[source] < amount) {
            success = false;
        } else {
            balances[source] -= amount;
            if (transfer)
                balances[destination] += amount;
        }
        try out.print("op {d}: {s} {s}\n", .{
            k + 1,
            command,
            if (success) @as([]const u8, "ok") else "failed (insufficient funds)"
        });
    }
    var order = [_]usize{ 0, 1, 2 };
    for (0..3) |i| {
        for (i + 1..3) |j| {
            if (std.mem.order(u8, names[order[j]], names[order[i]]) == .lt) {
                const t = order[i];
                order[i] = order[j];
                order[j] = t;
            }
        }
    }
    for (order) |i|
        try out.print("{s}: {d}\n", .{ names[i], balances[i] });
    try out.flush();
}
