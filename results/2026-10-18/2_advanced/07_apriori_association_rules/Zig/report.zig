const std = @import("std");
const b = @import("baskets.zig");
const r = @import("rules.zig");
pub fn fraction(value: r.Fraction) []const u8 {
    const numerator: i64 = @intCast(@abs(value.n)); const scaled = @divTrunc(10000 * numerator, value.d);
    return b.fmt("{s}{d}/{d}={s}{d}.{d:0>4}", .{ if (value.n < 0) "-" else "", numerator, value.d, if (value.n < 0 and scaled > 0) "-" else "", @divTrunc(scaled, 10000), @mod(scaled, 10000) });
}
pub fn percent(part: i64, whole: i64) []const u8 { const scaled = @divTrunc(10000 * part, whole); return b.fmt("{d}.{d:0>2}%", .{ @divTrunc(scaled, 100), @mod(scaled, 100) }); }
pub fn money(cents: i64) []const u8 { return b.fmt("{d}.{d:0>2}", .{ @divTrunc(cents, 100), @mod(cents, 100) }); }
pub fn itemset(mask: u128, names: b.Strings) []const u8 { var parts: std.ArrayList([]const u8) = .empty; var it = b.iterator(mask); while (it.next()) |code| b.append([]const u8, &parts, names[code]); return b.join(parts.items, "+"); }
pub fn arrow(rule: r.Rule, names: b.Strings) []const u8 { return b.fmt("{s} -> {s}", .{ itemset(rule.x, names), itemset(rule.y, names) }); }
pub fn csv(rules: []const r.Rule, names: b.Strings) b.Strings {
    var lines: std.ArrayList([]const u8) = .empty; b.append([]const u8, &lines, "rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement");
    for (rules, 1..) |rule, rank| b.append([]const u8, &lines, b.fmt("{d},{s},{s},{d},{s},{s},{s},{s},{s},{s}", .{ rank, itemset(rule.x, names), itemset(rule.y, names), rule.count, fraction(rule.support), fraction(rule.confidence), fraction(rule.lift), fraction(rule.leverage), if (rule.conviction) |value| fraction(value) else "INF", fraction(rule.improvement) }));
    return lines.items;
}
pub fn write(io: std.Io, name: []const u8, lines: b.Strings) !void { const cwd = std.Io.Dir.cwd(); try cwd.createDirPath(io, "output"); try cwd.writeFile(io, .{ .sub_path = b.fmt("output/{s}", .{name}), .data = if (lines.len == 0) "" else b.fmt("{s}\n", .{b.join(lines, "\n")}) }); }
