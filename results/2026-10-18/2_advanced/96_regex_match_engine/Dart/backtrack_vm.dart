part of 'main.dart';

class BacktrackState {
  final int pc, position;
  final List<int> captures;
  final Set<int> visited;
  BacktrackState(this.pc, this.position, List<int> captures, Set<int> visited)
    : captures = List.of(captures),
      visited = Set.of(visited);
}

class BacktrackResult {
  final List<int> captures;
  final int position;
  BacktrackResult(this.captures, this.position);
}

List<int> unsetCaptures(int groups) => List.filled(2 * groups + 2, -1);

class BacktrackVm {
  final List<Instruction> program;
  final String flags, text;
  final int groups;
  final bool full;
  int steps = 0;
  bool aborted = false;
  BacktrackVm(this.program, this.flags, this.groups, this.text, this.full);
  BacktrackResult? execute(
    int pc,
    int position,
    List<int> captures,
    bool partial,
  ) {
    final stack = [BacktrackState(pc, position, captures, {})];
    while (stack.isNotEmpty) {
      final state = stack.removeLast();
      var p = state.pc, q = state.position;
      var c = state.captures;
      var visited = state.visited;
      var running = true;
      while (running) {
        steps++;
        if (steps > 200000) {
          aborted = true;
          return null;
        }
        final instruction = program[p];
        switch (instruction.op) {
          case 'CHAR':
          case 'ANY':
          case 'CLASS':
            if (!consumes(instruction, text, q, flags)) {
              running = false;
              break;
            }
            p++;
            q++;
            visited = {};
          case 'SPLIT':
            if (visited.contains(p)) {
              running = false;
              break;
            }
            visited.add(p);
            stack.add(BacktrackState(instruction.y, q, c, visited));
            p = instruction.x;
          case 'JMP':
            p = instruction.x;
          case 'SAVE':
            c[instruction.number] = q;
            p++;
          case 'ASSERT':
            if (assertion(instruction.kind, text, q, flags)) {
              p++;
            } else {
              running = false;
            }
          case 'BACKREF':
            {
              final a = c[2 * instruction.number],
                  b = c[2 * instruction.number + 1];
              if (a < 0 || b < 0 || a > b || q + b - a > text.length) {
                running = false;
                break;
              }
              var matches = true;
              for (var j = 0; j < b - a; j++) {
                if (!charMatches(
                  text.codeUnitAt(q + j),
                  text.codeUnitAt(a + j),
                  flags,
                )) {
                  matches = false;
                  break;
                }
              }
              if (!matches) {
                running = false;
                break;
              }
              if (b > a) visited = {};
              q += b - a;
              p++;
            }
          case 'LOOK':
            {
              final result = execute(p + 1, q, c, true);
              if (aborted) return null;
              if (instruction.kind == 'NOT') {
                if (result == null) {
                  p = instruction.x;
                } else {
                  running = false;
                }
              } else if (result == null) {
                running = false;
              } else {
                c = result.captures;
                if (instruction.kind == 'ATOMIC') {
                  if (result.position > q) visited = {};
                  q = result.position;
                }
                p = instruction.x;
              }
            }
          case 'MATCH':
            if (partial || !full || q == text.length)
              return BacktrackResult(c, q);
            running = false;
        }
      }
    }
    return null;
  }

  List<int>? search(int start) {
    final last = full ? 0 : text.length;
    for (var b = full ? 0 : start; b <= last; b++) {
      final result = execute(0, b, unsetCaptures(groups), false);
      if (aborted) return null;
      if (result != null) return result.captures;
    }
    return null;
  }
}
