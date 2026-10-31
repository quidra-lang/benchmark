import 'dart:io';
import 'dart:math' as math;

final class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

Never fail(String message) => throw CommandError(message);

final class Rational implements Comparable<Rational> {
  final int p, q;
  factory Rational(int p, [int q = 1]) {
    if (q == 0) fail('division by zero');
    if (q < 0) {
      p = -p;
      q = -q;
    }
    final g = p.gcd(q);
    return Rational._(p ~/ g, q ~/ g);
  }
  const Rational._(this.p, this.q);
  Rational operator +(Rational b) => Rational(p * b.q + b.p * q, q * b.q);
  Rational operator *(Rational b) => Rational(p * b.p, q * b.q);
  Rational operator -() => Rational(-p, q);
  @override
  int compareTo(Rational b) => (p * b.q).compareTo(b.p * q);
  @override
  bool operator ==(Object b) => b is Rational && p == b.p && q == b.q;
  @override
  int get hashCode => Object.hash(p, q);
}

enum Kind { variable, sum, product, power, function, number }

final class Expr {
  final Kind kind;
  final Rational value;
  final String name;
  final List<Expr> args;
  Expr(this.kind, this.value, this.name, this.args);
}

Expr number(Rational q) => Expr(Kind.number, q, '', []);
Expr num(int p, [int q = 1]) => number(Rational(p, q));
Expr node(Kind k, List<Expr> a, [String s = '']) => Expr(k, Rational(0), s, a);
final zero = num(0), one = num(1), minus = num(-1), half = num(1, 2);
const functions = {'sin', 'cos', 'tan', 'exp', 'ln', 'sqrt'};
int compare(Expr a, Expr b) {
  if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
  if (a.kind == Kind.number) return a.value.compareTo(b.value);
  final c = a.name.compareTo(b.name);
  if (c != 0) return c;
  for (var i = 0; i < math.min(a.args.length, b.args.length); i++) {
    final c = compare(a.args[i], b.args[i]);
    if (c != 0) return c;
  }
  return a.args.length.compareTo(b.args.length);
}

bool equal(Expr a, Expr b) => compare(a, b) == 0;
bool integer(Expr f) => f.kind == Kind.number && f.value.q == 1;
bool negative(Expr f) =>
    f.kind == Kind.power &&
    f.args[1].kind == Kind.number &&
    f.args[1].value.p < 0;
Expr base(Expr f) => f.kind == Kind.power ? f.args[0] : f;
Expr exponent(Expr f) => f.kind == Kind.power ? f.args[1] : one;
(Rational, List<Expr>) coefficient(Expr f) {
  if (f.kind == Kind.number) return (f.value, []);
  if (f.kind == Kind.product)
    return f.args[0].kind == Kind.number
        ? (f.args[0].value, f.args.sublist(1))
        : (Rational(1), f.args);
  return (Rational(1), [f]);
}

Expr product(Rational c, List<Expr> a) {
  if (a.isEmpty) return number(c);
  if (c != Rational(1)) a = [number(c), ...a];
  return a.length == 1 ? a[0] : node(Kind.product, a);
}

int exponentCompare(Expr a, Expr b) {
  if (a.kind == Kind.number && b.kind != Kind.number) return -1;
  if (a.kind != Kind.number && b.kind == Kind.number) return 1;
  return compare(a, b);
}

int termCompare(Expr a, Expr b) {
  final x = coefficient(a).$2, y = coefficient(b).$2, bases = <Expr>[];
  for (final t in [...x, ...y]) {
    final b = base(t);
    if (!bases.any((s) => equal(s, b))) bases.add(b);
  }
  bases.sort(compare);
  for (final b in bases) {
    var u = zero, v = zero;
    for (final t in x) {
      if (equal(base(t), b)) u = exponent(t);
    }
    for (final t in y) {
      if (equal(base(t), b)) v = exponent(t);
    }
    final c = exponentCompare(v, u);
    if (c != 0) return c;
  }
  return 0;
}

