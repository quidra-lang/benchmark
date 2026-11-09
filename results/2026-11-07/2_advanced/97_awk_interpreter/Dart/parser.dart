part of 'main.dart';

typedef Binding = (Item?, String);

class Expr {
  String kind;
  final String name, op;
  final Position position;
  final Value value;
  final Expr? left, right, third;
  final List<Expr> args;
  late Binding binding;
  Item? function;
  final bool prefix;
  Expr(
    this.kind,
    this.position, {
    this.name = '',
    this.op = '',
    this.value = const Value(),
    this.left,
    this.right,
    this.third,
    this.args = const [],
    this.prefix = false,
  });
}

class Statement {
  String kind;
  final Position position;
  List<Expr?> exprs = [];
  Statement? body, otherwise;
  final List<Statement> statements = [];
  Expr? variable, array, redirect;
  String redirectMode = '';
  Position redirectPosition = const Position(0, 0);
  bool wholeDelete = false;
  Statement(this.kind, this.position);
}

class Item {
  final String kind, name, flavor;
  final Position position, namePosition;
  final List<Expr> parameters, patterns;
  final Map<String, bool> parameterNames = {};
  final Statement? body;
  int count = 0, calls = 0, active = 0, depth = 0;
  bool inside = false;
  Item(
    this.kind,
    this.position, {
    this.name = '',
    this.flavor = '',
    this.namePosition = const Position(0, 0),
    this.parameters = const [],
    this.patterns = const [],
    this.body,
  });
}

bool lvalue(Expr expression) =>
    {'name', 'array', 'field'}.contains(expression.kind);

class Parser {
  final List<Token> tokens;
  int index = 0, loops = 0;
  bool function = false;
  String phase = '';
  Parser(this.tokens);
  Token get peek => tokens[index];
  Token take() => tokens[index++];
  Never fail([Position? position]) =>
      throw SyntaxIssue(position ?? peek.position);
  bool accept(String spelling) {
    if (peek.spelling != spelling) return false;
    index++;
    return true;
  }

  Token expect(String spelling) {
    if (peek.spelling != spelling) fail();
    return take();
  }

  void newlines() {
    while (accept('\n')) {}
  }

  Expr name() {
    if (peek.kind != 'name') fail();
    final token = take();
    return Expr('name', token.position, name: token.spelling);
  }

  List<Item> parse() {
    final items = <Item>[];
    while (peek.kind != 'end') {
      if (accept('\n') || accept(';')) continue;
      final start = peek;
      if (accept('function')) {
        if (peek.kind != 'name' && peek.kind != 'function_name') fail();
        final token = take();
        expect('(');
        final parameters = <Expr>[];
        if (peek.spelling != ')') {
          while (true) {
            final parameter = name();
            parameter.kind = 'parameter';
            parameters.add(parameter);
            if (!accept(',')) break;
            newlines();
          }
        }
        expect(')');
        newlines();
        function = true;
        final body = block();
        function = false;
        items.add(
          Item(
            'function',
            start.position,
            name: token.spelling,
            namePosition: token.position,
            parameters: parameters,
            body: body,
          ),
        );
        continue;
      }
      var flavor = '';
      final patterns = <Expr>[];
      if (start.spelling == 'BEGIN' || start.spelling == 'END') {
        flavor = take().spelling;
      } else if (start.spelling == '{') {
        flavor = 'all';
      } else {
        patterns.add(expression());
        if (accept(',')) {
          newlines();
          patterns.add(expression());
        }
        flavor = patterns.length == 2 ? 'range' : 'pattern';
      }
      phase = flavor;
      Statement? action;
      if ({'BEGIN', 'END', 'all'}.contains(flavor) || peek.spelling == '{') {
        action = block();
      } else if (peek.spelling != '\n' &&
          peek.spelling != ';' &&
          peek.kind != 'end') {
        fail();
      }
      phase = '';
      items.add(
        Item(
          'rule',
          start.position,
          flavor: flavor,
          patterns: patterns,
          body: action,
        ),
      );
    }
    return items;
  }

  Statement block() {
    final opening = expect('{');
    final result = Statement('block', opening.position);
    while (peek.spelling != '}') {
      if (accept('\n') || accept(';')) continue;
      result.statements.add(statement());
    }
    expect('}');
    return result;
  }

  Expr condition() {
    expect('(');
    final value = expression();
    expect(')');
    return value;
  }

  Statement loopBody() {
    newlines();
    loops++;
    final result = statement();
    loops--;
    return result;
  }

