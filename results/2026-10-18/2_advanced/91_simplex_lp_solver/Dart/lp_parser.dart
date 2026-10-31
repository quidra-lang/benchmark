part of 'main.dart';

class ModelError {
  final int line;
  final String message;
  ModelError(this.line, this.message);
}

class Term {
  final String name;
  final Fraction coefficient;
  Term(this.name, this.coefficient);
}

class Constraint {
  final String name, comparison;
  final int line;
  final List<Term> terms;
  final Fraction rhs;
  List<Fraction> coefficients = [];
  Constraint(this.name, this.comparison, this.line, this.terms, this.rhs);
}

class BoundLine {
  final int line;
  final String name, kind;
  final Fraction? lower, upper;
  BoundLine(this.line, this.name, this.kind, {this.lower, this.upper});
}

class Declaration {
  final int line;
  final List<String> names;
  Declaration(this.line, this.names);
}

class RawModel {
  final String name;
  String direction = '';
  List<Term> objective = [];
  final List<Constraint> constraints = [];
  final List<BoundLine> bounds = [];
  final List<Declaration> integers = [], binaries = [];
  ModelError? error;
  RawModel(this.name);
}

class Settings {
  final int level, limit;
  final Map<String, int> logs = {}, limits = {};
  Settings(this.level, this.limit);
}

class Record {
  final int line;
  final String text;
  Record(this.line, this.text);
}

final namePattern = RegExp(r'^[a-z][a-z0-9_]*$');
bool wordIn(String words, String value) => words.split(' ').contains(value);
bool isName(String word) =>
    namePattern.hasMatch(word) &&
    !wordIn('bounds integer binary free inf', word);
List<Term>? parseExpression(List<String> words) {
  final out = <Term>[];
  var position = 0, sign = 1;
  if (words.isNotEmpty && words.first == '-') {
    position++;
    sign = -1;
  }
  while (position < words.length) {
    var coefficient = readNumber(words[position], false), name = '';
    if (coefficient != null) {
      if (position + 1 == words.length || !isName(words[position + 1]))
        return null;
      name = words[position + 1];
      position += 2;
    } else if (isName(words[position])) {
      coefficient = one;
      name = words[position++];
    } else {
      return null;
    }
    out.add(Term(name, coefficient.mul(Fraction(sign))));
    if (position == words.length) return out;
    if (words[position] != '+' && words[position] != '-') return null;
    sign = words[position] == '-' ? -1 : 1;
    position++;
  }
  return null;
}

(String, List<Term>)? namedExpression(List<String> words) {
  if (words.length < 2 || !words.first.endsWith(':')) return null;
  final name = words.first.substring(0, words.first.length - 1);
  if (!isName(name)) return null;
  final terms = parseExpression(words.sublist(1));
  return terms == null ? null : (name, terms);
}

Constraint? parseConstraint(List<String> words, int line) {
  if (words.length < 4 || !wordIn('<= >= =', words[words.length - 2]))
    return null;
  final rhs = readNumber(words.last, true),
      named = namedExpression(words.sublist(0, words.length - 2));
  return rhs == null || named == null
      ? null
      : Constraint(named.$1, words[words.length - 2], line, named.$2, rhs);
}

BoundLine? parseBound(List<String> words, int line) {
  final n = words.length;
  if (n == 2 && isName(words[0]) && words[1] == 'free')
    return BoundLine(line, words[0], 'both');
  if (n == 3 && isName(words[0])) {
    final value = readNumber(words[2], true);
    switch (words[1]) {
      case '>=':
        if (value != null || words[2] == '-inf')
          return BoundLine(line, words[0], 'lower', lower: value);
        break;
      case '<=':
        if (value != null || words[2] == 'inf')
          return BoundLine(line, words[0], 'upper', upper: value);
        break;
      case '=':
        if (value != null)
          return BoundLine(line, words[0], 'both', lower: value, upper: value);
        break;
    }
  }
  if (n == 5 && words[1] == '<=' && words[3] == '<=' && isName(words[2])) {
    final lower = readNumber(words[0], true),
        upper = readNumber(words[4], true);
    if ((lower != null || words[0] == '-inf') &&
        (upper != null || words[4] == 'inf'))
      return BoundLine(line, words[2], 'both', lower: lower, upper: upper);
  }
  return null;
}

RawModel parseBlock(String name, List<Record> body, int endLine) {
  final m = RawModel(name);
  var state = 'A';
  for (final record in body) {
    final words = record.text.split(' ');
    var accepted = false;
    switch (state) {
      case 'A':
        if (record.text == 'maximize' || record.text == 'minimize') {
          m.direction = record.text;
          state = 'B';
          accepted = true;
        }
        break;
      case 'B':
        final named = namedExpression(words);
        if (named != null) {
          m.objective = named.$2;
          state = 'C';
          accepted = true;
        }
        break;
      case 'C':
        if (record.text == 'subject to') {
          state = 'D';
          accepted = true;
        }
        break;
      case 'D':
      case 'E':
        if (state == 'E' && wordIn('bounds integer binary', record.text)) {
          state = {'bounds': 'F', 'integer': 'G', 'binary': 'H'}[record.text]!;
          accepted = true;
        } else {
          final c = parseConstraint(words, record.line);
          if (c != null) {
            m.constraints.add(c);
            state = 'E';
            accepted = true;
          }
        }
        break;
      case 'F':
        if (record.text == 'integer' || record.text == 'binary') {
          state = record.text == 'integer' ? 'G' : 'H';
          accepted = true;
        } else {
          final b = parseBound(words, record.line);
          if (b != null) {
            m.bounds.add(b);
            accepted = true;
          }
        }
        break;
      case 'G':
      case 'H':
        if (state == 'G' && record.text == 'binary') {
          state = 'H';
          accepted = true;
        } else if (words.every(isName)) {
          final d = Declaration(record.line, words);
          (state == 'G' ? m.integers : m.binaries).add(d);
          accepted = true;
        }
        break;
    }
    if (!accepted) {
      m.error = ModelError(record.line, 'syntax error');
      return m;
    }
  }
  if (wordIn('A B C D', state)) m.error = ModelError(endLine, 'syntax error');
  return m;
}

List<RawModel> readModels() {
  final out = <RawModel>[],
      body = <Record>[],
      lines = File('input/models.lp').readAsLinesSync();
  var name = '';
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty || line.startsWith('#')) continue;
    if (name.isEmpty) {
      name = line.split(' ')[1];
      body.clear();
    } else if (line == 'end') {
      out.add(parseBlock(name, body, i + 1));
      name = '';
    } else {
      body.add(Record(i + 1, line));
    }
  }
  return out;
}

Settings readSettings() {
  final lines = File('input/params.txt').readAsLinesSync(),
      s = Settings(
        int.parse(lines[0].split(' ')[1]),
        int.parse(lines[1].split(' ')[1]),
      );
  for (final line in lines.skip(2)) {
    final a = line.split(' ');
    (a[0] == 'log' ? s.logs : s.limits)[a[1]] = int.parse(a[2]);
  }
  return s;
}
