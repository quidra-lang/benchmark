export interface YieldAnalytics { ytm: number; macaulay: number; modified: number; convexity: number; dv01: number }
export function bisect(value: (x: number) => number, lower: number, upper: number, target: number): number {
  for (let step = 0; step < 80; step++) {
    const middle = (lower + upper) / 2;
    if (value(middle) > target) lower = middle; else upper = middle;
  }
  return (lower + upper) / 2;
}
function presentByYield(flows: number[], frequency: number, fraction: number, yieldValue: number): number[] {
  const first = 1 + fraction * yieldValue / frequency, growth = 1 + yieldValue / frequency;
  let power = 1;
  return flows.map(amount => { const value = amount / (first * power); power *= growth; return value; });
}
export function dirty(flows: number[], frequency: number, fraction: number, outstanding: number, yieldValue: number): number {
  let total = 0;
  for (const value of presentByYield(flows, frequency, fraction, yieldValue)) total += value;
  return total * 100 / outstanding;
}
export function yieldAnalytics(flows: number[], frequency: number, fraction: number, outstanding: number, target: number): YieldAnalytics {
  const value = (y: number) => dirty(flows, frequency, fraction, outstanding, y), ytm = bisect(value, 0, 1, target);
  const present = presentByYield(flows, frequency, fraction, ytm);
  let total = 0, weighted = 0, second = 0;
  for (let k = 0; k < present.length; k++) {
    const time = (k + fraction) / frequency;
    total += present[k]; weighted += time * present[k]; second += time * (time + 1 / frequency) * present[k];
  }
  const growth = 1 + ytm / frequency, macaulay = weighted / total;
  return { ytm, macaulay, modified: macaulay / growth, convexity: second / (total * growth * growth),
    dv01: (value(ytm - 0.0001) - value(ytm + 0.0001)) / 2 };
}
