const temperatures = [-40, -15, -3, 0, 22, 37, 100];
for (const celsius of temperatures) {
  const fahrenheit = celsius * 9 / 5 + 32;
  console.log(`${celsius} C = ${fahrenheit.toFixed(1)} F`);
}
