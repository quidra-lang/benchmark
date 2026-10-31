part of 'main.dart';

double clip(double p) => p < 1
    ? 1
    : p > 5
    ? 5
    : p;
double rmse(List<double> errors) {
  if (errors.isEmpty) return double.nan;
  var sum = 0.0;
  for (final e in errors) {
    sum += e * e;
  }
  return math.sqrt(sum / errors.length);
}

double mae(List<double> errors) {
  if (errors.isEmpty) return double.nan;
  var sum = 0.0;
  for (final e in errors) {
    sum += e.abs();
  }
  return sum / errors.length;
}

double trainingRMSE(List<Rating> training, double Function(int, int) predict) {
  var sum = 0.0;
  for (final r in training) {
    final e = r.value - predict(r.user, r.item);
    sum += e * e;
  }
  return math.sqrt(sum / training.length);
}

double log2(double x) => math.log(x) / math.ln2;
double rankWeight(int rank) => 1 / log2((rank + 1).toDouble());

class RankingMetrics {
  final int hits;
  final double recall, ndcg, ap, rr;
  RankingMetrics(this.hits, this.recall, this.ndcg, this.ap, this.rr);
}

RankingMetrics rankingMetrics(List<int> ranked, Set<int> relevant, int cutoff) {
  var hits = 0;
  var dcg = 0.0, ap = 0.0, rr = 0.0;
  for (var j = 0; j < cutoff; j++) {
    final i = ranked[j], rank = j + 1;
    if (relevant.contains(i)) {
      hits++;
      dcg += rankWeight(rank);
      ap += hits / rank;
      if (rr == 0) rr = 1 / rank;
    }
  }
  final ideal = math.min(cutoff, relevant.length);
  var idcg = 0.0;
  for (var t = 1; t <= ideal; t++) {
    idcg += rankWeight(t);
  }
  return RankingMetrics(
    hits,
    hits / relevant.length,
    dcg / idcg,
    ap / ideal,
    rr,
  );
}
