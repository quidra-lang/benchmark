import 'dart:io';

class SqlError implements Exception {
  final String reason;
  SqlError(this.reason);
}
Never fail(String reason) => throw SqlError(reason);
const aggregateNames = ['COUNT', 'SUM', 'MIN', 'MAX', 'AVG'];
const comparisons = ['=', '<>', '!=', '<', '<=', '>', '>='];
final reserved = 'SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT'.split(' ').toSet();

class Token {
  final String kind, text, key;
  Token(this.kind, this.text, this.key);
}
List<Token> tokenize(String source) {
  final pattern = RegExp(r"[ \n]+|--[^\n]*|'[^']*'|[0-9]+|[A-Za-z_][A-Za-z0-9_]*|<>|!=|<=|>=|\|\||[(),.;*/%+\-=<>]");
  final tokens = <Token>[];
  var i = 0;
  while (i < source.length) {
    final match = pattern.matchAsPrefix(source, i);
    if (match == null) fail("unexpected character '${source[i]}'");
    final text = match.group(0)!;
    i = match.end;
    if (text.startsWith(' ') || text.startsWith('\n') || text.startsWith('--')) continue;
    final kind = text.startsWith("'") ? 'string' : RegExp(r'^[0-9]').hasMatch(text) ? 'integer' : RegExp(r'^[A-Za-z_]').hasMatch(text) ? (reserved.contains(text.toUpperCase()) ? 'keyword' : 'name') : 'symbol';
    tokens.add(Token(kind, text, kind == 'keyword' ? text.toUpperCase() : text));
  }
  return tokens;
}

class Expr {
  final String kind;
  String op, column, written;
  String? table;
  Object? literal;
  List<Expr> children;
  int index = -1;
  bool negated = false, distinct = false;
  Expr(this.kind, {
    this.op = '', this.children = const [], this.literal, this.table, this.column = '', this.written = '',
  });
  bool get hasAggregate => kind == 'aggregate' || children.any((e) => e.hasAggregate);
}

class Column {
  final String name, type;
  final bool notNull;
  final int keys;
  Column(this.name, this.type, this.notNull, this.keys);
}

class Table {
  final String name;
  final List<Column> columns;
  List<List<Object?>> rows;
  Table(this.name, this.columns, [List<List<Object?>>? rows]) : rows = rows ?? [];
  int? get primary {
    final i = columns.indexWhere((c) => c.keys > 0);
    return i < 0 ? null : i;
  }
}

class TableRef {
  final String name;
  final String? alias;
  TableRef(this.name, this.alias);
  String get scopeName => alias ?? name;
}

class Join {
  final TableRef table;
  final bool outer;
  final Expr condition;
  Join(this.table, this.outer, this.condition);
}

class Item {
  final Expr expr;
  final String? alias;
  final String heading;
  Item(this.expr, this.alias, this.heading);
}

class Order {
  final Expr expr;
  final List<Token> tokens;
  final bool descending;
  Order(this.expr, this.tokens, this.descending);
}

class Statement {
  String command = '', name = '';
  List<Column> columns = [];
  List<String>? names;
  List<List<Expr>> tuples = [];
  List<(String, Expr)> assignments = [];
  Expr? whereExpr, having;
  bool distinct = false;
  List<Item>? items;
  TableRef? source;
  List<Join> joins = [];
  List<Expr> grouping = [];
  List<Order> orders = [];
  int? limit;
  int offset = 0;
}

