import 'dart:io';
import 'dart:math' as math;

final class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

final class Fraction implements Comparable<Fraction> {
  final int numerator, denominator;
  const Fraction._(this.numerator, this.denominator);
  static const zero = Fraction._(0, 1), one = Fraction._(1, 1);

  factory Fraction(int numerator, [int denominator = 1]) {
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final divisor = numerator.abs().gcd(denominator);
    return Fraction._(numerator ~/ divisor, denominator ~/ divisor);
  }

  factory Fraction.parse(String text) {
    final parts = text.split('/');
    final numerator = int.parse(parts[0], radix: 10);
    final denominator = parts.length == 1 ? 1 : int.parse(parts[1], radix: 10);
    if (denominator == 0) throw CommandError('ERROR ZERO DENOMINATOR');
    return Fraction(numerator, denominator);
  }

  bool get isZero => numerator == 0;
  int get sign => numerator.sign;
  Fraction operator +(Fraction other) => Fraction(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator);
  Fraction operator -(Fraction other) => Fraction(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator);
  Fraction operator *(Fraction other) => Fraction(
      numerator * other.numerator, denominator * other.denominator);
  Fraction operator /(Fraction other) => Fraction(
      numerator * other.denominator, denominator * other.numerator);
  Fraction operator -() => Fraction(-numerator, denominator);
  Fraction abs() => Fraction(numerator.abs(), denominator);
  Fraction power(int exponent) {
    var result = one;
    for (var i = 0; i < exponent; i++) result = result * this;
    return result;
  }

  @override
  int compareTo(Fraction other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);
  @override
  bool operator ==(Object other) =>
      other is Fraction && numerator == other.numerator && denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() => denominator == 1 ? '$numerator' : '$numerator/$denominator';
}

final class Polynomial {
  final List<Fraction> _coefficients;
  Polynomial._(this._coefficients);
  static final zero = Polynomial([]), one = Polynomial([Fraction.one]);
  static final x = Polynomial([Fraction.zero, Fraction.one]);

  factory Polynomial(List<Fraction> values) {
    var length = values.length;
    while (length > 0 && values[length - 1].isZero) length--;
    return Polynomial._(List<Fraction>.unmodifiable(values.take(length)));
  }

  int get degree => _coefficients.length - 1;
  bool get isZero => _coefficients.isEmpty;
  Fraction get leading => _coefficients.last;
  Fraction operator [](int index) => index < _coefficients.length ? _coefficients[index] : Fraction.zero;
  Polynomial operator +(Polynomial other) => Polynomial([
    for (var i = 0; i <= math.max(degree, other.degree); i++) this[i] + other[i],
  ]);
  Polynomial operator -(Polynomial other) => Polynomial([
    for (var i = 0; i <= math.max(degree, other.degree); i++) this[i] - other[i],
  ]);
  Polynomial operator -() => Polynomial([for (final value in _coefficients) -value]);
  Polynomial operator *(Polynomial other) {
    if (isZero || other.isZero) return zero;
    final result = List.filled(degree + other.degree + 1, Fraction.zero);
    for (var i = 0; i <= degree; i++) {
      for (var j = 0; j <= other.degree; j++) {
        result[i + j] = result[i + j] + this[i] * other[j];
      }
    }
    return Polynomial(result);
  }

  Polynomial scale(Fraction factor) => Polynomial([for (final value in _coefficients) value * factor]);
  Polynomial divideScalar(Fraction divisor) => Polynomial([for (final value in _coefficients) value / divisor]);
  Polynomial monic() => isZero ? zero : divideScalar(leading);
  Polynomial power(int exponent) {
    if (exponent == 0) return one;
    if (isZero) return zero;
    if (degree == 0 && leading.denominator == 1 && leading.numerator.abs() == 1) {
      return leading.numerator == 1 || exponent.isEven ? one : this;
    }
    var result = one;
    for (var i = 0; i < exponent; i++) result = result * this;
    return result;
  }

  Fraction evaluate(Fraction point) {
    var result = Fraction.zero;
    for (var i = degree; i >= 0; i--) result = result * point + this[i];
    return result;
  }

