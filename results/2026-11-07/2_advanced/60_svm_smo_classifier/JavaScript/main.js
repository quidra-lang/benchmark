'use strict';

const dataset = require('./dataset');
const kernels = require('./kernels');
const smo = require('./smo');
const multiclass = require('./multiclass');
const { sign, fixed, ratio, folds, binary, auc, confusion, write } = require('./evaluation');

function support(model) {
  let total = 0, bound = 0, free = 0;
  for (const a of model.alpha) if (a > 0) {
    total++;
    if (a === model.C) bound++; else free++;
  }
  return { total, bound, free };
}

function supportText(sv) { return `support_vectors ${sv.total} bound ${sv.bound} free ${sv.free}`; }
function runInfo(model) {
  return `passes ${model.passes ?? model.full + model.nonbound} steps ${model.steps} converged ${model.converged ? 'yes' : 'no'}`;
}

function objective(model, alpha = model.alpha) {
  const sums = smo.trainingSums(model, alpha);
  let q = 0, total = 0;
  for (let i = 0; i < alpha.length; i++) {
    q += alpha[i] * model.labels[i] * sums[i];
    total += alpha[i];
  }
  return { sums, q, dual: total - q / 2 };
}

function measure(model, test) {
  const result = objective(model);
  const values = result.sums.map(s => s - model.b);
  const testValues = test.map(row => smo.decision(model, row.point));
  return { model, ...result, values, testValues, sv: support(model),
    trainCorrect: binary(model.labels, values).correct,
    testStats: binary(test.map(row => row.label), testValues) };
}

function crossValidate(train, params, matrices) {
  const partition = folds(train.length, params.folds), combinations = [], best = [];
  for (const kernel of params.kernels) {
    let winner = null;
    for (const C of params.cs) {
      const result = { kernel, C, correct: 0, support: 0, passes: 0, steps: 0,
        values: Array(train.length).fill(0), folds: [] };
      for (const fold of partition) {
        const model = smo.train(fold.train.map(i => train[i].point), fold.train.map(i => train[i].label),
          kernels.subset(matrices[kernel.index], fold.train), C, kernel, params);
        let correct = 0;
        for (const i of fold.test) {
          result.values[i] = smo.decision(model, train[i].point);
          if (sign(result.values[i]) === train[i].label) correct++;
        }
        const sv = support(model), passes = model.full + model.nonbound;
        result.folds.push({ train: fold.train.length, test: fold.test.length, correct,
          support: sv.total, passes, steps: model.steps, converged: model.converged });
        result.correct += correct; result.support += sv.total;
        result.passes += passes; result.steps += model.steps;
      }
      combinations.push(result);
      if (winner === null || result.correct > winner.correct) winner = result;
    }
    best.push(winner);
  }
  const ranking = combinations.slice().sort((a, b) => b.correct - a.correct || a.C - b.C || a.kernel.index - b.kernel.index);
  return { combinations, best, ranking, selected: ranking[0] };
}

function crossValidationLines(cv, n, params) {
  const lines = [`cross_validation folds ${params.folds} examples ${n}`];
  for (const best of cv.best) lines.push(`best ${best.kernel.name} C ${fixed(best.C, 4)} correct ${best.correct}/${n} accuracy ${ratio(best.correct, n)}`);
  lines.push(`selected ${cv.selected.kernel.name} C ${fixed(cv.selected.C, 4)}`, 'ranking');
  cv.ranking.forEach((entry, i) => lines.push(`${i + 1} ${entry.kernel.name} C ${fixed(entry.C, 4)} correct ${entry.correct}/${n}`));
  lines.push(`cv_detail ${cv.selected.kernel.name} C ${fixed(cv.selected.C, 4)}`);
  cv.selected.folds.forEach((fold, i) => {
    lines.push(`fold ${i + 1} train ${fold.train} test ${fold.test} correct ${fold.correct} support_vectors ${fold.support} ${runInfo(fold)}`);
  });
  return lines;
}

