import 'dart:io';
import 'dart:math';
part 'lexer.dart';
part 'parser.dart';
part 'unifier.dart';
part 'inference.dart';
part 'evaluator.dart';

class TypePrinter {
  final Map<Type, String> names = {};
  final Set<Type> quantified;
  final bool local;
  TypePrinter({Set<Type>? quantified, this.local = false})
    : quantified = quantified ?? {};
  String print(Type t) {
    t = resolve(t);
    if (t.kind == 'var') {
      final known = names[t];
      if (known != null) return known;
      final index = names.length,
          prefix = local && !quantified.contains(t) ? "'_" : "'",
          name =
              '$prefix${String.fromCharCode(97 + index % 26)}${index >= 26 ? index ~/ 26 : ''}';
      names[t] = name;
      return name;
    }
    if (wordIn('int bool string', t.kind)) return t.kind;
    final first = resolve(t.children[0]);
    var left = print(first);
    if (t.kind == 'list') {
      if (first.kind == 'pair' || first.kind == 'function') left = '($left)';
      return '$left list';
    }
    final second = resolve(t.children[1]);
    var right = print(second);
    if (t.kind == 'pair') {
      if (first.kind == 'pair' || first.kind == 'function') left = '($left)';
      if (second.kind == 'pair' || second.kind == 'function')
        right = '($right)';
      return '$left * $right';
    }
    if (first.kind == 'function') left = '($left)';
    return '$left -> $right';
  }
}

Type signatureType(Expr e, Map<String, Type> variables) =>
    e.kind == 'type_variable'
    ? variables.putIfAbsent(e.value, fresh)
    : Type(e.kind, [
        for (final child in e.children) signatureType(child, variables),
      ]);
bool identicalTypes(Type a, Type b) {
  a = resolve(a);
  b = resolve(b);
  if (a.kind == 'var' || b.kind == 'var') return identical(a, b);
  if (a.kind != b.kind) return false;
  for (var j = 0; j < a.children.length; j++) {
    if (!identicalTypes(a.children[j], b.children[j])) return false;
  }
  return true;
}

bool signatureMatches(
  Type inferred,
  Type declared,
  Map<Type, Type> assignments,
) {
  inferred = resolve(inferred);
  declared = resolve(declared);
  if (inferred.kind == 'var') {
    final previous = assignments[inferred];
    if (previous != null) return identicalTypes(previous, declared);
    assignments[inferred] = declared;
    return true;
  }
  if (declared.kind == 'var' || inferred.kind != declared.kind) return false;
  for (var j = 0; j < inferred.children.length; j++) {
    if (!signatureMatches(
      inferred.children[j],
      declared.children[j],
      assignments,
    ))
      return false;
  }
  return true;
}

void checkSignatures(Group g, List<Item?> signatures) {
  for (var j = 0; j < g.bindings.length; j++) {
    final binding = g.bindings[j], signature = signatures[j];
    if (signature == null) continue;
    final declared = signatureType(signature.declared!, {}),
        inferred = binding.scheme!.value;
    if (!signatureMatches(inferred, declared, {}))
      throw TypeError(
        'signature',
        binding.name.position,
        name: binding.name.spelling,
        expected: inferred,
        found: declared,
      );
    binding.scheme = Scheme(declared, freeVariables(declared));
  }
}

int editDistance(String a, String b) {
  var previous = List.generate(b.length + 1, (j) => j);
  for (var i = 0; i < a.length; i++) {
    final current = List.filled(b.length + 1, 0);
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      current[j + 1] = min(
        min(current[j] + 1, previous[j + 1] + 1),
        previous[j] + (a[i] == b[j] ? 0 : 1),
      );
    }
    previous = current;
  }
  return previous.last;
}

