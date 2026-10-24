'use strict';

const { readDataset } = require('./dataset');
const { fitScaling } = require('./scaling');
const { compareText, vote } = require('./neighbors');
const { stratifiedSplit, Predictor, regression } = require('./validation');
const { real, rounded, ratio, fractionMetric, writeReport } = require('./report');

const modelText = model => `k=${model.k} metric=${model.metric} weighting=${model.weighting} scaling=${model.scaling}`;
const orderedRows = rows => [...rows].sort((left, right) => compareText(left.id, right.id));
const correctCount = (rows, predictions) => rows.filter(row => predictions.get(row.id).label === row.label).length;
const regressionFor = (rows, predictions) => regression(rows.map(row => ({ target: row.target, estimate: predictions.get(row.id).estimate })));
const flattenParts = parts => parts.flatMap((part, index) => index === 0 ? part : ['', ...part]);

function buildGrid(settings) {
  const models = [];
  for (const k of settings.ks) for (const metric of settings.metrics) {
    for (const weighting of settings.weightings) for (const scaling of settings.scalings) {
      models.push({ k, metric, weighting, scaling, order: models.length });
    }
  }
  return models;
}

function summarize(result, rows) {
  result.correct = correctCount(rows, result.predictions);
  result.statistics = regressionFor(rows, result.predictions);
  result.rmse = result.statistics.rmse;
  result.roundedRmse = rounded(result.rmse);
  return result;
}

function crossValidate(rows, models, count, features) {
  const folds = stratifiedSplit(rows, count);
  const results = models.map(model => ({ model, predictions: new Map() }));
  for (const fold of folds) {
    const excluded = new Set(fold.map(row => row.id));
    const predictor = new Predictor(rows.filter(row => !excluded.has(row.id)), features);
    for (const row of fold) {
      for (const result of results) result.predictions.set(row.id, predictor.predict(row, result.model));
    }
  }
  for (const result of results) summarize(result, rows);
  return { folds, results };
}

function selectModels(results) {
  const accuracy = [...results].sort((left, right) => right.correct - left.correct || left.model.order - right.model.order);
  const rmse = [...results].sort((left, right) => left.roundedRmse - right.roundedRmse || left.model.order - right.model.order);
  return { classifier: accuracy[0], regressor: rmse[0], accuracy, rmse };
}

function labelCounts(rows, labels) {
  const counts = new Map(labels.map(label => [label, 0]));
  for (const row of rows) counts.set(row.label, counts.get(row.label) + 1);
  return labels.map(label => `${label} ${counts.get(label)}`).join(' ');
}

function evaluationLines(rows, predictions, labels) {
  const positions = new Map(labels.map((label, index) => [label, index]));
  const matrix = labels.map(() => labels.map(() => 0));
  for (const row of rows) matrix[positions.get(row.label)][positions.get(predictions.get(row.id).label)]++;
  const lines = [`true\\predicted ${labels.join(' ')}`];
  for (let index = 0; index < labels.length; index++) lines.push(`${labels[index]} ${matrix[index].join(' ')}`);
  const totals = [0, 0, 0], counts = [0, 0, 0];
  for (let index = 0; index < labels.length; index++) {
    let predicted = 0, actual = 0;
    for (let other = 0; other < labels.length; other++) {
      predicted += matrix[other][index];
      actual += matrix[index][other];
    }
    const truePositive = matrix[index][index];
    const metrics = [[truePositive, predicted], [truePositive, actual], [2 * truePositive, predicted + actual]];
    for (let metric = 0; metric < metrics.length; metric++) {
      const [numerator, denominator] = metrics[metric];
      if (denominator !== 0) {
        totals[metric] += numerator / denominator;
        counts[metric]++;
      }
    }
    lines.push(`class ${labels[index]} precision ${fractionMetric(...metrics[0])} recall ${fractionMetric(...metrics[1])}`
      + ` f1 ${fractionMetric(...metrics[2])} support ${actual}`);
  }
  const macro = totals.map((total, index) => real(counts[index] === 0 ? null : total / counts[index]));
  lines.push(`macro precision ${macro[0]} recall ${macro[1]} f1 ${macro[2]}`);
  return lines;
}

