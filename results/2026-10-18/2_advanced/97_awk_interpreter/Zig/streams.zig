const std = @import("std");
const values = @import("values_fields.zig");
pub const Text = values.Text;
pub const Operand = struct { assignment: bool, name: Text, value: Text = "", records: usize = 0 };
pub const Arguments = struct { options: []const Operand, operands: []Operand };
pub fn valid(name: Text) bool { if (name.len == 0 or name[0] == '.') return false; for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '-') return false; return true; }
fn identifier(name: Text) bool { if (name.len == 0 or (!std.ascii.isAlphabetic(name[0]) and name[0] != '_')) return false; for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return false; return true; }
pub fn args(a: std.mem.Allocator, source: Text) !Arguments {
    var options: std.ArrayList(Operand) = .empty; var operands: std.ArrayList(Operand) = .empty; var argument_lines = std.mem.tokenizeScalar(u8, source, '\n');
    while (argument_lines.next()) |line| { if (std.mem.startsWith(u8, line, "-F ")) { try options.append(a, .{ .assignment = true, .name = "FS", .value = line[3..] }); continue; } const option = std.mem.startsWith(u8, line, "-v "); const text = if (option) line[3..] else line; const equal = std.mem.indexOfScalar(u8, text, '='); if (equal != null and identifier(text[0..equal.?])) { const item: Operand = .{ .assignment = true, .name = text[0..equal.?], .value = text[equal.? + 1..] }; if (option) try options.append(a, item) else try operands.append(a, item); } else try operands.append(a, .{ .assignment = false, .name = text }); }
    return .{ .options = options.items, .operands = operands.items };
}
pub fn lines(a: std.mem.Allocator, source: Text) ![]const Text { var result: std.ArrayList(Text) = .empty; var it = std.mem.splitScalar(u8, source, '\n'); while (it.next()) |line| { if (it.index == null and line.len == 0) break; try result.append(a, line); } return result.items; }
pub const Output = struct { name: Text, bytes: std.ArrayList(u8) = .empty, open: bool = true, writes: usize = 0 };
pub const Input = struct { name: Text, records: ?[]const Text = null, cursor: usize = 0, open: bool = false, reads: usize = 0, ever: bool = false };
pub const Streams = struct {
    a: std.mem.Allocator, io: std.Io, stdout: Output = .{ .name = "stdout.txt" }, outputs: std.ArrayList(Output) = .empty, inputs: std.ArrayList(Input) = .empty,
    pub fn readFile(s: *Streams, name: Text) !?[]const Text { if (!valid(name)) return null; const source = std.Io.Dir.cwd().readFileAlloc(s.io, try std.fmt.allocPrint(s.a, "input/{s}", .{name}), s.a, .unlimited) catch |err| switch (err) { error.FileNotFound => return null, else => return err }; return try lines(s.a, source); }
    pub fn getline(s: *Streams, name: Text) !struct { status: i64, line: Text = "" } {
        var index: ?usize = null; for (s.inputs.items, 0..) |in, i| if (values.eq(in.name, name)) { index = i; break; };
        if (index == null) { index = s.inputs.items.len; try s.inputs.append(s.a, .{ .name = name }); }
        const input = &s.inputs.items[index.?]; if (!input.open) { input.records = try s.readFile(name); input.cursor = 0; input.open = input.records != null; input.ever = input.ever or input.open; }
        const records = input.records orelse return .{ .status = -1 }; if (input.cursor == records.len) return .{ .status = 0 }; const line = records[input.cursor]; input.cursor += 1; input.reads += 1; return .{ .status = 1, .line = line };
    }
    pub fn write(s: *Streams, name: ?Text, append: bool, text: Text) !void {
        if (name == null) { try s.stdout.bytes.appendSlice(s.a, text); s.stdout.writes += 1; return; }
        var index: ?usize = null; for (s.outputs.items, 0..) |out, i| if (values.eq(out.name, name.?)) { index = i; break; };
        if (index == null) { index = s.outputs.items.len; try s.outputs.append(s.a, .{ .name = name.? }); }
        const out = &s.outputs.items[index.?]; if (!out.open and !append) out.bytes.clearRetainingCapacity(); out.open = true; try out.bytes.appendSlice(s.a, text); out.writes += 1;
    }
    pub fn close(s: *Streams, name: Text) i64 { var closed = false; for (s.outputs.items) |*out| if (out.open and values.eq(out.name, name)) { out.open = false; closed = true; }; for (s.inputs.items) |*in| if (in.open and values.eq(in.name, name)) { in.open = false; closed = true; }; return if (closed) 0 else -1; }
    pub fn save(s: *Streams, stats: Text) !void { const file = try std.Io.Dir.cwd().createFile(s.io, "output/stdout.txt", .{}); defer file.close(s.io); try file.writeStreamingAll(s.io, s.stdout.bytes.items); const st = try std.Io.Dir.cwd().createFile(s.io, "output/stats.txt", .{}); defer st.close(s.io); try st.writeStreamingAll(s.io, stats); for (s.outputs.items) |out| { const f = try std.Io.Dir.cwd().createFile(s.io, try std.fmt.allocPrint(s.a, "output/{s}", .{out.name}), .{}); defer f.close(s.io); try f.writeStreamingAll(s.io, out.bytes.items); } }
};
