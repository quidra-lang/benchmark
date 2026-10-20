import { readInput, nextMonth, real, writeLines, type Settings, type Series } from './series_io.ts';
import { sum, mean, sampleVariance, decompose, regression, type Decomposition } from './decomposition.ts';
import * as smoothing from './smoothing.ts';
import * as ar from './autoregression.ts';
import * as evaluation from './evaluation.ts';
const METHODS = ['naive', 'snaive', 'drift', 'ses', 'holt', 'damped', 'hw_add', 'hw_mult', 'decomp_add', 'decomp_mult', 'ar'] as const;
type MethodName = typeof METHODS[number];
interface Base { values: number[]; residuals: number[] }
type RegressionCore = Base & { name: 'decomp_add' | 'decomp_mult'; seasonal: number[]; intercept: number; slope: number };
type ARCore = Base & ar.ARState & { name: 'ar'; variances: number[]; correlations: number[]; partial: number[]; aic: number[]; order: number; sigma2: number };
type SmoothCore = Base & { name: smoothing.SmoothName; parameters: smoothing.Parameters; states: smoothing.State[] };
type Core = (Base & { name: 'naive' | 'snaive' }) | (Base & { name: 'drift'; slope: number }) | RegressionCore | ARCore | SmoothCore;
type Method = Core & { sse: number; residualRmse: number };
interface Combo { name: 'combo'; values: number[]; members: Method[] }
type Model = Method | Combo;
interface CV { origins: number[]; sigma: number[]; mae: number[]; rmse: number }
interface Evaluated { model: Model; cv: CV }
interface Prediction { period: string; actual: number | null; forecast: number; lo80: number; hi80: number; lo95: number; hi95: number }
interface Assessment extends Evaluated { rows: Prediction[]; accuracy: ReturnType<typeof evaluation.accuracy> & { fva: number; rank: number; cover80: number; cover95: number; winkler80: number; winkler95: number } }
interface Final { model: Model; fitted: Method[]; rows: Prediction[] }
interface Lift { count: number; total: number; lift: number }
interface Prepared extends Series { values: number[]; cleaned: number[]; decomposition: Decomposition; missing: Set<number>; pastEvents: Map<number, string>; lifts: Map<string, Lift>; outliers: Map<number, number>; strengthTrend: number; strengthSeasonal: number }
const squaredSum = (values: number[]) => { let total = 0; for (const v of values) total += v * v; return total; };
function interpolate(raw: (number | null)[]) {
    const values = raw.map(v => v ?? 0);
    for (let t = 0; t < raw.length; t++) {
        if (raw[t] !== null) continue;
        const before = t - 1; let after = t + 1; while (raw[after] === null) after++;
        for (let i = t; i < after; i++) values[i] = raw[before]! + (raw[after]! - raw[before]!) * (i - before) / (after - before);
        t = after - 1;
    }
    return values;
}
function prepareSeries(series: Series, s: Settings): Prepared {
    const values = interpolate(series.raw), d = decompose(values, s.season), missing = new Set<number>(), pastEvents = new Map<number, string>(), lifts = new Map<string, Lift>();
    for (let t = 0; t < values.length; t++) {
        if (series.raw[t] === null) missing.add(t);
        const kind = series.events.get(series.periods[t]); if (kind === undefined) continue;
        pastEvents.set(t, kind);
        let entry = lifts.get(kind); if (!entry) { entry = { count: 0, total: 0, lift: 0 }; lifts.set(kind, entry); }
        entry.count++; entry.total += values[t] / (d.trend[t]! + d.add[t % s.season]);
    }
    for (const entry of lifts.values()) entry.lift = entry.total / entry.count;
    const residuals = d.defined.map(t => d.residualAdd[t]!), residualMean = mean(residuals), variance = sampleVariance(residuals), deviation = Math.sqrt(variance), outliers = new Map<number, number>();
    for (const t of d.defined) {
        if (missing.has(t) || pastEvents.has(t)) continue;
        const delta = d.residualAdd[t]! - residualMean; if (Math.abs(delta) > s.outlier * deviation) outliers.set(t, delta / deviation);
    }
    const cleaned = values.map((v, t) => outliers.has(t) || pastEvents.has(t) ? d.trend[t]! + d.add[t % s.season] : v);
    const trendVariance = sampleVariance(d.defined.map(t => d.trend[t]! + d.residualAdd[t]!)), seasonalVariance = sampleVariance(d.defined.map(t => d.add[t % s.season] + d.residualAdd[t]!));
    const periods = series.periods.slice(); for (let k = 0; k < s.horizon; k++) periods.push(nextMonth(periods[periods.length - 1]));
    return { ...series, periods, values, cleaned, decomposition: d, missing, pastEvents, lifts, outliers, strengthTrend: Math.max(0, 1 - variance / trendVariance), strengthSeasonal: Math.max(0, 1 - variance / seasonalVariance) };
}
type ParameterName = keyof smoothing.Parameters;
function* parameterGrid(names: ParameterName[], s: Settings, position = 0, current: smoothing.Parameters = { alpha: 0, beta: 0, gamma: 0, phi: 1 }): Generator<smoothing.Parameters> {
    if (position === names.length) { yield current; return; }
    const name = names[position]; for (const value of s[name]) yield* parameterGrid(names, s, position + 1, { ...current, [name]: value });
}
function regressionForecast(model: RegressionCore, time: number) {
    const seasonal = model.seasonal[time % model.seasonal.length];
    return model.name === 'decomp_add' ? model.intercept + model.slope * (time + 1) + seasonal : (model.intercept + model.slope * (time + 1)) * seasonal;
}
function fitAutoregression(values: number[], s: Settings): ARCore {
    const variants = ar.DIFFERENCES.map(kind => { const d = ar.difference(values, kind, s.season); return { kind, ...d, ...ar.autocorrelation(d.values, s.maxLag) }; });
    let chosen = variants[0]; for (const v of variants.slice(1)) if (v.variance < chosen.variance) chosen = v;
    const recursion = ar.durbinLevinson(chosen.correlations), aic: number[] = []; let order = 0;
    for (let p = 0; p <= s.maxAr; p++) { aic.push(chosen.values.length * Math.log(chosen.variance * recursion.variances[p]) + 2 * p); if (aic[p] < aic[order]) order = p; }
    const coefficients = recursion.rows[order];
    return { name: 'ar', values, difference: chosen.kind, differenced: chosen.values, offset: chosen.offset, average: chosen.mean,
        variances: variants.map(v => v.variance), correlations: chosen.correlations, partial: recursion.partial, aic, order, coefficients,
        sigma2: chosen.variance * recursion.variances[order], residuals: ar.residuals(chosen.values, chosen.mean, coefficients) };
}
function fitMethod(name: MethodName, values: number[], s: Settings): Method {
    let core: Core;
    if (name === 'naive') core = { name, values, residuals: values.slice(1).map((v, i) => v - values[i]) };
    else if (name === 'snaive') core = { name, values, residuals: values.slice(s.season).map((v, i) => v - values[i]) };
    else if (name === 'drift') { const slope = (values[values.length - 1] - values[0]) / (values.length - 1); core = { name, values, slope, residuals: values.slice(1).map((v, i) => v - values[i] - slope) }; }
    else if (name === 'ar') core = fitAutoregression(values, s);
    else if (name === 'decomp_add' || name === 'decomp_mult') {
        const d = decompose(values, s.season), seasonal = name === 'decomp_add' ? d.add : d.mult;
        const adjusted = values.map((v, t) => name === 'decomp_add' ? v - seasonal[t % s.season] : v / seasonal[t % s.season]);
        const model: RegressionCore = { name, values, seasonal, ...regression(adjusted), residuals: [] };
        model.residuals = values.map((v, t) => v - regressionForecast(model, t)); core = model;
    } else {
        const names: ParameterName[] = name === 'ses' ? ['alpha'] : name === 'holt' ? ['alpha', 'beta'] : name === 'damped' ? ['alpha', 'beta', 'phi'] : ['alpha', 'beta', 'gamma'];
        let best: { states: smoothing.State[]; residuals: number[]; parameters: smoothing.Parameters; sse: number } | null = null;
        for (const parameters of parameterGrid(names, s)) {
            const candidate = smoothing.smooth(name, values, s.season, parameters), sse = squaredSum(candidate.residuals);
            if (!best || sse < best.sse) best = { ...candidate, parameters, sse };
        }
        core = { name, values, states: best!.states, residuals: best!.residuals, parameters: best!.parameters };
    }
    const sse = squaredSum(core.residuals); return { ...core, sse, residualRmse: Math.sqrt(sse / core.residuals.length) };
}
function forecast(model: Model, origin: number, steps: number, s: Settings): number[] {
    if (model.name === 'combo') {
        const result: number[] = Array(steps).fill(0);
        for (const member of model.members) { const values = forecast(member, origin, steps, s); for (let k = 0; k < steps; k++) result[k] += values[k]; }
        return result.map(v => v / model.members.length);
    }
    if (model.name === 'ar') return ar.forecast(model, origin, steps, s.season);
    if ('states' in model) return smoothing.forecast(model.name, model.states[origin], origin, steps, s.season, model.parameters);
    const result: number[] = [];
    for (let k = 1; k <= steps; k++) {
        if (model.name === 'naive') result.push(model.values[origin - 1]);
        else if (model.name === 'snaive') result.push(model.values[origin - s.season + (k - 1) % s.season]);
        else if (model.name === 'drift') result.push(model.values[origin - 1] + k * ((model.values[origin - 1] - model.values[0]) / (origin - 1)));
        else if ('seasonal' in model) result.push(regressionForecast(model, origin + k - 1));
    }
    return result;
}
function crossValidate(model: Model, s: Settings): CV {
    const squares: number[] = Array(s.horizon).fill(0), absolute: number[] = Array(s.horizon).fill(0), origins: number[] = Array(s.horizon).fill(0);
    for (let origin = s.cvStart; origin < model.values.length; origin++) {
        const steps = Math.min(s.horizon, model.values.length - origin), values = forecast(model, origin, steps, s);
        for (let k = 0; k < steps; k++) { const e = model.values[origin + k] - values[k]; squares[k] += e * e; absolute[k] += Math.abs(e); origins[k]++; }
    }
    return { origins, sigma: squares.map((v, k) => Math.sqrt(v / origins[k])), mae: absolute.map((v, k) => v / origins[k]), rmse: Math.sqrt(sum(squares.slice(0, s.holdout)) / sum(origins.slice(0, s.holdout))) };
}
function modelLines(model: Method) {
    const name = model.name, residual = `rmse ${real(model.residualRmse)} residuals ${model.residuals.length}`;
    if (model.name === 'naive' || model.name === 'snaive') return [`${name} ${residual}`];
    if (model.name === 'drift') return [`drift slope ${real(model.slope)} ${residual}`];
    if (model.name === 'ar') return ['ar variance ' + ar.DIFFERENCES.map((k, i) => `${k} ${real(model.variances[i])}`).join(' '),
        `ar difference ${model.difference} n ${model.differenced.length} mean ${real(model.average)} order ${model.order} sigma2 ${real(model.sigma2)} ${residual}`,
        'ar aic ' + model.aic.map(real).join(' '), 'ar coefficients ' + (model.coefficients.length ? model.coefficients.map(real).join(' ') : 'none')];
    if ('seasonal' in model) return [`${name} intercept ${real(model.intercept)} slope ${real(model.slope)} ${residual}`, `${name} seasonal ${model.seasonal.map(real).join(' ')}`];
    if ('states' in model) {
        const p = model.parameters, state = model.states[model.states.length - 1]; let text = `${name} alpha ${real(p.alpha)}`;
        if (name !== 'ses') text += ' beta ' + real(p.beta); if (name === 'damped') text += ' phi ' + real(p.phi);
        if (name === 'hw_add' || name === 'hw_mult') text += ' gamma ' + real(p.gamma);
        text += ` ${residual} level ${real(state.level)}`; if (name !== 'ses') text += ' slope ' + real(state.slope);
        const lines = [text];
        if (name === 'hw_add' || name === 'hw_mult') lines.push(`${name} seasonal ${state.seasonal.map((_, i) => real(state.seasonal[(model.values.length + i) % state.seasonal.length])).join(' ')}`);
        return lines;
    }
    return [];
}
function predictionRow(period: string, actual: number | null, value: number, sigma: number, multiplier: number, s: Settings): Prediction {
    const [z80, z95] = s.interval;
    return { period, actual, forecast: value * multiplier, lo80: (value - z80 * sigma) * multiplier, hi80: (value + z80 * sigma) * multiplier,
        lo95: (value - z95 * sigma) * multiplier, hi95: (value + z95 * sigma) * multiplier };
}
function assessHoldout(e: Evaluated, series: Prepared, s: Settings, delta: number): Assessment {
    const origin = series.values.length - s.holdout, actual = series.values.slice(origin), predictions = forecast(e.model, origin, s.holdout, s);
    const rows = predictions.map((v, i) => predictionRow(series.periods[origin + i], actual[i], v, e.cv.sigma[i], 1, s));
    const a = { ...evaluation.accuracy(actual, predictions, delta), fva: 0, rank: 0, cover80: 0, cover95: 0, winkler80: 0, winkler95: 0 };
    for (const row of rows) {
        if (row.lo80 <= row.actual! && row.actual! <= row.hi80) a.cover80++; if (row.lo95 <= row.actual! && row.actual! <= row.hi95) a.cover95++;
        a.winkler80 += evaluation.winkler(row.actual!, row.lo80, row.hi80, 10); a.winkler95 += evaluation.winkler(row.actual!, row.lo95, row.hi95, 40);
    }
    a.winkler80 /= s.holdout; a.winkler95 /= s.holdout;
    return { ...e, rows, accuracy: a };
}
function finalForecast(best: Assessment, members: Method[], series: Prepared, s: Settings): Final {
    const names = best.model.name === 'combo' ? members.map(m => m.name) : [best.model.name], fitted = names.map(n => fitMethod(n, series.cleaned, s));
    const model: Model = best.model.name === 'combo' ? { name: 'combo', values: series.cleaned, members: fitted } : fitted[0];
    const cv = crossValidate(model, s), predictions = forecast(model, series.values.length, s.horizon, s);
    const rows = predictions.map((v, k) => { const period = series.periods[series.values.length + k], kind = series.events.get(period); return predictionRow(period, null, v, cv.sigma[k], kind === undefined ? 1 : series.lifts.get(kind)!.lift, s); });
    return { model, fitted, rows };
}
function inventoryPlan(series: Prepared, final: Final, s: Settings) {
    const { onHand, leadTime, review, service } = series.inventory, span = leadTime + review;
    let squaredErrors = 0;
    for (let origin = s.cvStart; origin <= series.cleaned.length - span; origin++) {
        const predictions = forecast(final.model, origin, span, s); let error = 0;
        for (let k = 0; k < span; k++) error += series.cleaned[origin + k] - predictions[k]; squaredErrors += error * error;
    }
    const safety = service * Math.sqrt(squaredErrors / (series.cleaned.length - span - s.cvStart + 1)), reviews = new Set<number>(); let lastReview = 1;
    for (let k = 1; k - 1 + span <= s.horizon; k += review) { reviews.add(k); lastReview = k; }
    const end = lastReview - 1 + span, receipts = new Map<number, number>();
    const lines = [`series ${series.name} method ${final.model.name}`, `policy on_hand ${onHand} lead_time ${leadTime} review ${review} service ${real(service)} safety_stock ${real(safety)}`];
    let stock = onHand, pending = 0, orders = 0, ordered = 0, shortPeriods = 0, minimum = 0, totalStock = 0;
    for (let k = 1; k <= end; k++) {
        const receipt = receipts.get(k) ?? 0, row = final.rows[k - 1]; stock += receipt; pending -= receipt;
        if (reviews.has(k)) {
            const position = stock + pending, target = sum(final.rows.slice(k - 1, k - 1 + span).map(r => r.forecast)) + safety, quantity = Math.max(0, Math.ceil(target - position));
            if (quantity > 0) { receipts.set(k + leadTime, quantity); pending += quantity; orders++; ordered += quantity; }
            lines.push(`review ${row.period} position ${real(position)} target ${real(target)} order ${quantity}`);
        }
        stock -= row.forecast; const status = stock < 0 ? 'short' : stock < safety ? 'low' : 'ok';
        if (status === 'short') shortPeriods++; if (k === 1 || stock < minimum) minimum = stock; totalStock += stock;
        lines.push(`period ${row.period} demand ${real(row.forecast)} receipt ${receipt} on_hand ${real(stock)} status ${status}`);
    }
    lines.push(`summary orders ${orders} ordered ${ordered} short_periods ${shortPeriods} lowest ${real(minimum)} average ${real(totalStock / end)}`); return lines;
}
function yearlyTotals(series: Prepared, future: Prediction[]) {
    interface Year { year: string; actualMonths: number; actual: number; forecastMonths: number; forecast: number }
    const years = new Map<string, Year>();
    const getYear = (period: string) => { const year = period.slice(0, 4); let entry = years.get(year); if (!entry) { entry = { year, actualMonths: 0, actual: 0, forecastMonths: 0, forecast: 0 }; years.set(year, entry); } return entry; };
    for (let t = 0; t < series.values.length; t++) { const e = getYear(series.periods[t]); e.actualMonths++; e.actual += series.values[t]; }
    for (const row of future) { const e = getYear(row.period); e.forecastMonths++; e.forecast += row.forecast; }
    const lines: string[] = []; let previous: { months: number; total: number } | null = null;
    for (const year of [...years.keys()].sort()) {
        const e = years.get(year)!, total = e.actual + e.forecast, months = e.actualMonths + e.forecastMonths;
        const growth = previous && months === 12 && previous.months === 12 ? real(100 * (total - previous.total) / previous.total) : 'NA';
        lines.push(`year ${year} actual_months ${e.actualMonths} actual ${real(e.actual)} forecast_months ${e.forecastMonths} forecast ${real(e.forecast)} total ${real(total)} growth ${growth}`); previous = { months, total };
    }
    return lines;
}
function residualDiagnostics(model: Method) {
    const count = model.residuals.length, average = mean(model.residuals); let second = 0, third = 0, fourth = 0, successive = 0;
    for (let i = 0; i < count; i++) {
        const d = model.residuals[i] - average; second += d * d; third += d * d * d; fourth += d * d * d * d;
        if (i > 0) { const e = model.residuals[i] - model.residuals[i - 1]; successive += e * e; }
    }
    const m2 = second / count, m3 = third / count, m4 = fourth / count, sd = Math.sqrt(second / (count - 1)), dw = successive / model.sse;
    const skewness = m3 / (m2 * Math.sqrt(m2)), kurtosis = m4 / (m2 * m2) - 3, jb = count / 6 * (skewness * skewness + kurtosis * kurtosis / 4);
    return `residuals ${model.name} n ${count} mean ${real(average)} sd ${real(sd)} dw ${real(dw)} skewness ${real(skewness)} kurtosis ${real(kurtosis)} jb ${real(jb)}`;
}
function correlationBar(correlation: number, band: number) {
    const bar: string[] = Array(41).fill(' '), boundary = Math.floor(band * 20 + 0.5), length = Math.floor(Math.abs(correlation) * 20 + 0.5);
    bar[20 - boundary] = ':'; bar[20 + boundary] = ':'; bar[20] = '|';
    if (correlation > 0) for (let i = 21; i <= 20 + length; i++) bar[i] = '#'; if (correlation < 0) for (let i = 20 - length; i <= 19; i++) bar[i] = '#';
    return bar.join('');
}
function correlogram(series: Prepared, methods: Method[], s: Settings) {
    const model = methods.find(m => m.name === 'ar')!;
    if (model.name !== 'ar') return [];
    const band = 2 / Math.sqrt(model.differenced.length), lines = [`series ${series.name} difference ${model.difference} n ${model.differenced.length} band ${real(band)}`];
    const correlations: [string, number[]][] = [['acf', model.correlations], ['pacf', model.partial]];
    for (const [name, values] of correlations) for (let k = 1; k <= s.maxLag; k++) { const v = values[k]; lines.push(`${name} ${String(k).padStart(2, ' ')} ${real(v).padStart(7, ' ')} [${correlationBar(v, band)}]${Math.abs(v) > band ? ' *' : ''}`); }
    for (const method of methods) { lines.push(residualDiagnostics(method), `ljung_box ${method.name} ` + ar.ljungBox(method.residuals, s.ljungBox).map(t => `lag ${t.lag} q ${real(t.q)} p ${real(t.p)}`).join(' ')); }
    return lines;
}
function forecastChart(series: Prepared, best: Assessment, final: Final) {
    const rows = [...best.rows, ...final.rows]; let low = rows[0].lo95, high = rows[0].hi95;
    for (const r of rows) { low = Math.min(low, r.lo95); high = Math.max(high, r.hi95); if (r.actual !== null) { low = Math.min(low, r.actual); high = Math.max(high, r.actual); } }
    const column = (v: number) => Math.floor((v - low) / (high - low) * 60 + 0.5), lines = [`chart ${series.name} method ${best.model.name}`, `scale low ${real(low)} high ${real(high)}`];
    for (const row of rows) {
        const chart: string[] = Array(61).fill(' ');
        for (let i = column(row.lo95); i <= column(row.hi95); i++) chart[i] = '-'; for (let i = column(row.lo80); i <= column(row.hi80); i++) chart[i] = '=';
        chart[column(row.forecast)] = 'o'; if (row.actual !== null) chart[column(row.actual)] = '*'; lines.push(`${row.period} |${chart.join('')}|`);
    }
    let peak = 0; for (const v of series.decomposition.mult) peak = Math.max(peak, Math.abs(v - 1)); lines.push('profile peak ' + real(peak));
    for (const [j, v] of series.decomposition.mult.entries()) {
        const chart: string[] = Array(61).fill(' '), length = Math.floor(Math.abs(v - 1) / peak * 30 + 0.5); chart[30] = '|';
        if (v > 1) for (let i = 31; i <= 30 + length; i++) chart[i] = '#'; if (v < 1) for (let i = 30 - length; i <= 29; i++) chart[i] = '#';
        lines.push(`season ${String(j + 1).padStart(2, ' ')} ${real(v)} [${chart.join('')}]`);
    }
    return lines;
}
interface Reports { decomposition: string[]; models: string[]; forecasts: string[]; accuracy: string[]; cv: string[]; correlogram: string[]; chart: string[]; plan: string[] }
function appendReports(reports: Reports, series: Prepared, methods: Method[], members: Method[], assessments: Assessment[], best: Assessment, final: Final, s: Settings) {
    const d = series.decomposition, valueText = (v: number | null) => v === null ? 'NA' : real(v);
    for (let t = 0; t < series.values.length; t++) {
        const flag = series.pastEvents.get(t) ?? (series.missing.has(t) ? 'missing' : series.outliers.has(t) ? 'outlier' : 'ok'), j = t % s.season;
        reports.decomposition.push([series.name, series.periods[t], real(series.values[t]), real(series.cleaned[t]), valueText(d.trend[t]), real(d.add[j]), valueText(d.residualAdd[t]), real(d.mult[j]), valueText(d.residualMult[t]), flag].join(','));
    }
    reports.models.push(`series ${series.name}`, `data observations ${series.values.length} train ${series.values.length - s.holdout} holdout ${s.holdout} missing ${series.missing.size} outliers ${series.outliers.size} events ${series.pastEvents.size}`);
    for (const [kind, e] of series.lifts) reports.models.push(`event ${kind} occurrences ${e.count} lift ${real(e.lift)}`);
    for (const [t, score] of series.outliers) reports.models.push(`outlier ${series.periods[t]} value ${real(series.values[t])} expected ${real(series.cleaned[t])} score ${real(score)}`);
    reports.models.push(`strength trend ${real(series.strengthTrend)} seasonal ${real(series.strengthSeasonal)}`);
    for (const method of methods) reports.models.push(...modelLines(method));
    reports.models.push('combo members ' + members.map(m => m.name).join(' '), `best ${best.model.name} rmse ${real(best.accuracy.rmse)}`);
    for (const method of final.fitted) reports.models.push(...modelLines(method).map(line => 'final ' + line));
    const forecastLine = (stage: string, name: string, r: Prediction) => [series.name, stage, name, r.period, r.actual === null ? 'NA' : r.actual, ...[r.forecast, r.lo80, r.hi80, r.lo95, r.hi95].map(real)].join(',');
    for (const assessment of assessments) {
        const { model, rows, accuracy: a, cv } = assessment;
        for (const row of rows) reports.forecasts.push(forecastLine('holdout', model.name, row));
        reports.accuracy.push([series.name, model.name, ...[a.me, a.mae, a.rmse, a.mape, a.smape, a.mase, a.fva, cv.rmse].map(real), a.cover80, a.cover95, real(a.winkler80), real(a.winkler95), a.rank].join(','));
        for (let k = 0; k < s.horizon; k++) reports.cv.push([series.name, model.name, k + 1, cv.origins[k], real(cv.mae[k]), real(cv.sigma[k])].join(','));
    }
    for (const row of final.rows) reports.forecasts.push(forecastLine('future', best.model.name, row));
    reports.correlogram.push(...correlogram(series, methods, s)); reports.chart.push(...forecastChart(series, best, final)); reports.plan.push(...inventoryPlan(series, final, s), ...yearlyTotals(series, final.rows));
}
function main() {
    const { settings: s, series: inputs } = readInput();
    const reports: Reports = { decomposition: ['series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag'], models: [],
        forecasts: ['series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95'], accuracy: ['series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank'],
        cv: ['series,method,step,origins,mae,rmse'], correlogram: [], chart: [], plan: [] };
    for (const input of inputs) {
        const series = prepareSeries(input, s), training = series.cleaned.slice(0, series.values.length - s.holdout), methods = METHODS.map(name => fitMethod(name, training, s));
        const evaluated: Evaluated[] = methods.map(model => ({ model, cv: crossValidate(model, s) }));
        const selected = evaluation.rank(evaluated.map(e => e.cv.rmse)).slice(0, s.combo).sort((a, b) => a - b), members = selected.map(i => methods[i]);
        const combo: Combo = { name: 'combo', values: training, members }; evaluated.push({ model: combo, cv: crossValidate(combo, s) });
        const delta = evaluation.scale(training, s.season), assessments = evaluated.map(e => assessHoldout(e, series, s, delta));
        for (const a of assessments) a.accuracy.fva = 100 * (assessments[0].accuracy.mae - a.accuracy.mae) / assessments[0].accuracy.mae;
        const ranking = evaluation.rank(assessments.map(a => a.accuracy.rmse)); for (const [i, index] of ranking.entries()) assessments[index].accuracy.rank = i + 1;
        const best = assessments[ranking[0]], final = finalForecast(best, members, series, s); appendReports(reports, series, methods, members, assessments, best, final, s);
    }
    const files: [keyof Reports, string][] = [['decomposition', 'csv'], ['models', 'txt'], ['forecasts', 'csv'], ['accuracy', 'csv'], ['cv', 'csv'], ['correlogram', 'txt'], ['chart', 'txt'], ['plan', 'txt']];
    for (const [name, extension] of files) writeLines(name + '.' + extension, reports[name]);
}
main();
