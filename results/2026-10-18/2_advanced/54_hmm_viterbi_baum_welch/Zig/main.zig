const std = @import("std");
const c = @import("model_io.zig");
const inference = @import("inference.zig");
const training = @import("training.zig");
const evaluation = @import("evaluation.zig");
const sampler = @import("sampler.zig");
const zero_confusion: c.Confusion = [_][4]i64{.{ 0, 0, 0, 0 }} ** 4;
fn r(value: f64) []const u8 {
    return c.decimal(value, 4);
}
fn ratio(numerator: f64, denominator: i64) []const u8 {
    return if (denominator == 0) "-" else r(numerator / c.f(denominator));
}
fn stateString(path: c.Path, alphabet: []const u8) []const u8 {
    const out = c.alloc(u8, path.len);
    for (path, out) |state, *character| character.* = alphabet[state];
    return out;
}
fn symbolString(observation: c.Observation, alphabet: []const u8) []const u8 {
    const out = c.alloc(u8, observation.len);
    for (observation, out) |symbol, *character| character.* = alphabet[c.u(symbol)];
    return out;
}
fn integer(rows: c.Rows, index: usize) usize {
    return c.u(c.number(rows[index][1]));
}
fn indexOf(text: []const u8, character: u8) ?usize {
    return std.mem.indexOfScalar(u8, text, character);
}
fn parameters(rows: c.Rows, model: c.Model) c.Params {
    const candidates = rows[2][1..];
    const smoothing = c.alloc(f64, candidates.len);
    for (candidates, smoothing) |value, *alpha| alpha.* = c.real(value);
    const rich = c.alloc(i64, rows[10].len - 1);
    for (rows[10][1..], rich) |field, *symbol| symbol.* = c.n(indexOf(model.symbols, field[0]).?);
    return .{ .iterations = integer(rows, 0), .pseudocount = c.real(rows[1][1]), .smoothing = smoothing,
         .candidates = candidates, .folds = integer(rows, 3), .min_length = integer(rows, 4), .max_missing = integer(rows,
         5), .segment_state = indexOf(model.states, rows[6][1][0]).?, .merge_gap = integer(rows, 7),
         .min_segment = integer(rows, 8), .first_motif = c.n(indexOf(model.symbols, rows[9][1][0]).?),
         .second_motif = c.n(indexOf(model.symbols, rows[9][2][0]).?), .rich = rich, .min_rich = c.number(rows[11][1]),
         .min_motif = c.number(rows[12][1]), .confidence = c.real(rows[13][1]), .boundary_tolerance = integer(rows,
         14), .posterior_seed = c.number(rows[15][1]), .posterior_samples = integer(rows, 16), .sample_seed = c.number(rows[17][1]),
         .sample_count = integer(rows, 18), .sample_length = integer(rows, 19) };
}
const ParsedObservation = struct { path: c.Observation, reason: ?[]const u8 = null };
fn parseObservation(raw: []const u8, model: c.Model) ParsedObservation {
    const path = c.alloc(i64, raw.len);
    for (raw, path, 1..) |character, *symbol, position| {
        const ch = if (character >= 'a' and character <= 'z') character - 'a' + 'A' else character;
        if (ch == model.missing) symbol.* = -1 else if (indexOf(model.symbols, ch)) |value| symbol.* = c.n(value) else return .{ .path = path,
             .reason = c.fmt("invalid symbol {c} at position {d}", .{ ch, position }) };
    }
    return .{ .path = path };
}
fn missingCount(path: c.Observation) usize {
    var count: usize = 0;
    for (path) |symbol| count += @intFromBool(symbol < 0);
    return count;
}
fn finalChecks(path: c.Observation, p: c.Params) ?[]const u8 {
    if (path.len < p.min_length) return c.fmt("too short {d}", .{path.len});
    const missing = missingCount(path);
    if (100 * missing > p.max_missing * path.len) return c.fmt("too many missing {d}", .{missing});
    return null;
}
const Validated = struct { unlabeled: []const c.Sequence, train: []const c.Sequence, test_rows: []const c.Sequence,
     rejected: c.Lines = .{}, sequence_rejected: usize = 0, labeled_rejected: usize = 0 };
