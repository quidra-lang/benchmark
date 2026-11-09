part of 'main.dart';

(Atom?, int, String) patternAtom(String source, int at) {
  final c = source[at];
  if (c == '*' || c == 'A' || c == 'a') return (Atom(wildcard: c), at + 1, '');
  if (c == '[') {
    final end = source.indexOf(']', at + 1);
    if (end < 0) return (null, at, 'unclosed bracket');
    final parts = source.substring(at + 1, end).split(','),
        choices = <Choice>[];
    for (final part in parts) {
      if (part.isEmpty) return (null, at, 'bad bracket atom');
      final (a, next, ok) = organic(part, 0);
      if (!ok || next != part.length) return (null, at, 'bad bracket atom');
      final atom = a!;
      choices.add(Choice(atom.symbol, atom.aromatic));
    }
    return (Atom(choices: choices), end + 1, '');
  }
  final (a, next, ok) = organic(source, at);
  if (!ok) return (null, at, 'unexpected character');
  final atom = a!;
  return (Atom(choices: [Choice(atom.symbol, atom.aromatic)]), next, '');
}

bool atomMatches(Atom pattern, Atom molecule) {
  switch (pattern.wildcard) {
    case '*':
      return true;
    case 'A':
      return !molecule.aromatic;
    case 'a':
      return molecule.aromatic;
  }
  return pattern.choices.any(
    (c) => c.symbol == molecule.symbol && c.aromatic == molecule.aromatic,
  );
}

bool bondMatches(Bond pattern, Bond molecule) =>
    pattern.match & (1 << molecule.type) != 0;
Molecule moleculePattern(Molecule m) {
  final p = Molecule();
  for (final a in m.atoms) {
    p.atoms.add(Atom(choices: [Choice(a.symbol, a.aromatic)]));
  }
  for (final b in m.bonds) {
    p.bonds.add(Bond(b.a, b.b, match: 1 << b.type));
  }
  p.build();
  return p;
}

class Embeddings {
  int count = 0, unique = 0;
  List<int>? first;
}

Embeddings embeddings(Molecule pattern, Molecule molecule) {
  final out = Embeddings();
  if (pattern.atoms.length > molecule.atoms.length) return out;
  final mapping = List.filled(pattern.atoms.length, -1),
      used = List.filled(molecule.atoms.length, false),
      sets = <BigInt>{};
  void search(int index) {
    if (index == pattern.atoms.length) {
      out.count++;
      out.first ??= [for (final a in mapping) a + 1];
      var mask = BigInt.zero;
      for (final a in mapping) {
        mask |= BigInt.one << a;
      }
      sets.add(mask);
      return;
    }
    for (var candidate = 0; candidate < molecule.atoms.length; candidate++) {
      final a = molecule.atoms[candidate];
      if (used[candidate] || !atomMatches(pattern.atoms[index], a)) continue;
      var valid = true;
      for (final e in pattern.adjacent[index]) {
        final b = pattern.bonds[e], other = b.other(index);
        if (other >= index) continue;
        final actual = molecule.bond(candidate, mapping[other]);
        if (actual == null || !bondMatches(b, actual)) {
          valid = false;
          break;
        }
      }
      if (valid) {
        mapping[index] = candidate;
        used[candidate] = true;
        search(index + 1);
        used[candidate] = false;
        mapping[index] = -1;
      }
    }
  }

  search(0);
  out.unique = sets.length;
  return out;
}

void fingerprint(Molecule m, Map<String, Element> elements) {
  final codes = [
        for (var i = 0; i < m.atoms.length; i++)
          16 * elements[m.atoms[i].symbol]!.number +
              (m.atoms[i].aromatic ? 8 : 0) +
              m.adjacent[i].length,
      ],
      visited = List.filled(m.atoms.length, false);
  void visit(int a, int depth, int hash) {
    m.paths++;
    m.bits[hash % 1024] = true;
    if (depth == 5) return;
    for (final e in m.adjacent[a]) {
      final b = m.bonds[e], next = b.other(a);
      if (visited[next]) continue;
      var value = (hash * 31 + b.type) % 1000003;
      value = (value * 31 + codes[next]) % 1000003;
      visited[next] = true;
      visit(next, depth + 1, value);
      visited[next] = false;
    }
  }

  for (var i = 0; i < m.atoms.length; i++) {
    visited[i] = true;
    visit(i, 0, codes[i]);
    visited[i] = false;
  }
  m.bitCount = m.bits.where((v) => v).length;
}

class Fraction {
  final int numerator, denominator;
  Fraction(this.numerator, this.denominator);
  int compare(Fraction b) =>
      (numerator * b.denominator).compareTo(b.numerator * denominator);
  @override
  String toString() => '$numerator/$denominator';
}

int gcd(int a, int b) {
  while (b != 0) {
    final r = a % b;
    a = b;
    b = r;
  }
  return a;
}

Fraction fraction(int n, int d) {
  final g = gcd(n, d);
  return Fraction(n ~/ g, d ~/ g);
}

class Similarity {
  final Fraction value;
  final int common, union;
  Similarity(this.value, this.common, this.union);
}

Similarity similarity(Molecule a, Molecule b) {
  var common = 0, union = 0;
  for (var i = 0; i < 1024; i++) {
    if (a.bits[i] && b.bits[i]) common++;
    if (a.bits[i] || b.bits[i]) union++;
  }
  return Similarity(fraction(common, union), common, union);
}
