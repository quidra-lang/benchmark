import 'dart:io';
import 'dart:math' as math;
import 'dataset.dart';
import 'impurity.dart';
import 'tree_builder.dart';
import 'pruning.dart';
import 'evaluation.dart';

class Minstd {
  int state;
  Minstd(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }
}

List<String> joinSections(List<List<String>> sections) {
  final lines = <String>[];
  for (var index = 0; index < sections.length; index++) {
    if (index > 0) lines.add('');
    lines.addAll(sections[index]);
  }
  return lines;
}

String directionText(bool left) => left ? 'left' : 'right';

class Condition {
  final Attribute attribute;
  int? lower, upper, equal;
  final excluded = <int>{};
  Condition(this.attribute);

  String get text {
    final name = attribute.name;
    if (attribute.integer) {
      if (lower != null && upper != null) return '${halfText(lower!)} < $name <= ${halfText(upper!)}';
      if (lower != null) return '$name > ${halfText(lower!)}';
      return '$name <= ${halfText(upper!)}';
    }
    if (equal != null) return '$name = ${attribute.values[equal!]}';
    final values = excluded.toList()..sort();
    final names = values.map((value) => attribute.values[value]).toList();
    return names.length == 1 ? '$name != ${names.first}' : '$name not in {${names.join(',')}}';
  }

  bool holds(Row row) {
    final value = row.values[attribute.index];
    if (value == null) return false;
    if (attribute.integer) return (lower == null || 2 * value > lower!) && (upper == null || 2 * value <= upper!);
    return equal != null ? value == equal : !excluded.contains(value);
  }
}

List<Condition> simplify(List<(Split, bool)> steps, List<Attribute> attributes) {
  final conditions = <Condition>[];
  for (final attribute in attributes) {
    final related = steps.where((step) => step.$1.attribute.index == attribute.index).toList();
    if (related.isEmpty) continue;
    final condition = Condition(attribute);
    for (final (split, left) in related) {
      if (attribute.integer) {
        if (left) { condition.upper = condition.upper == null ? split.point : math.min(condition.upper!, split.point); }
        else { condition.lower = condition.lower == null ? split.point : math.max(condition.lower!, split.point); }
      } else if (left) { condition.equal = split.point; }
      else { condition.excluded.add(split.point); }
    }
    conditions.add(condition);
  }
  return conditions;
}

String conditionsText(List<Condition> conditions) => conditions.isEmpty ? 'true' : conditions.map((condition) => condition.text).join(' and ');

(int, int) coverage(List<Condition> conditions, List<Row> rows, int label) {
  var hits = 0, covered = 0;
  for (final row in rows) {
    if (!conditions.every((condition) => condition.holds(row))) continue;
    covered++;
    if (row.label == label) hits++;
  }
  return (hits, covered);
}

Fraction laplace(List<Condition> conditions, List<Row> rows, int label, int classes) {
  final (hits, covered) = coverage(conditions, rows, label);
  return (hits + 1, covered + classes);
}

List<Condition> omitCondition(List<Condition> conditions, int index) => [...conditions.take(index), ...conditions.skip(index + 1)];

(List<Condition>, List<String>) generalize(List<Condition> conditions, List<Row> rows, int label, int classes) {
  var current = conditions.toList();
  final removed = <String>[];
  while (current.isNotEmpty) {
    final estimate = laplace(current, rows, label, classes);
    var bestIndex = 0;
    Fraction? best;
    for (var index = 0; index < current.length; index++) {
      final value = laplace(omitCondition(current, index), rows, label, classes);
      if (best == null || compareFractions(value, best) > 0) { bestIndex = index; best = value; }
    }
    if (compareFractions(estimate, best!) > 0) break;
    removed.add(current[bestIndex].attribute.name);
    current = omitCondition(current, bestIndex);
  }
  return (current, removed);
}

class Rule {
  final int number;
  final Node leaf;
  final List<Condition> conditions, general;
  final List<String> removed;
  Rule(this.number, this.leaf, this.conditions, this.general, this.removed);
}

class DepthResult {
  final int depth;
  final Tree tree;
  final int correct;
  DepthResult(this.depth, this.tree, this.correct);
}

class Bag {
  final Tree tree;
  final int distinct, outOfBag, correct;
  Bag(this.tree, this.distinct, this.outOfBag, this.correct);
}

