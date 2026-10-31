const text = "she sells sea shells by the sea shore";
const frequencies = new Map();
for (const symbol of text) frequencies.set(symbol, (frequencies.get(symbol) ?? 0) + 1);
const trees = [...frequencies].map(([symbol, weight]) => ({
  weight, minimum: symbol, symbol, left: null, right: null
}));
while (trees.length > 1) {
  trees.sort((a, b) => a.weight - b.weight || (a.minimum < b.minimum ? -1 : a.minimum > b.minimum ? 1 : 0));
  const left = trees.shift(), right = trees.shift();
  trees.push({
    weight: left.weight + right.weight,
    minimum: left.minimum < right.minimum ? left.minimum : right.minimum,
    symbol: null, left, right
  });
}
const codes = new Map();

function visit(tree, prefix) {
  if (tree.symbol !== null) {
    codes.set(tree.symbol, prefix);
  } else {
    visit(tree.left, prefix + "0");
    visit(tree.right, prefix + "1");
  }
}

visit(trees[0], "");
let bits = 0;
for (const symbol of [...frequencies.keys()].sort()) {
  console.log(`'${symbol}' freq=${frequencies.get(symbol)} code=${codes.get(symbol)}`);
  bits += frequencies.get(symbol) * codes.get(symbol).length;
}
console.log(`encoded bits: ${bits}`);
console.log(`fixed 8-bit: ${text.length * 8}`);
