import 'dart:io';
import 'dart:math' as math;
import 'dataset.dart';
import 'distances.dart';
import 'agglomerative.dart';
import 'dendrogram.dart';
import 'validation.dart';

String realText(double? value) {
  if (value == null) return '-';
  if (value.abs() >= 1e21) return '${BigInt.from(value)}.0000';
  final text = value.toStringAsFixed(4);
  return text == '-0.0000' ? '0.0000' : text;
}
String reals(Iterable<double> values) => values.map(realText).join(' ');
String integers(Iterable<int> values) => values.join(' ');
double fourDigit(double value) {
  if (value.abs() >= 1e12) return value;
  final rounded = (value * 10000).roundToDouble() / 10000;
  return rounded == 0 ? 0.0 : rounded;
}
String ariText(Fraction ari) => '${ari.p}/${ari.q} ${realText(ari.value)}';
List<double> pairValues(List<List<double>> matrix) => [
  for (var i = 0; i < matrix.length; i++) for (var j = i + 1; j < matrix.length; j++) matrix[i][j]
];
int histogramBin(double value, double maximum) => math.min(9, (10 * value / maximum).floor());
int maxInt(Iterable<int> values) => values.reduce((a, b) => math.max(a, b));
double maxReal(Iterable<double> values) => values.reduce((a, b) => math.max(a, b));
double minReal(Iterable<double> values) => values.reduce((a, b) => math.min(a, b));
List<double> centroid(List<List<double>> vectors) =>
    [for (var f = 0; f < vectors[0].length; f++) sequentialSum(vectors.map((vector) => vector[f])) / vectors.length];
List<List<int>> clusterMembers(List<int> partition, int groups) {
  final members = List.generate(groups, (_) => <int>[]);
  for (var i = 0; i < partition.length; i++) { members[partition[i] - 1].add(i); }
  return members;
}
int majorityClass(List<int> row) {
  var best = 0;
  for (var t = 1; t < row.length; t++) { if (row[t] > row[best]) best = t; }
  return best;
}
List<int> connectedComponents(int count, List<Edge> edges) {
  final component = List.generate(count, (i) => i);
  for (final edge in edges) {
    final old = component[edge.child];
    final current = component[edge.parent];
    for (var u = 0; u < count; u++) { if (component[u] == old) component[u] = current; }
  }
  return component;
}
List<String> joinParts(List<List<String>> parts) {
  final lines = <String>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) lines.add('');
    lines.addAll(parts[i]);
  }
  return lines;
}
List<List<double>> rowSelection(List<List<double>> vectors, List<int> indices) => indices.map((i) => vectors[i]).toList();
List<int> rankedIndices(List<double> values, bool descending, bool rounded) {
  final order = List.generate(values.length, (i) => i);
  order.sort((i, j) {
    final compared = rounded ? fourDigit(values[i]).compareTo(fourDigit(values[j])) : values[i].compareTo(values[j]);
    return compared == 0 ? i.compareTo(j) : descending ? -compared : compared;
  });
  return order;
}
Fraction partitionARI(List<int> first, List<int> second) => adjustedRandIndex(
    contingencyTable(first.map((n) => n - 1).toList(), second.map((n) => n - 1).toList(), maxInt(first), maxInt(second)));
