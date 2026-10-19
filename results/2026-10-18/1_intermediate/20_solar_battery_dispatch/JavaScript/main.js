import { readFileSync } from 'node:fs';

const SETTING_RANGES = {
  CAPACITY: [1, 100000], INITIAL: [0, 100], CHARGE: [1, 20000],
  DISCHARGE: [1, 20000], CEFF: [1, 100], DEFF: [1, 100],
  RESERVE: [0, 100], COST: [0, 100000], EXPORT: [0, 100000],
  FEEDIN: [0, 10000], FIXED: [0, 100000], DEMAND: [0, 100000],
  PVSCALE: [0, 300]
};
const STRATEGY_RANGES = {TOU: [1, 100], PEAKSHAVE: [0, 100000], BACKUP: [0, 100]};
const FLOW_NAMES = [
  'PV>LOAD', 'PV>BATTERY', 'PV>GRID', 'PV>CURTAIL',
  'BATTERY>LOAD', 'BATTERY>GRID', 'GRID>LOAD', 'GRID>BATTERY'
];
const TOTAL_FIELDS = [
  'load', 'pv', 'charge', 'discharge', 'imported', 'exported',
  'curtailed', 'drawn', 'loss', 'shortfall', 'import_cost', 'export_income'
];
const DAY_NAMES = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

class CommandError extends Error {}

const sum = numbers => numbers.reduce((total, value) => total + value, 0);
const quotient = (a, b) => Math.floor(a / b);
const ceiling = (a, b) => Math.floor((a + b - 1) / b);
const money = amount => (amount < 0 ? '-' : '') + quotient(Math.abs(amount), 100) +
  '.' + String(Math.abs(amount) % 100).padStart(2, '0');
const percentage = (numerator, denominator) => {
  const value = denominator ? quotient(10000 * numerator, denominator) : 0;
  return quotient(value, 100) + '.' + String(value % 100).padStart(2, '0');
};
const tableRow = (values, widths) => values.map((value, i) => String(value).padStart(widths[i])).join('');
const bar = width => '|' + '#'.repeat(width) + '.'.repeat(20 - width) + '|';
const strategyText = ([name, parameter]) => parameter === null ? name : `${name} ${parameter}`;

function tariffExtremes(prices) {
  const names = Object.keys(prices);
  let cheapest = names[0], peak = names[0];
  for (const name of names) {
    if (prices[name] < prices[cheapest]) cheapest = name;
    if (prices[name] > prices[peak]) peak = name;
  }
  return [cheapest, peak];
}

function readStrategies(tokens) {
  const strategies = [];
  for (let index = 0; index < tokens.length;) {
    const name = tokens[index++];
    if (name === 'SELF' || name === 'EXPORTPEAK') {
      strategies.push([name, null]);
      continue;
    }
    if (!Object.hasOwn(STRATEGY_RANGES, name)) throw new CommandError('unknown strategy ' + name);
    if (index === tokens.length) throw new CommandError('missing parameter for ' + name);
    const parameter = Number(tokens[index++]);
    const [low, high] = STRATEGY_RANGES[name];
    if (parameter < low || parameter > high) throw new CommandError('invalid parameter for ' + name);
    strategies.push([name, parameter]);
  }
  return strategies;
}

function requireCount(values, expected) {
  if (values.length !== expected) throw new CommandError('wrong number of arguments');
}
function oneStrategy(values) {
  const result = readStrategies(values);
  requireCount(result, 1);
  return result[0];
}
function checkedRange(low, high, step, [minimum, maximum]) {
  if (low < minimum || high > maximum || high < low || step < 1 ||
      quotient(high - low, step) + 1 > 20) throw new CommandError('invalid range');
  const values = [];
  for (let value = low; value <= high; value += step) values.push(value);
  return values;
}
function gcd(a, b) {
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}

