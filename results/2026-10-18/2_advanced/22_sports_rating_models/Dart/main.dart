import 'dart:io';
import 'dart:math' as math;
import 'season.dart';
import 'elo.dart';
import 'linear_models.dart';
import 'iterative_models.dart';
import 'evaluation.dart';
import 'report.dart';

const ratingModels = ['elo', 'colley', 'massey', 'bt', 'od', 'winpct'];
const comparisonModels = ['standings', 'elo', 'colley', 'massey', 'bt', 'od', 'winpct', 'rpi', 'pythag'];
const linkModels = ['colley', 'massey', 'od', 'winpct'];
const predictionModels = ['base', 'elo', 'colley', 'massey', 'bt', 'od', 'winpct', 'ensemble'];
const standingsHeader = 'pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck';
const ratingsHeader = 'team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank';
const historyHeader = 'round,team,elo,change,elo_rank,points,position';
const projectionHeader = 'projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position';

double sequentialSum(Iterable<double> values) {
  var total = 0.0;
  for (final value in values) {
    total += value;
  }
  return total;
}
double mean(List<double> values) => sequentialSum(values) / values.length;
String csv(List<Object> fields) => fields.join(',');
List<String> joinParts(List<List<String>> parts) {
  final lines = <String>[];
  for (final part in parts) {
    if (lines.isNotEmpty) lines.add('');
    lines.addAll(part);
  }
  return lines;
}
List<int> indices(int count) => List.generate(count, (i) => i);
List<int> competitionRanks(List<Fraction> values) => [
  for (final value in values) 1 + values.where((other) => other.compareTo(value) > 0).length
];
List<Fraction> roundedValues(List<double> values, int places) =>
    values.map((value) => Fraction(decimalValue(value, places))).toList();
List<Fraction> negativeValues(List<int> values) =>
    values.map((value) => Fraction(-value)).toList();
String resultLetter(int scored, int conceded) => scored > conceded ? 'W' : scored == conceded ? 'D' : 'L';
String resultCode(int result2) => result2 == 2 ? 'H' : result2 == 0 ? 'A' : 'D';

class Appearance {
  final Match match;
  final bool home;
  final int opponent;
  final int scored;
  final int conceded;
  Appearance(this.match, int team)
      : home = match.home == team,
        opponent = match.home == team ? match.away : match.home,
        scored = match.home == team ? match.homeScore : match.awayScore,
        conceded = match.home == team ? match.awayScore : match.homeScore;
  String get letter => resultLetter(scored, conceded);
}
List<Appearance> appearancesOf(int team, List<Match> matches) => [
  for (final match in matches) if (match.home == team || match.away == team) Appearance(match, team)
];
String recordText(List<Appearance> items) =>
    '${items.where((item) => item.letter == 'W').length}-'
    '${items.where((item) => item.letter == 'D').length}-'
    '${items.where((item) => item.letter == 'L').length}';

class Record {
  var played = 0;
  var won = 0;
  var drawn = 0;
  var lost = 0;
  var scored = 0;
  var conceded = 0;
  var points = 0;
  int get difference => scored - conceded;
  Fraction get percentage => Fraction(2 * won + drawn, 2 * played);
  void add(int scored, int conceded, Settings settings) {
    played++;
    this.scored += scored;
    this.conceded += conceded;
    if (scored > conceded) {
      won++;
      points += settings.winPoints;
    } else if (scored == conceded) {
      drawn++;
      points += settings.drawPoints;
    } else {
      lost++;
    }
  }
}
List<Record> teamRecords(int count, List<Match> matches, Settings settings) {
  final records = List.generate(count, (_) => Record());
  for (final match in matches) {
    records[match.home].add(match.homeScore, match.awayScore, settings);
    records[match.away].add(match.awayScore, match.homeScore, settings);
  }
  return records;
}

