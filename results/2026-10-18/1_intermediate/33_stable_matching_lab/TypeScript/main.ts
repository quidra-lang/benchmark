import { readFileSync } from 'node:fs';

type MarketKind = 'MARKET' | 'ROOMS' | 'HOUSES';
type CreationCommand = MarketKind | 'RANDOM';
type Source = 'GS' | 'GSR' | 'BOSTON' | 'EGALITARIAN' | 'MINREGRET';
type Command = CreationCommand | Source | 'PREF' | 'CAPACITY' | 'SHOW' | 'CHECK'
  | 'LATTICE' | 'HR' | 'ROOMMATES' | 'TTC' | 'SERIAL' | 'MANIPULATE' | 'STATS';
type Side = 'PROPOSER' | 'RECEIVER';
type Matching = readonly number[];

interface Saved {
  readonly source: Source;
  readonly matching: Matching;
}
interface DeferredRun {
  readonly matching: Matching;
  readonly proposals: number;
  readonly history: readonly string[];
}
interface BostonRun {
  readonly matching: Matching;
  readonly applications: number;
}
interface Metrics {
  readonly cost: number;
  readonly regret: number;
}
interface MatchingRecord {
  readonly matching: Matching;
  readonly origin: number | null;
  readonly via: number | null;
}
interface Lattice {
  readonly records: readonly MatchingRecord[];
  readonly rotations: readonly string[];
}

function isCreation(command: Command): command is CreationCommand {
  return command === 'MARKET' || command === 'ROOMS' || command === 'HOUSES' || command === 'RANDOM';
}

class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }
const sequence = (start: number, end: number): number[] => Array.from({ length: end - start }, (_, i) => start + i);
const rank = (preference: readonly number[], partner: number): number => {
  const index = preference.indexOf(partner);
  return index < 0 ? preference.length + 1 : index + 1;
};
const listText = (names: readonly string[], indices: readonly number[]): string => indices.length ? indices.map(i => names[i]).join(' ') : '-';
const partnerName = (market: Market, partner: number): string => partner < 0 ? '*' : market.names[partner];
const pairText = (market: Market, matching: Matching): string => matching.map((partner, p) => `${market.names[p]}-${partnerName(market, partner)}`).join(' ');
const rotationText = (market: Market, matching: Matching, rotation: readonly number[]): string => rotation.map(p => `${market.names[p]}-${market.names[matching[p]]}`).join(' ');
const allocationText = (market: Market, allocation: readonly number[]): string => allocation.map((house, a) => `${market.names[a]}-${house < 0 ? '*' : market.houses[house]}`).join(' ');
const partnersOf = (matching: Matching, receiver: number): number[] => sequence(0, matching.length).filter(p => matching[p] === receiver);

class Market {
  readonly name: string;
  readonly kind: MarketKind;
  readonly names: readonly string[];
  readonly proposers: number;
  readonly houses: readonly string[];
  preferences: (readonly number[])[];
  capacities: number[];
  current: Saved | null = null;

  constructor(name: string, kind: MarketKind, names: readonly string[], proposers = 0, houses: readonly string[] = []) {
    this.name = name;
    this.kind = kind;
    this.names = names.slice();
    this.proposers = proposers;
    this.houses = houses.slice();
    this.preferences = names.map(() => []);
    this.capacities = names.map(() => 1);
    this.current = null;
  }
  requireKind(kind: MarketKind): void { if (this.kind !== kind) fail(`WRONG TYPE ${this.name}`); }
  agent(name: string, side: Side | null = null): number {
    const index = this.names.indexOf(name);
    if (index < 0) fail(`UNKNOWN AGENT ${name}`);
    if (side === 'PROPOSER' && index >= this.proposers) fail(`NOT PROPOSER ${name}`);
    if (side === 'RECEIVER' && index < this.proposers) fail(`NOT RECEIVER ${name}`);
    return index;
  }
  trial(proposer: number, preference: readonly number[]): Market {
    const result = new Market(this.name, this.kind, this.names, this.proposers, this.houses);
    result.preferences = this.preferences.map((list, i) => (i === proposer ? preference : list).slice());
    result.capacities = this.capacities.slice();
    return result;
  }
  save(source: Source, matching: Matching): void { this.current = { source, matching: matching.slice() }; }
  effective(agent: number): readonly number[] {
    const preference = this.preferences[agent], own = preference.indexOf(agent);
    return own < 0 ? [...preference, agent] : preference.slice(0, own + 1);
  }
}

