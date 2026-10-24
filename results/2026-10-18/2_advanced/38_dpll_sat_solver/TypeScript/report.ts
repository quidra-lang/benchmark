import { writeFileSync } from 'node:fs';

export function items(prefix: string, values: Record<string, string | number>): string {
  return (
    prefix +
    ' ' +
    Object.entries(values)
      .map(([name, value]) => `${name}=${value}`)
      .join(' ')
  );
}
export function numberList(values: number[]): string {
  return values.length ? values.join(',') : '-';
}
export function frequencyList(values: number[]): string {
  const counts = new Map<number, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return counts.size
    ? [...counts]
        .sort((a, b) => a[0] - b[0])
        .map(([value, count]) => `${value}:${count}`)
        .join(',')
    : '-';
}
export function boardLines(columns: number[]): string[] {
  return columns.map((c) => '.'.repeat(c - 1) + 'Q' + '.'.repeat(columns.length - c));
}
export function writeParagraphs(filename: string, paragraphs: string[][]): void {
  writeFileSync(
    `output/${filename}`,
    paragraphs.length ? paragraphs.map((lines) => lines.join('\n')).join('\n\n') + '\n' : '',
    'ascii',
  );
}
export function writeCsv(filename: string, rows: (string | number)[][]): void {
  writeFileSync(`output/${filename}`, rows.map((row) => row.join(',')).join('\n') + '\n', 'ascii');
}
