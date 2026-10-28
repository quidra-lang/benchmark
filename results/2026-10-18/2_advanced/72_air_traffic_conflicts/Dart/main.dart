import 'dart:io';
import 'dart:math';

part 'flight_plans.dart';
part 'trajectory.dart';
part 'conflict.dart';
part 'resolution.dart';
part 'report.dart';

class Classification {
  final double levelA, levelB, trackA, trackB, angle;
  final String geometry, severity;
  final int sector;
  Classification(
    this.levelA,
    this.levelB,
    this.trackA,
    this.trackB,
    this.angle,
    this.geometry,
    this.severity,
    this.sector,
  );
}

class Transit {
  final int flight, sector;
  int previous = -1, next = -1;
  final double entry;
  double exit;
  Transit(this.flight, this.sector, this.entry, this.exit);
}

class Alert {
  final int a, b, first;
  int last, samples = 1;
  final double predicted;
  double minimum, lead = 0;
  bool isTrue = false;
  Alert(this.a, this.b, this.first, this.last, this.predicted, this.minimum);
}

class LevelUsage {
  final Set<int> flights = {};
  double time = 0;
}

(int, int) pair(int a, int b) => a < b ? (a, b) : (b, a);
String pairName(int a, int b, List<FlightPlan> plans) =>
    '${plans[a].callsign}-${plans[b].callsign}';
double track(Segment s) {
  var theta = atan2(s.velocity.x, s.velocity.y) * 180 / 3.141592653589793;
  if (theta < 0) theta += 360;
  return theta;
}

bool contains(Sector s, Vec p) =>
    s.x1 / 10 <= p.x &&
    p.x < s.x2 / 10 &&
    s.y1 / 10 <= p.y &&
    p.y < s.y2 / 10 &&
    s.lower * 100 <= p.z &&
    p.z < s.upper * 100;
Classification classify(
  Conflict c,
  List<Trajectory> trajectories,
  Input input,
) {
  final a = trajectories[c.a].segments[c.closest.a],
      b = trajectories[c.b].segments[c.closest.b];
  final pa = a.at(c.closest.loss.time),
      pb = b.at(c.closest.loss.time),
      trackA = track(a),
      trackB = track(b);
  final g = (trackA - trackB).abs(),
      dot = a.velocity.x * b.velocity.x + a.velocity.y * b.velocity.y,
      cross = a.velocity.x * b.velocity.y - a.velocity.y * b.velocity.x;
  final angle = g > 180 ? 360 - g : g,
      geometry = dot * dot > cross * cross
          ? (dot < 0 ? 'head_on' : 'trailing')
          : 'crossing',
      d = c.closest.loss.distance;
  final severity = 10 * d < 4 * input.settings.dh
          ? 'HIGH'
          : 10 * d < 7 * input.settings.dh
          ? 'MEDIUM'
          : 'LOW',
      midpoint = Vec((pa.x + pb.x) / 2, (pa.y + pb.y) / 2, (pa.z + pb.z) / 2);
  var sector = -1;
  for (var i = 0; i < input.sectors.length; i++) {
    if (contains(input.sectors[i], midpoint)) {
      sector = i;
      break;
    }
  }
  return Classification(
    pa.z / 100,
    pb.z / 100,
    trackA,
    trackB,
    angle,
    geometry,
    severity,
    sector,
  );
}

bool active(Conflict c, double time) => c.start <= time && time < c.end;
String sectorName(int index, Input input) =>
    index < 0 ? '-' : input.sectors[index].name;
(double, double)? segmentInside(Segment segment, Sector sector) {
  var lo = segment.start, hi = segment.end;
  final positions = [
        segment.position.x,
        segment.position.y,
        segment.position.z,
      ],
      velocities = [segment.velocity.x, segment.velocity.y, segment.velocity.z],
      lower = [sector.x1 / 10, sector.y1 / 10, (sector.lower * 100).toDouble()],
      upper = [sector.x2 / 10, sector.y2 / 10, (sector.upper * 100).toDouble()];
  for (var axis = 0; axis < 3; axis++) {
    final p = positions[axis],
        v = velocities[axis],
        a = lower[axis],
        b = upper[axis];
    if (v == 0) {
      if (!(a <= p && p < b)) return null;
    } else {
      final r1 = (a - p) / v, r2 = (b - p) / v;
      lo = max(lo, segment.start + min(r1, r2));
      hi = min(hi, segment.start + max(r1, r2));
    }
  }
  return hi - lo > 1e-6 ? (lo, hi) : null;
}

