import type {
  Layout, Section, Point, Signal, Route, Train, PathPart,
  Request, Params, UserEvent, ScheduleRequest, Punctuality, Stop
} from './types.ts';

import * as fs from 'node:fs';
import { readLayout, beyond } from './layout.ts';
import { Interlocking } from './interlocking.ts';
import { decideSignals } from './signals.ts';
import { readTrains, selectSpeed } from './trains.ts';
import { Safety } from './safety.ts';

const readLines = (path: string): string[] => fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
const trackOccupied = (section: Section): boolean => section.failed || section.occupants.length > 0;

function readInputs(): {layout: Layout; interlocking: Interlocking; trains: Train[]; requests: Map<number, ScheduleRequest[]>; params: Params; events: Map<number, UserEvent[]>} {
  const layout = readLayout('input/layout.txt'), interlocking = new Interlocking('input/routes.txt', layout);
  const plan = readTrains('input/trains.txt', layout, interlocking.byName), params: Partial<Params> = {}, events = new Map<number, UserEvent[]>();
  for (const line of readLines('input/params.txt')) {
    const [key, ...values] = line.split(' ');
    params[key] = key === 'SNAPSHOTS' ? new Set(values.map(Number)) : Number(values[0]);
  }
  for (const line of readLines('input/events.txt')) {
    const [when, kind, ...args] = line.split(' '), time = Number(when);
    if (!events.has(time)) events.set(time, []);
    events.get(time).push({ kind, args });
  }
  return { layout, interlocking, ...plan, params: params as Params, events };
}

function headEntry(train: Train): PathPart {
  for (let i = train.path.length - 1; i >= 0; i--) if (train.path[i].start < train.head) return train.path[i];
  return train.path[0];
}

function occupiedParts(train: Train): (PathPart & {lo: number; hi: number})[] {
  if (train.state !== 'RUNNING') return [];
  const parts = [], tail = train.head - train.length;
  for (const entry of train.path) {
    const end = entry.start + entry.section.length;
    if (entry.start < train.head && end > tail) {
      parts.push({ ...entry, lo: Math.max(tail, entry.start), hi: Math.min(train.head, end) });
    }
  }
  return parts;
}

