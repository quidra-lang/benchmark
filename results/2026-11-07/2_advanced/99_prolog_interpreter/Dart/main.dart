import 'dart:io';
import 'dart:math';
part 'reader.dart';
part 'terms.dart';
part 'unify.dart';
part 'database.dart';
part 'predicates.dart';

bool operatorName(String name) =>
    infixOperators.containsKey(name) || prefixOperators.containsKey(name);

class Writer {
  final bool quoted;
  final Map<Term, String> names = Map.identity();
  int serial = 0;
  Writer(this.quoted);
  String atomName(String name) {
    if (!quoted) return name;
    var plain = {'[]', '!', ';'}.contains(name);
    if (name.isNotEmpty) {
      plain =
          plain ||
          lower(name.codeUnitAt(0)) && name.codeUnits.every(alphanumeric) ||
          name != '.' && name.codeUnits.every(symbol);
    }
    if (plain) return name;
    final out = StringBuffer("'");
    for (final c in name.codeUnits)
      out.write(switch (c) {
        92 => r'\\',
        39 => r"\'",
        10 => r'\n',
        9 => r'\t',
        _ => String.fromCharCode(c),
      });
    out.write("'");
    return out.toString();
  }

  String write(Term term, int limit, bool operand) {
    term = dereference(term);
    switch (term.kind) {
      case 'variable':
        return names.putIfAbsent(term, () => '_G${++serial}');
      case 'integer':
        return '${term.integer}';
      case 'atom':
        final name = atomName(term.name);
        return operand && operatorName(term.name) ? '($name)' : name;
    }
    if (isCompound(term, '.', 2)) {
      final (elements, tail) = listParts(term);
      return '[${elements.map((e) => write(e, 999, false)).join(',')}${isNil(tail) ? '' : '|${write(tail, 999, false)}'}]';
    }
    final op = infixOperators[term.name];
    if (op != null && term.arguments.length == 2) {
      final left = write(term.arguments[0], op.left, true),
          right = write(term.arguments[1], op.right, true);
      String value;
      if (term.name == ',') {
        value = '$left,$right';
      } else if (lower(term.name.codeUnitAt(0))) {
        value = '$left ${term.name} $right';
      } else {
        final before =
            left.isNotEmpty && symbol(left.codeUnitAt(left.length - 1))
            ? ' '
            : '';
        final after = right.isNotEmpty && symbol(right.codeUnitAt(0))
            ? ' '
            : '';
        value = '$left$before${term.name}$after$right';
      }
      return op.priority > limit ? '($value)' : value;
    }
    final priority = prefixOperators[term.name];
    if (priority != null && term.arguments.length == 1) {
      final arg = write(term.arguments[0], priority, true);
      final gap =
          arg.isNotEmpty &&
              (symbol(arg.codeUnitAt(0)) ||
                  digit(arg.codeUnitAt(0)) ||
                  arg[0] == '(')
          ? ' '
          : '';
      final value = '${term.name}$gap$arg';
      return priority > limit ? '($value)' : value;
    }
    return '${atomName(term.name)}(${term.arguments.map((a) => write(a, 999, false)).join(',')})';
  }
}

String termText(Term term) => Writer(true).write(term, 1200, false);
String indicatorText(Indicator predicate) => termText(indicatorTerm(predicate));
bool control(Indicator p) =>
    {
      (',', 2),
      ('!', 0),
      (';', 2),
      ('->', 2),
      (r'\+', 1),
      ('catch', 3),
    }.contains(p) ||
    p.name == 'call' && p.arity >= 1 && p.arity <= 8;
bool builtin(Indicator p) =>
    deterministicIndicators.contains(p) ||
    {('findall', 3), ('throw', 1), ('between', 3), ('length', 2)}.contains(p);
