part of 'main.dart';

double orderedSum(Iterable<double> values) {
  var total = 0.0;
  for (final value in values) {
    total += value;
  }
  return total;
}

double crossValidationScore(List<double> observed, List<double> predicted) {
  var total = 0.0;
  for (var i = 0; i < observed.length; i++) {
    if (predicted[i].isNaN) return double.nan;
    final d = observed[i] - predicted[i];
    total += d * d;
  }
  return total / observed.length;
}

double residualSquare(List<double> observed, List<double> fitted) {
  var total = 0.0;
  for (var i = 0; i < observed.length; i++) {
    final d = observed[i] - fitted[i];
    total += d * d;
  }
  return total;
}

double generalizedScore(
  List<double> observed,
  List<double> fitted,
  double edf,
) {
  final tau = 1 - edf / observed.length;
  return residualSquare(observed, fitted) / observed.length / (tau * tau);
}

int chooseCandidate(List<Candidate> candidates) {
  var best = -1;
  for (var i = 0; i < candidates.length; i++) {
    if (!candidates[i].score.isNaN &&
        (best < 0 || candidates[i].score < candidates[best].score))
      best = i;
  }
  return best;
}
