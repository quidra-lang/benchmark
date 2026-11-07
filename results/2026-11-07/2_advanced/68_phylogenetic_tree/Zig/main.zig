const std = @import("std");
const d = @import("alignment.zig");
const distances = @import("distances.zig");
const building = @import("tree_building.zig");
const parsimony = @import("parsimony.zig");
const output = @import("tree_io.zig");
const Tree = building.Tree;
const Rooted = building.Rooted;
const Matrix = distances.Matrix;
const real = output.real;
const symbols = output.symbols;
const f = d.f;
const n = d.n;
const u = d.u;
const bit = d.bit;
const models = [_][]const u8{ "P", "JC", "K2P" };
const methods = [_][]const u8{ "NJ_P", "NJ_JC", "NJ_K2P", "ME", "MP", "CONSENSUS" };
fn contains(masks: []const u32, mask: u32) bool {
    return std.mem.indexOfScalar(u32, masks, mask) != null;
}
fn addMask(masks: *std.ArrayList(u32), mask: u32) void {
    if (!contains(masks.items, mask)) d.append(u32, masks, mask);
}
fn maskLess(_: void, a: u32, b: u32) bool {
    for (0..16) |t| if ((a & bit(t)) != (b & bit(t))) return a & bit(t) != 0;
    return false;
}
fn symbolOrder(masks: []const u32) []const u32 {
    const out = d.dupe(u32, masks);
    std.mem.sort(u32, out, {}, maskLess);
    return out;
}
fn rf(a: []const u32, b: []const u32) usize {
    var count: usize = 0;
    for (a) |mask| count += @intFromBool(!contains(b, mask));
    for (b) |mask| count += @intFromBool(!contains(a, mask));
    return count;
}
fn splitSet(tree: *const Tree, outgroup: usize) []const u32 {
    const root = Rooted.init(tree, outgroup);
    return root.splits(tree);
}
fn sum(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value;
    return total;
}
fn square(value: f64) f64 {
    return value * value;
}
fn integer(value: f64) i64 {
    return @intFromFloat(value);
}
const Params = struct { model: usize, outgroup: []const u8, replicates: usize, seed: i64, maximum_missing: i64,
     saturation: f64, exhaustive: []const []const u8, low_sites: usize };
fn readParameters(io: std.Io) !Params {
    const lines = try d.readLines(io, "input/params.txt");
    return .{ .model = d.indexOf(&models, d.words(lines[0])[1]).?, .outgroup = d.words(lines[1])[1],
         .replicates = u(d.number(d.words(lines[2])[1])), .seed = d.number(d.words(lines[3])[1]),
         .maximum_missing = d.number(d.words(lines[4])[1]), .saturation = std.fmt.parseFloat(f64,
         d.words(lines[5])[1]) catch unreachable, .exhaustive = d.words(lines[6])[1..], .low_sites = u(d.number(d.words(lines[7])[1])) };
}
const Addition = struct { taxon: usize, mask: u32, score: i64, ties: usize };
const Stepwise = struct { tree: Tree, initial: i64, score: i64, evaluated: usize = 0, taxa: []const usize,
     additions: std.ArrayList(Addition) = .empty };
const Move = struct { mask: u32, swap: usize, value: f64 };
const Search = struct { tree: Tree, value: f64, evaluated: usize = 0, moves: std.ArrayList(Move) = .empty };
const ExhaustiveRecord = struct { tree: Tree, score: i64, bme: f64, newick: []const u8, splits: []const u32 };
const Exhaustive = struct { taxa: []const usize, records: []const ExhaustiveRecord, optimal: []const usize,
     best_score: i64, best_bme: usize, second_bme: f64, heuristic: i64, strict: Tree };