Term? goalConversion(Term term) {
  term = dereference(term);
  if (term.kind == 'variable') return compound('call', [term]);
  if (term.kind == 'integer') return null;
  if (term.kind == 'compound' &&
      term.arguments.length == 2 &&
      {',', ';', '->'}.contains(term.name)) {
    final left = goalConversion(term.arguments[0]);
    if (left == null) return null;
    final right = goalConversion(term.arguments[1]);
    if (right == null) return null;
    return compound(term.name, [left, right]);
  }
  return term;
}

class ConsultStats {
  int clauses = 0, errors = 0, warnings = 0;
}

class Consultant {
  final Database database = Database();
  final List<String> reports = [];
  final Map<String, ConsultStats> statistics = {
    'prelude.pl': ConsultStats(),
    'program.pl': ConsultStats(),
  };
  void warning(String file, int line, String message) {
    reports.add('$file:$line: warning: $message');
    statistics[file]!.warnings++;
  }

  void consult(String file, String source) {
    final reader = Reader(lex(source, 1));
    final lines = textLines(source);
    final seen = <Indicator>{}, warned = <Indicator>{};
    Indicator? last;
    while (reader.peek.kind != 'eof') {
      final line = reader.peek.position.line;
      Term term;
      try {
        term = reader.clause(false);
      } on SyntaxIssue catch (issue) {
        final token = issue.token;
        reports.add(
          '$file:${token.position.line}:${token.position.column}: syntax error: ${issue.message}',
        );
        if (token.kind != 'eof')
          reports.addAll([
            '    ${lines[token.position.line - 1]}',
            '${''.padLeft(token.position.column + 3)}^',
          ]);
        statistics[file]!.errors++;
        reader.index = issue.index;
        while (reader.peek.kind != 'end' && reader.peek.kind != 'eof')
          reader.take();
        if (reader.peek.kind == 'end') reader.take();
        continue;
      }
      var head = term;
      Term? body;
      if (isCompound(term, ':-', 2)) {
        head = term.arguments[0];
        body = term.arguments[1];
      }
      Term? error;
      if (head.kind == 'variable') {
        error = atom('instantiation_error');
      } else if (head.kind == 'integer') {
        error = errorTerm('type_error', [atom('callable'), head]);
      } else {
        final predicate = indicator(head);
        if (control(predicate) || builtin(predicate)) {
          error = errorTerm('permission_error', [
            atom('modify'),
            atom('static_procedure'),
            indicatorTerm(predicate),
          ]);
        } else if (body != null) {
          final converted = goalConversion(body);
          if (converted == null) {
            error = errorTerm('type_error', [atom('callable'), body]);
          } else {
            body = converted;
          }
        }
      }
      if (error != null) {
        reports.add('$file:$line: error: ${termText(error)}');
        statistics[file]!.errors++;
        continue;
      }
      final indicatorValue = indicator(head);
      final predicate = database.ensure(indicatorValue);
      if (file == 'program.pl' &&
          predicate.clauses.isNotEmpty &&
          predicate.clauses.first.file == 'prelude.pl') {
        warning(
          file,
          line,
          'redefining prelude procedure ${indicatorText(indicatorValue)}',
        );
        predicate.clauses.clear();
      }
      if (seen.contains(indicatorValue) &&
          last != null &&
          last != indicatorValue &&
          warned.add(indicatorValue))
        warning(
          file,
          line,
          'clauses of ${indicatorText(indicatorValue)} are not together',
        );
      predicate.clauses.add(Clause(head, body, file, line));
      seen.add(indicatorValue);
      last = indicatorValue;
      statistics[file]!.clauses++;
      final singles = <String>[], repeated = <String>[];
      for (final name in reader.order) {
        if (!name.startsWith('_') && reader.counts[name] == 1)
          singles.add(name);
        if (name.length >= 2 &&
            name.startsWith('_') &&
            reader.counts[name]! >= 2)
          repeated.add(name);
      }
      if (singles.isNotEmpty)
        warning(file, line, 'singleton variables: ${singles.join(', ')}');
      if (repeated.isNotEmpty)
        warning(
          file,
          line,
          'variables starting with _ occur more than once: ${repeated.join(', ')}',
        );
    }
  }

