import 'dart:io';

class Problem implements Exception {
  final String message;
  Problem(this.message);
}

Never fail(String message) => throw Problem(message);

class Rational implements Comparable<Rational> {
  final BigInt n, d;
  Rational._(this.n, this.d);
  factory Rational(BigInt n, [BigInt? denominator]) {
    var d = denominator ?? BigInt.one;
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final divisor = n.abs().gcd(d);
    return Rational._(n ~/ divisor, d ~/ divisor);
  }
  Rational operator +(Rational other) =>
      Rational(n * other.d + other.n * d, d * other.d);
  Rational operator -(Rational other) =>
      Rational(n * other.d - other.n * d, d * other.d);
  Rational operator *(Rational other) => Rational(n * other.n, d * other.d);
  Rational operator /(Rational other) => Rational(n * other.d, d * other.n);
  Rational operator -() => Rational(-n, d);
  @override
  int compareTo(Rational other) => (n * other.d).compareTo(other.n * d);
  bool get zero => n == BigInt.zero;
  bool get positive => n > BigInt.zero;
  @override
  String toString() => d == BigInt.one ? '$n' : '$n/$d';
  String value() {
    final million = BigInt.from(1000000), scaled = n.abs() * million ~/ d;
    return '$this (${n.isNegative ? '-' : ''}${scaled ~/ million}.${(scaled % million).toString().padLeft(6, '0')})';
  }
}

Rational rational(int value) => Rational(BigInt.from(value));
final zero = rational(0), one = rational(1);

Rational? readNumber(String word) {
  var text = word, multiplier = one;
  final multipliers = {
    'meg': rational(1000000),
    'k': rational(1000),
    'm': Rational(BigInt.one, BigInt.from(1000)),
    'u': Rational(BigInt.one, BigInt.from(1000000)),
  };
  for (final entry in multipliers.entries) {
    if (text.endsWith(entry.key)) {
      text = text.substring(0, text.length - entry.key.length);
      multiplier = entry.value;
      break;
    }
  }
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);
  if (!RegExp(r'^[0-9]+(?:\.[0-9]+|/[0-9]+)?$').hasMatch(text)) return null;
  BigInt numerator, denominator;
  if (text.contains('/')) {
    final parts = text.split('/');
    numerator = BigInt.parse(parts[0]);
    denominator = BigInt.parse(parts[1]);
    if (denominator == BigInt.zero) return null;
  } else if (text.contains('.')) {
    final parts = text.split('.');
    numerator = BigInt.parse(parts.join(''));
    denominator = BigInt.from(10).pow(parts[1].length);
  } else {
    numerator = BigInt.parse(text);
    denominator = BigInt.one;
  }
  return Rational(negative ? -numerator : numerator, denominator) * multiplier;
}

Rational numberCheck(String word) {
  final value = readNumber(word);
  if (value == null) fail('invalid value $word');
  return value;
}

bool validNode(String name) =>
    name == '0' || RegExp(r'^[a-z][a-z0-9]{0,7}$').hasMatch(name);

class Element {
  final String name;
  final List<String> terminals;
  final String? reference;
  Rational value;
  Element(this.name, this.terminals, this.reference, this.value);
}

bool voltageType(Element element) => 'VEH'.contains(element.name[0]);
bool independent(Element element) => 'VI'.contains(element.name[0]);
List<Rational> zeros(int count) => List<Rational>.filled(count, zero);
List<List<Rational>> matrix(int count) =>
    List.generate(count, (_) => zeros(count));

List<Rational>? solve(List<List<Rational>> a, List<Rational> b) {
  final n = a.length;
  final rows = List.generate(n, (i) => [...a[i], b[i]]);
  for (var k = 0; k < n; k++) {
    var r = k;
    while (r < n && rows[r][k].zero) {
      r++;
    }
    if (r == n) return null;
    final old = rows[k];
    rows[k] = rows[r];
    rows[r] = old;
    final pivot = rows[k][k];
    for (var j = 0; j <= n; j++) {
      rows[k][j] = rows[k][j] / pivot;
    }
    for (var i = 0; i < n; i++) {
      if (i != k && !rows[i][k].zero) {
        final factor = rows[i][k];
        for (var j = 0; j <= n; j++) {
          rows[i][j] = rows[i][j] - factor * rows[k][j];
        }
      }
    }
  }
  return rows.map((row) => row[n]).toList();
}