class InputData {
  constructor(lines) {
    let position = 0;
    const read = () => lines[position++].split(' ');
    const battery = read().slice(1).map(Number);
    const grid = read().slice(1).map(Number);
    this.initialSettings = Object.fromEntries(
      Object.keys(SETTING_RANGES).map((key, i) => [key, [...battery, ...grid, 100][i]])
    );
    const periodCount = Number(read()[1]);
    this.initialPrices = {};
    for (let i = 0; i < periodCount; ++i) {
      const [name, price] = read();
      this.initialPrices[name] = Number(price);
    }
    const weekday = InputData.readPeriodHours(read().slice(1));
    const weekend = InputData.readPeriodHours(read().slice(1));
    const profileCount = Number(read()[1]);
    const profiles = new Map();
    for (let i = 0; i < profileCount; ++i) {
      const [kind, name, ...values] = read();
      profiles.set(kind + '/' + name, values.map(Number));
    }
    this.dayCount = Number(read()[1]);
    this.loads = [];
    this.basePV = [];
    for (let day = 0; day < this.dayCount; ++day) {
      const [loadName, loadPct, pvName, pvPct] = read();
      this.loads.push(...profiles.get('LOAD/' + loadName).map(v => quotient(v * Number(loadPct), 100)));
      this.basePV.push(...profiles.get('PV/' + pvName).map(v => quotient(v * Number(pvPct), 100)));
    }
    const holidays = new Set(read().slice(2).map(Number));
    const overrideCount = Number(read()[1]);
    for (let i = 0; i < overrideCount; ++i) {
      const [day, hour, load, pv] = read().map(Number);
      const index = (day - 1) * 24 + hour;
      this.loads[index] = load;
      this.basePV[index] = pv;
    }
    this.dayNames = [];
    this.weekendDays = [];
    this.periods = [];
    for (let day = 1; day <= this.dayCount; ++day) {
      const holiday = holidays.has(day);
      const weekendDay = holiday || (day - 1) % 7 >= 5;
      this.dayNames.push(holiday ? 'HOL' : DAY_NAMES[(day - 1) % 7]);
      this.weekendDays.push(weekendDay);
      this.periods.push(...(weekendDay ? weekend : weekday));
    }
    this.commands = lines.slice(position);
  }

  static readPeriodHours(tokens) {
    const hours = [];
    for (let i = 0; i < tokens.length; i += 2) {
      const start = Number(tokens[i]);
      const end = i + 2 < tokens.length ? Number(tokens[i + 2]) : 24;
      for (let hour = start; hour < end; ++hour) hours.push(tokens[i + 1]);
    }
    return hours;
  }
}

class HourRecord {
  constructor(index, period, load, pv, soc, flows, drawn, shortfall, loss, price, feedin) {
    this.index = index;
    this.day = quotient(index, 24) + 1;
    this.hour = index % 24;
    this.period = period;
    this.load = load;
    this.pv = pv;
    this.soc = soc;
    this.flows = flows;
    this.charge = flows[1] + flows[7];
    this.discharge = flows[4] + flows[5];
    this.imported = flows[6] + flows[7];
    this.exported = flows[2] + flows[5];
    this.curtailed = flows[3];
    this.drawn = drawn;
    this.shortfall = shortfall;
    this.loss = loss;
    this.import_cost = quotient(this.imported * price, 100000);
    this.export_income = quotient(this.exported * feedin, 100000);
    this.net_cost = this.import_cost - this.export_income;
  }
}

class Totals {
  constructor(records) {
    this.count = records.length;
    for (const field of TOTAL_FIELDS) this[field] = sum(records.map(row => row[field]));
    this.flows = FLOW_NAMES.map((_, i) => sum(records.map(row => row.flows[i])));
    this.net_cost = this.import_cost - this.export_income;
  }
}

class SimulationResult {
  constructor(strategy, settings, prices, startSOC, reserve, records) {
    this.strategy = strategy;
    this.settings = {...settings};
    this.prices = {...prices};
    this.startSOC = startSOC;
    this.reserve = reserve;
    this.hours = records;
    this.days = [];
    for (let i = 0; i < records.length; i += 24) this.days.push(records.slice(i, i + 24));
    this.daily = this.days.map(day => new Totals(day));
    this.byPeriod = {};
    for (const period of Object.keys(prices)) {
      this.byPeriod[period] = new Totals(records.filter(record => record.period === period));
    }
    this.total = new Totals(records);
    this.peak = Math.max(...records.map(record => record.imported));
    this.demandCharge = quotient(this.peak * settings.DEMAND, 1000);
    this.bill = this.total.net_cost + settings.FIXED + this.demandCharge;
    this.endSOC = records.at(-1).soc;
    this.sufficiency = percentage(Math.max(0, this.total.load - this.total.imported), this.total.load);
  }
}

