'use strict';

const { readInput, nextMonth, real, writeLines } = require('./series_io');
const { sum, mean, sampleVariance, decompose, regression } = require('./decomposition');
const smoothing = require('./smoothing');
const autoregression = require('./autoregression');
const evaluation = require('./evaluation');
const METHODS = ['naive', 'snaive', 'drift', 'ses', 'holt', 'damped', 'hw_add', 'hw_mult', 'decomp_add', 'decomp_mult', 'ar'];
const DIFFERENCES = ['none', 'first', 'seasonal', 'both'];

function squaredSum(values) {
    let total = 0;
    for (const value of values) total += value * value;
    return total;
}

function interpolate(raw) {
    const values = raw.slice();
    for (let t = 0; t < raw.length; t++) {
        if (raw[t] !== null) continue;
        const before = t - 1;
        let after = t + 1;
        while (raw[after] === null) after++;
        for (let i = t; i < after; i++) values[i] = raw[before] + (raw[after] - raw[before]) * (i - before) / (after - before);
        t = after - 1;
    }
    return values;
}

function prepareSeries(series, settings) {
    const values = interpolate(series.raw);
    const decomposition = decompose(values, settings.season);
    const missing = new Set(series.raw.map((value, t) => value === null ? t : -1).filter(t => t >= 0));
    const pastEvents = new Map();
    const lifts = new Map();
    for (let t = 0; t < values.length; t++) {
        const kind = series.events.get(series.periods[t]);
        if (kind === undefined) continue;
        pastEvents.set(t, kind);
        if (!lifts.has(kind)) lifts.set(kind, { count: 0, total: 0 });
        const entry = lifts.get(kind);
        entry.count++;
        entry.total += values[t] / (decomposition.trend[t] + decomposition.add[t % settings.season]);
    }
    for (const entry of lifts.values()) entry.lift = entry.total / entry.count;
    const residuals = decomposition.defined.map(t => decomposition.residualAdd[t]);
    const residualMean = mean(residuals);
    const residualVariance = sampleVariance(residuals);
    const deviation = Math.sqrt(residualVariance);
    const outliers = new Map();
    for (const t of decomposition.defined) {
        if (missing.has(t) || pastEvents.has(t)) continue;
        const difference = decomposition.residualAdd[t] - residualMean;
        if (Math.abs(difference) > settings.outlier * deviation) outliers.set(t, difference / deviation);
    }
    const cleaned = values.map((value, t) => outliers.has(t) || pastEvents.has(t)
        ? decomposition.trend[t] + decomposition.add[t % settings.season] : value);
    const trendVariance = sampleVariance(decomposition.defined.map(t => decomposition.trend[t] + decomposition.residualAdd[t]));
    const seasonalVariance = sampleVariance(decomposition.defined.map(t => decomposition.add[t % settings.season] + decomposition.residualAdd[t]));
    const strengthTrend = Math.max(0, 1 - residualVariance / trendVariance);
    const strengthSeasonal = Math.max(0, 1 - residualVariance / seasonalVariance);
    const periods = series.periods.slice();
    for (let k = 0; k < settings.horizon; k++) periods.push(nextMonth(periods.at(-1)));
    return { ...series, periods, values, cleaned, decomposition, missing, pastEvents, lifts, outliers, strengthTrend, strengthSeasonal };
}

function* parameterGrid(names, settings, position = 0, current = {}) {
    if (position === names.length) { yield current; return; }
    const name = names[position];
    for (const value of settings[name]) yield* parameterGrid(names, settings, position + 1, { ...current, [name]: value });
}

function regressionForecast(model, time) {
    const seasonal = model.seasonal[time % model.seasonal.length];
    return model.name === 'decomp_add' ? model.intercept + model.slope * (time + 1) + seasonal
        : (model.intercept + model.slope * (time + 1)) * seasonal;
}

