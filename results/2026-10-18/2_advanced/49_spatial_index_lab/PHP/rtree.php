<?php

function area($box) {
    return ($box[2] - $box[0]) * ($box[3] - $box[1]);
}

function boxUnion($first, $second) {
    return [min($first[0], $second[0]), min($first[1], $second[1]), max($first[2], $second[2]), max($first[3], $second[3])];
}

function nodeBox($node) {
    $result = $node->entries[0]['box'];
    foreach (array_slice($node->entries, 1) as $entry) $result = boxUnion($result, $entry['box']);
    return $result;
}

function enlargement($first, $second) {
    return area(boxUnion($first, $second)) - area($first);
}

function contains($first, $second) {
    return $first[0] <= $second[0] && $second[2] <= $first[2] && $first[1] <= $second[1] && $second[3] <= $first[3];
}

function intersects($first, $second) {
    return $first[0] <= $second[2] && $second[0] <= $first[2] && $first[1] <= $second[3] && $second[1] <= $first[3];
}

function overlap($first, $second) {
    $width = min($first[2], $second[2]) - max($first[0], $second[0]);
    $height = min($first[3], $second[3]) - max($first[1], $second[1]);
    return $width > 0 && $height > 0 ? $width * $height : 0;
}

function compareTuple($first, $second) {
    foreach ($first as $i => $value) if ($value !== $second[$i]) return $value <=> $second[$i];
    return 0;
}

class RNode {
    public $level;
    public $entries;
    public $parent = null;

    public function __construct($level, $entries = []) {
        $this->level = $level;
        $this->entries = $entries;
        foreach ($entries as $entry) if (isset($entry['child'])) $entry['child']->parent = $this;
    }
}

function leafEntry($object) {
    return ['box' => $object['box'], 'object' => $object];
}

function childEntry($child) {
    return ['box' => nodeBox($child), 'child' => $child];
}

function splitNode($node, $minimum) {
    $entries = $node->entries;
    $seeds = [0, 1];
    $waste = PHP_INT_MIN;
    for ($i = 0; $i < count($entries) - 1; $i++) for ($j = $i + 1; $j < count($entries); $j++) {
        $value = area(boxUnion($entries[$i]['box'], $entries[$j]['box'])) - area($entries[$i]['box']) - area($entries[$j]['box']);
        if ($value > $waste) {
            $waste = $value;
            $seeds = [$i, $j];
        }
    }
    $groups = [[$entries[$seeds[0]]], [$entries[$seeds[1]]]];
    $bounds = [$entries[$seeds[0]]['box'], $entries[$seeds[1]]['box']];
    $rest = [];
    foreach ($entries as $i => $entry) if ($i !== $seeds[0] && $i !== $seeds[1]) $rest[] = $entry;
    while ($rest) {
        if (count($groups[0]) + count($rest) === $minimum) {
            $groups[0] = array_merge($groups[0], $rest);
            break;
        }
        if (count($groups[1]) + count($rest) === $minimum) {
            $groups[1] = array_merge($groups[1], $rest);
            break;
        }
        $chosen = 0;
        $largest = -1;
        foreach ($rest as $i => $entry) {
            $difference = abs(enlargement($bounds[0], $entry['box']) - enlargement($bounds[1], $entry['box']));
            if ($difference > $largest) {
                $largest = $difference;
                $chosen = $i;
            }
        }
        $entry = array_splice($rest, $chosen, 1)[0];
        $first = [enlargement($bounds[0], $entry['box']), area($bounds[0]), count($groups[0])];
        $second = [enlargement($bounds[1], $entry['box']), area($bounds[1]), count($groups[1])];
        $target = compareTuple($first, $second) <= 0 ? 0 : 1;
        $groups[$target][] = $entry;
        $bounds[$target] = boxUnion($bounds[$target], $entry['box']);
    }
    $node->entries = $groups[0];
    foreach ($node->entries as $entry) if (isset($entry['child'])) $entry['child']->parent = $node;
    return new RNode($node->level, $groups[1]);
}

