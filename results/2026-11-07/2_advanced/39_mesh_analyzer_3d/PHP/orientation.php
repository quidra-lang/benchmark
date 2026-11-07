<?php

function containsDirection(array $face, int $a, int $b): bool
{
    $vertices = $face['vertices'];
    for ($i = 0; $i < 3; $i++) {
        if ($vertices[$i] === $a && $vertices[($i + 1) % 3] === $b) return true;
    }
    return false;
}

function flipFace(array &$face): void
{
    [$face['vertices'][1], $face['vertices'][2]] = [$face['vertices'][2], $face['vertices'][1]];
}

function inconsistentEdges(array $faces, array $topology): array
{
    $result = [];
    foreach ($topology['edges'] as $key) {
        $edge = $topology['edgeMap'][$key];
        if (count($edge['faces']) === 2 &&
            containsDirection($faces[$edge['faces'][0]], $edge['a'], $edge['b']) ===
            containsDirection($faces[$edge['faces'][1]], $edge['a'], $edge['b'])) $result[] = $key;
    }
    return $result;
}

function orientFaces(array &$faces, array $topology): void
{
    $visited = array_fill(0, count($faces), false);
    foreach (array_keys($faces) as $start) {
        if ($visited[$start]) continue;
        $visited[$start] = true;
        $queue = [$start];
        for ($head = 0; $head < count($queue); $head++) {
            $index = $queue[$head];
            $vertices = $faces[$index]['vertices'];
            for ($i = 0; $i < 3; $i++) {
                $a = $vertices[$i];
                $b = $vertices[($i + 1) % 3];
                $edge = $topology['edgeMap'][edgeKey($a, $b)];
                if (count($edge['faces']) !== 2) continue;
                $other = $edge['faces'][0] === $index ? $edge['faces'][1] : $edge['faces'][0];
                if ($visited[$other]) continue;
                if (containsDirection($faces[$other], $a, $b)) flipFace($faces[$other]);
                $visited[$other] = true;
                $queue[] = $other;
            }
        }
    }
}