fn optimalLess(records: []const ExhaustiveRecord, a: usize, b: usize) bool {
    return std.mem.order(u8, records[a].newick, records[b].newick) == .lt;
}
const Support = struct { mask: u32, count: i64 };
fn supportLess(_: void, a: Support, b: Support) bool {
    return if (a.count != b.count) a.count > b.count else maskLess({}, a.mask, b.mask);
}
fn lowLess(values: []const f64, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] < values[b] else a < b;
}
const Study = struct {
    params: Params,
    records: []const d.Record,
    names: []const []const u8,
    sequences: []const []const u8,
    rejected: d.Lines,
    patterns: d.Patterns,
    size: usize,
    length: usize,
    outgroup: usize,
    taxa: []const usize,
    pairs: []const distances.Pair,
    matrices: [3]Matrix = undefined,
    patristics: [3]Matrix = undefined,
    saturated: [3][]const distances.Pair = undefined,
    trees: [6]Tree = undefined,
    nj_scores: [3]i64 = undefined,
    site_logs: [3][]const f64 = undefined,
    support: []i64,
    minimum: i64 = 0,
    maximum: i64 = 0,
    minima: []const i64 = &.{},
    initial: Stepwise = undefined,
    me: Search = undefined,
    mp: Search = undefined,
    reconstruction: parsimony.Reconstruction = undefined,
    exhaustive: Exhaustive = undefined,
    me_start: f64 = 0,
    bootstrap_lines: d.Lines = .{},
    fn init(io: std.Io) !Study {
        const params = try readParameters(io);
        const records = try d.readFasta(io);
        const length = records[0].sequence.len;
        var names: std.ArrayList([]const u8) = .empty;
        var sequences: std.ArrayList([]const u8) = .empty;
        var rejected: d.Lines = .{};
        for (records, 0..) |record, index| {
            var reason: ?[]const u8 = null;
            for (records[0..index]) |earlier| if (d.eq(record.name, earlier.name)) {
                reason = "duplicate name";
                break;
            };
            if (reason == null) for (record.sequence, 1..) |character, column| {
                if (d.baseSet(character) == 0) {
                    reason = d.fmt("invalid character {c} at column {d}", .{ character, column });
                    break;
                }
            };
            if (reason == null and record.sequence.len != length) reason = d.fmt("length mismatch {d}",
                 .{record.sequence.len});
            if (reason == null) {
                var missing: i64 = 0;
                for (record.sequence) |character| missing += @intFromBool(character == '-' or character == 'N');
                if (100 * missing > params.maximum_missing * n(length)) reason = d.fmt("too many missing {d}",
                     .{missing});
            }
            if (reason) |why| rejected.add("REJECT line {d} {s} {s}", .{ record.line, record.name, why }) else {
                d.append([]const u8, &names, record.name);
                d.append([]const u8, &sequences, record.sequence);
            }
        }
        const taxa = d.alloc(usize, names.items.len);
        for (taxa, 0..) |*taxon, i| taxon.* = i;
        const weights = d.alloc(i64, length);
        @memset(weights, 1);
        const support = d.alloc(i64, 65536);
        @memset(support, 0);
        var out: Study = .{ .params = params, .records = records, .names = names.items, .sequences = sequences.items,
             .rejected = rejected, .patterns = d.Patterns.init(sequences.items), .size = names.items.len,
             .length = length, .outgroup = d.indexOf(names.items, params.outgroup).?, .taxa = taxa,
             .pairs = distances.allPairs(sequences.items, weights), .support = support };
        for (0..3) |model| {
            const built = distances.buildMatrix(out.pairs, model, params.saturation);
            out.matrices[model] = built.matrix;
            out.saturated[model] = built.saturated;
            out.trees[model] = building.neighborJoining(&out.matrices[model], out.size, taxa);
            out.patristics[model] = building.patristic(&out.trees[model]);
            out.nj_scores[model] = parsimony.score(&out.trees[model], out.patterns, out.outgroup);
            out.site_logs[model] = out.likelihoodSites(&out.trees[model]);
        }
        return out;
    }
    fn summary(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        out.add("INPUT records {d} accepted {d} rejected {d} columns {d}", .{ self.records.len,
             self.size, self.rejected.data.items.len, self.length });
        out.extend(self.rejected);
        const columns = d.alloc([4]i64, self.length);
        @memset(columns, [_]i64{0} ** 4);
        var composition = [_]i64{0} ** 4;
        for (0..self.length) |c| for (self.sequences) |sequence| {
            if (d.baseIndex(sequence[c])) |base| columns[c][base] += 1;
        };
        for (self.names, self.sequences) |name, sequence| {
            var counts = [_]i64{0} ** 4;
            var ambiguous: i64 = 0;
            var missing: i64 = 0;
            var unique: i64 = 0;
            for (sequence, 0..) |character, c| {
                if (d.baseIndex(character)) |base| {
                    counts[base] += 1;
                    var total: i64 = 0;
                    for (columns[c]) |count| total += count;
                    unique += @intFromBool(columns[c][base] == 1 and total > 1);
                } else if (character == 'N' or character == '-') missing += 1 else ambiguous += 1;
            }
            var bases: i64 = 0;
            for (counts, 0..) |count, b| {
                bases += count;
                composition[b] += count;
            }
            out.add("TAXON {s} bases {d} ambiguous {d} missing {d} unique {d} gc {s}", .{ name,
                 bases, ambiguous, missing, unique, real(f(counts[1] + counts[2]) / f(bases),
                 4) });
        }
        const classes = d.classify(self.sequences);
        out.add("COLUMNS constant {d} variable {d} informative {d} gapped {d} empty {d}", .{ classes.constant,
             classes.variable, classes.informative, classes.gapped, classes.empty });
        out.add("PATTERNS {d}", .{self.patterns.text.len});
        var total: i64 = 0;
        for (composition) |count| total += count;
        out.add("COMPOSITION A {s} C {s} G {s} T {s}", .{ real(f(composition[0]) / f(total),
             4), real(f(composition[1]) / f(total), 4), real(f(composition[2]) / f(total),
             4), real(f(composition[3]) / f(total), 4) });
        return out;
    }
    fn bme(self: *const Study, tree: *const Tree) f64 {
        var value: f64 = 0;
        const taxa = tree.taxa();
        for (taxa) |a| {
            const steps = building.paths(tree, a, true);
            for (taxa) |b| if (a < b) {
                const exponent: usize = @intFromFloat(steps[b] - 1);
                const denominator = f(@as(u64, 1) << @intCast(exponent));
                value += self.matrices[self.params.model][a][b] / denominator;
            };
        }
        return value;
    }
    fn stepwise(self: *const Study, taxa: []const usize) Stepwise {
        const start = building.star(self.size, taxa[0..3]);
        const initial = parsimony.score(&start, self.patterns, self.outgroup);
        var out: Stepwise = .{ .tree = start, .initial = initial, .score = initial, .taxa = taxa };
        for (taxa[3..]) |taxon| {
            var best: i64 = std.math.maxInt(i64);
            var chosen: Tree = undefined;
            var chosen_mask: u32 = 0;
            var ties: usize = 0;
            for (parsimony.branches(&out.tree, self.outgroup)) |branch| {
                const candidate = parsimony.insert(&out.tree, branch.first, branch.second, taxon);
                const value = parsimony.score(&candidate, self.patterns, self.outgroup);
                out.evaluated += 1;
                if (value < best) {
                    best = value;
                    chosen = candidate;
                    chosen_mask = branch.mask;
                    ties = 1;
                } else if (value == best) ties += 1;
            }
            out.tree = chosen;
            out.score = best;
            d.append(Addition, &out.additions, .{ .taxon = taxon, .mask = chosen_mask, .score = best, .ties = ties });
        }
        return out;
    }
    fn hillClimb(self: *const Study, start: *const Tree, minimum_evolution: bool, value: f64) Search {
        var out: Search = .{ .tree = start.*, .value = value };
        var candidates: std.ArrayList(parsimony.Swap) = .empty;
        while (true) {
            var moved = false;
            parsimony.nniCandidates(&out.tree, self.outgroup, &candidates);
            for (candidates.items) |*candidate| {
                const result = if (minimum_evolution) self.bme(&candidate.tree) else f(parsimony.score(&candidate.tree,
                     self.patterns, self.outgroup));
                out.evaluated += 1;
                if (result < out.value) {
                    out.tree = candidate.tree;
                    out.value = result;
                    d.append(Move, &out.moves, .{ .mask = candidate.mask, .swap = candidate.number, .value = result });
                    moved = true;
                    break;
                }
            }
            if (!moved) break;
        }
        return out;
    }
    fn consensusFill(tree: *Tree, parent: usize, region: u32, clades: []const u32, taxa: []const usize) void {
        var covered: u32 = 0;
        for (clades) |candidate| {
            if (candidate == region or candidate & region != candidate) continue;
            var maximal = true;
            for (clades) |other| if (other != region and candidate != other and other & region == other and candidate & other == candidate) {
                maximal = false;
            };
            if (maximal) {
                const node = tree.internal();
                tree.connect(parent, node, 0);
                consensusFill(tree, node, candidate, clades, taxa);
                covered |= candidate;
            }
        }
        for (taxa) |taxon| if (region & bit(taxon) != 0 and covered & bit(taxon) == 0) tree.connect(parent, taxon, 0);
    }
    fn consensus(self: *const Study, taxa: []const usize, clades: []const u32) Tree {
        var tree = Tree.init(self.size);
        const root = tree.internal();
        tree.connect(root, self.outgroup, 0);
        var ingroup: u32 = 0;
        for (taxa) |taxon| if (taxon != self.outgroup) {
            ingroup |= bit(taxon);
        };
        consensusFill(&tree, root, ingroup, clades, taxa);
        return tree;
    }
    fn exhaustiveSearch(self: *const Study, taxa: []const usize) Exhaustive {
        var forest: std.ArrayList(Tree) = .empty;
        d.append(Tree, &forest, building.star(self.size, taxa[0..3]));
        for (taxa[3..]) |taxon| {
            var expanded: std.ArrayList(Tree) = .empty;
            for (forest.items) |*tree| for (parsimony.branches(tree, self.outgroup)) |branch| {
                d.append(Tree, &expanded, parsimony.insert(tree, branch.first, branch.second, taxon));
            };
            forest = expanded;
        }
        const records = d.alloc(ExhaustiveRecord, forest.items.len);
        var best_score: i64 = std.math.maxInt(i64);
        for (forest.items, records) |*tree, *record| {
            const score = parsimony.score(tree, self.patterns, self.outgroup);
            record.* = .{ .tree = tree.*, .score = score, .bme = self.bme(tree), .newick = output.newick(tree,
                 self.names, self.outgroup, false, null), .splits = splitSet(tree, self.outgroup) };
            best_score = @min(best_score, score);
        }
        var optimal: std.ArrayList(usize) = .empty;
        for (records, 0..) |record, i| if (record.score == best_score) d.append(usize, &optimal, i);
        std.mem.sort(usize, optimal.items, @as([]const ExhaustiveRecord, records), optimalLess);
        var common: std.ArrayList(u32) = .empty;
        for (records[optimal.items[0]].splits) |mask| d.append(u32, &common, mask);
        for (optimal.items) |index| {
            var retained: std.ArrayList(u32) = .empty;
            for (common.items) |mask| if (contains(records[index].splits, mask)) d.append(u32, &retained, mask);
            common = retained;
        }
        const strict = self.consensus(taxa, common.items);
        const initial = self.stepwise(taxa);
        const searched = self.hillClimb(&initial.tree, false, f(initial.score));
        var best_bme: usize = 0;
        for (records, 0..) |record, i| {
            const best = records[best_bme];
            if (record.bme < best.bme or (record.bme == best.bme and std.mem.order(u8, record.newick,
                 best.newick) == .lt)) best_bme = i;
        }
        var second = std.math.inf(f64);
        for (records, 0..) |record, i| if (i != best_bme) {
            second = @min(second, record.bme);
        };
        return .{ .taxa = taxa, .records = records, .optimal = optimal.items, .best_score = best_score,
             .best_bme = best_bme, .second_bme = second, .heuristic = integer(searched.value),
             .strict = strict };
    }
    fn likelihoodSites(self: *const Study, tree: *const Tree) []const f64 {
        const root = Rooted.init(tree, self.outgroup);
        const values = d.alloc(f64, self.patterns.encoded.len);
        for (self.patterns.encoded, values) |pattern, *value| {
            var partial = [_][4]f64{[_]f64{0} ** 4} ** 32;
            var i = root.count;
            while (i > 0) {
                i -= 1;
                const node = root.order[i];
                if (node < self.size) {
                    for (0..4) |x| partial[node][x] = if (pattern[node] & (@as(u8, 1) << @intCast(x)) != 0) 1 else 0;
                } else for (0..4) |x| {
                    var product: f64 = 1;
                    for (root.children[node][0..root.child_count[node]]) |child| {
                        const exponential = @exp(-4 * tree.length[node][child] / 3);
                        var subtotal: f64 = 0;
                        for (0..4) |y| {
                            const probability = if (x == y) 0.25 + 0.75 * exponential else 0.25 - 0.25 * exponential;
                            subtotal += probability * partial[child][y];
                        }
                        product *= subtotal;
                    }
                    partial[node][x] = product;
                };
            }
            var probability: f64 = 0;
            for (partial[root.root]) |item| probability += 0.25 * item;
            value.* = @log(probability);
        }
        const out = d.alloc(f64, self.length);
        for (self.patterns.columns, out) |index, *value| value.* = values[index];
        return out;
    }
    fn bounds(self: *Study) void {
        const lower = d.alloc(i64, self.patterns.encoded.len);
        for (self.patterns.encoded, self.patterns.weights, lower) |pattern, weight, *minimum| {
            var low: i64 = 4;
            var high = n(self.size);
            for (1..16) |mask| {
                var covers = true;
                for (pattern[0..self.size]) |set| if (mask & set == 0) {
                    covers = false;
                };
                if (covers) low = @min(low, n(@popCount(mask)) - 1);
            }
            for (0..4) |b| {
                var misses: i64 = 0;
                for (pattern[0..self.size]) |set| misses += @intFromBool(set & (@as(u8, 1) << @intCast(b)) == 0);
                high = @min(high, misses);
            }
            minimum.* = low;
            self.maximum += high * weight;
        }
        const minima = d.alloc(i64, self.length);
        for (self.patterns.columns, minima) |index, *minimum| {
            minimum.* = lower[index];
            self.minimum += minimum.*;
        }
        self.minima = minima;
    }
    fn bootstrap(self: *Study) void {
        const main_splits = splitSet(&self.trees[self.params.model], self.outgroup);
        var state = self.params.seed;
        self.bootstrap_lines.add("BOOTSTRAP model {s} replicates {d} seed {d}", .{ models[self.params.model],
             self.params.replicates, state });
        var identical: usize = 0;
        const weights = d.alloc(i64, self.length);
        for (1..self.params.replicates + 1) |replicate| {
            @memset(weights, 0);
            for (0..self.length) |_| {
                state = @mod(48271 * state, 2147483647);
                weights[u(@mod(state, n(self.length)))] += 1;
            }
            const built = distances.buildMatrix(distances.allPairs(self.sequences, weights),
                 self.params.model, self.params.saturation);
            const tree = building.neighborJoining(&built.matrix, self.size, self.taxa);
            const splits = splitSet(&tree, self.outgroup);
            for (splits) |mask| self.support[mask] += 1;
            const difference = rf(main_splits, splits);
            identical += @intFromBool(difference == 0);
            var distinct: usize = 0;
            for (weights) |count| distinct += @intFromBool(count > 0);
            self.bootstrap_lines.add("REPLICATE {d} distinct {d} rf {d}", .{ replicate, distinct, difference });
        }
        self.bootstrap_lines.add("IDENTICAL {d}", .{identical});
        for (symbolOrder(main_splits)) |mask| self.bootstrap_lines.add("SUPPORT {s} {d}", .{ symbols(mask,
             self.size), self.support[mask] });
        var ranked: std.ArrayList(Support) = .empty;
        var majority: std.ArrayList(u32) = .empty;
        for (0..@as(usize, bit(self.size))) |value| {
            const mask: u32 = @intCast(value);
            const count = self.support[mask];
            if (count > 0) {
                d.append(Support, &ranked, .{ .mask = mask, .count = count });
                if (2 * count > n(self.params.replicates)) d.append(u32, &majority, mask);
            }
        }
        std.mem.sort(Support, ranked.items, {}, supportLess);
        for (ranked.items) |item| self.bootstrap_lines.add("SPLIT {s} {d}", .{ symbols(item.mask,
             self.size), item.count });
        self.trees[5] = self.consensus(self.taxa, majority.items);
        self.bootstrap_lines.add("CONSENSUS {s}", .{output.newick(&self.trees[5], self.names,
             self.outgroup, false, self.support)});
        for (0..self.size) |removed| {
            if (removed == self.outgroup) continue;
            var kept: std.ArrayList(usize) = .empty;
            for (self.taxa) |taxon| if (taxon != removed) d.append(usize, &kept, taxon);
            const tree = building.neighborJoining(&self.matrices[self.params.model], self.size, kept.items);
            var reduced: std.ArrayList(u32) = .empty;
            for (main_splits) |mask| {
                const after = mask & ~bit(removed);
                if (@popCount(after) >= 2 and @popCount(after) <= self.size - 3) addMask(&reduced, after);
            }
            self.bootstrap_lines.add("JACKKNIFE {s} rf {d}", .{ self.names[removed], rf(splitSet(&tree,
                 self.outgroup), reduced.items) });
        }
    }
    fn matrixLines(self: *const Study, out: *d.Lines, matrix: *const Matrix) void {
        var width: usize = 0;
        for (self.names) |name| width = @max(width, name.len);
        for (self.names, 0..) |name, a| {
            var row: d.Text = .{};
            row.add("{s}", .{name});
            for (0..width - name.len) |_| row.add(" ", .{});
            for (0..self.size) |b| row.add(" {s}", .{real(matrix[a][b], 5)});
            out.add("{s}", .{row.value()});
        }
    }
    fn distancesReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        var sites: i64 = 0;
        var transitions: i64 = 0;
        var transversions: i64 = 0;
        for (self.pairs) |pair| {
            out.add("PAIR {s} {s} sites {d} transitions {d} transversions {d}", .{ self.names[pair.first],
                 self.names[pair.second], pair.sites, pair.transitions, pair.transversions });
            sites += pair.sites;
            transitions += pair.transitions;
            transversions += pair.transversions;
        }
        out.add("TOTAL sites {d} transitions {d} transversions {d}", .{ sites, transitions, transversions });
        for (0..3) |model| {
            out.add("", .{});
            out.add("MODEL {s}", .{models[model]});
            self.matrixLines(&out, &self.matrices[model]);
            for (self.saturated[model]) |pair| out.add("SATURATED {s} {s} sites {d}", .{ self.names[pair.first],
                 self.names[pair.second], pair.sites });
        }
        out.add("", .{});
        out.add("PATRISTIC {s}", .{methods[self.params.model]});
        self.matrixLines(&out, &self.patristics[self.params.model]);
        out.add("", .{});
        out.add("ME start {s} length {s}", .{ methods[self.params.model], real(self.me_start, 5) });
        for (self.me.moves.items) |move| out.add("NNI edge {s} swap {d} length {s}", .{ symbols(move.mask,
             self.size), move.swap, real(move.value, 5) });
        out.add("ME moves {d} evaluated {d} length {s}", .{ self.me.moves.items.len, self.me.evaluated,
             real(self.me.value, 5) });
        const best = self.exhaustive.records[self.exhaustive.best_bme];
        out.add("EXHAUSTIVE taxa {d} trees {d} best {s} second {s}", .{ self.exhaustive.taxa.len,
             self.exhaustive.records.len, real(best.bme, 5), real(self.exhaustive.second_bme,
             5) });
        out.add("BEST {s} parsimony {d}", .{ best.newick, best.score });
        return out;
    }
    fn scoreLine(self: *const Study, out: *d.Lines, method: []const u8, score: i64) void {
        out.add("TREE {s} score {d} ci {s} ri {s}", .{ method, score, real(f(self.minimum) / f(score),
             4), real(f(self.maximum - score) / f(self.maximum - self.minimum), 4) });
    }
    fn parsimonyReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        out.add("BOUNDS minimum {d} maximum {d}", .{ self.minimum, self.maximum });
        for (0..3) |i| self.scoreLine(&out, methods[i], self.nj_scores[i]);
        out.add("START {s} {s} {s} score {d}", .{ self.names[self.initial.taxa[0]], self.names[self.initial.taxa[1]],
             self.names[self.initial.taxa[2]], self.initial.initial });
        for (self.initial.additions.items) |add| out.add("ADD {s} edge {s} score {d} ties {d}",
             .{ self.names[add.taxon], symbols(add.mask, self.size), add.score, add.ties });
        out.add("STEPWISE score {d} evaluated {d}", .{ self.initial.score, self.initial.evaluated });
        for (self.mp.moves.items) |move| out.add("NNI edge {s} swap {d} score {d}", .{ symbols(move.mask,
             self.size), move.swap, integer(move.value) });
        out.add("SEARCH moves {d} evaluated {d} score {d}", .{ self.mp.moves.items.len, self.mp.evaluated,
             integer(self.mp.value) });
        self.scoreLine(&out, "MP", integer(self.mp.value));
        out.add("MP {s}", .{output.newick(&self.trees[4], self.names, self.outgroup, true, null)});
        var histogram = [_]i64{0} ** 16;
        var largest: usize = 0;
        var homoplasy: usize = 0;
        for (self.reconstruction.sites, self.minima) |changes, minimum| {
            histogram[u(changes)] += 1;
            largest = @max(largest, u(changes));
            homoplasy += @intFromBool(changes > minimum);
        }
        for (0..largest + 1) |k| out.add("CHANGES {d} columns {d}", .{ k, histogram[k] });
        out.add("HOMOPLASY columns {d} extra {d}", .{ homoplasy, integer(self.mp.value) - self.minimum });
        const root = Rooted.init(&self.trees[4], self.outgroup);
        var masks: std.ArrayList(u32) = .empty;
        var nodes = [_]usize{0} ** 65536;
        for (self.size..self.trees[4].next) |node| {
            const mask = if (node == root.root) root.ingroup else root.masks[node];
            d.append(u32, &masks, mask);
            nodes[mask] = node;
        }
        for (symbolOrder(masks.items)) |mask| out.add("ANCESTOR {s} {s}", .{ symbols(mask,
             self.size), self.reconstruction.ancestors[nodes[mask]].? });
        out.add("", .{});
        out.add("EXHAUSTIVE taxa {d} trees {d} best {d} optimal {d}", .{ self.exhaustive.taxa.len,
             self.exhaustive.records.len, self.exhaustive.best_score, self.exhaustive.optimal.len });
        var scores = [_]i64{0} ** 4501;
        for (self.exhaustive.records) |record| scores[u(record.score)] += 1;
        for (scores, 0..) |count, score| if (count > 0) out.add("SCORE {d} trees {d}", .{ score, count });
        for (self.exhaustive.optimal) |index| {
            const record = self.exhaustive.records[index];
            out.add("OPTIMAL {s} bme {s}", .{ record.newick, real(record.bme, 5) });
        }
        out.add("STRICT {s}", .{output.newick(&self.exhaustive.strict, self.names, self.outgroup, false, null)});
        out.add("HEURISTIC score {d} optimal {s}", .{ self.exhaustive.heuristic, if (self.exhaustive.heuristic == self.exhaustive.best_score) "yes" else "no" });
        return out;
    }
    fn likelihoodReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        out.add("LIKELIHOOD columns {d} patterns {d}", .{ self.length, self.patterns.text.len });
        for (0..3) |i| {
            const total = sum(self.site_logs[i]);
            out.add("TREE {s} loglik {s} per_site {s}", .{ methods[i], real(total, 4), real(total / f(self.length),
                 4) });
        }
        for (0..3) |a| for (a + 1..3) |b| {
            const deltas = d.alloc(f64, self.length);
            for (deltas, 0..) |*delta, c| delta.* = self.site_logs[a][c] - self.site_logs[b][c];
            const difference = sum(deltas);
            const average = difference / f(self.length);
            var squares: f64 = 0;
            for (deltas) |value| squares += square(value - average);
            const error_value = @sqrt(f(self.length) / f(self.length - 1) * squares);
            out.add("KH {s} {s} difference {s} se {s} z {s}", .{ methods[a], methods[b], real(difference,
                 4), real(error_value, 4), real(difference / error_value, 4) });
        };
        const order = d.alloc(usize, self.length);
        const rounded = d.alloc(f64, self.length);
        for (order, rounded, 0..) |*column, *value, c| {
            column.* = c;
            value.* = std.fmt.parseFloat(f64, real(self.site_logs[self.params.model][c], 4)) catch unreachable;
        }
        std.mem.sort(usize, order, @as([]const f64, rounded), lowLess);
        out.add("LOWEST {s} sites {d}", .{ methods[self.params.model], self.params.low_sites });
        const changes = parsimony.patternScores(&self.trees[self.params.model], self.patterns, self.outgroup);
        for (order[0..self.params.low_sites]) |c| {
            const pattern = self.patterns.columns[c];
            out.add("SITE {d} loglik {s} changes {d} pattern {s}", .{ c + 1, real(self.site_logs[self.params.model][c],
                 4), changes[pattern], self.patterns.text[pattern] });
        }
        return out;
    }
    fn clockReport(self: *const Study) d.Lines {
        var pairs: d.Lines = .{};
        var rejected: usize = 0;
        for (0..self.size) |a| {
            if (a == self.outgroup) continue;
            for (a + 1..self.size) |b| {
                if (b == self.outgroup) continue;
                var m1: i64 = 0;
                var m2: i64 = 0;
                for (self.sequences[a], self.sequences[b], self.sequences[self.outgroup]) |x,
                     y, o| if (d.baseIndex(x) != null and d.baseIndex(y) != null and d.baseIndex(o) != null and x != y) {
                    m1 += @intFromBool(y == o);
                    m2 += @intFromBool(x == o);
                };
                const difference = m1 - m2;
                const reject = 1000 * difference * difference > 3841 * (m1 + m2);
                rejected += @intFromBool(reject);
                pairs.add("RRT {s} {s} m1 {d} m2 {d} chi2 {s} {s}", .{ self.names[a], self.names[b],
                     m1, m2, if (m1 + m2 > 0) real(f(difference * difference) / f(m1 + m2),
                     4) else "-", if (reject) "reject" else "ok" });
            }
        }
        var out: d.Lines = .{};
        out.add("RELATIVE_RATE outgroup {s} pairs {d} rejected {d}", .{ self.names[self.outgroup],
             pairs.data.items.len, rejected });
        out.extend(pairs);
        const tree = &self.trees[self.params.model];
        const root = Rooted.init(tree, self.outgroup);
        const paths = building.paths(tree, root.root, false);
        var average: f64 = 0;
        for (0..self.size) |t| if (t != self.outgroup) {
            average += paths[t];
        };
        average /= f(self.size - 1);
        var deviation: f64 = 0;
        for (0..self.size) |t| if (t != self.outgroup) {
            deviation += square(paths[t] - average);
        };
        deviation = @sqrt(deviation / f(self.size - 2));
        out.add("ROOT_TO_TIP {s} mean {s} sd {s} cv {s}", .{ methods[self.params.model], real(average,
             5), real(deviation, 5), real(deviation / average, 4) });
        for (0..self.size) |t| if (t != self.outgroup) out.add("TIP {s} {s}", .{ self.names[t], real(paths[t], 5) });
        return out;
    }
    fn quartets(self: *const Study, splits: []const u32) []const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (0..self.size) |a| for (a + 1..self.size) |b| for (b + 1..self.size) |c| for (c + 1..self.size) |e| {
            const quartet = bit(a) | bit(b) | bit(c) | bit(e);
            var topology: u8 = 0;
            for ([_]usize{ b, c, e }, 1..) |other, i| {
                const side = bit(a) | bit(other);
                for (splits) |mask| {
                    const intersection = mask & quartet;
                    if (intersection == side or intersection == quartet ^ side) {
                        topology = @intCast(i);
                        break;
                    }
                }
                if (topology != 0) break;
            }
            d.append(u8, &out, topology);
        };
        return out.items;
    }
    fn comparisonReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        var splits: [6][]const u32 = undefined;
        var topologies: [6][]const u8 = undefined;
        var all: std.ArrayList(u32) = .empty;
        for (&self.trees, 0..) |*tree, i| {
            splits[i] = splitSet(tree, self.outgroup);
            topologies[i] = self.quartets(splits[i]);
            var supported: usize = 0;
            for (splits[i]) |mask| {
                addMask(&all, mask);
                supported += @intFromBool(2 * self.support[mask] > n(self.params.replicates));
            }
            var score_text: []const u8 = "-";
            var balanced: []const u8 = "-";
            var length_text: []const u8 = "-";
            var negative: []const u8 = "-";
            var residual: []const u8 = "-";
            var likelihood: []const u8 = "-";
            if (i != 5) {
                const score = if (i < 3) self.nj_scores[i] else if (i == 4) integer(self.mp.value) else parsimony.score(tree,
                     self.patterns, self.outgroup);
                score_text = d.fmt("{d}", .{score});
                balanced = real(self.bme(tree), 5);
            }
            if (i < 3) {
                var length: f64 = 0;
                for (parsimony.branches(tree, self.outgroup)) |branch| length += tree.length[branch.first][branch.second];
                var error_value: f64 = 0;
                for (0..self.size) |a| for (a + 1..self.size) |b| {
                    error_value += square(self.matrices[i][a][b] - self.patristics[i][a][b]);
                };
                length_text = real(length, 5);
                negative = d.fmt("{d}", .{tree.negative});
                residual = real(error_value, 6);
                likelihood = real(sum(self.site_logs[i]), 4);
            } else if (i == 4) length_text = real(self.mp.value / f(self.length), 5);
            out.add("TREE {s} splits {d} supported {d} parsimony {s} bme {s} length {s} negative {s} sse {s} loglik {s}",
                 .{ methods[i], splits[i].len, supported, score_text, balanced, length_text,
                 negative, residual, likelihood });
        }
        for (0..2) |kind| {
            var heading: d.Text = .{};
            heading.add("{s}", .{if (kind == 0) "RF" else "QUARTET"});
            for (methods) |method| heading.add(" {s}", .{method});
            out.add("{s}", .{heading.value()});
            for (0..6) |a| {
                var row: d.Text = .{};
                row.add("{s}", .{methods[a]});
                for (0..6) |b| {
                    var difference: usize = 0;
                    if (kind == 0) difference = rf(splits[a], splits[b]) else for (topologies[a],
                         topologies[b]) |left, right| {
                        difference += @intFromBool(left != right);
                    };
                    row.add(" {d}", .{difference});
                }
                out.add("{s}", .{row.value()});
            }
        }
        const lengths = d.alloc(?f64, 65536);
        @memset(lengths, null);
        const changes = d.alloc(?i64, 65536);
        @memset(changes, null);
        const main = &self.trees[self.params.model];
        const root = Rooted.init(main, self.outgroup);
        for (root.order[1..root.count]) |node| {
            const mask = if (node == self.outgroup) root.ingroup else root.masks[node];
            lengths[mask] = main.length[node][root.parent[node].?];
        }
        for (parsimony.branches(&self.trees[4], self.outgroup)) |branch| changes[branch.mask] = self.reconstruction.changes[@min(branch.first,
             branch.second)][@max(branch.first, branch.second)];
        for (symbolOrder(all.items)) |mask| {
            var marks: [6]u8 = undefined;
            for (0..6) |i| marks[i] = if (contains(splits[i], mask)) '+' else '-';
            out.add("CLADE {s} support {d} trees {s} length {s} changes {s}", .{ symbols(mask,
                 self.size), self.support[mask], &marks, if (lengths[mask]) |length| real(length,
                 5) else "-", if (changes[mask]) |change| d.fmt("{d}", .{change}) else "-" });
        }
        return out;
    }
    fn hypothesesReport(self: *const Study, io: std.Io) !d.Lines {
        var out: d.Lines = .{};
        var splits: [6][]const u32 = undefined;
        for (&self.trees, 0..) |*tree, i| splits[i] = splitSet(tree, self.outgroup);
        const ingroup = (bit(self.size) - 1) ^ bit(self.outgroup);
        var exhaustive_ingroup: u32 = 0;
        for (self.exhaustive.taxa) |taxon| if (taxon != self.outgroup) {
            exhaustive_ingroup |= bit(taxon);
        };
        for (try d.readLines(io, "input/clades.txt")) |line| {
            const row = d.words(line);
            const hypothesis = row[0];
            var unknown: ?[]const u8 = null;
            var mask: u32 = 0;
            for (row[1..]) |name| {
                if (d.indexOf(self.names, name)) |taxon| mask |= bit(taxon) else if (unknown == null) {
                    unknown = name;
                }
            }
            if (unknown) |name| {
                out.add("INVALID {s} unknown taxon {s}", .{ hypothesis, name });
                continue;
            }
            if (mask & bit(self.outgroup) != 0) {
                out.add("INVALID {s} contains outgroup", .{hypothesis});
                continue;
            }
            out.add("CLADE {s} taxa {d} support {d}", .{ hypothesis, @popCount(mask), self.support[mask] });
            for (0..6) |i| {
                var common = ingroup;
                for (splits[i]) |clade| if (clade & mask == mask and @popCount(clade) < @popCount(common)) {
                    common = clade;
                };
                var intruders: d.Text = .{};
                for (self.names, 0..) |name, t| if (common & ~mask & bit(t) != 0) {
                    intruders.add("{s}{s}", .{ if (intruders.value().len == 0) "" else ",", name });
                };
                out.add("TEST {s} {s} monophyletic {s} mrca {d} intruders {s}", .{ hypothesis,
                     methods[i], if (common == mask) "yes" else "no", @popCount(common), if (intruders.value().len == 0) "-" else intruders.value() });
            }
            const subset = mask & exhaustive_ingroup;
            if (@popCount(subset) < 2 or @popCount(subset) >= @popCount(exhaustive_ingroup)) {
                out.add("SUBSET {s} untestable", .{hypothesis});
                continue;
            }
            var scores = [_]i64{std.math.maxInt(i64)} ** 2;
            var balanced = [_]f64{std.math.inf(f64)} ** 2;
            for (self.exhaustive.records) |record| {
                const side: usize = if (contains(record.splits, subset)) 0 else 1;
                scores[side] = @min(scores[side], record.score);
                balanced[side] = @min(balanced[side], record.bme);
            }
            out.add("SUBSET {s} taxa {d} with {d} without {d} bme_with {s} bme_without {s}",
                 .{ hypothesis, @popCount(subset), scores[0], scores[1], real(balanced[0],
                 5), real(balanced[1], 5) });
        }
        return out;
    }
    fn run(self: *Study, io: std.Io) !void {
        self.me_start = self.bme(&self.trees[self.params.model]);
        self.me = self.hillClimb(&self.trees[self.params.model], true, self.me_start);
        self.trees[3] = self.me.tree;
        var order: std.ArrayList(usize) = .empty;
        d.append(usize, &order, self.outgroup);
        for (self.taxa) |taxon| if (taxon != self.outgroup) d.append(usize, &order, taxon);
        self.initial = self.stepwise(order.items);
        self.mp = self.hillClimb(&self.initial.tree, false, f(self.initial.score));
        self.trees[4] = self.mp.tree;
        self.reconstruction = parsimony.reconstruct(&self.trees[4], self.patterns, self.outgroup);
        for (0..self.trees[4].next) |a| for (a + 1..self.trees[4].next) |b| {
            if (self.trees[4].adjacent[a][b]) self.trees[4].connect(a, b, f(self.reconstruction.changes[a][b]) / f(self.length));
        };
        self.bounds();
        var exhaustive: std.ArrayList(usize) = .empty;
        d.append(usize, &exhaustive, self.outgroup);
        for (self.names, 0..) |name, t| if (t != self.outgroup and d.indexOf(self.params.exhaustive,
             name) != null) d.append(usize, &exhaustive, t);
        self.exhaustive = self.exhaustiveSearch(exhaustive.items);
        self.bootstrap();
        var newicks: d.Lines = .{};
        var diagrams: d.Lines = .{};
        for (&self.trees, 0..) |*tree, i| {
            newicks.add("{s} {s}", .{ methods[i], output.newick(tree, self.names, self.outgroup,
                 i < 3 or i == 4, if (i == 5) self.support else null) });
            if (i > 0) diagrams.add("", .{});
            diagrams.add("TREE {s}", .{methods[i]});
            diagrams.extend(output.cladogram(tree, self.names, self.outgroup, self.support));
        }
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try output.save(io, "summary.txt", self.summary());
        try output.save(io, "distances.txt", self.distancesReport());
        try output.save(io, "trees.nwk", newicks);
        try output.save(io, "cladograms.txt", diagrams);
        try output.save(io, "parsimony.txt", self.parsimonyReport());
        try output.save(io, "likelihood.txt", self.likelihoodReport());
        try output.save(io, "bootstrap.txt", self.bootstrap_lines);
        try output.save(io, "clock.txt", self.clockReport());
        try output.save(io, "comparison.txt", self.comparisonReport());
        try output.save(io, "hypotheses.txt", try self.hypothesesReport(io));
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    var study = try Study.init(init.io);
    try study.run(init.io);
}