class Permutation {
  final Attribute attribute;
  final List<int> counts;
  final int drop;
  Permutation(this.attribute, this.counts, this.drop);
}

Tree limited(Tree tree, int depth) => Tree(tree.root, {for (final node in tree.internal) if (node.depth == depth) node.number});

class Analysis {
  final Dataset data;
  late final TreeBuilder builder;
  late final Tree grown, pruned;
  late final List<Decision> decisions;
  final rules = <Rule>[];
  final bounds = <int>[];
  final foldTrees = <Tree>[];
  final depths = <DepthResult>[];
  var selectedDepth = 0, selectedIndex = 0;
  late final List<SequenceTree> sequence;
  final bags = <Bag>[];
  late final List<List<int>> oobVotes, testVotes;
  final predictions = <String, List<int>>{};

  Analysis(this.data) {
    builder = TreeBuilder(data.attributes, data.classes.length, data.settings);
    grown = Tree(builder.grow(data.train));
    final pruning = reducedErrorPruning(grown.root, data.validation);
    pruned = pruning.$1;
    decisions = pruning.$2;
    buildRules();
    for (var fold = 0; fold <= data.settings.folds; fold++) { bounds.add(fold * data.train.length ~/ data.settings.folds); }
    for (var fold = 1; fold <= data.settings.folds; fold++) {
      final training = [...data.train.take(bounds[fold - 1]), ...data.train.skip(bounds[fold])];
      foldTrees.add(Tree(builder.grow(training)));
    }
    for (var depth = 0; depth <= data.settings.maxDepth; depth++) {
      var correct = 0;
      for (var index = 0; index < foldTrees.length; index++) { correct += limited(foldTrees[index], depth).correct(foldRows(index + 1)); }
      depths.add(DepthResult(depth, limited(grown, depth), correct));
      if (correct > depths[selectedDepth].correct) selectedDepth = depth;
    }
    sequence = costComplexitySequence(grown.root);
    for (var index = 0; index < sequence.length; index++) {
      if (validationErrors(sequence[index].tree) <= validationErrors(sequence[selectedIndex].tree)) selectedIndex = index;
    }
    bagging();
    testVotes = List.generate(data.test.length, (index) {
      final votes = List.filled(data.classes.length, 0);
      for (final bag in bags) { votes[bag.tree.predict(data.test[index])]++; }
      return votes;
    });
    final models = {'grown': grown, 'pruned': pruned, 'depth': depths[selectedDepth].tree, 'cost_complexity': sequence[selectedIndex].tree};
    for (final entry in models.entries) { predictions[entry.key] = data.test.map(entry.value.predict).toList(); }
    predictions['bagging'] = testVotes.map(majority).toList();
  }

  List<Row> foldRows(int fold) => data.train.sublist(bounds[fold - 1], bounds[fold]);
  int validationErrors(Tree tree) => data.validation.length - tree.correct(data.validation);
  String accuracy(Tree tree, List<Row> rows) => ratioText(tree.correct(rows), rows.length);

  void buildRules() {
    void collect(Node node, List<(Split, bool)> steps) {
      if (pruned.isLeaf(node)) {
        final conditions = simplify(steps, data.attributes);
        final (general, removed) = generalize(conditions, data.validation, node.stats.majority, data.classes.length);
        rules.add(Rule(rules.length + 1, node, conditions, general, removed));
      } else {
        collect(node.left!, [...steps, (node.split!, true)]);
        collect(node.right!, [...steps, (node.split!, false)]);
      }
    }
    collect(pruned.root, []);
  }

  void bagging() {
    final generator = Minstd(data.settings.bagSeed), size = data.train.length;
    oobVotes = List.generate(size, (_) => List.filled(data.classes.length, 0));
    for (var bag = 0; bag < data.settings.bagTrees; bag++) {
      final sample = <Row>[], seen = <int>{};
      for (var draw = 0; draw < size; draw++) {
        final index = generator.draw() % size;
        sample.add(data.train[index]);
        seen.add(index);
      }
      final tree = Tree(builder.grow(sample));
      var outside = 0, correct = 0;
      for (var index = 0; index < size; index++) {
        if (seen.contains(index)) continue;
        outside++;
        final prediction = tree.predict(data.train[index]);
        oobVotes[index][prediction]++;
        if (prediction == data.train[index].label) correct++;
      }
      bags.add(Bag(tree, seen.length, outside, correct));
    }
  }

