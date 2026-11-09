import 'lexer.dart';

RegExpMatch? fullMatch(String pattern, String text) {
  final match = RegExp('^(?:$pattern)\$').firstMatch(text);
  return match != null && match.end == text.length ? match : null;
}

bool isName(String text) => fullMatch(r'[a-z][a-z0-9_]*', text) != null;
bool isSectionName(String text) =>
    fullMatch(r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*', text) != null;

String trimLeftSpaces(String text) {
  var index = 0;
  while (index < text.length && text[index] == ' ') { index++; }
  return text.substring(index);
}

String trimRightSpaces(String text) {
  var end = text.length;
  while (end > 0 && text[end - 1] == ' ') { end--; }
  return text.substring(0, end);
}

String trimSpaces(String text) => trimRightSpaces(trimLeftSpaces(text));

List<String> trimmed(List<String> segments) {
  final result = List<String>.of(segments);
  result[0] = trimLeftSpaces(result[0]);
  result[result.length - 1] = trimRightSpaces(result.last);
  return result;
}

class Statement {
  final String kind;
  final int line;
  final String target;
  final String value;
  Statement(this.kind, this.line, this.target, [this.value = '']);
}

class Document {
  final statements = <Statement>[];
  final diagnostics = <Diagnostic>[];
}

class IniParser {
  final String name;
  final document = Document();
  final assigned = <String, int>{};
  String? section;
  String? base;
  IniParser(this.name);

  void report(int line, String code, String message) =>
      document.diagnostics.add(Diagnostic(Origin(name, line), code, message));

  void add(String kind, int line, String target, [String value = '']) =>
      document.statements.add(Statement(kind, line, target, value));

  void interpret(LogicalLine line) {
    final error = line.error;
    if (error != null) {
      report(line.number, error.$1, error.$2);
      return;
    }
    final segments = trimmed(line.segments);
    final first = segments.first;
    if (segments.length == 1 && first.isEmpty) return;
    if (first.startsWith('[')) {
      header(line.number, segments);
    } else if (first.startsWith('@')) {
      directive(line.number, segments);
    } else {
      assignment(line.number, segments);
    }
  }

  void badHeader(int line, String message) {
    report(line, 'E_SECTION', message);
    section = null;
  }

  void header(int line, List<String> segments) {
    final text = segments.first;
    if (segments.length != 1 || !text.endsWith(']')) {
      badHeader(line, 'invalid section header');
      return;
    }
    final inside = text.substring(1, text.length - 1);
    final colon = inside.indexOf(':');
    final name = trimSpaces(colon < 0 ? inside : inside.substring(0, colon));
    final parent = colon < 0 ? null : trimSpaces(inside.substring(colon + 1));
    final relative = name.startsWith('.') && isSectionName(name.substring(1));
    if ((parent != null && !isSectionName(parent)) ||
        (!relative && !isSectionName(name))) {
      badHeader(line, 'invalid section header');
    } else if (relative && base == null) {
      badHeader(line, 'relative section without base');
    } else {
      if (relative) {
        section = base! + name;
      } else {
        section = base = name;
      }
      if (parent != null) add('inherit', line, section!, parent);
    }
  }

  void directive(int line, List<String> segments) {
    final words = segments.first.split(RegExp(r' +'));
    if (segments.length != 1 || words.length != 2 ||
        !['@include', '@unset'].contains(words[0]) || !isName(words[1])) {
      report(line, 'E_SYNTAX', 'invalid directive');
    } else if (words[0] == '@include') {
      add('include', line, words[1]);
    } else if (section == null) {
      report(line, 'E_NO_SECTION', 'no current section');
    } else {
      add('unset', line, '$section.${words[1]}');
    }
  }

  void assignment(int line, List<String> segments) {
    var hasEquals = false;
    for (var index = 0; index < segments.length; index += 2) {
      if (segments[index].contains('=')) hasEquals = true;
    }
    if (!hasEquals) {
      report(line, 'E_SYNTAX', 'invalid line');
      return;
    }
    final equals = segments.first.indexOf('=');
    if (equals < 0) {
      report(line, 'E_SYNTAX', 'invalid key');
      return;
    }
    var key = trimSpaces(segments.first.substring(0, equals));
    final append = key.endsWith('+');
    if (append) key = trimRightSpaces(key.substring(0, key.length - 1));
    if (!isName(key)) {
      report(line, 'E_SYNTAX', 'invalid key');
      return;
    }
    final parts = trimmed([segments.first.substring(equals + 1), ...segments.skip(1)]);
    final String? value = parts.length == 1 ? parts.first :
        parts.length == 3 && parts.first.isEmpty && parts.last.isEmpty ? parts[1] : null;
    if (value == null) {
      report(line, 'E_SYNTAX', 'invalid value');
    } else if (section == null) {
      report(line, 'E_NO_SECTION', 'no current section');
    } else {
      final fullKey = '$section.$key';
      if (!append) {
        final previous = assigned[fullKey];
        if (previous != null) report(line, 'W_DUPLICATE', '$fullKey already set at line $previous');
        assigned[fullKey] = line;
      }
      add(append ? 'append' : 'assign', line, fullKey, value);
    }
  }
}

Document parseDocument(String name, List<String> lines) {
  final parser = IniParser(name);
  for (final line in logicalLines(lines)) {
    parser.interpret(line);
  }
  return parser.document;
}