fn validate(input: c.Input, p: c.Params) Validated {
    var out: Validated = .{ .unlabeled = &.{}, .train = &.{}, .test_rows = &.{} };
    var unlabeled: std.ArrayList(c.Sequence) = .empty;
    var train: std.ArrayList(c.Sequence) = .empty;
    var test_rows: std.ArrayList(c.Sequence) = .empty;
    for (input.sequences, 0..) |fields, i| {
        var sequence: c.Sequence = .{ .name = fields[0] };
        var reason: ?[]const u8 = null;
        for (input.sequences[0..i]) |earlier| if (c.eq(sequence.name, earlier[0])) {
            reason = "duplicate name";
            break;
        };
        if (reason == null) {
            const parsed = parseObservation(fields[1], input.model);
            sequence.observation = parsed.path;
            reason = parsed.reason;
        }
        if (reason == null) reason = finalChecks(sequence.observation, p);
        if (reason) |message| {
            out.sequence_rejected += 1;
            out.rejected.add("REJECT sequences.txt line {d} {s} {s}", .{ i + 1, sequence.name, message });
        } else c.append(c.Sequence, &unlabeled, sequence);
    }
    var i: usize = 0;
    while (i < input.labeled.len) : (i += 2) {
        const fields = input.labeled[i];
        const labels = input.labeled[i + 1][0];
        var sequence: c.Sequence = .{ .name = fields[0], .role = fields[1] };
        var reason: ?[]const u8 = null;
        var earlier: usize = 0;
        while (earlier < i) : (earlier += 2) if (c.eq(sequence.name, input.labeled[earlier][0])) {
            reason = "duplicate name";
            break;
        };
        if (reason == null) {
            const parsed = parseObservation(fields[2], input.model);
            sequence.observation = parsed.path;
            reason = parsed.reason;
        }
        if (reason == null) {
            const truth = c.alloc(usize, labels.len);
            sequence.truth = truth;
            for (labels, truth, 1..) |character, *state, position| {
                state.* = indexOf(input.model.states, character) orelse {
                    reason = c.fmt("invalid label {c} at position {d}", .{ character, position });
                    break;
                };
            }
        }
        if (reason == null and fields[2].len != labels.len) reason = c.fmt("length mismatch {d} {d}",
             .{ fields[2].len, labels.len });
        if (reason == null) reason = finalChecks(sequence.observation, p);
        if (reason) |message| {
            out.labeled_rejected += 1;
            out.rejected.add("REJECT labeled.txt line {d} {s} {s}", .{ i + 1, sequence.name, message });
        } else if (c.eq(sequence.role, "TRAIN")) c.append(c.Sequence, &train, sequence) else c.append(c.Sequence,
             &test_rows, sequence);
    }
    out.unlabeled = unlabeled.items;
    out.train = train.items;
    out.test_rows = test_rows.items;
    return out;
}
fn observations(sequences: []const c.Sequence) []const c.Observation {
    const out = c.alloc(c.Observation, sequences.len);
    for (sequences, out) |sequence, *path| path.* = sequence.observation;
    return out;
}
fn pairs(sequences: []const c.Sequence) []const c.Pair {
    const out = c.alloc(c.Pair, sequences.len);
    for (sequences, out) |sequence, *pair| pair.* = .{ .observation = sequence.observation, .path = sequence.truth };
    return out;
}
fn segments(path: c.Path, p: c.Params) []const evaluation.Region {
    var merged: std.ArrayList(evaluation.Region) = .empty;
    var out: std.ArrayList(evaluation.Region) = .empty;
    for (evaluation.runs(path)) |run| if (run.state == p.segment_state) {
        if (merged.items.len > 0 and run.start - merged.items[merged.items.len - 1].end - 1 <= p.merge_gap) merged.items[merged.items.len - 1].end = run.end else c.append(evaluation.Region,
             &merged, .{ .start = run.start, .end = run.end });
    };
    for (merged.items) |region| if (region.length() >= p.min_segment) c.append(evaluation.Region, &out, region);
    return out.items;
}
fn trueRegions(path: c.Path, state: usize) []const evaluation.Region {
    var out: std.ArrayList(evaluation.Region) = .empty;
    for (evaluation.runs(path)) |run| if (run.state == state) c.append(evaluation.Region, &out, .{ .start = run.start,
         .end = run.end });
    return out.items;
}
const Composition = struct { observed: i64 = 0, rich: i64 = 0, motifs: i64 = 0, first: i64 = 0, second: i64 = 0,
     island: bool = false };
