const std = @import("std");
const p = @import("pgm_reader.zig");
const threshold = @import("threshold.zig");
const morphology = @import("morphology.zig");
const labeling = @import("labeling.zig");
const report = @import("report.zig");
const Rational = report.Rational;
const Point = p.Point;
const Mask = p.Mask;
const Feature = enum {
    area, x0, y0, x1, y1, width, height, cx, cy, mean, variance, min, max,
    contrast, border, perimeter, chain, straight, diagonal, turns, compactness,
    runs, holes, hole_area, euler, depth, var_x, var_y, cov_xy, hu1, anisotropy,
    extent, mirror_lr, mirror_tb, solidity, feret2, width2, elongation, bays,
    bay_area, skeleton, endpoints, branches,
};
const feature_count = @typeInfo(Feature).@"enum".fields.len;
const orientations = [_][]const u8{ "none", "horizontal", "vertical", "falling", "rising" };
const symbols = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const directions4 = [_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 } };
const directions8 = [_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 1, .y = -1 }, .{ .x = 0, .y = -1 }, .{ .x = -1, .y = -1 }, .{ .x = -1, .y = 0 }, .{ .x = -1, .y = 1 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 } };
const csv_header = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border," ++
    "perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent," ++
    "depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area," ++
    "solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes";

const Element = struct { name: []const u8, offsets: []Point };
const Setting = struct {
    name: []const u8, connectivity: usize, cutoff: []const u8, polarity: []const u8, operations: p.Strings,
    fn method(self: Setting) []const u8 { return if (p.eq(self.cutoff, "otsu") or p.eq(self.cutoff, "isodata")) self.cutoff else "fixed"; }
};
const Parameters = struct { otsu_top: usize, sweep: usize, isotropy: Rational, bay_min: usize, elements: []Element, settings: []Setting };
const Condition = struct {
    feature: ?Feature = null,
    feature_word: []const u8,
    comparison: []const u8,
    text: []const u8,
    value: Rational = .{},
    fn init(parts: p.Strings) Condition {
        var result: Condition = .{ .feature_word = parts[0], .comparison = parts[1], .text = parts[2] };
        inline for (std.meta.fields(Feature)) |field| if (p.eq(parts[0], field.name)) { result.feature = @enumFromInt(field.value); };
        if (result.feature != null) result.value = Rational.parse(parts[2]);
        return result;
    }
    fn holds(self: Condition, region: *const Region) bool {
        const compared = if (self.feature) |feature| region.get(feature).compare(self.value) else std.mem.order(u8, orientations[region.orientation], self.text);
        if (p.eq(self.comparison, "<")) return compared == .lt;
        if (p.eq(self.comparison, "<=")) return compared != .gt;
        if (p.eq(self.comparison, ">")) return compared == .gt;
        if (p.eq(self.comparison, ">=")) return compared != .lt;
        if (p.eq(self.comparison, "=")) return compared == .eq;
        return compared != .eq;
    }
};
const Rule = struct {
    name: []const u8, conditions: []Condition,
    fn matches(self: Rule, region: *const Region) bool {
        for (self.conditions) |condition| if (!condition.holds(region)) return false;
        return true;
    }
};
const Rules = struct { filters: []Condition, classes: []Rule, flags: []Rule, class_names: p.Strings };
const Hole = struct { owner: usize = 0, area: usize = 0, first: usize = 0, x0: usize = 0, y0: usize = 0, x1: usize = 0, y1: usize = 0 };
const Region = struct {
    features: [feature_count]Rational = [_]Rational{.{}} ** feature_count,
    pixels: []usize = &.{},
    count: usize = 0,
    parent: usize = 0,
    depth: usize = 0,
    orientation: usize = 0,
    class_number: usize = 0,
    dropped_by: ?usize = null,
    neighbor: usize = 0,
    hull_doubled: i64 = 0,
    distance: i64 = 0,
    codes: []const u8 = "",
    kept: bool = false,
    flags: [20]bool = [_]bool{false} ** 20,
    skeleton_mask: Mask = undefined,
    fn get(self: *const Region, feature: Feature) Rational { return self.features[@intFromEnum(feature)]; }
    fn int(self: *const Region, feature: Feature) i64 { return self.get(feature).numerator; }
    fn set(self: *Region, feature: Feature, numerator: i64, denominator: i64) void { self.features[@intFromEnum(feature)] = Rational.init(numerator, denominator); }
    fn intText(self: *const Region, feature: Feature) []const u8 { return p.fmt("{d}", .{self.int(feature)}); }
    fn decimal(self: *const Region, feature: Feature, places: usize) []const u8 { return report.decimal(self.get(feature), places); }
};

