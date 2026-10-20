import 'dart:io';

final class CommandError implements Exception {
  final String message;
  CommandError(String message) : message = 'ERROR $message';
}

final class Fraction implements Comparable<Fraction> {
  final int numerator, denominator;
  const Fraction._(this.numerator, this.denominator);
  static const one = Fraction._(1, 1);

  factory Fraction(int numerator, [int denominator = 1]) {
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final divisor = numerator.abs().gcd(denominator);
    return Fraction._(numerator ~/ divisor, denominator ~/ divisor);
  }

  factory Fraction.parse(String text) {
    final negative = text.startsWith('-');
    final body = negative ? text.substring(1) : text;
    final separator = RegExp(r'[./]').firstMatch(body)?.start ?? -1;
    final first = separator < 0 ? body : body.substring(0, separator);
    final second = separator < 0 ? '1' : body.substring(separator + 1);
    final digits = RegExp(r'^[0-9]+$');
    if (!digits.hasMatch(first) || !digits.hasMatch(second)) {
      throw CommandError('BAD NUMBER $text');
    }
    var numerator = int.parse(first, radix: 10), denominator = 1;
    if (separator >= 0 && body[separator] == '/') {
      denominator = int.parse(second, radix: 10);
      if (denominator == 0) throw CommandError('BAD NUMBER $text');
    } else if (separator >= 0) {
      for (var i = 0; i < second.length; i++) denominator *= 10;
      numerator = numerator * denominator + int.parse(second, radix: 10);
    }
    return Fraction(negative ? -numerator : numerator, denominator);
  }

  bool get isZero => numerator == 0;
  Fraction operator +(Fraction other) => Fraction(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator);
  Fraction operator -(Fraction other) => Fraction(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator);
  Fraction operator *(Fraction other) => Fraction(numerator * other.numerator, denominator * other.denominator);
  Fraction operator /(Fraction other) => Fraction(numerator * other.denominator, denominator * other.numerator);
  Fraction operator -() => Fraction(-numerator, denominator);
  Fraction abs() => Fraction(numerator.abs(), denominator);
  Fraction power(int exponent) {
    final factor = exponent < 0 ? one / this : this;
    var result = one;
    for (var i = 0; i < exponent.abs(); i++) result = result * factor;
    return result;
  }
  String decimal() {
    final magnitude = numerator.abs();
    final places = (magnitude % denominator * 1000000 ~/ denominator).toString().padLeft(6, '0');
    return '${numerator < 0 ? '-' : ''}${magnitude ~/ denominator}.$places';
  }
  @override
  int compareTo(Fraction other) => (numerator * other.denominator).compareTo(other.numerator * denominator);
  @override
  bool operator ==(Object other) => other is Fraction && numerator == other.numerator && denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() => denominator == 1 ? '$numerator' : '$numerator/$denominator';
}

final class Dimension {
  final int kg, m, s, a, k, mol, cd;
  const Dimension({this.kg = 0, this.m = 0, this.s = 0, this.a = 0, this.k = 0, this.mol = 0, this.cd = 0});
  static const zero = Dimension();
  List<int> get exponents => [kg, m, s, a, k, mol, cd];
  bool get isZero => this == zero;
  bool get isEven => exponents.every((value) => value % 2 == 0);
  Dimension operator +(Dimension other) => Dimension(
      kg: kg + other.kg, m: m + other.m, s: s + other.s, a: a + other.a,
      k: k + other.k, mol: mol + other.mol, cd: cd + other.cd);
  Dimension operator -(Dimension other) => Dimension(
      kg: kg - other.kg, m: m - other.m, s: s - other.s, a: a - other.a,
      k: k - other.k, mol: mol - other.mol, cd: cd - other.cd);
  Dimension scale(int factor) => Dimension(
      kg: kg * factor, m: m * factor, s: s * factor, a: a * factor,
      k: k * factor, mol: mol * factor, cd: cd * factor);
  Dimension half() => Dimension(kg: kg ~/ 2, m: m ~/ 2, s: s ~/ 2, a: a ~/ 2, k: k ~/ 2, mol: mol ~/ 2, cd: cd ~/ 2);
  @override
  bool operator ==(Object other) => other is Dimension &&
      kg == other.kg && m == other.m && s == other.s && a == other.a &&
      k == other.k && mol == other.mol && cd == other.cd;
  @override
  int get hashCode => Object.hash(kg, m, s, a, k, mol, cd);
  @override
  String toString() {
    const symbols = ['kg', 'm', 's', 'A', 'K', 'mol', 'cd'];
    final values = exponents;
    final parts = <String>[];
    for (var i = 0; i < values.length; i++) {
      if (values[i] != 0) parts.add(values[i] == 1 ? symbols[i] : '${symbols[i]}^${values[i]}');
    }
    return parts.isEmpty ? '1' : parts.join(' ');
  }
}

