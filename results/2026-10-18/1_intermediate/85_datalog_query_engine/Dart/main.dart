import 'dart:convert';
import 'dart:io';

class Problem implements Exception {
  final String reason;
  Problem(this.reason);
}
Never fail(String reason) => throw Problem(reason);
final reserved = 'not mod count sum min max retract dump why forget listing strata stats check predicates undo halt'.split(' ').toSet();
const comparisons = {'=', '!=', '<', '<=', '>', '>='};
const arithmetic = {'+', '-', '*', '/', 'mod'};

class Value implements Comparable<Value> {
  final int? integer;
  final String? symbol;
  Value.number(int value) : integer = value, symbol = null;
  Value.symbol(String value) : integer = null, symbol = value;
  @override
  bool operator ==(Object other) => other is Value && integer == other.integer && symbol == other.symbol;
  @override
  int get hashCode => Object.hash(integer, symbol);
  @override
  int compareTo(Value other) {
    final a = integer, b = other.integer;
    if (a != null) return b == null ? -1 : a.compareTo(b);
    return b != null ? 1 : symbol!.compareTo(other.symbol!);
  }
  String text() {
    if (integer != null) return '$integer';
    final value = symbol!;
    return RegExp(r'^[a-z][a-zA-Z0-9_]*$').hasMatch(value) && !reserved.contains(value) ? value : '"$value"';
  }
}
int tupleCompare(List<Value> a, List<Value> b) {
  for (var i = 0; i < a.length; i++) {
    final order = a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  return 0;
}
String tupleKey(List<Value> values) => jsonEncode(values.map((value) => value.integer != null ? ['integer', value.integer] : ['symbol', value.symbol]).toList());
typedef Binding = Map<String, Value>;
String bindingKey(Binding binding) {
  final names = binding.keys.toList()..sort();
  return jsonEncode(names.map((name) => [name, tupleKey([binding[name]!])]).toList());
}

sealed class Term {}
final class Constant extends Term {
  final Value value;
  Constant(this.value);
}
final class Variable extends Term {
  final String name;
  Variable(this.name);
}
final class Anonymous extends Term {}
class Atom {
  final String name;
  final List<Term> terms;
  Atom(this.name, this.terms);
}
sealed class Expression {}
final class TermExpression extends Expression {
  final Term term;
  TermExpression(this.term);
}
final class Parentheses extends Expression {
  final Expression expression;
  Parentheses(this.expression);
}
final class Operation extends Expression {
  final String op;
  final Expression left, right;
  Operation(this.op, this.left, this.right);
}
sealed class Literal {}
final class AtomLiteral extends Literal {
  final Atom atom;
  final bool negative;
  AtomLiteral(this.atom, this.negative);
}
final class Comparison extends Literal {
  final Expression left, right;
  final String op;
  Comparison(this.left, this.op, this.right);
}
sealed class Statement {}
final class Clause extends Statement {
  final Atom? head;
  final List<Literal> body;
  Clause(this.head, this.body);
}
final class Query extends Statement {
  final String aggregate, variable;
  final List<Literal> body;
  Query(this.aggregate, this.variable, this.body);
}
final class AtomCommand extends Statement {
  final String command;
  final Atom atom;
  AtomCommand(this.command, this.atom);
}
final class NamedCommand extends Statement {
  final String command;
  final String? name;
  NamedCommand(this.command, this.name);
}
final class Forget extends Statement {
  final int number;
  Forget(this.number);
}
final class SimpleCommand extends Statement {
  final String command;
  SimpleCommand(this.command);
}
class Token {
  final String kind, text;
  Token(this.kind, this.text);
}
bool wordCharacter(String c) => RegExp(r'[a-zA-Z0-9_]').hasMatch(c);
List<Token> lex(String line) {
  final tokens = <Token>[];
  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (c == ' ') { i++; continue; }
    if (c == '%') break;
    if (c == '"') {
      final end = line.indexOf('"', i + 1);
      if (end < 0) fail('unterminated string');
      tokens.add(Token('string', line.substring(i, end + 1)));
      i = end + 1;
      continue;
    }
    final pair = i + 1 < line.length ? line.substring(i, i + 2) : c;
    if ([':-', '?-', '!=', '<=', '>='].contains(pair)) {
      tokens.add(Token(pair, pair)); i += 2; continue;
    }
    if ('(),.:=<>+-*/'.contains(c)) { tokens.add(Token(c, c)); i++; continue; }
    if (wordCharacter(c)) {
      final start = i;
      while (i < line.length && wordCharacter(line[i])) { i++; }
      final text = line.substring(start, i);
      if (RegExp(r'^[a-z]').hasMatch(text)) {
        tokens.add(Token(reserved.contains(text) ? text : 'name', text));
      } else if (RegExp(r'^[A-Z]').hasMatch(text)) {
        tokens.add(Token('variable', text));
      } else if (text == '_') {
        tokens.add(Token('anonymous', text));
      } else if (RegExp(r'^[0-9]+$').hasMatch(text)) {
        if (int.parse(text) > 1000000000) fail("integer out of range '$text'");
        tokens.add(Token('integer', text));
      } else {
        fail("bad token '$text'");
      }
      continue;
    }
    fail("bad character '$c'");
  }
  tokens.add(Token('end', ''));
  return tokens;
}

