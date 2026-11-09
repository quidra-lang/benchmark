import 'dart:io';
import 'dart:math';
part 'mesh.dart';
part 'materials.dart';
part 'transient.dart';
part 'steady.dart';
part 'report.dart';

class Segment {
  final String name, edge, kind;
  final List<int> cells;
  final int face;
  final double h, theta;
  Segment(
    this.name,
    this.edge,
    this.kind,
    this.cells,
    this.face, [
    this.h = 0,
    this.theta = 0,
  ]);
}

class Source {
  final String name;
  final List<int> cells;
  final double power, duty;
  final List<(int, int)> periods;
  Source(this.name, this.cells, this.power, this.duty, this.periods);
}

class Probe {
  final String name;
  final int cell;
  Probe(this.name, this.cell);
}

class RunConfig {
  final String name, method;
  final int d;
  RunConfig(this.name, this.method, this.d);
}

class Params {
  double initial = 0, tolerance = 0, omega = 0, alarm = 0, limit = 0;
  int end = 0, probeEvery = 0, maxIterations = 0;
  final snapshots = <int>[],
      probes = <Probe>[],
      runs = <RunConfig>[],
      bands = <double>[];
  String reference = '';
}

class Snapshot {
  final List<double> field;
  final double u, b, q;
  Snapshot(this.field, this.u, this.b, this.q);
}

class ProbeRecord {
  final int time;
  final List<double> values;
  ProbeRecord(this.time, this.values);
}

class Run {
  final RunConfig config;
  String reason = '';
  final snapshots = <int, Snapshot>{}, probes = <ProbeRecord>[];
  List<double> finalField = [];
  final List<double> boundary;
  double source = 0, storedEnergy = 0, peak = 0;
  int peakTime = 0, peakCell = 0, alarmTime = -1, alarmCell = 0, above = 0;
  Run(this.config, int segments) : boundary = List.filled(segments, 0);
}

double sum(List<double> a) {
  var s = 0.0;
  for (final v in a) {
    s += v;
  }
  return s;
}

int hottest(List<double> x) {
  var p = 0;
  for (var i = 1; i < x.length; i++) {
    if (x[i] > x[p]) p = i;
  }
  return p;
}

double minimum(List<double> x) {
  var v = x.first;
  for (final a in x.skip(1)) {
    v = min(v, a);
  }
  return v;
}

double maxDifference(List<double> a, List<double> b) {
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    m = max(m, (a[i] - b[i]).abs());
  }
  return m;
}

String verdict(bool b) => b ? 'ok' : 'failed';
String yes(bool b) => b ? 'yes' : 'no';
Params readParams(Mesh mesh) {
  final p = Params();
  for (final line in readLines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'initial':
        p.initial = double.parse(a[1]);
      case 'end_time':
        p.end = int.parse(a[1]);
      case 'snapshots':
        p.snapshots.addAll(a.sublist(1).map(int.parse));
      case 'probe_every':
        p.probeEvery = int.parse(a[1]);
      case 'probe':
        p.probes.add(Probe(a[1], int.parse(a[2]) * mesh.w + int.parse(a[3])));
      case 'run':
        p.runs.add(RunConfig(a[1], a[2], int.parse(a[3])));
      case 'reference':
        p.reference = a[1];
      case 'tolerance':
        p.tolerance = double.parse(a[1]);
      case 'max_iterations':
        p.maxIterations = int.parse(a[1]);
      case 'omega':
        p.omega = double.parse(a[1]);
      case 'bands':
        p.bands.addAll(a.sublist(1).map(double.parse));
      case 'alarm':
        p.alarm = double.parse(a[1]);
      case 'limit':
        p.limit = double.parse(a[1]);
    }
  }
  return p;
}

