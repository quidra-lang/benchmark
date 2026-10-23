import 'dart:io';

class Problem implements Exception {
  final String reason;
  Problem(this.reason);
}
Never fail(String reason) => throw Problem(reason);
const precedence = {'<->': 1, '->': 2, '|': 3, '^': 4, '&': 5};
sealed class Formula {}
final class Variable extends Formula {
  final String name;
  Variable(this.name);
}
final class Constant extends Formula {
  final int value;
  Constant(this.value);
}
final class Negation extends Formula {
  final Formula child;
  Negation(this.child);
}
final class Binary extends Formula {
  final String op;
  final Formula left, right;
  Binary(this.op, this.left, this.right);
}

String notation(Formula node) {
  if (node is Variable) return node.name;
  if (node is Constant) return '${node.value}';
  if (node is Negation) return '~${node.child is Binary ? '(${notation(node.child)})' : notation(node.child)}';
  final binary = node as Binary, a = binary.left, b = binary.right;
  final level = precedence[binary.op]!;
  final left = a is Binary && (precedence[a.op]! < level || binary.op == '->' && a.op == '->');
  final right = b is Binary && (precedence[b.op]! < level || binary.op == b.op && binary.op != '->');
  return '${left ? '(${notation(a)})' : notation(a)} ${binary.op} ${right ? '(${notation(b)})' : notation(b)}';
}
List<String> formulaVariables(Formula node) {
  if (node is Variable) return [node.name];
  if (node is Constant) return [];
  if (node is Negation) return formulaVariables(node.child);
  final binary = node as Binary;
  return [...formulaVariables(binary.left), ...formulaVariables(binary.right)];
}
List<String> variables(List<Formula> nodes) => nodes.expand(formulaVariables).toSet().toList()..sort();
(int, int) measure(Formula node) {
  if (node is Variable || node is Constant) return (1, 1);
  if (node is Negation) { final child = measure(node.child); return (child.$1 + 1, child.$2 + 1); }
  final binary = node as Binary, left = measure(binary.left), right = measure(binary.right);
  return (left.$1 + right.$1 + 1, (left.$2 > right.$2 ? left.$2 : right.$2) + 1);
}
class Token {
  final String text;
  final int position;
  Token(this.text, this.position);
}
List<Token> lex(String text, int start) {
  final tokens = <Token>[];
  var i = 0;
  while (i < text.length) {
    final c = text[i], position = start + i;
    if (c == ' ') { i++; continue; }
    if (text.startsWith('<->', i)) { tokens.add(Token('<->', position)); i += 3; continue; }
    if (text.startsWith('->', i)) { tokens.add(Token('->', position)); i += 2; continue; }
    if (RegExp(r'[a-z]').hasMatch(c)) {
      final begin = i++;
      while (i < text.length && RegExp(r'[a-z0-9]').hasMatch(text[i])) { i++; }
      tokens.add(Token(text.substring(begin, i), position));
      continue;
    }
    if (RegExp(r'[A-Z01~&^|()]').hasMatch(c)) { tokens.add(Token(c, position)); i++; continue; }
    fail("invalid character '$c' at $position");
  }
  tokens.add(Token('', start + text.length));
  return tokens;
}
class FormulaParser {
  final List<Token> tokens;
  final Map<String, Formula> definitions;
  int at = 0;
  FormulaParser(this.tokens, this.definitions);
  Never unexpected() {
    final token = tokens[at];
    fail(token.text.isEmpty ? 'unexpected end of formula at ${token.position}' : "unexpected '${token.text}' at ${token.position}");
  }
  Formula unary() {
    final token = tokens[at];
    if (token.text == '~') { at++; return Negation(unary()); }
    if (token.text == '(') {
      at++; final result = expression(1);
      if (tokens[at].text != ')') unexpected();
      at++; return result;
    }
    if (RegExp(r'^[A-Z]$').hasMatch(token.text)) { at++; return Variable(token.text); }
    if (token.text == '0' || token.text == '1') { at++; return Constant(int.parse(token.text)); }
    if (RegExp(r'^[a-z]').hasMatch(token.text)) {
      at++;
      final definition = definitions[token.text];
      if (definition == null) fail("undefined name '${token.text}' at ${token.position}");
      return definition;
    }
    unexpected();
  }
  Formula expression(int minimum) {
    Formula left = unary();
    while (precedence.containsKey(tokens[at].text) && precedence[tokens[at].text]! >= minimum) {
      final op = tokens[at++].text, level = precedence[op]!;
      left = Binary(op, left, expression(level + (op == '->' ? 0 : 1)));
    }
    return left;
  }
  Formula parse() {
    final result = expression(1);
    if (tokens[at].text.isNotEmpty) unexpected();
    return result;
  }
}
Formula parseFormula(String text, int start, Map<String, Formula> definitions) => FormulaParser(lex(text, start), definitions).parse();
bool equal(Formula a, Formula b) {
  if (identical(a, b)) return true;
  if (a is Variable && b is Variable) return a.name == b.name;
  if (a is Constant && b is Constant) return a.value == b.value;
  if (a is Negation && b is Negation) return equal(a.child, b.child);
  return a is Binary && b is Binary && a.op == b.op && equal(a.left, b.left) && equal(a.right, b.right);
}
Formula reducedNegation(Formula a) => a is Constant ? Constant(1 - a.value) : a is Negation ? a.child : Negation(a);
Formula simplifyBinary(String op, Formula a, Formula b) {
  bool isValue(Formula node, int value) => node is Constant && node.value == value;
  final same = equal(a, b), complementary = a is Negation && equal(a.child, b) || b is Negation && equal(a, b.child);
  switch (op) {
    case '&':
      if (isValue(a, 0) || isValue(b, 0)) return Constant(0);
      if (isValue(a, 1)) return b; if (isValue(b, 1)) return a;
      if (same) return a; if (complementary) return Constant(0); break;
    case '|':
      if (isValue(a, 1) || isValue(b, 1)) return Constant(1);
      if (isValue(a, 0)) return b; if (isValue(b, 0)) return a;
      if (same) return a; if (complementary) return Constant(1); break;
    case '^':
      if (isValue(a, 0)) return b; if (isValue(b, 0)) return a;
      if (isValue(a, 1)) return reducedNegation(b); if (isValue(b, 1)) return reducedNegation(a);
      if (same) return Constant(0); if (complementary) return Constant(1); break;
    case '->':
      if (isValue(a, 0) || isValue(b, 1)) return Constant(1);
      if (isValue(a, 1)) return b; if (isValue(b, 0)) return reducedNegation(a);
      if (same) return Constant(1); if (complementary) return b; break;
    case '<->':
      if (isValue(a, 1)) return b; if (isValue(b, 1)) return a;
      if (isValue(a, 0)) return reducedNegation(b); if (isValue(b, 0)) return reducedNegation(a);
      if (same) return Constant(1); if (complementary) return Constant(0); break;
  }
  return Binary(op, a, b);
}
Formula simplify(Formula node, [Map<String, int> replacements = const {}]) {
  if (node is Constant) return node;
  if (node is Variable) return replacements.containsKey(node.name) ? Constant(replacements[node.name]!) : node;
  if (node is Negation) return reducedNegation(simplify(node.child, replacements));
  final binary = node as Binary;
  return simplifyBinary(binary.op, simplify(binary.left, replacements), simplify(binary.right, replacements));
}
final nnfCache = Expando<Map<bool, Formula>>();
Formula nnf(Formula node, [bool positive = true]) {
  final bySign = nnfCache[node] ??= <bool, Formula>{};
  final cached = bySign[positive];
  if (cached != null) return cached;
  final result = nnfCompute(node, positive);
  bySign[positive] = result;
  return result;
}
Formula nnfCompute(Formula node, bool positive) {
  if (node is Constant) return Constant(positive ? node.value : 1 - node.value);
  if (node is Variable) return positive ? node : Negation(node);
  if (node is Negation) return nnf(node.child, !positive);
  final binary = node as Binary, a = binary.left, b = binary.right, op = binary.op;
  if (op == '&' || op == '|') return Binary(positive ? op : op == '&' ? '|' : '&', nnf(a, positive), nnf(b, positive));
  if (op == '->') return Binary(positive ? '|' : '&', nnf(a, !positive), nnf(b, positive));
  final same = op == '<->' ? positive : !positive;
  return Binary('|', Binary('&', nnf(a), nnf(b, same)), Binary('&', nnf(a, false), nnf(b, !same)));
}
Formula dual(Formula node) {
  if (node is Variable) return node;
  if (node is Constant) return Constant(1 - node.value);
  if (node is Negation) return Negation(dual(node.child));
  final binary = node as Binary, a = dual(binary.left), b = dual(binary.right);
  return binary.op == '->' ? Binary('&', Negation(a), b) : Binary(binary.op == '&' ? '|' : binary.op == '|' ? '&' : binary.op == '^' ? '<->' : '^', a, b);
}
int evaluate(Formula node, List<String> names, int row) {
  if (node is Constant) return node.value;
  if (node is Variable) return row >> (names.length - names.indexOf(node.name) - 1) & 1;
  if (node is Negation) return 1 - evaluate(node.child, names, row);
  final binary = node as Binary, a = evaluate(binary.left, names, row), b = evaluate(binary.right, names, row);
  return binary.op == '&' ? a & b : binary.op == '|' ? a | b : binary.op == '^' ? a ^ b : binary.op == '->' ? (1 - a) | b : a == b ? 1 : 0;
}
String bits(int row, int count) => count == 0 ? '' : row.toRadixString(2).padLeft(count, '0');
String assignmentText(List<String> names, int row) {
  final pattern = bits(row, names.length);
  return '{${[for (var i = 0; i < names.length; i++) '${names[i]}=${pattern[i]}'].join(' ')}}';
}
int literalCount(String pattern) => pattern.split('').where((c) => c != '-').length;
int patternCompare(String a, String b) {
  const rank = {'1': 0, '0': 1, '-': 2};
  for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return rank[a[i]]! - rank[b[i]]!; }
  return 0;
}
String flip(String pattern) => pattern.split('').map((c) => c == '-' ? '-' : c == '0' ? '1' : '0').join();
bool contains(String pattern, String row) {
  for (var i = 0; i < pattern.length; i++) { if (pattern[i] != '-' && pattern[i] != row[i]) return false; }
  return true;
}
String patternText(String pattern, List<String> names, bool product) {
  final literals = <String>[for (var i = 0; i < pattern.length; i++) if (pattern[i] != '-') '${pattern[i] == '0' ? '~' : ''}${names[i]}'];
  return literals.isEmpty ? product ? '1' : '0' : literals.join(product ? ' & ' : ' | ');
}
String coverText(List<String> patterns, List<String> names, bool product) {
  if (patterns.isEmpty) return product ? '0' : '1';
  return patterns.map((pattern) {
    final text = patternText(pattern, names, product);
    return !product && patterns.length >= 2 && literalCount(pattern) >= 2 ? '($text)' : text;
  }).join(product ? ' | ' : ' & ');
}
List<int> coefficients(List<int> values) {
  final result = List<int>.of(values);
  for (var bit = 1; bit < values.length; bit *= 2) {
    for (var row = 0; row < values.length; row++) { if ((row & bit) != 0) result[row] ^= result[row ^ bit]; }
  }
  return result;
}