  void undefinedWarnings() {
    final reported = <Indicator>{};
    for (final predicate in database.predicates.values) {
      for (final clause in predicate.clauses) {
        if (clause.body == null) continue;
        void walk(Term term) {
          term = dereference(term);
          if (term.kind == 'variable' || term.kind == 'integer') return;
          final p = indicator(term);
          if (p.arity == 2 && {',', ';', '->'}.contains(p.name)) {
            walk(term.arguments[0]);
            walk(term.arguments[1]);
          } else if (p == (r'\+', 1) || p == ('call', 1)) {
            walk(term.arguments[0]);
          } else if (p == ('findall', 3)) {
            walk(term.arguments[1]);
          } else if (p == ('catch', 3)) {
            walk(term.arguments[0]);
            walk(term.arguments[2]);
          } else if (!control(p) &&
              !builtin(p) &&
              !database.predicates.containsKey(p) &&
              reported.add(p)) {
            warning(
              clause.file,
              clause.line,
              'undefined procedure ${indicatorText(p)} called from ${indicatorText(predicate.indicator)}',
            );
          }
        }

        walk(clause.body!);
      }
    }
  }

  List<String> reportLines() {
    final result = List<String>.of(reports);
    for (final file in ['prelude.pl', 'program.pl']) {
      final s = statistics[file]!;
      result.add(
        '$file: clauses=${s.clauses} errors=${s.errors} warnings=${s.warnings}',
      );
    }
    final clauses = database.predicates.values.fold(
      0,
      (n, p) => n + p.clauses.length,
    );
    result.add(
      'database: predicates=${database.predicates.length} clauses=$clauses',
    );
    return result;
  }
}

List<String> listing(Database database) {
  final result = <String>[];
  for (final predicate in database.predicates.values) {
    if (result.isNotEmpty) result.add('');
    for (final clause in predicate.clauses) {
      final counts = <Term, int>{};
      final order = <Term>[];
      final values = [
        ...termVariables(clause.head),
        if (clause.body != null) ...termVariables(clause.body!),
      ];
      for (final value in values) {
        if (!counts.containsKey(value)) order.add(value);
        counts.update(value, (n) => n + 1, ifAbsent: () => 1);
      }
      final writer = Writer(true);
      var serial = 0;
      for (final value in order) {
        if (counts[value] == 1) {
          writer.names[value] = '_';
        } else {
          writer.names[value] =
              '${String.fromCharCode(65 + serial % 26)}${serial >= 26 ? '${serial ~/ 26}' : ''}';
          serial++;
        }
      }
      final head = writer.write(clause.head, 1200, false);
      if (clause.body == null) {
        result.add('$head.');
        continue;
      }
      result.add('$head :-');
      final goals = <Term>[];
      var body = clause.body!;
      while (isCompound(body, ',', 2)) {
        goals.add(body.arguments[0]);
        body = body.arguments[1];
      }
      goals.add(body);
      for (var i = 0; i < goals.length; i++)
        result.add(
          '    ${writer.write(goals[i], 999, false)}${i == goals.length - 1 ? '.' : ','}',
        );
    }
  }
  return result;
}

class QueryVariable {
  final String name;
  final Term term;
  QueryVariable(this.name, this.term);
}

String answer(List<QueryVariable> variables) {
  final writer = Writer(true);
  for (final variable in variables) {
    final value = dereference(variable.term);
    if (value.kind == 'variable')
      writer.names.putIfAbsent(value, () => variable.name);
  }
  final last = <Term, String>{};
  final items = <String>[];
  for (final variable in variables) {
    final value = dereference(variable.term);
    if (value.kind == 'variable') {
      final previous = last[value];
      if (previous != null) items.add('$previous = ${variable.name}');
      last[value] = variable.name;
    } else {
      items.add('${variable.name} = ${writer.write(value, 699, true)}');
    }
  }
  return items.isEmpty ? 'true' : items.join(', ');
}

