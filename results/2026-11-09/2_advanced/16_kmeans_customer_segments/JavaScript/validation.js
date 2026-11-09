'use strict';

const { squaredDistance, meanPoint } = require('./kmeans');

function distanceTable(points) {
  const table = points.map(() => Array(points.length).fill(0));
  for (let first = 0; first < points.length; first++) for (let second = first + 1; second < points.length; second++) {
    table[first][second] = Math.sqrt(squaredDistance(points[first], points[second]));
    table[second][first] = table[first][second];
  }
  return table;
}

function clusterIndices(points, solution, distances) {
  const { segments, assignment, sse } = solution, silhouettes = [];
  for (let index = 0; index < points.length; index++) {
    const own = segments[assignment[index]];
    if (own.members.length === 1) { silhouettes.push(0); continue; }
    let within = 0, other = null;
    for (const member of own.members) if (member !== index) within += distances[index][member];
    within /= own.members.length - 1;
    for (let segment = 0; segment < segments.length; segment++) {
      if (segment === assignment[index]) continue;
      let total = 0;
      for (const member of segments[segment].members) total += distances[index][member];
      const average = total / segments[segment].members.length;
      if (other === null || average < other) other = average;
    }
    const denominator = Math.max(within, other);
    silhouettes.push(denominator === 0 ? 0 : (other - within) / denominator);
  }
  const global = meanPoint(points), scatters = [];
  let between = 0, totalSilhouette = 0;
  for (const value of silhouettes) totalSilhouette += value;
  for (const segment of segments) {
    between += segment.members.length * squaredDistance(segment.center, global);
    let total = 0;
    for (const member of segment.members) total += Math.sqrt(squaredDistance(points[member], segment.center));
    scatters.push(total / segment.members.length);
  }
  let totalDB = 0;
  for (let first = 0; first < segments.length; first++) {
    let maximum = 0;
    for (let second = 0; second < segments.length; second++) {
      if (first === second) continue;
      const value = (scatters[first] + scatters[second]) / Math.sqrt(squaredDistance(segments[first].center, segments[second].center));
      maximum = Math.max(maximum, value);
    }
    totalDB += maximum;
  }
  return { silhouettes, silhouette: totalSilhouette / points.length,
    calinski_harabasz: (between / (segments.length - 1)) / (sse / (points.length - segments.length)),
    davies_bouldin: totalDB / segments.length };
}

function elbow(k, firstK, lastK, sse, firstSSE, lastSSE) {
  const x = (k - firstK) / (lastK - firstK), y = (sse - lastSSE) / (firstSSE - lastSSE);
  return ((1 - x) - y) / Math.sqrt(2);
}

const hartigan = (sse, nextSSE, n, k) => (sse / nextSSE - 1) * (n - k - 1);

function adjustedRand(first, second) {
  const rows = new Map(), columns = new Map(), cells = new Map();
  for (let index = 0; index < first.length; index++) {
    const left = first[index], right = second[index];
    rows.set(left, (rows.get(left) || 0) + 1);
    columns.set(right, (columns.get(right) || 0) + 1);
    if (!cells.has(left)) cells.set(left, new Map());
    const row = cells.get(left);
    row.set(right, (row.get(right) || 0) + 1);
  }
  const pairs = value => value * (value - 1) / 2;
  let sx = 0, sy = 0, sxy = 0;
  for (const value of rows.values()) sx += pairs(value);
  for (const value of columns.values()) sy += pairs(value);
  for (const row of cells.values()) for (const value of row.values()) sxy += pairs(value);
  const z = pairs(first.length), numerator = 2 * (z * sxy - sx * sy), denominator = z * (sx + sy) - 2 * sx * sy;
  return denominator === 0 ? 1 : numerator / denominator;
}

module.exports = { distanceTable, clusterIndices, elbow, hartigan, adjustedRand };
