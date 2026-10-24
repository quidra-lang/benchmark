'use strict';

const fs = require('node:fs');
const { readInput } = require('./dataset');
const kernels = require('./kernels');
const loess = require('./loess');
const spline = require('./spline');
const selection = require('./selection');

function sum(values) {
    let total = 0;
    for (const value of values) total += value;
    return total;
}

function squares(values) {
    let total = 0;
    for (const value of values) total += value * value;
    return total;
}

function residualSum(points, fitted) {
    let total = 0;
    for (let i = 0; i < points.length; i++) {
        const error = points[i].y - fitted[i];
        total += error * error;
    }
    return total;
}

function real(value) {
    if (value === null) return 'NA';
    const magnitude = Math.abs(value);
    if (magnitude >= 1e21) return (value < 0 ? '-' : '') + BigInt(magnitude).toString() + '.0000';
    const text = value.toFixed(4);
    return text === '-0.0000' ? '0.0000' : text;
}

function hundredths(value) {
    const magnitude = Math.abs(value);
    return (value < 0 ? '-' : '') + Math.floor(magnitude / 100) + '.' + String(magnitude % 100).padStart(2, '0');
}

function methodList(settings) {
    const methods = [
        { name: 'linear', kind: 'linear' },
        { name: 'running_mean', kind: 'mean', candidates: settings.windows },
        { name: 'running_median', kind: 'median', candidates: settings.windows }
    ];
    for (const kind of ['nw', 'll']) {
        for (const kernel of settings.kernels) methods.push({ name: kind + '_' + kernel, kind, kernel, candidates: settings.bandwidths });
    }
    for (const degree of settings.degrees) methods.push({ name: 'loess' + degree, kind: 'loess', degree, candidates: settings.spans });
    methods.push({ name: 'spline', kind: 'spline', candidates: settings.lambdas });
    methods.push({ name: 'isotonic', kind: 'isotonic' });
    return methods;
}

function fitLinear(points) {
    const n = points.length;
    const xbar = sum(points.map(point => point.x)) / n;
    const ybar = sum(points.map(point => point.y)) / n;
    let sxx = 0;
    let sxy = 0;
    for (const point of points) {
        const dx = point.x - xbar;
        sxx += dx * dx;
        sxy += dx * (point.y - ybar);
    }
    const b = sxy / sxx;
    const a = ybar - b * xbar;
    return {
        yhat: points.map(point => a + b * point.x), edf: 2,
        lev: points.map(point => 1 / n + (point.x - xbar) * (point.x - xbar) / sxx),
        at: position => ({ value: a + b * (position / 100),
            weights: points.map(point => 1 / n + (position / 100 - xbar) * (point.x - xbar) / sxx) })
    };
}

function nearestPoint(points, position) {
    let nearest = 0;
    for (let i = 1; i < points.length; i++) {
        if (Math.abs(points[i].X - position) < Math.abs(points[nearest].X - position)) nearest = i;
    }
    return nearest;
}

function fitRunning(points, width, median) {
    const radii = points.map((_, i) => Math.min((width - 1) / 2, i, points.length - 1 - i));
    const yhat = radii.map((radius, i) => {
        const values = points.slice(i - radius, i + radius + 1).map(point => point.Y);
        if (median) return values.sort((a, b) => a - b)[radius] / 100;
        return sum(values) / (100 * (2 * radius + 1));
    });
    const lev = median ? null : radii.map(radius => 1 / (2 * radius + 1));
    return { yhat, lev, edf: median ? null : sum(lev), at: position => {
        const center = nearestPoint(points, position);
        let weights = null;
        if (!median) {
            weights = points.map(() => 0);
            for (let j = center - radii[center]; j <= center + radii[center]; j++) weights[j] = 1 / (2 * radii[center] + 1);
        }
        return { value: yhat[center], weights };
    } };
}

function fitIsotonic(points, direction) {
    const blocks = [];
    for (let i = 0; i < points.length; i++) {
        blocks.push({ first: i, last: i, total: points[i].Y, count: 1 });
        while (blocks.length >= 2) {
            const left = blocks[blocks.length - 2];
            const right = blocks[blocks.length - 1];
            const a = left.total * right.count;
            const b = right.total * left.count;
            if (direction === 'increasing' ? a <= b : a >= b) break;
            blocks.splice(-2, 2, { first: left.first, last: right.last, total: left.total + right.total, count: left.count + right.count });
        }
    }
    const yhat = Array(points.length);
    for (const block of blocks) {
        block.value = block.total / (100 * block.count);
        for (let i = block.first; i <= block.last; i++) yhat[i] = block.value;
    }
    return { yhat, edf: blocks.length, lev: null, blocks, direction, at: position => {
        let index = 0;
        while (index + 1 < points.length && points[index + 1].X <= position) index++;
        return { value: yhat[index], weights: null };
    } };
}

