'use strict';

const { hex } = require('./config_io');

class Bus {
  constructor(latency) { this.latency = latency; this.free = 0; this.busy = 0; this.wait = 0; this.transactions = []; }
  assign(requestCycle, core, type, block) {
    const start = Math.max(requestCycle, this.free);
    this.wait += start - requestCycle; this.busy += this.latency; this.free = start + this.latency;
    const transaction = { number: this.transactions.length + 1, start, core, type, block,
      snoops: [], supplier: null, invalidations: 0, l2: null, eviction: null };
    this.transactions.push(transaction);
    return transaction;
  }
  lines(lineSize) {
    return this.transactions.map(transaction => {
      const prefix = `${transaction.number} ${transaction.start} c${transaction.core} ${transaction.type} ${hex(transaction.block * lineSize)}`;
      if (transaction.type === 'WB') return prefix;
      let line = `${prefix} snoop ${transaction.snoops.join(' ') || 'none'}`;
      if (transaction.type === 'BusUpgr') return line;
      if (transaction.type === 'BusRd' || transaction.type === 'BusRdX') {
        line += ` data ${transaction.supplier !== null ? `c${transaction.supplier}` : transaction.l2 === 'hit' ? 'L2' : 'mem'}`;
      }
      line += ` l2 ${transaction.l2}`;
      if (transaction.eviction !== null) {
        const evicted = transaction.eviction;
        line += ` evict ${hex(evicted.block * lineSize)} ${evicted.copies.join(' ') || 'none'} ${evicted.dirty ? 'dirty' : 'clean'}`;
      }
      return line;
    });
  }
}

module.exports = { Bus };