class Simulator {
  constructor(data, strategy, settings, prices, outage = null) {
    this.data = data;
    this.strategy = strategy;
    [this.name, this.parameter] = strategy;
    this.settings = {...settings};
    this.prices = {...prices};
    this.outage = outage;
    this.capacity = settings.CAPACITY;
    this.ceff = settings.CEFF;
    this.deff = settings.DEFF;
    const reservePercent = this.name === 'BACKUP' ? Math.max(settings.RESERVE, this.parameter) : settings.RESERVE;
    this.reserve = quotient(this.capacity * reservePercent, 100);
    this.startSOC = quotient(this.capacity * settings.INITIAL, 100);
    this.soc = this.startSOC;
    [this.cheapest, this.peak] = tariffExtremes(prices);
    this.arbitrage = this.name === 'EXPORTPEAK' && settings.FEEDIN > prices[this.cheapest];
  }

  dischargeTarget(deficit, period) {
    if (this.name === 'TOU') return period === this.peak ? deficit : 0;
    if (this.name === 'PEAKSHAVE') return Math.max(0, deficit - this.parameter);
    if (this.arbitrage && period === this.cheapest && period !== this.peak) return 0;
    return deficit;
  }

  gridCharge(period, pvCharge, gridLoad) {
    let headroom = this.settings.CHARGE - pvCharge;
    let target = null;
    if (this.name === 'TOU' && period === this.cheapest && period !== this.peak) {
      target = quotient(this.capacity * this.parameter, 100);
    } else if (this.name === 'PEAKSHAVE' && period === this.cheapest) {
      target = this.capacity;
      headroom = Math.min(headroom, Math.max(0, this.parameter - gridLoad));
    } else if (this.name === 'BACKUP' && period === this.cheapest) {
      target = this.reserve;
    } else if (this.arbitrage && period === this.cheapest && period !== this.peak) {
      target = this.capacity;
    }
    if (target === null) return 0;
    const amount = Math.min(headroom, ceiling(100 * Math.max(0, target - this.soc), this.ceff));
    this.soc += quotient(amount * this.ceff, 100);
    return amount;
  }

  runHour(index) {
    const settings = this.settings;
    const load = this.data.loads[index];
    const pv = quotient(this.data.basePV[index] * settings.PVSCALE, 100);
    const period = this.data.periods[index];
    const direct = Math.min(load, pv);
    let surplus = pv - direct;
    let deficit = load - direct;
    const pvCharge = Math.min(surplus, settings.CHARGE,
      ceiling(100 * (this.capacity - this.soc), this.ceff));
    this.soc += quotient(pvCharge * this.ceff, 100);
    surplus -= pvCharge;
    const isOutage = this.outage !== null && this.outage[0] <= index && index <= this.outage[1];
    const target = isOutage ? deficit : this.dischargeTarget(deficit, period);
    const lowerBound = isOutage ? 0 : this.reserve;
    const loadDrawn = Math.min(ceiling(100 * target, this.deff), settings.DISCHARGE,
      Math.max(0, this.soc - lowerBound));
    const loadDischarge = quotient(loadDrawn * this.deff, 100);
    this.soc -= loadDrawn;
    deficit -= loadDischarge;
    let gridLoad, shortfall, pvExport, curtailed, gridCharge, exportDrawn = 0, batteryExport = 0;
    if (isOutage) {
      gridLoad = 0;
      shortfall = deficit;
      pvExport = 0;
      curtailed = surplus;
      gridCharge = 0;
    } else {
      gridLoad = deficit;
      shortfall = 0;
      pvExport = Math.min(surplus, settings.EXPORT);
      curtailed = surplus - pvExport;
      gridCharge = this.gridCharge(period, pvCharge, gridLoad);
      if (this.arbitrage && period === this.peak && pvCharge === 0) {
        exportDrawn = Math.min(
          ceiling(100 * (settings.EXPORT - pvExport), this.deff),
          settings.DISCHARGE - loadDrawn,
          Math.max(0, this.soc - this.reserve)
        );
        batteryExport = quotient(exportDrawn * this.deff, 100);
        this.soc -= exportDrawn;
      }
    }
    const loss = pvCharge - quotient(pvCharge * this.ceff, 100) +
      gridCharge - quotient(gridCharge * this.ceff, 100) +
      loadDrawn - loadDischarge + exportDrawn - batteryExport;
    const flows = [direct, pvCharge, pvExport, curtailed, loadDischarge,
      batteryExport, gridLoad, gridCharge];
    return new HourRecord(index, period, load, pv, this.soc, flows,
      loadDrawn + exportDrawn, shortfall, loss, this.prices[period], settings.FEEDIN);
  }

