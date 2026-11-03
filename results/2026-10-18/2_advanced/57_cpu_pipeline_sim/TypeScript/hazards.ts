import type { Instruction, Variant } from './trace_io.ts';

export interface Source {
  register: number;
  position: 'rs1' | 'rs2';
  producer?: number;
}
export interface Timing {
  fetch: number;
  decode: number;
  execute: number;
  memory: number;
  writeback: number;
}
export const control = (instruction: Instruction) =>
  instruction.kind === 'BRANCH' || instruction.kind === 'JUMP';
export const idResolved = (instruction: Instruction, variant: Variant) =>
  control(instruction) &&
  (variant.stage === 'ID' || (instruction.kind === 'JUMP' && instruction.rs1 === undefined));
export function dependencies(instructions: Instruction[]): Source[][] {
  const latest = new Map<number, number>();
  return instructions.map((instruction, i) => {
    const sources: Source[] = [];
    for (const position of ['rs1', 'rs2'] as const) {
      const register = instruction[position];
      if (register !== undefined && register !== 0) {
        sources.push({ register, position, producer: latest.get(register) });
      }
    }
    if (instruction.rd !== undefined && instruction.rd !== 0) latest.set(instruction.rd, i);
    return sources;
  });
}
export function ready(
  source: Source,
  instruction: Instruction,
  variant: Variant,
  instructions: Instruction[],
  timings: Timing[],
): number | undefined {
  const p = source.producer;
  if (p === undefined) return undefined;
  return variant.forwarding
    ? (instructions[p].kind === 'LOAD' ? timings[p].writeback : timings[p].memory) +
        (idResolved(instruction, variant) ? 1 : 0)
    : timings[p].writeback + 1;
}
export function forwardingPath(
  source: Source,
  instruction: Instruction,
  timing: Timing,
  variant: Variant,
  timings: Timing[],
): 'regfile' | 'ex_mem' | 'mem_wb' {
  if (!variant.forwarding || source.producer === undefined) return 'regfile';
  const resolved = idResolved(instruction, variant);
  const used = timing.execute - (resolved ? 1 : 0);
  const producer = timings[source.producer];
  if (producer.memory === used) return 'ex_mem';
  if (!resolved && producer.writeback === used) return 'mem_wb';
  return 'regfile';
}
