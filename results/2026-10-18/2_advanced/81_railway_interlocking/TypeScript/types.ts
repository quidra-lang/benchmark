export interface Section {
  name: string;
  length: number;
  row: number;
  col1: number;
  col2: number;
  ends: Record<string, any>;
  signals: Record<string, Signal>;
  failed: boolean;
  occupants: Train[];
  routeLock: Route | null;
  overlapLocks: Set<Route>;
  stats: {occupied: number; locked: number; trains: Set<Train>};
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
  locks: {route: Route; position: string}[];
  stats: {throws: number; locked: number; moving: number};
}

export interface Signal {
  kind: string;
  name: string;
  section: Section;
  direction: string;
  row: number;
  col: number;
  aspect: string;
  stats: Record<string, number>;
}

export interface Feature {
  kind: string;
  name: string;
  section: Section;
  end: string;
  row: number;
  col: number;
}

export interface Route {
  name: string;
  start: Signal;
  finish: Feature | Signal;
  direction: string;
  points: PointRequirement[];
  flank: PointRequirement[];
  sections: Section[];
  overlap: Section[];
  conflictNames: string[];
  approach: number;
  state: string | null;
  passed: Set<Section>;
  overlapLocked: boolean;
  overlapCounter: number;
  releaseTime: number | null;
  conflicts: Route[];
  requirements: PointRequirement[];
  stats: {requests: number; grants: number; uses: number; cancels: number; wait: number; maxwait: number; locked: number};
}

export interface PointRequirement {
  point: Point;
  position: string;
}

export interface PathPart {
  section: Section;
  start: number;
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

export interface Train {
  name: string;
  symbol: string;
  length: number;
  acceleration: number;
  deceleration: number;
  maximum: number;
  entry: Feature;
  scheduledEntry: number;
  entrySpeed: number;
  stops: Stop[];
  exit: Feature | null;
  scheduledExit: number | null;
  actualEntry: number | null;
  actualExit: number | null;
  state: string;
  direction: string | null;
  path: PathPart[];
  head: number;
  speed: number;
  nextStop: number;
  dwelling: boolean;
  pendingDeparture: Stop | null;
  emergency: boolean;
  crossed: {boundary: any; coordinate: number} | null;
  stats: {distance: number; maxspeed: number; standing: number; passes: number};
}

export interface Layout {
  sections: Section[];
  points: Point[];
  signals: Signal[];
  buffers: Feature[];
  boundaries: Feature[];
  labels: {row: number; col: number; text: string}[];
  sectionByName: Map<string, Section>;
  pointByName: Map<string, Point>;
  signalByName: Map<string, Signal>;
  boundaryByName: Map<string, Feature>;
  features: Map<string, Feature | Signal>;
}

export interface Request {
  number: number;
  route: Route;
  time: number;
  lastReason: string | null;
}

export interface Params {
  END: number;
  THROW: number;
  OVERLAP: number;
  SNAPSHOTS: Set<number>;
  [key: string]: number | Set<number>;
}

export interface UserEvent {
  kind: string;
  args: string[];
}

export interface ScheduleRequest {
  train: Train;
  route: Route;
}

export interface Punctuality {
  onTime: number;
  late: number;
  missing: number;
  totalDelay: number;
  maxDelay: number;
}
