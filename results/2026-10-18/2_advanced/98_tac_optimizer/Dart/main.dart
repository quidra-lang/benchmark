import 'dart:io';
import 'dart:math';
part 'tac_parser.dart';
part 'cfg.dart';
part 'dataflow.dart';
part 'optimizations.dart';
part 'regalloc.dart';

const passOrder = [
  'constprop',
  'copyprop',
  'cse',
  'dce',
  'licm',
  'unreachable',
];

class PassResult {
  final int count;
  final List<String> records;
  PassResult([this.count = 0, this.records = const []]);
}

PassResult constantPropagation(
  FunctionCode function,
  Cfg graph,
  DataFlow data,
) {
  final records = <String>[];
  final replacements = <int, List<CodeLine>>{};
  for (final block in graph.orderedBlocks) {
    if (!block.reachable) continue;
    for (var n = block.first; n <= block.last; n++) {
      final copy = graph.at(n).copy();
      final operands = graph.at(n).operands;
      var changed = false;
      for (var i = 0; i < operands.length; i++) {
        final operand = operands[i];
        if (operand.isConstant) continue;
        var found = false, valid = true;
        var value = 0;
        for (final definition in data.reaching.before[n]!) {
          if (definition.$1 != operand.variable) continue;
          if (definition.$2 == 0) {
            valid = false;
            break;
          }
          final source = graph.at(definition.$2);
          if (source.kind != 'copy' ||
              !source.a.isConstant ||
              found && value != source.a.value) {
            valid = false;
            break;
          }
          found = true;
          value = source.a.value;
        }
        if (found && valid) {
          operands[i] = constant(value);
          records.add('#$n: ${operand.variable} -> $value');
          changed = true;
        }
      }
      copy.setOperands(operands);
      final (foldedInstruction, fold) = folded(copy);
      if (fold) {
        changed = true;
        records.add(
          copy.kind == 'if' && foldedInstruction == null
              ? '#$n: delete ${copy.text}'
              : '#$n: fold ${foldedInstruction!.text}',
        );
      }
      if (changed)
        replacements[n] = foldedInstruction == null
            ? []
            : [CodeLine.instruction(foldedInstruction)];
    }
  }
  rewrite(function, replacements);
  return PassResult(records.length, records);
}

PassResult copyPropagation(FunctionCode function, Cfg graph, DataFlow data) {
  final records = <String>[];
  final replacements = <int, List<CodeLine>>{};
  for (final block in graph.orderedBlocks) {
    if (!block.reachable) continue;
    for (var n = block.first; n <= block.last; n++) {
      final copy = graph.at(n).copy();
      final operands = graph.at(n).operands;
      var changed = false;
      for (var i = 0; i < operands.length; i++) {
        final operand = operands[i];
        if (operand.isConstant) continue;
        for (final pair in data.copies.before[n]!) {
          if (pair.$1 == operand.variable) {
            records.add('#$n: ${operand.variable} -> ${pair.$2}');
            operands[i] = (pair.$2, 0);
            changed = true;
            break;
          }
        }
      }
      if (changed) {
        copy.setOperands(operands);
        replacements[n] = [CodeLine.instruction(copy)];
      }
    }
  }
  rewrite(function, replacements);
  return PassResult(records.length, records);
}

class CseGroup {
  final Expression expression;
  final List<int> candidates = [];
  CseGroup(this.expression);
}

