import 'dart:io';
import 'dart:math' as math;

part 'ratings.dart';
part 'neighborhood.dart';
part 'factorization.dart';
part 'evaluation.dart';
part 'report.dart';

const methods = [
  'GLOBAL',
  'BASELINE',
  'USER_KNN',
  'ITEM_KNN',
  'SLOPE_ONE',
  'SVD',
  'ALS',
];
const rankings = [
  'POPULAR',
  'BASELINE',
  'USER_KNN',
  'ITEM_KNN',
  'SLOPE_ONE',
  'SVD',
  'ALS',
];

class Prediction {
  final double value, similarity;
  final bool fallback;
  final int neighbors, top;
  Prediction(
    this.value, {
    this.fallback = false,
    this.neighbors = 0,
    this.similarity = 0,
    this.top = 0,
  });
}

class Metric {
  final double rmse, mae;
  final int clipped, fallback;
  Metric(this.rmse, this.mae, this.clipped, this.fallback);
}

class GenreCount {
  final String genre;
  final int count;
  GenreCount(this.genre, this.count);
}

double sum(Iterable<double> values) {
  var total = 0.0;
  for (final x in values) {
    total += x;
  }
  return total;
}

int groupIndex(int count, List<int> bounds) =>
    bounds.where((b) => count >= b).length;
String countSummary(List<int> counts) {
  final ordered = [...counts]..sort(), n = counts.length;
  final median = n.isEven
      ? (ordered[n ~/ 2 - 1] + ordered[n ~/ 2]) / 2
      : ordered[n ~/ 2].toDouble();
  return 'min ${ordered.first} median ${real(median)} max ${ordered.last}';
}

class Recommender {
  final Ratings data;
  late final Neighborhood neighborhood;
  late final List<double> userBias, itemBias;
  late final List<int> popularity;
  late final List<bool> popular;
  late final int head;
  late final FactorModel svd, als;
  final log = <TrainingRecord>[], trainErrors = <int, double>{};
  final predictions = List.generate(7, (_) => <Prediction>[]),
      clipped = List.generate(7, (_) => <double>[]),
      errors = List.generate(7, (_) => <double>[]),
      metrics = <Metric>[];
  final relevant = <int, Set<int>>{},
      evaluated = <int>[],
      rankedLists = <int, List<List<int>>>{},
      rankingPredictions = <int, List<Map<int, Prediction>>>{};
  Recommender(this.data) {
    neighborhood = Neighborhood(data, data.params.shrinkage);
    userBias = List.filled(data.users.length, 0.0);
    itemBias = List.filled(data.items.length, 0.0);
    popular = List.filled(data.items.length, false);
    head = data.items.length ~/ 5;
    popularity = List.generate(data.items.length, (i) => i)
      ..sort((i, j) {
        var result = data.itemCounts[j].compareTo(data.itemCounts[i]);
        if (result != 0) return result;
        result = data.itemMeans[j].compareTo(data.itemMeans[i]);
        return result != 0 ? result : i.compareTo(j);
      });
    for (final i in popularity.take(head)) {
      popular[i] = true;
    }
  }
  double baseline(int u, int i) => (data.mean + userBias[u]) + itemBias[i];
  void train() {
    final d = data, p = data.params;
    trainErrors[0] = trainingRMSE(d.training, (_, _) => d.mean);
    for (var sweep = 1; sweep <= 10; sweep++) {
      for (var i = 0; i < d.items.length; i++) {
        final rows = d.byItem[i];
        var total = 0.0;
        for (final v in rows) {
          total += v.value - d.mean - userBias[v.other];
        }
        itemBias[i] = total / (p.itemReg + rows.length);
      }
      for (var u = 0; u < d.users.length; u++) {
        final rows = d.byUser[u];
        var total = 0.0;
        for (final v in rows) {
          total += v.value - d.mean - itemBias[v.other];
        }
        userBias[u] = total / (p.userReg + rows.length);
      }
      log.add(
        TrainingRecord('BASELINE', sweep, trainingRMSE(d.training, baseline)),
      );
    }
    trainErrors[1] = log.last.rmse;
    final (svdModel, svdLog) = trainSVD(d);
    svd = svdModel;
    log.addAll(svdLog);
    trainErrors[5] = svdLog.last.rmse;
    final (alsModel, alsLog) = trainALS(d, userBias, itemBias);
    als = alsModel;
    log.addAll(alsLog);
    trainErrors[6] = alsLog.last.rmse;
  }

