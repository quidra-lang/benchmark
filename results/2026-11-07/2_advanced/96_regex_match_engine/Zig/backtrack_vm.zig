const std = @import("std");
const chars = @import("charset.zig");
const code = @import("compiler.zig");
pub const Captures = [42]i16;
pub const empty: Captures = @splat(-1);
pub const Result = struct { captures: Captures, q: usize };
const State = struct { p: usize, q: usize, captures: Captures, visited: std.StaticBitSet(300) = std.StaticBitSet(300).initEmpty() };
pub fn consumes(ins: code.Instruction, text: []const u8, q: usize, flags: []const u8) bool {
    if (q >= text.len) return false;
    return switch (ins.op) { .CHAR => chars.same(text[q], @intCast(ins.x), flags), .ANY => text[q] != 10 or std.mem.indexOfScalar(u8, flags, 's') != null, .CLASS => chars.class(ins.set, ins.neg, text[q], flags), else => false };
}
pub const VM = struct {
    a: std.mem.Allocator, program: []const code.Instruction, flags: []const u8, text: []const u8, full: bool, steps: usize = 0,
    pub fn run(vm: *VM, p: usize, q: usize, captures: Captures, partial: bool) anyerror!?Result {
        var stack: std.ArrayList(State) = .empty;
        defer stack.deinit(vm.a);
        try stack.append(vm.a, .{ .p = p, .q = q, .captures = captures });
        while (stack.items.len > 0) {
            var s = stack.pop().?;
            while (true) {
                vm.steps += 1; if (vm.steps > 200000) return error.TooManySteps;
                const ins = vm.program[s.p];
                switch (ins.op) {
                    .CHAR, .ANY, .CLASS => { if (!consumes(ins, vm.text, s.q, vm.flags)) break; s.q += 1; s.p += 1; s.visited = .initEmpty(); },
                    .SPLIT => { if (s.visited.isSet(s.p)) break; s.visited.set(s.p); var alternate = s; alternate.p = ins.y; try stack.append(vm.a, alternate); s.p = ins.x; },
                    .JMP => s.p = ins.x,
                    .SAVE => { s.captures[ins.x] = @intCast(s.q); s.p += 1; },
                    .ASSERT => { if (!chars.assertion(ins.assertion, vm.text, s.q, vm.flags)) break; s.p += 1; },
                    .BACKREF => {
                        const first = s.captures[2 * ins.x]; const last = s.captures[2 * ins.x + 1];
                        if (first < 0 or last < first) break;
                        const start: usize = @intCast(first); const count: usize = @intCast(last - first);
                        if (s.q + count > vm.text.len) break;
                        var valid = true; for (0..count) |j| if (!chars.same(vm.text[start + j], vm.text[s.q + j], vm.flags)) { valid = false; break; };
                        if (!valid) break; s.q += count; s.p += 1; if (count > 0) s.visited = .initEmpty();
                    },
                    .LOOK => {
                        const found = try vm.run(s.p + 1, s.q, s.captures, true);
                        if (ins.look == .NOT) { if (found != null) break; } else {
                            const result = found orelse break; s.captures = result.captures;
                            if (ins.look == .ATOMIC) { if (result.q > s.q) s.visited = .initEmpty(); s.q = result.q; }
                        }
                        s.p = ins.x;
                    },
                    .MATCH => { if (partial or !vm.full or s.q == vm.text.len) return .{ .captures = s.captures, .q = s.q }; break; },
                }
            }
        }
        return null;
    }
    pub fn search(vm: *VM, start: usize) !?Captures {
        var b = if (vm.full) 0 else start;
        while (b <= vm.text.len) : (b += 1) { if (try vm.run(0, b, empty, false)) |r| return r.captures; if (vm.full) break; }
        return null;
    }
};
