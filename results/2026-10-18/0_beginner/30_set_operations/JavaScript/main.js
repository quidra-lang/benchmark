const a = new Set([12, 5, 8, 21, 5, 17, 3, 12, 9]);
const b = new Set([8, 14, 21, 6, 14, 3, 25, 6]);
const results = new Map([
  ["union", a.union(b)], ["intersection", a.intersection(b)],
  ["difference", a.difference(b)], ["symmetric difference", a.symmetricDifference(b)]
]);
for (const [label, values] of results) console.log(`${label}: ${[...values].sort((x, y) => x - y).join(" ")}`);
