import 'dart:io';

sealed class Term {}
final class Variable extends Term {
  final String name;
  Variable(this.name);
}
final class Macro extends Term {
  final String name;
  Macro(this.name);
}
final class Numeral extends Term {
  final int value;
  Numeral(this.value);
}
final class Lambda extends Term {
  final String name;
  final Term body;
  Lambda(this.name, this.body);
}
final class Apply extends Term {
  final Term left, right;
  Apply(this.left, this.right);
}
final class Constant extends Term {
  final String name;
  Constant(this.name);
}

sealed class DBTerm {}
final class Free extends DBTerm {
  final String name;
  Free(this.name);
}
final class Index extends DBTerm {
  final int value;
  Index(this.value);
}
final class DBLambda extends DBTerm {
  final DBTerm body;
  DBLambda(this.body);
}
final class DBApply extends DBTerm {
  final DBTerm left, right;
  DBApply(this.left, this.right);
}

class Problem implements Exception {
  final String reason;
  Problem(this.reason);
}
class TypeFailure implements Exception {}
Never fail(String reason) => throw Problem(reason);

class Token {
  final String kind, text;
  final int column;
  Token(this.kind, this.text, this.column);
}

bool lower(String c) => c.compareTo('a') >= 0 && c.compareTo('z') <= 0;
bool upper(String c) => c.compareTo('A') >= 0 && c.compareTo('Z') <= 0;
bool digit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

List<Token> lex(String argument, int start, int end) {
  final result = <Token>[];
  var i = 0;
  while (i < argument.length) {
    final c = argument[i], column = start + i;
    if (c == ' ') { i++; continue; }
    if ('\\.()=;'.contains(c)) {
      result.add(Token(c, c, column));
      i++;
      continue;
    }
    final begin = i;
    String kind;
    if (lower(c)) {
      kind = 'variable';
      while (i < argument.length && (lower(argument[i]) || digit(argument[i]))) { i++; }
    } else if (upper(c)) {
      kind = 'macro';
      while (i < argument.length && (upper(argument[i]) || digit(argument[i]) || argument[i] == '_')) { i++; }
    } else if (c == '#' && i + 1 < argument.length && digit(argument[i + 1])) {
      kind = 'numeral';
      i += 2;
      while (i < argument.length && digit(argument[i])) { i++; }
    } else {
      fail("column $column: unexpected character '$c'");
    }
    result.add(Token(kind, argument.substring(begin, i), column));
  }
  result.add(Token('end', '', end));
  return result;
}

class Parser {
  final List<Token> tokens;
  int at = 0;
  Parser(this.tokens);
  Token get peek => tokens[at];
  Token expect(String kind) {
    final token = peek;
    if (token.kind != kind) {
      final notation = kind == 'variable' ? 'variable' : kind == 'macro' ? 'macro name' : "'$kind'";
      fail('column ${token.column}: expected $notation');
    }
    at++;
    return token;
  }
  Term term() {
    final elements = <Term>[];
    while (['variable', 'macro', 'numeral', '('].contains(peek.kind)) { elements.add(atom()); }
    if (peek.kind == '\\') {
      at++;
      final names = <String>[expect('variable').text];
      while (peek.kind == 'variable') { names.add(tokens[at++].text); }
      expect('.');
      Term body = term();
      for (var i = names.length - 1; i >= 0; i--) { body = Lambda(names[i], body); }
      elements.add(body);
    }
    if (elements.isEmpty) { fail('column ${peek.column}: expected term'); }
    Term result = elements.first;
    for (final element in elements.skip(1)) { result = Apply(result, element); }
    return result;
  }
  Term atom() {
    final token = tokens[at++];
    if (token.kind == 'variable') return Variable(token.text);
    if (token.kind == 'macro') return Macro(token.text);
    if (token.kind == 'numeral') return Numeral(int.parse(token.text.substring(1)));
    final result = term();
    expect(')');
    return result;
  }
  void end() {
    if (peek.kind != 'end') { fail("column ${peek.column}: unexpected '${peek.text}'"); }
  }
}

