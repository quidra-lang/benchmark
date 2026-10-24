'use strict';

const fs = require('node:fs');
const matrix = require('./matrix');
const kalman = require('./kalman');
const association = require('./association');
const imm = require('./imm');
const evaluation = require('./evaluation');
const { distance, fixed: f } = evaluation;
const FILTERS = ['cv', 'ca', 'abg', 'imm', 'rts'];
const CHARACTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

function sum(values) {
    if (values.length === 0) return 0;
    let total = values[0];
    for (let i = 1; i < values.length; i++) total += values[i];
    return total;
}

const mean = values => sum(values) / values.length;
const absent = value => value === null ? '-' : value;
const listLine = (name, values) => name + ' ' + (values.length ? values.join(' ') : 'none');

function readInputs() {
    const scans = [], targetMap = new Map(), params = {};
    const readLines = name => fs.readFileSync('input/' + name, 'ascii').trimEnd().split('\n');
    for (const line of readLines('measurements.csv').slice(1)) {
        const [scan, time, x, y] = line.split(',').map(Number);
        if (!scans[scan - 1]) scans[scan - 1] = { number: scan, time, points: [] };
        scans[scan - 1].points.push([x, y]);
    }
    for (const line of readLines('truth.csv').slice(1)) {
        const [number, scan, x, y] = line.split(',').map(Number);
        if (!targetMap.has(number)) {
            targetMap.set(number, { number, first: scan, last: scan, positions: new Map(), track: null });
        }
        const target = targetMap.get(number);
        target.positions.set(scan, [x, y]);
        target.last = scan;
    }
    const arrays = new Set([
        'CONFIRM', 'ABG', 'IMM_Q', 'IMM_TRANSITION', 'IMM_INITIAL',
        'NIS_EDGES', 'PLOT_X', 'PLOT_Y', 'PLOT_SIZE',
    ]);
    for (const line of readLines('params.txt')) {
        const [key, ...values] = line.split(' ');
        params[key] = key === 'MODEL' ? values[0] : arrays.has(key) ? values.map(Number) : Number(values[0]);
    }
    return { scans, targets: [...targetMap.values()].sort((a, b) => a.number - b.number), params };
}

function greedyAssignment(costs) {
    const candidates = [];
    for (let i = 0; i < costs.length; i++) {
        for (let j = 0; j < costs[i].length; j++) {
            if (costs[i][j] !== null) candidates.push([i, j, costs[i][j]]);
        }
    }
    candidates.sort((a, b) => a[2] - b[2] || a[0] - b[0] || a[1] - b[1]);
    const rows = new Set(), columns = new Set(), pairs = [];
    for (const [i, j] of candidates) {
        if (rows.has(i) || columns.has(j)) continue;
        pairs.push([i, j]);
        rows.add(i);
        columns.add(j);
    }
    pairs.sort((a, b) => a[0] - b[0]);
    return pairs;
}