fn composition(observation: c.Observation, region: evaluation.Region, p: c.Params) Composition {
    var out: Composition = .{};
    for (region.start - 1..region.end) |t| {
        const symbol = observation[t];
        if (symbol >= 0) {
            out.observed += 1;
            for (p.rich) |value| if (value == symbol) {
                out.rich += 1;
                break;
            };
            out.first += @intFromBool(symbol == p.first_motif);
            out.second += @intFromBool(symbol == p.second_motif);
        }
        if (t + 1 < region.end and symbol == p.first_motif and observation[t + 1] == p.second_motif) out.motifs += 1;
    }
    out.island = out.first * out.second > 0 and 100 * out.rich >= p.min_rich * out.observed and 100 * out.motifs * out.observed >= p.min_motif * out.first * out.second;
    return out;
}
fn add(target: *evaluation.MatchCounts, value: evaluation.MatchCounts) void {
    target.predicted += value.predicted;
    target.truth += value.truth;
    target.matched_predicted += value.matched_predicted;
    target.matched_truth += value.matched_truth;
}
const Evaluation = struct { matrix: c.Confusion = zero_confusion, positions: i64 = 0, correct_count: i64 = 0,
     regions: evaluation.MatchCounts = .{}, boundaries: evaluation.MatchCounts = .{}, bins: [10]i64 = [_]i64{0} ** 10,
     correct_bins: [10]i64 = [_]i64{0} ** 10, record_correct: [30]i64 = undefined };
