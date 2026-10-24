'use strict';

function countLetters(text) {
  const counts = Array(26).fill(0);
  for (let index = 0; index < text.length; index++) {
    counts[text.charCodeAt(index) - 65]++;
  }
  return counts;
}

function coincidence(text) {
  let numerator = 0;
  for (const count of countLetters(text)) numerator += count * (count - 1);
  return Math.floor(100000 * numerator / (text.length * (text.length - 1)));
}

function columns(text, period) {
  const result = Array(period).fill('');
  for (let index = 0; index < text.length; index++) {
    result[index % period] += text[index];
  }
  return result;
}

function periodStatistics(text, maximum, examination) {
  const table = [];
  for (let period = 1; period <= maximum; period++) {
    const indices = columns(text, period).map(coincidence);
    let total = 0;
    for (const value of indices) total += value;
    let divisible = 0;
    for (const gap of examination.gaps) {
      if (gap % period === 0) divisible++;
    }
    table.push({period, indices, average: Math.floor(total / period), divisible});
  }
  return table;
}

function gcd(left, right) {
  while (right !== 0) {
    const remainder = left % right;
    left = right;
    right = remainder;
  }
  return left;
}

function kasiski(text) {
  const positions = new Map();
  for (let index = 0; index + 2 < text.length; index++) {
    const trigram = text.slice(index, index + 3);
    if (!positions.has(trigram)) positions.set(trigram, []);
    positions.get(trigram).push(index + 1);
  }
  const repeats = [];
  const gaps = [];
  for (const trigram of Array.from(positions.keys()).sort()) {
    const occurrences = positions.get(trigram);
    if (occurrences.length < 2) continue;
    const distances = [];
    let divisor = 0;
    for (let index = 1; index < occurrences.length; index++) {
      const gap = occurrences[index] - occurrences[index - 1];
      distances.push(gap);
      gaps.push(gap);
      divisor = gcd(divisor, gap);
    }
    repeats.push({trigram, positions: occurrences, gaps: distances, gcd: divisor});
  }
  return {repeats, gaps};
}

function percentage(count, total) {
  const tenths = Math.floor((2000 * count + total) / (2 * total));
  return `${Math.floor(tenths / 10)}.${tenths % 10}`;
}

function pairCounts(text, step) {
  const counts = new Map();
  for (let index = 0; index + 1 < text.length; index += step) {
    const pair = text.slice(index, index + 2);
    counts.set(pair, (counts.get(pair) || 0) + 1);
  }
  return counts;
}

function topPairs(counts) {
  return Array.from(counts).sort((left, right) => {
    if (left[1] !== right[1]) return right[1] - left[1];
    return left[0] < right[0] ? -1 : left[0] > right[0] ? 1 : 0;
  }).slice(0, 10).map(([pair, count]) => `${pair}:${count}`).join(' ');
}

function doubles(text) {
  let adjacent = 0;
  let paired = 0;
  for (let index = 0; index + 1 < text.length; index++) {
    if (text[index] === text[index + 1]) {
      adjacent++;
      if (index % 2 === 0) paired++;
    }
  }
  return {adjacent, paired};
}

module.exports = {
  countLetters, coincidence, columns, periodStatistics, kasiski,
  percentage, pairCounts, topPairs, doubles,
};