class Standings {
  final List<Record> records;
  final List<int> h2hPoints;
  final List<int> h2hDifference;
  final List<int> order;
  final List<int> positions;
  Standings(List<Team> teams, List<Match> matches, Settings settings)
      : records = teamRecords(teams.length, matches, settings),
        h2hPoints = List.filled(teams.length, 0),
        h2hDifference = List.filled(teams.length, 0),
        order = indices(teams.length), positions = List.filled(teams.length, 0) {
    for (final match in matches) {
      final i = match.home;
      final j = match.away;
      if (records[i].points != records[j].points) continue;
      h2hDifference[i] += match.margin;
      h2hDifference[j] -= match.margin;
      if (match.margin > 0) {
        h2hPoints[i] += settings.winPoints;
      } else if (match.margin < 0) {
        h2hPoints[j] += settings.winPoints;
      } else {
        h2hPoints[i] += settings.drawPoints;
        h2hPoints[j] += settings.drawPoints;
      }
    }
    order.sort((a, b) {
      final first = [records[a].points, h2hPoints[a], h2hDifference[a], records[a].difference, records[a].scored];
      final second = [records[b].points, h2hPoints[b], h2hDifference[b], records[b].difference, records[b].scored];
      for (var k = 0; k < first.length; k++) {
        if (first[k] != second[k]) return second[k].compareTo(first[k]);
      }
      return teams[a].code.compareTo(teams[b].code);
    });
    for (var i = 0; i < order.length; i++) {
      positions[order[i]] = i + 1;
    }
  }

  List<List<int>> tiedGroups() {
    final groups = <List<int>>[];
    for (final team in order) {
      if (groups.isNotEmpty && records[groups.last.first].points == records[team].points) {
        groups.last.add(team);
      } else {
        groups.add([team]);
      }
    }
    return groups.where((group) => group.length > 1).toList();
  }
}

class Streak {
  final int length;
  final int first;
  final int last;
  Streak(this.length, this.first, this.last);
}
Streak longestStreak(List<Appearance> items, bool unbeaten) {
  var best = Streak(0, 0, 0);
  var start = 0;
  var length = 0;
  for (var i = 0; i < items.length; i++) {
    if (items[i].letter != 'W' && !(unbeaten && items[i].letter == 'D')) {
      length = 0;
      continue;
    }
    if (length == 0) start = i;
    length++;
    if (length > best.length) best = Streak(length, items[start].match.round, items[i].match.round);
  }
  return best;
}
String currentStreak(List<Appearance> items) {
  final letter = items.last.letter;
  var count = 0;
  for (final item in items.reversed) {
    if (item.letter != letter) break;
    count++;
  }
  return '$letter$count';
}

class ModelFit {
  late EloRun elo;
  late List<double> colley;
  late List<double> massey;
  late double homeAdvantage;
  late List<double> strengths;
  late double homeFactor;
  late List<double> offense;
  late List<double> defense;
  late List<double> od;
  late List<Fraction> winPercentages;
  ModelFit(int count, List<Match> matches, Settings settings) {
    elo = runElo(count, matches, settings.eloK, settings.eloHome, settings.eloInitial);
    colley = colleyRatings(count, matches);
    final mass = masseyRatings(count, matches);
    massey = mass.$1;
    homeAdvantage = mass.$2;
    final bt = bradleyTerry(count, matches, settings.btIterations);
    strengths = bt.$1;
    homeFactor = bt.$2;
    final values = offenseDefense(count, matches, settings.odIterations);
    offense = values.$1;
    defense = values.$2;
    od = values.$3;
    winPercentages = teamRecords(count, matches, settings).map((record) => record.percentage).toList();
  }

  double feature(String model, Match match) {
    final i = match.home;
    final j = match.away;
    if (model == 'colley') return colley[i] - colley[j];
    if (model == 'massey') return massey[i] - massey[j];
    if (model == 'od') return math.log(od[i]) - math.log(od[j]);
    return winPercentages[i].real - winPercentages[j].real;
  }
  double btProbability(Match match) {
    final home = homeFactor * strengths[match.home];
    return home / (home + strengths[match.away]);
  }
}

