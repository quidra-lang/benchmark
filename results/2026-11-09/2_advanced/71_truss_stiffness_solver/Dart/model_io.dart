part of 'main.dart';

class Node {
  final int id, x, y;
  Node(this.id, this.x, this.y);
}

class Member {
  final int id, i, j, section, material, group;
  double length = 0, c = 0, s = 0;
  List<int> dofs = [];
  Member(this.id, this.i, this.j, this.section, this.material, this.group);
}

class Section {
  final String name;
  final double area, inertia;
  Section(this.name, this.area, this.inertia);
}

class Material {
  final String name;
  final double e, fy, rho, alpha;
  Material(this.name, this.e, this.fy, this.rho, this.alpha);
}

class Support {
  final int node;
  final List<bool> fixed;
  final List<double> prescribed;
  Support(this.node, this.fixed, this.prescribed);
}

class LoadLine {
  final String kind;
  final int item;
  final double x, y;
  LoadLine(this.kind, [this.item = 0, this.x = 0, this.y = 0]);
}

class LoadCase {
  final String name;
  final List<LoadLine> lines = [];
  LoadCase(this.name);
}

class Term {
  final int caseIndex;
  final double factor;
  Term(this.caseIndex, this.factor);
}

class Combination {
  final String name;
  final List<Term> terms = [];
  Combination(this.name);
}

class Axle {
  final int offset;
  final double force;
  Axle(this.offset, this.force);
}

class Drawing {
  final int result, scale, wc, hc;
  Drawing(this.result, this.scale, this.wc, this.hc);
}

class Settings {
  final List<int> deck = [], influence = [];
  int step = 0,
      rating = 0,
      deflection = 0,
      ratio = 0,
      vibration = 0,
      modes = 0,
      iterations = 0,
      removal = 0,
      mapWC = 0,
      mapHC = 0;
  final List<Axle> axles = [];
  double gammaD = 0, gammaL = 0, compression = 0, tension = 0;
  final List<Drawing> drawings = [];
}

class Model {
  final List<Node> nodes = [];
  final List<Member> members = [];
  final List<Section> sections = [];
  final List<Material> materials = [];
  final List<Support> supports = [];
  final List<LoadCase> cases = [];
  final List<Combination> combinations = [];
  final List<String> groups = [];
  final Settings settings = Settings();
  List<int> order = [], number = [], free = [], restrained = [], dofNode = [];
  List<double> prescribed = [];
}

List<List<String>> csvRows(String name) => File(
  'input/$name.csv',
).readAsLinesSync().skip(1).map((s) => s.split(',')).toList();
Model readModel() {
  final m = Model(),
      nodes = <int, int>{},
      members = <int, int>{},
      sections = <String, int>{},
      materials = <String, int>{},
      groups = <String, int>{};
  for (final a in csvRows('nodes')) {
    nodes[int.parse(a[0])] = m.nodes.length;
    m.nodes.add(Node(int.parse(a[0]), int.parse(a[1]), int.parse(a[2])));
  }
  for (final a in csvRows('sections')) {
    sections[a[0]] = m.sections.length;
    m.sections.add(Section(a[0], double.parse(a[1]), double.parse(a[2])));
  }
  for (final a in csvRows('materials')) {
    materials[a[0]] = m.materials.length;
    m.materials.add(
      Material(
        a[0],
        double.parse(a[1]),
        double.parse(a[2]),
        double.parse(a[3]),
        double.parse(a[4]),
      ),
    );
  }
  for (final a in csvRows('members')) {
    var group = groups[a[5]];
    if (group == null) {
      group = m.groups.length;
      groups[a[5]] = group;
      m.groups.add(a[5]);
    }
    members[int.parse(a[0])] = m.members.length;
    m.members.add(
      Member(
        int.parse(a[0]),
        nodes[int.parse(a[1])]!,
        nodes[int.parse(a[2])]!,
        sections[a[3]]!,
        materials[a[4]]!,
        group,
      ),
    );
  }
  for (final a in csvRows('supports')) {
    m.supports.add(
      Support(
        nodes[int.parse(a[0])]!,
        [a[1] == '1', a[2] == '1'],
        [double.parse(a[3]), double.parse(a[4])],
      ),
    );
  }
  final caseIndex = <String, int>{}, resultIndex = <String, int>{};
  for (final line in File('input/loads.txt').readAsLinesSync()) {
    final a = line.split(' ');
    if (a[0] == 'LOADCASE') {
      caseIndex[a[1]] = m.cases.length;
      resultIndex[a[1]] = m.cases.length;
      m.cases.add(LoadCase(a[1]));
    } else if (a[0] == 'END') {
      continue;
    } else if (a[0] == 'COMBINATION') {
      final combo = Combination(a[1]);
      for (var i = 2; i < a.length; i += 2) {
        combo.terms.add(Term(caseIndex[a[i]]!, double.parse(a[i + 1])));
      }
      resultIndex[a[1]] = m.cases.length + m.combinations.length;
      m.combinations.add(combo);
    } else {
      var load = LoadLine(a[0]);
      if (a[0] == 'FORCE')
        load = LoadLine(
          a[0],
          nodes[int.parse(a[1])]!,
          double.parse(a[2]),
          double.parse(a[3]),
        );
      if (a[0] == 'TEMPERATURE')
        load = LoadLine(a[0], members[int.parse(a[1])]!, double.parse(a[2]));
      m.cases.last.lines.add(load);
    }
  }
  final p = m.settings;
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'deck':
        p.deck.addAll(a.skip(1).map((s) => nodes[int.parse(s)]!));
        break;
      case 'influence':
        p.influence.add(members[int.parse(a[1])]!);
        break;
      case 'vehicle':
        p.step = int.parse(a[1]);
        for (var i = 2; i < a.length; i += 2) {
          p.axles.add(Axle(int.parse(a[i]), double.parse(a[i + 1])));
        }
        break;
      case 'rating':
        p.rating = resultIndex[a[1]]!;
        p.gammaD = double.parse(a[2]);
        p.gammaL = double.parse(a[3]);
        break;
      case 'slenderness':
        p.compression = double.parse(a[1]);
        p.tension = double.parse(a[2]);
        break;
      case 'deflection':
        p.deflection = resultIndex[a[1]]!;
        p.ratio = int.parse(a[2]);
        break;
      case 'vibration':
        p.vibration = caseIndex[a[1]]!;
        p.modes = int.parse(a[2]);
        p.iterations = int.parse(a[3]);
        break;
      case 'removal':
        p.removal = resultIndex[a[1]]!;
        break;
      case 'drawing':
        p.drawings.add(
          Drawing(
            resultIndex[a[1]]!,
            int.parse(a[2]),
            int.parse(a[3]),
            int.parse(a[4]),
          ),
        );
        break;
      case 'utilization_map':
        p.mapWC = int.parse(a[1]);
        p.mapHC = int.parse(a[2]);
        break;
    }
  }
  return m;
}