  run() {
    const records = this.data.loads.map((_, index) => this.runHour(index));
    return new SimulationResult(this.strategy, this.settings, this.prices,
      this.startSOC, this.reserve, records);
  }
}

class DispatchDesk {
  constructor(data) {
    this.data = data;
    this.settings = {...data.initialSettings};
    this.prices = {...data.initialPrices};
    this.current = null;
    this.handlers = {
      RUN: args => this.run(args), SET: args => this.setValue(args),
      PRICE: args => this.price(args), RESET: args => this.reset(args),
      CONFIG: args => this.config(args), NOBATTERY: args => this.noBattery(args),
      COMPARE: args => this.compare(args), SIZE: args => this.size(args),
      SWEEP: args => this.sweep(args), OUTAGE: args => this.outage(args),
      DIFF: args => this.diff(args), HOURLY: args => this.hourly(args),
      DAILY: args => this.daily(args), BILL: args => this.bill(args),
      SAVINGS: args => this.savings(args), BYPERIOD: args => this.byPeriod(args),
      DAYTYPE: args => this.dayType(args), PEAKS: args => this.peaks(args),
      PROFILE: args => this.profile(args), FLOWS: args => this.flows(args),
      SELFSUFF: args => this.selfSuff(args), CYCLES: args => this.cycles(args),
      USAGE: args => this.usage(args), HISTOGRAM: args => this.histogram(args),
      CHART: args => this.chart(args)
    };
  }

  execute(tokens) {
    const [command, ...args] = tokens;
    if (!Object.hasOwn(this.handlers, command)) return [`ERROR unknown command ${command}`];
    try {
      return this.handlers[command](args);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      return [`ERROR ${error.message}`];
    }
  }

  requireResult() {
    if (this.current === null) throw new CommandError('no run');
    return this.current;
  }

  checkedDay(text) {
    const day = Number(text);
    if (day < 1 || day > this.data.dayCount) throw new CommandError('invalid day');
    return day;
  }

  resultWithoutArguments(args) {
    requireCount(args, 0);
    return this.requireResult();
  }

  resultForDay(args) {
    requireCount(args, 1);
    const day = this.checkedDay(args[0]);
    return [day, this.requireResult()];
  }

  simulate(strategy, settings = this.settings, prices = this.prices, outage = null) {
    return new Simulator(this.data, strategy, settings, prices, outage).run();
  }

  baseline(settings, prices) {
    return this.simulate(['SELF', null], {...settings, CAPACITY: 0}, prices);
  }

  run(args) {
    const strategy = oneStrategy(args);
    const result = this.simulate(strategy);
    this.current = result;
    const total = result.total;
    return [`RUN ${strategyText(strategy)} bill ${money(result.bill)} ` +
      `import ${total.imported} export ${total.exported} soc ${result.endSOC}`];
  }

