import 'dart:io';

class Team {
  final String code;
  final String name;
  Team(this.code, this.name);
}

class Match {
  final int round;
  final int home;
  final int away;
  final int homeScore;
  final int awayScore;
  Match(this.round, this.home, this.away, this.homeScore, this.awayScore);
  int get margin => homeScore - awayScore;
  int get result2 => homeScore > awayScore ? 2 : homeScore == awayScore ? 1 : 0;
  double get y => result2 / 2;
}

class Settings {
  final Map<String, List<String>> values;
  Settings(this.values);
  int value(String key) => int.parse(values[key]![0]);
  List<int> integers(String key) => values[key]!.map(int.parse).toList();
  int get winPoints => value('WIN_POINTS');
  int get drawPoints => value('DRAW_POINTS');
  int get formLength => value('FORM_LENGTH');
  int get closeMargin => value('CLOSE_MARGIN');
  double get exponent => double.parse(values['PYTHAGOREAN_EXPONENT']![0]);
  int get eloK => value('ELO_K');
  int get eloHome => value('ELO_HOME');
  int get eloInitial => value('ELO_INITIAL');
  List<int> get gridK => integers('ELO_GRID_K');
  List<int> get gridHome => integers('ELO_GRID_HOME');
  int get btIterations => value('BT_ITERATIONS');
  int get odIterations => value('OD_ITERATIONS');
  int get linkIterations => value('LINK_ITERATIONS');
  int get holdout => value('HOLDOUT_ROUND');
  int get upsets => value('UPSETS');
  int get bins => value('CALIBRATION_BINS');
  int get simulations => value('SIMULATIONS');
  int get seed => value('SIM_SEED');
  int get top => value('TOP_POSITIONS');
  int get bottom => value('BOTTOM_POSITIONS');
}

List<String> readLines(String path) => File(path).readAsLinesSync();
List<Match> matchesBefore(List<Match> matches, int round) =>
    matches.where((match) => match.round < round).toList();

(List<Team>, List<Match>, Settings) loadSeason() {
  final teams = <Team>[];
  final indices = <String, int>{};
  for (final line in readLines('input/teams.csv').skip(1)) {
    final fields = line.split(',');
    indices[fields[0]] = teams.length;
    teams.add(Team(fields[0], fields[1]));
  }
  final numbered = <(int, Match)>[];
  for (final line in readLines('input/matches.csv').skip(1)) {
    final f = line.split(',');
    numbered.add((numbered.length, Match(int.parse(f[0]), indices[f[1]]!,
        indices[f[2]]!, int.parse(f[3]), int.parse(f[4]))));
  }
  numbered.sort((a, b) {
    final roundOrder = a.$2.round.compareTo(b.$2.round);
    return roundOrder != 0 ? roundOrder : a.$1.compareTo(b.$1);
  });
  final values = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final fields = line.split(' ');
    values[fields[0]] = fields.sublist(1);
  }
  return (teams, numbered.map((entry) => entry.$2).toList(), Settings(values));
}
