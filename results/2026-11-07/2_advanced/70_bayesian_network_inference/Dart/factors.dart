part of 'main.dart';

class Factor {
  final List<int> variables;
  final List<double> values;
  Factor(this.variables, this.values);
  double value(List<int> a, Network n) => values[factorIndex(variables, a, n)];
}

class Evidence {
  final int v, s;
  Evidence(this.v, this.s);
}

int assignmentCount(List<int> vars, Network n) {
  var count = 1;
  for (final v in vars) {
    count *= n.variables[v].states.length;
  }
  return count;
}

void assignments(List<int> vars, Network n, void Function(List<int>) visit) {
  final a = List.filled(n.variables.length, 0);
  void walk(int pos) {
    if (pos == vars.length) {
      visit(a);
      return;
    }
    final v = vars[pos];
    for (var state = 0; state < n.variables[v].states.length; state++) {
      a[v] = state;
      walk(pos + 1);
    }
  }

  walk(0);
}

List<int> variableUnion(Iterable<List<int>> lists) =>
    lists.expand((a) => a).toSet().toList()..sort();
List<int> without(List<int> vars, Set<int> remove) =>
    vars.where((v) => !remove.contains(v)).toList();
int factorIndex(List<int> vars, List<int> a, Network n) {
  var index = 0;
  for (final v in vars) {
    index = index * n.variables[v].states.length + a[v];
  }
  return index;
}

Factor cptFactor(int v, Network n) {
  final co = n.variables[v],
      f = Factor(
        variableUnion([
          [v],
          n.variables[v].parents,
        ]),
        [],
      );
  assignments(f.variables, n, (a) {
    f.values.add(co.theta[parentCombination(co.parents, a, n)][a[v]]);
  });
  return f;
}

Factor reduce(Factor f, List<Evidence> e, Network n) {
  final remove = e.map((ev) => ev.v).toSet(),
      g = Factor(without(f.variables, remove), []);
  assignments(g.variables, n, (a) {
    for (final ev in e) {
      a[ev.v] = ev.s;
    }
    g.values.add(f.value(a, n));
  });
  return g;
}

Factor multiply(Factor a, Factor b, Network n) {
  final f = Factor(variableUnion([a.variables, b.variables]), []);
  assignments(f.variables, n, (state) {
    f.values.add(a.value(state, n) * b.value(state, n));
  });
  return f;
}

Factor product(List<Factor> factors, Network n) {
  if (factors.isEmpty) return Factor([], [1]);
  var f = factors.first;
  for (final g in factors.skip(1)) {
    f = multiply(f, g, n);
  }
  return f;
}

Factor eliminate(Factor f, int v, bool maximum, Network n) {
  final g = Factor(without(f.variables, {v}), []);
  assignments(g.variables, n, (a) {
    var value = maximum ? -1.0 : 0.0;
    for (var state = 0; state < n.variables[v].states.length; state++) {
      a[v] = state;
      final x = f.value(a, n);
      if (maximum) {
        if (x > value) value = x;
      } else {
        value += x;
      }
    }
    g.values.add(value);
  });
  return g;
}
