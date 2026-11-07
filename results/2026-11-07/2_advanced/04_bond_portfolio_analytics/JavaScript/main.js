'use strict';

const fs = require('node:fs');
const { parseDate, formatDate, dateParts, Calendar } = require('./dates_calendar');
const { yearFraction } = require('./daycount');
const { couponSchedule } = require('./schedule');
const { bisect, dirty, yieldAnalytics } = require('./pricing');
const { Curve, bootstrap } = require('./curve');

const TYPES = ['FIXED', 'ZERO', 'AMORT', 'FRN'];
const FREQUENCIES = [1, 2, 4, 12];
const DAYCOUNTS = ['30/360', '30E/360', 'ACT/360', 'ACT/365F', 'ACT/ACT'];
const CONVENTIONS = ['FOLLOWING', 'MODIFIED_FOLLOWING', 'PRECEDING', 'UNADJUSTED'];
const BUCKETS = ['0-1Y', '1-3Y', '3-5Y', '5-10Y', '10Y+'];
const compareText = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const roundRatio = (numerator, denominator) => Math.floor((2 * numerator + denominator) / (2 * denominator));
const thousandths = text => Number(text.replace('.', ''));
const readLines = name => fs.readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);
const readCsv = name => readLines(name).slice(1).map((text, index) => ({ fields: text.split(','), line: index + 2 }));

function sum(values) {
  let total = 0;
  for (const value of values) total += value;
  return total;
}

function hundredths(value) {
  const magnitude = Math.abs(value);
  return (value < 0 ? '-' : '') + Math.floor(magnitude / 100) + '.' + String(magnitude % 100).padStart(2, '0');
}

function decimal(value, digits) {
  let scale = 1;
  for (let index = 0; index < digits; index++) scale *= 10;
  const rounded = Math.floor(Math.abs(value) * scale + 0.5);
  return (value < 0 && rounded !== 0 ? '-' : '') + Math.floor(rounded / scale) + '.'
    + String(rounded % scale).padStart(digits, '0');
}

const percent = value => decimal(value * 100, 4);
const amount = cents => decimal(cents / 100, 2);

function readParameters() {
  const parameters = { scenarios: [], limits: [] };
  const lines = readLines('params.txt');
  for (let index = 0; index < lines.length; index++) {
    const [kind, ...words] = lines[index].split(' ');
    if (kind === 'valuation_date') parameters.valuation = parseDate(words[0]);
    else if (kind === 'settlement_days') parameters.settlementDays = Number(words[0]);
    else if (kind === 'scenario') parameters.scenarios.push({ name: words[0], shifts: words.slice(1).map(Number), line: index + 1 });
    else parameters.limits.push({ kind: words[0], arguments: words.slice(1) });
  }
  return parameters;
}

function validatePillars(settlement, report) {
  const seen = new Set(), pillars = [];
  for (const row of readCsv('curve_quotes.csv')) {
    const [text, couponText, frequencyText] = row.fields;
    const duplicate = seen.has(text), maturity = parseDate(text), frequency = Number(frequencyText);
    seen.add(text);
    let error = null;
    if (duplicate) error = 'duplicate pillar';
    else if (maturity === null) error = 'invalid date';
    else if (maturity <= settlement) error = 'pillar not after settlement';
    else if (!FREQUENCIES.includes(frequency)) error = 'invalid frequency';
    if (error !== null) report('curve_quotes.csv', row.line, text, error);
    else pillars.push({ maturity, frequency, coupon: Number(couponText) });
  }
  return pillars.sort((left, right) => left.maturity - right.maturity);
}

function validateScenarios(parameters, count, report) {
  const seen = new Set(), scenarios = [];
  for (const scenario of parameters.scenarios) {
    const duplicate = seen.has(scenario.name);
    seen.add(scenario.name);
    const error = duplicate ? 'duplicate scenario' : scenario.shifts.length !== count ? 'wrong number of shifts' : null;
    if (error !== null) report('params.txt', scenario.line, scenario.name, error);
    else scenarios.push(scenario);
  }
  return scenarios;
}

