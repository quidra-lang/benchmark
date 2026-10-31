'use strict';

function letterValue(character) {
  const code = character.charCodeAt(0);
  if (code >= 65 && code <= 90) return code - 65;
  if (code >= 97 && code <= 122) return code - 97;
  return -1;
}

function letterString(text) {
  const letters = [];
  for (const character of text) {
    const value = letterValue(character);
    if (value >= 0) letters.push(String.fromCharCode(65 + value));
  }
  return letters.join('');
}

function parseWeights(text) {
  const lines = text.split('\n');
  return {
    monograms: lines[1].split(' ').map(Number),
    bigrams: lines.slice(3, 29).map(line => line.split(' ').map(Number)),
  };
}

function monogramFitness(text, weights) {
  let score = 0;
  for (let index = 0; index < text.length; index++) {
    score += weights.monograms[text.charCodeAt(index) - 65];
  }
  return score;
}

function bigramFitness(text, weights) {
  let score = 0;
  for (let index = 1; index < text.length; index++) {
    score += weights.bigrams[text.charCodeAt(index - 1) - 65]
      [text.charCodeAt(index) - 65];
  }
  return score;
}

module.exports = {letterValue, letterString, parseWeights, monogramFitness, bigramFitness};
