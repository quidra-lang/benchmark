import 'dart:io';
import 'dart:math' as math;

part 'dataset.dart';
part 'estimators.dart';
part 'group_tests.dart';
part 'cox.dart';
part 'plot.dart';
part 'numerics.dart';

String number(double value) {
  if (value.isNaN) return 'NA';
  final s = value.toStringAsFixed(4);
  return s == '-0.0000' ? '0.0000' : s;
}

String day(int t) => t == 0 ? 'NA' : '$t';
String reals(Iterable<double> values) => values.map(number).join(' ');
String ints(Iterable<int> values) => values.join(' ');
int eventCount(List<Subject> subjects) =>
    subjects.fold(0, (sum, s) => sum + s.event);
int riskCount(List<Subject> subjects, int time) =>
    subjects.where((s) => s.time >= time).length;
int percentileTime(List<KMRow> rows, double threshold, int column) {
  for (final r in rows) {
    var v = column == 0
        ? r.survival
        : column == 1
        ? r.lower
        : r.upper;
    if (r.survival == 0) v = 0;
    if (!v.isNaN && v <= threshold) return r.time;
  }
  return 0;
}

List<double> restrictedMean(List<KMRow> rows, int tau) {
  final selected = rows.where((r) => r.time <= tau).toList(),
      times = [0, for (final r in selected) r.time, tau],
      survival = [1.0, for (final r in selected) r.survival],
      tails = [
        for (var i = 0; i < survival.length; i++)
          survival[i] * (times[i + 1] - times[i]),
      ];
  for (var i = tails.length - 2; i >= 0; i--) {
    tails[i] = tails[i] + tails[i + 1];
  }
  var variance = 0.0;
  for (var j = 0; j < selected.length; j++) {
    final i = j + 1, r = selected[j];
    variance +=
        tails[i] * tails[i] * (r.events / (r.risk * (r.risk - r.events)));
  }
  final mean = tails[0], se = math.sqrt(variance);
  return [mean, se, mean - z95 * se, mean + z95 * se];
}

class Summary {
  final List<KMRow> rows;
  final List<LifeRow> life;
  final int events, maximum, personDays, followup;
  final double rate, rateLower, rateUpper, lifeMedian;
  final List<List<int>> percentiles;
  final List<double> rmst;
  Summary(
    this.rows,
    this.life,
    this.events,
    this.maximum,
    this.personDays,
    this.followup,
    this.rate,
    this.rateLower,
    this.rateUpper,
    this.lifeMedian,
    this.percentiles,
    this.rmst,
  );
}

Summary collectionSummary(List<Subject> subjects, Params p) {
  final rows = kaplanMeier(subjects),
      life = lifeTable(subjects, p.width, p.intervals),
      events = eventCount(subjects),
      personDays = subjects.fold(0, (sum, s) => sum + s.time),
      maximum = subjects.map((s) => s.time).reduce(math.max),
      rate = 1000 * events / personDays,
      eta = z95 / math.sqrt(events),
      followup = percentileTime(
        kaplanMeier(subjects.map((s) => s.reversed()).toList()),
        0.5,
        0,
      );
  var lifeMedian = double.nan, previous = 1.0;
  for (final r in life) {
    if (r.survival <= 0.5) {
      lifeMedian =
          r.start + p.width * (previous - 0.5) / (previous - r.survival);
      break;
    }
    previous = r.survival;
  }
  final percentiles = <List<int>>[];
  for (var j = 0; j < 3; j++) {
    final q = [0.75, 0.5, 0.25][j];
    percentiles.add([
      25 * (j + 1),
      percentileTime(rows, q, 0),
      percentileTime(rows, q, 1),
      percentileTime(rows, q, 2),
    ]);
  }
  return Summary(
    rows,
    life,
    events,
    maximum,
    personDays,
    followup,
    rate,
    math.exp(math.log(rate) - eta),
    math.exp(math.log(rate) + eta),
    lifeMedian,
    percentiles,
    restrictedMean(rows, p.tau),
  );
}

String variableValue(Subject s, String name) =>
    name == 'sex' ? s.sex : '${s.stage}';
List<String> variableLevels(List<Subject> subjects, String name) =>
    subjects.map((s) => variableValue(s, name)).toSet().toList()..sort();
