part of 'main.dart';

class Token {
  final String kind, spelling;
  final int line;
  final bool space;
  final Set<String> hide;
  Token(
    this.kind,
    this.spelling,
    this.line, {
    this.space = false,
    Set<String>? hide,
  }) : hide = Set.unmodifiable(hide ?? {});
  Token copy({
    String? kind,
    String? spelling,
    int? line,
    bool? space,
    Set<String>? hide,
  }) => Token(
    kind ?? this.kind,
    spelling ?? this.spelling,
    line ?? this.line,
    space: space ?? this.space,
    hide: hide ?? this.hide,
  );
}

class LogicalLine {
  final List<Token> tokens;
  final int start, end;
  LogicalLine(this.tokens, this.start, this.end);
}

final punctuators =
    '... <<= >>= -> ++ -- << >> <= >= == != && || *= /= %= += -= &= ^= |= ## [ ] ( ) { } . & * + - ~ ! / % < > ^ | ? : ; = , #'
        .split(' ');
bool identifierStart(String c) =>
    c == '_' ||
    c.compareTo('a') >= 0 && c.compareTo('z') <= 0 ||
    c.compareTo('A') >= 0 && c.compareTo('Z') <= 0;
bool digit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
bool wordIn(String words, String value) => words.split(' ').contains(value);
(String, String, int) readToken(String source, int index, bool header) {
  final c = source[index], n = source.length;
  if (header && c == '<') {
    final end = source.indexOf('>', index + 1),
        newline = source.indexOf('\n', index + 1);
    if (end >= 0 && (newline < 0 || end < newline))
      return ('header', source.substring(index, end + 1), end + 1);
  }
  if (identifierStart(c)) {
    var end = index + 1;
    while (end < n && (identifierStart(source[end]) || digit(source[end]))) {
      end++;
    }
    return ('identifier', source.substring(index, end), end);
  }
  if (digit(c) || c == '.' && index + 1 < n && digit(source[index + 1])) {
    var end = index + 1;
    while (end < n) {
      if ('eEpP'.contains(source[end]) &&
          end + 1 < n &&
          '+-'.contains(source[end + 1])) {
        end += 2;
      } else if (identifierStart(source[end]) ||
          digit(source[end]) ||
          source[end] == '.') {
        end++;
      } else {
        break;
      }
    }
    return ('number', source.substring(index, end), end);
  }
  if (c == "'" || c == '"') {
    var end = index + 1;
    while (end < n && source[end] != '\n') {
      if (source[end] == c)
        return (
          c == '"' ? 'string' : 'character',
          source.substring(index, end + 1),
          end + 1,
        );
      end += source[end] == '\\' && end + 1 < n && source[end + 1] != '\n'
          ? 2
          : 1;
    }
  }
  for (final punctuator in punctuators) {
    if (source.startsWith(punctuator, index))
      return ('punctuator', punctuator, index + punctuator.length);
  }
  return ('other', c, index + 1);
}

List<LogicalLine> scan(String source, List<int> positions, int start) {
  final lines = <LogicalLine>[];
  var tokens = <Token>[], spaced = true;
  for (var index = 0; index < source.length;) {
    if (source[index] == ' ') {
      spaced = true;
      index++;
    } else if (source[index] == '\n') {
      final end = positions[index];
      lines.add(LogicalLine(tokens, start, end));
      tokens = [];
      start = end + 1;
      spaced = true;
      index++;
    } else if (source.startsWith('/*', index)) {
      final end = source.indexOf('*/', index + 2);
      index = end < 0 ? source.length : end + 2;
      spaced = true;
    } else if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index);
      index = end < 0 ? source.length : end;
      spaced = true;
    } else {
      final header =
          tokens.length == 2 &&
          tokens[0].spelling == '#' &&
          tokens[1].spelling == 'include';
      final (kind, spelling, end) = readToken(source, index, header);
      tokens.add(Token(kind, spelling, positions[index], space: spaced));
      index = end;
      spaced = false;
    }
  }
  if (tokens.isNotEmpty) lines.add(LogicalLine(tokens, start, positions.last));
  return lines;
}

List<LogicalLine> lexSource(String source) {
  final characters = StringBuffer(), positions = <int>[];
  var line = 1;
  for (var i = 0; i < source.length;) {
    if (i + 1 < source.length && source[i] == '\\' && source[i + 1] == '\n') {
      i += 2;
      line++;
      continue;
    }
    final c = source[i++];
    characters.write(c);
    positions.add(line);
    if (c == '\n') line++;
  }
  return scan(characters.toString(), positions, 1);
}

List<Token> lexDefinition(String source, int line) {
  source += '\n';
  return [
    for (final logical in scan(source, List.filled(source.length, line), line))
      ...logical.tokens,
  ];
}

String render(List<Token> tokens) => [
  for (var i = 0; i < tokens.length; i++)
    '${i > 0 && tokens[i].space ? ' ' : ''}${tokens[i].spelling}',
].join();
String? singleToken(String source) {
  if (source.isEmpty || source.startsWith('//') || source.startsWith('/*'))
    return null;
  final (kind, _, end) = readToken(source, 0, false);
  return end == source.length ? kind : null;
}
