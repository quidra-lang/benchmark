import 'dart:convert';
import 'dart:io';

typedef Value = Object?;
typedef Step = Object;
bool isIdentifier(String text) =>
    RegExp(r'^[A-Za-z_]').hasMatch(text) &&
    !RegExp(r'[^A-Za-z0-9_]').hasMatch(text);
final integerNotation = RegExp(r'^(?:0|-?[1-9][0-9]{0,8})$');
const escapeCodes = {
  'b': '\b',
  'f': '\f',
  'n': '\n',
  'r': '\r',
  't': '\t',
  '/': '/',
  r'\': r'\',
};
final missing = Object();

class JsonFailure implements Exception {
  final int position;
  final String message;
  JsonFailure(this.position, this.message);
}

class QueryFailure implements Exception {
  final String message;
  QueryFailure(this.message);
}

class JsonMatch {
  final Value value;
  final List<Step> path;
  final List<int> order;
  JsonMatch(this.value, this.path, this.order);
}

class Selector {
  final String kind;
  final String? key;
  final int? index;
  final int? start;
  final int? end;
  final bool descendant;
  Selector(
    this.kind, {
    this.key,
    this.index,
    this.start,
    this.end,
    this.descendant = false,
  });
}

String quote(String text, [String delimiter = '"']) {
  final result = StringBuffer(delimiter);
  const escapes = {
    '\b': r'\b',
    '\f': r'\f',
    '\n': r'\n',
    '\r': r'\r',
    '\t': r'\t',
  };
  for (final char in text.split('')) {
    if (char == delimiter || char == r'\') {
      result.write(r'\');
      result.write(char);
    } else if (escapes.containsKey(char)) {
      result.write(escapes[char]);
    } else if (char.codeUnitAt(0) < 32 || char.codeUnitAt(0) == 127) {
      result.write(
        '\\u${char.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
      );
    } else {
      result.write(char);
    }
  }
  result.write(delimiter);
  return result.toString();
}

String compact(Value value) {
  if (value is Map<String, Value>)
    return '{${value.entries.map((entry) => '${quote(entry.key)}:${compact(entry.value)}').join(',')}}';
  if (value is List<Value>) return '[${value.map(compact).join(',')}]';
  return value is String ? quote(value) : value.toString();
}

String pretty(Value value, [String indentation = '']) {
  final next = '$indentation  ';
  if (value is Map<String, Value> && value.isNotEmpty)
    return '{\n${value.entries.map((entry) => '$next${quote(entry.key)}: ${pretty(entry.value, next)}').join(',\n')}\n$indentation}';
  if (value is List<Value> && value.isNotEmpty)
    return '[\n${value.map((child) => '$next${pretty(child, next)}').join(',\n')}\n$indentation]';
  return compact(value);
}

Value clone(Value value) {
  if (value is Map<String, Value>)
    return value.map((key, child) => MapEntry(key, clone(child)));
  return value is List<Value> ? value.map(clone).toList() : value;
}

String typeName(Value value) => value == null
    ? 'null'
    : value is Map<String, Value>
    ? 'object'
    : value is List<Value>
    ? 'array'
    : value is String
    ? 'string'
    : value is int
    ? 'number'
    : 'boolean';

class JsonReader {
  final String text;
  int position = 0;
  JsonReader(this.text);
  String current() => position < text.length ? text[position] : '';
  Never fail(String reason, [int? at]) =>
      throw JsonFailure(at ?? position, reason);
  void whitespace() {
    while (current() == ' ' || current() == '\n') position++;
  }

  String string([String delimiter = '"']) {
    position++;
    final result = StringBuffer();
    while (true) {
      final char = current();
      if (char.isEmpty || char == '\n') fail('unterminated string');
      if (char == delimiter) {
        position++;
        return result.toString();
      }
      if (char != r'\') {
        result.write(char);
        position++;
        continue;
      }
      final start = position;
      final escaped = start + 1 < text.length ? text[start + 1] : '';
      if (escaped.isEmpty || escaped == '\n')
        fail('unterminated string', start + 1);
      if (escaped == 'u') {
        if (start + 6 > text.length) fail('bad unicode escape', start);
        final digits = text.substring(start + 2, start + 6);
        if (!RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(digits))
          fail('bad unicode escape', start);
        final code = int.parse(digits, radix: 16);
        if (code > 127) fail('non-ascii escape', start);
        result.writeCharCode(code);
        position += 6;
      } else if (escaped == delimiter || escapeCodes.containsKey(escaped)) {
        result.write(escaped == delimiter ? delimiter : escapeCodes[escaped]);
        position += 2;
      } else {
        fail("invalid escape '\\$escaped'", start);
      }
    }
  }

  int number() {
    final start = position;
    final negative = current() == '-';
    if (negative) position++;
    final digitsStart = position;
    while (RegExp(r'^[0-9]$').hasMatch(current())) position++;
    final digits = text.substring(digitsStart, position);
    if (digits.isEmpty) fail('invalid number', start);
    if (digits.length > 1 && digits[0] == '0')
      fail('leading zero', digitsStart);
    if (current() == '.') fail('fraction not allowed');
    if (current() == 'e' || current() == 'E') fail('exponent not allowed');
    if (digits.length >= 10) fail('number out of range', start);
    return (negative ? -1 : 1) * int.parse(digits);
  }

  Value value() {
    whitespace();
    final char = current();
    if (char.isEmpty) fail('unexpected end of input');
    if (char == '"') return string();
    if (char == '-' || RegExp(r'^[0-9]$').hasMatch(char)) return number();
    if (RegExp(r'^[A-Za-z]$').hasMatch(char)) {
      final start = position;
      while (RegExp(r'^[A-Za-z]$').hasMatch(current())) position++;
      final word = text.substring(start, position);
      if (word == 'null') return null;
      if (word == 'true' || word == 'false') return word == 'true';
      fail("invalid literal '$word'", start);
    }
    if (char == '{') {
      position++;
      whitespace();
      final object = <String, Value>{};
      if (current() == '}') {
        position++;
        return object;
      }
      while (true) {
        whitespace();
        if (current().isEmpty) fail('unexpected end of input');
        if (current() != '"') fail('expected key');
        final start = position;
        final key = string();
        if (object.containsKey(key)) fail('duplicate key ${quote(key)}', start);
        whitespace();
        if (current().isEmpty) fail('unexpected end of input');
        if (current() != ':') fail("expected ':'");
        position++;
        object[key] = value();
        whitespace();
        if (current() == '}') {
          position++;
          return object;
        }
        if (current().isEmpty) fail('unexpected end of input');
        if (current() != ',') fail("expected ',' or '}'");
        position++;
        whitespace();
        if (current() == '}') fail('trailing comma');
      }
    }
    if (char == '[') {
      position++;
      whitespace();
      final array = <Value>[];
      if (current() == ']') {
        position++;
        return array;
      }
      while (true) {
        array.add(value());
        whitespace();
        if (current() == ']') {
          position++;
          return array;
        }
        if (current().isEmpty) fail('unexpected end of input');
        if (current() != ',') fail("expected ',' or ']'");
        position++;
        whitespace();
        if (current() == ']') fail('trailing comma');
      }
    }
    fail("unexpected character '$char'");
  }

  Value parse() {
    final result = value();
    whitespace();
    if (current().isNotEmpty) fail('trailing characters');
    return result;
  }
}

List<Selector> parsePath(String text, {bool field = false}) {
  try {
    if (text.isEmpty || text[0] != (field ? '@' : r'$')) throw QueryFailure('');
    final result = <Selector>[];
    var position = 1;
    while (position < text.length) {
      var descendant = false;
      var bracket = false;
      if (!field && text.startsWith('..', position)) {
        descendant = true;
        position += 2;
        bracket = position < text.length && text[position] == '[';
      } else if (text[position] == '.') {
        position++;
      } else if (text[position] == '[') {
        bracket = true;
      } else {
        throw QueryFailure('');
      }
      final Selector selector;
      if (bracket) {
        position++;
        if (position < text.length && text[position] == "'") {
          final reader = JsonReader(text)..position = position;
          final key = reader.string("'");
          position = reader.position;
          if (position == text.length || text[position++] != ']')
            throw QueryFailure('');
          selector = Selector('key', key: key, descendant: descendant);
        } else {
          final end = text.indexOf(']', position);
          if (end < 0) throw QueryFailure('');
          final selection = text.substring(position, end);
          position = end + 1;
          if (integerNotation.hasMatch(selection)) {
            selector = Selector(
              'index',
              index: int.parse(selection),
              descendant: descendant,
            );
          } else if (!field && selection == '*') {
            selector = Selector('all', descendant: descendant);
          } else if (!field && selection.contains(':')) {
            final parts = selection.split(':');
            if (parts.length != 2 ||
                parts.any(
                  (part) => part.isNotEmpty && !integerNotation.hasMatch(part),
                ))
              throw QueryFailure('');
            selector = Selector(
              'slice',
              start: parts[0].isEmpty ? null : int.parse(parts[0]),
              end: parts[1].isEmpty ? null : int.parse(parts[1]),
              descendant: descendant,
            );
          } else {
            throw QueryFailure('');
          }
        }
      } else if (!field && position < text.length && text[position] == '*') {
        position++;
        selector = Selector('all', descendant: descendant);
      } else {
        final name = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*')
            .firstMatch(text.substring(position));
        if (name == null) throw QueryFailure('');
        position += name[0]!.length;
        selector = Selector('key', key: name[0]!, descendant: descendant);
      }
      result.add(selector);
    }
    return result;
  } catch (_) {
    throw QueryFailure(field ? 'bad field' : 'bad path');
  }
}

List<JsonMatch> children(JsonMatch match) {
  final value = match.value;
  if (value is Map<String, Value>) {
    var index = 0;
    return value.entries
        .map(
          (entry) => JsonMatch(
            entry.value,
            [...match.path, entry.key],
            [...match.order, index++],
          ),
        )
        .toList();
  }
  if (value is List<Value>)
    return List.generate(
      value.length,
      (index) => JsonMatch(
        value[index],
        [...match.path, index],
        [...match.order, index],
      ),
    );
  return [];
}

List<JsonMatch> preorder(JsonMatch match) {
  final result = <JsonMatch>[];
  final pending = [match];
  while (pending.isNotEmpty) {
    final next = pending.removeLast();
    result.add(next);
    pending.addAll(children(next).reversed);
  }
  return result;
}

List<JsonMatch> select(JsonMatch match, Selector selector) {
  final all = children(match);
  if (selector.kind == 'all') return all;
  if (selector.kind == 'key')
    return match.value is Map<String, Value>
        ? all.where((child) => child.path.last == selector.key).toList()
        : [];
  if (match.value is! List<Value>) return [];
  final length = (match.value as List<Value>).length;
  if (selector.kind == 'index') {
    final index = selector.index! < 0
        ? length + selector.index!
        : selector.index!;
    return index >= 0 && index < length ? [all[index]] : [];
  }
  int bound(int value) {
    final adjusted = value < 0 ? length + value : value;
    return adjusted < 0
        ? 0
        : adjusted > length
        ? length
        : adjusted;
  }

  final start = bound(selector.start ?? 0);
  final end = bound(selector.end ?? length);
  return start >= end ? [] : all.sublist(start, end);
}

List<JsonMatch> applySegment(List<JsonMatch> matches, Selector selector) =>
    matches
        .expand(
          (match) => (selector.descendant ? preorder(match) : [match]).expand(
            (value) => select(value, selector),
          ),
        )
        .toList();
List<JsonMatch> evaluate(Value document, List<Selector> selectors) => selectors
    .fold<List<JsonMatch>>([JsonMatch(document, [], [])], applySegment);
String location(List<Step> steps) =>
    r'$' +
    steps.map((step) {
      if (step is int) return '[$step]';
      final key = step as String;
      return isIdentifier(key) ? '.$key' : '[${quote(key, "'")}]';
    }).join();
Value fieldValue(Value value, List<Selector> selectors) {
  var matches = [JsonMatch(value, [], [])];
  for (final selector in selectors) matches = applySegment(matches, selector);
  return matches.isEmpty ? missing : matches[0].value;
}

bool equal(Value left, Value right) {
  if (typeName(left) != typeName(right)) return false;
  if (left is Map<String, Value> && right is Map<String, Value>)
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              equal(entry.value, right[entry.key]),
        );
  if (left is List<Value> && right is List<Value>)
    return left.length == right.length &&
        List.generate(
          left.length,
          (i) => equal(left[i], right[i]),
        ).every((same) => same);
  return left == right;
}