function fitAutoregression(model, settings) {
    const variants = DIFFERENCES.map(kind => {
        const differenced = autoregression.difference(model.values, kind, settings.season);
        return { kind, ...differenced, ...autoregression.autocorrelation(differenced.values, settings.maxLag) };
    });
    let chosen = variants[0];
    for (const candidate of variants.slice(1)) if (candidate.variance < chosen.variance) chosen = candidate;
    const recursion = autoregression.durbinLevinson(chosen.correlations);
    const aic = [];
    let order = 0;
    for (let p = 0; p <= settings.maxAr; p++) {
        aic.push(chosen.values.length * Math.log(chosen.variance * recursion.variances[p]) + 2 * p);
        if (aic[p] < aic[order]) order = p;
    }
    Object.assign(model, { difference: chosen.kind, differenced: chosen.values, offset: chosen.offset,
        average: chosen.mean, variances: variants.map(variant => variant.variance), correlations: chosen.correlations,
        partial: recursion.partial, aic, order, coefficients: recursion.rows[order], sigma2: chosen.variance * recursion.variances[order] });
    model.residuals = autoregression.residuals(model.differenced, model.average, model.coefficients);
}

function fitMethod(name, values, settings) {
    const model = { name, values };
    const season = settings.season;
    if (name === 'naive') model.residuals = values.slice(1).map((value, i) => value - values[i]);
    else if (name === 'snaive') model.residuals = values.slice(season).map((value, i) => value - values[i]);
    else if (name === 'drift') {
        model.slope = (values.at(-1) - values[0]) / (values.length - 1);
        model.residuals = values.slice(1).map((value, i) => value - values[i] - model.slope);
    } else if (name === 'ar') fitAutoregression(model, settings);
    else if (name.startsWith('decomp_')) {
        const decomposition = decompose(values, season);
        model.seasonal = name === 'decomp_add' ? decomposition.add : decomposition.mult;
        const adjusted = values.map((value, t) => name === 'decomp_add' ? value - model.seasonal[t % season] : value / model.seasonal[t % season]);
        Object.assign(model, regression(adjusted));
        model.residuals = values.map((value, t) => value - regressionForecast(model, t));
    } else {
        const names = name === 'ses' ? ['alpha'] : name === 'holt' ? ['alpha', 'beta']
            : name === 'damped' ? ['alpha', 'beta', 'phi'] : ['alpha', 'beta', 'gamma'];
        let best = null;
        for (const parameters of parameterGrid(names, settings)) {
            const candidate = smoothing.smooth(name, values, season, parameters);
            const sse = squaredSum(candidate.residuals);
            if (best === null || sse < best.sse) best = { ...candidate, parameters, sse };
        }
        Object.assign(model, best);
    }
    model.sse = squaredSum(model.residuals);
    model.residualRmse = Math.sqrt(model.sse / model.residuals.length);
    return model;
}

function forecast(model, origin, steps, settings) {
    if (model.name === 'combo') {
        const result = Array(steps).fill(0);
        for (const member of model.members) {
            const values = forecast(member, origin, steps, settings);
            for (let k = 0; k < steps; k++) result[k] += values[k];
        }
        return result.map(value => value / model.members.length);
    }
    if (model.name === 'ar') return autoregression.forecast(model, origin, steps, settings.season);
    if (model.states) return smoothing.forecast(model.name, model.states[origin], origin, steps, settings.season, model.parameters);
    const result = [];
    for (let k = 1; k <= steps; k++) {
        if (model.name === 'naive') result.push(model.values[origin - 1]);
        else if (model.name === 'snaive') result.push(model.values[origin - settings.season + (k - 1) % settings.season]);
        else if (model.name === 'drift') result.push(model.values[origin - 1] + k * ((model.values[origin - 1] - model.values[0]) / (origin - 1)));
        else result.push(regressionForecast(model, origin + k - 1));
    }
    return result;
}

function crossValidate(model, settings) {
    const squares = Array(settings.horizon).fill(0);
    const absolute = Array(settings.horizon).fill(0);
    const origins = Array(settings.horizon).fill(0);
    for (let origin = settings.cvStart; origin < model.values.length; origin++) {
        const steps = Math.min(settings.horizon, model.values.length - origin);
        const values = forecast(model, origin, steps, settings);
        for (let k = 0; k < steps; k++) {
            const error = model.values[origin + k] - values[k];
            squares[k] += error * error;
            absolute[k] += Math.abs(error);
            origins[k]++;
        }
    }
    const sigma = squares.map((value, k) => Math.sqrt(value / origins[k]));
    const mae = absolute.map((value, k) => value / origins[k]);
    const rmse = Math.sqrt(sum(squares.slice(0, settings.holdout)) / sum(origins.slice(0, settings.holdout)));
    return { origins, sigma, mae, rmse };
}