String typeErrorMessage(TypeError error) {
  final printer = TypePrinter();
  switch (error.kind) {
    case 'unbound':
      {
        var message = "unbound variable '${error.name}'",
            best = '',
            bestDistance = 3;
        for (final candidate in error.candidates) {
          final distance = editDistance(error.name, candidate);
          if (distance <= 2 &&
              distance < error.name.length &&
              (distance < bestDistance ||
                  distance == bestDistance &&
                      (best.isEmpty || candidate.compareTo(best) < 0))) {
            best = candidate;
            bestDistance = distance;
          }
        }
        if (best.isNotEmpty) message += " (did you mean '$best'?)";
        return message;
      }
    case 'not_function':
      return 'expected a function but found ${printer.print(error.found!)}';
    case 'duplicate_pattern':
      return "variable '${error.name}' is bound twice in this pattern";
    case 'duplicate_let':
      return "variable '${error.name}' is bound twice in this let";
    case 'recursive_function':
      return "'${error.name}' in let rec must be a function";
    case 'signature':
      return "'${error.name}' has type ${printer.print(error.expected!)} but its signature is ${printer.print(error.found!)}";
    case 'check':
      {
        var message =
            'expected ${printer.print(error.expected!)} but found ${printer.print(error.found!)}';
        final failure = error.failure!;
        if (failure.infinite) {
          final variable = failure.expected.kind == 'var'
                  ? failure.expected
                  : failure.found,
              value = failure.expected.kind == 'var'
                  ? failure.found
                  : failure.expected;
          message +=
              ' (infinite type ${printer.print(variable)} = ${printer.print(value)})';
        } else if (failure.nested) {
          message +=
              ' (${printer.print(failure.expected)} vs ${printer.print(failure.found)})';
        }
        return message;
      }
  }
  return '';
}

(TypeEnv, ValueEnv) builtins() {
  final types = TypeEnv(), values = ValueEnv();
  for (final name in ['fst', 'snd']) {
    final a = fresh(), b = fresh(), result = name == 'snd' ? b : a;
    types[name] = Scheme(
      Type('function', [
        Type('pair', [a, b]),
        result,
      ]),
      {a, b},
    );
  }
  types['not'] = Scheme(Type('function', [boolType, boolType]));
  types['string_of_int'] = Scheme(Type('function', [intType, stringType]));
  final result = fresh();
  types['failwith'] = Scheme(Type('function', [stringType, result]), {result});
  for (final name in types.keys) {
    values[name] = Value('function', builtin: name);
  }
  return (types, values);
}

String quoteString(String value) {
  final out = StringBuffer('"');
  for (var j = 0; j < value.length; j++) {
    switch (value[j]) {
      case '\\':
        out.write(r'\\');
        break;
      case '"':
        out.write(r'\"');
        break;
      case '\n':
        out.write(r'\n');
        break;
      case '\t':
        out.write(r'\t');
        break;
      default:
        out.write(value[j]);
        break;
    }
  }
  out.write('"');
  return out.toString();
}

String printValue(Value v) => switch (v.kind) {
  'integer' => '${v.integer}',
  'boolean' => v.boolean ? 'true' : 'false',
  'string' => quoteString(v.text),
  'pair' => '(${printValue(v.items[0])}, ${printValue(v.items[1])})',
  'list' => '[${v.items.map(printValue).join('; ')}]',
  _ => '<fun>',
};
String declaredType(Expr e) {
  if (e.kind == 'type_variable') return e.value;
  if (wordIn('int bool string', e.kind)) return e.kind;
  final first = e.children[0];
  var left = declaredType(first);
  if (e.kind == 'list') {
    if (first.kind == 'pair' || first.kind == 'function') left = '($left)';
    return '$left list';
  }
  final second = e.children[1];
  var right = declaredType(second);
  if (e.kind == 'pair') {
    if (first.kind == 'pair' || first.kind == 'function') left = '($left)';
    if (second.kind == 'pair' || second.kind == 'function') right = '($right)';
    return '$left * $right';
  }
  if (first.kind == 'function') left = '($left)';
  return '$left -> $right';
}

