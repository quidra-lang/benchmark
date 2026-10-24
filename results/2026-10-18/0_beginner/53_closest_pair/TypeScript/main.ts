const points = [[12, -7], [-33, 25], [41, 18], [-8, -44], [27, 39], [-46, -12], [5, 14], [36, -29], [-19, 47], [-2, 3]];
let closest = [Infinity, 0, 0], farthest = [-Infinity, 0, 0];
for (let i = 0; i < points.length; i++) {
  for (let j = i + 1; j < points.length; j++) {
    const dx = points[i][0] - points[j][0], dy = points[i][1] - points[j][1];
    const squared = dx * dx + dy * dy;
    if (squared < closest[0]) closest = [squared, i, j];
    if (squared > farthest[0]) farthest = [squared, i, j];
  }
}
for (const [label, pair] of new Map([["closest", closest], ["farthest", farthest]])) {
  const [squared, i, j] = pair;
  console.log(`${label}: P${i} P${j} ${Math.sqrt(squared).toFixed(4)}`);
}
