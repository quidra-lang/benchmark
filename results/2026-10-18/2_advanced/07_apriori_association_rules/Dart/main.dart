import 'dart:io';
import 'dart:math';
import 'baskets.dart';
import 'apriori.dart';
import 'fpgrowth.dart';
import 'rules.dart';
import 'report.dart';

List<String> names<T>(Map<String, T> map) => map.keys.toList()..sort();
int sum(Iterable<int> values) => values.fold(0, (total, value) => total + value);

class Params {
  final Map<String, int> integers = {};
  final Map<String, Fraction> fractions = {};
  Params() {
    for (final line in File('input/params.txt').readAsLinesSync()) {
      final [key, value] = line.split(' ');
      if (value.contains('/')) { fractions[key] = Fraction.parse(value); } else { integers[key] = int.parse(value); }
    }
  }
  int n(String key) => integers[key]!;
  Fraction f(String key) => fractions[key]!;
  bool passes(Fraction confidence, Fraction lift) => meetsThresholds(confidence, lift, f('min_confidence'), f('min_lift'));
}

class Data {
  final List<String> errors = [];
  final Map<String, Product> products = {};
  final List<Transaction> transactions = [], baskets = [];
  final List<Set<String>> sets = [], extended = [];
  final Map<String, String> taxonomy = {};
  final Set<String> categories = {};
  final Map<String, List<Transaction>> customers = {};
  int itemRows = 0, transactionLines = 0, adopted = 0, rejected = 0, duplicates = 0;
  late final int firstDay, lastDay;
  Data() {
    final itemRecords = readRecords('items.csv'); itemRows = itemRecords.length;
    for (final (index, fields) in itemRecords.indexed) {
      final [name, category, priceText] = fields; final price = int.parse(priceText);
      final reason = products.containsKey(name) ? 'duplicate item $name' : price == 0 ? 'bad price $priceText' : null;
      if (reason != null) { errors.add('items.csv line ${index + 2}: $reason'); }
      else { products[name] = Product(name, category, price); taxonomy[name] = category; categories.add(category); }
    }
    final records = readRecords('transactions.csv'), seen = <String>{}; transactionLines = records.length;
    Transaction? current;
    for (final (index, fields) in records.indexed) {
      final [tid, customer, dayText, item] = fields; final day = int.parse(dayText); String? reason;
      if (current != null && current.tid != tid && seen.contains(tid)) { reason = 'tid $tid not contiguous'; }
      else {
        if (!seen.contains(tid)) { current = Transaction(tid, customer, day); seen.add(tid); transactions.add(current); }
        final transaction = current!;
        if (transaction.customer != customer) { reason = 'tid $tid customer $customer differs from ${transaction.customer}'; }
        else if (transaction.day != day) { reason = 'tid $tid day $day differs from ${transaction.day}'; }
        else if (!products.containsKey(item)) { reason = 'unknown item $item'; }
      }
      if (reason != null) { errors.add('transactions.csv line ${index + 2}: $reason'); rejected++; }
      else { adopted++; if (current!.add(item)) duplicates++; }
    }
    for (final transaction in transactions.where((t) => t.counts.isNotEmpty)) {
      baskets.add(transaction); sets.add(transaction.products.toSet()); extended.add(extendedBasket(transaction.products, taxonomy)); (customers[transaction.customer] ??= []).add(transaction);
    }
    firstDay = baskets.map((b) => b.day).reduce(min); lastDay = baskets.map((b) => b.day).reduce(max);
  }
}

typedef Level = ({int size, int candidates, int excluded, int pruned, int counted, Frequent frequent});
typedef RuleSet = ({int generated, List<Rule> rules, int productive});
typedef Classifications = ({Frequent closed, Frequent maximal, Frequent generators});

class Mining {
  final List<Level> levels;
  final Frequent frequent;
  Mining(this.levels, this.frequent);
}

