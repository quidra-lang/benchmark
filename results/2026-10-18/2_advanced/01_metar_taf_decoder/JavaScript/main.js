'use strict';

const fs = require('node:fs');
const path = require('node:path');
const groups = require('./groups');
const metar = require('./metar');
const taf = require('./taf');
const verification = require('./verification');
const {Calendar, floorDiv, pad, sin, cos, mileFraction, meterValue,
  compareVisibility, fraction} = require('./units');

const CATEGORIES = verification.CATEGORIES;

function readLines(filename) {
  return fs.readFileSync(path.join('input', filename), 'ascii').split('\n').slice(0, -1);
}

function readInputs() {
  const stations = new Map();
  for (const line of readLines('stations.txt')) {
    const [code, elevation, runwayList, ...name] = line.split(' ');
    const runways = runwayList.split(',').map(entry => {
      const [runwayName, heading] = entry.split('/');
      return {name: runwayName, heading: Number(heading)};
    });
    stations.set(code, {code, elevation: Number(elevation), runways, name: name.join(' ')});
  }
  const settings = new Map(readLines('params.txt').map(line => {
    const [name, ...values] = line.split(' ');
    return [name, values];
  }));
  const params = {year: Number(settings.get('YEAR')[0]), month: Number(settings.get('MONTH')[0]),
    crosswind: Number(settings.get('CROSSWIND_LIMIT')[0]),
    tailwind: Number(settings.get('TAILWIND_LIMIT')[0]), verify: settings.get('VERIFY')};
  const reports = [];
  for (const line of readLines('reports.txt')) {
    const words = line.replace(/^ +/, '').split(' ');
    if (line.startsWith(' ')) reports.at(-1).words.push(...words);
    else reports.push({number: reports.length + 1, words});
  }
  return {stations, params, reports};
}

function errorRecorder(errors, reportNumber) {
  return (position, reason, text = null) => {
    const content = reason + (text === null ? '' : ` "${text}"`);
    errors.push({report: reportNumber, position, content});
  };
}

function parseHeader(raw, stations, calendar, error) {
  const words = raw.words;
  const kind = words[0];
  if (!['METAR', 'SPECI', 'TAF'].includes(kind)) {
    error(1, 'rejected report, invalid type', kind);
    return null;
  }
  let cursor = 1;
  let modifier = null;
  if (kind === 'TAF' && ['AMD', 'COR'].includes(words[cursor])) modifier = words[cursor++];
  const report = {number: raw.number, kind, modifier};
  for (const item of kind === 'TAF' ? ['station', 'time', 'validity'] : ['station', 'time']) {
    if (cursor === words.length) {
      error(words.length + 1, `rejected report, missing ${item}`);
      return null;
    }
    const word = words[cursor];
    let valid = false;
    if (item === 'station') {
      valid = stations.has(word);
      if (valid) report.station = stations.get(word);
    } else if (item === 'time') {
      report.time = calendar.observationTime(word);
      valid = report.time !== null;
      if (valid) report.issueDay = floorDiv(report.time, 1440) + 1;
    } else {
      const period = calendar.period(word, report.issueDay, 1800);
      valid = period !== null;
      if (valid) Object.assign(report, period);
    }
    if (!valid) {
      error(cursor + 1, `rejected report, invalid ${item}`, word);
      return null;
    }
    cursor += 1;
  }
  report.bodyStart = cursor;
  return report;
}

function joinGroups(words, start) {
  const result = [];
  for (let index = start; index < words.length; index += 1) {
    const position = index + 1;
    let text = words[index];
    if (/^\d$/.test(text) && index + 1 < words.length && /^\d\/\d{1,2}SM$/.test(words[index + 1])) {
      text += ' ' + words[++index];
    }
    result.push({text, position});
  }
  return result;
}

function matchSection(body, slots, context, station, error) {
  const section = groups.section(context);
  let current = 0;
  for (const group of body) {
    let found = current;
    let value = null;
    for (; found < slots.length; found += 1) {
      value = slots[found].test(group.text);
      if (value !== null) break;
    }
    if (found === slots.length) {
      const earlier = slots.slice(0, current).some(slot => slot.test(group.text) !== null);
      error(group.position, earlier ? 'out of order group' : 'unknown group', group.text);
      continue;
    }
    const slot = slots[found];
    if (!groups.valid(slot.kind, value, section, station)) {
      error(group.position, 'invalid group', group.text);
      continue;
    }
    groups.accept(section, slot.kind, value);
    if (slot.kind === 'visibility' && value.kind === 'cavok') {
      current = slots.findIndex(candidate => candidate.kind === 'cloud') + 1;
    } else {
      current = found + (slot.repeat ? 0 : 1);
    }
  }
  return section;
}