function reliabilityLines(rows, predictions, boundaries) {
  const bins = [0, ...boundaries].map(lower => ({ lower, count: 0, correct: 0, total: 0 }));
  for (const row of rows) {
    const prediction = predictions.get(row.id);
    let index = 0;
    while (index < boundaries.length && prediction.share >= boundaries[index]) index++;
    const bin = bins[index];
    bin.count++;
    if (prediction.label === row.label) bin.correct++;
    bin.total += prediction.share;
  }
  return bins.map(bin => `bin ${real(bin.lower, 2)} rows ${bin.count}`
    + (bin.count === 0 ? '' : ` correct ${ratio(bin.correct, bin.count)} share ${real(bin.total / bin.count)}`));
}

function bestPerItem(results, settings) {
  const items = [['k', settings.ks], ['metric', settings.metrics], ['weighting', settings.weightings], ['scaling', settings.scalings]];
  return new Map(items.map(([item, values]) => [item, values.map(value => ({ value,
    ...selectModels(results.filter(result => result.model[item] === value)) }))]));
}

function mcnemarLines(rows, classifier, comparisons) {
  const lines = ['mcnemar'];
  for (const comparison of comparisons) {
    let firstOnly = 0, secondOnly = 0;
    for (const row of rows) {
      const first = classifier.predictions.get(row.id).label === row.label;
      const second = comparison.classifier.predictions.get(row.id).label === row.label;
      if (first && !second) firstOnly++;
      if (second && !first) secondOnly++;
    }
    const difference = Math.max(0, Math.abs(firstOnly - secondOnly) - 1);
    const numerator = difference * difference, denominator = firstOnly + secondOnly;
    const statistic = denominator === 0 ? '0/1 0.0000' : fractionMetric(numerator, denominator);
    const significant = 1000 * numerator > 3841 * denominator ? 'yes' : 'no';
    lines.push(`${modelText(comparison.classifier.model)} b ${firstOnly} c ${secondOnly} statistic ${statistic} significant ${significant}`);
  }
  return lines;
}

function leaveOneOut(rows, classifier, regressor, ks) {
  const byK = ks.map(k => ({ model: { ...classifier.model, k }, predictions: new Map() }));
  const regressionResult = { model: regressor.model, predictions: new Map() };
  const results = [...byK, regressionResult];
  for (const row of rows) {
    const predictor = new Predictor(rows.filter(other => other.id !== row.id));
    for (const result of results) result.predictions.set(row.id, predictor.predict(row, result.model));
  }
  for (const result of results) summarize(result, rows);
  return { byK, classifier: byK.find(result => result.model.k === classifier.model.k), regressor: regressionResult };
}

function leaveOneOutParts(rows, labels, results, top) {
  const { classifier, regressor, byK } = results;
  const errors = orderedRows(rows.filter(row => classifier.predictions.get(row.id).label !== row.label));
  const first = [`leave_one_out classifier ${modelText(classifier.model)}`, `errors ${ratio(errors.length, rows.length)}`,
    `class_errors ${labelCounts(errors, labels)}`];
  for (const row of errors) {
    const prediction = classifier.predictions.get(row.id);
    first.push(`${row.id} true ${row.label} predicted ${prediction.label} share ${real(prediction.share)}`);
  }
  const residuals = rows.map(row => {
    const estimate = regressor.predictions.get(row.id).estimate;
    return { row, estimate, residual: estimate - row.target };
  }).sort((left, right) => rounded(Math.abs(right.residual)) - rounded(Math.abs(left.residual)) || compareText(left.row.id, right.row.id));
  const second = [`leave_one_out regressor ${modelText(regressor.model)}`,
    `rmse ${real(regressor.rmse)} mae ${real(regressor.statistics.mae)}`, `largest ${top} residuals`];
  for (const item of residuals.slice(0, top)) second.push(`${item.row.id} target ${real(item.row.target)}`
    + ` estimate ${real(item.estimate)} residual ${real(item.residual)}`);
  const third = [`leave_one_out by k metric=${classifier.model.metric} weighting=${classifier.model.weighting} scaling=${classifier.model.scaling}`];
  for (const result of byK) third.push(`k=${result.model.k} correct ${ratio(result.correct, rows.length)} rmse ${real(result.rmse)}`);
  return [first, second, third];
}

