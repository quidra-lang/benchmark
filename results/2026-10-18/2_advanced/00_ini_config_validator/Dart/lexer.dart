class Origin {
  final String document;
  final int line;
  const Origin(this.document, this.line);

  @override
  String toString() => '$document:$line';
  @override
  bool operator ==(Object other) =>
      other is Origin && document == other.document && line == other.line;
  @override
  int get hashCode => Object.hash(document, line);
}

class Diagnostic {
  final Origin origin;
  final String code;
  final String message;
  const Diagnostic(this.origin, this.code, this.message);

  @override
  bool operator ==(Object other) =>
      other is Diagnostic && origin == other.origin &&
      code == other.code && message == other.message;
  @override
  int get hashCode => Object.hash(origin, code, message);
}

class LogicalLine {
  final int number;
  final segments = <String>[];
  (String, String)? error;
  LogicalLine(this.number);

  void fail(String code, String message) => error ??= (code, message);
}

// Printable ASCII input cannot contain this marker for an escaped dollar.
const literalDollar = '\u0001';

Iterable<LogicalLine> logicalLines(List<String> physicalLines) sync* {
  var index = 0;
  while (index < physicalLines.length) {
    final line = LogicalLine(index + 1);
    var source = physicalLines[index++];
    var position = 0;
    var quoted = false;
    var current = StringBuffer();
    while (position < source.length) {
      final char = source[position];
      if (char == '\\' && position == source.length - 1) {
        source = physicalLines[index++].replaceFirst(RegExp(r'^ *'), '');
        position = 0;
      } else if (quoted && char == '\\') {
        final follower = source[position + 1];
        final decoded = switch (follower) {
          '\\' => '\\', '"' => '"', 'n' => '\n', 't' => '\t',
          r'$' => literalDollar, _ => null,
        };
        if (decoded == null) {
          line.fail('E_ESCAPE', 'invalid escape sequence \\$follower');
        } else {
          current.write(decoded);
        }
        position += 2;
      } else if (char == '"') {
        line.segments.add(current.toString());
        current = StringBuffer();
        quoted = !quoted;
        position++;
      } else if (!quoted && (char == ';' || char == '#')) {
        break;
      } else {
        current.write(char);
        position++;
      }
    }
    if (quoted) line.fail('E_UNTERMINATED', 'unterminated string');
    line.segments.add(current.toString());
    yield line;
  }
}
