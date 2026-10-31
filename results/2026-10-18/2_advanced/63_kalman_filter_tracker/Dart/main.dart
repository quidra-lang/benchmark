import 'dart:io';
import 'dart:math';
part 'matrix.dart';
part 'kalman.dart';
part 'association.dart';
part 'imm.dart';
part 'evaluation.dart';

const filterNames = ['cv', 'ca', 'abg', 'imm', 'rts'];
typedef Point = (double, double);

class Scan {
  final double time;
  final measurements = <Point>[];
  Scan(this.time);
}

class Target {
  final int id, first;
  int last;
  final positions = <int, Point>{};
  Target(this.id, this.first) : last = first;
}

class Params {
  String model = '';
  double qcv = 0,
      qca = 0,
      sigma = 0,
      velocity = 0,
      acceleration = 0,
      gate = 0,
      match = 0,
      cutoff = 0,
      bound = 0,
      xMin = 0,
      xMax = 0,
      yMin = 0,
      yMax = 0;
  int m = 0, n = 0, delete = 0, w = 0, h = 0;
  final abg = List.filled(3, 0.0),
      immQ = List.filled(2, 0.0),
      immTransition = List.generate(2, (_) => List.filled(2, 0.0)),
      immInitial = List.filled(2, 0.0),
      edges = <double>[];
}

class Data {
  final scans = <Scan>[], targets = <Target>[];
  final params = Params();
  int measurements = 0;
}

List<String> lines(String path) => File(path).readAsLinesSync();
Data readData() {
  final out = Data();
  for (final line in lines('input/measurements.csv').skip(1)) {
    final a = line.split(','), k = int.parse(a[0]) - 1;
    while (out.scans.length <= k) {
      out.scans.add(Scan(double.parse(a[1])));
    }
    out.scans[k].measurements.add((double.parse(a[2]), double.parse(a[3])));
    out.measurements++;
  }
  final index = <int, int>{};
  for (final line in lines('input/truth.csv').skip(1)) {
    final a = line.split(','), id = int.parse(a[0]), k = int.parse(a[1]) - 1;
    var i = index[id];
    if (i == null) {
      i = out.targets.length;
      index[id] = i;
      out.targets.add(Target(id, k));
    }
    out.targets[i].last = k;
    out.targets[i].positions[k] = (double.parse(a[2]), double.parse(a[3]));
  }
  final p = out.params;
  for (final line in lines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'MODEL':
        p.model = a[1];
      case 'Q_CV':
        p.qcv = double.parse(a[1]);
      case 'Q_CA':
        p.qca = double.parse(a[1]);
      case 'SIGMA':
        p.sigma = double.parse(a[1]);
      case 'INIT_VELOCITY_VARIANCE':
        p.velocity = double.parse(a[1]);
      case 'INIT_ACCELERATION_VARIANCE':
        p.acceleration = double.parse(a[1]);
      case 'GATE':
        p.gate = double.parse(a[1]);
      case 'CONFIRM':
        p.m = int.parse(a[1]);
        p.n = int.parse(a[2]);
      case 'DELETE':
        p.delete = int.parse(a[1]);
      case 'ABG':
        for (var i = 0; i < 3; i++) {
          p.abg[i] = double.parse(a[i + 1]);
        }
      case 'IMM_Q':
        p.immQ[0] = double.parse(a[1]);
        p.immQ[1] = double.parse(a[2]);
      case 'IMM_TRANSITION':
        for (var i = 0; i < 2; i++) {
          for (var j = 0; j < 2; j++) {
            p.immTransition[i][j] = double.parse(a[1 + 2 * i + j]);
          }
        }
      case 'IMM_INITIAL':
        p.immInitial[0] = double.parse(a[1]);
        p.immInitial[1] = double.parse(a[2]);
      case 'MATCH_DISTANCE':
        p.match = double.parse(a[1]);
      case 'OSPA_CUTOFF':
        p.cutoff = double.parse(a[1]);
      case 'CONSISTENCY_BOUND':
        p.bound = double.parse(a[1]);
      case 'NIS_EDGES':
        p.edges.addAll(a.sublist(1).map(double.parse));
      case 'PLOT_X':
        p.xMin = double.parse(a[1]);
        p.xMax = double.parse(a[2]);
      case 'PLOT_Y':
        p.yMin = double.parse(a[1]);
        p.yMax = double.parse(a[2]);
      case 'PLOT_SIZE':
        p.w = int.parse(a[1]);
        p.h = int.parse(a[2]);
    }
  }
  return out;
}

