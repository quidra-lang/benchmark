import 'dart:io';
import 'dart:math' as math;
import 'transactions.dart';
import 'features.dart';
import 'kmeans.dart';
import 'validation.dart' as validation;
import 'profiles.dart';
import 'report.dart';

class Minstd {
  int state;
  Minstd(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }
}

List<double> nearestGaps(List<List<double>> points, List<int> chosen) =>
    [for (final point in points) chosen.map((index) => squaredDistance(point, points[index])).reduce(math.min)];

List<int> maximin(List<List<double>> points, int k, int number) {
  final center = meanPoint(points), spread = <double>[];
  for (final point in points) {
    spread.add(squaredDistance(point, center));
  }
  final order = List.generate(points.length, (index) => index)..sort((first, second) {
    final compared = spread[first].compareTo(spread[second]);
    return compared != 0 ? compared : first.compareTo(second);
  });
  final chosen = [order[number - 1]];
  while (chosen.length < k) {
    final gaps = nearestGaps(points, chosen);
    var best = 0;
    for (var index = 1; index < gaps.length; index++) {
      if (gaps[index] > gaps[best]) best = index;
    }
    chosen.add(best);
  }
  return chosen;
}

List<int> initialSeeds(String method, List<List<double>> points, int k, int number, Minstd generator) {
  if (method == 'maximin') return maximin(points, k, number);
  final chosen = <int>[];
  if (method == 'forgy') {
    while (chosen.length < k) {
      final index = generator.draw() % points.length;
      if (!chosen.contains(index)) chosen.add(index);
    }
    return chosen;
  }
  chosen.add(generator.draw() % points.length);
  while (chosen.length < k) {
    final gaps = nearestGaps(points, chosen);
    final weight = orderedSum(gaps);
    final threshold = (generator.draw() / 2147483647) * weight;
    var total = 0.0, selected = -1;
    for (var index = 0; index < gaps.length; index++) {
      total += gaps[index];
      if (total > threshold) {
        selected = index;
        break;
      }
    }
    if (selected < 0) {
      for (var index = 0; index < gaps.length; index++) {
        if (gaps[index] > 0) selected = index;
      }
    }
    chosen.add(selected);
  }
  return chosen;
}

class Improvement {
  final List<int> labels;
  final int passes, transfers;
  final double sseValue;
  Improvement(this.labels, this.passes, this.transfers, this.sseValue);
}

Improvement improve(List<List<double>> points, List<int> original, int k, int limit) {
  final labels = original.toList(), sizes = clusterSizes(original, k);
  final centers = clusterCenters(points, labels, k);
  var passes = 0, transfers = 0;
  while (passes < limit) {
    var moved = false;
    passes++;
    for (var index = 0; index < points.length; index++) {
      final own = labels[index];
      if (sizes[own] == 1) continue;
      final removal = (sizes[own] / (sizes[own] - 1)) * squaredDistance(points[index], centers[own]);
      var target = -1, cost = 0.0;
      for (var cluster = 0; cluster < k; cluster++) {
        if (cluster == own) continue;
        final candidate = (sizes[cluster] / (sizes[cluster] + 1)) * squaredDistance(points[index], centers[cluster]);
        if (target < 0 || candidate < cost) {
          target = cluster;
          cost = candidate;
        }
      }
      if (cost < removal) {
        labels[index] = target;
        sizes[own]--;
        sizes[target]++;
        centers[own] = clusterCenter(points, labels, own);
        centers[target] = clusterCenter(points, labels, target);
        transfers++;
        moved = true;
      }
    }
    if (!moved) break;
  }
  return Improvement(labels, passes, transfers, sse(points, labels, clusterCenters(points, labels, k)));
}

class Run {
  final String method;
  final int number;
  final List<int> seeds;
  final LloydResult result;
  final double lloydSSE;
  final Improvement improved;
  Run._(this.method, this.number, this.seeds, this.result, this.lloydSSE, this.improved);
  factory Run(String method, int number, List<int> seeds, List<List<double>> points, int limit) {
    final result = lloyd(points, [for (final index in seeds) points[index]], limit);
    return Run._(method, number, seeds, result, sse(points, result.labels, result.centers),
        improve(points, result.labels, seeds.length, limit));
  }
}