PassResult commonSubexpressions(
  FunctionCode function,
  Cfg graph,
  DataFlow data,
) {
  final groups = <Expression, CseGroup>{};
  for (final block in graph.orderedBlocks) {
    if (!block.reachable) continue;
    for (var n = block.first; n <= block.last; n++) {
      final expression = graph.at(n).expression;
      if (expression != null &&
          data.expressions.before[n]!.contains(expression))
        groups
            .putIfAbsent(expression, () => CseGroup(expression))
            .candidates
            .add(n);
    }
  }
  final replacements = <int, List<CodeLine>>{};
  final records = <String>[];
  var count = 0;
  for (final group in groups.values) {
    final candidates = group.candidates.toSet(), sources = <int>{};
    bool computes(int n) => graph.at(n).expression == group.expression;
    for (final n in group.candidates) {
      final block = graph.block(graph.blockOf[n]!);
      var found = false;
      for (var i = n - 1; i >= block.first; i--) {
        if (computes(i)) {
          sources.add(i);
          found = true;
          break;
        }
      }
      if (found) continue;
      final queue = List<int>.of(block.predecessors);
      final visited = <int>{};
      while (queue.isNotEmpty) {
        final p = queue.removeLast();
        if (!graph.reachable.contains(p) || !visited.add(p)) continue;
        final previous = graph.block(p);
        found = false;
        for (var i = previous.last; i >= previous.first; i--) {
          if (computes(i)) {
            sources.add(i);
            found = true;
            break;
          }
        }
        if (!found) queue.addAll(previous.predecessors);
      }
    }
    sources.removeAll(candidates);
    final (temporary, edits) = cseReplacements(
      function,
      graph,
      sources,
      candidates,
    );
    replacements.addAll(edits);
    records.add(
      '${group.expression.text}: $temporary sources=${instructionList(sortedInts(sources))} replaced=${instructionList(group.candidates)}',
    );
    count += group.candidates.length;
  }
  rewrite(function, replacements);
  return PassResult(count, records);
}

PassResult deadCode(FunctionCode function, Cfg graph, DataFlow data) {
  final replacements = <int, List<CodeLine>>{};
  final records = <int, String>{};
  for (final block in graph.orderedBlocks) {
    if (!block.reachable) continue;
    var live = Set<String>.of(data.liveOut[block.number]!);
    for (var n = block.last; n >= block.first; n--) {
      var instruction = graph.at(n);
      if (instruction.kind == 'copy' &&
              !instruction.a.isConstant &&
              instruction.destination == instruction.a.variable ||
          {'copy', 'bin', 'load'}.contains(instruction.kind) &&
              !live.contains(instruction.destination)) {
        replacements[n] = [];
        records[n] = '#$n: delete ${instruction.text}';
        continue;
      }
      if (instruction.kind == 'call' &&
          instruction.destination.isNotEmpty &&
          !live.contains(instruction.destination)) {
        records[n] = '#$n: unused result ${instruction.text}';
        instruction = instruction.copy()..destination = '';
        replacements[n] = [CodeLine.instruction(instruction)];
      }
      live = liveTransfer(instruction, live);
    }
  }
  final numbers = records.keys.toList()..sort();
  final lines = [for (final n in numbers) records[n]!];
  rewrite(function, replacements);
  return PassResult(lines.length, lines);
}

