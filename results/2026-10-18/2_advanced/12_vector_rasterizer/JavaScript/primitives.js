'use strict';

const { floorDiv, round } = require('./canvas');

function* bresenham(start, end) {
  let [x, y] = start;
  const [lastX, lastY] = end, dx = Math.abs(lastX - x), dy = -Math.abs(lastY - y);
  const sx = x < lastX ? 1 : -1, sy = y < lastY ? 1 : -1;
  let error = dx + dy;
  while (true) {
    yield [x, y];
    if (x === lastX && y === lastY) return;
    const twice = 2 * error;
    if (twice >= dy) { error += dy; x += sx; }
    if (twice <= dx) { error += dx; y += sy; }
  }
}

function* expandPoint([x, y], width) {
  const low = -floorDiv(width - 1, 2);
  for (let j = low; j < low + width; j++) {
    for (let i = low; i < low + width; i++) yield [x + i, y + j];
  }
}

function circlePoints(radius) {
  const points = new Map();
  let a = radius, b = 0, error = 1 - radius;
  while (a >= b) {
    for (const point of [[a, b], [b, a], [-b, a], [-a, b], [-a, -b], [-b, -a], [b, -a], [a, -b]]) {
      points.set(point.join(','), point);
    }
    b++;
    if (error < 0) error += 2 * b + 1;
    else { a--; error += 2 * (b - a) + 1; }
  }
  return [...points.values()];
}

function ellipsePoints(rx, ry) {
  const points = new Map(), rx2 = rx * rx, ry2 = ry * ry;
  let x = 0, y = ry;
  const append = () => {
    for (const point of [[x, y], [-x, y], [x, -y], [-x, -y]]) points.set(point.join(','), point);
  };
  append();
  while (ry2 * x < rx2 * y) {
    const decision = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2;
    x++;
    if (decision >= 0) y--;
    append();
  }
  while (y > 0) {
    const decision = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2;
    y--;
    if (decision <= 0) x++;
    append();
  }
  return [...points.values()];
}

function bezier(points, segments) {
  const result = [], degree = points.length - 1;
  const denominator = degree === 2 ? segments * segments : segments * segments * segments;
  for (let i = 0; i <= segments; i++) {
    const left = segments - i;
    const weights = degree === 2 ? [left * left, 2 * i * left, i * i]
      : [left * left * left, 3 * i * left * left, 3 * i * i * left, i * i * i];
    let x = 0, y = 0;
    for (let index = 0; index < weights.length; index++) {
      x += weights[index] * points[index][0];
      y += weights[index] * points[index][1];
    }
    result.push([round(x, denominator), round(y, denominator)]);
  }
  return result;
}

module.exports = { bresenham, expandPoint, circlePoints, ellipsePoints, bezier };
