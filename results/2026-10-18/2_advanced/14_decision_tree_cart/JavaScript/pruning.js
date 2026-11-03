'use strict';

const { compareFractions } = require('./impurity');
const { isLeaf, preorder, route } = require('./evaluation');

function reducedError(root, validation) {
    const original = { root, cuts: new Set() };
    const visits = new Map(preorder(original).map(node => [node.number, []]));
    for (const row of validation) {
        for (const node of route(original, row).path) visits.get(node.number).push(row);
    }
    const cuts = new Set();
    const decisions = [];
    function visit(node) {
        const rows = visits.get(node.number);
        let leafError = 0;
        for (const row of rows) if (row.label !== node.majority) leafError++;
        if (node.split === null) return leafError;
        const leftError = visit(node.left);
        const rightError = visit(node.right);
        const subtreeError = leftError + rightError;
        const pruned = leafError <= subtreeError;
        if (pruned) cuts.add(node.number);
        decisions.push({ node, rows: rows.length, leafError, subtreeError, pruned });
        return pruned ? leafError : subtreeError;
    }
    visit(root);
    return { view: { root, cuts }, decisions };
}

function costComplexity(root) {
    let view = { root, cuts: new Set() };
    const sequence = [{ view, alpha: { numerator: 0, denominator: 1 } }];
    while (!isLeaf(root, view)) {
        const candidates = [];
        function visit(node) {
            if (isLeaf(node, view)) return { leaves: 1, error: node.error };
            const left = visit(node.left);
            const right = visit(node.right);
            const leaves = left.leaves + right.leaves;
            const error = left.error + right.error;
            candidates.push({
                node,
                value: { numerator: node.error - error, denominator: leaves - 1 },
            });
            return { leaves, error };
        }
        visit(root);
        let minimum = candidates[0].value;
        for (const candidate of candidates) {
            if (compareFractions(candidate.value, minimum) < 0) minimum = candidate.value;
        }
        const cuts = new Set(view.cuts);
        for (const candidate of candidates) {
            if (compareFractions(candidate.value, minimum) === 0) cuts.add(candidate.node.number);
        }
        view = { root, cuts };
        sequence.push({ view, alpha: minimum });
    }
    return sequence;
}

module.exports = { reducedError, costComplexity };