final class Quantity {
  final Fraction value;
  final Dimension dimension;
  const Quantity(this.value, this.dimension);
}
final class Definition {
  final Fraction value;
  final String expression;
  const Definition(this.value, this.expression);
}
final class Unit {
  final String symbol;
  final Quantity quantity;
  final bool prefix;
  final Definition? definition;
  const Unit(this.symbol, this.quantity, this.prefix, [this.definition]);
}

enum TokenKind { number, identifier, unit, symbol, invalid, end }
final class Token {
  final TokenKind kind;
  final String text;
  final int position;
  const Token(this.kind, this.text, this.position);
}

abstract class Parser {
  final String source;
  final tokens = <Token>[];
  var index = 0;
  Token get current => tokens[index];

  Parser(this.source, bool quantity) {
    for (var i = 0; i < source.length;) {
      final start = i++;
      final c = source.codeUnitAt(start);
      TokenKind kind;
      if (isLetter(c)) {
        while (i < source.length && isLetter(source.codeUnitAt(i))) i++;
        kind = TokenKind.identifier;
      } else if (isDigit(c)) {
        while (i < source.length && isDigit(source.codeUnitAt(i))) i++;
        if (quantity && i + 1 < source.length && source[i] == '.' && isDigit(source.codeUnitAt(i + 1))) {
          i += 2;
          while (i < source.length && isDigit(source.codeUnitAt(i))) i++;
        }
        kind = TokenKind.number;
      } else {
        final end = quantity && c == 91 ? source.indexOf(']', i) : -1;
        if (end > i) {
          i = end + 1;
          kind = TokenKind.unit;
        } else {
          kind = (quantity ? '+-*/^(),' : '*/^()-').contains(source[start]) ? TokenKind.symbol : TokenKind.invalid;
        }
      }
      tokens.add(Token(kind, source.substring(start, i), start + 1));
    }
    tokens.add(Token(TokenKind.end, '', source.length + 1));
  }

  static bool isLetter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
  static bool isDigit(int c) => c >= 48 && c <= 57;
  Token advance() => tokens[index++];
  bool take(String text) {
    if (current.text != text) return false;
    index++;
    return true;
  }
  void expect(String text) { if (!take(text)) throw syntax(); }
  CommandError syntax() => CommandError('SYNTAX $source AT ${current.kind == TokenKind.end ? 'END' : current.position}');
  void finish() { if (current.kind != TokenKind.end) throw syntax(); }
  String exponent() {
    final sign = take('-') ? '-' : '';
    if (current.kind != TokenKind.number || current.text.contains('.')) throw syntax();
    return sign + advance().text;
  }
}

sealed class UnitNode {}
final class UnitName extends UnitNode {
  final String name;
  UnitName(this.name);
}
final class UnitNumber extends UnitNode {
  final String text;
  UnitNumber(this.text);
}
final class UnitPower extends UnitNode {
  final UnitNode atom;
  final String exponent;
  UnitPower(this.atom, this.exponent);
}
final class UnitProduct extends UnitNode {
  final List<(String, UnitNode)> terms;
  UnitProduct(this.terms);
}

final class UnitParser extends Parser {
  UnitParser(String source) : super(source, false);
  UnitNode parse() { final node = expression(); finish(); return node; }
  UnitNode expression() {
    final terms = <(String, UnitNode)>[('*', term())];
    while (current.text == '*' || current.text == '/') {
      final op = advance().text;
      terms.add((op, term()));
    }
    return UnitProduct(terms);
  }
  UnitNode term() {
    UnitNode atom;
    if (current.kind == TokenKind.identifier) {
      atom = UnitName(advance().text);
    } else if (current.kind == TokenKind.number && current.text[0] != '0') {
      atom = UnitNumber(advance().text);
    } else if (take('(')) {
      atom = expression();
      expect(')');
    } else {
      throw syntax();
    }
    return take('^') ? UnitPower(atom, exponent()) : atom;
  }
}

