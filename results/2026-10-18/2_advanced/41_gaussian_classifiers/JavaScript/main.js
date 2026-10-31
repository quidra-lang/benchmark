'use strict';

const fs = require('node:fs');
const { readDataset } = require('./dataset');
const algebra = require('./linalg');
const { train, predict, predictRow } = require('./gaussian_models');
const { fraction, confusion, mcnemar, Random } = require('./evaluation');
const { real, fractionText, frame, cell, writeLines } = require('./plot');

const MODELS = ['NB', 'LDA', 'QDA'];
const fields = (...values) => values.join(' ');
const reals = values => values.map(real).join(' ');
const ratio = (numerator, denominator) => fractionText(fraction(numerator, denominator));
const predictions = values => values.map(value => value.predicted);

function sections(parts) {
  const lines = [];
  parts.forEach((part, index) => {
    if (index > 0) lines.push('');
    lines.push(...part);
  });
  return lines;
}

function correctCount(rows, predicted) {
  let count = 0;
  rows.forEach((row, index) => { if (row.class === predicted[index]) count++; });
  return count;
}

function fit(data, type, features = data.all, rows = data.train, changes = {}) {
  return train(rows, features, type, { ...data.settings, ...changes }, data.classes.length);
}

function classifyRows(model, rows, costs = null) {
  return rows.map(row => predictRow(model, row, costs));
}

function crossValidation(data, type, features = data.all, changes = {}) {
  const settings = { ...data.settings, ...changes };
  const key = JSON.stringify([type, features, settings.prior, settings.epsilon, settings.gamma]);
  if (data.cv.has(key)) return data.cv.get(key);
  const predicted = Array(data.train.length).fill(0);
  const folds = Array(settings.folds).fill(0);
  for (let fold = 0; fold < settings.folds; fold++) {
    const rows = data.train.filter(row => row.id % settings.folds !== fold);
    const model = fit(data, type, features, rows, changes);
    data.train.forEach((row, index) => {
      if (row.id % settings.folds !== fold) return;
      predicted[index] = predictRow(model, row).predicted;
      if (predicted[index] === row.class) folds[fold]++;
    });
  }
  const result = { predicted, folds, correct: correctCount(data.train, predicted) };
  data.cv.set(key, result);
  return result;
}

function modelReport(data, models) {
  const [nb, lda, qda] = models;
  const names = data.classes;
  const settings = data.settings;
  const parts = [];
  const description = [fields('features', ...data.features), fields('classes', ...names), fields('prior_mode', settings.prior)];
  nb.classes.forEach((group, index) => {
    description.push(fields('class', names[index], 'letter', names[index][0].toUpperCase(), 'count', group.count,
      'prior', real(group.prior), 'mean', reals(group.mean)));
  });
  parts.push(description);
  const naive = ['model NB', fields('smoothing epsilon', real(settings.epsilon), 'max_variance', real(nb.maximumVariance), 'added', real(nb.added))];
  nb.classes.forEach((group, index) => {
    naive.push(fields('class', names[index], 'variance', reals(group.covariance.map((row, feature) => row[feature])),
      'log_det', real(group.logDeterminant)));
  });
  parts.push(naive);
  const linear = ['model LDA', fields('log_det', real(lda.classes[0].logDeterminant))];
  for (const row of lda.classes[0].covariance) linear.push('  ' + reals(row));
  for (let index = 0; index < names.length; index++) {
    const group = lda.classes[index];
    const coefficient = algebra.backward(group.lower, algebra.forward(group.lower, group.mean));
    let product = 0;
    for (let feature = 0; feature < data.features.length; feature++) product += group.mean[feature] * coefficient[feature];
    const intercept = Math.log(group.prior) - product / 2;
    linear.push(fields('class', names[index], 'intercept', real(intercept), 'coef', reals(coefficient)));
  }
  parts.push(linear);
  const quadratic = [fields('model QDA gamma', real(settings.gamma))];
  qda.classes.forEach((group, index) => {
    const eigenvalues = algebra.jacobi(group.covariance).values.sort((a, b) => b - a);
    quadratic.push(fields('class', names[index], 'log_det', real(group.logDeterminant), 'eigenvalues', reals(eigenvalues),
      'condition', real(eigenvalues[0] / eigenvalues.at(-1))));
    for (const row of group.covariance) quadratic.push('  ' + reals(row));
  });
  parts.push(quadratic);
  const separation = ['separation'];
  for (let first = 0; first < names.length; first++) {
    for (let second = first + 1; second < names.length; second++) {
      const a = qda.classes[first];
      const b = qda.classes[second];
      const difference = a.mean.map((value, index) => value - b.mean[index]);
      const average = a.covariance.map((row, i) => row.map((value, j) => (value + b.covariance[i][j]) / 2));
      const lower = algebra.cholesky(average);
      const mahalanobis = Math.sqrt(algebra.quadratic(lda.classes[0].lower, difference));
      const bhattacharyya = algebra.quadratic(lower, difference) / 8
        + (algebra.logDeterminant(lower) - (a.logDeterminant + b.logDeterminant) / 2) / 2;
      separation.push(fields(names[first], names[second], 'mahalanobis', real(mahalanobis), 'bhattacharyya', real(bhattacharyya)));
    }
  }
  parts.push(separation);
  const outliers = [];
  data.train.forEach((row, index) => {
    const q = predictRow(qda, row).distances[row.class];
    if (q > settings.outlier) outliers.push({ row, index, q });
  });
  outliers.sort((a, b) => b.q - a.q || a.index - b.index);
  parts.push([fields('outliers threshold', real(settings.outlier)),
    ...outliers.map(item => fields(item.row.id, item.row.label, 'q', real(item.q))), fields('count', outliers.length)]);
  return sections(parts);
}