class GoalEntry {
  final Term? goal;
  final String marker;
  final int height, barrier;
  final Choice? frame, context;
  GoalEntry({
    this.goal,
    this.marker = '',
    this.height = 0,
    this.barrier = 0,
    this.frame,
    this.context,
  });
}

class GoalNode {
  final GoalEntry entry;
  final GoalNode? next;
  GoalNode(this.entry, this.next);
}

GoalNode? prepend(List<GoalEntry> entries, GoalNode? tail) {
  for (final entry in entries.reversed) tail = GoalNode(entry, tail);
  return tail;
}

GoalEntry goalEntry(Term goal, int barrier, Choice? context) =>
    GoalEntry(goal: goal, barrier: barrier, context: context);

class Choice {
  final String kind;
  int mark = 0;
  final GoalNode? resume;
  final Term? goal;
  final List<Clause> clauses;
  int nextClause;
  final int barrier;
  final Choice? context;
  final int high, base;
  int nextValue;
  final Term? variable, tail, length, catcher, recovery, template, result;
  final Choice? parent;
  final List<Term> results = [];
  Choice(
    this.kind, {
    this.resume,
    this.goal,
    this.clauses = const [],
    this.nextClause = 0,
    this.barrier = 0,
    this.context,
    this.high = 0,
    this.base = 0,
    this.nextValue = 0,
    this.variable,
    this.tail,
    this.length,
    this.catcher,
    this.recovery,
    this.parent,
    this.template,
    this.result,
  });
}

class Profile {
  int calls = 0, tries = 0;
}

class Ball implements Exception {
  final Term term;
  Ball(this.term);
}

class Machine {
  final Database database;
  final Map<Indicator, Profile> profiles;
  final Bindings bindings = Bindings();
  GoalNode? goals;
  final List<Choice> choices = [];
  final List<QueryVariable> variables;
  final int limit;
  int inferences = 0, created = 0, backtracks = 0, solutions = 0;
  String end = '';
  Term? uncaught;
  final List<String> answers = [];
  final StringBuffer output = StringBuffer();
  Machine(this.database, this.profiles, this.variables, this.limit);
  Profile profile(Indicator predicate) =>
      profiles.putIfAbsent(predicate, Profile.new);
  void push(Choice choice) {
    choice.mark = bindings.mark;
    choices.add(choice);
    created++;
  }

  void cut(int height) {
    choices.removeRange(height, choices.length);
  }

  bool inference(Indicator predicate) {
    if (inferences == 20000) {
      end = 'limit';
      return false;
    }
    inferences++;
    profile(predicate).calls++;
    return true;
  }

  bool tryClause(
    Term goal,
    Clause clause,
    int barrier,
    Choice? context,
    GoalNode? continuation,
  ) {
    profile(indicator(goal)).tries++;
    final (head, body) = copyClause(clause);
    if (!bindings.unify(head, goal)) return false;
    goals = body == null
        ? continuation
        : prepend([goalEntry(body, barrier, context)], continuation);
    return true;
  }

  (bool, Term?) step(GoalEntry entry, GoalNode? continuation) {
    try {
      return (executeEntry(entry, continuation), null);
    } on Ball catch (ball) {
      return (false, ball.term);
    } on BuiltinIssue catch (issue) {
      return (
        false,
        errorBall(issue.term, indicator(dereference(entry.goal!))),
      );
    }
  }

