'use strict';

const { readInputs, real, modelLines, writeLines } = require('./model_io');
const { argmax, viterbi, decode } = require('./inference');
const { reestimate, estimateByCounting, totalLoglik } = require('./training');
const { fraction, confusion, accumulate, confusionLines, metricLines, runs,
    overlaps, boundaries, matchedBoundaries } = require('./evaluation');
const { Minstd, synthetic, posteriorPath } = require('./sampler');

const MODEL_NAMES = ['INITIAL', 'BAUM_WELCH', 'VITERBI_TRAINING', 'SUPERVISED'];
const DECODERS = ['VITERBI', 'POSTERIOR'];

function parameters(rows, model) {
    const values = new Map(rows.map(([key, ...rest]) => [key, rest]));
    const result = {};
    const numeric = ['iterations', 'pseudocount', 'folds', 'min_sequence_length',
        'max_missing_percent', 'merge_gap', 'min_segment_length', 'min_rich_percent',
        'min_motif_percent', 'confidence', 'boundary_tolerance', 'posterior_seed',
        'posterior_samples', 'sample_seed', 'sample_count', 'sample_length'];
    for (const key of numeric) result[key] = Number(values.get(key)[0]);
    result.smoothing = values.get('smoothing').map(text => ({ text, value: Number(text) }));
    result.segment_state = model.states.indexOf(values.get('segment_state')[0]);
    result.motif = values.get('motif').map(symbol => model.symbols.indexOf(symbol));
    result.rich_symbols = new Set(values.get('rich_symbols').map(symbol => model.symbols.indexOf(symbol)));
    return result;
}

function rejectionReason(record, seen, model, params, labeled) {
    const duplicate = seen.has(record.name);
    seen.add(record.name);
    if (duplicate) return 'duplicate name';
    record.text = record.text.toUpperCase();
    for (let t = 0; t < record.text.length; t++) {
        const character = record.text[t];
        if (character !== model.missing && !model.symbols.includes(character)) {
            return `invalid symbol ${character} at position ${t + 1}`;
        }
    }
    if (labeled) {
        for (let t = 0; t < record.labels.length; t++) {
            if (!model.states.includes(record.labels[t])) {
                return `invalid label ${record.labels[t]} at position ${t + 1}`;
            }
        }
        if (record.text.length !== record.labels.length) {
            return `length mismatch ${record.text.length} ${record.labels.length}`;
        }
    }
    if (record.text.length < params.min_sequence_length) return `too short ${record.text.length}`;
    let missing = 0;
    for (const character of record.text) if (character === model.missing) missing++;
    if (100 * missing > params.max_missing_percent * record.text.length) {
        return `too many missing ${missing}`;
    }
    record.missing = missing;
    record.observations = Array.from(record.text, character => model.symbols.indexOf(character));
    if (labeled) record.path = Array.from(record.labels, character => model.states.indexOf(character));
    return null;
}

function validate(input, params) {
    const data = { unlabeled: [], train: [], test: [], rejected: [] };
    let seen = new Set();
    for (let i = 0; i < input.sequences.length; i++) {
        const [name, text] = input.sequences[i];
        const record = { name, text };
        const reason = rejectionReason(record, seen, input.model, params, false);
        if (reason === null) data.unlabeled.push(record);
        else data.rejected.push({ file: 'sequences.txt', line: i + 1, name, reason });
    }
    seen = new Set();
    for (let i = 0; i < input.labeled.length; i += 2) {
        const [name, role, text] = input.labeled[i];
        const record = { name, role, text, labels: input.labeled[i + 1][0] };
        const reason = rejectionReason(record, seen, input.model, params, true);
        if (reason === null) data[role === 'TRAIN' ? 'train' : 'test'].push(record);
        else data.rejected.push({ file: 'labeled.txt', line: i + 1, name, reason });
    }
    return data;
}