Mining apriori(List<Set<String>> baskets, Itemset universe, int minimum, int maximum, [Map<String, String>? taxonomy]) {
  final ordered = [...universe]..sort(), levels = <Level>[], frequent = <String, Counted>{};
  var candidates = ordered.map((item) => [item]).toList(), previous = <Itemset>[];
  for (var size = 1; size <= maximum; size++) {
    int joined, excluded, pruned;
    if (size == 1) { joined = ordered.length; excluded = pruned = 0; }
    else {
      if (previous.isEmpty) break;
      final result = generateCandidates(previous, size, taxonomy); joined = result.joined; excluded = result.excluded; pruned = result.pruned; candidates = result.itemsets;
    }
    final counts = countSupports(baskets, candidates), level = <String, Counted>{}; previous = [];
    for (final items in candidates) {
      final key = setKey(items), count = counts[key]!;
      if (count >= minimum) { final pattern = (items: items, count: count); level[key] = pattern; frequent[key] = pattern; previous.add(items); }
    }
    final entries = level.entries.toList()..sort((a, b) => compareSets(a.value.items, b.value.items));
    levels.add((size: size, candidates: joined, excluded: excluded, pruned: pruned, counted: candidates.length, frequent: Map.fromEntries(entries)));
  }
  return Mining(levels, frequent);
}

List<Itemset> subsets(Itemset items) => [for (var mask = 0; mask < (1 << items.length); mask++) [for (final (i, item) in items.indexed) if ((mask & (1 << i)) != 0) item]];
int countIn(Frequent frequent, Itemset items, int total) => items.isEmpty ? total : frequent[setKey(items)]!.count;

RuleSet makeRules(Mining result, int total, Params p, [Map<String, Product>? products]) {
  final frequent = result.frequent, rules = <Rule>[]; var generated = 0;
  for (final pattern in frequent.values) {
    final items = pattern.items, count = pattern.count;
    if (items.length < 2 || products != null && items.every(products.containsKey)) continue;
    for (final first in subsets(items)) {
      if (first.isEmpty || first.length == items.length) continue;
      generated++; final second = items.where((item) => !first.contains(item)).toList();
      final rule = Rule(items, first, second, count, total, countIn(frequent, first, total), countIn(frequent, second, total));
      if (!p.passes(rule.confidence, rule.lift)) continue;
      var best = Fraction(0);
      for (final subset in subsets(first)) {
        if (subset.length == first.length) continue;
        final union = [...subset, ...second]..sort(), confidence = Fraction(countIn(frequent, union, total), countIn(frequent, subset, total));
        if (confidence.compareTo(best) > 0) best = confidence;
      }
      rule.improvement = rule.confidence - best; rules.add(rule);
    }
  }
  rules.sort(compareRules); for (final (index, rule) in rules.indexed) { rule.rank = index + 1; }
  return (generated: generated, rules: rules, productive: rules.where((rule) => rule.improvement.numerator > 0).length);
}

Classifications classify(Frequent frequent, int total) {
  final closed = {for (final key in frequent.keys) key: true}, maximal = {for (final key in frequent.keys) key: true}, generators = <String, Counted>{};
  for (final pattern in frequent.values) {
    var generator = true;
    for (final subset in subsets(pattern.items)) {
      if (subset.length == pattern.items.length) continue;
      if (countIn(frequent, subset, total) == pattern.count) generator = false;
      if (subset.isEmpty) continue;
      final key = setKey(subset); maximal[key] = false; if (frequent[key]!.count == pattern.count) closed[key] = false;
    }
    if (generator) generators[setKey(pattern.items)] = pattern;
  }
  return (closed: Map.fromEntries(frequent.entries.where((entry) => closed[entry.key]!)), maximal: Map.fromEntries(frequent.entries.where((entry) => maximal[entry.key]!)), generators: generators);
}

Fraction median(List<int> values) {
  final ordered = [...values]..sort(), middle = ordered.length ~/ 2;
  return ordered.length.isOdd ? Fraction(ordered[middle]) : Fraction(ordered[middle - 1] + ordered[middle], 2);
}

typedef Sequence = ({String first, String second, int count, int base, Fraction confidence, Fraction lift, Fraction gap});
typedef Repeat = ({String item, int customers, int count, int minimum, int maximum, Fraction mean, Fraction median});
typedef Patterns = ({Map<String, int> buyers, int pairs, int multiDay, List<Sequence> sequences, List<Repeat> repeats});