  void terminator() {
    if (accept(';') || accept('\n')) return;
    if (peek.spelling != '}') fail();
  }

  Statement statement() {
    final token = peek;
    final kind = peek.spelling;
    if (kind == '{') return block();
    if (accept(';')) return Statement('empty', token.position);
    final result = Statement(kind, token.position);
    switch (kind) {
      case 'if':
        take();
        result.exprs = [condition()];
        newlines();
        result.body = statement();
        newlines();
        if (accept('else')) {
          newlines();
          result.otherwise = statement();
        }
        return result;
      case 'while':
        take();
        result.exprs = [condition()];
        result.body = loopBody();
        return result;
      case 'do':
        take();
        result.body = loopBody();
        newlines();
        expect('while');
        result.exprs = [condition()];
        terminator();
        return result;
      case 'for':
        take();
        expect('(');
        if (index + 3 < tokens.length &&
            tokens[index].kind == 'name' &&
            tokens[index + 1].spelling == 'in' &&
            tokens[index + 2].kind == 'name' &&
            tokens[index + 3].spelling == ')') {
          result.kind = 'for_in';
          result.variable = name();
          expect('in');
          result.array = name();
          expect(')');
          result.body = loopBody();
          return result;
        }
        result.exprs = List.filled(3, null);
        if (peek.spelling != ';') result.exprs[0] = expression();
        expect(';');
        newlines();
        if (peek.spelling != ';') result.exprs[1] = expression();
        expect(';');
        newlines();
        if (peek.spelling != ')') result.exprs[2] = expression();
        expect(')');
        result.body = loopBody();
        return result;
      case 'print':
      case 'printf':
        take();
        output(result);
      case 'delete':
        take();
        result.array = name();
        result.wholeDelete = true;
        if (accept('[')) {
          result.wholeDelete = false;
          result.exprs = expressionList();
          expect(']');
        }
      case 'next':
      case 'break':
      case 'continue':
      case 'exit':
      case 'return':
        take();
        if (kind == 'next' &&
                !function &&
                (phase == 'BEGIN' || phase == 'END') ||
            kind == 'return' && !function ||
            (kind == 'break' || kind == 'continue') && loops == 0)
          fail(token.position);
        if ((kind == 'exit' || kind == 'return') &&
            !{';', '\n', '}'}.contains(peek.spelling))
          result.exprs = [expression()];
      default:
        result.kind = 'expression';
        result.exprs = [expression()];
    }
    terminator();
    return result;
  }

  bool parenthesizedOutput() {
    if (peek.spelling != '(') return false;
    var depth = 0;
    for (var i = index; i < tokens.length; i++) {
      if (tokens[i].spelling == '(') depth++;
      if (tokens[i].spelling == ')') {
        depth--;
        if (depth == 0) {
          if (i + 1 == tokens.length) return false;
          final next = tokens[i + 1];
          return next.kind == 'end' ||
              {';', '\n', '}', '>', '>>'}.contains(next.spelling);
        }
      }
    }
    return false;
  }

  void output(Statement result) {
    if (parenthesizedOutput()) {
      expect('(');
      result.exprs = expressionList();
      expect(')');
    } else if (!{';', '\n', '}', '>', '>>'}.contains(peek.spelling)) {
      result.exprs = expressionList(false);
    }
    if (result.kind == 'printf' && result.exprs.isEmpty) fail();
    if (peek.spelling == '>' || peek.spelling == '>>') {
      final redirect = take();
      result.redirectMode = redirect.spelling;
      result.redirectPosition = redirect.position;
      result.redirect = concatenation();
    }
  }

  List<Expr> expressionList([bool greater = true]) {
    final result = [expression(greater)];
    while (accept(',')) {
      newlines();
      result.add(expression(greater));
    }
    return result;
  }

  Expr expression([bool greater = true]) {
    final left = conditional(greater);
    if (lvalue(left) && wordIn('= += -= *= /= %= ^=', peek.spelling)) {
      final op = take();
      return Expr(
        'assignment',
        op.position,
        op: op.spelling,
        left: left,
        right: expression(greater),
      );
    }
    return left;
  }

  Expr conditional(bool greater) {
    final left = logical(0, greater);
    if (!accept('?')) return left;
    final position = tokens[index - 1].position;
    final first = conditional(greater);
    expect(':');
    return Expr(
      'conditional',
      position,
      left: left,
      right: first,
      third: conditional(greater),
    );
  }