Set<String> reachable(String start, List<(String, String)> edges) {
  final seen = <String>{start}, pending = <String>[start];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    for (final (a, b) in edges) {
      final next = a == node
          ? b
          : b == node
          ? a
          : null;
      if (next != null && seen.add(next)) pending.add(next);
    }
  }
  return seen;
}

class Groups {
  final Map<String, String> parent;
  Groups(List<String> nodes) : parent = {for (final node in nodes) node: node};
  String find(String node) {
    final previous = parent[node]!;
    if (previous == node) return node;
    final root = find(previous);
    parent[node] = root;
    return root;
  }

  void join(String a, String b) {
    a = find(a);
    b = find(b);
    if (a == b) return;
    if (a.compareTo(b) < 0) {
      parent[b] = a;
    } else {
      parent[a] = b;
    }
  }
}

class Equations {
  final List<String> nodes;
  final List<Element> sources;
  final int count;
  final Map<String, int> nodeIndex, sourceIndex;
  final List<List<Rational>> a;
  final List<Rational> b;
  Equations(
    this.nodes,
    this.sources,
    this.count,
    this.nodeIndex,
    this.sourceIndex,
    this.a,
    this.b,
  );
}

class Edge {
  final String a, b;
  final Rational value;
  Edge(this.a, this.b, this.value);
}

class Resistor extends Edge {
  final String name;
  Resistor(this.name, super.a, super.b, super.value);
}

class Circuit {
  List<Element> elements = [];
  List<String> nodes({bool includeGround = false}) {
    final names = elements.expand((element) => element.terminals).toSet();
    if (includeGround) names.add('0');
    return names.toList()..sort();
  }

  List<String> circuitNodes() => nodes().where((node) => node != '0').toList();
  Element elementCheck(String name) {
    for (final element in elements) {
      if (element.name == name) return element;
    }
    fail('unknown element $name');
  }

  void nodeCheck(String name) {
    if (name != '0' && !circuitNodes().contains(name))
      fail('unknown node $name');
  }

  void add(List<String> words) {
    final name = words[0], type = words[0][0];
    if (!'RVIEGFH'.contains(type)) fail('unknown element type $name');
    final expected = 'EG'.contains(type)
        ? 6
        : 'FH'.contains(type)
        ? 5
        : 4;
    if (words.length != expected) fail('wrong field count for $name');
    if (elements.any((element) => element.name == name))
      fail('duplicate element $name');
    final terminals = words.sublist(1, 'EG'.contains(type) ? 5 : 3);
    for (final node in terminals) {
      if (!validNode(node)) fail('invalid node $node');
    }
    final reference = 'FH'.contains(type) ? words[3] : null;
    if (reference != null &&
        !elements.any(
          (element) => element.name == reference && element.name[0] == 'V',
        ))
      fail('unknown voltage source $reference');
    final value = numberCheck(words.last);
    if (type == 'R' && !value.positive) fail('nonpositive resistance $name');
    elements.add(Element(name, terminals, reference, value));
  }

  List<String> floating() {
    final edges = elements
        .where((element) => 'RVEH'.contains(element.name[0]))
        .map((element) => (element.terminals[0], element.terminals[1]))
        .toList();
    final seen = reachable('0', edges);
    return circuitNodes().where((node) => !seen.contains(node)).toList();
  }

  List<String> loops() {
    final groups = Groups(nodes(includeGround: true)), result = <String>[];
    for (final element in elements.where(voltageType)) {
      final a = element.terminals[0], b = element.terminals[1];
      if (groups.find(a) == groups.find(b)) result.add(element.name);
      groups.join(a, b);
    }
    return result;
  }

