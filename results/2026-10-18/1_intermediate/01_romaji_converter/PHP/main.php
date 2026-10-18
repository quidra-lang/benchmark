<?php
const SYSTEMS = ['HEPBURN', 'TRADITIONAL', 'KUNREI', 'NIHON', 'WAPURO'];
const ROWS = ['a', 'ka', 'sa', 'ta', 'na', 'ha', 'ma', 'ya', 'ra', 'wa', 'ga', 'za', 'da', 'ba', 'pa'];
const ROW_TEXT = ['a i u e o', 'ka ki ku ke ko', 'sa si su se so', 'ta ti tu te to',
    'na ni nu ne no', 'ha hi hu he ho', 'ma mi mu me mo', 'ya yu yo', 'ra ri ru re ro',
    'wa wi we wo', 'ga gi gu ge go', 'za zi zu ze zo', 'da di du de do', 'ba bi bu be bo', 'pa pi pu pe po'];
const CONTRACT_ROWS = ['ka', 'sa', 'ta', 'na', 'ha', 'ma', 'ra', 'ga', 'za', 'da', 'ba', 'pa'];
const BASE_ROW = ['ga' => 'ka', 'za' => 'sa', 'da' => 'ta', 'ba' => 'ha', 'pa' => 'ha'];
const DEVOICE = ['g' => 'k', 'z' => 's', 'd' => 't', 'b' => 'h', 'p' => 'h'];
const GOJUON = 'a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N';
const IROHA = 'i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N';
const ARG_COUNTS = ['SET' => 2, 'TABLE' => 2, 'CONVERT' => 2, 'NORMALIZE' => 0,
    'REVERSE' => 1, 'VALID' => 1, 'DETECT' => 0, 'DIFF' => 2, 'SAME' => 2, 'MORAE' => 1,
    'SYLLABLES' => 1, 'ROW' => 1, 'STATS' => 1, 'SORT' => 1, 'INDEX' => 1, 'FIND' => 2,
    'HAIKU' => 1, 'KAIBUN' => 1, 'SHIRITORI' => 1];
const SET_VALUES = ['LONG' => ['KEEP', 'DROP', 'PASSPORT', 'HYPHEN', 'DOUBLE'],
    'CASE' => ['KEEP', 'LOWER', 'UPPER', 'TITLE'], 'ORDER' => ['GOJUON', 'IROHA']];
$identifiers = [];
$rowOf = [];
$danOf = [];
$iOf = [];
foreach (ROWS as $i => $row) {
    foreach (explode(' ', ROW_TEXT[$i]) as $id) {
        $identifiers[] = $id;
        $rowOf[$id] = $row;
        $danOf[$id] = substr($id, -1);
        if ($danOf[$id] === 'i') {
            $iOf[$row] = $id;
        }
    }
}
foreach (CONTRACT_ROWS as $row) {
    foreach (['ya', 'yu', 'yo'] as $dan) {
        $id = substr($iOf[$row], 0, -1) . $dan;
        $identifiers[] = $id;
        $rowOf[$id] = $row;
        $danOf[$id] = $dan;
    }
}

function fail(string $message): never
{
    throw new InvalidArgumentException($message);
}

function column_error(int $column, string $message): never
{
    fail("col $column: $message");
}

function is_syllabic(string $id): bool
{
    global $rowOf;
    return isset($rowOf[$id]);
}

function is_vowel(string $id): bool
{
    return in_array($id, ['a', 'i', 'u', 'e', 'o'], true);
}

function spelling(string $system, string $id): string
{
    if (in_array($system, ['HEPBURN', 'TRADITIONAL', 'WAPURO'], true)) {
        $changes = ['si' => 'shi', 'ti' => 'chi', 'tu' => 'tsu', 'hu' => 'fu', 'zi' => 'ji'];
        if ($system !== 'WAPURO') {
            $changes += ['di' => 'ji', 'du' => 'zu', 'wi' => 'i', 'we' => 'e', 'wo' => 'o'];
        }
        if (isset($changes[$id])) {
            return $changes[$id];
        }
        if (str_starts_with($id, 'sy')) {
            return 'sh' . substr($id, 2);
        }
        if (str_starts_with($id, 'ty')) {
            return 'ch' . substr($id, 2);
        }
        if (str_starts_with($id, 'zy') || ($system !== 'WAPURO' && str_starts_with($id, 'dy'))) {
            return 'j' . substr($id, 2);
        }
    } elseif ($system === 'KUNREI') {
        $changes = ['di' => 'zi', 'du' => 'zu', 'wi' => 'i', 'we' => 'e', 'wo' => 'o',
            'dya' => 'zya', 'dyu' => 'zyu', 'dyo' => 'zyo'];
        return $changes[$id] ?? $id;
    }
    return $id;
}