class Simulation {
  layout: Layout;
  interlocking: Interlocking;
  routes: Route[];
  trains: Train[];
  planRequests: Map<number, ScheduleRequest[]>;
  events: Map<number, UserEvent[]>;
  params: Params;
  time: number;
  queue: Request[];
  requestCount: number;
  granted: number;
  dropped: number;
  eventLines: string[];
  snapshotLines: string[];
  safety: Safety;
  constructor(input: ReturnType<typeof readInputs>) {
    this.layout = input.layout; this.interlocking = input.interlocking; this.routes = input.interlocking.routes;
    this.trains = input.trains; this.planRequests = input.requests; this.events = input.events; this.params = input.params;
    this.time = 0; this.queue = []; this.requestCount = 0; this.granted = 0; this.dropped = 0;
    this.eventLines = []; this.snapshotLines = []; this.safety = new Safety();
  }
  log(content: string): void { this.eventLines.push(`${this.time} ${content}`); }
  startThrow(point: Point, position: string): void {
    point.moving = true; point.target = position; point.completion = this.time + this.params.THROW;
    this.log(`MOVE ${point.name} ${position} until ${point.completion}`);
  }
  completeThrows(): void {
    for (const point of this.layout.points) if (point.moving && point.completion === this.time) {
      point.position = point.target; point.moving = false; point.completion = null;
      this.log(`POINT ${point.name} ${point.position}`); point.stats.throws++;
    }
  }
  releaseApproaches(): void {
    for (const route of this.routes) if (route.state === 'APPROACH' && route.releaseTime === this.time) {
      this.interlocking.release(route); this.log('TIMEOUT ' + route.name);
    }
  }
  addRequest(route: Route, requester: string): void {
    const request = { number: ++this.requestCount, route, time: this.time, lastReason: null };
    this.queue.push(request); route.stats.requests++;
    this.log(`REQUEST q${request.number} ${route.name} ${requester}`);
  }
  reason(route: Route): string | null {
    if (route.state !== null) return 'busy';
    for (const other of route.conflicts) {
      if (other.state === 'LOCKED' || other.state === 'APPROACH') return 'conflict ' + other.name;
    }
    const opposite = other => other.direction !== route.direction;
    for (const section of route.sections) {
      if (trackOccupied(section)) return 'occupied ' + section.name;
      if (section.routeLock !== null || Array.from(section.overlapLocks).some(opposite)) return 'locked ' + section.name;
    }
    for (const section of route.overlap) {
      if (trackOccupied(section)) return 'occupied ' + section.name;
      if ((section.routeLock !== null && opposite(section.routeLock)) || Array.from(section.overlapLocks).some(opposite)) return 'locked ' + section.name;
    }
    for (const { point, position } of route.requirements) {
      if (point.locks.some(lock => lock.position !== position)) return 'point ' + point.name + ' locked';
      if ((!point.moving && point.position === position) || (point.moving && point.target === position)) continue;
      if (point.failed) return 'point ' + point.name + ' failed';
      if (point.moving) return 'point ' + point.name + ' moving';
      if (trackOccupied(point.common)) return 'point ' + point.name + ' occupied';
    }
    return null;
  }
  judgeRequests(): void {
    const remaining = [];
    for (const request of this.queue) {
      const route = request.route, reason = this.reason(route);
      if (reason !== null) {
        if (reason !== request.lastReason) {
          this.log(`WAIT q${request.number} ${route.name} ${reason}`); request.lastReason = reason;
        }
        remaining.push(request); continue;
      }
      this.interlocking.lock(route);
      const wait = this.time - request.time;
      this.log(`GRANT q${request.number} ${route.name} wait ${wait}`);
      this.granted++; route.stats.grants++; route.stats.wait += wait; route.stats.maxwait = Math.max(route.stats.maxwait, wait);
      for (const { point, position } of route.requirements) {
        if (!point.moving && point.position !== position) this.startThrow(point, position);
      }
    }
    this.queue = remaining;
  }
  cancel(route: Route): void {
    const pending = this.queue.filter(request => request.route === route);
    if (pending.length > 0) {
      for (const request of pending) { this.log(`DROP q${request.number} ${route.name}`); this.dropped++; }
      this.queue = this.queue.filter(request => request.route !== route);
      return;
    }
    if (route.state === 'LOCKED') {
      route.stats.cancels++;
      if (route.start.aspect !== 'RED' && trackOccupied(route.start.section)) {
        route.state = 'APPROACH'; route.releaseTime = this.time + route.approach;
        this.log(`CANCEL ${route.name} approach until ${route.releaseTime}`);
      } else { this.interlocking.release(route); this.log(`CANCEL ${route.name} released`); }
    } else this.log(`CANCEL ${route.name} ${route.state === null ? 'none' : 'refused'}`);
  }
  executeEvent(event: UserEvent): void {
    const { kind, args } = event;
    if (kind === 'REQUEST') this.addRequest(this.interlocking.byName.get(args[0]), 'OPERATOR');
    else if (kind === 'CANCEL') this.cancel(this.interlocking.byName.get(args[0]));
    else if (kind === 'THROW') {
      const point = this.layout.pointByName.get(args[0]), position = args[1];
      const result = point.locks.length > 0 ? 'locked' : point.failed ? 'failed' : point.moving ? 'moving' :
        trackOccupied(point.common) ? 'occupied' : point.position === position ? 'none' : 'start';
      this.log(`THROW ${point.name} ${position} ${result}`);
      if (result === 'start') this.startThrow(point, position);
    } else if (kind === 'TCFAIL' || kind === 'TCFIX') {
      const section = this.layout.sectionByName.get(args[0]);
      section.failed = kind === 'TCFAIL'; this.log(kind + ' ' + section.name);
    } else {
      const point = this.layout.pointByName.get(args[0]);
      point.failed = kind === 'POINTFAIL'; this.log(kind + ' ' + point.name);
      if (point.moving) {
        if (point.failed) point.completion = null;
        else this.startThrow(point, point.target!);
      }
    }
  }
  setSignals(): void {
    const aspects = decideSignals(this.layout.signals, this.routes, trackOccupied);
    this.layout.signals.forEach((signal, i) => {
      if (signal.aspect !== aspects[i]) {
        signal.aspect = aspects[i]; this.log(`SIGNAL ${signal.name} ${signal.aspect}`);
      }
    });
  }
  reverse(train: Train, stop: Stop): void {
    const head = headEntry(train), end = head.start + head.section.length;
    const parts = occupiedParts(train);
    train.path = parts.reverse().map(part => ({ section: part.section, start: end - (part.start + part.section.length) }));
    train.head = end - (train.head - train.length);
    train.direction = train.direction === 'UP' ? 'DOWN' : 'UP';
    this.log(`REVERSE ${train.name} ${stop.section.name}`);
  }
  limitDistance(train: Train): number | null {
    if (train.crossed !== null) return null;
    const entry = headEntry(train), stop = train.stops[train.nextStop];
    let section = entry.section, distance = entry.start + section.length - train.head;
    while (true) {
      const signal = section.signals[train.direction!];
      if (signal && signal.aspect === 'RED') return distance;
      if (stop && stop.section === section) return distance;
      const next = beyond(section, train.direction!);
      if (next.kind === 'boundary') return null;
      if (next.kind === 'buffer' || next.kind === 'impassable') return distance;
      section = next.section; distance += section.length;
    }
  }
  passSignal(train: Train, signal: Signal): void {
    const route = this.routes.find(candidate => candidate.start === signal && (candidate.state === 'LOCKED' || candidate.state === 'APPROACH'));
    this.log(`PASS ${train.name} ${signal.name} ${signal.aspect} ${route ? route.name : '-'}`);
    signal.stats.passes++; train.stats.passes++;
    if (route) { route.state = 'USED'; route.stats.uses++; }
    if (signal.aspect === 'RED') {
      this.log(`SPAD ${train.name} ${signal.name}`); train.emergency = true;
    }
    this.safety.passing(this.time, train, signal);
  }
  move(train: Train, speed: number): void {
    let remaining = speed, entry = headEntry(train);
    while (remaining > 0) {
      if (train.crossed !== null) { train.head += remaining; break; }
      const end = entry.start + entry.section.length;
      if (train.head + remaining <= end) { train.head += remaining; break; }
      remaining -= end - train.head; train.head = end;
      const signal = entry.section.signals[train.direction!];
      if (signal) this.passSignal(train, signal);
      if (train.pendingDeparture !== null && train.pendingDeparture.section === entry.section) {
        this.log(`DEPART ${train.name} ${entry.section.name}`);
        train.pendingDeparture.departure = this.time; train.pendingDeparture = null;
      }
      const next = beyond(entry.section, train.direction!);
      if (next.kind === 'boundary') train.crossed = { boundary: next, coordinate: end };
      else { entry = { section: next.section, start: end }; train.path.push(entry); }
    }
  }
  runTrain(train: Train, entered: Set<import('./types.ts').Feature>): void {
    if (train.state === 'EXITED') return;
    if (train.state === 'WAITING') {
      if (this.time < train.scheduledEntry || trackOccupied(train.entry.section) || entered.has(train.entry)) return;
      entered.add(train.entry); train.state = 'RUNNING'; train.actualEntry = this.time;
      train.direction = train.entry.end === 'L' ? 'UP' : 'DOWN';
      train.path = [{ section: train.entry.section, start: 0 }]; train.head = 0; train.speed = train.entrySpeed;
      this.log(`ENTER ${train.name} ${train.entry.name}`);
    }
    if (train.dwelling) {
      const stop = train.stops[train.nextStop];
      if (this.time < stop.arrival + stop.dwell || this.time < stop.scheduledDeparture) return;
      train.dwelling = false; train.pendingDeparture = stop; train.nextStop++;
      if (stop.turn) this.reverse(train, stop);
    }
    const oldSpeed = train.speed, speed = selectSpeed(train, this.limitDistance(train));
    this.move(train, speed);
    train.speed = speed; train.stats.distance += speed; train.stats.maxspeed = Math.max(train.stats.maxspeed, speed);
    if (speed === 0) train.emergency = false;
    const head = headEntry(train), stop = train.stops[train.nextStop];
    let arrived = false;
    if (stop && speed === 0 && head.section === stop.section && train.head === head.start + head.section.length) {
      train.dwelling = true; stop.arrival = this.time; arrived = true;
      this.log(`ARRIVE ${train.name} ${stop.section.name}`);
    }
    if (speed === 0 && !arrived) {
      train.stats.standing++;
      if (oldSpeed > 0) this.log(`HOLD ${train.name} ${head.section.name}`);
    }
    if (train.crossed !== null && train.head - train.length >= train.crossed.coordinate) {
      train.state = 'EXITED'; train.actualExit = this.time;
      this.log(`EXIT ${train.name} ${train.crossed.boundary.name}`);
    }
  }
  recomputeOccupancy(): void {
    for (const section of this.layout.sections) section.occupants = [];
    for (const train of this.trains) for (const part of occupiedParts(train)) {
      if (!part.section.occupants.includes(train)) part.section.occupants.push(train);
    }
  }
  releaseSections(): void {
    for (const route of this.routes) if (route.state === 'USED') {
      for (const section of route.sections) {
        if (section.routeLock === route && trackOccupied(section)) route.passed.add(section);
      }
      for (const section of route.sections) {
        if (section.routeLock !== route) continue;
        if (!route.passed.has(section) || trackOccupied(section)) break;
        this.interlocking.unlockSection(route, section); this.log(`RELEASE ${route.name} ${section.name}`);
      }
      if (route.sections.every(section => section.routeLock !== route)) {
        this.interlocking.release(route); this.log('DONE ' + route.name);
      } else if (route.overlap.length > 0 && route.overlapLocked) {
        route.overlapCounter = trackOccupied(route.sections[route.sections.length - 1]) ? route.overlapCounter + 1 : 0;
        if (route.overlapCounter === this.params.OVERLAP) {
          this.interlocking.unlockOverlap(route); this.log('OVERLAP ' + route.name);
        }
      }
    }
  }
  statistics(): void {
    for (const route of this.routes) if (route.state !== null) route.stats.locked++;
    for (const point of this.layout.points) {
      if (point.locks.length > 0) point.stats.locked++;
      if (point.moving) point.stats.moving++;
    }
    for (const section of this.layout.sections) {
      if (trackOccupied(section)) section.stats.occupied++;
      if (section.routeLock !== null || section.overlapLocks.size > 0) section.stats.locked++;
      for (const train of section.occupants) section.stats.trains.add(train);
    }
    for (const signal of this.layout.signals) signal.stats[signal.aspect]++;
  }
  simulate(): void {
    for (this.time = 0; this.time <= this.params.END; this.time++) {
      this.completeThrows();
      this.releaseApproaches();
      for (const request of this.planRequests.get(this.time) || []) this.addRequest(request.route, request.train.name);
      for (const event of this.events.get(this.time) || []) this.executeEvent(event);
      this.judgeRequests();
      this.setSignals();
      const entered = new Set<import('./types.ts').Feature>();
      for (const train of this.trains) this.runTrain(train, entered);
      this.recomputeOccupancy();
      this.releaseSections();
      this.safety.step(this.time, this.layout, this.routes);
      this.statistics();
      if (this.params.SNAPSHOTS.has(this.time)) this.snapshotLines.push(...snapshot(this));
    }
  }
}

