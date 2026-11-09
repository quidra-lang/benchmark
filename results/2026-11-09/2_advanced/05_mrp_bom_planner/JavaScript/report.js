const fs = require('node:fs');

function floorRatio(numerator, denominator) {
  return Number(BigInt(numerator) / BigInt(denominator));
}

function ceilRatio(numerator, denominator) {
  const n = BigInt(numerator);
  const d = BigInt(denominator);
  return Number(n / d + (n % d === 0n ? 0n : 1n));
}

function roundRatio(numerator, denominator) {
  const n = BigInt(numerator);
  const d = BigInt(denominator);
  return Number((2n * n + d) / (2n * d));
}

function money(cents) {
  const value = BigInt(cents);
  return `${value / 100n}.${String(value % 100n).padStart(2, '0')}`;
}

function percentage(quantity, capacity) {
  return roundRatio(100 * quantity, capacity);
}

function tableRow(label, values, width) {
  return label.padEnd(10, ' ') + values.map(value => String(value).padStart(width, ' ')).join('');
}

function writeReports(reports) {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : `${lines.join('\n')}\n`, 'ascii');
  }
}

module.exports = { floorRatio, ceilRatio, roundRatio, money, percentage, tableRow, writeReports };