double? meanSilhouette(List<int> partition, List<List<double>> delta) {
  final groups = maxInt(partition);
  return groups < 2 ? null : sequentialSum(silhouetteValues(partition, groups, delta)) / partition.length;
}
bool equalInts(List<int> first, List<int> second) {
  for (var i = 0; i < first.length; i++) { if (first[i] != second[i]) return false; }
  return true;
}
int boundedDepth(String text) {
  var depth = 0;
  for (final digit in text.codeUnits) {
    depth = math.min(120, depth * 10 + digit - 48);
  }
  return depth;
}
class Settings {
  final String distance;
  final String standardize;
  final List<String> linkages;
  final List<double> cutHeights;
  final List<int> cutCounts;
  final int inconsistencyDepth;
  final String inconsistencyDepthText;
  final int inconsistencyCount;
  final int gapMaxK;
  final int listSize;
  final int width;
  final String compareLinkage;
  final int replicates;
  final int percent;
  final int seed;
  final int refineIterations;
  Settings(Map<String, List<String>> entries) : distance = entries['DISTANCE']![0], standardize = entries['STANDARDIZE']![0],
      linkages = entries['LINKAGES']!, cutHeights = entries['CUT_HEIGHTS']!.map(double.parse).toList(),
      cutCounts = entries['CUT_K']!.map(int.parse).toList(), inconsistencyDepth = boundedDepth(entries['INCONSISTENCY']![0]),
      inconsistencyDepthText = entries['INCONSISTENCY']![0],
      inconsistencyCount = int.parse(entries['INCONSISTENCY']![1]), gapMaxK = int.parse(entries['GAP_MAX_K']![0]),
      listSize = int.parse(entries['LIST_SIZE']![0]), width = int.parse(entries['DENDROGRAM_WIDTH']![0]),
      compareLinkage = entries['COMPARE_LINKAGE']![0], replicates = int.parse(entries['SUBSAMPLES']![0]),
      percent = int.parse(entries['SUBSAMPLES']![1]), seed = int.parse(entries['SUBSAMPLES']![2]),
      refineIterations = int.parse(entries['REFINE_ITERATIONS']![0]);
}
class Minstd {
  int state;
  Minstd(this.state);
  int draw() => state = 48271 * state % 2147483647;
}
class Tree {
  final List<Merge> merges;
  final int count;
  final List<double> heights = [];
  late final List<(int, int)> children;
  late final List<int> order;
  late final List<List<int>> members;
  late final List<int> depths;
  final List<double> subtreeHeights = [];
  Tree(this.merges, this.count) {
    children = orderedChildren(merges, count);
    order = leafOrder(children, count);
    members = List.generate(count, (u) => [u]);
    depths = List.filled(count, 0, growable: true);
    for (final merge in merges) {
      heights.add(merge.height);
      members.add([...members[merge.a], ...members[merge.b]]);
      depths.add(1 + math.max(depths[merge.a], depths[merge.b]));
      subtreeHeights.add(math.max(merge.height, math.max(subtreeHeight(merge.a), subtreeHeight(merge.b))));
    }
  }
  int get root => 2 * count - 2;
  double heightOf(int node) => node < count ? 0.0 : heights[node - count];
  double subtreeHeight(int node) => node < count ? 0.0 : subtreeHeights[node - count];
  List<int> partition(List<bool> selected) {
    final owner = List.generate(count, (u) => u);
    for (var step = 0; step < selected.length; step++) {
      if (selected[step]) {
        final node = count + step;
        for (final u in members[node]) { owner[u] = node; }
      }
    }
    final numbers = List.filled(2 * count - 1, 0);
    var groups = 0;
    for (final u in order) { if (numbers[owner[u]] == 0) numbers[owner[u]] = ++groups; }
    return owner.map((node) => numbers[node]).toList();
  }
  List<int> cutAtHeight(double height) => partition(subtreeHeights.map((value) => value <= height).toList());
  List<int> cutInto(int k) => partition(List.generate(merges.length, (step) => step < count - k));
  List<List<double>> cophenetic() {
    final matrix = floatMatrix(count, count);
    for (final merge in merges) {
      for (final i in members[merge.a]) {
        for (final j in members[merge.b]) { matrix[i][j] = matrix[j][i] = merge.height; }
      }
    }
    return matrix;
  }
  List<double> joiningHeights() {
    final values = List.filled(count, 0.0);
    for (final merge in merges) {
      for (final child in [merge.a, merge.b]) { if (child < count) values[child] = merge.height; }
    }
    return values;
  }
  List<double> heightSequence(int step, int depth) {
    if (depth == 0) return [];
    final merge = merges[step];
    return [merge.height, for (final child in [merge.a, merge.b]) if (child >= count) ...heightSequence(child - count, depth - 1)];
  }
  String newick(int node, List<String> idents) {
    if (node < count) return idents[node];
    final (upper, lower) = children[node - count];
    return '(${[upper, lower].map((child) => '${newick(child, idents)}:${realText(heightOf(node) - heightOf(child))}').join(',')})';
  }
}
class Evaluation {
  final List<int> partition;
  final List<int> sizes;
  final double? silhouette;
  final double? dunn;
  final double wss;
  final double? ch;
  final Fraction ari;
  Evaluation(this.partition, this.sizes, this.silhouette, this.dunn, this.wss, this.ch, this.ari);
  String get text => 'sizes ${integers(sizes)} silhouette ${realText(silhouette)} dunn ${realText(dunn)} wss ${realText(wss)} ch ${realText(ch)} ari ${ariText(ari)}';
}
class LinkageResult {
  final String method;
  final Tree tree;
  final List<double> cophenetic;
  final double coefficient;
  final List<Evaluation> heightCuts;
  final List<Evaluation> countCuts;
  final List<int> labelPartition;
  LinkageResult(this.method, this.tree, this.cophenetic, this.coefficient, this.heightCuts, this.countCuts, this.labelPartition);
}
class Study {
  final List<String> featureNames;
  final Settings settings;
  final int count;
  late final List<String> idents;
  late final List<String> labels;
  late final List<String> classes;
  late final List<int> targets;
  late final List<List<double>> raw;
  late final List<List<double>> vectors;
  late final List<double> means;
  late final List<double> deviations;
  late final List<List<double>> distances;
  late final List<double> distancePairs;
  late final double distanceMax;
  late final List<int> neighbors;
  final List<LinkageResult> results = [];
  late final LinkageResult chosen;
  late final int kappa;
  late final Evaluation selectedCut;
  late final List<int> selected;
  late final List<List<int>> members;
  late final List<double> silhouettes;
  late final List<List<int>> table;
  late final List<int> majority;
  Study(this.featureNames, List<Observation> observations, this.settings) : count = observations.length {
    idents = observations.map((observation) => observation.ident).toList();
    labels = observations.map((observation) => observation.label).toList();
    classes = labels.toSet().toList()..sort();
    targets = labels.map(classes.indexOf).toList();
    raw = observations.map((observation) => observation.values).toList();
    final statistics = featureStatistics(raw);
    means = statistics.$1;
    deviations = statistics.$2;
    vectors = settings.standardize == 'yes' ? standardizeData(raw, means, deviations) : raw;
    distances = distanceMatrix(vectors, settings.distance);
    distancePairs = pairValues(distances);
    distanceMax = maxReal(distancePairs);
    neighbors = [for (var i = 0; i < count; i++) nearestNeighbor(i)];
    for (final method in settings.linkages) { results.add(analyseLinkage(method)); }
    var best = results[0];
    var position = 0;
    for (final result in results) {
      for (var index = 0; index < settings.cutCounts.length; index++) {
        if (result.countCuts[index].ari.greater(best.countCuts[position].ari)) {
          best = result;
          position = index;
        }
      }
    }
    chosen = best;
    kappa = settings.cutCounts[position];
    selectedCut = chosen.countCuts[position];
    selected = selectedCut.partition;
    members = clusterMembers(selected, kappa);
    silhouettes = silhouetteValues(selected, kappa, distances);
    table = classTable(selected);
    majority = table.map(majorityClass).toList();
  }
  int nearestNeighbor(int i) {
    var best = -1;
    for (var j = 0; j < count; j++) { if (j != i && (best < 0 || distances[i][j] < distances[i][best])) best = j; }
    return best;
  }
  List<List<int>> classTable(List<int> partition) => contingencyTable(partition.map((n) => n - 1).toList(), targets, maxInt(partition), classes.length);
  Fraction labelARI(List<int> partition) => adjustedRandIndex(classTable(partition));
  int matchCount(List<int> partition) => classTable(partition).fold(0, (total, row) => total + maxInt(row));
  List<List<double>> centroids(List<int> partition) => [for (final group in clusterMembers(partition, maxInt(partition))) centroid(rowSelection(vectors, group))];
  double withinSum(List<int> partition) {
    final centers = centroids(partition);
    return sequentialSum([for (var i = 0; i < count; i++) squaredDistance(vectors[i], centers[partition[i] - 1])]);
  }
  double? dunnIndex(List<int> partition, int groups) {
    var diameter = 0.0;
    var separation = double.infinity;
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final value = distances[i][j];
        if (partition[i] == partition[j]) {
          diameter = math.max(diameter, value);
        } else {
          separation = math.min(separation, value);
        }
      }
    }
    return groups >= 2 && diameter > 0 ? separation / diameter : null;
  }
  Evaluation evaluate(List<int> partition) {
    final groups = maxInt(partition);
    final sizes = clusterMembers(partition, groups).map((group) => group.length).toList();
    final wss = withinSum(partition);
    double? ch;
    if (groups >= 2 && groups < count) {
      final overall = centroid(vectors);
      final centers = centroids(partition);
      final bss = sequentialSum([for (var g = 0; g < groups; g++) sizes[g] * squaredDistance(centers[g], overall)]);
      ch = (bss / (groups - 1)) / (wss / (count - groups));
    }
    return Evaluation(partition, sizes, meanSilhouette(partition, distances), dunnIndex(partition, groups), wss, ch, labelARI(partition));
  }
  LinkageResult analyseLinkage(String method) {
    final tree = Tree(agglomerate(distances, method), count);
    final coph = pairValues(tree.cophenetic());
    return LinkageResult(method, tree, coph, correlation(distancePairs, coph),
        settings.cutHeights.map((height) => evaluate(tree.cutAtHeight(height))).toList(),
        settings.cutCounts.map((k) => evaluate(tree.cutInto(k))).toList(), tree.cutInto(classes.length));
  }
  List<String> linkageTable() => ['method,step,a,b,height,size', for (final result in results)
    for (var step = 0; step < result.tree.merges.length; step++) mergeCSV(result.method, step, result.tree.merges[step])];
  String mergeCSV(String method, int step, Merge merge) => '$method,${step + 1},${merge.a},${merge.b},${realText(merge.height)},${merge.size}';
  List<String> clustersTable() {
    final header = ['id', 'label', for (final result in results) ...[
      for (var j = 0; j < settings.cutHeights.length; j++) '${result.method}_h${j + 1}',
      for (final k in settings.cutCounts) '${result.method}_k$k'
    ]];
    return [header.join(','), for (var i = 0; i < count; i++) [idents[i], labels[i],
      for (final result in results) for (final cut in [...result.heightCuts, ...result.countCuts]) '${cut.partition[i]}'
    ].join(',')];
  }
  List<String> dendrogramReport() {
    final blocks = <List<String>>[];
    final width = settings.width;
    for (final result in results) {
      final tree = result.tree;
      final maximum = maxReal(tree.heights);
      final cuts = settings.cutHeights.map((height) => column(height, maximum, width)).toList();
      blocks.add([
        'dendrogram ${result.method} height_max ${realText(maximum)} width $width',
        ...dendrogramRows(tree.merges, tree.children, tree.order, idents, labels, maximum, cuts, width),
        for (var i = 0; i < cuts.length; i++) 'cut ${realText(settings.cutHeights[i])} column ${cuts[i] <= width ? cuts[i] : '-'}'
      ]);
    }
    return joinParts(blocks);
  }
  List<String> treesReport() => [for (final result in results) '${result.method} ${result.tree.newick(result.tree.root, idents)};'];
  String pairText(int i, int j) => '${realText(distances[i][j])} ${idents[i]} ${idents[j]}';
  List<String> dataPart() {
    final lines = <String>[
      'data n $count features ${featureNames.length} classes ${classes.length} distance ${settings.distance} standardize ${settings.standardize}',
      for (var f = 0; f < featureNames.length; f++) 'feature ${featureNames[f]} mean ${realText(means[f])} sd ${realText(deviations[f])}'
    ];
    var smallest = (0, 1);
    var largest = (0, 1);
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        if (distances[i][j] < distances[smallest.$1][smallest.$2]) smallest = (i, j);
        if (distances[i][j] > distances[largest.$1][largest.$2]) largest = (i, j);
      }
    }
    lines.add('distances pairs ${distancePairs.length} min ${pairText(smallest.$1, smallest.$2)} max ${pairText(largest.$1, largest.$2)} mean ${realText(sequentialSum(distancePairs) / distancePairs.length)}');
    final nearest = sequentialSum([for (var i = 0; i < count; i++) distances[i][neighbors[i]]]) / count;
    final reciprocal = [for (var i = 0; i < count; i++) if (i < neighbors[i] && neighbors[neighbors[i]] == i) i].length;
    lines.add('nearest_neighbors mean ${realText(nearest)} reciprocal_pairs $reciprocal');
    lines.add('labels ${evaluate(targets.map((target) => target + 1).toList()).text}');
    return lines;
  }
  List<String> correlationPart() {
    final columns = [for (var f = 0; f < featureNames.length; f++) raw.map((row) => row[f]).toList()];
    return ['correlation ${featureNames.join(' ')}', for (var f = 0; f < columns.length; f++)
      '${featureNames[f]} ${reals(columns.map((second) => correlation(columns[f], second)))}'
    ];
  }
  List<String> histogramPart() {
    final counts = List.filled(10, 0);
    for (final value in distancePairs) { counts[histogramBin(value, distanceMax)]++; }
    final highest = maxInt(counts);
    final lines = <String>['histogram'];
    for (var b = 0; b < 10; b++) {
      var line = '${realText(b * distanceMax / 10)} ${realText((b + 1) * distanceMax / 10)} ${counts[b]}';
      final length = counts[b] * 50 ~/ highest;
      if (length > 0) line += ' ${List.filled(length, '#').join()}';
      lines.add(line);
    }
    return lines;
  }
  List<double> gaps(Tree tree) {
    final ordered = List<double>.of(tree.subtreeHeights)..sort();
    return [for (var k = 2; k <= settings.gapMaxK; k++) ordered[count - k] - ordered[count - k - 1]];
  }
  String inconsistencyLine(Tree tree, int step) {
    final sequence = tree.heightSequence(step, settings.inconsistencyDepth);
    final mean = sequentialSum(sequence) / sequence.length;
    var deviation = 0.0;
    var coefficient = 0.0;
    if (sequence.length >= 2) {
      var squares = 0.0;
      for (final value in sequence) {
        final difference = value - mean;
        squares += difference * difference;
      }
      deviation = math.sqrt(squares / (sequence.length - 1));
      coefficient = (tree.heights[step] - mean) / deviation;
    }
    return 'step ${step + 1} height ${realText(tree.heights[step])} mean ${realText(mean)} sd ${realText(deviation)} count ${sequence.length} coefficient ${realText(coefficient)}';
  }
  List<String> linkagePart(LinkageResult result) {
    final tree = result.tree;
    final heights = tree.heights;
    final leafPath = sequentialSum([for (var r = 0; r < count - 1; r++) distances[tree.order[r]][tree.order[r + 1]]]);
    final inversions = [for (var step = 1; step < heights.length; step++) if (heights[step] < heights[step - 1]) step];
    final lines = <String>[
      'linkage ${result.method}', 'cophenetic ${realText(result.coefficient)} leaf_path ${realText(leafPath)}',
      'heights min ${realText(minReal(heights))} max ${realText(maxReal(heights))} inversions ${inversions.length}',
      for (final step in inversions) 'inversion step ${step + 1} height ${realText(heights[step])} previous ${realText(heights[step - 1])}'
    ];
    final values = gaps(tree);
    var suggested = 2;
    for (var k = 3; k <= settings.gapMaxK; k++) { if (fourDigit(values[k - 2]) > fourDigit(values[suggested - 2])) suggested = k; }
    lines.addAll(['gaps ${reals(values)}', 'suggested_k $suggested']);
    final joining = tree.joiningHeights();
    final late = rankedIndices(joining, true, false).take(settings.listSize);
    lines.add('late_joiners ${late.map((i) => '${idents[i]}:${realText(joining[i])}').join(' ')}');
    final kinds = List.filled(3, 0);
    for (final merge in tree.merges) {
      final leaves = (merge.a < count ? 1 : 0) + (merge.b < count ? 1 : 0);
      kinds[2 - leaves]++;
    }
    final matches = matchCount(result.labelPartition);
    lines.addAll([
      'merges leaf_leaf ${kinds[0]} leaf_cluster ${kinds[1]} cluster_cluster ${kinds[2]} depth ${tree.depths[tree.root]}',
      'label_cut k ${classes.length} purity $matches/$count ${realText(matches / count)}',
      'inconsistency depth ${settings.inconsistencyDepthText}',
      for (var step = count - settings.inconsistencyCount - 1; step < count - 1; step++) inconsistencyLine(tree, step),
      for (var i = 0; i < settings.cutHeights.length; i++) 'cut height ${realText(settings.cutHeights[i])} clusters ${result.heightCuts[i].sizes.length} ${result.heightCuts[i].text}',
      for (var i = 0; i < settings.cutCounts.length; i++) 'cut k ${settings.cutCounts[i]} ${result.countCuts[i].text}'
    ]);
    return lines;
  }
  LinkageResult? resultOf(String method) {
    for (final result in results) { if (result.method == method) return result; }
    return null;
  }
  List<String> mstPart() {
    final single = resultOf('single')!;
    final edges = minimumSpanningTree(distances);
    final total = sequentialSum(edges.map((edge) => edge.weight));
    final weights = edges.map((edge) => edge.weight).toList()..sort();
    var heightResult = 'match';
    for (var i = 0; i < weights.length; i++) { if ((weights[i] - single.tree.heights[i]).abs() > 1e-9) heightResult = 'mismatch'; }
    final linked = List.generate(count, (_) => List.filled(count, false));
    for (final edge in edges) { linked[edge.parent][edge.child] = linked[edge.child][edge.parent] = true; }
    final nnEdges = [for (var i = 0; i < count; i++) if (linked[i][neighbors[i]]) i].length;
    final lines = <String>['mst total ${realText(total)} heights $heightResult nn_edges $nnEdges/$count'];
    final order = List.generate(edges.length, (i) => i)..sort((a, b) {
      final compared = edges[a].weight.compareTo(edges[b].weight);
      return compared == 0 ? a.compareTo(b) : compared;
    });
    final ordered = order.map((i) => edges[i]).toList();
    for (var position = 0; position < settings.cutCounts.length; position++) {
      final k = settings.cutCounts[position];
      final component = connectedComponents(count, ordered.take(count - k).toList());
      final partition = single.countCuts[position].partition;
      var result = 'match';
      for (var i = 0; i < count; i++) {
        for (var j = i + 1; j < count; j++) { if ((component[i] == component[j]) != (partition[i] == partition[j])) result = 'mismatch'; }
      }
      lines.add('mst partition k $k $result');
    }
    return lines;
  }
  List<String> comparePart() {
    final method = settings.compareLinkage;
    final lines = <String>['compare linkage $method k ${classes.length}'];
    for (final kind in distanceTypes) {
      final delta = distanceMatrix(vectors, kind);
      final tree = Tree(agglomerate(delta, method), count);
      final coefficient = correlation(pairValues(delta), pairValues(tree.cophenetic()));
      final partition = tree.cutInto(classes.length);
      lines.add('metric $kind cophenetic ${realText(coefficient)} silhouette ${realText(meanSilhouette(partition, delta))} ari ${ariText(labelARI(partition))}');
    }
    return lines;
  }
  List<String> copheneticPart() => [
    'cophenetic_matrix', 'linkage ${results.map((result) => result.method).join(' ')}',
    for (final first in results) '${first.method} ${reals(results.map((second) => correlation(first.cophenetic, second.cophenetic)))}'
  ];
  List<String> agreementPart() => [
    'agreement k ${classes.length}', 'linkage ${results.map((result) => result.method).join(' ')}',
    for (final first in results) '${first.method} ${reals(results.map((second) => partitionARI(first.labelPartition, second.labelPartition).value))}'
  ];
  List<String> summaryPart() {
    final ranking = rankedIndices(results.map((result) => result.coefficient).toList(), true, true);
    final lines = <String>['summary', 'cophenetic_ranking ${ranking.map((i) => results[i].method).join(' ')}'];
    for (var position = 0; position < settings.cutCounts.length; position++) {
      var best = results[0];
      for (final result in results.skip(1)) { if (result.countCuts[position].ari.greater(best.countCuts[position].ari)) best = result; }
      lines.add('best_ari k ${settings.cutCounts[position]} ${best.method} ${ariText(best.countCuts[position].ari)}');
    }
    for (final result in results) {
      var best = 0;
      for (var position = 1; position < settings.cutCounts.length; position++) {
        if (fourDigit(result.countCuts[position].silhouette!) > fourDigit(result.countCuts[best].silhouette!)) best = position;
      }
      lines.add('best_silhouette ${result.method} k ${settings.cutCounts[best]} ${realText(result.countCuts[best].silhouette)}');
    }
    lines.add('selected ${chosen.method} k $kappa');
    return lines;
  }
  List<String> validationReport() => joinParts([
    dataPart(), correlationPart(), histogramPart(), for (final result in results) linkagePart(result),
    if (resultOf('single') != null) mstPart(), comparePart(), copheneticPart(), agreementPart(), summaryPart()
  ]);
  double separation(List<int> first, List<int> second) {
    var best = double.infinity;
    for (final i in first) { for (final j in second) { best = math.min(best, distances[i][j]); } }
    return best;
  }
  List<String> clusterLines(int g) {
    final group = members[g];
    final size = group.length;
    final silhouette = sequentialSum(group.map((i) => silhouettes[i])) / size;
    final major = majority[g];
    final majorCount = table[g][major];
    final means = [for (var f = 0; f < featureNames.length; f++) sequentialSum(group.map((i) => raw[i][f])) / size];
    var medoid = -1;
    var medoidSum = 0.0;
    for (final i in group) {
      final total = sequentialSum(group.map((j) => distances[i][j]));
      if (medoid < 0 || total < medoidSum) {
        medoid = i;
        medoidSum = total;
      }
    }
    var diameter = '0.0000 - -';
    (int, int)? widest;
    for (var position = 0; position < group.length; position++) {
      for (final j in group.skip(position + 1)) {
        final i = group[position];
        if (widest == null || distances[i][j] > distances[widest.$1][widest.$2]) widest = (i, j);
      }
    }
    if (widest != null) diameter = pairText(widest.$1, widest.$2);
    var nearest = -1;
    var nearestSeparation = 0.0;
    for (var h = 0; h < kappa; h++) {
      if (h == g) continue;
      final value = separation(group, members[h]);
      if (nearest < 0 || value < nearestSeparation) {
        nearest = h;
        nearestSeparation = value;
      }
    }
    return [
      'cluster ${g + 1} size $size silhouette ${realText(silhouette)} majority ${classes[major]} purity $majorCount/$size ${realText(majorCount / size)}',
      '  mean ${reals(means)}', '  medoid ${idents[medoid]} diameter $diameter nearest ${nearest + 1} separation ${realText(nearestSeparation)}'
    ];
  }
  List<String> selectionPart() => [
    'selected linkage ${chosen.method} k $kappa ari ${ariText(selectedCut.ari)} silhouette ${realText(selectedCut.silhouette)}',
    for (var g = 0; g < kappa; g++) ...clusterLines(g)
  ];
  List<String> centroidPart() {
    final centers = centroids(selected);
    return ['centroid_distances', for (var g = 0; g < centers.length; g++)
      '${g + 1} ${reals(centers.map((second) => math.sqrt(squaredDistance(centers[g], second))))}'
    ];
  }
  List<String> profilePart() {
    final nameWidth = maxInt(featureNames.map((name) => name.length));
    final lines = <String>['profile_bars'];
    for (var g = 0; g < kappa; g++) {
      final group = members[g];
      lines.add('cluster ${g + 1}');
      for (var f = 0; f < featureNames.length; f++) {
        final zeta = sequentialSum(group.map((i) => (raw[i][f] - means[f]) / deviations[f])) / group.length;
        final bar = List.filled(math.min(10, (zeta.abs() * 4).floor()), '#').join();
        final blank = List.filled(10, ' ').join();
        final left = zeta < 0 ? bar.padLeft(10) : blank;
        final right = zeta < 0 ? blank : bar.padRight(10);
        lines.add('${featureNames[f].padRight(nameWidth)} $left|$right ${realText(zeta)}');
      }
    }
    return lines;
  }
  List<String> contingencyPart() {
    final totals = List.filled(classes.length, 0);
    final lines = <String>['contingency', 'cluster ${classes.join(' ')} total'];
    for (var g = 0; g < table.length; g++) {
      final row = table[g];
      for (var t = 0; t < row.length; t++) { totals[t] += row[t]; }
      lines.add('${g + 1} ${integers(row)} ${row.fold(0, (total, value) => total + value)}');
    }
    final matches = matchCount(selected);
    lines.addAll(['total ${integers(totals)} $count', 'purity $matches/$count ${realText(matches / count)}']);
    return lines;
  }
  List<String> misplacedPart() {
    final lines = <String>['misplaced'];
    var wrong = 0;
    for (var i = 0; i < count; i++) {
      final major = majority[selected[i] - 1];
      if (targets[i] != major) {
        wrong++;
        lines.add('${idents[i]} label ${labels[i]} cluster ${selected[i]} majority ${classes[major]}');
      }
    }
    lines.add('count $wrong');
    return lines;
  }
  List<String> weakestPart() => ['weakest', for (final i in rankedIndices(silhouettes, false, false).take(settings.listSize))
    '${idents[i]} label ${labels[i]} cluster ${selected[i]} silhouette ${realText(silhouettes[i])}'
  ];
  List<String> featurePart() {
    final ratios = <double>[];
    for (var f = 0; f < featureNames.length; f++) {
      final values = vectors.map((vector) => vector[f]).toList();
      final overall = sequentialSum(values) / count;
      final means = [for (final group in members) sequentialSum(group.map((i) => values[i])) / group.length];
      var between = 0.0;
      for (var g = 0; g < kappa; g++) {
        final difference = means[g] - overall;
        between += members[g].length * difference * difference;
      }
      var within = 0.0;
      for (var i = 0; i < count; i++) {
        final difference = values[i] - means[selected[i] - 1];
        within += difference * difference;
      }
      ratios.add((between / (kappa - 1)) / (within / (count - kappa)));
    }
    final ranking = rankedIndices(ratios, true, true);
    return ['features', for (var rank = 0; rank < ranking.length; rank++)
      '${rank + 1} ${featureNames[ranking[rank]]} f_ratio ${realText(ratios[ranking[rank]])}'
    ];
  }
  String classCounts(Tree tree, int node) {
    final counts = List.filled(classes.length, 0);
    for (final i in tree.members[node]) { counts[targets[i]]++; }
    return counts.join('/');
  }
  List<String> topMergesPart() {
    final tree = chosen.tree;
    final lines = <String>['top_merges'];
    for (var step = count - settings.inconsistencyCount - 1; step < count - 1; step++) {
      final merge = tree.merges[step];
      lines.add('step ${step + 1} height ${realText(merge.height)} a ${merge.a} ${tree.members[merge.a].length} ${classCounts(tree, merge.a)} b ${merge.b} ${tree.members[merge.b].length} ${classCounts(tree, merge.b)}');
    }
    return lines;
  }
  List<String> dropFeaturePart() {
    final lines = <String>['drop_feature'];
    for (var f = 0; f < featureNames.length; f++) {
      final reduced = [for (final vector in vectors) [for (var j = 0; j < vector.length; j++) if (j != f) vector[j]]];
      final partition = Tree(agglomerate(distanceMatrix(reduced, settings.distance), chosen.method), count).cutInto(kappa);
      lines.add('${featureNames[f]} ari_selected ${ariText(partitionARI(partition, selected))} ari_labels ${ariText(labelARI(partition))}');
    }
    return lines;
  }
  int nearestCenter(List<double> vector, List<List<double>> centers) {
    var best = 0;
    var bestValue = squaredDistance(vector, centers[0]);
    for (var g = 1; g < centers.length; g++) {
      final value = squaredDistance(vector, centers[g]);
      if (value < bestValue) {
        best = g;
        bestValue = value;
      }
    }
    return best + 1;
  }
  List<String> refinementPart() {
    final limit = settings.refineIterations;
    final centers = centroids(selected);
    var previous = List<int>.of(selected);
    var iterations = limit;
    for (var t = 1; t <= limit; t++) {
      final assignment = vectors.map((vector) => nearestCenter(vector, centers)).toList();
      if (equalInts(assignment, previous)) {
        iterations = t;
        previous = assignment;
        break;
      }
      final members = clusterMembers(assignment, kappa);
      for (var g = 0; g < kappa; g++) { if (members[g].isNotEmpty) centers[g] = centroid(rowSelection(vectors, members[g])); }
      previous = assignment;
    }
    final changed = [for (var i = 0; i < count; i++) if (previous[i] != selected[i]) i].length;
    final sizes = clusterMembers(previous, kappa).map((group) => group.length).toList();
    return [
      'refinement max_iterations $limit', 'iterations $iterations changed $changed wss ${realText(withinSum(selected))} -> ${realText(withinSum(previous))}',
      'sizes ${integers(sizes)} silhouette ${realText(meanSilhouette(previous, distances))}',
      'ari_selected ${ariText(partitionARI(previous, selected))} ari_labels ${ariText(labelARI(previous))}'
    ];
  }
  List<double> jaccard(List<int> samplePartition, List<int> restricted) {
    final table = contingencyTable(restricted.map((n) => n - 1).toList(), samplePartition.map((n) => n - 1).toList(), kappa, maxInt(samplePartition));
    final columns = List.filled(table[0].length, 0);
    for (final row in table) { for (var h = 0; h < row.length; h++) { columns[h] += row[h]; } }
    final values = <double>[];
    for (final row in table) {
      final size = row.fold(0, (total, value) => total + value);
      var best = Fraction(0, 1);
      if (size > 0) {
        for (var h = 0; h < row.length; h++) {
          final candidate = Fraction(row[h], size + columns[h] - row[h]);
          if (candidate.greater(best)) best = candidate;
        }
      }
      values.add(best.value);
    }
    return values;
  }
  List<String> stabilityPart() {
    final generator = Minstd(settings.seed);
    final size = count * settings.percent ~/ 100;
    final aris = <double>[];
    final jaccards = <List<double>>[];
    final lines = <String>['stability replicates ${settings.replicates} percent ${settings.percent} seed ${settings.seed}'];
    for (var b = 1; b <= settings.replicates; b++) {
      final array = List.generate(count, (i) => i);
      for (var t = 0; t < size; t++) {
        final j = t + generator.draw() % (count - t);
        final saved = array[t];
        array[t] = array[j];
        array[j] = saved;
      }
      final sample = array.take(size).toList()..sort();
      final delta = [for (final u in sample) [for (final w in sample) distances[u][w]]];
      final partition = Tree(agglomerate(delta, chosen.method), size).cutInto(kappa);
      final restricted = sample.map((u) => selected[u]).toList();
      final ari = partitionARI(partition, restricted);
      final values = jaccard(partition, restricted);
      aris.add(ari.value);
      jaccards.add(values);
      lines.add('replicate $b size $size ari ${ariText(ari)} jaccard ${reals(values)}');
    }
    final means = [for (var g = 0; g < kappa; g++) sequentialSum(jaccards.map((row) => row[g])) / settings.replicates];
    lines.addAll(['mean_ari ${realText(sequentialSum(aris) / settings.replicates)}', 'mean_jaccard ${reals(means)}']);
    return lines;
  }
  List<String> distanceMapPart() {
    final frame = '+${List.filled(count, '-').join()}+';
    return ['distance_map ${chosen.method}', frame, for (final u in chosen.tree.order)
      '|${chosen.tree.order.map((w) => '@%#*+=-:. '[histogramBin(distances[u][w], distanceMax)]).join()}|', frame
    ];
  }
  List<String> profilesReport() => joinParts([
    selectionPart(), centroidPart(), profilePart(), contingencyPart(), misplacedPart(), weakestPart(), featurePart(),
    topMergesPart(), dropFeaturePart(), refinementPart(), stabilityPart(), distanceMapPart()
  ]);
}
void main() {
  final (names, observations) = readObservations();
  final study = Study(names, observations, Settings(readSettings()));
  Directory('output').createSync(recursive: true);
  writeLines('linkage.csv', study.linkageTable());
  writeLines('clusters.csv', study.clustersTable());
  writeLines('dendrogram.txt', study.dendrogramReport());
  writeLines('trees.txt', study.treesReport());
  writeLines('validation.txt', study.validationReport());
  writeLines('profiles.txt', study.profilesReport());
}
