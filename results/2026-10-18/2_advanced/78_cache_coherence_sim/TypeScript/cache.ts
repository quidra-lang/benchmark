import type { Geometry, CacheHit, CacheLine, CacheSet } from './types.ts';

export class Cache {
  ways: number;
  policy: string;
  clock: number;
  sets: CacheSet[];
  constructor(geometry: Geometry, policy: string) {
    this.ways = geometry.ways; this.policy = policy; this.clock = 0;
    this.sets = Array.from({ length: geometry.sets }, () => ({ ways: Array<CacheLine | null>(this.ways).fill(null), bits: Array<number>(this.ways).fill(0), fills: 0, evictions: 0 }));
  }
  lookup(block: number): CacheHit | null {
    const set = block % this.sets.length, way = this.sets[set].ways.findIndex(line => line !== null && line.block === block);
    return way < 0 ? null : { set, way, line: this.sets[set].ways[way]! };
  }
  state(block: number): string { const found = this.lookup(block); return found === null ? 'I' : found.line.state; }
  setState(block: number, state: string): void { this.lookup(block)!.line.state = state; }
  remove(block: number): void {
    const found = this.lookup(block);
    if (found !== null) this.sets[found.set].ways[found.way] = null;
  }
  touch(found: CacheHit, fill = false): void {
    if (this.policy === 'FIFO' && !fill) return;
    found.line.stamp = ++this.clock;
    if (this.policy !== 'PLRU') return;
    const bits = this.sets[found.set].bits;
    let node = 1, first = 0, width = this.ways;
    while (width > 1) {
      const half = width / 2;
      if (found.way < first + half) { bits[node] = 1; node *= 2; }
      else { bits[node] = 0; first += half; node = node * 2 + 1; }
      width = half;
    }
  }
  victim(setNumber: number): number {
    const set = this.sets[setNumber], empty = set.ways.findIndex(line => line === null);
    if (empty >= 0) return empty;
    if (this.policy !== 'PLRU') {
      let oldest = 0;
      for (let way = 1; way < this.ways; way++) if (set.ways[way]!.stamp < set.ways[oldest]!.stamp) oldest = way;
      return oldest;
    }
    let node = 1, first = 0, width = this.ways;
    while (width > 1) {
      width /= 2;
      if (set.bits[node] === 0) node *= 2;
      else { first += width; node = node * 2 + 1; }
    }
    return first;
  }
  fill(block: number, state: string): CacheLine | null {
    const setNumber = block % this.sets.length, set = this.sets[setNumber], way = this.victim(setNumber);
    const previous = set.ways[way];
    set.fills++;
    if (previous !== null) set.evictions++;
    const line: CacheLine = { block, state, stamp: 0 }; set.ways[way] = line;
    this.touch({ set: setNumber, way, line }, true);
    return previous;
  }
  order(setNumber: number): string {
    const set = this.sets[setNumber];
    if (this.policy === 'PLRU') return this.ways === 1 ? '-' : set.bits.slice(1).join('');
    return set.ways.map((line, way) => ({ line, way })).filter(item => item.line !== null)
      .sort((a, b) => b.line!.stamp - a.line!.stamp || a.way - b.way).map(item => item.way).join(' ') || '-';
  }
}

