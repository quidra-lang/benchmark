part of 'main.dart';

class EventSums {
  final double s0;
  final List<double> s1;
  final int events;
  EventSums(this.s0, this.s1, this.events);
}

class CoxEvaluation {
  double loglik = 0;
  final List<double> score, predictors;
  final List<List<double>> information;
  final sums = <int, EventSums>{};
  CoxEvaluation(int p, int n)
    : score = List.filled(p, 0.0),
      information = zeros(p),
      predictors = List.filled(n, 0.0);
}

class CoxIteration {
  final int number;
  final double loglik;
  final List<double> beta;
  CoxIteration(this.number, this.loglik, this.beta);
}

class CoxModel {
  final List<double> beta;
  final CoxEvaluation nullEvaluation, finalEvaluation;
  final List<CoxIteration> iterations;
  CoxModel(
    this.beta,
    this.nullEvaluation,
    this.finalEvaluation,
    this.iterations,
  );
}

CoxEvaluation evaluateCox(
  List<Subject> subjects,
  List<List<int>> vectors,
  List<double> beta,
) {
  final p = beta.length,
      r = CoxEvaluation(beta.length, subjects.length),
      risks = List.filled(subjects.length, 0.0),
      order = List.generate(subjects.length, (i) => i);
  for (var j = 0; j < subjects.length; j++) {
    for (var c = 0; c < p; c++) {
      r.predictors[j] += beta[c] * vectors[j][c];
    }
    risks[j] = math.exp(r.predictors[j]);
  }
  order.sort((i, j) {
    final result = subjects[j].time.compareTo(subjects[i].time);
    return result != 0 ? result : subjects[i].id.compareTo(subjects[j].id);
  });
  var s0 = 0.0;
  final s1 = List.filled(p, 0.0), s2 = zeros(p);
  var start = 0;
  while (start < order.length) {
    var end = start + 1;
    final time = subjects[order[start]].time;
    while (end < order.length && subjects[order[end]].time == time) {
      end++;
    }
    final events = <int>[];
    for (final j in order.sublist(start, end)) {
      final risk = risks[j];
      s0 += risk;
      for (var c = 0; c < p; c++) {
        s1[c] += risk * vectors[j][c];
        for (var d = 0; d < p; d++) {
          s2[c][d] += risk * vectors[j][c] * vectors[j][d];
        }
      }
      if (subjects[j].event == 1) events.add(j);
    }
    if (events.isNotEmpty) {
      final e = events.length;
      var sumTheta = 0.0;
      for (final j in events) {
        sumTheta += r.predictors[j];
      }
      r.loglik += sumTheta - e * math.log(s0);
      for (var c = 0; c < p; c++) {
        var sumX = 0;
        for (final j in events) {
          sumX += vectors[j][c];
        }
        r.score[c] += sumX - e * s1[c] / s0;
        for (var d = 0; d < p; d++) {
          r.information[c][d] +=
              e * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0));
        }
      }
      r.sums[time] = EventSums(s0, [...s1], events.length);
    }
    start = end;
  }
  return r;
}

CoxModel fitCox(List<Subject> subjects, List<List<int>> vectors) {
  final beta = List.filled(vectors.first.length, 0.0),
      nullEvaluation = evaluateCox(subjects, vectors, beta),
      iterations = <CoxIteration>[];
  var current = nullEvaluation;
  for (var s = 1; s <= 25; s++) {
    final delta = solve(current.information, current.score);
    for (var c = 0; c < beta.length; c++) {
      beta[c] += delta[c];
    }
    iterations.add(CoxIteration(s, current.loglik, [...beta]));
    current = evaluateCox(subjects, vectors, beta);
  }
  return CoxModel(beta, nullEvaluation, current, iterations);
}
