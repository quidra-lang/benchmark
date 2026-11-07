'use strict';

const { readDataset } = require('./dataset');
const { discrete, samme } = require('./adaboost');
const { real, gentle, logit } = require('./variants');
const { fixed, ratio, prediction, auc, confusion, countAtMost, writeLines } = require('./evaluation');

class Minstd {
  constructor(seed) { this.state = seed; }
  next() {
    this.state = (48271 * this.state) % 2147483647;
    return this.state;
  }
}

function sum(values) {
  let total = 0;
  for (const value of values) total += value;
  return total;
}

function trainVariant(name, rows, params) {
  if (name === 'discrete') return discrete(rows, params.rounds);
  if (name === 'real') return real(rows, params);
  if (name === 'gentle') return gentle(rows, params);
  return logit(rows, params);
}

function score(rounds, values) {
  let result = 0;
  for (const round of rounds) result += round.stump.output(values);
  return result;
}

const scoreRows = (rounds, rows) => rows.map(row => score(rounds, row.values));
const magnitude = round => Math.max(...round.stump.values.map(value => Math.abs(value)));

function errorCount(rows, scores) {
  let errors = 0;
  for (let i = 0; i < rows.length; i++) if (prediction(scores[i]) !== rows[i].label) errors++;
  return errors;
}

function loss(rows, scores, variant) {
  let total = 0;
  for (let i = 0; i < rows.length; i++) {
    total += variant === 'logit' ? Math.log(1 + Math.exp(-2 * rows[i].label * scores[i])) :
      Math.exp(-rows[i].label * scores[i]);
  }
  return total / rows.length;
}

function minimumPosition(values) {
  let best = 0;
  for (let i = 1; i < values.length; i++) if (values[i] < values[best]) best = i;
  return best;
}

function curve(rounds, train, test, variant) {
  const trainScores = Array(train.length).fill(0);
  const testScores = Array(test.length).fill(0);
  let scale = 0;
  const result = [];
  for (const round of rounds) {
    for (let i = 0; i < train.length; i++) trainScores[i] += round.stump.output(train[i].values);
    for (let i = 0; i < test.length; i++) testScores[i] += round.stump.output(test[i].values);
    scale += magnitude(round);
    const minimum = Math.min(...train.map((row, i) => row.label * trainScores[i]));
    result.push({ trainErrors: errorCount(train, trainScores), testErrors: errorCount(test, testScores),
      trainLoss: loss(train, trainScores, variant), testLoss: loss(test, testScores, variant), minimum: minimum / scale });
  }
  return result;
}

function crossValidation(rows, params) {
  const folds = [];
  for (let fold = 0; fold < params.folds; fold++) {
    const validation = rows.map((row, index) => index).filter(index => index % params.folds === fold);
    const count = rows.length - validation.length;
    const weights = rows.map((row, index) => index % params.folds === fold ? 0 : 1 / count);
    const model = discrete(rows, params.rounds, 1, weights);
    const scores = Array(validation.length).fill(0);
    const errors = [];
    for (let t = 0; t < params.rounds; t++) {
      if (t < model.rounds.length) {
        for (let i = 0; i < validation.length; i++) scores[i] += model.rounds[t].stump.output(rows[validation[i]].values);
      }
      let countErrors = 0;
      for (let i = 0; i < validation.length; i++) if (prediction(scores[i]) !== rows[validation[i]].label) countErrors++;
      errors.push(countErrors);
    }
    folds.push({ model, validation, count, errors });
  }
  const errors = Array(params.rounds).fill(0);
  for (const fold of folds) {
    for (let t = 0; t < params.rounds; t++) errors[t] += fold.errors[t];
  }
  const selected = minimumPosition(errors) + 1;
  const scores = Array(rows.length).fill(0);
  for (const fold of folds) {
    const rounds = fold.model.rounds.slice(0, selected);
    for (const i of fold.validation) scores[i] = score(rounds, rows[i].values);
  }
  return { folds, errors, selected, scores };
}

