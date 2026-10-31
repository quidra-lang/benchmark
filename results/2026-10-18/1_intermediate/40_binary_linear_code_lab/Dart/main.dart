import 'dart:collection';
import 'dart:io';

final class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
}

Never fail(String message) => throw CommandError(message);
bool bit(int word, int length, int column) =>
    ((word >> (length - column - 1)) & 1) != 0;
String bits(int word, int length) => word.toRadixString(2).padLeft(length, '0');
String yes(bool value) => value ? 'yes' : 'no';
int weight(int word) {
  var count = 0;
  while (word != 0) {
    word &= word - 1;
    count++;
  }
  return count;
}

({int quotient, int remainder}) divide(int dividend, int divisor) {
  var quotient = 0;
  while (dividend != 0 && dividend.bitLength >= divisor.bitLength) {
    final shift = dividend.bitLength - divisor.bitLength;
    quotient ^= 1 << shift;
    dividend ^= divisor << shift;
  }
  return (quotient: quotient, remainder: dividend);
}

List<int> basis(Iterable<int> rows, int length) {
  final pivots = List<int>.filled(length, 0), kept = <int>[];
  for (final original in rows) {
    var row = original;
    for (var column = 0; column < length; column++) {
      if (!bit(row, length, column)) continue;
      if (pivots[column] != 0) {
        row ^= pivots[column];
      } else {
        pivots[column] = row;
        kept.add(original);
        break;
      }
    }
  }
  return kept;
}

({List<int> rows, List<int> columns}) rref(Iterable<int> original, int length) {
  final rows = original.toList(), columns = <int>[];
  for (var column = 0; column < length; column++) {
    final pivot = columns.length;
    var found = pivot;
    while (found < rows.length && !bit(rows[found], length, column)) {
      found++;
    }
    if (found == rows.length) continue;
    final old = rows[pivot];
    rows[pivot] = rows[found];
    rows[found] = old;
    for (var row = 0; row < rows.length; row++) {
      if (row != pivot && bit(rows[row], length, column)) {
        rows[row] ^= rows[pivot];
      }
    }
    columns.add(column);
  }
  return (rows: rows.take(columns.length).toList(), columns: columns);
}

List<int> nullspace(Iterable<int> original, int length) {
  final reduced = rref(original, length), result = <int>[];
  for (var column = 0; column < length; column++) {
    if (reduced.columns.contains(column)) continue;
    var word = 1 << (length - column - 1);
    for (var row = 0; row < reduced.rows.length; row++) {
      if (bit(reduced.rows[row], length, column)) {
        word |= 1 << (length - reduced.columns[row] - 1);
      }
    }
    result.add(word);
  }
  return result;
}

List<int> span(Iterable<int> rows) {
  final words = <int>[0];
  for (final row in rows) {
    final count = words.length;
    for (var i = 0; i < count; i++) {
      words.add(words[i] ^ row);
    }
  }
  return words;
}

List<int> distribution(Iterable<int> words, int length) {
  final counts = List<int>.filled(length + 1, 0);
  for (final word in words) {
    counts[weight(word)]++;
  }
  return counts;
}

String weightList(List<int> counts) => [
  for (var i = 0; i < counts.length; i++)
    if (counts[i] != 0) '$i:${counts[i]}',
].join(' ');

void checkDimension(int n, int k) {
  if (k < 1 || k > 12 || n - k < 1 || n - k > 12) {
    fail('bad dimension $n $k');
  }
}

int removeBit(int word, int length, int column) {
  final low = length - column - 1;
  return ((word >> (low + 1)) << low) | (word & ((1 << low) - 1));
}

List<int> reedMuller(int order, int variables) {
  final length = 1 << variables;
  if (order == 0) return [(1 << length) - 1];
  final firstOrder = order < variables ? order : variables - 1;
  return [
    for (final row in reedMuller(firstOrder, variables - 1))
      (row << (length ~/ 2)) | row,
    ...reedMuller(order - 1, variables - 1),
  ];
}

typedef Decoded = ({int error, int word, int message});

final class Code {
  final int n;
  final List<int> g, h;
  final int? polynomial;
  late final List<int> words;
  late final Map<int, int> _messages;
  List<int>? _leaders;
  int get k => g.length;
  String get encoder => polynomial == null ? 'matrix' : 'polynomial';