function runTracking(scans, params) {
    const tracks = [], csv = ['track,scan,x,y,vx,vy,status'], log = [];
    let conflictingMeasurements = 0, conflictingTracks = 0, greedyDifferences = 0;
    const q = params.MODEL === 'CV' ? params.Q_CV : params.Q_CA;
    for (const scan of scans) {
        const k = scan.number, live = tracks.filter(track => track.status !== 'deleted');
        if (k > 1) {
            const T = scan.time - scans[k - 2].time;
            for (const track of live) track.estimate = kalman.predict(track.estimate, params.MODEL, T, q);
        }
        const innovations = live.map(track => scan.points.map(point =>
            kalman.innovation(track.estimate, point, params.SIGMA)));
        const costs = innovations.map(row => row.map(value => value.d2 <= params.GATE ? value.d2 : null));
        const gate = [];
        for (let i = 0; i < live.length; i++) {
            for (let j = 0; j < scan.points.length; j++) {
                if (costs[i][j] !== null) gate.push(live[i].number + ':' + (j + 1) + '=' + f(costs[i][j]));
            }
        }
        const rowConflicts = costs.filter(row => row.filter(value => value !== null).length >= 2).length;
        let columnConflicts = 0;
        for (let j = 0; j < scan.points.length; j++) {
            if (costs.filter(row => row[j] !== null).length >= 2) columnConflicts++;
        }
        conflictingMeasurements += columnConflicts;
        conflictingTracks += rowConflicts;
        const assigned = association.optimal(costs), greedy = greedyAssignment(costs);
        const pairKey = pairs => pairs.map(pair => pair.join(':')).join(' ');
        if (pairKey(assigned) !== pairKey(greedy)) greedyDifferences++;
        const byTrack = new Map(assigned), used = new Set(assigned.map(pair => pair[1]));
        const missed = [], confirmed = [], deleted = [], created = [], newPairs = [];
        for (let i = 0; i < live.length; i++) {
            const track = live[i];
            let measurement = null, nis = null;
            if (byTrack.has(i)) {
                const j = byTrack.get(i);
                measurement = scan.points[j];
                nis = innovations[i][j].d2;
                track.estimate = kalman.update(track.estimate, innovations[i][j]);
                track.hits++;
                track.consecutive = 0;
                track.end = k;
            } else {
                track.consecutive++;
                missed.push(track.number);
            }
            track.records.push({ measurement, nis });
        }
        for (const track of live) {
            if (track.status === 'confirmed') {
                if (track.consecutive >= params.DELETE) {
                    track.status = 'deleted';
                    track.deletion = k;
                    deleted.push(track.number);
                }
            } else if (track.hits >= params.CONFIRM[0]) {
                track.status = 'confirmed';
                track.confirmation = k;
                confirmed.push(track.number);
            } else if (k - track.birth + 1 >= params.CONFIRM[1]) {
                track.status = 'deleted';
                track.deletion = k;
                deleted.push(track.number);
            }
        }
        for (let j = 0; j < scan.points.length; j++) {
            if (used.has(j)) continue;
            const measurement = scan.points[j];
            const track = {
                number: tracks.length + 1, birth: k, end: k, confirmation: null, deletion: null,
                status: 'tentative', hits: 1, consecutive: 0,
                estimate: kalman.initialize(params.MODEL, measurement, params),
                records: [{ measurement, nis: null }],
            };
            tracks.push(track);
            created.push(track);
            newPairs.push(track.number + ':' + (j + 1));
        }
        for (const track of [...live, ...created]) {
            csv.push([track.number, k, ...track.estimate.x.slice(0, 4).map(f), track.status].join(','));
        }
        const formatPairs = pairs => pairs.map(([i, j]) => live[i].number + ':' + (j + 1));
        log.push('scan ' + k + ' tracks ' + live.length + ' measurements ' + scan.points.length);
        log.push(listLine('gate', gate), listLine('assign', formatPairs(assigned)), listLine('greedy', formatPairs(greedy)));
        log.push(listLine('missed', missed), listLine('new', newPairs), listLine('confirmed', confirmed), listLine('deleted', deleted));
        log.push('status tentative ' + tracks.filter(track => track.status === 'tentative').length
            + ' confirmed ' + tracks.filter(track => track.status === 'confirmed').length);
        log.push('conflicts measurements ' + columnConflicts + ' tracks ' + rowConflicts);
    }
    return { tracks, csv, log, conflictingMeasurements, conflictingTracks, greedyDifferences };
}