(List<String>, Expr) parameters(Expr e) {
  final names = <String>[];
  while (e.kind == 'fun') {
    names.add(e.token!.spelling);
    e = e.children.first;
  }
  return (names, e);
}

String formatGroup(Group g) {
  final parts = <String>[];
  for (final binding in g.bindings) {
    final (params, body) = parameters(binding.expression);
    parts.add(
      [
        binding.name.spelling,
        ...params,
        '=',
        formatExpression(body, 0),
      ].join(' '),
    );
  }
  return '${g.rec == null ? 'let ' : 'let rec '}${parts.join(' and ')}';
}

bool endsWithMatch(Expr e) => switch (e.kind) {
  'match' => true,
  'let' || 'fun' => endsWithMatch(e.children.first),
  'if' => endsWithMatch(e.children[2]),
  _ => false,
};
String formatPattern(Expr p) {
  switch (p.kind) {
    case 'wildcard':
    case 'name':
    case 'boolean':
      return p.value;
    case 'integer':
      return '${p.integer}';
    case 'string':
      return quoteString(p.value);
    case 'list':
      return '[${p.children.map(formatPattern).join('; ')}]';
    case 'pair':
      return '(${formatPattern(p.children[0])}, ${formatPattern(p.children[1])})';
    case 'cons':
      final left = formatPattern(p.children[0]);
      return '${p.children[0].kind == 'cons' ? '($left)' : left} :: ${formatPattern(p.children[1])}';
  }
  return '';
}

String formatExpression(Expr e, int minimum) {
  var strength = 9, text = '';
  final c = e.children;
  switch (e.kind) {
    case 'integer':
      text = '${e.integer}';
      break;
    case 'boolean':
    case 'name':
      text = e.value;
      break;
    case 'string':
      text = quoteString(e.value);
      break;
    case 'fun':
      {
        strength = 0;
        final (params, body) = parameters(e);
        text = 'fun ${params.join(' ')} -> ${formatExpression(body, 0)}';
        break;
      }
    case 'apply':
      strength = 8;
      text = '${formatExpression(c[0], 8)} ${formatExpression(c[1], 9)}';
      break;
    case 'binary':
      {
        final (level, right) = operatorInfo(e.token!.spelling);
        strength = level;
        text =
            '${formatExpression(c[0], right ? level + 1 : level)} ${e.token!.spelling} ${formatExpression(c[1], right ? level : level + 1)}';
        break;
      }
    case 'negate':
      strength = 7;
      text = '-${formatExpression(c.first, 7)}';
      break;
    case 'if':
      strength = 0;
      text =
          'if ${formatExpression(c[0], 0)} then ${formatExpression(c[1], 0)} else ${formatExpression(c[2], 0)}';
      break;
    case 'pair':
      text = '(${formatExpression(c[0], 0)}, ${formatExpression(c[1], 0)})';
      break;
    case 'list':
      text =
          '[${[for (final child in c) formatExpression(child, 0)].join('; ')}]';
      break;
    case 'let':
      strength = 0;
      text = '${formatGroup(e.group!)} in ${formatExpression(c.first, 0)}';
      break;
    case 'match':
      {
        strength = 0;
        final parts = <String>[];
        for (var j = 0; j < e.arms.length; j++) {
          final arm = e.arms[j];
          var body = formatExpression(arm.body, 0);
          if (j + 1 < e.arms.length && endsWithMatch(arm.body))
            body = '($body)';
          parts.add('${formatPattern(arm.pattern)} -> $body');
        }
        text =
            'match ${formatExpression(c.first, 0)} with ${parts.join(' | ')}';
        break;
      }
  }
  return strength < minimum ? '($text)' : text;
}

String formatItem(Item item) => switch (item.kind) {
  'signature' =>
    'val ${item.name!.spelling} : ${declaredType(item.declared!)};;',
  'declaration' => '${formatGroup(item.group!)};;',
  _ => '${formatExpression(item.expression!, 0)};;',
};