(List<Segment>, List<Source>) readBoundary(Mesh mesh, int end) {
  final segments = <Segment>[], sources = <Source>[];
  for (final line in readLines('input/boundary.txt')) {
    final a = line.split(' ');
    if (a[0] == 'segment') {
      final (cells, face) = mesh.segmentCells(
        a[2],
        int.parse(a[3]),
        int.parse(a[4]),
      );
      final kind = a[5],
          h = kind == 'convective' ? double.parse(a[6]) : 0.0,
          theta = kind == 'fixed'
              ? double.parse(a[6])
              : kind == 'convective'
              ? double.parse(a[7])
              : 0.0;
      segments.add(Segment(a[1], a[2], kind, cells, face, h, theta));
    } else {
      final periods = <(int, int)>[];
      var active = 0;
      for (var i = 7; i < a.length; i += 2) {
        final on = int.parse(a[i]), off = int.parse(a[i + 1]);
        periods.add((on, off));
        active += min(off, end) - min(on, end);
      }
      sources.add(
        Source(
          a[1],
          mesh.sourceCells(
            int.parse(a[2]),
            int.parse(a[3]),
            int.parse(a[4]),
            int.parse(a[5]),
          ),
          double.parse(a[6]),
          active / end,
          periods,
        ),
      );
    }
  }
  return (segments, sources);
}

Plate buildPlate(
  Mesh mesh,
  List<Material> materials,
  List<int> index,
  List<Segment> segments,
  List<Source> sources,
) {
  final plate = Plate(mesh, materials, index);
  for (var p = 0; p < mesh.codes.length; p++) {
    final m = materials[index[p]];
    plate.c[p] = capacity(m, mesh);
    for (final face in plate.faces[p]) {
      if (face.neighbor >= 0)
        face.g = interiorConductance(
          m.k,
          materials[index[face.neighbor]].k,
          mesh.thickness,
        );
    }
  }
  for (final s in segments) {
    for (final p in s.cells) {
      final f = plate.faces[p][s.face], k = materials[index[p]].k;
      if (s.kind == 'fixed' || s.kind == 'convective') {
        f.g = s.kind == 'fixed'
            ? fixedConductance(k, mesh.thickness)
            : convectiveConductance(k, s.h, mesh);
        f.theta = s.theta;
        f.boundary = true;
      }
    }
  }
  for (var p = 0; p < plate.c.length; p++) {
    for (final f in plate.faces[p]) {
      plate.a[p] += f.g;
      if (f.boundary) plate.beta[p] += f.g * f.theta;
    }
  }
  for (final s in sources) {
    final w = s.power / s.cells.length;
    for (final p in s.cells) {
      plate.sall[p] += w;
    }
  }
  return plate;
}

(List<double>, double) sourceAt(List<Source> sources, int n, int time) {
  final out = List.filled(n, 0.0);
  var power = 0.0;
  for (final s in sources) {
    if (s.periods.any((p) => p.$1 <= time && time < p.$2)) {
      power += s.power;
      final w = s.power / s.cells.length;
      for (final p in s.cells) {
        out[p] += w;
      }
    }
  }
  return (out, power);
}

double stored(Plate plate, List<double> x, double initial) {
  var s = 0.0;
  for (var p = 0; p < x.length; p++) {
    s += plate.c[p] * (x[p] - initial);
  }
  return s;
}

