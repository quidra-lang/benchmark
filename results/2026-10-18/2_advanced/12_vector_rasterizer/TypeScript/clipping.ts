import { round, type Point, type Rectangle, type Segment } from './canvas.ts';

export const contains = ([x0,y0,x1,y1]: Rectangle, [x,y]: Point): boolean => x0 <= x && x <= x1 && y0 <= y && y <= y1;
export const intersection = (a: Rectangle, b: Rectangle): Rectangle => [Math.max(a[0],b[0]), Math.max(a[1],b[1]), Math.min(a[2],b[2]), Math.min(a[3],b[3])];
export const isEmpty = (r: Rectangle): boolean => r[0] > r[2] || r[1] > r[3];
export function clipSegment(start: Point, end: Point, [x0,y0,x1,y1]: Rectangle): Segment | null {
  const code = ([x,y]: Point) => (x < x0 ? 1 : 0) | (x > x1 ? 2 : 0) | (y < y0 ? 4 : 0) | (y > y1 ? 8 : 0);
  let p = start, q = end;
  while (true) {
    const first = code(p), second = code(q);
    if (first === 0 && second === 0) return [p,q];
    if ((first & second) !== 0) return null;
    const atStart = first !== 0, region = atStart ? first : second;
    const [ax,ay] = atStart ? p : q, [bx,by] = atStart ? q : p;
    let point: Point;
    if (region & 4) point = [ax + round((bx-ax)*(y0-ay), by-ay), y0];
    else if (region & 8) point = [ax + round((bx-ax)*(y1-ay), by-ay), y1];
    else if (region & 2) point = [x1, ay + round((by-ay)*(x1-ax), bx-ax)];
    else point = [x0, ay + round((by-ay)*(x0-ax), bx-ax)];
    if (atStart) p = point; else q = point;
  }
}
export function clipPolygon(vertices: Point[], rectangle: Rectangle): Point[] {
  let points = vertices;
  const boundaries: [0 | 1, number, number][] = [[0,rectangle[0],1],[0,rectangle[2]+1,-1],[1,rectangle[1],1],[1,rectangle[3]+1,-1]];
  for (const [axis,limit,direction] of boundaries) {
    if (points.length === 0) break;
    const output: Point[] = [], inside = (p: Point) => direction * (p[axis] - limit) >= 0;
    let previous = points[points.length - 1];
    for (const p of points) {
      if (inside(previous) !== inside(p)) {
        const other = 1 - axis, crossing: Point = [0,0];
        crossing[axis] = limit;
        crossing[other] = previous[other] + round((limit-previous[axis])*(p[other]-previous[other]), p[axis]-previous[axis]);
        output.push(crossing);
      }
      if (inside(p)) output.push(p);
      previous = p;
    }
    points = output;
  }
  return points;
}
