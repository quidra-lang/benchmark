import 'dart:io';
import 'dart:math';

part 'model_io.dart';
part 'assembly.dart';
part 'solver.dart';
part 'postprocess.dart';
part 'design.dart';

class TrussSystem {
  final List<List<double>> k, kff;
  List<List<double>> g = [];
  final List<Result> results = [];
  int unstable = -1;
  TrussSystem(this.k, int nf) : kff = matrix(nf, nf);
}

class Change {
  final int group, before, after;
  final double utilization;
  Change(this.group, this.before, this.after, this.utilization);
}

class Grid {
  final List<List<String>> cells;
  final int x0, y1, wc, hc;
  Grid(this.cells, this.x0, this.y1, this.wc, this.hc);
  (int, int) point(num x, num y) =>
      (((x - x0) / wc + 0.5).floor() + 2, ((y1 - y) / hc + 0.5).floor() + 2);
  void put(int c, int r, String value) {
    if (r >= 0 && r < cells.length && c >= 0 && c < cells[r].length)
      cells[r][c] = value;
  }

  void segment(int c0, int r0, int c1, int r1, String value) {
    final dc = (c1 - c0).abs(),
        dr = -(r1 - r0).abs(),
        sc = c0 < c1 ? 1 : -1,
        sr = r0 < r1 ? 1 : -1;
    var err = dc + dr, c = c0, r = r0;
    while (true) {
      put(c, r, value);
      if (c == c1 && r == r1) break;
      final e2 = 2 * err;
      if (e2 >= dr) {
        err += dr;
        c += sc;
      }
      if (e2 <= dc) {
        err += dc;
        r += sr;
      }
    }
  }

  void frame(StringBuffer out) {
    final border = '+${'-' * cells[0].length}+';
    out.writeln(border);
    for (final row in cells) {
      out.writeln('|${row.join()}|');
    }
    out.writeln(border);
  }
}

String format(double x, int digits) {
  final s = x.toStringAsFixed(digits);
  return s.startsWith('-') && RegExp(r'^0(?:\.0+)?$').hasMatch(s.substring(1))
      ? s.substring(1)
      : s;
}

String f(double x) => format(x, 4);
int key(double x) => (x * 10000).round();
int largest(List<double> a) {
  var best = 0;
  for (var i = 1; i < a.length; i++) {
    if (key(a[i]) > key(a[best])) best = i;
  }
  return best;
}

int smallest(List<double> a) {
  var best = 0;
  for (var i = 1; i < a.length; i++) {
    if (key(a[i]) < key(a[best])) best = i;
  }
  return best;
}

void write(String path, StringBuffer s) =>
    File(path).writeAsStringSync(s.toString());
String yes(bool b) => b ? 'yes' : 'no';
(int, int, int, int) renumber(Model m) {
  final n = m.nodes.length, adj = List.generate(m.nodes.length, (_) => <int>[]);
  for (final member in m.members) {
    adj[member.i].add(member.j);
    adj[member.j].add(member.i);
  }
  var start = 0;
  for (var i = 1; i < n; i++) {
    if (adj[i].length < adj[start].length) start = i;
  }
  final queue = [start], seen = {start};
  for (var pos = 0; pos < queue.length; pos++) {
    final neighbors = adj[queue[pos]].where((v) => !seen.contains(v)).toList()
      ..sort((a, b) {
        final c = adj[a].length.compareTo(adj[b].length);
        return c != 0 ? c : m.nodes[a].id.compareTo(m.nodes[b].id);
      });
    for (final v in neighbors) {
      seen.add(v);
      queue.add(v);
    }
  }
  m.number = List.filled(n, 0);
  m.order = queue.reversed.toList();
  for (var newNumber = 0; newNumber < n; newNumber++) {
    m.number[m.order[newNumber]] = newNumber;
  }
  (int, int) metrics(List<int> number) {
    var bandwidth = 0, profile = 0;
    for (var i = 0; i < n; i++) {
      var low = number[i];
      for (final j in adj[i]) {
        low = min(low, number[j]);
        bandwidth = max(bandwidth, (number[i] - number[j]).abs());
      }
      profile += number[i] - low;
    }
    return (bandwidth, profile);
  }

  final (beforeBand, beforeProfile) = metrics([for (var i = 0; i < n; i++) i]);
  final (afterBand, afterProfile) = metrics(m.number);
  final nd = 2 * n, restrained = List.filled(2 * n, false);
  m.prescribed = List.filled(nd, 0.0);
  m.dofNode = List.filled(nd, 0);
  for (var node = 0; node < n; node++) {
    final d = 2 * m.number[node];
    m.dofNode[d] = node;
    m.dofNode[d + 1] = node;
  }
  for (final support in m.supports) {
    for (var axis = 0; axis < 2; axis++) {
      if (support.fixed[axis]) {
        final d = 2 * m.number[support.node] + axis;
        restrained[d] = true;
        m.prescribed[d] = support.prescribed[axis];
      }
    }
  }
  for (var d = 0; d < nd; d++) {
    (restrained[d] ? m.restrained : m.free).add(d);
  }
  geometry(m);
  return (beforeBand, afterBand, beforeProfile, afterProfile);
}

