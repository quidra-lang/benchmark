import {
  readInputs,
  timestampMinutes,
  buildCases,
  median,
  quotient,
  type InputRow,
  type Event,
  type Case,
} from './eventlog.ts';
import {
  pairKey,
  count,
  countFollows,
  basicRelation,
  table,
  footprint,
  type Counts,
  type LogEntry,
  type Relation,
} from './dfg.ts';
import {
  compareSequences,
  comparePairs,
  extendPair,
  triangleCounts,
  alphaPlusRelation,
  type Pair,
} from './alpha_miner.ts';
import {
  dependency,
  loopMeasure,
  routingMeasure,
  compareFractions,
  subtractFractions,
} from './heuristic_miner.ts';
import {
  PetriNet,
  readModel,
  replayRecord,
  fitness,
  type ReplayRecord,
  type PlaceReplay,
} from './conformance.ts';
import { fraction, percentage, list, writeOutputs, type Fraction } from './report.ts';

interface Settings {
  filter: number;
  sla: number;
  observations: number;
  dependency: Fraction;
  relative: Fraction;
  loop1: Fraction;
  loop2: Fraction;
  and: Fraction;
}
interface Variant {
  trace: string[];
  cases: Case[];
  number: number;
  keep: boolean;
}
interface ActivityStats {
  events: number;
  cases: number;
  start: number;
  end: number;
  rework: number;
  wait: number;
  waits: number;
  resources: Set<string>;
}
interface Edge {
  from: string;
  to: string;
  count: number;
  cases: Set<string>;
  waits: number[];
}
interface Discovery {
  activities: string[];
  relation: Relation;
  causal: number;
  candidates: number;
  pairs: Pair[];
  starts: string[];
  ends: string[];
  net: PetriNet;
}
interface Prefix {
  trace: string[];
  weight: number;
  followers: Set<string>;
}
interface Replay {
  totals: ReplayRecord;
  cases: Map<string, ReplayRecord>;
}
interface NetResult {
  name: string;
  net: PetriNet;
  reachability: ReturnType<typeof explore>;
  footprint: ReturnType<typeof footprintFitness>;
  precision: ReturnType<typeof precision>;
  replay: Replay;
}
const nameOrder = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);
const pairOrder = (a: { from: string; to: string }, b: { from: string; to: string }): number =>
  nameOrder(a.from, b.from) || nameOrder(a.to, b.to);
