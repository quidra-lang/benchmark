import 'dart:io';
import 'dart:math';
part 'lexer.dart';
part 'parser.dart';
part 'semantic.dart';
part 'codegen.dart';
part 'vm.dart';

class Source {
  final String name;
  final int firstLine;
  final List<String> lines = [];
  Source(this.name, this.firstLine);
}

class Warning {
  final Position position;
  final String message;
  Warning(this.position, this.message);
}

const ruleNames = [
  'const-jump',
  'not-compare',
  'not-jump',
  'invert-branch',
  'thread',
  'jump-next',
  'unreachable',
];
int comparePositions(Position a, Position b) =>
    a.line != b.line ? a.line.compareTo(b.line) : a.column.compareTo(b.column);
Set<Symbol> reachableFunctions(Program p) {
  final reachable = <Symbol>{};
  void visit(Symbol f) {
    if (!reachable.add(f)) return;
    for (final callee in f.calls) {
      visit(callee);
    }
  }

  visit(p.names['main']!);
  return reachable;
}

List<Warning> collectWarnings(Program p, Set<Symbol> reachable) {
  final out = <Warning>[];
  for (final symbol in p.symbols) {
    if (symbol.kind != 'function' && symbol.reads == 0) {
      final kind = symbol.kind == 'parameter' ? 'parameter' : 'variable';
      out.add(
        Warning(
          symbol.declaration.name.position,
          "unused $kind '${symbol.name}'",
        ),
      );
    }
  }
  for (final f in p.functions) {
    if (!reachable.contains(f.symbol))
      out.add(
        Warning(
          f.name.position,
          "function '${f.name.spelling}' is never called",
        ),
      );
    walkStatements(f.body, (s) {
      if (s.kind != 'block') return;
      for (var i = 0; i < s.statements.length; i++) {
        if (!canComplete(s.statements[i])) {
          if (i + 1 < s.statements.length)
            out.add(
              Warning(
                s.statements[i + 1].token.position,
                'unreachable statement',
              ),
            );
          break;
        }
      }
    });
  }
  out.sort((a, b) => comparePositions(a.position, b.position));
  return out;
}

bool literal(Expr e) => e.kind == 'integer' || e.kind == 'boolean';
bool inRange(int v) => v >= -2147483648 && v <= 2147483647;
Expr foldedLiteral(Expr e, int value) =>
    Expr(e.type == 'bool' ? 'boolean' : 'integer', e.token, value: value)
      ..type = e.type;
int? constantBinary(String op, int a, int b) {
  switch (op) {
    case '+':
      {
        final value = a + b;
        return inRange(value) ? value : null;
      }
    case '-':
      {
        final value = a - b;
        return inRange(value) ? value : null;
      }
    case '*':
      {
        final value = a * b;
        return inRange(value) ? value : null;
      }
    case '/':
    case '%':
      if (b == 0) return null;
      final q = a ~/ b;
      return op == '/' ? (inRange(q) ? q : null) : a - q * b;
    default:
      final answer = switch (op) {
        '<' => a < b,
        '<=' => a <= b,
        '>' => a > b,
        '>=' => a >= b,
        '==' => a == b,
        '!=' => a != b,
        '&&' => a != 0 && b != 0,
        _ => a != 0 || b != 0,
      };
      return answer ? 1 : 0;
  }
}