class Parser {
  final List<Token> tokens;
  int at = 0;
  Parser(this.tokens);
  Token peek([int offset = 0]) => tokens[at + offset];
  Never syntax() => fail(peek().kind == 'end' ? 'syntax error at end of line' : "syntax error at '${peek().text}'");
  Token take(String kind) {
    if (peek().kind != kind) syntax();
    return tokens[at++];
  }
  Term term() {
    final token = peek();
    if (token.kind == 'name' || token.kind == 'string' || token.kind == 'integer') {
      at++;
      final value = token.kind == 'integer' ? Value.number(int.parse(token.text))
          : Value.symbol(token.kind == 'string' ? token.text.substring(1, token.text.length - 1) : token.text);
      return Constant(value);
    }
    if (token.kind == '-') { at++; return Constant(Value.number(-int.parse(take('integer').text))); }
    if (token.kind == 'variable') { at++; return Variable(token.text); }
    if (token.kind == 'anonymous') { at++; return Anonymous(); }
    syntax();
  }
  Atom atom() {
    final name = take('name').text, terms = <Term>[];
    if (peek().kind == '(') {
      at++; terms.add(term());
      while (peek().kind == ',') { at++; terms.add(term()); }
      take(')');
    }
    return Atom(name, terms);
  }
  Expression factor() {
    if (peek().kind == '(') {
      at++; final inner = expression(); take(')'); return Parentheses(inner);
    }
    return TermExpression(term());
  }
  Expression product() {
    Expression left = factor();
    while (['*', '/', 'mod'].contains(peek().kind)) {
      final op = tokens[at++].kind;
      left = Operation(op, left, factor());
    }
    return left;
  }
  Expression expression() {
    Expression left = product();
    while (peek().kind == '+' || peek().kind == '-') {
      final op = tokens[at++].kind;
      left = Operation(op, left, product());
    }
    return left;
  }
  Literal literal() {
    if (peek().kind == 'not') { at++; return AtomLiteral(atom(), true); }
    if (peek().kind == 'name' && !comparisons.contains(peek(1).kind) && !arithmetic.contains(peek(1).kind)) return AtomLiteral(atom(), false);
    final left = expression(), op = peek().kind;
    if (!comparisons.contains(op)) syntax();
    at++;
    return Comparison(left, op, expression());
  }
  List<Literal> body() {
    final literals = <Literal>[literal()];
    while (peek().kind == ',') { at++; literals.add(literal()); }
    return literals;
  }
  Statement statement() {
    Statement result;
    final kind = peek().kind;
    if (kind == 'name' || kind == ':-') {
      final head = kind == 'name' ? atom() : null;
      var literals = <Literal>[];
      if (peek().kind == ':-') { at++; literals = body(); }
      result = Clause(head, literals);
    } else if (kind == '?-') {
      at++;
      var aggregate = '', variable = '';
      if (['count', 'sum', 'min', 'max'].contains(peek().kind)) {
        aggregate = tokens[at++].kind;
        if (aggregate != 'count') { variable = take('variable').text; take(':'); }
      }
      result = Query(aggregate, variable, body());
    } else if (kind == 'retract' || kind == 'why') {
      at++; result = AtomCommand(kind, atom());
    } else if (kind == 'dump' || kind == 'listing') {
      at++;
      final name = kind == 'dump' || peek().kind == 'name' ? take('name').text : null;
      result = NamedCommand(kind, name);
    } else if (kind == 'forget') {
      at++; result = Forget(int.parse(take('integer').text));
    } else if (['strata', 'stats', 'check', 'predicates', 'undo', 'halt'].contains(kind)) {
      at++; result = SimpleCommand(kind);
    } else {
      syntax();
    }
    take('.'); take('end');
    return result;
  }
}

