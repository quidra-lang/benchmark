import 'dart:io';
import 'dart:math';
part 'charset.dart';
part 'formatter.dart';
part 'backtrack_vm.dart';
part 'pike_vm.dart';

class Node {
  final String kind;
  final String value, mode, name;
  final int char, column, lower, upper;
  final Set<int> set;
  final bool negated, positive;
  int number;
  final Node? child;
  final List<Node> children;
  Node(
    this.kind, {
    this.value = '',
    this.mode = '',
    this.name = '',
    this.char = 0,
    this.column = 0,
    this.lower = 0,
    this.upper = -1,
    this.set = const {},
    this.negated = false,
    this.positive = false,
    this.number = 0,
    this.child,
    this.children = const [],
  });
}

class PatternError implements Exception {
  final String message;
  final int column;
  PatternError(this.message, this.column);
}

bool quantifier(int c) => {42, 43, 63, 123}.contains(c);

class PatternParser {
  final String text;
  int index = 0, groups = 0;
  final Map<String, int> names = {};
  final List<Node> references = [];
  PatternParser(this.text);
  int peek([int offset = 0]) =>
      index + offset >= text.length ? 0 : text.codeUnitAt(index + offset);
  Never fail(String message, int column) => throw PatternError(message, column);
  String digits() {
    final start = index;
    while (digit(peek())) index++;
    return text.substring(start, index);
  }

  String name() {
    final start = index;
    if (letter(peek()) || peek() == 95) {
      index++;
      while (letter(peek()) || digit(peek()) || peek() == 95) index++;
    }
    if (start == index || peek() != 62) fail('invalid group name', index + 1);
    final result = text.substring(start, index);
    index++;
    return result;
  }

  Node parse() {
    final root = alternation();
    if (index != text.length) fail('unmatched )', index + 1);
    for (final reference in references) {
      if (reference.name.isNotEmpty) {
        final group = names[reference.name];
        if (group == null) fail('unknown group name', reference.column);
        reference.number = group;
      } else if (reference.number > groups) {
        fail('invalid group reference', reference.column);
      }
    }
    return root;
  }

  Node alternation() {
    final children = [concatenation()];
    while (peek() == 124) {
      index++;
      children.add(concatenation());
    }
    return children.length == 1
        ? children.first
        : Node('alternation', children: children);
  }

  Node concatenation() {
    final children = <Node>[];
    while (peek() != 0 && peek() != 124 && peek() != 41)
      children.add(quantified());
    return children.length == 1
        ? children.first
        : Node('concat', children: children);
  }

  Node quantified() {
    if (quantifier(peek())) fail('nothing to repeat', index + 1);
    final child = element();
    if (!quantifier(peek())) return child;
    if (child.kind == 'assert' || child.kind == 'look')
      fail('nothing to repeat', index + 1);
    var lower = 0, upper = -1;
    switch (peek()) {
      case 42:
        index++;
      case 43:
        lower = 1;
        index++;
      case 63:
        upper = 1;
        index++;
      case 123:
        final column = index + 1;
        index++;
        final first = digits();
        if (first.isEmpty) fail('invalid quantifier', column);
        lower = int.parse(first);
        if (peek() == 125) {
          upper = lower;
        } else if (peek() == 44) {
          index++;
          if (peek() != 125) {
            final last = digits();
            if (last.isEmpty) fail('invalid quantifier', column);
            upper = int.parse(last);
          }
        } else {
          fail('invalid quantifier', column);
        }
        if (peek() != 125) fail('invalid quantifier', column);
        index++;
        if (lower > 100 || upper > 100) fail('quantifier too large', column);
        if (upper >= 0 && lower > upper)
          fail('quantifier range out of order', column);
    }
    var mode = 'greedy';
    if (peek() == 63) {
      mode = 'lazy';
      index++;
    } else if (peek() == 43) {
      mode = 'possessive';
      index++;
    }
    if (quantifier(peek())) fail('nested quantifier', index + 1);
    return Node('repeat', child: child, lower: lower, upper: upper, mode: mode);
  }

