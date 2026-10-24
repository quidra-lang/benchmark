import { mkdirSync } from 'node:fs';
import * as io from './config_io.ts';
import { Cache } from './cache.ts';
import * as protocol from './protocol.ts';
import { Bus } from './bus.ts';
import * as stats from './stats.ts';
import type {
  AccessEvent, AccessRecord, BusType, CacheLine, Config, Counters, LineData, MissClass,
  RegionReport, ReuseResult, Scenario, StaticLine, TraceEvent, Transaction, ValidatedTrace, WordData,
} from './types.ts';

const DISTANCE_LABELS = ['1', '2-4', '5-16', '17-64', '65-256', '257+'];
const LATENCY_LABELS = ['1', '2-9', '10-29', '30-99', '100-299', '300+'];
const category = (value: number, ends: number[]): number => { const index = ends.findIndex(end => value <= end); return index < 0 ? ends.length : index; };
const typeCounts = (): Record<string, number> => Object.fromEntries(protocol.TYPES.map(type => [type, 0]));
const countTypes = (counts: Record<string, number>): string => protocol.TYPES.map(type => `${type} ${counts[type]}`).join(' ');
const sumTypes = (counts: Record<string, number>): number => protocol.TYPES.reduce((sum, type) => sum + counts[type], 0);

function validateTrace(lines: string[], config: Config): ValidatedTrace {
  const events: TraceEvent[] = [], rejected: ValidatedTrace['rejected'] = [], byCore: TraceEvent[][] = Array.from({ length: config.cores }, () => []);
  let previousCycle = 0;
  lines.forEach((line, index) => {
    const fields = line.split(' ');
    let reason = null;
    if ((fields.length !== 3 && fields.length !== 4) || fields.includes('')) reason = 'fields';
    else if (!io.decimalInteger(fields[0]) || fields[0].length > 7) reason = 'cycle';
    else if (!io.decimalInteger(fields[1]) || Number(fields[1]) >= config.cores) reason = 'core';
    else if (!['R', 'W', 'FENCE'].includes(fields[2]) || (fields[2] === 'FENCE' ? fields.length !== 3 : fields.length !== 4)) reason = 'op';
    else if (fields[2] !== 'FENCE' && (!io.hexDigits(fields[3]) || Number.parseInt(fields[3], 16) % 4 !== 0 || Number.parseInt(fields[3], 16) > 0x7fffffff)) reason = 'address';
    else if (Number(fields[0]) < previousCycle) reason = 'order';
    if (reason !== null) { rejected.push({ line: index + 1, reason }); return; }
    const base = { number: events.length + 1, cycle: Number(fields[0]), core: Number(fields[1]) };
    const event: TraceEvent = fields[2] === 'FENCE'
      ? { ...base, operation: 'FENCE' }
      : {
        ...base,
        operation: fields[2] as AccessEvent['operation'],
        address: Number.parseInt(fields[3], 16),
        block: Math.floor(Number.parseInt(fields[3], 16) / config.line),
        word: Math.floor((Number.parseInt(fields[3], 16) % config.line) / 4),
        distance: null,
      };
    previousCycle = event.cycle; events.push(event); byCore[event.core].push(event);
  });
  return { events, rejected, byCore, lineCount: lines.length };
}