class Prediction {
  final Match match;
  final List<double> probabilities;
  final double marginError;
  late List<double> losses;
  late List<double> briers;
  late List<int> scores2;
  Prediction(this.match, this.probabilities, this.marginError) {
    losses = [for (final p in probabilities) logLoss(p, match.result2)];
    briers = [for (final p in probabilities) brierScore(p, match.y)];
    scores2 = [for (final p in probabilities) correctness2(p, match.result2)];
  }
}

class ValidationRound {
  final int number;
  final List<Match> training;
  final ModelFit fit;
  late double base;
  final links = <String, (double, double)>{};
  final predictions = <Prediction>[];
  ValidationRound(this.number, int count, List<Match> matches, Settings settings)
      : training = matchesBefore(matches, number),
        fit = ModelFit(count, matchesBefore(matches, number), settings) {
    var y2 = 0;
    for (final match in training) {
      y2 += match.result2;
    }
    base = y2 / (2 * training.length);
    final results = training.map((match) => match.y).toList();
    for (final model in linkModels) {
      links[model] = fitLink(training.map((match) => fit.feature(model, match)).toList(), results, settings.linkIterations);
    }
    for (final match in matches.where((match) => match.round == number)) {
      final p = List.filled(8, 0.0);
      p[0] = base;
      p[1] = expectedScore(fit.elo.ratings[match.home], fit.elo.ratings[match.away], settings.eloHome);
      p[4] = fit.btProbability(match);
      for (final model in linkModels) {
        final (alpha, beta) = links[model]!;
        p[predictionModels.indexOf(model)] = sigma(alpha + beta * fit.feature(model, match));
      }
      p[7] = sequentialSum([for (final k in [1, 2, 3, 4, 5, 6]) p[k]]) / 6;
      final margin = fit.massey[match.home] - fit.massey[match.away] + fit.homeAdvantage;
      predictions.add(Prediction(match, p, match.margin - margin));
    }
  }
}

class ModelScores {
  final losses = List.filled(8, 0.0);
  final briers = List.filled(8, 0.0);
  final skills = List.filled(8, 0.0);
  final accuracies = <Fraction>[];
  final lossRanking = indices(8);
  final brierRanking = indices(8);
  final accuracyRanking = indices(8);
  ModelScores(List<Prediction> predictions) {
    for (var k = 0; k < 8; k++) {
      losses[k] = mean(predictions.map((item) => item.losses[k]).toList());
      briers[k] = mean(predictions.map((item) => item.briers[k]).toList());
      var score2 = 0;
      for (final prediction in predictions) {
        score2 += prediction.scores2[k];
      }
      accuracies.add(Fraction(score2, 2 * predictions.length));
    }
    for (var k = 0; k < 8; k++) {
      skills[k] = 1 - briers[k] / briers[0];
    }
    int tie(int compared, int a, int b) => compared != 0 ? compared : a.compareTo(b);
    lossRanking.sort((a, b) => tie(decimalValue(losses[a], 4).compareTo(decimalValue(losses[b], 4)), a, b));
    brierRanking.sort((a, b) => tie(decimalValue(briers[a], 4).compareTo(decimalValue(briers[b], 4)), a, b));
    accuracyRanking.sort((a, b) => tie(accuracies[b].compareTo(accuracies[a]), a, b));
  }
}

