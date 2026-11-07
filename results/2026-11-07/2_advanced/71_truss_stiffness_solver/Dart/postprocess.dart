part of 'main.dart';

class Result {
  final String name;
  final List<double> displacements, forces, reactions, external;
  Result(
    this.name,
    this.displacements,
    this.forces,
    this.reactions,
    this.external,
  );
}

List<double> axialForces(
  List<double> displacements,
  List<double> p0,
  Model m,
  List<int> sections,
  int removed,
) {
  final forces = List.filled(m.members.length, 0.0);
  for (var i = 0; i < m.members.length; i++) {
    if (i == removed) continue;
    final member = m.members[i], a = m.members[i].dofs;
    final e =
            (displacements[a[2]] - displacements[a[0]]) * member.c +
            (displacements[a[3]] - displacements[a[1]]) * member.s,
        k =
            m.materials[member.material].e *
            m.sections[sections[i]].area /
            member.length;
    forces[i] = k * e - p0[i];
  }
  return forces;
}

List<double> reactions(
  List<List<double>> k,
  List<double> d,
  List<double> f,
  List<int> restrained,
) {
  final r = List.filled(d.length, 0.0);
  for (final row in restrained) {
    var sum = 0.0;
    for (var col = 0; col < d.length; col++) {
      sum += k[row][col] * d[col];
    }
    r[row] = sum - f[row];
  }
  return r;
}

Result combination(Combination combo, List<Result> cases) {
  final nd = cases[0].displacements.length, nm = cases[0].forces.length;
  final r = Result(
    combo.name,
    List.filled(nd, 0.0),
    List.filled(nm, 0.0),
    List.filled(nd, 0.0),
    List.filled(nd, 0.0),
  );
  for (final term in combo.terms) {
    final c = cases[term.caseIndex];
    for (var i = 0; i < nd; i++) {
      r.displacements[i] += term.factor * c.displacements[i];
      r.reactions[i] += term.factor * c.reactions[i];
      r.external[i] += term.factor * c.external[i];
    }
    for (var i = 0; i < nm; i++) {
      r.forces[i] += term.factor * c.forces[i];
    }
  }
  return r;
}

(double, double) equilibrium(Result r, Model m) {
  final z = List.filled(r.external.length, 0.0);
  var scale = 1.0;
  for (var i = 0; i < z.length; i++) {
    z[i] = r.external[i] + r.reactions[i];
    scale = max(scale, r.external[i].abs());
    scale = max(scale, r.reactions[i].abs());
  }
  for (var i = 0; i < m.members.length; i++) {
    final member = m.members[i],
        t = [m.members[i].c, m.members[i].s, -m.members[i].c, -m.members[i].s];
    for (var k = 0; k < 4; k++) {
      z[member.dofs[k]] += r.forces[i] * t[k];
    }
  }
  var maximum = 0.0;
  for (final v in z) {
    maximum = max(maximum, v.abs());
  }
  return (maximum, scale);
}
