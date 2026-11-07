<?php

function realNumber(float $value, int $digits): string
{
    $text = sprintf('%.' . $digits . 'F', $value);
    return $text[0] === '-' && (float) $text == 0.0 ? substr($text, 1) : $text;
}

function symbols(int $mask, int $count): string
{
    $result = '';
    for ($i = 0; $i < $count; $i++) {
        $result .= ($mask & (1 << $i)) !== 0 ? '*' : '.';
    }
    return $result;
}

function orderedRoot(object $tree, int $outgroup, array $names): object
{
    $rooted = rootTree($tree, $outgroup);
    $minimum = [];
    foreach ($rooted->masks as $node => $mask) {
        $contained = [];
        foreach ($names as $i => $name) {
            if (($mask & (1 << $i)) !== 0) {
                $contained[] = $name;
            }
        }
        sort($contained, SORT_STRING);
        $minimum[$node] = $contained[0];
    }
    foreach ($rooted->children as $node => $children) {
        usort($children, fn($a, $b) => strcmp($minimum[$a], $minimum[$b]));
        $rooted->children[$node] = $children;
    }
    return $rooted;
}

function renderNewick(object $tree, object $rooted, array $names, int $node, bool $lengths, ?array $support): string
{
    if ($node < $tree->count) {
        $text = $names[$node];
    } else {
        $children = [];
        foreach ($rooted->children[$node] as $child) {
            $children[] = renderNewick($tree, $rooted, $names, $child, $lengths, $support);
        }
        $text = '(' . implode(',', $children) . ')';
        if ($node !== $rooted->root && $support !== null) {
            $text .= ($support[$rooted->masks[$node]] ?? 0);
        }
    }
    if ($node !== $rooted->root && $lengths) {
        $text .= ':' . realNumber($rooted->lengths[$node], 5);
    }
    return $text;
}

function newick(object $tree, int $outgroup, array $names, bool $lengths = false, ?array $support = null): string
{
    $rooted = orderedRoot($tree, $outgroup, $names);
    return renderNewick($tree, $rooted, $names, $rooted->root, $lengths, $support) . ';';
}

function cladogramVisit(object $tree, object $rooted, array $names, array $support, int $node, string $prefix, bool $last, array &$lines): void
{
    $label = $node < $tree->count ? $names[$node] : '[' . ($support[$rooted->masks[$node]] ?? 0) . ']';
    $lines[] = $prefix . ($last ? '`-- ' : '|-- ') . $label;
    $children = $rooted->children[$node];
    foreach ($children as $i => $child) {
        cladogramVisit($tree, $rooted, $names, $support, $child, $prefix . ($last ? '    ' : '|   '), $i === count($children) - 1, $lines);
    }
}

function cladogram(object $tree, int $outgroup, array $names, array $support): array
{
    $rooted = orderedRoot($tree, $outgroup, $names);
    $lines = ['*'];
    $children = $rooted->children[$rooted->root];
    foreach ($children as $i => $child) {
        cladogramVisit($tree, $rooted, $names, $support, $child, '', $i === count($children) - 1, $lines);
    }
    return $lines;
}

function writeLines(string $name, array $lines): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
