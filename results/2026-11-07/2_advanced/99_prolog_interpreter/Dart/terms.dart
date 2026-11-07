part of 'main.dart';

class Term {
  final String kind, name;
  final int integer;
  final List<Term> arguments;
  Term? binding;
  Term(
    this.kind, {
    this.name = '',
    this.integer = 0,
    this.arguments = const [],
  });
}

Term atom(String name) => Term('atom', name: name);
Term integer(int n) => Term('integer', integer: n);
Term variable() => Term('variable');
Term compound(String name, List<Term> args) =>
    Term('compound', name: name, arguments: args);
Term dereference(Term term) {
  while (term.kind == 'variable' && term.binding != null) term = term.binding!;
  return term;
}

bool isCompound(Term term, String name, int arity) {
  term = dereference(term);
  return term.kind == 'compound' &&
      term.name == name &&
      term.arguments.length == arity;
}

bool isNil(Term term) {
  term = dereference(term);
  return term.kind == 'atom' && term.name == '[]';
}

Term makeList(List<Term> elements, [Term? tail]) {
  var result = tail ?? atom('[]');
  for (final element in elements.reversed)
    result = compound('.', [element, result]);
  return result;
}

(List<Term>, Term) listParts(Term term) {
  final elements = <Term>[];
  term = dereference(term);
  while (isCompound(term, '.', 2)) {
    elements.add(term.arguments[0]);
    term = dereference(term.arguments[1]);
  }
  return (elements, term);
}

class Copier {
  final Map<Term, Term> variables = Map.identity();
  Term copy(Term term) {
    term = dereference(term);
    if (term.kind == 'variable') return variables.putIfAbsent(term, variable);
    if (term.kind != 'compound') return term;
    return compound(term.name, term.arguments.map(copy).toList());
  }
}

Term copyTerm(Term term) => Copier().copy(term);
List<Term> termVariables(Term term) {
  final result = <Term>[];
  void walk(Term term) {
    term = dereference(term);
    if (term.kind == 'variable') {
      result.add(term);
    } else if (term.kind == 'compound') {
      for (final arg in term.arguments) walk(arg);
    }
  }

  walk(term);
  return result;
}

typedef Indicator = (String, int);

extension IndicatorProperties on Indicator {
  String get name => $1;
  int get arity => $2;
}

Indicator indicator(Term term) {
  term = dereference(term);
  return (term.name, term.kind == 'atom' ? 0 : term.arguments.length);
}

Term indicatorTerm(Indicator predicate) =>
    compound('/', [atom(predicate.name), integer(predicate.arity)]);
Term errorTerm(String kind, [List<Term> args = const []]) =>
    args.isEmpty ? atom(kind) : compound(kind, args);
Term errorBall(Term error, Indicator predicate) =>
    compound('error', [error, indicatorTerm(predicate)]);
