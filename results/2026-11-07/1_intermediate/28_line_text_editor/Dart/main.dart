import 'dart:io';
import 'dart:math';

class CommandError implements Exception {
  final String reason;
  CommandError(this.reason);
}

enum ElementKind { number, offset, current, last, mark, forward, backward, separator, all }
enum Kind {
  empty, append, insert, change, print, numbered, listed, number, count, yank,
  marks, history, files, delete, put, join, joinSpaced, window, indent, unindent,
  undo, redo, changeCase, read, write, writeAppend, edit, writePrint, mark, move,
  copy, sort, substitute, global, inverseGlobal,
}

class Element {
  final ElementKind kind;
  final int value;
  final String symbol, text;
  const Element(this.kind, {this.value = 0, this.symbol = '', this.text = ''});
}

class Address {
  final List<Element> left;
  final List<Element>? right;
  final String separator;
  const Address(this.left, [this.right, this.separator = '']);
  int get count => right != null ? 2 : left.isEmpty ? 0 : 1;
}

class Command {
  final Kind kind;
  int count = 0;
  String suffix = '', caseMode = '', name = '', pattern = '', options = '';
  List<String?>? replacement;
  bool all = false;
  List<Element> destination = [];
  Command? subcommand;
  Command(this.kind);
}

class Cursor {
  final String text;
  int position;
  Cursor(this.text, [this.position = 0]);
  bool get ended => position == text.length;
  String get rest => text.substring(position);
}

bool digit(String c) => c.isNotEmpty && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
bool digits(String text) => text.isNotEmpty && text.split('').every(digit);
bool printSuffix(String c) => c == 'p' || c == 'n' || c == 'l';
bool sortForm(String text) => text == 'sort' || text.startsWith('sort ');

({String text, List<String?> replacement, String raw}) delimited(Cursor cursor, String delimiter) {
  final start = cursor.position;
  final value = StringBuffer();
  final replacement = <String?>[];
  while (!cursor.ended) {
    var c = cursor.text[cursor.position++];
    if (c == delimiter) {
      return (
        text: value.toString(), replacement: replacement,
        raw: cursor.text.substring(start, cursor.position - 1),
      );
    }
    final escaped = c == '\\';
    if (escaped) {
      if (cursor.ended) break;
      c = cursor.text[cursor.position++];
    }
    value.write(c);
    replacement.add(c == '&' && !escaped ? null : c);
  }
  throw CommandError('missing delimiter');
}

List<Element> scanAddress(Cursor cursor) {
  final elements = <Element>[];
  while (!cursor.ended) {
    final c = cursor.text[cursor.position];
    if (digit(c)) {
      final start = cursor.position++;
      while (!cursor.ended && digit(cursor.text[cursor.position])) cursor.position++;
      elements.add(Element(ElementKind.number, value: int.parse(cursor.text.substring(start, cursor.position))));
    } else if (c == '+' || c == '-') {
      final start = ++cursor.position;
      while (!cursor.ended && digit(cursor.text[cursor.position])) cursor.position++;
      final value = cursor.position == start ? 1 : int.parse(cursor.text.substring(start, cursor.position));
      elements.add(Element(ElementKind.offset, value: c == '+' ? value : -value));
    } else if (c == "'") {
      cursor.position++;
      elements.add(Element(ElementKind.mark, symbol: cursor.ended ? '' : cursor.text[cursor.position++]));
    } else if (c == '/' || c == '?') {
      cursor.position++;
      final pattern = delimited(cursor, c).text;
      elements.add(Element(c == '/' ? ElementKind.forward : ElementKind.backward, text: pattern));
    } else {
      final kind = switch (c) {
        '.' => ElementKind.current, r'$' => ElementKind.last,
        ',' || ';' => ElementKind.separator, '%' => ElementKind.all, _ => null,
      };
      if (kind == null) break;
      elements.add(Element(kind, symbol: c));
      cursor.position++;
    }
  }
  return elements;
}