function readOptions(text, type) {
  const allowed = new Set(['EOM', 'LONG', ...(type === 'FIXED' ? ['CALL'] : type === 'AMORT' ? ['SINK']
    : type === 'FRN' ? ['LAG', 'CAP', 'FLOOR'] : [])]);
  const values = new Map(), sinks = [], calls = [];
  if (text !== '-') {
    for (const item of text.split(';')) {
      const equals = item.indexOf('='), key = equals < 0 ? item : item.slice(0, equals);
      const value = equals < 0 ? null : item.slice(equals + 1);
      if (!allowed.has(key) || (key !== 'SINK' && key !== 'CALL' && values.has(key))) return null;
      values.set(key, value);
      if (key === 'SINK') {
        const [date, cents] = value.split(':');
        sinks.push({ date, amount: Number(cents) });
      } else if (key === 'CALL') {
        const [date, price] = value.split(':');
        calls.push({ date, price: thousandths(price) });
      }
    }
  }
  const lag = values.has('LAG') ? Number(values.get('LAG')) : null;
  const cap = values.has('CAP') ? Number(values.get('CAP')) : null;
  const floor = values.has('FLOOR') ? Number(values.get('FLOOR')) : null;
  if (type === 'FRN' && (lag === null || lag < 1 || lag > 5 || cap > 1200 || floor > (cap ?? 1200))) return null;
  return { eom: values.has('EOM'), long: values.has('LONG'), lag, cap, floor, sinks, calls };
}

function indexRate(fixings, date) {
  let lower = 0, upper = fixings.length - 1, found = -1;
  while (lower <= upper) {
    const middle = Math.floor((lower + upper) / 2);
    if (fixings[middle].date <= date) {
      found = middle;
      lower = middle + 1;
    } else {
      upper = middle - 1;
    }
  }
  return found < 0 ? null : fixings[found].rate;
}

function buildCashflows(bond, calendar, fixings) {
  const cashflows = [], sinks = new Map(bond.options.sinks.map(item => [item.day, item.amount]));
  let opening = bond.face;
  for (let period = 1; period < bond.schedule.length; period++) {
    const start = bond.schedule[period - 1], end = bond.schedule[period];
    const [numerator, denominator] = yearFraction(start, end, bond.daycount);
    const payment = calendar.adjust(end, bond.convention);
    let rate = bond.coupon;
    if (bond.type === 'FRN') {
      const fixingDate = calendar.shift(calendar.adjust(start, bond.convention), -bond.options.lag);
      const fixing = indexRate(fixings, fixingDate);
      if (fixing === null) return null;
      rate += fixing;
      if (bond.options.floor !== null) rate = Math.max(rate, bond.options.floor);
      if (bond.options.cap !== null) rate = Math.min(rate, bond.options.cap);
    }
    const principal = period === bond.schedule.length - 1 ? opening : sinks.get(end) || 0;
    const coupon = roundRatio(opening * rate * numerator, 10000 * denominator);
    cashflows.push({ period, start, end, payment, numerator, denominator, rate, opening, coupon, principal,
      cash: coupon + principal });
    opening -= principal;
  }
  return cashflows;
}