final freeCache = Expando<Set<String>>();
Set<String> free(Term term) {
  final cached = freeCache[term];
  if (cached != null) return cached;
  final Set<String> result;
  if (term is Variable) {
    result = {term.name};
  } else if (term is Lambda) {
    result = {...free(term.body)}..remove(term.name);
  } else if (term is Apply) {
    result = {...free(term.left), ...free(term.right)};
  } else {
    result = <String>{};
  }
  freeCache[term] = result;
  return result;
}

String printTerm(Term term, [bool end = true]) {
  if (term is Variable) return term.name;
  if (term is Macro) return term.name;
  if (term is Constant) return term.name;
  if (term is Numeral) return '#${term.value}';
  if (term is Lambda) {
    final names = <String>[];
    Term body = term;
    while (body is Lambda) { names.add(body.name); body = body.body; }
    final text = '\\${names.join(' ')}. ${printTerm(body)}';
    return end ? text : '($text)';
  }
  final node = term as Apply;
  final left = node.left is Lambda ? '(${printTerm(node.left)})' : printTerm(node.left, false);
  final right = node.right is Apply ? '(${printTerm(node.right)})' : printTerm(node.right, end);
  return '$left $right';
}

List<String> references(Term term) {
  if (term is Macro) return [term.name];
  if (term is Lambda) return references(term.body);
  if (term is Apply) return [...references(term.left), ...references(term.right)];
  return [];
}

Term substitute(Term term, String name, Term replacement) {
  if (term is Variable) return term.name == name ? replacement : term;
  if (term is Apply) return Apply(substitute(term.left, name, replacement), substitute(term.right, name, replacement));
  final node = term as Lambda;
  if (node.name == name || !free(node.body).contains(name)) return node;
  if (!free(replacement).contains(node.name)) return Lambda(node.name, substitute(node.body, name, replacement));
  final base = node.name.replaceFirst(RegExp(r'[0-9]+$'), '');
  var i = 1;
  String next;
  do {
    next = '$base${i++}';
  } while (free(replacement).contains(next) || free(node.body).contains(next));
  return Lambda(next, substitute(substitute(node.body, node.name, Variable(next)), name, replacement));
}

DBTerm toDB(Term term, [List<String> environment = const []]) {
  if (term is Variable) {
    final index = environment.indexOf(term.name);
    return index < 0 ? Free(term.name) : Index(index);
  }
  if (term is Lambda) return DBLambda(toDB(term.body, [term.name, ...environment]));
  final node = term as Apply;
  return DBApply(toDB(node.left, environment), toDB(node.right, environment));
}

String printDB(DBTerm term, [bool end = true]) {
  if (term is Free) return term.name;
  if (term is Index) return '${term.value}';
  if (term is DBLambda) {
    DBTerm body = term;
    var prefix = '';
    while (body is DBLambda) { prefix += '\\'; body = body.body; }
    final text = prefix + printDB(body);
    return end ? text : '($text)';
  }
  final node = term as DBApply;
  final left = node.left is DBLambda ? '(${printDB(node.left)})' : printDB(node.left, false);
  final right = node.right is DBApply ? '(${printDB(node.right)})' : printDB(node.right, end);
  return '$left $right';
}

String generatedName(int index) => String.fromCharCode(97 + index % 26) + (index >= 26 ? '${index ~/ 26}' : '');
Term fromDB(DBTerm term) {
  final names = <String>{};
  void collect(DBTerm node) {
    if (node is Free) { names.add(node.name); }
    else if (node is DBLambda) { collect(node.body); }
    else if (node is DBApply) { collect(node.left); collect(node.right); }
  }
  collect(term);
  var counter = 0;
  Term walk(DBTerm node, List<String> environment) {
    if (node is Free) return Variable(node.name);
    if (node is Index) return Variable(environment[node.value]);
    if (node is DBLambda) {
      String name;
      do { name = generatedName(counter++); } while (names.contains(name));
      return Lambda(name, walk(node.body, [name, ...environment]));
    }
    final application = node as DBApply;
    return Apply(walk(application.left, environment), walk(application.right, environment));
  }
  return walk(term, []);
}
String canonical(Term term) => printTerm(fromDB(toDB(term)));

