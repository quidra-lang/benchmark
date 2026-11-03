<?php

require_once __DIR__ . '/grammar_parser.php';
require_once __DIR__ . '/transform.php';
require_once __DIR__ . '/first_follow.php';
require_once __DIR__ . '/table.php';
require_once __DIR__ . '/driver.php';

function terminalOrder(array $values): array
{
    $values = array_map('strval', $values);
    usort($values, fn($a, $b) => $a === $b ? 0 : ($a === '$' ? 1 : ($b === '$' ? -1 : strcmp($a, $b))));
    return $values;
}

function listLine(string $heading, array $values): string
{
    return $heading . ($values ? ' ' . implode(' ', $values) : '');
}

function sections(array $parts): array
{
    $result = [];
    foreach ($parts as $index => $part) {
        if ($index > 0) $result[] = '';
        foreach ($part as $line) $result[] = $line;
    }
    return $result;
}

function prune(object $grammar, array $keep): void
{
    $grammar->order = array_values(array_filter($grammar->order, fn($name) => isset($keep[$name])));
    foreach (array_keys($grammar->rules) as $name) if (!isset($keep[$name])) unset($grammar->rules[$name]);
}

function reachable(object $grammar): array
{
    $queue = [$grammar->start];
    $seen = [$grammar->start => true];
    for ($head = 0; $head < count($queue); $head++) {
        foreach ($grammar->rules[$queue[$head]] as $right) foreach ($right as $symbol) {
            if (isNonterminal($symbol) && !isset($seen[$symbol])) {
                $seen[$symbol] = true;
                $queue[] = $symbol;
            }
        }
    }
    return $seen;
}

function checkDeclarations(object $parsed): array
{
    if (!$parsed->hasDeclarations) return [];
    $missing = [];
    foreach ($parsed->wordLines as $name => $line) if (!isset($parsed->declared[$name])) $missing[] = (string) $name;
    return array_map(fn($name) => 'undeclared terminal ' . $name . ' at line ' . $parsed->wordLines[$name], terminalOrder($missing));
}

function cleanGrammar(object $original): object
{
    $grammar = copyGrammar($original);
    $diagnostics = [];
    $undefined = [];
    foreach ($grammar->rules as $alternatives) foreach ($alternatives as $right) foreach ($right as $symbol) {
        if (isNonterminal($symbol) && !isset($grammar->rules[$symbol])) $undefined[$symbol] = true;
    }
    $undefinedOrder = array_keys($undefined);
    usort($undefinedOrder, fn($a, $b) => strcmp(substr($a, 1, -1), substr($b, 1, -1)));
    foreach ($undefinedOrder as $name) $diagnostics[] = 'undefined nonterminal ' . $name;
    $remove = function (array $names, string $reason) use ($grammar, &$diagnostics): void {
        foreach ($grammar->order as $left) {
            $kept = [];
            foreach ($grammar->rules[$left] as $right) {
                $removed = null;
                foreach ($right as $symbol) if (isset($names[$symbol])) {
                    $removed = $symbol;
                    break;
                }
                if ($removed === null) $kept[] = $right;
                else $diagnostics[] = 'removed ' . productionText($left, $right) . ' (' . $reason . ' ' . $removed . ')';
            }
            $grammar->rules[$left] = $kept;
        }
    };
    $remove($undefined, 'undefined');
    $productive = [];
    do {
        $changed = false;
        foreach ($grammar->order as $name) {
            if (isset($productive[$name])) continue;
            foreach ($grammar->rules[$name] as $right) {
                $all = true;
                foreach ($right as $symbol) if (isNonterminal($symbol) && !isset($productive[$symbol])) {
                    $all = false;
                    break;
                }
                if ($all) {
                    $productive[$name] = true;
                    $changed = true;
                    break;
                }
            }
        }
    } while ($changed);
    $unproductive = [];
    foreach ($grammar->order as $name) if (!isset($productive[$name])) {
        $unproductive[$name] = true;
        $diagnostics[] = 'unproductive nonterminal ' . $name;
    }
    prune($grammar, $productive);
    $remove($unproductive, 'unproductive');
    $reached = reachable($grammar);
    foreach ($grammar->order as $name) if (!isset($reached[$name])) $diagnostics[] = 'unreachable nonterminal ' . $name;
    prune($grammar, $reached);
    return (object) compact('grammar', 'diagnostics');
}

