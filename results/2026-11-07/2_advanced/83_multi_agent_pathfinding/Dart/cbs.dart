part of 'main.dart';

class Constraint {
  final int agent, time, u, v;
  final bool edge;
  Constraint(this.agent, this.time, this.u, this.v, this.edge);
}

class Conflict {
  final int time, a, b, u, v;
  final bool edge;
  Conflict(this.time, this.a, this.b, this.u, this.v, this.edge);
  Constraint constraint(int agent) => Constraint(
    agent,
    time,
    edge && agent == b ? v : u,
    edge && agent == b ? u : v,
    edge,
  );
}

int position(List<int> path, int t) => path[min(t, path.length - 1)];
(int, int) planCosts(List<List<int>> paths) {
  var soc = 0, makespan = 0;
  for (final p in paths) {
    soc += p.length - 1;
    makespan = max(makespan, p.length - 1);
  }
  return (soc, makespan);
}

List<Conflict> conflicts(List<List<int>> paths) {
  final last = planCosts(paths).$2, out = <Conflict>[];
  for (var t = 1; t <= last; t++) {
    for (var a = 0; a < paths.length; a++) {
      for (var b = a + 1; b < paths.length; b++) {
        final u = position(paths[a], t - 1),
            v = position(paths[a], t),
            bu = position(paths[b], t - 1),
            bv = position(paths[b], t);
        if (v == bv) {
          out.add(Conflict(t, a, b, v, v, false));
        } else if (v == bu && bv == u) {
          out.add(Conflict(t, a, b, u, v, true));
        }
      }
    }
  }
  return out;
}

class Node {
  final int number, parent, depth, cost;
  final List<List<int>> paths;
  final List<List<Constraint>> constraints;
  final List<Conflict> conflicts;
  Node(
    this.number,
    this.parent,
    this.depth,
    this.cost,
    this.paths,
    this.constraints,
    this.conflicts,
  );
}

int nodeCompare(Node a, Node b) {
  var c = a.cost.compareTo(b.cost);
  if (c != 0) return c;
  c = a.conflicts.length.compareTo(b.conflicts.length);
  return c != 0 ? c : a.number.compareTo(b.number);
}
