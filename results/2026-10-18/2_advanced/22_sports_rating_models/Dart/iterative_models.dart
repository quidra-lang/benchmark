import 'season.dart';
import 'linear_models.dart';

(List<double>, double) bradleyTerry(int count, List<Match> matches, int iterations) {
  final wins = List.filled(count, 0.0);
  var homeWins = 0.0;
  for (final match in matches) {
    wins[match.home] += match.y;
    wins[match.away] += 1 - match.y;
    homeWins += match.y;
  }
  final strengths = List.filled(count, 1.0);
  var theta = 1.0;
  for (var iteration = 0; iteration < iterations; iteration++) {
    final zeta = List.filled(count, 0.0);
    for (final match in matches) {
      final q = theta * strengths[match.home] + strengths[match.away];
      zeta[match.home] += theta / q;
      zeta[match.away] += 1 / q;
    }
    for (var i = 0; i < count; i++) {
      strengths[i] = wins[i] / zeta[i];
    }
    var total = 0.0;
    for (final strength in strengths) {
      total += strength;
    }
    for (var i = 0; i < count; i++) {
      strengths[i] = strengths[i] * count / total;
    }
    var denominator = 0.0;
    for (final match in matches) {
      final home = strengths[match.home];
      denominator += home / (theta * home + strengths[match.away]);
    }
    theta = homeWins / denominator;
  }
  return (strengths, theta);
}

(List<double>, List<double>, List<double>) offenseDefense(
    int count, List<Match> matches, int iterations) {
  final points = realMatrix(count);
  for (final match in matches) {
    points[match.home][match.away] += match.awayScore;
    points[match.away][match.home] += match.homeScore;
  }
  final offense = List.filled(count, 0.0);
  final defense = List.filled(count, 1.0);
  for (var iteration = 0; iteration < iterations; iteration++) {
    for (var j = 0; j < count; j++) {
      var total = 0.0;
      for (var i = 0; i < count; i++) {
        total += points[i][j] / defense[i];
      }
      offense[j] = total;
    }
    for (var i = 0; i < count; i++) {
      var total = 0.0;
      for (var j = 0; j < count; j++) {
        total += points[i][j] / offense[j];
      }
      defense[i] = total;
    }
  }
  return (offense, defense, [for (var i = 0; i < count; i++) offense[i] / defense[i]]);
}