Patterns purchasePatterns(Data data, Params p) {
  final days = <String, Map<String, List<int>>>{}, buyers = {for (final item in data.products.keys) item: 0}; var multiDay = 0;
  for (final entry in data.customers.entries) {
    final customerDays = <int>{}, purchased = <String, Set<int>>{};
    for (final basket in entry.value) { customerDays.add(basket.day); for (final item in basket.counts.keys) { (purchased[item] ??= {}).add(basket.day); } }
    if (customerDays.length >= 2) multiDay++;
    days[entry.key] = {};
    for (final entryItem in purchased.entries) { days[entry.key]![entryItem.key] = entryItem.value.toList()..sort(); buyers[entryItem.key] = buyers[entryItem.key]! + 1; }
  }
  final pairs = <(String, String), List<int>>{}, intervals = <String, List<int>>{}, repeatCustomers = <String, int>{};
  for (final purchases in days.values) {
    for (final firstEntry in purchases.entries) {
      final first = firstEntry.key, firstDays = firstEntry.value;
      if (firstDays.length >= 2) { repeatCustomers[first] = (repeatCustomers[first] ?? 0) + 1; for (var i = 1; i < firstDays.length; i++) { (intervals[first] ??= []).add(firstDays[i] - firstDays[i - 1]); } }
      for (final secondEntry in purchases.entries) {
        final secondDays = secondEntry.value;
        if (firstDays.first >= secondDays.last) continue;
        var gap = secondDays.last - firstDays.first, j = 0;
        for (final day in firstDays) { while (j < secondDays.length && secondDays[j] <= day) { j++; } if (j < secondDays.length) gap = min(gap, secondDays[j] - day); }
        (pairs[(first, secondEntry.key)] ??= []).add(gap);
      }
    }
  }
  final sequences = <Sequence>[];
  for (final entry in pairs.entries) {
    final (first, second) = entry.key; final count = entry.value.length;
    if (count < p.n('sequence_min_support')) continue;
    sequences.add((first: first, second: second, count: count, base: buyers[first]!, confidence: Fraction(count, buyers[first]!), lift: Fraction(count * data.customers.length, buyers[first]! * buyers[second]!), gap: median(entry.value)));
  }
  sequences.sort((a, b) {
    for (final comparison in [b.count.compareTo(a.count), b.confidence.compareTo(a.confidence), a.first.compareTo(b.first), a.second.compareTo(b.second)]) { if (comparison != 0) return comparison; }
    return 0;
  });
  final repeats = <Repeat>[];
  for (final entry in intervals.entries) { final list = entry.value; repeats.add((item: entry.key, customers: repeatCustomers[entry.key]!, count: list.length, minimum: list.reduce(min), maximum: list.reduce(max), mean: Fraction(sum(list), list.length), median: median(list))); }
  repeats.sort((a, b) { final comparison = a.mean.compareTo(b.mean); return comparison != 0 ? comparison : a.item.compareTo(b.item); });
  return (buyers: buyers, pairs: pairs.length, multiDay: multiDay, sequences: sequences, repeats: repeats);
}

class SupportCounter {
  final List<Set<String>> baskets;
  final Map<String, int> cache = {};
  SupportCounter(this.baskets);
  int count(Itemset items) {
    if (items.isEmpty) return baskets.length;
    final ordered = [...items]..sort(), key = setKey(ordered);
    return cache.putIfAbsent(key, () => baskets.where((basket) => containsSet(basket, ordered)).length);
  }
}

Itemset recommend(Set<String> atHand, Itemset candidates, int top) {
  final selected = <String>[];
  for (final item in candidates) { if (!atHand.contains(item) && !selected.contains(item)) { selected.add(item); if (selected.length == top) break; } }
  return selected;
}
Itemset ruleRecommendation(Set<String> atHand, List<Rule> rules, int top) => recommend(atHand, [for (final rule in rules) if (rule.consequent.length == 1 && containsSet(atHand, rule.antecedent)) rule.consequent.first], top);

typedef TrainingCase = ({Rule rule, int antecedent, int joint, Fraction? confidence, Fraction? lift, String verdict});