Term? etaBody(Lambda term) {
  final body = term.body;
  if (body is Apply && body.right is Variable && (body.right as Variable).name == term.name && !free(body.left).contains(term.name)) return body.left;
  return null;
}

class Step {
  final Term term;
  final String kind;
  Step(this.term, this.kind);
}
class Reduction {
  final Term term;
  final int count;
  final bool success;
  Reduction(this.term, this.count, this.success);
}

Step? oneStep(Term term, String strategy, bool eta) {
  if (term is Variable) return null;
  if (term is Lambda) {
    if (strategy == 'CBN' || strategy == 'CBV') return null;
    final candidate = eta ? etaBody(term) : null;
    if (strategy == 'NORMAL' && candidate != null) return Step(candidate, 'eta');
    final step = oneStep(term.body, strategy, eta);
    if (step != null) return Step(Lambda(term.name, step.term), step.kind);
    return candidate == null ? null : Step(candidate, 'eta');
  }
  final node = term as Apply;
  final early = strategy == 'NORMAL' || strategy == 'CBN';
  final function = node.left;
  if (early && function is Lambda) return Step(substitute(function.body, function.name, node.right), 'beta');
  final left = oneStep(node.left, strategy, eta);
  if (left != null) return Step(Apply(left.term, node.right), left.kind);
  if (strategy != 'CBN') {
    final right = oneStep(node.right, strategy, eta);
    if (right != null) return Step(Apply(node.left, right.term), right.kind);
  }
  if (!early && function is Lambda && (strategy != 'CBV' || node.right is Variable || node.right is Lambda)) {
    return Step(substitute(function.body, function.name, node.right), 'beta');
  }
  return null;
}

Term abstractSki(String name, Term term) {
  if (!free(term).contains(name)) return Apply(Constant('K'), term);
  if (term is Variable) return Constant('I');
  final node = term as Apply;
  if (node.right is Variable && (node.right as Variable).name == name && !free(node.left).contains(name)) return node.left;
  return Apply(Apply(Constant('S'), abstractSki(name, node.left)), abstractSki(name, node.right));
}
Term toSki(Term term) {
  if (term is Variable) return term;
  if (term is Lambda) return abstractSki(term.name, toSki(term.body));
  final node = term as Apply;
  return Apply(toSki(node.left), toSki(node.right));
}
Step? skiStep(Term term) {
  Term head = term;
  final args = <Term>[];
  while (head is Apply) { args.insert(0, head.right); head = head.left; }
  Term? result;
  var used = 0;
  if (head is Constant) {
    if (head.name == 'I' && args.isNotEmpty) { result = args[0]; used = 1; }
    else if (head.name == 'K' && args.length >= 2) { result = args[0]; used = 2; }
    else if (head.name == 'S' && args.length >= 3) {
      result = Apply(Apply(args[0], args[2]), Apply(args[1], args[2]));
      used = 3;
    }
  }
  if (result != null) {
    for (final argument in args.skip(used)) { result = Apply(result!, argument); }
    return Step(result!, (head as Constant).name);
  }
  for (var i = 0; i < args.length; i++) {
    final step = skiStep(args[i]);
    if (step != null) {
      args[i] = step.term;
      Term rebuilt = head;
      for (final argument in args) { rebuilt = Apply(rebuilt, argument); }
      return Step(rebuilt, step.kind);
    }
  }
  return null;
}

sealed class SimpleType {}
final class TypeVariable extends SimpleType {
  final int id;
  SimpleType? link;
  TypeVariable(this.id);
}
final class Arrow extends SimpleType {
  final SimpleType left, right;
  Arrow(this.left, this.right);
}

