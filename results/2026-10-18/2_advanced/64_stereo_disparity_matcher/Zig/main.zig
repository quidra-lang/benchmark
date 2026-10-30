const std = @import("std");
const d = @import("pgm_io.zig");
const costs = @import("costs.zig");
const aggregation = @import("aggregation.zig");
const refinement = @import("refinement.zig");
const evaluation = @import("evaluation.zig");
const n = d.n;
const u = d.u;
const ratio = evaluation.ratio;
const two = refinement.twoDecimals;
const names = [7][]const u8{ "sad", "ssd", "census", "sgm", "fusion", "wta_final", "sgm_final" };
const region_names = [3][]const u8{ "nonocc", "all", "disc" };
const sources = [5][]const u8{ "kept", "median", "background", "interpolated", "none" };
const Selection = struct { image: []const i64 = &.{}, reasons: []const i64 = &.{}, margins: []const i64 = &.{},
     lr: [4]i64 = .{ 0, 0, 0, 0 }, bounds: i64 = 0, window: usize = 0 };
fn consistent(x: usize, y: usize, width: usize, disparity: usize, right: []const i64, p: d.Params) bool {
    return x >= disparity and @abs(n(disparity) - right[y * width + x - disparity]) <= @as(u64, @intCast(p.lr));
}
fn select(volume: d.Volume, strength: []const i64, width: usize, height: usize, p: d.Params) Selection {
    const count = volume.disparities;
    const right = d.alloc(i64, width * height);
    @memset(right, 0);
    for (0..height) |y| for (0..width) |x| {
        var best: i64 = std.math.maxInt(i64);
        for (p.minimum..p.maximum + 1) |disparity| {
            if (x + disparity >= width) break;
            const value = volume.values[(y * width + x + disparity) * count + disparity - p.minimum];
            if (value < best) {
                best = value;
                right[y * width + x] = n(disparity);
            }
        }
    };
    const image = d.alloc(i64, width * height);
    @memset(image, 0);
    const reasons = d.alloc(i64, width * height);
    const margins = d.alloc(i64, width * height);
    @memset(margins, 0);
    var out: Selection = .{ .image = image, .reasons = reasons, .margins = margins };
    for (0..height) |y| for (0..width) |x| {
        const index = y * width + x;
        const row = volume.values[index * count ..][0..count];
        var first: usize = 0;
        for (row, 0..) |value, i| {
            if (value < row[first]) first = i;
        }
        const disparity = p.minimum + first;
        const c1 = row[first];
        var c2: i64 = std.math.maxInt(i64);
        for (row, 0..) |value, i| {
            if (@abs(n(i) - n(first)) >= 2) c2 = @min(c2, value);
        }
        var reason: i64 = 0;
        if (strength[index] < p.texture_threshold) reason = 50 else if (100 * c2 <= (100 + p.uniqueness) * c1) reason = 100 else if (x < disparity) reason = 150 else if (!consistent(x,
             y, width, disparity, right, p)) {
            var any = false;
            for (p.minimum..p.maximum + 1) |candidate| any = any or consistent(x, y, width, candidate, right, p);
            reason = if (any) 200 else 255;
        }
        reasons[index] = reason;
        if (reason == 0) {
            image[index] = n(disparity);
            margins[index] = c2 - c1;
        }
        if (reason == 0 or reason == 200 or reason == 255) {
            const difference = @abs(n(disparity) - right[y * width + x - disparity]);
            out.lr[@min(@as(usize, 3), @as(usize, @intCast(difference)))] += 1;
        }
        out.bounds += @intFromBool(disparity == p.minimum or disparity == p.maximum);
    };
    return out;
}
fn lessValue(_: void, a: i64, b: i64) bool {
    return a < b;
}
fn median(values: []i64) i64 {
    std.mem.sort(i64, values, {}, lessValue);
    return values[(values.len - 1) / 2];
}
fn components(image: []const i64, width: usize, height: usize, range: i64) []const []const usize {
    const visited = d.alloc(bool, image.len);
    @memset(visited, false);
    var out: std.ArrayList([]const usize) = .empty;
    const steps = [4]d.Point{ .{ .x = 1, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = -1 } };
    for (image, 0..) |value, seed| {
        if (value == 0 or visited[seed]) continue;
        var queue: [3072]usize = undefined;
        var count: usize = 1;
        queue[0] = seed;
        visited[seed] = true;
        var head: usize = 0;
        while (head < count) : (head += 1) {
            const index = queue[head];
            const x = index % width;
            const y = index / width;
            for (steps) |step| {
                const xx = n(x) + step.x;
                const yy = n(y) + step.y;
                if (xx < 0 or xx >= n(width) or yy < 0 or yy >= n(height)) continue;
                const other = u(yy) * width + u(xx);
                if (!visited[other] and image[other] != 0 and @abs(image[index] - image[other]) <= @as(u64,
                     @intCast(range))) {
                    visited[other] = true;
                    queue[count] = other;
                    count += 1;
                }
            }
        }
        d.append([]const usize, &out, d.dupe(usize, queue[0..count]));
    }
    return out.items;
}
const Post = struct { image: []const i64, source: []const usize, components: i64 = 0, pixels: i64 = 0,
     median_changes: i64 = 0, background: i64 = 0, interpolated: i64 = 0, unfilled: i64 = 0 };
