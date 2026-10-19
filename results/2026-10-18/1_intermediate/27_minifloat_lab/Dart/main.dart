import 'dart:io';

enum Mode { rne, rna, rtz, rup, rdn }
enum Operation { add, sub, mul, div, sqrt, fma }
enum RealKind { finite, infinity, nan }
enum Flag {
  invalid(1), divbyzero(2), overflow(4), underflow(8), inexact(16);
  final int bit;
  const Flag(this.bit);
}

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

Never fail(String message) => throw CommandError(message);
String modeText(Mode mode) => mode.name.toUpperCase();
String binary(int value, int width) => value.toRadixString(2).padLeft(width, '0');
String relation(int a, int b) => a < b ? 'LT' : a > b ? 'GT' : 'EQ';
String flagsText(int flags) {
  final names = [for (final flag in Flag.values) if (flags & flag.bit != 0) flag.name];
  return 'flags=${names.isEmpty ? 'none' : names.join(',')}';
}

class Result {
  final int pattern, flags;
  const Result(this.pattern, [this.flags = 0]);
}

typedef Units = ({int integer, bool inexact});
typedef Fields = ({bool negative, int exponent, int fraction, int q});

(int, int) scaled(int numerator, int denominator, int exponent) =>
    exponent >= 0 ? (numerator << exponent, denominator) : (numerator, denominator << -exponent);

int integerSqrt(int value) {
  if (value == 0) return 0;
  var root = 1 << ((value.bitLength + 1) ~/ 2);
  while (true) {
    final next = (root + value ~/ root) ~/ 2;
    if (next >= root) return root;
    root = next;
  }
}

bool increment(Mode mode, bool negative, int integer, bool inexact, int halfway) {
  if (!inexact) return false;
  return switch (mode) {
    Mode.rne => halfway > 0 || halfway == 0 && integer.isOdd,
    Mode.rna => halfway >= 0,
    Mode.rtz => false,
    Mode.rup => !negative,
    Mode.rdn => negative,
  };
}

Units roundUnits(Exact value, int exponent, Mode mode) {
  final (n, d) = scaled(value.numerator, value.denominator, value.exponent - exponent);
  var integer = n ~/ d;
  final remainder = n % d;
  if (increment(mode, value.negative, integer, remainder != 0, 2 * remainder - d)) integer++;
  return (integer: integer, inexact: remainder != 0);
}

Units roundSqrtUnits(Exact value, int exponent, Mode mode) {
  final (n, d) = scaled(value.numerator, value.denominator, value.exponent - 2 * exponent);
  var integer = integerSqrt(n ~/ d);
  final inexact = integer * integer * d != n;
  final midpoint = 2 * integer + 1;
  if (increment(mode, false, integer, inexact, 4 * n - d * midpoint * midpoint)) integer++;
  return (integer: integer, inexact: inexact);
}

// The separate sign preserves negative zero in numerator * 2^exponent / denominator.
class Exact {
  final int numerator, exponent, denominator;
  final bool negative;
  const Exact(this.numerator, {this.exponent = 0, this.denominator = 1, this.negative = false});

  Exact negated() => Exact(numerator, exponent: exponent, denominator: denominator, negative: !negative);

  int log2Floor() {
    final t = numerator.bitLength - denominator.bitLength + exponent;
    final (n, d) = scaled(numerator, denominator, exponent - t);
    return n < d ? t - 1 : t;
  }

  String fraction() {
    if (numerator == 0) return '0';
    var (n, d) = scaled(numerator, denominator, exponent);
    final divisor = n.gcd(d);
    n ~/= divisor;
    d ~/= divisor;
    return '${negative ? '-' : ''}$n${d == 1 ? '' : '/$d'}';
  }

  String decimal({bool keepZeroSign = false}) {
    final (n, d) = scaled(numerator, denominator, exponent);
    final text = StringBuffer();
    if (negative && (numerator != 0 || keepZeroSign)) text.write('-');
    text.write(n ~/ d);
    var remainder = n % d;
    if (remainder != 0) {
      text.write('.');
      while (remainder != 0) {
        remainder *= 10;
        text.write(String.fromCharCode(48 + remainder ~/ d));
        remainder %= d;
      }
    }
    return text.toString();
  }