function fitFull(method, candidate, points, iterations = 0) {
    if (method.kind === 'linear') return fitLinear(points);
    if (method.kind === 'mean' || method.kind === 'median') return fitRunning(points, candidate.value, method.kind === 'median');
    if (method.kind === 'nw' || method.kind === 'll') return kernels.fit(points, method.kind, method.kernel, candidate.hundredths);
    if (method.kind === 'loess') return loess.fit(points, method.degree, candidate.hundredths, iterations);
    return spline.fit(points, candidate.value);
}

function subsetEstimator(method, candidate, points, direction) {
    if (method.kind === 'nw' || method.kind === 'll') {
        return position => kernels.estimate(points, method.kind, method.kernel, candidate.hundredths, position).value;
    }
    if (method.kind === 'loess') {
        const robustness = points.map(() => 1);
        return position => loess.localFit(points, method.degree, candidate.hundredths, robustness, position).value;
    }
    let fit;
    if (method.kind === 'spline') fit = spline.fit(points, candidate.value, false);
    else if (method.kind === 'isotonic') fit = fitIsotonic(points, direction);
    else fit = fitFull(method, candidate, points);
    return position => fit.at(position).value;
}

function leaveOneOut(method, candidate, points, direction) {
    const predictions = [];
    for (let i = 0; i < points.length; i++) {
        const subset = points.filter((_, j) => j !== i);
        predictions.push(subsetEstimator(method, candidate, subset, direction)(points[i].X));
    }
    return selection.crossValidation(points.map(point => point.y), predictions);
}

function kfold(method, candidate, points, direction, groups) {
    const predictions = Array(points.length);
    for (let group = 0; group < groups; group++) {
        const subset = points.filter((_, i) => i % groups !== group);
        const estimate = subsetEstimator(method, candidate, subset, direction);
        for (let i = group; i < points.length; i += groups) predictions[i] = estimate(points[i].X);
    }
    return selection.crossValidation(points.map(point => point.y), predictions);
}

function fitMethods(series, settings, methods) {
    const points = series.points;
    const models = [];
    for (const method of methods) {
        let fit;
        let chosen = null;
        let selected = -1;
        let parameter = '-';
        let candidates = [];
        let loo;
        let increasingRSS = null;
        let decreasingRSS = null;
        if (method.kind === 'linear') {
            fit = fitLinear(points);
            loo = leaveOneOut(method, null, points);
        } else if (method.kind === 'isotonic') {
            if (series.mode === 'auto') {
                const increasing = fitIsotonic(points, 'increasing');
                const decreasing = fitIsotonic(points, 'decreasing');
                increasingRSS = residualSum(points, increasing.yhat);
                decreasingRSS = residualSum(points, decreasing.yhat);
                fit = increasingRSS <= decreasingRSS ? increasing : decreasing;
            } else fit = fitIsotonic(points, series.mode);
            parameter = fit.direction;
            loo = leaveOneOut(method, null, points, fit.direction);
        } else {
            const evaluated = method.candidates.map(candidate => {
                const candidateFit = fitFull(method, candidate, points);
                const score = method.kind === 'spline'
                    ? selection.generalized(points.map(point => point.y), candidateFit.yhat, candidateFit.edf)
                    : leaveOneOut(method, candidate, points);
                return { candidate, fit: candidateFit, score, edf: candidateFit.edf };
            });
            selected = selection.choose(evaluated);
            const winner = evaluated[selected];
            chosen = winner.candidate;
            parameter = chosen.text;
            fit = method.kind === 'loess' && settings.robustIterations > 0
                ? fitFull(method, chosen, points, settings.robustIterations) : winner.fit;
            loo = method.kind === 'spline' ? leaveOneOut(method, chosen, points) : winner.score;
            candidates = evaluated.map(item => ({ parameter: item.candidate.text, score: item.score, edf: item.edf }));
        }
        models.push({ ...fit, method, name: method.name, order: models.length, chosen, parameter,
            selected, candidates, loo, increasingRSS, decreasingRSS,
            kfold: kfold(method, chosen, points, fit.direction, settings.folds) });
    }
    return models;
}