List<String> groupLines(WeightedTest t) => [
  for (var h = 0; h < t.groups.length; h++)
    '  group ${t.groups[h]} events ${t.events[h]} observed ${number(t.observed[h])} expected ${number(t.expected[h])} o_minus_e ${number(t.observed[h] - t.expected[h])} variance ${number(t.covariance[h][h])}',
];
String testFields(WeightedTest t) =>
    'chisq ${number(t.statistic)} df ${t.degrees} p ${number(t.p)}';

class TwoGroup {
  final WeightedTest test;
  final double hr, logHR, variance, lower, upper;
  TwoGroup(
    this.test,
    this.hr,
    this.logHR,
    this.variance,
    this.lower,
    this.upper,
  );
}

TwoGroup twoGroup(List<Subject> subjects, List<String> groups, int population) {
  final t = weightedTest(subjects, groups, 'logrank', population),
      hr = (t.observed[1] / t.expected[1]) / (t.observed[0] / t.expected[0]),
      variance = 1 / t.expected[0] + 1 / t.expected[1],
      l = math.log(hr);
  return TwoGroup(
    t,
    hr,
    l,
    variance,
    math.exp(l - z95 * math.sqrt(variance)),
    math.exp(l + z95 * math.sqrt(variance)),
  );
}

String differenceFields(double delta, double se) {
  final stat = delta / se;
  return 'difference ${number(delta)} se ${number(se)} lower ${number(delta - z95 * se)} upper ${number(delta + z95 * se)} z ${number(stat)} p ${number(chiP(stat * stat, 1))}';
}

bool baselineName(String name) =>
    name == 'age' || name == 'male' || name == 'stage';
List<List<int>> covariateVectors(List<Subject> subjects, List<String> names) =>
    [
      for (final s in subjects)
        [
          for (final name in names)
            switch (name) {
              'age' => s.age,
              'stage' => s.stage,
              'male' => s.sex == 'M' ? 1 : 0,
              _ => s.group == name ? 1 : 0,
            },
        ],
    ];
String coefficientFields(double coef, double se) {
  final stat = coef / se;
  return 'coef ${number(coef)} se ${number(se)} z ${number(stat)} p ${number(chiP(stat * stat, 1))} hr ${number(math.exp(coef))} lower ${number(math.exp(coef - z95 * se))} upper ${number(math.exp(coef + z95 * se))}';
}

List<String> coefficientLines(
  List<String> names,
  List<double> beta,
  List<List<double>> cov,
) {
  final lines = [
        for (var i = 0; i < names.length; i++)
          'term ${names[i]} ${coefficientFields(beta[i], math.sqrt(cov[i][i]))}',
      ],
      indices = [
        for (var i = 0; i < names.length; i++)
          if (!baselineName(names[i])) i,
      ];
  for (var i = 0; i < indices.length; i++) {
    final c = indices[i];
    for (final d in indices.skip(i + 1)) {
      final coef = beta[d] - beta[c],
          se = math.sqrt(cov[d][d] + cov[c][c] - 2 * cov[c][d]);
      lines.add(
        'contrast ${names[d]} vs ${names[c]} ${coefficientFields(coef, se)}',
      );
    }
  }
  return lines;
}

List<String> coxTestLines(
  List<Subject> subjects,
  List<List<int>> vectors,
  List<String> names,
  CoxModel model,
) {
  final p = names.length,
      f = model.finalEvaluation,
      n = model.nullEvaluation,
      lr = 2 * (f.loglik - n.loglik);
  var wald = 0.0;
  for (var c = 0; c < p; c++) {
    var inner = 0.0;
    for (var d = 0; d < p; d++) {
      inner += f.information[c][d] * model.beta[d];
    }
    wald += model.beta[c] * inner;
  }
  final solution = solve(n.information, n.score);
  var score = 0.0;
  for (var c = 0; c < p; c++) {
    score += n.score[c] * solution[c];
  }
  final values = [lr, wald, score],
      labels = ['likelihood_ratio', 'wald', 'score'],
      lines = [
        for (var i = 0; i < 3; i++)
          '${labels[i]} chisq ${number(values[i])} df $p p ${number(chiP(values[i], p))}',
      ];
  for (var c = 0; c < p; c++) {
    var ll = n.loglik;
    if (p >= 2) {
      final reduced = [
        for (final x in vectors) [...x.take(c), ...x.skip(c + 1)],
      ];
      ll = fitCox(subjects, reduced).finalEvaluation.loglik;
    }
    final stat = 2 * (f.loglik - ll);
    lines.add(
      'drop ${names[c]} loglik ${number(ll)} chisq ${number(stat)} df 1 p ${number(chiP(stat, 1))}',
    );
  }
  return lines;
}