String principalType(Term term) {
  final freeTypes = <String, SimpleType>{};
  var next = 0;
  TypeVariable fresh() => TypeVariable(next++);
  SimpleType prune(SimpleType type) {
    if (type is TypeVariable && type.link != null) {
      type.link = prune(type.link!);
      return type.link!;
    }
    return type;
  }
  bool occurs(TypeVariable variable, SimpleType type) {
    final node = prune(type);
    return identical(node, variable) || node is Arrow && (occurs(variable, node.left) || occurs(variable, node.right));
  }
  void unify(SimpleType left, SimpleType right) {
    final a = prune(left), b = prune(right);
    if (identical(a, b)) return;
    if (a is TypeVariable) {
      if (occurs(a, b)) throw TypeFailure();
      a.link = b;
    } else if (b is TypeVariable) {
      unify(b, a);
    } else {
      final x = a as Arrow, y = b as Arrow;
      unify(x.left, y.left);
      unify(x.right, y.right);
    }
  }
  SimpleType infer(Term node, Map<String, SimpleType> bound) {
    if (node is Variable) {
      if (bound.containsKey(node.name)) return bound[node.name]!;
      return freeTypes.putIfAbsent(node.name, fresh);
    }
    if (node is Lambda) {
      final type = fresh(), environment = {...bound};
      environment[node.name] = type;
      return Arrow(type, infer(node.body, environment));
    }
    final application = node as Apply;
    final left = infer(application.left, bound), right = infer(application.right, bound), result = fresh();
    unify(left, Arrow(right, result));
    return result;
  }
  try {
    final type = infer(term, <String, SimpleType>{}), names = <TypeVariable, String>{};
    String show(SimpleType type) {
      final node = prune(type);
      if (node is TypeVariable) return names.putIfAbsent(node, () => generatedName(names.length));
      final arrow = node as Arrow;
      final left = show(arrow.left);
      return '${prune(arrow.left) is Arrow ? '($left)' : left} -> ${show(arrow.right)}';
    }
    return show(type);
  } on TypeFailure {
    return 'not typable';
  }
}

String readChurch(Term term) {
  if (term is Lambda && term.body is Lambda) {
    final innerLambda = term.body as Lambda;
    final outer = term.name, inner = innerLambda.name;
    Term body = innerLambda.body;
    var count = 0;
    while (body is Apply && body.left is Variable && (body.left as Variable).name == outer) {
      count++;
      body = body.right;
    }
    if (body is Variable && body.name == inner) return '$count';
    if (innerLambda.body is Variable && (innerLambda.body as Variable).name == outer) return 'true';
  }
  if (term is Lambda && term.body is Apply) {
    final body = term.body as Apply;
    if (body.left is Apply) {
      final leftApplication = body.left as Apply;
      if (leftApplication.left is Variable && (leftApplication.left as Variable).name == term.name) {
        final left = leftApplication.right, right = body.right;
        if (!free(left).contains(term.name) && !free(right).contains(term.name)) return '(${readChurch(left)}, ${readChurch(right)})';
      }
    }
  }
  return canonical(term);
}

class Closure {
  final DBTerm code;
  final List<Closure> environment;
  Closure(this.code, this.environment);
}

