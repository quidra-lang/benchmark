const points = [
  [3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1],
  [5, 6], [-6, -2], [2, -2], [7, -1], [-3, 4], [2, 8], [-6, 3]
];

function cross(o: number[], a: number[], b: number[]): number {
  return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
}

function chain(ordered: number[][]): number[][] {
  const result: number[][] = [];
  for (const point of ordered) {
    while (result.length >= 2 && cross(result.at(-2)!, result.at(-1)!, point) <= 0) result.pop();
    result.push(point);
  }
  return result;
}

const ordered = [...points].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
const hull = [...chain(ordered).slice(0, -1), ...chain(ordered.toReversed()).slice(0, -1)];
let areaTwice = 0;
hull.forEach(([x, y], i) => {
  const [nextX, nextY] = hull[(i + 1) % hull.length];
  areaTwice += x * nextY - nextX * y;
});
console.log(`hull: ${hull.length} points`);
for (const [x, y] of hull) console.log(`(${x}, ${y})`);
console.log(`area: ${(areaTwice / 2).toFixed(1)}`);
