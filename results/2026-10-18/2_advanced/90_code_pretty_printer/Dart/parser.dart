part of 'main.dart';

class Node {
  final String kind, value;
  int first, last;
  Token? token, name, open, close, op, colon, elseToken, semi, semi2, trailing;
  Node? expr, left, right, thenNode, elseNode, body, init, cond, update;
  final List<Node> elements, dimensions;
  final List<Token> commas;
  Node(
    this.kind, {
    this.value = '',
    this.first = 0,
    this.last = 0,
    this.token,
    this.name,
    this.open,
    this.close,
    this.op,
    this.colon,
    this.elseToken,
    this.semi,
    this.semi2,
    this.trailing,
    this.expr,
    this.left,
    this.right,
    this.thenNode,
    this.elseNode,
    this.body,
    this.init,
    this.cond,
    this.update,
    List<Node>? elements,
    List<Node>? dimensions,
    List<Token>? commas,
  }) : elements = elements ?? [],
       dimensions = dimensions ?? [],
       commas = commas ?? [];
}

List<Node> nodeChildren(Node n) => [
  for (final child in [
    n.expr,
    n.left,
    n.right,
    n.thenNode,
    n.elseNode,
    n.body,
    n.init,
    n.cond,
    n.update,
  ])
    if (child != null) child,
  ...n.elements,
  ...n.dimensions,
];
bool typeName(Token t) => wordIn('int float bool string void', t.text);
int precedence(String op) => switch (op) {
  '||' => 1,
  '&&' => 2,
  '==' || '!=' => 3,
  '<' || '<=' || '>' || '>=' => 4,
  '+' || '-' => 5,
  '*' || '/' || '%' => 6,
  _ => 0,
};
int expressionLevel(Node n) => switch (n.kind) {
  'conditional' => 0,
  'binary' => precedence(n.op!.text),
  'unary' => 7,
  _ => 8,
};

class Parser {
  final List<Token> tokens;
  int position = 0;
  FileError? error;
  Parser(this.tokens);
  Token peek() => tokens[min(position, tokens.length - 1)];
  Token read() {
    final t = peek();
    if (position < tokens.length - 1) position++;
    return t;
  }

  void fail(String expected) {
    if (error != null) return;
    final t = peek(), actual = t.kind == 'end' ? 'end of file' : "'${t.text}'";
    error = FileError(t, 'expected $expected, found $actual');
  }

  Token take(String text) {
    if (peek().text != text) {
      fail("'$text'");
      return peek();
    }
    return read();
  }

  Token takeType() {
    if (!typeName(peek())) {
      fail('type');
      return peek();
    }
    return read();
  }

  Token identifier() {
    if (peek().kind != 'identifier') {
      fail('identifier');
      return peek();
    }
    return read();
  }

  Node mark(Node n, int start) {
    n.first = start;
    n.last = max(start, position - 1);
    return n;
  }

  Node program() {
    final n = Node('program');
    while (error == null && peek().kind != 'end') {
      final start = position, t = takeType(), name = identifier();
      if (error != null) break;
      if (peek().text == '(') {
        final params = list('parameters', '(', ')', false), body = block();
        n.elements.add(
          mark(
            Node('function', token: t, name: name, init: params, body: body),
            start,
          ),
        );
      } else {
        n.elements.add(declaration(t, name, start, true));
      }
    }
    return n;
  }

  Node list(String kind, String open, String close, bool trailing) {
    final start = position, n = Node('list', value: kind, open: take(open));
    if (peek().text != close && error == null) {
      while (error == null) {
        final child = switch (kind) {
          'parameters' => parameter(),
          'initializer' => initializer(),
          _ => expression(),
        };
        n.elements.add(child);
        if (peek().text != ',') break;
        final comma = read();
        if (trailing && peek().text == close) {
          n.trailing = comma;
          break;
        }
        n.commas.add(comma);
      }
    }
    n.close = take(close);
    return mark(n, start);
  }

  Node parameter() {
    final start = position,
        n = Node('parameter', token: takeType(), name: identifier());
    while (error == null && peek().text == '[') {
      final dstart = position, open = read(), close = take(']');
      n.dimensions.add(
        mark(Node('dimension', open: open, close: close), dstart),
      );
    }
    return mark(n, start);
  }

  Node declaration(Token t, Token name, int start, bool semi) {
    final n = Node('declaration', token: t, name: name);
    while (error == null && peek().text == '[') {
      final dstart = position, open = read(), d = Node('dimension', open: open);
      if (peek().text != ']') d.expr = expression();
      d.close = take(']');
      n.dimensions.add(mark(d, dstart));
    }
    if (error == null && peek().text == '=') {
      n.op = read();
      n.init = initializer();
    }
    if (semi) n.semi = take(';');
    return mark(n, start);
  }

