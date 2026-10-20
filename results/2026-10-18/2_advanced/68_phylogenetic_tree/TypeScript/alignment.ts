import { readFileSync } from 'node:fs';
export const bases = 'ACGT';
export const baseSets: Readonly<Record<string, number>> = {
  A: 1, C: 2, G: 4, T: 8, R: 5, Y: 10, S: 6, W: 9, K: 12, M: 3, B: 14, D: 13, H: 11, V: 7, N: 15, '-': 15
};
export interface FastaRecord { name: string; sequence: string; line: number }
export function readFasta(): FastaRecord[] {
  const records: FastaRecord[] = [];
  readFileSync('input/alignment.fasta', 'ascii').slice(0, -1).split('\n').forEach((line, i) => {
    if (line.startsWith('>')) records.push({ name: line.slice(1).split(' ')[0], sequence: '', line: i + 1 });
    else records[records.length - 1].sequence += line.toUpperCase();
  });
  return records;
}
export function patterns(sequences: string[]) {
  const groups = new Map<string, number[]>();
  for (let c = 0; c < sequences[0].length; c++) {
    const pattern = sequences.map(s => s[c]).join(''), columns = groups.get(pattern);
    if (columns) columns.push(c); else groups.set(pattern, [c]);
  }
  return [...groups].map(([pattern, columns]) => ({ pattern, columns }));
}
export function classify(pattern: string) {
  const counts = [...bases].map(base => [...pattern].filter(c => c === base).length), kinds = counts.filter(n => n > 0).length;
  return { counts, empty: kinds === 0, constant: kinds === 1, variable: kinds >= 2,
    informative: counts.filter(n => n >= 2).length >= 2, gapped: pattern.includes('-') };
}
