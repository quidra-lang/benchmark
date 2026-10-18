import 'dart:io';
import 'dart:math' as math;

const types = ['MOTORCYCLE', 'CAR', 'ECAR', 'VAN', 'BUS'];
const kinds = ['MOTO', 'COMPACT', 'LARGE', 'EV'];
const preferences = [[0, 1, 2], [1, 2], [3, 1, 2], [2], [2]];
int num(String s) => int.parse(s);
int date(int t) => t ~/ 1440 + 1;
String duration(int t) => '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
String time(int t) => '${date(t)}-${duration(t % 1440).padLeft(5, '0')}';
String decimal(int q) => '${q ~/ 10}.${q % 10}';
class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}
Never fail(String s) => throw CommandError(s);
class Spot {
  final int level, number, kind, order;
  bool closed = false;
  Vehicle? occupant;
  Spot(this.level, this.number, this.kind, this.order);
  bool get free => !closed && occupant == null;
  String get label => 'L$level-$number';
}
class Vehicle {
  final String plate;
  final int type, entry;
  List<Spot> spots;
  int kwh = 0, charge = 0, validation = 0;
  List<int>? payment;
  Vehicle(this.plate, this.type, this.entry, this.spots);
  String get location => type == 4 ? '${spots.first.label}..${spots.last.number}' : spots.first.label;
}
class Waiting {
  final String plate;
  final int type, joined;
  Waiting(this.plate, this.type, this.joined);
}
class ExitRecord {
  final String plate, location;
  final int type, entry, exit;
  final List<int> fees;
  final bool lost;
  ExitRecord(Vehicle v, this.exit, this.fees, this.lost)
      : plate = v.plate, location = v.location, type = v.type, entry = v.entry;
}
class Daily {
  final entries = List.filled(5, 0), exits = List.filled(5, 0), refused = List.filled(5, 0), revenue = List.filled(5, 0);
}
class Garage {
  int now = 0, peak = 0;
  int? peakTime;
  final levels = <List<Spot>>[], spots = <Spot>[];
  final vehicles = <String, Vehicle>{}, passes = <String, int>{};
  final queue = <Waiting>[], records = <ExitRecord>[];
  final rates = [100, 200, 200, 300, 600], caps = [800, 1600, 1600, 2400, 4800];
  final fees = <String, int>{'NIGHT': 300, 'LOST': 2000, 'KWH': 30};
  final daily = <int, Daily>{};
  final entries = List.filled(5, 0), exits = List.filled(5, 0), refused = List.filled(5, 0), stays = List.filled(5, 0);
  Daily day(int d) => daily.putIfAbsent(d, () => Daily());
  bool pass(String p) => (passes[p] ?? 0) >= date(now);
  Vehicle parked(String p) => vehicles[p] ?? fail('$p is not parked');
  Spot findSpot(String s) {
    final p = s.substring(1).split('-');
    final l = num(p[0]), n = num(p[1]);
    if (l > levels.length || n > levels[l - 1].length) fail('unknown spot $s');
    return levels[l - 1][n - 1];
  }
  List<Spot>? assign(int type) {
    if (type == 4) {
      for (final level in levels) {
        for (var i = 0; i + 2 < level.length; i++) {
          final triple = level.sublist(i, i + 3);
          if (triple.every((s) => s.kind == 2 && s.free)) return triple;
        }
      }
    } else {
      for (final kind in preferences[type]) {
        for (final s in spots) {
          if (s.kind == kind && s.free) return [s];
        }
      }
    }
    return null;
  }
  Vehicle park(String p, int type, List<Spot> place) {
    final v = Vehicle(p, type, now, place);
    vehicles[p] = v;
    for (final s in place) s.occupant = v;
    entries[type]++;
    day(date(now)).entries[type]++;
    if (vehicles.length > peak) { peak = vehicles.length; peakTime = now; }
    return v;
  }
  void refuse(int type, int t) { refused[type]++; day(date(t)).refused[type]++; }
  void giveup(StringBuffer out) {
    for (final w in queue.toList()) {
      if (now - w.joined >= 30) {
        queue.remove(w);
        refuse(w.type, w.joined + 30);
        out.writeln('GIVEUP ${w.plate} ${types[w.type]} ${time(w.joined + 30)}');
      }
    }
  }
  void admit(StringBuffer out) {
    for (final w in queue.toList()) {
      final place = assign(w.type);
      if (place != null) {
        queue.remove(w);
        final v = park(w.plate, w.type, place);
        out.writeln('ADMIT ${w.plate} ${types[w.type]} ${v.location} waited ${duration(now - w.joined)}');
      }
    }
  }
  List<int> interval(Vehicle v, int a, int free) {
    final total = now - a;
    if (pass(v.plate) || total <= free) return [0, 0];
    var parking = 0;
    for (var offset = 0; offset < total; offset += 1440) {
      final bill = math.min(total - offset, 1440) - (offset == 0 ? free : 0);
      parking += math.min(((bill + 29) ~/ 30) * rates[v.type], caps[v.type]);
    }
    return [parking, (date(now) - date(a)) * fees['NIGHT']!];
  }
  List<int> charges(Vehicle v, bool lost) {
    final payment = v.payment;
    final f = interval(v, payment == null ? v.entry : payment[0], payment == null ? 15 + v.validation : 15);
    final parking = f[0] + (payment == null ? 0 : payment[1]);
    final night = f[1] + (payment == null ? 0 : payment[2]);
    final loss = lost ? fees['LOST']! : 0;
    final total = parking + night + loss + v.charge;
    return [parking, night, loss, v.charge, total, payment == null ? total : f[0] + f[1]];
  }
  String annotation(Vehicle v) => '${pass(v.plate) ? ' PASS' : ''}${v.validation == 0 ? '' : ' VAL ${v.validation}'}${v.kwh == 0 ? '' : ' KWH ${v.kwh}'}${v.payment == null ? '' : ' PAID'}';
  List<Vehicle> ordered() => vehicles.values.toList()..sort((a, b) => a.spots.first.order.compareTo(b.spots.first.order));
  void feeLine(StringBuffer out, String label, Vehicle v, List<int> f) => out.writeln('$label ${v.plate} ${v.location} stay ${duration(now - v.entry)} parking ${f[0]} night ${f[1]} lost ${f[2]} charge ${f[3]} total ${f[4]} due ${f[5]}');
  void move(Vehicle v, List<Spot> place, StringBuffer out) {
    final old = v.location;
    for (final s in v.spots) s.occupant = null;
    v.spots = place;
    for (final s in place) s.occupant = v;
    out.writeln('MOVE ${v.plate} $old -> ${v.location}');
  }
  void execute(List<String> a, StringBuffer out) {
    final op = a[2], args = a.sublist(3);
    final p = args.isEmpty ? '' : args[0];
    if (op == 'LEVEL') {
      final counts = args.map(num).toList(), level = <Spot>[];
      final l = levels.length + 1;
      for (var k = 0; k < 4; k++) {
        for (var j = 0; j < counts[k]; j++) {
          final s = Spot(l, level.length + 1, k, spots.length);
          level.add(s); spots.add(s);
        }
      }
      levels.add(level);
      out.writeln('LEVEL $l spots ${level.length} MOTO ${counts[0]} COMPACT ${counts[1]} LARGE ${counts[2]} EV ${counts[3]}');
      admit(out);
    } else if (op == 'CLOSE' || op == 'OPEN') {
      final s = findSpot(p);
      if (op == 'CLOSE') {
        if (s.closed) fail('spot $p is already closed');
        if (s.occupant != null) fail('spot $p is occupied by ${s.occupant!.plate}');
        s.closed = true;
      } else {
        if (!s.closed) fail('spot $p is not closed');
        s.closed = false;
      }
      out.writeln('$op $p ${kinds[s.kind]}');
      if (op == 'OPEN') admit(out);
    } else if (op == 'RATE') {
      final k = types.indexOf(p);
      if (k < 0) fail('unknown type $p');
      final r = num(args[1]), c = num(args[2]);
      if (c < r) fail('cap below rate for $p');
      rates[k] = r; caps[k] = c;
      out.writeln('RATE $p $r $c');
    } else if (op == 'FEE') {
      if (!fees.containsKey(p)) fail('unknown fee $p');
      fees[p] = num(args[1]);
      out.writeln('FEE $p ${fees[p]}');
    } else if (op == 'ENTER') {
      final k = types.indexOf(args[1]);
      if (k < 0) fail('unknown type ${args[1]}');
      if (vehicles.containsKey(p)) fail('$p is already parked at ${vehicles[p]!.location}');
      if (queue.any((w) => w.plate == p)) fail('$p is already waiting');
      final place = assign(k);
      if (place != null) {
        final v = park(p, k, place);
        out.writeln('ENTER $p ${types[k]} ${v.location}');
      } else if (queue.length < 3) {
        queue.add(Waiting(p, k, now));
        out.writeln('WAIT $p ${types[k]} ${queue.length}');
      } else { refuse(k, now); out.writeln('FULL $p ${types[k]}'); }
    } else if (op == 'LEAVE') {
      final i = queue.indexWhere((w) => w.plate == p);
      if (i < 0) fail('$p is not waiting');
      final w = queue.removeAt(i);
      out.writeln('LEAVE $p ${types[w.type]}');
    } else if (['EXIT', 'PAY', 'QUOTE', 'CHARGE', 'VALIDATE'].contains(op)) {
      final v = parked(p);
      if (op == 'EXIT') {
        final lost = args.length > 1;
        if (lost && v.payment != null) fail('$p has already paid');
        final f = charges(v, lost);
        feeLine(out, op, v, f);
        records.add(ExitRecord(v, now, f, lost));
        exits[v.type]++; stays[v.type] += now - v.entry;
        day(date(now)).exits[v.type]++; day(date(now)).revenue[v.type] += f[4];
        for (final s in v.spots) s.occupant = null;
        vehicles.remove(p); admit(out);
      } else if (op == 'QUOTE') { feeLine(out, op, v, charges(v, false));
      } else if (op == 'PAY') {
        if (v.payment != null) fail('$p has already paid');
        final f = charges(v, false);
        v.payment = [now, f[0], f[1]];
        out.writeln('PAY $p parking ${f[0]} night ${f[1]} charge ${f[3]} total ${f[4]}');
      } else if (op == 'CHARGE') {
        if (v.type != 2) fail('$p is not an electric car');
        if (v.spots.first.kind != 3) fail('$p is not at a charger');
        if (v.payment != null) fail('$p has already paid');
        final kwh = num(args[1]);
        if (v.kwh + kwh > 100) fail('charge limit exceeded for $p');
        final cost = kwh * fees['KWH']!;
        v.kwh += kwh; v.charge += cost;
        out.writeln('CHARGE $p kwh $kwh cost $cost stay_kwh ${v.kwh} stay_cost ${v.charge}');
      } else {
        if (v.payment != null) fail('$p has already paid');
        final n = num(args[1]);
        if (v.validation + n > 180) fail('validation limit exceeded for $p');
        v.validation += n;
        out.writeln('VALIDATE $p $n total ${v.validation}');
      }
    } else if (op == 'PASS') {
      passes[p] = (pass(p) ? passes[p]! : date(now) - 1) + num(args[1]);
      out.writeln('PASS $p until ${passes[p]}');
    } else if (op == 'UNPASS') {
      if (!pass(p)) fail('$p has no pass');
      passes.remove(p); out.writeln('UNPASS $p');
    } else if (op == 'MOVE') {
      final v = parked(p);
      if (v.type == 4) fail('bus $p cannot be moved');
      final dest = args[1], s = findSpot(args[1]);
      if (s == v.spots.first) fail('$p is already at $dest');
      if (s.closed) fail('spot $dest is closed');
      if (s.occupant != null) fail('spot $dest is occupied by ${s.occupant!.plate}');
      if (!preferences[v.type].contains(s.kind)) fail('${types[v.type]} cannot use ${kinds[s.kind]} spot $dest');
      move(v, [s], out); admit(out);
    } else if (op == 'REBALANCE') {
      var moved = 0;
      for (final v in ordered().where((v) => v.type != 4)) {
        final pref = preferences[v.type], place = assign(v.type);
        if (place != null && pref.indexOf(place.first.kind) < pref.indexOf(v.spots.first.kind)) {
          move(v, place, out); moved++;
        }
      }
      out.writeln('REBALANCE $moved'); admit(out);
    } else if (op == 'WHERE') {
      final v = vehicles[p], i = queue.indexWhere((w) => w.plate == p);
      final history = records.where((r) => r.plate == p).toList();
      if (v != null) { out.writeln('WHERE $p ${v.location} ${types[v.type]} ${time(v.entry)} stay ${duration(now - v.entry)}${annotation(v)}');
      } else if (i >= 0) { out.writeln('WHERE $p waiting ${i + 1}');
      } else if (history.isNotEmpty) { out.writeln('WHERE $p gone ${time(history.last.exit)}');
      } else { fail('unknown plate $p'); }
    } else if (op == 'LIST') {
      final l = args.isEmpty ? null : num(p);
      if (l != null && l > levels.length) fail('unknown level $l');
      final list = ordered().where((v) => l == null || v.spots.first.level == l).toList();
      out.writeln('LIST ${list.length}');
      for (final v in list) out.writeln('${v.location} ${v.plate} ${types[v.type]} ${time(v.entry)}${annotation(v)}');
    } else if (op == 'MAP') {
      out.writeln('MAP ${levels.length}');
      for (var i = 0; i < levels.length; i++) {
        final symbols = <String>[];
        for (var j = 0; j < levels[i].length; j++) {
          if (j > 0 && j % 10 == 0) symbols.add(' ');
          final s = levels[i][j];
          symbols.add(s.closed ? '#' : s.occupant != null ? 'MCLE'[s.kind] : 'mcle'[s.kind]);
        }
        out.writeln('L${i + 1} ${symbols.join()}');
      }
    } else if (op == 'OCCUPANCY') {
      final allUsed = List.filled(4, 0), allAvail = List.filled(4, 0);
      var allClosed = 0;
      out.writeln('OCCUPANCY vehicles ${vehicles.length} waiting ${queue.length}');
      for (var i = 0; i < levels.length; i++) {
        final used = List.filled(4, 0), avail = List.filled(4, 0);
        var closed = 0;
        for (final s in levels[i]) {
          if (s.closed) { closed++; } else { avail[s.kind]++; }
          if (s.occupant != null) used[s.kind]++;
        }
        out.writeln('L${i + 1} ${List.generate(4, (k) => '${kinds[k]} ${used[k]}/${avail[k]}').join(' ')} closed $closed');
        for (var k = 0; k < 4; k++) { allUsed[k] += used[k]; allAvail[k] += avail[k]; }
        allClosed += closed;
      }
      final av = allAvail.fold(0, (a, b) => a + b), us = allUsed.fold(0, (a, b) => a + b);
      out.writeln('TOTAL ${List.generate(4, (k) => '${kinds[k]} ${allUsed[k]}/${allAvail[k]}').join(' ')} closed $allClosed rate ${decimal(av == 0 ? 0 : us * 1000 ~/ av)}%');
    } else if (op == 'SIGN') {
      final counts = List.filled(5, 0);
      for (var k = 0; k < 4; k++) counts[k] = spots.where((s) => s.free && preferences[k].contains(s.kind)).length;
      for (final level in levels) {
        var run = 0;
        for (final s in level) {
          if (s.free && s.kind == 2) { run++; } else { counts[4] += run ~/ 3; run = 0; }
        }
        counts[4] += run ~/ 3;
      }
      out.writeln('SIGN ${List.generate(5, (k) => '${types[k]} ${counts[k] == 0 ? 'FULL' : counts[k]}').join(' ')}');
    } else if (op == 'RATES') {
      out.writeln('RATES');
      for (var k = 0; k < 5; k++) out.writeln('${types[k]} ${rates[k]} ${caps[k]}');
      out.writeln('NIGHT ${fees['NIGHT']} LOST ${fees['LOST']} KWH ${fees['KWH']}');
    } else if (op == 'PASSES') {
      final ps = passes.keys.where(pass).toList()..sort();
      out.writeln('PASSES ${ps.length}');
      for (final plate in ps) out.writeln('$plate until ${passes[plate]}${vehicles.containsKey(plate) ? ' IN' : ''}');
    } else if (op == 'OVERSTAY') {
      final hours = num(p), vs = ordered().where((v) => now - v.entry >= num(p) * 60).toList();
      vs.sort((a, b) { final c = a.entry.compareTo(b.entry); return c != 0 ? c : a.spots.first.order.compareTo(b.spots.first.order); });
      out.writeln('OVERSTAY $hours ${vs.length}');
      for (final v in vs) out.writeln('${v.location} ${v.plate} ${types[v.type]} ${time(v.entry)} stay ${duration(now - v.entry)}');
    } else if (op == 'HISTORY') {
      final rs = records.where((r) => r.plate == p).toList();
      if (rs.isEmpty) fail('no history for $p');
      out.writeln('HISTORY $p visits ${rs.length} paid ${rs.fold(0, (s, r) => s + r.fees[4])}');
      for (final r in rs) out.writeln('${time(r.entry)} ${time(r.exit)} ${r.location} ${types[r.type]} ${r.fees[4]}${r.lost ? ' LOST' : ''}');
    } else if (op == 'REVENUE') {
      final totals = List.generate(6, (_) => List.filled(6, 0));
      for (final r in records) {
        for (final k in [r.type, 5]) {
          totals[k][0]++;
          for (var j = 0; j < 5; j++) totals[k][j + 1] += r.fees[j];
        }
      }
      out.writeln('REVENUE');
      for (var k = 0; k < 6; k++) { final f = totals[k]; out.writeln('${k == 5 ? 'TOTAL' : types[k]} exits ${f[0]} parking ${f[1]} night ${f[2]} lost ${f[3]} charge ${f[4]} total ${f[5]}'); }
    } else if (op == 'DAILY') {
      final d = num(p), s = daily[num(p)] ?? Daily();
      for (final k in [-1, 0, 1, 2, 3, 4]) {
        int value(List<int> xs) => k < 0 ? xs.fold(0, (a, b) => a + b) : xs[k];
        out.writeln('${k < 0 ? 'DAILY $d' : types[k]} entries ${value(s.entries)} exits ${value(s.exits)} refused ${value(s.refused)} revenue ${value(s.revenue)}');
      }
    } else if (op == 'STATS') {
      out.writeln('STATS parked ${vehicles.length} peak $peak at ${peakTime == null ? '-' : time(peakTime!)}');
      for (var k = 0; k < 6; k++) {
        int value(List<int> xs) => k == 5 ? xs.fold(0, (a, b) => a + b) : xs[k];
        final e = value(exits), stay = value(stays);
        out.writeln('${k == 5 ? 'ALL' : types[k]} entries ${value(entries)} exits $e refused ${value(refused)} avg_stay ${decimal(e == 0 ? 0 : stay * 10 ~/ e)}');
      }
    }
  }
}
void main() {
  final garage = Garage(), output = StringBuffer();
  final n = num(stdin.readLineSync()!);
  for (var i = 0; i < n; i++) {
    final a = stdin.readLineSync()!.split(' ');
    final hhmm = a[1].split(':');
    garage.now = (num(a[0]) - 1) * 1440 + num(hhmm[0]) * 60 + num(hhmm[1]);
    garage.giveup(output);
    final draft = StringBuffer();
    try { garage.execute(a, draft); output.write(draft); }
    on CommandError catch (e) { output.writeln('ERROR ${e.message}'); }
  }
  stdout.write(output);
}