Run bestRun(List<Run> runs) {
  var best = runs.first;
  for (final run in runs.skip(1)) {
    if (fourDecimal(run.improved.sseValue) < fourDecimal(best.improved.sseValue)) best = run;
  }
  return best;
}

class Solution {
  final int k;
  final List<List<int>> members;
  final List<int> sizes, labels;
  final List<List<double>> centers;
  final double sseValue;
  Solution._(this.k, this.members, this.sizes, this.labels, this.centers, this.sseValue);
  factory Solution(List<List<double>> points, List<int> labels, int k) {
    final groups = List.generate(k, (_) => <int>[]);
    for (var index = 0; index < labels.length; index++) {
      groups[labels[index]].add(index);
    }
    groups.sort((first, second) {
      final compared = second.length.compareTo(first.length);
      return compared != 0 ? compared : first.first.compareTo(second.first);
    });
    final updated = List.filled(labels.length, 0);
    for (var cluster = 0; cluster < k; cluster++) {
      for (final index in groups[cluster]) {
        updated[index] = cluster;
      }
    }
    final centers = clusterCenters(points, updated, k);
    return Solution._(k, groups, groups.map((group) => group.length).toList(), updated,
        centers, sse(points, updated, centers));
  }
}

class Candidate {
  final int k;
  final List<Run> runs, methodBests;
  final Run best;
  final Solution solution;
  List<double> silhouettes = [];
  double silhouette = 0, calinskiHarabasz = 0, daviesBouldin = 0, elbow = 0;
  double? hartigan;
  List<int> ruleNumbers = [];
  List<String> names = [];
  Candidate(this.k, this.runs, this.methodBests, this.best, this.solution);
}

(List<int>, List<String>) segmentNames(List<Rule> rules, List<List<double>> centers) {
  final numbers = <int>[], names = <String>[], used = <int, int>{};
  for (final center in centers) {
    final number = ruleNumber(rules, center);
    final repeat = (used[number] ?? 0) + 1;
    used[number] = repeat;
    numbers.add(number);
    names.add('${rules[number - 1].name}${repeat == 1 ? '' : '_$repeat'}');
  }
  return (numbers, names);
}

List<List<int>> rfmScores(List<Customer> customers) => [for (final customer in customers)
  [for (final rank in [customers.where((other) => other.recency > customer.recency).length,
    customers.where((other) => other.frequency < customer.frequency).length,
    customers.where((other) => other.spend < customer.spend).length]) 1 + 5 * rank ~/ customers.length]];

double gini(List<int> spends) {
  final ordered = spends.toList()..sort();
  var total = 0, weighted = 0;
  for (var index = 0; index < ordered.length; index++) {
    total += ordered[index];
    weighted += (index + 1) * ordered[index];
  }
  return (2 * weighted - (ordered.length + 1) * total) / (ordered.length * total);
}

double lowerMedian(List<double> values) => (values.toList()..sort())[(values.length - 1) ~/ 2];
List<String> traits(List<double> center) {
  final order = List.generate(center.length, (index) => index)..sort((first, second) {
    final compared = center[second].abs().compareTo(center[first].abs());
    return compared != 0 ? compared : first.compareTo(second);
  });
  return [for (final feature in order.take(2)) '${center[feature] > 0 ? 'high_' : 'low_'}${featureNames[feature]}'];
}
Map<String, int> categoryTotals(List<Customer> customers) {
  final totals = <String, int>{};
  for (final customer in customers) {
    for (final entry in customer.categorySpend.entries) {
      totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
    }
  }
  return totals;
}
List<String> categoryRanking(Map<String, int> totals) => totals.keys.where((name) => totals[name]! > 0).toList()..sort((first, second) {
  final compared = totals[second]!.compareTo(totals[first]!);
  return compared != 0 ? compared : first.compareTo(second);
});
String yesNo(bool flag) => flag ? 'yes' : 'no';
String integers(List<int> values) => values.join(' ');
List<String> joinBlocks(List<List<String>> blocks) => [for (var index = 0; index < blocks.length; index++)
  ...[if (index > 0) '', ...blocks[index]]];

