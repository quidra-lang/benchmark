<?php

function integerWord(string $word): bool
{
    return preg_match('/\A-?[0-9]+\z/', $word) === 1;
}

function readModel(): array
{
    $lines = file('input/model.obj', FILE_IGNORE_NEW_LINES);
    $vertices = [null];
    $polygons = [];
    $groups = [];
    $errors = [];
    $group = 'default';
    $ignored = 0;
    $ignoredKeywords = ['vt', 'vn', 's', 'o', 'usemtl', 'mtllib'];
    foreach ($lines as $index => $line) {
        if ($line === '' || $line[0] === '#') continue;
        $parts = explode(' ', $line);
        $keyword = array_shift($parts);
        $error = null;
        if ($keyword === 'v') {
            if (count($parts) !== 3 || count(array_filter($parts, 'integerWord')) !== 3) {
                $error = 'bad_vertex';
            } else {
                $vertices[] = array_map('intval', $parts);
            }
        } elseif ($keyword === 'f') {
            $references = [];
            if (count($parts) < 3) {
                $error = 'short_face';
            } else {
                foreach ($parts as $reference) {
                    $part = explode('/', $reference, 2)[0];
                    if (!integerWord($part) || (int)$part === 0) {
                        $error = 'bad_index';
                        break;
                    }
                    $value = (int)$part;
                    $number = $value > 0 ? $value : count($vertices) + $value;
                    if ($number < 1 || $number >= count($vertices)) {
                        $error = 'out_of_range';
                        break;
                    }
                    $references[] = $number;
                }
            }
            if ($error === null) {
                $polygons[] = ['number' => count($polygons) + 1, 'line' => $index + 1,
                    'group' => $group, 'vertices' => $references];
                if (!in_array($group, $groups, true)) $groups[] = $group;
            }
        } elseif ($keyword === 'g') {
            $group = $parts[0] ?? 'default';
        } elseif (in_array($keyword, $ignoredKeywords, true)) {
            $ignored++;
        } else {
            $error = 'unknown_keyword';
        }
        if ($error !== null) $errors[] = ['line' => $index + 1, 'kind' => $error];
    }
    return compact('vertices', 'polygons', 'groups', 'errors', 'ignored') + ['lines' => count($lines)];
}

function writeModel(array $vertices, array $faces): void
{
    $lines = ['# vertices ' . (count($vertices) - 1) . ' faces ' . count($faces)];
    for ($i = 1; $i < count($vertices); $i++) $lines[] = 'v ' . implode(' ', $vertices[$i]);
    $group = null;
    foreach ($faces as $face) {
        if ($face['group'] !== $group) {
            $group = $face['group'];
            $lines[] = 'g ' . $group;
        }
        $lines[] = 'f ' . implode(' ', $face['vertices']);
    }
    file_put_contents('output/repaired.obj', implode("\n", $lines) . "\n");
}
