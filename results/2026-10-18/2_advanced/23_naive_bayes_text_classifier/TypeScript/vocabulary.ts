import type { Document, LabelledDocument, TermKind } from './tokenizer.ts';
export interface Term { term: string; df: number; perClass: number[]; chiSquare: number; bestClass: number }
export interface Vocabulary {
  kind: TermKind; terms: Term[]; indices: Map<string, number>; ranking: Term[]; candidateCount: number;
  termCount: number; classCounts: number[]; documentCount: number;
}
export interface Encoded { sequence: number[]; first: number[]; counts: Map<number, number> }
export function compareText(a: string, b: string): number { return a < b ? -1 : a > b ? 1 : 0; }
export function buildVocabulary(documents: LabelledDocument[], classCount: number, minimum: number, limit: number, kind: TermKind): Vocabulary {
  const counts = new Map<string, Term>(), classCounts: number[] = Array(classCount).fill(0);
  for (const doc of documents) {
    classCounts[doc.label]++;
    for (const term of new Set(doc.tokens[kind])) {
      let entry = counts.get(term);
      if (!entry) { entry = { term, df: 0, perClass: Array(classCount).fill(0), chiSquare: 0, bestClass: 0 }; counts.set(term, entry); }
      entry.df++; entry.perClass[doc.label]++;
    }
  }
  const candidates = [...counts.values()].filter(t => t.df >= minimum), m = documents.length;
  for (const entry of candidates) for (let c = 0; c < classCount; c++) {
    const a = entry.perClass[c], b = entry.df - a, absent = classCounts[c] - a, otherAbsent = m - classCounts[c] - b;
    const det = a * otherAbsent - b * absent, x = m * (det * det), y = entry.df * (m - entry.df) * classCounts[c] * (m - classCounts[c]);
    const value = y === 0 ? 0 : x / y;
    if (value > entry.chiSquare) { entry.chiSquare = value; entry.bestClass = c; }
  }
  candidates.sort((a, b) => b.chiSquare - a.chiSquare || compareText(a.term, b.term));
  const ranking = limit > 0 ? candidates.slice(0, limit) : candidates, terms = [...ranking].sort((a, b) => compareText(a.term, b.term));
  return { kind, terms, indices: new Map(terms.map((t, i) => [t.term, i])), ranking, candidateCount: candidates.length,
    termCount: counts.size, classCounts, documentCount: m };
}
export function encode(document: Document, vocabulary: Vocabulary): Encoded {
  const sequence: number[] = [], counts = new Map<number, number>();
  for (const term of document.tokens[vocabulary.kind]) {
    const i = vocabulary.indices.get(term);
    if (i === undefined) continue;
    sequence.push(i); counts.set(i, (counts.get(i) ?? 0) + 1);
  }
  return { sequence, first: [...counts.keys()], counts };
}
