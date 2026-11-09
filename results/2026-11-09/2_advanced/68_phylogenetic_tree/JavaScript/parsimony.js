'use strict';

const { clone, connect, disconnect, rootTree } = require('./tree_building');
const { LETTERS } = require('./alignment');
const BITS = [1, 2, 4, 8];

function merge(a, b) {
    return (a & b) !== 0 ? { set: a & b, change: 0 } : { set: a | b, change: 1 };
}

function provisional(tree, rooted, encoded, column) {
    const sets = new Map();
    let changes = 0;
    for (let i = rooted.order.length - 1; i >= 0; i--) {
        const node = rooted.order[i];
        if (node < tree.count) {
            sets.set(node, encoded[node][column]);
        } else {
            const children = rooted.children.get(node).filter(child => child !== rooted.outgroup);
            const result = merge(sets.get(children[0]), sets.get(children[1]));
            sets.set(node, result.set);
            changes += result.change;
        }
    }
    changes += merge(sets.get(rooted.root), sets.get(rooted.outgroup)).change;
    return { sets, changes };
}

function score(tree, encoded, outgroup) {
    const rooted = rootTree(tree, outgroup);
    const columns = [];
    let total = 0;
    for (let c = 0; c < encoded[0].length; c++) {
        const changes = provisional(tree, rooted, encoded, c).changes;
        columns.push(changes);
        total += changes;
    }
    return { total, columns };
}

function branches(tree, outgroup) {
    const rooted = rootTree(tree, outgroup);
    return rooted.order.filter(node => node !== rooted.root).map(node => ({
        u: rooted.parent.get(node), v: node,
        mask: node === outgroup ? rooted.ingroup : rooted.masks.get(node),
        length: rooted.lengths.get(node),
    })).sort((a, b) => a.mask - b.mask);
}

function insert(tree, branch, taxon) {
    const result = clone(tree);
    const node = result.next++;
    disconnect(result, branch.u, branch.v);
    connect(result, branch.u, node);
    connect(result, node, branch.v);
    connect(result, node, taxon);
    return result;
}

function* nniCandidates(tree, outgroup) {
    const rooted = rootTree(tree, outgroup);
    for (const edge of branches(tree, outgroup)) {
        const { u, v, mask } = edge;
        if (u < tree.count || v < tree.count) continue;
        const descendants = rooted.children.get(v).slice().sort((a, b) =>
            rooted.masks.get(a) - rooted.masks.get(b));
        const side = rooted.children.get(u).find(node => node !== v && node !== outgroup);
        for (let index = 0; index < 2; index++) {
            const child = descendants[index];
            const result = clone(tree);
            disconnect(result, u, side);
            disconnect(result, v, child);
            connect(result, u, child);
            connect(result, v, side);
            yield { tree: result, mask, swap: index + 1 };
        }
    }
}

function reconstruct(tree, encoded, outgroup) {
    const rooted = rootTree(tree, outgroup);
    const edges = branches(tree, outgroup);
    const ancestors = new Map(rooted.order.filter(node => node >= tree.count).map(node => [node, '']));
    const branchChanges = new Map(edges.map(edge => [edge.mask, 0]));
    const columns = [];
    let total = 0;
    const first = set => BITS.find(bit => (set & bit) !== 0);
    for (let c = 0; c < encoded[0].length; c++) {
        const { sets, changes } = provisional(tree, rooted, encoded, c);
        columns.push(changes);
        total += changes;
        const x0 = first(merge(sets.get(rooted.root), sets.get(outgroup)).set);
        const states = new Map();
        for (const node of [rooted.root, outgroup]) {
            states.set(node, (sets.get(node) & x0) !== 0 ? x0 : first(sets.get(node)));
        }
        for (const node of rooted.order) {
            if (node === rooted.root || node === outgroup) continue;
            const inherited = states.get(rooted.parent.get(node));
            states.set(node, (sets.get(node) & inherited) !== 0 ? inherited : first(sets.get(node)));
        }
        for (const node of ancestors.keys()) {
            ancestors.set(node, ancestors.get(node) + LETTERS[BITS.indexOf(states.get(node))]);
        }
        for (const edge of edges) {
            if (states.get(edge.u) !== states.get(edge.v)) {
                branchChanges.set(edge.mask, branchChanges.get(edge.mask) + 1);
            }
        }
    }
    for (const edge of edges) connect(tree, edge.u, edge.v, branchChanges.get(edge.mask) / encoded[0].length);
    return { ancestors, branchChanges, columns, total, rooted };
}

module.exports = { merge, provisional, score, branches, insert, nniCandidates, reconstruct };