fn readParameters(io: std.Io) !Parameters {
    var result: Parameters = undefined;
    var elements: std.ArrayList(Element) = .empty;
    var settings: std.ArrayList(Setting) = .empty;
    const source = p.lines(try std.Io.Dir.cwd().readFileAlloc(io, "input/params.txt", p.allocator, .unlimited));
    for (source) |line| {
        const parts = p.split(line, ' ');
        if (p.eq(parts[0], "otsu_top")) result.otsu_top = p.integer(parts[1]) else if (p.eq(parts[0], "sweep")) result.sweep = p.integer(parts[1]) else if (p.eq(parts[0], "isotropy")) result.isotropy = Rational.parse(parts[1]) else if (p.eq(parts[0], "bay_min")) result.bay_min = p.integer(parts[1]) else if (p.eq(parts[0], "element")) {
            var offsets: std.ArrayList(Point) = .empty;
            const ox = p.number(parts[4]);
            const oy = p.number(parts[5]);
            for (parts[6..], 0..) |row, y| {
                for (row, 0..) |symbol, x| if (symbol == '#') { p.append(Point, &offsets, .{ .x = p.n(x) - ox, .y = p.n(y) - oy }); };
            }
            p.append(Element, &elements, .{ .name = parts[1], .offsets = offsets.items });
        } else {
            p.append(Setting, &settings, .{ .name = parts[1], .connectivity = p.integer(parts[2]), .cutoff = parts[3], .polarity = parts[4], .operations = parts[5..] });
        }
    }
    result.elements = elements.items;
    result.settings = settings.items;
    return result;
}

fn readRules(io: std.Io) !Rules {
    var filters: std.ArrayList(Condition) = .empty;
    var classes: std.ArrayList(Rule) = .empty;
    var flags: std.ArrayList(Rule) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    const source = p.lines(try std.Io.Dir.cwd().readFileAlloc(io, "input/rules.txt", p.allocator, .unlimited));
    for (source) |line| {
        const parts = p.split(line, ' ');
        if (p.eq(parts[0], "filter")) p.append(Condition, &filters, Condition.init(parts[1..])) else {
            const conditions = p.alloc(Condition, (parts.len - 2) / 3);
            for (conditions, 0..) |*condition, i| condition.* = Condition.init(parts[2 + 3 * i ..]);
            const rule: Rule = .{ .name = parts[1], .conditions = conditions };
            if (p.eq(parts[0], "class")) {
                p.append(Rule, &classes, rule);
                var present = false;
                for (names.items) |name| if (p.eq(name, rule.name)) { present = true; };
                if (!present) p.append([]const u8, &names, rule.name);
            } else p.append(Rule, &flags, rule);
        }
    }
    p.append([]const u8, &names, "other");
    return .{ .filters = filters.items, .classes = classes.items, .flags = flags.items, .class_names = names.items };
}

fn binarize(image: p.Image, setting: Setting, cutoff: usize) Mask {
    const result = Mask.init(image.width, image.height);
    const bright = p.eq(setting.polarity, "bright");
    for (image.pixels, result.pixels) |value, *pixel| pixel.* = if (bright) value > p.n(cutoff) else value <= p.n(cutoff);
    return result;
}

fn backgroundComponents(mask: Mask, connectivity: usize, edge: *[3073]bool) labeling.Labeling {
    const background = Mask.init(mask.width, mask.height);
    for (mask.pixels, background.pixels) |value, *pixel| pixel.* = !value;
    const labels = labeling.labelComponents(background, connectivity);
    for (0..mask.height) |y| {
        for (0..mask.width) |x| {
            if (x == 0 or y == 0 or x == mask.width - 1 or y == mask.height - 1) edge[labels.pixels[y * mask.width + x]] = true;
        }
    }
    return labels;
}

fn fillHoles(mask: Mask, connectivity: usize) Mask {
    var edge = [_]bool{false} ** 3073;
    const background = backgroundComponents(mask, connectivity, &edge);
    const result = Mask.init(mask.width, mask.height);
    for (mask.pixels, background.pixels, result.pixels) |value, label, *pixel| pixel.* = value or (label > 0 and !edge[label]);
    return result;
}

fn applyOperation(mask: Mask, operation: []const u8, parameters: Parameters, connectivity: usize) Mask {
    if (p.eq(operation, "fill")) return fillHoles(mask, 12 - connectivity);
    const parts = p.split(operation, ':');
    var offsets: []const Point = undefined;
    for (parameters.elements) |element| if (p.eq(element.name, parts[1])) { offsets = element.offsets; break; };
    if (p.eq(parts[0], "erode")) return morphology.erode(mask, offsets);
    if (p.eq(parts[0], "dilate")) return morphology.dilate(mask, offsets);
    if (p.eq(parts[0], "open")) return morphology.opening(mask, offsets);
    return morphology.closing(mask, offsets);
}

fn cross(a: Point, b: Point, point: Point) i64 { return (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x); }
fn squaredDistance(a: Point, b: Point) i64 { const dx = a.x - b.x; const dy = a.y - b.y; return dx * dx + dy * dy; }
fn pointLess(_: void, a: Point, b: Point) bool { return if (a.x != b.x) a.x < b.x else a.y < b.y; }
fn pointEqual(a: Point, b: Point) bool { return a.x == b.x and a.y == b.y; }

