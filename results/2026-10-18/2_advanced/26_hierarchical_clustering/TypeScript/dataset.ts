import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';

export interface Observation {
  id: string;
  label: string;
  values: number[];
}

function readLines(path: string): string[] {
  return readFileSync(path, 'ascii').trimEnd().split('\n');
}

export function readDataset() {
  const lines = readLines('input/data.csv');
  const features = lines[0].split(',').slice(2);
  const observations: Observation[] = lines.slice(1).map((line) => {
    const [id, label, ...values] = line.split(',');
    return { id, label, values: values.map(Number) };
  });
  const parameters = new Map(
    readLines('input/params.txt').map((line) => {
      const [name, ...values] = line.split(' ');
      return [name, values];
    }),
  );
  return { features, observations, parameters };
}

export function writeReports(reports: Record<string, string[]>): void {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
  }
}