List<Transit> transits(List<Trajectory> trajectories, Input input) {
  final result = <Transit>[];
  for (var flight = 0; flight < trajectories.length; flight++) {
    final times = <Transit>[];
    for (var sector = 0; sector < input.sectors.length; sector++) {
      final joined = <Transit>[];
      for (final segment in trajectories[flight].segments) {
        final inside = segmentInside(segment, input.sectors[sector]);
        if (inside == null) continue;
        final (lo, hi) = inside;
        if (joined.isNotEmpty && lo - joined.last.exit <= 1e-6) {
          joined.last.exit = hi;
        } else {
          joined.add(Transit(flight, sector, lo, hi));
        }
      }
      times.addAll(joined);
    }
    times.sort((a, b) {
      final c = a.entry.compareTo(b.entry);
      return c != 0 ? c : a.sector.compareTo(b.sector);
    });
    for (var i = 1; i < times.length; i++) {
      if ((times[i].entry - times[i - 1].exit).abs() <= 1e-6) {
        times[i - 1].next = times[i].sector;
        times[i].previous = times[i - 1].sector;
      }
    }
    result.addAll(times);
  }
  return result;
}

List<int> sampleTimes(Settings settings) => [
  for (var t = settings.ta; t < settings.tb; t += 60) t,
];
List<List<int>> occupancy(
  List<Trajectory> trajectories,
  Input input,
  List<int> times,
) {
  final a = List.generate(
    input.sectors.length,
    (_) => List.filled(times.length, 0),
  );
  for (var j = 0; j < times.length; j++) {
    for (final trajectory in trajectories) {
      final at = trajectory.at(times[j].toDouble());
      if (at == null) continue;
      final (p, _) = at;
      for (var sector = 0; sector < input.sectors.length; sector++) {
        if (contains(input.sectors[sector], p)) a[sector][j]++;
      }
    }
  }
  return a;
}