List<Term> expressionTerms(Expression expression) {
  if (expression is TermExpression) return [expression.term];
  if (expression is Parentheses) return expressionTerms(expression.expression);
  final operation = expression as Operation;
  return [...expressionTerms(operation.left), ...expressionTerms(operation.right)];
}
List<Term> literalTerms(Literal literal) {
  if (literal is AtomLiteral) return literal.atom.terms;
  final comparison = literal as Comparison;
  return [...expressionTerms(comparison.left), ...expressionTerms(comparison.right)];
}
List<Term> allTerms(Atom? head, List<Literal> body) => [...?head?.terms, ...body.expand(literalTerms)];
List<String> variables(List<Term> terms) => terms.whereType<Variable>().map((term) => term.name).toSet().toList();
Value termValue(Term term, Binding binding) {
  if (term is Constant) return term.value;
  if (term is Variable) return binding[term.name]!;
  throw StateError('Anonymous variables have no value');
}
String termText(Term term, [Binding? binding]) {
  if (term is Constant) return term.value.text();
  if (term is Anonymous) return '_';
  final variable = term as Variable;
  return binding == null ? variable.name : binding[variable.name]!.text();
}
String atomText(Atom atom, [Binding? binding]) => atom.name + (atom.terms.isEmpty ? '' : '(${atom.terms.map((term) => termText(term, binding)).join(', ')})');
String tupleText(String name, List<Value> values) => name + (values.isEmpty ? '' : '(${values.map((value) => value.text()).join(', ')})');
String expressionText(Expression expression, [Binding? binding]) {
  if (expression is TermExpression) return termText(expression.term, binding);
  if (expression is Parentheses) return '(${expressionText(expression.expression, binding)})';
  final operation = expression as Operation;
  return '${expressionText(operation.left, binding)} ${operation.op} ${expressionText(operation.right, binding)}';
}
String literalText(Literal literal, [Binding? binding]) {
  if (literal is AtomLiteral) return '${literal.negative ? 'not ' : ''}${atomText(literal.atom, binding)}';
  final comparison = literal as Comparison;
  return '${expressionText(comparison.left, binding)} ${comparison.op} ${expressionText(comparison.right, binding)}';
}
String ruleText(Atom? head, List<Literal> body) => '${head == null ? ':- ' : '${atomText(head)} :- '}${body.map((literal) => literalText(literal)).join(', ')}.';

Value? expressionValue(Expression expression, Binding binding) {
  if (expression is TermExpression) return termValue(expression.term, binding);
  if (expression is Parentheses) return expressionValue(expression.expression, binding);
  final operation = expression as Operation;
  final a = expressionValue(operation.left, binding)?.integer, b = expressionValue(operation.right, binding)?.integer;
  if (a == null || b == null) return null;
  switch (operation.op) {
    case '+': return Value.number(a + b);
    case '-': return Value.number(a - b);
    case '*': return Value.number(a * b);
    default:
      if (b == 0) return null;
      var q = a ~/ b;
      if (a.remainder(b) != 0 && (a < 0) != (b < 0)) q--;
      return Value.number(operation.op == '/' ? q : a - b * q);
  }
}
bool comparisonHolds(Comparison literal, Binding binding) {
  final a = expressionValue(literal.left, binding), b = expressionValue(literal.right, binding);
  if (a == null || b == null) return false;
  if (literal.op == '=') return a == b;
  if (literal.op == '!=') return a != b;
  final x = a.integer, y = b.integer;
  if (x == null || y == null) return false;
  return literal.op == '<' ? x < y : literal.op == '<=' ? x <= y : literal.op == '>' ? x > y : x >= y;
}
Binding? match(Atom atom, List<Value> values, Binding binding) {
  final next = Map<String, Value>.of(binding);
  for (var i = 0; i < atom.terms.length; i++) {
    final term = atom.terms[i], value = values[i];
    if (term is Constant) {
      if (term.value != value) return null;
    } else if (term is Variable) {
      if (next.containsKey(term.name) && next[term.name] != value) return null;
      next[term.name] = value;
    }
  }
  return next;
}
class Derived {
  final List<Value> values;
  final int round, rule;
  Derived(this.values, this.round, this.rule);
}
typedef Data = Map<String, Map<String, Derived>>;
typedef Facts = Map<String, Map<String, List<Value>>>;

