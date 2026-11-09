import type { Rational } from './rational.ts';
import type { Tableau } from './tableau.ts';

export interface ErrorDetail {line: number; message: string}
export interface Term {name: string; coefficient: Rational}
export interface RawObjective {name: string; terms: Term[]; line: number}
export interface RawConstraint extends RawObjective {op: string; rhs: Rational}
export type RawBound =
  | {name: string; kind: 'both'; lower: Rational | null; upper: Rational | null; line: number}
  | {name: string; kind: 'lower' | 'upper'; value: Rational | null; line: number};
export interface Declaration {names: string[]; line: number}
export type Direction = 'maximize' | 'minimize';
export interface RawModel {
  name: string;
  direction: Direction;
  objective: RawObjective | null;
  constraints: RawConstraint[];
  bounds: RawBound[];
  integers: Declaration[];
  binaries: Declaration[];
  error: ErrorDetail | null;
}
export interface ParseSettings {
  logs: Map<string, number>;
  limits: Map<string, number>;
  log_level: number;
  node_limit: number;
}
export interface ModelConstraint extends RawConstraint {coefficients: Rational[]}
export interface Model {
  name: string;
  direction: Direction;
  variables: string[];
  error: ErrorDetail | null;
  c: Rational[];
  constraints: ModelConstraint[];
  lower: (Rational | null)[];
  upper: (Rational | null)[];
  integers: number[];
}
export interface Column {
  name: string;
  variable: number | null;
  direction: number;
  artificial: boolean;
}
export interface Mapping {
  kind: 'shift' | 'reflect' | 'split';
  offset: Rational;
  upperRow: number | null;
  columns: number[];
}
export interface StandardRow {
  name: string;
  op: string;
  values: Rational[];
  rhs: Rational;
  sigma: number;
  slack: number | null;
  artificial: number | null;
  initial: number;
}
export interface StandardForm {
  model: Model;
  lower: (Rational | null)[];
  upper: (Rational | null)[];
  columns: Column[];
  maps: Mapping[];
  rows: StandardRow[];
  phase1: Rational[];
  phase2: Rational[];
  sign: number;
  constant: Rational;
  artificialCount: number;
}
export type LpStatus = 'OPTIMAL' | 'INFEASIBLE' | 'UNBOUNDED';
export interface LpResult {
  form: StandardForm;
  tableau: Tableau;
  lines: string[];
  phase1: number;
  phase2: number;
  drives: number;
  redundant: number;
  objective: Rational | null;
  solution: Rational[] | null;
  w: Rational;
  status: LpStatus;
  pivots: number;
  farkas?: Rational[];
  ray?: Rational[];
  rate?: Rational;
}
export interface PivotPhase {
  status: 'optimal' | 'unbounded';
  iterations: number;
  lines: string[];
  entering: number | null;
}
export interface Node {
  lower: (Rational | null)[];
  upper: (Rational | null)[];
  depth: number;
  parent: number | null;
  branch: string;
  parentValue: Rational | null;
}
export type SolveStatus = LpStatus | 'NODE_LIMIT' | 'ERROR';
export interface BnbResult {
  status: SolveStatus;
  root: LpResult | null;
  objective: Rational | null;
  solution: Rational[] | null;
  processed: number;
  lines: string[];
}
export interface Counts {solves: number; phase1: number; phase2: number; drives: number}
export interface ModelResult {
  model: Model;
  status: SolveStatus;
  root: LpResult | null;
  objective: Rational | null;
  solution: Rational[] | null;
  lines: string[];
  tree: string[];
  counts: Counts;
  pivots: number;
}
export type Range = [Rational | null, Rational | null];
export interface Sensitivity {
  dual: Rational[];
  variableReduced: Rational[];
  coefficientRanges: Range[];
  rhsRanges: Range[];
  primalDegeneracy: number;
  dualDegeneracy: number;
  dualObjective: Rational;
  statuses: string[];
}