bool sameList(List<Expr> a, List<Expr> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => equal(a[i], b[i])).every((v) => v);
Expr add(List<Expr> operands) {
  final terms = <Expr>[];
  for (final f in operands) {
    if (f.kind == Kind.sum) {
      terms.addAll(f.args);
    } else if (f.kind == Kind.product &&
        f.args.length == 2 &&
        f.args[0].kind == Kind.number &&
        f.args[1].kind == Kind.sum) {
      for (final t in f.args[1].args) {
        terms.add(mul([f.args[0], t]));
      }
    } else {
      terms.add(f);
    }
  }
  final keys = <List<Expr>>[], values = <Rational>[];
  for (final f in terms) {
    final (c, m) = coefficient(f);
    final i = keys.indexWhere((a) => sameList(a, m));
    if (i < 0) {
      keys.add(m);
      values.add(c);
    } else {
      values[i] = values[i] + c;
    }
  }
  final built = [
    for (var i = 0; i < keys.length; i++)
      if (values[i].p != 0) product(values[i], keys[i]),
  ]..sort(termCompare);
  return built.isEmpty
      ? zero
      : built.length == 1
      ? built[0]
      : node(Kind.sum, built);
}

Expr mul(List<Expr> operands) {
  var c = Rational(1);
  final bases = <Expr>[], groups = <List<Expr>>[];
  for (final f in operands.expand(
    (t) => t.kind == Kind.product ? t.args : [t],
  )) {
    if (f.kind == Kind.number) {
      c = c * f.value;
    } else {
      final b = base(f);
      var i = bases.indexWhere((t) => equal(t, b));
      if (i < 0) {
        bases.add(b);
        groups.add([]);
        i = groups.length - 1;
      }
      groups[i].add(f);
    }
  }
  if (c.p == 0) return zero;
  final r = [
    for (var i = 0; i < groups.length; i++)
      groups[i].length == 1
          ? groups[i][0]
          : power(bases[i], add(groups[i].map(exponent).toList())),
  ];
  var regroup = r.any((f) => f.kind == Kind.number || f.kind == Kind.product);
  for (var i = 0; i < r.length; i++) {
    for (var j = 0; j < i; j++) {
      if (equal(base(r[i]), base(r[j]))) regroup = true;
    }
  }
  if (regroup) return mul([number(c), ...r]);
  r.sort((a, b) => compare(base(a), base(b)));
  return product(c, r);
}

int? root(int v, int d) {
  if (v == 1) return 1;
  if (d > 20) return null;
  final r = math.pow(v, 1 / d).round();
  for (var s = math.max(0, r - 1); s <= r + 1; s++) {
    var a = 1;
    for (var i = 0; i < d && a <= v; i++) {
      a *= s;
    }
    if (a == v) return s;
  }
  return null;
}

Expr rationalPower(Rational b, int n) {
  if (n < 0) {
    b = Rational(b.q, b.p);
    n = -n;
  }
  var r = Rational(1);
  while (n > 0) {
    if (n.isOdd) r = r * b;
    n = n ~/ 2;
    if (n > 0) b = b * b;
  }
  return number(r);
}

Expr power(Expr b, Expr x) {
  if (equal(x, zero)) return one;
  if (equal(x, one)) return b;
  if (b.kind == Kind.number) {
    if (equal(b, one)) return one;
    if (x.kind != Kind.number) return node(Kind.power, [b, x]);
    if (b.value.p == 0) {
      if (x.value.p > 0) return zero;
      fail('division by zero');
    }
    if (integer(x)) return rationalPower(b.value, x.value.p);
    if (b.value.p > 0) {
      final s = root(b.value.p, x.value.q), t = root(b.value.q, x.value.q);
      if (s != null && t != null)
        return rationalPower(Rational(s, t), x.value.p);
    }
  } else if (integer(x)) {
    if (b.kind == Kind.power) return power(b.args[0], mul([b.args[1], x]));
    if (b.kind == Kind.product)
      return mul(b.args.map((f) => power(f, x)).toList());
  }
  return node(Kind.power, [b, x]);
}