function kalmanRun(track, kind, scans, params) {
    let estimate = kalman.initialize(kind, track.sequence[0].measurement, params);
    const history = [{ estimate, prediction: null }], states = [estimate.x.slice(0, 4)], likelihoods = [];
    const q = kind === 'CV' ? params.Q_CV : params.Q_CA;
    for (let i = 1; i < track.sequence.length; i++) {
        const k = track.birth + i, T = scans[k - 1].time - scans[k - 2].time;
        const prediction = kalman.predict(estimate, kind, T, q);
        const measurement = track.sequence[i].measurement;
        if (measurement === null) estimate = prediction;
        else {
            estimate = kalman.update(prediction, kalman.innovation(prediction, measurement, params.SIGMA));
            likelihoods.push(estimate.logLikelihood);
        }
        history.push({ estimate, prediction });
        states.push(estimate.x.slice(0, 4));
    }
    return { states, history, logLikelihood: sum(likelihoods) };
}

function abgRun(track, scans, params) {
    let state = [...track.sequence[0].measurement, 0, 0, 0, 0];
    const states = [state.slice(0, 4)], [alpha, beta, gamma] = params.ABG;
    for (let i = 1; i < track.sequence.length; i++) {
        const k = track.birth + i, T = scans[k - 1].time - scans[k - 2].time;
        const predicted = state.slice(), measurement = track.sequence[i].measurement;
        for (let axis = 0; axis < 2; axis++) {
            predicted[axis] = state[axis] + T * state[axis + 2] + T * T * state[axis + 4] / 2;
            predicted[axis + 2] = state[axis + 2] + T * state[axis + 4];
            if (measurement !== null) {
                const residual = measurement[axis] - predicted[axis];
                predicted[axis] += alpha * residual;
                predicted[axis + 2] += beta * residual / T;
                predicted[axis + 4] += 2 * gamma * residual / (T * T);
            }
        }
        state = predicted;
        states.push(state.slice(0, 4));
    }
    return { states };
}

function immRun(track, scans, params) {
    let state = imm.initialize(track.sequence[0].measurement, params);
    const states = [imm.estimate(state)], high = [state.probabilities[1]];
    for (let i = 1; i < track.sequence.length; i++) {
        const k = track.birth + i;
        state = imm.advance(state, scans[k - 1].time - scans[k - 2].time, track.sequence[i].measurement, params);
        states.push(imm.estimate(state));
        high.push(state.probabilities[1]);
    }
    return { states, high };
}

function pathLength(points) {
    const lengths = [];
    for (let i = 1; i < points.length; i++) lengths.push(distance(points[i], points[i - 1]));
    return sum(lengths);
}

function scanSegments(labels, first) {
    const segments = [];
    let current = null;
    for (let i = 0; i < labels.length; i++) {
        if (labels[i] === null) {
            current = null;
        } else if (current === null || current.target !== labels[i]) {
            current = { first: first + i, last: first + i, target: labels[i] };
            segments.push(current);
        } else current.last = first + i;
    }
    return segments;
}

function prepareTracks(tracking, scans, params) {
    const tracks = tracking.tracks.filter(track => track.confirmation !== null), primary = params.MODEL.toLowerCase();
    for (let a = 0; a < tracks.length; a++) {
        const track = tracks[a];
        track.character = CHARACTERS[a];
        track.sequence = track.records.slice(0, track.end - track.birth + 1);
        track.nis = track.sequence.slice(1).filter(record => record.measurement !== null).map(record => record.nis);
        track.hits = track.sequence.filter(record => record.measurement !== null).length;
        track.misses = track.sequence.length - track.hits;
        let gap = 0;
        track.longestGap = 0;
        for (const record of track.sequence) {
            gap = record.measurement === null ? gap + 1 : 0;
            track.longestGap = Math.max(track.longestGap, gap);
        }
        track.filters = {
            cv: kalmanRun(track, 'CV', scans, params), ca: kalmanRun(track, 'CA', scans, params),
            abg: abgRun(track, scans, params), imm: immRun(track, scans, params),
        };
        track.filters.rts = { states: kalman.smooth(track.filters[primary].history).map(state => state.slice(0, 4)) };
        track.path = pathLength(track.filters.rts.states);
        track.scanTargets = new Array(track.sequence.length).fill(null);
        track.match = null;
        const high = track.filters.imm.high;
        let maximum = 0;
        for (let i = 1; i < high.length; i++) if (high[i] > high[maximum]) maximum = i;
        track.high = {
            mean: mean(high), maximum: high[maximum], scan: track.birth + maximum,
            count: high.filter(value => value > 0.5).length,
            segments: scanSegments(high.map(value => value > 0.5 ? 1 : null), track.birth),
        };
    }
    return tracks;
}

