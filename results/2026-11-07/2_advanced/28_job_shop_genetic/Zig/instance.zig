const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &result, field);
    return result.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
};
pub fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub const Operation = struct { job: usize, index: usize, machine: usize, duration: i64, head: i64,
     tail: i64, previous: ?usize, next: ?usize };
pub const Job = struct { number: usize, work: i64, operations: []const usize };
pub const Machine = struct { count: usize = 0, load: i64 = 0, head: i64 = 1000000, tail: i64 = 1000000, bound: i64 = 0 };
pub const Instance = struct {
    machines: usize,
    operations: []const Operation,
    jobs: []const Job,
    machine: []Machine,
    errors: []const []const u8,
    work: i64,
    pub fn job(self: *const Instance, number_: usize) Job {
        for (self.jobs) |value| if (value.number == number_) return value;
        unreachable;
    }
};
pub const Order = [][]usize;
pub const Schedule = struct { start: []i64, finish: []i64, previous: []?usize, next: []?usize, order: Order,
     makespan: i64 = 0, decisions: usize = 0, ties: usize = 0 };
pub fn notation(op: Operation) []const u8 {
    return fmt("J{d}-{d}", .{ op.job, op.index });
}
pub fn cloneOrder(order: Order) Order {
    const result = alloc([]usize, order.len);
    for (order, result) |sequence, *target| target.* = dupe(usize, sequence);
    return result;
}
pub fn read(io: std.Io) !Instance {
    const lines = try readLines(io, "instance.txt");
    const header = split(lines[0], ' ');
    const machines = u(number(header[1]));
    const machine_stats = alloc(Machine, machines);
    @memset(machine_stats, .{});
    var operations: std.ArrayList(Operation) = .empty;
    var jobs: std.ArrayList(Job) = .empty;
    var errors: std.ArrayList([]const u8) = .empty;
    var total: i64 = 0;
    for (lines[1..], 1..) |line, job_number| {
        const fields = split(line, ' ');
        const route = alloc([2]i64, fields.len);
        var seen: [10]bool = @splat(false);
        var error_message: ?[]const u8 = null;
        for (fields, 0..) |field, index| {
            const pair = split(field, ':');
            const machine = number(pair[0]);
            const duration = number(pair[1]);
            var message: ?[]const u8 = null;
            if (machine < 1 or machine > n(machines)) message = fmt("unknown machine {d}", .{machine}) else if (duration < 1 or duration > 99) message = fmt("bad duration {d}",
                 .{duration}) else if (seen[u(machine - 1)]) message = fmt("repeated machine {d}",
                 .{machine});
            if (message) |reason| {
                error_message = fmt("job {d} operation {d}: {s}", .{ job_number, index + 1, reason });
                break;
            }
            seen[u(machine - 1)] = true;
            route[index] = .{ machine - 1, duration };
        }
        if (error_message) |message| {
            append([]const u8, &errors, message);
            continue;
        }
        var work: i64 = 0;
        for (route) |pair| work += pair[1];
        var head: i64 = 0;
        const ids = alloc(usize, fields.len);
        for (route, ids, 0..) |pair, *id, index| {
            id.* = operations.items.len;
            const op: Operation = .{ .job = job_number, .index = index + 1, .machine = u(pair[0]),
                 .duration = pair[1], .head = head, .tail = work - head - pair[1], .previous = if (index > 0) id.* - 1 else null,
                 .next = if (index + 1 < fields.len) id.* + 1 else null };
            append(Operation, &operations, op);
            head += op.duration;
            const machine = &machine_stats[op.machine];
            machine.count += 1;
            machine.load += op.duration;
            machine.head = @min(machine.head, op.head);
            machine.tail = @min(machine.tail, op.tail);
        }
        append(Job, &jobs, .{ .number = job_number, .work = work, .operations = ids });
        total += work;
    }
    for (machine_stats) |*machine| machine.bound = machine.head + machine.load + machine.tail;
    return .{ .machines = machines, .operations = operations.items, .jobs = jobs.items, .machine = machine_stats,
         .errors = errors.items, .work = total };
}