void writeLines(String name, List<String> a) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${a.join('\n')}\n');
}

class Track {
  final int id, birth;
  int confirmation = -1, deletion = -1, lastHit, hits = 1, misses = 0;
  String status = 'tentative';
  State state;
  final List<Point?> measurements;
  final nis = <double>[];
  Track(this.id, this.birth, this.state, Point point)
    : lastHit = birth,
      measurements = [point];
}

class Segment {
  final int first, last, target;
  Segment(this.first, this.last, this.target);
}

class Evaluated {
  final Track track;
  final List<Point?> sequence;
  final filters = List.generate(5, (_) => <List<double>>[]),
      likelihood = List.filled(2, 0.0),
      high = <double>[],
      segments = <Segment>[];
  List<State> primary = [];
  final List<int> scanTargets;
  int matchedScans = 0, matchedTarget = -1, common = 0;
  double meanDistance = 0;
  Evaluated(this.track, this.sequence, int scans)
    : scanTargets = List.filled(scans, -1);
}

String listLine(String keyword, List<String> items) =>
    '$keyword ${items.isEmpty ? 'none' : items.join(' ')}';
Point pointOf(List<double> v) => (v[0], v[1]);
double sum(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x;
  }
  return s;
}

String optionalScan(int k) => k < 0 ? '-' : '${k + 1}';

