const strings = [
  "(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3",
  "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}"
];
const matching = new Map([[")", "("], ["]", "["], ["}", "{"]]);
for (const text of strings) {
  const stack: string[] = [];
  let error = -1;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if ("([{".includes(char)) {
      stack.push(char);
    } else if (matching.has(char)) {
      if (stack.length === 0 || stack.at(-1) !== matching.get(char)) {
        error = i;
        break;
      }
      stack.pop();
    }
  }
  if (error < 0 && stack.length > 0) error = text.length;
  console.log(`${text} -> ${error < 0 ? "balanced" : `error at index ${error}`}`);
}