function modelLines(model) {
    const name = model.name;
    const residual = `rmse ${real(model.residualRmse)} residuals ${model.residuals.length}`;
    if (name === 'naive' || name === 'snaive') return [`${name} ${residual}`];
    if (name === 'drift') return [`drift slope ${real(model.slope)} ${residual}`];
    if (name === 'ar') {
        return ['ar variance ' + DIFFERENCES.map((kind, i) => `${kind} ${real(model.variances[i])}`).join(' '),
            `ar difference ${model.difference} n ${model.differenced.length} mean ${real(model.average)} order ${model.order}`
                + ` sigma2 ${real(model.sigma2)} ${residual}`,
            'ar aic ' + model.aic.map(real).join(' '),
            'ar coefficients ' + (model.coefficients.length ? model.coefficients.map(real).join(' ') : 'none')];
    }
    if (name.startsWith('decomp_')) return [`${name} intercept ${real(model.intercept)} slope ${real(model.slope)} ${residual}`,
        `${name} seasonal ${model.seasonal.map(real).join(' ')}`];
    const parameters = model.parameters;
    const state = model.states.at(-1);
    let text = `${name} alpha ${real(parameters.alpha)}`;
    if (name !== 'ses') text += ' beta ' + real(parameters.beta);
    if (name === 'damped') text += ' phi ' + real(parameters.phi);
    if (name.startsWith('hw_')) text += ' gamma ' + real(parameters.gamma);
    text += ` ${residual} level ${real(state.level)}`;
    if (name !== 'ses') text += ' slope ' + real(state.slope);
    const lines = [text];
    if (name.startsWith('hw_')) {
        const rotated = state.seasonal.map((_, i) => state.seasonal[(model.values.length + i) % state.seasonal.length]);
        lines.push(`${name} seasonal ${rotated.map(real).join(' ')}`);
    }
    return lines;
}

function predictionRow(period, actual, value, sigma, multiplier, settings) {
    const [z80, z95] = settings.interval;
    return { period, actual, forecast: value * multiplier, lo80: (value - z80 * sigma) * multiplier,
        hi80: (value + z80 * sigma) * multiplier, lo95: (value - z95 * sigma) * multiplier,
        hi95: (value + z95 * sigma) * multiplier };
}

function assessHoldout(model, series, settings, delta) {
    const origin = series.values.length - settings.holdout;
    const actual = series.values.slice(origin);
    const predictions = forecast(model, origin, settings.holdout, settings);
    const rows = predictions.map((value, i) => predictionRow(series.periods[origin + i], actual[i], value, model.cv.sigma[i], 1, settings));
    const accuracy = evaluation.accuracy(actual, predictions, delta);
    accuracy.cover80 = 0;
    accuracy.cover95 = 0;
    let winkler80 = 0;
    let winkler95 = 0;
    for (const row of rows) {
        if (row.lo80 <= row.actual && row.actual <= row.hi80) accuracy.cover80++;
        if (row.lo95 <= row.actual && row.actual <= row.hi95) accuracy.cover95++;
        winkler80 += evaluation.winkler(row.actual, row.lo80, row.hi80, 10);
        winkler95 += evaluation.winkler(row.actual, row.lo95, row.hi95, 40);
    }
    accuracy.winkler80 = winkler80 / settings.holdout;
    accuracy.winkler95 = winkler95 / settings.holdout;
    return { model, rows, accuracy };
}

function finalForecast(best, members, series, settings) {
    const names = best.model.name === 'combo' ? members.map(model => model.name) : [best.model.name];
    const fitted = names.map(name => fitMethod(name, series.cleaned, settings));
    const model = best.model.name === 'combo' ? { name: 'combo', values: series.cleaned, members: fitted } : fitted[0];
    const cv = crossValidate(model, settings);
    const predictions = forecast(model, series.values.length, settings.horizon, settings);
    const rows = predictions.map((value, k) => {
        const period = series.periods[series.values.length + k];
        const kind = series.events.get(period);
        const multiplier = kind === undefined ? 1 : series.lifts.get(kind).lift;
        return predictionRow(period, null, value, cv.sigma[k], multiplier, settings);
    });
    return { model, fitted, rows };
}

