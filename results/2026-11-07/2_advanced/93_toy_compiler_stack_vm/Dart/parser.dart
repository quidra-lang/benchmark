part of 'main.dart';

class Expr {
  final String kind;
  String type = '';
  final Token token;
  final int value;
  final List<Expr> children;
  Symbol? referent;
  Expr(this.kind, this.token, {this.value = 0, List<Expr>? children})
    : children = children ?? [];
  Position get position => token.position;
}

class Declaration {
  final String type;
  final Token name;
  bool array = false, function = false;
  Token? size;
  Expr? initializer;
  final List<Declaration> parameters = [];
  Statement? body;
  Symbol? symbol;
  List<Symbol> slots = [];
  Declaration(this.type, this.name);
}

class Statement {
  final String kind;
  final Token token;
  Token? close;
  Declaration? declaration;
  Expr? expression, index, condition;
  final List<Expr> expressions = [];
  final List<Statement> statements = [];
  Statement? thenStatement, elseStatement, body, init, update;
  Symbol? referent;
  Statement(this.kind, this.token, {this.declaration, this.expression});
}

class Program {
  final List<Declaration> declarations = [], globals = [], functions = [];
  late Token end;
  final Map<String, Symbol> names = {};
  final List<Symbol> symbols = [];
}

bool isType(Token t) => wordIn('int bool void', t.kind);
int precedence(String op) => switch (op) {
  '||' => 1,
  '&&' => 2,
  '==' || '!=' => 3,
  '<' || '<=' || '>' || '>=' => 4,
  '+' || '-' => 5,
  '*' || '/' || '%' => 6,
  _ => 0,
};

class Parser {
  final List<Token> tokens;
  int index = 0;
  Parser(this.tokens);
  Token peek() => tokens[index];
  Never fail() {
    final t = peek();
    throw CompileError(
      'syntax',
      t.kind == 'END'
          ? 'unexpected end of program'
          : "unexpected '${t.spelling}'",
      t.position,
    );
  }

  Token take(String kind) {
    if (peek().kind != kind) fail();
    return tokens[index++];
  }

  bool accept(String kind) {
    if (peek().kind != kind) return false;
    index++;
    return true;
  }

  Declaration declarationStart() {
    if (!isType(peek())) fail();
    final type = tokens[index++].kind;
    return Declaration(type, take('identifier'));
  }

  Program program() {
    final out = Program();
    while (peek().kind != 'END') {
      final d = declarationStart();
      if (accept('(')) {
        d.function = true;
        if (!accept(')')) {
          d.parameters.add(declarationStart());
          while (accept(',')) {
            d.parameters.add(declarationStart());
          }
          take(')');
        }
        d.body = block();
        out.functions.add(d);
      } else {
        if (accept('[')) {
          d.array = true;
          d.size = take('integer');
          take(']');
        } else if (accept('=')) {
          d.initializer = expression(1);
        }
        take(';');
        out.globals.add(d);
      }
      out.declarations.add(d);
    }
    out.end = peek();
    return out;
  }

  Statement block() {
    final s = Statement('block', take('{'));
    while (peek().kind != '}') {
      if (peek().kind == 'END') fail();
      if (isType(peek())) {
        final start = peek(), d = declarationStart();
        if (accept('=')) d.initializer = expression(1);
        take(';');
        s.statements.add(Statement('declaration', start, declaration: d));
      } else {
        s.statements.add(statement());
      }
    }
    s.close = take('}');
    return s;
  }

  Statement statement() {
    final t = peek();
    if (t.kind == '{') return block();
    index++;
    var s = Statement(t.kind, t);
    switch (t.kind) {
      case 'if':
        take('(');
        s.condition = expression(1);
        take(')');
        s.thenStatement = statement();
        if (accept('else')) s.elseStatement = statement();
        break;
      case 'while':
        take('(');
        s.condition = expression(1);
        take(')');
        s.body = statement();
        break;
      case 'for':
        take('(');
        if (isType(peek())) {
          final start = peek(), d = declarationStart();
          take('=');
          d.initializer = expression(1);
          s.init = Statement('declaration', start, declaration: d);
        } else if (peek().kind != ';') {
          s.init = simple();
        }
        take(';');
        if (peek().kind != ';') s.condition = expression(1);
        take(';');
        if (peek().kind != ')') s.update = simple();
        take(')');
        s.body = statement();
        break;
      case 'break':
      case 'continue':
        take(';');
        break;
      case 'return':
        if (peek().kind != ';') s.expression = expression(1);
        take(';');
        break;
      case 'print':
        take('(');
        s.expressions.add(expression(1));
        while (accept(',')) {
          s.expressions.add(expression(1));
        }
        take(')');
        take(';');
        break;
      case 'identifier':
      case 'read':
        index--;
        s = simple();
        take(';');
        break;
      default:
        index--;
        fail();
    }
    return s;
  }

  Expr call(Token t) {
    take('(');
    final arguments = <Expr>[];
    if (!accept(')')) {
      arguments.add(expression(1));
      while (accept(',')) {
        arguments.add(expression(1));
      }
      take(')');
    }
    return Expr('call', t, children: arguments);
  }

  Statement simple() {
    var t = peek();
    if (t.kind == 'read') {
      index++;
      take('(');
      take(')');
      return Statement('call', t, expression: Expr('read', t));
    }
    t = take('identifier');
    if (peek().kind == '(') return Statement('call', t, expression: call(t));
    final s = Statement('assignment', t);
    if (accept('[')) {
      s.index = expression(1);
      take(']');
    }
    take('=');
    s.expression = expression(1);
    return s;
  }

  Expr expression(int minimum) {
    var left = unary();
    while (true) {
      final level = precedence(peek().kind);
      if (level == 0 || level < minimum) break;
      final op = tokens[index++], right = expression(level + 1);
      left = Expr('binary', op, children: [left, right]);
    }
    return left;
  }

  Expr unary() {
    if (peek().kind == '-' || peek().kind == '!') {
      final op = tokens[index++];
      return Expr('unary', op, children: [unary()]);
    }
    return primary();
  }

  Expr primary() {
    final t = peek();
    switch (t.kind) {
      case 'integer':
        index++;
        return Expr('integer', t, value: t.integer);
      case 'true':
      case 'false':
        index++;
        return Expr('boolean', t, value: t.kind == 'true' ? 1 : 0);
      case 'read':
        index++;
        take('(');
        take(')');
        return Expr('read', t);
      case '(':
        index++;
        final e = expression(1);
        take(')');
        return e;
      case 'identifier':
        index++;
        if (peek().kind == '(') return call(t);
        if (accept('[')) {
          final index = expression(1);
          take(']');
          return Expr('array', t, children: [index]);
        }
        return Expr('variable', t);
    }
    fail();
  }
}
