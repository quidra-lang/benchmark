const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};

const max_side = 64;
const max_maxval = 255;
const coordinate_limit = 1000;
const shades = "@#*+=~-:,.";
const histogram_bins = 16;
const bar_length = 32;
const neighborhood_offsets = [_][2]i32{
    .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 },
    .{ -1, 0 },  .{ 0, 0 },  .{ 1, 0 },
    .{ -1, 1 },  .{ 0, 1 },  .{ 1, 1 },
};
const four_neighbors = [_][2]i32{ .{ 0, -1 }, .{ -1, 0 }, .{ 1, 0 }, .{ 0, 1 } };
const eight_neighbors = [_][2]i32{
    .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 }, .{ -1, 0 },
    .{ 1, 0 },   .{ -1, 1 }, .{ 0, 1 },  .{ 1, 1 },
};
const erode_rank = 0;
const median_rank = 4;
const dilate_rank = 8;
const diffusion = [_][3]i32{ .{ 1, 0, 7 }, .{ -1, 1, 3 }, .{ 0, 1, 5 }, .{ 1, 1, 1 } };

const Name = enum {
    NEW,
    OUTPUT,
    INVERT,
    BRIGHTNESS,
    CONTRAST,
    THRESHOLD,
    LEVELS,
    POSTERIZE,
    MAXVAL,
    FLIPH,
    FLIPV,
    ROTATE,
    CROP,
    PAD,
    SCALE,
    SHIFT,
    TILE,
    BLUR,
    GAUSS,
    SHARPEN,
    CONVOLVE,
    SOBEL,
    MEDIAN,
    ERODE,
    DILATE,
    OPEN,
    CLOSE,
    GRADIENT,
    LINE,
    RECT,
    CIRCLE,
    FLOOD,
    HISTOGRAM,
    EQUALIZE,
    LABEL,
    DISTANCE,
    STATS,
    REGION,
    DITHER,
    ASCIIART,
    STORE,
    RECALL,
    DROP,
    BLEND,
    DIFF,
    PASTE,
    SLOTS,
    INFO,
    UNDO,
    REDO,
};

fn pattern(name: Name) []const u8 {
    return switch (name) {
        .BRIGHTNESS, .THRESHOLD, .POSTERIZE, .MAXVAL, .ROTATE, .LABEL, .DISTANCE => "i",
        .CONTRAST, .LEVELS, .PAD, .SCALE, .TILE => "ii",
        .SHIFT, .FLOOD => "iii",
        .NEW, .CROP, .CIRCLE, .REGION => "iiii",
        .LINE, .RECT => "iiiii",
        .CONVOLVE => "iiiiiiiiii",
        .STORE, .RECALL, .DROP, .DIFF => "n",
        .BLEND, .PASTE => "nii",
        else => "",
    };
}

fn needsImage(name: Name) bool {
    return switch (name) {
        .NEW, .RECALL, .DROP, .SLOTS, .INFO, .UNDO, .REDO => false,
        else => true,
    };
}

fn usesSlot(name: Name) bool {
    return switch (name) {
        .RECALL, .DROP, .BLEND, .DIFF, .PASTE => true,
        else => false,
    };
}

const Point = struct { x: i32, y: i32 };
const Area = struct { left: usize, top: usize, width: usize, height: usize };
const Kernel = struct { weights: [9]i32, divisor: i32 };

const Command = struct {
    name: Name,
    numbers: [10]i32 = undefined,
    slot: []const u8 = "",
    fill: bool,
};

fn signed(value: usize) i32 {
    return @intCast(value);
}

fn absolute(value: i32) i32 {
    return @intCast(@abs(value));
}

fn between(value: i32, low: i32, high: i32) bool {
    return low <= value and value <= high;
}

fn withinLimit(values: []const i32) bool {
    for (values) |value| {
        if (!between(value, -coordinate_limit, coordinate_limit)) return false;
    }
    return true;
}

