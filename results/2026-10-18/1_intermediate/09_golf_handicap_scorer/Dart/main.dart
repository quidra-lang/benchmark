import 'dart:io';
import 'dart:math' as math;

int number(String s) => int.parse(s);
int sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);
int away(int n, int d) => n < 0 ? -((-n * 2 + d) ~/ (2 * d)) : (n * 2 + d) ~/ (2 * d);
int floorDiv(int n, int d) => n >= 0 ? n ~/ d : -((-n + d - 1) ~/ d);
int halfUp(int n, int d) => floorDiv(2 * n + d, 2 * d);
String dec(int v) => '${v < 0 ? '-' : ''}${v.abs() ~/ 10}.${v.abs() % 10}';
String indexText(int? v) => v == null ? 'none' : v < 0 ? '+${dec(-v)}' : dec(v);
String hcpText(int? h) => h == null ? 'none' : h < 0 ? '+${-h}' : '$h';
String two(int n, int d) { final q = n * 100 ~/ d; return '${q ~/ 100}.${(q % 100).toString().padLeft(2, '0')}'; }
String status(int lead) => lead == 0 ? 'AS' : lead > 0 ? '$lead UP' : '${-lead} DN';
class GolfError implements Exception { final String reason; GolfError(this.reason); }
Never fail(String s) => throw GolfError(s);
class Tee { final String id; final int rating, slope; Tee(this.id, this.rating, this.slope); }
class Course {
  final String id;
  final List<int> pars, si;
  final tees = <String, Tee>{};
  Course(this.id, this.pars, this.si);
  int get par => sum(pars);
}
class Calculation {
  final int k, average, adjustment;
  final int? low;
  final bool hard, soft, maximum;
  Calculation(this.k, this.average, this.adjustment, this.low, this.hard, this.soft, this.maximum);
}
class Round {
  final Course course;
  final Tee tee;
  final int day, ags, diff, exceptional;
  final List<int?> scores;
  final List<int> adjusted;
  final int? handicap, oldIndex;
  final Calculation? oldCalculation;
  final int oldRecords;
  Round(this.course, this.tee, this.day, this.scores, this.handicap, this.adjusted, this.ags, this.diff, this.exceptional, this.oldIndex, this.oldCalculation, this.oldRecords);
}
class Player {
  final String id, name;
  int? index;
  Calculation? calculation;
  final rounds = <Round>[], records = <(int, int)>[];
  Player(this.id, this.name, this.index);
}
class Pick { final int number, value; bool counting = false; Pick(this.number, this.value); }
class Event {
  final String id, format;
  final Course course;
  final Tee tee;
  final int day, allowance;
  final List<Player> players;
  Event(this.id, this.format, this.course, this.tee, this.day, this.allowance, this.players);
}
class Result {
  final Event event;
  final List<Round> rounds;
  final List<int> ph;
  final List<List<int?>> nets;
  final List<List<int>> points;
  Result(this.event, this.rounds, this.ph, this.nets, this.points);
}
List<int> allocation(int h, Course c) {
  if (h >= 0) return c.si.map((si) => h ~/ 18 + (si <= h % 18 ? 1 : 0)).toList();
  return c.si.map((si) => -((-h) ~/ 18) - (si >= 19 - (-h) % 18 ? 1 : 0)).toList();
}
int handicap(int index, Course c, Tee t) => halfUp(index * t.slope + 113 * (t.rating - 10 * c.par), 1130);
int points(int? net, int par) => net == null ? 0 : math.max(0, par + 2 - net);
(int, int) countRule(int n) {
  if (n <= 5) return (1, n == 3 ? -20 : n == 4 ? -10 : 0);
  if (n == 6) return (2, -10);
  return (n <= 8 ? 2 : n <= 11 ? 3 : n <= 14 ? 4 : n <= 16 ? 5 : n <= 18 ? 6 : n == 19 ? 7 : 8, 0);
}
List<Pick> eligible(Player p) {
  final result = <Pick>[];
  var reduction = 0;
  for (var i = p.rounds.length - 1; i >= math.max(0, p.rounds.length - 20); i--) {
    reduction += p.rounds[i].exceptional;
    result.add(Pick(i + 1, p.rounds[i].diff - reduction));
  }
  if (result.length >= 3) {
    final ranked = result.toList()..sort((a, b) { final c = a.value.compareTo(b.value); return c != 0 ? c : b.number.compareTo(a.number); });
    for (final pick in ranked.take(countRule(result.length).$1)) pick.counting = true;
  }
  return result.reversed.toList();
}
(int, int)? lowIndex(Player p, int day) {
  (int, int)? best;
  for (final r in p.records) {
    if (r.$1 >= day - 365 && r.$1 < day && (best == null || r.$2 < best.$2 || r.$2 == best.$2 && r.$1 < best.$1)) best = r;
  }
  return best;
}
int compareValues(List<int> a, List<int> b, bool higher) {
  for (final start in [0, 9, 12, 15, 17]) {
    final c = sum(a.skip(start)).compareTo(sum(b.skip(start)));
    if (c != 0) return higher ? -c : c;
  }
  return 0;
}
class Golf {
  final courses = <String, Course>{}, players = <String, Player>{}, events = <String, Event>{};
  Player player(String id) => players[id] ?? fail('unknown player');
  Course course(String id) => courses[id] ?? fail('unknown course');
  Tee tee(Course c, String id) => c.tees[id] ?? fail('unknown tee');
  void update(Player p, int day) {
    final picks = eligible(p);
    if (picks.length < 3) { p.calculation = null; return; }
    final rule = countRule(picks.length);
    final avg = away(sum(picks.where((x) => x.counting).map((x) => x.value)), rule.$1);
    var value = avg + rule.$2;
    final low = lowIndex(p, day)?.$2;
    var soft = false, hard = false, maximum = false;
    if (low != null && value - low > 30) {
      final capped = low + 30 + (value - low - 30) ~/ 2;
      soft = capped != value; value = capped;
    }
    if (low != null && value - low > 50) { value = low + 50; hard = true; }
    if (value > 540) { value = 540; maximum = true; }
    p.index = value;
    p.calculation = Calculation(rule.$1, avg, rule.$2, low, hard, soft, maximum);
  }
  Result evaluate(Event e) {
    final rs = <Round>[];
    for (final p in e.players) {
      final candidates = p.rounds.where((r) => r.course == e.course && r.tee == e.tee && r.day == e.day);
      if (candidates.isEmpty) fail('missing round');
      final r = candidates.first;
      if (r.handicap == null) fail('no index');
      rs.add(r);
    }
    final ph = rs.map((r) => halfUp(r.handicap! * e.allowance, 100)).toList();
    final minimum = ph.reduce(math.min);
    final relative = ['MATCH', 'NASSAU', 'FOURBALL'].contains(e.format);
    final nets = <List<int?>>[], pts = <List<int>>[];
    for (var i = 0; i < rs.length; i++) {
      final strokes = allocation(ph[i] - (relative ? minimum : 0), e.course);
      final net = List<int?>.generate(18, (h) => rs[i].scores[h] == null || rs[i].scores[h]! <= 0 ? null : rs[i].scores[h]! - strokes[h]);
      nets.add(net); pts.add(List.generate(18, (h) => points(net[h], e.course.pars[h])));
    }
    return Result(e, rs, ph, nets, pts);
  }
  List<int> rank(Result r, {bool gross = false}) {
    final e = r.event, rows = <int>[];
    final values = <int, List<int>>{};
    for (var i = 0; i < e.players.length; i++) {
      if (e.format == 'STROKE' && r.nets[i].contains(null)) continue;
      rows.add(i);
      values[i] = gross ? r.rounds[i].scores.cast<int>() : e.format == 'STABLEFORD' ? r.points[i] : e.format == 'PAR' ? List.generate(18, (h) => r.nets[i][h] == null || r.nets[i][h]! > e.course.pars[h] ? -1 : r.nets[i][h] == e.course.pars[h] ? 0 : 1) : r.nets[i].cast<int>();
    }
    rows.sort((a, b) { final c = compareValues(values[a]!, values[b]!, !gross && e.format != 'STROKE'); return c != 0 ? c : e.players[a].id.compareTo(e.players[b].id); });
    return rows;
  }
  (List<String>, String) match(List<int> wins, int first, int end, String side1, String side2) {
    var lead = 0, remaining = end - first;
    final statuses = <String>[];
    for (var h = first; h < end; h++) {
      lead += wins[h]; remaining = end - h - 1; statuses.add(status(lead));
      if (lead.abs() > remaining) break;
    }
    final result = lead == 0 ? 'AS' : '${lead > 0 ? side1 : side2} ${lead.abs()}${remaining > 0 ? '&$remaining' : ' UP'}';
    return (statuses, result);
  }
  void results(Result r, StringBuffer out) {
    final e = r.event;
    out.writeln('results ${e.id}: ${e.format} ${e.course.id} ${e.tee.id} day ${e.day} allowance ${e.allowance}');
    if (['STROKE', 'STABLEFORD', 'PAR'].contains(e.format)) {
      final ranked = rank(r);
      for (var place = 0; place < ranked.length; place++) {
        final i = ranked[place], prefix = '${place + 1} ${e.players[i].id}';
        if (e.format == 'STROKE') { out.writeln('$prefix net ${sum(r.nets[i].cast<int>())} gross ${sum(r.rounds[i].scores.cast<int>())} hcp ${hcpText(r.ph[i])}');
        } else if (e.format == 'STABLEFORD') { out.writeln('$prefix points ${sum(r.points[i])} hcp ${hcpText(r.ph[i])}');
        } else {
          final record = sum(List.generate(18, (h) => r.nets[i][h] == null || r.nets[i][h]! > e.course.pars[h] ? -1 : r.nets[i][h] == e.course.pars[h] ? 0 : 1));
          out.writeln('$prefix ${status(record)} hcp ${hcpText(r.ph[i])}');
        }
      }
      if (e.format == 'STROKE') {
        final nr = List.generate(e.players.length, (i) => i).where((i) => r.nets[i].contains(null)).toList()..sort((a, b) => e.players[a].id.compareTo(e.players[b].id));
        for (final i in nr) out.writeln('NR ${e.players[i].id} hcp ${hcpText(r.ph[i])}');
        if (ranked.isNotEmpty) { final i = rank(r, gross: true).first; out.writeln('gross ${e.players[i].id} ${sum(r.rounds[i].scores.cast<int>())}'); }
      }
    } else if (['MATCH', 'NASSAU', 'FOURBALL'].contains(e.format)) {
      final minPH = r.ph.reduce(math.min);
      out.writeln('strokes ${List.generate(e.players.length, (i) => '${e.players[i].id} ${r.ph[i] - minPH}').join(' ')}');
      final four = e.format == 'FOURBALL';
      final side1 = four ? '${e.players[0].id}+${e.players[1].id}' : e.players[0].id;
      final side2 = four ? '${e.players[2].id}+${e.players[3].id}' : e.players[1].id;
      final wins = List<int>.generate(18, (h) {
        final a = (four ? [r.nets[0][h], r.nets[1][h]] : [r.nets[0][h]]).whereType<int>().toList();
        final b = (four ? [r.nets[2][h], r.nets[3][h]] : [r.nets[1][h]]).whereType<int>().toList();
        if (a.isEmpty) return b.isEmpty ? 0 : -1;
        if (b.isEmpty) return 1;
        return -a.reduce(math.min).compareTo(b.reduce(math.min));
      });
      if (e.format == 'NASSAU') {
        out.writeln('front ${match(wins, 0, 9, side1, side2).$2}');
        out.writeln('back ${match(wins, 9, 18, side1, side2).$2}');
        out.writeln('total ${match(wins, 0, 18, side1, side2).$2}');
      } else { final m = match(wins, 0, 18, side1, side2); out.writeln('status ${m.$1.join(', ')}'); out.writeln('result ${m.$2}'); }
    } else if (e.format == 'BETTERBALL') {
      final teams = List.generate(e.players.length ~/ 2, (i) => i);
      final values = List.generate(teams.length, (i) => List.generate(18, (h) => math.max(r.points[2 * i][h], r.points[2 * i + 1][h])));
      teams.sort((a, b) { final c = compareValues(values[a], values[b], true); return c != 0 ? c : e.players[2 * a].id.compareTo(e.players[2 * b].id); });
      for (var rank = 0; rank < teams.length; rank++) { final i = 2 * teams[rank]; out.writeln('${rank + 1} ${e.players[i].id}+${e.players[i + 1].id} points ${sum(values[i ~/ 2])} hcp ${hcpText(r.ph[i])} ${hcpText(r.ph[i + 1])}'); }
    } else {
      var carry = 0;
      final totals = List.filled(e.players.length, 0);
      List<int> winners(int h) {
        final ids = List.generate(e.players.length, (i) => i).where((i) => r.nets[i][h] != null).toList();
        if (ids.isEmpty) return [];
        final minNet = ids.map((i) => r.nets[i][h]!).reduce(math.min);
        return ids.where((i) => r.nets[i][h] == minNet).toList();
      }
      for (var h = 0; h < 18; h++) {
        carry++;
        final ws = winners(h);
        if (ws.length == 1) { final i = ws.first; totals[i] += carry * 100; out.writeln('hole ${h + 1} ${e.players[i].id} $carry'); carry = 0; }
      }
      if (carry > 0) {
        var ws = winners(17);
        if (ws.isEmpty) ws = List.generate(e.players.length, (i) => i);
        ws.sort((a, b) => e.players[a].id.compareTo(e.players[b].id));
        for (final i in ws) totals[i] += carry * 100 ~/ ws.length;
        out.writeln('carry $carry ${ws.map((i) => e.players[i].id).join(' ')}');
      }
      final ids = List.generate(e.players.length, (i) => i)..sort((a, b) { final c = totals[b].compareTo(totals[a]); return c != 0 ? c : e.players[a].id.compareTo(e.players[b].id); });
      for (final i in ids) out.writeln('${e.players[i].id} ${two(totals[i], 100)}');
    }
  }
  void card(Player p, int no, Round r, StringBuffer out) {
    final c = r.course, strokes = allocation(r.handicap ?? 0, r.course);
    final nets = List<int?>.generate(18, (h) => r.scores[h] == null || r.scores[h]! <= 0 ? null : r.scores[h]! - strokes[h]);
    final pts = List.generate(18, (h) => points(nets[h], c.pars[h]));
    out.writeln('card ${p.id} $no: ${c.id} ${r.tee.id} day ${r.day} handicap ${hcpText(r.handicap)}');
    void total(String label, int a, int b) {
      final complete = nets.sublist(a, b).every((n) => n != null);
      out.writeln('$label ${sum(c.pars.sublist(a, b))} ${complete ? sum(r.scores.sublist(a, b).cast<int>()) : '-'} ${sum(r.adjusted.sublist(a, b))} ${sum(strokes.sublist(a, b))} ${complete ? sum(nets.sublist(a, b).cast<int>()) : '-'} ${sum(pts.sublist(a, b))}');
    }
    for (var h = 0; h < 18; h++) {
      final score = r.scores[h] == null ? '-' : r.scores[h] == 0 ? 'X' : '${r.scores[h]}';
      out.writeln('${h + 1} ${c.pars[h]} ${c.si[h]} $score ${r.adjusted[h]} ${strokes[h]} ${nets[h] ?? '-'} ${pts[h]}');
      if (h == 8) total('OUT', 0, 9);
      if (h == 17) { total('IN', 9, 18); total('TOTAL', 0, 18); }
    }
    out.writeln('ags ${r.ags} diff ${dec(r.diff)}');
  }
  void stats(Player p, StringBuffer out) {
    final categories = List.filled(7, 0), parSum = List.filled(6, 0), parCount = List.filled(6, 0), complete = <int>[];
    for (final r in p.rounds) {
      if (r.scores.every((s) => s != null && s > 0)) complete.add(sum(r.scores.cast<int>()));
      for (var h = 0; h < 18; h++) {
        final s = r.scores[h], par = r.course.pars[h];
        if (s == 0) { categories[6]++; } else if (s != null) {
          final d = s - par;
          categories[d <= -2 ? 0 : d == -1 ? 1 : d == 0 ? 2 : d == 1 ? 3 : d == 2 ? 4 : 5]++;
          parSum[par] += s; parCount[par]++;
        }
      }
    }
    out.writeln('stats ${p.id}: rounds ${p.rounds.length} best ${complete.isEmpty ? '-' : complete.reduce(math.min)} average ${complete.isEmpty ? '-' : two(sum(complete), complete.length)} eagles ${categories[0]} birdies ${categories[1]} pars ${categories[2]} bogeys ${categories[3]} doubles ${categories[4]} others ${categories[5]} pickups ${categories[6]} ${[3, 4, 5].map((k) => 'par$k ${parCount[k] == 0 ? '-' : two(parSum[k], parCount[k])}').join(' ')}');
  }
  void execute(List<String> a, StringBuffer out) {
    final op = a[0], id = a.length > 1 ? a[1] : '';
    if (op == 'COURSE') {
      if (courses.containsKey(id)) fail('duplicate course');
      final pars = a.sublist(2, 20).map(number).toList(), si = a.sublist(20).map(number).toList();
      if (pars.any((p) => p < 3 || p > 5) || si.toSet().length != 18 || si.any((s) => s < 1 || s > 18)) fail('invalid course');
      courses[id] = Course(id, pars, si);
    } else if (op == 'TEE') {
      final c = course(id);
      if (c.tees.containsKey(a[2])) fail('duplicate tee');
      final r = number(a[3]), s = number(a[4]);
      if (r < 500 || r > 900 || s < 55 || s > 155) fail('invalid tee');
      c.tees[a[2]] = Tee(a[2], r, s);
    } else if (op == 'PLAYER') {
      if (players.containsKey(id)) fail('duplicate player');
      final i = a.length > 3 ? number(a[3]) : null;
      if (i != null && (i < -100 || i > 540)) fail('invalid index');
      players[id] = Player(id, a[2], i);
    } else if (op == 'ROUND') {
      final p = player(id), c = course(a[2]), t = tee(course(a[2]), a[3]), day = number(a[4]);
      if (p.rounds.isNotEmpty && day < p.rounds.last.day) fail('invalid day');
      final scores = a.sublist(5).map((s) => s == '-' ? null : s == 'X' ? 0 : number(s)).toList();
      if (scores.where((s) => s == null).length >= 5) fail('too few holes');
      final hcp = p.index == null ? null : handicap(p.index!, c, t), strokes = allocation(hcp ?? 0, c);
      final adjusted = List.generate(18, (h) {
        final limit = c.pars[h] + (p.index == null ? 5 : 2 + strokes[h]);
        return scores[h] == null ? c.pars[h] + strokes[h] : scores[h] == 0 ? limit : math.min(scores[h]!, limit);
      });
      final ags = sum(adjusted), diff = away(113 * (10 * sum(adjusted) - t.rating), t.slope);
      final exceptional = p.index != null && p.index! - diff >= 70 ? (p.index! - diff < 100 ? 10 : 20) : 0;
      p.rounds.add(Round(c, t, day, scores, hcp, adjusted, ags, diff, exceptional, p.index, p.calculation, p.records.length));
      update(p, day);
      if (p.index != null) p.records.add((day, p.index!));
      out.writeln('round $id ${p.rounds.length}: ags $ags diff ${dec(diff)}${exceptional == 0 ? '' : ' exceptional ${dec(-exceptional)}'} index ${indexText(p.index)}');
    } else if (op == 'REMOVE') {
      final p = player(id);
      if (p.rounds.isEmpty) fail('no rounds');
      final no = p.rounds.length, r = p.rounds.removeLast();
      p.index = r.oldIndex; p.calculation = r.oldCalculation; p.records.length = r.oldRecords;
      out.writeln('removed $id $no: index ${indexText(p.index)}');
    } else if (['INDEX', 'HISTORY', 'LOWINDEX', 'STATS', 'CARD'].contains(op)) {
      final p = player(id);
      if (op == 'INDEX') {
        final c = p.calculation;
        out.writeln('index $id: ${indexText(p.index)} rounds ${p.rounds.length}${c == null ? '' : ' lowest ${c.k} average ${dec(c.average)} adjustment ${dec(c.adjustment)}${c.low == null ? '' : ' low ${indexText(c.low)}'}${c.hard ? ' hard cap' : c.soft ? ' soft cap' : ''}${c.maximum ? ' maximum' : ''}'}');
      } else if (op == 'HISTORY') {
        out.writeln('history $id: rounds ${p.rounds.length}');
        for (final pick in eligible(p)) {
          final r = p.rounds[pick.number - 1];
          out.writeln('${pick.number} day ${r.day} ${r.course.id} ${r.tee.id} ags ${r.ags} diff ${dec(r.diff)}${pick.value == r.diff ? '' : ' adjusted ${dec(pick.value)}'}${pick.counting ? ' *' : ''}');
        }
      } else if (op == 'LOWINDEX') {
        final d = number(a[2]), r = lowIndex(p, number(a[2]));
        out.writeln('lowindex $id $d: ${r == null ? 'none' : '${indexText(r.$2)} day ${r.$1}'}');
      } else if (op == 'STATS') { stats(p, out);
      } else {
        final n = number(a[2]);
        if (n > p.rounds.length) fail('unknown round');
        card(p, n, p.rounds[n - 1], out);
      }
    } else if (op == 'COURSEHCP') {
      final p = player(id), c = course(a[2]), t = tee(course(a[2]), a[3]);
      if (p.index == null) fail('no index');
      final h = handicap(p.index!, c, t);
      out.writeln('coursehcp $id ${c.id} ${t.id}: ${hcpText(h)} strokes ${allocation(h, c).join(' ')}');
    } else if (op == 'HCPTABLE') {
      final c = course(id), t = tee(course(id), a[2]), first = number(a[3]), last = number(a[4]);
      if (first < -100 || first > last || last > 540) fail('invalid index');
      out.writeln('hcptable $id ${t.id}: ${indexText(first)} to ${indexText(last)}');
      var start = first, current = handicap(first, c, t);
      for (var i = first + 1; i <= last + 1; i++) {
        final h = i > last ? null : handicap(i, c, t);
        if (h != current) { out.writeln('${indexText(start)} to ${indexText(i - 1)}: ${hcpText(current)}'); start = i; if (h != null) current = h; }
      }
    } else if (op == 'HOLESTATS') {
      final c = course(id), sums = List.filled(18, 0), counts = List.filled(18, 0);
      var rounds = 0;
      for (final p in players.values) {
        for (final r in p.rounds.where((r) => r.course == c)) {
          rounds++;
          for (var h = 0; h < 18; h++) if (r.scores[h] != null && r.scores[h]! > 0) { counts[h]++; sums[h] += r.scores[h]!; }
        }
      }
      final holes = List.generate(18, (h) => h)..sort((a, b) {
        if (counts[a] == 0 || counts[b] == 0) { if (counts[a] == counts[b]) return a.compareTo(b); return counts[a] == 0 ? 1 : -1; }
        final c1 = ((sums[b] - c.pars[b] * counts[b]) * counts[a]).compareTo((sums[a] - c.pars[a] * counts[a]) * counts[b]);
        return c1 != 0 ? c1 : a.compareTo(b);
      });
      final ranks = List.filled(18, 0); for (var i = 0; i < 18; i++) ranks[holes[i]] = i + 1;
      out.writeln('holestats $id: rounds $rounds');
      for (var h = 0; h < 18; h++) out.writeln('${h + 1} par ${c.pars[h]} si ${c.si[h]} scores ${counts[h]} avg ${counts[h] == 0 ? '-' : two(sums[h], counts[h])} rank ${ranks[h]}');
    } else if (op == 'PLAYERS') {
      final ps = players.values.toList()..sort((a, b) { final c = a.index == null ? (b.index == null ? 0 : 1) : b.index == null ? -1 : a.index!.compareTo(b.index!); return c != 0 ? c : a.id.compareTo(b.id); });
      out.writeln('players ${ps.length}');
      for (final p in ps) out.writeln('${p.id} ${p.name} ${indexText(p.index)} rounds ${p.rounds.length}');
    } else if (op == 'EVENT') {
      if (events.containsKey(id)) fail('duplicate event');
      final c = course(a[3]), t = tee(course(a[3]), a[4]), allowance = number(a[6]), ids = a.sublist(7), f = a[2];
      if (allowance < 1 || allowance > 100) fail('invalid allowance');
      final ps = ids.map(player).toList(), n = ids.length;
      final valid = f == 'MATCH' || f == 'NASSAU' ? n == 2 : f == 'FOURBALL' ? n == 4 : f == 'BETTERBALL' ? [4, 6, 8].contains(n) : n >= 2 && n <= 8;
      if (ids.toSet().length != n || !valid) fail('invalid players');
      events[id] = Event(id, f, c, t, number(a[5]), allowance, ps);
    } else if (op == 'RESULTS') {
      final e = events[id] ?? fail('unknown event'); results(evaluate(e), out);
    } else if (op == 'MERIT') {
      final values = <String, List<int>>{};
      var counted = 0;
      for (final e in events.values) {
        if (!['STROKE', 'STABLEFORD', 'PAR'].contains(e.format)) continue;
        Result r;
        try { r = evaluate(e); } on GolfError { continue; }
        counted++;
        for (final p in e.players) values.putIfAbsent(p.id, () => [0, 0, 0])[2]++;
        final ranked = rank(r);
        for (var i = 0; i < ranked.length; i++) {
          final v = values[e.players[ranked[i]].id]!;
          v[0] += [10, 8, 6, 5, 4, 3, 2, 1][i]; if (i == 0) v[1]++;
        }
      }
      final ids = values.keys.toList()..sort((a, b) { var c = values[b]![0].compareTo(values[a]![0]); if (c == 0) c = values[b]![1].compareTo(values[a]![1]); return c != 0 ? c : a.compareTo(b); });
      out.writeln('merit: events $counted');
      for (var i = 0; i < ids.length; i++) { final id = ids[i], v = values[ids[i]]!; out.writeln('${i + 1} $id ${v[0]} wins ${v[1]} played ${v[2]}'); }
    }
  }
}
void main() {
  final golf = Golf(), output = StringBuffer(), n = number(stdin.readLineSync()!);
  for (var i = 0; i < n; i++) {
    final a = stdin.readLineSync()!.split(' '), draft = StringBuffer();
    try { golf.execute(a, draft); output.write(draft); } on GolfError catch (e) { output.writeln('ERROR ${e.reason}'); }
  }
  stdout.write(output);
}
