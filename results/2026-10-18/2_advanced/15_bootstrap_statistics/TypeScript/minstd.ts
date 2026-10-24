export class Minstd {
  constructor(private state: number) {}
  draw(): number {
    this.state = (48271 * this.state) % 2147483647;
    return this.state;
  }
  below(limit: number): number {
    return this.draw() % limit;
  }
  shuffle<T>(values: T[]): T[] {
    for (let i = values.length - 1; i > 0; i--) {
      const j = this.below(i + 1);
      [values[i], values[j]] = [values[j], values[i]];
    }
    return values;
  }
}