  Polynomial compose(Polynomial inner) {
    var result = zero;
    for (var i = degree; i >= 0; i--) result = result * inner + Polynomial([this[i]]);
    return result;
  }

  Polynomial derivative([int order = 1]) {
    var result = this;
    for (var step = 0; step < order; step++) {
      result = Polynomial([for (var i = 1; i <= result.degree; i++) Fraction(i) * result[i]]);
    }
    return result;
  }

  Polynomial integral() => isZero ? zero : Polynomial([
    Fraction.zero,
    for (var i = 0; i <= degree; i++) this[i] / Fraction(i + 1),
  ]);

  ({Polynomial quotient, Polynomial remainder}) divide(Polynomial divisor) {
    final quotient = List.filled(math.max(0, degree - divisor.degree + 1), Fraction.zero);
    final remainder = List<Fraction>.of(_coefficients);
    var currentDegree = degree;
    while (currentDegree >= divisor.degree && currentDegree >= 0) {
      final factor = remainder[currentDegree] / divisor.leading;
      final shift = currentDegree - divisor.degree;
      quotient[shift] = factor;
      for (var j = 0; j <= divisor.degree; j++) {
        remainder[shift + j] = remainder[shift + j] - factor * divisor[j];
      }
      while (currentDegree >= 0 && remainder[currentDegree].isZero) currentDegree--;
    }
    return (quotient: Polynomial(quotient), remainder: Polynomial(remainder));
  }

  static Polynomial gcd(Polynomial a, Polynomial b) {
    while (!b.isZero) (a, b) = (b, a.divide(b).remainder);
    return a.monic();
  }

  static ({Polynomial g, Polynomial s, Polynomial t}) extendedGcd(Polynomial a, Polynomial b) {
    var r0 = a, r1 = b, s0 = one, s1 = zero, t0 = zero, t1 = one;
    while (!r1.isZero) {
      final division = r0.divide(r1);
      (r0, r1) = (r1, division.remainder);
      (s0, s1) = (s1, s0 - division.quotient * s1);
      (t0, t1) = (t1, t0 - division.quotient * t1);
    }
    return r0.isZero
        ? (g: r0, s: s0, t: t0)
        : (g: r0.monic(), s: s0.divideScalar(r0.leading), t: t0.divideScalar(r0.leading));
  }

  Fraction content() {
    var denominator = 1, numerator = 0;
    for (final coefficient in _coefficients) {
      denominator = denominator * coefficient.denominator ~/ denominator.gcd(coefficient.denominator);
      numerator = numerator.gcd(coefficient.numerator.abs());
    }
    return Fraction(leading.sign < 0 ? -numerator : numerator, denominator);
  }

  Polynomial primitive() => divideScalar(content());
  Polynomial squareFreePart() => degree < 1 ? this : divide(gcd(this, derivative())).quotient;
  Polynomial withoutConstant() => Polynomial(_coefficients.sublist(1));

  String format([String variable = 'x']) {
    if (isZero) return '0';
    final result = StringBuffer();
    for (var i = degree; i >= 0; i--) {
      final coefficient = this[i];
      if (coefficient.isZero) continue;
      if (result.isEmpty) {
        if (coefficient.sign < 0) result.write('-');
      } else {
        result.write(coefficient.sign < 0 ? ' - ' : ' + ');
      }
      final magnitude = coefficient.abs();
      if (i == 0 || magnitude != Fraction.one) result.write(magnitude);
      if (i > 0) result.write(variable);
      if (i > 1) result.write('^$i');
    }
    return result.toString();
  }
}