function prepareTruth(targets, scans) {
    for (const target of targets) {
        target.count = target.last - target.first + 1;
        target.path = pathLength([...target.positions.values()]);
        target.meanSpeed = target.path / (scans[target.last - 1].time - scans[target.first - 1].time);
        target.velocities = new Map();
        for (let k = target.first + 1; k < target.last; k++) {
            const before = target.positions.get(k - 1), after = target.positions.get(k + 1);
            const T = scans[k].time - scans[k - 2].time;
            target.velocities.set(k, [(after[0] - before[0]) / T, (after[1] - before[1]) / T]);
        }
    }
}

function associateScans(tracks, targets, scans, params) {
    const labels = Object.fromEntries(FILTERS.map(name =>
        [name, new Map(targets.map(target => [target.number, new Array(scans.length).fill(null)]))]));
    const table = [], primary = params.MODEL.toLowerCase();
    for (const scan of scans) {
        const k = scan.number, active = tracks.filter(track => track.birth <= k && k <= track.end);
        const existing = targets.filter(target => target.positions.has(k));
        const truth = existing.map(target => target.positions.get(k)), values = [];
        for (const name of FILTERS) {
            const estimates = active.map(track => track.filters[name].states[k - track.birth]);
            const costs = estimates.map(estimate => truth.map(point => {
                const d = distance(estimate, point);
                return d <= params.MATCH_DISTANCE ? d : null;
            }));
            for (const [a, b] of association.optimal(costs)) {
                labels[name].get(existing[b].number)[k - 1] = active[a].number;
                if (name === primary) active[a].scanTargets[k - active[a].birth] = existing[b].number;
            }
            values.push(evaluation.ospa(estimates, truth, params.OSPA_CUTOFF));
        }
        table.push({ scan: k, targets: existing.length, tracks: active.length, values });
    }
    for (const track of tracks) {
        track.matchedScans = track.scanTargets.filter(value => value !== null).length;
        track.segments = scanSegments(track.scanTargets, track.birth);
    }
    const continuity = Object.fromEntries(FILTERS.map(name => [name, targets.map(target =>
        evaluation.continuity(labels[name].get(target.number).slice(target.first - 1, target.last)))]));
    return { labels, table, continuity };
}

function matchTracks(tracks, targets, params) {
    const primary = params.MODEL.toLowerCase(), cutoff = params.OSPA_CUTOFF;
    const details = tracks.map(track => targets.map(target => {
        const firstCommon = Math.max(track.birth, target.first), lastCommon = Math.min(track.end, target.last);
        if (firstCommon > lastCommon) return null;
        const first = Math.min(track.birth, target.first), last = Math.max(track.end, target.last);
        const values = [];
        let usable = false;
        for (let k = first; k <= last; k++) {
            if (firstCommon <= k && k <= lastCommon) {
                const d = distance(track.filters[primary].states[k - track.birth], target.positions.get(k));
                values.push(Math.min(cutoff, d));
                if (d < cutoff) usable = true;
            } else values.push(cutoff);
        }
        return { cost: mean(values), common: lastCommon - firstCommon + 1, usable };
    }));
    const costs = details.map(row => row.map(value => value !== null && value.usable ? value.cost : null));
    for (const [a, b] of association.optimal(costs)) {
        tracks[a].match = { ...details[a][b], target: targets[b] };
        targets[b].track = tracks[a];
    }
}

