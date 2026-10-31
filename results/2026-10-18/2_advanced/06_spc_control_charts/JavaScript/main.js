'use strict';

const fs = require('node:fs');
const {readDataset} = require('./dataset');
const {subgroupStatistics, movingRanges, familyLimits, outside} = require('./variable_charts');
const {attributeModel, attributeLot} = require('./attribute_charts');
const {runRules, zoneName} = require('./run_rules');
const {computeCapability, frequencyDistribution} = require('./capability');
const {variableBand, cusumBand, averageBand, standardizedBand} = require('./plot');

const FAMILIES = ['XBAR_R', 'XBAR_S', 'I_MR'];
const CHARTS = ['XBAR_R', 'R', 'XBAR_S', 'S', 'I', 'MR', 'CUSUM', 'EWMA', 'MA'];
const FAMILY_CHARTS = new Map([
  ['XBAR_R', ['XBAR_R', 'R']], ['XBAR_S', ['XBAR_S', 'S']], ['I_MR', ['I', 'MR']],
]);
const ATTRIBUTE_CHARTS = ['p', 'np', 'c', 'u'];
const SPREAD_CHARTS = new Set(['R', 'S', 'MR']);

function numbers(first, last) {
  return Array.from({length: last - first + 1}, (_, index) => first + index);
}

