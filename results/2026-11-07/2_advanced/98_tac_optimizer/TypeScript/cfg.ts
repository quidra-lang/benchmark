import type { TACFunction, CFG, BasicBlock, Instruction, NaturalLoop } from './types.ts';

export const equalSets = <T>(a: Set<T>, b: Set<T>): boolean => a.size === b.size && Array.from(a).every(value => b.has(value));
export function intersection<T>(sets: Set<T>[]): Set<T> {
  if (sets.length === 0) return new Set<T>();
  return new Set<T>(Array.from(sets[0]).filter(value => sets.slice(1).every(set => set.has(value))));
}
export const numeric = (values: Iterable<number>): number[] => Array.from(values).sort((a, b) => a - b);

export function buildCFG(fn: TACFunction): CFG {
  const blocks: BasicBlock[] = [];
  const instructions = new Map<number, Instruction>();
  const owner = new Map<number, number>();
  const labels = new Map<string, number>();
  let pending: string[] = [], start = 0;
  let previous: Instruction | null = null, block: BasicBlock | null = null, number = 0;
  for (let i = 0; i < fn.code.length; i++) {
    const instruction = fn.code[i];
    if (instruction.kind === 'label') {
      if (pending.length === 0) start = i;
      pending.push(instruction.name!); continue;
    }
    instruction.number = ++number; instructions.set(number, instruction);
    if (block === null || pending.length || ['goto', 'if', 'return'].includes(previous!.kind)) {
      block = { number: blocks.length + 1, labels: pending, instructions: [], start: pending.length ? start : i,
        successors: [], predecessors: [], depth: 0 };
      blocks.push(block);
      for (const name of pending) labels.set(name, block.number);
      pending = [];
    }
    block.instructions.push(instruction); owner.set(number, block.number); previous = instruction;
  }
  const byNumber = new Map<number, BasicBlock>(blocks.map(b => [b.number, b]));
  for (const current of blocks) {
    const last = current.instructions[current.instructions.length - 1], next = current.number + 1;
    if (last.kind === 'goto') current.successors = [labels.get(last.target!)!];
    else if (last.kind === 'if') current.successors = Array.from(new Set([next, labels.get(last.target!)!]));
    else if (last.kind !== 'return') current.successors = [next];
    for (const target of current.successors) byNumber.get(target)!.predecessors.push(current.number);
  }
  const reachable = new Set<number>([1]), postorder: number[] = [], stack = [{ number: 1, next: 0 }];
  while (stack.length) {
    const frame = stack[stack.length - 1], successors = byNumber.get(frame.number)!.successors;
    if (frame.next === successors.length) { postorder.push(frame.number); stack.pop(); }
    else {
      const target = successors[frame.next++];
      if (!reachable.has(target)) { reachable.add(target); stack.push({ number: target, next: 0 }); }
    }
  }
  const reversePostorder = postorder.slice().reverse(), dominators = new Map<number, Set<number>>();
  const reachablePredecessors = (n: number): number[] => byNumber.get(n)!.predecessors.filter(p => reachable.has(p));
  for (const n of reachable) dominators.set(n, n === 1 ? new Set([1]) : new Set(reachable));
  let changed;
  do {
    changed = false;
    for (const n of reversePostorder.slice(1)) {
      const next = intersection(reachablePredecessors(n).map(p => dominators.get(p)!)); next.add(n);
      if (!equalSets(next, dominators.get(n)!)) { dominators.set(n, next); changed = true; }
    }
  } while (changed);
  const immediate = new Map<number, number | null>([[1, null]]);
  for (const n of reachable) if (n !== 1) {
    const ancestors = Array.from(dominators.get(n)).filter(p => p !== n);
    ancestors.sort((a, b) => dominators.get(b).size - dominators.get(a).size || a - b);
    immediate.set(n, ancestors[0]);
  }
  const loops: NaturalLoop[] = [];
  for (const header of blocks) if (reachable.has(header.number)) {
    const h = header.number, latches = reachablePredecessors(h).filter(t => dominators.get(t)!.has(h));
    if (latches.length === 0) continue;
    const members = new Set<number>([h, ...latches]), work = latches.filter(t => t !== h);
    while (work.length) {
      const current = work.pop()!;
      for (const p of reachablePredecessors(current)) if (!members.has(p)) { members.add(p); if (p !== h) work.push(p); }
    }
    const exits = new Set<number>(), outside = new Set<number>();
    for (const n of members) {
      const member = byNumber.get(n)!;
      if (member.instructions[member.instructions.length - 1].kind === 'return') exits.add(n);
      for (const successor of member.successors) if (!members.has(successor)) { exits.add(n); outside.add(successor); }
    }
    loops.push({ header: h, latches, blocks: members, exits, outside, depth: 0 });
  }
  for (const loop of loops) loop.depth = loops.filter(other => other.blocks.has(loop.header)).length;
  for (const current of blocks) current.depth = loops.filter(loop => loop.blocks.has(current.number)).length;
  return { blocks, byNumber, instructions, owner, labels, reachable, postorder, reversePostorder,
    dominators, immediate, loops, reachablePredecessors };
}

