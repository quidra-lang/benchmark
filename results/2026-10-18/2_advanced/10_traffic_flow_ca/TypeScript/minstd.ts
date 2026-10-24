export class Minstd {
  constructor(private state: number) {}

  draw(): number {
    this.state = (48271 * this.state) % 2147483647;
    return this.state;
  }
}

export function select(weights: readonly number[], random: number): number {
  let sum = 0;
  for (const weight of weights) sum += weight;
  let remainder = random % sum;
  let index = 0;
  while (remainder >= weights[index]) remainder -= weights[index++];
  return index;
}
