import { readFileSync } from 'node:fs';
import type { Fraction } from './report.ts';

export interface PlaceReplay {
  missing: number;
  remaining: number;
  deviating: number;
  waitingCount: number;
  waitingTotal: number;
  waitingMaximum: number;
  consumptions: Map<string, number>;
}
export interface ReplayRecord {
  missing: number;
  remaining: number;
  consumed: number;
  produced: number;
  skipped: number;
  fitting: number;
  places: PlaceReplay[];
}
export class PetriNet {
  places: string[];
  transitions: string[];
  arcs: [string, string][];
  placeIndex: Map<string, number>;
  initial: number;
  final: number;
  inputs: Map<string, number[]>;
  outputs: Map<string, number[]>;
  constructor(
    places: string[],
    transitions: string[],
    arcs: [string, string][],
    initial: string,
    final: string,
  ) {
    this.places = places.slice();
    this.transitions = transitions.toSorted();
    this.arcs = arcs.map(([a, b]) => [a, b]);
    this.placeIndex = new Map(places.map((p, i) => [p, i]));
    this.initial = this.placeIndex.get(initial)!;
    this.final = this.placeIndex.get(final)!;
    this.inputs = new Map(this.transitions.map((t) => [t, []]));
    this.outputs = new Map(this.transitions.map((t) => [t, []]));
    for (const [a, b] of arcs) {
      if (this.placeIndex.has(a)) this.inputs.get(b)!.push(this.placeIndex.get(a)!);
      else this.outputs.get(a)!.push(this.placeIndex.get(b)!);
    }
    for (const indices of this.inputs.values()) indices.sort((a, b) => a - b);
    for (const indices of this.outputs.values()) indices.sort((a, b) => a - b);
  }
  marking(final = false): number[] {
    const tokens: number[] = Array(this.places.length).fill(0);
    tokens[final ? this.final : this.initial] = 1;
    return tokens;
  }
  enabled(marking: number[], transition: string): boolean {
    const inputs = this.inputs.get(transition);
    return inputs !== undefined && inputs.every((p) => marking[p] >= 1);
  }
  enabledTransitions(marking: number[]): string[] {
    return this.transitions.filter((t) => this.enabled(marking, t));
  }
  fire(marking: number[], transition: string): number[] {
    const result = marking.slice();
    for (const p of this.inputs.get(transition)!) result[p]--;
    for (const p of this.outputs.get(transition)!) result[p]++;
    return result;
  }
}
export function readModel(): PetriNet {
  const places: string[] = [];
  const transitions: string[] = [];
  const arcs: [string, string][] = [];
  let initial = '';
  let final = '';
  for (const line of readFileSync('input/model.txt', 'ascii').trimEnd().split('\n')) {
    const [kind, a, b] = line.split(' ');
    if (kind === 'PLACE') places.push(a);
    else if (kind === 'TRANSITION') transitions.push(a);
    else if (kind === 'ARC') arcs.push([a, b]);
    else if (kind === 'INITIAL') initial = a;
    else final = a;
  }
  return new PetriNet(places, transitions, arcs, initial, final);
}
export function replayRecord(net: PetriNet): ReplayRecord {
  return {
    missing: 0,
    remaining: 0,
    consumed: 0,
    produced: 0,
    skipped: 0,
    fitting: 0,
    places: net.places.map(() => ({
      missing: 0,
      remaining: 0,
      deviating: 0,
      waitingCount: 0,
      waitingTotal: 0,
      waitingMaximum: 0,
      consumptions: new Map(),
    })),
  };
}
export function fitness(record: ReplayRecord): Fraction {
  const c = BigInt(record.consumed);
  const p = BigInt(record.produced);
  const d = 2n * c * p;
  return [d - BigInt(record.missing) * p - BigInt(record.remaining) * c, d];
}
