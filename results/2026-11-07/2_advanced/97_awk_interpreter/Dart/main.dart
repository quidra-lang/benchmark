import 'dart:io';
import 'dart:math';
part 'lexer.dart';
part 'parser.dart';
part 'values_fields.dart';
part 'builtins.dart';
part 'streams.dart';

const specialNames = [
  'FILENAME',
  'FNR',
  'FS',
  'NF',
  'NR',
  'OFS',
  'ORS',
  'SUBSEP',
];

class StaticIssue implements Exception {
  final Position position;
  final int priority;
  final String message;
  StaticIssue(this.position, this.priority, this.message);
}

class Analysis {
  final List<Item> items;
  final List<Item> functions = [], rules = [];
  final Map<String, Item> functionTable = {};
  final Set<String> globals = {...specialNames};
  final Set<Binding> arrays = {};
  final List<Expr> expressions = [];
  final List<Statement> statements = [];
  final Set<int> lines = {};
  final List<StaticIssue> errors = [];
  Analysis(this.items) {
    for (final item in items)
      (item.kind == 'function' ? functions : rules).add(item);
  }
  void issue(Position position, int priority, String message) {
    errors.add(StaticIssue(position, priority, message));
  }

  void expression(Expr? node, Item? function) {
    if (node == null) return;
    expressions.add(node);
    if (node.kind == 'name' ||
        node.kind == 'array' ||
        node.kind == 'parameter') {
      if (function != null && function.parameterNames.containsKey(node.name)) {
        node.binding = (function, node.name);
      } else {
        node.binding = (null, node.name);
        globals.add(node.name);
      }
      if (functionTable.containsKey(node.name))
        issue(node.position, 2, 'function ${node.name} used as variable');
    } else if (node.kind == 'call') {
      final target = functionTable[node.name];
      node.function = target;
      if (target == null) {
        issue(node.position, 3, 'undefined function ${node.name}');
      } else if (node.args.length > target.parameters.length) {
        issue(node.position, 4, 'too many arguments to ${node.name}');
      }
    }
    expression(node.left, function);
    expression(node.right, function);
    expression(node.third, function);
    for (final arg in node.args) expression(arg, function);
  }

  void statement(Statement? node, Item? function) {
    if (node == null) return;
    statements.add(node);
    if (node.kind != 'block' && node.kind != 'empty')
      lines.add(node.position.line);
    for (final expr in node.exprs) expression(expr, function);
    expression(node.variable, function);
    expression(node.array, function);
    expression(node.redirect, function);
    for (final child in node.statements) statement(child, function);
    statement(node.body, function);
    statement(node.otherwise, function);
  }

  void prepare() {
    for (final function in functions) {
      if (functionTable.containsKey(function.name)) {
        issue(function.namePosition, 0, 'function ${function.name} redefined');
      } else {
        functionTable[function.name] = function;
      }
      for (final parameter in function.parameters) {
        if (function.parameterNames.containsKey(parameter.name))
          issue(parameter.position, 1, 'duplicate parameter ${parameter.name}');
        function.parameterNames[parameter.name] = true;
      }
    }
    for (final item in items) {
      final function = item.kind == 'function' ? item : null;
      for (final parameter in item.parameters) expression(parameter, function);
      for (final pattern in item.patterns) expression(pattern, function);
      statement(item.body, function);
    }
    if (errors.isNotEmpty) {
      errors.sort((a, b) {
        if (a.position.line != b.position.line)
          return a.position.line.compareTo(b.position.line);
        if (a.position.column != b.position.column)
          return a.position.column.compareTo(b.position.column);
        return a.priority.compareTo(b.priority);
      });
      throw errors.first;
    }
    final links = <(Binding, Binding)>[];
    for (final node in expressions) {
      switch (node.kind) {
        case 'array':
          arrays.add(node.binding);
        case 'membership':
          arrays.add(node.right!.binding);
        case 'builtin':
          if (node.name == 'split') arrays.add(node.args[1].binding);
        case 'call':
          for (var i = 0; i < node.args.length; i++) {
            if (node.args[i].kind == 'name')
              links.add((
                node.args[i].binding,
                node.function!.parameters[i].binding,
              ));
          }
      }
    }
    for (final node in statements) {
      if (node.kind == 'delete' || node.kind == 'for_in')
        arrays.add(node.array!.binding);
    }
    while (true) {
      var changed = false;
      for (final link in links) {
        if (arrays.contains(link.$1) && arrays.add(link.$2)) changed = true;
        if (arrays.contains(link.$2) && arrays.add(link.$1)) changed = true;
      }
      if (!changed) break;
    }
  }
}