  static Exact product(Exact a, Exact b) => Exact(
    a.numerator * b.numerator,
    exponent: a.exponent + b.exponent,
    denominator: a.denominator * b.denominator,
    negative: a.negative != b.negative,
  );

  static Exact sum(List<Exact> terms, Mode mode) {
    int? exponent;
    for (final term in terms) {
      if (term.numerator != 0 && (exponent == null || term.exponent < exponent)) exponent = term.exponent;
    }
    if (exponent == null) {
      final same = terms.every((term) => term.negative == terms.first.negative);
      return Exact(0, negative: same ? terms.first.negative : mode == Mode.rdn);
    }
    // All summands and differences are dyadic, with denominator 1.
    var numerator = 0;
    for (final term in terms) {
      if (term.numerator == 0) continue;
      final aligned = term.numerator << (term.exponent - exponent);
      numerator += term.negative ? -aligned : aligned;
    }
    return Exact(numerator.abs(), exponent: exponent,
      negative: numerator < 0 || numerator == 0 && mode == Mode.rdn);
  }
}

class MiniFormat {
  final String name;
  final int e, m;
  const MiniFormat(this.name, this.e, this.m);
  int get width => 1 + e + m;
  int get bias => (1 << (e - 1)) - 1;
  int get minExponent => 1 - bias;
  int get maxExponent => bias;
  int get hidden => 1 << m;
  int get exponentMask => (1 << e) - 1;
  int get signBit => 1 << (e + m);
  int get infinity => exponentMask * hidden;
  int get nan => infinity + hidden ~/ 2;
  int get maximum => infinity - 1;

  Fields fields(int pattern) {
    final exponent = (pattern >> m) & exponentMask;
    return (negative: pattern & signBit != 0, exponent: exponent, fraction: pattern & (hidden - 1),
      q: (exponent == 0 ? minExponent : exponent - bias) - m);
  }
  bool isNaN(int pattern) => fields(pattern).exponent == exponentMask && fields(pattern).fraction != 0;
  bool isSignaling(int pattern) => isNaN(pattern) && fields(pattern).fraction < hidden ~/ 2;
  bool isInfinity(int pattern) => pattern & (signBit - 1) == infinity;
  bool isZero(int pattern) => pattern & (signBit - 1) == 0;
  bool isFinite(int pattern) => fields(pattern).exponent != exponentMask;
  int zero(bool negative) => negative ? signBit : 0;
  int inf(bool negative) => zero(negative) + infinity;
  int flip(int pattern) => pattern ^ signBit;

  Exact exact(int pattern) {
    final f = fields(pattern);
    return Exact(f.exponent == 0 ? f.fraction : hidden + f.fraction, exponent: f.q, negative: f.negative);
  }
  String bits(int pattern) {
    final f = fields(pattern);
    return '${f.negative ? 1 : 0}|${binary(f.exponent, e)}|${binary(f.fraction, m)}';
  }
  String hex(int pattern) => '0x${pattern.toRadixString(16).toUpperCase().padLeft((width + 3) ~/ 4, '0')}';
  String value(int pattern) => isNaN(pattern) ? 'nan' : isInfinity(pattern)
      ? (fields(pattern).negative ? '-inf' : 'inf') : exact(pattern).decimal(keepZeroSign: true);
  String patternText(int pattern) => '${bits(pattern)} ${hex(pattern)} ${value(pattern)}';
  String resultText(Result result) => '${patternText(result.pattern)} ${flagsText(result.flags)}';

  Result overflow(bool negative, Mode mode) {
    final toInfinity = mode == Mode.rne || mode == Mode.rna || mode == Mode.rup && !negative || mode == Mode.rdn && negative;
    return Result(zero(negative) + (toInfinity ? infinity : maximum), Flag.overflow.bit | Flag.inexact.bit);
  }

  Result roundNonzero(bool negative, int t, Mode mode, Units Function(int) unitsAt) {
    if (t > maxExponent) return overflow(negative, mode);
    var exponent = (t > minExponent ? t : minExponent) - m;
    final units = unitsAt(exponent);
    var n = units.integer;
    if (n == 2 * hidden) {
      n = hidden;
      exponent++;
    }
    if (exponent > maxExponent - m) return overflow(negative, mode);
    final magnitude = n >= hidden ? (exponent + m + bias) * hidden + n - hidden : n;
    var flags = units.inexact ? Flag.inexact.bit : 0;
    if (units.inexact && t < minExponent &&
        (t < minExponent - 1 || unitsAt(t - m).integer < 2 * hidden)) flags |= Flag.underflow.bit;
    return Result(zero(negative) + magnitude, flags);
  }

