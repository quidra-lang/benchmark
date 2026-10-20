import { mkdirSync } from 'node:fs';
import { readDataset, type Dataset, type Row, type Subset } from './dataset.ts';
import * as algebra from './linalg.ts';
import {
  MODELS,
  train,
  predict,
  predictRow,
  type ModelType,
  type Model,
  type ModelSettings,
  type Prediction,
} from './gaussian_models.ts';
import { fraction, confusion, mcnemar, Random } from './evaluation.ts';
import { real, fractionText, frame, cell, writeLines } from './plot.ts';
interface Validation {
  predicted: number[];
  folds: number[];
  correct: number;
}
interface Data extends Dataset {
  all: number[];
  cv: Map<string, Validation>;
}
const fields = (...v: (string | number)[]) => v.join(' ');
const reals = (v: number[]) => v.map(real).join(' ');
const ratio = (a: number, b: number) => fractionText(fraction(a, b));
const predictions = (v: Prediction[]) => v.map((p) => p.predicted);
const sections = (parts: string[][]) => parts.flatMap((part, i) => (i ? ['', ...part] : part));
const correctCount = (rows: Row[], predicted: number[]) =>
  rows.reduce((n, r, i) => n + Number(r.class === predicted[i]), 0);
const fit = (
  d: Data,
  type: ModelType,
  features = d.all,
  rows = d.train,
  changes: Partial<ModelSettings> = {},
) => train(rows, features, type, { ...d.settings, ...changes }, d.classes.length);
const classify = (model: Model, rows: Row[], costs: number[][] | null = null) =>
  rows.map((r) => predictRow(model, r, costs));
function crossValidation(
  d: Data,
  type: ModelType,
  features = d.all,
  changes: Partial<ModelSettings> = {},
): Validation {
  const s = { ...d.settings, ...changes };
  const key = JSON.stringify([type, features, s.prior, s.epsilon, s.gamma]);
  const cached = d.cv.get(key);
  if (cached) return cached;
  const predicted: number[] = Array(d.train.length).fill(0);
  const folds: number[] = Array(s.folds).fill(0);
  for (let f = 0; f < s.folds; f++) {
    const model = fit(
      d,
      type,
      features,
      d.train.filter((r) => r.id % s.folds !== f),
      changes,
    );
    d.train.forEach((r, i) => {
      if (r.id % s.folds !== f) return;
      predicted[i] = predictRow(model, r).predicted;
      if (predicted[i] === r.class) folds[f]++;
    });
  }
  const result = { predicted, folds, correct: correctCount(d.train, predicted) };
  d.cv.set(key, result);
  return result;
}
function modelReport(d: Data, models: Model[]) {
  const [nb, lda, qda] = models;
  const s = d.settings;
  const names = d.classes;
  const parts: string[][] = [];
  parts.push([
    fields('features', ...d.features),
    fields('classes', ...names),
    fields('prior_mode', s.prior),
    ...nb.classes.map((g, i) =>
      fields(
        'class',
        names[i],
        'letter',
        names[i][0].toUpperCase(),
        'count',
        g.count,
        'prior',
        real(g.prior),
        'mean',
        reals(g.mean),
      ),
    ),
  ]);
  parts.push([
    'model NB',
    fields(
      'smoothing epsilon',
      real(s.epsilon),
      'max_variance',
      real(nb.maximumVariance),
      'added',
      real(nb.added),
    ),
    ...nb.classes.map((g, i) =>
      fields(
        'class',
        names[i],
        'variance',
        reals(g.covariance.map((r, j) => r[j])),
        'log_det',
        real(g.logDeterminant),
      ),
    ),
  ]);
  const linear = [
    'model LDA',
    fields('log_det', real(lda.classes[0].logDeterminant)),
    ...lda.classes[0].covariance.map((r) => '  ' + reals(r)),
  ];
  for (const [i, g] of lda.classes.entries()) {
    const coef = algebra.backward(g.lower, algebra.forward(g.lower, g.mean));
    let product = 0;
    for (let j = 0; j < coef.length; j++) product += g.mean[j] * coef[j];
    linear.push(
      fields(
        'class',
        names[i],
        'intercept',
        real(Math.log(g.prior) - product / 2),
        'coef',
        reals(coef),
      ),
    );
  }
  parts.push(linear);
  const quadratic = [fields('model QDA gamma', real(s.gamma))];
  for (const [i, g] of qda.classes.entries()) {
    const ev = algebra.jacobi(g.covariance).values.sort((a, b) => b - a);
    quadratic.push(
      fields(
        'class',
        names[i],
        'log_det',
        real(g.logDeterminant),
        'eigenvalues',
        reals(ev),
        'condition',
        real(ev[0] / ev[ev.length - 1]),
      ),
      ...g.covariance.map((r) => '  ' + reals(r)),
    );
  }
  parts.push(quadratic);
  const separation = ['separation'];
  for (let a = 0; a < names.length; a++) {
    for (let b = a + 1; b < names.length; b++) {
      const ga = qda.classes[a];
      const gb = qda.classes[b];
      const delta = ga.mean.map((v, j) => v - gb.mean[j]);
      const sm = ga.covariance.map((r, i) => r.map((v, j) => (v + gb.covariance[i][j]) / 2));
      const lm = algebra.cholesky(sm);
      const mahal = Math.sqrt(algebra.quadratic(lda.classes[0].lower, delta));
      const bhat =
        algebra.quadratic(lm, delta) / 8 +
        (algebra.logDeterminant(lm) - (ga.logDeterminant + gb.logDeterminant) / 2) / 2;
      separation.push(
        fields(names[a], names[b], 'mahalanobis', real(mahal), 'bhattacharyya', real(bhat)),
      );
    }
  }
  parts.push(separation);
  const outliers = d.train
    .map((row, i) => ({ row, i, q: predictRow(qda, row).distances[row.class] }))
    .filter((o) => o.q > s.outlier)
    .sort((a, b) => b.q - a.q || a.i - b.i);
  parts.push([
    fields('outliers threshold', real(s.outlier)),
    ...outliers.map((o) => fields(o.row.id, o.row.label, 'q', real(o.q))),
    fields('count', outliers.length),
  ]);
  return sections(parts);
}
function predictionReport(d: Data, results: Prediction[][]) {
  const lines = [['id', 'model', 'actual', 'predicted', 'decision', ...d.classes].join(',')];
  d.test.forEach((r, i) =>
    MODELS.forEach((name, m) => {
      const p = results[m][i];
      lines.push(
        [
          r.id,
          name,
          r.label,
          d.classes[p.predicted],
          d.classes[p.decision],
          ...p.posterior.map(real),
        ].join(','),
      );
    }),
  );
  return lines;
}
const confusionLines = (d: Data, metrics: ReturnType<typeof confusion>) =>
  metrics.table.map((r, i) => fields('confusion', d.classes[i], ...r));