function computeErrors(tracks, targets, params) {
    const overallPosition = FILTERS.map(() => []), overallVelocity = FILTERS.map(() => []);
    const primary = params.MODEL.toLowerCase();
    for (const target of targets) {
        if (target.track === null) continue;
        const track = target.track, first = Math.max(track.birth, target.first), last = Math.min(track.end, target.last);
        const common = Array.from({ length: last - first + 1 }, (_, i) => first + i);
        const velocityScans = common.filter(k => target.velocities.has(k));
        const position = [], velocity = [];
        for (let index = 0; index < FILTERS.length; index++) {
            const states = track.filters[FILTERS[index]].states;
            const positionErrors = common.map(k => {
                const estimate = states[k - track.birth], truth = target.positions.get(k);
                const x = estimate[0] - truth[0], y = estimate[1] - truth[1];
                return x * x + y * y;
            });
            const velocityErrors = velocityScans.map(k => {
                const estimate = states[k - track.birth], truth = target.velocities.get(k);
                const x = estimate[2] - truth[0], y = estimate[3] - truth[1];
                return x * x + y * y;
            });
            position.push(Math.sqrt(mean(positionErrors)));
            velocity.push(Math.sqrt(mean(velocityErrors)));
            overallPosition[index].push(...positionErrors);
            overallVelocity[index].push(...velocityErrors);
        }
        const nees = common.map(k => {
            const estimate = track.filters[primary].history[k - track.birth].estimate, truth = target.positions.get(k);
            const error = [estimate.x[0] - truth[0], estimate.x[1] - truth[1]];
            const covariance = [estimate.P[0].slice(0, 2), estimate.P[1].slice(0, 2)];
            return matrix.quadratic2(error, matrix.inverse(covariance));
        });
        target.errors = { common: common.length, velocityCount: velocityScans.length, position, velocity, nees };
    }
    return {
        position: overallPosition.map(values => Math.sqrt(mean(values))),
        velocity: overallVelocity.map(values => Math.sqrt(mean(values))),
    };
}

function nisHistogram(tracks, edges) {
    const values = tracks.flatMap(track => track.nis), observed = new Array(edges.length + 1).fill(0);
    for (const value of values) {
        let bin = 0;
        while (bin < edges.length && value >= edges[bin]) bin++;
        observed[bin]++;
    }
    const lower = [0, ...edges];
    const expected = lower.map((value, i) => values.length
        * (Math.exp(-value / 2) - (i === edges.length ? 0 : Math.exp(-edges[i] / 2))));
    return { total: values.length, observed, expected };
}

function rmseText(values) {
    const rounded = values.map(value => Number(f(value)));
    let best = 0;
    for (let i = 1; i < values.length; i++) if (rounded[i] < rounded[best]) best = i;
    return FILTERS.map((name, i) => name + ' ' + f(values[i])).join(' ') + ' best ' + FILTERS[best];
}

