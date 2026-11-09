'use strict';

const {format} = require('./groups');

const MAIN_SLOTS = [['modifier', false], ['wind', false], ['variation', false],
  ['visibility', false], ['rvr', true], ['weather', true], ['cloud', true],
  ['temperature', false], ['pressure', false], ['noTrend', false]]
  .map(([kind, repeat]) => ({kind, repeat, test: text => format(kind, text)}));

function isTrend(group) {
  return group.text === 'BECMG' || group.text === 'TEMPO';
}

function splitBody(body) {
  const remarkIndex = body.findIndex(group => group.text === 'RMK');
  const beforeRemarks = remarkIndex < 0 ? body : body.slice(0, remarkIndex);
  const remarks = remarkIndex < 0 ? [] : body.slice(remarkIndex + 1);
  const trendIndex = beforeRemarks.findIndex(isTrend);
  return {main: trendIndex < 0 ? beforeRemarks : beforeRemarks.slice(0, trendIndex),
    trends: trendIndex < 0 ? [] : beforeRemarks.slice(trendIndex), remarks};
}

function readTrends(groups, error) {
  const trends = [];
  let index = 0;
  while (index < groups.length) {
    const indicator = groups[index];
    let end = index + 1;
    while (end < groups.length && !isTrend(groups[end])) end += 1;
    let cursor = index + 1;
    const times = [];
    let invalid = false;
    while (cursor < end) {
      const match = /^(FM|TL|AT)(\d{2})(\d{2})$/.exec(groups[cursor].text);
      if (!match || times.length > 0 && !(times.length === 1 && times[0].kind === 'FM' && match[1] === 'TL')) break;
      const hour = Number(match[2]);
      const minute = Number(match[3]);
      if (hour > 23 || minute > 59) {
        error(groups[cursor].position, 'invalid period', groups[cursor].text);
        invalid = true;
        break;
      }
      times.push({kind: match[1], hour, minute});
      cursor += 1;
    }
    if (!invalid) trends.push({kind: indicator.text, times, groups: groups.slice(cursor, end)});
    index = end;
  }
  return trends;
}

function readRemarks(groups) {
  const pressures = [];
  const temperatures = [];
  for (const group of groups) {
    let match = /^SLP(\d{3})$/.exec(group.text);
    if (match) {
      const value = Number(match[1]);
      pressures.push((value >= 500 ? 9000 : 10000) + value);
      continue;
    }
    match = /^T([01])(\d{3})([01])(\d{3})$/.exec(group.text);
    if (match) temperatures.push({temperature: Number(match[2]) * (match[1] === '1' ? -1 : 1),
      dewPoint: Number(match[4]) * (match[3] === '1' ? -1 : 1)});
  }
  return {pressures, temperatures};
}

module.exports = {MAIN_SLOTS, splitBody, readTrends, readRemarks};