function optimalMisses(accesses: AccessEvent[], capacity: number): number {
  const next: number[] = Array(accesses.length), future = new Map<number, number>();
  for (let i = accesses.length - 1; i >= 0; i--) {
    next[i] = future.has(accesses[i].block) ? future.get(accesses[i].block)! : accesses.length;
    future.set(accesses[i].block, i);
  }
  const resident = new Map<number, number>(), heap: [number, number][] = [];
  const later = (a: [number, number], b: [number, number]): boolean => a[0] > b[0] || (a[0] === b[0] && a[1] < b[1]);
  const push = (item: [number, number]): void => {
    heap.push(item);
    let index = heap.length - 1;
    while (index > 0) {
      const parent = Math.floor((index - 1) / 2);
      if (!later(heap[index], heap[parent])) break;
      [heap[index], heap[parent]] = [heap[parent], heap[index]]; index = parent;
    }
  };
  const pop = (): [number, number] => {
    const first = heap[0], last = heap.pop()!;
    if (heap.length === 0) return first;
    heap[0] = last;
    let index = 0;
    while (true) {
      const left = 2 * index + 1, right = left + 1;
      let best = index;
      if (left < heap.length && later(heap[left], heap[best])) best = left;
      if (right < heap.length && later(heap[right], heap[best])) best = right;
      if (best === index) break;
      [heap[index], heap[best]] = [heap[best], heap[index]]; index = best;
    }
    return first;
  };
  let misses = 0;
  accesses.forEach((access, index) => {
    if (!resident.has(access.block)) {
      misses++;
      if (resident.size === capacity) {
        let victim: [number, number];
        do { victim = pop(); } while (!resident.has(victim[1]) || resident.get(victim[1]) !== victim[0]);
        resident.delete(victim[1]);
      }
    }
    resident.set(access.block, next[index]); push([next[index], access.block]);
  });
  return misses;
}

function reuseAnalysis(byCore: TraceEvent[][], capacity: number): ReuseResult[] {
  const capacities = [capacity / 4, capacity / 2, capacity, 2 * capacity, 4 * capacity];
  return byCore.map(events => {
    const accesses = events.filter((event): event is AccessEvent => event.operation !== 'FENCE'), previous = new Map<number, number>();
    const tree = Array(accesses.length + 1).fill(0), histogram = Array(6).fill(0), misses = Array(5).fill(0);
    const prefix = (position: number): number => { let sum = 0; for (let i = position; i > 0; i -= i & -i) sum += tree[i]; return sum; };
    const add = (position: number, value: number): void => { for (let i = position; i < tree.length; i += i & -i) tree[i] += value; };
    let cold = 0;
    accesses.forEach((access, index) => {
      const old = previous.get(access.block);
      if (old === undefined) { access.distance = null; cold++; }
      else {
        access.distance = prefix(index) - prefix(old - 1);
        histogram[category(access.distance, [1, 4, 16, 64, 256])]++; add(old, -1);
      }
      capacities.forEach((limit, i) => { if (access.distance === null || access.distance > limit) misses[i]++; });
      add(index + 1, 1); previous.set(access.block, index + 1);
    });
    return { accesses: accesses.length, lines: previous.size, histogram, cold, capacities, misses, opt: optimalMisses(accesses, capacity) };
  });
}

function staticSharing(events: TraceEvent[]): Map<number, StaticLine> {
  const lines = new Map<number, StaticLine>();
  for (const event of events) {
    if (event.operation === 'FENCE') continue;
    if (!lines.has(event.block)) lines.set(event.block, { cores: new Set<number>(), writers: new Set<number>(), words: new Map<number, {readers: Set<number>; writers: Set<number>}>(), reads: 0, writes: 0, shared: false, true: false });
    const line = lines.get(event.block); line.cores.add(event.core);
    if (!line.words.has(event.word)) line.words.set(event.word, { readers: new Set<number>(), writers: new Set<number>() });
    const word = line.words.get(event.word);
    if (event.operation === 'W') { line.writes++; line.writers.add(event.core); word.writers.add(event.core); }
    else { line.reads++; word.readers.add(event.core); }
  }
  for (const line of lines.values()) {
    line.shared = line.cores.size >= 2 && line.writers.size > 0;
    line.true = Array.from(line.words.values()).some(word => word.writers.size > 0 && new Set([...word.readers, ...word.writers]).size >= 2);
  }
  return lines;
}