function importance(rounds, featureCount, multiclass = false) {
  const features = Array.from({ length: featureCount }, (_, feature) => ({ feature, score: 0, count: 0 }));
  for (const round of rounds) {
    const item = features[round.stump.feature];
    item.score += multiclass ? round.alpha : magnitude(round);
    item.count++;
  }
  let total = 0;
  for (const item of features) total += item.score;
  for (const item of features) item.share = item.score / total;
  return features.sort((a, b) => b.score - a.score || a.feature - b.feature);
}

function analyzeModels(data, cv) {
  const models = [];
  for (const name of data.params.variants) {
    const full = trainVariant(name, data.train, data.params);
    const rounds = name === 'discrete' ? full.rounds.slice(0, cv.selected) : full.rounds.slice();
    const scale = sum(rounds.map(magnitude));
    const trainScores = scoreRows(rounds, data.train);
    const testScores = scoreRows(rounds, data.test);
    models.push({ name, full, rounds, scale, trainScores, testScores,
      trainMargins: data.train.map((row, i) => row.label * trainScores[i] / scale),
      testMargins: data.test.map((row, i) => row.label * testScores[i] / scale),
      trainPredictions: trainScores.map(prediction), testPredictions: testScores.map(prediction),
      curve: curve(full.rounds, data.train, data.test, name), importance: importance(rounds, data.features.length) });
  }
  return models;
}

function ensembleLines(data, models, cv) {
  const lines = [];
  for (const model of models) {
    if (lines.length > 0) lines.push('');
    const { name, full } = model;
    let heading = `variant ${name} rounds ${full.rounds.length} stop ${full.stop}`;
    if (name === 'real') heading += ` bins ${data.params.bins} smoothing ${fixed(data.params.smoothing)} convergence ${fixed(data.params.convergence, 6)}`;
    if (name === 'logit') heading += ` clip ${fixed(data.params.clip)}`;
    lines.push(heading);
    if (name === 'real') {
      for (let j = 0; j < data.features.length; j++) lines.push(`cuts ${data.features[j]} ${full.cuts[j].map(value => fixed(value)).join(' ')}`);
    }
    for (let t = 0; t < full.rounds.length; t++) {
      const round = full.rounds[t];
      const stump = round.stump;
      const prefix = `round ${t + 1} feature ${data.features[stump.feature]}`;
      if (name === 'discrete') {
        lines.push(`${prefix} threshold ${fixed(stump.thresholds[0])} polarity ${round.polarity} error ${fixed(round.error)}` +
          ` alpha ${fixed(round.alpha)} z ${fixed(round.z)} bound ${fixed(round.bound)}`);
        let maximum = 0;
        let squares = 0;
        for (let i = 0; i < round.weights.length; i++) {
          if (round.weights[i] > round.weights[maximum]) maximum = i;
          squares += round.weights[i] * round.weights[i];
        }
        lines.push(`weights ${t + 1} max ${fixed(round.weights[maximum], 6)} id ${data.train[maximum].id} ess ${fixed(1 / squares)}`);
      } else if (name === 'real') {
        lines.push(`${prefix} z ${fixed(round.z)} bound ${fixed(round.bound)} values ${stump.values.map(value => fixed(value)).join(' ')}`);
      } else {
        let line = `${prefix} threshold ${fixed(stump.thresholds[0])} left ${fixed(stump.values[0])} right ${fixed(stump.values[1])} error ${fixed(round.error)}`;
        if (name === 'logit') line += ` loss ${fixed(round.loss)}`;
        lines.push(line);
      }
    }
    if (name === 'discrete') {
      lines.push(`cv folds ${data.params.folds} selected ${cv.selected} errors ${cv.errors[cv.selected - 1]}/${data.train.length}`);
      for (let f = 0; f < cv.folds.length; f++) {
        const fold = cv.folds[f];
        lines.push(`fold ${f + 1} train ${fold.count} validation ${fold.validation.length} rounds ${fold.model.rounds.length}` +
          ` stop ${fold.model.stop} selected ${fold.errors[cv.selected - 1]}/${fold.validation.length} final ${fold.errors.at(-1)}/${fold.validation.length}`);
      }
      lines.push('cv_errors ' + cv.errors.join(' '));
    }
  }
  return lines;
}

