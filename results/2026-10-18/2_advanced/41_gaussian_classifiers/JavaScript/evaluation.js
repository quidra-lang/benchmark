'use strict';

function fraction(numerator, denominator) {
  if (denominator === 0) return null;
  let first = Math.abs(numerator);
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  return [numerator / first, denominator / first];
}

function addFractions(first, second) {
  return fraction(first[0] * second[1] + second[0] * first[1], first[1] * second[1]);
}

function confusion(rows, predicted, classCount) {
  const table = Array.from({ length: classCount }, () => Array(classCount).fill(0));
  rows.forEach((row, index) => { table[row.class][predicted[index]]++; });
  const support = Array(classCount).fill(0);
  const decided = Array(classCount).fill(0);
  let correct = 0;
  for (let actual = 0; actual < classCount; actual++) {
    for (let prediction = 0; prediction < classCount; prediction++) {
      support[actual] += table[actual][prediction];
      decided[prediction] += table[actual][prediction];
    }
    correct += table[actual][actual];
  }
  const classes = [];
  let recalls = [0, 1];
  let macro = 0;
  let expected = 0;
  for (let index = 0; index < classCount; index++) {
    const truePositive = table[index][index];
    const recall = fraction(truePositive, support[index]);
    classes.push({ support: support[index], recall, precision: fraction(truePositive, decided[index]),
      f1: fraction(2 * truePositive, support[index] + decided[index]) });
    recalls = addFractions(recalls, recall);
    macro += (2 * truePositive) / (support[index] + decided[index]);
    expected += support[index] * decided[index];
  }
  const count = rows.length;
  return { table, classes, correct, accuracy: fraction(correct, count),
    balanced: fraction(recalls[0], recalls[1] * classCount),
    kappa: fraction(count * correct - expected, count * count - expected), macroF1: macro / classCount };
}

function mcnemar(rows, first, second) {
  let b01 = 0;
  let b10 = 0;
  rows.forEach((row, index) => {
    const correctFirst = first[index] === row.class;
    const correctSecond = second[index] === row.class;
    if (correctFirst && !correctSecond) b01++;
    else if (!correctFirst && correctSecond) b10++;
  });
  const difference = Math.abs(b01 - b10) - 1;
  const chi2 = b01 === b10 ? 0 : difference * difference / (b01 + b10);
  return { b01, b10, chi2, significant: chi2 > 3.841 };
}

class Random {
  constructor(seed) {
    this.state = seed;
  }

  next() {
    this.state = 48271 * this.state % 2147483647;
    return this.state;
  }
}

module.exports = { fraction, addFractions, confusion, mcnemar, Random };
