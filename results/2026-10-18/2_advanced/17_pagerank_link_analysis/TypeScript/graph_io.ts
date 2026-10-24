import { readFileSync } from 'node:fs';

export interface Page {
  id: number;
  host: string;
  title: string;
  words: Set<string>;
}
export interface LinkRecord {
  source: number;
  destination: number;
  line: number;
}
export interface Query {
  words: string[];
  seeds: number[];
}
export interface Settings {
  damping: number;
  iterations: number;
  tolerance: number;
  sweep: number[];
  trusted: number[];
  spamTop: number;
  spamThreshold: number;
  hitsIterations: number;
  top: number;
  rootLimit: number;
  neighborLimit: number;
}
export interface Input {
  pages: Page[];
  records: LinkRecord[];
  queries: Query[];
  settings: Settings;
}
const readLines = (path: string) => readFileSync(path, 'ascii').slice(0, -1).split('\n');

export function readInput(): Input {
  const pages = readLines('input/pages.csv')
    .slice(1)
    .map((line) => {
      const [id, host, title] = line.split(',');
      return { id: Number(id), host, title, words: new Set(title.split(' ')) };
    })
    .sort((first, second) => first.id - second.id);
  const records = readLines('input/links.csv')
    .slice(1)
    .map((line, index) => {
      const [source, destination] = line.split(',').map(Number);
      return { source, destination, line: index + 2 };
    });
  const queries = readLines('input/queries.txt').map((line) => {
    const [words, seeds] = line.split(' | ');
    return { words: words.split(' '), seeds: seeds.split(' ').map(Number) };
  });
  const params = new Map(
    readLines('input/params.txt').map((line) => {
      const [name, ...values] = line.split(' ');
      return [name, values.map(Number)];
    }),
  );
  const values = (name: string) => params.get(name)!;
  const first = (name: string) => values(name)[0];
  const settings: Settings = {
    damping: first('DAMPING'),
    iterations: first('PAGERANK_ITERATIONS'),
    tolerance: first('TOLERANCE'),
    sweep: values('DAMPING_SWEEP'),
    trusted: values('TRUSTED'),
    spamTop: first('SPAM_TOP'),
    spamThreshold: first('SPAM_THRESHOLD'),
    hitsIterations: first('HITS_ITERATIONS'),
    top: first('TOP_K'),
    rootLimit: first('ROOT_LIMIT'),
    neighborLimit: first('NEIGHBOR_LIMIT'),
  };
  return { pages, records, queries, settings };
}