function errorCurveLines(data, models, multi) {
  const lines = ['variant,round,train_error,test_error,train_loss,test_loss,min_margin'];
  for (const model of models) {
    for (let t = 0; t < model.curve.length; t++) {
      const row = model.curve[t];
      lines.push([model.name, t + 1, ratio(row.trainErrors, data.train.length), ratio(row.testErrors, data.test.length),
        fixed(row.trainLoss), fixed(row.testLoss), fixed(row.minimum)].join(','));
    }
  }
  for (let t = 0; t < multi.curve.length; t++) {
    lines.push(['samme', t + 1, ratio(multi.curve[t].train, data.multiTrain.length),
      ratio(multi.curve[t].test, data.multiTest.length), '-', '-', '-'].join(','));
  }
  return lines;
}

function predictionLines(data, models) {
  const lines = ['id,variant,score,label,' + data.features.join(',')];
  for (let i = 0; i < data.test.length; i++) {
    for (const model of models) {
      const contributions = Array(data.features.length).fill(0);
      for (const round of model.rounds) contributions[round.stump.feature] += round.stump.output(data.test[i].values);
      lines.push([data.test[i].id, model.name, fixed(model.testScores[i]), model.testPredictions[i],
        ...contributions.map(value => fixed(value))].join(','));
    }
  }
  return lines;
}

function rocLines(data, models) {
  const lines = ['variant,threshold,tp,fp'];
  for (const model of models) {
    const thresholds = [...new Set(model.testScores)].sort((a, b) => b - a);
    for (const threshold of thresholds) {
      let tp = 0;
      let fp = 0;
      for (let i = 0; i < data.test.length; i++) {
        if (model.testScores[i] < threshold) continue;
        if (data.test[i].label === 1) tp++;
        else fp++;
      }
      lines.push([model.name, fixed(threshold), tp, fp].join(','));
    }
  }
  return lines;
}

function importanceLines(items, names) {
  return items.map((item, index) =>
    `${index + 1} ${names[item.feature]} score ${fixed(item.score)} share ${fixed(item.share)} rounds ${item.count}`);
}

function permutationImportance(model, rows, featureCount, repeats, generator) {
  const base = rows.length - errorCount(rows, model.testScores);
  const results = [];
  for (let feature = 0; feature < featureCount; feature++) {
    const counts = [];
    let drop = 0;
    for (let r = 0; r < repeats; r++) {
      const permutation = rows.map((row, index) => index);
      for (let i = rows.length - 1; i >= 1; i--) {
        const other = generator.next() % (i + 1);
        [permutation[i], permutation[other]] = [permutation[other], permutation[i]];
      }
      let correct = 0;
      for (let i = 0; i < rows.length; i++) {
        const values = rows[i].values.slice();
        values[feature] = rows[permutation[i]].values[feature];
        if (prediction(score(model.rounds, values)) === rows[i].label) correct++;
      }
      counts.push(correct);
      drop += base - correct;
    }
    results.push({ feature, drop, minimum: Math.min(...counts), maximum: Math.max(...counts) });
  }
  results.sort((a, b) => b.drop - a.drop || a.feature - b.feature);
  return { base, results };
}