function validateBond(fields, calendar, fixings) {
  const [id, type, issueText, maturityText, couponText, frequencyText, daycount, convention, faceText, optionText] = fields;
  if (!TYPES.includes(type)) return { error: 'unknown type' };
  const issue = parseDate(issueText), maturity = parseDate(maturityText);
  if (issue === null || maturity === null) return { error: 'invalid date' };
  if (maturity <= issue) return { error: 'maturity not after issue' };
  const frequency = Number(frequencyText), coupon = Number(couponText), face = Number(faceText);
  if (!FREQUENCIES.includes(frequency)) return { error: 'invalid frequency' };
  if (!DAYCOUNTS.includes(daycount)) return { error: 'unknown day count' };
  if (!CONVENTIONS.includes(convention)) return { error: 'unknown business day rule' };
  if (face % 100000 !== 0 || face > 10000000) return { error: 'invalid face' };
  if (coupon > 1200 || (type === 'ZERO' && coupon !== 0)) return { error: 'invalid coupon' };
  const options = readOptions(optionText, type);
  if (options === null) return { error: 'invalid option' };
  const schedule = couponSchedule(issue, maturity, frequency, options.eom, options.long);
  const internalDates = new Set(schedule.slice(1, -1));
  let previous = null, total = 0;
  for (const sink of options.sinks) {
    sink.day = parseDate(sink.date);
    if (sink.day === null || !internalDates.has(sink.day) || (previous !== null && sink.day <= previous)
        || sink.amount === 0) return { error: 'invalid sinking fund' };
    previous = sink.day;
    total += sink.amount;
  }
  if (type === 'AMORT' && (total === 0 || total >= face)) return { error: 'invalid sinking fund' };
  previous = null;
  for (const call of options.calls) {
    call.day = parseDate(call.date);
    if (call.day === null || !internalDates.has(call.day) || (previous !== null && call.day <= previous)
        || call.price < 100000 || call.price > 110000) return { error: 'invalid call schedule' };
    previous = call.day;
  }
  const bond = { id, type, issue, maturity, coupon, frequency, daycount, convention, face, options, schedule };
  bond.cashflows = buildCashflows(bond, calendar, fixings);
  return bond.cashflows === null ? { error: 'missing fixing' } : { bond };
}

function validateBonds(calendar, fixings, report) {
  const seen = new Set(), bonds = new Map();
  for (const row of readCsv('bonds.csv')) {
    const id = row.fields[0], duplicate = seen.has(id);
    seen.add(id);
    const result = duplicate ? { error: 'duplicate id' } : validateBond(row.fields, calendar, fixings);
    if (result.error) report('bonds.csv', row.line, id, result.error);
    else bonds.set(id, result.bond);
  }
  return bonds;
}

function settlementValues(bond, price, settlement) {
  const current = bond.cashflows.findIndex(flow => flow.end > settlement);
  const remaining = bond.cashflows.slice(current), period = remaining[0];
  const [numerator, denominator] = yearFraction(period.start, settlement, bond.daycount);
  const accrued = period.rate * numerator / (100 * denominator);
  const accruedAmount = roundRatio(period.opening * period.rate * numerator, 10000 * denominator);
  const cleanAmount = roundRatio(period.opening * price, 100000);
  const [nextNumerator, nextDenominator] = yearFraction(settlement, period.end, bond.daycount);
  const fraction = bond.frequency * nextNumerator / nextDenominator;
  const flows = remaining.filter(flow => flow.cash >= 1).map(flow => ({ ...flow, days: flow.payment - settlement }));
  return { current, remaining, flows, outstanding: period.opening, price, accrued, accruedAmount, cleanAmount,
    marketValue: cleanAmount + accruedAmount, target: price / 1000 + accrued, fraction,
    amounts: remaining.map(flow => flow.cash), curveFlows: flows.map(flow => ({ days: flow.days, amount: flow.cash })) };
}

function completeAnalytics(bond, values, settlement, curve) {
  Object.assign(bond, values, yieldAnalytics(values.amounts, bond.frequency, values.fraction, values.outstanding, values.target));
  bond.ytw = bond.ytm;
  bond.workout = bond.maturity;
  for (const call of bond.options.calls) {
    if (call.day <= settlement) continue;
    const ending = bond.remaining.findIndex(flow => flow.end === call.day);
    const called = bond.remaining.slice(0, ending + 1).map(flow => flow.coupon);
    called[called.length - 1] += roundRatio(bond.remaining[ending].opening * call.price, 100000);
    const value = yieldValue => dirty(called, bond.frequency, bond.fraction, bond.outstanding, yieldValue);
    const yieldCall = bisect(value, 0, 1, bond.target);
    if (yieldCall < bond.ytw) {
      bond.ytw = yieldCall;
      bond.workout = call.day;
    }
  }
  bond.wal = sum(bond.flows.map(flow => flow.principal * flow.days)) / (365 * bond.outstanding);
  bond.nextPayment = bond.flows[0].payment;
  bond.curveClean = curve.present(bond.curveFlows) * 100 / bond.outstanding - bond.accrued;
  bond.zspread = curve.zspread(bond.curveFlows, bond.marketValue);
}

