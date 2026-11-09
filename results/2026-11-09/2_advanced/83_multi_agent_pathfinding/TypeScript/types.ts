import type { Grid } from './grid_map.ts';
import type { Prohibitions, Budget } from './low_level.ts';

export type Path = number[];
export type Plan = Path[];
export type CostFunction = 'SOC' | 'MAKESPAN';
export type Solver = 'PP' | 'CBS' | 'ICBS' | 'WHCA';

export interface Agent {
  number: number;
  name: string;
  start: number;
  goal: number;
  distance: number[];
  shortest: number;
}

export type ConstraintKind = 'vertex' | 'edge';
export interface Constraint {
  agent: number;
  kind: ConstraintKind;
  time: number;
  u: number;
  v: number;
}

export interface Conflict {
  kind: ConstraintKind;
  time: number;
  a: number;
  b: number;
  u: number;
  v: number;
  class?: ConflictClass;
}

export type ConflictClass = 'cardinal' | 'semi_cardinal' | 'non_cardinal';

export interface RunConfig {
  solver: Solver;
  costFunction: CostFunction;
  name: string;
  order: number;
}
export interface Delay {agent: number; start: number; length: number}
export interface Parameters {
  orders: number[][];
  runs: RunConfig[];
  delays: Delay[];
  horizon: number;
  highBudget: number;
  lowBudget: number;
  window: number;
  step: number;
  animation: {name: string; frames: number};
}

export interface MDD {
  layers: Set<number>[];
  states: number;
  width: number;
}

export interface Instance {
  grid: Grid;
  agents: Agent[];
  parameters: Parameters;
  mddCache: WeakMap<Prohibitions, Map<number, MDD>>[];
}

export interface BudgetReport {
  limit: number | null;
  searches: number;
  expansions: number;
}

export interface SearchResult {
  path: Path | null;
  expansions: number;
}

export interface Overview {
  free: number;
  degrees: number[];
  components: number;
  diagrams: MDD[];
  paths: Plan;
  conflicts: Conflict[];
  classCounts: Record<ConflictClass, number>;
  bounds: {soc: number; makespan: number};
  groups: string[];
}

export interface PathDetail {
  cost: number;
  extra: number;
  waits: number;
  turns: number;
  arrival: number;
  leave: number;
  actions: string;
}

export interface PlanStatistics {
  soc: number;
  makespan: number;
  cost: number;
  details: PathDetail[];
  sumExtra: number;
  maxExtra: number;
  waits: number;
  turns: number;
  arrivals: number[];
  traffic: number[];
  cellWaits: number[];
  hotspots: number[];
}

export interface Execution {
  deadlock: boolean;
  time?: number;
  soc?: number;
  makespan?: number;
  held?: number;
  finish?: number[];
}

export interface Run extends RunConfig {
  budget: Budget;
  highLevel: number;
  generated: number | null;
  paths: Plan | null;
  reason: string | null;
  trace: string[];
  specific: string[];
  statistics?: PlanStatistics;
  execution?: Execution;
}