  List<String> treeLines(Tree tree) {
    final lines = <String>[];
    void visit(Node node, String condition) {
      final indent = List.filled(node.depth, '  ').join();
      final line = '$indent${node.number} $condition n ${node.stats.size} counts ${node.stats.counts.join(' ')}';
      if (tree.isLeaf(node)) { lines.add('$line leaf ${data.classes[node.stats.majority]}'); return; }
      lines.add(line);
      visit(node.left!, node.split!.condition(true));
      visit(node.right!, node.split!.condition(false));
    }
    visit(tree.root, 'root');
    final nodes = tree.preorder();
    lines.addAll(['', 'nodes ${nodes.length} leaves ${tree.leaves.length} depth ${tree.depth} errors ${ratioText(tree.trainingErrors, data.train.length)}']);
    for (var level = 0; level <= tree.depth; level++) {
      final atLevel = nodes.where((node) => node.depth == level).toList();
      final leaves = atLevel.where(tree.isLeaf).toList();
      lines.add('level $level nodes ${atLevel.length} leaves ${leaves.length} rows ${sum(leaves.map((node) => node.stats.size))} errors ${sum(leaves.map((node) => node.stats.errors))}');
    }
    return lines;
  }

  List<String> rootCandidateLines() {
    final found = <Candidate>[];
    for (final attribute in data.attributes) {
      final candidate = builder.bestForAttribute(data.train, attribute);
      if (candidate != null) found.add(candidate);
    }
    found.sort((a, b) {
      final order = compareFractions(b.value, a.value);
      return order != 0 ? order : a.split.attribute.index.compareTo(b.split.attribute.index);
    });
    final size = data.train.length;
    final lines = ['root candidates n $size counts ${grown.root.stats.counts.join(' ')}'];
    for (var index = 0; index < found.length; index++) {
      final candidate = found[index];
      final gain = candidate.value.$1 / candidate.value.$2 / size - grown.root.stats.squares / (size * size);
      lines.add('${index + 1} ${candidate.split.condition(true)} left ${candidate.left.length} right ${candidate.right.length} gain ${realText(gain, 6)}');
    }
    return lines;
  }

  List<String> surrogateLines() {
    final lines = ['surrogates'];
    for (final node in grown.internal) {
      final parts = [for (final surrogate in node.surrogates) '${surrogate.split.condition(true)} ${directionText(surrogate.left)} ${surrogate.score}/${node.stats.size}'];
      lines.add('node ${node.number} split ${node.split!.condition(true)} default ${directionText(node.defaultLeft)} surrogates ${parts.isEmpty ? 'none' : parts.join(' ; ')}');
    }
    return lines;
  }

  List<String> pruningLines() {
    final lines = ['reduced_error_pruning validation ${data.validation.length}'];
    for (final decision in decisions) {
      lines.add('node ${decision.node.number} depth ${decision.node.depth} rows ${decision.rows} leaf ${decision.leafError} subtree ${decision.subtreeError} ${decision.pruned ? 'pruned' : 'kept'}');
    }
    final count = decisions.where((decision) => decision.pruned).length;
    lines.add('examined ${decisions.length} pruned $count kept ${decisions.length - count}');
    return lines;
  }

  List<String> predictionLines() {
    final lines = ['id,predicted,actual,grown,leaf,path,missing'];
    for (final row in data.test) {
      final route = pruned.route(row);
      lines.add([row.id, data.classes[route.leaf.stats.majority], data.classes[row.label], data.classes[grown.predict(row)], route.leaf.number, route.path.map((node) => node.number).join('-'), route.steps.where((step) => step.method != 'primary').length].join(','));
    }
    return lines;
  }

  List<String> ruleLines() {
    final lines = ['rules ${rules.length}'];
    for (final rule in rules) {
      final reached = data.test.where((row) => pruned.route(row).leaf.number == rule.leaf.number).toList();
      final label = rule.leaf.stats.majority, hits = reached.where((row) => row.label == rule.leaf.stats.majority).length;
      lines.add('rule ${rule.number} node ${rule.leaf.number} if ${conditionsText(rule.conditions)} then ${data.classes[label]} train ${ratioText(rule.leaf.stats.counts[label], rule.leaf.stats.size)} test ${ratioText(hits, reached.length)}');
    }
    return lines;
  }