fn convexHull(region: *const Region, width: usize) []Point {
    var left = [_]i64{64} ** 48;
    var right = [_]i64{-1} ** 48;
    for (region.pixels) |index| {
        const x = p.n(index % width);
        const y = index / width;
        left[y] = @min(left[y], x);
        right[y] = @max(right[y], x);
    }
    var points: std.ArrayList(Point) = .empty;
    for (0..48) |y| {
        if (right[y] < 0) continue;
        p.append(Point, &points, .{ .x = left[y], .y = p.n(y) });
        p.append(Point, &points, .{ .x = left[y], .y = p.n(y) + 1 });
        p.append(Point, &points, .{ .x = right[y] + 1, .y = p.n(y) });
        p.append(Point, &points, .{ .x = right[y] + 1, .y = p.n(y) + 1 });
    }
    std.mem.sort(Point, points.items, {}, pointLess);
    var unique: usize = 0;
    for (points.items) |point| {
        if (unique == 0 or !pointEqual(point, points.items[unique - 1])) { points.items[unique] = point; unique += 1; }
    }
    const hull = p.alloc(Point, 2 * unique);
    var length: usize = 0;
    for (points.items[0..unique]) |point| {
        while (length >= 2 and cross(hull[length - 2], hull[length - 1], point) <= 0) length -= 1;
        hull[length] = point;
        length += 1;
    }
    const lower = length;
    var i = unique - 1;
    while (i > 0) {
        i -= 1;
        const point = points.items[i];
        while (length > lower and cross(hull[length - 2], hull[length - 1], point) <= 0) length -= 1;
        hull[length] = point;
        length += 1;
    }
    return hull[0 .. length - 1];
}

fn containsCenter(hull: []const Point, x: usize, y: usize) bool {
    const center: Point = .{ .x = 2 * p.n(x) + 1, .y = 2 * p.n(y) + 1 };
    for (hull, 0..) |a, i| {
        const b = hull[(i + 1) % hull.len];
        if (cross(.{ .x = 2 * a.x, .y = 2 * a.y }, .{ .x = 2 * b.x, .y = 2 * b.y }, center) < 0) return false;
    }
    return true;
}