class Application {
  final Data data;
  final tracks = <Track>[], evaluated = <Evaluated>[];
  int primary = 0,
      conflictMeasurements = 0,
      conflictTracks = 0,
      greedyDifferences = 0;
  final labels = List.generate(5, (_) => <List<int>>[]);
  List<List<double>> ospaValues = [];
  List<int> scanTracks = [], scanTargets = [], targetTracks = [];
  Application(this.data);
  void tracking() {
    final p = data.params, q = p.model == 'CA' ? p.qca : p.qcv;
    if (p.model == 'CA') primary = 1;
    final csv = ['track,scan,x,y,vx,vy,status'], log = <String>[];
    for (var k = 0; k < data.scans.length; k++) {
      final scan = data.scans[k],
          live = tracks.where((t) => t.status != 'deleted').toList();
      if (k > 0) {
        final t = scan.time - data.scans[k - 1].time;
        for (final track in live) {
          track.state = predict(track.state, p.model, t, q).$1;
        }
      }
      final cost = zeros(live.length, scan.measurements.length),
          usable = List.generate(
            live.length,
            (_) => List.filled(scan.measurements.length, false),
          ),
          rowGates = List.filled(live.length, 0),
          columnGates = List.filled(scan.measurements.length, 0),
          gates = <String>[],
          candidates = <(int, int, double)>[];
      for (var i = 0; i < live.length; i++) {
        final track = live[i];
        for (var j = 0; j < scan.measurements.length; j++) {
          final d2 = innovation(
            track.state,
            scan.measurements[j],
            p.sigma,
          ).distance;
          cost[i][j] = d2;
          if (d2 <= p.gate) {
            usable[i][j] = true;
            rowGates[i]++;
            columnGates[j]++;
            gates.add('${track.id}:${j + 1}=${fixed(d2)}');
            candidates.add((i, j, d2));
          }
        }
      }
      final cm = columnGates.where((count) => count >= 2).length,
          ct = rowGates.where((count) => count >= 2).length;
      conflictMeasurements += cm;
      conflictTracks += ct;
      final chosen = assignment(cost, usable, scan.measurements.length);
      candidates.sort((x, y) {
        var c = x.$3.compareTo(y.$3);
        if (c != 0) return c;
        c = x.$1.compareTo(y.$1);
        return c != 0 ? c : x.$2.compareTo(y.$2);
      });
      final greedy = List.filled(live.length, -1);
      var usedColumns = List.filled(scan.measurements.length, false);
      for (final (row, column, _) in candidates) {
        if (greedy[row] < 0 && !usedColumns[column]) {
          greedy[row] = column;
          usedColumns[column] = true;
        }
      }
      if (List.generate(
        chosen.length,
        (i) => chosen[i] != greedy[i],
      ).any((x) => x))
        greedyDifferences++;
      final assigned = <String>[],
          greedyPairs = <String>[],
          missed = <String>[],
          created = <String>[],
          confirmed = <String>[],
          deleted = <String>[];
      usedColumns = List.filled(scan.measurements.length, false);
      for (var i = 0; i < live.length; i++) {
        final track = live[i], j = chosen[i];
        if (j >= 0) {
          final z = scan.measurements[j];
          final (state, v, _) = update(track.state, z, p.sigma);
          track.state = state;
          track.nis.add(v.distance);
          track.hits++;
          track.misses = 0;
          track.lastHit = k;
          track.measurements.add(z);
          usedColumns[j] = true;
          assigned.add('${track.id}:${j + 1}');
        } else {
          track.misses++;
          track.measurements.add(null);
          missed.add('${track.id}');
        }
        if (greedy[i] >= 0) greedyPairs.add('${track.id}:${greedy[i] + 1}');
      }
      for (final track in live) {
        if (track.status == 'confirmed') {
          if (track.misses >= p.delete) {
            track.status = 'deleted';
            track.deletion = k;
            deleted.add('${track.id}');
          }
        } else {
          if (track.hits >= p.m) {
            track.status = 'confirmed';
            track.confirmation = k;
            confirmed.add('${track.id}');
          } else if (k - track.birth + 1 >= p.n) {
            track.status = 'deleted';
            track.deletion = k;
            deleted.add('${track.id}');
          }
        }
      }
      final processed = List<Track>.of(live);
      for (var j = 0; j < scan.measurements.length; j++) {
        if (usedColumns[j]) continue;
        final z = scan.measurements[j],
            track = Track(tracks.length + 1, k, initialize(p.model, z, p), z);
        tracks.add(track);
        processed.add(track);
        created.add('${track.id}:${j + 1}');
      }
      for (final track in processed) {
        final x = track.state.x;
        csv.add(
          '${track.id},${k + 1},${fixed(x[0])},${fixed(x[1])},${fixed(x[2])},${fixed(x[3])},${track.status}',
        );
      }
      final tentative = tracks.where((t) => t.status == 'tentative').length,
          activeConfirmed = tracks.where((t) => t.status == 'confirmed').length;
      log.addAll([
        'scan ${k + 1} tracks ${live.length} measurements ${scan.measurements.length}',
        listLine('gate', gates),
        listLine('assign', assigned),
        listLine('greedy', greedyPairs),
        listLine('missed', missed),
        listLine('new', created),
        listLine('confirmed', confirmed),
        listLine('deleted', deleted),
        'status tentative $tentative confirmed $activeConfirmed',
        'conflicts measurements $cm tracks $ct',
      ]);
    }
    writeLines('tracks.csv', csv);
    writeLines('association_log.txt', log);
  }

  (List<State>, List<State?>, List<Matrix?>, double) replay(
    Track track,
    List<Point?> sequence,
    String kind,
    double q,
  ) {
    var state = initialize(kind, sequence.first!, data.params);
    final states = [state],
        predicted = List<State?>.filled(sequence.length, null),
        fs = List<Matrix?>.filled(sequence.length, null);
    var logLikelihood = 0.0;
    for (var i = 1; i < sequence.length; i++) {
      final scan = track.birth + i,
          t = data.scans[scan].time - data.scans[scan - 1].time;
      final (next, f) = predict(state, kind, t, q);
      state = next;
      predicted[i] = state;
      fs[i] = f;
      final z = sequence[i];
      if (z != null) {
        final (updated, _, l) = update(state, z, data.params.sigma);
        state = updated;
        logLikelihood += l;
      }
      states.add(state);
    }
    return (states, predicted, fs, logLikelihood);
  }

