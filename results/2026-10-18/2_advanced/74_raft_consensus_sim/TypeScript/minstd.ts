export class Minstd {
  draws = 0;
  constructor(private state: number) {}
  next(): number { this.state = 48271 * this.state % 2147483647; this.draws++; return this.state; }
  range(low: number, high: number): number { return low + this.next() % (high - low + 1); }
}
