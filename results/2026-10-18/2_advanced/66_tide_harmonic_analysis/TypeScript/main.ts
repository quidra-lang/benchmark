import { readAll, datetime, hourDatetime, date, type Parameters, type Constituent, type Station, type Observation, type NumericRow } from './records.ts';
import { flatRuns, spikeTests, gaps, type Reason, type PreliminaryRow } from './cleaning.ts';
import { fit, PI, type FitConstituent } from './harmonic_fit.ts';
import { level, gridExtrema, type GridExtremum } from './predict.ts';
import { real as f, plotLines, writeFiles } from './report.ts';

interface ResidualRow extends PreliminaryRow { fitted: number; residual: number }
interface Extremum extends GridExtremum { minute: number; day: number; label: 'HHW' | 'LHW' | 'HLW' | 'LLW' }
interface Daily { day: number; highCount: number; lowCount: number; hhw: number | null; llw: number | null; range: number | null }
interface Surge { type: 'positive' | 'negative'; start: number; end: number; peak: number; peakTime: number }
interface EstimatedConstituent extends FitConstituent { amplitudeError: number; phaseError: number; snr: number; significant: string }
type Cleaned = ReturnType<typeof checkStation>;
type Fitted = ReturnType<typeof finalFit>;
type Predicted = ReturnType<typeof predictions>;
type StationResult = ReturnType<typeof analyzeStation>;
function sum(values: number[]): number { let total = 0; for (const value of values) total += value; return total; }
const mean = (values: number[]): number => sum(values) / values.length;
function choose<T>(items: T[], value: (item: T) => number, largest = true): T | null { let best: T | null = null; for (const item of items) if (best === null || (largest ? value(item) > value(best) : value(item) < value(best))) best = item; return best; }
function selectConstituents(constituents: Constituent[], length: number, rayleigh: number) {
    const selected: Constituent[] = [], statuses = new Map<string, string>();
    for (const c of constituents) {
        if (c.speed * length < 360 * rayleigh) { statuses.set(c.name, 'short'); continue; }
        const conflict = selected.find(other => Math.abs(c.speed - other.speed) * length < 360 * rayleigh);
        if (conflict) statuses.set(c.name, 'conflict:' + conflict.name); else { statuses.set(c.name, 'fitted'); selected.push(c); }
    }
    return { selected, statuses };
}
function checkStation(station: Station, rows: Observation[], constituents: Constituent[], params: Parameters) {
    const numeric = rows.filter((row): row is NumericRow => row.value !== null), first = numeric[0].time, last = numeric.at(-1)!.time, length = last - first;
    const byTime = new Map(rows.map(row => [row.time, row])), reasons = new Map<number, Reason>();
    for (let t = first; t <= last; t++) { if (!byTime.has(t)) reasons.set(t, 'absent'); else if (byTime.get(t)!.value === null) reasons.set(t, 'na'); }
    const flats = flatRuns(numeric, params.flatRun); for (const run of flats) for (let t = run.start + 1; t <= run.end; t++) reasons.set(t, 'flat');
    const candidateRows = numeric.filter(row => !reasons.has(row.time)), selection = selectConstituents(constituents, length, params.rayleigh), preliminary = fit(candidateRows, selection.selected);
    const candidates = candidateRows.map(row => ({ ...row, preliminary: row.value - level(preliminary, row.time) })), prefitRms = Math.sqrt(sum(candidates.map(row => row.preliminary * row.preliminary)) / candidates.length);
    const { tested, spikes } = spikeTests(candidates, params.spike); for (const spike of spikes) reasons.set(spike.time, 'spike');
    const usable = candidates.filter(row => !reasons.has(row.time)), counts = { rows: rows.length, numeric: numeric.length, na: 0, absent: 0, flat: 0, spikes: 0, usable: usable.length };
    for (const reason of reasons.values()) counts[reason === 'spike' ? 'spikes' : reason]++;
    return { ...station, first, last, length, selection, candidates, usable, counts, flats, prefitRms, tested, spikes, gaps: gaps(first, last, reasons) };
}
function finalFit(station: Cleaned, params: Parameters) {
    const model = fit(station.usable, station.selection.selected), residuals = new Map<number, number>(); let squares = 0, maxAbs = 0;
    const usable: ResidualRow[] = station.usable.map(row => { const fitted = level(model, row.time), residual = row.value - fitted; residuals.set(row.time, residual); squares += residual * residual; maxAbs = Math.max(maxAbs, Math.abs(residual)); return { ...row, fitted, residual }; });
    const dof = usable.length - model.unknowns, variance = squares / dof, observedMean = mean(usable.map(row => row.value)); let centeredSquares = 0, lagProduct = 0, lagSquares = 0;
    for (const row of usable) { const difference = row.value - observedMean; centeredSquares += difference * difference; if (residuals.has(row.time + 1)) { lagProduct += row.residual * residuals.get(row.time + 1)!; lagSquares += row.residual * row.residual; } }
    const fittedConstituents = new Map<string, EstimatedConstituent>(model.constituents.map((c, i): [string, EstimatedConstituent] => {
        const { a, b, amplitude } = c, ia = 2 * i + 1, ib = 2 * i + 2, va = variance * model.inverse[ia][ia], vb = variance * model.inverse[ib][ib], cab = variance * model.inverse[ia][ib];
        const amplitudeError = Math.sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amplitude;
        const phaseError = Math.sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amplitude * amplitude) * 180 / PI, ratio = amplitude / amplitudeError, snr = ratio * ratio;
        return [c.name, { ...c, amplitudeError, phaseError, snr, significant: snr >= params.snrMin ? 'yes' : 'no' }];
    }));
    const statistics = { dof, rms: Math.sqrt(squares / usable.length), maxAbs, explained: 100 * (1 - squares / centeredSquares), lag1: lagProduct / lagSquares };
    const top = usable.toSorted((a, b) => Math.abs(b.residual) - Math.abs(a.residual) || a.time - b.time).slice(0, params.topResiduals);
    return { ...station, usable, model, fittedConstituents, residuals, statistics, top };
}
function predictions(station: Fitted, params: Parameters) {
    const hourly = Array.from({ length: params.hours + 1 }, (_, i) => level(station.model, params.start + i)), raw = gridExtrema(station.model, params.start, params.hours, params.grid), rawExtrema = raw.length;
    while (raw.length >= 2) { let pair = 0, difference = Math.abs(raw[0].height - raw[1].height); for (let i = 1; i + 1 < raw.length; i++) { const candidate = Math.abs(raw[i].height - raw[i + 1].height); if (candidate < difference) { difference = candidate; pair = i; } } if (difference >= params.minRange) break; raw.splice(pair, 2); }
    const extrema: Extremum[] = raw.map(e => { const minute = Math.floor(e.refinedMinute + 0.5); return { ...e, minute, day: Math.floor(minute / 1440), label: e.kind === 'high' ? 'LHW' : 'HLW' }; });
    const byDay = new Map<number, { highs: Extremum[]; lows: Extremum[] }>();
    for (const e of extrema) { let group = byDay.get(e.day); if (!group) { group = { highs: [], lows: [] }; byDay.set(e.day, group); } group[e.kind === 'high' ? 'highs' : 'lows'].push(e); }
    for (const group of byDay.values()) { const high = choose(group.highs, e => e.height), low = choose(group.lows, e => e.height, false); if (high) high.label = 'HHW'; if (low) low.label = 'LLW'; }
    const daily: Daily[] = [];
    for (let offset = 0; offset < params.hours / 24; offset++) {
        const day = params.start / 24 + offset, group = byDay.get(day) ?? { highs: [], lows: [] }, high = choose(group.highs, e => e.height), low = choose(group.lows, e => e.height, false), hhw = high?.height ?? null, llw = low?.height ?? null;
        daily.push({ day, highCount: group.highs.length, lowCount: group.lows.length, hhw, llw, range: hhw === null || llw === null ? null : hhw - llw });
    }
    return { ...station, predictions: hourly, rawExtrema, extrema, highs: extrema.filter(e => e.kind === 'high'), lows: extrema.filter(e => e.kind === 'low'), daily };
}
function validation(station: Fitted, constituents: Constituent[], params: Parameters) {
    const split = station.first + Math.floor(station.length / 2), training = station.usable.filter(row => row.time <= split), test = station.usable.filter(row => row.time > split);
    const selection = selectConstituents(constituents, training.at(-1)!.time - training[0].time, params.rayleigh), model = fit(training, selection.selected), observedMean = mean(test.map(row => row.value)); let squares = 0, inSample = 0, centeredSquares = 0;
    for (const row of test) { const error = row.value - level(model, row.time), centered = row.value - observedMean; squares += error * error; inSample += row.residual * row.residual; centeredSquares += centered * centered; }
    return { split, train: training.length, test: test.length, constituents: selection.selected.length, rms: Math.sqrt(squares / test.length), inSampleRms: Math.sqrt(inSample / test.length), skill: 1 - squares / centeredSquares };
}
function residualEvents(station: Fitted, settings: Parameters['surge']): Surge[] {
    const events: Surge[] = []; let current: Surge | null = null;
    const finish = (): void => { if (current !== null && current.end - current.start + 1 >= settings.hours) events.push(current); current = null; };
    for (const row of station.usable) {
        const type = row.residual > settings.threshold ? 'positive' : row.residual < -settings.threshold ? 'negative' : null;
        if (current !== null && (type !== current.type || row.time !== current.end + 1)) finish(); if (type === null) continue;
        if (current === null) current = { type, start: row.time, end: row.time, peak: row.residual, peakTime: row.time };
        else { current.end = row.time; if (type === 'positive' ? row.residual > current.peak : row.residual < current.peak) { current.peak = row.residual; current.peakTime = row.time; } }
    }
    finish(); return events;
}
function dailyMeans(station: Fitted) {
    const weights = [0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1], usable = new Map(station.usable.map(row => [row.time, row.value])), filledLevels: number[] = [];
    for (let t = station.first; t <= station.last; t++) filledLevels.push(usable.has(t) ? usable.get(t)! : level(station.model, t));
    const days: { day: number; level: number; filled: number }[] = [];
    for (let day = Math.floor(station.first / 24); day <= Math.floor(station.last / 24); day++) {
        const noon = day * 24 + 12; if (noon - 19 < station.first || noon + 19 > station.last) continue; let total = 0, filled = 0;
        for (let j = -19; j <= 19; j++) { const time = noon + j; total += weights[Math.abs(j)] * filledLevels[time - station.first]; if (!usable.has(time)) filled++; } days.push({ day, level: total / 30, filled });
    }
    const average = mean(days.map(d => d.level)), firstDay = days[0].day, meanDay = mean(days.map(d => d.day - firstDay)); let numerator = 0, denominator = 0;
    for (const d of days) { const x = d.day - firstDay - meanDay; numerator += x * (d.level - average); denominator += x * x; }
    return { days, average, slope: 1000 * (numerator / denominator), maximum: choose(days, d => d.level)!, minimum: choose(days, d => d.level, false)! };
}
function tidalCharacteristics(station: Predicted, params: Parameters) {
    const m2 = station.fittedConstituents.get('M2')!, s2 = station.fittedConstituents.get('S2')!, k1 = station.fittedConstituents.get('K1')!, o1 = station.fittedConstituents.get('O1')!, m4 = station.fittedConstituents.get('M4')!;
    const form = (k1.amplitude + o1.amplitude) / (m2.amplitude + s2.amplitude), type = form < 0.25 ? 'semidiurnal' : form < 1.5 ? 'mixed_semidiurnal' : form < 3 ? 'mixed_diurnal' : 'diurnal';
    const mhhw = mean(station.daily.filter(d => d.hhw !== null).map(d => d.hhw!)), mllw = mean(station.daily.filter(d => d.llw !== null).map(d => d.llw!)), mhw = mean(station.highs.map(e => e.height)), mlw = mean(station.lows.map(e => e.height)), amplitudes = sum(station.model.constituents.map(c => c.amplitude));
    const complete = station.daily.filter(d => d.range !== null), rises: number[] = [], falls: number[] = [];
    for (let i = 1; i < station.extrema.length; i++) { const a = station.extrema[i - 1], b = station.extrema[i]; if (a.kind === 'low' && b.kind === 'high') rises.push(b.minute - a.minute); if (a.kind === 'high' && b.kind === 'low') falls.push(b.minute - a.minute); }
    let relativePhase = 2 * m2.phase - m4.phase; while (relativePhase < 0) relativePhase += 360; while (relativePhase >= 360) relativePhase -= 360;
    const above = station.predictions.filter(v => v > mhhw).length, below = station.predictions.filter(v => v < mllw).length;
    return { form, type, spring: 2 * (m2.amplitude + s2.amplitude), neap: 2 * (m2.amplitude - s2.amplitude), mhhw, mllw, mhw, mlw, mtl: (mhw + mlw) / 2, dtl: (mhhw + mllw) / 2, mn: mhw - mlw, gt: mhhw - mllw,
        hat: station.model.mean + amplitudes, lat: station.model.mean - amplitudes, highest: choose(station.highs, e => e.height)!, lowest: choose(station.lows, e => e.height, false)!, widest: choose(complete, d => d.range!)!, narrowest: choose(complete, d => d.range!, false)!,
        above: 100 * above / (params.hours + 1), below: 100 * below / (params.hours + 1), rise: mean(rises), fall: mean(falls), m4Ratio: m4.amplitude / m2.amplitude, relativePhase, dominance: relativePhase < 180 ? 'flood' : 'ebb' };
}
function springNeap(station: Fitted, params: Parameters) {
    const m2 = station.fittedConstituents.get('M2')!, s2 = station.fittedConstituents.get('S2')!, dw = s2.speed - m2.speed, dg = s2.phase - m2.phase, qa = (dw * params.start - dg) / 180, qb = (dw * (params.start + params.hours) - dg) / 180, events: { type: string; minute: number }[] = [];
    for (let q = Math.floor(Math.min(qa, qb)) - 1; q <= Math.ceil(Math.max(qa, qb)) + 1; q++) { const time = (dg + 180 * q) / dw; if (params.start <= time && time <= params.start + params.hours) events.push({ type: q % 2 === 0 ? 'spring' : 'neap', minute: Math.floor(time * 60 + 0.5) }); }
    return events;
}
function analyzeStation(source: Station, rows: Observation[], constituents: Constituent[], params: Parameters) {
    const station = predictions(finalFit(checkStation(source, rows, constituents, params), params), params);
    return { ...station, validation: validation(station, constituents, params), events: residualEvents(station, params.surge), dailyMeans: dailyMeans(station), characteristics: tidalCharacteristics(station, params), springNeap: springNeap(station, params) };
}
function cleaningLines(s: StationResult, p: Parameters): string[] {
    const dt = (t: number): string => hourDatetime(p.epoch, t), c = s.counts;
    const lines = [`station=${s.code} name=${s.name}`, `span start=${dt(s.first)} end=${dt(s.last)} hours=${s.length + 1} record_length=${s.length}`, `counts rows=${c.rows} numeric=${c.numeric} na=${c.na} absent=${c.absent} flat=${c.flat} spikes=${c.spikes} usable=${c.usable}`];
    for (const run of s.flats) lines.push(`flat start=${dt(run.start)} end=${dt(run.end)} value=${f(run.value, 3)} removed=${run.end - run.start}`);
    lines.push(`spike_test window=${p.spike.window} candidates=${s.candidates.length} tested=${s.tested} prefit_rms=${f(s.prefitRms, 4)}`);
    for (const spike of s.spikes) lines.push(`spike time=${dt(spike.time)} value=${f(spike.value, 3)} residual=${f(spike.residual, 4)} median=${f(spike.median, 4)} mad=${f(spike.mad, 4)} limit=${f(spike.limit, 4)}`);
    for (const gap of s.gaps) lines.push(`gap start=${dt(gap.start)} end=${dt(gap.end)} hours=${gap.end - gap.start + 1} cause=${gap.cause}`); return lines;
}
function constituentLines(s: StationResult, constituents: Constituent[]): string[] {
    return constituents.map(c => { const status = s.selection.statuses.get(c.name)!, prefix = `${s.code},${c.name},${f(c.speed, 7)},${status}`; if (status !== 'fitted') return prefix + ',,,,,,'; const x = s.fittedConstituents.get(c.name)!; return prefix + `,${f(x.amplitude, 4)},${f(x.phase, 2)},${f(x.amplitudeError, 4)},${f(x.phaseError, 2)},${f(x.snr, 1)},${x.significant}`; });
}
function extremeLines(s: StationResult, p: Parameters): string[] {
    const lines = [`station=${s.code} extremes=${s.extrema.length} raw=${s.rawExtrema} removed=${s.rawExtrema - s.extrema.length}`];
    s.extrema.forEach((e, i) => lines.push(`${datetime(p.epoch, e.minute)} ${e.label} ${f(e.height, 3)} change=${i ? f(e.height - s.extrema[i - 1].height, 3) : 'none'}`));
    for (const d of s.daily) lines.push(`day date=${date(p.epoch, d.day)} high_waters=${d.highCount} low_waters=${d.lowCount} hhw=${f(d.hhw, 3)} llw=${f(d.llw, 3)} range=${f(d.range, 3)}`); return lines;
}
function summaryLines(s: StationResult, p: Parameters): string[] {
    const dt = (t: number): string => hourDatetime(p.epoch, t), minute = (m: number): string => datetime(p.epoch, m), day = (d: number): string => date(p.epoch, d), stats = s.statistics, v = s.validation, t = s.characteristics, d = s.dailyMeans;
    const lines = [`[station ${s.code}] ${s.name}`, `record first=${dt(s.first)} last=${dt(s.last)} length=${s.length} usable=${s.usable.length}`, `fit constituents=${s.model.constituents.length} unknowns=${s.model.unknowns} dof=${stats.dof} mean_level=${f(s.model.mean, 4)}`, `residual rms=${f(stats.rms, 4)} max_abs=${f(stats.maxAbs, 4)} explained_percent=${f(stats.explained, 4)} lag1_autocorrelation=${f(stats.lag1, 4)}`];
    s.top.forEach((row, i) => lines.push(`top_residual rank=${i + 1} time=${dt(row.time)} observed=${f(row.value, 3)} fitted=${f(row.fitted, 4)} residual=${f(row.residual, 4)}`));
    lines.push(`validation split=${dt(v.split)} train=${v.train} test=${v.test} constituents=${v.constituents} rms=${f(v.rms, 4)} in_sample_rms=${f(v.inSampleRms, 4)} skill=${f(v.skill, 4)}`,
        `form_number=${f(t.form, 4)} type=${t.type}`, `ranges spring=${f(t.spring, 3)} neap=${f(t.neap, 3)} mn=${f(t.mn, 3)} gt=${f(t.gt, 3)}`,
        `asymmetry rise_minutes=${f(t.rise, 1)} fall_minutes=${f(t.fall, 1)} m4_m2_ratio=${f(t.m4Ratio, 4)} relative_phase=${f(t.relativePhase, 2)} dominance=${t.dominance}`,
        `datums mhhw=${f(t.mhhw, 3)} mhw=${f(t.mhw, 3)} mtl=${f(t.mtl, 3)} dtl=${f(t.dtl, 3)} mlw=${f(t.mlw, 3)} mllw=${f(t.mllw, 3)}`, `bounds hat=${f(t.hat, 3)} lat=${f(t.lat, 3)}`,
        `window high_waters=${s.highs.length} low_waters=${s.lows.length} highest=${f(t.highest.height, 3)} highest_time=${minute(t.highest.minute)} lowest=${f(t.lowest.height, 3)} lowest_time=${minute(t.lowest.minute)}`,
        `daily_range widest=${f(t.widest.range, 3)} widest_date=${day(t.widest.day)} narrowest=${f(t.narrowest.range, 3)} narrowest_date=${day(t.narrowest.day)}`, `exceedance above_mhhw=${f(t.above, 2)} below_mllw=${f(t.below, 2)}`);
    for (const event of s.springNeap) lines.push(`${event.type} time=${minute(event.minute)}`);
    lines.push(`surges count=${s.events.length} threshold=${f(p.surge.threshold, 3)} min_hours=${p.surge.hours}`);
    for (const e of s.events) lines.push(`surge type=${e.type} start=${dt(e.start)} end=${dt(e.end)} hours=${e.end - e.start + 1} peak=${f(e.peak, 4)} peak_time=${dt(e.peakTime)}`);
    lines.push(`daily_mean days=${d.days.length} average=${f(d.average, 4)} slope_mm_per_day=${f(d.slope, 3)} max=${f(d.maximum.level, 4)} max_date=${day(d.maximum.day)} min=${f(d.minimum.level, 4)} min_date=${day(d.minimum.day)}`);
    for (const entry of d.days) lines.push(`daily_mean date=${day(entry.day)} level=${f(entry.level, 4)} filled=${entry.filled}`); return lines;
}
function waterLag(waters: Extremum[], reference: Extremum[]): number {
    let total = 0; for (const water of waters) { let nearest = reference[0]; for (let i = 1; i < reference.length; i++) if (Math.abs(reference[i].minute - water.minute) < Math.abs(nearest.minute - water.minute)) nearest = reference[i]; total += water.minute - nearest.minute; } return total / waters.length;
}
function comparisonLines(stations: StationResult[], p: Parameters): string[] {
    const reference = stations.find(s => s.code === p.reference)!, lines = [`[comparison] reference=${p.reference}`];
    for (const s of stations) {
        if (s === reference) continue;
        lines.push(`${s.code} tide hw_lag_min=${f(waterLag(s.highs, reference.highs), 1)} lw_lag_min=${f(waterLag(s.lows, reference.lows), 1)} range_ratio=${f(s.characteristics.gt / reference.characteristics.gt, 4)} mtl_diff=${f(s.characteristics.mtl - reference.characteristics.mtl, 3)}`);
        for (const name of ['M2', 'S2', 'K1', 'O1']) { const own = s.fittedConstituents.get(name)!, other = reference.fittedConstituents.get(name)!; let phase = own.phase - other.phase; if (phase > 180) phase -= 360; if (phase <= -180) phase += 360; lines.push(`${s.code} ${name} amplitude_ratio=${f(own.amplitude / other.amplitude, 4)} phase_diff=${f(phase, 2)} time_lag_min=${f(phase / own.speed * 60, 1)}`); }
    }
    return lines;
}
function correlation(a: StationResult, b: StationResult, lag: number) {
    const pairs: [number, number][] = []; for (const row of a.usable) if (b.residuals.has(row.time + lag)) pairs.push([row.residual, b.residuals.get(row.time + lag)!]);
    const mx = mean(pairs.map(pair => pair[0])), my = mean(pairs.map(pair => pair[1])); let sxy = 0, sxx = 0, syy = 0;
    for (const pair of pairs) { const x = pair[0] - mx, y = pair[1] - my; sxy += x * y; sxx += x * x; syy += y * y; } return { lag, rho: sxy / Math.sqrt(sxx * syy), pairs: pairs.length };
}
function correlationLines(stations: StationResult[], maximum: number): string[] {
    const lines = [`[correlation] max_lag=${maximum}`];
    for (let i = 0; i < stations.length; i++) for (let j = i + 1; j < stations.length; j++) {
        let best: ReturnType<typeof correlation> | null = null, zero = 0;
        for (let lag = -maximum; lag <= maximum; lag++) { const c = correlation(stations[i], stations[j], lag); if (lag === 0) zero = c.rho; if (best === null || c.rho > best.rho || c.rho === best.rho && (Math.abs(lag) < Math.abs(best.lag) || Math.abs(lag) === Math.abs(best.lag) && lag < best.lag)) best = c; }
        lines.push(`${stations[i].code}-${stations[j].code} lag0=${f(zero, 4)} best_lag=${best!.lag} best=${f(best!.rho, 4)} pairs=${best!.pairs}`);
    }
    return lines;
}
function plot(stations: StationResult[], p: Parameters): string[] {
    const s = stations.find(s => s.code === p.plot.code)!, { hours, top, bottom, step } = p.plot, rows = (top - bottom) / step + 1, cells: string[][] = Array.from({ length: rows }, () => Array(hours).fill(' ')), heights = Array.from({ length: rows }, (_, r) => top - r * step);
    const baseline = Math.floor((top - 100 * s.model.mean) / step + 0.5); if (baseline >= 0 && baseline < rows) cells[baseline].fill('-');
    const marks = new Map<number, string>(); for (const e of s.extrema) { const column = Math.floor((e.minute - 60 * p.start + 30) / 60); if (column >= 0 && column < hours) marks.set(column, e.kind === 'high' ? 'H' : 'L'); }
    for (let c = 0; c < hours; c++) { const row = Math.floor((top - 100 * s.predictions[c]) / step + 0.5); if (row < 0) cells[0][c] = '^'; else if (row >= rows) cells[rows - 1][c] = 'v'; else cells[row][c] = marks.get(c) ?? '*'; }
    return [`[plot] station=${s.code} start=${hourDatetime(p.epoch, p.start)} hours=${hours} step_cm=${step}`, ...plotLines(cells, heights)];
}
function main(): void {
    const { params, constituents, observations } = readAll(), stations = params.stations.map(s => analyzeStation(s, observations.get(s.code)!, constituents, params));
    const cleaning: string[] = [], constants = ['station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant'], extremes: string[] = [], summary: string[] = [], predictions = ['time,' + params.stations.map(s => s.code).join(',')];
    for (const s of stations) { cleaning.push(...cleaningLines(s, params)); constants.push(...constituentLines(s, constituents)); extremes.push(...extremeLines(s, params)); summary.push(...summaryLines(s, params)); }
    for (let i = 0; i <= params.hours; i++) predictions.push(hourDatetime(params.epoch, params.start + i) + ',' + stations.map(s => f(s.predictions[i], 3)).join(','));
    summary.push(...comparisonLines(stations, params), ...correlationLines(stations, params.correlationLag), ...plot(stations, params));
    writeFiles({ 'cleaning.txt': cleaning, 'constituents.csv': constants, 'predictions.csv': predictions, 'extremes.txt': extremes, 'summary.txt': summary });
}
main();
