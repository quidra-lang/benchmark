'use strict';

const {orphans} = require('./tiles');

class Calculator {
  constructor() {
    this.suitCache = new Map();
    this.honorCache = new Map();
  }

  profile(counts, numbered) {
    const cache = numbered ? this.suitCache : this.honorCache;
    const key = counts.join('');
    if (cache.has(key)) return cache.get(key);
    // For fixed set and head counts, only the largest partial-set count can improve shanten.
    const result = Array(10).fill(-1);
    const first = counts.findIndex(count => count > 0);
    if (first === -1) result[0] = 0;
    else {
      const take = (indices, sets, head, partials) => {
        for (const index of indices) counts[index]--;
        const child = this.profile(counts, numbered);
        for (let m = 0; m + sets <= 4; m++) {
          for (let h = 0; h + head <= 1; h++) {
            const value = child[2 * m + h];
            if (value < 0) continue;
            const target = 2 * (m + sets) + h + head;
            result[target] = Math.max(result[target], value + partials);
          }
        }
        for (const index of indices) counts[index]++;
      };
      take([first], 0, 0, 0);
      if (counts[first] >= 3) take([first, first, first], 1, 0, 0);
      if (counts[first] >= 2) {
        take([first, first], 0, 1, 0);
        take([first, first], 0, 0, 1);
      }
      if (numbered) {
        if (first <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0) take([first, first + 1, first + 2], 1, 0, 0);
        for (const gap of [1, 2]) if (first + gap < 9 && counts[first + gap] > 0) take([first, first + gap], 0, 0, 1);
      }
    }
    cache.set(key, result);
    return result;
  }

  numbers(counts) {
    let combined = Array(10).fill(-1);
    combined[0] = 0;
    for (let suit = 0; suit < 4; suit++) {
      const profile = this.profile(counts.slice(9 * suit, suit === 3 ? 34 : 9 * suit + 9), suit < 3);
      const next = Array(10).fill(-1);
      for (let m = 0; m <= 4; m++) for (let h = 0; h <= 1; h++) {
        if (combined[2 * m + h] < 0) continue;
        for (let added = 0; added + m <= 4; added++) for (let head = 0; head + h <= 1; head++) {
          const partials = profile[2 * added + head];
          if (partials < 0) continue;
          const target = 2 * (m + added) + h + head;
          next[target] = Math.max(next[target], combined[2 * m + h] + partials);
        }
      }
      combined = next;
    }
    let standard = 8;
    for (let m = 0; m <= 4; m++) for (let h = 0; h <= 1; h++) {
      const partials = combined[2 * m + h];
      if (partials >= 0) standard = Math.min(standard, 8 - 2 * m - Math.min(partials, 4 - m) - h);
    }
    const pairs = counts.filter(count => count >= 2).length;
    const distinct = counts.filter(count => count > 0).length;
    const chiitoitsu = 6 - pairs + Math.max(0, 7 - distinct);
    const kokushi = 13 - orphans.filter(kind => counts[kind] > 0).length - (orphans.some(kind => counts[kind] >= 2) ? 1 : 0);
    return {standard, chiitoitsu, kokushi, minimum: Math.min(standard, chiitoitsu, kokushi)};
  }
}

module.exports = {Calculator};