function ceiling(state) {
  const layer = (state.cloud ?? []).find(cloud => ['BKN', 'OVC', 'VV'].includes(cloud.amount));
  return layer === undefined ? null : layer.height;
}

function flightCategory(state) {
  const height = ceiling(state);
  const visibility = state.visibility === null ? null : mileFraction(state.visibility);
  const less = value => visibility !== null && visibility[0] < value * visibility[1];
  const atMost = value => visibility !== null && visibility[0] <= value * visibility[1];
  if (height !== null && height < 500 || less(1)) return 'LIFR';
  if (height !== null && height < 1000 || less(3)) return 'IFR';
  if (height !== null && height <= 3000 || atMost(5)) return 'MVFR';
  return 'VFR';
}

function components(direction, heading, speed) {
  const angle = direction - heading;
  return {head: floorDiv(speed * cos(angle), 1000), cross: floorDiv(speed * sin(angle), 1000)};
}

function runwayWinds(wind, station, params) {
  if (wind === null || wind.variable || wind.calm) return null;
  const runways = [];
  let preferred = null;
  for (const runway of station.runways) {
    const mean = components(wind.direction, runway.heading, wind.speed);
    const gust = wind.gust === null ? null : components(wind.direction, runway.heading, wind.gust);
    const deciding = gust ?? mean;
    const usable = Math.abs(deciding.cross) <= params.crosswind && -deciding.head <= params.tailwind;
    const result = {name: runway.name, mean, gust, usable};
    runways.push(result);
    if (usable && (preferred === null || mean.head > preferred.mean.head)) preferred = result;
  }
  return {runways, preferred};
}

function windChanges(earlier, later, alpha) {
  if (earlier === null || later === null) return [];
  const reasons = [];
  if (!earlier.variable && !earlier.calm && !later.variable && !later.calm
      && Math.max(earlier.speed, later.speed) >= 10) {
    const difference = Math.abs(earlier.direction - later.direction) % 360;
    if (Math.min(difference, 360 - difference) >= alpha) reasons.push('wind shift');
  }
  if (Math.abs(earlier.speed - later.speed) >= 10) reasons.push('wind speed');
  return reasons;
}

function speciCheck(previous, report) {
  if (previous === undefined) return ['no previous report'];
  const before = previous.main;
  const after = report.main;
  const reasons = [];
  if (before.category !== after.category) reasons.push(`category ${before.category} to ${after.category}`);
  reasons.push(...windChanges(before.wind, after.wind, 45));
  const thunderstorm = state => (state.weather ?? []).some(weather => weather.descriptor === 'TS');
  const freezing = state => (state.weather ?? []).some(weather => weather.descriptor === 'FZ'
    && weather.phenomena.some(code => code === 'DZ' || code === 'RA'));
  if (thunderstorm(before) !== thunderstorm(after)) reasons.push(`thunderstorm ${thunderstorm(after) ? 'began' : 'ended'}`);
  if (freezing(before) !== freezing(after)) reasons.push(`freezing precipitation ${freezing(after) ? 'began' : 'ended'}`);
  return reasons.length === 0 ? ['no criteria met'] : reasons;
}

function decodeObservation(report, body, params, error) {
  const parts = metar.splitBody(body);
  report.main = matchSection(parts.main, metar.MAIN_SLOTS, 'main', report.station, error);
  report.trends = metar.readTrends(parts.trends, error).map(trend => ({...trend,
    state: matchSection(trend.groups, taf.SLOTS, 'trend', report.station, error)}));
  report.remarks = metar.readRemarks(parts.remarks);
  const main = report.main;
  main.ceiling = ceiling(main);
  main.category = flightCategory(main);
  report.pressureAltitude = main.pressure === null ? null
    : report.station.elevation + (2992 - main.pressure.inHg) * 10;
  report.densityAltitude = report.pressureAltitude === null || main.temperature === null ? null
    : report.pressureAltitude + floorDiv(120 * (1000 * main.temperature.temperature - 15000
      + 2 * report.pressureAltitude), 1000);
  report.runwayWinds = runwayWinds(main.wind, report.station, params);
}

