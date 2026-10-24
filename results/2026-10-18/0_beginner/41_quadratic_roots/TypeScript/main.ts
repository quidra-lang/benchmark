for (const [a, b, c] of [[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]]) {
  const discriminant = b * b - 4 * a * c;
  let result;
  if (discriminant > 0) {
    const first = (-b + Math.sqrt(discriminant)) / (2 * a);
    const second = (-b - Math.sqrt(discriminant)) / (2 * a);
    result = `x1 = ${Math.max(first, second).toFixed(4)}, x2 = ${Math.min(first, second).toFixed(4)}`;
  } else if (discriminant === 0) {
    result = `x = ${(-b / (2 * a)).toFixed(4)}`;
  } else {
    const real = (-b / (2 * a)).toFixed(4);
    const imaginary = (Math.sqrt(-discriminant) / (2 * Math.abs(a))).toFixed(4);
    result = `x = ${real} + ${imaginary}i, ${real} - ${imaginary}i`;
  }
  console.log(`${a} ${b} ${c}: ${result}`);
}