Run runTransient(
  Plate plate,
  Params params,
  RunConfig config,
  List<Segment> segments,
  List<Source> sources,
  double dtMax,
) {
  final out = Run(config, segments.length),
      times = [
        params.end,
        params.probeEvery,
        ...params.snapshots,
        for (final source in sources)
          for (final period in source.periods) ...[period.$1, period.$2],
      ];
  if (times.any((t) => t % config.d != 0)) {
    out.reason = 'step';
    return out;
  }
  final dt = config.d / 1000;
  if (config.method == 'ftcs' && dt > dtMax) {
    out.reason = 'unstable';
    return out;
  }
  var x = List.filled(plate.c.length, params.initial);
  void observe(int time) {
    final hot = hottest(x);
    if (time == 0 || x[hot] > out.peak) {
      out.peak = x[hot];
      out.peakTime = time;
      out.peakCell = hot;
    }
    if (x[hot] >= params.alarm) {
      if (out.alarmTime < 0) {
        out.alarmTime = time;
        out.alarmCell = hot;
      }
      if (time > 0) out.above += config.d;
    }
    if (time % params.probeEvery == 0)
      out.probes.add(
        ProbeRecord(time, [for (final p in params.probes) x[p.cell]]),
      );
    if (params.snapshots.contains(time))
      out.snapshots[time] = Snapshot(
        List.of(x),
        stored(plate, x, params.initial),
        sum(out.boundary),
        out.source,
      );
  }

  observe(0);
  for (var time = 0; time < params.end; time += config.d) {
    final (source, power) = sourceAt(sources, x.length, time);
    final (next, y) = step(plate, x, source, dt, config.method);
    for (var j = 0; j < segments.length; j++) {
      final segment = segments[j];
      if (segment.kind == 'insulated') continue;
      var s = 0.0;
      for (final p in segment.cells) {
        var temperature = x[p];
        if (config.method != 'ftcs') {
          temperature = segment.face < 2
              ? y![p]
              : config.method == 'backward_euler'
              ? next[p]
              : (x[p] + next[p]) / 2;
        }
        final f = plate.faces[p][segment.face];
        s += f.g * (f.theta - temperature);
      }
      out.boundary[j] += dt * s;
    }
    out.source += dt * power;
    x = next;
    observe(time + config.d);
  }
  out.finalField = x;
  out.storedEnergy = stored(plate, x, params.initial);
  return out;
}

String summary(Mesh mesh, List<double> x) {
  final hot = hottest(x);
  return 'max ${fixed(x[hot], 2)} at ${cell(mesh, hot)} min ${fixed(minimum(x), 2)} mean ${fixed(sum(x) / x.length, 2)}';
}

String runPrefix(RunConfig c) =>
    'run ${c.name} ${c.method} dt ${timeText(c.d)}';
void snapshotsOutput(Plate plate, Params params, List<Run> runs, double dtMax) {
  final out = <String>[], probes = ['run,time,probe,temperature'];
  for (final run in runs) {
    final prefix = runPrefix(run.config);
    if (run.reason.isNotEmpty) {
      out.add(
        '$prefix rejected ${run.reason}${run.reason == 'unstable' ? ' max_dt ${fixed(dtMax, 4)}' : ''}',
      );
      continue;
    }
    for (final time in params.snapshots) {
      final x = run.snapshots[time]!.field;
      out.add('$prefix time ${timeText(time)} ${summary(plate.mesh, x)}');
      out.addAll(fieldLines(plate.mesh, x));
    }
    for (final record in run.probes) {
      for (var i = 0; i < params.probes.length; i++) {
        probes.add(
          '${run.config.name},${timeText(record.time)},${params.probes[i].name},${fixed(record.values[i], 3)}',
        );
      }
    }
  }
  writeLines('snapshots.txt', out);
  writeLines('probes.csv', probes);
}

(double, double, double) selectedStats(List<double> x, List<int> cells) {
  var lo = x[cells.first], hi = lo, total = 0.0;
  for (final p in cells) {
    lo = min(lo, x[p]);
    hi = max(hi, x[p]);
    total += x[p];
  }
  return (lo, hi, total / cells.length);
}

String solverLine(Solver s) {
  final prefix =
          'solver ${s.name}${s.name == 'sor' || s.name == 'sor_estimated' ? ' omega ${fixed(s.omega, 4)}' : ''}',
      milestones = s.milestones.map((k) => k == 0 ? 'never' : '$k').join(' ');
  return '$prefix iterations ${s.deltas.length} converged ${yes(s.converged)} rate ${fixed(s.rate, 6)} milestones $milestones';
}

class InterfaceFlow {
  int count = 0;
  double forward = 0, backward = 0;
}

