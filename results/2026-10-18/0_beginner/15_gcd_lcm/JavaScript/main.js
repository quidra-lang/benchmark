function gcd(a, b) {
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}
for (const [a, b] of [[48, 180], [1071, 462], [7, 91], [13, 97], [36288, 98280]]) {
  const divisor = gcd(a, b);
  const multiple = a / divisor * b;
  console.log(`gcd(${a}, ${b}) = ${divisor}, lcm(${a}, ${b}) = ${multiple}`);
}