  factory Code(int n, List<int> g, {List<int>? h, int? polynomial}) {
    checkDimension(n, g.length);
    return Code._(n, List.unmodifiable(g),
        List.unmodifiable(h ?? nullspace(g, n)), polynomial);
  }

  Code._(this.n, this.g, this.h, this.polynomial) {
    _messages = {
      for (var message = 0; message < (1 << k); message++) encode(message): message,
    };
    words = List.unmodifiable(_messages.keys.toList()..sort());
  }

  int encode(int message) {
    final p = polynomial;
    if (p != null) {
      final shifted = message << (n - k);
      return shifted | divide(shifted, p).remainder;
    }
    var word = 0;
    for (var row = 0; row < k; row++) {
      if (bit(message, k, row)) word ^= g[row];
    }
    return word;
  }

  int syndrome(int word) =>
      h.fold(0, (result, row) => (result << 1) | (weight(row & word) % 2));
  int message(int word) => _messages[word]!;
  bool contains(int word) => _messages.containsKey(word);

  List<int> get leaders {
    if (_leaders != null) return _leaders!;
    final result = List<int>.filled(1 << (n - k), -1);
    result[0] = 0;
    var remaining = result.length - 1;
    for (var count = 1; remaining > 0; count++) {
      var word = (1 << count) - 1;
      while (word < (1 << n)) {
        final s = syndrome(word);
        if (result[s] == -1) {
          result[s] = word;
          if (--remaining == 0) break;
        }
        final lowest = word & -word, next = word + lowest;
        word = next | (((next ^ word) >> 2) ~/ lowest);
      }
    }
    return _leaders = List.unmodifiable(result);
  }

  Decoded decode(int received) {
    final error = leaders[syndrome(received)], word = received ^ error;
    return (error: error, word: word, message: message(word));
  }

  String decodedText(Decoded value) =>
      'codeword ${bits(value.word, n)} message ${bits(value.message, k)} '
      'error ${bits(value.error, n)} weight ${weight(value.error)}';
}

enum Verb {
  gen, pcheck, hamming, simplex, repetition, parity, rm, cyclic, dual, extend,
  puncture, shorten, augment, expurgate, permute, directsum, uuv, product,
  list, delete, show, info, systematic, weights, covering, burst, trellis,
  stdarray, equal, encode, syndrome, decode, bounded, coset, erasure, interleave,
  crc, crccheck, factor, macwilliams, bounds;

  bool get defining => index <= Verb.product.index;
}

enum Argument { name, code, number, bits, erasure }

final class Format {
  final List<Argument> types;
  final Argument? repeated;
  final int maximum;
  const Format(this.types, {this.repeated, this.maximum = 0});
}

final class Command {
  final Verb verb;
  final List<String> args;
  const Command(this.verb, this.args);
}

final verbs = {for (final verb in Verb.values) verb.name.toUpperCase(): verb};
final formats = <Verb, Format>{
  for (final verb in [Verb.gen, Verb.pcheck])
    verb: const Format([Argument.name], repeated: Argument.bits, maximum: 24),
  for (final verb in [Verb.hamming, Verb.simplex, Verb.repetition, Verb.parity])
    verb: const Format([Argument.name, Argument.number]),
  Verb.rm: const Format([Argument.name, Argument.number, Argument.number]),
  Verb.cyclic: const Format([Argument.name, Argument.number, Argument.bits]),
  for (final verb in [Verb.dual, Verb.extend, Verb.augment, Verb.expurgate])
    verb: const Format([Argument.name, Argument.code]),
  for (final verb in [Verb.puncture, Verb.shorten])
    verb: const Format([Argument.name, Argument.code, Argument.number]),
  Verb.permute: const Format([Argument.name, Argument.code],
      repeated: Argument.number, maximum: 24),
  for (final verb in [Verb.directsum, Verb.uuv, Verb.product])
    verb: const Format([Argument.name, Argument.code, Argument.code]),
  Verb.list: const Format([]),
  for (final verb in [Verb.delete, Verb.show, Verb.info, Verb.systematic,
      Verb.weights, Verb.covering, Verb.burst, Verb.trellis, Verb.stdarray])
    verb: const Format([Argument.code]),
  Verb.equal: const Format([Argument.code, Argument.code]),
  for (final verb in [Verb.encode, Verb.syndrome, Verb.decode, Verb.coset])
    verb: const Format([Argument.code, Argument.bits]),
  Verb.bounded: const Format([Argument.code, Argument.number, Argument.bits]),
  Verb.erasure: const Format([Argument.code, Argument.erasure]),
  Verb.interleave: const Format([Argument.code, Argument.number, Argument.number],
      repeated: Argument.bits, maximum: 8),
  for (final verb in [Verb.crc, Verb.crccheck])
    verb: const Format([Argument.bits, Argument.bits]),
  Verb.factor: const Format([Argument.number]),
  Verb.macwilliams: const Format([Argument.number],
      repeated: Argument.number, maximum: 25),
  Verb.bounds: const Format([Argument.number, Argument.number]),
};

