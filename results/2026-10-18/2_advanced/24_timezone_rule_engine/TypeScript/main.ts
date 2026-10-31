import { readFileSync, mkdirSync } from 'node:fs';
import * as parser from './tz_parser.ts';
import { daysInMonth, dayNumber, timeValue, splitTime } from './day_rules.ts';
import {
  expandInstances,
  adj,
  processInstances,
  abbreviation,
  type Rule,
  type RuleSet,
} from './transitions.ts';
import {
  periodIndex,
  periodRange,
  resolveLocal,
  type Period,
  type Transition,
  type Candidate,
} from './resolver.ts';
import * as report from './report.ts';
type Rules = { kind: 'none' | 'fixed'; save: number } | { kind: 'named'; name: string };
interface ZoneLine {
  stdOffset: number;
  rules: Rules;
  format: string;
  until: parser.Until | null;
  start: number;
  end: number;
}
interface Line {
  number: number;
  kind: string;
  fields: string[];
  block: Block | null;
  fieldError: string | null;
  error: string | null;
  rule?: Rule;
  zoneLine?: ZoneLine;
}
interface Block {
  name: string;
  lines: Line[];
  defined: boolean;
}
interface Zone {
  name: string;
  lines: ZoneLine[];
  aliases: string[];
  periods: Period[];
  transitions: Transition[];
  applied: Map<number, number>;
}
interface Database {
  lines: Line[];
  blocks: Block[];
  ruleSets: Map<string, RuleSet>;
  zones: Zone[];
  registry: Map<string, Zone>;
}
interface Settings {
  reference: number;
  workStart: number;
  workEnd: number;
}
interface Interval {
  start: number;
  end: number;
}
type Choice = 'EARLIER' | 'LATER' | null;
type Query =
  | { command: 'TOUTC'; zone: Zone; local: number; choice: Choice }
  | { command: 'CONVERT'; zone: Zone; destination: Zone; local: number; choice: Choice }
  | { command: 'TOLOCAL'; zone: Zone; time: number }
  | { command: 'OFFSET'; zone: Zone; time: number }
  | { command: 'TRANSITIONS'; zone: Zone; from: number; to: number }
  | { command: 'DURATION'; zone: Zone; first: number; second: number; words: string[] }
  | { command: 'MEETING'; day: number; zones: Zone[]; names: string[] };
const readLines = (name: string) =>
  readFileSync('input/' + name, 'ascii')
    .split('\n')
    .slice(0, -1);
