import type { Canvas } from './canvas.ts';

export type Direction = 'TB' | 'BT' | 'LR' | 'RL';
export type Heuristic = 'barycenter' | 'median';
export interface Settings {
  layering: 'longest' | 'coffman';
  width: number;
  promotion: 'on' | 'off';
  heuristic: Heuristic;
  sweeps: number;
  node_sep: number;
  dummy_sep: number;
  layer_gap: number;
  direction: Direction;
  sifting: 'on' | 'off';
  reduce: 'on' | 'off';
  restarts: number;
  seed: number;
  [key: string]: string | number;
}
export interface GraphNode {id: number; label: string}
export interface RawEdge {from: number; to: number}
export interface Graph {
  name: string;
  settings: Settings;
  nodes: GraphNode[];
  edges: RawEdge[];
  path: [number, number] | null;
  error: {kind: string; line: number} | null;
  selfLoops: number;
  duplicates: number;
}
export interface GraphAnalysis {
  sources: number; sinks: number; isolated: number; components: number;
  scc: number[][];
}
export interface Edge extends RawEdge {
  number: number;
  reversed: boolean;
  upper: number;
  lower: number;
  transitive: boolean;
  span: number;
  chain: number[];
  segments: GapSegment[];
  crossings: number;
  upperPoint: [number,number];
  lowerPoint: [number,number];
  bends: number;
  route: number[][];
  length: number;
}
export interface Vertex {
  name: string;
  label?: string;
  real: boolean;
  layer: number;
  width: number;
  upper: number[];
  lower: number[];
  left: number;
  right: number;
  x: number;
}
export interface GapSegment {
  upper: number;
  lower: number;
  edge: number;
  gap: number;
  offset: number;
}
export interface LayerHeights {
  height: number[]; labels: number[]; dummyBefore: number;
  promotions: {round:number;vertex:number;difference:number}[];
  rounds: number;
}
export interface ReductionRecord {
  run: number; sweep: number; crossings: number;
  direction?: string; moved?: number; swaps?: number;
}
export interface BestReduction {run:number;sweep:number;crossings:number;order:number[][]}
export interface Reduction {records: ReductionRecord[];best:BestReduction}
export interface SiftRecord {round:number;moves:number;crossings:number}
export interface Crossings {perGap:number[];brute:number;total:number}
export interface CoordinateVariant {
  name:string; coordinates:number[]; low:number; high:number; width:number; blocks:number;
}
export interface Coordinates {
  conflicts:number; variants:CoordinateVariant[]; smallest:string;
}
export interface Bus {
  upper:boolean;vertex:number;low:number;high:number;
  segments:GapSegment[];track:number;
}
export interface Geometry {
  spaces:{tracks:number;length:number}[];
  bands:{start:number;thickness:number}[];
  mainLength:number;secondaryLength:number;vertical:boolean;
}
export interface GraphStatistics {
  drawn:Edge[]; spans:Map<number,number>;spanTotal:number;spanMaximum:number;
  longEdges:number;vertical:number;routeLength:number;bends:number;longest:Edge|null;
  segments:number;straight:number;offset:number;dummies:number;
  maxNodes:number;maxVertices:number;crossingCells:number;
}
export interface GraphResult {
  graph:Graph;edges:Edge[];analysis:GraphAnalysis;sequence:number[];
  heights:LayerHeights;vertices:Vertex[];gaps:GapSegment[][];reduction:Reduction;
  order:number[][];positions:number[];sifting:SiftRecord[];crossings:Crossings;
  bk:Coordinates;geometry:Geometry;canvas:Canvas;path:number[]|null;
  stats:GraphStatistics;
}