function nestedValidation(rows, folds, models, count) {
  const lines = [`nested_cross_validation folds ${count}`], predictions = new Map();
  let totalCorrect = 0;
  for (let index = 0; index < folds.length; index++) {
    const fold = folds[index], excluded = new Set(fold.map(row => row.id));
    const training = rows.filter(row => !excluded.has(row.id));
    const inner = selectModels(crossValidate(training, models, count).results), predictor = new Predictor(training);
    let correct = 0;
    for (const row of fold) {
      if (predictor.predict(row, inner.classifier.model).label === row.label) correct++;
      predictions.set(row.id, predictor.predict(row, inner.regressor.model));
    }
    totalCorrect += correct;
    lines.push(`fold ${index + 1} classifier ${modelText(inner.classifier.model)} inner ${real(inner.classifier.correct / training.length)}`
      + ` outer ${ratio(correct, fold.length)}`);
    lines.push(`fold ${index + 1} regressor ${modelText(inner.regressor.model)} inner ${real(inner.regressor.rmse)}`
      + ` outer ${real(regressionFor(fold, predictions).rmse)}`);
  }
  lines.push(`nested accuracy ${ratio(totalCorrect, rows.length)} rmse ${real(regressionFor(rows, predictions).rmse)}`);
  return lines;
}

function selectFeatures(data, classifier) {
  const { train, features, settings, test } = data, n = train.length;
  let current = features.map((_, index) => index), selected = current, best = classifier.correct;
  const names = indices => indices.map(index => features[index]).join(' ');
  const lines = [`feature_selection ${modelText(classifier.model)}`, `start features ${names(current)} correct ${ratio(best, n)}`];
  let step = 0;
  while (current.length >= 3) {
    const candidates = current.map(feature => {
      const used = current.filter(index => index !== feature);
      const result = crossValidate(train, [classifier.model], settings.folds, used).results[0];
      return { feature, used, correct: result.correct };
    });
    let chosen = candidates[0];
    for (const candidate of candidates) if (candidate.correct > chosen.correct) chosen = candidate;
    current = chosen.used;
    if (chosen.correct >= best) {
      selected = current;
      best = chosen.correct;
    }
    step++;
    lines.push(`step ${step} remove ${features[chosen.feature]} correct ${ratio(chosen.correct, n)} candidates `
      + candidates.map(candidate => `${features[candidate.feature]} ${candidate.correct}`).join(' '));
  }
  const labelled = test.filter(row => row.label !== null), predictor = new Predictor(train, selected);
  let correct = 0;
  for (const row of labelled) if (predictor.predict(row, classifier.model).label === row.label) correct++;
  lines.push(`selected features ${names(selected)} correct ${ratio(best, n)}`, `selected test ${ratio(correct, labelled.length)}`);
  return lines;
}

function predictTest(data, classifier, regressor) {
  const predictor = new Predictor(data.train), classification = new Map(), estimates = new Map();
  for (const row of data.test) {
    classification.set(row.id, predictor.predict(row, classifier.model));
    estimates.set(row.id, predictor.predict(row, regressor.model));
  }
  return { predictor, classification, estimates };
}

