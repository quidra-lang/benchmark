<?php

function real_text(float $value, int $places = 4): string
{
    $text = number_format($value, $places, '.', '');
    return (float) $text === 0.0 ? number_format(0, $places, '.', '') : $text;
}

function ratio_text(int $a, int $b): string
{
    return $b === 0 ? '0/0 -' : "$a/$b " . real_text($a / $b);
}

function fraction_text(int $a, int $b, int $places = 4): string
{
    if ($b === 0) {
        return '- -';
    }
    $x = abs($a);
    $y = $b;
    while ($y !== 0) {
        [$x, $y] = [$y, $x % $y];
    }
    return intdiv($a, $x) . '/' . intdiv($b, $x) . ' ' . real_text($a / $b, $places);
}

class TreeView
{
    public function __construct(public TreeNode $root, public array $cut = [])
    {
    }

    public function isLeaf(TreeNode $node): bool
    {
        return $node->split === null || isset($this->cut[$node->number]);
    }

    public function preorder(?TreeNode $start = null): array
    {
        $nodes = [];
        $pending = [$start ?? $this->root];
        while ($pending) {
            $node = array_pop($pending);
            $nodes[] = $node;
            if (!$this->isLeaf($node)) {
                $pending[] = $node->right;
                $pending[] = $node->left;
            }
        }
        return $nodes;
    }

    public function leaves(?TreeNode $start = null): array
    {
        return array_values(array_filter($this->preorder($start), fn($node) => $this->isLeaf($node)));
    }

    public function internalNodes(): array
    {
        return array_values(array_filter($this->preorder(), fn($node) => !$this->isLeaf($node)));
    }

    public function route(DataRow $row): array
    {
        $node = $this->root;
        $path = [];
        $steps = [];
        while (true) {
            $path[] = $node;
            if ($this->isLeaf($node)) {
                return ['leaf' => $node, 'path' => $path, 'steps' => $steps];
            }
            $value = $row->values[$node->split->attribute->index];
            $method = null;
            if ($value !== null) {
                $left = $node->split->goesLeft($value);
                $method = 'primary';
            } else {
                foreach ($node->surrogates as $surrogate) {
                    $value = $row->values[$surrogate['split']->attribute->index];
                    if ($value !== null) {
                        $left = $surrogate['split']->goesLeft($value) === ($surrogate['direction'] === 'left');
                        $method = 'surrogate';
                        break;
                    }
                }
                if ($method === null) {
                    $left = $node->default === 'left';
                    $method = 'default';
                }
            }
            $steps[] = ['node' => $node, 'left' => $left, 'method' => $method];
            $node = $left ? $node->left : $node->right;
        }
    }

    public function predict(DataRow $row): int
    {
        return $this->route($row)['leaf']->prediction;
    }

    public function correctCount(array $rows): int
    {
        return count(array_filter($rows, fn($row) => $this->predict($row) === $row->label));
    }
}

function classification_lines(string $title, array $classes, array $rows, array $predictions): array
{
    $size = count($classes);
    $matrix = array_fill(0, $size, array_fill(0, $size, 0));
    $correct = 0;
    foreach ($rows as $index => $row) {
        $matrix[$row->label][$predictions[$index]]++;
        if ($row->label === $predictions[$index]) {
            $correct++;
        }
    }
    $lines = ["confusion $title correct $correct/" . count($rows) . ' accuracy ' . fraction_text($correct, count($rows)),
        'actual\\predicted ' . implode(' ', $classes)];
    foreach ($classes as $index => $name) {
        $lines[] = $name . ' ' . implode(' ', $matrix[$index]);
    }
    $total = 0.0;
    $available = 0;
    foreach ($classes as $index => $name) {
        $hits = $matrix[$index][$index];
        $predicted = array_sum(array_column($matrix, $index));
        $support = array_sum($matrix[$index]);
        $lines[] = "class $name precision " . fraction_text($hits, $predicted) . ' recall ' . fraction_text($hits, $support)
            . ' f1 ' . fraction_text(2 * $hits, $predicted + $support) . " support $support";
        if ($predicted + $support > 0) {
            $total += 2 * $hits / ($predicted + $support);
            $available++;
        }
    }
    $lines[] = 'macro_f1 ' . ($available > 0 ? real_text($total / $available) : '-');
    return $lines;
}
