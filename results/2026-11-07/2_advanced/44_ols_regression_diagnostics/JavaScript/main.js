'use strict';

const fs = require('node:fs');
const { readInput } = require('./dataframe');
const { parseFormula, contained, formatFormula, modelRows, columnValues, design, predictable } = require('./formula');
const { fit } = require('./qr_solver');
const { diagnose } = require('./diagnostics');
const { tP, fP, tQuantile, mark, fixed, pValue } = require('./inference');
const sum = values => values.reduce((total, value) => total + value, 0);

function modelStatistics(fitting, parameters, inference = true) {
    const { n, rank, weights, response, rss, leverage, weightedResiduals } = fitting;
    const df = n - rank;
    const sigma = Math.sqrt(rss / df);
    const weightSum = sum(weights);
    const mean = sum(response.map((value, i) => weights[i] * value)) / weightSum;
    const tss = sum(response.map((value, i) => weights[i] * (value - mean) * (value - mean)));
    const r2 = 1 - rss / tss;
    const adjusted = 1 - (1 - r2) * (n - 1) / df;
    const f = rank > 1 ? ((tss - rss) / (rank - 1)) / (rss / df) : null;
    const loglik = 0.5 * (sum(weights.map(Math.log)) - n * (Math.log(2 * Math.PI) + 1 - Math.log(n) + Math.log(rss)));
    const aic = -2 * loglik + 2 * (rank + 1);
    const bic = -2 * loglik + Math.log(n) * (rank + 1);
    const press = sum(weightedResiduals.map((value, i) => (value / (1 - leverage[i])) * (value / (1 - leverage[i]))));
    const predicted = 1 - press / tss;
    const ordered = weightedResiduals.slice().sort((a, b) => a - b);
    const quantiles = [0, 0.25, 0.5, 0.75, 1].map(proportion => {
        const position = (n - 1) * proportion;
        const lower = Math.floor(position);
        return lower + 1 < n ? ordered[lower] + (position - lower) * (ordered[lower + 1] - ordered[lower]) : ordered[lower];
    });
    return { df, sigma, weightSum, mean, tss, r2, adjusted, f, fP: inference && rank > 1 ? fP(f, rank - 1, df) : null,
        loglik, aic, bic, press, predicted, quantiles, critical: inference ? tQuantile(parameters.CONFIDENCE, df) : null };
}

function fitTerms(model, terms, parameters, inference = false) {
    const built = design(model, model.rows, model.levels, terms);
    const fitting = fit(built.matrix, built.response, built.weights, parameters.RANK_TOL);
    return { terms, columns: built.columns, fitting, statistics: modelStatistics(fitting, parameters, inference) };
}

function coefficientInference(model) {
    const { fitting, statistics } = model;
    const coefficients = Array(fitting.p).fill(null);
    fitting.accepted.forEach((column, k) => {
        const estimate = fitting.coefficients[column];
        const se = statistics.sigma * Math.sqrt(fitting.variance[k]);
        const t = estimate / se;
        let robustVariance = 0;
        for (let i = 0; i < fitting.n; i++) {
            const epsilon = fitting.weightedResiduals[i];
            const remainder = 1 - fitting.leverage[i];
            const omega = epsilon * epsilon / (remainder * remainder);
            robustVariance += omega * fitting.g[i][k] * fitting.g[i][k];
        }
        const robustSe = Math.sqrt(robustVariance);
        const robustT = estimate / robustSe;
        coefficients[column] = { estimate, se, t, p: tP(t, statistics.df),
            lower: estimate - statistics.critical * se, upper: estimate + statistics.critical * se,
            robustSe, robustT, robustP: tP(robustT, statistics.df) };
    });
    return coefficients;
}

function sequentialTests(model) {
    const { fitting, statistics, columns } = model;
    const tests = [];
    for (const term of model.terms) {
        const indices = fitting.accepted.map((column, k) => columns[column].term === term ? k : -1).filter(k => k >= 0);
        if (indices.length === 0) continue;
        const ss = sum(indices.map(k => fitting.effects[k] * fitting.effects[k]));
        const mean = ss / indices.length;
        const f = mean / (fitting.rss / statistics.df);
        tests.push({ term, df: indices.length, ss, mean, f, p: fP(f, indices.length, statistics.df) });
    }
    return tests;
}