const Analysis = struct {
    image: p.Image, setting: Setting, parameters: Parameters,
    histogram: threshold.Histogram, otsu: threshold.Otsu, isodata: threshold.Isodata, cutoff: usize,
    initial: Mask, final: Mask, morph_counts: [6]usize = [_]usize{0} ** 6,
    labels: labeling.Labeling = undefined, four: usize = 0, eight: usize = 0, bitquad: i64 = 0,
    hole_of: []usize = &.{}, holes: []Hole = &.{}, regions: []Region = &.{},

    fn init(image: p.Image, setting: Setting, parameters: Parameters, rules: Rules) Analysis {
        const hist = threshold.Histogram.init(image);
        const otsu = threshold.otsu(&hist);
        const isodata = threshold.isodata(&hist);
        const cutoff = if (p.eq(setting.cutoff, "otsu")) otsu.cutoff else if (p.eq(setting.cutoff, "isodata")) isodata.cutoff else p.integer(setting.cutoff);
        const initial = binarize(image, setting, cutoff);
        var result: Analysis = .{ .image = image, .setting = setting, .parameters = parameters, .histogram = hist, .otsu = otsu, .isodata = isodata, .cutoff = cutoff, .initial = initial, .final = initial };
        for (setting.operations, 0..) |operation, i| {
            result.final = applyOperation(result.final, operation, parameters, setting.connectivity);
            result.morph_counts[i] = result.final.count();
        }
        result.findRegions();
        for (1..result.regions.len) |number| result.measure(number);
        result.applyRules(rules);
        return result;
    }

    fn labelAt(self: *const Analysis, x: i64, y: i64) i64 {
        if (x < 0 or y < 0 or x >= p.n(self.image.width) or y >= p.n(self.image.height)) return -1;
        return p.n(self.labels.pixels[p.u(y) * self.image.width + p.u(x)]);
    }

    fn findRegions(self: *Analysis) void {
        const width = self.image.width;
        self.labels = labeling.labelComponents(self.final, self.setting.connectivity);
        self.four = labeling.labelComponents(self.final, 4).count;
        self.eight = labeling.labelComponents(self.final, 8).count;
        self.bitquad = labeling.bitQuadEuler(self.final, self.setting.connectivity);
        self.regions = p.alloc(Region, self.labels.count + 1);
        @memset(self.regions, .{});
        for (self.labels.pixels) |label| if (label > 0) { self.regions[label].count += 1; };
        for (self.regions[1..]) |*region| region.pixels = p.alloc(usize, region.count);
        var positions = [_]usize{0} ** 63;
        for (self.labels.pixels, 0..) |label, index| {
            if (label == 0) continue;
            self.regions[label].pixels[positions[label]] = index;
            positions[label] += 1;
        }
        var edge = [_]bool{false} ** 3073;
        const background = backgroundComponents(self.final, 12 - self.setting.connectivity, &edge);
        var numbers = [_]usize{0} ** 3073;
        self.hole_of = p.alloc(usize, self.image.pixels.len);
        @memset(self.hole_of, 0);
        var holes: std.ArrayList(Hole) = .empty;
        p.append(Hole, &holes, .{});
        for (background.pixels, 0..) |label, index| {
            if (label == 0 or edge[label]) continue;
            const x = index % width;
            const y = index / width;
            if (numbers[label] == 0) {
                numbers[label] = holes.items.len;
                p.append(Hole, &holes, .{ .owner = self.labels.pixels[index - width], .first = index, .x0 = x, .y0 = y, .x1 = x, .y1 = y });
            }
            const number = numbers[label];
            self.hole_of[index] = number;
            const hole = &holes.items[number];
            hole.area += 1;
            hole.x0 = @min(hole.x0, x);
            hole.y0 = @min(hole.y0, y);
            hole.x1 = @max(hole.x1, x);
            hole.y1 = @max(hole.y1, y);
        }
        self.holes = holes.items;
        for (self.regions[1..]) |*region| {
            const first = region.pixels[0];
            if (first >= width and self.hole_of[first - width] > 0) {
                region.parent = self.holes[self.hole_of[first - width]].owner;
                region.depth = self.regions[region.parent].depth + 1;
            }
        }
    }

    fn measureBoundary(self: *Analysis, number: usize) void {
        const region = &self.regions[number];
        const connectivity = self.setting.connectivity;
        const complement = 12 - connectivity;
        const neighbors: []const Point = if (complement == 4) &directions4 else &directions8;
        const directions: []const Point = if (connectivity == 4) &directions4 else &directions8;
        var perimeter: i64 = 0;
        var runs: i64 = 0;
        for (region.pixels) |index| {
            const x = p.n(index % self.image.width);
            const y = p.n(index / self.image.width);
            var boundary = false;
            for (neighbors) |offset| if (self.labelAt(x + offset.x, y + offset.y) != p.n(number)) { boundary = true; };
            perimeter += @intFromBool(boundary);
            runs += @intFromBool(self.labelAt(x - 1, y) != p.n(number));
        }
        const start: Point = .{ .x = p.n(region.pixels[0] % self.image.width), .y = p.n(region.pixels[0] / self.image.width) };
        var current = start;
        var first = start;
        var heading = connectivity - 1;
        var codes: p.Text = .{};
        while (true) {
            const search = if (connectivity == 4) (heading + 3) % 4 else (heading + (if (heading % 2 == 0) @as(usize, 7) else 6)) % 8;
            var direction: ?usize = null;
            for (0..connectivity) |offset| {
                const candidate = (search + offset) % connectivity;
                if (self.labelAt(current.x + directions[candidate].x, current.y + directions[candidate].y) == p.n(number)) { direction = candidate; break; }
            }
            const chosen = direction orelse break;
            const next: Point = .{ .x = current.x + directions[chosen].x, .y = current.y + directions[chosen].y };
            if (codes.value().len > 0 and pointEqual(current, start) and pointEqual(next, first)) break;
            if (codes.value().len == 0) first = next;
            codes.add("{d}", .{chosen});
            current = next;
            heading = chosen;
        }
        var straight: i64 = 0;
        var turns: i64 = 0;
        const text = codes.value();
        for (text, 0..) |code, i| {
            if (connectivity == 4 or (code - '0') % 2 == 0) straight += 1;
            if (code != text[(i + text.len - 1) % text.len]) turns += 1;
        }
        const diagonal = p.n(text.len) - straight;
        const length = 5 * straight + 7 * diagonal;
        region.codes = text;
        region.set(.perimeter, perimeter, 1);
        region.set(.runs, runs, 1);
        region.set(.chain, p.n(text.len), 1);
        region.set(.straight, straight, 1);
        region.set(.diagonal, diagonal, 1);
        region.set(.turns, turns, 1);
        region.set(.compactness, length * length, 25 * p.n(region.count));
    }

    fn measureHull(self: *Analysis, number: usize) void {
        const region = &self.regions[number];
        const hull = convexHull(region, self.image.width);
        var doubled: i64 = 0;
        var feret: i64 = 0;
        var width2: Rational = .{};
        for (hull, 0..) |a, i| {
            const b = hull[(i + 1) % hull.len];
            doubled += a.x * b.y - b.x * a.y;
            var reach: i64 = 0;
            for (hull) |point| {
                feret = @max(feret, squaredDistance(a, point));
                reach = @max(reach, p.abs(cross(a, b, point)));
            }
            const candidate = Rational.init(reach * reach, squaredDistance(a, b));
            if (i == 0 or candidate.compare(width2) == .lt) width2 = candidate;
        }
        region.hull_doubled = p.abs(doubled);
        region.set(.solidity, 2 * p.n(region.count), region.hull_doubled);
        region.set(.feret2, feret, 1);
        region.features[@intFromEnum(Feature.width2)] = width2;
        region.set(.elongation, feret * width2.denominator, width2.numerator);
        const concavity = Mask.init(self.image.width, self.image.height);
        var area: i64 = 0;
        for (p.u(region.int(.y0))..p.u(region.int(.y1)) + 1) |y| {
            for (p.u(region.int(.x0))..p.u(region.int(.x1)) + 1) |x| {
                const index = y * self.image.width + x;
                if (self.labels.pixels[index] == 0 and self.hole_of[index] == 0 and containsCenter(hull, x, y)) { concavity.pixels[index] = true; area += 1; }
            }
        }
        const bays = labeling.labelComponents(concavity, 12 - self.setting.connectivity);
        var sizes = [_]usize{0} ** 3073;
        for (bays.pixels) |label| sizes[label] += 1;
        var large: i64 = 0;
        for (sizes[1 .. bays.count + 1]) |size| if (size >= self.parameters.bay_min) { large += 1; };
        region.set(.bays, large, 1);
        region.set(.bay_area, area, 1);
    }

    fn measure(self: *Analysis, number: usize) void {
        const region = &self.regions[number];
        const image = self.image;
        const area = p.n(region.count);
        var sum_x: i64 = 0;
        var sum_y: i64 = 0;
        var sum_x2: i64 = 0;
        var sum_y2: i64 = 0;
        var sum_xy: i64 = 0;
        var sum_i: i64 = 0;
        var sum_i2: i64 = 0;
        var x0 = p.n(image.width);
        var y0 = p.n(image.height);
        var x1: i64 = 0;
        var y1: i64 = 0;
        var minimum = p.n(image.maxval);
        var maximum: i64 = 0;
        var surrounding = [_]bool{false} ** 3072;
        const region_mask = Mask.init(image.width, image.height);
        for (region.pixels) |index| {
            const x = p.n(index % image.width);
            const y = p.n(index / image.width);
            const value = image.pixels[index];
            region_mask.pixels[index] = true;
            x0 = @min(x0, x); y0 = @min(y0, y); x1 = @max(x1, x); y1 = @max(y1, y);
            minimum = @min(minimum, value); maximum = @max(maximum, value);
            sum_x += x; sum_y += y; sum_x2 += x * x; sum_y2 += y * y; sum_xy += x * y;
            sum_i += value; sum_i2 += value * value;
            for (directions8) |offset| {
                const nx = x + offset.x;
                const ny = y + offset.y;
                if (self.labelAt(nx, ny) == 0) surrounding[p.u(ny) * image.width + p.u(nx)] = true;
            }
        }
        var surrounding_count: i64 = 0;
        var surrounding_sum: i64 = 0;
        for (image.pixels, 0..) |value, index| if (surrounding[index]) { surrounding_count += 1; surrounding_sum += value; };
        region.set(.area, area, 1);
        region.set(.x0, x0, 1); region.set(.y0, y0, 1); region.set(.x1, x1, 1); region.set(.y1, y1, 1);
        region.set(.width, x1 - x0 + 1, 1); region.set(.height, y1 - y0 + 1, 1);
        region.set(.border, @intFromBool(x0 == 0 or y0 == 0 or x1 == p.n(image.width) - 1 or y1 == p.n(image.height) - 1), 1);
        region.set(.mean, sum_i, area);
        region.set(.variance, area * sum_i2 - sum_i * sum_i, area * area);
        region.set(.min, minimum, 1); region.set(.max, maximum, 1);
        if (surrounding_count > 0) region.set(.contrast, sum_i * surrounding_count - surrounding_sum * area, area * surrounding_count);
        region.set(.cx, sum_x, area); region.set(.cy, sum_y, area);
        const m20 = area * sum_x2 - sum_x * sum_x;
        const m02 = area * sum_y2 - sum_y * sum_y;
        const m11 = area * sum_xy - sum_x * sum_y;
        region.set(.var_x, m20, area * area); region.set(.var_y, m02, area * area); region.set(.cov_xy, m11, area * area);
        region.set(.hu1, m20 + m02, area * area * area);
        if (m20 + m02 > 0) region.set(.anisotropy, p.abs(m20 - m02) + 2 * p.abs(m11), m20 + m02);
        if (region.get(.anisotropy).compare(self.parameters.isotropy) == .gt) {
            const u = m20 - m02;
            const v = 2 * m11;
            region.orientation = if (p.abs(v) >= p.abs(u)) (if (v > 0) @as(usize, 3) else 4) else (if (u > 0) @as(usize, 1) else 2);
        }
        region.set(.extent, area, (x1 - x0 + 1) * (y1 - y0 + 1));
        var mirror_lr: i64 = 0;
        var mirror_tb: i64 = 0;
        for (region.pixels) |index| {
            const x = p.n(index % image.width);
            const y = p.n(index / image.width);
            mirror_lr += @intFromBool(self.labelAt(x0 + x1 - x, y) == p.n(number));
            mirror_tb += @intFromBool(self.labelAt(x, y0 + y1 - y) == p.n(number));
        }
        region.set(.mirror_lr, mirror_lr, area); region.set(.mirror_tb, mirror_tb, area);
        var holes: i64 = 0;
        var hole_area: i64 = 0;
        for (self.holes[1..]) |hole| if (hole.owner == number) { holes += 1; hole_area += p.n(hole.area); };
        region.set(.holes, holes, 1); region.set(.hole_area, hole_area, 1); region.set(.euler, 1 - holes, 1); region.set(.depth, p.n(region.depth), 1);
        self.measureBoundary(number);
        self.measureHull(number);
        region.skeleton_mask = morphology.thin(region_mask);
        var endpoints: i64 = 0;
        var branches: i64 = 0;
        for (region.pixels) |index| {
            if (!region.skeleton_mask.pixels[index]) continue;
            const crossing = morphology.crossingNumber(region.skeleton_mask, p.n(index % image.width), p.n(index / image.width));
            endpoints += @intFromBool(crossing == 1);
            branches += @intFromBool(crossing >= 3);
        }
        region.set(.skeleton, p.n(region.skeleton_mask.count()), 1);
        region.set(.endpoints, endpoints, 1); region.set(.branches, branches, 1);
    }

    fn applyRules(self: *Analysis, rules: Rules) void {
        for (self.regions[1..]) |*region| {
            for (rules.filters, 0..) |condition, i| if (!condition.holds(region)) { region.dropped_by = i; break; };
            if (region.dropped_by != null) continue;
            region.kept = true;
            var class_name: []const u8 = "other";
            for (rules.classes) |rule| if (rule.matches(region)) { class_name = rule.name; break; };
            for (rules.class_names, 0..) |name, i| if (p.eq(name, class_name)) { region.class_number = i; break; };
            for (rules.flags, 0..) |rule, i| region.flags[i] = rule.matches(region);
        }
        for (self.regions[1..], 1..) |*region, number| {
            if (!region.kept) continue;
            for (self.regions[1..], 1..) |*other, candidate| {
                if (number == candidate or !other.kept) continue;
                const dx = region.int(.x0) + region.int(.x1) - other.int(.x0) - other.int(.x1);
                const dy = region.int(.y0) + region.int(.y1) - other.int(.y0) - other.int(.y1);
                const distance = dx * dx + dy * dy;
                if (region.neighbor == 0 or distance < region.distance) { region.neighbor = candidate; region.distance = distance; }
            }
        }
    }
};