bool valid(String text, Argument kind) {
  final bytes = text.codeUnits;
  bool letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
  bool digit(int c) => c >= 48 && c <= 57;
  if (bytes.isEmpty) return false;
  return switch (kind) {
    Argument.name || Argument.code => bytes.length <= 8 &&
        letter(bytes.first) && bytes.every((c) => letter(c) || digit(c)),
    Argument.number => bytes.length <= 4 &&
        (bytes.length == 1 || bytes.first != 48) && bytes.every(digit),
    Argument.bits || Argument.erasure => bytes.length <= 30 &&
        bytes.every((c) => c == 48 || c == 49 || kind == Argument.erasure && c == 63),
  };
}

final choose = List.generate(25, (n) {
  final row = List<int>.filled(25, 0);
  row[0] = 1;
  for (var k = 1; k <= n; k++) {
    row[k] = row[k - 1] * (n - k + 1) ~/ k;
  }
  return row;
});
int binomial(int n, int k) => k < 0 || k > n ? 0 : choose[n][k];
int volume(int n, int t) => choose[n].take(t + 1).fold(0, (a, b) => a + b);

final class Laboratory {
  final _codes = SplayTreeMap<String, Code>();

  Command parse(String line) {
    final words = line.split(' '), verb = verbs[words[0]];
    if (verb == null) fail('unknown command ${words[0]}');
    final spec = formats[verb]!, args = words.sublist(1);
    final extra = args.length - spec.types.length;
    if (spec.repeated == null ? extra != 0 : extra < 1 || extra > spec.maximum) {
      fail('bad arguments');
    }
    for (var i = 0; i < args.length; i++) {
      final kind = i < spec.types.length ? spec.types[i] : spec.repeated!;
      if (!valid(args[i], kind)) fail('bad arguments');
    }
    for (var i = 0; i < spec.types.length; i++) {
      if (spec.types[i] == Argument.code && !_codes.containsKey(args[i])) {
        fail('no code ${args[i]}');
      }
    }
    return Command(verb, args);
  }