class Analysis {
  final Params params;
  final TransactionData data;
  final List<Rule> rules;
  final Minstd generator;
  final List<Order> referenceOrders;
  final Map<String, List<Order>> customerOrders;
  final List<Customer> customers;
  final Map<String, int> numbers;
  final List<double> means, sds;
  final List<List<double>> points;
  final candidates = <Candidate>[];
  final votes = <(String, int)>[];
  late Candidate finalCandidate;
  late int finalVotes, k, totalSpend;
  late List<int> labels;
  late List<List<double>> centers;
  late List<String> names, codes, categoryNames;
  late List<double> silhouettes;
  final distances = <double>[], others = <(int, double)>[];
  late List<List<int>> scores;
  late Map<String, int> overallCategories;
  final segmentCustomers = <List<Customer>>[];
  final segmentSpends = <int>[], segmentCategories = <Map<String, int>>[];
  final rankings = <List<String>>[], segmentSSE = <double>[];
  late List<List<double>> jaccards;
  Analysis._(this.params, this.data, this.rules, this.generator, this.referenceOrders,
      this.customerOrders, this.customers, this.numbers, this.means, this.sds, this.points);
  factory Analysis(Params params, TransactionData data, List<Rule> rules) {
    final orders = groupOrders(data.validRows, 1, params.referenceDay);
    final customers = eligibleCustomers(orders, params.referenceDay);
    final transformed = [for (final customer in customers) customer.transformed()];
    final (means, sds) = standardization(transformed);
    return Analysis._(params, data, rules, Minstd(params.seed), orders, ordersByCustomer(orders), customers,
        {for (var index = 0; index < customers.length; index++) customers[index].id: index}, means, sds,
        [for (final values in transformed) standardize(values, means, sds)]);
  }
  String ids(List<int> numbers) => numbers.map((number) => customers[number].id).join(' ');
  Candidate candidate(int k) => candidates[k - params.kMin];

  Candidate search(int k) {
    final runs = <Run>[], bests = <Run>[];
    for (final method in params.methods) {
      final methodRuns = <Run>[];
      for (var number = 1; number <= params.restarts; number++) {
        final seeds = initialSeeds(method, points, k, number, generator);
        methodRuns.add(Run(method, number, seeds, points, params.maxIterations));
      }
      runs.addAll(methodRuns);
      bests.add(bestRun(methodRuns));
    }
    final best = bestRun(bests);
    return Candidate(k, runs, bests, best, Solution(points, best.improved.labels, k));
  }

  void evaluate() {
    final table = validation.distanceTable(points), first = candidates.first.solution.sseValue, last = candidates.last.solution.sseValue;
    for (var position = 0; position < candidates.length; position++) {
      final item = candidates[position], solution = candidates[position].solution;
      item.silhouettes = validation.silhouettes(table, solution.labels, solution.sizes);
      item.silhouette = mean(item.silhouettes);
      item.calinskiHarabasz = validation.calinskiHarabasz(points, solution.centers, solution.sizes, solution.sseValue);
      item.daviesBouldin = validation.daviesBouldin(points, solution.labels, solution.centers, solution.sizes);
      item.elbow = validation.elbow(item.k, params.kMin, params.kMax, solution.sseValue, first, last);
      if (item.k < params.kMax) item.hartigan = validation.hartigan(solution.sseValue, candidates[position + 1].solution.sseValue, points.length, item.k);
      final (ruleNumbers, names) = segmentNames(rules, solution.centers);
      item.ruleNumbers = ruleNumbers;
      item.names = names;
    }
  }

  void chooseK() {
    final functions = <double Function(Candidate)>[(item) => item.elbow, (item) => item.silhouette,
      (item) => item.calinskiHarabasz, (item) => -item.daviesBouldin];
    const criteria = ['elbow', 'silhouette', 'calinski_harabasz', 'davies_bouldin'];
    final counts = <int, int>{};
    for (var column = 0; column < functions.length; column++) {
      final options = column == 0 ? candidates.sublist(1, candidates.length - 1) : candidates;
      var best = options.first;
      for (final item in options.skip(1)) {
        if (fourDecimal(functions[column](item)) > fourDecimal(functions[column](best))) best = item;
      }
      votes.add((criteria[column], best.k));
      counts[best.k] = (counts[best.k] ?? 0) + 1;
    }
    var chosen = params.kMax;
    for (final item in candidates) {
      if (item.hartigan != null && item.hartigan! <= 10) { chosen = item.k; break; }
    }
    votes.add(('hartigan', chosen));
    counts[chosen] = (counts[chosen] ?? 0) + 1;
    finalCandidate = candidates.first;
    for (final item in candidates.skip(1)) {
      final first = counts[item.k] ?? 0, second = counts[finalCandidate.k] ?? 0;
      if (first > second || first == second && fourDecimal(item.silhouette) > fourDecimal(finalCandidate.silhouette)) finalCandidate = item;
    }
    finalVotes = counts[finalCandidate.k] ?? 0;
  }