class Cover {
  final String tag;
  final List<Cover?> children;
  Cover(this.tag, [List<Cover?>? children]) : children = children ?? [];
}

Cover? coveragePattern(Expr p) {
  switch (p.kind) {
    case 'name':
    case 'wildcard':
      return null;
    case 'integer':
      return Cover('i:${p.integer}');
    case 'string':
      return Cover('s:${quoteString(p.value)}');
    case 'boolean':
      return Cover('b:${p.value}');
    case 'list':
      var out = Cover('nil');
      for (final child in p.children.reversed) {
        out = Cover('cons', [coveragePattern(child), out]);
      }
      return out;
    default:
      return Cover(p.kind, p.children.map(coveragePattern).toList());
  }
}

List<String> constructors(Type t) => switch (resolve(t).kind) {
  'bool' => ['b:false', 'b:true'],
  'list' => ['nil', 'cons'],
  'pair' => ['pair'],
  _ => [],
};
List<Type> constructorTypes(String tag, Type t) {
  t = resolve(t);
  return tag == 'pair'
      ? t.children
      : tag == 'cons'
      ? [t.children.first, t]
      : [];
}

List<List<Cover?>> specialize(
  List<List<Cover?>> matrix,
  String tag,
  int arity,
) {
  final out = <List<Cover?>>[];
  for (final row in matrix) {
    final head = row.first;
    if (head == null) {
      out.add([...List<Cover?>.filled(arity, null), ...row.skip(1)]);
    } else if (head.tag == tag) {
      out.add([...head.children, ...row.skip(1)]);
    }
  }
  return out;
}

String coverCode(Cover? p) => p == null
    ? '_'
    : '${p.tag.length}:${p.tag}(${p.children.map(coverCode).join()})';
String coverageTypeCode(Type t) {
  t = resolve(t);
  return t.kind == 'var' || t.kind == 'function'
      ? 'opaque'
      : '${t.kind}(${t.children.map(coverageTypeCode).join()})';
}

class Coverage {
  final Map<String, bool> memo = {};
  bool useful(List<List<Cover?>> matrix, List<Cover?> query, List<Type> types) {
    final code =
        '${[for (final row in matrix) '[${row.map(coverCode).join()}]'].join()}?${query.map(coverCode).join()}:${types.map(coverageTypeCode).join()}';
    final known = memo[code];
    if (known != null) return known;
    final value = compute(matrix, query, types);
    memo[code] = value;
    return value;
  }

  bool compute(
    List<List<Cover?>> matrix,
    List<Cover?> query,
    List<Type> types,
  ) {
    if (query.isEmpty) return matrix.isEmpty;
    if (matrix.isEmpty) return true;
    final head = query.first;
    if (head != null) {
      final argumentTypes = constructorTypes(head.tag, types.first);
      return useful(
        specialize(matrix, head.tag, head.children.length),
        [...head.children, ...query.skip(1)],
        [...argumentTypes, ...types.skip(1)],
      );
    }
    final possible = constructors(types.first),
        present = {
          for (final row in matrix)
            if (row.first != null) row.first!.tag,
        };
    if (possible.isNotEmpty && possible.every(present.contains)) {
      for (final tag in possible) {
        final arguments = constructorTypes(tag, types.first);
        if (useful(
          specialize(matrix, tag, arguments.length),
          [...List<Cover?>.filled(arguments.length, null), ...query.skip(1)],
          [...arguments, ...types.skip(1)],
        ))
          return true;
      }
      return false;
    }
    return useful(
      [
        for (final row in matrix)
          if (row.first == null) row.skip(1).toList(),
      ],
      query.skip(1).toList(),
      types.skip(1).toList(),
    );
  }
}

class Symbol {
  final String name;
  final Position position;
  final bool top;
  bool used = false;
  Symbol(this.name, this.position, this.top);
}

class Warning {
  final Position position;
  final int order;
  final String message;
  Warning(this.position, this.order, this.message);
}