  Prediction knnPrediction(int user, int item, int size, bool byUser) {
    final d = data, candidates = <Neighbor>[];
    if (byUser) {
      for (final v in d.byItem[item]) {
        final s = neighborhood.users[user][v.other];
        if (s != null && s.value > d.params.minSimilarity)
          candidates.add(Neighbor(v.other, s.value));
      }
    } else {
      for (final v in d.byUser[user]) {
        final s = neighborhood.items[item][v.other];
        if (s != null && s.value > d.params.minSimilarity)
          candidates.add(Neighbor(v.other, s.value));
      }
    }
    final selected = largestNeighbors(candidates, size);
    if (selected.isEmpty)
      return Prediction(baseline(user, item), fallback: true);
    var numerator = 0.0, denominator = 0.0;
    for (final v in selected) {
      final rating = byUser ? d.values[v.index][item] : d.values[user][v.index],
          mean = byUser ? d.userMeans[v.index] : d.itemMeans[v.index];
      numerator += v.similarity * (rating - mean);
      denominator += v.similarity;
    }
    final mean = byUser ? d.userMeans[user] : d.itemMeans[item],
        top = byUser
            ? d.users[selected.first.index]
            : d.items[selected.first.index];
    return Prediction(
      mean + numerator / denominator,
      neighbors: selected.length,
      similarity: denominator / selected.length,
      top: top,
    );
  }

  Prediction slopePrediction(int u, int i) {
    var numerator = 0.0, denominator = 0;
    for (final v in data.byUser[u]) {
      final count = neighborhood.counts[i][v.other];
      if (count > 0) {
        numerator += (neighborhood.deviation(i, v.other) + v.value) * count;
        denominator += count;
      }
    }
    return denominator == 0
        ? Prediction(baseline(u, i), fallback: true)
        : Prediction(numerator / denominator);
  }

  Prediction predict(int method, int u, int i, int size) => switch (method) {
    0 => Prediction(data.mean),
    1 => Prediction(baseline(u, i)),
    2 => knnPrediction(u, i, size, true),
    3 => knnPrediction(u, i, size, false),
    4 => slopePrediction(u, i),
    5 => Prediction(svd.predict(u, i)),
    6 => Prediction(als.predict(u, i)),
    _ => throw StateError('unknown method'),
  };
  List<String> predictTests() {
    final lines = ['user,item,actual,${methods.join(',')}'], d = data;
    for (final row in d.test) {
      final fields = [
        '${d.users[row.user]}',
        '${d.items[row.item]}',
        '${row.value}',
      ];
      for (var m = 0; m < 7; m++) {
        final p = predict(m, row.user, row.item, d.params.neighbors),
            q = clip(p.value);
        predictions[m].add(p);
        clipped[m].add(q);
        errors[m].add(q - row.value);
        fields.add(real(q));
      }
      lines.add(fields.join(','));
    }
    for (var m = 0; m < 7; m++) {
      final ps = predictions[m];
      metrics.add(
        Metric(
          rmse(errors[m]),
          mae(errors[m]),
          ps.where((p) => p.value < 1 || p.value > 5).length,
          ps.where((p) => p.fallback).length,
        ),
      );
    }
    return lines;
  }