function evaluationLines(scans, targets, tracks, tracking, perScan, errors, params) {
    const summary = [
        'summary', 'scans ' + scans.length, 'measurements ' + sum(scans.map(scan => scan.points.length)),
        'targets ' + targets.length, 'tracks_created ' + tracking.tracks.length,
        'tracks_confirmed ' + tracks.length, 'false_tracks ' + tracks.filter(track => track.matchedScans === 0).length,
        'missed_targets ' + targets.filter(target => target.track === null).length,
        'measurements_used ' + sum(tracks.map(track => track.hits)),
        'conflict_measurements ' + tracking.conflictingMeasurements, 'conflict_tracks ' + tracking.conflictingTracks,
        'greedy_differences ' + tracking.greedyDifferences,
    ];
    const targetLines = ['targets'];
    for (const target of targets) {
        targetLines.push('target ' + target.number + ' first ' + target.first + ' last ' + target.last
            + ' scans ' + target.count + ' path ' + f(target.path) + ' mean_speed ' + f(target.meanSpeed));
    }
    const trackLines = ['tracks'], matching = ['matching'], models = ['models'], high = ['imm'];
    for (const track of tracks) {
        const inside = track.nis.filter(value => value <= params.CONSISTENCY_BOUND).length;
        trackLines.push('track ' + track.number + ' birth ' + track.birth + ' confirmed ' + track.confirmation
            + ' end ' + track.end + ' deleted ' + absent(track.deletion) + ' hits ' + track.hits + ' misses ' + track.misses
            + ' longest_gap ' + track.longestGap + ' path ' + f(track.path) + ' nis ' + f(mean(track.nis))
            + ' nis_inside ' + inside + '/' + track.nis.length);
        const match = track.match === null ? '-' : track.match.target.number + ' common '
            + track.match.common + ' mean_distance ' + f(track.match.cost);
        const segments = track.segments.map(segment => segment.first + '-' + segment.last + ':' + segment.target);
        matching.push('track ' + track.number + ' target ' + match + ' matched_scans ' + track.matchedScans
            + ' ' + listLine('segments', segments));
        const cv = track.filters.cv.logLikelihood, ca = track.filters.ca.logLikelihood;
        models.push('track ' + track.number + ' updates ' + track.nis.length + ' cv ' + f(cv) + ' ca ' + f(ca)
            + ' better ' + (cv >= ca ? 'cv' : 'ca'));
        high.push('track ' + track.number + ' mean_high ' + f(track.high.mean) + ' max_high ' + f(track.high.maximum)
            + ' at ' + track.high.scan + ' high_scans ' + track.high.count + ' '
            + listLine('segments', track.high.segments.map(segment => segment.first + '-' + segment.last)));
    }
    const rmse = ['rmse'], consistency = ['consistency'];
    for (const target of targets) {
        const prefix = 'target ' + target.number;
        if (target.track === null) {
            rmse.push(prefix + ' track -');
            consistency.push(prefix + ' track -');
            continue;
        }
        const error = target.errors, trackNumber = target.track.number;
        rmse.push(prefix + ' track ' + trackNumber + ' common ' + error.common + ' ' + rmseText(error.position));
        rmse.push(prefix + ' velocity ' + error.velocityCount + ' ' + rmseText(error.velocity));
        consistency.push(prefix + ' track ' + trackNumber + ' nees ' + f(mean(error.nees)) + ' inside '
            + error.nees.filter(value => value <= params.CONSISTENCY_BOUND).length + '/' + error.common);
    }
    rmse.push('overall position ' + rmseText(errors.position), 'overall velocity ' + rmseText(errors.velocity));
    const histogram = nisHistogram(tracks, params.NIS_EDGES);
    consistency.push('nis_histogram total ' + histogram.total + ' observed ' + histogram.observed.join(' ')
        + ' expected ' + histogram.expected.map(f).join(' '));
    const ospa = ['ospa cutoff ' + f(params.OSPA_CUTOFF) + ' order 2', 'scan targets tracks cv ca abg imm rts'];
    for (const row of perScan.table) {
        ospa.push([row.scan, row.targets, row.tracks, ...row.values.map(f)].join(' '));
    }
    ospa.push('mean ' + FILTERS.map((name, i) => f(mean(perScan.table.map(row => row.values[i])))).join(' '));
    const continuity = ['continuity'];
    for (const name of FILTERS) {
        const records = perScan.continuity[name];
        continuity.push(name + ' covered ' + sum(records.map(record => record.covered))
            + ' breaks ' + sum(records.map(record => record.breaks)) + ' swaps ' + sum(records.map(record => record.swaps)));
        for (let i = 0; i < targets.length; i++) {
            const record = records[i], target = targets[i];
            continuity.push('  target ' + target.number + ' scans ' + target.count + ' covered ' + record.covered
                + ' breaks ' + record.breaks + ' swaps ' + record.swaps + ' delay ' + absent(record.delay));
        }
    }
    const sections = [summary, targetLines, trackLines, matching, rmse, consistency, models, ospa, continuity, high];
    return sections.flatMap((section, i) => i === 0 ? section : ['', ...section]);
}

