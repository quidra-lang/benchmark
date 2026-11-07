function evaluate(tokens: string[], variables: Map<string, number>): number {
  let index = 0;
  const peek = () => tokens[index] ?? "";
  function factor(): number {
    const token = tokens[index++];
    if (token === "-") return -factor();
    if (token === "(") {
      const value = expression();
      index++;
      return value;
    }
    if (/^\d+$/.test(token)) return Number(token);
    if (!variables.has(token)) throw new Error(`undefined variable ${token}`);
    return variables.get(token)!;
  }

  function term(): number {
    let value = factor();
    while (peek() === "*" || peek() === "/") {
      const operation = tokens[index];
      index++;
      const right = factor();
      if (operation === "*") {
        value *= right;
      } else {
        if (right === 0) throw new Error("division by zero");
        value = Math.trunc(value / right);
      }
    }
    return value;
  }

  function expression(): number {
    let value = term();
    while (peek() === "+" || peek() === "-") {
      const operation = tokens[index];
      index++;
      const right = term();
      value = operation === "+" ? value + right : value - right;
    }
    return value;
  }
  return expression();
}

const lines = [
  "width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
  "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus",
  "volume = area * depth", "width = (width+3)*-(2-4)", "width * shift - height"
];
const variables = new Map<string, number>();
for (const line of lines) {
  const tokens = line.match(/\d+|[a-z]+|[-+*\/()=]/g)!;
  const name = tokens[1] === "=" ? tokens[0] : "";
  try {
    const value = evaluate(name ? tokens.slice(2) : tokens, variables);
    if (name) {
      variables.set(name, value);
      console.log(`${name} = ${value}`);
    } else {
      console.log(value);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.log(`error: ${message}`);
  }
}
