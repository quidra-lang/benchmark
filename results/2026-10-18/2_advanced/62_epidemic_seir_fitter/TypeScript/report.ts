export function real(value: number | null, digits = 4): string {
  if (value === null) return '-';
  if (Math.abs(value) >= 1e21) return BigInt(value) + '.' + '0'.repeat(digits);
  const text = value.toFixed(digits);
  return Number(text) === 0 ? (0).toFixed(digits) : text;
}
export function curvePlot(observed: number[], fitted: number[]): string[] {
  const count = observed.length;
  const maximum = Math.max(...observed);
  const width = String(maximum).length;
  const canvas = Array.from({ length: 20 }, () => Array<string>(70).fill('.'));
  const dayIndex = (x: number) => Math.floor((x * (count - 1)) / 69);
  for (let x = 0; x < 70; x++) {
    const day = dayIndex(x);
    const o = Math.min(19, Math.floor((20 * observed[day]) / maximum));
    const f = Math.min(19, Math.floor((20 * fitted[day]) / maximum));
    canvas[o][x] = o === f ? '#' : 'o';
    if (f !== o) canvas[f][x] = '*';
  }
  const lines = [`plot observed o fitted * both # days 1 ${count} max ${maximum}`];
  for (let y = 19; y >= 0; y--) {
    lines.push(`${String(Math.floor((maximum * y) / 20)).padStart(width)} |${canvas[y].join('')}`);
  }
  lines.push(
    ' '.repeat(width + 1) +
      '+' +
      Array.from({ length: 70 }, (_, x) => (x % 10 === 0 ? '+' : '-')).join(''),
  );
  const labels = Array<string>(70).fill(' ');
  for (let x = 0; x <= 60; x += 10) {
    const label = String(dayIndex(x) + 1);
    for (let i = 0; i < label.length; i++) labels[x + i] = label[i];
  }
  return [...lines, (' '.repeat(width + 2) + labels.join('')).trimEnd()];
}
