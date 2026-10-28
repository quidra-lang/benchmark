import 'dart:io';
import 'dart:math';

part 'waveform_io.dart';
part 'picker.dart';
part 'associator.dart';
part 'locator.dart';
part 'magnitude.dart';

class Jack {
  final Station station;
  final double dx, dy, dz, shift;
  Jack(this.station, this.dx, this.dy, this.dz, this.shift);
}

class Quality {
  final Ellipse ellipse;
  double gap = 0, dmin = double.infinity, dh = 0, dz = 0;
  String grade = 'C';
  final jackknife = <Jack>[];
  late Jack maximum;
  Quality(this.ellipse);
}

class Event {
  final int number;
  final List<Pick> used;
  final LocationRun first;
  late LocationRun finalRun;
  List<Observation> observations = [];
  double startRMS = 0;
  late Quality quality;
  final magnitudes = <PickMagnitude>[];
  bool hasML = false;
  double ml = 0, md = 0, mlc = 0;
  int cluster = 0;
  Event(this.number, this.used, this.first);
}

class Cluster {
  final int number;
  final List<int> members;
  final List<double> center;
  final double span;
  Cluster(this.number, this.members, this.center, this.span);
}

class Regression {
  final int n;
  final double velocity, intercept, rms;
  Regression(this.n, this.velocity, this.intercept, this.rms);
}

int scaledDecimal(double value, int digits) {
  var scale = 1;
  for (var i = 0; i < digits; i++) {
    scale *= 10;
  }
  final magnitude = (value.abs() * scale + 0.5).floor();
  return value < 0 ? -magnitude : magnitude;
}

String decimal(double value, int digits) {
  var n = scaledDecimal(value, digits), sign = '', scale = 1;
  if (n < 0) {
    sign = '-';
    n = -n;
  }
  for (var i = 0; i < digits; i++) {
    scale *= 10;
  }
  return digits == 0
      ? '$sign$n'
      : '$sign${n ~/ scale}.${'${n % scale}'.padLeft(digits, '0')}';
}

String timeNotation(int sample) =>
    '${sample ~/ 100}.${'${sample % 100}'.padLeft(2, '0')}';
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

List<Pick> stationOrdered(List<Pick> picks) =>
    List<Pick>.of(picks)
      ..sort((a, b) => a.station.order.compareTo(b.station.order));
List<Observation> observations(List<Pick> picks, bool corrected) => [
  for (final pick in picks)
    Observation(
      pick.station,
      pick.time - (corrected ? pick.station.timeCorrection : 0),
    ),
];
List<Event> locateCandidates(List<Candidate> candidates, Params p) {
  final events = <Event>[];
  for (final candidate in candidates) {
    final ordered = stationOrdered(candidate.picks),
        first = runLocation(observations(ordered, false), p),
        retained = <Pick>[];
    candidate.passes.add(LocationPass(ordered, first));
    for (var i = 0; i < ordered.length; i++) {
      final pick = ordered[i], error = first.residuals[i];
      if (error.abs() > p.real('residual_limit')) {
        candidate.dropped.add(Drop(pick, error));
      } else {
        retained.add(pick);
      }
    }
    if (candidate.dropped.isNotEmpty &&
        retained.length < p.integer('min_stations')) {
      candidate.rejected = true;
      for (final pick in ordered) {
        pick.state = 'rejected';
      }
      continue;
    }
    var adopted = first;
    if (candidate.dropped.isNotEmpty) {
      adopted = runLocation(observations(retained, false), p);
      candidate.passes.add(LocationPass(retained, adopted));
    }
    final number = events.length + 1;
    candidate.event = number;
    for (var i = 0; i < retained.length; i++) {
      final pick = retained[i];
      pick.state = 'used';
      pick.event = number;
      pick.firstResidual = adopted.residuals[i];
      pick.station.firstResiduals.add(pick.firstResidual);
    }
    for (final drop in candidate.dropped) {
      drop.pick.state = 'dropped';
      drop.pick.event = number;
    }
    events.add(Event(number, retained, adopted));
  }
  return events;
}