List<String> minimize(List<String> names, List<int> on, List<int> dc, bool pos) {
  var stage = [...on, ...dc].map((row) => bits(row, names.length)).toSet();
  final primes = <String>[], output = <String>[];
  for (var number = 0;; number++) {
    final used = <String>{}, next = <String>{};
    for (final pattern in stage) {
      for (var i = 0; i < pattern.length; i++) {
        if (pattern[i] != '0') continue;
        final partner = '${pattern.substring(0, i)}1${pattern.substring(i + 1)}';
        if (stage.contains(partner)) {
          used.addAll([pattern, partner]);
          next.add('${pattern.substring(0, i)}-${pattern.substring(i + 1)}');
        }
      }
    }
    final current = stage.where((pattern) => !used.contains(pattern)).toList();
    primes.addAll(current);
    if (!pos) output.add('stage $number: implicants ${stage.length} primes ${current.length}');
    if (next.isEmpty) break;
    stage = next;
  }
  final rows = on.map((row) => bits(row, names.length)).toList();
  final target = primes.where((pattern) => rows.any((row) => contains(pattern, row))).toList()..sort(patternCompare);
  final masks = <BigInt>[];
  for (final pattern in target) {
    var mask = BigInt.zero;
    for (var i = 0; i < rows.length; i++) { if (contains(pattern, rows[i])) mask |= BigInt.one << i; }
    masks.add(mask);
  }
  final essential = <int>{};
  for (var i = 0; i < rows.length; i++) {
    final candidates = <int>[for (var j = 0; j < target.length; j++) if ((masks[j] & (BigInt.one << i)) != BigInt.zero) j];
    if (candidates.length == 1) essential.add(candidates.first);
  }
  final fixed = essential.toList(), optional = <int>[for (var i = 0; i < target.length; i++) if (!essential.contains(i)) i];
  final full = (BigInt.one << rows.length) - BigInt.one;
  List<int>? best;
  var bestLiterals = 0;
  List<String> ordered(List<int> indices) => indices.map((i) => pos ? flip(target[i]) : target[i]).toList()..sort(patternCompare);
  bool better(List<int> candidate, int literals) {
    final previous = best;
    if (previous == null || candidate.length != previous.length) return previous == null || candidate.length < previous.length;
    if (literals != bestLiterals) return literals < bestLiterals;
    final a = ordered(candidate), b = ordered(previous);
    for (var i = 0; i < a.length; i++) {
      final order = patternCompare(a[i], b[i]);
      if (order != 0) return order < 0;
    }
    return false;
  }
  for (var subset = 0; subset < (1 << optional.length); subset++) {
    final candidate = List<int>.of(fixed);
    var covered = BigInt.zero, literals = 0;
    for (var i = 0; i < optional.length; i++) { if ((subset & (1 << i)) != 0) candidate.add(optional[i]); }
    final previous = best;
    if (previous != null && candidate.length > previous.length) continue;
    for (final index in candidate) { covered |= masks[index]; literals += literalCount(target[index]); }
    if (covered == full && better(candidate, literals)) { best = candidate; bestLiterals = literals; }
  }
  final chosen = ordered(best!);
  if (pos) return ['minimal: ${coverText(chosen, names, false)}', 'clauses ${chosen.length} literals $bestLiterals'];
  final primeText = target.map((pattern) => patternText(pattern, names, true)).join(', ');
  final essentials = fixed.map((i) => target[i]).toList()..sort(patternCompare);
  final essentialText = essentials.map((pattern) => patternText(pattern, names, true)).join(', ');
  output.addAll(['primes: ${primeText.isEmpty ? 'none' : primeText}', 'essential: ${essentialText.isEmpty ? 'none' : essentialText}', 'minimal: ${coverText(chosen, names, true)}', 'terms ${chosen.length} literals $bestLiterals']);
  return output;
}
String? mergeClauses(String a, String b) {
  var result = '';
  for (var i = 0; i < a.length; i++) {
    if (a[i] != '-' && b[i] != '-' && a[i] != b[i]) return null;
    result += a[i] == '-' ? b[i] : a[i];
  }
  return result;
}
List<String> tidy(List<String> patterns) {
  final unique = patterns.toSet().toList();
  bool includes(String pattern, String other) {
    for (var i = 0; i < pattern.length; i++) { if (other[i] != '-' && other[i] != pattern[i]) return false; }
    return true;
  }
  return unique.where((pattern) => !unique.any((other) => literalCount(other) < literalCount(pattern) && includes(pattern, other))).toList();
}
List<String> clauses(Formula node, List<String> names, [Map<Formula, List<String>>? memo]) {
  final cache = memo ?? <Formula, List<String>>{};
  final cached = cache[node];
  if (cached != null) return cached;
  final result = clausesCompute(node, names, cache);
  cache[node] = result;
  return result;
}
List<String> clausesCompute(Formula node, List<String> names, Map<Formula, List<String>> cache) {
  if (node is Constant) return node.value == 1 ? [] : ['-' * names.length];
  if (node is Variable || node is Negation) {
    final name = node is Variable ? node.name : ((node as Negation).child as Variable).name;
    final i = names.indexOf(name);
    return ['${'-' * i}${node is Negation ? '0' : '1'}${'-' * (names.length - i - 1)}'];
  }
  final binary = node as Binary, a = clauses(binary.left, names, cache), b = clauses(binary.right, names, cache);
  if (binary.op == '&') return tidy([...a, ...b]);
  final merged = <String>[];
  for (final x in a) {
    for (final y in b) { final value = mergeClauses(x, y); if (value != null) merged.add(value); }
  }
  return tidy(merged);
}
class BDDNode {
  final int index, lo, hi;
  BDDNode(this.index, this.lo, this.hi);
}