List<double> displacements(
  TrussSystem system,
  List<double> force,
  bool settlement,
  Model m,
) {
  final d = List.filled(2 * m.nodes.length, 0.0);
  if (settlement) {
    for (final r in m.restrained) {
      d[r] = m.prescribed[r];
    }
  }
  final b = List.filled(m.free.length, 0.0);
  for (var i = 0; i < m.free.length; i++) {
    final free = m.free[i];
    b[i] = force[free];
    for (final r in m.restrained) {
      b[i] -= system.k[free][r] * d[r];
    }
  }
  final x = solve(system.g, b);
  for (var i = 0; i < m.free.length; i++) {
    d[m.free[i]] = x[i];
  }
  return d;
}

TrussSystem analyze(Model m, List<int> sections, int removed) {
  final system = TrussSystem(stiffness(m, sections, removed), m.free.length);
  for (var i = 0; i < m.free.length; i++) {
    for (var j = 0; j < m.free.length; j++) {
      system.kff[i][j] = system.k[m.free[i]][m.free[j]];
    }
  }
  final (g, failed) = cholesky(system.kff);
  if (failed >= 0) {
    system.unstable = m.free[failed];
    return system;
  }
  system.g = g!;
  for (final load in m.cases) {
    final l = loadVectors(load, m, sections, removed);
    final d = displacements(system, l.total, l.settlement, m);
    system.results.add(
      Result(
        load.name,
        d,
        axialForces(d, l.p0, m, sections, removed),
        reactions(system.k, d, l.total, m.restrained),
        l.external,
      ),
    );
  }
  for (final combo in m.combinations) {
    system.results.add(
      combination(combo, system.results.take(m.cases.length).toList()),
    );
  }
  return system;
}

Result unit(TrussSystem system, int node, Model m, List<int> sections) {
  final force = List.filled(2 * m.nodes.length, 0.0);
  force[2 * m.number[node] + 1] = -1000;
  final d = displacements(system, force, false, m);
  return Result(
    '',
    d,
    axialForces(d, List.filled(m.members.length, 0.0), m, sections, -1),
    reactions(system.k, d, force, m.restrained),
    force,
  );
}

double weight(Model m, List<int> sections) {
  var w = 0.0;
  for (var i = 0; i < m.members.length; i++) {
    final member = m.members[i];
    w += memberWeight(
      member,
      m.sections[sections[i]],
      m.materials[member.material],
    );
  }
  return w;
}

double memberUtilization(int i, double force, Model m, List<int> sections) {
  final member = m.members[i];
  return utilization(
    force,
    member,
    m.sections[sections[i]],
    m.materials[member.material],
  );
}

List<double> magnitudes(List<double> d, Model m) {
  final a = List.filled(m.nodes.length, 0.0);
  for (var node = 0; node < m.nodes.length; node++) {
    final newNumber = m.number[node],
        x = d[2 * newNumber],
        y = d[2 * newNumber + 1];
    a[node] = sqrt(x * x + y * y);
  }
  return a;
}

