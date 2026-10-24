import * as low from './low_level.ts';
import type { Grid } from './grid_map.ts';
import type { Agent, Plan, SearchResult } from './types.ts';

export function planOrder(grid: Grid, agents: Agent[], order: number[], budget: low.Budget, horizon: number,
  record: (agent: number, search: SearchResult) => void):
  {paths: Plan | null; planned: number; failed: number | null; expansions: number} {
  const prohibitions = new low.Prohibitions(grid.size);
  const paths: Plan = Array(agents.length);
  const before = budget.expansions;
  let planned = 0;
  for (const number of order) {
    const result = low.plan(grid, agents[number], prohibitions, budget, horizon);
    record(number, result);
    if (result.path === null) return {paths: null, planned, failed: number, expansions: budget.expansions - before};
    paths[number] = result.path;
    planned++;
    prohibitions.reserve(result.path, 0, true);
  }
  return {paths, planned, failed: null, expansions: budget.expansions - before};
}