fn meanText(sum: i64, count: usize) []const u8 { return if (count == 0) "-" else report.decimal(Rational.init(sum, p.n(count)), 2); }

fn thresholdLines(analysis: *const Analysis, lines: *p.Lines) void {
    const image = analysis.image;
    const hist = &analysis.histogram;
    lines.add("image {s} size {d} {d} maxval {d}", .{ image.name, image.width, image.height, image.maxval });
    lines.add("histogram pixels {d} min {d} max {d} mean {s} median {d} mode {d} levels {d}", .{
        hist.pixels, hist.minimum, hist.maximum, meanText(hist.total, p.u(hist.pixels)), hist.median, hist.mode, hist.levels,
    });
    var bins: p.Text = .{};
    bins.add("bins {d}", .{hist.bin_width});
    for (hist.bins[0..hist.bin_count]) |count| bins.add(" {d}", .{count});
    lines.write(bins.value());
    lines.add("otsu threshold {d} upper {d} candidates {d}", .{ analysis.otsu.cutoff, analysis.otsu.upper, analysis.otsu.candidates.len });
    for (analysis.otsu.candidates[0..@min(analysis.otsu.candidates.len, analysis.parameters.otsu_top)], 1..) |candidate, rank| {
        const gap = Rational.init(candidate.sum_above * candidate.below - candidate.sum_below * candidate.above, candidate.below * candidate.above);
        lines.add("rank {d} t {d} below {d} above {d} mean_below {s} mean_above {s} gap {s}", .{
            rank, candidate.cutoff, candidate.below, candidate.above,
            meanText(candidate.sum_below, p.u(candidate.below)), meanText(candidate.sum_above, p.u(candidate.above)), report.decimal(gap, 2),
        });
    }
    lines.add("isodata threshold {d} iterations {d}", .{ analysis.isodata.cutoff, analysis.isodata.iterations });
    lines.add("threshold {d} {s} {s} foreground {d}", .{ analysis.cutoff, analysis.setting.method(), analysis.setting.polarity, analysis.initial.count() });
    for (analysis.setting.operations, 0..) |operation, i| lines.add("morph {s} foreground {d}", .{ operation, analysis.morph_counts[i] });
    var cutoff = analysis.parameters.sweep;
    while (cutoff < image.maxval) : (cutoff += analysis.parameters.sweep) {
        const mask = binarize(image, analysis.setting, cutoff);
        lines.add("sweep {d} foreground {d} regions {d}", .{ cutoff, mask.count(), labeling.labelComponents(mask, analysis.setting.connectivity).count });
    }
}

