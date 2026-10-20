import type { Predictor } from './trace_io.ts';

export class Btb {
  private entries: ({ pc: number; target: number } | undefined)[];
  constructor(size: number) { this.entries = Array(size).fill(undefined); }
  lookup(pc: number): number | undefined { const entry = this.entries[Math.floor(pc / 4) % this.entries.length]; return entry?.pc === pc ? entry.target : undefined; }
  insert(pc: number, target: number): void { this.entries[Math.floor(pc / 4) % this.entries.length] = { pc, target }; }
}
export class Ras {
  private stack: number[] = [];
  constructor(private depth: number) {}
  push(address: number): void { if (!this.depth) return; if (this.stack.length === this.depth) this.stack.shift(); this.stack.push(address); }
  pop(): number | undefined { return this.stack.pop(); }
}
const updateCounter = (value: number, taken: boolean) => taken ? Math.min(3, value + 1) : Math.max(0, value - 1);
export class DirectionPredictor {
  private local: number[] = [];
  private global: number[] = [];
  private chooser: number[] = [];
  private history = 0;
  constructor(private config: Predictor) {
    if (config.scheme === 'ONEBIT' || config.scheme === 'TWOBIT') this.local = Array<number>(config.size).fill(config.scheme === 'ONEBIT' ? 0 : 1);
    else if (config.scheme === 'GSHARE') this.global = Array<number>(config.size).fill(1);
    else if (config.scheme === 'TOURNAMENT') { this.local = Array<number>(config.local).fill(1); this.global = Array<number>(config.global).fill(1); this.chooser = Array<number>(config.chooser).fill(1); }
  }
  predict(pc: number, target: number, actual: boolean): boolean {
    const config = this.config, word = Math.floor(pc / 4);
    if (config.scheme === 'PERFECT') return actual;
    if (config.scheme === 'STATIC_NT') return false;
    if (config.scheme === 'BTFN') return target < pc;
    if (config.scheme === 'ONEBIT') return this.local[word % config.size] === 1;
    if (config.scheme === 'TWOBIT') return this.local[word % config.size] >= 2;
    if (config.scheme === 'GSHARE') return this.global[(word ^ this.history) % config.size] >= 2;
    if (config.scheme === 'TOURNAMENT') return this.chooser[word % config.chooser] >= 2 ? this.global[(word ^ this.history) % config.global] >= 2 : this.local[word % config.local] >= 2;
    return false;
  }
  update(pc: number, taken: boolean): void {
    const config = this.config, word = Math.floor(pc / 4);
    if (config.scheme === 'ONEBIT') this.local[word % config.size] = taken ? 1 : 0;
    else if (config.scheme === 'TWOBIT') this.local[word % config.size] = updateCounter(this.local[word % config.size], taken);
    else if (config.scheme === 'GSHARE') {
      const index = (word ^ this.history) % config.size; this.global[index] = updateCounter(this.global[index], taken); this.history = (2 * this.history + (taken ? 1 : 0)) % 2 ** config.history;
    } else if (config.scheme === 'TOURNAMENT') {
      const li = word % config.local, gi = (word ^ this.history) % config.global, ci = word % config.chooser;
      const local = this.local[li] >= 2, global = this.global[gi] >= 2;
      if (local !== global) this.chooser[ci] = updateCounter(this.chooser[ci], global === taken);
      this.local[li] = updateCounter(this.local[li], taken); this.global[gi] = updateCounter(this.global[gi], taken);
      this.history = (2 * this.history + (taken ? 1 : 0)) % 2 ** config.history;
    }
  }
}
export function storage(config: Predictor): number {
  if (config.scheme === 'ONEBIT') return config.size;
  if (config.scheme === 'TWOBIT') return 2 * config.size;
  if (config.scheme === 'GSHARE') return 2 * config.size + config.history;
  if (config.scheme === 'TOURNAMENT') return 2 * (config.local + config.global + config.chooser) + config.history;
  return 0;
}