List<Binding> solutions(List<Literal> body, Data data, [int? before]) {
  final positives = body.whereType<AtomLiteral>().where((literal) => !literal.negative).map((literal) => literal.atom).toList();
  final filters = body.where((literal) => literal is Comparison || literal is AtomLiteral && literal.negative).toList();
  final bound = <String>{}, ordered = <(Atom, List<Derived>)>[];
  while (positives.isNotEmpty) {
    int score(Atom atom) => atom.terms.where((term) => term is Constant || term is Variable && bound.contains(term.name)).length;
    positives.sort((a, b) { final order = score(b).compareTo(score(a)); return order != 0 ? order : data[a.name]!.length.compareTo(data[b.name]!.length); });
    final atom = positives.removeAt(0);
    ordered.add((atom, data[atom.name]!.values.where((tuple) => before == null || tuple.round < before).toList()));
    bound.addAll(variables(atom.terms));
  }
  bool accepts(Binding binding) {
    for (final literal in filters) {
      if (!variables(literalTerms(literal)).every(binding.containsKey)) continue;
      if (literal is Comparison) { if (!comparisonHolds(literal, binding)) return false; }
      else { final atom = (literal as AtomLiteral).atom; if (data[atom.name]!.values.any((tuple) => match(atom, tuple.values, binding) != null)) return false; }
    }
    return true;
  }
  final answers = <String, Binding>{};
  void visit(int index, Binding binding) {
    if (index == ordered.length) { if (accepts(binding)) answers[bindingKey(binding)] = binding; return; }
    final (atom, tuples) = ordered[index];
    final seen = <String>{};
    for (final tuple in tuples) {
      final candidate = match(atom, tuple.values, binding);
      if (candidate == null || !accepts(candidate)) continue;
      if (seen.add(bindingKey(candidate))) visit(index + 1, candidate);
    }
  }
  visit(0, <String, Value>{});
  return answers.values.toList();
}
class Rule {
  final Atom? head;
  final List<Literal> body;
  final int number;
  Rule(this.head, this.body, this.number);
}
Map<String, int>? assignment(Map<String, int> predicates, List<Rule> rules) {
  final levels = {for (final name in predicates.keys) name: 0};
  for (var iteration = 0; iteration < predicates.length; iteration++) {
    var changed = false;
    for (final rule in rules) {
      final head = rule.head;
      if (head == null) continue;
      for (final literal in rule.body.whereType<AtomLiteral>()) {
        final level = levels[literal.atom.name]! + (literal.negative ? 1 : 0);
        if (level > levels[head.name]!) { levels[head.name] = level; changed = true; }
      }
    }
    if (!changed) return levels;
    if (iteration == predicates.length - 1) return null;
  }
  return levels;
}
class Model {
  final Data data;
  final Map<String, int> levels;
  final int maximum;
  final List<int> rounds, added;
  Model(this.data, this.levels, this.maximum, this.rounds, this.added);
}
class Snapshot {
  final int line;
  final Map<String, int> predicates;
  final Facts facts;
  final List<Rule> rules;
  Snapshot(this.line, this.predicates, this.facts, this.rules);
}
class Answers {
  final List<String> names;
  final List<List<Value>> rows;
  Answers(this.names, this.rows);
}

class Engine {
  Map<String, int> predicates = {};
  Facts facts = {};
  List<Rule> rules = [];
  final history = <Snapshot>[];
  int nextRule = 1;
  Model? cached;

