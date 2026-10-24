'use strict';

function accumulator(segments, positions, lowerCount) {
  let capacity = 1;
  while (capacity < lowerCount) capacity *= 2;
  const tree = Array(2 * capacity - 1).fill(0);
  const pairs = segments.map(segment => [positions[segment.upper], positions[segment.lower]]);
  pairs.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  let result = 0;
  for (const pair of pairs) {
    let k = pair[1] + capacity - 1;
    tree[k]++;
    while (k > 0) {
      if (k % 2 === 1) result += tree[k + 1];
      k = Math.floor((k - 1) / 2);
      tree[k]++;
    }
  }
  return result;
}

function crosses(a, b, positions) {
  return (positions[a.upper] - positions[b.upper]) * (positions[a.lower] - positions[b.lower]) < 0;
}

function brute(segments, positions) {
  let result = 0;
  for (let a = 0; a < segments.length; a++) {
    for (let b = a + 1; b < segments.length; b++) if (crosses(segments[a], segments[b], positions)) result++;
  }
  return result;
}

function total(gaps, order, positions) {
  let result = 0;
  for (let i = 0; i < gaps.length; i++) result += accumulator(gaps[i], positions, order[i + 1].length);
  return result;
}

function incidentCost(v, w, vertices, positions) {
  let result = 0;
  for (const side of ['upper', 'lower']) {
    for (const a of vertices[v][side]) {
      for (const b of vertices[w][side]) if (positions[a] > positions[b]) result++;
    }
  }
  return result;
}

module.exports = {accumulator, brute, total, crosses, incidentCost};
