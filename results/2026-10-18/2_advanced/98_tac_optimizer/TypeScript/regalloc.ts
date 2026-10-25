import { definition, uses, variable } from './tac_parser.ts';
import { liveTransfer } from './dataflow.ts';
import type { TACFunction, Analysis, RegisterAllocation } from './types.ts';
export const ascii = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;

export function allocate(fn: TACFunction, analysis: Analysis, registers: number): RegisterAllocation {
  const nodeSet = new Set<string>(fn.parameters);
  for (const block of analysis.blocks) if (analysis.reachable.has(block.number)) {
    for (const instruction of block.instructions) {
      if (definition(instruction) !== undefined) nodeSet.add(definition(instruction)!);
      for (const name of uses(instruction)) nodeSet.add(name);
    }
  }
  const nodes = Array.from(nodeSet).sort(ascii);
  const neighbors = new Map<string,Set<string>>(nodes.map(name => [name, new Set<string>()]));
  const partners = new Map<string,Set<string>>(nodes.map(name => [name, new Set<string>()]));
  const costs = new Map<string,bigint>(nodes.map(name => [name, 0n]));
  const edge = (a: string, b: string): void => {
    if (a !== b) { neighbors.get(a)!.add(b); neighbors.get(b)!.add(a); }
  };
  for (const block of analysis.blocks) if (analysis.reachable.has(block.number)) {
    let live = analysis.live.outgoing.get(block.number)!;
    const weight = 10n ** BigInt(block.depth);
    for (let i = block.instructions.length - 1; i >= 0; i--) {
      const instruction = block.instructions[i], defined = definition(instruction);
      if (defined !== undefined) {
        for (const name of live) if (!(instruction.kind === 'copy' && variable(instruction.a) && name === instruction.a)) edge(defined, name);
        costs.set(defined, costs.get(defined)! + weight);
      }
      for (const name of uses(instruction)) costs.set(name, costs.get(name)! + weight);
      live = liveTransfer(instruction, live);
    }
  }
  const entry = new Set<string>([...analysis.live.incoming.get(1)!, ...fn.parameters]);
  for (const parameter of fn.parameters) {
    for (const name of entry) edge(parameter, name);
    costs.set(parameter, costs.get(parameter)! + 1n);
  }
  for (const instruction of fn.code) if (instruction.kind === 'copy' && variable(instruction.a) && instruction.a !== instruction.dest) {
    if (partners.has(instruction.dest)) partners.get(instruction.dest)!.add(instruction.a);
    if (partners.has(instruction.a)) partners.get(instruction.a)!.add(instruction.dest!);
  }
  const remaining = new Set<string>(nodes), order: string[] = [], potential: RegisterAllocation['potential'] = [];
  while (remaining.size) {
    const degree = new Map<string,number>(Array.from(remaining, name => [name, Array.from(neighbors.get(name)!).filter(other => remaining.has(other)).length]));
    const small = Array.from(remaining).filter(name => degree.get(name)! < registers);
    let selected;
    if (small.length) {
      small.sort((a, b) => degree.get(a)! - degree.get(b)! || ascii(a, b)); selected = small[0];
    } else {
      const candidates = Array.from(remaining);
      candidates.sort((a, b) => {
        const left = costs.get(a)! * BigInt(degree.get(b)!), right = costs.get(b)! * BigInt(degree.get(a)!);
        return left < right ? -1 : left > right ? 1 : ascii(a, b);
      });
      selected = candidates[0]; potential.push({ name: selected, cost: costs.get(selected)!, degree: degree.get(selected)! });
    }
    order.push(selected); remaining.delete(selected);
  }
  const colors = new Map<string,number|null>();
  for (let i = order.length - 1; i >= 0; i--) {
    const name = order[i], occupied = new Set<number|null|undefined>(Array.from(neighbors.get(name)!, other => colors.get(other)));
    const free = Array.from({ length: registers }, (_, n) => n).filter(n => !occupied.has(n));
    if (free.length === 0) { colors.set(name, null); continue; }
    const preferred = Array.from(partners.get(name)!, other => colors.get(other)).filter((color): color is number => color !== null && color !== undefined && free.includes(color)).sort((a, b) => a - b);
    colors.set(name, preferred.length ? preferred[0] : free[0]);
  }
  return { nodes, neighbors, costs, partners, order, potential, colors,
    edges: nodes.reduce((sum, name) => sum + neighbors.get(name)!.size, 0) / 2 };
}