function positions(records) {
    let count = 0;
    for (const record of records) count += record.observations.length;
    return count;
}

function correctCount(left, right) {
    let count = 0;
    for (let t = 0; t < left.length; t++) if (left[t] === right[t]) count++;
    return count;
}

function maximumChange(previous, current) {
    const before = [previous.initial, ...previous.transition, ...previous.emission];
    const after = [current.initial, ...current.transition, ...current.emission];
    let maximum = 0;
    for (let row = 0; row < before.length; row++) {
        for (let column = 0; column < before[row].length; column++) {
            maximum = Math.max(maximum, Math.abs(after[row][column] - before[row][column]));
        }
    }
    return maximum;
}

function baumWelch(initial, data, params) {
    const observations = data.unlabeled.map(record => record.observations);
    const heldout = data.train.concat(data.test).map(record => record.observations);
    const history = [];
    const lines = ['iteration,loglik,heldout,change,max_change,status'];
    let model = initial;
    let previous = null;
    let violations = 0;
    let best = 0;
    for (let iteration = 0; iteration <= params.iterations; iteration++) {
        const loglik = totalLoglik(model, observations);
        const held = totalLoglik(model, heldout);
        history.push({ loglik, held });
        if (held > history[best].held) best = iteration;
        if (iteration === 0) lines.push(`0,${real(loglik)},${real(held)},,,`);
        else {
            const before = history[iteration - 1].loglik;
            const violation = loglik < before - 0.000001 * Math.abs(before);
            if (violation) violations++;
            lines.push([iteration, real(loglik), real(held), real(loglik - before),
                real(maximumChange(previous, model), 6), violation ? 'violation' : 'ok'].join(','));
        }
        if (iteration < params.iterations) {
            previous = model;
            model = reestimate(model, observations, params.pseudocount);
        }
    }
    return { model, history, lines, violations, best };
}

function viterbiTraining(initial, records, params) {
    const observations = records.map(record => record.observations);
    const lines = ['iteration,logprob,loglik,changed'];
    let model = initial;
    let decoded = observations.map(sequence => viterbi(model, sequence));
    let changed = null;
    let iteration = 0;
    for (;;) {
        let logprob = 0;
        for (const result of decoded) logprob += result.logprob;
        lines.push([iteration, real(logprob), real(totalLoglik(model, observations)),
            changed === null ? '' : changed].join(','));
        if (changed === 0 || iteration === params.iterations) break;
        const pairs = observations.map((sequence, i) => ({ observations: sequence, path: decoded[i].path }));
        model = estimateByCounting(initial, pairs, params.pseudocount, 'VITERBI_TRAINING');
        const next = observations.map(sequence => viterbi(model, sequence));
        changed = 0;
        for (let i = 0; i < next.length; i++) {
            changed += observations[i].length - correctCount(decoded[i].path, next[i].path);
        }
        decoded = next;
        iteration++;
    }
    return { model, lines, iterations: iteration, converged: changed === 0 };
}

function supervisedTraining(initial, data, params) {
    const candidates = [];
    let best = 0;
    for (const smoothing of params.smoothing) {
        const matrix = confusion(initial.states.length);
        const folds = [];
        let correct = 0;
        for (let f = 0; f < params.folds; f++) {
            const train = data.train.filter((record, i) => i % params.folds !== f);
            const held = data.train.filter((record, i) => i % params.folds === f);
            const model = estimateByCounting(initial, train, smoothing.value, 'SUPERVISED');
            let foldCorrect = 0;
            for (const record of held) {
                foldCorrect += accumulate(matrix, record.path, viterbi(model, record.observations).path);
            }
            folds.push({ records: held.length, positions: positions(held), correct: foldCorrect });
            correct += foldCorrect;
        }
        candidates.push({ smoothing, matrix, folds, correct });
        if (correct > candidates[best].correct) best = candidates.length - 1;
    }
    const selected = candidates[best];
    const model = estimateByCounting(initial, data.train, selected.smoothing.value, 'SUPERVISED');
    const learning = [];
    for (let r = 1; r <= data.train.length; r++) {
        const current = estimateByCounting(initial, data.train.slice(0, r), selected.smoothing.value, 'SUPERVISED');
        let correct = 0;
        for (const record of data.test) correct += correctCount(record.path, viterbi(current, record.observations).path);
        learning.push(correct);
    }
    return { model, selected, candidates, learning };
}

