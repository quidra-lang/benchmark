const expressions = [
  "3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",
  "15 7 1 1 + - / 3 * 2 1 1 + + -", "4 2 5 * + 1 3 2 * - 5 + /",
  "2 3 4 + 5", "46341 46339 * -2 /"
];
for (const expression of expressions) {
  const stack: number[] = [];
  let error = "";
  for (const token of expression.split(" ")) {
    if (!["+", "-", "*", "/"].includes(token)) {
      stack.push(Number(token));
      continue;
    }
    if (stack.length < 2) {
      error = "stack underflow";
      break;
    }
    const b = stack.pop()!, a = stack.pop()!;
    if (token === "/" && b === 0) {
      error = "division by zero";
      break;
    }
    let result;
    if (token === "+") result = a + b;
    else if (token === "-") result = a - b;
    else if (token === "*") result = a * b;
    else result = Math.trunc(a / b);
    stack.push(result);
  }
  if (!error && stack.length !== 1) error = "leftover operands";
  console.log(`${expression} => ${error ? `error: ${error}` : stack[0]}`);
}