function marginLines(data, models) {
  const lines = [];
  const generator = new Minstd(data.params.permutationSeed);
  for (const model of models) {
    if (lines.length > 0) lines.push('');
    lines.push(`variant ${model.name} rounds ${model.rounds.length} scale ${fixed(model.scale)}`,
      `train min ${fixed(Math.min(...model.trainMargins))} mean ${fixed(sum(model.trainMargins) / data.train.length)}`);
    for (const threshold of data.params.margins) {
      const count = countAtMost(model.trainMargins, threshold);
      lines.push(`train le ${fixed(threshold)} ${count}/${data.train.length} ${ratio(count, data.train.length)}`);
    }
    const histogram = Array(20).fill(0);
    for (const margin of model.trainMargins) histogram[Math.min(19, Math.floor((margin + 1) * 10))]++;
    lines.push('histogram ' + histogram.join(' '));
    const hardest = data.train.map((row, index) => index).sort((a, b) => model.trainMargins[a] - model.trainMargins[b] || a - b);
    for (const i of hardest.slice(0, 5)) lines.push(`hardest ${data.train[i].id} label ${data.train[i].label} margin ${fixed(model.trainMargins[i])}`);
    lines.push(`test min ${fixed(Math.min(...model.testMargins))} mean ${fixed(sum(model.testMargins) / data.test.length)}`);
    for (const threshold of data.params.margins) {
      const count = countAtMost(model.testMargins, threshold);
      lines.push(`test le ${fixed(threshold)} ${count}/${data.test.length} ${ratio(count, data.test.length)}`);
    }
    for (const threshold of data.params.margins) {
      let count = 0;
      let correct = 0;
      for (let i = 0; i < data.test.length; i++) {
        if (Math.abs(model.testMargins[i]) <= threshold) continue;
        count++;
        if (model.testPredictions[i] === data.test[i].label) correct++;
      }
      lines.push(`test confident ${fixed(threshold)} ${count}/${data.test.length} correct ${correct}/${count} ${ratio(correct, count)}`);
    }
    lines.push('importance', ...importanceLines(model.importance, data.features));
    const permutation = permutationImportance(model, data.test, data.features.length, data.params.permutationRepeats, generator);
    lines.push(`permutation repeats ${data.params.permutationRepeats} base ${permutation.base}/${data.test.length}`);
    for (let i = 0; i < permutation.results.length; i++) {
      const item = permutation.results[i];
      lines.push(`${i + 1} ${data.features[item.feature]} drop ${ratio(item.drop, data.params.permutationRepeats * data.test.length)}` +
        ` min ${item.minimum}/${data.test.length} max ${item.maximum}/${data.test.length}`);
    }
  }
  return lines;
}

function shapeLines(data, models) {
  const lines = [];
  for (const model of models) {
    if (lines.length > 0) lines.push('');
    lines.push(`variant ${model.name} rounds ${model.rounds.length}`);
    for (let feature = 0; feature < data.features.length; feature++) {
      const rounds = model.rounds.filter(round => round.stump.feature === feature);
      const thresholds = [...new Set(rounds.flatMap(round => round.stump.thresholds))].sort((a, b) => a - b);
      const values = [];
      for (let interval = 0; interval <= thresholds.length; interval++) {
        let total = 0;
        for (const round of rounds) {
          let bin = 0;
          if (interval > 0) {
            for (const threshold of round.stump.thresholds) if (threshold <= thresholds[interval - 1]) bin++;
          }
          total += round.stump.values[bin];
        }
        values.push(total);
      }
      lines.push(`feature ${data.features[feature]} rounds ${rounds.length} cuts ${thresholds.length} range ${fixed(Math.max(...values) - Math.min(...values))}`);
      for (let i = 0; i < values.length; i++) {
        const lower = i === 0 ? '-inf' : fixed(thresholds[i - 1]);
        const upper = i === thresholds.length ? 'inf' : fixed(thresholds[i]);
        lines.push(`interval ${lower} ${upper} value ${fixed(values[i])}`);
      }
    }
  }
  return lines;
}

function metricsLine(kind, variant, rounds, rows, scores) {
  let tp = 0;
  let fp = 0;
  let tn = 0;
  let fn = 0;
  for (let i = 0; i < rows.length; i++) {
    const predicted = prediction(scores[i]);
    if (rows[i].label === 1) {
      if (predicted === 1) tp++;
      else fn++;
    } else if (predicted === 1) fp++;
    else tn++;
  }
  return `${kind} ${variant} rounds ${rounds} correct ${tp + tn}/${rows.length} accuracy ${ratio(tp + tn, rows.length)}` +
    ` tp ${tp} fp ${fp} tn ${tn} fn ${fn} precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)}` +
    ` f1 ${ratio(2 * tp, 2 * tp + fp + fn)} auc ${auc(rows, scores)} loss ${fixed(loss(rows, scores, variant))}`;
}