function predictionReport(data, results) {
  const lines = [['id', 'model', 'actual', 'predicted', 'decision', ...data.classes].join(',')];
  data.test.forEach((row, index) => {
    MODELS.forEach((name, model) => {
      const result = results[model][index];
      lines.push([row.id, name, row.label, data.classes[result.predicted], data.classes[result.decision],
        ...result.posterior.map(real)].join(','));
    });
  });
  return lines;
}

function confusionLines(data, metrics) {
  return metrics.table.map((row, index) => fields('confusion', data.classes[index], ...row));
}

function evaluateModel(data, type, results) {
  const predicted = predictions(results);
  const metrics = confusion(data.test, predicted, data.classes.length);
  const lines = [fields('model', type), ...confusionLines(data, metrics),
    fields('accuracy', fractionText(metrics.accuracy)), fields('balanced_accuracy', fractionText(metrics.balanced)),
    fields('kappa', fractionText(metrics.kappa))];
  metrics.classes.forEach((group, index) => {
    lines.push(fields('class', data.classes[index], 'support', group.support, 'recall', fractionText(group.recall),
      'precision', fractionText(group.precision), 'f1', fractionText(group.f1)));
  });
  let logProbability = 0;
  data.test.forEach((row, index) => { logProbability += results[index].logPosterior[row.class]; });
  lines.push(fields('macro_f1', real(metrics.macroF1)), fields('log_loss', real(-logProbability / data.test.length)),
    fields('errors', data.test.length - metrics.correct));
  data.test.forEach((row, index) => {
    if (row.class !== predicted[index]) lines.push(fields('error', row.id, 'actual', row.label,
      'predicted', data.classes[predicted[index]], 'confidence', real(results[index].confidence)));
  });
  const edges = [0, ...data.settings.calibration, 1];
  let calibrationError = 0;
  for (let bin = 0; bin + 1 < edges.length; bin++) {
    let count = 0;
    let correct = 0;
    let confidence = 0;
    data.test.forEach((row, index) => {
      const value = results[index].confidence;
      if (value < edges[bin] || (bin + 2 === edges.length ? value > edges[bin + 1] : value >= edges[bin + 1])) return;
      count++;
      if (row.class === predicted[index]) correct++;
      confidence += value;
    });
    lines.push(fields('bin', real(edges[bin]), real(edges[bin + 1]), 'count', count,
      'confidence', count === 0 ? '-' : real(confidence / count), 'accuracy', ratio(correct, count)));
    calibrationError += Math.abs(correct - confidence);
  }
  lines.push(fields('ece', real(calibrationError / data.test.length)));
  for (const threshold of data.settings.reject) {
    let count = 0;
    let correct = 0;
    data.test.forEach((row, index) => {
      if (results[index].confidence < threshold) return;
      count++;
      if (row.class === predicted[index]) correct++;
    });
    lines.push(fields('reject', real(threshold), 'accepted', count, 'coverage', ratio(count, data.test.length),
      'accuracy', ratio(correct, count)));
  }
  return lines;
}