fn allDigits(word: []const u8) bool {
    if (word.len == 0) return false;
    for (word) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn isIntegerWord(word: []const u8) bool {
    if (std.mem.eql(u8, word, "0")) return true;
    const digits = if (std.mem.startsWith(u8, word, "-")) word[1..] else word;
    return allDigits(digits) and digits.len <= 7 and digits[0] != '0';
}

fn isNameWord(word: []const u8) bool {
    if (word.len < 1 or word.len > 8) return false;
    for (word) |c| {
        if (!std.ascii.isLower(c)) return false;
    }
    return true;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

const Image = struct {
    width: usize,
    height: usize,
    maxval: i32,
    pixels: []i32,

    fn blank(gpa: Allocator, width: usize, height: usize, maxval: i32) Allocator.Error!Image {
        const pixels = try gpa.alloc(i32, width * height);
        return .{ .width = width, .height = height, .maxval = maxval, .pixels = pixels };
    }

    fn alike(image: Image, gpa: Allocator) Allocator.Error!Image {
        return blank(gpa, image.width, image.height, image.maxval);
    }

    fn index(image: Image, x: i32, y: i32) usize {
        return @intCast(y * signed(image.width) + x);
    }

    fn get(image: Image, x: usize, y: usize) i32 {
        return image.pixels[y * image.width + x];
    }

    fn at(image: Image, x: i32, y: i32) i32 {
        return image.pixels[image.index(x, y)];
    }

    fn set(image: Image, x: usize, y: usize, value: i32) void {
        image.pixels[y * image.width + x] = value;
    }

    fn row(image: Image, y: usize) []const i32 {
        return image.pixels[y * image.width ..][0..image.width];
    }

    fn contains(image: Image, x: i32, y: i32) bool {
        return between(x, 0, signed(image.width) - 1) and between(y, 0, signed(image.height) - 1);
    }

    fn clamp(image: Image, value: i32) i32 {
        return std.math.clamp(value, 0, image.maxval);
    }

    fn neighborhood(image: Image, x: usize, y: usize) [9]i32 {
        var values: [9]i32 = undefined;
        for (neighborhood_offsets, &values) |offset, *value| {
            const nx = std.math.clamp(signed(x) + offset[0], 0, signed(image.width) - 1);
            const ny = std.math.clamp(signed(y) + offset[1], 0, signed(image.height) - 1);
            value.* = image.at(nx, ny);
        }
        return values;
    }

    fn checksum(image: Image) i64 {
        var total: i64 = 0;
        for (image.pixels, 1..) |value, position| total += @as(i64, @intCast(position)) * value;
        return total;
    }

    pub fn format(image: Image, writer: *Writer) Writer.Error!void {
        try writer.print("{d}x{d} maxval {d} checksum {d}", .{
            image.width, image.height, image.maxval, image.checksum(),
        });
    }
};

fn rotated(gpa: Allocator, image: Image, angle: i32) Allocator.Error!Image {
    const width = image.width;
    const height = image.height;
    const result = if (angle == 180)
        try image.alike(gpa)
    else
        try Image.blank(gpa, height, width, image.maxval);
    for (0..result.height) |y| {
        for (0..result.width) |x| {
            result.set(x, y, switch (angle) {
                90 => image.get(y, height - 1 - x),
                180 => image.get(width - 1 - x, height - 1 - y),
                else => image.get(width - 1 - y, x),
            });
        }
    }
    return result;
}

fn cropped(gpa: Allocator, image: Image, area: Area) Allocator.Error!Image {
    const result = try Image.blank(gpa, area.width, area.height, image.maxval);
    for (0..area.height) |j| {
        for (0..area.width) |i| result.set(i, j, image.get(area.left + i, area.top + j));
    }
    return result;
}

fn translated(
    gpa: Allocator,
    image: Image,
    width: usize,
    height: usize,
    dx: i32,
    dy: i32,
    fill: i32,
) Allocator.Error!Image {
    const result = try Image.blank(gpa, width, height, image.maxval);
    for (0..height) |y| {
        for (0..width) |x| {
            const source_x = signed(x) - dx;
            const source_y = signed(y) - dy;
            const inside = image.contains(source_x, source_y);
            result.set(x, y, if (inside) image.at(source_x, source_y) else fill);
        }
    }
    return result;
}

fn scaled(
    gpa: Allocator,
    image: Image,
    width: usize,
    height: usize,
    numerator: usize,
    denominator: usize,
) Allocator.Error!Image {
    const result = try Image.blank(gpa, width, height, image.maxval);
    for (0..height) |y| {
        const source_y = (2 * y + 1) * denominator / (2 * numerator);
        for (0..width) |x| {
            const source_x = (2 * x + 1) * denominator / (2 * numerator);
            result.set(x, y, image.get(source_x, source_y));
        }
    }
    return result;
}

fn convolution(gpa: Allocator, image: Image, kernel: [9]i32, divisor: i32) Allocator.Error!Image {
    const result = try image.alike(gpa);
    for (0..image.height) |y| {
        for (0..image.width) |x| {
            var total: i32 = 0;
            for (kernel, image.neighborhood(x, y)) |weight, value| total += weight * value;
            result.set(x, y, image.clamp(@divFloor(total, divisor)));
        }
    }
    return result;
}

fn rankFiltered(gpa: Allocator, image: Image, rank: usize) Allocator.Error!Image {
    const result = try image.alike(gpa);
    for (0..image.height) |y| {
        for (0..image.width) |x| {
            var values = image.neighborhood(x, y);
            std.mem.sort(i32, &values, {}, std.sort.asc(i32));
            result.set(x, y, values[rank]);
        }
    }
    return result;
}

fn sobelEdges(gpa: Allocator, image: Image) Allocator.Error!Image {
    const result = try image.alike(gpa);
    for (0..image.height) |y| {
        for (0..image.width) |x| {
            const q = image.neighborhood(x, y);
            const gx = (q[2] + 2 * q[5] + q[8]) - (q[0] + 2 * q[3] + q[6]);
            const gy = (q[6] + 2 * q[7] + q[8]) - (q[0] + 2 * q[1] + q[2]);
            result.set(x, y, image.clamp(absolute(gx) + absolute(gy)));
        }
    }
    return result;
}

fn linePoints(gpa: Allocator, x0: i32, y0: i32, x1: i32, y1: i32) Allocator.Error![]const Point {
    const dx = absolute(x1 - x0);
    const dy = -absolute(y1 - y0);
    const step_x: i32 = if (x0 < x1) 1 else -1;
    const step_y: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;
    var x = x0;
    var y = y0;
    var points: std.ArrayList(Point) = .empty;
    while (true) {
        try points.append(gpa, .{ .x = x, .y = y });
        if (x == x1 and y == y1) return points.items;
        const doubled = 2 * err;
        if (doubled >= dy) {
            err += dy;
            x += step_x;
        }
        if (doubled <= dx) {
            err += dx;
            y += step_y;
        }
    }
}

fn rectanglePoints(
    gpa: Allocator,
    image: Image,
    left: i32,
    top: i32,
    width: i32,
    height: i32,
    filled: bool,
) Allocator.Error![]const Point {
    const right = left + width - 1;
    const bottom = top + height - 1;
    var points: std.ArrayList(Point) = .empty;
    var y: i32 = @max(top, 0);
    while (y <= @min(bottom, signed(image.height) - 1)) : (y += 1) {
        var x: i32 = @max(left, 0);
        while (x <= @min(right, signed(image.width) - 1)) : (x += 1) {
            if (filled or x == left or x == right or y == top or y == bottom) {
                try points.append(gpa, .{ .x = x, .y = y });
            }
        }
    }
    return points.items;
}

fn circlePoints(gpa: Allocator, cx: i32, cy: i32, radius: i32) Allocator.Error![]const Point {
    var a = radius;
    var b: i32 = 0;
    var err = 1 - radius;
    var points: std.ArrayList(Point) = .empty;
    while (a >= b) {
        try points.appendSlice(gpa, &[_]Point{
            .{ .x = cx + a, .y = cy + b }, .{ .x = cx + b, .y = cy + a },
            .{ .x = cx - b, .y = cy + a }, .{ .x = cx - a, .y = cy + b },
            .{ .x = cx - a, .y = cy - b }, .{ .x = cx - b, .y = cy - a },
            .{ .x = cx + b, .y = cy - a }, .{ .x = cx + a, .y = cy - b },
        });
        b += 1;
        if (err < 0) {
            err += 2 * b + 1;
        } else {
            a -= 1;
            err += 2 * (b - a) + 1;
        }
    }
    return points.items;
}

fn discPoints(gpa: Allocator, image: Image, outline: []const Point) Allocator.Error![]const Point {
    const Span = struct { low: i32, high: i32 };
    const spans = try gpa.alloc(?Span, image.height);
    @memset(spans, null);
    for (outline) |point| {
        if (point.y < 0 or point.y >= signed(image.height)) continue;
        const span = &spans[@intCast(point.y)];
        span.* = if (span.*) |known|
            .{ .low = @min(known.low, point.x), .high = @max(known.high, point.x) }
        else
            .{ .low = point.x, .high = point.x };
    }
    var points: std.ArrayList(Point) = .empty;
    for (spans, 0..) |maybe_span, y| {
        const span = maybe_span orelse continue;
        var x: i32 = @max(span.low, 0);
        while (x <= @min(span.high, signed(image.width) - 1)) : (x += 1) {
            try points.append(gpa, .{ .x = x, .y = signed(y) });
        }
    }
    return points.items;
}

fn floodPoints(gpa: Allocator, image: Image, x: i32, y: i32) Allocator.Error![]const Point {
    const target = image.at(x, y);
    const visited = try gpa.alloc(bool, image.pixels.len);
    @memset(visited, false);
    visited[image.index(x, y)] = true;
    var stack: std.ArrayList(Point) = .empty;
    try stack.append(gpa, .{ .x = x, .y = y });
    var points: std.ArrayList(Point) = .empty;
    while (stack.pop()) |point| {
        try points.append(gpa, point);
        for (four_neighbors) |offset| {
            const nx = point.x + offset[0];
            const ny = point.y + offset[1];
            if (!image.contains(nx, ny) or image.at(nx, ny) != target) continue;
            const index = image.index(nx, ny);
            if (!visited[index]) {
                visited[index] = true;
                try stack.append(gpa, .{ .x = nx, .y = ny });
            }
        }
    }
    return points.items;
}

fn equalized(gpa: Allocator, image: Image) Allocator.Error!Image {
    const total = signed(image.pixels.len);
    const cdf = try gpa.alloc(i32, @intCast(image.maxval + 1));
    @memset(cdf, 0);
    for (image.pixels) |pixel| cdf[@intCast(pixel)] += 1;
    for (1..cdf.len) |value| cdf[value] += cdf[value - 1];
    const lowest = cdf[@intCast(std.mem.min(i32, image.pixels))];
    if (lowest == total) return image;
    const span = total - lowest;
    const result = try image.alike(gpa);
    for (result.pixels, image.pixels) |*target, pixel| {
        target.* = @divFloor(2 * (cdf[@intCast(pixel)] - lowest) * image.maxval + span, 2 * span);
    }
    return result;
}

fn components(gpa: Allocator, image: Image, threshold: i32) Allocator.Error![]const []const Point {
    const visited = try gpa.alloc(bool, image.pixels.len);
    @memset(visited, false);
    var result: std.ArrayList([]const Point) = .empty;
    for (image.pixels, 0..) |pixel, start| {
        if (pixel < threshold or visited[start]) continue;
        visited[start] = true;
        var stack: std.ArrayList(Point) = .empty;
        try stack.append(gpa, .{
            .x = signed(start % image.width),
            .y = signed(start / image.width),
        });
        var members: std.ArrayList(Point) = .empty;
        while (stack.pop()) |point| {
            try members.append(gpa, point);
            for (eight_neighbors) |offset| {
                const nx = point.x + offset[0];
                const ny = point.y + offset[1];
                if (!image.contains(nx, ny)) continue;
                const index = image.index(nx, ny);
                if (image.pixels[index] >= threshold and !visited[index]) {
                    visited[index] = true;
                    try stack.append(gpa, .{ .x = nx, .y = ny });
                }
            }
        }
        try result.append(gpa, members.items);
    }
    return result.items;
}

fn onBoundary(image: Image, point: Point, threshold: i32) bool {
    for (four_neighbors) |offset| {
        const x = point.x + offset[0];
        const y = point.y + offset[1];
        if (!image.contains(x, y) or image.at(x, y) < threshold) return true;
    }
    return false;
}

fn writeComponent(
    out: *Writer,
    image: Image,
    threshold: i32,
    number: usize,
    members: []const Point,
) Writer.Error!void {
    var low = members[0];
    var high = members[0];
    var sum: Point = .{ .x = 0, .y = 0 };
    var perimeter: usize = 0;
    for (members) |point| {
        low = .{ .x = @min(low.x, point.x), .y = @min(low.y, point.y) };
        high = .{ .x = @max(high.x, point.x), .y = @max(high.y, point.y) };
        sum = .{ .x = sum.x + point.x, .y = sum.y + point.y };
        if (onBoundary(image, point, threshold)) perimeter += 1;
    }
    const area = signed(members.len);
    try out.print("label {d} area {d} perimeter {d} box {d} {d} {d} {d} center {d} {d}\n", .{
        number,                 area,                   perimeter, low.x, low.y, high.x, high.y,
        @divFloor(sum.x, area), @divFloor(sum.y, area),
    });
}

fn distanceMap(gpa: Allocator, image: Image, threshold: i32) Allocator.Error!Image {
    const result = try image.alike(gpa);
    if (std.mem.min(i32, image.pixels) >= threshold) {
        @memset(result.pixels, image.maxval);
        return result;
    }
    const width = image.width;
    const far = signed(width + image.height);
    const distances = result.pixels;
    for (distances, image.pixels) |*distance, pixel| distance.* = if (pixel < threshold) 0 else far;
    for (0..distances.len) |index| {
        if (index % width > 0) {
            distances[index] = @min(distances[index], distances[index - 1] + 1);
        }
        if (index >= width) {
            distances[index] = @min(distances[index], distances[index - width] + 1);
        }
    }
    var index = distances.len;
    while (index > 0) {
        index -= 1;
        if (index % width < width - 1) {
            distances[index] = @min(distances[index], distances[index + 1] + 1);
        }
        if (index + width < distances.len) {
            distances[index] = @min(distances[index], distances[index + width] + 1);
        }
    }
    for (distances) |*distance| distance.* = @min(distance.*, image.maxval);
    return result;
}

fn dithered(gpa: Allocator, image: Image) Allocator.Error!Image {
    const errors = try gpa.dupe(i32, image.pixels);
    const result = try image.alike(gpa);
    for (0..image.height) |y| {
        for (0..image.width) |x| {
            const old = errors[y * image.width + x];
            const new = if (2 * old >= image.maxval) image.maxval else 0;
            result.set(x, y, new);
            const err = old - new;
            for (diffusion) |spread| {
                const nx = signed(x) + spread[0];
                const ny = signed(y) + spread[1];
                if (image.contains(nx, ny)) {
                    errors[image.index(nx, ny)] += @divFloor(err * spread[2], 16);
                }
            }
        }
    }
    return result;
}

const Editor = struct {
    gpa: Allocator,
    out: *Writer,
    current: ?Image = null,
    undo_history: std.ArrayList(Image) = .empty,
    redo_history: std.ArrayList(Image) = .empty,
    slots: std.StringHashMapUnmanaged(Image) = .empty,
    reason: []const u8 = "",

    fn fail(editor: *Editor, comptime reason: []const u8, args: anytype) Error {
        editor.reason = std.fmt.allocPrint(editor.gpa, reason, args) catch return error.OutOfMemory;
        return error.Invalid;
    }

    fn require(editor: *Editor, condition: bool, reason: []const u8) Error!void {
        if (!condition) {
            editor.reason = reason;
            return error.Invalid;
        }
    }

    fn validate(editor: *Editor, condition: bool) Error!void {
        return editor.require(condition, "bad value");
    }

    fn headerValue(
        editor: *Editor,
        words: []const []const u8,
        position: usize,
        limit: usize,
        reason: []const u8,
    ) Error!usize {
        try editor.require(position < words.len, "truncated header");
        const word = words[position];
        try editor.require(allDigits(word), "bad number");
        const value = std.fmt.parseInt(usize, word, 10) catch unreachable;
        try editor.require(1 <= value and value <= limit, reason);
        return value;
    }

    fn readPgm(editor: *Editor, lines: []const []const u8) Error!Image {
        var words: std.ArrayList([]const u8) = .empty;
        for (lines) |text| {
            const content = text[0 .. std.mem.findScalar(u8, text, '#') orelse text.len];
            var tokens = std.mem.tokenizeScalar(u8, content, ' ');
            while (tokens.next()) |word| try words.append(editor.gpa, word);
        }
        const all = words.items;
        try editor.require(all.len > 0 and std.mem.eql(u8, all[0], "P2"), "bad magic");
        const width = try editor.headerValue(all, 1, max_side, "bad size");
        const height = try editor.headerValue(all, 2, max_side, "bad size");
        const maxval: i32 = @intCast(try editor.headerValue(all, 3, max_maxval, "bad maxval"));
        const values = all[4..];
        const total = width * height;
        const pixels = try editor.gpa.alloc(i32, total);
        for (pixels, 0..) |*pixel, index| {
            const x = index % width;
            const y = index / width;
            if (index >= values.len) {
                return editor.fail("too few pixels ({d} of {d})", .{ values.len, total });
            }
            const word = values[index];
            if (!allDigits(word)) return editor.fail("bad pixel at {d},{d}", .{ x, y });
            pixel.* = std.fmt.parseInt(i32, word, 10) catch unreachable;
            if (pixel.* > maxval) return editor.fail("pixel out of range at {d},{d}", .{ x, y });
        }
        if (values.len > total) {
            return editor.fail("too many pixels ({d} of {d})", .{ values.len, total });
        }
        return .{ .width = width, .height = height, .maxval = maxval, .pixels = pixels };
    }

    fn parse(editor: *Editor, words: []const []const u8) Error!Command {
        const name = std.meta.stringToEnum(Name, words[0]) orelse
            return editor.fail("unknown command {s}", .{words[0]});
        const kinds = pattern(name);
        var arguments = words[1..];
        const fill = (name == .RECT or name == .CIRCLE) and arguments.len == kinds.len + 1 and
            std.mem.eql(u8, arguments[arguments.len - 1], "FILL");
        if (fill) arguments = arguments[0 .. arguments.len - 1];
        try editor.require(arguments.len == kinds.len, "bad arguments");
        var command: Command = .{ .name = name, .fill = fill };
        var count: usize = 0;
        for (kinds, arguments) |kind, word| {
            if (kind == 'i') {
                try editor.require(isIntegerWord(word), "bad arguments");
                command.numbers[count] = std.fmt.parseInt(i32, word, 10) catch unreachable;
                count += 1;
            } else {
                try editor.require(isNameWord(word), "bad arguments");
                command.slot = word;
            }
        }
        return command;
    }

    fn execute(editor: *Editor, words: []const []const u8) Error!void {
        editor.run(words) catch |err| {
            if (err != error.Invalid) return err;
            try editor.out.print("error: {s}\n", .{editor.reason});
        };
    }

    fn run(editor: *Editor, words: []const []const u8) Error!void {
        const command = try editor.parse(words);
        if (needsImage(command.name)) try editor.require(editor.current != null, "no image");
        if (usesSlot(command.name) and !editor.slots.contains(command.slot)) {
            return editor.fail("no slot {s}", .{command.slot});
        }
        const gpa = editor.gpa;
        switch (command.name) {
            .NEW => try editor.newImage(command),
            .OUTPUT => try editor.writeImage(),
            .INVERT => try editor.invert(),
            .BRIGHTNESS => try editor.brightness(command),
            .CONTRAST => try editor.contrast(command),
            .THRESHOLD => try editor.thresholdImage(command),
            .LEVELS => try editor.adjustLevels(command),
            .POSTERIZE => try editor.posterize(command),
            .MAXVAL => try editor.changeMaxval(command),
            .FLIPH, .FLIPV => try editor.flip(command.name),
            .ROTATE => try editor.rotate(command),
            .CROP => try editor.crop(command),
            .PAD => try editor.pad(command),
            .SCALE => try editor.scale(command),
            .SHIFT => try editor.shift(command),
            .TILE => try editor.tile(command),
            .BLUR, .GAUSS, .SHARPEN => try editor.kernelFilter(command.name),
            .CONVOLVE => try editor.convolve(command),
            .SOBEL => try editor.commit(try sobelEdges(gpa, editor.current.?)),
            .MEDIAN, .ERODE, .DILATE => try editor.rankFilter(command.name),
            .OPEN, .CLOSE, .GRADIENT => try editor.morphology(command.name),
            .LINE => try editor.drawLine(command),
            .RECT => try editor.drawRect(command),
            .CIRCLE => try editor.drawCircle(command),
            .FLOOD => try editor.floodFill(command),
            .HISTOGRAM => try editor.histogram(),
            .EQUALIZE => try editor.commit(try equalized(gpa, editor.current.?)),
            .LABEL => try editor.label(command),
            .DISTANCE => try editor.distance(command),
            .STATS => try editor.writeStatistics(editor.current.?.pixels, editor.current.?.maxval),
            .REGION => try editor.region(command),
            .DITHER => try editor.commit(try dithered(gpa, editor.current.?)),
            .ASCIIART => try editor.asciiArt(),
            .STORE => try editor.store(command.slot),
            .RECALL => try editor.recall(command.slot),
            .DROP => try editor.drop(command.slot),
            .BLEND => try editor.blend(command),
            .DIFF => try editor.diff(command.slot),
            .PASTE => try editor.paste(command),
            .SLOTS => try editor.listSlots(),
            .INFO => try editor.info(),
            .UNDO => try editor.undo(),
            .REDO => try editor.redo(),
        }
    }

    fn load(editor: *Editor, lines: []const []const u8) Error!void {
        const image = editor.readPgm(lines) catch |err| {
            if (err != error.Invalid) return err;
            return editor.out.print("error: load: {s}\n", .{editor.reason});
        };
        editor.replace(image);
        try editor.out.print("loaded {f}\n", .{image});
    }

    fn replace(editor: *Editor, image: Image) void {
        editor.current = image;
        editor.undo_history.clearRetainingCapacity();
        editor.redo_history.clearRetainingCapacity();
    }

    fn advance(editor: *Editor, image: Image) Allocator.Error!void {
        try editor.undo_history.append(editor.gpa, editor.current.?);
        editor.redo_history.clearRetainingCapacity();
        editor.current = image;
    }

    fn commit(editor: *Editor, image: Image) Error!void {
        try editor.advance(image);
        try editor.out.print("ok {f}\n", .{image});
    }

    fn commitPainted(editor: *Editor, image: Image, painted: usize) Error!void {
        try editor.advance(image);
        try editor.out.print("ok {f} painted {d}\n", .{ image, painted });
    }

    fn copy(editor: *Editor) Allocator.Error!Image {
        var image = editor.current.?;
        image.pixels = try editor.gpa.dupe(i32, image.pixels);
        return image;
    }

    fn paint(editor: *Editor, points: []const Point, value: i32) Error!void {
        const image = editor.current.?;
        const marked = try editor.gpa.alloc(bool, image.pixels.len);
        @memset(marked, false);
        for (points) |point| {
            if (image.contains(point.x, point.y)) marked[image.index(point.x, point.y)] = true;
        }
        const result = try image.alike(editor.gpa);
        var painted: usize = 0;
        for (result.pixels, image.pixels, marked) |*target, pixel, mark| {
            target.* = if (mark) value else pixel;
            painted += @intFromBool(mark);
        }
        try editor.commitPainted(result, painted);
    }

    fn cropArea(editor: *Editor, command: Command) Error!Area {
        const left, const top, const width, const height = command.numbers[0..4].*;
        const image = editor.current.?;
        try editor.validate(left >= 0 and top >= 0 and width >= 1 and height >= 1);
        try editor.validate(left + width <= signed(image.width) and
            top + height <= signed(image.height));
        return .{
            .left = @intCast(left),
            .top = @intCast(top),
            .width = @intCast(width),
            .height = @intCast(height),
        };
    }

    fn matchingSlot(editor: *Editor, slot: []const u8) Error!Image {
        const other = editor.slots.get(slot).?;
        const image = editor.current.?;
        const same_size = other.width == image.width and other.height == image.height;
        try editor.require(same_size, "size mismatch");
        try editor.require(other.maxval == image.maxval, "maxval mismatch");
        return other;
    }

    fn newImage(editor: *Editor, command: Command) Error!void {
        const width, const height, const maxval, const value = command.numbers[0..4].*;
        try editor.validate(between(width, 1, max_side) and between(height, 1, max_side));
        try editor.validate(between(maxval, 1, max_maxval) and between(value, 0, maxval));
        const image = try Image.blank(editor.gpa, @intCast(width), @intCast(height), maxval);
        @memset(image.pixels, value);
        editor.replace(image);
        try editor.out.print("created {f}\n", .{image});
    }

    fn writeImage(editor: *Editor) Error!void {
        const image = editor.current.?;
        try editor.out.print("P2\n{d} {d}\n{d}\n", .{ image.width, image.height, image.maxval });
        for (0..image.height) |y| {
            for (image.row(y), 0..) |value, x| {
                if (x > 0) try editor.out.writeByte(' ');
                try editor.out.print("{d}", .{value});
            }
            try editor.out.writeByte('\n');
        }
    }

    fn invert(editor: *Editor) Error!void {
        const image = try editor.copy();
        for (image.pixels) |*pixel| pixel.* = image.maxval - pixel.*;
        try editor.commit(image);
    }

    fn brightness(editor: *Editor, command: Command) Error!void {
        const delta = command.numbers[0];
        try editor.validate(between(delta, -max_maxval, max_maxval));
        const image = try editor.copy();
        for (image.pixels) |*pixel| pixel.* = image.clamp(pixel.* + delta);
        try editor.commit(image);
    }

    fn contrast(editor: *Editor, command: Command) Error!void {
        const numerator, const denominator = command.numbers[0..2].*;
        try editor.validate(between(numerator, 0, 100) and between(denominator, 1, 100));
        const image = try editor.copy();
        const center = @divFloor(image.maxval + 1, 2);
        for (image.pixels) |*pixel| {
            pixel.* = image.clamp(center + @divFloor((pixel.* - center) * numerator, denominator));
        }
        try editor.commit(image);
    }

    fn thresholdImage(editor: *Editor, command: Command) Error!void {
        const level = command.numbers[0];
        const image = try editor.copy();
        try editor.validate(between(level, 0, image.maxval));
        for (image.pixels) |*pixel| pixel.* = if (pixel.* >= level) image.maxval else 0;
        try editor.commit(image);
    }

    fn adjustLevels(editor: *Editor, command: Command) Error!void {
        const low, const high = command.numbers[0..2].*;
        const image = try editor.copy();
        try editor.validate(0 <= low and low < high and high <= image.maxval);
        for (image.pixels) |*pixel| {
            pixel.* = image.clamp(@divFloor((pixel.* - low) * image.maxval, high - low));
        }
        try editor.commit(image);
    }

    fn posterize(editor: *Editor, command: Command) Error!void {
        const count = command.numbers[0];
        const image = try editor.copy();
        const maxval = image.maxval;
        try editor.validate(between(count, 2, maxval + 1));
        for (image.pixels) |*pixel| {
            pixel.* = @divFloor(@divFloor(pixel.* * count, maxval + 1) * maxval, count - 1);
        }
        try editor.commit(image);
    }

    fn changeMaxval(editor: *Editor, command: Command) Error!void {
        const target = command.numbers[0];
        try editor.validate(between(target, 1, max_maxval));
        var image = try editor.copy();
        const old = image.maxval;
        for (image.pixels) |*pixel| pixel.* = @divFloor(2 * pixel.* * target + old, 2 * old);
        image.maxval = target;
        try editor.commit(image);
    }

    fn flip(editor: *Editor, name: Name) Error!void {
        const image = editor.current.?;
        const width = image.width;
        const height = image.height;
        const result = try image.alike(editor.gpa);
        for (0..height) |y| {
            for (0..width) |x| {
                const value = if (name == .FLIPH)
                    image.get(width - 1 - x, y)
                else
                    image.get(x, height - 1 - y);
                result.set(x, y, value);
            }
        }
        try editor.commit(result);
    }

    fn rotate(editor: *Editor, command: Command) Error!void {
        const angle = command.numbers[0];
        try editor.validate(angle == 90 or angle == 180 or angle == 270);
        try editor.commit(try rotated(editor.gpa, editor.current.?, angle));
    }

    fn pad(editor: *Editor, command: Command) Error!void {
        const border, const value = command.numbers[0..2].*;
        const image = editor.current.?;
        try editor.validate(border >= 1 and between(value, 0, image.maxval));
        const width = signed(image.width) + 2 * border;
        const height = signed(image.height) + 2 * border;
        try editor.require(width <= max_side and height <= max_side, "too large");
        const result = try translated(
            editor.gpa,
            image,
            @intCast(width),
            @intCast(height),
            border,
            border,
            value,
        );
        try editor.commit(result);
    }

    fn scale(editor: *Editor, command: Command) Error!void {
        const numerator, const denominator = command.numbers[0..2].*;
        try editor.validate(between(numerator, 1, 16) and between(denominator, 1, 16));
        const image = editor.current.?;
        const width = @divFloor(signed(image.width) * numerator, denominator);
        const height = @divFloor(signed(image.height) * numerator, denominator);
        try editor.require(width > 0 and height > 0, "too small");
        try editor.require(width <= max_side and height <= max_side, "too large");
        const result = try scaled(
            editor.gpa,
            image,
            @intCast(width),
            @intCast(height),
            @intCast(numerator),
            @intCast(denominator),
        );
        try editor.commit(result);
    }

    fn shift(editor: *Editor, command: Command) Error!void {
        const dx, const dy, const value = command.numbers[0..3].*;
        const image = editor.current.?;
        try editor.validate(withinLimit(&.{ dx, dy }) and between(value, 0, image.maxval));
        const result = try translated(editor.gpa, image, image.width, image.height, dx, dy, value);
        try editor.commit(result);
    }

    fn tile(editor: *Editor, command: Command) Error!void {
        const across, const down = command.numbers[0..2].*;
        try editor.validate(across >= 1 and down >= 1);
        const image = editor.current.?;
        const width = signed(image.width) * across;
        const height = signed(image.height) * down;
        try editor.require(width <= max_side and height <= max_side, "too large");
        const result = try Image.blank(editor.gpa, @intCast(width), @intCast(height), image.maxval);
        for (0..result.height) |y| {
            for (0..result.width) |x| {
                result.set(x, y, image.get(x % image.width, y % image.height));
            }
        }
        try editor.commit(result);
    }

    fn kernelFilter(editor: *Editor, name: Name) Error!void {
        const kernel: Kernel = switch (name) {
            .BLUR => .{ .weights = .{ 1, 1, 1, 1, 1, 1, 1, 1, 1 }, .divisor = 9 },
            .GAUSS => .{ .weights = .{ 1, 2, 1, 2, 4, 2, 1, 2, 1 }, .divisor = 16 },
            else => .{ .weights = .{ 0, -1, 0, -1, 5, -1, 0, -1, 0 }, .divisor = 1 },
        };
        const image = editor.current.?;
        try editor.commit(try convolution(editor.gpa, image, kernel.weights, kernel.divisor));
    }

    fn convolve(editor: *Editor, command: Command) Error!void {
        const kernel = command.numbers[0..9].*;
        const divisor = command.numbers[9];
        for (kernel) |weight| try editor.validate(between(weight, -16, 16));
        try editor.validate(between(divisor, 1, 256));
        try editor.commit(try convolution(editor.gpa, editor.current.?, kernel, divisor));
    }

    fn rankFilter(editor: *Editor, name: Name) Error!void {
        const rank: usize = switch (name) {
            .ERODE => erode_rank,
            .MEDIAN => median_rank,
            else => dilate_rank,
        };
        try editor.commit(try rankFiltered(editor.gpa, editor.current.?, rank));
    }

    fn morphology(editor: *Editor, name: Name) Error!void {
        const gpa = editor.gpa;
        const image = editor.current.?;
        const result = switch (name) {
            .OPEN => try rankFiltered(gpa, try rankFiltered(gpa, image, erode_rank), dilate_rank),
            .CLOSE => try rankFiltered(gpa, try rankFiltered(gpa, image, dilate_rank), erode_rank),
            else => gradient: {
                const dilated = try rankFiltered(gpa, image, dilate_rank);
                const eroded = try rankFiltered(gpa, image, erode_rank);
                for (dilated.pixels, eroded.pixels) |*high, low| high.* -= low;
                break :gradient dilated;
            },
        };
        try editor.commit(result);
    }

    fn drawLine(editor: *Editor, command: Command) Error!void {
        const x0, const y0, const x1, const y1, const value = command.numbers[0..5].*;
        try editor.validate(withinLimit(&.{ x0, y0, x1, y1 }) and
            between(value, 0, editor.current.?.maxval));
        try editor.paint(try linePoints(editor.gpa, x0, y0, x1, y1), value);
    }

    fn drawRect(editor: *Editor, command: Command) Error!void {
        const left, const top, const width, const height, const value = command.numbers[0..5].*;
        const image = editor.current.?;
        try editor.validate(withinLimit(&.{ left, top }));
        try editor.validate(between(width, 1, coordinate_limit) and
            between(height, 1, coordinate_limit));
        try editor.validate(between(value, 0, image.maxval));
        try editor.paint(
            try rectanglePoints(editor.gpa, image, left, top, width, height, command.fill),
            value,
        );
    }

    fn drawCircle(editor: *Editor, command: Command) Error!void {
        const cx, const cy, const radius, const value = command.numbers[0..4].*;
        const image = editor.current.?;
        try editor.validate(withinLimit(&.{ cx, cy }) and between(radius, 0, coordinate_limit));
        try editor.validate(between(value, 0, image.maxval));
        var points = try circlePoints(editor.gpa, cx, cy, radius);
        if (command.fill) points = try discPoints(editor.gpa, image, points);
        try editor.paint(points, value);
    }

    fn floodFill(editor: *Editor, command: Command) Error!void {
        const x, const y, const value = command.numbers[0..3].*;
        const image = editor.current.?;
        try editor.validate(image.contains(x, y) and between(value, 0, image.maxval));
        try editor.paint(try floodPoints(editor.gpa, image, x, y), value);
    }

    fn histogram(editor: *Editor) Error!void {
        const image = editor.current.?;
        const levels: usize = @intCast(image.maxval + 1);
        var lows: [histogram_bins]?usize = @splat(null);
        var highs: [histogram_bins]usize = @splat(0);
        var counts: [histogram_bins]usize = @splat(0);
        for (0..levels) |value| {
            const number = value * histogram_bins / levels;
            if (lows[number] == null) lows[number] = value;
            highs[number] = value;
        }
        for (image.pixels) |pixel| {
            counts[@as(usize, @intCast(pixel)) * histogram_bins / levels] += 1;
        }
        var top: usize = 0;
        for (lows, counts) |low, count| {
            if (low != null) top = @max(top, count);
        }
        for (lows, highs, counts) |maybe_low, high, count| {
            const low = maybe_low orelse continue;
            try editor.out.print("{d:>3}-{d:>3} {d:>4} |", .{ low, high, count });
            try editor.out.splatByteAll('#', count * bar_length / top);
            try editor.out.writeByte('\n');
        }
    }

    fn label(editor: *Editor, command: Command) Error!void {
        const threshold = command.numbers[0];
        const image = editor.current.?;
        try editor.validate(between(threshold, 0, image.maxval));
        const found = try components(editor.gpa, image, threshold);
        try editor.out.print("labels {d}\n", .{found.len});
        for (found, 1..) |members, number| {
            try writeComponent(editor.out, image, threshold, number, members);
        }
    }

    fn distance(editor: *Editor, command: Command) Error!void {
        const threshold = command.numbers[0];
        const image = editor.current.?;
        try editor.validate(between(threshold, 0, image.maxval));
        try editor.commit(try distanceMap(editor.gpa, image, threshold));
    }

    fn writeStatistics(editor: *Editor, values: []const i32, maxval: i32) Error!void {
        const ordered = try editor.gpa.dupe(i32, values);
        std.mem.sort(i32, ordered, {}, std.sort.asc(i32));
        const occurrences = try editor.gpa.alloc(usize, @intCast(maxval + 1));
        @memset(occurrences, 0);
        var sum: i32 = 0;
        for (ordered) |value| {
            occurrences[@intCast(value)] += 1;
            sum += value;
        }
        const count = ordered.len;
        try editor.out.print("min {d} max {d} mean {d} median {d} mode {d}\n", .{
            ordered[0],
            ordered[count - 1],
            @divFloor(sum, signed(count)),
            ordered[(count - 1) / 2],
            std.mem.findMax(usize, occurrences),
        });
    }

    fn crop(editor: *Editor, command: Command) Error!void {
        const area = try editor.cropArea(command);
        try editor.commit(try cropped(editor.gpa, editor.current.?, area));
    }

    fn region(editor: *Editor, command: Command) Error!void {
        const area = try editor.cropArea(command);
        const part = try cropped(editor.gpa, editor.current.?, area);
        try editor.writeStatistics(part.pixels, part.maxval);
    }

    fn asciiArt(editor: *Editor) Error!void {
        const image = editor.current.?;
        const levels: usize = @intCast(image.maxval + 1);
        for (0..image.height) |y| {
            for (image.row(y)) |pixel| {
                try editor.out.writeByte(shades[@as(usize, @intCast(pixel)) * shades.len / levels]);
            }
            try editor.out.writeByte('\n');
        }
    }

    fn store(editor: *Editor, slot: []const u8) Error!void {
        try editor.slots.put(editor.gpa, slot, editor.current.?);
        try editor.out.print("stored {s} {f}\n", .{ slot, editor.current.? });
    }

    fn recall(editor: *Editor, slot: []const u8) Error!void {
        const image = editor.slots.get(slot).?;
        editor.replace(image);
        try editor.out.print("recalled {s} {f}\n", .{ slot, image });
    }

    fn drop(editor: *Editor, slot: []const u8) Error!void {
        _ = editor.slots.remove(slot);
        try editor.out.print("dropped {s}\n", .{slot});
    }

    fn blend(editor: *Editor, command: Command) Error!void {
        const weight, const total = command.numbers[0..2].*;
        try editor.validate(between(weight, 0, total) and between(total, 1, 100));
        const other = try editor.matchingSlot(command.slot);
        const image = try editor.copy();
        for (image.pixels, other.pixels) |*pixel, source| {
            pixel.* = @divFloor(pixel.* * (total - weight) + source * weight, total);
        }
        try editor.commit(image);
    }

    fn diff(editor: *Editor, slot: []const u8) Error!void {
        const other = try editor.matchingSlot(slot);
        const image = try editor.copy();
        for (image.pixels, other.pixels) |*pixel, source| pixel.* = absolute(pixel.* - source);
        try editor.commit(image);
    }

    fn paste(editor: *Editor, command: Command) Error!void {
        const left, const top = command.numbers[0..2].*;
        try editor.validate(withinLimit(&.{ left, top }));
        const other = editor.slots.get(command.slot).?;
        const image = try editor.copy();
        try editor.require(other.maxval == image.maxval, "maxval mismatch");
        var painted: usize = 0;
        for (0..other.height) |j| {
            for (0..other.width) |i| {
                const x = left + signed(i);
                const y = top + signed(j);
                if (image.contains(x, y)) {
                    image.pixels[image.index(x, y)] = other.get(i, j);
                    painted += 1;
                }
            }
        }
        try editor.commitPainted(image, painted);
    }

    fn listSlots(editor: *Editor) Error!void {
        if (editor.slots.count() == 0) try editor.out.writeAll("no slots\n");
        var names: std.ArrayList([]const u8) = .empty;
        var iterator = editor.slots.keyIterator();
        while (iterator.next()) |name| try names.append(editor.gpa, name.*);
        std.mem.sort([]const u8, names.items, {}, lessThan);
        for (names.items) |name| {
            try editor.out.print("{s} {f}\n", .{ name, editor.slots.get(name).? });
        }
    }

    fn info(editor: *Editor) Error!void {
        try editor.out.writeAll("image ");
        if (editor.current) |image| {
            try editor.out.print("{f}", .{image});
        } else {
            try editor.out.writeAll("none");
        }
        try editor.out.print(" undo {d} redo {d} slots {d}\n", .{
            editor.undo_history.items.len, editor.redo_history.items.len, editor.slots.count(),
        });
    }

    fn undo(editor: *Editor) Error!void {
        try editor.require(editor.undo_history.items.len > 0, "nothing to undo");
        try editor.redo_history.append(editor.gpa, editor.current.?);
        editor.current = editor.undo_history.pop().?;
        try editor.out.print("undo {f}\n", .{editor.current.?});
    }

    fn redo(editor: *Editor) Error!void {
        try editor.require(editor.redo_history.items.len > 0, "nothing to redo");
        try editor.undo_history.append(editor.gpa, editor.current.?);
        editor.current = editor.redo_history.pop().?;
        try editor.out.print("redo {f}\n", .{editor.current.?});
    }
};

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var editor: Editor = .{ .gpa = gpa, .out = &output.interface };
    const count = try std.fmt.parseInt(usize, lines.next().?, 10);
    for (0..count) |_| {
        var words: std.ArrayList([]const u8) = .empty;
        var tokens = std.mem.splitScalar(u8, lines.next().?, ' ');
        while (tokens.next()) |word| try words.append(gpa, word);
        if (std.mem.eql(u8, words.items[0], "LOAD")) {
            const data = try gpa.alloc([]const u8, try std.fmt.parseInt(usize, words.items[1], 10));
            for (data) |*line| line.* = lines.next().?;
            try editor.load(data);
        } else {
            try editor.execute(words.items);
        }
    }
    try output.interface.flush();
}