function marginalTests(model, current, getFit) {
    const tests = [];
    for (const term of current.terms) {
        if (current.terms.some(other => contained(term, other))) continue;
        const reduced = getFit(current.terms.filter(other => other !== term));
        const df = current.fitting.rank - reduced.fitting.rank;
        const ss = reduced.fitting.rss - current.fitting.rss;
        const f = df > 0 ? (ss / df) / (current.fitting.rss / current.statistics.df) : null;
        tests.push({ term, df, ss, rss: reduced.fitting.rss, f, p: df > 0 ? fP(f, df, current.statistics.df) : null });
    }
    return tests;
}

function varianceInflation(model, parameters) {
    const { fitting, statistics } = model;
    const rows = [];
    for (let k = 1; k < fitting.rank; k++) {
        const column = fitting.accepted[k];
        const response = fitting.matrix.map(row => row[column]);
        const matrix = fitting.matrix.map(row => fitting.accepted.filter(j => j !== column).map(j => row[j]));
        const auxiliary = fit(matrix, response, fitting.weights, parameters.RANK_TOL);
        const mean = sum(response.map((value, i) => fitting.weights[i] * value)) / statistics.weightSum;
        const tss = sum(response.map((value, i) => fitting.weights[i] * (value - mean) * (value - mean)));
        const r2 = 1 - auxiliary.rss / tss;
        const value = 1 / (1 - r2);
        rows.push({ column, value, high: value > parameters.VIF });
    }
    return rows;
}

function diagnosticSummary(model, parameters) {
    const { fitting, statistics } = model;
    const diagnostics = diagnose(fitting, statistics, parameters);
    const expanded = fitting.matrix.map((row, i) => [...fitting.accepted.map(j => row[j]),
        fitting.fitted[i] * fitting.fitted[i], fitting.fitted[i] * fitting.fitted[i] * fitting.fitted[i]]);
    const auxiliary = fit(expanded, fitting.response, fitting.weights, parameters.RANK_TOL);
    const added = auxiliary.rank - fitting.rank;
    const df = fitting.n - auxiliary.rank;
    const f = ((fitting.rss - auxiliary.rss) / added) / (auxiliary.rss / df);
    const reset = { f, added, df, p: fP(f, added, df) };
    let outlier = 0;
    for (let i = 1; i < fitting.n; i++) if (Math.abs(diagnostics.rows[i].studentized) > Math.abs(diagnostics.rows[outlier].studentized)) outlier = i;
    const outlierP = tP(diagnostics.rows[outlier].studentized, statistics.df - 1);
    const cooks = diagnostics.rows.map((_, i) => i).sort((a, b) => diagnostics.rows[b].cooks - diagnostics.rows[a].cooks || a - b).slice(0, 3);
    const dfbetas = fitting.accepted.map((column, k) => {
        let largest = 0;
        for (let i = 1; i < fitting.n; i++) if (Math.abs(diagnostics.rows[i].dfbetas[k]) > Math.abs(diagnostics.rows[largest].dfbetas[k])) largest = i;
        return { column, row: largest, value: diagnostics.rows[largest].dfbetas[k] };
    });
    const dwLabel = diagnostics.dw < parameters.DURBIN_WATSON ? 'positive autocorrelation'
        : diagnostics.dw > 4 - parameters.DURBIN_WATSON ? 'negative autocorrelation' : 'no autocorrelation';
    return { ...diagnostics, reset, outlier, outlierP, bonferroni: Math.min(1, fitting.n * outlierP), cooks, dfbetas, dwLabel,
        bpLabel: diagnostics.bp.p < parameters.BREUSCH_PAGAN ? 'heteroscedastic' : 'homoscedastic',
        jbLabel: diagnostics.jb.p < parameters.NORMALITY ? 'non-normal' : 'normal' };
}

