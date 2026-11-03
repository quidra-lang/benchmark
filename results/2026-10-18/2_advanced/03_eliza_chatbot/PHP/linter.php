<?php
const DIAGNOSTIC_CODES = ['SYNTAX', 'ORPHAN', 'DUPLICATE', 'KEY_NO_DECOMP', 'KEY_UNREACHABLE', 'SYNON_UNUSED', 'PRE_CHAIN', 'SYNON_UNKNOWN', 'RULE_NO_REASM', 'RULE_SHADOWED', 'REF_UNBOUND', 'TARGET_UNDEFINED', 'TARGET_CYCLE'];
const ERROR_CODES = ['SYNTAX', 'ORPHAN', 'DUPLICATE', 'SYNON_UNKNOWN', 'REF_UNBOUND', 'TARGET_UNDEFINED', 'TARGET_CYCLE'];

function unknown_groups(array $pattern, array $groups): array {
    $unknown = [];
    foreach ($pattern as $element) if ($element[0] === '@' && !isset($groups[substr($element, 1)])) $unknown[] = substr($element, 1);
    return $unknown;
}

function lint_script(array $script): array {
    $found = $script['diagnostics'];
    $add = function ($line, $code, $message) use (&$found) { $found[] = [$line, $code, $message]; };
    $graph = array_fill(0, count($script['keywords']), []);
    $targets = [];
    foreach ($script['keywords'] as $id => $keyword) foreach ($keyword['decomps'] as $rule) foreach ($script['rules'][$rule]['items'] as $itemId) {
        $item = $script['items'][$itemId];
        if (!in_array($item['kind'], ['GOTO', 'RESTATE'], true)) continue;
        $target = $item['arguments'][0];
        $targets[$target] = true;
        if (isset($script['keyword_map'][$target])) $graph[$id][] = $script['keyword_map'][$target];
    }
    foreach ($script['keywords'] as $id => $keyword) {
        $word = $keyword['word'];
        if (!$keyword['decomps']) $add($keyword['line'], 'KEY_NO_DECOMP', "keyword $word has no DECOMP");
        $replaced = false;
        foreach ($script['pres'] as $pre) if (in_array($word, $pre['replacement'], true)) $replaced = true;
        if (isset($script['pre'][$word]) && !$replaced && !isset($targets[$word])) $add($keyword['line'], 'KEY_UNREACHABLE', "keyword $word is replaced by PRE");
        foreach (['memories', 'decomps'] as $kind) foreach ($keyword[$kind] as $position => $ruleId) {
            $rule = $script['rules'][$ruleId];
            $unknown = unknown_groups($rule['pattern'], $script['group_words']);
            foreach ($unknown as $group) $add($rule['line'], 'SYNON_UNKNOWN', "unknown group $group");
            if (!$rule['items']) $add($rule['line'], 'RULE_NO_REASM', 'rule has no reassembly');
            if (!$unknown) foreach (array_slice($keyword[$kind], 0, $position) as $earlierId) {
                $earlier = $script['rules'][$earlierId];
                if (!unknown_groups($earlier['pattern'], $script['group_words']) && pattern_covers($earlier['pattern'], $rule['pattern'], $script['group_words'])) {
                    $add($rule['line'], 'RULE_SHADOWED', 'pattern is shadowed by line ' . $earlier['line']);
                    break;
                }
            }
            $wildcards = count(array_filter($rule['pattern'], 'wildcard'));
            foreach ($rule['items'] as $itemId) {
                $item = $script['items'][$itemId];
                $references = [];
                if ($item['kind'] === 'REASM') for ($index = 0; $index < strlen($item['text']); $index++) {
                    $number = reference_number(substr($item['text'], $index, 3));
                    if ($number !== null) $references[] = $number;
                }
                elseif ($item['kind'] === 'RESTATE') foreach (array_slice($item['arguments'], 1) as $argument) {
                    $number = reference_number($argument);
                    if ($number !== null) $references[] = $number;
                }
                foreach ($references as $number) if ($number === 0 || $number > $wildcards) $add($item['line'], 'REF_UNBOUND', "reference ($number) is not bound");
                if (!in_array($item['kind'], ['GOTO', 'RESTATE'], true)) continue;
                $target = $item['arguments'][0];
                if (!isset($script['keyword_map'][$target])) $add($item['line'], 'TARGET_UNDEFINED', "target $target is not a keyword");
                else {
                    $pending = [$script['keyword_map'][$target]];
                    $seen = [];
                    while ($pending) {
                        $node = array_pop($pending);
                        if ($node === $id) { $add($item['line'], 'TARGET_CYCLE', "edge $word -> $target is on a cycle"); break; }
                        if (isset($seen[$node])) continue;
                        $seen[$node] = true;
                        array_push($pending, ...$graph[$node]);
                    }
                }
            }
        }
    }
    foreach ($script['groups'] as $group) {
        $used = false;
        foreach ($script['rules'] as $rule) if (in_array('@' . $group['name'], $rule['pattern'], true)) $used = true;
        if (!$used) $add($group['line'], 'SYNON_UNUSED', 'group ' . $group['name'] . ' is never used');
    }
    foreach ($script['pres'] as $pre) foreach ($pre['replacement'] as $word) if (isset($script['pre'][$word])) $add($pre['line'], 'PRE_CHAIN', "replacement $word is itself replaced by PRE");
    usort($found, fn($a, $b) => ($a[0] <=> $b[0]) ?: (array_search($a[1], DIAGNOSTIC_CODES, true) <=> array_search($b[1], DIAGNOSTIC_CODES, true)));
    if (!$found) return ['OK'];
    $errors = count(array_filter($found, fn($diagnostic) => in_array($diagnostic[1], ERROR_CODES, true)));
    $lines = array_map(fn($diagnostic) => implode(' ', $diagnostic), $found);
    $lines[] = 'TOTAL ' . count($found) . " errors=$errors warnings=" . (count($found) - $errors);
    return $lines;
}
