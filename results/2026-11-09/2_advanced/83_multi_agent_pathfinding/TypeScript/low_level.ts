import type { Agent, Constraint, Path, SearchResult } from './types.ts';
import type { Grid } from './grid_map.ts';

export interface Budget {limit: number | null; searches: number; expansions: number}
interface SearchState {
  cell: number;
  time: number;
  g: number;
  f: number;
  number: number;
  parent: SearchState | null;
}

export class Heap<T> {
  compare: (a: T, b: T) => number;
  items: T[];
  constructor(compare: (a: T, b: T) => number) {
    this.compare = compare;
    this.items = [];
  }

  get size(): number {
    return this.items.length;
  }

  push(value: T): void {
    let index = this.items.length;
    this.items.push(value);
    while (index > 0) {
      const parent = Math.floor((index - 1) / 2);
      if (this.compare(this.items[parent], value) <= 0) break;
      this.items[index] = this.items[parent];
      index = parent;
    }
    this.items[index] = value;
  }

  pop(): T {
    const first = this.items[0];
    const last = this.items.pop()!;
    if (this.items.length === 0) return first;
    let index = 0;
    while (2 * index + 1 < this.items.length) {
      let child = 2 * index + 1;
      if (child + 1 < this.items.length && this.compare(this.items[child + 1], this.items[child]) < 0) child++;
      if (this.compare(last, this.items[child]) <= 0) break;
      this.items[index] = this.items[child];
      index = child;
    }
    this.items[index] = last;
    return first;
  }
}

export class Prohibitions {
  size: number;
  entries: Constraint[];
  states: Set<number>;
  moves: Set<number>;
  permanent: Map<number, number>;
  latest: Map<number, number>;
  constructor(size: number, entries: Constraint[] = []) {
    this.size = size;
    this.entries = entries;
    this.states = new Set<number>();
    this.moves = new Set<number>();
    this.permanent = new Map<number, number>();
    this.latest = new Map<number, number>();
    for (const entry of entries) {
      if (entry.kind === 'vertex') this.addState(entry.v, entry.time);
      else this.addMove(entry.u, entry.v, entry.time);
    }
  }

  addState(cell: number, time: number): void {
    this.states.add(time * this.size + cell);
    if (!this.latest.has(cell) || this.latest.get(cell)! < time) this.latest.set(cell, time);
  }

  addMove(from: number, to: number, time: number): void {
    this.moves.add((time * this.size + from) * this.size + to);
  }

  permits(from: number, to: number, time: number): boolean {
    return !this.states.has(time * this.size + to) &&
      (!this.permanent.has(to) || this.permanent.get(to)! > time) &&
      (from === to || !this.moves.has((time * this.size + from) * this.size + to));
  }

  arrival(goal: number): number {
    return this.latest.has(goal) ? this.latest.get(goal)! + 1 : 0;
  }

  withConstraint(constraint: Constraint): Prohibitions {
    return new Prohibitions(this.size, this.entries.concat(constraint));
  }

  reserve(path: Path, startTime = 0, permanent = false): void {
    for (let index = 0; index < path.length; index++) {
      this.addState(path[index], startTime + index);
      if (index > 0 && path[index] !== path[index - 1]) {
        this.addMove(path[index], path[index - 1], startTime + index);
      }
    }
    if (permanent) {
      const goal = path.at(-1)!;
      const time = startTime + path.length - 1;
      if (!this.permanent.has(goal) || time < this.permanent.get(goal)!) this.permanent.set(goal, time);
    }
  }
}

export class BudgetExceeded extends Error {}

export function counter(limit: number | null = null): Budget {
  return {limit, searches: 0, expansions: 0};
}

export function search(grid: Grid, agent: Agent, prohibitions: Prohibitions, budget: Budget, start: number, startTime: number, maximum: number, window = false): SearchResult {
  budget.searches++;
  const before = budget.expansions;
  const arrival = prohibitions.arrival(agent.goal);
  const open = new Heap<SearchState>((a, b) => a.f - b.f || b.g - a.g || a.number - b.number);
  const generated = new Set([startTime * grid.size + start]);
  let number = 0;
  open.push({cell: start, time: startTime, g: 0, f: agent.distance[start], number: number++, parent: null});
  while (open.size > 0) {
    const state = open.pop();
    budget.expansions++;
    if (budget.limit !== null && budget.expansions > budget.limit) throw new BudgetExceeded();
    if ((state.cell === agent.goal && state.time >= arrival) || (window && state.time === maximum)) {
      const path: Path = [];
      for (let current: SearchState | null = state; current !== null; current = current.parent) path.push(current.cell);
      path.reverse();
      return {path, expansions: budget.expansions - before};
    }
    if (state.time === maximum) continue;
    const time = state.time + 1;
    const g = time - startTime;
    for (const cell of grid.neighbors[state.cell]) {
      const key = time * grid.size + cell;
      if (agent.distance[cell] < 0 || !prohibitions.permits(state.cell, cell, time) || generated.has(key)) continue;
      generated.add(key);
      open.push({cell, time, g, f: g + agent.distance[cell], number: number++, parent: state});
    }
  }
  return {path: null, expansions: budget.expansions - before};
}

export function plan(grid: Grid, agent: Agent, prohibitions: Prohibitions, budget: Budget, horizon: number): SearchResult {
  return search(grid, agent, prohibitions, budget, agent.start, 0, horizon);
}

