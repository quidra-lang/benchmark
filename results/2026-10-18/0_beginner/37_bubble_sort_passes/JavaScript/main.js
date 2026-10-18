const values = [27, 64, 13, 88, 41, 5, 72, 36];
let swaps = 0;
for (let p = 1; p < values.length; p++) {
  let changed = false;
  for (let j = 0; j < values.length - p; j++) {
    if (values[j] > values[j + 1]) {
      [values[j], values[j + 1]] = [values[j + 1], values[j]];
      swaps++;
      changed = true;
    }
  }
  console.log(`pass ${p}: ${values.join(" ")}`);
  if (!changed) break;
}
console.log(`swaps: ${swaps}`);