fn mapLines(analysis: *const Analysis, lines: *p.Lines) void {
    const image = analysis.image;
    const headings = [_][]const u8{ "morphology", "labels", "skeleton" };
    for (headings, 0..) |heading, kind| {
        lines.add("{s} {s} {d} {d}", .{ heading, image.name, image.width, image.height });
        for (0..image.height) |y| {
            const row = p.alloc(u8, image.width);
            for (row, 0..) |*symbol, x| {
                const index = y * image.width + x;
                const label = analysis.labels.pixels[index];
                if (kind == 0) {
                    const initial = analysis.initial.pixels[index];
                    const final = analysis.final.pixels[index];
                    symbol.* = if (final) (if (initial) @as(u8, '#') else '+') else (if (initial) @as(u8, '-') else '.');
                } else if (label == 0) {
                    symbol.* = if (analysis.hole_of[index] > 0) ':' else '.';
                } else {
                    const region = &analysis.regions[label];
                    symbol.* = if (kind == 2 and !region.skeleton_mask.pixels[index]) '+' else if (region.kept) symbols[label % 62] else '#';
                }
            }
            lines.write(row);
        }
    }
}

fn csvLines(analysis: *const Analysis, rules: Rules, lines: *p.Lines) void {
    for (analysis.regions[1..], 1..) |*region, number| {
        if (!region.kept) continue;
        var flags: p.Text = .{};
        for (rules.flags, 0..) |rule, i| {
            if (!region.flags[i]) continue;
            if (flags.value().len > 0) flags.write("+");
            flags.write(rule.name);
        }
        const fields = [_][]const u8{
            analysis.image.name, p.fmt("{d}", .{number}), rules.class_names[region.class_number], if (flags.value().len > 0) flags.value() else "-",
            region.intText(.area), region.intText(.x0), region.intText(.y0), region.intText(.x1), region.intText(.y1),
            region.decimal(.cx, 3), region.decimal(.cy, 3), region.decimal(.mean, 2), region.decimal(.variance, 2),
            region.intText(.min), region.intText(.max), region.decimal(.contrast, 2), region.intText(.border),
            region.intText(.perimeter), region.intText(.chain), region.intText(.straight), region.intText(.diagonal), region.intText(.turns),
            region.decimal(.compactness, 3), region.intText(.runs), region.intText(.holes), region.intText(.hole_area), region.intText(.euler),
            if (region.parent > 0) p.fmt("{d}", .{region.parent}) else "-", region.intText(.depth),
            region.decimal(.var_x, 3), region.decimal(.var_y, 3), region.decimal(.cov_xy, 3), region.decimal(.hu1, 4),
            orientations[region.orientation], region.decimal(.anisotropy, 3), region.decimal(.extent, 3), region.decimal(.mirror_lr, 3), region.decimal(.mirror_tb, 3),
            report.hullAreaText(region.hull_doubled), region.decimal(.solidity, 3), region.intText(.feret2), region.decimal(.width2, 3), region.decimal(.elongation, 3),
            region.intText(.bays), region.intText(.bay_area), region.intText(.skeleton), region.intText(.endpoints), region.intText(.branches),
            if (region.neighbor > 0) p.fmt("{d}", .{region.neighbor}) else "-",
            if (region.neighbor > 0) report.decimal(Rational.init(region.distance, 4), 2) else "-", if (region.codes.len > 0) region.codes else "-",
        };
        var row: p.Text = .{};
        for (fields, 0..) |field, i| { if (i > 0) row.write(","); row.write(field); }
        lines.write(row.value());
    }
}

