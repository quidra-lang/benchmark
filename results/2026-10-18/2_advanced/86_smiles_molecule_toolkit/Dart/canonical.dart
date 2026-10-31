part of 'main.dart';

int compareInts(List<int> a, List<int> b) {
  for (var i = 0; i < min(a.length, b.length); i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

List<int> dense(List<List<int>> values) {
  final order = List.generate(values.length, (i) => i)
        ..sort((a, b) => compareInts(values[a], values[b])),
      ranks = List.filled(values.length, 0);
  var rank = 0;
  List<int>? previous;
  for (final i in order) {
    if (previous == null || compareInts(values[i], previous) != 0) {
      rank++;
      previous = values[i];
    }
    ranks[i] = rank;
  }
  return ranks;
}

int rankCount(List<int> ranks) => ranks.fold<int>(0, (a, b) => max(a, b));
List<int> refine(Molecule m, List<int> ranks) {
  while (true) {
    final values = <List<int>>[];
    for (var a = 0; a < m.atoms.length; a++) {
      final neighbors =
          [
            for (final e in m.adjacent[a])
              (ranks[m.bonds[e].other(a)], m.bonds[e].type),
          ]..sort((a, b) {
            final c = a.$1.compareTo(b.$1);
            return c != 0 ? c : a.$2.compareTo(b.$2);
          });
      values.add([
        ranks[a],
        for (final p in neighbors) ...[p.$1, p.$2],
      ]);
    }
    final next = dense(values);
    if (rankCount(next) == rankCount(ranks)) return next;
    ranks = next;
  }
}

void canonicalRanks(Molecule m, Map<String, Element> elements) {
  final values = [
    for (var i = 0; i < m.atoms.length; i++)
      [
        m.adjacent[i].length,
        elements[m.atoms[i].symbol]!.number,
        m.atoms[i].mass,
        m.atoms[i].charge,
        m.atoms[i].hydrogens,
        m.atoms[i].aromatic ? 1 : 0,
      ],
  ];
  var ranks = refine(m, dense(values));
  m.classes = rankCount(ranks);
  while (rankCount(ranks) < m.atoms.length) {
    final counts = <int, int>{};
    for (final r in ranks) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    var smallest = m.atoms.length + 1;
    for (final e in counts.entries) {
      if (e.value > 1) smallest = min(smallest, e.key);
    }
    final chosen = ranks.indexOf(smallest),
        values = [
          for (var i = 0; i < ranks.length; i++)
            [2 * ranks[i] - (i == chosen ? 1 : 0)],
        ];
    ranks = refine(m, dense(values));
  }
  m.ranks = ranks;
}

String atomNotation(Molecule m, int index, Map<String, Element> elements) {
  final a = m.atoms[index],
      symbol = a.aromatic ? a.symbol.toLowerCase() : a.symbol,
      organic =
          [
            'B',
            'C',
            'N',
            'O',
            'P',
            'S',
            'F',
            'Cl',
            'Br',
            'I',
          ].contains(a.symbol) &&
          (!a.aromatic || ['B', 'C', 'N', 'O', 'P', 'S'].contains(a.symbol));
  final (hydrogens, possible) = organicHydrogens(m, index, elements);
  if (organic &&
      a.mass == 0 &&
      a.charge == 0 &&
      (!a.aromatic ||
          m.needsPi(index, elements, true) ==
              m.needsPi(index, elements, false)) &&
      possible &&
      hydrogens == a.hydrogens)
    return symbol;
  final out = StringBuffer('[');
  if (a.mass != 0) out.write(a.mass);
  out.write(symbol);
  if (a.hydrogens > 0) {
    out.write('H');
    if (a.hydrogens >= 2) out.write(a.hydrogens);
  }
  if (a.charge != 0) {
    out.write(a.charge > 0 ? '+' : '-');
    if (a.charge.abs() >= 2) out.write(a.charge.abs());
  }
  out.write(']');
  return out.toString();
}

String canonicalBond(Molecule m, Bond b) {
  final inRing = m.atoms[b.a].aromatic && m.atoms[b.b].aromatic && b.ring;
  return switch (b.type) {
    1 => inRing ? '-' : '',
    2 => '=',
    3 => '#',
    4 => inRing ? '' : ':',
    _ => throw StateError('bad bond type'),
  };
}

String canonicalSMILES(Molecule m, Map<String, Element> elements) {
  final start = m.ranks.indexOf(1),
      visited = List.filled(m.atoms.length, false),
      visitOrder = List.filled(m.atoms.length, 0),
      classification = List.filled(m.bonds.length, 0),
      children = List.generate(m.atoms.length, (_) => <(int, int)>[]);
  var serial = 0;
  void visit(int a, int parentEdge) {
    visited[a] = true;
    visitOrder[a] = ++serial;
    final neighbors = List<int>.of(m.adjacent[a])
      ..sort(
        (i, j) => m.ranks[m.bonds[i].other(a)].compareTo(
          m.ranks[m.bonds[j].other(a)],
        ),
      );
    for (final e in neighbors) {
      if (e == parentEdge || classification[e] == 2) continue;
      final b = m.bonds[e].other(a);
      if (!visited[b]) {
        classification[e] = 1;
        children[a].add((b, e));
        visit(b, e);
      } else {
        classification[e] = 2;
      }
    }
  }

  visit(start, -1);
  final assignments = <int, int>{}, used = <int>{};
  String numberText(int n) =>
      n <= 9 ? '$n' : '%${n.toString().padLeft(2, '0')}';
  String write(int a) {
    final out = StringBuffer(atomNotation(m, a, elements)),
        closures =
            [
              for (final e in m.adjacent[a])
                if (classification[e] == 2) e,
            ]..sort(
              (i, j) => visitOrder[m.bonds[i].other(a)].compareTo(
                visitOrder[m.bonds[j].other(a)],
              ),
            );
    for (final e in closures) {
      final number = assignments[e];
      if (number != null) {
        out.write(numberText(number));
        assignments.remove(e);
        used.remove(number);
      } else {
        var number = 1;
        while (used.contains(number)) {
          number++;
        }
        assignments[e] = number;
        used.add(number);
        out.write(canonicalBond(m, m.bonds[e]));
        out.write(numberText(number));
      }
    }
    for (var i = 0; i < children[a].length; i++) {
      final child = children[a][i],
          text = '${canonicalBond(m, m.bonds[child.$2])}${write(child.$1)}';
      out.write(i + 1 < children[a].length ? '($text)' : text);
    }
    return out.toString();
  }

  return write(start);
}