void reportConflicts(
  StringBuffer out,
  String name,
  List<Conflict> list,
  List<Classification> classes,
  List<Trajectory> trajectories,
  Input input,
  Set<(int, int)> resolved,
  Set<(int, int)> finalPairs,
) {
  out.writeln('CONFLICTS plan=$name count=${list.length}');
  final counts = <String, int>{};
  var total = 0.0, minimum = double.maxFinite;
  for (var i = 0; i < list.length; i++) {
    final c = list[i], cl = classes[i];
    final outcome = finalPairs.contains(pair(c.a, c.b))
            ? 'remaining'
            : resolved.contains(pair(c.a, c.b))
            ? 'resolved'
            : 'indirect',
        piece = c.closest;
    final a = trajectories[c.a].segments[piece.a],
        b = trajectories[c.b].segments[piece.b];
    out.writeln(
      'CONFLICT ${i + 1} ${pairName(c.a, c.b, input.plans)} start=${f(c.start)} end=${f(c.end)} duration=${f(c.end - c.start)} outcome=$outcome',
    );
    out.writeln(
      '  CPA t=${f(piece.loss.time)} dist=${f(piece.loss.distance)} vert=${format(piece.loss.vertical, 1)} levels=${format(cl.levelA, 2)}/${format(cl.levelB, 2)} tracks=${format(cl.trackA, 1)}/${format(cl.trackB, 1)} angle=${format(cl.angle, 1)}',
    );
    out.writeln(
      '  TYPE geometry=${cl.geometry} phases=${a.phase}/${b.phase} segments=${a.number}/${b.number} sector=${sectorName(cl.sector, input)} severity=${cl.severity}',
    );
    for (final p in c.pieces) {
      out.writeln(
        '  PIECE ${p.a + 1}/${p.b + 1} ${f(p.loss.lo)} ${f(p.loss.hi)}',
      );
    }
    total += c.end - c.start;
    minimum = min(minimum, piece.loss.distance);
    counts[cl.geometry] = (counts[cl.geometry] ?? 0) + 1;
    counts[cl.severity] = (counts[cl.severity] ?? 0) + 1;
  }
  out.writeln(
    'SUMMARY count=${list.length} total=${f(total)} min_dist=${list.isEmpty ? '-' : f(minimum)} head_on=${counts['head_on'] ?? 0} crossing=${counts['crossing'] ?? 0} trailing=${counts['trailing'] ?? 0} high=${counts['HIGH'] ?? 0} medium=${counts['MEDIUM'] ?? 0} low=${counts['LOW'] ?? 0}',
  );
  final involved = <int>{};
  for (var flight = 0; flight < input.plans.length; flight++) {
    var number = 0, first = 0.0;
    final partners = <int>{};
    for (final c in list) {
      if (c.a == flight || c.b == flight) {
        if (number == 0) first = c.start;
        number++;
        partners.add(c.a == flight ? c.b : c.a);
      }
    }
    if (number == 0) continue;
    involved.add(flight);
    final names = [
      for (var i = 0; i < input.plans.length; i++)
        if (partners.contains(i)) input.plans[i].callsign,
    ];
    out.writeln(
      'FLIGHT ${input.plans[flight].callsign} conflicts=$number first=${f(first)} partners=${names.join(',')}',
    );
  }
  out.writeln(
    'TIMELINE from=${input.settings.ta} to=${input.settings.tb} step=60',
  );
  for (var flight = 0; flight < input.plans.length; flight++) {
    if (!involved.contains(flight)) continue;
    final timeline = StringBuffer();
    for (final time in sampleTimes(input.settings)) {
      final at = trajectories[flight].at(time.toDouble());
      var mark = '.';
      if (at != null) {
        mark = '-';
        for (final c in list) {
          if ((c.a == flight || c.b == flight) && active(c, time.toDouble())) {
            mark = 'X';
            break;
          }
        }
      }
      timeline.write(mark);
    }
    out.writeln('${input.plans[flight].callsign} $timeline');
  }
}

Map<int, LevelUsage> levelUsage(List<Trajectory> trajectories) {
  final result = <int, LevelUsage>{};
  for (var flight = 0; flight < trajectories.length; flight++) {
    for (final s in trajectories[flight].segments) {
      if (s.phase != 'LVL') continue;
      final level = (s.position.z / 100).toInt(),
          usage = result[level] ??= LevelUsage();
      usage.flights.add(flight);
      usage.time += s.end - s.start;
    }
  }
  return result;
}

