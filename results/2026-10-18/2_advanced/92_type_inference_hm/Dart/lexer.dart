part of 'main.dart';

class Position {
  final String file;
  final int line, column;
  const Position(this.file, this.line, this.column);
}

class Token {
  final String kind, spelling, value;
  final Position position;
  final int integer;
  Token(
    this.kind,
    this.position, {
    this.spelling = '',
    this.value = '',
    this.integer = 0,
  });
  bool get name => kind == 'identifier' && spelling != '_';
}

bool wordIn(String words, String value) => words.split(' ').contains(value);
bool letter(String c) =>
    c.compareTo('A') >= 0 && c.compareTo('Z') <= 0 ||
    c.compareTo('a') >= 0 && c.compareTo('z') <= 0;
bool digit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
List<Token> lex(String filename, List<String> lines) {
  final source = lines.isEmpty ? '' : '${lines.join('\n')}\n',
      positions = <Position>[],
      out = <Token>[];
  var line = 1, column = 1;
  for (var i = 0; i < source.length; i++) {
    positions.add(Position(filename, line, column));
    if (source[i] == '\n') {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  positions.add(Position(filename, lines.length + 1, 1));
  for (var i = 0; i < source.length;) {
    final c = source[i];
    if (c == ' ' || c == '\n') {
      i++;
      continue;
    }
    final start = i, position = positions[i];
    if (source.startsWith('(*', i)) {
      final end = source.indexOf('*)', i + 2);
      if (end < 0) {
        out.add(Token('invalid', position, value: 'unterminated comment'));
        break;
      }
      i = end + 2;
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
          digits.length == 10 && digits.compareTo('2147483647') > 0) {
        out.add(
          Token(
            'invalid',
            position,
            spelling: spelling,
            value: 'integer literal too large',
          ),
        );
      } else {
        out.add(
          Token(
            'integer',
            position,
            spelling: spelling,
            integer: int.parse(digits.isEmpty ? '0' : digits),
          ),
        );
      }
      continue;
    }
    if (letter(c) || c == '_') {
      i++;
      while (i < source.length &&
          (letter(source[i]) ||
              digit(source[i]) ||
              source[i] == '_' ||
              source[i] == "'")) {
        i++;
      }
      final spelling = source.substring(start, i),
          kind =
              wordIn(
                'let rec and in fun if then else match with true false mod val',
                spelling,
              )
              ? spelling
              : 'identifier';
      out.add(Token(kind, position, spelling: spelling));
      continue;
    }
    if (c == "'" &&
        i + 1 < source.length &&
        source[i + 1].compareTo('a') >= 0 &&
        source[i + 1].compareTo('z') <= 0) {
      i += 2;
      while (i < source.length &&
          (letter(source[i]) || digit(source[i]) || source[i] == '_')) {
        i++;
      }
      out.add(
        Token('type_variable', position, spelling: source.substring(start, i)),
      );
      continue;
    }
    if (c == '"') {
      i++;
      var bad = false;
      final value = StringBuffer();
      while (i < source.length && source[i] != '\n' && source[i] != '"') {
        if (source[i] == '\\' &&
            i + 1 < source.length &&
            source[i + 1] != '\n') {
          final next = source[i + 1];
          switch (next) {
            case 'n':
              value.write('\n');
              break;
            case 't':
              value.write('\t');
              break;
            case '\\':
            case '"':
              value.write(next);
              break;
            default:
              bad = true;
              break;
          }
          i += 2;
        } else {
          value.write(source[i++]);
        }
      }
      var kind = 'string', content = value.toString();
      if (i == source.length || source[i] == '\n') {
        kind = 'invalid';
        content = 'unterminated string';
      } else {
        i++;
        if (bad) {
          kind = 'invalid';
          content = 'invalid escape sequence';
        }
      }
      out.add(
        Token(
          kind,
          position,
          spelling: source.substring(start, i),
          value: content,
        ),
      );
      continue;
    }
    var found = '';
    for (final symbol
        in ';; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |'.split(
          ' ',
        )) {
      if (source.startsWith(symbol, i) && symbol.length > found.length)
        found = symbol;
    }
    if (found.isNotEmpty) {
      i += found.length;
      out.add(Token(found, position, spelling: found));
    } else {
      i++;
      out.add(
        Token(
          'invalid',
          position,
          spelling: c,
          value: "illegal character '$c'",
        ),
      );
    }
  }
  out.add(Token('EOF', positions.last));
  return out;
}