  setValue(args) {
    requireCount(args, 2);
    const [item, valueText] = args;
    if (!Object.hasOwn(SETTING_RANGES, item)) throw new CommandError(`unknown parameter ${item}`);
    const value = Number(valueText);
    const [min, max] = SETTING_RANGES[item];
    if (value < min || value > max) throw new CommandError(`invalid value for ${item}`);
    const previous = this.settings[item];
    this.settings[item] = value;
    return [`SET ${item} ${previous} -> ${value}`];
  }

  price(args) {
    requireCount(args, 2);
    const [period, valueText] = args;
    if (!Object.hasOwn(this.prices, period)) throw new CommandError(`unknown period ${period}`);
    const value = Number(valueText);
    if (value < 0 || value > 10000) throw new CommandError(`invalid value for ${period}`);
    const previous = this.prices[period];
    this.prices[period] = value;
    const [cheapest, peak] = tariffExtremes(this.prices);
    return [`PRICE ${period} ${previous} -> ${value} cheapest ${cheapest} peak ${peak}`];
  }

  reset(args) {
    requireCount(args, 0);
    this.settings = {...this.data.initialSettings};
    this.prices = {...this.data.initialPrices};
    return ['RESET'];
  }

  config(args) {
    requireCount(args, 0);
    const names = Object.keys(SETTING_RANGES);
    const settings = this.settings;
    const battery = names.slice(0, 8).map(item => `${item.toLowerCase()} ${settings[item]}`).join(' ');
    const grid = names.slice(8, 12).map(item => `${item.toLowerCase()} ${settings[item]}`).join(' ');
    const tariff = Object.entries(this.prices).map(([item, value]) => `${item} ${value}`).join(' ');
    const [cheapest, peak] = tariffExtremes(this.prices);
    return [`BATTERY ${battery}`, `GRID ${grid}`, `SOLAR pvscale ${settings.PVSCALE}`,
      `TARIFF ${tariff} cheapest ${cheapest} peak ${peak}`];
  }

  noBattery(args) {
    requireCount(args, 0);
    const result = this.baseline(this.settings, this.prices);
    const total = result.total;
    return [`NOBATTERY bill ${money(result.bill)} import ${total.imported} ` +
      `export ${total.exported} curtailed ${total.curtailed} peak ${result.peak}`];
  }

  compare(args) {
    const strategies = readStrategies(args);
    if (!strategies.length) throw new CommandError('wrong number of arguments');
    const baseline = this.baseline(this.settings, this.prices);
    const trials = strategies.map(strategy => this.simulate(strategy));
    trials.sort((a, b) => a.bill - b.bill);
    const output = [`COMPARE baseline ${money(baseline.bill)}`];
    trials.forEach((result, index) => {
      output.push(`${index + 1}. ${strategyText(result.strategy)} bill ${money(result.bill)} ` +
        `saving ${money(baseline.bill - result.bill)} sufficiency ${result.sufficiency}%`);
    });
    return output;
  }

  size(args) {
    requireCount(args, 3);
    const capacities = checkedRange(...args.map(Number), SETTING_RANGES.CAPACITY);
    const baseline = this.baseline(this.settings, this.prices);
    const output = [];
    let best = null;
    for (const capacity of capacities) {
      const settings = {...this.settings, CAPACITY: capacity};
      const result = this.simulate(['SELF', null], settings);
      const saving = baseline.bill - result.bill;
      const cost = quotient(capacity * settings.COST, 1000);
      let payback = 'never';
      if (saving > 0) {
        const tenths = quotient(10 * cost, saving);
        payback = `${quotient(tenths, 10)}.${tenths % 10}`;
        if (best === null || cost * best.saving < best.cost * saving) {
          best = {capacity, cost, saving};
        }
      }
      output.push(`SIZE ${capacity} bill ${money(result.bill)} saving ${money(saving)} ` +
        `cost ${money(cost)} payback ${payback}`);
    }
    output.push(`BEST ${best === null ? 'none' : best.capacity}`);
    return output;
  }