bool expression(List<Element> elements) {
  for (var i = 0; i < elements.length; i++) {
    final kind = elements[i].kind;
    if (kind == ElementKind.offset) continue;
    if (i != 0 || kind == ElementKind.separator || kind == ElementKind.all) return false;
  }
  return true;
}

Address addressForm(List<Element> elements) {
  if (elements.length == 1 && elements.first.kind == ElementKind.all) {
    return const Address([Element(ElementKind.number, value: 1)], [Element(ElementKind.last)], ',');
  }
  final separators = [
    for (var i = 0; i < elements.length; i++)
      if (elements[i].kind == ElementKind.separator) i,
  ];
  if (separators.length > 1) throw CommandError('bad address');
  if (separators.isEmpty) {
    if (!expression(elements)) throw CommandError('bad address');
    return Address(elements);
  }
  final split = separators.single;
  final left = elements.sublist(0, split), right = elements.sublist(split + 1);
  if (!expression(left) || !expression(right)) throw CommandError('bad address');
  return Address(left, right, elements[split].symbol);
}

int optionalCount(String argument) {
  if (argument.isEmpty) return 0;
  if (!digits(argument) || int.parse(argument) == 0) throw CommandError('invalid suffix');
  return int.parse(argument);
}

String suffix(String argument) {
  if (argument.isNotEmpty && !printSuffix(argument)) throw CommandError('invalid suffix');
  return argument;
}

String fileName(String argument) {
  if (!RegExp(r'^ [a-z0-9]{1,8}$').hasMatch(argument)) throw CommandError('invalid file name');
  return argument.substring(1);
}

Command substitution(String argument) {
  final command = Command(Kind.substitute)..count = 1;
  var flags = argument;
  if (!argument.split('').every((c) => c == 'g' || printSuffix(c) || digit(c))) {
    final delimiter = argument[0];
    if (delimiter == ' ' || delimiter == '\\') throw CommandError('missing delimiter');
    final cursor = Cursor(argument, 1);
    command.pattern = delimited(cursor, delimiter).text;
    final replacement = delimited(cursor, delimiter);
    if (replacement.raw != '%') command.replacement = replacement.replacement;
    flags = cursor.rest;
  }
  var hasCount = false;
  var position = 0;
  while (position < flags.length) {
    final c = flags[position++];
    if (c == 'g' && !command.all) {
      command.all = true;
    } else if (printSuffix(c) && command.suffix.isEmpty) {
      command.suffix = c;
    } else if (digit(c) && !hasCount) {
      final start = position - 1;
      while (position < flags.length && digit(flags[position])) position++;
      command.count = int.parse(flags.substring(start, position));
      if (command.count == 0) throw CommandError('invalid suffix');
      hasCount = true;
    } else {
      throw CommandError('invalid suffix');
    }
  }
  return command;
}

