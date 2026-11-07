part of 'main.dart';

class PotentialSpill {
  final String name;
  final int degree;
  PotentialSpill(this.name, this.degree);
}

class Allocation {
  final List<String> nodes;
  final Map<String, Set<String>> neighbors = {}, partners = {};
  final Map<String, BigInt> costs = {};
  final List<String> simplify = [];
  final List<PotentialSpill> potential = [];
  final Map<String, int> registers = {};
  final Set<String> spills = {};
  int edges = 0;
  Allocation(this.nodes);
}

Allocation allocate(Cfg graph, DataFlow data, int k) {
  final nodes = <String>{...graph.function.parameters};
  for (final block in graph.orderedBlocks) {
    if (!block.reachable) continue;
    for (var n = block.first; n <= block.last; n++) {
      final instruction = graph.at(n);
      if (instruction.destination.isNotEmpty)
        nodes.add(instruction.destination);
      nodes.addAll(instruction.used);
    }
  }
  final result = Allocation(sortedStrings(nodes));
  for (final node in result.nodes) {
    result.neighbors[node] = {};
    result.partners[node] = {};
    result.costs[node] = BigInt.zero;
  }
  void edge(String x, String y) {
    if (x == y || !nodes.contains(x) || !nodes.contains(y)) return;
    result.neighbors[x]!.add(y);
    result.neighbors[y]!.add(x);
  }

  for (final block in graph.orderedBlocks) {
    if (!block.reachable) continue;
    var live = Set<String>.of(data.liveOut[block.number]!);
    final weight = BigInt.from(10).pow(block.depth);
    for (var n = block.last; n >= block.first; n--) {
      final instruction = graph.at(n);
      final destination = instruction.destination;
      if (destination.isNotEmpty) {
        for (final value in live) {
          if (instruction.kind == 'copy' &&
              !instruction.a.isConstant &&
              value == instruction.a.variable)
            continue;
          edge(destination, value);
        }
        result.costs[destination] = result.costs[destination]! + weight;
      }
      for (final value in instruction.used)
        result.costs[value] = result.costs[value]! + weight;
      live = liveTransfer(instruction, live);
    }
  }
  final entry = {...data.liveIn[1]!, ...graph.function.parameters};
  for (final parameter in graph.function.parameters) {
    result.costs[parameter] = result.costs[parameter]! + BigInt.one;
    for (final value in entry) edge(parameter, value);
  }
  for (final line in graph.function.code) {
    final instruction = line.instruction;
    if (instruction != null &&
        instruction.kind == 'copy' &&
        !instruction.a.isConstant &&
        instruction.destination != instruction.a.variable &&
        nodes.contains(instruction.destination) &&
        nodes.contains(instruction.a.variable)) {
      result.partners[instruction.destination]!.add(instruction.a.variable);
      result.partners[instruction.a.variable]!.add(instruction.destination);
    }
  }
  for (final node in result.nodes)
    result.edges += result.neighbors[node]!.length;
  result.edges ~/= 2;
  final remaining = Set<String>.of(nodes);
  while (remaining.isNotEmpty) {
    final degrees = {
      for (final node in remaining)
        node: result.neighbors[node]!.where(remaining.contains).length,
    };
    String? chosen;
    var low = false;
    for (final node in result.nodes) {
      if (!remaining.contains(node) || degrees[node]! >= k) continue;
      if (!low || degrees[node]! < degrees[chosen]!) {
        chosen = node;
        low = true;
      }
    }
    if (!low) {
      for (final node in result.nodes) {
        if (!remaining.contains(node)) continue;
        if (chosen == null ||
            result.costs[node]! * BigInt.from(degrees[chosen]!) <
                result.costs[chosen]! * BigInt.from(degrees[node]!))
          chosen = node;
      }
      result.potential.add(PotentialSpill(chosen!, degrees[chosen]!));
    }
    result.simplify.add(chosen!);
    remaining.remove(chosen);
  }
  for (final node in result.simplify.reversed) {
    final forbidden = <int>{
      for (final neighbor in result.neighbors[node]!)
        if (result.registers.containsKey(neighbor)) result.registers[neighbor]!,
    };
    int? chosen;
    for (final partner in result.partners[node]!) {
      final register = result.registers[partner];
      if (register != null &&
          !forbidden.contains(register) &&
          (chosen == null || register < chosen))
        chosen = register;
    }
    if (chosen == null) {
      for (var r = 0; r < k; r++) {
        if (!forbidden.contains(r)) {
          chosen = r;
          break;
        }
      }
    }
    if (chosen == null) {
      result.spills.add(node);
    } else {
      result.registers[node] = chosen;
    }
  }
  return result;
}