  List<String> generalizedLines() {
    final lines = ['generalized ${rules.length}'];
    for (final rule in rules) {
      final label = rule.leaf.stats.majority;
      final (hits, covered) = coverage(rule.general, data.validation, label);
      final (testHits, testCovered) = coverage(rule.general, data.test, label);
      lines.add('general ${rule.number} if ${conditionsText(rule.general)} then ${data.classes[label]} removed ${rule.removed.isEmpty ? 'none' : rule.removed.join(',')} laplace ${fractionText(hits + 1, covered + data.classes.length)} validation $hits/$covered test $testHits/$testCovered');
    }
    return lines;
  }

  List<String> misclassifiedLines() {
    final numbers = {for (final rule in rules) rule.leaf.number: rule.number}, records = <String>[];
    for (final row in data.test) {
      final route = pruned.route(row), label = route.leaf.stats.majority;
      if (label == row.label) continue;
      final parts = [for (final step in route.steps) '${step.node.split!.condition(step.left)}${step.method == 'primary' ? '' : ' [${step.method}]'}'];
      records.add('${row.id} actual ${data.classes[row.label]} predicted ${data.classes[label]} rule ${numbers[route.leaf.number]} path ${parts.isEmpty ? 'root' : parts.join('; ')}');
    }
    return ['misclassified ${records.length}', ...records];
  }
  List<String> dataLines() {
    final trainCounts = statistics(data.train, data.classes.length).counts;
    final validationCounts = statistics(data.validation, data.classes.length).counts;
    final testCounts = statistics(data.test, data.classes.length).counts;
    final lines = ['data train ${data.train.length} validation ${data.validation.length} test ${data.test.length} attributes ${data.attributes.length} classes ${data.classes.length} target ${data.target}'];
    for (var index = 0; index < data.classes.length; index++) {
      lines.add('class ${data.classes[index]} train ${trainCounts[index]} validation ${validationCounts[index]} test ${testCounts[index]}');
    }
    lines.add('missing validation ${sum(data.validation.map((row) => row.missing))} test ${sum(data.test.map((row) => row.missing))}');
    for (final attribute in data.attributes) {
      final validation = data.validation.where((row) => row.values[attribute.index] == null).length;
      final test = data.test.where((row) => row.values[attribute.index] == null).length;
      lines.add('missing ${attribute.name} validation $validation test $test');
    }
    return lines;
  }

  String summaryLine(String name, Tree tree) => '$name nodes ${tree.preorder().length} leaves ${tree.leaves.length} depth ${tree.depth} train ${accuracy(tree, data.train)} validation ${accuracy(tree, data.validation)} test ${accuracy(tree, data.test)}';

  List<String> modelEvaluation(String model) => classificationLines('$model test', data.classes, data.test, predictions[model]!);

  List<String> routingLines() {
    final tally = {for (final node in pruned.internal) node.number: {'primary': 0, 'surrogate': 0, 'default': 0}};
    final complete = <Row>[], incomplete = <Row>[];
    for (final row in data.test) {
      for (final step in pruned.route(row).steps) { tally[step.node.number]![step.method] = tally[step.node.number]![step.method]! + 1; }
      (row.missing == 0 ? complete : incomplete).add(row);
    }
    final lines = ['routing pruned test'];
    for (final node in pruned.internal) {
      final counts = tally[node.number]!;
      lines.add('node ${node.number} rows ${sum(counts.values)} primary ${counts['primary']} surrogate ${counts['surrogate']} default ${counts['default']}');
    }
    lines.add('complete rows ${complete.length} correct ${accuracy(pruned, complete)}');
    lines.add('incomplete rows ${incomplete.length} correct ${accuracy(pruned, incomplete)}');
    return lines;
  }

  List<String> crossValidationLines() {
    final lines = ['cross_validation folds ${data.settings.folds}'];
    var total = 0;
    for (var index = 0; index < foldTrees.length; index++) {
      final rows = foldRows(index + 1), tree = foldTrees[index], correct = tree.correct(rows);
      total += correct;
      lines.add('fold ${index + 1} rows ${bounds[index] + 1}-${bounds[index + 1]} leaves ${tree.leaves.length} correct ${ratioText(correct, rows.length)}');
    }
    lines.add('cv accuracy ${ratioText(total, data.train.length)}');
    return lines;
  }