  void prepareRankings() {
    final d = data, selected = <int>{};
    for (final t in d.test) {
      if (t.value >= 4) {
        relevant.putIfAbsent(t.user, () => <int>{}).add(t.item);
        selected.add(t.user);
      }
    }
    for (var u = 0; u < d.users.length; u++) {
      if (relevant.containsKey(u)) evaluated.add(u);
    }
    for (final id in d.params.recommendUsers) {
      final u = d.userIndex[id];
      if (u != null) selected.add(u);
    }
    for (var u = 0; u < d.users.length; u++) {
      if (!selected.contains(u)) continue;
      final candidates = [
            for (var i = 0; i < d.items.length; i++)
              if (d.values[u][i] == 0) i,
          ],
          lists = List.generate(7, (_) => <int>[]),
          ps = List.generate(7, (_) => <int, Prediction>{});
      lists[0] = [
        for (final i in popularity)
          if (d.values[u][i] == 0) i,
      ];
      for (var m = 1; m < 7; m++) {
        final values = {
              for (final i in candidates)
                i: predict(m, u, i, d.params.neighbors),
            },
            order = [...candidates]
              ..sort((i, j) {
                final result = values[j]!.value.compareTo(values[i]!.value);
                return result != 0 ? result : i.compareTo(j);
              });
        ps[m] = values;
        lists[m] = order;
      }
      rankedLists[u] = lists;
      rankingPredictions[u] = ps;
    }
  }

  (int, int) timeRange() {
    var first = data.training.first.time, last = first;
    for (final t in data.training.skip(1)) {
      first = math.min(first, t.time);
      last = math.max(last, t.time);
    }
    return (first, last);
  }

  List<String> dataSummary() {
    final d = data, hist = List.filled(5, 0);
    for (final t in d.training) {
      hist[t.value - 1]++;
    }
    final (first, last) = timeRange();
    var up = 0, uu = 0, ip = 0, iu = 0, sp = 0;
    for (var i = 0; i < d.users.length; i++) {
      for (var j = i + 1; j < d.users.length; j++) {
        final s = neighborhood.users[i][j];
        if (s != null) {
          up++;
          if (s.value > d.params.minSimilarity) uu++;
        }
      }
    }
    for (var i = 0; i < d.items.length; i++) {
      for (var j = i + 1; j < d.items.length; j++) {
        final s = neighborhood.items[i][j];
        if (s != null) {
          ip++;
          if (s.value > d.params.minSimilarity) iu++;
        }
        if (neighborhood.counts[i][j] > 0) sp++;
      }
    }
    return [
      'data users ${d.users.length} items ${d.items.length} catalog ${d.catalog.length} ratings ${d.training.length} test ${d.test.length}',
      'density ${real(d.training.length / (d.users.length * d.items.length))} global_mean ${real(d.mean)}',
      'histogram ${ints(hist)}',
      'user_ratings ${countSummary(d.userCounts)}',
      'item_ratings ${countSummary(d.itemCounts)}',
      'timestamps first $first last $last',
      'cold_items ${d.catalog.length - d.items.length}',
      'similarities user_pairs $up usable $uu item_pairs $ip usable $iu slope_pairs $sp',
    ];
  }

  List<String> genreSummary() {
    final d = data,
        genres = {
          for (final id in data.items) ...data.catalog[id]!.genres,
        }.toList()..sort(),
        lines = ['genre_stats'];
    for (final g in genres) {
      var items = 0, ratings = 0, high = 0;
      for (var i = 0; i < d.items.length; i++) {
        if (d.catalog[d.items[i]]!.genres.contains(g)) {
          items++;
          ratings += d.itemCounts[i];
          for (final v in d.byItem[i]) {
            if (v.value >= 4) high++;
          }
        }
      }
      lines.add('genre $g items $items ratings $ratings high $high');
    }
    return lines;
  }

  List<String> timeSummary() {
    final d = data,
        buckets = data.params.buckets,
        counts = List.filled(buckets, 0),
        totals = List.filled(buckets, 0),
        users = List.generate(buckets, (_) => <int>{});
    final (first, last) = timeRange();
    for (final t in d.training) {
      final b = (t.time - first) * buckets ~/ (last - first + 1);
      counts[b]++;
      totals[b] += t.value;
      users[b].add(t.user);
    }
    return [
      'time_buckets $buckets',
      for (var b = 0; b < buckets; b++)
        'bucket ${b + 1} ratings ${counts[b]} users ${users[b].length} mean ${real(counts[b] > 0 ? totals[b] / counts[b] : double.nan)}',
    ];
  }

