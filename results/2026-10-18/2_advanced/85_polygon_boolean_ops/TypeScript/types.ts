import type { Fraction, Point } from './rational.ts';
import type { GreinerHormann } from './greiner_hormann.ts';

export type Ring = Point[];
export interface Polygon {
  name: string;
  input: Ring[];
  rings: Ring[];
}
export interface Region {
  outer: Ring;
  holes: Ring[];
}
export interface Crossing {
  point: Point;
  nodes: GraphNode[];
}
export interface GraphNode {
  point: Point;
  crossing: Crossing | null;
  side: number;
  entering?: boolean;
  next?: GraphNode;
  prev?: GraphNode;
}
export interface EdgeHit {
  position: Fraction;
  crossing: Crossing;
}
export interface GraphCrossing {
  point: Point;
  t: Fraction;
  u: Fraction;
}
export interface PolygonRegistry {
  used: Set<string>;
  valid: Map<string, Polygon>;
  rejected: string[];
  blocks: number;
  validBlocks: number;
}
export interface ResultTarget {
  result: Region[];
  operands: [Polygon, Polygon] | null;
  graph?: GreinerHormann;
  relation?: string;
  iou?: number;
}
export interface RecordLine {text: string; line: number}
export interface Operation {
  number: number;
  text: string;
  words: string[];
  kind: string;
}
export interface Prepared {
  reason?: string;
  target?: ResultTarget;
  a?: Polygon;
  b?: Polygon;
  name?: string;
  input?: Ring[];
}
export interface RingRecord {
  ring: Ring;
  polygon: number;
  hole: number;
  area: number;
}
export interface PolygonValues {
  polygons: number;
  rings: RingRecord[];
  holes: number;
  vertices: number;
  area: number;
  perimeter: number;
  low: Point | null;
  high: Point | null;
  centroid: [number, number] | null;
  origins: {a: number; b: number; crossing: number};
}
