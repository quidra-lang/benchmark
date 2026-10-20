import { read } from './dataset.ts';
import type { Example, MultiExample, Point, Kernel, Parameters } from './dataset.ts';
import * as kernels from './kernels.ts';
import * as smo from './smo.ts';
import type { Trainer } from './smo.ts';
import * as multiclass from './multiclass.ts';
import type { Models } from './multiclass.ts';
import { sign, fixed, ratio, folds, binary, auc, confusion, write } from './evaluation.ts';

interface Support { total: number; bound: number; free: number }
interface FoldResult { train: number; test: number; correct: number; support: number; passes: number; steps: number; converged: boolean }
interface Candidate { kernel: Kernel; C: number; correct: number; support: number; passes: number; steps: number; values: number[]; folds: FoldResult[] }
interface CrossValidation { combinations: Candidate[]; best: Candidate[]; ranking: Candidate[]; selected: Candidate }
function support(model: Trainer): Support { let total = 0, bound = 0, free = 0; for (const a of model.alpha) if (a > 0) { total++; if (a === model.C) bound++; else free++; } return { total, bound, free }; }
const supportText = (s: Support) => `support_vectors ${s.total} bound ${s.bound} free ${s.free}`;
const runInfo = (model: Trainer | FoldResult) => `passes ${'passes' in model ? model.passes : model.full + model.nonbound} steps ${model.steps} converged ${model.converged ? 'yes' : 'no'}`;
function objective(model: Trainer, alpha = model.alpha) { const sums = smo.trainingSums(model, alpha); let q = 0, total = 0; for (let i = 0; i < alpha.length; i++) { q += alpha[i] * model.labels[i] * sums[i]; total += alpha[i]; } return { sums, q, dual: total - q / 2 }; }
function measure(model: Trainer, test: Example[]) {
    const result = objective(model), values = result.sums.map(s => s - model.b), testValues = test.map(row => smo.decision(model, row.point)); let w1 = 0, w2 = 0;
    for (let i = 0; i < model.alpha.length; i++) { w1 += model.alpha[i] * model.labels[i] * model.points[i][0]; w2 += model.alpha[i] * model.labels[i] * model.points[i][1]; }
    return { model, ...result, values, testValues, weights: [w1, w2], sv: support(model), trainCorrect: binary(model.labels, values).correct, testStats: binary(test.map(row => row.label), testValues) };
}
type Measured = ReturnType<typeof measure>;
function crossValidate(train: Example[], p: Parameters, matrices: number[][][]): CrossValidation {
    const partition = folds(train.length, p.folds), combinations: Candidate[] = [], best: Candidate[] = [];
    for (const kernel of p.kernels) {
        const candidates: Candidate[] = [];
        for (const C of p.cs) {
            const result: Candidate = { kernel, C, correct: 0, support: 0, passes: 0, steps: 0, values: Array(train.length).fill(0), folds: [] };
            for (const fold of partition) {
                const model = smo.train(fold.train.map(i => train[i].point), fold.train.map(i => train[i].label), kernels.subset(matrices[kernel.index], fold.train), C, kernel, p); let correct = 0;
                for (const i of fold.test) { result.values[i] = smo.decision(model, train[i].point); if (sign(result.values[i]) === train[i].label) correct++; }
                const sv = support(model), passes = model.full + model.nonbound;
                result.folds.push({ train: fold.train.length, test: fold.test.length, correct, support: sv.total, passes, steps: model.steps, converged: model.converged }); result.correct += correct; result.support += sv.total; result.passes += passes; result.steps += model.steps;
            } candidates.push(result); combinations.push(result);
        } best.push(candidates.slice().sort((a, b) => b.correct - a.correct || a.C - b.C)[0]);
    }
    const ranking = combinations.slice().sort((a, b) => b.correct - a.correct || a.C - b.C || a.kernel.index - b.kernel.index); return { combinations, best, ranking, selected: ranking[0] };
}
function crossValidationLines(cv: CrossValidation, n: number, p: Parameters) {
    const lines = [`cross_validation folds ${p.folds} examples ${n}`]; for (const best of cv.best) lines.push(`best ${best.kernel.name} C ${fixed(best.C, 4)} correct ${best.correct}/${n} accuracy ${ratio(best.correct, n)}`);
    lines.push(`selected ${cv.selected.kernel.name} C ${fixed(cv.selected.C, 4)}`, 'ranking'); cv.ranking.forEach((e, i) => lines.push(`${i + 1} ${e.kernel.name} C ${fixed(e.C, 4)} correct ${e.correct}/${n}`)); lines.push(`cv_detail ${cv.selected.kernel.name} C ${fixed(cv.selected.C, 4)}`);
    cv.selected.folds.forEach((f, i) => lines.push(`fold ${i + 1} train ${f.train} test ${f.test} correct ${f.correct} support_vectors ${f.support} ${runInfo(f)}`)); return lines;
}
function finalModelLines(result: Measured, train: Example[], test: Example[], p: Parameters) {
    const { model, q, dual, values, testValues, sv, trainCorrect, testStats, weights } = result, n = train.length, m = test.length;
    let sy = 0, sg = 0, maximum = -Infinity, minimum = Infinity;
    for (let i = 0; i < n; i++) { maximum = Math.max(maximum, model.Q[i][i]); for (let j = 0; j < n; j++) { sy += model.labels[i] * model.labels[j] * model.Q[i][j]; sg += model.Q[i][j] * model.Q[i][j]; minimum = Math.min(minimum, model.Q[i][j]); } }
    const radius = maximum - minimum, norm = Math.sqrt(q), byClass = { positive: { bound: 0, free: 0 }, negative: { bound: 0, free: 0 } }; let equality = 0, xi = 0, violations = 0, maxViolation = 0, estimatedErrors = 0;
    for (let i = 0; i < n; i++) {
        const a = model.alpha[i], y = model.labels[i], hinge = Math.max(0, 1 - y * values[i]), r = y * values[i] - 1; equality += a * y; xi += hinge;
        const violation = a === 0 ? Math.max(0, -r) : a === model.C ? Math.max(0, r) : Math.abs(r); if (violation > p.tau) violations++; maxViolation = Math.max(maxViolation, violation); if (2 * a * radius + hinge >= 1) estimatedErrors++;
        if (a > 0) byClass[y === 1 ? 'positive' : 'negative'][a === model.C ? 'bound' : 'free']++;
    }
    const primal = q / 2 + model.C * xi; let inside = 0, positiveSum = 0, negativeSum = 0, positives = 0, negatives = 0;
    for (let i = 0; i < m; i++) { if (Math.abs(testValues[i]) < 1) inside++; if (test[i].label === 1) { positiveSum += testValues[i]; positives++; } else { negativeSum += testValues[i]; negatives++; } }
    const lines = [`model ${model.kernel.name}`, `kernel ${kernels.description(model.kernel)}`, `C ${fixed(model.C, 4)}`, `alignment ${fixed(sy / (n * Math.sqrt(sg)), 6)}`, `passes ${model.full + model.nonbound} full ${model.full} nonbound ${model.nonbound} converged ${model.converged ? 'yes' : 'no'}`, `examined ${model.examined} steps ${model.steps}`, `choice heuristic ${model.choice.heuristic} nonbound_loop ${model.choice.nonbound_loop} full_loop ${model.choice.full_loop}`, `clipping none ${model.clipping.none} lower ${model.clipping.lower} upper ${model.clipping.upper}`, supportText(sv), `b ${fixed(model.b, 6)}`, `equality ${fixed(equality, 6)}`];
    if (model.kernel.kind === 'linear') lines.push(`w ${fixed(weights[0], 6)} ${fixed(weights[1], 6)}`);
    const { positive, negative } = byClass, { tp, fp, tn, fn, correct } = testStats;
    lines.push(`sv_by_class positive bound ${positive.bound} free ${positive.free} negative bound ${negative.bound} free ${negative.free}`, `norm ${fixed(norm, 6)} margin ${fixed(2 / norm, 6)}`, `dual_objective ${fixed(dual, 6)}`, `primal_objective ${fixed(primal, 6)}`, `duality_gap ${fixed(primal - dual, 6)}`, `kkt_violations ${violations} max ${fixed(maxViolation, 6)}`, `xi_alpha radius ${fixed(radius, 6)} errors ${estimatedErrors}/${n} accuracy ${ratio(n - estimatedErrors, n)}`, `train correct ${trainCorrect}/${n} accuracy ${ratio(trainCorrect, n)}`, `test correct ${correct}/${m} accuracy ${ratio(correct, m)} tp ${tp} fp ${fp} tn ${tn} fn ${fn}`, `test precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)} f1 ${ratio(2 * tp, 2 * tp + fp + fn)} auc ${fixed(auc(test.map(row => row.label), testValues), 4)}`, `test inside_margin ${inside}`, `test mean_decision positive ${fixed(positiveSum / positives, 4)} negative ${fixed(negativeSum / negatives, 4)}`);
    for (let i = 0; i < n; i++) if (model.alpha[i] > 0) lines.push(`sv ${train[i].id} y ${model.labels[i]} alpha ${fixed(model.alpha[i], 6)} f ${fixed(values[i], 4)} ${model.alpha[i] === model.C ? 'bound' : 'free'}`); return lines;
}
function trainingLog(model: Trainer) {
    const lines = [`training_log ${model.kernel.name}`];
    for (let i = 0; i < model.records.length;) { const first = model.records[i]; if (first.kind === 'full') { lines.push(`pass ${first.number} full examined ${first.examined} changed ${first.changed} dual_objective ${fixed(objective(model, first.alpha).dual, 6)}`); i++; } else { let examined = 0, changed = 0, last = first.number; while (i < model.records.length && model.records[i].kind === 'nonbound') { const record = model.records[i++]; examined += record.examined; changed += record.changed; last = record.number; } lines.push(`passes ${first.number}-${last} nonbound examined ${examined} changed ${changed}`); } } return lines;
}
function selectedAnalyses(selected: Measured, train: Example[], test: Example[], p: Parameters) {
    const { model } = selected, n = train.length, m = test.length, path = [`c_path ${model.kernel.name}`];
    for (const C of p.cs) { const fitted = C === model.C ? model : smo.train(model.points, model.labels, model.Q, C, model.kernel, p), result = measure(fitted, test); path.push(`C ${fixed(C, 4)} ${supportText(result.sv)} dual_objective ${fixed(result.dual, 6)} train ${result.trainCorrect}/${n} test ${result.testStats.correct}/${m} ${runInfo(fitted)}`); }
    const learning = [`learning_curve ${model.kernel.name} C ${fixed(model.C, 4)}`];
    for (const fraction of p.learningCurve) { const size = Math.floor(n * fraction / 100), indices = Array.from({ length: size }, (_, i) => i), fitted = size === n ? model : smo.train(model.points.slice(0, size), model.labels.slice(0, size), kernels.subset(model.Q, indices), model.C, model.kernel, p), result = measure(fitted, test); learning.push(`size ${size} support_vectors ${result.sv.total} train ${result.trainCorrect}/${size} test ${result.testStats.correct}/${m} ${runInfo(fitted)}`); }
    return [trainingLog(model), path, learning];
}
const probability = (value: number, A: number, B: number) => 1 / (1 + Math.exp(A * value + B));
function calibrate(cv: Candidate, selected: Measured, train: Example[], test: Example[], p: Parameters) {
    const values = cv.values, n = train.length, m = test.length, positives = train.filter(row => row.label === 1).length, negatives = n - positives, targets = train.map(row => row.label === 1 ? (positives + 1) / (positives + 2) : 1 / (negatives + 2)); let A = 0, B = Math.log((negatives + 1) / (positives + 1));
    const nll = () => { let sum = 0; for (let i = 0; i < n; i++) { const pr = probability(values[i], A, B), target = targets[i]; sum += target * Math.log(pr) + (1 - target) * Math.log(1 - pr); } return -sum; };
    const lines = [`calibration ${selected.model.kernel.name} C ${fixed(selected.model.C, 4)} positives ${positives} negatives ${negatives}`, `start A ${fixed(A, 6)} B ${fixed(B, 6)} nll ${fixed(nll(), 6)}`];
    for (let iteration = 1; iteration <= p.newtonIterations; iteration++) {
        let g1 = 0, g2 = 0, h11 = 0, h21 = 0, h22 = 0;
        for (let i = 0; i < n; i++) { const v = values[i], pr = probability(v, A, B), target = targets[i]; g1 += v * (target - pr); g2 += target - pr; h11 += v * v * pr * (1 - pr); h21 += v * pr * (1 - pr); h22 += pr * (1 - pr); }
        const det = h11 * h22 - h21 * h21, nextA = A - (h22 * g1 - h21 * g2) / det, nextB = B - (h11 * g2 - h21 * g1) / det; A = nextA; B = nextB; lines.push(`iteration ${iteration} A ${fixed(A, 6)} B ${fixed(B, 6)} nll ${fixed(nll(), 6)}`);
    }
    const probabilities = selected.testValues.map(value => probability(value, A, B)), bins = Array.from({ length: 5 }, () => ({ count: 0, sum: 0, positive: 0 })); let logSum = 0, brierSum = 0;
    for (let i = 0; i < m; i++) { const pr = probabilities[i], positive = test[i].label === 1; logSum += Math.log(positive ? pr : 1 - pr); const error = pr - (positive ? 1 : 0); brierSum += error * error; const bin = bins[Math.min(4, Math.floor(pr * 5))]; bin.count++; bin.sum += pr; if (positive) bin.positive++; }
    lines.push(`test log_loss ${fixed(-logSum / m, 6)} brier ${fixed(brierSum / m, 6)}`); const ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0']; bins.forEach((bin, i) => lines.push(`bin ${ranges[i]} count ${bin.count} mean_probability ${bin.count ? fixed(bin.sum / bin.count, 4) : '-'} positive_rate ${ratio(bin.positive, bin.count)}`));
    const closest = Array.from({ length: m }, (_, i) => i).sort((a, b) => Math.abs(selected.testValues[a]) - Math.abs(selected.testValues[b]) || a - b).slice(0, 5); for (const i of closest) lines.push(`closest ${test[i].id} label ${test[i].label} decision ${fixed(selected.testValues[i], 4)} probability ${fixed(probabilities[i], 4)}`); return { A, B, probabilities, lines };
}
type Calibration = ReturnType<typeof calibrate>;
type Weights = [number, number, number];
const linearValue = (weights: Weights, point: Point) => weights[0] * point[0] + weights[1] * point[1] + weights[2];
function pegasos(train: Example[], test: Example[], comparison: Measured, p: Parameters) {
    const { lambda, iterations, seed } = p.pegasos, n = train.length, m = test.length; let state = seed, w1 = 0, w2 = 0, w0 = 0, s1 = 0, s2 = 0, s0 = 0, updates = 0;
    const lines = [`pegasos lambda ${fixed(lambda, 4)} iterations ${iterations} seed ${seed}`];
    for (let t = 1; t <= iterations; t++) {
        state = (48271 * state) % 2147483647; const row = train[state % n], eta = 1 / (lambda * t), sigma = 1 - eta * lambda, value = w1 * row.point[0] + w2 * row.point[1] + w0;
        if (row.label * value < 1) { w1 = sigma * w1 + eta * row.label * row.point[0]; w2 = sigma * w2 + eta * row.label * row.point[1]; w0 = sigma * w0 + eta * row.label; updates++; } else { w1 = sigma * w1; w2 = sigma * w2; w0 = sigma * w0; }
        s1 += w1; s2 += w2; s0 += w0;
        if (t % (iterations / 10) === 0) { let xi = 0, correct = 0; for (const example of train) { const v = w1 * example.point[0] + w2 * example.point[1] + w0; xi += Math.max(0, 1 - example.label * v); if (sign(v) === example.label) correct++; } const objective = lambda / 2 * (w1 * w1 + w2 * w2 + w0 * w0) + xi / n; lines.push(`checkpoint ${t} objective ${fixed(objective, 6)} train ${correct}/${n}`); }
    }
    const weights: Weights = [w1, w2, w0], average: Weights = [s1 / iterations, s2 / iterations, s0 / iterations], values = test.map(row => linearValue(weights, row.point)), trainCorrect = binary(train.map(row => row.label), train.map(row => linearValue(weights, row.point))).correct, testCorrect = binary(test.map(row => row.label), values).correct, averageCorrect = binary(test.map(row => row.label), test.map(row => linearValue(average, row.point))).correct, [v1, v2] = comparison.weights;
    const cosine = (w1 * v1 + w2 * v2) / (Math.sqrt(w1 * w1 + w2 * w2) * Math.sqrt(v1 * v1 + v2 * v2)); let agreement = 0; for (let i = 0; i < m; i++) if (sign(values[i]) === sign(comparison.testValues[i])) agreement++;
    lines.push(`updates ${updates}`, `w ${fixed(w1, 6)} ${fixed(w2, 6)} bias ${fixed(w0, 6)}`, `train correct ${trainCorrect}/${n} accuracy ${ratio(trainCorrect, n)}`, `test correct ${testCorrect}/${m} accuracy ${ratio(testCorrect, m)}`, `average w ${fixed(average[0], 6)} ${fixed(average[1], 6)} bias ${fixed(average[2], 6)} test correct ${averageCorrect}/${m}`, `compare ${comparison.model.kernel.name} cosine ${fixed(cosine, 6)} test_agreement ${agreement}/${m}`); return { weights, values, lines };
}
function mcnemar(finals: Measured[], pegValues: number[], test: Example[]) {
    const comparisons = [...finals.map(r => ({ name: r.model.kernel.name, values: r.testValues })), { name: 'pegasos', values: pegValues }], lines = ['mcnemar'];
    for (let a = 0; a < comparisons.length; a++) for (let b = a + 1; b < comparisons.length; b++) { let first = 0, second = 0; for (let i = 0; i < test.length; i++) { const ca = sign(comparisons[a].values[i]) === test[i].label, cb = sign(comparisons[b].values[i]) === test[i].label; if (ca && !cb) first++; if (cb && !ca) second++; } const difference = Math.abs(first - second) - 1, chi = first + second > 0 ? fixed(difference * difference / (first + second), 4) : '-'; lines.push(`${comparisons[a].name} ${comparisons[b].name} only_first ${first} only_second ${second} chi2 ${chi}`); } return lines;
}
function multiclassLines(models: Models, train: MultiExample[], test: MultiExample[], kernel: Kernel, p: Parameters) {
    const trainResults = train.map(row => multiclass.classify(models, row.point)), testResults = test.map(row => multiclass.classify(models, row.point)), lines = [`multiclass kernel ${kernel.name} C ${fixed(p.multiC, 4)} classes 3 train ${train.length} test ${test.length}`, 'ovr'];
    models.ovr.forEach((model, i) => { let correct = 0; for (let j = 0; j < test.length; j++) if (sign(testResults[j].g[i]) === (test[j].class === i + 1 ? 1 : -1)) correct++; lines.push(`model ${i + 1}-rest examples ${train.length} positives ${model.labels.filter(y => y === 1).length} ${supportText(support(model))} b ${fixed(model.b, 6)} ${runInfo(model)} test ${correct}/${test.length}`); });
    lines.push('ovo'); models.ovo.forEach((model, i) => { const [a, b] = multiclass.pairs[i]; let correct = 0, count = 0; for (let j = 0; j < test.length; j++) if (test[j].class === a || test[j].class === b) { count++; if (sign(testResults[j].h[i]) === (test[j].class === a ? 1 : -1)) correct++; } lines.push(`model ${a}-${b} examples ${model.points.length} positives ${model.labels.filter(y => y === 1).length} ${supportText(support(model))} b ${fixed(model.b, 6)} ${runInfo(model)} test ${correct}/${count}`); });
    lines.push('predictions'); testResults.forEach((r, i) => lines.push(`${test[i].id} class ${test[i].class} ovr ${r.g.map(v => fixed(v, 4)).join(' ')} pred ${r.ovr} ovo ${r.h.map(v => fixed(v, 4)).join(' ')} votes ${r.votes.join(' ')} pred ${r.ovo}`));
    for (const item of [{ name: 'train', rows: train, results: trainResults }, { name: 'test', rows: test, results: testResults }]) { let ovr = 0, ovo = 0, agreement = 0, ties = 0; const { name, rows, results } = item; for (let i = 0; i < rows.length; i++) { if (results[i].ovr === rows[i].class) ovr++; if (results[i].ovo === rows[i].class) ovo++; if (results[i].ovr === results[i].ovo) agreement++; if (results[i].voteTie) ties++; } lines.push(`${name} ovr ${ovr}/${rows.length} ${ratio(ovr, rows.length)} ovo ${ovo}/${rows.length} ${ratio(ovo, rows.length)} agreement ${agreement}/${rows.length} vote_ties ${ties}`); }
    for (const kind of ['ovr', 'ovo'] as const) { const U = confusion(test.map(row => row.class), testResults.map(result => result[kind])); lines.push(`confusion ${kind}`); for (const row of U) lines.push(row.join(' ')); for (let k = 0; k < 3; k++) { let column = 0, row = 0; for (let j = 0; j < 3; j++) { column += U[j][k]; row += U[k][j]; } lines.push(`class ${k + 1} precision ${ratio(U[k][k], column)} recall ${ratio(U[k][k], row)}`); } } return lines;
}
function decisionPlots(finals: Measured[], selected: Measured, calibration: Calibration, models: Models, multiKernel: Kernel, train: Example[], multiTrain: MultiExample[], p: Parameters) {
    const W = p.width, H = p.height, dx = (p.xMax - p.xMin) / W, dy = (p.yMax - p.yMin) / H, binaryGrid: string[][] = [], probabilityGrid: string[][] = [], multiGrid: string[][] = [], signs: number[][] = finals.map(() => []), levels: number[] = Array(10).fill(0);
    for (let r = 0; r < H; r++) { binaryGrid.push([]); probabilityGrid.push([]); multiGrid.push([]); for (let c = 0; c < W; c++) { const point: Point = [p.xMin + (c + 0.5) * dx, p.yMax - (r + 0.5) * dy], values = finals.map(result => smo.decision(result.model, point)), v = values[selected.model.kernel.index]; binaryGrid[r].push(v >= 1 ? '+' : v > 0 ? '.' : v > -1 ? '-' : ' '); const digit = Math.min(9, Math.floor(probability(v, calibration.A, calibration.B) * 10)); probabilityGrid[r].push(String(digit)); levels[digit]++; for (let i = 0; i < finals.length; i++) signs[i].push(sign(values[i])); const result = multiclass.classify(models, point); multiGrid[r].push(result.ovr !== result.ovo ? '?' : [' ', '.', ':'][result.ovr - 1]); } }
    function overlay(grid: string[][], rows: { point: Point }[], prefer: (i: number, old: number) => boolean, character: (i: number) => string) {
        const owners: number[] = Array(W * H).fill(-1); let outside = 0, points = 0;
        for (let i = 0; i < rows.length; i++) { const c = Math.floor((rows[i].point[0] - p.xMin) / dx), r = Math.floor((p.yMax - rows[i].point[1]) / dy); if (c < 0 || c >= W || r < 0 || r >= H) { outside++; continue; } const cell = r * W + c; if (owners[cell] < 0) { owners[cell] = i; points++; } else if (prefer(i, owners[cell])) owners[cell] = i; }
        for (let r = 0; r < H; r++) for (let c = 0; c < W; c++) if (owners[r * W + c] >= 0) grid[r][c] = character(owners[r * W + c]); return { outside, points };
    }
    const binaryOverlay = overlay(binaryGrid, train, (i, old) => selected.model.alpha[i] > 0 && !(selected.model.alpha[old] > 0), i => train[i].label === 1 ? (selected.model.alpha[i] > 0 ? 'X' : 'x') : (selected.model.alpha[i] > 0 ? 'O' : 'o')), multiOverlay = overlay(multiGrid, multiTrain, () => false, i => String(multiTrain[i].class));
    const count = (grid: string[][], char: string) => grid.reduce((total, row) => total + row.filter(c => c === char).length, 0), frame = (grid: string[][]) => { const border = '+' + '-'.repeat(W) + '+'; return [border, ...grid.map(row => '|' + row.join('') + '|'), border]; };
    const lines = [`binary ${selected.model.kernel.name} C ${fixed(selected.model.C, 4)}`, `x ${fixed(p.xMin, 4)} ${fixed(p.xMax, 4)} y ${fixed(p.yMin, 4)} ${fixed(p.yMax, 4)} grid ${W}x${H}`, ...frame(binaryGrid), `cells outer_positive ${count(binaryGrid, '+')} inner_positive ${count(binaryGrid, '.')} inner_negative ${count(binaryGrid, '-')} outer_negative ${count(binaryGrid, ' ')} points ${binaryOverlay.points} outside ${binaryOverlay.outside}`, '', `probability ${selected.model.kernel.name} A ${fixed(calibration.A, 6)} B ${fixed(calibration.B, 6)}`, ...frame(probabilityGrid), `levels ${levels.join(' ')}`, '', 'grid_agreement'];
    for (let a = 0; a < finals.length; a++) for (let b = a + 1; b < finals.length; b++) { let agreement = 0, positiveA = 0, positiveB = 0; for (let cell = 0; cell < W * H; cell++) { if (signs[a][cell] === signs[b][cell]) agreement++; if (signs[a][cell] === 1) positiveA++; if (signs[b][cell] === 1) positiveB++; } lines.push(`${finals[a].model.kernel.name} ${finals[b].model.kernel.name} ${agreement}/${W * H} positive ${positiveA} ${positiveB}`); }
    lines.push('', `multiclass ${multiKernel.name} C ${fixed(p.multiC, 4)}`, ...frame(multiGrid), `cells class1 ${count(multiGrid, ' ')} class2 ${count(multiGrid, '.')} class3 ${count(multiGrid, ':')} disagree ${count(multiGrid, '?')} points ${multiOverlay.points} outside ${multiOverlay.outside}`); return lines;
}
function main() {
    const { train, test, multiTrain, multiTest, params: p } = read(), points = train.map(row => row.point), labels = train.map(row => row.label), matrices = p.kernels.map(kernel => kernels.matrix(kernel, points)), cv = crossValidate(train, p, matrices), finals = p.kernels.map(kernel => measure(smo.train(points, labels, matrices[kernel.index], cv.best[kernel.index].C, kernel, p), test)), selected = finals[cv.selected.kernel.index];
    const blocks = [crossValidationLines(cv, train.length, p)]; for (const result of finals) blocks.push(finalModelLines(result, train, test, p)); blocks.push(...selectedAnalyses(selected, train, test, p));
    const calibration = calibrate(cv.selected, selected, train, test, p), comparison = finals.find(result => result.model.kernel.kind === 'linear')!, peg = pegasos(train, test, comparison, p); blocks.push(calibration.lines, peg.lines, mcnemar(finals, peg.values, test));
    const modelLines: string[] = []; for (const block of blocks) { if (modelLines.length) modelLines.push(''); modelLines.push(...block); } write('output/model.txt', modelLines);
    const grid = [['kernel', 'C', ...Array.from({ length: p.folds }, (_, i) => `fold${i + 1}`), 'correct', 'accuracy', 'support_vectors', 'passes', 'steps'].join(',')]; for (const e of cv.combinations) grid.push([e.kernel.name, fixed(e.C, 4), ...e.folds.map(f => f.correct), e.correct, ratio(e.correct, train.length), e.support, e.passes, e.steps].join(',')); write('output/cv_grid.csv', grid);
    const predictions = [['id', 'label', ...p.kernels.map(kernel => kernel.name), 'pegasos', 'predicted', 'probability'].join(',')]; test.forEach((row, i) => predictions.push([row.id, row.label, ...finals.map(result => fixed(result.testValues[i], 4)), fixed(peg.values[i], 4), sign(selected.testValues[i]), fixed(calibration.probabilities[i], 4)].join(','))); write('output/predictions.csv', predictions);
    const multiKernel = p.kernels.find(kernel => kernel.name === p.multiName)!, models = multiclass.train(multiTrain, multiKernel, p.multiC, p); write('output/multiclass.txt', multiclassLines(models, multiTrain, multiTest, multiKernel, p)); write('output/decision_plot.txt', decisionPlots(finals, selected, calibration, models, multiKernel, train, multiTrain, p));
}
main();