  Node element() {
    final c = peek();
    switch (c) {
      case 40:
        return group();
      case 91:
        return characterClass();
      case 92:
        return escape();
      case 46:
        index++;
        return Node('any');
      case 94:
        index++;
        return Node('assert', value: 'BOL');
      case 36:
        index++;
        return Node('assert', value: 'EOL');
      default:
        index++;
        return Node('literal', char: c);
    }
  }

  Node group() {
    final column = index + 1;
    index++;
    var kind = 99;
    var groupName = '';
    if (peek() == 63) {
      index++;
      kind = peek();
      if (!{58, 61, 33, 60}.contains(kind)) fail('invalid group', column);
      index++;
      if (kind == 60) {
        final nameColumn = index + 1;
        groupName = name();
        if (names.containsKey(groupName))
          fail('duplicate group name', nameColumn);
      }
    }
    var number = 0;
    if (kind == 99 || kind == 60) {
      number = ++groups;
      if (groupName.isNotEmpty) names[groupName] = number;
    }
    final content = alternation();
    if (peek() != 41) fail('missing )', column);
    index++;
    if (kind == 58) return content;
    if (kind == 61 || kind == 33)
      return Node('look', positive: kind == 61, child: content);
    return Node('group', number: number, child: content);
  }

  (Set<int>, int, bool) classItem() {
    var c = peek();
    index++;
    if (c == 92) {
      final column = index;
      c = peek();
      if (c == 0) fail('trailing backslash', column);
      index++;
      if ({100, 68, 119, 87, 115, 83}.contains(c))
        return (standard(c), 0, true);
      if (c == 110) {
        c = 10;
      } else if (c == 116) {
        c = 9;
      } else if (letter(c) || digit(c)) {
        fail('invalid escape', column);
      }
    }
    return ({c}, c, false);
  }

  Node characterClass() {
    final column = index + 1;
    index++;
    var negated = false;
    if (peek() == 94) {
      negated = true;
      index++;
    }
    if (peek() == 93) fail('empty class', index + 1);
    final set = <int>{};
    while (true) {
      if (peek() == 0) fail('missing ]', column);
      if (peek() == 93) {
        index++;
        break;
      }
      final (item, first, isSet) = classItem();
      if (peek() == 45 && peek(1) != 0 && peek(1) != 93) {
        final dash = index + 1;
        index++;
        if (isSet) fail('invalid range', dash);
        final (_, last, lastSet) = classItem();
        if (lastSet || first > last) fail('invalid range', dash);
        for (var c = first; c <= last; c++) set.add(c);
      } else {
        set.addAll(item);
      }
    }
    return Node('class', set: set, negated: negated);
  }

  Node escape() {
    final column = index + 1;
    index++;
    final c = peek();
    if (c == 0) fail('trailing backslash', column);
    index++;
    if ({100, 68, 119, 87, 115, 83}.contains(c))
      return Node('class', set: standard(c | 32), negated: c >= 65 && c <= 90);
    if (c == 98 || c == 66)
      return Node('assert', value: c == 98 ? 'WORD' : 'NOTWORD');
    if (c == 110 || c == 116) return Node('literal', char: c == 110 ? 10 : 9);
    Node reference;
    if (c >= 49 && c <= 57) {
      reference = Node(
        'backref',
        number: int.parse('${String.fromCharCode(c)}${digits()}'),
        column: column,
      );
    } else if (c == 107) {
      if (peek() != 60) fail('invalid escape', column);
      index++;
      reference = Node('backref', name: name(), column: column);
    } else {
      if (letter(c) || digit(c)) fail('invalid escape', column);
      return Node('literal', char: c);
    }
    references.add(reference);
    return reference;
  }
}

class Instruction {
  final String op, kind;
  final int char, number;
  final Set<int> set;
  final bool negated;
  int x, y;
  Instruction(
    this.op, {
    this.kind = '',
    this.char = 0,
    this.number = 0,
    this.set = const {},
    this.negated = false,
    this.x = 0,
    this.y = 0,
  });
}

class Compiler {
  final List<Instruction> program = [];
  int emit(Instruction instruction) {
    program.add(instruction);
    return program.length - 1;
  }

  void split(int pc, int continuation, int end, bool lazy) {
    program[pc].x = lazy ? end : continuation;
    program[pc].y = lazy ? continuation : end;
  }

