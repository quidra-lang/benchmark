import { prefixValue, prefixCompare, contains, role, direction, readTopology, connectingLink } from './topology.ts';
import { NO_EXPORT, parseCommunities, editCommunities, readPolicies, appliedRule } from './policy.ts';
import { sameSequence, originated, learned, attributesEqual, routesEqual, selectBest } from './decision.ts';
import { MessageQueue, readEvents, readParams } from './simulator.ts';
import { pathText, attributeText, routeText, writeReports } from './report.ts';
import type {
  Attribute, Route, LearnedRoute, AutonomousSystem, Session, Origin, Delivery,
  SimEvent, Policies, Topology, Parameters, ForwardingTrace, PathResult,
  Period, RingRecord, ActiveTrace, BestChange
} from './types.ts';

const prefixOrder = (values: Iterable<string>): string[] => Array.from(values).sort(prefixCompare);
const compressed = (values: number[]): number[] => values.filter((value, i) => i === 0 || value !== values[i - 1]);
const attributeState = (value: Attribute | null | undefined): unknown => value == null ? null : [value.path, value.origin, value.med, value.communities];
const tableState = (table: Map<string, Attribute>): unknown[] => prefixOrder(table.keys()).map(prefix => [prefix, attributeState(table.get(prefix))]);

class Simulation {
  topology: Topology;
  policies: Policies;
  events: SimEvent[];
  params: Parameters;
  messages: MessageQueue;
  time: number;
  logLines: string[];
  periods: Period[];
  changedPrefixes: Set<string>;
  current: Period | null;
  rings: RingRecord[];
  activeRings: Map<string, RingRecord>;
  traceRecords: ActiveTrace[];
  activeTraces: Map<number, ActiveTrace>;
  endTime: number;
  constructor() {
    this.topology = readTopology('input/topology.txt'); this.policies = readPolicies('input/policies.txt');
    this.events = readEvents('input/events.txt'); this.params = readParams('input/params.txt');
    this.messages = new MessageQueue(); this.time = 0; this.logLines = []; this.periods = [];
    this.changedPrefixes = new Set<string>(); this.current = null; this.rings = []; this.activeRings = new Map<string, RingRecord>();
    this.traceRecords = []; this.activeTraces = new Map<number, ActiveTrace>(); this.endTime = 0;
  }
  log(content: string): void { this.logLines.push(this.time + ' ' + content); }
  importEvaluation(session: Session, prefix: string, attribute: Attribute): {rule: Policies['rules'][number] | null; route: LearnedRoute | null} {
    const rule = appliedRule(this.policies, 'IMPORT', session, prefix, attribute.path, attribute.communities);
    if (rule && rule.DENY) return { rule, route: null };
    const preference = rule && rule.LOCALPREF !== undefined ? rule.LOCALPREF : this.params.preferences[role(session.link, session.owner.asn)];
    const adjusted = { ...attribute, med: rule && rule.MED !== undefined ? rule.MED : attribute.med,
      communities: editCommunities(attribute.communities, rule) };
    return { rule, route: learned(adjusted, preference, session.link) };
  }
  candidates(as: AutonomousSystem, prefix: string): LearnedRoute[] {
    const routes: LearnedRoute[] = [];
    for (const session of as.sessions) if (session.input.has(prefix)) {
      const evaluation = this.importEvaluation(session, prefix, session.input.get(prefix)!);
      if (evaluation.route) routes.push(evaluation.route);
    }
    return routes;
  }
  redecide(as: AutonomousSystem, prefix: string): void {
    let next: Route | null = as.origination.get(prefix) || null;
    if (next === null) {
      const candidates = this.candidates(as, prefix);
      if (candidates.length) next = selectBest(candidates, this.topology.ases).route;
    }
    if (routesEqual(as.rib.get(prefix), next)) return;
    if (next === null) as.rib.delete(prefix);
    else as.rib.set(prefix, next);
    this.log(`BEST ${as.asn} ${prefix} ${routeText(next)}`);
    as.changes++; this.current!.bestChanges++; this.changedPrefixes.add(prefix);
    const key = as.asn + '|' + prefix;
    this.current!.exploration.set(key, (this.current!.exploration.get(key) || 0) + 1);
    this.current!.bestLines.push({ time: this.time, asn: as.asn, prefix, route: next });
    for (const session of as.sessions) if (session.link.up) {
      session.pending.add(prefix);
      if (session.timer === null) this.processPending(session);
    }
  }
  advertised(session: Session, prefix: string): {content: Attribute | null; rule: Policies['rules'][number] | null} {
    const asn = session.owner.asn, route = session.owner.rib.get(prefix);
    if (!route || (!route.local && route.path[0] === session.neighbor) || route.communities.includes(NO_EXPORT)) return { content: null, rule: null };
    const rule = appliedRule(this.policies, 'EXPORT', session, prefix, route.path, route.communities);
    if (rule && rule.DENY) return { content: null, rule };
    if (!(rule && rule.ALLOW) && !route.local && role(route.link, asn) !== 'customer' && role(session.link, asn) !== 'customer') {
      return { content: null, rule };
    }
    const prepend = rule && rule.PREPEND !== undefined ? rule.PREPEND : 0;
    const content = { path: Array(1 + prepend).fill(asn).concat(route.path), origin: route.origin,
      med: rule && rule.MED !== undefined ? rule.MED : 0, communities: editCommunities(route.communities, rule) };
    return { content, rule };
  }
  processPending(session: Session): void {
    let sent = 0;
    for (const prefix of prefixOrder(session.pending)) {
      const { content, rule } = this.advertised(session, prefix);
      if (attributesEqual(session.output.get(prefix), content)) continue;
      if (content === null) session.output.delete(prefix);
      else session.output.set(prefix, content);
      const message = this.messages.send(this.time, session, prefix, content);
      this.log(`SEND #${message.serial} ${message.sender}->${message.receiver} ${message.link.name} ${prefix} ` +
        (content === null ? 'WITHDRAW' : 'ANNOUNCE ' + attributeText(content)));
      sent++; session.sent++; this.current!.updates++;
      if (content === null) this.current!.withdrawals++;
      if (rule) rule.hits++;
    }
    session.pending.clear();
    session.timer = sent > 0 && session.link.mrai > 0 ? this.time + session.link.mrai : null;
  }
  receive(message: Delivery): void {
    const { prefix, content } = message, session = message.link.sessions.get(message.receiver)!;
    let result;
    if (content === null) { session.input.delete(prefix); result = 'WITHDRAW'; }
    else if (content.path.includes(message.receiver)) { session.input.delete(prefix); result = 'ANNOUNCE loop'; }
    else {
      session.input.set(prefix, content);
      const evaluation = this.importEvaluation(session, prefix, content);
      if (evaluation.rule) evaluation.rule.hits++;
      result = evaluation.route ? 'ANNOUNCE accept' + (evaluation.rule ? ' ' + evaluation.rule.name : '') : 'ANNOUNCE deny ' + evaluation.rule!.name;
    }
    session.received++;
    this.log(`RECV #${message.serial} ${message.sender}->${message.receiver} ${message.link.name} ${prefix} ${result}`);
    this.redecide(session.owner, prefix);
  }
  originate(asn: number, prefix: string, origin: Origin, communities: string[]): void {
    const as = this.topology.ases.get(asn)!;
    as.origination.set(prefix, originated(origin, parseCommunities(communities)));
    this.redecide(as, prefix);
  }
  executeEvent(event: SimEvent): void {
    this.log(`EVENT ${event.number} ${event.text}`);
    const fields = event.fields;
    if (event.kind === 'INITIAL') {
      for (const item of this.topology.initial) this.originate(item.asn, item.prefix, item.origin, item.communities);
    } else if (event.kind === 'ANNOUNCE') this.originate(Number(fields[1]), fields[2], fields[3] as Origin, fields.slice(4));
    else if (event.kind === 'WITHDRAW') {
      const as = this.topology.ases.get(Number(fields[1]))!;
      as.origination.delete(fields[2]); this.redecide(as, fields[2]);
    } else if (event.kind === 'LINK_DOWN' || event.kind === 'LINK_UP') {
      const link = this.topology.linkByName.get(fields[2])!;
      const sessions = Array.from(link.sessions.values()).sort((a, b) => a.owner.asn - b.owner.asn);
      link.up = event.kind === 'LINK_UP';
      if (!link.up) {
        link.downs++;
        for (const message of this.messages.removeLink(link)) {
          this.log(`DROP #${message.serial} ${message.sender}->${message.receiver} ${link.name} ${message.prefix}`); this.current!.drops++;
        }
        const remembered = sessions.map(session => prefixOrder(session.input.keys()));
        for (const session of sessions) {
          session.input.clear(); session.output.clear(); session.pending.clear(); session.timer = null;
        }
        sessions.forEach((session, i) => { for (const prefix of remembered[i]) this.redecide(session.owner, prefix); });
      } else for (const session of sessions) {
        session.pending = new Set(session.owner.rib.keys()); this.processPending(session);
      }
    } else {
      const rule = this.policies.byName.get(fields[2])!, as = this.topology.ases.get(rule.asn)!;
      rule.active = event.kind === 'POLICY_ON';
      if (rule.direction === 'IMPORT') {
        const prefixes = new Set<string>();
        for (const session of as.sessions) for (const prefix of session.input.keys()) prefixes.add(prefix);
        for (const prefix of prefixOrder(prefixes)) this.redecide(as, prefix);
      } else for (const session of as.sessions) if (session.link.up) {
        for (const prefix of as.rib.keys()) session.pending.add(prefix);
        for (const prefix of session.output.keys()) session.pending.add(prefix);
        if (session.timer === null) this.processPending(session);
      }
    }
  }
  globalState(): string {
    const sessions = this.topology.sessions.map(session => [tableState(session.input), tableState(session.output),
      prefixOrder(session.pending), session.timer === null ? null : session.timer - this.time]);
    const messages = this.messages.ordered().map(message => [message.arrival - this.time, message.receiver, message.sender,
      message.link.number, message.prefix, attributeState(message.content)]);
    return JSON.stringify([sessions, messages]);
  }
  checkDivergence(): void {
    const period = this.current!;
    if (period.first !== null || period.deliveries > this.params.cap) return;
    const state = this.globalState();
    if (period.states.has(state)) {
      period.first = period.states.get(state)!; period.repeat = this.time;
      period.cycle = period.bestLines.filter(line => line.time > period.first! && line.time <= period.repeat!);
    } else period.states.set(state, this.time);
  }
  tracePath(source: number, address: number): PathResult {
    const visits: number[] = [source], hops: PathResult['hops'] = [];
    let current = source, count = 0;
    while (true) {
      const as = this.topology.ases.get(current)!;
      let match: string | null = null;
      for (const prefix of as.rib.keys()) {
        const value = prefixValue(prefix);
        if (contains(value, address) && (match === null || value.length > prefixValue(match).length)) match = prefix;
      }
      if (match === null) return { result: hops.length ? 'BLACKHOLE' : 'UNREACHABLE', visits, hops, count };
      const route = as.rib.get(match)!;
      if (route.local) {
        hops.push({ asn: current, prefix: match, link: null });
        return { result: 'DELIVERED', visits, hops, count, arrival: current };
      }
      hops.push({ asn: current, prefix: match, link: route.link }); count++;
      const next = route.path[0], repeated = visits.includes(next);
      visits.push(next);
      if (repeated) return { result: 'LOOP', visits, hops, count };
      current = next;
    }
  }
  forwardingLoops(prefix: string): number[][] {
    const arrows = new Map<number, number>(), visited = new Set<number>(), loops: number[][] = [];
    for (const as of this.topology.asOrder) {
      const route = as.rib.get(prefix)!;
      if (route && !route.local) arrows.set(as.asn, route.path[0]);
    }
    for (const as of this.topology.asOrder) {
      if (visited.has(as.asn)) continue;
      const path: number[] = [], positions = new Map<number, number>();
      let current = as.asn;
      while (current !== undefined && !visited.has(current) && !positions.has(current)) {
        positions.set(current, path.length); path.push(current); current = arrows.get(current);
      }
      if (current !== undefined && positions.has(current)) {
        const cycle = path.slice(positions.get(current)!), minimum = Math.min(...cycle), start = cycle.indexOf(minimum);
        loops.push(cycle.slice(start).concat(cycle.slice(0, start)));
      }
      for (const node of path) visited.add(node);
    }
    return loops.sort((a, b) => a[0] - b[0]);
  }
  checkForwarding(): void {
    for (const prefix of prefixOrder(this.changedPrefixes)) {
      const loops = this.forwardingLoops(prefix), present = new Map(loops.map(loop => [prefix + '|' + pathText(loop), loop]));
      for (const [key, record] of this.activeRings) if (record.prefix === prefix && !present.has(key)) {
        record.end = this.time; this.activeRings.delete(key);
      }
      for (const [key, loop] of present) if (!this.activeRings.has(key)) {
        const record: RingRecord = { prefix, loop, start: this.time, end: null };
        this.rings.push(record); this.activeRings.set(key, record);
      }
    }
    for (const trace of this.params.traces) {
      const path = this.tracePath(trace.asn, trace.value);
      const status = path.result === 'LOOP' || path.result === 'BLACKHOLE' ? JSON.stringify([path.result, path.visits]) : null;
      const previous = this.activeTraces.get(trace.index);
      if (previous && previous.status !== status) { previous.end = this.time; this.activeTraces.delete(trace.index); }
      if (status !== null && !this.activeTraces.has(trace.index)) {
        const record: ActiveTrace = { trace, status, result: path.result, visits: path.visits, start: this.time, end: null };
        this.traceRecords.push(record); this.activeTraces.set(trace.index, record);
      }
    }
  }
  quiet(): boolean { return this.messages.length === 0 && this.topology.sessions.every(session => session.pending.size === 0); }
  run(): void {
    for (let index = 0; index < this.events.length; index++) {
      const event = this.events[index], last = index + 1 === this.events.length;
      const end = last ? null : this.events[index + 1].time - 1;
      const starting = this.topology.asOrder.map(as => new Map(as.rib));
      const period: Period = { event, convergence: 0, updates: 0, withdrawals: 0, drops: 0, bestChanges: 0, routesChanged: 0,
        exploration: new Map(), bestLines: [], deliveries: 0, states: new Map(), first: null, repeat: null, cycle: [],
        status: '', maxExploration: 0 };
      this.current = period; this.time = event.time; this.changedPrefixes = new Set<string>(); this.executeEvent(event);
      while (true) {
        const deliveries = this.messages.takeTime(this.time);
        for (const message of deliveries) this.receive(message);
        if (deliveries.length) period.convergence = this.time - event.time;
        for (const session of this.topology.sessions) if (session.timer === this.time) {
          session.timer = null;
          if (session.pending.size) this.processPending(session);
        }
        if (this.changedPrefixes.size) this.checkForwarding();
        if (deliveries.length) { period.deliveries++; this.checkDivergence(); }
        if (last ? this.quiet() || period.first !== null || period.deliveries >= this.params.cap : this.time === end) break;
        let next = end === null ? Infinity : end;
        if (this.messages.nextTime !== null) next = Math.min(next, this.messages.nextTime);
        for (const session of this.topology.sessions) if (session.timer !== null) next = Math.min(next, session.timer);
        this.time = next; this.changedPrefixes = new Set();
      }
      period.status = period.first !== null ? 'DIVERGENT' : this.quiet() ? 'CONVERGED' : last ? 'CAPPED' : 'UNSETTLED';
      this.topology.asOrder.forEach((as, i) => {
        const prefixes = new Set([...starting[i].keys(), ...as.rib.keys()]);
        for (const prefix of prefixes) if (!routesEqual(starting[i].get(prefix), as.rib.get(prefix))) period.routesChanged++;
      });
      period.maxExploration = Math.max(0, ...period.exploration.values());
      period.states.clear(); this.periods.push(period);
    }
    this.endTime = this.time;
  }
}