function comparisonLines(rows, names, predicted) {
  const lines = [];
  for (let first = 0; first < names.length; first++) {
    for (let second = first + 1; second < names.length; second++) {
      const result = mcnemar(rows, predicted[first], predicted[second]);
      lines.push(fields(names[first], names[second], 'b01', result.b01, 'b10', result.b10,
        'chi2', real(result.chi2), 'significant', result.significant ? 'yes' : 'no'));
    }
  }
  return lines;
}

function bootstrapReport(data, predicted) {
  const settings = data.settings;
  const random = new Random(settings.seed);
  const samples = MODELS.map(() => []);
  for (let resample = 0; resample < settings.resamples; resample++) {
    const counts = [0, 0, 0];
    for (let draw = 0; draw < data.test.length; draw++) {
      const index = random.next() % data.test.length;
      for (let model = 0; model < MODELS.length; model++) if (predicted[model][index] === data.test[index].class) counts[model]++;
    }
    counts.forEach((count, model) => samples[model].push(count));
  }
  const lines = [fields('bootstrap resamples', settings.resamples, 'seed', settings.seed)];
  const offset = Math.floor(settings.resamples / 40);
  samples.forEach((sample, model) => {
    const ordered = sample.slice().sort((a, b) => a - b);
    let total = 0;
    for (const count of sample) total += count;
    lines.push(fields(MODELS[model], 'mean', real(total / settings.resamples / data.test.length),
      'interval', ratio(ordered[offset], data.test.length), ratio(ordered[ordered.length - 1 - offset], data.test.length)));
  });
  for (let first = 0; first < MODELS.length; first++) {
    for (let second = first + 1; second < MODELS.length; second++) {
      let wins = 0;
      let ties = 0;
      let losses = 0;
      for (let index = 0; index < settings.resamples; index++) {
        if (samples[first][index] > samples[second][index]) wins++;
        else if (samples[first][index] === samples[second][index]) ties++;
        else losses++;
      }
      lines.push(fields(MODELS[first], MODELS[second], 'wins', wins, 'ties', ties, 'losses', losses));
    }
  }
  return lines;
}

function subsetReport(data) {
  const sizes = Array(data.settings.folds).fill(0);
  for (const row of data.train) sizes[row.id % data.settings.folds]++;
  const lines = [fields('cross_validation folds', data.settings.folds), fields('fold_sizes', ...sizes)];
  let best = null;
  for (const subset of data.settings.subsets) {
    lines.push(fields('subset', subset.name, 'features', ...subset.features.map(feature => data.features[feature])));
    for (const type of MODELS) {
      const result = crossValidation(data, type, subset.features);
      lines.push('  ' + fields(type, 'fold_correct', ...result.folds, 'correct', result.correct, 'accuracy', ratio(result.correct, data.train.length)));
      if (best === null || result.correct > best.correct
        || (result.correct === best.correct && subset.features.length < best.subset.features.length)) {
        best = { subset, type, correct: result.correct };
      }
    }
  }
  const model = fit(data, best.type, best.subset.features);
  const count = correctCount(data.test, predictions(classifyRows(model, data.test)));
  lines.push(fields('best subset', best.subset.name, 'model', best.type, 'correct', best.correct, 'accuracy', ratio(best.correct, data.train.length)),
    fields('refit_test correct', count, 'accuracy', ratio(count, data.test.length)));
  return lines;
}

function leaveOneOutReport(data) {
  const lines = ['leave_one_out'];
  for (const type of MODELS) {
    let correct = 0;
    data.train.forEach((row, index) => {
      const remaining = data.train.filter((_, other) => other !== index);
      if (predictRow(fit(data, type, data.all, remaining), row).predicted === row.class) correct++;
    });
    lines.push(fields(type, 'correct', correct, 'accuracy', ratio(correct, data.train.length)));
  }
  return lines;
}