  List<String> ratingMetrics() => [
    'rating_metrics',
    for (var m = 0; m < 7; m++)
      '${methods[m]} rmse ${real(metrics[m].rmse)} mae ${real(metrics[m].mae)} clipped ${metrics[m].clipped} fallback ${metrics[m].fallback}',
  ];
  List<String> generalization() => [
    'generalization',
    for (final m in [0, 1, 5, 6])
      '${methods[m]} train ${real(trainErrors[m]!)} test ${real(metrics[m].rmse)} gap ${real(metrics[m].rmse - trainErrors[m]!)}',
  ];
  List<String> neighborhoodUsage() {
    final lines = ['neighborhoods k ${data.params.neighbors}'];
    for (final m in [2, 3]) {
      var count = 0, neighbors = 0;
      var similarity = 0.0;
      for (final p in predictions[m]) {
        if (!p.fallback) {
          count++;
          neighbors += p.neighbors;
          similarity += p.similarity;
        }
      }
      lines.add(
        '${methods[m]} predictions ${data.test.length} with_neighbors $count mean_neighbors ${real(count > 0 ? neighbors / count : double.nan)} mean_similarity ${real(count > 0 ? similarity / count : double.nan)}',
      );
    }
    return lines;
  }

  List<String> predictionStatistics() {
    final n = data.test.length,
        total = data.test.fold(0, (sum, t) => sum + t.value),
        mean = total / n;
    var variation = 0.0, lo = data.test.first.value, hi = data.test.first.value;
    for (final t in data.test) {
      final x = t.value - mean;
      variation += x * x;
      lo = math.min(lo, t.value);
      hi = math.max(hi, t.value);
    }
    final lines = [
      'prediction_stats actual mean ${real(mean)} std ${real(math.sqrt(variation / n))}',
    ];
    for (var m = 0; m < 7; m++) {
      final q = clipped[m], mq = sum(q) / n;
      var vq = 0.0, cov = 0.0, ql = q.first, qh = q.first;
      for (var i = 0; i < n; i++) {
        final x = q[i];
        vq += (x - mq) * (x - mq);
        cov += (x - mq) * (data.test[i].value - mean);
        ql = math.min(ql, x);
        qh = math.max(qh, x);
      }
      final correlation = ql != qh && lo != hi
          ? cov / math.sqrt(vq * variation)
          : double.nan;
      lines.add(
        '${methods[m]} mean ${real(mq)} std ${real(math.sqrt(vq / n))} correlation ${real(correlation)}',
      );
    }
    return lines;
  }

  List<String> errorBins() {
    final lines = ['error_bins edges 0.5 1.0 1.5 2.0'];
    for (var m = 0; m < 7; m++) {
      final bins = List.filled(5, 0);
      for (final e in errors[m]) {
        final b = [0.5, 1.0, 1.5, 2.0].where((edge) => e.abs() >= edge).length;
        bins[b]++;
      }
      lines.add('${methods[m]} ${ints(bins)}');
    }
    return lines;
  }

  List<String> comparison() {
    final lines = ['comparison'];
    for (var a = 0; a < 7; a++) {
      for (var b = a + 1; b < 7; b++) {
        var wins = 0, ties = 0, losses = 0;
        for (var i = 0; i < errors[a].length; i++) {
          final left = errors[a][i].abs(), right = errors[b][i].abs();
          if (left < right)
            wins++;
          else if (left == right)
            ties++;
          else
            losses++;
        }
        lines.add(
          '${methods[a]} ${methods[b]} wins $wins ties $ties losses $losses',
        );
      }
    }
    return lines;
  }

  String errorsFor(List<int> indices, bool absolute) {
    final fields = <String>[];
    for (var m = 0; m < 7; m++) {
      final es = [for (final i in indices) errors[m][i]],
          metric = absolute ? mae(es) : rmse(es);
      fields.add('${methods[m]} ${real(metric)}');
    }
    return fields.join(' ');
  }