class Folder {
  int count = 0;
  Expr? expression(Expr? e) {
    if (e == null) return null;
    for (var i = 0; i < e.children.length; i++) {
      e.children[i] = expression(e.children[i])!;
    }
    if (e.kind == 'unary' && literal(e.children.first)) {
      var value = e.children.first.value;
      if (e.token.spelling == '-') {
        value = -value;
        if (!inRange(value)) return e;
      } else {
        value = value == 0 ? 1 : 0;
      }
      count++;
      return foldedLiteral(e, value);
    }
    if (e.kind != 'binary') return e;
    final left = e.children[0], right = e.children[1], op = e.token.spelling;
    if (literal(left) && literal(right)) {
      final value = constantBinary(op, left.value, right.value);
      if (value != null) {
        count++;
        return foldedLiteral(e, value);
      }
    }
    if (literal(left)) {
      if (op == '&&' && left.value == 0 || op == '||' && left.value != 0) {
        count++;
        return foldedLiteral(e, left.value);
      }
      if (op == '&&' && left.value != 0 ||
          op == '||' && left.value == 0 ||
          op == '+' && left.value == 0 ||
          op == '*' && left.value == 1) {
        count++;
        return right;
      }
    }
    if (literal(right) &&
        (op == '+' && right.value == 0 ||
            op == '-' && right.value == 0 ||
            op == '*' && right.value == 1 ||
            op == '/' && right.value == 1 ||
            op == '&&' && right.value != 0 ||
            op == '||' && right.value == 0)) {
      count++;
      return left;
    }
    return e;
  }

  Statement? statement(Statement? s) {
    if (s == null) return null;
    switch (s.kind) {
      case 'if':
        s.condition = expression(s.condition);
        if (literal(s.condition!)) {
          final replacement = s.condition!.value != 0
              ? statement(s.thenStatement)
              : s.elseStatement != null
              ? statement(s.elseStatement)
              : Statement('empty', s.token);
          count++;
          return replacement;
        }
        s.thenStatement = statement(s.thenStatement);
        s.elseStatement = statement(s.elseStatement);
        break;
      case 'while':
        s.condition = expression(s.condition);
        if (literal(s.condition!) && s.condition!.value == 0) {
          count++;
          return Statement('empty', s.token);
        }
        s.body = statement(s.body);
        break;
      case 'for':
        s.init = statement(s.init);
        s.condition = expression(s.condition);
        s.update = statement(s.update);
        s.body = statement(s.body);
        break;
      case 'block':
        for (var i = 0; i < s.statements.length; i++) {
          s.statements[i] = statement(s.statements[i])!;
        }
        break;
      case 'declaration':
        s.declaration!.initializer = expression(s.declaration!.initializer);
        break;
      case 'assignment':
        s.index = expression(s.index);
        s.expression = expression(s.expression);
        break;
      case 'call':
      case 'return':
        s.expression = expression(s.expression);
        break;
      case 'print':
        for (var i = 0; i < s.expressions.length; i++) {
          s.expressions[i] = expression(s.expressions[i])!;
        }
        break;
    }
    return s;
  }

  int program(Program p, Set<Symbol> reachable) {
    for (final d in p.globals) {
      d.initializer = expression(d.initializer);
    }
    for (final f in p.functions) {
      if (reachable.contains(f.symbol)) f.body = statement(f.body);
    }
    return count;
  }
}

String inverse(String op) => op == 'JUMPF' ? 'JUMPT' : 'JUMPF';
bool branchTaken(String op, int value) =>
    op == 'JUMPF' && value == 0 || op == 'JUMPT' && value != 0;
void deleteInstruction(Unit unit, int index) {
  unit.code.removeAt(index);
  for (final instruction in unit.code) {
    if (jump(instruction.op) && instruction.a > index) instruction.a--;
  }
}