function turningCount(estimates) {
    const values = estimates.map(item => item.value).filter(value => value !== null);
    let previousSign = 0;
    let count = 0;
    for (let i = 1; i < values.length; i++) {
        const delta = values[i] - values[i - 1];
        if (delta === 0) continue;
        const sign = delta > 0 ? 1 : -1;
        if (previousSign !== 0 && sign !== previousSign) count++;
        previousSign = sign;
    }
    return count;
}

function diagnostics(points, model, linearRSS) {
    const n = points.length;
    const errors = points.map((point, i) => point.y - model.yhat[i]);
    const rss = squares(errors);
    const ybar = sum(points.map(point => point.y)) / n;
    const tss = squares(points.map(point => point.y - ybar));
    const df = model.edf === null ? null : n - model.edf;
    const rse = df === null ? null : Math.sqrt(rss / df);
    const nonlinear = model.name !== 'linear' && model.edf !== null && model.edf > 2
        ? ((linearRSS - rss) / (model.edf - 2)) / (rss / df) : null;
    const meanError = sum(errors) / n;
    const centered = errors.map(value => value - meanError);
    const denominator = squares(centered);
    const acf = [];
    for (let lag = 1; lag <= 5; lag++) {
        let numerator = 0;
        for (let i = 0; i < n - lag; i++) numerator += centered[i] * centered[i + lag];
        acf.push(numerator / denominator);
    }
    let successive = 0;
    let positive = 0;
    let negative = 0;
    let runs = 0;
    let previousSign = 0;
    let largest = 0;
    for (let i = 0; i < n; i++) {
        if (i > 0) { const delta = errors[i] - errors[i - 1]; successive += delta * delta; }
        if (Math.abs(errors[i]) > Math.abs(errors[largest])) largest = i;
        if (errors[i] === 0) continue;
        const sign = errors[i] > 0 ? 1 : -1;
        if (sign > 0) positive++; else negative++;
        if (sign !== previousSign) runs++;
        previousSign = sign;
    }
    const nonzero = positive + negative;
    const pairs = 2 * positive * negative;
    const mu = 1 + pairs / nonzero;
    const variance = pairs * (pairs - nonzero) / (nonzero * nonzero * (nonzero - 1));
    const sorted = errors.slice().sort((a, b) => a - b);
    const quantiles = [];
    for (let k = 0; k <= 4; k++) {
        const j = Math.floor((n - 1) * k / 4);
        const remainder = (n - 1) * k - 4 * j;
        quantiles.push(remainder === 0 ? sorted[j] : sorted[j] + remainder / 4 * (sorted[j + 1] - sorted[j]));
    }
    return { errors, rss, df, rse, r2: 1 - rss / tss, nonlinear, acf, dw: successive / rss,
        positive, negative, runs, runsZ: (runs - mu) / Math.sqrt(variance), largest, quantiles, turning: turningCount(model.grid) };
}

function compareFits(models, grid, settings) {
    const ranking = models.slice().sort((a, b) => a.loo - b.loo || a.order - b.order);
    const best = ranking[0];
    const agreements = [];
    for (const model of models) {
        if (model === best) continue;
        let count = 0;
        let total = 0;
        let maximum = null;
        let position;
        for (let k = 0; k < grid.length; k++) {
            if (model.grid[k].value === null || best.grid[k].value === null) continue;
            const delta = Math.abs(model.grid[k].value - best.grid[k].value);
            count++;
            total += delta * delta;
            if (maximum === null || delta > maximum) { maximum = delta; position = grid[k]; }
        }
        agreements.push({ name: model.name, count, rms: Math.sqrt(total / count), maximum, position });
    }
    const splineModel = models.find(model => model.name === 'spline');
    let maximum = null;
    let minimum = null;
    let maxPosition;
    let minPosition;
    for (let k = 1; k < grid.length - 1; k++) {
        const slope = (splineModel.grid[k + 1].value - splineModel.grid[k - 1].value) / ((grid[k + 1] - grid[k - 1]) / 100);
        if (maximum === null || slope > maximum) { maximum = slope; maxPosition = grid[k]; }
        if (minimum === null || slope < minimum) { minimum = slope; minPosition = grid[k]; }
    }
    const outlierMethod = ranking.find(model => model.lev !== null);
    const standardized = [];
    for (let i = 0; i < outlierMethod.lev.length; i++) {
        const lev = outlierMethod.lev[i];
        if (lev >= 1) continue;
        const t = outlierMethod.diagnostics.errors[i] / (outlierMethod.diagnostics.rse * Math.sqrt(1 - lev));
        const cook = t * t * lev / ((1 - lev) * outlierMethod.edf);
        standardized.push({ index: i, t, cook });
    }
    const outliers = standardized.filter(item => Math.abs(item.t) > settings.threshold / 100)
        .sort((a, b) => Math.abs(b.t) - Math.abs(a.t) || a.index - b.index);
    const influence = standardized.slice().sort((a, b) => b.cook - a.cook || a.index - b.index).slice(0, 3);
    return { ranking, best, agreements, slope: { maximum, minimum, maxPosition, minPosition },
        outlierMethod, standardized, outliers, influence };
}