function forwardSelectionReport(data, type) {
  const selected = [];
  const lines = [fields('forward_selection model', type)];
  let best = null;
  while (selected.length < data.features.length) {
    let candidate = null;
    for (const feature of data.all) {
      if (selected.includes(feature)) continue;
      const result = crossValidation(data, type, [...selected, feature]);
      if (candidate === null || result.correct > candidate.correct) candidate = { feature, correct: result.correct };
    }
    selected.push(candidate.feature);
    lines.push(fields('step', selected.length, 'add', data.features[candidate.feature],
      'correct', candidate.correct, 'accuracy', ratio(candidate.correct, data.train.length)));
    if (best === null || candidate.correct > best.correct) best = { correct: candidate.correct, features: selected.slice() };
  }
  lines.push(fields('best_step', best.features.length, 'features', ...best.features.map(feature => data.features[feature])));
  return lines;
}

function tuningReport(data, type, parameter, grid, heading) {
  const lines = [heading];
  let best = null;
  for (const value of grid) {
    const result = crossValidation(data, type, data.all, { [parameter]: value });
    lines.push(fields('value', real(value), 'correct', result.correct, 'accuracy', ratio(result.correct, data.train.length)));
    if (best === null || result.correct >= best.correct) best = { value, correct: result.correct };
  }
  const model = fit(data, type, data.all, data.train, { [parameter]: best.value });
  const count = correctCount(data.test, predictions(classifyRows(model, data.test)));
  lines.push(fields('best', real(best.value), 'test correct', count, 'accuracy', ratio(count, data.test.length)));
  return lines;
}

function evaluationReport(data, results) {
  const parts = [[fields('test rows', data.test.length)]];
  MODELS.forEach((type, index) => parts.push(evaluateModel(data, type, results[index])));
  const predicted = results.map(predictions);
  const ensemble = data.test.map((_, row) => {
    const probabilities = data.classes.map((name, group) => {
      let total = 0;
      for (let model = 0; model < MODELS.length; model++) total += results[model][row].posterior[group];
      return total / 3;
    });
    let best = 0;
    for (let group = 1; group < probabilities.length; group++) if (probabilities[group] > probabilities[best]) best = group;
    return best;
  });
  const ensembleMetrics = confusion(data.test, ensemble, data.classes.length);
  parts.push(['ensemble soft_vote', fields('accuracy', fractionText(ensembleMetrics.accuracy),
    'balanced_accuracy', fractionText(ensembleMetrics.balanced), 'kappa', fractionText(ensembleMetrics.kappa))]);
  parts.push(['mcnemar test', ...comparisonLines(data.test, [...MODELS, 'ENSEMBLE'], [...predicted, ensemble])]);
  const costs = ['costs'];
  results.forEach((model, index) => {
    let predictedCost = 0;
    let decidedCost = 0;
    let changed = 0;
    let correct = 0;
    data.test.forEach((row, position) => {
      const result = model[position];
      predictedCost += data.costs[row.class][result.predicted];
      decidedCost += data.costs[row.class][result.decision];
      if (result.predicted !== result.decision) changed++;
      if (result.decision === row.class) correct++;
    });
    costs.push(fields(MODELS[index], 'argmax_total', real(predictedCost), 'decision_total', real(decidedCost),
      'changed', changed, 'decision_accuracy', ratio(correct, data.test.length)));
  });
  parts.push(costs);
  const novel = [];
  results[2].forEach((result, index) => {
    let nearest = 0;
    for (let group = 1; group < data.classes.length; group++) if (result.distances[group] < result.distances[nearest]) nearest = group;
    if (result.distances[nearest] > data.settings.outlier) novel.push({ index, nearest, q: result.distances[nearest] });
  });
  novel.sort((a, b) => b.q - a.q || a.index - b.index);
  parts.push([fields('novelty threshold', real(data.settings.outlier)),
    ...novel.map(item => fields(data.test[item.index].id, 'nearest', data.classes[item.nearest], 'q', real(item.q))), fields('count', novel.length)]);
  parts.push(bootstrapReport(data, predicted));
  const prior = data.settings.prior === 'empirical' ? 'uniform' : 'empirical';
  const sensitivity = [fields('prior_sensitivity alternative', prior)];
  MODELS.forEach((type, index) => {
    const alternative = predictions(classifyRows(fit(data, type, data.all, data.train, { prior }), data.test));
    const metrics = confusion(data.test, alternative, data.classes.length);
    let changed = 0;
    for (let row = 0; row < alternative.length; row++) if (alternative[row] !== predicted[index][row]) changed++;
    sensitivity.push(fields(type, 'accuracy', fractionText(metrics.accuracy), 'balanced_accuracy', fractionText(metrics.balanced), 'changed', changed));
  });
  parts.push(sensitivity);
  const learning = ['learning_curve'];
  for (const size of data.settings.curve) {
    const taken = Array(data.classes.length).fill(0);
    const rows = data.train.filter(row => ++taken[row.class] <= size);
    const line = ['size', size, 'rows', rows.length];
    for (const type of MODELS) {
      const count = correctCount(data.test, predictions(classifyRows(fit(data, type, data.all, rows), data.test)));
      line.push(type, ratio(count, data.test.length));
    }
    learning.push(fields(...line));
  }
  parts.push(learning, subsetReport(data));
  const validation = MODELS.map(type => crossValidation(data, type));
  parts.push(['mcnemar cross_validation', ...comparisonLines(data.train, MODELS, validation.map(result => result.predicted))]);
  validation.forEach((result, index) => {
    const metrics = confusion(data.train, result.predicted, data.classes.length);
    parts.push([fields('cv_confusion model', MODELS[index]), ...confusionLines(data, metrics),
      fields('balanced_accuracy', fractionText(metrics.balanced), 'kappa', fractionText(metrics.kappa))]);
  });
  parts.push(leaveOneOutReport(data));
  for (const type of MODELS) parts.push(forwardSelectionReport(data, type));
  parts.push(tuningReport(data, 'NB', 'epsilon', data.settings.smoothingGrid, 'nb_smoothing_path'));
  parts.push(tuningReport(data, 'QDA', 'gamma', data.settings.gammaGrid, 'qda_gamma_path'));
  return sections(parts);
}

