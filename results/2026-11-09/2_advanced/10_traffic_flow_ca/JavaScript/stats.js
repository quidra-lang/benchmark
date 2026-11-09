function floorRatio(numerator, denominator) {
  return Number(BigInt(numerator) / BigInt(denominator));
}

function gcd(first, second) {
  let a = BigInt(first);
  let b = BigInt(second);
  while (b !== 0n) [a, b] = [b, a % b];
  return a;
}

function decimal(numerator, denominator, digits) {
  const a = BigInt(numerator);
  const b = BigInt(denominator);
  if (b === 0n) return '-';
  const scale = 10n ** BigInt(digits);
  const rounded = (2n * a * scale + b) / (2n * b);
  return `${rounded / scale}.${String(rounded % scale).padStart(digits, '0')}`;
}

function fraction(numerator, denominator) {
  const a = BigInt(numerator);
  const b = BigInt(denominator);
  if (b === 0n) return '-';
  const divisor = gcd(a, b);
  return `${a / divisor}/${b / divisor}`;
}

function percentile(sorted, percent) {
  return sorted[floorRatio(percent * sorted.length + 99, 100) - 1];
}

function histogramLines(sorted, width) {
  const counts = new Map();
  let maximum = 0;
  for (const value of sorted) {
    const bin = floorRatio(value, width);
    const count = (counts.get(bin) ?? 0) + 1;
    counts.set(bin, count);
    maximum = Math.max(maximum, count);
  }
  const lines = [];
  const first = floorRatio(sorted[0], width);
  const last = floorRatio(sorted.at(-1), width);
  for (let bin = first; bin <= last; bin += 1) {
    const count = counts.get(bin) ?? 0;
    const stars = floorRatio(80 * count + maximum, 2 * maximum);
    lines.push(`  ${bin * width}-${bin * width + width - 1} ${count}${stars > 0 ? ' ' + '*'.repeat(stars) : ''}`);
  }
  return lines;
}

module.exports = { floorRatio, gcd, decimal, fraction, percentile, histogramLines };
