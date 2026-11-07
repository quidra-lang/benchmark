import 'dart:io';
import 'dart:math';
part 'data_io.dart';
part 'models.dart';
part 'integrator.dart';
part 'fitting.dart';
part 'report.dart';

double sum(List<double> a) {
  var s = 0.0;
  for (final v in a) {
    s += v;
  }
  return s;
}

int sumInts(List<int> a) {
  var s = 0;
  for (final v in a) {
    s += v;
  }
  return s;
}

double squares(List<double> a) {
  var s = 0.0;
  for (final v in a) {
    s += v * v;
  }
  return s;
}

int largest(List<double> a) {
  var best = 0;
  for (var i = 1; i < a.length; i++) {
    if (a[i] > a[best]) best = i;
  }
  return best;
}

List<double> intReals(List<int> a) => a.map((x) => x.toDouble()).toList();
List<double> constant(int n, double x) => List.filled(n, x);
List<double> multiply(List<double> a, double x) => a.map((y) => x * y).toList();
List<double> multiplierSequence(List<Intervention> interventions, int n) =>
    List.generate(n, (index) {
      var value = 0.0;
      for (final line in interventions) {
        if (line.day <= index + 1) value = line.multiplier;
      }
      return value;
    });
double sse(List<double> series, double scale, List<int> observed) {
  var value = 0.0;
  for (var i = 0; i < series.length; i++) {
    final e = scale * series[i] - observed[i];
    value += e * e;
  }
  return value;
}

double rmse(double sse, int n) => sqrt(sse / n);
List<double> incidence(List<List<double>> states, String kind) =>
    states.map((state) {
      if (kind == 'sir') return state[3];
      if (kind == 'age') {
        var total = 0.0;
        for (var g = 0; g < state.length ~/ 6; g++) {
          total += state[6 * g + 5];
        }
        return total;
      }
      return state[5];
    }).toList();
