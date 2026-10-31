'use strict';

function rho(point, theta, trig, step) {
  return Math.floor((point.x * trig.cos[theta] + point.y * trig.sin[theta]) / (16384 * step));
}

function circlePoints(radius) {
  const points = new Map();
  let a = radius, b = 0, error = 1 - radius;
  while (a >= b) {
    for (const [x, y] of [[a, b], [b, a], [-b, a], [-a, b], [-a, -b], [-b, -a], [b, -a], [a, -b]]) {
      points.set(`${x},${y}`, { x, y });
    }
    b++;
    if (error < 0) error += 2 * b + 1;
    else { a--; error += 2 * (b - a) + 1; }
  }
  return Array.from(points.values());
}

function circleVotes(edges, width, height, minimum, maximum) {
  const pixels = [];
  for (let index = 0; index < edges.length; index++) {
    if (edges[index]) pixels.push({ x: index % width, y: Math.floor(index / width) });
  }
  const layers = [];
  for (let radius = minimum; radius <= maximum; radius++) {
    const offsets = circlePoints(radius), counts = new Int32Array(width * height);
    for (const p of pixels) {
      for (const o of offsets) {
        const x = p.x + o.x, y = p.y + o.y;
        if (x >= 0 && x < width && y >= 0 && y < height) counts[y * width + x]++;
      }
    }
    layers.push({ radius, offsets, counts });
  }
  return layers;
}

function circlePeaks(layers, width, height, percent) {
  const peaks = [];
  let candidates = 0;
  for (let k = 0; k < layers.length; k++) {
    const layer = layers[k], points = layer.offsets.length;
    for (let index = 0; index < layer.counts.length; index++) {
      const votes = layer.counts[index];
      if (100 * votes < percent * points) continue;
      candidates++;
      const x = index % width, y = Math.floor(index / width);
      let peak = true;
      for (let other = Math.max(0, k - 2); other <= Math.min(layers.length - 1, k + 2) && peak; other++) {
        const neighbor = layers[other], lhs = votes * neighbor.offsets.length;
        for (let ny = Math.max(0, y - 2); ny <= Math.min(height - 1, y + 2) && peak; ny++) {
          for (let nx = Math.max(0, x - 2); nx <= Math.min(width - 1, x + 2); nx++) {
            const next = ny * width + nx;
            if (other === k && next === index) continue;
            const rhs = neighbor.counts[next] * points;
            const earlier = other < k || (other === k && next < index);
            if (lhs < rhs || (lhs === rhs && earlier)) { peak = false; break; }
          }
        }
      }
      if (peak) peaks.push({ radius: layer.radius, x, y, votes, points, offsets: layer.offsets });
    }
  }
  return { candidates, peaks };
}

function lineVotes(pixels, trig, step) {
  return Array.from({ length: 180 }, (_, theta) => {
    const counts = new Map();
    for (const point of pixels) {
      const r = rho(point, theta, trig, step);
      counts.set(r, (counts.get(r) || 0) + 1);
    }
    return counts;
  });
}

function linePeaks(votes, threshold) {
  const peaks = [];
  for (let theta = 0; theta < 180; theta++) {
    for (const [r, count] of votes[theta]) {
      if (count < threshold) continue;
      let peak = true;
      for (let t = Math.max(0, theta - 2); t <= Math.min(179, theta + 2) && peak; t++) {
        for (let s = r - 2; s <= r + 2; s++) {
          if (t === theta && s === r) continue;
          const other = votes[t].get(s) || 0, earlier = t < theta || (t === theta && s < r);
          if (count < other || (count === other && earlier)) { peak = false; break; }
        }
      }
      if (peak) peaks.push({ theta, rho: r, votes: count });
    }
  }
  return peaks;
}

module.exports = { rho, circlePoints, circleVotes, circlePeaks, lineVotes, linePeaks };