$readings = [];
foreach ([...SYSTEMS, 'NORMAL'] as $system) {
    $seen = [];
    $styles = $system === 'NORMAL' ? ['HEPBURN', 'KUNREI', 'NIHON', 'WAPURO'] : [$system];
    foreach ($identifiers as $id) {
        foreach ($styles as $style) {
            $text = spelling($style, $id);
            if (!isset($seen[$text])) {
                $seen[$text] = $id;
            }
        }
    }
    $entries = [];
    foreach ($seen as $text => $id) {
        $entries[] = ['text' => $text, 'id' => $id];
    }
    usort($entries, fn($a, $b) => strlen($b['text']) <=> strlen($a['text']));
    $readings[$system] = $entries;
}

function match_syllable(string $word, int $position, string $system): ?array
{
    global $readings;
    if ($position >= strlen($word)) {
        return null;
    }
    foreach ($readings[$system] as $entry) {
        if (substr_compare($word, $entry['text'], $position, strlen($entry['text'])) === 0) {
            return $entry;
        }
    }
    return null;
}

function parse_word(string $text, int $start, string $system): array
{
    $word = strtolower($text);
    $ids = [];
    $columns = [];
    $p = 0;
    while ($p < strlen($word)) {
        $c = $word[$p];
        $c2 = $word[$p + 1] ?? '';
        $c3 = $word[$p + 2] ?? '';
        $matched = match_syllable($word, $p, $system);
        $advance = 1;
        if ($c === '-') {
            if ($ids === [] || !is_syllabic($ids[count($ids) - 1])) {
                column_error($start + $p, 'misplaced long mark');
            }
            $id = '-';
        } elseif ($c === "'") {
            column_error($start + $p, 'misplaced apostrophe');
        } elseif ($matched !== null) {
            $id = $matched['id'];
            $advance = strlen($matched['text']);
        } elseif (in_array($system, ['WAPURO', 'NORMAL'], true) && substr($word, $p, 3) === 'xtu') {
            $id = 'Q';
            $advance = 3;
        } elseif ($c === 'n') {
            $id = 'N';
            if ($system === 'WAPURO') {
                $advance = $c2 === 'n' ? 2 : 1;
            } elseif ($system === 'NORMAL') {
                if ($c2 === "'" || ($c2 === 'n' && !in_array($c3, ['a', 'i', 'u', 'e', 'o', 'y', "'"], true))) {
                    $advance = 2;
                }
            } elseif ($c2 === "'") {
                $advance = 2;
            }
        } elseif (in_array($system, ['TRADITIONAL', 'NORMAL'], true) && $c === 'm' && in_array($c2, ['b', 'm', 'p'], true)) {
            $id = 'N';
        } elseif ($c >= 'a' && $c <= 'z' && !in_array($c, ['a', 'i', 'u', 'e', 'o', 'n'], true) && $c === $c2 && match_syllable($word, $p + 1, $system) !== null) {
            $id = 'Q';
        } elseif (in_array($system, ['HEPBURN', 'TRADITIONAL', 'NORMAL'], true) && $c === 't' && $c2 === 'c' && $c3 === 'h' && match_syllable($word, $p + 1, $system) !== null) {
            $id = 'Q';
        } else {
            column_error($start + $p, 'unknown syllable');
        }
        $ids[] = $id;
        $columns[] = $start + $p;
        $p += $advance;
    }
    return [$ids, $columns];
}