function validatePrices(bonds, settlement, curve, report) {
  const seen = new Set(), priced = new Map();
  for (const row of readCsv('prices.csv')) {
    const [id, text] = row.fields, duplicate = seen.has(id), bond = bonds.get(id);
    seen.add(id);
    let error = null, values;
    if (!bond) error = 'unknown bond';
    else if (duplicate) error = 'duplicate price';
    else if (!(bond.issue <= settlement && settlement < bond.maturity)) error = 'not outstanding';
    else {
      values = settlementValues(bond, thousandths(text), settlement);
      const value = yieldValue => dirty(values.amounts, bond.frequency, values.fraction, values.outstanding, yieldValue);
      if (!(value(0) > values.target && values.target > value(1))) error = 'yield out of range';
    }
    if (error !== null) report('prices.csv', row.line, id, error);
    else {
      completeAnalytics(bond, values, settlement, curve);
      priced.set(id, bond);
    }
  }
  return priced;
}

function validateHoldings(bonds, priced, report) {
  const portfolios = new Map();
  for (const row of readCsv('holdings.csv')) {
    const [name, id, faceText, bookText] = row.fields, face = Number(faceText), bond = priced.get(id);
    let error = null;
    if (!bonds.has(id)) error = 'unknown bond';
    else if (!bond) error = 'no price';
    else if (face % bond.face !== 0) error = 'invalid face';
    if (error !== null) {
      report('holdings.csv', row.line, id, error);
      continue;
    }
    if (!portfolios.has(name)) portfolios.set(name, new Map());
    const positions = portfolios.get(name);
    if (!positions.has(id)) positions.set(id, { bond, units: 0, book: 0 });
    const position = positions.get(id), units = face / bond.face;
    position.units += units;
    position.book += roundRatio(units * bond.outstanding * thousandths(bookText), 100000);
  }
  return [...portfolios].sort(([left], [right]) => compareText(left, right)).map(([name, positions]) => ({ name,
    positions: [...positions.values()].sort((left, right) => compareText(left.bond.id, right.bond.id)) }));
}

function maturityBucket(days) {
  if (days < 365) return BUCKETS[0];
  if (days < 1095) return BUCKETS[1];
  if (days < 1825) return BUCKETS[2];
  if (days < 3650) return BUCKETS[3];
  return BUCKETS[4];
}

function groupedRisk(positions, keys, select, total) {
  return keys.map(key => {
    const selected = positions.filter(position => select(position) === key);
    const value = sum(selected.map(position => position.value));
    return { key, count: selected.length, value, weight: value * 100 / total,
      duration: sum(selected.map(position => position.value * position.bond.modified)) / total,
      dv01: sum(selected.map(position => position.dv01)) };
  });
}