sealed class QuantityNode {}
final class Literal extends QuantityNode {
  final String number;
  final String? unit;
  Literal(this.number, [this.unit]);
}
final class Variable extends QuantityNode {
  final String name;
  Variable(this.name);
}
final class Binary extends QuantityNode {
  final String op;
  final QuantityNode left, right;
  Binary(this.op, this.left, this.right);
}
final class Power extends QuantityNode {
  final QuantityNode base;
  final String exponent;
  Power(this.base, this.exponent);
}
final class Negative extends QuantityNode {
  final QuantityNode operand;
  Negative(this.operand);
}
final class Call extends QuantityNode {
  final String name;
  final List<QuantityNode> arguments;
  Call(this.name, this.arguments);
}

final class QuantityParser extends Parser {
  QuantityParser(String source) : super(source, true);
  QuantityNode parse() { final node = expression(); finish(); return node; }
  QuantityNode expression() {
    var node = product();
    while (current.text == '+' || current.text == '-') {
      final op = advance().text;
      node = Binary(op, node, product());
    }
    return node;
  }
  QuantityNode product() {
    var node = unary();
    while (current.text == '*' || current.text == '/') {
      final op = advance().text;
      node = Binary(op, node, unary());
    }
    return node;
  }
  QuantityNode unary() {
    if (take('-')) return Negative(unary());
    final node = primary();
    return take('^') ? Power(node, exponent()) : node;
  }
  QuantityNode primary() {
    if (current.kind == TokenKind.number) {
      final number = advance().text;
      return Literal(number, current.kind == TokenKind.unit ? unitString() : null);
    }
    if (current.kind == TokenKind.unit) return Literal('1', unitString());
    if (current.kind == TokenKind.identifier) {
      final name = advance().text;
      if (!take('(')) return Variable(name);
      final arguments = <QuantityNode>[expression()];
      while (take(',')) arguments.add(expression());
      expect(')');
      return Call(name, arguments);
    }
    if (take('(')) {
      final node = expression();
      expect(')');
      return node;
    }
    throw syntax();
  }
  String unitString() {
    final text = advance().text;
    return text.substring(1, text.length - 1);
  }
}

typedef ParsedUnit = ({UnitNode tree, Quantity quantity, List<String> names});
typedef Reduced = ({Fraction coefficient, Map<String, int> exponents});

final class Calculator {
  static const kinds = <String, Dimension>{
    'dimensionless': Dimension(), 'length': Dimension(m: 1), 'mass': Dimension(kg: 1),
    'time': Dimension(s: 1), 'current': Dimension(a: 1), 'temperature': Dimension(k: 1),
    'amount': Dimension(mol: 1), 'luminous_intensity': Dimension(cd: 1), 'area': Dimension(m: 2),
    'volume': Dimension(m: 3), 'speed': Dimension(m: 1, s: -1), 'acceleration': Dimension(m: 1, s: -2),
    'density': Dimension(kg: 1, m: -3), 'momentum': Dimension(kg: 1, m: 1, s: -1),
    'force': Dimension(kg: 1, m: 1, s: -2), 'energy': Dimension(kg: 1, m: 2, s: -2),
    'power': Dimension(kg: 1, m: 2, s: -3), 'pressure': Dimension(kg: 1, m: -1, s: -2),
    'frequency': Dimension(s: -1), 'charge': Dimension(s: 1, a: 1),
    'voltage': Dimension(kg: 1, m: 2, s: -3, a: -1), 'resistance': Dimension(kg: 1, m: 2, s: -3, a: -2),
    'conductance': Dimension(kg: -1, m: -2, s: 3, a: 2), 'capacitance': Dimension(kg: -1, m: -2, s: 4, a: 2),
    'magnetic_flux': Dimension(kg: 1, m: 2, s: -2, a: -1), 'flux_density': Dimension(kg: 1, s: -2, a: -1),
    'inductance': Dimension(kg: 1, m: 2, s: -2, a: -2), 'illuminance': Dimension(m: -2, cd: 1),
    'catalytic_activity': Dimension(s: -1, mol: 1),
  };
  static final prefixes = <(String, Fraction)>[
    ('G', Fraction(1000000000)), ('M', Fraction(1000000)), ('k', Fraction(1000)),
    ('h', Fraction(100)), ('da', Fraction(10)), ('d', Fraction(1, 10)), ('c', Fraction(1, 100)),
    ('m', Fraction(1, 1000)), ('u', Fraction(1, 1000000)), ('n', Fraction(1, 1000000000)),
  ];
  final units = <Unit>[];
  final variables = <String, Quantity>{};