  List<String> define(Verb verb, List<String> args) {
    final name = args[0], source = _codes[args[1]];
    final other = args.length > 2 ? _codes[args[2]] : null;
    var n = 0, g = <int>[];
    List<int>? h;
    int? polynomial;
    switch (verb) {
      case Verb.gen || Verb.pcheck:
        n = args[1].length;
        if (args.skip(1).any((word) => word.length != n)) fail('bad length');
        final rows = basis(args.skip(1).map((word) => int.parse(word, radix: 2)), n);
        if (verb == Verb.gen) {
          g = rows;
        } else {
          h = rows;
          g = nullspace(rows, n);
        }
      case Verb.hamming || Verb.simplex:
        final r = int.parse(args[1]);
        if (r < 2 || r > 4) fail('bad parameter');
        n = (1 << r) - 1;
        final rows = List<int>.filled(r, 0);
        for (var column = 1; column <= n; column++) {
          for (var row = 0; row < r; row++) {
            rows[row] = (rows[row] << 1) | (bit(column, r, row) ? 1 : 0);
          }
        }
        if (verb == Verb.hamming) {
          h = rows;
          g = nullspace(rows, n);
        } else {
          g = rows;
        }
      case Verb.repetition || Verb.parity:
        n = int.parse(args[1]);
        if (n < 2 || n > 24) fail('bad parameter');
        g = verb == Verb.repetition ? [(1 << n) - 1] : [
          for (var row = 0; row < n - 1; row++) (1 << (n - row - 1)) | 1,
        ];
      case Verb.rm:
        final r = int.parse(args[1]), m = int.parse(args[2]);
        if (m < 1 || m > 4 || r > m) fail('bad parameter');
        n = 1 << m;
        g = reedMuller(r, m);
      case Verb.cyclic:
        n = int.parse(args[1]);
        final text = args[2], d = text.length - 1;
        if (n < 2 || n > 24 || text.startsWith('0') ||
            text.length < 2 || text.length > n) fail('bad parameter');
        final p = int.parse(text, radix: 2);
        if (divide((1 << n) | 1, p).remainder != 0) fail('not a divisor');
        final k = n - d;
        checkDimension(n, k);
        polynomial = p;
        g = [for (var row = 0; row < k; row++) p << (k - row - 1)];
        h = List<int>.filled(d, 0);
        for (var column = 0; column < n; column++) {
          final remainder = divide(1 << (n - column - 1), p).remainder;
          for (var row = 0; row < d; row++) {
            h[row] = (h[row] << 1) | (bit(remainder, d, row) ? 1 : 0);
          }
        }
      case Verb.dual:
        n = source!.n;
        g = source.h;
        h = source.g;
      case Verb.extend:
        n = source!.n + 1;
        g = [for (final row in source.g) (row << 1) | (weight(row) % 2)];
      case Verb.puncture || Verb.shorten:
        final a = source!, column = int.parse(args[2]) - 1;
        if (column < 0 || column >= a.n) fail('bad position');
        var rows = a.g.toList();
        if (verb == Verb.shorten) {
          final pivot = rows.indexWhere((row) => bit(row, a.n, column));
          if (pivot != -1) {
            final z = rows.removeAt(pivot);
            rows = [for (final row in rows) bit(row, a.n, column) ? row ^ z : row];
          }
        }
        n = a.n - 1;
        g = [for (final row in rows) removeBit(row, a.n, column)];
        if (verb == Verb.puncture) g = basis(g, n);
      case Verb.augment:
        n = source!.n;
        g = basis([...source.g, (1 << n) - 1], n);
      case Verb.expurgate:
        n = source!.n;
        g = source.g.toList();
        final pivot = g.indexWhere((row) => weight(row).isOdd);
        if (pivot != -1) {
          final z = g.removeAt(pivot);
          g = [for (final row in g) weight(row).isOdd ? row ^ z : row];
        }
      case Verb.permute:
        final a = source!, order = args.skip(2).map(int.parse).toList();
        n = a.n;
        if (order.length != n || order.toSet().length != n ||
            order.any((column) => column < 1 || column > n)) fail('bad permutation');
        g = [
          for (final row in a.g)
            order.fold(0, (result, column) =>
                (result << 1) | (bit(row, n, column - 1) ? 1 : 0)),
        ];
      case Verb.directsum || Verb.uuv || Verb.product:
        final a = source!, b = other!;
        if (verb == Verb.uuv && a.n != b.n) fail('bad length');
        n = verb == Verb.product ? a.n * b.n : a.n + b.n;
        checkDimension(n, verb == Verb.product ? a.k * b.k : a.k + b.k);
        if (verb == Verb.product) {
          for (final x in a.g) {
            for (final y in b.g) {
              var row = 0;
              for (var i = 0; i < a.n; i++) {
                row = (row << b.n) | (bit(x, a.n, i) ? y : 0);
              }
              g.add(row);
            }
          }
        } else {
          g = [
            for (final row in a.g) (row << b.n) | (verb == Verb.uuv ? row : 0),
            ...b.g,
          ];
        }
      default:
        throw StateError('Not a defining command');
    }
    final code = Code(n, g, h: h, polynomial: polynomial);
    final prefix = _codes.containsKey(name) ? 'redefined' : 'defined';
    _codes[name] = code;
    return ['$prefix $name n $n k ${code.k}'];
  }

  List<String> systematic(String name, Code code) {
    final n = code.n, k = code.k, rows = code.g.toList();
    final order = List.generate(n, (i) => i + 1);
    for (var pivot = 0; pivot < k; pivot++) {
      var column = pivot;
      while (!rows.skip(pivot).any((row) => bit(row, n, column))) {
        column++;
      }
      if (column != pivot) {
        final mask = (1 << (n - pivot - 1)) | (1 << (n - column - 1));
        for (var row = 0; row < k; row++) {
          if (bit(rows[row], n, pivot) != bit(rows[row], n, column)) rows[row] ^= mask;
        }
        final old = order[pivot];
        order[pivot] = order[column];
        order[column] = old;
      }
      var found = pivot;
      while (!bit(rows[found], n, pivot)) {
        found++;
      }
      final old = rows[pivot];
      rows[pivot] = rows[found];
      rows[found] = old;
      for (var row = 0; row < k; row++) {
        if (row != pivot && bit(rows[row], n, pivot)) rows[row] ^= rows[pivot];
      }
    }
    final output = ['systematic $name perm ${order.join(' ')}',
      for (final row in rows) 'G ${bits(row, n)}'];
    for (var column = k; column < n; column++) {
      var row = rows.fold(0, (result, word) =>
          (result << 1) | (bit(word, n, column) ? 1 : 0));
      row = (row << (n - k)) | (1 << (n - column - 1));
      output.add('H ${bits(row, n)}');
    }
    return output;
  }