function deferred(market: Market, reverse = false, verbose = false): DeferredRun {
  const count = market.names.length, next = Array<number>(count).fill(0), counts = Array<number>(count).fill(0);
  const holding: number[][] = market.names.map(() => []), queued = Array<boolean>(count).fill(false);
  const able = (agent: number): boolean => counts[agent] < market.capacities[agent] && next[agent] < market.preferences[agent].length;
  const proposing = reverse ? sequence(market.proposers, count) : sequence(0, market.proposers);
  const queue = proposing.filter(able), history: string[] = [];
  for (const agent of queue) queued[agent] = true;
  let proposals = 0;
  for (let head = 0; head < queue.length; head++) {
    const proposer = queue[head];
    queued[proposer] = false;
    const receiver = market.preferences[proposer][next[proposer]++], preference = market.preferences[receiver];
    proposals++;
    let action = 'REJECT';
    if (preference.includes(proposer)) {
      if (holding[receiver].length < market.capacities[receiver]) {
        holding[receiver].push(proposer);
        counts[proposer]++;
        action = 'HOLD';
      } else {
        let worst = 0;
        for (let i = 1; i < holding[receiver].length; i++) {
          if (rank(preference, holding[receiver][i]) > rank(preference, holding[receiver][worst])) worst = i;
        }
        const rejected = holding[receiver][worst];
        if (rank(preference, proposer) < rank(preference, rejected)) {
          holding[receiver][worst] = proposer;
          counts[proposer]++;
          counts[rejected]--;
          action = `HOLD REJECT ${market.names[rejected]}`;
          if (able(rejected) && !queued[rejected]) { queue.push(rejected); queued[rejected] = true; }
        }
      }
    }
    if (verbose) history.push(`PROPOSE ${market.names[proposer]} ${market.names[receiver]} ${action}`);
    if (able(proposer)) { queue.push(proposer); queued[proposer] = true; }
  }
  const matching = Array<number>(market.proposers).fill(-1);
  const receiving = reverse ? sequence(0, market.proposers) : sequence(market.proposers, count);
  for (const receiver of receiving) {
    for (const proposer of holding[receiver]) {
      if (reverse) matching[receiver] = proposer;
      else matching[proposer] = receiver;
    }
  }
  return { matching, proposals, history };
}
function boston(market: Market): BostonRun {
  const matching = Array<number>(market.proposers).fill(-1), remaining = market.capacities.slice();
  const rounds = Math.max(...market.preferences.slice(0, market.proposers).map(list => list.length));
  let applications = 0;
  for (let round = 0; round < rounds; round++) {
    const applied = Array<number>(market.proposers).fill(-1);
    for (let proposer = 0; proposer < market.proposers; proposer++) {
      if (matching[proposer] < 0 && round < market.preferences[proposer].length) {
        applied[proposer] = market.preferences[proposer][round];
        applications++;
      }
    }
    for (let receiver = market.proposers; receiver < market.names.length; receiver++) {
      for (const proposer of market.preferences[receiver]) {
        if (remaining[receiver] > 0 && applied[proposer] === receiver) {
          matching[proposer] = receiver;
          remaining[receiver]--;
        }
      }
    }
  }
  return { matching, applications };
}
function exposedRotations(market: Market, matching: Matching): number[][] {
  const owner = Array<number>(market.names.length).fill(-1), successor = Array<number>(market.proposers).fill(-1);
  matching.forEach((receiver, proposer) => { if (receiver >= 0) owner[receiver] = proposer; });
  for (let proposer = 0; proposer < market.proposers; proposer++) {
    if (matching[proposer] < 0) continue;
    const preference = market.preferences[proposer];
    for (const receiver of preference.slice(rank(preference, matching[proposer]))) {
      const ranking = market.preferences[receiver];
      if (ranking.includes(proposer) && (owner[receiver] < 0 || rank(ranking, proposer) < rank(ranking, owner[receiver]))) {
        successor[proposer] = owner[receiver];
        break;
      }
    }
  }
  const covered = new Set<number>(), rotations: number[][] = [];
  for (let start = 0; start < market.proposers; start++) {
    if (covered.has(start)) continue;
    const path: number[] = [];
    let point = start;
    while (point >= 0 && !path.includes(point)) { path.push(point); point = successor[point]; }
    if (point === start) {
      path.forEach(proposer => covered.add(proposer));
      rotations.push(path);
    }
  }
  return rotations;
}
function metrics(market: Market, matching: Matching): Metrics {
  let cost = 0, regret = 0;
  matching.forEach((receiver, proposer) => {
    if (receiver < 0) return;
    const first = rank(market.preferences[proposer], receiver), second = rank(market.preferences[receiver], proposer);
    cost += first + second;
    regret = Math.max(regret, first, second);
  });
  return { cost, regret };
}
function enumerate(market: Market): Lattice {
  if (market.capacities.slice(market.proposers).some(capacity => capacity !== 1)) fail('NOT ONE TO ONE');
  const initial = deferred(market).matching;
  const records: MatchingRecord[] = [{ matching: initial, origin: null, via: null }];
  const rotations: string[] = [], seen = new Set([initial.join(',')]);
  for (let index = 0; index < records.length; index++) {
    const { matching } = records[index];
    for (const rotation of exposedRotations(market, matching)) {
      const notation = rotationText(market, matching, rotation);
      let identifier = rotations.indexOf(notation);
      if (identifier < 0) { identifier = rotations.length; rotations.push(notation); }
      const following = matching.slice();
      rotation.forEach((proposer, i) => { following[proposer] = matching[rotation[(i + 1) % rotation.length]]; });
      const key = following.join(',');
      if (seen.has(key)) continue;
      if (records.length === 50) fail('TOO MANY MATCHINGS');
      seen.add(key);
      records.push({ matching: following, origin: index + 1, via: identifier + 1 });
    }
  }
  return { records, rotations };
}