function decodeForecast(report, body, calendar, error) {
  const parts = taf.splitBody(body, report, calendar, error);
  report.base = matchSection(parts.base, taf.SLOTS, 'base', report.station, error);
  report.changes = parts.changes.map(change => ({...change,
    state: matchSection(change.groups, taf.SLOTS, 'change', report.station, error)}));
  report.timeline = taf.expand(report);
  for (const hour of report.timeline.values()) {
    hour.prevailing.category = flightCategory(hour.prevailing);
    for (const change of hour.temporary) change.state.category = flightCategory(change.state);
  }
}

function windPhrase(wind) {
  if (wind.calm) return 'calm';
  let phrase = wind.variable ? `variable at ${wind.speed} KT`
    : `${pad(wind.direction, 3)} degrees at ${wind.speed} KT`;
  if (wind.gust !== null) phrase += ` gusting ${wind.gust} KT`;
  return phrase;
}

function windCode(wind) {
  if (wind.calm) return '00000KT';
  const direction = wind.variable ? 'VRB' : pad(wind.direction, 3);
  return direction + pad(wind.speed, 2) + (wind.gust === null ? '' : 'G' + pad(wind.gust, 2)) + 'KT';
}

function mileNumber(visibility) {
  if (!visibility.fractional) return String(visibility.whole);
  const fractionPart = `${visibility.numerator}/${visibility.denominator}`;
  return visibility.whole === 0 ? fractionPart : `${visibility.whole} ${fractionPart}`;
}

function visibilityPhrase(visibility) {
  if (visibility.kind === 'cavok') return '10 km or more (CAVOK)';
  if (visibility.kind === 'meter') return visibility.qualifier === 'P' ? '10 km or more' : `${visibility.meters} m`;
  const qualifier = {M: 'less than ', P: 'more than ', '': ''}[visibility.qualifier];
  return qualifier + mileNumber(visibility) + ' SM';
}

function visibilityCode(visibility) {
  if (visibility.kind === 'cavok') return 'CAVOK';
  if (visibility.kind === 'meter') return visibility.code;
  return visibility.qualifier + mileNumber(visibility) + 'SM';
}

function weatherPhrase(weather) {
  if (weather.nsw) return 'no significant weather';
  const parts = [];
  if (weather.intensity) parts.push(groups.INTENSITIES[weather.intensity]);
  if (weather.descriptor !== null) parts.push(groups.DESCRIPTORS[weather.descriptor]);
  if (weather.phenomena.length > 0) parts.push(weather.phenomena.map(code => groups.PHENOMENA[code]).join(' and '));
  return parts.join(' ');
}

function cloudPhrase(cloud) {
  if (Object.hasOwn(groups.CLEAR, cloud.amount)) return groups.CLEAR[cloud.amount];
  if (cloud.amount === 'VV') return `vertical visibility ${cloud.height} ft`;
  let phrase = `${groups.AMOUNTS[cloud.amount]} at ${cloud.height} ft`;
  if (cloud.suffix) phrase += cloud.suffix === 'CB' ? ' cumulonimbus' : ' towering cumulus';
  return phrase;
}

function cloudCode(cloud) {
  if (Object.hasOwn(groups.CLEAR, cloud.amount)) return cloud.amount;
  return cloud.amount + pad(floorDiv(cloud.height, 100), 3) + cloud.suffix;
}

function stateSummary(state) {
  const parts = [];
  if (state.wind !== null) parts.push('wind ' + windPhrase(state.wind));
  if (state.visibility !== null) parts.push('visibility ' + visibilityPhrase(state.visibility));
  if (state.weather !== null && state.weather.length > 0) parts.push('weather ' + state.weather.map(weatherPhrase).join(', '));
  if (state.cloud !== null && state.cloud.length > 0) parts.push('cloud ' + state.cloud.map(cloudPhrase).join(', '));
  return parts.length > 0 ? parts.join('; ') : 'no conditions';
}

function stateTokens(state) {
  const tokens = [];
  if (state.wind !== null) tokens.push(windCode(state.wind));
  if (state.visibility !== null) tokens.push(visibilityCode(state.visibility));
  for (const weather of state.weather ?? []) if (!weather.nsw) tokens.push(weather.raw);
  for (const cloud of state.cloud ?? []) tokens.push(cloudCode(cloud));
  tokens.push(state.category);
  return tokens.join(' ');
}

