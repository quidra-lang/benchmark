import type { Instance, Operation } from './instance.ts';
import type { Schedule } from './genetic.ts';

export type Rule = 'SPT' | 'LPT' | 'MWKR' | 'FIFO' | 'GENES';
export interface Dispatched extends Schedule {
  decisions: number;
  ties: number;
}

export function dispatch(instance: Instance, rule: Rule, genePositions: number[] = []): Dispatched {
  const next = instance.jobs.map(() => 0);
  const ready = instance.jobs.map(() => 0);
  const free = instance.machines.map(() => 0);
  const order: number[][] = instance.machines.map(() => []);
  const starts: number[] = [];
  const ends: number[] = [];
  let decisions = 0;
  let ties = 0;
  for (let step = 0; step < instance.operations.length; step++) {
    const available: { operation: Operation; start: number; end: number; priority: number }[] = [];
    let earliest = Infinity;
    let machine = Infinity;
    for (const job of instance.jobs) {
      if (next[job.index] === job.operations.length) continue;
      const operation = instance.operations[job.operations[next[job.index]]];
      const start = Math.max(ready[job.index], free[operation.machine]);
      const end = start + operation.duration;
      const priority =
        rule === 'SPT'
          ? operation.duration
          : rule === 'LPT'
            ? -operation.duration
            : rule === 'MWKR'
              ? -(operation.duration + operation.tail)
              : rule === 'FIFO'
                ? ready[job.index]
                : genePositions[operation.index];
      available.push({ operation, start, end, priority });
      if (end < earliest || (end === earliest && operation.machine < machine)) {
        earliest = end;
        machine = operation.machine;
      }
    }
    const conflict = available.filter(
      (item) => item.operation.machine === machine && item.start < earliest,
    );
    let chosen = conflict[0];
    for (const item of conflict) if (item.priority < chosen.priority) chosen = item;
    if (conflict.length >= 2) decisions++;
    if (conflict.filter((item) => item.priority === chosen.priority).length >= 2) ties++;
    const operation = chosen.operation;
    starts[operation.index] = chosen.start;
    ends[operation.index] = chosen.end;
    order[machine].push(operation.index);
    ready[operation.jobIndex] = chosen.end;
    free[machine] = chosen.end;
    next[operation.jobIndex]++;
  }
  return { starts, ends, order, makespan: Math.max(...ends), decisions, ties };
}