function learningLines(data, classifier, regressor) {
  const lines = ['n,train_size,correct,accuracy,rmse'];
  const labelled = data.test.filter(row => row.label !== null), targets = data.test.filter(row => row.target !== null);
  for (const count of data.settings.curve) {
    const counts = new Map();
    const training = data.train.filter(row => {
      const previous = counts.get(row.label) || 0;
      if (previous >= count) return false;
      counts.set(row.label, previous + 1);
      return true;
    });
    const predictor = new Predictor(training), estimates = new Map();
    let correct = 0;
    for (const row of labelled) if (predictor.predict(row, classifier.model).label === row.label) correct++;
    for (const row of targets) estimates.set(row.id, predictor.predict(row, regressor.model));
    lines.push([count, training.length, correct, real(correct / labelled.length), real(regressionFor(targets, estimates).rmse)].join(','));
  }
  return lines;
}

function prototypeParts(data, labels, classifier, predictions) {
  const { train, test, settings } = data, model = classifier.model, original = orderedRows(train);
  const labelled = test.filter(row => row.label !== null), space = predictions.predictor;
  const order = (row, allowed, exclude = null) => space.order(row, model)
    .filter(item => allowed.has(item.row.id) && item.row.id !== exclude);
  const parts = [[`space ${modelText(model)}`]], editing = [`editing k=${settings.editK}`];
  let edited = original, pass = 0;
  while (true) {
    const allowed = new Set(edited.map(row => row.id)), removed = [];
    for (const row of edited) {
      const prediction = vote(order(row, allowed, row.id), settings.editK, model.weighting);
      if (prediction.label !== row.label) removed.push({ row, prediction });
    }
    editing.push(`pass ${++pass} removed ${removed.length}`);
    for (const item of removed) editing.push(`  ${item.row.id} true ${item.row.label}`
      + ` predicted ${item.prediction.label} share ${real(item.prediction.share)}`);
    if (removed.length === 0) break;
    const excluded = new Set(removed.map(item => item.row.id));
    edited = edited.filter(row => !excluded.has(row.id));
  }
  editing.push(`edited size ${edited.length} removed ${train.length - edited.length}`);
  parts.push(editing);
  function condense(rows) {
    const stored = new Set([rows[0].id]);
    let scans = 0;
    while (true) {
      let added = 0;
      for (const row of rows) {
        if (stored.has(row.id)) continue;
        if (order(row, stored)[0].row.label !== row.label) {
          stored.add(row.id);
          added++;
        }
      }
      scans++;
      if (added === 0) return { rows: rows.filter(row => stored.has(row.id)), scans };
    }
  }
  const condensed = condense(original), editedCondensed = condense(edited);
  parts.push([`condensing original scans ${condensed.scans} size ${condensed.rows.length}`,
    `condensing edited scans ${editedCondensed.scans} size ${editedCondensed.rows.length}`]);
  const sets = [['original', original], ['edited', edited], ['condensed', condensed.rows], ['edited_condensed', editedCondensed.rows]];
  const summaries = [];
  for (const [name, rows] of sets) {
    const allowed = new Set(rows.map(row => row.id));
    let knn = 0, nearest = 0;
    for (const row of labelled) {
      const neighbors = order(row, allowed);
      if (vote(neighbors, model.k, model.weighting).label === row.label) knn++;
      if (neighbors[0].row.label === row.label) nearest++;
    }
    summaries.push(`set ${name} size ${rows.length} ${labelCounts(rows, labels)}`
      + ` knn ${ratio(knn, labelled.length)} 1nn ${ratio(nearest, labelled.length)}`);
  }
  parts.push(summaries);
  for (const [name, rows] of sets.slice(2)) {
    const lines = [`prototypes ${name}`];
    for (let index = 0; index < rows.length; index += 10) lines.push(rows.slice(index, index + 10).map(row => row.id).join(' '));
    parts.push(lines);
  }
  const borders = ['borders'];
  let borderTotal = 0;
  for (const label of labels) {
    const rows = original.filter(row => row.label === label);
    let border = 0, same = 0, other = 0;
    for (const row of rows) {
      const neighbors = space.order(row, model).filter(item => item.row.id !== row.id);
      if (neighbors[0].row.label !== label) border++;
      same += neighbors.find(item => item.row.label === label).distance;
      other += neighbors.find(item => item.row.label !== label).distance;
    }
    borderTotal += border;
    borders.push(`class ${label} size ${rows.length} border ${border} same ${real(same / rows.length)} other ${real(other / rows.length)}`);
  }
  borders.push(`border total ${ratio(borderTotal, train.length)}`);
  parts.push(borders);
  const counts = new Map(train.map(row => [row.id, 0]));
  for (const row of test) {
    for (const neighbor of predictions.classification.get(row.id).neighbors) counts.set(neighbor.row.id, counts.get(neighbor.row.id) + 1);
  }
  const ranked = [...train].sort((left, right) => counts.get(right.id) - counts.get(left.id) || compareText(left.id, right.id));
  const hubs = [`hubs k=${model.k} queries ${test.length}`];
  for (const row of ranked.slice(0, settings.top)) hubs.push(`${row.id} ${row.label} ${counts.get(row.id)}`);
  hubs.push(`anti_hubs ${train.filter(row => counts.get(row.id) === 0).length}`);
  parts.push(hubs);
  return parts;
}

