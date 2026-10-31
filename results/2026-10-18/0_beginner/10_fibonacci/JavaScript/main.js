const terms = [1, 1];
while (terms.length < 30) terms.push(terms.at(-1) + terms.at(-2));
console.log(terms.join(" "));
console.log(`sum: ${terms.reduce((sum, n) => sum + n, 0)}`);