Quality qualityForEvent(Event event, Params p) {
  final solution = event.finalRun.solution,
      quality = Quality(
        errorEllipse(
          event.finalRun.solution,
          event.observations,
          p.real('velocity'),
        ),
      ),
      angles = <double>[];
  for (final pick in event.used) {
    final station = pick.station;
    var angle =
        atan2(station.x - solution[0], station.y - solution[1]) *
        180 /
        circlePi;
    if (angle < 0) {
      angle += 360;
    }
    angles.add(angle);
    final dx = station.x - solution[0], dy = station.y - solution[1];
    quality.dmin = min(quality.dmin, sqrt(dx * dx + dy * dy));
  }
  angles.sort();
  quality.gap = angles.first + 360 - angles.last;
  for (var i = 0; i + 1 < angles.length; i++) {
    quality.gap = max(quality.gap, angles[i + 1] - angles[i]);
  }
  bool fits(String key) =>
      quality.gap <= p.real(key) &&
      event.finalRun.rms <= p.real(key, 1) &&
      quality.ellipse.smaj <= p.real(key, 2);
  quality.grade = fits('quality_a')
      ? 'A'
      : fits('quality_b')
      ? 'B'
      : 'C';
  final dx = solution[0] - event.first.solution[0],
      dy = solution[1] - event.first.solution[1];
  quality.dh = sqrt(dx * dx + dy * dy);
  quality.dz = solution[2] - event.first.solution[2];
  for (var i = 0; i < event.used.length; i++) {
    final remaining = [
          for (var j = 0; j < event.observations.length; j++)
            if (i != j) event.observations[j],
        ],
        run = geiger(solution, remaining, p.real('velocity'));
    final dx = run.solution[0] - solution[0],
        dy = run.solution[1] - solution[1],
        dz = run.solution[2] - solution[2],
        jack = Jack(event.used[i].station, dx, dy, dz, sqrt(dx * dx + dy * dy));
    quality.jackknife.add(jack);
    if (i == 0 || jack.shift > quality.maximum.shift) {
      quality.maximum = jack;
    }
  }
  return quality;
}

void relocateEvents(List<Event> events, List<Station> stations, Params p) {
  for (final station in stations) {
    if (station.firstResiduals.isNotEmpty) {
      station.timeCorrection =
          sum(station.firstResiduals) / station.firstResiduals.length;
    }
  }
  for (final event in events) {
    event.observations = observations(event.used, true);
    event.startRMS = rms(
      event.first.solution,
      event.observations,
      p.real('velocity'),
    );
    event.finalRun = geiger(
      event.first.solution,
      event.observations,
      p.real('velocity'),
    );
    for (var i = 0; i < event.used.length; i++) {
      final pick = event.used[i];
      pick.residual = event.finalRun.residuals[i];
      pick.station.finalResiduals.add(pick.residual);
    }
    event.quality = qualityForEvent(event, p);
  }
}

void computeMagnitudes(List<Event> events, List<Station> stations, Params p) {
  for (final event in events) {
    final local = <double>[], duration = <double>[];
    for (final pick in event.used) {
      final data = perPickMagnitude(
        pick,
        distance(event.finalRun.solution, pick.station) / 1000,
        p,
      );
      event.magnitudes.add(data);
      duration.add(data.md);
      if (data.hasML) {
        local.add(data.ml);
      }
    }
    event.hasML = local.isNotEmpty;
    if (event.hasML) {
      event.ml = median(local);
    }
    event.md = median(duration);
    for (final m in event.magnitudes) {
      if (m.hasML) {
        m.pick.station.magResiduals.add(m.ml - event.ml);
      }
    }
  }
  for (final s in stations) {
    if (s.magResiduals.isNotEmpty) {
      s.magCorrection = sum(s.magResiduals) / s.magResiduals.length;
    }
  }
  for (final event in events) {
    final corrected = [
      for (final m in event.magnitudes)
        if (m.hasML) m.ml - m.pick.station.magCorrection,
    ];
    if (corrected.isNotEmpty) {
      event.mlc = median(corrected);
    }
  }
}

Regression travelTimeRegression(List<Event> events) {
  final points = <(double, double)>[];
  var sd = 0.0, st = 0.0, sdd = 0.0, sdt = 0.0;
  for (final event in events) {
    for (final pick in event.used) {
      final d = distance(event.finalRun.solution, pick.station) / 1000,
          t = pick.time - event.finalRun.solution[3];
      points.add((d, t));
      sd += d;
      st += t;
      sdd += d * d;
      sdt += d * t;
    }
  }
  final n = points.length,
      slope = (n * sdt - sd * st) / (n * sdd - sd * sd),
      intercept = (st - slope * sd) / n;
  var total = 0.0;
  for (final (d, t) in points) {
    final error = t - intercept - slope * d;
    total += error * error;
  }
  return Regression(n, 1000 / slope, intercept, sqrt(total / n));
}

