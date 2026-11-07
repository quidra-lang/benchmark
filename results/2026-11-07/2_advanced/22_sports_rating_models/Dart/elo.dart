import 'dart:math' as math;
import 'season.dart';

class EloRun {
  final List<double> ratings;
  final expected = <double>[];
  final changes = <double>[];
  final rounds = <List<double>>[];
  EloRun(this.ratings);
}

double expectedScore(double home, double away, num advantage) =>
    1 / (1 + math.pow(10, (away - home - advantage) / 400));

double multiplier(Match match, double home, double away, num advantage) {
  final goals = match.margin.abs();
  if (goals == 0) return 1;
  final difference = match.margin > 0 ? home + advantage - away : away - home - advantage;
  return math.log(goals + 1) * 2.2 / (0.001 * difference + 2.2);
}

EloRun runElo(int count, List<Match> matches, num k, num advantage, num initial) {
  final run = EloRun(List.filled(count, initial.toDouble()));
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final home = run.ratings[match.home];
    final away = run.ratings[match.away];
    final expected = expectedScore(home, away, advantage);
    final weight = multiplier(match, home, away, advantage);
    final change = k.toDouble() * weight * (match.y - expected);
    run.ratings[match.home] = home + change;
    run.ratings[match.away] = away - change;
    run.expected.add(expected);
    run.changes.add(change);
    if (i + 1 == matches.length || matches[i + 1].round != match.round) {
      run.rounds.add(List.of(run.ratings));
    }
  }
  return run;
}
