import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { tokenize, type Document, type LabelledDocument, type TermKind } from './tokenizer.ts';
import {
  compareText,
  buildVocabulary,
  encode,
  type Vocabulary,
  type Encoded,
} from './vocabulary.ts';
import * as nb from './naive_bayes.ts';
import * as rocchio from './rocchio.ts';
import { real, rounded, proportion, metric, evaluate, evaluationLines } from './evaluation.ts';

const NB_MODELS = ['multinomial', 'bernoulli', 'complement'] as const;
const MODELS = [...NB_MODELS, 'rocchio', 'vote'] as const;
const PAIRS: [number, number][] = [];
for (let a = 0; a < 4; a++) for (let b = a + 1; b < 4; b++) PAIRS.push([a, b]);
interface TrainingDocument extends LabelledDocument {
  number: number;
}
interface TestDocument extends Document {
  id: string;
  order: number;
  label: number | null;
}
interface Settings {
  alphas: number[];
  minimum: number;
  features: number;
  kind: TermKind;
  top: number;
  curve: number[];
  sizes: number[];
  thresholds: number[];
  lengths: number[];
  iterations: number;
  weight: number;
  bootstrap: number;
  seed: number;
}
interface Input {
  settings: Settings;
  classes: string[];
  train: TrainingDocument[];
  test: TestDocument[];
  unlabelled: Document[];
}
interface CVRun {
  model: number;
  alpha: number | null;
  predictions: number[];
  correctByFold: number[];
}
interface Row {
  document: TestDocument;
  encoded: Encoded;
  nb: nb.NBPrediction[];
  predictions: nb.Prediction[];
}
const twoDecimal = (v: number) => Math.floor(v / 100) + '.' + String(v % 100).padStart(2, '0');
const alphaText = (run: CVRun) => (run.alpha === null ? '-' : twoDecimal(run.alpha));
const classCountsText = (counts: number[], classes: string[]) =>
  classes.map((c, i) => c + ' ' + counts[i]).join(' ');