function variabilityBands(points, models, settings) {
    return settings.bandMethods.map(name => {
        const model = models.find(item => item.name === name);
        const rse = model.diagnostics.rse;
        let total = 0;
        let count = 0;
        const values = model.grid.map(estimate => {
            if (estimate.value === null) return { fit: null, se: null, lower: null, upper: null };
            const se = rse * Math.sqrt(squares(estimate.weights));
            total += se;
            count++;
            return { fit: estimate.value, se, lower: estimate.value - settings.bandZ * se, upper: estimate.value + settings.bandZ * se };
        });
        let coverage = 0;
        for (let i = 0; i < points.length; i++) {
            const se = rse * Math.sqrt(squares(model.at(points[i].X).weights));
            if (Math.abs(model.diagnostics.errors[i]) <= settings.bandZ * Math.sqrt(rse * rse + se * se)) coverage++;
        }
        return { name, values, meanSE: total / count, coverage };
    });
}

function bootstrapIntervals(model, grid, settings, draw) {
    const residuals = model.diagnostics.errors;
    const mean = sum(residuals) / residuals.length;
    const centered = residuals.map(value => value - mean);
    const samples = grid.map(() => []);
    for (let b = 0; b < settings.bootstrap; b++) {
        const values = [];
        for (let i = 0; i < residuals.length; i++) values.push(model.yhat[i] + centered[draw() % residuals.length]);
        const fit = model.system.fit(values);
        for (let k = 0; k < grid.length; k++) samples[k].push(model.system.evaluate(fit, grid[k]));
    }
    return samples.map((values, k) => {
        const average = sum(values) / settings.bootstrap;
        const se = Math.sqrt(squares(values.map(value => value - average)) / (settings.bootstrap - 1));
        const sorted = values.slice().sort((a, b) => a - b);
        return { fit: model.grid[k].value, se, lower: sorted[settings.trim], upper: sorted[settings.bootstrap - settings.trim - 1] };
    });
}

function diagnosticsBlock(result, settings) {
    const { series, models, comparison, bands } = result;
    const { points, name } = series;
    const lines = [`series ${name} n ${points.length} x ${hundredths(points[0].X)} ${hundredths(points.at(-1).X)} y ${hundredths(result.minY)} ${hundredths(result.maxY)}`];
    for (const model of models) {
        const d = model.diagnostics;
        let heading = `method ${model.name} parameter ${model.parameter} loo ${real(model.loo)}`;
        if (model.name === 'spline') heading += ` gcv ${real(model.candidates[model.selected].score)}`;
        lines.push(heading);
        lines.push(`  rss ${real(d.rss)} edf ${real(model.edf)} df ${real(d.df)} rse ${real(d.rse)} r2 ${real(d.r2)} f_nonlinear ${real(d.nonlinear)}`);
        lines.push(`  acf ${d.acf.map(real).join(' ')} dw ${real(d.dw)}`);
        lines.push(`  runs ${d.runs} positive ${d.positive} negative ${d.negative} z ${real(d.runsZ)}`);
        lines.push(`  max_residual ${real(d.errors[d.largest])} at ${hundredths(points[d.largest].X)} turning ${d.turning}`);
        lines.push(`  quantiles ${d.quantiles.map(real).join(' ')}`);
        if (model.method.kind === 'loess') {
            for (const record of model.records) lines.push(`  robust ${record.iteration} scale ${real(record.scale)} zero_weight ${record.zeros} max_change ${real(record.change)}`);
            const zeros = points.filter((_, i) => model.robustness[i] === 0).map(point => hundredths(point.X));
            lines.push('  zero_weight_points ' + (zeros.length ? zeros.join(' ') : 'none'));
        }
    }
    lines.push('ranking');
    comparison.ranking.forEach((model, i) => lines.push(`  ${i + 1} ${model.name} ${real(model.loo)} kfold ${real(model.kfold)}`));
    lines.push('agreement with ' + comparison.best.name);
    for (const item of comparison.agreements) lines.push(`  ${item.name} points ${item.count} rms ${real(item.rms)} max ${real(item.maximum)} at ${hundredths(item.position)}`);
    const slope = comparison.slope;
    lines.push(`slope spline max ${real(slope.maximum)} at ${hundredths(slope.maxPosition)} min ${real(slope.minimum)} at ${hundredths(slope.minPosition)}`);
    const outlier = comparison.outlierMethod;
    lines.push(`outliers method ${outlier.name} threshold ${hundredths(settings.threshold)}`);
    if (comparison.outliers.length === 0) lines.push('  none');
    for (const item of comparison.outliers) {
        const point = points[item.index];
        lines.push(`  x ${hundredths(point.X)} y ${hundredths(point.Y)} fit ${real(outlier.yhat[item.index])} residual ${real(outlier.diagnostics.errors[item.index])} standardized ${real(item.t)}`);
    }
    lines.push('influence method ' + outlier.name);
    for (const item of comparison.influence) lines.push(`  x ${hundredths(points[item.index].X)} lev ${real(outlier.lev[item.index])} cook ${real(item.cook)}`);
    lines.push('bands');
    for (const band of bands) lines.push(`  ${band.name} mean_se ${real(band.meanSE)} coverage ${band.coverage} of ${points.length}`);
    return lines.join('\n');
}