String concordanceLine(
  List<Subject> subjects,
  List<List<int>> vectors,
  List<double> predictors,
) {
  var comparable = 0, concordant = 0, tied = 0;
  for (var i = 0; i < subjects.length; i++) {
    final first = subjects[i];
    if (first.event == 0) continue;
    for (var j = 0; j < subjects.length; j++) {
      final second = subjects[j];
      if (i == j ||
          !(first.time < second.time ||
              first.time == second.time && second.event == 0))
        continue;
      comparable++;
      var equal = true;
      for (var c = 0; c < vectors[i].length; c++) {
        if (vectors[i][c] != vectors[j][c]) {
          equal = false;
          break;
        }
      }
      if (equal)
        tied++;
      else if (predictors[i] > predictors[j])
        concordant++;
    }
  }
  return 'concordance ${number((2 * concordant + tied) / (2 * comparable))} comparable $comparable concordant $concordant tied $tied';
}

List<String> proportionalLines(
  List<Subject> subjects,
  List<List<int>> vectors,
  List<String> names,
  CoxEvaluation e,
) {
  final order =
          [
            for (var i = 0; i < subjects.length; i++)
              if (subjects[i].event == 1) i,
          ]..sort((i, j) {
            final result = subjects[i].time.compareTo(subjects[j].time);
            return result != 0
                ? result
                : subjects[i].id.compareTo(subjects[j].id);
          }),
      count = order.length,
      meanTime = order.fold(0, (sum, i) => sum + subjects[i].time) / count,
      lines = <String>[];
  for (var c = 0; c < names.length; c++) {
    final residuals = <double>[];
    var sum = 0.0;
    for (final i in order) {
      final sums = e.sums[subjects[i].time]!,
          value = vectors[i][c] - sums.s1[c] / sums.s0;
      residuals.add(value);
      sum += value;
    }
    final mean = sum / count;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var j = 0; j < count; j++) {
      final x = residuals[j] - mean, y = subjects[order[j]].time - meanTime;
      sxy += x * y;
      sxx += x * x;
      syy += y * y;
    }
    final rho = sxy / math.sqrt(sxx * syy),
        stat = 0.5 * math.log((1 + rho) / (1 - rho)) * math.sqrt(count - 3);
    lines.add(
      'ph_check ${names[c]} rho ${number(rho)} z ${number(stat)} p ${number(chiP(stat * stat, 1))}',
    );
  }
  return lines;
}

class HazardRow {
  final int time;
  final double cumulative;
  HazardRow(this.time, this.cumulative);
}

List<HazardRow> baselineHazard(CoxEvaluation e) {
  final times = e.sums.keys.toList()..sort(), rows = <HazardRow>[];
  var cumulative = 0.0;
  for (final t in times) {
    final s = e.sums[t]!;
    cumulative += s.events / s.s0;
    rows.add(HazardRow(t, cumulative));
  }
  return rows;
}

double hazardAt(List<HazardRow> rows, int time) {
  for (var j = rows.length - 1; j >= 0; j--) {
    if (rows[j].time <= time) return rows[j].cumulative;
  }
  return 0;
}

class Residual {
  final Subject subject;
  final double martingale, deviance;
  Residual(this.subject, this.martingale, this.deviance);
}

List<String> residualLines(
  List<Subject> subjects,
  CoxEvaluation e,
  List<HazardRow> hazard,
  int count,
) {
  final rows = <Residual>[];
  for (var i = 0; i < subjects.length; i++) {
    final s = subjects[i],
        m = s.event - hazardAt(hazard, s.time) * math.exp(e.predictors[i]);
    var d = s.event == 1
        ? math.sqrt(-2 * (m + math.log(1 - m)))
        : math.sqrt(-2 * m);
    if (!(m > 0)) d = -d;
    rows.add(Residual(s, m, d));
  }
  rows.sort((a, b) {
    final result = b.deviance.abs().compareTo(a.deviance.abs());
    return result != 0 ? result : a.subject.id.compareTo(b.subject.id);
  });
  return [
    'residuals top $count',
    for (final r in rows.take(count))
      '  id ${r.subject.id} group ${r.subject.group} time ${r.subject.time} event ${r.subject.event} martingale ${number(r.martingale)} deviance ${number(r.deviance)}',
  ];
}

