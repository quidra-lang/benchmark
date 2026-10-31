part of 'main.dart';

class TypeError implements Exception {
  final String kind, name;
  final Position position;
  final Type? expected, found;
  final UnificationFailure? failure;
  final List<String> candidates;
  TypeError(
    this.kind,
    this.position, {
    this.name = '',
    this.expected,
    this.found,
    this.failure,
    List<String>? candidates,
  }) : candidates = candidates ?? [];
}

(Type, Type, Type) operatorTypes(String op) {
  if (wordIn('+ - * / mod', op)) return (intType, intType, intType);
  if (op == '^') return (stringType, stringType, stringType);
  if (op == '&&' || op == '||') return (boolType, boolType, boolType);
  final variable = fresh();
  if (op == '::') {
    final sequence = Type('list', [variable]);
    return (variable, sequence, sequence);
  }
  return (variable, variable, boolType);
}

class Inferencer {
  final List<Binding> locals = [];
  void check(Type expected, Type found, Position p) {
    final failure = unify(expected, found);
    if (failure != null)
      throw TypeError(
        'check',
        p,
        expected: expected,
        found: found,
        failure: failure,
      );
  }

  Type expression(Expr e, TypeEnv env) {
    late Type result;
    final c = e.children;
    switch (e.kind) {
      case 'integer':
        {
          result = intType;
          break;
        }
      case 'string':
        {
          result = stringType;
          break;
        }
      case 'boolean':
        {
          result = boolType;
          break;
        }
      case 'name':
        {
          final scheme = env[e.value];
          if (scheme == null)
            throw TypeError(
              'unbound',
              e.position,
              name: e.value,
              candidates: env.keys.toList(),
            );
          result = instantiate(scheme);
          break;
        }
      case 'fun':
        {
          final argument = fresh(), inner = TypeEnv.of(env);
          if (e.token!.spelling != '_')
            inner[e.token!.spelling] = Scheme(argument);
          result = Type('function', [argument, expression(c.first, inner)]);
          break;
        }
      case 'apply':
        {
          final function = resolve(expression(c[0], env));
          late Type argument;
          if (function.kind == 'var') {
            argument = fresh();
            result = fresh();
            function.binding = Type('function', [argument, result]);
          } else if (function.kind == 'function') {
            argument = function.children[0];
            result = function.children[1];
          } else {
            throw TypeError('not_function', c[0].position, found: function);
          }
          final found = expression(c[1], env);
          check(argument, found, c[1].position);
          break;
        }
      case 'binary':
        {
          final (first, second, r) = operatorTypes(e.token!.spelling);
          final left = expression(c[0], env);
          check(first, left, c[0].position);
          final right = expression(c[1], env);
          check(second, right, c[1].position);
          result = r;
          break;
        }
      case 'negate':
        {
          final found = expression(c.first, env);
          check(intType, found, c.first.position);
          result = intType;
          break;
        }
      case 'if':
        {
          final condition = expression(c[0], env);
          check(boolType, condition, c[0].position);
          result = expression(c[1], env);
          final other = expression(c[2], env);
          check(result, other, c[2].position);
          break;
        }
      case 'pair':
        {
          final first = expression(c[0], env), second = expression(c[1], env);
          result = Type('pair', [first, second]);
          break;
        }
      case 'list':
        {
          final element = fresh();
          for (final child in c) {
            final found = expression(child, env);
            check(element, found, child.position);
          }
          result = Type('list', [element]);
          break;
        }
      case 'match':
        {
          final matched = expression(c.first, env);
          result = fresh();
          for (final arm in e.arms) {
            final bindings = <String, Type>{},
                patternType = pattern(arm.pattern, bindings);
            check(matched, patternType, arm.pattern.position);
            final inner = TypeEnv.of(env);
            for (final entry in bindings.entries) {
              inner[entry.key] = Scheme(entry.value);
            }
            final found = expression(arm.body, inner);
            check(result, found, arm.body.position);
          }
          break;
        }
      case 'let':
        {
          final inner = group(e.group!, env, true);
          result = expression(c.first, inner);
          break;
        }
    }
    e.inferred = result;
    return result;
  }

  Type pattern(Expr p, Map<String, Type> bindings) {
    final c = p.children;
    switch (p.kind) {
      case 'wildcard':
        return fresh();
      case 'name':
        if (bindings.containsKey(p.value))
          throw TypeError('duplicate_pattern', p.position, name: p.value);
        final t = fresh();
        bindings[p.value] = t;
        return t;
      case 'integer':
        return intType;
      case 'boolean':
        return boolType;
      case 'string':
        return stringType;
      case 'pair':
        final first = pattern(c[0], bindings), second = pattern(c[1], bindings);
        return Type('pair', [first, second]);
    }
    final element = fresh(), sequence = Type('list', [element]);
    if (p.kind == 'cons') {
      final first = pattern(c[0], bindings);
      check(element, first, c[0].position);
      final second = pattern(c[1], bindings);
      check(sequence, second, c[1].position);
    } else {
      for (final child in c) {
        final found = pattern(child, bindings);
        check(element, found, child.position);
      }
    }
    return sequence;
  }

  TypeEnv group(Group g, TypeEnv env, bool local) {
    final seen = <String>{};
    for (final binding in g.bindings) {
      final name = binding.name.spelling;
      if (!seen.add(name))
        throw TypeError('duplicate_let', binding.name.position, name: name);
      if (g.rec != null && binding.expression.kind != 'fun')
        throw TypeError(
          'recursive_function',
          binding.name.position,
          name: name,
        );
    }
    final types = <Type>[];
    if (g.rec == null) {
      for (final binding in g.bindings) {
        types.add(expression(binding.expression, env));
      }
    } else {
      final recursive = TypeEnv.of(env);
      for (final binding in g.bindings) {
        final t = fresh();
        types.add(t);
        recursive[binding.name.spelling] = Scheme(t);
      }
      for (var j = 0; j < g.bindings.length; j++) {
        final binding = g.bindings[j],
            found = expression(binding.expression, recursive);
        check(types[j], found, binding.name.position);
      }
    }
    final result = TypeEnv.of(env);
    for (var j = 0; j < g.bindings.length; j++) {
      final binding = g.bindings[j], scheme = generalize(types[j], env);
      binding.scheme = scheme;
      result[binding.name.spelling] = scheme;
    }
    if (local) locals.addAll(g.bindings);
    return result;
  }
}