function featureSummary(rows, feature) {
  const values = rows.map(row => row.values[feature]);
  return `${fixed(Math.min(...values))} ${fixed(Math.max(...values))} ${fixed(sum(values) / values.length)} ${new Set(values).size}`;
}

function variantPairs(models) {
  const pairs = [];
  for (let a = 0; a < models.length; a++) {
    for (let b = a + 1; b < models.length; b++) pairs.push([a, b]);
  }
  return pairs;
}

function bootstrapLines(data, models) {
  const { bootstrapSamples: samples, bootstrapSeed: seed } = data.params;
  const generator = new Minstd(seed);
  const counts = models.map(() => []);
  for (let sample = 0; sample < samples; sample++) {
    const selected = [];
    for (let i = 0; i < data.test.length; i++) selected.push(generator.next() % data.test.length);
    for (let v = 0; v < models.length; v++) {
      let correct = 0;
      for (const i of selected) if (models[v].testPredictions[i] === data.test[i].label) correct++;
      counts[v].push(correct);
    }
  }
  const lines = [`bootstrap samples ${samples} seed ${seed}`];
  const tail = Math.floor(samples / 40);
  for (let v = 0; v < models.length; v++) {
    const sorted = counts[v].slice().sort((a, b) => a - b);
    lines.push(`${models[v].name} mean ${ratio(sum(counts[v]), samples * data.test.length)}` +
      ` low ${ratio(sorted[tail], data.test.length)} high ${ratio(sorted[samples - tail - 1], data.test.length)}`);
  }
  for (const [a, b] of variantPairs(models)) {
    let first = 0;
    let tie = 0;
    let second = 0;
    for (let i = 0; i < samples; i++) {
      if (counts[a][i] > counts[b][i]) first++;
      else if (counts[a][i] < counts[b][i]) second++;
      else tie++;
    }
    lines.push(`${models[a].name} ${models[b].name} first ${first} tie ${tie} second ${second}`);
  }
  return lines;
}

function calibrationLines(data, models) {
  const lines = [];
  const ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0'];
  for (const model of models) {
    const bins = Array.from({ length: 5 }, () => ({ count: 0, probability: 0, positive: 0 }));
    let brier = 0;
    for (let i = 0; i < data.test.length; i++) {
      const probability = 1 / (1 + Math.exp(-2 * model.testScores[i]));
      const target = data.test[i].label === 1 ? 1 : 0;
      brier += (probability - target) * (probability - target);
      const bin = bins[Math.min(4, Math.floor(probability * 5))];
      bin.count++;
      bin.probability += probability;
      bin.positive += target;
    }
    lines.push(`calibration ${model.name} brier ${fixed(brier / data.test.length)}`);
    for (let i = 0; i < bins.length; i++) {
      const bin = bins[i];
      lines.push(`bin ${ranges[i]} count ${bin.count} mean ${ratio(bin.probability, bin.count)} positives ${bin.positive}`);
    }
  }
  return lines;
}