function checkPairs(market: Market, pairs: readonly string[]): string[] {
  if (market.kind === 'HOUSES') fail(`WRONG TYPE ${market.name}`);
  const matching = Array<number>(market.names.length).fill(-1), counts = Array<number>(market.names.length).fill(0);
  for (const word of pairs) {
    const [x, y] = word.split('-');
    const first = market.agent(x, market.kind === 'MARKET' ? 'PROPOSER' : null);
    const second = market.agent(y, market.kind === 'MARKET' ? 'RECEIVER' : null);
    if (matching[first] >= 0) fail(`DUPLICATE AGENT ${x}`);
    if (market.kind === 'MARKET') {
      if (++counts[second] > market.capacities[second]) fail(`OVER CAPACITY ${y}`);
    } else {
      if (first === second || matching[second] >= 0) fail(`DUPLICATE AGENT ${y}`);
      matching[second] = first;
    }
    matching[first] = second;
  }
  const unacceptable: string[] = [], blocking: string[] = [];
  if (market.kind === 'MARKET') {
    for (let proposer = 0; proposer < market.proposers; proposer++) {
      const receiver = matching[proposer], preference = market.preferences[proposer];
      if (receiver >= 0 && (!preference.includes(receiver) || !market.preferences[receiver].includes(proposer))) {
        unacceptable.push(`UNACCEPTABLE ${market.names[proposer]} ${market.names[receiver]}`);
      }
      for (let other = market.proposers; other < market.names.length; other++) {
        const ranking = market.preferences[other];
        if (receiver === other || !preference.includes(other) || !ranking.includes(proposer)) continue;
        if (rank(preference, other) >= rank(preference, receiver)) continue;
        const held = partnersOf(matching.slice(0, market.proposers), other);
        if (held.length < market.capacities[other] || rank(ranking, proposer) < Math.max(...held.map(p => rank(ranking, p)))) {
          blocking.push(`BLOCKING ${market.names[proposer]} ${market.names[other]}`);
        }
      }
    }
  } else {
    for (let first = 0; first < market.names.length; first++) {
      for (let second = first + 1; second < market.names.length; second++) {
        const mutual = market.preferences[first].includes(second) && market.preferences[second].includes(first);
        const notation = `${market.names[first]} ${market.names[second]}`;
        if (matching[first] === second) {
          if (!mutual) unacceptable.push(`UNACCEPTABLE ${notation}`);
        } else if (mutual && rank(market.preferences[first], second) < rank(market.preferences[first], matching[first])
            && rank(market.preferences[second], first) < rank(market.preferences[second], matching[second])) {
          blocking.push(`BLOCKING ${notation}`);
        }
      }
    }
  }
  if (!unacceptable.length && !blocking.length) return [`CHECK ${market.name} STABLE`];
  return [`CHECK ${market.name} UNSTABLE unacceptable=${unacceptable.length} blocking=${blocking.length}`, ...unacceptable, ...blocking];
}
function roommates(market: Market, verbose: boolean): string[] {
  market.requireKind('ROOMS');
  const count = market.names.length;
  for (let agent = 0; agent < count; agent++) {
    if (market.preferences[agent].length < count - 1) fail(`INCOMPLETE ${market.names[agent]}`);
  }
  const lists = market.preferences.map(list => list.slice()), held = Array<number>(count).fill(-1), queue = sequence(0, count);
  const removePair = (a: number, b: number): void => { lists[a] = lists[a].filter(x => x !== b); lists[b] = lists[b].filter(x => x !== a); };
  const table = (): string[] => lists.map((list, a) => `TABLE ${market.names[a]} ${listText(market.names, list)}`);
  let proposals = 0, failure = -1;
  for (let head = 0; head < queue.length; head++) {
    const proposer = queue[head], receiver = lists[proposer][0];
    if (held[receiver] >= 0) queue.push(held[receiver]);
    held[receiver] = proposer;
    proposals++;
    for (const other of lists[receiver].slice(lists[receiver].indexOf(proposer) + 1)) removePair(receiver, other);
    failure = lists.findIndex(list => list.length === 0);
    if (failure >= 0) break;
  }
  const history = failure < 0 && verbose ? table() : [];
  let rotations = 0;
  while (failure < 0) {
    let point = lists.findIndex(list => list.length >= 2);
    if (point < 0) break;
    const path: number[] = [];
    while (!path.includes(point)) {
      path.push(point);
      const nextList = lists[lists[point][1]];
      point = nextList[nextList.length - 1];
    }
    const rotation = path.slice(path.indexOf(point)), front = rotation.map(agent => lists[agent][0]);
    history.push(`ROTATION ${++rotations} ${rotation.map((a, i) => `${market.names[a]}-${market.names[front[i]]}`).join(' ')}`);
    const removals: [number, number][] = [];
    rotation.forEach((agent, i) => {
      const receiver = front[(i + 1) % front.length];
      for (const other of lists[receiver].slice(lists[receiver].indexOf(agent) + 1)) removals.push([receiver, other]);
    });
    for (const [first, second] of removals) removePair(first, second);
    if (verbose) history.push(...table());
    failure = lists.findIndex(list => list.length === 0);
  }
  const output = [`ROOMMATES ${market.name} proposals=${proposals}`, ...history];
  if (failure >= 0) return [...output, `NO STABLE MATCHING ${market.names[failure]}`];
  const pairs: string[] = [];
  lists.forEach((list, a) => { if (a < list[0]) pairs.push(`${market.names[a]}-${market.names[list[0]]}`); });
  return [...output, `MATCHING ${pairs.join(' ')}`];
}
function ttc(market: Market): string[] {
  const remaining = new Set(sequence(0, market.names.length)), allocation = Array<number>(market.names.length).fill(-1), cycles: string[] = [];
  while (remaining.size) {
    const pointing = Array<number>(market.names.length).fill(-1);
    for (const agent of remaining) {
      // Every remaining agent still owns a remaining house in its effective list.
      pointing[agent] = market.effective(agent).find(house => remaining.has(house))!;
    }
    const path: number[] = [];
    let point = remaining.values().next().value!;
    while (!path.includes(point)) { path.push(point); point = pointing[point]; }
    const cycle = path.slice(path.indexOf(point));
    for (const agent of cycle) { allocation[agent] = pointing[agent]; remaining.delete(agent); }
    cycles.push(`CYCLE ${cycles.length + 1} ${cycle.map(a => `${market.names[a]}:${market.houses[allocation[a]]}`).join(' ')}`);
  }
  return [`TTC ${market.name} cycles=${cycles.length}`, ...cycles, `ALLOCATION ${allocationText(market, allocation)}`];
}
function serial(market: Market, names: readonly string[]): string[] {
  const order: number[] = [];
  for (const name of names) {
    const agent = market.agent(name);
    if (order.includes(agent)) fail(`DUPLICATE AGENT ${name}`);
    order.push(agent);
  }
  if (order.length !== market.names.length) fail('BAD ORDER');
  const remaining = new Set(sequence(0, market.houses.length)), allocation = Array<number>(market.names.length).fill(-1);
  let assigned = 0;
  for (const agent of order) {
    const house = market.preferences[agent].find(candidate => remaining.has(candidate));
    if (house !== undefined) { allocation[agent] = house; remaining.delete(house); assigned++; }
  }
  const worse = sequence(0, market.names.length).filter(a => !market.effective(a).includes(allocation[a]));
  return [`SERIAL ${market.name} assigned=${assigned}`, `ALLOCATION ${allocationText(market, allocation)}`, `WORSE ${listText(market.names, worse)}`];
}
function hospitalReport(market: Market): string[] {
  const resident = deferred(market).matching, hospital = deferred(market, true).matching;
  const unmatched = sequence(0, market.proposers).filter(p => resident[p] < 0);
  let rural = resident.every((partner, p) => (partner >= 0) === (hospital[p] >= 0));
  const output = [`HR ${market.name} residents=${market.proposers} hospitals=${market.names.length - market.proposers}`,
    `RESIDENT-OPTIMAL ${pairText(market, resident)}`, `HOSPITAL-OPTIMAL ${pairText(market, hospital)}`, `UNMATCHED ${listText(market.names, unmatched)}`];
  for (let receiver = market.proposers; receiver < market.names.length; receiver++) {
    const first = partnersOf(resident, receiver), second = partnersOf(hospital, receiver), capacity = market.capacities[receiver];
    const same = first.length === second.length && first.every((p, i) => p === second[i]);
    output.push(`HOSPITAL ${market.names[receiver]} cap=${capacity} resident=${first.length} hospital=${second.length} same=${same ? 'YES' : 'NO'}`);
    if (first.length !== second.length || (first.length < capacity && !same)) rural = false;
  }
  return [...output, `RURAL ${rural ? 'HOLDS' : 'FAILS'}`];
}

