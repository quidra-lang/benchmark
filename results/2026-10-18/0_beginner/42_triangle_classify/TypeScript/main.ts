const triples = [[3, 8, 5], [6, 6, 6], [5, 8, 5], [13, 5, 12], [2, 9, 4], [7, 4, 7], [8, 6, 7], [4, 9, 6]];
for (const triple of triples) {
  const [a, b, c] = [...triple].sort((x, y) => x - y);
  let result = "not a triangle";
  if (a + b > c) {
    const side = a === c ? "equilateral" : a === b || b === c ? "isosceles" : "scalene";
    const squareSum = a * a + b * b;
    const angle = c * c < squareSum ? "acute" : c * c === squareSum ? "right" : "obtuse";
    result = `${side} ${angle}`;
  }
  console.log(`${triple.join(" ")}: ${result}`);
}
