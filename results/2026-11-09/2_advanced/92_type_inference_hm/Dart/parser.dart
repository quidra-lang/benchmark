part of 'main.dart';

class Expr {
  final String kind, value;
  Position position;
  final int integer;
  final List<Expr> children;
  final Token? token;
  final Group? group;
  final List<Arm> arms;
  Type? inferred;
  Expr(
    this.kind,
    this.position, {
    this.value = '',
    this.integer = 0,
    List<Expr>? children,
    this.token,
    this.group,
    List<Arm>? arms,
  }) : children = children ?? [],
       arms = arms ?? [];
}

class Arm {
  final Expr pattern, body;
  Arm(this.pattern, this.body);
}

class Binding {
  final Token name;
  final Expr expression;
  Scheme? scheme;
  String classification = '';
  Binding(this.name, this.expression);
}

class Group {
  final List<Binding> bindings = [];
  Position? rec;
}

class Item {
  final String kind;
  final Token? name;
  final Expr? declared, expression;
  final Group? group;
  Item(this.kind, {this.name, this.declared, this.expression, this.group});
}

class SyntaxError implements Exception {
  final Token token;
  SyntaxError(this.token);
}

(int, bool) operatorInfo(String op) => switch (op) {
  '||' => (1, true),
  '&&' => (2, true),
  '=' || '<>' || '<' || '>' || '<=' || '>=' => (3, false),
  '::' || '^' => (4, true),
  '+' || '-' => (5, false),
  '*' || '/' || 'mod' => (6, false),
  _ => (0, false),
};

class Parser {
  final List<Token> tokens;
  int index = 0;
  Parser(this.tokens);
  Token peek() => tokens[index];
  Token? accept(String kind) {
    final t = peek();
    if (t.kind != kind) return null;
    index++;
    return t;
  }

  Token expect(String kind) => accept(kind) ?? (throw SyntaxError(peek()));
  Token name() {
    if (!peek().name) throw SyntaxError(peek());
    return expect('identifier');
  }

  void recoverItem() {
    while (peek().kind != ';;' && peek().kind != 'EOF') {
      index++;
    }
    accept(';;');
  }

  Item item() {
    if (accept('val') != null) {
      final n = name();
      expect(':');
      final declared = typeExpression();
      expect(';;');
      return Item('signature', name: n, declared: declared);
    }
    Item result;
    final opening = accept('let');
    if (opening != null) {
      final g = group();
      if (accept('in') != null) {
        result = Item(
          'expression',
          expression: Expr(
            'let',
            opening.position,
            group: g,
            children: [expression()],
          ),
        );
      } else {
        result = Item('declaration', group: g);
      }
    } else {
      result = Item('expression', expression: expression());
    }
    expect(';;');
    return result;
  }

  Group group() {
    final g = Group(), rec = accept('rec');
    g.rec = rec?.position;
    g.bindings.add(binding());
    while (accept('and') != null) {
      g.bindings.add(binding());
    }
    return g;
  }

  Binding binding() {
    final n = name(), parameters = <Token>[];
    while (peek().kind == 'identifier') {
      parameters.add(expect('identifier'));
    }
    expect('=');
    var e = expression();
    for (final parameter in parameters.reversed) {
      e = Expr('fun', parameter.position, token: parameter, children: [e]);
    }
    return Binding(n, e);
  }

  Expr expression() {
    final let = accept('let');
    if (let != null) {
      final g = group();
      expect('in');
      return Expr('let', let.position, group: g, children: [expression()]);
    }
    final fun = accept('fun');
    if (fun != null) {
      final parameters = [expect('identifier')];
      while (peek().kind == 'identifier') {
        parameters.add(expect('identifier'));
      }
      expect('->');
      var e = expression();
      for (final parameter in parameters.reversed) {
        e = Expr('fun', parameter.position, token: parameter, children: [e]);
      }
      e.position = fun.position;
      return e;
    }
    final condition = accept('if');
    if (condition != null) {
      final c = expression();
      expect('then');
      final first = expression();
      expect('else');
      final second = expression();
      return Expr('if', condition.position, children: [c, first, second]);
    }
    final match = accept('match');
    if (match != null) {
      final e = expression();
      expect('with');
      accept('|');
      final arms = [arm()];
      while (accept('|') != null) {
        arms.add(arm());
      }
      return Expr('match', match.position, children: [e], arms: arms);
    }
    return binary(1);
  }