  Result round(Exact value, Mode mode) => value.numerator == 0 ? Result(zero(value.negative))
      : roundNonzero(value.negative, value.log2Floor(), mode, (q) => roundUnits(value, q, mode));

  Result sqrt(Exact value, Mode mode) {
    final log = value.log2Floor();
    final t = log >= 0 ? log ~/ 2 : -((-log + 1) ~/ 2);
    return roundNonzero(false, t, mode, (q) => roundSqrtUnits(value, q, mode));
  }
}

class RealInput {
  final RealKind kind;
  final Exact number;
  const RealInput(this.kind, this.number);
  String get text => kind == RealKind.finite ? number.fraction() : kind == RealKind.nan
      ? 'nan' : number.negative ? '-inf' : 'inf';
}

Mode modeAt(List<String> words, int index) => index == words.length ? Mode.rne : switch (words[index]) {
  'RNE' => Mode.rne, 'RNA' => Mode.rna, 'RTZ' => Mode.rtz, 'RUP' => Mode.rup, 'RDN' => Mode.rdn,
  _ => fail('BAD MODE ${words[index]}'),
};

RealInput realInput(String word) {
  if (word == 'nan') return const RealInput(RealKind.nan, Exact(0));
  if (word == 'inf' || word == '-inf') return RealInput(RealKind.infinity, Exact(0, negative: word == '-inf'));
  if (word.startsWith('0b') || word.startsWith('0x')) fail('BAD OPERAND $word');
  final negative = word.startsWith('-');
  var body = negative ? word.substring(1) : word;
  final slash = body.indexOf('/');
  if (slash >= 0) {
    final n = int.parse(body.substring(0, slash));
    final d = int.parse(body.substring(slash + 1));
    if (d == 0) fail('BAD OPERAND $word');
    return RealInput(RealKind.finite, Exact(n, denominator: d, negative: negative));
  }
  final dot = body.indexOf('.');
  var denominator = 1;
  if (dot >= 0) {
    for (var i = dot + 1; i < body.length; i++) denominator *= 10;
    body = body.replaceRange(dot, dot + 1, '');
  }
  return RealInput(RealKind.finite, Exact(int.parse(body), denominator: denominator, negative: negative));
}

Result encoded(MiniFormat f, RealInput input, Mode mode) => switch (input.kind) {
  RealKind.nan => Result(f.nan),
  RealKind.infinity => Result(f.inf(input.number.negative)),
  RealKind.finite => f.round(input.number, mode),
};

int operand(MiniFormat f, String word) {
  final bits = word.startsWith('0b'), hex = word.startsWith('0x');
  if (bits || hex) {
    if (word.length - 2 != (bits ? f.width : (f.width + 3) ~/ 4)) fail('BAD OPERAND $word');
    final pattern = int.parse(word.substring(2), radix: bits ? 2 : 16);
    if (pattern >= 1 << f.width) fail('BAD OPERAND $word');
    return pattern;
  }
  return encoded(f, realInput(word), Mode.rne).pattern;
}