function segments(path, params) {
    const merged = [];
    for (const run of runs(path)) {
        if (run.state !== params.segment_state) continue;
        const previous = merged[merged.length - 1];
        if (previous && run.start - previous.end - 1 <= params.merge_gap) previous.end = run.end;
        else merged.push({ start: run.start, end: run.end });
    }
    return merged.filter(segment => segment.end - segment.start + 1 >= params.min_segment_length);
}

function composition(observations, segment, params) {
    let observed = 0;
    let rich = 0;
    let pairs = 0;
    let first = 0;
    let second = 0;
    for (let t = segment.start; t <= segment.end; t++) {
        const symbol = observations[t];
        if (symbol >= 0) {
            observed++;
            if (params.rich_symbols.has(symbol)) rich++;
            if (symbol === params.motif[0]) first++;
            if (symbol === params.motif[1]) second++;
        }
        if (t < segment.end && symbol === params.motif[0] && observations[t + 1] === params.motif[1]) pairs++;
    }
    const product = first * second;
    const island = product > 0 && 100 * rich >= params.min_rich_percent * observed
        && 100 * pairs * observed >= params.min_motif_percent * product;
    return { rich: observed === 0 ? null : rich / observed,
        ratio: product === 0 ? null : pairs * observed / product, island };
}

function evaluationBlock(model, records, decoded, decoder, params) {
    const matrix = confusion(model.states.length);
    const region = { predicted: 0, truth: 0, matchedPredicted: 0, matchedTruth: 0 };
    const boundary = { predicted: 0, truth: 0, matchedPredicted: 0, matchedTruth: 0 };
    const bins = Array.from({ length: 10 }, () => ({ positions: 0, correct: 0 }));
    const recordLines = [];
    let correct = 0;
    for (let i = 0; i < records.length; i++) {
        const record = records[i];
        const result = decoded[i];
        const path = decoder === 'VITERBI' ? result.viterbi : result.posterior;
        const count = accumulate(matrix, record.path, path);
        correct += count;
        recordLines.push(`RECORD ${record.name} length ${path.length} correct ${count}`);
        const predicted = segments(path, params);
        const truth = runs(record.path).filter(run => run.state === params.segment_state);
        region.predicted += predicted.length;
        region.truth += truth.length;
        for (const segment of predicted) if (truth.some(other => overlaps(segment, other))) region.matchedPredicted++;
        for (const segment of truth) if (predicted.some(other => overlaps(segment, other))) region.matchedTruth++;
        const predictedBoundaries = boundaries(path);
        const trueBoundaries = boundaries(record.path);
        boundary.predicted += predictedBoundaries.length;
        boundary.truth += trueBoundaries.length;
        boundary.matchedPredicted += matchedBoundaries(predictedBoundaries, trueBoundaries, params.boundary_tolerance);
        boundary.matchedTruth += matchedBoundaries(trueBoundaries, predictedBoundaries, params.boundary_tolerance);
        if (decoder === 'POSTERIOR') {
            for (let t = 0; t < path.length; t++) {
                const bin = Math.min(9, Math.floor(10 * result.confidence[t]));
                bins[bin].positions++;
                if (path[t] === record.path[t]) bins[bin].correct++;
            }
        }
    }
    const lines = [`EVALUATION ${model.name} ${decoder}`, ...confusionLines(matrix, model.states),
        ...metricLines(matrix, model.states)];
    lines.push(`REGIONS ${model.states[params.segment_state]} predicted ${region.predicted} true ${region.truth}`
        + ` precision ${fraction(region.matchedPredicted, region.predicted)} recall ${fraction(region.matchedTruth, region.truth)}`);
    lines.push(`BOUNDARIES predicted ${boundary.predicted} true ${boundary.truth}`
        + ` precision ${fraction(boundary.matchedPredicted, boundary.predicted)} recall ${fraction(boundary.matchedTruth, boundary.truth)}`);
    for (let b = 0; b < bins.length; b++) {
        if (bins[b].positions === 0) continue;
        const range = b === 9 ? '0.9-1.0' : `0.${b}-0.${b + 1}`;
        lines.push(`CALIBRATION ${range} positions ${bins[b].positions} correct ${bins[b].correct}`
            + ` accuracy ${fraction(bins[b].correct, bins[b].positions)}`);
    }
    lines.push(...recordLines);
    return { lines, correct };
}

