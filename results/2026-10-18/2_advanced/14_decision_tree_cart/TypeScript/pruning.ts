import type { Row } from './dataset.ts';
import { compareFractions } from './impurity.ts';
import type { Fraction } from './impurity.ts';
import type { BranchNode, TreeNode, TreeView } from './tree_builder.ts';
import { isBranch, preorder, route } from './evaluation.ts';

export interface PruningDecision {
    node: BranchNode; rows: number; leafError: number; subtreeError: number; pruned: boolean;
}
export interface PruningResult { view: TreeView; decisions: PruningDecision[] }
export interface SequenceTree { view: TreeView; alpha: Fraction }
export function reducedError(root: TreeNode, validation: Row[]): PruningResult {
    const original: TreeView = { root, cuts: new Set() };
    const visits = new Map<number, Row[]>(preorder(original).map(node => [node.number, []]));
    for (const row of validation) for (const node of route(original, row).path) visits.get(node.number)!.push(row);
    const cuts = new Set<number>();
    const decisions: PruningDecision[] = [];
    function visit(node: TreeNode): number {
        const rows = visits.get(node.number)!;
        const leafError = rows.reduce((sum, row) => sum + Number(row.label !== node.majority), 0);
        if (node.kind === 'leaf') return leafError;
        const subtreeError = visit(node.left) + visit(node.right);
        const pruned = leafError <= subtreeError;
        if (pruned) cuts.add(node.number);
        decisions.push({ node, rows: rows.length, leafError, subtreeError, pruned });
        return pruned ? leafError : subtreeError;
    }
    visit(root);
    return { view: { root, cuts }, decisions };
}
export function costComplexity(root: TreeNode): SequenceTree[] {
    let view: TreeView = { root, cuts: new Set() };
    const sequence: SequenceTree[] = [{ view, alpha: { numerator: 0, denominator: 1 } }];
    while (isBranch(root, view)) {
        const candidates: { node: BranchNode; value: Fraction }[] = [];
        function visit(node: TreeNode): { leaves: number; error: number } {
            if (!isBranch(node, view)) return { leaves: 1, error: node.error };
            const left = visit(node.left), right = visit(node.right);
            const leaves = left.leaves + right.leaves, error = left.error + right.error;
            candidates.push({ node, value: { numerator: node.error - error, denominator: leaves - 1 } });
            return { leaves, error };
        }
        visit(root);
        let minimum = candidates[0].value;
        for (const candidate of candidates) if (compareFractions(candidate.value, minimum) < 0) minimum = candidate.value;
        const cuts = new Set(view.cuts);
        for (const candidate of candidates) if (compareFractions(candidate.value, minimum) === 0) cuts.add(candidate.node.number);
        view = { root, cuts };
        sequence.push({ view, alpha: minimum });
    }
    return sequence;
}