function leftRecursionReport(object $grammar): array
{
    $diagnostics = [];
    foreach ($grammar->order as $start) {
        $queue = [$start];
        $parents = [$start => null];
        $found = null;
        for ($head = 0; $head < count($queue) && $found === null; $head++) {
            $current = $queue[$head];
            foreach ($grammar->rules[$current] as $right) {
                $next = $right[0] ?? null;
                if ($next === $start) {
                    $found = $current;
                    break;
                }
                if ($next !== null && isNonterminal($next) && !array_key_exists($next, $parents)) {
                    $parents[$next] = $current;
                    $queue[] = $next;
                }
            }
        }
        if ($found === null) continue;
        $path = [$found];
        while ($path[count($path) - 1] !== $start) $path[] = $parents[$path[count($path) - 1]];
        $path = array_reverse($path);
        $path[] = $start;
        $diagnostics[] = 'left recursion: ' . implode(' -> ', $path);
    }
    return $diagnostics;
}

function finishGrammar(object $original): object
{
    $grammar = copyGrammar($original);
    $reached = reachable($grammar);
    $removed = array_values(array_filter($grammar->order, fn($name) => !isset($reached[$name])));
    prune($grammar, $reached);
    $log = array_map(fn($name) => 'remove unreachable ' . $name, $removed);
    $diagnostics = array_map(fn($name) => 'unreachable after transformation ' . $name, $removed);
    return (object) compact('grammar', 'log', 'diagnostics');
}

function betterPair(array $candidate, ?array $previous): bool
{
    return $previous === null || $candidate[0] < $previous[0] || ($candidate[0] === $previous[0] && $candidate[1] < $previous[1]);
}

function equalPair(?array $first, ?array $second): bool
{
    return $first !== null && $second !== null && $first[0] === $second[0] && $first[1] === $second[1];
}

function shortestSentences(object $grammar, array $productions): object
{
    $costs = [];
    $measure = function (array $right) use (&$costs): ?array {
        $length = 0;
        $height = 1;
        foreach ($right as $symbol) {
            if (!isNonterminal($symbol)) $length++;
            else {
                $cost = $costs[$symbol] ?? null;
                if ($cost === null) return null;
                $length += $cost[0];
                $height = max($height, $cost[1] + 1);
            }
        }
        return [$length, $height];
    };
    do {
        $changed = false;
        foreach ($grammar->order as $left) foreach ($grammar->rules[$left] as $right) {
            $candidate = $measure($right);
            if ($candidate !== null && betterPair($candidate, $costs[$left] ?? null)) {
                $costs[$left] = $candidate;
                $changed = true;
            }
        }
    } while ($changed);
    $words = [];
    $word = null;
    $expand = null;
    $word = function (string $symbol) use ($grammar, &$words, &$expand, $measure, &$costs): array {
        if (!isNonterminal($symbol)) return [$symbol];
        if (!isset($words[$symbol])) {
            foreach ($grammar->rules[$symbol] as $right) if (equalPair($measure($right), $costs[$symbol])) {
                $words[$symbol] = $expand($right);
                break;
            }
        }
        return $words[$symbol];
    };
    $expand = function (array $symbols) use (&$word): array {
        $tokens = [];
        foreach ($symbols as $symbol) foreach ($word($symbol) as $token) $tokens[] = $token;
        return $tokens;
    };
    $length = function (array $symbols) use (&$costs): int {
        $total = 0;
        foreach ($symbols as $symbol) $total += isNonterminal($symbol) ? $costs[$symbol][0] : 1;
        return $total;
    };
    $contextCosts = [$grammar->start => [0, 0]];
    $occurrenceCost = function (object $production, int $index) use (&$contextCosts, $length): ?array {
        $parent = $contextCosts[$production->left] ?? null;
        if ($parent === null) return null;
        return [$parent[0] + $length(array_slice($production->right, 0, $index)) + $length(array_slice($production->right, $index + 1)), $parent[1] + 1];
    };
    do {
        $changed = false;
        foreach ($productions as $production) foreach ($production->right as $index => $symbol) {
            if (!isNonterminal($symbol) || $symbol === $grammar->start) continue;
            $candidate = $occurrenceCost($production, $index);
            if ($candidate !== null && betterPair($candidate, $contextCosts[$symbol] ?? null)) {
                $contextCosts[$symbol] = $candidate;
                $changed = true;
            }
        }
    } while ($changed);
    $occurrences = [];
    foreach ($productions as $production) foreach ($production->right as $index => $symbol) {
        if (!isNonterminal($symbol) || $symbol === $grammar->start || isset($occurrences[$symbol])) continue;
        if (equalPair($occurrenceCost($production, $index), $contextCosts[$symbol] ?? null)) $occurrences[$symbol] = (object) compact('production', 'index');
    }
    $contexts = [$grammar->start => (object) ['before' => [], 'after' => []]];
    $context = null;
    $context = function (string $symbol) use (&$context, &$contexts, $occurrences, &$expand): object {
        if (!isset($contexts[$symbol])) {
            $occurrence = $occurrences[$symbol];
            $production = $occurrence->production;
            $index = $occurrence->index;
            $parent = $context($production->left);
            $contexts[$symbol] = (object) ['before' => array_merge($parent->before, $expand(array_slice($production->right, 0, $index))),
                'after' => array_merge($expand(array_slice($production->right, $index + 1)), $parent->after)];
        }
        return $contexts[$symbol];
    };
    foreach ($grammar->order as $name) {
        $word($name);
        $context($name);
    }
    $example = function (object $production) use (&$context, &$expand): array {
        $outer = $context($production->left);
        return array_merge($outer->before, $expand($production->right), $outer->after);
    };
    return (object) compact('word', 'example');
}