  List<String> groupErrors(bool user) {
    final d = data,
        kind = user ? 'user' : 'item',
        bounds = user ? data.params.userGroups : data.params.itemGroups,
        groups = List.generate(bounds.length + 1, (_) => <int>[]);
    for (var i = 0; i < d.test.length; i++) {
      final t = d.test[i],
          count = user ? d.userCounts[t.user] : d.itemCounts[t.item];
      groups[groupIndex(count, bounds)].add(i);
    }
    return [
      '${kind}_groups bounds ${ints(bounds)}',
      for (var g = 0; g < groups.length; g++)
        'group ${g + 1} from ${g > 0 ? bounds[g - 1] : 1} to ${g < bounds.length ? bounds[g] - 1 : '-'} pairs ${groups[g].length} ${errorsFor(groups[g], false)}',
    ];
  }

  List<String> ratingErrors() {
    final lines = ['by_rating'];
    for (var v = 1; v <= 5; v++) {
      final indices = [
        for (var i = 0; i < data.test.length; i++)
          if (data.test[i].value == v) i,
      ];
      lines.add(
        'rating $v pairs ${indices.length} ${errorsFor(indices, true)}',
      );
    }
    return lines;
  }

  List<String> genreErrors() {
    final genres = {
          for (final t in data.test)
            ...data.catalog[data.items[t.item]]!.genres,
        }.toList()..sort(),
        lines = ['genres'];
    for (final g in genres) {
      final indices = [
        for (var i = 0; i < data.test.length; i++)
          if (data.catalog[data.items[data.test[i].item]]!.genres.contains(g))
            i,
      ];
      lines.add(
        'genre $g pairs ${indices.length} ${errorsFor(indices, false)}',
      );
    }
    return lines;
  }

  RankingMetrics userRankingMetrics(int m, int u, int cutoff) =>
      rankingMetrics(rankedLists[u]![m], relevant[u]!, cutoff);
  List<String> rankingEvaluation() {
    final count = evaluated.length,
        relevantCount = evaluated.fold(
          0,
          (sum, u) => sum + relevant[u]!.length,
        ),
        lines = ['ranking users ${evaluated.length} relevant $relevantCount'];
    for (final cutoff in data.params.cutoffs) {
      lines.add('cutoff $cutoff');
      for (var m = 0; m < 7; m++) {
        var hits = 0, hitUsers = 0;
        var recall = 0.0, ndcg = 0.0, ap = 0.0, rr = 0.0;
        for (final u in evaluated) {
          final v = userRankingMetrics(m, u, cutoff);
          hits += v.hits;
          if (v.hits >= 1) hitUsers++;
          recall += v.recall;
          ndcg += v.ndcg;
          ap += v.ap;
          rr += v.rr;
        }
        lines.add(
          '  ${rankings[m]} precision ${real(hits / (cutoff * count))} recall ${real(recall / count)} ndcg ${real(ndcg / count)} map ${real(ap / count)} mrr ${real(rr / count)} hit_rate ${real(hitUsers / count)}',
        );
      }
    }
    return lines;
  }

  List<String> beyondAccuracy() {
    final d = data,
        size = data.params.topN,
        count = evaluated.length,
        pairs = size * (size - 1) ~/ 2,
        lines = ['beyond_accuracy top_n ${data.params.topN} head $head'];
    for (var m = 0; m < 7; m++) {
      final distinct = <int>{};
      var diversity = 0, popularityTotal = 0, longTail = 0;
      var novelty = 0.0, similarity = 0.0;
      for (final u in evaluated) {
        final ranked = rankedLists[u]![m].take(size).toList(),
            genres = <String>{};
        var nov = 0.0;
        for (final i in ranked) {
          distinct.add(i);
          genres.addAll(d.catalog[d.items[i]]!.genres);
          nov += log2(d.users.length / d.itemCounts[i]);
          popularityTotal += d.itemCounts[i];
          if (!popular[i]) longTail++;
        }
        diversity += genres.length;
        novelty += nov / size;
        var pairSum = 0.0;
        for (var a = 0; a < size; a++) {
          for (var b = a + 1; b < size; b++) {
            final s = neighborhood.items[ranked[a]][ranked[b]];
            if (s != null) pairSum += s.value;
          }
        }
        similarity += pairSum / pairs;
      }
      lines.add(
        '${rankings[m]} coverage ${real(distinct.length / d.items.length)} diversity ${real(diversity / count)} novelty ${real(novelty / count)} popularity ${real(popularityTotal / (size * count))} long_tail ${real(longTail / (size * count))} similarity ${real(similarity / count)}',
      );
    }
    return lines;
  }