const unique = (names: string[]): string[] => [...new Set(names)].sort();
function increment<K>(map: Map<K, number>, key: K, amount = 1): void {
  map.set(key, (map.get(key) ?? 0) + amount);
}
function sum(values: number[]): number {
  let total = 0;
  for (const value of values) total += value;
  return total;
}
function parameters(values: Map<string, string>): Settings {
  const ratio = (key: string): Fraction => {
    const [a, b] = values.get(key)!.split('/');
    return [BigInt(a), BigInt(b)];
  };
  return {
    filter: Number(values.get('filter_min_follows')),
    sla: Number(values.get('sla_minutes')),
    observations: Number(values.get('positive_observations')),
    dependency: ratio('dependency_threshold'),
    relative: ratio('relative_to_best'),
    loop1: ratio('loop1_threshold'),
    loop2: ratio('loop2_threshold'),
    and: ratio('and_threshold'),
  };
}
function validate(rows: InputRow[]): { events: Event[]; errors: string[] } {
  const events: Event[] = [];
  const errors: string[] = [];
  const adopted = new Set<string>();
  for (const row of rows) {
    const time = timestampMinutes(row.timestamp);
    const key = [row.caseId, row.activity, row.timestamp].join('\0');
    if (time === null) errors.push(`ERROR line ${row.line}: bad timestamp ${row.timestamp}`);
    else if (adopted.has(key)) {
      errors.push(
        `ERROR line ${row.line}: duplicate event ${row.caseId} ${row.activity} ${row.timestamp}`,
      );
    } else {
      adopted.add(key);
      events.push({ ...row, time });
    }
  }
  return { events, errors };
}
function groupVariants(cases: Case[], follows: Counts, settings: Settings): Variant[] {
  const groups = new Map<string, Variant>();
  for (const item of cases) {
    const key = item.trace.join(',');
    let group = groups.get(key);
    if (!group) {
      group = { trace: item.trace, cases: [], number: 0, keep: false };
      groups.set(key, group);
    }
    group.cases.push(item);
  }
  const variants = [...groups.values()].sort(
    (a, b) => b.cases.length - a.cases.length || compareSequences(a.trace, b.trace),
  );
  variants.forEach((v, i) => {
    v.number = i + 1;
    v.keep = v.trace.every(
      (a, j) => j === 0 || count(follows, v.trace[j - 1], a) >= settings.filter,
    );
    for (const item of v.cases) item.variant = v.number;
  });
  return variants;
}
function discoverAlpha(log: LogEntry[], activities: string[], relation: Relation): Discovery {
  const candidates: (Pair & { maximal: boolean })[] = [];
  const known = new Set<string>();
  const add = (pair: Pair): void => {
    const key = pair.A.join(',') + '|' + pair.B.join(',');
    if (!known.has(key)) {
      known.add(key);
      candidates.push({ ...pair, maximal: true });
    }
  };
  let causal = 0;
  for (const a of activities) {
    for (const b of activities) {
      if (relation(a, b) === '->') {
        causal++;
        if (relation(a, a) === '#' && relation(b, b) === '#') add({ A: [a], B: [b] });
      }
    }
  }
  const sides: ('A' | 'B')[] = ['A', 'B'];
  for (let i = 0; i < candidates.length; i++) {
    const pair = candidates[i];
    for (const activity of activities) {
      for (const side of sides) {
        const extended = extendPair(pair, activity, side, relation);
        if (extended !== null) {
          pair.maximal = false;
          add(extended);
        }
      }
    }
  }
  const pairs = candidates.filter((p) => p.maximal).sort(comparePairs);
  const starts = unique(log.map((e) => e.trace[0]));
  const ends = unique(log.map((e) => e.trace.at(-1)!));
  const places = ['start', ...pairs.map((_, i) => `p${i + 1}`), 'end'];
  const arcs: [string, string][] = [];
  for (const a of starts) arcs.push(['start', a]);
  for (const a of ends) arcs.push([a, 'end']);
  pairs.forEach((pair, i) => {
    for (const a of pair.A) arcs.push([a, places[i + 1]]);
    for (const b of pair.B) arcs.push([places[i + 1], b]);
  });
  return {
    activities,
    relation,
    causal,
    candidates: candidates.length,
    pairs,
    starts,
    ends,
    net: new PetriNet(places, activities, arcs, 'start', 'end'),
  };
}
function netLines(d: Discovery): string[] {
  const { net, starts, ends, pairs } = d;
  const lines = [`PLACE start - ${list(starts)}`];
  pairs.forEach((pair, i) => lines.push(`PLACE p${i + 1} ${list(pair.A)} ${list(pair.B)}`));
  lines.push(`PLACE end ${list(ends)} -`);
  for (const t of net.transitions) {
    lines.push(
      `TRANSITION ${t} in ${list(net.inputs.get(t)!.map((i) => net.places[i]))} out ${list(net.outputs.get(t)!.map((i) => net.places[i]))}`,
    );
  }
  lines.push(
    `NET places ${net.places.length} transitions ${net.transitions.length} arcs ${net.arcs.length}`,
  );
  return lines;
}
function alphaMining(variants: Variant[]): { alpha: PetriNet; plus: PetriNet; lines: string[] } {
  const filtered = variants
    .filter((v) => v.keep)
    .map((v) => ({ trace: v.trace, weight: v.cases.length }));
  const activities = unique(filtered.flatMap((e) => e.trace));
  const follows = countFollows(filtered);
  const loops = activities.filter((a) => count(follows, a, a) > 0);
  const loopSet = new Set(loops);
  const alpha = discoverAlpha(filtered, activities, (a, b) => basicRelation(follows, a, b));
  const reduced = filtered.map((e) => ({
    trace: e.trace.filter((a) => !loopSet.has(a)),
    weight: e.weight,
  }));
  const reducedActivities = activities.filter((a) => !loopSet.has(a));
  const triangles = triangleCounts(reduced);
  const plus = discoverAlpha(
    reduced,
    reducedActivities,
    alphaPlusRelation(countFollows(reduced), triangles),
  );
  const arcs = plus.net.arcs.slice();
  const loopLines: string[] = [];
  for (const activity of loops) {
    const before = reducedActivities.filter((a) => count(follows, a, activity) > 0);
    const after = reducedActivities.filter((b) => count(follows, activity, b) > 0);
    const i = plus.pairs.findIndex(
      (pair) => compareSequences(pair.A, before) === 0 && compareSequences(pair.B, after) === 0,
    );
    const place = i < 0 ? '-' : `p${i + 1}`;
    if (i >= 0) arcs.push([place, activity], [activity, place]);
    loopLines.push(`LOOP ${activity} before ${list(before)} after ${list(after)} place ${place}`);
  }
  plus.net = new PetriNet(plus.net.places, activities, arcs, 'start', 'end');
  const lines = [
    `LOG variants ${filtered.length} cases ${sum(filtered.map((e) => e.weight))} activities ${list(activities)}`,
    `LOOPS ${list(loops)}`,
    'MINER alpha',
    ...footprint(alpha.activities, alpha.relation),
    `PAIRS causal ${alpha.causal} candidates ${alpha.candidates} maximal ${alpha.pairs.length}`,
    ...netLines(alpha),
    'MINER alpha_plus',
  ];
  for (const a of reducedActivities) {
    for (const b of reducedActivities) {
      const n = count(triangles, a, b);
      if (n) lines.push(`TRIANGLE ${a} ${b} count ${n}`);
    }
  }
  lines.push(
    ...footprint(plus.activities, plus.relation),
    `PAIRS causal ${plus.causal} candidates ${plus.candidates} maximal ${plus.pairs.length}`,
    ...loopLines,
    ...netLines(plus),
  );
  return { alpha: alpha.net, plus: plus.net, lines };
}
function heuristicReport(
  log: LogEntry[],
  activities: string[],
  follows: Counts,
  settings: Settings,
): string[] {
  const lines: string[] = [];
  const triangles = triangleCounts(log);
  const loops1 = new Set<string>();
  const loops2 = new Set<string>();
  const edges = new Set<string>();
  let loopPairs = 0;
  for (const a of activities) {
    const n = count(follows, a, a);
    if (!n) continue;
    const measure = loopMeasure(n);
    const accepted = n >= settings.observations && compareFractions(measure, settings.loop1) >= 0;
    lines.push(`L1 ${a} count ${n} measure ${fraction(measure)} ${accepted ? 'ACCEPT' : 'REJECT'}`);
    if (accepted) {
      loops1.add(a);
      edges.add(pairKey(a, a));
    }
  }
  for (let i = 0; i < activities.length; i++) {
    for (let j = i + 1; j < activities.length; j++) {
      const a = activities[i];
      const b = activities[j];
      if (loops1.has(a) || loops1.has(b)) continue;
      const n = count(triangles, a, b) + count(triangles, b, a);
      if (!n) continue;
      const measure = loopMeasure(n);
      const accepted = n >= settings.observations && compareFractions(measure, settings.loop2) >= 0;
      lines.push(
        `L2 ${a} ${b} count ${n} measure ${fraction(measure)} ${accepted ? 'ACCEPT' : 'REJECT'}`,
      );
      if (accepted) {
        loops2.add(pairKey(a, b));
        loops2.add(pairKey(b, a));
        loopPairs++;
      }
    }
  }
  const dependencies: { a: string; b: string; n: number; measure: Fraction }[] = [];
  const bestOut = new Map<string, Fraction>();
  const bestIn = new Map<string, Fraction>();
  for (const a of activities) {
    for (const b of activities) {
      const n = count(follows, a, b);
      if (a === b || !n) continue;
      const measure = dependency(follows, a, b);
      dependencies.push({ a, b, n, measure });
      if (!bestOut.has(a) || compareFractions(measure, bestOut.get(a)!) > 0) {
        bestOut.set(a, measure);
      }
      if (!bestIn.has(b) || compareFractions(measure, bestIn.get(b)!) > 0) bestIn.set(b, measure);
    }
  }
  for (const { a, b, n, measure } of dependencies) {
    let verdict = 'ACCEPT';
    if (loops2.has(pairKey(a, b))) verdict = 'LOOP2';
    else if (n < settings.observations) verdict = 'REJECT_COUNT';
    else if (compareFractions(measure, settings.dependency) < 0) verdict = 'REJECT_MEASURE';
    else if (
      compareFractions(subtractFractions(bestOut.get(a)!, measure), settings.relative) > 0 &&
      compareFractions(subtractFractions(bestIn.get(b)!, measure), settings.relative) > 0
    ) {
      verdict = 'REJECT_BEST';
    }
    if (verdict === 'ACCEPT' || verdict === 'LOOP2') edges.add(pairKey(a, b));
    lines.push(
      `DEP ${a} ${b} count ${n} reverse ${count(follows, b, a)} measure ${fraction(measure)} ${verdict}`,
    );
  }
  const nodes = activities.map((a) => ({
    activity: a,
    inputs: activities.filter((x) => edges.has(pairKey(x, a))),
    outputs: activities.filter((x) => edges.has(pairKey(a, x))),
  }));
  for (const n of nodes) {
    lines.push(`NODE ${n.activity} in ${list(n.inputs)} out ${list(n.outputs)}`);
  }
  for (const n of nodes) {
    for (const split of [true, false]) {
      const neighbors = (split ? n.outputs : n.inputs).filter((x) => x !== n.activity);
      for (let i = 0; i < neighbors.length; i++) {
        for (let j = i + 1; j < neighbors.length; j++) {
          const measure = routingMeasure(follows, n.activity, neighbors[i], neighbors[j], split);
          lines.push(
            `${split ? 'SPLIT' : 'JOIN'} ${n.activity} ${neighbors[i]} ${neighbors[j]} measure ${fraction(measure)} ${compareFractions(measure, settings.and) >= 0 ? 'AND' : 'XOR'}`,
          );
        }
      }
    }
  }
  lines.push(
    `GRAPH activities ${activities.length} edges ${edges.size} loops1 ${loops1.size} loops2 ${loopPairs}`,
  );
  return lines;
}
function explore(net: PetriNet) {
  const initial = net.marking();
  const states = [initial];
  const ids = new Map([[initial.join(','), 0]]);
  const reverseEdges: number[][] = [[]];
  const finalKey = net.marking(true).join(',');
  const dead = new Set(net.transitions);
  const follows: Counts = new Map();
  let edges = 0;
  let unsafe = 0;
  let deadlocks = 0;
  for (let i = 0; i < states.length; i++) {
    const marking = states[i];
    const enabled = net.enabledTransitions(marking);
    if (!enabled.length && marking.join(',') !== finalKey) deadlocks++;
    for (const t of enabled) {
      dead.delete(t);
      const next = net.fire(marking, t);
      if (next.some((tokens) => tokens > 1)) {
        unsafe++;
        continue;
      }
      edges++;
      const key = next.join(',');
      if (!ids.has(key)) {
        ids.set(key, states.length);
        states.push(next);
        reverseEdges.push([]);
      }
      reverseEdges[ids.get(key)!].push(i);
      for (const u of net.enabledTransitions(next)) follows.set(pairKey(t, u), 1);
    }
  }
  const canFinish = new Set<number>();
  if (ids.has(finalKey)) {
    const queue = [ids.get(finalKey)!];
    canFinish.add(queue[0]);
    for (let i = 0; i < queue.length; i++) {
      for (const p of reverseEdges[queue[i]]) {
        if (!canFinish.has(p)) {
          canFinish.add(p);
          queue.push(p);
        }
      }
    }
  }
  const stuck = states.length - canFinish.size;
  return {
    markings: states.length,
    edges,
    unsafe,
    deadlocks,
    stuck,
    final: ids.has(finalKey),
    dead: net.transitions.filter((t) => dead.has(t)),
    sound: unsafe === 0 && stuck === 0 && dead.size === 0,
    follows,
  };
}
function footprintFitness(
  activities: string[],
  follows: Counts,
  net: PetriNet,
  reachability: ReturnType<typeof explore>,
) {
  const names = unique([...activities, ...net.transitions]);
  const differences: string[] = [];
  let differing = 0;
  for (const a of names) {
    for (const b of names) {
      const observed = basicRelation(follows, a, b);
      const model = basicRelation(reachability.follows, a, b);
      if (observed !== model) {
        differing++;
        if (a <= b) differences.push(`DIFF ${a} ${b} log ${observed} model ${model}`);
      }
    }
  }
  const cells = names.length * names.length;
  const value: Fraction = [BigInt(cells - differing), BigInt(cells)];
  return { activities: names.length, cells, differing, fitness: value, differences };
}
function buildPrefixes(cases: Case[]): Prefix[] {
  const prefixes = new Map<string, Prefix>();
  for (const item of cases) {
    for (let n = 0; n <= item.trace.length; n++) {
      const trace = item.trace.slice(0, n);
      const key = trace.join(',');
      let prefix = prefixes.get(key);
      if (!prefix) {
        prefix = { trace, weight: 0, followers: new Set() };
        prefixes.set(key, prefix);
      }
      prefix.weight++;
      if (n < item.trace.length) prefix.followers.add(item.trace[n]);
    }
  }
  return [...prefixes.values()];
}
function precision(net: PetriNet, prefixes: Prefix[]) {
  let fitting = 0;
  let allowed = 0;
  let escaping = 0;
  const escapes = new Map<string, number>();
  for (const prefix of prefixes) {
    let marking = net.marking();
    let fits = true;
    for (const t of prefix.trace) {
      if (!net.enabled(marking, t)) {
        fits = false;
        break;
      }
      marking = net.fire(marking, t);
    }
    if (!fits) continue;
    fitting++;
    const enabled = net.enabledTransitions(marking);
    allowed += prefix.weight * enabled.length;
    for (const t of enabled) {
      if (!prefix.followers.has(t)) {
        escaping += prefix.weight;
        increment(escapes, t, prefix.weight);
      }
    }
  }
  const value: Fraction = allowed === 0 ? [1n, 1n] : [BigInt(allowed - escaping), BigInt(allowed)];
  return { prefixes: fitting, allowed, escaping, escapes, value };
}
function replayCase(net: PetriNet, item: Case): ReplayRecord {
  const record = replayRecord(net);
  const tokens: { times: number[]; consumed: number }[] = net.places.map(() => ({
    times: [],
    consumed: 0,
  }));
  tokens[net.initial].times.push(item.events[0].time);
  record.produced = 1;
  for (const event of item.events) {
    if (!net.inputs.has(event.activity)) {
      record.skipped++;
      continue;
    }
    for (const p of net.inputs.get(event.activity)!) {
      record.consumed++;
      const queue = tokens[p];
      const statistic = record.places[p];
      if (queue.consumed < queue.times.length) {
        const waiting = event.time - queue.times[queue.consumed++];
        statistic.waitingCount++;
        statistic.waitingTotal += waiting;
        statistic.waitingMaximum = Math.max(statistic.waitingMaximum, waiting);
        increment(statistic.consumptions, event.activity);
      } else {
        record.missing++;
        statistic.missing++;
      }
    }
    for (const p of net.outputs.get(event.activity)!) {
      tokens[p].times.push(event.time);
      record.produced++;
    }
  }
  record.consumed++;
  const final = tokens[net.final];
  if (final.consumed < final.times.length) final.consumed++;
  else {
    record.missing++;
    record.places[net.final].missing++;
  }
  for (let p = 0; p < net.places.length; p++) {
    const remaining = tokens[p].times.length - tokens[p].consumed;
    record.remaining += remaining;
    record.places[p].remaining = remaining;
    record.places[p].deviating = record.places[p].missing > 0 || remaining > 0 ? 1 : 0;
  }
  record.fitting = record.missing === 0 && record.remaining === 0 ? 1 : 0;
  return record;
}
function replayAll(net: PetriNet, cases: Case[]): Replay {
  const totals = replayRecord(net);
  const records = new Map<string, ReplayRecord>();
  const fields: (keyof Omit<ReplayRecord, 'places'>)[] = [
    'missing',
    'remaining',
    'consumed',
    'produced',
    'skipped',
    'fitting',
  ];
  const placeFields: (keyof Pick<
    PlaceReplay,
    'missing' | 'remaining' | 'deviating' | 'waitingCount' | 'waitingTotal'
  >)[] = ['missing', 'remaining', 'deviating', 'waitingCount', 'waitingTotal'];
  for (const item of cases) {
    const record = replayCase(net, item);
    records.set(item.id, record);
    for (const field of fields) totals[field] += record[field];
    for (let p = 0; p < net.places.length; p++) {
      const target = totals.places[p];
      const source = record.places[p];
      for (const field of placeFields) target[field] += source[field];
      target.waitingMaximum = Math.max(target.waitingMaximum, source.waitingMaximum);
      for (const [t, n] of source.consumptions) increment(target.consumptions, t, n);
    }
  }
  return { totals, cases: records };
}
function logSummary(
  rows: InputRow[],
  events: Event[],
  errors: string[],
  cases: Case[],
  activities: string[],
  resources: string[],
  net: PetriNet,
  settings: Settings,
): string[] {
  const lines = errors.slice();
  const chronological = events.toSorted((a, b) => a.time - b.time || a.line - b.line);
  lines.push(
    `LOG rows ${rows.length} adopted ${events.length} rejected ${errors.length} cases ${cases.length} activities ${activities.length} resources ${resources.length} first ${chronological[0].timestamp} last ${chronological.at(-1)!.timestamp}`,
  );
  const statistics = new Map<string, ActivityStats>(
    activities.map((a) => [
      a,
      {
        events: 0,
        cases: 0,
        start: 0,
        end: 0,
        rework: 0,
        wait: 0,
        waits: 0,
        resources: new Set(),
      },
    ]),
  );
  const weekdays = Array.from({ length: 7 }, () => ({ events: 0, starts: 0, ends: 0 }));
  const dayCounts = new Map<number, number>();
  const weekday = (t: number): number => (quotient(t, 1440) + 3) % 7;
  let late = 0;
  for (const item of cases) {
    const frequencies = new Map<string, number>();
    item.events.forEach((e, i) => {
      const s = statistics.get(e.activity)!;
      s.events++;
      s.resources.add(e.resource);
      increment(frequencies, e.activity);
      weekdays[weekday(e.time)].events++;
      if (i > 0) {
        s.wait += e.time - item.events[i - 1].time;
        s.waits++;
      }
    });
    for (const [a, n] of frequencies) {
      const s = statistics.get(a)!;
      s.cases++;
      if (n >= 2) s.rework++;
    }
    statistics.get(item.trace[0])!.start++;
    statistics.get(item.trace.at(-1)!)!.end++;
    weekdays[weekday(item.events[0].time)].starts++;
    weekdays[weekday(item.events.at(-1)!.time)].ends++;
    increment(dayCounts, quotient(item.duration, 1440));
    if (item.duration > settings.sla) late++;
  }
  for (const a of activities) {
    const s = statistics.get(a)!;
    lines.push(
      `ACTIVITY ${a} events ${s.events} cases ${s.cases} start ${s.start} end ${s.end} rework ${s.rework} wait ${s.waits ? fraction(s.wait, s.waits) : '-'} resources ${s.resources.size} model ${net.inputs.has(a) ? 'yes' : 'no'}`,
    );
  }
  const summaries: [string, number[]][] = [
    ['LENGTH', cases.map((c) => c.events.length)],
    ['DURATION', cases.map((c) => c.duration)],
  ];
  for (const [name, values] of summaries) {
    lines.push(
      `${name} min ${Math.min(...values)} max ${Math.max(...values)} mean ${fraction(sum(values), values.length)} median ${fraction(median(values))}`,
    );
  }
  for (let d = 0; d <= Math.max(...dayCounts.keys()); d++) {
    const n = dayCounts.get(d) ?? 0;
    lines.push(`DAYS ${d} cases ${n} share ${percentage(n, cases.length)}`);
  }
  lines.push(`SLA limit ${settings.sla} late ${late} share ${percentage(late, cases.length)}`);
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  weekdays.forEach((s, i) =>
    lines.push(`WEEKDAY ${names[i]} events ${s.events} starts ${s.starts} ends ${s.ends}`),
  );
  return lines;
}
function variantReport(
  variants: Variant[],
  cases: Case[],
  eventCount: number,
  settings: Settings,
  replay: Replay,
): string[] {
  const lines: string[] = [];
  let keptVariants = 0;
  let keptCases = 0;
  let keptEvents = 0;
  for (const v of variants) {
    const n = v.cases.length;
    const first = v.cases[0];
    const durations = v.cases.map((c) => c.duration);
    const late = durations.filter((d) => d > settings.sla).length;
    lines.push(
      `VARIANT ${v.number} count ${n} share ${percentage(n, cases.length)} length ${v.trace.length} first ${first.id} duration ${fraction(sum(durations), n)} late ${late} fitness ${fraction(fitness(replay.cases.get(first.id)!))} ${v.keep ? 'KEEP' : 'DROP'} ${v.trace.join(',')}`,
    );
    if (v.keep) {
      keptVariants++;
      keptCases += n;
      keptEvents += n * v.trace.length;
    }
  }
  lines.push(
    `FILTER min_follows ${settings.filter} variants ${keptVariants} of ${variants.length} cases ${keptCases} of ${cases.length} events ${keptEvents} of ${eventCount}`,
  );
  return lines;
}
function directlyFollowsReport(cases: Case[], activities: string[], follows: Counts): string[] {
  const starts = new Map<string, number>();
  const ends = new Map<string, number[]>();
  const edges = new Map<string, Edge>();
  for (const item of cases) {
    increment(starts, item.trace[0]);
    const end = item.trace.at(-1)!;
    let durations = ends.get(end);
    if (!durations) {
      durations = [];
      ends.set(end, durations);
    }
    durations.push(item.duration);
    for (let i = 1; i < item.events.length; i++) {
      const a = item.events[i - 1];
      const b = item.events[i];
      const key = pairKey(a.activity, b.activity);
      let edge = edges.get(key);
      if (!edge) {
        edge = { from: a.activity, to: b.activity, count: 0, cases: new Set(), waits: [] };
        edges.set(key, edge);
      }
      edge.count++;
      edge.cases.add(item.id);
      edge.waits.push(b.time - a.time);
    }
  }
  const lines: string[] = [];
  for (const [a, n] of [...starts].sort((a, b) => b[1] - a[1] || nameOrder(a[0], b[0]))) {
    lines.push(`START ${a} count ${n}`);
  }
  for (const [a, durations] of [...ends].sort(
    (a, b) => b[1].length - a[1].length || nameOrder(a[0], b[0]),
  )) {
    lines.push(
      `END ${a} count ${durations.length} duration ${fraction(sum(durations), durations.length)}`,
    );
  }
  for (const e of [...edges.values()].sort((a, b) => b.count - a.count || pairOrder(a, b))) {
    lines.push(
      `EDGE ${e.from} ${e.to} count ${e.count} cases ${e.cases.size} mean ${fraction(sum(e.waits), e.waits.length)} min ${Math.min(...e.waits)} max ${Math.max(...e.waits)}`,
    );
  }
  lines.push(...footprint(activities, (a, b) => basicRelation(follows, a, b)));
  return lines;
}
function conformanceReport(results: NetResult[], cases: Case[]): string[] {
  const reference = results[0].net;
  const lines = [
    `MODEL places ${reference.places.length} transitions ${reference.transitions.length} arcs ${reference.arcs.length}`,
  ];
  for (const { name, reachability: r } of results) {
    lines.push(
      `REACHABILITY ${name} markings ${r.markings} edges ${r.edges} unsafe ${r.unsafe} deadlocks ${r.deadlocks} stuck ${r.stuck} final ${r.final ? 'yes' : 'no'} dead ${list(r.dead)} sound ${r.sound ? 'yes' : 'no'}`,
    );
  }
  for (const { name, footprint: r } of results) {
    lines.push(
      `FOOTPRINT ${name} activities ${r.activities} cells ${r.cells} differing ${r.differing} fitness ${fraction(r.fitness)}`,
    );
    if (name === 'reference') lines.push(...r.differences);
  }
  for (const { name, precision: r } of results) {
    lines.push(
      `PRECISION ${name} prefixes ${r.prefixes} allowed ${r.allowed} escaping ${r.escaping} precision ${fraction(r.value)}`,
    );
    for (const [t, n] of [...r.escapes].sort((a, b) => b[1] - a[1] || nameOrder(a[0], b[0]))) {
      lines.push(`ESCAPE ${name} ${t} weight ${n}`);
    }
  }
  for (const { name, net, replay } of results) {
    const r = replay.totals;
    lines.push(
      `REPLAY ${name} cases ${cases.length} fitting ${r.fitting} skipped ${r.skipped} missing ${r.missing} remaining ${r.remaining} consumed ${r.consumed} produced ${r.produced} fitness ${fraction(fitness(r))}`,
    );
    for (let p = 0; p < net.places.length; p++) {
      const s = r.places[p];
      lines.push(
        `PLACE ${name} ${net.places[p]} missing ${s.missing} remaining ${s.remaining} deviating ${s.deviating} tokens ${s.waitingCount} mean ${s.waitingCount ? fraction(s.waitingTotal, s.waitingCount) : '-'} max ${s.waitingCount ? s.waitingMaximum : '-'}`,
      );
    }
    for (let p = 0; p < net.places.length; p++) {
      const outputs = net.transitions.filter((t) => net.inputs.get(t)!.includes(p));
      if (outputs.length >= 2) {
        lines.push(
          `ROUTE ${name} ${net.places[p]} ${outputs.map((t) => `${t}=${r.places[p].consumptions.get(t) ?? 0}`).join(',')}`,
        );
      }
    }
  }
  return lines;
}
function conformanceCsv(cases: Case[], replay: Replay): string[] {
  const lines = ['case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness'];
  for (const item of cases) {
    const r = replay.cases.get(item.id)!;
    lines.push(
      [
        item.id,
        item.variant,
        item.events.length,
        r.skipped,
        r.missing,
        r.remaining,
        r.consumed,
        r.produced,
        fraction(fitness(r)),
      ].join(','),
    );
  }
  return lines;
}
function resourceReport(cases: Case[], resources: string[]): string[] {
  const statistics = new Map<
    string,
    { events: number; cases: Set<string>; work: Map<string, number> }
  >(resources.map((r) => [r, { events: 0, cases: new Set(), work: new Map() }]));
  const handovers = new Map<
    string,
    { from: string; to: string; count: number; cases: Set<string> }
  >();
  const subcontracting: Counts = new Map();
  const together: Counts = new Map();
  let total = 0;
  let self = 0;
  for (const item of cases) {
    const present = unique(item.events.map((e) => e.resource));
    for (const e of item.events) {
      const s = statistics.get(e.resource)!;
      s.events++;
      s.cases.add(item.id);
      increment(s.work, e.activity);
    }
    for (let i = 0; i < present.length; i++) {
      for (let j = i + 1; j < present.length; j++) {
        increment(together, pairKey(present[i], present[j]));
      }
    }
    for (let i = 1; i < item.events.length; i++) {
      const from = item.events[i - 1].resource;
      const to = item.events[i].resource;
      const key = pairKey(from, to);
      let h = handovers.get(key);
      if (!h) {
        h = { from, to, count: 0, cases: new Set() };
        handovers.set(key, h);
      }
      h.count++;
      h.cases.add(item.id);
      total++;
      if (from === to) self++;
      if (i + 1 < item.events.length && from !== to && from === item.events[i + 1].resource) {
        increment(subcontracting, key);
      }
    }
  }
  const lines: string[] = [];
  resources.forEach((r, i) => {
    const s = statistics.get(r)!;
    const work = [...s.work].sort((a, b) => nameOrder(a[0], b[0])).map(([a, n]) => `${a}=${n}`);
    lines.push(
      `RESOURCE ${i + 1} ${r} events ${s.events} cases ${s.cases.size} work ${work.join(',')}`,
    );
  });
  for (const h of [...handovers.values()]
    .filter((h) => h.from !== h.to)
    .sort((a, b) => b.count - a.count || pairOrder(a, b))) {
    lines.push(`HANDOVER ${h.from} ${h.to} count ${h.count} cases ${h.cases.size}`);
  }
  lines.push(
    ...table(
      resources.map((a) => resources.map((b) => handovers.get(pairKey(a, b))?.count ?? 0)),
      5,
    ),
  );
  const sortedCounts = (counts: Counts): { from: string; to: string; count: number }[] =>
    [...counts]
      .map(([key, count]) => {
        const [from, to] = key.split('\0');
        return { from, to, count };
      })
      .sort((a, b) => b.count - a.count || pairOrder(a, b));
  for (const r of sortedCounts(subcontracting)) {
    lines.push(`SUBCONTRACT ${r.from} ${r.to} count ${r.count}`);
  }
  for (const r of sortedCounts(together)) lines.push(`TOGETHER ${r.from} ${r.to} cases ${r.count}`);
  lines.push(`TOTAL handovers ${total} self ${self} other ${total - self}`);
  return lines;
}
function main(): void {
  const input = readInputs();
  const settings = parameters(input.parameters);
  const { events, errors } = validate(input.rows);
  const cases = buildCases(events);
  const activities = unique(events.map((e) => e.activity));
  const resources = unique(events.map((e) => e.resource));
  const reference = readModel();
  const fullLog = cases.map((c) => ({ trace: c.trace, weight: 1 }));
  const follows = countFollows(fullLog);
  const variants = groupVariants(cases, follows, settings);
  const discovered = alphaMining(variants);
  const prefixes = buildPrefixes(cases);
  const nets: [string, PetriNet][] = [
    ['reference', reference],
    ['alpha', discovered.alpha],
    ['alpha_plus', discovered.plus],
  ];
  const results: NetResult[] = nets.map(([name, net]) => {
    const reachability = explore(net);
    return {
      name,
      net,
      reachability,
      footprint: footprintFitness(activities, follows, net, reachability),
      precision: precision(net, prefixes),
      replay: replayAll(net, cases),
    };
  });
  writeOutputs({
    'log_summary.txt': logSummary(
      input.rows,
      events,
      errors,
      cases,
      activities,
      resources,
      reference,
      settings,
    ),
    'variants.txt': variantReport(variants, cases, events.length, settings, results[0].replay),
    'dfg.txt': directlyFollowsReport(cases, activities, follows),
    'alpha_net.txt': discovered.lines,
    'heuristic_net.txt': heuristicReport(fullLog, activities, follows, settings),
    'conformance.csv': conformanceCsv(cases, results[0].replay),
    'conformance.txt': conformanceReport(results, cases),
    'resources.txt': resourceReport(cases, resources),
  });
}
main();
