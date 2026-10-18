const a = new Set([12, 5, 8, 21, 5, 17, 3, 12, 9]);
const b = new Set([8, 14, 21, 6, 14, 3, 25, 6]);
const union = [...new Set([...a, ...b])];
const results = new Map([
  ["union", union], ["intersection", [...a].filter(n => b.has(n))],
  ["difference", [...a].filter(n => !b.has(n))],
  ["symmetric difference", union.filter(n => a.has(n) !== b.has(n))]
]);
for (const [label, values] of results) console.log(`${label}: ${values.sort((x, y) => x - y).join(" ")}`);