function emptyGrid(width, height) {
  return Array.from({ length: height }, () => Array(width).fill(' '));
}

function placePoint(grid, column, row, letter) {
  const previous = grid[row][column];
  grid[row][column] = previous === ' ' || previous === letter ? letter : '*';
}

function boundaryReport(data) {
  const parts = [];
  const { width, height } = data.settings;
  for (const features of data.settings.pairs) {
    const [fx, fy] = features;
    const xs = data.train.map(row => row.values[fx]);
    const ys = data.train.map(row => row.values[fy]);
    const xmin = Math.min(...xs);
    const xmax = Math.max(...xs);
    const ymin = Math.min(...ys);
    const ymax = Math.max(...ys);
    const dx = (xmax - xmin) / (width - 1);
    const dy = (ymax - ymin) / (height - 1);
    const lines = [fields('pair', data.features[fx], data.features[fy]),
      fields('x', data.features[fx], real(xmin), real(xmax), 'y', data.features[fy], real(ymin), real(ymax), 'grid', width + 'x' + height)];
    const maps = [];
    const uncertainty = emptyGrid(width, height);
    for (const type of MODELS) {
      const model = fit(data, type, features);
      const correct = correctCount(data.train, predictions(classifyRows(model, data.train)));
      lines.push(fields('model', type, 'train_accuracy', ratio(correct, data.train.length),
        'cv_accuracy', ratio(crossValidation(data, type, features).correct, data.train.length)));
      const region = emptyGrid(width, height);
      const counts = Array(data.classes.length).fill(0);
      const choices = [];
      for (let row = 0; row < height; row++) {
        const chosen = [];
        for (let column = 0; column < width; column++) {
          const result = predict(model, [xmin + column * dx, ymax - row * dy]);
          region[row][column] = data.classes[result.predicted][0].toUpperCase();
          counts[result.predicted]++;
          chosen.push(result.predicted);
          if (type === 'QDA') {
            const u = (1 - result.confidence) / (1 - 1 / data.classes.length);
            const level = Math.min(9, Math.floor(10 * u));
            uncertainty[row][column] = ' .:-=+*#%@'[level];
          }
        }
        choices.push(chosen);
      }
      maps.push(choices);
      lines.push(...frame(region));
      const cells = ['cells'];
      data.classes.forEach((name, index) => cells.push(name[0].toUpperCase(), counts[index]));
      lines.push(fields(...cells));
    }
    const agreement = emptyGrid(width, height);
    let disagreements = 0;
    for (let row = 0; row < height; row++) {
      for (let column = 0; column < width; column++) {
        const distinct = new Set(maps.map(map => map[row][column])).size;
        agreement[row][column] = distinct === 1 ? '.' : String(distinct);
        if (distinct !== 1) disagreements++;
      }
    }
    const points = emptyGrid(width, height);
    for (const row of data.train) {
      const column = cell(row.values[fx], xmin, xmax, width);
      const line = height - 1 - cell(row.values[fy], ymin, ymax, height);
      placePoint(points, column, line, data.classes[row.class][0]);
    }
    lines.push('agreement', ...frame(agreement), fields('disagreement_cells', disagreements),
      'uncertainty QDA', ...frame(uncertainty), 'points', ...frame(points));
    parts.push(lines);
  }
  return sections(parts);
}