Grid newGrid(Model m, int wc, int hc) {
  var x0 = m.nodes[0].x,
      x1 = m.nodes[0].x,
      y0 = m.nodes[0].y,
      y1 = m.nodes[0].y;
  for (final node in m.nodes) {
    x0 = min(x0, node.x);
    x1 = max(x1, node.x);
    y0 = min(y0, node.y);
    y1 = max(y1, node.y);
  }
  final w = ((x1 - x0) / wc + 0.5).floor() + 5,
      h = ((y1 - y0) / hc + 0.5).floor() + 5;
  return Grid(List.generate(h, (_) => List.filled(w, ' ')), x0, y1, wc, hc);
}

double ordinate(List<double> values, int x, Model m) {
  final deck = m.settings.deck,
      first = m.nodes[m.settings.deck.first].x,
      last = m.nodes[m.settings.deck.last].x;
  if (x < first || x > last) return 0;
  if (x == last) return values.last;
  for (var k = 0; k + 1 < deck.length; k++) {
    final a = m.nodes[deck[k]].x, b = m.nodes[deck[k + 1]].x;
    if (a <= x && x < b)
      return values[k] + (values[k + 1] - values[k]) * (x - a) / (b - a);
  }
  return 0;
}

List<double> vehicleEffects(List<double> values, List<int> positions, Model m) {
  final a = List.filled(positions.length, 0.0);
  for (var i = 0; i < positions.length; i++) {
    var sum = 0.0;
    for (final axle in m.settings.axles) {
      sum += axle.force * ordinate(values, positions[i] - axle.offset, m);
    }
    a[i] = sum;
  }
  return a;
}