  void structure() {
    if (circuitNodes().isEmpty) fail('no nodes');
    final ungrounded = floating();
    if (ungrounded.isNotEmpty) fail('floating node ${ungrounded.first}');
    final cycles = loops();
    if (cycles.isNotEmpty) fail('voltage source loop at ${cycles.first}');
  }

  Equations equations([Map<String, Rational> overrides = const {}]) {
    final names = circuitNodes(),
        sources = elements.where(voltageType).toList();
    final count = names.length + sources.length;
    final nodeIndex = {for (var i = 0; i < names.length; i++) names[i]: i};
    final sourceIndex = {
      for (var i = 0; i < sources.length; i++)
        sources[i].name: names.length + i,
    };
    final a = matrix(count), b = zeros(count);
    int node(String name) => name == '0' ? -1 : nodeIndex[name]!;
    int source(String? name) => sourceIndex[name]!;
    void stamp(int row, int column, Rational value) {
      if (row >= 0 && column >= 0) a[row][column] = a[row][column] + value;
    }

    void rhs(int row, Rational value) {
      if (row >= 0) b[row] = b[row] + value;
    }

    for (final element in elements) {
      final terminals = element.terminals, type = element.name[0];
      final x = node(terminals[0]),
          y = node(terminals[1]),
          w = overrides[element.name] ?? element.value;
      if (type == 'R') {
        final g = one / w;
        stamp(x, x, g);
        stamp(y, y, g);
        stamp(x, y, -g);
        stamp(y, x, -g);
      } else if (type == 'I') {
        rhs(x, -w);
        rhs(y, w);
      } else if (type == 'G') {
        stamp(x, node(terminals[2]), w);
        stamp(y, node(terminals[3]), w);
        stamp(x, node(terminals[3]), -w);
        stamp(y, node(terminals[2]), -w);
      } else if (type == 'F') {
        stamp(x, source(element.reference), w);
        stamp(y, source(element.reference), -w);
      } else {
        final s = source(element.name);
        stamp(x, s, one);
        stamp(s, x, one);
        stamp(y, s, -one);
        stamp(s, y, -one);
        if (type == 'V') {
          rhs(s, w);
        } else if (type == 'E') {
          stamp(s, node(terminals[2]), -w);
          stamp(s, node(terminals[3]), w);
        } else {
          stamp(s, source(element.reference), -w);
        }
      }
    }
    return Equations(names, sources, count, nodeIndex, sourceIndex, a, b);
  }

  Rational potential(
    Equations equations,
    List<Rational> solution,
    String name,
  ) => name == '0' ? zero : solution[equations.nodeIndex[name]!];
  Rational sourceCurrent(
    Equations equations,
    List<Rational> solution,
    String? name,
  ) => solution[equations.sourceIndex[name]!];
  Rational current(
    Equations equations,
    List<Rational> solution,
    Element element,
  ) {
    final t = element.terminals, type = element.name[0];
    if (type == 'R')
      return (potential(equations, solution, t[0]) -
              potential(equations, solution, t[1])) /
          element.value;
    if (type == 'I') return element.value;
    if (type == 'G')
      return element.value *
          (potential(equations, solution, t[2]) -
              potential(equations, solution, t[3]));
    if (type == 'F')
      return element.value *
          sourceCurrent(equations, solution, element.reference);
    return sourceCurrent(equations, solution, element.name);
  }

  List<Rational> injection(Equations equations, String a, String b) {
    final column = zeros(equations.count);
    if (a != '0') {
      final i = equations.nodeIndex[a]!;
      column[i] = column[i] + one;
    }
    if (b != '0') {
      final i = equations.nodeIndex[b]!;
      column[i] = column[i] - one;
    }
    return solve(equations.a, column)!;
  }

  List<Rational> alone(Equations equations, Element element, bool unit) {
    final column = zeros(equations.count), value = unit ? one : element.value;
    if (element.name[0] == 'V') {
      column[equations.sourceIndex[element.name]!] = value;
    } else {
      final a = element.terminals[0], b = element.terminals[1];
      if (a != '0') {
        final i = equations.nodeIndex[a]!;
        column[i] = column[i] - value;
      }
      if (b != '0') {
        final i = equations.nodeIndex[b]!;
        column[i] = column[i] + value;
      }
    }
    return solve(equations.a, column)!;
  }

