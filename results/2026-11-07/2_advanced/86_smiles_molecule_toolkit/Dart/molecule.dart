part of 'main.dart';

class Element {
  final String symbol;
  final int number, weight;
  final List<int> valences;
  Element(this.symbol, this.number, this.weight, this.valences);
}

class Choice {
  final String symbol;
  final bool aromatic;
  Choice(this.symbol, this.aromatic);
}

class Atom {
  final String symbol, wildcard;
  final bool aromatic, bracket;
  final int mass, charge;
  int hydrogens, column;
  final List<Choice> choices;
  Atom({
    this.symbol = '',
    this.aromatic = false,
    this.mass = 0,
    this.charge = 0,
    this.hydrogens = 0,
    this.column = 0,
    this.bracket = false,
    this.choices = const [],
    this.wildcard = '',
  });
}

class Bond {
  final int a, b;
  final String symbol;
  int type, multiplicity, match;
  bool ring;
  Bond(
    this.a,
    this.b, {
    this.symbol = '',
    this.type = 0,
    this.multiplicity = 0,
    this.match = 0,
    this.ring = false,
  });
  int other(int atom) => atom == a ? b : a;
}

class Molecule {
  String name = '', canonical = '', scaffold = '', formula = '', lipinski = '';
  final List<Atom> atoms = [];
  final List<Bond> bonds = [];
  List<List<int>> adjacent = [];
  final List<List<int>> rings = [];
  List<bool> ringAtoms = [];
  List<int> ranks = [];
  int classes = 0,
      weight = 0,
      heavy = 0,
      rotatable = 0,
      donors = 0,
      acceptors = 0,
      charge = 0,
      bitCount = 0,
      paths = 0;
  final List<bool> bits = List.filled(1024, false);
  void build() {
    bonds.sort((a, b) {
      final c = a.a.compareTo(b.a);
      return c != 0 ? c : a.b.compareTo(b.b);
    });
    adjacent = List.generate(atoms.length, (_) => <int>[]);
    for (var i = 0; i < bonds.length; i++) {
      final b = bonds[i];
      adjacent[b.a].add(i);
      adjacent[b.b].add(i);
    }
    for (var a = 0; a < atoms.length; a++) {
      adjacent[a].sort(
        (i, j) => bonds[i].other(a).compareTo(bonds[j].other(a)),
      );
    }
  }

  Bond? bond(int a, int b) {
    for (final e in adjacent[a]) {
      final bond = bonds[e];
      if (bond.other(a) == b) return bond;
    }
    return null;
  }

  int base(int a) {
    var sum = 0;
    for (final e in adjacent[a]) {
      final type = bonds[e].type;
      sum += type == 4 ? 1 : type;
    }
    return sum;
  }

  int multiplicity(int a) {
    var sum = 0;
    for (final e in adjacent[a]) {
      sum += bonds[e].multiplicity;
    }
    return sum;
  }

  bool needsPi(int a, Map<String, Element> elements, bool hydrogens) {
    final atom = atoms[a];
    return atom.aromatic &&
        elements[atom.symbol]!.valences.first + atom.charge >=
            base(a) + (hydrogens ? atom.hydrogens : 0) + 1;
  }
}

(int, bool) organicHydrogens(Molecule m, int a, Map<String, Element> elements) {
  final b = m.multiplicity(a);
  for (final v in elements[m.atoms[a].symbol]!.valences) {
    if (v >= b) return (v - b, true);
  }
  return (0, false);
}

class ParseError {
  final String reason;
  final int column;
  ParseError(this.reason, this.column);
}

List<String> lines(String path) => File(path).readAsLinesSync();
bool ignored(String s) => s.isEmpty || s.startsWith('#');
Map<String, Element> readElements() {
  final out = <String, Element>{};
  for (final line in lines('input/elements.txt')) {
    if (ignored(line)) continue;
    final a = line.split(' ');
    out[a[0]] = Element(
      a[0],
      int.parse(a[1]),
      int.parse(a[2]),
      a[3].split(',').map(int.parse).toList(),
    );
  }
  return out;
}
