import type { LabelledDocument } from './tokenizer.ts';
import type { Encoded, Vocabulary } from './vocabulary.ts';
import type { Prediction } from './naive_bayes.ts';
export interface RocchioModel { idf: number[]; centroids: number[][]; lengths: number[] }
export function vector(document: Encoded, idf: number[]) {
  const entries: [number, number][] = [...document.counts].sort((a, b) => a[0] - b[0]).map(([t, count]) => [t, count * idf[t]]);
  let squared = 0;
  for (const [, v] of entries) squared += v * v;
  return { entries, length: Math.sqrt(squared) };
}
export function train(documents: LabelledDocument[], encoded: Encoded[], vocabulary: Vocabulary, k: number): RocchioModel {
  const idf = vocabulary.terms.map(t => Math.log(documents.length / t.df));
  const centroids: number[][] = Array.from({ length: k }, () => Array(idf.length).fill(0));
  documents.forEach((doc, i) => {
    const v = vector(encoded[i], idf);
    if (v.length) for (const [t, value] of v.entries) centroids[doc.label][t] += value / v.length;
  });
  const lengths = centroids.map((row, c) => {
    let squared = 0;
    for (let t = 0; t < row.length; t++) { row[t] /= vocabulary.classCounts[c]; squared += row[t] * row[t]; }
    return Math.sqrt(squared);
  });
  return { idf, centroids, lengths };
}
export function predict(model: RocchioModel, document: Encoded): Prediction {
  const v = vector(document, model.idf);
  const scores = model.centroids.map((row, c) => {
    let similarity = 0;
    if (v.length > 0 && model.lengths[c] > 0) { for (const [t, value] of v.entries) similarity += value * row[t]; similarity /= v.length * model.lengths[c]; }
    return similarity;
  });
  const ranking = scores.map((_, c) => c).sort((a, b) => scores[b] - scores[a] || a - b);
  return { label: ranking[0], ranking, scores, score: scores[ranking[0]] };
}