function firstPath(int $number, string $terminal, object $table, object $sets): array
{
    $queue = [$number];
    $parents = [$number => null];
    for ($head = 0; $head < count($queue); $head++) {
        $current = $queue[$head];
        foreach ($table->productions[$current - 1]->right as $symbol) {
            if ($symbol === $terminal) {
                $path = [];
                for ($node = $current; $node !== $number; $node = $parents[$node]) $path[] = $node;
                return array_reverse($path);
            }
            if (isNonterminal($symbol)) foreach ($table->byLeft[$symbol] as $production) {
                if (array_key_exists($production->number, $parents)) continue;
                $parents[$production->number] = $current;
                $queue[] = $production->number;
            }
            if (!isNonterminal($symbol) || !$sets->nullable[$symbol]) break;
        }
    }
    throw new RuntimeException('FIRST explanation has no derivation');
}

function followPath(string $start, string $terminal, object $grammar, object $table, object $sets): array
{
    $queue = [$start];
    $paths = [$start => []];
    for ($head = 0; $head < count($queue); $head++) {
        $current = $queue[$head];
        $path = $paths[$current];
        if ($current === $grammar->start && $terminal === '$') return $path;
        foreach ($table->productions as $production) foreach ($production->right as $index => $symbol) {
            if ($symbol !== $current) continue;
            $suffix = firstOf(array_slice($production->right, $index + 1), $sets->nullable, $sets->first);
            if (isset($suffix->terminals[$terminal])) return array_merge($path, [$production->number]);
            if ($suffix->nullable && !array_key_exists($production->left, $paths)) {
                $paths[$production->left] = array_merge($path, [$production->number]);
                $queue[] = $production->left;
            }
        }
    }
    throw new RuntimeException('FOLLOW explanation has no derivation');
}

function grammarSummary(object $grammar): string
{
    $productions = numberProductions($grammar);
    $terminals = [];
    $empty = $unit = 0;
    foreach ($productions as $production) {
        foreach ($production->right as $symbol) if (!isNonterminal($symbol)) $terminals[$symbol] = true;
        if (!$production->right) $empty++;
        if (count($production->right) === 1 && isNonterminal($production->right[0])) $unit++;
    }
    return 'start=' . $grammar->start . ' nonterminals=' . count($grammar->order) . ' terminals=' . count($terminals) .
        ' productions=' . count($productions) . ' empty=' . $empty . ' unit=' . $unit;
}