class Workbench {
  final macros = <String, Term>{};
  final output = <String>[];
  bool display = false, eta = false;
  int limit = 10000;
  Workbench() {
    final predefined = {'S': r'\x y z. x z (y z)', 'K': r'\x y. x', 'I': r'\x. x'};
    for (final entry in predefined.entries) {
      macros[entry.key] = Parser(lex(entry.value, 1, entry.value.length + 1)).term();
    }
  }
  List<String> userNames() => macros.keys.where((name) => !['S', 'K', 'I'].contains(name)).toList()..sort();
  Term expand(Term term) {
    if (term is Macro) {
      final definition = macros[term.name];
      if (definition == null) fail('unbound macro ${term.name}');
      return expand(definition);
    }
    if (term is Numeral) {
      Term body = Variable('x');
      for (var i = 0; i < term.value; i++) { body = Apply(Variable('f'), body); }
      return Lambda('f', Lambda('x', body));
    }
    if (term is Variable) return term;
    if (term is Lambda) return Lambda(term.name, expand(term.body));
    final node = term as Apply;
    return Apply(expand(node.left), expand(node.right));
  }
  bool depends(String name, String target, [Set<String>? seen]) {
    final visited = seen ?? <String>{};
    if (['S', 'K', 'I'].contains(name) || !macros.containsKey(name) || visited.contains(name)) return false;
    visited.add(name);
    return references(macros[name]!).any((other) => other == target || depends(other, target, visited));
  }
  Reduction reduction(Term term, String strategy, bool useEta, {bool show = false, bool ski = false}) {
    var count = 0;
    while (true) {
      final step = ski ? skiStep(term) : oneStep(term, strategy, useEta);
      if (step == null) return Reduction(term, count, true);
      if (count == limit) return Reduction(term, count, false);
      term = step.term;
      count++;
      if (show && display) output.add('step $count (${step.kind}): ${printTerm(term)}');
    }
  }
  void kam(Term term) {
    DBTerm code = toDB(term);
    var environment = <Closure>[];
    final stack = <Closure>[];
    var count = 0;
    while (true) {
      if (code is! DBApply && code is! Index && !(code is DBLambda && stack.isNotEmpty)) break;
      if (count == limit) {
        output.add('no result within $limit transitions');
        return;
      }
      String kind;
      if (code is DBApply) {
        kind = 'push';
        stack.add(Closure(code.right, environment));
        code = code.left;
      } else if (code is DBLambda) {
        kind = 'grab';
        environment = [stack.removeLast(), ...environment];
        code = code.body;
      } else {
        kind = 'access';
        final closure = environment[(code as Index).value];
        code = closure.code;
        environment = closure.environment;
      }
      count++;
      if (display) output.add('step $count ($kind): ${printDB(code)} [env ${environment.length}, stack ${stack.length}]');
    }
    DBTerm restore(DBTerm code, List<Closure> environment, [int depth = 0]) {
      while (code is Index && code.value >= depth) {
        final closure = environment[code.value - depth];
        code = closure.code;
        environment = closure.environment;
        depth = 0;
      }
      if (code is DBLambda) return DBLambda(restore(code.body, environment, depth + 1));
      if (code is DBApply) return DBApply(restore(code.left, environment, depth), restore(code.right, environment, depth));
      return code;
    }
    DBTerm result = restore(code, environment);
    for (final closure in stack.reversed) { result = DBApply(result, restore(closure.code, closure.environment)); }
    output.add('result: ${printTerm(fromDB(result))} (transitions: $count)');
  }
  void command(String line) {
    final position = line.indexOf(' ');
    final command = position < 0 ? line : line.substring(0, position);
    final argument = position < 0 ? '' : line.substring(position + 1);
    const commands = ['let', 'unlet', 'macros', 'steps', 'eta', 'limit', 'expand', 'subst', 'reduce', 'equal', 'alpha', 'debruijn', 'fv', 'size', 'depth', 'type', 'church', 'ski', 'skireduce', 'kam'];
    if (!commands.contains(command)) fail('unknown command $command');
    const reserved = ['S', 'K', 'I', 'NORMAL', 'APPLICATIVE', 'CBN', 'CBV'];
    if (['unlet', 'macros', 'steps', 'eta', 'limit'].contains(command)) {
      final words = argument.split(' ').where((word) => word.isNotEmpty).toList();
      if (command == 'macros') {
        if (words.isNotEmpty) fail('bad argument');
        final names = userNames();
        if (names.isEmpty) output.add('(none)');
        for (final name in names) { output.add('$name = ${printTerm(macros[name]!)}'); }
      } else if (command == 'steps' || command == 'eta') {
        if (words.length != 1 || !['on', 'off'].contains(words[0])) fail('bad argument');
        if (command == 'steps') { display = words[0] == 'on'; }
        else { eta = words[0] == 'on'; }
      } else if (command == 'limit') {
        if (words.length != 1 || !RegExp(r'^[0-9]{1,5}$').hasMatch(words[0]) || int.parse(words[0]) < 1 || int.parse(words[0]) > 10000) fail('bad argument');
        limit = int.parse(words[0]);
      } else {
        if (words.length != 1 || !RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(words[0])) fail('bad argument');
        final name = words[0];
        if (reserved.contains(name)) fail('reserved name $name');
        if (!macros.containsKey(name)) fail('unbound macro $name');
        for (final user in userNames()) {
          if (references(macros[user]!).contains(name)) fail('$name is used by $user');
        }
        macros.remove(name);
        output.add('removed $name');
      }
      return;
    }
    final parser = Parser(lex(argument, position < 0 ? line.length + 1 : position + 2, line.length + 1));
    var name = '', strategy = 'NORMAL';
    List<Term> terms;
    if (command == 'let' || command == 'subst') {
      name = parser.expect(command == 'let' ? 'macro' : 'variable').text;
      parser.expect('=');
      terms = [parser.term()];
      if (command == 'subst') { parser.expect(';'); terms.add(parser.term()); }
    } else if (command == 'equal' || command == 'alpha') {
      terms = [parser.term()];
      parser.expect(';');
      terms.add(parser.term());
    } else {
      if (command == 'reduce' && parser.peek.kind == 'macro' && ['NORMAL', 'APPLICATIVE', 'CBN', 'CBV'].contains(parser.peek.text)) strategy = parser.tokens[parser.at++].text;
      terms = [parser.term()];
    }
    parser.end();
    if (command == 'let') {
      final term = terms[0];
      if (reserved.contains(name)) fail('reserved name $name');
      for (final reference in references(term)) {
        if (reference == name || depends(reference, name)) fail('recursive definition of $name');
        if (!macros.containsKey(reference)) fail('unbound macro $reference');
      }
      final variables = free(term).toList()..sort();
      if (variables.isNotEmpty) fail('free variable ${variables.first} in definition of $name');
      output.add('${macros.containsKey(name) ? 'redefined' : 'defined'} $name');
      macros[name] = term;
      return;
    }
    terms = terms.map(expand).toList();
    final term = terms[0];
    if (command == 'expand') { output.add(printTerm(term)); }
    else if (command == 'subst') { output.add(printTerm(substitute(terms[1], name, term))); }
    else if (command == 'fv') {
      final names = free(term).toList()..sort();
      output.add(names.isEmpty ? '(none)' : names.join(' '));
    } else if (command == 'debruijn') { output.add(printDB(toDB(term))); }
    else if (command == 'alpha') { output.add(printDB(toDB(term)) == printDB(toDB(terms[1])) ? 'yes' : 'no'); }
    else if (command == 'size' || command == 'depth') {
      int measure(Term node) {
        if (node is Variable) return 1;
        if (node is Lambda) return 1 + measure(node.body);
        final application = node as Apply;
        final left = measure(application.left), right = measure(application.right);
        return 1 + (command == 'size' ? left + right : left > right ? left : right);
      }
      output.add('${measure(term)}');
    } else if (command == 'type') { output.add(principalType(term)); }
    else if (command == 'ski') { output.add(printTerm(toSki(term))); }
    else if (command == 'kam') { kam(term); }
    else if (command == 'equal') {
      final a = reduction(term, 'NORMAL', eta), b = reduction(terms[1], 'NORMAL', eta);
      output.add(!a.success || !b.success ? 'unknown' : printDB(toDB(a.term)) == printDB(toDB(b.term)) ? 'yes' : 'no');
    } else {
      final ski = command == 'skireduce';
      final result = reduction(ski ? toSki(term) : term, strategy, command == 'church' ? false : eta, show: command == 'reduce' || ski, ski: ski);
      output.add(!result.success ? 'no normal form within $limit steps'
          : command == 'church' ? readChurch(fromDB(toDB(result.term)))
          : 'result: ${ski ? printTerm(result.term) : canonical(result.term)} (steps: ${result.count})');
    }
  }
}

void main() {
  final workbench = Workbench();
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    final input = line!;
    if (input == 'quit') break;
    if (input.isEmpty || input.startsWith('--')) continue;
    try {
      workbench.command(input);
    } on Problem catch (error) {
      workbench.output.add('error: ${error.reason}');
    }
  }
  if (workbench.output.isNotEmpty) stdout.write('${workbench.output.join('\n')}\n');
}
