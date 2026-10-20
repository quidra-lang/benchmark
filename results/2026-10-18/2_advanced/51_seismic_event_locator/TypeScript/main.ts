import { mkdirSync, writeFileSync } from 'node:fs';
import { readInput, type Station, type Parameters } from './waveform_io.ts';
import { detectPicks, type Pick, type PickState } from './picker.ts';
import { associate, type Candidate } from './associator.ts';
import { distance, evaluate, geiger, locationRun, uncertainty, type Point, type Observation } from './locator.ts';
import { median, localMagnitude, durationMagnitude, magnitudeClass, frequencyStatistics } from './magnitude.ts';
type LocationRun = ReturnType<typeof locationRun>;
interface StationState { station: Station; stats: ReturnType<typeof detectPicks>; used: Pick[]; correction: number; magnitudePicks: Pick[]; magnitudeCorrection: number }
interface ProcessedCandidate extends Candidate { pass1: LocationRun; pass2: LocationRun | null; dropped: { pick: Pick; residual: number }[]; remaining: Pick[]; rejected: boolean; event: number | null }
interface FirstEvent { number: number; used: Pick[]; firstStage: LocationRun }
interface Jack { station: Station; dx: number; dy: number; dz: number; shift: number }
interface Event extends FirstEvent { corrected: Observation[]; startRms: number; relocation: ReturnType<typeof geiger>; ellipse: ReturnType<typeof uncertainty>; shift: { dh: number; dz: number }; gap: number; dmin: number; quality: string; jackknife: Jack[]; worstJackknife: Jack; unclipped: Pick[]; ml: number | null; md: number; mlc: number | null; hundredths: number | null; magnitudeClass: number | null; cluster: number }
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);
const timeNotation = (k: number) => Math.floor(k / 100) + '.' + String(k % 100).padStart(2, '0');
const classNotation = (t: number) => (t < 0 ? '-' : '') + Math.floor(Math.abs(t) / 10) + '.' + Math.abs(t) % 10;
function fixed(value: number | null, digits: number) { if (value === null) return '-'; const a = Math.abs(value), text = a >= 1e21 ? BigInt(a).toString() + '.' + '0'.repeat(digits) : a.toFixed(digits); return value < 0 && Number(text) !== 0 ? '-' + text : text; }
const scaled = (v: number, digits: number) => Number(fixed(v, digits).replace('.', ''));
const rms = (v: number[]) => v.length ? Math.sqrt(sum(v.map(x => x * x)) / v.length) : null;
const observation = (pick: Pick): Observation => ({ station: pick.station, time: pick.time, pick });
function processCandidates(candidates: Candidate[], states: Map<Station, StationState>, p: Parameters) {
    const events: FirstEvent[] = [], processed: ProcessedCandidate[] = [];
    for (const c of candidates) {
        c.picks.sort((a, b) => a.station.index - b.station.index);
        const pass1 = locationRun(c.picks.map(observation), p), dropped: { pick: Pick; residual: number }[] = [], remaining: Pick[] = [];
        c.picks.forEach((pick, i) => { if (Math.abs(pass1.residuals[i]) > p.residualLimit) dropped.push({ pick, residual: pass1.residuals[i] }); else remaining.push(pick); });
        const rejected = dropped.length > 0 && remaining.length < p.minStations;
        if (rejected) { for (const pick of c.picks) pick.state = 'rejected'; processed.push({ ...c, pass1, pass2: null, dropped, remaining, rejected, event: null }); continue; }
        const pass2 = dropped.length ? locationRun(remaining.map(observation), p) : null, adopted = pass2 ?? pass1, event: FirstEvent = { number: events.length + 1, used: remaining, firstStage: adopted };
        event.used.forEach((pick, i) => { pick.state = 'used'; pick.event = event.number; pick.firstResidual = adopted.residuals[i]; states.get(pick.station)!.used.push(pick); });
        for (const { pick } of dropped) { pick.state = 'dropped'; pick.event = event.number; }
        events.push(event); processed.push({ ...c, pass1, pass2, dropped, remaining, rejected, event: event.number });
    }
    return { events, candidates: processed };
}
function relocate(events: FirstEvent[], states: Map<Station, StationState>, p: Parameters): Event[] {
    for (const s of states.values()) s.correction = s.used.length ? sum(s.used.map(p => p.firstResidual)) / s.used.length : 0;
    return events.map(e => {
        const corrected = e.used.map(pick => ({ ...observation(pick), time: pick.time - states.get(pick.station)!.correction })), startRms = evaluate(e.firstStage.point, corrected, p.velocity).rms, relocation = geiger(e.firstStage.point, corrected, p.velocity), point = relocation.point, ellipse = uncertainty(point, corrected, p.velocity);
        e.used.forEach((pick, i) => pick.residual = relocation.residuals[i]);
        const dx = point.x - e.firstStage.point.x, dy = point.y - e.firstStage.point.y, shift = { dh: Math.sqrt(dx * dx + dy * dy), dz: point.z - e.firstStage.point.z }, azimuths: number[] = [], horizontal: number[] = [];
        for (const pick of e.used) { const x = pick.station.x - point.x, y = pick.station.y - point.y; let az = Math.atan2(x, y) * 180 / 3.141592653589793; if (az < 0) az += 360; azimuths.push(az); horizontal.push(Math.sqrt(x * x + y * y)); }
        azimuths.sort((a, b) => a - b); let gap = azimuths[0] + 360 - azimuths[azimuths.length - 1]; for (let i = 1; i < azimuths.length; i++) gap = Math.max(gap, azimuths[i] - azimuths[i - 1]);
        const meets = (limits: number[]) => gap <= limits[0] && relocation.rms <= limits[1] && ellipse.smaj <= limits[2], quality = meets(p.qualityA) ? 'A' : meets(p.qualityB) ? 'B' : 'C';
        const jackknife = e.used.map((pick, i) => { const result = geiger(point, corrected.filter((_, j) => j !== i), p.velocity).point, dx = result.x - point.x, dy = result.y - point.y; return { station: pick.station, dx, dy, dz: result.z - point.z, shift: Math.sqrt(dx * dx + dy * dy) }; });
        let worstJackknife = jackknife[0]; for (const j of jackknife) if (j.shift > worstJackknife.shift) worstJackknife = j;
        return { ...e, corrected, startRms, relocation, ellipse, shift, gap, dmin: Math.min(...horizontal), quality, jackknife, worstJackknife, unclipped: [], ml: null, md: 0, mlc: null, hundredths: null, magnitudeClass: null, cluster: 0 };
    });
}
function computeMagnitudes(events: Event[], states: Map<Station, StationState>, p: Parameters) {
    for (const e of events) {
        e.used.forEach((pick, i) => { pick.distanceKm = e.relocation.distances[i] / 1000; pick.ml = pick.clipped ? null : localMagnitude(pick.amplitude, pick.distanceKm, p.localMagnitude); pick.md = durationMagnitude(pick.duration, pick.distanceKm, p.durationMagnitude); });
        e.unclipped = e.used.filter(p => !p.clipped); e.ml = median(e.unclipped.map(p => p.ml!)); e.md = median(e.used.map(p => p.md))!;
        for (const pick of e.unclipped) pick.mlResidual = pick.ml! - e.ml!;
        e.hundredths = e.ml === null ? null : scaled(e.ml, 2); e.magnitudeClass = e.hundredths === null ? null : magnitudeClass(e.hundredths);
    }
    for (const s of states.values()) { s.magnitudePicks = s.used.filter(p => !p.clipped); s.magnitudeCorrection = s.magnitudePicks.length ? sum(s.magnitudePicks.map(p => p.mlResidual)) / s.magnitudePicks.length : 0; }
    for (const e of events) e.mlc = median(e.unclipped.map(p => p.ml! - states.get(p.station)!.magnitudeCorrection));
}
function travelTimeFit(events: Event[]) {
    const points = events.flatMap(e => e.used.map(p => ({ d: p.distanceKm, t: p.time - e.relocation.point.t0 }))); let sd = 0, st = 0, sdd = 0, sdt = 0;
    for (const p of points) { sd += p.d; st += p.t; sdd += p.d * p.d; sdt += p.d * p.t; }
    const n = points.length, slope = (n * sdt - sd * st) / (n * sdd - sd * sd), intercept = (st - slope * sd) / n; let squares = 0;
    for (const p of points) { const r = p.t - intercept - slope * p.d; squares += r * r; } return { n, velocity: 1000 / slope, intercept, rms: Math.sqrt(squares / n) };
}
function clusterEvents(events: Event[], p: Parameters) {
    const [dl, tl] = p.cluster, neighbors: number[][] = events.map(() => []);
    for (let i = 0; i < events.length; i++) for (let j = i + 1; j < events.length; j++) { const a = events[i].relocation.point, b = events[j].relocation.point, dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z; if (Math.abs(a.t0 - b.t0) <= tl && Math.sqrt(dx * dx + dy * dy + dz * dz) <= dl) { neighbors[i].push(j); neighbors[j].push(i); } }
    const clusters: { number: number; members: Event[]; x: number; y: number; z: number; span: number }[] = [];
    for (let i = 0; i < events.length; i++) {
        if (events[i].cluster) continue; const number = clusters.length + 1, queue = [i]; events[i].cluster = number;
        for (let k = 0; k < queue.length; k++) for (const next of neighbors[queue[k]]) if (!events[next].cluster) { events[next].cluster = number; queue.push(next); }
        queue.sort((a, b) => a - b); const members = queue.map(k => events[k]), points = members.map(e => e.relocation.point);
        clusters.push({ number, members, x: sum(points.map(p => p.x)) / points.length, y: sum(points.map(p => p.y)) / points.length, z: sum(points.map(p => p.z)) / points.length, span: Math.max(...points.map(p => p.t0)) - Math.min(...points.map(p => p.t0)) });
    }
    return clusters;
}
function reassociate(picks: Pick[], events: Event[], states: Map<Station, StationState>, p: Parameters) {
    const sets = events.map(e => new Set(e.used.map(p => p.station))), added: Pick[] = [];
    for (const pick of picks) {
        if (pick.state !== 'unassociated') continue; let best: { i: number; residual: number } | null = null;
        for (const [i, e] of events.entries()) { if (sets[i].has(pick.station)) continue; const point = e.relocation.point, residual = pick.time - point.t0 - distance(point, pick.station) / p.velocity - states.get(pick.station)!.correction; if (Math.abs(residual) <= p.residualLimit && (!best || Math.abs(residual) < Math.abs(best.residual))) best = { i, residual }; }
        if (best) { pick.state = 'added'; pick.event = events[best.i].number; pick.residual = best.residual; sets[best.i].add(pick.station); added.push(pick); }
    }
    return added;
}
function catalogStatistics(events: Event[]) {
    const measured = events.filter(e => e.ml !== null), frequency = frequencyStatistics(measured.map(e => e.magnitudeClass!)), n = measured.length, xbar = sum(measured.map(e => e.md)) / n, ybar = sum(measured.map(e => e.ml!)) / n;
    let xx = 0, xy = 0, yy = 0; for (const e of measured) { const x = e.md - xbar, y = e.ml! - ybar; xx += x * x; xy += x * y; yy += y * y; }
    const slope = xy / xx; return { frequency, measured: n, relation: { n, slope, intercept: ybar - slope * xbar, r: xy / Math.sqrt(xx * yy), meanDifference: ybar - xbar } };
}
const solutionLine = (label: string, point: Point, rms: number) => `${label} x=${fixed(point.x, 1)} y=${fixed(point.y, 1)} z=${fixed(point.z, 1)} t0=${fixed(point.t0, 3)} rms=${fixed(rms, 4)}`;
const iterationLines = (iterations: ReturnType<typeof geiger>['iterations']) => iterations.map((it, i) => solutionLine('ITER ' + (i + 1), it.point, it.rms));
function passLines(pass: LocationRun, number: number, velocity: number) {
    return ['PASS ' + number + ' stations=' + pass.observations.map(o => o.station.code).join(','), solutionLine('GRID', pass.grid.point, pass.grid.rms), 'PROFILE ' + pass.grid.profile.map(v => fixed(v, 4)).join(' '), ...iterationLines(pass.iterations),
        ...pass.observations.map((o, i) => `RES ${o.station.code} dist=${fixed(pass.distances[i], 1)} tt=${fixed(pass.distances[i] / velocity, 4)} obs=${timeNotation(o.pick.sample)} res=${fixed(pass.residuals[i], 4)}`)];
}
function locationsLines(states: Map<Station, StationState>, picks: Pick[], candidates: ProcessedCandidate[], events: Event[], fit: ReturnType<typeof travelTimeFit>, clusters: ReturnType<typeof clusterEvents>, added: Pick[], p: Parameters) {
    const lines: string[] = [];
    for (const c of candidates) { lines.push(`CANDIDATE ${c.number} picks=${c.picks.length} first=${timeNotation(c.first.sample)}`, ...passLines(c.pass1, 1, p.velocity)); for (const item of c.dropped) lines.push(`DROP ${item.pick.station.code} res=${fixed(item.residual, 4)}`); if (c.rejected) lines.push('RESULT REJECTED stations=' + c.remaining.length); else { if (c.pass2) lines.push(...passLines(c.pass2, 2, p.velocity)); lines.push('RESULT EVENT ' + c.event); } }
    lines.push('CORRECTIONS'); for (const s of states.values()) lines.push(`${s.station.code} n=${s.used.length} correction=${fixed(s.correction, 4)}`);
    for (const e of events) {
        lines.push('EVENT ' + e.number, solutionLine('START', e.firstStage.point, e.startRms), ...iterationLines(e.relocation.iterations));
        e.used.forEach((pick, i) => { const d = e.relocation.distances[i]; lines.push(`RES ${pick.station.code} dist=${fixed(d, 1)} tt=${fixed(d / p.velocity, 4)} obs=${timeNotation(pick.sample)} corr=${fixed(states.get(pick.station)!.correction, 4)} res=${fixed(pick.residual, 4)}`); });
        const el = e.ellipse;
        lines.push(`ELLIPSE smaj=${fixed(el.smaj, 1)} smin=${fixed(el.smin, 1)} az=${fixed(el.az, 1)} erz=${fixed(el.erz, 1)} ert=${fixed(el.ert, 4)}`, `SHIFT dh=${fixed(e.shift.dh, 1)} dz=${fixed(e.shift.dz, 1)}`, `GAP ${fixed(e.gap, 1)} DMIN ${fixed(e.dmin, 1)} QUALITY ${e.quality}`);
        for (const j of e.jackknife) lines.push(`JACK ${j.station.code} dx=${fixed(j.dx, 1)} dy=${fixed(j.dy, 1)} dz=${fixed(j.dz, 1)} shift=${fixed(j.shift, 1)}`);
        lines.push(`JACKKNIFE max=${fixed(e.worstJackknife.shift, 1)} station=${e.worstJackknife.station.code}`);
    }
    lines.push(`FIT n=${fit.n} velocity=${fixed(fit.velocity, 1)} intercept=${fixed(fit.intercept, 4)} rms=${fixed(fit.rms, 4)}`);
    for (const c of clusters) if (c.members.length >= 2) lines.push(`CLUSTER ${c.number} events=${c.members.map(e => e.number).join(',')} x=${fixed(c.x, 1)} y=${fixed(c.y, 1)} z=${fixed(c.z, 1)} span=${fixed(c.span, 3)}`);
    lines.push('ADDED'); for (const pick of added) lines.push(`${pick.station.code} sample=${pick.sample} event=${pick.event} res=${fixed(pick.residual, 4)}`);
    const depths = events.map(e => e.relocation.point.z), quality = (q: string) => events.filter(e => e.quality === q).length;
    lines.push(`SUMMARY picks=${picks.length} candidates=${candidates.length} events=${events.length} rejected=${candidates.filter(c => c.rejected).length} unassociated=${picks.filter(p => p.state === 'unassociated').length}`,
        `DEPTH min=${fixed(Math.min(...depths), 1)} median=${fixed(median(depths), 1)} max=${fixed(Math.max(...depths), 1)}`, `QUALITY A=${quality('A')} B=${quality('B')} C=${quality('C')} mean_rms=${fixed(sum(events.map(e => e.relocation.rms)) / events.length, 4)}`); return lines;
}
function picksLines(picks: Pick[]) { return ['station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual', ...picks.map(p => [p.station.code, p.sample, timeNotation(p.sample), p.duration, fixed(p.snr, 2), p.amplitude, p.clipped ? 'yes' : 'no', p.event ?? 0, p.state, p.state === 'used' || p.state === 'added' ? fixed(p.residual, 4) : '-'].join(','))]; }
function catalogLines(events: Event[]) { return ['event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster', ...events.map(e => { const p = e.relocation.point, el = e.ellipse; return [e.number, fixed(p.t0, 3), fixed(p.x, 1), fixed(p.y, 1), fixed(p.z, 1), fixed(e.relocation.rms, 4), e.used.length, fixed(e.gap, 1), fixed(e.dmin, 1), fixed(el.smaj, 1), fixed(el.smin, 1), fixed(el.az, 1), fixed(el.erz, 1), fixed(e.ml, 2), fixed(e.md, 2), e.quality, e.cluster].join(','); })]; }
const chartGrid = (w: number, h: number): string[][] => Array.from({ length: h }, () => Array(w).fill(' '));
function framed(grid: string[][]) { const border = '+' + '-'.repeat(grid[0].length) + '+'; return [border, ...grid.map(r => '|' + r.join('') + '|'), border]; }
function timelineLines(events: Event[], p: Parameters) {
    const [duration, width, low, high, height] = p.timeline, grid = chartGrid(width, height);
    for (const e of events) { if (e.ml === null) continue; const time = scaled(e.relocation.point.t0, 3), h = e.hundredths!; if (time < 0 || time >= 1000 * duration || h < 100 * low) continue; const col = Math.floor(time * width / (1000 * duration)), level = Math.min(Math.floor((h - 100 * low) * height / (100 * (high - low))), height - 1); for (let k = 0; k <= level; k++) { const row = height - 1 - k; if (k === level) grid[row][col] = 'o'; else if (grid[row][col] === ' ') grid[row][col] = '|'; } }
    return [`TIMELINE t=0..${duration} ML=${low}..${high}`, ...framed(grid)];
}
function magnitudesLines(events: Event[], stats: ReturnType<typeof catalogStatistics>, p: Parameters) {
    const lines: string[] = [];
    for (const e of events) { lines.push(`EVENT ${e.number} ML=${fixed(e.ml, 2)} n=${e.unclipped.length} MD=${fixed(e.md, 2)}`); for (const pick of e.used) lines.push(`${pick.station.code} r=${fixed(pick.distanceKm, 3)} amp=${pick.amplitude}` + (pick.clipped ? ' clipped' : ` ml=${fixed(pick.ml, 2)} res=${fixed(pick.mlResidual, 2)}`) + ` dur=${pick.duration} md=${fixed(pick.md, 2)}`); }
    lines.push('CORRECTED', ...events.map(e => `EVENT ${e.number} MLC=${fixed(e.mlc, 2)}`), 'FMD');
    const f = stats.frequency; let cumulative = stats.measured; for (let t = f.minimum; t <= f.maximum; t++) { const count = f.frequencies.get(t) ?? 0; lines.push(`M=${classNotation(t)} N=${count} CUM=${cumulative}`); cumulative -= count; }
    const r = stats.relation; lines.push('MC ' + classNotation(f.completeness), `BVALUE ${fixed(f.b, 3)} SIGMA ${fixed(f.sigma, 3)} N ${f.count}`, 'AVALUE ' + fixed(f.a, 3), `MLMD n=${r.n} slope=${fixed(r.slope, 3)} intercept=${fixed(r.intercept, 3)} r=${fixed(r.r, 3)} mean_diff=${fixed(r.meanDifference, 3)}`, ...timelineLines(events, p)); return lines;
}
function stationsLines(states: Map<Station, StationState>) {
    const lines: string[] = [];
    for (const s of states.values()) {
        const station = s.station, stats = s.stats, count = (state: PickState) => stats.picks.filter(p => p.state === state).length;
        lines.push(`STATION ${station.code} x=${station.x} y=${station.y} elevation=${station.elevation}`, `SAMPLES start=${station.start} count=${station.samples.length} mean=${stats.mean} noise=${fixed(stats.noise, 1)} peak=${stats.peak} clipped=${stats.clippedSamples}`,
            `TRIGGERS total=${stats.triggers} short=${stats.shortTriggers} picks=${stats.picks.length}`, `PICKS used=${count('used')} dropped=${count('dropped')} added=${count('added')} rejected=${count('rejected')} unassociated=${count('unassociated')}`,
            `RESIDUALS n=${s.used.length} rms=${fixed(rms(s.used.map(p => p.firstResidual)), 4)} correction=${fixed(s.correction, 4)} after=${fixed(rms(s.used.map(p => p.residual!)), 4)}`, `MAGNITUDES n=${s.magnitudePicks.length} correction=${fixed(s.magnitudeCorrection, 2)}`);
    }
    return lines;
}
function mapLines(stations: Station[], events: Event[], p: Parameters) {
    const [xmin, xmax, ymin, ymax] = p.mapArea, [w, mh] = p.mapSize, [zmax, sh] = p.section, map = chartGrid(w, mh), ew = chartGrid(w, sh), ns = chartGrid(w, sh);
    const inX = (x: number) => 10 * xmin <= x && x < 10 * xmax, inY = (y: number) => 10 * ymin <= y && y < 10 * ymax, xCol = (x: number) => Math.floor((x - 10 * xmin) * w / (10 * (xmax - xmin))), yCol = (y: number) => Math.floor((y - 10 * ymin) * w / (10 * (ymax - ymin)));
    type Position = [number, number] | null;
    const mapPosition = (x: number, y: number): Position => inX(x) && inY(y) ? [xCol(x), mh - 1 - Math.floor((y - 10 * ymin) * mh / (10 * (ymax - ymin)))] : null;
    const priority = ' ?.oO@^';
    const place = (grid: string[][], position: Position, symbol: string) => { if (!position) return; const [x, y] = position; if (priority.indexOf(symbol) > priority.indexOf(grid[y][x])) grid[y][x] = symbol; };
    const eventPositions = events.map(e => {
        const point = e.relocation.point, x = scaled(point.x, 1), y = scaled(point.y, 1), z = scaled(point.z, 1), h = e.hundredths, symbol = h === null ? '?' : h < 100 ? '.' : h < 200 ? 'o' : h < 300 ? 'O' : '@';
        const m = mapPosition(x, y), a: Position = inX(x) && z < 10 * zmax ? [xCol(x), Math.floor(z * sh / (10 * zmax))] : null, b: Position = inY(y) && z < 10 * zmax ? [yCol(y), Math.floor(z * sh / (10 * zmax))] : null;
        place(map, m, symbol); place(ew, a, symbol); place(ns, b, symbol); return { e, symbol, map: m, ew: a, ns: b };
    });
    const stationPositions = stations.map(station => { const position = mapPosition(10 * station.x, 10 * station.y); place(map, position, '^'); return { station, position }; }), text = (position: Position) => position ? position.join(',') : 'outside';
    return [`MAP x=${xmin}..${xmax} y=${ymin}..${ymax}`, ...framed(map), `SECTION EW x=${xmin}..${xmax} z=0..${zmax}`, ...framed(ew), `SECTION NS y=${ymin}..${ymax} z=0..${zmax}`, ...framed(ns), 'LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML',
        ...stationPositions.map(s => `STATION ${s.station.code} map=${text(s.position)}`), ...eventPositions.map(i => `EVENT ${i.e.number} ${i.symbol} map=${text(i.map)} ew=${text(i.ew)} ns=${text(i.ns)}`)];
}
function main() {
    const { stations, params } = readInput(), states = new Map<Station, StationState>();
    for (const station of stations) states.set(station, { station, stats: detectPicks(station, params), used: [], correction: 0, magnitudePicks: [], magnitudeCorrection: 0 });
    const picks = [...states.values()].flatMap(s => s.stats.picks).sort((a, b) => a.sample - b.sample || a.station.index - b.station.index), processed = processCandidates(associate(picks, params.associationWindow, params.minStations), states, params), events = relocate(processed.events, states, params);
    computeMagnitudes(events, states, params); const fit = travelTimeFit(events), clusters = clusterEvents(events, params), added = reassociate(picks, events, states, params), stats = catalogStatistics(events);
    const outputs: [string, string[]][] = [['picks.csv', picksLines(picks)], ['locations.txt', locationsLines(states, picks, processed.candidates, events, fit, clusters, added, params)], ['catalog.csv', catalogLines(events)], ['magnitudes.txt', magnitudesLines(events, stats, params)], ['stations.txt', stationsLines(states)], ['map.txt', mapLines(stations, events, params)]];
    mkdirSync('output', { recursive: true }); for (const [name, lines] of outputs) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}
main();