function inventoryPlan(series, final, settings) {
    const { onHand, leadTime, review, service } = series.inventory;
    const span = leadTime + review;
    let squaredErrors = 0;
    for (let origin = settings.cvStart; origin <= series.cleaned.length - span; origin++) {
        const predictions = forecast(final.model, origin, span, settings);
        let error = 0;
        for (let k = 0; k < span; k++) error += series.cleaned[origin + k] - predictions[k];
        squaredErrors += error * error;
    }
    const sigma = Math.sqrt(squaredErrors / (series.cleaned.length - span - settings.cvStart + 1));
    const safety = service * sigma;
    const reviews = new Set();
    let lastReview = 1;
    for (let k = 1; k - 1 + span <= settings.horizon; k += review) { reviews.add(k); lastReview = k; }
    const end = lastReview - 1 + span;
    const lines = [`series ${series.name} method ${final.model.name}`,
        `policy on_hand ${onHand} lead_time ${leadTime} review ${review} service ${real(service)} safety_stock ${real(safety)}`];
    const receipts = new Map();
    let stock = onHand;
    let pending = 0;
    let orders = 0;
    let ordered = 0;
    let shortPeriods = 0;
    let minimum = 0;
    let totalStock = 0;
    for (let k = 1; k <= end; k++) {
        const receipt = receipts.get(k) ?? 0;
        stock += receipt;
        pending -= receipt;
        const row = final.rows[k - 1];
        if (reviews.has(k)) {
            const position = stock + pending;
            const target = sum(final.rows.slice(k - 1, k - 1 + span).map(item => item.forecast)) + safety;
            const quantity = Math.max(0, Math.ceil(target - position));
            if (quantity > 0) {
                receipts.set(k + leadTime, quantity);
                pending += quantity;
                orders++;
                ordered += quantity;
            }
            lines.push(`review ${row.period} position ${real(position)} target ${real(target)} order ${quantity}`);
        }
        stock -= row.forecast;
        const status = stock < 0 ? 'short' : stock < safety ? 'low' : 'ok';
        if (status === 'short') shortPeriods++;
        if (k === 1 || stock < minimum) minimum = stock;
        totalStock += stock;
        lines.push(`period ${row.period} demand ${real(row.forecast)} receipt ${receipt} on_hand ${real(stock)} status ${status}`);
    }
    lines.push(`summary orders ${orders} ordered ${ordered} short_periods ${shortPeriods} lowest ${real(minimum)} average ${real(totalStock / end)}`);
    return lines;
}

function yearlyTotals(series, futureRows) {
    const years = new Map();
    const getYear = period => {
        const year = period.slice(0, 4);
        if (!years.has(year)) years.set(year, { year, actualMonths: 0, actual: 0, forecastMonths: 0, forecast: 0 });
        return years.get(year);
    };
    for (let t = 0; t < series.values.length; t++) {
        const entry = getYear(series.periods[t]);
        entry.actualMonths++;
        entry.actual += series.values[t];
    }
    for (const row of futureRows) {
        const entry = getYear(row.period);
        entry.forecastMonths++;
        entry.forecast += row.forecast;
    }
    const lines = [];
    let previous = null;
    for (const year of [...years.keys()].sort()) {
        const entry = years.get(year);
        entry.total = entry.actual + entry.forecast;
        entry.months = entry.actualMonths + entry.forecastMonths;
        const growth = previous !== null && entry.months === 12 && previous.months === 12
            ? real(100 * (entry.total - previous.total) / previous.total) : 'NA';
        lines.push(`year ${year} actual_months ${entry.actualMonths} actual ${real(entry.actual)} forecast_months ${entry.forecastMonths}`
            + ` forecast ${real(entry.forecast)} total ${real(entry.total)} growth ${growth}`);
        previous = entry;
    }
    return lines;
}

function residualDiagnostics(model) {
    const count = model.residuals.length;
    const average = mean(model.residuals);
    let second = 0;
    let third = 0;
    let fourth = 0;
    let successive = 0;
    for (let i = 0; i < count; i++) {
        const centered = model.residuals[i] - average;
        second += centered * centered;
        third += centered * centered * centered;
        fourth += centered * centered * centered * centered;
        if (i > 0) { const difference = model.residuals[i] - model.residuals[i - 1]; successive += difference * difference; }
    }
    const m2 = second / count;
    const m3 = third / count;
    const m4 = fourth / count;
    const sd = Math.sqrt(second / (count - 1));
    const dw = successive / model.sse;
    const skewness = m3 / (m2 * Math.sqrt(m2));
    const kurtosis = m4 / (m2 * m2) - 3;
    const jb = count / 6 * (skewness * skewness + kurtosis * kurtosis / 4);
    return `residuals ${model.name} n ${count} mean ${real(average)} sd ${real(sd)} dw ${real(dw)}`
        + ` skewness ${real(skewness)} kurtosis ${real(kurtosis)} jb ${real(jb)}`;
}