int compareKeys(Value left, Value right) {
  int rank(Value value) => value == null
      ? 0
      : value is int
      ? 1
      : value is String
      ? 2
      : 3;
  final difference = rank(left) - rank(right);
  if (difference != 0) return difference;
  if (left is int && right is int) return left.compareTo(right);
  if (left is String && right is String) return left.compareTo(right);
  return 0;
}

List<JsonMatch> targets(List<JsonMatch> matches) {
  final unique = <String, JsonMatch>{};
  for (final match in matches) unique[jsonEncode(match.path)] = match;
  return unique.values.toList()..sort((a, b) {
    final length = a.order.length < b.order.length
        ? a.order.length
        : b.order.length;
    for (var i = 0; i < length; i++) {
      if (a.order[i] != b.order[i]) return b.order[i].compareTo(a.order[i]);
    }
    return b.order.length.compareTo(a.order.length);
  });
}

Value getAt(Value document, List<Step> steps) {
  Value value = document;
  for (final step in steps)
    value = step is String
        ? (value as Map<String, Value>)[step]
        : (value as List<Value>)[step as int];
  return value;
}

Value putAt(Value document, List<Step> steps, Value value) {
  if (steps.isEmpty) return value;
  final parent = getAt(document, steps.sublist(0, steps.length - 1));
  final last = steps.last;
  if (last is String) {
    (parent as Map<String, Value>)[last] = value;
  } else {
    (parent as List<Value>)[last as int] = value;
  }
  return document;
}

