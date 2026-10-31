const arrays = [
  [3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2],
  [-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1],
  [-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2]
];
for (const values of arrays) {
  let current = values[0], best = values[0], start = 0, bestStart = 0, bestEnd = 0;
  for (let i = 1; i < values.length; i++) {
    if (current + values[i] < values[i]) {
      current = values[i];
      start = i;
    } else {
      current += values[i];
    }
    if (current > best) {
      best = current;
      bestStart = start;
      bestEnd = i;
    }
  }
  console.log(`max sum ${best} at [${bestStart}, ${bestEnd}]`);
}