List<int> optimize(Unit unit) {
  final counts = List.filled(7, 0),
      negations = {
        'LT': 'GE',
        'GE': 'LT',
        'LE': 'GT',
        'GT': 'LE',
        'EQ': 'NE',
        'NE': 'EQ',
      };
  while (true) {
    final targets = {
      for (final instruction in unit.code)
        if (jump(instruction.op)) instruction.a,
    };
    var applied = false;
    for (var i = 0; i < unit.code.length; i++) {
      final a = unit.code[i],
          free = i + 1 < unit.code.length && !targets.contains(i + 1),
          b = i + 1 < unit.code.length ? unit.code[i + 1] : null;
      var rule = -1;
      if (a.op == 'PUSH' && free && b != null && conditional(b.op)) {
        if (branchTaken(b.op, a.a)) {
          unit.code[i] = Instruction('JUMP', b.position, a: b.a);
          deleteInstruction(unit, i + 1);
        } else {
          deleteInstruction(unit, i + 1);
          deleteInstruction(unit, i);
        }
        rule = 0;
      } else if (negations.containsKey(a.op) &&
          free &&
          b != null &&
          b.op == 'NOT') {
        unit.code[i].op = negations[a.op]!;
        deleteInstruction(unit, i + 1);
        rule = 1;
      } else if (a.op == 'NOT' && free && b != null && conditional(b.op)) {
        unit.code[i] = Instruction(inverse(b.op), b.position, a: b.a);
        deleteInstruction(unit, i + 1);
        rule = 2;
      } else if (conditional(a.op) &&
          a.a == i + 2 &&
          free &&
          b != null &&
          b.op == 'JUMP') {
        unit.code[i] = Instruction(inverse(a.op), a.position, a: b.a);
        deleteInstruction(unit, i + 1);
        rule = 3;
      } else {
        if (jump(a.op) && a.a < unit.code.length) {
          final t = a.a, target = unit.code[t];
          var newTarget = -1;
          if (target.op == 'JUMP') {
            newTarget = target.a;
          } else if (target.op == 'PUSH' &&
              t + 1 < unit.code.length &&
              conditional(unit.code[t + 1].op)) {
            final next = unit.code[t + 1];
            newTarget = branchTaken(next.op, target.a) ? next.a : t + 2;
          }
          if (newTarget >= 0 && newTarget != t) {
            unit.code[i].a = newTarget;
            rule = 4;
          }
        }
        if (rule < 0 && jump(a.op) && a.a == i + 1) {
          if (a.op == 'JUMP') {
            deleteInstruction(unit, i);
          } else {
            unit.code[i] = Instruction('POP', a.position);
          }
          rule = 5;
        }
        if (rule < 0 && transfer(a.op) && free) {
          deleteInstruction(unit, i + 1);
          rule = 6;
        }
      }
      if (rule >= 0) {
        counts[rule]++;
        applied = true;
        break;
      }
    }
    if (!applied) return counts;
  }
}

int arrange(List<Unit> units) {
  var start = 0;
  final starts = <Declaration?, int>{};
  for (final unit in units) {
    unit.start = start;
    starts[unit.function] = start;
    start += unit.code.length;
  }
  for (final unit in units) {
    for (final instruction in unit.code) {
      if (instruction.op == 'CALL') instruction.a = starts[instruction.callee]!;
    }
  }
  return start;
}

int stackEffect(Instruction instruction) {
  switch (instruction.op) {
    case 'PUSH':
    case 'LOADG':
    case 'LOADL':
    case 'READ':
      return 1;
    case 'POP':
    case 'STOREG':
    case 'STOREL':
    case 'JUMPF':
    case 'JUMPT':
    case 'RETV':
    case 'ADD':
    case 'SUB':
    case 'MUL':
    case 'DIV':
    case 'MOD':
    case 'LT':
    case 'LE':
    case 'GT':
    case 'GE':
    case 'EQ':
    case 'NE':
      return -1;
    case 'STOREA':
      return -2;
    case 'CALL':
      return -instruction.b + (instruction.callee!.type != 'void' ? 1 : 0);
    case 'PRINT':
      return -instruction.a;
  }
  return 0;
}