  bool executeEntry(GoalEntry entry, GoalNode? continuation) {
    final c = entry.barrier;
    final k = entry.context;
    goals = continuation;
    if (entry.marker.isNotEmpty) {
      switch (entry.marker) {
        case 'ITE':
          cut(entry.height);
          return true;
        case 'NAF':
          cut(entry.height);
          return false;
        case 'EXIT':
          if (choices.isNotEmpty && identical(choices.last, entry.frame))
            choices.removeLast();
          return true;
        case 'COLLECT':
          entry.frame!.results.add(copyTerm(entry.frame!.template!));
          return false;
      }
    }
    final goal = dereference(entry.goal!);
    final predicate = indicator(goal);
    final args = goal.arguments;
    if (control(predicate)) {
      switch (predicate.name) {
        case ',':
          goals = prepend([
            goalEntry(args[0], c, k),
            goalEntry(args[1], c, k),
          ], continuation);
        case '!':
          cut(c);
        case ';':
          {
            final h = choices.length;
            push(
              Choice(
                'ALT',
                resume: prepend([goalEntry(args[1], c, k)], continuation),
              ),
            );
            final left = dereference(args[0]);
            if (isCompound(left, '->', 2)) {
              goals = prepend([
                goalEntry(left.arguments[0], h + 1, k),
                GoalEntry(marker: 'ITE', height: h, barrier: c, context: k),
                goalEntry(left.arguments[1], c, k),
              ], continuation);
            } else {
              goals = prepend([goalEntry(args[0], c, k)], continuation);
            }
          }
        case '->':
          {
            final h = choices.length;
            goals = prepend([
              goalEntry(args[0], h, k),
              GoalEntry(marker: 'ITE', height: h, barrier: c, context: k),
              goalEntry(args[1], c, k),
            ], continuation);
          }
        case r'\+':
          {
            final h = choices.length;
            push(Choice('ALT', resume: continuation));
            goals = prepend([
              goalEntry(compound('call', [args[0]]), c, k),
              GoalEntry(marker: 'NAF', height: h, barrier: c, context: k),
            ], continuation);
          }
        case 'call':
          {
            var target = dereference(args[0]);
            if (target.kind == 'variable')
              throw Ball(errorBall(atom('instantiation_error'), predicate));
            if (target.kind == 'integer')
              throw Ball(
                errorBall(
                  errorTerm('type_error', [atom('callable'), target]),
                  predicate,
                ),
              );
            if (args.length > 1)
              target = compound(target.name, [
                if (target.kind == 'compound') ...target.arguments,
                ...args.skip(1),
              ]);
            final converted = goalConversion(target);
            if (converted == null)
              throw Ball(
                errorBall(
                  errorTerm('type_error', [atom('callable'), target]),
                  predicate,
                ),
              );
            goals = prepend([
              goalEntry(converted, choices.length, k),
            ], continuation);
          }
        case 'catch':
          {
            final frame = Choice(
              'CATCH',
              resume: continuation,
              catcher: args[1],
              recovery: args[2],
              parent: k,
            );
            push(frame);
            goals = prepend([
              goalEntry(compound('call', [args[0]]), c, frame),
              GoalEntry(marker: 'EXIT', frame: frame, barrier: c, context: k),
            ], continuation);
          }
      }
      return true;
    }
    if (!inference(predicate)) return false;
    switch (predicate) {
      case ('findall', 3):
        final frame = Choice(
          'FINDALL',
          resume: continuation,
          template: args[0],
          result: args[2],
        );
        push(frame);
        goals = prepend([
          goalEntry(compound('call', [args[1]]), c, k),
          GoalEntry(marker: 'COLLECT', frame: frame, barrier: c, context: k),
        ], null);
        return true;
      case ('throw', 1):
        final value = dereference(args[0]);
        if (value.kind == 'variable')
          throw Ball(errorBall(atom('instantiation_error'), predicate));
        throw Ball(value);
      case ('between', 3):
        {
          final low = integerCheck(args[0]), high = integerCheck(args[1]);
          final value = dereference(args[2]);
          if (value.kind != 'variable' && value.kind != 'integer')
            predicateError(errorTerm('type_error', [atom('integer'), value]));
          if (value.kind == 'integer')
            return value.integer >= low && value.integer <= high;
          if (low > high) return false;
          if (low < high)
            push(
              Choice(
                'BETWEEN',
                resume: continuation,
                high: high,
                nextValue: low + 1,
                variable: args[2],
              ),
            );
          return bindings.unify(args[2], integer(low));
        }
      case ('length', 2):
        {
          final length = dereference(args[1]);
          if (length.kind != 'variable' && length.kind != 'integer')
            predicateError(errorTerm('type_error', [atom('integer'), length]));
          if (length.kind == 'integer' && length.integer < 0)
            predicateError(
              errorTerm('domain_error', [atom('not_less_than_zero'), length]),
            );
          final (elements, tail) = listParts(args[0]);
          final base = elements.length;
          if (isNil(tail)) return bindings.unify(args[1], integer(base));
          if (tail.kind != 'variable')
            predicateError(errorTerm('type_error', [atom('list'), args[0]]));
          if (length.kind == 'integer') {
            if (length.integer < base) return false;
            return bindings.unify(
              tail,
              makeList([
                for (var i = base; i < length.integer; i++) variable(),
              ]),
            );
          }
          push(
            Choice(
              'LENGTH',
              resume: continuation,
              tail: tail,
              length: args[1],
              base: base,
              nextValue: base + 1,
            ),
          );
          return bindings.unify(tail, atom('[]')) &&
              bindings.unify(args[1], integer(base));
        }
    }
    if (deterministicIndicators.contains(predicate))
      return deterministic(goal, bindings, output);
    final procedure = database.predicates[predicate];
    if (procedure == null)
      throw Ball(
        errorBall(
          errorTerm('existence_error', [
            atom('procedure'),
            indicatorTerm(predicate),
          ]),
          predicate,
        ),
      );
    final candidates = procedure.candidates(goal);
    if (candidates.isEmpty) return false;
    final height = choices.length;
    if (candidates.length > 1)
      push(
        Choice(
          'CLAUSES',
          resume: continuation,
          goal: goal,
          clauses: candidates,
          nextClause: 1,
          barrier: height,
          context: k,
        ),
      );
    return tryClause(goal, candidates.first, height, k, continuation);
  }

