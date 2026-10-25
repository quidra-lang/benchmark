const items = [
  {name: "tent", weight: 10, value: 120}, {name: "stove", weight: 3, value: 65},
  {name: "lantern", weight: 2, value: 45}, {name: "rope", weight: 3, value: 20},
  {name: "camera", weight: 5, value: 90}, {name: "blanket", weight: 5, value: 85},
  {name: "water", weight: 6, value: 100}
];
const capacity = 20;
const dp = Array.from({length: items.length + 1}, () => Array<number>(capacity + 1).fill(0));
items.forEach(({weight, value}, index) => {
  const i = index + 1;
  for (let limit = 0; limit <= capacity; limit++) {
    dp[i][limit] = dp[i - 1][limit];
    if (weight <= limit) dp[i][limit] = Math.max(dp[i][limit], dp[i - 1][limit - weight] + value);
  }
});
const chosen: typeof items = [];
let remaining = capacity;
for (let i = items.length; i > 0; i--) {
  if (dp[i][remaining] !== dp[i - 1][remaining]) {
    chosen.push(items[i - 1]);
    remaining -= items[i - 1].weight;
  }
}
chosen.reverse();
console.log(`max value: ${dp[items.length][capacity]}`);
console.log(`total weight: ${chosen.reduce((sum, item) => sum + item.weight, 0)}`);
console.log(`items: ${chosen.map(item => item.name).join(" ")}`);