void analyzeUnit(Unit unit) {
  final n = unit.code.length, leaders = <int>{0};
  for (var i = 0; i < n; i++) {
    final instruction = unit.code[i];
    if (jump(instruction.op) && instruction.a < n) leaders.add(instruction.a);
    if ((jump(instruction.op) || transfer(instruction.op)) && i + 1 < n)
      leaders.add(i + 1);
  }
  final indices = leaders.toList()..sort(), blockOf = List.filled(n, 0);
  for (var k = 0; k < indices.length; k++) {
    final first = indices[k],
        last = k + 1 < indices.length ? indices[k + 1] - 1 : n - 1;
    for (var i = first; i <= last; i++) {
      blockOf[i] = k;
    }
    unit.blocks.add(BasicBlock(first, last));
  }
  for (final block in unit.blocks) {
    final last = unit.code[block.last], successors = <int>[];
    if (last.op == 'JUMP') {
      successors.add(last.a);
    } else if (conditional(last.op)) {
      successors.addAll([block.last + 1, last.a]);
    } else if (!transfer(last.op)) {
      successors.add(block.last + 1);
    }
    final seen = <int>{};
    for (final index in successors) {
      if (index < n && seen.add(blockOf[index]))
        block.successors.add(blockOf[index]);
    }
  }
  final depths = List.filled(n, -1), queue = [0];
  depths[0] = 0;
  for (var head = 0; head < queue.length; head++) {
    final i = queue[head],
        instruction = unit.code[i],
        nextDepth = depths[i] + stackEffect(instruction),
        next = <int>[];
    unit.stack = max(unit.stack, nextDepth);
    if (!transfer(instruction.op) && i + 1 < n) next.add(i + 1);
    if (jump(instruction.op) && instruction.a < n) next.add(instruction.a);
    for (final j in next) {
      if (depths[j] < 0) {
        depths[j] = nextDepth;
        queue.add(j);
      }
    }
  }
}

bool recursive(Symbol function) {
  final seen = <Symbol>{};
  bool visit(Symbol current) {
    seen.add(current);
    for (final callee in current.calls) {
      if (identical(callee, function)) return true;
      if (!seen.contains(callee) && visit(callee)) return true;
    }
    return false;
  }

  return visit(function);
}

String spelling(Instruction instruction, int start) {
  var out = instruction.op;
  final a = instruction.a + (jump(instruction.op) ? start : 0);
  if (wordIn(
    'PUSH LOADG STOREG LOADL STOREL LOADA STOREA JUMP JUMPF JUMPT CALL ENTER PRINT',
    instruction.op,
  ))
    out += ' $a';
  if (instruction.op == 'LOADA' ||
      instruction.op == 'STOREA' ||
      instruction.op == 'CALL')
    out += ' ${instruction.b}';
  return out;
}

String callees(Symbol symbol) {
  final names = symbol.calls.map((s) => s.name).toList()..sort();
  return names.isEmpty ? '-' : names.join(',');
}