class Validation {
  final List<Set<String>> train = [], test = [];
  late final Mining training;
  late final List<Rule> trainRules, emerging;
  final List<TrainingCase> verdicts = [];
  final Map<String, int> totals = {'HOLD': 0, 'FAIL': 0, 'UNSEEN': 0};
  final Map<int, List<int>> evaluations = {};
  final List<int> total = List.filled(5, 0);
  late final Map<String, int> held, hits;
  Validation(Data data, Params p) {
    for (final (index, basket) in data.baskets.indexed) { (basket.day <= p.n('split_day') ? train : test).add(data.sets[index]); }
    final universe = names(data.products);
    training = apriori(train, universe, p.n('train_min_support'), p.n('max_size'));
    final testing = apriori(test, universe, p.n('test_min_support'), p.n('max_size'));
    trainRules = makeRules(training, train.length, p).rules;
    final testRules = makeRules(testing, test.length, p).rules, testCounter = SupportCounter(test), trainCounter = SupportCounter(train), known = <(String, String)>{};
    for (final rule in trainRules) {
      final a = testCounter.count(rule.antecedent), b = testCounter.count(rule.consequent), c = testCounter.count(rule.itemset);
      Fraction? confidence, lift; String verdict;
      if (a == 0 || b == 0) { verdict = 'UNSEEN'; }
      else { confidence = Fraction(c, a); lift = Fraction(test.length * c, a * b); verdict = p.passes(confidence, lift) ? 'HOLD' : 'FAIL'; }
      totals[verdict] = totals[verdict]! + 1; verdicts.add((rule: rule, antecedent: a, joint: c, confidence: confidence, lift: lift, verdict: verdict)); known.add((setKey(rule.antecedent), setKey(rule.consequent)));
    }
    emerging = testRules.where((rule) => !known.contains((setKey(rule.antecedent), setKey(rule.consequent)))).toList();
    final popular = [...universe]..sort((a, b) { final comparison = trainCounter.count([b]).compareTo(trainCounter.count([a])); return comparison != 0 ? comparison : a.compareTo(b); });
    held = {for (final item in universe) item: 0}; hits = {for (final item in universe) item: 0};
    for (final basket in test) {
      final size = basket.length; if (size < 2) continue;
      for (final item in basket) {
        final atHand = {...basket}..remove(item), recommendation = ruleRecommendation(atHand, trainRules, p.n('recommend_top')), baseline = recommend(atHand, popular, p.n('recommend_top'));
        final counts = [1, recommendation.isNotEmpty ? 1 : 0, recommendation.isNotEmpty && recommendation.first == item ? 1 : 0, recommendation.contains(item) ? 1 : 0, baseline.contains(item) ? 1 : 0];
        held[item] = held[item]! + 1; hits[item] = hits[item]! + counts[3]; final evaluation = evaluations.putIfAbsent(size, () => List.filled(5, 0));
        for (final (i, value) in counts.indexed) { evaluation[i] += value; total[i] += value; }
      }
    }
  }
}

typedef Partner = ({String item, int count, Fraction lift});
class ProductStats {
  int units = 0, revenue = 0, itemsets = 0;
  final int support;
  Partner? partner;
  Rule? best;
  ProductStats(this.support);
}
typedef Group = ({Itemset members, int edges, String core, int revenue});
typedef Substitute = ({String first, String second, int count, Fraction expected, Fraction lift});

class ProductAnalysis {
  final Map<String, ProductStats> stats = {};
  final List<Group> groups = [];
  final List<Substitute> substitutes = [];
  ProductAnalysis(Data data, Params p, Mining main, List<Rule> rules, SupportCounter counter) {
    for (final item in data.products.keys) { stats[item] = ProductStats(counter.count([item])); }
    for (final basket in data.baskets) {
      for (final entry in basket.counts.entries) { stats[entry.key]!.units += entry.value; stats[entry.key]!.revenue += entry.value * data.products[entry.key]!.price; }
    }
    final graph = {for (final item in data.products.keys) item: <String>[]};
    for (final pattern in main.frequent.values) {
      for (final item in pattern.items) { stats[item]!.itemsets++; }
      if (pattern.items.length != 2) continue;
      final [first, second] = pattern.items;
      final lift = Fraction(data.baskets.length * pattern.count, stats[first]!.support * stats[second]!.support);
      for (final (item, other) in [(first, second), (second, first)]) {
        final old = stats[item]!.partner;
        if (old == null || lift.compareTo(old.lift) > 0 || lift.compareTo(old.lift) == 0 && (pattern.count > old.count || pattern.count == old.count && other.compareTo(old.item) < 0)) {
          stats[item]!.partner = (item: other, count: pattern.count, lift: lift);
        }
      }
      if (lift.compareTo(p.f('group_min_lift')) >= 0) { graph[first]!.add(second); graph[second]!.add(first); }
    }
    for (final rule in rules) { for (final item in rule.itemset) { stats[item]!.best ??= rule; } }
    final visited = <String>{};
    for (final start in names(data.products)) {
      if (visited.contains(start) || graph[start]!.isEmpty) continue;
      final stack = [start], members = <String>[]; visited.add(start);
      while (stack.isNotEmpty) {
        final item = stack.removeLast(); members.add(item);
        for (final other in graph[item]!) { if (visited.add(other)) stack.add(other); }
      }
      members.sort(); final cores = [...members]..sort((a, b) {
        for (final comparison in [graph[b]!.length.compareTo(graph[a]!.length), stats[b]!.support.compareTo(stats[a]!.support), a.compareTo(b)]) { if (comparison != 0) return comparison; }
        return 0;
      });
      groups.add((members: members, edges: sum(members.map((item) => graph[item]!.length)) ~/ 2, core: cores.first, revenue: sum(members.map((item) => stats[item]!.revenue))));
    }
    groups.sort((a, b) { final comparison = b.members.length.compareTo(a.members.length); return comparison != 0 ? comparison : a.members.first.compareTo(b.members.first); });
    final singletons = [for (final pattern in main.frequent.values) if (pattern.items.length == 1) pattern.items.first]..sort();
    for (final (i, first) in singletons.indexed) {
      for (var j = i + 1; j < singletons.length; j++) {
        final second = singletons[j], product = stats[first]!.support * stats[second]!.support;
        if (product < p.n('negative_min_expected') * data.baskets.length) continue;
        final count = counter.count([first, second]), lift = Fraction(data.baskets.length * count, product);
        if (lift.compareTo(p.f('negative_max_lift')) <= 0) substitutes.add((first: first, second: second, count: count, expected: Fraction(product, data.baskets.length), lift: lift));
      }
    }
    substitutes.sort((a, b) {
      for (final comparison in [a.lift.compareTo(b.lift), b.expected.compareTo(a.expected), a.first.compareTo(b.first), a.second.compareTo(b.second)]) { if (comparison != 0) return comparison; }
      return 0;
    });
  }
}

