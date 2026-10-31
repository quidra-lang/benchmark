part of 'main.dart';

const weights = ['logrank', 'gehan_wilcoxon', 'tarone_ware'];

class WeightedTest {
  final List<String> groups;
  final List<int> events;
  final List<double> observed, expected;
  final List<List<double>> covariance;
  double statistic = 0, p = 0;
  int degrees = 0;
  WeightedTest(this.groups)
    : events = List.filled(groups.length, 0),
      observed = List.filled(groups.length, 0.0),
      expected = List.filled(groups.length, 0.0),
      covariance = zeros(groups.length);
}

WeightedTest weightedTotals(
  List<Subject> subjects,
  List<String> groups,
  String weight,
  int population,
) {
  final result = WeightedTest(groups),
      collections = [
        for (final g in groups) subjects.where((s) => s.group == g).toList(),
      ],
      times =
          subjects
              .where((s) => s.event == 1)
              .map((s) => s.time)
              .toSet()
              .toList()
            ..sort();
  for (final time in times) {
    final risk = List.filled(groups.length, 0),
        deaths = List.filled(groups.length, 0);
    var n = 0, d = 0;
    for (var k = 0; k < groups.length; k++) {
      for (final s in collections[k]) {
        if (s.time >= time) risk[k]++;
        if (s.time == time) deaths[k] += s.event;
      }
      n += risk[k];
      d += deaths[k];
    }
    final value = weight == 'logrank'
        ? 1.0
        : weight == 'gehan_wilcoxon'
        ? n / population
        : math.sqrt(n / population);
    for (var h = 0; h < groups.length; h++) {
      result.events[h] += deaths[h];
      result.observed[h] += value * deaths[h];
      result.expected[h] += value * (d * risk[h] / n);
      if (n < 2) continue;
      final factor = value * value * (d * (n - d) / ((n - 1) * n * n));
      for (var l = 0; l < groups.length; l++) {
        final multiple = h == l
            ? risk[h] * (n - risk[h])
            : -(risk[h] * risk[l]);
        result.covariance[h][l] += factor * multiple;
      }
    }
  }
  return result;
}

WeightedTest finishTest(WeightedTest result) {
  final n = result.groups.length - 1,
      u = [for (var h = 0; h < n; h++) result.observed[h] - result.expected[h]],
      matrix = [
        for (var h = 0; h < n; h++) result.covariance[h].take(n).toList(),
      ],
      x = solve(matrix, u);
  var stat = 0.0;
  for (var h = 0; h < n; h++) {
    stat += u[h] * x[h];
  }
  result.statistic = stat;
  result.degrees = n;
  result.p = chiP(stat, n);
  return result;
}

WeightedTest weightedTest(
  List<Subject> subjects,
  List<String> groups,
  String weight,
  int population,
) => finishTest(weightedTotals(subjects, groups, weight, population));
WeightedTest combineStrata(List<WeightedTest> strata, List<String> groups) {
  final r = WeightedTest(groups);
  for (final s in strata) {
    for (var h = 0; h < groups.length; h++) {
      r.events[h] += s.events[h];
      r.observed[h] += s.observed[h];
      r.expected[h] += s.expected[h];
      for (var l = 0; l < groups.length; l++) {
        r.covariance[h][l] += s.covariance[h][l];
      }
    }
  }
  return finishTest(r);
}
