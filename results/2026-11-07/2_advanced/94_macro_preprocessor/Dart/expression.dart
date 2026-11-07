part of 'main.dart';

class ExpressionError implements Exception {
  final String message;
  ExpressionError(this.message);
}

class ConditionExpr {
  final String kind, op, name;
  final int value;
  final List<ConditionExpr> children;
  ConditionExpr(
    this.kind, {
    this.op = '',
    this.name = '',
    this.value = 0,
    List<ConditionExpr>? children,
  }) : children = children ?? [];
}

final hexPattern = RegExp(r'^0[xX][0-9a-fA-F]+$'),
    octalPattern = RegExp(r'^0[0-7]*$'),
    decimalPattern = RegExp(r'^[1-9][0-9]*$');
Never expressionError(String message) => throw ExpressionError(message);
int integerConstant(String spelling) {
  var value = spelling;
  for (final suffix in ['ll', 'LL', 'l', 'L']) {
    if (value.length > suffix.length && value.endsWith(suffix)) {
      value = value.substring(0, value.length - suffix.length);
      break;
    }
  }
  if (hexPattern.hasMatch(value))
    return int.parse(value.substring(2), radix: 16);
  if (octalPattern.hasMatch(value)) return int.parse(value, radix: 8);
  if (decimalPattern.hasMatch(value)) return int.parse(value);
  expressionError('invalid integer constant "$spelling"');
}

int characterConstant(String spelling) {
  final body = spelling.substring(1, spelling.length - 1);
  if (body.length == 1 && body != "'" && body != '\\')
    return body.codeUnitAt(0);
  if (body.length == 2 && body[0] == '\\') {
    final value = {
      'n': 10,
      't': 9,
      '\\': 92,
      "'": 39,
      '"': 34,
      '0': 0,
    }[body[1]];
    if (value != null) return value;
  }
  expressionError('invalid character constant $spelling');
}

int conditionPrecedence(String op) => switch (op) {
  '||' => 1,
  '&&' => 2,
  '|' => 3,
  '^' => 4,
  '&' => 5,
  '==' || '!=' => 6,
  '<' || '>' || '<=' || '>=' => 7,
  '<<' || '>>' => 8,
  '+' || '-' => 9,
  '*' || '/' || '%' => 10,
  _ => 0,
};

class ExpressionParser {
  final List<Token> tokens;
  int index = 0;
  ExpressionParser(this.tokens);
  String peek() => index == tokens.length ? '' : tokens[index].spelling;
  ConditionExpr expression() {
    final first = binary(1);
    if (peek() == '?') {
      index++;
      final second = expression();
      if (peek() != ':') expressionError("'?' without following ':'");
      index++;
      final third = expression();
      return ConditionExpr('conditional', children: [first, second, third]);
    }
    return first;
  }

  ConditionExpr binary(int minimum) {
    var left = unary();
    while (true) {
      final level = conditionPrecedence(peek());
      if (level == 0 || level < minimum) break;
      final op = peek();
      index++;
      final right = binary(level + 1);
      left = ConditionExpr('binary', op: op, children: [left, right]);
    }
    return left;
  }

  ConditionExpr unary() {
    if (wordIn('+ - ! ~', peek())) {
      final op = peek();
      index++;
      return ConditionExpr('unary', op: op, children: [unary()]);
    }
    return primary();
  }

  ConditionExpr primary() {
    if (index == tokens.length)
      expressionError('expected value at end of expression');
    final token = tokens[index++];
    if (token.kind == 'number' || token.kind == 'character')
      return ConditionExpr(
        'constant',
        value: token.kind == 'number'
            ? integerConstant(token.spelling)
            : characterConstant(token.spelling),
      );
    if (token.kind == 'identifier')
      return ConditionExpr('identifier', name: token.spelling);
    if (token.spelling == '(') {
      final e = expression();
      if (peek() != ')') expressionError("missing ')' in expression");
      index++;
      return e;
    }
    expressionError('expected value before "${token.spelling}"');
  }
}

ConditionExpr parseCondition(List<Token> tokens, String directive) {
  if (tokens.isEmpty) expressionError('#$directive with no expression');
  final p = ExpressionParser(tokens), tree = p.expression();
  if (p.index < tokens.length)
    expressionError('missing binary operator before "${p.peek()}"');
  return tree;
}

int evaluateCondition(ConditionExpr e, void Function(String) warning) {
  switch (e.kind) {
    case 'constant':
      return e.value;
    case 'identifier':
      warning('identifier "${e.name}" evaluates to 0');
      return 0;
    case 'unary':
      final a = evaluateCondition(e.children.first, warning);
      return switch (e.op) {
        '+' => a,
        '-' => -a,
        '!' => a == 0 ? 1 : 0,
        _ => -a - 1,
      };
    case 'conditional':
      return evaluateCondition(
        e.children[evaluateCondition(e.children[0], warning) != 0 ? 1 : 2],
        warning,
      );
    case 'binary':
      {
        final a = evaluateCondition(e.children[0], warning);
        if (e.op == '&&' && a == 0) return 0;
        if (e.op == '||' && a != 0) return 1;
        final b = evaluateCondition(e.children[1], warning);
        switch (e.op) {
          case '+':
            return a + b;
          case '-':
            return a - b;
          case '*':
            return a * b;
          case '/':
          case '%':
            if (b == 0) expressionError('division by zero in #if');
            final q = a ~/ b;
            return e.op == '/' ? q : a - b * q;
          case '<<':
            return a << b;
          case '>>':
            return a >> b;
          case '&':
            return a & b;
          case '|':
            return a | b;
          case '^':
            return a ^ b;
          default:
            return (switch (e.op) {
                  '==' => a == b,
                  '!=' => a != b,
                  '<' => a < b,
                  '<=' => a <= b,
                  '>' => a > b,
                  '>=' => a >= b,
                  _ => b != 0,
                })
                ? 1
                : 0;
        }
      }
  }
  return 0;
}