class Parser {
  final List<Token> tokens;
  int pos = 0;
  Parser(this.tokens);
  Token get peek => tokens[pos < tokens.length ? pos : tokens.length - 1];
  bool at(List<String> keys) => (peek.kind == 'keyword' || peek.kind == 'symbol') && keys.contains(peek.key);
  Token take() {
    final t = peek;
    pos++;
    return t;
  }
  bool accept(String key) {
    if (at([key])) {
      pos++;
      return true;
    }
    return false;
  }
  Never syntax() => fail("syntax error at '${peek.text}'");
  void expect(String key) {
    if (!accept(key)) syntax();
  }
  String name() {
    if (peek.kind != 'name') syntax();
    return take().text;
  }
  int integer() {
    if (peek.kind != 'integer') syntax();
    return int.parse(take().text);
  }
  List<T> list<T>(T Function() parse) {
    final a = [parse()];
    while (accept(',')) {
      a.add(parse());
    }
    return a;
  }
  List<T> parenthesized<T>(T Function() parse) {
    expect('(');
    final a = list(parse);
    expect(')');
    return a;
  }
  String? alias() {
    if (accept('AS')) return name();
    return peek.kind == 'name' ? take().text : null;
  }
  Expr ref() {
    final first = name();
    if (accept('.')) {
      final c = name();
      return Expr('column', table: first, column: c, written: '$first.$c');
    }
    return Expr('column', column: first, written: first);
  }
  TableRef tableRef() {
    final n = name();
    return TableRef(n, alias());
  }
  Expr? clause(String key) => accept(key) ? expr() : null;
  Statement parse() {
    final s = Statement();
    if (accept('CREATE')) {
      s.command = 'CREATE';
      expect('TABLE');
      s.name = name();
      s.columns = parenthesized(() {
        final n = name();
        if (!at(['INT', 'TEXT'])) syntax();
        final type = take().key;
        var keys = 0;
        var nn = false;
        while (at(['PRIMARY', 'NOT'])) {
          if (accept('PRIMARY')) {
            expect('KEY');
            keys++;
          } else {
            expect('NOT');
            expect('NULL');
            nn = true;
          }
        }
        return Column(n, type, nn || keys > 0, keys);
      });
    } else if (accept('DROP')) {
      s.command = 'DROP';
      expect('TABLE');
      s.name = name();
    }
    else if (accept('INSERT')) {
      s.command = 'INSERT';
      expect('INTO');
      s.name = name();
      if (at(['('])) s.names = parenthesized(name);
      expect('VALUES');
      s.tuples = list(() => parenthesized(expr));
    }
    else if (accept('UPDATE')) {
      s.command = 'UPDATE';
      s.name = name();
      expect('SET');
      s.assignments = list(() {
        final n = name();
        expect('=');
        return (n, expr());
      });
      s.whereExpr = clause('WHERE');
    }
    else if (accept('DELETE')) {
      s.command = 'DELETE';
      expect('FROM');
      s.name = name();
      s.whereExpr = clause('WHERE');
    }
    else if (accept('SELECT')) {
      s.command = 'SELECT';
      s.distinct = accept('DISTINCT');
      if (!accept('*')) s.items = list(() {
        final start = pos;
        final e = expr();
        final t = tokens.sublist(start, pos);
        final a = alias();
        var heading = '';
        for (var i = 0; i < t.length; i++) {
          if (i > 0 && t[i].kind != 'symbol' && t[i-1].kind != 'symbol') heading += ' ';
          heading += t[i].text;
        }
        return Item(e, a, a ?? (e.kind == 'column' && t[0].kind == 'name' ? e.column : heading));
      });
      expect('FROM');
      s.source = tableRef();
      while (at(['JOIN', 'LEFT', 'INNER'])) {
        final outer = accept('LEFT');
        if (outer) {
          accept('OUTER');
        } else {
          accept('INNER');
        }
        expect('JOIN');
        final t = tableRef();
        expect('ON');
        s.joins.add(Join(t, outer, expr()));
      }
      s.whereExpr = clause('WHERE');
      if (accept('GROUP')) {
        expect('BY');
        s.grouping = list(ref);
      }
      s.having = clause('HAVING');
      if (accept('ORDER')) {
        expect('BY');
        s.orders = list(() {
          final start = pos;
          final e = expr();
          final t = tokens.sublist(start, pos);
          final desc = accept('DESC');
          if (!desc) accept('ASC');
          return Order(e, t, desc);
        });
      }
      if (accept('LIMIT')) {
        s.limit = integer();
        if (accept('OFFSET')) s.offset = integer();
      }
    } else if (accept('EXIT')) {
      s.command = 'EXIT';
    }
    expect(';');
    return s;
  }
  Expr binary(List<String> ops, Expr Function() operand) {
    var e = operand();
    while (at(ops)) {
      final op = take().key;
      e = Expr('binary', op: op, children: [e, operand()]);
    }
    return e;
  }
  Expr expr() => binary(['OR'], andExpr);
  Expr andExpr() => binary(['AND'], notExpr);
  Expr notExpr() => accept('NOT') ? Expr('unary', op: 'NOT', children: [notExpr()]) : comparison();
  Expr comparison() {
    final e = additive();
    if (at(comparisons)) {
      final op = take().key;
      return Expr('binary', op: op, children: [e, additive()]);
    }
    if (accept('IS')) {
      final n = accept('NOT');
      expect('NULL');
      return Expr('isnull', children: [e])..negated = n;
    }
    final n = accept('NOT');
    Expr? r;
    if (accept('IN')) {
      r = Expr('in', children: [e, ...parenthesized(expr)]);
    }
    else if (accept('BETWEEN')) {
      final low = additive();
      expect('AND');
      r = Expr('between', children: [e, low, additive()]);
    }
    else if (accept('LIKE')) {
      r = Expr('like', children: [e, additive()]);
    }
    else if (n) {
      syntax();
    }
    if (r != null) {
      r.negated = n;
      return r;
    }
    return e;
  }
  Expr additive() => binary(['+', '-', '||'], multiplicative);
  Expr multiplicative() => binary(['*', '/', '%'], unary);
  Expr unary() => accept('-') ? Expr('unary', op: '-', children: [unary()]) : primary();
  Expr primary() {
    if (peek.kind == 'integer') return Expr('literal', literal: int.parse(take().text));
    if (peek.kind == 'string') {
      final t = take().text;
      return Expr('literal', literal: t.substring(1, t.length-1));
    }
    if (accept('NULL')) return Expr('literal');
    if (peek.kind == 'name') return ref();
    if (at(aggregateNames)) {
      final n = take().key;
      expect('(');
      final e = Expr('aggregate', op: n);
      if (n == 'COUNT' && accept('*')) {
      } else {
        e.distinct = accept('DISTINCT');
        e.children = [expr()];
      }
      expect(')');
      return e;
    }
    if (accept('(')) {
      final e = expr();
      expect(')');
      return e;
    }
    syntax();
  }
}

