import { readDataset } from './dataset.ts';
import type { BinaryRow, MultiRow, ValuesRow, Parameters, Variant } from './dataset.ts';
import { discrete, samme } from './adaboost.ts';
import type { Training, Round } from './adaboost.ts';
import { real, gentle, logit } from './variants.ts';
import { largestIndex } from './stumps.ts';
import type { Stump } from './stumps.ts';
import { fixed, ratio, prediction, auc, confusion, countAtMost, writeLines } from './evaluation.ts';

type Data = ReturnType<typeof readDataset>;
type CV = ReturnType<typeof crossValidation>;
type Model = ReturnType<typeof analyzeModels>[number];
type Multi = ReturnType<typeof multiclassAnalysis>;
interface StumpRound { stump: Stump }
class Minstd {
  constructor(private state: number) {}
  next(): number { this.state = 48271 * this.state % 2147483647; return this.state; }
}
function sum(values: number[]): number { let total = 0; for (const value of values) total += value; return total; }
function trainVariant(name: Variant, rows: BinaryRow[], params: Parameters): Training {
  switch (name) { case 'discrete': return discrete(rows, params.rounds); case 'real': return real(rows, params);
    case 'gentle': return gentle(rows, params); case 'logit': return logit(rows, params); }
}
function score(rounds: StumpRound[], values: number[]): number {
  let result = 0;
  for (const round of rounds) result += round.stump.output(values);
  return result;
}
const scoreRows = (rounds: StumpRound[], rows: ValuesRow[]) => rows.map(row => score(rounds, row.values));
const magnitude = (round: StumpRound) => Math.max(...round.stump.values.map(Math.abs));
function errorCount(rows: BinaryRow[], scores: number[]): number {
  let errors = 0;
  rows.forEach((row, i) => { if (prediction(scores[i]) !== row.label) errors++; });
  return errors;
}
function loss(rows: BinaryRow[], scores: number[], variant: string): number {
  let total = 0;
  rows.forEach((row, i) => { total += variant === 'logit' ? Math.log(1 + Math.exp(-2 * row.label * scores[i])) : Math.exp(-row.label * scores[i]); });
  return total / rows.length;
}
function minimumPosition(values: number[]): number {
  let best = 0;
  for (let i = 1; i < values.length; i++) if (values[i] < values[best]) best = i;
  return best;
}
function curve(rounds: Round[], train: BinaryRow[], test: BinaryRow[], variant: Variant) {
  const trainScores = train.map(() => 0), testScores = test.map(() => 0);
  let scale = 0;
  return rounds.map(round => {
    train.forEach((row, i) => { trainScores[i] += round.stump.output(row.values); });
    test.forEach((row, i) => { testScores[i] += round.stump.output(row.values); });
    scale += magnitude(round);
    return { trainErrors: errorCount(train, trainScores), testErrors: errorCount(test, testScores),
      trainLoss: loss(train, trainScores, variant), testLoss: loss(test, testScores, variant),
      minimum: Math.min(...train.map((row, i) => row.label * trainScores[i])) / scale };
  });
}
function crossValidation(rows: BinaryRow[], params: Parameters) {
  const folds = Array.from({ length: params.folds }, (_, fold) => {
    const validation = rows.map((_, i) => i).filter(i => i % params.folds === fold), count = rows.length - validation.length;
    const model = discrete(rows, params.rounds, 1, rows.map((_, i) => i % params.folds === fold ? 0 : 1 / count));
    const scores = validation.map(() => 0), errors: number[] = [];
    for (let t = 0; t < params.rounds; t++) {
      if (t < model.rounds.length) validation.forEach((row, i) => { scores[i] += model.rounds[t].stump.output(rows[row].values); });
      errors.push(validation.filter((row, i) => prediction(scores[i]) !== rows[row].label).length);
    }
    return { model, validation, count, errors };
  });
  const errors = Array<number>(params.rounds).fill(0);
  for (const fold of folds) for (let t = 0; t < params.rounds; t++) errors[t] += fold.errors[t];
  const selected = minimumPosition(errors) + 1, scores = rows.map(() => 0);
  for (const fold of folds) for (const i of fold.validation) scores[i] = score(fold.model.rounds.slice(0, selected), rows[i].values);
  return { folds, errors, selected, scores };
}
function importance<R extends StumpRound>(rounds: R[], featureCount: number, valueOf: (round: R) => number = magnitude) {
  const features = Array.from({ length: featureCount }, (_, feature) => ({ feature, score: 0, count: 0, share: 0 }));
  for (const round of rounds) { const item = features[round.stump.feature]; item.score += valueOf(round); item.count++; }
  const total = sum(features.map(item => item.score));
  for (const item of features) item.share = item.score / total;
  return features.sort((a, b) => b.score - a.score || a.feature - b.feature);
}
function analyzeModels(data: Data, cv: CV) {
  return data.params.variants.map(name => {
    const full = trainVariant(name, data.train, data.params), rounds = name === 'discrete' ? full.rounds.slice(0, cv.selected) : full.rounds.slice();
    const scale = sum(rounds.map(magnitude)), trainScores = scoreRows(rounds, data.train), testScores = scoreRows(rounds, data.test);
    return { name, full, rounds, scale, trainScores, testScores, trainMargins: data.train.map((r, i) => r.label * trainScores[i] / scale),
      testMargins: data.test.map((r, i) => r.label * testScores[i] / scale), trainPredictions: trainScores.map(prediction), testPredictions: testScores.map(prediction),
      curve: curve(full.rounds, data.train, data.test, name), importance: importance(rounds, data.features.length) };
  });
}
function ensembleLines(data: Data, models: Model[], cv: CV): string[] {
  const lines: string[] = [];
  for (const { name, full } of models) {
    if (lines.length) lines.push('');
    let heading = `variant ${name} rounds ${full.rounds.length} stop ${full.stop}`;
    if (name === 'real') heading += ` bins ${data.params.bins} smoothing ${fixed(data.params.smoothing)} convergence ${fixed(data.params.convergence, 6)}`;
    if (name === 'logit') heading += ` clip ${fixed(data.params.clip)}`;
    lines.push(heading);
    if (name === 'real') data.features.forEach((feature, j) => lines.push(`cuts ${feature} ${full.cuts![j].map(v => fixed(v)).join(' ')}`));
    full.rounds.forEach((round, t) => {
      const stump = round.stump, prefix = `round ${t + 1} feature ${data.features[stump.feature]}`;
      if (round.kind === 'discrete') {
        lines.push(`${prefix} threshold ${fixed(stump.thresholds[0])} polarity ${round.polarity} error ${fixed(round.error)} alpha ${fixed(round.alpha)} z ${fixed(round.z)} bound ${fixed(round.bound)}`);
        let maximum = 0, squares = 0;
        round.weights.forEach((w, i) => { if (w > round.weights[maximum]) maximum = i; squares += w * w; });
        lines.push(`weights ${t + 1} max ${fixed(round.weights[maximum], 6)} id ${data.train[maximum].id} ess ${fixed(1 / squares)}`);
      } else if (round.kind === 'real') lines.push(`${prefix} z ${fixed(round.z)} bound ${fixed(round.bound)} values ${stump.values.map(v => fixed(v)).join(' ')}`);
      else lines.push(`${prefix} threshold ${fixed(stump.thresholds[0])} left ${fixed(stump.values[0])} right ${fixed(stump.values[1])} error ${fixed(round.error)}`
        + (round.kind === 'logit' ? ` loss ${fixed(round.loss)}` : ''));
    });
    if (name === 'discrete') {
      lines.push(`cv folds ${data.params.folds} selected ${cv.selected} errors ${cv.errors[cv.selected - 1]}/${data.train.length}`);
      cv.folds.forEach((f, i) => lines.push(`fold ${i + 1} train ${f.count} validation ${f.validation.length} rounds ${f.model.rounds.length} stop ${f.model.stop} selected ${f.errors[cv.selected - 1]}/${f.validation.length} final ${f.errors[f.errors.length - 1]}/${f.validation.length}`));
      lines.push('cv_errors ' + cv.errors.join(' '));
    }
  }
  return lines;
}
function errorCurveLines(data: Data, models: Model[], multi: Multi): string[] {
  return ['variant,round,train_error,test_error,train_loss,test_loss,min_margin', ...models.flatMap(m => m.curve.map((r, i) =>
    [m.name, i + 1, ratio(r.trainErrors, data.train.length), ratio(r.testErrors, data.test.length), fixed(r.trainLoss), fixed(r.testLoss), fixed(r.minimum)].join(','))),
  ...multi.curve.map((r, i) => ['samme', i + 1, ratio(r.train, data.multiTrain.length), ratio(r.test, data.multiTest.length), '-', '-', '-'].join(','))];
}
function predictionLines(data: Data, models: Model[]): string[] {
  const lines = ['id,variant,score,label,' + data.features.join(',')];
  data.test.forEach((row, i) => {
    for (const m of models) {
      const contributions = data.features.map(() => 0);
      for (const r of m.rounds) contributions[r.stump.feature] += r.stump.output(row.values);
      lines.push([row.id, m.name, fixed(m.testScores[i]), m.testPredictions[i], ...contributions.map(v => fixed(v))].join(','));
    }
  });
  return lines;
}
function rocLines(data: Data, models: Model[]): string[] {
  const lines = ['variant,threshold,tp,fp'];
  for (const m of models) for (const threshold of [...new Set(m.testScores)].sort((a, b) => b - a)) {
    let tp = 0, fp = 0;
    data.test.forEach((r, i) => { if (m.testScores[i] >= threshold) { if (r.label === 1) tp++; else fp++; } });
    lines.push([m.name, fixed(threshold), tp, fp].join(','));
  }
  return lines;
}
function importanceLines(items: ReturnType<typeof importance>, names: string[]): string[] {
  return items.map((item, i) => `${i + 1} ${names[item.feature]} score ${fixed(item.score)} share ${fixed(item.share)} rounds ${item.count}`);
}
function permutationImportance(model: Model, rows: BinaryRow[], featureCount: number, repeats: number, generator: Minstd) {
  const base = rows.length - errorCount(rows, model.testScores), results: { feature: number; drop: number; minimum: number; maximum: number }[] = [];
  for (let feature = 0; feature < featureCount; feature++) {
    const counts: number[] = [];
    let drop = 0;
    for (let r = 0; r < repeats; r++) {
      const permutation = rows.map((_, i) => i);
      for (let i = rows.length - 1; i >= 1; i--) {
        const other = generator.next() % (i + 1);
        [permutation[i], permutation[other]] = [permutation[other], permutation[i]];
      }
      let correct = 0;
      rows.forEach((row, i) => {
        const values = row.values.slice(); values[feature] = rows[permutation[i]].values[feature];
        if (prediction(score(model.rounds, values)) === row.label) correct++;
      });
      counts.push(correct); drop += base - correct;
    }
    results.push({ feature, drop, minimum: Math.min(...counts), maximum: Math.max(...counts) });
  }
  return { base, results: results.sort((a, b) => b.drop - a.drop || a.feature - b.feature) };
}
function marginLines(data: Data, models: Model[]): string[] {
  const lines: string[] = [], generator = new Minstd(data.params.permutationSeed);
  for (const m of models) {
    if (lines.length) lines.push('');
    lines.push(`variant ${m.name} rounds ${m.rounds.length} scale ${fixed(m.scale)}`, `train min ${fixed(Math.min(...m.trainMargins))} mean ${fixed(sum(m.trainMargins) / data.train.length)}`);
    for (const threshold of data.params.margins) {
      const count = countAtMost(m.trainMargins, threshold); lines.push(`train le ${fixed(threshold)} ${count}/${data.train.length} ${ratio(count, data.train.length)}`);
    }
    const histogram = Array<number>(20).fill(0);
    for (const margin of m.trainMargins) histogram[Math.min(19, Math.floor((margin + 1) * 10))]++;
    lines.push('histogram ' + histogram.join(' '));
    const hardest = data.train.map((_, i) => i).sort((a, b) => m.trainMargins[a] - m.trainMargins[b] || a - b);
    for (const i of hardest.slice(0, 5)) lines.push(`hardest ${data.train[i].id} label ${data.train[i].label} margin ${fixed(m.trainMargins[i])}`);
    lines.push(`test min ${fixed(Math.min(...m.testMargins))} mean ${fixed(sum(m.testMargins) / data.test.length)}`);
    for (const threshold of data.params.margins) {
      const count = countAtMost(m.testMargins, threshold); lines.push(`test le ${fixed(threshold)} ${count}/${data.test.length} ${ratio(count, data.test.length)}`);
    }
    for (const threshold of data.params.margins) {
      let count = 0, correct = 0;
      data.test.forEach((row, i) => { if (Math.abs(m.testMargins[i]) > threshold) { count++; if (m.testPredictions[i] === row.label) correct++; } });
      lines.push(`test confident ${fixed(threshold)} ${count}/${data.test.length} correct ${correct}/${count} ${ratio(correct, count)}`);
    }
    lines.push('importance', ...importanceLines(m.importance, data.features));
    const permutation = permutationImportance(m, data.test, data.features.length, data.params.permutationRepeats, generator);
    lines.push(`permutation repeats ${data.params.permutationRepeats} base ${permutation.base}/${data.test.length}`);
    permutation.results.forEach((r, i) => lines.push(`${i + 1} ${data.features[r.feature]} drop ${ratio(r.drop, data.params.permutationRepeats * data.test.length)} min ${r.minimum}/${data.test.length} max ${r.maximum}/${data.test.length}`));
  }
  return lines;
}
function shapeLines(data: Data, models: Model[]): string[] {
  const lines: string[] = [];
  for (const model of models) {
    if (lines.length) lines.push('');
    lines.push(`variant ${model.name} rounds ${model.rounds.length}`);
    data.features.forEach((name, feature) => {
      const rounds = model.rounds.filter(r => r.stump.feature === feature), thresholds = [...new Set(rounds.flatMap(r => r.stump.thresholds))].sort((a, b) => a - b);
      const values = Array.from({ length: thresholds.length + 1 }, (_, interval) => {
        let total = 0;
        for (const round of rounds) {
          let bin = 0;
          if (interval > 0) for (const threshold of round.stump.thresholds) if (threshold <= thresholds[interval - 1]) bin++;
          total += round.stump.values[bin];
        }
        return total;
      });
      lines.push(`feature ${name} rounds ${rounds.length} cuts ${thresholds.length} range ${fixed(Math.max(...values) - Math.min(...values))}`);
      values.forEach((v, i) => lines.push(`interval ${i === 0 ? '-inf' : fixed(thresholds[i - 1])} ${i === thresholds.length ? 'inf' : fixed(thresholds[i])} value ${fixed(v)}`));
    });
  }
  return lines;
}
function metricsLine(kind: string, variant: string, rounds: number, rows: BinaryRow[], scores: number[]): string {
  let tp = 0, fp = 0, tn = 0, fn = 0;
  rows.forEach((row, i) => { const p = prediction(scores[i]); if (row.label === 1) { if (p === 1) tp++; else fn++; } else if (p === 1) fp++; else tn++; });
  return `${kind} ${variant} rounds ${rounds} correct ${tp + tn}/${rows.length} accuracy ${ratio(tp + tn, rows.length)} tp ${tp} fp ${fp} tn ${tn} fn ${fn} precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)} f1 ${ratio(2 * tp, 2 * tp + fp + fn)} auc ${auc(rows, scores)} loss ${fixed(loss(rows, scores, variant))}`;
}
function featureSummary(rows: ValuesRow[], feature: number): string {
  const values = rows.map(row => row.values[feature]);
  return `${fixed(Math.min(...values))} ${fixed(Math.max(...values))} ${fixed(sum(values) / values.length)} ${new Set(values).size}`;
}
function variantPairs(models: Model[]): [number, number][] {
  const pairs: [number, number][] = [];
  for (let a = 0; a < models.length; a++) for (let b = a + 1; b < models.length; b++) pairs.push([a, b]);
  return pairs;
}
function bootstrapLines(data: Data, models: Model[]): string[] {
  const { bootstrapSamples: samples, bootstrapSeed: seed } = data.params, generator = new Minstd(seed), counts = models.map((): number[] => []);
  for (let s = 0; s < samples; s++) {
    const selected = data.test.map(() => generator.next() % data.test.length);
    models.forEach((m, v) => counts[v].push(selected.filter(i => m.testPredictions[i] === data.test[i].label).length));
  }
  const lines = [`bootstrap samples ${samples} seed ${seed}`], tail = Math.floor(samples / 40);
  models.forEach((m, v) => {
    const sorted = counts[v].slice().sort((a, b) => a - b);
    lines.push(`${m.name} mean ${ratio(sum(counts[v]), samples * data.test.length)} low ${ratio(sorted[tail], data.test.length)} high ${ratio(sorted[samples - tail - 1], data.test.length)}`);
  });
  for (const [a, b] of variantPairs(models)) {
    let first = 0, tie = 0, second = 0;
    for (let i = 0; i < samples; i++) { if (counts[a][i] > counts[b][i]) first++; else if (counts[a][i] < counts[b][i]) second++; else tie++; }
    lines.push(`${models[a].name} ${models[b].name} first ${first} tie ${tie} second ${second}`);
  }
  return lines;
}
function calibrationLines(data: Data, models: Model[]): string[] {
  const lines: string[] = [], ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0'];
  for (const model of models) {
    const bins = Array.from({ length: 5 }, () => ({ count: 0, probability: 0, positive: 0 }));
    let brier = 0;
    data.test.forEach((row, i) => {
      const p = 1 / (1 + Math.exp(-2 * model.testScores[i])), target = row.label === 1 ? 1 : 0;
      brier += (p - target) * (p - target);
      const bin = bins[Math.min(4, Math.floor(p * 5))]; bin.count++; bin.probability += p; bin.positive += target;
    });
    lines.push(`calibration ${model.name} brier ${fixed(brier / data.test.length)}`);
    bins.forEach((bin, i) => lines.push(`bin ${ranges[i]} count ${bin.count} mean ${ratio(bin.probability, bin.count)} positives ${bin.positive}`));
  }
  return lines;
}
function summaryLines(data: Data, models: Model[], cv: CV): string[] {
  const lines = [`data train ${data.train.length} test ${data.test.length} features ${data.features.length} positives ${data.train.filter(r => r.label === 1).length} ${data.test.filter(r => r.label === 1).length}`];
  data.features.forEach((name, j) => lines.push(`feature ${name} train ${featureSummary(data.train, j)} test ${featureSummary(data.test, j)}`));
  lines.push(`cv selected ${cv.selected} errors ${cv.errors[cv.selected - 1]}/${data.train.length} rate ${ratio(cv.errors[cv.selected - 1], data.train.length)}`, metricsLine('oof', 'discrete', cv.selected, data.train, cv.scores));
  for (const m of models) lines.push(metricsLine('train', m.name, m.rounds.length, data.train, m.trainScores), metricsLine('test', m.name, m.rounds.length, data.test, m.testScores));
  const committeeRounds = sum(models.map(m => m.rounds.length));
  const committee = (rows: BinaryRow[], training: boolean) => rows.map((_, i) => {
    let total = 0;
    for (const m of models) total += (training ? m.trainScores[i] : m.testScores[i]) / m.scale;
    return total;
  });
  lines.push(metricsLine('train', 'committee', committeeRounds, data.train, committee(data.train, true)), metricsLine('test', 'committee', committeeRounds, data.test, committee(data.test, false)));
  for (const m of models) {
    const a = minimumPosition(m.curve.map(r => r.trainErrors)), b = minimumPosition(m.curve.map(r => r.testErrors));
    lines.push(`curve ${m.name} rounds ${m.full.rounds.length} train_min ${m.curve[a].trainErrors}/${data.train.length} at ${a + 1} test_min ${m.curve[b].testErrors}/${data.test.length} at ${b + 1}`);
  }
  const wrong = data.test.filter((r, i) => models.every(m => m.testPredictions[i] !== r.label));
  lines.push(['all_wrong', wrong.length, ...wrong.map(r => r.id)].join(' '), 'agreement');
  for (const [a, b] of variantPairs(models)) {
    let agree = 0, first = 0, second = 0;
    data.test.forEach((row, i) => {
      const left = models[a].testPredictions[i], right = models[b].testPredictions[i];
      if (left === right) agree++;
      if (left === row.label && right !== row.label) first++;
      if (right === row.label && left !== row.label) second++;
    });
    const difference = Math.abs(first - second) - 1;
    lines.push(`${models[a].name} ${models[b].name} agree ${agree}/${data.test.length} only_first ${first} only_second ${second} chi2 ${ratio(difference * difference, first + second)}`);
  }
  return [...lines, ...bootstrapLines(data, models), ...calibrationLines(data, models)];
}
const classPrediction = (scores: number[]) => largestIndex(scores) + 1;
const multiclassErrors = (rows: MultiRow[], predictions: number[]) => rows.filter((r, i) => r.category !== predictions[i]).length;
function multiclassAnalysis(data: Data) {
  const { multiTrain: train, multiTest: test, params } = data, model = samme(train, params.classes, params.sammeRounds);
  const trainScores = train.map(() => Array<number>(params.classes).fill(0)), testScores = test.map(() => Array<number>(params.classes).fill(0));
  const progress = model.rounds.map(round => {
    train.forEach((r, i) => { trainScores[i][round.stump.output(r.values) - 1] += round.alpha; });
    test.forEach((r, i) => { testScores[i][round.stump.output(r.values) - 1] += round.alpha; });
    return { train: multiclassErrors(train, trainScores.map(classPrediction)), test: multiclassErrors(test, testScores.map(classPrediction)) };
  });
  const ovr = Array.from({ length: params.classes }, (_, c) => {
    const binaryTrain = train.map(r => ({ ...r, label: r.category === c + 1 ? 1 : -1 })), binaryTest = test.map(r => ({ ...r, label: r.category === c + 1 ? 1 : -1 }));
    const model = discrete(binaryTrain, params.sammeRounds), trainScores = scoreRows(model.rounds, binaryTrain), testScores = scoreRows(model.rounds, binaryTest);
    return { model, trainScores, testScores, positives: binaryTrain.filter(r => r.label === 1).length, trainErrors: errorCount(binaryTrain, trainScores), testErrors: errorCount(binaryTest, testScores) };
  });
  return { model, curve: progress, trainScores, testScores, ovr, trainPredictions: trainScores.map(classPrediction), testPredictions: testScores.map(classPrediction),
    ovrTrain: train.map((_, i) => classPrediction(ovr.map(m => m.trainScores[i]))), ovrTest: test.map((_, i) => classPrediction(ovr.map(m => m.testScores[i]))) };
}
function confusionLines(rows: MultiRow[], predictions: number[], classes: number): string[] {
  const matrix = confusion(rows, predictions, classes), lines = ['confusion', ...matrix.map(row => row.join(' '))];
  for (let c = 0; c < classes; c++) lines.push(`class ${c + 1} precision ${ratio(matrix[c][c], sum(matrix.map(r => r[c])))} recall ${ratio(matrix[c][c], sum(matrix[c]))}`);
  return lines;
}
function multiclassEvaluationLines(data: Data, trainPredictions: number[], testPredictions: number[]): string[] {
  const trainErrors = multiclassErrors(data.multiTrain, trainPredictions), testErrors = multiclassErrors(data.multiTest, testPredictions);
  return [`train errors ${trainErrors}/${data.multiTrain.length} rate ${ratio(trainErrors, data.multiTrain.length)}`, `test errors ${testErrors}/${data.multiTest.length} rate ${ratio(testErrors, data.multiTest.length)}`,
    ...confusionLines(data.multiTest, testPredictions, data.params.classes)];
}
function sammeLines(data: Data, multi: Multi): string[] {
  const model = multi.model, lines = [`samme classes ${data.params.classes} train ${data.multiTrain.length} test ${data.multiTest.length} rounds ${model.rounds.length} stop ${model.stop}`];
  model.rounds.forEach((r, t) => lines.push(`round ${t + 1} feature ${data.multiFeatures[r.stump.feature]} threshold ${fixed(r.stump.thresholds[0])} left ${r.stump.values[0]} right ${r.stump.values[1]} error ${fixed(r.error)} alpha ${fixed(r.alpha)}`));
  lines.push(...multiclassEvaluationLines(data, multi.trainPredictions, multi.testPredictions), 'importance', ...importanceLines(importance(model.rounds, data.multiFeatures.length, r => r.alpha), data.multiFeatures), '', `ovr classes ${data.params.classes} rounds ${data.params.sammeRounds}`);
  multi.ovr.forEach((r, c) => lines.push(`class ${c + 1} rounds ${r.model.rounds.length} stop ${r.model.stop} positives ${r.positives} train_errors ${r.trainErrors}/${data.multiTrain.length} test_errors ${r.testErrors}/${data.multiTest.length}`));
  lines.push(...multiclassEvaluationLines(data, multi.ovrTrain, multi.ovrTest), `agreement ${multi.testPredictions.filter((p, i) => p === multi.ovrTest[i]).length}/${data.multiTest.length}`, '', 'predictions');
  data.multiTest.forEach((r, i) => lines.push(`${r.id} class ${r.category} samme ${multi.testPredictions[i]} ovr ${multi.ovrTest[i]} scores ${multi.testScores[i].map(v => fixed(v)).join(' ')}`));
  return lines;
}
function experimentStats(model: Training, train: BinaryRow[], test: BinaryRow[]) {
  const trainErrors = errorCount(train, scoreRows(model.rounds, train)), scores = test.map(() => 0);
  const errors = model.rounds.map(round => { test.forEach((r, i) => { scores[i] += round.stump.output(r.values); }); return errorCount(test, scores); });
  const minimum = minimumPosition(errors);
  return { trainErrors, testErrors: errors[errors.length - 1], minimum: errors[minimum], at: minimum + 1 };
}
function experimentFields(model: Training, stats: ReturnType<typeof experimentStats>, trainCount: number, testCount: number): string {
  return `rounds ${model.rounds.length} stop ${model.stop} train_errors ${stats.trainErrors}/${trainCount} test_errors ${stats.testErrors}/${testCount}`;
}
function experimentLines(data: Data, models: Model[], cv: CV): string[] {
  const { train, test, params } = data, lines: string[] = [];
  for (const q of params.sizes) {
    const count = Math.floor(train.length * q / 100), selected = train.slice(0, count);
    lines.push(`size ${q} rows ${count}`);
    for (const variant of params.variants) { const m = trainVariant(variant, selected, params); lines.push(`${variant} ${experimentFields(m, experimentStats(m, selected, test), count, test.length)}`); }
  }
  for (const shrinkage of params.shrinkage) {
    const m = discrete(train, params.rounds, shrinkage), stats = experimentStats(m, train, test);
    lines.push(`shrinkage ${fixed(shrinkage)} ${experimentFields(m, stats, train.length, test.length)} test_min ${stats.minimum}/${test.length} at ${stats.at}`);
  }
  const ranks = models.find(m => m.name === 'discrete')!.importance;
  for (let count = 1; count <= data.features.length; count++) {
    const features = ranks.slice(0, count).map(r => r.feature).sort((a, b) => a - b);
    const project = (rows: BinaryRow[]) => rows.map(row => ({ ...row, values: features.map(f => row.values[f]) }));
    const reducedTrain = project(train), reducedTest = project(test), m = discrete(reducedTrain, cv.selected), stats = experimentStats(m, reducedTrain, reducedTest);
    lines.push(`top ${count} features ${features.map(f => data.features[f]).join(' ')} rounds ${m.rounds.length} train_errors ${stats.trainErrors}/${train.length} test_errors ${stats.testErrors}/${test.length}`);
  }
  for (const q of params.noise) {
    const count = Math.floor(train.length * q / 100), generator = new Minstd(params.noiseSeed), permutation = train.map((_, i) => i);
    for (let i = 0; i < count; i++) { const other = i + generator.next() % (train.length - i); [permutation[i], permutation[other]] = [permutation[other], permutation[i]]; }
    const flipped = new Set(permutation.slice(0, count)), noisy = train.map((row, i) => ({ ...row, label: flipped.has(i) ? -row.label : row.label }));
    lines.push(`noise ${q} flipped ${count}`);
    for (const variant of params.variants) {
      const m = trainVariant(variant, noisy, params), stats = experimentStats(m, noisy, test), weights = m.rounds[m.rounds.length - 1].weights;
      let flippedWeight = 0;
      for (let i = 0; i < train.length; i++) if (flipped.has(i)) flippedWeight += weights[i];
      lines.push(`${variant} ${experimentFields(m, stats, train.length, test.length)} test_min ${stats.minimum}/${test.length} at ${stats.at} flipped_weight ${fixed(flippedWeight)}`);
    }
  }
  return lines;
}
function main(): void {
  const data = readDataset(), cv = crossValidation(data.train, data.params), models = analyzeModels(data, cv), multi = multiclassAnalysis(data);
  const files: Record<string, string[]> = { 'ensemble.txt': ensembleLines(data, models, cv), 'error_curve.csv': errorCurveLines(data, models, multi),
    'predictions.csv': predictionLines(data, models), 'roc.csv': rocLines(data, models), 'margins.txt': marginLines(data, models),
    'shapes.txt': shapeLines(data, models), 'samme.txt': sammeLines(data, multi), 'summary.txt': summaryLines(data, models, cv), 'experiments.txt': experimentLines(data, models, cv) };
  for (const [name, lines] of Object.entries(files)) writeLines(name, lines);
}
main();