List<Cluster> clusterEvents(List<Event> events, Params p) {
  final neighbors = List.generate(events.length, (_) => <int>[]);
  for (var i = 0; i < events.length; i++) {
    for (var j = i + 1; j < events.length; j++) {
      final x = events[i].finalRun.solution, y = events[j].finalRun.solution;
      if ((x[3] - y[3]).abs() > p.real('cluster', 1)) {
        continue;
      }
      var total = 0.0;
      for (var axis = 0; axis < 3; axis++) {
        final d = x[axis] - y[axis];
        total += d * d;
      }
      if (sqrt(total) <= p.real('cluster')) {
        neighbors[i].add(j);
        neighbors[j].add(i);
      }
    }
  }
  final seen = List.filled(events.length, false), clusters = <Cluster>[];
  for (var first = 0; first < events.length; first++) {
    if (seen[first]) {
      continue;
    }
    seen[first] = true;
    final queue = <int>[first];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      for (final other in neighbors[queue[cursor]]) {
        if (!seen[other]) {
          seen[other] = true;
          queue.add(other);
        }
      }
    }
    queue.sort();
    final number = clusters.length + 1,
        members = <int>[],
        center = List.filled(3, 0.0);
    var earliest = double.infinity, latest = double.negativeInfinity;
    for (final index in queue) {
      final event = events[index];
      event.cluster = number;
      members.add(event.number);
      for (var axis = 0; axis < 3; axis++) {
        center[axis] += event.finalRun.solution[axis];
      }
      earliest = min(earliest, event.finalRun.solution[3]);
      latest = max(latest, event.finalRun.solution[3]);
    }
    for (var axis = 0; axis < 3; axis++) {
      center[axis] /= queue.length;
    }
    clusters.add(Cluster(number, members, center, latest - earliest));
  }
  return clusters;
}

List<Pick> reassociate(List<Pick> picks, List<Event> events, Params p) {
  final stationSets = [
        for (final event in events)
          {for (final pick in event.used) pick.station.order},
      ],
      added = <Pick>[];
  for (final pick in picks) {
    if (pick.state != 'unassociated') {
      continue;
    }
    var best = -1, bestAbsolute = double.infinity, residual = 0.0;
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      if (stationSets[i].contains(pick.station.order)) {
        continue;
      }
      final rho =
          pick.time -
          event.finalRun.solution[3] -
          distance(event.finalRun.solution, pick.station) / p.real('velocity') -
          pick.station.timeCorrection;
      if (rho.abs() <= p.real('residual_limit') && rho.abs() < bestAbsolute) {
        best = i;
        bestAbsolute = rho.abs();
        residual = rho;
      }
    }
    if (best >= 0) {
      pick.state = 'added';
      pick.event = events[best].number;
      pick.residual = residual;
      stationSets[best].add(pick.station.order);
      added.add(pick);
    }
  }
  return added;
}

List<String> picksFile(List<Pick> picks) => [
  'station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual',
  for (final pick in picks)
    '${pick.station.code},${pick.sample},${timeNotation(pick.sample)},${pick.duration},${decimal(pick.ratio, 2)},${pick.amplitude},${pick.clipped ? 'yes' : 'no'},${['used', 'dropped', 'added'].contains(pick.state) ? pick.event : 0},${pick.state},${['used', 'added'].contains(pick.state) ? decimal(pick.residual, 4) : '-'}',
];
String formatSolution(String label, Solution solution, double rms) =>
    '$label x=${decimal(solution[0], 1)} y=${decimal(solution[1], 1)} z=${decimal(solution[2], 1)} t0=${decimal(solution[3], 3)} rms=${decimal(rms, 4)}';
