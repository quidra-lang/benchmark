'use strict';

class RuntimeError extends Error {}
const fail = message => { throw new RuntimeError(message); };
const checked = value => {
  if (value < -2147483648 || value > 2147483647) fail('integer overflow');
  return value === 0 ? 0 : value;
};
const comparisons = { LT: (a, b) => a < b, LE: (a, b) => a <= b, GT: (a, b) => a > b,
  GE: (a, b) => a >= b, EQ: (a, b) => a === b, NE: (a, b) => a !== b };

function run(code, globalSize, input) {
  const globals = Array(globalSize).fill(0), stack = [], frames = [], output = [], counts = Array(code.length).fill(0);
  const calls = new Map(), pairs = new Map();
  let pc = 0, readPosition = 0, executed = 0, maxStack = 0, maxDepth = 0, error = null;
  while (true) {
    const instruction = code[pc], { op, args } = instruction;
    if (executed === 100000) { error = { message: 'instruction limit exceeded', instruction }; break; }
    executed++; counts[pc]++;
    let next = pc + 1, halted = false;
    try {
      if (Object.hasOwn(comparisons, op)) {
        const b = stack.pop(), a = stack.pop(); stack.push(comparisons[op](a, b) ? 1 : 0);
      } else switch (op) {
        case 'PUSH': stack.push(args[0]); break;
        case 'POP': stack.pop(); break;
        case 'LOADG': stack.push(globals[args[0]]); break;
        case 'STOREG': globals[args[0]] = stack.pop(); break;
        case 'LOADL': stack.push(frames[frames.length - 1].locals[args[0]]); break;
        case 'STOREL': frames[frames.length - 1].locals[args[0]] = stack.pop(); break;
        case 'LOADA': case 'STOREA': {
          const value = op === 'STOREA' ? stack.pop() : null, index = stack.pop();
          if (index < 0 || index >= args[1]) fail(`index ${index} out of bounds for array of size ${args[1]}`);
          if (op === 'STOREA') globals[args[0] + index] = value; else stack.push(globals[args[0] + index]);
          break;
        }
        case 'ADD': case 'SUB': case 'MUL': case 'DIV': case 'MOD': {
          const b = stack.pop(), a = stack.pop();
          if ((op === 'DIV' || op === 'MOD') && b === 0) fail('division by zero');
          let value;
          if (op === 'ADD') value = a + b;
          else if (op === 'SUB') value = a - b;
          else if (op === 'MUL') value = a * b;
          else if (op === 'DIV') value = Math.trunc(a / b);
          else value = a % b;
          stack.push(checked(value)); break;
        }
        case 'NEG': stack.push(checked(-stack.pop())); break;
        case 'NOT': stack.push(stack.pop() === 0 ? 1 : 0); break;
        case 'JUMP': next = args[0]; break;
        case 'JUMPF': if (stack.pop() === 0) next = args[0]; break;
        case 'JUMPT': if (stack.pop() !== 0) next = args[0]; break;
        case 'CALL': {
          if (frames.length === 100) fail('call depth limit exceeded');
          const locals = stack.splice(stack.length - args[1], args[1]);
          frames.push({ locals, returnAddress: pc + 1 }); next = args[0];
          const from = instruction.unit.name, to = code[args[0]].unit.name, key = from + '\0' + to;
          calls.set(to, (calls.get(to) || 0) + 1);
          if (!pairs.has(key)) pairs.set(key, { from, to, count: 0 });
          pairs.get(key).count++; break;
        }
        case 'ENTER': {
          const locals = frames[frames.length - 1].locals;
          while (locals.length < args[0]) locals.push(0);
          break;
        }
        case 'RET': case 'RETV': next = frames.pop().returnAddress; break;
        case 'READ':
          if (readPosition === input.length) fail('read past end of input');
          stack.push(input[readPosition++]); break;
        case 'PRINT': output.push(stack.splice(stack.length - args[0], args[0]).join(' ')); break;
        case 'HALT': halted = true; break;
      }
    } catch (failure) {
      if (!(failure instanceof RuntimeError)) throw failure;
      error = { message: failure.message, instruction }; break;
    }
    maxStack = Math.max(maxStack, stack.length); maxDepth = Math.max(maxDepth, frames.length);
    if (halted) break;
    pc = next;
  }
  return { output, counts, calls, pairs, executed, maxStack, maxDepth, error, frames };
}

module.exports = { run };
