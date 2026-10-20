import { mkdirSync, writeFileSync } from 'node:fs';
import { readInputs, Minstd } from './dataset.ts';
import type { Image, Run, Settings } from './dataset.ts';
import { Network } from './network.ts';
import type { Forward } from './network.ts';
import { Optimizer, learningRate } from './optimizers.ts';
import {
  real,
  ratio,
  prediction,
  secondClass,
  confusion,
  perClass,
  levelMaps,
  imageRows,
} from './evaluation.ts';

interface Data {
  width: number;
  height: number;
  pixels: number;
  classes: number;
  allTrain: Image[];
  train: Image[];
  validation: Image[];
  test: Image[];
}
interface Scored extends Forward {
  predicted: number;
  correct: boolean;
  confidence: number;
}
interface Epoch {
  epoch: number;
  rate: number;
  magnitude: number;
  trainLoss: number;
  trainCorrect: number;
  validationLoss: number;
  validationCorrect: number;
  correct: boolean[];
  improved: boolean;
}
interface Best {
  theta: number[];
  epoch: number;
  loss: number;
  correct: number;
}
interface Bin {
  count: number;
  correct: number;
  totalConfidence: number;
  mean: number | null;
}
const indices = (count: number) => Array.from({ length: count }, (_, i) => i);
function evaluate(network: Network, theta: number[], images: Image[]) {
  const results: Scored[] = [];
  let totalLoss = 0;
  let correct = 0;
  for (const image of images) {
    const result = network.forward(theta, image);
    const predicted = prediction(result.scores);
    const matches = predicted === image.label;
    totalLoss += result.loss;
    if (matches) correct++;
    results.push({ ...result, predicted, correct: matches, confidence: result.scores[predicted] });
  }
  return { results, correct, loss: totalLoss / images.length };
}
function meanGradient(network: Network, theta: number[], images: Image[]) {
  const mean: number[] = Array(network.parameterCount).fill(0);
  for (const image of images) {
    const { gradient } = network.backward(theta, network.forward(theta, image));
    for (let p = 0; p < mean.length; p++) mean[p] += gradient[p];
  }
  return mean.map((v) => v / images.length);
}
function checkNetwork(network: Network, data: Data, settings: Settings) {
  const order = new Minstd(settings.seed).shuffle(indices(data.train.length));
  const batch = order
    .slice(0, Math.min(settings.batchSize, data.train.length))
    .map((i) => data.train[i]);
  const theta = network.initial.slice();
  const analytic = meanGradient(network, theta, batch);
  const counts = network.layers.map(() => ({ weights: 0, biases: 0 }));
  const h = 0.00001;
  let checked = 0;
  let passed = true;
  for (let p = 0; p < network.parameterCount; p += settings.stride) {
    const original = theta[p];
    theta[p] = original + h;
    const plus = evaluate(network, theta, batch).loss;
    theta[p] = original - h;
    const minus = evaluate(network, theta, batch).loss;
    theta[p] = original;
    const numerical = (plus - minus) / (2 * h);
    const error =
      Math.abs(analytic[p] - numerical) / Math.max(1, Math.abs(analytic[p]) + Math.abs(numerical));
    if (!(error < 0.000001)) passed = false;
    const l = network.layers.findIndex((layer) => p < layer.end);
    counts[l][p < network.layers[l].biasOffset ? 'weights' : 'biases']++;
    checked++;
  }
  const lines = [
    `network ${network.name}`,
    `parameters ${network.parameterCount}`,
    `batch ${batch.map((image) => image.id).join(' ')}`,
  ];
  counts.forEach((count, l) =>
    lines.push(`layer ${l + 1} weights ${count.weights} biases ${count.biases}`),
  );
  lines.push(`checked ${checked}`, `result ${passed ? 'PASS' : 'FAIL'}`);
  return lines;
}
function trainRun(run: Run, network: Network, data: Data, settings: Settings) {
  const theta = network.initial.slice();
  const generator = new Minstd(settings.seed);
  const optimizer = new Optimizer(run, network.parameterCount);
  const order = indices(data.train.length);
  const history: Epoch[] = [];
  let best: Best = { theta: theta.slice(), epoch: 0, loss: Infinity, correct: 0 };
  let wait = 0;
  let updates = 0;
  let stop = 'max_epochs';
  for (let epoch = 1; epoch <= settings.maxEpochs; epoch++) {
    const rate = learningRate(run, settings, epoch);
    generator.shuffle(order);
    let magnitude = 0;
    let batches = 0;
    for (let start = 0; start < order.length; start += settings.batchSize) {
      const batch = order.slice(start, start + settings.batchSize).map((i) => data.train[i]);
      const gradient = meanGradient(network, theta, batch);
      for (const p of network.weightIndices) gradient[p] += run.decay * theta[p];
      let squared = 0;
      for (const value of gradient) squared += value * value;
      magnitude += Math.sqrt(squared);
      optimizer.update(theta, gradient, rate);
      batches++;
      updates++;
    }
    const training = evaluate(network, theta, data.train);
    const validation = evaluate(network, theta, data.validation);
    const improved = epoch === 1 || validation.loss < best.loss;
    if (improved) {
      best = { theta: theta.slice(), epoch, loss: validation.loss, correct: validation.correct };
      wait = 0;
    } else wait++;
    history.push({
      epoch,
      rate,
      magnitude: magnitude / batches,
      trainLoss: training.loss,
      trainCorrect: training.correct,
      validationLoss: validation.loss,
      validationCorrect: validation.correct,
      correct: training.results.map((r) => r.correct),
      improved,
    });
    if (wait >= settings.patience) {
      stop = 'early';
      break;
    }
  }
  return { run, network, theta: best.theta, best, history, epochs: history.length, updates, stop };
}
type Trained = ReturnType<typeof trainRun>;
function forgetting(history: Epoch[], size: number) {
  let events = 0;
  let rows = 0;
  let neverLearned = 0;
  for (let i = 0; i < size; i++) {
    let forgotten = 0;
    let learned = false;
    for (let e = 0; e < history.length; e++) {
      if (history[e].correct[i]) learned = true;
      if (e > 0 && history[e - 1].correct[i] && !history[e].correct[i]) forgotten++;
    }
    events += forgotten;
    if (forgotten > 0) rows++;
    if (!learned) neverLearned++;
  }
  return { events, rows, neverLearned };
}
function weightStatistics(network: Network, theta: number[]) {
  const norms: number[] = [];
  const changes: number[] = [];
  for (const layer of network.layers) {
    let squared = 0;
    let changed = 0;
    for (let p = layer.offset; p < layer.biasOffset; p++) {
      squared += theta[p] * theta[p];
      const difference = theta[p] - network.initial[p];
      changed += difference * difference;
    }
    norms.push(Math.sqrt(squared));
    changes.push(Math.sqrt(changed));
  }
  return { norms, changes };
}
function noisyData(images: Image[], rate: number, seed: number) {
  const generator = new Minstd(seed);
  let flipped = 0;
  const changed = images.map((image) => {
    const vector = image.vector.map((pixel) => {
      const flip = generator.next() % 100 < rate;
      if (flip) flipped++;
      return flip ? 1 - pixel : pixel;
    });
    return { ...image, vector, pixels: vector.join('') };
  });
  return { rate, images: changed, flipped };
}
type Noise = ReturnType<typeof noisyData>;
function calibration(results: Scored[], size: number) {
  const bins: Bin[] = Array.from({ length: size }, () => ({
    count: 0,
    correct: 0,
    totalConfidence: 0,
    mean: null,
  }));
  for (const result of results) {
    const bin = bins[Math.min(size - 1, Math.floor(result.confidence * size))];
    bin.count++;
    if (result.correct) bin.correct++;
    bin.totalConfidence += result.confidence;
  }
  let ece = 0;
  for (const bin of bins) {
    if (bin.count > 0) {
      bin.mean = bin.totalConfidence / bin.count;
      ece += (bin.count / results.length) * Math.abs(bin.correct / bin.count - bin.mean);
    }
  }
  return { bins, ece };
}
function hiddenStatistics(network: Network, images: Image[], results: Scored[]) {
  return network.layers.slice(0, -1).map((layer, l) => {
    const sums: number[][] = Array.from({ length: network.classes }, () =>
      Array(layer.units).fill(0),
    );
    const counts: number[] = Array(network.classes).fill(0);
    const zeroCounts: number[] = Array(layer.units).fill(0);
    for (let i = 0; i < images.length; i++) {
      const label = images[i].label;
      counts[label]++;
      for (let j = 0; j < layer.units; j++) {
        const value = results[i].activations[l + 1][j];
        sums[label][j] += value;
        if (value === 0) zeroCounts[j]++;
      }
    }
    const means = sums.map((values, k) =>
      counts[k] === 0 ? null : values.map((value) => value / counts[k]),
    );
    const preferred: number[] = [];
    for (let j = 0; j < layer.units; j++) {
      let best = -1;
      let maximum = -Infinity;
      for (let k = 0; k < network.classes; k++) {
        const mean = means[k];
        if (mean !== null && (best < 0 || mean[j] > maximum)) {
          best = k;
          maximum = mean[j];
        }
      }
      preferred.push(best);
    }
    return { layer, means, preferred, zeroCounts };
  });
}
function evaluateRun(trained: Trained, data: Data, settings: Settings, noisy: Noise[]) {
  const { network, theta } = trained;
  const test = evaluate(network, theta, data.test);
  const matrix = confusion(data.test, test.results, network.classes);
  const confidenceSums = [0, 0];
  const misclassified: number[] = [];
  let topTwo = 0;
  test.results.forEach((result, i) => {
    if (result.correct || secondClass(result.scores, result.predicted) === data.test[i].label) {
      topTwo++;
    }
    confidenceSums[result.correct ? 0 : 1] += result.confidence;
    if (!result.correct) misclassified.push(i);
  });
  const sorted = network.weightIndices.toSorted(
    (a, b) => Math.abs(theta[a]) - Math.abs(theta[b]) || a - b,
  );
  const pruning = settings.prune.map((percent) => {
    const removed = Math.floor((percent * sorted.length) / 100);
    const pruned = theta.slice();
    for (let i = 0; i < removed; i++) pruned[sorted[i]] = 0;
    const result = evaluate(network, pruned, data.test);
    return { percent, removed, correct: result.correct, loss: result.loss };
  });
  const noise = noisy.map((group) => ({
    rate: group.rate,
    correct: evaluate(network, theta, group.images).correct,
  }));
  return {
    ...trained,
    test,
    matrix,
    topTwo,
    misclassified,
    pruning,
    noise,
    confidenceCorrect: test.correct === 0 ? null : confidenceSums[0] / test.correct,
    confidenceWrong: misclassified.length === 0 ? null : confidenceSums[1] / misclassified.length,
    forgetting: forgetting(trained.history, data.train.length),
    weights: weightStatistics(network, theta),
    calibration: calibration(test.results, settings.bins),
    hidden: hiddenStatistics(network, data.test, test.results),
  };
}
type Evaluated = ReturnType<typeof evaluateRun>;
function classCounts(images: Image[], size: number) {
  const counts: number[] = Array(size).fill(0);
  for (const image of images) counts[image.label]++;
  return counts;
}
function dataReport(data: Data) {
  const training = classCounts(data.train, data.classes);
  const validation = classCounts(data.validation, data.classes);
  const test = classCounts(data.test, data.classes);
  const pixels: number[][] = Array.from({ length: data.classes }, () => Array(data.pixels).fill(0));
  const ink: number[] = Array(data.classes).fill(0);
  for (const image of data.train) {
    for (let i = 0; i < data.pixels; i++) {
      pixels[image.label][i] += image.vector[i];
      ink[image.label] += image.vector[i];
    }
  }
  const lines = [
    'data',
    `train ${data.train.length} validation ${data.validation.length} test ${data.test.length} pixels ${data.pixels}`,
  ];
  for (let k = 0; k < data.classes; k++) {
    lines.push(
      `class ${k} train ${training[k]} validation ${validation[k]} test ${test[k]} ink ${ratio(ink[k], training[k])}`,
    );
  }
  const maps = pixels.map((values, k) =>
    values.map((value) =>
      training[k] === 0 ? 0 : Math.min(9, Math.floor((10 * value) / training[k])),
    ),
  );
  lines.push(
    `mean_images ${indices(data.classes).join(' ')}`,
    ...levelMaps(maps, data.width, data.height),
  );
  return lines;
}
function learningCurve(result: Evaluated) {
  let maximum = 0;
  for (const e of result.history) maximum = Math.max(maximum, e.trainLoss, e.validationLoss);
  return result.history.map((e) => {
    const row: string[] = Array(40).fill(' ');
    const tr = Math.floor((39 * e.trainLoss) / maximum + 0.5);
    const va = Math.floor((39 * e.validationLoss) / maximum + 0.5);
    row[tr] = 't';
    row[va] = tr === va ? '*' : 'v';
    return `${String(e.epoch).padStart(2)} |${row.join('')}|${e.epoch === result.best.epoch ? ' best' : ''}`;
  });
}
function runReport(result: Evaluated, data: Data) {
  const { run, network, best, test } = result;
  const total = data.test.length;
  const lines = [
    `run ${run.name} network ${network.name} optimizer ${run.optimizer}`,
    `epochs ${result.epochs} best_epoch ${best.epoch} stop ${result.stop} updates ${result.updates}`,
    `best_val_loss ${real(best.loss, 6)} best_val_acc ${ratio(best.correct, data.validation.length)} correct ${best.correct}/${data.validation.length}`,
    `test_loss ${real(test.loss, 6)} test_acc ${ratio(test.correct, total)} correct ${test.correct}/${total}`,
    `top2_acc ${ratio(result.topTwo, total)} correct ${result.topTwo}/${total}`,
    `confidence correct ${real(result.confidenceCorrect)} wrong ${real(result.confidenceWrong)}`,
    `forgetting events ${result.forgetting.events} rows ${result.forgetting.rows} never_learned ${result.forgetting.neverLearned}`,
    `weight_norms ${result.weights.norms.map((v) => real(v)).join(' ')}`,
    `weight_changes ${result.weights.changes.map((v) => real(v)).join(' ')}`,
    'curve',
    ...learningCurve(result),
    'confusion',
  ];
  result.matrix.forEach((row, k) => lines.push(`${k}: ${row.join(' ')}`));
  perClass(result.matrix).forEach((v, k) =>
    lines.push(
      `class ${k} support ${v.support} predicted ${v.predicted} precision ${v.precision} recall ${v.recall} f1 ${v.f1}`,
    ),
  );
  lines.push('calibration');
  result.calibration.bins.forEach((bin, i, bins) =>
    lines.push(
      `bin ${i + 1} ${real(i / bins.length, 2)} ${real((i + 1) / bins.length, 2)} count ${bin.count} accuracy ${ratio(bin.correct, bin.count)} confidence ${real(bin.mean)}`,
    ),
  );
  lines.push(`ece ${real(result.calibration.ece)}`);
  result.hidden.forEach((hidden, l) => {
    lines.push(`hidden ${l + 1} ${hidden.layer.activation} units ${hidden.layer.units}`);
    hidden.means.forEach((mean, k) =>
      lines.push(`class ${k} mean ${mean === null ? '-' : mean.map((v) => real(v)).join(' ')}`),
    );
    lines.push(`preferred ${hidden.preferred.join(' ')}`);
    if (hidden.layer.activation === 'RELU') {
      lines.push(`zero_counts ${hidden.zeroCounts.join(' ')}`);
    }
  });
  lines.push('pruning');
  for (const prune of result.pruning) {
    lines.push(
      `prune ${prune.percent} removed ${prune.removed} correct ${prune.correct} test_acc ${ratio(prune.correct, total)} test_loss ${real(prune.loss, 6)}`,
    );
  }
  lines.push('noise');
  for (const noise of result.noise) {
    lines.push(
      `noise ${noise.rate} correct ${noise.correct} test_acc ${ratio(noise.correct, total)}`,
    );
  }
  lines.push(
    `misclassified ${result.misclassified.length}` +
      result.misclassified.map((i) => ` ${data.test[i].id}`).join(''),
  );
  return lines;
}
function majorityVote(runs: Evaluated[], ranked: Evaluated[], data: Data) {
  const predictions: number[] = [];
  let correct = 0;
  let fixed = 0;
  let broken = 0;
  for (let i = 0; i < data.test.length; i++) {
    const votes: number[] = Array(data.classes).fill(0);
    for (const run of runs) votes[run.test.results[i].predicted]++;
    const maximum = Math.max(...votes);
    const chosen = ranked.find((run) => votes[run.test.results[i].predicted] === maximum)!.test
      .results[i].predicted;
    predictions.push(chosen);
    const matches = chosen === data.test[i].label;
    const topCorrect = ranked[0].test.results[i].correct;
    if (matches) correct++;
    if (matches && !topCorrect) fixed++;
    if (!matches && topCorrect) broken++;
  }
  return { predictions, correct, fixed, broken };
}
function softEnsemble(runs: Evaluated[], data: Data) {
  const selected = runs.filter((run) => run.network.outputType === 'SOFTMAX');
  if (!selected.length) return null;
  let correct = 0;
  for (let i = 0; i < data.test.length; i++) {
    const scores: number[] = Array(data.classes).fill(0);
    for (const run of selected) {
      for (let k = 0; k < data.classes; k++) scores[k] += run.test.results[i].scores[k];
    }
    if (prediction(scores.map((s) => s / selected.length)) === data.test[i].label) correct++;
  }
  return { runs: selected.length, correct };
}
function saliency(top: Evaluated, data: Data) {
  const sums: number[][] = Array.from({ length: data.classes }, () => Array(data.pixels).fill(0));
  const counts: number[] = Array(data.classes).fill(0);
  for (let i = 0; i < data.test.length; i++) {
    const label = data.test[i].label;
    const { inputGradient } = top.network.backward(top.theta, top.test.results[i]);
    counts[label]++;
    for (let p = 0; p < data.pixels; p++) sums[label][p] += Math.abs(inputGradient[p]);
  }
  return sums.map((values, k) => {
    if (!counts[k]) return Array<number>(data.pixels).fill(0);
    const means = values.map((v) => v / counts[k]);
    const maximum = Math.max(...means);
    return means.map((v) => (maximum === 0 ? 0 : Math.min(9, Math.floor((10 * v) / maximum))));
  });
}
function nearestImage(image: Image, candidates: Image[]) {
  let nearest = candidates[0];
  let distance = Infinity;
  for (const candidate of candidates) {
    let differences = 0;
    for (let p = 0; p < image.pixels.length; p++) {
      if (image.pixels[p] !== candidate.pixels[p]) differences++;
    }
    if (differences < distance) {
      nearest = candidate;
      distance = differences;
    }
  }
  return { image: nearest, distance };
}
function comparisonReport(runs: Evaluated[], data: Data, noisy: Noise[]) {
  const ranked = runs.toSorted(
    (a, b) =>
      b.test.correct - a.test.correct || a.best.loss - b.best.loss || a.run.order - b.run.order,
  );
  const top = ranked[0];
  const total = data.test.length;
  const ensemble = majorityVote(runs, ranked, data);
  const soft = softEnsemble(runs, data);
  const lines = ['comparison'];
  ranked.forEach((run, i) =>
    lines.push(
      `rank ${i + 1} ${run.run.name} correct ${run.test.correct} test_acc ${ratio(run.test.correct, total)} best_val_loss ${real(run.best.loss, 6)} test_loss ${real(run.test.loss, 6)} best_epoch ${run.best.epoch} epochs ${run.epochs} updates ${run.updates}`,
    ),
  );
  lines.push('agreement');
  for (const left of runs) {
    const agreements = runs.map((right) => {
      let count = 0;
      for (let i = 0; i < total; i++) {
        if (left.test.results[i].predicted === right.test.results[i].predicted) count++;
      }
      return count;
    });
    lines.push(`${left.run.name} ${agreements.join(' ')}`);
  }
  lines.push(`mcnemar ${top.run.name}`);
  for (const other of ranked.slice(1)) {
    let b = 0;
    let c = 0;
    for (let i = 0; i < total; i++) {
      if (top.test.results[i].correct && !other.test.results[i].correct) b++;
      if (!top.test.results[i].correct && other.test.results[i].correct) c++;
    }
    const difference = Math.max(Math.abs(b - c) - 1, 0);
    const numerator = difference * difference;
    const denominator = b + c;
    const significant = numerator * 1000 > 3841 * denominator;
    lines.push(
      `vs ${other.run.name} b ${b} c ${c} chi2 ${denominator === 0 ? '0.0000' : ratio(numerator, denominator)} significant ${significant ? 'yes' : 'no'}`,
    );
  }
  lines.push(
    `ensemble correct ${ensemble.correct}/${total} test_acc ${ratio(ensemble.correct, total)} fixed ${ensemble.fixed} broken ${ensemble.broken}`,
    soft === null
      ? 'soft_ensemble none'
      : `soft_ensemble runs ${soft.runs} correct ${soft.correct}/${total} test_acc ${ratio(soft.correct, total)}`,
  );
  for (const group of noisy) lines.push(`noise ${group.rate} flipped ${group.flipped}`);
  const pairs: { y: number; p: number; count: number }[] = [];
  for (let y = 0; y < data.classes; y++) {
    for (let p = 0; p < data.classes; p++) {
      if (y === p) continue;
      let count = 0;
      for (const run of runs) count += run.matrix[y][p];
      if (count > 0) pairs.push({ y, p, count });
    }
  }
  pairs.sort((a, b) => b.count - a.count || a.y - b.y || a.p - b.p);
  lines.push('confused_pairs');
  for (const pair of pairs.slice(0, 5)) lines.push(`${pair.y} as ${pair.p} count ${pair.count}`);
  lines.push(
    '',
    `saliency ${top.run.name}`,
    `classes ${indices(data.classes).join(' ')}`,
    ...levelMaps(saliency(top, data), data.width, data.height),
  );
  const training = evaluate(top.network, top.theta, data.train);
  const hardest = training.results
    .map((result, i) => ({ result, image: data.train[i], order: i }))
    .sort((a, b) => b.result.loss - a.result.loss || a.order - b.order)
    .slice(0, 5);
  lines.push('', `hardest_training_examples ${top.run.name}`);
  for (const item of hardest) {
    lines.push(
      `${item.image.id} label ${item.image.label} predicted ${item.result.predicted} loss ${real(item.result.loss, 6)}`,
    );
  }
  lines.push('', `misclassified_examples ${top.run.name}`);
  for (const i of top.misclassified) {
    const image = data.test[i];
    const result = top.test.results[i];
    const nearest = nearestImage(image, data.allTrain);
    lines.push(
      `${image.id} label ${image.label} predicted ${result.predicted} confidence ${real(result.confidence)} true_score ${real(result.scores[image.label])} runs ${runs.map((run) => run.test.results[i].predicted).join(' ')} ensemble ${ensemble.predictions[i]}`,
      `nearest ${nearest.image.id} label ${nearest.image.label} distance ${nearest.distance}`,
      ...imageRows(image, data.width, data.height),
    );
  }
  return lines;
}
function trainingLog(runs: Evaluated[], data: Data) {
  const lines = ['run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved'];
  for (const run of runs) {
    for (const e of run.history) {
      lines.push(
        [
          run.run.name,
          e.epoch,
          real(e.rate, 6),
          real(e.magnitude),
          real(e.trainLoss, 6),
          ratio(e.trainCorrect, data.train.length),
          real(e.validationLoss, 6),
          ratio(e.validationCorrect, data.validation.length),
          e.improved ? 1 : 0,
        ].join(','),
      );
    }
  }
  return lines;
}
function finalWeightLines(runs: Evaluated[]) {
  const lines: string[] = [];
  for (const run of runs) {
    if (lines.length) lines.push('');
    lines.push(`RUN ${run.run.name} NETWORK ${run.network.name} EPOCH ${run.best.epoch}`);
    run.network.layers.forEach((layer, l) => {
      lines.push(`LAYER ${l + 1} ${layer.units} ${layer.inputs}`);
      for (let j = 0; j < layer.units; j++) {
        const offset = layer.offset + j * layer.inputs;
        lines.push(
          'W ' +
            run.theta
              .slice(offset, offset + layer.inputs)
              .map((v) => real(v))
              .join(' '),
        );
      }
      lines.push(
        'B ' +
          run.theta
            .slice(layer.biasOffset, layer.end)
            .map((v) => real(v))
            .join(' '),
      );
    });
  }
  return lines;
}
function main() {
  const input = readInputs();
  const networks = input.networks.map(
    (definition) =>
      new Network(definition, input.width * input.height, input.weights.get(definition.name)!),
  );
  const byName = new Map(networks.map((network) => [network.name, network]));
  const validationSize = Math.floor(input.train.length / 5);
  const trainingSize = input.train.length - validationSize;
  const data: Data = {
    width: input.width,
    height: input.height,
    pixels: input.width * input.height,
    classes: networks[0].classes,
    allTrain: input.train,
    train: input.train.slice(0, trainingSize),
    validation: input.train.slice(trainingSize),
    test: input.test,
  };
  const checkLines: string[] = [];
  for (const network of networks) {
    if (checkLines.length) checkLines.push('');
    checkLines.push(...checkNetwork(network, data, input.settings));
  }
  const noisy = input.settings.noise.map((rate) => noisyData(data.test, rate, input.settings.seed));
  const runs = input.settings.runs.map((run) =>
    evaluateRun(
      trainRun(run, byName.get(run.network)!, data, input.settings),
      data,
      input.settings,
      noisy,
    ),
  );
  const predictions = ['run,id,label,predicted,confidence'];
  const report = dataReport(data);
  for (const run of runs) {
    run.test.results.forEach((r, i) =>
      predictions.push(
        `${run.run.name},${data.test[i].id},${data.test[i].label},${r.predicted},${real(r.confidence)}`,
      ),
    );
    report.push('', ...runReport(run, data));
  }
  report.push('', ...comparisonReport(runs, data, noisy));
  mkdirSync('output', { recursive: true });
  const outputs: [string, string[]][] = [
    ['gradient_check.txt', checkLines],
    ['training_log.csv', trainingLog(runs, data)],
    ['final_weights.txt', finalWeightLines(runs)],
    ['predictions.csv', predictions],
    ['evaluation.txt', report],
  ];
  for (const [file, lines] of outputs) {
    writeFileSync(`output/${file}`, lines.join('\n') + '\n', 'ascii');
  }
}
main();