typedef Trend = ({String name, int units, Fraction slope, Fraction? relative, String verdict});
class Trends {
  late final int weeks;
  final Map<String, List<int>> series = {};
  late final List<int> baskets, units, customers;
  final List<Trend> trends = [];
  Trends(Data data, Params p) {
    weeks = (data.lastDay - 1) ~/ 7 + 1;
    final categories = data.categories.toList()..sort();
    for (final name in [...categories, ...names(data.products)]) { series[name] = List.filled(weeks, 0); }
    baskets = List.filled(weeks, 0); units = List.filled(weeks, 0); final customerSets = List.generate(weeks, (_) => <String>{});
    for (final basket in data.baskets) {
      final week = (basket.day - 1) ~/ 7; baskets[week]++; units[week] += basket.units; customerSets[week].add(basket.customer);
      for (final entry in basket.counts.entries) { series[entry.key]![week] += entry.value; series[data.taxonomy[entry.key]]![week] += entry.value; }
    }
    customers = customerSets.map((set) => set.length).toList();
    final sumW = sum(List.generate(weeks, (i) => i + 1)), sumSquares = sum(List.generate(weeks, (i) => (i + 1) * (i + 1))), denominator = weeks * sumSquares - sumW * sumW;
    for (final entry in series.entries) {
      final total = sum(entry.value), weighted = sum(entry.value.indexed.map((pair) => (pair.$1 + 1) * pair.$2)), slope = Fraction(weeks * weighted - sumW * total, denominator);
      final relative = total > 0 ? slope.times(weeks, total) : null, threshold = p.f('trend_threshold'), negative = Fraction(-threshold.numerator, threshold.denominator);
      final verdict = relative == null ? 'NONE' : relative.compareTo(threshold) >= 0 ? 'RISING' : relative.compareTo(negative) <= 0 ? 'FALLING' : 'FLAT';
      trends.add((name: entry.key, units: total, slope: slope, relative: relative, verdict: verdict));
    }
    trends.sort((a, b) {
      final first = a.relative, second = b.relative;
      if (first == null) return second == null ? a.name.compareTo(b.name) : 1;
      if (second == null) return -1;
      final comparison = second.compareTo(first); return comparison != 0 ? comparison : a.name.compareTo(b.name);
    });
  }
}

List<Counted> orderedItemsets(Frequent frequent) => frequent.values.toList()..sort((a, b) => sizeOrder(a.items, b.items));

