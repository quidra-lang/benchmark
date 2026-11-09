const std = @import("std");
const chars = @import("charset.zig");
const code = @import("compiler.zig");
const back = @import("backtrack_vm.zig");
const Thread = struct { p: usize, captures: back.Captures };
const List = struct { threads: std.ArrayList(Thread) = .empty, marks: std.StaticBitSet(300) = std.StaticBitSet(300).initEmpty() };
pub const VM = struct {
    a: std.mem.Allocator, program: []const code.Instruction, flags: []const u8, text: []const u8, full: bool, steps: usize = 0,
    fn add(vm: *VM, list: *List, p: usize, captures: back.Captures, q: usize) anyerror!void {
        if (list.marks.isSet(p)) return; list.marks.set(p); vm.steps += 1;
        const ins = vm.program[p];
        switch (ins.op) {
            .JMP => try vm.add(list, ins.x, captures, q),
            .SPLIT => { try vm.add(list, ins.x, captures, q); try vm.add(list, ins.y, captures, q); },
            .SAVE => { var copy = captures; copy[ins.x] = @intCast(q); try vm.add(list, p + 1, copy, q); },
            .ASSERT => if (chars.assertion(ins.assertion, vm.text, q, vm.flags)) { try vm.add(list, p + 1, captures, q); },
            else => try list.threads.append(vm.a, .{ .p = p, .captures = captures }),
        }
    }
    pub fn search(vm: *VM, start: usize) !?back.Captures {
        var found: ?back.Captures = null; var list: List = .{}; var q = start;
        defer list.threads.deinit(vm.a);
        while (true) {
            if (found == null and (!vm.full or q == start)) try vm.add(&list, 0, back.empty, q);
            var next: List = .{};
            for (list.threads.items) |thread| {
                vm.steps += 1; const ins = vm.program[thread.p];
                if (ins.op == .MATCH) { if (!vm.full or q == vm.text.len) { found = thread.captures; break; } }
                else if (back.consumes(ins, vm.text, q, vm.flags)) try vm.add(&next, thread.p + 1, thread.captures, q + 1);
            }
            if (q == vm.text.len or (next.threads.items.len == 0 and (found != null or vm.full))) { next.threads.deinit(vm.a); break; }
            list.threads.deinit(vm.a); list = next; q += 1;
        }
        return found;
    }
};
