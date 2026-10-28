<?php

const TYPES = ['ordinary', 'operator', 'binary', 'relation', 'open', 'close', 'punctuation'];

const SPACING = [
    [0,   1,   'B',  'R',  0,   0,    0],
    [1,   1,   null, 'R',  0,   0,    0],
    ['B', 'B', null, null, 'B', null, null],
    ['R', 'R', null, 0,    'R', 0,    0],
    [0,   0,   null, 0,    0,   0,    0],
    [0,   1,   'B',  'R',  0,   0,    0],
    ['P', 'P', null, 'P',  'P', 'P',  'P'],
];

function elementTypes(MathNode $node): array
{
    if ($node->kind === 'symbol')
        $kind = symbolType($node->value);
    elseif ($node->kind === 'command')
        $kind = symbolCommands()[$node->value][1];
    elseif ($node->kind === 'delim')
        return ['open', 'close'];
    elseif ($node->kind === 'script')
        return elementTypes($node->children[0]);
    elseif ($node->kind === 'overset' || $node->kind === 'underset')
        return elementTypes($node->children[1]);
    else
        $kind = 'ordinary';
    return [$kind, $kind];
}

function convertedTypes(array $nodes): array
{
    $result = array_map(elementTypes(...), $nodes);
    foreach ($result as $i => $unused) {
        if (
            $result[$i][0] === 'binary'
            && (
                $i === 0
                || in_array(
                    $result[$i - 1][1],
                    ['binary', 'operator', 'relation', 'open', 'punctuation'],
                    true,
                )
            )
        )
            $result[$i] = ['ordinary', 'ordinary'];
        if (
            $i > 0
            && in_array($result[$i][0], ['relation', 'close', 'punctuation'], true)
            && $result[$i - 1][1] === 'binary'
        )
            $result[$i - 1] = ['ordinary', 'ordinary'];
    }
    $n = count($result);
    if ($n && $result[$n - 1][1] === 'binary')
        $result[$n - 1] = ['ordinary', 'ordinary'];
    return $result;
}

function wordElement(MathNode $n): bool
{
    if ($n->kind === 'script')
        return wordElement($n->children[0]);
    return $n->kind === 'command' && (in_array(substr($n->value, 1), GREEK, true) || $n->value === '\\infty');
}

function alphanumeric(MathNode $n): bool
{
    if ($n->kind === 'identifier' || $n->kind === 'number' || wordElement($n))
        return true;
    if ($n->kind === 'script')
        return alphanumeric($n->children[0]);
    return (
        $n->kind === 'accent'
        && in_array($n->value, ['overline', 'hat', 'vec', 'dot', 'tilde'], true)
        && alphanumeric($n->children[0])
    );
}

function spacing(array $nodes, string $style, array $params): array
{
    $types = convertedTypes($nodes);
    $values = [
        'B' => $style === 'normal' ? $params['bin_space'] : 0,
        'R' => $style === 'normal' ? $params['rel_space'] : 0,
        'P' => $style === 'normal' ? $params['punct_space'] : 0,
    ];
    $gaps = [];
    for ($i = 0; $i < (count($nodes) - 1); ++$i) {
        $a = $nodes[$i];
        $b = $nodes[$i + 1];
        if (alphanumeric($a) && alphanumeric($b) && (wordElement($a) || wordElement($b)))
            $gaps[] = 1;
        else {
            $entry = SPACING[array_search($types[$i][1], TYPES, true)][array_search(
                $types[$i + 1][0],
                TYPES,
                true,
            )];
            $gaps[] = is_string($entry) ? $values[$entry] : $entry;
        }
    }
    return [$types, $gaps];
}

function rowBox(array $children, array $gaps, string $description = 'row', ?array $roles = null): Box
{
    $ascent = $descent = $width = 0;
    foreach ($children as $child) {
        $ascent = max($ascent, $child->baseline);
        $descent = max($descent, $child->descent());
        $width += $child->width;
    }
    $width += array_sum($gaps);
    $box = new Box($width, $ascent + $descent + 1, $ascent, $description);
    $x = 0;
    foreach ($children as $i => $child) {
        $box->add($child, $x, $ascent - $child->baseline, $roles[$i] ?? '');
        $x += $child->width + ($gaps[$i] ?? 0);
    }
    return $box;
}