function valleyViolation(pattern: string): number | null {
  let position = 0;
  while (pattern[position] === 'U') position++;
  if (pattern[position] === 'P') position++;
  while (pattern[position] === 'D') position++;
  return position === pattern.length ? null : position;
}

function convergenceReport(simulation: Simulation): string[] {
  const lines = ['event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration'];
  for (const period of simulation.periods) {
    const event = period.event;
    lines.push([event.number, event.time, event.kind, period.status, period.convergence, period.updates, period.withdrawals,
      period.drops, period.bestChanges, period.routesChanged, period.maxExploration].join(','));
  }
  return lines;
}

function ribsReport(simulation: Simulation): string[] {
  const lines = [], topology = simulation.topology;
  for (const as of topology.asOrder) {
    const local = Array.from(as.rib.values()).filter(route => route.local).length;
    const sent = as.sessions.reduce((sum, session) => sum + session.sent, 0);
    const received = as.sessions.reduce((sum, session) => sum + session.received, 0);
    lines.push(`AS ${as.asn} routes ${as.rib.size} local ${local} sent ${sent} received ${received} changes ${as.changes}`);
    for (const session of as.sessions) {
      let accepted = 0;
      for (const [prefix, attribute] of session.input) if (simulation.importEvaluation(session, prefix, attribute).route) accepted++;
      lines.push(`SESSION ${session.link.name} ${session.neighbor} ${role(session.link, as.asn)} ${session.link.up ? 'UP' : 'DOWN'} in ${session.input.size} accepted ${accepted} out ${session.output.size} sent ${session.sent} received ${session.received} flaps ${session.link.downs}`);
    }
    for (const prefix of prefixOrder(as.rib.keys())) {
      const route = as.rib.get(prefix)!, candidates = simulation.candidates(as, prefix);
      const reason = route.local ? '' : ' reason ' + selectBest(candidates, topology.ases).reason;
      lines.push(`${prefix} ${routeText(route)} candidates ${candidates.length}${reason}`);
      let alternatives = candidates.filter(candidate => !routesEqual(candidate, route));
      while (alternatives.length) {
        const best = selectBest(alternatives, topology.ases).route;
        lines.push('ALT ' + routeText(best)); alternatives = alternatives.filter(candidate => candidate !== best);
      }
    }
  }
  return lines;
}

