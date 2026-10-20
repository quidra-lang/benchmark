import { mkdirSync, writeFileSync } from 'node:fs';

export function real(value: number): string {
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.0000`;
  const text = value.toFixed(4);
  return Number(text) === 0 ? '0.0000' : text;
}
export function shadeRows(
  magnitudes: number[][],
  maximum: number,
  sampleRate: number,
  frameLength: number,
  bandDb: number,
): string[] {
  const rows: string[] = [];
  for (let k = frameLength / 2; k >= 0; k--) {
    rows.push(
      real((k * sampleRate) / frameLength).padStart(9) +
        ' |' +
        magnitudes
          .map(
            (frame) =>
              ' .:-=+*#%@'[
                Math.max(0, 9 - Math.floor((-20 * Math.log10(frame[k] / maximum)) / bandDb))
              ],
          )
          .join('') +
        '|',
    );
  }
  return rows;
}
export function writeLines(name: string, lines: string[]): void {
  mkdirSync('output', { recursive: true });
  writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
export function writeCsv(name: string, header: string, rows: (string | number)[][]): void {
  writeLines(name, [header, ...rows.map((row) => row.join(','))]);
}
