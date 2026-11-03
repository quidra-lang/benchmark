export type Captures = (number | null)[];
export type Engine = 'backtrack' | 'pike';

export interface Instruction {
  op: 'CHAR' | 'ANY' | 'CLASS' | 'SPLIT' | 'JMP' | 'SAVE' | 'ASSERT' | 'BACKREF' | 'LOOK' | 'MATCH';
  character?: number;
  set?: Set<number>;
  negated?: boolean;
  x?: number;
  y?: number;
  group?: number;
  assertion?: string;
  kind?: string;
}

export interface LiteralNode { kind: 'literal'; character: number }
export interface AnyNode { kind: 'any' }
export interface ClassNode { kind: 'class'; set: Set<number>; negated: boolean }
export interface AssertionNode { kind: 'assertion'; assertion: string }
export interface BackReferenceNode {
  kind: 'backreference';
  group?: number;
  name?: string;
  column: number;
}
export interface GroupNode { kind: 'group'; group: number; content: RegexNode }
export interface LookaheadNode { kind: 'lookahead'; positive: boolean; content: RegexNode }
export interface CompositeNode { kind: 'alternation' | 'concatenation'; elements: RegexNode[] }
export interface RepetitionNode {
  kind: 'repetition';
  content: RegexNode;
  minimum: number;
  maximum: number | null;
  mode: 'lazy' | 'greedy' | 'possessive';
}
export type RegexNode =
  | LiteralNode | AnyNode | ClassNode | AssertionNode | BackReferenceNode
  | GroupNode | LookaheadNode | CompositeNode | RepetitionNode;

export interface RegexProperties {
  minimum: number;
  maximum: number | null;
  first: Set<number>;
  nullable: boolean;
}

export interface Pattern {
  name: string;
  flags: string;
  source: string;
  error: {message: string; column: number} | null;
  groups: number;
  names: Map<string, number>;
  program: Instruction[];
  properties: RegexProperties;
  pike: boolean;
}

export interface SearchResult {
  captures: Captures;
  position: number;
}

export interface RegexCommand {
  kind: string;
  mode: string | null;
  template: (string | number)[] | null;
}

export interface EngineResult {
  steps: [Engine, number][];
  matches: Captures[] | null;
  label: string;
  failure: string | null;
}

export type RegexVM = { search(start: number, full: boolean): Captures | null };
