'use strict';

const { floorDiv } = require('./canvas');
const { contains } = require('./clipping');

function fillPolygon(sequences, rule, clip, width) {
  const edges = [], pixels = new Set();
  for (const points of sequences) {
    for (let index = 0; index < points.length; index++) {
      const start = points[index], end = points[(index + 1) % points.length];
      if (start[1] !== end[1]) edges.push([start, end]);
    }
  }
  for (let y = clip[1]; y <= clip[3]; y++) {
    const events = new Map();
    let count = 0, winding = 0;
    for (const [[xa, ya], [xb, yb]] of edges) {
      if (y < Math.min(ya, yb) || y >= Math.max(ya, yb)) continue;
      let denominator = yb - ya, numerator = 2 * xa * denominator + (2 * y + 1 - 2 * ya) * (xb - xa);
      const direction = denominator > 0 ? 1 : -1;
      if (denominator < 0) [numerator, denominator] = [-numerator, -denominator];
      const first = floorDiv(numerator - denominator, 2 * denominator) + 1;
      if (first <= clip[0]) { count++; winding += direction; }
      else {
        if (!events.has(first)) events.set(first, [0, 0]);
        const event = events.get(first);
        event[0]++;
        event[1] += direction;
      }
    }
    for (let x = clip[0]; x <= clip[2]; x++) {
      if (events.has(x)) { count += events.get(x)[0]; winding += events.get(x)[1]; }
      if (rule === 'evenodd' ? count % 2 !== 0 : winding !== 0) pixels.add(y * width + x);
    }
  }
  return pixels;
}

function fillShape(points, [cx, cy], clip, width) {
  const spans = new Map(), pixels = new Set();
  for (const [x, y] of points) spans.set(y, Math.max(spans.get(y) || 0, Math.abs(x)));
  for (const [dy, extent] of spans) {
    const y = cy + dy;
    if (y < clip[1] || y > clip[3]) continue;
    for (let x = Math.max(cx - extent, clip[0]); x <= Math.min(cx + extent, clip[2]); x++) pixels.add(y * width + x);
  }
  return pixels;
}

function floodFill(layer, seed, clip, width) {
  const first = seed[1] * width + seed[0], value = layer.pixels[first];
  const pixels = new Set([first]), queue = [seed];
  const equal = pixel => value === null ? pixel === null
    : pixel !== null && value.color.every((component, index) => component === pixel.color[index]);
  for (let head = 0; head < queue.length; head++) {
    const [x, y] = queue[head];
    for (const point of [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]) {
      if (!contains(clip, point)) continue;
      const index = point[1] * width + point[0];
      if (!pixels.has(index) && equal(layer.pixels[index])) { pixels.add(index); queue.push(point); }
    }
  }
  return pixels;
}

module.exports = { fillPolygon, fillShape, floodFill };