fn treeText(analysis: *const Analysis, number: usize, text: *p.Text) void {
    text.add("{d}", .{number});
    var first = true;
    for (number + 1..analysis.regions.len) |child| {
        if (analysis.regions[child].parent != number) continue;
        text.write(if (first) "(" else " ");
        treeText(analysis, child, text);
        first = false;
    }
    if (!first) text.write(")");
}

fn orientationLine(counts: [5]usize, lines: *p.Lines) void {
    var text: p.Text = .{};
    text.write("orientations");
    for (orientations, counts) |name, count| text.add(" {s} {d}", .{ name, count });
    lines.write(text.value());
}

fn summaryLines(analysis: *const Analysis, rules: Rules, lines: *p.Lines) void {
    const region_count = analysis.labels.count;
    const foreground = analysis.final.count();
    var kept: usize = 0;
    var hole_pixels: usize = 0;
    var depth: usize = 0;
    var largest: usize = 0;
    var smallest: usize = 0;
    var classes = [_]usize{0} ** 21;
    var flags = [_]usize{0} ** 20;
    var orientation_counts = [_]usize{0} ** 5;
    var area: i64 = 0;
    var foreground_sum: i64 = 0;
    var background_sum: i64 = 0;
    for (analysis.image.pixels, analysis.final.pixels) |value, pixel| {
        if (pixel) foreground_sum += value else background_sum += value;
    }
    for (analysis.regions[1..], 1..) |*region, number| {
        depth = @max(depth, region.depth);
        if (!region.kept) continue;
        kept += 1;
        area += p.n(region.count);
        classes[region.class_number] += 1;
        orientation_counts[region.orientation] += 1;
        for (rules.flags, 0..) |_, i| flags[i] += @intFromBool(region.flags[i]);
        if (largest == 0 or region.count > analysis.regions[largest].count) largest = number;
        if (smallest == 0 or region.count < analysis.regions[smallest].count) smallest = number;
    }
    for (analysis.holes[1..]) |hole| hole_pixels += hole.area;
    lines.add("image {s}", .{analysis.image.name});
    lines.add("threshold {d} {s} {s} conn {d}", .{ analysis.cutoff, analysis.setting.method(), analysis.setting.polarity, analysis.setting.connectivity });
    lines.add("foreground {d} {d}", .{ analysis.initial.count(), foreground });
    lines.add("regions {d} provisional {d} kept {d} dropped {d}", .{ region_count, analysis.labels.provisional, kept, region_count - kept });
    lines.add("connectivity four {d} eight {d}", .{ analysis.four, analysis.eight });
    lines.add("holes {d} hole_pixels {d} euler {d} bitquad {d}", .{ analysis.holes.len - 1, hole_pixels, p.n(region_count) - p.n(analysis.holes.len - 1), analysis.bitquad });
    for (analysis.holes[1..], 1..) |hole, number| lines.add("hole {d} owner {d} area {d} box {d} {d} {d} {d}", .{ number, hole.owner, hole.area, hole.x0, hole.y0, hole.x1, hole.y1 });
    lines.add("depth_max {d}", .{depth});
    var tree: p.Text = .{};
    tree.write("tree");
    for (analysis.regions[1..], 1..) |*region, number| {
        if (region.parent != 0) continue;
        tree.write(" ");
        treeText(analysis, number, &tree);
    }
    lines.write(tree.value());
    lines.add("intensity foreground {s} background {s}", .{ meanText(foreground_sum, foreground), meanText(background_sum, analysis.image.pixels.len - foreground) });
    if (kept > 0) lines.add("area total {d} mean {s} largest {d} {d} smallest {d} {d}", .{
        area, meanText(area, kept), largest, analysis.regions[largest].count, smallest, analysis.regions[smallest].count,
    }) else lines.write("area total 0 mean - largest - smallest -");
    var class_line: p.Text = .{};
    class_line.write("classes");
    for (rules.class_names, 0..) |name, i| class_line.add(" {s} {d}", .{ name, classes[i] });
    lines.write(class_line.value());
    orientationLine(orientation_counts, lines);
    var flag_line: p.Text = .{};
    flag_line.write("flags");
    for (rules.flags, 0..) |rule, i| flag_line.add(" {s} {d}", .{ rule.name, flags[i] });
    lines.write(flag_line.value());
}