List<String> iterationLines(LocationRun run) => [
  for (final iteration in run.trace)
    formatSolution(
      'ITER ${iteration.number}',
      iteration.solution,
      iteration.rms,
    ),
];
List<String> locationPassLines(int number, LocationPass pass, double velocity) {
  final grid = pass.run.grid!,
      lines = <String>[
        'PASS $number stations=${pass.picks.map((p) => p.station.code).join(',')}',
        formatSolution('GRID', grid.solution, grid.rms),
        'PROFILE ${grid.profile.map((v) => decimal(v, 4)).join(' ')}',
        ...iterationLines(pass.run),
      ];
  for (var i = 0; i < pass.picks.length; i++) {
    final pick = pass.picks[i], d = distance(pass.run.solution, pick.station);
    lines.add(
      'RES ${pick.station.code} dist=${decimal(d, 1)} tt=${decimal(d / velocity, 4)} obs=${timeNotation(pick.sample)} res=${decimal(pass.run.residuals[i], 4)}',
    );
  }
  return lines;
}

List<String> locationFile(
  List<Pick> picks,
  List<Candidate> candidates,
  List<Event> events,
  List<Station> stations,
  Regression regression,
  List<Cluster> clusters,
  List<Pick> added,
  Params p,
) {
  final lines = <String>[], velocity = p.real('velocity');
  for (final candidate in candidates) {
    lines.add(
      'CANDIDATE ${candidate.number} picks=${candidate.picks.length} first=${timeNotation(candidate.first.sample)}',
    );
    lines.addAll(locationPassLines(1, candidate.passes[0], velocity));
    for (final drop in candidate.dropped) {
      lines.add(
        'DROP ${drop.pick.station.code} res=${decimal(drop.residual, 4)}',
      );
    }
    if (candidate.rejected) {
      lines.add(
        'RESULT REJECTED stations=${candidate.picks.length - candidate.dropped.length}',
      );
    } else {
      if (candidate.passes.length == 2) {
        lines.addAll(locationPassLines(2, candidate.passes[1], velocity));
      }
      lines.add('RESULT EVENT ${candidate.event}');
    }
  }
  lines.add('CORRECTIONS');
  for (final station in stations) {
    lines.add(
      '${station.code} n=${station.firstResiduals.length} correction=${decimal(station.timeCorrection, 4)}',
    );
  }
  for (final event in events) {
    lines.addAll([
      'EVENT ${event.number}',
      formatSolution('START', event.first.solution, event.startRMS),
      ...iterationLines(event.finalRun),
    ]);
    for (final pick in event.used) {
      final d = distance(event.finalRun.solution, pick.station);
      lines.add(
        'RES ${pick.station.code} dist=${decimal(d, 1)} tt=${decimal(d / velocity, 4)} obs=${timeNotation(pick.sample)} corr=${decimal(pick.station.timeCorrection, 4)} res=${decimal(pick.residual, 4)}',
      );
    }
    final q = event.quality, e = q.ellipse;
    lines.addAll([
      'ELLIPSE smaj=${decimal(e.smaj, 1)} smin=${decimal(e.smin, 1)} az=${decimal(e.az, 1)} erz=${decimal(e.erz, 1)} ert=${decimal(e.ert, 4)}',
      'SHIFT dh=${decimal(q.dh, 1)} dz=${decimal(q.dz, 1)}',
      'GAP ${decimal(q.gap, 1)} DMIN ${decimal(q.dmin, 1)} QUALITY ${q.grade}',
    ]);
    for (final jack in q.jackknife) {
      lines.add(
        'JACK ${jack.station.code} dx=${decimal(jack.dx, 1)} dy=${decimal(jack.dy, 1)} dz=${decimal(jack.dz, 1)} shift=${decimal(jack.shift, 1)}',
      );
    }
    lines.add(
      'JACKKNIFE max=${decimal(q.maximum.shift, 1)} station=${q.maximum.station.code}',
    );
  }
  lines.add(
    'FIT n=${regression.n} velocity=${decimal(regression.velocity, 1)} intercept=${decimal(regression.intercept, 4)} rms=${decimal(regression.rms, 4)}',
  );
  for (final cluster in clusters) {
    if (cluster.members.length >= 2) {
      lines.add(
        'CLUSTER ${cluster.number} events=${cluster.members.join(',')} x=${decimal(cluster.center[0], 1)} y=${decimal(cluster.center[1], 1)} z=${decimal(cluster.center[2], 1)} span=${decimal(cluster.span, 3)}',
      );
    }
  }
  lines.add('ADDED');
  for (final pick in added) {
    lines.add(
      '${pick.station.code} sample=${pick.sample} event=${pick.event} res=${decimal(pick.residual, 4)}',
    );
  }
  lines.add(
    'SUMMARY picks=${picks.length} candidates=${candidates.length} events=${events.length} rejected=${candidates.where((c) => c.rejected).length} unassociated=${picks.where((p) => p.state == 'unassociated').length}',
  );
  final depths = [for (final event in events) event.finalRun.solution[2]],
      qualities = <String, int>{};
  var rmsTotal = 0.0;
  for (final event in events) {
    qualities[event.quality.grade] = (qualities[event.quality.grade] ?? 0) + 1;
    rmsTotal += event.finalRun.rms;
  }
  lines.addAll([
    'DEPTH min=${decimal(depths.reduce(min), 1)} median=${decimal(median(depths), 1)} max=${decimal(depths.reduce(max), 1)}',
    'QUALITY A=${qualities['A'] ?? 0} B=${qualities['B'] ?? 0} C=${qualities['C'] ?? 0} mean_rms=${decimal(rmsTotal / events.length, 4)}',
  ]);
  return lines;
}