  void compile(Node node, {String? repeatMode}) {
    switch (node.kind) {
      case 'literal':
        emit(Instruction('CHAR', char: node.char));
      case 'any':
        emit(Instruction('ANY'));
      case 'class':
        emit(Instruction('CLASS', set: node.set, negated: node.negated));
      case 'assert':
        emit(Instruction('ASSERT', kind: node.value));
      case 'backref':
        emit(Instruction('BACKREF', number: node.number));
      case 'group':
        emit(Instruction('SAVE', number: 2 * node.number));
        compile(node.child!);
        emit(Instruction('SAVE', number: 2 * node.number + 1));
      case 'look':
        {
          final pc = emit(
            Instruction('LOOK', kind: node.positive ? 'AHEAD' : 'NOT'),
          );
          compile(node.child!);
          emit(Instruction('MATCH'));
          program[pc].x = program.length;
        }
      case 'concat':
        for (final child in node.children) compile(child);
      case 'alternation':
        {
          final jumps = <int>[];
          for (final child in node.children.take(node.children.length - 1)) {
            final pc = emit(Instruction('SPLIT'));
            program[pc].x = pc + 1;
            compile(child);
            final jump = emit(Instruction('JMP'));
            program[pc].y = program.length;
            jumps.add(jump);
          }
          compile(node.children.last);
          for (final jump in jumps) program[jump].x = program.length;
        }
      case 'repeat':
        {
          final mode = repeatMode ?? node.mode;
          if (mode == 'possessive') {
            final pc = emit(Instruction('LOOK', kind: 'ATOMIC'));
            compile(node, repeatMode: 'greedy');
            emit(Instruction('MATCH'));
            program[pc].x = program.length;
            return;
          }
          final lazy = mode == 'lazy';
          if (node.upper < 0 && node.lower == 0) {
            final pc = emit(Instruction('SPLIT'));
            final continuation = program.length;
            compile(node.child!);
            emit(Instruction('JMP', x: pc));
            split(pc, continuation, program.length, lazy);
            return;
          }
          if (node.upper < 0) {
            for (var i = 0; i < node.lower - 1; i++) compile(node.child!);
            final first = program.length;
            compile(node.child!);
            final pc = emit(Instruction('SPLIT'));
            split(pc, first, program.length, lazy);
            return;
          }
          for (var i = 0; i < node.lower; i++) compile(node.child!);
          final optional = <(int, int)>[];
          for (var i = node.lower; i < node.upper; i++) {
            final pc = emit(Instruction('SPLIT'));
            final continuation = program.length;
            compile(node.child!);
            optional.add((pc, continuation));
          }
          for (final pair in optional)
            split(pair.$1, pair.$2, program.length, lazy);
        }
    }
  }
}

(int, int) lengthRange(Node node) {
  switch (node.kind) {
    case 'literal':
    case 'any':
    case 'class':
      return (1, 1);
    case 'assert':
    case 'look':
      return (0, 0);
    case 'backref':
      return (0, -1);
    case 'group':
      return lengthRange(node.child!);
    case 'repeat':
      final (a, b) = lengthRange(node.child!);
      return (
        a * node.lower,
        b == 0
            ? 0
            : b < 0 || node.upper < 0
            ? -1
            : b * node.upper,
      );
    case 'concat':
    case 'alternation':
      var lower = 0, upper = 0;
      for (var i = 0; i < node.children.length; i++) {
        final (a, b) = lengthRange(node.children[i]);
        if (node.kind == 'concat') {
          lower += a;
          upper = upper < 0 || b < 0 ? -1 : upper + b;
        } else {
          if (i == 0 || a < lower) lower = a;
          upper = upper < 0 || b < 0 ? -1 : max(upper, b);
        }
      }
      return (lower, upper);
  }
  throw StateError('unknown node');
}

