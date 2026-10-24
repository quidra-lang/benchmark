export type Direction = 'UP' | 'DOWN';
export type SignalAspect = 'RED' | 'YELLOW' | 'GREEN';
export type RouteState = 'LOCKED' | 'APPROACH' | 'USED' | null;
export type TrainState = 'WAITING' | 'RUNNING' | 'EXITED';

export interface Section {
  name: string;
  length: number;
  row: number;
  col1: number;
  col2: number;
  ends: Record<string, Connection>;
  signals: Partial<Record<Direction, Signal>>;
  failed: boolean;
  occupants: Train[];
  stats: {occupied: number; locked: number; trains: Set<Train>};
  routeLock: Route | null;
  overlapLocks: Set<Route>;
}

export interface Point {
  name: string;
  side: string;
  common: Section;
  normal: Section;
  reverse: Section;
  row: number;
  col: number;
  position: string;
  moving: boolean;
  target: string | null;
  completion: number | null;
  failed: boolean;
  stats: {throws: number; locked: number; moving: number};
  locks: {route: Route; position: string}[];
}

export interface Signal {
  kind: 'signal';
  name: string;
  section: Section;
  direction: Direction;
  row: number;
  col: number;
  aspect: SignalAspect;
  stats: Record<SignalAspect, number> & {passes: number};
}

export interface BufferEnd {
  kind: 'buffer';
  name: string;
  section: Section;
  end: string;
  row: number;
  col: number;
}

export interface Boundary {
  kind: 'boundary';
  name: string;
  section: Section;
  end: string;
}

export type Feature = Signal | BufferEnd | Boundary;
export type Connection =
  | {kind: 'section'; section: Section}
  | {kind: 'point'; point: Point}
  | BufferEnd
  | Boundary;
export type NextConnection =
  | {kind: 'section'; section: Section}
  | BufferEnd
  | Boundary
  | {kind: 'impassable'};

export interface Layout {
  sections: Section[];
  points: Point[];
  signals: Signal[];
  buffers: BufferEnd[];
  boundaries: Boundary[];
  labels: {row: number; col: number; text: string}[];
  sectionByName: Map<string, Section>;
  pointByName: Map<string, Point>;
  signalByName: Map<string, Signal>;
  boundaryByName: Map<string, Boundary>;
  features: Map<string, Feature>;
}

export interface PointRequirement {point: Point; position: string}
export interface Route {
  name: string;
  start: Signal;
  finish: Feature;
  direction: Direction;
  points: PointRequirement[];
  flank: PointRequirement[];
  requirements: PointRequirement[];
  sections: Section[];
  overlap: Section[];
  conflictNames: string[];
  conflicts: Route[];
  approach: number;
  state: RouteState;
  passed: Set<Section>;
  overlapLocked: boolean;
  overlapCounter: number;
  releaseTime: number | null;
  stats: {requests: number; grants: number; uses: number; cancels: number; wait: number; maxwait: number; locked: number};
}

export interface Stop {
  section: Section;
  turn: boolean;
  dwell: number;
  scheduledArrival: number;
  scheduledDeparture: number;
  arrival: number | null;
  departure: number | null;
}

export interface PathEntry {section: Section; start: number}
export interface OccupiedPart extends PathEntry {lo: number; hi: number}
export interface Train {
  name: string;
  symbol: string;
  length: number;
  acceleration: number;
  deceleration: number;
  maximum: number;
  entry: Boundary;
  scheduledEntry: number;
  entrySpeed: number;
  stops: Stop[];
  exit: Boundary | null;
  scheduledExit: number | null;
  actualEntry: number | null;
  actualExit: number | null;
  state: TrainState;
  direction: Direction | null;
  path: PathEntry[];
  head: number;
  speed: number;
  nextStop: number;
  dwelling: boolean;
  pendingDeparture: Stop | null;
  emergency: boolean;
  crossed: {boundary: Boundary; coordinate: number} | null;
  stats: {distance: number; maxspeed: number; standing: number; passes: number};
}

export interface RouteRequest {train: Train; route: Route}
export interface Event {kind: string; args: string[]}
export interface Params {
  THROW: number;
  OVERLAP: number;
  END: number;
  SNAPSHOTS: Set<number>;
}
export interface QueueRequest {number: number; route: Route; time: number; lastReason: string | null}
export interface Punctuality {onTime: number; late: number; missing: number; totalDelay: number; maxDelay: number}