class Entry {
  final String name;
  final Table table;
  final int offset;
  Entry(this.name, this.table, this.offset);
}

class Scope {
  final entries = <Entry>[];
  int width = 0;
  void add(String name, Table table) {
    if (entries.any((e) => e.name == name)) fail('duplicate table name $name');
    entries.add(Entry(name, table, width));
    width += table.columns.length;
  }
  String resolve(Expr e) {
    var selected = entries;
    if (e.table != null) {
      selected = entries.where((entry) => entry.name == e.table).toList();
      if (selected.isEmpty) fail('unknown table ${e.table}');
    }
    final candidates = <(int, String)>[];
    for (final entry in selected) {
      for (var i = 0; i < entry.table.columns.length; i++) {
        final c = entry.table.columns[i];
        if (c.name == e.column) candidates.add((entry.offset+i, c.type));
      }
    }
    if (candidates.isEmpty) fail('unknown column ${e.written}');
    if (candidates.length > 1) fail('ambiguous column ${e.column}');
    e.index = candidates[0].$1;
    return candidates[0].$2;
  }
}
String type(Object? value) => value == null ? 'NULL' : value is int ? 'INT' : 'TEXT';
String written(Object? value) => value?.toString() ?? 'NULL';
void require(String a, String b, String op) {
  if (a != b && a != 'NULL' && b != 'NULL') fail('type mismatch for $op');
}
String check(Expr e, Scope scope, [bool allowed = false, Set<int>? grouped, bool inside = false]) {
  if (e.kind == 'literal') return type(e.literal);
  if (e.kind == 'column') {
    final t = scope.resolve(e);
    if (grouped != null && !inside && !grouped.contains(e.index)) fail('column ${e.written} is not grouped');
    return t;
  }
  if (e.kind == 'aggregate') {
    if (!allowed || inside) fail('misuse of aggregate ${e.op}');
    if (e.children.isEmpty) return 'INT';
    final t = check(e.children[0], scope, allowed, grouped, true);
    if (['SUM', 'AVG'].contains(e.op)) require(t, 'INT', e.op);
    return ['MIN', 'MAX'].contains(e.op) ? t : 'INT';
  }
  final types = e.children.map((c) => check(c, scope, allowed, grouped, inside)).toList();
  switch (e.kind) {
    case 'unary': require(types[0], 'INT', e.op);
    case 'binary':
    if (comparisons.contains(e.op)) {
      require(types[0], types[1], e.op);
    }
    else {
      final t = e.op == '||' ? 'TEXT' : 'INT';
      for (final a in types) {
        require(a, t, e.op);
      }
      return t;
    }
    case 'in': case 'between': for (final t in types.skip(1)) {
      require(t, types[0], e.kind == 'in' ? 'IN' : 'BETWEEN');
    }
    case 'like': for (final t in types) {
      require(t, 'TEXT', 'LIKE');
    }
  }
  return 'INT';
}
void condition(Expr? e, Scope scope, String clause, [bool allowed = false, Set<int>? grouped]) {
  if (e != null) require(check(e, scope, allowed, grouped), 'INT', clause);
}
bool truth(Object? v) => v != null && v != 0;
Object? logicalNot(Object? v) => v == null ? null : truth(v) ? 0 : 1;
int compare(Object? a, Object? b) {
  if (a == b) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a is int ? a.compareTo(b as int) : (a as String).compareTo(b as String);
}
Object? operation(String op, Object? a, Object? b) {
  if (op == 'AND') return a == 0 || b == 0 ? 0 : a == null || b == null ? null : 1;
  if (op == 'OR') return truth(a) || truth(b) ? 1 : a == null || b == null ? null : 0;
  if (a == null || b == null) return null;
  switch (op) {
    case '+': return (a as int) + (b as int);
    case '-': return (a as int) - (b as int);
    case '*': return (a as int) * (b as int);
    case '/': return b == 0 ? null : (a as int) ~/ (b as int);
    case '%': return b == 0 ? null : (a as int).remainder(b as int);
    case '||': return (a as String) + (b as String);
    case '=': return a == b ? 1 : 0;
    case '!=': case '<>': return a != b ? 1 : 0;
    case '<': return compare(a, b) < 0 ? 1 : 0;
    case '<=': return compare(a, b) <= 0 ? 1 : 0;
    case '>': return compare(a, b) > 0 ? 1 : 0;
    default: return compare(a, b) >= 0 ? 1 : 0;
  }
}
bool like(String text, String pattern) {
  final matched = [true, ...List.filled(text.length, false)];
  for (final c in pattern.split('')) {
    if (c == '%') {
      for (var i = 1; i <= text.length; i++) {
        matched[i] = matched[i] || matched[i-1];
      }
    }
    else {
      for (var i = text.length; i > 0; i--) {
        matched[i] = matched[i-1] && (c == '_' || c == text[i-1]);
      }
      matched[0] = false;
    }
  }
  return matched.last;
}
Object? evaluate(Expr e, List<Object?> row, [List<List<Object?>> group = const []]) {
  if (e.kind == 'literal') return e.literal;
  if (e.kind == 'column') return row[e.index];
  if (e.kind == 'aggregate') {
    if (e.children.isEmpty) return group.length;
    var values = group.map((r) => evaluate(e.children[0], r)).where((v) => v != null).toList();
    if (e.distinct) values = values.toSet().toList();
    if (e.op == 'COUNT') return values.length;
    if (values.isEmpty) return null;
    if (e.op == 'MIN') return values.reduce((a,b) => compare(a,b) < 0 ? a : b);
    if (e.op == 'MAX') return values.reduce((a,b) => compare(a,b) > 0 ? a : b);
    final sum = values.fold<int>(0, (a,b) => a + (b as int));
    return e.op == 'AVG' ? sum ~/ values.length : sum;
  }
  final v = e.children.map((c) => evaluate(c, row, group)).toList();
  Object? result;
  switch (e.kind) {
    case 'unary': return e.op == 'NOT' ? logicalNot(v[0]) : v[0] == null ? null : -(v[0] as int);
    case 'binary': return operation(e.op, v[0], v[1]);
    case 'isnull': result = v[0] == null ? 1 : 0;
    case 'in': result = v[0] == null ? null : v.skip(1).contains(v[0]) ? 1 : v.skip(1).contains(null) ? null : 0;
    case 'between': result = operation('AND', operation('>=',v[0],v[1]), operation('<=',v[0],v[2]));
    case 'like': result = v.contains(null) ? null : like(v[0] as String, v[1] as String) ? 1 : 0;
  }
  return e.negated ? logicalNot(result) : result;
}
final database = <String, Table>{};
Table lookup(String name) => database[name] ?? fail('unknown table $name');
List<int> targets(List<String> names, Table t) {
  final indices = <int>[];
  for (final n in names) {
    final i = t.columns.indexWhere((c) => c.name == n);
    if (i < 0) fail('unknown column $n');
    if (indices.contains(i)) fail('duplicate column $n');
    indices.add(i);
  }
  return indices;
}
void constraints(Table t, List<int> checked) {
  for (final i in checked) {
    for (var j = 0; j < t.columns.length; j++) {
      if (t.columns[j].notNull && t.rows[i][j] == null) fail('NULL value in column ${t.columns[j].name}');
    }
    final k = t.primary;
    if (k != null) {
      for (var j = 0; j < t.rows.length; j++) {
        if (i != j && t.rows[i][k] == t.rows[j][k]) fail('duplicate primary key ${written(t.rows[i][k])}');
      }
    }
  }
}
String rowKey(List<Object?> row) => row.map((v) => '${type(v)}:${written(v).length}:${written(v)}').join('|');
void countMessage(int n, String verb) => print('$n ${n == 1 ? 'row' : 'rows'} $verb.');
void printTable(List<Item> items, List<String> types, List<List<Object?>> rows) {
  final headings = items.map((i) => i.heading).toList();
  final widths = items.map((i) => i.heading.length).toList();
  for (final r in rows) {
    for (var i = 0; i < widths.length; i++) {
      if (written(r[i]).length > widths[i]) widths[i] = written(r[i]).length;
    }
  }
  final separator = '+' + widths.map((w) => '-' * (w + 2) + '+').join();
  String line(List<String> values, bool data) {
    final cells = List.generate(values.length, (i) {
      final cell = data && types[i] == 'INT'
          ? values[i].padLeft(widths[i])
          : values[i].padRight(widths[i]);
      return ' ' + cell + ' |';
    });
    return '|' + cells.join();
  }
  print(separator);
  print(line(headings,false));
  print(separator);
  for (final r in rows) {
    print(line(r.map(written).toList(),true));
  }
  print(separator);
  print('(${rows.length} ${rows.length == 1 ? 'row' : 'rows'})');
}

