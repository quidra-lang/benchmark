'use strict';

const fs = require('fs');

function sign(value) { return value > 0 ? 1 : -1; }

function fixed(value, digits) {
  if (Math.abs(value) >= 1e21) {
    return (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString() + '.' + '0'.repeat(digits);
  }
  const text = value.toFixed(digits);
  return Number(text) === 0 && text[0] === '-' ? text.slice(1) : text;
}

function ratio(a, b) { return b > 0 ? fixed(a / b, 4) : '-'; }

function folds(count, k) {
  return Array.from({ length: k }, (_, fold) => {
    const train = [], test = [];
    for (let i = 0; i < count; i++) (i % k === fold ? test : train).push(i);
    return { train, test };
  });
}

function binary(labels, decisions) {
  let tp = 0, fp = 0, tn = 0, fn = 0;
  for (let i = 0; i < labels.length; i++) {
    if (sign(decisions[i]) === 1) {
      if (labels[i] === 1) tp++; else fp++;
    } else if (labels[i] === -1) tn++; else fn++;
  }
  return { tp, fp, tn, fn, correct: tp + tn };
}

function auc(labels, decisions) {
  let sum = 0, positives = 0, negatives = 0;
  for (const label of labels) { if (label === 1) positives++; else negatives++; }
  for (let i = 0; i < labels.length; i++) if (labels[i] === 1) {
    for (let j = 0; j < labels.length; j++) if (labels[j] === -1) {
      if (decisions[i] > decisions[j]) sum += 1;
      else if (decisions[i] === decisions[j]) sum += 0.5;
    }
  }
  return sum / (positives * negatives);
}

function confusion(classes, predictions) {
  const counts = Array.from({ length: 3 }, () => [0, 0, 0]);
  for (let i = 0; i < classes.length; i++) counts[classes[i] - 1][predictions[i] - 1]++;
  return counts;
}

function write(path, lines) {
  fs.writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

module.exports = { sign, fixed, ratio, folds, binary, auc, confusion, write };