List<String> listing(
  Program p,
  List<Unit> before,
  List<Unit> after,
  int beforeCount,
  int afterCount,
) {
  final out = <String>[];
  if (p.globals.isEmpty) {
    out.add('globals: none');
  } else {
    out.add('globals:');
    for (final d in p.globals) {
      final type = d.array ? 'int[${d.size!.integer}]' : d.type;
      out.add('  ${d.symbol!.address} ${d.name.spelling} $type');
    }
  }
  out.add('functions:');
  for (var i = 0; i < after.length; i++) {
    final unit = after[i], f = unit.function;
    var signature = '', calls = 'main', suffix = '';
    if (f != null) {
      signature = ' ${f.type}(${f.parameters.map((p) => p.type).join(',')})';
      calls = callees(f.symbol!);
      if (recursive(f.symbol!)) suffix = ' recursive';
    }
    out.add(
      '  ${unit.name}$signature address=${before[i].start}->${unit.start} size=${before[i].code.length}->${unit.code.length} slots=${unit.slots} stack=${unit.stack} blocks=${unit.blocks.length} calls=$calls$suffix',
    );
    if (f != null) {
      for (var slot = 0; slot < f.slots.length; slot++) {
        final symbol = f.slots[slot];
        out.add('    slot $slot ${symbol.name} ${symbol.type}');
      }
    }
  }
  out.add('references:');
  for (final d in [...p.globals, ...p.functions]) {
    final ordered = {
      for (final position in d.symbol!.references) position.line,
    }.toList()..sort();
    out.add(
      '  ${d.name.spelling} defined ${d.name.position.line} used ${ordered.isEmpty ? '-' : ordered.join(' ')}',
    );
  }
  for (var pass = 0; pass < 2; pass++) {
    final units = pass == 0 ? before : after,
        label = pass == 0 ? 'before' : 'after',
        count = pass == 0 ? beforeCount : afterCount;
    out.add('$label peephole: $count instructions');
    for (final unit in units) {
      out.add('${unit.name}:');
      for (var i = 0; i < unit.code.length; i++) {
        out.add(
          '${(unit.start + i).toString().padLeft(5, ' ')}  ${spelling(unit.code[i], unit.start)}',
        );
      }
    }
  }
  out.add('control flow:');
  for (final unit in after) {
    out.add('  ${unit.name}');
    for (var k = 0; k < unit.blocks.length; k++) {
      final block = unit.blocks[k];
      var line =
          '    B$k ${unit.start + block.first}-${unit.start + block.last}';
      if (block.successors.isNotEmpty)
        line +=
            ' -> ${[for (final successor in block.successors) 'B$successor'].join(' ')}';
      out.add(line);
    }
  }
  return out;
}

bool sameBehavior(RunResult a, RunResult b) {
  if (a.error != b.error || a.output.length != b.output.length) return false;
  for (var i = 0; i < a.output.length; i++) {
    if (a.output[i] != b.output[i]) return false;
  }
  return true;
}

int sumCounts(List<int> values) => values.fold(0, (a, b) => a + b);
List<MapEntry<String, int>> sortedCounts(
  Map<String, int> counts,
  bool positive,
) =>
    [
      for (final entry in counts.entries)
        if (!positive || entry.value > 0) entry,
    ]..sort(
      (a, b) => a.value != b.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key),
    );
List<String> statsLines(
  List<Unit> units,
  int beforeCount,
  int afterCount,
  int folds,
  List<int> rules,
  RunResult run,
  RunResult comparison,
) {
  final behaviour = sameBehavior(run, comparison) ? 'same' : 'different',
      out = [
        'code: $beforeCount -> $afterCount',
        'folds: $folds',
        'peephole: ${sumCounts(rules)}',
      ];
  for (var i = 0; i < ruleNames.length; i++) {
    out.add('  ${ruleNames[i]} ${rules[i]}');
  }
  out.addAll([
    'executed: ${run.executed}',
    'executed before peephole: ${comparison.executed}',
    'behaviour: $behaviour',
    'max call depth: ${run.maximumDepth}',
    'max stack: ${run.maximumStack}',
    'opcodes:',
  ]);
  final code = flatten(units),
      opcodes = <String, int>{},
      functions = {
        for (final unit in units)
          if (unit.function != null) unit.name: 0,
      },
      lineCounts = <int, int>{};
  for (var pc = 0; pc < code.length; pc++) {
    final entry = code[pc],
        instruction = entry.instruction,
        count = run.counts[pc];
    opcodes[instruction.op] = (opcodes[instruction.op] ?? 0) + count;
    if (entry.unit.function != null)
      functions[entry.unit.name] = functions[entry.unit.name]! + count;
    lineCounts[instruction.position.line] =
        (lineCounts[instruction.position.line] ?? 0) + count;
  }
  for (final record in sortedCounts(opcodes, true)) {
    out.add('  ${record.key} ${record.value}');
  }
  out.add('functions:');
  for (final record in sortedCounts(functions, false)) {
    out.add(
      '  ${record.key} calls=${run.calls[record.key] ?? 0} executed=${record.value}',
    );
  }
  out.add('calls:');
  final pairs =
      [
        for (final pair in run.pairs.keys)
          if (run.pairs[pair]! > 0) pair,
      ]..sort((a, b) {
        final c = run.pairs[b]!.compareTo(run.pairs[a]!);
        if (c != 0) return c;
        final caller = a.$1.compareTo(b.$1);
        return caller != 0 ? caller : a.$2.compareTo(b.$2);
      });
  for (final pair in pairs) {
    out.add('  ${pair.$1} -> ${pair.$2} ${run.pairs[pair]}');
  }
  final positive =
          [
            for (final line in lineCounts.keys)
              if (lineCounts[line]! > 0) line,
          ]..sort((a, b) {
            final c = lineCounts[b]!.compareTo(lineCounts[a]!);
            return c != 0 ? c : a.compareTo(b);
          }),
      negative = [
        for (final line in lineCounts.keys)
          if (lineCounts[line] == 0) line,
      ]..sort();
  out.add('hot lines:');
  for (final line in positive.take(5)) {
    out.add('  line $line: ${lineCounts[line]}');
  }
  out.addAll([
    'coverage: ${positive.length} of ${lineCounts.length} lines',
    'not executed: ${negative.isEmpty ? 'none' : negative.join(' ')}',
    'hot spots:',
  ]);
  final pcs =
      [
        for (var pc = 0; pc < run.counts.length; pc++)
          if (run.counts[pc] > 0) pc,
      ]..sort(
        (a, b) => run.counts[a] != run.counts[b]
            ? run.counts[b].compareTo(run.counts[a])
            : a.compareTo(b),
      );
  for (final pc in pcs.take(5)) {
    out.add(
      '  pc=$pc count=${run.counts[pc]} ${spelling(code[pc].instruction, 0)}',
    );
  }
  return out;
}

