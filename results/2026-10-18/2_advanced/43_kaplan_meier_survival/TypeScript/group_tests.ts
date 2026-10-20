import type { Subject } from './dataset.ts';
import { eventTimes } from './estimators.ts';
import { pValue, solve } from './numerics.ts';

export type Weight = 'logrank' | 'gehan_wilcoxon' | 'tarone_ware';
export const weights: Weight[] = ['logrank', 'gehan_wilcoxon', 'tarone_ware'];
export interface TestSums { events: number[]; observed: number[]; expected: number[]; covariance: number[][] }
export interface WeightedTest extends TestSums { chi2: number; df: number; p: number }
function empty(size: number): TestSums {
  return { events: Array<number>(size).fill(0), observed: Array<number>(size).fill(0), expected: Array<number>(size).fill(0), covariance: Array.from({ length: size }, () => Array<number>(size).fill(0)) };
}
export function finish(sums: TestSums): WeightedTest {
  const df = sums.events.length - 1, u = sums.observed.slice(0, df).map((o, i) => o - sums.expected[i]);
  const x = solve(sums.covariance.slice(0, df).map(row => row.slice(0, df)), u);
  let chi2 = 0; for (let h = 0; h < df; h++) chi2 = chi2 + u[h] * x[h];
  return { ...sums, chi2, df, p: pValue(chi2, df) };
}
export function weightedTest(subjects: Subject[], groups: string[], weight: Weight, totalSubjects: number): WeightedTest {
  const result = empty(groups.length);
  for (const time of eventTimes(subjects)) {
    const risks = groups.map(group => subjects.filter(s => s.group === group && s.time >= time).length);
    const events = groups.map(group => subjects.filter(s => s.group === group && s.time === time && s.event === 1).length);
    const n = risks.reduce((a, b) => a + b, 0), d = events.reduce((a, b) => a + b, 0);
    const nu = weight === 'logrank' ? 1 : weight === 'gehan_wilcoxon' ? n / totalSubjects : Math.sqrt(n / totalSubjects);
    for (let h = 0; h < groups.length; h++) {
      result.events[h] += events[h]; result.observed[h] = result.observed[h] + nu * events[h];
      result.expected[h] = result.expected[h] + nu * (d * risks[h] / n);
      if (n >= 2) for (let l = 0; l < groups.length; l++) {
        const coefficient = h === l ? risks[h] * (n - risks[h]) : -(risks[h] * risks[l]);
        result.covariance[h][l] = result.covariance[h][l] + nu * nu * (d * (n - d) / ((n - 1) * n * n)) * coefficient;
      }
    }
  }
  return finish(result);
}
export function stratified(tests: TestSums[]): WeightedTest {
  const result = empty(tests[0].events.length);
  for (const test of tests) for (let h = 0; h < result.events.length; h++) {
    result.events[h] += test.events[h]; result.observed[h] += test.observed[h]; result.expected[h] += test.expected[h];
    for (let l = 0; l < result.events.length; l++) result.covariance[h][l] += test.covariance[h][l];
  }
  return finish(result);
}
