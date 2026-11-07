const pairs: [number, string][] = [
  [1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"],
  [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]
];
const values = new Map([["I", 1], ["V", 5], ["X", 10], ["L", 50], ["C", 100], ["D", 500], ["M", 1000]]);
for (const n of [9, 14, 49, 94, 444, 1994, 2768, 3999]) {
  let remaining = n, roman = "";
  for (const [value, symbol] of pairs) {
    while (remaining >= value) {
      roman += symbol;
      remaining -= value;
    }
  }
  let decoded = 0;
  for (let i = 0; i < roman.length; i++) {
    const value = values.get(roman[i])!;
    decoded += i + 1 < roman.length && value < values.get(roman[i + 1])! ? -value : value;
  }
  console.log(`${n} -> ${roman} -> ${decoded}`);
}