PassResult invariantMotion(FunctionCode function, Cfg graph, DataFlow data) {
  final loops = List<NaturalLoop>.of(graph.loops)
    ..sort(
      (a, b) => a.blocks.length != b.blocks.length
          ? a.blocks.length.compareTo(b.blocks.length)
          : a.header.compareTo(b.header),
    );
  for (final loop in loops) {
    final instructions = <int>[];
    final inside = <int>{};
    final stores = <String>{};
    final definitionCounts = <String, int>{};
    var hasCall = false;
    for (final block in graph.orderedBlocks) {
      if (!loop.blocks.contains(block.number)) continue;
      for (var n = block.first; n <= block.last; n++) {
        instructions.add(n);
        inside.add(n);
        final instruction = graph.at(n);
        if (instruction.destination.isNotEmpty)
          definitionCounts.update(
            instruction.destination,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        if (instruction.kind == 'store') stores.add(instruction.name);
        hasCall = hasCall || instruction.kind == 'call';
      }
    }
    final marked = <int>{};
    final order = <int>[];
    while (true) {
      var changed = false;
      for (final n in instructions) {
        if (marked.contains(n)) continue;
        final instruction = graph.at(n);
        if (!{'copy', 'bin', 'load'}.contains(instruction.kind)) continue;
        if (instruction.kind == 'load' &&
            (hasCall || stores.contains(instruction.name)))
          continue;
        var invariant = true;
        for (final variable in instruction.used) {
          final definitions = data.reaching.before[n]!
              .where((d) => d.$1 == variable)
              .toList();
          final hasInside = definitions.any((d) => inside.contains(d.$2));
          if (hasInside &&
              (definitions.length != 1 ||
                  !marked.contains(definitions.first.$2))) {
            invariant = false;
            break;
          }
        }
        if (invariant) {
          marked.add(n);
          order.add(n);
          changed = true;
        }
      }
      if (!changed) break;
    }
    final moves = <int>[];
    final moved = <int>{};
    for (final n in order) {
      final instruction = graph.at(n);
      final x = instruction.destination;
      if (definitionCounts[x] != 1 || data.liveIn[loop.header]!.contains(x))
        continue;
      final block = graph.blockOf[n]!;
      final dominates = loop.exits.every(
        (exit) => graph.block(exit).dom.contains(block),
      );
      final dangerous =
          instruction.kind == 'load' ||
          instruction.kind == 'bin' &&
              (instruction.operation == '/' || instruction.operation == '%') &&
              (!instruction.b.isConstant || instruction.b.value == 0);
      final outsideDead =
          !dangerous &&
          loop.outside.every((outside) => !data.liveIn[outside]!.contains(x));
      if (!dominates && !outsideDead) continue;
      var dependencies = true;
      for (final variable in instruction.used) {
        for (final definition in data.reaching.before[n]!) {
          if (definition.$1 == variable &&
              inside.contains(definition.$2) &&
              !moved.contains(definition.$2))
            dependencies = false;
        }
      }
      if (dependencies) {
        moves.add(n);
        moved.add(n);
      }
    }
    if (moves.isNotEmpty) {
      final destination = hoist(function, graph, loop, moves);
      return PassResult(moves.length, [
        'B${loop.header}: hoist ${instructionList(moves)} to $destination',
      ]);
    }
  }
  return PassResult();
}

PassResult applyPass(String name, FunctionCode function) {
  final graph = Cfg(function);
  final data = DataFlow(graph);
  switch (name) {
    case 'constprop':
      return constantPropagation(function, graph, data);
    case 'copyprop':
      return copyPropagation(function, graph, data);
    case 'cse':
      return commonSubexpressions(function, graph, data);
    case 'dce':
      return deadCode(function, graph, data);
    case 'licm':
      return invariantMotion(function, graph, data);
    case 'unreachable':
      final records = removeUnreachable(function, graph);
      return PassResult(records.length, records);
  }
  throw StateError('unknown pass');
}

String list(List<String> parts) => parts.isEmpty ? '-' : parts.join(',');
String blockList(List<int> numbers) => list(numbers.map((n) => 'B$n').toList());
String instructionList(List<int> numbers) =>
    list(numbers.map((n) => '#$n').toList());
String definitionList(Set<Definition> set) {
  final definitions = set.toList()
    ..sort(
      (a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
    );
  return list(definitions.map((d) => '${d.$1}:${d.$2}').toList());
}

String expressionList(Set<Expression> set) =>
    list(set.map((e) => e.text).toList()..sort());

class CallGraph {
  final Map<String, List<String>> callees = {};
  final Set<String> reachable = {}, recursive = {};
  CallGraph(Program program) {
    for (final function in program.functions) {
      final names = {
        for (final line in function.code)
          if (line.instruction?.kind == 'call') line.instruction!.name,
      };
      callees[function.name] = [
        for (final other in program.functions)
          if (names.contains(other.name)) other.name,
      ];
    }
    void visit(String name, Set<String> seen) {
      if (!seen.add(name)) return;
      for (final next in callees[name]!) visit(next, seen);
    }

    visit('main', reachable);
    for (final function in program.functions) {
      final seen = <String>{};
      for (final next in callees[function.name]!) visit(next, seen);
      if (seen.contains(function.name)) recursive.add(function.name);
    }
  }
}

List<String> callGraphLines(Program program, CallGraph graph) => [
  for (final function in program.functions)
    '${function.name} -> ${list(graph.callees[function.name]!)}${graph.recursive.contains(function.name) ? ' (recursive)' : ''}',
  'unreachable functions: ${list([for (final function in program.functions)
    if (!graph.reachable.contains(function.name)) function.name])}',
];
List<String> analysisLines(FunctionCode function, String heading) {
  final graph = Cfg(function);
  final data = DataFlow(graph);
  final result = ['== ${function.name} ($heading) ==', 'code:'];
  for (final line in function.code) {
    final instruction = line.instruction;
    if (instruction == null) {
      result.add('${line.label}:');
      continue;
    }
    var text = '  #${instruction.number} ${instruction.text}';
    if (graph.reachable.contains(graph.blockOf[instruction.number])) {
      final chains = <String>[];
      final seen = <String>{};
      for (final variable in instruction.used) {
        if (!seen.add(variable)) continue;
        final numbers = sortedInts({
          for (final definition in data.reaching.before[instruction.number]!)
            if (definition.$1 == variable) definition.$2,
        });
        chains.add('$variable:${numbers.join(',')}');
      }
      if (chains.isNotEmpty) text += ' | ${chains.join(' ')}';
    }
    result.add(text);
  }
  result.add('blocks: ${graph.blocks.length - 1}');
  final unreachable = <int>[];
  for (final block in graph.orderedBlocks) {
    result.add(
      'B${block.number} ${block.first}-${block.last} labels=${list(block.labels)} preds=${blockList(block.predecessors)} succs=${blockList(block.successors)}',
    );
    if (!block.reachable) unreachable.add(block.number);
  }
  result.addAll([
    'unreachable: ${blockList(unreachable)}',
    'order: ${blockList(graph.reversePostorder)}',
    'dominators:',
  ]);
  for (final block in graph.orderedBlocks) {
    if (block.reachable)
      result.add(
        'B${block.number} idom=${block.idom == 0 ? '-' : 'B${block.idom}'} dom=${blockList(sortedInts(block.dom))}',
      );
  }
  result.add('dominator tree:');
  void tree(int n, int depth) {
    result.add('${''.padLeft(2 * depth)}B$n');
    for (final block in graph.orderedBlocks) {
      if (block.reachable && block.idom == n) tree(block.number, depth + 1);
    }
  }

  tree(1, 0);
  result.add('loops: ${graph.loops.length}');
  for (final loop in graph.loops)
    result.add(
      'header=B${loop.header} latches=${blockList(loop.latches)} depth=${loop.depth} blocks=${blockList(sortedInts(loop.blocks))} exits=${blockList(sortedInts(loop.exits))}',
    );
  result.add('reaching definitions: iterations=${data.reaching.iterations}');
  for (final block in graph.orderedBlocks) {
    if (block.reachable)
      result.add(
        'B${block.number} in=${definitionList(data.reaching.incoming[block.number]!)} out=${definitionList(data.reaching.outgoing[block.number]!)}',
      );
  }
  result.add('liveness: iterations=${data.liveIterations}');
  for (final block in graph.orderedBlocks) {
    if (block.reachable)
      result.add(
        'B${block.number} in=${list(sortedStrings(data.liveIn[block.number]!))} out=${list(sortedStrings(data.liveOut[block.number]!))}',
      );
  }
  result.add(
    'available expressions: iterations=${data.expressions.iterations}',
  );
  for (final block in graph.orderedBlocks) {
    if (block.reachable)
      result.add(
        'B${block.number} in=${expressionList(data.expressions.incoming[block.number]!)} out=${expressionList(data.expressions.outgoing[block.number]!)}',
      );
  }
  return result;
}

