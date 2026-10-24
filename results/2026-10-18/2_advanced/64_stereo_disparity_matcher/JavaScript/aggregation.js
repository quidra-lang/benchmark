const DIRECTIONS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [-1, 1], [1, -1]];

function pathCosts(base, left, width, height, direction, p1, p2, gamma) {
  const [rx, ry] = direction;
  const result = Array(base.length);
  const disparities = base[0].length;
  for (let row = 0; row < height; row++) {
    const y = ry >= 0 ? row : height - 1 - row;
    for (let column = 0; column < width; column++) {
      const x = rx >= 0 ? column : width - 1 - column;
      const p = y * width + x;
      const qx = x - rx, qy = y - ry;
      if (qx < 0 || qx >= width || qy < 0 || qy >= height) {
        result[p] = [...base[p]];
        continue;
      }
      const q = qy * width + qx;
      const previous = result[q];
      const minimum = Math.min(...previous);
      const penalty = Math.max(p1, Math.floor(p2 * gamma / (gamma + Math.abs(left[p] - left[q]))));
      result[p] = [];
      for (let d = 0; d < disparities; d++) {
        let best = Math.min(previous[d], minimum + penalty);
        if (d > 0) best = Math.min(best, previous[d - 1] + p1);
        if (d + 1 < disparities) best = Math.min(best, previous[d + 1] + p1);
        result[p].push(base[p][d] + best - minimum);
      }
    }
  }
  return result;
}

function* cumulativeCosts(base, left, width, height, paths, p1, p2, gamma) {
  const total = base.map(row => row.map(() => 0));
  for (const direction of DIRECTIONS.slice(0, paths)) {
    const costs = pathCosts(base, left, width, height, direction, p1, p2, gamma);
    costs.forEach((row, p) => row.forEach((value, d) => { total[p][d] += value; }));
    yield total;
  }
}

module.exports = { DIRECTIONS, pathCosts, cumulativeCosts };