List<String> adjustedLines(
  List<List<int>> vectors,
  List<String> names,
  List<double> beta,
  List<String> groups,
  List<int> times,
  List<HazardRow> hazard,
) {
  final means = <String, double>{}, fields = <String>[];
  for (var c = 0; c < names.length; c++) {
    final name = names[c];
    if (baselineName(name)) {
      final mean = vectors.fold(0, (sum, x) => sum + x[c]) / vectors.length;
      means[name] = mean;
      fields.add('$name ${number(mean)}');
    }
  }
  final lines = [
        'adjusted_survival mean ${fields.isEmpty ? 'none' : fields.join(' ')}',
      ],
      risks = <double>[];
  for (final group in groups) {
    var theta = 0.0;
    for (var c = 0; c < names.length; c++) {
      final name = names[c], v = means[name] ?? (name == group ? 1.0 : 0.0);
      theta += beta[c] * v;
    }
    risks.add(math.exp(theta));
  }
  for (final time in times) {
    final cumulative = hazardAt(hazard, time);
    lines.add(
      '  at $time ${[for (var g = 0; g < groups.length; g++) '${groups[g]} ${number(math.exp(-cumulative * risks[g]))}'].join(' ')}',
    );
  }
  final medians = <String>[];
  for (var g = 0; g < groups.length; g++) {
    var median = 0;
    for (final r in hazard) {
      if (math.exp(-r.cumulative * risks[g]) <= 0.5) {
        median = r.time;
        break;
      }
    }
    medians.add('${groups[g]} ${day(median)}');
  }
  lines.add('  median ${medians.join(' ')}');
  return lines;
}

class Analysis {
  final List<Subject> subjects;
  final Params params;
  final names = <String>[],
      collections = <List<Subject>>[],
      summaries = <Summary>[];
  Analysis(this.subjects, this.params) {
    names.addAll([...params.groups, 'all']);
    for (final name in names) {
      final rows = name == 'all'
          ? subjects
          : subjects.where((s) => s.group == name).toList();
      collections.add(rows);
      summaries.add(collectionSummary(rows, params));
    }
  }
  List<String> kmTables() {
    final sections = <List<String>>[];
    for (var k = 0; k < names.length; k++) {
      final name = names[k],
          s = summaries[k],
          rows = collections[k],
          v = s.rmst,
          lines = [
            'group $name subjects ${rows.length} events ${s.events} censored ${rows.length - s.events} max_time ${s.maximum}',
            'person_days ${s.personDays} rate ${number(s.rate)} lower ${number(s.rateLower)} upper ${number(s.rateUpper)}',
            'followup_median ${day(s.followup)}',
            'life_table_median ${number(s.lifeMedian)}',
          ];
      for (final p in s.percentiles) {
        lines.add(
          'percentile ${p[0]} time ${day(p[1])} lower ${day(p[2])} upper ${day(p[3])}',
        );
      }
      lines.add(
        'rmst tau ${params.tau} estimate ${number(v[0])} se ${number(v[1])} lower ${number(v[2])} upper ${number(v[3])}',
      );
      for (final time in params.times) {
        final r = rowAt(s.rows, time),
            events = rows
                .where((s) => s.time <= time)
                .fold(0, (sum, s) => sum + s.event);
        lines.add(
          'at $time at_risk ${riskCount(rows, time)} events $events survival ${number(r.survival)} std_err ${number(r.se)} lower ${number(r.lower)} upper ${number(r.upper)} cum_hazard ${number(r.hazard)} hazard_se ${number(r.hazardSE)}',
        );
      }
      lines.add(
        [
          'time',
          'at_risk',
          'events',
          'censored',
          'survival',
          'std_err',
          'lower',
          'upper',
          'cum_haz',
          'haz_se',
        ].map((s) => s.padLeft(9)).join(),
      );
      for (final r in s.rows) {
        final fields = [
          '${r.time}',
          '${r.risk}',
          '${r.events}',
          '${r.censored}',
          number(r.survival),
          number(r.se),
          number(r.lower),
          number(r.upper),
          number(r.hazard),
          number(r.hazardSE),
        ];
        lines.add(fields.map((s) => s.padLeft(9)).join());
      }
      sections.add(lines);
    }
    return joinSections(sections);
  }

