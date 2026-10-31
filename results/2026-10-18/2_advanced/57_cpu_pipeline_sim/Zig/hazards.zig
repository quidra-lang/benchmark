const c = @import("trace_io.zig");
pub const Sources = [2]?usize;
pub const Timing = struct { f: i64 = 0, d: i64 = 0, x: i64 = 0, m: i64 = 0, w: i64 = 0 };
pub fn dependencies(instructions: []const c.Instruction) []Sources {
    const out = c.alloc(Sources, instructions.len);
    var last = [_]?usize{null} ** 32;
    for (instructions, 0..) |instruction, i| {
        out[i] = .{ if (instruction.rs1 > 0) last[c.u(instruction.rs1)] else null, if (instruction.rs2 > 0) last[c.u(instruction.rs2)] else null };
        if (instruction.rd > 0) last[c.u(instruction.rd)] = i;
    }
    return out;
}
pub fn idResolved(instruction: c.Instruction, variant: c.Variant) bool {
    return (instruction.kind == .jump and instruction.rs1 < 0) or (instruction.control() and variant.id);
}
pub fn readyCycle(consumer: c.Instruction, producer: c.Instruction, time: Timing, variant: c.Variant) i64 {
    if (!variant.forwarding) return time.w + 1;
    return (if (producer.kind == .load) time.w else time.m) + @as(i64, @intFromBool(idResolved(consumer, variant)));
}
pub fn forwardingPath(consumer: c.Instruction, producer: ?Timing, time: Timing, variant: c.Variant) usize {
    if (producer == null or !variant.forwarding) return 0;
    const early = idResolved(consumer, variant);
    const use = time.x - @as(i64, @intFromBool(early));
    if (producer.?.m == use) return 1;
    if (!early and producer.?.w == use) return 2;
    return 0;
}