Expr fn(String s, Expr a) {
  if (s == 'sqrt') return power(a, half);
  if (equal(a, zero) && {'sin', 'tan'}.contains(s)) return zero;
  if (equal(a, zero) && {'cos', 'exp'}.contains(s)) return one;
  if (equal(a, one) && s == 'ln') return zero;
  if ({'sin', 'cos', 'tan'}.contains(s) && coefficient(a).$1.p < 0) {
    final r = fn(s, mul([minus, a]));
    return s == 'cos' ? r : mul([minus, r]);
  }
  if (a.kind == Kind.function &&
      ((s == 'exp' && a.name == 'ln') || (s == 'ln' && a.name == 'exp')))
    return a.args[0];
  return node(Kind.function, [a], s);
}

List<String> variables(Expr f) {
  final r = <String>{if (f.kind == Kind.variable) f.name};
  for (final a in f.args) {
    r.addAll(variables(a));
  }
  return r.toList()..sort();
}

Expr derivative(Expr f, String v) {
  if (f.kind == Kind.number) return zero;
  if (f.kind == Kind.variable) return f.name == v ? one : zero;
  if (f.kind == Kind.sum)
    return add(f.args.map((t) => derivative(t, v)).toList());
  if (f.kind == Kind.product)
    return add([
      for (var i = 0; i < f.args.length; i++)
        mul([
          for (var j = 0; j < f.args.length; j++)
            i == j ? derivative(f.args[j], v) : f.args[j],
        ]),
    ]);
  if (f.kind == Kind.power) {
    final b = f.args[0], x = f.args[1];
    if (!variables(x).contains(v))
      return mul([
        x,
        power(b, add([x, minus])),
        derivative(b, v),
      ]);
    if (!variables(b).contains(v))
      return mul([f, fn('ln', b), derivative(x, v)]);
    return mul([
      f,
      add([
        mul([derivative(x, v), fn('ln', b)]),
        mul([x, derivative(b, v), power(b, minus)]),
      ]),
    ]);
  }
  final a = f.args[0],
      h = switch (f.name) {
        'sin' => fn('cos', a),
        'cos' => mul([minus, fn('sin', a)]),
        'tan' => power(fn('cos', a), num(-2)),
        'exp' => f,
        _ => power(a, minus),
      };
  return mul([h, derivative(a, v)]);
}

Expr rebuild(Expr f, List<Expr> a) => switch (f.kind) {
  Kind.sum => add(a),
  Kind.product => mul(a),
  Kind.power => power(a[0], a[1]),
  _ => fn(f.name, a[0]),
};
Expr substitute(Expr f, Map<String, Expr> m) {
  if (f.kind == Kind.variable) return m[f.name] ?? f;
  if (f.kind == Kind.number) return f;
  return rebuild(f, f.args.map((t) => substitute(t, m)).toList());
}

List<Expr> terms(Expr f) => f.kind == Kind.sum ? f.args : [f];
Expr distribute(Expr a, Expr b) => add([
  for (final x in terms(a))
    for (final y in terms(b)) mul([x, y]),
]);
Expr expand(Expr f) {
  if (f.kind == Kind.variable || f.kind == Kind.number) return f;
  final a = f.args.map(expand).toList();
  if (f.kind == Kind.product) return a.reduce(distribute);
  if (f.kind == Kind.power &&
      a[0].kind == Kind.sum &&
      integer(a[1]) &&
      a[1].value.p > 0) {
    var r = a[0];
    for (var i = 1; i < a[1].value.p; i++) {
      r = distribute(r, a[0]);
    }
    return r;
  }
  return rebuild(f, a);
}

double numeric(Expr f) {
  if (f.kind == Kind.number) return f.value.p / f.value.q;
  if (f.kind == Kind.sum) return f.args.fold(0.0, (r, t) => r + numeric(t));
  if (f.kind == Kind.product) return f.args.fold(1.0, (r, t) => r * numeric(t));
  if (f.kind == Kind.power) {
    final u = numeric(f.args[0]), z = numeric(f.args[1]);
    final integral = f.args[1].kind == Kind.number
        ? integer(f.args[1])
        : z == z.truncateToDouble();
    if (u < 0 && !integral) fail('domain error');
    return equal(f.args[1], half) ? math.sqrt(u) : math.pow(u, z).toDouble();
  }
  final a = numeric(f.args[0]);
  if (f.name == 'ln' && a <= 0) fail('domain error');
  return switch (f.name) {
    'sin' => math.sin(a),
    'cos' => math.cos(a),
    'tan' => math.tan(a),
    'exp' => math.exp(a),
    _ => math.log(a),
  };
}