function pathsReport(simulation: Simulation): string[] {
  const lines = [], topology = simulation.topology;
  for (const trace of simulation.params.traces) {
    const path = simulation.tracePath(trace.asn, trace.value);
    lines.push(`TRACE ${trace.asn} ${trace.address} ${path.result} hops ${path.count}`);
    for (const hop of path.hops) {
      const ending = hop.link ? `next ${hop.link.sessions.get(hop.asn)!.neighbor} link ${hop.link.name}` : 'LOCAL';
      lines.push(`HOP ${hop.asn} ${hop.prefix} ${ending}`);
    }
    const last = path.visits[path.visits.length - 1];
    if (path.result === 'LOOP') lines.push(`HOP ${last} REVISIT`);
    else if (path.result === 'BLACKHOLE' || path.result === 'UNREACHABLE') lines.push(`HOP ${last} NOROUTE`);
    if (path.hops.length === 0) lines.push('CONTROL NONE');
    else {
      const route = topology.ases.get(trace.asn)!.rib.get(path.hops[0].prefix)!;
      const match = path.result === 'DELIVERED' && sameSequence(compressed(route.path), path.visits.slice(1));
      lines.push(`CONTROL ${route.local ? 'LOCAL' : pathText(route.path)} ${match ? 'MATCH' : 'MISMATCH'}`);
    }
    if (path.count > 0) {
      const pattern = path.hops.filter(hop => hop.link).map(hop => direction(hop.link, hop.asn)).join('');
      lines.push(`PATTERN ${pattern} ${valleyViolation(pattern) === null ? 'VALLEYFREE' : 'VALLEY'}`);
    }
  }
  const prefixes = new Set();
  for (const as of topology.asOrder) for (const prefix of as.origination.keys()) prefixes.add(prefix);
  const ordered = prefixOrder(prefixes);
  lines.push(('PREFIXES ' + ordered.join(',')).trimEnd());
  for (const as of topology.asOrder) {
    const symbols = ordered.map(prefix => {
      const path = simulation.tracePath(as.asn, prefixValue(prefix).value);
      if (path.result === 'DELIVERED') {
        if (path.count === 0) return '*';
        return topology.ases.get(path.arrival!)!.origination.has(prefix) ? '+' : 'X';
      }
      return ({ LOOP: 'L', BLACKHOLE: 'B', UNREACHABLE: 'U', DELIVERED: '+' } as Record<string, string>)[path.result];
    }).join('');
    lines.push((`REACH ${as.asn} ` + symbols).trimEnd());
  }
  return lines;
}