function fisherDirections(within, between) {
  const dimension = within.length;
  const lower = algebra.cholesky(within);
  const first = algebra.matrix(dimension);
  for (let column = 0; column < dimension; column++) {
    const result = algebra.forward(lower, between.map(row => row[column]));
    for (let row = 0; row < dimension; row++) first[row][column] = result[row];
  }
  const second = algebra.matrix(dimension);
  for (let column = 0; column < dimension; column++) {
    const result = algebra.forward(lower, first[column]);
    for (let row = 0; row < dimension; row++) second[row][column] = result[row];
  }
  const symmetric = second.map((row, a) => row.map((value, b) => (value + second[b][a]) / 2));
  const eigen = algebra.jacobi(symmetric);
  const order = Array.from({ length: dimension }, (_, index) => index)
    .sort((a, b) => eigen.values[b] - eigen.values[a] || a - b);
  let total = 0;
  for (const value of eigen.values) total += value;
  const directions = order.slice(0, 2).map(index => {
    const vector = algebra.backward(lower, eigen.vectors.map(row => row[index]));
    let norm = 0;
    for (const value of vector) norm += value * value;
    norm = Math.sqrt(norm);
    const direction = vector.map(value => value / norm);
    let largest = 0;
    for (let feature = 1; feature < dimension; feature++) if (Math.abs(direction[feature]) > Math.abs(direction[largest])) largest = feature;
    return direction[largest] < 0 ? direction.map(value => -value) : direction;
  });
  return { directions, sweeps: eigen.sweeps, eigenvalues: order.map(index => eigen.values[index]),
    ratios: order.map(index => eigen.values[index] / total) };
}

function project(vector, directions, center) {
  return directions.map(direction => {
    let value = 0;
    for (let feature = 0; feature < vector.length; feature++) value += direction[feature] * (vector[feature] - center[feature]);
    return value;
  });
}

function nearestCount(rows, projections, centroids, dimensions) {
  let correct = 0;
  rows.forEach((row, index) => {
    let nearest = 0;
    let minimum = Infinity;
    centroids.forEach((centroid, group) => {
      const first = projections[index][0] - centroid[0];
      let distance = first * first;
      if (dimensions === 2) {
        const second = projections[index][1] - centroid[1];
        distance += second * second;
      }
      if (distance < minimum) {
        minimum = distance;
        nearest = group;
      }
    });
    if (nearest === row.class) correct++;
  });
  return correct;
}

