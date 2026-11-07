part of 'main.dart';

class Loads {
  final List<double> external, temperature, total, p0;
  bool settlement = false;
  Loads(int nd, int members)
    : external = List.filled(nd, 0.0),
      temperature = List.filled(nd, 0.0),
      total = List.filled(nd, 0.0),
      p0 = List.filled(members, 0.0);
}

void geometry(Model m) {
  for (final member in m.members) {
    final a = m.nodes[member.i], b = m.nodes[member.j];
    final dx = b.x - a.x, dy = b.y - a.y;
    member.length = sqrt(dx * dx + dy * dy);
    member.c = dx / member.length;
    member.s = dy / member.length;
    member.dofs = [
      2 * m.number[member.i],
      2 * m.number[member.i] + 1,
      2 * m.number[member.j],
      2 * m.number[member.j] + 1,
    ];
  }
}

List<List<double>> matrix(int rows, int columns) =>
    List.generate(rows, (_) => List.filled(columns, 0.0));
List<List<double>> stiffness(Model m, List<int> sections, int removed) {
  final nd = 2 * m.nodes.length, global = matrix(nd, nd);
  for (var i = 0; i < m.members.length; i++) {
    if (i == removed) continue;
    final member = m.members[i],
        material = m.materials[member.material],
        section = m.sections[sections[i]];
    final k = material.e * section.area / member.length,
        c = member.c,
        s = member.s;
    final kxx = k * (c * c), kxy = k * (c * s), kyy = k * (s * s);
    final local = [
      [kxx, kxy, -kxx, -kxy],
      [kxy, kyy, -kxy, -kyy],
      [-kxx, -kxy, kxx, kxy],
      [-kxy, -kyy, kxy, kyy],
    ];
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        global[member.dofs[r]][member.dofs[c]] += local[r][c];
      }
    }
  }
  return global;
}

double memberWeight(Member member, Section section, Material material) =>
    material.rho * 9.81 * section.area * member.length / 1000000000;
Loads loadVectors(LoadCase load, Model m, List<int> sections, int removed) {
  final l = Loads(2 * m.nodes.length, m.members.length);
  for (final line in load.lines) {
    switch (line.kind) {
      case 'FORCE':
        final d = 2 * m.number[line.item];
        l.external[d] += line.x * 1000;
        l.external[d + 1] += line.y * 1000;
        break;
      case 'TEMPERATURE':
        if (line.item == removed) continue;
        final member = m.members[line.item],
            material = m.materials[member.material],
            section = m.sections[sections[line.item]];
        final p0 = material.e * section.area * material.alpha * line.x;
        l.p0[line.item] = p0;
        final t = [-member.c, -member.s, member.c, member.s];
        for (var i = 0; i < 4; i++) {
          l.temperature[member.dofs[i]] += p0 * t[i];
        }
        break;
      case 'SELFWEIGHT':
        for (var i = 0; i < m.members.length; i++) {
          if (i == removed) continue;
          final member = m.members[i],
              w = memberWeight(
                m.members[i],
                m.sections[sections[i]],
                m.materials[m.members[i].material],
              );
          l.external[member.dofs[1]] -= w / 2;
          l.external[member.dofs[3]] -= w / 2;
        }
        break;
      case 'SETTLEMENT':
        l.settlement = true;
        break;
    }
  }
  for (var d = 0; d < l.total.length; d++) {
    l.total[d] = l.external[d] + l.temperature[d];
  }
  return l;
}
