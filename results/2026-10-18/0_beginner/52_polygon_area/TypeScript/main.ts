const polygons = [[[0, 0], [5, 0], [6, 4], [1, 3]], [[2, 1], [0, 4], [3, 7], [7, 6], [8, 2]], [[0, 0], [8, 0], [8, 6], [5, 6], [4, 3], [3, 6], [0, 6]]];
polygons.forEach((vertices, index) => {
  let crossSum = 0, perimeter = 0;
  vertices.forEach(([x, y], i) => {
    const [nextX, nextY] = vertices[(i + 1) % vertices.length];
    crossSum += x * nextY - nextX * y;
    const dx = x - nextX, dy = y - nextY;
    perimeter += Math.sqrt(dx * dx + dy * dy);
  });
  console.log(`polygon ${index + 1}: area=${(Math.abs(crossSum) / 2).toFixed(1)} perimeter=${perimeter.toFixed(3)}`);
});