function supervisedBlocks(result, data, states, params) {
    const total = positions(data.train);
    const selected = result.selected;
    const lines = [`CROSS_VALIDATION folds ${params.folds}`];
    for (const candidate of result.candidates) {
        lines.push(`SMOOTHING ${candidate.smoothing.text} positions ${total} correct ${candidate.correct}`
            + ` accuracy ${fraction(candidate.correct, total)}`);
    }
    lines.push(`SELECTED ${selected.smoothing.text}`);
    for (let f = 0; f < selected.folds.length; f++) {
        const fold = selected.folds[f];
        lines.push(`FOLD ${f + 1} records ${fold.records} positions ${fold.positions} correct ${fold.correct}`
            + ` accuracy ${fraction(fold.correct, fold.positions)}`);
    }
    lines.push(...confusionLines(selected.matrix, states), ...metricLines(selected.matrix, states));
    const learning = ['LEARNING_CURVE'];
    for (let r = 0; r < result.learning.length; r++) {
        learning.push(`RECORDS ${r + 1} correct ${result.learning[r]} accuracy ${fraction(result.learning[r], positions(data.test))}`);
    }
    return [lines, learning];
}

function pathText(path, states) {
    return path.map(state => states[state]).join('');
}

function annotate(model, records, decoded, params) {
    const generator = new Minstd(params.posterior_seed);
    const lines = [];
    const segmentLines = ['sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island'];
    for (let i = 0; i < records.length; i++) {
        const record = records[i];
        const result = decoded[i];
        const samples = [];
        let segmentCount = 0;
        for (let sample = 0; sample < params.posterior_samples; sample++) {
            const path = posteriorPath(model, result.factors, generator);
            samples.push(path);
            segmentCount += segments(path, params).length;
        }
        let uncertain = 0;
        let confident = '';
        let imputed = '';
        for (let t = 0; t < record.observations.length; t++) {
            if (result.confidence[t] < params.confidence) {
                uncertain++;
                confident += '.';
            } else confident += model.states[result.posterior[t]];
            const symbol = record.observations[t];
            if (symbol >= 0) imputed += model.symbols[symbol];
            else {
                const weights = [];
                for (let c = 0; c < model.symbols.length; c++) {
                    let weight = 0;
                    for (let state = 0; state < model.states.length; state++) weight += result.gamma[t][state] * model.emission[state][c];
                    weights.push(weight);
                }
                imputed += model.symbols[argmax(weights)].toLowerCase();
            }
        }
        const differences = record.observations.length - correctCount(result.viterbi, result.posterior);
        lines.push(`SEQUENCE ${record.name} length ${record.observations.length} loglik ${real(result.loglik)}`
            + ` viterbi ${real(result.logprob)} differences ${differences} uncertain ${uncertain}`
            + ` expected_segments ${real(segmentCount / params.posterior_samples)}`,
        `VITERBI ${pathText(result.viterbi, model.states)}`, `POSTERIOR ${pathText(result.posterior, model.states)}`,
        `CONFIDENT ${confident}`, `IMPUTED ${imputed}`);
        for (const decoder of ['viterbi', 'posterior']) {
            for (const segment of segments(result[decoder], params)) {
                const length = segment.end - segment.start + 1;
                let probability = 0;
                for (let t = segment.start; t <= segment.end; t++) probability += result.gamma[t][params.segment_state];
                let support = 0;
                for (const sample of samples) {
                    let count = 0;
                    for (let t = segment.start; t <= segment.end; t++) if (sample[t] === params.segment_state) count++;
                    if (2 * count > length) support++;
                }
                const judged = composition(record.observations, segment, params);
                segmentLines.push([record.name, decoder, segment.start + 1, segment.end + 1, length,
                    real(probability / length), support, real(judged.rich), real(judged.ratio), judged.island ? 'yes' : 'no'].join(','));
            }
        }
    }
    return { lines, segmentLines };
}

