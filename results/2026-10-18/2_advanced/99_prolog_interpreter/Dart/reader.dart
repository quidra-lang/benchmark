part of 'main.dart';

class Position {
  final int line, column;
  Position(this.line, this.column);
}

class Token {
  String kind = '', name = '', spelling = '', message = '';
  int integer = 0;
  final Position position;
  final bool whitespace;
  Token(this.position, this.whitespace);
}

bool lower(int c) => c >= 97 && c <= 122;
bool upper(int c) => c >= 65 && c <= 90;
bool digit(int c) => c >= 48 && c <= 57;
bool alphanumeric(int c) => lower(c) || upper(c) || digit(c) || c == 95;
bool symbol(int c) => r'+-*/\^<>=~:.?@#&$'.codeUnits.contains(c);
List<Token> lex(String source, int startColumn) {
  final tokens = <Token>[];
  var i = 0, line = 1, column = startColumn;
  var space = true;
  while (i < source.length) {
    var c = source.codeUnitAt(i);
    if (c == 32 || c == 10) {
      space = true;
      i++;
      if (c == 10) {
        line++;
        column = 1;
      } else {
        column++;
      }
      continue;
    }
    if (c == 37) {
      space = true;
      while (i < source.length && source.codeUnitAt(i) != 10) {
        i++;
        column++;
      }
      continue;
    }
    final start = i;
    final token = Token(Position(line, column), space);
    space = false;
    if (digit(c)) {
      token.kind = 'integer';
      var n = 0;
      var tooLarge = false;
      while (i < source.length && digit(source.codeUnitAt(i))) {
        if (n > 214748364 || n == 214748364 && source.codeUnitAt(i) > 55)
          tooLarge = true;
        if (!tooLarge) n = n * 10 + source.codeUnitAt(i) - 48;
        i++;
        column++;
      }
      token.integer = n;
      if (tooLarge) {
        token.kind = 'invalid';
        token.message = 'integer too large';
      }
    } else if (lower(c) || upper(c) || c == 95) {
      token.kind = lower(c) ? 'name' : 'variable';
      while (i < source.length && alphanumeric(source.codeUnitAt(i))) {
        i++;
        column++;
      }
      token.name = source.substring(start, i);
    } else if (symbol(c)) {
      while (i < source.length && symbol(source.codeUnitAt(i))) {
        i++;
        column++;
      }
      token.name = source.substring(start, i);
      token.kind = 'name';
      if (token.name == '.' &&
          (i == source.length || {32, 10, 37}.contains(source.codeUnitAt(i))))
        token.kind = 'end';
    } else if (c == 33 || c == 59) {
      token.kind = 'name';
      token.name = source[i++];
      column++;
    } else if (',|()[]'.codeUnits.contains(c)) {
      token.kind = 'punctuation';
      token.name = source[i++];
      column++;
    } else if (c == 39) {
      token.kind = 'quoted';
      i++;
      column++;
      final name = StringBuffer();
      var incorrect = false, closed = false;
      while (i < source.length && source.codeUnitAt(i) != 10) {
        c = source.codeUnitAt(i);
        if (c == 39) {
          if (i + 1 < source.length && source.codeUnitAt(i + 1) == 39) {
            name.writeCharCode(39);
            i += 2;
            column += 2;
            continue;
          }
          i++;
          column++;
          closed = true;
          break;
        }
        if (c == 92) {
          if (i + 1 == source.length || source.codeUnitAt(i + 1) == 10) {
            i++;
            column++;
            continue;
          }
          final next = source.codeUnitAt(i + 1);
          switch (next) {
            case 110:
              name.writeCharCode(10);
            case 116:
              name.writeCharCode(9);
            case 92:
            case 39:
              name.writeCharCode(next);
            default:
              incorrect = true;
          }
          i += 2;
          column += 2;
          continue;
        }
        name.writeCharCode(c);
        i++;
        column++;
      }
      if (!closed) {
        token.kind = 'invalid';
        token.message = 'unterminated quoted atom';
      } else if (incorrect) {
        token.kind = 'invalid';
        token.message = 'undefined escape sequence';
      } else {
        token.name = name.toString();
      }
    } else {
      token.kind = 'invalid';
      token.message = "illegal character '${String.fromCharCode(c)}'";
      i++;
      column++;
    }
    token.spelling = source.substring(start, i);
    tokens.add(token);
  }
  tokens.add(Token(Position(line, column), space)..kind = 'eof');
  return tokens;
}

class Operator {
  final int priority, left, right;
  const Operator(this.priority, this.left, this.right);
}

