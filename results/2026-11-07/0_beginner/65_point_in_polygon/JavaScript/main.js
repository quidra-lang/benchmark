const vertices = [[1, 1], [11, 2], [13, 9], [9, 7], [7, 12], [5, 6], [2, 10], [3, 5]];
const points = [[4, 8], [6, 4], [10, 8], [7, 11], [14, 3], [12, 8]];
for (const [px, py] of points) {
  let crossings = 0;
  vertices.forEach(([x1, y1], i) => {
    const [x2, y2] = vertices[(i + 1) % vertices.length];
    if ((y1 > py) !== (y2 > py)) {
      const intersection = x1 + (x2 - x1) * (py - y1) / (y2 - y1);
      if (intersection > px) crossings++;
    }
  });
  console.log(`(${px}, ${py}): ${crossings % 2 ? "inside" : "outside"}`);
}
