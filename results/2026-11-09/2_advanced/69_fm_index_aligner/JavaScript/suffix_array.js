'use strict';

const SYMBOLS = '$#ACGT';

function countingSort(positions, key, classes) {
  const counts = Array(classes).fill(0), offsets = Array(classes).fill(0), result = Array(positions.length);
  for (const position of positions) counts[key(position)]++;
  for (let i = 1; i < classes; i++) offsets[i] = offsets[i - 1] + counts[i - 1];
  for (const position of positions) result[offsets[key(position)]++] = position;
  return result;
}

function build(text) {
  const positions = Array.from({ length: text.length }, (_, i) => i);
  let order = countingSort(positions, i => SYMBOLS.indexOf(text[i]), 6), rank = Array(text.length), classes = 0;
  for (let i = 0; i < order.length; i++) {
    if (i === 0 || text[order[i]] !== text[order[i - 1]]) classes++;
    rank[order[i]] = classes - 1;
  }
  const rounds = [classes];
  let prefix = 1;
  while (classes < text.length) {
    const second = i => i + prefix < text.length ? rank[i + prefix] + 1 : 0;
    order = countingSort(countingSort(positions, second, classes + 1), i => rank[i], classes);
    const next = Array(text.length);
    let count = 0;
    for (let i = 0; i < order.length; i++) {
      if (i === 0 || rank[order[i]] !== rank[order[i - 1]] || second(order[i]) !== second(order[i - 1])) count++;
      next[order[i]] = count - 1;
    }
    rank = next; classes = count; rounds.push(classes); prefix *= 2;
  }
  return { sa: order, rounds };
}

function check(text, sa) {
  let ordered = 0, lcpSum = 0, maximum = -1, row = 1;
  const lcp = [0];
  for (let i = 1; i < sa.length; i++) {
    let length = 0;
    while (text[sa[i - 1] + length] === text[sa[i] + length]) length++;
    if (SYMBOLS.indexOf(text[sa[i - 1] + length]) < SYMBOLS.indexOf(text[sa[i] + length])) ordered++;
    lcp.push(length); lcpSum += length;
    if (length > maximum) { maximum = length; row = i; }
  }
  return { ordered, lcp, lcpSum, maximum, row };
}

function direct(text) {
  return Array.from({ length: text.length }, (_, i) => i).sort((a, b) => {
    const first = text.slice(a), second = text.slice(b);
    return first < second ? -1 : first > second ? 1 : 0;
  });
}

module.exports = { SYMBOLS, countingSort, build, check, direct };
