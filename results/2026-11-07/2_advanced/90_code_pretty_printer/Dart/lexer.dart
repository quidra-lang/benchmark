part of 'main.dart';

class Position {
  final int line, column;
  const Position(this.line, this.column);
}

class FileError extends Position {
  final String message;
  FileError(Position p, this.message) : super(p.line, p.column);
}

class Comment extends Position {
  final String text, kind;
  final int blank;
  bool own = false;
  Comment(this.text, this.kind, Position p, this.blank)
    : super(p.line, p.column);
}

class Token extends Position {
  final String text, kind;
  final int blank, index;
  final List<Comment> leading = [];
  List<Comment> trailing = [];
  bool originalTrailing = false;
  Token(this.text, this.kind, Position p, {this.blank = 0, this.index = 0})
    : super(p.line, p.column);
}

class Lexeme {
  final Token? token;
  final Comment? comment;
  Lexeme.token(Token t) : token = t, comment = null;
  Lexeme.comment(Comment c) : token = null, comment = c;
  int get line => token?.line ?? comment!.line;
}

bool wordIn(String words, String value) => words.split(' ').contains(value);
bool letter(String c) =>
    c.compareTo('A') >= 0 && c.compareTo('Z') <= 0 ||
    c.compareTo('a') >= 0 && c.compareTo('z') <= 0 ||
    c == '_';
bool digit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
(List<Token>, List<Lexeme>, FileError?) lex(List<String> source) {
  final tokens = <Token>[], items = <Lexeme>[];
  var previousLine = 0;
  for (var row = 0; row < source.length; row++) {
    final line = source[row];
    for (var i = 0; i < line.length;) {
      final c = line[i];
      if (c == ' ') {
        i++;
        continue;
      }
      final position = Position(row + 1, i + 1),
          blank = max(0, row + 1 - previousLine - 1);
      void addToken(String text, String kind) {
        final t = Token(
          text,
          kind,
          position,
          blank: blank,
          index: tokens.length,
        );
        tokens.add(t);
        items.add(Lexeme.token(t));
        previousLine = row + 1;
      }

      void addComment(String text, String kind) {
        items.add(Lexeme.comment(Comment(text, kind, position, blank)));
        previousLine = row + 1;
      }

      if (line.startsWith('//', i)) {
        addComment(line.substring(i).trimRight(), 'line');
        break;
      }
      if (line.startsWith('/*', i)) {
        final end = line.indexOf('*/', i + 2);
        if (end < 0)
          return (
            <Token>[],
            <Lexeme>[],
            FileError(position, 'unterminated comment'),
          );
        addComment(line.substring(i, end + 2), 'block');
        i = end + 2;
        continue;
      }
      if (letter(c)) {
        var j = i + 1;
        while (j < line.length && (letter(line[j]) || digit(line[j]))) {
          j++;
        }
        final value = line.substring(i, j),
            kind =
                wordIn(
                  'int float bool string void if else while for return break continue true false switch case default',
                  value,
                )
                ? 'keyword'
                : 'identifier';
        addToken(value, kind);
        i = j;
        continue;
      }
      if (digit(c)) {
        var j = i + 1;
        while (j < line.length && digit(line[j])) {
          j++;
        }
        if (j + 1 < line.length && line[j] == '.' && digit(line[j + 1])) {
          j += 2;
          while (j < line.length && digit(line[j])) {
            j++;
          }
        }
        addToken(line.substring(i, j), 'number');
        i = j;
        continue;
      }
      if (c == '"') {
        var j = i + 1;
        while (j < line.length && line[j] != '"') {
          j += line[j] == '\\' ? 2 : 1;
        }
        if (j >= line.length)
          return (
            <Token>[],
            <Lexeme>[],
            FileError(position, 'unterminated string'),
          );
        j++;
        addToken(line.substring(i, j), 'string');
        i = j;
        continue;
      }
      if (i + 1 < line.length &&
          wordIn(
            '<= >= == != && || += -= *= /= %=',
            line.substring(i, i + 2),
          )) {
        addToken(line.substring(i, i + 2), 'symbol');
        i += 2;
        continue;
      }
      if ('+-*/%<>=!()[]{},;.?:'.contains(c)) {
        addToken(c, 'symbol');
        i++;
        continue;
      }
      return (
        <Token>[],
        <Lexeme>[],
        FileError(position, "unexpected character '$c'"),
      );
    }
  }
  tokens.add(
    Token('', 'end', Position(source.length + 1, 1), index: tokens.length),
  );
  return (tokens, items, null);
}