class Projection {
  final Standings current;
  final List<double> ratings;
  final List<Match> remaining;
  final List<int> totalPoints;
  final List<int> titles;
  final List<int> tops;
  final List<int> bottoms;
  late List<int> order;
  late List<int> ranks;
  Projection(List<Team> teams, List<Match> matches, Settings settings)
      : current = Standings(teams, matchesBefore(matches, settings.holdout), settings),
        ratings = runElo(teams.length, matchesBefore(matches, settings.holdout), settings.eloK, settings.eloHome, settings.eloInitial).ratings,
        remaining = matches.where((match) => match.round >= settings.holdout).toList(),
        totalPoints = List.filled(teams.length, 0), titles = List.filled(teams.length, 0),
        tops = List.filled(teams.length, 0), bottoms = List.filled(teams.length, 0) {
    final probabilities = [for (final match in remaining) expectedScore(ratings[match.home], ratings[match.away], settings.eloHome)];
    var state = settings.seed;
    for (var simulation = 0; simulation < settings.simulations; simulation++) {
      final points = current.records.map((record) => record.points).toList();
      for (var i = 0; i < remaining.length; i++) {
        final match = remaining[i];
        state = (48271 * state) % 2147483647;
        if (state / 2147483647 < probabilities[i]) {
          points[match.home] += settings.winPoints;
        } else {
          points[match.away] += settings.winPoints;
        }
      }
      final result = rankOrder(points);
      for (var place = 0; place < result.length; place++) {
        final team = result[place];
        totalPoints[team] += points[team];
        if (place == 0) titles[team]++;
        if (place < settings.top) tops[team]++;
        if (place >= teams.length - settings.bottom) bottoms[team]++;
      }
    }
    order = rankOrder(totalPoints);
    ranks = List.filled(teams.length, 0);
    for (var i = 0; i < order.length; i++) {
      ranks[order[i]] = i + 1;
    }
  }

  List<int> rankOrder(List<int> points) => indices(points.length)..sort((a, b) {
    final compared = points[b].compareTo(points[a]);
    return compared != 0 ? compared : current.positions[a].compareTo(current.positions[b]);
  });
  double opponentStrength(int team) => mean([
    for (final match in remaining)
      if (match.home == team) ratings[match.away]
      else if (match.away == team) ratings[match.home]
  ]);
}

class LeagueAnalysis {
  final List<Team> teams;
  final List<Match> matches;
  final Settings settings;
  late int count;
  late int finalRound;
  late List<List<Appearance>> appearances;
  late Standings finalTable;
  late ModelFit fit;
  late List<Standings> roundTables;
  late List<Streak> winStreaks;
  late List<Streak> unbeatenStreaks;
  late List<Fraction> sos;
  late List<Fraction> sos2;
  late List<Fraction> rpi;
  late List<double> pythag;
  late List<double> luck;
  late Map<String, List<Fraction>> comparison;
  late Map<String, List<int>> ranks;
  late List<ValidationRound> rounds;
  late List<Prediction> predictions;
  late ModelScores scores;
  late Projection projection;
  LeagueAnalysis(this.teams, this.matches, this.settings) {
    count = teams.length;
    finalRound = matches.last.round;
    appearances = [for (var team = 0; team < count; team++) appearancesOf(team, matches)];
    finalTable = Standings(teams, matches, settings);
    fit = ModelFit(count, matches, settings);
    roundTables = [for (var r = 1; r <= finalRound; r++) Standings(teams, matchesBefore(matches, r + 1), settings)];
    winStreaks = appearances.map((items) => longestStreak(items, false)).toList();
    unbeatenStreaks = appearances.map((items) => longestStreak(items, true)).toList();
    sos = [for (var team = 0; team < count; team++) opponentAverage(team, fit.winPercentages)];
    sos2 = [for (var team = 0; team < count; team++) opponentAverage(team, sos)];
    rpi = [for (var team = 0; team < count; team++) (fit.winPercentages[team] + sos[team] * Fraction(2) + sos2[team]).dividedBy(4)];
    pythag = [for (final record in finalTable.records) 1 / (1 + math.pow(record.conceded / record.scored, settings.exponent))];
    luck = [for (var team = 0; team < count; team++) fit.winPercentages[team].real - pythag[team]];
    comparison = {
      'standings': negativeValues(finalTable.positions), 'elo': roundedValues(fit.elo.ratings, 2),
      'colley': roundedValues(fit.colley, 4), 'massey': roundedValues(fit.massey, 4),
      'bt': roundedValues(fit.strengths, 4), 'od': roundedValues(fit.od, 2),
      'winpct': fit.winPercentages, 'rpi': rpi, 'pythag': roundedValues(pythag, 4),
    };
    ranks = {for (final model in ratingModels) model: competitionRanks(comparison[model]!)};
    rounds = [for (var r = settings.holdout; r <= finalRound; r++) ValidationRound(r, count, matches, settings)];
    predictions = [for (final round in rounds) ...round.predictions];
    scores = ModelScores(predictions);
    projection = Projection(teams, matches, settings);
  }