void merge(Map<String, Value> target, Map<String, Value> source) {
  for (final entry in source.entries) {
    final previous = target[entry.key];
    if (previous is Map<String, Value> && entry.value is Map<String, Value>) {
      merge(previous, entry.value as Map<String, Value>);
    } else {
      target[entry.key] = clone(entry.value);
    }
  }
}

List<String> splitLimited(String text, int maximum) {
  final result = <String>[];
  var start = 0;
  while (result.length < maximum) {
    final space = text.indexOf(' ', start);
    if (space < 0) break;
    result.add(text.substring(start, space));
    start = space + 1;
  }
  result.add(text.substring(start));
  return result;
}

class QueryTool {
  Value document;
  final List<Value> history = [];
  final List<String> output = [];
  void load(List<String> lines) {
    final text = lines.join('\n');
    try {
      final value = JsonReader(text).parse();
      history.add(clone(document));
      document = clone(value);
      final all = preorder(JsonMatch(value, [], []));
      final depth = all
          .map((match) => match.path.length + 1)
          .reduce((a, b) => a > b ? a : b);
      output.add('LOADED nodes=${all.length} depth=$depth');
    } on JsonFailure catch (error) {
      final before = text.substring(0, error.position);
      output.add(
        'PARSE ERROR line ${before.split('\n').length} col ${error.position - before.lastIndexOf('\n')}: ${error.message}',
      );
    }
  }