  sweep(args) {
    if (args.length < 5) throw new CommandError('wrong number of arguments');
    const item = args[0];
    if (!Object.hasOwn(SETTING_RANGES, item)) throw new CommandError(`unknown parameter ${item}`);
    const values = checkedRange(...args.slice(1, 4).map(Number), SETTING_RANGES[item]);
    const strategy = oneStrategy(args.slice(4));
    const output = [];
    let best = null;
    for (const value of values) {
      const settings = {...this.settings, [item]: value};
      const result = this.simulate(strategy, settings);
      const baseline = this.baseline(settings, this.prices);
      if (best === null || result.bill < best.bill) best = {value, bill: result.bill};
      output.push(`SWEEP ${item} ${value} bill ${money(result.bill)} ` +
        `saving ${money(baseline.bill - result.bill)} sufficiency ${result.sufficiency}%`);
    }
    output.push(`BEST ${best.value}`);
    return output;
  }

  outage(args) {
    requireCount(args, 3);
    const day = this.checkedDay(args[0]);
    const [start, end] = args.slice(1).map(Number);
    if (start < 0 || end > 23 || start > end) throw new CommandError('invalid hours');
    const current = this.requireResult();
    const first = (day - 1) * 24 + start;
    const last = (day - 1) * 24 + end;
    const result = this.simulate(current.strategy, current.settings, current.prices, [first, last]);
    const before = first ? result.hours[first - 1].soc : result.startSOC;
    const output = [`OUTAGE day ${day} hours ${start}-${end} ` +
      `strategy ${strategyText(result.strategy)} soc ${before}`,
    'hour   load     pv  disch    soc  short   curt'];
    const records = result.hours.slice(first, last + 1);
    for (const record of records) {
      output.push(tableRow([record.hour, record.load, record.pv, record.discharge,
        record.soc, record.shortfall, record.curtailed], [4, 7, 7, 7, 7, 7, 7]));
    }
    const total = new Totals(records);
    const served = total.load ? percentage(total.load - total.shortfall, total.load) : '100.00';
    output.push(`TOTAL load ${total.load} unserved ${total.shortfall} ` +
      `served ${served}% bill ${money(result.bill)}`);
    return output;
  }

  diff(args) {
    if (args.length < 2) throw new CommandError('wrong number of arguments');
    const day = this.checkedDay(args[0]);
    const strategy = oneStrategy(args.slice(1));
    const current = this.requireResult();
    const comparison = this.simulate(strategy, current.settings, current.prices);
    const output = [`DIFF day ${day} ${this.data.dayNames[day - 1]} ` +
      `${strategyText(current.strategy)} vs ${strategyText(strategy)}`,
    'hour   imp1   imp2   exp1   exp2   soc1   soc2'];
    const before = current.days[day - 1];
    const after = comparison.days[day - 1];
    for (let i = 0; i < before.length; ++i) {
      const first = before[i], second = after[i];
      output.push(tableRow([first.hour, first.imported, second.imported, first.exported,
        second.exported, first.soc, second.soc], [4, 7, 7, 7, 7, 7, 7]));
    }
    const cost1 = current.daily[day - 1].net_cost;
    const cost2 = comparison.daily[day - 1].net_cost;
    output.push(`TOTAL cost1 ${money(cost1)} cost2 ${money(cost2)} ` +
      `difference ${money(cost2 - cost1)}`);
    return output;
  }

  hourly(args) {
    const [day, result] = this.resultForDay(args);
    const output = [`HOURLY day ${day} ${this.data.dayNames[day - 1]} ` +
      `strategy ${strategyText(result.strategy)}`,
    'hour   load     pv charge  disch    soc import export   curt'];
    const widths = [4, ...Array(8).fill(7)];
    for (const record of result.days[day - 1]) {
      output.push(tableRow([record.hour, record.load, record.pv, record.charge,
        record.discharge, record.soc, record.imported, record.exported, record.curtailed], widths));
    }
    const total = result.daily[day - 1];
    output.push(tableRow(['sum', total.load, total.pv, total.charge,
      total.discharge, '', total.imported, total.exported, total.curtailed], widths));
    return output;
  }