void reportSectors(
  StringBuffer loadOut,
  StringBuffer report,
  List<List<Trajectory>> trajectories,
  List<List<Transit>> lists,
  List<List<Classification>> classes,
  Input input,
  List<int> times,
) {
  final occ = [
    occupancy(trajectories[0], input, times),
    occupancy(trajectories[1], input, times),
  ];
  loadOut.writeln(
    'sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status',
  );
  for (var si = 0; si < input.sectors.length; si++) {
    final sector = input.sectors[si], over = [0, 0];
    for (var period = 0; period < times.length ~/ 5; period++) {
      final start = input.settings.ta + 300 * period,
          end = input.settings.ta + 300 * (period + 1),
          entries = [0, 0],
          peak = [0, 0],
          sum = [0, 0];
      for (var plan = 0; plan < 2; plan++) {
        for (final transit in lists[plan]) {
          if (transit.sector == si &&
              start <= transit.entry &&
              transit.entry < end)
            entries[plan]++;
        }
        for (var j = 5 * period; j < 5 * (period + 1); j++) {
          final count = occ[plan][si][j];
          sum[plan] += count;
          peak[plan] = max(peak[plan], count);
        }
        if (peak[plan] > sector.capacity) over[plan]++;
      }
      final status = peak[1] > sector.capacity
          ? 'OVER'
          : peak[0] > sector.capacity
          ? 'RELIEVED'
          : 'OK';
      loadOut.writeln(
        '${sector.name},${period + 1},$start,$end,${entries[0]},${entries[1]},${peak[0]},${peak[1]},${format(sum[1] / 5, 1)},${sector.capacity},$status',
      );
    }
    report.writeln(
      'SECTOR ${sector.name} x=${sector.x1}..${sector.x2} y=${sector.y1}..${sector.y2} fl=${sector.lower}..${sector.upper} capacity=${sector.capacity}',
    );
    var maxFinal = 0;
    for (var plan = 0; plan < 2; plan++) {
      var entries = 0, dwell = 0.0;
      for (final transit in lists[plan]) {
        if (transit.sector == si) {
          entries++;
          dwell += transit.exit - transit.entry;
        }
      }
      var peak = 0;
      for (final v in occ[plan][si]) {
        peak = max(peak, v);
      }
      if (plan == 1) maxFinal = peak;
      final conflictCount = classes[plan].where((c) => c.sector == si).length;
      report.writeln(
        '${plan == 0 ? 'INITIAL' : 'FINAL'} entries=$entries time=${f(dwell)} mean=${entries == 0 ? '-' : f(dwell / entries)} peak=$peak over=${over[plan]} conflicts=$conflictCount',
      );
    }
    final top = max(sector.capacity + 1, maxFinal);
    final grid = [
      for (var row = 0; row < top; row++)
        [
          for (final count in occ[1][si])
            count >= top - row
                ? '#'
                : top - row == sector.capacity
                ? '-'
                : '.',
        ],
    ];
    chart(report, grid);
  }
  report.writeln('LEVELS');
  final usage = [levelUsage(trajectories[0]), levelUsage(trajectories[1])],
      levelsSet = <int>{};
  for (final u in usage) {
    levelsSet.addAll(u.keys);
  }
  final levels = levelsSet.toList()..sort((a, b) => b.compareTo(a));
  for (final level in levels) {
    final count = [0, 0], duration = [0.0, 0.0];
    for (var plan = 0; plan < 2; plan++) {
      final value = usage[plan][level];
      if (value != null) {
        count[plan] = value.flights.length;
        duration[plan] = value.time;
      }
    }
    report.writeln(
      'LEVEL $level flights=${count[0]}->${count[1]} time=${f(duration[0])}->${f(duration[1])}',
    );
  }
  final handoffs = <(int, int), int>{};
  var total = 0;
  for (final transit in lists[1]) {
    if (transit.next >= 0) {
      final pair = (transit.sector, transit.next);
      handoffs[pair] = (handoffs[pair] ?? 0) + 1;
      total++;
    }
  }
  report.writeln('HANDOFFS plan=final count=$total');
  for (var a = 0; a < input.sectors.length; a++) {
    for (var b = 0; b < input.sectors.length; b++) {
      final count = handoffs[(a, b)] ?? 0;
      if (count > 0)
        report.writeln(
          'HANDOFF ${input.sectors[a].name} ${input.sectors[b].name} $count',
        );
    }
  }
}

(List<Alert>, Set<int>) alertReplay(
  List<Trajectory> trajectories,
  List<Conflict> list,
  Input input,
  List<int> times,
) {
  final alerts = <Alert>[];
  for (var a = 0; a < trajectories.length; a++) {
    for (var b = a + 1; b < trajectories.length; b++) {
      final grouped = <Alert>[];
      for (final time in times) {
        final aa = trajectories[a].at(time.toDouble()),
            bb = trajectories[b].at(time.toDouble());
        if (aa == null || bb == null) continue;
        final (pa, sa) = aa;
        final (pb, sb) = bb;
        final loss = lossInterval(
          pa.subtract(pb),
          sa.velocity.subtract(sb.velocity),
          0,
          input.settings.alert.toDouble(),
          input.settings,
        );
        if (loss == null) continue;
        if (grouped.isNotEmpty && time - grouped.last.last == 60) {
          final last = grouped.last;
          last.last = time;
          last.samples++;
          last.minimum = min(last.minimum, loss.distance);
        } else {
          grouped.add(Alert(a, b, time, time, time + loss.lo, loss.distance));
        }
      }
      alerts.addAll(grouped);
    }
  }
  alerts.sort((a, b) {
    var c = a.first.compareTo(b.first);
    if (c != 0) return c;
    c = a.a.compareTo(b.a);
    return c != 0 ? c : a.b.compareTo(b.b);
  });
  final detected = <int>{};
  for (final alert in alerts) {
    for (var ci = 0; ci < list.length; ci++) {
      final c = list[ci];
      if (c.a == alert.a &&
          c.b == alert.b &&
          c.start < alert.last + input.settings.alert &&
          c.end > alert.first) {
        if (!alert.isTrue) {
          alert.isTrue = true;
          alert.lead = c.start - alert.first;
        }
        detected.add(ci);
      }
    }
  }
  return (alerts, detected);
}

