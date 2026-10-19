const fs = require('node:fs');

function floorRatio(numerator, denominator) {
  return Number(BigInt(numerator) / BigInt(denominator));
}

function ceilRatio(numerator, denominator) {
  const a = BigInt(numerator);
  const b = BigInt(denominator);
  return Number((a + b - 1n) / b);
}

function percentage(numerator, denominator) {
  const a = BigInt(numerator);
  const b = BigInt(denominator);
  return Number((200n * a + b) / (2n * b));
}

function tableLine(label, values, labelWidth, columnWidth) {
  return label.padEnd(labelWidth) + values.map(value => String(value).padStart(columnWidth)).join('');
}

function writeReports(reports) {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
}

module.exports = { floorRatio, ceilRatio, percentage, tableLine, writeReports };
