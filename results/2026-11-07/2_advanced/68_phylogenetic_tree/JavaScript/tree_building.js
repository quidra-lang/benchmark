'use strict';

function emptyTree(count) {
    return { count, next: count, adj: new Map(), negative: 0 };
}

function connect(tree, a, b, length = 0) {
    if (!tree.adj.has(a)) tree.adj.set(a, new Map());
    if (!tree.adj.has(b)) tree.adj.set(b, new Map());
    tree.adj.get(a).set(b, length);
    tree.adj.get(b).set(a, length);
}

function disconnect(tree, a, b) {
    tree.adj.get(a).delete(b);
    tree.adj.get(b).delete(a);
}

function clone(tree) {
    return { ...tree, adj: new Map(Array.from(tree.adj, ([node, edges]) => [node, new Map(edges)])) };
}

function star(taxa, count) {
    const tree = emptyTree(count);
    const root = tree.next++;
    for (const taxon of taxa) connect(tree, root, taxon);
    return tree;
}

function leaves(tree) {
    return Array.from(tree.adj.keys()).filter(node => node < tree.count).sort((a, b) => a - b);
}

function bitCount(mask) {
    let count = 0;
    while (mask !== 0) {
        mask &= mask - 1;
        count++;
    }
    return count;
}

function rootTree(tree, outgroup) {
    const root = tree.adj.get(outgroup).keys().next().value;
    const parent = new Map([[root, null]]);
    const children = new Map();
    const masks = new Map();
    const lengths = new Map();
    const order = [];
    function visit(node) {
        order.push(node);
        const list = [];
        let mask = node < tree.count ? 2 ** node : 0;
        for (const [other, length] of tree.adj.get(node)) {
            if (other === parent.get(node)) continue;
            parent.set(other, node);
            lengths.set(other, length);
            list.push(other);
            mask |= visit(other);
        }
        children.set(node, list);
        masks.set(node, mask);
        return mask;
    }
    const all = visit(root);
    const ingroup = all & ~(2 ** outgroup);
    masks.set(root, ingroup);
    return { root, outgroup, parent, children, masks, lengths, order, ingroup };
}

function splitSet(tree, outgroup) {
    const rooted = rootTree(tree, outgroup);
    const splits = new Set();
    for (const node of rooted.order) {
        if (node >= tree.count && node !== rooted.root) splits.add(rooted.masks.get(node));
    }
    return splits;
}

function neighborJoining(matrix, taxa, count) {
    const tree = emptyTree(count);
    let active = taxa.slice();
    const distances = new Map(taxa.map(i => [i, new Map(taxa.map(j => [j, matrix[i][j]]))]));
    const d = (a, b) => distances.get(a).get(b);
    while (active.length >= 4) {
        const r = active.length;
        const totals = new Map();
        for (const x of active) {
            let total = 0;
            for (const y of active) if (y !== x) total += d(x, y);
            totals.set(x, total);
        }
        let chosen = null;
        for (let a = 0; a < r; a++) {
            for (let b = a + 1; b < r; b++) {
                const i = active[a];
                const j = active[b];
                const q = (r - 2) * d(i, j) - totals.get(i) - totals.get(j);
                if (chosen === null || q < chosen.q) chosen = { i, j, q };
            }
        }
        const { i, j } = chosen;
        const u = tree.next++;
        const first = d(i, j) / 2 + (totals.get(i) - totals.get(j)) / (2 * (r - 2));
        connect(tree, i, u, first);
        connect(tree, j, u, d(i, j) - first);
        distances.set(u, new Map());
        active = active.filter(k => k !== i && k !== j);
        for (const k of active) {
            const value = (d(i, k) + d(j, k) - d(i, j)) / 2;
            distances.get(u).set(k, value);
            distances.get(k).set(u, value);
        }
        active.push(u);
    }
    const [a, b, c] = active;
    const z = tree.next++;
    connect(tree, a, z, (d(a, b) + d(a, c) - d(b, c)) / 2);
    connect(tree, b, z, (d(a, b) + d(b, c) - d(a, c)) / 2);
    connect(tree, c, z, (d(a, c) + d(b, c) - d(a, b)) / 2);
    for (const [node, edges] of tree.adj) {
        for (const [other, length] of edges) {
            if (node < other && length < 0) {
                connect(tree, node, other, 0);
                tree.negative++;
            }
        }
    }
    return tree;
}

function path(tree, start, end) {
    function visit(node, previous, lengths) {
        if (node === end) return lengths;
        for (const [other, length] of tree.adj.get(node)) {
            if (other === previous) continue;
            const found = visit(other, node, [...lengths, length]);
            if (found !== null) return found;
        }
        return null;
    }
    return visit(start, null, []);
}

function pathDistance(tree, start, end) {
    let total = 0;
    for (const length of path(tree, start, end)) total += length;
    return total;
}

function patristic(tree) {
    const matrix = Array.from({ length: tree.count }, () => Array(tree.count).fill(0));
    const taxa = leaves(tree);
    for (let i = 0; i < taxa.length; i++) {
        for (let j = i + 1; j < taxa.length; j++) {
            const a = taxa[i];
            const b = taxa[j];
            matrix[a][b] = matrix[b][a] = pathDistance(tree, a, b);
        }
    }
    return matrix;
}

module.exports = { emptyTree, connect, disconnect, clone, star, leaves, bitCount,
    rootTree, splitSet, neighborJoining, path, pathDistance, patristic };
