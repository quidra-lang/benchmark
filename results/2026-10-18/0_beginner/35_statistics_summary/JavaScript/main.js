const values = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71];
const ordered = [...values].sort((a, b) => a - b);
const mean = values.reduce((sum, n) => sum + n, 0) / values.length;
let squares = 0;
for (const value of values) {
  const difference = value - mean;
  squares += difference * difference;
}
const stdev = Math.sqrt(squares / values.length);
const counts = new Map();
for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
let mode = ordered[0];
for (const value of ordered) {
  if (counts.get(value) > counts.get(mode)) mode = value;
}
console.log(`mean: ${mean.toFixed(3)}`);
console.log(`median: ${ordered[Math.floor(values.length / 2)]}`);
console.log(`mode: ${mode}`);
console.log(`range: ${ordered.at(-1) - ordered[0]}`);
console.log(`stdev: ${stdev.toFixed(3)}`);
