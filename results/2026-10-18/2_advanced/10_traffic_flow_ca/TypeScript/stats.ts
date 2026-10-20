export function floorRatio(numerator: number, denominator: number): number {
  return Number(BigInt(numerator) / BigInt(denominator));
}

export function gcd(first: number | bigint, second: number | bigint): bigint {
  let a = BigInt(first), b = BigInt(second);
  while (b !== 0n) [a, b] = [b, a % b];
  return a;
}

export function decimal(numerator: number | bigint, denominator: number | bigint, digits: number): string {
  const a = BigInt(numerator), b = BigInt(denominator);
  if (b === 0n) return '-';
  const scale = 10n ** BigInt(digits);
  const rounded = (2n * a * scale + b) / (2n * b);
  return `${rounded / scale}.${String(rounded % scale).padStart(digits, '0')}`;
}

export function fraction(numerator: number | bigint, denominator: number | bigint): string {
  const a = BigInt(numerator), b = BigInt(denominator);
  if (b === 0n) return '-';
  const divisor = gcd(a, b);
  return `${a / divisor}/${b / divisor}`;
}

export function percentile(sorted: readonly number[], percent: number): number {
  return sorted[floorRatio(percent * sorted.length + 99, 100) - 1];
}

export function histogramLines(sorted: readonly number[], width: number): string[] {
  const counts = new Map<number, number>();
  let maximum = 0;
  for (const value of sorted) {
    const bin = floorRatio(value, width);
    const count = (counts.get(bin) ?? 0) + 1;
    counts.set(bin, count);
    maximum = Math.max(maximum, count);
  }
  const lines: string[] = [];
  for (let bin = floorRatio(sorted[0], width); bin <= floorRatio(sorted[sorted.length - 1], width); bin++) {
    const count = counts.get(bin) ?? 0;
    const stars = floorRatio(80 * count + maximum, 2 * maximum);
    lines.push(`  ${bin * width}-${bin * width + width - 1} ${count}${stars > 0 ? ' ' + '*'.repeat(stars) : ''}`);
  }
  return lines;
}