void reportAlerts(
  StringBuffer out,
  String name,
  List<Trajectory> trajectories,
  List<Conflict> list,
  Input input,
  List<int> times,
) {
  final (alerts, detected) = alertReplay(trajectories, list, input, times);
  out.writeln(
    'ALERTS plan=$name horizon=${input.settings.alert} count=${alerts.length}',
  );
  var trueCount = 0, lead = 0.0;
  for (var i = 0; i < alerts.length; i++) {
    final a = alerts[i];
    var status = 'status=false lead=-';
    if (a.isTrue) {
      trueCount++;
      lead += a.lead;
      status = 'status=true lead=${f(a.lead)}';
    }
    out.writeln(
      'ALERT ${i + 1} ${pairName(a.a, a.b, input.plans)} first=${a.first} last=${a.last} samples=${a.samples} predicted=${f(a.predicted)} min_dist=${f(a.minimum)} $status',
    );
  }
  var missed = 0;
  for (var i = 0; i < list.length; i++) {
    if (!detected.contains(i)) {
      missed++;
      final c = list[i];
      out.writeln(
        'MISSED ${pairName(c.a, c.b, input.plans)} start=${f(c.start)} end=${f(c.end)}',
      );
    }
  }
  out.writeln(
    'SUMMARY alerts=${alerts.length} true=$trueCount false=${alerts.length - trueCount} missed=$missed mean_lead=${trueCount == 0 ? '-' : f(lead / trueCount)}',
  );
}

(int, int)? cell(Vec p, Settings settings) {
  final r = settings.radar,
      fx =
          (10 * p.x - settings.radar[0]) *
          settings.radar[4] /
          (settings.radar[2] - settings.radar[0]),
      fy =
          (10 * p.y - settings.radar[1]) *
          settings.radar[5] /
          (settings.radar[3] - settings.radar[1]);
  final col = fx.floor(), row = fy.floor();
  return col >= 0 && col < r[4] && row >= 0 && row < r[5]
      ? (col, r[5] - 1 - row)
      : null;
}