function real(value) {
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.0000`;
  const result = value.toFixed(4);
  return result === '-0.0000' ? '0.0000' : result;
}

function numberList(values) {
  return values.length === 0 ? 'none' : values.join(' ');
}

function estimateFamily(family, data) {
  const {spec, groups, samples, constants} = data;
  const count = spec.phase1_subgroups * (family === 'I_MR' ? spec.subgroup_size : 1);
  const initial = numbers(1, count);
  let retained = initial;
  let model;
  let status = 'stopped';
  const passes = [];
  for (let pass = 1; pass <= spec.max_passes; pass++) {
    model = familyLimits(family, retained, groups, samples, spec.subgroup_size, constants);
    const outliers = new Set();
    for (let chart = 0; chart < 2; chart++) {
      for (const point of model.sequences[chart]) {
        if (outside(point.value, model.limits[chart])) outliers.add(point.number);
      }
    }
    const out = retained.filter(number => outliers.has(number));
    passes.push({pass, count: retained.length, model, out});
    if (out.length === 0) {
      status = 'converged';
      break;
    }
    if (pass === spec.max_passes) break;
    retained = retained.filter(number => !outliers.has(number));
  }
  const kept = new Set(retained);
  return {family, retained, removed: initial.filter(number => !kept.has(number)), passes, status, model};
}

function phaseOneChecks(families, spec) {
  const checks = new Map();
  for (const family of FAMILIES) {
    const model = families.get(family).model;
    const names = FAMILY_CHARTS.get(family);
    for (let index = 0; index < names.length; index++) {
      const chart = names[index];
      const sequence = model.sequences[index];
      const control = model.limits[index];
      checks.set(chart, {sequence, control, signals: runRules(sequence, control, spec.rules.get(chart))});
    }
  }
  return checks;
}

function phaseTwoSequences(data) {
  const groups = data.groups.slice(data.spec.phase1_subgroups);
  const sampleStart = data.spec.phase1_subgroups * data.spec.subgroup_size;
  const individual = data.samples.slice(sampleStart).map(sample => ({number: sample.number, value: sample.value}));
  const ranges = movingRanges(data.samples).filter(point => point.number > sampleStart);
  const means = groups.map(group => ({number: group.number, value: group.mean}));
  return new Map([
    ['XBAR_R', means], ['R', groups.map(group => ({number: group.number, value: group.range}))],
    ['XBAR_S', means], ['S', groups.map(group => ({number: group.number, value: group.sd}))],
    ['I', individual], ['MR', ranges],
  ]);
}

function monitorShewhart(sequences, checks, spec) {
  const signals = [];
  for (const [chart, sequence] of sequences) {
    for (const signal of runRules(sequence, checks.get(chart).control, spec.rules.get(chart))) {
      signals.push({chart, ...signal});
    }
  }
  return signals;
}

function monitorAverages(data, families) {
  const {spec, constants, groups} = data;
  const xr = families.get('XBAR_R').model.limits;
  const center = xr[0].cl;
  const sigma = xr[1].cl / constants.d2 / Math.sqrt(spec.subgroup_size);
  const reference = spec.cusum_k * sigma;
  const threshold = spec.cusum_h * sigma;
  const lambda = spec.ewma_lambda;
  const q = (1 - lambda) * (1 - lambda);
  const rho = lambda / (2 - lambda);
  const ewmaWidth = spec.ewma_l * sigma * Math.sqrt(rho);
  const maWidth = 3 * sigma / Math.sqrt(spec.ma_span);
  const baseline = {center, sigma, reference, threshold, ewmaWidth, maWidth};
  const rows = new Map();
  const signals = [];
  let plus = 0;
  let minus = 0;
  let plusLength = 0;
  let minusLength = 0;
  let z = center;
  let factor = 1;
  for (const group of groups.slice(spec.phase1_subgroups)) {
    const end = group.number;
    plus = Math.max(0, plus + (group.mean - center - reference));
    minus = Math.max(0, minus + (center - group.mean - reference));
    plusLength = plus > 0 ? plusLength + 1 : 0;
    minusLength = minus > 0 ? minusLength + 1 : 0;
    const row = {plus, minus};
    const upper = plus > threshold;
    const lower = minus > threshold;
    if (upper) signals.push({chart: 'CUSUM', rule: 'UPPER', start: end - plusLength + 1,
      end, value: plus, direction: 'UP'});
    if (lower) signals.push({chart: 'CUSUM', rule: 'LOWER', start: end - minusLength + 1,
      end, value: minus, direction: 'DOWN'});
    if (upper) {
      plus = 0;
      plusLength = 0;
    }
    if (lower) {
      minus = 0;
      minusLength = 0;
    }
    z = lambda * group.mean + (1 - lambda) * z;
    factor = factor * q;
    const currentEwmaWidth = spec.ewma_l * sigma * Math.sqrt(rho * (1 - factor));
    row.ewma = z;
    row.ewmaWidth = currentEwmaWidth;
    row.ewmaLcl = center - currentEwmaWidth;
    row.ewmaUcl = center + currentEwmaWidth;
    if (z > row.ewmaUcl) signals.push({chart: 'EWMA', rule: 'UPPER', start: end, end, value: z, direction: 'UP'});
    if (z < row.ewmaLcl) signals.push({chart: 'EWMA', rule: 'LOWER', start: end, end, value: z, direction: 'DOWN'});
    const start = Math.max(spec.phase1_subgroups + 1, end - spec.ma_span + 1);
    const count = end - start + 1;
    let total = 0;
    for (let number = start; number <= end; number++) total += groups[number - 1].total;
    row.ma = total / (spec.subgroup_size * count);
    row.maWidth = 3 * sigma / Math.sqrt(count);
    row.maLcl = center - row.maWidth;
    row.maUcl = center + row.maWidth;
    if (row.ma > row.maUcl) signals.push({chart: 'MA', rule: 'UPPER', start, end, value: row.ma, direction: 'UP'});
    if (row.ma < row.maLcl) signals.push({chart: 'MA', rule: 'LOWER', start, end, value: row.ma, direction: 'DOWN'});
    rows.set(end, row);
  }
  return {baseline, rows, signals};
}

function sortSignals(signals, size) {
  const chartOrder = new Map(CHARTS.map((chart, index) => [chart, index]));
  const ruleOrder = rule => typeof rule === 'number' ? rule : rule === 'UPPER' ? 9 : 10;
  signals.sort((left, right) => chartOrder.get(left.chart) - chartOrder.get(right.chart)
    || left.end - right.end || ruleOrder(left.rule) - ruleOrder(right.rule));
  for (const signal of signals) {
    signal.subgroup = signal.chart === 'I' || signal.chart === 'MR'
      ? Math.floor((signal.end - 1) / size) + 1 : signal.end;
  }
}

function characterizeEvents(signals, data, families, baseline) {
  const numbersWithSignals = [...new Set(signals.map(signal => signal.subgroup))].sort((left, right) => left - right);
  const events = [];
  for (const number of numbersWithSignals) {
    const previous = events.at(-1);
    if (previous && number - previous.end - 1 <= data.spec.event_gap) previous.end = number;
    else events.push({number: events.length + 1, start: number, end: number});
  }
  const categories = ['locationUp', 'locationDown', 'spreadUp', 'spreadDown', 'pattern'];
  const types = ['SHIFT_UP', 'SHIFT_DOWN', 'SPREAD_UP', 'SPREAD_DOWN', 'PATTERN'];
  const referenceSd = families.get('XBAR_S').model.limits[1].cl;
  for (const event of events) {
    event.length = event.end - event.start + 1;
    event.signals = signals.filter(signal => signal.subgroup >= event.start && signal.subgroup <= event.end);
    for (const category of categories) event[category] = 0;
    event.detection = new Map();
    let onset = null;
    for (const signal of event.signals) {
      if (signal.direction === 'NONE') event.pattern++;
      else if (SPREAD_CHARTS.has(signal.chart)) {
        if (signal.direction === 'UP') event.spreadUp++;
        else event.spreadDown++;
      } else if (signal.direction === 'UP') event.locationUp++;
      else event.locationDown++;
      const previous = event.detection.get(signal.chart);
      if (previous === undefined || signal.subgroup < previous) event.detection.set(signal.chart, signal.subgroup);
      if (signal.chart === 'CUSUM') onset = onset === null ? signal.start : Math.min(onset, signal.start);
    }
    event.onset = onset === null ? event.start : onset;
    let best = 0;
    for (let index = 1; index < categories.length; index++) {
      if (event[categories[index]] > event[categories[best]]) best = index;
    }
    event.type = types[best];
    let total = 0;
    let deviations = 0;
    event.outOfSpec = 0;
    for (let number = event.start; number <= event.end; number++) {
      const group = data.groups[number - 1];
      total += group.total;
      deviations += group.sd;
      for (const sample of group.samples) {
        if (sample.value < data.spec.lsl || sample.value > data.spec.usl) event.outOfSpec++;
      }
    }
    const mean = total / (data.spec.subgroup_size * event.length);
    event.shift = (mean - baseline.center) / baseline.sigma;
    event.spread = (deviations / event.length) / referenceSd;
  }
  return events;
}

function proposedLimits(data, families, eventAt) {
  const accepted = data.groups.slice(data.spec.phase1_subgroups).filter(group => eventAt[group.number] === null);
  const proposed = new Map();
  for (const family of FAMILIES) {
    const points = families.get(family).retained.slice();
    for (const group of accepted) {
      if (family === 'I_MR') {
        for (const sample of group.samples) points.push(sample.number);
      } else points.push(group.number);
    }
    const model = familyLimits(family, points, data.groups, data.samples, data.spec.subgroup_size, data.constants);
    proposed.set(family, {points, model});
  }
  return proposed;
}

function estimateAttribute(chart, lots, spec) {
  const initial = numbers(1, lots.length);
  let retained = initial;
  let model;
  let status = 'stopped';
  const passes = [];
  for (let pass = 1; pass <= spec.max_passes; pass++) {
    model = attributeModel(chart, retained, lots);
    const out = retained.filter(number => attributeLot(chart, model, lots[number - 1]).status !== 'ok');
    passes.push({pass, count: retained.length, center: model.center, out});
    if (out.length === 0) {
      status = 'converged';
      break;
    }
    if (pass === spec.max_passes) break;
    const excluded = new Set(out);
    retained = retained.filter(number => !excluded.has(number));
  }
  const kept = new Set(retained);
  const removed = initial.filter(number => !kept.has(number));
  const rows = lots.map(lot => attributeLot(chart, model, lot));
  const sequence = rows.map(row => ({number: row.number, value: row.z}));
  const signals = runRules(sequence, {lcl: -3, cl: 0, ucl: 3}, spec.rules.get('STD'));
  return {chart, retained, removed, passes, status, rows, signals};
}

function capabilityTarget(points, data) {
  const groups = points.map(number => data.groups[number - 1]);
  const samples = groups.flatMap(group => group.samples);
  const values = computeCapability(groups, samples, data.spec, data.constants);
  return {groups, samples, values};
}

function collectCapability(data, families) {
  const phase1 = capabilityTarget(families.get('XBAR_R').retained, data);
  const phase2 = capabilityTarget(numbers(data.spec.phase1_subgroups + 1, data.groups.length), data);
  const rolling = [];
  for (let start = data.spec.phase1_subgroups + 1;
    start + data.spec.rolling_window - 1 <= data.groups.length; start += data.spec.rolling_step) {
    const end = start + data.spec.rolling_window - 1;
    rolling.push({start, end, ...capabilityTarget(numbers(start, end), data)});
  }
  return {phase1, phase2, rolling};
}

function controlText(name, control) {
  return `${name} lcl ${real(control.lcl)} cl ${real(control.cl)} ucl ${real(control.ucl)}`;
}

function familyControlText(family, model) {
  const first = family === 'I_MR' ? 'I' : 'XBAR';
  const second = family === 'I_MR' ? 'MR' : family === 'XBAR_R' ? 'R' : 'S';
  return `${controlText(first, model.limits[0])} ${controlText(second, model.limits[1])}`;
}

function limitsReport(data, families, checks, proposed, averages, signals) {
  const {spec, groups, samples} = data;
  const lines = [`characteristic ${spec.characteristic}`, `subgroup_size ${spec.subgroup_size}`,
    `subgroups ${groups.length}`, `samples ${samples.length}`, `phase1_subgroups ${spec.phase1_subgroups}`];
  for (const family of FAMILIES) {
    const result = families.get(family);
    lines.push(`family ${family}`);
    for (const pass of result.passes) {
      lines.push(`pass ${pass.pass} points ${pass.count} ${familyControlText(family, pass.model)} out ${numberList(pass.out)}`);
    }
    lines.push(`result ${result.status} passes ${result.passes.length} retained ${result.retained.length} removed ${numberList(result.removed)}`);
  }
  for (const [chart, check] of checks) {
    for (const signal of check.signals) {
      lines.push(`phase1_signal ${chart} ${signal.rule} ${signal.start} ${signal.end} ${real(signal.value)}`);
    }
    lines.push(`phase1_check ${chart} points ${check.sequence.length} signals ${check.signals.length}`);
  }
  for (const family of FAMILIES) {
    const result = proposed.get(family);
    lines.push(`proposed ${family} points ${result.points.length} ${familyControlText(family, result.model)}`);
  }
  const {center, sigma, reference, threshold, ewmaWidth, maWidth} = averages.baseline;
  lines.push(`cusum target ${real(center)} sigma ${real(sigma)} k ${real(reference)} h ${real(threshold)}`);
  lines.push(`ewma target ${real(center)} sigma ${real(sigma)} lcl ${real(center - ewmaWidth)} ucl ${real(center + ewmaWidth)}`);
  lines.push(`ma target ${real(center)} sigma ${real(sigma)} span ${spec.ma_span} lcl ${real(center - maWidth)} ucl ${real(center + maWidth)}`);
  for (const chart of CHARTS) {
    const found = signals.filter(signal => signal.chart === chart);
    const ends = new Set(found.map(signal => signal.end));
    const first = found.length === 0 ? 'none' : found[0].end;
    const points = chart === 'I' || chart === 'MR'
      ? samples.length - spec.phase1_subgroups * spec.subgroup_size : groups.length - spec.phase1_subgroups;
    const rules = spec.rules.get(chart) || ['UPPER', 'LOWER'];
    const counts = rules.map(rule => `${rule}:${found.filter(signal => signal.rule === rule).length}`);
    lines.push(`phase2 ${chart} points ${points} signals ${found.length} signalled ${ends.size} first ${first} by_rule ${counts.join(' ')}`);
  }
  return lines;
}

function signalsReport(signals) {
  return ['chart,rule,start,end,value,direction', ...signals.map(signal =>
    `${signal.chart},${signal.rule},${signal.start},${signal.end},${real(signal.value)},${signal.direction}`)];
}

function eventsReport(events) {
  const lines = [`events ${events.length}`];
  for (const event of events) {
    const charts = CHARTS.filter(chart => event.detection.has(chart)).join(',');
    lines.push(`event ${event.number} start ${event.start} end ${event.end} length ${event.length}`
      + ` signals ${event.signals.length} charts ${charts} location_up ${event.locationUp} location_down ${event.locationDown}`
      + ` spread_up ${event.spreadUp} spread_down ${event.spreadDown} pattern ${event.pattern} onset ${event.onset}`
      + ` shift ${real(event.shift)} spread ${real(event.spread)} out_of_spec ${event.outOfSpec} type ${event.type}`);
    const detections = CHARTS.map(chart => `${chart}:${event.detection.get(chart) ?? '-'}`);
    lines.push(`detection ${event.number} ${detections.join(' ')}`);
  }
  return lines;
}

function subgroupsReport(data, families, averages, signals, eventAt) {
  const lines = ['subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event'];
  const excluded = new Set(families.get('XBAR_R').removed);
  const control = families.get('XBAR_R').model.limits[0];
  const counts = Array(data.groups.length + 1).fill(0);
  for (const signal of signals) counts[signal.subgroup]++;
  for (const group of data.groups) {
    const number = group.number;
    const phase = number > data.spec.phase1_subgroups ? 'phase2' : excluded.has(number) ? 'excluded' : 'phase1';
    const row = averages.rows.get(number);
    const values = row ? [real(row.plus), real(row.minus), real(row.ewma), real(row.ma)] : ['-', '-', '-', '-'];
    lines.push([number, phase, real(group.mean), zoneName(group.mean, control), group.range, real(group.sd),
      ...values, counts[number], eventAt[number]?.number ?? '-'].join(','));
  }
  return lines;
}

function attributesReport(attributes) {
  const lines = [];
  for (const chart of ATTRIBUTE_CHARTS) {
    const result = attributes.get(chart);
    lines.push(`chart ${chart}`);
    for (const pass of result.passes) {
      lines.push(`pass ${pass.pass} lots ${pass.count} center ${real(pass.center)} out ${numberList(pass.out)}`);
    }
    lines.push(`result ${result.status} passes ${result.passes.length} retained ${result.retained.length} removed ${numberList(result.removed)}`);
    for (const row of result.rows) {
      const value = chart === 'np' || chart === 'c' ? String(row.value) : real(row.value);
      lines.push(`lot ${row.number} size ${row.inspected} value ${value} lcl ${real(row.lcl)} ucl ${real(row.ucl)} z ${real(row.z)} status ${row.status}`);
    }
    for (const signal of result.signals) {
      lines.push(`signal ${signal.rule} ${signal.start} ${signal.end} ${real(signal.value)}`);
    }
    lines.push(`signals ${result.signals.length}`);
  }
  return lines;
}

function capabilityReport(targets, spec) {
  const lines = [];
  const fields = [['mean', 'mean'], ['sigma_within', 'sigmaWithin'], ['sigma_sbar', 'sigmaSbar'],
    ['sigma_overall', 'sigmaOverall'], ['cp', 'cp'], ['cpu', 'cpu'], ['cpl', 'cpl'], ['cpk', 'cpk'],
    ['pp', 'pp'], ['ppu', 'ppu'], ['ppl', 'ppl'], ['ppk', 'ppk'], ['cpm', 'cpm']];
  for (const name of ['phase1', 'phase2']) {
    const target = targets[name];
    const values = target.values;
    lines.push(`group ${name} subgroups ${target.groups.length} values ${target.samples.length}`);
    for (const [label, property] of fields) lines.push(`${label} ${real(values[property])}`);
    lines.push(`cpk_ci ${values.cpkCI.map(real).join(' ')}`);
    lines.push(`ppk_ci ${values.ppkCI.map(real).join(' ')}`);
    lines.push(`below_lsl ${values.below}`);
    lines.push(`above_usl ${values.above}`);
    lines.push(`ppm ${real(values.ppm)}`);
    for (const sample of values.outOfSpec) {
      lines.push(`out_of_spec sample ${sample.number} subgroup ${sample.subgroup} value ${sample.value} side ${sample.side}`);
    }
    lines.push(`verdict ${values.verdict}`);
    for (const bin of frequencyDistribution(target.samples, spec)) {
      let line = `bin ${bin.lower} ${bin.upper} ${bin.frequency}`;
      if (bin.barLength > 0) line += ' ' + '#'.repeat(bin.barLength);
      if (bin.marks.length > 0) line += ' ' + bin.marks.join(' ');
      lines.push(line);
    }
  }
  for (const target of targets.rolling) {
    const values = target.values;
    lines.push(`rolling ${target.start} ${target.end} mean ${real(values.mean)} sigma_within ${real(values.sigmaWithin)}`
      + ` sigma_overall ${real(values.sigmaOverall)} cpk ${real(values.cpk)} ppk ${real(values.ppk)} verdict ${values.verdict}`);
  }
  return lines;
}

function chartsReport(data, families, averages, attributes, signals) {
  const lines = [];
  const ends = new Map(CHARTS.map(chart => [chart, new Set()]));
  const cusumUpper = new Set();
  const cusumLower = new Set();
  for (const signal of signals) {
    ends.get(signal.chart).add(signal.end);
    if (signal.chart === 'CUSUM') (signal.rule === 'UPPER' ? cusumUpper : cusumLower).add(signal.end);
  }
  const pictures = [
    {name: 'XBAR', chart: 'XBAR_R', family: 'XBAR_R', control: 0, property: 'mean'},
    {name: 'R', chart: 'R', family: 'XBAR_R', control: 1, property: 'range'},
    {name: 'S', chart: 'S', family: 'XBAR_S', control: 1, property: 'sd'},
  ];
  for (const picture of pictures) {
    const family = families.get(picture.family);
    const control = family.model.limits[picture.control];
    const removed = new Set(family.removed);
    lines.push(`chart ${controlText(picture.name, control)}`);
    for (const group of data.groups) {
      const number = String(group.number).padStart(3, ' ');
      const phase2 = group.number > data.spec.phase1_subgroups;
      const mark = phase2 ? '2' : removed.has(group.number) ? 'x' : '1';
      const value = group[picture.property];
      const band = variableBand(control, value, phase2 && ends.get(picture.chart).has(group.number));
      lines.push(`${number} ${mark} ${band} ${real(value)}`);
    }
  }
  const {center, threshold, ewmaWidth, maWidth} = averages.baseline;
  lines.push(`chart CUSUM h ${real(threshold)}`);
  for (const [number, row] of averages.rows) {
    const band = cusumBand(row.plus, row.minus, threshold, cusumUpper.has(number), cusumLower.has(number));
    lines.push(`${String(number).padStart(3, ' ')} ${band} ${real(row.plus)} ${real(row.minus)}`);
  }
  for (const chart of ['EWMA', 'MA']) {
    const width = chart === 'EWMA' ? ewmaWidth : maWidth;
    lines.push(`chart ${controlText(chart, {lcl: center - width, cl: center, ucl: center + width})}`);
    for (const [number, row] of averages.rows) {
      const value = chart === 'EWMA' ? row.ewma : row.ma;
      const currentWidth = chart === 'EWMA' ? row.ewmaWidth : row.maWidth;
      const lower = chart === 'EWMA' ? row.ewmaLcl : row.maLcl;
      const upper = chart === 'EWMA' ? row.ewmaUcl : row.maUcl;
      const band = averageBand(value, currentWidth, width, center, ends.get(chart).has(number));
      lines.push(`${String(number).padStart(3, ' ')} ${band} ${real(value)} ${real(lower)} ${real(upper)}`);
    }
  }
  for (const chart of ATTRIBUTE_CHARTS) {
    lines.push(`chart ${chart.toUpperCase()}_STD lcl -3.0000 cl 0.0000 ucl 3.0000`);
    for (const row of attributes.get(chart).rows) {
      const band = standardizedBand(row.z, row.status);
      lines.push(`${String(row.number).padStart(3, ' ')} ${band} ${real(row.z)}`);
    }
  }
  return lines;
}

function writeReport(name, lines) {
  fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

function main() {
  const data = readDataset();
  data.groups = subgroupStatistics(data.samples, data.spec.subgroup_size);
  const families = new Map(FAMILIES.map(family => [family, estimateFamily(family, data)]));
  const checks = phaseOneChecks(families, data.spec);
  const sequences = phaseTwoSequences(data);
  const signals = monitorShewhart(sequences, checks, data.spec);
  const averages = monitorAverages(data, families);
  for (const signal of averages.signals) signals.push(signal);
  sortSignals(signals, data.spec.subgroup_size);
  const events = characterizeEvents(signals, data, families, averages.baseline);
  const eventAt = Array(data.groups.length + 1).fill(null);
  for (const event of events) {
    for (let number = event.start; number <= event.end; number++) eventAt[number] = event;
  }
  const proposed = proposedLimits(data, families, eventAt);
  const attributes = new Map(ATTRIBUTE_CHARTS.map(chart => [chart, estimateAttribute(chart, data.lots, data.spec)]));
  const targets = collectCapability(data, families);
  fs.mkdirSync('output', {recursive: true});
  writeReport('limits.txt', limitsReport(data, families, checks, proposed, averages, signals));
  writeReport('signals.csv', signalsReport(signals));
  writeReport('events.txt', eventsReport(events));
  writeReport('subgroups.csv', subgroupsReport(data, families, averages, signals, eventAt));
  writeReport('attribute_charts.txt', attributesReport(attributes));
  writeReport('capability.txt', capabilityReport(targets, data.spec));
  writeReport('charts.txt', chartsReport(data, families, averages, attributes, signals));
}

if (require.main === module) main();
