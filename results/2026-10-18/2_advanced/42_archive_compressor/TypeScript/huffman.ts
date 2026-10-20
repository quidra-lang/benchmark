type Node = { weight: number; minimum: number } & ({ symbol: number } | { first: Node; second: Node });
function treeLengths(frequencies: number[]) {
    const lengths: number[] = Array(frequencies.length).fill(0), nodes: Node[] = [];
    for (let s = 0; s < frequencies.length; s++) if (frequencies[s]) nodes.push({ weight: frequencies[s], minimum: s, symbol: s });
    if (!nodes.length) return lengths;
    if (nodes.length === 1) { lengths[nodes[0].minimum] = 1; return lengths; }
    while (nodes.length > 1) { nodes.sort((a, b) => a.weight - b.weight || a.minimum - b.minimum); const first = nodes.shift()!, second = nodes.shift()!; nodes.push({ weight: first.weight + second.weight, minimum: Math.min(first.minimum, second.minimum), first, second }); }
    const stack = [{ node: nodes[0], depth: 0 }];
    while (stack.length) { const { node, depth } = stack.pop()!; if ('symbol' in node) lengths[node.symbol] = depth; else { stack.push({ node: node.second, depth: depth + 1 }, { node: node.first, depth: depth + 1 }); } }
    return lengths;
}
export function limitedLengths(frequencies: number[], limit: number) {
    let current = frequencies.slice(), halvings = 0;
    while (true) { const lengths = treeLengths(current); if (Math.max(...lengths) <= limit) return { lengths, halvings }; current = current.map(f => Math.floor((f + 1) / 2)); halvings++; }
}
export function canonical(lengths: number[]) {
    const symbols = lengths.map((_, s) => s).filter(s => lengths[s] > 0).sort((a, b) => lengths[a] - lengths[b] || a - b), codes: number[] = Array(lengths.length).fill(0);
    let value = 0, previousLength = 0;
    for (const [i, s] of symbols.entries()) { value = (value + Number(i > 0)) * 2 ** (lengths[s] - previousLength); codes[s] = value; previousLength = lengths[s]; }
    return codes;
}