class Simulation {
  config: Config;
  scenario: Scenario;
  byCore: TraceEvent[][];
  primary: boolean;
  l1: Cache[];
  l2: Cache;
  bus: Bus;
  cores: Counters[];
  ready: number[];
  writeComplete: number[];
  invalidations: Map<number, Set<number>>[];
  l2Stats: {lookups: number; hits: number; misses: number; flushes: number; writebacks: number; evictions: number; dirtyEvictions: number};
  snoopHits: number;
  fanout: number[];
  histogram: number[];
  lineData: Map<number, LineData>;
  wordData: Map<string, WordData>;
  communication: number[][];
  accesses: AccessRecord[];
  watchLines: string[];
  total!: Counters;
  constructor(config: Config, scenario: Scenario, byCore: TraceEvent[][]) {
    this.config = config; this.scenario = scenario; this.byCore = byCore; this.primary = scenario.name === config.primary;
    this.l1 = Array.from({ length: config.cores }, () => new Cache(config.l1, scenario.l1Policy));
    this.l2 = new Cache(config.l2, scenario.l2Policy); this.bus = new Bus(config.latencies[3]);
    this.cores = Array.from({ length: config.cores }, () => stats.create());
    this.ready = Array(config.cores).fill(0); this.writeComplete = Array(config.cores).fill(0);
    this.invalidations = Array.from({ length: config.cores }, () => new Map<number, Set<number>>());
    this.l2Stats = { lookups: 0, hits: 0, misses: 0, flushes: 0, writebacks: 0, evictions: 0, dirtyEvictions: 0 };
    this.snoopHits = 0; this.fanout = Array(config.cores).fill(0); this.histogram = Array(6).fill(0);
    this.lineData = new Map<number, LineData>(); this.wordData = new Map<string, WordData>(); this.communication = Array.from({ length: config.cores }, () => Array(config.cores).fill(0));
    this.accesses = []; this.watchLines = [];
  }
  line(block: number): LineData {
    if (!this.lineData.has(block)) this.lineData.set(block, { bus: typeCounts(), cores: new Set<number>(), misses: 0,
      coherence: 0, invalidations: 0, trueSharing: 0, falseSharing: 0, handoffs: 0, lastWriter: null });
    return this.lineData.get(block);
  }
  assign(cycle: number, core: number, type: BusType, block: number): Transaction {
    const transaction = this.bus.assign(cycle, core, type, block), line = this.line(block);
    this.cores[core].bus[type]++; line.bus[type]++; line.cores.add(core);
    return transaction;
  }
  watchedState(block: number): string[] { return [...this.l1.map(cache => cache.state(block)), this.l2.state(block)]; }
  sharing(event: AccessEvent): void {
    if (!this.primary) return;
    const line = this.line(event.block), key = `${event.block}/${event.word}`;
    if (!this.wordData.has(key)) this.wordData.set(key, { writer: null, readers: new Set<number>() });
    const word = this.wordData.get(key);
    if (event.operation === 'W') {
      if (line.lastWriter !== null && line.lastWriter !== event.core) line.handoffs++;
      line.lastWriter = event.core; word.writer = event.core; word.readers = new Set<number>();
    } else if (word.writer !== null && word.writer !== event.core && !word.readers.has(event.core)) {
      this.communication[word.writer][event.core]++; word.readers.add(event.core);
    }
  }
  transact(event: AccessEvent, type: BusType, requestCycle: number): {completion: number; service: string} {
    const { core, block, word } = event, transaction = this.assign(requestCycle, core, type, block);
    let flushed = false;
    for (let other = 0; other < this.config.cores; other++) {
      if (other === core) continue;
      const state = this.l1[other].state(block);
      if (state === 'I') continue;
      const changed = protocol.snoop(this.scenario.protocol, state, type);
      transaction.snoops.push(`c${other}:${state}>${changed.state}`);
      if (changed.state === 'I') {
        this.l1[other].remove(block); this.cores[core].invalidationsSent++; this.cores[other].invalidationsReceived++;
        this.invalidations[other].set(block, new Set([word])); transaction.invalidations++;
      } else this.l1[other].setState(block, changed.state);
      if (changed.supply) { transaction.supplier = other; this.cores[other].supplied++; }
      if (changed.flush) flushed = true;
    }
    this.snoopHits += transaction.snoops.length; this.line(block).invalidations += transaction.invalidations;
    if (type !== 'BusRd') this.fanout[transaction.invalidations]++;
    if (type !== 'BusUpgr') {
      this.l2Stats.lookups++;
      const found = this.l2.lookup(block);
      if (found !== null) { transaction.l2 = 'hit'; this.l2Stats.hits++; this.l2.touch(found); }
      else {
        transaction.l2 = 'miss'; this.l2Stats.misses++;
        const evicted = this.l2.fill(block, 'C');
        if (evicted !== null) {
          this.l2Stats.evictions++;
          const eviction = { block: evicted.block, copies: [] as string[], dirty: evicted.state === 'D' };
          for (let other = 0; other < this.config.cores; other++) {
            const state = this.l1[other].state(evicted.block);
            if (state === 'I') continue;
            eviction.copies.push(`c${other}:${state}`);
            if (protocol.DIRTY.has(state)) eviction.dirty = true;
            this.l1[other].remove(evicted.block); this.cores[other].backInvalidations++;
          }
          if (eviction.dirty) this.l2Stats.dirtyEvictions++;
          transaction.eviction = eviction;
        }
      }
      if (flushed || type === 'BusWr') this.l2.setState(block, 'D');
    }
    if (flushed) this.l2Stats.flushes++;
    const [, l2Latency, memoryLatency, busLatency] = this.config.latencies;
    let completion = transaction.start + busLatency, service;
    if (type === 'BusUpgr') service = 'upgrade';
    else if (type !== 'BusWr' && transaction.supplier !== null) service = 'cache';
    else {
      completion += l2Latency;
      if (transaction.l2 === 'miss') completion += memoryLatency;
      service = type === 'BusWr' ? 'through' : transaction.l2 === 'hit' ? 'l2' : 'memory';
    }
    return { completion, service };
  }
  access(event: AccessEvent, issue: number): void {
    const { core, block, operation, word } = event, cache = this.l1[core], counter = this.cores[core];
    const before = this.primary ? this.config.watches.map(watched => this.watchedState(watched)) : [];
    const old = cache.state(block), transition = protocol.request(this.scenario.protocol, old, operation), hit = old !== 'I';
    const line = this.line(block);
    counter.accesses++; counter[operation === 'R' ? 'reads' : 'writes']++;
    let classification: MissClass | null = null;
    if (hit) { counter.hits++; cache.touch(cache.lookup(block)!); }
    else {
      counter.misses++; line.misses++;
      if (event.distance === null) classification = 'compulsory';
      else if (this.invalidations[core].has(block)) {
        classification = 'coherence'; line.coherence++;
        const sharing: 'trueSharing' | 'falseSharing' = this.invalidations[core].get(block)!.has(word) ? 'trueSharing' : 'falseSharing';
        counter[sharing]++; line[sharing]++;
      } else classification = event.distance > this.config.capacity ? 'capacity' : 'conflict';
      counter[classification as MissClass]++;
    }
    if (operation === 'W') {
      for (let other = 0; other < this.config.cores; other++) {
        if (other !== core && this.invalidations[other].has(block)) this.invalidations[other].get(block)!.add(word);
      }
    }
    this.sharing(event);
    if (transition.state === 'ES') transition.state = this.l1.some((other, i) => i !== core && other.state(block) !== 'I') ? 'S' : 'E';
    let completion = issue + this.config.latencies[0], service = 'l1';
    if (transition.type !== null) ({ completion, service } = this.transact(event, transition.type, completion));
    if (old !== 'I') cache.setState(block, transition.state);
    else if (transition.state !== 'I') {
      const evicted = cache.fill(block, transition.state); this.invalidations[core].delete(block);
      if (evicted !== null && protocol.DIRTY.has(evicted.state)) {
        this.assign(this.bus.free, core, 'WB', evicted.block); this.l2Stats.writebacks++;
        this.l2.touch(this.l2.lookup(evicted.block)!); this.l2.setState(evicted.block, 'D');
      }
    }
    const latency = completion - issue;
    counter.latency += latency; counter[operation === 'R' ? 'readLatency' : 'writeLatency'] += latency;
    counter.service[service]++; counter.finish = Math.max(counter.finish, completion);
    this.histogram[category(latency, [1, 9, 29, 99, 299])]++;
    if (operation === 'R') this.ready[core] = completion;
    else { this.ready[core] = issue + this.config.latencies[0]; this.writeComplete[core] = Math.max(this.writeComplete[core], completion); }
    this.accesses.push({ ...event, issue, latency, service, hit, classification });
    if (this.primary) this.config.watches.forEach((watched, i) => {
      const after = this.watchedState(watched);
      if (block === watched || after.some((state, k) => state !== before[i][k])) {
        this.watchLines.push(`${event.number} ${issue} c${core} ${operation} ${io.hex(event.address)} line ${io.hex(watched * this.config.line)} ${after.slice(0, -1).map((state, k) => `c${k}:${state}`).join(' ')} L2:${after[after.length - 1]}`);
      }
    });
  }
  simulate(): Simulation {
    const positions = Array(this.config.cores).fill(0);
    while (true) {
      let selected = -1, issue = null;
      for (let core = 0; core < this.config.cores; core++) {
        if (positions[core] >= this.byCore[core].length) continue;
        const candidate = Math.max(this.byCore[core][positions[core]].cycle, this.ready[core]);
        if (issue === null || candidate < issue) { selected = core; issue = candidate; }
      }
      if (selected < 0) break;
      const event = this.byCore[selected][positions[selected]++];
      if (event.operation === 'FENCE') {
        const completion = Math.max(issue!, this.writeComplete[selected]), counter = this.cores[selected];
        counter.fences++; counter.fenceStall += completion - issue!; counter.finish = Math.max(counter.finish, completion);
        this.ready[selected] = completion;
      } else this.access(event, issue!);
    }
    this.total = stats.total(this.cores);
    return this;
  }
}