function makePredictions(model, predictions) {
    const { fitting, statistics } = model;
    return predictions.rows.map(row => {
        if (!predictable(model, model.levels, row)) return { row: row.number, predictable: false };
        const values = columnValues(model.columns, row);
        let prediction = 0;
        for (const column of fitting.accepted) prediction += values[column] * fitting.coefficients[column];
        let squares = 0;
        for (let k = 0; k < fitting.rank; k++) {
            let total = 0;
            for (let m = 0; m < fitting.rank; m++) total += values[fitting.accepted[m]] * fitting.inverse[m][k];
            squares += total * total;
        }
        const se = statistics.sigma * Math.sqrt(squares);
        const confidence = statistics.critical * se;
        const predictionHalf = statistics.critical * Math.sqrt(statistics.sigma * statistics.sigma + se * se);
        const actual = row.values[model.response] ?? null;
        return { row: row.number, predictable: true, prediction, se, confLower: prediction - confidence, confUpper: prediction + confidence,
            predLower: prediction - predictionHalf, predUpper: prediction + predictionHalf, actual,
            error: actual === null ? null : actual - prediction,
            covered: actual === null ? null : prediction - predictionHalf <= actual && actual <= prediction + predictionHalf };
    });
}

function prepareModel(text, number, data, predictions, parameters) {
    const model = parseFormula(text, number);
    Object.assign(model, modelRows(model, data));
    Object.assign(model, fitTerms(model, model.terms, parameters, true));
    model.coefficients = coefficientInference(model);
    model.sequential = sequentialTests(model);
    model.marginal = marginalTests(model, model, terms => fitTerms(model, terms, parameters));
    model.vif = varianceInflation(model, parameters);
    model.diagnostics = diagnosticSummary(model, parameters);
    model.predictions = makePredictions(model, predictions);
    const predicted = model.predictions.filter(row => row.predictable);
    const checked = predicted.filter(row => row.error !== null);
    model.predictionCheck = { predicted: predicted.length, checked: checked.length,
        rmse: checked.length ? Math.sqrt(sum(checked.map(row => row.error * row.error)) / checked.length) : null,
        covered: checked.filter(row => row.covered).length };
    return model;
}

function selectionLines(model, parameters) {
    const original = model.terms;
    const cache = new Map();
    const getFit = terms => {
        const mask = terms.reduce((mask, term) => mask + 2 ** original.indexOf(term), 0);
        if (!cache.has(mask)) cache.set(mask, fitTerms(model, terms, parameters));
        return cache.get(mask);
    };
    let terms = original.slice();
    const lines = [`Backward elimination (model 1, alpha ${fixed(parameters.ALPHA_REMOVE)}, rows ${model.rows.length})`];
    for (let step = 1; ; step++) {
        const current = getFit(terms);
        lines.push(`Step ${step}: ${formatFormula(model, terms)} (RSS ${fixed(current.fitting.rss)}, df ${current.statistics.df}, AIC ${fixed(current.statistics.aic)})`);
        if (terms.length === 0) { lines.push('  stop: no removable terms'); break; }
        const tests = marginalTests(model, current, getFit);
        let largest = tests[0];
        for (const test of tests) {
            lines.push(`  - ${test.term.name}: F ${fixed(test.f)} on ${test.df} and ${current.statistics.df} DF, p-value ${pValue(test.p)}`);
            if (test.p > largest.p) largest = test;
        }
        if (largest.p > parameters.ALPHA_REMOVE) {
            lines.push('  remove ' + largest.term.name);
            terms = terms.filter(term => term !== largest.term);
        } else {
            lines.push(`  stop: largest p-value ${pValue(largest.p)} is not above ${fixed(parameters.ALPHA_REMOVE)}`);
            break;
        }
    }
    lines.push('Final model: ' + formatFormula(model, terms), '', `Forward selection by AIC (model 1, rows ${model.rows.length})`);
    terms = [];
    for (let step = 1; ; step++) {
        const current = getFit(terms);
        lines.push(`Step ${step}: ${formatFormula(model, terms)} (AIC ${fixed(current.statistics.aic)})`);
        const candidates = original.filter(term => !terms.includes(term) && original.every(other => !contained(other, term) || terms.includes(other)));
        if (candidates.length === 0) { lines.push('  stop: no candidate terms remain'); break; }
        let best = null;
        for (const candidate of candidates) {
            const expanded = original.filter(term => terms.includes(term) || term === candidate);
            const fitting = getFit(expanded);
            lines.push(`  + ${candidate.name}: AIC ${fixed(fitting.statistics.aic)}`);
            if (best === null || fitting.statistics.aic < best.fitting.statistics.aic) best = { candidate, terms: expanded, fitting };
        }
        if (best.fitting.statistics.aic < current.statistics.aic) { lines.push('  add ' + best.candidate.name); terms = best.terms; }
        else { lines.push('  stop: no candidate lowers the AIC'); break; }
    }
    lines.push('Final model: ' + formatFormula(model, terms), '');
    const subsets = [];
    for (let mask = 0; mask < 2 ** original.length; mask++) {
        const selected = original.filter((_, index) => (mask & 2 ** index) !== 0);
        if (!selected.every(term => original.every(other => !contained(other, term) || selected.includes(other)))) continue;
        subsets.push({ mask, terms: selected, result: getFit(selected) });
    }
    subsets.sort((a, b) => a.result.statistics.bic - b.result.statistics.bic || a.mask - b.mask);
    lines.push(`Best subsets by BIC (model 1, rows ${model.rows.length}, subsets ${subsets.length})`);
    subsets.slice(0, parameters.BEST_SUBSETS).forEach((subset, index) => lines.push(
        `${index + 1}. BIC ${fixed(subset.result.statistics.bic)}, AIC ${fixed(subset.result.statistics.aic)}, rank ${subset.result.fitting.rank}: ${formatFormula(model, subset.terms)}`));
    return lines;
}