String optionalMagnitude(double value, bool present) =>
    present ? decimal(value, 2) : '-';
List<String> catalogFile(List<Event> events) {
  final lines = <String>[
    'event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster',
  ];
  for (final event in events) {
    final s = event.finalRun.solution, q = event.quality, e = q.ellipse;
    lines.add(
      [
        '${event.number}',
        decimal(s[3], 3),
        decimal(s[0], 1),
        decimal(s[1], 1),
        decimal(s[2], 1),
        decimal(event.finalRun.rms, 4),
        '${event.used.length}',
        decimal(q.gap, 1),
        decimal(q.dmin, 1),
        decimal(e.smaj, 1),
        decimal(e.smin, 1),
        decimal(e.az, 1),
        decimal(e.erz, 1),
        optionalMagnitude(event.ml, event.hasML),
        decimal(event.md, 2),
        q.grade,
        '${event.cluster}',
      ].join(','),
    );
  }
  return lines;
}

List<List<String>> blankCanvas(int width, int height) =>
    List.generate(height, (_) => List.filled(width, ' '));
List<String> framed(List<List<String>> rows) {
  final border = '+${'-' * rows.first.length}+';
  return [border, for (final row in rows) '|${row.join()}|', border];
}

List<String> timeline(List<Event> events, Params p) {
  final duration = p.integer('timeline'),
      width = p.integer('timeline', 1),
      low = p.integer('timeline', 2),
      high = p.integer('timeline', 3),
      height = p.integer('timeline', 4),
      rows = blankCanvas(width, height);
  for (final event in events) {
    if (!event.hasML) {
      continue;
    }
    final t = scaledDecimal(event.finalRun.solution[3], 3),
        h = scaledDecimal(event.ml, 2);
    if (t < 0 || t >= 1000 * duration || h < 100 * low) {
      continue;
    }
    final column = t * width ~/ (1000 * duration),
        level = min(
          (h - 100 * low) * height ~/ (100 * (high - low)),
          height - 1,
        );
    for (var k = 0; k <= level; k++) {
      final row = height - 1 - k;
      if (k == level) {
        rows[row][column] = 'o';
      } else if (rows[row][column] == ' ') {
        rows[row][column] = '|';
      }
    }
  }
  return ['TIMELINE t=0..$duration ML=$low..$high', ...framed(rows)];
}

