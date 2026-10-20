import { writeFileSync } from 'node:fs';
import { numberValue, readInputs, type DataRow } from './dataframe.ts';
import { diagnose, type Diagnostics } from './diagnostics.ts';
import { columnValue, contained, designColumns, findLevels, formulaText, parseFormula, predictable, variables, type DesignColumn, type Model } from './formula.ts';
import { format as f, formatP as fp, pF, pT, significance, tQuantile } from './inference.ts';
import { fit, type Fit } from './qr_solver.ts';

const { data, predictions, formulas, params } = readInputs();
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);
interface Statistics { df: number; sigma: number; tss: number; r2: number; adjusted: number; f?: number; fP?: number; loglik: number; aic: number; bic: number; press: number; predicted: number; quantiles: number[]; critical: number }
function statistics(model: Fit, y: number[], weights: number[]): Statistics {
  const n = y.length, r = model.rank, df = n - r, sigma = Math.sqrt(model.rss / df), weightSum = sum(weights);
  const mean = sum(y.map((value, i) => weights[i] * value)) / weightSum;
  const tss = sum(y.map((value, i) => weights[i] * (value - mean) * (value - mean)));
  const r2 = 1 - model.rss / tss, adjusted = 1 - (1 - r2) * (n - 1) / df;
  const f = r > 1 ? ((tss - model.rss) / (r - 1)) / (model.rss / df) : undefined;
  const loglik = 0.5 * (sum(weights.map(Math.log)) - n * (Math.log(2 * 3.141592653589793) + 1 - Math.log(n) + Math.log(model.rss)));
  const aic = -2 * loglik + 2 * (r + 1), bic = -2 * loglik + Math.log(n) * (r + 1);
  const press = sum(model.weightedResiduals.map((eps, i) => (eps / (1 - model.leverage[i])) * (eps / (1 - model.leverage[i]))));
  const residuals = [...model.weightedResiduals].sort((a, b) => a - b);
  const quantiles = [0, 0.25, 0.5, 0.75, 1].map(proportion => {
    const g = (n - 1) * proportion, k = Math.floor(g); return k + 1 < n ? residuals[k] + (g - k) * (residuals[k + 1] - residuals[k]) : residuals[k];
  });
  return { df, sigma, tss, r2, adjusted, f, fP: f === undefined ? undefined : pF(f, r - 1, df), loglik, aic, bic, press, predicted: 1 - press / tss, quantiles, critical: tQuantile(params.confidence, df) };
}
interface ModelContext { model: Model; rows: DataRow[]; levels: Map<string, string[]>; columns: DesignColumn[]; x: number[][]; y: number[]; weights: number[]; fit: Fit; stats: Statistics; diagnostics: Diagnostics }
const models: ModelContext[] = formulas.map(line => {
  const model = parseFormula(line), required = variables(model), rows = data.rows.filter(row => required.every(name => row.values[name] !== null));
  const levels = findLevels(model, rows), columns = designColumns(model, levels), x = rows.map(row => columns.map(column => columnValue(column, row)));
  const y = rows.map(row => numberValue(row, model.response)), weights = rows.map(row => model.weight ? numberValue(row, model.weight) : 1);
  const fitted = fit(x, y, weights, params.tolerance), stats = statistics(fitted, y, weights), diagnostics = diagnose(fitted, x, stats.sigma, stats.df, params);
  return { model, rows, levels, columns, x, y, weights, fit: fitted, stats, diagnostics };
});
interface SubsetFit { fit: Fit; stats: Statistics }
function fitTerms(context: ModelContext, terms: number[]): SubsetFit {
  const columns = context.columns.flatMap((column, j) => column.term === undefined || terms.includes(column.term) ? [j] : []);
  const fitted = fit(context.x.map(row => columns.map(j => row[j])), context.y, context.weights, params.tolerance);
  return { fit: fitted, stats: statistics(fitted, context.y, context.weights) };
}
interface MarginalTest { term: number; df: number; ss: number; rss: number; f?: number; p?: number }
function marginal(context: ModelContext, terms: number[], current: SubsetFit): MarginalTest[] {
  return terms.filter(t => !terms.some(other => contained(context.model.terms[t], context.model.terms[other]))).map(term => {
    const reduced = fitTerms(context, terms.filter(t => t !== term)), df = current.fit.rank - reduced.fit.rank, ss = reduced.fit.rss - current.fit.rss;
    const value = df > 0 ? (ss / df) / (current.fit.rss / current.stats.df) : undefined;
    return { term, df, ss, rss: reduced.fit.rss, f: value, p: value === undefined ? undefined : pF(value, df, current.stats.df) };
  });
}
interface TableRow { fields: string[]; mark?: string }
interface Coefficient {
  name: string; estimate?: number; se?: number; t?: number; p?: number; lower?: number; upper?: number;
  robustSe?: number; robustT?: number; robustP?: number;
}
function table(header: string[], rows: TableRow[]): string[] {
  const widths = header.map((heading, c) => Math.max(heading.length, ...rows.map(row => row.fields[c]?.length ?? 0)));
  const render = (fields: string[], mark = '') => fields.map((field, c) => c ? field.padStart(widths[c]) : field.padEnd(widths[c])).join('  ').trimEnd() + (mark ? ' ' + mark : '');
  return [render(header), ...rows.map(row => render(row.fields, row.mark))];
}
const numericColumns = data.columns.filter(c => !c.categorical), categoricalColumns = data.columns.filter(c => c.categorical);
const summary = [`Data: ${data.rows.length} rows, ${data.columns.length} columns`, '', 'Numeric columns:'];
summary.push(...table(['column', 'n', 'missing', 'Mean', 'SD', 'Min', 'Max'], numericColumns.map(column => {
  const values = data.rows.map(row => row.values[column.name]).filter((value): value is number => typeof value === 'number'), mean = sum(values) / values.length;
  return { fields: [column.name, String(values.length), String(data.rows.length - values.length), f(mean), f(Math.sqrt(sum(values.map(value => (value - mean) * (value - mean))) / (values.length - 1))), f(Math.min(...values)), f(Math.max(...values))] };
})), '', 'Categorical columns:');
for (const column of categoricalColumns) {
  const values = data.rows.map(row => row.values[column.name]).filter((value): value is string => typeof value === 'string'), levels = [...new Set(values)].sort();
  summary.push(`${column.name}: ${values.length} values, ${data.rows.length - values.length} missing, ${levels.length} levels: ${levels.map(level => `${level} ${values.filter(value => value === level).length}`).join(', ')}`);
}
summary.push('', 'Correlations (pairwise complete observations):', ...table(['column', ...numericColumns.map(c => c.name)], numericColumns.map(a => ({ fields: [a.name, ...numericColumns.map(b => {
  const pairs = data.rows.flatMap(row => { const x = row.values[a.name], y = row.values[b.name]; return typeof x === 'number' && typeof y === 'number' ? [{ x, y }] : []; });
  const xbar = sum(pairs.map(pair => pair.x)) / pairs.length, ybar = sum(pairs.map(pair => pair.y)) / pairs.length;
  let xy = 0, xx = 0, yy = 0; for (const pair of pairs) { xy += (pair.x - xbar) * (pair.y - ybar); xx += (pair.x - xbar) * (pair.x - xbar); yy += (pair.y - ybar) * (pair.y - ybar); }
  return f(xy / Math.sqrt(xx * yy));
})] }))), '');
const diagnosticsLines = ['model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags'];
const predictionLines = ['model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered'];
const predictionChecks: string[] = [], plotBlocks: string[][] = [];
models.forEach((context, modelIndex) => {
  const { model, rows, columns, x, y, weights, fit: fitted, stats, diagnostics } = context, number = modelIndex + 1, n = rows.length, r = fitted.rank;
  if (modelIndex) summary.push('');
  const alias = columns.filter((_, j) => !fitted.accepted.includes(j)).map(column => column.name);
  summary.push(`Model ${number}: ${model.formula}`, `Terms: ${model.terms.map(term => term.name).join(', ')}`, `Weights: ${model.weight ?? 'none'}`, `Observations: ${n} used, ${data.rows.length - n} dropped`,
    `Columns: ${columns.length}, rank ${r}, aliased: ${alias.join(', ') || 'none'}`, '',
    `Residuals: Min ${f(stats.quantiles[0])}, 1Q ${f(stats.quantiles[1])}, Median ${f(stats.quantiles[2])}, 3Q ${f(stats.quantiles[3])}, Max ${f(stats.quantiles[4])}`, '', 'Coefficients:');
  const coefficients = columns.map((column, j): Coefficient => {
    const k = fitted.accepted.indexOf(j), estimate = fitted.beta[j];
    if (k < 0 || estimate === undefined) return { name: column.name };
    const se = stats.sigma * Math.sqrt(fitted.varianceFactors[k]), t = estimate / se, p = pT(t, stats.df);
    let robustVariance = 0;
    for (let i = 0; i < n; i++) { const eps = fitted.weightedResiduals[i], h = fitted.leverage[i], omega = eps * eps / ((1 - h) * (1 - h)); robustVariance += omega * fitted.g[i][k] * fitted.g[i][k]; }
    const robustSe = Math.sqrt(robustVariance), robustT = estimate / robustSe;
    return { name: column.name, estimate, se, t, p, lower: estimate - stats.critical * se, upper: estimate + stats.critical * se, robustSe, robustT, robustP: pT(robustT, stats.df) };
  });
  summary.push(...table(['term', 'Estimate', 'Std. Error', 't value', 'Pr(>|t|)'], coefficients.map(c => ({ fields: [c.name, f(c.estimate), f(c.se), f(c.t), fp(c.p)], mark: significance(c.p) }))), '---',
    "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", '',
    `Residual standard error: ${f(stats.sigma)} on ${stats.df} degrees of freedom`, `Multiple R-squared: ${f(stats.r2)}, Adjusted R-squared: ${f(stats.adjusted)}`,
    `F-statistic: ${f(stats.f)} on ${r - 1} and ${stats.df} DF, p-value: ${fp(stats.fP)}`, `Log-likelihood: ${f(stats.loglik)}, AIC: ${f(stats.aic)}, BIC: ${f(stats.bic)}`,
    `PRESS: ${f(stats.press)}, Predicted R-squared: ${f(stats.predicted)}`, '', `Confidence intervals (level ${f(params.confidence)}, t ${f(stats.critical)}):`,
    ...table(['term', 'Lower', 'Upper'], coefficients.map(c => ({ fields: [c.name, f(c.lower), f(c.upper)] }))), '', 'Robust standard errors (HC3):',
    ...table(['term', 'Std. Error', 't value', 'Pr(>|t|)'], coefficients.map(c => ({ fields: [c.name, f(c.robustSe), f(c.robustT), fp(c.robustP)], mark: significance(c.robustP) }))), '', 'Analysis of variance (sequential):');
  const sequential: TableRow[] = [];
  model.terms.forEach((term, t) => {
    const accepted = fitted.accepted.flatMap((j, k) => columns[j].term === t ? [k] : []), df = accepted.length;
    if (!df) return;
    const ss = sum(accepted.map(k => fitted.effects[k] * fitted.effects[k])), ms = ss / df, value = ms / (fitted.rss / stats.df), p = pF(value, df, stats.df);
    sequential.push({ fields: [term.name, String(df), f(ss), f(ms), f(value), fp(p)], mark: significance(p) });
  });
  sequential.push({ fields: ['Residuals', String(stats.df), f(fitted.rss), f(fitted.rss / stats.df)] });
  const terms = model.terms.map((_, t) => t), marginalTests = marginal(context, terms, { fit: fitted, stats });
  summary.push(...table(['term', 'Df', 'Sum Sq', 'Mean Sq', 'F value', 'Pr(>F)'], sequential), '', 'Marginal F tests (drop one term):',
    ...table(['term', 'Df', 'Sum Sq', 'RSS', 'F value', 'Pr(>F)'], marginalTests.map(test => ({ fields: [model.terms[test.term].name, String(test.df), f(test.ss), f(test.rss), f(test.f), fp(test.p)], mark: significance(test.p) }))), '', 'Variance inflation factors:');
  const vifRows: TableRow[] = fitted.accepted.slice(1).map(j => {
    const response = x.map(row => row[j]), matrix = x.map(row => fitted.accepted.filter(k => k !== j).map(k => row[k]));
    const auxiliary = fit(matrix, response, weights, params.tolerance), mean = sum(response.map((value, i) => weights[i] * value)) / sum(weights);
    const tss = sum(response.map((value, i) => weights[i] * (value - mean) * (value - mean))), r2 = 1 - auxiliary.rss / tss, value = 1 / (1 - r2);
    return { fields: [columns[j].name, f(value)], mark: value > params.vif ? 'high' : '' };
  });
  const acceptedX = x.map(row => fitted.accepted.map(j => row[j])), reset = fit(acceptedX.map((row, i) => [...row, fitted.fitted[i] * fitted.fitted[i], fitted.fitted[i] * fitted.fitted[i] * fitted.fitted[i]]), y, weights, params.tolerance);
  const resetDf = reset.rank - r, resetResidualDf = n - reset.rank, resetF = ((fitted.rss - reset.rss) / resetDf) / (reset.rss / resetResidualDf), resetP = pF(resetF, resetDf, resetResidualDf);
  const order = rows.map((_, i) => i), outlier = [...order].sort((a, b) => Math.abs(diagnostics.rows[b].studentized) - Math.abs(diagnostics.rows[a].studentized) || a - b)[0];
  const outlierP = pT(diagnostics.rows[outlier].studentized, stats.df - 1), cooks = [...order].sort((a, b) => diagnostics.rows[b].cooks - diagnostics.rows[a].cooks || a - b).slice(0, 3);
  const dwResult = diagnostics.dw < params.durbinWatson ? 'positive autocorrelation' : diagnostics.dw > 4 - params.durbinWatson ? 'negative autocorrelation' : 'no autocorrelation';
  summary.push(...table(['column', 'VIF'], vifRows), '', 'Diagnostics:', `Durbin-Watson: ${f(diagnostics.dw)} (${dwResult})`,
    `Breusch-Pagan: ${f(diagnostics.bp)} on ${diagnostics.bpDf} DF, p-value: ${fp(diagnostics.bpP)} (${diagnostics.bpP < params.heterogeneity ? 'heteroscedastic' : 'homoscedastic'})`,
    `Jarque-Bera: ${f(diagnostics.jb)} on 2 DF, p-value: ${fp(diagnostics.jbP)}, skewness ${f(diagnostics.skewness)}, kurtosis ${f(diagnostics.kurtosis)} (${diagnostics.jbP < params.normality ? 'non-normal' : 'normal'})`,
    `RESET (powers 2 and 3): F ${f(resetF)} on ${resetDf} and ${resetResidualDf} DF, p-value: ${fp(resetP)}`,
    `Outlier test: row ${rows[outlier].number}, studentized ${f(diagnostics.rows[outlier].studentized)}, unadjusted p-value: ${fp(outlierP)}, Bonferroni p-value: ${fp(Math.min(1, n * outlierP))}`,
    `Flagged rows: leverage ${diagnostics.rows.filter(row => row.flags.includes('H')).length}, outlier ${diagnostics.rows.filter(row => row.flags.includes('O')).length}, cooks ${diagnostics.rows.filter(row => row.flags.includes('C')).length}, dffits ${diagnostics.rows.filter(row => row.flags.includes('F')).length}, any ${diagnostics.rows.filter(row => row.flags !== '-').length}`,
    "Largest Cook's distances:", ...cooks.map(i => `row ${rows[i].number}: cooks_d ${f(diagnostics.rows[i].cooks)}, leverage ${f(fitted.leverage[i])}, studentized ${f(diagnostics.rows[i].studentized)}, flags ${diagnostics.rows[i].flags}`), 'Largest absolute DFBETAS:');
  summary.push(...table(['column', 'row', 'DFBETAS'], fitted.accepted.map((j, k) => {
    let best = 0; for (let i = 1; i < n; i++) if (Math.abs(diagnostics.rows[i].dfbetas[k]) > Math.abs(diagnostics.rows[best].dfbetas[k])) best = i;
    return { fields: [columns[j].name, String(rows[best].number), f(diagnostics.rows[best].dfbetas[k])] };
  })));
  rows.forEach((row, i) => { const d = diagnostics.rows[i]; diagnosticsLines.push(`${number},${row.number},${f(fitted.fitted[i])},${f(fitted.residuals[i])},${f(fitted.leverage[i])},${f(d.studentized)},${f(d.cooks)},${f(d.dffits)},${d.flags}`); });
  let predictedCount = 0, actualCount = 0, errorSquares = 0, coveredCount = 0;
  for (const row of predictions.rows) {
    const values = [String(number), String(row.number)];
    if (!predictable(model, context.levels, row)) values.push(...Array<string>(9).fill('NA'));
    else {
      predictedCount++; const design = columns.map(column => columnValue(column, row));
      let prediction = 0; for (const j of fitted.accepted) prediction += design[j] * fitted.beta[j]!;
      const u = fitted.accepted.map((_, k) => { let value = 0; fitted.accepted.forEach((j, m) => { value += design[j] * fitted.inverse[m][k]; }); return value; });
      const se = stats.sigma * Math.sqrt(sum(u.map(value => value * value))), confidenceHalf = stats.critical * se, predictionHalf = stats.critical * Math.sqrt(stats.sigma * stats.sigma + se * se);
      values.push(f(prediction), f(se), f(prediction - confidenceHalf), f(prediction + confidenceHalf), f(prediction - predictionHalf), f(prediction + predictionHalf));
      const actual = row.values[model.response];
      if (typeof actual !== 'number') values.push('NA', 'NA', 'NA');
      else {
        const error = actual - prediction, covered = prediction - predictionHalf <= actual && actual <= prediction + predictionHalf;
        actualCount++; errorSquares += error * error; if (covered) coveredCount++;
        values.push(f(actual), f(error), covered ? 'yes' : 'no');
      }
    }
    predictionLines.push(values.join(','));
  }
  predictionChecks.push(`model ${number}: ${predictedCount} predicted, ${actualCount} with actual values, RMSE ${actualCount ? f(Math.sqrt(errorSquares / actualCount)) : 'NA'}, inside prediction interval ${coveredCount}`);
  const { width, height, range } = params;
  const grid = (horizontal: number[], lo: number, hi: number) => {
    const cells = Array.from({ length: height }, () => Array<number>(width).fill(0));
    diagnostics.rows.forEach((row, i) => {
      const column = Math.min(Math.floor((horizontal[i] - lo) / (hi - lo) * width), width - 1), position = Math.max(0, Math.min(height - 1, Math.floor((range - row.studentized) / (2 * range) * height)));
      cells[position][column]++;
    });
    return cells;
  };
  const frame = (cells: number[][]) => { const border = '+' + '-'.repeat(width) + '+'; return [border, ...cells.map((row, rho) => '|' + row.map(count => count >= 10 ? '*' : count > 0 ? String(count) : rho === Math.floor(height / 2) ? '-' : '.').join('') + '|'), border]; };
  const minimumFit = Math.min(...fitted.fitted), maximumFit = Math.max(...fitted.fitted), maximumH = Math.max(...fitted.leverage), residualGrid = grid(fitted.fitted, minimumFit, maximumFit);
  const histogram = residualGrid.map(sum), maximumCount = Math.max(...histogram);
  const plot = [`Model ${number}: studentized residuals vs fitted values`, `fitted ${f(minimumFit)} to ${f(maximumFit)}, studentized ${f(-range)} to ${f(range)}`, ...frame(residualGrid),
    `points: ${n}, above +2: ${diagnostics.rows.filter(row => row.studentized > 2).length}, below -2: ${diagnostics.rows.filter(row => row.studentized < -2).length}, outside range: ${diagnostics.rows.filter(row => Math.abs(row.studentized) > range).length}`, 'Histogram of studentized residuals:'];
  histogram.forEach((count, rho) => {
    const length = Math.floor((count * 40 + maximumCount - 1) / maximumCount);
    plot.push(`${f(range - 2 * range * (rho + 1) / height)} to ${f(range - 2 * range * rho / height)}: ${count}${length ? ' ' + '#'.repeat(length) : ''}`);
  });
  plot.push(`Model ${number}: studentized residuals vs leverage`, `leverage 0.0000 to ${f(maximumH)}, studentized ${f(-range)} to ${f(range)}`, ...frame(grid(fitted.leverage, 0, maximumH))); plotBlocks.push(plot);
});
summary.push('', 'Model comparison:', ...table(['model', 'n', 'rank', 'sigma', 'R-squared', 'Adj. R-squared', 'Pred. R-squared', 'AIC', 'BIC'], models.map((model, i) => ({ fields: [String(i + 1), String(model.rows.length), String(model.fit.rank), f(model.stats.sigma), f(model.stats.r2), f(model.stats.adjusted), f(model.stats.predicted), f(model.stats.aic), f(model.stats.bic)] }))), '', 'Prediction check:', ...predictionChecks);
const first = models[0], allTerms = first.model.terms.map((_, t) => t), subsetCache = new Map<string, SubsetFit>();
const subset = (terms: number[]): SubsetFit => { const key = terms.join(','); let result = subsetCache.get(key); if (!result) { result = fitTerms(first, terms); subsetCache.set(key, result); } return result; };
const selection = [`Backward elimination (model 1, alpha ${f(params.alpha)}, rows ${first.rows.length})`];
let selected = [...allTerms];
for (let step = 1;; step++) {
  const current = subset(selected); selection.push(`Step ${step}: ${formulaText(first.model, selected)} (RSS ${f(current.fit.rss)}, df ${current.stats.df}, AIC ${f(current.stats.aic)})`);
  if (!selected.length) { selection.push('  stop: no removable terms'); break; }
  const tests = marginal(first, selected, current); let best = tests[0];
  for (const test of tests) {
    selection.push(`  - ${first.model.terms[test.term].name}: F ${f(test.f)} on ${test.df} and ${current.stats.df} DF, p-value ${fp(test.p)}`);
    if (test.p! > best.p!) best = test;
  }
  if (best.p! > params.alpha) { selection.push(`  remove ${first.model.terms[best.term].name}`); selected = selected.filter(term => term !== best.term); }
  else { selection.push(`  stop: largest p-value ${fp(best.p)} is not above ${f(params.alpha)}`); break; }
}
selection.push(`Final model: ${formulaText(first.model, selected)}`, '', `Forward selection by AIC (model 1, rows ${first.rows.length})`);
selected = [];
for (let step = 1;; step++) {
  const current = subset(selected); selection.push(`Step ${step}: ${formulaText(first.model, selected)} (AIC ${f(current.stats.aic)})`);
  const candidates = allTerms.filter(term => !selected.includes(term) && allTerms.every(other => !contained(first.model.terms[other], first.model.terms[term]) || selected.includes(other)));
  if (!candidates.length) { selection.push('  stop: no candidate terms remain'); break; }
  const trials = candidates.map(term => {
    const terms = [...selected, term].sort((a, b) => a - b), result = subset(terms);
    selection.push(`  + ${first.model.terms[term].name}: AIC ${f(result.stats.aic)}`); return { term, terms, result };
  });
  let best = trials[0]; for (const trial of trials.slice(1)) if (trial.result.stats.aic < best.result.stats.aic) best = trial;
  if (best.result.stats.aic < current.stats.aic) { selection.push(`  add ${first.model.terms[best.term].name}`); selected = best.terms; }
  else { selection.push('  stop: no candidate lowers the AIC'); break; }
}
selection.push(`Final model: ${formulaText(first.model, selected)}`);
const subsets: { mask: number; terms: number[]; result: SubsetFit }[] = [];
for (let mask = 0; mask < 2 ** allTerms.length; mask++) {
  const terms = allTerms.filter(term => Math.floor(mask / 2 ** term) % 2 === 1);
  if (terms.every(term => allTerms.every(other => !contained(first.model.terms[other], first.model.terms[term]) || terms.includes(other)))) subsets.push({ mask, terms, result: subset(terms) });
}
subsets.sort((a, b) => a.result.stats.bic - b.result.stats.bic || a.mask - b.mask);
selection.push('', `Best subsets by BIC (model 1, rows ${first.rows.length}, subsets ${subsets.length})`, ...subsets.slice(0, params.best).map(({ terms, result }, i) => `${i + 1}. BIC ${f(result.stats.bic)}, AIC ${f(result.stats.aic)}, rank ${result.fit.rank}: ${formulaText(first.model, terms)}`));
const write = (name: string, lines: string[]) => writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
write('summary.txt', summary); write('diagnostics.csv', diagnosticsLines); write('selection.txt', selection); write('predictions.csv', predictionLines);
write('residual_plot.txt', plotBlocks.flatMap((block, i) => i ? ['', ...block] : block));