function table(header, rows) {
    const entries = [{ fields: header }, ...rows.map(row => Array.isArray(row) ? { fields: row } : row)];
    const widths = header.map((_, column) => Math.max(...entries.map(row => column < row.fields.length ? String(row.fields[column]).length : 0)));
    return entries.map(row => {
        const fields = row.fields.map(String);
        let line = fields[0].padEnd(widths[0]);
        for (let column = 1; column < fields.length; column++) line += '  ' + fields[column].padStart(widths[column]);
        if (row.mark) line += ' ' + row.mark;
        return line.trimEnd();
    });
}

function dataSummary(data) {
    const numeric = data.columns.filter(column => !column.categorical);
    const categorical = data.columns.filter(column => column.categorical);
    const numericRows = numeric.map(column => {
        const values = data.rows.map(row => row.values[column.name]).filter(value => value !== null);
        const mean = sum(values) / values.length;
        const deviation = Math.sqrt(sum(values.map(value => (value - mean) * (value - mean))) / (values.length - 1));
        return [column.name, values.length, data.rows.length - values.length, fixed(mean), fixed(deviation), fixed(Math.min(...values)), fixed(Math.max(...values))];
    });
    const lines = [`Data: ${data.rows.length} rows, ${data.columns.length} columns`, '', 'Numeric columns:',
        ...table(['column', 'n', 'missing', 'Mean', 'SD', 'Min', 'Max'], numericRows), '', 'Categorical columns:'];
    for (const column of categorical) {
        const counts = new Map();
        let present = 0;
        for (const row of data.rows) {
            const value = row.values[column.name];
            if (value === null) continue;
            present++;
            counts.set(value, (counts.get(value) || 0) + 1);
        }
        const labels = [...counts.keys()].sort();
        lines.push(`${column.name}: ${present} values, ${data.rows.length - present} missing, ${labels.length} levels: `
            + labels.map(label => label + ' ' + counts.get(label)).join(', '));
    }
    const correlations = numeric.map(a => [a.name, ...numeric.map(b => {
        const pairs = data.rows.filter(row => row.values[a.name] !== null && row.values[b.name] !== null);
        const meanA = sum(pairs.map(row => row.values[a.name])) / pairs.length;
        const meanB = sum(pairs.map(row => row.values[b.name])) / pairs.length;
        let xy = 0, xx = 0, yy = 0;
        for (const row of pairs) {
            const x = row.values[a.name] - meanA;
            const y = row.values[b.name] - meanB;
            xy += x * y;
            xx += x * x;
            yy += y * y;
        }
        return fixed(xy / Math.sqrt(xx * yy));
    })]);
    lines.push('', 'Correlations (pairwise complete observations):', ...table(['column', ...numeric.map(column => column.name)], correlations), '');
    return lines;
}