  List<String> depthLines() {
    final lines = ['depth_selection'];
    for (final result in depths) {
      final tree = result.tree;
      lines.add('depth ${result.depth} leaves ${tree.leaves.length} cv ${ratioText(result.correct, data.train.length)} train ${accuracy(tree, data.train)} validation ${accuracy(tree, data.validation)} test ${accuracy(tree, data.test)}');
    }
    final selected = depths[selectedDepth];
    lines.add('selected depth ${selected.depth} leaves ${selected.tree.leaves.length} test ${accuracy(selected.tree, data.test)}');
    return lines;
  }

  List<String> complexityLines() {
    final lines = ['cost_complexity'];
    for (var index = 0; index < sequence.length; index++) {
      final step = sequence[index];
      final alpha = fractionText(step.alpha.$1, step.alpha.$2 * data.train.length, 6);
      lines.add('subtree $index alpha $alpha leaves ${step.tree.leaves.length} train_errors ${step.tree.trainingErrors} validation_errors ${validationErrors(step.tree)}');
    }
    final selected = sequence[selectedIndex].tree;
    lines.add('selected subtree $selectedIndex leaves ${selected.leaves.length} test ${accuracy(selected, data.test)}');
    return lines;
  }

  List<String> baggingLines() {
    final settings = data.settings;
    final lines = ['bagging trees ${settings.bagTrees} seed ${settings.bagSeed}'];
    for (var index = 0; index < bags.length; index++) {
      final bag = bags[index];
      lines.add('bag ${index + 1} distinct ${bag.distinct} leaves ${bag.tree.leaves.length} oob ${ratioText(bag.correct, bag.outOfBag)}');
    }
    var hits = 0, voted = 0;
    for (var index = 0; index < oobVotes.length; index++) {
      if (sum(oobVotes[index]) == 0) continue;
      voted++;
      if (majority(oobVotes[index]) == data.train[index].label) hits++;
    }
    lines.add('oob accuracy ${ratioText(hits, voted)} unvoted ${data.train.length - voted}');
    lines.addAll(modelEvaluation('bagging'));
    return lines;
  }

  List<String> mcnemarLines() {
    final lines = ['mcnemar pruned test'];
    for (final model in ['grown', 'depth', 'cost_complexity', 'bagging']) {
      var b = 0, c = 0;
      for (var index = 0; index < data.test.length; index++) {
        final first = predictions['pruned']![index] == data.test[index].label;
        final second = predictions[model]![index] == data.test[index].label;
        if (first && !second) b++;
        if (second && !first) c++;
      }
      final difference = math.max(0, (b - c).abs() - 1), numerator = difference * difference;
      final statistic = b + c == 0 ? '0/1 0.0000' : fractionText(numerator, b + c);
      lines.add('versus $model b $b c $c statistic $statistic significant ${1000 * numerator > 3841 * (b + c) ? 'yes' : 'no'}');
    }
    return lines;
  }

  List<List<Fraction>> scores(String model) {
    if (model == 'bagging') return [for (final votes in testVotes) [for (final count in votes) (count, data.settings.bagTrees)]];
    final tree = model == 'grown' ? grown : pruned;
    final scores = <List<Fraction>>[];
    for (final row in data.test) {
      final leaf = tree.route(row).leaf;
      scores.add([for (final count in leaf.stats.counts) (count, leaf.stats.size)]);
    }
    return scores;
  }

  List<String> aucLines() {
    final lines = <String>[];
    for (final model in ['grown', 'pruned', 'bagging']) {
      final values = scores(model), parts = ['auc', model];
      var macro = 0.0, defined = 0;
      for (var label = 0; label < data.classes.length; label++) {
        final positives = <int>[], negatives = <int>[];
        for (var index = 0; index < data.test.length; index++) { (data.test[index].label == label ? positives : negatives).add(index); }
        var wins = 0;
        for (final positive in positives) {
          for (final negative in negatives) {
            final comparison = compareFractions(values[positive][label], values[negative][label]);
            if (comparison > 0) wins += 2;
            else if (comparison == 0) wins++;
          }
        }
        final denominator = 2 * positives.length * negatives.length;
        parts.addAll([data.classes[label], fractionText(wins, denominator)]);
        if (denominator > 0) { macro += wins / denominator; defined++; }
      }
      parts.addAll(['macro', defined == 0 ? '-' : realText(macro / defined)]);
      lines.add(parts.join(' '));
    }
    return lines;
  }