  void describeFinal() {
    final solution = finalCandidate.solution;
    k = solution.k;
    labels = solution.labels;
    centers = solution.centers;
    names = finalCandidate.names;
    silhouettes = finalCandidate.silhouettes;
    for (var index = 0; index < points.length; index++) {
      final point = points[index], label = labels[index];
      var other = -1, best = 0.0;
      for (var cluster = 0; cluster < k; cluster++) {
        if (cluster == label) continue;
        final distance = squaredDistance(point, centers[cluster]);
        if (other < 0 || distance < best) { other = cluster; best = distance; }
      }
      distances.add(math.sqrt(squaredDistance(point, centers[label])));
      others.add((other, math.sqrt(best)));
    }
    scores = rfmScores(customers);
    codes = scores.map((score) => score.join()).toList();
    totalSpend = customers.fold(0, (total, customer) => total + customer.spend);
    overallCategories = categoryTotals(customers);
    categoryNames = overallCategories.keys.toList()..sort();
    for (var segment = 0; segment < k; segment++) {
      final members = solution.members[segment], selected = [for (final number in solution.members[segment]) customers[number]];
      segmentCustomers.add(selected);
      segmentSpends.add(selected.fold(0, (total, customer) => total + customer.spend));
      final categories = categoryTotals(selected);
      segmentCategories.add(categories);
      rankings.add(categoryRanking(categories));
      segmentSSE.add(orderedSum(members.map((number) => squaredDistance(points[number], centers[segment]))));
    }
  }

  void analyze() {
    for (var k = params.kMin; k <= params.kMax; k++) {
      candidates.add(search(k));
    }
    evaluate();
    chooseK();
    describeFinal();
    jaccards = subsampleJaccards();
  }

  String recommendation(int number) {
    for (final category in rankings[labels[number]]) {
      if ((customers[number].categorySpend[category] ?? 0) <= 0) return category;
    }
    return '-';
  }

  List<List<double>> subsampleJaccards() {
    final n = points.length, size = points.length * params.subsamplePercent ~/ 100;
    final jaccards = List.generate(k, (_) => <double>[]);
    for (var repeat = 0; repeat < params.subsamples; repeat++) {
      final order = List.generate(n, (index) => index);
      for (var position = 0; position < size; position++) {
        final other = position + generator.draw() % (n - position), saved = order[position];
        order[position] = order[other];
        order[other] = saved;
      }
      final sample = order.sublist(0, size)..sort();
      final result = lloyd([for (final number in sample) points[number]], centers, params.maxIterations);
      for (var segment = 0; segment < k; segment++) {
        var best = 0.0;
        for (var cluster = 0; cluster < k; cluster++) {
          var both = 0, either = 0;
          for (var index = 0; index < sample.length; index++) {
            final member = labels[sample[index]] == segment, actual = result.labels[index] == cluster;
            if (member && actual) both++;
            if (member || actual) either++;
          }
          if (either > 0) best = math.max(best, both / either);
        }
        jaccards[segment].add(best);
      }
    }
    return jaccards;
  }

  List<String> featuresLines() => ['customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure',
    for (var index = 0; index < customers.length; index++)
      [customers[index].id, customers[index].recency, customers[index].frequency,
        amount(customers[index].spend), realText(customers[index].basket),
        customers[index].categories, customers[index].tenure, ...points[index].map(realText)].join(',')];
  String runLine(Run run) => 'run ${run.method} ${run.number} seeds ${ids(run.seeds)} iterations ${run.result.iterations} converged ${yesNo(run.result.converged)} reseeds ${run.result.reseeds} sse ${realText(run.lloydSSE)} passes ${run.improved.passes} transfers ${run.improved.transfers} refined ${realText(run.improved.sseValue)}';
  String runSummary(Run run) => '${run.method} restart ${run.number} sse ${realText(run.improved.sseValue)}';
  List<String> runsLines() => joinBlocks([for (final item in candidates)
    ['k ${item.k}', ...item.runs.map(runLine), for (final run in item.methodBests) 'best ${runSummary(run)}',
      'chosen ${runSummary(item.best)}', 'sizes ${integers(item.solution.sizes)}']]);