bool atomic(Expr f) =>
    f.kind == Kind.variable ||
    f.kind == Kind.function ||
    (integer(f) && f.value.p >= 0) ||
    (f.kind == Kind.power && equal(f.args[1], half));
String atom(Expr f) => atomic(f) ? show(f) : '(${show(f)})';
String showPower(Expr b, Expr x) =>
    equal(x, half) ? 'sqrt(${show(b)})' : '${atom(b)}^${atom(x)}';
String factor(Expr f) => f.kind == Kind.sum
    ? '(${show(f)})'
    : f.kind == Kind.power
    ? showPower(f.args[0], f.args[1])
    : show(f);
String quotient(Rational c, List<Expr> a) {
  final top = <String>[if (c.p.abs() != 1) '${c.p.abs()}'],
      bottom = <String>[if (c.q != 1) '${c.q}'];
  for (final f in a) {
    if (negative(f)) {
      final r = number(-f.args[1].value);
      bottom.add(equal(r, one) ? factor(f.args[0]) : showPower(f.args[0], r));
    } else {
      top.add(factor(f));
    }
  }
  var s = top.isEmpty ? '1' : top.join('*');
  if (bottom.length == 1) {
    s += '/' + bottom[0];
  } else if (bottom.isNotEmpty) {
    s += '/(${bottom.join('*')})';
  }
  return (c.p < 0 ? '-' : '') + s;
}

String show(Expr f) {
  if (f.kind == Kind.number)
    return '${f.value.p}' + (f.value.q == 1 ? '' : '/${f.value.q}');
  if (f.kind == Kind.variable) return f.name;
  if (f.kind == Kind.function) return '${f.name}(${show(f.args[0])})';
  if (f.kind == Kind.power)
    return negative(f)
        ? quotient(Rational(1), [f])
        : showPower(f.args[0], f.args[1]);
  if (f.kind == Kind.product) {
    final (c, a) = coefficient(f);
    return quotient(c, a);
  }
  return f.args
      .map(show)
      .reduce(
        (a, b) => a + (b.startsWith('-') ? ' - ' + b.substring(1) : ' + ' + b),
      );
}

final class Syntax {
  final String op;
  final Expr? value;
  final List<Syntax> args;
  Syntax(this.op, this.value, [this.args = const []]);
}

final class Parser {
  final Map<String, Expr> names;
  final tokens = <String>[];
  int position = 0;
  Parser(String text, this.names) {
    for (final m in RegExp(
      r'[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*/^()]| +|.',
    ).allMatches(text)) {
      final t = m[0]!;
      if (t.startsWith(' ')) continue;
      if (!RegExp(r'^[a-zA-Z0-9+*/^()-]+$').hasMatch(t))
        fail("invalid character '$t'");
      tokens.add(t);
    }
  }
  String get peek => position < tokens.length ? tokens[position] : '';
  Never unexpected() => fail(
    position == tokens.length
        ? 'unexpected end of expression'
        : "unexpected '$peek'",
  );
  bool accept(String s) {
    if (peek != s) return false;
    position++;
    return true;
  }

  void expect(String s) {
    if (!accept(s)) unexpected();
  }

  Syntax atomTree() {
    final t = peek;
    if (t.isEmpty) unexpected();
    if (accept('(')) {
      final a = expression();
      expect(')');
      return a;
    }
    if (!RegExp(r'^[a-zA-Z0-9]').hasMatch(t)) unexpected();
    position++;
    if (RegExp(r'^[0-9]').hasMatch(t)) return Syntax('', num(int.parse(t)));
    if (RegExp(r'^[A-Z]').hasMatch(t)) {
      if (!names.containsKey(t)) fail("undefined name '$t'");
      return Syntax('', names[t]!);
    }
    if (!functions.contains(t)) return Syntax('', node(Kind.variable, [], t));
    expect('(');
    final a = expression();
    expect(')');
    return Syntax(t, null, [a]);
  }