function scenarioReport(simulation: Simulation): string[] {
  const { config, scenario, total, bus, l2Stats } = simulation, transactions = bus.transactions.length;
  const lines = [`scenario ${scenario.name} ${scenario.protocol} ${scenario.l1Policy} ${scenario.l2Policy}`];
  simulation.cores.forEach((core, i) => lines.push(...stats.lines(`c${i}`, core)));
  lines.push(...stats.lines('total', total));
  lines.push(`l2 lookups ${l2Stats.lookups} hits ${l2Stats.hits} misses ${l2Stats.misses} flushes ${l2Stats.flushes} writebacks ${l2Stats.writebacks} evictions ${l2Stats.evictions} dirty_evictions ${l2Stats.dirtyEvictions}`,
    `bus transactions ${transactions} busy ${bus.busy} wait ${bus.wait} utilization ${stats.decimal(100 * bus.busy, total.finish)}`,
    `traffic command_bytes ${8 * transactions} data_bytes ${config.line * (total.bus.BusRd + total.bus.BusRdX + total.bus.WB) + 4 * total.bus.BusWr} memory_bytes ${config.line * (l2Stats.misses + l2Stats.dirtyEvictions)}`,
    `snoops probes ${(config.cores - 1) * (transactions - total.bus.WB)} hits ${simulation.snoopHits} fanout ${stats.ranges(Array.from({ length: config.cores }, (_, i) => String(i)), simulation.fanout)}`,
    `latencies reads ${total.readLatency} writes ${total.writeLatency} histogram ${stats.ranges(LATENCY_LABELS, simulation.histogram)}`);
  return lines;
}