  void filters() {
    final p = data.params, out = ['track,scan,x,y,vx,vy'];
    for (final track in tracks) {
      if (track.confirmation < 0) continue;
      final length = track.lastHit - track.birth + 1,
          sequence = track.measurements.sublist(0, length),
          e = Evaluated(track, sequence, data.scans.length);
      for (var f = 0; f < 2; f++) {
        final kind = f == 0 ? 'CV' : 'CA', q = f == 0 ? p.qcv : p.qca;
        final (states, predicted, fs, likelihood) = replay(
          track,
          sequence,
          kind,
          q,
        );
        e.likelihood[f] = likelihood;
        e.filters[f] = states.map((state) => state.x.sublist(0, 4)).toList();
        if (f == primary) {
          e.primary = states;
          e.filters[4] = smooth(states, predicted, fs);
        }
      }
      final first = sequence.first!,
          abg = [first.$1, first.$2, 0.0, 0.0, 0.0, 0.0],
          imm = IMM(first, p);
      e.filters[2].add(abg.sublist(0, 4));
      e.filters[3].add(imm.estimate());
      e.high.add(imm.mu[1]);
      for (var i = 1; i < length; i++) {
        final scan = track.birth + i,
            t = data.scans[scan].time - data.scans[scan - 1].time;
        for (var axis = 0; axis < 2; axis++) {
          final position = abg[axis],
              velocity = abg[axis + 2],
              acceleration = abg[axis + 4];
          abg[axis] = position + t * velocity + t * t * acceleration / 2;
          abg[axis + 2] = velocity + t * acceleration;
        }
        final z = sequence[i];
        if (z != null) {
          final coordinates = [z.$1, z.$2];
          for (var axis = 0; axis < 2; axis++) {
            final r = coordinates[axis] - abg[axis];
            abg[axis] = abg[axis] + p.abg[0] * r;
            abg[axis + 2] = abg[axis + 2] + p.abg[1] * r / t;
            abg[axis + 4] = abg[axis + 4] + 2 * p.abg[2] * r / (t * t);
          }
        }
        e.filters[2].add(abg.sublist(0, 4));
        imm.step(t, z, p);
        e.filters[3].add(imm.estimate());
        e.high.add(imm.mu[1]);
      }
      evaluated.add(e);
      for (var i = 0; i < e.filters[4].length; i++) {
        final x = e.filters[4][i];
        out.add(
          '${track.id},${track.birth + i + 1},${fixed(x[0])},${fixed(x[1])},${fixed(x[2])},${fixed(x[3])}',
        );
      }
    }
    writeLines('smoothed.csv', out);
  }

