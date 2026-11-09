part of 'main.dart';

class Factor {
  final String name;
  late final String column;
  int power = 1;
  bool categorical = false;
  Factor(this.name) {
    if (name.startsWith('C(')) {
      categorical = true;
      column = name.substring(2, name.length - 1);
    } else if (name.startsWith('I(')) {
      final parts = name.substring(2, name.length - 1).split('^');
      column = parts[0];
      power = int.parse(parts[1]);
    } else {
      column = name;
    }
  }
  double value(DataRow row, String level) {
    final v = row[column]!;
    if (categorical) return v.label == level ? 1 : 0;
    final x = v.number!;
    return power == 2
        ? x * x
        : power == 3
        ? x * x * x
        : x;
  }
}

class Term {
  final List<Factor> factors;
  final String name;
  final Set<String> names;
  Term(this.factors)
    : name = factors.map((f) => f.name).join(':'),
      names = factors.map((f) => f.name).toSet();
  bool contained(Term other) =>
      names.length < other.names.length && names.every(other.names.contains);
}

class Model {
  late final String original, response, weight;
  final terms = <Term>[],
      factorColumns = <String>[],
      categoryColumns = <String>[],
      variables = <String>[];
  Model(String line) {
    final split = line.split(' weights=');
    original = split[0];
    weight = split.length == 2 ? split[1] : '';
    final parts = original.split(' ~ ');
    response = parts[0];
    final seen = <String>{};
    void add(List<Factor> factors) {
      final term = Term(factors),
          names = term.names.toList()..sort(),
          key = names.join('\u0000');
      if (seen.add(key)) terms.add(term);
    }

    for (final expression in parts[1].split(' + ')) {
      if (expression.contains('*')) {
        final factors = expression.split('*').map(Factor.new).toList();
        for (var size = 1; size <= factors.length; size++) {
          for (var mask = 1; mask < 1 << factors.length; mask++) {
            var count = 0;
            for (var bits = mask; bits > 0; bits >>= 1) {
              count += bits & 1;
            }
            if (count != size) continue;
            add([
              for (var j = 0; j < factors.length; j++)
                if ((mask & (1 << j)) != 0) factors[j],
            ]);
          }
        }
      } else {
        add(expression.split(':').map(Factor.new).toList());
      }
    }
    for (final t in terms) {
      for (final f in t.factors) {
        if (!factorColumns.contains(f.column)) factorColumns.add(f.column);
        if (f.categorical && !categoryColumns.contains(f.column))
          categoryColumns.add(f.column);
      }
    }
    variables.addAll([
      ...factorColumns,
      response,
      if (weight.isNotEmpty) weight,
    ]);
  }
  String format(List<int> selected) =>
      '$response ~ ${selected.isEmpty ? '1' : selected.map((i) => terms[i].name).join(' + ')}';
  List<int> removable(List<int> selected) => [
    for (final i in selected)
      if (!selected.any((j) => terms[i].contained(terms[j]))) i,
  ];
  List<int> candidates(List<int> selected) {
    final set = selected.toSet();
    return [
      for (var i = 0; i < terms.length; i++)
        if (!set.contains(i) &&
            [
              for (var j = 0; j < terms.length; j++)
                if (terms[j].contained(terms[i])) j,
            ].every(set.contains))
          i,
    ];
  }

  bool hierarchical(List<int> selected) {
    final set = selected.toSet();
    return selected.every(
      (i) => [
        for (var j = 0; j < terms.length; j++)
          if (terms[j].contained(terms[i])) j,
      ].every(set.contains),
    );
  }
}

class Component {
  final Factor factor;
  final String name, level;
  Component(this.factor, this.name, [this.level = '']);
}

class DesignColumn {
  final int term;
  final String name;
  final List<Component> components;
  DesignColumn(this.term, this.name, this.components);
  double value(DataRow row) {
    if (components.isEmpty) return 1;
    var v = components.first.factor.value(row, components.first.level);
    for (final s in components.skip(1)) {
      v *= s.factor.value(row, s.level);
    }
    return v;
  }
}

class Design {
  final Model model;
  final rowNumbers = <int>[],
      rows = <DataRow>[],
      levels = <String, List<String>>{},
      columns = <DesignColumn>[],
      matrix = <List<double>>[],
      response = <double>[],
      weights = <double>[];
  Design(this.model, DataFrame data) {
    columns.add(DesignColumn(-1, '(Intercept)', []));
    for (var i = 0; i < data.rows.length; i++) {
      final row = data.rows[i];
      if (model.variables.every((c) => row[c]!.present)) {
        rowNumbers.add(i + 1);
        rows.add(row);
      }
    }
    for (final c in model.categoryColumns) {
      levels[c] = rows.map((r) => r[c]!.label!).toSet().toList()..sort();
    }
    for (var i = 0; i < model.terms.length; i++) {
      final t = model.terms[i],
          components = [
            for (final f in t.factors)
              f.categorical
                  ? [
                      for (final level in levels[f.column]!.skip(1))
                        Component(f, f.name + level, level),
                    ]
                  : [Component(f, f.name)],
          ];
      final choices = List<Component?>.filled(components.length, null);
      void product(int j) {
        if (j < 0) {
          final tuple = [for (final c in choices) c!];
          columns.add(
            DesignColumn(i, tuple.map((c) => c.name).join(':'), tuple),
          );
          return;
        }
        for (final c in components[j]) {
          choices[j] = c;
          product(j - 1);
        }
      }

      product(components.length - 1);
    }
    for (final row in rows) {
      matrix.add(values(row));
      response.add(row[model.response]!.number!);
      weights.add(model.weight.isEmpty ? 1 : row[model.weight]!.number!);
    }
  }
  List<double> values(DataRow row) => columns.map((c) => c.value(row)).toList();
  List<List<double>> subsetMatrix(List<int> selected) {
    final set = selected.toSet(),
        indices = [
          for (var j = 0; j < columns.length; j++)
            if (columns[j].term < 0 || set.contains(columns[j].term)) j,
        ];
    return [
      for (final row in matrix) [for (final j in indices) row[j]],
    ];
  }

  bool predictable(DataRow row) {
    for (final c in model.factorColumns) {
      final v = row[c]!;
      if (!v.present) return false;
      if (levels.containsKey(c) && !levels[c]!.contains(v.label)) return false;
    }
    return true;
  }
}