function hotReport(simulation: Simulation): string[] {
  const { config } = simulation, lines = [`hot ${config.primary}`];
  const hot = Array.from(simulation.lineData).filter(([, data]) => sumTypes(data.bus) > 0)
    .sort((a, b) => sumTypes(b[1].bus) - sumTypes(a[1].bus) || a[0] - b[0]).slice(0, config.top);
  hot.forEach(([block, data], i) => lines.push(`${i + 1} ${io.hex(block * config.line)} transactions ${sumTypes(data.bus)} ${countTypes(data.bus)} misses ${data.misses} coherence ${data.coherence} invalidations ${data.invalidations} cores ${stats.coreString(data.cores)}`));
  return lines;
}

function intervalReport(simulation: Simulation): string[] {
  const { config } = simulation, width = config.interval;
  const intervals = Array.from({ length: Math.floor(simulation.total.finish / width) + 1 }, () => ({ accesses: Array(config.cores).fill(0), misses: 0, transactions: 0, busy: 0 }));
  for (const access of simulation.accesses) {
    const interval = intervals[Math.floor(access.issue / width)];
    interval.accesses[access.core]++;
    if (!access.hit) interval.misses++;
  }
  for (const transaction of simulation.bus.transactions) {
    const first = Math.floor(transaction.start / width), last = Math.floor((transaction.start + config.latencies[3] - 1) / width);
    if (first < intervals.length) intervals[first].transactions++;
    for (let index = first; index <= last && index < intervals.length; index++) {
      intervals[index].busy += Math.min(transaction.start + config.latencies[3], (index + 1) * width) - Math.max(transaction.start, index * width);
    }
  }
  return [`intervals ${config.primary} ${width}`, ...intervals.map((interval, i) =>
    `${i} ${i * width}-${(i + 1) * width - 1} accesses ${interval.accesses.join(' ')} misses ${interval.misses} transactions ${interval.transactions} busy ${interval.busy} utilization ${stats.decimal(100 * interval.busy, width)}`)];
}

