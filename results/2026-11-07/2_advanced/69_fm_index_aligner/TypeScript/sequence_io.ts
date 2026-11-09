import { readFileSync } from 'node:fs';

export interface Reference {
  name: string;
  sequence: string;
  masked: number;
  offset: number;
}

export interface Read {
  name: string;
  sequence: string;
  quality: string;
  qualities: number[];
  length: number;
  trimmed: number;
}

export interface Parameters {
  MAX_MISMATCHES: number;
  MIN_READ_LENGTH: number;
  TRIM_QUALITY: number;
  SEED_LENGTH: number;
  SEED_STEP: number;
  MAX_SEED_HITS: number;
  BAND_WIDTH: number;
  SCORES: [number, number, number, number];
  MIN_SCORE_PERCENT: number;
  MAX_ALT_HITS: number;
  OCC_INTERVAL: number;
  SA_SAMPLE_INTERVAL: number;
  DIRECT_SORT_LIMIT: number;
  COVERAGE_WINDOW: number;
  COVERAGE_MIN_MAPQ: number;
  VARIANTS: [number, number, number, number];
}

const lines = (path: string): string[] => readFileSync(path, 'ascii').slice(0, -1).split('\n');

export function read(): { references: Reference[]; reads: Read[]; params: Parameters } {
  const references: Reference[] = [];
  for (const line of lines('input/reference.fasta')) {
    if (line.startsWith('>')) {
      references.push({ name: line.slice(1).split(' ')[0], sequence: '', masked: 0, offset: 0 });
    } else {
      const reference = references[references.length - 1];
      for (const base of line) if (base >= 'a' && base <= 'z') reference.masked++;
      reference.sequence += line.toUpperCase();
    }
  }
  const records = lines('input/reads.fastq');
  const reads: Read[] = [];
  for (let i = 0; i < records.length; i += 4) {
    reads.push({
      name: records[i].slice(1),
      sequence: records[i + 1],
      quality: records[i + 3],
      qualities: [...records[i + 3]].map(character => character.charCodeAt(0) - 33),
      length: records[i + 1].length,
      trimmed: 0,
    });
  }
  const settings = new Map(lines('input/params.txt').map((line): [string, number[]] => {
    const [key, ...values] = line.split(' ');
    return [key, values.map(Number)];
  }));
  const value = (key: string): number => settings.get(key)![0];
  const tuple = (key: string): [number, number, number, number] => {
    const values = settings.get(key)!;
    return [values[0], values[1], values[2], values[3]];
  };
  return { references, reads, params: {
    MAX_MISMATCHES: value('MAX_MISMATCHES'),
    MIN_READ_LENGTH: value('MIN_READ_LENGTH'),
    TRIM_QUALITY: value('TRIM_QUALITY'),
    SEED_LENGTH: value('SEED_LENGTH'),
    SEED_STEP: value('SEED_STEP'),
    MAX_SEED_HITS: value('MAX_SEED_HITS'),
    BAND_WIDTH: value('BAND_WIDTH'),
    SCORES: tuple('SCORES'),
    MIN_SCORE_PERCENT: value('MIN_SCORE_PERCENT'),
    MAX_ALT_HITS: value('MAX_ALT_HITS'),
    OCC_INTERVAL: value('OCC_INTERVAL'),
    SA_SAMPLE_INTERVAL: value('SA_SAMPLE_INTERVAL'),
    DIRECT_SORT_LIMIT: value('DIRECT_SORT_LIMIT'),
    COVERAGE_WINDOW: value('COVERAGE_WINDOW'),
    COVERAGE_MIN_MAPQ: value('COVERAGE_MIN_MAPQ'),
    VARIANTS: tuple('VARIANTS'),
  } };
}

export function reverseComplement(sequence: string): string {
  const complements: Record<string, string> = { A: 'T', C: 'G', G: 'C', T: 'A', N: 'N' };
  return [...sequence].reverse().map(base => complements[base]).join('');
}
