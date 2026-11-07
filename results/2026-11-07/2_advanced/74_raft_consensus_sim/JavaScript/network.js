'use strict';

const fs = require('fs');
const TYPES = ['RV', 'RVR', 'AE', 'AER', 'TN'];
const newCounts = () => ({ sent: 0, delivered: 0, inflight: 0, partition: 0, rule: 0, loss: 0, down: 0 });
const endpointMatches = (pattern, number) => pattern === '*' || Number(pattern) === number;

class Network {
  constructor(size, path) {
    this.groups = Array(size + 1).fill(0); this.queue = new Map(); this.serial = 0;
    this.total = newCounts(); this.types = new Map(TYPES.map(type => [type, newCounts()])); this.links = new Map();
    const lines = fs.readFileSync(path, 'ascii').split('\n').slice(0, -1).map(line => line.split(' '));
    for (let source = 1; source <= size; source++) for (let destination = 1; destination <= size; destination++) {
      if (source === destination) continue;
      const link = { source, destination, delay: Number(lines[0][1]), loss: 0, pass: 0, drops: [], counts: newCounts() };
      for (const [kind, a, b, ...args] of lines.slice(1)) {
        if (!endpointMatches(a, source) || !endpointMatches(b, destination)) continue;
        if (kind === 'DELAY') link.delay = Number(args[0]);
        else if (kind === 'LOSS') link.loss = Number(args[0]);
        else link.drops.push({ type: args[0], first: Number(args[1]), last: Number(args[2]) });
      }
      this.links.set(`${source}/${destination}`, link);
    }
  }
  separated(source, destination) { return this.groups[source] !== this.groups[destination]; }
  partition(groups) { groups.forEach((group, index) => group.forEach(node => { this.groups[node] = index; })); }
  heal() { this.groups.fill(0); }
  count(message, field, amount = 1) {
    this.total[field] += amount;
    this.types.get(message.type)[field] += amount;
    this.links.get(`${message.source}/${message.destination}`).counts[field] += amount;
  }
  send(time, source, destination, type, term, content = {}) {
    const message = { source, destination, type, term, content, serial: this.serial++ };
    const link = this.links.get(`${source}/${destination}`);
    this.count(message, 'sent');
    if (this.separated(source, destination)) { this.count(message, 'partition'); return; }
    if (link.drops.some(rule => (rule.type === type || rule.type === 'ALL') && rule.first <= time && time <= rule.last)) {
      this.count(message, 'rule'); return;
    }
    link.pass++;
    if (link.loss > 0 && link.pass % link.loss === 0) { this.count(message, 'loss'); return; }
    const arrival = time + link.delay;
    if (!this.queue.has(arrival)) this.queue.set(arrival, []);
    this.queue.get(arrival).push(message);
    this.count(message, 'inflight');
  }
  take(time) {
    const messages = this.queue.get(time) || [];
    this.queue.delete(time);
    return messages.sort((a, b) => a.source - b.source || a.serial - b.serial);
  }
  resolve(message, outcome) {
    this.count(message, 'inflight', -1);
    this.count(message, outcome);
  }
}

module.exports = { Network, TYPES };