function finalModelLines(result, train, test, params) {
  const { model, q, dual, values, testValues, sv, trainCorrect, testStats } = result;
  const n = train.length, m = test.length;
  let sy = 0, sg = 0, maximum = -Infinity, minimum = Infinity;
  for (let i = 0; i < n; i++) {
    maximum = Math.max(maximum, model.Q[i][i]);
    for (let j = 0; j < n; j++) {
      sy += model.labels[i] * model.labels[j] * model.Q[i][j];
      sg += model.Q[i][j] * model.Q[i][j];
      minimum = Math.min(minimum, model.Q[i][j]);
    }
  }
  const radius = maximum - minimum, norm = Math.sqrt(q);
  let equality = 0, w1 = 0, w2 = 0, xi = 0, violations = 0, maxViolation = 0, estimatedErrors = 0;
  const byClass = { positive: { bound: 0, free: 0 }, negative: { bound: 0, free: 0 } };
  for (let i = 0; i < n; i++) {
    const a = model.alpha[i], y = model.labels[i];
    equality += a * y;
    w1 += a * y * train[i].point[0]; w2 += a * y * train[i].point[1];
    const hinge = Math.max(0, 1 - y * values[i]), r = y * values[i] - 1;
    xi += hinge;
    const violation = a === 0 ? Math.max(0, -r) : a === model.C ? Math.max(0, r) : Math.abs(r);
    if (violation > params.tau) violations++;
    maxViolation = Math.max(maxViolation, violation);
    if (2 * a * radius + hinge >= 1) estimatedErrors++;
    if (a > 0) byClass[y === 1 ? 'positive' : 'negative'][a === model.C ? 'bound' : 'free']++;
  }
  result.weights = [w1, w2];
  const primal = q / 2 + model.C * xi;
  let inside = 0, positiveSum = 0, negativeSum = 0, positives = 0, negatives = 0;
  for (let i = 0; i < m; i++) {
    if (Math.abs(testValues[i]) < 1) inside++;
    if (test[i].label === 1) { positiveSum += testValues[i]; positives++; }
    else { negativeSum += testValues[i]; negatives++; }
  }
  const lines = [`model ${model.kernel.name}`, `kernel ${kernels.description(model.kernel)}`,
    `C ${fixed(model.C, 4)}`, `alignment ${fixed(sy / (n * Math.sqrt(sg)), 6)}`,
    `passes ${model.full + model.nonbound} full ${model.full} nonbound ${model.nonbound} converged ${model.converged ? 'yes' : 'no'}`,
    `examined ${model.examined} steps ${model.steps}`,
    `choice heuristic ${model.choice.heuristic} nonbound_loop ${model.choice.nonbound_loop} full_loop ${model.choice.full_loop}`,
    `clipping none ${model.clipping.none} lower ${model.clipping.lower} upper ${model.clipping.upper}`,
    supportText(sv), `b ${fixed(model.b, 6)}`, `equality ${fixed(equality, 6)}`];
  if (model.kernel.kind === 'linear') lines.push(`w ${fixed(w1, 6)} ${fixed(w2, 6)}`);
  const { positive, negative } = byClass, { tp, fp, tn, fn, correct } = testStats;
  lines.push(`sv_by_class positive bound ${positive.bound} free ${positive.free} negative bound ${negative.bound} free ${negative.free}`,
    `norm ${fixed(norm, 6)} margin ${fixed(2 / norm, 6)}`, `dual_objective ${fixed(dual, 6)}`,
    `primal_objective ${fixed(primal, 6)}`, `duality_gap ${fixed(primal - dual, 6)}`,
    `kkt_violations ${violations} max ${fixed(maxViolation, 6)}`,
    `xi_alpha radius ${fixed(radius, 6)} errors ${estimatedErrors}/${n} accuracy ${ratio(n - estimatedErrors, n)}`,
    `train correct ${trainCorrect}/${n} accuracy ${ratio(trainCorrect, n)}`,
    `test correct ${correct}/${m} accuracy ${ratio(correct, m)} tp ${tp} fp ${fp} tn ${tn} fn ${fn}`,
    `test precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)} f1 ${ratio(2 * tp, 2 * tp + fp + fn)} auc ${fixed(auc(test.map(row => row.label), testValues), 4)}`,
    `test inside_margin ${inside}`,
    `test mean_decision positive ${fixed(positiveSum / positives, 4)} negative ${fixed(negativeSum / negatives, 4)}`);
  for (let i = 0; i < n; i++) if (model.alpha[i] > 0) {
    lines.push(`sv ${train[i].id} y ${model.labels[i]} alpha ${fixed(model.alpha[i], 6)} f ${fixed(values[i], 4)} ${model.alpha[i] === model.C ? 'bound' : 'free'}`);
  }
  return lines;
}

