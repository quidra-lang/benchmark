export type BusType = 'BusRd' | 'BusRdX' | 'BusUpgr' | 'BusWr' | 'WB';
export type AccessOperation = 'R' | 'W';
export interface Geometry { size: number; ways: number; sets: number }
export interface Scenario {
  name: string;
  protocol: string;
  l1Policy: string;
  l2Policy: string;
  order: number;
}
export interface Region {
  name: string;
  first: number;
  last: number;
}
export interface RegionReport {
  name: string;
  first?: number;
  last?: number;
  accesses: number;
  reads: number;
  writes: number;
  hits: number;
  compulsory: number;
  capacity: number;
  conflict: number;
  coherence: number;
  transactions: number;
  latency: number;
}
export interface Config {
  cores: number;
  line: number;
  l1: Geometry;
  l2: Geometry;
  latencies: number[];
  scenarios: Scenario[];
  primary: string;
  interval: number;
  top: number;
  regions: Region[];
  watches: number[];
  capacity: number;
}
export interface BaseEvent { number: number; cycle: number; core: number }
export interface FenceEvent extends BaseEvent { operation: 'FENCE' }
export interface AccessEvent extends BaseEvent {
  operation: AccessOperation;
  address: number;
  block: number;
  word: number;
  distance: number | null;
}
export type TraceEvent = FenceEvent | AccessEvent;
export interface ValidatedTrace {
  events: TraceEvent[];
  rejected: {line: number; reason: string}[];
  byCore: TraceEvent[][];
  lineCount: number;
}
export interface CacheLine { block: number; state: string; stamp: number }
export interface CacheSet {
  ways: (CacheLine | null)[];
  bits: number[];
  fills: number;
  evictions: number;
}
export interface CacheHit { set: number; way: number; line: CacheLine }
export interface Eviction { block: number; copies: string[]; dirty: boolean }
export interface Transaction {
  number: number;
  start: number;
  core: number;
  type: BusType;
  block: number;
  snoops: string[];
  supplier: number | null;
  invalidations: number;
  l2: string | null;
  eviction: Eviction | null;
}
export interface Counters {
  accesses: number; reads: number; writes: number; hits: number; misses: number; fences: number;
  compulsory: number; capacity: number; conflict: number; coherence: number;
  trueSharing: number; falseSharing: number;
  service: Record<string, number>;
  bus: Record<string, number>;
  invalidationsSent: number; invalidationsReceived: number; supplied: number;
  backInvalidations: number; latency: number; readLatency: number; writeLatency: number;
  fenceStall: number; finish: number;
}
export interface ReuseResult {
  accesses: number; lines: number; histogram: number[]; cold: number;
  capacities: number[]; misses: number[]; opt: number;
}
export interface StaticLine {
  cores: Set<number>;
  writers: Set<number>;
  words: Map<number, {readers: Set<number>; writers: Set<number>}>;
  reads: number;
  writes: number;
  shared: boolean;
  true: boolean;
}
export interface LineData {
  bus: Record<string, number>;
  cores: Set<number>;
  misses: number; coherence: number; invalidations: number; trueSharing: number;
  falseSharing: number; handoffs: number; lastWriter: number | null;
}
export interface WordData { writer: number | null; readers: Set<number> }
export type MissClass = 'compulsory' | 'capacity' | 'conflict' | 'coherence';
export interface AccessRecord extends AccessEvent {
  issue: number; latency: number; service: string; hit: boolean; classification: MissClass | null;
}