  String stabilityLine(int position, Candidate item) {
    final parts = ['k=${item.k}'], bests = item.methodBests;
    for (var first = 0; first < bests.length; first++) {
      for (var second = first + 1; second < bests.length; second++) {
        parts.addAll(['${bests[first].method}:${bests[second].method}', realText(validation.adjustedRand(bests[first].improved.labels, bests[second].improved.labels))]);
      }
    }
    parts.add('final');
    for (final run in bests) {
      parts.addAll([run.method, realText(validation.adjustedRand(run.improved.labels, item.solution.labels))]);
    }
    parts.addAll(['next', position + 1 < candidates.length ? realText(validation.adjustedRand(item.solution.labels, candidates[position + 1].solution.labels)) : '-']);
    return parts.join(' ');
  }

  List<String> selectionLines() {
    final indices = ['indices'], voteLines = ['votes'], nameLines = ['segments'], stability = ['stability'];
    for (var position = 0; position < candidates.length; position++) {
      final item = candidates[position];
      final h = item.hartigan == null ? '-' : realText(item.hartigan!);
      indices.add('k=${item.k} sse ${realText(item.solution.sseValue)} elbow ${realText(item.elbow)} silhouette ${realText(item.silhouette)} calinski_harabasz ${realText(item.calinskiHarabasz)} davies_bouldin ${realText(item.daviesBouldin)} hartigan $h');
      nameLines.add(['k=${item.k}', for (var segment = 0; segment < item.k; segment++) '${item.names[segment]}:${item.solution.sizes[segment]}'].join(' '));
      stability.add(stabilityLine(position, item));
    }
    voteLines.addAll([for (final (criterion, k) in votes) '$criterion k=$k']);
    voteLines.add('chosen k=${finalCandidate.k} votes $finalVotes');
    return joinBlocks([indices, voteLines, nameLines, stability]);
  }

  List<String> segmentsLines() => ['customer,segment,name,distance,other,other_distance,silhouette,recommend',
    for (var index = 0; index < customers.length; index++) [customers[index].id, labels[index] + 1,
      names[labels[index]], realText(distances[index]), others[index].$1 + 1,
      realText(others[index].$2), realText(silhouettes[index]), recommendation(index)].join(',')];

  String medianLine(List<Customer> selected) {
    final medians = [for (var feature = 0; feature < 6; feature++) lowerMedian([
      for (final customer in selected) feature == 2 ? customer.spend.toDouble() : customer.values()[feature]])];
    return '  median recency ${medians[0].toInt()} frequency ${medians[1].toInt()} monetary ${amount(medians[2].toInt())} basket ${realText(medians[3])} categories ${medians[4].toInt()} tenure ${medians[5].toInt()}';
  }

  String related(List<int> members, int k) {
    if (k < params.kMin || k > params.kMax) return 'k=$k -';
    final counts = List.filled(k, 0), labels = candidate(k).solution.labels;
    for (final number in members) {
      counts[labels[number]]++;
    }
    var best = 0;
    for (var cluster = 1; cluster < k; cluster++) {
      if (counts[cluster] > counts[best]) best = cluster;
    }
    return 'k=$k segment ${best + 1} shared ${counts[best]}';
  }

  String cadenceLine(List<Customer> selected) {
    final gaps = <double>[];
    var overdue = 0;
    for (final customer in selected) {
      if (customer.frequency < 2) continue;
      final active = customer.tenure - customer.recency, intervals = customer.frequency - 1;
      gaps.add(active / intervals);
      if (customer.recency * intervals > params.overdueFactor * active) overdue++;
    }
    return '  cadence customers ${gaps.length} mean_gap ${gaps.isEmpty ? '-' : realText(mean(gaps))} overdue $overdue';
  }

  String orderSizesLine(List<Customer> selected) {
    final bins = List.filled(params.orderBins.length + 1, 0);
    for (final customer in selected) {
      for (final order in customer.orders) {
        bins[params.orderBins.where((bound) => order.net >= bound * 100).length]++;
      }
    }
    return '  order_sizes ${integers(bins)}';
  }