function trainingLog(model) {
  const lines = [`training_log ${model.kernel.name}`];
  for (let i = 0; i < model.records.length;) {
    const first = model.records[i];
    if (first.kind === 'full') {
      lines.push(`pass ${first.number} full examined ${first.examined} changed ${first.changed} dual_objective ${fixed(objective(model, first.alpha).dual, 6)}`);
      i++;
    } else {
      let examined = 0, changed = 0, last = first.number;
      while (i < model.records.length && model.records[i].kind === 'nonbound') {
        const record = model.records[i++];
        examined += record.examined; changed += record.changed; last = record.number;
      }
      lines.push(`passes ${first.number}-${last} nonbound examined ${examined} changed ${changed}`);
    }
  }
  return lines;
}

function selectedAnalyses(selected, train, test, params) {
  const { model } = selected, n = train.length, m = test.length;
  const path = [`c_path ${model.kernel.name}`];
  for (const C of params.cs) {
    const fitted = smo.train(model.points, model.labels, model.Q, C, model.kernel, params);
    const result = measure(fitted, test);
    path.push(`C ${fixed(C, 4)} ${supportText(result.sv)} dual_objective ${fixed(result.dual, 6)} train ${result.trainCorrect}/${n} test ${result.testStats.correct}/${m} ${runInfo(fitted)}`);
  }
  const learning = [`learning_curve ${model.kernel.name} C ${fixed(model.C, 4)}`];
  for (const fraction of params.learningCurve) {
    const size = Math.floor(n * fraction / 100), indices = Array.from({ length: size }, (_, i) => i);
    const fitted = smo.train(model.points.slice(0, size), model.labels.slice(0, size),
      kernels.subset(model.Q, indices), model.C, model.kernel, params);
    const result = measure(fitted, test);
    learning.push(`size ${size} support_vectors ${result.sv.total} train ${result.trainCorrect}/${size} test ${result.testStats.correct}/${m} ${runInfo(fitted)}`);
  }
  return [trainingLog(model), path, learning];
}

function probability(value, A, B) { return 1 / (1 + Math.exp(A * value + B)); }