function decimalTenth(value) {
  const absolute = Math.abs(value);
  return (value < 0 ? '-' : '') + floorDiv(absolute, 10) + '.' + absolute % 10;
}

function pressurePhrase(pressure) {
  const inches = `${floorDiv(pressure.inHg, 100)}.${pad(pressure.inHg % 100, 2)} inHg`;
  const hectopascals = `${pressure.hPa} hPa`;
  return pressure.unit === 'A' ? `${inches} (${hectopascals})` : `${hectopascals} (${inches})`;
}

function rvrPhrase(rvr) {
  const reading = value => ({M: 'less than ', P: 'more than ', '': ''}[value.qualifier] + value.value);
  let phrase = `runway ${rvr.runway} `;
  phrase += rvr.second === null ? reading(rvr.first) : `between ${reading(rvr.first)} and ${reading(rvr.second)}`;
  phrase += ' ' + rvr.unit;
  if (rvr.trend !== null) phrase += {U: ', rising', D: ', falling', N: ', no change'}[rvr.trend];
  return phrase;
}

function componentPhrase(component) {
  let phrase = component.head < 0 ? `tailwind ${-component.head} KT` : `headwind ${component.head} KT`;
  if (component.cross === 0) phrase += ', crosswind 0 KT';
  else phrase += `, crosswind ${Math.abs(component.cross)} KT from ${component.cross > 0 ? 'right' : 'left'}`;
  return phrase;
}

function observationLines(report, calendar) {
  const main = report.main;
  const lines = [`time: ${calendar.stamp(report.time)}`];
  if (main.modifier !== null) lines.push(`modifier: ${main.modifier === 'AUTO' ? 'automated' : 'corrected'}`);
  let wind = main.wind === null ? 'not reported' : windPhrase(main.wind);
  if (main.variation !== null) wind += `, varying between ${pad(main.variation[0], 3)} and ${pad(main.variation[1], 3)} degrees`;
  lines.push('wind: ' + wind);
  lines.push('visibility: ' + (main.visibility === null ? 'not reported' : visibilityPhrase(main.visibility)));
  for (const rvr of main.rvr) lines.push('runway visual range: ' + rvrPhrase(rvr));
  for (const weather of main.weather ?? []) lines.push('weather: ' + weatherPhrase(weather));
  if (main.visibility?.kind === 'cavok') lines.push('cloud: no significant cloud');
  else if (main.cloud === null) lines.push('cloud: not reported');
  else for (const cloud of main.cloud) lines.push('cloud: ' + cloudPhrase(cloud));
  if (main.temperature === null) lines.push('temperature: not reported');
  else {
    const {temperature, dewPoint} = main.temperature;
    lines.push(`temperature: ${temperature} C, dew point ${dewPoint} C, spread ${temperature - dewPoint} C`);
  }
  lines.push('altimeter: ' + (main.pressure === null ? 'not reported' : pressurePhrase(main.pressure)));
  if (main.noTrend !== null) lines.push('trend: no significant change');
  for (const trend of report.trends) {
    let phrase = trend.kind === 'BECMG' ? 'becoming' : 'temporarily';
    for (const time of trend.times) {
      phrase += ` ${{FM: 'from', TL: 'until', AT: 'at'}[time.kind]} ${pad(time.hour, 2)}:${pad(time.minute, 2)}Z`;
    }
    lines.push(`trend: ${phrase}: ${stateSummary(trend.state)}`);
  }
  for (const pressure of report.remarks.pressures) lines.push(`sea level pressure: ${decimalTenth(pressure)} hPa`);
  for (const temperature of report.remarks.temperatures) {
    lines.push(`precise temperature: ${decimalTenth(temperature.temperature)} C, dew point ${decimalTenth(temperature.dewPoint)} C`);
  }
  lines.push('ceiling: ' + (main.ceiling === null ? 'none' : `${main.ceiling} ft`));
  lines.push('flight category: ' + main.category);
  lines.push('pressure altitude: ' + (report.pressureAltitude === null ? 'not available' : `${report.pressureAltitude} ft`));
  lines.push('density altitude: ' + (report.densityAltitude === null ? 'not available' : `${report.densityAltitude} ft`));
  if (report.runwayWinds === null) lines.push('runway wind: not computed');
  else {
    for (const runway of report.runwayWinds.runways) {
      let phrase = componentPhrase(runway.mean);
      if (runway.gust !== null) phrase += '; gusts ' + componentPhrase(runway.gust);
      lines.push(`runway ${runway.name}: ${phrase}`);
    }
    const usable = report.runwayWinds.runways.filter(runway => runway.usable).map(runway => runway.name);
    lines.push('usable runways: ' + (usable.length > 0 ? usable.join(' ') : 'none'));
    lines.push('preferred runway: ' + (report.runwayWinds.preferred?.name ?? 'none'));
  }
  if (report.kind === 'SPECI') lines.push('speci check: ' + report.speciReasons.join(', '));
  return lines;
}

