'use strict';

const LENGTHS = [0, 1, 3, 5, 8, 6, 14, 15, 8];

function zoneBoundaries(control) {
  const upper = (control.ucl - control.cl) / 3;
  const lower = (control.cl - control.lcl) / 3;
  return {u1: control.cl + upper, u2: control.cl + 2 * upper,
    l1: control.cl - lower, l2: control.cl - 2 * lower};
}

function directionFor(rule, values, control, zones) {
  const last = values.at(-1);
  if (rule === 1) {
    if (last > control.ucl || last < control.lcl) return last > control.cl ? 'UP' : 'DOWN';
  } else if (rule === 2 || rule === 3) {
    const upper = rule === 2 ? zones.u2 : zones.u1;
    const lower = rule === 2 ? zones.l2 : zones.l1;
    const required = rule === 2 ? 2 : 4;
    if (last > upper && values.filter(value => value > upper).length >= required) return 'UP';
    if (last < lower && values.filter(value => value < lower).length >= required) return 'DOWN';
  } else if (rule === 4) {
    if (values.every(value => value > control.cl)) return 'UP';
    if (values.every(value => value < control.cl)) return 'DOWN';
  } else if (rule === 5) {
    if (values.every((value, index) => index === 0 || value > values[index - 1])) return 'UP';
    if (values.every((value, index) => index === 0 || value < values[index - 1])) return 'DOWN';
  } else if (rule === 6) {
    let previous = 0;
    let alternating = true;
    for (let index = 1; index < values.length; index++) {
      const sign = Math.sign(values[index] - values[index - 1]);
      if (sign === 0 || sign === previous) alternating = false;
      previous = sign;
    }
    if (alternating) return 'NONE';
  } else if (rule === 7) {
    if (values.every(value => value > zones.l1 && value < zones.u1)) return 'NONE';
  } else if (rule === 8) {
    if (values.every(value => value > zones.u1 || value < zones.l1)
        && values.some(value => value > zones.u1) && values.some(value => value < zones.l1)) return 'NONE';
  }
  return null;
}

function runRules(sequence, control, rules) {
  const signals = [];
  const zones = zoneBoundaries(control);
  for (let index = 0; index < sequence.length; index++) {
    for (const rule of rules) {
      const length = LENGTHS[rule];
      if (index + 1 < length) continue;
      const window = sequence.slice(index - length + 1, index + 1);
      const direction = directionFor(rule, window.map(point => point.value), control, zones);
      if (direction !== null) signals.push({rule, start: window[0].number,
        end: sequence[index].number, value: sequence[index].value, direction});
    }
  }
  return signals;
}

function zoneName(value, control) {
  const zones = zoneBoundaries(control);
  if (value > control.ucl) return 'OUT+';
  if (value < control.lcl) return 'OUT-';
  if (value > zones.u2) return 'A+';
  if (value > zones.u1) return 'B+';
  if (value > control.cl) return 'C+';
  if (value < zones.l2) return 'A-';
  if (value < zones.l1) return 'B-';
  if (value < control.cl) return 'C-';
  return 'C0';
}

module.exports = {zoneBoundaries, runRules, zoneName};
