<?php
const TEXT_DIRECTIVES = ['INITIAL', 'FINAL', 'DEFAULT', 'QUESTION', 'REPEAT'];
const GLOBAL_DIRECTIVES = ['INITIAL', 'FINAL', 'QUIT', 'STOP', 'DEFAULT', 'QUESTION', 'REPEAT', 'MEMSIZE', 'PERSIST', 'PRE', 'POST', 'SYNON'];
const RULE_DIRECTIVES = ['DECOMP', 'MEMORY'];
const ITEM_DIRECTIVES = ['REASM', 'GOTO', 'NEWKEY', 'RESTATE'];

function read_lines(string $path): array {
    $lines = explode("\n", file_get_contents($path));
    array_pop($lines);
    return $lines;
}

function is_word(string $word): bool {
    return $word !== '' && $word[0] !== "'" && $word[strlen($word) - 1] !== "'"
        && strspn($word, "abcdefghijklmnopqrstuvwxyz0123456789'") === strlen($word);
}

function reference_number(string $word): ?int {
    return preg_match('/^\([0-9]\)$/D', $word) ? (int)$word[1] : null;
}

function is_number(string $word): bool {
    return preg_match('/^[0-9]{1,2}$/D', $word) === 1;
}

function is_element(string $word): bool {
    return $word === '*' || $word === '#' || ($word[0] === '@' ? is_word(substr($word, 1)) : is_word($word));
}

function well_formed(string $name, array $args): bool {
    $count = count($args);
    if (in_array($name, [...TEXT_DIRECTIVES, 'REASM'], true)) return $count > 0;
    if (in_array($name, ['QUIT', 'STOP'], true)) return $count > 0 && count(array_filter($args, 'is_word')) === $count;
    if ($name === 'MEMSIZE') return $count === 1 && is_number($args[0]) && (int)$args[0] >= 1 && (int)$args[0] <= 20;
    if ($name === 'PERSIST') return $count === 1 && in_array($args[0], ['cycles', 'memory'], true);
    if (in_array($name, ['PRE', 'SYNON'], true)) return $count >= 2 && count(array_filter($args, 'is_word')) === $count;
    if ($name === 'POST') return $count >= 2 && is_word($args[0]);
    if ($name === 'KEY') return $count === 2 && is_word($args[0]) && is_number($args[1]);
    if (in_array($name, RULE_DIRECTIVES, true)) return $count > 0 && count(array_filter($args, 'is_element')) === $count;
    if ($name === 'GOTO') return $count === 1 && is_word($args[0]);
    if ($name === 'NEWKEY') return $count === 0;
    return $name === 'RESTATE' && $count >= 2 && is_word($args[0])
        && count(array_filter(array_slice($args, 1), fn($word) => is_word($word) || reference_number($word) !== null)) === $count - 1;
}

function load_script(string $path): array {
    $script = ['lines' => read_lines($path), 'texts' => array_fill_keys(TEXT_DIRECTIVES, []), 'quit' => [], 'stop' => [],
        'capacity' => 3, 'persist' => [], 'pres' => [], 'posts' => [], 'pre' => [], 'post' => [], 'groups' => [],
        'group_words' => [], 'keywords' => [], 'keyword_map' => [], 'rules' => [], 'items' => [], 'diagnostics' => []];
    $keyword = $rule = null;
    $ignoring = false;
    $first = [];
    foreach ($script['lines'] as $index => $line) {
        if ($line === '' || $line[0] === '#') continue;
        $parts = explode(' ', $line, 2);
        $name = $parts[0];
        $text = $parts[1] ?? '';
        $args = $text === '' ? [] : explode(' ', $text);
        $isRule = in_array($name, RULE_DIRECTIVES, true);
        $isItem = in_array($name, ITEM_DIRECTIVES, true);
        if (in_array($name, GLOBAL_DIRECTIVES, true) || $name === 'KEY') {
            $keyword = $rule = null;
            $ignoring = false;
        } elseif ($isRule || $isItem) {
            if ($ignoring) continue;
            if ($isRule) $rule = null;
        }
        $definition = $name === 'MEMSIZE' ? $name
            : (in_array($name, ['KEY', 'SYNON', 'PRE', 'POST', 'PERSIST'], true) && count($args) > 0 ? "$name $args[0]" : null);
        $problem = null;
        if (!in_array($name, GLOBAL_DIRECTIVES, true) && $name !== 'KEY' && !$isRule && !$isItem) $problem = ['SYNTAX', "unknown directive $name"];
        elseif (!well_formed($name, $args)) $problem = ['SYNTAX', "bad arguments for $name"];
        elseif ($isRule && $keyword === null) $problem = ['ORPHAN', "$name without KEY"];
        elseif ($name === 'REASM' && $rule === null) $problem = ['ORPHAN', 'REASM without DECOMP or MEMORY'];
        elseif (in_array($name, ['GOTO', 'NEWKEY', 'RESTATE'], true) && ($rule === null || $script['rules'][$rule]['kind'] === 'MEMORY')) $problem = ['ORPHAN', "$name without DECOMP"];
        elseif ($definition !== null && isset($first[$definition])) $problem = ['DUPLICATE', "$definition first defined at line $first[$definition]"];
        $number = $index + 1;
        if ($problem !== null) {
            $script['diagnostics'][] = [$number, ...$problem];
            if ($name === 'KEY' && $problem[0] === 'DUPLICATE') $ignoring = true;
            continue;
        }
        if ($definition !== null) $first[$definition] = $number;
        if (in_array($name, TEXT_DIRECTIVES, true)) $script['texts'][$name][] = $text;
        elseif ($name === 'QUIT' || $name === 'STOP') foreach ($args as $word) $script[strtolower($name)][$word] = true;
        elseif ($name === 'MEMSIZE') $script['capacity'] = (int)$args[0];
        elseif ($name === 'PERSIST') $script['persist'][$args[0]] = true;
        elseif ($name === 'PRE' || $name === 'POST') {
            $entry = ['source' => $args[0], 'replacement' => array_slice($args, 1), 'line' => $number];
            $table = strtolower($name);
            $script[$table][$args[0]] = $entry['replacement'];
            $script[$table . 's'][] = $entry;
        } elseif ($name === 'SYNON') {
            $members = array_fill_keys($args, true);
            $script['groups'][] = ['name' => $args[0], 'members' => $members, 'line' => $number];
            $script['group_words'][$args[0]] = $members;
        } elseif ($name === 'KEY') {
            $keyword = count($script['keywords']);
            $script['keyword_map'][$args[0]] = $keyword;
            $script['keywords'][] = ['word' => $args[0], 'rank' => (int)$args[1], 'line' => $number, 'memories' => [], 'decomps' => []];
        } elseif ($isRule) {
            $rule = count($script['rules']);
            $script['rules'][] = ['kind' => $name, 'pattern' => $args, 'line' => $number, 'items' => []];
            $script['keywords'][$keyword][$name === 'MEMORY' ? 'memories' : 'decomps'][] = $rule;
        } else {
            $id = count($script['items']);
            $script['items'][] = ['kind' => $name, 'text' => $text, 'arguments' => $args, 'line' => $number];
            $script['rules'][$rule]['items'][] = $id;
        }
    }
    return $script;
}