class Cell {
  Value value;
  final Map<String, Value>? array;
  Cell({this.value = const Value(), this.array});
}

class Location {
  final String kind;
  final Cell? cell;
  final String key;
  final int index;
  final bool nf;
  Location(
    this.kind, {
    this.cell,
    this.key = '',
    this.index = 0,
    this.nf = false,
  });
}

class Transfer implements Exception {
  final String kind;
  final Value value;
  Transfer(this.kind, [this.value = const Value()]);
}

Value boolean(bool value) => numeric(value ? 1 : 0);
Value arithmetic(String op, Value a, Value b, Position position) {
  var x = a.number, y = b.number, result = 0;
  switch (op) {
    case '+':
      result = x + y;
    case '-':
      result = x - y;
    case '*':
      result = x * y;
    case '/':
    case '%':
      if (y == 0) runtimeError(position, 'division by zero');
      result = x ~/ y;
      if (op == '%') result = x - result * y;
    case '^':
      if (y < 0) runtimeError(position, 'negative exponent');
      result = 1;
      while (y > 0) {
        if ((y & 1) != 0) result *= x;
        y >>= 1;
        if (y > 0) x *= x;
      }
  }
  return numeric(result);
}

class Engine {
  final Analysis analysis;
  final List<Option> options;
  final List<Operand> operands;
  final Map<String, Cell> globals = {};
  final List<Map<String, Cell>> locals = [];
  late final AwkRecord record;
  final Streams streams = Streams();
  final Map<int, int> lines = {};
  String phase = 'BEGIN';
  int exitStatus = 0, operandIndex = 0, inputIndex = 0;
  RuntimeIssue? error;
  Operand? current;
  List<String> inputLines = [];
  Engine(this.analysis, this.options, this.operands) {
    for (final name in analysis.globals)
      globals[name] = Cell(
        array: analysis.arrays.contains((null, name)) ? {} : null,
      );
    for (final name in specialNames) globals[name]!.value = numeric(0);
    globals['FILENAME']!.value = stringValue('');
    globals['FS']!.value = stringValue(' ');
    globals['OFS']!.value = stringValue(' ');
    globals['ORS']!.value = stringValue('\n');
    globals['SUBSEP']!.value = stringValue(String.fromCharCode(28));
    for (final line in analysis.lines) lines[line] = 0;
    record = AwkRecord(global);
  }
  Cell cell(Binding binding) =>
      binding.$1 != null ? locals.last[binding.$2]! : globals[binding.$2]!;
  Value global(String name) =>
      name == 'NF' ? numeric(record.fields.length) : globals[name]!.value;
  void assignInput(String name, String text) {
    globals.putIfAbsent(name, Cell.new).value = inputValue(text);
  }

  String subscript(List<Expr> args) {
    final values = <String>[];
    for (final arg in args) values.add(evaluate(arg).text);
    return values.join(global('SUBSEP').text);
  }

  Location location(Expr node) {
    if (node.kind == 'name')
      return Location(
        'variable',
        cell: cell(node.binding),
        nf: node.binding.$1 == null && node.name == 'NF',
      );
    if (node.kind == 'array') {
      final key = subscript(node.args);
      return Location('array', cell: cell(node.binding), key: key);
    }
    final index = evaluate(node.left!).number;
    if (index < 0) runtimeError(node.position, 'negative field index');
    return Location('field', index: index);
  }

  Value read(Location location) {
    if (location.kind == 'field') return record.read(location.index);
    if (location.kind == 'array')
      return location.cell!.array!.putIfAbsent(
        location.key,
        () => const Value(),
      );
    return location.nf ? numeric(record.fields.length) : location.cell!.value;
  }

