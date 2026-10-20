'use strict';

const { SYMBOLS } = require('./suffix_array');

class FMIndex {
  constructor(text, sa, interval, sampleInterval = null) {
    this.text = text; this.sa = sa; this.interval = interval;
    this.bwt = sa.map(position => text[position > 0 ? position - 1 : text.length - 1]).join('');
    this.checkpoints = [];
    const counts = Array(6).fill(0);
    for (let i = 0; i <= text.length; i++) {
      if (i % interval === 0) this.checkpoints.push(counts.slice());
      if (i < text.length) counts[SYMBOLS.indexOf(this.bwt[i])]++;
    }
    this.counts = counts;
    this.C = Array(6).fill(0);
    for (let i = 1; i < 6; i++) this.C[i] = this.C[i - 1] + counts[i - 1];
    this.samples = new Map();
    if (sampleInterval !== null) sa.forEach((position, row) => {
      if (position % sampleInterval === 0) this.samples.set(row, position);
    });
  }

  occ(symbol, position) {
    const checkpoint = Math.floor(position / this.interval), index = SYMBOLS.indexOf(symbol);
    let count = this.checkpoints[checkpoint][index];
    for (let i = checkpoint * this.interval; i < position; i++) if (this.bwt[i] === symbol) count++;
    return count;
  }

  lf(row) { return this.C[SYMBOLS.indexOf(this.bwt[row])] + this.occ(this.bwt[row], row); }

  extend(lo, hi, base) {
    if (base === 'N') return [0, 0];
    const start = this.C[SYMBOLS.indexOf(base)];
    return [start + this.occ(base, lo), start + this.occ(base, hi)];
  }

  backward(sequence) {
    let lo = 0, hi = this.text.length;
    for (let i = sequence.length - 1; i >= 0; i--) {
      [lo, hi] = this.extend(lo, hi, sequence[i]);
      if (lo >= hi) break;
    }
    return [lo, hi];
  }

  locate(row) {
    let steps = 0;
    while (!this.samples.has(row)) { row = this.lf(row); steps++; }
    return { position: this.samples.get(row) + steps, steps };
  }

  inverse() {
    const result = Array(this.text.length);
    result[result.length - 1] = '$';
    let row = 0;
    for (let i = result.length - 2; i >= 0; i--) { result[i] = this.bwt[row]; row = this.lf(row); }
    return result.join('');
  }
}

module.exports = { FMIndex };