  String returnsLine(List<Customer> selected) {
    var gross = 0, returned = 0, cancelled = 0;
    for (final customer in selected) {
      for (final order in customerOrders[customer.id]!) {
        if (order.net <= 0) cancelled++;
        for (final row in order.rows) {
          if (row.amount > 0) gross += row.amount;
          else returned -= row.amount;
        }
      }
    }
    return '  returns rate ${realText(returned / gross)} returned ${amount(returned)} cancelled $cancelled';
  }

  String rfmLine(List<int> members) {
    final totals = List.filled(3, 0.0), counts = <String, int>{};
    for (final number in members) {
      for (var part = 0; part < 3; part++) {
        totals[part] += scores[number][part];
      }
      counts[codes[number]] = (counts[codes[number]] ?? 0) + 1;
    }
    final order = counts.keys.toList()..sort((first, second) {
      final compared = counts[second]!.compareTo(counts[first]!);
      return compared != 0 ? compared : first.compareTo(second);
    });
    final mode = order.first, means = totals.map((value) => value / members.length).toList();
    return '  rfm r ${realText(means[0])} f ${realText(means[1])} m ${realText(means[2])} mode $mode ${counts[mode]}';
  }

  String categoriesLine(int segment) {
    final parts = ['  categories'];
    for (final category in rankings[segment].take(params.topCategories)) {
      final share = segmentCategories[segment][category]! / segmentSpends[segment];
      final lift = share / (overallCategories[category]! / totalSpend);
      parts.addAll([category, realText(share), realText(lift)]);
    }
    return parts.join(' ');
  }

  String outliersLine(List<int> members) {
    final outliers = <String>[];
    if (members.length >= 2) {
      final selected = [for (final number in members) distances[number]];
      final limit = mean(selected) + params.outlierSD * sampleSD(selected);
      for (final number in members) {
        if (distances[number] > limit) outliers.add(customers[number].id);
      }
    }
    return ['  outliers', '${outliers.length}', ...outliers].join(' ');
  }

  List<String> segmentProfile(int segment) {
    final members = finalCandidate.solution.members[segment], selected = segmentCustomers[segment];
    final size = members.length, center = centers[segment], spend = segmentSpends[segment];
    final values = originalScale(center, means, sds);
    final top = members.toList()..sort((first, second) {
      final compared = customers[second].spend.compareTo(customers[first].spend);
      return compared != 0 ? compared : first.compareTo(second);
    });
    final selectedSilhouettes = [for (final number in members) silhouettes[number]];
    return ['segment ${segment + 1} ${names[segment]} rule ${finalCandidate.ruleNumbers[segment]} size $size share ${realText(size / customers.length)} revenue ${amount(spend)} revenue_share ${realText(spend / totalSpend)}',
      '  center ${reals(center)}', '  value ${[for (var feature = 0; feature < 6; feature++) '${featureNames[feature]} ${realText(values[feature])}'].join(' ')}',
      '  traits ${traits(center).join(' ')}', medianLine(selected), '  related ${related(members, k - 1)} ${related(members, k + 1)}',
      '  top_customers ${[for (final number in top.take(params.topCustomers)) '${customers[number].id} ${amount(customers[number].spend)}'].join(' ')}',
      cadenceLine(selected), orderSizesLine(selected), '  sse ${realText(segmentSSE[segment])} share ${realText(segmentSSE[segment] / finalCandidate.solution.sseValue)}',
      '  gini ${realText(gini([for (final customer in selected) customer.spend]))}', returnsLine(selected),
      '  silhouette ${realText(mean(selectedSilhouettes))} negative ${selectedSilhouettes.where((value) => value < 0).length}',
      rfmLine(members), categoriesLine(segment), outliersLine(members)];
  }

  String segmentNumbers() => List.generate(k, (index) => index + 1).join(' ');
  List<String> categoryMixLines() => ['category_mix ${segmentNumbers()}', for (final category in categoryNames)
    '$category ${reals([for (var segment = 0; segment < k; segment++) (segmentCategories[segment][category] ?? 0) / segmentSpends[segment]])}'];
  List<String> recencyTableLines() => ['rfm_recency ${segmentNumbers()}', for (final score in [5, 4, 3, 2, 1])
    'r=$score ${[for (var segment = 0; segment < k; segment++) finalCandidate.solution.members[segment].where((number) => scores[number][0] == score).length].join(' ')}',
    'ari rfm_codes ${realText(validation.adjustedRand(codes, labels))}'];
  List<String> centerDistanceLines() => ['center_distances', for (var segment = 0; segment < k; segment++)
    '${segment + 1} ${reals([for (final other in centers) math.sqrt(squaredDistance(centers[segment], other))])}'];
  List<String> profilesLines() => joinBlocks([
    ['segments k=$k customers ${customers.length} revenue ${amount(totalSpend)} gini ${realText(gini(customers.map((customer) => customer.spend).toList()))}'],
    for (var segment = 0; segment < k; segment++) segmentProfile(segment), categoryMixLines(), recencyTableLines(), centerDistanceLines()]);