function portfolioRisk(portfolio, settlement, curve, scenarios) {
  const positions = portfolio.positions;
  for (const position of positions) {
    const { bond, units } = position;
    Object.assign(position, { face: units * bond.face, outstanding: units * bond.outstanding,
      value: units * bond.marketValue, gain: units * bond.cleanAmount - position.book,
      dv01: bond.dv01 * units * bond.outstanding / 10000, days: bond.maturity - settlement });
  }
  portfolio.total = sum(positions.map(position => position.value));
  for (const position of positions) position.weight = position.value * 100 / portfolio.total;
  for (const key of ['face', 'outstanding', 'book', 'gain', 'dv01']) portfolio[key] = sum(positions.map(position => position[key]));
  for (const key of ['ytm', 'modified', 'convexity', 'zspread']) {
    portfolio[key] = sum(positions.map(position => position.value * position.bond[key])) / portfolio.total;
  }
  const flows = [], ladder = new Map();
  portfolio.income = 0;
  for (const position of positions) {
    for (const flow of position.bond.flows) {
      const coupon = position.units * flow.coupon, principal = position.units * flow.principal;
      flows.push({ days: flow.days, amount: position.units * flow.cash });
      if (flow.days <= 365) portfolio.income += coupon;
      const year = dateParts(flow.payment)[0];
      if (!ladder.has(year)) ladder.set(year, { year, coupon: 0, principal: 0 });
      ladder.get(year).coupon += coupon;
      ladder.get(year).principal += principal;
    }
  }
  portfolio.ladder = [...ladder.values()].sort((left, right) => left.year - right.year);
  portfolio.ladderCoupon = sum(portfolio.ladder.map(row => row.coupon));
  portfolio.ladderPrincipal = sum(portfolio.ladder.map(row => row.principal));
  portfolio.cashflowYield = bisect(rate => new Curve([0], [rate]).present(flows), 0, 1, portfolio.total);
  const values = shifted => positions.map(position => position.units * shifted.present(position.bond.curveFlows, position.bond.zspread));
  const baseValues = values(curve), base = sum(baseValues), count = curve.days.length;
  const present = shifts => sum(values(curve.shifted(shifts)));
  portfolio.effective = (present(Array(count).fill(-0.0001)) - present(Array(count).fill(0.0001))) / (2 * 0.0001 * base);
  portfolio.krd = [];
  for (let pillar = 0; pillar < count; pillar++) {
    const down = Array(count).fill(0), up = Array(count).fill(0);
    down[pillar] = -0.0001;
    up[pillar] = 0.0001;
    portfolio.krd.push((present(down) - present(up)) / (2 * 0.0001 * base));
  }
  portfolio.scenarios = [{ name: 'BASE', values: baseValues, total: base, pnls: positions.map(() => 0), pnl: 0 }];
  for (const scenario of scenarios) {
    const shifted = values(curve.shifted(scenario.shifts.map(shift => shift * 0.0001)));
    const total = sum(shifted);
    portfolio.scenarios.push({ name: scenario.name, values: shifted, total, pnl: total - base,
      pnls: shifted.map((value, index) => value - baseValues[index]) });
  }
  portfolio.worst = null;
  for (const scenario of portfolio.scenarios.slice(1)) {
    if (portfolio.worst === null || scenario.pnl < portfolio.worst.pnl) portfolio.worst = scenario;
  }
  if (portfolio.worst !== null) {
    portfolio.losers = positions.map((position, index) => ({ id: position.bond.id, pnl: portfolio.worst.pnls[index] }))
      .sort((left, right) => left.pnl - right.pnl || compareText(left.id, right.id)).slice(0, 3);
  }
  portfolio.types = groupedRisk(positions, TYPES, position => position.bond.type, portfolio.total);
  portfolio.buckets = groupedRisk(positions, BUCKETS, position => maturityBucket(position.days), portfolio.total);
}

function complianceLines(portfolio, limits) {
  const lines = [];
  let breaches = 0;
  for (const limit of limits) {
    const args = limit.arguments;
    let text, breached;
    if (limit.kind === 'position_weight') {
      let largest = portfolio.positions[0];
      for (const position of portfolio.positions) if (position.value > largest.value) largest = position;
      const bound = Number(args[0]);
      breached = largest.value * 10000 > bound * portfolio.total;
      text = `position_weight ${largest.bond.id} ${decimal(largest.weight, 4)} limit ${hundredths(bound)}`;
    } else if (limit.kind === 'type_weight') {
      const group = portfolio.types.find(row => row.key === args[0]), bound = Number(args[1]);
      breached = group.value * 10000 > bound * portfolio.total;
      text = `type_weight ${args[0]} ${decimal(group.weight, 4)} limit ${hundredths(bound)}`;
    } else if (limit.kind === 'max_maturity') {
      const years = Number(args[0]), count = portfolio.positions.filter(position => position.days > 365 * years).length;
      breached = count > 0;
      text = `max_maturity ${years}Y positions ${count}`;
    } else if (limit.kind === 'min_yield') {
      const bound = Number(args[0]);
      breached = portfolio.ytm * 10000 < bound;
      text = `min_yield ${percent(portfolio.ytm)} limit ${hundredths(bound)}`;
    } else if (limit.kind === 'duration') {
      const lower = Number(args[0]), upper = Number(args[1]);
      breached = portfolio.modified < lower / 100 || portfolio.modified > upper / 100;
      text = `duration ${decimal(portfolio.modified, 4)} range ${hundredths(lower)} ${hundredths(upper)}`;
    } else {
      const bound = Number(args[0]);
      breached = portfolio.dv01 * 100 > bound;
      text = `dv01 ${decimal(portfolio.dv01, 2)} limit ${hundredths(bound)}`;
    }
    if (breached) breaches++;
    lines.push(`${portfolio.name} ${text} ${breached ? 'BREACH' : 'PASS'}`);
  }
  lines.push(`${portfolio.name} breaches ${breaches}`);
  return lines;
}