function long_flags(array $ids): array
{
    $paired = array_fill(0, count($ids), false);
    $long = array_map(fn($id) => $id === '-', $ids);
    $i = 0;
    while ($i + 1 < count($ids)) {
        $first = $ids[$i];
        $second = $ids[$i + 1];
        if (is_syllabic($first) && is_vowel($second)) {
            $vowel = substr($first, -1);
            if ($vowel === $second || ($vowel === 'o' && $second === 'u') || ($vowel === 'e' && $second === 'i')) {
                $paired[$i + 1] = true;
                $long[$i + 1] = ($vowel === 'o' && in_array($second, ['o', 'u'], true)) || ($vowel === 'u' && $second === 'u');
                $i += 2;
                continue;
            }
        }
        ++$i;
    }
    return [$paired, $long];
}

function write_parts(array $ids, array $columns, string $system, string $longSetting): array
{
    [, $long] = long_flags($ids);
    $parts = [];
    foreach ($ids as $i => $id) {
        $nextId = $ids[$i + 1] ?? '';
        $nextText = is_syllabic($nextId) ? spelling($system, $nextId) : '';
        $first = $nextText[0] ?? '';
        if ($long[$i]) {
            $vowel = substr($ids[$i - 1], -1);
            if ($longSetting === 'KEEP') {
                $part = $id === '-' ? '-' : spelling($system, $id);
            } elseif ($longSetting === 'DROP') {
                $part = '';
            } elseif ($longSetting === 'PASSPORT') {
                $part = $vowel === 'o' && !is_vowel($first) ? 'h' : '';
            } elseif ($longSetting === 'HYPHEN') {
                $part = '-';
            } else {
                $part = $vowel;
            }
        } elseif (is_syllabic($id)) {
            $part = spelling($system, $id);
        } elseif ($id === 'N') {
            if ($system === 'WAPURO') {
                $part = $nextId === 'N' || in_array($first, ['a', 'i', 'u', 'e', 'o', 'y', 'n'], true) ? 'nn' : 'n';
            } elseif ($system === 'TRADITIONAL' && in_array($first, ['b', 'm', 'p'], true)) {
                $part = 'm';
            } else {
                $part = in_array($first, ['a', 'i', 'u', 'e', 'o', 'y'], true) ? "n'" : 'n';
            }
        } else {
            if ($nextText !== '' && !in_array($first, ['a', 'i', 'u', 'e', 'o', 'n'], true)) {
                $part = in_array($system, ['HEPBURN', 'TRADITIONAL'], true) && str_starts_with($nextText, 'ch') ? 't' : $first;
            } elseif ($system === 'WAPURO') {
                $part = 'xtu';
            } else {
                column_error($columns[$i], 'small tsu cannot be written');
            }
        }
        $parts[] = $part;
    }
    return $parts;
}

function word_pattern(string $text): string
{
    if ($text === strtolower($text)) {
        return 'LOWER';
    }
    if ($text[0] >= 'A' && $text[0] <= 'Z' && substr($text, 1) === strtolower(substr($text, 1))) {
        return 'TITLE';
    }
    if (preg_match_all('/[A-Z]/', $text) >= 2 && $text === strtoupper($text)) {
        return 'UPPER';
    }
    return '';
}

function written(array $word, string $system, array $settings, bool $canonical = false, ?array $ids = null, ?array $columns = null): string
{
    $mode = $canonical ? 'KEEP' : $settings['LONG'];
    $text = implode('', write_parts($ids ?? $word['ids'], $columns ?? $word['columns'], $system, $mode));
    $pattern = $canonical || $settings['CASE'] === 'KEEP' ? $word['pattern'] : $settings['CASE'];
    if ($pattern === 'UPPER') {
        return strtoupper($text);
    }
    return $pattern === 'TITLE' ? ucfirst($text) : $text;
}

function words_in(string $text): array
{
    preg_match_all("/[A-Za-z'-]+/", $text, $matches, PREG_OFFSET_CAPTURE);
    $words = [];
    foreach ($matches[0] as [$word, $offset]) {
        $words[] = ['text' => $word, 'start' => $offset + 1, 'pattern' => '', 'ids' => [], 'columns' => [],
            'part' => substr_count(substr($text, 0, $offset), '/') + 1, 'index' => count($words)];
    }
    return $words;
}