double finalSize(double r) {
  if (r <= 1) return 0;
  var lo = 1 - 1 / r, hi = 1.0;
  for (var i = 0; i < 20; i++) {
    final mid = (lo + hi) / 2, g = 1 - mid - exp(-r * mid);
    if (g > 0) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

(double, List<double>) power(List<List<double>> matrix) {
  final n = matrix.length, v = constant(matrix.length, 1 / matrix.length);
  var nu = 0.0;
  for (var iteration = 0; iteration < 200; iteration++) {
    final u = List.filled(n, 0.0);
    for (var g = 0; g < n; g++) {
      for (var h = 0; h < n; h++) {
        u[g] += matrix[g][h] * v[h];
      }
    }
    nu = sum(u);
    for (var g = 0; g < n; g++) {
      v[g] = u[g] / nu;
    }
  }
  return (nu, v);
}

class Application {
  final Data data;
  List<double> multipliers = [],
      incidences = [],
      reported = [],
      residual = [],
      modelDeaths = [],
      average = [],
      rt = [];
  final fitLines = <String>[];
  double beta = 0,
      gamma = 0,
      rho = 0,
      r0 = 0,
      sseFit = 0,
      seBeta = 0,
      spacingBeta = 0,
      spacingRho = 0,
      kbar = 0;
  List<List<double>> states = [], ageStates = [], w = [];
  Application(this.data);
  Model model(
    String kind,
    double beta,
    double gamma,
    double sigma, [
    List<List<double>> w = const [],
  ]) => Model(
    kind,
    beta,
    gamma,
    sigma,
    data.population.toDouble(),
    data.fatality,
    data.groups,
    w,
  );
  List<List<double>> course(
    String kind,
    double beta,
    double gamma,
    double sigma,
    List<double> multipliers, [
    List<List<double>> w = const [],
  ]) => simulate(
    model(kind, beta, gamma, sigma, w),
    initial(data, kind),
    multipliers,
  );
  double objective(double beta, double gamma, double rho, List<double> m) =>
      sse(
        incidence(course('seir', beta, gamma, data.params.sigma, m), 'seir'),
        rho,
        data.cases.sublist(0, m.length),
      );
  void fit() {
    final p = data.params, t = data.cases.length;
    multipliers = multiplierSequence(data.interventions, t);
    spacingBeta = (p.betaMax - p.betaMin) / (p.betaCount - 1);
    spacingRho = (p.rhoMax - p.rhoMin) / (p.rhoCount - 1);
    fitLines.add(
      'data days $t cases ${sumInts(data.cases)} deaths ${sumInts(data.deaths)} population ${data.population} fatality ${fixed(data.fatality, 6)}',
    );
    final rhoGrid = List.generate(
      p.rhoCount,
      (j) => p.rhoMin + (p.rhoMax - p.rhoMin) * j / (p.rhoCount - 1),
    );
    fitLines.add(
      'grid gamma ${fixed(p.gamma, 4)} rho ${rhoGrid.map((v) => fixed(v, 4)).join(' ')}',
    );
    var betaGrid = 0.0, bestRho = 0.0, bestValue = 0.0;
    for (var i = 0; i < p.betaCount; i++) {
      final b = p.betaMin + (p.betaMax - p.betaMin) * i / (p.betaCount - 1),
          series = incidence(
            course('seir', b, p.gamma, p.sigma, multipliers),
            'seir',
          ),
          line = ['grid beta ${fixed(b, 4)} rmse'];
      for (var j = 0; j < rhoGrid.length; j++) {
        final r = rhoGrid[j], value = sse(series, r, data.cases);
        line.add(fixed(rmse(value, t), 2));
        if ((i == 0 && j == 0) || value < bestValue) {
          betaGrid = b;
          bestRho = r;
          bestValue = value;
        }
      }
      fitLines.add(line.join(' '));
    }
    fitLines.add(
      'grid_best beta ${fixed(betaGrid, 4)} rho ${fixed(bestRho, 4)} sse ${fixed(bestValue, 1)} rmse ${fixed(rmse(bestValue, t), 4)}',
    );
    var b = betaGrid, r = bestRho, goldenValue = bestValue;
    void appendGolden(int round, String name, GoldenResult g) {
      for (var i = 0; i < g.records.length; i++) {
        final v = g.records[i];
        fitLines.add(
          'golden $round $name $i a ${fixed(v.a, 6)} b ${fixed(v.b, 6)} c ${fixed(v.c, 6)} d ${fixed(v.d, 6)} rmse ${fixed(rmse(v.fc, t), 4)} ${fixed(rmse(v.fd, t), 4)}',
        );
      }
      fitLines.add(
        'golden_result $round $name ${fixed(g.x, 6)} sse ${fixed(g.value, 1)}',
      );
    }

    for (var round = 1; round <= p.rounds; round++) {
      var g = golden(
        (x) => objective(x, p.gamma, r, multipliers),
        b - spacingBeta,
        b + spacingBeta,
        p.golden,
      );
      b = g.x;
      appendGolden(round, 'beta', g);
      g = golden(
        (x) => objective(b, p.gamma, x, multipliers),
        r - spacingRho,
        r + spacingRho,
        p.golden,
      );
      r = g.x;
      goldenValue = g.value;
      appendGolden(round, 'rho', g);
    }
    final nm = nelder((b, g) => objective(b, g, r, multipliers), b, p.gamma, p);
    for (final v in nm.initial) {
      fitLines.add(
        'simplex ${v.number} beta ${fixed(v.beta, 6)} gamma ${fixed(v.gamma, 6)} rmse ${fixed(rmse(v.value, t), 4)}',
      );
    }
    for (var i = 0; i < nm.records.length; i++) {
      final record = nm.records[i], v = record.best;
      fitLines.add(
        'nelder_mead ${i + 1} ${record.operation} beta ${fixed(v.beta, 6)} gamma ${fixed(v.gamma, 6)} rmse ${fixed(rmse(v.value, t), 4)}',
      );
    }
    for (var i = 0; i < nm.finalVertices.length; i++) {
      final v = nm.finalVertices[i];
      fitLines.add(
        'final_simplex ${i + 1} beta ${fixed(v.beta, 6)} gamma ${fixed(v.gamma, 6)} rmse ${fixed(rmse(v.value, t), 4)}',
      );
    }
    final v = nm.finalVertices.first;
    beta = v.beta;
    gamma = v.gamma;
    rho = r;
    sseFit = v.value;
    r0 = beta / gamma;
    states = course('seir', beta, gamma, p.sigma, multipliers);
    incidences = incidence(states, 'seir');
    reported = multiply(incidences, rho);
    residual = List.filled(t, 0);
    modelDeaths = List.filled(t, 0);
    average = List.filled(t, 0);
    rt = List.filled(t, 0);
    var previousDeath = 0.0, previousS = data.population - p.e0 - p.i0;
    for (var d = 0; d < t; d++) {
      final state = states[d];
      residual[d] = data.cases[d] - reported[d];
      modelDeaths[d] = state[4] - previousDeath;
      previousDeath = state[4];
      rt[d] = r0 * multipliers[d] * previousS / data.population;
      previousS = state[0];
      average[d] =
          sumInts(data.cases.sublist(max(0, d - 6), d + 1)) / min(d + 1, 7);
    }
    final mean = sumInts(data.cases) / t;
    var sst = 0.0;
    for (final c in data.cases) {
      final e = c - mean;
      sst += e * e;
    }
    fitLines.addAll([
      'fitted beta ${fixed(beta, 6)} gamma ${fixed(gamma, 6)} rho ${fixed(rho, 6)} sigma ${fixed(p.sigma, 6)} r0 ${fixed(r0, 4)}',
      'sse grid ${fixed(bestValue, 1)} golden ${fixed(goldenValue, 1)} nelder_mead ${fixed(sseFit, 1)} rmse ${fixed(rmse(sseFit, t), 4)} r2 ${fixed(1 - sseFit / sst, 4)}',
    ]);
    for (final (name, sb, sg, sr, ss) in [
      ('grid', betaGrid, p.gamma, bestRho, bestValue),
      ('golden', b, p.gamma, r, goldenValue),
      ('nelder_mead', beta, gamma, rho, sseFit),
    ]) {
      fitLines.add(
        'stage $name beta ${fixed(sb, 6)} gamma ${fixed(sg, 6)} rho ${fixed(sr, 6)} r0 ${fixed(sb / sg, 4)} rmse ${fixed(rmse(ss, t), 4)}',
      );
    }
  }

  void diagnostics() {
    final t = data.cases.length,
        p = data.params,
        e = residual,
        u = squares(residual);
    var residualSum = sum(e),
        mae = 0.0,
        dw = 0.0,
        positive = 0,
        runs = 1,
        maximum = 0;
    for (var d = 0; d < t; d++) {
      final v = e[d];
      mae += v.abs();
      if (v > 0) positive++;
      if (v.abs() > e[maximum].abs()) maximum = d;
      if (d > 0) {
        final difference = v - e[d - 1];
        dw += difference * difference;
        if ((v > 0) != (e[d - 1] > 0)) runs++;
      }
    }
    fitLines.add(
      'residuals sum ${fixed(residualSum, 1)} mae ${fixed(mae / t, 1)} max ${fixed(e[maximum], 1)} day ${maximum + 1} positive $positive runs $runs durbin_watson ${fixed(dw / u, 4)}',
    );
    final acf = ['autocorrelation'];
    for (var lag = 1; lag <= 7; lag++) {
      var value = 0.0;
      for (var d = 0; d < t - lag; d++) {
        value += e[d] * e[d + lag];
      }
      acf.add(fixed(value / u, 4));
    }
    fitLines.add(acf.join(' '));
    var outliers = 0;
    for (var d = 0; d < t; d++) {
      final z = e[d] / sqrt(reported[d]);
      if (z.abs() > p.outlier) {
        outliers++;
        fitLines.add(
          'outlier ${d + 1} observed ${data.cases[d]} fitted ${fixed(reported[d], 1)} z ${fixed(z, 4)}',
        );
      }
    }
    fitLines.add('outliers $outliers');
    final weekdayObserved = List.filled(7, 0),
        weekdayFitted = List.filled(7, 0.0),
        factors = List.filled(7, 0.0);
    for (var d = 0; d < t; d++) {
      weekdayObserved[d % 7] += data.cases[d];
      weekdayFitted[d % 7] += reported[d];
    }
    for (var k = 0; k < 7; k++) {
      factors[k] = weekdayObserved[k] / weekdayFitted[k];
      fitLines.add(
        'weekday ${k + 1} observed ${weekdayObserved[k]} fitted ${fixed(weekdayFitted[k], 1)} factor ${fixed(factors[k], 4)}',
      );
    }
    final adjusted = List.generate(t, (d) => reported[d] * factors[d % 7]),
        infections = sum(incidences);
    fitLines.addAll([
      'weekday_adjusted rmse ${fixed(rmse(sse(adjusted, 1, data.cases), t), 4)}',
      'burden infections ${fixed(infections, 1)} ascertainment ${fixed(sumInts(data.cases) / infections, 4)} deaths_per_infection ${fixed(sumInts(data.deaths) / infections, 6)}',
    ]);
    var cross = 0.0;
    for (var d = 0; d < t; d++) {
      cross += modelDeaths[d] * data.deaths[d];
    }
    final scale = cross / squares(modelDeaths);
    fitLines.add(
      'deaths observed ${sumInts(data.deaths)} model ${fixed(states.last[4], 1)} rmse ${fixed(rmse(sse(modelDeaths, 1, data.deaths), t), 4)} scale ${fixed(scale, 4)} implied_fatality ${fixed(data.fatality * scale, 6)} cfr ${fixed(sumInts(data.deaths) / sumInts(data.cases), 4)}',
    );
    var bestLag = 0, bestCorrelation = 0.0;
    for (var lag = 0; lag <= p.deathLag; lag++) {
      var cross = 0, squareCases = 0, squareDeaths = 0;
      for (var d = 0; d < t - lag; d++) {
        final c = data.cases[d], q = data.deaths[d + lag];
        cross += c * q;
        squareCases += c * c;
        squareDeaths += q * q;
      }
      final correlation =
          cross / sqrt(squareCases.toDouble() * squareDeaths.toDouble());
      if (lag == 0 || correlation > bestCorrelation) {
        bestLag = lag;
        bestCorrelation = correlation;
      }
      final cfr =
          sumInts(data.deaths.sublist(lag)) /
          sumInts(data.cases.sublist(0, t - lag));
      fitLines.add(
        'death_lag $lag correlation ${fixed(correlation, 4)} cfr ${fixed(cfr, 4)}',
      );
    }
    fitLines.add('death_best_lag $bestLag');
    var previous = 0;
    for (var start = 0; start < t; start += 7) {
      final end = min(t, start + 7),
          observed = sumInts(data.cases.sublist(start, end)),
          growth = start > 0 ? fixed(observed / previous, 4) : '-';
      fitLines.add(
        'weekly ${start ~/ 7 + 1} days ${start + 1} $end observed $observed fitted ${fixed(sum(reported.sublist(start, end)), 1)} deaths_observed ${sumInts(data.deaths.sublist(start, end))} deaths_model ${fixed(sum(modelDeaths.sublist(start, end)), 1)} growth $growth',
      );
      previous = observed;
    }
    for (var parameter = 0; parameter < 3; parameter++) {
      final name = ['beta', 'gamma', 'rho'][parameter],
          values = [beta, gamma, rho],
          v = values[parameter],
          profile = List.filled(11, 0.0);
      for (var k = -5; k <= 5; k++) {
        final point = List<double>.of(values);
        point[parameter] = v * (1 + k / 100);
        profile[k + 5] = objective(point[0], point[1], point[2], multipliers);
        fitLines.add(
          'profile $name $k value ${fixed(point[parameter], 6)} rmse ${fixed(rmse(profile[k + 5], t), 4)}',
        );
      }
      final h = v / 100,
          curvature = (profile[6] - 2 * profile[5] + profile[4]) / (h * h),
          variance = sseFit / (t - 3),
          se = sqrt(2 * variance / curvature);
      if (parameter == 0) seBeta = se;
      fitLines.add('profile_se $name ${fixed(se, 6)}');
    }
  }

  void furtherFit() {
    final p = data.params, t = data.cases.length, trainingDays = t - p.holdout;
    var g = golden(
      (b) => objective(b, gamma, rho, multipliers.sublist(0, trainingDays)),
      beta - spacingBeta,
      beta + spacingBeta,
      p.golden,
    );
    final backBeta = g.x;
    g = golden(
      (r) =>
          objective(backBeta, gamma, r, multipliers.sublist(0, trainingDays)),
      rho - spacingRho,
      rho + spacingRho,
      p.golden,
    );
    final backRho = g.x,
        forecast = multiply(
          incidence(
            course('seir', backBeta, gamma, p.sigma, multipliers),
            'seir',
          ),
          backRho,
        );
    fitLines.add(
      'backtest train_days $trainingDays beta ${fixed(backBeta, 6)} rho ${fixed(backRho, 6)} train_rmse ${fixed(rmse(g.value, trainingDays), 4)} test_rmse ${fixed(rmse(sse(forecast.sublist(trainingDays), 1, data.cases.sublist(trainingDays)), p.holdout), 4)} full_fit_test_rmse ${fixed(rmse(sse(reported.sublist(trainingDays), 1, data.cases.sublist(trainingDays)), p.holdout), 4)}',
    );
    for (var d = trainingDays; d < t; d++) {
      fitLines.add(
        'backtest_day ${d + 1} observed ${data.cases[d]} forecast ${fixed(forecast[d], 1)} error ${fixed(data.cases[d] - forecast[d], 1)}',
      );
    }
    final estimated = List<Intervention>.of(data.interventions);
    var effectSSE = sseFit;
    for (var k = 1; k < estimated.length; k++) {
      final given = data.interventions[k],
          result = golden(
            (x) {
              final changed = List<Intervention>.of(estimated);
              changed[k] = Intervention(given.day, x);
              return objective(
                beta,
                gamma,
                rho,
                multiplierSequence(changed, t),
              );
            },
            given.multiplier - p.effectWidth,
            given.multiplier + p.effectWidth,
            p.golden,
          );
      estimated[k] = Intervention(given.day, result.x);
      effectSSE = result.value;
      fitLines.add(
        'effect ${k + 1} day ${given.day} given ${fixed(given.multiplier, 4)} estimated ${fixed(result.x, 6)} sse ${fixed(result.value, 1)}',
      );
    }
    fitLines.add(
      'effect_sse before ${fixed(sseFit, 1)} after ${fixed(effectSSE, 1)} rmse ${fixed(rmse(effectSSE, t), 4)}',
    );
    for (var parameter = 0; parameter < 4; parameter++) {
      final name = ['beta', 'gamma', 'sigma', 'rho'][parameter];
      for (final factor in [.9, 1.1]) {
        final point = [beta, gamma, p.sigma, rho];
        point[parameter] *= factor;
        final states = course(
              'seir',
              point[0],
              point[1],
              point[2],
              multipliers,
            ),
            j = incidence(states, 'seir'),
            peak = largest(j);
        fitLines.add(
          'sensitivity $name ${fixed(factor, 2)} r0 ${fixed(point[0] / point[1], 4)} rmse ${fixed(rmse(sse(j, point[3], data.cases), t), 4)} peak_day ${peak + 1} peak ${fixed(point[3] * j[peak], 1)} attack ${fixed((data.population - states.last[0]) / data.population, 4)}',
        );
      }
    }
  }

  void prepareAge() {
    final groups = data.groups;
    var weighted = 0.0;
    for (var g = 0; g < groups.length; g++) {
      weighted += groups[g].population * sum(data.contacts[g]);
    }
    kbar = weighted / data.population;
    w = [
      for (var g = 0; g < groups.length; g++)
        [for (var h = 0; h < groups.length; h++) data.contacts[g][h] / kbar],
    ];
    ageStates = course('age', beta, gamma, data.params.sigma, multipliers, w);
  }

  void modelComparison() {
    final p = data.params,
        t = data.cases.length,
        sir = incidence(
          course('sir', beta, gamma, p.sigma, multipliers),
          'sir',
        ),
        series = [sir, incidences, incidence(ageStates, 'age')];
    for (var i = 0; i < series.length; i++) {
      final j = series[i], name = ['sir', 'seir', 'age'][i];
      var cross = 0.0;
      for (var d = 0; d < t; d++) {
        cross += data.cases[d] * j[d];
      }
      final r = cross / squares(j);
      fitLines.add(
        'model $name rmse ${fixed(rmse(sse(j, rho, data.cases), t), 4)} peak_day ${largest(j) + 1} rho_opt ${fixed(r, 6)} rmse_opt ${fixed(rmse(sse(j, r, data.cases), t), 4)}',
      );
    }
    final g = golden(
          (b) => sse(
            incidence(course('sir', b, gamma, p.sigma, multipliers), 'sir'),
            rho,
            data.cases,
          ),
          p.betaMin,
          p.betaMax,
          p.golden,
        ),
        j = incidence(course('sir', g.x, gamma, p.sigma, multipliers), 'sir');
    fitLines.add(
      'model sir_fit beta ${fixed(g.x, 6)} rmse ${fixed(rmse(g.value, t), 4)} peak_day ${largest(j) + 1}',
    );
  }

  List<List<double>> ngm(
    List<List<double>> w,
    double multiplier, [
    List<double>? susceptible,
  ]) => [
    for (var g = 0; g < w.length; g++)
      [
        for (var h = 0; h < w.length; h++)
          susceptible == null
              ? r0 *
                    w[g][h] *
                    data.groups[g].population /
                    data.groups[h].population
              : multiplier *
                    r0 *
                    w[g][h] *
                    susceptible[6 * g] /
                    data.groups[h].population,
      ],
  ];
  (List<String>, List<String>) reproduction() {
    final p = data.params,
        t = data.cases.length,
        n = data.population.toDouble(),
        long = course('seir', beta, gamma, p.sigma, constant(730, 1)),
        out = [
          'r0 ${fixed(r0, 4)} herd_immunity ${fixed(1 - 1 / r0, 4)}',
          'final_size equation ${fixed(finalSize(r0), 4)} simulated ${fixed((n - long.last[0]) / n, 4)}',
        ],
        generation = simulate(
          model('generation', beta, gamma, p.sigma),
          initial(data, 'generation'),
          constant(p.generation, 1),
        ),
        daily = generation.map((state) => state[2]).toList(),
        coverage = sum(daily),
        weights = List.filled(daily.length, 0.0);
    var mean = 0.0;
    for (var i = 0; i < daily.length; i++) {
      weights[i] = daily[i] / coverage;
      mean += (i + 1 - .5) * weights[i];
    }
    out.add(
      'generation mean ${fixed(mean, 4)} theory ${fixed(1 / p.sigma + 1 / gamma, 4)} coverage ${fixed(coverage, 4)}',
    );
    for (var i = 0; i < weights.length; i++) {
      out.add('generation_weight ${i + 1} ${fixed(weights[i], 6)}');
    }
    final peak = largest(incidences),
        infectious = states.map((s) => s[2]).toList(),
        ip = largest(infectious),
        observed = intReals(data.cases),
        op = largest(observed),
        ap = largest(average);
    out.addAll([
      'peak model day ${peak + 1} incidence ${fixed(incidences[peak], 1)} reported ${fixed(reported[peak], 1)} infectious_day ${ip + 1} infectious ${fixed(infectious[ip], 1)}',
      'peak observed day ${op + 1} cases ${data.cases[op]} average7_day ${ap + 1} average7 ${fixed(average[ap], 2)}',
    ]);
    for (var k = 0; k < data.interventions.length; k++) {
      final line = data.interventions[k],
          start = line.day - 1,
          end = k + 1 < data.interventions.length
              ? data.interventions[k + 1].day - 1
              : t,
          count = end - start;
      out.add(
        'period ${k + 1} days ${start + 1} $end multiplier ${fixed(line.multiplier, 4)} rt_start ${fixed(rt[start], 4)} rt_end ${fixed(rt[end - 1], 4)} observed ${sumInts(data.cases.sublist(start, end))} fitted ${fixed(sum(reported.sublist(start, end)), 1)} rmse ${fixed(rmse(squares(residual.sublist(start, end)), count), 4)} bias ${fixed(sum(residual.sublist(start, end)) / count, 1)}',
      );
    }
    for (final target in p.milestones) {
      var co = 0, cr = 0.0, od = 'never', fd = 'never';
      for (var d = 0; d < t; d++) {
        co += data.cases[d];
        cr += reported[d];
        if (od == 'never' && co >= target) od = '${d + 1}';
        if (fd == 'never' && cr >= target) fd = '${d + 1}';
      }
      out.add('milestone $target observed $od fitted $fd');
    }
    final total = sum(reported),
        counterfactual = multiply(
          incidence(
            course(
              'seir',
              beta,
              gamma,
              p.sigma,
              constant(t, data.interventions.first.multiplier),
            ),
            'seir',
          ),
          rho,
        ),
        cp = largest(counterfactual),
        ctotal = sum(counterfactual);
    out.add(
      'counterfactual none reported ${fixed(ctotal, 1)} peak_day ${cp + 1} peak ${fixed(counterfactual[cp], 1)} averted ${fixed(ctotal - total, 1)}',
    );
    for (var k = 1; k < data.interventions.length; k++) {
      final removed = List<Intervention>.of(data.interventions)..removeAt(k),
          cases = multiply(
            incidence(
              course(
                'seir',
                beta,
                gamma,
                p.sigma,
                multiplierSequence(removed, t),
              ),
              'seir',
            ),
            rho,
          ),
          value = sum(cases);
      out.add(
        'counterfactual without ${k + 1} reported ${fixed(value, 1)} averted ${fixed(value - total, 1)}',
      );
    }
    for (var k = 1; k < data.interventions.length; k++) {
      for (final shift in [-7, 7]) {
        final changed = List<Intervention>.of(data.interventions),
            old = changed[k];
        changed[k] = Intervention(old.day + shift, old.multiplier);
        final cases = multiply(
              incidence(
                course(
                  'seir',
                  beta,
                  gamma,
                  p.sigma,
                  multiplierSequence(changed, t),
                ),
                'seir',
              ),
              rho,
            ),
            value = sum(cases);
        out.add(
          'timing ${k + 1} shift $shift reported ${fixed(value, 1)} change ${fixed(value - total, 1)}',
        );
      }
    }
    for (var d = 1; d < t; d++) {
      if ((rt[d] < 1) != (rt[d - 1] < 1))
        out.add('rt_cross day ${d + 1} ${rt[d] < 1 ? 'down' : 'up'}');
    }
    final pressure = List.filled(t, 0.0);
    for (var d = 0; d < t; d++) {
      for (var s = 1; s <= min(p.generation, d); s++) {
        pressure[d] += weights[s - 1] * data.cases[d - s];
      }
    }
    for (var d = 0; d < t; d++) {
      final empirical = d + 1 >= p.generation + 7
          ? fixed(
              sumInts(data.cases.sublist(d - 6, d + 1)) /
                  sum(pressure.sublist(d - 6, d + 1)),
              4,
            )
          : '-';
      out.add('rt ${d + 1} model ${fixed(rt[d], 4)} empirical $empirical');
    }
    final matrix = ngm(w, 1);
    final (eigenvalue, eigenvector) = power(matrix);
    for (var g = 0; g < matrix.length; g++) {
      out.add(
        'ngm ${data.groups[g].name} ${matrix[g].map((v) => fixed(v, 4)).join(' ')}',
      );
    }
    out.add(
      'r0_age ${fixed(eigenvalue, 4)} ratio ${fixed(eigenvalue / r0, 4)} kbar ${fixed(kbar, 4)} eigenvector ${eigenvector.map((v) => fixed(v, 4)).join(' ')}',
    );
    var z = constant(data.groups.length, 1);
    for (var iteration = 0; iteration < 100; iteration++) {
      final next = List.filled(z.length, 0.0);
      for (var g = 0; g < z.length; g++) {
        var force = 0.0;
        for (var h = 0; h < z.length; h++) {
          force += r0 * w[g][h] * z[h];
        }
        next[g] = 1 - exp(-force);
      }
      z = next;
    }
    final longAge = course('age', beta, gamma, p.sigma, constant(730, 1), w),
        longFinal = longAge.last;
    var equationTotal = 0.0, simulationTotal = 0.0;
    for (var g = 0; g < data.groups.length; g++) {
      final group = data.groups[g],
          population = group.population.toDouble(),
          simulated = (population - longFinal[6 * g]) / population;
      equationTotal += population * z[g];
      simulationTotal += population * simulated;
      out.add(
        'final_size_age ${group.name} equation ${fixed(z[g], 4)} simulated ${fixed(simulated, 4)}',
      );
    }
    out.add(
      'final_size_age total equation ${fixed(equationTotal / n, 4)} simulated ${fixed(simulationTotal / n, 4)}',
    );
    final ageInitial = initial(data, 'age');
    for (var d = 0; d < t; d += 7) {
      final previous = d > 0 ? ageStates[d - 1] : ageInitial;
      final (value, _) = power(ngm(w, multipliers[d], previous));
      out.add(
        'age_rt ${d + 1} ${fixed(value, 4)} homogeneous ${fixed(rt[d], 4)}',
      );
    }
    for (var start = 0; start < t; start += 7) {
      final end = min(t, start + 7),
          items = ['age_weekly ${start ~/ 7 + 1} days ${start + 1} $end'];
      for (var g = 0; g < data.groups.length; g++) {
        var value = 0.0;
        for (var d = start; d < end; d++) {
          value += ageStates[d][6 * g + 5];
        }
        items.add(fixed(value, 1));
      }
      out.add(items.join(' '));
    }
    final ageInfections = List.filled(data.groups.length, 0.0),
        ageFinal = ageStates.last;
    for (var g = 0; g < data.groups.length; g++) {
      for (var d = 0; d < t; d++) {
        ageInfections[g] += ageStates[d][6 * g + 5];
      }
    }
    final ageTotal = sum(ageInfections);
    for (var g = 0; g < data.groups.length; g++) {
      final group = data.groups[g],
          series = ageStates.map((state) => state[6 * g + 5]).toList(),
          peak = largest(series);
      out.add(
        'age ${group.name} attack ${fixed((group.population - ageFinal[6 * g]) / group.population, 4)} infections ${fixed(ageInfections[g], 1)} share ${fixed(ageInfections[g] / ageTotal, 4)} deaths ${fixed(ageFinal[6 * g + 4], 1)} peak_day ${peak + 1} peak ${fixed(series[peak], 1)}',
      );
    }
    for (final change in p.changes) {
      final target = data.groups.indexWhere((g) => g.name == change.group),
          changed = [
            for (var g = 0; g < w.length; g++)
              [
                for (var h = 0; h < w.length; h++)
                  w[g][h] *
                      (g == target ? change.factor : 1) *
                      (h == target ? change.factor : 1),
              ],
          ];
      final (value, _) = power(ngm(changed, 1));
      final changedStates = course(
            'age',
            beta,
            gamma,
            p.sigma,
            multipliers,
            changed,
          ),
          infections = sum(incidence(changedStates, 'age')),
          last = changedStates.last;
      var deaths = 0.0, infected = 0.0;
      for (var g = 0; g < data.groups.length; g++) {
        deaths += last[6 * g + 4];
        infected += data.groups[g].population - last[6 * g];
      }
      out.add(
        'contact_change ${change.name} group ${change.group} factor ${fixed(change.factor, 4)} r0_age ${fixed(value, 4)} infections ${fixed(infections, 1)} deaths ${fixed(deaths, 1)} attack ${fixed(infected / n, 4)}',
      );
    }
    final scenarioCSV = ['scenario,day,incidence,reported'];
    var firstTotal = 0.0;
    for (var index = 0; index < p.scenarios.length; index++) {
      final scenario = p.scenarios[index],
          futureMultipliers = constant(p.horizon, scenario.multiplier),
          future = simulate(
            model('seir', beta, gamma, p.sigma),
            states.last,
            futureMultipliers,
          ),
          j = incidence(future, 'seir'),
          projected = multiply(j, rho),
          value = sum(projected),
          peak = largest(projected);
      if (index == 0) firstTotal = value;
      var below = 'never', above = 0;
      for (var d = 0; d < projected.length; d++) {
        final v = projected[d];
        scenarioCSV.add(
          '${scenario.name},${t + d + 1},${fixed(j[d], 1)},${fixed(v, 1)}',
        );
        if (v < p.threshold && below == 'never') below = '${t + d + 1}';
        if (v >= p.threshold) above++;
      }
      out.add(
        'scenario ${scenario.name} multiplier ${fixed(scenario.multiplier, 4)} rt ${fixed(r0 * scenario.multiplier * states.last[0] / n, 4)} reported ${fixed(value, 1)} peak_day ${t + peak + 1} peak ${fixed(projected[peak], 1)} attack ${fixed((n - future.last[0]) / n, 4)} final_size ${fixed(finalSize(r0 * scenario.multiplier), 4)} averted ${fixed(firstTotal - value, 1)} below $below days_above $above',
      );
      final sequence = [...multipliers, ...futureMultipliers],
          bounds = [beta - 2 * seBeta, beta + 2 * seBeta],
          totals = List.filled(2, 0.0);
      for (var i = 0; i < 2; i++) {
        final series = incidence(
          course('seir', bounds[i], gamma, p.sigma, sequence),
          'seir',
        );
        totals[i] = sum(multiply(series.sublist(t), rho));
      }
      out.add(
        'scenario_band ${scenario.name} beta_low ${fixed(bounds[0], 6)} reported_low ${fixed(totals[0], 1)} beta_high ${fixed(bounds[1], 6)} reported_high ${fixed(totals[1], 1)}',
      );
      final ageFuture = simulate(
            model('age', beta, gamma, p.sigma, w),
            ageFinal,
            futureMultipliers,
          ),
          last = ageFuture.last,
          items = ['scenario_age ${scenario.name} attack'];
      var deaths = 0.0;
      for (var g = 0; g < data.groups.length; g++) {
        items.add(
          fixed(
            (data.groups[g].population - last[6 * g]) /
                data.groups[g].population,
            4,
          ),
        );
        deaths += last[6 * g + 4];
      }
      items.addAll(['deaths', fixed(deaths, 1)]);
      out.add(items.join(' '));
    }
    return (out, scenarioCSV);
  }

  void trajectoryOutput() {
    final out = [
      'day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported',
    ];
    var co = 0, cr = 0.0;
    for (var d = 0; d < states.length; d++) {
      co += data.cases[d];
      cr += reported[d];
      out.add(
        [
          '${d + 1}',
          ...states[d].take(5).map((v) => fixed(v, 1)),
          fixed(incidences[d], 1),
          fixed(reported[d], 1),
          '${data.cases[d]}',
          fixed(average[d], 2),
          '$co',
          fixed(cr, 1),
        ].join(','),
      );
    }
    writeLines('trajectories.csv', out);
  }
}

void main() {
  final a = Application(readData());
  a.fit();
  a.diagnostics();
  a.furtherFit();
  a.prepareAge();
  a.modelComparison();
  final (reproduction, scenarios) = a.reproduction();
  writeLines('fit.txt', a.fitLines);
  a.trajectoryOutput();
  writeLines('scenarios.csv', scenarios);
  writeLines('reproduction.txt', reproduction);
  writeLines('curve_plot.txt', curvePlot(a.data.cases, a.reported));
}