function frame(rows) {
    const border = '+' + '-'.repeat(rows[0].length) + '+';
    return [border, ...rows.map(row => '|' + row.join('') + '|'), border];
}

function plotLines(scans, targets, tracks, perScan, params) {
    const [width, height] = params.PLOT_SIZE, [xmin, xmax] = params.PLOT_X, [ymin, ymax] = params.PLOT_Y;
    const dx = (xmax - xmin) / width, dy = (ymax - ymin) / height;
    const trajectory = Array.from({ length: height }, () => new Array(width).fill(' '));
    const measurements = Array.from({ length: height }, () => new Array(width).fill(0));
    function cell(point) {
        const c = Math.floor((point[0] - xmin) / dx), r = Math.floor((ymax - point[1]) / dy);
        return 0 <= c && c < width && 0 <= r && r < height ? [r, c] : null;
    }
    for (const target of targets) {
        for (const point of target.positions.values()) {
            const at = cell(point);
            if (at !== null) trajectory[at[0]][at[1]] = '.';
        }
    }
    for (const track of tracks) {
        for (const state of track.filters.rts.states) {
            const at = cell(state);
            if (at !== null) trajectory[at[0]][at[1]] = track.character;
        }
    }
    for (const scan of scans) {
        for (const point of scan.points) {
            const at = cell(point);
            if (at !== null) measurements[at[0]][at[1]]++;
        }
    }
    const lines = ['tracks x ' + f(xmin) + ' ' + f(xmax) + ' y ' + f(ymin) + ' ' + f(ymax)
        + ' size ' + width + ' ' + height, ...frame(trajectory)];
    for (const track of tracks) {
        lines.push(track.character + ' track ' + track.number + ' target ' + (track.match === null ? '-' : track.match.target.number));
    }
    lines.push('', 'measurements', ...frame(measurements.map(row =>
        row.map(value => value === 0 ? ' ' : value < 10 ? String(value) : '#'))), '', 'timeline');
    const primary = params.MODEL.toLowerCase(), characters = new Map(tracks.map(track => [track.number, track.character]));
    for (const target of targets) {
        const labels = perScan.labels[primary].get(target.number);
        const timeline = scans.map(scan => !target.positions.has(scan.number) ? ' '
            : labels[scan.number - 1] === null ? '.' : characters.get(labels[scan.number - 1])).join('');
        lines.push(target.number + ' |' + timeline + '|');
    }
    const primaryIndex = FILTERS.indexOf(primary);
    const heights = perScan.table.map(row => Math.floor(10 * row.values[primaryIndex] / params.OSPA_CUTOFF));
    const ospa = Array.from({ length: 10 }, (_, row) => heights.map(value => value >= 10 - row ? '#' : ' '));
    lines.push('', 'ospa ' + primary, ...frame(ospa));
    return lines;
}

function main() {
    const { scans, targets, params } = readInputs();
    const tracking = runTracking(scans, params);
    const tracks = prepareTracks(tracking, scans, params);
    prepareTruth(targets, scans);
    const perScan = associateScans(tracks, targets, scans, params);
    matchTracks(tracks, targets, params);
    const errors = computeErrors(tracks, targets, params);
    const smoothed = ['track,scan,x,y,vx,vy'];
    for (const track of tracks) {
        track.filters.rts.states.forEach((state, i) => smoothed.push([track.number, track.birth + i, ...state.map(f)].join(',')));
    }
    const files = {
        'tracks.csv': tracking.csv,
        'smoothed.csv': smoothed,
        'association_log.txt': tracking.log,
        'evaluation.txt': evaluationLines(scans, targets, tracks, tracking, perScan, errors, params),
        'track_plot.txt': plotLines(scans, targets, tracks, perScan, params),
    };
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(files)) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