function evaluateModel(d: Data, type: ModelType, results: Prediction[]) {
  const predicted = predictions(results);
  const m = confusion(d.test, predicted, d.classes.length);
  const n = d.test.length;
  const lines = [
    fields('model', type),
    ...confusionLines(d, m),
    fields('accuracy', fractionText(m.accuracy)),
    fields('balanced_accuracy', fractionText(m.balanced)),
    fields('kappa', fractionText(m.kappa)),
  ];
  m.classes.forEach((g, i) =>
    lines.push(
      fields(
        'class',
        d.classes[i],
        'support',
        g.support,
        'recall',
        fractionText(g.recall),
        'precision',
        fractionText(g.precision),
        'f1',
        fractionText(g.f1),
      ),
    ),
  );
  let logs = 0;
  d.test.forEach((r, i) => (logs += results[i].logPosterior[r.class]));
  lines.push(
    fields('macro_f1', real(m.macroF1)),
    fields('log_loss', real(-logs / n)),
    fields('errors', n - m.correct),
  );
  d.test.forEach((r, i) => {
    if (r.class !== predicted[i]) {
      lines.push(
        fields(
          'error',
          r.id,
          'actual',
          r.label,
          'predicted',
          d.classes[predicted[i]],
          'confidence',
          real(results[i].confidence),
        ),
      );
    }
  });
  const edges = [0, ...d.settings.calibration, 1];
  let ece = 0;
  for (let b = 0; b + 1 < edges.length; b++) {
    let count = 0;
    let correct = 0;
    let confidence = 0;
    d.test.forEach((r, i) => {
      const v = results[i].confidence;
      if (v < edges[b] || (b + 2 === edges.length ? v > edges[b + 1] : v >= edges[b + 1])) return;
      count++;
      correct += Number(r.class === predicted[i]);
      confidence += v;
    });
    lines.push(
      fields(
        'bin',
        real(edges[b]),
        real(edges[b + 1]),
        'count',
        count,
        'confidence',
        count ? real(confidence / count) : '-',
        'accuracy',
        ratio(correct, count),
      ),
    );
    ece += Math.abs(correct - confidence);
  }
  lines.push(fields('ece', real(ece / n)));
  for (const t of d.settings.reject) {
    let accepted = 0;
    let correct = 0;
    d.test.forEach((r, i) => {
      if (results[i].confidence >= t) {
        accepted++;
        correct += Number(r.class === predicted[i]);
      }
    });
    lines.push(
      fields(
        'reject',
        real(t),
        'accepted',
        accepted,
        'coverage',
        ratio(accepted, n),
        'accuracy',
        ratio(correct, accepted),
      ),
    );
  }
  return lines;
}
function comparisons(rows: Row[], names: readonly string[], predicted: number[][]) {
  const lines: string[] = [];
  for (let a = 0; a < names.length; a++) {
    for (let b = a + 1; b < names.length; b++) {
      const r = mcnemar(rows, predicted[a], predicted[b]);
      lines.push(
        fields(
          names[a],
          names[b],
          'b01',
          r.b01,
          'b10',
          r.b10,
          'chi2',
          real(r.chi2),
          'significant',
          r.significant ? 'yes' : 'no',
        ),
      );
    }
  }
  return lines;
}
function bootstrapReport(d: Data, predicted: number[][]) {
  const s = d.settings;
  const rng = new Random(s.seed);
  const samples: number[][] = MODELS.map(() => []);
  const n = d.test.length;
  for (let b = 0; b < s.resamples; b++) {
    const counts = [0, 0, 0];
    for (let draw = 0; draw < n; draw++) {
      const i = rng.next() % n;
      for (let m = 0; m < 3; m++) counts[m] += Number(predicted[m][i] === d.test[i].class);
    }
    counts.forEach((v, i) => samples[i].push(v));
  }
  const lines = [fields('bootstrap resamples', s.resamples, 'seed', s.seed)];
  const offset = Math.floor(s.resamples / 40);
  samples.forEach((sample, m) => {
    const ordered = sample.toSorted((a, b) => a - b);
    let total = 0;
    for (const v of sample) total += v;
    lines.push(
      fields(
        MODELS[m],
        'mean',
        real(total / s.resamples / n),
        'interval',
        ratio(ordered[offset], n),
        ratio(ordered[ordered.length - 1 - offset], n),
      ),
    );
  });
  for (let a = 0; a < 3; a++) {
    for (let b = a + 1; b < 3; b++) {
      let wins = 0;
      let ties = 0;
      let losses = 0;
      for (let i = 0; i < s.resamples; i++) {
        if (samples[a][i] > samples[b][i]) wins++;
        else if (samples[a][i] === samples[b][i]) ties++;
        else losses++;
      }
      lines.push(fields(MODELS[a], MODELS[b], 'wins', wins, 'ties', ties, 'losses', losses));
    }
  }
  return lines;
}
function subsetReport(d: Data) {
  const sizes: number[] = Array(d.settings.folds).fill(0);
  for (const row of d.train) sizes[row.id % d.settings.folds]++;
  const lines = [
    fields('cross_validation folds', d.settings.folds),
    fields('fold_sizes', ...sizes),
  ];
  let best: { subset: Subset; type: ModelType; correct: number } | null = null;
  for (const subset of d.settings.subsets) {
    lines.push(
      fields('subset', subset.name, 'features', ...subset.features.map((f) => d.features[f])),
    );
    for (const type of MODELS) {
      const r = crossValidation(d, type, subset.features);
      lines.push(
        '  ' +
          fields(
            type,
            'fold_correct',
            ...r.folds,
            'correct',
            r.correct,
            'accuracy',
            ratio(r.correct, d.train.length),
          ),
      );
      if (
        !best ||
        r.correct > best.correct ||
        (r.correct === best.correct && subset.features.length < best.subset.features.length)
      ) {
        best = { subset, type, correct: r.correct };
      }
    }
  }
  const b = best!;
  const count = correctCount(
    d.test,
    predictions(classify(fit(d, b.type, b.subset.features), d.test)),
  );
  lines.push(
    fields(
      'best subset',
      b.subset.name,
      'model',
      b.type,
      'correct',
      b.correct,
      'accuracy',
      ratio(b.correct, d.train.length),
    ),
    fields('refit_test correct', count, 'accuracy', ratio(count, d.test.length)),
  );
  return lines;
}
function leaveOneOut(d: Data) {
  const lines = ['leave_one_out'];
  for (const type of MODELS) {
    let correct = 0;
    d.train.forEach((r, i) => {
      if (
        predictRow(
          fit(
            d,
            type,
            d.all,
            d.train.filter((_, j) => i !== j),
          ),
          r,
        ).predicted === r.class
      ) {
        correct++;
      }
    });
    lines.push(fields(type, 'correct', correct, 'accuracy', ratio(correct, d.train.length)));
  }
  return lines;
}
function forwardSelection(d: Data, type: ModelType) {
  const selected: number[] = [];
  const lines = [fields('forward_selection model', type)];
  let best: { correct: number; features: number[] } | null = null;
  while (selected.length < d.features.length) {
    let candidate: { feature: number; correct: number } | null = null;
    for (const f of d.all) {
      if (!selected.includes(f)) {
        const r = crossValidation(d, type, [...selected, f]);
        if (!candidate || r.correct > candidate.correct) {
          candidate = { feature: f, correct: r.correct };
        }
      }
    }
    const c = candidate!;
    selected.push(c.feature);
    lines.push(
      fields(
        'step',
        selected.length,
        'add',
        d.features[c.feature],
        'correct',
        c.correct,
        'accuracy',
        ratio(c.correct, d.train.length),
      ),
    );
    if (!best || c.correct > best.correct) {
      best = { correct: c.correct, features: selected.slice() };
    }
  }
  lines.push(
    fields(
      'best_step',
      best!.features.length,
      'features',
      ...best!.features.map((f) => d.features[f]),
    ),
  );
  return lines;
}
function tuning(
  d: Data,
  type: ModelType,
  parameter: 'epsilon' | 'gamma',
  grid: number[],
  heading: string,
) {
  const lines = [heading];
  let best: { value: number; correct: number } | null = null;
  for (const value of grid) {
    const r = crossValidation(d, type, d.all, { [parameter]: value });
    lines.push(
      fields(
        'value',
        real(value),
        'correct',
        r.correct,
        'accuracy',
        ratio(r.correct, d.train.length),
      ),
    );
    if (!best || r.correct >= best.correct) best = { value, correct: r.correct };
  }
  const count = correctCount(
    d.test,
    predictions(classify(fit(d, type, d.all, d.train, { [parameter]: best!.value }), d.test)),
  );
  lines.push(
    fields(
      'best',
      real(best!.value),
      'test correct',
      count,
      'accuracy',
      ratio(count, d.test.length),
    ),
  );
  return lines;
}
function evaluationReport(d: Data, results: Prediction[][]) {
  const parts: string[][] = [
    [fields('test rows', d.test.length)],
    ...MODELS.map((type, i) => evaluateModel(d, type, results[i])),
  ];
  const predicted = results.map(predictions);
  const ensemble = d.test.map((_, r) => {
    const p = d.classes.map((__, k) => {
      let sum = 0;
      for (let m = 0; m < 3; m++) sum += results[m][r].posterior[k];
      return sum / 3;
    });
    let best = 0;
    for (let k = 1; k < p.length; k++) if (p[k] > p[best]) best = k;
    return best;
  });
  const em = confusion(d.test, ensemble, d.classes.length);
  parts.push(
    [
      'ensemble soft_vote',
      fields(
        'accuracy',
        fractionText(em.accuracy),
        'balanced_accuracy',
        fractionText(em.balanced),
        'kappa',
        fractionText(em.kappa),
      ),
    ],
    ['mcnemar test', ...comparisons(d.test, [...MODELS, 'ENSEMBLE'], [...predicted, ensemble])],
  );
  const costs = ['costs'];
  results.forEach((model, i) => {
    let arg = 0;
    let decision = 0;
    let changed = 0;
    let correct = 0;
    d.test.forEach((r, j) => {
      const p = model[j];
      arg += d.costs[r.class][p.predicted];
      decision += d.costs[r.class][p.decision];
      changed += Number(p.predicted !== p.decision);
      correct += Number(p.decision === r.class);
    });
    costs.push(
      fields(
        MODELS[i],
        'argmax_total',
        real(arg),
        'decision_total',
        real(decision),
        'changed',
        changed,
        'decision_accuracy',
        ratio(correct, d.test.length),
      ),
    );
  });
  parts.push(costs);
  const novel: { i: number; nearest: number; q: number }[] = [];
  results[2].forEach((r, i) => {
    let nearest = 0;
    for (let k = 1; k < d.classes.length; k++) {
      if (r.distances[k] < r.distances[nearest]) nearest = k;
    }
    if (r.distances[nearest] > d.settings.outlier) {
      novel.push({ i, nearest, q: r.distances[nearest] });
    }
  });
  novel.sort((a, b) => b.q - a.q || a.i - b.i);
  parts.push(
    [
      fields('novelty threshold', real(d.settings.outlier)),
      ...novel.map((v) => fields(d.test[v.i].id, 'nearest', d.classes[v.nearest], 'q', real(v.q))),
      fields('count', novel.length),
    ],
    bootstrapReport(d, predicted),
  );
  const prior = d.settings.prior === 'empirical' ? 'uniform' : 'empirical';
  const sensitivity = [fields('prior_sensitivity alternative', prior)];
  MODELS.forEach((type, i) => {
    const alternative = predictions(classify(fit(d, type, d.all, d.train, { prior }), d.test));
    const m = confusion(d.test, alternative, d.classes.length);
    sensitivity.push(
      fields(
        type,
        'accuracy',
        fractionText(m.accuracy),
        'balanced_accuracy',
        fractionText(m.balanced),
        'changed',
        alternative.filter((p, j) => p !== predicted[i][j]).length,
      ),
    );
  });
  parts.push(sensitivity);
  const curve = ['learning_curve'];
  for (const size of d.settings.curve) {
    const taken: number[] = Array(d.classes.length).fill(0);
    const rows = d.train.filter((r) => ++taken[r.class] <= size);
    const line: (string | number)[] = ['size', size, 'rows', rows.length];
    for (const type of MODELS) {
      line.push(
        type,
        ratio(
          correctCount(d.test, predictions(classify(fit(d, type, d.all, rows), d.test))),
          d.test.length,
        ),
      );
    }
    curve.push(fields(...line));
  }
  parts.push(curve, subsetReport(d));
  const validation = MODELS.map((type) => crossValidation(d, type));
  parts.push([
    'mcnemar cross_validation',
    ...comparisons(
      d.train,
      MODELS,
      validation.map((r) => r.predicted),
    ),
  ]);
  validation.forEach((r, i) => {
    const m = confusion(d.train, r.predicted, d.classes.length);
    parts.push([
      fields('cv_confusion model', MODELS[i]),
      ...confusionLines(d, m),
      fields('balanced_accuracy', fractionText(m.balanced), 'kappa', fractionText(m.kappa)),
    ]);
  });
  parts.push(
    leaveOneOut(d),
    ...MODELS.map((type) => forwardSelection(d, type)),
    tuning(d, 'NB', 'epsilon', d.settings.smoothingGrid, 'nb_smoothing_path'),
    tuning(d, 'QDA', 'gamma', d.settings.gammaGrid, 'qda_gamma_path'),
  );
  return sections(parts);
}
const emptyGrid = (w: number, h: number): string[][] =>
  Array.from({ length: h }, () => Array(w).fill(' '));