  Calculator() {
    void add(String symbol, int numerator, int denominator, String kind, bool prefix) =>
        units.add(Unit(symbol, Quantity(Fraction(numerator, denominator), kinds[kind]!), prefix));
    add('m', 1, 1, 'length', true); add('g', 1, 1000, 'mass', true);
    add('s', 1, 1, 'time', true); add('A', 1, 1, 'current', true); add('K', 1, 1, 'temperature', true);
    add('mol', 1, 1, 'amount', true); add('cd', 1, 1, 'luminous_intensity', true);
    add('N', 1, 1, 'force', true); add('J', 1, 1, 'energy', true); add('W', 1, 1, 'power', true);
    add('Pa', 1, 1, 'pressure', true); add('Hz', 1, 1, 'frequency', true); add('C', 1, 1, 'charge', true);
    add('V', 1, 1, 'voltage', true); add('ohm', 1, 1, 'resistance', true);
    add('S', 1, 1, 'conductance', true); add('F', 1, 1, 'capacitance', true);
    add('Wb', 1, 1, 'magnetic_flux', true); add('T', 1, 1, 'flux_density', true);
    add('H', 1, 1, 'inductance', true); add('lx', 1, 1, 'illuminance', true);
    add('kat', 1, 1, 'catalytic_activity', true); add('L', 1, 1000, 'volume', true);
    add('t', 1000, 1, 'mass', false); add('min', 60, 1, 'time', false);
    add('h', 3600, 1, 'time', false); add('day', 86400, 1, 'time', false);
    add('in', 127, 5000, 'length', false); add('ft', 381, 1250, 'length', false);
    add('yd', 1143, 1250, 'length', false); add('mi', 201168, 125, 'length', false);
    add('nmi', 1852, 1, 'length', false); add('ha', 10000, 1, 'area', false);
    add('kn', 463, 900, 'speed', false); add('bar', 100000, 1, 'pressure', true);
    add('atm', 101325, 1, 'pressure', false); add('Torr', 20265, 152, 'pressure', false);
    add('cal', 523, 125, 'energy', true); add('Wh', 3600, 1, 'energy', true);
    add('Ah', 3600, 1, 'charge', true); add('dC', 1, 1, 'temperature', false); add('dF', 5, 9, 'temperature', false);
  }

  Quantity? resolve(String name) {
    for (final unit in units) {
      if (unit.symbol == name) return unit.quantity;
    }
    for (final (symbol, factor) in prefixes) {
      for (final unit in units) {
        if (unit.definition == null && unit.prefix && name == symbol + unit.symbol) {
          return Quantity(factor * unit.quantity.value, unit.quantity.dimension);
        }
      }
    }
    return null;
  }
  static String kind(Dimension dimension) {
    for (final entry in kinds.entries) {
      if (entry.value == dimension) return entry.key;
    }
    return '-';
  }
  String simplified(Dimension dimension) {
    for (final unit in units) {
      if (unit.quantity.dimension == dimension && unit.quantity.value == Fraction.one) return unit.symbol;
    }
    return dimension.toString();
  }
  static String format(Fraction value, String unit) => '$value $unit (${value.decimal()})';
  String formatQuantity(Quantity quantity) => format(quantity.value, simplified(quantity.dimension));
  static void match(Dimension a, Dimension b) {
    if (a != b) throw CommandError('DIMENSION MISMATCH $a vs $b');
  }
  static int checkExponent(String text) {
    final value = int.parse(text, radix: 10);
    if (value < -3 || value == 0 || value > 3) throw CommandError('BAD EXPONENT $text');
    return value;
  }
  static void checkName(String name, bool variable) {
    if (name.isEmpty || name.length > 12 || !name.codeUnits.every(Parser.isLetter) ||
        variable && const ['abs', 'sqrt', 'min', 'max'].contains(name)) throw CommandError('BAD NAME $name');
  }

