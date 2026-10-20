import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import * as matrix from './matrix.ts';
import * as kalman from './kalman.ts';
import type { Position, MotionModel, Estimate, HistoryEntry } from './kalman.ts';
import { optimal } from './association.ts';
import type { Costs, Pair } from './association.ts';
import * as imm from './imm.ts';
import type { ImmParameters } from './imm.ts';
import { distance, fixed as f, continuity, ospa } from './evaluation.ts';

type Filter = 'cv' | 'ca' | 'abg' | 'imm' | 'rts';
const FILTERS: Filter[] = ['cv', 'ca', 'abg', 'imm', 'rts'];
const CHARACTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
interface Parameters extends ImmParameters {
  model: MotionModel; qCV: number; qCA: number; gate: number; confirm: number[]; delete: number; abg: number[];
  matchDistance: number; cutoff: number; consistencyBound: number; nisEdges: number[]; plotX: number[]; plotY: number[]; plotSize: number[];
}
interface Scan { number: number; time: number; points: Position[] }
interface Truth { number: number; first: number; last: number; positions: Map<number, Position> }
interface MeasurementRecord { measurement: Position | null; nis: number | null }
type Status = 'tentative' | 'confirmed' | 'deleted';
interface Track {
  number: number; birth: number; end: number; confirmation: number | null; deletion: number | null;
  status: Status; hits: number; consecutive: number; estimate: Estimate; records: MeasurementRecord[];
}
interface FilterStates { states: number[][] }
interface KalmanRun extends FilterStates { history: HistoryEntry[]; logLikelihood: number }
interface ComparedFilters { cv: KalmanRun; ca: KalmanRun; abg: FilterStates; imm: FilterStates & { high: number[] }; rts: FilterStates }
interface Segment { first: number; last: number; target: number }
interface TargetErrors { common: number; velocityCount: number; position: number[]; velocity: number[]; nees: number[] }
interface Target extends Truth {
  count: number; path: number; meanSpeed: number; velocities: Map<number, Position>; track: EvaluatedTrack | null; errors: TargetErrors | null;
}
interface EvaluatedTrack extends Track {
  character: string; sequence: MeasurementRecord[]; nis: number[]; misses: number; longestGap: number; filters: ComparedFilters; path: number;
  scanTargets: (number | null)[]; matchedScans: number; segments: Segment[]; match: { target: Target; cost: number; common: number } | null;
  high: { mean: number; maximum: number; scan: number; count: number; segments: Segment[] };
}
function sum(values: number[]): number {
  if (values.length === 0) return 0;
  let total = values[0]; for (let i = 1; i < values.length; i++) total += values[i]; return total;
}
const mean = (values: number[]) => sum(values) / values.length;
const absent = (value: number | null) => value === null ? '-' : value;
const listLine = (name: string, values: (number | string)[]) => name + ' ' + (values.length ? values.join(' ') : 'none');
const primaryFilter = (p: Parameters): 'cv' | 'ca' => p.model === 'CV' ? 'cv' : 'ca';
function readInputs() {
  const scans: Scan[] = [], targetMap = new Map<number, Truth>();
  const readLines = (name: string) => readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
  for (const line of readLines('measurements.csv').slice(1)) {
    const [scan, time, x, y] = line.split(',').map(Number);
    if (!scans[scan - 1]) scans[scan - 1] = { number: scan, time, points: [] };
    scans[scan - 1].points.push([x, y]);
  }
  for (const line of readLines('truth.csv').slice(1)) {
    const [number, scan, x, y] = line.split(',').map(Number);
    let target = targetMap.get(number);
    if (target === undefined) { target = { number, first: scan, last: scan, positions: new Map() }; targetMap.set(number, target); }
    target.positions.set(scan, [x, y]); target.last = scan;
  }
  const settings = new Map(readLines('params.txt').map(line => { const [key, ...values] = line.split(' '); return [key, values]; }));
  const numbers = (key: string) => settings.get(key)!.map(Number), scalar = (key: string) => numbers(key)[0];
  const model = settings.get('MODEL')![0]; if (model !== 'CV' && model !== 'CA') throw new Error('Unknown motion model');
  const transition = numbers('IMM_TRANSITION');
  const params: Parameters = { model, qCV: scalar('Q_CV'), qCA: scalar('Q_CA'), sigma: scalar('SIGMA'), velocityVariance: scalar('INIT_VELOCITY_VARIANCE'),
    accelerationVariance: scalar('INIT_ACCELERATION_VARIANCE'), gate: scalar('GATE'), confirm: numbers('CONFIRM'), delete: scalar('DELETE'), abg: numbers('ABG'),
    immQ: numbers('IMM_Q'), immTransition: [transition.slice(0, 2), transition.slice(2)], immInitial: numbers('IMM_INITIAL'),
    matchDistance: scalar('MATCH_DISTANCE'), cutoff: scalar('OSPA_CUTOFF'), consistencyBound: scalar('CONSISTENCY_BOUND'),
    nisEdges: numbers('NIS_EDGES'), plotX: numbers('PLOT_X'), plotY: numbers('PLOT_Y'), plotSize: numbers('PLOT_SIZE') };
  return { scans, targets: [...targetMap.values()].sort((a, b) => a.number - b.number), params };
}
function greedyAssignment(costs: Costs): Pair[] {
  const candidates: [number, number, number][] = [];
  for (let i = 0; i < costs.length; i++) for (let j = 0; j < costs[i].length; j++) { const cost = costs[i][j]; if (cost !== null) candidates.push([i, j, cost]); }
  candidates.sort((a, b) => a[2] - b[2] || a[0] - b[0] || a[1] - b[1]);
  const rows = new Set<number>(), columns = new Set<number>(), pairs: Pair[] = [];
  for (const [i, j] of candidates) { if (rows.has(i) || columns.has(j)) continue; pairs.push([i, j]); rows.add(i); columns.add(j); }
  return pairs.sort((a, b) => a[0] - b[0]);
}
function runTracking(scans: Scan[], p: Parameters) {
  const tracks: Track[] = [], csv = ['track,scan,x,y,vx,vy,status'], log: string[] = [];
  let conflictingMeasurements = 0, conflictingTracks = 0, greedyDifferences = 0;
  const q = p.model === 'CV' ? p.qCV : p.qCA;
  for (const scan of scans) {
    const k = scan.number, live = tracks.filter(t => t.status !== 'deleted');
    if (k > 1) { const T = scan.time - scans[k - 2].time; for (const track of live) track.estimate = kalman.predict(track.estimate, p.model, T, q); }
    const innovations = live.map(t => scan.points.map(point => kalman.innovation(t.estimate, point, p.sigma)));
    const costs: Costs = innovations.map(row => row.map(v => v.d2 <= p.gate ? v.d2 : null)), gate: string[] = [];
    for (let i = 0; i < live.length; i++) for (let j = 0; j < scan.points.length; j++) {
      const cost = costs[i][j]; if (cost !== null) gate.push(`${live[i].number}:${j + 1}=${f(cost)}`);
    }
    const rowConflicts = costs.filter(row => row.filter(v => v !== null).length >= 2).length; let columnConflicts = 0;
    for (let j = 0; j < scan.points.length; j++) if (costs.filter(row => row[j] !== null).length >= 2) columnConflicts++;
    conflictingMeasurements += columnConflicts; conflictingTracks += rowConflicts;
    const assigned = optimal(costs), greedy = greedyAssignment(costs), pairKey = (pairs: Pair[]) => pairs.map(pair => pair.join(':')).join(' ');
    if (pairKey(assigned) !== pairKey(greedy)) greedyDifferences++;
    const byTrack = new Map(assigned), used = new Set(assigned.map(pair => pair[1]));
    const missed: number[] = [], confirmed: number[] = [], deleted: number[] = [], created: Track[] = [], newPairs: string[] = [];
    for (let i = 0; i < live.length; i++) {
      const track = live[i], j = byTrack.get(i); let measurement: Position | null = null, nis: number | null = null;
      if (j !== undefined) {
        measurement = scan.points[j]; nis = innovations[i][j].d2; track.estimate = kalman.update(track.estimate, innovations[i][j]);
        track.hits++; track.consecutive = 0; track.end = k;
      } else { track.consecutive++; missed.push(track.number); }
      track.records.push({ measurement, nis });
    }
    for (const track of live) {
      if (track.status === 'confirmed') {
        if (track.consecutive >= p.delete) { track.status = 'deleted'; track.deletion = k; deleted.push(track.number); }
      } else if (track.hits >= p.confirm[0]) { track.status = 'confirmed'; track.confirmation = k; confirmed.push(track.number); }
      else if (k - track.birth + 1 >= p.confirm[1]) { track.status = 'deleted'; track.deletion = k; deleted.push(track.number); }
    }
    for (let j = 0; j < scan.points.length; j++) {
      if (used.has(j)) continue;
      const measurement = scan.points[j], track: Track = { number: tracks.length + 1, birth: k, end: k, confirmation: null, deletion: null,
        status: 'tentative', hits: 1, consecutive: 0, estimate: kalman.initialize(p.model, measurement, p), records: [{ measurement, nis: null }] };
      tracks.push(track); created.push(track); newPairs.push(`${track.number}:${j + 1}`);
    }
    for (const track of [...live, ...created]) csv.push([track.number, k, ...track.estimate.x.slice(0, 4).map(f), track.status].join(','));
    const formatPairs = (pairs: Pair[]) => pairs.map(([i, j]) => `${live[i].number}:${j + 1}`);
    log.push(`scan ${k} tracks ${live.length} measurements ${scan.points.length}`, listLine('gate', gate), listLine('assign', formatPairs(assigned)), listLine('greedy', formatPairs(greedy)),
      listLine('missed', missed), listLine('new', newPairs), listLine('confirmed', confirmed), listLine('deleted', deleted),
      `status tentative ${tracks.filter(t => t.status === 'tentative').length} confirmed ${tracks.filter(t => t.status === 'confirmed').length}`,
      `conflicts measurements ${columnConflicts} tracks ${rowConflicts}`);
  }
  return { tracks, csv, log, conflictingMeasurements, conflictingTracks, greedyDifferences };
}
type Tracking = ReturnType<typeof runTracking>;
interface MeasurementSequence { birth: number; sequence: MeasurementRecord[] }
function kalmanRun(track: MeasurementSequence, kind: MotionModel, scans: Scan[], p: Parameters): KalmanRun {
  let estimate = kalman.initialize(kind, track.sequence[0].measurement!, p);
  const history: HistoryEntry[] = [{ estimate, prediction: null }], states = [estimate.x.slice(0, 4)], likelihoods: number[] = [];
  const q = kind === 'CV' ? p.qCV : p.qCA;
  for (let i = 1; i < track.sequence.length; i++) {
    const k = track.birth + i, T = scans[k - 1].time - scans[k - 2].time, prediction = kalman.predict(estimate, kind, T, q), measurement = track.sequence[i].measurement;
    if (measurement === null) estimate = prediction;
    else { const updated = kalman.update(prediction, kalman.innovation(prediction, measurement, p.sigma)); estimate = updated; likelihoods.push(updated.logLikelihood); }
    history.push({ estimate, prediction }); states.push(estimate.x.slice(0, 4));
  }
  return { states, history, logLikelihood: sum(likelihoods) };
}
function abgRun(track: MeasurementSequence, scans: Scan[], p: Parameters): FilterStates {
  let state = [...track.sequence[0].measurement!, 0, 0, 0, 0]; const states = [state.slice(0, 4)], [alpha, beta, gamma] = p.abg;
  for (let i = 1; i < track.sequence.length; i++) {
    const k = track.birth + i, T = scans[k - 1].time - scans[k - 2].time, predicted = state.slice(), measurement = track.sequence[i].measurement;
    for (let axis = 0; axis < 2; axis++) {
      predicted[axis] = state[axis] + T * state[axis + 2] + T * T * state[axis + 4] / 2; predicted[axis + 2] = state[axis + 2] + T * state[axis + 4];
      if (measurement !== null) {
        const residual = measurement[axis] - predicted[axis]; predicted[axis] += alpha * residual;
        predicted[axis + 2] += beta * residual / T; predicted[axis + 4] += 2 * gamma * residual / (T * T);
      }
    }
    state = predicted; states.push(state.slice(0, 4));
  }
  return { states };
}
function immRun(track: MeasurementSequence, scans: Scan[], p: Parameters) {
  let state = imm.initialize(track.sequence[0].measurement!, p); const states = [imm.estimate(state)], high = [state.probabilities[1]];
  for (let i = 1; i < track.sequence.length; i++) {
    const k = track.birth + i; state = imm.advance(state, scans[k - 1].time - scans[k - 2].time, track.sequence[i].measurement, p);
    states.push(imm.estimate(state)); high.push(state.probabilities[1]);
  }
  return { states, high };
}
function pathLength(points: number[][]): number {
  const lengths: number[] = []; for (let i = 1; i < points.length; i++) lengths.push(distance(points[i], points[i - 1])); return sum(lengths);
}
function scanSegments(labels: (number | null)[], first: number): Segment[] {
  const segments: Segment[] = []; let current: Segment | null = null;
  for (let i = 0; i < labels.length; i++) {
    const target = labels[i];
    if (target === null) current = null;
    else if (current === null || current.target !== target) { current = { first: first + i, last: first + i, target }; segments.push(current); }
    else current.last = first + i;
  }
  return segments;
}
function prepareTracks(tracking: Tracking, scans: Scan[], p: Parameters): EvaluatedTrack[] {
  return tracking.tracks.filter(t => t.confirmation !== null).map((track, a) => {
    const sequence = track.records.slice(0, track.end - track.birth + 1), span = { birth: track.birth, sequence };
    const nis = sequence.slice(1).filter(r => r.measurement !== null).map(r => r.nis!), hits = sequence.filter(r => r.measurement !== null).length;
    let gap = 0, longestGap = 0;
    for (const record of sequence) { gap = record.measurement === null ? gap + 1 : 0; longestGap = Math.max(longestGap, gap); }
    const cv = kalmanRun(span, 'CV', scans, p), ca = kalmanRun(span, 'CA', scans, p), immFilter = immRun(span, scans, p);
    const rts = { states: kalman.smooth((p.model === 'CV' ? cv : ca).history).map(s => s.slice(0, 4)) };
    const high = immFilter.high; let maximum = 0;
    for (let i = 1; i < high.length; i++) if (high[i] > high[maximum]) maximum = i;
    return { ...track, character: CHARACTERS[a], sequence, nis, hits, misses: sequence.length - hits, longestGap,
      filters: { cv, ca, abg: abgRun(span, scans, p), imm: immFilter, rts }, path: pathLength(rts.states),
      scanTargets: Array<number | null>(sequence.length).fill(null), matchedScans: 0, segments: [], match: null,
      high: { mean: mean(high), maximum: high[maximum], scan: track.birth + maximum, count: high.filter(v => v > 0.5).length,
        segments: scanSegments(high.map(v => v > 0.5 ? 1 : null), track.birth) } };
  });
}
function prepareTruth(truth: Truth[], scans: Scan[]): Target[] {
  return truth.map(target => {
    const path = pathLength([...target.positions.values()]), velocities = new Map<number, Position>();
    for (let k = target.first + 1; k < target.last; k++) {
      const before = target.positions.get(k - 1)!, after = target.positions.get(k + 1)!, T = scans[k].time - scans[k - 2].time;
      velocities.set(k, [(after[0] - before[0]) / T, (after[1] - before[1]) / T]);
    }
    return { ...target, count: target.last - target.first + 1, path, meanSpeed: path / (scans[target.last - 1].time - scans[target.first - 1].time),
      velocities, track: null, errors: null };
  });
}
function associateScans(tracks: EvaluatedTrack[], targets: Target[], scans: Scan[], p: Parameters) {
  const labelMap = () => new Map(targets.map(t => [t.number, Array<number | null>(scans.length).fill(null)]));
  const labels: Record<Filter, Map<number, (number | null)[]>> = { cv: labelMap(), ca: labelMap(), abg: labelMap(), imm: labelMap(), rts: labelMap() };
  const table: { scan: number; targets: number; tracks: number; values: number[] }[] = [], primary = primaryFilter(p);
  for (const scan of scans) {
    const k = scan.number, active = tracks.filter(t => t.birth <= k && k <= t.end), existing = targets.filter(t => t.positions.has(k));
    const truth = existing.map(t => t.positions.get(k)!), values: number[] = [];
    for (const name of FILTERS) {
      const estimates = active.map(t => t.filters[name].states[k - t.birth]);
      const costs = estimates.map(estimate => truth.map(point => { const d = distance(estimate, point); return d <= p.matchDistance ? d : null; }));
      for (const [a, b] of optimal(costs)) {
        labels[name].get(existing[b].number)![k - 1] = active[a].number;
        if (name === primary) active[a].scanTargets[k - active[a].birth] = existing[b].number;
      }
      values.push(ospa(estimates, truth, p.cutoff));
    }
    table.push({ scan: k, targets: existing.length, tracks: active.length, values });
  }
  for (const track of tracks) { track.matchedScans = track.scanTargets.filter(v => v !== null).length; track.segments = scanSegments(track.scanTargets, track.birth); }
  const continuityFor = (name: Filter) => targets.map(t => continuity(labels[name].get(t.number)!.slice(t.first - 1, t.last)));
  const continuityRecords: Record<Filter, ReturnType<typeof continuity>[]> = {
    cv: continuityFor('cv'), ca: continuityFor('ca'), abg: continuityFor('abg'), imm: continuityFor('imm'), rts: continuityFor('rts') };
  return { labels, table, continuity: continuityRecords };
}
type PerScan = ReturnType<typeof associateScans>;
function matchTracks(tracks: EvaluatedTrack[], targets: Target[], p: Parameters): void {
  const primary = primaryFilter(p), cutoff = p.cutoff;
  const details = tracks.map(track => targets.map(target => {
    const firstCommon = Math.max(track.birth, target.first), lastCommon = Math.min(track.end, target.last); if (firstCommon > lastCommon) return null;
    const first = Math.min(track.birth, target.first), last = Math.max(track.end, target.last), values: number[] = []; let usable = false;
    for (let k = first; k <= last; k++) {
      if (firstCommon <= k && k <= lastCommon) {
        const d = distance(track.filters[primary].states[k - track.birth], target.positions.get(k)!); values.push(Math.min(cutoff, d)); if (d < cutoff) usable = true;
      } else values.push(cutoff);
    }
    return { cost: mean(values), common: lastCommon - firstCommon + 1, usable };
  }));
  const costs = details.map(row => row.map(v => v !== null && v.usable ? v.cost : null));
  for (const [a, b] of optimal(costs)) { const detail = details[a][b]!; tracks[a].match = { target: targets[b], cost: detail.cost, common: detail.common }; targets[b].track = tracks[a]; }
}
function computeErrors(targets: Target[], p: Parameters) {
  const overallPosition: number[][] = FILTERS.map(() => []), overallVelocity: number[][] = FILTERS.map(() => []), primary = primaryFilter(p);
  for (const target of targets) {
    if (target.track === null) continue;
    const track = target.track, first = Math.max(track.birth, target.first), last = Math.min(track.end, target.last);
    const common = Array.from({ length: last - first + 1 }, (_, i) => first + i), velocityScans = common.filter(k => target.velocities.has(k));
    const position: number[] = [], velocity: number[] = [];
    for (let index = 0; index < FILTERS.length; index++) {
      const states = track.filters[FILTERS[index]].states;
      const positionErrors = common.map(k => { const estimate = states[k - track.birth], truth = target.positions.get(k)!, x = estimate[0] - truth[0], y = estimate[1] - truth[1]; return x * x + y * y; });
      const velocityErrors = velocityScans.map(k => { const estimate = states[k - track.birth], truth = target.velocities.get(k)!, x = estimate[2] - truth[0], y = estimate[3] - truth[1]; return x * x + y * y; });
      position.push(Math.sqrt(mean(positionErrors))); velocity.push(Math.sqrt(mean(velocityErrors)));
      overallPosition[index].push(...positionErrors); overallVelocity[index].push(...velocityErrors);
    }
    const nees = common.map(k => {
      const estimate = track.filters[primary].history[k - track.birth].estimate, truth = target.positions.get(k)!, error = [estimate.x[0] - truth[0], estimate.x[1] - truth[1]];
      return matrix.quadratic2(error, matrix.inverse([estimate.P[0].slice(0, 2), estimate.P[1].slice(0, 2)]));
    });
    target.errors = { common: common.length, velocityCount: velocityScans.length, position, velocity, nees };
  }
  return { position: overallPosition.map(v => Math.sqrt(mean(v))), velocity: overallVelocity.map(v => Math.sqrt(mean(v))) };
}
function nisHistogram(tracks: EvaluatedTrack[], edges: number[]) {
  const values = tracks.flatMap(t => t.nis), observed = Array<number>(edges.length + 1).fill(0);
  for (const value of values) { let bin = 0; while (bin < edges.length && value >= edges[bin]) bin++; observed[bin]++; }
  const expected = [0, ...edges].map((v, i) => values.length * (Math.exp(-v / 2) - (i === edges.length ? 0 : Math.exp(-edges[i] / 2))));
  return { total: values.length, observed, expected };
}
function rmseText(values: number[]): string {
  const rounded = values.map(v => Number(f(v))); let best = 0;
  for (let i = 1; i < values.length; i++) if (rounded[i] < rounded[best]) best = i;
  return FILTERS.map((name, i) => `${name} ${f(values[i])}`).join(' ') + ' best ' + FILTERS[best];
}
function evaluationLines(scans: Scan[], targets: Target[], tracks: EvaluatedTrack[], tracking: Tracking, perScan: PerScan, errors: ReturnType<typeof computeErrors>, p: Parameters): string[] {
  const summary = ['summary', `scans ${scans.length}`, `measurements ${sum(scans.map(s => s.points.length))}`, `targets ${targets.length}`,
    `tracks_created ${tracking.tracks.length}`, `tracks_confirmed ${tracks.length}`, `false_tracks ${tracks.filter(t => t.matchedScans === 0).length}`,
    `missed_targets ${targets.filter(t => t.track === null).length}`, `measurements_used ${sum(tracks.map(t => t.hits))}`,
    `conflict_measurements ${tracking.conflictingMeasurements}`, `conflict_tracks ${tracking.conflictingTracks}`, `greedy_differences ${tracking.greedyDifferences}`];
  const targetLines = ['targets'];
  for (const t of targets) targetLines.push(`target ${t.number} first ${t.first} last ${t.last} scans ${t.count} path ${f(t.path)} mean_speed ${f(t.meanSpeed)}`);
  const trackLines = ['tracks'], matching = ['matching'], models = ['models'], high = ['imm'];
  for (const t of tracks) {
    const inside = t.nis.filter(v => v <= p.consistencyBound).length;
    trackLines.push(`track ${t.number} birth ${t.birth} confirmed ${t.confirmation} end ${t.end} deleted ${absent(t.deletion)} hits ${t.hits} misses ${t.misses} longest_gap ${t.longestGap} path ${f(t.path)} nis ${f(mean(t.nis))} nis_inside ${inside}/${t.nis.length}`);
    const match = t.match === null ? '-' : `${t.match.target.number} common ${t.match.common} mean_distance ${f(t.match.cost)}`;
    matching.push(`track ${t.number} target ${match} matched_scans ${t.matchedScans} ` + listLine('segments', t.segments.map(s => `${s.first}-${s.last}:${s.target}`)));
    const cv = t.filters.cv.logLikelihood, ca = t.filters.ca.logLikelihood;
    models.push(`track ${t.number} updates ${t.nis.length} cv ${f(cv)} ca ${f(ca)} better ${cv >= ca ? 'cv' : 'ca'}`);
    high.push(`track ${t.number} mean_high ${f(t.high.mean)} max_high ${f(t.high.maximum)} at ${t.high.scan} high_scans ${t.high.count} ` + listLine('segments', t.high.segments.map(s => `${s.first}-${s.last}`)));
  }
  const rmse = ['rmse'], consistency = ['consistency'];
  for (const t of targets) {
    const prefix = `target ${t.number}`;
    if (t.track === null) { rmse.push(prefix + ' track -'); consistency.push(prefix + ' track -'); continue; }
    const e = t.errors!, number = t.track.number;
    rmse.push(`${prefix} track ${number} common ${e.common} ${rmseText(e.position)}`, `${prefix} velocity ${e.velocityCount} ${rmseText(e.velocity)}`);
    consistency.push(`${prefix} track ${number} nees ${f(mean(e.nees))} inside ${e.nees.filter(v => v <= p.consistencyBound).length}/${e.common}`);
  }
  rmse.push('overall position ' + rmseText(errors.position), 'overall velocity ' + rmseText(errors.velocity));
  const histogram = nisHistogram(tracks, p.nisEdges);
  consistency.push(`nis_histogram total ${histogram.total} observed ${histogram.observed.join(' ')} expected ${histogram.expected.map(f).join(' ')}`);
  const ospaLines = [`ospa cutoff ${f(p.cutoff)} order 2`, 'scan targets tracks cv ca abg imm rts'];
  for (const row of perScan.table) ospaLines.push([row.scan, row.targets, row.tracks, ...row.values.map(f)].join(' '));
  ospaLines.push('mean ' + FILTERS.map((_, i) => f(mean(perScan.table.map(row => row.values[i])))).join(' '));
  const continuityLines = ['continuity'];
  for (const name of FILTERS) {
    const records = perScan.continuity[name];
    continuityLines.push(`${name} covered ${sum(records.map(r => r.covered))} breaks ${sum(records.map(r => r.breaks))} swaps ${sum(records.map(r => r.swaps))}`);
    for (let i = 0; i < targets.length; i++) {
      const r = records[i], t = targets[i]; continuityLines.push(`  target ${t.number} scans ${t.count} covered ${r.covered} breaks ${r.breaks} swaps ${r.swaps} delay ${absent(r.delay)}`);
    }
  }
  return [summary, targetLines, trackLines, matching, rmse, consistency, models, ospaLines, continuityLines, high].flatMap((section, i) => i === 0 ? section : ['', ...section]);
}
function frame(rows: string[][]): string[] {
  const border = '+' + '-'.repeat(rows[0].length) + '+'; return [border, ...rows.map(row => '|' + row.join('') + '|'), border];
}
function plotLines(scans: Scan[], targets: Target[], tracks: EvaluatedTrack[], perScan: PerScan, p: Parameters): string[] {
  const [width, height] = p.plotSize, [xmin, xmax] = p.plotX, [ymin, ymax] = p.plotY, dx = (xmax - xmin) / width, dy = (ymax - ymin) / height;
  const trajectory = Array.from({ length: height }, () => Array<string>(width).fill(' ')), measurements = Array.from({ length: height }, () => Array<number>(width).fill(0));
  function cell(point: number[]): [number, number] | null {
    const c = Math.floor((point[0] - xmin) / dx), r = Math.floor((ymax - point[1]) / dy); return 0 <= c && c < width && 0 <= r && r < height ? [r, c] : null;
  }
  for (const target of targets) for (const point of target.positions.values()) { const at = cell(point); if (at !== null) trajectory[at[0]][at[1]] = '.'; }
  for (const track of tracks) for (const state of track.filters.rts.states) { const at = cell(state); if (at !== null) trajectory[at[0]][at[1]] = track.character; }
  for (const scan of scans) for (const point of scan.points) { const at = cell(point); if (at !== null) measurements[at[0]][at[1]]++; }
  const lines = [`tracks x ${f(xmin)} ${f(xmax)} y ${f(ymin)} ${f(ymax)} size ${width} ${height}`, ...frame(trajectory)];
  for (const track of tracks) lines.push(`${track.character} track ${track.number} target ${track.match === null ? '-' : track.match.target.number}`);
  lines.push('', 'measurements', ...frame(measurements.map(row => row.map(v => v === 0 ? ' ' : v < 10 ? String(v) : '#'))), '', 'timeline');
  const primary = primaryFilter(p), characters = new Map(tracks.map(t => [t.number, t.character]));
  for (const target of targets) {
    const labels = perScan.labels[primary].get(target.number)!;
    const timeline = scans.map(scan => { const label = labels[scan.number - 1]; return !target.positions.has(scan.number) ? ' ' : label === null ? '.' : characters.get(label)!; }).join('');
    lines.push(`${target.number} |${timeline}|`);
  }
  const primaryIndex = FILTERS.indexOf(primary), heights = perScan.table.map(row => Math.floor(10 * row.values[primaryIndex] / p.cutoff));
  const ospaRows = Array.from({ length: 10 }, (_, row) => heights.map(v => v >= 10 - row ? '#' : ' '));
  lines.push('', 'ospa ' + primary, ...frame(ospaRows)); return lines;
}
function main(): void {
  const input = readInputs(), { scans, params } = input, tracking = runTracking(scans, params), tracks = prepareTracks(tracking, scans, params), targets = prepareTruth(input.targets, scans);
  const perScan = associateScans(tracks, targets, scans, params); matchTracks(tracks, targets, params); const errors = computeErrors(targets, params);
  const smoothed = ['track,scan,x,y,vx,vy'];
  for (const track of tracks) track.filters.rts.states.forEach((state, i) => smoothed.push([track.number, track.birth + i, ...state.map(f)].join(',')));
  const files: Record<string, string[]> = { 'tracks.csv': tracking.csv, 'smoothed.csv': smoothed, 'association_log.txt': tracking.log,
    'evaluation.txt': evaluationLines(scans, targets, tracks, tracking, perScan, errors, params), 'track_plot.txt': plotLines(scans, targets, tracks, perScan, params) };
  mkdirSync('output', { recursive: true }); for (const [name, lines] of Object.entries(files)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}
main();