  void associations() {
    final s = data.scans.length, b = data.targets.length;
    ospaValues = zeros(s, 5);
    scanTracks = List.filled(s, 0);
    scanTargets = List.filled(s, 0);
    for (var f = 0; f < 5; f++) {
      labels[f].addAll(List.generate(b, (_) => List.filled(s, -1)));
    }
    for (var k = 0; k < s; k++) {
      final estimated = [
            for (var i = 0; i < evaluated.length; i++)
              if (evaluated[i].track.birth <= k &&
                  k <= evaluated[i].track.lastHit)
                i,
          ],
          truth = <int>[],
          y = <Point>[];
      for (var i = 0; i < b; i++) {
        final z = data.targets[i].positions[k];
        if (z != null) {
          truth.add(i);
          y.add(z);
        }
      }
      scanTracks[k] = estimated.length;
      scanTargets[k] = truth.length;
      for (var f = 0; f < 5; f++) {
        final x = <Point>[],
            cost = zeros(estimated.length, truth.length),
            usable = List.generate(
              estimated.length,
              (_) => List.filled(truth.length, false),
            );
        for (var i = 0; i < estimated.length; i++) {
          final e = evaluated[estimated[i]],
              position = pointOf(e.filters[f][k - e.track.birth]);
          x.add(position);
          for (var j = 0; j < y.length; j++) {
            cost[i][j] = distance(position, y[j]);
            usable[i][j] = cost[i][j] <= data.params.match;
          }
        }
        final chosen = assignment(cost, usable, truth.length);
        for (var i = 0; i < chosen.length; i++) {
          final j = chosen[i];
          if (j >= 0) {
            final ei = estimated[i], ti = truth[j];
            labels[f][ti][k] = ei;
            if (f == primary) {
              evaluated[ei].matchedScans++;
              evaluated[ei].scanTargets[k] = ti;
            }
          }
        }
        ospaValues[k][f] = ospa(x, y, data.params.cutoff);
      }
    }
    for (final e in evaluated) {
      for (var k = e.track.birth; k <= e.track.lastHit;) {
        final target = e.scanTargets[k];
        if (target < 0) {
          k++;
          continue;
        }
        var end = k;
        while (end + 1 <= e.track.lastHit && e.scanTargets[end + 1] == target) {
          end++;
        }
        e.segments.add(Segment(k, end, target));
        k = end + 1;
      }
    }
    final cost = zeros(evaluated.length, b),
        usable = List.generate(evaluated.length, (_) => List.filled(b, false));
    for (var i = 0; i < evaluated.length; i++) {
      final e = evaluated[i];
      for (var j = 0; j < b; j++) {
        final target = data.targets[j],
            first = max(e.track.birth, target.first),
            last = min(e.track.lastHit, target.last);
        if (first > last) continue;
        var total = 0.0;
        for (
          var k = min(e.track.birth, target.first);
          k <= max(e.track.lastHit, target.last);
          k++
        ) {
          var d = data.params.cutoff;
          if (k >= first && k <= last) {
            d = distance(
              pointOf(e.filters[primary][k - e.track.birth]),
              target.positions[k]!,
            );
            if (d < data.params.cutoff) usable[i][j] = true;
            d = min(d, data.params.cutoff);
          }
          total += d;
        }
        final count =
            max(e.track.lastHit, target.last) -
            min(e.track.birth, target.first) +
            1;
        cost[i][j] = total / count;
      }
    }
    final chosen = assignment(cost, usable, b);
    targetTracks = List.filled(b, -1);
    for (var i = 0; i < chosen.length; i++) {
      final j = chosen[i];
      if (j >= 0) {
        final e = evaluated[i], target = data.targets[j];
        e.matchedTarget = j;
        e.meanDistance = cost[i][j];
        e.common =
            min(e.track.lastHit, target.last) -
            max(e.track.birth, target.first) +
            1;
        targetTracks[j] = i;
      }
    }
  }

