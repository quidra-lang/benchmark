import {
  readDataset,
  type Dataset,
  type Model,
  type Row,
  type Settings,
  type TrainingRow,
} from './dataset.ts';
import { fitScaling } from './scaling.ts';
import { compareText, vote, type Prediction } from './neighbors.ts';
import { Predictor, regression, stratifiedSplit, type Regression } from './validation.ts';
import { fractionMetric, ratio, real, rounded, writeReport } from './report.ts';

type Predictions = Map<string, Prediction>;
interface Result {
  model: Model;
  predictions: Predictions;
  correct: number;
  rmse: number;
  statistics: Regression;
}
interface CrossValidation {
  folds: TrainingRow[][];
  results: Result[];
}
interface Selection {
  classifier: Result;
  regressor: Result;
  accuracy: Result[];
  rmse: Result[];
}
interface ItemSelection extends Selection {
  value: string | number;
}
interface TestPredictions {
  predictor: Predictor;
  classification: Predictions;
  estimates: Predictions;
}
const modelText = (m: Model) =>
  `k=${m.k} metric=${m.metric} weighting=${m.weighting} scaling=${m.scaling}`;
const orderedRows = (rows: TrainingRow[]) => [...rows].sort((a, b) => compareText(a.id, b.id));
const correctCount = (rows: Row[], predictions: Predictions) =>
  rows.filter((row) => predictions.get(row.id)!.label === row.label).length;
const regressionFor = (rows: Row[], predictions: Predictions) =>
  regression(
    rows.map((row) => ({ target: row.target!, estimate: predictions.get(row.id)!.estimate })),
  );
const flattenParts = (parts: string[][]) =>
  parts.flatMap((part, i) => (i === 0 ? part : ['', ...part]));