List<List<String>> blankGrid(Settings settings, String mark) => List.generate(
  settings.radar[5],
  (_) => List.filled(settings.radar[4], mark),
);
void reportRadar(
  StringBuffer out,
  List<List<Trajectory>> trajectories,
  List<List<Conflict>> lists,
  Input input,
  List<int> times,
) {
  for (final time in input.settings.snapshots) {
    for (var plan = 0; plan < 2; plan++) {
      final name = plan == 0 ? 'initial' : 'final',
          grid = blankGrid(input.settings, '.'),
          counts = List.generate(
            input.settings.radar[5],
            (_) => List.filled(input.settings.radar[4], 0),
          ),
          conflicted = <int>{};
      var conflictCount = 0;
      for (final c in lists[plan]) {
        if (active(c, time.toDouble())) {
          conflicted
            ..add(c.a)
            ..add(c.b);
          conflictCount++;
        }
      }
      var aircraft = 0;
      for (var flight = 0; flight < trajectories[plan].length; flight++) {
        final at = trajectories[plan][flight].at(time.toDouble());
        if (at == null) continue;
        aircraft++;
        final (p, _) = at;
        final place = cell(p, input.settings);
        if (place == null) continue;
        final (col, row) = place;
        counts[row][col]++;
        grid[row][col] = counts[row][col] >= 2
            ? '${counts[row][col]}'
            : conflicted.contains(flight)
            ? input.plans[flight].callsign[0].toLowerCase()
            : input.plans[flight].callsign[0];
      }
      for (final trajectory in trajectories[plan]) {
        final now = trajectory.at(time.toDouble()),
            later = trajectory.at((time + input.settings.leader).toDouble());
        if (now != null && later != null) {
          final place = cell(later.$1, input.settings);
          if (place != null) {
            final (col, row) = place;
            if (grid[row][col] == '.') grid[row][col] = '*';
          }
        }
      }
      out.writeln(
        'RADAR plan=$name t=$time aircraft=$aircraft conflicts=$conflictCount',
      );
      chart(out, grid);
      for (var flight = 0; flight < trajectories[plan].length; flight++) {
        final at = trajectories[plan][flight].at(time.toDouble());
        if (at == null) continue;
        final (p, segment) = at;
        final place = cell(p, input.settings),
            where = place == null ? 'outside' : '${place.$1},${place.$2}';
        out.writeln(
          '${input.plans[flight].callsign} x=${f(p.x)} y=${f(p.y)} fl=${format(p.z / 100, 2)} track=${format(track(segment), 1)} phase=${segment.phase} cell=$where',
        );
      }
      for (final c in lists[plan]) {
        if (active(c, time.toDouble())) {
          final pa = trajectories[plan][c.a].at(time.toDouble())!.$1,
              pb = trajectories[plan][c.b].at(time.toDouble())!.$1;
          final d = pa.subtract(pb);
          out.writeln(
            'CONFLICT ${pairName(c.a, c.b, input.plans)} dist=${f(sqrt(d.x * d.x + d.y * d.y))} vert=${format(d.z.abs(), 1)}',
          );
        }
      }
    }
  }
  for (var plan = 0; plan < 2; plan++) {
    final name = plan == 0 ? 'initial' : 'final',
        grid = blankGrid(input.settings, '.'),
        counts = List.generate(
          input.settings.radar[5],
          (_) => List.filled(input.settings.radar[4], 0),
        );
    var maximum = 0;
    for (final time in times) {
      for (final trajectory in trajectories[plan]) {
        final at = trajectory.at(time.toDouble());
        if (at != null) {
          final place = cell(at.$1, input.settings);
          if (place != null) {
            final (col, row) = place;
            counts[row][col]++;
            maximum = max(maximum, counts[row][col]);
          }
        }
      }
    }
    for (var row = 0; row < grid.length; row++) {
      for (var col = 0; col < grid[row].length; col++) {
        final count = counts[row][col];
        if (count >= 10) {
          grid[row][col] = '#';
        } else if (count > 0) {
          grid[row][col] = '$count';
        }
      }
    }
    out.writeln(
      'DENSITY plan=$name from=${input.settings.ta} to=${input.settings.tb} step=60 max=$maximum',
    );
    chart(out, grid);
  }
}

int flightConflictCount(int flight, List<Conflict> list) =>
    list.where((c) => c.a == flight || c.b == flight).length;
(double, int) waypointPass(Trajectory trajectory, int index) {
  if (index == 0) {
    final s = trajectory.segments[0];
    return (s.start, (s.position.z / 100).toInt());
  }
  final result = trajectory.segments.lastWhere((s) => s.leg == index);
  return (result.end, (result.finalPosition.z / 100).toInt());
}

