import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { Calendar, dateParts, formatDate, parseDate, type BusinessRule } from './dates_calendar.ts';
import { yearFraction, type DayCount } from './daycount.ts';
import { couponSchedule, type Frequency } from './schedule.ts';
import { bisect, dirty, yieldAnalytics, type YieldAnalytics } from './pricing.ts';
import { bootstrap, Curve, type CurveFlow, type Pillar } from './curve.ts';

type BondType = 'FIXED' | 'ZERO' | 'AMORT' | 'FRN';
interface Scenario {
  name: string;
  shifts: number[];
  line: number;
}
interface Limit {
  kind: string;
  args: string[];
}
interface Parameters {
  valuation: number;
  settlementDays: number;
  scenarios: Scenario[];
  limits: Limit[];
}
interface Sink {
  day: number;
  amount: number;
}
interface Call {
  day: number;
  price: number;
}
interface Options {
  eom: boolean;
  long: boolean;
  lag: number | null;
  cap: number | null;
  floor: number | null;
  sinks: Sink[];
  calls: Call[];
}
interface Flow {
  period: number;
  start: number;
  end: number;
  payment: number;
  numerator: number;
  denominator: number;
  rate: number;
  opening: number;
  coupon: number;
  principal: number;
  cash: number;
}
interface Bond {
  id: string;
  type: BondType;
  issue: number;
  maturity: number;
  coupon: number;
  frequency: Frequency;
  daycount: DayCount;
  convention: BusinessRule;
  face: number;
  options: Options;
  schedule: number[];
  cashflows: Flow[];
}
interface DatedFlow extends Flow {
  days: number;
}
interface SettlementValues {
  remaining: Flow[];
  flows: DatedFlow[];
  outstanding: number;
  price: number;
  accrued: number;
  cleanAmount: number;
  marketValue: number;
  target: number;
  fraction: number;
  amounts: number[];
  curveFlows: CurveFlow[];
}
interface PricedBond extends Bond, SettlementValues, YieldAnalytics {
  ytw: number;
  workout: number;
  wal: number;
  nextPayment: number;
  curveClean: number;
  zspread: number;
}
interface Holding {
  bond: PricedBond;
  units: number;
  book: number;
}
interface Portfolio {
  name: string;
  positions: Holding[];
}
interface Fixing {
  date: number;
  rate: number;
}
type Report = (file: string, line: number, key: string, message: string) => void;
const TYPES: BondType[] = ['FIXED', 'ZERO', 'AMORT', 'FRN'];
const BUCKETS = ['0-1Y', '1-3Y', '3-5Y', '5-10Y', '10Y+'];
const isType = (text: string): text is BondType =>
  text === 'FIXED' || text === 'ZERO' || text === 'AMORT' || text === 'FRN';
const isFrequency = (n: number): n is Frequency => n === 1 || n === 2 || n === 4 || n === 12;
const isDayCount = (s: string): s is DayCount =>
  ['30/360', '30E/360', 'ACT/360', 'ACT/365F', 'ACT/ACT'].includes(s);
const isRule = (s: string): s is BusinessRule =>
  ['FOLLOWING', 'MODIFIED_FOLLOWING', 'PRECEDING', 'UNADJUSTED'].includes(s);
const compare = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
const roundRatio = (a: number, b: number) => Math.floor((2 * a + b) / (2 * b));
const thousandths = (s: string) => Number(s.replace('.', ''));
const readLines = (name: string) => readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);
const readCsv = (name: string) =>
  readLines(name)
    .slice(1)
    .map((text, i) => ({ fields: text.split(','), line: i + 2 }));