function grammarListing(object $grammar, bool $numbered = false): array
{
    $lines = [];
    $width = strlen((string) count(numberProductions($grammar)));
    $number = 0;
    foreach ($grammar->order as $left) foreach ($grammar->rules[$left] as $index => $right) {
        $number++;
        $prefix = $numbered ? str_pad((string) $number, $width, ' ', STR_PAD_LEFT) . '  ' : '';
        $rule = $index === 0 ? $left . ' -> ' : str_repeat(' ', strlen($left)) . ' | ';
        $lines[] = $prefix . $rule . notation($right);
    }
    return $lines;
}

function grammarReport(object $cleaned, object $eliminated, object $factored, object $final, object $table): array
{
    $stage = function (string $heading, object $result, bool $numbered = false): array {
        return array_merge([$heading], $result->log ?: ['none'], [grammarSummary($result->grammar)], grammarListing($result->grammar, $numbered));
    };
    $reference = ['== cross reference =='];
    foreach (array_merge($final->grammar->order, terminalOrder(array_keys($table->known))) as $symbol) {
        $label = isNonterminal($symbol) ? $symbol : '"' . $symbol . '"';
        $numbers = [];
        foreach ($table->productions as $production) if (in_array($symbol, $production->right, true)) $numbers[] = $production->number;
        $reference[] = $numbers ? listLine($label . ' used in', $numbers) : $label . ' not used';
    }
    return sections([
        array_merge(['== cleaned grammar ==', grammarSummary($cleaned)], grammarListing($cleaned)),
        $stage('== left recursion elimination ==', $eliminated),
        $stage('== left factoring ==', $factored),
        $stage('== final grammar ==', $final, true), $reference]);
}

function setsReport(object $grammar, object $sets, object $shortest): array
{
    $passes = $sets->passes;
    $lines = ['passes: nullable=' . $passes->nullable . ' first=' . $passes->first . ' follow=' . $passes->follow, ''];
    foreach ($grammar->order as $name) {
        $lines[] = $name;
        $lines[] = '  nullable: ' . ($sets->nullable[$name] ? 'yes' : 'no');
        $lines[] = listLine('  first:', terminalOrder(array_keys($sets->first[$name])));
        $lines[] = listLine('  follow:', terminalOrder(array_keys($sets->follow[$name])));
        $lines[] = listLine('  shortest:', ($shortest->word)($name));
    }
    return $lines;
}

function tableReport(object $grammar, object $table, object $sets, int $before): array
{
    $lines = ['== predict sets =='];
    foreach ($table->productions as $production) {
        $lines[] = $production->number . ': ' . productionText($production->left, $production->right);
        $lines[] = listLine('  predict:', terminalOrder(array_keys($production->reasons)));
    }
    $rows = [array_merge([''], $table->columns)];
    foreach ($grammar->order as $name) {
        $row = [$name];
        foreach ($table->columns as $terminal) {
            $entries = $table->cells[$name][$terminal];
            $row[] = $entries ? implode('/', array_map(fn($production) => $production->number, $entries)) : '.';
        }
        $rows[] = $row;
    }
    $widths = array_fill(0, count($rows[0]), 0);
    foreach ($rows as $row) foreach ($row as $index => $value) $widths[$index] = max($widths[$index], strlen((string) $value));
    $lines[] = '';
    $lines[] = '== parse table ==';
    foreach ($rows as $row) {
        $line = str_pad($row[0], $widths[0]);
        for ($index = 1; $index < count($row); $index++) $line .= '  ' . str_pad($row[$index], $widths[$index], ' ', STR_PAD_LEFT);
        $lines[] = $line;
    }
    $lines[] = '';
    $lines[] = '== conflicts ==';
    if (!$table->conflicts) $lines[] = 'none';
    foreach ($table->conflicts as $conflict) {
        $lines[] = 'conflict ' . $conflict->left . ' on ' . $conflict->terminal . ': ' . $conflict->kind . ', chosen ' . $conflict->chosen->number;
        foreach ($conflict->entries as $production) {
            $reason = $production->reasons[$conflict->terminal];
            $path = $reason === 'FIRST' ? firstPath($production->number, $conflict->terminal, $table, $sets)
                : followPath($conflict->left, $conflict->terminal, $grammar, $table, $sets);
            $explanation = $reason . ($path ? ' via ' . implode(' ', $path) : '');
            $lines[] = '  ' . $production->number . ': ' . productionText($production->left, $production->right) . ' (' . $explanation . ')';
        }
    }
    $lines[] = 'LL(1): ' . ($table->conflicts ? 'no' : 'yes');
    $lines[] = 'conflicts before transformation: ' . $before;
    return $lines;
}