function projectionReport(data, lda) {
  const dimension = data.features.length;
  const count = data.classes.length;
  const { center, classes } = lda.data;
  const within = algebra.matrix(dimension);
  const between = algebra.matrix(dimension);
  for (let first = 0; first < dimension; first++) {
    for (let second = 0; second < dimension; second++) {
      for (const group of classes) {
        within[first][second] += group.scatter[first][second];
        between[first][second] += group.count * (group.mean[first] - center[first]) * (group.mean[second] - center[second]);
      }
    }
  }
  const fvalues = data.all.map(feature => (between[feature][feature] / (count - 1)) / (within[feature][feature] / (data.train.length - count)));
  const order = data.all.slice().sort((a, b) => fvalues[b] - fvalues[a] || a - b);
  const univariate = ['univariate', ...order.map((feature, rank) => fields('rank', rank + 1, data.features[feature],
    'f', real(fvalues[feature]), 'between', real(between[feature][feature]), 'within', real(within[feature][feature])))];
  const fisher = fisherDirections(within, between);
  const lines = [fields('fisher features', ...data.features), fields('center', reals(center)), fields('sweeps', fisher.sweeps),
    fields('eigenvalues', reals(fisher.eigenvalues)), fields('ratios', reals(fisher.ratios))];
  fisher.directions.forEach((direction, index) => {
    const standardized = direction.map((value, feature) => value * Math.sqrt(lda.classes[0].covariance[feature][feature]));
    lines.push(fields('direction', index + 1, reals(direction)), fields('standardized', index + 1, reals(standardized)));
  });
  const centroids = classes.map(group => project(group.mean, fisher.directions, center));
  const training = data.train.map(row => project(row.values, fisher.directions, center));
  const testing = data.test.map(row => project(row.values, fisher.directions, center));
  classes.forEach((group, index) => {
    const spread = [0, 1].map(direction => {
      let total = 0;
      data.train.forEach((row, position) => {
        if (row.class !== index) return;
        const difference = training[position][direction] - centroids[index][direction];
        total += difference * difference;
      });
      return Math.sqrt(total / group.count);
    });
    lines.push(fields('centroid', data.classes[index], reals(centroids[index]), 'spread', reals(spread)));
  });
  for (const dimensions of [1, 2]) {
    lines.push(fields('nearest_centroid dims', dimensions,
      'train', ratio(nearestCount(data.train, training, centroids, dimensions), data.train.length),
      'test', ratio(nearestCount(data.test, testing, centroids, dimensions), data.test.length)));
  }
  const low1 = Math.min(...training.map(point => point[0]));
  const high1 = Math.max(...training.map(point => point[0]));
  const low2 = Math.min(...training.map(point => point[1]));
  const high2 = Math.max(...training.map(point => point[1]));
  const width = data.settings.plotWidth;
  const height = data.settings.plotHeight;
  const grid = emptyGrid(width, height);
  training.forEach((point, index) => {
    const column = cell(point[0], low1, high1, width);
    const row = height - 1 - cell(point[1], low2, high2, height);
    placePoint(grid, column, row, data.classes[data.train[index].class][0]);
  });
  centroids.forEach((point, index) => {
    const column = cell(point[0], low1, high1, width);
    const row = height - 1 - cell(point[1], low2, high2, height);
    grid[row][column] = data.classes[index][0].toUpperCase();
  });
  const plot = [fields('plot x', real(low1), real(high1), 'y', real(low2), real(high2), 'size', width + 'x' + height), ...frame(grid)];
  return sections([univariate, lines, plot]);
}

function main() {
  const data = readDataset();
  data.all = data.features.map((name, index) => index);
  data.cv = new Map();
  const models = MODELS.map(type => fit(data, type));
  const results = models.map(model => classifyRows(model, data.test, data.costs));
  const modelLines = modelReport(data, models);
  const predictionLines = predictionReport(data, results);
  const evaluationLines = evaluationReport(data, results);
  const boundaryLines = boundaryReport(data);
  const projectionLines = projectionReport(data, models[1]);
  fs.mkdirSync('output', { recursive: true });
  writeLines('models.txt', modelLines);
  writeLines('predictions.csv', predictionLines);
  writeLines('evaluation.txt', evaluationLines);
  writeLines('boundaries.txt', boundaryLines);
  writeLines('projection.txt', projectionLines);
}

if (require.main === module) main();
