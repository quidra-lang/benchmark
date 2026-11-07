export interface CacheGeometry {
  size: number;
  ways: number;
  sets: number;
}
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
export interface Config {
  cores: number;
  line: number;
  l1: CacheGeometry;
  l2: CacheGeometry;
  latencies: number[];
  scenarios: Scenario[];
  primary: string;
  interval: number;
  top: number;
  regions: Region[];
  watches: number[];
  capacity: number;
}
export interface TraceEvent {
  number: number;
  cycle: number;
  core: number;
  operation: string;
  address?: number;
  block?: number;
  word?: number;
  distance?: number | null;
}
export interface TraceValidation {
  events: TraceEvent[];
  rejected: {line: number; reason: string}[];
  byCore: TraceEvent[][];
  lineCount: number;
}
export interface ReuseStats {
  accesses: number;
  lines: number;
  histogram: number[];
  cold: number;
  capacities: number[];
  misses: number[];
  opt: number;
}
export interface WordSharing {
  readers: Set<number>;
  writers: Set<number>;
}
export interface SharingLine {
  cores: Set<number>;
  writers: Set<number>;
  words: Map<number, WordSharing>;
  reads: number;
  writes: number;
  shared?: boolean;
  true?: boolean;
}
export interface CoreStats {
  accesses: number;
  reads: number;
  writes: number;
  hits: number;
  misses: number;
  fences: number;
  compulsory: number;
  capacity: number;
  conflict: number;
  coherence: number;
  trueSharing: number;
  falseSharing: number;
  service: Record<string, number>;
  bus: Record<string, number>;
  invalidationsSent: number;
  invalidationsReceived: number;
  supplied: number;
  backInvalidations: number;
  latency: number;
  readLatency: number;
  writeLatency: number;
  fenceStall: number;
  finish: number;
  [key: string]: any;
}
export interface LineStats {
  bus: Record<string, number>;
  cores: Set<number>;
  misses: number;
  coherence: number;
  invalidations: number;
  trueSharing: number;
  falseSharing: number;
  handoffs: number;
  lastWriter: number | null;
  [key: string]: any;
}
export interface CacheLine {
  block: number;
  state: string;
  stamp: number;
}
export interface CacheSet {
  ways: (CacheLine | null)[];
  bits: number[];
  fills: number;
  evictions: number;
}
export interface FoundLine {
  set: number;
  way: number;
  line: CacheLine;
}
export interface BusEviction {
  block: number;
  copies: string[];
  dirty: boolean;
}
export interface BusTransaction {
  number: number;
  start: number;
  core: number;
  type: string;
  block: number;
  snoops: string[];
  supplier: number | null;
  invalidations: number;
  l2: string | null;
  eviction: BusEviction | null;
}
export interface AccessRecord extends TraceEvent {
  issue: number;
  latency: number;
  service: string;
  hit: boolean;
  classification: string | null;
}