(Set<int>, bool) firstCharacters(Node node, String flags) {
  switch (node.kind) {
    case 'literal':
      return (
        {
          node.char,
          if (flags.contains('i') && letter(node.char)) swapped(node.char),
        },
        false,
      );
    case 'any':
      return (
        {
          for (var i = 0; i < 128; i++)
            if (flags.contains('s') || i != 10) i,
        },
        false,
      );
    case 'class':
      return (
        {
          for (var i = 0; i < 128; i++)
            if (classMatches(node.set, node.negated, i, flags)) i,
        },
        false,
      );
    case 'assert':
    case 'look':
      return (<int>{}, true);
    case 'backref':
      return ({for (var i = 0; i < 128; i++) i}, true);
    case 'group':
      return firstCharacters(node.child!, flags);
    case 'repeat':
      if (node.upper == 0) return (<int>{}, true);
      final (set, nullable) = firstCharacters(node.child!, flags);
      return (set, nullable || node.lower == 0);
    case 'concat':
    case 'alternation':
      final set = <int>{};
      var nullable = node.kind == 'concat';
      for (final child in node.children) {
        final (chars, empty) = firstCharacters(child, flags);
        set.addAll(chars);
        if (node.kind == 'concat') {
          if (!empty) return (set, false);
        } else {
          nullable = nullable || empty;
        }
      }
      return (set, nullable);
  }
  throw StateError('unknown node');
}

class Pattern {
  final String name, flagsText, flags, text;
  Node? root;
  List<Instruction> program = [];
  int groups = 0;
  Map<String, int> names = {};
  bool pike = false;
  PatternError? error;
  Pattern(this.name, this.flagsText, this.text)
    : flags = flagsText == '-' ? '' : flagsText {
    final parser = PatternParser(text);
    try {
      final parsed = parser.parse();
      root = parsed;
      groups = parser.groups;
      names = parser.names;
      final compiler = Compiler();
      compiler.emit(Instruction('SAVE', number: 0));
      compiler.compile(parsed);
      compiler.emit(Instruction('SAVE', number: 1));
      compiler.emit(Instruction('MATCH'));
      program = compiler.program;
      pike = !program.any((i) => i.op == 'BACKREF' || i.op == 'LOOK');
    } on PatternError catch (failure) {
      error = failure;
    }
  }
}

List<String> readLines(String path) => File(path).readAsLinesSync();
String decodeQuoted(String text) {
  final out = StringBuffer();
  for (var i = 1; i < text.length - 1; i++) {
    var c = text.codeUnitAt(i);
    if (c == 92) {
      c = text.codeUnitAt(++i);
      if (c == 110) {
        c = 10;
      } else if (c == 116) {
        c = 9;
      }
    }
    out.writeCharCode(c);
  }
  return out.toString();
}

class Command {
  final int number;
  final String line;
  String kind = '', mode = '', pattern = '', subject = '', template = '';
  Command(this.line, this.number) {
    final a = line.split(' ');
    kind = a[0];
    if (kind == 'REPLACE') {
      mode = a[1];
      pattern = a[2];
      subject = a[3];
      var start = 0;
      for (var i = 0; i < 4; i++) start = line.indexOf(' ', start) + 1;
      template = decodeQuoted(line.substring(start));
    } else {
      pattern = a[1];
      if (kind != 'LIST') subject = a[2];
    }
  }
}

class TemplatePart {
  final String text;
  final int group;
  TemplatePart({this.text = '', this.group = -1});
}

List<TemplatePart>? parseTemplate(String text, Pattern pattern) {
  final parts = <TemplatePart>[];
  var i = 0;
  while (i < text.length) {
    if (text.codeUnitAt(i) != 36) {
      parts.add(TemplatePart(text: text[i++]));
      continue;
    }
    if (++i == text.length) return null;
    if (text.codeUnitAt(i) == 36) {
      parts.add(TemplatePart(text: r'$'));
      i++;
      continue;
    }
    var group = -1;
    if (digit(text.codeUnitAt(i))) {
      group = text.codeUnitAt(i++) - 48;
    } else if (text[i] == '{') {
      final end = text.indexOf('}', i + 1);
      if (end < 0) return null;
      final name = text.substring(i + 1, end);
      if (name.isNotEmpty && name.codeUnits.every(digit)) {
        group = int.parse(name);
      } else {
        group = pattern.names[name] ?? -1;
      }
      i = end + 1;
    } else {
      return null;
    }
    if (group < 0 || group > pattern.groups) return null;
    parts.add(TemplatePart(group: group));
  }
  return parts;
}