  Fraction opponentAverage(int team, List<Fraction> values) {
    var total = Fraction(0);
    for (final appearance in appearances[team]) {
      total += values[appearance.opponent];
    }
    return total.dividedBy(appearances[team].length);
  }
  String code(int team) => teams[team].code;

  List<String> standingsLines() {
    final lines = [standingsHeader];
    for (var position = 0; position < count; position++) {
      final team = finalTable.order[position];
      final record = finalTable.records[team];
      final items = appearances[team];
      final form = items.skip(items.length - settings.formLength).map((item) => item.letter).join();
      lines.add(csv([
        position + 1, code(team), teams[team].name, record.played, record.won, record.drawn,
        record.lost, record.scored, record.conceded, record.difference, record.points,
        recordText(items.where((item) => item.home).toList()),
        recordText(items.where((item) => !item.home).toList()), form, currentStreak(items),
        recordText(items.where((item) => (item.scored - item.conceded).abs() <= settings.closeMargin).toList()),
        winStreaks[team].length, unbeatenStreaks[team].length, fit.winPercentages[team],
        fixedFraction(sos[team]), fixedFraction(sos2[team]), fixedFraction(rpi[team]),
        fixed(pythag[team]), fixed(luck[team]),
      ]));
    }
    return lines;
  }

  List<String> ratingsLines() {
    final totals = [for (var team = 0; team < count; team++) ratingModels.fold<int>(0, (sum, model) => sum + ranks[model]![team])];
    final order = indices(count)..sort((a, b) {
      final compared = totals[a].compareTo(totals[b]);
      return compared != 0 ? compared : code(a).compareTo(code(b));
    });
    final lines = [ratingsHeader];
    for (final team in order) {
      final values = [for (final model in ratingModels) ranks[model]![team]];
      lines.add(csv([
        code(team), fixed(fit.elo.ratings[team], 2), ranks['elo']![team],
        fixed(fit.colley[team]), ranks['colley']![team], fixed(fit.massey[team]), ranks['massey']![team],
        fixed(fit.strengths[team]), ranks['bt']![team], fixed(fit.offense[team], 2),
        fixed(fit.defense[team]), fixed(fit.od[team], 2), ranks['od']![team],
        fixedFraction(fit.winPercentages[team]), ranks['winpct']![team], totals[team],
        values.reduce((a, b) => a < b ? a : b), values.reduce((a, b) => a > b ? a : b),
      ]));
    }
    return lines;
  }

  List<String> historyLines() {
    final lines = [historyHeader];
    var previous = List.filled(count, settings.eloInitial.toDouble());
    for (var r = 0; r < finalRound; r++) {
      final ratings = fit.elo.rounds[r];
      final eloRanks = competitionRanks(roundedValues(ratings, 2));
      for (var team = 0; team < count; team++) {
        lines.add(csv([r + 1, code(team), fixed(ratings[team], 2), fixed(ratings[team] - previous[team], 2),
          eloRanks[team], roundTables[r].records[team].points, roundTables[r].positions[team]]));
      }
      previous = ratings;
    }
    return lines;
  }

  List<String> summaryLines() {
    var y2 = 0;
    for (final match in matches) {
      y2 += match.result2;
    }
    return [
      'season teams $count matches ${matches.length} rounds $finalRound',
      'home won ${matches.where((match) => match.result2 == 2).length} drawn ${matches.where((match) => match.result2 == 1).length} '
          'lost ${matches.where((match) => match.result2 == 0).length} rate ${fractionWithReal(Fraction(y2, 2 * matches.length))}',
      'massey_home_advantage ${fixed(fit.homeAdvantage)}',
      'bt_home_factor ${fixed(fit.homeFactor)}',
    ];
  }

