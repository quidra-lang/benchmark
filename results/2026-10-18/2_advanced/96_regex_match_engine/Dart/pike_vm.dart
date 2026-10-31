part of 'main.dart';

class PikeThread {
  final int pc;
  final List<int> captures;
  PikeThread(this.pc, List<int> captures) : captures = List.of(captures);
}

class ThreadList {
  final List<PikeThread> threads = [];
  final Set<int> marks = {};
}

class PikeVm {
  final List<Instruction> program;
  final String flags, text;
  final int groups;
  final bool full;
  int steps = 0;
  PikeVm(this.program, this.flags, this.groups, this.text, this.full);
  void add(ThreadList list, int p, List<int> captures, int q) {
    if (!list.marks.add(p)) return;
    steps++;
    final instruction = program[p];
    switch (instruction.op) {
      case 'JMP':
        add(list, instruction.x, captures, q);
      case 'SPLIT':
        add(list, instruction.x, captures, q);
        add(list, instruction.y, captures, q);
      case 'SAVE':
        final copy = List<int>.of(captures);
        copy[instruction.number] = q;
        add(list, p + 1, copy, q);
      case 'ASSERT':
        if (assertion(instruction.kind, text, q, flags))
          add(list, p + 1, captures, q);
      default:
        list.threads.add(PikeThread(p, captures));
    }
  }

  List<int>? search(int start) {
    List<int>? match;
    var list = ThreadList();
    for (var q = start; ; q++) {
      if (match == null && (!full || q == start))
        add(list, 0, unsetCaptures(groups), q);
      final next = ThreadList();
      for (final thread in list.threads) {
        steps++;
        final instruction = program[thread.pc];
        if (instruction.op == 'MATCH') {
          if (!full || q == text.length) {
            match = List.of(thread.captures);
            break;
          }
        } else if (consumes(instruction, text, q, flags)) {
          add(next, thread.pc + 1, thread.captures, q + 1);
        }
      }
      if (q == text.length || next.threads.isEmpty && (match != null || full))
        return match;
      list = next;
    }
  }
}