List<String> positionDisplay(Position pos, List<String> allLines) => [
  '  ${allLines[pos.line - 1]}',
  '${List.filled(pos.column + 1, ' ').join()}^',
];
List<String> runtimeDiagnostics(
  List<Unit> units,
  RunResult run,
  List<String> allLines,
) {
  final code = flatten(units),
      entry = code[run.faultPC],
      out = [
        'runtime error ${entry.instruction.position}: ${run.error} in ${entry.unit.name}',
        ...positionDisplay(entry.instruction.position, allLines),
      ],
      count = max(0, run.frames.length - 1);
  var shown = 0;
  for (var i = run.frames.length - 1; i >= 1 && shown < 5; i--) {
    final caller = code[run.frames[i].returnAddress - 1];
    out.add(
      '  called from ${caller.unit.name} at ${caller.instruction.position}',
    );
    shown++;
  }
  if (count > shown) out.add('  ... ${count - shown} more');
  return out;
}

List<Source> sources(List<String> lines) {
  final out = <Source>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('#program ')) {
      out.add(Source(line.substring(9), i + 2));
    } else {
      out.last.lines.add(line);
    }
  }
  return out;
}

Map<String, List<int>> inputs() {
  final out = <String, List<int>>{};
  var name = '';
  for (final line in File('input/input.txt').readAsLinesSync()) {
    if (line.startsWith('#input ')) {
      name = line.substring(7);
      out[name] = [];
    } else {
      out[name]!.addAll(line.split(' ').map(int.parse));
    }
  }
  return out;
}

void writeLines(String path, List<String> lines) =>
    File('output/$path').writeAsStringSync('${lines.join('\n')}\n');