function selectionParts(data, labels, cross, selected, perItem) {
  const { train, test, features, settings } = data, n = train.length;
  const labelled = test.filter(row => row.label !== null), targets = test.filter(row => row.target !== null);
  const parts = [[`data train ${n} test ${test.length} labelled ${labelled.length} targets ${targets.length} features ${features.length} classes ${labels.length}`,
    `classes ${labelCounts(train, labels)}`]];
  for (const method of settings.scalings) {
    const scaling = fitScaling(train, method);
    parts.push([`scaling ${method}`, ...features.map((name, index) =>
      `${name} center ${real(scaling.centers[index], 6)} scale ${real(scaling.scales[index], 6)}`)]);
  }
  parts.push([`folds ${settings.folds}`, ...cross.folds.map((fold, index) =>
    `fold ${index + 1} size ${fold.length} ${labelCounts(fold, labels)}`)]);
  const { classifier, regressor } = selected;
  parts.push([`grid ${cross.results.length}`,
    `best_classifier ${modelText(classifier.model)} correct ${ratio(classifier.correct, n)} rmse ${real(classifier.rmse)}`,
    `best_regressor ${modelText(regressor.model)} rmse ${real(regressor.rmse)} correct ${ratio(regressor.correct, n)}`]);
  parts.push([`top ${settings.top} by accuracy`, ...selected.accuracy.slice(0, settings.top).map((result, index) =>
    `${index + 1} ${modelText(result.model)} correct ${ratio(result.correct, n)} rmse ${real(result.rmse)}`)]);
  parts.push([`top ${settings.top} by rmse`, ...selected.rmse.slice(0, settings.top).map((result, index) =>
    `${index + 1} ${modelText(result.model)} rmse ${real(result.rmse)} correct ${ratio(result.correct, n)}`)]);
  for (const [item, records] of perItem) {
    parts.push([`best per ${item}`, ...records.map(record => `${item}=${record.value}`
      + ` classifier ${modelText(record.classifier.model)} accuracy ${real(record.classifier.correct / n)}`
      + ` regressor ${modelText(record.regressor.model)} rmse ${real(record.regressor.rmse)}`)]);
  }
  parts.push(['classifier folds', ...cross.folds.map((fold, index) =>
    `fold ${index + 1} correct ${ratio(correctCount(fold, classifier.predictions), fold.length)}`)]);
  parts.push(['regressor folds', ...cross.folds.map((fold, index) =>
    `fold ${index + 1} size ${fold.length} rmse ${real(regressionFor(fold, regressor.predictions).rmse)}`)]);
  parts.push(['cross_validation classes', ...evaluationLines(train, classifier.predictions, labels)]);
  parts.push(['cross_validation reliability', ...reliabilityLines(train, classifier.predictions, settings.bins)]);
  parts.push(mcnemarLines(train, classifier, perItem.get('metric')));
  return parts;
}

