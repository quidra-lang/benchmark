export type Grid = number[][];
export type Coordinate = [number, number];

export interface Locations {
  format: Coordinate[][];
  version: Coordinate[][];
}

export interface Layout {
  size: number;
  grid: Grid;
  areas: string[][];
  order: Coordinate[];
  locations: Locations;
  functionCount: number;
}

export interface BlockTable {
  e: number;
  lengths: number[];
  data: number;
  total: number;
  placement: Coordinate[];
}

export interface VersionTable {
  blocks: Record<string, BlockTable>;
  centers: number[];
  layout?: Layout;
}

export interface QRRequest {
  id: string;
  level: string;
  mode: string;
  version: string;
  mask: string;
  text: string;
}

export interface Segment {
  mode: string;
  text: string;
}

export interface SegmentPlan {
  segments: Segment[];
  bits: number;
}

export interface Damage {
  kind: string;
  args: string[];
}

export interface Scan {
  name: string;
  grid: Grid;
}

export interface Input {
  requests: QRRequest[];
  quiet: number;
  scale: number;
  tables: VersionTable[];
  damage: Map<string, Damage[]>;
  scans: Scan[];
}

export interface Resolved extends SegmentPlan {
  request: QRRequest;
  version: number;
  level: string;
  mode: string;
  split: (mode: string, version: number) => SegmentPlan;
  table: BlockTable;
  layout: Layout;
}

export interface Penalty {
  n1: number;
  n2: number;
  n3: number;
  n4: number;
  total: number;
  dark: number;
}

export interface Encoded extends Resolved {
  blocks: {data: number[]; ec: number[]; words: number[]}[];
  interleaved: number[];
  bitLines: string[];
  penalties: Penalty[];
  mask: number;
  grid: Grid;
  dark: number;
}

export interface Correction {
  status: 'ok' | 'corrected' | 'failed';
  syndromes: number[];
  positions: number[];
  codewords: number[];
}

export interface Decoded {
  success: boolean;
  lines: string[];
  blocks: Correction[];
  text?: string;
}

export interface Summary {
  encoded: number;
  errorCount: number;
  errors: Record<string, number>;
  modes: Record<string, number>;
  levels: Record<string, number>;
  boosted: number;
  versions: number[];
  masks: number[];
  segments: number;
  dataCodewords: number;
  ecCodewords: number;
  modules: number;
  dark: number;
  checks: Record<string, number>;
  blocks: Record<string, number>;
  scans: Record<string, number>;
}