class GroupSymbols {
  final Group group;
  final Set<Symbol> targets;
  GroupSymbols(this.group, this.targets);
}

typedef SymbolEnv = Map<String, Symbol?>;

class StaticChecks {
  final List<Symbol> symbols = [];
  final Map<Expr, Symbol?> references = {};
  final List<GroupSymbols> groups = [];
  final List<Warning> warnings = [];
  Symbol symbol(String name, Position position, bool top) {
    final value = Symbol(name, position, top);
    symbols.add(value);
    return value;
  }

  void pattern(Expr p, SymbolEnv env) {
    if (p.kind == 'name') env[p.value] = symbol(p.value, p.position, false);
    for (final child in p.children) {
      pattern(child, env);
    }
  }

  SymbolEnv group(Group g, SymbolEnv env, bool top) {
    final inner = SymbolEnv.of(env), targets = <Symbol>{};
    for (final binding in g.bindings) {
      final s = symbol(binding.name.spelling, binding.name.position, top);
      inner[s.name] = s;
      targets.add(s);
    }
    groups.add(GroupSymbols(g, targets));
    final right = g.rec == null ? env : inner;
    for (final binding in g.bindings) {
      expression(binding.expression, right);
    }
    return inner;
  }

  void expression(Expr e, SymbolEnv env) {
    switch (e.kind) {
      case 'name':
        {
          final s = env[e.value];
          references[e] = s;
          if (s != null) s.used = true;
          return;
        }
      case 'fun':
        {
          final inner = SymbolEnv.of(env);
          if (e.token!.spelling != '_')
            inner[e.token!.spelling] = symbol(
              e.token!.spelling,
              e.token!.position,
              false,
            );
          expression(e.children.first, inner);
          return;
        }
      case 'let':
        {
          final inner = group(e.group!, env, false);
          expression(e.children.first, inner);
          return;
        }
      case 'match':
        {
          expression(e.children.first, env);
          final coverage = Coverage(),
              matrix = <List<Cover?>>[],
              types = [e.children.first.inferred!];
          for (var j = 0; j < e.arms.length; j++) {
            final arm = e.arms[j], query = [coveragePattern(arm.pattern)];
            if (j > 0 && !coverage.useful(matrix, query, types))
              warnings.add(
                Warning(arm.pattern.position, 2, 'this match case is unused'),
              );
            matrix.add(query);
            final inner = SymbolEnv.of(env);
            pattern(arm.pattern, inner);
            expression(arm.body, inner);
          }
          if (coverage.useful(matrix, [null], types))
            warnings.add(
              Warning(e.position, 1, 'this match is not exhaustive'),
            );
          return;
        }
    }
    for (final child in e.children) {
      expression(child, env);
    }
  }

  String classification(Expr e, Set<Symbol> targets) {
    final (_, body) = parameters(e);
    var count = 0, allTail = true;
    void visit(Expr n, bool tail) {
      final c = n.children;
      switch (n.kind) {
        case 'name':
          if (targets.contains(references[n])) {
            count++;
            allTail = false;
          }
          return;
        case 'apply':
          {
            final arguments = <Expr>[];
            var head = n;
            while (head.kind == 'apply') {
              arguments.add(head.children[1]);
              head = head.children[0];
            }
            if (head.kind == 'name' && targets.contains(references[head])) {
              count++;
              if (!tail) allTail = false;
            } else {
              visit(head, false);
            }
            for (final argument in arguments.reversed) {
              visit(argument, false);
            }
            return;
          }
        case 'if':
          visit(c[0], false);
          visit(c[1], tail);
          visit(c[2], tail);
          return;
        case 'match':
          visit(c.first, false);
          for (final arm in n.arms) {
            visit(arm.body, tail);
          }
          return;
        case 'let':
          for (final binding in n.group!.bindings) {
            visit(binding.expression, false);
          }
          visit(c.first, tail);
          return;
        case 'binary':
          if (n.token!.spelling == '&&' || n.token!.spelling == '||') {
            visit(c[0], false);
            visit(c[1], tail);
            return;
          }
          break;
      }
      for (final child in c) {
        visit(child, false);
      }
    }

    visit(body, true);
    return count == 0
        ? ''
        : allTail
        ? 'tail recursive'
        : 'recursive';
  }
}