function summaryLines(data, models, cv) {
  const positives = rows => rows.filter(row => row.label === 1).length;
  const lines = [`data train ${data.train.length} test ${data.test.length} features ${data.features.length}` +
    ` positives ${positives(data.train)} ${positives(data.test)}`];
  for (let j = 0; j < data.features.length; j++) {
    lines.push(`feature ${data.features[j]} train ${featureSummary(data.train, j)} test ${featureSummary(data.test, j)}`);
  }
  lines.push(`cv selected ${cv.selected} errors ${cv.errors[cv.selected - 1]}/${data.train.length} rate ${ratio(cv.errors[cv.selected - 1], data.train.length)}`,
    metricsLine('oof', 'discrete', cv.selected, data.train, cv.scores));
  for (const model of models) {
    lines.push(metricsLine('train', model.name, model.rounds.length, data.train, model.trainScores),
      metricsLine('test', model.name, model.rounds.length, data.test, model.testScores));
  }
  const committeeRounds = sum(models.map(model => model.rounds.length));
  for (const kind of ['train', 'test']) {
    const rows = data[kind];
    const scores = rows.map((row, index) => {
      let total = 0;
      for (const model of models) total += model[kind + 'Scores'][index] / model.scale;
      return total;
    });
    lines.push(metricsLine(kind, 'committee', committeeRounds, rows, scores));
  }
  for (const model of models) {
    const trainMinimum = minimumPosition(model.curve.map(row => row.trainErrors));
    const testMinimum = minimumPosition(model.curve.map(row => row.testErrors));
    lines.push(`curve ${model.name} rounds ${model.full.rounds.length} train_min ${model.curve[trainMinimum].trainErrors}/${data.train.length}` +
      ` at ${trainMinimum + 1} test_min ${model.curve[testMinimum].testErrors}/${data.test.length} at ${testMinimum + 1}`);
  }
  const wrong = data.test.filter((row, i) => models.every(model => model.testPredictions[i] !== row.label));
  lines.push(['all_wrong', wrong.length, ...wrong.map(row => row.id)].join(' '), 'agreement');
  for (const [a, b] of variantPairs(models)) {
    let agree = 0;
    let first = 0;
    let second = 0;
    for (let i = 0; i < data.test.length; i++) {
      const left = models[a].testPredictions[i];
      const right = models[b].testPredictions[i];
      if (left === right) agree++;
      if (left === data.test[i].label && right !== data.test[i].label) first++;
      if (right === data.test[i].label && left !== data.test[i].label) second++;
    }
    const difference = Math.abs(first - second) - 1;
    lines.push(`${models[a].name} ${models[b].name} agree ${agree}/${data.test.length} only_first ${first} only_second ${second}` +
      ` chi2 ${ratio(difference * difference, first + second)}`);
  }
  lines.push(...bootstrapLines(data, models), ...calibrationLines(data, models));
  return lines;
}

function classPrediction(scores) {
  let best = 0;
  for (let c = 1; c < scores.length; c++) if (scores[c] > scores[best]) best = c;
  return best + 1;
}

function multiclassErrors(rows, predictions) {
  let errors = 0;
  for (let i = 0; i < rows.length; i++) if (predictions[i] !== rows[i].category) errors++;
  return errors;
}

function multiclassAnalysis(data) {
  const { multiTrain: train, multiTest: test, params } = data;
  const model = samme(train, params.classes, params.sammeRounds);
  const trainScores = train.map(() => Array(params.classes).fill(0));
  const testScores = test.map(() => Array(params.classes).fill(0));
  const progress = [];
  for (const round of model.rounds) {
    for (let i = 0; i < train.length; i++) trainScores[i][round.stump.output(train[i].values) - 1] += round.alpha;
    for (let i = 0; i < test.length; i++) testScores[i][round.stump.output(test[i].values) - 1] += round.alpha;
    progress.push({ train: multiclassErrors(train, trainScores.map(classPrediction)), test: multiclassErrors(test, testScores.map(classPrediction)) });
  }
  const ovr = [];
  for (let category = 1; category <= params.classes; category++) {
    const binaryTrain = train.map(row => ({ ...row, label: row.category === category ? 1 : -1 }));
    const binaryTest = test.map(row => ({ ...row, label: row.category === category ? 1 : -1 }));
    const binaryModel = discrete(binaryTrain, params.sammeRounds);
    const trainValues = scoreRows(binaryModel.rounds, binaryTrain);
    const testValues = scoreRows(binaryModel.rounds, binaryTest);
    ovr.push({ model: binaryModel, trainScores: trainValues, testScores: testValues,
      positives: binaryTrain.filter(row => row.label === 1).length,
      trainErrors: errorCount(binaryTrain, trainValues), testErrors: errorCount(binaryTest, testValues) });
  }
  return { model, curve: progress, trainScores, testScores, ovr,
    trainPredictions: trainScores.map(classPrediction), testPredictions: testScores.map(classPrediction),
    ovrTrain: train.map((row, i) => classPrediction(ovr.map(item => item.trainScores[i]))),
    ovrTest: test.map((row, i) => classPrediction(ovr.map(item => item.testScores[i]))) };
}

