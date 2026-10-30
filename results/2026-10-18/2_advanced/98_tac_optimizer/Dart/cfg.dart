part of 'main.dart';

bool equalSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
List<int> sortedInts(Set<int> set) => set.toList()..sort();
List<String> sortedStrings(Set<String> set) => set.toList()..sort();

class Block {
  final int number, first, start;
  int last, end = 0, idom = 0, depth = 0;
  final List<String> labels;
  final List<int> predecessors = [], successors = [];
  Set<int> dom = {};
  bool reachable = false;
  Block(this.number, this.first, this.start, this.labels) : last = first;
}

class NaturalLoop {
  final int header;
  final List<int> latches = [];
  final Set<int> blocks, exits = {}, outside = {};
  int depth = 0;
  NaturalLoop(this.header) : blocks = {header};
}

class Cfg {
  final FunctionCode function;
  final List<Block?> blocks = [null];
  final List<Instruction?> instructions = [null];
  final Map<int, int> blockOf = {}, positions = {};
  final List<int> postorder = [], reversePostorder = [];
  final Set<int> reachable = {};
  final List<NaturalLoop> loops = [];
  Block block(int n) => blocks[n]!;
  Instruction at(int n) => instructions[n]!;
  Iterable<Block> get orderedBlocks => blocks.skip(1).cast<Block>();
  Cfg(this.function) {
    var pending = <String>[];
    var pendingStart = 0;
    Block? current;
    Instruction? previous;
    for (var i = 0; i < function.code.length; i++) {
      final line = function.code[i];
      final instruction = line.instruction;
      if (instruction == null) {
        if (pending.isEmpty) pendingStart = i;
        pending.add(line.label);
        continue;
      }
      final number = instructions.length;
      instruction.number = number;
      instructions.add(instruction);
      positions[number] = i;
      if (current == null ||
          pending.isNotEmpty ||
          {'goto', 'if', 'return'}.contains(previous!.kind)) {
        final start = pending.isNotEmpty ? pendingStart : i;
        if (current != null) current.end = start;
        current = Block(blocks.length, number, start, List.of(pending));
        blocks.add(current);
      } else {
        current.last = number;
      }
      pending = [];
      blockOf[number] = current.number;
      previous = instruction;
    }
    current!.end = function.code.length;
    final labels = <String, int>{
      for (final b in orderedBlocks)
        for (final label in b.labels) label: b.number,
    };
    for (final b in orderedBlocks) {
      final instruction = at(b.last);
      switch (instruction.kind) {
        case 'goto':
          b.successors.add(labels[instruction.name]!);
        case 'if':
          b.successors.add(b.number + 1);
          final target = labels[instruction.name]!;
          if (target != b.number + 1) b.successors.add(target);
        case 'return':
          break;
        default:
          b.successors.add(b.number + 1);
      }
      for (final next in b.successors) block(next).predecessors.add(b.number);
    }
    void visit(int n) {
      reachable.add(n);
      block(n).reachable = true;
      for (final next in block(n).successors) {
        if (!reachable.contains(next)) visit(next);
      }
      postorder.add(n);
    }

    visit(1);
    reversePostorder.addAll(postorder.reversed);
    for (final n in reversePostorder) block(n).dom = Set.of(reachable);
    block(1).dom = {1};
    while (true) {
      var changed = false;
      for (final n in reversePostorder.skip(1)) {
        Set<int>? dom;
        for (final pred in block(n).predecessors) {
          if (!reachable.contains(pred)) continue;
          if (dom == null) {
            dom = Set.of(block(pred).dom);
          } else {
            dom.retainAll(block(pred).dom);
          }
        }
        final dominance = dom!;
        dominance.add(n);
        if (!equalSet(dominance, block(n).dom)) {
          block(n).dom = dominance;
          changed = true;
        }
      }
      if (!changed) break;
    }
    for (final b in orderedBlocks) {
      if (!b.reachable || b.number == 1) continue;
      var best = 0;
      for (final d in b.dom) {
        if (d != b.number &&
            (best == 0 || block(d).dom.length > block(best).dom.length))
          best = d;
      }
      b.idom = best;
    }
    for (final h in orderedBlocks) {
      if (!h.reachable) continue;
      final loop = NaturalLoop(h.number);
      for (final t in orderedBlocks) {
        if (t.reachable &&
            t.dom.contains(h.number) &&
            t.successors.contains(h.number)) {
          loop.latches.add(t.number);
          loop.blocks.add(t.number);
        }
      }
      if (loop.latches.isEmpty) continue;
      final queue = List<int>.of(loop.latches);
      for (var head = 0; head < queue.length; head++) {
        final n = queue[head];
        if (n == h.number) continue;
        for (final pred in block(n).predecessors) {
          if (reachable.contains(pred) && loop.blocks.add(pred))
            queue.add(pred);
        }
      }
      for (final n in loop.blocks) {
        final b = block(n);
        if (at(b.last).kind == 'return') loop.exits.add(n);
        for (final next in b.successors) {
          if (!loop.blocks.contains(next)) {
            loop.exits.add(n);
            loop.outside.add(next);
          }
        }
      }
      loops.add(loop);
    }
    for (final loop in loops) {
      for (final other in loops) {
        if (other.blocks.contains(loop.header)) loop.depth++;
      }
      for (final n in loop.blocks) block(n).depth++;
    }
  }
}
