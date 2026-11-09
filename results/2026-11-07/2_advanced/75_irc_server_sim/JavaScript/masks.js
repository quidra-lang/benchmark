'use strict';

const {fold} = require('./protocol');

function matches(mask, text) {
  const pattern = fold(mask);
  const value = fold(text);
  let patternIndex = 0;
  let valueIndex = 0;
  let star = -1;
  let retry = 0;
  while (valueIndex < value.length) {
    if (patternIndex < pattern.length && pattern[patternIndex] !== '*' &&
        (pattern[patternIndex] === '?' || pattern[patternIndex] === value[valueIndex])) {
      patternIndex++;
      valueIndex++;
    } else if (pattern[patternIndex] === '*') {
      star = patternIndex++;
      retry = valueIndex;
    } else if (star >= 0) {
      patternIndex = star + 1;
      valueIndex = ++retry;
    } else return false;
  }
  while (pattern[patternIndex] === '*') patternIndex++;
  return patternIndex === pattern.length;
}

function normalize(text) {
  const bang = text.includes('!');
  const at = text.includes('@');
  if (bang && at) return text;
  if (at) return `*!${text}`;
  if (bang) return `${text}@*`;
  return text.includes('.') ? `*!*@${text}` : `${text}!*@*`;
}

module.exports = {matches, normalize};
