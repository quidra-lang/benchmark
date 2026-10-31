let state = 12345;
const counts = Array<number>(13).fill(0);
for (let trial = 0; trial < 1000; trial++) {
  state = state * 48271 % 2147483647;
  const first = state % 6 + 1;
  state = state * 48271 % 2147483647;
  const second = state % 6 + 1;
  counts[first + second]++;
}
let most = 2;
for (let total = 2; total <= 12; total++) {
  console.log(`${total}: ${counts[total]}`);
  if (counts[total] > counts[most]) most = total;
}
console.log(`most frequent: ${most}`);