  bool backtrack() {
    var increment = true;
    while (true) {
      if (increment) backtracks++;
      increment = true;
      if (choices.isEmpty) {
        end = 'exhausted';
        return false;
      }
      final choice = choices.last;
      bindings.undo(choice.mark);
      switch (choice.kind) {
        case 'ALT':
          choices.removeLast();
          goals = choice.resume;
          return true;
        case 'CLAUSES':
          final index = choice.nextClause;
          if (index == choice.clauses.length - 1) {
            choices.removeLast();
          } else {
            choice.nextClause++;
          }
          if (tryClause(
            choice.goal!,
            choice.clauses[index],
            choice.barrier,
            choice.context,
            choice.resume,
          ))
            return true;
        case 'BETWEEN':
          if (!inference(('between', 3))) return false;
          final value = choice.nextValue;
          if (value == choice.high) {
            choices.removeLast();
          } else {
            choice.nextValue++;
          }
          if (bindings.unify(choice.variable!, integer(value))) {
            goals = choice.resume;
            return true;
          }
        case 'LENGTH':
          if (!inference(('length', 2))) return false;
          final length = choice.nextValue++;
          if (bindings.unify(
                choice.tail!,
                makeList([
                  for (var i = choice.base; i < length; i++) variable(),
                ]),
              ) &&
              bindings.unify(choice.length!, integer(length))) {
            goals = choice.resume;
            return true;
          }
        case 'CATCH':
          choices.removeLast();
          increment = false;
        case 'FINDALL':
          choices.removeLast();
          if (bindings.unify(makeList(choice.results), choice.result!)) {
            goals = choice.resume;
            return true;
          }
      }
    }
  }

  bool exception(Term ball, Choice? context) {
    ball = copyTerm(ball);
    while (context != null) {
      var index = choices.length - 1;
      while (!identical(choices[index], context)) index--;
      choices.removeRange(index, choices.length);
      bindings.undo(context.mark);
      final mark = bindings.mark;
      if (bindings.unify(copyTerm(ball), context.catcher!)) {
        goals = prepend([
          goalEntry(
            compound('call', [context.recovery!]),
            choices.length,
            context.parent,
          ),
        ], context.resume);
        return true;
      }
      bindings.undo(mark);
      context = context.parent;
    }
    uncaught = ball;
    end = 'exception';
    return false;
  }

