const std = @import("std");
pub const Text = []const u8;
pub const Value = struct {
    kind: enum { number, string, strnum, uninitialized } = .uninitialized, n: i64 = 0, s: Text = "",
    pub fn number(n: i64) Value { return .{ .kind = .number, .n = n }; }
    pub fn string(s: Text) Value { return .{ .kind = .string, .s = s }; }
    pub fn input(s: Text) Value { return .{ .kind = if (numeric(s)) .strnum else .string, .s = s, .n = numericPrefix(s) }; }
    pub fn num(v: Value) i64 { return if (v.kind == .number or v.kind == .strnum) v.n else numericPrefix(v.s); }
    pub fn text(v: Value, a: std.mem.Allocator) !Text { return if (v.kind == .number) std.fmt.allocPrint(a, "{d}", .{v.n}) else v.s; }
    pub fn truth(v: Value) bool { return if (v.kind == .number or v.kind == .strnum) v.n != 0 else v.s.len != 0; }
};
pub fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn numeric(s: Text) bool { const t = std.mem.trim(u8, s, " \t\n"); var p: usize = 0; if (t.len > 0 and (t[0] == '+' or t[0] == '-')) p += 1; if (p == t.len) return false; for (t[p..]) |c| if (!std.ascii.isDigit(c)) return false; return true; }
fn numericPrefix(s: Text) i64 { var p: usize = 0; while (p < s.len and (s[p] == ' ' or s[p] == 9 or s[p] == 10)) p += 1; const start = p; if (p < s.len and (s[p] == '+' or s[p] == '-')) p += 1; const digits = p; while (p < s.len and std.ascii.isDigit(s[p])) p += 1; return if (p == digits) 0 else std.fmt.parseInt(i64, s[start..p], 10) catch unreachable; }
pub fn compare(a: std.mem.Allocator, x: Value, y: Value) !std.math.Order { return if (x.kind != .string and y.kind != .string) std.math.order(x.num(), y.num()) else std.mem.order(u8, try x.text(a), try y.text(a)); }
pub fn integerKey(s: Text) ?i64 { if (eq(s, "0")) return 0; const start: usize = @intFromBool(s.len > 0 and s[0] == '-'); if (start == s.len or s[start] < '1' or s[start] > '9') return null; for (s[start..]) |c| if (!std.ascii.isDigit(c)) return null; return std.fmt.parseInt(i64, s, 10) catch null; }
pub fn keyLess(_: void, x: Text, y: Text) bool { const a = integerKey(x); const b = integerKey(y); if (a != null and b != null) return a.? < b.?; if (a != null or b != null) return a != null; return std.mem.order(u8, x, y) == .lt; }
pub fn split(a: std.mem.Allocator, s: Text, separator: Text) ![]const Text {
    var pieces: std.ArrayList(Text) = .empty; if (s.len == 0) return pieces.items;
    if (eq(separator, " ")) { var words = std.mem.tokenizeAny(u8, s, " \t\n"); while (words.next()) |piece| try pieces.append(a, piece); }
    else if (separator.len == 0) { for (0..s.len) |i| try pieces.append(a, s[i..i + 1]); }
    else { var words = std.mem.splitSequence(u8, s, separator); while (words.next()) |piece| try pieces.append(a, piece); } return pieces.items;
}
pub const Record = struct {
    zero: Value = Value.string(""), fields: std.ArrayList(Value) = .empty,
    pub fn set(r: *Record, a: std.mem.Allocator, s: Text, fs: Text) !void { r.zero = Value.input(s); r.fields = .empty; for (try split(a, s, fs)) |piece| try r.fields.append(a, Value.input(piece)); }
    pub fn get(r: *Record, index: usize) Value { return if (index == 0) r.zero else if (index <= r.fields.items.len) r.fields.items[index - 1] else .{}; }
    pub fn resize(r: *Record, a: std.mem.Allocator, n: usize) !void { while (r.fields.items.len < n) try r.fields.append(a, Value.string("")); r.fields.items.len = n; }
    pub fn rebuild(r: *Record, a: std.mem.Allocator, ofs: Text) !void { var bytes: std.ArrayList(u8) = .empty; for (r.fields.items, 0..) |v, i| { if (i > 0) try bytes.appendSlice(a, ofs); try bytes.appendSlice(a, try v.text(a)); } r.zero = Value.input(bytes.items); }
};
pub fn shown(a: std.mem.Allocator, v: Value) !Text {
    if (v.kind == .uninitialized) return "(uninitialized)"; if (v.kind == .number) return v.text(a);
    var b: std.ArrayList(u8) = .empty; try b.append(a, '"');
    for (v.s) |c| switch (c) { '"' => try b.appendSlice(a, "\\\""), '\\' => try b.appendSlice(a, "\\\\"), 10 => try b.appendSlice(a, "\\n"), 9 => try b.appendSlice(a, "\\t"), else => if (c < 32 or c > 126) { try b.appendSlice(a, try std.fmt.allocPrint(a, "\\{o:0>3}", .{c})); } else try b.append(a, c) };
    try b.append(a, '"'); if (v.kind == .strnum) try b.appendSlice(a, " (strnum)"); return b.items;
}