(FunctionCode, int) allocatedFunction(
  FunctionCode function,
  Allocation allocation,
) {
  final result = function.copy();
  String rename(String name) => allocation.registers.containsKey(name)
      ? 'R${allocation.registers[name]}'
      : name;
  result.parameters = result.parameters.map(rename).toList();
  final code = <CodeLine>[];
  var removed = 0;
  for (final line in result.code) {
    final instruction = line.instruction;
    if (instruction != null) {
      if (instruction.destination.isNotEmpty)
        instruction.destination = rename(instruction.destination);
      instruction.setOperands([
        for (final operand in instruction.operands)
          operand.isConstant ? operand : (rename(operand.variable), 0),
      ]);
      if (instruction.kind == 'copy' &&
          !instruction.a.isConstant &&
          instruction.destination == instruction.a.variable) {
        removed++;
        continue;
      }
    }
    code.add(line);
  }
  result.code = code;
  return (result, removed);
}

(FunctionCode, List<String>) allocationLines(FunctionCode function, int k) {
  final graph = Cfg(function);
  final data = DataFlow(graph);
  final allocation = allocate(graph, data, k);
  final result = [
    '== ${function.name} ==',
    'nodes=${allocation.nodes.length} edges=${allocation.edges} registers=$k',
  ];
  for (final variable in allocation.nodes)
    result.add(
      '$variable degree=${allocation.neighbors[variable]!.length} cost=${allocation.costs[variable]} neighbors=${list(sortedStrings(allocation.neighbors[variable]!))}',
    );
  final potential = [
    for (final spill in allocation.potential)
      '${spill.name}(${allocation.costs[spill.name]}/${spill.degree})',
  ];
  result.addAll([
    'simplify: ${list(allocation.simplify)}',
    'potential spills: ${list(potential)}',
  ]);
  final used = <int>{};
  for (final variable in allocation.nodes) {
    final register = allocation.registers[variable];
    if (register != null) used.add(register);
    result.add('$variable -> ${register == null ? 'spill' : 'R$register'}');
  }
  var pressure = 0, spillUses = 0, spillDefs = 0;
  for (final n in data.liveBefore.keys)
    pressure = max(
      pressure,
      max(data.liveBefore[n]!.length, data.liveAfter[n]!.length),
    );
  for (final parameter in function.parameters) {
    if (allocation.spills.contains(parameter)) spillDefs++;
  }
  for (final line in function.code) {
    final instruction = line.instruction;
    if (instruction == null) continue;
    if (allocation.spills.contains(instruction.destination)) spillDefs++;
    for (final variable in instruction.used) {
      if (allocation.spills.contains(variable)) spillUses++;
    }
  }
  final (allocated, moves) = allocatedFunction(function, allocation);
  result.add(
    'summary: pressure=$pressure used=${used.length} spilled=${allocation.spills.length} moves=$moves spill_uses=$spillUses spill_defs=$spillDefs',
  );
  result.addAll(functionLines(allocated));
  return (allocated, result);
}