  List<String> rankingGroups() {
    final bounds = data.params.userGroups,
        size = data.params.topN,
        groups = List.generate(bounds.length + 1, (_) => <int>[]);
    for (final u in evaluated) {
      groups[groupIndex(data.userCounts[u], bounds)].add(u);
    }
    final lines = ['ranking_groups top_n $size bounds ${ints(bounds)}'];
    for (var g = 0; g < groups.length; g++) {
      final users = groups[g],
          fields = ['group ${g + 1} users ${groups[g].length}'];
      for (var m = 0; m < 7; m++) {
        var mean = double.nan;
        if (users.isNotEmpty) {
          var total = 0.0;
          for (final u in users) {
            total += userRankingMetrics(m, u, size).ndcg;
          }
          mean = total / users.length;
        }
        fields.add('${rankings[m]} ${real(mean)}');
      }
      lines.add(fields.join(' '));
    }
    return lines;
  }

  List<String> agreement() {
    final size = data.params.topN,
        lines = ['agreement top_n ${data.params.topN}'];
    for (var a = 0; a < 7; a++) {
      for (var b = a + 1; b < 7; b++) {
        var total = 0.0;
        for (final u in evaluated) {
          final left = rankedLists[u]![a].take(size).toSet(),
              right = rankedLists[u]![b].take(size).toSet(),
              intersection = left.intersection(right).length;
          total += intersection / (2 * size - intersection);
        }
        lines.add(
          '${rankings[a]} ${rankings[b]} jaccard ${real(total / evaluated.length)}',
        );
      }
    }
    return lines;
  }

  List<String> neighborGrid() {
    final lines = ['neighbor_grid'],
        best = List.filled(2, 0),
        values = List.filled(2, double.infinity);
    for (final size in data.params.neighborGrid) {
      final fields = ['k $size'];
      for (var j = 0; j < 2; j++) {
        final m = j + 2, es = <double>[];
        for (final t in data.test) {
          final p = predict(m, t.user, t.item, size);
          es.add(clip(p.value) - t.value);
        }
        final error = rmse(es);
        fields.add('${methods[m]} ${real(error)}');
        if (error < values[j]) {
          values[j] = error;
          best[j] = size;
        }
      }
      lines.add(fields.join(' '));
    }
    lines.add('best USER_KNN ${best[0]} ITEM_KNN ${best[1]}');
    return lines;
  }

  List<String> biasLists() {
    final d = data, lines = ['biases'];
    for (final item in [true, false]) {
      final biases = item ? itemBias : userBias,
          counts = item ? d.itemCounts : d.userCounts,
          means = item ? d.itemMeans : d.userMeans,
          ids = item ? d.items : d.users,
          kind = item ? 'item' : 'user';
      for (final high in [true, false]) {
        final order = List.generate(ids.length, (i) => i)
              ..sort((a, b) {
                final result = high
                    ? biases[b].compareTo(biases[a])
                    : biases[a].compareTo(biases[b]);
                return result != 0 ? result : a.compareTo(b);
              }),
            label = high ? 'high' : 'low';
        for (final i in order.take(d.params.listSize)) {
          var line =
              '${kind}_$label ${ids[i]} bias ${real(biases[i])} count ${counts[i]} mean ${real(means[i])}';
          if (item) line += ' ${d.catalog[ids[i]]!.title}';
          lines.add(line);
        }
      }
    }
    return lines;
  }

