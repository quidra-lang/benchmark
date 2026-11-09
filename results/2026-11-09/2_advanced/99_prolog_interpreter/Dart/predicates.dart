part of 'main.dart';

class BuiltinIssue implements Exception {
  final Term term;
  BuiltinIssue(this.term);
}

Never predicateError(Term term) => throw BuiltinIssue(term);
int integerCheck(Term term) {
  term = dereference(term);
  if (term.kind == 'variable') predicateError(atom('instantiation_error'));
  if (term.kind != 'integer')
    predicateError(errorTerm('type_error', [atom('integer'), term]));
  return term.integer;
}

String atomCheck(Term term) {
  term = dereference(term);
  if (term.kind == 'variable') predicateError(atom('instantiation_error'));
  if (term.kind != 'atom')
    predicateError(errorTerm('type_error', [atom('atom'), term]));
  return term.name;
}

List<Term> properListCheck(Term term) {
  final (elements, tail) = listParts(term);
  if (tail.kind == 'variable') predicateError(atom('instantiation_error'));
  if (!isNil(tail))
    predicateError(errorTerm('type_error', [atom('list'), term]));
  return elements;
}

int arithmeticValue(Term term) {
  term = dereference(term);
  if (term.kind == 'variable') predicateError(atom('instantiation_error'));
  if (term.kind == 'integer') return term.integer;
  final predicate = indicator(term);
  final valid =
      predicate.arity == 2 &&
          {
            '+',
            '-',
            '*',
            '//',
            'mod',
            'rem',
            'min',
            'max',
          }.contains(predicate.name) ||
      predicate.arity == 1 && {'-', 'abs'}.contains(predicate.name);
  if (!valid)
    predicateError(
      errorTerm('type_error', [atom('evaluable'), indicatorTerm(predicate)]),
    );
  final a = arithmeticValue(term.arguments[0]);
  var result = 0;
  if (predicate.arity == 1) {
    result = predicate.name == 'abs' ? a.abs() : -a;
  } else {
    final b = arithmeticValue(term.arguments[1]);
    switch (predicate.name) {
      case '+':
        result = a + b;
      case '-':
        result = a - b;
      case '*':
        result = a * b;
      case '//':
      case 'mod':
      case 'rem':
        if (b == 0)
          predicateError(errorTerm('evaluation_error', [atom('zero_divisor')]));
        var quotient = a ~/ b;
        if (predicate.name == '//') {
          result = quotient;
        } else {
          if (predicate.name == 'mod' &&
              a - (a ~/ b) * b != 0 &&
              (a < 0) != (b < 0))
            quotient--;
          result = a - b * quotient;
        }
      case 'min':
        result = min(a, b);
      case 'max':
        result = max(a, b);
    }
  }
  if (result < -2147483648 || result > 2147483647)
    predicateError(errorTerm('evaluation_error', [atom('int_overflow')]));
  return result;
}