  List<String> burst(String name, Code code) {
    var detect = code.n;
    for (final word in code.words.skip(1)) {
      final span = word.bitLength - (word & -word).bitLength;
      if (span < detect) detect = span;
    }
    final seen = <int>{0};
    for (var length = 1; length <= code.n; length++) {
      for (var start = 0; start <= code.n - length; start++) {
        final limit = length == 1 ? 1 : 1 << (length - 2);
        for (var middle = 0; middle < limit; middle++) {
          final pattern = length == 1 ? 1 : (1 << (length - 1)) | (middle << 1) | 1;
          final s = code.syndrome(pattern << (code.n - start - length));
          if (!seen.add(s)) return ['burst $name detect $detect correct ${length - 1}'];
        }
      }
    }
    throw StateError('A nonzero codeword is an undetectable burst');
  }

  List<String> interleave(String name, Code code, List<String> args) {
    final messages = args.sublist(3), start = int.parse(args[1]);
    final length = int.parse(args[2]), depth = messages.length;
    if (messages.any((word) => word.length != code.k)) fail('bad length');
    if (start < 1 || length < 1 || start + length - 1 > depth * code.n) {
      fail('bad burst');
    }
    final sentWords = [for (final word in messages) code.encode(int.parse(word, radix: 2))];
    final receivedWords = List<int>.filled(depth, 0);
    final sent = StringBuffer(), received = StringBuffer();
    for (var column = 0; column < code.n; column++) {
      for (var row = 0; row < depth; row++) {
        final position = column * depth + row + 1;
        final original = bit(sentWords[row], code.n, column);
        final changed = original != (start <= position && position < start + length);
        sent.write(original ? '1' : '0');
        received.write(changed ? '1' : '0');
        receivedWords[row] = (receivedWords[row] << 1) | (changed ? 1 : 0);
      }
    }
    final output = ['interleave $name depth $depth burst $start $length',
      'sent $sent', 'recv $received'];
    var correct = 0;
    for (var row = 0; row < depth; row++) {
      final decoded = code.decode(receivedWords[row]);
      final message = bits(decoded.message, code.k), ok = message == messages[row];
      if (ok) correct++;
      output.add('row ${row + 1} errors ${weight(receivedWords[row] ^ sentWords[row])} '
          'corrected ${weight(decoded.error)} message $message ${ok ? 'ok' : 'wrong'}');
    }
    output.add('result ok $correct wrong ${depth - correct}');
    return output;
  }

