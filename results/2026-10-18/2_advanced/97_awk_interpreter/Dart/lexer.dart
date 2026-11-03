part of 'main.dart';

class Position {
  final int line, column;
  const Position(this.line, this.column);
  String toString() => '$line:$column';
}

class SyntaxIssue implements Exception {
  final Position position;
  SyntaxIssue(this.position);
}

class Token {
  final String kind, spelling, text;
  final int number;
  final Position position;
  Token(
    this.kind,
    this.spelling,
    this.position, {
    this.text = '',
    this.number = 0,
  });
}

bool letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
bool digit(int c) => c >= 48 && c <= 57;
bool wordIn(String words, String value) => words.split(' ').contains(value);
int decimal(String text) => int.parse(text);
List<Token> tokenize(String source) {
  final tokens = <Token>[];
  var i = 0, line = 1, column = 1;
  while (i < source.length) {
    var c = source.codeUnitAt(i);
    final position = Position(line, column);
    if (c == 32) {
      i++;
      column++;
      continue;
    }
    if (c == 92 && i + 1 < source.length && source.codeUnitAt(i + 1) == 10) {
      i += 2;
      line++;
      column = 1;
      continue;
    }
    if (c == 35) {
      while (i < source.length && source.codeUnitAt(i) != 10) {
        i++;
        column++;
      }
      continue;
    }
    if (c == 10) {
      tokens.add(Token('newline', '\n', position));
      i++;
      line++;
      column = 1;
      continue;
    }
    if (digit(c)) {
      final start = i;
      while (i < source.length && digit(source.codeUnitAt(i))) {
        i++;
        column++;
      }
      final text = source.substring(start, i);
      tokens.add(Token('number', text, position, number: decimal(text)));
      continue;
    }
    if (letter(c) || c == 95) {
      final start = i;
      while (i < source.length &&
          (letter(source.codeUnitAt(i)) ||
              digit(source.codeUnitAt(i)) ||
              source.codeUnitAt(i) == 95)) {
        i++;
        column++;
      }
      final text = source.substring(start, i);
      var kind = 'name';
      if (wordIn(
        'BEGIN END function if else while for do break continue next exit return delete in getline print printf',
        text,
      )) {
        kind = 'keyword';
      } else if (wordIn(
        'length substr index split sprintf toupper tolower close int',
        text,
      )) {
        kind = 'builtin';
      } else if (i < source.length && source[i] == '(') {
        kind = 'function_name';
      }
      tokens.add(Token(kind, text, position));
      continue;
    }
    if (c == 34) {
      final start = i;
      i++;
      column++;
      final value = StringBuffer();
      while (true) {
        if (i == source.length || source.codeUnitAt(i) == 10)
          throw SyntaxIssue(position);
        c = source.codeUnitAt(i++);
        column++;
        if (c == 34) break;
        if (c == 92) {
          final slash = Position(line, column - 1);
          if (i == source.length) throw SyntaxIssue(slash);
          c = source.codeUnitAt(i++);
          column++;
          c = switch (c) {
            110 => 10,
            116 => 9,
            92 || 34 || 47 => c,
            _ => throw SyntaxIssue(slash),
          };
        }
        value.writeCharCode(c);
      }
      tokens.add(
        Token(
          'string',
          source.substring(start, i),
          position,
          text: value.toString(),
        ),
      );
      continue;
    }
    var symbol = '';
    if (i + 1 < source.length &&
        wordIn(
          '+= -= *= /= %= ^= == <= >= != ++ -- && || >>',
          source.substring(i, i + 2),
        )) {
      symbol = source.substring(i, i + 2);
    } else if ('+-*/%^!><?:=()[]{},;\$'.contains(source[i])) {
      symbol = source[i];
    }
    if (symbol.isEmpty) throw SyntaxIssue(position);
    tokens.add(Token('symbol', symbol, position));
    i += symbol.length;
    column += symbol.length;
  }
  tokens.add(
    Token(
      'end',
      '',
      Position(source.codeUnits.where((c) => c == 10).length + 1, 1),
    ),
  );
  return tokens;
}