function languageModel(object $grammar, object $table, object $sets): object
{
    $productions = array_merge([(object) ['left' => null, 'right' => [$grammar->start]]], $table->productions);
    $byLeft = [];
    foreach ($grammar->order as $name) $byLeft[$name] = [];
    for ($number = 1; $number < count($productions); $number++) $byLeft[$productions[$number]->left][] = $number;
    return (object) ['productions' => $productions, 'byLeft' => $byLeft, 'nullable' => $sets->nullable, 'terminals' => $table->known];
}

function inLanguage(array $tokens, object $model): bool
{
    foreach ($tokens as $token) if (!isset($model->terminals[$token])) return false;
    $charts = [];
    for ($i = 0; $i <= count($tokens); $i++) $charts[] = (object) ['items' => [], 'seen' => [], 'waiting' => []];
    $add = function (int $position, int $production, int $dot, int $origin) use ($charts): void {
        $chart = $charts[$position];
        $key = $production . '/' . $dot . '/' . $origin;
        if (isset($chart->seen[$key])) return;
        $chart->seen[$key] = true;
        $chart->items[] = (object) compact('production', 'dot', 'origin');
    };
    $add(0, 0, 0, 0);
    foreach ($charts as $position => $chart) {
        for ($head = 0; $head < count($chart->items); $head++) {
            $item = $chart->items[$head];
            $production = $model->productions[$item->production];
            if ($item->dot === count($production->right)) {
                foreach ($charts[$item->origin]->waiting[$production->left] ?? [] as $parent) $add($position, $parent->production, $parent->dot + 1, $parent->origin);
                continue;
            }
            $symbol = $production->right[$item->dot];
            if (isNonterminal($symbol)) {
                $chart->waiting[$symbol][] = $item;
                foreach ($model->byLeft[$symbol] as $number) $add($position, $number, 0, $position);
                if ($model->nullable[$symbol]) $add($position, $item->production, $item->dot + 1, $item->origin);
            } elseif ($position < count($tokens) && $tokens[$position] === $symbol) $add($position + 1, $item->production, $item->dot + 1, $item->origin);
        }
    }
    return isset($charts[count($tokens)]->seen['0/1/0']);
}

function compactTree(object $node): object
{
    $children = [];
    foreach ($node->children as $child) {
        if ($child->symbol === '%empty') continue;
        $compacted = compactTree($child);
        if (!$compacted->mark && isNonterminal($compacted->symbol) && !$compacted->children) continue;
        if (!$compacted->mark && isNonterminal($compacted->symbol) && str_contains($compacted->symbol, "'")) {
            foreach ($compacted->children as $descendant) $children[] = $descendant;
        } else $children[] = $compacted;
    }
    if (count($children) === 1 && !$node->mark) return $children[0];
    return (object) ['symbol' => $node->symbol, 'mark' => $node->mark, 'children' => $children];
}

function drawTree(object $root): array
{
    $label = fn($node) => $node->symbol . ($node->mark ? ' (' . $node->mark . ')' : '');
    $lines = [$label($root)];
    $pending = [];
    $push = function (object $node, string $prefix) use (&$pending): void {
        for ($index = count($node->children) - 1; $index >= 0; $index--) {
            $pending[] = (object) ['node' => $node->children[$index], 'prefix' => $prefix, 'last' => $index === count($node->children) - 1];
        }
    };
    $push($root, '');
    while ($pending) {
        $entry = array_pop($pending);
        $lines[] = $entry->prefix . ($entry->last ? '`-- ' : '|-- ') . $label($entry->node);
        $push($entry->node, $entry->prefix . ($entry->last ? '    ' : '|   '));
    }
    return $lines;
}

