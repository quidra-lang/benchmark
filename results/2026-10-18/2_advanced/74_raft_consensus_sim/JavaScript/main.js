'use strict';

const fs = require('fs');
const { read } = require('./cluster');
const { Minstd } = require('./minstd');
const { Network, TYPES } = require('./network');
const { RaftNode, makeEntry, copyEntry, sameEntry, applyCommand } = require('./raft_node');
const { Checker } = require('./checker');

const nodeSet = numbers => Array.from(numbers).sort((a, b) => a - b).map(number => `n${number}`).join(',') || '-';
const sameState = (a, b) => a.size === b.size && Array.from(a).every(([key, value]) => b.has(key) && b.get(key) === value);
const messageCounts = counts => `sent ${counts.sent} delivered ${counts.delivered} inflight ${counts.inflight} partition ${counts.partition} rule ${counts.rule} loss ${counts.loss} down ${counts.down}`;

class Simulation {
  constructor(settings, controls, requests) {
    this.settings = settings; this.controls = controls; this.requests = requests;
    this.nodes = Array.from({ length: settings.NODES }, (_, i) => new RaftNode(i + 1));
    this.random = new Minstd(settings.SEED); this.network = new Network(settings.NODES, 'input/network.txt');
    this.checker = new Checker(); this.elections = []; this.leaders = new Map(); this.traceLines = [];
    this.timeline = []; this.gaps = []; this.gapStart = null; this.leaderTicks = 0; this.multiTicks = 0; this.time = 0;
  }
  node(number) { return this.nodes[number - 1]; }
  trace(content) { this.traceLines.push(`${this.time} ${content}`); }
  majority(count) { return 2 * count > this.nodes.length; }
  electionTimer(node) { node.electionDeadline = this.time + this.random.range(...this.settings.ELECTION); }
  send(node, destination, type, content = {}) {
    this.network.send(this.time, node.number, destination, type, node.currentTerm, content);
  }
  appendTo(node, destination) {
    const prev = node.next.get(destination) - 1;
    this.send(node, destination, 'AE', { prev, prevTerm: node.term(prev),
      entries: node.log.slice(prev, Math.min(prev + this.settings.BATCH, node.lastIndex)).map(copyEntry), commit: node.commit });
  }
  appendAll(node) {
    for (const other of this.nodes) if (other !== node) this.appendTo(node, other.number);
  }
  endLeadership(node, reason) {
    const record = this.leaders.get(node.currentTerm);
    record.ended = this.time; record.reason = reason; record.commit = node.commit;
    node.transfer = null;
  }
  startElection(node, trigger) {
    node.currentTerm++; node.role = 'CANDIDATE'; node.votedFor = node.number;
    node.votes = new Set([node.number]); node.knownLeader = null;
    this.electionTimer(node); node.stats.elections++;
    const election = { time: this.time, node: node.number, term: node.currentTerm, trigger, votes: node.votes, won: null };
    node.election = election; this.elections.push(election);
    this.trace(`ELECTION n${node.number} term ${node.currentTerm} last ${node.lastIndex}/${node.lastTerm} deadline ${node.electionDeadline}`);
    for (const other of this.nodes) if (other !== node) {
      this.send(node, other.number, 'RV', { lastIndex: node.lastIndex, lastTerm: node.lastTerm });
    }
  }
  becomeLeader(node) {
    node.role = 'LEADER'; node.knownLeader = node.number;
    for (const other of this.nodes) if (other !== node) {
      node.next.set(other.number, node.lastIndex + 1); node.match.set(other.number, 0);
    }
    node.log.push(makeEntry(node.currentTerm, 'NOOP', 0)); node.stats.leaders++; node.election.won = this.time;
    this.checker.leader(node);
    this.leaders.set(node.currentTerm, { node: node.number, elected: this.time, votes: new Set(node.votes),
      appended: 1, ended: null, reason: 'ACTIVE', commit: null });
    this.trace(`LEADER n${node.number} term ${node.currentTerm} votes ${nodeSet(node.votes)} noop ${node.lastIndex}`);
    this.appendAll(node);
    node.heartbeatDeadline = this.time + this.settings.HEARTBEAT;
    node.quorumDeadline = this.time + this.settings.QUORUM; node.heard = new Set();
  }
  advanceCommit(node, last) {
    this.checker.commit(node, node.commit + 1, last, this.time);
    node.commit = last;
    const first = node.applied + 1;
    for (let index = first; index <= last; index++) {
      const entry = node.entry(index), result = applyCommand(node.store, entry.command);
      node.stats.applies++; this.checker.apply(index, entry, result);
    }
    node.applied = last;
    this.trace(`APPLY n${node.number} ${first}-${last}`);
  }
  commitCheck(node) {
    for (let index = node.lastIndex; index > node.commit; index--) {
      if (node.term(index) !== node.currentTerm) break;
      let count = 1;
      for (const matched of node.match.values()) if (matched >= index) count++;
      if (this.majority(count)) {
        this.trace(`COMMIT n${node.number} ${node.commit + 1}-${index} term ${node.currentTerm}`);
        this.advanceCommit(node, index); break;
      }
    }
  }
  truncate(node, first) {
    const removed = node.lastIndex - first + 1;
    node.stats.truncated += removed; this.checker.truncate(node, first);
    node.log.length = first - 1;
    this.trace(`TRUNCATE n${node.number} from ${first} removed ${removed}`);
  }
  requestVote(node, message) {
    const { source, term, content } = message;
    let reason = null;
    if (term < node.currentTerm) reason = 'term';
    else if (node.votedFor !== null && node.votedFor !== source) reason = 'voted';
    else if (!node.candidateCurrent(content.lastIndex, content.lastTerm)) reason = 'log';
    if (reason === null) {
      node.votedFor = source; node.stats.votesGranted++; this.electionTimer(node);
      this.trace(`VOTE n${node.number} n${source} term ${node.currentTerm} deadline ${node.electionDeadline}`);
    } else this.trace(`DENY n${node.number} n${source} term ${node.currentTerm} ${reason}`);
    this.send(node, source, 'RVR', { granted: reason === null });
  }
  voteResponse(node, message) {
    if (node.role !== 'CANDIDATE' || message.term !== node.currentTerm || !message.content.granted) return;
    node.votes.add(message.source);
    if (this.majority(node.votes.size)) this.becomeLeader(node);
  }
  appendRequest(node, message) {
    const { source, term, content } = message;
    if (term < node.currentTerm) { this.send(node, source, 'AER', { success: false, m: 0 }); return; }
    if (node.role === 'CANDIDATE') {
      node.role = 'FOLLOWER';
      this.trace(`YIELD n${node.number} term ${node.currentTerm} n${source}`);
    }
    node.knownLeader = source; this.electionTimer(node);
    if (content.prev > node.lastIndex || node.term(content.prev) !== content.prevTerm) {
      node.stats.aeFail++;
      this.send(node, source, 'AER', { success: false, m: content.prev > node.lastIndex ? node.lastIndex : content.prev - 1 });
      return;
    }
    node.stats.aeOk++;
    for (let i = 0; i < content.entries.length; i++) {
      const index = content.prev + i + 1, entry = content.entries[i];
      if (index <= node.lastIndex && node.term(index) !== entry.term) this.truncate(node, index);
      if (index > node.lastIndex) { node.log.push(copyEntry(entry)); node.stats.appended++; }
    }
    const m = content.prev + content.entries.length, committed = Math.min(content.commit, m);
    if (committed > node.commit) this.advanceCommit(node, committed);
    this.send(node, source, 'AER', { success: true, m });
  }
  appendResponse(node, message) {
    if (node.role !== 'LEADER' || message.term !== node.currentTerm) return;
    const source = message.source, { success, m } = message.content;
    node.heard.add(source);
    if (success) {
      node.match.set(source, Math.max(node.match.get(source), m));
      node.next.set(source, Math.max(node.next.get(source), m + 1));
      this.commitCheck(node);
      if (node.transfer !== null && node.transfer.target === source && !node.transfer.sent && node.match.get(source) === node.lastIndex) {
        this.timeoutNow(node);
      } else if (node.next.get(source) <= node.lastIndex) this.appendTo(node, source);
    } else {
      node.next.set(source, Math.max(node.match.get(source) + 1, Math.min(node.next.get(source) - 1, m + 1)));
      this.trace(`BACKTRACK n${node.number} n${source} next ${node.next.get(source)}`);
      this.appendTo(node, source);
    }
  }
  receive(node, message) {
    if (message.term > node.currentTerm) {
      const role = node.role;
      this.trace(`TERM n${node.number} ${node.currentTerm}->${message.term} ${message.type} n${message.source} ${role}`);
      if (role === 'LEADER') this.endLeadership(node, 'STEPDOWN');
      node.currentTerm = message.term; node.votedFor = null; node.knownLeader = null; node.role = 'FOLLOWER';
      if (role === 'LEADER') this.electionTimer(node);
    }
    if (message.type === 'RV') this.requestVote(node, message);
    else if (message.type === 'RVR') this.voteResponse(node, message);
    else if (message.type === 'AE') this.appendRequest(node, message);
    else if (message.type === 'AER') this.appendResponse(node, message);
    else if (message.term !== node.currentTerm || node.role !== 'FOLLOWER') {
      this.trace(`IGNORE n${node.number} TN n${message.source} term ${message.term}`);
    } else this.startElection(node, 'transfer');
  }
  timeoutNow(node) {
    this.trace(`TIMEOUTNOW n${node.number} n${node.transfer.target} term ${node.currentTerm} index ${node.lastIndex}`);
    node.transfer.sent = true;
    this.send(node, node.transfer.target, 'TN');
  }
  transfer(source, target) {
    const node = this.node(source);
    if (!node.up || node.role !== 'LEADER' || node.transfer !== null || source === target) {
      this.trace(`TRANSFER n${source} n${target} ignored`); return;
    }
    this.trace(`TRANSFER n${source} n${target} start match ${node.match.get(target)}/${node.lastIndex}`);
    node.transfer = { target, sent: false, deadline: this.time + this.settings.ELECTION[0] };
    if (node.match.get(target) === node.lastIndex) this.timeoutNow(node);
    else this.appendTo(node, target);
  }
  control(event) {
    if (event.kind === 'CRASH') {
      const node = this.node(event.args[0]);
      this.trace(`CRASH n${node.number} ${node.role} term ${node.currentTerm}`);
      if (node.role === 'LEADER') this.endLeadership(node, 'CRASH');
      node.up = false; node.resetVolatile();
    } else if (event.kind === 'RESTART') {
      const node = this.node(event.args[0]);
      node.up = true; this.electionTimer(node);
      this.trace(`RESTART n${node.number} term ${node.currentTerm} length ${node.lastIndex} deadline ${node.electionDeadline}`);
    } else if (event.kind === 'PARTITION') {
      this.network.partition(event.args);
      this.trace(`PARTITION ${event.args.map(nodeSet).join(' ')}`);
    } else if (event.kind === 'HEAL') { this.network.heal(); this.trace('HEAL'); }
    else this.transfer(...event.args);
  }
  attempt(request) {
    request.attempts++;
    let destination = request.destination, redirected = 0;
    while (true) {
      const node = this.node(destination);
      let reason;
      if (!node.up) reason = 'down';
      else if (node.role === 'LEADER') {
        if (node.transfer !== null) reason = 'transfer';
        else {
          node.log.push(makeEntry(node.currentTerm, request.command, request.number));
          this.leaders.get(node.currentTerm).appended++;
          request.accepted = { index: node.lastIndex, term: node.currentTerm };
          this.trace(`ACCEPT r${request.number} n${node.number} index ${node.lastIndex} term ${node.currentTerm}`);
          return;
        }
      } else if (node.knownLeader === null || redirected >= this.nodes.length - 1) reason = 'noleader';
      else {
        this.trace(`REDIRECT r${request.number} n${node.number} n${node.knownLeader}`);
        request.redirects++; redirected++; destination = node.knownLeader; continue;
      }
      if (request.attempts < this.settings.ATTEMPTS) {
        request.destination = node.number % this.nodes.length + 1; request.scheduled = this.time + this.settings.RETRY;
        this.trace(`REJECT r${request.number} n${node.number} ${reason} retry n${request.destination} at ${request.scheduled}`);
      } else { request.abandoned = true; this.trace(`REJECT r${request.number} n${node.number} ${reason} giveup`); }
      return;
    }
  }
  timers(node) {
    if (node.role === 'LEADER') {
      if (node.quorumDeadline === this.time) {
        if (!this.majority(node.heard.size + 1)) {
          this.trace(`STEPDOWN n${node.number} term ${node.currentTerm} heard ${nodeSet(node.heard)}`);
          this.endLeadership(node, 'QUORUM'); node.role = 'FOLLOWER'; node.knownLeader = null; this.electionTimer(node);
          return;
        }
        node.heard = new Set(); node.quorumDeadline = this.time + this.settings.QUORUM;
      }
      if (node.transfer !== null && node.transfer.deadline === this.time) {
        this.trace(`TRANSFER n${node.number} n${node.transfer.target} abort`); node.transfer = null;
      }
      if (node.heartbeatDeadline === this.time) {
        this.appendAll(node); node.heartbeatDeadline = this.time + this.settings.HEARTBEAT;
      }
    } else if (node.electionDeadline === this.time) this.startElection(node, 'timeout');
  }
  endTick() {
    this.checker.matching(this.nodes);
    const active = this.nodes.filter(node => node.up && node.role === 'LEADER');
    for (const node of active) node.stats.leaderTicks++;
    if (active.length > 0) {
      this.leaderTicks++;
      if (active.length >= 2) this.multiTicks++;
      if (this.gapStart !== null) { this.gaps.push([this.gapStart, this.time - 1]); this.gapStart = null; }
    } else if (this.gapStart === null) this.gapStart = this.time;
    if (this.time % this.settings.SAMPLE === 0) {
      this.timeline.push(`TIMELINE ${this.time} ${this.nodes.map(node => `${node.up ? node.role[0] : 'D'}${node.currentTerm}`).join(' ')}`);
    }
  }
  simulate() {
    for (const node of this.nodes) { this.electionTimer(node); this.trace(`START n${node.number} deadline ${node.electionDeadline}`); }
    for (this.time = 0; this.time <= this.settings.END; this.time++) {
      for (const event of this.controls.get(this.time) || []) this.control(event);
      for (const request of this.requests) {
        if (!request.accepted && !request.abandoned && request.scheduled === this.time) this.attempt(request);
      }
      for (const message of this.network.take(this.time)) {
        const destination = this.node(message.destination);
        if (!destination.up) this.network.resolve(message, 'down');
        else if (this.network.separated(message.source, message.destination)) this.network.resolve(message, 'partition');
        else { this.network.resolve(message, 'delivered'); this.receive(destination, message); }
      }
      for (const node of this.nodes) if (node.up) this.timers(node);
      this.endTick();
    }
    if (this.gapStart !== null) this.gaps.push([this.gapStart, this.settings.END]);
  }
}