const infixOperators = {
  ':-': Operator(1200, 1199, 1199),
  ';': Operator(1100, 1099, 1100),
  '->': Operator(1050, 1049, 1050),
  ',': Operator(1000, 999, 1000),
  '=': Operator(700, 699, 699),
  r'\=': Operator(700, 699, 699),
  '==': Operator(700, 699, 699),
  r'\==': Operator(700, 699, 699),
  'is': Operator(700, 699, 699),
  '=:=': Operator(700, 699, 699),
  r'=\=': Operator(700, 699, 699),
  '<': Operator(700, 699, 699),
  '>': Operator(700, 699, 699),
  '=<': Operator(700, 699, 699),
  '>=': Operator(700, 699, 699),
  '=..': Operator(700, 699, 699),
  '+': Operator(500, 500, 499),
  '-': Operator(500, 500, 499),
  '*': Operator(400, 400, 399),
  '/': Operator(400, 400, 399),
  '//': Operator(400, 400, 399),
  'mod': Operator(400, 400, 399),
  'rem': Operator(400, 400, 399),
};
const prefixOperators = {r'\+': 900, '-': 200};

class SyntaxIssue implements Exception {
  final Token token;
  final int index;
  final String message;
  SyntaxIssue(this.token, this.index, this.message);
}

class Reader {
  final List<Token> tokens;
  int index = 0;
  Map<String, Term> named = {};
  Map<String, int> counts = {};
  List<String> order = [];
  Reader(this.tokens);
  Token get peek => tokens[index];
  Token take() {
    final token = peek;
    if (token.kind != 'eof') index++;
    return token;
  }

  Never fail(Token token, int index, [String? message]) {
    message ??= switch (token.kind) {
      'invalid' => token.message,
      'eof' => 'unexpected end of file',
      'end' => 'unexpected end of clause',
      _ =>
        token.kind == 'name' && infixOperators.containsKey(token.name)
            ? 'operator priority clash'
            : 'unexpected "${token.spelling}"',
    };
    throw SyntaxIssue(token, index, message);
  }

  void expect(String name) {
    final start = index;
    final token = take();
    if (token.kind != 'punctuation' || token.name != name) fail(token, start);
  }

  bool canStart(Token token) =>
      {'integer', 'variable', 'quoted'}.contains(token.kind) ||
      token.kind == 'punctuation' && (token.name == '(' || token.name == '[') ||
      token.kind == 'name' &&
          (!infixOperators.containsKey(token.name) ||
              prefixOperators.containsKey(token.name));
  (Term, int) term(int limit) {
    var (left, priority) = primary(limit);
    while (true) {
      final next = peek;
      final op = infixOperators[next.name];
      if (op == null ||
          next.kind != 'name' &&
              (next.kind != 'punctuation' || next.name != ',') ||
          op.priority > limit ||
          priority > op.left)
        return (left, priority);
      take();
      final (right, _) = term(op.right);
      left = compound(next.name, [left, right]);
      priority = op.priority;
    }
  }

  (Term, int) primary(int limit) {
    final start = index;
    final token = take();
    switch (token.kind) {
      case 'integer':
        return (integer(token.integer), 0);
      case 'variable':
        counts.update(token.name, (n) => n + 1, ifAbsent: () => 1);
        if (counts[token.name] == 1) order.add(token.name);
        return (
          token.name == '_'
              ? variable()
              : named.putIfAbsent(token.name, variable),
          0,
        );
      case 'punctuation':
        if (token.name == '(') {
          final (value, _) = term(1200);
          expect(')');
          return (value, 0);
        }
        if (token.name == '[') {
          if (peek.kind == 'punctuation' && peek.name == ']') {
            take();
            return (atom('[]'), 0);
          }
          final elements = [term(999).$1];
          while (peek.kind == 'punctuation' && peek.name == ',') {
            take();
            elements.add(term(999).$1);
          }
          var tail = atom('[]');
          if (peek.kind == 'punctuation' && peek.name == '|') {
            take();
            tail = term(999).$1;
          }
          expect(']');
          return (makeList(elements, tail), 0);
        }
        fail(token, start);
      case 'name':
      case 'quoted':
        if (peek.kind == 'punctuation' &&
            peek.name == '(' &&
            !peek.whitespace) {
          take();
          final args = [term(999).$1];
          while (peek.kind == 'punctuation' && peek.name == ',') {
            take();
            args.add(term(999).$1);
          }
          expect(')');
          return (compound(token.name, args), 0);
        }
        if (token.kind == 'name' &&
            token.name == '-' &&
            peek.kind == 'integer' &&
            !peek.whitespace)
          return (integer(-take().integer), 0);
        final priority = prefixOperators[token.name];
        if (token.kind == 'name' && priority != null && canStart(peek)) {
          if (priority > limit) fail(token, start, 'operator priority clash');
          return (compound(token.name, [term(priority).$1]), priority);
        }
        return (atom(token.name), 0);
      default:
        fail(token, start);
    }
  }

  Term clause(bool query) {
    named = {};
    counts = {};
    order = [];
    final result = term(1200).$1;
    final start = index;
    final token = take();
    if (token.kind != 'end') fail(token, start);
    if (query && peek.kind != 'eof') fail(peek, index);
    return result;
  }
}