const deterministicIndicators = <Indicator>{
  ('true', 0),
  ('fail', 0),
  ('false', 0),
  ('=', 2),
  (r'\=', 2),
  ('==', 2),
  (r'\==', 2),
  ('var', 1),
  ('nonvar', 1),
  ('atom', 1),
  ('number', 1),
  ('integer', 1),
  ('atomic', 1),
  ('compound', 1),
  ('callable', 1),
  ('is_list', 1),
  ('is', 2),
  ('=:=', 2),
  (r'=\=', 2),
  ('<', 2),
  ('>', 2),
  ('=<', 2),
  ('>=', 2),
  ('functor', 3),
  ('arg', 3),
  ('=..', 2),
  ('copy_term', 2),
  ('atom_length', 2),
  ('atom_chars', 2),
  ('write', 1),
  ('writeq', 1),
  ('nl', 0),
};
bool deterministic(Term goal, Bindings bindings, StringBuffer output) {
  final predicate = indicator(goal);
  final args = goal.arguments;
  Term argument(int i) => dereference(args[i]);
  switch (predicate.name) {
    case 'true':
      return true;
    case 'fail':
    case 'false':
      return false;
    case '=':
      return bindings.unify(args[0], args[1]);
    case r'\=':
      final mark = bindings.mark;
      final success = bindings.unify(args[0], args[1]);
      bindings.undo(mark);
      return !success;
    case '==':
      return identicalTerms(args[0], args[1]);
    case r'\==':
      return !identicalTerms(args[0], args[1]);
    case 'var':
      return argument(0).kind == 'variable';
    case 'nonvar':
      return argument(0).kind != 'variable';
    case 'atom':
      return argument(0).kind == 'atom';
    case 'number':
    case 'integer':
      return argument(0).kind == 'integer';
    case 'atomic':
      return argument(0).kind == 'atom' || argument(0).kind == 'integer';
    case 'compound':
      return argument(0).kind == 'compound';
    case 'callable':
      return argument(0).kind == 'atom' || argument(0).kind == 'compound';
    case 'is_list':
      return isNil(listParts(args[0]).$2);
    case 'is':
      return bindings.unify(args[0], integer(arithmeticValue(args[1])));
    case '=:=':
    case r'=\=':
    case '<':
    case '>':
    case '=<':
    case '>=':
      final x = arithmeticValue(args[0]), y = arithmeticValue(args[1]);
      return switch (predicate.name) {
        '=:=' => x == y,
        r'=\=' => x != y,
        '<' => x < y,
        '>' => x > y,
        '=<' => x <= y,
        _ => x >= y,
      };
    case 'functor':
      {
        final term = argument(0), name = argument(1), arity = argument(2);
        if (term.kind != 'variable') {
          if (term.kind == 'compound')
            return bindings.unify(args[1], atom(term.name)) &&
                bindings.unify(args[2], integer(term.arguments.length));
          return bindings.unify(args[1], term) &&
              bindings.unify(args[2], integer(0));
        }
        if (name.kind == 'variable' || arity.kind == 'variable')
          predicateError(atom('instantiation_error'));
        if (name.kind == 'compound')
          predicateError(errorTerm('type_error', [atom('atomic'), name]));
        if (arity.kind != 'integer')
          predicateError(errorTerm('type_error', [atom('integer'), arity]));
        if (arity.integer < 0)
          predicateError(
            errorTerm('domain_error', [atom('not_less_than_zero'), arity]),
          );
        if (arity.integer > 255)
          predicateError(
            errorTerm('representation_error', [atom('max_arity')]),
          );
        if (arity.integer == 0) return bindings.unify(args[0], name);
        if (name.kind == 'integer')
          predicateError(errorTerm('type_error', [atom('atom'), name]));
        return bindings.unify(
          args[0],
          compound(name.name, [
            for (var i = 0; i < arity.integer; i++) variable(),
          ]),
        );
      }
    case 'arg':
      {
        final n = argument(0), term = argument(1);
        if (n.kind == 'variable' || term.kind == 'variable')
          predicateError(atom('instantiation_error'));
        if (n.kind != 'integer')
          predicateError(errorTerm('type_error', [atom('integer'), n]));
        if (term.kind != 'compound')
          predicateError(errorTerm('type_error', [atom('compound'), term]));
        if (n.integer < 1 || n.integer > term.arguments.length) return false;
        return bindings.unify(term.arguments[n.integer - 1], args[2]);
      }
    case '=..':
      {
        final term = argument(0);
        if (term.kind == 'compound')
          return bindings.unify(
            makeList([atom(term.name), ...term.arguments]),
            args[1],
          );
        if (term.kind != 'variable')
          return bindings.unify(makeList([term]), args[1]);
        final elements = properListCheck(args[1]);
        if (elements.isEmpty)
          predicateError(
            errorTerm('domain_error', [atom('non_empty_list'), atom('[]')]),
          );
        final head = dereference(elements.first);
        if (head.kind == 'variable')
          predicateError(atom('instantiation_error'));
        if (elements.length == 1) {
          if (head.kind == 'compound')
            predicateError(errorTerm('type_error', [atom('atomic'), head]));
          return bindings.unify(args[0], head);
        }
        if (head.kind != 'atom')
          predicateError(errorTerm('type_error', [atom('atom'), head]));
        if (elements.length - 1 > 255)
          predicateError(
            errorTerm('representation_error', [atom('max_arity')]),
          );
        return bindings.unify(
          args[0],
          compound(head.name, elements.skip(1).toList()),
        );
      }
    case 'copy_term':
      return bindings.unify(copyTerm(args[0]), args[1]);
    case 'atom_length':
      final name = atomCheck(args[0]);
      final n = argument(1);
      if (n.kind != 'variable' && n.kind != 'integer')
        predicateError(errorTerm('type_error', [atom('integer'), n]));
      return bindings.unify(integer(name.length), args[1]);
    case 'atom_chars':
      {
        final term = argument(0);
        if (term.kind != 'variable') {
          final name = atomCheck(term);
          return bindings.unify(
            args[1],
            makeList([for (var i = 0; i < name.length; i++) atom(name[i])]),
          );
        }
        final elements = properListCheck(args[1]);
        final name = StringBuffer();
        for (final element in elements) {
          final value = dereference(element);
          if (value.kind == 'variable')
            predicateError(atom('instantiation_error'));
          if (value.kind != 'atom' || value.name.length != 1)
            predicateError(errorTerm('type_error', [atom('character'), value]));
          name.write(value.name);
        }
        return bindings.unify(args[0], atom(name.toString()));
      }
    case 'write':
    case 'writeq':
      output.write(
        Writer(predicate.name == 'writeq').write(args[0], 1200, false),
      );
      return true;
    case 'nl':
      output.write('\n');
      return true;
  }
  throw StateError('unknown deterministic predicate');
}