function correlationBar(correlation, band) {
    const bar = Array(41).fill(' ');
    const boundary = Math.floor(band * 20 + 0.5);
    const length = Math.floor(Math.abs(correlation) * 20 + 0.5);
    bar[20 - boundary] = ':';
    bar[20 + boundary] = ':';
    bar[20] = '|';
    if (correlation > 0) for (let i = 21; i <= 20 + length; i++) bar[i] = '#';
    if (correlation < 0) for (let i = 20 - length; i <= 19; i++) bar[i] = '#';
    return bar.join('');
}

function correlogram(series, methods, settings) {
    const ar = methods.at(-1);
    const band = 2 / Math.sqrt(ar.differenced.length);
    const lines = [`series ${series.name} difference ${ar.difference} n ${ar.differenced.length} band ${real(band)}`];
    for (const [name, values] of [['acf', ar.correlations], ['pacf', ar.partial]]) {
        for (let k = 1; k <= settings.maxLag; k++) {
            const value = values[k];
            lines.push(`${name} ${String(k).padStart(2, ' ')} ${real(value).padStart(7, ' ')} [${correlationBar(value, band)}]`
                + (Math.abs(value) > band ? ' *' : ''));
        }
    }
    for (const method of methods) {
        lines.push(residualDiagnostics(method));
        const tests = autoregression.ljungBox(method.residuals, settings.ljungBox);
        lines.push(`ljung_box ${method.name} ` + tests.map(test => `lag ${test.lag} q ${real(test.q)} p ${real(test.p)}`).join(' '));
    }
    return lines;
}

function forecastChart(series, best, final) {
    const rows = [...best.rows, ...final.rows];
    let low = rows[0].lo95;
    let high = rows[0].hi95;
    for (const row of rows) {
        low = Math.min(low, row.lo95);
        high = Math.max(high, row.hi95);
        if (row.actual !== null) { low = Math.min(low, row.actual); high = Math.max(high, row.actual); }
    }
    const column = value => Math.floor((value - low) / (high - low) * 60 + 0.5);
    const lines = [`chart ${series.name} method ${best.model.name}`, `scale low ${real(low)} high ${real(high)}`];
    for (const row of rows) {
        const chart = Array(61).fill(' ');
        for (let i = column(row.lo95); i <= column(row.hi95); i++) chart[i] = '-';
        for (let i = column(row.lo80); i <= column(row.hi80); i++) chart[i] = '=';
        chart[column(row.forecast)] = 'o';
        if (row.actual !== null) chart[column(row.actual)] = '*';
        lines.push(`${row.period} |${chart.join('')}|`);
    }
    let peak = 0;
    for (const seasonal of series.decomposition.mult) peak = Math.max(peak, Math.abs(seasonal - 1));
    lines.push('profile peak ' + real(peak));
    for (let j = 0; j < series.decomposition.mult.length; j++) {
        const seasonal = series.decomposition.mult[j];
        const chart = Array(61).fill(' ');
        chart[30] = '|';
        const length = Math.floor(Math.abs(seasonal - 1) / peak * 30 + 0.5);
        if (seasonal > 1) for (let i = 31; i <= 30 + length; i++) chart[i] = '#';
        if (seasonal < 1) for (let i = 30 - length; i <= 29; i++) chart[i] = '#';
        lines.push(`season ${String(j + 1).padStart(2, ' ')} ${real(seasonal)} [${chart.join('')}]`);
    }
    return lines;
}

function decompositionLines(series, settings) {
    const lines = [];
    const d = series.decomposition;
    const valueText = value => value === null ? 'NA' : real(value);
    for (let t = 0; t < series.values.length; t++) {
        const flag = series.pastEvents.get(t) ?? (series.missing.has(t) ? 'missing' : series.outliers.has(t) ? 'outlier' : 'ok');
        const j = t % settings.season;
        lines.push([series.name, series.periods[t], real(series.values[t]), real(series.cleaned[t]), valueText(d.trend[t]),
            real(d.add[j]), valueText(d.residualAdd[t]), real(d.mult[j]), valueText(d.residualMult[t]), flag].join(','));
    }
    return lines;
}