function leaderReport(simulation, maximumTerm) {
  const lines = [];
  for (const election of simulation.elections) {
    lines.push(`ELECTION ${election.time} n${election.node} term ${election.term} trigger ${election.trigger} votes ${election.votes.size} ${election.won === null ? 'LOST' : `WON ${election.won}`}`);
  }
  for (let term = 1; term <= maximumTerm; term++) {
    const elections = simulation.elections.filter(election => election.term === term);
    const candidates = nodeSet(new Set(elections.map(election => election.node))), record = simulation.leaders.get(term);
    if (!record) { lines.push(`TERM ${term} NONE candidates ${candidates}`); continue; }
    const commit = record.ended === null ? simulation.node(record.node).commit : record.commit;
    const started = elections[0].time;
    lines.push(`TERM ${term} LEADER n${record.node} elected ${record.elected} votes ${nodeSet(record.votes)} ended ${record.ended === null ? '-' : record.ended} ${record.reason} appended ${record.appended} commit ${commit} candidates ${candidates} started ${started} wait ${record.elected - started}`);
  }
  for (const node of simulation.nodes) {
    const stats = node.stats;
    lines.push(`NODE n${node.number} elections ${stats.elections} leader_terms ${stats.leaders} leader_ticks ${stats.leaderTicks} votes_granted ${stats.votesGranted}`);
  }
  lines.push(...simulation.timeline);
  let longest = 0;
  for (const [first, last] of simulation.gaps) {
    const length = last - first + 1; longest = Math.max(longest, length);
    lines.push(`GAP ${first}-${last} length ${length}`);
  }
  lines.push(`SUMMARY terms ${maximumTerm} leaders ${simulation.leaders.size} elections ${simulation.elections.length} leader_ticks ${simulation.leaderTicks} multi_ticks ${simulation.multiTicks} ticks ${simulation.settings.END + 1} gaps ${simulation.gaps.length} longest ${longest}`);
  return lines;
}