function syntheticReport(model, params) {
    const generator = new Minstd(params.sample_seed);
    const lines = [];
    let viterbiCorrect = 0;
    let posteriorCorrect = 0;
    for (let sample = 1; sample <= params.sample_count; sample++) {
        const generated = synthetic(model, params.sample_length, generator);
        const result = decode(model, generated.observations);
        const vc = correctCount(generated.path, result.viterbi);
        const pc = correctCount(generated.path, result.posterior);
        viterbiCorrect += vc;
        posteriorCorrect += pc;
        lines.push(`SAMPLE ${sample} loglik ${real(result.loglik)} viterbi ${real(result.logprob)}`
            + ` viterbi_correct ${vc} posterior_correct ${pc}`, `STATES ${pathText(generated.path, model.states)}`,
        `SYMBOLS ${pathText(generated.observations, model.symbols)}`, `VITERBI ${pathText(result.viterbi, model.states)}`,
        `POSTERIOR ${pathText(result.posterior, model.states)}`);
    }
    const total = params.sample_count * params.sample_length;
    lines.push(`TOTAL positions ${total} viterbi_accuracy ${fraction(viterbiCorrect, total)}`
        + ` posterior_accuracy ${fraction(posteriorCorrect, total)}`);
    return lines;
}

function pathStatistics(paths, size) {
    const counts = Array(size).fill(0);
    const runCounts = Array(size).fill(0);
    let total = 0;
    for (const path of paths) {
        total += path.length;
        for (const state of path) counts[state]++;
        for (const run of runs(path)) runCounts[run.state]++;
    }
    return { occupancy: counts.map(count => count / total),
        meanRun: counts.map((count, i) => runCounts[i] === 0 ? null : count / runCounts[i]) };
}

function stationary(model) {
    const size = model.states.length;
    const system = [];
    for (let j = 0; j < size - 1; j++) {
        const row = [];
        for (let i = 0; i < size; i++) row.push(model.transition[i][j] - (i === j ? 1 : 0));
        system.push([...row, 0]);
    }
    system.push([...Array(size).fill(1), 1]);
    for (let column = 0; column < size; column++) {
        let pivot = column;
        for (let row = column + 1; row < size; row++) {
            if (Math.abs(system[row][column]) > Math.abs(system[pivot][column])) pivot = row;
        }
        [system[column], system[pivot]] = [system[pivot], system[column]];
        const divisor = system[column][column];
        for (let j = column; j <= size; j++) system[column][j] /= divisor;
        for (let row = 0; row < size; row++) {
            if (row === column) continue;
            const factor = system[row][column];
            for (let j = column; j <= size; j++) system[row][j] -= factor * system[column][j];
        }
    }
    return system.map(row => row[size]);
}