void checkProduct(Polynomial a, Polynomial b) {
  if (!a.isZero && !b.isZero && a.degree + b.degree > 30) throw CommandError('ERROR DEGREE LIMIT');
}
void checkPower(Polynomial value, int exponent) {
  if (!value.isZero && value.degree * exponent > 30) throw CommandError('ERROR DEGREE LIMIT');
}
void checkComposition(Polynomial a, Polynomial b) {
  if (a.degree >= 1 && b.degree >= 1 && a.degree * b.degree > 30) throw CommandError('ERROR DEGREE LIMIT');
}
void checkNonzero(Polynomial value) {
  if (value.isZero) throw CommandError('ERROR ZERO POLYNOMIAL');
}
void checkDivisor(Polynomial value) {
  if (value.isZero) throw CommandError('ERROR DIVISION BY ZERO');
}
void checkPositiveDegree(Polynomial value) {
  if (value.degree == 0) throw CommandError('ERROR DEGREE TOO LOW');
}

sealed class Expression {
  Polynomial evaluate(Map<String, Polynomial> storage);
}
final class LiteralExpression extends Expression {
  final Polynomial value;
  LiteralExpression(this.value);
  @override
  Polynomial evaluate(Map<String, Polynomial> storage) => value;
}
final class NameExpression extends Expression {
  final String name;
  final int order;
  NameExpression(this.name, this.order);
  @override
  Polynomial evaluate(Map<String, Polynomial> storage) {
    final value = storage[name];
    if (value == null) throw CommandError('ERROR UNKNOWN $name');
    return value.derivative(order);
  }
}
final class NegativeExpression extends Expression {
  final Expression operand;
  NegativeExpression(this.operand);
  @override
  Polynomial evaluate(Map<String, Polynomial> storage) => -operand.evaluate(storage);
}
final class BinaryExpression extends Expression {
  final String operation;
  final Expression left, right;
  BinaryExpression(this.operation, this.left, this.right);
  @override
  Polynomial evaluate(Map<String, Polynomial> storage) {
    final a = left.evaluate(storage), b = right.evaluate(storage);
    switch (operation) {
      case '+': return a + b;
      case '-': return a - b;
      case '*': checkProduct(a, b); return a * b;
      default:
        checkDivisor(b);
        if (b.degree >= 1) throw CommandError('ERROR NONCONSTANT DIVISOR');
        return a.divideScalar(b[0]);
    }
  }
}
final class PowerExpression extends Expression {
  final Expression operand;
  final int exponent;
  PowerExpression(this.operand, this.exponent);
  @override
  Polynomial evaluate(Map<String, Polynomial> storage) {
    final value = operand.evaluate(storage);
    checkPower(value, exponent);
    return value.power(exponent);
  }
}
final class CallExpression extends Expression {
  final Expression function, argument;
  CallExpression(this.function, this.argument);
  @override
  Polynomial evaluate(Map<String, Polynomial> storage) {
    final outer = function.evaluate(storage), inner = argument.evaluate(storage);
    checkComposition(outer, inner);
    return outer.compose(inner);
  }
}

enum TokenKind { number, name, symbol, end }
final class Token {
  final TokenKind kind;
  final String text;
  final int position;
  Token(this.kind, this.text, this.position);
}

final class Parser {
  final List<Token> tokens = [];
  int position = 0;
  Token get current => tokens[position];
  bool at(String symbol) => current.kind == TokenKind.symbol && current.text == symbol;
  static bool digit(int code) => code >= 48 && code <= 57;
  static bool upper(int code) => code >= 65 && code <= 90;

  Parser(String source) {
    var i = 0;
    while (i < source.length) {
      if (source.codeUnitAt(i) == 32) { i++; continue; }
      final start = i++;
      TokenKind kind;
      if (digit(source.codeUnitAt(start))) {
        kind = TokenKind.number;
        while (i < source.length && digit(source.codeUnitAt(i))) i++;
      } else if (upper(source.codeUnitAt(start))) {
        kind = TokenKind.name;
        while (i < source.length && (upper(source.codeUnitAt(i)) || digit(source.codeUnitAt(i)))) i++;
      } else {
        kind = TokenKind.symbol;
      }
      tokens.add(Token(kind, source.substring(start, i), start + 1));
    }
    tokens.add(Token(TokenKind.end, '', source.length + 1));
  }

  Never syntax() => throw CommandError(current.kind == TokenKind.end
      ? 'ERROR SYNTAX AT END' : 'ERROR SYNTAX AT ${current.position}');
  void expect(String symbol) {
    if (!at(symbol)) syntax();
    position++;
  }