Command parseCommand(String text) {
  if (sortForm(text)) {
    final options = text.length == 4 ? '' : text.substring(5);
    if ((text.length > 4 && options.isEmpty) ||
        options.split('').any((c) => !'ruin'.contains(c)) ||
        options.split('').toSet().length != options.length ||
        (options.contains('i') && options.contains('n'))) {
      throw CommandError('invalid suffix');
    }
    return Command(Kind.sort)..options = options;
  }
  final first = text.isEmpty ? '' : text[0];
  final argument = text.isEmpty ? '' : text.substring(1);
  const plain = {
    '': Kind.empty, 'a': Kind.append, 'i': Kind.insert, 'c': Kind.change,
    'p': Kind.print, 'n': Kind.numbered, 'l': Kind.listed, '=': Kind.number,
    '#': Kind.count, 'y': Kind.yank, 'K': Kind.marks, 'h': Kind.history, 'f': Kind.files,
  };
  final simple = plain[first];
  if (simple != null) {
    if (argument.isNotEmpty) throw CommandError('invalid suffix');
    return Command(simple);
  }
  switch (first) {
    case 'd': case 'x': case 'j': case 'J':
      final kind = switch (first) {
        'd' => Kind.delete, 'x' => Kind.put, 'j' => Kind.join, _ => Kind.joinSpaced,
      };
      return Command(kind)..suffix = suffix(argument);
    case 'z': case '>': case '<': case 'u':
      final kind = switch (first) {
        'z' => Kind.window, '>' => Kind.indent, '<' => Kind.unindent, _ => Kind.undo,
      };
      return Command(kind)..count = optionalCount(argument);
    case '~':
      if (argument != '' && argument != 'u' && argument != 'l') throw CommandError('invalid suffix');
      return Command(Kind.changeCase)..caseMode = argument;
    case 'r':
      if (argument.isEmpty || digits(argument)) return Command(Kind.redo)..count = optionalCount(argument);
      return Command(Kind.read)..name = fileName(argument);
    case 'w':
      if (argument.isEmpty) return Command(Kind.writePrint);
      return Command(Kind.write)..name = fileName(argument);
    case 'W': case 'e':
      return Command(first == 'W' ? Kind.writeAppend : Kind.edit)..name = fileName(argument);
    case 'k':
      if (!RegExp(r'^[a-z]$').hasMatch(argument)) throw CommandError('invalid mark');
      return Command(Kind.mark)..name = argument;
    case 'm': case 't':
      final cursor = Cursor(argument);
      final destination = scanAddress(cursor);
      if (destination.isEmpty || !expression(destination)) throw CommandError('invalid destination');
      return Command(first == 'm' ? Kind.move : Kind.copy)
        ..destination = destination
        ..suffix = suffix(cursor.rest);
    case 's': return substitution(argument);
    case 'g': case 'v':
      if (argument.isEmpty || argument[0] == ' ' || argument[0] == '\\') throw CommandError('missing delimiter');
      final cursor = Cursor(argument, 1);
      final pattern = delimited(cursor, argument[0]).text;
      final subcommand = cursor.ended ? 'p' : cursor.rest;
      if (!'pnldmtjJs><~aicx'.contains(subcommand[0]) || sortForm(subcommand)) {
        throw CommandError('invalid global command');
      }
      return Command(first == 'g' ? Kind.global : Kind.inverseGlobal)
        ..pattern = pattern
        ..subcommand = parseCommand(subcommand);
    default: throw CommandError('unknown command');
  }
}

bool hasText(String line) {
  try {
    final cursor = Cursor(line);
    scanAddress(cursor);
    final command = cursor.rest;
    if (command == 'a' || command == 'i' || command == 'c') return true;
    if (command.length < 2 || (command[0] != 'g' && command[0] != 'v') ||
        command[1] == ' ' || command[1] == '\\') return false;
    final global = Cursor(command, 2);
    delimited(global, command[1]);
    return global.rest == 'a' || global.rest == 'i' || global.rest == 'c';
  } on CommandError {
    return false;
  }
}

class Line {
  final int id;
  final String text;
  const Line(this.id, this.text);
}

class HistoryRecord {
  final String command;
  final List<Line> lines;
  final int current;
  HistoryRecord(this.command, this.lines, this.current);
}

class EditorState {
  List<Line> lines = [];
  int current = 0, displayCount = 5, nextId = 1;
  List<int?> marks = List.filled(26, null);
  List<String> cut = [];
  String? pattern;
  List<String?>? replacement;
  List<HistoryRecord> undo = [], redo = [];
  Map<String, List<String>> files = {};
  EditorState();

  EditorState.copy(EditorState other) {
    lines = [...other.lines];
    current = other.current;
    displayCount = other.displayCount;
    nextId = other.nextId;
    marks = [...other.marks];
    cut = other.cut;
    pattern = other.pattern;
    replacement = other.replacement;
    undo = [...other.undo];
    redo = [...other.redo];
    files = {...other.files};
  }
}