  void save(int line) {
    history.add(Snapshot(line, Map.of(predicates), {for (final entry in facts.entries) entry.key: Map.of(entry.value)}, List.of(rules)));
  }
  Map<String, int> predicateCheck(List<Atom> atoms, bool clauses) {
    final result = Map<String, int>.of(predicates);
    for (final atom in atoms) {
      if (!result.containsKey(atom.name)) {
        if (!clauses) fail('unknown predicate ${atom.name}');
        result[atom.name] = atom.terms.length;
      } else if (result[atom.name] != atom.terms.length) {
        fail('arity mismatch for ${atom.name}: expected ${result[atom.name]}, got ${atom.terms.length}');
      }
    }
    return result;
  }
  void safety(Atom? head, List<Literal> body, [String aggregate = '']) {
    if (head != null && head.terms.any((term) => term is Anonymous)) fail('anonymous variable in head');
    for (final literal in body.whereType<Comparison>()) {
      if (literalTerms(literal).any((term) => term is Anonymous)) fail('anonymous variable in comparison');
    }
    final bound = body.whereType<AtomLiteral>().where((literal) => !literal.negative).expand((literal) => variables(literal.atom.terms)).toSet();
    final required = head == null ? aggregate.isEmpty ? <String>[] : [aggregate] : variables(head.terms);
    for (final literal in body) {
      if (literal is Comparison || literal is AtomLiteral && literal.negative) required.addAll(variables(literalTerms(literal)));
    }
    for (final variable in required) {
      if (!bound.contains(variable)) fail('unsafe variable $variable');
    }
  }
  List<String> register(Clause statement, int line) {
    final head = statement.head, body = statement.body;
    final atoms = <Atom>[if (head != null) head, ...body.whereType<AtomLiteral>().map((literal) => literal.atom)];
    final checked = predicateCheck(atoms, true);
    safety(head, body);
    if (head != null && body.isEmpty) {
      final values = head.terms.map((term) => termValue(term, {})).toList();
      final key = tupleKey(values);
      if (facts[head.name]?.containsKey(key) ?? false) return [];
      save(line); predicates = checked;
      for (final name in predicates.keys) { facts.putIfAbsent(name, () => {}); }
      facts[head.name]![key] = values;
      cached = null;
      return [];
    }
    final text = ruleText(head, body);
    for (final rule in rules) {
      if (ruleText(rule.head, rule.body) == text) fail('duplicate of rule ${rule.number}');
    }
    final rule = Rule(head, body, nextRule);
    if (head != null && assignment(checked, [...rules, rule]) == null) fail('negative cycle through ${head.name}');
    save(line); predicates = checked;
    for (final name in predicates.keys) { facts.putIfAbsent(name, () => {}); }
    rules.add(rule); nextRule++; cached = null;
    final counts = <String, int>{};
    for (final term in allTerms(head, body).whereType<Variable>()) { counts[term.name] = (counts[term.name] ?? 0) + 1; }
    return counts.entries.where((entry) => entry.value == 1).map((entry) => 'WARNING line $line: singleton variable ${entry.key}').toList();
  }
  Model model() {
    final previous = cached;
    if (previous != null) return previous;
    final levels = assignment(predicates, rules)!;
    var maximum = 0;
    for (final level in levels.values) { if (level > maximum) maximum = level; }
    final data = <String, Map<String, Derived>>{
      for (final name in predicates.keys) name: {for (final entry in facts[name]!.entries) entry.key: Derived(entry.value, 0, 0)}
    };
    final rounds = List.filled(maximum + 1, 0), added = List.filled(maximum + 1, 0);
    var serial = 0;
    for (var stratum = 0; stratum <= maximum; stratum++) {
      final active = rules.where((rule) => rule.head != null && levels[rule.head!.name] == stratum).toList()..sort((a, b) => a.number.compareTo(b.number));
      while (true) {
        final pending = <String, Map<String, Derived>>{};
        for (final rule in active) {
          final head = rule.head!;
          for (final binding in solutions(rule.body, data)) {
            final values = head.terms.map((term) => termValue(term, binding)).toList(), name = head.name;
            final key = tupleKey(values);
            if (data[name]!.containsKey(key)) continue;
            final tuples = pending.putIfAbsent(name, () => {});
            tuples.putIfAbsent(key, () => Derived(values, serial + 1, rule.number));
          }
        }
        var count = 0;
        for (final entry in pending.entries) {
          data[entry.key]!.addAll(entry.value);
          count += entry.value.length;
        }
        if (count == 0) break;
        serial++; rounds[stratum]++; added[stratum] += count;
      }
    }
    final result = Model(data, levels, maximum, rounds, added);
    cached = result;
    return result;
  }
  Answers answers(List<Literal> body, Model model) {
    final names = variables(body.expand(literalTerms).toList());
    final rows = solutions(body, model.data).map((binding) => names.map((name) => binding[name]!).toList()).toList()..sort(tupleCompare);
    return Answers(names, rows);
  }
  String answerText(List<String> names, List<Value> row) => [for (var i = 0; i < names.length; i++) '${names[i]} = ${row[i].text()}'].join(', ');
  void proof(String name, Derived tuple, int depth, Model model, List<String> output) {
    final indent = '  ' * depth, text = tupleText(name, tuple.values);
    if (tuple.round == 0) { output.add('$indent$text [fact]'); return; }
    final candidates = rules.where((rule) => rule.head != null && rule.head!.name == name).toList()..sort((a, b) => a.number.compareTo(b.number));
    for (final rule in candidates) {
      final head = rule.head!, names = variables(allTerms(rule.head, rule.body));
      final bindings = solutions(rule.body, model.data, tuple.round).where((binding) => tupleKey(head.terms.map((term) => termValue(term, binding)).toList()) == tupleKey(tuple.values)).toList();
      if (bindings.isEmpty) continue;
      bindings.sort((a, b) => tupleCompare(names.map((name) => a[name]!).toList(), names.map((name) => b[name]!).toList()));
      final binding = bindings.first;
      output.add('$indent$text [rule ${rule.number}]');
      for (final literal in rule.body) {
        if (literal is AtomLiteral && !literal.negative) {
          final tuples = model.data[literal.atom.name]!.values.where((other) => other.round < tuple.round && match(literal.atom, other.values, binding) != null).toList()..sort((a, b) => tupleCompare(a.values, b.values));
          proof(literal.atom.name, tuples.first, depth + 1, model, output);
        } else {
          output.add('$indent  ${literalText(literal, binding)}');
        }
      }
      return;
    }
  }
  bool recursive(String name) {
    final visited = <String>{};
    bool visit(String current) {
      for (final rule in rules) {
        if (rule.head == null || rule.head!.name != current) continue;
        for (final literal in rule.body.whereType<AtomLiteral>()) {
          final next = literal.atom.name;
          if (next == name) return true;
          if (visited.add(next) && visit(next)) return true;
        }
      }
      return false;
    }
    return visit(name);
  }
  List<String> process(Statement statement, int line) {
    if (statement is Clause) return register(statement, line);
    if (statement is Query) {
      predicateCheck(statement.body.whereType<AtomLiteral>().map((literal) => literal.atom).toList(), false);
      safety(null, statement.body, statement.variable);
      final result = answers(statement.body, model()), names = result.names, rows = result.rows;
      if (statement.aggregate == 'count') return ['${rows.length}'];
      if (statement.aggregate == 'sum') {
        final index = names.indexOf(statement.variable);
        var total = 0;
        for (final row in rows) {
          final value = row[index].integer;
          if (value == null) fail('non-integer value in sum');
          total += value;
        }
        return ['$total'];
      }
      if (statement.aggregate == 'min' || statement.aggregate == 'max') {
        if (rows.isEmpty) return ['no answers'];
        final index = names.indexOf(statement.variable), values = rows.map((row) => row[index]).toList()..sort();
        return [(statement.aggregate == 'min' ? values.first : values.last).text()];
      }
      if (names.isEmpty) return [rows.isEmpty ? 'false.' : 'true.'];
      return [...rows.map((row) => answerText(names, row)), '${rows.length} ${rows.length == 1 ? 'answer' : 'answers'}'];
    }
    if (statement is AtomCommand) {
      final atom = statement.atom;
      predicateCheck([atom], false);
      if (statement.command == 'retract') {
        final tuples = facts[atom.name]!;
        final keys = tuples.entries.where((entry) => match(atom, entry.value, {}) != null).map((entry) => entry.key).toList();
        if (keys.isEmpty) fail('no matching facts');
        save(line);
        for (final key in keys) { tuples.remove(key); }
        cached = null;
        return ['${keys.length} ${keys.length == 1 ? 'fact' : 'facts'} retracted'];
      }
      if (atom.terms.any((term) => term is! Constant)) fail('why needs a ground atom');
      final current = model(), tuple = current.data[atom.name]![tupleKey(atom.terms.map((term) => termValue(term, {})).toList())];
      if (tuple == null) return ['false.'];
      final output = <String>[];
      proof(atom.name, tuple, 0, current, output);
      return output;
    }
    if (statement is Forget) {
      final index = rules.indexWhere((rule) => rule.number == statement.number);
      if (index < 0) fail('no rule ${statement.number}');
      save(line); rules.removeAt(index); cached = null;
      return [];
    }
    if (statement is NamedCommand) {
      final name = statement.name;
      if (name != null && !predicates.containsKey(name)) fail('unknown predicate $name');
      if (statement.command == 'listing') {
        final selected = rules.where((rule) => name == null || rule.head != null && rule.head!.name == name).toList()..sort((a, b) => a.number.compareTo(b.number));
        return selected.isEmpty ? ['no rules'] : selected.map((rule) => '${rule.number}: ${ruleText(rule.head, rule.body)}').toList();
      }
      final tuples = model().data[name]!.values.toList()..sort((a, b) => tupleCompare(a.values, b.values));
      return [...tuples.map((tuple) => '${tupleText(name!, tuple.values)}.'), '${tuples.length} ${tuples.length == 1 ? 'tuple' : 'tuples'}'];
    }
    final command = (statement as SimpleCommand).command;
    if (command == 'undo') {
      if (history.isEmpty) fail('nothing to undo');
      final snapshot = history.removeLast();
      predicates = snapshot.predicates; facts = snapshot.facts; rules = snapshot.rules; cached = null;
      return ['undid line ${snapshot.line}'];
    }
    final current = model(), output = <String>[];
    if (command == 'strata') {
      if (predicates.isEmpty) return ['no predicates'];
      for (var level = 0; level <= current.maximum; level++) {
        final names = predicates.keys.where((name) => current.levels[name] == level).toList()..sort();
        output.add('stratum $level: ${names.map((name) => '$name${recursive(name) ? '*' : ''}').join(', ')}');
      }
    } else if (command == 'stats') {
      final factCount = facts.values.fold(0, (total, tuples) => total + tuples.length);
      final tupleCount = current.data.values.fold(0, (total, tuples) => total + tuples.length);
      final selected = rules.where((rule) => rule.head != null).toList()..sort((a, b) => a.number.compareTo(b.number));
      output.add('facts $factCount, rules ${selected.length}, constraints ${rules.length - selected.length}, tuples $tupleCount');
      if (predicates.isNotEmpty) {
        for (var level = 0; level <= current.maximum; level++) { output.add('stratum $level: rounds ${current.rounds[level]}, new ${current.added[level]}'); }
      }
      for (final rule in selected) {
        var count = 0;
        for (final tuples in current.data.values) {
          for (final tuple in tuples.values) { if (tuple.rule == rule.number) count++; }
        }
        output.add('rule ${rule.number}: new $count');
      }
    } else if (command == 'predicates') {
      if (predicates.isEmpty) return ['no predicates'];
      final names = predicates.keys.toList()..sort();
      for (final name in names) {
        final count = rules.where((rule) => rule.head != null && rule.head!.name == name).length;
        output.add('$name/${predicates[name]}: facts ${facts[name]!.length}, rules $count, tuples ${current.data[name]!.length}');
      }
    } else if (command == 'check') {
      final constraints = rules.where((rule) => rule.head == null).toList()..sort((a, b) => a.number.compareTo(b.number));
      if (constraints.isEmpty) return ['no constraints'];
      for (final constraint in constraints) {
        final result = answers(constraint.body, current), rows = result.rows, names = result.names;
        output.add('constraint ${constraint.number}: ${rows.isEmpty ? 'ok' : '${rows.length} ${rows.length == 1 ? 'violation' : 'violations'}'}');
        if (names.isNotEmpty) {
          for (final row in rows) { output.add('  ${answerText(names, row)}'); }
        }
      }
    }
    return output;
  }
}

void main() {
  final engine = Engine(), output = <String>[];
  var lineNumber = 0;
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    lineNumber++;
    try {
      final tokens = lex(line!);
      if (tokens.length == 1) continue;
      final statement = Parser(tokens).statement();
      if (statement is SimpleCommand && statement.command == 'halt') break;
      output.addAll(engine.process(statement, lineNumber));
    } on Problem catch (error) {
      output.add('ERROR line $lineNumber: ${error.reason}');
    }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