function calibrate(selectedCV, selected, train, test, params) {
  const values = selectedCV.values, n = train.length, m = test.length;
  let positives = 0;
  for (const row of train) if (row.label === 1) positives++;
  const negatives = n - positives;
  const targets = train.map(row => row.label === 1 ? (positives + 1) / (positives + 2) : 1 / (negatives + 2));
  let A = 0, B = Math.log((negatives + 1) / (positives + 1));
  function nll() {
    let sum = 0;
    for (let i = 0; i < n; i++) {
      const p = probability(values[i], A, B), target = targets[i];
      sum += target * Math.log(p) + (1 - target) * Math.log(1 - p);
    }
    return -sum;
  }
  const lines = [`calibration ${selected.model.kernel.name} C ${fixed(selected.model.C, 4)} positives ${positives} negatives ${negatives}`,
    `start A ${fixed(A, 6)} B ${fixed(B, 6)} nll ${fixed(nll(), 6)}`];
  for (let iteration = 1; iteration <= params.newtonIterations; iteration++) {
    let g1 = 0, g2 = 0, h11 = 0, h21 = 0, h22 = 0;
    for (let i = 0; i < n; i++) {
      const v = values[i], p = probability(v, A, B), target = targets[i];
      g1 += v * (target - p); g2 += target - p;
      h11 += v * v * p * (1 - p); h21 += v * p * (1 - p); h22 += p * (1 - p);
    }
    const det = h11 * h22 - h21 * h21;
    const nextA = A - (h22 * g1 - h21 * g2) / det;
    const nextB = B - (h11 * g2 - h21 * g1) / det;
    A = nextA; B = nextB;
    lines.push(`iteration ${iteration} A ${fixed(A, 6)} B ${fixed(B, 6)} nll ${fixed(nll(), 6)}`);
  }
  const probabilities = selected.testValues.map(value => probability(value, A, B));
  const bins = Array.from({ length: 5 }, () => ({ count: 0, sum: 0, positive: 0 }));
  let logSum = 0, brierSum = 0;
  for (let i = 0; i < m; i++) {
    const p = probabilities[i], positive = test[i].label === 1;
    logSum += Math.log(positive ? p : 1 - p);
    const error = p - (positive ? 1 : 0);
    brierSum += error * error;
    const bin = bins[Math.min(4, Math.floor(p * 5))];
    bin.count++; bin.sum += p;
    if (positive) bin.positive++;
  }
  lines.push(`test log_loss ${fixed(-logSum / m, 6)} brier ${fixed(brierSum / m, 6)}`);
  const ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0'];
  bins.forEach((bin, i) => lines.push(`bin ${ranges[i]} count ${bin.count} mean_probability ${bin.count ? fixed(bin.sum / bin.count, 4) : '-'} positive_rate ${ratio(bin.positive, bin.count)}`));
  const closest = Array.from({ length: m }, (_, i) => i).sort((a, b) =>
    Math.abs(selected.testValues[a]) - Math.abs(selected.testValues[b]) || a - b).slice(0, 5);
  for (const i of closest) lines.push(`closest ${test[i].id} label ${test[i].label} decision ${fixed(selected.testValues[i], 4)} probability ${fixed(probabilities[i], 4)}`);
  return { A, B, probabilities, lines };
}

function linearValue(weights, point) { return weights[0] * point[0] + weights[1] * point[1] + weights[2]; }

function pegasos(train, test, comparison, params) {
  const { lambda, iterations, seed } = params.pegasos, n = train.length, m = test.length;
  let rho = seed, w1 = 0, w2 = 0, w0 = 0, s1 = 0, s2 = 0, s0 = 0, updates = 0;
  const lines = [`pegasos lambda ${fixed(lambda, 4)} iterations ${iterations} seed ${seed}`];
  for (let t = 1; t <= iterations; t++) {
    rho = (48271 * rho) % 2147483647;
    const row = train[rho % n], eta = 1 / (lambda * t), sigma = 1 - eta * lambda;
    const oldValue = w1 * row.point[0] + w2 * row.point[1] + w0;
    if (row.label * oldValue < 1) {
      w1 = sigma * w1 + eta * row.label * row.point[0];
      w2 = sigma * w2 + eta * row.label * row.point[1];
      w0 = sigma * w0 + eta * row.label;
      updates++;
    } else { w1 = sigma * w1; w2 = sigma * w2; w0 = sigma * w0; }
    s1 += w1; s2 += w2; s0 += w0;
    if (t % (iterations / 10) === 0) {
      let xi = 0, correct = 0;
      for (const example of train) {
        const value = w1 * example.point[0] + w2 * example.point[1] + w0;
        xi += Math.max(0, 1 - example.label * value);
        if (sign(value) === example.label) correct++;
      }
      const objective = lambda / 2 * (w1 * w1 + w2 * w2 + w0 * w0) + xi / n;
      lines.push(`checkpoint ${t} objective ${fixed(objective, 6)} train ${correct}/${n}`);
    }
  }
  const weights = [w1, w2, w0], average = [s1 / iterations, s2 / iterations, s0 / iterations];
  const values = test.map(row => linearValue(weights, row.point));
  const trainCorrect = binary(train.map(row => row.label), train.map(row => linearValue(weights, row.point))).correct;
  const testCorrect = binary(test.map(row => row.label), values).correct;
  const averageCorrect = binary(test.map(row => row.label), test.map(row => linearValue(average, row.point))).correct;
  const [v1, v2] = comparison.weights;
  const cosine = (w1 * v1 + w2 * v2) / (Math.sqrt(w1 * w1 + w2 * w2) * Math.sqrt(v1 * v1 + v2 * v2));
  let agreement = 0;
  for (let i = 0; i < m; i++) if (sign(values[i]) === sign(comparison.testValues[i])) agreement++;
  lines.push(`updates ${updates}`, `w ${fixed(w1, 6)} ${fixed(w2, 6)} bias ${fixed(w0, 6)}`,
    `train correct ${trainCorrect}/${n} accuracy ${ratio(trainCorrect, n)}`,
    `test correct ${testCorrect}/${m} accuracy ${ratio(testCorrect, m)}`,
    `average w ${fixed(average[0], 6)} ${fixed(average[1], 6)} bias ${fixed(average[2], 6)} test correct ${averageCorrect}/${m}`,
    `compare ${comparison.model.kernel.name} cosine ${fixed(cosine, 6)} test_agreement ${agreement}/${m}`);
  return { weights, values, lines };
}

