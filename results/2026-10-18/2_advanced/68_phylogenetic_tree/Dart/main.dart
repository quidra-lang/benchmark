import 'dart:io';
import 'dart:math';

part 'alignment.dart';
part 'distances.dart';
part 'tree_building.dart';
part 'parsimony.dart';
part 'tree_io.dart';

class Settings {
  String model = '';
  int outgroup = 0, replicates = 0, seed = 0, missing = 0, low = 0;
  double saturation = 0;
  final List<int> exhaustive = [];
  final List<List<String>> hypotheses = [];
}

class Move {
  final int mask, swap;
  final double value;
  Move(this.mask, this.swap, this.value);
}

class Addition {
  final int taxon, mask, score, ties;
  Addition(this.taxon, this.mask, this.score, this.ties);
}

class Stepwise {
  Tree tree;
  final int initialScore;
  int score = 0, evaluated = 0;
  final List<Addition> additions = [];
  Stepwise(this.tree, this.initialScore);
}

class Search {
  Tree tree;
  double value;
  int evaluated = 0;
  final List<Move> moves = [];
  Search(this.tree, this.value);
}

class ExhaustiveTree {
  final Tree tree;
  final int score;
  final double bme;
  final String newick;
  final Set<int> splits;
  ExhaustiveTree(this.tree, this.score, this.bme, this.newick, this.splits);
}

int popcount(int mask) {
  var n = 0;
  while (mask != 0) {
    mask &= mask - 1;
    n++;
  }
  return n;
}

String yes(bool b) => b ? 'yes' : 'no';
Settings readSettings(List<SequenceRecord> taxa) {
  final index = {for (var i = 0; i < taxa.length; i++) taxa[i].name: i},
      p = Settings();
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'model':
        p.model = a[1];
        break;
      case 'outgroup':
        p.outgroup = index[a[1]]!;
        break;
      case 'replicates':
        p.replicates = int.parse(a[1]);
        break;
      case 'seed':
        p.seed = int.parse(a[1]);
        break;
      case 'max_missing_percent':
        p.missing = int.parse(a[1]);
        break;
      case 'saturation_distance':
        p.saturation = double.parse(a[1]);
        break;
      case 'exhaustive_taxa':
        p.exhaustive.addAll(a.skip(1).map((s) => index[s]!));
        break;
      case 'low_sites':
        p.low = int.parse(a[1]);
        break;
    }
  }
  p.exhaustive.sort();
  p.hypotheses.addAll(
    File('input/clades.txt').readAsLinesSync().map((s) => s.split(' ')),
  );
  return p;
}

(List<SequenceRecord>, List<String>) checkAlignment(
  List<SequenceRecord> records,
  int missing,
) {
  final length = records.first.sequence.length,
      seen = <String>{},
      taxa = <SequenceRecord>[],
      errors = <String>[];
  for (final r in records) {
    var reason = '';
    if (seen.contains(r.name)) {
      reason = 'duplicate name';
    } else {
      for (var i = 0; i < r.sequence.length; i++) {
        if (!baseSets.containsKey(r.sequence[i])) {
          reason = 'invalid character ${r.sequence[i]} at column ${i + 1}';
          break;
        }
      }
      if (reason.isEmpty && r.sequence.length != length)
        reason = 'length mismatch ${r.sequence.length}';
      if (reason.isEmpty) {
        var n = 0;
        for (var i = 0; i < r.sequence.length; i++) {
          if (r.sequence[i] == '-' || r.sequence[i] == 'N') n++;
        }
        if (100 * n > missing * length) reason = 'too many missing $n';
      }
    }
    seen.add(r.name);
    if (reason.isNotEmpty) {
      errors.add('REJECT line ${r.line} ${r.name} $reason');
    } else {
      taxa.add(r);
    }
  }
  return (taxa, errors);
}

Stepwise stepwise(
  List<int> list,
  List<SequenceRecord> taxa,
  int outgroup,
  int length,
) {
  var t = Tree(taxa.length);
  final u = t.next++;
  for (final x in list.take(3)) {
    t.connect(u, x, 0);
  }
  final result = Stepwise(t, parsimonyScore(t, taxa, outgroup, length));
  for (final x in list.skip(3)) {
    var bestScore = 1 << 30, ties = 0, mask = 0;
    late Tree best;
    for (final b in branches(t, taxa, outgroup)) {
      final v = insertion(t, b, x),
          score = parsimonyScore(v, taxa, outgroup, length);
      result.evaluated++;
      if (score < bestScore) {
        bestScore = score;
        ties = 1;
        mask = b.mask;
        best = v;
      } else if (score == bestScore) {
        ties++;
      }
    }
    t = best;
    result.additions.add(Addition(x, mask, bestScore, ties));
  }
  result.tree = t;
  result.score = parsimonyScore(t, taxa, outgroup, length);
  return result;
}