  List<String> subsampleLines() => ['subsamples ${params.subsamples} size ${customers.length * params.subsamplePercent ~/ 100}',
    for (var segment = 0; segment < k; segment++)
      'segment ${segment + 1} ${names[segment]} mean_jaccard ${realText(mean(jaccards[segment]))} min_jaccard ${realText(jaccards[segment].reduce(math.min))}'];
  List<String> ablationLines() {
    final lines = ['ablation'];
    for (var feature = 0; feature < 6; feature++) {
      final reduced = [for (final point in points) [...point.take(feature), ...point.skip(feature + 1)]];
      final seeds = maximin(reduced, k, 1);
      final run = Run('maximin', 1, seeds, reduced, params.maxIterations);
      lines.add('without ${featureNames[feature]} seeds ${ids(seeds)} iterations ${run.result.iterations} converged ${yesNo(run.result.converged)} transfers ${run.improved.transfers} sse ${realText(run.improved.sseValue)} ari ${realText(validation.adjustedRand(run.improved.labels, labels))}');
    }
    return lines;
  }
  List<String> drilldownLines() {
    final members = finalCandidate.solution.members.first;
    final selected = [for (final number in members) points[number]];
    final seeds = maximin(selected, 2, 1);
    final run = Run('maximin', 1, seeds, selected, params.maxIterations), before = segmentSSE.first;
    final parts = Solution(selected, run.improved.labels, 2), after = run.improved.sseValue;
    return ['drilldown segment 1 ${names.first} size ${members.length} seeds ${ids([for (final seed in seeds) members[seed]])} iterations ${run.result.iterations} converged ${yesNo(run.result.converged)} transfers ${run.improved.transfers}',
      'sse before ${realText(before)} after ${realText(after)} gain ${realText(before - after)}',
      for (var part = 0; part < 2; part++) 'part ${part + 1} size ${parts.sizes[part]} center ${reals(parts.centers[part])}'];
  }
  List<String> robustnessLines() => joinBlocks([subsampleLines(), ablationLines(), drilldownLines()]);

  List<String> periodLines() {
    final lines = ['periods ${params.periods} days ${params.periodDays}'];
    for (var period = 1; period <= params.periods; period++) {
      final first = params.referenceDay - period * params.periodDays + 1, last = params.referenceDay - (period - 1) * params.periodDays;
      final revenue = List.filled(k, 0), active = List.filled(k, 0), acquired = List.filled(k, 0);
      for (var number = 0; number < customers.length; number++) {
        final customer = customers[number], label = labels[number];
        final orders = customer.orders.where((order) => first <= order.day && order.day <= last).toList();
        if (orders.isNotEmpty) {
          revenue[label] += orders.fold(0, (total, order) => total + order.net);
          active[label]++;
        }
        final day = params.referenceDay - customer.tenure;
        if (first <= day && day <= last) acquired[label]++;
      }
      lines.add('period $period days $first $last revenue ${revenue.map(amount).join(' ')} active ${integers(active)} acquired ${integers(acquired)}');
    }
    return lines;
  }

  List<String> migrationLines() {
    final day = params.snapshotDay, previous = <String, int>{};
    final snapshot = eligibleCustomers(groupOrders(data.validRows, 1, day), day);
    for (final customer in snapshot) {
      final point = standardize(customer.transformed(), means, sds);
      previous[customer.id] = assign([point], centers).$1.first;
    }
    final table = List.generate(k + 1, (_) => List.filled(k, 0)), moved = <String>[];
    var stayed = 0, fresh = 0;
    for (var number = 0; number < customers.length; number++) {
      final customer = customers[number], label = labels[number], origin = previous[customers[number].id] ?? k;
      table[origin][label]++;
      if (origin == k) fresh++;
      else if (origin == label) stayed++;
      else moved.add('${customer.id} ${origin + 1} ${label + 1}');
    }
    final lost = previous.keys.where((id) => !numbers.containsKey(id)).length;
    return ['migration day $day customers ${snapshot.length}', 'from\\to ${segmentNumbers()}',
      for (var origin = 0; origin <= k; origin++) '${origin == k ? 'none' : origin + 1} ${integers(table[origin])}',
      'moved_customers', ...moved, 'stayed $stayed moved ${moved.length} new $fresh lost $lost'];
  }

