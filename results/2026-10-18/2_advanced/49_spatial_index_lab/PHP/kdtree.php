<?php

class KDNode {
    public $point;
    public $axis;
    public $left = null;
    public $right = null;

    public function __construct($point, $axis) {
        $this->point = $point;
        $this->axis = $axis;
    }
}

function kdCompare($first, $second, $axis) {
    if ($axis === 0) return ($first['x'] <=> $second['x']) ?: (($first['y'] <=> $second['y']) ?: ($first['id'] <=> $second['id']));
    return ($first['y'] <=> $second['y']) ?: (($first['x'] <=> $second['x']) ?: ($first['id'] <=> $second['id']));
}

function kdBuild($points, $depth = 0) {
    if (!$points) return null;
    $axis = $depth % 2;
    usort($points, fn($a, $b) => kdCompare($a, $b, $axis));
    $middle = intdiv(count($points), 2);
    $node = new KDNode($points[$middle], $axis);
    $node->left = kdBuild(array_slice($points, 0, $middle), $depth + 1);
    $node->right = kdBuild(array_slice($points, $middle + 1), $depth + 1);
    return $node;
}

function kdMinimum($node, $axis) {
    if ($node->axis === $axis) return $node->left ? kdMinimum($node->left, $axis) : $node->point;
    $best = $node->point;
    foreach ([$node->left, $node->right] as $child) {
        if ($child === null) continue;
        $candidate = kdMinimum($child, $axis);
        if (kdCompare($candidate, $best, $axis) < 0) $best = $candidate;
    }
    return $best;
}

function kdRemove($node, $point) {
    if ($node->point['id'] === $point['id']) {
        if ($node->right !== null) {
            $node->point = kdMinimum($node->right, $node->axis);
            $node->right = kdRemove($node->right, $node->point);
        } elseif ($node->left !== null) {
            $node->point = kdMinimum($node->left, $node->axis);
            $node->right = kdRemove($node->left, $node->point);
            $node->left = null;
        } else return null;
    } elseif (kdCompare($point, $node->point, $node->axis) < 0) $node->left = kdRemove($node->left, $point);
    else $node->right = kdRemove($node->right, $point);
    return $node;
}

class KDTree {
    public $root;

    public function __construct($points) {
        $this->root = kdBuild($points);
    }

    public function insert($point) {
        if ($this->root === null) {
            $this->root = new KDNode($point, 0);
            return;
        }
        $node = $this->root;
        while (true) {
            $side = kdCompare($point, $node->point, $node->axis) < 0 ? 'left' : 'right';
            if ($node->$side === null) {
                $node->$side = new KDNode($point, 1 - $node->axis);
                return;
            }
            $node = $node->$side;
        }
    }

    public function remove($point) {
        $this->root = kdRemove($this->root, $point);
    }
}
