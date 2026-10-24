const fs = require('node:fs');

function real(value, digits = 4) {
  const text = value.toFixed(digits);
  return Number(text) === 0 ? (0).toFixed(digits) : text;
}

function decimalValue(value, digits = 4) {
  return Number(real(value, digits));
}

function fraction(numerator, denominator) {
  if (denominator < 0) {
    numerator = -numerator;
    denominator = -denominator;
  }
  let first = Math.abs(numerator);
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  return [numerator / first, denominator / first];
}

function fractionText(value) {
  return `${value[0]}/${value[1]}`;
}

function fractionReal(value, digits = 4) {
  const numerator = BigInt(Math.abs(value[0])) * 10n ** BigInt(digits);
  const denominator = BigInt(value[1]);
  let rounded = numerator / denominator;
  if (2n * (numerator % denominator) >= denominator) rounded += 1n;
  const text = rounded.toString().padStart(digits + 1, '0');
  const sign = value[0] < 0 && rounded !== 0n ? '-' : '';
  if (digits === 0) return sign + text;
  return sign + text.slice(0, -digits) + '.' + text.slice(-digits);
}

function writeReports(reports) {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
  }
}

module.exports = { real, decimalValue, fraction, fractionText, fractionReal, writeReports };
