const pi = 3.141592653589793;
for (const radius of [3, 7, 12, 25, 41]) {
  const area = pi * radius * radius;
  const circumference = 2 * pi * radius;
  console.log(`r=${radius} area=${area.toFixed(3)} circumference=${circumference.toFixed(3)}`);
}