  Syntax unary() {
    if (accept('-')) return Syntax('neg', null, [unary()]);
    final a = atomTree();
    return accept('^') ? Syntax('^', null, [a, unary()]) : a;
  }

  Syntax term() {
    var a = unary();
    while (peek == '*' || peek == '/') {
      final op = tokens[position++];
      a = Syntax(op, null, [a, unary()]);
    }
    return a;
  }

  Syntax expression() {
    var a = term();
    while (peek == '+' || peek == '-') {
      final op = tokens[position++];
      a = Syntax(op, null, [a, term()]);
    }
    return a;
  }

  Expr evaluate(Syntax t) {
    if (t.value != null) return t.value!;
    final a = t.args.map(evaluate).toList();
    return switch (t.op) {
      '+' => add(a),
      '-' => add([
        a[0],
        mul([minus, a[1]]),
      ]),
      '*' => mul(a),
      '/' => mul([a[0], power(a[1], minus)]),
      '^' => power(a[0], a[1]),
      'neg' => mul([minus, a[0]]),
      _ => fn(t.op, a[0]),
    };
  }

  Expr parse() {
    final t = expression();
    if (position < tokens.length) unexpected();
    return evaluate(t);
  }
}

bool variable(String s) =>
    RegExp(r'^[a-z][a-z0-9]*$').hasMatch(s) && !functions.contains(s);
bool rationalLiteral(String s) => RegExp(r'^-?[0-9]+(?:/[0-9]+)?$').hasMatch(s);
Expr literal(String s) {
  if (!rationalLiteral(s)) fail("invalid number '$s'");
  final a = s.split('/');
  return num(int.parse(a[0]), a.length == 1 ? 1 : int.parse(a[1]));
}

