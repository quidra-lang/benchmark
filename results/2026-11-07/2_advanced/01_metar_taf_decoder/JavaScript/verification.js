'use strict';

const {floorDiv} = require('./units');

const CATEGORIES = ['VFR', 'MVFR', 'IFR', 'LIFR'];

function covers(taf, observation) {
  const hour = observation.time - observation.time % 60;
  return taf.time <= observation.time && taf.start <= hour && hour < taf.end;
}

function select(tafs, observation) {
  let selected = null;
  for (const taf of tafs) {
    if (covers(taf, observation) && (selected === null || taf.time > selected.time
        || taf.time === selected.time && taf.number > selected.number)) selected = taf;
  }
  return selected;
}

function analyze(observations, tafs) {
  const table = Array.from({length: 4}, () => [0, 0, 0, 0]);
  const buckets = Array.from({length: 5}, () => ({hits: 0, pairs: 0}));
  const choices = [];
  let noForecast = 0;
  let hits = 0;
  let temporaryHits = 0;
  for (const observation of observations) {
    const hour = observation.time - observation.time % 60;
    const category = observation.main.category;
    for (const taf of tafs) {
      if (!covers(taf, observation)) continue;
      const bucket = buckets[floorDiv(floorDiv(hour - taf.start, 60), 6)];
      bucket.pairs += 1;
      if (taf.timeline.get(hour).prevailing.category === category) bucket.hits += 1;
    }
    const chosen = select(tafs, observation);
    if (chosen === null) {
      noForecast += 1;
      continue;
    }
    const forecast = chosen.timeline.get(hour);
    const forecastCategory = forecast.prevailing.category;
    const hit = forecastCategory === category;
    const temporaryHit = hit || forecast.temporary.some(change => change.state.category === category);
    table[CATEGORIES.indexOf(forecastCategory)][CATEGORIES.indexOf(category)] += 1;
    if (hit) hits += 1;
    if (temporaryHit) temporaryHits += 1;
    choices.push({observation, taf: chosen, forecast, hit, temporaryHit});
  }
  const rows = table.map(row => row.reduce((total, count) => total + count, 0));
  const columns = CATEGORIES.map((category, index) => table.reduce((total, row) => total + row[index], 0));
  const total = rows.reduce((sum, value) => sum + value, 0);
  let expected = 0;
  for (let index = 0; index < 4; index += 1) expected += rows[index] * columns[index];
  const metrics = CATEGORIES.map((category, index) => ({
    pod: [table[index][index], columns[index]],
    far: [rows[index] - table[index][index], rows[index]],
  }));
  return {table, rows, columns, total, noForecast, choices, buckets, metrics,
    hitRate: [hits, total], temporaryHitRate: [temporaryHits, total],
    skill: [total * hits - expected, total * total - expected]};
}

module.exports = {CATEGORIES, covers, select, analyze};