  List<String> lifeLines() => [
    'group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard',
    for (var k = 0; k < names.length; k++)
      for (final r in summaries[k].life)
        '${names[k]},${r.start}-${r.end},${r.risk},${r.events},${r.withdrawn},${r.exposed.toStringAsFixed(1)},${number(r.q)},${number(r.survival)},${number(r.se)},${number(r.hazard)}',
  ];
  List<String> baselineLines() {
    final lines = ['baseline'];
    for (var k = 0; k < names.length; k++) {
      final rows = collections[k],
          ages = rows.map((s) => s.age).toList()..sort(),
          mean = rows.fold(0, (sum, s) => sum + s.age) / rows.length;
      var variance = 0.0, male = 0;
      final stages = List.filled(4, 0);
      for (final s in rows) {
        final delta = s.age - mean;
        variance += delta * delta;
        if (s.sex == 'M') male++;
        stages[s.stage - 1]++;
      }
      final median =
          (ages[(rows.length - 1) ~/ 2] + ages[rows.length ~/ 2]) / 2;
      lines.add(
        '  group ${names[k]} subjects ${rows.length} age_mean ${number(mean)} age_sd ${number(math.sqrt(variance / (rows.length - 1)))} age_median ${median.toStringAsFixed(1)} male $male stage ${ints(stages)}',
      );
    }
    final ranked = [...subjects]
          ..sort((a, b) {
            final result = a.age.compareTo(b.age);
            return result != 0 ? result : a.id.compareTo(b.id);
          }),
        ranks = <int, double>{};
    var ties = 0, start = 0;
    while (start < ranked.length) {
      var end = start + 1;
      while (end < ranked.length && ranked[end].age == ranked[start].age) {
        end++;
      }
      final rank = (start + 1 + end) / 2;
      for (final s in ranked.sublist(start, end)) {
        ranks[s.id] = rank;
      }
      final size = end - start;
      ties += size * size * size - size;
      start = end;
    }
    var weighted = 0.0;
    for (final rows in collections.take(params.groups.length)) {
      var sum = 0.0;
      for (final s in rows) {
        sum += ranks[s.id]!;
      }
      weighted += sum * sum / rows.length;
    }
    final n = subjects.length,
        raw = 12 * weighted / (n * (n + 1)) - 3 * (n + 1),
        stat = raw / (1 - ties / (n * n * n - n)),
        df = params.groups.length - 1;
    lines.add(
      '  age kruskal_wallis chisq ${number(stat)} df $df p ${number(chiP(stat, df))}',
    );
    for (final variable in ['sex', 'stage']) {
      final levels = variableLevels(subjects, variable),
          counts = [
            for (final level in levels)
              subjects.where((s) => variableValue(s, variable) == level).length,
          ];
      var stat = 0.0;
      for (final rows in collections.take(params.groups.length)) {
        for (var j = 0; j < levels.length; j++) {
          final observed = rows
                  .where((s) => variableValue(s, variable) == levels[j])
                  .length,
              expected = rows.length * counts[j] / n,
              d = observed - expected;
          stat += d * d / expected;
        }
      }
      final df = (params.groups.length - 1) * (levels.length - 1);
      lines.add(
        '  $variable chisq ${number(stat)} df $df p ${number(chiP(stat, df))}',
      );
    }
    return lines;
  }

  List<String> overallLines() {
    final lines = <String>[];
    WeightedTest? lr;
    for (final weight in weights) {
      final t = weightedTest(subjects, params.groups, weight, subjects.length);
      if (weight == 'logrank') lr = t;
      lines.add('test $weight ${testFields(t)}');
      lines.addAll(groupLines(t));
    }
    final logrank = lr!;
    var trend = 0.0, variance = 0.0;
    for (var g = 0; g < params.groups.length; g++) {
      trend += (g + 1) * (logrank.observed[g] - logrank.expected[g]);
      var inner = 0.0;
      for (var h = 0; h < params.groups.length; h++) {
        inner += (g + 1) * (h + 1) * logrank.covariance[g][h];
      }
      variance += inner;
    }
    final stat = trend * trend / variance;
    lines.add(
      'test logrank_trend chisq ${number(stat)} df 1 p ${number(chiP(stat, 1))}',
    );
    return lines;
  }