Search hillClimb(
  Tree t,
  List<SequenceRecord> taxa,
  int outgroup,
  double Function(Tree) objective,
) {
  final result = Search(t.copy(), objective(t));
  while (true) {
    var moved = false;
    for (final b in branches(result.tree, taxa, outgroup)) {
      if (b.u < taxa.length || b.v < taxa.length) continue;
      for (var swap = 1; swap <= 2; swap++) {
        final candidate = nni(result.tree, b, swap, taxa, outgroup),
            value = objective(candidate);
        result.evaluated++;
        if (value < result.value) {
          result.tree = candidate;
          result.value = value;
          result.moves.add(Move(b.mask, swap, value));
          moved = true;
          break;
        }
      }
      if (moved) break;
    }
    if (!moved) break;
  }
  return result;
}

double bme(Tree t, List<List<double>> matrix, int n) {
  final taxa = t.leaves(n);
  var sum = 0.0;
  for (var i = 0; i < taxa.length; i++) {
    final a = taxa[i];
    for (final b in taxa.skip(i + 1)) {
      final edges = path(t, a, b).$2;
      sum += matrix[a][b] / (1 << (edges - 1));
    }
  }
  return sum;
}

(int, int, List<int>) bounds(List<SequenceRecord> taxa, int length) {
  var minimum = 0, maximum = 0;
  final columns = List.filled(length, 0);
  for (var col = 0; col < length; col++) {
    var best = 5;
    for (var mask = 1; mask <= 15; mask++) {
      if (taxa.every((t) => (mask & baseSets[t.sequence[col]]!) != 0))
        best = min(best, popcount(mask));
    }
    columns[col] = best - 1;
    minimum += best - 1;
    var maxChanges = taxa.length;
    for (var b = 1; b <= 8; b <<= 1) {
      var count = 0;
      for (final t in taxa) {
        if ((baseSets[t.sequence[col]]! & b) == 0) count++;
      }
      maxChanges = min(maxChanges, count);
    }
    maximum += maxChanges;
  }
  return (minimum, maximum, columns);
}

Tree consensus(
  Set<int> clades,
  List<int> list,
  List<SequenceRecord> taxa,
  int outgroup,
) {
  final t = Tree(taxa.length), root = taxa.length;
  t.next++;
  var mask = 0;
  for (final x in list) {
    if (x != outgroup) mask |= 1 << x;
  }
  t.connect(root, outgroup, 0);
  void build(int node, int current) {
    final maximal = <int>[];
    for (final c in clades) {
      if (c != current && (c & current) == c) {
        var contained = false;
        for (final d in clades) {
          if (d != c && d != current && (d & current) == d && (c & d) == c) {
            contained = true;
            break;
          }
        }
        if (!contained) maximal.add(c);
      }
    }
    maximal.sort();
    var covered = 0;
    for (final c in maximal) {
      final v = t.next++;
      t.connect(node, v, 0);
      covered |= c;
      build(v, c);
    }
    for (final x in list) {
      if (((current >> x) & 1) != 0 && ((covered >> x) & 1) == 0)
        t.connect(node, x, 0);
    }
  }

  build(root, mask);
  return t;
}

List<ExhaustiveTree> exhaustive(
  List<int> list,
  List<SequenceRecord> taxa,
  int outgroup,
  int length,
  List<List<double>> matrix,
) {
  final t = Tree(taxa.length), u = taxa.length;
  t.next++;
  for (final x in list.take(3)) {
    t.connect(u, x, 0);
  }
  var trees = [t];
  for (final x in list.skip(3)) {
    final next = <Tree>[];
    for (final tree in trees) {
      for (final branch in branches(tree, taxa, outgroup)) {
        next.add(insertion(tree, branch, x));
      }
    }
    trees = next;
  }
  return [
    for (final tree in trees)
      ExhaustiveTree(
        tree,
        parsimonyScore(tree, taxa, outgroup, length),
        bme(tree, matrix, taxa.length),
        newick(tree, taxa, outgroup, false, null),
        splitSet(tree, taxa, outgroup),
      ),
  ];
}

