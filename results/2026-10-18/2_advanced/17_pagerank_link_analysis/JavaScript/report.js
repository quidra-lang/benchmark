const fs = require('node:fs');

function real(value, digits = 6) {
  const text = value.toFixed(digits);
  return Number(text) === 0 ? (0).toFixed(digits) : text;
}

function roundedInteger(value, digits = 6) {
  return Number(real(value, digits).replace('.', ''));
}

function fraction(numerator, denominator) {
  let first = Math.abs(numerator);
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  const top = numerator / first;
  const bottom = denominator / first;
  return `${top}/${bottom} ${real(top / bottom, 4)}`;
}

function writeReports(reports) {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
}

module.exports = { real, roundedInteger, fraction, writeReports };