String expandTemplate(
  List<TemplatePart> parts,
  List<int> captures,
  String text,
) {
  final out = StringBuffer();
  for (final part in parts) {
    if (part.group < 0) {
      out.write(part.text);
    } else {
      final a = captures[2 * part.group], b = captures[2 * part.group + 1];
      if (a >= 0 && b >= 0) out.write(text.substring(a, b));
    }
  }
  return out.toString();
}

List<List<int>> scans(
  List<int>? Function(int) search,
  String text,
  bool single,
  bool Function() aborted,
) {
  final matches = <List<int>>[];
  for (var start = 0; start <= text.length;) {
    final captures = search(start);
    if (aborted() || captures == null) break;
    matches.add(captures);
    if (single) break;
    start = captures[1] + (captures[0] == captures[1] ? 1 : 0);
  }
  return matches;
}

bool sameMatches(List<List<int>> a, List<List<int>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    for (var j = 0; j < a[i].length; j++) {
      if (a[i][j] != b[i][j]) return false;
    }
  }
  return true;
}

class Evaluation {
  String status = '', engine = '', text = '';
  List<List<int>> matches = [];
  List<TemplatePart> parts = [];
  final List<(String, int)> steps = [];
}

Evaluation evaluate(
  Command command,
  Pattern pattern,
  Map<String, String> subjects,
) {
  final result = Evaluation();
  if (pattern.error != null) {
    result.status = 'invalid pattern';
    return result;
  }
  if (command.kind == 'LIST') {
    result.status = 'list';
    return result;
  }
  if (command.kind == 'REPLACE') {
    final parts = parseTemplate(command.template, pattern);
    if (parts == null) {
      result.status = 'invalid template';
      return result;
    }
    result.parts = parts;
  }
  result.text = subjects[command.subject]!;
  final single =
      command.kind == 'MATCH' ||
      command.kind == 'SEARCH' ||
      command.kind == 'REPLACE' && command.mode == 'FIRST';
  final backtrack = BacktrackVm(
    pattern.program,
    pattern.flags,
    pattern.groups,
    result.text,
    command.kind == 'MATCH',
  );
  final matches = scans(
    backtrack.search,
    result.text,
    single,
    () => backtrack.aborted,
  );
  result.steps.add(('backtrack', backtrack.steps));
  if (pattern.pike) {
    final pike = PikeVm(
      pattern.program,
      pattern.flags,
      pattern.groups,
      result.text,
      command.kind == 'MATCH',
    );
    final pikeMatches = scans(pike.search, result.text, single, () => false);
    result.steps.add(('pike', pike.steps));
    if (backtrack.aborted) {
      result.engine = 'pike (backtrack: TOO_MANY_STEPS)';
    } else if (!sameMatches(matches, pikeMatches)) {
      result.status = 'MISMATCH';
      return result;
    } else {
      result.engine = 'both';
    }
    result.matches = pikeMatches;
  } else {
    if (backtrack.aborted) {
      result.status = 'TOO_MANY_STEPS';
      return result;
    }
    result.engine = 'backtrack';
    result.matches = matches;
  }
  result.status = 'ok';
  return result;
}

List<String> matchLines(List<int> captures, Pattern pattern, String text) {
  final result = [
    'match ${captures[0]}-${captures[1]} ${quoted(text.substring(captures[0], captures[1]))}',
  ];
  for (var k = 1; k <= pattern.groups; k++) {
    final a = captures[2 * k], b = captures[2 * k + 1];
    result.add(
      a < 0 || b < 0
          ? 'group $k -'
          : 'group $k $a-$b ${quoted(text.substring(a, b))}',
    );
  }
  return result;
}