function cashflowLines(bonds) {
  const lines = ['bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal'];
  for (const bond of [...bonds.values()].sort((left, right) => compareText(left.id, right.id))) {
    for (const flow of bond.cashflows) {
      if (flow.cash < 1) continue;
      lines.push([bond.id, flow.period, formatDate(flow.start), formatDate(flow.end), formatDate(flow.payment),
        decimal(flow.numerator / flow.denominator, 6), flow.rate, flow.opening, flow.coupon, flow.principal].join(','));
    }
  }
  return lines;
}

function analyticsLines(priced) {
  const lines = ['bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread'];
  for (const bond of [...priced.values()].sort((left, right) => compareText(left.id, right.id))) {
    lines.push([bond.id, decimal(bond.price / 1000, 6), decimal(bond.accrued, 6), decimal(bond.target, 6),
      percent(bond.ytm), percent(bond.ytw), formatDate(bond.workout), formatDate(bond.nextPayment),
      decimal(bond.wal, 4), decimal(bond.macaulay, 4), decimal(bond.modified, 4), decimal(bond.convexity, 4),
      decimal(bond.dv01, 6), decimal(bond.curveClean, 6), percent(bond.zspread)].join(','));
  }
  return lines;
}

function curveLines(parameters, settlement, pillars, curve) {
  const lines = [`valuation ${formatDate(parameters.valuation)} settlement ${formatDate(settlement)}`];
  for (let index = 0; index < pillars.length; index++) {
    const pillar = pillars[index], days = curve.days[index], previous = index === 0 ? 0 : curve.days[index - 1];
    lines.push(`pillar ${formatDate(pillar.maturity)} days ${days} frequency ${pillar.frequency} par ${hundredths(pillar.coupon)}`
      + ` zero ${percent(curve.rates[index])} df ${decimal(curve.discount(days), 6)} forward ${percent(curve.forward(previous, days))}`);
  }
  for (let year = 1; year <= Math.floor(curve.days.at(-1) / 365); year++) {
    const days = 365 * year;
    lines.push(`grid ${year}Y days ${days} zero ${percent(curve.rate(days))} df ${decimal(curve.discount(days), 6)}`
      + ` forward ${percent(curve.forward(days - 365, days))}`);
  }
  return lines;
}

