part of 'main.dart';

class Expression {
  final String word;
  final List<Expression> list;
  Expression({this.word = '', this.list = const []});
}

List<Expression> expressions(String path) {
  final tokens = <String>[];
  for (final line in lines(path)) {
    final text = line
        .split(';')
        .first
        .replaceAll('(', ' ( ')
        .replaceAll(')', ' ) ');
    tokens.addAll(text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty));
  }
  var at = 0;
  Expression read() {
    final token = tokens[at++];
    if (token != '(') return Expression(word: token);
    final list = <Expression>[];
    while (tokens[at] != ')') {
      list.add(read());
    }
    at++;
    return Expression(list: list);
  }

  final out = <Expression>[];
  while (at < tokens.length) {
    out.add(read());
  }
  return out;
}

List<String> words(List<Expression> expressions) =>
    expressions.map((e) => e.word).toList();

class Typed {
  final String name, type;
  Typed(this.name, this.type);
}

List<Typed> typedList(List<String> tokens) {
  final out = <Typed>[];
  var pending = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] == '-') {
      i++;
      for (final name in pending) {
        out.add(Typed(name, tokens[i]));
      }
      pending = [];
    } else {
      pending.add(tokens[i]);
    }
  }
  for (final name in pending) {
    out.add(Typed(name, 'object'));
  }
  return out;
}

class Atom {
  final String predicate;
  final List<String> terms;
  Atom(this.predicate, this.terms);
  String text() => '($predicate${terms.isEmpty ? '' : ' ${terms.join(' ')}'})';
}

Atom parseAtom(Expression e) =>
    Atom(e.list.first.word, words(e.list.sublist(1)));

class Literal {
  final Atom atom;
  final bool negative;
  Literal(this.atom, [this.negative = false]);
  String text() => negative ? '(not ${atom.text()})' : atom.text();
}

Literal literal(Expression e) => e.list.first.word == 'not'
    ? Literal(parseAtom(e.list[1]), true)
    : Literal(parseAtom(e));
List<Expression> conjunction(Expression e) =>
    e.list.isNotEmpty && e.list.first.word == 'and' ? e.list.sublist(1) : [e];

class Predicate {
  final String name;
  final List<String> types;
  Predicate(this.name, this.types);
}

class Schema {
  final String name;
  List<Typed> parameters = [];
  final List<Literal> conditions = [], effects = [];
  int cost = 1;
  Schema(this.name);
}

class Domain {
  final String name;
  final List<String> types = ['object'];
  final Map<String, String> parents = {};
  final List<Predicate> predicates = [];
  final Map<String, int> predicateIndex = {};
  List<Schema> actions = [];
  final Set<String> fluent = {};
  final List<String> diagnostics = [];
  Domain(this.name);
}

class Problem {
  final String name;
  List<Typed> objects = [];
  List<Atom> initial = [], goals = [];
  final List<String> diagnostics = [];
  Problem(this.name);
}

Domain readDomain() {
  final e = expressions('input/domain.txt').first,
      d = Domain(e.list[1].list[1].word);
  for (final section in e.list.skip(2)) {
    final a = section.list;
    switch (a[0].word) {
      case ':types':
        {
          final tokens = words(a.sublist(1)), seen = {'object'};
          for (final t in tokens) {
            if (t != '-' && seen.add(t)) {
              d.types.add(t);
              d.parents[t] = 'object';
            }
          }
          for (final t in typedList(tokens)) {
            d.parents[t.name] = t.type;
          }
          break;
        }
      case ':predicates':
        for (final declaration in a.skip(1)) {
          final p = Predicate(
            declaration.list.first.word,
            typedList(
              words(declaration.list.sublist(1)),
            ).map((t) => t.type).toList(),
          );
          d.predicateIndex[p.name] = d.predicates.length;
          d.predicates.add(p);
        }
        break;
      case ':action':
        {
          final schema = Schema(a[1].word);
          for (var i = 2; i < a.length; i += 2) {
            switch (a[i].word) {
              case ':parameters':
                schema.parameters = typedList(words(a[i + 1].list));
                break;
              case ':precondition':
                schema.conditions.addAll(conjunction(a[i + 1]).map(literal));
                break;
              case ':effect':
                for (final e in conjunction(a[i + 1])) {
                  if (e.list.first.word == 'increase') {
                    schema.cost = int.parse(e.list[2].word);
                  } else {
                    schema.effects.add(literal(e));
                  }
                }
                break;
            }
          }
          d.actions.add(schema);
          break;
        }
    }
  }
  return d;
}

List<Problem> readProblems() {
  final out = <Problem>[];
  for (final e in expressions('input/problems.txt')) {
    final p = Problem(e.list[1].list[1].word);
    for (final section in e.list.skip(2)) {
      final a = section.list;
      switch (a[0].word) {
        case ':objects':
          p.objects = typedList(words(a.sublist(1)));
          break;
        case ':init':
          p.initial.addAll(a.skip(1).map(parseAtom));
          break;
        case ':goal':
          p.goals.addAll(conjunction(a[1]).map(parseAtom));
          break;
      }
    }
    out.add(p);
  }
  return out;
}

List<String> lines(String path) => File(path).readAsLinesSync();