void steadyOutput(
  Plate plate,
  Params params,
  List<Segment> segments,
  List<Source> sources,
  List<List<double>> solution,
  List<Solver> solvers,
) {
  final mesh = plate.mesh,
      steady = solution[0],
      base = solution[1],
      units = solution.sublist(2),
      out = [
        'steady ${summary(mesh, solution[0])}',
        ...fieldLines(mesh, solution[0]),
      ];
  for (final material in plate.materials) {
    final (lo, hi, mean) = selectedStats(steady, material.cells);
    out.add(
      'material ${material.code} ${material.name} cells ${material.cells.length} min ${fixed(lo, 2)} max ${fixed(hi, 2)} mean ${fixed(mean, 2)}',
    );
  }
  for (final source in sources) {
    final (_, hi, mean) = selectedStats(steady, source.cells);
    out.add(
      'source ${source.name} power ${fixed(source.power, 4)} duty ${fixed(source.duty, 4)} mean ${fixed(mean, 2)} max ${fixed(hi, 2)}',
    );
  }
  for (final s in sources) {
    for (var j = 0; j < sources.length; j++) {
      var total = 0.0;
      for (final p in s.cells) {
        total += units[j][p];
      }
      out.add(
        'influence ${s.name} ${sources[j].name} ${fixed(total / s.cells.length, 4)}',
      );
    }
  }
  final superposed = List<double>.of(base), duty = List<double>.of(base);
  for (var p = 0; p < steady.length; p++) {
    for (var j = 0; j < sources.length; j++) {
      final source = sources[j];
      superposed[p] += source.power * units[j][p];
      duty[p] += (source.duty * source.power) * units[j][p];
    }
  }
  out.add(
    'superposition ${verdict(maxDifference(superposed, steady) <= .000001)}',
  );
  for (var j = 0; j < sources.length; j++) {
    for (final segment in segments) {
      var escape = 0.0;
      if (segment.kind != 'insulated') {
        for (final p in segment.cells) {
          escape += plate.faces[p][segment.face].g * units[j][p];
        }
      }
      out.add('path ${sources[j].name} ${segment.name} ${fixed(escape, 4)}');
    }
  }
  out.add('duty_steady ${summary(mesh, duty)}');
  for (var j = 0; j < sources.length; j++) {
    final source = sources[j];
    var best = 0, power = 0.0;
    for (var p = 0; p < steady.length; p++) {
      final v =
          (params.limit - (steady[p] - source.power * units[j][p])) /
          units[j][p];
      if (p == 0 || v < power) {
        best = p;
        power = v;
      }
    }
    out.add(
      'headroom ${source.name} max_power ${fixed(power, 4)} at ${cell(mesh, best)}',
    );
  }
  final interfaces = <(int, int), InterfaceFlow>{};
  var gradient = 0.0, gp = 0, gq = -1;
  for (var p = 0; p < steady.length; p++) {
    for (final face in [1, 3]) {
      final f = plate.faces[p][face], q = f.neighbor;
      if (q < 0) continue;
      final g = (steady[p] - steady[q]).abs() / mesh.dx;
      if (gq < 0 || g > gradient) {
        gradient = g;
        gp = p;
        gq = q;
      }
      var a = plate.materialIndex[p], b = plate.materialIndex[q];
      if (a == b) continue;
      var phi = f.g * (steady[p] - steady[q]);
      if (a > b) {
        final temp = a;
        a = b;
        b = temp;
        phi = -phi;
      }
      final flow = interfaces.putIfAbsent((a, b), InterfaceFlow.new);
      flow.count++;
      if (phi > 0) {
        flow.forward += phi;
      } else if (phi < 0) {
        flow.backward += -phi;
      }
    }
  }
  for (var a = 0; a < plate.materials.length; a++) {
    for (var b = a + 1; b < plate.materials.length; b++) {
      final flow = interfaces[(a, b)];
      if (flow != null)
        out.add(
          'interface ${plate.materials[a].code} ${plate.materials[b].code} faces ${flow.count} forward ${fixed(flow.forward, 4)} backward ${fixed(flow.backward, 4)}',
        );
    }
  }
  var boundaryFlows = 0.0, absoluteFlows = 0.0;
  for (final segment in segments) {
    var flow = 0.0;
    if (segment.kind != 'insulated') {
      for (final p in segment.cells) {
        final f = plate.faces[p][segment.face];
        flow += f.g * (f.theta - steady[p]);
      }
    }
    boundaryFlows += flow;
    absoluteFlows += flow.abs();
    out.add(
      'segment ${segment.name} ${segment.edge} ${segment.kind} flow ${fixed(flow, 4)}',
    );
  }
  var totalPower = 0.0;
  for (final source in sources) {
    totalPower += source.power;
  }
  out.addAll([
    'sources ${fixed(totalPower, 4)}',
    'balance ${verdict((boundaryFlows + totalPower).abs() <= .000001 * (absoluteFlows + totalPower))}',
    'max_gradient ${fixed(gradient, 2)} between ${cell(mesh, gp)} and ${cell(mesh, gq)}',
  ]);
  out.addAll(solvers.map(solverLine));
  writeLines('steady_state.txt', out);
}

