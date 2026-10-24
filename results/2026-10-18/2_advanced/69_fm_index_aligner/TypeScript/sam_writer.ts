import { writeFileSync } from 'node:fs';
import { reverseComplement, type Read, type Reference } from './sequence_io.ts';

export interface Alignment {
  r: number;
  pos: number;
  strand: number;
  ops: string;
}

export interface DescribedAlignment extends Alignment {
  runs: { operation: 'M' | 'I' | 'D'; length: number }[];
  pairs: { refPos: number; base: string; reference: string; cycle: number; quality: number; match: boolean }[];
  cigar: string;
  md: string;
  nm: number;
}

export type MappingResult<A extends Alignment = Alignment> =
  | { reason: 'SHORT' | 'NOHIT' }
  | { reason?: undefined; alignments: A[]; mapq: number; score: number; x0: number; x1: number; method: 'EXACT' | 'MISMATCH' | 'SEED' };

export function ratio(numerator: number, denominator: number): string {
  return denominator === 0 ? '-' : (numerator / denominator).toFixed(4);
}

export function header(references: Reference[]): string[] {
  return [
    '@HD\tVN:1.6\tSO:unsorted',
    ...references.map(reference => `@SQ\tSN:${reference.name}\tLN:${reference.sequence.length}`),
    '@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0',
  ];
}

export function record(read: Read, result: MappingResult<DescribedAlignment>, references: Reference[], maximumAlternatives: number): string {
  if (result.reason) {
    return [read.name, 4, '*', 0, 0, '*', '*', 0, 0, read.sequence, read.quality, `YM:Z:${result.reason}`].join('\t');
  }
  const primary = result.alignments[0], reverse = primary.strand === 1;
  const fields = [
    read.name, reverse ? 16 : 0, references[primary.r].name, primary.pos + 1, result.mapq,
    primary.cigar, '*', 0, 0, reverse ? reverseComplement(read.sequence) : read.sequence,
    reverse ? [...read.quality].reverse().join('') : read.quality,
    `NM:i:${primary.nm}`, `MD:Z:${primary.md}`, `AS:i:${result.score}`,
    `X0:i:${result.x0}`, `X1:i:${result.x1}`, `YM:Z:${result.method}`,
  ];
  const alternatives = result.alignments.slice(1);
  if (alternatives.length > 0 && alternatives.length <= maximumAlternatives) {
    fields.push('XA:Z:' + alternatives.map(alignment =>
      `${references[alignment.r].name},${alignment.strand === 0 ? '+' : '-'}${alignment.pos + 1},${alignment.cigar},${alignment.nm};`,
    ).join(''));
  }
  return fields.join('\t');
}

export function write(path: string, lines: string[]): void {
  writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