  List<String> resistance(String a, String b) {
    final groups = Groups(nodes(includeGround: true));
    for (final element in elements) {
      if (element.name[0] == 'V')
        groups.join(element.terminals[0], element.terminals[1]);
    }
    a = groups.find(a);
    b = groups.find(b);
    if (a == b) return ['Req = ${zero.value()}'];
    final edges = <Edge>[];
    for (final element in elements) {
      if (element.name[0] == 'R') {
        final x = groups.find(element.terminals[0]),
            y = groups.find(element.terminals[1]);
        if (x != y) edges.add(Edge(x, y, one / element.value));
      }
    }
    final seen = reachable(a, edges.map((edge) => (edge.a, edge.b)).toList());
    if (!seen.contains(b)) return ['Req = INFINITE'];
    final names = seen.where((name) => name != b).toList()..sort();
    final indices = {for (var i = 0; i < names.length; i++) names[i]: i};
    final g = matrix(names.length), column = zeros(names.length);
    void stamp(String row, String col, Rational value) {
      if (row != b && col != b) {
        final i = indices[row]!, j = indices[col]!;
        g[i][j] = g[i][j] + value;
      }
    }

    for (final edge in edges) {
      if (seen.contains(edge.a)) {
        stamp(edge.a, edge.a, edge.value);
        stamp(edge.b, edge.b, edge.value);
        stamp(edge.a, edge.b, -edge.value);
        stamp(edge.b, edge.a, -edge.value);
      }
    }
    column[indices[a]!] = one;
    return ['Req = ${solve(g, column)![indices[a]!].value()}'];
  }

