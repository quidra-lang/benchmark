'use strict';

const { round } = require('./canvas');

const contains = ([x0, y0, x1, y1], [x, y]) => x0 <= x && x <= x1 && y0 <= y && y <= y1;
const intersection = (left, right) => [Math.max(left[0], right[0]), Math.max(left[1], right[1]),
  Math.min(left[2], right[2]), Math.min(left[3], right[3])];
const isEmpty = rectangle => rectangle[0] > rectangle[2] || rectangle[1] > rectangle[3];

function clipSegment(start, end, rectangle) {
  const [x0, y0, x1, y1] = rectangle;
  const code = ([x, y]) => (x < x0 ? 1 : 0) | (x > x1 ? 2 : 0) | (y < y0 ? 4 : 0) | (y > y1 ? 8 : 0);
  let p = start, q = end;
  while (true) {
    const first = code(p), second = code(q);
    if (first === 0 && second === 0) return [p, q];
    if ((first & second) !== 0) return null;
    const atStart = first !== 0, region = atStart ? first : second;
    const [ax, ay] = atStart ? p : q, [bx, by] = atStart ? q : p;
    let point;
    if ((region & 4) !== 0) point = [ax + round((bx - ax) * (y0 - ay), by - ay), y0];
    else if ((region & 8) !== 0) point = [ax + round((bx - ax) * (y1 - ay), by - ay), y1];
    else if ((region & 2) !== 0) point = [x1, ay + round((by - ay) * (x1 - ax), bx - ax)];
    else point = [x0, ay + round((by - ay) * (x0 - ax), bx - ax)];
    if (atStart) p = point;
    else q = point;
  }
}

function clipPolygon(vertices, rectangle) {
  let points = vertices;
  const boundaries = [[0, rectangle[0], 1], [0, rectangle[2] + 1, -1],
    [1, rectangle[1], 1], [1, rectangle[3] + 1, -1]];
  for (const [axis, limit, direction] of boundaries) {
    if (points.length === 0) break;
    const output = [], inside = point => direction * (point[axis] - limit) >= 0;
    let previous = points.at(-1);
    for (const point of points) {
      const previousInside = inside(previous), currentInside = inside(point);
      if (previousInside !== currentInside) {
        const other = 1 - axis;
        const crossing = [];
        crossing[axis] = limit;
        crossing[other] = previous[other] + round((limit - previous[axis]) * (point[other] - previous[other]),
          point[axis] - previous[axis]);
        output.push(crossing);
      }
      if (currentInside) output.push(point);
      previous = point;
    }
    points = output;
  }
  return points;
}

module.exports = { contains, intersection, isEmpty, clipSegment, clipPolygon };