void comparisonOutput(
  Plate plate,
  Params params,
  List<Segment> segments,
  List<Run> runs,
  Run reference,
  List<double> steady,
  List<double> b,
  List<Solver> solvers,
  double dtMax,
  double rho,
  double omega,
) {
  final out = ['ftcs_max_dt ${fixed(dtMax, 4)}'];
  for (final run in runs) {
    final prefix = runPrefix(run.config), name = run.config.name;
    if (run.reason.isNotEmpty) {
      out.add('$prefix rejected ${run.reason}');
      continue;
    }
    final alarm = run.alarmTime < 0
        ? 'never'
        : '${timeText(run.alarmTime)} at ${cell(plate.mesh, run.alarmCell)}';
    out.add(
      '$prefix steps ${params.end ~/ run.config.d} peak ${fixed(run.peak, 2)} time ${timeText(run.peakTime)} at ${cell(plate.mesh, run.peakCell)} alarm $alarm above ${timeText(run.above)}',
    );
    final boundary = sum(run.boundary),
        balance =
            (run.storedEnergy - boundary - run.source).abs() <=
            .000001 *
                (run.storedEnergy.abs() + boundary.abs() + run.source.abs());
    out.add(
      'energy $name stored ${fixed(run.storedEnergy, 2)} boundary ${fixed(boundary, 2)} source ${fixed(run.source, 2)} balance ${verdict(balance)}',
    );
    for (final time in params.snapshots) {
      final snap = run.snapshots[time]!;
      out.add(
        'energy_at $name time ${timeText(time)} stored ${fixed(snap.u, 2)} boundary ${fixed(snap.b, 2)} source ${fixed(snap.q, 2)}',
      );
    }
    for (final material in plate.materials) {
      var energy = 0.0;
      for (final p in material.cells) {
        energy += plate.c[p] * (run.finalField[p] - params.initial);
      }
      out.add('energy_material $name ${material.code} ${fixed(energy, 2)}');
    }
    for (var j = 0; j < segments.length; j++) {
      out.add(
        'energy_segment $name ${segments[j].name} ${fixed(run.boundary[j], 2)}',
      );
    }
    for (var j = 0; j < params.probes.length; j++) {
      var hi = run.probes.first.values[j],
          lo = hi,
          maxTime = run.probes.first.time,
          minTime = maxTime;
      for (final record in run.probes.skip(1)) {
        final v = record.values[j];
        if (v > hi) {
          hi = v;
          maxTime = record.time;
        }
        if (v < lo) {
          lo = v;
          minTime = record.time;
        }
      }
      out.add(
        'probe_summary $name ${params.probes[j].name} max ${fixed(hi, 3)} time ${timeText(maxTime)} min ${fixed(lo, 3)} time ${timeText(minTime)}',
      );
    }
    if (name != params.reference) {
      for (final time in params.snapshots) {
        final x = run.snapshots[time]!.field,
            z = reference.snapshots[time]!.field;
        var squared = 0.0;
        for (var p = 0; p < x.length; p++) {
          final e = (x[p] - z[p]).abs();
          squared += e * e;
        }
        out.add(
          'compare $name ${params.reference} time ${timeText(time)} max_diff ${fixed(maxDifference(x, z), 6)} rms_diff ${fixed(sqrt(squared / x.length), 6)}',
        );
      }
    }
    out.add(
      'final $name steady_max_diff ${fixed(maxDifference(run.finalField, steady), 6)}',
    );
  }
  out.add('steady direct max_residual ${fixed(residual(plate, steady, b), 6)}');
  for (final s in solvers) {
    out.add(
      'steady ${s.name} iterations ${s.deltas.length} max_diff ${fixed(s.error, 6)} max_residual ${fixed(s.residual, 6)}',
    );
  }
  out.addAll([
    'jacobi_spectral_radius ${fixed(rho, 6)} squared ${fixed(rho * rho, 6)}',
    'omega_estimated ${fixed(omega, 4)}',
  ]);
  writeLines('solver_comparison.txt', out);
}