List<String> renderResult(
  Command command,
  Pattern pattern,
  Evaluation evaluation,
) {
  final result = ['#${command.number} ${command.line}'];
  if (evaluation.status == 'list') {
    result.add('instructions ${pattern.program.length}');
    return result;
  }
  if (evaluation.status != 'ok') {
    result.add(evaluation.status);
    return result;
  }
  result.add('engine ${evaluation.engine}');
  final text = evaluation.text;
  final matches = evaluation.matches;
  switch (command.kind) {
    case 'MATCH':
    case 'SEARCH':
      if (matches.isEmpty) {
        result.add('no match');
      } else {
        result.addAll(matchLines(matches.first, pattern, text));
      }
    case 'FINDALL':
      result.add('matches ${matches.length}');
      for (final match in matches)
        result.addAll(matchLines(match, pattern, text));
    case 'REPLACE':
      {
        final value = StringBuffer();
        var previous = 0;
        for (final match in matches) {
          value.write(text.substring(previous, match[0]));
          value.write(expandTemplate(evaluation.parts, match, text));
          previous = match[1];
        }
        value.write(text.substring(previous));
        result.add('replacements ${matches.length}');
        result.add('result ${quoted(value.toString())}');
      }
    case 'SPLIT':
      {
        final pieces = <String>[];
        var previous = 0;
        for (final match in matches) {
          pieces.add(text.substring(previous, match[0]));
          previous = match[1];
        }
        pieces.add(text.substring(previous));
        result.add('pieces ${pieces.length}');
        result.add('piece ${quoted(pieces.first)}');
        for (var i = 0; i < matches.length; i++) {
          final captures = matches[i];
          for (var k = 1; k <= pattern.groups; k++) {
            final a = captures[2 * k], b = captures[2 * k + 1];
            result.add(
              'group $k ${a < 0 || b < 0 ? '-' : quoted(text.substring(a, b))}',
            );
          }
          result.add('piece ${quoted(pieces[i + 1])}');
        }
      }
  }
  return result;
}

List<String> programListing(Pattern pattern) {
  final (lower, upper) = lengthRange(pattern.root!);
  final (first, _) = firstCharacters(pattern.root!, pattern.flags);
  final names = pattern.names.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final nameText = names.isEmpty
      ? '-'
      : names.map((e) => '${e.key}:${e.value}').join(',');
  return [
    '=== ${pattern.name}',
    'flags=${pattern.flagsText} groups=${pattern.groups} names=$nameText length=$lower..${upper < 0 ? 'inf' : '$upper'} first=${first.isEmpty ? '-' : setNotation(first)} pike=${pattern.pike ? 'yes' : 'no'} size=${pattern.program.length}',
    for (var pc = 0; pc < pattern.program.length; pc++)
      '$pc ${instructionNotation(pattern.program[pc])}',
  ];
}

void save(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final patterns = <String, Pattern>{};
  for (final line in readLines('input/patterns.txt')) {
    final first = line.indexOf(' '),
        second = line.indexOf(' ', line.indexOf(' ') + 1);
    final pattern = Pattern(
      line.substring(0, first),
      line.substring(first + 1, second),
      line.substring(second + 1),
    );
    patterns[pattern.name] = pattern;
  }
  final subjects = <String, String>{};
  for (final line in readLines('input/subjects.txt')) {
    final space = line.indexOf(' ');
    subjects[line.substring(0, space)] = decodeQuoted(
      line.substring(space + 1),
    );
  }
  final results = <String>[], programs = <String>[];
  final steps = ['command,engine,steps'];
  var number = 0;
  for (final line in readLines('input/commands.txt')) {
    final command = Command(line, ++number);
    final pattern = patterns[command.pattern]!;
    final evaluation = evaluate(command, pattern, subjects);
    results.addAll(renderResult(command, pattern, evaluation));
    if (command.kind == 'LIST' && pattern.error == null)
      programs.addAll(programListing(pattern));
    for (final step in evaluation.steps)
      steps.add('${command.number},${step.$1},${step.$2}');
  }
  final errors = <String>[];
  for (final pattern in patterns.values) {
    final failure = pattern.error;
    if (failure != null)
      errors.addAll([
        '${pattern.name}: ${failure.message} at column ${failure.column}',
        '  ${pattern.text}',
        '  ${''.padLeft(failure.column - 1)}^',
      ]);
  }
  if (programs.isEmpty) programs.add('no programs');
  if (errors.isEmpty) errors.add('no errors');
  Directory('output').createSync(recursive: true);
  save('results.txt', results);
  save('programs.txt', programs);
  save('steps.csv', steps);
  save('errors.txt', errors);
}