bool noAddress(Kind kind) => {Kind.undo, Kind.redo, Kind.history, Kind.marks, Kind.files, Kind.edit}.contains(kind);
bool oneAddress(Kind kind) => {Kind.append, Kind.insert, Kind.put, Kind.number, Kind.read, Kind.mark, Kind.window}.contains(kind);
bool modifies(Command command) => switch (command.kind) {
  Kind.append || Kind.insert || Kind.change || Kind.delete || Kind.put || Kind.join ||
  Kind.joinSpaced || Kind.move || Kind.copy || Kind.substitute || Kind.indent ||
  Kind.unindent || Kind.changeCase || Kind.sort || Kind.read || Kind.edit => true,
  Kind.global || Kind.inverseGlobal => modifies(command.subcommand!),
  _ => false,
};

class Editor {
  final EditorState state;
  final List<String> output = [];
  Editor(this.state);

  String pattern(String search) {
    if (search.isNotEmpty) state.pattern = search;
    return state.pattern ?? (throw CommandError('no previous pattern'));
  }

  int evaluate(List<Element> elements) {
    var value = state.current;
    for (final element in elements) {
      switch (element.kind) {
        case ElementKind.offset: value += element.value;
        case ElementKind.number: value = element.value;
        case ElementKind.current: value = state.current;
        case ElementKind.last: value = state.lines.length;
        case ElementKind.mark:
          if (!RegExp(r'^[a-z]$').hasMatch(element.symbol)) throw CommandError('invalid mark');
          final id = state.marks[element.symbol.codeUnitAt(0) - 97];
          value = id == null ? 0 : state.lines.indexWhere((line) => line.id == id) + 1;
          if (value == 0) throw CommandError('mark not set');
        case ElementKind.forward: case ElementKind.backward:
          final search = pattern(element.text);
          final size = state.lines.length;
          final forward = element.kind == ElementKind.forward;
          var index = forward ? state.current : state.current - 2;
          value = 0;
          for (var checked = 0; checked < size; checked++) {
            if (index >= size) index = 0;
            if (index < 0) index = size - 1;
            if (state.lines[index].text.contains(search)) {
              value = index + 1;
              break;
            }
            index += forward ? 1 : -1;
          }
          if (value == 0) throw CommandError('no match');
        case ElementKind.separator: case ElementKind.all:
          throw StateError('invalid address form');
      }
    }
    return value;
  }

  List<int> evaluateAddress(Address address) {
    if (address.count == 0) return [];
    if (address.count == 1) return [evaluate(address.left)];
    final left = address.left.isEmpty ? (address.separator == ',' ? 1 : state.current) : evaluate(address.left);
    if (address.separator == ';') {
      if (left < 0 || left > state.lines.length) throw CommandError('address out of range');
      state.current = left;
    }
    final right = address.right!.isEmpty ? state.lines.length : evaluate(address.right!);
    return [left, right];
  }

  (int, int) range(Command command, List<int> addresses) {
    final kind = command.kind;
    final size = state.lines.length;
    if (noAddress(kind)) return (0, 0);
    if (oneAddress(kind)) {
      final a = addresses.isNotEmpty ? addresses.first : switch (kind) {
        Kind.number || Kind.read => size, Kind.window => state.current + 1, _ => state.current,
      };
      final minimum = kind == Kind.mark || kind == Kind.window ? 1 : 0;
      if (a < minimum || a > size) throw CommandError('address out of range');
      return (a, a);
    }
    int a, b;
    if (addresses.isNotEmpty) {
      a = addresses.first;
      b = addresses.last;
    } else if ({Kind.writePrint, Kind.write, Kind.writeAppend, Kind.count}.contains(kind)) {
      return (1, size);
    } else if ({Kind.global, Kind.inverseGlobal, Kind.sort}.contains(kind)) {
      a = 1;
      b = size;
    } else {
      a = state.current;
      b = a + (kind == Kind.join || kind == Kind.joinSpaced ? 1 : 0);
    }
    if (a < 1 || b < 1 || a > size || b > size) throw CommandError('address out of range');
    if (a > b || a == b && (kind == Kind.join || kind == Kind.joinSpaced)) throw CommandError('invalid range');
    return (a, b);
  }