  Expression parse() {
    final result = expression();
    if (current.kind != TokenKind.end) syntax();
    return result;
  }

  Expression expression() {
    final negative = at('-');
    if (negative) position++;
    var result = term();
    if (negative) result = NegativeExpression(result);
    while (at('+') || at('-')) {
      final operation = current.text;
      position++;
      result = BinaryExpression(operation, result, term());
    }
    return result;
  }

  Expression term() {
    var result = factor();
    while (true) {
      String operation;
      if (at('*') || at('/')) { operation = current.text; position++; }
      else if (at('x') || at('(') || current.kind == TokenKind.name) { operation = '*'; }
      else { break; }
      result = BinaryExpression(operation, result, factor());
    }
    return result;
  }

  Expression factor() {
    var result = primary();
    if (at('^')) {
      position++;
      if (current.kind != TokenKind.number) syntax();
      final exponent = int.parse(current.text, radix: 10);
      position++;
      result = PowerExpression(result, exponent);
    }
    return result;
  }

  Expression primary() {
    if (current.kind == TokenKind.number) {
      final value = Polynomial([Fraction(int.parse(current.text, radix: 10))]);
      position++;
      return LiteralExpression(value);
    }
    if (at('x')) { position++; return LiteralExpression(Polynomial.x); }
    if (current.kind == TokenKind.name) {
      final name = current.text;
      position++;
      var order = 0;
      while (at("'")) { order++; position++; }
      final reference = NameExpression(name, order);
      if (!at('(')) return reference;
      position++;
      final argument = expression();
      expect(')');
      return CallExpression(reference, argument);
    }
    if (at('(')) {
      position++;
      final result = expression();
      expect(')');
      return result;
    }
    syntax();
  }
}

final class Endpoint implements Comparable<Endpoint> {
  final int infinity;
  final Fraction value;
  const Endpoint(this.infinity, this.value);
  factory Endpoint.parse(String text) => switch (text) {
    '-inf' => const Endpoint(-1, Fraction.zero),
    'inf' => const Endpoint(1, Fraction.zero),
    _ => Endpoint(0, Fraction.parse(text)),
  };
  @override
  int compareTo(Endpoint other) => infinity == 0 && other.infinity == 0
      ? value.compareTo(other.value) : infinity.compareTo(other.infinity);
  @override
  String toString() => infinity == 0 ? '$value' : infinity < 0 ? '-inf' : 'inf';
}

typedef Root = ({Fraction root, int multiplicity});
typedef Factor = ({Polynomial polynomial, int multiplicity});
typedef Interval = ({Fraction left, Fraction right});

({Fraction content, Polynomial remaining, List<Root> roots}) rationalRoots(Polynomial value) {
  final content = value.content();
  var remaining = value.divideScalar(content);
  var zeros = 0;
  while (remaining[0].isZero) { remaining = remaining.withoutConstant(); zeros++; }
  List<int> divisors(int number) => [for (var i = 1; i <= number; i++) if (number % i == 0) i];
  final numerators = divisors(remaining[0].numerator.abs());
  final denominators = divisors(remaining.leading.numerator);
  final candidates = <Fraction>[];
  for (final numerator in numerators) {
    for (final denominator in denominators) {
      if (numerator.gcd(denominator) == 1) {
        candidates.add(Fraction(numerator, denominator));
        candidates.add(Fraction(-numerator, denominator));
      }
    }
  }
  candidates.sort();
  final roots = <Root>[];
  for (final candidate in candidates) {
    var count = 0;
    final divisor = Polynomial([Fraction(-candidate.numerator), Fraction(candidate.denominator)]);
    while (remaining.degree >= 1 && remaining.evaluate(candidate).isZero) {
      remaining = remaining.divide(divisor).quotient;
      count++;
    }
    if (count > 0) roots.add((root: candidate, multiplicity: count));
  }
  if (zeros > 0) roots.add((root: Fraction.zero, multiplicity: zeros));
  roots.sort((a, b) => a.root.compareTo(b.root));
  return (content: content, remaining: remaining, roots: roots);
}