  Arm arm() {
    final p = pattern();
    expect('->');
    return Arm(p, expression());
  }

  Expr binary(int minimum) {
    var left = unary();
    while (true) {
      final (precedence, rightAssociative) = operatorInfo(peek().kind);
      if (precedence == 0 || precedence < minimum) break;
      final op = tokens[index++],
          right = binary(rightAssociative ? precedence : precedence + 1);
      left = Expr('binary', left.position, token: op, children: [left, right]);
    }
    return left;
  }

  bool startsAtom(Token t) =>
      wordIn('integer string true false ( [', t.kind) || t.name;
  Expr unary() {
    final op = accept('-');
    if (op != null)
      return Expr('negate', op.position, token: op, children: [unary()]);
    var e = atom();
    while (startsAtom(peek())) {
      e = Expr('apply', e.position, children: [e, atom()]);
    }
    return e;
  }

  Expr atom() {
    final t = peek();
    if (t.kind == 'integer' || t.kind == 'string') {
      index++;
      return Expr(t.kind, t.position, value: t.value, integer: t.integer);
    }
    if (t.kind == 'true' || t.kind == 'false') {
      index++;
      return Expr('boolean', t.position, value: t.kind);
    }
    if (t.name) {
      index++;
      return Expr('name', t.position, value: t.spelling);
    }
    if (accept('(') != null) {
      final first = expression();
      if (accept(',') != null) {
        final second = expression();
        expect(')');
        return Expr('pair', t.position, children: [first, second]);
      }
      expect(')');
      return first;
    }
    if (accept('[') != null) {
      final elements = <Expr>[];
      if (accept(']') == null) {
        elements.add(expression());
        while (accept(';') != null) {
          elements.add(expression());
        }
        expect(']');
      }
      return Expr('list', t.position, children: elements);
    }
    throw SyntaxError(t);
  }

  Expr pattern() {
    final first = patternAtom();
    return accept('::') != null
        ? Expr('cons', first.position, children: [first, pattern()])
        : first;
  }

  Expr patternAtom() {
    final t = peek();
    if (t.kind == 'identifier') {
      index++;
      return Expr(
        t.spelling == '_' ? 'wildcard' : 'name',
        t.position,
        value: t.spelling,
      );
    }
    if (accept('-') != null) {
      final number = expect('integer');
      return Expr('integer', t.position, integer: -number.integer);
    }
    if (wordIn('integer string true false', t.kind)) return atom();
    if (accept('(') != null) {
      final first = pattern();
      if (accept(',') != null) {
        final second = pattern();
        expect(')');
        return Expr('pair', t.position, children: [first, second]);
      }
      expect(')');
      return first;
    }
    if (accept('[') != null) {
      final elements = <Expr>[];
      if (accept(']') == null) {
        elements.add(pattern());
        while (accept(';') != null) {
          elements.add(pattern());
        }
        expect(']');
      }
      return Expr('list', t.position, children: elements);
    }
    throw SyntaxError(t);
  }

  Expr typeExpression() {
    var first = listType();
    if (accept('*') != null)
      first = Expr('pair', first.position, children: [first, listType()]);
    if (accept('->') != null)
      first = Expr(
        'function',
        first.position,
        children: [first, typeExpression()],
      );
    return first;
  }

  Expr listType() {
    var e = typeAtom();
    while (peek().kind == 'identifier' && peek().spelling == 'list') {
      index++;
      e = Expr('list', e.position, children: [e]);
    }
    return e;
  }

  Expr typeAtom() {
    final t = peek();
    if (t.kind == 'identifier' && wordIn('int bool string', t.spelling)) {
      index++;
      return Expr(t.spelling, t.position);
    }
    if (accept('type_variable') != null)
      return Expr('type_variable', t.position, value: t.spelling);
    if (accept('(') != null) {
      final e = typeExpression();
      expect(')');
      return e;
    }
    throw SyntaxError(t);
  }
}