  List<String> execute(Command command) {
    final verb = command.verb, args = command.args;
    if (verb.defining) return define(verb, args);
    if ([Verb.crc, Verb.crccheck, Verb.factor, Verb.macwilliams, Verb.bounds].contains(verb)) {
      return independent(verb, args);
    }
    if (verb == Verb.list) {
      return ['codes ${_codes.length}', for (final entry in _codes.entries)
        '${entry.key} n ${entry.value.n} k ${entry.value.k} encoder ${entry.value.encoder}'];
    }
    final name = args[0];
    if (verb == Verb.delete) {
      _codes.remove(name);
      return ['deleted $name'];
    }
    final code = _codes[name]!, n = code.n, k = code.k;
    switch (verb) {
      case Verb.show:
        final p = code.polynomial;
        return ['code $name n $n k $k encoder ${code.encoder}',
          if (p != null) 'poly g ${bits(p, n - k + 1)} h ${bits(divide((1 << n) | 1, p).quotient, k + 1)}',
          for (final row in code.g) 'G ${bits(row, n)}',
          for (final row in code.h) 'H ${bits(row, n)}'];
      case Verb.info:
        final distance = code.words.skip(1).map(weight).reduce((a, b) => a < b ? a : b);
        final t = (distance - 1) ~/ 2, divisor = n.gcd(k);
        final cyclic = code.g.every((row) =>
            code.contains(((row << 1) & ((1 << n) - 1)) | (row >> (n - 1))));
        return ['info $name n $n k $k rate ${k ~/ divisor}/${n ~/ divisor} '
          'd $distance t $t perfect ${yes(volume(n, t) == (1 << (n - k)))} '
          'mds ${yes(distance == n - k + 1)} cyclic ${cyclic ? code.words[1].toRadixString(2) : 'no'}'];
      case Verb.systematic:
        return systematic(name, code);
      case Verb.weights:
        final a = distribution(code.words, n), b = distribution(span(code.h), n);
        final orthogonal = code.g.every((x) => code.g.every((y) => weight(x & y).isEven));
        final formal = List.generate(n + 1, (i) => i).every((i) => a[i] == b[i]);
        return ['weights $name ${weightList(a)}', 'dual $name ${weightList(b)}',
          'duality $name self-orthogonal ${yes(orthogonal)} self-dual ${yes(orthogonal && n == 2 * k)} '
          'formally-self-dual ${yes(formal)}'];
      case Verb.covering:
        final counts = distribution(code.leaders, n);
        final radius = counts.lastIndexWhere((count) => count != 0);
        return ['covering $name radius $radius leaders ${[
          for (var i = 0; i <= radius; i++) '$i:${counts[i]}',
        ].join(' ')}'];
      case Verb.burst:
        return burst(name, code);
      case Verb.trellis:
        final profile = <int>[];
        for (var cut = 0; cut <= n; cut++) {
          final right = n - cut;
          profile.add(basis(code.g.map((row) => row >> right), cut).length +
              basis(code.g.map((row) => row & ((1 << right) - 1)), right).length - k);
        }
        return ['trellis $name profile ${profile.join(' ')} max ${profile.reduce((a, b) => a > b ? a : b)}'];
      case Verb.stdarray:
        if (n - k > 6 || k > 4) fail('too large');
        final leaders = code.leaders;
        final syndromes = List.generate(leaders.length, (i) => i)..sort((a, b) {
          final byWeight = weight(leaders[a]).compareTo(weight(leaders[b]));
          return byWeight != 0 ? byWeight : leaders[a].compareTo(leaders[b]);
        });
        return ['stdarray $name rows ${leaders.length} columns ${code.words.length}',
          for (final s in syndromes)
            '${bits(s, n - k)}: ${code.words.map((word) => bits(word ^ leaders[s], n)).join(' ')}'];
      case Verb.equal:
        final other = _codes[args[1]]!;
        if (n != other.n) return ['equal $name ${args[1]} no lengths $n ${other.n}'];
        final common = k + other.k - basis([...code.g, ...other.g], n).length;
        return ['equal $name ${args[1]} ${yes(k == common && other.k == common)} intersection $common'];
      case Verb.encode:
        if (args[1].length != k) fail('bad length');
        return ['encode $name message ${args[1]} codeword ${bits(code.encode(int.parse(args[1], radix: 2)), n)}'];
      case Verb.syndrome || Verb.decode || Verb.bounded || Verb.coset:
        final text = args[verb == Verb.bounded ? 2 : 1];
        if (text.length != n) fail('bad length');
        final word = int.parse(text, radix: 2), s = code.syndrome(word);
        if (verb == Verb.syndrome) {
          return ['syndrome $name ${bits(s, n - k)} codeword ${yes(s == 0)}'];
        }
        final decoded = code.decode(word);
        if (verb == Verb.coset) {
          final counts = distribution(code.words.map((c) => c ^ word), n);
          return ['coset $name syndrome ${bits(s, n - k)} leader ${bits(decoded.error, n)} weights ${weightList(counts)}'];
        }
        if (verb == Verb.bounded && weight(decoded.error) > int.parse(args[1])) {
          return ['bounded $name fail weight ${weight(decoded.error)}'];
        }
        return ['${verb == Verb.bounded ? 'bounded' : 'decode'} $name ${code.decodedText(decoded)}'];
      case Verb.erasure:
        final text = args[1];
        if (text.length != n) fail('bad length');
        var mask = 0, known = 0, erased = 0;
        for (final character in text.codeUnits) {
          mask = (mask << 1) | (character != 63 ? 1 : 0);
          known = (known << 1) | (character == 49 ? 1 : 0);
          if (character == 63) erased++;
        }
        final candidates = code.words.where((word) => (word & mask) == known).toList();
        var output = 'erasure $name erased $erased candidates ${candidates.length}';
        if (candidates.length == 1) {
          output += ' codeword ${bits(candidates.single, n)} message ${bits(code.message(candidates.single), k)}';
        }
        return [output];
      case Verb.interleave:
        return interleave(name, code, args);
      default:
        throw StateError('Unhandled command');
    }
  }
}

