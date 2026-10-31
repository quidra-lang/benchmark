const std = @import("std");
const c = @import("ratings.zig");
const neighborhood = @import("neighborhood.zig");
const factorization = @import("factorization.zig");
const evaluation = @import("evaluation.zig");
const report = @import("report.zig");
const real = report.real;
const methods = [_][]const u8{ "GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS" };
const rankings = [_][]const u8{ "POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS" };
const Prediction = struct { value: f64 = 0, mean_similarity: f64 = 0, neighbors: usize = 0, top: ?usize = null,
     fallback: bool = false };
const Context = struct { d: c.Data, s: neighborhood.Similarities, f: factorization.Factors, bu: []const f64, bi: []const f64 };
fn predict(context: Context, method: usize, u: usize, i: usize, size: usize) Prediction {
    const d = context.d;
    const s = context.s;
    const baseline = (d.mean + context.bu[u]) + context.bi[i];
    var out: Prediction = .{ .value = baseline };
    if (method == 0) {
        out.value = d.mean;
        return out;
    }
    if (method == 1) return out;
    if (method == 5) {
        out.value = ((d.mean + context.f.user_bias[u]) + context.f.item_bias[i]) + factorization.dot(context.f.p[u],
             context.f.q[i]);
        return out;
    }
    if (method == 6) {
        out.value = baseline + factorization.dot(context.f.x[u], context.f.y[i]);
        return out;
    }
    if (method == 4) {
        var num: f64 = 0;
        var den: i64 = 0;
        for (0..d.items.len) |j| if (d.ratings[u][j] != 0 and s.common[i][j] >= 1) {
            const count = s.common[i][j];
            const deviation = c.f(s.difference[i][j]) / c.f(count + d.params.shrinkage);
            num += (deviation + c.f(d.ratings[u][j])) * c.f(count);
            den += count;
        };
        if (den > 0) out.value = num / c.f(den) else out.fallback = true;
        return out;
    }
    var candidates: [300]neighborhood.Neighbor = undefined;
    var count: usize = 0;
    if (method == 2) {
        for (0..d.users.len) |v| if (d.ratings[v][i] != 0) {
            if (s.user[u][v]) |similarity| if (similarity > d.params.minimum) {
                candidates[count] = .{ .index = v, .similarity = similarity };
                count += 1;
            };
        };
    } else {
        for (0..d.items.len) |j| if (d.ratings[u][j] != 0) {
            if (s.item[i][j]) |similarity| if (similarity > d.params.minimum) {
                candidates[count] = .{ .index = j, .similarity = similarity };
                count += 1;
            };
        };
    }
    const selected = neighborhood.select(candidates[0..count], size);
    if (selected.len == 0) {
        out.fallback = true;
        return out;
    }
    out.neighbors = selected.len;
    out.top = selected[0].index;
    var num: f64 = 0;
    var den: f64 = 0;
    for (selected) |neighbor| {
        const j = neighbor.index;
        num += neighbor.similarity * (if (method == 2) c.f(d.ratings[j][i]) - d.user_mean[j] else c.f(d.ratings[u][j]) - d.item_mean[j]);
        den += neighbor.similarity;
    }
    out.value = (if (method == 2) d.user_mean[u] else d.item_mean[i]) + num / den;
    out.mean_similarity = den / c.f(out.neighbors);
    return out;
}
fn group(count: i64, bounds: []const i64) usize {
    var out: usize = 0;
    for (bounds) |bound| out += @intFromBool(count >= bound);
    return out;
}
fn lessInt(_: void, a: i64, b: i64) bool {
    return a < b;
}
fn median(values: []const i64) f64 {
    const sorted = c.dupe(i64, values);
    std.mem.sort(i64, sorted, {}, lessInt);
    const n = values.len;
    return if (n % 2 == 1) c.f(sorted[n / 2]) else c.f(sorted[n / 2 - 1] + sorted[n / 2]) / 2;
}
fn textLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
fn addGenre(values: *std.ArrayList([]const u8), value: []const u8) void {
    if (!c.has(values.items, value)) c.append([]const u8, values, value);
}
fn has(item: c.Item, genre: []const u8) bool {
    return c.has(item.genres, genre);
}
const GenreCount = struct { name: []const u8, count: usize };
fn genreLess(_: void, a: GenreCount, b: GenreCount) bool {
    return if (a.count != b.count) a.count > b.count else std.mem.lessThan(u8, a.name, b.name);
}
fn genresFor(d: c.Data, u: usize, liked: bool, genres: []const []const u8) []const GenreCount {
    var out: std.ArrayList(GenreCount) = .empty;
    for (genres) |genre| {
        var count: usize = 0;
        for (d.items, 0..) |item, i| if ((if (liked) d.ratings[u][i] >= 4 else d.ratings[u][i] > 0 and d.ratings[u][i] <= 2) and has(item,
             genre)) {
            count += 1;
        };
        if (count > 0) c.append(GenreCount, &out, .{ .name = genre, .count = count });
    }
    std.mem.sort(GenreCount, out.items, {}, genreLess);
    return out.items[0..@min(3, out.items.len)];
}
fn popularityLess(d: c.Data, a: usize, b: usize) bool {
    return if (d.item_count[a] != d.item_count[b]) d.item_count[a] > d.item_count[b] else if (d.item_mean[a] != d.item_mean[b]) d.item_mean[a] > d.item_mean[b] else a < b;
}
const RankContext = struct { predictions: []const [7]Prediction, method: usize };
fn rankLess(context: RankContext, a: usize, b: usize) bool {
    const x = context.predictions[a][context.method].value;
    const y = context.predictions[b][context.method].value;
    return if (x != y) x > y else a < b;
}
const BiasContext = struct { values: []const f64, high: bool };
fn biasLess(context: BiasContext, a: usize, b: usize) bool {
    return if (context.values[a] != context.values[b]) (if (context.high) context.values[a] > context.values[b] else context.values[a] < context.values[b]) else a < b;
}
fn recentLess(_: void, a: c.Rating, b: c.Rating) bool {
    return if (a.time != b.time) a.time > b.time else a.item < b.item;
}
const SimilarContext = struct { kind: usize, common: []const i64 };
fn similarLess(context: SimilarContext, a: neighborhood.Neighbor, b: neighborhood.Neighbor) bool {
    if (a.similarity != b.similarity) return a.similarity > b.similarity;
    if (context.kind == 3 and context.common[a.index] != context.common[b.index]) return context.common[a.index] > context.common[b.index];
    return a.index < b.index;
}
fn subsetErrors(errors: []const f64, indices: []const usize) c.Vector {
    const out = c.vector(indices.len);
    for (indices, out) |index, *value| value.* = errors[index];
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const d = try c.readInput(init.io);
    const p = d.params;
    const nu = d.users.len;
    const ni = d.items.len;
    const nm = d.test_rows.len;
    const bu = c.vector(nu);
    const bi = c.vector(ni);
    var training: std.ArrayList(factorization.Training) = .empty;
    for (1..11) |sweep| {
        for (0..ni) |i| {
            var sum: f64 = 0;
            for (0..nu) |u| if (d.ratings[u][i] != 0) {
                sum += c.f(d.ratings[u][i]) - d.mean - bu[u];
            };
            bi[i] = sum / (p.item_reg + c.f(d.item_count[i]));
        }
        for (0..nu) |u| {
            var sum: f64 = 0;
            for (0..ni) |i| if (d.ratings[u][i] != 0) {
                sum += c.f(d.ratings[u][i]) - d.mean - bi[i];
            };
            bu[u] = sum / (p.user_reg + c.f(d.user_count[u]));
        }
        var sum: f64 = 0;
        for (d.train) |record| {
            const err = c.f(record.rating) - ((d.mean + bu[record.user]) + bi[record.item]);
            sum += err * err;
        }
        c.append(factorization.Training, &training, .{ .method = "BASELINE", .epoch = sweep, .rmse = @sqrt(sum / c.f(d.train.len)) });
    }
    const s = neighborhood.similarities(d);
    const factors = factorization.train(d, bu, bi);
    for (factors.log) |entry| c.append(factorization.Training, &training, entry);
    const context: Context = .{ .d = d, .s = s, .f = factors, .bu = bu, .bi = bi };
    const predictions = c.alloc([][7]Prediction, nu);
    for (predictions, 0..) |*row, u| {
        row.* = c.alloc([7]Prediction, ni);
        @memset(row.*, [1]Prediction{.{}} ** 7);
        for (0..ni) |i| if (d.ratings[u][i] == 0) {
            for (0..7) |method| row.*[i][method] = predict(context, method, u, i, p.neighbors);
        };
    }
    var errors: [7]c.Vector = undefined;
    var clipped_values: [7]c.Vector = undefined;
    for (0..7) |method| {
        errors[method] = c.vector(nm);
        clipped_values[method] = c.vector(nm);
    }
    var clipped = [_]usize{0} ** 7;
    var fallback = [_]usize{0} ** 7;
    var prediction_file: c.Lines = .{};
    prediction_file.add("user,item,actual,GLOBAL,BASELINE,USER_KNN,ITEM_KNN,SLOPE_ONE,SVD,ALS", .{});
    var log_file: c.Lines = .{};
    var out: c.Lines = .{};
    var recommendations: c.Lines = .{};
    var similar: c.Lines = .{};
    var line: c.Text = .{};
    for (d.test_rows, 0..) |record, t| {
        line = .{};
        line.add("{d},{d},{d}", .{ d.users[record.user], d.items[record.item].id, record.rating });
        for (0..7) |method| {
            const value = predictions[record.user][record.item][method];
            const q = evaluation.clip(value.value);
            clipped[method] += @intFromBool(value.value < 1 or value.value > 5);
            fallback[method] += @intFromBool(value.fallback);
            clipped_values[method][t] = q;
            errors[method][t] = q - c.f(record.rating);
            line.add(",{s}", .{real(q)});
        }
        prediction_file.add("{s}", .{line.value()});
    }
    log_file.add("method,epoch,train_rmse", .{});
    for (training.items) |entry| log_file.add("{s},{d},{s}", .{ entry.method, entry.epoch, real(entry.rmse) });
    const popularity = c.alloc(usize, ni);
    for (popularity, 0..) |*index, i| index.* = i;
    std.mem.sort(usize, popularity, d, popularityLess);
    const head = c.alloc(bool, ni);
    @memset(head, false);
    for (popularity[0 .. ni / 5]) |i| head[i] = true;
    const lists = c.alloc([7][]const usize, nu);
    for (0..nu) |u| for (0..7) |method| {
        var list: std.ArrayList(usize) = .empty;
        if (method == 0) {
            for (popularity) |i| if (d.ratings[u][i] == 0) c.append(usize, &list, i);
        } else {
            for (0..ni) |i| if (d.ratings[u][i] == 0) c.append(usize, &list, i);
            std.mem.sort(usize, list.items, RankContext{ .predictions = predictions[u], .method = method }, rankLess);
        }
        lists[u][method] = list.items;
    };
    const relevant = c.alloc([]bool, nu);
    for (relevant) |*row| {
        row.* = c.alloc(bool, ni);
        @memset(row.*, false);
    }
    const relevant_count = c.alloc(usize, nu);
    @memset(relevant_count, 0);
    for (d.test_rows) |record| if (record.rating >= 4) {
        relevant[record.user][record.item] = true;
        relevant_count[record.user] += 1;
    };
    var evaluated: std.ArrayList(usize) = .empty;
    var total_relevant: usize = 0;
    for (0..nu) |u| if (relevant_count[u] > 0) {
        c.append(usize, &evaluated, u);
        total_relevant += relevant_count[u];
    };
    var genres: std.ArrayList([]const u8) = .empty;
    var test_genres: std.ArrayList([]const u8) = .empty;
    for (d.items) |item| for (item.genres) |genre| addGenre(&genres, genre);
    for (d.test_rows) |record| for (d.items[record.item].genres) |genre| addGenre(&test_genres, genre);
    std.mem.sort([]const u8, genres.items, {}, textLess);
    std.mem.sort([]const u8, test_genres.items, {}, textLess);
    var histogram = [_]usize{0} ** 5;
    var first = d.train[0].time;
    var last = first;
    for (d.train) |record| {
        histogram[c.u(record.rating - 1)] += 1;
        first = @min(first, record.time);
        last = @max(last, record.time);
    }
    var user_pairs: usize = 0;
    var user_usable: usize = 0;
    var item_pairs: usize = 0;
    var item_usable: usize = 0;
    var slope_pairs: usize = 0;
    for (0..nu - 1) |u| for (u + 1..nu) |v| {
        if (s.user[u][v]) |value| {
            user_pairs += 1;
            user_usable += @intFromBool(value > p.minimum);
        }
    };
    for (0..ni - 1) |i| for (i + 1..ni) |j| {
        if (s.item[i][j]) |value| {
            item_pairs += 1;
            item_usable += @intFromBool(value > p.minimum);
        }
        slope_pairs += @intFromBool(s.common[i][j] >= 1);
    };
    var user_min = d.user_count[0];
    var user_max = user_min;
    var item_min = d.item_count[0];
    var item_max = item_min;
    for (d.user_count) |count| {
        user_min = @min(user_min, count);
        user_max = @max(user_max, count);
    }
    for (d.item_count) |count| {
        item_min = @min(item_min, count);
        item_max = @max(item_max, count);
    }
    out.add("data users {d} items {d} catalog {d} ratings {d} test {d}", .{ nu, ni, d.catalog.len, d.train.len, nm });
    out.add("density {s} global_mean {s}", .{ real(c.f(d.train.len) / c.f(nu * ni)), real(d.mean) });
    line = .{};
    line.add("histogram", .{});
    for (histogram) |count| line.add(" {d}", .{count});
    out.add("{s}", .{line.value()});
    out.add("user_ratings min {d} median {s} max {d}", .{ user_min, real(median(d.user_count)), user_max });
    out.add("item_ratings min {d} median {s} max {d}", .{ item_min, real(median(d.item_count)), item_max });
    out.add("timestamps first {d} last {d}", .{ first, last });
    out.add("cold_items {d}", .{d.catalog.len - ni});
    out.add("similarities user_pairs {d} usable {d} item_pairs {d} usable {d} slope_pairs {d}", .{ user_pairs,
         user_usable, item_pairs, item_usable, slope_pairs });
    out.add("", .{});
    out.add("genre_stats", .{});
    for (genres.items) |genre| {
        var count: usize = 0;
        var ratings: i64 = 0;
        var high: usize = 0;
        for (d.items, 0..) |item, i| if (has(item, genre)) {
            count += 1;
            ratings += d.item_count[i];
            for (0..nu) |u| high += @intFromBool(d.ratings[u][i] >= 4);
        };
        out.add("genre {s} items {d} ratings {d} high {d}", .{ genre, count, ratings, high });
    }
    out.add("", .{});
    out.add("time_buckets {d}", .{p.buckets});
    for (0..p.buckets) |bucket| {
        var count: usize = 0;
        var total: i64 = 0;
        const seen = c.alloc(bool, nu);
        @memset(seen, false);
        var nseen: usize = 0;
        for (d.train) |record| if (@divFloor((record.time - first) * c.n(p.buckets), last - first + 1) == c.n(bucket)) {
            count += 1;
            total += record.rating;
            if (!seen[record.user]) {
                seen[record.user] = true;
                nseen += 1;
            }
        };
        out.add("bucket {d} ratings {d} users {d} mean {s}", .{ bucket + 1, count, nseen, if (count > 0) real(c.f(total) / c.f(count)) else "-" });
    }
    out.add("", .{});
    out.add("rating_metrics", .{});
    for (0..7) |method| out.add("{s} rmse {s} mae {s} clipped {d} fallback {d}", .{ methods[method],
         real(evaluation.rmse(errors[method])), real(evaluation.mae(errors[method])), clipped[method],
         fallback[method] });
    out.add("", .{});
    out.add("generalization", .{});
    var global_squares: f64 = 0;
    for (d.train) |record| global_squares += (c.f(record.rating) - d.mean) * (c.f(record.rating) - d.mean);
    for ([_]usize{ 0, 1, 5, 6 }) |method| {
        const train = if (method == 0) @sqrt(global_squares / c.f(d.train.len)) else if (method == 1) training.items[9].rmse else if (method == 5) factors.log[p.epochs - 1].rmse else factors.log[factors.log.len - 1].rmse;
        const heldout = evaluation.rmse(errors[method]);
        out.add("{s} train {s} test {s} gap {s}", .{ methods[method], real(train), real(heldout), real(heldout - train) });
    }
    out.add("", .{});
    out.add("neighborhoods k {d}", .{p.neighbors});
    for (2..4) |method| {
        var count: usize = 0;
        var total: usize = 0;
        var similarity: f64 = 0;
        for (d.test_rows) |record| {
            const value = predictions[record.user][record.item][method];
            if (!value.fallback) {
                count += 1;
                total += value.neighbors;
                similarity += value.mean_similarity;
            }
        }
        out.add("{s} predictions {d} with_neighbors {d} mean_neighbors {s} mean_similarity {s}", .{ methods[method],
             nm, count, if (count > 0) real(c.f(total) / c.f(count)) else "-", if (count > 0) real(similarity / c.f(count)) else "-" });
    }
    var actual_sum: f64 = 0;
    for (d.test_rows) |record| actual_sum += c.f(record.rating);
    const actual_mean = actual_sum / c.f(nm);
    var actual_squares: f64 = 0;
    var actual_same = true;
    for (d.test_rows) |record| {
        actual_squares += (c.f(record.rating) - actual_mean) * (c.f(record.rating) - actual_mean);
        actual_same = actual_same and record.rating == d.test_rows[0].rating;
    }
    out.add("", .{});
    out.add("prediction_stats actual mean {s} std {s}", .{ real(actual_mean), real(@sqrt(actual_squares / c.f(nm))) });
    for (0..7) |method| {
        var sum: f64 = 0;
        for (clipped_values[method]) |q| sum += q;
        const mean = sum / c.f(nm);
        var squares: f64 = 0;
        var cross: f64 = 0;
        var same = true;
        for (clipped_values[method], d.test_rows) |q, record| {
            squares += (q - mean) * (q - mean);
            cross += (q - mean) * (c.f(record.rating) - actual_mean);
            same = same and q == clipped_values[method][0];
        }
        out.add("{s} mean {s} std {s} correlation {s}", .{ methods[method], real(mean), real(@sqrt(squares / c.f(nm))),
             if (same or actual_same) "-" else real(cross / @sqrt(squares * actual_squares)) });
    }
    out.add("", .{});
    out.add("error_bins edges 0.5 1.0 1.5 2.0", .{});
    for (0..7) |method| {
        var bins = [_]usize{0} ** 5;
        for (errors[method]) |err| {
            const value = @abs(err);
            bins[if (value < 0.5) @as(usize, 0) else if (value < 1) @as(usize, 1) else if (value < 1.5) @as(usize,
                 2) else if (value < 2) @as(usize, 3) else @as(usize, 4)] += 1;
        }
        line = .{};
        line.add("{s}", .{methods[method]});
        for (bins) |count| line.add(" {d}", .{count});
        out.add("{s}", .{line.value()});
    }
    out.add("", .{});
    out.add("comparison", .{});
    for (0..6) |a| for (a + 1..7) |b| {
        var wins: usize = 0;
        var ties: usize = 0;
        var losses: usize = 0;
        for (errors[a], errors[b]) |left, right| {
            const x = @abs(left);
            const y = @abs(right);
            wins += @intFromBool(x < y);
            ties += @intFromBool(x == y);
            losses += @intFromBool(x > y);
        }
        out.add("{s} {s} wins {d} ties {d} losses {d}", .{ methods[a], methods[b], wins, ties, losses });
    };
    for (0..2) |kind| {
        const bounds = if (kind == 0) p.user_groups else p.item_groups;
        out.add("", .{});
        line = .{};
        line.add("{s} bounds", .{if (kind == 0) "user_groups" else "item_groups"});
        for (bounds) |value| line.add(" {d}", .{value});
        out.add("{s}", .{line.value()});
        for (0..bounds.len + 1) |g| {
            var indices: std.ArrayList(usize) = .empty;
            for (d.test_rows, 0..) |record, t| {
                const count = if (kind == 0) d.user_count[record.user] else d.item_count[record.item];
                if (group(count, bounds) == g) c.append(usize, &indices, t);
            }
            line = .{};
            line.add("group {d} from {d} to {s} pairs {d}", .{ g + 1, if (g == 0) @as(i64, 1) else bounds[g - 1],
                 if (g == bounds.len) "-" else c.fmt("{d}", .{bounds[g] - 1}), indices.items.len });
            for (0..7) |method| line.add(" {s} {s}", .{ methods[method], if (indices.items.len > 0) real(evaluation.rmse(subsetErrors(errors[method],
                 indices.items))) else "-" });
            out.add("{s}", .{line.value()});
        }
    }
    out.add("", .{});
    out.add("by_rating", .{});
    for (1..6) |rating| {
        var indices: std.ArrayList(usize) = .empty;
        for (d.test_rows, 0..) |record, t| if (record.rating == c.n(rating)) c.append(usize, &indices, t);
        line = .{};
        line.add("rating {d} pairs {d}", .{ rating, indices.items.len });
        for (0..7) |method| line.add(" {s} {s}", .{ methods[method], if (indices.items.len > 0) real(evaluation.mae(subsetErrors(errors[method],
             indices.items))) else "-" });
        out.add("{s}", .{line.value()});
    }
    out.add("", .{});
    out.add("genres", .{});
    for (test_genres.items) |genre| {
        var indices: std.ArrayList(usize) = .empty;
        for (d.test_rows, 0..) |record, t| if (has(d.items[record.item], genre)) c.append(usize, &indices, t);
        line = .{};
        line.add("genre {s} pairs {d}", .{ genre, indices.items.len });
        for (0..7) |method| line.add(" {s} {s}", .{ methods[method], real(evaluation.rmse(subsetErrors(errors[method],
             indices.items))) });
        out.add("{s}", .{line.value()});
    }
    out.add("", .{});
    out.add("ranking users {d} relevant {d}", .{ evaluated.items.len, total_relevant });
    for (p.cutoffs) |cutoff_| {
        const cutoff = c.u(cutoff_);
        out.add("cutoff {d}", .{cutoff});
        for (0..7) |method| {
            var hits: usize = 0;
            var hit_users: usize = 0;
            var recall: f64 = 0;
            var ndcg: f64 = 0;
            var ap: f64 = 0;
            var rr: f64 = 0;
            for (evaluated.items) |u| {
                const metrics = evaluation.rankingMetrics(lists[u][method], relevant[u], relevant_count[u], cutoff);
                hits += metrics.hits;
                hit_users += @intFromBool(metrics.hits > 0);
                recall += metrics.recall;
                ndcg += metrics.ndcg;
                ap += metrics.ap;
                rr += metrics.rr;
            }
            out.add("  {s} precision {s} recall {s} ndcg {s} map {s} mrr {s} hit_rate {s}", .{ rankings[method],
                 real(c.f(hits) / c.f(cutoff * evaluated.items.len)), real(recall / c.f(evaluated.items.len)),
                 real(ndcg / c.f(evaluated.items.len)), real(ap / c.f(evaluated.items.len)), real(rr / c.f(evaluated.items.len)),
                 real(c.f(hit_users) / c.f(evaluated.items.len)) });
        }
    }
    out.add("", .{});
    out.add("beyond_accuracy top_n {d} head {d}", .{ p.top, ni / 5 });
    for (0..7) |method| {
        const covered = c.alloc(bool, ni);
        @memset(covered, false);
        var ncovered: usize = 0;
        var diversity: usize = 0;
        var popular: i64 = 0;
        var tail: usize = 0;
        var novelty: f64 = 0;
        var similarity: f64 = 0;
        for (evaluated.items) |u| {
            const list = lists[u][method];
            var found: std.ArrayList([]const u8) = .empty;
            var nov: f64 = 0;
            var ils: f64 = 0;
            for (list[0..p.top]) |i| {
                if (!covered[i]) {
                    covered[i] = true;
                    ncovered += 1;
                }
                for (d.items[i].genres) |genre| addGenre(&found, genre);
                nov += @log2(c.f(nu) / c.f(d.item_count[i]));
                popular += d.item_count[i];
                tail += @intFromBool(!head[i]);
            }
            diversity += found.items.len;
            novelty += nov / c.f(p.top);
            for (0..p.top - 1) |a| for (a + 1..p.top) |b| {
                ils += s.item[list[a]][list[b]] orelse 0;
            };
            similarity += ils / c.f(p.top * (p.top - 1) / 2);
        }
        out.add("{s} coverage {s} diversity {s} novelty {s} popularity {s} long_tail {s} similarity {s}",
             .{ rankings[method], real(c.f(ncovered) / c.f(ni)), real(c.f(diversity) / c.f(evaluated.items.len)),
             real(novelty / c.f(evaluated.items.len)), real(c.f(popular) / c.f(p.top * evaluated.items.len)),
             real(c.f(tail) / c.f(p.top * evaluated.items.len)), real(similarity / c.f(evaluated.items.len)) });
    }
    out.add("", .{});
    line = .{};
    line.add("ranking_groups top_n {d} bounds", .{p.top});
    for (p.user_groups) |value| line.add(" {d}", .{value});
    out.add("{s}", .{line.value()});
    for (0..p.user_groups.len + 1) |g| {
        var selected: std.ArrayList(usize) = .empty;
        for (evaluated.items) |u| if (group(d.user_count[u], p.user_groups) == g) c.append(usize, &selected, u);
        line = .{};
        line.add("group {d} users {d}", .{ g + 1, selected.items.len });
        for (0..7) |method| {
            var total: f64 = 0;
            for (selected.items) |u| total += evaluation.rankingMetrics(lists[u][method], relevant[u],
                 relevant_count[u], p.top).ndcg;
            line.add(" {s} {s}", .{ rankings[method], if (selected.items.len > 0) real(total / c.f(selected.items.len)) else "-" });
        }
        out.add("{s}", .{line.value()});
    }
    out.add("", .{});
    out.add("agreement top_n {d}", .{p.top});
    for (0..6) |a| for (a + 1..7) |b| {
        var total: f64 = 0;
        for (evaluated.items) |u| {
            var common: usize = 0;
            for (lists[u][a][0..p.top]) |i| common += @intFromBool(std.mem.indexOfScalar(usize, lists[u][b][0..p.top],
                 i) != null);
            total += c.f(common) / c.f(2 * p.top - common);
        }
        out.add("{s} {s} jaccard {s}", .{ rankings[a], rankings[b], real(total / c.f(evaluated.items.len)) });
    };
    out.add("", .{});
    out.add("neighbor_grid", .{});
    var best = [_]usize{0} ** 2;
    var smallest = [_]f64{0} ** 2;
    for (p.grid) |size_| {
        const size = c.u(size_);
        line = .{};
        line.add("k {d}", .{size});
        for (0..2) |kind| {
            const values = c.vector(nm);
            for (d.test_rows, values) |record, *value| value.* = evaluation.clip(predict(context,
                 kind + 2, record.user, record.item, size).value) - c.f(record.rating);
            const value = evaluation.rmse(values);
            if (best[kind] == 0 or value < smallest[kind]) {
                best[kind] = size;
                smallest[kind] = value;
            }
            line.add(" {s} {s}", .{ methods[kind + 2], real(value) });
        }
        out.add("{s}", .{line.value()});
    }
    out.add("best USER_KNN {d} ITEM_KNN {d}", .{ best[0], best[1] });
    out.add("", .{});
    out.add("biases", .{});
    for (0..4) |kind| {
        const item = kind < 2;
        const high = kind % 2 == 0;
        const bias = if (item) bi else bu;
        const order = c.alloc(usize, bias.len);
        for (order, 0..) |*value, i| value.* = i;
        std.mem.sort(usize, order, BiasContext{ .values = bias, .high = high }, biasLess);
        for (order[0..p.list]) |index| {
            line = .{};
            line.add("{s}_{s} {d} bias {s} count {d} mean {s}", .{ if (item) "item" else "user", if (high) "high" else "low",
                 if (item) d.items[index].id else d.users[index], real(bias[index]), if (item) d.item_count[index] else d.user_count[index],
                 real(if (item) d.item_mean[index] else d.user_mean[index]) });
            if (item) line.add(" {s}", .{d.items[index].title});
            out.add("{s}", .{line.value()});
        }
    }
    for (p.users, 0..) |id, request| {
        if (request > 0) recommendations.add("", .{});
        const user = std.mem.indexOfScalar(i64, d.users, id);
        if (user == null) {
            recommendations.add("user {d} unknown", .{id});
            recommendations.add("list POPULAR", .{});
            for (popularity[0..p.top], 1..) |i, rank| recommendations.add("  {d} {d} count {d} mean {s} {s}",
                 .{ rank, d.items[i].id, d.item_count[i], real(d.item_mean[i]), d.items[i].title });
            continue;
        }
        const u = user.?;
        recommendations.add("user {d} ratings {d} mean {s} bias {s}", .{ id, d.user_count[u], real(d.user_mean[u]),
             real(bu[u]) });
        const liked = genresFor(d, u, true, genres.items);
        const disliked = genresFor(d, u, false, genres.items);
        for (0..2) |kind| {
            const values = if (kind == 0) liked else disliked;
            line = .{};
            line.add("{s}", .{if (kind == 0) "liked_genres" else "disliked_genres"});
            if (values.len == 0) line.add(" -", .{});
            for (values) |entry| line.add(" {s} {d}", .{ entry.name, entry.count });
            recommendations.add("{s}", .{line.value()});
        }
        var recent: std.ArrayList(c.Rating) = .empty;
        for (d.train) |record| if (record.user == u) c.append(c.Rating, &recent, record);
        std.mem.sort(c.Rating, recent.items, {}, recentLess);
        line = .{};
        line.add("recent", .{});
        for (recent.items[0..@min(3, recent.items.len)]) |record| line.add(" {d} {d}", .{ d.items[record.item].id,
             record.rating });
        recommendations.add("{s}", .{line.value()});
        var neighbors: [200]neighborhood.Neighbor = undefined;
        var nneighbors: usize = 0;
        for (0..nu) |v| if (s.user[u][v]) |similarity| {
            if (similarity > p.minimum) {
                neighbors[nneighbors] = .{ .index = v, .similarity = similarity };
                nneighbors += 1;
            }
        };
        for (neighborhood.select(neighbors[0..nneighbors], p.list)) |neighbor| recommendations.add("neighbor {d} similarity {s} common {d}",
             .{ d.users[neighbor.index], real(neighbor.similarity), s.user_common[u][neighbor.index] });
        for (d.test_rows) |record| if (record.user == u) {
            line = .{};
            line.add("heldout {d} actual {d}", .{ d.items[record.item].id, record.rating });
            for (0..7) |method| line.add(" {s}", .{real(evaluation.clip(predictions[u][record.item][method].value))});
            recommendations.add("{s}", .{line.value()});
        };
        for (0..7) |method| {
            const list = lists[u][method];
            var matches: usize = 0;
            for (list[0..p.top]) |i| {
                var matched = false;
                for (liked) |entry| matched = matched or has(d.items[i], entry.name);
                matches += @intFromBool(matched);
            }
            recommendations.add("list {s} genre_match {d}", .{ rankings[method], matches });
            for (list[0..p.top], 1..) |i, rank| {
                line = .{};
                line.add("  {d} {d}", .{ rank, d.items[i].id });
                if (method == 0) line.add(" count {d} mean {s}", .{ d.item_count[i], real(d.item_mean[i]) }) else {
                    const value = predictions[u][i][method];
                    line.add(" {s}", .{real(value.value)});
                    if (method == 2 or method == 3) line.add(" via {s}", .{if (value.top) |top| c.fmt("{d}",
                         .{if (method == 2) d.users[top] else d.items[top].id}) else "-"});
                }
                line.add(" {s}", .{d.items[i].title});
                recommendations.add("{s}", .{line.value()});
            }
        }
    }
    for (p.items, 0..) |id, request| {
        if (request > 0) similar.add("", .{});
        const i = c.itemIndex(d.items, id);
        similar.add("item {d} ratings {d} mean {s} bias {s} genres {s} title {s}", .{ id, d.item_count[i],
             real(d.item_mean[i]), real(bi[i]), d.items[i].genre_list, d.items[i].title });
        for (0..4) |kind| {
            similar.add("{s}", .{if (kind == 0) "cosine" else if (kind == 1) "factors" else if (kind == 2) "co_rated" else "slope_one"});
            var candidates: [300]neighborhood.Neighbor = undefined;
            var count: usize = 0;
            for (0..ni) |j| {
                if (j == i) continue;
                var value: ?f64 = null;
                if (kind == 0) value = s.item[i][j] else if (kind == 1) value = factorization.dot(factors.q[i],
                     factors.q[j]) / @sqrt(factorization.dot(factors.q[i], factors.q[i]) * factorization.dot(factors.q[j],
                     factors.q[j])) else if (s.common[i][j] >= 1) value = if (kind == 2) c.f(s.common[i][j]) else c.f(s.difference[j][i]) / c.f(s.common[j][i] + p.shrinkage);
                if (value) |similarity| {
                    candidates[count] = .{ .index = j, .similarity = similarity };
                    count += 1;
                }
            }
            std.mem.sort(neighborhood.Neighbor, candidates[0..count], SimilarContext{ .kind = kind,
                 .common = s.common[i] }, similarLess);
            for (candidates[0..@min(p.list, count)], 1..) |candidate, rank| {
                const j = candidate.index;
                line = .{};
                line.add("  {d} {d}", .{ rank, d.items[j].id });
                if (kind < 2) {
                    line.add(" similarity {s}", .{real(candidate.similarity)});
                    if (kind == 0) line.add(" common {d}", .{s.common[i][j]});
                } else if (kind == 2) line.add(" common {d}", .{s.common[i][j]}) else line.add(" difference {d} common {d}",
                     .{ s.difference[j][i], s.common[j][i] });
                line.add(" {s}", .{d.items[j].title});
                similar.add("{s}", .{line.value()});
            }
        }
    }
    try report.write(init.io, "predictions.csv", prediction_file);
    try report.write(init.io, "evaluation.txt", out);
    try report.write(init.io, "recommendations.txt", recommendations);
    try report.write(init.io, "similar_items.txt", similar);
    try report.write(init.io, "training_log.csv", log_file);
}
