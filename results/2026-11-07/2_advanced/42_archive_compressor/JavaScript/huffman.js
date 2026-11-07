'use strict';

function treeLengths(frequencies) {
  const lengths = Array(frequencies.length).fill(0);
  const nodes = [];
  for (let symbol = 0; symbol < frequencies.length; symbol++) {
    if (frequencies[symbol] > 0) nodes.push({ weight: frequencies[symbol], minimum: symbol, symbol });
  }
  if (nodes.length === 0) return lengths;
  if (nodes.length === 1) {
    lengths[nodes[0].symbol] = 1;
    return lengths;
  }
  while (nodes.length > 1) {
    nodes.sort((a, b) => a.weight - b.weight || a.minimum - b.minimum);
    const first = nodes.shift();
    const second = nodes.shift();
    nodes.push({ weight: first.weight + second.weight, minimum: Math.min(first.minimum, second.minimum), first, second });
  }
  const stack = [{ node: nodes[0], depth: 0 }];
  while (stack.length) {
    const { node, depth } = stack.pop();
    if (node.symbol !== undefined) lengths[node.symbol] = depth;
    else {
      stack.push({ node: node.second, depth: depth + 1 });
      stack.push({ node: node.first, depth: depth + 1 });
    }
  }
  return lengths;
}

function limitedLengths(frequencies, limit) {
  let current = frequencies.slice();
  let halvings = 0;
  while (true) {
    const lengths = treeLengths(current);
    let maximum = 0;
    for (const length of lengths) maximum = Math.max(maximum, length);
    if (maximum <= limit) return { lengths, halvings };
    current = current.map(frequency => Math.floor((frequency + 1) / 2));
    halvings++;
  }
}

function canonical(lengths) {
  const symbols = [];
  for (let symbol = 0; symbol < lengths.length; symbol++) if (lengths[symbol] > 0) symbols.push(symbol);
  symbols.sort((a, b) => lengths[a] - lengths[b] || a - b);
  const codes = Array(lengths.length).fill(null);
  let value = 0;
  let previousLength = 0;
  for (let index = 0; index < symbols.length; index++) {
    const symbol = symbols[index];
    value = (value + Number(index > 0)) * 2 ** (lengths[symbol] - previousLength);
    codes[symbol] = value;
    previousLength = lengths[symbol];
  }
  return codes;
}

module.exports = { limitedLengths, canonical };
