const numbers = ["688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309", "9884593615513906"];
for (const number of numbers) {
  let total = 0;
  [...number].reverse().forEach((char, i) => {
    let digit = Number(char);
    if (i % 2 === 1) { digit *= 2; if (digit > 9) digit -= 9; }
    total += digit;
  });
  const expected = (10 - (total - Number(number.at(-1))) % 10) % 10;
  const result = total % 10 === 0 ? "valid" : `invalid (expected check digit ${expected})`;
  console.log(`${number}: ${result}`);
}