function regionReport(simulation: Simulation): string[] {
  const { config } = simulation;
  const emptyStats = () => ({ accesses: 0, reads: 0, writes: 0, hits: 0, compulsory: 0,
    capacity: 0, conflict: 0, coherence: 0, transactions: 0, latency: 0 });
  const regions: RegionReport[] = config.regions.map(region => ({ ...region, ...emptyStats() }));
  regions.push({ name: 'other', ...emptyStats() });
  const locate = (address: number): RegionReport =>
    regions.find(region => region.name !== 'other' && region.first !== undefined &&
      region.last !== undefined && region.first <= address && address <= region.last)! || regions[regions.length - 1];
  for (const access of simulation.accesses) {
    const region = locate(access.address);
    region.accesses++; region[access.operation === 'R' ? 'reads' : 'writes']++;
    if (access.hit) region.hits++; else region[access.classification!]++;
    region.latency += access.latency;
  }
  for (const transaction of simulation.bus.transactions) locate(transaction.block * config.line).transactions++;
  return [`regions ${config.primary}`, ...regions.map(region =>
    `${region.name} accesses ${region.accesses} reads ${region.reads} writes ${region.writes} hits ${region.hits} compulsory ${region.compulsory} capacity ${region.capacity} conflict ${region.conflict} coherence ${region.coherence} transactions ${region.transactions} latency ${region.latency} amat ${region.accesses === 0 ? '-' : `${stats.fraction(region.latency, region.accesses)} ${stats.decimal(region.latency, region.accesses)}`}`)];
}

function statisticsReport(config: Config, trace: ValidatedTrace, reuse: ReuseResult[], simulations: Simulation[], primary: Simulation): string[] {
  const parts = [], first = [`trace lines ${trace.lineCount} accepted ${trace.events.length} rejected ${trace.rejected.length}`];
  for (const rejected of trace.rejected) first.push(`reject line ${rejected.line} ${rejected.reason}`);
  first.push(`geometry cores ${config.cores} line ${config.line} l1 ${config.l1.size} ${config.l1.ways} sets ${config.l1.sets} l2 ${config.l2.size} ${config.l2.ways} sets ${config.l2.sets}`,
    `latency l1 ${config.latencies[0]} l2 ${config.latencies[1]} memory ${config.latencies[2]} bus ${config.latencies[3]}`);
  parts.push(first);
  const reuseLines = [];
  reuse.forEach((result, core) => reuseLines.push(`reuse c${core} accesses ${result.accesses} lines ${result.lines} distance ${stats.ranges(DISTANCE_LABELS, result.histogram)} cold ${result.cold}`,
    `mrc c${core} lru ${result.capacities.map((capacity, i) => `${capacity}:${result.misses[i]}`).join(' ')} opt ${config.capacity}:${result.opt}`));
  parts.push(reuseLines);
  for (const simulation of simulations) parts.push(scenarioReport(simulation));
  const ranking = simulations.slice().sort((a, b) => a.total.finish - b.total.finish || a.bus.transactions.length - b.bus.transactions.length || a.scenario.order - b.scenario.order);
  parts.push(['ranking', ...ranking.map((simulation, i) => `${i + 1} ${simulation.scenario.name} finish ${simulation.total.finish} transactions ${simulation.bus.transactions.length} amat ${stats.fraction(simulation.total.latency, simulation.total.accesses)} ${stats.decimal(simulation.total.latency, simulation.total.accesses)}`)]);
  parts.push(hotReport(primary), intervalReport(primary));
  const slowest = primary.accesses.slice().sort((a, b) => b.latency - a.latency || a.number - b.number).slice(0, config.top);
  parts.push([`slowest ${config.primary}`, ...slowest.map((access, i) => `${i + 1} event ${access.number} cycle ${access.issue} c${access.core} ${access.operation} ${io.hex(access.address)} latency ${access.latency} service ${access.service}`)]);
  parts.push(regionReport(primary));
  return parts.flatMap((part, i) => i === 0 ? part : ['', ...part]);
}

