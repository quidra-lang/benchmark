part of 'main.dart';

class Expr {
  final String op, name;
  final Value? value;
  final List<Expr> args;
  Expr(this.op, {this.name = '', this.value, this.args = const []});
}

List<String> tokenize(String s) {
  final out = <String>[];
  var i = 0;
  while (i < s.length) {
    if (s[i] == ' ') {
      i++;
      continue;
    }
    final start = i, c = s[i];
    if (c == '"') {
      i++;
      while (s[i] != '"') {
        i++;
      }
      i++;
    } else if (digit(c)) {
      i++;
      while (i < s.length && digit(s[i])) {
        i++;
      }
    } else if (letter(c)) {
      i++;
      while (i < s.length &&
          (letter(s[i]) || digit(s[i]) || s[i] == '_' || s[i] == '.')) {
        i++;
      }
    } else {
      i++;
      if (i < s.length && s[i] == '=' && '=!<>'.contains(c)) i++;
    }
    out.add(s.substring(start, i));
  }
  return out;
}

bool digit(String s) => s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
bool letter(String s) {
  final c = s.codeUnitAt(0);
  return c >= 65 && c <= 90 || c >= 97 && c <= 122;
}

class ExprParser {
  final List<String> tokens;
  int at = 0;
  ExprParser(String s) : tokens = tokenize(s);
  String get peek => at == tokens.length ? '' : tokens[at];
  String take() => tokens[at++];
  Expr joined(Expr Function() next, List<String> ops) {
    var e = next();
    while (ops.contains(peek)) {
      final op = take();
      e = Expr(op, args: [e, next()]);
    }
    return e;
  }

  Expr disjunction() => joined(conjunction, ['or']);
  Expr conjunction() => joined(negation, ['and']);
  Expr negation() {
    if (peek == 'not') {
      take();
      return Expr('not', args: [negation()]);
    }
    return comparison();
  }

  Expr comparison() {
    final e = sum(), op = peek;
    if (['==', '!=', '<', '<=', '>', '>=', 'in'].contains(op)) {
      take();
      return Expr(op, args: [e, sum()]);
    }
    return e;
  }

  Expr sum() => joined(product, ['+', '-']);
  Expr product() => joined(unary, ['*']);
  Expr unary() {
    if (peek == '-') {
      take();
      return Expr('-', args: [unary()]);
    }
    return primary();
  }

  Expr primary() {
    final token = take();
    if (token == '(') {
      final e = disjunction();
      take();
      return e;
    }
    if (token == '[') {
      final a = <String>[];
      while (peek != ']') {
        final s = take();
        a.add(s.substring(1, s.length - 1));
        if (peek != ']') take();
      }
      take();
      return Expr('literal', value: Value.bag(a));
    }
    if (token.startsWith('"'))
      return Expr(
        'literal',
        value: Value.string(token.substring(1, token.length - 1)),
      );
    if (digit(token[0]))
      return Expr('literal', value: Value.integer(number(token)));
    if (token == 'true' || token == 'false')
      return Expr('literal', value: Value.boolean(token == 'true'));
    if (token == 'it') return Expr('it');
    if (token.contains('.')) return Expr('attribute', name: token);
    take();
    final args = <Expr>[];
    while (peek != ')') {
      args.add(disjunction());
      if (peek != ')') take();
    }
    take();
    return Expr(token, args: args);
  }
}

Expr parseExpr(String s) => ExprParser(s).disjunction();
