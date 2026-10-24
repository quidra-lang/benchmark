'use strict';

const { sameEntry, copyEntry } = require('./raft_node');
const PROPERTIES = ['ELECTION_SAFETY', 'LEADER_COMPLETENESS', 'LOG_MATCHING', 'STATE_MACHINE_SAFETY', 'COMMITTED_KEPT'];

class Checker {
  constructor() {
    this.leaders = new Map(); this.committed = new Map(); this.applied = new Map();
    this.violations = Array(5).fill(0); this.elected = 0; this.ticks = 0; this.pairs = 0;
    this.applies = 0; this.truncations = 0; this.removed = 0;
  }
  leader(node) {
    this.elected++;
    if (!this.leaders.has(node.currentTerm)) this.leaders.set(node.currentTerm, node.number);
    else if (this.leaders.get(node.currentTerm) !== node.number) this.violations[0]++;
    for (const [index, record] of this.committed) {
      if (index > node.lastIndex || node.term(index) !== record.term) { this.violations[1]++; break; }
    }
  }
  commit(node, first, last, time) {
    for (let index = first; index <= last; index++) {
      if (!this.committed.has(index)) this.committed.set(index, { term: node.term(index), time });
    }
  }
  apply(index, entry, result) {
    this.applies++;
    if (!this.applied.has(index)) this.applied.set(index, { entry: copyEntry(entry), result });
    else if (!sameEntry(this.applied.get(index).entry, entry)) this.violations[3]++;
  }
  truncate(node, first) {
    this.truncations++;
    for (let index = first; index <= node.lastIndex; index++) {
      this.removed++;
      if (this.committed.has(index) && this.committed.get(index).term === node.term(index)) this.violations[4]++;
    }
  }
  matching(nodes) {
    this.ticks++;
    for (let a = 0; a < nodes.length; a++) for (let b = a + 1; b < nodes.length; b++) {
      this.pairs++;
      const first = nodes[a], second = nodes[b];
      let greatest = Math.min(first.lastIndex, second.lastIndex);
      while (greatest > 0 && first.term(greatest) !== second.term(greatest)) greatest--;
      for (let index = 1; index <= greatest; index++) {
        if (!sameEntry(first.entry(index), second.entry(index))) { this.violations[2]++; break; }
      }
    }
  }
  lines(maximumTerm) {
    const details = [
      `terms ${maximumTerm} leaders ${this.leaders.size} elected ${this.elected}`,
      `checks ${this.elected} committed ${this.committed.size}`,
      `checks ${this.ticks} pairs ${this.pairs}`,
      `applies ${this.applies} indices ${this.applied.size}`,
      `truncations ${this.truncations} removed ${this.removed}`,
    ];
    return PROPERTIES.map((property, i) => `${property} ${this.violations[i] === 0 ? 'OK' : 'FAIL'} violations ${this.violations[i]} ${details[i]}`);
  }
}

module.exports = { Checker, PROPERTIES };