function sharingReport(config: Config, sharing: Map<number, StaticLine>, primary: Simulation): string[] {
  const lines = [], blocks = Array.from(sharing.keys()).filter(block => sharing.get(block)!.shared).sort((a, b) => a - b);
  let trueLines = 0, trueMisses = 0, falseMisses = 0;
  for (const block of blocks) {
    const line = sharing.get(block)!, dynamic = primary.lineData.get(block)!;
    if (line.true) trueLines++;
    trueMisses += dynamic.trueSharing; falseMisses += dynamic.falseSharing;
    const words = Array.from(line.words.keys()).sort((a, b) => a - b).map(word =>
      `w${word}=${stats.coreString(line.words.get(word)!.readers)}/${stats.coreString(line.words.get(word)!.writers)}`).join(' ');
    lines.push(`${io.hex(block * config.line)} ${line.true ? 'true' : 'false'} cores ${stats.coreString(line.cores)} writers ${stats.coreString(line.writers)} reads ${line.reads} writes ${line.writes} handoffs ${dynamic.handoffs} coherence ${dynamic.trueSharing + dynamic.falseSharing} true ${dynamic.trueSharing} false ${dynamic.falseSharing} words ${words}`);
  }
  lines.push(`lines ${blocks.length} true_lines ${trueLines} false_lines ${blocks.length - trueLines} coherence ${trueMisses + falseMisses} true ${trueMisses} false ${falseMisses}`, 'communication');
  primary.communication.forEach((counts, core) => lines.push(`c${core} ${counts.join(' ')}`));
  return lines;
}

function finalStateReport(simulation: Simulation): string[] {
  const lines = [], { config } = simulation;
  const cacheLines = (cache: Cache, label: string): CacheLine[] => {
    cache.sets.forEach((set, index) => {
      const ways = set.ways.map(line => line === null ? '-' : `${io.hex(line.block * config.line)}:${line.state}`).join(' ');
      lines.push(`${label} ${index} ${ways} ${cache.policy.toLowerCase()} ${cache.order(index)} fills ${set.fills} evictions ${set.evictions}`);
    });
    return cache.sets.flatMap(set => set.ways.filter((line): line is CacheLine => line !== null));
  };
  simulation.l1.forEach((cache, core) => {
    const held = cacheLines(cache, `c${core}`), states = ['M', 'O', 'E', 'S', 'V'];
    lines.push(`c${core} lines ${held.length} ${states.map(state => `${state} ${held.filter(line => line.state === state).length}`).join(' ')}`);
  });
  const held = cacheLines(simulation.l2, 'L2'), dirty = held.filter(line => line.state === 'D').length;
  const inL1 = held.filter(line => simulation.l1.some(cache => cache.state(line.block) !== 'I')).length;
  lines.push(`L2 lines ${held.length} dirty ${dirty} clean ${held.length - dirty} in_l1 ${inL1}`);
  return lines;
}

function main(): void {
  const input = io.read(), { config } = input, trace = validateTrace(input.trace, config);
  const reuse = reuseAnalysis(trace.byCore, config.capacity), sharing = staticSharing(trace.events);
  const simulations = config.scenarios.map(scenario => new Simulation(config, scenario, trace.byCore).simulate());
  const primary = simulations.find(simulation => simulation.primary)!;
  mkdirSync('output', { recursive: true });
  io.write('output/stats.txt', statisticsReport(config, trace, reuse, simulations, primary));
  io.write('output/bus_log.txt', primary.bus.lines(config.line));
  io.write('output/watch.txt', primary.watchLines);
  io.write('output/sharing.txt', sharingReport(config, sharing, primary));
  io.write('output/final_state.txt', finalStateReport(primary));
}

main();
