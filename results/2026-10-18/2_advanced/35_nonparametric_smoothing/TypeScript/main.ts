import { mkdirSync, writeFileSync } from 'node:fs';
import { readInput, type Point, type Series, type Settings, type Candidate, type Kernel, type Direction, type Fit, type Estimate } from './dataset.ts';
import * as kernels from './kernels.ts';
import * as loess from './loess.ts';
import * as spline from './spline.ts';
import * as selection from './selection.ts';

type Method = { name: string; kind: 'linear' | 'isotonic' }
  | { name: string; kind: 'mean' | 'median'; candidates: Candidate[] }
  | { name: string; kind: 'nw' | 'll'; kernel: Kernel; candidates: Candidate[] }
  | { name: string; kind: 'loess'; degree: number; candidates: Candidate[] }
  | { name: string; kind: 'spline'; candidates: Candidate[] };
interface BasicFit extends Fit { kind: 'linear' | 'running'; yhat: number[] }
interface Block { first: number; last: number; total: number; count: number; value: number }
interface IsotonicFit extends Fit { kind: 'isotonic'; yhat: number[]; blocks: Block[]; direction: Direction }
type FitResult = BasicFit | IsotonicFit | kernels.KernelFit | loess.LoessFit | spline.SplineFit;
interface Model {
  fit: FitResult; method: Method; name: string; order: number; chosen: Candidate | null; parameter: string;
  selected: number; candidates: { parameter: string; score: number | null; edf: number | null }[];
  loo: number; kfold: number | null; increasingRSS: number | null; decreasingRSS: number | null;
  yhat: number[]; lev: number[] | null; edf: number | null;
}
function sum(values: number[]): number { let total = 0; for (const v of values) total += v; return total; }
function squares(values: number[]): number { let total = 0; for (const v of values) total += v * v; return total; }
function residualSum(points: Point[], fitted: number[]): number { return squares(points.map((p, i) => p.y - fitted[i])); }
function real(value: number | null): string {
  if (value === null) return 'NA';
  if (Math.abs(value) >= 1e21) return (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString() + '.0000';
  const text = value.toFixed(4); return +text === 0 ? '0.0000' : text;
}
function hundredths(value: number): string {
  const n = Math.abs(value); return `${value < 0 ? '-' : ''}${Math.floor(n / 100)}.${String(n % 100).padStart(2, '0')}`;
}
function methodList(settings: Settings): Method[] {
  const methods: Method[] = [{ name: 'linear', kind: 'linear' }, { name: 'running_mean', kind: 'mean', candidates: settings.windows }, { name: 'running_median', kind: 'median', candidates: settings.windows }];
  for (const kind of ['nw', 'll'] as const) for (const kernel of settings.kernels) methods.push({ name: kind + '_' + kernel, kind, kernel, candidates: settings.bandwidths });
  for (const degree of settings.degrees) methods.push({ name: 'loess' + degree, kind: 'loess', degree, candidates: settings.spans });
  return [...methods, { name: 'spline', kind: 'spline', candidates: settings.lambdas }, { name: 'isotonic', kind: 'isotonic' }];
}
function fitLinear(points: Point[]): BasicFit {
  const n = points.length, xbar = sum(points.map(p => p.x)) / n, ybar = sum(points.map(p => p.y)) / n;
  let sxx = 0, sxy = 0;
  for (const p of points) { const d = p.x - xbar; sxx += d * d; sxy += d * (p.y - ybar); }
  const b = sxy / sxx, a = ybar - b * xbar;
  return { kind: 'linear', yhat: points.map(p => a + b * p.x), edf: 2, lev: points.map(p => 1 / n + (p.x - xbar) * (p.x - xbar) / sxx),
    at: (position: number) => ({ value: a + b * (position / 100), weights: points.map(p => 1 / n + (position / 100 - xbar) * (p.x - xbar) / sxx) }) };
}
function nearestPoint(points: Point[], position: number): number {
  let nearest = 0; for (let i = 1; i < points.length; i++) if (Math.abs(points[i].X - position) < Math.abs(points[nearest].X - position)) nearest = i;
  return nearest;
}
function fitRunning(points: Point[], width: number, median: boolean): BasicFit {
  const radii = points.map((_, i) => Math.min((width - 1) / 2, i, points.length - 1 - i));
  const yhat = radii.map((r, i) => { const values = points.slice(i - r, i + r + 1).map(p => p.Y); return median ? values.sort((a, b) => a - b)[r] / 100 : sum(values) / (100 * (2 * r + 1)); });
  const lev = median ? null : radii.map(r => 1 / (2 * r + 1));
  return { kind: 'running', yhat, lev, edf: lev === null ? null : sum(lev), at: (position: number) => {
    const c = nearestPoint(points, position); let weights: number[] | null = null;
    if (!median) { weights = points.map(() => 0); for (let j = c - radii[c]; j <= c + radii[c]; j++) weights[j] = 1 / (2 * radii[c] + 1); }
    return { value: yhat[c], weights };
  } };
}
function fitIsotonic(points: Point[], direction: Direction): IsotonicFit {
  const blocks: Block[] = [];
  points.forEach((p, i) => {
    blocks.push({ first: i, last: i, total: p.Y, count: 1, value: 0 });
    while (blocks.length >= 2) {
      const a = blocks[blocks.length - 2], b = blocks[blocks.length - 1], left = a.total * b.count, right = b.total * a.count;
      if (direction === 'increasing' ? left <= right : left >= right) break;
      blocks.splice(-2, 2, { first: a.first, last: b.last, total: a.total + b.total, count: a.count + b.count, value: 0 });
    }
  });
  const yhat: number[] = Array(points.length);
  for (const b of blocks) { b.value = b.total / (100 * b.count); for (let i = b.first; i <= b.last; i++) yhat[i] = b.value; }
  return { kind: 'isotonic', yhat, lev: null, edf: blocks.length, blocks, direction, at: (position: number) => {
    let i = 0; while (i + 1 < points.length && points[i + 1].X <= position) i++; return { value: yhat[i], weights: null };
  } };
}
function fitFull(method: Method, candidate: Candidate | null, points: Point[], iterations = 0, direction: Direction = 'increasing'): FitResult {
  switch (method.kind) {
    case 'linear': return fitLinear(points);
    case 'mean': case 'median': return fitRunning(points, candidate!.value, method.kind === 'median');
    case 'nw': case 'll': return kernels.fit(points, method.kind, method.kernel, candidate!.hundredths!);
    case 'loess': return loess.fit(points, method.degree, candidate!.hundredths!, iterations);
    case 'spline': return spline.fit(points, candidate!.value);
    case 'isotonic': return fitIsotonic(points, direction);
  }
}
function subsetEstimator(method: Method, candidate: Candidate | null, points: Point[], direction: Direction = 'increasing'): (position: number) => number | null {
  if (method.kind === 'nw' || method.kind === 'll') return x => kernels.estimate(points, method.kind, method.kernel, candidate!.hundredths!, x).value;
  if (method.kind === 'loess') { const rho = points.map(() => 1); return x => loess.localFit(points, method.degree, candidate!.hundredths!, rho, x).value; }
  const fit = method.kind === 'spline' ? spline.fit(points, candidate!.value, false) : fitFull(method, candidate, points, 0, direction);
  return x => fit.at(x).value;
}
function leaveOneOut(method: Method, candidate: Candidate | null, points: Point[], direction?: Direction): number | null {
  const predictions = points.map((p, i) => subsetEstimator(method, candidate, points.filter((_, j) => j !== i), direction)(p.X));
  return selection.crossValidation(points.map(p => p.y), predictions);
}
function kfold(method: Method, candidate: Candidate | null, points: Point[], direction: Direction | undefined, groups: number): number | null {
  const predictions: (number | null)[] = Array(points.length);
  for (let g = 0; g < groups; g++) {
    const at = subsetEstimator(method, candidate, points.filter((_, i) => i % groups !== g), direction);
    for (let i = g; i < points.length; i += groups) predictions[i] = at(points[i].X);
  }
  return selection.crossValidation(points.map(p => p.y), predictions);
}
function fitMethods(series: Series, settings: Settings, methods: Method[]): Model[] {
  const points = series.points;
  return methods.map((method, order) => {
    let fit: FitResult, chosen: Candidate | null = null, selected = -1, parameter = '-', loo: number | null;
    let increasingRSS: number | null = null, decreasingRSS: number | null = null;
    let candidates: Model['candidates'] = [];
    if (method.kind === 'linear') { fit = fitLinear(points); loo = leaveOneOut(method, null, points); }
    else if (method.kind === 'isotonic') {
      let iso: IsotonicFit;
      if (series.mode === 'auto') {
        const inc = fitIsotonic(points, 'increasing'), dec = fitIsotonic(points, 'decreasing');
        increasingRSS = residualSum(points, inc.yhat); decreasingRSS = residualSum(points, dec.yhat); iso = increasingRSS <= decreasingRSS ? inc : dec;
      } else iso = fitIsotonic(points, series.mode);
      fit = iso; parameter = iso.direction; loo = leaveOneOut(method, null, points, iso.direction);
    } else {
      const evaluated = method.candidates.map(candidate => {
        const fit = fitFull(method, candidate, points), score = method.kind === 'spline' ? selection.generalized(points.map(p => p.y), fit.yhat!, fit.edf!) : leaveOneOut(method, candidate, points);
        return { candidate, fit, score, edf: fit.edf };
      });
      selected = selection.choose(evaluated); const winner = evaluated[selected]; chosen = winner.candidate; parameter = chosen.text;
      fit = method.kind === 'loess' && settings.robustIterations > 0 ? fitFull(method, chosen, points, settings.robustIterations) : winner.fit;
      loo = method.kind === 'spline' ? leaveOneOut(method, chosen, points) : winner.score;
      candidates = evaluated.map(e => ({ parameter: e.candidate.text, score: e.score, edf: e.edf }));
    }
    return { fit, method, name: method.name, order, chosen, parameter, selected, candidates, loo: loo!, increasingRSS, decreasingRSS,
      yhat: fit.yhat!, lev: fit.lev, edf: fit.edf, kfold: kfold(method, chosen, points, fit.kind === 'isotonic' ? fit.direction : undefined, settings.folds) };
  });
}
function turningCount(estimates: Estimate[]): number {
  const values = estimates.map(e => e.value).filter((v): v is number => v !== null); let previous = 0, count = 0;
  for (let i = 1; i < values.length; i++) { const delta = values[i] - values[i - 1]; if (delta === 0) continue; const sign = delta > 0 ? 1 : -1; if (previous && previous !== sign) count++; previous = sign; }
  return count;
}
function diagnostics(points: Point[], model: Model, grid: Estimate[], linearRSS: number) {
  const n = points.length, errors = points.map((p, i) => p.y - model.yhat[i]), rss = squares(errors), ybar = sum(points.map(p => p.y)) / n;
  const tss = squares(points.map(p => p.y - ybar)), df = model.edf === null ? null : n - model.edf, rse = df === null ? null : Math.sqrt(rss / df);
  const nonlinear = model.name !== 'linear' && model.edf !== null && model.edf > 2 ? ((linearRSS - rss) / (model.edf - 2)) / (rss / df!) : null;
  const mean = sum(errors) / n, centered = errors.map(e => e - mean), denominator = squares(centered), acf: number[] = [];
  for (let lag = 1; lag <= 5; lag++) { let numerator = 0; for (let i = 0; i < n - lag; i++) numerator += centered[i] * centered[i + lag]; acf.push(numerator / denominator); }
  let successive = 0, positive = 0, negative = 0, runs = 0, previous = 0, largest = 0;
  for (let i = 0; i < n; i++) {
    if (i) { const d = errors[i] - errors[i - 1]; successive += d * d; }
    if (Math.abs(errors[i]) > Math.abs(errors[largest])) largest = i;
    if (errors[i] === 0) continue;
    const sign = errors[i] > 0 ? 1 : -1; if (sign > 0) positive++; else negative++; if (sign !== previous) runs++; previous = sign;
  }
  const nonzero = positive + negative, pairs = 2 * positive * negative, mu = 1 + pairs / nonzero, variance = pairs * (pairs - nonzero) / (nonzero * nonzero * (nonzero - 1));
  const sorted = [...errors].sort((a, b) => a - b), quantiles = [0, 1, 2, 3, 4].map(k => {
    const j = Math.floor((n - 1) * k / 4), r = (n - 1) * k - 4 * j; return r === 0 ? sorted[j] : sorted[j] + r / 4 * (sorted[j + 1] - sorted[j]);
  });
  return { errors, rss, df, rse, r2: 1 - rss / tss, nonlinear, acf, dw: successive / rss, positive, negative, runs, runsZ: (runs - mu) / Math.sqrt(variance), largest, quantiles, turning: turningCount(grid) };
}
type AnalyzedModel = Model & { grid: Estimate[]; diagnostics: ReturnType<typeof diagnostics> };
function compareFits(models: AnalyzedModel[], grid: number[], settings: Settings) {
  const ranking = [...models].sort((a, b) => a.loo - b.loo || a.order - b.order), best = ranking[0];
  const agreements = models.filter(m => m !== best).map(m => {
    let count = 0, total = 0, maximum = -1, position = grid[0];
    for (let k = 0; k < grid.length; k++) {
      const a = m.grid[k].value, b = best.grid[k].value; if (a === null || b === null) continue;
      const delta = Math.abs(a - b); count++; total += delta * delta; if (delta > maximum) { maximum = delta; position = grid[k]; }
    }
    return { name: m.name, count, rms: Math.sqrt(total / count), maximum, position };
  });
  const spl = models.find(m => m.name === 'spline')!; let maximum = -Infinity, minimum = Infinity, maxPosition = grid[1], minPosition = grid[1];
  for (let k = 1; k < grid.length - 1; k++) {
    const slope = (spl.grid[k + 1].value! - spl.grid[k - 1].value!) / ((grid[k + 1] - grid[k - 1]) / 100);
    if (slope > maximum) { maximum = slope; maxPosition = grid[k]; } if (slope < minimum) { minimum = slope; minPosition = grid[k]; }
  }
  const outlierMethod = ranking.find(m => m.lev !== null)!;
  const standardized: { index: number; t: number; cook: number }[] = [];
  outlierMethod.lev!.forEach((lev, i) => {
    if (lev >= 1) return;
    const t = outlierMethod.diagnostics.errors[i] / (outlierMethod.diagnostics.rse! * Math.sqrt(1 - lev));
    standardized.push({ index: i, t, cook: t * t * lev / ((1 - lev) * outlierMethod.edf!) });
  });
  return { ranking, best, agreements, slope: { maximum, minimum, maxPosition, minPosition }, outlierMethod, standardized,
    outliers: standardized.filter(e => Math.abs(e.t) > settings.threshold / 100).sort((a, b) => Math.abs(b.t) - Math.abs(a.t) || a.index - b.index),
    influence: [...standardized].sort((a, b) => b.cook - a.cook || a.index - b.index).slice(0, 3) };
}
interface BandValue { fit: number | null; se: number | null; lower: number | null; upper: number | null }
function variabilityBands(points: Point[], models: AnalyzedModel[], settings: Settings) {
  return settings.bandMethods.map(name => {
    const model = models.find(m => m.name === name)!, rse = model.diagnostics.rse!; let total = 0, count = 0;
    const values: BandValue[] = model.grid.map(e => {
      if (e.value === null) return { fit: null, se: null, lower: null, upper: null };
      const se = rse * Math.sqrt(squares(e.weights!)); total += se; count++;
      return { fit: e.value, se, lower: e.value - settings.bandZ * se, upper: e.value + settings.bandZ * se };
    });
    let coverage = 0;
    points.forEach((p, i) => { const se = rse * Math.sqrt(squares(model.fit.at(p.X).weights!)); if (Math.abs(model.diagnostics.errors[i]) <= settings.bandZ * Math.sqrt(rse * rse + se * se)) coverage++; });
    return { name, values, meanSE: total / count, coverage };
  });
}
function bootstrapIntervals(model: AnalyzedModel, grid: number[], settings: Settings, draw: () => number): BandValue[] {
  if (model.fit.kind !== 'spline') throw new Error('Bootstrap requires a spline');
  const system = model.fit.system, residuals = model.diagnostics.errors, mean = sum(residuals) / residuals.length, centered = residuals.map(e => e - mean);
  const samples: number[][] = grid.map(() => []);
  for (let b = 0; b < settings.bootstrap; b++) {
    const values = model.yhat.map(y => y + centered[draw() % residuals.length]), curve = system.fit(values);
    grid.forEach((x, k) => samples[k].push(system.evaluate(curve, x)));
  }
  return samples.map((values, k) => {
    const average = sum(values) / settings.bootstrap, se = Math.sqrt(squares(values.map(v => v - average)) / (settings.bootstrap - 1)), sorted = [...values].sort((a, b) => a - b);
    return { fit: model.grid[k].value, se, lower: sorted[settings.trim], upper: sorted[settings.bootstrap - settings.trim - 1] };
  });
}
function processSeries(series: Series, settings: Settings, methods: Method[], draw: () => number) {
  const points = series.points, last = points[points.length - 1], grid = Array.from({ length: settings.gridPoints }, (_, k) => points[0].X + Math.floor(k * (last.X - points[0].X) / (settings.gridPoints - 1)));
  const fitted = fitMethods(series, settings, methods), linearRSS = residualSum(points, fitted[0].yhat);
  const models = fitted.map(m => { const estimates = grid.map(x => m.fit.at(x)); return { ...m, grid: estimates, diagnostics: diagnostics(points, m, estimates, linearRSS) }; });
  return { series, grid, models, comparison: compareFits(models, grid, settings), bands: variabilityBands(points, models, settings),
    bootstrap: bootstrapIntervals(models.find(m => m.name === 'spline')!, grid, settings, draw), minY: Math.min(...points.map(p => p.Y)), maxY: Math.max(...points.map(p => p.Y)) };
}
type Result = ReturnType<typeof processSeries>;
function diagnosticsBlock(result: Result, settings: Settings): string[] {
  const { series: s, models, comparison: c, bands } = result, points = s.points;
  const lines = [`series ${s.name} n ${points.length} x ${hundredths(points[0].X)} ${hundredths(points[points.length - 1].X)} y ${hundredths(result.minY)} ${hundredths(result.maxY)}`];
  for (const m of models) {
    const d = m.diagnostics;
    lines.push(`method ${m.name} parameter ${m.parameter} loo ${real(m.loo)}` + (m.name === 'spline' ? ` gcv ${real(m.candidates[m.selected].score)}` : ''),
      `  rss ${real(d.rss)} edf ${real(m.edf)} df ${real(d.df)} rse ${real(d.rse)} r2 ${real(d.r2)} f_nonlinear ${real(d.nonlinear)}`,
      `  acf ${d.acf.map(real).join(' ')} dw ${real(d.dw)}`, `  runs ${d.runs} positive ${d.positive} negative ${d.negative} z ${real(d.runsZ)}`,
      `  max_residual ${real(d.errors[d.largest])} at ${hundredths(points[d.largest].X)} turning ${d.turning}`, `  quantiles ${d.quantiles.map(real).join(' ')}`);
    if (m.fit.kind === 'loess') {
      const fit = m.fit;
      for (const r of fit.records) lines.push(`  robust ${r.iteration} scale ${real(r.scale)} zero_weight ${r.zeros} max_change ${real(r.change)}`);
      const zeros = points.filter((_, i) => fit.robustness[i] === 0).map(p => hundredths(p.X)); lines.push('  zero_weight_points ' + (zeros.length ? zeros.join(' ') : 'none'));
    }
  }
  lines.push('ranking', ...c.ranking.map((m, i) => `  ${i + 1} ${m.name} ${real(m.loo)} kfold ${real(m.kfold)}`), 'agreement with ' + c.best.name,
    ...c.agreements.map(a => `  ${a.name} points ${a.count} rms ${real(a.rms)} max ${real(a.maximum)} at ${hundredths(a.position)}`));
  const slope = c.slope, outlier = c.outlierMethod;
  lines.push(`slope spline max ${real(slope.maximum)} at ${hundredths(slope.maxPosition)} min ${real(slope.minimum)} at ${hundredths(slope.minPosition)}`,
    `outliers method ${outlier.name} threshold ${hundredths(settings.threshold)}`);
  if (!c.outliers.length) lines.push('  none');
  for (const i of c.outliers) { const p = points[i.index]; lines.push(`  x ${hundredths(p.X)} y ${hundredths(p.Y)} fit ${real(outlier.yhat[i.index])} residual ${real(outlier.diagnostics.errors[i.index])} standardized ${real(i.t)}`); }
  lines.push('influence method ' + outlier.name, ...c.influence.map(i => `  x ${hundredths(points[i.index].X)} lev ${real(outlier.lev![i.index])} cook ${real(i.cook)}`), 'bands',
    ...bands.map(b => `  ${b.name} mean_se ${real(b.meanSE)} coverage ${b.coverage} of ${points.length}`));
  return lines;
}
function isotonicBlock(result: Result): string[] {
  const s = result.series, m = result.models.find(m => m.name === 'isotonic')!;
  if (m.fit.kind !== 'isotonic') throw new Error('Expected isotonic fit');
  const heading = `series ${s.name} direction ${m.fit.direction} mode ${s.mode}` + (s.mode === 'auto' ? ` rss_increasing ${real(m.increasingRSS)} rss_decreasing ${real(m.decreasingRSS)}` : '');
  return [heading, `blocks ${m.fit.blocks.length} rss ${real(m.diagnostics.rss)} loo ${real(m.loo)}`, ...m.fit.blocks.map((b, i) =>
    `block ${i + 1} x ${hundredths(s.points[b.first].X)} ${hundredths(s.points[b.last].X)} count ${b.count} value ${real(b.value)}`)];
}
function frame(cells: string[][]): string[] { const border = '+' + '-'.repeat(cells[0].length) + '+'; return [border, ...cells.map(row => '|' + row.join('') + '|'), border]; }
function histogram(standardized: { t: number }[]): string[] {
  const counts: number[] = Array(14).fill(0);
  for (const { t } of standardized) { let bin = 0; if (t >= 3) bin = 13; else if (t >= -3) { bin = 1; while (t >= -3 + 0.5 * bin) bin++; } counts[bin]++; }
  return counts.map((n, k) => `${k === 0 ? '-inf' : hundredths(-300 + 50 * (k - 1))} ${k === 13 ? 'inf' : hundredths(-300 + 50 * k)} ${n} |${'#'.repeat(n)}`);
}
function plotBlock(result: Result, settings: Settings): string[] {
  const { series: s, models, comparison: c, minY, maxY } = result, { width: w, height: h } = settings, points = s.points;
  const firstX = points[0].X, lastX = points[points.length - 1].X, ymin = minY / 100, ymax = maxY / 100;
  const blank = (): string[][] => Array.from({ length: h }, () => Array(w).fill(' ')), clampRow = (v: number) => Math.max(0, Math.min(h - 1, Math.floor(v)));
  const column = (p: Point) => Math.min(w - 1, Math.floor(w * (p.X - firstX) / (lastX - firstX))), cells = blank();
  for (const p of points) cells[Math.min(h - 1, Math.floor(h * (maxY - p.Y) / (maxY - minY)))][column(p)] = '.';
  settings.plotMethods.forEach((name, i) => {
    const model = models.find(m => m.name === name)!, digit = String(i + 1);
    for (let col = 0; col < w; col++) {
      const x = firstX + Math.floor((2 * col + 1) * (lastX - firstX) / (2 * w)), v = model.fit.at(x).value; if (v === null) continue;
      const row = clampRow(h * (ymax - v) / (ymax - ymin)), old = cells[row][col]; cells[row][col] = old === ' ' || old === '.' || old === digit ? digit : '*';
    }
  });
  let data = 0, curve = 0, overlap = 0;
  for (const row of cells) for (const ch of row) { if (ch === '.') data++; else if (ch === '*') overlap++; else if (ch >= '1' && ch <= '9') curve++; }
  const residuals = blank(), errors = c.best.diagnostics.errors; residuals[Math.floor(h / 2)].fill('-'); let limit = 0;
  for (const e of errors) limit = Math.max(limit, Math.abs(e));
  points.forEach((p, i) => { residuals[clampRow(h * ((limit - errors[i]) / (2 * limit)))][column(p)] = 'o'; });
  return [`plot ${s.name} size ${w}x${h} x ${hundredths(firstX)} ${hundredths(lastX)} y ${hundredths(minY)} ${hundredths(maxY)}`,
    'legend . data ' + settings.plotMethods.map((name, i) => `${i + 1} ${name}`).join(' '), ...frame(cells), `cells data ${data} curve ${curve} overlap ${overlap}`, '',
    `residuals ${s.name} method ${c.best.name} limit ${real(limit)}`, ...frame(residuals), '', `histogram ${s.name} method ${c.outlierMethod.name}`, ...histogram(c.standardized)];
}
function joinBlocks(blocks: string[][]): string[] { return blocks.flatMap((b, i) => i ? ['', ...b] : b); }
function main(): void {
  const { settings, series, tests } = readInput(), methods = methodList(settings); let state = settings.seed;
  const draw = () => { state = 48271 * state % 2147483647; return state; }, results = series.map(s => processSeries(s, settings, methods, draw));
  const byName = new Map(results.map(r => [r.series.name, r])), header = 'series,x,' + methods.map(m => m.name).join(',');
  const selected = ['series,method,parameter,score,edf,selected'], fits = [header], predictions = [header], bands = ['series,method,x,fit,se,lower,upper'];
  for (const r of results) {
    const name = r.series.name;
    for (const m of r.models) m.candidates.forEach((c, i) => selected.push([name, m.name, c.parameter, real(c.score), real(c.edf), i === m.selected ? 1 : 0].join(',')));
    r.grid.forEach((x, k) => fits.push([name, hundredths(x), ...r.models.map(m => real(m.grid[k].value))].join(',')));
    for (const b of [...r.bands, { name: 'spline_bootstrap', values: r.bootstrap }]) b.values.forEach((v, k) => bands.push([name, b.name, hundredths(r.grid[k]), real(v.fit), real(v.se), real(v.lower), real(v.upper)].join(',')));
  }
  for (const t of tests) predictions.push([t.name, hundredths(t.X), ...byName.get(t.name)!.models.map(m => real(m.fit.at(t.X).value))].join(','));
  const reports: Record<string, string[]> = { 'selection.csv': selected, 'fits.csv': fits, 'predictions.csv': predictions, 'bands.csv': bands,
    'diagnostics.txt': joinBlocks(results.map(r => diagnosticsBlock(r, settings))), 'isotonic.txt': joinBlocks(results.map(isotonicBlock)),
    'plots.txt': joinBlocks(settings.plotSeries.map(name => plotBlock(byName.get(name)!, settings))) };
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}
main();
