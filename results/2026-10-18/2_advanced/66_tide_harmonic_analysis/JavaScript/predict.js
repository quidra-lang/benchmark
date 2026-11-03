'use strict';

const {angle} = require('./harmonic_fit');

function level(model, time) {
  let value = model.mean;
  for (const constituent of model.constituents) {
    const theta = angle(constituent.speed, time);
    value += constituent.a * Math.cos(theta) + constituent.b * Math.sin(theta);
  }
  return value;
}

function gridExtrema(model, start, hours, spacing) {
  const count = hours * 60 / spacing;
  const values = [];
  for (let index = 0; index <= count; index++) {
    values.push(level(model, (60 * start + index * spacing) / 60));
  }
  const extrema = [];
  for (let index = 1; index < count; index++) {
    const previous = values[index - 1];
    const current = values[index];
    const next = values[index + 1];
    let kind;
    if (previous < current && current > next) kind = 'high';
    else if (previous > current && current < next) kind = 'low';
    else continue;
    const delta = (previous - next) / (2 * (previous - 2 * current + next));
    const refinedMinute = 60 * start + index * spacing + delta * spacing;
    const height = current - (previous - next) * delta / 4;
    extrema.push({kind, refinedMinute, height});
  }
  return extrema;
}

module.exports = {level, gridExtrema};
