import type { Segment, Turn } from './road';
import type { Minstd } from './minstd';

export interface Source {
  node: string;
  rates: { rate: number; end: number }[];
  entry: Segment;
  queue: Vehicle[];
  head: number;
  queueStart: number;
  maximumQueue: number;
}

export class VehicleClass {
  constructor(readonly name: string, readonly maximum: number, readonly weight: number,
    readonly overtake: boolean, readonly stops: boolean) {}
}

export class Vehicle {
  insertion: number | null = null;
  exit: number | null = null;
  sink: string | null = null;
  segment: Segment | null = null;
  lane = 0;
  cell = 0;
  speed = 0;
  turn: Turn | null = null;
  route: string[] = [];
  steps = 0;
  distance = 0;
  stoppedSteps = 0;
  stopCount = 0;
  laneChanges = 0;
  dwell = 0;
  completedStops = new Set<string>();
  trajectory: string[] | null = null;

  constructor(readonly number: number, readonly type: VehicleClass,
    readonly source: Source, readonly arrival: number) {}

  road(): Segment {
    if (this.segment === null) throw new Error('Vehicle is not on a road');
    return this.segment;
  }

  maximumSpeed(): number { return Math.min(this.type.maximum, this.road().limit); }

  headingForStop(): boolean {
    return this.segment !== null && this.type.stops && this.segment.stop !== null
      && !this.completedStops.has(this.segment.id) && this.cell <= this.segment.stop.cell;
  }

  place(segment: Segment, lane: number, cell: number): void {
    if (this.segment !== null) this.segment.cells[this.lane - 1][this.cell] = null;
    this.segment = segment;
    this.lane = lane;
    this.cell = cell;
    segment.cells[lane - 1][cell] = this;
  }

  remove(): void {
    this.road().cells[this.lane - 1][this.cell] = null;
    this.segment = null;
  }
}

export function randomSlowdown(proposed: number, previous: number, p: number, p0: number,
  generator: Minstd): number {
  const random = generator.draw();
  return proposed > 0 && random % 1000 < (previous === 0 ? p0 : p) ? proposed - 1 : proposed;
}