function forecastLines(report, calendar) {
  const lines = ['issued: ' + calendar.stamp(report.time)];
  if (report.modifier !== null) lines.push(`modifier: ${report.modifier === 'AMD' ? 'amended' : 'corrected'}`);
  lines.push(`valid: ${calendar.stamp(report.start)} to ${calendar.stamp(report.end)}`);
  lines.push('base: ' + stateSummary(report.base));
  for (const change of report.changes) {
    const period = change.kind === 'FM' ? calendar.stamp(change.time)
      : `${calendar.stamp(change.start)} to ${calendar.stamp(change.end)}`;
    lines.push(`${change.kind} ${period}: ${stateSummary(change.state)}`);
  }
  return lines;
}

function decodedBlock(report, calendar) {
  const header = `REPORT ${report.number}: ${report.kind} ${report.station.code} (${report.station.name})`;
  const lines = report.kind === 'TAF' ? forecastLines(report, calendar) : observationLines(report, calendar);
  return [header, ...lines.map(line => '  ' + line)];
}

function categoryCounts(states) {
  const counts = Object.fromEntries(CATEGORIES.map(category => [category, 0]));
  for (const state of states) counts[state.category] += 1;
  return CATEGORIES.map(category => `${category} ${counts[category]}`).join(', ');
}

function timelineBlock(report, calendar) {
  const lines = [`TAF ${report.station.code} issued ${calendar.stamp(report.time)} `
    + `valid ${calendar.stamp(report.start)} to ${calendar.stamp(report.end)}`];
  for (const [time, hour] of report.timeline) {
    let line = `${calendar.stamp(time)} ${stateTokens(hour.prevailing)}`;
    for (const temporary of hour.temporary) line += ` | ${temporary.kind} ${stateTokens(temporary.state)}`;
    lines.push(line);
  }
  lines.push('summary: ' + categoryCounts([...report.timeline.values()].map(hour => hour.prevailing)));
  return lines;
}

function categoriesLine(report, calendar) {
  const main = report.main;
  const visibility = main.visibility === null ? 'NONE' : main.visibility.qualifier + meterValue(main.visibility);
  return [report.station.code, calendar.stamp(report.time), main.ceiling ?? 'NONE', visibility, main.category].join(',');
}

function extreme(observations, valueOf, compare) {
  let selected = null;
  let selectedValue = null;
  for (const observation of observations) {
    const value = valueOf(observation);
    if (value !== null && (selected === null || compare(value, selectedValue) < 0)) {
      selected = observation;
      selectedValue = value;
    }
  }
  return selected === null ? null : {observation: selected, value: selectedValue};
}

function extremeLines(observations, calendar) {
  const temperature = report => report.main.temperature?.temperature ?? null;
  const strength = wind => wind.gust ?? wind.speed;
  const extremes = [
    ['lowest temperature', extreme(observations, temperature, (a, b) => a - b), value => `${value} C`],
    ['highest temperature', extreme(observations, temperature, (a, b) => b - a), value => `${value} C`],
    ['strongest wind', extreme(observations, report => report.main.wind, (a, b) => strength(b) - strength(a)), windPhrase],
    ['lowest ceiling', extreme(observations, report => report.main.ceiling, (a, b) => a - b), value => `${value} ft`],
    ['lowest visibility', extreme(observations, report => report.main.visibility, compareVisibility), visibilityPhrase],
  ];
  return extremes.map(([label, selected, phrase]) => label + ': ' + (selected === null ? 'not available'
    : `${phrase(selected.value)} at ${calendar.stamp(selected.observation.time)}`));
}