function replace_words(string $text, array $words, array $replacements): string
{
    $output = '';
    $position = 0;
    foreach ($words as $i => $word) {
        $offset = $word['start'] - 1;
        $output .= substr($text, $position, $offset - $position) . $replacements[$i];
        $position = $offset + strlen($word['text']);
    }
    return $output . substr($text, $position);
}

function devoice(string $id): string
{
    return (DEVOICE[$id[0]] ?? $id[0]) . substr($id, 1);
}

function elements(array $ids): array
{
    global $rowOf, $danOf, $iOf;
    $items = [];
    foreach ($ids as $id) {
        if ($id === '-') {
            continue;
        }
        if ($id === 'N') {
            $items[] = ['N', 0, 0];
        } elseif ($id === 'Q') {
            $items[] = ['tu', 0, 1];
        } else {
            $row = $rowOf[$id];
            $voice = 0;
            if (in_array($row, ['ga', 'za', 'da', 'ba'], true)) {
                $voice = 1;
            } elseif ($row === 'pa') {
                $voice = 2;
            }
            if (strlen($danOf[$id]) === 2) {
                $items[] = [devoice($iOf[$row]), $voice, 0];
                $items[] = [$danOf[$id], 0, 1];
            } else {
                $items[] = [devoice($id), $voice, 0];
            }
        }
    }
    return $items;
}

function collation(array $word, string $order): array
{
    $ranks = array_flip(explode(' ', $order === 'GOJUON' ? GOJUON : IROHA));
    $items = elements($word['ids']);
    return [array_map(fn($item) => $ranks[$item[0]], $items), array_column($items, 1), array_column($items, 2),
        array_map(fn($id) => $id === '-' ? 1 : 0, $word['ids'])];
}

function vector_compare(array $a, array $b): int
{
    for ($i = 0; $i < min(count($a), count($b)); ++$i) {
        if ($a[$i] !== $b[$i]) {
            return $a[$i] <=> $b[$i];
        }
    }
    return count($a) <=> count($b);
}

function pattern_tokens(string $pattern, string $system): array
{
    if (preg_match("/^[a-z'\\-?*]+$/D", $pattern) !== 1) {
        fail('invalid pattern');
    }
    $tokens = [];
    $chunk = '';
    try {
        foreach (str_split($pattern) as $c) {
            if ($c === '?' || $c === '*') {
                $tokens = [...$tokens, ...parse_word($chunk, 1, $system)[0], $c];
                $chunk = '';
            } else {
                $chunk .= $c;
            }
        }
        return [...$tokens, ...parse_word($chunk, 1, $system)[0]];
    } catch (InvalidArgumentException $exception) {
        fail('invalid pattern');
    }
}

function wildcard_matches(array $tokens, array $ids): bool
{
    $previous = array_fill(0, count($ids) + 1, false);
    $previous[0] = true;
    foreach ($tokens as $token) {
        $current = array_fill(0, count($ids) + 1, false);
        if ($token === '*') {
            $current[0] = $previous[0];
        }
        foreach ($ids as $j => $id) {
            if ($token === '*') {
                $current[$j + 1] = $previous[$j + 1] || $current[$j];
            } else {
                $current[$j + 1] = $previous[$j] && ($token === '?' || $token === $id);
            }
        }
        $previous = $current;
    }
    return $previous[count($ids)];
}

