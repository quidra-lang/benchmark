import { floorDiv, round, type Point } from './canvas.ts';

export function* bresenham([x, y]: Point, [lastX, lastY]: Point): Generator<Point> {
  const dx = Math.abs(lastX - x);
  const dy = -Math.abs(lastY - y);
  const sx = x < lastX ? 1 : -1;
  const sy = y < lastY ? 1 : -1;
  let error = dx + dy;
  while (true) {
    yield [x, y];
    if (x === lastX && y === lastY) return;
    const twice = 2 * error;
    if (twice >= dy) {
      error += dy;
      x += sx;
    }
    if (twice <= dx) {
      error += dx;
      y += sy;
    }
  }
}
export function* expandPoint([x, y]: Point, width: number): Generator<Point> {
  const lo = -floorDiv(width - 1, 2);
  for (let j = lo; j < lo + width; j++) for (let i = lo; i < lo + width; i++) yield [x + i, y + j];
}
export function circlePoints(radius: number): Point[] {
  const points = new Map<string, Point>();
  let a = radius;
  let b = 0;
  let error = 1 - radius;
  while (a >= b) {
    const octants: Point[] = [
      [a, b],
      [b, a],
      [-b, a],
      [-a, b],
      [-a, -b],
      [-b, -a],
      [b, -a],
      [a, -b],
    ];
    for (const p of octants) points.set(p.join(','), p);
    b++;
    if (error < 0) error += 2 * b + 1;
    else {
      a--;
      error += 2 * (b - a) + 1;
    }
  }
  return [...points.values()];
}
export function ellipsePoints(rx: number, ry: number): Point[] {
  const points = new Map<string, Point>();
  const rx2 = rx * rx;
  const ry2 = ry * ry;
  let x = 0;
  let y = ry;
  const append = () => {
    const reflected: Point[] = [
      [x, y],
      [-x, y],
      [x, -y],
      [-x, -y],
    ];
    for (const p of reflected) points.set(p.join(','), p);
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
export function bezier(points: Point[], segments: number): Point[] {
  const result: Point[] = [];
  const degree = points.length - 1;
  const denominator = segments ** degree;
  for (let i = 0; i <= segments; i++) {
    const left = segments - i;
    const weights =
      degree === 2
        ? [left * left, 2 * i * left, i * i]
        : [left * left * left, 3 * i * left * left, 3 * i * i * left, i * i * i];
    let x = 0;
    let y = 0;
    for (let k = 0; k < weights.length; k++) {
      x += weights[k] * points[k][0];
      y += weights[k] * points[k][1];
    }
    result.push([round(x, denominator), round(y, denominator)]);
  }
  return result;
}
