import { lessEqual, relation } from './clocks.ts';
import { balanceAt, type Process, type SimEvent, type Copy } from './processes.ts';

export function eventGraph(processes: Process[], events: SimEvent[], copies: Copy[]): number[][] {
  const graph: number[][] = events.map(() => []);
  for (const p of processes) {
    for (let i = 1; i < p.events.length; i++) {
      graph[p.events[i - 1].number - 1].push(p.events[i].number - 1);
    }
  }
  for (const copy of copies) {
    if (copy.received !== null) {
      graph[copy.message.event!.number - 1].push(copy.received.number - 1);
    }
  }
  return graph;
}
export function breadthFirst(graph: number[][], start: number, end: number): number[] | null {
  const parents: number[] = Array(graph.length).fill(-1);
  const queue = [start];
  parents[start] = start;
  for (let head = 0; head < queue.length; head++) {
    for (const next of graph[queue[head]]) {
      if (parents[next] !== -1) continue;
      parents[next] = queue[head];
      if (next === end) {
        const path = [end];
        while (path[path.length - 1] !== start) path.push(parents[path[path.length - 1]]);
        return path.reverse();
      }
      queue.push(next);
    }
  }
  return null;
}
export function concurrentPairs(events: SimEvent[], size: number) {
  let ordered = 0;
  let concurrent = 0;
  let sameLamport = 0;
  let inversions = 0;
  const pairs: number[][] = Array.from({ length: size }, () => Array(size).fill(0));
  for (let i = 0; i < events.length; i++) {
    for (let j = i + 1; j < events.length; j++) {
      const a = events[i];
      const b = events[j];
      if (relation(a.V, b.V) === '||') {
        concurrent++;
        if (a.L === b.L) sameLamport++;
        pairs[Math.min(a.process, b.process)][Math.max(a.process, b.process)]++;
      } else ordered++;
      if ((a.time < b.time && a.L > b.L) || (a.time > b.time && a.L < b.L)) inversions++;
    }
  }
  return { ordered, concurrent, sameLamport, inversions, pairs };
}
export function deliveryRelations(processes: Process[]) {
  const races: { process: number; first: Copy; second: Copy }[] = [];
  const violations: typeof races = [];
  let fifo = 0;
  for (const p of processes) {
    for (let i = 0; i < p.deliveries.length; i++) {
      const first = p.deliveries[i];
      const second = p.deliveries[i + 1];
      if (second && relation(first.message.event!.V, second.message.event!.V) === '||') {
        races.push({ process: p.index, first, second });
      }
      for (let j = i + 1; j < p.deliveries.length; j++) {
        const second = p.deliveries[j];
        if (relation(second.message.event!.V, first.message.event!.V) !== '->') continue;
        violations.push({ process: p.index, first, second });
        if (first.source === second.source) fifo++;
      }
    }
  }
  return { races, violations, fifo };
}
function nextCut(cut: number[], bounds: number[]): void {
  for (let i = 0; i < cut.length; i++) {
    if (cut[i] < bounds[i]) {
      cut[i]++;
      return;
    }
    cut[i] = 0;
  }
}
export function countCuts(processes: Process[], time: number, initial: number) {
  const bounds = processes.map((p) => p.events.filter((e) => e.time <= time).length);
  const strides: number[] = [];
  let product = 1;
  let maximumLevel = 0;
  for (const b of bounds) {
    strides.push(product);
    product *= b + 1;
    maximumLevel += b;
  }
  const valid = new Uint8Array(product);
  const amount = new Int32Array(product);
  const levels: number[] = Array(maximumLevel + 1).fill(0);
  const cut: number[] = Array(bounds.length).fill(0);
  let consistent = 0;
  for (let index = 0; index < product; index++) {
    if (cut.every((count, i) => count === 0 || lessEqual(processes[i].events[count - 1].V, cut))) {
      valid[index] = 1;
      consistent++;
      let level = 0;
      let balances = 0;
      for (let i = 0; i < cut.length; i++) {
        level += cut[i];
        balances += balanceAt(processes[i], cut[i]);
      }
      levels[level]++;
      amount[index] = initial - balances;
    }
    nextCut(cut, bounds);
  }
  return { bounds, strides, product, valid, amount, levels, consistent };
}
export function predicate(cuts: ReturnType<typeof countCuts>, threshold: number) {
  const reachable = new Uint8Array(cuts.product);
  const cut: number[] = Array(cuts.bounds.length).fill(0);
  let count = 0;
  for (let index = 0; index < cuts.product; index++) {
    if (cuts.valid[index]) {
      if (cuts.amount[index] >= threshold) count++;
      else if (index === 0 || cut.some((v, i) => v > 0 && reachable[index - cuts.strides[i]])) {
        reachable[index] = 1;
      }
    }
    nextCut(cut, cuts.bounds);
  }
  return { count, possibly: count > 0, definitely: reachable[cuts.product - 1] === 0 };
}