Result calculate(MiniFormat f, Operation operation, Mode mode, List<int> inputs) {
  if (inputs.any(f.isNaN)) return Result(f.nan, inputs.any(f.isSignaling) ? Flag.invalid.bit : 0);
  final a = inputs[0], negative = f.fields(inputs[0]).negative;
  final invalid = Result(f.nan, Flag.invalid.bit);
  if (operation == Operation.sqrt) {
    if (f.isZero(a)) return Result(a);
    if (negative) return invalid;
    if (f.isInfinity(a)) return Result(a);
    return f.sqrt(f.exact(a), mode);
  }
  final b = operation == Operation.sub ? f.flip(inputs[1]) : inputs[1];
  final sigma = negative != f.fields(b).negative;
  if (operation == Operation.add || operation == Operation.sub) {
    if (f.isInfinity(a) && f.isInfinity(b) && sigma) return invalid;
    if (f.isInfinity(a)) return Result(a);
    if (f.isInfinity(b)) return Result(b);
    return f.round(Exact.sum([f.exact(a), f.exact(b)], mode), mode);
  }
  if (operation == Operation.mul) {
    if (f.isInfinity(a) || f.isInfinity(b)) return f.isZero(a) || f.isZero(b) ? invalid : Result(f.inf(sigma));
    if (f.isZero(a) || f.isZero(b)) return Result(f.zero(sigma));
    return f.round(Exact.product(f.exact(a), f.exact(b)), mode);
  }
  if (operation == Operation.div) {
    if (f.isInfinity(a)) return f.isInfinity(b) ? invalid : Result(f.inf(sigma));
    if (f.isInfinity(b)) return Result(f.zero(sigma));
    if (f.isZero(b)) return f.isZero(a) ? invalid : Result(f.inf(sigma), Flag.divbyzero.bit);
    if (f.isZero(a)) return Result(f.zero(sigma));
    final x = f.exact(a), y = f.exact(b);
    return f.round(Exact(x.numerator * y.denominator, exponent: x.exponent - y.exponent,
      denominator: x.denominator * y.numerator, negative: sigma), mode);
  }
  final c = inputs[2];
  if (f.isInfinity(a) || f.isInfinity(b)) {
    if (f.isZero(a) || f.isZero(b) || f.isInfinity(c) && f.fields(c).negative != sigma) return invalid;
    return Result(f.inf(sigma));
  }
  if (f.isInfinity(c)) return Result(c);
  return f.round(Exact.sum([Exact.product(f.exact(a), f.exact(b)), f.exact(c)], mode), mode);
}

int nextUp(MiniFormat f, int pattern) => pattern == f.infinity ? pattern
    : f.isZero(pattern) ? 1 : pattern + (f.fields(pattern).negative ? -1 : 1);
String difference(MiniFormat f, int pattern, Exact exact) => !f.isFinite(pattern) ? f.value(pattern)
    : Exact.sum([f.exact(pattern), exact.negated()], Mode.rne).fraction();

class Laboratory {
  final formats = <String, MiniFormat>{
    'HALF': const MiniFormat('HALF', 5, 10), 'E5M2': const MiniFormat('E5M2', 5, 2), 'E4M3': const MiniFormat('E4M3', 4, 3),
  };
  static const integerTypes = <String, (int, int)>{
    'I8': (-128, 127), 'U8': (0, 255), 'I16': (-32768, 32767), 'U16': (0, 65535),
    'I32': (-2147483648, 2147483647), 'U32': (0, 4294967295),
  };
  static const operations = {
    'ADD': Operation.add, 'SUB': Operation.sub, 'MUL': Operation.mul,
    'DIV': Operation.div, 'SQRT': Operation.sqrt, 'FMA': Operation.fma,
  };
  final List<String> output = [];
  void emit(String line) => output.add(line);
  MiniFormat format(String name) => formats[name] ?? fail('UNKNOWN FORMAT $name');

  List<int> operands(MiniFormat f, List<String> words, int begin, int end) =>
      [for (var i = begin; i < end; i++) operand(f, words[i])];

  void summary(MiniFormat f, Mode mode, List<int> patterns, Result result) {
    final exact = Exact.sum(patterns.map(f.exact).toList(), mode);
    emit('RESULT ${f.resultText(result)}');
    emit('EXACT ${exact.decimal()}');
    emit('ROUNDED ${f.resultText(f.round(exact, mode))}');
    emit('DIFF ${difference(f, result.pattern, exact)}');
  }

  void summation(String command, MiniFormat f, Mode mode, List<int> patterns) {
    if (!patterns.every(f.isFinite)) fail('NOT FINITE');
    emit('$command ${f.name} ${modeText(mode)} count=${patterns.length}');
    var sum = patterns.first, compensation = 0, flags = 0;
    for (var i = 1; i < patterns.length; i++) {
      if (command == 'SUM') {
        final added = calculate(f, Operation.add, mode, [sum, patterns[i]]);
        sum = added.pattern;
        flags |= added.flags;
        emit('PARTIAL ${i + 1} ${f.resultText(added)}');
      } else {
        final y = calculate(f, Operation.sub, mode, [patterns[i], compensation]);
        final t = calculate(f, Operation.add, mode, [sum, y.pattern]);
        final d = calculate(f, Operation.sub, mode, [t.pattern, sum]);
        final c = calculate(f, Operation.sub, mode, [d.pattern, y.pattern]);
        sum = t.pattern;
        compensation = c.pattern;
        final step = y.flags | t.flags | d.flags | c.flags;
        flags |= step;
        emit('KSTEP ${i + 1} sum=${f.value(sum)} comp=${f.value(compensation)} ${flagsText(step)}');
      }
    }
    summary(f, mode, patterns, Result(sum, flags));
  }