void main() {
  final allLines = File('input/program.src').readAsLinesSync(),
      programs = sources(allLines),
      input = inputs(),
      listingReport = <String>[],
      output = <String>[],
      diagnostics = <String>[],
      statistics = <String>[],
      errors = <String, int>{},
      totalRules = List.filled(7, 0),
      table = <List<String>>[
        ['program', 'status', 'code', 'executed', 'output'],
      ];
  var compiled = 0, runtimeErrors = 0, totalFolds = 0, totalExecuted = 0;
  for (final source in programs) {
    final heading = '== program ${source.name} ==';
    listingReport.add(heading);
    output.add(heading);
    diagnostics.add(heading);
    statistics.add(heading);
    Program? program;
    CompileError? failure;
    try {
      final tokens = tokenize(source.lines, source.firstLine);
      program = Parser(tokens).program();
      Semantics(program).analyze();
    } on CompileError catch (error) {
      failure = error;
    }
    final error = failure;
    if (error != null) {
      errors[error.kind] = (errors[error.kind] ?? 0) + 1;
      listingReport.add('not compiled');
      statistics.add('not compiled');
      diagnostics.add(
        '${error.kind} error ${error.position}: ${error.message}',
      );
      diagnostics.addAll(positionDisplay(error.position, allLines));
      diagnostics.add('status: compile error');
      table.add([source.name, '${error.kind} error', '-', '-', '-']);
      continue;
    }
    compiled++;
    final p = program!,
        reachable = reachableFunctions(p),
        warnings = collectWarnings(p, reachable);
    for (final warning in warnings) {
      diagnostics.add('warning ${warning.position}: ${warning.message}');
    }
    final folds = Folder().program(p, reachable);
    final (before, cells) = generate(p, reachable);
    final beforeCount = arrange(before),
        after = <Unit>[],
        rules = List.filled(7, 0);
    for (final original in before) {
      final unit = Unit(
            original.name,
            function: original.function,
            code: original.code.map(Instruction.copy).toList(),
            slots: original.slots,
          ),
          counts = optimize(unit);
      for (var i = 0; i < counts.length; i++) {
        rules[i] += counts[i];
      }
      analyzeUnit(unit);
      after.add(unit);
    }
    final afterCount = arrange(after);
    listingReport.addAll(listing(p, before, after, beforeCount, afterCount));
    final run = execute(after, cells, input[source.name] ?? []),
        comparison = execute(before, cells, input[source.name] ?? []);
    output.addAll(run.output);
    var status = 'ok';
    if (run.error.isNotEmpty) {
      runtimeErrors++;
      status = 'runtime error';
      diagnostics.addAll(runtimeDiagnostics(after, run, allLines));
    }
    diagnostics.add('status: $status');
    statistics.addAll(
      statsLines(after, beforeCount, afterCount, folds, rules, run, comparison),
    );
    totalFolds += folds;
    totalExecuted += run.executed;
    for (var i = 0; i < rules.length; i++) {
      totalRules[i] += rules[i];
    }
    table.add([
      source.name,
      status,
      '$afterCount',
      '${run.executed}',
      '${run.output.length}',
    ]);
  }
  statistics.addAll([
    '== summary ==',
    'programs: ${programs.length}',
    'compiled: $compiled',
    'compile errors: lexical ${errors['lexical'] ?? 0} syntax ${errors['syntax'] ?? 0} semantic ${errors['semantic'] ?? 0}',
    'runtime errors: $runtimeErrors',
    'folds: $totalFolds',
    'peephole: ${sumCounts(totalRules)}',
  ]);
  for (var i = 0; i < ruleNames.length; i++) {
    statistics.add('  ${ruleNames[i]} ${totalRules[i]}');
  }
  statistics.add('executed: $totalExecuted');
  final widths = List.filled(5, 0);
  for (final row in table) {
    for (var i = 0; i < row.length; i++) {
      widths[i] = max(widths[i], row[i].length);
    }
  }
  for (final row in table) {
    statistics.add(
      '  ${[for (var i = 0; i < row.length; i++) i < 2 ? row[i].padRight(widths[i], ' ') : row[i].padLeft(widths[i], ' ')].join('  ')}',
    );
  }
  Directory('output').createSync(recursive: true);
  writeLines('listing.txt', listingReport);
  writeLines('output.txt', output);
  writeLines('diagnostics.txt', diagnostics);
  writeLines('stats.txt', statistics);
}