function snapshot(simulation: Simulation): string[] {
  const { layout, trains, routes } = simulation;
  let height = 0, width = 0;
  const include = (row, col) => { height = Math.max(height, row + 1); width = Math.max(width, col + 1); };
  for (const section of layout.sections) include(section.row, section.col2);
  for (const item of [...layout.points, ...layout.signals, ...layout.buffers]) include(item.row, item.col);
  for (const label of layout.labels) include(label.row, label.col + label.text.length - 1);
  const grid = Array.from({ length: height }, () => Array(width).fill(' '));
  for (const label of layout.labels) {
    for (let i = 0; i < label.text.length; i++) grid[label.row][label.col + i] = label.text[i];
  }
  for (const section of layout.sections) {
    const character = section.failed ? '#' : section.routeLock !== null ? '=' : section.overlapLocks.size > 0 ? '~' : '-';
    for (let col = section.col1; col <= section.col2; col++) grid[section.row][col] = character;
  }
  for (const train of trains) for (const part of occupiedParts(train)) {
    const { section, start, lo, hi } = part, length = section.length, columns = section.col2 - section.col1 + 1;
    const first = train.direction === 'UP' ? lo - start : length - (hi - start);
    const last = train.direction === 'UP' ? hi - start : length - (lo - start);
    for (let j = 0; j < columns; j++) {
      if (first * columns < (j + 1) * length && last * columns > j * length) {
        const previous = grid[section.row][section.col1 + j];
        grid[section.row][section.col1 + j] = previous === '*' || (previous >= 'a' && previous <= 'z') ? '*' : train.symbol;
      }
    }
  }
  for (const buffer of layout.buffers) grid[buffer.row][buffer.col] = '|';
  for (const point of layout.points) grid[point.row][point.col] = point.moving || point.failed ? '?' : point.position;
  for (const signal of layout.signals) grid[signal.row][signal.col] = ({ RED: 'X', YELLOW: 'Y', GREEN: 'G' } as Record<string, string>)[signal.aspect];
  const lines = ['SNAPSHOT ' + simulation.time, ...grid.map(row => row.join('').replace(/ +$/, ''))];
  for (const train of trains) if (train.state === 'RUNNING') {
    const sections = occupiedParts(train).map(part => part.section.name).join(',');
    lines.push(`TRAIN ${train.symbol} ${train.name} ${train.direction} ${train.speed} ${sections}`);
  }
  const set = routes.filter(route => route.state !== null).map(route => route.name + '/' + route.state);
  lines.push('ROUTES ' + (set.length > 0 ? set.join(' ') : '-'));
  return lines;
}

