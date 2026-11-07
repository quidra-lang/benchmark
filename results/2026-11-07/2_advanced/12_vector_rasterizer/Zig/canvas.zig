const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub var backing: std.mem.Allocator = undefined;
pub var scratch: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub const Color = [4]i64;
pub const RGB = [3]i64;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn tempAlloc(comptime T: type, count: usize) []T { return scratch.alloc(T, count) catch @panic("allocation failed"); }
pub fn create(comptime T: type, value: T) *T { const result = allocator.create(T) catch @panic("allocation failed"); result.* = value; return result; }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn push(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(scratch, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn int(value: anytype) i64 { return @intCast(value); }
pub fn index(value: i64) usize { return @intCast(value); }
pub fn abs(value: i64) i64 { return if (value < 0) -value else value; }
pub fn number(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn split(text: []const u8, delimiter: u8) Strings { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, delimiter); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn words(text: []const u8) Strings { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.tokenizeScalar(u8, text, ' '); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn lines(text: []const u8) Strings { const result = split(text, '\n'); return result[0..result.len - 1]; }
pub fn join(parts: Strings, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn byte(self: *Text, ch: u8) void { append(u8, &self.data, ch); }
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn content(self: Lines) []const u8 { var text: Text = .{}; for (self.data.items) |line| { text.write(line); text.byte('\n'); } return text.value(); }
};
pub const Point = struct { x: i64, y: i64 };
pub const Segment = struct { first: Point, last: Point };
pub const Rect = struct {
    x0: i64, y0: i64, x1: i64, y1: i64,
    pub fn empty(self: Rect) bool { return self.x0 > self.x1 or self.y0 > self.y1; }
    pub fn contains(self: Rect, point: Point) bool { return point.x >= self.x0 and point.x <= self.x1 and point.y >= self.y0 and point.y <= self.y1; }
    pub fn intersect(self: Rect, other: Rect) Rect { return .{ .x0 = @max(self.x0, other.x0), .y0 = @max(self.y0, other.y0), .x1 = @min(self.x1, other.x1), .y1 = @min(self.y1, other.y1) }; }
};
pub fn boxText(box: ?Rect) []const u8 { const rect = box orelse return "none"; return fmt("{d} {d} {d} {d}", .{ rect.x0, rect.y0, rect.x1, rect.y1 }); }
pub const Mask = struct {
    width: usize, height: usize, bits: []bool,
    pub fn init(width: usize, height: usize) Mask { const bits = tempAlloc(bool, width * height); @memset(bits, false); return .{ .width = width, .height = height, .bits = bits }; }
    pub fn add(self: Mask, point: Point, clip: Rect) void { if (clip.contains(point)) self.bits[index(point.y) * self.width + index(point.x)] = true; }
    pub fn count(self: Mask) usize { var result: usize = 0; for (self.bits) |value| { if (value) result += 1; } return result; }
    pub fn box(self: Mask) ?Rect { var result: ?Rect = null; for (self.bits, 0..) |value, i| { if (!value) continue; const x = int(i % self.width); const y = int(i / self.width); if (result) |*rect| { rect.x0 = @min(rect.x0, x); rect.y0 = @min(rect.y0, y); rect.x1 = @max(rect.x1, x); rect.y1 = @max(rect.y1, y); } else result = .{ .x0 = x, .y0 = y, .x1 = x, .y1 = y }; } return result; }
};
pub fn roundRatio(numerator: i64, denominator: i64) i64 { const n = if (denominator < 0) -numerator else numerator; const d = abs(denominator); return @divFloor(2 * n + d, 2 * d); }
pub fn effectiveAlpha(alpha: i64, opacity: i64) i64 { return roundRatio(alpha * opacity, 255); }
pub const Mode = enum { normal, multiply, screen };
pub const Rule = enum { evenodd, nonzero };
pub const Layer = struct {
    width: usize, height: usize, opacity: i64, mode: Mode, colors: []?Color, lines: []usize,
    pub fn init(width: usize, height: usize, opacity: i64, mode: Mode) Layer { const colors = alloc(?Color, width * height); @memset(colors, null); const origins = alloc(usize, width * height); @memset(origins, 0); return .{ .width = width, .height = height, .opacity = opacity, .mode = mode, .colors = colors, .lines = origins }; }
    pub fn alpha(self: *const Layer, pixel: usize) i64 { const color = self.colors[pixel] orelse return 0; return effectiveAlpha(color[3], self.opacity); }
    pub fn paint(self: *Layer, pixel: usize, color: Color, line: usize) void { self.colors[pixel] = color; self.lines[pixel] = line; }
};
fn blend(mode: Mode, source: i64, value: i64) i64 { return switch (mode) { .normal => source, .multiply => roundRatio(source * value, 255), .screen => 255 - roundRatio((255 - source) * (255 - value), 255) }; }
pub fn composite(layers: []const *Layer, background: Color, width: usize, height: usize) []const RGB { const image = alloc(RGB, width * height); for (image, 0..) |*rgb, pixel| { rgb.* = .{ background[0], background[1], background[2] }; for (layers) |layer| { const color = layer.colors[pixel] orelse continue; const alpha = effectiveAlpha(color[3], layer.opacity); for (0..3) |channel| rgb[channel] = roundRatio(alpha * blend(layer.mode, color[channel], rgb[channel]) + (255 - alpha) * rgb[channel], 255); } } return image; }
