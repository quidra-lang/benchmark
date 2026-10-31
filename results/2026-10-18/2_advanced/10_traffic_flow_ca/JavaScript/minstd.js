class Minstd {
  constructor(seed) {
    this.state = seed;
  }

  draw() {
    this.state = (48271 * this.state) % 2147483647;
    return this.state;
  }
}

function select(weights, random) {
  let total = 0;
  for (const weight of weights) total += weight;
  let remainder = random % total;
  let index = 0;
  while (remainder >= weights[index]) {
    remainder -= weights[index];
    index += 1;
  }
  return index;
}

module.exports = { Minstd, select };