function manipulate(market: Market, proposer: number): string[] {
  const truth = market.preferences[proposer], baselineB = boston(market).matching[proposer], baselineG = deferred(market).matching[proposer];
  const output = [`MANIPULATE ${market.name} ${market.names[proposer]} boston=${partnerName(market, baselineB)} gs=${partnerName(market, baselineG)} swaps=${Math.max(0, truth.length - 1)}`];
  for (let index = 0; index + 1 < truth.length; index++) {
    const preference = truth.slice();
    [preference[index], preference[index + 1]] = [preference[index + 1], preference[index]];
    const trial = market.trial(proposer, preference);
    const outcomes: readonly (readonly ['BOSTON' | 'GS', number, number])[] = [
      ['BOSTON', boston(trial).matching[proposer], baselineB], ['GS', deferred(trial).matching[proposer], baselineG],
    ];
    for (const [label, result, baseline] of outcomes) {
      if (rank(truth, result) < rank(truth, baseline)) {
        output.push(`IMPROVE ${label} ${index + 1} ${market.names[truth[index]]} ${market.names[truth[index + 1]]} result=${partnerName(market, result)}`);
      }
    }
  }
  if (output.length === 1) output.push('NO IMPROVEMENT');
  return output;
}
function gcd(first: number, second: number): number {
  while (second) [first, second] = [second, first % second];
  return first;
}
function statistics(market: Market): string[] {
  if (market.current === null) fail('NO MATCHING');
  const { source, matching } = market.current, proposerRanks: number[] = [], receiverRanks: number[] = [], occupied = new Set<number>();
  matching.forEach((receiver, proposer) => {
    if (receiver < 0) return;
    proposerRanks.push(rank(market.preferences[proposer], receiver));
    receiverRanks.push(rank(market.preferences[receiver], proposer));
    occupied.add(receiver);
  });
  const pairs = proposerRanks.length, output = [`STATS ${market.name} source=${source} pairs=${pairs}`];
  const sides = [
    { label: 'PROPOSERS', ranks: proposerRanks, unmatched: market.proposers - pairs },
    { label: 'RECEIVERS', ranks: receiverRanks, unmatched: market.names.length - market.proposers - occupied.size },
  ];
  for (const { label, ranks, unmatched } of sides) {
    const sum = ranks.reduce((a, b) => a + b, 0), first = ranks.filter(value => value === 1).length;
    let average = '-', truncated = '-';
    if (pairs) {
      const divisor = gcd(sum, pairs), cents = Math.floor(100 * sum / pairs);
      average = `${sum / divisor}/${pairs / divisor}`;
      truncated = `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;
    }
    output.push(`${label} sum=${sum} average=${average} truncated=${truncated} first=${first} unmatched=${unmatched}`);
  }
  return output;
}
function showMarket(market: Market): string[] {
  const output = [market.kind === 'MARKET'
    ? `SHOW ${market.name} MARKET proposers=${market.proposers} receivers=${market.names.length - market.proposers}`
    : `SHOW ${market.name} ${market.kind} agents=${market.names.length}`];
  market.names.forEach((name, agent) => {
    let prefix: string;
    if (market.kind === 'MARKET') prefix = agent < market.proposers ? `PROPOSER ${name}` : `RECEIVER ${name} cap=${market.capacities[agent]}`;
    else prefix = `AGENT ${name}${market.kind === 'HOUSES' ? ' house=' + market.houses[agent] : ''}`;
    output.push(`${prefix} ${listText(market.kind === 'HOUSES' ? market.houses : market.names, market.preferences[agent])}`);
  });
  if (market.kind === 'MARKET') output.push(`CURRENT ${market.current?.source ?? '-'}`);
  return output;
}
function newMarket(command: CreationCommand, name: string, args: readonly string[]): Market {
  if (command === 'RANDOM') {
    const count = Number(args[0]), names = ['P', 'R'].flatMap(prefix => sequence(1, count + 1).map(i => prefix + i));
    const market = new Market(name, 'MARKET', names, count);
    let state = Number(args[1]);
    for (let agent = 0; agent < names.length; agent++) {
      const preference = agent < count ? sequence(count, 2 * count) : sequence(0, count);
      for (let length = count; length >= 2; length--) {
        state = 48271 * state % 2147483647;
        const index = state % length;
        [preference[length - 1], preference[index]] = [preference[index], preference[length - 1]];
      }
      market.preferences[agent] = preference;
    }
    return market;
  }
  const names: string[] = [], houses: string[] = [];
  let proposers = 0;
  for (const word of args) {
    if (word === '|') { proposers = names.length; continue; }
    const [agent, house] = word.split(':');
    if (names.includes(agent)) fail(`DUPLICATE AGENT ${agent}`);
    if (command === 'HOUSES') {
      if (houses.includes(house)) fail(`DUPLICATE HOUSE ${house}`);
      houses.push(house);
    }
    names.push(agent);
  }
  return new Market(name, command, names, proposers, houses);
}
class Laboratory {
  readonly #markets = new Map<string, Market>();

  execute(line: string): string[] {
    const [word, name, ...args] = line.split(' ');
    const command = word as Command; // The input grammar guarantees a listed command.
    if (isCreation(command)) {
      if (this.#markets.has(name)) fail(`DUPLICATE MARKET ${name}`);
      const market = newMarket(command, name, args);
      this.#markets.set(name, market);
      if (command === 'RANDOM') return [`RANDOM ${name} n=${market.proposers} seed=${args[1]}`];
      if (command === 'MARKET') return [`MARKET ${name} proposers=${market.proposers} receivers=${market.names.length - market.proposers}`];
      return [`${command} ${name} agents=${market.names.length}`];
    }
    const market = this.#markets.get(name);
    if (market === undefined) fail(`UNKNOWN MARKET ${name}`);
    switch (command) {
      case 'SHOW': return showMarket(market);
      case 'PREF': {
        const agent = market.agent(args[0]), names = market.kind === 'HOUSES' ? market.houses : market.names, preference: number[] = [];
        for (const word of args.slice(1)) {
          const choice = names.indexOf(word);
          if (choice < 0 || (market.kind === 'ROOMS' && choice === agent)
              || (market.kind === 'MARKET' && (agent < market.proposers) === (choice < market.proposers))) fail(`BAD CHOICE ${word}`);
          if (preference.includes(choice)) fail(`DUPLICATE CHOICE ${word}`);
          preference.push(choice);
        }
        market.preferences[agent] = preference;
        if (market.kind === 'MARKET') market.current = null;
        return [`PREF ${name} ${args[0]} length=${preference.length}`];
      }
      case 'CHECK': return checkPairs(market, args);
      case 'ROOMMATES': return roommates(market, args.length === 1);
      case 'TTC': case 'SERIAL':
        market.requireKind('HOUSES');
        return command === 'TTC' ? ttc(market) : serial(market, args);
      default: market.requireKind('MARKET');
    }
    switch (command) {
      case 'CAPACITY': {
        const receiver = market.agent(args[0], 'RECEIVER'), capacity = Number(args[1]);
        market.capacities[receiver] = capacity;
        market.current = null;
        return [`CAPACITY ${name} ${args[0]} ${capacity}`];
      }
      case 'GS': case 'GSR': {
        const run = deferred(market, command === 'GSR', args.length === 1);
        market.save(command, run.matching);
        return [`${command} ${name} proposals=${run.proposals}`, ...run.history, `MATCHING ${pairText(market, run.matching)}`];
      }
      case 'BOSTON': {
        const run = boston(market);
        market.save(command, run.matching);
        return [`BOSTON ${name} applications=${run.applications}`, `MATCHING ${pairText(market, run.matching)}`];
      }
      case 'HR': return hospitalReport(market);
      case 'MANIPULATE': return manipulate(market, market.agent(args[0], 'PROPOSER'));
      case 'STATS': return statistics(market);
      default: {
        const lattice = enumerate(market);
        if (command === 'LATTICE') {
          const output = [`LATTICE ${name} matchings=${lattice.records.length} rotations=${lattice.rotations.length}`];
          lattice.records.forEach(({ matching, origin, via }, i) => {
            const { cost, regret } = metrics(market, matching);
            output.push(`MATCHING ${i + 1} from=${origin ?? '-'} via=${via ?? '-'} cost=${cost} regret=${regret} ${pairText(market, matching)}`);
          });
          lattice.rotations.forEach((rotation, i) => output.push(`ROTATION ${i + 1} ${rotation}`));
          return output;
        }
        const label = command === 'EGALITARIAN' ? 'cost' : 'regret';
        const values = lattice.records.map(record => metrics(market, record.matching)[label]), best = values.indexOf(Math.min(...values));
        const matching = lattice.records[best].matching;
        market.save(command, matching);
        return [`${command} ${name} matching=${best + 1} ${label}=${values[best]}`, `MATCHING ${pairText(market, matching)}`];
      }
    }
  }
}

const lines = readFileSync(0, 'utf8').split(/\r?\n/), count = Number(lines[0]), laboratory = new Laboratory(), output: string[] = [];
for (let i = 1; i <= count; i++) {
  try { output.push(...laboratory.execute(lines[i])); }
  catch (error) {
    if (!(error instanceof CommandError)) throw error;
    output.push(`ERROR ${error.message}`);
  }
}
process.stdout.write(output.join('\n') + '\n');