List<Factor> squareFreeFactors(Polynomial value) {
  final result = <Factor>[];
  if (value.degree < 1) return result;
  final monic = value.monic();
  var c = Polynomial.gcd(monic, monic.derivative());
  var w = monic.divide(c).quotient;
  for (var i = 1; w.degree >= 1; i++) {
    final y = Polynomial.gcd(w, c);
    final factor = w.divide(y).quotient;
    if (factor.degree >= 1) result.add((polynomial: factor.primitive(), multiplicity: i));
    c = c.divide(y).quotient;
    w = y;
  }
  return result;
}

List<Polynomial> sturmSequence(Polynomial value) {
  var previous = value.squareFreePart();
  var current = previous.derivative();
  final result = [previous];
  while (!current.isZero) {
    result.add(current);
    final next = -previous.divide(current).remainder;
    previous = current;
    current = next;
  }
  return result;
}

int variations(List<Polynomial> sequence, Endpoint point) {
  var previous = 0, changes = 0;
  for (final value in sequence) {
    var sign = point.infinity == 0 ? value.evaluate(point.value).sign : value.leading.sign;
    if (point.infinity < 0 && value.degree.isOdd) sign = -sign;
    if (sign == 0) continue;
    if (previous != 0 && previous != sign) changes++;
    previous = sign;
  }
  return changes;
}

int rootCount(List<Polynomial> sequence, Endpoint left, Endpoint right) =>
    variations(sequence, left) - variations(sequence, right);

List<Interval> isolate(Polynomial value, int precision) {
  final sequence = sturmSequence(value);
  final first = sequence[0];
  var maximum = Fraction.zero;
  for (var i = 0; i < first.degree; i++) {
    final candidate = (first[i] / first.leading).abs();
    if (candidate.compareTo(maximum) > 0) maximum = candidate;
  }
  final beta = Fraction.one + maximum, width = Fraction(1, 1 << precision);
  final result = <Interval>[];
  int count(Fraction left, Fraction right) => rootCount(sequence, Endpoint(0, left), Endpoint(0, right));
  void examine(Fraction left, Fraction right) {
    final roots = count(left, right);
    if (roots >= 2) {
      final middle = (left + right) / Fraction(2);
      examine(left, middle);
      examine(middle, right);
    } else if (roots == 1) {
      while ((right - left).compareTo(width) > 0) {
        final middle = (left + right) / Fraction(2);
        if (count(left, middle) >= 1) { right = middle; } else { left = middle; }
      }
      result.add((left: left, right: right));
    }
  }
  examine(-beta, beta);
  return result;
}

Fraction resultant(Polynomial p, Polynomial q) {
  var result = Fraction.one;
  while (q.degree >= 1) {
    final remainder = p.divide(q).remainder;
    if (remainder.isZero) return Fraction.zero;
    result = result * q.leading.power(p.degree - remainder.degree);
    if ((p.degree * q.degree).isOdd) result = -result;
    (p, q) = (q, remainder);
  }
  return result * q[0].power(p.degree);
}

int descartes(Polynomial value, bool negative) {
  var previous = 0, count = 0;
  for (var i = value.degree; i >= 0; i--) {
    var sign = value[i].sign;
    if (negative && i.isOdd) sign = -sign;
    if (sign == 0) continue;
    if (previous != 0 && previous != sign) count++;
    previous = sign;
  }
  return count;
}

Polynomial interpolate(List<Fraction> values) {
  final count = values.length ~/ 2;
  final x = [for (var i = 0; i < count; i++) values[2 * i]];
  final differences = [for (var i = 0; i < count; i++) values[2 * i + 1]];
  for (var j = 1; j < count; j++) {
    for (var i = 0; i < j; i++) {
      if (x[j].compareTo(x[i]) == 0) throw CommandError('ERROR DUPLICATE X ${x[j]}');
    }
  }
  for (var j = 1; j < count; j++) {
    for (var i = count - 1; i >= j; i--) {
      differences[i] = (differences[i] - differences[i - 1]) / (x[i] - x[i - j]);
    }
  }
  var result = Polynomial.zero;
  for (var i = count - 1; i >= 0; i--) {
    result = result * Polynomial([-x[i], Fraction.one]) + Polynomial([differences[i]]);
  }
  return result;
}