function isotonicBlock(result) {
    const { series, models } = result;
    const model = models.find(item => item.name === 'isotonic');
    let heading = `series ${series.name} direction ${model.direction} mode ${series.mode}`;
    if (series.mode === 'auto') heading += ` rss_increasing ${real(model.increasingRSS)} rss_decreasing ${real(model.decreasingRSS)}`;
    const lines = [heading, `blocks ${model.blocks.length} rss ${real(model.diagnostics.rss)} loo ${real(model.loo)}`];
    model.blocks.forEach((block, i) => lines.push(`block ${i + 1} x ${hundredths(series.points[block.first].X)} ${hundredths(series.points[block.last].X)} count ${block.count} value ${real(block.value)}`));
    return lines.join('\n');
}

function frame(cells) {
    const border = '+' + '-'.repeat(cells[0].length) + '+';
    return [border, ...cells.map(row => '|' + row.join('') + '|'), border];
}

function histogram(standardized) {
    const counts = Array(14).fill(0);
    for (const { t } of standardized) {
        let bin = 0;
        if (t >= 3) bin = 13;
        else if (t >= -3) {
            bin = 1;
            while (t >= -3 + 0.5 * bin) bin++;
        }
        counts[bin]++;
    }
    return counts.map((count, bin) => {
        const lower = bin === 0 ? '-inf' : hundredths(-300 + 50 * (bin - 1));
        const upper = bin === 13 ? 'inf' : hundredths(-300 + 50 * bin);
        return `${lower} ${upper} ${count} |${'#'.repeat(count)}`;
    });
}

function plotBlock(result, settings) {
    const { series, models, comparison, minY, maxY } = result;
    const { width, height } = settings;
    const points = series.points;
    const firstX = points[0].X;
    const lastX = points.at(-1).X;
    const ymin = minY / 100;
    const ymax = maxY / 100;
    const blank = () => Array.from({ length: height }, () => Array(width).fill(' '));
    const clampRow = value => Math.max(0, Math.min(height - 1, Math.floor(value)));
    const column = point => Math.min(width - 1, Math.floor(width * (point.X - firstX) / (lastX - firstX)));
    const cells = blank();
    for (const point of points) {
        const row = Math.min(height - 1, Math.floor(height * (maxY - point.Y) / (maxY - minY)));
        cells[row][column(point)] = '.';
    }
    for (let i = 0; i < settings.plotMethods.length; i++) {
        const model = models.find(item => item.name === settings.plotMethods[i]);
        const digit = String(i + 1);
        for (let c = 0; c < width; c++) {
            const position = firstX + Math.floor((2 * c + 1) * (lastX - firstX) / (2 * width));
            const value = model.at(position).value;
            if (value === null) continue;
            const row = clampRow(height * (ymax - value) / (ymax - ymin));
            const previous = cells[row][c];
            cells[row][c] = previous === ' ' || previous === '.' || previous === digit ? digit : '*';
        }
    }
    let data = 0;
    let curve = 0;
    let overlap = 0;
    for (const row of cells) {
        for (const cell of row) {
            if (cell === '.') data++;
            else if (cell === '*') overlap++;
            else if (cell >= '1' && cell <= '9') curve++;
        }
    }
    const residuals = blank();
    residuals[Math.floor(height / 2)].fill('-');
    const errors = comparison.best.diagnostics.errors;
    let limit = 0;
    for (const error of errors) limit = Math.max(limit, Math.abs(error));
    for (let i = 0; i < points.length; i++) residuals[clampRow(height * ((limit - errors[i]) / (2 * limit)))][column(points[i])] = 'o';
    const lines = [`plot ${series.name} size ${width}x${height} x ${hundredths(firstX)} ${hundredths(lastX)} y ${hundredths(minY)} ${hundredths(maxY)}`,
        'legend . data ' + settings.plotMethods.map((name, i) => `${i + 1} ${name}`).join(' '),
        ...frame(cells), `cells data ${data} curve ${curve} overlap ${overlap}`, '',
        `residuals ${series.name} method ${comparison.best.name} limit ${real(limit)}`, ...frame(residuals), '',
        `histogram ${series.name} method ${comparison.outlierMethod.name}`, ...histogram(comparison.standardized)];
    return lines.join('\n');
}