List<String> independent(Verb verb, List<String> args) {
  if (verb == Verb.crc || verb == Verb.crccheck) {
    final generator = args[0], text = args[1], d = generator.length - 1;
    if (generator.startsWith('0') || generator.length < 2 || generator.length > 17) {
      fail('bad parameter');
    }
    if (verb == Verb.crc && text.length + d > 30) fail('bad length');
    final word = int.parse(text, radix: 2), divisor = int.parse(generator, radix: 2);
    final remainder = divide(verb == Verb.crc ? word << d : word, divisor).remainder;
    final suffix = bits(remainder, d);
    if (verb == Verb.crc) return ['crc remainder $suffix frame $text$suffix'];
    return ['crccheck ${remainder == 0 ? 'ok' : 'error'} remainder $suffix'];
  }
  final n = int.parse(args[0]);
  if (verb == Verb.bounds) {
    final d = int.parse(args[1]);
    if (d < 1 || d > n || n > 24) fail('bad parameter');
    final v = volume(n, (d - 1) ~/ 2);
    var hamming = 0, griesmer = 0, sum = 0;
    for (var k = 0; k <= n; k++) {
      if ((1 << k) * v <= (1 << n)) hamming = k;
    }
    for (var k = 1; k <= n; k++) {
      final denominator = 1 << (k - 1);
      sum += (d + denominator - 1) ~/ denominator;
      if (sum <= n) griesmer = k;
    }
    return ['bounds n $n d $d singleton ${n - d + 1} hamming $hamming griesmer $griesmer'];
  }
  if (n < 1 || n > 24) fail('bad parameter');
  if (verb == Verb.factor) {
    var remaining = (1 << n) | 1, candidate = 2, divisors = 1;
    final factors = <String>[];
    while (2 * (candidate.bitLength - 1) <= remaining.bitLength - 1) {
      var exponent = 0;
      while (divide(remaining, candidate).remainder == 0) {
        remaining = divide(remaining, candidate).quotient;
        exponent++;
      }
      if (exponent > 0) {
        factors.add('${candidate.toRadixString(2)}^$exponent');
        divisors *= exponent + 1;
      }
      candidate++;
    }
    if (remaining > 1) {
      factors.add('${remaining.toRadixString(2)}^1');
      divisors *= 2;
    }
    return ['factor $n ${factors.join(' ')} divisors $divisors'];
  }
  final counts = args.skip(1).map(int.parse).toList();
  if (counts.length != n + 1) fail('bad length');
  if (counts[0] != 1) fail('bad parameter');
  final size = counts.fold(0, (a, b) => a + b);
  var feasible = (size & (size - 1)) == 0;
  final transformed = <String>[];
  for (var j = 0; j <= n; j++) {
    var numerator = 0;
    for (var x = 0; x <= n; x++) {
      var krawtchouk = 0;
      for (var y = 0; y <= j; y++) {
        krawtchouk += (y.isEven ? 1 : -1) * binomial(x, y) * binomial(n - x, j - y);
      }
      numerator += counts[x] * krawtchouk;
    }
    final divisor = numerator.gcd(size), p = numerator ~/ divisor, q = size ~/ divisor;
    transformed.add(q == 1 ? '$p' : '$p/$q');
    if (q != 1 || p < 0) feasible = false;
  }
  return ['macwilliams n $n size $size', 'dual ${transformed.join(' ')}', 'feasible ${yes(feasible)}'];
}

void main() {
  final count = int.parse(stdin.readLineSync()!), laboratory = Laboratory();
  for (var i = 0; i < count; i++) {
    try {
      final command = laboratory.parse(stdin.readLineSync()!);
      for (final line in laboratory.execute(command)) {
        stdout.writeln(line);
      }
    } on CommandError catch (error) {
      stdout.writeln('error: ${error.message}');
    }
  }
}