function buildGrid(settings: Settings): Model[] {
  const models: Model[] = [];
  for (const k of settings.ks) {
    for (const metric of settings.metrics) {
      for (const weighting of settings.weightings) {
        for (const scaling of settings.scalings) {
          models.push({ k, metric, weighting, scaling, order: models.length });
        }
      }
    }
  }
  return models;
}
function summarize(model: Model, predictions: Predictions, rows: TrainingRow[]): Result {
  const statistics = regressionFor(rows, predictions);
  return {
    model,
    predictions,
    statistics,
    rmse: statistics.rmse!,
    correct: correctCount(rows, predictions),
  };
}
function crossValidate(
  rows: TrainingRow[],
  models: Model[],
  count: number,
  features?: number[],
): CrossValidation {
  const folds = stratifiedSplit(rows, count);
  const predictions = models.map(() => new Map<string, Prediction>());
  for (const fold of folds) {
    const excluded = new Set(fold.map((row) => row.id));
    const predictor = new Predictor(
      rows.filter((row) => !excluded.has(row.id)),
      features,
    );
    for (const row of fold) {
      for (let i = 0; i < models.length; i++) {
        predictions[i].set(row.id, predictor.predict(row, models[i]));
      }
    }
  }
  return { folds, results: models.map((model, i) => summarize(model, predictions[i], rows)) };
}
function selectModels(results: Result[]): Selection {
  const accuracy = [...results].sort(
    (a, b) => b.correct - a.correct || a.model.order - b.model.order,
  );
  const rmse = [...results].sort(
    (a, b) => rounded(a.rmse) - rounded(b.rmse) || a.model.order - b.model.order,
  );
  return { classifier: accuracy[0], regressor: rmse[0], accuracy, rmse };
}
function labelCounts(rows: Row[], labels: string[]): string {
  return labels
    .map((label) => `${label} ${rows.filter((row) => row.label === label).length}`)
    .join(' ');
}
function evaluationLines(rows: Row[], predictions: Predictions, labels: string[]): string[] {
  const positions = new Map(labels.map((label, i) => [label, i]));
  const matrix = labels.map(() => labels.map(() => 0));
  for (const row of rows) {
    matrix[positions.get(row.label!)!][positions.get(predictions.get(row.id)!.label)!]++;
  }
  const lines = [`true\\predicted ${labels.join(' ')}`];
  for (let i = 0; i < labels.length; i++) lines.push(`${labels[i]} ${matrix[i].join(' ')}`);
  const totals = [0, 0, 0];
  const counts = [0, 0, 0];
  for (let i = 0; i < labels.length; i++) {
    let predicted = 0;
    let actual = 0;
    for (let j = 0; j < labels.length; j++) {
      predicted += matrix[j][i];
      actual += matrix[i][j];
    }
    const tp = matrix[i][i];
    const metrics: [number, number][] = [
      [tp, predicted],
      [tp, actual],
      [2 * tp, predicted + actual],
    ];
    for (let j = 0; j < metrics.length; j++) {
      const [a, b] = metrics[j];
      if (b !== 0) {
        totals[j] += a / b;
        counts[j]++;
      }
    }
    lines.push(
      `class ${labels[i]} precision ${fractionMetric(...metrics[0])} recall ${fractionMetric(...metrics[1])}` +
        ` f1 ${fractionMetric(...metrics[2])} support ${actual}`,
    );
  }
  const macro = totals.map((total, i) => real(counts[i] === 0 ? null : total / counts[i]));
  lines.push(`macro precision ${macro[0]} recall ${macro[1]} f1 ${macro[2]}`);
  return lines;
}
function reliabilityLines(rows: Row[], predictions: Predictions, boundaries: number[]): string[] {
  const bins = [0, ...boundaries].map((lower) => ({ lower, count: 0, correct: 0, total: 0 }));
  for (const row of rows) {
    const p = predictions.get(row.id)!;
    let i = 0;
    while (i < boundaries.length && p.share >= boundaries[i]) i++;
    const bin = bins[i];
    bin.count++;
    if (p.label === row.label) bin.correct++;
    bin.total += p.share;
  }
  return bins.map(
    (b) =>
      `bin ${real(b.lower, 2)} rows ${b.count}` +
      (b.count === 0
        ? ''
        : ` correct ${ratio(b.correct, b.count)} share ${real(b.total / b.count)}`),
  );
}
function bestPerItem(
  results: Result[],
  settings: Settings,
): Map<keyof Pick<Model, 'k' | 'metric' | 'weighting' | 'scaling'>, ItemSelection[]> {
  const items: [
    keyof Pick<Model, 'k' | 'metric' | 'weighting' | 'scaling'>,
    (number | string)[],
  ][] = [
    ['k', settings.ks],
    ['metric', settings.metrics],
    ['weighting', settings.weightings],
    ['scaling', settings.scalings],
  ];
  return new Map(
    items.map(([item, values]) => [
      item,
      values.map((value) => ({
        value,
        ...selectModels(results.filter((result) => result.model[item] === value)),
      })),
    ]),
  );
}
function mcnemarLines(
  rows: TrainingRow[],
  classifier: Result,
  comparisons: ItemSelection[],
): string[] {
  const lines = ['mcnemar'];
  for (const comparison of comparisons) {
    let b = 0;
    let c = 0;
    for (const row of rows) {
      const first = classifier.predictions.get(row.id)!.label === row.label;
      const second = comparison.classifier.predictions.get(row.id)!.label === row.label;
      if (first && !second) b++;
      if (second && !first) c++;
    }
    const delta = Math.max(0, Math.abs(b - c) - 1);
    const u = delta * delta;
    const denominator = b + c;
    lines.push(
      `${modelText(comparison.classifier.model)} b ${b} c ${c} statistic ` +
        `${denominator === 0 ? '0/1 0.0000' : fractionMetric(u, denominator)} significant ${1000 * u > 3841 * denominator ? 'yes' : 'no'}`,
    );
  }
  return lines;
}
function leaveOneOutParts(
  rows: TrainingRow[],
  labels: string[],
  classifier: Result,
  regressor: Result,
  settings: Settings,
): string[][] {
  const models = settings.ks.map((k) => ({ ...classifier.model, k }));
  const all = [...models, regressor.model];
  const predictions = all.map(() => new Map<string, Prediction>());
  for (const row of rows) {
    const predictor = new Predictor(rows.filter((other) => other.id !== row.id));
    for (let i = 0; i < all.length; i++) predictions[i].set(row.id, predictor.predict(row, all[i]));
  }
  const results = all.map((model, i) => summarize(model, predictions[i], rows));
  const cls = results.find((result) => result.model.k === classifier.model.k)!;
  const reg = results[results.length - 1];
  const errors = orderedRows(
    rows.filter((row) => cls.predictions.get(row.id)!.label !== row.label),
  );
  const first = [
    `leave_one_out classifier ${modelText(cls.model)}`,
    `errors ${ratio(errors.length, rows.length)}`,
    `class_errors ${labelCounts(errors, labels)}`,
  ];
  for (const row of errors) {
    const p = cls.predictions.get(row.id)!;
    first.push(`${row.id} true ${row.label} predicted ${p.label} share ${real(p.share)}`);
  }
  const residuals = rows
    .map((row) => {
      const estimate = reg.predictions.get(row.id)!.estimate;
      return { row, estimate, residual: estimate - row.target };
    })
    .sort(
      (a, b) =>
        rounded(Math.abs(b.residual)) - rounded(Math.abs(a.residual)) ||
        compareText(a.row.id, b.row.id),
    );
  const second = [
    `leave_one_out regressor ${modelText(reg.model)}`,
    `rmse ${real(reg.rmse)} mae ${real(reg.statistics.mae)}`,
    `largest ${settings.top} residuals`,
  ];
  for (const item of residuals.slice(0, settings.top)) {
    second.push(
      `${item.row.id} target ${real(item.row.target)} estimate ${real(item.estimate)} residual ${real(item.residual)}`,
    );
  }
  const third = [
    `leave_one_out by k metric=${classifier.model.metric} weighting=${classifier.model.weighting} scaling=${classifier.model.scaling}`,
  ];
  for (const r of results.slice(0, -1)) {
    third.push(`k=${r.model.k} correct ${ratio(r.correct, rows.length)} rmse ${real(r.rmse)}`);
  }
  return [first, second, third];
}
function nestedValidation(
  rows: TrainingRow[],
  folds: TrainingRow[][],
  models: Model[],
  count: number,
): string[] {
  const lines = [`nested_cross_validation folds ${count}`];
  const predictions: Predictions = new Map();
  let totalCorrect = 0;
  for (let i = 0; i < folds.length; i++) {
    const fold = folds[i];
    const excluded = new Set(fold.map((row) => row.id));
    const training = rows.filter((row) => !excluded.has(row.id));
    const inner = selectModels(crossValidate(training, models, count).results);
    const predictor = new Predictor(training);
    let correct = 0;
    for (const row of fold) {
      if (predictor.predict(row, inner.classifier.model).label === row.label) correct++;
      predictions.set(row.id, predictor.predict(row, inner.regressor.model));
    }
    totalCorrect += correct;
    lines.push(
      `fold ${i + 1} classifier ${modelText(inner.classifier.model)} inner ${real(inner.classifier.correct / training.length)} outer ${ratio(correct, fold.length)}`,
      `fold ${i + 1} regressor ${modelText(inner.regressor.model)} inner ${real(inner.regressor.rmse)} outer ${real(regressionFor(fold, predictions).rmse)}`,
    );
  }
  lines.push(
    `nested accuracy ${ratio(totalCorrect, rows.length)} rmse ${real(regressionFor(rows, predictions).rmse)}`,
  );
  return lines;
}
function featureSelection(data: Dataset, classifier: Result): string[] {
  const { train, features, settings, test } = data;
  const n = train.length;
  let current = features.map((_, i) => i);
  let selected = current;
  let best = classifier.correct;
  let step = 0;
  const names = (indices: number[]) => indices.map((i) => features[i]).join(' ');
  const lines = [
    `feature_selection ${modelText(classifier.model)}`,
    `start features ${names(current)} correct ${ratio(best, n)}`,
  ];
  while (current.length >= 3) {
    const candidates = current.map((feature) => {
      const used = current.filter((i) => i !== feature);
      return {
        feature,
        used,
        correct: crossValidate(train, [classifier.model], settings.folds, used).results[0].correct,
      };
    });
    let chosen = candidates[0];
    for (const candidate of candidates) if (candidate.correct > chosen.correct) chosen = candidate;
    current = chosen.used;
    if (chosen.correct >= best) {
      selected = current;
      best = chosen.correct;
    }
    lines.push(
      `step ${++step} remove ${features[chosen.feature]} correct ${ratio(chosen.correct, n)} candidates ` +
        candidates
          .map((candidate) => `${features[candidate.feature]} ${candidate.correct}`)
          .join(' '),
    );
  }
  const labelled = test.filter((row) => row.label !== null);
  const predictor = new Predictor(train, selected);
  const correct = labelled.filter(
    (row) => predictor.predict(row, classifier.model).label === row.label,
  ).length;
  lines.push(
    `selected features ${names(selected)} correct ${ratio(best, n)}`,
    `selected test ${ratio(correct, labelled.length)}`,
  );
  return lines;
}
function predictTest(data: Dataset, classifier: Result, regressor: Result): TestPredictions {
  const predictor = new Predictor(data.train);
  const classification: Predictions = new Map();
  const estimates: Predictions = new Map();
  for (const row of data.test) {
    classification.set(row.id, predictor.predict(row, classifier.model));
    estimates.set(row.id, predictor.predict(row, regressor.model));
  }
  return { predictor, classification, estimates };
}
function learningLines(data: Dataset, classifier: Result, regressor: Result): string[] {
  const lines = ['n,train_size,correct,accuracy,rmse'];
  const labelled = data.test.filter((row) => row.label !== null);
  const targets = data.test.filter((row) => row.target !== null);
  for (const count of data.settings.curve) {
    const counts = new Map<string, number>();
    const training = data.train.filter((row) => {
      const old = counts.get(row.label) ?? 0;
      if (old >= count) return false;
      counts.set(row.label, old + 1);
      return true;
    });
    const predictor = new Predictor(training);
    const estimates: Predictions = new Map();
    const correct = labelled.filter(
      (row) => predictor.predict(row, classifier.model).label === row.label,
    ).length;
    for (const row of targets) estimates.set(row.id, predictor.predict(row, regressor.model));
    lines.push(
      [
        count,
        training.length,
        correct,
        real(correct / labelled.length),
        real(regressionFor(targets, estimates).rmse),
      ].join(','),
    );
  }
  return lines;
}
function prototypeParts(
  data: Dataset,
  labels: string[],
  classifier: Result,
  predictions: TestPredictions,
): string[][] {
  const { train, test, settings } = data;
  const model = classifier.model;
  const original = orderedRows(train);
  const space = predictions.predictor;
  const labelled = test.filter((row) => row.label !== null);
  const order = (row: Row, allowed: Set<string>, exclude?: string) =>
    space.order(row, model).filter((item) => allowed.has(item.row.id) && item.row.id !== exclude);
  const parts = [[`space ${modelText(model)}`]];
  const editing = [`editing k=${settings.editK}`];
  let edited = original;
  let pass = 0;
  while (true) {
    const allowed = new Set(edited.map((row) => row.id));
    const removed: { row: TrainingRow; prediction: Prediction }[] = [];
    for (const row of edited) {
      const prediction = vote(order(row, allowed, row.id), settings.editK, model.weighting);
      if (prediction.label !== row.label) removed.push({ row, prediction });
    }
    editing.push(`pass ${++pass} removed ${removed.length}`);
    for (const { row, prediction: p } of removed) {
      editing.push(`  ${row.id} true ${row.label} predicted ${p.label} share ${real(p.share)}`);
    }
    if (!removed.length) break;
    const excluded = new Set(removed.map((item) => item.row.id));
    edited = edited.filter((row) => !excluded.has(row.id));
  }
  editing.push(`edited size ${edited.length} removed ${train.length - edited.length}`);
  parts.push(editing);
  function condense(rows: TrainingRow[]): { rows: TrainingRow[]; scans: number } {
    const stored = new Set([rows[0].id]);
    let scans = 0;
    while (true) {
      let added = 0;
      for (const row of rows) {
        if (!stored.has(row.id) && order(row, stored)[0].row.label !== row.label) {
          stored.add(row.id);
          added++;
        }
      }
      scans++;
      if (!added) return { rows: rows.filter((row) => stored.has(row.id)), scans };
    }
  }
  const condensed = condense(original);
  const editedCondensed = condense(edited);
  parts.push([
    `condensing original scans ${condensed.scans} size ${condensed.rows.length}`,
    `condensing edited scans ${editedCondensed.scans} size ${editedCondensed.rows.length}`,
  ]);
  const sets: [string, TrainingRow[]][] = [
    ['original', original],
    ['edited', edited],
    ['condensed', condensed.rows],
    ['edited_condensed', editedCondensed.rows],
  ];
  const summaries: string[] = [];
  for (const [name, rows] of sets) {
    const allowed = new Set(rows.map((row) => row.id));
    let knn = 0;
    let nearest = 0;
    for (const row of labelled) {
      const neighbors = order(row, allowed);
      if (vote(neighbors, model.k, model.weighting).label === row.label) knn++;
      if (neighbors[0].row.label === row.label) nearest++;
    }
    summaries.push(
      `set ${name} size ${rows.length} ${labelCounts(rows, labels)} knn ${ratio(knn, labelled.length)} 1nn ${ratio(nearest, labelled.length)}`,
    );
  }
  parts.push(summaries);
  for (const [name, rows] of sets.slice(2)) {
    const lines = [`prototypes ${name}`];
    for (let i = 0; i < rows.length; i += 10) {
      lines.push(
        rows
          .slice(i, i + 10)
          .map((row) => row.id)
          .join(' '),
      );
    }
    parts.push(lines);
  }
  const borders = ['borders'];
  let total = 0;
  for (const label of labels) {
    const rows = original.filter((row) => row.label === label);
    let border = 0;
    let same = 0;
    let other = 0;
    for (const row of rows) {
      const neighbors = space.order(row, model).filter((item) => item.row.id !== row.id);
      if (neighbors[0].row.label !== label) border++;
      same += neighbors.find((item) => item.row.label === label)!.distance;
      other += neighbors.find((item) => item.row.label !== label)!.distance;
    }
    total += border;
    borders.push(
      `class ${label} size ${rows.length} border ${border} same ${real(same / rows.length)} other ${real(other / rows.length)}`,
    );
  }
  borders.push(`border total ${ratio(total, train.length)}`);
  parts.push(borders);
  const counts = new Map(train.map((row) => [row.id, 0]));
  for (const row of test) {
    for (const neighbor of predictions.classification.get(row.id)!.neighbors) {
      counts.set(neighbor.row.id, counts.get(neighbor.row.id)! + 1);
    }
  }
  const ranked = [...train].sort(
    (a, b) => counts.get(b.id)! - counts.get(a.id)! || compareText(a.id, b.id),
  );
  const hubs = [`hubs k=${model.k} queries ${test.length}`];
  for (const row of ranked.slice(0, settings.top)) {
    hubs.push(`${row.id} ${row.label} ${counts.get(row.id)}`);
  }
  hubs.push(`anti_hubs ${train.filter((row) => counts.get(row.id) === 0).length}`);
  parts.push(hubs);
  return parts;
}
function selectionParts(
  data: Dataset,
  labels: string[],
  cross: CrossValidation,
  selected: Selection,
  perItem: ReturnType<typeof bestPerItem>,
): string[][] {
  const { train, test, features, settings } = data;
  const n = train.length;
  const labelled = test.filter((row) => row.label !== null);
  const targets = test.filter((row) => row.target !== null);
  const parts = [
    [
      `data train ${n} test ${test.length} labelled ${labelled.length} targets ${targets.length} features ${features.length} classes ${labels.length}`,
      `classes ${labelCounts(train, labels)}`,
    ],
  ];
  for (const method of settings.scalings) {
    const scaling = fitScaling(train, method);
    parts.push([
      `scaling ${method}`,
      ...features.map(
        (name, i) =>
          `${name} center ${real(scaling.centers[i], 6)} scale ${real(scaling.scales[i], 6)}`,
      ),
    ]);
  }
  parts.push([
    `folds ${settings.folds}`,
    ...cross.folds.map(
      (fold, i) => `fold ${i + 1} size ${fold.length} ${labelCounts(fold, labels)}`,
    ),
  ]);
  const { classifier: c, regressor: r } = selected;
  parts.push([
    `grid ${cross.results.length}`,
    `best_classifier ${modelText(c.model)} correct ${ratio(c.correct, n)} rmse ${real(c.rmse)}`,
    `best_regressor ${modelText(r.model)} rmse ${real(r.rmse)} correct ${ratio(r.correct, n)}`,
  ]);
  parts.push([
    `top ${settings.top} by accuracy`,
    ...selected.accuracy
      .slice(0, settings.top)
      .map(
        (x, i) =>
          `${i + 1} ${modelText(x.model)} correct ${ratio(x.correct, n)} rmse ${real(x.rmse)}`,
      ),
  ]);
  parts.push([
    `top ${settings.top} by rmse`,
    ...selected.rmse
      .slice(0, settings.top)
      .map(
        (x, i) =>
          `${i + 1} ${modelText(x.model)} rmse ${real(x.rmse)} correct ${ratio(x.correct, n)}`,
      ),
  ]);
  for (const [item, records] of perItem) {
    parts.push([
      `best per ${item}`,
      ...records.map(
        (x) =>
          `${item}=${x.value} classifier ${modelText(x.classifier.model)} accuracy ${real(x.classifier.correct / n)} regressor ${modelText(x.regressor.model)} rmse ${real(x.regressor.rmse)}`,
      ),
    ]);
  }
  parts.push([
    'classifier folds',
    ...cross.folds.map(
      (fold, i) => `fold ${i + 1} correct ${ratio(correctCount(fold, c.predictions), fold.length)}`,
    ),
  ]);
  parts.push([
    'regressor folds',
    ...cross.folds.map(
      (fold, i) =>
        `fold ${i + 1} size ${fold.length} rmse ${real(regressionFor(fold, r.predictions).rmse)}`,
    ),
  ]);
  parts.push(
    ['cross_validation classes', ...evaluationLines(train, c.predictions, labels)],
    ['cross_validation reliability', ...reliabilityLines(train, c.predictions, settings.bins)],
  );
  parts.push(mcnemarLines(train, c, perItem.get('metric')!));
  return parts;
}
function testParts(
  data: Dataset,
  labels: string[],
  classifier: Result,
  regressor: Result,
  predictions: TestPredictions,
): string[][] {
  const { test, settings } = data;
  const { classification, estimates } = predictions;
  const labelled = test.filter((row) => row.label !== null);
  const targets = test.filter((row) => row.target !== null);
  const parts = [
    [
      `test classification ${modelText(classifier.model)}`,
      `labelled ${labelled.length} correct ${ratio(correctCount(labelled, classification), labelled.length)}`,
      ...evaluationLines(labelled, classification, labels),
    ],
    ['test reliability', ...reliabilityLines(labelled, classification, settings.bins)],
  ];
  const uncertain = test
    .map((row) => {
      const p = classification.get(row.id)!;
      return { row, p, margin: p.share - p.runnerShare };
    })
    .sort((a, b) => rounded(a.margin) - rounded(b.margin) || a.row.index - b.row.index);
  parts.push([
    `uncertain ${settings.top} test rows`,
    ...uncertain
      .slice(0, settings.top)
      .map(
        ({ row, p, margin }) =>
          `${row.id} predicted ${p.label} share ${real(p.share)} runner_up ${p.runnerUp ?? '-'} share ${real(p.runnerShare)} margin ${real(margin)} true ${row.label ?? '-'}`,
      ),
  ]);
  const stats = regressionFor(targets, estimates);
  const lines = [
    `test regression ${modelText(regressor.model)}`,
    `targets ${targets.length} rmse ${real(stats.rmse)} mae ${real(stats.mae)} r2 ${real(stats.r2)}`,
  ];
  for (const label of labels) {
    const rows = targets.filter((row) => row.label === label);
    lines.push(
      `class ${label} targets ${rows.length} rmse ${real(regressionFor(rows, estimates).rmse)}`,
    );
  }
  parts.push(lines);
  const errors = labelled.filter((row) => classification.get(row.id)!.label !== row.label);
  const misclassified = ['misclassified test rows'];
  for (const row of errors) {
    const p = classification.get(row.id)!;
    misclassified.push(`${row.id} true ${row.label} predicted ${p.label} share ${real(p.share)}`);
    for (const neighbor of p.neighbors) {
      misclassified.push(`  ${neighbor.row.id} ${neighbor.row.label} ${real(neighbor.distance)}`);
    }
  }
  misclassified.push(`count ${errors.length}`);
  parts.push(misclassified);
  return parts;
}
function main(): void {
  const data = readDataset();
  const labels = [...new Set(data.train.map((row) => row.label))].sort(compareText);
  const grid = buildGrid(data.settings);
  const cross = crossValidate(data.train, grid, data.settings.folds);
  const selected = selectModels(cross.results);
  const { classifier, regressor } = selected;
  const perItem = bestPerItem(cross.results, data.settings);
  const parts = selectionParts(data, labels, cross, selected, perItem);
  parts.push(
    ...leaveOneOutParts(data.train, labels, classifier, regressor, data.settings),
    nestedValidation(data.train, cross.folds, grid, data.settings.folds),
    featureSelection(data, classifier),
  );
  const predictions = predictTest(data, classifier, regressor);
  parts.push(...testParts(data, labels, classifier, regressor, predictions));
  writeReport('cv_grid.csv', [
    'k,metric,weighting,scaling,correct,accuracy,rmse',
    ...cross.results.map((r) =>
      [
        r.model.k,
        r.model.metric,
        r.model.weighting,
        r.model.scaling,
        r.correct,
        real(r.correct / data.train.length),
        real(r.rmse),
      ].join(','),
    ),
  ]);
  writeReport('predictions.csv', [
    'id,label,vote_share,estimate',
    ...data.test.map((row) => {
      const p = predictions.classification.get(row.id)!;
      return [
        row.id,
        p.label,
        real(p.share),
        real(predictions.estimates.get(row.id)!.estimate),
      ].join(',');
    }),
  ]);
  writeReport('metrics.txt', flattenParts(parts));
  writeReport('learning_curve.csv', learningLines(data, classifier, regressor));
  writeReport(
    'prototypes.txt',
    flattenParts(prototypeParts(data, labels, classifier, predictions)),
  );
}
main();