  daily(args) {
    const result = this.resultWithoutArguments(args);
    const output = [`DAILY strategy ${strategyText(result.strategy)}`,
      'day name    load      pv  import  export    curt     soc      cost'];
    result.daily.forEach((total, index) => {
      output.push(tableRow([index + 1, this.data.dayNames[index], total.load, total.pv,
        total.imported, total.exported, total.curtailed, result.days[index].at(-1).soc,
        money(total.net_cost)], [3, 5, 8, 8, 8, 8, 8, 8, 10]));
    });
    const total = result.total;
    output.push(`TOTAL load ${total.load} pv ${total.pv} import ${total.imported} ` +
      `export ${total.exported} curtailed ${total.curtailed} cost ${money(total.net_cost)}`);
    return output;
  }

  bill(args) {
    const result = this.resultWithoutArguments(args);
    const output = [`BILL strategy ${strategyText(result.strategy)} days ${this.data.dayCount}`];
    for (const [period, total] of Object.entries(result.byPeriod)) {
      output.push(`IMPORT ${period} ${total.imported} Wh ${money(total.import_cost)}`);
    }
    output.push(`EXPORT ${result.total.exported} Wh ${money(-result.total.export_income)}`,
      `FIXED ${money(result.settings.FIXED)}`,
      `DEMAND ${result.peak} Wh ${money(result.demandCharge)}`,
      `TOTAL ${money(result.bill)}`);
    return output;
  }

  savings(args) {
    const result = this.resultWithoutArguments(args);
    const baseline = this.baseline(result.settings, result.prices);
    const pairs = [];
    for (const [period, total] of Object.entries(result.byPeriod)) {
      pairs.push([period, baseline.byPeriod[period].import_cost, total.import_cost]);
    }
    pairs.push(['EXPORT', -baseline.total.export_income, -result.total.export_income],
      ['DEMAND', baseline.demandCharge, result.demandCharge],
      ['TOTAL', baseline.bill, result.bill]);
    const output = [`SAVINGS strategy ${strategyText(result.strategy)}`];
    for (const [name, before, after] of pairs) {
      output.push(`${name} ${money(before)} -> ${money(after)} saving ${money(before - after)}`);
    }
    return output;
  }

  byPeriod(args) {
    const result = this.resultWithoutArguments(args);
    const output = [`BYPERIOD strategy ${strategyText(result.strategy)}`];
    for (const [period, total] of Object.entries(result.byPeriod)) {
      output.push(`${period} hours ${total.count} load ${total.load} pv ${total.pv} ` +
        `charge ${total.charge} discharge ${total.discharge} import ${total.imported} ` +
        `export ${total.exported}`);
    }
    return output;
  }

  dayType(args) {
    const result = this.resultWithoutArguments(args);
    const output = [`DAYTYPE strategy ${strategyText(result.strategy)}`];
    for (const [name, weekend] of [['WEEKDAY', false], ['WEEKEND', true]]) {
      const days = this.data.weekendDays.map((flag, index) => flag === weekend ? index : -1)
        .filter(index => index !== -1);
      const records = days.flatMap(day => result.days[day]);
      const total = new Totals(records);
      const count = days.length;
      output.push(`${name} days ${count} load ${quotient(total.load, count)} ` +
        `pv ${quotient(total.pv, count)} import ${quotient(total.imported, count)} ` +
        `export ${quotient(total.exported, count)} ` +
        `cost ${money(Math.trunc(total.net_cost / count))}`);
    }
    return output;
  }

  peaks(args) {
    requireCount(args, 1);
    const count = Number(args[0]);
    if (count < 1) throw new CommandError('invalid count');
    const result = this.requireResult();
    const records = result.hours.filter(record => record.imported > 0)
      .sort((a, b) => b.imported - a.imported || a.index - b.index);
    const output = [`PEAKS strategy ${strategyText(result.strategy)}`];
    records.slice(0, count).forEach((record, index) => {
      output.push(`${index + 1}. day ${record.day} hour ${record.hour} ${record.period} ` +
        `import ${record.imported} load ${record.load} soc ${record.soc}`);
    });
    if (!records.length) output.push('none');
    return output;
  }