  List<String> stratifiedLines() {
    final variable = params.strata,
        levels = variableLevels(subjects, params.strata),
        strata = [
          for (final level in levels)
            subjects.where((s) => variableValue(s, variable) == level).toList(),
        ],
        lines = <String>[];
    for (final weight in weights) {
      final tests = [
            for (final rows in strata)
              weightedTest(rows, params.groups, weight, subjects.length),
          ],
          combined = combineStrata(tests, params.groups);
      lines.add('stratified $weight by $variable ${testFields(combined)}');
      for (var i = 0; i < tests.length; i++) {
        final t = tests[i];
        lines.add(
          '  stratum ${levels[i]} subjects ${strata[i].length} events ${eventCount(strata[i])} chisq ${number(t.statistic)} p ${number(t.p)}',
        );
      }
      lines.addAll(groupLines(combined));
    }
    return lines;
  }

  List<String> pairwiseLines() {
    final pairs = <(String, String)>[], tests = <TwoGroup>[];
    for (var i = 0; i < params.groups.length; i++) {
      final g = params.groups[i];
      for (final h in params.groups.skip(i + 1)) {
        pairs.add((g, h));
        final rows = subjects
            .where((s) => s.group == g || s.group == h)
            .toList();
        tests.add(twoGroup(rows, [g, h], subjects.length));
      }
    }
    final order = List.generate(tests.length, (i) => i)
          ..sort((i, j) {
            final result = tests[i].test.p.compareTo(tests[j].test.p);
            return result != 0 ? result : i.compareTo(j);
          }),
        adjusted = List.filled(tests.length, 0.0);
    var previous = 0.0;
    for (var rank = 0; rank < order.length; rank++) {
      final i = order[rank],
          candidate = (tests.length - rank) * tests[i].test.p;
      previous = math.max(previous, math.min(1.0, candidate));
      adjusted[i] = previous;
    }
    return [
      'pairwise logrank adjust holm',
      for (var i = 0; i < tests.length; i++)
        '  ${pairs[i].$1} ${pairs[i].$2} chisq ${number(tests[i].test.statistic)} p ${number(tests[i].test.p)} p_holm ${number(adjusted[i])} hr ${number(tests[i].hr)} lower ${number(tests[i].lower)} upper ${number(tests[i].upper)}',
    ];
  }

  List<String> subgroupLines() {
    final groups = params.groups,
        lines = ['subgroups reference ${params.groups.first}'];
    for (final variable in params.subgroups) {
      final levels = variableLevels(subjects, variable);
      for (final group in groups.skip(1)) {
        final tests = <TwoGroup>[];
        for (final level in levels) {
          final rows = subjects
                  .where(
                    (s) =>
                        variableValue(s, variable) == level &&
                        (s.group == groups.first || s.group == group),
                  )
                  .toList(),
              t = twoGroup(rows, [groups.first, group], subjects.length);
          tests.add(t);
          lines.add(
            '  $variable $level $group subjects ${rows.length} events ${eventCount(rows)} hr ${number(t.hr)} lower ${number(t.lower)} upper ${number(t.upper)} p ${number(t.test.p)}',
          );
        }
        var sum = 0.0, total = 0.0;
        for (final t in tests) {
          final w = 1 / t.variance;
          sum += w * t.logHR;
          total += w;
        }
        final mean = sum / total;
        var stat = 0.0;
        for (final t in tests) {
          final w = 1 / t.variance;
          stat += w * (t.logHR - mean) * (t.logHR - mean);
        }
        final df = levels.length - 1;
        lines.add(
          '  $variable $group heterogeneity chisq ${number(stat)} df $df p ${number(chiP(stat, df))}',
        );
      }
    }
    return lines;
  }

