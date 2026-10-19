'use strict';

const {knots, inHg, hPa} = require('./units');

const DESCRIPTORS = {MI: 'shallow', BC: 'patches', PR: 'partial', DR: 'low drifting',
  BL: 'blowing', SH: 'showers', TS: 'thunderstorm', FZ: 'freezing'};
const PHENOMENA = {DZ: 'drizzle', RA: 'rain', SN: 'snow', SG: 'snow grains', IC: 'ice crystals',
  PL: 'ice pellets', GR: 'hail', GS: 'small hail', UP: 'unknown precipitation', BR: 'mist',
  FG: 'fog', FU: 'smoke', VA: 'volcanic ash', DU: 'dust', SA: 'sand', HZ: 'haze', PY: 'spray',
  PO: 'dust whirls', SQ: 'squalls', FC: 'funnel cloud', SS: 'sandstorm', DS: 'duststorm'};
const PRECIPITATION = new Set(['DZ', 'RA', 'SN', 'SG', 'IC', 'PL', 'GR', 'GS', 'UP']);
const AMOUNTS = {FEW: 'few', SCT: 'scattered', BKN: 'broken', OVC: 'overcast'};
const CLEAR = {SKC: 'sky clear', CLR: 'clear below 12000 ft', NSC: 'no significant cloud'};
const INTENSITIES = {'-': 'light', '+': 'heavy', VC: 'nearby'};
const WEATHER_CODES = new Set([...Object.keys(DESCRIPTORS), ...Object.keys(PHENOMENA)]);

function section(context) {
  return {context, modifier: null, wind: null, variation: null, visibility: null,
    rvr: [], weather: null, cloud: null, temperature: null, pressure: null, noTrend: null};
}

function visibilityFormat(text) {
  if (text === 'CAVOK') return {kind: 'cavok', meters: 10000, qualifier: 'P'};
  if (/^\d{4}$/.test(text)) {
    const value = Number(text);
    return {kind: 'meter', meters: value === 9999 ? 10000 : value,
      qualifier: value === 9999 ? 'P' : '', code: text};
  }
  let match = /^(\d) (\d)\/(\d{1,2})SM$/.exec(text);
  if (match) return {kind: 'mile', whole: Number(match[1]), numerator: Number(match[2]),
    denominator: Number(match[3]), qualifier: '', mixed: true, fractional: true};
  match = /^([MP]?)(?:(\d{1,2})|(\d)\/(\d{1,2}))SM$/.exec(text);
  if (!match) return null;
  return {kind: 'mile', qualifier: match[1], whole: Number(match[2] ?? 0),
    numerator: Number(match[3] ?? 0), denominator: Number(match[4] ?? 1),
    mixed: false, fractional: match[3] !== undefined};
}

function weatherFormat(text) {
  if (text === 'NSW') return {raw: text, nsw: true, intensity: '', codes: []};
  let intensity = '';
  let body = text;
  if (body.startsWith('VC')) {
    intensity = 'VC';
    body = body.slice(2);
  } else if (body.startsWith('-') || body.startsWith('+')) {
    intensity = body[0];
    body = body.slice(1);
  }
  if (body.length === 0 || body.length % 2 !== 0) return null;
  const codes = [];
  for (let index = 0; index < body.length; index += 2) {
    const code = body.slice(index, index + 2);
    if (!WEATHER_CODES.has(code)) return null;
    codes.push(code);
  }
  const descriptor = Object.hasOwn(DESCRIPTORS, codes[0]) ? codes[0] : null;
  return {raw: text, nsw: false, intensity, codes, descriptor,
    phenomena: descriptor === null ? codes : codes.slice(1)};
}

