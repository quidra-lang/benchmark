import { idResolved, ready, type Source, type Timing } from './hazards.ts';
import type { Instruction, Variant } from './trace_io.ts';

export const causes = ['control', 'structural', 'load_use', 'raw'] as const;
export type Cause = (typeof causes)[number];
export interface Stall {
  cause: Cause;
  cycles: number;
  responsible: number;
  waiting?: number;
  producer?: number;
}
export interface Run {
  timings: Timing[];
  stalls: Stall[];
  cycles: number;
}
export function simulate(
  instructions: Instruction[],
  sources: Source[][],
  variant: Variant,
  mispredicted: boolean[],
): Run {
  const timings: Timing[] = [];
  const stalls: Stall[] = [];
  instructions.forEach((instruction, i) => {
    let fetch = 1;
    let decode = 2;
    let execute = 3;
    if (i) {
      const previous = timings[i - 1];
      const ideal = previous.execute + 1;
      fetch = mispredicted[i - 1]
        ? previous.execute + (idResolved(instructions[i - 1], variant) ? 0 : 1)
        : previous.decode;
      decode = Math.max(fetch + 1, previous.execute);
      const bounds: Record<Cause, number> = {
        control: decode + 1,
        structural: previous.memory,
        load_use: ideal,
        raw: ideal,
      };
      const producers: Partial<Record<Cause, number>> = {};
      for (const source of sources[i]) {
        const cycle = ready(source, instruction, variant, instructions, timings);
        if (cycle === undefined || source.producer === undefined) continue;
        const cause = instructions[source.producer].kind === 'LOAD' ? 'load_use' : 'raw';
        if (cycle > bounds[cause]) {
          bounds[cause] = cycle;
          producers[cause] = source.producer;
        }
      }
      execute = ideal;
      for (const cause of causes) {
        if (bounds[cause] > execute) {
          stalls.push({
            cause,
            cycles: bounds[cause] - execute,
            responsible: cause === 'control' || cause === 'structural' ? i - 1 : i,
            waiting: i,
            producer: producers[cause],
          });
          execute = bounds[cause];
        }
      }
    }
    const memory = execute + (instruction.kind === 'MUL' ? variant.latency : 1);
    timings.push({ fetch, decode, execute, memory, writeback: memory + 1 });
  });
  const last = instructions.length - 1;
  if (instructions[last].kind === 'MUL' && variant.latency >= 2) {
    stalls.push({ cause: 'structural', cycles: variant.latency - 1, responsible: last });
  }
  return { timings, stalls, cycles: timings[last].writeback };
}