function stateAlignment(model, records) {
    const matrix = confusion(model.states.length);
    for (const record of records) accumulate(matrix, record.path, viterbi(model, record.observations).path);
    let best = null;
    let agreement = -1;
    const permutation = [];
    function visit(score) {
        const column = permutation.length;
        if (column === model.states.length) {
            if (score > agreement) {
                best = permutation.slice();
                agreement = score;
            }
            return;
        }
        for (let state = 0; state < model.states.length; state++) {
            if (permutation.includes(state)) continue;
            permutation.push(state);
            visit(score + matrix[state][column]);
            permutation.pop();
        }
    }
    visit(0);
    return { permutation: best, agreement };
}

function inputReport(data, model) {
    const labeled = data.train.concat(data.test);
    let missing = 0;
    let labeledMissing = 0;
    for (const record of data.unlabeled) missing += record.missing;
    for (const record of labeled) labeledMissing += record.missing;
    const rejectedSequences = data.rejected.filter(rejection => rejection.file === 'sequences.txt').length;
    const lines = ['INPUT', `SEQUENCES accepted ${data.unlabeled.length} rejected ${rejectedSequences}`
        + ` positions ${positions(data.unlabeled)} missing ${missing}`,
    `LABELED train ${data.train.length} test ${data.test.length} rejected ${data.rejected.length - rejectedSequences}`
        + ` positions ${positions(labeled)} missing ${labeledMissing}`];
    for (const rejected of data.rejected) lines.push(`REJECT ${rejected.file} line ${rejected.line} ${rejected.name} ${rejected.reason}`);
    const symbols = Array(model.symbols.length).fill(0);
    for (const record of data.unlabeled) for (const symbol of record.observations) if (symbol >= 0) symbols[symbol]++;
    const observed = positions(data.unlabeled) - missing;
    lines.push('COMPOSITION ' + model.symbols.map((symbol, i) => `${symbol} ${real(symbols[i] / observed)}`).join(' '));
    for (const role of ['TRAIN', 'TEST']) {
        const summary = pathStatistics(data[role.toLowerCase()].map(record => record.path), model.states.length);
        for (let state = 0; state < model.states.length; state++) {
            lines.push(`TRUTH ${role} ${model.states[state]} occupancy ${real(summary.occupancy[state])}`
                + ` mean_run ${real(summary.meanRun[state])}`);
        }
    }
    return lines;
}

function trainingReport(bw, vt, supervised, data, decoded, scores, params) {
    const lines = [`TRAINING BAUM_WELCH iterations ${params.iterations} initial_loglik ${real(bw.history[0].loglik)}`
        + ` final_loglik ${real(bw.history[bw.history.length - 1].loglik)} violations ${bw.violations} best_heldout_iteration ${bw.best}`,
    `TRAINING VITERBI_TRAINING iterations ${vt.iterations} converged ${vt.converged ? 'yes' : 'no'}`,
    `TRAINING SUPERVISED smoothing ${supervised.selected.smoothing.text}`];
    const preference = Array(MODEL_NAMES.length).fill(0);
    for (let sequence = 0; sequence < data.unlabeled.length; sequence++) {
        preference[argmax(decoded.map(results => results[sequence].loglik))]++;
    }
    lines.push('PREFERENCE ' + MODEL_NAMES.map((name, i) => `${name} ${preference[i]}`).join(' '));
    for (let left = 0; left < MODEL_NAMES.length; left++) {
        for (let right = left + 1; right < MODEL_NAMES.length; right++) {
            let agreement = 0;
            for (let i = 0; i < data.unlabeled.length; i++) agreement += correctCount(decoded[left][i].viterbi, decoded[right][i].viterbi);
            lines.push(`AGREEMENT ${MODEL_NAMES[left]} ${MODEL_NAMES[right]} ${fraction(agreement, positions(data.unlabeled))}`);
        }
    }
    for (let decoder = 0; decoder < DECODERS.length; decoder++) {
        const best = argmax(scores.map(row => row[decoder]));
        lines.push(`BEST ${DECODERS[decoder]} ${MODEL_NAMES[best]} accuracy ${fraction(scores[best][decoder], positions(data.test))}`);
    }
    return lines;
}