function mcnemar(finals, peg, test) {
  const comparisons = finals.map(result => ({ name: result.model.kernel.name, values: result.testValues }));
  comparisons.push({ name: 'pegasos', values: peg.values });
  const lines = ['mcnemar'];
  for (let a = 0; a < comparisons.length; a++) for (let b = a + 1; b < comparisons.length; b++) {
    let first = 0, second = 0;
    for (let i = 0; i < test.length; i++) {
      const correctA = sign(comparisons[a].values[i]) === test[i].label;
      const correctB = sign(comparisons[b].values[i]) === test[i].label;
      if (correctA && !correctB) first++;
      if (correctB && !correctA) second++;
    }
    const difference = Math.abs(first - second) - 1;
    const chi = first + second > 0 ? fixed(difference * difference / (first + second), 4) : '-';
    lines.push(`${comparisons[a].name} ${comparisons[b].name} only_first ${first} only_second ${second} chi2 ${chi}`);
  }
  return lines;
}

function multiclassLines(models, train, test, kernel, params) {
  const trainResults = train.map(row => multiclass.classify(models, row.point));
  const testResults = test.map(row => multiclass.classify(models, row.point));
  const lines = [`multiclass kernel ${kernel.name} C ${fixed(params.multiC, 4)} classes 3 train ${train.length} test ${test.length}`, 'ovr'];
  models.ovr.forEach((model, i) => {
    const positives = model.labels.filter(y => y === 1).length;
    let correct = 0;
    for (let j = 0; j < test.length; j++) if (sign(testResults[j].g[i]) === (test[j].class === i + 1 ? 1 : -1)) correct++;
    lines.push(`model ${i + 1}-rest examples ${train.length} positives ${positives} ${supportText(support(model))} b ${fixed(model.b, 6)} ${runInfo(model)} test ${correct}/${test.length}`);
  });
  lines.push('ovo');
  models.ovo.forEach((model, i) => {
    const [a, b] = multiclass.pairs[i], positives = model.labels.filter(y => y === 1).length;
    let correct = 0, count = 0;
    for (let j = 0; j < test.length; j++) if (test[j].class === a || test[j].class === b) {
      count++;
      if (sign(testResults[j].h[i]) === (test[j].class === a ? 1 : -1)) correct++;
    }
    lines.push(`model ${a}-${b} examples ${model.points.length} positives ${positives} ${supportText(support(model))} b ${fixed(model.b, 6)} ${runInfo(model)} test ${correct}/${count}`);
  });
  lines.push('predictions');
  testResults.forEach((result, i) => {
    lines.push(`${test[i].id} class ${test[i].class} ovr ${result.g.map(v => fixed(v, 4)).join(' ')} pred ${result.ovr} ovo ${result.h.map(v => fixed(v, 4)).join(' ')} votes ${result.votes.join(' ')} pred ${result.ovo}`);
  });
  for (const [name, rows, results] of [['train', train, trainResults], ['test', test, testResults]]) {
    let ovr = 0, ovo = 0, agreement = 0, ties = 0;
    for (let i = 0; i < rows.length; i++) {
      if (results[i].ovr === rows[i].class) ovr++;
      if (results[i].ovo === rows[i].class) ovo++;
      if (results[i].ovr === results[i].ovo) agreement++;
      if (results[i].voteTie) ties++;
    }
    lines.push(`${name} ovr ${ovr}/${rows.length} ${ratio(ovr, rows.length)} ovo ${ovo}/${rows.length} ${ratio(ovo, rows.length)} agreement ${agreement}/${rows.length} vote_ties ${ties}`);
  }
  for (const kind of ['ovr', 'ovo']) {
    const U = confusion(test.map(row => row.class), testResults.map(result => result[kind]));
    lines.push(`confusion ${kind}`);
    for (const row of U) lines.push(row.join(' '));
    for (let k = 0; k < 3; k++) {
      let column = 0, row = 0;
      for (let j = 0; j < 3; j++) { column += U[j][k]; row += U[k][j]; }
      lines.push(`class ${k + 1} precision ${ratio(U[k][k], column)} recall ${ratio(U[k][k], row)}`);
    }
  }
  return lines;
}

