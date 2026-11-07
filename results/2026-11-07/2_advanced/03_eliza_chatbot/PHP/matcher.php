<?php
function wildcard(string $element): bool {
    return $element === '*' || $element === '#' || $element[0] === '@';
}

function word_fits(string $element, string $word, array $groups): bool {
    if ($element === '#') return true;
    return $element[0] === '@' ? isset($groups[substr($element, 1)][$word]) : $element === $word;
}

function match_pattern(array $pattern, array $words, array $groups): ?array {
    $search = function ($position, $start, $bindings) use (&$search, $pattern, $words, $groups) {
        if ($position === count($pattern)) return $start === count($words) ? $bindings : null;
        $element = $pattern[$position];
        if ($element === '*') $ends = range($start, count($words));
        elseif ($start < count($words) && word_fits($element, $words[$start], $groups)) $ends = [$start + 1];
        else return null;
        foreach ($ends as $end) {
            $next = $bindings;
            if (wildcard($element)) $next[] = array_slice($words, $start, $end - $start);
            $result = $search($position + 1, $end, $next);
            if ($result !== null) return $result;
        }
        return null;
    };
    return $search(0, 0, []);
}

function pattern_covers(array $earlier, array $later, array $groups): bool {
    $fits = function ($element, $other) use ($groups) {
        if ($element === '#') return $other !== '*';
        if ($element[0] !== '@') return $element === $other;
        $members = $groups[substr($element, 1)];
        if ($other[0] !== '@') return isset($members[$other]);
        return count(array_diff_key($groups[substr($other, 1)], $members)) === 0;
    };
    $search = function ($position, $start) use (&$search, $earlier, $later, $fits) {
        if ($position === count($earlier)) return $start === count($later);
        if ($earlier[$position] === '*') {
            for ($end = $start; $end <= count($later); $end++) if ($search($position + 1, $end)) return true;
            return false;
        }
        return $start < count($later) && $fits($earlier[$position], $later[$start]) && $search($position + 1, $start + 1);
    };
    return $search(0, 0);
}