function processSeries(series, settings, methods, draw) {
    const points = series.points;
    const grid = Array.from({ length: settings.gridPoints }, (_, k) =>
        points[0].X + Math.floor(k * (points.at(-1).X - points[0].X) / (settings.gridPoints - 1)));
    const models = fitMethods(series, settings, methods);
    const linearRSS = residualSum(points, models[0].yhat);
    for (const model of models) {
        model.grid = grid.map(position => model.at(position));
        model.diagnostics = diagnostics(points, model, linearRSS);
    }
    const comparison = compareFits(models, grid, settings);
    const bands = variabilityBands(points, models, settings);
    const bootstrap = bootstrapIntervals(models.find(model => model.name === 'spline'), grid, settings, draw);
    return { series, grid, models, comparison, bands, bootstrap,
        minY: Math.min(...points.map(point => point.Y)), maxY: Math.max(...points.map(point => point.Y)) };
}

function main() {
    const { settings, series, tests } = readInput();
    const methods = methodList(settings);
    let state = settings.seed;
    const draw = () => { state = 48271 * state % 2147483647; return state; };
    const results = series.map(item => processSeries(item, settings, methods, draw));
    const byName = new Map(results.map(result => [result.series.name, result]));
    const selectionLines = ['series,method,parameter,score,edf,selected'];
    const estimatesHeader = 'series,x,' + methods.map(method => method.name).join(',');
    const fitLines = [estimatesHeader];
    const predictionLines = [estimatesHeader];
    const bandLines = ['series,method,x,fit,se,lower,upper'];
    for (const result of results) {
        const name = result.series.name;
        for (const model of result.models) {
            model.candidates.forEach((candidate, i) => selectionLines.push(
                [name, model.name, candidate.parameter, real(candidate.score), real(candidate.edf), i === model.selected ? 1 : 0].join(',')));
        }
        result.grid.forEach((position, k) => fitLines.push(
            [name, hundredths(position), ...result.models.map(model => real(model.grid[k].value))].join(',')));
        const bands = [...result.bands, { name: 'spline_bootstrap', values: result.bootstrap }];
        for (const band of bands) {
            band.values.forEach((value, k) => bandLines.push([name, band.name, hundredths(result.grid[k]),
                real(value.fit), real(value.se), real(value.lower), real(value.upper)].join(',')));
        }
    }
    for (const test of tests) {
        const result = byName.get(test.name);
        predictionLines.push([test.name, hundredths(test.X), ...result.models.map(model => real(model.at(test.X).value))].join(','));
    }
    const files = [
        ['selection.csv', selectionLines.join('\n')], ['fits.csv', fitLines.join('\n')],
        ['predictions.csv', predictionLines.join('\n')], ['bands.csv', bandLines.join('\n')],
        ['diagnostics.txt', results.map(result => diagnosticsBlock(result, settings)).join('\n\n')],
        ['isotonic.txt', results.map(isotonicBlock).join('\n\n')],
        ['plots.txt', settings.plotSeries.map(name => plotBlock(byName.get(name), settings)).join('\n\n')]
    ];
    fs.mkdirSync('output', { recursive: true });
    for (const [name, contents] of files) fs.writeFileSync('output/' + name, contents + '\n', 'ascii');
}

main();