function decisionPlots(finals, selected, calibration, multiModels, multiKernel, train, multiTrain, params) {
  const W = params.width, H = params.height;
  const dx = (params.xMax - params.xMin) / W, dy = (params.yMax - params.yMin) / H;
  const binaryGrid = [], probabilityGrid = [], multiGrid = [], signs = finals.map(() => []);
  const levels = Array(10).fill(0);
  for (let r = 0; r < H; r++) {
    binaryGrid.push([]); probabilityGrid.push([]); multiGrid.push([]);
    for (let c = 0; c < W; c++) {
      const point = [params.xMin + (c + 0.5) * dx, params.yMax - (r + 0.5) * dy];
      const values = finals.map(result => smo.decision(result.model, point));
      const value = values[selected.model.kernel.index];
      binaryGrid[r].push(value >= 1 ? '+' : value > 0 ? '.' : value > -1 ? '-' : ' ');
      const digit = Math.min(9, Math.floor(probability(value, calibration.A, calibration.B) * 10));
      probabilityGrid[r].push(String(digit)); levels[digit]++;
      for (let i = 0; i < finals.length; i++) signs[i].push(sign(values[i]));
      const result = multiclass.classify(multiModels, point);
      multiGrid[r].push(result.ovr !== result.ovo ? '?' : [' ', '.', ':'][result.ovr - 1]);
    }
  }
  function overlay(grid, rows, prefer, character) {
    const owners = Array(W * H).fill(-1);
    let outside = 0, points = 0;
    for (let i = 0; i < rows.length; i++) {
      const c = Math.floor((rows[i].point[0] - params.xMin) / dx);
      const r = Math.floor((params.yMax - rows[i].point[1]) / dy);
      if (c < 0 || c >= W || r < 0 || r >= H) { outside++; continue; }
      const cell = r * W + c;
      if (owners[cell] < 0) { owners[cell] = i; points++; }
      else if (prefer(i, owners[cell])) owners[cell] = i;
    }
    for (let r = 0; r < H; r++) for (let c = 0; c < W; c++) {
      if (owners[r * W + c] >= 0) grid[r][c] = character(owners[r * W + c]);
    }
    return { outside, points };
  }
  const binaryOverlay = overlay(binaryGrid, train,
    (i, old) => selected.model.alpha[i] > 0 && !(selected.model.alpha[old] > 0),
    i => train[i].label === 1 ? (selected.model.alpha[i] > 0 ? 'X' : 'x') : (selected.model.alpha[i] > 0 ? 'O' : 'o'));
  const multiOverlay = overlay(multiGrid, multiTrain, () => false, i => String(multiTrain[i].class));
  function count(grid, character) {
    let total = 0;
    for (const row of grid) for (const cell of row) if (cell === character) total++;
    return total;
  }
  function frame(grid) {
    const border = '+' + '-'.repeat(W) + '+';
    return [border, ...grid.map(row => '|' + row.join('') + '|'), border];
  }
  const lines = [`binary ${selected.model.kernel.name} C ${fixed(selected.model.C, 4)}`,
    `x ${fixed(params.xMin, 4)} ${fixed(params.xMax, 4)} y ${fixed(params.yMin, 4)} ${fixed(params.yMax, 4)} grid ${W}x${H}`,
    ...frame(binaryGrid),
    `cells outer_positive ${count(binaryGrid, '+')} inner_positive ${count(binaryGrid, '.')} inner_negative ${count(binaryGrid, '-')} outer_negative ${count(binaryGrid, ' ')} points ${binaryOverlay.points} outside ${binaryOverlay.outside}`,
    '', `probability ${selected.model.kernel.name} A ${fixed(calibration.A, 6)} B ${fixed(calibration.B, 6)}`,
    ...frame(probabilityGrid), `levels ${levels.join(' ')}`, '', 'grid_agreement'];
  for (let a = 0; a < finals.length; a++) for (let b = a + 1; b < finals.length; b++) {
    let agreement = 0, positiveA = 0, positiveB = 0;
    for (let cell = 0; cell < W * H; cell++) {
      if (signs[a][cell] === signs[b][cell]) agreement++;
      if (signs[a][cell] === 1) positiveA++;
      if (signs[b][cell] === 1) positiveB++;
    }
    lines.push(`${finals[a].model.kernel.name} ${finals[b].model.kernel.name} ${agreement}/${W * H} positive ${positiveA} ${positiveB}`);
  }
  lines.push('', `multiclass ${multiKernel.name} C ${fixed(params.multiC, 4)}`, ...frame(multiGrid),
    `cells class1 ${count(multiGrid, ' ')} class2 ${count(multiGrid, '.')} class3 ${count(multiGrid, ':')} disagree ${count(multiGrid, '?')} points ${multiOverlay.points} outside ${multiOverlay.outside}`);
  return lines;
}

