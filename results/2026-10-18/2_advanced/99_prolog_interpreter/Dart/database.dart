part of 'main.dart';

class Clause {
  final Term head;
  final Term? body;
  final String file;
  final int line;
  Clause(this.head, this.body, this.file, this.line);
}

class Predicate {
  final Indicator indicator;
  final List<Clause> clauses = [];
  Predicate(this.indicator);
  List<Clause> candidates(Term goal) => [
    for (final clause in clauses)
      if (indicator.arity == 0 ||
          sameKind(goal.arguments[0], clause.head.arguments[0]))
        clause,
  ];
}

class Database {
  final Map<Indicator, Predicate> predicates = {};
  Predicate ensure(Indicator indicator) =>
      predicates.putIfAbsent(indicator, () => Predicate(indicator));
}

bool sameKind(Term first, Term second) {
  final a = dereference(first), b = dereference(second);
  if (a.kind == 'variable' || b.kind == 'variable') return true;
  if (a.kind != b.kind) return false;
  return switch (a.kind) {
    'integer' => a.integer == b.integer,
    'atom' => a.name == b.name,
    'compound' => a.name == b.name && a.arguments.length == b.arguments.length,
    _ => false,
  };
}

(Term, Term?) copyClause(Clause clause) {
  final copier = Copier();
  return (
    copier.copy(clause.head),
    clause.body == null ? null : copier.copy(clause.body!),
  );
}