  Node initializer() =>
      peek().text == '{' ? list('initializer', '{', '}', true) : expression();
  Node block() {
    final start = position, n = Node('block', open: take('{'));
    while (error == null && peek().text != '}' && peek().kind != 'end') {
      n.elements.add(statement());
    }
    n.close = take('}');
    return mark(n, start);
  }

  Node statement() {
    final start = position, t = peek();
    if (t.text == '{') return block();
    if (typeName(t)) {
      final typ = read(), name = identifier();
      return declaration(typ, name, start, true);
    }
    var n = Node(t.text, token: read());
    switch (t.text) {
      case 'if':
      case 'while':
        n.open = take('(');
        n.expr = expression();
        n.close = take(')');
        if (error == null) n.body = statement();
        if (t.text == 'if' && error == null && peek().text == 'else') {
          n.elseToken = read();
          n.elseNode = statement();
        }
        break;
      case 'for':
        n.open = take('(');
        if (error == null && peek().text != ';') {
          if (typeName(peek())) {
            final initStart = position, typ = read(), name = identifier();
            n.init = declaration(typ, name, initStart, false);
          } else {
            n.init = simple();
          }
        }
        n.semi = take(';');
        if (error == null && peek().text != ';') n.cond = expression();
        n.semi2 = take(';');
        if (error == null && peek().text != ')') n.update = simple();
        n.close = take(')');
        if (error == null) n.body = statement();
        break;
      case 'switch':
        {
          n.open = take('(');
          n.expr = expression();
          n.close = take(')');
          final bodyStart = position,
              body = Node('switchbody', open: take('{'));
          while (error == null &&
              (peek().text == 'case' || peek().text == 'default')) {
            final clauseStart = position,
                label = read(),
                clause = Node('clause', token: label);
            if (label.text == 'case') clause.expr = expression();
            clause.colon = take(':');
            while (error == null &&
                !wordIn('case default }', peek().text) &&
                peek().kind != 'end') {
              clause.elements.add(statement());
            }
            body.elements.add(mark(clause, clauseStart));
          }
          body.close = take('}');
          n.body = mark(body, bodyStart);
          break;
        }
      case 'return':
        if (error == null && peek().text != ';') n.expr = expression();
        n.semi = take(';');
        break;
      case 'break':
      case 'continue':
        n.semi = take(';');
        break;
      default:
        position = start;
        n = simple();
        n.semi = take(';');
        break;
    }
    return mark(n, start);
  }

  Node simple() {
    final start = position, left = expression();
    var n = Node('simple', expr: left);
    if (error == null && wordIn('= += -= *= /= %=', peek().text)) {
      final op = read();
      n = Node('assignment', left: left, op: op, right: expression());
    }
    return mark(n, start);
  }

  Node expression() {
    final start = position;
    var n = binary(1);
    if (error == null && peek().text == '?') {
      final question = read(),
          then = expression(),
          colon = take(':'),
          other = expression();
      n = mark(
        Node(
          'conditional',
          expr: n,
          op: question,
          thenNode: then,
          colon: colon,
          elseNode: other,
        ),
        start,
      );
    }
    return n;
  }

  Node binary(int level) {
    if (level == 7) return unary();
    var left = binary(level + 1);
    while (error == null && precedence(peek().text) == level) {
      final op = read(), right = binary(level + 1);
      left = Node(
        'binary',
        left: left,
        op: op,
        right: right,
        first: left.first,
        last: right.last,
      );
    }
    return left;
  }

  Node unary() {
    final start = position;
    if (error != null)
      return Node('atom', token: peek(), first: start, last: start);
    if (peek().text == '-' || peek().text == '!') {
      final op = read();
      return mark(Node('unary', op: op, expr: unary()), start);
    }
    final t = peek();
    Node n;
    if (t.kind == 'identifier' ||
        t.kind == 'number' ||
        t.kind == 'string' ||
        t.text == 'true' ||
        t.text == 'false') {
      n = Node('atom', token: read(), first: start, last: start);
    } else if (t.text == '(') {
      final open = read(), inner = expression(), close = take(')');
      n = mark(Node('paren', open: open, close: close, expr: inner), start);
    } else {
      fail('expression');
      return Node('atom', token: t, first: start, last: start);
    }
    while (error == null) {
      switch (peek().text) {
        case '(':
          final args = list('arguments', '(', ')', false);
          n = mark(Node('call', left: n, init: args), start);
          break;
        case '[':
          final open = read(), index = expression(), close = take(']');
          n = mark(
            Node('index', left: n, open: open, close: close, expr: index),
            start,
          );
          break;
        case '.':
          final op = read(), name = identifier();
          n = mark(Node('member', left: n, op: op, name: name), start);
          break;
        default:
          return n;
      }
    }
    return n;
  }
}