  void store(Location location, Value value, Position position) {
    switch (location.kind) {
      case 'field':
        record.write(location.index, value);
      case 'array':
        location.cell!.array![location.key] = value;
      default:
        if (location.nf) {
          final n = value.number;
          if (n < 0) runtimeError(position, 'negative NF');
          record.resize(n);
        } else {
          location.cell!.value = value;
        }
    }
  }

  Value evaluate(Expr node) {
    switch (node.kind) {
      case 'number':
      case 'string':
        return node.value;
      case 'name':
      case 'array':
      case 'field':
        return read(location(node));
      case 'paren':
        return evaluate(node.left!);
      case 'assignment':
        {
          final target = location(node.left!);
          var value = evaluate(node.right!);
          if (node.op != '=')
            value = arithmetic(node.op[0], read(target), value, node.position);
          store(target, value, node.position);
          return read(target);
        }
      case 'increment':
        {
          final target = location(node.left!);
          final old = read(target).number;
          final value = old + (node.op == '--' ? -1 : 1);
          store(target, numeric(value), node.position);
          return numeric(node.prefix ? value : old);
        }
      case 'conditional':
        return evaluate(evaluate(node.left!).truth ? node.right! : node.third!);
      case 'unary':
        {
          final value = evaluate(node.left!);
          if (node.op == '!') return boolean(!value.truth);
          return numeric(node.op == '-' ? -value.number : value.number);
        }
      case 'membership':
        {
          final key = subscript(node.args);
          return boolean(cell(node.right!.binding).array!.containsKey(key));
        }
      case 'binary':
        {
          final first = evaluate(node.left!);
          if (node.op == '||' && first.truth) return numeric(1);
          if (node.op == '&&' && !first.truth) return numeric(0);
          final second = evaluate(node.right!);
          if (node.op == '&&' || node.op == '||') return boolean(second.truth);
          if (node.op == 'concat') return stringValue(first.text + second.text);
          if (wordIn('< <= == != >= >', node.op)) {
            final order = compare(first, second);
            return boolean(switch (node.op) {
              '<' => order < 0,
              '<=' => order <= 0,
              '==' => order == 0,
              '!=' => order != 0,
              '>=' => order >= 0,
              _ => order > 0,
            });
          }
          return arithmetic(node.op, first, second, node.position);
        }
      case 'call':
        return call(node);
      case 'builtin':
        return builtin(node);
      case 'getline':
        return getline(node);
    }
    throw StateError('unknown expression');
  }

  Value call(Expr node) {
    final function = node.function!;
    final frame = <String, Cell>{};
    for (var i = 0; i < function.parameters.length; i++) {
      final parameter = function.parameters[i];
      if (analysis.arrays.contains(parameter.binding)) {
        frame[parameter.name] = i < node.args.length
            ? cell(node.args[i].binding)
            : Cell(array: {});
      } else {
        frame[parameter.name] = Cell(
          value: i < node.args.length ? evaluate(node.args[i]) : const Value(),
        );
      }
    }
    function.calls++;
    function.active++;
    function.depth = max(function.depth, function.active);
    locals.add(frame);
    try {
      statement(function.body!);
    } on Transfer catch (transfer) {
      if (transfer.kind == 'return') return transfer.value;
      rethrow;
    } finally {
      locals.removeLast();
      function.active--;
    }
    return const Value();
  }

  Value builtin(Expr node) {
    switch (node.name) {
      case 'length':
        if (node.args.isEmpty) return numeric(record.zero.text.length);
        final argument = node.args.first;
        if (argument.kind == 'name' &&
            analysis.arrays.contains(argument.binding))
          return numeric(cell(argument.binding).array!.length);
        return numeric(evaluate(argument).text.length);
      case 'split':
        final text = evaluate(node.args[0]).text;
        final separator = node.args.length == 3
            ? evaluate(node.args[2]).text
            : global('FS').text;
        final array = cell(node.args[1].binding).array!;
        array.clear();
        final pieces = splitPieces(text, separator);
        for (var i = 0; i < pieces.length; i++)
          array['${i + 1}'] = inputValue(pieces[i]);
        return numeric(pieces.length);
      case 'close':
        return numeric(streams.close(evaluate(node.args[0]).text));
    }
    final values = <Value>[];
    for (final argument in node.args) values.add(evaluate(argument));
    return invokeBuiltin(node.name, values, node.position);
  }