  void execute(String line) {
    final space = line.indexOf(' ');
    final command = space < 0 ? line : line.substring(0, space);
    final argument = space < 0 ? null : line.substring(space + 1);
    const commands = {
      'LOAD',
      'GET',
      'COMPACT',
      'PRETTY',
      'TYPE',
      'LENGTH',
      'KEYS',
      'FLATTEN',
      'COUNT',
      'SUM',
      'MIN',
      'MAX',
      'AVG',
      'FILTER',
      'SET',
      'DELETE',
      'INSERT',
      'MERGE',
      'SORT',
      'RENAME',
      'UNDO',
    };
    if (!commands.contains(command))
      throw QueryFailure("unknown command '$command'");
    var args = argument == null ? <String>[] : argument.split(' ');
    if (command == 'SET' || command == 'MERGE')
      args = argument == null ? [] : splitLimited(argument, 1);
    if (command == 'INSERT')
      args = argument == null ? [] : splitLimited(argument, 2);
    if (command == 'FILTER')
      args = argument == null ? [] : splitLimited(argument, 3);
    final optional = ['COMPACT', 'PRETTY', 'FLATTEN'].contains(command);
    final shape = optional
        ? args.length <= 1
        : command == 'UNDO' || command == 'LOAD'
        ? args.isEmpty
        : command == 'SET' || command == 'MERGE' || command == 'RENAME'
        ? args.length == 2
        : command == 'INSERT'
        ? args.length == 3
        : command == 'FILTER'
        ? args.length >= 3 &&
              (args[2] == 'EXISTS' ? args.length == 3 : args.length == 4)
        : command == 'SORT'
        ? args.isNotEmpty &&
              args.length <= 3 &&
              (args.length < 3 || args[1] != 'DESC' && args[2] == 'DESC')
        : args.length == 1;
    if (!shape) throw QueryFailure('bad arguments');
    if (command == 'UNDO') {
      if (history.isEmpty) throw QueryFailure('nothing to undo');
      document = clone(history.removeLast());
      output.add('UNDO ${history.length}');
      return;
    }
    final selectors = parsePath(args.isEmpty ? r'$' : args[0]);
    List<Selector> field = [];
    var key = '';
    Value value;
    if (command == 'FILTER') {
      field = parsePath(args[1], field: true);
      if (!['==', '!=', '<', '<=', '>', '>=', 'EXISTS'].contains(args[2]))
        throw QueryFailure('bad operator');
      if (args[2] != 'EXISTS') value = JsonReader(args[3]).parse();
    } else if (command == 'SORT') {
      field = parsePath(
        args.length > 1 && args[1] != 'DESC' ? args[1] : '@',
        field: true,
      );
    } else if (command == 'RENAME') {
      try {
        if (isIdentifier(args[1])) {
          key = args[1];
        } else {
          final reader = JsonReader(args[1]);
          if (reader.current() != "'") throw QueryFailure('');
          key = reader.string("'");
          if (reader.position != args[1].length) throw QueryFailure('');
        }
      } catch (_) {
        throw QueryFailure('bad key');
      }
    } else if (command == 'SET' || command == 'MERGE') {
      value = JsonReader(args[1]).parse();
    } else if (command == 'INSERT') {
      if (!integerNotation.hasMatch(args[1])) throw QueryFailure('bad index');
      value = JsonReader(args[2]).parse();
    }
    if (command == 'MERGE' && value is! Map<String, Value>)
      throw QueryFailure('merge value is not an object');
    if (command == 'DELETE' && selectors.isEmpty)
      throw QueryFailure('cannot delete root');
    var matches = evaluate(document, selectors);
    for (final match in matches) {
      if (['FILTER', 'INSERT', 'SORT'].contains(command) &&
          match.value is! List<Value>)
        throw QueryFailure('not an array at ${location(match.path)}');
      if (['MERGE', 'KEYS'].contains(command) &&
          match.value is! Map<String, Value>)
        throw QueryFailure('not an object at ${location(match.path)}');
      if (command == 'LENGTH' &&
          match.value is! Map<String, Value> &&
          match.value is! List<Value> &&
          match.value is! String)
        throw QueryFailure('no length at ${location(match.path)}');
      if (command == 'RENAME' &&
          (match.path.isEmpty || match.path.last is! String))
        throw QueryFailure('not a member at ${location(match.path)}');
    }
    if (command == 'INSERT') {
      final index = int.parse(args[1]);
      for (final match in matches) {
        final n = (match.value as List<Value>).length;
        if (index < -n - 1 || index > n)
          throw QueryFailure('index out of range at ${location(match.path)}');
      }
    }
    if (command == 'FILTER') {
      final lines = <String>[];
      for (final match in matches) {
        for (final child in children(match)) {
          final left = fieldValue(child.value, field);
          final operator = args[2];
          var accepted = operator == 'EXISTS'
              ? !identical(left, missing)
              : operator == '=='
              ? !identical(left, missing) && equal(left, value)
              : operator == '!='
              ? identical(left, missing) || !equal(left, value)
              : false;
          if (!['EXISTS', '==', '!='].contains(operator) &&
              (left is int && value is int ||
                  left is String && value is String)) {
            final comparison = compareKeys(left, value);
            accepted = operator == '<'
                ? comparison < 0
                : operator == '<='
                ? comparison <= 0
                : operator == '>'
                ? comparison > 0
                : comparison >= 0;
          }
          if (accepted)
            lines.add('${location(child.path)} = ${compact(child.value)}');
        }
      }
      output.addAll(lines.isEmpty ? ['no match'] : lines);
      return;
    }
    if ([
      'SET',
      'DELETE',
      'INSERT',
      'MERGE',
      'SORT',
      'RENAME',
    ].contains(command)) {
      if (command == 'SET' && selectors.isNotEmpty) {
        final last = selectors.last;
        if (last.kind == 'key' && !last.descendant) {
          matches = [];
          for (final parent in evaluate(
            document,
            selectors.sublist(0, selectors.length - 1),
          )) {
            if (parent.value is! Map<String, Value>) continue;
            final object = parent.value as Map<String, Value>;
            final keys = object.keys.toList();
            final index = keys.indexOf(last.key!);
            matches.add(
              JsonMatch(
                object[last.key],
                [...parent.path, last.key!],
                [...parent.order, index < 0 ? keys.length : index],
              ),
            );
          }
        }
      }
      final selected = targets(matches);
      Value candidate = clone(document);
      for (final target in selected) {
        if (command == 'SET') {
          candidate = putAt(candidate, target.path, clone(value));
        } else if (command == 'DELETE') {
          final parent = getAt(
            candidate,
            target.path.sublist(0, target.path.length - 1),
          );
          final last = target.path.last;
          if (last is String) {
            (parent as Map<String, Value>).remove(last);
          } else {
            (parent as List<Value>).removeAt(last as int);
          }
        } else if (command == 'INSERT') {
          final array = getAt(candidate, target.path) as List<Value>;
          final index = int.parse(args[1]);
          array.insert(
            index < 0 ? array.length + 1 + index : index,
            clone(value),
          );
        } else if (command == 'MERGE') {
          merge(
            getAt(candidate, target.path) as Map<String, Value>,
            value as Map<String, Value>,
          );
        } else if (command == 'SORT') {
          final array = getAt(candidate, target.path) as List<Value>;
          final direction = args.last == 'DESC' ? -1 : 1;
          final decorated = List.generate(
            array.length,
            (i) =>
                (value: array[i], index: i, key: fieldValue(array[i], field)),
          );
          decorated.sort((a, b) {
            final comparison = direction * compareKeys(a.key, b.key);
            return comparison == 0 ? a.index.compareTo(b.index) : comparison;
          });
          candidate = putAt(
            candidate,
            target.path,
            decorated.map((item) => item.value).toList(),
          );
        } else {
          final parentPath = target.path.sublist(0, target.path.length - 1);
          final old = target.path.last as String;
          final object = getAt(candidate, parentPath) as Map<String, Value>;
          if (old != key && object.containsKey(key))
            throw QueryFailure('key exists at ${location(target.path)}');
          candidate = putAt(
            candidate,
            parentPath,
            Map<String, Value>.fromEntries(
              object.entries.map(
                (entry) =>
                    MapEntry(entry.key == old ? key : entry.key, entry.value),
              ),
            ),
          );
        }
      }
      history.add(clone(document));
      document = candidate;
      output.add('$command ${selected.length}');
      return;
    }
    if (command == 'COUNT') {
      output.add('COUNT ${matches.length}');
      return;
    }
    if (['SUM', 'MIN', 'MAX', 'AVG'].contains(command)) {
      final numbers = matches
          .map((match) => match.value)
          .whereType<int>()
          .toList();
      final sum = numbers.fold<int>(0, (total, number) => total + number);
      var answer = 'null';
      if (command == 'SUM') {
        answer = '$sum';
      } else if (numbers.isNotEmpty) {
        if (command == 'AVG') {
          final rounded =
              (sum.abs() * 200 + numbers.length) ~/ (2 * numbers.length);
          answer =
              '${sum < 0 && rounded > 0 ? '-' : ''}${rounded ~/ 100}.${(rounded % 100).toString().padLeft(2, '0')}';
        } else {
          answer = numbers
              .reduce(
                (best, number) => command == 'MIN'
                    ? best < number
                          ? best
                          : number
                    : best > number
                    ? best
                    : number,
              )
              .toString();
        }
      }
      output.add('$command $answer');
      return;
    }
    if (matches.isEmpty) {
      output.add('no match');
      return;
    }
    for (final match in matches) {
      final value = match.value;
      if (command == 'GET') {
        output.add('${location(match.path)} = ${compact(value)}');
      } else if (command == 'COMPACT') {
        output.add(compact(value));
      } else if (command == 'PRETTY') {
        output.add(pretty(value));
      } else if (command == 'TYPE') {
        output.add('${location(match.path)} ${typeName(value)}');
      } else if (command == 'LENGTH') {
        final length = value is Map<String, Value>
            ? value.length
            : value is List<Value>
            ? value.length
            : (value as String).length;
        output.add('${location(match.path)} $length');
      } else if (command == 'KEYS') {
        output.add(
          '${location(match.path)} ${compact((value as Map<String, Value>).keys.toList())}',
        );
      } else if (command == 'FLATTEN') {
        for (final leaf in preorder(match)) {
          if (children(leaf).isEmpty)
            output.add('${location(leaf.path)} = ${compact(leaf.value)}');
        }
      }
    }
  }

  void run(List<String> lines) {
    var position = 0;
    List<String> block() {
      final body = <String>[];
      while (lines[position] != '%%') body.add(lines[position++]);
      position++;
      return body;
    }

    load(block());
    while (lines[position] != 'END') {
      final line = lines[position++];
      if (line == 'LOAD') {
        load(block());
        continue;
      }
      try {
        execute(line);
      } on JsonFailure catch (error) {
        output.add('PARSE ERROR col ${error.position + 1}: ${error.message}');
      } on QueryFailure catch (error) {
        output.add('ERROR ${error.message}');
      }
    }
  }
}

Future<void> main() async {
  final tool = QueryTool();
  tool.run((await stdin.transform(utf8.decoder).join()).split('\n'));
  stdout.write('${tool.output.join('\n')}\n');
}
