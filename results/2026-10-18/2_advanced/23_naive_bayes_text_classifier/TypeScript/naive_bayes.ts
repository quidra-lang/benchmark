import type { LabelledDocument } from './tokenizer.ts';
import type { Encoded } from './vocabulary.ts';
export type NBKind = 'multinomial' | 'bernoulli' | 'complement';
export interface Counts {
  classes: number[]; occurrences: number[][]; documentTerms: number[][]; totals: number[]; termTotals: number[];
  documentTotals: number[]; total: number; documents: number; vocabularySize: number;
}
export interface NBModel { kind: NBKind; weights: number[][]; baseline: number[]; prior: number[] }
export interface Prediction { label: number; ranking: number[]; scores: number[]; score: number }
export interface NBPrediction extends Prediction { probabilities: number[]; normalizer: number; margin: number }
export function trainingCounts(documents: LabelledDocument[], encoded: Encoded[], k: number, v: number): Counts {
  const classes: number[] = Array(k).fill(0), occurrences: number[][] = Array.from({ length: k }, () => Array(v).fill(0));
  const documentTerms = occurrences.map(row => [...row]), totals = [...classes];
  documents.forEach((doc, i) => {
    const c = doc.label; classes[c]++;
    for (const t of encoded[i].sequence) { occurrences[c][t]++; totals[c]++; }
    for (const t of encoded[i].first) documentTerms[c][t]++;
  });
  const termTotals: number[] = Array(v).fill(0), documentTotals = [...termTotals];
  let total = 0;
  for (let c = 0; c < k; c++) { total += totals[c]; for (let t = 0; t < v; t++) { termTotals[t] += occurrences[c][t]; documentTotals[t] += documentTerms[c][t]; } }
  return { classes, occurrences, documentTerms, totals, termTotals, documentTotals, total, documents: documents.length, vocabularySize: v };
}
export function multinomialModel(occurrences: number[][], totals: number[], classes: number[], documents: number, alpha: number): NBModel {
  const v = occurrences[0].length;
  return { kind: 'multinomial', weights: occurrences.map((row, c) => row.map(n => Math.log((100 * n + alpha) / (100 * totals[c] + alpha * v)))),
    prior: classes.map(n => Math.log(n / documents)), baseline: classes.map(() => 0) };
}
export function train(kind: NBKind, counts: Counts, alpha: number): NBModel {
  if (kind === 'multinomial') return multinomialModel(counts.occurrences, counts.totals, counts.classes, counts.documents, alpha);
  const weights: number[][] = [], baseline: number[] = [];
  for (let c = 0; c < counts.classes.length; c++) {
    const row: number[] = [];
    let base = 0;
    for (let t = 0; t < counts.vocabularySize; t++) {
      if (kind === 'bernoulli') {
        const p = Math.log((100 * counts.documentTerms[c][t] + alpha) / (100 * counts.classes[c] + 2 * alpha));
        const q = Math.log((100 * (counts.classes[c] - counts.documentTerms[c][t]) + alpha) / (100 * counts.classes[c] + 2 * alpha));
        row.push(p - q); base += q;
      } else row.push(Math.log((100 * (counts.termTotals[t] - counts.occurrences[c][t]) + alpha) / (100 * (counts.total - counts.totals[c]) + alpha * counts.vocabularySize)));
    }
    weights.push(row); baseline.push(base);
  }
  return { kind, weights, baseline, prior: counts.classes.map(n => Math.log(n / counts.documents)) };
}
export function posterior(scores: number[]): NBPrediction {
  const ranking = scores.map((_, i) => i).sort((a, b) => scores[b] - scores[a] || a - b), label = ranking[0];
  let normalizer = 0;
  const exponentials = scores.map(s => { const e = Math.exp(s - scores[label]); normalizer += e; return e; });
  const probabilities = exponentials.map(e => e / normalizer);
  return { label, ranking, scores, probabilities, normalizer, score: probabilities[label], margin: scores[label] - scores[ranking[1]] };
}
export function predict(model: NBModel, document: Encoded): NBPrediction {
  const scores = model.prior.map((prior, c) => {
    let score = model.kind === 'bernoulli' ? model.baseline[c] : 0;
    for (const t of model.kind === 'bernoulli' ? document.first : document.sequence) {
      if (model.kind === 'complement') score -= model.weights[c][t]; else score += model.weights[c][t];
    }
    return score + prior;
  });
  return posterior(scores);
}