class Execution {
  final Map<String, int> steps = {}, calls = {}, kinds = {};
  final List<int> output = [];
}

class Interpreter {
  final Map<String, FunctionCode> functions;
  final Map<String, List<int>> arrays;
  final List<int> input;
  int inputIndex = 0;
  final Execution result = Execution();
  Interpreter(Program program, this.input)
    : functions = {
        for (final function in program.functions) function.name: function,
      },
      arrays = {
        for (final array in program.arrays)
          array.name: List.filled(array.size, 0),
      };
  int call(String name, List<int> arguments) {
    final function = functions[name]!;
    final variables = {
      for (var i = 0; i < function.parameters.length; i++)
        function.parameters[i]: arguments[i],
    };
    final labels = {
      for (var i = 0; i < function.code.length; i++)
        if (function.code[i].instruction == null) function.code[i].label: i + 1,
    };
    int value(Operand operand) =>
        operand.isConstant ? operand.value : variables[operand.variable]!;
    final pushed = <int>[];
    result.calls.update(name, (n) => n + 1, ifAbsent: () => 1);
    for (var pc = 0; pc < function.code.length;) {
      final instruction = function.code[pc++].instruction;
      if (instruction == null) continue;
      result.steps.update(name, (n) => n + 1, ifAbsent: () => 1);
      result.kinds.update(instruction.kind, (n) => n + 1, ifAbsent: () => 1);
      switch (instruction.kind) {
        case 'copy':
          variables[instruction.destination] = value(instruction.a);
        case 'bin':
          variables[instruction.destination] = calculate(
            instruction.operation,
            value(instruction.a),
            value(instruction.b),
          );
        case 'load':
          variables[instruction.destination] =
              arrays[instruction.name]![value(instruction.a)];
        case 'store':
          final index = value(instruction.a);
          arrays[instruction.name]![index] = value(instruction.b);
        case 'goto':
          pc = labels[instruction.name]!;
        case 'if':
          if (calculate(
                instruction.operation,
                value(instruction.a),
                value(instruction.b),
              ) !=
              0)
            pc = labels[instruction.name]!;
        case 'param':
          pushed.add(value(instruction.a));
        case 'call':
          final start = pushed.length - instruction.count;
          final args = pushed.sublist(start);
          pushed.removeRange(start, pushed.length);
          final returned = call(instruction.name, args);
          if (instruction.destination.isNotEmpty)
            variables[instruction.destination] = returned;
        case 'return':
          return instruction.hasA ? value(instruction.a) : 0;
        case 'read':
          variables[instruction.destination] = input[inputIndex++];
        case 'print':
          result.output.add(value(instruction.a));
      }
    }
    return 0;
  }
}