function bulkLoad($objects, $maximum) {
    $entries = [];
    foreach ($objects as $object) {
        $entry = leafEntry($object);
        $entry['number'] = $object['id'];
        $entries[] = $entry;
    }
    $level = 0;
    while (true) {
        $pages = intdiv(count($entries) + $maximum - 1, $maximum);
        $slabs = 1;
        while ($slabs * $slabs < $pages) $slabs++;
        usort($entries, fn($a, $b) => compareTuple([$a['box'][0] + $a['box'][2], $a['box'][1] + $a['box'][3], $a['number']],
            [$b['box'][0] + $b['box'][2], $b['box'][1] + $b['box'][3], $b['number']]));
        $nodes = [];
        for ($start = 0; $start < count($entries); $start += $slabs * $maximum) {
            $slab = array_slice($entries, $start, $slabs * $maximum);
            usort($slab, fn($a, $b) => compareTuple([$a['box'][1] + $a['box'][3], $a['box'][0] + $a['box'][2], $a['number']],
                [$b['box'][1] + $b['box'][3], $b['box'][0] + $b['box'][2], $b['number']]));
            for ($offset = 0; $offset < count($slab); $offset += $maximum) $nodes[] = new RNode($level, array_slice($slab, $offset, $maximum));
        }
        if (count($nodes) === 1) return $nodes[0];
        $entries = [];
        foreach ($nodes as $number => $node) {
            $entry = childEntry($node);
            $entry['number'] = $number;
            $entries[] = $entry;
        }
        $level++;
    }
}

function findLeaf($node, $object) {
    if ($node->level === 0) {
        foreach ($node->entries as $i => $entry) if ($entry['object']['id'] === $object['id']) return [$node, $i];
        return null;
    }
    foreach ($node->entries as $entry) {
        if (!contains($entry['box'], $object['box'])) continue;
        $found = findLeaf($entry['child'], $object);
        if ($found !== null) return $found;
    }
    return null;
}

class RTree {
    public $root;
    public $maximum;
    public $minimum;

    public function __construct($objects, $maximum, $minimum, $bulk = false) {
        $this->maximum = $maximum;
        $this->minimum = $minimum;
        $this->root = $bulk ? bulkLoad($objects, $maximum) : new RNode(0);
        if (!$bulk) foreach ($objects as $object) $this->insert($object);
    }

    public function choose($entry, $level) {
        $node = $this->root;
        while ($node->level > $level) {
            $selected = 0;
            $priority = [enlargement($node->entries[0]['box'], $entry['box']), area($node->entries[0]['box'])];
            foreach ($node->entries as $i => $candidate) {
                $value = [enlargement($candidate['box'], $entry['box']), area($candidate['box'])];
                if (compareTuple($value, $priority) < 0) {
                    $priority = $value;
                    $selected = $i;
                }
            }
            $node = $node->entries[$selected]['child'];
        }
        return $node;
    }

    public function insertEntry($entry, $level) {
        $node = $this->choose($entry, $level);
        $node->entries[] = $entry;
        if (isset($entry['child'])) $entry['child']->parent = $node;
        while (true) {
            $sibling = count($node->entries) > $this->maximum ? splitNode($node, $this->minimum) : null;
            if ($node === $this->root) {
                if ($sibling !== null) $this->root = new RNode($node->level + 1, [childEntry($node), childEntry($sibling)]);
                return;
            }
            $parent = $node->parent;
            foreach ($parent->entries as $i => $item) if ($item['child'] === $node) {
                $parent->entries[$i]['box'] = nodeBox($node);
                break;
            }
            if ($sibling !== null) {
                $parent->entries[] = childEntry($sibling);
                $sibling->parent = $parent;
            }
            $node = $parent;
        }
    }

    public function insert($object) {
        $this->insertEntry(leafEntry($object), 0);
    }

    public function remove($object) {
        [$node, $index] = findLeaf($this->root, $object);
        array_splice($node->entries, $index, 1);
        $removed = [];
        while ($node !== $this->root) {
            $parent = $node->parent;
            foreach ($parent->entries as $i => $entry) if ($entry['child'] === $node) {
                $index = $i;
                break;
            }
            if (count($node->entries) < $this->minimum) {
                array_splice($parent->entries, $index, 1);
                $removed[] = $node;
                $node->parent = null;
            } else $parent->entries[$index]['box'] = nodeBox($node);
            $node = $parent;
        }
        foreach ($removed as $detached) foreach ($detached->entries as $entry) $this->insertEntry($entry, $detached->level);
        while ($this->root->level > 0 && count($this->root->entries) === 1) {
            $this->root = $this->root->entries[0]['child'];
            $this->root->parent = null;
        }
    }
}
