import { readInputs, writeOutputs } from './data_io.ts';
import type { Intervention } from './data_io.ts';
import { seird, sir, ageSeird, generation } from './models.ts';
import { simulate } from './integrator.ts';
import { goldenSearch, nelderMead } from './fitting.ts';
import type { Vertex } from './fitting.ts';
import { real, curvePlot } from './report.ts';

function sum(values: number[], first = 0, end = values.length): number {
  let total = 0;
  for (let i = first; i < end; i++) total += values[i];
  return total;
}
function dot(left: number[], right: number[]): number {
  let total = 0;
  for (let i = 0; i < left.length; i++) total += left[i] * right[i];
  return total;
}
function squaredError(series: number[], coefficient: number, observed: number[]): number {
  let total = 0;
  for (let i = 0; i < series.length; i++) {
    const difference = coefficient * series[i] - observed[i];
    total += difference * difference;
  }
  return total;
}
const rmse = (error: number, count: number) => Math.sqrt(error / count);
const incidence = (states: number[][]) => states.map((state) => state[5]);
function maximumIndex(values: number[]): number {
  let best = 0;
  for (let i = 1; i < values.length; i++) if (values[i] > values[best]) best = i;
  return best;
}
function cumulative(values: number[]): number[] {
  let total = 0;
  return values.map((value) => (total += value));
}
function multiplierSequence(interventions: Intervention[], count: number): number[] {
  const multipliers: number[] = [];
  let active = 0;
  for (let day = 1; day <= count; day++) {
    while (active + 1 < interventions.length && interventions[active + 1].day <= day) active++;
    multipliers.push(interventions[active].multiplier);
  }
  return multipliers;
}
function prepare(input: ReturnType<typeof readInputs>) {
  let N = 0;
  let fatalityTotal = 0;
  for (const group of input.groups) {
    N += group.population;
    fatalityTotal += group.population * group.fatality;
  }
  const T = input.cases.length;
  const p = input.params;
  return {
    ...input,
    N,
    T,
    fatality: fatalityTotal / N,
    caseTotal: sum(input.cases),
    deathTotal: sum(input.deaths),
    multipliers: multiplierSequence(input.interventions, T),
    betaSpacing: (p.betaMax - p.betaMin) / (p.betaCount - 1),
    rhoSpacing: (p.rhoMax - p.rhoMin) / (p.rhoCount - 1),
  };
}
type Data = ReturnType<typeof prepare>;
interface FitStage {
  beta: number;
  gamma: number;
  rho: number;
  error: number;
}
interface Fit extends FitStage {
  r0: number;
}
type ProfileName = 'beta' | 'gamma' | 'rho';
type StandardErrors = Record<ProfileName, number>;
function trajectory(
  data: Data,
  beta: number,
  gamma: number,
  multipliers = data.multipliers,
  sigma = data.params.sigma,
): number[][] {
  return simulate(seird(data, beta, gamma, sigma), multipliers);
}
function objective(data: Data, beta: number, gamma: number, rho: number): number {
  return squaredError(incidence(trajectory(data, beta, gamma)), rho, data.cases);
}
function goldenLines(
  lines: string[],
  result: ReturnType<typeof goldenSearch>,
  round: number,
  name: string,
  count: number,
): void {
  result.records.forEach((r, i) =>
    lines.push(
      `golden ${round} ${name} ${i} a ${real(r.a, 6)} b ${real(r.b, 6)} c ${real(r.c, 6)} d ${real(r.d, 6)} rmse ${real(rmse(r.fc, count))} ${real(rmse(r.fd, count))}`,
    ),
  );
  lines.push(
    `golden_result ${round} ${name} ${real(result.point, 6)} sse ${real(result.value, 1)}`,
  );
}
function fitModel(data: Data, lines: string[]): Fit {
  const p = data.params;
  const betas = Array.from(
    { length: p.betaCount },
    (_, i) => p.betaMin + ((p.betaMax - p.betaMin) * i) / (p.betaCount - 1),
  );
  const rhos = Array.from(
    { length: p.rhoCount },
    (_, i) => p.rhoMin + ((p.rhoMax - p.rhoMin) * i) / (p.rhoCount - 1),
  );
  lines.push(
    `data days ${data.T} cases ${data.caseTotal} deaths ${data.deathTotal} population ${data.N} fatality ${real(data.fatality, 6)}`,
  );
  lines.push(`grid gamma ${real(p.gamma)} rho ${rhos.map((v) => real(v)).join(' ')}`);
  let grid: FitStage | undefined;
  for (const beta of betas) {
    const series = incidence(trajectory(data, beta, p.gamma));
    const errors: number[] = [];
    for (const rho of rhos) {
      const error = squaredError(series, rho, data.cases);
      errors.push(error);
      if (grid === undefined || error < grid.error) grid = { beta, gamma: p.gamma, rho, error };
    }
    lines.push(
      `grid beta ${real(beta)} rmse ${errors.map((e) => real(rmse(e, data.T), 2)).join(' ')}`,
    );
  }
  if (grid === undefined) throw new Error('Empty parameter grid');
  lines.push(
    `grid_best beta ${real(grid.beta)} rho ${real(grid.rho)} sse ${real(grid.error, 1)} rmse ${real(rmse(grid.error, data.T))}`,
  );
  let beta = grid.beta;
  let rho = grid.rho;
  let goldenError = grid.error;
  for (let round = 1; round <= p.rounds; round++) {
    const betaSearch = goldenSearch(
      (x) => objective(data, x, p.gamma, rho),
      beta - data.betaSpacing,
      beta + data.betaSpacing,
      p.goldenIterations,
    );
    goldenLines(lines, betaSearch, round, 'beta', data.T);
    beta = betaSearch.point;
    const series = incidence(trajectory(data, beta, p.gamma));
    const rhoSearch = goldenSearch(
      (x) => squaredError(series, x, data.cases),
      rho - data.rhoSpacing,
      rho + data.rhoSpacing,
      p.goldenIterations,
    );
    goldenLines(lines, rhoSearch, round, 'rho', data.T);
    rho = rhoSearch.point;
    goldenError = rhoSearch.value;
  }
  const golden: FitStage = { beta, gamma: p.gamma, rho, error: goldenError };
  const simplex = nelderMead((x, y) => objective(data, x, y, rho), beta, p.gamma, p);
  const vertexText = (v: Vertex) =>
    `beta ${real(v.point[0], 6)} gamma ${real(v.point[1], 6)} rmse ${real(rmse(v.value, data.T))}`;
  for (const v of simplex.initial) lines.push(`simplex ${v.number} ${vertexText(v)}`);
  for (const r of simplex.records) {
    lines.push(`nelder_mead ${r.iteration} ${r.operation} ${vertexText(r.best)}`);
  }
  simplex.vertices.forEach((v, i) => lines.push(`final_simplex ${i + 1} ${vertexText(v)}`));
  const best = simplex.vertices[0];
  const fitted: Fit = {
    beta: best.point[0],
    gamma: best.point[1],
    rho,
    error: best.value,
    r0: best.point[0] / best.point[1],
  };
  const mean = data.caseTotal / data.T;
  let sst = 0;
  for (const cases of data.cases) {
    const difference = cases - mean;
    sst += difference * difference;
  }
  lines.push(
    `fitted beta ${real(fitted.beta, 6)} gamma ${real(fitted.gamma, 6)} rho ${real(rho, 6)} sigma ${real(p.sigma, 6)} r0 ${real(fitted.r0)}`,
  );
  lines.push(
    `sse grid ${real(grid.error, 1)} golden ${real(golden.error, 1)} nelder_mead ${real(fitted.error, 1)} rmse ${real(rmse(fitted.error, data.T))} r2 ${real(1 - fitted.error / sst)}`,
  );
  const stages: [string, FitStage][] = [
    ['grid', grid],
    ['golden', golden],
    ['nelder_mead', fitted],
  ];
  for (const [name, s] of stages) {
    lines.push(
      `stage ${name} beta ${real(s.beta, 6)} gamma ${real(s.gamma, 6)} rho ${real(s.rho, 6)} r0 ${real(s.beta / s.gamma)} rmse ${real(rmse(s.error, data.T))}`,
    );
  }
  return fitted;
}
function fittedCourse(data: Data, fit: Fit) {
  const model = seird(data, fit.beta, fit.gamma);
  const states = simulate(model, data.multipliers);
  const infections = incidence(states);
  const reported = infections.map((v) => fit.rho * v);
  const residuals = reported.map((v, i) => data.cases[i] - v);
  const deaths = states.map((s, i) => s[4] - (i === 0 ? 0 : states[i - 1][4]));
  const average7 = data.cases.map(
    (_, i) => sum(data.cases, Math.max(0, i - 6), i + 1) / Math.min(i + 1, 7),
  );
  return {
    model,
    states,
    infections,
    reported,
    residuals,
    deaths,
    average7,
    cumulativeObserved: cumulative(data.cases),
    cumulativeReported: cumulative(reported),
  };
}
type Course = ReturnType<typeof fittedCourse>;
function residualReport(data: Data, course: Course, lines: string[]): void {
  const { residuals, reported, infections } = course;
  let absolute = 0;
  let squares = 0;
  let differences = 0;
  let positive = 0;
  let runs = 1;
  for (let i = 0; i < data.T; i++) {
    const value = residuals[i];
    absolute += Math.abs(value);
    squares += value * value;
    if (value > 0) positive++;
    if (i > 0) {
      const change = value - residuals[i - 1];
      differences += change * change;
      if (value > 0 !== residuals[i - 1] > 0) runs++;
    }
  }
  const maximum = maximumIndex(residuals.map(Math.abs));
  lines.push(
    `residuals sum ${real(sum(residuals), 1)} mae ${real(absolute / data.T, 1)} max ${real(residuals[maximum], 1)} day ${maximum + 1} positive ${positive} runs ${runs} durbin_watson ${real(differences / squares)}`,
  );
  const correlations: string[] = [];
  for (let lag = 1; lag <= 7; lag++) {
    let product = 0;
    for (let i = 0; i < data.T - lag; i++) product += residuals[i] * residuals[i + lag];
    correlations.push(real(product / squares));
  }
  lines.push(`autocorrelation ${correlations.join(' ')}`);
  let outliers = 0;
  for (let i = 0; i < data.T; i++) {
    const z = residuals[i] / Math.sqrt(reported[i]);
    if (Math.abs(z) > data.params.outlier) {
      lines.push(
        `outlier ${i + 1} observed ${data.cases[i]} fitted ${real(reported[i], 1)} z ${real(z)}`,
      );
      outliers++;
    }
  }
  lines.push(`outliers ${outliers}`);
  const observed = Array<number>(7).fill(0);
  const expected = Array<number>(7).fill(0);
  for (let i = 0; i < data.T; i++) {
    observed[i % 7] += data.cases[i];
    expected[i % 7] += reported[i];
  }
  const factors = observed.map((v, i) => v / expected[i]);
  for (let i = 0; i < 7; i++) {
    lines.push(
      `weekday ${i + 1} observed ${observed[i]} fitted ${real(expected[i], 1)} factor ${real(factors[i])}`,
    );
  }
  const adjusted = reported.map((v, i) => v * factors[i % 7]);
  lines.push(`weekday_adjusted rmse ${real(rmse(squaredError(adjusted, 1, data.cases), data.T))}`);
  const burden = sum(infections);
  lines.push(
    `burden infections ${real(burden, 1)} ascertainment ${real(data.caseTotal / burden)} deaths_per_infection ${real(data.deathTotal / burden, 6)}`,
  );
}
function deathReport(data: Data, course: Course, lines: string[]): void {
  const scale = dot(course.deaths, data.deaths) / dot(course.deaths, course.deaths);
  lines.push(
    `deaths observed ${data.deathTotal} model ${real(course.states[data.T - 1][4], 1)} rmse ${real(rmse(squaredError(course.deaths, 1, data.deaths), data.T))} scale ${real(scale)} implied_fatality ${real(data.fatality * scale, 6)} cfr ${real(data.deathTotal / data.caseTotal)}`,
  );
  const correlations: number[] = [];
  for (let lag = 0; lag <= data.params.deathLag; lag++) {
    let cross = 0;
    let caseSquares = 0;
    let deathSquares = 0;
    for (let i = 0; i < data.T - lag; i++) {
      cross += data.cases[i] * data.deaths[i + lag];
      caseSquares += data.cases[i] * data.cases[i];
      deathSquares += data.deaths[i + lag] * data.deaths[i + lag];
    }
    const correlation = cross / Math.sqrt(caseSquares * deathSquares);
    correlations.push(correlation);
    const fatality = sum(data.deaths, lag) / sum(data.cases, 0, data.T - lag);
    lines.push(`death_lag ${lag} correlation ${real(correlation)} cfr ${real(fatality)}`);
  }
  lines.push(`death_best_lag ${maximumIndex(correlations)}`);
}
function weeklyReport(data: Data, course: Course, lines: string[]): void {
  let previous: number | null = null;
  for (let start = 0, week = 1; start < data.T; start += 7, week++) {
    const end = Math.min(start + 7, data.T);
    const cases = sum(data.cases, start, end);
    const growth = previous === null ? '-' : real(cases / previous);
    lines.push(
      `weekly ${week} days ${start + 1} ${end} observed ${cases} fitted ${real(sum(course.reported, start, end), 1)} deaths_observed ${sum(data.deaths, start, end)} deaths_model ${real(sum(course.deaths, start, end), 1)} growth ${growth}`,
    );
    previous = cases;
  }
}
function parameterProfiles(data: Data, fit: Fit, lines: string[]): StandardErrors {
  const standardErrors: StandardErrors = { beta: 0, gamma: 0, rho: 0 };
  const names: ProfileName[] = ['beta', 'gamma', 'rho'];
  for (const name of names) {
    const scores: number[] = [];
    for (let k = -5; k <= 5; k++) {
      const value = fit[name] * (1 + k / 100);
      const parameters = { ...fit, [name]: value };
      const score = objective(data, parameters.beta, parameters.gamma, parameters.rho);
      scores.push(score);
      lines.push(`profile ${name} ${k} value ${real(value, 6)} rmse ${real(rmse(score, data.T))}`);
    }
    const h = fit[name] / 100;
    const curvature = (scores[6] - 2 * scores[5] + scores[4]) / (h * h);
    const variance = fit.error / (data.T - 3);
    standardErrors[name] = Math.sqrt((2 * variance) / curvature);
    lines.push(`profile_se ${name} ${real(standardErrors[name], 6)}`);
  }
  return standardErrors;
}
function backtestReport(data: Data, fit: Fit, course: Course, lines: string[]): void {
  const count = data.T - data.params.holdout;
  const multipliers = data.multipliers.slice(0, count);
  const observed = data.cases.slice(0, count);
  const betaSearch = goldenSearch(
    (beta) =>
      squaredError(incidence(trajectory(data, beta, fit.gamma, multipliers)), fit.rho, observed),
    fit.beta - data.betaSpacing,
    fit.beta + data.betaSpacing,
    data.params.goldenIterations,
  );
  const beta = betaSearch.point;
  const training = incidence(trajectory(data, beta, fit.gamma, multipliers));
  const rhoSearch = goldenSearch(
    (rho) => squaredError(training, rho, observed),
    fit.rho - data.rhoSpacing,
    fit.rho + data.rhoSpacing,
    data.params.goldenIterations,
  );
  const rho = rhoSearch.point;
  const forecast = incidence(trajectory(data, beta, fit.gamma))
    .slice(count)
    .map((v) => rho * v);
  const heldOut = data.cases.slice(count);
  const testError = squaredError(forecast, 1, heldOut);
  const fullError = squaredError(course.reported.slice(count), 1, heldOut);
  lines.push(
    `backtest train_days ${count} beta ${real(beta, 6)} rho ${real(rho, 6)} train_rmse ${real(rmse(rhoSearch.value, count))} test_rmse ${real(rmse(testError, data.params.holdout))} full_fit_test_rmse ${real(rmse(fullError, data.params.holdout))}`,
  );
  for (let i = 0; i < forecast.length; i++) {
    lines.push(
      `backtest_day ${count + i + 1} observed ${heldOut[i]} forecast ${real(forecast[i], 1)} error ${real(heldOut[i] - forecast[i], 1)}`,
    );
  }
}
function interventionEffects(data: Data, fit: Fit, lines: string[]): void {
  const estimated = data.interventions.map((i) => ({ ...i }));
  let error = fit.error;
  for (let k = 1; k < estimated.length; k++) {
    const original = data.interventions[k];
    const search = goldenSearch(
      (multiplier) => {
        const changed = estimated.map((line, i) => (i === k ? { ...line, multiplier } : line));
        return squaredError(
          incidence(trajectory(data, fit.beta, fit.gamma, multiplierSequence(changed, data.T))),
          fit.rho,
          data.cases,
        );
      },
      original.multiplier - data.params.effectWidth,
      original.multiplier + data.params.effectWidth,
      data.params.goldenIterations,
    );
    estimated[k].multiplier = search.point;
    error = search.value;
    lines.push(
      `effect ${k + 1} day ${original.day} given ${real(original.multiplier)} estimated ${real(search.point, 6)} sse ${real(error, 1)}`,
    );
  }
  lines.push(
    `effect_sse before ${real(fit.error, 1)} after ${real(error, 1)} rmse ${real(rmse(error, data.T))}`,
  );
}
function sensitivityReport(data: Data, fit: Fit, lines: string[]): void {
  const names: ('beta' | 'gamma' | 'sigma' | 'rho')[] = ['beta', 'gamma', 'sigma', 'rho'];
  for (const name of names) {
    for (const factor of [0.9, 1.1]) {
      const p = { beta: fit.beta, gamma: fit.gamma, sigma: data.params.sigma, rho: fit.rho };
      p[name] *= factor;
      const states = trajectory(data, p.beta, p.gamma, data.multipliers, p.sigma);
      const series = incidence(states);
      const peak = maximumIndex(series);
      lines.push(
        `sensitivity ${name} ${real(factor, 2)} r0 ${real(p.beta / p.gamma)} rmse ${real(rmse(squaredError(series, p.rho, data.cases), data.T))} peak_day ${peak + 1} peak ${real(p.rho * series[peak], 1)} attack ${real((data.N - states[data.T - 1][0]) / data.N)}`,
      );
    }
  }
}
function ageIncidence(states: number[][], count: number): number[] {
  return states.map((state) => {
    let total = 0;
    for (let g = 0; g < count; g++) total += state[6 * g + 5];
    return total;
  });
}
function prepareAge(data: Data, fit: Fit) {
  let contacts = 0;
  for (let g = 0; g < data.groups.length; g++) {
    contacts += data.groups[g].population * sum(data.contacts[g]);
  }
  const meanContacts = contacts / data.N;
  const matrix = data.contacts.map((row) => row.map((v) => v / meanContacts));
  const model = ageSeird(data, fit.beta, fit.gamma, matrix);
  const states = simulate(model, data.multipliers);
  return {
    meanContacts,
    matrix,
    model,
    states,
    infections: ageIncidence(states, data.groups.length),
  };
}
type AgeCourse = ReturnType<typeof prepareAge>;
function modelReport(data: Data, fit: Fit, course: Course, age: AgeCourse, lines: string[]): void {
  const sirIncidence = (beta: number) =>
    simulate(sir(data, beta, fit.gamma), data.multipliers).map((state) => state[3]);
  const models: [string, number[]][] = [
    ['sir', sirIncidence(fit.beta)],
    ['seir', course.infections],
    ['age', age.infections],
  ];
  for (const [name, series] of models) {
    const optimalRho = dot(data.cases, series) / dot(series, series);
    lines.push(
      `model ${name} rmse ${real(rmse(squaredError(series, fit.rho, data.cases), data.T))} peak_day ${maximumIndex(series) + 1} rho_opt ${real(optimalRho, 6)} rmse_opt ${real(rmse(squaredError(series, optimalRho, data.cases), data.T))}`,
    );
  }
  const search = goldenSearch(
    (beta) => squaredError(sirIncidence(beta), fit.rho, data.cases),
    data.params.betaMin,
    data.params.betaMax,
    data.params.goldenIterations,
  );
  lines.push(
    `model sir_fit beta ${real(search.point, 6)} rmse ${real(rmse(search.value, data.T))} peak_day ${maximumIndex(sirIncidence(search.point)) + 1}`,
  );
}
function finalSize(reproduction: number): number {
  if (reproduction <= 1) return 0;
  let low = 1 - 1 / reproduction;
  let high = 1;
  for (let i = 0; i < 20; i++) {
    const middle = (low + high) / 2;
    const value = 1 - middle - Math.exp(-reproduction * middle);
    if (value > 0) low = middle;
    else high = middle;
  }
  return (low + high) / 2;
}
function largestEigenpair(matrix: number[][]) {
  let vector = Array<number>(matrix.length).fill(1 / matrix.length);
  let value = 0;
  for (let i = 0; i < 200; i++) {
    const product = matrix.map((row) => dot(row, vector));
    value = sum(product);
    vector = product.map((v) => v / value);
  }
  return { value, vector };
}
function generationAnalysis(data: Data, fit: Fit, course: Course) {
  const states = simulate(
    generation(data.params.sigma, fit.gamma),
    Array<number>(data.params.generation).fill(1),
  );
  const inflows = states.map((s) => s[2]);
  const coverage = sum(inflows);
  const weights = inflows.map((v) => v / coverage);
  let mean = 0;
  for (let s = 0; s < weights.length; s++) mean += (s + 1 - 0.5) * weights[s];
  const rt = data.multipliers.map(
    (m, i) => (fit.r0 * m * (i === 0 ? course.model.initial[0] : course.states[i - 1][0])) / data.N,
  );
  const pressure: number[] = [];
  for (let i = 0; i < data.T; i++) {
    let total = 0;
    for (let s = 1; s <= Math.min(weights.length, i); s++) {
      total += weights[s - 1] * data.cases[i - s];
    }
    pressure.push(total);
  }
  const empirical = pressure.map((_, i) =>
    i + 1 < weights.length + 7 ? null : sum(data.cases, i - 6, i + 1) / sum(pressure, i - 6, i + 1),
  );
  return { coverage, weights, mean, theory: 1 / data.params.sigma + 1 / fit.gamma, rt, empirical };
}
function counterfactualReport(data: Data, fit: Fit, course: Course, lines: string[]): void {
  const totalFitted = sum(course.reported);
  const reported = (interventions: Intervention[]) =>
    incidence(trajectory(data, fit.beta, fit.gamma, multiplierSequence(interventions, data.T))).map(
      (v) => fit.rho * v,
    );
  const withoutAll = reported([data.interventions[0]]);
  const total = sum(withoutAll);
  const peak = maximumIndex(withoutAll);
  lines.push(
    `counterfactual none reported ${real(total, 1)} peak_day ${peak + 1} peak ${real(withoutAll[peak], 1)} averted ${real(total - totalFitted, 1)}`,
  );
  for (let k = 1; k < data.interventions.length; k++) {
    const value = sum(reported(data.interventions.filter((_, i) => i !== k)));
    lines.push(
      `counterfactual without ${k + 1} reported ${real(value, 1)} averted ${real(value - totalFitted, 1)}`,
    );
  }
  for (let k = 1; k < data.interventions.length; k++) {
    for (const shift of [-7, 7]) {
      const changed = data.interventions.map((line, i) =>
        i === k ? { ...line, day: line.day + shift } : line,
      );
      const value = sum(reported(changed));
      lines.push(
        `timing ${k + 1} shift ${shift} reported ${real(value, 1)} change ${real(value - totalFitted, 1)}`,
      );
    }
  }
}
function reproductionReport(data: Data, fit: Fit, course: Course, lines: string[]): number[] {
  const a = generationAnalysis(data, fit, course);
  const longRun = trajectory(data, fit.beta, fit.gamma, Array<number>(730).fill(1));
  lines.push(`r0 ${real(fit.r0)} herd_immunity ${real(1 - 1 / fit.r0)}`);
  lines.push(
    `final_size equation ${real(finalSize(fit.r0))} simulated ${real((data.N - longRun[729][0]) / data.N)}`,
  );
  lines.push(
    `generation mean ${real(a.mean)} theory ${real(a.theory)} coverage ${real(a.coverage)}`,
  );
  a.weights.forEach((v, i) => lines.push(`generation_weight ${i + 1} ${real(v, 6)}`));
  const peak = maximumIndex(course.infections);
  const infectious = maximumIndex(course.states.map((s) => s[2]));
  const observed = maximumIndex(data.cases);
  const average = maximumIndex(course.average7);
  lines.push(
    `peak model day ${peak + 1} incidence ${real(course.infections[peak], 1)} reported ${real(course.reported[peak], 1)} infectious_day ${infectious + 1} infectious ${real(course.states[infectious][2], 1)}`,
  );
  lines.push(
    `peak observed day ${observed + 1} cases ${data.cases[observed]} average7_day ${average + 1} average7 ${real(course.average7[average], 2)}`,
  );
  for (let k = 0; k < data.interventions.length; k++) {
    const line = data.interventions[k];
    const start = line.day - 1;
    const end = k + 1 < data.interventions.length ? data.interventions[k + 1].day - 1 : data.T;
    const errors = course.residuals.slice(start, end);
    lines.push(
      `period ${k + 1} days ${start + 1} ${end} multiplier ${real(line.multiplier)} rt_start ${real(a.rt[start])} rt_end ${real(a.rt[end - 1])} observed ${sum(data.cases, start, end)} fitted ${real(sum(course.reported, start, end), 1)} rmse ${real(rmse(dot(errors, errors), end - start))} bias ${real(sum(errors) / (end - start), 1)}`,
    );
  }
  for (const target of data.params.milestones) {
    const observedDay = course.cumulativeObserved.findIndex((v) => v >= target);
    const fittedDay = course.cumulativeReported.findIndex((v) => v >= target);
    lines.push(
      `milestone ${target} observed ${observedDay < 0 ? 'never' : observedDay + 1} fitted ${fittedDay < 0 ? 'never' : fittedDay + 1}`,
    );
  }
  counterfactualReport(data, fit, course, lines);
  for (let i = 1; i < data.T; i++) {
    if (a.rt[i] < 1 !== a.rt[i - 1] < 1) {
      lines.push(`rt_cross day ${i + 1} ${a.rt[i] < 1 ? 'down' : 'up'}`);
    }
  }
  for (let i = 0; i < data.T; i++) {
    lines.push(`rt ${i + 1} model ${real(a.rt[i])} empirical ${real(a.empirical[i])}`);
  }
  return a.rt;
}
function nextGenerationMatrix(data: Data, r0: number, contacts: number[][]): number[][] {
  return contacts.map((row, g) =>
    row.map((v, h) => (r0 * v * data.groups[g].population) / data.groups[h].population),
  );
}
function ageFinalSizes(data: Data, fit: Fit, age: AgeCourse) {
  let equation = Array<number>(data.groups.length).fill(1);
  for (let i = 0; i < 100; i++) {
    equation = age.matrix.map((row) => {
      let total = 0;
      for (let h = 0; h < row.length; h++) total += fit.r0 * row[h] * equation[h];
      return 1 - Math.exp(-total);
    });
  }
  const final = simulate(age.model, Array<number>(730).fill(1))[729];
  const simulated = data.groups.map(
    (group, g) => (group.population - final[6 * g]) / group.population,
  );
  let equationTotal = 0;
  let simulatedTotal = 0;
  for (let g = 0; g < data.groups.length; g++) {
    equationTotal += data.groups[g].population * equation[g];
    simulatedTotal += data.groups[g].population * simulated[g];
  }
  return {
    equation,
    simulated,
    equationTotal: equationTotal / data.N,
    simulatedTotal: simulatedTotal / data.N,
  };
}
function contactChangeReport(data: Data, fit: Fit, age: AgeCourse, lines: string[]): void {
  for (const change of data.contactChanges) {
    const target = data.groups.findIndex((g) => g.name === change.group);
    const matrix = age.matrix.map((row, g) =>
      row.map(
        (v, h) => v * (g === target ? change.factor : 1) * (h === target ? change.factor : 1),
      ),
    );
    const eigenpair = largestEigenpair(nextGenerationMatrix(data, fit.r0, matrix));
    const states = simulate(ageSeird(data, fit.beta, fit.gamma, matrix), data.multipliers);
    const infections = sum(ageIncidence(states, data.groups.length));
    const final = states[data.T - 1];
    let deaths = 0;
    let affected = 0;
    for (let g = 0; g < data.groups.length; g++) {
      deaths += final[6 * g + 4];
      affected += data.groups[g].population - final[6 * g];
    }
    lines.push(
      `contact_change ${change.name} group ${change.group} factor ${real(change.factor)} r0_age ${real(eigenpair.value)} infections ${real(infections, 1)} deaths ${real(deaths, 1)} attack ${real(affected / data.N)}`,
    );
  }
}
function ageReport(
  data: Data,
  fit: Fit,
  age: AgeCourse,
  homogeneousRt: number[],
  lines: string[],
): void {
  const matrix = nextGenerationMatrix(data, fit.r0, age.matrix);
  const eigenpair = largestEigenpair(matrix);
  matrix.forEach((row, g) =>
    lines.push(`ngm ${data.groups[g].name} ${row.map((v) => real(v)).join(' ')}`),
  );
  lines.push(
    `r0_age ${real(eigenpair.value)} ratio ${real(eigenpair.value / fit.r0)} kbar ${real(age.meanContacts)} eigenvector ${eigenpair.vector.map((v) => real(v)).join(' ')}`,
  );
  const sizes = ageFinalSizes(data, fit, age);
  data.groups.forEach((group, g) =>
    lines.push(
      `final_size_age ${group.name} equation ${real(sizes.equation[g])} simulated ${real(sizes.simulated[g])}`,
    ),
  );
  lines.push(
    `final_size_age total equation ${real(sizes.equationTotal)} simulated ${real(sizes.simulatedTotal)}`,
  );
  for (let i = 0; i < data.T; i += 7) {
    const previous = i === 0 ? age.model.initial : age.states[i - 1];
    const effective = age.matrix.map((row, g) =>
      row.map(
        (v, h) => (data.multipliers[i] * fit.r0 * v * previous[6 * g]) / data.groups[h].population,
      ),
    );
    lines.push(
      `age_rt ${i + 1} ${real(largestEigenpair(effective).value)} homogeneous ${real(homogeneousRt[i])}`,
    );
  }
  for (let start = 0, week = 1; start < data.T; start += 7, week++) {
    const end = Math.min(start + 7, data.T);
    const totals = data.groups.map((_, g) => {
      let total = 0;
      for (let i = start; i < end; i++) total += age.states[i][6 * g + 5];
      return total;
    });
    lines.push(
      `age_weekly ${week} days ${start + 1} ${end} ${totals.map((v) => real(v, 1)).join(' ')}`,
    );
  }
  const groupIncidence = data.groups.map((_, g) => age.states.map((s) => s[6 * g + 5]));
  const totals = groupIncidence.map((s) => sum(s));
  const allInfections = sum(totals);
  const final = age.states[data.T - 1];
  for (let g = 0; g < data.groups.length; g++) {
    const group = data.groups[g];
    const peak = maximumIndex(groupIncidence[g]);
    lines.push(
      `age ${group.name} attack ${real((group.population - final[6 * g]) / group.population)} infections ${real(totals[g], 1)} share ${real(totals[g] / allInfections)} deaths ${real(final[6 * g + 4], 1)} peak_day ${peak + 1} peak ${real(groupIncidence[g][peak], 1)}`,
    );
  }
  contactChangeReport(data, fit, age, lines);
}
function scenarioReport(
  data: Data,
  fit: Fit,
  course: Course,
  age: AgeCourse,
  errors: StandardErrors,
  lines: string[],
): string[] {
  const csv = ['scenario,day,incidence,reported'];
  let reference: number | null = null;
  const betaLow = fit.beta - 2 * errors.beta;
  const betaHigh = fit.beta + 2 * errors.beta;
  for (const scenario of data.scenarios) {
    const multipliers = Array<number>(data.params.horizon).fill(scenario.multiplier);
    const last = course.states[data.T - 1];
    const states = simulate(course.model, multipliers, last);
    const infections = incidence(states);
    const reported = infections.map((v) => fit.rho * v);
    for (let i = 0; i < states.length; i++) {
      csv.push(
        `${scenario.name},${data.T + i + 1},${real(infections[i], 1)},${real(reported[i], 1)}`,
      );
    }
    const total = sum(reported);
    if (reference === null) reference = total;
    const peak = maximumIndex(reported);
    const below = reported.findIndex((v) => v < data.params.threshold);
    let daysAbove = 0;
    for (const value of reported) if (value >= data.params.threshold) daysAbove++;
    lines.push(
      `scenario ${scenario.name} multiplier ${real(scenario.multiplier)} rt ${real((fit.r0 * scenario.multiplier * last[0]) / data.N)} reported ${real(total, 1)} peak_day ${data.T + peak + 1} peak ${real(reported[peak], 1)} attack ${real((data.N - states[states.length - 1][0]) / data.N)} final_size ${real(finalSize(fit.r0 * scenario.multiplier))} averted ${real(reference - total, 1)} below ${below < 0 ? 'never' : data.T + below + 1} days_above ${daysAbove}`,
    );
    const extended = data.multipliers.concat(multipliers);
    const band = [betaLow, betaHigh].map((beta) => {
      const extendedStates = trajectory(data, beta, fit.gamma, extended);
      let total = 0;
      for (let i = data.T; i < extendedStates.length; i++) {
        total += fit.rho * extendedStates[i][5];
      }
      return total;
    });
    lines.push(
      `scenario_band ${scenario.name} beta_low ${real(betaLow, 6)} reported_low ${real(band[0], 1)} beta_high ${real(betaHigh, 6)} reported_high ${real(band[1], 1)}`,
    );
    const ageStates = simulate(age.model, multipliers, age.states[data.T - 1]);
    const finalAge = ageStates[ageStates.length - 1];
    const fractions = data.groups.map(
      (group, g) => (group.population - finalAge[6 * g]) / group.population,
    );
    let deaths = 0;
    for (let g = 0; g < data.groups.length; g++) deaths += finalAge[6 * g + 4];
    lines.push(
      `scenario_age ${scenario.name} attack ${fractions.map((v) => real(v)).join(' ')} deaths ${real(deaths, 1)}`,
    );
  }
  return csv;
}
function trajectoryLines(data: Data, course: Course): string[] {
  const lines = [
    'day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported',
  ];
  for (let i = 0; i < data.T; i++) {
    lines.push(
      [
        i + 1,
        ...course.states[i].map((v) => real(v, 1)),
        real(course.reported[i], 1),
        data.cases[i],
        real(course.average7[i], 2),
        course.cumulativeObserved[i],
        real(course.cumulativeReported[i], 1),
      ].join(','),
    );
  }
  return lines;
}
function main(): void {
  const data = prepare(readInputs());
  const fitLines: string[] = [];
  const fit = fitModel(data, fitLines);
  const course = fittedCourse(data, fit);
  const age = prepareAge(data, fit);
  residualReport(data, course, fitLines);
  deathReport(data, course, fitLines);
  weeklyReport(data, course, fitLines);
  const standardErrors = parameterProfiles(data, fit, fitLines);
  backtestReport(data, fit, course, fitLines);
  interventionEffects(data, fit, fitLines);
  sensitivityReport(data, fit, fitLines);
  modelReport(data, fit, course, age, fitLines);
  const reproduction: string[] = [];
  const rt = reproductionReport(data, fit, course, reproduction);
  ageReport(data, fit, age, rt, reproduction);
  const scenarios = scenarioReport(data, fit, course, age, standardErrors, reproduction);
  writeOutputs({
    'fit.txt': fitLines,
    'trajectories.csv': trajectoryLines(data, course),
    'scenarios.csv': scenarios,
    'reproduction.txt': reproduction,
    'curve_plot.txt': curvePlot(data.cases, course.reported),
  });
}
main();
