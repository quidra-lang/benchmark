import type { Control, Point } from './variable_charts.ts';
export type Direction = 'UP' | 'DOWN' | 'NONE';
export interface RuleSignal {
  rule: number | 'UPPER' | 'LOWER';
  start: number;
  end: number;
  value: number;
  direction: Direction;
}
export function zoneBoundaries(c: Control) {
  const a = (c.ucl - c.cl) / 3;
  const b = (c.cl - c.lcl) / 3;
  return { u1: c.cl + a, u2: c.cl + 2 * a, l1: c.cl - b, l2: c.cl - 2 * b };
}
export function runRules(sequence: Point[], c: Control, rules: number[]): RuleSignal[] {
  const lengths = [0, 1, 3, 5, 8, 6, 14, 15, 8];
  const zones = zoneBoundaries(c);
  const signals: RuleSignal[] = [];
  for (let i = 0; i < sequence.length; i++) {
    for (const rule of rules) {
      const length = lengths[rule];
      if (i + 1 < length) continue;
      const window = sequence.slice(i - length + 1, i + 1);
      const values = window.map((p) => p.value);
      const last = sequence[i].value;
      let direction: Direction | undefined;
      if (rule === 1 && outside(last, c)) direction = last > c.cl ? 'UP' : 'DOWN';
      if (rule === 2 || rule === 3) {
        const upper = rule === 2 ? zones.u2 : zones.u1;
        const lower = rule === 2 ? zones.l2 : zones.l1;
        const required = rule === 2 ? 2 : 4;
        if (last > upper && values.filter((v) => v > upper).length >= required) direction = 'UP';
        else if (last < lower && values.filter((v) => v < lower).length >= required) {
          direction = 'DOWN';
        }
      }
      if (rule === 4) {
        if (values.every((v) => v > c.cl)) direction = 'UP';
        else if (values.every((v) => v < c.cl)) direction = 'DOWN';
      }
      if (rule === 5) {
        if (values.every((v, j) => j === 0 || v > values[j - 1])) direction = 'UP';
        else if (values.every((v, j) => j === 0 || v < values[j - 1])) direction = 'DOWN';
      }
      if (rule === 6) {
        let previous = 0;
        let alternating = true;
        for (let j = 1; j < values.length; j++) {
          const sign = Math.sign(values[j] - values[j - 1]);
          if (sign === 0 || sign === previous) alternating = false;
          previous = sign;
        }
        if (alternating) direction = 'NONE';
      }
      if (rule === 7 && values.every((v) => zones.l1 < v && v < zones.u1)) direction = 'NONE';
      if (
        rule === 8 &&
        values.every((v) => v > zones.u1 || v < zones.l1) &&
        values.some((v) => v > zones.u1) &&
        values.some((v) => v < zones.l1)
      ) {
        direction = 'NONE';
      }
      if (direction) {
        signals.push({
          rule,
          start: window[0].number,
          end: sequence[i].number,
          value: last,
          direction,
        });
      }
    }
  }
  return signals;
}
function outside(v: number, c: Control) {
  return v > c.ucl || v < c.lcl;
}
export function zoneName(v: number, c: Control): string {
  const z = zoneBoundaries(c);
  return v > c.ucl
    ? 'OUT+'
    : v < c.lcl
      ? 'OUT-'
      : v > z.u2
        ? 'A+'
        : v > z.u1
          ? 'B+'
          : v > c.cl
            ? 'C+'
            : v < z.l2
              ? 'A-'
              : v < z.l1
                ? 'B-'
                : v < c.cl
                  ? 'C-'
                  : 'C0';
}