Execution executeProgram(Program program, List<int> input) {
  final vm = Interpreter(program, input);
  vm.call('main', []);
  return vm.result;
}

int total(Map<String, int> values) => values.values.fold(0, (a, b) => a + b);
Map<String, int> instructionCounts(Program program) {
  final counts = <String, int>{};
  for (final function in program.functions) {
    for (final line in function.code) {
      final instruction = line.instruction;
      if (instruction != null)
        counts.update(instruction.kind, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

String outputList(List<int> values) => list(values.map((n) => '$n').toList());
bool sameOutput(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> comparisons(
  Program original,
  Program optimized,
  Program allocated,
  List<List<int>> runs,
) {
  final programs = [original, optimized, allocated];
  final names = ['original', 'optimized', 'allocated'];
  final aggregates = [for (var i = 0; i < 3; i++) Execution()];
  final result = <String>[];
  var same = 0;
  for (var i = 0; i < runs.length; i++) {
    final input = runs[i];
    result.add('run ${i + 1}: inputs=${input.length}');
    final results = <Execution>[];
    for (var j = 0; j < programs.length; j++) {
      final execution = executeProgram(programs[j], input);
      results.add(execution);
      result.add(
        '  ${names[j]}: steps=${total(execution.steps)} calls=${total(execution.calls)} output=${outputList(execution.output)}',
      );
      for (final entry in execution.steps.entries)
        aggregates[j].steps.update(
          entry.key,
          (n) => n + entry.value,
          ifAbsent: () => entry.value,
        );
      for (final entry in execution.calls.entries)
        aggregates[j].calls.update(
          entry.key,
          (n) => n + entry.value,
          ifAbsent: () => entry.value,
        );
      for (final entry in execution.kinds.entries)
        aggregates[j].kinds.update(
          entry.key,
          (n) => n + entry.value,
          ifAbsent: () => entry.value,
        );
    }
    final identical =
        sameOutput(results[0].output, results[1].output) &&
        sameOutput(results[0].output, results[2].output);
    if (identical) same++;
    result.add('  result: ${identical ? 'same' : 'different'}');
  }
  result.add('== profile ==');
  for (final function in original.functions)
    result.add(
      '${function.name}: calls=${aggregates[0].calls[function.name] ?? 0} original=${aggregates[0].steps[function.name] ?? 0} optimized=${aggregates[1].steps[function.name] ?? 0} allocated=${aggregates[2].steps[function.name] ?? 0}',
    );
  final before = instructionCounts(original),
      after = instructionCounts(optimized);
  result.addAll([
    '== summary ==',
    'runs=${runs.length} same=$same different=${runs.length - same}',
    'instructions: original=${total(before)} optimized=${total(after)}',
    'kinds: ${[for (final kind in instructionKinds) '$kind=${before[kind] ?? 0}->${after[kind] ?? 0}'].join(' ')}',
    'steps: original=${total(aggregates[0].steps)} optimized=${total(aggregates[1].steps)} allocated=${total(aggregates[2].steps)}',
  ]);
  for (var j = 0; j < names.length; j++)
    result.add(
      'dynamic ${names[j]}: ${[for (final kind in instructionKinds) '$kind=${aggregates[j].kinds[kind] ?? 0}'].join(' ')}',
    );
  return result;
}

void save(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
void main() {
  final original = parseProgram();
  final parameters = readLines('input/params.txt');
  final optimized = original.copy();
  final registers = int.parse(words(parameters[0])[1]),
      maxRounds = int.parse(words(parameters[2])[1]);
  final enabled = words(parameters[1]).skip(1).toSet();
  final passes = passOrder.where(enabled.contains).toList();
  final analysis = [
    '== call graph (original) ==',
    ...callGraphLines(original, CallGraph(original)),
  ];
  for (final function in original.functions)
    analysis.addAll(analysisLines(function, 'original'));
  final passLines = <String>[];
  final totals = <String, int>{};
  for (final function in optimized.functions) {
    final before = Cfg(function).instructions.length - 1;
    passLines.add('== ${function.name} ==');
    var rounds = 0;
    for (var round = 1; round <= maxRounds; round++) {
      rounds = round;
      final parts = <String>[], records = <String>[];
      var changed = 0;
      for (final name in passes) {
        final result = applyPass(name, function);
        parts.add('$name=${result.count}');
        changed += result.count;
        totals.update(
          name,
          (n) => n + result.count,
          ifAbsent: () => result.count,
        );
        for (final record in result.records) records.add('  $name $record');
      }
      passLines.add('round $round: ${parts.join(' ')}');
      passLines.addAll(records);
      if (changed == 0) break;
    }
    passLines.add(
      'result: rounds=$rounds instructions=$before->${Cfg(function).instructions.length - 1}',
    );
  }
  final graph = CallGraph(optimized);
  analysis.add('== call graph (optimized) ==');
  analysis.addAll(callGraphLines(optimized, graph));
  final removed = <String>[];
  final kept = <FunctionCode>[];
  for (final function in optimized.functions) {
    if (enabled.contains('unreachable') &&
        !graph.reachable.contains(function.name)) {
      removed.add(function.name);
    } else {
      kept.add(function);
    }
  }
  optimized.functions = kept;
  for (final function in optimized.functions)
    analysis.addAll(analysisLines(function, 'optimized'));
  passLines.addAll([
    '== program ==',
    'removed functions: ${list(removed)}',
    '== total ==',
    [for (final name in passes) '$name=${totals[name] ?? 0}'].join(' '),
  ]);
  final allocated = Program(arrays: List.of(optimized.arrays));
  final allocation = <String>[];
  for (final function in optimized.functions) {
    final (result, lines) = allocationLines(function, registers);
    allocated.functions.add(result);
    allocation.addAll(lines);
  }
  final inputs = readLines('input/input.txt');
  final runs = <List<int>>[];
  for (final line in inputs.skip(1).take(int.parse(inputs[0])))
    runs.add(words(line).skip(1).map(int.parse).toList());
  Directory('output').createSync(recursive: true);
  save('optimized.tac', programLines(optimized));
  save('analysis.txt', analysis);
  save('passes.txt', passLines);
  save('regalloc.txt', allocation);
  save('comparison.txt', comparisons(original, optimized, allocated, runs));
}