function format(kind, text) {
  let match;
  switch (kind) {
    case 'modifier':
      return text === 'AUTO' || text === 'COR' ? text : null;
    case 'wind':
      match = /^(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)$/.exec(text);
      return match ? {direction: match[1] === 'VRB' ? null : Number(match[1]),
        variable: match[1] === 'VRB', speed: Number(match[2]),
        gust: match[3] === undefined ? null : Number(match[3]), unit: match[4], calm: match[1] === '000'} : null;
    case 'variation':
      match = /^(\d{3})V(\d{3})$/.exec(text);
      return match ? match.slice(1).map(Number) : null;
    case 'visibility':
      return visibilityFormat(text);
    case 'rvr':
      match = /^R(\d{2}[LCR]?)\/([MP]?)(\d{4})(?:V([MP]?)(\d{4}))?(FT)?([UDN])?$/.exec(text);
      return match ? {runway: match[1], first: {qualifier: match[2], value: Number(match[3])},
        second: match[5] === undefined ? null : {qualifier: match[4], value: Number(match[5])},
        unit: match[6] ? 'ft' : 'm', trend: match[7] ?? null} : null;
    case 'weather':
      return weatherFormat(text);
    case 'cloud':
      if (Object.hasOwn(CLEAR, text)) return {raw: text, amount: text, height: null, suffix: ''};
      match = /^(FEW|SCT|BKN|OVC)(\d{3})(CB|TCU)?$/.exec(text);
      if (match) return {raw: text, amount: match[1], height: Number(match[2]) * 100, suffix: match[3] ?? ''};
      match = /^VV(\d{3})$/.exec(text);
      return match ? {raw: text, amount: 'VV', height: Number(match[1]) * 100, suffix: ''} : null;
    case 'temperature':
      match = /^(M?)(\d{2})\/(M?)(\d{2})$/.exec(text);
      return match ? {temperature: Number(match[2]) * (match[1] ? -1 : 1),
        dewPoint: Number(match[4]) * (match[3] ? -1 : 1)} : null;
    case 'pressure':
      match = /^([AQ])(\d{4})$/.exec(text);
      return match ? {unit: match[1], value: Number(match[2])} : null;
    case 'noTrend':
      return text === 'NOSIG' ? true : null;
    default:
      throw new Error(`Unknown group kind: ${kind}`);
  }
}

function valid(kind, value, current, station) {
  if (kind === 'wind') {
    if (value.variable) {
      if (value.speed < 1) return false;
    } else {
      if (value.direction > 360 || value.direction % 10 !== 0) return false;
      if ((value.direction === 0) !== (value.speed === 0)) return false;
    }
    return value.gust === null || !value.calm && value.gust > value.speed;
  }
  if (kind === 'variation') {
    return value.every(direction => direction >= 10 && direction <= 360 && direction % 10 === 0)
      && value[0] !== value[1] && current.wind !== null && !current.wind.variable && !current.wind.calm;
  }
  if (kind === 'visibility' && value.kind === 'mile') {
    if (!value.fractional) return value.whole >= 1;
    return [2, 4, 8, 16].includes(value.denominator) && value.numerator >= 1
      && value.numerator < value.denominator && (!value.mixed || value.whole >= 1);
  }
  if (kind === 'rvr') {
    return station.runways.some(runway => runway.name === value.runway)
      && (value.second === null || value.first.value < value.second.value);
  }
  if (kind === 'weather') {
    const accepted = current.weather ?? [];
    if (accepted.length >= 3 || accepted.some(weather => weather.nsw)) return false;
    if (value.nsw) return accepted.length === 0 && ['trend', 'change'].includes(current.context);
    if (value.phenomena.some(code => !Object.hasOwn(PHENOMENA, code))) return false;
    if (new Set(value.phenomena).size !== value.phenomena.length) return false;
    if (value.phenomena.length === 0 && !['TS', 'SH'].includes(value.descriptor)) return false;
    if (['-', '+'].includes(value.intensity) && !value.phenomena.some(code => PRECIPITATION.has(code))) return false;
    return value.phenomena.length < 2 || value.phenomena.every(code => PRECIPITATION.has(code));
  }
  if (kind === 'cloud' && current.cloud !== null && current.cloud.length > 0) {
    const previous = current.cloud.at(-1);
    return Object.hasOwn(AMOUNTS, value.amount) && Object.hasOwn(AMOUNTS, previous.amount)
      && value.height > previous.height;
  }
  if (kind === 'temperature') return value.dewPoint <= value.temperature;
  if (kind === 'pressure') {
    return value.unit === 'A' ? value.value >= 2500 && value.value <= 3150
      : value.value >= 850 && value.value <= 1070;
  }
  return true;
}

function accept(current, kind, value) {
  if (kind === 'wind' && value.unit === 'MPS') {
    value.speed = knots(value.speed);
    if (value.gust !== null) value.gust = knots(value.gust);
  }
  if (kind === 'pressure') {
    value.inHg = value.unit === 'A' ? value.value : inHg(value.value);
    value.hPa = value.unit === 'Q' ? value.value : hPa(value.value);
  }
  if (['rvr', 'weather', 'cloud'].includes(kind)) {
    if (current[kind] === null) current[kind] = [];
    current[kind].push(value);
  } else {
    current[kind] = value;
  }
  if (kind === 'visibility' && value.kind === 'cavok') {
    current.weather = [];
    current.cloud = [];
  }
}

module.exports = {DESCRIPTORS, PHENOMENA, PRECIPITATION, AMOUNTS, CLEAR, INTENSITIES,
  section, format, valid, accept};