Polynomial special(String kind, int degree) {
  if (!['chebyshev', 'chebyshev2', 'legendre', 'hermite', 'laguerre'].contains(kind)) {
    throw CommandError('ERROR UNKNOWN KIND $kind');
  }
  if (degree > 30) throw CommandError('ERROR DEGREE LIMIT');
  var previous = Polynomial.one;
  var current = switch (kind) {
    'chebyshev2' || 'hermite' => Polynomial([Fraction.zero, Fraction(2)]),
    'laguerre' => Polynomial([Fraction.one, Fraction(-1)]),
    _ => Polynomial.x,
  };
  if (degree == 0) return previous;
  for (var j = 1; j < degree; j++) {
    final factor = switch (kind) {
      'legendre' => Polynomial([Fraction.zero, Fraction(2 * j + 1)]),
      'laguerre' => Polynomial([Fraction(2 * j + 1), Fraction(-1)]),
      _ => Polynomial([Fraction.zero, Fraction(2)]),
    };
    final scale = kind == 'legendre' || kind == 'laguerre' ? j : kind == 'hermite' ? 2 * j : 1;
    var next = factor * current - previous.scale(Fraction(scale));
    if (kind == 'legendre' || kind == 'laguerre') next = next.scale(Fraction(1, j + 1));
    previous = current;
    current = next;
  }
  return current;
}

final class Calculator {
  final Map<String, Polynomial> storage = {};

  Polynomial lookup(String name) => storage[name] ?? (throw CommandError('ERROR UNKNOWN $name'));
  static List<int> nameArguments(String command) => switch (command) {
    'PRINT' || 'DELETE' || 'DEGREE' || 'AREA' || 'TAYLOR' || 'EVAL' || 'ROOTS' || 'FACTOR' ||
    'SQFREE' || 'DESCARTES' || 'STURM' || 'ISOLATE' || 'DISCRIM' || 'POWERSUM' => [1],
    'ADD' || 'SUB' || 'MUL' || 'GCD' || 'LCM' || 'INVMOD' || 'COMPOSE' => [2, 3],
    'POW' || 'DERIV' || 'INTEG' || 'TANGENT' => [2],
    'DIV' => [3, 4], 'XGCD' => [4, 5], 'CRT' => [2, 3, 4, 5],
    'MODPOW' => [2, 4], 'RESULTANT' => [1, 2], _ => [],
  };