List<double> likelihood(
  Tree t,
  List<SequenceRecord> taxa,
  int outgroup,
  int length,
) {
  final r = rootTree(t, taxa, outgroup), a = List.filled(length, 0.0);
  for (var col = 0; col < length; col++) {
    List<double> visit(int v) {
      if (v < taxa.length) {
        final mask = baseSets[taxa[v].sequence[col]]!;
        return [for (var x = 0; x < 4; x++) ((mask >> x) & 1) != 0 ? 1.0 : 0.0];
      }
      final values = List.filled(4, 1.0);
      for (final child in r.children[v]!) {
        final partial = visit(child), e = exp(-4 * t.adj[v]![child]! / 3);
        final same = 0.25 + 0.75 * e, different = 0.25 - 0.25 * e;
        for (var x = 0; x < 4; x++) {
          var sum = 0.0;
          for (var y = 0; y < 4; y++) {
            sum += (x == y ? same : different) * partial[y];
          }
          values[x] *= sum;
        }
      }
      return values;
    }

    final root = visit(r.root);
    var sum = 0.0;
    for (var x = 0; x < 4; x++) {
      sum += 0.25 * root[x];
    }
    a[col] = log(sum);
  }
  return a;
}

int rf(Set<int> a, Set<int> b) =>
    a.difference(b).length + b.difference(a).length;
int quartet(Set<int> splits, int a, int b, int c, int d) {
  final partitions = [(a, b, c, d), (a, c, b, d), (a, d, b, c)];
  for (var k = 0; k < 3; k++) {
    final p = partitions[k];
    for (final mask in splits) {
      final left = (mask >> p.$1) & 1, right = (mask >> p.$3) & 1;
      if (left == ((mask >> p.$2) & 1) &&
          right == ((mask >> p.$4) & 1) &&
          left != right)
        return k + 1;
    }
  }
  return 0;
}

int quartetDistance(Set<int> a, Set<int> b, int n) {
  var count = 0;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      for (var k = j + 1; k < n; k++) {
        for (var l = k + 1; l < n; l++) {
          if (quartet(a, i, j, k, l) != quartet(b, i, j, k, l)) count++;
        }
      }
    }
  }
  return count;
}

double sum(List<double> a) {
  var s = 0.0;
  for (final v in a) {
    s += v;
  }
  return s;
}

void matrixLines(
  StringBuffer out,
  List<List<double>> d,
  List<SequenceRecord> taxa,
) {
  final width = taxa.map((t) => t.name.length).reduce(max);
  for (var i = 0; i < taxa.length; i++) {
    out.write(taxa[i].name.padRight(width));
    for (var j = 0; j < taxa.length; j++) {
      out.write(' ${format(d[i][j], 5)}');
    }
    out.writeln();
  }
}