List<String> magnitudeFile(List<Event> events, FrequencyStats stats, Params p) {
  final lines = <String>[];
  for (final event in events) {
    lines.add(
      'EVENT ${event.number} ML=${optionalMagnitude(event.ml, event.hasML)} n=${event.magnitudes.where((m) => m.hasML).length} MD=${decimal(event.md, 2)}',
    );
    for (final m in event.magnitudes) {
      final pick = m.pick;
      var prefix =
          '${pick.station.code} r=${decimal(m.r, 3)} amp=${pick.amplitude} ';
      prefix += m.hasML
          ? 'ml=${decimal(m.ml, 2)} res=${decimal(m.ml - event.ml, 2)} '
          : 'clipped ';
      lines.add('${prefix}dur=${pick.duration} md=${decimal(m.md, 2)}');
    }
  }
  lines.add('CORRECTED');
  for (final event in events) {
    lines.add(
      'EVENT ${event.number} MLC=${optionalMagnitude(event.mlc, event.hasML)}',
    );
  }
  lines.add('FMD');
  var cumulative = stats.classes.values.fold(0, (a, b) => a + b);
  for (var c = stats.minimum; c <= stats.maximum; c++) {
    lines.add(
      'M=${magnitudeClass(c)} N=${stats.classes[c] ?? 0} CUM=$cumulative',
    );
    cumulative -= stats.classes[c] ?? 0;
  }
  lines.addAll([
    'MC ${magnitudeClass(stats.completeness)}',
    'BVALUE ${decimal(stats.bvalue, 3)} SIGMA ${decimal(stats.sigma, 3)} N ${stats.nb}',
    'AVALUE ${decimal(stats.avalue, 3)}',
    'MLMD n=${stats.n} slope=${decimal(stats.slope, 3)} intercept=${decimal(stats.intercept, 3)} r=${decimal(stats.r, 3)} mean_diff=${decimal(stats.meanDiff, 3)}',
    ...timeline(events, p),
  ]);
  return lines;
}

String residualRMS(List<double> values) {
  if (values.isEmpty) {
    return '-';
  }
  var total = 0.0;
  for (final v in values) {
    total += v * v;
  }
  return decimal(sqrt(total / values.length), 4);
}

List<String> stationFile(List<Station> stations) {
  final lines = <String>[];
  for (final s in stations) {
    final states = <String, int>{};
    for (final pick in s.picks) {
      states[pick.state] = (states[pick.state] ?? 0) + 1;
    }
    lines.addAll([
      'STATION ${s.code} x=${s.x} y=${s.y} elevation=${s.elevation}',
      'SAMPLES start=${s.start} count=${s.samples.length} mean=${s.mean} noise=${decimal(s.noise, 1)} peak=${s.peak} clipped=${s.clippedSamples}',
      'TRIGGERS total=${s.triggers} short=${s.shortTriggers} picks=${s.picks.length}',
      'PICKS used=${states['used'] ?? 0} dropped=${states['dropped'] ?? 0} added=${states['added'] ?? 0} rejected=${states['rejected'] ?? 0} unassociated=${states['unassociated'] ?? 0}',
      'RESIDUALS n=${s.firstResiduals.length} rms=${residualRMS(s.firstResiduals)} correction=${decimal(s.timeCorrection, 4)} after=${residualRMS(s.finalResiduals)}',
      'MAGNITUDES n=${s.magResiduals.length} correction=${decimal(s.magCorrection, 2)}',
    ]);
  }
  return lines;
}

typedef PlotPosition = (int, int)?;
String positionText(PlotPosition p) =>
    p == null ? 'outside' : '${p.$1},${p.$2}';
String eventSymbol(Event event) {
  if (!event.hasML) {
    return '?';
  }
  final h = scaledDecimal(event.ml, 2);
  return h < 100
      ? '.'
      : h < 200
      ? 'o'
      : h < 300
      ? 'O'
      : '@';
}

List<PlotPosition> eventPositions(Event event, Params p) {
  final x = scaledDecimal(event.finalRun.solution[0], 1),
      y = scaledDecimal(event.finalRun.solution[1], 1),
      z = scaledDecimal(event.finalRun.solution[2], 1),
      left = p.integer('map_area'),
      right = p.integer('map_area', 1),
      bottom = p.integer('map_area', 2),
      top = p.integer('map_area', 3),
      width = p.integer('map_size'),
      height = p.integer('map_size', 1),
      limit = p.integer('section'),
      sectionHeight = p.integer('section', 1);
  return [
    10 * left <= x && x < 10 * right && 10 * bottom <= y && y < 10 * top
        ? (
            (x - 10 * left) * width ~/ (10 * (right - left)),
            height - 1 - (y - 10 * bottom) * height ~/ (10 * (top - bottom)),
          )
        : null,
    10 * left <= x && x < 10 * right && z < 10 * limit
        ? (
            (x - 10 * left) * width ~/ (10 * (right - left)),
            z * sectionHeight ~/ (10 * limit),
          )
        : null,
    10 * bottom <= y && y < 10 * top && z < 10 * limit
        ? (
            (y - 10 * bottom) * width ~/ (10 * (top - bottom)),
            z * sectionHeight ~/ (10 * limit),
          )
        : null,
  ];
}

