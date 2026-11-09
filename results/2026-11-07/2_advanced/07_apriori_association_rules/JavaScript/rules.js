const { compareItemsets, itemsetKey } = require('./baskets');

class Fraction {
  constructor(numerator, denominator = 1) {
    let n = BigInt(numerator);
    let d = BigInt(denominator);
    if (d < 0n) [n, d] = [-n, -d];
    let first = n < 0n ? -n : n;
    let second = d;
    while (second !== 0n) [first, second] = [second, first % second];
    this.numerator = n / first;
    this.denominator = d / first;
  }

  compare(other) {
    const difference = this.numerator * other.denominator - other.numerator * this.denominator;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }

  subtract(other) {
    return new Fraction(this.numerator * other.denominator - other.numerator * this.denominator,
      this.denominator * other.denominator);
  }

  multiply(other) {
    return new Fraction(this.numerator * other.numerator, this.denominator * other.denominator);
  }

  negate() {
    return new Fraction(-this.numerator, this.denominator);
  }
}

function createRule(antecedent, consequent, countX, countY, count, total) {
  return {
    antecedent, consequent, count,
    support: new Fraction(count, total),
    confidence: new Fraction(count, countX),
    lift: new Fraction(total * count, countX * countY),
    leverage: new Fraction(total * count - countX * countY, total * total),
    conviction: countX === count ? null : new Fraction((total - countY) * countX, total * (countX - count)),
  };
}

function passes(rule, confidence, lift) {
  return rule.confidence.compare(confidence) >= 0 && rule.lift.compare(lift) >= 0;
}

function compareRules(first, second) {
  return second.confidence.compare(first.confidence) || second.lift.compare(first.lift)
    || second.count - first.count || compareItemsets(first.antecedent, second.antecedent)
    || compareItemsets(first.consequent, second.consequent);
}

function ruleKey(rule) {
  return `${itemsetKey(rule.antecedent)}->${itemsetKey(rule.consequent)}`;
}

module.exports = { Fraction, createRule, passes, compareRules, ruleKey };