void main() {
  final records = readFASTA();
  var missing = 0;
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    if (a[0] == 'max_missing_percent') missing = int.parse(a[1]);
  }
  final (taxa, errors) = checkAlignment(records, missing);
  final p = readSettings(taxa),
      n = taxa.length,
      length = records.first.sequence.length;
  final list = [for (var i = 0; i < n; i++) i],
      ingroup = [
        for (var i = 0; i < n; i++)
          if (i != p.outgroup) i,
      ];
  final order = [p.outgroup, ...ingroup],
      exOrder = [p.outgroup, ...p.exhaustive.where((i) => i != p.outgroup)];
  var exMask = 0;
  for (final x in exOrder.skip(1)) {
    exMask |= 1 << x;
  }
  final (patternStrings, patternCount) = patterns(taxa, length);
  final weights = List.filled(length, 1),
      modelNames = ['P', 'JC', 'K2P'],
      methodNames = ['NJ_P', 'NJ_JC', 'NJ_K2P', 'ME', 'MP', 'CONSENSUS'];
  var mainIndex = 0;
  final matrices = <List<List<double>>>[], trees = <Tree>[];
  for (var i = 0; i < 3; i++) {
    matrices.add(distanceMatrix(taxa, weights, modelNames[i], p.saturation));
    trees.add(neighborJoining(matrices[i], list, n));
    if (modelNames[i] == p.model) mainIndex = i;
  }
  final mainMatrix = matrices[mainIndex],
      mainTree = trees[mainIndex],
      mainName = methodNames[mainIndex],
      mainSplits = splitSet(trees[mainIndex], taxa, p.outgroup);
  final (minimum, maximum, minColumns) = bounds(taxa, length);
  final mpStep = stepwise(order, taxa, p.outgroup, length);
  final mpSearch = hillClimb(
    mpStep.tree,
    taxa,
    p.outgroup,
    (t) => parsimonyScore(t, taxa, p.outgroup, length).toDouble(),
  );
  final (mp, ancestors, changes, mpColumns) = reconstruct(
    mpSearch.tree,
    taxa,
    p.outgroup,
    length,
  );
  final me = hillClimb(
    mainTree,
    taxa,
    p.outgroup,
    (t) => bme(t, mainMatrix, n),
  );
  trees
    ..add(me.tree)
    ..add(mp);
  final allTrees = exhaustive(exOrder, taxa, p.outgroup, length, mainMatrix);
  var bestScore = allTrees.first.score;
  for (final t in allTrees) {
    bestScore = min(bestScore, t.score);
  }
  final optimal = <ExhaustiveTree>[], scoreCounts = <int, int>{};
  for (final t in allTrees) {
    scoreCounts[t.score] = (scoreCounts[t.score] ?? 0) + 1;
    if (t.score == bestScore) optimal.add(t);
  }
  optimal.sort((a, b) => a.newick.compareTo(b.newick));
  var strictClades = Set.of(optimal.first.splits);
  for (final t in optimal.skip(1)) {
    strictClades = strictClades.intersection(t.splits);
  }
  final strict = consensus(strictClades, exOrder, taxa, p.outgroup),
      bmeTrees = List.of(allTrees)
        ..sort((a, b) {
          final c = a.bme.compareTo(b.bme);
          return c != 0 ? c : a.newick.compareTo(b.newick);
        });
  final validationStep = stepwise(exOrder, taxa, p.outgroup, length);
  final validationSearch = hillClimb(
    validationStep.tree,
    taxa,
    p.outgroup,
    (t) => parsimonyScore(t, taxa, p.outgroup, length).toDouble(),
  );
  final loglik = [
    for (var i = 0; i < 3; i++) likelihood(trees[i], taxa, p.outgroup, length),
  ];
  final summary = StringBuffer(),
      distancesOut = StringBuffer(),
      newicks = StringBuffer(),
      cladograms = StringBuffer(),
      parsimonyOut = StringBuffer(),
      likelihoodOut = StringBuffer(),
      bootstrap = StringBuffer(),
      clock = StringBuffer(),
      comparison = StringBuffer(),
      hypotheses = StringBuffer();
  summary.writeln(
    'INPUT records ${records.length} accepted $n rejected ${errors.length} columns $length',
  );
  for (final e in errors) {
    summary.writeln(e);
  }
  final composition = List.filled(4, 0);
  for (var i = 0; i < n; i++) {
    final t = taxa[i];
    var bases = 0, ambiguous = 0, miss = 0, unique = 0, gc = 0;
    for (var col = 0; col < length; col++) {
      final c = t.sequence[col];
      if (isBase(c)) {
        bases++;
        if (c == 'G' || c == 'C') gc++;
        composition['ACGT'.indexOf(c)]++;
        var otherBase = false, same = false;
        for (var j = 0; j < n; j++) {
          if (j != i && isBase(taxa[j].sequence[col])) {
            otherBase = true;
            if (taxa[j].sequence[col] == c) same = true;
          }
        }
        if (otherBase && !same) unique++;
      } else if (c == 'N' || c == '-') {
        miss++;
      } else {
        ambiguous++;
      }
    }
    summary.writeln(
      'TAXON ${t.name} bases $bases ambiguous $ambiguous missing $miss unique $unique gc ${format(gc / bases, 4)}',
    );
  }
  final classification = classify(taxa, length);
  summary.writeln(
    'COLUMNS constant ${classification.constant} variable ${classification.variable} informative ${classification.informative} gapped ${classification.gapped} empty ${classification.empty}',
  );
  summary.writeln('PATTERNS $patternCount');
  final totalBases = composition.reduce((a, b) => a + b);
  summary.writeln(
    'COMPOSITION A ${format(composition[0] / totalBases, 4)} C ${format(composition[1] / totalBases, 4)} G ${format(composition[2] / totalBases, 4)} T ${format(composition[3] / totalBases, 4)}',
  );
  final total = PairCounts();
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final c = tally(taxa[i].sequence, taxa[j].sequence, weights);
      distancesOut.writeln(
        'PAIR ${taxa[i].name} ${taxa[j].name} sites ${c.n} transitions ${c.s} transversions ${c.v}',
      );
      total.n += c.n;
      total.s += c.s;
      total.v += c.v;
    }
  }
  distancesOut.writeln(
    'TOTAL sites ${total.n} transitions ${total.s} transversions ${total.v}',
  );
  for (var i = 0; i < 3; i++) {
    final name = modelNames[i];
    distancesOut.writeln();
    distancesOut.writeln('MODEL $name');
    matrixLines(distancesOut, matrices[i], taxa);
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b < n; b++) {
        final c = tally(taxa[a].sequence, taxa[b].sequence, weights);
        final (_, saturated) = distance(c, name, p.saturation);
        if (saturated)
          distancesOut.writeln(
            'SATURATED ${taxa[a].name} ${taxa[b].name} sites ${c.n}',
          );
      }
    }
  }
  distancesOut.writeln();
  distancesOut.writeln('PATRISTIC $mainName');
  matrixLines(distancesOut, patristic(mainTree, n), taxa);
  distancesOut.writeln();
  distancesOut.writeln(
    'ME start $mainName length ${format(bme(mainTree, mainMatrix, n), 5)}',
  );
  for (final m in me.moves) {
    distancesOut.writeln(
      'NNI edge ${symbol(m.mask, n)} swap ${m.swap} length ${format(m.value, 5)}',
    );
  }
  distancesOut.writeln(
    'ME moves ${me.moves.length} evaluated ${me.evaluated} length ${format(me.value, 5)}',
  );
  distancesOut.writeln(
    'EXHAUSTIVE taxa ${exOrder.length} trees ${allTrees.length} best ${format(bmeTrees[0].bme, 5)} second ${format(bmeTrees[1].bme, 5)}',
  );
  distancesOut.writeln(
    'BEST ${bmeTrees[0].newick} parsimony ${bmeTrees[0].score}',
  );
  parsimonyOut.writeln('BOUNDS minimum $minimum maximum $maximum');
  for (var i = 0; i < 3; i++) {
    final s = parsimonyScore(trees[i], taxa, p.outgroup, length);
    parsimonyOut.writeln(
      'TREE ${methodNames[i]} score $s ci ${format(minimum / s, 4)} ri ${format((maximum - s) / (maximum - minimum), 4)}',
    );
  }
  parsimonyOut.writeln(
    'START ${taxa[order[0]].name} ${taxa[order[1]].name} ${taxa[order[2]].name} score ${mpStep.initialScore}',
  );
  for (final a in mpStep.additions) {
    parsimonyOut.writeln(
      'ADD ${taxa[a.taxon].name} edge ${symbol(a.mask, n)} score ${a.score} ties ${a.ties}',
    );
  }
  parsimonyOut.writeln(
    'STEPWISE score ${mpStep.score} evaluated ${mpStep.evaluated}',
  );
  for (final m in mpSearch.moves) {
    parsimonyOut.writeln(
      'NNI edge ${symbol(m.mask, n)} swap ${m.swap} score ${m.value.toInt()}',
    );
  }
  final mpScore = mpSearch.value.toInt();
  parsimonyOut.writeln(
    'SEARCH moves ${mpSearch.moves.length} evaluated ${mpSearch.evaluated} score $mpScore',
  );
  parsimonyOut.writeln(
    'TREE MP score $mpScore ci ${format(minimum / mpScore, 4)} ri ${format((maximum - mpScore) / (maximum - minimum), 4)}',
  );
  parsimonyOut.writeln('MP ${newick(mp, taxa, p.outgroup, true, null)}');
  final columnCounts = <int, int>{};
  var most = 0, homoplasy = 0;
  for (var col = 0; col < length; col++) {
    final k = mpColumns[col];
    columnCounts[k] = (columnCounts[k] ?? 0) + 1;
    most = max(most, k);
    if (k > minColumns[col]) homoplasy++;
  }
  for (var k = 0; k <= most; k++) {
    parsimonyOut.writeln('CHANGES $k columns ${columnCounts[k] ?? 0}');
  }
  parsimonyOut.writeln(
    'HOMOPLASY columns $homoplasy extra ${mpScore - minimum}',
  );
  for (final mask in sortedMasks(ancestors.keys, n)) {
    parsimonyOut.writeln('ANCESTOR ${symbol(mask, n)} ${ancestors[mask]}');
  }
  parsimonyOut.writeln();
  parsimonyOut.writeln(
    'EXHAUSTIVE taxa ${exOrder.length} trees ${allTrees.length} best $bestScore optimal ${optimal.length}',
  );
  final scores = scoreCounts.keys.toList()..sort();
  for (final s in scores) {
    parsimonyOut.writeln('SCORE $s trees ${scoreCounts[s]}');
  }
  for (final t in optimal) {
    parsimonyOut.writeln('OPTIMAL ${t.newick} bme ${format(t.bme, 5)}');
  }
  parsimonyOut.writeln(
    'STRICT ${newick(strict, taxa, p.outgroup, false, null)}',
  );
  parsimonyOut.writeln(
    'HEURISTIC score ${validationSearch.value.toInt()} optimal ${yes(validationSearch.value.toInt() == bestScore)}',
  );
  likelihoodOut.writeln('LIKELIHOOD columns $length patterns $patternCount');
  for (var i = 0; i < 3; i++) {
    final total = sum(loglik[i]);
    likelihoodOut.writeln(
      'TREE ${methodNames[i]} loglik ${format(total, 4)} per_site ${format(total / length, 4)}',
    );
  }
  for (final (a, b) in [(0, 1), (0, 2), (1, 2)]) {
    final delta = [
      for (var col = 0; col < length; col++) loglik[a][col] - loglik[b][col],
    ];
    final difference = sum(delta), mean = difference / length;
    var ss = 0.0;
    for (final v in delta) {
      final d = v - mean;
      ss += d * d;
    }
    final se = sqrt(length / (length - 1) * ss);
    likelihoodOut.writeln(
      'KH ${methodNames[a]} ${methodNames[b]} difference ${format(difference, 4)} se ${format(se, 4)} z ${format(difference / se, 4)}',
    );
  }
  final low = [for (var i = 0; i < length; i++) i]
    ..sort((a, b) {
      final c = double.parse(
        format(loglik[mainIndex][a], 4),
      ).compareTo(double.parse(format(loglik[mainIndex][b], 4)));
      return c != 0 ? c : a.compareTo(b);
    });
  likelihoodOut.writeln('LOWEST $mainName sites ${p.low}');
  for (final col in low.take(p.low)) {
    final (_, changes, _) = provisional(mainTree, taxa, p.outgroup, col);
    likelihoodOut.writeln(
      'SITE ${col + 1} loglik ${format(loglik[mainIndex][col], 4)} changes $changes pattern ${patternStrings[col]}',
    );
  }
  final support = <int, int>{};
  bootstrap.writeln(
    'BOOTSTRAP model ${p.model} replicates ${p.replicates} seed ${p.seed}',
  );
  var state = p.seed, identical = 0;
  for (var replicate = 1; replicate <= p.replicates; replicate++) {
    final w = List.filled(length, 0);
    for (var draw = 0; draw < length; draw++) {
      state = 48271 * state % 2147483647;
      w[state % length]++;
    }
    final distinct = w.where((count) => count > 0).length,
        tree = neighborJoining(
          distanceMatrix(taxa, w, p.model, p.saturation),
          list,
          n,
        );
    final splits = splitSet(tree, taxa, p.outgroup);
    for (final mask in splits) {
      support[mask] = (support[mask] ?? 0) + 1;
    }
    final distance = rf(mainSplits, splits);
    if (distance == 0) identical++;
    bootstrap.writeln('REPLICATE $replicate distinct $distinct rf $distance');
  }
  bootstrap.writeln('IDENTICAL $identical');
  for (final mask in sortedMasks(mainSplits, n)) {
    bootstrap.writeln('SUPPORT ${symbol(mask, n)} ${support[mask] ?? 0}');
  }
  final majority = {
        for (final entry in support.entries)
          if (2 * entry.value > p.replicates) entry.key,
      },
      ranked = sortedMasks(support.keys, n);
  ranked.sort((a, b) {
    final c = support[b]!.compareTo(support[a]!);
    return c != 0 ? c : symbol(a, n).compareTo(symbol(b, n));
  });
  for (final mask in ranked) {
    bootstrap.writeln('SPLIT ${symbol(mask, n)} ${support[mask]}');
  }
  trees.add(consensus(majority, list, taxa, p.outgroup));
  bootstrap.writeln(
    'CONSENSUS ${newick(trees[5], taxa, p.outgroup, false, support)}',
  );
  for (final removed in ingroup) {
    final keep = list.where((x) => x != removed).toList(), restricted = <int>{};
    final tree = neighborJoining(mainMatrix, keep, n);
    for (var mask in mainSplits) {
      mask &= ~(1 << removed);
      final count = popcount(mask);
      if (count >= 2 && count <= n - 3) restricted.add(mask);
    }
    bootstrap.writeln(
      'JACKKNIFE ${taxa[removed].name} rf ${rf(restricted, splitSet(tree, taxa, p.outgroup))}',
    );
  }
  final rateLines = StringBuffer();
  var rejected = 0, pairCount = 0;
  for (var i = 0; i < ingroup.length; i++) {
    final a = ingroup[i];
    for (final b in ingroup.skip(i + 1)) {
      var m1 = 0, m2 = 0;
      for (var col = 0; col < length; col++) {
        final x = taxa[a].sequence[col],
            y = taxa[b].sequence[col],
            o = taxa[p.outgroup].sequence[col];
        if (isBase(x) && isBase(y) && isBase(o) && x != y) {
          if (y == o) m1++;
          if (x == o) m2++;
        }
      }
      final difference = m1 - m2,
          reject = 1000 * difference * difference > 3841 * (m1 + m2);
      if (reject) rejected++;
      pairCount++;
      final chi = m1 + m2 == 0
          ? '-'
          : format(difference * difference / (m1 + m2), 4);
      rateLines.writeln(
        'RRT ${taxa[a].name} ${taxa[b].name} m1 $m1 m2 $m2 chi2 $chi ${reject ? 'reject' : 'ok'}',
      );
    }
  }
  clock.writeln(
    'RELATIVE_RATE outgroup ${taxa[p.outgroup].name} pairs $pairCount rejected $rejected',
  );
  clock.write(rateLines);
  final root = rootTree(mainTree, taxa, p.outgroup).root;
  final tipDistances = [for (final x in ingroup) path(mainTree, root, x).$1];
  final mu = sum(tipDistances) / ingroup.length;
  var ss = 0.0;
  for (final x in tipDistances) {
    final d = x - mu;
    ss += d * d;
  }
  final sd = sqrt(ss / (ingroup.length - 1));
  clock.writeln(
    'ROOT_TO_TIP $mainName mean ${format(mu, 5)} sd ${format(sd, 5)} cv ${format(sd / mu, 4)}',
  );
  for (var i = 0; i < ingroup.length; i++) {
    clock.writeln('TIP ${taxa[ingroup[i]].name} ${format(tipDistances[i], 5)}');
  }
  final splits = <Set<int>>[],
      allClades = <int>{},
      mainLengths = <int, double>{},
      mpBranchMasks = <int>{};
  for (final branch in branches(mainTree, taxa, p.outgroup)) {
    mainLengths[branch.mask] = mainTree.adj[branch.u]![branch.v]!;
  }
  for (final branch in branches(mp, taxa, p.outgroup)) {
    mpBranchMasks.add(branch.mask);
  }
  for (var i = 0; i < 6; i++) {
    final t = trees[i];
    splits.add(splitSet(t, taxa, p.outgroup));
    var supported = 0;
    for (final mask in splits[i]) {
      allClades.add(mask);
      if (2 * (support[mask] ?? 0) > p.replicates) supported++;
    }
    var parsimonyValue = '-',
        bmeValue = '-',
        treeLength = '-',
        negative = '-',
        sseValue = '-',
        likelihoodValue = '-';
    if (i < 5) {
      parsimonyValue = parsimonyScore(t, taxa, p.outgroup, length).toString();
      bmeValue = format(bme(t, mainMatrix, n), 5);
    }
    if (i < 3) {
      var total = 0.0;
      for (final branch in branches(t, taxa, p.outgroup)) {
        total += t.adj[branch.u]![branch.v]!;
      }
      treeLength = format(total, 5);
      negative = t.negative.toString();
      var ss = 0.0;
      for (var a = 0; a < n; a++) {
        for (var b = a + 1; b < n; b++) {
          final patristic = path(t, a, b).$1,
              delta = matrices[i][a][b] - patristic;
          ss += delta * delta;
        }
      }
      sseValue = format(ss, 6);
      likelihoodValue = format(sum(loglik[i]), 4);
    }
    if (i == 4) treeLength = format(mpScore / length, 5);
    comparison.writeln(
      'TREE ${methodNames[i]} splits ${splits[i].length} supported $supported parsimony $parsimonyValue bme $bmeValue length $treeLength negative $negative sse $sseValue loglik $likelihoodValue',
    );
    newicks.writeln(
      '${methodNames[i]} ${newick(t, taxa, p.outgroup, i < 3 || i == 4, i == 5 ? support : null)}',
    );
    if (i > 0) cladograms.writeln();
    cladograms.writeln('TREE ${methodNames[i]}');
    cladogram(cladograms, t, taxa, p.outgroup, support);
  }
  for (var k = 0; k < 2; k++) {
    comparison.writeln('${k == 0 ? 'RF' : 'QUARTET'} ${methodNames.join(' ')}');
    for (var i = 0; i < 6; i++) {
      comparison.writeln(
        [
          methodNames[i],
          for (var j = 0; j < 6; j++)
            (k == 0
                    ? rf(splits[i], splits[j])
                    : quartetDistance(splits[i], splits[j], n))
                .toString(),
        ].join(' '),
      );
    }
  }
  for (final mask in sortedMasks(allClades, n)) {
    final marks = [
      for (var i = 0; i < 6; i++) splits[i].contains(mask) ? '+' : '-',
    ].join();
    comparison.writeln(
      'CLADE ${symbol(mask, n)} support ${support[mask] ?? 0} trees $marks length ${mainLengths.containsKey(mask) ? format(mainLengths[mask]!, 5) : '-'} changes ${mpBranchMasks.contains(mask) ? (changes[mask] ?? 0).toString() : '-'}',
    );
  }
  final nameToTaxon = {for (var i = 0; i < n; i++) taxa[i].name: i};
  var allIngroup = 0;
  for (final x in ingroup) {
    allIngroup |= 1 << x;
  }
  for (final h in p.hypotheses) {
    final name = h[0];
    var mask = 0, reason = '';
    for (final taxonName in h.skip(1)) {
      final i = nameToTaxon[taxonName];
      if (i == null) {
        reason = 'unknown taxon $taxonName';
        break;
      }
      mask |= 1 << i;
    }
    if (reason.isEmpty && ((mask >> p.outgroup) & 1) != 0)
      reason = 'contains outgroup';
    if (reason.isNotEmpty) {
      hypotheses.writeln('INVALID $name $reason');
      continue;
    }
    hypotheses.writeln(
      'CLADE $name taxa ${popcount(mask)} support ${support[mask] ?? 0}',
    );
    for (var i = 0; i < 6; i++) {
      var mrca = allIngroup;
      for (final clade in splits[i]) {
        if ((clade & mask) == mask && popcount(clade) < popcount(mrca))
          mrca = clade;
      }
      final intruders = [
        for (var x = 0; x < n; x++)
          if (((mrca >> x) & 1) != 0 && ((mask >> x) & 1) == 0) taxa[x].name,
      ];
      hypotheses.writeln(
        'TEST $name ${methodNames[i]} monophyletic ${yes(mrca == mask)} mrca ${popcount(mrca)} intruders ${intruders.isEmpty ? '-' : intruders.join(',')}',
      );
    }
    final subset = mask & exMask, count = popcount(mask & exMask);
    if (count < 2 || count >= exOrder.length - 1) {
      hypotheses.writeln('SUBSET $name untestable');
      continue;
    }
    var withScore = 1 << 30,
        withoutScore = 1 << 30,
        bmeWith = double.maxFinite,
        bmeWithout = double.maxFinite;
    for (final t in allTrees) {
      if (t.splits.contains(subset)) {
        withScore = min(withScore, t.score);
        bmeWith = min(bmeWith, t.bme);
      } else {
        withoutScore = min(withoutScore, t.score);
        bmeWithout = min(bmeWithout, t.bme);
      }
    }
    hypotheses.writeln(
      'SUBSET $name taxa $count with $withScore without $withoutScore bme_with ${format(bmeWith, 5)} bme_without ${format(bmeWithout, 5)}',
    );
  }
  Directory('output').createSync(recursive: true);
  final outputs = {
    'summary.txt': summary,
    'distances.txt': distancesOut,
    'trees.nwk': newicks,
    'cladograms.txt': cladograms,
    'parsimony.txt': parsimonyOut,
    'likelihood.txt': likelihoodOut,
    'bootstrap.txt': bootstrap,
    'clock.txt': clock,
    'comparison.txt': comparison,
    'hypotheses.txt': hypotheses,
  };
  for (final entry in outputs.entries) {
    write('output/${entry.key}', entry.value);
  }
}