class Result {
  final List<Object?> values, keys;
  final int ordinal;
  Result(this.values,this.keys,this.ordinal);
}
void executeSelect(Statement s) {
  final scope = Scope();
  final tables = <Table>[];
  final refs = [s.source!, ...s.joins.map((j) => j.table)];
  for (var i = 0; i < refs.length; i++) {
    final r = refs[i];
    final t = lookup(r.name);
    scope.add(r.scopeName,t);
    tables.add(t);
    if (i > 0) condition(s.joins[i-1].condition,scope,'ON');
  }
  condition(s.whereExpr,scope,'WHERE');
  for (final e in s.grouping) {
    scope.resolve(e);
  }
  final aggregate = s.grouping.isNotEmpty || s.having != null || (s.items ?? []).any((i) => i.expr.hasAggregate) || s.orders.any((o) => o.expr.hasAggregate);
  final grouped = aggregate ? s.grouping.map((e) => e.index).toSet() : null;
  final items = s.items ?? [for (final entry in scope.entries) for (final c in entry.table.columns) Item(Expr('column',table:entry.name,column:c.name,written:c.name),null,c.name)];
  final types = items.map((i) => check(i.expr,scope,true,grouped)).toList();
  condition(s.having,scope,'HAVING',true,grouped);
  final keys = <Expr>[];
  for (final order in s.orders) {
    if (order.tokens.length == 1 && order.tokens[0].kind == 'integer') {
      final k = int.parse(order.tokens[0].text);
      if (k < 1 || k > items.length) fail('ORDER BY position $k is out of range');
      keys.add(items[k-1].expr);
    }
    else {
      final i = order.tokens.length == 1 && order.tokens[0].kind == 'name' ? items.indexWhere((i) => i.alias == order.tokens[0].text) : -1;
      if (i >= 0) {
        keys.add(items[i].expr);
      } else {
        check(order.expr,scope,true,grouped);
        keys.add(order.expr);
      }
    }
  }
  var rows = tables[0].rows;
  for (var j = 0; j < s.joins.length; j++) {
    final join = s.joins[j];
    final next = <List<Object?>>[];
    for (final l in rows) {
      var matched = false;
      for (final r in tables[j+1].rows) {
        final combined = [...l,...r];
        if (truth(evaluate(join.condition,combined))) {
          next.add(combined);
          matched = true;
        }
      }
      if (!matched && join.outer) next.add([...l,...List<Object?>.filled(tables[j+1].columns.length,null)]);
    }
    rows = next;
  }
  if (s.whereExpr != null) rows = rows.where((r) => truth(evaluate(s.whereExpr!,r))).toList();
  var groups = <List<List<Object?>>>[];
  if (aggregate) {
    if (s.grouping.isEmpty) {
      groups = [rows];
    }
    else {
      final indices = <String, int>{};
      for (final r in rows) {
        final key = rowKey(s.grouping.map((e) => r[e.index]).toList());
        final i = indices[key];
        if (i != null) {
          groups[i].add(r);
        } else {
          indices[key] = groups.length;
          groups.add([r]);
        }
      }
    }
  } else {
    groups = rows.map((r) => [r]).toList();
  }
  var results = <Result>[];
  for (final g in groups) {
    final row = g.isEmpty ? List<Object?>.filled(scope.width,null) : g[0];
    if (s.having != null && !truth(evaluate(s.having!,row,g))) continue;
    results.add(Result(items.map((i) => evaluate(i.expr,row,g)).toList(),keys.map((k) => evaluate(k,row,g)).toList(),results.length));
  }
  if (keys.isNotEmpty) results.sort((a,b) {
    for (var i = 0; i < keys.length; i++) {
      final c = compare(a.keys[i],b.keys[i]);
      if (c != 0) return s.orders[i].descending ? -c : c;
    }
    return a.ordinal.compareTo(b.ordinal);
  });
  if (s.distinct) {
    final seen = <String>{};
    results = results.where((r) => seen.add(rowKey(r.values))).toList();
  }
  printTable(items,types,results.skip(s.offset).take(s.limit ?? results.length).map((r) => r.values).toList());
}
void execute(Statement s) {
  if (s.command.isEmpty || s.command == 'EXIT') return;
  if (s.command == 'SELECT') {
    executeSelect(s);
    return;
  }
  if (s.command == 'CREATE') {
    if (database.containsKey(s.name)) fail('table ${s.name} already exists');
    final seen = <String>{};
    var keys = 0;
    for (final c in s.columns) {
      if (!seen.add(c.name)) fail('duplicate column ${c.name}');
      keys += c.keys;
      if (keys > 1) fail('multiple primary keys');
    }
    database[s.name] = Table(s.name,s.columns);
    print('Table ${s.name} created.');
    return;
  }
  final original = lookup(s.name);
  final t = Table(original.name,original.columns,original.rows.map((r) => List<Object?>.of(r)).toList());
  if (s.command == 'DROP') {
    database.remove(s.name);
    print('Table ${s.name} dropped.');
    return;
  }
  final scope = Scope()..add(t.name,t);
  if (s.command == 'INSERT') {
    final columns = targets(s.names ?? t.columns.map((c) => c.name).toList(),t);
    for (final tuple in s.tuples) {
      if (tuple.length != columns.length) fail('expected ${columns.length} values, got ${tuple.length}');
      for (var j = 0; j < tuple.length; j++) {
        final c = t.columns[columns[j]];
        require(check(tuple[j],Scope()),c.type,'column ${c.name}');
      }
    }
    final start = t.rows.length;
    for (final tuple in s.tuples) {
      final row = List<Object?>.filled(t.columns.length,null);
      for (var j = 0; j < tuple.length; j++) {
        row[columns[j]] = evaluate(tuple[j],[]);
      }
      t.rows.add(row);
    }
    constraints(t,List.generate(t.rows.length-start,(i) => start+i));
    database[s.name] = t;
    countMessage(s.tuples.length,'inserted');
    return;
  }
  var assigned = <int>[];
  if (s.command == 'UPDATE') {
    assigned = targets(s.assignments.map((a) => a.$1).toList(),t);
    for (var j = 0; j < assigned.length; j++) {
      final c = t.columns[assigned[j]];
      require(check(s.assignments[j].$2,scope),c.type,'column ${c.name}');
    }
  }
  condition(s.whereExpr,scope,'WHERE');
  final affected = List.generate(t.rows.length,(i) => i).where((i) => s.whereExpr == null || truth(evaluate(s.whereExpr!,t.rows[i]))).toList();
  if (s.command == 'DELETE') {
    final removed = affected.toSet();
    t.rows = [
      for (var i = 0; i < t.rows.length; i++)
        if (!removed.contains(i)) t.rows[i]
    ];
  }
  else {
    for (final i in affected) {
      final before = List<Object?>.of(t.rows[i]);
      for (var j = 0; j < assigned.length; j++) {
        t.rows[i][assigned[j]] = evaluate(s.assignments[j].$2,before);
      }
    }
    constraints(t,affected);
  }
  database[s.name] = t;
  countMessage(affected.length,s.command == 'DELETE' ? 'deleted' : 'updated');
}
void main() {
  final input = stdin.readLineSync;
  final buffer = StringBuffer();
  String? line;
  while ((line = input()) != null) {
    buffer.writeln(line);
  }
  final source = buffer.toString();
  var start = 0;
  var quoted = false;
  var comment = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (comment) {
      if (c == '\n') comment = false;
    }
    else if (c == "'") {
      quoted = !quoted;
    }
    else if (!quoted && c == '-' && i+1 < source.length && source[i+1] == '-') {
      comment = true;
    }
    else if (!quoted && c == ';') {
      try {
        final s = Parser(tokenize(source.substring(start,i+1))).parse();
        if (s.command == 'EXIT') break;
        execute(s);
      } on SqlError catch (e) {
        print('ERROR: ${e.reason}');
      }
      start = i+1;
    }
  }
}