function main() {
  const { train, test, multiTrain, multiTest, params } = dataset.read();
  const points = train.map(row => row.point), labels = train.map(row => row.label);
  const matrices = params.kernels.map(kernel => kernels.matrix(kernel, points));
  const cv = crossValidate(train, params, matrices);
  const finals = params.kernels.map(kernel => measure(smo.train(points, labels, matrices[kernel.index],
    cv.best[kernel.index].C, kernel, params), test));
  const selected = finals[cv.selected.kernel.index];
  const blocks = [crossValidationLines(cv, train.length, params)];
  for (const result of finals) blocks.push(finalModelLines(result, train, test, params));
  for (const block of selectedAnalyses(selected, train, test, params)) blocks.push(block);
  const calibration = calibrate(cv.selected, selected, train, test, params);
  blocks.push(calibration.lines);
  const comparison = finals.find(result => result.model.kernel.kind === 'linear');
  const peg = pegasos(train, test, comparison, params);
  blocks.push(peg.lines, mcnemar(finals, peg, test));
  const modelLines = [];
  for (const block of blocks) {
    if (modelLines.length) modelLines.push('');
    for (const line of block) modelLines.push(line);
  }
  write('output/model.txt', modelLines);
  const grid = [['kernel', 'C', ...Array.from({ length: params.folds }, (_, i) => `fold${i + 1}`),
    'correct', 'accuracy', 'support_vectors', 'passes', 'steps'].join(',')];
  for (const entry of cv.combinations) grid.push([entry.kernel.name, fixed(entry.C, 4),
    ...entry.folds.map(fold => fold.correct), entry.correct, ratio(entry.correct, train.length),
    entry.support, entry.passes, entry.steps].join(','));
  write('output/cv_grid.csv', grid);
  const predictions = [['id', 'label', ...params.kernels.map(kernel => kernel.name), 'pegasos', 'predicted', 'probability'].join(',')];
  test.forEach((row, i) => predictions.push([row.id, row.label, ...finals.map(result => fixed(result.testValues[i], 4)),
    fixed(peg.values[i], 4), sign(selected.testValues[i]), fixed(calibration.probabilities[i], 4)].join(',')));
  write('output/predictions.csv', predictions);
  const multiKernel = params.kernels.find(kernel => kernel.name === params.multiName);
  const multiModels = multiclass.train(multiTrain, multiKernel, params.multiC, params);
  write('output/multiclass.txt', multiclassLines(multiModels, multiTrain, multiTest, multiKernel, params));
  write('output/decision_plot.txt', decisionPlots(finals, selected, calibration, multiModels, multiKernel, train, multiTrain, params));
}

main();