PlotPosition stationPosition(Station s, Params p) {
  final left = p.integer('map_area'),
      right = p.integer('map_area', 1),
      bottom = p.integer('map_area', 2),
      top = p.integer('map_area', 3);
  if (s.x < left || s.x >= right || s.y < bottom || s.y >= top) {
    return null;
  }
  return (
    (s.x - left) * p.integer('map_size') ~/ (right - left),
    p.integer('map_size', 1) -
        1 -
        (s.y - bottom) * p.integer('map_size', 1) ~/ (top - bottom),
  );
}

void placePoint(List<List<String>> rows, PlotPosition position, String symbol) {
  if (position == null) {
    return;
  }
  const rank = {' ': -1, '?': 0, '.': 1, 'o': 2, 'O': 3, '@': 4, '^': 5};
  if (rank[symbol]! > rank[rows[position.$2][position.$1]]!) {
    rows[position.$2][position.$1] = symbol;
  }
}

List<String> mapFile(List<Event> events, List<Station> stations, Params p) {
  final width = p.integer('map_size'),
      height = p.integer('map_size', 1),
      sectionHeight = p.integer('section', 1),
      grids = [
        blankCanvas(width, height),
        blankCanvas(width, sectionHeight),
        blankCanvas(width, sectionHeight),
      ],
      locations = [for (final event in events) eventPositions(event, p)];
  for (var i = 0; i < events.length; i++) {
    for (var j = 0; j < 3; j++) {
      placePoint(grids[j], locations[i][j], eventSymbol(events[i]));
    }
  }
  final stationLocations = <PlotPosition>[];
  for (final station in stations) {
    final position = stationPosition(station, p);
    stationLocations.add(position);
    placePoint(grids[0], position, '^');
  }
  final left = p.integer('map_area'),
      right = p.integer('map_area', 1),
      bottom = p.integer('map_area', 2),
      top = p.integer('map_area', 3),
      limit = p.integer('section'),
      headings = [
        'MAP x=$left..$right y=$bottom..$top',
        'SECTION EW x=$left..$right z=0..$limit',
        'SECTION NS y=$bottom..$top z=0..$limit',
      ],
      lines = <String>[];
  for (var i = 0; i < 3; i++) {
    lines.addAll([headings[i], ...framed(grids[i])]);
  }
  lines.add('LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML');
  for (var i = 0; i < stations.length; i++) {
    lines.add(
      'STATION ${stations[i].code} map=${positionText(stationLocations[i])}',
    );
  }
  for (var i = 0; i < events.length; i++) {
    final event = events[i], positions = locations[i];
    lines.add(
      'EVENT ${event.number} ${eventSymbol(event)} map=${positionText(positions[0])} ew=${positionText(positions[1])} ns=${positionText(positions[2])}',
    );
  }
  return lines;
}

void main() {
  final (stations, p) = loadInputs();
  final picks = <Pick>[];
  for (final station in stations) {
    picks.addAll(detectStation(station, p));
  }
  picks.sort((a, b) {
    final c = a.sample.compareTo(b.sample);
    return c != 0 ? c : a.station.order.compareTo(b.station.order);
  });
  final candidates = associate(
        picks,
        p.integer('association_window'),
        p.integer('min_stations'),
      ),
      events = locateCandidates(candidates, p);
  relocateEvents(events, stations, p);
  computeMagnitudes(events, stations, p);
  final regression = travelTimeRegression(events),
      clusters = clusterEvents(events, p),
      added = reassociate(picks, events, p),
      stats = frequencyStatistics(events);
  writeLines('picks.csv', picksFile(picks));
  writeLines(
    'locations.txt',
    locationFile(
      picks,
      candidates,
      events,
      stations,
      regression,
      clusters,
      added,
      p,
    ),
  );
  writeLines('catalog.csv', catalogFile(events));
  writeLines('magnitudes.txt', magnitudeFile(events, stats, p));
  writeLines('stations.txt', stationFile(stations));
  writeLines('map.txt', mapFile(events, stations, p));
}