function contingencyLines(result) {
  const row = (label, values) => label.padEnd(8, ' ') + values.map(value => String(value).padStart(6, ' ')).join('');
  const lines = [row('forecast', [...CATEGORIES, 'total'])];
  for (let index = 0; index < 4; index += 1) lines.push(row(CATEGORIES[index], [...result.table[index], result.rows[index]]));
  lines.push(row('total', [...result.columns, result.total]));
  return lines;
}

function amendmentLines(result, calendar) {
  const lines = [];
  for (const choice of result.choices) {
    const observed = choice.observation.main;
    const forecast = choice.forecast.prevailing;
    const reasons = [];
    if (!choice.temporaryHit) reasons.push(`category ${observed.category}, forecast ${forecast.category}`);
    if (windChanges(forecast.wind, observed.wind, 60).length > 0) {
      reasons.push(`wind ${windCode(observed.wind)}, forecast ${windCode(forecast.wind)}`);
    }
    if (reasons.length > 0) lines.push(`amendment ${calendar.stamp(choice.observation.time)}: ${reasons.join('; ')}`);
  }
  return lines;
}

function verificationBlock(station, observations, forecasts, calendar) {
  const result = verification.analyze(observations, forecasts);
  const metars = observations.filter(report => report.kind === 'METAR').length;
  const specis = observations.length - metars;
  const lines = [`station ${station.code} (${station.name})`, `reports: METAR ${metars}, SPECI ${specis}`,
    'observed categories: ' + categoryCounts(observations.map(report => report.main))];
  lines.push(...extremeLines(observations, calendar));
  lines.push(`verified: ${result.total}`, `no forecast: ${result.noForecast}`);
  lines.push(...contingencyLines(result));
  lines.push('hit rate: ' + fraction(...result.hitRate));
  lines.push('hit rate with temporary groups: ' + fraction(...result.temporaryHitRate));
  lines.push('heidke skill score: ' + fraction(...result.skill));
  for (let index = 0; index < 4; index += 1) {
    const metric = result.metrics[index];
    lines.push(`${CATEGORIES[index]}: pod ${fraction(...metric.pod)}, far ${fraction(...metric.far)}`);
  }
  for (let index = 0; index < 5; index += 1) {
    const bucket = result.buckets[index];
    lines.push(`hours ${index * 6}-${index * 6 + 5}: ${fraction(bucket.hits, bucket.pairs)}`);
  }
  lines.push(...amendmentLines(result, calendar));
  return lines;
}

function blockText(blocks) {
  return blocks.length === 0 ? '' : blocks.map(block => block.join('\n')).join('\n\n') + '\n';
}

function lineText(lines) {
  return lines.length === 0 ? '' : lines.join('\n') + '\n';
}

function main() {
  const {stations, params, reports: rawReports} = readInputs();
  const calendar = new Calendar(params.year, params.month);
  const reports = [];
  const observations = [];
  const forecasts = [];
  const errors = [];
  const previous = new Map();
  for (const raw of rawReports) {
    const error = errorRecorder(errors, raw.number);
    const report = parseHeader(raw, stations, calendar, error);
    if (report === null) continue;
    const body = joinGroups(raw.words, report.bodyStart);
    if (report.kind === 'TAF') {
      decodeForecast(report, body, calendar, error);
      forecasts.push(report);
    } else {
      decodeObservation(report, body, params, error);
      if (report.kind === 'SPECI') report.speciReasons = speciCheck(previous.get(report.station.code), report);
      previous.set(report.station.code, report);
      observations.push(report);
    }
    reports.push(report);
  }
  const verificationBlocks = params.verify.map(code => verificationBlock(stations.get(code),
    observations.filter(report => report.station.code === code),
    forecasts.filter(report => report.station.code === code), calendar));
  errors.sort((first, second) => first.report - second.report || first.position - second.position);
  const outputs = new Map([
    ['decoded.txt', blockText(reports.map(report => decodedBlock(report, calendar)))],
    ['categories.csv', lineText(['station,time,ceiling,visibility,category',
      ...observations.map(report => categoriesLine(report, calendar))])],
    ['taf_timeline.txt', blockText(forecasts.map(report => timelineBlock(report, calendar)))],
    ['verification.txt', blockText(verificationBlocks)],
    ['errors.txt', lineText(errors.map(error => `report ${error.report} word ${error.position}: ${error.content}`))],
  ]);
  fs.mkdirSync('output', {recursive: true});
  for (const [name, text] of outputs) fs.writeFileSync(path.join('output', name), text, 'ascii');
}

if (require.main === module) main();