fn postprocess(selection: Selection, width: usize, height: usize, p: d.Params) Post {
    const a1 = d.dupe(i64, selection.image);
    var out: Post = .{ .image = &.{}, .source = &.{} };
    for (components(selection.image, width, height, p.speckle_range)) |group| {
        if (group.len >= p.speckle_size) continue;
        out.components += 1;
        out.pixels += n(group.len);
        for (group) |index| a1[index] = 0;
    }
    const a2 = d.dupe(i64, a1);
    for (0..height) |y| for (0..width) |x| {
        const index = y * width + x;
        if (a1[index] == 0) continue;
        var values: [9]i64 = undefined;
        var count: usize = 0;
        var dy: i64 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i64 = -1;
            while (dx <= 1) : (dx += 1) {
                const xx = n(x) + dx;
                const yy = n(y) + dy;
                if (xx < 0 or xx >= n(width) or yy < 0 or yy >= n(height)) continue;
                const value = a1[u(yy) * width + u(xx)];
                if (value != 0) {
                    values[count] = value;
                    count += 1;
                }
            }
        }
        a2[index] = median(values[0..count]);
        out.median_changes += @intFromBool(a2[index] != a1[index]);
    };
    const image = d.dupe(i64, a2);
    const source = d.alloc(usize, a2.len);
    @memset(source, 4);
    out.image = image;
    out.source = source;
    for (0..height) |y| for (0..width) |x| {
        const index = y * width + x;
        if (a2[index] != 0) {
            source[index] = if (a2[index] == selection.image[index]) 0 else 1;
            continue;
        }
        var values: [8]i64 = undefined;
        var count: usize = 0;
        const background = selection.reasons[index] == 150 or selection.reasons[index] == 255;
        const paths: usize = if (background) 2 else 8;
        for (aggregation.directions[0..paths]) |direction| {
            var xx = n(x) + direction.x;
            var yy = n(y) + direction.y;
            while (xx >= 0 and xx < n(width) and yy >= 0 and yy < n(height)) {
                const value = a2[u(yy) * width + u(xx)];
                if (value != 0) {
                    values[count] = value;
                    count += 1;
                    break;
                }
                xx += direction.x;
                yy += direction.y;
            }
        }
        if (count == 0) {
            out.unfilled += 1;
            continue;
        }
        const middle = median(values[0..count]);
        image[index] = if (background) values[0] else middle;
        source[index] = if (background) 2 else 3;
        if (background) out.background += 1 else out.interpolated += 1;
    };
    return out;
}
fn validCount(image: []const i64) i64 {
    var out: i64 = 0;
    for (image) |value| out += @intFromBool(value != 0);
    return out;
}
fn optional(value: i64) []const u8 {
    return if (value != 0) d.fmt("{d}", .{value}) else "-";
}
const Object = struct { pixels: []const usize, minimum: i64 = 0, maximum: i64 = 0, dm: i64 = 0,
     sum: i64 = 0, truth: i64 = 0, overlap: i64 = 0, x0: usize = 0, y0: usize = 0, x1: usize = 0,
     y1: usize = 0, first: usize = 0 };
