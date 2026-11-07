import type { Plan, Path, Conflict, Constraint, CostFunction } from './types.ts';
import type { Prohibitions } from './low_level.ts';

export function position(path: Path, time: number): number {
  return path[Math.min(time, path.length - 1)];
}

export function costs(paths: Plan): {soc: number; makespan: number} {
  let soc = 0;
  let makespan = 0;
  for (const path of paths) {
    soc += path.length - 1;
    makespan = Math.max(makespan, path.length - 1);
  }
  return {soc, makespan};
}

export function conflicts(paths: Plan): Conflict[] {
  const result: Conflict[] = [];
  const maximum = costs(paths).makespan;
  for (let time = 1; time <= maximum; time++) {
    for (let a = 0; a < paths.length; a++) {
      const from = position(paths[a], time - 1);
      const to = position(paths[a], time);
      for (let b = a + 1; b < paths.length; b++) {
        if (to === position(paths[b], time)) result.push({kind: 'vertex', time, a, b, u: to, v: to});
        else if (to === position(paths[b], time - 1) && from === position(paths[b], time)) {
          result.push({kind: 'edge', time, a, b, u: from, v: to});
        }
      }
    }
  }
  return result;
}

export function constraints(conflict: Conflict): Constraint[] {
  const {kind, time, a, b, u, v} = conflict;
  return [{agent: a, kind, time, u, v},
    {agent: b, kind, time, u: kind === 'vertex' ? u : v, v: kind === 'vertex' ? v : u}];
}

export class Node {
  paths: Plan;
  prohibitions: Prohibitions[];
  number: number;
  parent: Node | null;
  depth: number;
  cost: number;
  conflicts: Conflict[];
  constructor(paths: Plan, prohibitions: Prohibitions[], costFunction: CostFunction, number: number, parent: Node | null = null) {
    this.paths = paths;
    this.prohibitions = prohibitions;
    this.number = number;
    this.parent = parent;
    this.depth = parent === null ? 0 : parent.depth + 1;
    const total = costs(paths);
    this.cost = costFunction === 'SOC' ? total.soc : total.makespan;
    this.conflicts = conflicts(paths);
  }
}

export function compareNodes(a: Node, b: Node): number {
  return a.cost - b.cost || a.conflicts.length - b.conflicts.length || a.number - b.number;
}

