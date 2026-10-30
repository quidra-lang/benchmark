const std = @import("std");
const c = @import("trace_io.zig");
const h = @import("hazards.zig");
pub const Record = struct { cause: usize, cycles: i64, responsible: usize, waiting: ?usize, producer: ?usize };
pub const Run = struct { timings: []h.Timing, records: []const Record, cycles: i64, stalls: [4]i64 = .{ 0,
     0, 0, 0 }, events: [4]i64 = .{ 0, 0, 0, 0 } };
pub fn simulate(instructions: []const c.Instruction, sources: []const h.Sources, variant: c.Variant,
     flags: []const bool) Run {
    const timings = c.alloc(h.Timing, instructions.len);
    var records: std.ArrayList(Record) = .empty;
    for (instructions, 0..) |instruction, i| {
        var time: h.Timing = .{};
        const execute = if (instruction.kind == .multiply) variant.latency else 1;
        if (i == 0) {
            time.f = 1;
            time.d = 2;
            time.x = 3;
        } else {
            const previous = timings[i - 1];
            time.f = if (flags[i - 1]) previous.x + @as(i64, @intFromBool(!h.idResolved(instructions[i - 1],
                 variant))) else previous.d;
            time.d = @max(time.f + 1, previous.x);
            const ideal = previous.x + 1;
            var bound = [_]i64{ time.d + 1, previous.m, ideal, ideal };
            var producer = [_]?usize{null} ** 4;
            for (sources[i]) |source| if (source) |p| {
                const cause: usize = if (instructions[p].kind == .load) 2 else 3;
                const ready = h.readyCycle(instruction, instructions[p], timings[p], variant);
                if (ready > bound[cause]) {
                    bound[cause] = ready;
                    producer[cause] = p;
                }
            };
            time.x = ideal;
            for (bound, 0..) |value, cause| if (value > time.x) {
                c.append(Record, &records, .{ .cause = cause, .cycles = value - time.x, .responsible = if (cause < 2) i - 1 else i,
                     .waiting = i, .producer = producer[cause] });
                time.x = value;
            };
        }
        time.m = time.x + execute;
        time.w = time.m + 1;
        timings[i] = time;
    }
    if (instructions[instructions.len - 1].kind == .multiply and variant.latency >= 2) c.append(Record,
         &records, .{ .cause = 1, .cycles = variant.latency - 1, .responsible = instructions.len - 1,
         .waiting = null, .producer = null });
    var out: Run = .{ .timings = timings, .records = records.items, .cycles = timings[timings.len - 1].w };
    for (records.items) |record| {
        out.stalls[record.cause] += record.cycles;
        out.events[record.cause] += 1;
    }
    return out;
}