  void dot(MiniFormat f, Mode mode, List<int> a, List<int> b) {
    if (a.length != b.length) fail('LENGTH MISMATCH');
    if (!a.every(f.isFinite) || !b.every(f.isFinite)) fail('NOT FINITE');
    var naive = calculate(f, Operation.mul, mode, [a[0], b[0]]);
    var chained = naive;
    for (var i = 1; i < a.length; i++) {
      final product = calculate(f, Operation.mul, mode, [a[i], b[i]]);
      final added = calculate(f, Operation.add, mode, [naive.pattern, product.pattern]);
      naive = Result(added.pattern, naive.flags | product.flags | added.flags);
      final fused = calculate(f, Operation.fma, mode, [a[i], b[i], chained.pattern]);
      chained = Result(fused.pattern, chained.flags | fused.flags);
    }
    final exact = Exact.sum([for (var i = 0; i < a.length; i++) Exact.product(f.exact(a[i]), f.exact(b[i]))], mode);
    emit('DOT ${f.name} ${modeText(mode)} n=${a.length}');
    emit('NAIVE ${f.resultText(naive)}');
    emit('CHAINED ${f.resultText(chained)}');
    emit('EXACT ${exact.decimal()}');
    emit('FUSED ${f.resultText(f.round(exact, mode))}');
    emit('DIFF naive=${difference(f, naive.pattern, exact)} chained=${difference(f, chained.pattern, exact)}');
  }

  void table(MiniFormat f) {
    if (f.width > 8) fail('TABLE TOO LARGE');
    final count = f.infinity;
    emit('TABLE ${f.name} count=$count');
    for (var pattern = 0; pattern < count; pattern++) {
      final gap = pattern == count - 1 ? '-'
          : Exact.sum([f.exact(pattern + 1), f.exact(pattern).negated()], Mode.rne).decimal();
      emit('ENTRY $pattern ${f.patternText(pattern)} gap=$gap');
    }
    emit('MAX ${f.patternText(f.maximum)}');
    emit('MINNORMAL ${f.patternText(f.hidden)}');
    emit('MINSUBNORMAL ${f.patternText(1)}');
    emit('EPSILON ${Exact(1, exponent: -f.m).decimal()}');
    emit('PATTERNS finite=${2 * count} infinite=2 nan=${2 * (f.hidden - 1)} total=${1 << f.width}');
  }