  profile(args) {
    const result = this.resultWithoutArguments(args);
    const output = [`PROFILE strategy ${strategyText(result.strategy)} days ${this.data.dayCount}`,
      'hour   load     pv import export    soc'];
    for (let hour = 0; hour < 24; ++hour) {
      const records = result.hours.filter(record => record.hour === hour);
      const averages = ['load', 'pv', 'imported', 'exported', 'soc']
        .map(field => quotient(sum(records.map(record => record[field])), this.data.dayCount));
      output.push(tableRow([hour, ...averages], [4, 7, 7, 7, 7, 7]));
    }
    return output;
  }

  flows(args) {
    const result = this.resultWithoutArguments(args);
    const output = [`FLOWS strategy ${strategyText(result.strategy)}`];
    FLOW_NAMES.forEach((name, i) => output.push(`${name} ${result.total.flows[i]}`));
    output.push(`LOSSES ${result.total.loss}`, `STORED ${result.endSOC - result.startSOC}`);
    return output;
  }

  selfSuff(args) {
    const result = this.resultWithoutArguments(args);
    const flows = result.total.flows;
    return [`SELFSUFF sufficiency ${result.sufficiency}% ` +
      `consumption ${percentage(flows[0] + flows[1], result.total.pv)}%`];
  }

  cycles(args) {
    const result = this.resultWithoutArguments(args);
    const drawn = result.total.drawn;
    const capacity = result.settings.CAPACITY;
    const common = gcd(drawn, capacity);
    const numerator = quotient(drawn, common), denominator = quotient(capacity, common);
    const thousandths = quotient(1000 * drawn, capacity);
    const decimal = `${quotient(thousandths, 1000)}.${String(thousandths % 1000).padStart(3, '0')}`;
    return [`CYCLES ${numerator}/${denominator} ${decimal} ` +
      `drawn ${drawn} losses ${result.total.loss}`];
  }

  usage(args) {
    const result = this.resultWithoutArguments(args);
    const hours = result.hours;
    const charging = hours.filter(record => record.charge > 0).length;
    const discharging = hours.filter(record => record.drawn > 0).length;
    const idle = hours.filter(record => record.charge === 0 && record.drawn === 0).length;
    const full = hours.filter(record => record.soc === result.settings.CAPACITY).length;
    let low = 0, runLength = 0, longest = 0, first = null;
    for (const record of hours) {
      if (record.soc <= result.reserve) {
        ++low;
        ++runLength;
        if (runLength > longest) {
          longest = runLength;
          first = hours[record.index - runLength + 1];
        }
      } else {
        runLength = 0;
      }
    }
    let line = `USAGE charging ${charging} discharging ${discharging} idle ${idle} ` +
      `full ${full} low ${low} longest ${longest}`;
    if (first !== null) line += ` from day ${first.day} hour ${first.hour}`;
    return [line];
  }

  histogram(args) {
    const result = this.resultWithoutArguments(args);
    const counts = Array(10).fill(0);
    for (const record of result.hours) {
      ++counts[Math.min(9, quotient(10 * record.soc, result.settings.CAPACITY))];
    }
    const output = [`HISTOGRAM strategy ${strategyText(result.strategy)}`];
    counts.forEach((count, index) => {
      const width = quotient(20 * count, result.hours.length);
      output.push(`${String(10 * index).padStart(3)}% ${bar(width)} ${count}`);
    });
    return output;
  }

  chart(args) {
    const [day, result] = this.resultForDay(args);
    const capacity = result.settings.CAPACITY;
    const output = [`CHART day ${day} ${this.data.dayNames[day - 1]} ` +
      `strategy ${strategyText(result.strategy)}`];
    for (const record of result.days[day - 1]) {
      const width = quotient(20 * record.soc, capacity);
      output.push(`${String(record.hour).padStart(2)} ${bar(width)} ` +
        `${percentage(record.soc, capacity)}%`);
    }
    return output;
  }
}

function main() {
  const lines = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
  const data = new InputData(lines);
  const desk = new DispatchDesk(data);
  const output = [];
  for (const line of data.commands) {
    const tokens = line.split(' ');
    if (tokens[0] === 'END') break;
    output.push(...desk.execute(tokens));
  }
  if (output.length) process.stdout.write(output.join('\n') + '\n');
}

main();