function modelSummary(model, totalRows, parameters) {
    const { fitting, statistics, diagnostics, columns } = model;
    const aliases = columns.filter((_, j) => fitting.coefficients[j] === null).map(column => column.name);
    const quantiles = statistics.quantiles.map(fixed);
    const coefficientRows = columns.map((column, j) => {
        const coefficient = model.coefficients[j];
        return coefficient ? { fields: [column.name, fixed(coefficient.estimate), fixed(coefficient.se), fixed(coefficient.t), pValue(coefficient.p)], mark: mark(coefficient.p) }
            : [column.name, 'NA', 'NA', 'NA', 'NA'];
    });
    const confidenceRows = columns.map((column, j) => {
        const coefficient = model.coefficients[j];
        return [column.name, fixed(coefficient ? coefficient.lower : null), fixed(coefficient ? coefficient.upper : null)];
    });
    const robustRows = columns.map((column, j) => {
        const coefficient = model.coefficients[j];
        return coefficient ? { fields: [column.name, fixed(coefficient.robustSe), fixed(coefficient.robustT), pValue(coefficient.robustP)], mark: mark(coefficient.robustP) }
            : [column.name, 'NA', 'NA', 'NA'];
    });
    const sequentialRows = model.sequential.map(test => ({ fields: [test.term.name, test.df, fixed(test.ss), fixed(test.mean), fixed(test.f), pValue(test.p)], mark: mark(test.p) }));
    sequentialRows.push({ fields: ['Residuals', statistics.df, fixed(fitting.rss), fixed(fitting.rss / statistics.df)] });
    const marginalRows = model.marginal.map(test => ({ fields: [test.term.name, test.df, fixed(test.ss), fixed(test.rss), fixed(test.f), pValue(test.p)], mark: mark(test.p) }));
    const vifRows = model.vif.map(row => ({ fields: [columns[row.column].name, fixed(row.value)], mark: row.high ? 'high' : '' }));
    const lines = [
        `Model ${model.number}: ${model.original}`,
        'Terms: ' + model.terms.map(term => term.name).join(', '),
        'Weights: ' + (model.weight || 'none'),
        `Observations: ${fitting.n} used, ${totalRows - fitting.n} dropped`,
        `Columns: ${fitting.p}, rank ${fitting.rank}, aliased: ${aliases.length ? aliases.join(', ') : 'none'}`,
        '',
        `Residuals: Min ${quantiles[0]}, 1Q ${quantiles[1]}, Median ${quantiles[2]}, 3Q ${quantiles[3]}, Max ${quantiles[4]}`,
        '', 'Coefficients:', ...table(['term', 'Estimate', 'Std. Error', 't value', 'Pr(>|t|)'], coefficientRows),
        '---', "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", '',
        `Residual standard error: ${fixed(statistics.sigma)} on ${statistics.df} degrees of freedom`,
        `Multiple R-squared: ${fixed(statistics.r2)}, Adjusted R-squared: ${fixed(statistics.adjusted)}`,
        `F-statistic: ${fixed(statistics.f)} on ${fitting.rank - 1} and ${statistics.df} DF, p-value: ${pValue(statistics.fP)}`,
        `Log-likelihood: ${fixed(statistics.loglik)}, AIC: ${fixed(statistics.aic)}, BIC: ${fixed(statistics.bic)}`,
        `PRESS: ${fixed(statistics.press)}, Predicted R-squared: ${fixed(statistics.predicted)}`, '',
        `Confidence intervals (level ${fixed(parameters.CONFIDENCE)}, t ${fixed(statistics.critical)}):`,
        ...table(['term', 'Lower', 'Upper'], confidenceRows), '', 'Robust standard errors (HC3):',
        ...table(['term', 'Std. Error', 't value', 'Pr(>|t|)'], robustRows), '', 'Analysis of variance (sequential):',
        ...table(['term', 'Df', 'Sum Sq', 'Mean Sq', 'F value', 'Pr(>F)'], sequentialRows), '', 'Marginal F tests (drop one term):',
        ...table(['term', 'Df', 'Sum Sq', 'RSS', 'F value', 'Pr(>F)'], marginalRows), '', 'Variance inflation factors:',
        ...table(['column', 'VIF'], vifRows), '', 'Diagnostics:',
        `Durbin-Watson: ${fixed(diagnostics.dw)} (${diagnostics.dwLabel})`,
        `Breusch-Pagan: ${fixed(diagnostics.bp.value)} on ${diagnostics.bp.df} DF, p-value: ${pValue(diagnostics.bp.p)} (${diagnostics.bpLabel})`,
        `Jarque-Bera: ${fixed(diagnostics.jb.value)} on 2 DF, p-value: ${pValue(diagnostics.jb.p)}, skewness ${fixed(diagnostics.jb.skewness)}, kurtosis ${fixed(diagnostics.jb.kurtosis)} (${diagnostics.jbLabel})`,
        `RESET (powers 2 and 3): F ${fixed(diagnostics.reset.f)} on ${diagnostics.reset.added} and ${diagnostics.reset.df} DF, p-value: ${pValue(diagnostics.reset.p)}`,
        `Outlier test: row ${model.rows[diagnostics.outlier].number}, studentized ${fixed(diagnostics.rows[diagnostics.outlier].studentized)}, unadjusted p-value: ${pValue(diagnostics.outlierP)}, Bonferroni p-value: ${pValue(diagnostics.bonferroni)}`
    ];
    const flags = letter => diagnostics.rows.filter(row => row.flags.includes(letter)).length;
    lines.push(`Flagged rows: leverage ${flags('H')}, outlier ${flags('O')}, cooks ${flags('C')}, dffits ${flags('F')}, any ${diagnostics.rows.filter(row => row.flags !== '-').length}`,
        "Largest Cook's distances:");
    for (const i of diagnostics.cooks) {
        const row = diagnostics.rows[i];
        lines.push(`row ${model.rows[i].number}: cooks_d ${fixed(row.cooks)}, leverage ${fixed(fitting.leverage[i])}, studentized ${fixed(row.studentized)}, flags ${row.flags}`);
    }
    lines.push('Largest absolute DFBETAS:', ...table(['column', 'row', 'DFBETAS'], diagnostics.dfbetas.map(row =>
        [columns[row.column].name, model.rows[row.row].number, fixed(row.value)])));
    return lines;
}