  List<String> execute(String line) {
    output.clear();
    final words = line.split(' '), command = words[0];
    if (command == 'FORMAT') {
      final name = words[1], e = int.parse(words[2]), m = int.parse(words[3]);
      if (formats.containsKey(name)) fail('FORMAT EXISTS $name');
      if (e < 2 || e > 5 || m < 1 || m > 10) fail('BAD FORMAT');
      final f = MiniFormat(name, e, m);
      formats[name] = f;
      emit('FORMAT $name e=$e m=$m bits=${f.width} bias=${f.bias} emin=${f.minExponent} emax=${f.maxExponent}');
      return output;
    }
    final f = format(words[1]);
    final operation = operations[command];
    if (command == 'ENCODE') {
      final input = realInput(words[2]);
      final mode = modeAt(words, 3);
      emit('ENCODE ${f.name} ${modeText(mode)} ${input.text} ${f.resultText(encoded(f, input, mode))}');
    } else if (command == 'CONVERT') {
      final g = format(words[2]);
      final a = operand(f, words[3]);
      final mode = modeAt(words, 4);
      final result = f.isNaN(a) ? Result(g.nan, f.isSignaling(a) ? Flag.invalid.bit : 0)
          : f.isInfinity(a) ? Result(g.inf(f.fields(a).negative)) : g.round(f.exact(a), mode);
      emit('CONVERT ${f.name} ${g.name} ${modeText(mode)} ${g.resultText(result)}');
    } else if (command == 'SUM' || command == 'KAHAN' || command == 'DOT') {
      final mode = modeAt(words, 2);
      if (command == 'DOT') {
        final separator = words.indexOf('|');
        final a = operands(f, words, 3, separator);
        final b = operands(f, words, separator + 1, words.length);
        dot(f, mode, a, b);
      } else {
        summation(command, f, mode, operands(f, words, 3, words.length));
      }
    } else if (command == 'TABLE') {
      table(f);
    } else if (operation != null) {
      final count = operation == Operation.sqrt ? 1 : operation == Operation.fma ? 3 : 2;
      final patterns = operands(f, words, 2, 2 + count);
      final mode = modeAt(words, 2 + count);
      emit('$command ${f.name} ${modeText(mode)} ${f.resultText(calculate(f, operation, mode, patterns))}');
    } else {
      final a = operand(f, words[2]);
      final fields = f.fields(a);
      if (command == 'DECODE') {
        final classification = f.isNaN(a) ? (f.isSignaling(a) ? 'snan' : 'qnan') : f.isInfinity(a) ? 'infinity'
            : f.isZero(a) ? 'zero' : fields.exponent == 0 ? 'subnormal' : 'normal';
        emit('DECODE ${f.name} ${f.bits(a)} ${f.hex(a)} $classification sign=${fields.negative ? 1 : 0}');
        final heading = 'FIELDS exponent=${fields.exponent} fraction=${fields.fraction}';
        if (f.isFinite(a)) {
          emit('$heading unbiased=${fields.q + f.m} significand=${fields.exponent == 0 ? 0 : 1}.${binary(fields.fraction, f.m)}');
          emit('VALUE ${f.exact(a).fraction()} ${f.value(a)}');
        } else {
          emit(f.isNaN(a) ? '$heading payload=${fields.fraction % (f.hidden ~/ 2)}' : heading);
        }
      } else if (command == 'COMPARE') {
        final b = operand(f, words[3]);
        int key(int pattern) => f.fields(pattern).negative ? -(pattern - f.signBit) - 1 : pattern;
        final order = relation(key(a), key(b));
        final numeric = f.isNaN(a) || f.isNaN(b) ? 'UN' : f.isZero(a) && f.isZero(b) ? 'EQ' : order;
        final flags = f.isSignaling(a) || f.isSignaling(b) ? Flag.invalid.bit : 0;
        emit('COMPARE ${f.name} ${f.hex(a)} ${f.hex(b)} $numeric total=$order ${flagsText(flags)}');
      } else if (command == 'TOINT') {
        final range = integerTypes[words[3]] ?? fail('BAD TYPE ${words[3]}');
        final mode = modeAt(words, 4);
        final prefix = 'TOINT ${f.name} ${words[3]} ${modeText(mode)}';
        if (!f.isFinite(a)) {
          emit('$prefix invalid flags=invalid');
        } else {
          final units = roundUnits(f.exact(a), 0, mode);
          final integer = fields.negative ? -units.integer : units.integer;
          emit(integer < range.$1 || integer > range.$2 ? '$prefix invalid flags=invalid'
              : '$prefix $integer ${flagsText(units.inexact ? Flag.inexact.bit : 0)}');
        }
      } else {
        final Result result;
        if (f.isNaN(a)) {
          result = Result(f.nan, f.isSignaling(a) ? Flag.invalid.bit : 0);
        } else if (command == 'NEXTUP') {
          result = Result(nextUp(f, a));
        } else if (command == 'NEXTDOWN') {
          result = Result(f.flip(nextUp(f, f.flip(a))));
        } else {
          result = Result(f.isInfinity(a) ? f.infinity : f.round(Exact(1, exponent: fields.q), Mode.rne).pattern);
        }
        emit('$command ${f.name} ${f.resultText(result)}');
      }
    }
    return output;
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final laboratory = Laboratory();
  for (var i = 0; i < count; i++) {
    try {
      stdout.write('${laboratory.execute(stdin.readLineSync()!).join('\n')}\n');
    } on CommandError catch (error) {
      stdout.write('ERROR ${error.message}\n');
    }
  }
}
