'use strict';

const {CONSTANTS} = require('./dataset');

function subgroupStatistics(samples, size) {
  const groups = [];
  for (let start = 0; start < samples.length; start += size) {
    const members = samples.slice(start, start + size);
    let total = 0;
    let squares = 0;
    let minimum = members[0].value;
    let maximum = minimum;
    for (const sample of members) {
      total += sample.value;
      squares += sample.value * sample.value;
      minimum = Math.min(minimum, sample.value);
      maximum = Math.max(maximum, sample.value);
    }
    groups.push({
      number: members[0].subgroup, samples: members, total, squares,
      mean: total / size, range: maximum - minimum,
      sd: Math.sqrt((size * squares - total * total) / (size * (size - 1))),
    });
  }
  return groups;
}

function movingRanges(sequence) {
  const ranges = [];
  for (let index = 1; index < sequence.length; index++) {
    ranges.push({number: sequence[index].number, value: Math.abs(sequence[index].value - sequence[index - 1].value)});
  }
  return ranges;
}

function limits(lower, center, upper) {
  return {lcl: lower, cl: center, ucl: upper};
}

function familyLimits(family, points, groups, samples, size, constants) {
  if (family === 'I_MR') {
    const individual = points.map(number => ({number, value: samples[number - 1].value}));
    const ranges = movingRanges(individual);
    let total = 0;
    let totalRanges = 0;
    for (const point of individual) total += point.value;
    for (const point of ranges) totalRanges += point.value;
    const center = total / individual.length;
    const meanRange = totalRanges / ranges.length;
    const two = CONSTANTS.get(2);
    const width = 3 * meanRange / two.d2;
    return {
      limits: [limits(center - width, center, center + width),
        limits(two.D3 * meanRange, meanRange, two.D4 * meanRange)],
      sequences: [individual, ranges],
    };
  }
  const selected = points.map(number => groups[number - 1]);
  let total = 0;
  let spreadTotal = 0;
  for (const group of selected) {
    total += group.total;
    spreadTotal += family === 'XBAR_R' ? group.range : group.sd;
  }
  const center = total / (selected.length * size);
  const spread = spreadTotal / selected.length;
  const width = (family === 'XBAR_R' ? constants.A2 : constants.A3) * spread;
  const lower = family === 'XBAR_R' ? constants.D3 : constants.B3;
  const upper = family === 'XBAR_R' ? constants.D4 : constants.B4;
  return {
    limits: [limits(center - width, center, center + width), limits(lower * spread, spread, upper * spread)],
    sequences: [selected.map(group => ({number: group.number, value: group.mean})),
      selected.map(group => ({number: group.number, value: family === 'XBAR_R' ? group.range : group.sd}))],
  };
}

function outside(value, control) {
  return value > control.ucl || value < control.lcl;
}

module.exports = {subgroupStatistics, movingRanges, familyLimits, outside};