class Analysis {
  final Params params = Params();
  final Data data = Data();
  late final Mining mining, category;
  late final Classifications classification;
  late final GrowthResult growth;
  late final bool matches;
  late final RuleSet mainRules, categoryRules;
  late final Patterns patterns;
  late final Validation validation;
  late final SupportCounter counter, extendedCounter;
  late final ProductAnalysis products;
  late final Trends trends;
  Analysis() {
    final universe = names(data.products), total = data.baskets.length;
    mining = apriori(data.sets, universe, params.n('min_support'), params.n('max_size')); classification = classify(mining.frequent, total);
    growth = fpGrowth([for (final basket in data.baskets) (basket.products, 1)], params.n('min_support'), params.n('max_size'));
    matches = mining.frequent.length == growth.itemsets.length && mining.frequent.entries.every((entry) => growth.itemsets[entry.key]?.count == entry.value.count);
    mainRules = makeRules(mining, total, params);
    category = apriori(data.extended, [...universe, ...data.categories], params.n('category_min_support'), params.n('max_size'), data.taxonomy); categoryRules = makeRules(category, total, params, data.products);
    patterns = purchasePatterns(data, params); validation = Validation(data, params); counter = SupportCounter(data.sets); extendedCounter = SupportCounter(data.extended);
    products = ProductAnalysis(data, params, mining, mainRules.rules, counter); trends = Trends(data, params);
  }

  List<String> summaryLines() {
    final total = data.baskets.length, sizes = data.baskets.map((b) => b.counts.length).toList(), largest = sizes.reduce(max), lines = data.errors.map((error) => 'ERROR $error').toList();
    lines.add('ITEMS rows ${data.itemRows} adopted ${data.products.length} categories ${data.categories.length}');
    lines.add('TRANSACTIONS lines ${data.transactionLines} adopted ${data.adopted} rejected ${data.rejected} duplicates ${data.duplicates} transactions ${data.transactions.length} empty ${data.transactions.length - total}');
    lines.add('BASKETS count $total customers ${data.customers.length} first_day ${data.firstDay} last_day ${data.lastDay} average_size ${fractionText(Fraction(sum(sizes), total))} largest $largest');
    for (var size = 1; size <= largest; size++) { final count = sizes.where((value) => value == size).length; lines.add('SIZE $size baskets $count share ${percentText(count, total)}'); }
    lines.add('FREQUENT itemsets ${mining.frequent.length} closed ${classification.closed.length} maximal ${classification.maximal.length} generators ${classification.generators.length} levels ${mining.levels.length}');
    lines.add('FPGROWTH header ${growth.header} nodes ${growth.nodes} conditional_trees ${growth.conditionalTrees} conditional_nodes ${growth.conditionalNodes} itemsets ${growth.itemsets.length} ${matches ? 'MATCH' : 'MISMATCH'}');
    if (!matches) {
      for (final (label, first, second) in [('ONLY_APRIORI', mining.frequent, growth.itemsets), ('ONLY_FPGROWTH', growth.itemsets, mining.frequent)]) {
        for (final pattern in orderedItemsets(first)) { if (second[setKey(pattern.items)]?.count != pattern.count) lines.add('$label ${setKey(pattern.items)} ${pattern.count}'); }
      }
    }
    lines.add('RULES generated ${mainRules.generated} passed ${mainRules.rules.length} productive ${mainRules.productive}');
    for (final level in category.levels) { lines.add('CATEGORY_LEVEL ${level.size} candidates ${level.candidates} taxonomy ${level.excluded} pruned ${level.pruned} counted ${level.counted} frequent ${level.frequent.length}'); }
    lines.add('CATEGORY_RULES itemsets ${category.frequent.length} generated ${categoryRules.generated} passed ${categoryRules.rules.length} productive ${categoryRules.productive}');
    lines.add('SEQUENCES customers ${data.customers.length} multi_day ${patterns.multiDay} pairs ${patterns.pairs} frequent ${patterns.sequences.length}');
    return lines;
  }

  List<String> itemsetLines() => [for (final level in mining.levels) ...['LEVEL ${level.size} candidates ${level.candidates} pruned ${level.pruned} counted ${level.counted} frequent ${level.frequent.length}', for (final pattern in level.frequent.values) '${setKey(pattern.items)} ${pattern.count}']];

  List<String> classificationLines() => [for (final (label, frequent) in [('CLOSED', classification.closed), ('MAXIMAL', classification.maximal), ('GENERATOR', classification.generators)]) for (final pattern in orderedItemsets(frequent)) '$label ${setKey(pattern.items)} ${pattern.count}'];

  List<String> sequenceLines() => [
    for (final (index, p) in patterns.sequences.indexed) 'SEQ ${index + 1} ${p.first} -> ${p.second} customers ${p.count} base ${p.base} confidence ${fractionText(p.confidence)} lift ${fractionText(p.lift)} gap ${fractionText(p.gap)}',
    for (final p in patterns.repeats) 'REPEAT ${p.item} customers ${p.customers} intervals ${p.count} min ${p.minimum} max ${p.maximum} mean ${fractionText(p.mean)} median ${fractionText(p.median)}'
  ];