  List<String> upsetLines() {
    final candidates = <(int, double, double)>[];
    for (var i = 0; i < matches.length; i++) {
      if (matches[i].margin == 0) continue;
      final expected = matches[i].margin > 0 ? fit.elo.expected[i] : 1 - fit.elo.expected[i];
      candidates.add((i, expected, fit.elo.changes[i].abs()));
    }
    candidates.sort((a, b) {
      final compared = decimalValue(a.$2, 4).compareTo(decimalValue(b.$2, 4));
      return compared != 0 ? compared : a.$1.compareTo(b.$1);
    });
    final lines = ['upsets top ${settings.upsets}'];
    for (final item in candidates.take(settings.upsets)) {
      final match = matches[item.$1];
      final home = match.margin > 0;
      final winner = home ? match.home : match.away;
      final loser = home ? match.away : match.home;
      final score = home ? '${match.homeScore}-${match.awayScore}' : '${match.awayScore}-${match.homeScore}';
      lines.add('round ${match.round} ${code(winner)} beat ${code(loser)} $score ${home ? 'home' : 'away'} expected ${fixed(item.$2)} gain ${fixed(item.$3, 2)}');
    }
    return lines;
  }

  List<String> tiebreakLines() {
    final lines = ['tiebreaks'];
    for (final group in finalTable.tiedGroups()) {
      lines.add('points ${finalTable.records[group.first].points} order ${group.map(code).join(' ')} '
          'h2h_points ${group.map((team) => finalTable.h2hPoints[team]).join(' ')} '
          'h2h_diff ${group.map((team) => finalTable.h2hDifference[team]).join(' ')}');
    }
    if (lines.length == 1) lines.add('none');
    return lines;
  }

  List<String> leaderLines() {
    final lines = ['leaders'];
    var previous = -1;
    var recorded = 0;
    for (var r = 0; r < finalRound; r++) {
      final table = roundTables[r];
      final leader = table.order.first;
      if (leader != previous) {
        lines.add('round ${r + 1} ${code(leader)} points ${table.records[leader].points}');
        recorded++;
      }
      previous = leader;
    }
    lines.add('lead_changes ${recorded - 1}');
    return lines;
  }

  List<String> streakLines() {
    final lines = <String>[];
    for (final (label, streaks) in [('longest_win_streak', winStreaks), ('longest_unbeaten_streak', unbeatenStreaks)]) {
      final longest = streaks.map((streak) => streak.length).reduce((a, b) => a > b ? a : b);
      for (var team = 0; team < count; team++) {
        final streak = streaks[team];
        if (streak.length == longest) lines.add('$label ${code(team)} length ${streak.length} rounds ${streak.first}-${streak.last}');
      }
    }
    return lines;
  }

  List<String> crosstableLines() {
    final top = finalTable.order.take(settings.top).toList();
    return [
      'crosstable top ${settings.top}', 'team ${top.map(code).join(' ')}',
      for (final first in top)
        '${code(first)} ${[for (final second in top) first == second ? '-' : recordText(appearances[first].where((item) => item.opponent == second).toList())].join(' ')}',
    ];
  }

  List<String> trajectoryLines() {
    final lines = ['trajectories'];
    for (var team = 0; team < count; team++) {
      var peak = 0;
      var low = 0;
      var best = 0;
      var worst = 0;
      final ratings = [for (final snapshot in fit.elo.rounds) snapshot[team]];
      final positions = [for (final table in roundTables) table.positions[team]];
      for (var r = 1; r < finalRound; r++) {
        if (decimalValue(ratings[r], 2) > decimalValue(ratings[peak], 2)) peak = r;
        if (decimalValue(ratings[r], 2) < decimalValue(ratings[low], 2)) low = r;
        if (positions[r] < positions[best]) best = r;
        if (positions[r] > positions[worst]) worst = r;
      }
      lines.add('${code(team)} elo_peak ${fixed(ratings[peak], 2)} round ${peak + 1} '
          'elo_low ${fixed(ratings[low], 2)} round ${low + 1} '
          'best_position ${positions[best]} round ${best + 1} worst_position ${positions[worst]} round ${worst + 1}');
    }
    return lines;
  }