  Value getline(Expr node) {
    var status = 0;
    var line = '';
    if (node.right != null) {
      final name = evaluate(node.right!).text;
      final result = streams.getline(name);
      status = result.$1;
      line = result.$2;
    } else if (phase != 'END') {
      final result = nextRecord();
      if (result != null) {
        line = result;
        status = 1;
      }
    }
    if (status == 1) {
      if (node.left == null) {
        record.set(line);
      } else {
        final target = location(node.left!);
        store(target, inputValue(line), node.position);
      }
    }
    return numeric(status);
  }

  void output(Statement node) {
    final values = <Value>[];
    for (final argument in node.exprs) values.add(evaluate(argument!));
    String text;
    if (node.kind == 'print') {
      if (values.isEmpty) values.add(record.zero);
      text =
          values.map((v) => v.text).join(global('OFS').text) +
          global('ORS').text;
    } else {
      text = formatOutput(values, node.position);
    }
    final name = node.redirect == null ? '' : evaluate(node.redirect!).text;
    streams.write(text, name, node.redirectMode, node.redirectPosition);
  }

  bool loopBody(Statement body) {
    try {
      statement(body);
    } on Transfer catch (transfer) {
      if (transfer.kind == 'break') return false;
      if (transfer.kind != 'continue') rethrow;
    }
    return true;
  }

  void statement(Statement node) {
    if (node.kind == 'block') {
      for (final child in node.statements) statement(child);
      return;
    }
    if (node.kind == 'empty') return;
    lines.update(node.position.line, (n) => n + 1);
    switch (node.kind) {
      case 'expression':
        evaluate(node.exprs[0]!);
      case 'print':
      case 'printf':
        output(node);
      case 'if':
        if (evaluate(node.exprs[0]!).truth) {
          statement(node.body!);
        } else if (node.otherwise != null) {
          statement(node.otherwise!);
        }
      case 'while':
        while (evaluate(node.exprs[0]!).truth) {
          if (!loopBody(node.body!)) break;
        }
      case 'do':
        while (true) {
          if (!loopBody(node.body!) || !evaluate(node.exprs[0]!).truth) break;
        }
      case 'for':
        if (node.exprs[0] != null) evaluate(node.exprs[0]!);
        while (node.exprs[1] == null || evaluate(node.exprs[1]!).truth) {
          if (!loopBody(node.body!)) break;
          if (node.exprs[2] != null) evaluate(node.exprs[2]!);
        }
      case 'for_in':
        final keys = orderedSubscripts(cell(node.array!.binding).array!);
        for (final key in keys) {
          final target = location(node.variable!);
          store(target, inputValue(key), node.variable!.position);
          if (!loopBody(node.body!)) break;
        }
      case 'delete':
        final array = cell(node.array!.binding).array!;
        if (node.wholeDelete) {
          array.clear();
        } else {
          array.remove(subscript(node.exprs.cast<Expr>()));
        }
      case 'next':
        if (phase == 'BEGIN' || phase == 'END')
          runtimeError(node.position, 'next used in BEGIN or END');
        throw Transfer('next');
      case 'exit':
        if (node.exprs.isNotEmpty) exitStatus = evaluate(node.exprs[0]!).number;
        throw Transfer('exit');
      case 'return':
        throw Transfer(
          'return',
          node.exprs.isEmpty ? const Value() : evaluate(node.exprs[0]!),
        );
      case 'break':
      case 'continue':
        throw Transfer(node.kind);
    }
  }

  String? nextRecord() {
    while (true) {
      if (inputIndex < inputLines.length) {
        final line = inputLines[inputIndex++];
        current!.records++;
        globals['NR']!.value = numeric(global('NR').number + 1);
        globals['FNR']!.value = numeric(global('FNR').number + 1);
        return line;
      }
      if (operandIndex == operands.length) return null;
      final operand = operands[operandIndex++];
      if (operand.kind == 'assignment') {
        assignInput(operand.name, operand.value);
      } else {
        current = operand;
        inputLines = readRecords(operand.name);
        inputIndex = 0;
        globals['FILENAME']!.value = stringValue(operand.name);
        globals['FNR']!.value = numeric(0);
      }
    }
  }