  List<String> evaluationReport() => separateSections([
    dataSummary(),
    genreSummary(),
    timeSummary(),
    ratingMetrics(),
    generalization(),
    neighborhoodUsage(),
    predictionStatistics(),
    errorBins(),
    comparison(),
    groupErrors(true),
    groupErrors(false),
    ratingErrors(),
    genreErrors(),
    rankingEvaluation(),
    beyondAccuracy(),
    rankingGroups(),
    agreement(),
    neighborGrid(),
    biasLists(),
  ]);
  List<GenreCount> preferredGenres(int u, bool liked) {
    final counts = <String, int>{};
    for (final v in data.byUser[u]) {
      final qualifies = liked ? v.value >= 4 : v.value <= 2;
      if (qualifies) {
        for (final g in data.catalog[data.items[v.other]]!.genres) {
          counts[g] = (counts[g] ?? 0) + 1;
        }
      }
    }
    final out =
        [for (final entry in counts.entries) GenreCount(entry.key, entry.value)]
          ..sort((a, b) {
            final result = b.count.compareTo(a.count);
            return result != 0 ? result : a.genre.compareTo(b.genre);
          });
    return out.take(3).toList();
  }

  String popularityLine(int rank, int item) =>
      '  $rank ${data.items[item]} count ${data.itemCounts[item]} mean ${real(data.itemMeans[item])} ${data.catalog[data.items[item]]!.title}';
  String recommendationLine(int u, int m, int rank, int item) {
    if (m == 0) return popularityLine(rank, item);
    final p = rankingPredictions[u]![m][item]!;
    var line = '  $rank ${data.items[item]} ${real(p.value)}';
    if (m == 2 || m == 3) line += ' via ${optional(p.top)}';
    return '$line ${data.catalog[data.items[item]]!.title}';
  }

  List<String> knownUserRecommendations(int u) {
    final d = data,
        lines = [
          'user ${data.users[u]} ratings ${data.userCounts[u]} mean ${real(data.userMeans[u])} bias ${real(userBias[u])}',
        ],
        liked = preferredGenres(u, true),
        disliked = preferredGenres(u, false);
    for (var i = 0; i < 2; i++) {
      final label = ['liked_genres', 'disliked_genres'][i],
          list = [liked, disliked][i],
          fields = [for (final g in list) '${g.genre} ${g.count}'];
      lines.add('$label ${fields.isEmpty ? '-' : fields.join(' ')}');
    }
    final recent = d.training.where((t) => t.user == u).toList()
      ..sort((a, b) {
        final result = b.time.compareTo(a.time);
        return result != 0 ? result : a.item.compareTo(b.item);
      });
    lines.add(
      'recent ${[for (final t in recent.take(3)) '${d.items[t.item]} ${t.value}'].join(' ')}',
    );
    final candidates = <Neighbor>[];
    for (var v = 0; v < d.users.length; v++) {
      final s = neighborhood.users[u][v];
      if (s != null && s.value > d.params.minSimilarity)
        candidates.add(Neighbor(v, s.value));
    }
    for (final n in largestNeighbors(candidates, d.params.listSize)) {
      lines.add(
        'neighbor ${d.users[n.index]} similarity ${real(n.similarity)} common ${neighborhood.users[u][n.index]!.common}',
      );
    }
    for (var j = 0; j < d.test.length; j++) {
      final t = d.test[j];
      if (t.user == u)
        lines.add(
          'heldout ${d.items[t.item]} actual ${t.value} ${[for (var m = 0; m < 7; m++) real(clipped[m][j])].join(' ')}',
        );
    }
    final likedNames = liked.map((g) => g.genre).toSet();
    for (var m = 0; m < 7; m++) {
      final ranked = rankedLists[u]![m].take(d.params.topN).toList(),
          matched = ranked
              .where(
                (i) => d.catalog[d.items[i]]!.genres.any(likedNames.contains),
              )
              .length;
      lines.add('list ${rankings[m]} genre_match $matched');
      for (var rank = 0; rank < ranked.length; rank++) {
        lines.add(recommendationLine(u, m, rank + 1, ranked[rank]));
      }
    }
    return lines;
  }

