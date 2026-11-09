'use strict';

const { Z } = require('./numerics');

function riskSets(subjects) {
  const counts = new Map();
  for (const subject of subjects) {
    if (!counts.has(subject.time)) counts.set(subject.time, { events: 0, censored: 0 });
    const count = counts.get(subject.time);
    if (subject.event === 1) count.events++;
    else count.censored++;
  }
  const times = [...counts.keys()].sort((a, b) => a - b);
  const rows = [];
  let atRisk = subjects.length;
  for (const time of times) {
    const { events, censored } = counts.get(time);
    rows.push({ time, atRisk, events, censored });
    atRisk -= events + censored;
  }
  return rows;
}

function kaplanMeier(subjects) {
  const events = riskSets(subjects).filter(row => row.events > 0);
  const rows = [];
  let survival = 1;
  let greenwood = 0;
  let cumHazard = 0;
  let hazardVariance = 0;
  for (let i = 0; i < events.length; i++) {
    const { time, atRisk: n, events: d } = events[i];
    survival *= (n - d) / n;
    if (n === d || greenwood === null) greenwood = null;
    else greenwood += d / (n * (n - d));
    let stdErr = null;
    let lower = null;
    let upper = null;
    if (survival !== 0) {
      const root = Math.sqrt(greenwood);
      stdErr = survival * root;
      const logarithm = Math.log(survival);
      const omega = Z * root / (-logarithm);
      lower = Math.exp(logarithm * Math.exp(omega));
      upper = Math.exp(logarithm * Math.exp(-omega));
    }
    cumHazard += d / n;
    hazardVariance += d / (n * n);
    let censored = 0;
    for (const subject of subjects) {
      if (subject.event === 0 && subject.time >= time &&
          (i + 1 === events.length || subject.time < events[i + 1].time)) censored++;
    }
    rows.push({
      time, atRisk: n, events: d, censored, survival, stdErr, lower, upper,
      cumHazard, hazardSe: Math.sqrt(hazardVariance)
    });
  }
  return rows;
}

function rowAt(rows, time) {
  let result = {
    survival: 1, stdErr: 0, lower: null, upper: null, cumHazard: 0, hazardSe: 0
  };
  for (const row of rows) {
    if (row.time > time) break;
    result = row;
  }
  return result;
}

function lifeTable(subjects, width, count) {
  const rows = [];
  let survival = 1;
  let greenwood = 0;
  for (let i = 0; i < count; i++) {
    const start = i * width;
    const end = (i + 1) * width;
    let atRisk = 0;
    let events = 0;
    let withdrawn = 0;
    for (const subject of subjects) {
      if (subject.time >= start) atRisk++;
      if (subject.time >= start && subject.time < end) {
        if (subject.event === 1) events++;
        else withdrawn++;
      }
    }
    const exposedTwice = 2 * atRisk - withdrawn;
    const q = (2 * events) / exposedTwice;
    survival *= (exposedTwice - 2 * events) / exposedTwice;
    greenwood += (4 * events) / (exposedTwice * (exposedTwice - 2 * events));
    const stdErr = survival * Math.sqrt(greenwood);
    const hazard = (2000 * events) / (width * (exposedTwice - events));
    rows.push({
      start, end, atRisk, events, withdrawn, exposed: exposedTwice / 2,
      q, survival, stdErr, hazard
    });
  }
  return rows;
}

module.exports = { riskSets, kaplanMeier, rowAt, lifeTable };