function logReport(simulation) {
  const lines = [], committed = simulation.checker.committed.size;
  for (const node of simulation.nodes) {
    lines.push(`NODE n${node.number} ${node.up ? node.role : 'DOWN'} term ${node.currentTerm} voted ${node.votedFor === null ? '-' : `n${node.votedFor}`} commit ${node.commit} applied ${node.applied} length ${node.lastIndex}`);
    node.log.forEach((entry, i) => lines.push(`${i + 1} ${entry.term} ${entry.command}${entry.request === 0 ? '' : ` r${entry.request}`}`));
  }
  let prefix = 0;
  const shortest = Math.min(...simulation.nodes.map(node => node.lastIndex));
  while (prefix < shortest && simulation.nodes.every(node => sameEntry(node.entry(prefix + 1), simulation.nodes[0].entry(prefix + 1)))) prefix++;
  lines.push(`AGREE prefix ${prefix} committed ${committed}`);
  for (const node of simulation.nodes) {
    let common = 0;
    while (common < Math.min(node.lastIndex, committed) && node.term(common + 1) === simulation.checker.committed.get(common + 1).term) common++;
    const stats = node.stats;
    lines.push(`DIFF n${node.number} common ${common} behind ${committed - common} extra ${node.lastIndex - common} ae_ok ${stats.aeOk} ae_fail ${stats.aeFail} appended ${stats.appended} truncated ${stats.truncated} applies ${stats.applies}`);
  }
  return lines;
}

