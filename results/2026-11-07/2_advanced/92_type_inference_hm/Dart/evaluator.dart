part of 'main.dart';

class Value {
  final String kind, text, builtin;
  final int integer;
  final bool boolean;
  final List<Value> items;
  final Token? parameter;
  final Expr? body;
  final ValueEnv? env;
  Value(
    this.kind, {
    this.text = '',
    this.builtin = '',
    this.integer = 0,
    this.boolean = false,
    List<Value>? items,
    this.parameter,
    this.body,
    this.env,
  }) : items = items ?? [];
}

typedef ValueEnv = Map<String, Value>;

class RuntimeError implements Exception {
  final Position position;
  final String message;
  RuntimeError(this.position, this.message);
}

Value intValue(int v) => Value('integer', integer: v);
Value boolValue(bool v) => Value('boolean', boolean: v);
Value stringValue(String v) => Value('string', text: v);
Value checked(int v, Position p) {
  if (v < -2147483648 || v > 2147483647)
    throw RuntimeError(p, 'integer overflow');
  return intValue(v);
}

int compareValues(Value a, Value b, Position p) {
  switch (a.kind) {
    case 'integer':
      return a.integer.compareTo(b.integer);
    case 'boolean':
      return a.boolean == b.boolean
          ? 0
          : a.boolean
          ? 1
          : -1;
    case 'string':
      return a.text.compareTo(b.text);
    case 'function':
      throw RuntimeError(p, 'functional value compared');
    case 'pair':
    case 'list':
      for (var j = 0; j < min(a.items.length, b.items.length); j++) {
        final c = compareValues(a.items[j], b.items[j], p);
        if (c != 0) return c;
      }
      return a.items.length.compareTo(b.items.length);
  }
  return 0;
}

bool matchPattern(Expr p, Value v, ValueEnv bindings) {
  switch (p.kind) {
    case 'wildcard':
      return true;
    case 'name':
      bindings[p.value] = v;
      return true;
    case 'integer':
      return p.integer == v.integer;
    case 'string':
      return p.value == v.text;
    case 'boolean':
      return (p.value == 'true') == v.boolean;
    case 'pair':
      return matchPattern(p.children[0], v.items[0], bindings) &&
          matchPattern(p.children[1], v.items[1], bindings);
    case 'list':
      if (p.children.length != v.items.length) return false;
      for (var j = 0; j < p.children.length; j++) {
        if (!matchPattern(p.children[j], v.items[j], bindings)) return false;
      }
      return true;
    case 'cons':
      return v.items.isNotEmpty &&
          matchPattern(p.children[0], v.items.first, bindings) &&
          matchPattern(
            p.children[1],
            Value('list', items: v.items.sublist(1)),
            bindings,
          );
  }
  return false;
}

class Evaluator {
  int calls = 0;
  Value apply(Value f, Value a, Position p) {
    calls++;
    if (f.builtin.isNotEmpty) {
      switch (f.builtin) {
        case 'fst':
          return a.items[0];
        case 'snd':
          return a.items[1];
        case 'not':
          return boolValue(!a.boolean);
        case 'string_of_int':
          return stringValue('${a.integer}');
        case 'failwith':
          throw RuntimeError(p, 'failure ${printValue(a)}');
      }
    }
    final inner = ValueEnv.of(f.env!);
    if (f.parameter!.spelling != '_') inner[f.parameter!.spelling] = a;
    return expression(f.body!, inner);
  }

  Value expression(Expr e, ValueEnv env) {
    final c = e.children;
    switch (e.kind) {
      case 'integer':
        {
          return intValue(e.integer);
        }
      case 'boolean':
        {
          return boolValue(e.value == 'true');
        }
      case 'string':
        {
          return stringValue(e.value);
        }
      case 'name':
        {
          return env[e.value]!;
        }
      case 'fun':
        {
          return Value('function', parameter: e.token, body: c.first, env: env);
        }
      case 'apply':
        {
          final function = expression(c[0], env),
              argument = expression(c[1], env);
          return apply(function, argument, e.position);
        }
      case 'negate':
        {
          final value = expression(c.first, env);
          return checked(-value.integer, e.token!.position);
        }
      case 'if':
        {
          final condition = expression(c[0], env);
          return expression(c[condition.boolean ? 1 : 2], env);
        }
      case 'pair':
      case 'list':
        return Value(
          e.kind,
          items: [for (final child in c) expression(child, env)],
        );
      case 'let':
        {
          final (inner, _) = group(e.group!, env);
          return expression(c.first, inner);
        }
      case 'match':
        {
          final value = expression(c.first, env);
          for (final arm in e.arms) {
            final bindings = ValueEnv();
            if (matchPattern(arm.pattern, value, bindings))
              return expression(arm.body, {...env, ...bindings});
          }
          throw RuntimeError(e.position, 'match failure');
        }
      case 'binary':
        {
          final left = expression(c[0], env), op = e.token!.spelling;
          if (op == '&&' && !left.boolean) return boolValue(false);
          if (op == '||' && left.boolean) return boolValue(true);
          final right = expression(c[1], env), p = e.token!.position;
          switch (op) {
            case '&&':
            case '||':
              return right;
            case '+':
              return checked(left.integer + right.integer, p);
            case '-':
              return checked(left.integer - right.integer, p);
            case '*':
              return checked(left.integer * right.integer, p);
            case '/':
            case 'mod':
              if (right.integer == 0) throw RuntimeError(p, 'division by zero');
              final quotient = left.integer ~/ right.integer;
              return op == '/'
                  ? checked(quotient, p)
                  : intValue(left.integer - right.integer * quotient);
            case '^':
              return stringValue(left.text + right.text);
            case '::':
              return Value('list', items: [left, ...right.items]);
            default:
              final comparison = compareValues(left, right, p);
              return boolValue(switch (op) {
                '=' => comparison == 0,
                '<>' => comparison != 0,
                '<' => comparison < 0,
                '>' => comparison > 0,
                '<=' => comparison <= 0,
                _ => comparison >= 0,
              });
          }
        }
    }
    throw StateError('unknown expression');
  }

  (ValueEnv, List<Value>) group(Group g, ValueEnv env) {
    final inner = ValueEnv.of(env), values = <Value>[];
    if (g.rec == null) {
      for (final binding in g.bindings) {
        values.add(expression(binding.expression, env));
      }
      for (var j = 0; j < g.bindings.length; j++) {
        inner[g.bindings[j].name.spelling] = values[j];
      }
    } else {
      for (final binding in g.bindings) {
        final e = binding.expression,
            value = Value(
              'function',
              parameter: e.token,
              body: e.children.first,
              env: inner,
            );
        values.add(value);
        inner[binding.name.spelling] = value;
      }
    }
    return (inner, values);
  }
}