function auditReport(simulation: Simulation): string[] {
  const lines = [], topology = simulation.topology;
  let loops = 0, blackholes = 0, routes = 0, valleys = 0, divergent = 0;
  const traceRecords = simulation.traceRecords.slice().sort((a, b) => a.start - b.start || a.trace.index - b.trace.index);
  for (const record of traceRecords) {
    const { trace, result, visits, start, end } = record;
    const at = result === 'BLACKHOLE' ? ' at ' + visits[visits.length - 1] : '';
    lines.push(`${result} ${trace.asn} ${trace.address} from ${start} to ${end === null ? 'END' : end}${at} path ${pathText(visits)}`);
    if (result === 'LOOP') loops++; else blackholes++;
  }
  const rings = simulation.rings.slice().sort((a, b) => a.start - b.start || prefixCompare(a.prefix, b.prefix) || a.loop[0] - b.loop[0]);
  for (const ring of rings) lines.push(`RING ${ring.prefix} from ${ring.start} to ${ring.end === null ? 'END' : ring.end} path ${pathText(ring.loop)}`);
  for (const as of topology.asOrder) for (const prefix of prefixOrder(as.rib.keys())) {
    const route = as.rib.get(prefix)!;
    if (route.local) continue;
    routes++;
    const path = compressed([as.asn, ...route.path]);
    const pattern = path.slice(0, -1).map((asn, i) => direction(connectingLink(topology, asn, path[i + 1]), asn)).join('');
    const violation = valleyViolation(pattern);
    if (violation !== null) {
      lines.push(`VALLEY ${as.asn} ${prefix} path ${pathText(route.path)} pattern ${pattern} leaker ${path[violation]}`); valleys++;
    }
  }
  for (const rule of simulation.policies.rules) lines.push(`RULE ${rule.name} ${rule.direction} ${rule.active ? 'ON' : 'OFF'} hits ${rule.hits}`);
  for (const period of simulation.periods) if (period.first !== null) {
    divergent++;
    lines.push(`DIVERGENT event ${period.event.number} first ${period.first} repeat ${period.repeat} period ${period.repeat! - period.first}`);
    const pairs = new Map<string, {asn: number; prefix: string; count: number}>();
    for (const item of period.cycle) {
      lines.push(`CYCLE ${item.time} ${item.asn} ${item.prefix} ${routeText(item.route)}`);
      const key = item.asn + '|' + item.prefix;
      if (!pairs.has(key)) pairs.set(key, { asn: item.asn, prefix: item.prefix, count: 0 });
      pairs.get(key)!.count++;
    }
    const ordered = Array.from(pairs.values()).sort((a, b) => a.asn - b.asn || prefixCompare(a.prefix, b.prefix));
    for (const pair of ordered) lines.push(`OSCILLATE ${pair.asn} ${pair.prefix} changes ${pair.count}`);
  }
  lines.push(`SUMMARY loops ${loops} blackholes ${blackholes} rings ${rings.length} routes ${routes} valleys ${valleys} divergent ${divergent} end ${simulation.endTime}`);
  return lines;
}

function main(): void {
  const simulation = new Simulation();
  simulation.run();
  writeReports([
    ['updates.txt', simulation.logLines], ['convergence.csv', convergenceReport(simulation)], ['ribs.txt', ribsReport(simulation)],
    ['paths.txt', pathsReport(simulation)], ['audit.txt', auditReport(simulation)],
  ]);
}

main();