function errorText(object $step, object $table): string
{
    $token = $step->token;
    $unexpected = $token->value === '$' ? 'end of input' : '"' . $token->value . '" at token ' . $token->position;
    $quote = fn($terminal) => $terminal === '$' ? '$' : '"' . $terminal . '"';
    if (isNonterminal($step->top)) {
        $expected = [];
        foreach ($table->columns as $terminal) if (isset($table->choices[$step->top][$terminal])) $expected[] = $quote($terminal);
        $expected = implode(' ', $expected);
    } else $expected = $quote($step->top);
    $recovery = $step->action === 'skip' ? 'skipped "' . $token->value . '"'
        : ($step->action === 'pop' ? 'popped ' . $step->top : 'inserted "' . $step->top . '"');
    return 'step ' . $step->number . ': unexpected ' . $unexpected . '; expected ' . $expected . '; ' . $recovery;
}

function actionText(object $step): string
{
    if ($step->action === 'accept') return 'accept';
    if ($step->action === 'match') return 'match ' . $step->token->value;
    if ($step->action === 'predict') return 'predict ' . $step->production->number . ': ' . productionText($step->production->left, $step->production->right);
    return 'error: ' . $step->action . ' ' . ($step->action === 'skip' ? $step->token->value : $step->top);
}

function traceTable(array $trace): array
{
    $rows = [['step', 'stack', 'input', 'action']];
    foreach ($trace as $step) $rows[] = [(string) $step->number, notation($step->stack), notation($step->input), actionText($step)];
    $widths = [0, 0, 0];
    foreach ($rows as $row) for ($index = 0; $index < 3; $index++) $widths[$index] = max($widths[$index], strlen($row[$index]));
    $lines = [];
    foreach ($rows as $row) {
        $lines[] = str_pad($row[0], $widths[0]) . '  ' . str_pad($row[1], $widths[1]) . '  ' . str_pad($row[2], $widths[2]) . '  ' . $row[3];
    }
    return $lines;
}

function derivation(object $grammar, object $table, array $leftParse): array
{
    $symbols = [$grammar->start];
    $lines = ['  ' . $grammar->start];
    foreach ($leftParse as $number) {
        $production = $table->productions[$number - 1];
        $index = 0;
        while ($index < count($symbols) && !isNonterminal($symbols[$index])) $index++;
        array_splice($symbols, $index, 1, $production->right);
        $lines[] = '  => ' . notation($symbols);
    }
    return $lines;
}

function parseReport(array $inputs, object $grammar, object $table, object $sets, object $shortest, object $membership): array
{
    $lines = [];
    $used = [];
    $recovery = ['unknown' => 0, 'skip' => 0, 'pop' => 0, 'missing' => 0];
    $mismatches = [];
    $accepted = $members = 0;
    foreach ($inputs as $index => $tokens) {
        $errors = $sequence = [];
        foreach ($tokens as $position => $value) {
            if (isset($table->known[$value])) $sequence[] = (object) ['value' => $value, 'position' => $position + 1];
            else {
                $errors[] = 'unknown "' . $value . '" at token ' . ($position + 1) . '; removed';
                $recovery['unknown']++;
            }
        }
        $sequence[] = (object) ['value' => '$', 'position' => count($tokens) + 1];
        $result = parseTokens($grammar, $table, $sets, $sequence);
        foreach ($result->trace as $step) if (in_array($step->action, ['skip', 'pop', 'missing'], true)) $errors[] = errorText($step, $table);
        foreach (['skip', 'pop', 'missing'] as $name) $recovery[$name] += $result->counts[$name];
        foreach ($result->leftParse as $number) $used[$number] = true;
        $success = !$errors;
        $member = inLanguage($tokens, $membership);
        if ($success) $accepted++;
        if ($member) $members++;
        if ($success !== $member) $mismatches[] = $index + 1;
        $lines[] = '== input ' . ($index + 1) . ' ==';
        $lines[] = listLine('tokens:', $tokens);
        foreach (traceTable($result->trace) as $line) $lines[] = $line;
        $lines[] = listLine('left parse:', $result->leftParse);
        $lines[] = 'stats: steps=' . count($result->trace) . ' predicts=' . count($result->leftParse) . ' matches=' . $result->matches . ' max_stack=' . $result->maximumStack;
        if ($errors) {
            $lines[] = 'errors:';
            foreach ($errors as $error) $lines[] = '  ' . $error;
        }
        $lines[] = $success ? 'result: accepted' : 'result: rejected (errors: ' . count($errors) . ')';
        $lines[] = 'language: ' . ($member ? 'yes' : 'no');
        if ($success) {
            $lines[] = 'derivation:';
            foreach (derivation($grammar, $table, $result->leftParse) as $line) $lines[] = $line;
        }
        $lines[] = 'tree:';
        foreach (drawTree($result->root) as $line) $lines[] = $line;
        $lines[] = 'compact tree:';
        foreach (drawTree(compactTree($result->root)) as $line) $lines[] = $line;
        $lines[] = '';
    }
    $unused = array_values(array_filter($table->productions, fn($production) => !isset($used[$production->number])));
    $lines[] = '== summary ==';
    $lines[] = 'inputs=' . count($inputs) . ' accepted=' . $accepted . ' rejected=' . (count($inputs) - $accepted) . ' in_language=' . $members;
    $lines[] = listLine('mismatches:', $mismatches);
    $lines[] = 'recovery: unknown=' . $recovery['unknown'] . ' skip=' . $recovery['skip'] . ' pop=' . $recovery['pop'] . ' missing=' . $recovery['missing'];
    $lines[] = 'coverage: ' . count($used) . ' of ' . count($table->productions) . ' productions used';
    $lines[] = listLine('unused:', array_map(fn($production) => $production->number, $unused));
    foreach ($unused as $production) {
        $tokens = ($shortest->example)($production);
        $sequence = [];
        foreach ($tokens as $position => $value) $sequence[] = (object) ['value' => $value, 'position' => $position + 1];
        $sequence[] = (object) ['value' => '$', 'position' => count($tokens) + 1];
        $result = parseTokens($grammar, $table, $sets, $sequence);
        $errors = $result->counts['skip'] + $result->counts['pop'] + $result->counts['missing'];
        $lines[] = '  ' . $production->number . ': ' . productionText($production->left, $production->right);
        $lines[] = listLine('    example:', $tokens);
        $lines[] = $errors ? '    result: rejected (errors: ' . $errors . ')' : '    result: accepted';
        $lines[] = '    used: ' . (in_array($production->number, $result->leftParse, true) ? 'yes' : 'no');
    }
    return $lines;
}

