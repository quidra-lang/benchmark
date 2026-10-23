const std = @import("std");
const core = @import("main.zig");
const parser = @import("ini_parser.zig");
const lexer = @import("lexer.zig");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const State = enum { unseen, active, done };
pub const Expansion = struct { results: []const ?Text, diagnostics: []const core.Diagnostic };
const Expander = struct {
    gpa: Allocator, config: *const core.Configuration,
    results: []?Text, states: []State, cycles: []bool,
    stack: std.ArrayList(usize) = .empty,
    diagnostics: std.ArrayList(core.Diagnostic) = .empty,

    fn report(expander: *Expander, index: usize, code: Text, message: Text) Allocator.Error!void {
        try expander.diagnostics.append(expander.gpa, .{ .origin = expander.config.entries.items[index].definition.origin, .code = code, .message = message });
    }
    fn expand(expander: *Expander, index: usize) Allocator.Error!?Text {
        if (expander.states[index] == .done) return expander.results[index];
        expander.states[index] = .active;
        try expander.stack.append(expander.gpa, index);
        const result = try expander.evaluate(index);
        _ = expander.stack.pop();
        expander.states[index] = .done;
        expander.results[index] = result;
        return result;
    }
    fn evaluate(expander: *Expander, index: usize) Allocator.Error!?Text {
        const entry = expander.config.entries.items[index];
        const value = entry.definition.value;
        var result: std.ArrayList(u8) = .empty;
        var position: usize = 0;
        while (position < value.len) {
            if (value[position] != '$' or position + 1 == value.len or value[position + 1] != '{') {
                try result.append(expander.gpa, if (value[position] == lexer.literal_dollar) '$' else value[position]);
                position += 1;
                continue;
            }
            const close: ?usize = if (std.mem.findScalar(u8, value[position + 2 ..], '}')) |offset| position + 2 + offset else null;
            if (close == null or !parser.isSection(value[position + 2 .. close.?])) {
                try expander.report(index, "E_BAD_REF", try std.fmt.allocPrint(expander.gpa, "{s}: invalid reference", .{entry.key}));
                return null;
            }
            const reference = value[position + 2 .. close.?];
            const target = if (std.mem.findScalar(u8, reference, '.') != null) reference
                else try std.fmt.allocPrint(expander.gpa, "{s}.{s}", .{ core.sectionOf(entry.key), reference });
            const target_index = expander.config.index(target) orelse {
                try expander.report(index, "E_UNDEFINED", try std.fmt.allocPrint(expander.gpa, "{s}: undefined reference {s}", .{ entry.key, target }));
                return null;
            };
            const expanded = if (expander.states[target_index] == .active) cycle: {
                var start: usize = 0;
                while (expander.stack.items[start] != target_index) : (start += 1) {}
                var path: std.ArrayList(Text) = .empty;
                for (expander.stack.items[start..]) |member| {
                    expander.cycles[member] = true;
                    try path.append(expander.gpa, expander.config.entries.items[member].key);
                }
                try path.append(expander.gpa, target);
                try expander.report(target_index, "E_CYCLE", try std.fmt.allocPrint(expander.gpa, "interpolation cycle {s}", .{try std.mem.join(expander.gpa, " -> ", path.items)}));
                break :cycle @as(?Text, null);
            } else try expander.expand(target_index);
            if (expanded) |text| {
                try result.appendSlice(expander.gpa, text);
            } else {
                if (!expander.cycles[index]) try expander.report(index, "E_DEPENDENCY", try std.fmt.allocPrint(expander.gpa, "{s}: depends on failed key {s}", .{ entry.key, target }));
                return null;
            }
            position = close.? + 1;
        }
        return try result.toOwnedSlice(expander.gpa);
    }
};
pub fn expand(gpa: Allocator, config: *const core.Configuration) Allocator.Error!Expansion {
    const length = config.entries.items.len;
    var expander: Expander = .{ .gpa = gpa, .config = config, .results = try gpa.alloc(?Text, length), .states = try gpa.alloc(State, length), .cycles = try gpa.alloc(bool, length) };
    @memset(expander.results, null);
    @memset(expander.states, .unseen);
    @memset(expander.cycles, false);
    for (try config.orderedKeys(gpa)) |key| _ = try expander.expand(config.index(key).?);
    return .{ .results = expander.results, .diagnostics = try expander.diagnostics.toOwnedSlice(gpa) };
}
