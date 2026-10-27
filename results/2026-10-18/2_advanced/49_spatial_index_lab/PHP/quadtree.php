<?php

const QUAD_NAMES = ['NW', 'NE', 'SW', 'SE'];

class QuadNode {
    public $x;
    public $y;
    public $size;
    public $points = [];
    public $children = null;

    public function __construct($x, $y, $size) {
        $this->x = $x;
        $this->y = $y;
        $this->size = $size;
    }
}

function quadDestination($node, $point) {
    $half = intdiv($node->size, 2);
    return ($point['x'] >= $node->x + $half ? 1 : 0) + ($point['y'] >= $node->y + $half ? 2 : 0);
}

function quadInsert($node, $point, $bucket) {
    if ($node->children !== null) {
        quadInsert($node->children[quadDestination($node, $point)], $point, $bucket);
        return;
    }
    $node->points[] = $point;
    usort($node->points, fn($a, $b) => $a['id'] <=> $b['id']);
    if (count($node->points) <= $bucket) return;
    $half = intdiv($node->size, 2);
    $node->children = [new QuadNode($node->x, $node->y, $half), new QuadNode($node->x + $half, $node->y, $half),
        new QuadNode($node->x, $node->y + $half, $half), new QuadNode($node->x + $half, $node->y + $half, $half)];
    $previous = $node->points;
    $node->points = [];
    foreach ($previous as $held) quadInsert($node, $held, $bucket);
}

function quadRemove($node, $point, $bucket) {
    if ($node->children === null) {
        foreach ($node->points as $i => $held) if ($held['id'] === $point['id']) {
            array_splice($node->points, $i, 1);
            break;
        }
        return;
    }
    quadRemove($node->children[quadDestination($node, $point)], $point, $bucket);
    $points = [];
    foreach ($node->children as $child) {
        if ($child->children !== null) return;
        foreach ($child->points as $held) $points[] = $held;
    }
    if (count($points) <= $bucket) {
        usort($points, fn($a, $b) => $a['id'] <=> $b['id']);
        $node->points = $points;
        $node->children = null;
    }
}

class QuadTree {
    public $root;
    public $bucket;

    public function __construct($points, $world, $bucket) {
        $this->root = new QuadNode(0, 0, $world);
        $this->bucket = $bucket;
        foreach ($points as $point) $this->insert($point);
    }

    public function insert($point) {
        quadInsert($this->root, $point, $this->bucket);
    }

    public function remove($point) {
        quadRemove($this->root, $point, $this->bucket);
    }
}