$parsed = parseGrammar(file('input/grammar.bnf', FILE_IGNORE_NEW_LINES));
$inputs = array_map(fn($line) => $line === '' ? [] : explode(' ', $line), file('input/inputs.txt', FILE_IGNORE_NEW_LINES));
$declarationDiagnostics = checkDeclarations($parsed);
$cleaned = cleanGrammar($parsed->grammar);
$recursionDiagnostics = leftRecursionReport($cleaned->grammar);
$originalSets = computeSets($cleaned->grammar);
$originalTable = buildTable($cleaned->grammar, $originalSets);
$eliminated = eliminate($cleaned->grammar);
$factored = factor($eliminated->grammar);
$final = finishGrammar($factored->grammar);
$sets = computeSets($final->grammar);
$table = buildTable($final->grammar, $sets);
$shortest = shortestSentences($final->grammar, $table->productions);
$membership = languageModel($cleaned->grammar, $originalTable, $originalSets);
$grammarLines = grammarReport($cleaned->grammar, $eliminated, $factored, $final, $table);
$setLines = setsReport($final->grammar, $sets, $shortest);
$tableLines = tableReport($final->grammar, $table, $sets, count($originalTable->conflicts));
$parseLines = parseReport($inputs, $final->grammar, $table, $sets, $shortest, $membership);
$unused = [];
if ($parsed->hasDeclarations) foreach ($parsed->declared as $name => $present) if (!isset($table->known[$name])) $unused[] = (string) $name;
$unusedDiagnostics = array_map(fn($name) => 'unused token ' . $name, terminalOrder($unused));
$diagnostics = array_merge($parsed->diagnostics, $declarationDiagnostics, $cleaned->diagnostics, $recursionDiagnostics,
    $final->diagnostics, $unusedDiagnostics, [$table->conflicts ? 'result: not LL(1) (conflicts: ' . count($table->conflicts) . ')' : 'result: LL(1)']);
if (!is_dir('output')) mkdir('output', 0777, true);
foreach (['grammar.txt' => $grammarLines, 'sets.txt' => $setLines, 'table.txt' => $tableLines, 'parses.txt' => $parseLines, 'diagnostics.txt' => $diagnostics] as $filename => $lines) {
    file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
}