class Workbench {
  final definitions = <String, Formula>{};
  List<String> define(String name, Formula formula) {
    final output = '${definitions.containsKey(name) ? 'redefined' : 'defined'} $name = ${notation(formula)}';
    definitions[name] = formula;
    return [output];
  }
  List<String> command(String line) {
    final split = line.indexOf(' '), command = split < 0 ? line : line.substring(0, split);
    final argument = split < 0 ? '' : line.substring(split + 1), start = command.length + 2;
    final single = 'PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY MINIMIZE MINPOS KMAP SAT TAUT COUNT PROPS BDD CLAUSES DP'.split(' ').toSet();
    const divided = {'RESTRICT', 'COFACTOR', 'MINDC', 'EQUIV', 'IMPLIES'};
    if (!single.contains(command) && !divided.contains(command) && !['DEF', 'DEFSUM', 'DEL', 'LIST'].contains(command)) fail('unknown command $command');
    if (command == 'LIST' && split >= 0) fail('unexpected argument');
    if (command != 'LIST' && split < 0) fail('missing argument');
    final separator = argument.indexOf(';');
    if (divided.contains(command) && separator < 0) fail("missing ';'");
    bool validName(String name) => RegExp(r'^[a-z][a-z0-9]{0,7}$').hasMatch(name);
    List<String> words(String text) => text.split(' ').where((word) => word.isNotEmpty).toList();
    if (command == 'LIST') {
      final names = definitions.keys.toList()..sort();
      return ['names: ${definitions.length}', ...names.map((name) => '$name = ${notation(definitions[name]!)}')];
    }
    if (command == 'DEL') {
      if (!validName(argument)) fail("invalid name '$argument'");
      if (!definitions.containsKey(argument)) fail("undefined name '$argument'");
      definitions.remove(argument);
      return ['deleted $argument'];
    }
    if (command == 'DEF') {
      final space = argument.indexOf(' ');
      if (space < 0) fail('missing argument');
      final name = argument.substring(0, space);
      if (!validName(name)) fail("invalid name '$name'");
      return define(name, parseFormula(argument.substring(space + 1), name.length + 6, definitions));
    }
    if (command == 'DEFSUM') {
      if (separator < 0) fail("missing ';'");
      final front = words(argument.substring(0, separator)), back = words(argument.substring(separator + 1));
      if (front.isEmpty) fail('missing argument');
      final name = front[0], names = front.sublist(1);
      if (!validName(name)) fail("invalid name '$name'");
      if (names.isEmpty) fail('bad variable list');
      for (var i = 0; i < names.length; i++) {
        if (!RegExp(r'^[A-Z]$').hasMatch(names[i]) || i > 0 && names[i - 1].compareTo(names[i]) >= 0) fail('bad variable list');
      }
      if (names.length >= 9) fail('too many variables: ${names.length}');
      final rows = <int>[];
      var previous = -1;
      for (final word in back) {
        if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(word) || int.parse(word) >= (1 << names.length) || int.parse(word) <= previous) fail("bad minterm '$word'");
        previous = int.parse(word); rows.add(previous);
      }
      Formula? formula;
      for (final row in rows) {
        final pattern = bits(row, names.length);
        Formula? term;
        for (var i = 0; i < names.length; i++) {
          final literal = pattern[i] == '1' ? Variable(names[i]) : Negation(Variable(names[i]));
          term = term == null ? literal : Binary('&', term, literal);
        }
        formula = formula == null ? term : Binary('|', formula, term!);
      }
      return define(name, formula ?? Constant(0));
    }
    final formula = parseFormula(divided.contains(command) ? argument.substring(0, separator) : argument, start, definitions);
    final back = divided.contains(command) ? argument.substring(separator + 1) : '';
    Formula? second;
    if (['MINDC', 'EQUIV', 'IMPLIES'].contains(command)) second = parseFormula(back, start + separator + 1, definitions);
    if (command == 'RESTRICT') {
      final assignments = words(back), replacements = <String, int>{};
      if (assignments.isEmpty) fail('missing assignment');
      for (final assignment in assignments) {
        if (!RegExp(r'^[A-Z]=[01]$').hasMatch(assignment)) fail("bad assignment '$assignment'");
        if (replacements.containsKey(assignment[0])) fail('duplicate variable ${assignment[0]}');
        replacements[assignment[0]] = int.parse(assignment[2]);
      }
      return ['restricted: ${notation(simplify(formula, replacements))}'];
    }
    if (command == 'COFACTOR') {
      final list = words(back);
      if (list.length != 1 || !RegExp(r'^[A-Z]$').hasMatch(list[0])) fail('bad variable');
      final name = list[0], one = simplify(formula, {list[0]: 1}), zero = simplify(formula, {list[0]: 0});
      return ['cofactor $name=1: ${notation(one)}', 'cofactor $name=0: ${notation(zero)}', 'difference: ${notation(simplifyBinary('^', one, zero))}'];
    }
    final names = variables([formula, if (second != null) second]);
    if (command == 'PRINT') {
      final info = measure(formula);
      return ['formula: ${notation(formula)}', 'variables: ${names.isEmpty ? 'none' : names.join(' ')}', 'size ${info.$1} depth ${info.$2}'];
    }
    if (command == 'NNF') return ['nnf: ${notation(nnf(formula))}'];
    if (command == 'DUAL') return ['dual: ${notation(dual(formula))}'];
    if (command == 'SIMPLIFY') return ['simplified: ${notation(simplify(formula))}'];
    if (command == 'CLAUSES' || command == 'DP') {
      var set = clauses(nnf(formula), names);
      if (command == 'CLAUSES') return ['clauses: ${coverText(set..sort(patternCompare), names, false)}'];
      final output = ['start: clauses ${set.length}'], empty = '-' * names.length;
      for (var i = 0; i < names.length; i++) {
        if (set.isEmpty || set.contains(empty)) break;
        final positive = set.where((pattern) => pattern[i] == '1').toList(), negative = set.where((pattern) => pattern[i] == '0').toList();
        final resolvents = <String>{};
        for (final a in positive) {
          for (final b in negative) {
            final value = mergeClauses('${a.substring(0, i)}-${a.substring(i + 1)}', '${b.substring(0, i)}-${b.substring(i + 1)}');
            if (value != null) resolvents.add(value);
          }
        }
        set = tidy([...set.where((pattern) => pattern[i] == '-'), ...resolvents]);
        output.add('eliminate ${names[i]}: resolvents ${resolvents.length} clauses ${set.length}');
      }
      output.add('result: ${set.contains(empty) ? 'unsatisfiable' : 'satisfiable'}');
      return output;
    }
    if (names.length >= 9) fail('too many variables: ${names.length}');
    if (command == 'KMAP' && (names.length < 2 || names.length > 4)) fail('kmap needs 2 to 4 variables');
    final values = List.generate(1 << names.length, (row) => evaluate(formula, names, row));
    final on = <int>[for (var row = 0; row < values.length; row++) if (values[row] == 1) row];
    final off = <int>[for (var row = 0; row < values.length; row++) if (values[row] == 0) row];
    if (command == 'TABLE') {
      return ['${names.isEmpty ? '' : '${names.join(' ')} '}| F', for (var row = 0; row < values.length; row++) '${names.isEmpty ? '' : '${bits(row, names.length).split('').join(' ')} '}| ${values[row]}'];
    }
    if (command == 'MINTERMS' || command == 'MAXTERMS') {
      final rows = command == 'MINTERMS' ? on : off;
      return ['${command == 'MINTERMS' ? 'minterms' : 'maxterms'}: ${rows.isEmpty ? 'none' : rows.join(' ')}'];
    }
    if (command == 'DNF') return ['dnf: ${coverText(on.map((row) => bits(row, names.length)).toList(), names, true)}'];
    if (command == 'CNF') return ['cnf: ${coverText(off.map((row) => flip(bits(row, names.length))).toList(), names, false)}'];
    final anf = coefficients(values);
    if (command == 'ANF') {
      final patterns = <String>[for (var row = 0; row < anf.length; row++) if (anf[row] == 1) bits(row, names.length).replaceAll('0', '-')];
      patterns.sort((a, b) { final order = literalCount(a).compareTo(literalCount(b)); return order != 0 ? order : patternCompare(a, b); });
      return ['anf: ${patterns.isEmpty ? '0' : patterns.map((pattern) => patternText(pattern, names, true)).join(' ^ ')}'];
    }
    if (command == 'SAT') return on.isEmpty ? ['unsatisfiable'] : ['satisfiable: ${assignmentText(names, on.first)}'];
    if (command == 'TAUT') return off.isEmpty ? ['tautology'] : ['not a tautology: ${assignmentText(names, off.first)}'];
    if (command == 'COUNT') return ['models: ${on.length} of ${values.length}'];
    if (command == 'EQUIV' || command == 'IMPLIES') {
      for (var row = 0; row < values.length; row++) {
        final a = values[row], b = evaluate(second!, names, row);
        if (command == 'EQUIV' && a != b) return ['not equivalent: ${assignmentText(names, row)} f=$a g=$b'];
        if (command == 'IMPLIES' && a == 1 && b == 0) return ['does not imply: ${assignmentText(names, row)}'];
      }
      return [command == 'EQUIV' ? 'equivalent' : 'implies'];
    }
    if (command == 'MINIMIZE' || command == 'MINPOS') return minimize(names, command == 'MINPOS' ? off : on, [], command == 'MINPOS');
    if (command == 'MINDC') {
      final dc = <int>[for (var row = 0; row < values.length; row++) if (evaluate(second!, names, row) == 1) row], ignored = <int>{};
      ignored.addAll(dc);
      return minimize(names, on.where((row) => !ignored.contains(row)).toList(), dc, false);
    }
    if (command == 'KMAP') {
      final p = names.length ~/ 2, q = names.length - p, label = '${names.sublist(0, p).join()}\\${names.sublist(p).join()}';
      final rows = List.generate(1 << p, (i) => i ^ (i >> 1)), columns = List.generate(1 << q, (i) => i ^ (i >> 1));
      return [label + columns.map((column) => ' ${bits(column, q)}').join(), ...rows.map((row) => bits(row, p).padRight(label.length, ' ') + columns.map((column) => '${' ' * q}${values[row * (1 << q) + column]}').join())];
    }
    if (command == 'PROPS') {
      final depends = <String>[], weights = <int, int>{};
      var monotone = true, symmetric = true;
      for (var i = 0; i < names.length; i++) {
        final bit = 1 << (names.length - 1 - i);
        var dependent = false;
        for (var row = 0; row < values.length; row++) {
          if (values[row] != values[row ^ bit]) dependent = true;
          if ((row & bit) == 0 && values[row] > values[row | bit]) monotone = false;
        }
        if (dependent) depends.add(names[i]);
      }
      for (var row = 0; row < values.length; row++) {
        final count = bits(row, names.length).split('').where((c) => c == '1').length;
        if (weights.containsKey(count) && weights[count] != values[row]) symmetric = false;
        weights[count] = values[row];
      }
      var selfDual = true, linear = true;
      for (var row = 0; row < values.length; row++) {
        if (values[row] == values[values.length - 1 - row]) selfDual = false;
        if (anf[row] == 1 && (row & (row - 1)) != 0) linear = false;
      }
      String yes(bool value) => value ? 'yes' : 'no';
      return ['depends: ${depends.isEmpty ? 'none' : depends.join(' ')}', 'zero-preserving: ${yes(values[0] == 0)}', 'one-preserving: ${yes(values.last == 1)}', 'self-dual: ${yes(selfDual)}', 'monotone: ${yes(monotone)}', 'linear: ${yes(linear)}', 'symmetric: ${yes(symmetric)}'];
    }
    final nodes = <BDDNode>[], unique = <String, int>{};
    int build(int index, List<int> list) {
      if (index == names.length) return list[0];
      final half = list.length ~/ 2;
      final lo = build(index + 1, list.sublist(0, half)), hi = build(index + 1, list.sublist(half));
      if (lo == hi) return lo;
      final key = '$index,$lo,$hi';
      if (unique.containsKey(key)) return unique[key]!;
      final id = nodes.length + 2;
      nodes.add(BDDNode(index, lo, hi)); unique[key] = id;
      return id;
    }
    final root = build(0, values), memo = <int, int>{0: 0, 1: 1};
    int paths(int id) {
      if (memo.containsKey(id)) return memo[id]!;
      final node = nodes[id - 2];
      final count = paths(node.lo) + paths(node.hi);
      memo[id] = count;
      return count;
    }
    return ['nodes: ${nodes.length}', for (var i = 0; i < nodes.length; i++) '${i + 2} = ite(${names[nodes[i].index]}, ${nodes[i].hi}, ${nodes[i].lo})', 'root: $root', 'paths: ${paths(root)}'];
  }
}

void main() {
  final n = int.parse(stdin.readLineSync()!), workbench = Workbench(), output = <String>[];
  for (var i = 0; i < n; i++) {
    final line = stdin.readLineSync()!;
    try { output.addAll(workbench.command(line)); }
    on Problem catch (error) { output.add('error: ${error.reason}'); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
