'use strict';

class Dictionary {
  constructor(lines, additions) {
    this.words = new Map();
    for (const line of [...lines, ...additions]) {
      let word = '';
      const points = [];
      for (const character of line) {
        if (character === '-') points.push(word.length);
        else word += character;
      }
      this.words.set(word, points);
    }
  }

  splitPoints(word, leftMinimum, rightMinimum) {
    const points = [];
    let first = 0;
    let last = word.length;
    while (first < last && !/[A-Za-z]/.test(word[first])) first++;
    while (last > first && !/[A-Za-z]/.test(word[last - 1])) last--;
    const core = word.slice(first, last);
    if (/^[A-Za-z]+$/.test(core)) {
      for (const position of this.words.get(core.toLowerCase()) ?? []) {
        if (position >= leftMinimum && core.length - position >= rightMinimum) {
          points.push({ position: first + position, hyphen: true });
        }
      }
    }
    for (let index = 1; index + 1 < word.length; index++) {
      if (word[index] === '-' && /[A-Za-z]/.test(word[index - 1]) && /[A-Za-z]/.test(word[index + 1])) {
        points.push({ position: index + 1, hyphen: false });
      }
    }
    return points.sort((a, b) => a.position - b.position);
  }
}

module.exports = { Dictionary };