function summaryLines(data, models, parameters) {
    const lines = dataSummary(data);
    models.forEach((model, index) => {
        if (index > 0) lines.push('');
        lines.push(...modelSummary(model, data.rows.length, parameters));
    });
    lines.push('', 'Model comparison:', ...table(['model', 'n', 'rank', 'sigma', 'R-squared', 'Adj. R-squared', 'Pred. R-squared', 'AIC', 'BIC'],
        models.map(model => [model.number, model.fitting.n, model.fitting.rank, fixed(model.statistics.sigma), fixed(model.statistics.r2),
            fixed(model.statistics.adjusted), fixed(model.statistics.predicted), fixed(model.statistics.aic), fixed(model.statistics.bic)])), '', 'Prediction check:');
    for (const model of models) {
        const check = model.predictionCheck;
        lines.push(`model ${model.number}: ${check.predicted} predicted, ${check.checked} with actual values, RMSE ${fixed(check.rmse)}, inside prediction interval ${check.covered}`);
    }
    return lines;
}

function diagnosticsLines(models) {
    const lines = ['model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags'];
    for (const model of models) model.rows.forEach((row, i) => {
        const { fitting } = model;
        const diagnostic = model.diagnostics.rows[i];
        lines.push([model.number, row.number, fixed(fitting.fitted[i]), fixed(fitting.residuals[i]), fixed(fitting.leverage[i]),
            fixed(diagnostic.studentized), fixed(diagnostic.cooks), fixed(diagnostic.dffits), diagnostic.flags].join(','));
    });
    return lines;
}