function trainLog(trains: Train[]): {lines: string[]; punctuality: Punctuality} {
  const lines = ['train,location,scheduled,actual,delay'];
  const punctuality = { onTime: 0, late: 0, missing: 0, totalDelay: 0, maxDelay: 0 };
  const record = (train: Train, location: string, scheduled: number, actual: number | null): void => {
    if (actual === null) { lines.push(`${train.name},${location},${scheduled},-,-`); punctuality.missing++; }
    else {
      const delay = actual - scheduled;
      lines.push(`${train.name},${location},${scheduled},${actual},${delay}`);
      if (delay <= 0) punctuality.onTime++;
      else { punctuality.late++; punctuality.totalDelay += delay; }
      punctuality.maxDelay = Math.max(punctuality.maxDelay, delay);
    }
  };
  for (const train of trains) {
    record(train, 'enter:' + train.entry.name, train.scheduledEntry, train.actualEntry);
    for (const stop of train.stops) {
      record(train, 'arr:' + stop.section.name, stop.scheduledArrival, stop.arrival);
      record(train, 'dep:' + stop.section.name, stop.scheduledDeparture, stop.departure);
    }
    record(train, 'exit:' + train.exit!.name, train.scheduledExit!, train.actualExit);
  }
  return { lines, punctuality };
}