  void process(String line, List<String> text, EditorState before) {
    final cursor = Cursor(line);
    final address = addressForm(scanAddress(cursor));
    final command = parseCommand(cursor.rest);
    if (noAddress(command.kind) && address.count != 0) throw CommandError('unexpected address');
    if (oneAddress(command.kind) && address.count == 2) throw CommandError('too many addresses');
    final (a, b) = range(command, evaluateAddress(address));
    execute(command, a, b, text);
    if (state.lines.length > 200) throw CommandError('buffer full');
    if (modifies(command)) {
      state.undo.add(HistoryRecord(line, [...before.lines], before.current));
      state.redo.clear();
    }
  }

  void printLine(int number, [String form = 'p']) {
    var text = state.lines[number - 1].text;
    if (form == 'n') {
      output.add('${number.toString().padLeft(3)} $text');
    } else if (form == 'l') {
      text = text.replaceAll('\\', '\\\\') + r'$';
      while (text.length > 40) {
        output.add('${text.substring(0, 39)}\\');
        text = text.substring(39);
      }
      output.add(text);
    } else {
      output.add(text);
    }
  }

  List<String> contents(int a, int b) => state.lines.sublist(a - 1, b).map((line) => line.text).toList();
  int bytes(Iterable<String> lines) => lines.fold(0, (sum, line) => sum + line.length + 1);

  void insert(int position, Iterable<String> text) {
    final lines = text.map((value) => Line(state.nextId++, value)).toList();
    state.lines.insertAll(position, lines);
    state.current = position + lines.length;
  }

  void history(bool undo, int count) {
    final source = undo ? state.undo : state.redo, target = undo ? state.redo : state.undo;
    if (source.length < count) throw CommandError(undo ? 'nothing to undo' : 'nothing to redo');
    for (var i = 0; i < count; i++) {
      final record = source.removeLast();
      target.add(HistoryRecord(record.command, [...state.lines], state.current));
      state.lines = [...record.lines];
      state.current = record.current;
    }
  }

  int leadingInteger(String text) {
    final match = RegExp(r'^-?[0-9]+').firstMatch(text);
    return match == null ? 0 : int.parse(match[0]!);
  }

  void sort(Command command, int a, int b) {
    final lines = state.lines.sublist(a - 1, b);
    final numeric = command.options.contains('n'), reverse = command.options.contains('r');
    String key(Line line) => command.options.contains('i') ? line.text.toLowerCase() : line.text;
    int compare(Line left, Line right) => numeric
        ? leadingInteger(left.text).compareTo(leadingInteger(right.text)) : key(left).compareTo(key(right));
    final ordered = [for (var i = 0; i < lines.length; i++) (i, lines[i])];
    ordered.sort((left, right) {
      var comparison = compare(left.$2, right.$2);
      if (reverse) comparison = -comparison;
      return comparison == 0 ? left.$1.compareTo(right.$1) : comparison;
    });
    final result = <Line>[];
    for (final (_, line) in ordered) {
      if (command.options.contains('u') && result.isNotEmpty && compare(result.last, line) == 0) continue;
      result.add(line);
    }
    state.lines.replaceRange(a - 1, b, result);
    state.current = a + result.length - 1;
  }

  int substitute(Command command, int a, int b, bool global) {
    final search = pattern(command.pattern);
    final replacement = command.replacement ?? state.replacement ?? (throw CommandError('no previous substitution'));
    state.replacement = replacement;
    final expanded = StringBuffer();
    for (final part in replacement) expanded.write(part ?? search);
    final value = expanded.toString();
    var substituted = 0;
    for (var number = a; number <= b; number++) {
      final line = state.lines[number - 1];
      final result = StringBuffer();
      var position = 0, occurrences = 0;
      while (true) {
        final match = line.text.indexOf(search, position);
        if (match < 0) break;
        result.write(line.text.substring(position, match));
        occurrences++;
        result.write(occurrences == command.count || command.all && occurrences >= command.count ? value : search);
        position = match + search.length;
      }
      if (occurrences < command.count) continue;
      result.write(line.text.substring(position));
      final changed = result.toString();
      if (changed.length > 80) throw CommandError('line too long');
      if (changed.isEmpty || changed.endsWith(' ')) throw CommandError('bad line');
      state.lines[number - 1] = Line(line.id, changed);
      state.current = number;
      substituted++;
    }
    if (substituted == 0 && !global) throw CommandError('no match');
    if (substituted != 0 && command.suffix.isNotEmpty) printLine(state.current, command.suffix);
    return substituted;
  }