function predictionsLines(models) {
    const lines = ['model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered'];
    for (const model of models) for (const row of model.predictions) {
        const values = row.predictable ? [fixed(row.prediction), fixed(row.se), fixed(row.confLower), fixed(row.confUpper),
            fixed(row.predLower), fixed(row.predUpper), fixed(row.actual), fixed(row.error), row.covered === null ? 'NA' : row.covered ? 'yes' : 'no'] : Array(9).fill('NA');
        lines.push([model.number, row.row, ...values].join(','));
    }
    return lines;
}

function plotGrid(values, studentized, low, high, width, height, limit) {
    const counts = Array.from({ length: height }, () => Array(width).fill(0));
    values.forEach((value, i) => {
        const column = Math.min(Math.floor((value - low) / (high - low) * width), width - 1);
        const row = Math.max(0, Math.min(Math.floor((limit - studentized[i]) / (2 * limit) * height), height - 1));
        counts[row][column]++;
    });
    const border = '+' + '-'.repeat(width) + '+';
    const middle = Math.floor(height / 2);
    const frame = [border, ...counts.map((row, i) => '|' + row.map(count => count >= 10 ? '*' : count > 0 ? String(count) : i === middle ? '-' : '.').join('') + '|'), border];
    return { counts, frame };
}

function plotLines(models, parameters) {
    const [width, height, limit] = parameters.PLOT;
    const lines = [];
    models.forEach((model, index) => {
        if (index > 0) lines.push('');
        const { fitting } = model;
        const studentized = model.diagnostics.rows.map(row => row.studentized);
        const low = Math.min(...fitting.fitted), high = Math.max(...fitting.fitted);
        const residual = plotGrid(fitting.fitted, studentized, low, high, width, height, limit);
        lines.push(`Model ${model.number}: studentized residuals vs fitted values`,
            `fitted ${fixed(low)} to ${fixed(high)}, studentized ${fixed(-limit)} to ${fixed(limit)}`, ...residual.frame,
            `points: ${fitting.n}, above +2: ${studentized.filter(value => value > 2).length}, below -2: ${studentized.filter(value => value < -2).length}, outside range: ${studentized.filter(value => Math.abs(value) > limit).length}`,
            'Histogram of studentized residuals:');
        const totals = residual.counts.map(sum);
        const maximum = Math.max(...totals);
        totals.forEach((count, row) => {
            const lower = limit - 2 * limit * (row + 1) / height;
            const upper = limit - 2 * limit * row / height;
            const bar = Math.floor((40 * count + maximum - 1) / maximum);
            lines.push(`${fixed(lower)} to ${fixed(upper)}: ${count}` + (bar > 0 ? ' ' + '#'.repeat(bar) : ''));
        });
        const maxLeverage = Math.max(...fitting.leverage);
        const leverage = plotGrid(fitting.leverage, studentized, 0, maxLeverage, width, height, limit);
        lines.push(`Model ${model.number}: studentized residuals vs leverage`,
            `leverage 0.0000 to ${fixed(maxLeverage)}, studentized ${fixed(-limit)} to ${fixed(limit)}`, ...leverage.frame);
    });
    return lines;
}

function main() {
    const { data, predictions, models: formulas, parameters } = readInput();
    const models = formulas.map((formula, index) => prepareModel(formula, index + 1, data, predictions, parameters));
    const outputs = [
        ['summary.txt', summaryLines(data, models, parameters)],
        ['diagnostics.csv', diagnosticsLines(models)],
        ['selection.txt', selectionLines(models[0], parameters)],
        ['predictions.csv', predictionsLines(models)],
        ['residual_plot.txt', plotLines(models, parameters)]
    ];
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of outputs) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