function finalStates(simulation) {
  const committed = simulation.checker.committed.size, reference = new Map();
  const wanted = new Set(simulation.nodes.map(node => node.applied)), replays = new Map([[0, new Map()]]);
  for (let index = 1; index <= committed; index++) {
    applyCommand(reference, simulation.checker.applied.get(index).entry.command);
    if (wanted.has(index)) replays.set(index, new Map(reference));
  }
  const requests = simulation.requests.map(request => {
    if (request.accepted === null) return { ...request, status: request.abandoned ? 'FAILED' : 'WAITING' };
    const { index, term } = request.accepted, record = simulation.checker.committed.get(index);
    if (record && record.term === term) return { ...request, status: 'COMMITTED',
      latency: record.time - request.time, result: simulation.checker.applied.get(index).result };
    const retained = simulation.nodes.some(node => node.lastIndex >= index && node.term(index) === term);
    return { ...request, status: retained ? 'UNCOMMITTED' : 'LOST' };
  });
  return { reference, replays, requests };
}

function stateReport(simulation, states) {
  const lines = [];
  for (const node of simulation.nodes) {
    const identical = sameState(node.store, states.replays.get(node.applied));
    lines.push(`NODE n${node.number} ${node.up ? 'UP' : 'DOWN'} applied ${node.applied} keys ${node.store.size} replay ${identical ? 'match' : 'mismatch'}`);
    for (const key of Array.from(node.store.keys()).sort()) lines.push(`${key} ${node.store.get(key)}`);
  }
  const counts = { COMMITTED: 0, UNCOMMITTED: 0, LOST: 0, FAILED: 0, WAITING: 0 }, latencies = [], keys = new Map();
  for (const request of states.requests) {
    counts[request.status]++;
    let status = request.status;
    if (request.accepted !== null) {
      status += ` index ${request.accepted.index} term ${request.accepted.term}`;
      if (request.status === 'COMMITTED') {
        status += ` latency ${request.latency} result ${request.result}`; latencies.push(request.latency);
      }
    } else if (request.status === 'WAITING') status += ` next ${request.scheduled}`;
    lines.push(`REQUEST r${request.number} at ${request.time} n${request.startNode} ${request.command} attempts ${request.attempts} redirects ${request.redirects} ${status}`);
    const key = request.command.split(' ')[1];
    if (!keys.has(key)) keys.set(key, { requests: 0, committed: 0 });
    keys.get(key).requests++;
    if (request.status === 'COMMITTED') keys.get(key).committed++;
  }
  for (const key of Array.from(keys.keys()).sort()) {
    const tally = keys.get(key);
    lines.push(`KEY ${key} requests ${tally.requests} committed ${tally.committed} final ${states.reference.has(key) ? states.reference.get(key) : 'missing'}`);
  }
  lines.push(`REQUESTS total ${states.requests.length} committed ${counts.COMMITTED} uncommitted ${counts.UNCOMMITTED} lost ${counts.LOST} failed ${counts.FAILED} waiting ${counts.WAITING}`,
    `LATENCY count ${latencies.length} total ${latencies.reduce((sum, value) => sum + value, 0)} min ${latencies.length ? Math.min(...latencies) : 0} max ${latencies.length ? Math.max(...latencies) : 0}`);
  return lines;
}

