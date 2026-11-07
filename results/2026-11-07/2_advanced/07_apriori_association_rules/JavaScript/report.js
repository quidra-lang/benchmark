const fs = require('node:fs');
const { itemsetKey } = require('./baskets');

function quotient(numerator, denominator) {
  return Number(BigInt(numerator) / BigInt(denominator));
}

function fraction(value) {
  const negative = value.numerator < 0n;
  const numerator = negative ? -value.numerator : value.numerator;
  const truncated = 10000n * numerator / value.denominator;
  const decimal = `${truncated / 10000n}.${String(truncated % 10000n).padStart(4, '0')}`;
  return `${negative ? '-' : ''}${numerator}/${value.denominator}=`
    + `${negative && truncated !== 0n ? '-' : ''}${decimal}`;
}

function percentage(numerator, denominator) {
  const truncated = 10000n * BigInt(numerator) / BigInt(denominator);
  return `${truncated / 100n}.${String(truncated % 100n).padStart(2, '0')}%`;
}

function money(cents) {
  const value = BigInt(cents);
  return `${value / 100n}.${String(value % 100n).padStart(2, '0')}`;
}

function ruleLines(rules) {
  const lines = ['rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement'];
  for (const rule of rules) {
    lines.push([rule.rank, itemsetKey(rule.antecedent), itemsetKey(rule.consequent), rule.count,
      fraction(rule.support), fraction(rule.confidence), fraction(rule.lift), fraction(rule.leverage),
      rule.conviction === null ? 'INF' : fraction(rule.conviction), fraction(rule.improvement)].join(','));
  }
  return lines;
}

function writeFiles(files) {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of files) {
    fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : `${lines.join('\n')}\n`, 'ascii');
  }
}

module.exports = { quotient, fraction, percentage, money, itemset: itemsetKey, ruleLines, writeFiles };