  String evaluationLine(String label, List<int> counts) {
    final [cases, covered, hit1, hit, baseline] = counts;
    return 'RECOMMEND $label cases $cases covered $covered hit1 $hit1 hit $hit rate ${fractionText(Fraction(hit, cases))} baseline $baseline rate ${fractionText(Fraction(baseline, cases))}';
  }

  List<String> validationLines() {
    final v = validation, lines = <String>[];
    for (final entry in v.verdicts) {
      final rule = entry.rule;
      lines.add('RULE ${rule.rank} ${ruleArrow(rule)} train ${rule.count} confidence ${fractionText(rule.confidence)} lift ${fractionText(rule.lift)} test ${entry.joint} of ${entry.antecedent} confidence ${entry.confidence == null ? '-' : fractionText(entry.confidence!)} lift ${entry.lift == null ? '-' : fractionText(entry.lift!)} ${entry.verdict}');
    }
    for (final rule in v.emerging) { lines.add('EMERGING ${rule.rank} ${ruleArrow(rule)} test ${rule.count} confidence ${fractionText(rule.confidence)} lift ${fractionText(rule.lift)}'); }
    lines.add('VALIDATION train ${v.train.length} test ${v.test.length} itemsets ${v.training.frequent.length} rules ${v.trainRules.length} hold ${v.totals['HOLD']} fail ${v.totals['FAIL']} unseen ${v.totals['UNSEEN']} emerging ${v.emerging.length}');
    final sizes = v.evaluations.keys.toList()..sort();
    for (final size in sizes) { lines.add(evaluationLine('size $size', v.evaluations[size]!)); }
    lines.add(evaluationLine('total', v.total)); return lines;
  }

  List<String> matrixLines(String label, Itemset items, SupportCounter counter) {
    final lines = [for (final (index, item) in items.indexed) '$label ${index + 1} $item baskets ${counter.count([item])}'];
    lines.add('    ${List.generate(items.length, (i) => '${i + 1}'.padLeft(7)).join()}');
    for (final (i, first) in items.indexed) {
      final values = [for (final (j, second) in items.indexed) (i == j ? '-' : '${100 * counter.baskets.length * counter.count([first, second]) ~/ (counter.count([first]) * counter.count([second]))}').padLeft(7)];
      lines.add('${'${i + 1}'.padLeft(4)}${values.join()}');
    }
    return lines;
  }

  List<String> productLines() {
    final stats = products.stats, total = data.baskets.length, revenue = sum(products.stats.values.map((p) => p.revenue)), units = sum(products.stats.values.map((p) => p.units)), lines = <String>[];
    final order = names(data.products)..sort((a, b) { final comparison = stats[b]!.revenue.compareTo(stats[a]!.revenue); return comparison != 0 ? comparison : a.compareTo(b); });
    for (final (index, item) in order.indexed) {
      final product = data.products[item]!, p = stats[item]!, partner = p.partner, best = p.best;
      final partnerText = partner == null ? 'none' : '${partner.item} ${fractionText(partner.lift)}', bestText = best == null ? 'none' : '${best.rank} ${ruleArrow(best)}';
      lines.add('ITEM ${index + 1} $item ${product.category} price ${moneyText(product.price)} units ${p.units} revenue ${moneyText(p.revenue)} share ${percentText(p.revenue, revenue)} baskets ${p.support} support ${fractionText(Fraction(p.support, total))} customers ${patterns.buyers[item]} itemsets ${p.itemsets} heldout ${validation.held[item]} hits ${validation.hits[item]} partner $partnerText best $bestText');
    }
    final categoryStats = {for (final name in data.categories) name: <int>[0, 0, 0]};
    for (final entry in data.products.entries) { final p = categoryStats[entry.value.category]!; p[0]++; p[1] += stats[entry.key]!.units; p[2] += stats[entry.key]!.revenue; }
    final categories = names(categoryStats)..sort((a, b) { final comparison = categoryStats[b]![2].compareTo(categoryStats[a]![2]); return comparison != 0 ? comparison : a.compareTo(b); });
    for (final name in categories) {
      final p = categoryStats[name]!, count = extendedCounter.count([name]);
      lines.add('CATEGORY $name items ${p[0]} units ${p[1]} revenue ${moneyText(p[2])} share ${percentText(p[2], revenue)} baskets $count support ${fractionText(Fraction(count, total))}');
    }
    lines.add('TOTAL items ${data.products.length} units $units revenue ${moneyText(revenue)} baskets $total customers ${data.customers.length}');
    for (final (index, group) in products.groups.indexed) { lines.add('GROUP ${index + 1} items ${group.members.length} edges ${group.edges} core ${group.core} revenue ${moneyText(group.revenue)} share ${percentText(group.revenue, revenue)} members ${setKey(group.members)}'); }
    for (final s in products.substitutes) { lines.add('SUBSTITUTE ${s.first} ${s.second} count ${s.count} expected ${fractionText(s.expected)} lift ${fractionText(s.lift)}'); }
    final matrixProducts = names(data.products)..sort((a, b) { final comparison = counter.count([b]).compareTo(counter.count([a])); return comparison != 0 ? comparison : a.compareTo(b); });
    lines.addAll(matrixLines('MATRIX', matrixProducts.take(params.n('matrix_size')).toList(), counter));
    final matrixCategories = data.categories.toList()..sort((a, b) { final comparison = extendedCounter.count([b]).compareTo(extendedCounter.count([a])); return comparison != 0 ? comparison : a.compareTo(b); });
    lines.addAll(matrixLines('CATEGORY_MATRIX', matrixCategories, extendedCounter)); return lines;
  }

