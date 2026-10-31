part of 'main.dart';

void rewrite(
  FunctionCode function,
  Map<int, List<CodeLine>> replacements, [
  Map<int, List<CodeLine>> insertions = const {},
]) {
  final result = <CodeLine>[];
  var number = 0;
  for (var i = 0; i < function.code.length; i++) {
    result.addAll(insertions[i] ?? []);
    final line = function.code[i];
    if (line.instruction != null) {
      number++;
      if (replacements.containsKey(number)) {
        result.addAll(replacements[number]!);
        continue;
      }
    }
    result.add(line);
  }
  result.addAll(insertions[function.code.length] ?? []);
  function.code = result;
}

(Instruction?, bool) folded(Instruction instruction) {
  if (instruction.kind != 'bin' && instruction.kind != 'if')
    return (instruction, false);
  final a = instruction.a, b = instruction.b;
  if (a.isConstant && b.isConstant) {
    if ((instruction.operation == '/' || instruction.operation == '%') &&
        b.value == 0)
      return (instruction, false);
    final value = calculate(instruction.operation, a.value, b.value);
    if (instruction.kind == 'if')
      return (
        value != 0 ? Instruction('goto', name: instruction.name) : null,
        true,
      );
    if (value >= -2147483648 && value <= 2147483647)
      return (
        Instruction(
          'copy',
          destination: instruction.destination,
          a: constant(value),
        ),
        true,
      );
    return (instruction, false);
  }
  if (instruction.kind != 'bin' || a.isConstant == b.isConstant)
    return (instruction, false);
  Operand? replacement;
  if (instruction.operation == '+' &&
      (a.isConstant && a.value == 0 || b.isConstant && b.value == 0)) {
    replacement = a.isConstant ? b : a;
  } else if (instruction.operation == '-' && b.isConstant && b.value == 0) {
    replacement = a;
  } else if (instruction.operation == '*' &&
      (a.isConstant && a.value == 1 || b.isConstant && b.value == 1)) {
    replacement = a.isConstant ? b : a;
  } else if (instruction.operation == '/' && b.isConstant && b.value == 1) {
    replacement = a;
  } else if (instruction.operation == '*' &&
      (a.isConstant && a.value == 0 || b.isConstant && b.value == 0)) {
    replacement = constant(0);
  }
  return replacement == null
      ? (instruction, false)
      : (
          Instruction(
            'copy',
            destination: instruction.destination,
            a: replacement,
          ),
          true,
        );
}

(String, Map<int, List<CodeLine>>) cseReplacements(
  FunctionCode function,
  Cfg graph,
  Set<int> sources,
  Set<int> candidates,
) {
  final temporary = '_t${++function.temporarySerial}';
  final replacements = <int, List<CodeLine>>{};
  for (final n in sources) {
    final old = graph.at(n);
    final copy = old.copy()..destination = temporary;
    replacements[n] = [
      CodeLine.instruction(copy),
      CodeLine.instruction(
        Instruction('copy', destination: old.destination, a: (temporary, 0)),
      ),
    ];
  }
  for (final n in candidates)
    replacements[n] = [
      CodeLine.instruction(
        Instruction(
          'copy',
          destination: graph.at(n).destination,
          a: (temporary, 0),
        ),
      ),
    ];
  return (temporary, replacements);
}

String hoist(
  FunctionCode function,
  Cfg graph,
  NaturalLoop loop,
  List<int> moves,
) {
  final header = graph.block(loop.header);
  final outside = header.predecessors
      .where((n) => !loop.blocks.contains(n))
      .toList();
  final replacements = <int, List<CodeLine>>{for (final n in moves) n: []};
  final instructions = [
    for (final n in moves) CodeLine.instruction(graph.at(n)),
  ];
  var position = 0;
  var destination = '';
  var insertion = instructions;
  if (loop.header != 1 &&
      outside.length == 1 &&
      graph.block(outside.first).successors.length == 1 &&
      graph.block(outside.first).successors.first == loop.header) {
    final preheader = graph.block(outside.first);
    final last = graph.at(preheader.last);
    position = graph.positions[preheader.last]!;
    if (last.kind != 'goto' && last.kind != 'if') position++;
    destination = 'B${preheader.number}';
  } else {
    final label = '_p${++function.preheaderSerial}';
    position = header.start;
    insertion = [CodeLine.label(label), ...instructions];
    destination = 'new $label';
    for (final pred in outside) {
      final n = graph.block(pred).last;
      final old = graph.at(n);
      if ((old.kind == 'goto' || old.kind == 'if') &&
          header.labels.contains(old.name))
        replacements[n] = [CodeLine.instruction(old.copy()..name = label)];
    }
  }
  rewrite(function, replacements, {position: insertion});
  return destination;
}

List<String> removeUnreachable(FunctionCode function, Cfg graph) {
  final records = <String>[];
  final deleted = <int>{};
  for (final block in graph.orderedBlocks) {
    if (!block.reachable) {
      records.add('remove block B${block.number}');
      for (var i = block.start; i < block.end; i++) deleted.add(i);
    }
  }
  final remaining = [
    for (var i = 0; i < function.code.length; i++)
      if (!deleted.contains(i)) function.code[i],
  ];
  final jumps = <int>{};
  for (var i = 0; i < remaining.length; i++) {
    final instruction = remaining[i].instruction;
    if (instruction == null ||
        instruction.kind != 'goto' && instruction.kind != 'if')
      continue;
    for (
      var j = i + 1;
      j < remaining.length && remaining[j].instruction == null;
      j++
    ) {
      if (remaining[j].label == instruction.name) {
        jumps.add(instruction.number);
        break;
      }
    }
  }
  for (final n in sortedInts(jumps)) records.add('remove jump #$n');
  final withoutJumps = <CodeLine>[];
  final targets = <String>{};
  for (final line in remaining) {
    final instruction = line.instruction;
    if (instruction != null && jumps.contains(instruction.number)) continue;
    withoutJumps.add(line);
    if (instruction != null &&
        (instruction.kind == 'goto' || instruction.kind == 'if'))
      targets.add(instruction.name);
  }
  function.code = [];
  for (final line in withoutJumps) {
    if (line.instruction == null && !targets.contains(line.label)) {
      records.add('remove label ${line.label}');
    } else {
      function.code.add(line);
    }
  }
  return records;
}
