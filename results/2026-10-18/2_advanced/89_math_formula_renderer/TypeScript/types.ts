export interface FormulaToken {
  kind: string;
  value: string;
  column: number;
}

export type FormulaNode =
  | {kind: 'atom'; atom: string; value: string; column: number}
  | {kind: 'row'; elements: FormulaNode[]}
  | {kind: 'script'; base: FormulaNode; sub: FormulaNode | null; sup: FormulaNode | null}
  | {kind: 'frac' | 'binom'; first: FormulaNode; second: FormulaNode}
  | {kind: 'overset' | 'underset'; placed: FormulaNode; base: FormulaNode}
  | {kind: 'sqrt'; body: FormulaNode}
  | {kind: 'root'; index: FormulaNode; body: FormulaNode}
  | {kind: 'delim'; left: string; right: string; body: FormulaNode; rightColumn: number}
  | {kind: 'matrix'; environment: string; rows: FormulaNode[][]}
  | {kind: 'accent'; name: string; body: FormulaNode};

export interface ParsedFormula {
  elements: FormulaNode[];
  tag: FormulaToken | null;
  label: FormulaToken | null;
}
export interface Formula extends ParsedFormula {
  number: number;
  source: string;
  warnings: {column: number; message: string}[];
  tokens: FormulaToken[];
  tagString: string | null;
  error: {column: number; message: string} | null;
}

export interface Params {
  width: number;
  indent: number;
  bin_space: number;
  rel_space: number;
  punct_space: number;
  col_gap: number;
  row_gap: number;
}

export interface Placement {
  box: import('./boxes.ts').Box;
  x: number;
  y: number;
  role?: string;
}
export interface Positioned extends Placement {
  level: number;
  role: string;
}
export interface Glyph {width: number; lines: string[]}
export interface BrokenLine {start: number; end: number; indent: number; width: number}
export interface LaidOutFormula {
  lineCount: number;
  width: number;
  height: number;
  placements: Positioned[];
  depth: number;
  overfull: {number: number; width: number}[];
  rendered: string[];
}