  List<String> trendLines() {
    final t = trends, lines = <String>[];
    final rows = {'WEEK': List.generate(t.weeks, (i) => i + 1), 'BASKETS': t.baskets, 'UNITS': t.units, 'CUSTOMERS': t.customers, ...t.series};
    for (final entry in rows.entries) { lines.add(entry.key.padRight(17) + entry.value.map((v) => '$v'.padLeft(6)).join()); }
    for (final trend in t.trends) { lines.add('TREND ${trend.name} units ${trend.units} slope ${fractionText(trend.slope)} relative ${trend.relative == null ? '-' : fractionText(trend.relative!)} ${trend.verdict}'); }
    return lines;
  }

  List<String> customerLines() {
    final lines = <String>[], segments = {'NEW': [0, 0], 'LOYAL': [0, 0], 'AT_RISK': [0, 0], 'REGULAR': [0, 0]}, totalRevenue = sum(products.stats.values.map((p) => p.revenue));
    for (final customer in names(data.customers)) {
      final baskets = data.customers[customer]!, days = <int>{}, history = <String>{}, categories = <String, int>{}; var units = 0, revenue = 0;
      for (final basket in baskets) {
        days.add(basket.day);
        for (final entry in basket.counts.entries) {
          history.add(entry.key); units += entry.value; final product = data.products[entry.key]!; revenue += entry.value * product.price; categories[product.category] = (categories[product.category] ?? 0) + entry.value;
        }
      }
      final first = days.reduce(min), last = days.reduce(max), count = baskets.length, favorite = names(categories)..sort((a, b) { final comparison = categories[b]!.compareTo(categories[a]!); return comparison != 0 ? comparison : a.compareTo(b); });
      final segment = first > data.lastDay - 28 ? 'NEW' : count >= 4 && data.lastDay - last <= 14 ? 'LOYAL' : data.lastDay - last > 28 ? 'AT_RISK' : 'REGULAR';
      final offer = ruleRecommendation(history, mainRules.rules, params.n('recommend_top')); segments[segment]![0]++; segments[segment]![1] += revenue;
      lines.add('CUSTOMER $customer baskets $count days ${days.length} first $first last $last items ${history.length} units $units revenue ${moneyText(revenue)} average ${moneyText(revenue ~/ count)} favorite ${favorite.first} segment $segment offer ${offer.isEmpty ? 'none' : setKey(offer)}');
    }
    for (final entry in segments.entries) { lines.add('SEGMENT ${entry.key} customers ${entry.value[0]} revenue ${moneyText(entry.value[1])} share ${percentText(entry.value[1], totalRevenue)}'); }
    return lines;
  }
}

void main() {
  final a = Analysis();
  for (final entry in {'summary.txt': a.summaryLines(), 'itemsets.txt': a.itemsetLines(), 'closed_maximal.txt': a.classificationLines(), 'rules.csv': rulesCsv(a.mainRules.rules), 'category_rules.csv': rulesCsv(a.categoryRules.rules), 'sequences.txt': a.sequenceLines(), 'validation.txt': a.validationLines(), 'items_report.txt': a.productLines(), 'trends.txt': a.trendLines(), 'customers.txt': a.customerLines()}.entries) {
    writeReport(entry.key, entry.value);
  }
}
