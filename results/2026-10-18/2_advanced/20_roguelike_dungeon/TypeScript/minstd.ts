import type { Dice } from './combat.ts';

export class Minstd {
  constructor(private state: number) {}
  next(): number {
    // The largest product is below 2^47, so number arithmetic is exact here.
    this.state = (48271 * this.state) % 2147483647;
    return this.state;
  }
  rnd(n: number): number { return this.next() % n; }
  roll(dice: Dice): number {
    let sum = 0;
    for (let i = 0; i < dice.count; i++) sum += 1 + this.rnd(dice.sides);
    return sum;
  }
  select<T extends { weight: number }>(choices: T[]): T {
    let q = this.rnd(choices.reduce((sum, choice) => sum + choice.weight, 0));
    for (const choice of choices) {
      if (q < choice.weight) return choice;
      q -= choice.weight;
    }
    throw new Error('Empty weighted selection');
  }
}