  List<String> outcomeLines() {
    final first = params.referenceDay + 1, last = params.referenceDay + params.outcomeDays;
    final purchases = <String, int>{};
    for (final order in groupOrders(data.validRows, first, last)) {
      if (order.net > 0) purchases[order.customer] = (purchases[order.customer] ?? 0) + order.net;
    }
    final lines = ['outcome days $first $last'];
    for (var segment = 0; segment < k; segment++) {
      final selected = segmentCustomers[segment];
      var buyers = 0, spend = 0;
      for (final customer in selected) {
        if (purchases.containsKey(customer.id)) { buyers++; spend += purchases[customer.id]!; }
      }
      lines.add('segment ${segment + 1} ${names[segment]} size ${selected.length} buyers $buyers rate ${realText(buyers / selected.length)} revenue ${amount(spend)} per_customer ${realText((spend / 100) / selected.length)}');
    }
    final outside = purchases.keys.where((id) => !numbers.containsKey(id)).toList();
    final spend = outside.fold(0, (total, id) => total + purchases[id]!);
    lines.add('unsegmented buyers ${outside.length} revenue ${amount(spend)}');
    return lines;
  }
  List<String> trackingLines() => joinBlocks([periodLines(), migrationLines(), outcomeLines()]);

  List<String> dataLines() {
    final used = data.validRows.where((row) => row.day <= params.referenceDay).toList();
    final valid = referenceOrders.where((order) => order.net > 0).length;
    final excluded = data.customers.where((id) => !numbers.containsKey(id)).toList()..sort();
    return ['rows ${data.rowCount} duplicates ${data.duplicates} zero ${data.free} used ${used.length} returns ${used.where((row) => row.amount < 0).length} later ${data.validRows.length - used.length}',
      'orders ${referenceOrders.length} valid $valid cancelled ${referenceOrders.length - valid}',
      'customers ${data.customers.length} clustered ${customers.length} excluded ${excluded.length}',
      'excluded_ids ${excluded.isEmpty ? '-' : excluded.join(' ')}'];
  }
  List<String> categoryLines() => [for (final category in categoryNames)
    'category $category revenue ${amount(overallCategories[category]!)} share ${realText(overallCategories[category]! / totalSpend)} customers ${customers.where((customer) => (customer.categorySpend[category] ?? 0) > 0).length}'];
  List<String> featureSummaryLines() => [for (var feature = 0; feature < 6; feature++)
    'feature ${featureNames[feature]} transform ${sqrtFeatures[feature] ? 'sqrt' : 'none'} raw_mean ${realText(mean([for (final customer in customers) customer.values()[feature]]))} raw_sd ${realText(sampleSD([for (final customer in customers) customer.values()[feature]]))} mean ${realText(means[feature])} sd ${realText(sds[feature])}'];
  List<String> correlationLines() => ['correlation ${featureNames.join(' ')}', for (var first = 0; first < 6; first++)
    '${featureNames[first]} ${reals([for (var second = 0; second < 6; second++) correlation(points, first, second)])}'];
  List<String> summaryLines() => joinBlocks([dataLines(), categoryLines(), featureSummaryLines(), correlationLines()]);
}

void main() {
  final analysis = Analysis(readParams(), readTransactions(), readRules())..analyze();
  Directory('output').createSync(recursive: true);
  final files = {'features.csv': analysis.featuresLines(), 'runs.txt': analysis.runsLines(),
    'selection.txt': analysis.selectionLines(), 'segments.csv': analysis.segmentsLines(),
    'profiles.txt': analysis.profilesLines(), 'robustness.txt': analysis.robustnessLines(),
    'tracking.txt': analysis.trackingLines(), 'summary.txt': analysis.summaryLines()};
  for (final entry in files.entries) {
    writeLines(entry.key, entry.value);
  }
}
