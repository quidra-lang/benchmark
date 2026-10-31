part of 'main.dart';

class Literal {
  final String kind;
  Value value;
  Literal(this.kind, this.value);
}

class Condition {
  final String op, column;
  int index = -1;
  final List<Literal> literals;
  final List<Condition> children;
  Condition(
    this.op, {
    this.column = '',
    this.literals = const [],
    this.children = const [],
  });
}

class Item {
  final String op, column;
  final bool distinct;
  int index = -1;
  Item(this.column, {this.op = '', this.distinct = false});
  String header() =>
      op.isEmpty ? column : '$op(${distinct ? 'DISTINCT ' : ''}$column)';
}

class Query {
  final List<Item> items = [];
  bool star = false, descending = false, aggregate = false;
  Condition? condition;
  String group = '', order = '';
  int limit = 0, groupIndex = -1, orderIndex = -1;
  final List<int> needed = [], conditionColumns = [], remaining = [];
}

List<String> queryTokens(String s) {
  final out = <String>[];
  var i = 0;
  bool word(String c) {
    final n = c.codeUnitAt(0);
    return n >= 65 && n <= 90 ||
        n >= 97 && n <= 122 ||
        n >= 48 && n <= 57 ||
        c == '_';
  }

  while (i < s.length) {
    if (s[i] == ' ') {
      i++;
      continue;
    }
    final start = i, c = s[i];
    if (c == "'") {
      i++;
      while (s[i] != "'") {
        i++;
      }
      i++;
    } else if (word(c) || c == '-') {
      i++;
      while (i < s.length && word(s[i])) {
        i++;
      }
    } else {
      i++;
      if (i < s.length &&
          (c == '<' || c == '>') &&
          (s[i] == '=' || s[i] == '>' && c == '<'))
        i++;
    }
    out.add(s.substring(start, i));
  }
  return out;
}

class QueryParser {
  final List<String> tokens;
  int at = 0;
  QueryParser(String s) : tokens = queryTokens(s);
  String get peek => at == tokens.length ? '' : tokens[at];
  String take() => tokens[at++];
  Literal literal() {
    final s = take();
    if (s.startsWith("'"))
      return Literal('STRING', Value(text: s.substring(1, s.length - 1)));
    if (s == 'TRUE' || s == 'FALSE')
      return Literal('BOOL', Value(number: s == 'TRUE' ? 1 : 0));
    return Literal('INT', Value(number: number(s)));
  }

  Condition comparison() {
    final column = take(), op = take(), values = <Literal>[];
    var actual = op;
    switch (op) {
      case 'IS':
        if (peek == 'NOT') {
          take();
          actual = 'IS NOT NULL';
        } else {
          actual = 'IS NULL';
        }
        take();
        break;
      case 'BETWEEN':
        values.add(literal());
        take();
        values.add(literal());
        break;
      case 'IN':
        take();
        while (true) {
          values.add(literal());
          if (take() == ')') break;
        }
        break;
      default:
        values.add(literal());
    }
    return Condition(actual, column: column, literals: values);
  }

  Condition negation() {
    if (peek == 'NOT') {
      take();
      return Condition('NOT', children: [negation()]);
    }
    if (peek == '(') {
      take();
      final c = disjunction();
      take();
      return c;
    }
    return comparison();
  }

  Condition conjunction() {
    var c = negation();
    while (peek == 'AND') {
      take();
      c = Condition('AND', children: [c, negation()]);
    }
    return c;
  }

  Condition disjunction() {
    var c = conjunction();
    while (peek == 'OR') {
      take();
      c = Condition('OR', children: [c, conjunction()]);
    }
    return c;
  }
}

Query parseQuery(String text) {
  final p = QueryParser(text), q = Query();
  p.take();
  if (p.peek == '*') {
    p.take();
    q.star = true;
  } else {
    while (true) {
      final token = p.take();
      if (['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'].contains(token)) {
        q.aggregate = true;
        p.take();
        var distinct = false;
        if (p.peek == 'DISTINCT') {
          p.take();
          distinct = true;
        }
        q.items.add(Item(p.take(), op: token, distinct: distinct));
        p.take();
      } else {
        q.items.add(Item(token));
      }
      if (p.peek != ',') break;
      p.take();
    }
  }
  if (p.peek == 'WHERE') {
    p.take();
    q.condition = p.disjunction();
  }
  if (p.peek == 'GROUP') {
    p.take();
    p.take();
    q.group = p.take();
    q.aggregate = true;
  }
  if (p.peek == 'ORDER') {
    p.take();
    p.take();
    q.order = p.take();
    if (p.peek == 'ASC' || p.peek == 'DESC') q.descending = p.take() == 'DESC';
  }
  if (p.peek == 'LIMIT') {
    p.take();
    q.limit = number(p.take());
  }
  return q;
}

List<Condition> conditionLeaves(Condition? c) => c == null
    ? []
    : c.children.isEmpty
    ? [c]
    : [for (final child in c.children) ...conditionLeaves(child)];
String queryHeaders(Query q) => q.items.map((i) => i.header()).join(',');