  List<String> execute(String line) {
    final output = <String>[];
    final pending = <(String, Polynomial)>[];
    String? deletion;
    void save(String name, Polynomial value) {
      pending.add((name, value));
      output.add('$name = ${value.format()}');
    }

    if (line.startsWith('DEF ')) {
      final separator = line.indexOf(' ', 4);
      final name = line.substring(4, separator);
      final expression = Parser(line.substring(separator + 1)).parse();
      save(name, expression.evaluate(storage));
    } else {
      final words = line.split(' ');
      final command = words[0];
      if (command == 'DIV' && words[1] == words[2] || command == 'XGCD' &&
          (words[1] == words[2] || words[1] == words[3] || words[2] == words[3])) {
        throw CommandError('ERROR SAME NAME');
      }
      final operands = [for (final index in nameArguments(command)) lookup(words[index])];
      final literalArguments = switch (command) {
        'AREA' => [2, 3], 'TANGENT' => [3], 'TAYLOR' => [2],
        'EVAL' || 'INTERP' => [for (var i = 2; i < words.length; i++) i], _ => <int>[],
      };
      final literals = [for (final index in literalArguments) Fraction.parse(words[index])];
      late final Endpoint left, right;
      if (command == 'STURM') {
        left = Endpoint.parse(words[2]);
        right = Endpoint.parse(words[3]);
      }
      final a = operands.isEmpty ? Polynomial.zero : operands[0];
      final b = operands.length < 2 ? Polynomial.zero : operands[1];
      switch (command) {
        case 'PRINT': output.add('${words[1]} = ${a.format()}');
        case 'DELETE': deletion = words[1]; output.add('deleted ${words[1]}');
        case 'LIST':
          if (storage.isEmpty) {
            output.add('no polynomials');
          } else {
            final names = storage.keys.toList()..sort();
            for (final name in names) output.add('$name = ${storage[name]!.format()}');
          }
        case 'DEGREE': output.add('deg(${words[1]}) = ${a.isZero ? '-inf' : a.degree}');
        case 'ADD': save(words[1], a + b);
        case 'SUB': save(words[1], a - b);
        case 'MUL': checkProduct(a, b); save(words[1], a * b);
        case 'POW':
          final exponent = int.parse(words[3]);
          checkPower(a, exponent);
          save(words[1], a.power(exponent));
        case 'DIV':
          checkDivisor(b);
          final division = a.divide(b);
          save(words[1], division.quotient);
          save(words[2], division.remainder);
        case 'GCD': save(words[1], Polynomial.gcd(a, b));
        case 'XGCD':
          final result = Polynomial.extendedGcd(a, b);
          save(words[1], result.g);
          save(words[2], result.s);
          save(words[3], result.t);
        case 'LCM':
          if (a.isZero || b.isZero) {
            save(words[1], Polynomial.zero);
          } else {
            final gcd = Polynomial.gcd(a, b);
            if (a.degree + b.degree - gcd.degree > 30) throw CommandError('ERROR DEGREE LIMIT');
            save(words[1], (a.divide(gcd).quotient * b).monic());
          }
        case 'INVMOD':
          checkDivisor(b);
          checkPositiveDegree(b);
          final result = Polynomial.extendedGcd(a, b);
          if (result.g.degree != 0 || result.g[0] != Fraction.one) throw CommandError('ERROR NOT COPRIME');
          save(words[1], result.s.divide(b).remainder);
        case 'CRT':
          final a2 = operands[2], m2 = operands[3];
          checkDivisor(b);
          checkDivisor(m2);
          if (b.degree + m2.degree > 30) throw CommandError('ERROR DEGREE LIMIT');
          final result = Polynomial.extendedGcd(b, m2);
          if (result.g.degree != 0 || result.g[0] != Fraction.one) throw CommandError('ERROR NOT COPRIME');
          final r1 = a.divide(b).remainder, r2 = a2.divide(m2).remainder;
          final u = ((r2 - r1) * result.s).divide(m2).remainder;
          save(words[1], r1 + b * u);
        case 'MODPOW':
          checkDivisor(b);
          if (2 * b.degree - 2 > 30) throw CommandError('ERROR DEGREE LIMIT');
          var x = Polynomial.one.divide(b).remainder, y = a.divide(b).remainder;
          var exponent = int.parse(words[3]);
          while (exponent > 0) {
            if (exponent.isOdd) x = (x * y).divide(b).remainder;
            exponent ~/= 2;
            if (exponent != 0) y = (y * y).divide(b).remainder;
          }
          save(words[1], x);
        case 'DERIV': save(words[1], a.derivative(int.parse(words[3])));
        case 'INTEG':
          if (a.degree == 30) throw CommandError('ERROR DEGREE LIMIT');
          save(words[1], a.integral());
        case 'AREA':
          final integral = a.integral();
          final value = integral.evaluate(literals[1]) - integral.evaluate(literals[0]);
          output.add('integral(${words[1]}, ${literals[0]}, ${literals[1]}) = $value');
        case 'TANGENT':
          final point = literals[0];
          final value = a.evaluate(point), slope = a.derivative().evaluate(point);
          save(words[1], Polynomial([value - slope * point, slope]));
        case 'TAYLOR':
          final point = literals[0];
          final shifted = a.compose(Polynomial([point, Fraction.one]));
          final variable = point.isZero ? 'x' : point.sign > 0 ? '(x - $point)' : '(x + ${-point})';
          output.add('taylor(${words[1]}, $point) = ${shifted.format(variable)}');
        case 'COMPOSE': checkComposition(a, b); save(words[1], a.compose(b));
        case 'EVAL':
          for (final point in literals) output.add('${words[1]}($point) = ${a.evaluate(point)}');
        case 'ROOTS':
          checkNonzero(a);
          final roots = rationalRoots(a).roots;
          final result = roots.isEmpty ? 'none' : roots.map((root) => '${root.root} (${root.multiplicity})').join(', ');
          output.add('roots(${words[1]}) = $result');
        case 'FACTOR':
          checkNonzero(a);
          final factorization = rationalRoots(a);
          final result = StringBuffer('factor(${words[1]}) = ${factorization.content}');
          for (final root in factorization.roots) {
            final factor = root.root.isZero ? 'x'
                : '(${Polynomial([Fraction(-root.root.numerator), Fraction(root.root.denominator)]).format()})';
            result.write(' * $factor');
            if (root.multiplicity >= 2) result.write('^${root.multiplicity}');
          }
          if (factorization.remaining.degree >= 1) result.write(' * (${factorization.remaining.format()})');
          output.add(result.toString());
        case 'SQFREE':
          checkNonzero(a);
          final factors = squareFreeFactors(a);
          final result = StringBuffer('sqfree(${words[1]}) = ${a.content()}');
          for (final factor in factors) {
            final value = factor.polynomial;
            final isX = value.degree == 1 && value[0].isZero && value[1] == Fraction.one;
            result.write(' * ${isX ? 'x' : '(${value.format()})'}');
            if (factor.multiplicity >= 2) result.write('^${factor.multiplicity}');
          }
          output.add(result.toString());
        case 'DESCARTES':
          checkNonzero(a);
          output.add('descartes(${words[1]}) = positive ${descartes(a, false)}, negative ${descartes(a, true)}');
        case 'STURM':
          checkNonzero(a);
          if (left.compareTo(right) >= 0) throw CommandError('ERROR BAD INTERVAL');
          final sequence = sturmSequence(a);
          output.add('sturm(${words[1]}, $left, $right) = ${rootCount(sequence, left, right)}');
        case 'ISOLATE':
          checkNonzero(a);
          final precision = int.parse(words[2]);
          final intervals = isolate(a, precision);
          final result = intervals.isEmpty ? 'none' : intervals.map((interval) => '(${interval.left}, ${interval.right}]').join(', ');
          output.add('isolate(${words[1]}, $precision) = $result');
        case 'RESULTANT':
          checkNonzero(a);
          checkNonzero(b);
          output.add('res(${words[1]}, ${words[2]}) = ${resultant(a, b)}');
        case 'DISCRIM':
          checkNonzero(a);
          checkPositiveDegree(a);
          var value = resultant(a, a.derivative()) / a.leading;
          if ((a.degree * (a.degree - 1) ~/ 2).isOdd) value = -value;
          output.add('disc(${words[1]}) = $value');
        case 'POWERSUM':
          checkNonzero(a);
          checkPositiveDegree(a);
          final count = int.parse(words[2]);
          final monic = a.monic();
          final sums = List.filled(count + 1, Fraction.zero);
          for (var j = 1; j <= count; j++) {
            var value = j <= a.degree ? Fraction(j) * monic[a.degree - j] : Fraction.zero;
            for (var i = 1; i <= math.min(j - 1, a.degree); i++) value = value + monic[a.degree - i] * sums[j - i];
            sums[j] = -value;
          }
          output.add('powersum(${words[1]}) = ${sums.skip(1).join(', ')}');
        case 'INTERP': save(words[1], interpolate(literals));
        case 'SPECIAL': save(words[1], special(words[2], int.parse(words[3])));
        default: throw StateError('Unknown command');
      }
    }
    if (deletion != null) storage.remove(deletion);
    for (final (name, value) in pending) storage[name] = value;
    return output;
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final calculator = Calculator();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      for (final output in calculator.execute(line)) stdout.writeln(output);
    } on CommandError catch (error) {
      stdout.writeln(error.message);
    }
  }
}
