const values = [52, 17, 38, 9, 61, 38, 24, 45];
let total = 0;
for (let i = 1; i < values.length; i++) {
  const value = values[i];
  let j = i - 1, shifts = 0;
  while (j >= 0 && values[j] > value) {
    values[j + 1] = values[j];
    j--;
    shifts++;
  }
  values[j + 1] = value;
  total += shifts;
  console.log(`i=${i} shifts=${shifts}: ${values.join(" ")}`);
}
console.log(`total shifts: ${total}`);
