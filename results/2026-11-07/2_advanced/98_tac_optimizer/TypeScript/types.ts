export type Operand = number | string;
export type OperandSlot = 'a' | 'b';
export type InstructionKind =
  'label' | 'copy' | 'bin' | 'load' | 'store' | 'goto' | 'if' |
  'param' | 'call' | 'return' | 'read' | 'print';

export interface Instruction {
  kind: InstructionKind;
  number?: number;
  name?: string;
  dest?: string;
  a?: Operand;
  b?: Operand;
  op?: string;
  array?: string;
  target?: string;
  count?: number;
}
export interface Expression {
  kind: 'bin' | 'load';
  a: Operand;
  b?: Operand;
  op?: string;
  array?: string;
}
export interface TACFunction {
  name: string;
  parameters: string[];
  code: Instruction[];
  temporary: number;
  preheader: number;
}
export interface TACProgram {
  arrays: {name: string; size: number}[];
  functions: TACFunction[];
}
export interface BasicBlock {
  number: number;
  labels: string[];
  instructions: Instruction[];
  start: number;
  successors: number[];
  predecessors: number[];
  depth: number;
}
export interface NaturalLoop {
  header: number;
  latches: number[];
  blocks: Set<number>;
  exits: Set<number>;
  outside: Set<number>;
  depth: number;
}
export interface CFG {
  blocks: BasicBlock[];
  byNumber: Map<number, BasicBlock>;
  instructions: Map<number, Instruction>;
  owner: Map<number, number>;
  labels: Map<string, number>;
  reachable: Set<number>;
  postorder: number[];
  reversePostorder: number[];
  dominators: Map<number, Set<number>>;
  immediate: Map<number, number | null>;
  loops: NaturalLoop[];
  reachablePredecessors: (n: number) => number[];
}
export interface Flow {
  incoming: Map<number, Set<string>>;
  outgoing: Map<number, Set<string>>;
  before: Map<number, Set<string>>;
  after: Map<number, Set<string>>;
  iterations: number;
}
export interface Definition {name: string; number: number}
export interface Analysis extends CFG {
  rd: Flow;
  live: Flow;
  available: Flow;
  copies: Flow;
  definitions: Map<string, Definition>;
  expressions: Map<string, Expression>;
  copyPairs: Map<string, [string, string]>;
}
export interface CommonExpressionGroup {
  key: string;
  candidates: Instruction[];
  sources: Instruction[];
}
export interface ExtractedGroup extends CommonExpressionGroup {temporary: string}
export interface OptimizationRecord {count: number; records: string[]}
export interface RemovedCode {blocks: number[]; jumps: number[]; labels: string[]}
export interface RegisterAllocation {
  nodes: string[];
  neighbors: Map<string, Set<string>>;
  costs: Map<string, bigint>;
  partners: Map<string, Set<string>>;
  order: string[];
  potential: {name: string; cost: bigint; degree: number}[];
  colors: Map<string, number | null>;
  edges: number;
}
export interface Settings {registers: number; passes: Set<string>; rounds: number}
export interface CallGraph {
  edges: Map<string, string[]>;
  reachable: Set<string>;
  recursive: Set<string>;
  unreachable: string[];
}
export interface ExecutionResult {
  output: number[];
  calls: Map<string, number>;
  steps: Map<string, number>;
  kinds: Record<string, number>;
  totalSteps: number;
  totalCalls: number;
}
export interface FunctionRuntime extends TACFunction {
  instructions: Instruction[];
  labels: Map<string, number>;
}
export interface Frame {
  fn: FunctionRuntime;
  values: Map<string, number>;
  pc: number;
  arguments: number[];
  destination: string | undefined;
}