function execute(string $line, array &$settings): string
{
    global $identifiers, $rowOf, $danOf;
    $command = explode(' ', $line, 2)[0];
    if (!array_key_exists($command, ARG_COUNTS)) {
        fail("unknown command $command");
    }
    $k = ARG_COUNTS[$command];
    if ($command === 'SET' || $command === 'TABLE') {
        $parts = explode(' ', $line);
        if (count($parts) < 3) {
            fail('missing argument');
        }
        if (count($parts) > 3) {
            fail('too many arguments');
        }
        $args = array_slice($parts, 1);
        $text = '';
    } else {
        if (substr_count($line, ' ') < $k + 1) {
            fail('missing argument');
        }
        $parts = explode(' ', $line, $k + 2);
        $args = array_slice($parts, 1, $k);
        $text = $parts[$k + 1];
    }
    $systemCount = 1;
    if (in_array($command, ['SET', 'NORMALIZE', 'DETECT'], true)) {
        $systemCount = 0;
    } elseif (in_array($command, ['CONVERT', 'DIFF', 'SAME'], true)) {
        $systemCount = 2;
    }
    foreach (array_slice($args, 0, $systemCount) as $system) {
        if (!in_array($system, SYSTEMS, true)) {
            fail("unknown system $system");
        }
    }
    if ($command === 'SET') {
        [$option, $value] = $args;
        if (!isset(SET_VALUES[$option])) {
            fail("unknown option $option");
        }
        if (!in_array($value, SET_VALUES[$option], true)) {
            fail("unknown value $value");
        }
        $settings[$option] = $value;
        return "$option=$value";
    }
    if ($command === 'TABLE') {
        [$system, $row] = $args;
        if (!in_array($row, ROWS, true)) {
            fail("unknown row $row");
        }
        $ids = array_filter($identifiers, fn($id) => $rowOf[$id] === $row);
        return implode(' ', array_map(fn($id) => spelling($system, $id), $ids));
    }
    $tokens = $command === 'FIND' ? pattern_tokens($args[1], $args[0]) : [];
    $slashAllowed = $command === 'HAIKU' || $command === 'SAME';
    foreach (str_split($text) as $i => $c) {
        $allowed = ctype_alpha($c) || ctype_digit($c) || str_contains("'- .,!?;:()\"", $c) || ($slashAllowed && $c === '/');
        if (!$allowed) {
            column_error($i + 1, 'invalid character');
        }
    }
    $words = words_in($text);
    if ($command === 'SAME') {
        $left = array_filter($words, fn($w) => $w['part'] === 1);
        $right = array_filter($words, fn($w) => $w['part'] === 2);
        if (substr_count($text, '/') !== 1 || $left === [] || $right === []) {
            fail('expected two texts');
        }
    } elseif ($command === 'HAIKU') {
        $lines = substr_count($text, '/') + 1;
        if (!in_array($lines, [3, 5], true)) {
            fail('expected 3 or 5 lines');
        }
        for ($i = 1; $i <= $lines; ++$i) {
            if (array_filter($words, fn($w) => $w['part'] === $i) === []) {
                fail('expected 3 or 5 lines');
            }
        }
    }
    if ($words === []) {
        fail('no words');
    }
    foreach ($words as &$word) {
        $word['pattern'] = word_pattern($word['text']);
        if ($word['pattern'] === '') {
            column_error($word['start'], 'mixed case');
        }
    }
    unset($word);
    if ($command === 'DETECT') {
        $output = [];
        foreach (SYSTEMS as $system) {
            $verdict = 'canonical';
            try {
                $parsedWords = $words;
                foreach ($parsedWords as &$word) {
                    [$word['ids'], $word['columns']] = parse_word($word['text'], $word['start'], $system);
                }
                unset($word);
                foreach ($parsedWords as $word) {
                    if (written($word, $system, $settings, true) !== $word['text']) {
                        $verdict = 'readable';
                    }
                }
            } catch (InvalidArgumentException $exception) {
                unset($word);
                $verdict = 'error';
            }
            $output[] = "$system=$verdict";
        }
        return implode(' ', $output);
    }
    foreach ($words as &$word) {
        if ($command === 'NORMALIZE') {
            $system = 'NORMAL';
        } elseif ($command === 'SAME') {
            $system = $args[$word['part'] - 1];
        } else {
            $system = $args[0];
        }
        [$word['ids'], $word['columns']] = parse_word($word['text'], $word['start'], $system);
    }
    unset($word);
    $system = $command === 'NORMALIZE' ? 'HEPBURN' : $args[0];
    if (in_array($command, ['CONVERT', 'NORMALIZE', 'REVERSE'], true)) {
        $target = $command === 'CONVERT' ? $args[1] : $system;
        $output = [];
        foreach ($words as $word) {
            $ids = $word['ids'];
            $columns = $word['columns'];
            if ($command === 'REVERSE') {
                foreach ($ids as $i => $id) {
                    if ($id === '-') {
                        $ids[$i] = substr($word['ids'][$i - 1], -1);
                    }
                }
                $ids = array_reverse($ids);
                $columns = array_reverse($columns);
            }
            $output[] = written($word, $target, $settings, false, $ids, $columns);
        }
        return replace_words($text, $words, $output);
    }
    if ($command === 'VALID') {
        foreach ($words as $word) {
            $expected = written($word, $system, $settings, true);
            if ($expected !== $word['text']) {
                $i = 0;
                while ($i < min(strlen($expected), strlen($word['text'])) && $expected[$i] === $word['text'][$i]) {
                    ++$i;
                }
                return 'INVALID col ' . ($word['start'] + $i) . ': expected ' . $expected;
            }
        }
        return 'VALID';
    }
    if ($command === 'DIFF') {
        $output = [];
        foreach ($words as $word) {
            $a = written($word, $args[0], $settings);
            $b = written($word, $args[1], $settings);
            if ($a !== $b) {
                $output[] = "$a>$b";
            }
        }
        $prefix = count($output) . ' of ' . count($words);
        return $output === [] ? $prefix : $prefix . ': ' . implode(' ', $output);
    }
    if ($command === 'SAME') {
        $left = array_values(array_filter($words, fn($w) => $w['part'] === 1));
        $right = array_values(array_filter($words, fn($w) => $w['part'] === 2));
        $exact = true;
        for ($i = 0; $i < min(count($left), count($right)); ++$i) {
            $a = $left[$i]['ids'];
            $b = $right[$i]['ids'];
            $aLong = long_flags($a)[1];
            $bLong = long_flags($b)[1];
            $aLoose = array_values(array_filter($a, fn($id, $j) => !$aLong[$j], ARRAY_FILTER_USE_BOTH));
            $bLoose = array_values(array_filter($b, fn($id, $j) => !$bLong[$j], ARRAY_FILTER_USE_BOTH));
            if ($aLoose !== $bLoose) {
                return 'DIFFERENT at word ' . ($i + 1);
            }
            $exact = $exact && $a === $b;
        }
        if (count($left) !== count($right)) {
            return 'DIFFERENT at word ' . (min(count($left), count($right)) + 1);
        }
        return $exact ? 'EXACT' : 'LOOSE';
    }
    if ($command === 'MORAE') {
        $total = 0;
        $output = [];
        foreach ($words as $word) {
            $total += count($word['ids']);
            $output[] = implode('.', array_map(fn($id) => spelling($system, $id), $word['ids']));
        }
        return "$total: " . implode(' ', $output);
    }
    if ($command === 'SYLLABLES') {
        $total = 0;
        $output = [];
        foreach ($words as $word) {
            [$paired] = long_flags($word['ids']);
            $parts = write_parts($word['ids'], $word['columns'], $system, 'KEEP');
            $syllables = [];
            foreach ($word['ids'] as $i => $id) {
                if ($i > 0 && (!is_syllabic($id) || $paired[$i])) {
                    $syllables[count($syllables) - 1] .= $parts[$i];
                } else {
                    $syllables[] = $parts[$i];
                }
            }
            $total += count($syllables);
            $output[] = implode('.', $syllables);
        }
        return "$total: " . implode(' ', $output);
    }
    if ($command === 'ROW') {
        $output = [];
        foreach ($words as $word) {
            foreach ($word['ids'] as $id) {
                $output[] = is_syllabic($id) ? spelling($system, $id) . ": $rowOf[$id] $danOf[$id]" : "$id: special";
            }
        }
        return implode(', ', $output);
    }
    if ($command === 'STATS') {
        $names = [...array_slice(ROWS, 0, 10), 'voiced', 'semivoiced', 'contracted', 'N', 'Q', 'L'];
        $counts = array_fill_keys($names, 0);
        $total = 0;
        foreach ($words as $word) {
            foreach ($word['ids'] as $id) {
                ++$total;
                if (is_syllabic($id)) {
                    $row = $rowOf[$id];
                    ++$counts[BASE_ROW[$row] ?? $row];
                    if (in_array($row, ['ga', 'za', 'da', 'ba'], true)) {
                        ++$counts['voiced'];
                    }
                    if ($row === 'pa') {
                        ++$counts['semivoiced'];
                    }
                    if (strlen($danOf[$id]) === 2) {
                        ++$counts['contracted'];
                    }
                } else {
                    ++$counts[$id === '-' ? 'L' : $id];
                }
            }
        }
        $output = ["morae=$total"];
        foreach (array_slice(ROWS, 0, 10) as $row) {
            if ($counts[$row] > 0) {
                $output[] = "$row=$counts[$row]";
            }
        }
        foreach (['voiced', 'semivoiced', 'contracted', 'N', 'Q', 'L'] as $name) {
            $output[] = "$name=$counts[$name]";
        }
        return implode(' ', $output);
    }
    if ($command === 'SORT' || $command === 'INDEX') {
        foreach ($words as &$word) {
            $word['key'] = collation($word, $settings['ORDER']);
        }
        unset($word);
        usort($words, function($a, $b) {
            for ($j = 0; $j < 4; ++$j) {
                $comparison = vector_compare($a['key'][$j], $b['key'][$j]);
                if ($comparison !== 0) {
                    return $comparison;
                }
            }
            return $a['index'] <=> $b['index'];
        });
        if ($command === 'SORT') {
            return implode(' ', array_column($words, 'text'));
        }
        $groups = [];
        $previous = '';
        foreach ($words as $word) {
            $base = elements($word['ids'])[0][0];
            $heading = $settings['ORDER'] === 'IROHA' || $base === 'N' ? $base : $rowOf[$base];
            if ($heading === $previous) {
                $groups[count($groups) - 1] .= ' ' . $word['text'];
            } else {
                $groups[] = "$heading: $word[text]";
                $previous = $heading;
            }
        }
        return implode('; ', $groups);
    }
    if ($command === 'FIND') {
        $matches = array_filter($words, fn($w) => wildcard_matches($tokens, $w['ids']));
        $prefix = count($matches) . ' of ' . count($words);
        return $matches === [] ? $prefix : $prefix . ': ' . implode(' ', array_column($matches, 'text'));
    }
    if ($command === 'HAIKU') {
        $counts = array_fill(0, substr_count($text, '/') + 1, 0);
        foreach ($words as $word) {
            $counts[$word['part'] - 1] += count($word['ids']);
        }
        $expected = count($counts) === 3 ? [5, 7, 5] : [5, 7, 5, 7, 7];
        $verdict = $counts === $expected ? 'OK' : 'NG';
        $form = count($counts) === 3 ? 'haiku' : 'tanka';
        return "$verdict $form " . implode('-', $counts);
    }
    if ($command === 'KAIBUN') {
        $bases = [];
        foreach ($words as $word) {
            $bases = [...$bases, ...array_column(elements($word['ids']), 0)];
        }
        return ($bases === array_reverse($bases) ? 'YES ' : 'NO ') . implode('.', $bases);
    }
    $seen = [];
    $previous = '';
    foreach ($words as $i => $word) {
        $items = elements($word['ids']);
        $head = $items[0][0];
        $tail = $items[count($items) - 1][0];
        $prefix = 'NG ' . ($i + 1) . ': ' . $word['text'];
        if ($i > 0 && $head !== $previous) {
            return $prefix . ' must start with ' . spelling($system, $previous);
        }
        if (in_array($word['ids'], $seen, true)) {
            return $prefix . ' is repeated';
        }
        if ($tail === 'N') {
            return $prefix . ' ends with N';
        }
        $seen[] = $word['ids'];
        $previous = $tail;
    }
    return 'OK ' . count($words);
}

$count = (int) fgets(STDIN);
$settings = ['LONG' => 'KEEP', 'CASE' => 'KEEP', 'ORDER' => 'GOJUON'];
for ($i = 0; $i < $count; ++$i) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        echo execute($line, $settings), "\n";
    } catch (InvalidArgumentException $exception) {
        echo 'ERROR ', $exception->getMessage(), "\n";
    }
}