void main() {
  final m = readModel();
  final (beforeBand, afterBand, beforeProfile, afterProfile) = renumber(m);
  final sections = m.members.map((member) => member.section).toList(),
      analysis = StringBuffer(),
      displacementOut = StringBuffer('case,node,dx,dy\n'),
      forcesOut = StringBuffer('case,member,force,stress,utilization\n'),
      reactionsOut = StringBuffer('case,node,rx,ry\n'),
      designOut = StringBuffer(),
      influenceOut = StringBuffer(),
      drawingOut = StringBuffer(),
      vibrationOut = StringBuffer();
  late TrussSystem system;
  var lastRound = 0, converged = false;
  for (var round = 1; round <= 10; round++) {
    lastRound = round;
    system = analyze(m, sections, -1);
    final combinations = system.results.sublist(m.cases.length);
    var bestMember = -1, bestCombo = 0, bestUtil = 0.0;
    for (var i = 0; i < m.members.length; i++) {
      for (var j = 0; j < combinations.length; j++) {
        final u = memberUtilization(i, combinations[j].forces[i], m, sections);
        if (bestMember < 0 || key(u) > key(bestUtil)) {
          bestMember = i;
          bestCombo = j;
          bestUtil = u;
        }
      }
    }
    final changes = <Change>[];
    for (var group = 0; group < m.groups.length; group++) {
      final next = selectSection(group, combinations, m);
      var first = -1, groupMax = 0.0, found = false;
      for (var i = 0; i < m.members.length; i++) {
        final member = m.members[i];
        if (member.group != group) continue;
        if (first < 0) first = i;
        for (final result in combinations) {
          final u = memberUtilization(i, result.forces[i], m, sections);
          if (!found || key(u) > key(groupMax)) {
            groupMax = u;
            found = true;
          }
        }
      }
      if (next != sections[first])
        changes.add(Change(group, sections[first], next, groupMax));
    }
    designOut.writeln(
      'round $round weight ${f(weight(m, sections) / 1000)} max_utilization ${f(bestUtil)} at ${m.members[bestMember].id} ${combinations[bestCombo].name} changes ${changes.length}',
    );
    for (final change in changes) {
      designOut.writeln(
        'change ${m.groups[change.group]} ${m.sections[change.before].name} ${m.sections[change.after].name} utilization ${f(change.utilization)}',
      );
    }
    if (changes.isEmpty) {
      converged = true;
      break;
    }
    if (round == 10) break;
    for (final change in changes) {
      for (var i = 0; i < m.members.length; i++) {
        if (m.members[i].group == change.group) sections[i] = change.after;
      }
    }
  }
  designOut.writeln(
    'result ${converged ? 'converged' : 'not_converged'} rounds $lastRound',
  );
  final combinations = system.results.sublist(m.cases.length),
      governing = List.filled(m.members.length, 0.0),
      governingCombo = List.filled(m.members.length, 0),
      limits = List.filled(m.members.length, 0.0);
  for (var i = 0; i < m.members.length; i++) {
    final u = [
      for (final result in combinations)
        memberUtilization(i, result.forces[i], m, sections),
    ];
    governingCombo[i] = largest(u);
    governing[i] = u[governingCombo[i]];
    limits[i] = slendernessLimit(i, combinations, m);
  }
  for (var group = 0; group < m.groups.length; group++) {
    final members = [
          for (var i = 0; i < m.members.length; i++)
            if (m.members[i].group == group) i,
        ],
        values = [
          for (var i = 0; i < m.members.length; i++)
            if (m.members[i].group == group) governing[i],
        ];
    final best = members[largest(values)];
    designOut.writeln(
      'group ${m.groups[group]} section ${m.sections[sections[members[0]]].name} members ${members.length} utilization ${f(governing[best])} at ${m.members[best].id}',
    );
  }
  for (var i = 0; i < m.members.length; i++) {
    final member = m.members[i],
        section = m.sections[sections[i]],
        lambda = slenderness(member, section);
    final verdict = governing[i] <= 1 && lambda <= limits[i] ? 'ok' : 'over';
    designOut.writeln(
      'member ${member.id} group ${m.groups[member.group]} section ${section.name} utilization ${f(governing[i])} governing ${combinations[governingCombo[i]].name} slenderness ${f(lambda)} limit ${f(limits[i])} $verdict',
    );
  }
  final ranking = [for (var i = 0; i < m.members.length; i++) i]
    ..sort((a, b) {
      final c = key(governing[b]).compareTo(key(governing[a]));
      return c != 0 ? c : a.compareTo(b);
    });
  for (var rank = 0; rank < min(5, ranking.length); rank++) {
    final i = ranking[rank];
    designOut.writeln(
      'rank ${rank + 1} member ${m.members[i].id} utilization ${f(governing[i])}',
    );
  }
  for (var i = 0; i < m.members.length; i++) {
    final values = [for (final result in combinations) result.forces[i] / 1000];
    final hi = largest(values), lo = smallest(values);
    designOut.writeln(
      'envelope ${m.members[i].id} max ${f(values[hi])} ${combinations[hi].name} min ${f(values[lo])} ${combinations[lo].name}',
    );
  }
  for (var section = 0; section < m.sections.length; section++) {
    var count = 0, length = 0.0;
    for (var i = 0; i < m.members.length; i++) {
      if (sections[i] == section) {
        count++;
        length += m.members[i].length;
      }
    }
    if (count > 0)
      designOut.writeln(
        'section ${m.sections[section].name} members $count length ${f(length)}',
      );
  }
  designOut.writeln('weight ${f(weight(m, sections) / 1000)}');
  analysis.writeln(
    'model nodes ${m.nodes.length} members ${m.members.length} supports ${m.supports.length} free_dofs ${m.free.length} restrained_dofs ${m.restrained.length} indeterminacy ${m.members.length + m.restrained.length - 2 * m.nodes.length}',
  );
  analysis.writeln(
    'renumbering ${m.order.map((node) => m.nodes[node].id).join(' ')}',
  );
  analysis.writeln('bandwidth before $beforeBand after $afterBand');
  analysis.writeln('profile before $beforeProfile after $afterProfile');
  for (final member in m.members) {
    analysis.writeln(
      'member ${member.id} nodes ${m.nodes[member.i].id} ${m.nodes[member.j].id} length ${f(member.length)} cos ${format(member.c, 6)} sin ${format(member.s, 6)}',
    );
  }
  for (var ri = 0; ri < system.results.length; ri++) {
    final result = system.results[ri],
        values = magnitudes(system.results[ri].displacements, m);
    final at = largest(values);
    var energy = 0.0;
    for (var i = 0; i < m.members.length; i++) {
      final member = m.members[i],
          force = result.forces[i],
          material = m.materials[member.material],
          section = m.sections[sections[i]];
      energy += force * force * member.length / (2 * material.e * section.area);
      forcesOut.writeln(
        '${result.name},${member.id},${f(force / 1000)},${f(force / section.area)},${f(memberUtilization(i, force, m, sections))}',
      );
    }
    final totalR = [0.0, 0.0], totalFE = [0.0, 0.0];
    for (var node = 0; node < m.nodes.length; node++) {
      final newNumber = m.number[node],
          dx = result.displacements[2 * m.number[node]],
          dy = result.displacements[2 * m.number[node] + 1];
      displacementOut.writeln(
        '${result.name},${m.nodes[node].id},${f(dx)},${f(dy)}',
      );
      for (var axis = 0; axis < 2; axis++) {
        final d = 2 * newNumber + axis;
        totalR[axis] += result.reactions[d];
        totalFE[axis] += result.external[d];
      }
    }
    for (final support in m.supports) {
      final d = 2 * m.number[support.node];
      reactionsOut.writeln(
        '${result.name},${m.nodes[support.node].id},${f(result.reactions[d] / 1000)},${f(result.reactions[d + 1] / 1000)}',
      );
    }
    final (error, scale) = equilibrium(result, m);
    analysis.writeln(
      '${ri < m.cases.length ? 'case' : 'combination'} ${result.name} equilibrium ${error <= 0.000001 * scale ? 'ok' : 'failed'} max_displacement ${f(values[at])} at ${m.nodes[at].id} energy ${f(energy / 1000)} reactions ${f(totalR[0] / 1000)} ${f(totalR[1] / 1000)} loads ${f(totalFE[0] / 1000)} ${f(totalFE[1] / 1000)}',
    );
  }
  final axes = ['x', 'y'];
  for (final support in m.supports) {
    for (var axis = 0; axis < 2; axis++) {
      if (!support.fixed[axis]) continue;
      final d = 2 * m.number[support.node] + axis,
          values = [
            for (final result in combinations)
              result.reactions[2 * m.number[support.node] + axis] / 1000,
          ];
      final uplift = combinations.any((result) => result.reactions[d] < 0),
          hi = largest(values),
          lo = smallest(values);
      analysis.write(
        'reaction_envelope ${m.nodes[support.node].id} ${axes[axis]} max ${f(values[hi])} ${combinations[hi].name} min ${f(values[lo])} ${combinations[lo].name}',
      );
      if (axis == 1) analysis.write(' uplift ${yes(uplift)}');
      analysis.writeln();
    }
  }
  for (var node = 0; node < m.nodes.length; node++) {
    final values = [
          for (final result in combinations)
            magnitudes(result.displacements, m)[node],
        ],
        at = largest(values);
    analysis.writeln(
      'displacement_envelope ${m.nodes[node].id} max ${f(values[at])} ${combinations[at].name}',
    );
  }
  final deflection = system.results[m.settings.deflection],
      supportY = {
        for (final support in m.supports)
          if (support.fixed[1]) support.node,
      };
  final deckSupports = [
    for (var i = 0; i < m.settings.deck.length; i++)
      if (supportY.contains(m.settings.deck[i])) i,
  ];
  for (var span = 1; span < deckSupports.length; span++) {
    final start = deckSupports[span - 1],
        end = deckSupports[span],
        a = m.settings.deck[deckSupports[span - 1]],
        b = m.settings.deck[deckSupports[span]];
    final xa = m.nodes[a].x,
        xb = m.nodes[b].x,
        va = deflection.displacements[2 * m.number[a] + 1],
        vb = deflection.displacements[2 * m.number[b] + 1];
    final deltas = <double>[];
    for (var i = start; i <= end; i++) {
      final node = m.settings.deck[i],
          v = deflection.displacements[2 * m.number[m.settings.deck[i]] + 1];
      deltas.add(
        (v - (va + (vb - va) * (m.nodes[node].x - xa) / (xb - xa))).abs(),
      );
    }
    final at = largest(deltas),
        node = m.settings.deck[start + at],
        limit = (xb - xa) / m.settings.ratio;
    analysis.writeln(
      'deflection ${deflection.name} span ${m.nodes[a].id} ${m.nodes[b].id} max ${f(deltas[at])} at ${m.nodes[node].id} limit ${f(limit)} ${deltas[at] <= limit ? 'ok' : 'exceeded'}',
    );
    final virtual = unit(system, node, m, sections);
    var sum = 0.0;
    for (var i = 0; i < m.members.length; i++) {
      final member = m.members[i];
      sum +=
          deflection.forces[i] *
          (virtual.forces[i] / 1000) *
          member.length /
          (m.materials[member.material].e * m.sections[sections[i]].area);
    }
    final stiffness = -deflection.displacements[2 * m.number[node] + 1];
    analysis.writeln(
      'virtual_work ${deflection.name} node ${m.nodes[node].id} stiffness ${f(stiffness)} virtual ${f(sum)} ${(sum - stiffness).abs() <= 0.000001 * max(1.0, stiffness.abs()) ? 'ok' : 'failed'}',
    );
  }
  for (var removed = 0; removed < m.members.length; removed++) {
    final member = m.members[removed], study = analyze(m, sections, removed);
    if (study.unstable >= 0) {
      final node = m.dofNode[study.unstable];
      analysis.writeln(
        'removal ${member.id} unstable at ${m.nodes[node].id} ${axes[study.unstable % 2]}',
      );
      continue;
    }
    final result = study.results[m.settings.removal],
        remaining = [
          for (var i = 0; i < m.members.length; i++)
            if (i != removed) i,
        ];
    final values = [
          for (final i in remaining)
            memberUtilization(i, result.forces[i], m, sections),
        ],
        disps = magnitudes(result.displacements, m);
    final at = largest(values), node = largest(disps);
    analysis.writeln(
      'removal ${member.id} stable max_utilization ${f(values[at])} at ${m.members[remaining[at]].id} max_displacement ${f(disps[node])} at ${m.nodes[node].id}',
    );
  }
  final q = m.settings.deck.length,
      forceOrdinates = matrix(m.members.length, m.settings.deck.length),
      reactionOrdinates = matrix(2 * m.nodes.length, m.settings.deck.length);
  for (var k = 0; k < q; k++) {
    final result = unit(system, m.settings.deck[k], m, sections);
    for (var i = 0; i < result.forces.length; i++) {
      forceOrdinates[i][k] = result.forces[i] / 1000;
    }
    for (var d = 0; d < result.reactions.length; d++) {
      reactionOrdinates[d][k] = result.reactions[d] / 1000;
    }
  }
  for (final memberIndex in m.settings.influence) {
    final member = m.members[memberIndex], values = forceOrdinates[memberIndex];
    influenceOut.writeln('influence ${member.id}');
    var positive = 0.0, negative = 0.0;
    final crossings = <double>[];
    for (var k = 0; k < values.length; k++) {
      final value = values[k];
      influenceOut.writeln(
        'node ${m.nodes[m.settings.deck[k]].id} ${f(value)}',
      );
      if (value > 0) positive += value;
      if (value < 0) negative += value;
      if (k + 1 < values.length &&
          ((value > 0 && values[k + 1] < 0) ||
              (value < 0 && values[k + 1] > 0))) {
        final x0 = m.nodes[m.settings.deck[k]].x,
            x1 = m.nodes[m.settings.deck[k + 1]].x;
        crossings.add(x0 + (x1 - x0) * value / (value - values[k + 1]));
      }
    }
    final hi = largest(values), lo = smallest(values);
    influenceOut.writeln(
      'max ${f(values[hi])} at ${m.nodes[m.settings.deck[hi]].id} min ${f(values[lo])} at ${m.nodes[m.settings.deck[lo]].id} positive ${f(positive)} negative ${f(negative)}',
    );
    influenceOut.writeln(
      [
        'crossings',
        '${crossings.length}',
        ...crossings.map((x) => format(x, 1)),
      ].join(' '),
    );
  }
  final positions = [
    for (
      var p = m.nodes[m.settings.deck.first].x;
      p <= m.nodes[m.settings.deck.last].x + m.settings.axles.last.offset;
      p += m.settings.step
    )
      p,
  ];
  influenceOut.writeln(
    'vehicle axles ${m.settings.axles.length} positions ${positions.length}',
  );
  final vehicleMax = List.filled(m.members.length, 0.0),
      vehicleMin = List.filled(m.members.length, 0.0);
  for (var i = 0; i < m.members.length; i++) {
    final effects = vehicleEffects(forceOrdinates[i], positions, m),
        hi = largest(effects),
        lo = smallest(effects);
    vehicleMax[i] = effects[hi];
    vehicleMin[i] = effects[lo];
    influenceOut.writeln(
      'vehicle_member ${m.members[i].id} max ${f(effects[hi])} at ${positions[hi]} min ${f(effects[lo])} at ${positions[lo]}',
    );
  }
  for (final support in m.supports) {
    for (var axis = 0; axis < 2; axis++) {
      if (!support.fixed[axis]) continue;
      final d = 2 * m.number[support.node] + axis;
      final effects = vehicleEffects(reactionOrdinates[d], positions, m);
      final hi = largest(effects), lo = smallest(effects);
      influenceOut.writeln(
        'vehicle_reaction ${m.nodes[support.node].id} ${axes[axis]} max ${f(effects[hi])} at ${positions[hi]} min ${f(effects[lo])} at ${positions[lo]}',
      );
    }
  }
  var ratingMinimum = 0.0, ratingMember = -1, ratingKind = '';
  final dead = system.results[m.settings.rating];
  for (var i = 0; i < m.members.length; i++) {
    final member = m.members[i],
        material = m.materials[member.material],
        section = m.sections[sections[i]],
        nd = dead.forces[i] / 1000,
        t = vehicleMax[i],
        c = vehicleMin[i];
    final pt = section.area * material.fy / 1000,
        pc =
            min(
              section.area * material.fy,
              buckling(member, section, material),
            ) /
            1000,
        names = ['none', 'none'],
        values = [0.0, 0.0],
        exists = [key(t) > 0, key(c) < 0];
    if (exists[0]) {
      values[0] = (pt - m.settings.gammaD * nd) / (m.settings.gammaL * t);
      names[0] = f(values[0]);
    }
    if (exists[1]) {
      values[1] = (pc + m.settings.gammaD * nd) / (m.settings.gammaL * (-c));
      names[1] = f(values[1]);
    }
    for (var k = 0; k < 2; k++) {
      final value = values[k];
      if (exists[k] && (ratingMember < 0 || key(value) < key(ratingMinimum))) {
        ratingMember = i;
        ratingMinimum = value;
        ratingKind = k == 0 ? 'tension' : 'compression';
      }
    }
    influenceOut.writeln(
      'rating ${member.id} tension ${names[0]} compression ${names[1]}',
    );
  }
  influenceOut.writeln(
    'rating_min ${f(ratingMinimum)} at ${m.members[ratingMember].id} $ratingKind',
  );
  final vibration = system.results[m.settings.vibration],
      mass = List.filled(m.nodes.length, 0.0);
  var totalMass = 0.0;
  for (var node = 0; node < m.nodes.length; node++) {
    mass[node] = -vibration.external[2 * m.number[node] + 1] / 9.81;
    totalMass += mass[node];
  }
  final freeMass = [for (final d in m.free) mass[m.dofNode[d]]];
  vibrationOut.writeln(
    'vibration ${vibration.name} mass ${f(totalMass)} iterations ${m.settings.iterations}',
  );
  final modes = <List<double>>[];
  for (var mode = 1; mode <= m.settings.modes; mode++) {
    final x = List.filled(m.free.length, 1.0);
    for (var iteration = 0; iteration < m.settings.iterations; iteration++) {
      for (final phi in modes) {
        var beta = 0.0;
        for (var i = 0; i < x.length; i++) {
          beta += phi[i] * freeMass[i] * x[i];
        }
        for (var i = 0; i < x.length; i++) {
          x[i] = x[i] - beta * phi[i];
        }
      }
      final b = [for (var i = 0; i < x.length; i++) freeMass[i] * x[i]],
          y = solve(system.g, b);
      var sum = 0.0;
      for (var i = 0; i < y.length; i++) {
        sum += freeMass[i] * y[i] * y[i];
      }
      final nu = sqrt(sum);
      for (var i = 0; i < x.length; i++) {
        x[i] = y[i] / nu;
      }
    }
    modes.add(List.of(x));
    var numerator = 0.0, denominator = 0.0;
    for (var i = 0; i < x.length; i++) {
      var kx = 0.0;
      for (var j = 0; j < x.length; j++) {
        kx += system.kff[i][j] * x[j];
      }
      numerator += x[i] * kx;
      denominator += freeMass[i] * x[i] * x[i];
    }
    final lambda = numerator / denominator,
        frequency = sqrt(1000 * lambda) / (2 * 3.141592653589793);
    vibrationOut.writeln(
      'mode $mode frequency ${f(frequency)} period ${f(1 / frequency)}',
    );
    var imax = 0;
    for (var i = 1; i < x.length; i++) {
      if (x[i].abs() > x[imax].abs()) imax = i;
    }
    final shape = List.filled(2 * m.nodes.length, 0.0);
    for (var i = 0; i < m.free.length; i++) {
      shape[m.free[i]] = x[i] / x[imax];
    }
    for (var node = 0; node < m.nodes.length; node++) {
      final newNumber = m.number[node];
      vibrationOut.writeln(
        'node ${m.nodes[node].id} ${f(shape[2 * newNumber])} ${f(shape[2 * newNumber + 1])}',
      );
    }
  }
  for (final drawing in m.settings.drawings) {
    final g = newGrid(m, drawing.wc, drawing.hc),
        result = system.results[drawing.result],
        positions = <(int, int)>[],
        deformed = <(int, int)>[];
    for (var node = 0; node < m.nodes.length; node++) {
      final value = m.nodes[node], d = 2 * m.number[node];
      positions.add(g.point(value.x, value.y));
      deformed.add(
        g.point(
          value.x + drawing.scale * result.displacements[d],
          value.y + drawing.scale * result.displacements[d + 1],
        ),
      );
    }
    for (final member in m.members) {
      final (c0, r0) = positions[member.i];
      final (c1, r1) = positions[member.j];
      g.segment(c0, r0, c1, r1, '.');
    }
    for (final (c, r) in positions) {
      g.put(c, r, '+');
    }
    for (final member in m.members) {
      final (c0, r0) = deformed[member.i];
      final (c1, r1) = deformed[member.j];
      g.segment(c0, r0, c1, r1, '*');
    }
    for (final (c, r) in deformed) {
      g.put(c, r, 'o');
    }
    drawingOut.writeln(
      'drawing ${result.name} magnification ${drawing.scale} columns ${g.cells[0].length} rows ${g.cells.length}',
    );
    g.frame(drawingOut);
  }
  final g = newGrid(m, m.settings.mapWC, m.settings.mapHC);
  for (var i = 0; i < m.members.length; i++) {
    final member = m.members[i], a = m.nodes[member.i], b = m.nodes[member.j];
    final (c0, r0) = g.point(a.x, a.y);
    final (c1, r1) = g.point(b.x, b.y);
    final value = governing[i] >= 1
        ? '#'
        : (10 * governing[i]).floor().toString();
    g.segment(c0, r0, c1, r1, value);
  }
  for (final node in m.nodes) {
    final (c, r) = g.point(node.x, node.y);
    g.put(c, r, 'o');
  }
  drawingOut.writeln(
    'utilization_map columns ${g.cells[0].length} rows ${g.cells.length}',
  );
  g.frame(drawingOut);
  Directory('output').createSync(recursive: true);
  final outputs = {
    'analysis.txt': analysis,
    'displacements.csv': displacementOut,
    'member_forces.csv': forcesOut,
    'reactions.csv': reactionsOut,
    'design.txt': designOut,
    'influence.txt': influenceOut,
    'drawing.txt': drawingOut,
    'vibration.txt': vibrationOut,
  };
  for (final entry in outputs.entries) {
    write('output/${entry.key}', entry.value);
  }
}