  String segmentText(Evaluated e) => e.segments.isEmpty
      ? 'none'
      : e.segments
            .map(
              (s) =>
                  '${s.first + 1}-${s.last + 1}:${data.targets[s.target].id}',
            )
            .join(' ');
  void evaluationOutput() {
    final d = data,
        p = data.params,
        s = data.scans.length,
        falseTracks = evaluated.where((e) => e.matchedScans == 0).length,
        lost = targetTracks.where((t) => t < 0).length,
        used = evaluated.fold(0, (n, e) => n + e.track.hits),
        parts = <List<String>>[
          [
            'summary',
            'scans $s',
            'measurements ${d.measurements}',
            'targets ${d.targets.length}',
            'tracks_created ${tracks.length}',
            'tracks_confirmed ${evaluated.length}',
            'false_tracks $falseTracks',
            'missed_targets $lost',
            'measurements_used $used',
            'conflict_measurements $conflictMeasurements',
            'conflict_tracks $conflictTracks',
            'greedy_differences $greedyDifferences',
          ],
        ];
    final targetLines = ['targets'];
    for (final target in d.targets) {
      var length = 0.0;
      for (var k = target.first + 1; k <= target.last; k++) {
        length += distance(target.positions[k - 1]!, target.positions[k]!);
      }
      final speed =
          length / (d.scans[target.last].time - d.scans[target.first].time);
      targetLines.add(
        'target ${target.id} first ${target.first + 1} last ${target.last + 1} scans ${target.last - target.first + 1} path ${fixed(length)} mean_speed ${fixed(speed)}',
      );
    }
    parts.add(targetLines);
    final trackLines = ['tracks'],
        matching = ['matching'],
        models = ['models'],
        allNIS = <double>[];
    for (final e in evaluated) {
      final track = e.track;
      var hits = 0, gap = 0, longest = 0;
      for (final z in e.sequence) {
        if (z != null) {
          hits++;
          gap = 0;
        } else {
          gap++;
          longest = max(longest, gap);
        }
      }
      var length = 0.0;
      for (var i = 1; i < e.sequence.length; i++) {
        length += distance(
          pointOf(e.filters[4][i - 1]),
          pointOf(e.filters[4][i]),
        );
      }
      final inside = track.nis.where((v) => v <= p.bound).length;
      allNIS.addAll(track.nis);
      trackLines.add(
        'track ${track.id} birth ${track.birth + 1} confirmed ${track.confirmation + 1} end ${track.lastHit + 1} deleted ${optionalScan(track.deletion)} hits $hits misses ${e.sequence.length - hits} longest_gap $longest path ${fixed(length)} nis ${fixed(sum(track.nis) / track.nis.length)} nis_inside $inside/${track.nis.length}',
      );
      final prefix = e.matchedTarget >= 0
          ? 'track ${track.id} target ${d.targets[e.matchedTarget].id} common ${e.common} mean_distance ${fixed(e.meanDistance)}'
          : 'track ${track.id} target -';
      matching.add(
        '$prefix matched_scans ${e.matchedScans} segments ${segmentText(e)}',
      );
      final better = e.likelihood[1] > e.likelihood[0] ? 'ca' : 'cv';
      models.add(
        'track ${track.id} updates ${track.nis.length} cv ${fixed(e.likelihood[0])} ca ${fixed(e.likelihood[1])} better $better',
      );
    }
    parts.addAll([trackLines, matching]);
    final rmseLines = ['rmse'],
        consistency = ['consistency'],
        overallP = List.filled(5, 0.0),
        overallV = List.filled(5, 0.0);
    var positionCount = 0, velocityCount = 0;
    for (var ti = 0; ti < d.targets.length; ti++) {
      final target = d.targets[ti], index = targetTracks[ti];
      if (index < 0) {
        rmseLines.add('target ${target.id} track -');
        consistency.add('target ${target.id} track -');
        continue;
      }
      final e = evaluated[index],
          position = List.filled(5, 0.0),
          velocity = List.filled(5, 0.0),
          first = max(target.first, e.track.birth),
          last = min(target.last, e.track.lastHit);
      var count = 0, velCount = 0, inside = 0, nees = 0.0;
      for (var k = first; k <= last; k++) {
        final i = k - e.track.birth,
            truth = target.positions[k]!,
            previous = target.positions[k - 1],
            next = target.positions[k + 1];
        count++;
        positionCount++;
        Point? trueVelocity = null;
        if (previous != null && next != null) {
          final dt = d.scans[k + 1].time - d.scans[k - 1].time;
          trueVelocity = (
            (next.$1 - previous.$1) / dt,
            (next.$2 - previous.$2) / dt,
          );
          velCount++;
          velocityCount++;
        }
        for (var f = 0; f < 5; f++) {
          final x = e.filters[f][i],
              ex = x[0] - truth.$1,
              ey = x[1] - truth.$2,
              error = ex * ex + ey * ey;
          position[f] += error;
          overallP[f] += error;
          if (trueVelocity != null) {
            final vx = x[2] - trueVelocity.$1,
                vy = x[3] - trueVelocity.$2,
                error = vx * vx + vy * vy;
            velocity[f] += error;
            overallV[f] += error;
          }
        }
        final x = e.filters[primary][i],
            v = [x[0] - truth.$1, x[1] - truth.$2],
            value = quadratic(v, inverse(positionCovariance(e.primary[i].p)));
        nees += value;
        if (value <= p.bound) inside++;
      }
      for (var f = 0; f < 5; f++) {
        position[f] = sqrt(position[f] / count);
        velocity[f] = sqrt(velocity[f] / velCount);
      }
      rmseLines.addAll([
        'target ${target.id} track ${e.track.id} common $count ${filterValues(position)} best ${bestFilter(position)}',
        'target ${target.id} velocity $velCount ${filterValues(velocity)} best ${bestFilter(velocity)}',
      ]);
      consistency.add(
        'target ${target.id} track ${e.track.id} nees ${fixed(nees / count)} inside $inside/$count',
      );
    }
    for (var f = 0; f < 5; f++) {
      overallP[f] = sqrt(overallP[f] / positionCount);
      overallV[f] = sqrt(overallV[f] / velocityCount);
    }
    rmseLines.addAll([
      'overall position ${filterValues(overallP)} best ${bestFilter(overallP)}',
      'overall velocity ${filterValues(overallV)} best ${bestFilter(overallV)}',
    ]);
    parts.add(rmseLines);
    final histogram = List.filled(p.edges.length + 1, 0);
    for (final v in allNIS) {
      var bin = 0;
      while (bin < p.edges.length && v >= p.edges[bin]) {
        bin++;
      }
      histogram[bin]++;
    }
    final histLine = [
      'nis_histogram total ${allNIS.length} observed',
      ...histogram.map((v) => '$v'),
      'expected',
    ];
    var lower = 0.0;
    for (var bin = 0; bin < histogram.length; bin++) {
      final upperTerm = bin < p.edges.length ? exp(-p.edges[bin] / 2) : 0.0,
          expected = allNIS.length * (exp(-lower / 2) - upperTerm);
      histLine.add(fixed(expected));
      if (bin < p.edges.length) lower = p.edges[bin];
    }
    consistency.add(histLine.join(' '));
    parts.addAll([consistency, models]);
    final ospaLines = [
          'ospa cutoff ${fixed(p.cutoff)} order 2',
          'scan targets tracks cv ca abg imm rts',
        ],
        mean = List.filled(5, 0.0);
    for (var k = 0; k < ospaValues.length; k++) {
      final row = ospaValues[k];
      ospaLines.add(
        '${k + 1} ${scanTargets[k]} ${scanTracks[k]} ${row.map(fixed).join(' ')}',
      );
      for (var f = 0; f < 5; f++) {
        mean[f] += row[f];
      }
    }
    ospaLines.add('mean ${mean.map((v) => fixed(v / s)).join(' ')}');
    parts.add(ospaLines);
    final continuityLines = ['continuity'];
    for (var f = 0; f < 5; f++) {
      final rows = <String>[];
      var covered = 0, breaks = 0, swaps = 0;
      for (var j = 0; j < d.targets.length; j++) {
        final target = d.targets[j],
            c = continuity(labels[f][j].sublist(target.first, target.last + 1));
        covered += c.covered;
        breaks += c.breaks;
        swaps += c.swaps;
        rows.add(
          '  target ${target.id} scans ${target.last - target.first + 1} covered ${c.covered} breaks ${c.breaks} swaps ${c.swaps} delay ${c.delay < 0 ? '-' : c.delay}',
        );
      }
      continuityLines.add(
        '${filterNames[f]} covered $covered breaks $breaks swaps $swaps',
      );
      continuityLines.addAll(rows);
    }
    parts.add(continuityLines);
    final immLines = ['imm'];
    for (final e in evaluated) {
      var maximum = 0, high = 0;
      final segments = <String>[];
      for (var i = 0; i < e.high.length;) {
        if (e.high[i] > e.high[maximum]) maximum = i;
        if (e.high[i] <= .5) {
          i++;
          continue;
        }
        final start = i;
        var end = i;
        while (end + 1 < e.high.length && e.high[end + 1] > .5) {
          end++;
          if (e.high[end] > e.high[maximum]) maximum = end;
        }
        high += end - start + 1;
        segments.add('${e.track.birth + start + 1}-${e.track.birth + end + 1}');
        i = end + 1;
      }
      immLines.add(
        'track ${e.track.id} mean_high ${fixed(sum(e.high) / e.high.length)} max_high ${fixed(e.high[maximum])} at ${e.track.birth + maximum + 1} high_scans $high segments ${segments.isEmpty ? 'none' : segments.join(' ')}',
      );
    }
    parts.add(immLines);
    final out = <String>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) out.add('');
      out.addAll(parts[i]);
    }
    writeLines('evaluation.txt', out);
  }

  void plots() {
    final p = data.params,
        dx = (p.xMax - p.xMin) / p.w,
        dy = (p.yMax - p.yMin) / p.h;
    (int, int, bool) position(Point point) {
      final c = ((point.$1 - p.xMin) / dx).floor(),
          r = ((p.yMax - point.$2) / dy).floor();
      return (r, c, r >= 0 && r < p.h && c >= 0 && c < p.w);
    }

    final trajectory = List.generate(p.h, (_) => List.filled(p.w, ' ')),
        measurementCounts = List.generate(p.h, (_) => List.filled(p.w, 0)),
        measurements = List.generate(p.h, (_) => List.filled(p.w, ' '));
    for (final target in data.targets) {
      for (var k = target.first; k <= target.last; k++) {
        final (r, c, inside) = position(target.positions[k]!);
        if (inside) trajectory[r][c] = '.';
      }
    }
    for (var i = 0; i < evaluated.length; i++) {
      for (final x in evaluated[i].filters[4]) {
        final (r, c, inside) = position(pointOf(x));
        if (inside) trajectory[r][c] = trackCharacter(i);
      }
    }
    for (final scan in data.scans) {
      for (final z in scan.measurements) {
        final (r, c, inside) = position(z);
        if (inside) measurementCounts[r][c]++;
      }
    }
    for (var r = 0; r < p.h; r++) {
      for (var c = 0; c < p.w; c++) {
        final count = measurementCounts[r][c];
        if (count >= 10) {
          measurements[r][c] = '#';
        } else if (count > 0) {
          measurements[r][c] = '$count';
        }
      }
    }
    final out = [
      'tracks x ${fixed(p.xMin)} ${fixed(p.xMax)} y ${fixed(p.yMin)} ${fixed(p.yMax)} size ${p.w} ${p.h}',
      ...frame(trajectory),
    ];
    for (var i = 0; i < evaluated.length; i++) {
      final e = evaluated[i];
      out.add(
        '${trackCharacter(i)} track ${e.track.id} target ${e.matchedTarget < 0 ? '-' : data.targets[e.matchedTarget].id}',
      );
    }
    out.addAll(['', 'measurements', ...frame(measurements), '', 'timeline']);
    final s = data.scans.length;
    for (var j = 0; j < data.targets.length; j++) {
      final target = data.targets[j], row = List.filled(s, ' ');
      for (var k = target.first; k <= target.last; k++) {
        final label = labels[primary][j][k];
        row[k] = label >= 0 ? trackCharacter(label) : '.';
      }
      out.add('${target.id} |${row.join()}|');
    }
    out.addAll(['', 'ospa ${filterNames[primary]}']);
    final grid = List.generate(10, (_) => List.filled(s, ' '));
    for (var r = 0; r < 10; r++) {
      for (var k = 0; k < s; k++) {
        final height = (10 * ospaValues[k][primary] / p.cutoff).floor();
        if (height >= 10 - r) grid[r][k] = '#';
      }
    }
    out.addAll(frame(grid));
    writeLines('track_plot.txt', out);
  }
}

String trackCharacter(int index) =>
    String.fromCharCode(index < 26 ? 65 + index : 97 + index - 26);
List<String> frame(List<List<String>> grid) => [
  '+${'-' * grid.first.length}+',
  ...grid.map((row) => '|${row.join()}|'),
  '+${'-' * grid.first.length}+',
];
void main() {
  final a = Application(readData());
  a.tracking();
  a.filters();
  a.associations();
  a.evaluationOutput();
  a.plots();
}
