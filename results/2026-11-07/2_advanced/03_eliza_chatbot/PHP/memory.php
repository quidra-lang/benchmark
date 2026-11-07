<?php
function memory_store(array &$memory, int $capacity, string $prefix, string $keyword, string $text): bool {
    if (in_array($text, $memory['texts'], true)) {
        $memory['log'][] = "$prefix SKIP $keyword $text";
        return false;
    }
    if (count($memory['texts']) === $capacity) $memory['log'][] = "$prefix DROP " . array_shift($memory['texts']);
    $memory['texts'][] = $text;
    $memory['log'][] = "$prefix STORE $keyword $text";
    return true;
}

function memory_recall(array &$memory, string $prefix): string {
    $text = array_shift($memory['texts']);
    $memory['log'][] = "$prefix RECALL $text";
    return $text;
}

function memory_clear(array &$memory, string $prefix): int {
    $count = count($memory['texts']);
    if ($count > 0) {
        $memory['texts'] = [];
        $memory['log'][] = "$prefix CLEAR $count";
    }
    return $count;
}