  List<String> reduce(String a, String b) {
    if (a == b) return ['Req = ${zero.value()}'];
    var list = elements
        .where((element) => element.name[0] == 'R')
        .map(
          (element) => Resistor(
            element.name,
            element.terminals[0],
            element.terminals[1],
            element.value,
          ),
        )
        .toList();
    final connected = reachable(
      a,
      list.map((element) => (element.a, element.b)).toList(),
    );
    if (!connected.contains(b)) return ['Req = INFINITE'];
    list = list.where((element) => connected.contains(element.a)).toList();
    final output = <String>[];
    var serial = 0;
    while (true) {
      var remove = list.indexWhere((element) => element.a == element.b);
      if (remove >= 0) {
        output.add('remove ${list.removeAt(remove).name}');
        continue;
      }
      final degree = <String, int>{};
      for (final element in list) {
        for (final node in [element.a, element.b]) {
          degree[node] = (degree[node] ?? 0) + 1;
        }
      }
      final internal =
          degree.keys.where((node) => node != a && node != b).toList()..sort();
      String? dangling;
      for (final node in internal) {
        if (degree[node] == 1) {
          dangling = node;
          break;
        }
      }
      if (dangling != null) {
        remove = list.indexWhere(
          (element) => element.a == dangling || element.b == dangling,
        );
        output.add('remove ${list.removeAt(remove).name}');
        continue;
      }
      var first = -1, second = -1, parallel = false;
      search:
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final x = list[i], y = list[j];
          if (x.a == y.a && x.b == y.b || x.a == y.b && x.b == y.a) {
            first = i;
            second = j;
            parallel = true;
            break search;
          }
        }
      }
      String? center;
      if (!parallel) {
        for (final node in internal) {
          if (degree[node] == 2) {
            center = node;
            break;
          }
        }
        if (center == null) break;
        final indices = <int>[];
        for (var i = 0; i < list.length; i++) {
          if (list[i].a == center || list[i].b == center) indices.add(i);
        }
        first = indices[0];
        second = indices[1];
      }
      final x = list[first], y = list[second], name = '#${++serial}';
      final value = parallel
          ? x.value * y.value / (x.value + y.value)
          : x.value + y.value;
      final left = parallel
          ? x.a
          : x.a == center
          ? x.b
          : x.a;
      final right = parallel
          ? x.b
          : y.a == center
          ? y.b
          : y.a;
      output.add(
        '$name = ${x.name} ${parallel ? '||' : '+'} ${y.name} = ${value.value()}',
      );
      list.removeAt(second);
      list.removeAt(first);
      list.add(Resistor(name, left, right, value));
    }
    output.add(
      list.length == 1
          ? 'Req = ${list[0].value.value()}'
          : 'not series-parallel: ${list.length} resistors remain',
    );
    return output;
  }

  List<String> check() {
    final names = circuitNodes();
    if (names.isEmpty) return ['no nodes'];
    final output = <String>[];
    for (final node in names) {
      var degree = 0;
      for (final element in elements) {
        if (element.terminals[0] == node) degree++;
        if (element.terminals[1] == node) degree++;
      }
      if (degree < 2) output.add('dangling node $node');
    }
    for (final node in floating()) {
      output.add('floating node $node');
    }
    for (final name in loops()) {
      output.add('voltage source loop at $name');
    }
    if (output.isEmpty) {
      final eq = equations();
      if (solve(eq.a, eq.b) == null) output.add('singular matrix');
    }
    return output.isEmpty ? ['ok'] : output;
  }

  List<String> command(List<String> words) {
    final command = words[0], args = words.sublist(1);
    const counts = {
      '.OP': 0,
      '.CURRENT': 1,
      '.VOLTAGE': 2,
      '.POWER': 0,
      '.KCL': 1,
      '.THEVENIN': 2,
      '.NORTON': 2,
      '.MAXPOWER': 2,
      '.TF': 2,
      '.SENS': 1,
      '.ZPARAM': 4,
      '.SUPERPOSITION': 1,
      '.SWEEP': 5,
      '.MATRIX': 0,
      '.REQ': 2,
      '.REDUCE': 2,
      '.CHECK': 0,
      '.ALTER': 2,
      '.DELETE': 1,
      '.CLEAR': 0,
      '.NODES': 0,
      '.PRINT': 0,
    };
    if (!counts.containsKey(command)) fail('unknown command $command');
    if (args.length != counts[command])
      fail('wrong argument count for $command');
    if (command == '.CLEAR') {
      final count = elements.length;
      elements = [];
      return ['cleared $count elements'];
    }
    if (command == '.DELETE') {
      final element = elementCheck(args[0]);
      for (final user in elements) {
        if (user.reference == element.name)
          fail('${element.name} is referenced by ${user.name}');
      }
      elements.remove(element);
      return ['deleted ${element.name}'];
    }
    if (command == '.ALTER') {
      final element = elementCheck(args[0]), value = numberCheck(args[1]);
      if (element.name[0] == 'R' && !value.positive)
        fail('nonpositive resistance ${element.name}');
      final output = 'altered ${element.name}: ${element.value} -> $value';
      element.value = value;
      return [output];
    }
    if (command == '.NODES') {
      final names = nodes();
      return names.isEmpty
          ? ['no nodes']
          : names
                .map(
                  (node) =>
                      '$node: ${elements.where((element) => element.terminals.contains(node)).map((element) => element.name).join(' ')}',
                )
                .toList();
    }
    if (command == '.PRINT') {
      return elements.isEmpty
          ? ['empty netlist']
          : elements
                .map(
                  (element) => [
                    element.name,
                    ...element.terminals,
                    if (element.reference != null) element.reference!,
                    '${element.value}',
                  ].join(' '),
                )
                .toList();
    }
    if (command == '.CHECK') return check();
    if (command == '.SWEEP') {
      final element = elementCheck(args[0]);
      final from = numberCheck(args[1]),
          to = numberCheck(args[2]),
          step = numberCheck(args[3]);
      nodeCheck(args[4]);
      if (!step.positive) fail('invalid sweep step');
      if (from.compareTo(to) > 0) fail('invalid sweep range');
      final span = (to - from) / step, count = span.n ~/ span.d + BigInt.one;
      if (count > BigInt.from(20)) fail('too many sweep points');
      if (element.name[0] == 'R' && !from.positive)
        fail('nonpositive resistance ${element.name}');
      structure();
      final output = <String>[];
      for (var k = BigInt.zero; k < count; k += BigInt.one) {
        final value = from + step * Rational(k),
            eq = equations({element.name: value});
        final solution = solve(eq.a, eq.b);
        output.add(
          '${element.name} = $value: ${solution == null ? 'singular matrix' : 'V(${args[4]}) = ${potential(eq, solution, args[4]).value()}'}',
        );
      }
      return output;
    }
    if (command == '.REQ' || command == '.REDUCE') {
      nodeCheck(args[0]);
      nodeCheck(args[1]);
      return command == '.REQ'
          ? resistance(args[0], args[1])
          : reduce(args[0], args[1]);
    }
    Element? selected;
    if (command == '.CURRENT') {
      selected = elementCheck(args[0]);
    } else if (command == '.TF') {
      nodeCheck(args[0]);
      selected = elementCheck(args[1]);
      if (!independent(selected))
        fail('not an independent source ${selected.name}');
    } else if ([
      '.VOLTAGE',
      '.KCL',
      '.THEVENIN',
      '.NORTON',
      '.MAXPOWER',
      '.SENS',
      '.ZPARAM',
      '.SUPERPOSITION',
    ].contains(command)) {
      for (final node in args) {
        nodeCheck(node);
      }
    }
    structure();
    final eq = equations();
    if (command == '.MATRIX') {
      final labels = [
        ...eq.nodes,
        ...eq.sources.map((element) => element.name),
      ];
      return [
        'unknowns: ${[...eq.nodes.map((node) => 'V($node)'), ...eq.sources.map((element) => 'I(${element.name})')].join(' ')}',
        for (var i = 0; i < labels.length; i++)
          '${labels[i]}: ${eq.a[i].join(' ')} | ${eq.b[i]}',
      ];
    }
    final solution = solve(eq.a, eq.b);
    if (solution == null) fail('singular matrix');
    Rational voltage(String name, [List<Rational>? values]) =>
        potential(eq, values ?? solution, name);
    final output = <String>[];
    if (command == '.OP') {
      for (final node in eq.nodes) {
        output.add('V($node) = ${voltage(node).value()}');
      }
      for (final element in eq.sources) {
        output.add(
          'I(${element.name}) = ${sourceCurrent(eq, solution, element.name).value()}',
        );
      }
    } else if (command == '.CURRENT') {
      final element = selected!;
      output.add(
        'I(${element.name}) = ${current(eq, solution, element).value()}',
      );
    } else if (command == '.VOLTAGE') {
      output.add(
        'V(${args[0]},${args[1]}) = ${(voltage(args[0]) - voltage(args[1])).value()}',
      );
    } else if (command == '.POWER') {
      var absorbed = zero, delivered = zero, total = zero;
      for (final element in elements) {
        final power =
            (voltage(element.terminals[0]) - voltage(element.terminals[1])) *
            current(eq, solution, element);
        output.add('P(${element.name}) = ${power.value()}');
        if (power.positive) {
          absorbed = absorbed + power;
        } else if (!power.zero) {
          delivered = delivered - power;
        }
        total = total + power;
      }
      output.addAll([
        'absorbed = ${absorbed.value()}',
        'delivered = ${delivered.value()}',
        'total = ${total.value()}',
      ]);
    } else if (command == '.KCL') {
      var sum = zero;
      for (final element in elements) {
        if (element.terminals[0] == args[0] ||
            element.terminals[1] == args[0]) {
          final value = element.terminals[0] == element.terminals[1]
              ? zero
              : element.terminals[0] == args[0]
              ? current(eq, solution, element)
              : -current(eq, solution, element);
          output.add(
            'I(${element.name}) leaving ${args[0]} = ${value.value()}',
          );
          sum = sum + value;
        }
      }
      output.add('sum = ${sum.value()}');
    } else if (['.THEVENIN', '.NORTON', '.MAXPOWER'].contains(command)) {
      final value = voltage(args[0]) - voltage(args[1]),
          z = injection(eq, args[0], args[1]);
      final resistance = voltage(args[0], z) - voltage(args[1], z);
      if (command == '.THEVENIN') {
        output.addAll([
          'Vth = ${value.value()}',
          'Rth = ${resistance.value()}',
        ]);
      } else if (command == '.NORTON') {
        if (resistance.zero) fail('zero thevenin resistance');
        output.addAll([
          'In = ${(value / resistance).value()}',
          'Rn = ${resistance.value()}',
        ]);
      } else {
        if (!resistance.positive) fail('nonpositive thevenin resistance');
        output.addAll([
          'RL = ${resistance.value()}',
          'Pmax = ${(value * value / (rational(4) * resistance)).value()}',
        ]);
      }
    } else if (command == '.TF') {
      final source = selected!;
      final z = alone(eq, source, true);
      output.add('gain = ${voltage(args[0], z).value()}');
      if (source.name[0] == 'V') {
        final value = sourceCurrent(eq, z, source.name);
        output.add(
          'input resistance = ${value.zero ? 'INFINITE' : (-one / value).value()}',
        );
      } else {
        output.add(
          'input resistance = ${(voltage(source.terminals[1], z) - voltage(source.terminals[0], z)).value()}',
        );
      }
      output.add(
        'output resistance = ${voltage(args[0], injection(eq, args[0], '0')).value()}',
      );
    } else if (command == '.SENS') {
      for (final element in elements) {
        final column = zeros(eq.count),
            t = element.terminals,
            type = element.name[0];
        void addNode(String node, Rational value) {
          if (node != '0') {
            final i = eq.nodeIndex[node]!;
            column[i] = column[i] + value;
          }
        }

        if (type == 'R') {
          final value = current(eq, solution, element) / element.value;
          addNode(t[0], value);
          addNode(t[1], -value);
        } else if (type == 'I') {
          addNode(t[0], -one);
          addNode(t[1], one);
        } else if (type == 'G' || type == 'F') {
          final value = type == 'G'
              ? voltage(t[2]) - voltage(t[3])
              : sourceCurrent(eq, solution, element.reference);
          addNode(t[0], -value);
          addNode(t[1], value);
        } else {
          column[eq.sourceIndex[element.name]!] = type == 'V'
              ? one
              : type == 'E'
              ? voltage(t[2]) - voltage(t[3])
              : sourceCurrent(eq, solution, element.reference);
        }
        output.add(
          'dV(${args[0]})/d${element.name} = ${voltage(args[0], solve(eq.a, column)!).value()}',
        );
      }
    } else if (command == '.ZPARAM') {
      final first = injection(eq, args[0], args[1]),
          second = injection(eq, args[2], args[3]);
      output.addAll([
        'z11 = ${(voltage(args[0], first) - voltage(args[1], first)).value()}',
        'z12 = ${(voltage(args[0], second) - voltage(args[1], second)).value()}',
        'z21 = ${(voltage(args[2], first) - voltage(args[3], first)).value()}',
        'z22 = ${(voltage(args[2], second) - voltage(args[3], second)).value()}',
      ]);
    } else if (command == '.SUPERPOSITION') {
      var total = zero;
      for (final element in elements.where(independent)) {
        final value = voltage(args[0], alone(eq, element, false));
        output.add('${element.name}: V(${args[0]}) = ${value.value()}');
        total = total + value;
      }
      output.add('total: V(${args[0]}) = ${total.value()}');
    }
    return output;
  }
}

void main() {
  final circuit = Circuit(), output = <String>[];
  var lineNumber = 0;
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    final input = line!;
    lineNumber++;
    if (input == '.END') break;
    if (input.startsWith('*')) continue;
    final words = input.split(' ');
    try {
      if (input.startsWith('.')) {
        output.addAll(circuit.command(words));
      } else {
        circuit.add(words);
      }
    } on Problem catch (error) {
      output.add('error: line $lineNumber: ${error.message}');
    }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