  Expr binary(Token op, Expr left, Expr right) =>
      Expr('binary', op.position, op: op.spelling, left: left, right: right);
  Expr logical(int level, bool greater) {
    if (level == 2) return membership(greater);
    final op = level == 0 ? '||' : '&&';
    var left = logical(level + 1, greater);
    while (peek.spelling == op) {
      final token = take();
      newlines();
      left = binary(token, left, logical(level + 1, greater));
    }
    return left;
  }

  Expr membership(bool greater) {
    var left = comparison(greater);
    while (peek.spelling == 'in') {
      final op = take();
      final array = name();
      left = Expr('membership', op.position, args: [left], right: array);
    }
    return left;
  }

  Expr comparison(bool greater) {
    var left = concatenation();
    while (wordIn('< <= == != >= >', peek.spelling) &&
        (greater || peek.spelling != '>')) {
      final op = take();
      left = binary(op, left, concatenation());
    }
    return left;
  }

  Expr concatenation() {
    var left = additive();
    while (wordIn('number string name function_name builtin', peek.kind) ||
        wordIn('\$ ( ++ --', peek.spelling)) {
      final op = Token('symbol', 'concat', peek.position);
      left = binary(op, left, additive());
    }
    return left;
  }

  Expr additive() {
    var left = multiplicative();
    while (peek.spelling == '+' || peek.spelling == '-') {
      final op = take();
      left = binary(op, left, multiplicative());
    }
    return left;
  }

  Expr multiplicative() {
    var left = unary();
    while (wordIn('* / %', peek.spelling)) {
      final op = take();
      left = binary(op, left, unary());
    }
    return left;
  }

  Expr unary() {
    if (wordIn('! - +', peek.spelling)) {
      final op = take();
      return Expr('unary', op.position, op: op.spelling, left: unary());
    }
    var left = postfix();
    if (peek.spelling == '^') {
      final op = take();
      left = binary(op, left, unary());
    }
    return left;
  }

  Expr prefix() {
    final op = take();
    return Expr(
      'increment',
      op.position,
      op: op.spelling,
      prefix: true,
      left: location(),
    );
  }

  Expr postfix() {
    if (peek.spelling == '++' || peek.spelling == '--') return prefix();
    final left = atom();
    if (lvalue(left) && (peek.spelling == '++' || peek.spelling == '--')) {
      final op = take();
      return Expr('increment', op.position, op: op.spelling, left: left);
    }
    return left;
  }

  Expr location() {
    if (peek.kind == 'name') {
      final node = name();
      if (!accept('[')) return node;
      final args = expressionList();
      expect(']');
      return Expr('array', node.position, name: node.name, args: args);
    }
    if (accept(r'$')) {
      final position = tokens[index - 1].position;
      final field = peek.spelling == '++' || peek.spelling == '--'
          ? prefix()
          : atom();
      return Expr('field', position, left: field);
    }
    fail();
  }

  Expr atom() {
    final token = peek;
    if (token.kind == 'number' || token.kind == 'string') {
      take();
      return Expr(
        token.kind,
        token.position,
        value: token.kind == 'number'
            ? numeric(token.number)
            : stringValue(token.text),
      );
    }
    if (token.kind == 'name' || token.spelling == r'$') return location();
    if (accept('(')) {
      final args = expressionList();
      expect(')');
      if (args.length == 1)
        return Expr('paren', token.position, left: args.first);
      expect('in');
      return Expr('membership', token.position, args: args, right: name());
    }
    if (token.kind == 'function_name' || token.kind == 'builtin') {
      take();
      var args = <Expr>[];
      if (accept('(')) {
        if (peek.spelling != ')') args = expressionList();
        expect(')');
      } else if (token.kind == 'function_name' || token.spelling != 'length') {
        fail();
      }
      final kind = token.kind == 'builtin' ? 'builtin' : 'call';
      if (kind == 'builtin') {
        final count = args.length;
        final valid = switch (token.spelling) {
          'length' => count <= 1,
          'substr' || 'split' => count == 2 || count == 3,
          'index' => count == 2,
          'sprintf' => count >= 1,
          _ => count == 1,
        };
        if (!valid || token.spelling == 'split' && args[1].kind != 'name')
          fail(token.position);
      }
      return Expr(kind, token.position, name: token.spelling, args: args);
    }
    if (accept('getline')) {
      final target = peek.kind == 'name' || peek.spelling == r'$'
          ? location()
          : null;
      final filename = accept('<') ? atom() : null;
      return Expr('getline', token.position, left: target, right: filename);
    }
    fail();
  }
}