  List<String> correlationLines(String title, Fraction Function(List<Fraction>, List<Fraction>) measure) => [
    title, 'model ${comparisonModels.join(' ')}',
    for (final first in comparisonModels)
      '$first ${[for (final second in comparisonModels) measure(comparison[first]!, comparison[second]!)].join(' ')}',
  ];

  List<String> similarityLines() {
    (String, String, Fraction)? most;
    (String, String, Fraction)? least;
    for (var i = 0; i < comparisonModels.length; i++) {
      final first = comparisonModels[i];
      for (final second in comparisonModels.skip(i + 1)) {
        final tau = kendallTau(comparison[first]!, comparison[second]!);
        if (most == null || tau.compareTo(most.$3) > 0) most = (first, second, tau);
        if (least == null || tau.compareTo(least.$3) < 0) least = (first, second, tau);
      }
    }
    final mostValue = most!;
    final leastValue = least!;
    return ['most_similar ${mostValue.$1} ${mostValue.$2} tau ${fractionWithReal(mostValue.$3)}',
      'least_similar ${leastValue.$1} ${leastValue.$2} tau ${fractionWithReal(leastValue.$3)}'];
  }

  List<String> seasonLines() => joinParts([
    summaryLines(), upsetLines(), tiebreakLines(), leaderLines(), streakLines(), crosstableLines(),
    trajectoryLines(), correlationLines('kendall', kendallTau), correlationLines('spearman', spearmanRho), similarityLines(),
  ]);

  List<String> predictionLines() => [
    'round,home,away,home_score,away_score,result,${predictionModels.join(',')}',
    for (final item in predictions) csv([
      item.match.round, code(item.match.home), code(item.match.away), item.match.homeScore,
      item.match.awayScore, resultCode(item.match.result2), ...item.probabilities.map((p) => fixed(p)),
    ]),
  ];

  List<String> linkLines() => [
    'links',
    for (final round in rounds)
      'round ${round.number} train ${round.training.length} base ${fixed(round.base)} bt_home ${fixed(round.fit.homeFactor)} '
          '${[for (final model in linkModels) '$model ${fixed(round.links[model]!.$1)} ${fixed(round.links[model]!.$2)}'].join(' ')}',
  ];

  List<String> scoreLines() => [
    'scores', 'model log_loss brier skill accuracy',
    for (var k = 0; k < predictionModels.length; k++)
      '${predictionModels[k]} ${fixed(scores.losses[k])} ${fixed(scores.briers[k])} ${fixed(scores.skills[k])} ${fractionWithReal(scores.accuracies[k])}',
    'ranking_log_loss ${scores.lossRanking.map((k) => predictionModels[k]).join(' ')}',
    'ranking_brier ${scores.brierRanking.map((k) => predictionModels[k]).join(' ')}',
    'ranking_accuracy ${scores.accuracyRanking.map((k) => predictionModels[k]).join(' ')}',
  ];

  List<String> pairedLines() {
    final reference = scores.lossRanking.first;
    final count = predictions.length;
    final lines = ['paired_log_loss reference ${predictionModels[reference]}'];
    for (var k = 0; k < predictionModels.length; k++) {
      if (k == reference) continue;
      final deltas = predictions.map((item) => item.losses[k] - item.losses[reference]).toList();
      final average = mean(deltas);
      final squares = sequentialSum(deltas.map((delta) => (delta - average) * (delta - average)));
      final spread = math.sqrt(squares / (count - 1));
      final t = average / (spread / math.sqrt(count));
      lines.add('${predictionModels[k]} mean_diff ${fixed(average)} sd ${fixed(spread)} t ${fixed(t, 2)}');
    }
    return lines;
  }

  List<String> marginLines() {
    final errors = predictions.map((item) => item.marginError).toList();
    final absolute = mean(errors.map((error) => error.abs()).toList());
    final squared = math.sqrt(mean(errors.map((error) => error * error).toList()));
    return ['massey_margin mae ${fixed(absolute)} rmse ${fixed(squared)} bias ${fixed(mean(errors))}'];
  }