function safetyReport(simulation, maximumTerm) {
  const lines = simulation.checker.lines(maximumTerm), network = simulation.network;
  lines.push(`MESSAGES ${messageCounts(network.total)}`);
  for (const type of TYPES) lines.push(`TYPE ${type} ${messageCounts(network.types.get(type))}`);
  for (const link of network.links.values()) {
    const counts = link.counts, dropped = counts.partition + counts.rule + counts.loss + counts.down;
    lines.push(`LINK n${link.source}->n${link.destination} delay ${link.delay} loss ${link.loss} sent ${counts.sent} delivered ${counts.delivered} dropped ${dropped}`);
  }
  lines.push(`DRAWS ${simulation.random.draws}`, `RESULT ${simulation.checker.violations.every(count => count === 0) ? 'SAFE' : 'UNSAFE'}`);
  return lines;
}

function main() {
  const { settings, controls, requests } = read(), simulation = new Simulation(settings, controls, requests);
  simulation.simulate();
  const maximumTerm = Math.max(...simulation.nodes.map(node => node.currentTerm)), states = finalStates(simulation);
  const reports = [
    ['trace.txt', simulation.traceLines], ['leaders.txt', leaderReport(simulation, maximumTerm)],
    ['logs.txt', logReport(simulation)], ['state.txt', stateReport(simulation, states)],
    ['safety.txt', safetyReport(simulation, maximumTerm)],
  ];
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of reports) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