const signatures = {
  'SIMPLIFY': 'e',
  'EXPAND': 'e',
  'DIFF': 'ev',
  'DIFFN': 'evn',
  'GRAD': 'e',
  'HESSIAN': 'e',
  'IMPLICIT': 'evv',
  'SUBST': 'eve',
  'EVAL': 'ea',
  'TANGENT': 'evc',
  'LIMIT': 'evc',
  'TAYLOR': 'evcn',
};
List<String> command(String line, Map<String, Expr> names) {
  final p = line.indexOf(' '),
      c = p < 0 ? line : line.substring(0, p),
      arg = p < 0 ? '' : line.substring(p + 1);
  if (c == 'LET') {
    final i = arg.indexOf('=');
    if (i < 0) fail('wrong number of arguments');
    final s = arg.substring(0, i).trim();
    if (!RegExp(r'^[A-Z][A-Z0-9]*$').hasMatch(s)) fail("invalid name '$s'");
    final f = Parser(arg.substring(i + 1).trim(), names).parse();
    names[s] = f;
    return ['$s = ${show(f)}'];
  }
  final sig = signatures[c];
  if (sig == null) fail('unknown command $c');
  final fields = p < 0
      ? <String>[]
      : arg.split(';').map((s) => s.trim()).toList();
  if (c == 'EVAL'
      ? !{1, 2}.contains(fields.length)
      : fields.length != sig.length)
    fail('wrong number of arguments');
  final forms = List.filled(fields.length, zero);
  var n = 0;
  for (var i = 0; i < fields.length; i++) {
    final s = fields[i];
    switch (sig[i]) {
      case 'e':
        forms[i] = Parser(s, names).parse();
      case 'v':
        if (!variable(s)) fail("invalid variable '$s'");
      case 'n':
        if (!RegExp(r'^[1-8]$').hasMatch(s)) fail("invalid order '$s'");
        n = int.parse(s);
      case 'c':
        forms[i] = literal(s);
    }
  }
  var f = forms[0];
  final v = fields.length > 1 ? fields[1] : '';
  final out = <String>[];
  if (c == 'SIMPLIFY') return ['simplified: ${show(f)}'];
  if (c == 'EXPAND') return ['expanded: ${show(expand(f))}'];
  if (c == 'DIFF') return ['d/d$v = ${show(derivative(f, v))}'];
  if (c == 'DIFFN') {
    for (var k = 1; k <= n; k++) {
      f = derivative(f, v);
      out.add('d^$k/d$v^$k = ${show(f)}');
    }
    return out;
  }
  if (c == 'GRAD' || c == 'HESSIAN') {
    final vs = variables(f);
    if (vs.isEmpty) return ['no variables'];
    for (var i = 0; i < vs.length; i++) {
      final d = derivative(f, vs[i]);
      if (c == 'GRAD') {
        out.add('d/d${vs[i]} = ${show(d)}');
      } else {
        for (var j = i; j < vs.length; j++) {
          out.add('d2/d${vs[i]}d${vs[j]} = ${show(derivative(d, vs[j]))}');
        }
      }
    }
    return out;
  }
  if (c == 'IMPLICIT') {
    final w = fields[2];
    if (v == w) fail('same variable');
    return [
      'd$w/d$v = ${show(mul([minus, derivative(f, v), power(derivative(f, w), minus)]))}',
    ];
  }
  if (c == 'SUBST')
    return [
      'substituted: ${show(substitute(f, {v: forms[2]}))}',
    ];
  if (c == 'EVAL') {
    final values = <String, Expr>{};
    for (final word in v.split(' ').where((s) => s.isNotEmpty)) {
      final i = word.indexOf('='),
          s = i < 0 ? word : word.substring(0, i),
          t = i < 0 ? '' : word.substring(i + 1);
      if (i < 0 || !variable(s) || !rationalLiteral(t))
        fail("invalid assignment '$word'");
      final q = literal(t);
      if (values.containsKey(s)) fail('duplicate variable $s');
      values[s] = q;
    }
    for (final s in variables(f)) {
      if (!values.containsKey(s)) fail('no value for $s');
    }
    final r = substitute(f, values);
    return [
      r.kind == Kind.number
          ? 'exact: ${show(r)}'
          : 'approx: ${numeric(r).toStringAsFixed(6)}',
    ];
  }
  final x = forms[2], point = {v: forms[2]};
  if (c == 'TANGENT') {
    final m = substitute(derivative(f, v), point),
        y = substitute(f, point),
        z = node(Kind.variable, [], v);
    final t =
        'tangent: y = ${show(add([
          mul([m, z]),
          y,
          mul([number(-x.value), m]),
        ]))}';
    if (equal(m, zero)) return [t, 'normal: $v = ${show(x)}'];
    final k = power(m, minus);
    return [
      t,
      'normal: y = ${show(add([
        mul([minus, k, z]),
        y,
        mul([x, k]),
      ]))}',
    ];
  }
  if (c == 'LIMIT') {
    final top = <Expr>[], bottom = <Expr>[];
    for (final t in f.kind == Kind.product ? f.args : [f]) {
      if (negative(t)) {
        bottom.add(power(t.args[0], number(-t.args[1].value)));
      } else {
        top.add(t);
      }
    }
    var g = mul(top), h = mul(bottom);
    for (var i = 0; i <= 5; i++) {
      final u = substitute(g, point), b = substitute(h, point);
      if (!equal(b, zero))
        return [
          'limit: ${show(mul([u, power(b, minus)]))}',
        ];
      if (!equal(u, zero)) return ['limit: unbounded'];
      if (i < 5) {
        g = derivative(g, v);
        h = derivative(h, v);
      }
    }
    return ['limit: unknown'];
  }
  final ds = [f], ps = <Expr>[];
  for (var i = 0; i < n; i++) {
    ds.add(derivative(ds.last, v));
  }
  var factorial = 1;
  for (var k = 0; k <= n; k++) {
    if (k > 0) factorial *= k;
    final co = mul([substitute(ds[k], point), num(1, factorial)]);
    ps.add(
      mul([
        co,
        power(add([node(Kind.variable, [], v), number(-x.value)]), num(k)),
      ]),
    );
  }
  return ['taylor: ${show(expand(add(ps)))}'];
}

void main() {
  final names = <String, Expr>{};
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      for (final s in command(line, names)) {
        print(s);
      }
    } on CommandError catch (e) {
      print('error: ${e.message}');
    }
  }
}
