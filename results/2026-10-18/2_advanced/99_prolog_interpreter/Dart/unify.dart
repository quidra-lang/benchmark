part of 'main.dart';

class Bindings {
  final List<Term> trail = [];
  int get mark => trail.length;
  void undo(int mark) {
    while (trail.length > mark) trail.removeLast().binding = null;
  }

  void bind(Term variable, Term term) {
    variable.binding = term;
    trail.add(variable);
  }

  bool unify(Term first, Term second) {
    final pairs = [(first, second)];
    while (pairs.isNotEmpty) {
      final pair = pairs.removeLast();
      final x = dereference(pair.$1), y = dereference(pair.$2);
      if (identical(x, y)) continue;
      if (x.kind == 'variable') {
        bind(x, y);
        continue;
      }
      if (y.kind == 'variable') {
        bind(y, x);
        continue;
      }
      if (x.kind != y.kind) return false;
      switch (x.kind) {
        case 'integer':
          if (x.integer != y.integer) return false;
        case 'atom':
          if (x.name != y.name) return false;
        case 'compound':
          if (x.name != y.name || x.arguments.length != y.arguments.length)
            return false;
          for (var i = x.arguments.length - 1; i >= 0; i--)
            pairs.add((x.arguments[i], y.arguments[i]));
      }
    }
    return true;
  }
}

bool identicalTerms(Term first, Term second) {
  final pairs = [(first, second)];
  while (pairs.isNotEmpty) {
    final pair = pairs.removeLast();
    final x = dereference(pair.$1), y = dereference(pair.$2);
    if (identical(x, y)) continue;
    if (x.kind != y.kind) return false;
    switch (x.kind) {
      case 'variable':
        return false;
      case 'integer':
        if (x.integer != y.integer) return false;
      case 'atom':
        if (x.name != y.name) return false;
      case 'compound':
        if (x.name != y.name || x.arguments.length != y.arguments.length)
          return false;
        for (var i = x.arguments.length - 1; i >= 0; i--)
          pairs.add((x.arguments[i], y.arguments[i]));
    }
  }
  return true;
}
