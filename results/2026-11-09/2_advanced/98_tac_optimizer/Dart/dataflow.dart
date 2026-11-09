part of 'main.dart';

typedef Definition = (String, int);
typedef CopyPair = (String, String);

class Flow<T> {
  final Map<int, Set<T>> incoming = {}, outgoing = {}, before = {};
  int iterations = 0;
}

Set<Definition> reachingTransfer(
  Instruction instruction,
  int number,
  Set<Definition> state,
) {
  final result = Set<Definition>.of(state);
  if (instruction.destination.isNotEmpty) {
    result.removeWhere((d) => d.$1 == instruction.destination);
    result.add((instruction.destination, number));
  }
  return result;
}

Set<String> liveTransfer(Instruction instruction, Set<String> state) =>
    Set<String>.of(state)
      ..remove(instruction.destination)
      ..addAll(instruction.used);
Set<Expression> expressionTransfer(
  Instruction instruction,
  int number,
  Set<Expression> state,
) {
  final result = Set<Expression>.of(state);
  final expression = instruction.expression;
  if (expression != null) result.add(expression);
  result.removeWhere(
    (e) =>
        instruction.kind == 'store' &&
            e.kind == 'load' &&
            e.operation == instruction.name ||
        instruction.kind == 'call' && e.kind == 'load' ||
        instruction.destination.isNotEmpty && e.uses(instruction.destination),
  );
  return result;
}

Set<CopyPair> copyTransfer(
  Instruction instruction,
  int number,
  Set<CopyPair> state,
) {
  final result = Set<CopyPair>.of(state);
  if (instruction.destination.isNotEmpty)
    result.removeWhere(
      (p) => p.$1 == instruction.destination || p.$2 == instruction.destination,
    );
  if (instruction.kind == 'copy' &&
      !instruction.a.isConstant &&
      instruction.destination != instruction.a.variable)
    result.add((instruction.destination, instruction.a.variable));
  return result;
}

Flow<T> forward<T>(
  Cfg graph,
  Set<T> universe,
  Set<T> entry,
  bool union,
  Set<T> Function(Instruction, int, Set<T>) transfer,
) {
  final flow = Flow<T>();
  for (final n in graph.reachable) flow.outgoing[n] = Set.of(universe);
  while (true) {
    flow.iterations++;
    var changed = false;
    for (final n in graph.reversePostorder) {
      var state = <T>{};
      var first = true;
      for (final pred in graph.block(n).predecessors) {
        if (!graph.reachable.contains(pred)) continue;
        if (union) {
          state.addAll(flow.outgoing[pred]!);
        } else if (first) {
          state = Set.of(flow.outgoing[pred]!);
          first = false;
        } else {
          state.retainAll(flow.outgoing[pred]!);
        }
      }
      if (n == 1) {
        if (union) {
          state.addAll(entry);
        } else {
          state = {};
        }
      }
      flow.incoming[n] = Set.of(state);
      final block = graph.block(n);
      for (var i = block.first; i <= block.last; i++)
        state = transfer(graph.at(i), i, state);
      if (!equalSet(state, flow.outgoing[n]!)) {
        flow.outgoing[n] = state;
        changed = true;
      }
    }
    if (!changed) break;
  }
  for (final block in graph.orderedBlocks) {
    if (!block.reachable) continue;
    var state = Set<T>.of(flow.incoming[block.number]!);
    for (var n = block.first; n <= block.last; n++) {
      flow.before[n] = Set.of(state);
      state = transfer(graph.at(n), n, state);
    }
  }
  return flow;
}

class DataFlow {
  final Cfg graph;
  late final Flow<Definition> reaching;
  late final Flow<Expression> expressions;
  late final Flow<CopyPair> copies;
  final Map<int, Set<String>> liveIn = {},
      liveOut = {},
      liveBefore = {},
      liveAfter = {};
  int liveIterations = 0;
  DataFlow(this.graph) {
    final expressionUniverse = <Expression>{};
    final copyUniverse = <CopyPair>{};
    final parameters = {for (final p in graph.function.parameters) (p, 0)};
    for (final block in graph.orderedBlocks) {
      if (!block.reachable) continue;
      for (var n = block.first; n <= block.last; n++) {
        final instruction = graph.at(n);
        final expression = instruction.expression;
        if (expression != null) expressionUniverse.add(expression);
        if (instruction.kind == 'copy' &&
            !instruction.a.isConstant &&
            instruction.destination != instruction.a.variable)
          copyUniverse.add((instruction.destination, instruction.a.variable));
      }
    }
    reaching = forward(
      graph,
      <Definition>{},
      parameters,
      true,
      reachingTransfer,
    );
    expressions = forward(
      graph,
      expressionUniverse,
      <Expression>{},
      false,
      expressionTransfer,
    );
    copies = forward(graph, copyUniverse, <CopyPair>{}, false, copyTransfer);
    for (final n in graph.reachable) liveIn[n] = {};
    while (true) {
      liveIterations++;
      var changed = false;
      for (final n in graph.postorder) {
        var state = <String>{};
        for (final next in graph.block(n).successors)
          state.addAll(liveIn[next]!);
        liveOut[n] = Set.of(state);
        final block = graph.block(n);
        for (var i = block.last; i >= block.first; i--)
          state = liveTransfer(graph.at(i), state);
        if (!equalSet(state, liveIn[n]!)) {
          liveIn[n] = state;
          changed = true;
        }
      }
      if (!changed) break;
    }
    for (final block in graph.orderedBlocks) {
      if (!block.reachable) continue;
      var state = Set<String>.of(liveOut[block.number]!);
      for (var n = block.last; n >= block.first; n--) {
        liveAfter[n] = Set.of(state);
        state = liveTransfer(graph.at(n), state);
        liveBefore[n] = Set.of(state);
      }
    }
  }
}