function hundredfold(text: string): number {
  const [whole, part] = text.split('.');
  return +whole * 100 + +part;
}
function readInput(): Input {
  const lines = (name: string) =>
    readFileSync('input/' + name, 'ascii')
      .slice(0, -1)
      .split('\n');
  const values = new Map(
    lines('params.txt').map((line) => {
      const [key, ...fields] = line.split(' ');
      return [key, fields];
    }),
  );
  const p = (key: string) => values.get(key)!;
  const integer = (key: string) => +p(key)[0];
  const settings: Settings = {
    alphas: p('ALPHAS').map(hundredfold),
    minimum: integer('MIN_DF'),
    features: integer('FEATURES'),
    kind: p('BIGRAMS')[0] === 'yes' ? 'bigrams' : 'unigrams',
    top: integer('TOP'),
    curve: p('CURVE').map(Number),
    sizes: p('SIZES').map(Number),
    thresholds: p('THRESHOLDS').map(hundredfold),
    lengths: p('LENGTHS').map(Number),
    iterations: integer('EM_ITERATIONS'),
    weight: hundredfold(p('EM_WEIGHT')[0]),
    bootstrap: +p('BOOTSTRAP')[0],
    seed: +p('BOOTSTRAP')[1],
  };
  const stopwords = new Set(lines('stopwords.txt'));
  const fields = lines('train.txt').map((line) => line.split('\t'));
  const classes = [...new Set(fields.map(([c]) => c))].sort(compareText);
  const indices = new Map(classes.map((c, i) => [c, i]));
  const train = fields.map(([c, text], i) => ({
    number: i + 1,
    label: indices.get(c)!,
    tokens: tokenize(text, stopwords),
  }));
  const test = lines('test.txt').map((line, order) => {
    const [id, c, text] = line.split('\t');
    return {
      id,
      order,
      label: c === '?' ? null : indices.get(c)!,
      tokens: tokenize(text, stopwords),
    };
  });
  return {
    settings,
    classes,
    train,
    test,
    unlabelled: lines('unlabelled.txt').map((text) => ({ tokens: tokenize(text, stopwords) })),
  };
}
function makeVocabulary(
  documents: LabelledDocument[],
  data: Input,
  kind = data.settings.kind,
  size = data.settings.features,
): Vocabulary {
  return buildVocabulary(documents, data.classes.length, data.settings.minimum, size, kind);
}
function fitModels(
  documents: LabelledDocument[],
  vocabulary: Vocabulary,
  selections: CVRun[],
  k: number,
) {
  const encoded = documents.map((d) => encode(d, vocabulary));
  const counts = nb.trainingCounts(documents, encoded, k, vocabulary.terms.length);
  return {
    vocabulary,
    counts,
    nb: NB_MODELS.map((name, m) => nb.train(name, counts, selections[m].alpha!)),
    rocchio: rocchio.train(documents, encoded, vocabulary, k),
  };
}
type Bundle = ReturnType<typeof fitModels>;
function majorityVote(predictions: nb.Prediction[], k: number): nb.Prediction {
  const votes: number[] = Array(k).fill(0);
  for (const p of predictions) votes[p.label]++;
  const maximum = Math.max(...votes);
  const label = predictions.find((p) => votes[p.label] === maximum)!.label;
  return { label, score: maximum / 4, scores: votes, ranking: [] };
}
function predictRows(bundle: Bundle, documents: TestDocument[]): Row[] {
  return documents.map((document) => {
    const encoded = encode(document, bundle.vocabulary);
    const predictions = bundle.nb.map((m) => nb.predict(m, encoded));
    const base = [...predictions, rocchio.predict(bundle.rocchio, encoded)];
    return {
      document,
      encoded,
      nb: predictions,
      predictions: [...base, majorityVote(base, bundle.counts.classes.length)],
    };
  });
}
function evaluateRows(rows: Row[], m: number, k: number) {
  return evaluate(
    rows.map((r) => r.document.label!),
    rows.map((r) => r.predictions[m].label),
    k,
  );
}
function crossValidation(data: Input) {
  const runs: CVRun[] = [];
  for (let model = 0; model < 3; model++) {
    for (const alpha of data.settings.alphas) {
      runs.push({
        model,
        alpha,
        predictions: Array(data.train.length),
        correctByFold: Array(5).fill(0),
      });
    }
  }
  runs.push({
    model: 3,
    alpha: null,
    predictions: Array(data.train.length),
    correctByFold: Array(5).fill(0),
  });
  const folds: { train: number; validate: number; candidates: number; vocabulary: number }[] = [];
  for (let f = 0; f < 5; f++) {
    const training = data.train.filter((d) => (d.number - 1) % 5 !== f);
    const validation = data.train.filter((d) => (d.number - 1) % 5 === f);
    const vocabulary = makeVocabulary(training, data);
    const encoded = training.map((d) => encode(d, vocabulary));
    const heldout = validation.map((d) => encode(d, vocabulary));
    const counts = nb.trainingCounts(
      training,
      encoded,
      data.classes.length,
      vocabulary.terms.length,
    );
    const centroid = rocchio.train(training, encoded, vocabulary, data.classes.length);
    folds.push({
      train: training.length,
      validate: validation.length,
      candidates: vocabulary.candidateCount,
      vocabulary: vocabulary.terms.length,
    });
    for (const run of runs) {
      const model = run.model < 3 ? nb.train(NB_MODELS[run.model], counts, run.alpha!) : null;
      const predictions = heldout.map((d) =>
        model === null ? rocchio.predict(centroid, d).label : nb.predict(model, d).label,
      );
      validation.forEach((doc, i) => {
        run.predictions[doc.number - 1] = predictions[i];
        if (predictions[i] === doc.label) run.correctByFold[f]++;
      });
    }
  }
  const actual = data.train.map((d) => d.label);
  const entries = runs.map((run) => ({
    ...run,
    evaluation: evaluate(actual, run.predictions, data.classes.length),
  }));
  const selections = [0, 1, 2, 3].map((m) => {
    const candidates = entries.filter((e) => e.model === m);
    let best = candidates[0];
    for (const e of candidates) {
      if (rounded(e.evaluation.macro) > rounded(best.evaluation.macro)) best = e;
    }
    return best;
  });
  return { entries, folds, selections };
}
type CV = ReturnType<typeof crossValidation>;
function vocabularyLines(data: Input, vocabulary: Vocabulary): string[] {
  return [
    `documents ${data.train.length} terms ${vocabulary.termCount} candidates ${vocabulary.candidateCount} vocabulary ${vocabulary.terms.length}`,
    ...vocabulary.ranking.map(
      (t, i) => `${i + 1} ${t.term} ${t.df} ${real(t.chiSquare)} ${data.classes[t.bestClass]}`,
    ),
  ];
}
function studies(data: Input, selections: CVRun[]) {
  const labelled = data.test.filter((d) => d.label !== null);
  const curve = ['size,vocabulary,model,correct,accuracy,macro_f1'];
  for (const size of data.settings.curve) {
    const docs = data.train.slice(0, size);
    const vocabulary = makeVocabulary(docs, data);
    const rows = predictRows(
      fitModels(docs, vocabulary, selections, data.classes.length),
      labelled,
    );
    for (let m = 0; m < 4; m++) {
      const e = evaluateRows(rows, m, data.classes.length);
      curve.push(
        [
          size,
          vocabulary.terms.length,
          MODELS[m],
          e.correct,
          real(e.correct / labelled.length),
          real(e.macro),
        ].join(','),
      );
    }
  }
  const features = ['terms,features,vocabulary,model,correct,accuracy,macro_f1'];
  for (const kind of ['unigrams', 'bigrams'] as const) {
    for (const size of data.settings.sizes) {
      const vocabulary = makeVocabulary(data.train, data, kind, size);
      const rows = predictRows(
        fitModels(data.train, vocabulary, selections, data.classes.length),
        labelled,
      );
      for (let m = 0; m < 4; m++) {
        const e = evaluateRows(rows, m, data.classes.length);
        features.push(
          [
            kind,
            size,
            vocabulary.terms.length,
            MODELS[m],
            e.correct,
            real(e.correct / labelled.length),
            real(e.macro),
          ].join(','),
        );
      }
    }
  }
  return { curve, features };
}
function dataLines(data: Input, bundle: Bundle, rows: Row[], labelled: Row[]): string[] {
  const { classes, train, test, unlabelled, settings } = data;
  const v = bundle.vocabulary;
  const lines = [
    `documents train ${train.length} test ${test.length} labelled ${labelled.length} unlabelled ${unlabelled.length} classes ${classes.length}`,
  ];
  classes.forEach((c, i) =>
    lines.push(
      `class ${c} train ${bundle.counts.classes[i]} test ${labelled.filter((r) => r.document.label === i).length}`,
    ),
  );
  let raw = 0;
  let stopped = 0;
  let short = 0;
  let kept = 0;
  let bigrams = 0;
  const words = new Set<string>();
  const pairs = new Set<string>();
  for (const { tokens: t } of train) {
    raw += t.raw;
    stopped += t.stopped;
    short += t.short;
    kept += t.unigrams.length;
    for (const w of t.unigrams) words.add(w);
    if (settings.kind === 'bigrams') {
      bigrams += t.pairs.length;
      for (const p of t.pairs) pairs.add(p);
    }
  }
  lines.push(
    `train_tokens raw ${raw} stopwords ${stopped} short ${short} unigrams ${kept} bigrams ${bigrams}`,
    `train_terms unigrams ${words.size} bigrams ${pairs.size} candidates ${v.candidateCount} vocabulary ${v.terms.length}`,
  );
  let total = 0;
  let included = 0;
  const unknown = new Map<string, number>();
  for (const r of rows) {
    total += r.document.tokens[settings.kind].length;
    included += r.encoded.sequence.length;
    for (const w of r.document.tokens.unigrams) {
      if (!v.indices.has(w)) unknown.set(w, (unknown.get(w) ?? 0) + 1);
    }
  }
  const oov = [...unknown]
    .sort((a, b) => b[1] - a[1] || compareText(a[0], b[0]))
    .slice(0, settings.top);
  lines.push(
    `test_terms total ${total} in_vocabulary ${included}`,
    'test_oov' + oov.map(([w, n]) => ` ${w} ${n}`).join(''),
  );
  return lines;
}
function validationParts(data: Input, cv: CV): string[][] {
  const folds = [
    'folds 5',
    ...cv.folds.map(
      (f, i) =>
        `fold ${i + 1} train ${f.train} validate ${f.validate} candidates ${f.candidates} vocabulary ${f.vocabulary}`,
    ),
  ];
  const selection = [
    'selection',
    ...cv.selections.map(
      (e) =>
        `${MODELS[e.model]} alpha ${alphaText(e)} correct ${proportion(e.evaluation.correct, data.train.length)} macro_f1 ${real(e.evaluation.macro)} folds ${e.correctByFold.join(' ')}`,
    ),
  ];
  return [
    folds,
    selection,
    ...cv.selections.map((e) => [
      `cross_validation ${MODELS[e.model]} alpha ${alphaText(e)}`,
      ...evaluationLines(e.evaluation, data.classes),
    ]),
  ];
}
function testParts(data: Input, labelled: Row[], selections: CVRun[]): string[][] {
  return MODELS.map((name, m) => {
    const e = evaluateRows(labelled, m, data.classes.length);
    const lines = [
      `test ${name} alpha ${m < 3 ? alphaText(selections[m]) : '-'}`,
      `labelled ${labelled.length} correct ${proportion(e.correct, labelled.length)}`,
    ];
    if (m < 4) {
      lines.push(
        'top2 ' +
          proportion(
            labelled.filter((r) => r.predictions[m].ranking.slice(0, 2).includes(r.document.label!))
              .length,
            labelled.length,
          ),
      );
    }
    return [...lines, ...evaluationLines(e, data.classes)];
  });
}
function probabilityParts(data: Input, labelled: Row[], selections: CVRun[]): string[][] {
  return NB_MODELS.map((name, m) => {
    const bounds = [0, ...data.settings.thresholds];
    const bins = bounds.map(() => ({ count: 0, correct: 0, total: 0 }));
    let loss = 0;
    let brier = 0;
    for (const r of labelled) {
      const p = r.nb[m];
      const y = r.document.label!;
      loss += Math.log(p.normalizer) - (p.scores[y] - p.scores[p.label]);
      let squared = 0;
      for (let c = 0; c < data.classes.length; c++) {
        const d = p.probabilities[c] - (c === y ? 1 : 0);
        squared += d * d;
      }
      brier += squared;
      const b = bins[data.settings.thresholds.filter((t) => p.score >= t / 100).length];
      b.count++;
      if (p.label === y) b.correct++;
      b.total += p.score;
    }
    const lines = [
      `probability ${name} alpha ${alphaText(selections[m])}`,
      `log_loss ${real(loss / labelled.length)} brier ${real(brier / labelled.length)}`,
    ];
    bins.forEach((b, i) =>
      lines.push(
        `bin ${twoDecimal(bounds[i])} rows ${b.count}` +
          (b.count
            ? ` correct ${proportion(b.correct, b.count)} mean ${real(b.total / b.count)}`
            : ''),
      ),
    );
    for (const t of data.settings.thresholds) {
      const accepted = labelled.filter((r) => r.nb[m].score >= t / 100);
      const correct = accepted.filter((r) => r.nb[m].label === r.document.label).length;
      lines.push(
        `threshold ${twoDecimal(t)} covered ${proportion(accepted.length, labelled.length)} correct ${accepted.length ? proportion(correct, accepted.length) : '-'}`,
      );
    }
    return lines;
  });
}
function lengthLines(data: Input, labelled: Row[]): string[] {
  const bounds = [0, ...data.settings.lengths];
  const buckets = bounds.map(() => ({ count: 0, correct: MODELS.map(() => 0) }));
  for (const r of labelled) {
    const b = buckets[data.settings.lengths.filter((e) => r.encoded.sequence.length >= e).length];
    b.count++;
    r.predictions.forEach((p, m) => {
      if (p.label === r.document.label) b.correct[m]++;
    });
  }
  return [
    'lengths',
    ...buckets.map(
      (b, i) =>
        `length ${bounds[i]} rows ${b.count}` +
        (b.count
          ? MODELS.map((name, m) => ` ${name} ${proportion(b.correct[m], b.count)}`).join('')
          : ''),
    ),
  ];
}
function comparisonLines(rows: Row[], labelled: Row[]): string[] {
  const lines = ['comparison'];
  for (const [a, b] of PAIRS) {
    const agreement = rows.filter((r) => r.predictions[a].label === r.predictions[b].label).length;
    let first = 0;
    let second = 0;
    for (const r of labelled) {
      const x = r.predictions[a].label === r.document.label;
      const y = r.predictions[b].label === r.document.label;
      if (x && !y) first++;
      if (y && !x) second++;
    }
    const d = Math.max(0, Math.abs(first - second) - 1);
    lines.push(
      `${MODELS[a]} ${MODELS[b]} agree ${proportion(agreement, rows.length)} b ${first} c ${second} statistic ${metric(d * d, first + second || 1)}`,
    );
  }
  const errors: number[] = Array(5).fill(0);
  for (const r of labelled) {
    errors[r.predictions.slice(0, 4).filter((p) => p.label !== r.document.label).length]++;
  }
  return [...lines, 'errors ' + errors.map((n, i) => i + ' ' + n).join(' ')];
}
function bootstrapLines(data: Input, labelled: Row[]): string[] {
  const repetitions = data.settings.bootstrap;
  const samples: number[][] = MODELS.map(() => []);
  const totals = MODELS.map(() => 0);
  const comparisons = PAIRS.map(() => ({ wins: 0, ties: 0, losses: 0 }));
  const correctness = labelled.map((r) =>
    r.predictions.map((p) => (p.label === r.document.label ? 1 : 0)),
  );
  let state = data.settings.seed;
  for (let r = 0; r < repetitions; r++) {
    const correct = MODELS.map(() => 0);
    for (let i = 0; i < labelled.length; i++) {
      state = (48271 * state) % 2147483647;
      const chosen = correctness[state % labelled.length];
      for (let m = 0; m < 5; m++) correct[m] += chosen[m];
    }
    for (let m = 0; m < 5; m++) {
      samples[m].push(correct[m]);
      totals[m] += correct[m];
    }
    PAIRS.forEach(([a, b], i) => {
      comparisons[i][
        correct[a] > correct[b] ? 'wins' : correct[a] === correct[b] ? 'ties' : 'losses'
      ]++;
    });
  }
  const index = Math.floor(repetitions / 40);
  const lines = [`bootstrap resamples ${repetitions} seed ${data.settings.seed}`];
  MODELS.forEach((name, m) => {
    samples[m].sort((a, b) => a - b);
    lines.push(
      `${name} mean ${real(totals[m] / (repetitions * labelled.length))} low ${proportion(samples[m][index], labelled.length)} high ${proportion(samples[m][repetitions - 1 - index], labelled.length)}`,
    );
  });
  PAIRS.forEach(([a, b], i) => {
    const c = comparisons[i];
    lines.push(`pair ${MODELS[a]} ${MODELS[b]} wins ${c.wins} ties ${c.ties} losses ${c.losses}`);
  });
  return lines;
}
function hardLines(data: Input, selections: CVRun[]): string[] {
  const hard = data.train.filter((d) =>
    selections.every((e) => e.predictions[d.number - 1] !== d.label),
  );
  const counts = data.classes.map(() => 0);
  for (const d of hard) counts[d.label]++;
  return [
    `hard_documents ${hard.length} ${classCountsText(counts, data.classes)}`,
    ...hard
      .slice(0, data.settings.top)
      .map(
        (d) =>
          `${d.number} true ${data.classes[d.label]} predicted ${selections.map((e) => data.classes[e.predictions[d.number - 1]]).join(' ')}`,
      ),
  ];
}
function uncertainLines(data: Input, rows: Row[]): string[] {
  const selected = [...rows]
    .sort(
      (a, b) =>
        rounded(a.nb[0].margin) - rounded(b.nb[0].margin) || a.document.order - b.document.order,
    )
    .slice(0, data.settings.top);
  return [
    `uncertain multinomial ${selected.length}`,
    ...selected.map((r) => {
      const p = r.nb[0];
      return `${r.document.id} predicted ${data.classes[p.label]} runner_up ${data.classes[p.ranking[1]]} margin ${real(p.margin)} posterior ${real(p.score)} true ${r.document.label === null ? '?' : data.classes[r.document.label]}`;
    }),
  ];
}
interface Ratio {
  term: string;
  numerator: number;
  denominator: number;
}
function ratioOrder(a: Ratio, b: Ratio): number {
  const left = a.numerator * b.denominator;
  const right = b.numerator * a.denominator;
  return left === right ? compareText(a.term, b.term) : left > right ? -1 : 1;
}
function evidenceLines(data: Input, bundle: Bundle, labelled: Row[], alpha: number): string[] {
  const wrong = labelled.filter((r) => r.nb[0].label !== r.document.label);
  const lines = [`misclassified multinomial ${wrong.length}`];
  for (const r of wrong) {
    const p = r.nb[0];
    const y = r.document.label!;
    const terms = r.encoded.first
      .map((t) => ({
        index: t,
        term: bundle.vocabulary.terms[t].term,
        numerator: 100 * bundle.counts.occurrences[p.label][t] + alpha,
        denominator: 100 * bundle.counts.occurrences[y][t] + alpha,
      }))
      .sort(ratioOrder);
    lines.push(
      `${r.document.id} true ${data.classes[y]} predicted ${data.classes[p.label]} posterior ${real(p.score)}`,
    );
    for (const t of terms.slice(0, 3)) {
      lines.push(
        `  ${t.term} count ${r.encoded.counts.get(t.index)} evidence ${real(bundle.nb[0].weights[p.label][t.index] - bundle.nb[0].weights[y][t.index])}`,
      );
    }
  }
  return lines;
}
function characteristicParts(data: Input, bundle: Bundle, selections: CVRun[]): string[][] {
  const parts: string[][] = [];
  const counts = bundle.counts;
  const v = bundle.vocabulary.terms.length;
  for (let m = 0; m < 2; m++) {
    const alpha = selections[m].alpha!;
    parts.push([
      `model ${MODELS[m]} alpha ${twoDecimal(alpha)} vocabulary ${v} top ${data.settings.top}`,
    ]);
    data.classes.forEach((name, c) => {
      const total = m === 0 ? counts.totals[c] : counts.classes[c];
      const other = m === 0 ? counts.total - total : counts.documents - total;
      const terms = bundle.vocabulary.terms
        .map((entry, t) => {
          const count = m === 0 ? counts.occurrences[c][t] : counts.documentTerms[c][t];
          const otherCount = (m === 0 ? counts.termTotals[t] : counts.documentTotals[t]) - count;
          return {
            term: entry.term,
            count,
            otherCount,
            numerator: 100 * count + alpha,
            denominator: 100 * otherCount + alpha,
          };
        })
        .sort(ratioOrder)
        .slice(0, data.settings.top);
      const smoothing = m === 0 ? alpha * v : 2 * alpha;
      parts.push([
        `class ${name} total ${total} other ${other}`,
        ...terms.map((t, i) => {
          const odds =
            Math.log((100 * t.count + alpha) / (100 * total + smoothing)) -
            Math.log((100 * t.otherCount + alpha) / (100 * other + smoothing));
          return `${i + 1} ${t.term} ${t.count} ${t.otherCount} ${real(odds)}`;
        }),
      ]);
    });
  }
  return parts;
}
function semiSupervisedLines(
  data: Input,
  bundle: Bundle,
  labelled: Row[],
  alpha: number,
): string[] {
  const unlabelled = data.unlabelled.map((d) => encode(d, bundle.vocabulary));
  const weight = data.settings.weight / 100;
  const documentTotal = data.train.length + (data.settings.weight * unlabelled.length) / 100;
  const actual = labelled.map((r) => r.document.label!);
  const lines = [
    `semi_supervised multinomial alpha ${twoDecimal(alpha)} weight ${twoDecimal(data.settings.weight)} unlabelled ${unlabelled.length}`,
  ];
  let previous: number[] | null = null;
  let model = bundle.nb[0];
  for (let iteration = 0; iteration <= data.settings.iterations; iteration++) {
    const posterior = unlabelled.map((d) => nb.predict(model, d));
    const assignments = posterior.map((p) => p.label);
    const classes = data.classes.map(() => 0);
    for (const c of assignments) classes[c]++;
    const e = evaluate(
      actual,
      labelled.map((r) => nb.predict(model, r.encoded).label),
      data.classes.length,
    );
    const changed =
      previous === null ? '-' : assignments.filter((c, i) => c !== previous![i]).length;
    lines.push(
      `iteration ${iteration} correct ${proportion(e.correct, labelled.length)} macro_f1 ${real(e.macro)} changed ${changed} assigned ${classCountsText(classes, data.classes)}`,
    );
    if (iteration === data.settings.iterations) break;
    const occurrences = bundle.counts.occurrences.map((row) => [...row]);
    const expectedDocuments = [...bundle.counts.classes];
    for (let u = 0; u < unlabelled.length; u++) {
      for (let c = 0; c < data.classes.length; c++) {
        const w = weight * posterior[u].probabilities[c];
        for (const t of unlabelled[u].first) occurrences[c][t] += w * unlabelled[u].counts.get(t)!;
        expectedDocuments[c] += w;
      }
    }
    const totals = occurrences.map((row) => {
      let total = 0;
      for (const count of row) total += count;
      return total;
    });
    model = nb.multinomialModel(occurrences, totals, expectedDocuments, documentTotal, alpha);
    previous = assignments;
  }
  return lines;
}
function joinParts(parts: string[][]): string[] {
  return parts.flatMap((p, i) => (i ? ['', ...p] : p));
}
function main(): void {
  const data = readInput();
  const cv = crossValidation(data);
  const vocabulary = makeVocabulary(data.train, data);
  const bundle = fitModels(data.train, vocabulary, cv.selections, data.classes.length);
  const rows = predictRows(bundle, data.test);
  const labelled = rows.filter((r) => r.document.label !== null);
  const study = studies(data, cv.selections);
  const alpha = cv.selections[0].alpha!;
  const metrics = joinParts([
    dataLines(data, bundle, rows, labelled),
    ...validationParts(data, cv),
    ...testParts(data, labelled, cv.selections),
    ...probabilityParts(data, labelled, cv.selections),
    lengthLines(data, labelled),
    comparisonLines(rows, labelled),
    bootstrapLines(data, labelled),
    hardLines(data, cv.selections),
    uncertainLines(data, rows),
    evidenceLines(data, bundle, labelled, alpha),
    semiSupervisedLines(data, bundle, labelled, alpha),
  ]);
  const reports: Record<string, string[]> = {
    'vocabulary.txt': vocabularyLines(data, vocabulary),
    'cv_results.csv': [
      'model,alpha,correct,accuracy,macro_f1,selected',
      ...cv.entries.map((e) =>
        [
          MODELS[e.model],
          alphaText(e),
          e.evaluation.correct,
          real(e.evaluation.correct / data.train.length),
          real(e.evaluation.macro),
          e === cv.selections[e.model] ? 'yes' : 'no',
        ].join(','),
      ),
    ],
    'predictions.csv': [
      'id,model,label,score',
      ...rows.flatMap((r) =>
        r.predictions.map((p, m) =>
          [r.document.id, MODELS[m], data.classes[p.label], real(p.score)].join(','),
        ),
      ),
    ],
    'learning_curve.csv': study.curve,
    'feature_study.csv': study.features,
    'metrics.txt': metrics,
    'top_features.txt': joinParts(characteristicParts(data, bundle, cv.selections)),
  };
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
  }
}
main();
