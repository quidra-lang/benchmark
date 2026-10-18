const std = @import("std");

fn value(token: []const u8, registers: *const [4]i64) i64 {
    if (token.len == 1 and token[0] >= 'A' and token[0] <= 'D')
        return registers[token[0] - 'A'];
    return std.fmt.parseInt(i64, token, 10) catch unreachable;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const program = [_][]const u8{
        "SET A 1",
        "SET B 1",
        "SET D 8",
        "MUL A B",
        "PRINT A",
        "ADD B 1",
        "SUB D 1",
        "JNZ D -4",
        "SET A 1071",
        "SET B 462",
        "SET C A",
        "MOD C B",
        "SET A B",
        "SET B C",
        "JNZ B -4",
        "PRINT A",
        "HALT"
    };
    var registers = [_]i64{ 0 } ** 4;
    var pc: i32 = 0;
    var executed: u32 = 0;
    while (pc >= 0 and pc < @as(i32, @intCast(program.len))) {
        var tokens = std.mem.splitScalar(u8, program[@intCast(pc)], ' ');
        const op = tokens.next().?;
        executed += 1;
        if (std.mem.eql(u8, op, "HALT"))
            break;
        const first = tokens.next().?;
        if (std.mem.eql(u8, op, "PRINT")) {
            try out.print("{d}\n", .{ value(first, &registers) });
            pc += 1;
            continue;
        }
        const second = tokens.next().?;
        if (std.mem.eql(u8, op, "JNZ")) {
            pc += if (value(first, &registers) != 0) try std.fmt.parseInt(i32, second, 10) else 1;
            continue;
        }
        const r = first[0] - 'A';
        const x = value(second, &registers);
        if (std.mem.eql(u8, op, "SET")) {
            registers[r] = x;
        } else if (std.mem.eql(u8, op, "ADD")) {
            registers[r] += x;
        } else if (std.mem.eql(u8, op, "SUB")) {
            registers[r] -= x;
        } else if (std.mem.eql(u8, op, "MUL")) {
            registers[r] *= x;
        } else if (std.mem.eql(u8, op, "MOD")) {
            registers[r] = @mod(registers[r], x);
        }
        pc += 1;
    }
    try out.print("executed: {d}\n", .{ executed });
    try out.flush();
}