function portfolioLines(portfolio) {
  const lines = [`portfolio ${portfolio.name}`];
  for (const position of portfolio.positions) {
    const bond = position.bond;
    lines.push(`position ${bond.id} face ${hundredths(position.face)} outstanding ${hundredths(position.outstanding)}`
      + ` clean ${decimal(bond.price / 1000, 6)} value ${hundredths(position.value)} weight ${decimal(position.weight, 4)}`
      + ` book ${hundredths(position.book)} gain ${hundredths(position.gain)} ytm ${percent(bond.ytm)}`
      + ` modified ${decimal(bond.modified, 4)} dv01 ${decimal(position.dv01, 2)}`);
  }
  lines.push(`total positions ${portfolio.positions.length} face ${hundredths(portfolio.face)} outstanding ${hundredths(portfolio.outstanding)}`
    + ` value ${hundredths(portfolio.total)} book ${hundredths(portfolio.book)} gain ${hundredths(portfolio.gain)} income ${hundredths(portfolio.income)}`);
  lines.push(`risk ytm ${percent(portfolio.ytm)} yield ${percent(portfolio.cashflowYield)} modified ${decimal(portfolio.modified, 4)}`
    + ` convexity ${decimal(portfolio.convexity, 4)} zspread ${percent(portfolio.zspread)} dv01 ${decimal(portfolio.dv01, 2)}`);
  lines.push(`curve effective ${decimal(portfolio.effective, 4)} krd ${portfolio.krd.map(value => decimal(value, 4)).join(' ')}`);
  for (const [kind, groups] of [['type', portfolio.types], ['bucket', portfolio.buckets]]) {
    for (const group of groups) lines.push(`${kind} ${group.key} positions ${group.count} value ${hundredths(group.value)}`
      + ` weight ${decimal(group.weight, 4)} duration ${decimal(group.duration, 4)} dv01 ${decimal(group.dv01, 2)}`);
  }
  for (const row of portfolio.ladder) lines.push(`ladder ${row.year} coupon ${hundredths(row.coupon)} principal ${hundredths(row.principal)}`
    + ` total ${hundredths(row.coupon + row.principal)}`);
  lines.push(`ladder total coupon ${hundredths(portfolio.ladderCoupon)} principal ${hundredths(portfolio.ladderPrincipal)}`
    + ` total ${hundredths(portfolio.ladderCoupon + portfolio.ladderPrincipal)}`);
  if (portfolio.worst !== null) lines.push(`stress worst ${portfolio.worst.name} pnl ${amount(portfolio.worst.pnl)} losers `
    + portfolio.losers.map(position => `${position.id} ${amount(position.pnl)}`).join(' '));
  return lines;
}

function scenarioLines(portfolios) {
  const lines = ['portfolio,scenario,bond,value,pnl'];
  for (const portfolio of portfolios) {
    for (const scenario of portfolio.scenarios) {
      for (let index = 0; index < portfolio.positions.length; index++) {
        lines.push([portfolio.name, scenario.name, portfolio.positions[index].bond.id,
          amount(scenario.values[index]), amount(scenario.pnls[index])].join(','));
      }
      lines.push([portfolio.name, scenario.name, '*', amount(scenario.total), amount(scenario.pnl)].join(','));
    }
  }
  return lines;
}

function main() {
  const parameters = readParameters(), calendar = new Calendar(readLines('calendar.txt').map(parseDate));
  const fixings = readCsv('fixings.csv').map(row => ({ date: parseDate(row.fields[0]), rate: Number(row.fields[1]) }));
  const settlement = calendar.shift(parameters.valuation, parameters.settlementDays), errors = [];
  const report = (file, line, key, message) => errors.push(`${file}:${line}: ${key}: ${message}`);
  const pillars = validatePillars(settlement, report);
  const scenarios = validateScenarios(parameters, pillars.length, report);
  const bonds = validateBonds(calendar, fixings, report), curve = bootstrap(pillars, settlement);
  const priced = validatePrices(bonds, settlement, curve, report);
  const portfolios = validateHoldings(bonds, priced, report);
  for (const portfolio of portfolios) portfolioRisk(portfolio, settlement, curve, scenarios);
  const files = new Map([
    ['errors.txt', errors], ['cashflows.csv', cashflowLines(bonds)], ['analytics.csv', analyticsLines(priced)],
    ['curve.txt', curveLines(parameters, settlement, pillars, curve)],
    ['portfolio.txt', portfolios.flatMap(portfolioLines)], ['scenarios.csv', scenarioLines(portfolios)],
    ['compliance.txt', portfolios.flatMap(portfolio => complianceLines(portfolio, parameters.limits))],
  ]);
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of files) fs.writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

main();
