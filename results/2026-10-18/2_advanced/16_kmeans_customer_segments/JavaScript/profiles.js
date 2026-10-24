'use strict';

const fs = require('node:fs');
const { FEATURES, SQUARE_ROOT } = require('./features');

function readRules() {
  return fs.readFileSync('input/segment_rules.txt', 'ascii').split('\n').slice(0, -1).map(line => {
    const [name, ...words] = line.split(' '), conditions = [];
    for (let index = 0; index < words.length; index += 3) {
      conditions.push({ feature: FEATURES.indexOf(words[index]), comparison: words[index + 1], threshold: Number(words[index + 2]) });
    }
    return { name, conditions };
  });
}

function matchingRule(center, rules) {
  return rules.findIndex(rule => rule.conditions.every(condition => condition.comparison === '>'
    ? center[condition.feature] > condition.threshold : center[condition.feature] < condition.threshold));
}

function originalCenter(center, scaling) {
  return center.map((coordinate, feature) => {
    const value = scaling[feature].mean + scaling[feature].sd * coordinate;
    return SQUARE_ROOT.has(feature) ? value * value : value;
  });
}

module.exports = { readRules, matchingRule, originalCenter };