  List<List<String>> comparisonSections() {
    final groups = params.groups,
        selected = subjects.where((s) => s.time > params.landmark).toList(),
        t = weightedTest(selected, groups, 'logrank', subjects.length),
        landmark = [
          'landmark ${params.landmark} subjects ${selected.length} ${testFields(t)}',
          ...groupLines(t),
        ],
        rmst = ['rmst_difference tau ${params.tau} reference ${groups.first}'],
        rates = ['rate_ratio reference ${groups.first}'],
        survival = ['survival_difference reference ${groups.first}'],
        control = summaries.first;
    for (var g = 1; g < groups.length; g++) {
      final group = groups[g],
          s = summaries[g],
          se = math.sqrt(
            s.rmst[1] * s.rmst[1] + control.rmst[1] * control.rmst[1],
          );
      rmst.add('  $group ${differenceFields(s.rmst[0] - control.rmst[0], se)}');
      final ratio = s.rate / control.rate,
          error = math.sqrt(1 / s.events + 1 / control.events),
          l = math.log(ratio),
          stat = l / error;
      rates.add(
        '  $group ratio ${number(ratio)} lower ${number(math.exp(l - z95 * error))} upper ${number(math.exp(l + z95 * error))} z ${number(stat)} p ${number(chiP(stat * stat, 1))}',
      );
    }
    for (final time in params.times) {
      final c = rowAt(control.rows, time);
      for (var g = 1; g < groups.length; g++) {
        final r = rowAt(summaries[g].rows, time),
            se = math.sqrt(r.se * r.se + c.se * c.se);
        survival.add(
          '  at $time ${groups[g]} ${differenceFields(r.survival - c.survival, se)}',
        );
      }
    }
    return [
      baselineLines(),
      overallLines(),
      stratifiedLines(),
      landmark,
      pairwiseLines(),
      subgroupLines(),
      rmst,
      rates,
      survival,
    ];
  }

  List<String> coxLines() {
    final names = params.covariates,
        vectors = covariateVectors(subjects, names),
        model = fitCox(subjects, vectors),
        f = model.finalEvaluation,
        covariance = inverse(f.information),
        lines = [
          'cox covariates ${params.covariates.join(' ')} subjects ${subjects.length} events ${eventCount(subjects)} event_times ${f.sums.length}',
        ];
    for (final r in model.iterations) {
      lines.add(
        'iter ${r.number} loglik ${number(r.loglik)} beta ${reals(r.beta)}',
      );
    }
    lines.add(
      'final loglik ${number(f.loglik)} null_loglik ${number(model.nullEvaluation.loglik)}',
    );
    lines.addAll(coefficientLines(names, model.beta, covariance));
    lines.addAll(coxTestLines(subjects, vectors, names, model));
    lines.add(concordanceLine(subjects, vectors, f.predictors));
    lines.addAll(proportionalLines(subjects, vectors, names, f));
    final hazard = baselineHazard(f);
    lines.addAll(residualLines(subjects, f, hazard, params.residuals));
    lines.addAll(
      adjustedLines(
        vectors,
        names,
        model.beta,
        params.groups,
        params.times,
        hazard,
      ),
    );
    return lines;
  }

  List<String> plotLines() {
    final w = params.plot[0],
        h = params.plot[1],
        limit = params.plot[2],
        divisions = params.plot[3],
        legend =
            'legend ${[for (var g = 0; g < params.groups.length; g++) '${String.fromCharCode(65 + g)} ${params.groups[g]}'].join(' ')}',
        estimates = [
          for (var g = 0; g < params.groups.length; g++) summaries[g].rows,
        ],
        times = [for (var i = 0; i <= divisions; i++) i * (limit ~/ divisions)],
        lines = [
          'km_plot width $w height $h time $limit',
          legend,
          ...curveLines(
            collections.take(params.groups.length).toList(),
            estimates,
            w,
            h,
            limit,
          ),
          'time 0 to $limit days, ${limit ~/ w} days per column',
          'at_risk ${ints(times)}',
        ];
    for (var g = 0; g < params.groups.length; g++) {
      lines.add(
        '${params.groups[g]} ${ints(times.map((time) => riskCount(collections[g], time)))}',
      );
    }
    return lines;
  }
}

List<String> joinSections(List<List<String>> sections) => [
  for (var i = 0; i < sections.length; i++) ...[if (i > 0) '', ...sections[i]],
];
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
void main() {
  final (subjects, p) = readDataset();
  final a = Analysis(subjects, p);
  Directory('output').createSync(recursive: true);
  writeLines('km_tables.txt', a.kmTables());
  writeLines('life_table.csv', a.lifeLines());
  writeLines('tests.txt', joinSections(a.comparisonSections()));
  writeLines('cox.txt', a.coxLines());
  writeLines('km_plot.txt', a.plotLines());
}
