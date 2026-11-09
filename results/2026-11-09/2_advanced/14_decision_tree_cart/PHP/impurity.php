<?php

function class_counts(array $rows, int $size): array
{
    $counts = array_fill(0, $size, 0);
    foreach ($rows as $row) {
        $counts[$row->label]++;
    }
    return $counts;
}

function square_sum(array $counts): int
{
    return array_sum(array_map(fn($value) => $value * $value, $counts));
}

function majority(array $counts): int
{
    return array_search(max($counts), $counts, true);
}

function evaluation_value(array $left, array $right): array
{
    $nl = array_sum($left);
    $nr = array_sum($right);
    return [square_sum($left) * $nr + square_sum($right) * $nl, $nl * $nr];
}

function compare_fractions(array $first, array $second): int
{
    return $first[0] * $second[1] <=> $second[0] * $first[1];
}

function improves(array $value, array $counts): bool
{
    return $value[0] * array_sum($counts) > square_sum($counts) * $value[1];
}

function impurity_decrease(TreeNode $node): float
{
    $left = square_sum($node->left->counts) / $node->left->size;
    $right = square_sum($node->right->counts) / $node->right->size;
    $parent = square_sum($node->counts) / $node->size;
    return ($left + $right) - $parent;
}