function fittedModelLines(series, methods, members, best, final, settings) {
    const lines = [`series ${series.name}`, `data observations ${series.values.length} train ${series.values.length - settings.holdout}`
        + ` holdout ${settings.holdout} missing ${series.missing.size} outliers ${series.outliers.size} events ${series.pastEvents.size}`];
    for (const [kind, entry] of series.lifts) lines.push(`event ${kind} occurrences ${entry.count} lift ${real(entry.lift)}`);
    for (const [t, score] of series.outliers) lines.push(`outlier ${series.periods[t]} value ${real(series.values[t])} expected ${real(series.cleaned[t])} score ${real(score)}`);
    lines.push(`strength trend ${real(series.strengthTrend)} seasonal ${real(series.strengthSeasonal)}`);
    for (const method of methods) lines.push(...modelLines(method));
    lines.push('combo members ' + members.map(model => model.name).join(' '), `best ${best.model.name} rmse ${real(best.accuracy.rmse)}`);
    for (const method of final.fitted) lines.push(...modelLines(method).map(line => 'final ' + line));
    return lines;
}

function forecastLine(series, stage, name, row) {
    return [series.name, stage, name, row.period, row.actual === null ? 'NA' : row.actual,
        ...[row.forecast, row.lo80, row.hi80, row.lo95, row.hi95].map(real)].join(',');
}

function appendReports(reports, series, methods, members, assessments, best, final, settings) {
    reports.decomposition.push(...decompositionLines(series, settings));
    reports.models.push(...fittedModelLines(series, methods, members, best, final, settings));
    for (const assessment of assessments) {
        const { model, rows, accuracy: a } = assessment;
        for (const row of rows) reports.forecasts.push(forecastLine(series, 'holdout', model.name, row));
        reports.accuracy.push([series.name, model.name, ...[a.me, a.mae, a.rmse, a.mape, a.smape, a.mase, a.fva, model.cv.rmse].map(real),
            a.cover80, a.cover95, real(a.winkler80), real(a.winkler95), a.rank].join(','));
        for (let k = 0; k < settings.horizon; k++) reports.cv.push([series.name, model.name, k + 1, model.cv.origins[k],
            real(model.cv.mae[k]), real(model.cv.sigma[k])].join(','));
    }
    for (const row of final.rows) reports.forecasts.push(forecastLine(series, 'future', best.model.name, row));
    reports.correlogram.push(...correlogram(series, methods, settings));
    reports.chart.push(...forecastChart(series, best, final));
    reports.plan.push(...inventoryPlan(series, final, settings), ...yearlyTotals(series, final.rows));
}

function main() {
    const { settings, series: inputs } = readInput();
    const reports = {
        decomposition: ['series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag'],
        models: [], forecasts: ['series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95'],
        accuracy: ['series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank'],
        cv: ['series,method,step,origins,mae,rmse'], correlogram: [], chart: [], plan: []
    };
    for (const input of inputs) {
        const series = prepareSeries(input, settings);
        const training = series.cleaned.slice(0, series.values.length - settings.holdout);
        const methods = METHODS.map(name => fitMethod(name, training, settings));
        for (const method of methods) method.cv = crossValidate(method, settings);
        const selected = evaluation.rank(methods.map(model => model.cv.rmse)).slice(0, settings.combo).sort((a, b) => a - b);
        const members = selected.map(index => methods[index]);
        const combo = { name: 'combo', values: training, members };
        combo.cv = crossValidate(combo, settings);
        const delta = evaluation.scale(training, settings.season);
        const assessments = [...methods, combo].map(model => assessHoldout(model, series, settings, delta));
        for (const assessment of assessments) assessment.accuracy.fva = 100 * (assessments[0].accuracy.mae - assessment.accuracy.mae) / assessments[0].accuracy.mae;
        const ranking = evaluation.rank(assessments.map(assessment => assessment.accuracy.rmse));
        for (let index = 0; index < ranking.length; index++) assessments[ranking[index]].accuracy.rank = index + 1;
        const best = assessments[ranking[0]];
        const final = finalForecast(best, members, series, settings);
        appendReports(reports, series, methods, members, assessments, best, final, settings);
    }
    for (const [name, extension] of [['decomposition', 'csv'], ['models', 'txt'], ['forecasts', 'csv'], ['accuracy', 'csv'],
        ['cv', 'csv'], ['correlogram', 'txt'], ['chart', 'txt'], ['plan', 'txt']]) writeLines(name + '.' + extension, reports[name]);
}

main();