  List<String> learningLines() {
    final lines = ['learning_curve'];
    for (final size in data.settings.curve) {
      final grown = Tree(builder.grow(data.train.take(size).toList()));
      final pruned = reducedErrorPruning(grown.root, data.validation).$1;
      lines.add('size $size grown leaves ${grown.leaves.length} test ${accuracy(grown, data.test)} pruned leaves ${pruned.leaves.length} test ${accuracy(pruned, data.test)}');
    }
    return lines;
  }

  List<String> impurityLines(String title, Tree tree) {
    final importance = List.filled(data.attributes.length, 0.0), splits = List.filled(data.attributes.length, 0);
    for (final node in tree.internal) {
      final index = node.split!.attribute.index;
      importance[index] += impurityDecrease(node.stats, node.left!.stats, node.right!.stats);
      splits[index]++;
    }
    var total = 0.0;
    for (final value in importance) { total += value; }
    final shares = [for (final value in importance) total == 0 ? 0.0 : value / total];
    final rounded = shares.map((value) => double.parse(realText(value))).toList();
    final order = List.generate(importance.length, (index) => index)..sort((a, b) {
      final comparison = rounded[b].compareTo(rounded[a]);
      return comparison != 0 ? comparison : a.compareTo(b);
    });
    return [
      'impurity $title',
      for (var rank = 0; rank < order.length; rank++)
        '${rank + 1} ${data.attributes[order[rank]].name} decrease ${realText(importance[order[rank]] / data.train.length)} share ${realText(shares[order[rank]])} splits ${splits[order[rank]]}',
    ];
  }

  List<String> permutationLines() {
    final generator = Minstd(data.settings.permutationSeed), repeats = data.settings.repeats;
    final size = data.test.length, base = pruned.correct(data.test), results = <Permutation>[];
    for (final attribute in data.attributes) {
      final counts = <int>[];
      for (var repeat = 0; repeat < repeats; repeat++) {
        final values = data.test.map((row) => row.values[attribute.index]).toList();
        for (var position = size; position >= 2; position--) {
          final other = generator.draw() % position, saved = values[position - 1];
          values[position - 1] = values[other];
          values[other] = saved;
        }
        final rows = <Row>[];
        for (var index = 0; index < size; index++) {
          final row = data.test[index], changed = row.values.toList();
          changed[attribute.index] = values[index];
          rows.add(Row(row.id, changed, row.label));
        }
        counts.add(pruned.correct(rows));
      }
      results.add(Permutation(attribute, counts, repeats * base - sum(counts)));
    }
    results.sort((a, b) {
      final comparison = b.drop.compareTo(a.drop);
      return comparison != 0 ? comparison : a.attribute.index.compareTo(b.attribute.index);
    });
    return [
      'permutation pruned test repeats $repeats seed ${data.settings.permutationSeed} base ${ratioText(base, size)}',
      for (var rank = 0; rank < results.length; rank++)
        '${rank + 1} ${results[rank].attribute.name} correct ${results[rank].counts.join(' ')} drop ${fractionText(results[rank].drop, repeats * size)}',
    ];
  }
}

void writeSections(String name, List<List<String>> sections) => File('output/$name').writeAsStringSync('${joinSections(sections).join('\n')}\n');

void main() {
  final analysis = Analysis(loadDataset());
  Directory('output').createSync(recursive: true);
  writeSections('tree.txt', [analysis.rootCandidateLines(), analysis.treeLines(analysis.grown), analysis.surrogateLines()]);
  writeSections('pruned_tree.txt', [analysis.pruningLines(), analysis.treeLines(analysis.pruned)]);
  writeSections('predictions.csv', [analysis.predictionLines()]);
  writeSections('rules.txt', [analysis.ruleLines(), analysis.generalizedLines(), analysis.misclassifiedLines()]);
  writeSections('evaluation.txt', [
    analysis.dataLines(),
    [analysis.summaryLine('grown', analysis.grown), analysis.summaryLine('pruned', analysis.pruned)],
    analysis.modelEvaluation('grown'), analysis.modelEvaluation('pruned'), analysis.routingLines(),
    analysis.crossValidationLines(), analysis.depthLines(), analysis.complexityLines(), analysis.baggingLines(),
    analysis.mcnemarLines(), analysis.aucLines(), analysis.learningLines(),
  ]);
  writeSections('importance.txt', [analysis.impurityLines('grown', analysis.grown), analysis.impurityLines('pruned', analysis.pruned), analysis.permutationLines()]);
}