fn evaluate(model: c.Model, records: []const c.Sequence, p: c.Params, decoder: usize) Evaluation {
    var out: Evaluation = .{};
    for (records, 0..) |sequence, i| {
        var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
        const permanent = c.allocator;
        c.allocator = scratch.allocator();
        const decoded = inference.decode(model, sequence.observation);
        const prediction = if (decoder == 0) decoded.viterbi.path else decoded.posterior;
        evaluation.accumulate(&out.matrix, sequence.truth, prediction);
        const correct_count = evaluation.correct(sequence.truth, prediction);
        out.positions += c.n(prediction.len);
        out.correct_count += correct_count;
        out.record_correct[i] = correct_count;
        add(&out.regions, evaluation.regionCounts(segments(prediction, p), trueRegions(sequence.truth, p.segment_state)));
        add(&out.boundaries, evaluation.boundaryCounts(prediction, sequence.truth, p.boundary_tolerance));
        if (decoder == 1) for (prediction, sequence.truth, decoded.confidence) |state, truth, confidence| {
            const bin = @min(@as(usize, 9), @as(usize, @intFromFloat(@floor(10 * confidence))));
            out.bins[bin] += 1;
            out.correct_bins[bin] += @intFromBool(state == truth);
        };
        c.allocator = permanent;
        scratch.deinit();
    }
    return out;
}
fn evaluationLines(model: c.Model, result: Evaluation, records: []const c.Sequence, p: c.Params, decoder: usize) c.Lines {
    var out: c.Lines = .{};
    out.add("EVALUATION {s} {s}", .{ model.name, if (decoder == 0) "VITERBI" else "POSTERIOR" });
    out.extend(evaluation.matrixLines(model, result.matrix));
    out.extend(evaluation.metricLines(model, result.matrix));
    out.add("REGIONS {c} predicted {d} true {d} precision {s} recall {s}", .{ model.states[p.segment_state],
         result.regions.predicted, result.regions.truth, evaluation.fraction(result.regions.matched_predicted,
         result.regions.predicted), evaluation.fraction(result.regions.matched_truth, result.regions.truth) });
    out.add("BOUNDARIES predicted {d} true {d} precision {s} recall {s}", .{ result.boundaries.predicted,
         result.boundaries.truth, evaluation.fraction(result.boundaries.matched_predicted, result.boundaries.predicted),
         evaluation.fraction(result.boundaries.matched_truth, result.boundaries.truth) });
    if (decoder == 1) for (0..10) |b| {
        if (result.bins[b] > 0) out.add("CALIBRATION 0.{d}-{s} positions {d} correct {d} accuracy {s}",
             .{ b, if (b == 9) "1.0" else c.fmt("0.{d}", .{b + 1}), result.bins[b], result.correct_bins[b],
             evaluation.fraction(result.correct_bins[b], result.bins[b]) });
    };
    for (records, 0..) |sequence, i| out.add("RECORD {s} length {d} correct {d}", .{ sequence.name,
         sequence.observation.len, result.record_correct[i] });
    return out;
}
fn stationary(model: c.Model) c.StateValues {
    var matrix = [_][5]f64{.{ 0, 0, 0, 0, 0 }} ** 4;
    const k = model.k();
    for (0..k - 1) |row| for (0..k) |column| {
        matrix[row][column] = model.transition[column][row] - (if (row == column) @as(f64, 1) else @as(f64, 0));
    };
    for (0..k) |column| matrix[k - 1][column] = 1;
    matrix[k - 1][k] = 1;
    for (0..k) |column| {
        var pivot = column;
        for (column + 1..k) |row| if (@abs(matrix[row][column]) > @abs(matrix[pivot][column])) {
            pivot = row;
        };
        std.mem.swap([5]f64, &matrix[pivot], &matrix[column]);
        const value = matrix[column][column];
        for (column..k + 1) |j| matrix[column][j] /= value;
        for (0..k) |row| if (row != column) {
            const factor = matrix[row][column];
            for (column..k + 1) |j| matrix[row][j] -= factor * matrix[column][j];
        };
    }
    var out: c.StateValues = .{ 0, 0, 0, 0 };
    for (0..k) |row| out[row] = matrix[row][k];
    return out;
}
const PathStats = struct { positions: [4]i64 = .{ 0, 0, 0, 0 }, runs: [4]i64 = .{ 0, 0, 0, 0 }, total: i64 = 0 };
fn pathStats(paths: []const c.Path) PathStats {
    var out: PathStats = .{};
    for (paths) |path| {
        out.total += c.n(path.len);
        for (path) |state| out.positions[state] += 1;
        for (evaluation.runs(path)) |run| out.runs[run.state] += 1;
    }
    return out;
}
fn maxChange(a: c.Model, b: c.Model) f64 {
    var out: f64 = 0;
    for (0..a.k()) |i| {
        out = @max(out, @abs(a.initial[i] - b.initial[i]));
        for (0..a.k()) |j| out = @max(out, @abs(a.transition[i][j] - b.transition[i][j]));
        for (0..a.m()) |j| out = @max(out, @abs(a.emission[i][j] - b.emission[i][j]));
    }
    return out;
}
fn nextPermutation(values: []usize) bool {
    if (values.len < 2) return false;
    var i = values.len - 1;
    while (i > 0 and values[i - 1] >= values[i]) i -= 1;
    if (i == 0) return false;
    const pivot = i - 1;
    var j = values.len - 1;
    while (values[j] <= values[pivot]) j -= 1;
    std.mem.swap(usize, &values[j], &values[pivot]);
    std.mem.reverse(usize, values[i..]);
    return true;
}
const CV = struct { matrix: c.Confusion = zero_confusion, correct_count: i64 = 0, positions: i64 = 0,
     fold_records: []i64, fold_positions: []i64, fold_correct: []i64 };
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    c.backing_allocator = init.gpa;
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.load(init.io);
    const p = parameters(input.parameters, input.model);
    const data = validate(input, p);
    const unlabeled = observations(data.unlabeled);
    const test_observations = observations(data.test_rows);
    var heldout_list: std.ArrayList(c.Observation) = .empty;
    for (observations(data.train)) |observation| c.append(c.Observation, &heldout_list, observation);
    for (test_observations) |observation| c.append(c.Observation, &heldout_list, observation);
    const heldout = heldout_list.items;
    const train_pairs = pairs(data.train);
    var models: [4]c.Model = undefined;
    models[0] = input.model;
    models[1] = input.model;
    var bw_trace: c.Lines = .{};
    var vit_trace: c.Lines = .{};
    var trained: c.Lines = .{};
    var decodings: c.Lines = .{};
    var segment_file: c.Lines = .{};
    var sample_file: c.Lines = .{};
    var evaluation_file: c.Lines = .{};
    var report: c.Lines = .{};
    bw_trace.add("iteration,loglik,heldout,change,max_change,status", .{});
    vit_trace.add("iteration,logprob,loglik,changed", .{});
    segment_file.add("sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island", .{});
    const likelihood = c.alloc(f64, p.iterations + 1);
    const held = c.alloc(f64, p.iterations + 1);
    var violations: usize = 0;
    var best_held: usize = 0;
    likelihood[0] = training.totalLoglik(models[1], unlabeled);
    held[0] = training.totalLoglik(models[1], heldout);
    bw_trace.add("0,{s},{s},,,", .{ r(likelihood[0]), r(held[0]) });
    for (1..p.iterations + 1) |iteration| {
        const previous = models[1];
        models[1] = training.baumWelch(previous, unlabeled, p.pseudocount);
        likelihood[iteration] = training.totalLoglik(models[1], unlabeled);
        held[iteration] = training.totalLoglik(models[1], heldout);
        const violation = likelihood[iteration] < likelihood[iteration - 1] - 0.000001 * @abs(likelihood[iteration - 1]);
        violations += @intFromBool(violation);
        if (held[iteration] > held[best_held]) best_held = iteration;
        bw_trace.add("{d},{s},{s},{s},{s},{s}", .{ iteration, r(likelihood[iteration]), r(held[iteration]),
             r(likelihood[iteration] - likelihood[iteration - 1]), c.decimal(maxChange(models[1],
             previous), 6), if (violation) "violation" else "ok" });
    }
    models[2] = input.model;
    const previous_paths = c.alloc(c.Path, unlabeled.len);
    var initial_probability: f64 = 0;
    for (unlabeled, previous_paths) |observation, *path| {
        const result = inference.viterbi(models[2], observation);
        path.* = result.path;
        initial_probability += result.logprob;
    }
    vit_trace.add("0,{s},{s},", .{ r(initial_probability), r(training.totalLoglik(models[2], unlabeled)) });
    var vit_iterations: usize = 0;
    var converged = false;
    for (1..p.iterations + 1) |iteration| {
        const current_pairs = c.alloc(c.Pair, unlabeled.len);
        for (unlabeled, previous_paths, current_pairs) |observation, path, *pair| pair.* = .{ .observation = observation,
             .path = path };
        models[2] = training.counting(input.model, current_pairs, p.pseudocount, "VITERBI_TRAINING");
        var changed: i64 = 0;
        var probability: f64 = 0;
        for (unlabeled, previous_paths) |observation, *path| {
            const result = inference.viterbi(models[2], observation);
            probability += result.logprob;
            changed += c.n(result.path.len) - evaluation.correct(path.*, result.path);
            path.* = result.path;
        }
        vit_trace.add("{d},{s},{s},{d}", .{ iteration, r(probability), r(training.totalLoglik(models[2], unlabeled)), changed });
        vit_iterations = iteration;
        converged = changed == 0;
        if (converged) break;
    }
    const cross_validation = c.alloc(CV, p.smoothing.len);
    var selected_candidate: usize = 0;
    for (p.smoothing, cross_validation, 0..) |alpha, *cv, candidate| {
        cv.* = .{ .fold_records = c.alloc(i64, p.folds), .fold_positions = c.alloc(i64, p.folds),
             .fold_correct = c.alloc(i64, p.folds) };
        @memset(cv.fold_records, 0);
        @memset(cv.fold_positions, 0);
        @memset(cv.fold_correct, 0);
        for (0..p.folds) |fold| {
            var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
            const permanent = c.allocator;
            c.allocator = scratch.allocator();
            var training_pairs: std.ArrayList(c.Pair) = .empty;
            for (train_pairs, 0..) |pair, i| if (i % p.folds != fold) c.append(c.Pair, &training_pairs, pair);
            const model = training.counting(input.model, training_pairs.items, alpha, "SUPERVISED");
            for (data.train, 0..) |sequence, i| if (i % p.folds == fold) {
                const decoded = inference.viterbi(model, sequence.observation);
                const correct_count = evaluation.correct(sequence.truth, decoded.path);
                cv.fold_records[fold] += 1;
                cv.fold_positions[fold] += c.n(sequence.truth.len);
                cv.fold_correct[fold] += correct_count;
                cv.positions += c.n(sequence.truth.len);
                cv.correct_count += correct_count;
                evaluation.accumulate(&cv.matrix, sequence.truth, decoded.path);
            };
            c.allocator = permanent;
            scratch.deinit();
        }
        if (cv.correct_count > cross_validation[selected_candidate].correct_count) selected_candidate = candidate;
    }
    models[3] = training.counting(input.model, train_pairs, p.smoothing[selected_candidate], "SUPERVISED");
    for (1..4) |model| {
        if (model > 1) trained.add("", .{});
        trained.extend(c.modelLines(models[model]));
    }
    var evaluations: [4][2]Evaluation = undefined;
    for (models, 0..) |model, index| for (0..2) |decoder| {
        evaluations[index][decoder] = evaluate(model, data.test_rows, p, decoder);
        if (evaluation_file.data.items.len > 0) evaluation_file.add("", .{});
        evaluation_file.extend(evaluationLines(model, evaluations[index][decoder], data.test_rows, p, decoder));
    };
    const cv = cross_validation[selected_candidate];
    evaluation_file.add("", .{});
    evaluation_file.add("CROSS_VALIDATION folds {d}", .{p.folds});
    for (cross_validation, p.candidates) |candidate, name| evaluation_file.add("SMOOTHING {s} positions {d} correct {d} accuracy {s}",
         .{ name, candidate.positions, candidate.correct_count, evaluation.fraction(candidate.correct_count,
         candidate.positions) });
    evaluation_file.add("SELECTED {s}", .{p.candidates[selected_candidate]});
    for (0..p.folds) |fold| evaluation_file.add("FOLD {d} records {d} positions {d} correct {d} accuracy {s}",
         .{ fold + 1, cv.fold_records[fold], cv.fold_positions[fold], cv.fold_correct[fold], evaluation.fraction(cv.fold_correct[fold],
         cv.fold_positions[fold]) });
    evaluation_file.extend(evaluation.matrixLines(input.model, cv.matrix));
    evaluation_file.extend(evaluation.metricLines(input.model, cv.matrix));
    evaluation_file.add("", .{});
    evaluation_file.add("LEARNING_CURVE", .{});
    const test_positions = evaluations[0][0].positions;
    for (1..train_pairs.len + 1) |count| {
        const model = training.counting(input.model, train_pairs[0..count], p.smoothing[selected_candidate], "SUPERVISED");
        var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
        const permanent = c.allocator;
        c.allocator = scratch.allocator();
        var correct_count: i64 = 0;
        for (data.test_rows) |sequence| correct_count += evaluation.correct(sequence.truth, inference.viterbi(model,
             sequence.observation).path);
        c.allocator = permanent;
        scratch.deinit();
        evaluation_file.add("RECORDS {d} correct {d} accuracy {s}", .{ count, correct_count, evaluation.fraction(correct_count,
             test_positions) });
    }
    var cached: [4][]inference.Decoding = undefined;
    for (models, &cached) |model, *results| {
        results.* = c.alloc(inference.Decoding, unlabeled.len);
        for (unlabeled, results.*) |observation, *result| result.* = inference.decode(model, observation);
    }
    var posterior_generator: sampler.Generator = .{ .state = p.posterior_seed };
    const bw = models[1];
    for (data.unlabeled, 0..) |sequence, index| {
        const decoded = cached[1][index];
        const samples = c.alloc(c.Path, p.posterior_samples);
        var segment_count: i64 = 0;
        for (samples) |*sample| {
            sample.* = sampler.posteriorSample(bw, decoded.fb, &posterior_generator);
            segment_count += c.n(segments(sample.*, p).len);
        }
        const differences = c.n(sequence.observation.len) - evaluation.correct(decoded.viterbi.path, decoded.posterior);
        var uncertain: usize = 0;
        const confident = c.dupe(u8, stateString(decoded.posterior, bw.states));
        const imputed = c.alloc(u8, sequence.observation.len);
        for (sequence.observation, 0..) |observed, t| {
            if (decoded.confidence[t] < p.confidence) {
                uncertain += 1;
                confident[t] = '.';
            }
            if (observed >= 0) imputed[t] = bw.symbols[c.u(observed)] else {
                var probabilities = [_]f64{0} ** 8;
                for (0..bw.m()) |symbol| for (0..bw.k()) |state| {
                    probabilities[symbol] += decoded.fb.posterior[t][state] * bw.emission[state][symbol];
                };
                const symbol = bw.symbols[inference.maximum(probabilities[0..bw.m()])];
                imputed[t] = symbol - 'A' + 'a';
            }
        }
        decodings.add("SEQUENCE {s} length {d} loglik {s} viterbi {s} differences {d} uncertain {d} expected_segments {s}",
             .{ sequence.name, sequence.observation.len, r(decoded.fb.loglik), r(decoded.viterbi.logprob),
             differences, uncertain, ratio(c.f(segment_count), c.n(p.posterior_samples)) });
        decodings.add("VITERBI {s}", .{stateString(decoded.viterbi.path, bw.states)});
        decodings.add("POSTERIOR {s}", .{stateString(decoded.posterior, bw.states)});
        decodings.add("CONFIDENT {s}", .{confident});
        decodings.add("IMPUTED {s}", .{imputed});
        for (0..2) |decoder| {
            const path = if (decoder == 0) decoded.viterbi.path else decoded.posterior;
            for (segments(path, p)) |region| {
                var mean: f64 = 0;
                for (region.start - 1..region.end) |t| mean += decoded.fb.posterior[t][p.segment_state];
                mean /= c.f(region.length());
                var support: usize = 0;
                for (samples) |sample| {
                    var inside: usize = 0;
                    for (sample[region.start - 1 .. region.end]) |state| inside += @intFromBool(state == p.segment_state);
                    support += @intFromBool(2 * inside > region.length());
                }
                const result = composition(sequence.observation, region, p);
                segment_file.add("{s},{s},{d},{d},{d},{s},{d},{s},{s},{s}", .{ sequence.name, if (decoder == 0) "viterbi" else "posterior",
                     region.start, region.end, region.length(), r(mean), support, ratio(c.f(result.rich),
                     result.observed), ratio(c.f(result.motifs * result.observed), result.first * result.second),
                     if (result.island) "yes" else "no" });
            }
        }
    }
    var sample_generator: sampler.Generator = .{ .state = p.sample_seed };
    var viterbi_correct: i64 = 0;
    var posterior_correct: i64 = 0;
    for (1..p.sample_count + 1) |sample| {
        const generated = sampler.synthetic(bw, p.sample_length, &sample_generator);
        const decoded = inference.decode(bw, generated.observation);
        const vc = evaluation.correct(generated.path, decoded.viterbi.path);
        const pc = evaluation.correct(generated.path, decoded.posterior);
        viterbi_correct += vc;
        posterior_correct += pc;
        sample_file.add("SAMPLE {d} loglik {s} viterbi {s} viterbi_correct {d} posterior_correct {d}",
             .{ sample, r(decoded.fb.loglik), r(decoded.viterbi.logprob), vc, pc });
        sample_file.add("STATES {s}", .{stateString(generated.path, bw.states)});
        sample_file.add("SYMBOLS {s}", .{symbolString(generated.observation, bw.symbols)});
        sample_file.add("VITERBI {s}", .{stateString(decoded.viterbi.path, bw.states)});
        sample_file.add("POSTERIOR {s}", .{stateString(decoded.posterior, bw.states)});
    }
    const synthetic_positions = c.n(p.sample_count * p.sample_length);
    sample_file.add("TOTAL positions {d} viterbi_accuracy {s} posterior_accuracy {s}", .{ synthetic_positions,
         evaluation.fraction(viterbi_correct, synthetic_positions), evaluation.fraction(posterior_correct,
         synthetic_positions) });
    var unlabeled_positions: i64 = 0;
    var unlabeled_missing: i64 = 0;
    var labeled_positions: i64 = 0;
    var labeled_missing: i64 = 0;
    var symbol_counts = [_]i64{0} ** 8;
    for (data.unlabeled) |sequence| {
        unlabeled_positions += c.n(sequence.observation.len);
        for (sequence.observation) |symbol| {
            if (symbol < 0) unlabeled_missing += 1 else symbol_counts[c.u(symbol)] += 1;
        }
    }
    for (data.train) |sequence| {
        labeled_positions += c.n(sequence.observation.len);
        labeled_missing += c.n(missingCount(sequence.observation));
    }
    for (data.test_rows) |sequence| {
        labeled_positions += c.n(sequence.observation.len);
        labeled_missing += c.n(missingCount(sequence.observation));
    }
    report.add("INPUT", .{});
    report.add("SEQUENCES accepted {d} rejected {d} positions {d} missing {d}", .{ data.unlabeled.len,
         data.sequence_rejected, unlabeled_positions, unlabeled_missing });
    report.add("LABELED train {d} test {d} rejected {d} positions {d} missing {d}", .{ data.train.len,
         data.test_rows.len, data.labeled_rejected, labeled_positions, labeled_missing });
    report.extend(data.rejected);
    var composition_line: c.Text = .{};
    composition_line.add("COMPOSITION", .{});
    for (input.model.symbols, 0..) |symbol, i| composition_line.add(" {c} {s}", .{ symbol, ratio(c.f(symbol_counts[i]),
         unlabeled_positions - unlabeled_missing) });
    report.add("{s}", .{composition_line.value()});
    const roles = [_][]const c.Sequence{ data.train, data.test_rows };
    for (roles, 0..) |records, role| {
        const truth = c.alloc(c.Path, records.len);
        for (records, truth) |sequence, *path| path.* = sequence.truth;
        const stats = pathStats(truth);
        for (input.model.states, 0..) |state, i| report.add("TRUTH {s} {c} occupancy {s} mean_run {s}",
             .{ if (role == 0) "TRAIN" else "TEST", state, ratio(c.f(stats.positions[i]), stats.total),
             ratio(c.f(stats.positions[i]), stats.runs[i]) });
    }
    report.add("", .{});
    report.add("TRAINING BAUM_WELCH iterations {d} initial_loglik {s} final_loglik {s} violations {d} best_heldout_iteration {d}",
         .{ p.iterations, r(likelihood[0]), r(likelihood[p.iterations]), violations, best_held });
    report.add("TRAINING VITERBI_TRAINING iterations {d} converged {s}", .{ vit_iterations, if (converged) "yes" else "no" });
    report.add("TRAINING SUPERVISED smoothing {s}", .{p.candidates[selected_candidate]});
    var preference = [_]usize{0} ** 4;
    for (0..unlabeled.len) |index| {
        var best: usize = 0;
        for (1..4) |model| if (cached[model][index].fb.loglik > cached[best][index].fb.loglik) {
            best = model;
        };
        preference[best] += 1;
    }
    report.add("PREFERENCE INITIAL {d} BAUM_WELCH {d} VITERBI_TRAINING {d} SUPERVISED {d}", .{ preference[0],
         preference[1], preference[2], preference[3] });
    for (0..4) |first| for (first + 1..4) |second| {
        var agreement: i64 = 0;
        for (0..unlabeled.len) |index| agreement += evaluation.correct(cached[first][index].viterbi.path,
             cached[second][index].viterbi.path);
        report.add("AGREEMENT {s} {s} {s}", .{ models[first].name, models[second].name, evaluation.fraction(agreement,
             unlabeled_positions) });
    };
    for (0..2) |decoder| {
        var best: usize = 0;
        for (1..4) |model| if (evaluations[model][decoder].correct_count > evaluations[best][decoder].correct_count) {
            best = model;
        };
        report.add("BEST {s} {s} accuracy {s}", .{ if (decoder == 0) "VITERBI" else "POSTERIOR", models[best].name,
             evaluation.fraction(evaluations[best][decoder].correct_count, test_positions) });
    }
    for (models, 0..) |model, model_index| {
        var loglik: f64 = 0;
        const paths = c.alloc(c.Path, unlabeled.len);
        var segment_count: i64 = 0;
        var segment_length: i64 = 0;
        var islands: i64 = 0;
        for (unlabeled, paths, 0..) |observation, *path, index| {
            const decoded = cached[model_index][index];
            loglik += decoded.fb.loglik;
            path.* = decoded.viterbi.path;
            for (segments(decoded.viterbi.path, p)) |region| {
                segment_count += 1;
                segment_length += c.n(region.length());
                islands += @intFromBool(composition(observation, region, p).island);
            }
        }
        const stats = pathStats(paths);
        const phi = stationary(model);
        var alignment = zero_confusion;
        var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
        const permanent = c.allocator;
        c.allocator = scratch.allocator();
        for (data.train) |sequence| evaluation.accumulate(&alignment, sequence.truth, inference.viterbi(model,
             sequence.observation).path);
        c.allocator = permanent;
        scratch.deinit();
        var permutation = [_]usize{ 0, 1, 2, 3 };
        var best_permutation: [4]usize = undefined;
        var best_agreement: i64 = -1;
        while (true) {
            var agreement: i64 = 0;
            for (0..model.k()) |state| agreement += alignment[permutation[state]][state];
            if (agreement > best_agreement) {
                best_agreement = agreement;
                best_permutation = permutation;
            }
            if (!nextPermutation(permutation[0..model.k()])) break;
        }
        report.add("", .{});
        report.add("MODEL {s}", .{model.name});
        report.add("LOGLIK unlabeled {s} per_symbol {s} test {s}", .{ r(loglik), ratio(loglik, unlabeled_positions - unlabeled_missing),
             r(training.totalLoglik(model, test_observations)) });
        report.add("SEGMENTS count {d} mean_length {s} islands {d}", .{ segment_count, ratio(c.f(segment_length),
             segment_count), islands });
        var mapping: c.Text = .{};
        mapping.add("ALIGNMENT", .{});
        for (model.states, 0..) |state, i| mapping.add(" {c}={c}", .{ state, model.states[best_permutation[i]] });
        var train_positions: i64 = 0;
        for (data.train) |sequence| train_positions += c.n(sequence.truth.len);
        report.add("{s} agreement {s}", .{ mapping.value(), evaluation.fraction(best_agreement, train_positions) });
        for (model.states, 0..) |state, i| report.add("STATE {c} stationary {s} duration {s} occupancy {s} mean_run {s}",
             .{ state, r(phi[i]), r(1 / (1 - model.transition[i][i])), ratio(c.f(stats.positions[i]),
             stats.total), ratio(c.f(stats.positions[i]), stats.runs[i]) });
    }
    try c.save(init.io, "trained_model.txt", trained);
    try c.save(init.io, "loglik_trace.csv", bw_trace);
    try c.save(init.io, "viterbi_trace.csv", vit_trace);
    try c.save(init.io, "decodings.txt", decodings);
    try c.save(init.io, "segments.csv", segment_file);
    try c.save(init.io, "samples.txt", sample_file);
    try c.save(init.io, "evaluation.txt", evaluation_file);
    try c.save(init.io, "report.txt", report);
}