function testParts(data, labels, classifier, regressor, predictions) {
  const { test, settings } = data, { classification, estimates } = predictions;
  const labelled = test.filter(row => row.label !== null), targets = test.filter(row => row.target !== null);
  const parts = [[`test classification ${modelText(classifier.model)}`,
    `labelled ${labelled.length} correct ${ratio(correctCount(labelled, classification), labelled.length)}`,
    ...evaluationLines(labelled, classification, labels)],
  ['test reliability', ...reliabilityLines(labelled, classification, settings.bins)]];
  const uncertain = test.map(row => {
    const prediction = classification.get(row.id);
    return { row, prediction, margin: prediction.share - prediction.runnerShare };
  }).sort((left, right) => rounded(left.margin) - rounded(right.margin) || left.row.index - right.row.index);
  const uncertainty = [`uncertain ${settings.top} test rows`];
  for (const item of uncertain.slice(0, settings.top)) {
    const { row, prediction, margin } = item;
    uncertainty.push(`${row.id} predicted ${prediction.label} share ${real(prediction.share)} runner_up ${prediction.runnerUp ?? '-'}`
      + ` share ${real(prediction.runnerShare)} margin ${real(margin)} true ${row.label ?? '-'}`);
  }
  parts.push(uncertainty);
  const statistics = regressionFor(targets, estimates);
  const regressionLines = [`test regression ${modelText(regressor.model)}`,
    `targets ${targets.length} rmse ${real(statistics.rmse)} mae ${real(statistics.mae)} r2 ${real(statistics.r2)}`];
  for (const label of labels) {
    const rows = targets.filter(row => row.label === label);
    regressionLines.push(`class ${label} targets ${rows.length} rmse ${real(regressionFor(rows, estimates).rmse)}`);
  }
  parts.push(regressionLines);
  const errors = labelled.filter(row => classification.get(row.id).label !== row.label), misclassified = ['misclassified test rows'];
  for (const row of errors) {
    const prediction = classification.get(row.id);
    misclassified.push(`${row.id} true ${row.label} predicted ${prediction.label} share ${real(prediction.share)}`);
    for (const neighbor of prediction.neighbors) misclassified.push(`  ${neighbor.row.id} ${neighbor.row.label} ${real(neighbor.distance)}`);
  }
  misclassified.push(`count ${errors.length}`);
  parts.push(misclassified);
  return parts;
}

function main() {
  const data = readDataset(), labels = [...new Set(data.train.map(row => row.label))].sort(compareText);
  const grid = buildGrid(data.settings), cross = crossValidate(data.train, grid, data.settings.folds);
  const selected = selectModels(cross.results), { classifier, regressor } = selected;
  const perItem = bestPerItem(cross.results, data.settings);
  const parts = selectionParts(data, labels, cross, selected, perItem);
  const loo = leaveOneOut(data.train, classifier, regressor, data.settings.ks);
  parts.push(...leaveOneOutParts(data.train, labels, loo, data.settings.top));
  parts.push(nestedValidation(data.train, cross.folds, grid, data.settings.folds));
  parts.push(selectFeatures(data, classifier));
  const predictions = predictTest(data, classifier, regressor);
  parts.push(...testParts(data, labels, classifier, regressor, predictions));
  const gridLines = ['k,metric,weighting,scaling,correct,accuracy,rmse'];
  for (const result of cross.results) gridLines.push([result.model.k, result.model.metric, result.model.weighting,
    result.model.scaling, result.correct, real(result.correct / data.train.length), real(result.rmse)].join(','));
  const predictionLines = ['id,label,vote_share,estimate'];
  for (const row of data.test) {
    const prediction = predictions.classification.get(row.id);
    predictionLines.push([row.id, prediction.label, real(prediction.share), real(predictions.estimates.get(row.id).estimate)].join(','));
  }
  writeReport('cv_grid.csv', gridLines);
  writeReport('predictions.csv', predictionLines);
  writeReport('metrics.txt', flattenParts(parts));
  writeReport('learning_curve.csv', learningLines(data, classifier, regressor));
  writeReport('prototypes.txt', flattenParts(prototypeParts(data, labels, classifier, predictions)));
}

main();
