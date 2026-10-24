const { itemsetKey } = require('./baskets');

class SupportCounter {
  constructor(baskets) {
    this.size = baskets.length;
    this.index = new Map();
    this.cache = new Map([['', baskets.length]]);
    baskets.forEach((basket, number) => {
      for (const item of basket) {
        if (!this.index.has(item)) this.index.set(item, new Set());
        this.index.get(item).add(number);
      }
    });
  }

  count(items) {
    const key = itemsetKey(items);
    if (this.cache.has(key)) return this.cache.get(key);
    const lists = items.map(item => this.index.get(item));
    let count = 0;
    if (lists.every(list => list !== undefined)) {
      lists.sort((first, second) => first.size - second.size);
      for (const number of lists[0]) {
        if (lists.every(list => list.has(number))) count += 1;
      }
    }
    this.cache.set(key, count);
    return count;
  }
}

function candidates(previous, categories = null) {
  const known = new Set(previous.map(itemsetKey));
  const prefixLength = previous[0].length - 1;
  const kept = [];
  let generated = 0;
  let excluded = 0;
  let pruned = 0;
  for (let first = 0; first < previous.length; first += 1) {
    for (let second = first + 1; second < previous.length; second += 1) {
      const left = previous[first];
      const right = previous[second];
      if (!left.slice(0, prefixLength).every((item, index) => item === right[index])) break;
      const joined = [...left, right.at(-1)];
      generated += 1;
      if (categories !== null && joined.length === 2
          && (categories.get(joined[0]) === joined[1] || categories.get(joined[1]) === joined[0])) {
        excluded += 1;
        continue;
      }
      if (joined.some((item, index) => !known.has(itemsetKey(joined.filter((value, position) => position !== index))))) {
        pruned += 1;
        continue;
      }
      kept.push(joined);
    }
  }
  return { items: kept, candidates: generated, excluded, pruned, counted: kept.length };
}

function countCandidates(items, counter, minimum) {
  const frequent = [];
  for (const itemset of items) {
    const count = counter.count(itemset);
    if (count >= minimum) frequent.push({ items: itemset, count });
  }
  return frequent;
}

module.exports = { SupportCounter, candidates, countCandidates };