function sum(values: number[]): number {
  let total = 0;
  for (const n of values) total += n;
  return total;
}
function hundredths(value: number): string {
  const n = Math.abs(value);
  return (value < 0 ? '-' : '') + Math.floor(n / 100) + '.' + String(n % 100).padStart(2, '0');
}
function decimal(value: number, digits: number): string {
  let scale = 1;
  for (let i = 0; i < digits; i++) scale *= 10;
  const rounded = Math.floor(Math.abs(value) * scale + 0.5);
  return (
    (value < 0 && rounded !== 0 ? '-' : '') +
    Math.floor(rounded / scale) +
    '.' +
    String(rounded % scale).padStart(digits, '0')
  );
}
const percent = (n: number) => decimal(n * 100, 4);
const amount = (cents: number) => decimal(cents / 100, 2);
function knownDate(text: string): number {
  const date = parseDate(text);
  if (date === null) throw new Error('Expected a valid input date');
  return date;
}
function readParameters(): Parameters {
  const result: Parameters = { valuation: 0, settlementDays: 0, scenarios: [], limits: [] };
  for (const [i, line] of readLines('params.txt').entries()) {
    const [kind, ...words] = line.split(' ');
    if (kind === 'valuation_date') result.valuation = knownDate(words[0]);
    else if (kind === 'settlement_days') result.settlementDays = Number(words[0]);
    else if (kind === 'scenario') {
      result.scenarios.push({ name: words[0], shifts: words.slice(1).map(Number), line: i + 1 });
    } else result.limits.push({ kind: words[0], args: words.slice(1) });
  }
  return result;
}
function validatePillars(settlement: number, report: Report): Pillar[] {
  const seen = new Set<string>();
  const pillars: Pillar[] = [];
  for (const {
    fields: [text, couponText, frequencyText],
    line,
  } of readCsv('curve_quotes.csv')) {
    const duplicate = seen.has(text);
    const maturity = parseDate(text);
    const frequency = Number(frequencyText);
    seen.add(text);
    if (duplicate) report('curve_quotes.csv', line, text, 'duplicate pillar');
    else if (maturity === null) report('curve_quotes.csv', line, text, 'invalid date');
    else if (maturity <= settlement) {
      report('curve_quotes.csv', line, text, 'pillar not after settlement');
    } else if (!isFrequency(frequency)) report('curve_quotes.csv', line, text, 'invalid frequency');
    else pillars.push({ maturity, frequency, coupon: Number(couponText) });
  }
  return pillars.sort((a, b) => a.maturity - b.maturity);
}
function validateScenarios(parameters: Parameters, count: number, report: Report): Scenario[] {
  const seen = new Set<string>();
  const scenarios: Scenario[] = [];
  for (const scenario of parameters.scenarios) {
    const duplicate = seen.has(scenario.name);
    seen.add(scenario.name);
    const error = duplicate
      ? 'duplicate scenario'
      : scenario.shifts.length !== count
        ? 'wrong number of shifts'
        : null;
    if (error) report('params.txt', scenario.line, scenario.name, error);
    else scenarios.push(scenario);
  }
  return scenarios;
}
interface RawOptions {
  eom: boolean;
  long: boolean;
  lag: number | null;
  cap: number | null;
  floor: number | null;
  sinks: { date: string; amount: number }[];
  calls: { date: string; price: number }[];
}
function readOptions(text: string, type: BondType): RawOptions | null {
  const allowed = new Set([
    'EOM',
    'LONG',
    ...(type === 'FIXED'
      ? ['CALL']
      : type === 'AMORT'
        ? ['SINK']
        : type === 'FRN'
          ? ['LAG', 'CAP', 'FLOOR']
          : []),
  ]);
  const values = new Map<string, string>();
  const sinks: RawOptions['sinks'] = [];
  const calls: RawOptions['calls'] = [];
  if (text !== '-') {
    for (const item of text.split(';')) {
      const equals = item.indexOf('=');
      const key = equals < 0 ? item : item.slice(0, equals);
      const value = equals < 0 ? '' : item.slice(equals + 1);
      if (!allowed.has(key) || (key !== 'SINK' && key !== 'CALL' && values.has(key))) return null;
      values.set(key, value);
      if (key === 'SINK') {
        const [date, cents] = value.split(':');
        sinks.push({ date, amount: Number(cents) });
      }
      if (key === 'CALL') {
        const [date, price] = value.split(':');
        calls.push({ date, price: thousandths(price) });
      }
    }
  }
  const lag = values.has('LAG') ? Number(values.get('LAG')) : null;
  const cap = values.has('CAP') ? Number(values.get('CAP')) : null;
  const floor = values.has('FLOOR') ? Number(values.get('FLOOR')) : null;
  if (
    type === 'FRN' &&
    (lag === null ||
      lag < 1 ||
      lag > 5 ||
      (cap !== null && cap > 1200) ||
      (floor !== null && floor > (cap ?? 1200)))
  ) {
    return null;
  }
  return { eom: values.has('EOM'), long: values.has('LONG'), lag, cap, floor, sinks, calls };
}
function indexRate(fixings: Fixing[], date: number): number | null {
  let low = 0;
  let high = fixings.length - 1;
  let found = -1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (fixings[mid].date <= date) {
      found = mid;
      low = mid + 1;
    } else high = mid - 1;
  }
  return found < 0 ? null : fixings[found].rate;
}
function buildCashflows(
  bond: Omit<Bond, 'cashflows'>,
  calendar: Calendar,
  fixings: Fixing[],
): Flow[] | null {
  const flows: Flow[] = [];
  const sinks = new Map(bond.options.sinks.map((s) => [s.day, s.amount]));
  let opening = bond.face;
  for (let period = 1; period < bond.schedule.length; period++) {
    const start = bond.schedule[period - 1];
    const end = bond.schedule[period];
    const [numerator, denominator] = yearFraction(start, end, bond.daycount);
    const payment = calendar.adjust(end, bond.convention);
    let rate = bond.coupon;
    if (bond.type === 'FRN') {
      const lag = bond.options.lag;
      if (lag === null) throw new Error('FRN must have a fixing lag');
      const fixing = indexRate(
        fixings,
        calendar.shift(calendar.adjust(start, bond.convention), -lag),
      );
      if (fixing === null) return null;
      rate += fixing;
      if (bond.options.floor !== null) rate = Math.max(rate, bond.options.floor);
      if (bond.options.cap !== null) rate = Math.min(rate, bond.options.cap);
    }
    const principal = period === bond.schedule.length - 1 ? opening : (sinks.get(end) ?? 0);
    const coupon = roundRatio(opening * rate * numerator, 10000 * denominator);
    flows.push({
      period,
      start,
      end,
      payment,
      numerator,
      denominator,
      rate,
      opening,
      coupon,
      principal,
      cash: coupon + principal,
    });
    opening -= principal;
  }
  return flows;
}
function validateBond(
  fields: string[],
  calendar: Calendar,
  fixings: Fixing[],
): { bond: Bond } | { error: string } {
  const [
    id,
    type,
    issueText,
    maturityText,
    couponText,
    frequencyText,
    daycount,
    convention,
    faceText,
    optionText,
  ] = fields;
  if (!isType(type)) return { error: 'unknown type' };
  const issue = parseDate(issueText);
  const maturity = parseDate(maturityText);
  if (issue === null || maturity === null) return { error: 'invalid date' };
  if (maturity <= issue) return { error: 'maturity not after issue' };
  const frequency = Number(frequencyText);
  const coupon = Number(couponText);
  const face = Number(faceText);
  if (!isFrequency(frequency)) return { error: 'invalid frequency' };
  if (!isDayCount(daycount)) return { error: 'unknown day count' };
  if (!isRule(convention)) return { error: 'unknown business day rule' };
  if (face % 100000 !== 0 || face > 10000000) return { error: 'invalid face' };
  if (coupon > 1200 || (type === 'ZERO' && coupon !== 0)) return { error: 'invalid coupon' };
  const raw = readOptions(optionText, type);
  if (raw === null) return { error: 'invalid option' };
  const schedule = couponSchedule(issue, maturity, frequency, raw.eom, raw.long);
  const internal = new Set(schedule.slice(1, -1));
  const sinks: Sink[] = [];
  const calls: Call[] = [];
  let previous = -1;
  let total = 0;
  for (const sink of raw.sinks) {
    const day = parseDate(sink.date);
    if (day === null || !internal.has(day) || day <= previous || sink.amount === 0) {
      return { error: 'invalid sinking fund' };
    }
    sinks.push({ day, amount: sink.amount });
    previous = day;
    total += sink.amount;
  }
  if (type === 'AMORT' && (total === 0 || total >= face)) return { error: 'invalid sinking fund' };
  previous = -1;
  for (const call of raw.calls) {
    const day = parseDate(call.date);
    if (
      day === null ||
      !internal.has(day) ||
      day <= previous ||
      call.price < 100000 ||
      call.price > 110000
    ) {
      return { error: 'invalid call schedule' };
    }
    calls.push({ day, price: call.price });
    previous = day;
  }
  const options: Options = { ...raw, sinks, calls };
  const base = {
    id,
    type,
    issue,
    maturity,
    frequency,
    coupon,
    face,
    daycount,
    convention,
    options,
    schedule,
  };
  const cashflows = buildCashflows(base, calendar, fixings);
  return cashflows === null ? { error: 'missing fixing' } : { bond: { ...base, cashflows } };
}
function validateBonds(calendar: Calendar, fixings: Fixing[], report: Report): Map<string, Bond> {
  const seen = new Set<string>();
  const bonds = new Map<string, Bond>();
  for (const row of readCsv('bonds.csv')) {
    const id = row.fields[0];
    const duplicate = seen.has(id);
    seen.add(id);
    const result = duplicate
      ? { error: 'duplicate id' }
      : validateBond(row.fields, calendar, fixings);
    if ('error' in result) report('bonds.csv', row.line, id, result.error);
    else bonds.set(id, result.bond);
  }
  return bonds;
}
function settlementValues(bond: Bond, price: number, settlement: number): SettlementValues {
  const remaining = bond.cashflows.slice(bond.cashflows.findIndex((f) => f.end > settlement));
  const current = remaining[0];
  const [n, m] = yearFraction(current.start, settlement, bond.daycount);
  const accrued = (current.rate * n) / (100 * m);
  const accruedAmount = roundRatio(current.opening * current.rate * n, 10000 * m);
  const cleanAmount = roundRatio(current.opening * price, 100000);
  const [nextN, nextM] = yearFraction(settlement, current.end, bond.daycount);
  const flows = remaining
    .filter((f) => f.cash >= 1)
    .map((f) => ({ ...f, days: f.payment - settlement }));
  return {
    remaining,
    flows,
    price,
    accrued,
    cleanAmount,
    marketValue: cleanAmount + accruedAmount,
    outstanding: current.opening,
    target: price / 1000 + accrued,
    fraction: (bond.frequency * nextN) / nextM,
    amounts: remaining.map((f) => f.cash),
    curveFlows: flows.map((f) => ({ days: f.days, amount: f.cash })),
  };
}
function completeAnalytics(
  bond: Bond,
  values: SettlementValues,
  settlement: number,
  curve: Curve,
): PricedBond {
  const analytics = yieldAnalytics(
    values.amounts,
    bond.frequency,
    values.fraction,
    values.outstanding,
    values.target,
  );
  let ytw = analytics.ytm;
  let workout = bond.maturity;
  for (const call of bond.options.calls) {
    if (call.day <= settlement) continue;
    const last = values.remaining.findIndex((f) => f.end === call.day);
    const called = values.remaining.slice(0, last + 1).map((f) => f.coupon);
    called[called.length - 1] += roundRatio(values.remaining[last].opening * call.price, 100000);
    const y = bisect(
      (y) => dirty(called, bond.frequency, values.fraction, values.outstanding, y),
      0,
      1,
      values.target,
    );
    if (y < ytw) {
      ytw = y;
      workout = call.day;
    }
  }
  return {
    ...bond,
    ...values,
    ...analytics,
    ytw,
    workout,
    wal: sum(values.flows.map((f) => f.principal * f.days)) / (365 * values.outstanding),
    nextPayment: values.flows[0].payment,
    curveClean: (curve.present(values.curveFlows) * 100) / values.outstanding - values.accrued,
    zspread: curve.zspread(values.curveFlows, values.marketValue),
  };
}
function validatePrices(
  bonds: Map<string, Bond>,
  settlement: number,
  curve: Curve,
  report: Report,
): Map<string, PricedBond> {
  const seen = new Set<string>();
  const priced = new Map<string, PricedBond>();
  for (const {
    fields: [id, text],
    line,
  } of readCsv('prices.csv')) {
    const duplicate = seen.has(id);
    const bond = bonds.get(id);
    seen.add(id);
    if (!bond) report('prices.csv', line, id, 'unknown bond');
    else if (duplicate) report('prices.csv', line, id, 'duplicate price');
    else if (!(bond.issue <= settlement && settlement < bond.maturity)) {
      report('prices.csv', line, id, 'not outstanding');
    } else {
      const values = settlementValues(bond, thousandths(text), settlement);
      const value = (y: number) =>
        dirty(values.amounts, bond.frequency, values.fraction, values.outstanding, y);
      if (!(value(0) > values.target && values.target > value(1))) {
        report('prices.csv', line, id, 'yield out of range');
      } else priced.set(id, completeAnalytics(bond, values, settlement, curve));
    }
  }
  return priced;
}
function validateHoldings(
  bonds: Map<string, Bond>,
  priced: Map<string, PricedBond>,
  report: Report,
): Portfolio[] {
  const portfolios = new Map<string, Map<string, Holding>>();
  for (const {
    fields: [name, id, faceText, bookText],
    line,
  } of readCsv('holdings.csv')) {
    const face = Number(faceText);
    const bond = priced.get(id);
    if (!bonds.has(id)) report('holdings.csv', line, id, 'unknown bond');
    else if (!bond) report('holdings.csv', line, id, 'no price');
    else if (face % bond.face !== 0) report('holdings.csv', line, id, 'invalid face');
    else {
      let positions = portfolios.get(name);
      if (!positions) {
        positions = new Map();
        portfolios.set(name, positions);
      }
      let position = positions.get(id);
      if (!position) {
        position = { bond, units: 0, book: 0 };
        positions.set(id, position);
      }
      const units = face / bond.face;
      position.units += units;
      position.book += roundRatio(units * bond.outstanding * thousandths(bookText), 100000);
    }
  }
  return [...portfolios]
    .sort(([a], [b]) => compare(a, b))
    .map(([name, positions]) => ({
      name,
      positions: [...positions.values()].sort((a, b) => compare(a.bond.id, b.bond.id)),
    }));
}
function maturityBucket(days: number): string {
  return BUCKETS[days < 365 ? 0 : days < 1095 ? 1 : days < 1825 ? 2 : days < 3650 ? 3 : 4];
}
function portfolioRisk(
  portfolio: Portfolio,
  settlement: number,
  curve: Curve,
  scenarios: Scenario[],
) {
  const positions = portfolio.positions.map((p) => ({
    ...p,
    face: p.units * p.bond.face,
    outstanding: p.units * p.bond.outstanding,
    value: p.units * p.bond.marketValue,
    gain: p.units * p.bond.cleanAmount - p.book,
    dv01: (p.bond.dv01 * p.units * p.bond.outstanding) / 10000,
    days: p.bond.maturity - settlement,
  }));
  const total = sum(positions.map((p) => p.value));
  const weighted = (select: (b: PricedBond) => number) =>
    sum(positions.map((p) => p.value * select(p.bond))) / total;
  const flows: CurveFlow[] = [];
  const ladder = new Map<number, { year: number; coupon: number; principal: number }>();
  let income = 0;
  for (const p of positions) {
    for (const flow of p.bond.flows) {
      const coupon = p.units * flow.coupon;
      const principal = p.units * flow.principal;
      const year = dateParts(flow.payment)[0];
      flows.push({ days: flow.days, amount: p.units * flow.cash });
      if (flow.days <= 365) income += coupon;
      let row = ladder.get(year);
      if (!row) {
        row = { year, coupon: 0, principal: 0 };
        ladder.set(year, row);
      }
      row.coupon += coupon;
      row.principal += principal;
    }
  }
  const ladderRows = [...ladder.values()].sort((a, b) => a.year - b.year);
  const values = (c: Curve) =>
    positions.map((p) => p.units * c.present(p.bond.curveFlows, p.bond.zspread));
  const baseValues = values(curve);
  const base = sum(baseValues);
  const count = curve.days.length;
  const present = (shifts: number[]) => sum(values(curve.shifted(shifts)));
  const krd: number[] = [];
  for (let j = 0; j < count; j++) {
    const down: number[] = Array(count).fill(0);
    const up: number[] = Array(count).fill(0);
    down[j] = -0.0001;
    up[j] = 0.0001;
    krd.push((present(down) - present(up)) / (2 * 0.0001 * base));
  }
  const scenarioRows = [
    { name: 'BASE', values: baseValues, total: base, pnls: positions.map(() => 0), pnl: 0 },
  ];
  for (const scenario of scenarios) {
    const shifted = values(curve.shifted(scenario.shifts.map((s) => s * 0.0001)));
    const value = sum(shifted);
    scenarioRows.push({
      name: scenario.name,
      values: shifted,
      total: value,
      pnls: shifted.map((v, i) => v - baseValues[i]),
      pnl: value - base,
    });
  }
  let worst: (typeof scenarioRows)[number] | null = null;
  for (const row of scenarioRows.slice(1)) if (worst === null || row.pnl < worst.pnl) worst = row;
  const worstRow = worst;
  const losers =
    worstRow === null
      ? []
      : positions
          .map((p, i) => ({ id: p.bond.id, pnl: worstRow.pnls[i] }))
          .sort((a, b) => a.pnl - b.pnl || compare(a.id, b.id))
          .slice(0, 3);
  const groups = (keys: string[], select: (p: (typeof positions)[number]) => string) =>
    keys.map((key) => {
      const selected = positions.filter((p) => select(p) === key);
      const value = sum(selected.map((p) => p.value));
      return {
        key,
        count: selected.length,
        value,
        weight: (value * 100) / total,
        duration: sum(selected.map((p) => p.value * p.bond.modified)) / total,
        dv01: sum(selected.map((p) => p.dv01)),
      };
    });
  return {
    name: portfolio.name,
    positions: positions.map((p) => ({ ...p, weight: (p.value * 100) / total })),
    total,
    income,
    face: sum(positions.map((p) => p.face)),
    outstanding: sum(positions.map((p) => p.outstanding)),
    book: sum(positions.map((p) => p.book)),
    gain: sum(positions.map((p) => p.gain)),
    dv01: sum(positions.map((p) => p.dv01)),
    ytm: weighted((b) => b.ytm),
    modified: weighted((b) => b.modified),
    convexity: weighted((b) => b.convexity),
    zspread: weighted((b) => b.zspread),
    ladder: ladderRows,
    ladderCoupon: sum(ladderRows.map((r) => r.coupon)),
    ladderPrincipal: sum(ladderRows.map((r) => r.principal)),
    cashflowYield: bisect((y) => new Curve([0], [y]).present(flows), 0, 1, total),
    effective:
      (present(Array(count).fill(-0.0001)) - present(Array(count).fill(0.0001))) /
      (2 * 0.0001 * base),
    krd,
    scenarios: scenarioRows,
    worst,
    losers,
    types: groups(TYPES, (p) => p.bond.type),
    buckets: groups(BUCKETS, (p) => maturityBucket(p.days)),
  };
}
type PortfolioRisk = ReturnType<typeof portfolioRisk>;
function complianceLines(p: PortfolioRisk, limits: Limit[]): string[] {
  const lines: string[] = [];
  let breaches = 0;
  for (const { kind, args } of limits) {
    let text: string;
    let breach: boolean;
    if (kind === 'position_weight') {
      let largest = p.positions[0];
      for (const position of p.positions) if (position.value > largest.value) largest = position;
      const bound = Number(args[0]);
      breach = largest.value * 10000 > bound * p.total;
      text = `position_weight ${largest.bond.id} ${decimal(largest.weight, 4)} limit ${hundredths(bound)}`;
    } else if (kind === 'type_weight') {
      const value = sum(p.positions.filter((q) => q.bond.type === args[0]).map((q) => q.value));
      const bound = Number(args[1]);
      breach = value * 10000 > bound * p.total;
      text = `type_weight ${args[0]} ${decimal((value * 100) / p.total, 4)} limit ${hundredths(bound)}`;
    } else if (kind === 'max_maturity') {
      const years = Number(args[0]);
      const count = p.positions.filter((q) => q.days > 365 * years).length;
      breach = count > 0;
      text = `max_maturity ${years}Y positions ${count}`;
    } else if (kind === 'min_yield') {
      const bound = Number(args[0]);
      breach = p.ytm * 10000 < bound;
      text = `min_yield ${percent(p.ytm)} limit ${hundredths(bound)}`;
    } else if (kind === 'duration') {
      const low = Number(args[0]);
      const high = Number(args[1]);
      breach = p.modified < low / 100 || p.modified > high / 100;
      text = `duration ${decimal(p.modified, 4)} range ${hundredths(low)} ${hundredths(high)}`;
    } else {
      const bound = Number(args[0]);
      breach = p.dv01 * 100 > bound;
      text = `dv01 ${decimal(p.dv01, 2)} limit ${hundredths(bound)}`;
    }
    if (breach) breaches++;
    lines.push(`${p.name} ${text} ${breach ? 'BREACH' : 'PASS'}`);
  }
  lines.push(`${p.name} breaches ${breaches}`);
  return lines;
}
function cashflowLines(bonds: Map<string, Bond>): string[] {
  const lines = ['bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal'];
  for (const b of [...bonds.values()].sort((a, b) => compare(a.id, b.id))) {
    for (const f of b.cashflows) {
      if (f.cash >= 1) {
        lines.push(
          [
            b.id,
            f.period,
            formatDate(f.start),
            formatDate(f.end),
            formatDate(f.payment),
            decimal(f.numerator / f.denominator, 6),
            f.rate,
            f.opening,
            f.coupon,
            f.principal,
          ].join(','),
        );
      }
    }
  }
  return lines;
}
function analyticsLines(priced: Map<string, PricedBond>): string[] {
  const lines = [
    'bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread',
  ];
  for (const b of [...priced.values()].sort((a, b) => compare(a.id, b.id))) {
    lines.push(
      [
        b.id,
        decimal(b.price / 1000, 6),
        decimal(b.accrued, 6),
        decimal(b.target, 6),
        percent(b.ytm),
        percent(b.ytw),
        formatDate(b.workout),
        formatDate(b.nextPayment),
        decimal(b.wal, 4),
        decimal(b.macaulay, 4),
        decimal(b.modified, 4),
        decimal(b.convexity, 4),
        decimal(b.dv01, 6),
        decimal(b.curveClean, 6),
        percent(b.zspread),
      ].join(','),
    );
  }
  return lines;
}
function curveLines(
  params: Parameters,
  settlement: number,
  pillars: Pillar[],
  curve: Curve,
): string[] {
  const lines = [`valuation ${formatDate(params.valuation)} settlement ${formatDate(settlement)}`];
  for (let j = 0; j < pillars.length; j++) {
    const p = pillars[j];
    const days = curve.days[j];
    const previous = j === 0 ? 0 : curve.days[j - 1];
    lines.push(
      `pillar ${formatDate(p.maturity)} days ${days} frequency ${p.frequency} par ${hundredths(p.coupon)} zero ${percent(curve.rates[j])} df ${decimal(curve.discount(days), 6)} forward ${percent(curve.forward(previous, days))}`,
    );
  }
  for (let y = 1; y <= Math.floor(curve.days[curve.days.length - 1] / 365); y++) {
    const days = 365 * y;
    lines.push(
      `grid ${y}Y days ${days} zero ${percent(curve.rate(days))} df ${decimal(curve.discount(days), 6)} forward ${percent(curve.forward(days - 365, days))}`,
    );
  }
  return lines;
}
function portfolioLines(p: PortfolioRisk): string[] {
  const lines = [`portfolio ${p.name}`];
  for (const q of p.positions) {
    const b = q.bond;
    lines.push(
      `position ${b.id} face ${hundredths(q.face)} outstanding ${hundredths(q.outstanding)} clean ${decimal(b.price / 1000, 6)} value ${hundredths(q.value)} weight ${decimal(q.weight, 4)} book ${hundredths(q.book)} gain ${hundredths(q.gain)} ytm ${percent(b.ytm)} modified ${decimal(b.modified, 4)} dv01 ${decimal(q.dv01, 2)}`,
    );
  }
  lines.push(
    `total positions ${p.positions.length} face ${hundredths(p.face)} outstanding ${hundredths(p.outstanding)} value ${hundredths(p.total)} book ${hundredths(p.book)} gain ${hundredths(p.gain)} income ${hundredths(p.income)}`,
  );
  lines.push(
    `risk ytm ${percent(p.ytm)} yield ${percent(p.cashflowYield)} modified ${decimal(p.modified, 4)} convexity ${decimal(p.convexity, 4)} zspread ${percent(p.zspread)} dv01 ${decimal(p.dv01, 2)}`,
  );
  lines.push(
    `curve effective ${decimal(p.effective, 4)} krd ${p.krd.map((n) => decimal(n, 4)).join(' ')}`,
  );
  for (const [kind, groups] of [
    ['type', p.types],
    ['bucket', p.buckets],
  ] as const) {
    for (const g of groups) {
      lines.push(
        `${kind} ${g.key} positions ${g.count} value ${hundredths(g.value)} weight ${decimal(g.weight, 4)} duration ${decimal(g.duration, 4)} dv01 ${decimal(g.dv01, 2)}`,
      );
    }
  }
  for (const row of p.ladder) {
    lines.push(
      `ladder ${row.year} coupon ${hundredths(row.coupon)} principal ${hundredths(row.principal)} total ${hundredths(row.coupon + row.principal)}`,
    );
  }
  lines.push(
    `ladder total coupon ${hundredths(p.ladderCoupon)} principal ${hundredths(p.ladderPrincipal)} total ${hundredths(p.ladderCoupon + p.ladderPrincipal)}`,
  );
  if (p.worst) {
    lines.push(
      `stress worst ${p.worst.name} pnl ${amount(p.worst.pnl)} losers ${p.losers.map((q) => `${q.id} ${amount(q.pnl)}`).join(' ')}`,
    );
  }
  return lines;
}
function scenarioLines(portfolios: PortfolioRisk[]): string[] {
  const lines = ['portfolio,scenario,bond,value,pnl'];
  for (const p of portfolios) {
    for (const s of p.scenarios) {
      for (let i = 0; i < p.positions.length; i++) {
        lines.push(
          [p.name, s.name, p.positions[i].bond.id, amount(s.values[i]), amount(s.pnls[i])].join(
            ',',
          ),
        );
      }
      lines.push([p.name, s.name, '*', amount(s.total), amount(s.pnl)].join(','));
    }
  }
  return lines;
}
function main(): void {
  const params = readParameters();
  const calendar = new Calendar(readLines('calendar.txt').map(knownDate));
  const fixings = readCsv('fixings.csv').map((r) => ({
    date: knownDate(r.fields[0]),
    rate: Number(r.fields[1]),
  }));
  const settlement = calendar.shift(params.valuation, params.settlementDays);
  const errors: string[] = [];
  const report: Report = (file, line, key, message) => {
    errors.push(`${file}:${line}: ${key}: ${message}`);
  };
  const pillars = validatePillars(settlement, report);
  const scenarios = validateScenarios(params, pillars.length, report);
  const bonds = validateBonds(calendar, fixings, report);
  const curve = bootstrap(pillars, settlement);
  const priced = validatePrices(bonds, settlement, curve, report);
  const portfolios = validateHoldings(bonds, priced, report).map((p) =>
    portfolioRisk(p, settlement, curve, scenarios),
  );
  const files = new Map<string, string[]>([
    ['errors.txt', errors],
    ['cashflows.csv', cashflowLines(bonds)],
    ['analytics.csv', analyticsLines(priced)],
    ['curve.txt', curveLines(params, settlement, pillars, curve)],
    ['portfolio.txt', portfolios.flatMap(portfolioLines)],
    ['scenarios.csv', scenarioLines(portfolios)],
    ['compliance.txt', portfolios.flatMap((p) => complianceLines(p, params.limits))],
  ]);
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of files) {
    writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
  }
}
main();