fn objectLess(_: void, a: Object, b: Object) bool {
    if (a.dm != b.dm) return a.dm > b.dm;
    if (a.pixels.len != b.pixels.len) return a.pixels.len > b.pixels.len;
    return a.first < b.first;
}
fn objectReport(image: []const i64, truth: d.PGM, p: d.Params) d.Lines {
    const width = truth.width;
    const height = truth.height;
    var small: usize = 0;
    var total: usize = 0;
    var layers: [32]i64 = [_]i64{0} ** 32;
    for (truth.pixels) |value| {
        if (value != 0) layers[u(value)] += 1;
    }
    var objects: std.ArrayList(Object) = .empty;
    for (components(image, width, height, p.object_range)) |group| {
        if (group.len < p.object_size) {
            small += 1;
            continue;
        }
        var object: Object = .{ .pixels = group, .first = group[0], .x0 = width, .y0 = height };
        var values: [3072]i64 = undefined;
        var counts: [32]i64 = [_]i64{0} ** 32;
        for (group, 0..) |index, j| {
            const x = index % width;
            const y = index / width;
            object.first = @min(object.first, index);
            object.x0 = @min(object.x0, x);
            object.x1 = @max(object.x1, x);
            object.y0 = @min(object.y0, y);
            object.y1 = @max(object.y1, y);
            values[j] = image[index];
            object.sum += image[index];
            if (truth.pixels[index] != 0) counts[u(truth.pixels[index])] += 1;
        }
        object.dm = median(values[0..group.len]);
        object.minimum = values[0];
        object.maximum = values[group.len - 1];
        for (1..32) |g| {
            if (counts[g] > object.overlap) {
                object.truth = n(g);
                object.overlap = counts[g];
            }
        }
        total += group.len;
        d.append(Object, &objects, object);
    }
    std.mem.sort(Object, objects.items, {}, objectLess);
    var out: d.Lines = .{};
    out.add("objects {d} small {d} pixels {d}", .{ objects.items.len, small, total });
    var detected: [32]bool = [_]bool{false} ** 32;
    for (objects.items, 1..) |object, i| {
        const count = n(object.pixels.len);
        var tail: []const u8 = "truth - iou -";
        if (object.truth != 0) {
            const denominator = count + layers[u(object.truth)] - object.overlap;
            tail = d.fmt("truth {d} iou {s}", .{ object.truth, ratio(object.overlap, denominator) });
            if (2 * object.overlap > denominator) detected[u(object.truth)] = true;
        }
        out.add("object {d} pixels {d} box {d} {d} {d} {d} disparity {d} {d} median {d} mean {s} depth {s} size {s} {s} {s}",
             .{ i, count, object.x0, object.y0, object.x1, object.y1, object.minimum, object.maximum,
             object.dm, two(object.sum, count), two(p.focal * p.baseline * count, object.sum),
             two(n(object.x1 - object.x0 + 1) * p.baseline, object.dm), two(n(object.y1 - object.y0 + 1) * p.baseline,
             object.dm), tail });
    }
    var layer_count: usize = 0;
    var detected_count: usize = 0;
    var missed: d.Text = .{};
    for (1..32) |g| {
        if (layers[g] == 0) continue;
        layer_count += 1;
        if (detected[g]) detected_count += 1 else missed.add("{s}{d}", .{ if (missed.value().len > 0) " " else "", g });
    }
    out.add("layers {d} detected {d} missed {s}", .{ layer_count, detected_count, if (missed.value().len > 0) missed.value() else "-" });
    return out;
}
fn rankingLess(values: []const evaluation.Evaluation, i: usize, j: usize) bool {
    const x = values[i];
    const y = values[j];
    if (x.bad1 != y.bad1) return x.bad1 < y.bad1;
    if (x.bad2 != y.bad2) return x.bad2 < y.bad2;
    if ((x.valid > 0) != (y.valid > 0)) return x.valid > 0;
    if (x.valid > 0 and x.error_sum * y.valid != y.error_sum * x.valid) return x.error_sum * y.valid < y.error_sum * x.valid;
    return i < j;
}
fn confidenceLess(margins: []const i64, i: usize, j: usize) bool {
    return if (margins[i] != margins[j]) margins[i] > margins[j] else i < j;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const io = init.io;
    const left = try d.readPGM(io, "input/left.pgm");
    const right = try d.readPGM(io, "input/right.pgm");
    const truth = try d.readPGM(io, "input/ground_truth.pgm");
    const p = try d.readParameters(io);
    const width = left.width;
    const height = left.height;
    const count = width * height;
    const regions = evaluation.truthRegions(truth);
    const cl = costs.census(left.pixels, width, height);
    const cr = costs.census(right.pixels, width, height);
    const strength = costs.texture(left.pixels, width, height, p.texture_window);
    var selections: [4]Selection = undefined;
    var images: [7][]const i64 = undefined;
    var sweeps: d.Lines = .{};
    var paths: d.Lines = .{};
    for (0..3) |kind| {
        var best: evaluation.Evaluation = .{};
        var first = true;
        for (p.windows[kind]) |window| {
            var candidate = select(costs.costVolume(left, right, cl, cr, kind, window, p), strength, width, height, p);
            candidate.window = window;
            const result = evaluation.evaluate(candidate.image, truth.pixels, regions.region[0]);
            sweeps.add("sweep {s} window {d} valid {d} bad1 {s} bad2 {s}", .{ names[kind],
                 window, validCount(candidate.image), ratio(result.bad1, result.pixels), ratio(result.bad2,
                 result.pixels) });
            if (first or result.bad1 < best.bad1 or (result.bad1 == best.bad1 and result.bad2 < best.bad2)) {
                first = false;
                best = result;
                selections[kind] = candidate;
            }
        }
        images[kind] = selections[kind].image;
    }
    const base = costs.costVolume(left, right, cl, cr, p.sgm_kind, p.sgm_window, p);
    const cumulative = aggregation.cumulativeCosts(base, left, p);
    for (cumulative, 1..) |volume, i| {
        var candidate = select(volume, strength, width, height, p);
        candidate.window = p.sgm_window;
        const result = evaluation.evaluate(candidate.image, truth.pixels, regions.region[0]);
        paths.add("paths {d} valid {d} bad1 {s} bad2 {s}", .{ i, validCount(candidate.image),
             ratio(result.bad1, result.pixels), ratio(result.bad2, result.pixels) });
        if (i == p.paths) selections[3] = candidate;
    }
    images[3] = selections[3].image;
    const wta = postprocess(selections[p.wta_kind], width, height, p);
    const sgm = postprocess(selections[3], width, height, p);
    images[5] = wta.image;
    images[6] = sgm.image;
    const fusion = d.alloc(i64, count);
    @memset(fusion, 0);
    images[4] = fusion;
    var votes: [5]i64 = [_]i64{0} ** 5;
    for (0..count) |index| {
        var values: [4]i64 = undefined;
        var size: usize = 0;
        for (0..4) |method| {
            if (images[method][index] != 0) {
                values[size] = images[method][index];
                size += 1;
            }
        }
        votes[size] += 1;
        if (size == 0) continue;
        const middle = median(values[0..size]);
        var agree: usize = 0;
        for (values[0..size]) |value| agree += @intFromBool(@abs(value - middle) <= 1);
        if (agree >= p.fusion_votes) fusion[index] = middle;
    }
    var report: d.Lines = .{};
    report.add("image {d} {d}", .{ width, height });
    report.add("disparities {d} {d}", .{ p.minimum, p.maximum });
    for (0..2) |side| {
        const image = if (side == 1) right.pixels else left.pixels;
        var sum: i64 = 0;
        var minimum = image[0];
        var maximum = image[0];
        for (image) |value| {
            sum += value;
            minimum = @min(minimum, value);
            maximum = @max(maximum, value);
        }
        report.add("{s} mean {s} min {d} max {d}", .{ if (side == 1) "right" else "left", two(sum,
             n(count)), minimum, maximum });
    }
    var texture_sum: i64 = 0;
    var textureless: i64 = 0;
    for (strength) |value| {
        texture_sum += value;
        textureless += @intFromBool(value < p.texture_threshold);
    }
    report.add("texture mean {s} textureless {d}", .{ two(texture_sum, n(count)), textureless });
    report.add("ground_truth known {d} nonocc {d} occluded {d} disc {d} unknown {d}", .{ regions.region[1].len,
         regions.region[0].len, regions.occluded.len, regions.region[2].len, count - regions.region[1].len });
    var photometric_abs: i64 = 0;
    var photometric_bias: i64 = 0;
    for (regions.region[0]) |index| {
        const delta = right.pixels[index - u(truth.pixels[index])] - left.pixels[index];
        photometric_abs += @intCast(@abs(delta));
        photometric_bias += delta;
    }
    var bias = two(@intCast(@abs(photometric_bias)), n(regions.region[0].len));
    if (photometric_bias < 0 and !d.eq(bias, "0.00")) bias = d.fmt("-{s}", .{bias});
    report.add("photometric pixels {d} mean_abs {s} bias {s}", .{ regions.region[0].len, two(photometric_abs,
         n(regions.region[0].len)), bias });
    report.extend(sweeps);
    report.extend(paths);
    var evaluations: [7][3]evaluation.Evaluation = undefined;
    for (images, 0..) |image, method| {
        var valid: std.ArrayList(i64) = .empty;
        for (image) |value| {
            if (value != 0) d.append(i64, &valid, value);
        }
        report.add("method {s} valid {d} invalid {d}", .{ names[method], valid.items.len, count - valid.items.len });
        if (valid.items.len == 0) report.add("disparity min - max - median - distinct 0", .{}) else {
            const middle = median(valid.items);
            var distinct: usize = 1;
            for (1..valid.items.len) |i| distinct += @intFromBool(valid.items[i] != valid.items[i - 1]);
            report.add("disparity min {d} max {d} median {d} distinct {d}", .{ valid.items[0],
                 valid.items[valid.items.len - 1], middle, distinct });
        }
        var horizontal: i64 = 0;
        var vertical: i64 = 0;
        for (0..height) |y| for (0..width) |x| {
            const index = y * width + x;
            if (image[index] == 0) continue;
            if (x + 1 < width and image[index + 1] != 0) horizontal += @intFromBool(@abs(image[index] - image[index + 1]) >= 2);
            if (y + 1 < height and image[index + width] != 0) vertical += @intFromBool(@abs(image[index] - image[index + width]) >= 2);
        };
        report.add("jumps horizontal {d} vertical {d}", .{ horizontal, vertical });
        if (method < 4) {
            const selection = selections[method];
            report.add("window {d} bounds {d}", .{ selection.window, selection.bounds });
            var reasons: [6]i64 = [_]i64{0} ** 6;
            for (selection.reasons) |value| {
                const code = if (value == 255) @as(usize, 5) else u(@divTrunc(value, 50));
                reasons[code] += 1;
            }
            report.add("reasons textureless {d} nonunique {d} outside {d} mismatch {d} occluded {d}",
                 .{ reasons[1], reasons[2], reasons[3], reasons[4], reasons[5] });
            report.add("lr 0 {d} 1 {d} 2 {d} 3+ {d}", .{ selection.lr[0], selection.lr[1],
                 selection.lr[2], selection.lr[3] });
        } else if (method == 4) report.add("votes 0 {d} 1 {d} 2 {d} 3 {d} 4 {d}", .{ votes[0],
             votes[1], votes[2], votes[3], votes[4] }) else {
            const post = if (method == 5) wta else sgm;
            report.add("postprocess speckles {d} {d} median {d} background {d} interpolated {d} unfilled {d}",
                 .{ post.components, post.pixels, post.median_changes, post.background, post.interpolated,
                 post.unfilled });
            for (0..5) |source| {
                var region: std.ArrayList(usize) = .empty;
                for (regions.region[1]) |index| {
                    if (post.source[index] == source) d.append(usize, &region, index);
                }
                const result = evaluation.evaluate(image, truth.pixels, region.items);
                report.add("source {s} pixels {d} bad1 {s}", .{ sources[source], result.pixels,
                     ratio(result.bad1, result.pixels) });
            }
        }
        for (0..3) |region| {
            const result = evaluation.evaluate(image, truth.pixels, regions.region[region]);
            evaluations[method][region] = result;
            report.add("region {s} pixels {d} valid {d} bad1 {s} bad2 {s} mae {s} exact {d}",
                 .{ region_names[region], result.pixels, result.valid, ratio(result.bad1, result.pixels),
                 ratio(result.bad2, result.pixels), if (result.valid > 0) two(result.error_sum,
                 result.valid) else "-", result.exact });
        }
        var depth_count: i64 = 0;
        var depth_sum: i64 = 0;
        var depth_maximum: i64 = 0;
        for (regions.region[0]) |index| {
            if (image[index] == 0) continue;
            const difference: i64 = @intCast(@abs(refinement.depthHundredths(image[index],
                 p.focal, p.baseline) - refinement.depthHundredths(truth.pixels[index], p.focal,
                 p.baseline)));
            depth_count += 1;
            depth_sum += difference;
            depth_maximum = @max(depth_maximum, difference);
        }
        if (depth_count > 0) report.add("depth_error pixels {d} mean {s} max {s}", .{ depth_count,
             two(depth_sum, 100 * depth_count), two(depth_maximum, 100) }) else report.add("depth_error pixels 0 mean - max -",
             .{});
        var errors: [6]i64 = [_]i64{0} ** 6;
        for (regions.region[1]) |index| {
            if (image[index] == 0) errors[5] += 1 else {
                const difference = @abs(image[index] - truth.pixels[index]);
                errors[@min(@as(usize, 4), @as(usize, @intCast(difference)))] += 1;
            }
        }
        report.add("errors 0 {d} 1 {d} 2 {d} 3 {d} 4+ {d} invalid {d}", .{ errors[0], errors[1],
             errors[2], errors[3], errors[4], errors[5] });
    }
    for (0..3) |region| {
        var order: [7]usize = .{ 0, 1, 2, 3, 4, 5, 6 };
        var ranking_values: [7]evaluation.Evaluation = undefined;
        for (0..7) |i| ranking_values[i] = evaluations[i][region];
        std.mem.sort(usize, &order, @as([]const evaluation.Evaluation, &ranking_values), rankingLess);
        var row: d.Text = .{};
        row.add("ranking {s}", .{region_names[region]});
        for (order) |method| row.add(" {s}", .{names[method]});
        report.add("{s}", .{row.value()});
    }
    for (0..4) |method| {
        var tp: i64 = 0;
        var fp: i64 = 0;
        var fn_count: i64 = 0;
        for (regions.occluded) |index| {
            const detected = selections[method].reasons[index] == 150 or selections[method].reasons[index] == 255;
            tp += @intFromBool(detected);
            fn_count += @intFromBool(!detected);
        }
        for (regions.region[0]) |index| fp += @intFromBool(selections[method].reasons[index] == 150 or selections[method].reasons[index] == 255);
        report.add("occlusion {s} tp {d} fp {d} fn {d} precision {s} recall {s}", .{ names[method],
             tp, fp, fn_count, ratio(tp, tp + fp), ratio(tp, tp + fn_count) });
    }
    for (0..4) |method| {
        var order: std.ArrayList(usize) = .empty;
        for (regions.region[0]) |index| {
            if (images[method][index] != 0) d.append(usize, &order, index);
        }
        std.mem.sort(usize, order.items, selections[method].margins, confidenceLess);
        for ([4]usize{ 25, 50, 75, 100 }) |percent| {
            const size = (order.items.len * percent + 99) / 100;
            var bad: i64 = 0;
            for (order.items[0..size]) |index| bad += @intFromBool(@abs(images[method][index] - truth.pixels[index]) > 1);
            report.add("confidence {s} {d} pixels {d} margin {s} bad1 {s}", .{ names[method],
                 percent, size, if (size > 0) d.fmt("{d}", .{selections[method].margins[order.items[size - 1]]}) else "-",
                 ratio(bad, n(size)) });
        }
    }
    var layers: [32]i64 = [_]i64{0} ** 32;
    for (truth.pixels) |value| {
        if (value != 0) layers[u(value)] += 1;
    }
    for (1..32) |g| {
        if (layers[g] == 0) continue;
        var region: std.ArrayList(usize) = .empty;
        for (regions.region[0]) |index| {
            if (truth.pixels[index] == n(g)) d.append(usize, &region, index);
        }
        var row: d.Text = .{};
        row.add("layer {d} pixels {d} nonocc {d} bad1", .{ g, layers[g], region.items.len });
        for (images) |image| row.add(" {d}", .{evaluation.evaluate(image, truth.pixels, region.items).bad1});
        report.add("{s}", .{row.value()});
    }
    for (p.minimum..p.maximum + 1) |disparity| {
        var size: usize = 0;
        for (images[6]) |value| size += @intFromBool(value == n(disparity));
        report.add("histogram {d} {d}", .{ disparity, size });
    }
    var depth: d.Lines = .{};
    depth.add("x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth", .{});
    for (p.samples.items) |sample| {
        const index = u(sample.y) * width + u(sample.x);
        var row: d.Text = .{};
        row.add("{d},{d}", .{ sample.x, sample.y });
        for (0..4) |method| row.add(",{s}", .{optional(images[method][index])});
        const disparity = images[6][index];
        if (disparity != 0) {
            const refined = refinement.subpixel(disparity, cumulative[cumulative.len - 1].values[index * base.disparities ..][0..base.disparities],
                 p);
            row.add(",{d},{s},{s},{s}", .{ disparity, sources[sgm.source[index]], refined.disparity, refined.depth });
        } else row.add(",-,none,-,-", .{});
        const ground = truth.pixels[index];
        if (ground != 0) row.add(",{d},{s}", .{ ground, two(p.focal * p.baseline, ground) }) else row.add(",-,-", .{});
        depth.add("{s}", .{row.value()});
    }
    try std.Io.Dir.cwd().createDirPath(io, "output");
    const wta_pgm = d.alloc(i64, count);
    const sgm_pgm = d.alloc(i64, count);
    const error_image = d.alloc(i64, count);
    for (0..count) |index| {
        wta_pgm[index] = 8 * images[5][index];
        sgm_pgm[index] = 8 * images[6][index];
        if (truth.pixels[index] == 0) error_image[index] = 0 else if (images[6][index] == 0) error_image[index] = 255 else error_image[index] = 50 + 50 * @as(i64,
             @intCast(@min(@as(u64, 3), @abs(images[6][index] - truth.pixels[index]))));
    }
    try d.writePGM(io, "disparity_wta.pgm", .{ .width = width, .height = height, .pixels = wta_pgm });
    try d.writePGM(io, "disparity_sgm.pgm", .{ .width = width, .height = height, .pixels = sgm_pgm });
    try d.writePGM(io, "occlusion.pgm", .{ .width = width, .height = height, .pixels = selections[3].reasons });
    try d.writePGM(io, "error_sgm.pgm", .{ .width = width, .height = height, .pixels = error_image });
    try d.save(io, "depth.csv", depth);
    try d.save(io, "evaluation.txt", report);
    try d.save(io, "objects.txt", objectReport(images[6], truth, p));
}
