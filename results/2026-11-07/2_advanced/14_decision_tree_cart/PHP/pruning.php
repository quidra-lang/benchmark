<?php

function reduced_error_pruning(TreeNode $root, array $rows): array
{
    $original = new TreeView($root);
    $reached = [];
    $errors = [];
    foreach ($rows as $row) {
        foreach ($original->route($row)['path'] as $node) {
            $reached[$node->number] = ($reached[$node->number] ?? 0) + 1;
            if ($row->label !== $node->prediction) {
                $errors[$node->number] = ($errors[$node->number] ?? 0) + 1;
            }
        }
    }
    $cut = [];
    $decisions = [];
    $visit = function ($node) use (&$visit, &$cut, &$decisions, $reached, $errors) {
        $leafError = $errors[$node->number] ?? 0;
        if ($node->split === null) {
            return $leafError;
        }
        $leftError = $visit($node->left);
        $subtreeError = $leftError + $visit($node->right);
        $pruned = $leafError <= $subtreeError;
        if ($pruned) {
            $cut[$node->number] = true;
        }
        $decisions[] = ['node' => $node, 'rows' => $reached[$node->number] ?? 0,
            'leaf_error' => $leafError, 'subtree_error' => $subtreeError, 'pruned' => $pruned];
        return $pruned ? $leafError : $subtreeError;
    };
    $visit($root);
    return [new TreeView($root, $cut), $decisions];
}

function cost_complexity_sequence(TreeNode $root): array
{
    $tree = new TreeView($root);
    $sequence = [['alpha' => [0, 1], 'tree' => $tree]];
    while (!$tree->isLeaf($root)) {
        $alpha = null;
        $weakest = [];
        foreach ($tree->internalNodes() as $node) {
            $leaves = $tree->leaves($node);
            $value = [$node->errors - array_sum(array_map(fn($leaf) => $leaf->errors, $leaves)), count($leaves) - 1];
            $comparison = $alpha === null ? -1 : compare_fractions($value, $alpha);
            if ($comparison < 0) {
                $alpha = $value;
                $weakest = [$node->number => true];
            } elseif ($comparison === 0) {
                $weakest[$node->number] = true;
            }
        }
        $tree = new TreeView($root, $tree->cut + $weakest);
        $sequence[] = ['alpha' => $alpha, 'tree' => $tree];
    }
    return $sequence;
}
