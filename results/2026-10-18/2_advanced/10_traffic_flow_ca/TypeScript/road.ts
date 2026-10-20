import type { Vehicle } from './vehicles';
import type { Junction } from './signals';

export const OBSTACLE = Symbol('obstacle');
export type Cell = Vehicle | typeof OBSTACLE | null;
export type ChangeKind = 'overtaking' | 'return' | 'avoidance';
export interface Turn { to: Segment; weight: number; vehicles: number }
export interface BusStop { segment: Segment; cell: number; dwell: number; buses: number }

export class Segment {
  readonly cells: Cell[][];
  junction: Junction | null = null;
  turns: Turn[] = [];
  turnWeights: number[] = [];
  stop: BusStop | null = null;
  entered = 0;
  vehicleSum = 0;
  speedSum = 0;
  maximumVehicles = 0;
  changes: Record<ChangeKind, number> = { overtaking: 0, return: 0, avoidance: 0 };
  greenCount = 0;
  passed = 0;
  blocked = 0;
  queueSum = 0;
  maximumQueue = 0;
  failures = 0;

  constructor(readonly id: string, readonly from: string, readonly to: string,
    readonly length: number, readonly lanes: number, readonly limit: number) {
    this.cells = Array.from({ length: lanes }, () => Array<Cell>(length).fill(null));
  }

  get(lane: number, cell: number): Cell { return this.cells[lane - 1][cell]; }

  free(lane: number, cell: number, maximum: number): number {
    const row = this.cells[lane - 1];
    let count = 0;
    while (count < maximum && cell + count + 1 < this.length && row[cell + count + 1] === null) count++;
    return count;
  }

  first(lane: number): number {
    const row = this.cells[lane - 1];
    for (let cell = 0; cell < this.length; cell++) if (row[cell] !== null) return cell;
    return this.length;
  }

  safe(lane: number, cell: number): boolean {
    const row = this.cells[lane - 1];
    for (let x = Math.max(0, cell - this.limit); x <= cell; x++) if (row[x] !== null) return false;
    return true;
  }

  diagram(lane: number): string {
    return this.cells[lane - 1].map(cell => cell === null ? '.' : cell === OBSTACLE ? '#' : String(cell.speed)).join('');
  }
}

export class Incident {
  state: 'planned' | 'active' | 'cleared' | 'cancelled' = 'planned';
  activeStart: number | null = null;
  activeEnd: number | null = null;

  constructor(readonly segment: Segment, readonly lane: number, readonly cell: number,
    readonly start: number, readonly end: number) {}

  update(step: number): 'INCIDENT_START' | 'INCIDENT_END' | null {
    const row = this.segment.cells[this.lane - 1];
    let event: 'INCIDENT_START' | 'INCIDENT_END' | null = null;
    if (this.state === 'active' && step > this.end) {
      this.state = 'cleared';
      row[this.cell] = null;
      event = 'INCIDENT_END';
    } else if (this.state === 'planned' && step > this.end) {
      this.state = 'cancelled';
    } else if (this.state === 'planned' && step >= this.start && row[this.cell] === null) {
      this.state = 'active';
      row[this.cell] = OBSTACLE;
      this.activeStart = step;
      event = 'INCIDENT_START';
    }
    if (this.state === 'active') this.activeEnd = step;
    return event;
  }
}
