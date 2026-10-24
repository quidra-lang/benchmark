import type { Instance, Job } from './instance.ts';
import type { Minstd } from './minstd.ts';

export interface Schedule {
  starts: number[];
  ends: number[];
  order: number[][];
  makespan: number;
}

export function decode(instance: Instance, chromosome: number[]): Schedule {
  const next = instance.jobs.map(() => 0);
  const ready = instance.jobs.map(() => 0);
  const free = instance.machines.map(() => 0);
  const starts: number[] = [];
  const ends: number[] = [];
  const order: number[][] = instance.machines.map(() => []);
  let makespan = 0;
  for (const number of chromosome) {
    const job = instance.byNumber.get(number)!;
    const operation = instance.operations[job.operations[next[job.index]++]];
    const start = Math.max(ready[job.index], free[operation.machine]);
    const end = start + operation.duration;
    starts[operation.index] = start;
    ends[operation.index] = end;
    order[operation.machine].push(operation.index);
    ready[job.index] = end;
    free[operation.machine] = end;
    makespan = Math.max(makespan, end);
  }
  return { starts, ends, order, makespan };
}

export function tournament(evaluations: number[], size: number, rng: Minstd): number {
  let best = -1;
  for (let i = 0; i < size; i++) {
    const candidate = rng.below(evaluations.length);
    if (
      best < 0 ||
      evaluations[candidate] < evaluations[best] ||
      (evaluations[candidate] === evaluations[best] && candidate < best)
    ) {
      best = candidate;
    }
  }
  return best;
}

export function crossover(
  first: number[],
  second: number[],
  jobs: Job[],
  rng: Minstd,
): [number[], number[]] {
  const selected = new Set<number>();
  for (const job of jobs) if (rng.below(2) === 0) selected.add(job.number);
  function child(fixed: number[], filling: number[]): number[] {
    const remaining = filling.filter((gene) => !selected.has(gene));
    let position = 0;
    return fixed.map((gene) => (selected.has(gene) ? gene : remaining[position++]));
  }
  return [child(first, second), child(second, first)];
}

export function swapMutation(chromosome: number[], rng: Minstd): void {
  const a = rng.below(chromosome.length);
  const b = rng.below(chromosome.length);
  [chromosome[a], chromosome[b]] = [chromosome[b], chromosome[a]];
}

export function insertionMutation(chromosome: number[], rng: Minstd): void {
  const a = rng.below(chromosome.length);
  const b = rng.below(chromosome.length);
  const [gene] = chromosome.splice(a, 1);
  chromosome.splice(b, 0, gene);
}
