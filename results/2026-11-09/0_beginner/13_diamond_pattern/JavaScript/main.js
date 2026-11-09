const n = 5;
for (let row = 1; row <= 2 * n - 1; row++) {
  const i = row <= n ? row : 2 * n - row;
  console.log(" ".repeat(n - i) + "*".repeat(2 * i - 1));
}