void isothermsOutput(
  Plate plate,
  Params params,
  List<double> steady,
  Run reference,
) {
  final out = <String>[];
  void appendMap(String label, List<double> x) {
    final (lines, counts) = isotherm(plate.mesh, x, params.bands);
    out.add('$label counts ${counts.join(' ')}');
    out.addAll(lines);
  }

  appendMap('isotherms steady', steady);
  for (final time in params.snapshots) {
    appendMap(
      'isotherms ${params.reference} time ${timeText(time)}',
      reference.snapshots[time]!.field,
    );
  }
  writeLines('isotherms.txt', out);
}

void main() {
  final mesh = readMesh();
  final (materials, index) = readMaterials(mesh);
  final params = readParams(mesh);
  final (segments, sources) = readBoundary(mesh, params.end);
  final plate = buildPlate(mesh, materials, index, segments, sources);
  var dtMax = plate.c[0] / plate.a[0];
  for (var p = 0; p < plate.c.length; p++) {
    dtMax = min(dtMax, plate.c[p] / plate.a[p]);
  }
  final b = List.generate(plate.c.length, (p) => plate.beta[p] + plate.sall[p]),
      right = [b, plate.beta];
  for (final source in sources) {
    final unit = List.filled(b.length, 0.0);
    for (final p in source.cells) {
      unit[p] = 1 / source.cells.length;
    }
    right.add(unit);
  }
  final solutions = direct(plate, right),
      jacobi = iterate(
        plate,
        'jacobi',
        1,
        params.initial,
        params.tolerance,
        params.maxIterations,
      ),
      rho = jacobi.rate,
      omega = 2 / (1 + sqrt(1 - rho * rho)),
      solvers = [
        jacobi,
        iterate(
          plate,
          'gauss_seidel',
          1,
          params.initial,
          params.tolerance,
          params.maxIterations,
        ),
        iterate(
          plate,
          'sor',
          params.omega,
          params.initial,
          params.tolerance,
          params.maxIterations,
        ),
        iterate(
          plate,
          'sor_estimated',
          omega,
          params.initial,
          params.tolerance,
          params.maxIterations,
        ),
      ];
  for (final solver in solvers) {
    solver.error = maxDifference(solver.field, solutions[0]);
    solver.residual = residual(plate, solver.field, b);
  }
  final runs = [
        for (final config in params.runs)
          runTransient(plate, params, config, segments, sources, dtMax),
      ],
      reference = runs.firstWhere((r) => r.config.name == params.reference);
  snapshotsOutput(plate, params, runs, dtMax);
  steadyOutput(plate, params, segments, sources, solutions, solvers);
  comparisonOutput(
    plate,
    params,
    segments,
    runs,
    reference,
    solutions[0],
    b,
    solvers,
    dtMax,
    rho,
    omega,
  );
  isothermsOutput(plate, params, solutions[0], reference);
}