function confusionLines(rows, predictions, classes) {
  const matrix = confusion(rows, predictions, classes);
  const lines = ['confusion', ...matrix.map(row => row.join(' '))];
  for (let c = 0; c < classes; c++) {
    let column = 0;
    for (const row of matrix) column += row[c];
    lines.push(`class ${c + 1} precision ${ratio(matrix[c][c], column)} recall ${ratio(matrix[c][c], sum(matrix[c]))}`);
  }
  return lines;
}

function multiclassEvaluationLines(data, trainPredictions, testPredictions) {
  const trainErrors = multiclassErrors(data.multiTrain, trainPredictions);
  const testErrors = multiclassErrors(data.multiTest, testPredictions);
  return [`train errors ${trainErrors}/${data.multiTrain.length} rate ${ratio(trainErrors, data.multiTrain.length)}`,
    `test errors ${testErrors}/${data.multiTest.length} rate ${ratio(testErrors, data.multiTest.length)}`,
    ...confusionLines(data.multiTest, testPredictions, data.params.classes)];
}

function sammeLines(data, multi) {
  const { model } = multi;
  const lines = [`samme classes ${data.params.classes} train ${data.multiTrain.length} test ${data.multiTest.length}` +
    ` rounds ${model.rounds.length} stop ${model.stop}`];
  for (let t = 0; t < model.rounds.length; t++) {
    const round = model.rounds[t];
    const stump = round.stump;
    lines.push(`round ${t + 1} feature ${data.multiFeatures[stump.feature]} threshold ${fixed(stump.thresholds[0])}` +
      ` left ${stump.values[0]} right ${stump.values[1]} error ${fixed(round.error)} alpha ${fixed(round.alpha)}`);
  }
  lines.push(...multiclassEvaluationLines(data, multi.trainPredictions, multi.testPredictions), 'importance',
    ...importanceLines(importance(model.rounds, data.multiFeatures.length, true), data.multiFeatures),
    '', `ovr classes ${data.params.classes} rounds ${data.params.sammeRounds}`);
  for (let c = 0; c < multi.ovr.length; c++) {
    const item = multi.ovr[c];
    lines.push(`class ${c + 1} rounds ${item.model.rounds.length} stop ${item.model.stop} positives ${item.positives}` +
      ` train_errors ${item.trainErrors}/${data.multiTrain.length} test_errors ${item.testErrors}/${data.multiTest.length}`);
  }
  lines.push(...multiclassEvaluationLines(data, multi.ovrTrain, multi.ovrTest));
  let agree = 0;
  for (let i = 0; i < data.multiTest.length; i++) if (multi.testPredictions[i] === multi.ovrTest[i]) agree++;
  lines.push(`agreement ${agree}/${data.multiTest.length}`, '', 'predictions');
  for (let i = 0; i < data.multiTest.length; i++) {
    const row = data.multiTest[i];
    lines.push(`${row.id} class ${row.category} samme ${multi.testPredictions[i]} ovr ${multi.ovrTest[i]}` +
      ` scores ${multi.testScores[i].map(value => fixed(value)).join(' ')}`);
  }
  return lines;
}

function experimentStats(model, train, test) {
  const trainErrors = errorCount(train, scoreRows(model.rounds, train));
  const testScores = Array(test.length).fill(0);
  const testErrors = [];
  for (const round of model.rounds) {
    for (let i = 0; i < test.length; i++) testScores[i] += round.stump.output(test[i].values);
    testErrors.push(errorCount(test, testScores));
  }
  const minimum = minimumPosition(testErrors);
  return { trainErrors, testErrors: testErrors.at(-1), minimum: testErrors[minimum], at: minimum + 1 };
}

