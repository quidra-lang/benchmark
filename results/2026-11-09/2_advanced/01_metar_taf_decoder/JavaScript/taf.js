'use strict';

const {format} = require('./groups');

const SLOTS = [['wind', false], ['visibility', false], ['weather', true], ['cloud', true]]
  .map(([kind, repeat]) => ({kind, repeat, test: text => format(kind, text)}));
const ELEMENTS = ['wind', 'visibility', 'weather', 'cloud'];
const TEMPORARY = new Set(['TEMPO', 'PROB30', 'PROB40', 'PROB30 TEMPO', 'PROB40 TEMPO']);

function isIndicator(group) {
  return ['BECMG', 'TEMPO', 'PROB30', 'PROB40'].includes(group.text) || /^FM\d{6}$/.test(group.text);
}

function splitBody(body, report, calendar, error) {
  let index = body.findIndex(isIndicator);
  if (index < 0) return {base: body, changes: []};
  const base = body.slice(0, index);
  const changes = [];
  while (index < body.length) {
    const indicator = body[index];
    let kind = indicator.text.startsWith('FM') ? 'FM' : indicator.text;
    index += 1;
    if ((kind === 'PROB30' || kind === 'PROB40') && body[index]?.text === 'TEMPO') {
      kind += ' TEMPO';
      index += 1;
    }
    let end = index;
    while (end < body.length && !isIndicator(body[end])) end += 1;
    if (kind === 'FM') {
      const time = calendar.changeTime(indicator.text, report.issueDay);
      if (time === null || time < report.start || time >= report.end) {
        error(indicator.position, 'invalid period', indicator.text);
      } else {
        changes.push({kind, time, groups: body.slice(index, end)});
      }
    } else if (index === end || !/^\d{4}\/\d{4}$/.test(body[index].text)) {
      error(indicator.position, 'missing period', kind);
    } else {
      const period = calendar.period(body[index].text, report.issueDay);
      if (period === null || period.start < report.start || period.end > report.end) {
        error(body[index].position, 'invalid period', body[index].text);
      } else {
        changes.push({kind, ...period, groups: body.slice(index + 1, end)});
      }
    }
    index = end;
  }
  return {base, changes};
}

function stateOf(section) {
  return Object.fromEntries(ELEMENTS.map(name => [name, section[name]]));
}

function overlay(state, change) {
  const result = {...state};
  for (const name of ELEMENTS) if (change[name] !== null) result[name] = change[name];
  return result;
}

function expand(report) {
  const timeline = new Map();
  for (let hour = report.start; hour < report.end; hour += 60) {
    let prevailing = stateOf(report.base);
    for (const change of report.changes) {
      if (change.kind === 'FM' && change.time <= hour) prevailing = stateOf(change.state);
      if (change.kind === 'BECMG' && change.end <= hour) prevailing = overlay(prevailing, change.state);
    }
    const temporary = [];
    for (const change of report.changes) {
      if (TEMPORARY.has(change.kind) && change.start <= hour && hour < change.end) {
        temporary.push({kind: change.kind, state: overlay(prevailing, change.state)});
      }
    }
    timeline.set(hour, {prevailing, temporary});
  }
  return timeline;
}

module.exports = {SLOTS, splitBody, expand};
