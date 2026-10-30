part of 'main.dart';

class ExecutableInstruction {
  final Instruction instruction;
  final Unit unit;
  ExecutableInstruction(this.instruction, this.unit);
}

class Frame {
  final List<int> locals;
  final int returnAddress;
  Frame(this.locals, this.returnAddress);
}

class RunResult {
  final List<String> output = [];
  int executed = 0, maximumStack = 0, maximumDepth = 0, faultPC = -1;
  final List<int> counts;
  final Map<String, int> calls = {};
  final Map<(String, String), int> pairs = {};
  String error = '';
  List<Frame> frames = [];
  RunResult(int size) : counts = List.filled(size, 0);
}

List<ExecutableInstruction> flatten(List<Unit> units) {
  final out = <ExecutableInstruction>[];
  for (final unit in units) {
    for (final original in unit.code) {
      final instruction = Instruction.copy(original);
      if (jump(instruction.op)) instruction.a += unit.start;
      out.add(ExecutableInstruction(instruction, unit));
    }
  }
  return out;
}

RunResult execute(List<Unit> units, int cells, List<int> input) {
  final code = flatten(units),
      r = RunResult(code.length),
      globals = List.filled(cells, 0),
      stack = <int>[],
      frames = <Frame>[],
      starts = {for (final unit in units) unit.start: unit};
  var pc = 0, read = 0;
  int pop() => stack.removeLast();
  RunResult fault(String message) {
    r.error = message;
    r.faultPC = pc;
    r.frames = List.of(frames);
    return r;
  }

  while (true) {
    final entry = code[pc], instruction = entry.instruction;
    if (r.executed == 100000) return fault('instruction limit exceeded');
    r.executed++;
    r.counts[pc]++;
    var next = pc + 1;
    switch (instruction.op) {
      case 'PUSH':
        stack.add(instruction.a);
        break;
      case 'POP':
        pop();
        break;
      case 'LOADG':
        stack.add(globals[instruction.a]);
        break;
      case 'STOREG':
        globals[instruction.a] = pop();
        break;
      case 'LOADL':
        stack.add(frames.last.locals[instruction.a]);
        break;
      case 'STOREL':
        frames.last.locals[instruction.a] = pop();
        break;
      case 'LOADA':
      case 'STOREA':
        {
          final value = instruction.op == 'STOREA' ? pop() : 0, index = pop();
          if (index < 0 || index >= instruction.b)
            return fault(
              'index $index out of bounds for array of size ${instruction.b}',
            );
          final address = instruction.a + index;
          if (instruction.op == 'LOADA') {
            stack.add(globals[address]);
          } else {
            globals[address] = value;
          }
          break;
        }
      case 'ADD':
      case 'SUB':
      case 'MUL':
      case 'DIV':
      case 'MOD':
        {
          final b = pop(), a = pop();
          var value = 0;
          switch (instruction.op) {
            case 'ADD':
              value = a + b;
              break;
            case 'SUB':
              value = a - b;
              break;
            case 'MUL':
              value = a * b;
              break;
            case 'DIV':
            case 'MOD':
              if (b == 0) return fault('division by zero');
              final quotient = a ~/ b;
              value = instruction.op == 'DIV' ? quotient : a - quotient * b;
              break;
          }
          if (value < -2147483648 || value > 2147483647)
            return fault('integer overflow');
          stack.add(value);
          break;
        }
      case 'NEG':
        {
          final value = -pop();
          if (value < -2147483648 || value > 2147483647)
            return fault('integer overflow');
          stack.add(value);
          break;
        }
      case 'NOT':
        stack.add(pop() == 0 ? 1 : 0);
        break;
      case 'LT':
      case 'LE':
      case 'GT':
      case 'GE':
      case 'EQ':
      case 'NE':
        {
          final b = pop(),
              a = pop(),
              answer = switch (instruction.op) {
                'LT' => a < b,
                'LE' => a <= b,
                'GT' => a > b,
                'GE' => a >= b,
                'EQ' => a == b,
                _ => a != b,
              };
          stack.add(answer ? 1 : 0);
          break;
        }
      case 'JUMP':
        next = instruction.a;
        break;
      case 'JUMPF':
      case 'JUMPT':
        final value = pop();
        if (instruction.op == 'JUMPF' && value == 0 ||
            instruction.op == 'JUMPT' && value != 0)
          next = instruction.a;
        break;
      case 'CALL':
        {
          if (frames.length == 100) return fault('call depth limit exceeded');
          final count = instruction.b,
              locals = stack.sublist(stack.length - count);
          stack.removeRange(stack.length - count, stack.length);
          frames.add(Frame(locals, pc + 1));
          next = instruction.a;
          final called = starts[next]!.name, pair = (entry.unit.name, called);
          r.calls[called] = (r.calls[called] ?? 0) + 1;
          r.pairs[pair] = (r.pairs[pair] ?? 0) + 1;
          break;
        }
      case 'ENTER':
        while (frames.last.locals.length < instruction.a) {
          frames.last.locals.add(0);
        }
        break;
      case 'RET':
      case 'RETV':
        next = frames.removeLast().returnAddress;
        break;
      case 'READ':
        if (read == input.length) return fault('read past end of input');
        stack.add(input[read++]);
        break;
      case 'PRINT':
        final count = instruction.a,
            values = stack.sublist(stack.length - count);
        stack.removeRange(stack.length - count, stack.length);
        r.output.add(values.join(' '));
        break;
      case 'HALT':
        r.maximumStack = max(r.maximumStack, stack.length);
        r.maximumDepth = max(r.maximumDepth, frames.length);
        return r;
    }
    r.maximumStack = max(r.maximumStack, stack.length);
    r.maximumDepth = max(r.maximumDepth, frames.length);
    pc = next;
  }
}