function experimentFields(model, stats, trainCount, testCount) {
  return `rounds ${model.rounds.length} stop ${model.stop} train_errors ${stats.trainErrors}/${trainCount} test_errors ${stats.testErrors}/${testCount}`;
}

function experimentLines(data, models, cv) {
  const { train, test, params } = data;
  const lines = [];
  for (const percentage of params.sizes) {
    const count = Math.floor(train.length * percentage / 100);
    const selected = train.slice(0, count);
    lines.push(`size ${percentage} rows ${count}`);
    for (const variant of params.variants) {
      const model = trainVariant(variant, selected, params);
      lines.push(`${variant} ${experimentFields(model, experimentStats(model, selected, test), count, test.length)}`);
    }
  }
  for (const shrinkage of params.shrinkage) {
    const model = discrete(train, params.rounds, shrinkage);
    const stats = experimentStats(model, train, test);
    lines.push(`shrinkage ${fixed(shrinkage)} ${experimentFields(model, stats, train.length, test.length)}` +
      ` test_min ${stats.minimum}/${test.length} at ${stats.at}`);
  }
  const ranks = models.find(model => model.name === 'discrete').importance;
  for (let count = 1; count <= data.features.length; count++) {
    const features = ranks.slice(0, count).map(item => item.feature).sort((a, b) => a - b);
    const project = rows => rows.map(row => ({ ...row, values: features.map(feature => row.values[feature]) }));
    const reducedTrain = project(train);
    const reducedTest = project(test);
    const model = discrete(reducedTrain, cv.selected);
    const stats = experimentStats(model, reducedTrain, reducedTest);
    lines.push(`top ${count} features ${features.map(feature => data.features[feature]).join(' ')} rounds ${model.rounds.length}` +
      ` train_errors ${stats.trainErrors}/${train.length} test_errors ${stats.testErrors}/${test.length}`);
  }
  for (const percentage of params.noise) {
    const count = Math.floor(train.length * percentage / 100);
    const generator = new Minstd(params.noiseSeed);
    const permutation = train.map((row, index) => index);
    for (let i = 0; i < count; i++) {
      const other = i + generator.next() % (train.length - i);
      [permutation[i], permutation[other]] = [permutation[other], permutation[i]];
    }
    const flipped = new Set(permutation.slice(0, count));
    const noisy = train.map((row, index) => ({ ...row, label: flipped.has(index) ? -row.label : row.label }));
    lines.push(`noise ${percentage} flipped ${count}`);
    for (const variant of params.variants) {
      const model = trainVariant(variant, noisy, params);
      const stats = experimentStats(model, noisy, test);
      const weights = model.rounds.at(-1).weights;
      let flippedWeight = 0;
      for (let i = 0; i < train.length; i++) if (flipped.has(i)) flippedWeight += weights[i];
      lines.push(`${variant} ${experimentFields(model, stats, train.length, test.length)}` +
        ` test_min ${stats.minimum}/${test.length} at ${stats.at} flipped_weight ${fixed(flippedWeight)}`);
    }
  }
  return lines;
}

function main() {
  const data = readDataset();
  const cv = crossValidation(data.train, data.params);
  const models = analyzeModels(data, cv);
  const multi = multiclassAnalysis(data);
  const outputs = [
    ['ensemble.txt', ensembleLines(data, models, cv)],
    ['error_curve.csv', errorCurveLines(data, models, multi)],
    ['predictions.csv', predictionLines(data, models)],
    ['roc.csv', rocLines(data, models)],
    ['margins.txt', marginLines(data, models)],
    ['shapes.txt', shapeLines(data, models)],
    ['samme.txt', sammeLines(data, multi)],
    ['summary.txt', summaryLines(data, models, cv)],
    ['experiments.txt', experimentLines(data, models, cv)]
  ];
  for (const [name, lines] of outputs) writeLines(name, lines);
}

main();
