import { mkdirSync, writeFileSync } from 'node:fs';
import { read } from './cluster.ts';
import type { Settings, Control, ClientRequest } from './cluster.ts';
import { Minstd } from './minstd.ts';
import { Network, TYPES } from './network.ts';
import type { Payload, Message, Counts } from './network.ts';
import { RaftNode, makeEntry, copyEntry, sameEntry, applyCommand } from './raft_node.ts';
import type { Election, Trigger } from './raft_node.ts';
import { Checker } from './checker.ts';

const nodeSet = (nodes: Iterable<number>) =>
  [...nodes]
    .sort((a, b) => a - b)
    .map((n) => `n${n}`)
    .join(',') || '-';
const sameState = (a: Map<string, number>, b: Map<string, number>) =>
  a.size === b.size && [...a].every(([key, value]) => b.get(key) === value);
const messageCounts = (c: Counts) =>
  `sent ${c.sent} delivered ${c.delivered} inflight ${c.inflight} partition ${c.partition} rule ${c.rule} loss ${c.loss} down ${c.down}`;
type EndReason = 'ACTIVE' | 'CRASH' | 'STEPDOWN' | 'QUORUM';
interface LeaderRecord {
  node: number;
  elected: number;
  votes: Set<number>;
  appended: number;
  ended: number | null;
  reason: EndReason;
  commit: number | null;
}
class Simulation {
  nodes: RaftNode[];
  random: Minstd;
  network: Network;
  checker = new Checker();
  elections: Election[] = [];
  leaders = new Map<number, LeaderRecord>();
  traceLines: string[] = [];
  timeline: string[] = [];
  gaps: [number, number][] = [];
  gapStart: number | null = null;
  leaderTicks = 0;
  multiTicks = 0;
  time = 0;
  constructor(
    readonly settings: Settings,
    readonly controls: Map<number, Control[]>,
    readonly requests: ClientRequest[],
  ) {
    this.nodes = Array.from({ length: settings.nodes }, (_, i) => new RaftNode(i + 1));
    this.random = new Minstd(settings.seed);
    this.network = new Network(settings.nodes, 'input/network.txt');
  }
  node(number: number): RaftNode {
    return this.nodes[number - 1];
  }
  trace(content: string): void {
    this.traceLines.push(`${this.time} ${content}`);
  }
  majority(count: number): boolean {
    return 2 * count > this.nodes.length;
  }
  electionTimer(node: RaftNode): void {
    node.electionDeadline =
      this.time + this.random.range(this.settings.electionMin, this.settings.electionMax);
  }
  send(node: RaftNode, destination: number, payload: Payload): void {
    this.network.send(this.time, node.number, destination, node.currentTerm, payload);
  }
  appendTo(node: RaftNode, destination: number): void {
    const prev = node.next.get(destination)! - 1;
    this.send(node, destination, {
      type: 'AE',
      prev,
      prevTerm: node.term(prev),
      entries: node.log
        .slice(prev, Math.min(prev + this.settings.batch, node.lastIndex))
        .map(copyEntry),
      commit: node.commit,
    });
  }
  appendAll(node: RaftNode): void {
    for (const other of this.nodes) if (other !== node) this.appendTo(node, other.number);
  }
  endLeadership(node: RaftNode, reason: EndReason): void {
    const record = this.leaders.get(node.currentTerm)!;
    record.ended = this.time;
    record.reason = reason;
    record.commit = node.commit;
    node.transfer = null;
  }
  startElection(node: RaftNode, trigger: Trigger): void {
    node.currentTerm++;
    node.role = 'CANDIDATE';
    node.votedFor = node.number;
    node.votes = new Set([node.number]);
    node.knownLeader = null;
    this.electionTimer(node);
    node.stats.elections++;
    const election: Election = {
      time: this.time,
      node: node.number,
      term: node.currentTerm,
      trigger,
      votes: node.votes,
      won: null,
    };
    node.election = election;
    this.elections.push(election);
    this.trace(
      `ELECTION n${node.number} term ${node.currentTerm} last ${node.lastIndex}/${node.lastTerm} deadline ${node.electionDeadline}`,
    );
    for (const other of this.nodes) {
      if (other !== node) {
        this.send(node, other.number, {
          type: 'RV',
          lastIndex: node.lastIndex,
          lastTerm: node.lastTerm,
        });
      }
    }
  }
  becomeLeader(node: RaftNode): void {
    node.role = 'LEADER';
    node.knownLeader = node.number;
    for (const other of this.nodes) {
      if (other !== node) {
        node.next.set(other.number, node.lastIndex + 1);
        node.match.set(other.number, 0);
      }
    }
    node.log.push(makeEntry(node.currentTerm, 'NOOP', 0));
    node.stats.leaders++;
    node.election!.won = this.time;
    this.checker.leader(node);
    this.leaders.set(node.currentTerm, {
      node: node.number,
      elected: this.time,
      votes: new Set(node.votes),
      appended: 1,
      ended: null,
      reason: 'ACTIVE',
      commit: null,
    });
    this.trace(
      `LEADER n${node.number} term ${node.currentTerm} votes ${nodeSet(node.votes)} noop ${node.lastIndex}`,
    );
    this.appendAll(node);
    node.heartbeatDeadline = this.time + this.settings.heartbeat;
    node.quorumDeadline = this.time + this.settings.quorum;
    node.heard = new Set();
  }
  advanceCommit(node: RaftNode, last: number): void {
    this.checker.commit(node, node.commit + 1, last, this.time);
    node.commit = last;
    const first = node.applied + 1;
    for (let i = first; i <= last; i++) {
      const entry = node.entry(i);
      const result = applyCommand(node.store, entry.command);
      node.stats.applies++;
      this.checker.apply(i, entry, result);
    }
    node.applied = last;
    this.trace(`APPLY n${node.number} ${first}-${last}`);
  }
  commitCheck(node: RaftNode): void {
    for (let i = node.lastIndex; i > node.commit; i--) {
      if (node.term(i) !== node.currentTerm) break;
      let count = 1;
      for (const matched of node.match.values()) if (matched >= i) count++;
      if (this.majority(count)) {
        this.trace(`COMMIT n${node.number} ${node.commit + 1}-${i} term ${node.currentTerm}`);
        this.advanceCommit(node, i);
        break;
      }
    }
  }
  truncate(node: RaftNode, first: number): void {
    const removed = node.lastIndex - first + 1;
    node.stats.truncated += removed;
    this.checker.truncate(node, first);
    node.log.length = first - 1;
    this.trace(`TRUNCATE n${node.number} from ${first} removed ${removed}`);
  }
  requestVote(node: RaftNode, message: Extract<Message, { type: 'RV' }>): void {
    const { source, term } = message;
    let reason: string | null = null;
    if (term < node.currentTerm) reason = 'term';
    else if (node.votedFor !== null && node.votedFor !== source) reason = 'voted';
    else if (!node.candidateCurrent(message.lastIndex, message.lastTerm)) reason = 'log';
    if (reason === null) {
      node.votedFor = source;
      node.stats.votesGranted++;
      this.electionTimer(node);
      this.trace(
        `VOTE n${node.number} n${source} term ${node.currentTerm} deadline ${node.electionDeadline}`,
      );
    } else this.trace(`DENY n${node.number} n${source} term ${node.currentTerm} ${reason}`);
    this.send(node, source, { type: 'RVR', granted: reason === null });
  }
  voteResponse(node: RaftNode, message: Extract<Message, { type: 'RVR' }>): void {
    if (node.role !== 'CANDIDATE' || message.term !== node.currentTerm || !message.granted) return;
    node.votes.add(message.source);
    if (this.majority(node.votes.size)) this.becomeLeader(node);
  }
  appendRequest(node: RaftNode, message: Extract<Message, { type: 'AE' }>): void {
    const { source, term, prev, prevTerm, entries, commit } = message;
    if (term < node.currentTerm) {
      this.send(node, source, { type: 'AER', success: false, m: 0 });
      return;
    }
    if (node.role === 'CANDIDATE') {
      node.role = 'FOLLOWER';
      this.trace(`YIELD n${node.number} term ${node.currentTerm} n${source}`);
    }
    node.knownLeader = source;
    this.electionTimer(node);
    if (prev > node.lastIndex || node.term(prev) !== prevTerm) {
      node.stats.aeFail++;
      this.send(node, source, {
        type: 'AER',
        success: false,
        m: prev > node.lastIndex ? node.lastIndex : prev - 1,
      });
      return;
    }
    node.stats.aeOk++;
    for (let i = 0; i < entries.length; i++) {
      const index = prev + i + 1;
      const entry = entries[i];
      if (index <= node.lastIndex && node.term(index) !== entry.term) this.truncate(node, index);
      if (index > node.lastIndex) {
        node.log.push(copyEntry(entry));
        node.stats.appended++;
      }
    }
    const m = prev + entries.length;
    const committed = Math.min(commit, m);
    if (committed > node.commit) this.advanceCommit(node, committed);
    this.send(node, source, { type: 'AER', success: true, m });
  }
  appendResponse(node: RaftNode, message: Extract<Message, { type: 'AER' }>): void {
    if (node.role !== 'LEADER' || message.term !== node.currentTerm) return;
    const { source, success, m } = message;
    node.heard.add(source);
    if (success) {
      node.match.set(source, Math.max(node.match.get(source)!, m));
      node.next.set(source, Math.max(node.next.get(source)!, m + 1));
      this.commitCheck(node);
      if (
        node.transfer !== null &&
        node.transfer.target === source &&
        !node.transfer.sent &&
        node.match.get(source) === node.lastIndex
      ) {
        this.timeoutNow(node);
      } else if (node.next.get(source)! <= node.lastIndex) this.appendTo(node, source);
    } else {
      node.next.set(
        source,
        Math.max(node.match.get(source)! + 1, Math.min(node.next.get(source)! - 1, m + 1)),
      );
      this.trace(`BACKTRACK n${node.number} n${source} next ${node.next.get(source)}`);
      this.appendTo(node, source);
    }
  }
  receive(node: RaftNode, message: Message): void {
    if (message.term > node.currentTerm) {
      const role = node.role;
      this.trace(
        `TERM n${node.number} ${node.currentTerm}->${message.term} ${message.type} n${message.source} ${role}`,
      );
      if (role === 'LEADER') this.endLeadership(node, 'STEPDOWN');
      node.currentTerm = message.term;
      node.votedFor = null;
      node.knownLeader = null;
      node.role = 'FOLLOWER';
      if (role === 'LEADER') this.electionTimer(node);
    }
    switch (message.type) {
      case 'RV':
        this.requestVote(node, message);
        break;
      case 'RVR':
        this.voteResponse(node, message);
        break;
      case 'AE':
        this.appendRequest(node, message);
        break;
      case 'AER':
        this.appendResponse(node, message);
        break;
      case 'TN':
        if (message.term !== node.currentTerm || node.role !== 'FOLLOWER') {
          this.trace(`IGNORE n${node.number} TN n${message.source} term ${message.term}`);
        } else this.startElection(node, 'transfer');
    }
  }
  timeoutNow(node: RaftNode): void {
    const transfer = node.transfer!;
    this.trace(
      `TIMEOUTNOW n${node.number} n${transfer.target} term ${node.currentTerm} index ${node.lastIndex}`,
    );
    transfer.sent = true;
    this.send(node, transfer.target, { type: 'TN' });
  }
  transfer(source: number, target: number): void {
    const node = this.node(source);
    if (!node.up || node.role !== 'LEADER' || node.transfer !== null || source === target) {
      this.trace(`TRANSFER n${source} n${target} ignored`);
      return;
    }
    this.trace(
      `TRANSFER n${source} n${target} start match ${node.match.get(target)}/${node.lastIndex}`,
    );
    node.transfer = { target, sent: false, deadline: this.time + this.settings.electionMin };
    if (node.match.get(target) === node.lastIndex) this.timeoutNow(node);
    else this.appendTo(node, target);
  }
  control(event: Control): void {
    if (event.kind === 'CRASH') {
      const node = this.node(event.node);
      this.trace(`CRASH n${node.number} ${node.role} term ${node.currentTerm}`);
      if (node.role === 'LEADER') this.endLeadership(node, 'CRASH');
      node.up = false;
      node.resetVolatile();
    } else if (event.kind === 'RESTART') {
      const node = this.node(event.node);
      node.up = true;
      this.electionTimer(node);
      this.trace(
        `RESTART n${node.number} term ${node.currentTerm} length ${node.lastIndex} deadline ${node.electionDeadline}`,
      );
    } else if (event.kind === 'PARTITION') {
      this.network.partition(event.groups);
      this.trace(`PARTITION ${event.groups.map(nodeSet).join(' ')}`);
    } else if (event.kind === 'HEAL') {
      this.network.heal();
      this.trace('HEAL');
    } else if (event.kind === 'TRANSFER') this.transfer(event.source, event.target);
  }
  attempt(request: ClientRequest): void {
    request.attempts++;
    let destination = request.destination;
    let redirected = 0;
    while (true) {
      const node = this.node(destination);
      let reason: 'down' | 'transfer' | 'noleader';
      if (!node.up) reason = 'down';
      else if (node.role === 'LEADER') {
        if (node.transfer !== null) reason = 'transfer';
        else {
          node.log.push(makeEntry(node.currentTerm, request.command, request.number));
          this.leaders.get(node.currentTerm)!.appended++;
          request.accepted = { index: node.lastIndex, term: node.currentTerm };
          this.trace(
            `ACCEPT r${request.number} n${node.number} index ${node.lastIndex} term ${node.currentTerm}`,
          );
          return;
        }
      } else if (node.knownLeader === null || redirected >= this.nodes.length - 1) {
        reason = 'noleader';
      } else {
        this.trace(`REDIRECT r${request.number} n${node.number} n${node.knownLeader}`);
        request.redirects++;
        redirected++;
        destination = node.knownLeader;
        continue;
      }
      if (request.attempts < this.settings.attempts) {
        request.destination = (node.number % this.nodes.length) + 1;
        request.scheduled = this.time + this.settings.retry;
        this.trace(
          `REJECT r${request.number} n${node.number} ${reason} retry n${request.destination} at ${request.scheduled}`,
        );
      } else {
        request.abandoned = true;
        this.trace(`REJECT r${request.number} n${node.number} ${reason} giveup`);
      }
      return;
    }
  }
  timers(node: RaftNode): void {
    if (node.role === 'LEADER') {
      if (node.quorumDeadline === this.time) {
        if (!this.majority(node.heard.size + 1)) {
          this.trace(
            `STEPDOWN n${node.number} term ${node.currentTerm} heard ${nodeSet(node.heard)}`,
          );
          this.endLeadership(node, 'QUORUM');
          node.role = 'FOLLOWER';
          node.knownLeader = null;
          this.electionTimer(node);
          return;
        }
        node.heard = new Set();
        node.quorumDeadline = this.time + this.settings.quorum;
      }
      if (node.transfer !== null && node.transfer.deadline === this.time) {
        this.trace(`TRANSFER n${node.number} n${node.transfer.target} abort`);
        node.transfer = null;
      }
      if (node.heartbeatDeadline === this.time) {
        this.appendAll(node);
        node.heartbeatDeadline = this.time + this.settings.heartbeat;
      }
    } else if (node.electionDeadline === this.time) this.startElection(node, 'timeout');
  }
  endTick(): void {
    this.checker.matching(this.nodes);
    const active = this.nodes.filter((n) => n.up && n.role === 'LEADER');
    for (const node of active) node.stats.leaderTicks++;
    if (active.length > 0) {
      this.leaderTicks++;
      if (active.length >= 2) this.multiTicks++;
      if (this.gapStart !== null) {
        this.gaps.push([this.gapStart, this.time - 1]);
        this.gapStart = null;
      }
    } else if (this.gapStart === null) this.gapStart = this.time;
    if (this.time % this.settings.sample === 0) {
      this.timeline.push(
        `TIMELINE ${this.time} ${this.nodes.map((n) => `${n.up ? n.role[0] : 'D'}${n.currentTerm}`).join(' ')}`,
      );
    }
  }
  simulate(): void {
    for (const node of this.nodes) {
      this.electionTimer(node);
      this.trace(`START n${node.number} deadline ${node.electionDeadline}`);
    }
    for (this.time = 0; this.time <= this.settings.end; this.time++) {
      for (const event of this.controls.get(this.time) ?? []) this.control(event);
      for (const request of this.requests) {
        if (request.accepted === null && !request.abandoned && request.scheduled === this.time) {
          this.attempt(request);
        }
      }
      for (const message of this.network.take(this.time)) {
        const destination = this.node(message.destination);
        if (!destination.up) this.network.resolve(message, 'down');
        else if (this.network.separated(message.source, message.destination)) {
          this.network.resolve(message, 'partition');
        } else {
          this.network.resolve(message, 'delivered');
          this.receive(destination, message);
        }
      }
      for (const node of this.nodes) if (node.up) this.timers(node);
      this.endTick();
    }
    if (this.gapStart !== null) this.gaps.push([this.gapStart, this.settings.end]);
  }
}
function leaderReport(s: Simulation, maximumTerm: number): string[] {
  const lines: string[] = [];
  for (const e of s.elections) {
    lines.push(
      `ELECTION ${e.time} n${e.node} term ${e.term} trigger ${e.trigger} votes ${e.votes.size} ${e.won === null ? 'LOST' : `WON ${e.won}`}`,
    );
  }
  for (let term = 1; term <= maximumTerm; term++) {
    const elections = s.elections.filter((e) => e.term === term);
    const candidates = nodeSet(new Set(elections.map((e) => e.node)));
    const r = s.leaders.get(term);
    if (r === undefined) {
      lines.push(`TERM ${term} NONE candidates ${candidates}`);
      continue;
    }
    const commit = r.ended === null ? s.node(r.node).commit : r.commit;
    const started = elections[0].time;
    lines.push(
      `TERM ${term} LEADER n${r.node} elected ${r.elected} votes ${nodeSet(r.votes)} ended ${r.ended === null ? '-' : r.ended} ${r.reason} appended ${r.appended} commit ${commit} candidates ${candidates} started ${started} wait ${r.elected - started}`,
    );
  }
  for (const n of s.nodes) {
    lines.push(
      `NODE n${n.number} elections ${n.stats.elections} leader_terms ${n.stats.leaders} leader_ticks ${n.stats.leaderTicks} votes_granted ${n.stats.votesGranted}`,
    );
  }
  lines.push(...s.timeline);
  let longest = 0;
  for (const [first, last] of s.gaps) {
    const length = last - first + 1;
    longest = Math.max(longest, length);
    lines.push(`GAP ${first}-${last} length ${length}`);
  }
  lines.push(
    `SUMMARY terms ${maximumTerm} leaders ${s.leaders.size} elections ${s.elections.length} leader_ticks ${s.leaderTicks} multi_ticks ${s.multiTicks} ticks ${s.settings.end + 1} gaps ${s.gaps.length} longest ${longest}`,
  );
  return lines;
}
function logReport(s: Simulation): string[] {
  const lines: string[] = [];
  const committed = s.checker.committed.size;
  for (const n of s.nodes) {
    lines.push(
      `NODE n${n.number} ${n.up ? n.role : 'DOWN'} term ${n.currentTerm} voted ${n.votedFor === null ? '-' : `n${n.votedFor}`} commit ${n.commit} applied ${n.applied} length ${n.lastIndex}`,
    );
    n.log.forEach((e, i) =>
      lines.push(`${i + 1} ${e.term} ${e.command}${e.request === 0 ? '' : ` r${e.request}`}`),
    );
  }
  let prefix = 0;
  const shortest = Math.min(...s.nodes.map((n) => n.lastIndex));
  while (
    prefix < shortest &&
    s.nodes.every((n) => sameEntry(n.entry(prefix + 1), s.nodes[0].entry(prefix + 1)))
  ) {
    prefix++;
  }
  lines.push(`AGREE prefix ${prefix} committed ${committed}`);
  for (const n of s.nodes) {
    let common = 0;
    while (
      common < Math.min(n.lastIndex, committed) &&
      n.term(common + 1) === s.checker.committed.get(common + 1)!.term
    ) {
      common++;
    }
    const v = n.stats;
    lines.push(
      `DIFF n${n.number} common ${common} behind ${committed - common} extra ${n.lastIndex - common} ae_ok ${v.aeOk} ae_fail ${v.aeFail} appended ${v.appended} truncated ${v.truncated} applies ${v.applies}`,
    );
  }
  return lines;
}
type RequestStatus = 'COMMITTED' | 'UNCOMMITTED' | 'LOST' | 'FAILED' | 'WAITING';
interface RequestOutcome {
  request: ClientRequest;
  status: RequestStatus;
  latency: number | null;
  result: string | null;
}
function finalStates(s: Simulation) {
  const reference = new Map<string, number>();
  const wanted = new Set(s.nodes.map((n) => n.applied));
  const replays = new Map<number, Map<string, number>>([[0, new Map()]]);
  for (let i = 1; i <= s.checker.committed.size; i++) {
    applyCommand(reference, s.checker.applied.get(i)!.entry.command);
    if (wanted.has(i)) replays.set(i, new Map(reference));
  }
  const requests: RequestOutcome[] = s.requests.map((request) => {
    if (request.accepted === null) {
      return {
        request,
        status: request.abandoned ? 'FAILED' : 'WAITING',
        latency: null,
        result: null,
      };
    }
    const { index, term } = request.accepted;
    const record = s.checker.committed.get(index);
    if (record !== undefined && record.term === term) {
      return {
        request,
        status: 'COMMITTED',
        latency: record.time - request.time,
        result: s.checker.applied.get(index)!.result,
      };
    }
    return {
      request,
      status: s.nodes.some((n) => n.lastIndex >= index && n.term(index) === term)
        ? 'UNCOMMITTED'
        : 'LOST',
      latency: null,
      result: null,
    };
  });
  return { reference, replays, requests };
}
function stateReport(s: Simulation, states: ReturnType<typeof finalStates>): string[] {
  const lines: string[] = [];
  for (const n of s.nodes) {
    lines.push(
      `NODE n${n.number} ${n.up ? 'UP' : 'DOWN'} applied ${n.applied} keys ${n.store.size} replay ${sameState(n.store, states.replays.get(n.applied)!) ? 'match' : 'mismatch'}`,
    );
    for (const key of [...n.store.keys()].sort()) lines.push(`${key} ${n.store.get(key)}`);
  }
  const counts: Record<RequestStatus, number> = {
    COMMITTED: 0,
    UNCOMMITTED: 0,
    LOST: 0,
    FAILED: 0,
    WAITING: 0,
  };
  const latencies: number[] = [];
  const keys = new Map<string, { requests: number; committed: number }>();
  for (const outcome of states.requests) {
    const { request: r } = outcome;
    counts[outcome.status]++;
    let status: string = outcome.status;
    if (r.accepted !== null) {
      status += ` index ${r.accepted.index} term ${r.accepted.term}`;
      if (outcome.status === 'COMMITTED') {
        status += ` latency ${outcome.latency} result ${outcome.result}`;
        latencies.push(outcome.latency!);
      }
    } else if (outcome.status === 'WAITING') status += ` next ${r.scheduled}`;
    lines.push(
      `REQUEST r${r.number} at ${r.time} n${r.startNode} ${r.command} attempts ${r.attempts} redirects ${r.redirects} ${status}`,
    );
    const key = r.command.split(' ')[1];
    const tally = keys.get(key) ?? { requests: 0, committed: 0 };
    tally.requests++;
    if (outcome.status === 'COMMITTED') tally.committed++;
    keys.set(key, tally);
  }
  for (const key of [...keys.keys()].sort()) {
    const t = keys.get(key)!;
    lines.push(
      `KEY ${key} requests ${t.requests} committed ${t.committed} final ${states.reference.has(key) ? states.reference.get(key) : 'missing'}`,
    );
  }
  lines.push(
    `REQUESTS total ${states.requests.length} committed ${counts.COMMITTED} uncommitted ${counts.UNCOMMITTED} lost ${counts.LOST} failed ${counts.FAILED} waiting ${counts.WAITING}`,
    `LATENCY count ${latencies.length} total ${latencies.reduce((total, v) => total + v, 0)} min ${latencies.length ? Math.min(...latencies) : 0} max ${latencies.length ? Math.max(...latencies) : 0}`,
  );
  return lines;
}
function safetyReport(s: Simulation, maximumTerm: number): string[] {
  const lines = s.checker.lines(maximumTerm);
  const network = s.network;
  lines.push(`MESSAGES ${messageCounts(network.total)}`);
  for (const type of TYPES) lines.push(`TYPE ${type} ${messageCounts(network.types.get(type)!)}`);
  for (const link of network.links.values()) {
    const c = link.counts;
    lines.push(
      `LINK n${link.source}->n${link.destination} delay ${link.delay} loss ${link.loss} sent ${c.sent} delivered ${c.delivered} dropped ${c.partition + c.rule + c.loss + c.down}`,
    );
  }
  lines.push(
    `DRAWS ${s.random.draws}`,
    `RESULT ${s.checker.violations.every((v) => v === 0) ? 'SAFE' : 'UNSAFE'}`,
  );
  return lines;
}
function main(): void {
  const { settings, controls, requests } = read();
  const simulation = new Simulation(settings, controls, requests);
  simulation.simulate();
  const maximumTerm = Math.max(...simulation.nodes.map((n) => n.currentTerm));
  const states = finalStates(simulation);
  const reports: Record<string, string[]> = {
    'trace.txt': simulation.traceLines,
    'leaders.txt': leaderReport(simulation, maximumTerm),
    'logs.txt': logReport(simulation),
    'state.txt': stateReport(simulation, states),
    'safety.txt': safetyReport(simulation, maximumTerm),
  };
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
  }
}
main();
