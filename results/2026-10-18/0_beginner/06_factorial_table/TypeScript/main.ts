let factorial = 1;
for (let n = 0; n <= 12; n++) {
  if (n > 0) factorial *= n;
  console.log(`${n}! = ${factorial}`);
}
