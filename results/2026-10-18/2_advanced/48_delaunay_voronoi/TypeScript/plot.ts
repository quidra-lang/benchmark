import type { Point, RationalPoint, Pair } from './predicates.ts';
export class Canvas {
  readonly cells: string[][];
  constructor(readonly width: number, readonly height: number) { this.cells = Array.from({ length: height }, () => Array<string>(width).fill(' ')); }
  position(point: Point | RationalPoint): Pair {
    const { X, Y, D } = 'D' in point ? point : { X: point.x, Y: point.y, D: 1 };
    return [Math.floor((2 * X * (this.width - 1) + 1000 * D) / (2000 * D)),
      this.height - 1 - Math.floor((2 * Y * (this.height - 1) + 1000 * D) / (2000 * D))];
  }
  point(point: Point | RationalPoint, character: string): void { const [c, r] = this.position(point); this.cells[r][c] = character; }
  line(start: Point, end: Point, character: string): void {
    let [x, y] = this.position(start);
    const [x1, y1] = this.position(end), dx = Math.abs(x1 - x), dy = -Math.abs(y1 - y), sx = x < x1 ? 1 : -1, sy = y < y1 ? 1 : -1;
    let error = dx + dy;
    while (true) {
      this.cells[y][x] = character;
      if (x === x1 && y === y1) break;
      const doubled = 2 * error;
      if (doubled >= dy) { error += dy; x += sx; }
      if (doubled <= dx) { error += dx; y += sy; }
    }
  }
  frame(): string[] { const border = '+' + '-'.repeat(this.width) + '+'; return [border, ...this.cells.map(r => '|' + r.join('') + '|'), border]; }
}
export function voronoiPlot(width: number, height: number, points: Point[]): string[] {
  const canvas = new Canvas(width, height), owners = Array.from({ length: height }, () => Array<number>(width).fill(0));
  for (let r = 0; r < height; r++) for (let c = 0; c < width; c++) {
    let best = Infinity;
    for (let s = 1; s < points.length; s++) {
      const x = (c * 1000 - points[s].x * (width - 1)) * (height - 1), y = ((height - 1 - r) * 1000 - points[s].y * (height - 1)) * (width - 1), distance = x * x + y * y;
      if (distance < best) { best = distance; owners[r][c] = s; }
    }
  }
  for (let r = 0; r < height; r++) for (let c = 0; c < width; c++) {
    if ((c < width - 1 && owners[r][c] !== owners[r][c + 1]) || (r < height - 1 && owners[r][c] !== owners[r + 1][c])) canvas.cells[r][c] = '#';
  }
  for (let s = 1; s < points.length; s++) canvas.point(points[s], 'o');
  return canvas.frame();
}
