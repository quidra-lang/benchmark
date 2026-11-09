const std = @import("std");
const d = @import("dataset.zig");
pub fn fixedPlaces(value: f64, places: usize) []const u8 { const text = switch (places) { 2 => d.fmt("{d:.2}", .{value}), 6 => d.fmt("{d:.6}", .{value}), else => d.fmt("{d:.4}", .{value}) }; if (text.len > 0 and text[0] == '-') { var zero = true; for (text[1..]) |c| { if (c != '0' and c != '.') zero = false; } if (zero) return text[1..]; } return text; }
pub fn fixed(value: f64) []const u8 { return fixedPlaces(value, 4); }
pub fn optional(value: ?f64) []const u8 { return if (value) |number| fixed(number) else "-"; }
pub fn four(value: f64) f64 { return @round(value * 10000); }
pub fn ratio(numerator: anytype, denominator: anytype) []const u8 { return d.fmt("{d}/{d} {s}", .{ numerator, denominator, fixed(d.real(numerator) / d.real(denominator)) }); }
pub fn fraction(numerator: i64, denominator: i64) []const u8 { if (denominator == 0) return "- -"; var left = numerator; var right = denominator; while (right != 0) { const remainder = @mod(left, right); left = right; right = remainder; } return d.fmt("{d}/{d} {s}", .{ @divTrunc(numerator, left), @divTrunc(denominator, left), fixed(d.real(numerator) / d.real(denominator)) }); }
pub fn write(io: std.Io, name: []const u8, lines: d.Strings) !void { const cwd = std.Io.Dir.cwd(); try cwd.createDirPath(io, "output"); try cwd.writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = d.fmt("{s}\n", .{d.join(lines, "\n")}) }); }