  List<String> recommendations() {
    final sections = <List<String>>[];
    for (final id in data.params.recommendUsers) {
      final u = data.userIndex[id];
      if (u != null) {
        sections.add(knownUserRecommendations(u));
      } else {
        sections.add([
          'user $id unknown',
          'list POPULAR',
          for (var rank = 0; rank < data.params.topN; rank++)
            popularityLine(rank + 1, popularity[rank]),
        ]);
      }
    }
    return separateSections(sections);
  }

  List<String> similarItems() {
    final d = data,
        size = data.params.listSize,
        norms = [for (final v in svd.items) dot(v, v)],
        sections = <List<String>>[];
    for (final id in d.params.similarItems) {
      final i = d.itemIndex[id]!,
          info = d.catalog[id]!,
          lines = [
            'item $id ratings ${d.itemCounts[i]} mean ${real(d.itemMeans[i])} bias ${real(itemBias[i])} genres ${info.genreText} title ${info.title}',
            'cosine',
          ];
      var candidates = <Neighbor>[];
      for (var j = 0; j < d.items.length; j++) {
        final s = neighborhood.items[i][j];
        if (s != null) candidates.add(Neighbor(j, s.value));
      }
      final cosine = largestNeighbors(candidates, size);
      for (var rank = 0; rank < cosine.length; rank++) {
        final n = cosine[rank];
        lines.add(
          '  ${rank + 1} ${d.items[n.index]} similarity ${real(n.similarity)} common ${neighborhood.items[i][n.index]!.common} ${d.catalog[d.items[n.index]]!.title}',
        );
      }
      candidates = [];
      for (var j = 0; j < d.items.length; j++) {
        if (i != j) {
          final value =
              dot(svd.items[i], svd.items[j]) / math.sqrt(norms[i] * norms[j]);
          candidates.add(Neighbor(j, value));
        }
      }
      lines.add('factors');
      final factors = largestNeighbors(candidates, size);
      for (var rank = 0; rank < factors.length; rank++) {
        final n = factors[rank];
        lines.add(
          '  ${rank + 1} ${d.items[n.index]} similarity ${real(n.similarity)} ${d.catalog[d.items[n.index]]!.title}',
        );
      }
      final common =
          [
            for (var j = 0; j < d.items.length; j++)
              if (neighborhood.counts[i][j] >= 1) j,
          ]..sort((j, k) {
            final result = neighborhood.counts[i][k].compareTo(
              neighborhood.counts[i][j],
            );
            return result != 0 ? result : j.compareTo(k);
          });
      lines.add('co_rated');
      for (var rank = 0; rank < math.min(size, common.length); rank++) {
        final j = common[rank];
        lines.add(
          '  ${rank + 1} ${d.items[j]} common ${neighborhood.counts[i][j]} ${d.catalog[d.items[j]]!.title}',
        );
      }
      common.sort((j, k) {
        var result = neighborhood
            .deviation(k, i)
            .compareTo(neighborhood.deviation(j, i));
        if (result != 0) return result;
        result = neighborhood.counts[k][i].compareTo(neighborhood.counts[j][i]);
        return result != 0 ? result : j.compareTo(k);
      });
      lines.add('slope_one');
      for (var rank = 0; rank < math.min(size, common.length); rank++) {
        final j = common[rank];
        lines.add(
          '  ${rank + 1} ${d.items[j]} difference ${neighborhood.differences[j][i]} common ${neighborhood.counts[j][i]} ${d.catalog[d.items[j]]!.title}',
        );
      }
      sections.add(lines);
    }
    return separateSections(sections);
  }

  List<String> trainingLog() => [
    'method,epoch,train_rmse',
    for (final t in log) '${t.method},${t.epoch},${real(t.rmse)}',
  ];
}

void main() {
  final r = Recommender(readInputs());
  r.train();
  final predictions = r.predictTests();
  r.prepareRankings();
  writeLines('predictions.csv', predictions);
  writeLines('evaluation.txt', r.evaluationReport());
  writeLines('recommendations.txt', r.recommendations());
  writeLines('similar_items.txt', r.similarItems());
  writeLines('training_log.csv', r.trainingLog());
}
