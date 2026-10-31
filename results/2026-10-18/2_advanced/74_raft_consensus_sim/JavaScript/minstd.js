'use strict';

class Minstd {
  constructor(seed) { this.state = seed; this.draws = 0; }
  next() {
    this.state = (48271 * this.state) % 2147483647;
    this.draws++;
    return this.state;
  }
  range(low, high) { return low + this.next() % (high - low + 1); }
}

module.exports = { Minstd };