void walkExpr(Expr e, void Function(Expr) visit) {
  visit(e);
  final g = e.group;
  if (g != null) {
    for (final binding in g.bindings) {
      walkExpr(binding.expression, visit);
    }
  }
  for (final child in e.children) {
    walkExpr(child, visit);
  }
  for (final arm in e.arms) {
    walkExpr(arm.body, visit);
  }
}

int comparePositions(Position a, Position b) =>
    a.line != b.line ? a.line.compareTo(b.line) : a.column.compareTo(b.column);
List<Warning> staticWarnings(Item item, TypeEnv env) {
  final s = StaticChecks(),
      names = <String, Symbol?>{for (final name in env.keys) name: null};
  if (item.kind == 'declaration') {
    s.group(item.group!, names, true);
  } else {
    s.expression(item.expression!, names);
  }
  for (final g in s.groups) {
    final rec = g.group.rec;
    if (rec == null) continue;
    var used = false;
    for (final binding in g.group.bindings) {
      walkExpr(binding.expression, (e) {
        if (g.targets.contains(s.references[e])) used = true;
      });
      binding.classification = s.classification(binding.expression, g.targets);
    }
    if (!used) s.warnings.add(Warning(rec, 3, 'unused rec flag'));
  }
  for (final symbol in s.symbols) {
    if (!symbol.top && !symbol.used && !symbol.name.startsWith('_'))
      s.warnings.add(
        Warning(symbol.position, 4, "unused variable '${symbol.name}'"),
      );
  }
  s.warnings.sort((a, b) {
    final c = comparePositions(a.position, b.position);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return s.warnings;
}

String suffixClassification(Binding b) =>
    b.classification.isEmpty ? '' : ' (${b.classification})';

class Counts {
  int items = 0,
      bindings = 0,
      syntax = 0,
      type = 0,
      runtime = 0,
      warnings = 0,
      calls = 0;
}

class Reports {
  final Map<String, List<String>> sources;
  final Map<String, Counts> stats;
  final List<String> lines = [];
  String current = '';
  Reports(this.sources, this.stats);
  void report(String kind, Position p, String message) {
    final c = stats[current]!;
    switch (kind) {
      case 'syntax error':
        c.syntax++;
        break;
      case 'type error':
        c.type++;
        break;
      case 'runtime error':
        c.runtime++;
        break;
      case 'warning':
        c.warnings++;
        break;
    }
    lines.add('${p.file}:${p.line}:${p.column}: $kind: $message');
    final source = sources[p.file]!;
    if (p.line <= source.length) {
      lines.add('    ${source[p.line - 1]}');
      lines.add('${List.filled(p.column + 3, ' ').join()}^');
    }
  }
}

String syntaxMessage(Token t) => t.kind == 'invalid'
    ? t.value
    : t.kind == 'EOF'
    ? 'unexpected end of file'
    : "unexpected '${t.spelling}'";
void writeLines(String path, List<String> lines) =>
    File('output/$path').writeAsStringSync('${lines.join('\n')}\n');
void main() {
  final filenames = ['prelude.ml', 'program.ml'],
      sources = {
        for (final filename in ['prelude.ml', 'program.ml'])
          filename: File('input/$filename').readAsLinesSync(),
      },
      statistics = {
        for (final filename in ['prelude.ml', 'program.ml']) filename: Counts(),
      },
      reports = Reports(sources, statistics),
      types = <String>[],
      values = <String>[],
      formatted = <String>[];
  var (typeEnv, valueEnv) = builtins();
  for (final filename in filenames) {
    reports.current = filename;
    final stats = statistics[filename]!,
        pending = <String, Item>{},
        parser = Parser(lex(filename, sources[filename]!)),
        evaluator = Evaluator();
    types.add('== $filename ==');
    values.add('== $filename ==');
    formatted.add('(* $filename *)');
    while (parser.peek().kind != 'EOF') {
      stats.items++;
      late Item item;
      try {
        item = parser.item();
      } on SyntaxError catch (error) {
        reports.report(
          'syntax error',
          error.token.position,
          syntaxMessage(error.token),
        );
        parser.recoverItem();
        continue;
      }
      formatted.add(formatItem(item));
      if (item.kind == 'signature') {
        final name = item.name!.spelling, old = pending[name];
        if (old != null)
          reports.report(
            'warning',
            old.name!.position,
            "signature for '$name' is never used",
          );
        pending[name] = item;
        continue;
      }
      final signatures = <Item?>[];
      if (item.kind == 'declaration') {
        for (final binding in item.group!.bindings) {
          signatures.add(pending.remove(binding.name.spelling));
        }
      }
      final inference = Inferencer();
      Type? inferred;
      try {
        if (item.kind == 'declaration') {
          inference.group(item.group!, typeEnv, false);
          checkSignatures(item.group!, signatures);
        } else {
          inferred = inference.expression(item.expression!, typeEnv);
        }
      } on TypeError catch (error) {
        reports.report('type error', error.position, typeErrorMessage(error));
        continue;
      }
      final warnings = staticWarnings(item, typeEnv);
      if (item.kind == 'declaration') {
        for (final binding in item.group!.bindings) {
          types.add(
            '${binding.name.spelling} : ${TypePrinter().print(binding.scheme!.value)}${suffixClassification(binding)}',
          );
        }
      } else {
        types.add('- : ${TypePrinter().print(inferred!)}');
      }
      inference.locals.sort(
        (a, b) => comparePositions(a.name.position, b.name.position),
      );
      for (final binding in inference.locals) {
        final scheme = binding.scheme!,
            printer = TypePrinter(quantified: scheme.quantified, local: true),
            p = binding.name.position;
        types.add(
          '  ${binding.name.spelling} (${p.line}:${p.column}) : ${printer.print(scheme.value)}${suffixClassification(binding)}',
        );
      }
      for (final warning in warnings) {
        reports.report('warning', warning.position, warning.message);
      }
      try {
        if (item.kind == 'declaration') {
          final (updated, evaluated) = evaluator.group(item.group!, valueEnv);
          typeEnv = TypeEnv.of(typeEnv);
          for (var j = 0; j < item.group!.bindings.length; j++) {
            final binding = item.group!.bindings[j],
                name = binding.name.spelling;
            typeEnv[name] = binding.scheme!;
            values.add('$name = ${printValue(evaluated[j])}');
            stats.bindings++;
          }
          valueEnv = updated;
        } else {
          values.add(
            '- = ${printValue(evaluator.expression(item.expression!, valueEnv))}',
          );
        }
      } on RuntimeError catch (error) {
        reports.report('runtime error', error.position, error.message);
      }
    }
    final remaining = pending.values.toList()
      ..sort((a, b) => comparePositions(a.name!.position, b.name!.position));
    for (final signature in remaining) {
      reports.report(
        'warning',
        signature.name!.position,
        "signature for '${signature.name!.spelling}' is never used",
      );
    }
    stats.calls = evaluator.calls;
  }
  reports.lines.add('== summary ==');
  for (final filename in filenames) {
    final c = statistics[filename]!;
    reports.lines.add(
      '$filename: items=${c.items} bindings=${c.bindings} syntax=${c.syntax} type=${c.type} runtime=${c.runtime} warnings=${c.warnings} calls=${c.calls}',
    );
  }
  Directory('output').createSync(recursive: true);
  writeLines('types.txt', types);
  writeLines('values.txt', values);
  writeLines('errors.txt', reports.lines);
  writeLines('formatted.ml', formatted);
}