  int execute(Command command, int a, int b, List<String> text, [bool global = false]) {
    final kind = command.kind;
    switch (kind) {
      case Kind.empty:
        printLine(b);
        state.current = b;
      case Kind.print: case Kind.numbered: case Kind.listed:
        final form = kind == Kind.print ? 'p' : kind == Kind.numbered ? 'n' : 'l';
        for (var i = a; i <= b; i++) printLine(i, form);
        state.current = b;
      case Kind.window:
        if (command.count != 0) state.displayCount = command.count;
        final end = min(state.lines.length, a + state.displayCount - 1);
        for (var i = a; i <= end; i++) printLine(i);
        state.current = end;
      case Kind.number: output.add('$a');
      case Kind.count:
        final counted = contents(a, b);
        final words = counted.fold<int>(0, (sum, line) => sum + line.split(' ').where((word) => word.isNotEmpty).length);
        final chars = counted.fold<int>(0, (sum, line) => sum + line.length);
        output.add('count lines=${counted.length} words=$words chars=$chars');
      case Kind.writePrint:
        for (var i = a; i <= b; i++) printLine(i);
        output.add('lines=${b - a + 1} bytes=${bytes(contents(a, b))}');
      case Kind.append: insert(a, text);
      case Kind.insert: insert(max(a, 1) - 1, text);
      case Kind.change: case Kind.delete:
        state.cut = contents(a, b);
        state.lines.removeRange(a - 1, b);
        if (kind == Kind.change && text.isNotEmpty) {
          insert(a - 1, text);
        } else {
          state.current = min(a, state.lines.length);
        }
      case Kind.yank: state.cut = contents(a, b);
      case Kind.put:
        if (state.cut.isEmpty) throw CommandError('nothing to put');
        insert(a, state.cut);
      case Kind.move: case Kind.copy:
        final destination = evaluate(command.destination);
        if (destination < 0 || destination > state.lines.length) throw CommandError('address out of range');
        if (kind == Kind.copy) {
          insert(destination, contents(a, b));
        } else {
          if (a <= destination && destination < b) throw CommandError('invalid destination');
          final moved = state.lines.sublist(a - 1, b);
          state.lines.removeRange(a - 1, b);
          final position = destination < a ? destination : destination - moved.length;
          state.lines.insertAll(position, moved);
          state.current = position + moved.length;
        }
      case Kind.join: case Kind.joinSpaced:
        final pieces = contents(a, b);
        if (kind == Kind.joinSpaced) {
          for (var i = 1; i < pieces.length; i++) pieces[i] = pieces[i].trimLeft();
        }
        final joined = pieces.join(kind == Kind.join ? '' : ' ');
        if (joined.length > 80) throw CommandError('line too long');
        state.lines[a - 1] = Line(state.lines[a - 1].id, joined);
        state.lines.removeRange(a, b);
        state.current = a;
      case Kind.indent: case Kind.unindent: case Kind.changeCase:
        final width = command.count == 0 ? 4 : command.count;
        for (var i = a - 1; i < b; i++) {
          final line = state.lines[i];
          var changed = line.text;
          if (kind == Kind.indent) {
            if (changed.length + width > 80) throw CommandError('line too long');
            changed = ' ' * width + changed;
          } else if (kind == Kind.unindent) {
            var removed = 0;
            while (removed < width && removed < changed.length && changed[removed] == ' ') removed++;
            changed = changed.substring(removed);
          } else if (command.caseMode == 'u') {
            changed = changed.toUpperCase();
          } else if (command.caseMode == 'l') {
            changed = changed.toLowerCase();
          } else {
            changed = String.fromCharCodes(changed.codeUnits.map((c) => c >= 65 && c <= 90 ? c + 32 :
                c >= 97 && c <= 122 ? c - 32 : c));
          }
          state.lines[i] = Line(line.id, changed);
        }
        state.current = b;
      case Kind.sort: sort(command, a, b);
      case Kind.substitute: return substitute(command, a, b, global);
      case Kind.mark: state.marks[command.name.codeUnitAt(0) - 97] = state.lines[a - 1].id;
      case Kind.marks:
        final marks = <String>[];
        for (var i = 0; i < 26; i++) {
          final id = state.marks[i];
          final number = id == null ? 0 : state.lines.indexWhere((line) => line.id == id) + 1;
          if (number != 0) marks.add('${String.fromCharCode(97 + i)}=$number');
        }
        output.add('marks ${marks.isEmpty ? 'none' : marks.join(' ')}');
      case Kind.undo: case Kind.redo: history(kind == Kind.undo, command.count == 0 ? 1 : command.count);
      case Kind.history:
        output.add('history undo=${state.undo.length} redo=${state.redo.length}');
        for (var i = 0; i < state.undo.length; i++) output.add('undo ${i + 1}: ${state.undo[state.undo.length - 1 - i].command}');
        for (var i = 0; i < state.redo.length; i++) output.add('redo ${i + 1}: ${state.redo[state.redo.length - 1 - i].command}');
      case Kind.global: case Kind.inverseGlobal:
        final search = pattern(command.pattern);
        final selected = state.lines.sublist(a - 1, b)
            .where((line) => line.text.contains(search) == (kind == Kind.global)).map((line) => line.id).toList();
        if (selected.isEmpty) throw CommandError('no match');
        final subcommand = command.subcommand!;
        var substituted = 0;
        for (final id in selected) {
          final index = state.lines.indexWhere((line) => line.id == id);
          if (index < 0) continue;
          state.current = index + 1;
          final (first, last) = range(subcommand, []);
          substituted += execute(subcommand, first, last, text, true);
        }
        if (subcommand.kind == Kind.substitute && substituted == 0) throw CommandError('no match');
      case Kind.write: case Kind.writeAppend: case Kind.read: case Kind.edit:
        if (kind == Kind.write || kind == Kind.writeAppend) {
          final written = contents(a, b);
          state.files[command.name] = kind == Kind.writeAppend ? [...?state.files[command.name], ...written] : written;
        } else {
          final read = state.files[command.name];
          if (read == null) throw CommandError('no such file');
          if (kind == Kind.edit) state.lines.clear();
          insert(kind == Kind.edit ? 0 : a, read);
        }
        final file = state.files[command.name]!;
        output.add('file ${command.name} lines=${file.length} bytes=${bytes(file)}');
      case Kind.files:
        final names = state.files.keys.toList()..sort();
        output.add('files ${names.isEmpty ? 'none' : names.map((name) => '$name=${state.files[name]!.length}').join(' ')}');
    }
    if (command.suffix.isNotEmpty && state.current >= 1) printLine(state.current, command.suffix);
    return 0;
  }
}

void main() {
  var state = EditorState();
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line == 'Q') break;
    final text = <String>[];
    if (hasText(line)) {
      while (true) {
        final value = stdin.readLineSync();
        if (value == null || value == '.') break;
        text.add(value);
      }
    }
    try {
      final next = EditorState.copy(state);
      final editor = Editor(next)..process(line, text, state);
      state = next;
      if (editor.output.isNotEmpty) stdout.writeln(editor.output.join('\n'));
    } on CommandError catch (error) {
      stdout.writeln('? ${error.reason}');
    }
  }
}
