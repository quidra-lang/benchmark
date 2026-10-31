part of 'main.dart';

class Position {
  final int line, column;
  const Position(this.line, this.column);
  @override
  String toString() => '$line:$column';
}

bool earlier(Position a, Position b) =>
    a.line < b.line || a.line == b.line && a.column < b.column;

class Token {
  final String kind, spelling;
  final int integer;
  final Position position;
  Token(this.kind, this.position, {this.spelling = '', this.integer = 0});
}

class CompileError implements Exception {
  final String kind, message;
  final Position position;
  CompileError(this.kind, this.message, this.position);
}

bool wordIn(String words, String value) => words.split(' ').contains(value);
bool letter(String c) =>
    c.compareTo('A') >= 0 && c.compareTo('Z') <= 0 ||
    c.compareTo('a') >= 0 && c.compareTo('z') <= 0 ||
    c == '_';
bool digit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
List<Token> tokenize(List<String> lines, int firstLine) {
  final source = '${lines.join('\n')}\n',
      positions = <Position>[],
      tokens = <Token>[];
  var line = firstLine, column = 1;
  for (var i = 0; i < source.length; i++) {
    positions.add(Position(line, column));
    if (source[i] == '\n') {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  for (var i = 0; i < source.length;) {
    final c = source[i];
    if (c == ' ' || c == '\n') {
      i++;
      continue;
    }
    final start = i, pos = positions[i];
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      if (end < 0) throw CompileError('lexical', 'unterminated comment', pos);
      i = end + 2;
      continue;
    }
    if (letter(c)) {
      i++;
      while (i < source.length && (letter(source[i]) || digit(source[i]))) {
        i++;
      }
      final spelling = source.substring(start, i),
          kind =
              wordIn(
                'int bool void true false if else while for break continue return print read',
                spelling,
              )
              ? spelling
              : 'identifier';
      tokens.add(Token(kind, pos, spelling: spelling));
      continue;
    }
    if (digit(c)) {
      i++;
      while (i < source.length && digit(source[i])) {
        i++;
      }
      final spelling = source.substring(start, i),
          digits = spelling.replaceFirst(RegExp(r'^0+'), '');
      if (digits.length > 10 ||
          digits.length == 10 && digits.compareTo('2147483647') > 0)
        throw CompileError('lexical', 'integer literal too large', pos);
      tokens.add(
        Token(
          'integer',
          pos,
          spelling: spelling,
          integer: int.parse(digits.isEmpty ? '0' : digits),
        ),
      );
      continue;
    }
    if (i + 1 < source.length &&
        wordIn('<= >= == != && ||', source.substring(i, i + 2))) {
      final spelling = source.substring(i, i + 2);
      tokens.add(Token(spelling, pos, spelling: spelling));
      i += 2;
      continue;
    }
    if ('+-*/%<>=!(){}[],;'.contains(c)) {
      tokens.add(Token(c, pos, spelling: c));
      i++;
      continue;
    }
    throw CompileError('lexical', "unexpected character '$c'", pos);
  }
  tokens.add(
    Token('END', Position(firstLine + lines.length - 1, lines.last.length + 1)),
  );
  return tokens;
}