fn overallLines(analyses: []const Analysis, rules: Rules, lines: *p.Lines) void {
    var regions: usize = 0;
    var kept: usize = 0;
    var holes: usize = 0;
    var filters = [_]usize{0} ** 20;
    var classes = [_]usize{0} ** 21;
    var flags = [_]usize{0} ** 20;
    var orientation_counts = [_]usize{0} ** 5;
    var areas = [_]i64{0} ** 21;
    var largest_image: ?usize = null;
    var largest_region: usize = 0;
    var largest_area: usize = 0;
    for (analyses, 0..) |*analysis, image_number| {
        regions += analysis.labels.count;
        holes += analysis.holes.len - 1;
        for (analysis.regions[1..], 1..) |*region, number| {
            if (!region.kept) { filters[region.dropped_by.?] += 1; continue; }
            kept += 1;
            classes[region.class_number] += 1;
            areas[region.class_number] += p.n(region.count);
            orientation_counts[region.orientation] += 1;
            for (rules.flags, 0..) |_, i| flags[i] += @intFromBool(region.flags[i]);
            if (largest_image == null or region.count > largest_area) { largest_image = image_number; largest_region = number; largest_area = region.count; }
        }
    }
    lines.write("overall");
    lines.add("images {d}", .{analyses.len});
    lines.add("regions {d} kept {d} dropped {d}", .{ regions, kept, regions - kept });
    lines.add("holes {d} euler {d}", .{ holes, p.n(regions) - p.n(holes) });
    for (rules.filters, 0..) |condition, i| lines.add("filter {d} {s} {s} {s} dropped {d}", .{ i + 1, condition.feature_word, condition.comparison, condition.text, filters[i] });
    for (rules.class_names, 0..) |name, i| lines.add("class {s} count {d} area {d} mean {s}", .{ name, classes[i], areas[i], meanText(areas[i], classes[i]) });
    for (rules.flags, 0..) |rule, i| lines.add("flag {s} count {d}", .{ rule.name, flags[i] });
    orientationLine(orientation_counts, lines);
    if (largest_image) |i| lines.add("largest {s} {d} {d}", .{ analyses[i].image.name, largest_region, largest_area }) else lines.write("largest -");
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    p.allocator = arena.allocator();
    const parameters = try readParameters(init.io);
    const rules = try readRules(init.io);
    const images = try p.readImages(init.io);
    const analyses = p.alloc(Analysis, images.len);
    var thresholds: p.Lines = .{};
    var labels: p.Lines = .{};
    var regions: p.Lines = .{};
    var summary: p.Lines = .{};
    regions.write(csv_header);
    for (images, analyses) |image, *analysis| {
        var setting: Setting = undefined;
        for (parameters.settings) |candidate| if (p.eq(candidate.name, image.name)) { setting = candidate; break; };
        analysis.* = Analysis.init(image, setting, parameters, rules);
        thresholdLines(analysis, &thresholds);
        mapLines(analysis, &labels);
        csvLines(analysis, rules, &regions);
        summaryLines(analysis, rules, &summary);
    }
    overallLines(analyses, rules, &summary);
    try report.writeLines(init.io, "thresholds.txt", thresholds);
    try report.writeLines(init.io, "labels.txt", labels);
    try report.writeLines(init.io, "regions.csv", regions);
    try report.writeLines(init.io, "summary.txt", summary);
}
