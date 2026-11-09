'use strict';

const makeEntry = (term, command, request) => ({ term, command, request });
const copyEntry = entry => ({ ...entry });
const sameEntry = (first, second) => first.term === second.term && first.command === second.command && first.request === second.request;

class RaftNode {
  constructor(number) {
    this.number = number; this.currentTerm = 0; this.votedFor = null; this.log = []; this.up = true;
    this.stats = { elections: 0, leaders: 0, votesGranted: 0, leaderTicks: 0, aeOk: 0, aeFail: 0, appended: 0, truncated: 0, applies: 0 };
    this.resetVolatile();
  }
  resetVolatile() {
    this.role = 'FOLLOWER'; this.commit = 0; this.applied = 0; this.store = new Map();
    this.knownLeader = null; this.votes = new Set(); this.electionDeadline = null;
    this.next = new Map(); this.match = new Map(); this.heartbeatDeadline = null; this.quorumDeadline = null;
    this.heard = new Set(); this.transfer = null; this.election = null;
  }
  get lastIndex() { return this.log.length; }
  get lastTerm() { return this.term(this.lastIndex); }
  entry(index) { return this.log[index - 1]; }
  term(index) { return index === 0 ? 0 : this.entry(index).term; }
  candidateCurrent(lastIndex, lastTerm) {
    return lastTerm > this.lastTerm || (lastTerm === this.lastTerm && lastIndex >= this.lastIndex);
  }
}

function applyCommand(store, command) {
  const [kind, key, value] = command.split(' ');
  if (kind === 'NOOP') return null;
  if (kind === 'SET') { store.set(key, Number(value)); return 'ok'; }
  if (kind === 'ADD') {
    const sum = (store.has(key) ? store.get(key) : 0) + Number(value);
    store.set(key, sum);
    return String(sum);
  }
  if (kind === 'DEL') {
    if (!store.has(key)) return 'missing';
    store.delete(key);
    return 'deleted';
  }
  return store.has(key) ? String(store.get(key)) : 'missing';
}

module.exports = { RaftNode, makeEntry, copyEntry, sameEntry, applyCommand };