  List<String> roundLossLines() => [
    'round_log_loss', 'round ${predictionModels.join(' ')}',
    for (final round in rounds)
      '${round.number} ${[for (var k = 0; k < 8; k++) fixed(mean(round.predictions.map((item) => item.losses[k]).toList()))].join(' ')}',
  ];

  List<String> calibrationLines() {
    final bins = settings.bins;
    final lines = ['calibration bins $bins'];
    for (var k = 0; k < 8; k++) {
      final members = List.generate(bins, (_) => <Prediction>[]);
      for (final item in predictions) {
        var bin = (bins * item.probabilities[k]).floor();
        if (bin >= bins) bin = bins - 1;
        members[bin].add(item);
      }
      for (var number = 0; number < bins; number++) {
        final group = members[number];
        final prefix = '${predictionModels[k]} bin ${number + 1} count ${group.length} predicted';
        if (group.isEmpty) {
          lines.add('$prefix - observed -');
        } else {
          var y2 = 0;
          for (final item in group) {
            y2 += item.match.result2;
          }
          final predicted = mean(group.map((item) => item.probabilities[k]).toList());
          lines.add('$prefix ${fixed(predicted)} observed ${Fraction(y2, 2 * group.length)}');
        }
      }
    }
    return lines;
  }

  List<String> gridLines() {
    final lines = ['elo_grid', 'k ${settings.gridHome.map((home) => 'h$home').join(' ')}'];
    (int, int, double)? best;
    for (final k in settings.gridK) {
      final row = [k.toString()];
      for (final home in settings.gridHome) {
        final run = runElo(count, matches, k, home, settings.eloInitial);
        final loss = mean([
          for (var i = 0; i < matches.length; i++)
            if (matches[i].round >= settings.holdout) logLoss(run.expected[i], matches[i].result2)
        ]);
        row.add(fixed(loss));
        if (best == null || decimalValue(loss, 4) < decimalValue(best.$3, 4)) best = (k, home, loss);
      }
      lines.add(row.join(' '));
    }
    final bestValue = best!;
    lines.add('best k ${bestValue.$1} home ${bestValue.$2} log_loss ${fixed(bestValue.$3)}');
    return lines;
  }

  Fraction projectionTau() => kendallTau(negativeValues(projection.ranks), negativeValues(finalTable.positions));
  List<String> evaluationLines() => joinParts([
    ['holdout rounds ${settings.holdout}-$finalRound matches ${predictions.length}'], linkLines(),
    scoreLines(), pairedLines(), marginLines(), roundLossLines(), calibrationLines(), gridLines(),
    ['projection simulations ${settings.simulations} kendall ${fractionWithReal(projectionTau())}'],
  ]);

  List<String> projectionLines() => [
    projectionHeader,
    for (var i = 0; i < projection.order.length; i++) projectionRow(i + 1, projection.order[i]),
  ];
  String projectionRow(int rank, int team) {
    final p = projection;
    final simulations = settings.simulations;
    return csv([rank, code(team), p.current.records[team].points, p.current.positions[team],
      fixed(p.opponentStrength(team), 2), fixedFraction(Fraction(p.totalPoints[team], simulations)),
      fixedFraction(Fraction(p.titles[team], simulations)), fixedFraction(Fraction(p.tops[team], simulations)), fixedFraction(Fraction(p.bottoms[team], simulations)),
      finalTable.records[team].points, finalTable.positions[team]]);
  }
}

void main() {
  final (teams, matches, settings) = loadSeason();
  final analysis = LeagueAnalysis(teams, matches, settings);
  Directory('output').createSync(recursive: true);
  writeLines('standings.csv', analysis.standingsLines());
  writeLines('ratings.csv', analysis.ratingsLines());
  writeLines('history.csv', analysis.historyLines());
  writeLines('season.txt', analysis.seasonLines());
  writeLines('predictions.csv', analysis.predictionLines());
  writeLines('evaluation.txt', analysis.evaluationLines());
  writeLines('projection.csv', analysis.projectionLines());
}