  void run(Term query) {
    goals = prepend([
      goalEntry(compound('call', [query]), 0, null),
    ], null);
    while (end.isEmpty) {
      final current = goals;
      if (current == null) {
        solutions++;
        final value = answer(variables);
        if (limit > 0 && solutions == limit || choices.isEmpty) {
          answers.add('$value.');
          end = 'done';
          break;
        }
        answers.add('$value ;');
        if (!backtrack()) break;
        continue;
      }
      final entry = current.entry;
      final (success, ball) = step(entry, current.next);
      if (end.isNotEmpty) break;
      if (ball != null) {
        if (!exception(ball, entry.context)) break;
      } else if (!success) {
        if (!backtrack()) break;
      }
    }
    switch (end) {
      case 'exhausted':
        answers.add('false.');
      case 'exception':
        answers.add('uncaught exception: ${termText(uncaught!)}');
      case 'limit':
        answers.add('inference limit exceeded');
    }
  }
}

String readText(String path) => File(path).readAsStringSync();
List<String> textLines(String text) => text.isEmpty
    ? []
    : (text.endsWith('\n') ? text.substring(0, text.length - 1) : text).split(
        '\n',
      );
void save(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final consultant = Consultant();
  for (final file in ['prelude.pl', 'program.pl'])
    consultant.consult(file, readText('input/$file'));
  consultant.undefinedWarnings();
  final profiles = <Indicator, Profile>{};
  final answers = <String>[];
  final stats = <String>[];
  final writes = StringBuffer();
  final totals = List.filled(4, 0);
  var number = 0;
  for (final line in textLines(readText('input/queries.txt'))) {
    number++;
    answers.add(line);
    writes.writeln('== query $number ==');
    final marker = line.indexOf('?- '), bodyStart = line.indexOf('?- ') + 3;
    final limit = marker > 0 ? int.parse(line.substring(0, marker).trim()) : 0;
    final reader = Reader(lex(line.substring(bodyStart), bodyStart + 1));
    Term query;
    try {
      query = reader.clause(true);
    } on SyntaxIssue catch (issue) {
      answers.add(
        'syntax error at column ${issue.token.position.column}: ${issue.message}',
      );
      stats.add('query $number: syntax error');
      continue;
    }
    final variables = [
      for (final name in reader.order)
        if (!name.startsWith('_')) QueryVariable(name, reader.named[name]!),
    ];
    final machine = Machine(consultant.database, profiles, variables, limit);
    machine.run(query);
    answers.addAll(machine.answers);
    final text = machine.output.toString();
    writes.write(text);
    if (text.isNotEmpty && !text.endsWith('\n')) writes.writeln();
    stats.add(
      'query $number: solutions=${machine.solutions} inferences=${machine.inferences} choicepoints=${machine.created} backtracks=${machine.backtracks}',
    );
    totals[0] += machine.solutions;
    totals[1] += machine.inferences;
    totals[2] += machine.created;
    totals[3] += machine.backtracks;
  }
  stats.addAll([
    'total: solutions=${totals[0]} inferences=${totals[1]} choicepoints=${totals[2]} backtracks=${totals[3]}',
    '== profile ==',
  ]);
  final indicators = profiles.keys.where((p) => profiles[p]!.calls > 0).toList()
    ..sort(
      (a, b) => profiles[a]!.calls != profiles[b]!.calls
          ? profiles[b]!.calls.compareTo(profiles[a]!.calls)
          : indicatorText(a).compareTo(indicatorText(b)),
    );
  for (final predicate in indicators)
    stats.add(
      '${indicatorText(predicate)} calls=${profiles[predicate]!.calls}${consultant.database.predicates.containsKey(predicate) ? ' tries=${profiles[predicate]!.tries}' : ''}',
    );
  Directory('output').createSync(recursive: true);
  save('consult.txt', consultant.reportLines());
  save('listing.txt', listing(consultant.database));
  save('answers.txt', answers);
  save('stats.txt', stats);
  File('output/write_output.txt').writeAsStringSync(writes.toString());
}
