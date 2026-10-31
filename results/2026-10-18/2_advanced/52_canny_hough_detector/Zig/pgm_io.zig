const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}
pub const Point = struct { x: i64, y: i64 };
pub const offsets = [_]i64{ -1, 0, 1 };
pub const Image = struct {
    width: usize,
    height: usize,
    data: []i64,
    pub fn init(width: usize, height: usize) Image {
        const data = alloc(i64, width * height);
        @memset(data, 0);
        return .{ .width = width, .height = height, .data = data };
    }
    pub fn inside(self: Image, point: Point) bool {
        return point.x >= 0 and point.x < n(self.width) and point.y >= 0 and point.y < n(self.height);
    }
    pub fn at(self: Image, point: Point) i64 {
        return self.data[u(point.y) * self.width + u(point.x)];
    }
    pub fn set(self: Image, point: Point, value: i64) void {
        self.data[u(point.y) * self.width + u(point.x)] = value;
    }
};
pub const Params = struct { ks: i64, kernel: []const i64, divisor: i64, low: i64, high: i64, r_min: i64,
     r_max: i64, circle_percent: i64, circle_count: i64, rho_step: i64, vote_threshold: i64, line_count: i64,
     tolerance: i64, max_gap: i64, min_length: i64, junction_distance: i64, junction_angle: i64, angle_tolerance: i64,
     square_tolerance: i64, margin: i64, harris_window: i64, harris_threshold: i64, corner_count: i64,
     match_distance: i64, overlay_divisor: i64 };
pub const Trig = [180][2]i64;
pub const Input = struct { image: Image, params: Params, trig: Trig };
fn value(line: []const u8) i64 {
    return number(words(line)[1]);
}
pub fn load(io: std.Io) !Input {
    const lines = try readLines(io, "input/image.pgm");
    const dimensions = words(lines[1]);
    const image = Image.init(u(number(dimensions[0])), u(number(dimensions[1])));
    for (lines[3..], 0..) |line, y| for (words(line), 0..) |field, x| {
        image.data[y * image.width + x] = number(field);
    };
    var trig: Trig = undefined;
    for (try readLines(io, "input/trig.txt"), 0..) |line, t| {
        const fields = words(line);
        trig[t] = .{ number(fields[1]), number(fields[2]) };
    }
    const settings = try readLines(io, "input/params.txt");
    const coefficients = words(settings[1]);
    const kernel = alloc(i64, coefficients.len - 1);
    for (coefficients[1..], kernel) |field, *coefficient| coefficient.* = number(field);
    return .{ .image = image, .trig = trig, .params = .{ .ks = value(settings[0]), .kernel = kernel,
         .divisor = value(settings[2]), .low = value(settings[3]), .high = value(settings[4]), .r_min = value(settings[5]),
         .r_max = value(settings[6]), .circle_percent = value(settings[7]), .circle_count = value(settings[8]),
         .rho_step = value(settings[9]), .vote_threshold = value(settings[10]), .line_count = value(settings[11]),
         .tolerance = value(settings[12]), .max_gap = value(settings[13]), .min_length = value(settings[14]),
         .junction_distance = value(settings[15]), .junction_angle = value(settings[16]), .angle_tolerance = value(settings[17]),
         .square_tolerance = value(settings[18]), .margin = value(settings[19]), .harris_window = value(settings[20]),
         .harris_threshold = value(settings[21]), .corner_count = value(settings[22]), .match_distance = value(settings[23]),
         .overlay_divisor = value(settings[24]) } };
}
pub fn writePgm(io: std.Io, name: []const u8, image: Image) !void {
    var out: Text = .{};
    out.add("P2\n{d} {d}\n255\n", .{ image.width, image.height });
    for (0..image.height) |y| {
        for (0..image.width) |x| out.add("{s}{d}", .{ if (x == 0) "" else " ", image.data[y * image.width + x] });
        out.add("\n", .{});
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = out.value() });
}
