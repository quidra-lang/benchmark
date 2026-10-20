import { mkdirSync, writeFileSync } from 'node:fs';
import { readDataset, type Dataset, type Row, type Missing, type Scaling, type Settings } from './dataset.ts';
import * as matrix from './matrix.ts';
import * as eigen from './eigen.ts';
import * as pca from './pca.ts';
import * as plot from './plot.ts';

function real(v: number, digits = 4): string { if (Math.abs(v) >= 1e21) return BigInt(v).toString() + '.' + '0'.repeat(digits); const text = v.toFixed(digits); return +text === 0 ? (0).toFixed(digits) : text; }
function reals(v: number[]): string { return v.map(x => real(x)).join(' '); }
function sum(v: number[]): number { let s = 0; for (const x of v) s += x; return s; }
function sections(parts: string[][]): string[] { return parts.flatMap((p, i) => i ? ['', ...p] : p); }
function names(prefix: string, count: number): string[] { return Array.from({ length: count }, (_, i) => prefix + (i + 1)); }
function top<T>(items: T[], value: (item: T) => number, count: number): T[] { return items.map((item, index) => ({ item, index, value: value(item) })).sort((a, b) => b.value - a.value || a.index - b.index).slice(0, count).map(e => e.item); }
function maximumIndex(v: number[]): number { let best = 0; for (let i = 1; i < v.length; i++) if (v[i] > v[best]) best = i; return best; }
function summarize(data: Dataset) {
  return data.names.map((name, j) => {
    const observed = data.rows.map(r => r.values[j]).filter((v): v is number => v !== null), mean = sum(observed) / observed.length;
    return { name, observed: observed.length, missing: data.rows.length - observed.length, mean,
      deviation: Math.sqrt(sum(observed.map(v => (v - mean) * (v - mean))) / (observed.length - 1)), minimum: Math.min(...observed), maximum: Math.max(...observed) };
  });
}
function analysis(data: Dataset, summary: ReturnType<typeof summarize>, missing: Missing, scaling: Scaling) {
  const rows = data.rows.filter(r => missing === 'mean' || !r.values.includes(null)).map(r => ({ id: r.id, values: r.values.map((v, j) => v === null ? summary[j].mean : v) }));
  const prepared = pca.prepare(rows.map(r => r.values), scaling); return { rows, prepared, eigen: eigen.jacobi(prepared.matrix) };
}
type Analysis = ReturnType<typeof analysis>;
function adequacy(r: number[][], n: number) {
  const p = r.length, { inverse, determinant } = matrix.inverseDeterminant(r), rr: number[] = [], pp: number[] = [], msa: number[] = [];
  for (let j = 0; j < p; j++) {
    let a = 0, b = 0;
    for (let k = 0; k < p; k++) if (j !== k) { const partial = -inverse[j][k] / Math.sqrt(inverse[j][j] * inverse[k][k]); a += r[j][k] * r[j][k]; b += partial * partial; }
    rr.push(a); pp.push(b); msa.push(a / (a + b));
  }
  const total = sum(rr); return { msa, determinant, kmo: total / (total + sum(pp)), bartlett: -(n - 1 - (2 * p + 5) / 6) * Math.log(determinant), degrees: p * (p - 1) / 2 };
}
function parallelAnalysis(n: number, p: number, settings: Settings): number[] {
  let state = settings.seed; const totals: number[] = Array(p).fill(0);
  for (let r = 0; r < settings.parallel; r++) {
    const rows = matrix.zeros(n, p);
    for (const row of rows) for (let j = 0; j < p; j++) { state = 48271 * state % 2147483647; row[j] = state / 2147483647; }
    const values = eigen.jacobi(pca.prepare(rows, 'correlation').correlation).values, total = sum(values);
    for (let k = 0; k < p; k++) totals[k] += values[k] / total;
  }
  return totals.map(t => t / settings.parallel);
}
function retention(values: number[], n: number, parallel: number[], settings: Settings) {
  const p = values.length, total = sum(values), average = total / p, ratios = values.map(v => v / total), cumulative: number[] = []; let accumulated = 0;
  for (const r of ratios) { accumulated += r; cumulative.push(accumulated); }
  const broken = values.map((_, k) => { let s = 0; for (let i = k + 1; i <= p; i++) s += 1 / i; return s / p; });
  const errors = values.map(v => v * Math.sqrt(2 / n)), separated = values.map((v, k) => (k === 0 || Math.abs(v - values[k - 1]) > errors[k]) && (k === p - 1 || Math.abs(v - values[k + 1]) > errors[k]));
  const leading = (bounds: number[]) => { const failed = ratios.findIndex((r, k) => r <= bounds[k]); return failed < 0 ? p : failed; };
  const criteria = { kaiser: values.filter(v => v > average).length, broken_stick: leading(broken), parallel: leading(parallel), cumulative: cumulative.findIndex(v => v >= settings.target) + 1 };
  return { total, average, ratios, cumulative, broken, parallel, errors, separated, criteria, retained: Math.max(1, typeof settings.components === 'number' ? settings.components : criteria[settings.components]) };
}
function criterion(g: number[][]): number {
  const p = g.length; let total = 0;
  for (let k = 0; k < g[0].length; k++) { let q4 = 0, q2 = 0; for (const row of g) { const v = row[k]; q4 += (v * v) * (v * v); q2 += v * v; } total += q4 / p - (q2 / p) * (q2 / p); }
  return total;
}
function rotateVarimax(g: number[][], a: number, b: number): void {
  let sa = 0, sb = 0, sc = 0, sd = 0;
  for (const row of g) { const phi = row[a] * row[a] - row[b] * row[b], psi = 2 * row[a] * row[b]; sa += phi; sb += psi; sc += phi * phi - psi * psi; sd += 2 * phi * psi; }
  const num = sd - 2 * sa * sb / g.length, den = sc - (sa * sa - sb * sb) / g.length, omega = Math.sqrt(num * num + den * den);
  if (omega === 0) return;
  const cos4 = den / omega, sin4 = num / omega, cos2 = Math.sqrt((1 + cos4) / 2), sin2 = cos2 === 0 ? 1 : sin4 / (2 * cos2), cos1 = Math.sqrt((1 + cos2) / 2), sin1 = sin2 / (2 * cos1);
  for (const row of g) { const x = row[a], y = row[b]; row[a] = cos1 * x + sin1 * y; row[b] = -sin1 * x + cos1 * y; }
}
function varimax(loadings: number[][], retained: number, cycles: number) {
  const eta = loadings.map(row => Math.sqrt(sum(row.slice(0, retained).map(v => v * v)))), normalized = loadings.map((row, j) => row.slice(0, retained).map(v => v / eta[j])), criteria = [criterion(normalized)];
  for (let c = 0; c < cycles; c++) { for (let a = 0; a < retained - 1; a++) for (let b = a + 1; b < retained; b++) rotateVarimax(normalized, a, b); criteria.push(criterion(normalized)); }
  const columns = Array.from({ length: retained }, (_, index) => {
    const vector = matrix.orient(normalized.map((row, j) => row[index] * eta[j]));
    const agreements = Array.from({ length: retained }, (_, k) => { const original = matrix.column(loadings, k); return Math.abs(matrix.dot(vector, original) / Math.sqrt(matrix.dot(vector, vector) * matrix.dot(original, original))); });
    const closest = maximumIndex(agreements); return { index, vector, square: matrix.dot(vector, vector), closest, congruence: agreements[closest] };
  }).sort((a, b) => b.square - a.square || a.index - b.index);
  return { criteria, columns };
}
function diagnostics(row: Row, z: number[], result: eigen.Eigensystem, retained: number, settings: Settings) {
  const scores = pca.scores(z, result.vectors), residuals = pca.residuals(z, scores, result.vectors, retained), t2 = pca.tSquared(scores, result.values, retained), spe = matrix.dot(residuals, residuals);
  const flag = (t2 > settings.t2Limit ? 'T' : '') + (spe > settings.speLimit ? 'Q' : '');
  const t2Contributions = z.map((v, j) => { let w = 0; for (let k = 0; k < retained; k++) w += (scores[k] / result.values[k]) * result.vectors[k][j]; return v * w; });
  return { row, standardized: z, scores, residuals, t2, spe, flag: flag || '-', quality: sum(scores.slice(0, retained).map(v => v * v)) / matrix.dot(z, z), t2Contributions, speContributions: residuals.map(v => v * v) };
}
type Diagnostic = ReturnType<typeof diagnostics>;
function supplementaryRows(data: Dataset, main: Analysis, k: number, training: Diagnostic[]) {
  return data.supplementary.map(row => {
    const item = diagnostics(row, pca.standardize(row.values, main.prepared.means, main.prepared.scales), main.eigen, k, data.settings);
    let nearest = 0, distance = Infinity;
    training.forEach((other, i) => { let d = 0; for (let h = 0; h < k; h++) { const v = item.scores[h] - other.scores[h]; d += v * v; } if (d < distance) { distance = d; nearest = i; } });
    return { ...item, nearest: training[nearest].row.id, distance: Math.sqrt(distance) };
  });
}
type Supplementary = ReturnType<typeof supplementaryRows>;
function scoreSummary(data: Dataset, main: Analysis, training: Diagnostic[], k: number): string[] {
  const lines = ['scores', 'component sd min min_id max max_id contributors'];
  for (let h = 0; h < k; h++) {
    let squared = 0, min = training[0], max = training[0];
    for (const item of training) { squared += item.scores[h] * item.scores[h]; if (item.scores[h] < min.scores[h]) min = item; if (item.scores[h] > max.scores[h]) max = item; }
    const contributions = training.map(item => ({ id: item.row.id, value: item.scores[h] * item.scores[h] / ((training.length - 1) * main.eigen.values[h]) }));
    lines.push(`pc${h + 1} ${real(Math.sqrt(squared / (training.length - 1)))} ${real(min.scores[h])} ${min.row.id} ${real(max.scores[h])} ${max.row.id} ${top(contributions, c => c.value, data.settings.top).map(c => c.id + ':' + real(c.value)).join(' ')}`);
  }
  return lines;
}
function eigenReport(data: Dataset, summary: ReturnType<typeof summarize>, main: Analysis, measures: ReturnType<typeof adequacy>, r: ReturnType<typeof retention>, power: ReturnType<typeof eigen.power>, rotation: ReturnType<typeof varimax>, training: Diagnostic[]): string[] {
  const s = data.settings, p = data.names.length, incomplete = data.rows.filter(row => row.values.includes(null));
  const intro = [`pca rows ${data.rows.length} used ${main.rows.length} variables ${p} missing ${s.missing} scaling ${s.scaling}`, `incomplete ${incomplete.length} ${incomplete.length ? incomplete.map(row => row.id).join(' ') : '-'}`];
  const variables = ['variable observed missing mean sd min max msa', ...summary.map((v, j) => `${v.name} ${v.observed} ${v.missing} ${reals([v.mean, v.deviation, v.minimum, v.maximum, measures.msa[j]])}`),
    `adequacy kmo ${real(measures.kmo)} determinant ${real(measures.determinant, 6)} bartlett ${real(measures.bartlett)} df ${measures.degrees}`];
  const pairs: { j: number; k: number; value: number }[] = []; for (let j = 0; j < p; j++) for (let k = j + 1; k < p; k++) pairs.push({ j, k, value: main.prepared.correlation[j][k] });
  const mat = [`matrix ${s.scaling}`, ...main.prepared.matrix.map((row, j) => `${data.names[j]} ${reals(row)}`), 'strongest ' + top(pairs, v => Math.abs(v.value), s.top).map(v => `${data.names[v.j]}:${data.names[v.k]}:${real(v.value)}`).join(' ')];
  const spectrum = [`jacobi sweeps ${main.eigen.sweeps}`, `eigenvalues total ${real(r.total)} average ${real(r.average)}`, 'k eigenvalue ratio cumulative broken_stick parallel se separated',
    ...main.eigen.values.map((v, k) => `${k + 1} ${reals([v, r.ratios[k], r.cumulative[k], r.broken[k], r.parallel[k], r.errors[k]])} ${r.separated[k] ? 'yes' : 'no'}`),
    `retention kaiser ${r.criteria.kaiser} broken_stick ${r.criteria.broken_stick} parallel ${r.criteria.parallel} cumulative ${r.criteria.cumulative} target ${real(s.target)}`, `components ${r.retained} rule ${s.components}`];
  const vectors = ['eigenvectors', 'variable ' + names('pc', p).join(' '), ...data.names.map((name, j) => `${name} ${reals(main.eigen.vectors.map(v => v[j]))}`)];
  const cross = ['power_iteration iterations 1000', 'k jacobi power agree_at match', ...power.map((v, k) => `${k + 1} ${real(main.eigen.values[k])} ${real(v.value)} ${v.agreement ?? '-'} ${v.match ? 'yes' : 'no'}`), `cross_check ${power.filter(v => v.match).length}/${p}`];
  const rotated = [`varimax components ${r.retained} cycles ${s.cycles}`, ...rotation.criteria.map((v, c) => `cycle ${c} criterion ${real(v, 6)}`),
    ...rotation.columns.map((v, k) => `rc${k + 1} ss ${real(v.square)} ratio ${real(v.square / r.total)} closest pc${v.closest + 1} congruence ${real(v.congruence)}`)];
  const sensitivity = ['sensitivity', 'missing scaling rows sweeps eigenvalues cumulative congruence'];
  for (const missing of ['listwise', 'mean'] as const) for (const scaling of ['covariance', 'correlation'] as const) {
    const other = analysis(data, summary, missing, scaling), total = sum(other.eigen.values); let cumulative = 0; const congruence: number[] = [];
    for (let k = 0; k < r.retained; k++) { cumulative += other.eigen.values[k] / total; congruence.push(Math.abs(matrix.dot(other.eigen.vectors[k], main.eigen.vectors[k]))); }
    sensitivity.push(`${missing} ${scaling} ${other.rows.length} ${other.eigen.sweeps} ${reals(other.eigen.values.slice(0, r.retained))} ${real(cumulative)} ${reals(congruence)}`);
  }
  return sections([intro, variables, mat, spectrum, vectors, cross, scoreSummary(data, main, training, r.retained), rotated, sensitivity]);
}
function outlierReport(data: Dataset, main: Analysis, training: Diagnostic[], supplementary: Supplementary, k: number): string[] {
  const first = [`diagnostics components ${k} t2_limit ${real(data.settings.t2Limit)} spe_limit ${real(data.settings.speLimit)}`, 'id t2 spe quality flag',
    ...training.map(v => `${v.row.id} ${reals([v.t2, v.spe, v.quality])} ${v.flag}`),
    `flagged t2 ${training.filter(v => v.flag.includes('T')).length} spe ${training.filter(v => v.flag.includes('Q')).length} both ${training.filter(v => v.flag === 'TQ').length} any ${training.filter(v => v.flag !== '-').length}`];
  const parts = [first];
  for (const statistic of ['t2', 'spe'] as const) parts.push([`top ${statistic}`, `rank id ${statistic} variable contribution`, ...top(training, v => v[statistic], data.settings.top).map((v, rank) => {
    const contributions = statistic === 't2' ? v.t2Contributions : v.speContributions, j = maximumIndex(contributions); return `${rank + 1} ${v.row.id} ${real(v[statistic])} ${data.names[j]} ${real(contributions[j])}`;
  })]);
  const reconstruction = ['reconstruction', 'k mean_spe max_spe max_id'];
  for (let h = 1; h < data.names.length; h++) {
    let total = 0, maximum = -Infinity, id = '';
    for (const v of training) { const errors = pca.residuals(v.standardized, v.scores, main.eigen.vectors, h), spe = matrix.dot(errors, errors); total += spe; if (spe > maximum) { maximum = spe; id = v.row.id; } }
    reconstruction.push(`${h} ${real(total / training.length)} ${real(maximum)} ${id}`);
  }
  return sections([...parts, reconstruction, ['supplementary', `id ${names('pc', k).join(' ')} t2 spe flag nearest distance`, ...supplementary.map(v => `${v.row.id} ${reals(v.scores.slice(0, k))} ${reals([v.t2, v.spe])} ${v.flag} ${v.nearest} ${real(v.distance)}`)]]);
}
function axes(g: string[][], p: plot.Cell): void { g[p.row].fill('-'); for (const row of g) row[p.column] = '|'; g[p.row][p.column] = '+'; }
function density(g: string[][], positions: plot.Cell[]): void {
  const counts = matrix.zeros(g.length, g[0].length); for (const p of positions) counts[p.row][p.column]++;
  for (let r = 0; r < g.length; r++) for (let c = 0; c < g[0].length; c++) { const n = counts[r][c]; if (n > 0) g[r][c] = n === 1 ? '.' : n <= 3 ? 'o' : '@'; }
}
function plotsReport(data: Dataset, main: Analysis, retained: ReturnType<typeof retention>, training: Diagnostic[], supplementary: Supplementary, loadings: number[][]): string[] {
  const s = data.settings, largest = main.eigen.values[0], kc = Math.floor(retained.average / largest * s.screeWidth + 0.5);
  const scree = [`scree width ${s.screeWidth} kaiser_column ${kc}`, ...main.eigen.values.map((v, k) => `|${plot.scree(s.screeWidth, Math.floor(v / largest * s.screeWidth + 0.5), Math.floor(retained.broken[k] * retained.total / largest * s.screeWidth + 0.5), kc)}| pc${k + 1} ${real(v)}`)];
  const all = [...training, ...supplementary], mx = Math.max(...all.map(v => Math.abs(v.scores[0]))), my = Math.max(...all.map(v => Math.abs(v.scores[1])));
  const lx = Math.max(...loadings.map(v => Math.abs(v[0]))), ly = Math.max(...loadings.map(v => Math.abs(v[1]))), scale = 0.9 * Math.min(mx / lx, my / ly);
  const cell = (x: number, y: number) => plot.biplotCell(x, y, mx, my, s.biplotWidth, s.biplotHeight), origin = cell(0, 0), b = plot.grid(s.biplotWidth, s.biplotHeight); axes(b, origin);
  const tips = loadings.map(v => cell(scale * v[0], scale * v[1])); for (const tip of tips) for (const p of plot.shaft(origin, tip)) b[p.row][p.column] = p.character;
  const positions = training.map(v => cell(v.scores[0], v.scores[1])); density(b, positions);
  training.forEach((v, i) => { if (v.flag !== '-') b[positions[i].row][positions[i].column] = 'X'; });
  for (const v of supplementary) { const p = cell(v.scores[0], v.scores[1]); b[p.row][p.column] = '*'; }
  tips.forEach((p, j) => { b[p.row][p.column] = String.fromCharCode(65 + j); });
  const biplot = [`biplot pc1 pc2 width ${s.biplotWidth} height ${s.biplotHeight}`, `x ${real(-mx)} ${real(mx)} y ${real(-my)} ${real(my)} arrow_scale ${real(scale)}`, ...plot.frame(b),
    ...data.names.map((name, j) => `${String.fromCharCode(65 + j)} ${name} ${reals(loadings[j].slice(0, 2))}`)];
  const rho = s.radius, rc = rho / 2 + 1, cc = rho + 1, circle = plot.grid(2 * rho + 3, rho + 3); axes(circle, { row: rc, column: cc });
  const inside = (r: number, c: number) => (c - cc) * (c - cc) + (2 * (r - rc)) * (2 * (r - rc)) <= rho * rho;
  for (let r = 0; r < circle.length; r++) for (let c = 0; c < circle[0].length; c++) if (inside(r, c) && (!inside(r - 1, c) || !inside(r + 1, c) || !inside(r, c - 1) || !inside(r, c + 1))) circle[r][c] = '.';
  const correlations = loadings.map((v, j) => v.slice(0, 2).map(x => x / Math.sqrt(main.prepared.matrix[j][j])));
  correlations.forEach((v, j) => { circle[rc - Math.floor(v[1] * (rho / 2) + 0.5)][cc + Math.floor(v[0] * rho + 0.5)] = String.fromCharCode(65 + j); });
  const circleLines = [`circle radius ${rho}`, ...plot.frame(circle), ...correlations.map((v, j) => `${String.fromCharCode(65 + j)} ${data.names[j]} ${reals([v[0], v[1], v[0] * v[0] + v[1] * v[1]])}`)];
  const dx = 2 * s.t2Limit, dy = 2 * s.speLimit, dg = plot.grid(s.diagnosticWidth, s.diagnosticHeight), pos = (v: Diagnostic) => plot.diagnosticCell(v.t2, v.spe, dx, dy, s.diagnosticWidth, s.diagnosticHeight);
  axes(dg, plot.diagnosticCell(s.t2Limit, s.speLimit, dx, dy, s.diagnosticWidth, s.diagnosticHeight)); density(dg, training.map(pos));
  for (const v of supplementary) { const p = pos(v); dg[p.row][p.column] = '*'; }
  return sections([scree, biplot, circleLines, [`diagnostic width ${s.diagnosticWidth} height ${s.diagnosticHeight} t2_max ${real(dx)} spe_max ${real(dy)}`, ...plot.frame(dg)]]);
}
function main(): void {
  const data = readDataset(), summary = summarize(data), main = analysis(data, summary, data.settings.missing, data.settings.scaling), measures = adequacy(main.prepared.correlation, main.rows.length);
  const retained = retention(main.eigen.values, main.rows.length, parallelAnalysis(main.rows.length, data.names.length, data.settings), data.settings), k = retained.retained;
  const loadings = data.names.map((_, j) => main.eigen.values.map((v, h) => main.eigen.vectors[h][j] * Math.sqrt(v))), rotation = varimax(loadings, k, data.settings.cycles);
  const training = main.rows.map((row, i) => diagnostics(row, main.prepared.standardized[i], main.eigen, k, data.settings)), supplementary = supplementaryRows(data, main, k, training);
  const loadingLines = [['variable', ...names('pc', k), 'communality', ...names('rc', k)].join(','), ...data.names.map((name, j) => [name,
    ...loadings[j].slice(0, k).map(v => real(v)), real(sum(loadings[j].slice(0, k).map(v => v * v)) / main.prepared.matrix[j][j]), ...rotation.columns.map(v => real(v.vector[j]))].join(','))];
  const scoreLines = [['id', 'set', ...names('pc', k)].join(','), ...training.map(v => [v.row.id, 'data', ...v.scores.slice(0, k).map(x => real(x))].join(',')), ...supplementary.map(v => [v.row.id, 'supplementary', ...v.scores.slice(0, k).map(x => real(x))].join(','))];
  const reports: Record<string, string[]> = { 'eigen.txt': eigenReport(data, summary, main, measures, retained, eigen.power(main.prepared.matrix, main.eigen), rotation, training),
    'loadings.csv': loadingLines, 'scores.csv': scoreLines, 'outliers.txt': outlierReport(data, main, training, supplementary, k), 'plots.txt': plotsReport(data, main, retained, training, supplementary, loadings) };
  mkdirSync('output', { recursive: true }); for (const [name, lines] of Object.entries(reports)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}
main();