  ParsedUnit parseUnit(String text) {
    final tree = UnitParser(text).parse();
    final names = <String>[], seen = <String>{};
    void validate(UnitNode node) {
      switch (node) {
        case UnitName name:
          if (resolve(name.name) == null) throw CommandError('UNKNOWN UNIT ${name.name}');
          if (seen.add(name.name)) names.add(name.name);
        case UnitNumber _:
          break;
        case UnitPower power:
          validate(power.atom);
          checkExponent(power.exponent);
        case UnitProduct product:
          for (final (_, term) in product.terms) validate(term);
      }
    }
    validate(tree);
    return (tree: tree, quantity: unitValue(tree), names: names);
  }
  Quantity unitValue(UnitNode node) {
    switch (node) {
      case UnitName name:
        return resolve(name.name)!;
      case UnitNumber number:
        return Quantity(Fraction(int.parse(number.text, radix: 10)), Dimension.zero);
      case UnitPower power:
        final atom = unitValue(power.atom);
        final exponent = int.parse(power.exponent, radix: 10);
        return Quantity(atom.value.power(exponent), atom.dimension.scale(exponent));
      case UnitProduct product:
        var result = const Quantity(Fraction.one, Dimension.zero);
        for (final (op, term) in product.terms) {
          final value = unitValue(term);
          result = op == '*'
              ? Quantity(result.value * value.value, result.dimension + value.dimension)
              : Quantity(result.value / value.value, result.dimension - value.dimension);
        }
        return result;
    }
  }
  static Reduced reduce(UnitNode node) {
    switch (node) {
      case UnitName name:
        return (coefficient: Fraction.one, exponents: {name.name: 1});
      case UnitNumber number:
        return (coefficient: Fraction(int.parse(number.text, radix: 10)), exponents: <String, int>{});
      case UnitPower power:
        final atom = reduce(power.atom);
        final exponent = int.parse(power.exponent, radix: 10);
        return (coefficient: atom.coefficient.power(exponent),
            exponents: {for (final entry in atom.exponents.entries) entry.key: entry.value * exponent});
      case UnitProduct product:
        var coefficient = Fraction.one;
        final exponents = <String, int>{};
        for (final (op, term) in product.terms) {
          final value = reduce(term);
          coefficient = op == '*' ? coefficient * value.coefficient : coefficient / value.coefficient;
          for (final entry in value.exponents.entries) {
            exponents[entry.key] = (exponents[entry.key] ?? 0) + (op == '*' ? entry.value : -entry.value);
          }
        }
        return (coefficient: coefficient, exponents: exponents);
    }
  }
  static String reducedText(ParsedUnit parsed) {
    final reduced = reduce(parsed.tree);
    final parts = <String>[];
    if (reduced.coefficient != Fraction.one) parts.add(reduced.coefficient.toString());
    for (final name in parsed.names) {
      final exponent = reduced.exponents[name]!;
      if (exponent != 0) parts.add(exponent == 1 ? name : '$name^$exponent');
    }
    return parts.isEmpty ? '1' : parts.join(' ');
  }
  static int integerRoot(int number) {
    var low = 0, high = number + 1;
    while (high - low > 1) {
      final middle = low + (high - low) ~/ 2;
      if (middle <= number ~/ middle) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }
  Quantity evaluate(QuantityNode node) {
    switch (node) {
      case Literal literal:
        final unitText = literal.unit;
        if (unitText == null) return Quantity(Fraction.parse(literal.number), Dimension.zero);
        final unit = parseUnit(unitText).quantity;
        return Quantity(Fraction.parse(literal.number) * unit.value, unit.dimension);
      case Variable variable:
        return variables[variable.name] ?? (throw CommandError('UNKNOWN VARIABLE ${variable.name}'));
      case Negative negative:
        final operand = evaluate(negative.operand);
        return Quantity(-operand.value, operand.dimension);
      case Power power:
        final basis = evaluate(power.base);
        final exponent = checkExponent(power.exponent);
        if (basis.value.isZero && exponent < 0) throw CommandError('DIVISION BY ZERO');
        return Quantity(basis.value.power(exponent), basis.dimension.scale(exponent));
      case Binary binary:
        final left = evaluate(binary.left);
        final right = evaluate(binary.right);
        if (binary.op == '+' || binary.op == '-') {
          match(left.dimension, right.dimension);
          return Quantity(binary.op == '+' ? left.value + right.value : left.value - right.value, left.dimension);
        }
        if (binary.op == '*') return Quantity(left.value * right.value, left.dimension + right.dimension);
        if (right.value.isZero) throw CommandError('DIVISION BY ZERO');
        return Quantity(left.value / right.value, left.dimension - right.dimension);
      case Call call:
        if (!const ['abs', 'sqrt', 'min', 'max'].contains(call.name)) throw CommandError('UNKNOWN FUNCTION ${call.name}');
        final count = call.name == 'abs' || call.name == 'sqrt' ? 1 : 2;
        if (call.arguments.length != count) throw CommandError('BAD ARGUMENTS ${call.name}');
        final a = evaluate(call.arguments[0]);
        if (call.name == 'abs') return Quantity(a.value.abs(), a.dimension);
        if (call.name == 'sqrt') {
          if (a.value.numerator < 0) throw CommandError('NEGATIVE ROOT');
          if (!a.dimension.isEven) throw CommandError('ODD DIMENSION ${a.dimension}');
          final p = integerRoot(a.value.numerator), q = integerRoot(a.value.denominator);
          if (p * p != a.value.numerator || q * q != a.value.denominator) throw CommandError('NOT EXACT');
          return Quantity(Fraction(p, q), a.dimension.half());
        }
        final b = evaluate(call.arguments[1]);
        match(a.dimension, b.dimension);
        final comparison = a.value.compareTo(b.value);
        return call.name == 'min' ? (comparison <= 0 ? a : b) : (comparison >= 0 ? a : b);
    }
  }
  List<Unit> matching(Dimension dimension) {
    final selected = units.where((unit) => unit.quantity.dimension == dimension).toList();
    selected.sort((a, b) {
      final comparison = a.quantity.value.compareTo(b.quantity.value);
      return comparison != 0 ? comparison : a.symbol.compareTo(b.symbol);
    });
    return selected;
  }

  String execute(String line) {
    final words = line.split(' '), command = words[0];
    switch (command) {
      case 'DEFINE': {
        checkName(words[1], false);
        final value = Fraction.parse(words[3]);
        final unit = parseUnit(words[4]).quantity;
        if (kinds.containsKey(words[1]) || resolve(words[1]) != null) throw CommandError('NAME TAKEN ${words[1]}');
        if (value.numerator <= 0) throw CommandError('NOT POSITIVE ${words[3]}');
        final defined = Quantity(value * unit.value, unit.dimension);
        units.add(Unit(words[1], defined, false, Definition(value, words[4])));
        return 'DEFINE ${words[1]} factor=${defined.value} dim=${defined.dimension} kind=${kind(defined.dimension)}';
      }
      case 'UNDEF': {
        final index = units.indexWhere((unit) => unit.symbol == words[1]);
        if (index >= 0 && units[index].definition == null) throw CommandError('BUILTIN UNIT ${words[1]}');
        if (index < 0) throw CommandError('NOT DEFINED ${words[1]}');
        units.removeAt(index);
        return 'UNDEF ${words[1]}';
      }
      case 'DEFS': {
        final users = units.where((unit) => unit.definition != null).toList();
        return [
          'DEFS count=${users.length}',
          for (final unit in users)
            'DEF ${unit.symbol} = ${unit.definition!.value} ${unit.definition!.expression} factor=${unit.quantity.value} dim=${unit.quantity.dimension}',
        ].join('\n');
      }
      case 'CONVERT': case 'INVERT': {
        final value = Fraction.parse(words[1]);
        final a = parseUnit(words[2]).quantity;
        final b = parseUnit(words[4]).quantity;
        if (command == 'CONVERT') {
          match(a.dimension, b.dimension);
        } else {
          if (a.dimension.isZero || !(a.dimension + b.dimension).isZero) {
            throw CommandError('NOT RECIPROCAL ${a.dimension} vs ${b.dimension}');
          }
          if (value.isZero) throw CommandError('DIVISION BY ZERO');
        }
        final result = command == 'CONVERT' ? value * a.value / b.value : (Fraction.one / (value * a.value)) / b.value;
        return '$command $value ${words[2]} = ${format(result, words[4])}';
      }
      case 'DIM': case 'REDUCE': case 'SIMPLIFY': {
        final parsed = parseUnit(words[1]), unit = parsed.quantity;
        return switch (command) {
          'DIM' => 'DIM ${words[1]} = ${unit.dimension} factor=${unit.value} kind=${kind(unit.dimension)}',
          'REDUCE' => 'REDUCE ${words[1]} = ${reducedText(parsed)}',
          _ => 'SIMPLIFY ${words[1]} = ${formatQuantity(unit)}',
        };
      }
      case 'ADD': case 'SUB': case 'MUL': case 'DIV': case 'COMPARE': {
        final x = Fraction.parse(words[1]);
        final a = parseUnit(words[2]).quantity;
        final y = Fraction.parse(words[3]);
        final b = parseUnit(words[4]).quantity;
        final target = words.length == 7 ? parseUnit(words[6]).quantity : null;
        if (command == 'COMPARE') {
          match(a.dimension, b.dimension);
          final left = x * a.value, right = y * b.value;
          final comparison = left.compareTo(right);
          final relation = comparison < 0 ? '<' : comparison > 0 ? '>' : '=';
          final ratio = right.isZero ? 'undefined' : (left / right).toString();
          return 'COMPARE $x ${words[2]} $relation $y ${words[4]} ratio=$ratio';
        }
        final op = switch (command) { 'ADD' => '+', 'SUB' => '-', 'MUL' => '*', _ => '/' };
        final prefix = '$command $x ${words[2]} $op $y ${words[4]} = ';
        if (command == 'ADD' || command == 'SUB') {
          match(a.dimension, b.dimension);
          if (target != null) match(a.dimension, target.dimension);
          final left = x * a.value, right = y * b.value;
          final result = (command == 'ADD' ? left + right : left - right) / (target?.value ?? a.value);
          return prefix + format(result, target == null ? words[2] : words[6]);
        }
        final dimension = command == 'MUL' ? a.dimension + b.dimension : a.dimension - b.dimension;
        if (command == 'DIV' && y.isZero) throw CommandError('DIVISION BY ZERO');
        if (target != null) match(dimension, target.dimension);
        final product = command == 'MUL' ? x * y : x / y;
        final first = x * a.value, second = y * b.value;
        final coherent = command == 'MUL' ? first * second : first / second;
        if (target != null) return prefix + format(coherent / target.value, words[6]);
        final rightUnit = command == 'DIV' && (words[4].contains('*') || words[4].contains('/')) ? '(${words[4]})' : words[4];
        return '$prefix$product ${words[2]}$op$rightUnit = ${format(coherent, simplified(dimension))}';
      }
      case 'TEMP': {
        final value = Fraction.parse(words[1]);
        for (final scale in [words[2], words[4]]) {
          if (!const ['C', 'F', 'K', 'R'].contains(scale)) throw CommandError('UNKNOWN SCALE $scale');
        }
        final kelvin = switch (words[2]) {
          'C' => value + Fraction(5463, 20),
          'F' => (value + Fraction(45967, 100)) * Fraction(5) / Fraction(9),
          'R' => value * Fraction(5) / Fraction(9), _ => value,
        };
        if (kelvin.numerator < 0) throw CommandError('BELOW ABSOLUTE ZERO');
        final result = switch (words[4]) {
          'C' => kelvin - Fraction(5463, 20),
          'F' => kelvin * Fraction(9) / Fraction(5) - Fraction(45967, 100),
          'R' => kelvin * Fraction(9) / Fraction(5), _ => kelvin,
        };
        return 'TEMP $value ${words[2]} = ${format(result, words[4])}';
      }
      case 'LIST': {
        final dimension = kinds[words[1]] ?? parseUnit(words[1]).quantity.dimension;
        final selected = matching(dimension);
        return [
          'LIST ${words[1]} dim=$dimension kind=${kind(dimension)} count=${selected.length}',
          for (final unit in selected)
            'UNIT ${unit.symbol} factor=${unit.quantity.value} origin=${unit.definition == null ? 'builtin' : 'user'} prefix=${unit.prefix ? 'yes' : 'no'}',
        ].join('\n');
      }
      case 'TABLE': case 'AUTO': case 'SPLIT': {
        final value = Fraction.parse(words[1]);
        final unit = parseUnit(words[2]).quantity;
        if (command == 'TABLE') {
          final selected = matching(unit.dimension);
          return [
            'TABLE $value ${words[2]} dim=${unit.dimension} count=${selected.length}',
            for (final row in selected) 'ROW ${format(value * unit.value / row.quantity.value, row.symbol)}',
          ].join('\n');
        }
        if (command == 'AUTO') {
          Unit? basis;
          for (final candidate in units) {
            if (candidate.definition == null && candidate.prefix && candidate.quantity.dimension == unit.dimension) {
              basis = candidate;
              break;
            }
          }
          if (basis == null) throw CommandError('NO PREFIXABLE UNIT ${unit.dimension}');
          final scaled = value * unit.value / basis.quantity.value, magnitude = scaled.abs();
          var exponent = 0;
          if (magnitude.compareTo(Fraction.one) >= 0) {
            while (exponent < 9 && magnitude.compareTo(Fraction(10).power(exponent + 3)) >= 0) exponent += 3;
          } else if (!magnitude.isZero) {
            while (exponent > -9 && magnitude.compareTo(Fraction(10).power(exponent)) < 0) exponent -= 3;
          }
          final prefix = switch (exponent) { 9 => 'G', 6 => 'M', 3 => 'k', -3 => 'm', -6 => 'u', -9 => 'n', _ => '' };
          return 'AUTO $value ${words[2]} = ${format(scaled / Fraction(10).power(exponent), prefix + basis.symbol)}';
        }
        final parts = words[4].split(',');
        final destinations = <Quantity>[];
        for (final part in parts) destinations.add(parseUnit(part).quantity);
        if (value.numerator < 0) throw CommandError('NEGATIVE VALUE');
        for (final destination in destinations) match(unit.dimension, destination.dimension);
        for (var i = 1; i < destinations.length; i++) {
          if (destinations[i - 1].value.compareTo(destinations[i].value) <= 0) throw CommandError('UNIT ORDER');
        }
        var remaining = value * unit.value;
        final pieces = <String>[];
        for (var i = 0; i < parts.length - 1; i++) {
          final quotient = remaining / destinations[i].value;
          final whole = quotient.numerator ~/ quotient.denominator;
          remaining = remaining - Fraction(whole) * destinations[i].value;
          pieces.add('$whole ${parts[i]}');
        }
        pieces.add(format(remaining / destinations.last.value, parts.last));
        return 'SPLIT $value ${words[2]} = ${pieces.join(' ')}';
      }
      case 'LET': {
        checkName(words[1], true);
        final value = evaluate(QuantityParser(words[3]).parse());
        variables[words[1]] = value;
        return 'LET ${words[1]} = ${formatQuantity(value)}';
      }
      case 'EVAL': {
        final value = evaluate(QuantityParser(words[1]).parse());
        if (words.length == 4) {
          final unit = parseUnit(words[3]).quantity;
          match(value.dimension, unit.dimension);
          return 'EVAL ${words[1]} = ${format(value.value / unit.value, words[3])}';
        }
        return 'EVAL ${words[1]} = ${formatQuantity(value)}';
      }
      case 'VARS': {
        final names = variables.keys.toList()..sort();
        return ['VARS count=${variables.length}', for (final name in names) 'VAR $name = ${formatQuantity(variables[name]!)}'].join('\n');
      }
      default:
        throw CommandError('UNKNOWN COMMAND $command');
    }
  }
}

void main() {
  final calculator = Calculator();
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      stdout.writeln(calculator.execute(line));
    } on CommandError catch (error) {
      stdout.writeln(error.message);
    }
  }
}