function classifyLines(texts: string[]) {
  const lines: Line[] = [];
  const blocks: Block[] = [];
  let previous: Line | null = null;
  for (let index = 0; index < texts.length; index++) {
    const parsed = parser.extractLine(texts[index]);
    if (!parsed) continue;
    const kind = parsed.continuation
      ? 'continuation'
      : ['Rule', 'Zone', 'Link'].includes(parsed.fields[0])
        ? parsed.fields[0]
        : 'unknown';
    const line: Line = {
      number: index + 1,
      kind,
      fields: parsed.fields,
      block: null,
      fieldError: null,
      error: null,
    };
    if (kind === 'Zone') {
      line.block = { name: line.fields[1], lines: [line], defined: false };
      blocks.push(line.block);
    } else if (
      kind === 'continuation' &&
      previous?.block &&
      ((previous.kind === 'Zone' && previous.fields.length >= 6) ||
        (previous.kind === 'continuation' && previous.fields.length >= 4))
    ) {
      line.block = previous.block;
      line.block.lines.push(line);
    }
    lines.push(line);
    previous = line;
  }
  return { lines, blocks };
}
function checkRule(line: Line): string | null {
  const f = line.fields;
  const from = parser.year(f[2]);
  if (from === null) return 'bad year';
  const to = parser.toYear(f[3], from);
  if (to === null) return 'bad year';
  if (f[4] !== '-') return 'syntax error';
  const month = parser.month(f[5]);
  if (month === null) return 'bad month';
  const day = parser.daySpec(f[6], month);
  if (!day) return 'bad day spec';
  const at = parser.time(f[7]);
  if (!at) return 'bad time';
  const save = parser.save(f[8]);
  if (save === null) return 'bad save';
  const letter = parser.letter(f[9]);
  if (letter === null) return 'bad letter';
  line.rule = { number: line.number, name: f[1], from, to, month, day, at, save, letter, raw: f };
  return null;
}
function checkZoneLine(line: Line): string | null {
  const f = line.fields.slice(line.kind === 'Zone' ? 2 : 0);
  const stdOffset = parser.offset(f[0]);
  if (stdOffset === null) return 'bad offset';
  let rules: Rules;
  if (f[1] === '-') rules = { kind: 'none', save: 0 };
  else if (/^[0-9]/.test(f[1])) {
    const save = parser.save(f[1]);
    if (save === null) return 'bad save';
    rules = { kind: 'fixed', save };
  } else rules = { kind: 'named', name: f[1] };
  if (!parser.validFormat(f[2], rules.kind === 'named')) return 'bad format';
  const until = parser.until(f.slice(3));
  if ('error' in until) return until.error;
  line.zoneLine = {
    stdOffset,
    rules,
    format: f[2],
    until: until.value,
    start: -Infinity,
    end: Infinity,
  };
  return null;
}
function fieldError(line: Line): string | null {
  const count = line.fields.length;
  if (line.kind === 'unknown' || (line.kind === 'continuation' && !line.block)) {
    return 'syntax error';
  }
  if (line.kind === 'Rule') return count !== 10 ? 'syntax error' : checkRule(line);
  if (line.kind === 'Zone') return count < 5 || count > 9 ? 'syntax error' : checkZoneLine(line);
  if (line.kind === 'continuation') {
    return count < 3 || count > 7 ? 'syntax error' : checkZoneLine(line);
  }
  return count === 3 ? null : 'syntax error';
}
function readDatabase(): Database {
  const { lines, blocks } = classifyLines(readLines('tzdata.txt'));
  const ruleSets = new Map<string, RuleSet>();
  for (const line of lines) {
    line.error = line.fieldError = fieldError(line);
    if (line.rule && !line.error) {
      let set = ruleSets.get(line.rule.name);
      if (!set) {
        set = { name: line.rule.name, rules: [], instances: [] };
        ruleSets.set(set.name, set);
      }
      set.rules.push(line.rule);
    }
  }
  const zoneNames = new Set<string>();
  for (const line of lines) {
    if (line.fieldError || !line.zoneLine) continue;
    if (line.kind === 'Zone') {
      const duplicate = zoneNames.has(line.fields[1]);
      zoneNames.add(line.fields[1]);
      if (duplicate) {
        line.error = 'duplicate zone ' + line.fields[1];
        continue;
      }
    }
    const data = line.zoneLine;
    if (data.rules.kind === 'named' && !ruleSets.has(data.rules.name)) {
      line.error = 'unknown rule ' + data.rules.name;
      continue;
    }
    if (line.kind === 'continuation' && data.until && line.block) {
      const previous = line.block.lines[line.block.lines.indexOf(line) - 1];
      if (
        !previous.fieldError &&
        previous.zoneLine?.until &&
        data.until.nominal <= previous.zoneLine.until.nominal
      ) {
        line.error = 'until not increasing';
        continue;
      }
    }
    if (data.until && line.block?.lines.at(-1) === line) line.error = 'missing continuation';
  }
  const zones: Zone[] = [];
  for (const block of blocks) {
    block.defined = block.lines.every((line) => !line.error);
    if (block.defined) {
      zones.push({
        name: block.name,
        lines: block.lines.map((line) => line.zoneLine!),
        aliases: [],
        periods: [],
        transitions: [],
        applied: new Map(),
      });
    }
  }
  const byName = new Map(zones.map((zone) => [zone.name, zone]));
  const registry = new Map(byName);
  for (const line of lines) {
    if (line.kind !== 'Link' || line.fieldError) continue;
    const [, target, alias] = line.fields;
    const zone = byName.get(target);
    if (!zone) line.error = 'unknown link target ' + target;
    else if (registry.has(alias)) line.error = 'duplicate link ' + alias;
    else {
      registry.set(alias, zone);
      zone.aliases.push(alias);
    }
  }
  for (const set of ruleSets.values()) set.instances = expandInstances(set.rules);
  return { lines, blocks, zones, ruleSets, registry };
}
function buildPeriods(zone: Zone, ruleSets: Map<string, RuleSet>) {
  let start = -Infinity;
  for (const line of zone.lines) {
    line.start = start;
    const switches: { time: number; save: number; letter: string }[] = [];
    if (line.rules.kind !== 'named') {
      const save = line.rules.save;
      line.end = line.until
        ? line.until.nominal - adj(line.until.time.type, line.stdOffset, save)
        : Infinity;
      switches.push({ time: start, save, letter: '' });
    } else {
      const instances = ruleSets.get(line.rules.name)!.instances;
      const processed = processInstances(instances, line.stdOffset, start, line.until);
      const initial = processed.preStart;
      switches.push({
        time: start,
        save: initial?.save ?? 0,
        letter: initial?.letter ?? instances.find((i) => i.save === 0)?.letter ?? '',
      });
      for (const { time, instance } of processed.applied) {
        switches.push({ time, save: instance.save, letter: instance.letter });
        zone.applied.set(instance.rule.number, (zone.applied.get(instance.rule.number) ?? 0) + 1);
      }
      line.end = processed.end;
    }
    for (const item of switches) {
      const period: Period = {
        start: item.time,
        offset: line.stdOffset + item.save,
        dst: item.save !== 0,
        abbreviation: abbreviation(line.format, item.save, item.letter),
      };
      const previous = zone.periods.at(-1);
      if (
        previous &&
        previous.offset === period.offset &&
        previous.dst === period.dst &&
        previous.abbreviation === period.abbreviation
      ) {
        continue;
      }
      zone.periods.push(period);
    }
    start = line.end;
  }
  zone.transitions = zone.periods
    .slice(1)
    .map((after, i) => ({ time: after.start, before: zone.periods[i], after }));
}
function queryValue(text: string, kind: string) {
  const [y, m, d, h, mi, s] = text.match(/[0-9]+/g)!.map(Number);
  if (y < 1800 || y > 2099) return null;
  if (kind === 'year') return y;
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
  if (kind === 'date') return dayNumber(y, m, d);
  return h > 23 || mi > 59 || s > 59 ? null : timeValue(y, m, d, h, mi, s);
}
function readSettings(): Settings {
  const rows = readLines('params.txt').map((line) => line.split(' '));
  const clock = (text: string) => {
    const [h, m] = text.split(':').map(Number);
    return h * 3600 + m * 60;
  };
  return {
    reference: queryValue(rows[0][1], 'utc')!,
    workStart: clock(rows[1][1]),
    workEnd: clock(rows[1][2]),
  };
}
function checkQuery(text: string, registry: Map<string, Zone>): Query | { error: string } {
  const [command, ...tokens] = text.split(' ');
  let choice: Choice = null;
  if (
    (command === 'TOUTC' || command === 'CONVERT') &&
    (tokens.at(-1) === 'EARLIER' || tokens.at(-1) === 'LATER')
  ) {
    choice = tokens.pop() === 'EARLIER' ? 'EARLIER' : 'LATER';
  }
  const forms: Record<string, string[]> = {
    TOUTC: ['zone', 'local'],
    TOLOCAL: ['zone', 'utc'],
    CONVERT: ['zone', 'zone', 'local'],
    OFFSET: ['zone', 'utc'],
    TRANSITIONS: ['zone', 'year', 'year'],
    DURATION: ['zone', 'local', 'local'],
  };
  const kinds =
    command === 'MEETING' ? ['date', ...tokens.slice(1).map(() => 'zone')] : forms[command];
  const zones: Zone[] = [];
  const values: number[] = [];
  for (let i = 0; i < tokens.length; i++) {
    if (kinds[i] === 'zone') {
      const zone = registry.get(tokens[i]);
      if (!zone) return { error: 'ERROR unknown zone ' + tokens[i] };
      zones.push(zone);
    } else {
      const value = queryValue(tokens[i], kinds[i]);
      if (value === null) return { error: 'ERROR invalid value ' + tokens[i] };
      values.push(value);
    }
  }
  const zone = zones[0];
  switch (command) {
    case 'TOUTC':
      return { command, zone, local: values[0], choice };
    case 'CONVERT':
      return { command, zone, destination: zones[1], local: values[0], choice };
    case 'TOLOCAL':
    case 'OFFSET':
      return { command, zone, time: values[0] };
    case 'TRANSITIONS':
      return values[0] > values[1]
        ? { error: 'ERROR invalid range' }
        : { command, zone, from: values[0], to: values[1] };
    case 'DURATION':
      return { command, zone, first: values[0], second: values[1], words: tokens.slice(1) };
    default:
      return { command: 'MEETING', day: values[0], zones, names: tokens.slice(1) };
  }
}
function selectLocal(zone: Zone, local: number, choice: Choice): Candidate | { error: string } {
  const { candidates, gap } = resolveLocal(zone, local);
  if (!candidates.length) {
    return {
      error: `NONEXISTENT gap ${report.localTime(gap!.time + gap!.before.offset)} to ${report.localTime(gap!.time + gap!.after.offset)} at ${report.utc(gap!.time)}`,
    };
  }
  if (candidates.length === 1 || choice) {
    return candidates[choice === 'LATER' ? candidates.length - 1 : 0];
  }
  return {
    error:
      'AMBIGUOUS ' +
      candidates.map((c) => `${report.utc(c.time)} (${report.state(c.period)})`).join(' or '),
  };
}
function shifts(changes: Transition[]) {
  let gaps = 0;
  let overlaps = 0;
  let unchanged = 0;
  for (const t of changes) {
    const d = t.after.offset - t.before.offset;
    if (d > 0) gaps++;
    else if (d < 0) overlaps++;
    else unchanged++;
  }
  return `gaps ${gaps}, overlaps ${overlaps}, no shift ${unchanged}`;
}
function transitionLine(t: Transition) {
  const d = t.after.offset - t.before.offset;
  const kind =
    d > 0 ? 'gap ' + report.duration(d) : d < 0 ? 'overlap ' + report.duration(-d) : 'no shift';
  return `${report.change(t)} (local ${report.localTime(t.time + t.before.offset)} -> ${report.localTime(t.time + t.after.offset)}, ${kind})`;
}
function mergeIntervals(intervals: Interval[]) {
  const result: Interval[] = [];
  for (const interval of intervals.sort((a, b) => a.start - b.start || a.end - b.end)) {
    const last = result.at(-1);
    if (last && interval.start <= last.end) last.end = Math.max(last.end, interval.end);
    else result.push({ ...interval });
  }
  return result;
}
function intersectIntervals(first: Interval[], second: Interval[]) {
  const result: Interval[] = [];
  let a = 0;
  let b = 0;
  while (a < first.length && b < second.length) {
    const start = Math.max(first[a].start, second[b].start);
    const end = Math.min(first[a].end, second[b].end);
    if (start < end) result.push({ start, end });
    if (first[a].end < second[b].end) a++;
    else b++;
  }
  return mergeIntervals(result);
}
function workingHours(zone: Zone, day: number, settings: Settings) {
  const intervals: Interval[] = [];
  for (let i = 0; i < zone.periods.length; i++) {
    const offset = zone.periods[i].offset;
    const range = periodRange(zone.periods, i);
    const start = Math.max(range.start, day * 86400 + settings.workStart - offset);
    const end = Math.min(range.end, day * 86400 + settings.workEnd - offset);
    if (start < end) intervals.push({ start, end });
  }
  return mergeIntervals(intervals);
}
function processQuery(
  text: string,
  database: Database,
  settings: Settings,
  transitionBlocks: string[][],
) {
  const q = checkQuery(text, database.registry);
  if ('error' in q) return q.error;
  if (q.command === 'TOUTC' || q.command === 'CONVERT') {
    const c = selectLocal(q.zone, q.local, q.choice);
    if ('error' in c) return c.error;
    if (q.command === 'TOUTC') return `${report.utc(c.time)} (${report.state(c.period)})`;
    const p = q.destination.periods[periodIndex(q.destination.periods, c.time)];
    const local = c.time + p.offset;
    const shift = Math.floor(local / 86400) - Math.floor(q.local / 86400);
    return `${report.localTime(local)} (${report.state(p)}) at ${report.utc(c.time)}, day shift ${shift > 0 ? '+' : ''}${shift}`;
  }
  if (q.command === 'TOLOCAL') {
    const p = q.zone.periods[periodIndex(q.zone.periods, q.time)];
    return `${report.localTime(q.time + p.offset)} (${report.state(p)})`;
  }
  if (q.command === 'OFFSET') {
    const i = periodIndex(q.zone.periods, q.time);
    const p = q.zone.periods;
    return (
      report.state(p[i]) +
      (i ? ' since ' + report.utc(p[i].start) : '') +
      (p[i + 1] ? ' until ' + report.utc(p[i + 1].start) : '')
    );
  }
  if (q.command === 'TRANSITIONS') {
    const start = timeValue(q.from, 1, 1);
    const end = timeValue(q.to + 1, 1, 1);
    const selected = q.zone.transitions.filter((t) => t.time >= start && t.time < end);
    transitionBlocks.push([text, ...selected.map(transitionLine), shifts(selected)]);
    return 'transitions: ' + selected.length;
  }
  if (q.command === 'DURATION') {
    const selected: Candidate[] = [];
    for (const [i, local] of [q.first, q.second].entries()) {
      const r = resolveLocal(q.zone, local);
      if (r.candidates.length !== 1) {
        return (r.candidates.length ? 'AMBIGUOUS ' : 'NONEXISTENT ') + q.words[i];
      }
      selected.push(r.candidates[0]);
    }
    const elapsed = selected[1].time - selected[0].time;
    return `${elapsed} s (${report.duration(elapsed)}), wall clock ${report.duration(q.second - q.first)}, offset change ${report.offset(selected[1].period.offset - selected[0].period.offset)}`;
  }
  let intervals = workingHours(q.zones[0], q.day, settings);
  for (const zone of q.zones.slice(1)) {
    intervals = intersectIntervals(intervals, workingHours(zone, q.day, settings));
  }
  return intervals.length
    ? intervals
        .map(({ start, end }) => {
          const locals = q.zones.map((zone, i) => {
            const p = zone.periods[periodIndex(zone.periods, start)];
            return `${q.names[i]} ${report.localTime(start + p.offset)} ${p.abbreviation}`;
          });
          return `${report.utc(start)} to ${report.utc(end)} (${report.duration(end - start)}) [${locals.join(', ')}]`;
        })
        .join('; ')
    : 'NONE';
}
function databaseSummary(db: Database) {
  const rules = db.lines.filter((l) => l.kind === 'Rule');
  const links = db.lines.filter((l) => l.kind === 'Link');
  const validRules = rules.filter((l) => !l.error).length;
  const validLinks = links.filter((l) => !l.error).length;
  const usage = new Map<string, number>();
  for (const name of db.ruleSets.keys()) usage.set(name, 0);
  for (const zone of db.zones) {
    const names = new Set<string>();
    for (const line of zone.lines) if (line.rules.kind === 'named') names.add(line.rules.name);
    for (const name of names) usage.set(name, usage.get(name)! + 1);
  }
  const unused = [...usage].filter(([, n]) => !n).map(([name]) => name);
  const invalid = db.blocks
    .filter((b) => !b.defined)
    .map((b) => `${b.name} (line ${b.lines[0].number})`);
  const body = [
    `rule lines: ${validRules} valid, ${rules.length - validRules} invalid`,
    `zones: ${db.zones.length} defined, ${db.blocks.length - db.zones.length} invalid`,
    `zone lines: ${db.zones.reduce((n, z) => n + z.lines.length, 0)} in defined zones`,
    `links: ${validLinks} defined, ${links.length - validLinks} invalid`,
    `errors: ${db.lines.filter((l) => l.error).length}`,
    'unused rules: ' + (unused.join(' ') || 'none'),
    'invalid zones: ' + (invalid.join(', ') || 'none'),
  ];
  for (const set of db.ruleSets.values()) {
    const from = Math.min(...set.rules.map((r) => r.from));
    const to = set.rules.some((r) => r.raw[3] === 'max')
      ? 'max'
      : Math.max(...set.rules.map((r) => r.to));
    body.push(
      `rule set ${set.name}: lines ${set.rules.length}, years ${from}-${to}, zones ${usage.get(set.name)}`,
    );
  }
  return ['DATABASE', ...body.map((s) => '  ' + s)];
}
function zoneSummary(zone: Zone, ruleSets: Map<string, RuleSet>, reference: number) {
  const lines = ['aliases: ' + (zone.aliases.join(' ') || 'none')];
  const names = new Set<string>();
  for (const [i, line] of zone.lines.entries()) {
    const rules =
      line.rules.kind === 'named'
        ? line.rules.name
        : line.rules.kind === 'none'
          ? '-'
          : report.clock(line.rules.save);
    let text = `line ${i + 1}: ${report.offset(line.stdOffset)} ${rules} ${line.format}`;
    if (i) text += ' from ' + report.utc(line.start);
    if (line.until) {
      const u = line.until;
      text += ` until ${u.rawYear} ${u.monthName} ${u.dayText} ${report.clock(u.time.value)}${u.time.type} = ${report.utc(line.end)}`;
    }
    lines.push(
      text +
        ', transitions ' +
        zone.transitions.filter((t) => t.time >= line.start && t.time < line.end).length,
    );
  }
  for (const line of zone.lines) {
    if (line.rules.kind !== 'named' || names.has(line.rules.name)) continue;
    names.add(line.rules.name);
    for (const r of ruleSets.get(line.rules.name)!.rules) {
      lines.push(
        `rule ${r.name} ${r.raw[2]} ${r.raw[3]} ${r.raw[5]} ${r.raw[6]} ${report.clock(r.at.value)}${r.at.type} ${report.clock(r.save)} ${r.raw[9]}, applied ${zone.applied.get(r.number) ?? 0}`,
      );
    }
  }
  const states = new Map<string, number>();
  const dstYears: number[] = [];
  let minimum = zone.periods[0].offset;
  let maximum = minimum;
  for (const p of zone.periods) {
    minimum = Math.min(minimum, p.offset);
    maximum = Math.max(maximum, p.offset);
    const state = report.state(p);
    states.set(state, (states.get(state) ?? 0) + 1);
    if (p.dst) dstYears.push(splitTime(p.start).year);
  }
  lines.push(`offset range: ${report.offset(minimum)} to ${report.offset(maximum)}`);
  for (const [state, n] of states) lines.push(`state ${state}, periods ${n}`);
  const p = zone.periods[periodIndex(zone.periods, reference)];
  const lineIndex = zone.lines.findIndex((l) => l.start <= reference && reference < l.end);
  lines.push(
    `reference: ${report.localTime(reference + p.offset)} (${report.state(p)}), line ${lineIndex + 1}`,
  );
  const previous = zone.transitions.filter((t) => t.time <= reference).at(-1);
  const next = zone.transitions.find((t) => t.time > reference);
  lines.push(
    'previous transition: ' + (previous ? report.change(previous) : 'none'),
    'next transition: ' + (next ? report.change(next) : 'none'),
    `transitions: ${zone.transitions.length}, ${shifts(zone.transitions)}`,
    dstYears.length
      ? `dst years: ${Math.min(...dstYears)}-${Math.max(...dstYears)}`
      : 'dst years: none',
  );
  const year = splitTime(reference).year;
  const yearStart = timeValue(year, 1, 1);
  const yearEnd = timeValue(year + 1, 1, 1);
  const intervals: Interval[] = [];
  for (const [i, p] of zone.periods.entries()) {
    if (!p.dst) continue;
    const range = periodRange(zone.periods, i);
    const start = Math.max(yearStart, range.start);
    const end = Math.min(yearEnd, range.end);
    if (start < end) intervals.push({ start, end });
  }
  let total = 0;
  for (const { start, end } of mergeIntervals(intervals)) {
    total += end - start;
    lines.push(
      `dst period: ${report.utc(start)} to ${report.utc(end)} (${report.duration(end - start)})`,
    );
  }
  lines.push(`dst total ${year}: ${report.duration(total)}`);
  return ['ZONE ' + zone.name, ...lines.map((s) => '  ' + s)];
}
function main() {
  const db = readDatabase();
  const settings = readSettings();
  const transitionBlocks: string[][] = [];
  for (const zone of db.zones) buildPeriods(zone, db.ruleSets);
  const answers = readLines('queries.txt').map(
    (text) => text + ' => ' + processQuery(text, db, settings, transitionBlocks),
  );
  const summaries = [
    databaseSummary(db),
    ...db.zones
      .toSorted((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
      .map((z) => zoneSummary(z, db.ruleSets, settings.reference)),
  ];
  mkdirSync('output', { recursive: true });
  report.writeLines('answers.txt', answers);
  report.writeBlocks('transitions.txt', transitionBlocks);
  report.writeBlocks('zone_summary.txt', summaries);
  report.writeLines(
    'errors.txt',
    db.lines.filter((l) => l.error).map((l) => `line ${l.number}: ${l.error}`),
  );
}
main();