function place(grid: string[][], x: number, y: number, letter: string) {
  const before = grid[y][x];
  grid[y][x] = before === ' ' || before === letter ? letter : '*';
}
function boundaryReport(d: Data) {
  const parts: string[][] = [];
  const { width: w, height: h } = d.settings;
  for (const features of d.settings.pairs) {
    const [fx, fy] = features;
    const xs = d.train.map((r) => r.values[fx]);
    const ys = d.train.map((r) => r.values[fy]);
    const xmin = Math.min(...xs);
    const xmax = Math.max(...xs);
    const ymin = Math.min(...ys);
    const ymax = Math.max(...ys);
    const dx = (xmax - xmin) / (w - 1);
    const dy = (ymax - ymin) / (h - 1);
    const lines = [
      fields('pair', d.features[fx], d.features[fy]),
      fields(
        'x',
        d.features[fx],
        real(xmin),
        real(xmax),
        'y',
        d.features[fy],
        real(ymin),
        real(ymax),
        'grid',
        `${w}x${h}`,
      ),
    ];
    const maps: number[][][] = [];
    const uncertainty = emptyGrid(w, h);
    for (const type of MODELS) {
      const model = fit(d, type, features);
      const correct = correctCount(d.train, predictions(classify(model, d.train)));
      const region = emptyGrid(w, h);
      const counts: number[] = Array(d.classes.length).fill(0);
      const choices: number[][] = [];
      lines.push(
        fields(
          'model',
          type,
          'train_accuracy',
          ratio(correct, d.train.length),
          'cv_accuracy',
          ratio(crossValidation(d, type, features).correct, d.train.length),
        ),
      );
      for (let y = 0; y < h; y++) {
        const chosen: number[] = [];
        for (let x = 0; x < w; x++) {
          const p = predict(model, [xmin + x * dx, ymax - y * dy]);
          region[y][x] = d.classes[p.predicted][0].toUpperCase();
          counts[p.predicted]++;
          chosen.push(p.predicted);
          if (type === 'QDA') {
            uncertainty[y][x] = ' .:-=+*#%@'[
              Math.min(9, Math.floor(10 * ((1 - p.confidence) / (1 - 1 / d.classes.length))))
            ];
          }
        }
        choices.push(chosen);
      }
      maps.push(choices);
      lines.push(
        ...frame(region),
        fields('cells', ...d.classes.flatMap((name, k) => [name[0].toUpperCase(), counts[k]])),
      );
    }
    const agreement = emptyGrid(w, h);
    const points = emptyGrid(w, h);
    let disagreements = 0;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const size = new Set(maps.map((m) => m[y][x])).size;
        agreement[y][x] = size === 1 ? '.' : String(size);
        if (size !== 1) disagreements++;
      }
    }
    for (const r of d.train) {
      place(
        points,
        cell(r.values[fx], xmin, xmax, w),
        h - 1 - cell(r.values[fy], ymin, ymax, h),
        d.classes[r.class][0],
      );
    }
    lines.push(
      'agreement',
      ...frame(agreement),
      fields('disagreement_cells', disagreements),
      'uncertainty QDA',
      ...frame(uncertainty),
      'points',
      ...frame(points),
    );
    parts.push(lines);
  }
  return sections(parts);
}
function fisherDirections(within: number[][], between: number[][]) {
  const n = within.length;
  const l = algebra.cholesky(within);
  const y = algebra.matrix(n);
  const z = algebra.matrix(n);
  for (let j = 0; j < n; j++) {
    const v = algebra.forward(
      l,
      between.map((r) => r[j]),
    );
    for (let i = 0; i < n; i++) y[i][j] = v[i];
  }
  for (let i = 0; i < n; i++) {
    const v = algebra.forward(l, y[i]);
    for (let j = 0; j < n; j++) z[j][i] = v[j];
  }
  const eigen = algebra.jacobi(z.map((r, a) => r.map((v, b) => (v + z[b][a]) / 2)));
  const order = Array.from({ length: n }, (_, i) => i).sort(
    (a, b) => eigen.values[b] - eigen.values[a] || a - b,
  );
  let total = 0;
  for (const v of eigen.values) total += v;
  const directions = order.slice(0, 2).map((i) => {
    const v = algebra.backward(
      l,
      eigen.vectors.map((r) => r[i]),
    );
    let norm = 0;
    for (const x of v) norm += x * x;
    norm = Math.sqrt(norm);
    const direction = v.map((x) => x / norm);
    let largest = 0;
    for (let j = 1; j < n; j++) {
      if (Math.abs(direction[j]) > Math.abs(direction[largest])) largest = j;
    }
    return direction[largest] < 0 ? direction.map((x) => -x) : direction;
  });
  return {
    directions,
    sweeps: eigen.sweeps,
    eigenvalues: order.map((i) => eigen.values[i]),
    ratios: order.map((i) => eigen.values[i] / total),
  };
}
function project(vector: number[], directions: number[][], center: number[]) {
  return directions.map((v) => {
    let sum = 0;
    for (let j = 0; j < vector.length; j++) sum += v[j] * (vector[j] - center[j]);
    return sum;
  });
}
function nearestCount(
  rows: Row[],
  projections: number[][],
  centroids: number[][],
  dimensions: number,
) {
  let correct = 0;
  rows.forEach((r, i) => {
    let nearest = 0;
    let least = Infinity;
    centroids.forEach((c, k) => {
      const a = projections[i][0] - c[0];
      let distance = a * a;
      if (dimensions === 2) {
        const b = projections[i][1] - c[1];
        distance += b * b;
      }
      if (distance < least) {
        least = distance;
        nearest = k;
      }
    });
    correct += Number(nearest === r.class);
  });
  return correct;
}
function projectionReport(d: Data, lda: Model) {
  const n = d.features.length;
  const count = d.classes.length;
  const { center, classes } = lda.data;
  const within = algebra.matrix(n);
  const between = algebra.matrix(n);
  for (let a = 0; a < n; a++) {
    for (let b = 0; b < n; b++) {
      for (const g of classes) {
        within[a][b] += g.scatter[a][b];
        between[a][b] += g.count * (g.mean[a] - center[a]) * (g.mean[b] - center[b]);
      }
    }
  }
  const fv = d.all.map(
    (j) => between[j][j] / (count - 1) / (within[j][j] / (d.train.length - count)),
  );
  const order = d.all.toSorted((a, b) => fv[b] - fv[a] || a - b);
  const univariate = [
    'univariate',
    ...order.map((j, i) =>
      fields(
        'rank',
        i + 1,
        d.features[j],
        'f',
        real(fv[j]),
        'between',
        real(between[j][j]),
        'within',
        real(within[j][j]),
      ),
    ),
  ];
  const fisher = fisherDirections(within, between);
  const lines = [
    fields('fisher features', ...d.features),
    fields('center', reals(center)),
    fields('sweeps', fisher.sweeps),
    fields('eigenvalues', reals(fisher.eigenvalues)),
    fields('ratios', reals(fisher.ratios)),
  ];
  fisher.directions.forEach((v, i) =>
    lines.push(
      fields('direction', i + 1, reals(v)),
      fields(
        'standardized',
        i + 1,
        reals(v.map((x, j) => x * Math.sqrt(lda.classes[0].covariance[j][j]))),
      ),
    ),
  );
  const centroids = classes.map((g) => project(g.mean, fisher.directions, center));
  const training = d.train.map((r) => project(r.values, fisher.directions, center));
  const testing = d.test.map((r) => project(r.values, fisher.directions, center));
  classes.forEach((g, k) => {
    const spread = [0, 1].map((t) => {
      let sum = 0;
      d.train.forEach((r, i) => {
        if (r.class === k) {
          const x = training[i][t] - centroids[k][t];
          sum += x * x;
        }
      });
      return Math.sqrt(sum / g.count);
    });
    lines.push(fields('centroid', d.classes[k], reals(centroids[k]), 'spread', reals(spread)));
  });
  for (const dims of [1, 2]) {
    lines.push(
      fields(
        'nearest_centroid dims',
        dims,
        'train',
        ratio(nearestCount(d.train, training, centroids, dims), d.train.length),
        'test',
        ratio(nearestCount(d.test, testing, centroids, dims), d.test.length),
      ),
    );
  }
  const lo1 = Math.min(...training.map((p) => p[0]));
  const hi1 = Math.max(...training.map((p) => p[0]));
  const lo2 = Math.min(...training.map((p) => p[1]));
  const hi2 = Math.max(...training.map((p) => p[1]));
  const w = d.settings.plotWidth;
  const h = d.settings.plotHeight;
  const grid = emptyGrid(w, h);
  training.forEach((p, i) =>
    place(
      grid,
      cell(p[0], lo1, hi1, w),
      h - 1 - cell(p[1], lo2, hi2, h),
      d.classes[d.train[i].class][0],
    ),
  );
  centroids.forEach(
    (p, k) =>
      (grid[h - 1 - cell(p[1], lo2, hi2, h)][cell(p[0], lo1, hi1, w)] =
        d.classes[k][0].toUpperCase()),
  );
  return sections([
    univariate,
    lines,
    [
      fields('plot x', real(lo1), real(hi1), 'y', real(lo2), real(hi2), 'size', `${w}x${h}`),
      ...frame(grid),
    ],
  ]);
}
function main() {
  const dataset = readDataset();
  const d: Data = { ...dataset, all: dataset.features.map((_, i) => i), cv: new Map() };
  const models = MODELS.map((t) => fit(d, t));
  const results = models.map((m) => classify(m, d.test, d.costs));
  mkdirSync('output', { recursive: true });
  writeLines('models.txt', modelReport(d, models));
  writeLines('predictions.csv', predictionReport(d, results));
  writeLines('evaluation.txt', evaluationReport(d, results));
  writeLines('boundaries.txt', boundaryReport(d));
  writeLines('projection.txt', projectionReport(d, models[1]));
}
main();
