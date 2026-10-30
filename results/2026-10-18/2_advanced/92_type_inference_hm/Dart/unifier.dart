part of 'main.dart';

class Type {
  final String kind;
  final List<Type> children;
  Type? binding;
  Type(this.kind, [List<Type>? children]) : children = children ?? [];
}

class Scheme {
  final Type value;
  final Set<Type> quantified;
  Scheme(this.value, [Set<Type>? quantified]) : quantified = quantified ?? {};
}

typedef TypeEnv = Map<String, Scheme>;
final intType = Type('int'),
    boolType = Type('bool'),
    stringType = Type('string');
Type fresh() => Type('var');
Type resolve(Type t) {
  final binding = t.binding;
  if (t.kind == 'var' && binding != null) {
    t.binding = resolve(binding);
    return t.binding!;
  }
  return t;
}

bool occurs(Type variable, Type value) {
  final t = resolve(value);
  return identical(t, variable) ||
      t.children.any((child) => occurs(variable, child));
}

class UnificationFailure {
  final Type expected, found;
  final bool infinite, nested;
  UnificationFailure(this.expected, this.found, this.infinite, this.nested);
}

UnificationFailure? unify(Type expected, Type found, [bool nested = false]) {
  expected = resolve(expected);
  found = resolve(found);
  if (identical(expected, found)) return null;
  if (expected.kind == 'var') {
    if (occurs(expected, found))
      return UnificationFailure(expected, found, true, nested);
    expected.binding = found;
    return null;
  }
  if (found.kind == 'var') {
    if (occurs(found, expected))
      return UnificationFailure(expected, found, true, nested);
    found.binding = expected;
    return null;
  }
  if (expected.kind != found.kind)
    return UnificationFailure(expected, found, false, nested);
  for (var i = 0; i < expected.children.length; i++) {
    final failure = unify(expected.children[i], found.children[i], true);
    if (failure != null) return failure;
  }
  return null;
}

Set<Type> freeVariables(Type t) {
  final out = <Type>{};
  void walk(Type value) {
    value = resolve(value);
    if (value.kind == 'var') {
      out.add(value);
      return;
    }
    for (final child in value.children) {
      walk(child);
    }
  }

  walk(t);
  return out;
}

Scheme generalize(Type t, TypeEnv env) {
  final quantified = freeVariables(t);
  for (final scheme in env.values) {
    quantified.removeAll(
      freeVariables(scheme.value).difference(scheme.quantified),
    );
  }
  return Scheme(t, quantified);
}

Type instantiate(Scheme s) {
  final replacements = <Type, Type>{};
  Type copy(Type t) {
    t = resolve(t);
    if (t.kind == 'var')
      return s.quantified.contains(t) ? replacements.putIfAbsent(t, fresh) : t;
    return Type(t.kind, [for (final child in t.children) copy(child)]);
  }

  return copy(s.value);
}