function summaryReport(simulation: Simulation, punctuality: Punctuality): string[] {
  const lines = [];
  for (const route of simulation.routes) {
    const stats = route.stats;
    lines.push(`ROUTE ${route.name} ${route.start.name}-${route.finish.name} requests ${stats.requests} grants ${stats.grants} uses ${stats.uses} cancels ${stats.cancels} wait ${stats.wait} maxwait ${stats.maxwait} locked ${stats.locked}`);
  }
  for (const point of simulation.layout.points) {
    const stats = point.stats;
    lines.push(`POINT ${point.name} throws ${stats.throws} locked ${stats.locked} moving ${stats.moving} final ${point.moving || point.failed ? '?' : point.position}`);
  }
  for (const section of simulation.layout.sections) {
    const stats = section.stats;
    lines.push(`SECTION ${section.name} occupied ${stats.occupied} locked ${stats.locked} trains ${stats.trains.size}`);
  }
  for (const signal of simulation.layout.signals) {
    const stats = signal.stats;
    lines.push(`SIGNAL ${signal.name} red ${stats.RED} yellow ${stats.YELLOW} green ${stats.GREEN} passes ${stats.passes}`);
  }
  const states: Record<string, number> = { WAITING: 0, RUNNING: 0, EXITED: 0 };
  for (const train of simulation.trains) {
    const stats = train.stats; states[train.state]++;
    lines.push(`TRAIN ${train.name} ${train.symbol} ${train.state} distance ${stats.distance} maxspeed ${stats.maxspeed} standing ${stats.standing} passes ${stats.passes}`);
  }
  lines.push(`TRAINS total ${simulation.trains.length} exited ${states.EXITED} running ${states.RUNNING} waiting ${states.WAITING}`,
    `PUNCTUALITY on_time ${punctuality.onTime} late ${punctuality.late} missing ${punctuality.missing} total_delay ${punctuality.totalDelay} max_delay ${punctuality.maxDelay}`,
    `REQUESTS total ${simulation.requestCount} granted ${simulation.granted} dropped ${simulation.dropped} pending ${simulation.queue.length}`);
  return lines;
}

function main(): void {
  const simulation = new Simulation(readInputs());
  simulation.simulate();
  const log = trainLog(simulation.trains);
  const reports: [string, string[]][] = [
    ['events.txt', simulation.eventLines], ['snapshots.txt', simulation.snapshotLines], ['train_log.csv', log.lines],
    ['safety.txt', simulation.safety.report()], ['summary.txt', summaryReport(simulation, log.punctuality)],
  ];
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of reports) fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

main();
