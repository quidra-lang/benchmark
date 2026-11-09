'use strict';

const {digits} = require('./protocol');

function items(mode, argumentsList) {
  let sign = '+';
  let next = 0;
  const result = [];
  const take = () => next < argumentsList.length ? argumentsList[next++] : undefined;
  for (const character of mode) {
    if (character === '+' || character === '-') {
      sign = character;
      continue;
    }
    let argument;
    if ('ovb'.includes(character)) argument = take();
    else if (character === 'k') {
      argument = take();
      if (sign === '-') argument = '*';
    } else if (character === 'l' && sign === '+') {
      const candidate = take();
      if (candidate !== undefined && candidate.length <= 4 &&
          digits(candidate) && Number(candidate) >= 1) argument = candidate;
    }
    result.push({sign, character, argument});
  }
  return result;
}

function changeString(changes) {
  let result = '';
  let previousSign = null;
  const argumentsList = [];
  for (const change of changes) {
    if (change.sign !== previousSign) {
      result += change.sign;
      previousSign = change.sign;
    }
    result += change.character;
    if (change.argument !== undefined) argumentsList.push(change.argument);
  }
  for (const argument of argumentsList) result += ` ${argument}`;
  return result;
}

module.exports = {items, changeString};