void main() {
  final input = readInput(), n = input.plans.length;
  final initial = [
        for (final p in input.plans) buildTrajectory(p, input.types[p.type]),
      ],
      plans = input.plans.map((p) => p.copy()).toList();
  final finalTrajectories = List.of(initial),
      initialConflicts = conflicts(initial, input.settings),
      unresolvedPairs = <(int, int)>{},
      resolvedPairs = <(int, int)>{},
      unresolved = <Conflict>[],
      history = List.generate(n, (_) => <String>[]);
  final trajectoriesOut = StringBuffer(),
      conflictsOut = StringBuffer(),
      resolutionsOut = StringBuffer(),
      transitsOut = StringBuffer(),
      loadOut = StringBuffer(),
      sectorsOut = StringBuffer(),
      alertsOut = StringBuffer(),
      radarOut = StringBuffer(),
      stripsOut = StringBuffer();
  var rounds = 0,
      resolvedCount = 0,
      trials = 0,
      infeasible = 0,
      blocked = 0,
      levelChanges = 0,
      speedChanges = 0,
      delayChanges = 0;
  final moves = manoeuvres(input.settings);
  while (true) {
    final current = conflicts(finalTrajectories, input.settings),
        targetIndex = current.indexWhere(
          (c) => !unresolvedPairs.contains(pair(c.a, c.b)),
        );
    if (targetIndex < 0) break;
    final target = current[targetIndex];
    rounds++;
    resolutionsOut.writeln(
      'ROUND $rounds ${pairName(target.a, target.b, input.plans)} start=${f(target.start)} end=${f(target.end)} dist=${f(target.closest.loss.distance)}',
    );
    var low = target.a, high = target.b;
    if (!lowerPriority(plans[low], plans[high])) {
      final swap = low;
      low = high;
      high = swap;
    }
    var accepted = false;
    for (final flight in [low, high]) {
      final partner = target.a == flight ? target.b : target.a;
      for (final move in moves) {
        trials++;
        final candidate = apply(
          plans[flight],
          move,
          input.types[plans[flight].type],
          input.settings,
        );
        if (candidate == null) {
          infeasible++;
          resolutionsOut.writeln(
            '  TRY ${plans[flight].callsign} ${move.name} infeasible',
          );
          continue;
        }
        final trajectory = buildTrajectory(
          candidate,
          input.types[candidate.type],
        );
        Conflict? blocker;
        for (var other = 0; other < n; other++) {
          if (other == flight || unresolvedPairs.contains(pair(flight, other)))
            continue;
          var a = flight,
              b = other,
              ta = trajectory,
              tb = finalTrajectories[other];
          if (a > b) {
            final temp = a;
            a = b;
            b = temp;
            final tempTrajectory = ta;
            ta = tb;
            tb = tempTrajectory;
          }
          for (final c in pairConflicts(a, b, ta, tb, input.settings)) {
            if (other == partner ||
                c.start < target.start + input.settings.lookahead) {
              if (blocker == null || compareConflicts(c, blocker) < 0)
                blocker = c;
            }
          }
        }
        if (blocker != null) {
          blocked++;
          resolutionsOut.writeln(
            '  TRY ${plans[flight].callsign} ${move.name} blocked ${pairName(blocker.a, blocker.b, input.plans)} start=${f(blocker.start)}',
          );
          continue;
        }
        accepted = true;
        plans[flight] = candidate;
        finalTrajectories[flight] = trajectory;
        history[flight].add(move.name);
        resolvedPairs.add(pair(target.a, target.b));
        resolvedCount++;
        if (move.kind == 'level') {
          levelChanges++;
        } else if (move.kind == 'speed') {
          speedChanges++;
        } else {
          delayChanges++;
        }
        resolutionsOut.writeln(
          '  TRY ${plans[flight].callsign} ${move.name} accepted',
        );
        resolutionsOut.writeln(
          '  RESULT resolved ${plans[flight].callsign} ${move.name}',
        );
        break;
      }
      if (accepted) break;
    }
    if (!accepted) {
      unresolvedPairs.add(pair(target.a, target.b));
      unresolved.add(target);
      resolutionsOut.writeln('  RESULT unresolved');
    }
  }
  final finalConflicts = conflicts(finalTrajectories, input.settings),
      finalPairs = {for (final c in finalConflicts) pair(c.a, c.b)},
      lists = [initialConflicts, finalConflicts],
      trajectories = [initial, finalTrajectories];
  final classes = [
    for (var plan = 0; plan < 2; plan++)
      [for (final c in lists[plan]) classify(c, trajectories[plan], input)],
  ];
  reportConflicts(
    conflictsOut,
    'initial',
    initialConflicts,
    classes[0],
    initial,
    input,
    resolvedPairs,
    finalPairs,
  );
  reportConflicts(
    conflictsOut,
    'final',
    finalConflicts,
    classes[1],
    finalTrajectories,
    input,
    resolvedPairs,
    finalPairs,
  );
  var totalDelay = 0, totalExtra = 0.0;
  for (var i = 0; i < n; i++) {
    final p = plans[i],
        extra = finalTrajectories[i].arrival - initial[i].arrival;
    totalDelay += p.delay;
    totalExtra += extra;
    final names = history[i].isEmpty ? '-' : history[i].join(',');
    resolutionsOut.writeln(
      'FLIGHT ${p.callsign} departure=${p.departure + p.delay} delay=${p.delay} level=${signed(p.offset)} speed=${p.originalSpeed}->${p.speed} arrival=${f(initial[i].arrival)}->${f(finalTrajectories[i].arrival)} extra=${f(extra)} length=${f(finalTrajectories[i].length)} conflicts=${flightConflictCount(i, initialConflicts)}->${flightConflictCount(i, finalConflicts)} manoeuvres=$names',
    );
  }
  for (final c in unresolved) {
    resolutionsOut.writeln(
      'UNRESOLVED ${pairName(c.a, c.b, input.plans)} start=${f(c.start)} dist=${f(c.closest.loss.distance)}',
    );
  }
  resolutionsOut.writeln(
    'TOTAL rounds=$rounds resolved=$resolvedCount unresolved=${unresolved.length} level=$levelChanges speed=$speedChanges delay=$delayChanges total_delay=$totalDelay total_extra=${f(totalExtra)} trials=$trials infeasible=$infeasible blocked=$blocked',
  );
  trajectoriesOut.writeln(
    'callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end',
  );
  for (var i = 0; i < n; i++) {
    for (final s in finalTrajectories[i].segments) {
      trajectoriesOut.writeln(
        '${plans[i].callsign},${s.number},${s.leg},${s.phase},${f(s.start)},${f(s.end)},${f(s.position.x)},${f(s.position.y)},${(s.position.z / 100).toInt()},${f(s.finalPosition.x)},${f(s.finalPosition.y)},${(s.finalPosition.z / 100).toInt()}',
      );
    }
  }
  final transitLists = [
    transits(initial, input),
    transits(finalTrajectories, input),
  ];
  transitsOut.writeln('callsign,sector,entry,exit,duration,from,to');
  for (final t in transitLists[1]) {
    transitsOut.writeln(
      '${plans[t.flight].callsign},${input.sectors[t.sector].name},${f(t.entry)},${f(t.exit)},${f(t.exit - t.entry)},${sectorName(t.previous, input)},${sectorName(t.next, input)}',
    );
  }
  final times = sampleTimes(input.settings);
  reportSectors(
    loadOut,
    sectorsOut,
    trajectories,
    transitLists,
    classes,
    input,
    times,
  );
  reportAlerts(alertsOut, 'initial', initial, initialConflicts, input, times);
  reportAlerts(
    alertsOut,
    'final',
    finalTrajectories,
    finalConflicts,
    input,
    times,
  );
  reportRadar(radarOut, trajectories, lists, input, times);
  for (var i = 0; i < n; i++) {
    final p = plans[i], names = history[i].isEmpty ? '-' : history[i].join(',');
    stripsOut.writeln(
      'STRIP ${p.callsign} type=${input.types[p.type].name} waypoints=${p.waypoints.length} length=${f(finalTrajectories[i].length)} manoeuvres=$names',
    );
    for (var k = 0; k < p.waypoints.length; k++) {
      final w = p.waypoints[k];
      final (t0, fl0) = waypointPass(initial[i], k);
      final (t1, fl1) = waypointPass(finalTrajectories[i], k);
      stripsOut.writeln(
        'WPT $k at=${w.x}:${w.y} eta=${f(t0)}->${f(t1)} fl=$fl0->$fl1',
      );
    }
    final sequence = [
      for (final t in transitLists[1])
        if (t.flight == i) '${input.sectors[t.sector].name}@${f(t.entry)}',
    ];
    stripsOut.writeln('SECTORS ${sequence.isEmpty ? '-' : sequence.join(',')}');
  }
  Directory('output').createSync(recursive: true);
  final outputs = {
    'trajectories.csv': trajectoriesOut,
    'conflicts.txt': conflictsOut,
    'resolutions.txt': resolutionsOut,
    'sector_transits.csv': transitsOut,
    'sector_load.csv': loadOut,
    'sector_report.txt': sectorsOut,
    'alerts.txt': alertsOut,
    'radar.txt': radarOut,
    'strips.txt': stripsOut,
  };
  for (final entry in outputs.entries) {
    write('output/${entry.key}', entry.value);
  }
}