  void actions(String kind) {
    phase = kind;
    for (final rule in analysis.rules) {
      if (rule.flavor == kind) {
        rule.count++;
        statement(rule.body!);
      }
    }
  }

  bool matches(Item rule) {
    if (rule.flavor == 'all') return true;
    if (rule.flavor == 'pattern') return evaluate(rule.patterns[0]).truth;
    if (!rule.inside && evaluate(rule.patterns[0]).truth) rule.inside = true;
    if (!rule.inside) return false;
    if (evaluate(rule.patterns[1]).truth) rule.inside = false;
    return true;
  }

  void records() {
    if (!analysis.rules.any((r) => r.flavor != 'BEGIN')) return;
    phase = 'records';
    while (true) {
      final line = nextRecord();
      if (line == null) return;
      record.set(line);
      try {
        for (final rule in analysis.rules) {
          if (rule.flavor == 'BEGIN' || rule.flavor == 'END') continue;
          if (matches(rule)) {
            rule.count++;
            if (rule.body == null) {
              streams.write(record.zero.text + global('ORS').text);
            } else {
              statement(rule.body!);
            }
          }
        }
      } on Transfer catch (transfer) {
        if (transfer.kind != 'next') rethrow;
      }
    }
  }

  void execute() {
    try {
      for (final option in options) assignInput(option.name, option.value);
      try {
        actions('BEGIN');
        records();
      } on Transfer catch (transfer) {
        if (transfer.kind != 'exit') rethrow;
      }
      try {
        actions('END');
      } on Transfer catch (transfer) {
        if (transfer.kind != 'exit') rethrow;
      }
    } on RuntimeIssue catch (failure) {
      error = failure;
    }
  }

  List<String> statistics() {
    final failure = error;
    final result = [
      failure == null
          ? 'status: exit $exitStatus'
          : 'status: runtime error at ${failure.position}: ${failure.message}',
      '[inputs]',
    ];
    for (final operand in operands) {
      if (operand.kind == 'file')
        result.add('${operand.name} records=${operand.records}');
    }
    result.add('[getline]');
    for (final entry in streams.inputs.entries)
      result.add(
        '${entry.key} ${entry.value.everOpened ? 'reads=${entry.value.reads}' : 'missing'}',
      );
    result.add('[rules]');
    for (final rule in analysis.rules)
      result.add('${rule.position} ${rule.flavor} count=${rule.count}');
    result.add('[functions]');
    for (final function in analysis.functions)
      result.add(
        '${function.name} calls=${function.calls} depth=${function.depth}',
      );
    result.add('[outputs]');
    result.add(
      'stdout.txt writes=${streams.stdout.writes} bytes=${streams.stdout.content.length}',
    );
    for (final entry in streams.outputs.entries)
      result.add(
        '${entry.key} writes=${entry.value.writes} bytes=${entry.value.content.length}',
      );
    result.add('[lines]');
    final lineNumbers = lines.keys.toList()..sort();
    for (final line in lineNumbers) result.add('$line count=${lines[line]}');
    result.add('[globals]');
    final globalNames = globals.keys.toList()..sort();
    for (final name in globalNames)
      result.add(
        '$name = ${analysis.arrays.contains((null, name)) ? 'array (${globals[name]!.array!.length})' : describe(global(name))}',
      );
    return result;
  }
}

void main() {
  final (options, operands) = parseArguments(
    textLines(readText('input/args.txt')),
  );
  var streams = Streams();
  List<String> statistics;
  try {
    final parser = Parser(tokenize(readText('input/program.awk')));
    final analysis = Analysis(parser.parse());
    analysis.prepare();
    final engine = Engine(analysis, options, operands);
    engine.execute();
    streams = engine.streams;
    statistics = engine.statistics();
  } on SyntaxIssue catch (failure) {
    statistics = ['status: syntax error at ${failure.position}'];
  } on StaticIssue catch (failure) {
    statistics = ['status: error at ${failure.position}: ${failure.message}'];
  }
  streams.save();
  File('output/stats.txt').writeAsStringSync('${statistics.join('\n')}\n');
}
