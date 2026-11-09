const std = @import("std");
const b = @import("baskets.zig");
const apriori = @import("apriori.zig");
const fp = @import("fpgrowth.zig");
const r = @import("rules.zig");
const out = @import("report.zig");
const Fraction = r.Fraction;
const segments = [_][]const u8{ "NEW", "LOYAL", "AT_RISK", "REGULAR" };
const Params = struct { support: i64, confidence: Fraction, lift: Fraction, max_size: usize, category_support: i64, sequence_support: i64, split: i64, train_support: i64, test_support: i64, top: usize, matrix: usize, group_lift: Fraction, negative_lift: Fraction, expected: i64, threshold: Fraction };
const Data = struct { errors: b.Strings, products: []const b.Product, categories: b.Strings, names: b.Strings, baskets: []const b.Transaction, transactions: usize, item_rows: usize, transaction_rows: usize, accepted: usize, rejected: usize, duplicates: usize };
const Level = struct { number: usize, candidates: usize, excluded: usize, pruned: usize, counted: usize, frequent: []const b.Frequent };
const AprioriResult = struct { supports: b.Counts, singles: b.Counts, levels: []const Level, itemsets: []const b.Frequent };
const RuleSet = struct { generated: usize, rules: []const r.Rule, productive: usize };
const Classification = struct { closed: []const b.Frequent, maximal: []const b.Frequent, generators: []const b.Frequent };
const Customer = struct { id: []const u8, baskets: usize = 0, days: u128 = 0, purchases: []u128, first: i64 = 113, last: i64 = 0, units: i64 = 0, revenue: i64 = 0, favorite: usize = 0, mask: u128 = 0 };
const Sequence = struct { first: usize, second: usize, count: i64, base: i64, confidence: Fraction, lift: Fraction, gap: Fraction };
const Repeat = struct { item: usize, customers: usize, count: usize, low: i64, high: i64, mean: Fraction, median: Fraction };
const Sequences = struct { buyers: []const i64, pairs: usize, count: usize, lines: b.Strings };
const Recommendation = struct { values: [5]usize = @splat(0), count: usize = 0, fn has(a: Recommendation, code: usize) bool { return std.mem.findScalar(usize, a.values[0..a.count], code) != null; } };
const Tally = struct {
    cases: i64 = 0, covered: i64 = 0, hit1: i64 = 0, hit: i64 = 0, baseline: i64 = 0,
    fn add(a: *Tally, c: Tally) void { a.cases += c.cases; a.covered += c.covered; a.hit1 += c.hit1; a.hit += c.hit; a.baseline += c.baseline; }
    fn describe(a: Tally) []const u8 { return b.fmt("cases {d} covered {d} hit1 {d} hit {d} rate {s} baseline {d} rate {s}", .{ a.cases, a.covered, a.hit1, a.hit, out.fraction(Fraction.init(a.hit, a.cases)), a.baseline, out.fraction(Fraction.init(a.baseline, a.cases)) }); }
};
const Evaluation = struct { lines: b.Strings, heldout: []const i64, hits: []const i64 };
fn appendLines(lines: *std.ArrayList([]const u8), more: b.Strings) void { for (more) |line| b.append([]const u8, lines, line); }
fn ratio(text: []const u8) Fraction { const parts = b.split(text, '/'); return Fraction.init(b.integer(parts[0]), b.integer(parts[1])); }
fn parameters(text: []const u8) Params {
    const rows = b.lines(text); const values = b.alloc([]const u8, rows.len); for (rows, values) |line, *value| value.* = b.split(line, ' ')[1];
    return .{ .support = b.integer(values[0]), .confidence = ratio(values[1]), .lift = ratio(values[2]), .max_size = @intCast(b.integer(values[3])), .category_support = b.integer(values[4]), .sequence_support = b.integer(values[5]), .split = b.integer(values[6]), .train_support = b.integer(values[7]), .test_support = b.integer(values[8]), .top = @intCast(b.integer(values[9])), .matrix = @intCast(b.integer(values[10])), .group_lift = ratio(values[11]), .negative_lift = ratio(values[12]), .expected = b.integer(values[13]), .threshold = ratio(values[14]) };
}
fn nameIndex(names: b.Strings, name: []const u8) ?usize { for (names, 0..) |candidate, i| { if (b.eq(candidate, name)) return i; } return null; }
fn textLess(_: void, a: []const u8, c: []const u8) bool { return b.textLess(a, c); }
fn intLess(_: void, a: i64, c: i64) bool { return a < c; }
fn loadData(items_text: []const u8, transactions_text: []const u8) Data {
    const RawProduct = struct { name: []const u8, category: []const u8, price: i64, fn less(_: void, a: @This(), c: @This()) bool { return b.textLess(a.name, c.name); } };
    var errors: std.ArrayList([]const u8) = .empty; var adopted: std.ArrayList(RawProduct) = .empty; const item_rows = b.rows(items_text);
    for (item_rows, 2..) |f, line| {
        var duplicate = false; for (adopted.items) |product| { if (b.eq(product.name, f[0])) { duplicate = true; break; } }
        const price = b.integer(f[2]);
        if (duplicate) b.append([]const u8, &errors, b.fmt("items.csv line {d}: duplicate item {s}", .{ line, f[0] })) else if (price == 0) b.append([]const u8, &errors, b.fmt("items.csv line {d}: bad price 0", .{line})) else b.append(RawProduct, &adopted, .{ .name = f[0], .category = f[1], .price = price });
    }
    std.mem.sort(RawProduct, adopted.items, {}, RawProduct.less);
    var categories: std.ArrayList([]const u8) = .empty; for (adopted.items) |product| { if (nameIndex(categories.items, product.category) == null) b.append([]const u8, &categories, product.category); }
    std.mem.sort([]const u8, categories.items, {}, textLess);
    var names: std.ArrayList([]const u8) = .empty; appendLines(&names, categories.items); const products = b.alloc(b.Product, adopted.items.len);
    for (adopted.items, products, 0..) |raw, *product, i| { product.* = .{ .name = raw.name, .category = nameIndex(categories.items, raw.category).?, .price = raw.price, .code = categories.items.len + i }; b.append([]const u8, &names, raw.name); }
    var transactions: std.ArrayList(b.Transaction) = .empty; const transaction_rows = b.rows(transactions_text); var accepted: usize = 0; var rejected: usize = 0; var duplicates: usize = 0;
    for (transaction_rows, 2..) |f, line| {
        const day = b.integer(f[2]); var existing: ?usize = null; for (transactions.items, 0..) |transaction, i| { if (b.eq(transaction.tid, f[0])) { existing = i; break; } }
        var message: ?[]const u8 = null;
        if (existing != null and existing.? != transactions.items.len - 1) message = b.fmt("tid {s} not contiguous", .{f[0]}) else {
            if (existing == null) { const units = b.alloc(i64, products.len); @memset(units, 0); b.append(b.Transaction, &transactions, .{ .tid = f[0], .customer = f[1], .day = day, .units = units }); }
            const current = &transactions.items[transactions.items.len - 1]; const product_index = nameIndex(names.items[categories.items.len..], f[3]);
            if (!b.eq(current.customer, f[1])) message = b.fmt("tid {s} customer {s} differs from {s}", .{ f[0], f[1], current.customer }) else if (day != current.day) message = b.fmt("tid {s} day {d} differs from {d}", .{ f[0], day, current.day }) else if (product_index == null) message = b.fmt("unknown item {s}", .{f[3]}) else { const i = product_index.?; if (current.units[i] > 0) duplicates += 1; current.units[i] += 1; current.mask |= b.bit(products[i].code); accepted += 1; }
        }
        if (message) |problem| { rejected += 1; b.append([]const u8, &errors, b.fmt("transactions.csv line {d}: {s}", .{ line, problem })); }
    }
    var baskets: std.ArrayList(b.Transaction) = .empty; for (transactions.items) |transaction| { if (transaction.mask != 0) b.append(b.Transaction, &baskets, transaction); }
    return .{ .errors = errors.items, .products = products, .categories = categories.items, .names = names.items, .baskets = baskets.items, .transactions = transactions.items.len, .item_rows = item_rows.len, .transaction_rows = transaction_rows.len, .accepted = accepted, .rejected = rejected, .duplicates = duplicates };
}
fn frequentLevel(counts: []const b.Frequent, minimum: i64, supports: *b.Counts, all: *std.ArrayList(b.Frequent)) []const b.Frequent { var chosen: std.ArrayList(b.Frequent) = .empty; for (counts) |entry| { if (entry.count >= minimum) { b.append(b.Frequent, &chosen, entry); b.put(supports, entry.mask, entry.count); b.append(b.Frequent, all, entry); } } return chosen.items; }
fn runApriori(baskets: []const u128, universe: []const usize, minimum: i64, max_size: usize, taxonomy: []const u128) AprioriResult {
    var supports: b.Counts = .empty; var singles: b.Counts = .empty; var levels: std.ArrayList(Level) = .empty; var all: std.ArrayList(b.Frequent) = .empty;
    const masks = b.alloc(u128, universe.len); for (universe, masks) |code, *mask| mask.* = b.bit(code);
    const counts = apriori.count(baskets, masks); for (counts) |entry| b.put(&singles, entry.mask, entry.count);
    var previous = frequentLevel(counts, minimum, &supports, &all);
    b.append(Level, &levels, .{ .number = 1, .candidates = masks.len, .excluded = 0, .pruned = 0, .counted = masks.len, .frequent = previous });
    var size: usize = 2;
    while (size <= max_size and previous.len > 0) : (size += 1) {
        const generation = apriori.generate(previous, size, taxonomy); previous = frequentLevel(apriori.count(baskets, generation.masks), minimum, &supports, &all);
        b.append(Level, &levels, .{ .number = size, .candidates = generation.joined, .excluded = generation.excluded, .pruned = generation.pruned, .counted = generation.masks.len, .frequent = previous });
    }
    std.mem.sort(b.Frequent, all.items, {}, b.sizeLess);
    return .{ .supports = supports, .singles = singles, .levels = levels.items, .itemsets = all.items };
}
fn makeRules(analysis: AprioriResult, total: i64, p: Params, required: u128) RuleSet {
    var generated: usize = 0; var kept: std.ArrayList(r.Rule) = .empty; var productive: usize = 0;
    for (analysis.itemsets) |entry| {
        const z = entry.mask; if (b.size(z) < 2 or (required != 0 and z & required == 0)) continue;
        var x = (z - 1) & z;
        while (x != 0) : (x = (x - 1) & z) {
            const y = z ^ x; generated += 1; const first = analysis.supports.get(x).?; const second = analysis.supports.get(y).?;
            const confidence = Fraction.init(entry.count, first); const lift = r.lift(total, entry.count, first, second);
            if (!r.meets(confidence, lift, p.confidence, p.lift)) continue;
            var reference = Fraction.init(second, total); var w = (x - 1) & x;
            while (w != 0) : (w = (w - 1) & x) { const value = Fraction.init(analysis.supports.get(w | y).?, analysis.supports.get(w).?); if (value.compare(reference) == .gt) reference = value; }
            const improvement = confidence.sub(reference); if (improvement.n > 0) productive += 1;
            b.append(r.Rule, &kept, r.make(x, y, entry.count, total, first, second, improvement));
        }
    }
    std.mem.sort(r.Rule, kept.items, {}, r.less); return .{ .generated = generated, .rules = kept.items, .productive = productive };
}
fn classify(analysis: AprioriResult, total: i64) Classification {
    var closed: std.ArrayList(b.Frequent) = .empty; var maximal: std.ArrayList(b.Frequent) = .empty; var generators: std.ArrayList(b.Frequent) = .empty;
    for (analysis.itemsets) |entry| {
        var is_closed = true; var is_maximal = true; var is_generator = true;
        for (analysis.itemsets) |other| { if (other.mask != entry.mask and b.contains(other.mask, entry.mask)) { is_maximal = false; if (other.count == entry.count) is_closed = false; } }
        var it = b.iterator(entry.mask); while (it.next()) |code| { const subset = entry.mask ^ b.bit(code); const count = if (subset == 0) total else analysis.supports.get(subset).?; if (count <= entry.count) is_generator = false; }
        if (is_closed) b.append(b.Frequent, &closed, entry); if (is_maximal) b.append(b.Frequent, &maximal, entry); if (is_generator) b.append(b.Frequent, &generators, entry);
    }
    return .{ .closed = closed.items, .maximal = maximal.items, .generators = generators.items };
}
fn histories(data: Data) []const Customer {
    var ids: std.ArrayList([]const u8) = .empty; for (data.baskets) |basket| { if (nameIndex(ids.items, basket.customer) == null) b.append([]const u8, &ids, basket.customer); } std.mem.sort([]const u8, ids.items, {}, textLess);
    const result = b.alloc(Customer, ids.items.len);
    for (ids.items, result) |id, *customer| {
        const purchases = b.alloc(u128, data.products.len); @memset(purchases, 0); customer.* = .{ .id = id, .purchases = purchases };
        const category_units = b.alloc(i64, data.categories.len); @memset(category_units, 0);
        for (data.baskets) |basket| {
            if (!b.eq(id, basket.customer)) continue;
            customer.baskets += 1; customer.days |= b.bit(@intCast(basket.day - 1)); customer.first = @min(customer.first, basket.day); customer.last = @max(customer.last, basket.day); customer.mask |= basket.mask;
            for (basket.units, data.products, purchases) |quantity, product, *days| { customer.units += quantity; customer.revenue += quantity * product.price; category_units[product.category] += quantity; if (quantity > 0) days.* |= b.bit(@intCast(basket.day - 1)); }
        }
        for (category_units, 0..) |quantity, i| { if (quantity > category_units[customer.favorite]) customer.favorite = i; }
    }
    return result;
}
fn median(values: []const i64) Fraction { const ordered = b.clone(i64, values); std.mem.sort(i64, ordered, {}, intLess); const middle = ordered.len / 2; return if (ordered.len % 2 == 1) Fraction.init(ordered[middle], 1) else Fraction.init(ordered[middle - 1] + ordered[middle], 2); }
fn sequenceLess(_: void, a: Sequence, c: Sequence) bool { if (a.count != c.count) return a.count > c.count; const order = a.confidence.compare(c.confidence); if (order != .eq) return order == .gt; return if (a.first == c.first) a.second < c.second else a.first < c.first; }
fn repeatLess(_: void, a: Repeat, c: Repeat) bool { const order = a.mean.compare(c.mean); return if (order == .eq) a.item < c.item else order == .lt; }
fn sequenceAnalysis(data: Data, history: []const Customer, p: Params) Sequences {
    const buyers = b.alloc(i64, data.products.len); @memset(buyers, 0); for (history) |customer| for (customer.purchases, buyers) |days, *count| { if (days != 0) count.* += 1; };
    var pairs: usize = 0; var sequences: std.ArrayList(Sequence) = .empty; var repeats: std.ArrayList(Repeat) = .empty;
    for (data.products, 0..) |_, first| for (data.products, 0..) |_, second| {
        var gaps: std.ArrayList(i64) = .empty;
        for (history) |customer| {
            const earlier = customer.purchases[first]; const later = customer.purchases[second]; if (earlier == 0 or later == 0 or @ctz(earlier) >= 127 - @clz(later)) continue;
            var gap: i64 = 113; var x = b.iterator(earlier);
            while (x.next()) |day| { var y = b.iterator(later); while (y.next()) |after| { if (after > day) { gap = @min(gap, b.int(after - day)); break; } } }
            b.append(i64, &gaps, gap);
        }
        if (gaps.items.len == 0) continue; pairs += 1;
        if (b.int(gaps.items.len) >= p.sequence_support) { const count = b.int(gaps.items.len); b.append(Sequence, &sequences, .{ .first = first, .second = second, .count = count, .base = buyers[first], .confidence = Fraction.init(count, buyers[first]), .lift = r.lift(b.int(history.len), count, buyers[first], buyers[second]), .gap = median(gaps.items) }); }
    };
    for (data.products, 0..) |_, i| {
        var intervals: std.ArrayList(i64) = .empty; var customers: usize = 0; var total: i64 = 0; var low: i64 = 113; var high: i64 = 0;
        for (history) |customer| { if (b.size(customer.purchases[i]) < 2) continue; customers += 1; var it = b.iterator(customer.purchases[i]); var previous = it.next().?; while (it.next()) |day| { const gap = b.int(day - previous); b.append(i64, &intervals, gap); total += gap; low = @min(low, gap); high = @max(high, gap); previous = day; } }
        if (intervals.items.len > 0) b.append(Repeat, &repeats, .{ .item = i, .customers = customers, .count = intervals.items.len, .low = low, .high = high, .mean = Fraction.init(total, b.int(intervals.items.len)), .median = median(intervals.items) });
    }
    std.mem.sort(Sequence, sequences.items, {}, sequenceLess); std.mem.sort(Repeat, repeats.items, {}, repeatLess); var lines: std.ArrayList([]const u8) = .empty;
    for (sequences.items, 1..) |sequence, rank| b.append([]const u8, &lines, b.fmt("SEQ {d} {s} -> {s} customers {d} base {d} confidence {s} lift {s} gap {s}", .{ rank, data.products[sequence.first].name, data.products[sequence.second].name, sequence.count, sequence.base, out.fraction(sequence.confidence), out.fraction(sequence.lift), out.fraction(sequence.gap) }));
    for (repeats.items) |repeat| b.append([]const u8, &lines, b.fmt("REPEAT {s} customers {d} intervals {d} min {d} max {d} mean {s} median {s}", .{ data.products[repeat.item].name, repeat.customers, repeat.count, repeat.low, repeat.high, out.fraction(repeat.mean), out.fraction(repeat.median) }));
    return .{ .buyers = buyers, .pairs = pairs, .count = sequences.items.len, .lines = lines.items };
}
fn select(result: *Recommendation, held: u128, code: usize, limit: usize) void { if (result.count < limit and !b.contains(held, b.bit(code)) and !result.has(code)) { result.values[result.count] = code; result.count += 1; } }
fn ruleRecommendation(held: u128, rules: []const r.Rule, limit: usize) Recommendation { var result: Recommendation = .{}; for (rules) |rule| { if (b.size(rule.y) == 1 and b.contains(held, rule.x)) select(&result, held, @intCast(@ctz(rule.y)), limit); if (result.count == limit) break; } return result; }
fn popularityRecommendation(held: u128, popularity: []const usize, limit: usize) Recommendation { var result: Recommendation = .{}; for (popularity) |code| { select(&result, held, code, limit); if (result.count == limit) break; } return result; }
fn cachedSupport(cache: *b.Counts, baskets: []const u128, mask: u128) i64 { if (cache.get(mask)) |value| return value; const value = apriori.support(baskets, mask); b.put(cache, mask, value); return value; }
const PopularityContext = struct { counts: b.Counts };
fn popularityLess(context: PopularityContext, a: usize, c: usize) bool { const first = context.counts.get(b.bit(a)).?; const second = context.counts.get(b.bit(c)).?; return if (first == second) a < c else first > second; }
fn validation(data: Data, p: Params, universe: []const usize) Evaluation {
    var train: std.ArrayList(u128) = .empty; var testing_baskets: std.ArrayList(u128) = .empty;
    for (data.baskets) |basket| { if (basket.day <= p.split) b.append(u128, &train, basket.mask) else b.append(u128, &testing_baskets, basket.mask); }
    const training = runApriori(train.items, universe, p.train_support, p.max_size, &.{}); const testing = runApriori(testing_baskets.items, universe, p.test_support, p.max_size, &.{});
    const rules = makeRules(training, b.int(train.items.len), p, 0); const test_rules = makeRules(testing, b.int(testing_baskets.items.len), p, 0);
    var cache: b.Counts = .empty; var lines: std.ArrayList([]const u8) = .empty; var verdicts: [3]usize = @splat(0);
    const RuleKey = struct { x: u128, y: u128 }; var known: std.AutoHashMapUnmanaged(RuleKey, void) = .empty;
    for (rules.rules, 1..) |rule, rank| {
        const first = cachedSupport(&cache, testing_baskets.items, rule.x); const second = cachedSupport(&cache, testing_baskets.items, rule.y); const together = cachedSupport(&cache, testing_baskets.items, rule.x | rule.y);
        var confidence: []const u8 = "-"; var lift: []const u8 = "-"; var verdict: usize = 2;
        if (first > 0 and second > 0) { const conf = Fraction.init(together, first); const value = r.lift(b.int(testing_baskets.items.len), together, first, second); confidence = out.fraction(conf); lift = out.fraction(value); verdict = if (r.meets(conf, value, p.confidence, p.lift)) 0 else 1; }
        verdicts[verdict] += 1; const names = [_][]const u8{ "HOLD", "FAIL", "UNSEEN" };
        b.append([]const u8, &lines, b.fmt("RULE {d} {s} train {d} confidence {s} lift {s} test {d} of {d} confidence {s} lift {s} {s}", .{ rank, out.arrow(rule, data.names), rule.count, out.fraction(rule.confidence), out.fraction(rule.lift), together, first, confidence, lift, names[verdict] }));
        known.put(b.allocator, .{ .x = rule.x, .y = rule.y }, {}) catch @panic("allocation failed");
    }
    var emerging: usize = 0;
    for (test_rules.rules, 1..) |rule, rank| { if (known.contains(.{ .x = rule.x, .y = rule.y })) continue; emerging += 1; b.append([]const u8, &lines, b.fmt("EMERGING {d} {s} test {d} confidence {s} lift {s}", .{ rank, out.arrow(rule, data.names), rule.count, out.fraction(rule.confidence), out.fraction(rule.lift) })); }
    b.append([]const u8, &lines, b.fmt("VALIDATION train {d} test {d} itemsets {d} rules {d} hold {d} fail {d} unseen {d} emerging {d}", .{ train.items.len, testing_baskets.items.len, training.itemsets.len, rules.rules.len, verdicts[0], verdicts[1], verdicts[2], emerging }));
    const popularity = b.clone(usize, universe); std.mem.sort(usize, popularity, PopularityContext{ .counts = training.singles }, popularityLess);
    const RecCache = std.AutoHashMapUnmanaged(u128, Recommendation); var suggestions: RecCache = .empty; var baselines: RecCache = .empty;
    var tallies: [61]Tally = @splat(.{}); const heldout = b.alloc(i64, data.products.len); const hits = b.alloc(i64, data.products.len); @memset(heldout, 0); @memset(hits, 0);
    for (testing_baskets.items) |basket| {
        const size = b.size(basket); if (size < 2) continue; var it = b.iterator(basket);
        while (it.next()) |held_out| {
            const held = basket ^ b.bit(held_out);
            const suggestion = suggestions.get(held) orelse blk: { const value = ruleRecommendation(held, rules.rules, p.top); suggestions.put(b.allocator, held, value) catch @panic("allocation failed"); break :blk value; };
            const baseline = baselines.get(held) orelse blk: { const value = popularityRecommendation(held, popularity, p.top); baselines.put(b.allocator, held, value) catch @panic("allocation failed"); break :blk value; };
            const hit = suggestion.has(held_out);
            tallies[size].add(.{ .cases = 1, .covered = if (suggestion.count > 0) 1 else 0, .hit1 = if (suggestion.count > 0 and suggestion.values[0] == held_out) 1 else 0, .hit = if (hit) 1 else 0, .baseline = if (baseline.has(held_out)) 1 else 0 });
            const index = held_out - data.categories.len; heldout[index] += 1; if (hit) hits[index] += 1;
        }
    }
    var total: Tally = .{}; for (tallies, 0..) |tally, size| { if (tally.cases == 0) continue; total.add(tally); b.append([]const u8, &lines, b.fmt("RECOMMEND size {d} {s}", .{ size, tally.describe() })); }
    b.append([]const u8, &lines, b.fmt("RECOMMEND total {s}", .{total.describe()}));
    return .{ .lines = lines.items, .heldout = heldout, .hits = hits };
}
fn summaryLines(data: Data, history: []const Customer, analysis: AprioriResult, classified: Classification, growth: fp.Result, main_rules: RuleSet, category: AprioriResult, category_rules: RuleSet, sequences: Sequences) b.Strings {
    var lines: std.ArrayList([]const u8) = .empty; for (data.errors) |problem| b.append([]const u8, &lines, b.fmt("ERROR {s}", .{problem}));
    b.append([]const u8, &lines, b.fmt("ITEMS rows {d} adopted {d} categories {d}", .{ data.item_rows, data.products.len, data.categories.len }));
    b.append([]const u8, &lines, b.fmt("TRANSACTIONS lines {d} adopted {d} rejected {d} duplicates {d} transactions {d} empty {d}", .{ data.transaction_rows, data.accepted, data.rejected, data.duplicates, data.transactions, data.transactions - data.baskets.len }));
    var sizes: [61]usize = @splat(0); var total_sizes: i64 = 0; var largest: usize = 0; var first_day: i64 = 113; var last_day: i64 = 0;
    for (data.baskets) |basket| { const size = b.size(basket.mask); sizes[size] += 1; total_sizes += b.int(size); largest = @max(largest, size); first_day = @min(first_day, basket.day); last_day = @max(last_day, basket.day); }
    const total = b.int(data.baskets.len);
    b.append([]const u8, &lines, b.fmt("BASKETS count {d} customers {d} first_day {d} last_day {d} average_size {s} largest {d}", .{ data.baskets.len, history.len, first_day, last_day, out.fraction(Fraction.init(total_sizes, total)), largest }));
    for (1..largest + 1) |size| b.append([]const u8, &lines, b.fmt("SIZE {d} baskets {d} share {s}", .{ size, sizes[size], out.percent(b.int(sizes[size]), total) }));
    b.append([]const u8, &lines, b.fmt("FREQUENT itemsets {d} closed {d} maximal {d} generators {d} levels {d}", .{ analysis.itemsets.len, classified.closed.len, classified.maximal.len, classified.generators.len, analysis.levels.len }));
    var match = analysis.supports.count() == growth.counts.count(); for (analysis.itemsets) |entry| { if ((growth.counts.get(entry.mask) orelse -1) != entry.count) match = false; }
    b.append([]const u8, &lines, b.fmt("FPGROWTH header {d} nodes {d} conditional_trees {d} conditional_nodes {d} itemsets {d} {s}", .{ growth.header, growth.nodes, growth.conditional_trees, growth.conditional_nodes, growth.itemsets.len, if (match) "MATCH" else "MISMATCH" }));
    if (!match) {
        for (analysis.itemsets) |entry| { if ((growth.counts.get(entry.mask) orelse -1) != entry.count) b.append([]const u8, &lines, b.fmt("ONLY_APRIORI {s} {d}", .{ out.itemset(entry.mask, data.names), entry.count })); }
        for (growth.itemsets) |entry| { if ((analysis.supports.get(entry.mask) orelse -1) != entry.count) b.append([]const u8, &lines, b.fmt("ONLY_FPGROWTH {s} {d}", .{ out.itemset(entry.mask, data.names), entry.count })); }
    }
    b.append([]const u8, &lines, b.fmt("RULES generated {d} passed {d} productive {d}", .{ main_rules.generated, main_rules.rules.len, main_rules.productive }));
    for (category.levels) |level| b.append([]const u8, &lines, b.fmt("CATEGORY_LEVEL {d} candidates {d} taxonomy {d} pruned {d} counted {d} frequent {d}", .{ level.number, level.candidates, level.excluded, level.pruned, level.counted, level.frequent.len }));
    b.append([]const u8, &lines, b.fmt("CATEGORY_RULES itemsets {d} generated {d} passed {d} productive {d}", .{ category.itemsets.len, category_rules.generated, category_rules.rules.len, category_rules.productive }));
    var multi_day: usize = 0; for (history) |customer| { if (b.size(customer.days) >= 2) multi_day += 1; }
    b.append([]const u8, &lines, b.fmt("SEQUENCES customers {d} multi_day {d} pairs {d} frequent {d}", .{ history.len, multi_day, sequences.pairs, sequences.count })); return lines.items;
}
fn itemsetLines(analysis: AprioriResult, names: b.Strings) b.Strings { var lines: std.ArrayList([]const u8) = .empty; for (analysis.levels) |level| { b.append([]const u8, &lines, b.fmt("LEVEL {d} candidates {d} pruned {d} counted {d} frequent {d}", .{ level.number, level.candidates, level.pruned, level.counted, level.frequent.len })); for (level.frequent) |entry| b.append([]const u8, &lines, b.fmt("{s} {d}", .{ out.itemset(entry.mask, names), entry.count })); } return lines.items; }
fn closedLines(classified: Classification, names: b.Strings) b.Strings { var lines: std.ArrayList([]const u8) = .empty; const labels = [_][]const u8{ "CLOSED", "MAXIMAL", "GENERATOR" }; const sets = [_][]const b.Frequent{ classified.closed, classified.maximal, classified.generators }; for (labels, sets) |label, entries| for (entries) |entry| b.append([]const u8, &lines, b.fmt("{s} {s} {d}", .{ label, out.itemset(entry.mask, names), entry.count })); return lines.items; }
const RevenueContext = struct { revenue: []const i64 };
fn revenueLess(context: RevenueContext, a: usize, c: usize) bool { return if (context.revenue[a] == context.revenue[c]) a < c else context.revenue[a] > context.revenue[c]; }
fn indices(count: usize) []usize { const result = b.alloc(usize, count); for (result, 0..) |*value, i| value.* = i; return result; }
const Group = struct { members: u128, count: usize, edges: usize, core: usize, revenue: i64 };
fn groupLess(_: void, a: Group, c: Group) bool { return if (a.count == c.count) @ctz(a.members) < @ctz(c.members) else a.count > c.count; }
const Substitute = struct { first: usize, second: usize, count: i64, expected: Fraction, lift: Fraction };
fn substituteLess(_: void, a: Substitute, c: Substitute) bool { const lift = a.lift.compare(c.lift); if (lift != .eq) return lift == .lt; const expected = a.expected.compare(c.expected); if (expected != .eq) return expected == .gt; return if (a.first == c.first) a.second < c.second else a.first < c.first; }
fn matrixLines(lines: *std.ArrayList([]const u8), label: []const u8, codes: []const usize, baskets: []const u128, names: b.Strings) void {
    const counts = b.alloc(i64, codes.len); var header: std.ArrayList([]const u8) = .empty; b.append([]const u8, &header, "    ");
    for (codes, counts, 1..) |code, *count, i| { count.* = apriori.support(baskets, b.bit(code)); b.append([]const u8, lines, b.fmt("{s} {d} {s} baskets {d}", .{ label, i, names[code], count.* })); b.append([]const u8, &header, b.fmt("{d: >7}", .{i})); }
    b.append([]const u8, lines, b.join(header.items, ""));
    for (codes, 0..) |first, i| { var row: std.ArrayList([]const u8) = .empty; b.append([]const u8, &row, b.fmt("{d: >4}", .{i + 1})); for (codes, 0..) |second, j| { if (i == j) b.append([]const u8, &row, "      -") else { const value = @divTrunc(100 * b.int(baskets.len) * apriori.support(baskets, b.bit(first) | b.bit(second)), counts[i] * counts[j]); b.append([]const u8, &row, b.fmt("{d: >7}", .{value})); } } b.append([]const u8, lines, b.join(row.items, "")); }
}
const ItemReport = struct { lines: b.Strings, revenue: i64 };
fn itemsLines(data: Data, p: Params, analysis: AprioriResult, main_rules: RuleSet, sequences: Sequences, evaluation: Evaluation, masks: []const u128, extended: []const u128, customer_count: usize) ItemReport {
    const total = b.int(data.baskets.len); const units = b.alloc(i64, data.products.len); const revenue = b.alloc(i64, data.products.len); @memset(units, 0);
    for (data.baskets) |basket| for (basket.units, units) |quantity, *quantity_total| quantity_total.* += quantity;
    var total_revenue: i64 = 0; var total_units: i64 = 0;
    for (data.products, units, revenue) |product, quantity, *amount| { amount.* = product.price * quantity; total_revenue += amount.*; total_units += quantity; }
    const order = indices(data.products.len); std.mem.sort(usize, order, RevenueContext{ .revenue = revenue }, revenueLess);
    var lines: std.ArrayList([]const u8) = .empty; const adjacency = b.alloc(u128, data.products.len); @memset(adjacency, 0);
    for (order, 1..) |i, rank| {
        const product = data.products[i]; const mask = b.bit(product.code); var count_sets: usize = 0;
        const Partner = struct { code: usize, count: i64, lift: Fraction }; var partner: ?Partner = null;
        for (analysis.itemsets) |entry| {
            if (!b.contains(entry.mask, mask)) continue; count_sets += 1; if (b.size(entry.mask) != 2) continue;
            const other: usize = @intCast(@ctz(entry.mask ^ mask)); const lift = r.lift(total, entry.count, analysis.singles.get(mask).?, analysis.singles.get(b.bit(other)).?);
            if (partner == null or lift.compare(partner.?.lift) == .gt or (lift.compare(partner.?.lift) == .eq and (entry.count > partner.?.count or (entry.count == partner.?.count and other < partner.?.code)))) partner = .{ .code = other, .count = entry.count, .lift = lift };
            if (lift.compare(p.group_lift) != .lt) adjacency[i] |= b.bit(other);
        }
        const partner_text = if (partner) |value| b.fmt("{s} {s}", .{ data.names[value.code], out.fraction(value.lift) }) else "none";
        var best: []const u8 = "none"; for (main_rules.rules, 1..) |rule, index| { if (b.contains(rule.x | rule.y, mask)) { best = b.fmt("{d} {s}", .{ index, out.arrow(rule, data.names) }); break; } }
        const baskets = analysis.singles.get(mask).?;
        b.append([]const u8, &lines, b.fmt("ITEM {d} {s} {s} price {s} units {d} revenue {s} share {s} baskets {d} support {s} customers {d} itemsets {d} heldout {d} hits {d} partner {s} best {s}", .{ rank, product.name, data.categories[product.category], out.money(product.price), units[i], out.money(revenue[i]), out.percent(revenue[i], total_revenue), baskets, out.fraction(Fraction.init(baskets, total)), sequences.buyers[i], count_sets, evaluation.heldout[i], evaluation.hits[i], partner_text, best }));
    }
    const category_units = b.alloc(i64, data.categories.len); const category_revenue = b.alloc(i64, data.categories.len); const category_products = b.alloc(usize, data.categories.len); const category_counts = b.alloc(i64, data.categories.len); @memset(category_units, 0); @memset(category_revenue, 0); @memset(category_products, 0);
    var all_counts: b.Counts = .empty;
    for (data.products, units, revenue) |product, quantity, amount| { category_units[product.category] += quantity; category_revenue[product.category] += amount; category_products[product.category] += 1; b.put(&all_counts, b.bit(product.code), analysis.singles.get(b.bit(product.code)).?); }
    for (category_counts, 0..) |*count, i| { count.* = apriori.support(extended, b.bit(i)); b.put(&all_counts, b.bit(i), count.*); }
    const category_order = indices(data.categories.len); std.mem.sort(usize, category_order, RevenueContext{ .revenue = category_revenue }, revenueLess);
    for (category_order) |i| b.append([]const u8, &lines, b.fmt("CATEGORY {s} items {d} units {d} revenue {s} share {s} baskets {d} support {s}", .{ data.categories[i], category_products[i], category_units[i], out.money(category_revenue[i]), out.percent(category_revenue[i], total_revenue), category_counts[i], out.fraction(Fraction.init(category_counts[i], total)) }));
    b.append([]const u8, &lines, b.fmt("TOTAL items {d} units {d} revenue {s} baskets {d} customers {d}", .{ data.products.len, total_units, out.money(total_revenue), data.baskets.len, customer_count }));
    const visited = b.alloc(bool, data.products.len); @memset(visited, false); var groups: std.ArrayList(Group) = .empty;
    for (data.products, 0..) |_, i| {
        if (visited[i]) continue; var stack: std.ArrayList(usize) = .empty; b.append(usize, &stack, i); visited[i] = true;
        var members: u128 = 0; var degree_total: usize = 0; var amount: i64 = 0; var core = i;
        while (stack.pop()) |index| {
            const product = data.products[index]; members |= b.bit(product.code); degree_total += b.size(adjacency[index]); amount += revenue[index];
            const degree = b.size(adjacency[index]); const core_degree = b.size(adjacency[core]); const support = analysis.singles.get(b.bit(product.code)).?; const core_support = analysis.singles.get(b.bit(data.products[core].code)).?;
            if (degree > core_degree or (degree == core_degree and (support > core_support or (support == core_support and index < core)))) core = index;
            var neighbors = b.iterator(adjacency[index]); while (neighbors.next()) |code| { const child = code - data.categories.len; if (!visited[child]) { visited[child] = true; b.append(usize, &stack, child); } }
        }
        if (b.size(members) >= 2) b.append(Group, &groups, .{ .members = members, .count = b.size(members), .edges = degree_total / 2, .core = core, .revenue = amount });
    }
    std.mem.sort(Group, groups.items, {}, groupLess);
    for (groups.items, 1..) |group, number| b.append([]const u8, &lines, b.fmt("GROUP {d} items {d} edges {d} core {s} revenue {s} share {s} members {s}", .{ number, group.count, group.edges, data.products[group.core].name, out.money(group.revenue), out.percent(group.revenue, total_revenue), out.itemset(group.members, data.names) }));
    var substitutes: std.ArrayList(Substitute) = .empty; var pair_cache: b.Counts = .empty;
    for (data.products, 0..) |first, i| {
        const first_mask = b.bit(first.code); if (!analysis.supports.contains(first_mask)) continue;
        for (data.products[i + 1..], i + 1..) |second, j| {
            const second_mask = b.bit(second.code); if (!analysis.supports.contains(second_mask)) continue;
            const first_count = analysis.singles.get(first_mask).?; const second_count = analysis.singles.get(second_mask).?; const expected = Fraction.init(first_count * second_count, total);
            if (expected.compare(Fraction.init(p.expected, 1)) == .lt) continue;
            const count = cachedSupport(&pair_cache, masks, first_mask | second_mask); const lift = r.lift(total, count, first_count, second_count);
            if (lift.compare(p.negative_lift) != .gt) b.append(Substitute, &substitutes, .{ .first = i, .second = j, .count = count, .expected = expected, .lift = lift });
        }
    }
    std.mem.sort(Substitute, substitutes.items, {}, substituteLess);
    for (substitutes.items) |value| b.append([]const u8, &lines, b.fmt("SUBSTITUTE {s} {s} count {d} expected {s} lift {s}", .{ data.products[value.first].name, data.products[value.second].name, value.count, out.fraction(value.expected), out.fraction(value.lift) }));
    const product_codes = b.alloc(usize, data.products.len); for (data.products, product_codes) |product, *code| code.* = product.code;
    std.mem.sort(usize, product_codes, PopularityContext{ .counts = all_counts }, popularityLess); matrixLines(&lines, "MATRIX", product_codes[0..p.matrix], masks, data.names);
    const category_codes = indices(data.categories.len); std.mem.sort(usize, category_codes, PopularityContext{ .counts = all_counts }, popularityLess); matrixLines(&lines, "CATEGORY_MATRIX", category_codes, extended, data.names);
    return .{ .lines = lines.items, .revenue = total_revenue };
}
const Trend = struct { code: usize, units: i64, slope: Fraction, relative: ?Fraction, verdict: []const u8 };
fn trendLess(_: void, a: Trend, c: Trend) bool { if (a.relative == null) return c.relative == null and a.code < c.code; if (c.relative == null) return true; const order = a.relative.?.compare(c.relative.?); return if (order == .eq) a.code < c.code else order == .gt; }
fn table(label: []const u8, values: []const i64) []const u8 { var parts: std.ArrayList([]const u8) = .empty; b.append([]const u8, &parts, b.fmt("{s: <17}", .{label})); for (values) |value| b.append([]const u8, &parts, b.fmt("{d: >6}", .{value})); return b.join(parts.items, ""); }
fn trendLines(data: Data, p: Params, history: []const Customer) b.Strings {
    var last_day: i64 = 0; for (data.baskets) |basket| last_day = @max(last_day, basket.day); const weeks: usize = @intCast(@divTrunc(last_day - 1, 7) + 1);
    const baskets = b.alloc(i64, weeks); const units = b.alloc(i64, weeks); const customers = b.alloc(i64, weeks); const week_numbers = b.alloc(i64, weeks); @memset(baskets, 0); @memset(units, 0); @memset(customers, 0);
    const series = b.alloc([]i64, data.names.len); for (series) |*values| { values.* = b.alloc(i64, weeks); @memset(values.*, 0); }
    for (data.baskets) |basket| { const week: usize = @intCast(@divTrunc(basket.day - 1, 7)); baskets[week] += 1; for (basket.units, data.products) |quantity, product| { units[week] += quantity; series[product.code][week] += quantity; series[product.category][week] += quantity; } }
    var week_sum: i64 = 0; var square_sum: i64 = 0;
    for (week_numbers, 0..) |*number, i| { number.* = b.int(i + 1); week_sum += number.*; square_sum += number.* * number.*; const days = (b.bit(7) - 1) << @intCast(i * 7); for (history) |customer| { if (customer.days & days != 0) customers[i] += 1; } }
    var lines: std.ArrayList([]const u8) = .empty; appendLines(&lines, &.{ table("WEEK", week_numbers), table("BASKETS", baskets), table("UNITS", units), table("CUSTOMERS", customers) });
    var trends: std.ArrayList(Trend) = .empty;
    for (data.names, series, 0..) |name, values, code| {
        b.append([]const u8, &lines, table(name, values)); var total: i64 = 0; var weighted: i64 = 0; for (values, week_numbers) |value, week| { total += value; weighted += week * value; }
        const slope = Fraction.init(b.int(weeks) * weighted - week_sum * total, b.int(weeks) * square_sum - week_sum * week_sum); const relative: ?Fraction = if (total > 0) slope.mul(Fraction.init(b.int(weeks), total)) else null;
        const verdict: []const u8 = if (relative == null) "NONE" else if (relative.?.compare(p.threshold) != .lt) "RISING" else if (relative.?.compare(p.threshold.negative()) != .gt) "FALLING" else "FLAT";
        b.append(Trend, &trends, .{ .code = code, .units = total, .slope = slope, .relative = relative, .verdict = verdict });
    }
    std.mem.sort(Trend, trends.items, {}, trendLess);
    for (trends.items) |trend| b.append([]const u8, &lines, b.fmt("TREND {s} units {d} slope {s} relative {s} {s}", .{ data.names[trend.code], trend.units, out.fraction(trend.slope), if (trend.relative) |value| out.fraction(value) else "-", trend.verdict })); return lines.items;
}
fn customerLines(data: Data, p: Params, history: []const Customer, rules: []const r.Rule, total_revenue: i64) b.Strings {
    var last_day: i64 = 0; for (data.baskets) |basket| last_day = @max(last_day, basket.day); var counts: [4]usize = @splat(0); var revenues: [4]i64 = @splat(0); var lines: std.ArrayList([]const u8) = .empty;
    for (history) |customer| {
        const segment: usize = if (customer.first > last_day - 28) 0 else if (customer.baskets >= 4 and last_day - customer.last <= 14) 1 else if (last_day - customer.last > 28) 2 else 3; counts[segment] += 1; revenues[segment] += customer.revenue;
        const recommendation = ruleRecommendation(customer.mask, rules, p.top); var offers: std.ArrayList([]const u8) = .empty; for (recommendation.values[0..recommendation.count]) |code| b.append([]const u8, &offers, data.names[code]);
        b.append([]const u8, &lines, b.fmt("CUSTOMER {s} baskets {d} days {d} first {d} last {d} items {d} units {d} revenue {s} average {s} favorite {s} segment {s} offer {s}", .{ customer.id, customer.baskets, b.size(customer.days), customer.first, customer.last, b.size(customer.mask), customer.units, out.money(customer.revenue), out.money(@divTrunc(customer.revenue, b.int(customer.baskets))), data.categories[customer.favorite], segments[segment], if (offers.items.len == 0) "none" else b.join(offers.items, "+") }));
    }
    for (segments, counts, revenues) |segment, count, revenue| b.append([]const u8, &lines, b.fmt("SEGMENT {s} customers {d} revenue {s} share {s}", .{ segment, count, out.money(revenue), out.percent(revenue, total_revenue) })); return lines.items;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); b.allocator = arena.allocator(); b.backing = init.gpa; const cwd = std.Io.Dir.cwd();
    const params_text = try cwd.readFileAlloc(init.io, "input/params.txt", b.allocator, .unlimited); const items_text = try cwd.readFileAlloc(init.io, "input/items.csv", b.allocator, .unlimited); const transactions_text = try cwd.readFileAlloc(init.io, "input/transactions.csv", b.allocator, .unlimited);
    const p = parameters(params_text); const data = loadData(items_text, transactions_text); const universe = b.alloc(usize, data.products.len); const taxonomy = b.alloc(u128, data.products.len);
    for (data.products, universe, taxonomy) |product, *code, *pair| { code.* = product.code; pair.* = b.bit(product.code) | b.bit(product.category); }
    const masks = b.alloc(u128, data.baskets.len); const extended = b.alloc(u128, data.baskets.len); for (data.baskets, masks, extended) |basket, *mask, *extension| { mask.* = basket.mask; extension.* = b.extended(basket, data.products); }
    const analysis = runApriori(masks, universe, p.support, p.max_size, &.{}); const growth = fp.growth(masks, p.support, p.max_size); const classified = classify(analysis, b.int(masks.len)); const main_rules = makeRules(analysis, b.int(masks.len), p, 0);
    const category = runApriori(extended, indices(data.names.len), p.category_support, p.max_size, taxonomy); const category_rules = makeRules(category, b.int(masks.len), p, b.bit(data.categories.len) - 1);
    const history = histories(data); const sequences = sequenceAnalysis(data, history, p); const evaluation = validation(data, p, universe); const item_report = itemsLines(data, p, analysis, main_rules, sequences, evaluation, masks, extended, history.len);
    const names = [_][]const u8{ "summary.txt", "itemsets.txt", "closed_maximal.txt", "rules.csv", "category_rules.csv", "sequences.txt", "validation.txt", "items_report.txt", "trends.txt", "customers.txt" };
    const reports = [_]b.Strings{ summaryLines(data, history, analysis, classified, growth, main_rules, category, category_rules, sequences), itemsetLines(analysis, data.names), closedLines(classified, data.names), out.csv(main_rules.rules, data.names), out.csv(category_rules.rules, data.names), sequences.lines, evaluation.lines, item_report.lines, trendLines(data, p, history), customerLines(data, p, history, main_rules.rules, item_report.revenue) };
    for (names, reports) |name, lines| try out.write(init.io, name, lines);
}