function modelReport(model, data, decoded, testDecoded, params) {
    let loglik = 0;
    let testLoglik = 0;
    let observed = 0;
    let segmentCount = 0;
    let segmentLength = 0;
    let islands = 0;
    for (let i = 0; i < data.unlabeled.length; i++) {
        loglik += decoded[i].loglik;
        observed += data.unlabeled[i].observations.length - data.unlabeled[i].missing;
        for (const segment of segments(decoded[i].viterbi, params)) {
            segmentCount++;
            segmentLength += segment.end - segment.start + 1;
            if (composition(data.unlabeled[i].observations, segment, params).island) islands++;
        }
    }
    for (const result of testDecoded) testLoglik += result.loglik;
    const distribution = stationary(model);
    const summary = pathStatistics(decoded.map(result => result.viterbi), model.states.length);
    const alignment = stateAlignment(model, data.train);
    const lines = [`MODEL ${model.name}`, `LOGLIK unlabeled ${real(loglik)} per_symbol ${real(loglik / observed)} test ${real(testLoglik)}`,
        `SEGMENTS count ${segmentCount} mean_length ${real(segmentCount === 0 ? null : segmentLength / segmentCount)} islands ${islands}`];
    lines.push('ALIGNMENT ' + model.states.map((state, i) => `${state}=${model.states[alignment.permutation[i]]}`).join(' ')
        + ` agreement ${fraction(alignment.agreement, positions(data.train))}`);
    for (let state = 0; state < model.states.length; state++) {
        lines.push(`STATE ${model.states[state]} stationary ${real(distribution[state])}`
            + ` duration ${real(1 / (1 - model.transition[state][state]))} occupancy ${real(summary.occupancy[state])}`
            + ` mean_run ${real(summary.meanRun[state])}`);
    }
    return lines;
}

function joinBlocks(blocks) {
    const lines = [];
    for (const block of blocks) {
        if (lines.length > 0) lines.push('');
        for (const line of block) lines.push(line);
    }
    return lines;
}

function main() {
    const input = readInputs();
    const params = parameters(input.parameters, input.model);
    const data = validate(input, params);
    const bw = baumWelch(input.model, data, params);
    const vt = viterbiTraining(input.model, data.unlabeled, params);
    const supervised = supervisedTraining(input.model, data, params);
    const models = [input.model, bw.model, vt.model, supervised.model];
    const decoded = models.map(model => data.unlabeled.map(record => decode(model, record.observations)));
    const testDecoded = models.map(model => data.test.map(record => decode(model, record.observations)));
    const evaluation = [];
    const scores = [];
    for (let i = 0; i < models.length; i++) {
        const row = [];
        for (const decoder of DECODERS) {
            const result = evaluationBlock(models[i], data.test, testDecoded[i], decoder, params);
            evaluation.push(result.lines);
            row.push(result.correct);
        }
        scores.push(row);
    }
    evaluation.push(...supervisedBlocks(supervised, data, input.model.states, params));
    const annotation = annotate(bw.model, data.unlabeled, decoded[1], params);
    const report = [inputReport(data, input.model), trainingReport(bw, vt, supervised, data, decoded, scores, params)];
    for (let i = 0; i < models.length; i++) report.push(modelReport(models[i], data, decoded[i], testDecoded[i], params));
    writeLines('trained_model.txt', joinBlocks(models.slice(1).map(modelLines)));
    writeLines('loglik_trace.csv', bw.lines);
    writeLines('viterbi_trace.csv', vt.lines);
    writeLines('decodings.txt', annotation.lines);
    writeLines('segments.csv', annotation.segmentLines);
    writeLines('samples.txt', syntheticReport(bw.model, params));
    writeLines('evaluation.txt', joinBlocks(evaluation));
    writeLines('report.txt', joinBlocks(report));
}

main();
