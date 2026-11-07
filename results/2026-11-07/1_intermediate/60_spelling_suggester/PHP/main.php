<?php

declare(strict_types=1);

const ADJACENT_KEYS = [
    'a' => 'qswz', 'b' => 'ghnv', 'c' => 'dfvx', 'd' => 'cefrsx', 'e' => 'drsw',
    'f' => 'cdgrtv', 'g' => 'bfhtvy', 'h' => 'bgjnuy', 'i' => 'jkou', 'j' => 'hikmnu',
    'k' => 'ijlmo', 'l' => 'kop', 'm' => 'jkn', 'n' => 'bhjm', 'o' => 'iklp',
    'p' => 'lo', 'q' => 'aw', 'r' => 'deft', 's' => 'adewxz', 't' => 'fgry',
    'u' => 'hijy', 'v' => 'bcfg', 'w' => 'aeqs', 'x' => 'cdsz', 'y' => 'ghtu',
    'z' => 'asx',
];
const SOUNDEX_GROUPS = [
    ['bfpv', '1'], ['cgjkqsxz', '2'], ['dt', '3'], ['l', '4'],
    ['mn', '5'], ['r', '6'], ['aeiouy', '0'],
];
const COUNTERS = ['checked', 'unknown', 'case', 'capital', 'repeats', 'corrected'];
const FINDINGS = ['unknown', 'case', 'capital', 'repeats'];
const TEXT_COMMANDS = ['CHECK', 'CORRECT', 'FIX', 'PROFILE', 'LEARN'];
const ARITIES = [
    'SUGGEST' => 1, 'DIST' => 2, 'SOUNDEX' => 1, 'SOUNDS' => 1, 'SPLIT' => 1,
    'PREFIX' => 2, 'COMPLETE' => 2, 'LIST' => 2, 'WORD' => 1, 'ADD' => 2,
    'REMOVE' => 1, 'IGNORE' => 1, 'UNIGNORE' => 1, 'RULE' => 2, 'UNRULE' => 1,
    'RULES' => 0, 'KEYBOARD' => 1, 'SET' => 2, 'UNDO' => 0, 'REPORT' => 0,
    'HISTORY' => 0, 'STATS' => 0,
];

final class CommandError extends RuntimeException {}

function wordArgument(string $text): string
{
    if (!preg_match('/^[A-Za-z]{1,30}$/D', $text)) throw new CommandError("BAD WORD $text");
    return strtolower($text);
}

function numberArgument(string $text, int $minimum, int $maximum): int
{
    if (!preg_match('/^[0-9]{1,7}$/D', $text)) throw new CommandError("BAD NUMBER $text");
    $value = (int) $text;
    if ($value < $minimum || $value > $maximum) throw new CommandError("BAD NUMBER $text");
    return $value;
}

function decimalText(int $numerator, int $denominator, int $digits): string
{
    $scale = 10 ** $digits;
    $value = intdiv(2 * $numerator * $scale + $denominator, 2 * $denominator);
    return intdiv($value, $scale) . '.' . str_pad((string) ($value % $scale), $digits, '0', STR_PAD_LEFT);
}

function applyCase(string $original, string $word): string
{
    if (strlen($original) >= 2 && strtoupper($original) === $original) return strtoupper($word);
    if ($original[0] >= 'A' && $original[0] <= 'Z') return ucfirst($word);
    return $word;
}

final class Token
{
    public string $word;
    public bool $sentenceStart;
    public bool $repeat;

    public function __construct(
        public int $number,
        public string $text,
        public int $start,
        public int $end,
        public string $gap,
        ?self $previous
    ) {
        $this->word = strtolower($text);
        $this->sentenceStart = $previous === null || strpbrk($gap, '.!?') !== false;
        $this->repeat = $previous !== null && $this->word === $previous->word &&
            strspn($gap, ' ') === strlen($gap);
    }

    public function mixedCase(): bool
    {
        return preg_match('/[A-Z]/', substr($this->text, 1)) === 1 &&
            strtoupper($this->text) !== $this->text;
    }
}

function textTokens(string $text): array
{
    preg_match_all('/[A-Za-z]+/', $text, $matches, PREG_OFFSET_CAPTURE);
    $tokens = [];
    $previous = null;
    $position = 0;
    foreach ($matches[0] as [$spelling, $start]) {
        $end = $start + strlen($spelling);
        $token = new Token(count($tokens) + 1, $spelling, $start, $end,
            substr($text, $position, $start - $position), $previous);
        $tokens[] = $token;
        $previous = $token;
        $position = $end;
    }
    return $tokens;
}

function substitutionCost(string $first, string $second, bool $keyboard): int
{
    if ($first === $second) return 0;
    if (!$keyboard) return 1;
    return str_contains(ADJACENT_KEYS[$first], $second) ? 1 : 2;
}

function isSwap(string $first, string $second, int $i, int $j): bool
{
    return $i >= 2 && $j >= 2 &&
        $first[$i - 1] === $second[$j - 2] && $first[$i - 2] === $second[$j - 1];
}

function distanceTable(string $first, string $second, bool $keyboard): array
{
    $gap = $keyboard ? 2 : 1;
    $rows = strlen($first);
    $columns = strlen($second);
    $table = array_fill(0, $rows + 1, array_fill(0, $columns + 1, 0));
    for ($i = 0; $i <= $rows; ++$i) $table[$i][0] = $i * $gap;
    for ($j = 0; $j <= $columns; ++$j) $table[0][$j] = $j * $gap;
    for ($i = 1; $i <= $rows; ++$i) {
        for ($j = 1; $j <= $columns; ++$j) {
            $best = min(
                $table[$i - 1][$j] + $gap,
                $table[$i][$j - 1] + $gap,
                $table[$i - 1][$j - 1] + substitutionCost($first[$i - 1], $second[$j - 1], $keyboard)
            );
            if (isSwap($first, $second, $i, $j)) {
                $best = min($best, $table[$i - 2][$j - 2] + 1);
            }
            $table[$i][$j] = $best;
        }
    }
    return $table;
}

function editDistance(string $first, string $second, bool $keyboard): int
{
    return distanceTable($first, $second, $keyboard)[strlen($first)][strlen($second)];
}

function prefixDistance(string $word, string $other, bool $keyboard): int
{
    return min(distanceTable($word, $other, $keyboard)[strlen($word)]);
}

function editOperations(string $first, string $second, bool $keyboard): array
{
    $table = distanceTable($first, $second, $keyboard);
    $gap = $keyboard ? 2 : 1;
    $operations = [];
    $i = strlen($first);
    $j = strlen($second);
    while ($i > 0 || $j > 0) {
        if ($i >= 1 && $j >= 1 &&
            $table[$i][$j] === $table[$i - 1][$j - 1] +
                substitutionCost($first[$i - 1], $second[$j - 1], $keyboard)) {
            if ($first[$i - 1] !== $second[$j - 1]) {
                $operations[] = 'sub:' . $first[$i - 1] . '>' . $second[$j - 1];
            }
            --$i;
            --$j;
        } elseif (isSwap($first, $second, $i, $j) &&
                  $table[$i][$j] === $table[$i - 2][$j - 2] + 1) {
            $operations[] = 'swap:' . $first[$i - 2] . $first[$i - 1];
            $i -= 2;
            $j -= 2;
        } elseif ($i >= 1 && $table[$i][$j] === $table[$i - 1][$j] + $gap) {
            $operations[] = 'del:' . $first[$i - 1];
            --$i;
        } else {
            $operations[] = 'ins:' . $second[$j - 1];
            --$j;
        }
    }
    return [$table[strlen($first)][strlen($second)], array_reverse($operations)];
}

function spellSoundex(string $word): string
{
    static $digits = null;
    if ($digits === null) {
        $digits = [];
        foreach (SOUNDEX_GROUPS as [$letters, $digit]) {
            foreach (str_split($letters) as $letter) $digits[$letter] = $digit;
        }
    }
    $code = strtoupper($word[0]);
    $previous = str_contains('hw', $word[0]) ? '0' : $digits[$word[0]];
    for ($i = 1; $i < strlen($word); ++$i) {
        $letter = $word[$i];
        if (str_contains('hw', $letter)) continue;
        $digit = $digits[$letter];
        if ($digit !== '0' && $digit !== $previous) $code .= $digit;
        $previous = $digit;
    }
    return substr($code . '000', 0, 4);
}

function compareWordLists(array $first, array $second): int
{
    $length = min(count($first), count($second));
    for ($i = 0; $i < $length; ++$i) {
        $order = strcmp($first[$i], $second[$i]);
        if ($order !== 0) return $order;
    }
    return count($first) <=> count($second);
}

function segment(string $word, array $dictionary): array
{
    $length = strlen($word);
    $ways = array_fill(0, $length + 1, 0);
    $best = array_fill(0, $length + 1, null);
    $ways[$length] = 1;
    $best[$length] = [];
    for ($start = $length - 1; $start >= 0; --$start) {
        for ($end = $start + 1; $end <= $length; ++$end) {
            $piece = substr($word, $start, $end - $start);
            if (!isset($dictionary[$piece]) || $ways[$end] === 0) continue;
            $ways[$start] += $ways[$end];
            $candidate = array_merge([$piece], $best[$end]);
            $current = $best[$start];
            if ($current === null || count($candidate) < count($current) ||
                (count($candidate) === count($current) && compareWordLists($candidate, $current) < 0)) {
                $best[$start] = $candidate;
            }
        }
    }
    return [$ways[0], $best[0]];
}

final class SpellChecker
{
    public array $output = [];
    private array $dictionary;
    private array $ignored = [];
    private array $rules = [];
    private bool $keyboard = false;
    private int $baseLimit = 2;
    private int $suggestionCount = 5;
    private array $undoHistory = [];
    private array $unknownLog = [];
    private array $correctionLog = [];
    private array $counters;

    public function __construct(array $dictionary)
    {
        $this->dictionary = $dictionary;
        $this->counters = array_fill_keys(COUNTERS, 0);
    }

    private function emit(string ...$parts): void
    {
        $this->output[] = implode(' ', $parts);
    }

    private function limit(): int
    {
        return $this->keyboard ? 2 * $this->baseLimit : $this->baseLimit;
    }

    private function isKnown(string $word): bool
    {
        return isset($this->dictionary[$word]) || isset($this->ignored[$word]);
    }

    private function frequencyOrder(): array
    {
        $words = array_keys($this->dictionary);
        usort($words, function (string $a, string $b): int {
            return ($this->dictionary[$b] <=> $this->dictionary[$a]) ?: strcmp($a, $b);
        });
        return $words;
    }

    private function requireEntry(string $word): int
    {
        if (!isset($this->dictionary[$word])) throw new CommandError("NOT FOUND $word");
        return $this->dictionary[$word];
    }

    private function candidates(string $word): array
    {
        $limit = $this->limit();
        $gap = $this->keyboard ? 2 : 1;
        $found = [];
        foreach ($this->dictionary as $other => $frequency) {
            if ($other === $word || abs(strlen($other) - strlen($word)) * $gap > $limit) continue;
            $distance = editDistance($word, $other, $this->keyboard);
            if ($distance <= $limit) $found[] = [$other, $distance, $frequency];
        }
        usort($found, static function (array $a, array $b): int {
            return ($a[1] <=> $b[1]) ?: (($b[2] <=> $a[2]) ?: strcmp($a[0], $b[0]));
        });
        return $found;
    }

    private function correction(string $word): ?string
    {
        if ($this->isKnown($word)) return null;
        if (isset($this->rules[$word])) return $this->rules[$word];
        $candidates = $this->candidates($word);
        return $candidates ? $candidates[0][0] : null;
    }

    private function recordUndo(string $name): void
    {
        $this->undoHistory[] = [$name, $this->dictionary, $this->ignored, $this->rules];
    }

    private function logCorrection(string $word, string $replacement): void
    {
        $key = $word . '>' . $replacement;
        $this->correctionLog[$key] = ($this->correctionLog[$key] ?? 0) + 1;
        ++$this->counters['corrected'];
    }

    private function unknownFinding(Token $token): string
    {
        $prefix = 'UNKNOWN ' . $token->number . ' ' . $token->text;
        if (isset($this->rules[$token->word])) {
            return $prefix . ' RULE ' . $this->rules[$token->word];
        }
        $found = $this->candidates($token->word);
        if (!$found) return $prefix . ' NONE';
        $words = array_column(array_slice($found, 0, $this->suggestionCount), 0);
        return $prefix . ' SUGGEST ' . implode(' ', $words);
    }

    private function cmdCheck(string $text): void
    {
        $tokens = textTokens($text);
        $findings = [];
        foreach ($tokens as $token) {
            if (!$this->isKnown($token->word)) {
                $findings[] = ['unknown', $this->unknownFinding($token)];
                $this->unknownLog[$token->word] = ($this->unknownLog[$token->word] ?? 0) + 1;
            }
            if ($token->mixedCase()) {
                $findings[] = ['case', 'CASE ' . $token->number . ' ' . $token->text];
            }
            if ($token->sentenceStart && ctype_lower($token->text[0])) {
                $findings[] = ['capital', 'CAPITAL ' . $token->number . ' ' . $token->text];
            }
            if ($token->repeat) {
                $findings[] = ['repeats', 'REPEAT ' . $token->number . ' ' . $token->text];
            }
        }
        $counts = array_fill_keys(FINDINGS, 0);
        foreach ($findings as [$kind, $_]) ++$counts[$kind];
        $this->counters['checked'] += count($tokens);
        foreach (FINDINGS as $kind) $this->counters[$kind] += $counts[$kind];
        $items = ['CHECK', 'words=' . count($tokens)];
        foreach (FINDINGS as $kind) $items[] = $kind . '=' . $counts[$kind];
        $this->emit(...$items);
        foreach ($findings as [$_, $line]) $this->emit($line);
    }

    private function cmdCorrect(string $text): void
    {
        $pieces = [];
        $position = 0;
        $changed = 0;
        foreach (textTokens($text) as $token) {
            $replacement = $this->correction($token->word);
            if ($replacement === null) {
                $pieces[] = $token->gap . $token->text;
            } else {
                $pieces[] = $token->gap . applyCase($token->text, $replacement);
                $this->logCorrection($token->word, $replacement);
                ++$changed;
            }
            $position = $token->end;
        }
        $pieces[] = substr($text, $position);
        $this->emit('CORRECT', 'changed=' . $changed . ':', implode('', $pieces));
    }

    private function cmdFix(string $text): void
    {
        $pieces = [];
        $position = 0;
        $removed = 0;
        $replaced = 0;
        $recased = 0;
        foreach (textTokens($text) as $token) {
            $position = $token->end;
            if ($token->repeat) { ++$removed; continue; }
            $replacement = $this->correction($token->word);
            $target = $replacement ?? $token->word;
            $result = applyCase($token->text, $target);
            if ($token->sentenceStart && ctype_lower($result[0])) $result = ucfirst($result);
            if ($replacement !== null) {
                $this->logCorrection($token->word, $replacement);
                ++$replaced;
            } elseif ($result !== $token->text) {
                ++$recased;
            }
            $pieces[] = $token->gap . $result;
        }
        $pieces[] = substr($text, $position);
        $this->emit('FIX', 'removed=' . $removed, 'replaced=' . $replaced,
            'recased=' . $recased . ':', implode('', $pieces));
    }

    private function cmdProfile(string $text): void
    {
        $tokens = textTokens($text);
        $seen = [];
        $unknown = 0;
        $sentences = 0;
        $characters = 0;
        $longest = '-';
        $maxLength = 0;
        foreach ($tokens as $token) {
            $seen[$token->word] = true;
            if (!$this->isKnown($token->word)) ++$unknown;
            if ($token->sentenceStart) ++$sentences;
            $characters += strlen($token->text);
            if (strlen($token->text) > $maxLength) {
                $maxLength = strlen($token->text);
                $longest = $token->word;
            }
        }
        $count = count($tokens);
        $rate = $count ? decimalText(100 * $unknown, $count, 1) : '0.0';
        $average = $count ? decimalText($characters, $count, 2) : '0.00';
        $this->emit('PROFILE', 'words=' . $count, 'distinct=' . count($seen),
            'unknown=' . $unknown, 'rate=' . $rate, 'avglen=' . $average,
            'longest=' . $longest, 'sentences=' . $sentences);
    }

    private function cmdLearn(string $text): void
    {
        $this->recordUndo('LEARN');
        $updated = 0; $added = 0; $skipped = 0;
        foreach (textTokens($text) as $token) {
            if (strlen($token->word) > 30) {
                ++$skipped;
            } elseif (isset($this->dictionary[$token->word])) {
                ++$this->dictionary[$token->word];
                ++$updated;
            } else {
                $this->dictionary[$token->word] = 1;
                unset($this->ignored[$token->word]);
                ++$added;
            }
        }
        $this->emit('LEARN', 'updated=' . $updated, 'added=' . $added, 'skipped=' . $skipped);
    }

    private function cmdSuggest(array $args): void
    {
        $word = wordArgument($args[0]);
        if ($this->isKnown($word)) {
            $this->emit('SUGGEST', $word, 'KNOWN');
        } elseif (isset($this->rules[$word])) {
            $this->emit('SUGGEST', $word, 'RULE', $this->rules[$word]);
        } else {
            $found = $this->candidates($word);
            $pieces = ['SUGGEST', $word, 'found=' . count($found)];
            foreach (array_slice($found, 0, $this->suggestionCount) as [$other, $distance]) {
                $pieces[] = $other . ':' . $distance;
            }
            $this->emit(...$pieces);
        }
    }

    private function cmdDist(array $args): void
    {
        $first = wordArgument($args[0]);
        $second = wordArgument($args[1]);
        [$distance, $operations] = editOperations($first, $second, $this->keyboard);
        $this->emit('DIST', $first, $second, (string) $distance, ...$operations);
    }

    private function cmdSoundex(array $args): void
    {
        $word = wordArgument($args[0]);
        $this->emit('SOUNDEX', $word, spellSoundex($word));
    }

    private function cmdSounds(array $args): void
    {
        $word = wordArgument($args[0]);
        $code = spellSoundex($word);
        $matches = [];
        foreach ($this->frequencyOrder() as $other) {
            if ($other !== $word && spellSoundex($other) === $code) $matches[] = $other;
        }
        $this->emit('SOUNDS', $word, $code, 'count=' . count($matches), ...array_slice($matches, 0, 10));
    }

    private function cmdSplit(array $args): void
    {
        $word = wordArgument($args[0]);
        [$ways, $best] = segment($word, $this->dictionary);
        if ($ways === 0) {
            $this->emit('SPLIT', $word, 'ways=0', '->', 'NONE');
        } else {
            $this->emit('SPLIT', $word, 'ways=' . $ways, '->', ...$best);
        }
    }

    private function cmdPrefix(array $args): void
    {
        $word = wordArgument($args[0]);
        $count = numberArgument($args[1], 1, 20);
        $found = [];
        foreach ($this->frequencyOrder() as $other) {
            if (str_starts_with($other, $word)) $found[] = $other;
        }
        $items = ['PREFIX', $word, 'count=' . count($found)];
        foreach (array_slice($found, 0, $count) as $other) {
            $items[] = $other . ':' . $this->dictionary[$other];
        }
        $this->emit(...$items);
    }

    private function cmdComplete(array $args): void
    {
        $word = wordArgument($args[0]);
        $count = numberArgument($args[1], 1, 20);
        $threshold = intdiv($this->limit(), 2);
        $found = [];
        foreach ($this->dictionary as $other => $frequency) {
            $distance = prefixDistance($word, $other, $this->keyboard);
            if ($distance <= $threshold) $found[] = [$other, $distance, $frequency];
        }
        usort($found, static function (array $a, array $b): int {
            return ($a[1] <=> $b[1]) ?: (($b[2] <=> $a[2]) ?: strcmp($a[0], $b[0]));
        });
        $items = ['COMPLETE', $word, 'count=' . count($found)];
        foreach (array_slice($found, 0, $count) as [$other, $distance]) {
            $items[] = $other . ':' . $distance;
        }
        $this->emit(...$items);
    }

    private function cmdList(array $args): void
    {
        $word = wordArgument($args[0]);
        $count = numberArgument($args[1], 1, 20);
        $found = array_values(array_filter(array_keys($this->dictionary),
            static fn(string $other): bool => strcmp($other, $word) >= 0));
        sort($found, SORT_STRING);
        $items = ['LIST', $word, 'count=' . count($found)];
        foreach (array_slice($found, 0, $count) as $other) {
            $items[] = $other . ':' . $this->dictionary[$other];
        }
        $this->emit(...$items);
    }

    private function cmdWord(array $args): void
    {
        $word = wordArgument($args[0]);
        $frequency = $this->requireEntry($word);
        $rank = array_search($word, $this->frequencyOrder(), true) + 1;
        $this->emit('WORD', $word, 'freq=' . $frequency, 'rank=' . $rank,
            'soundex=' . spellSoundex($word), 'neighbors=' . count($this->candidates($word)));
    }

    private function cmdAdd(array $args): void
    {
        $word = wordArgument($args[0]);
        $frequency = numberArgument($args[1], 1, 1000000);
        if (isset($this->dictionary[$word])) throw new CommandError("DUPLICATE $word");
        $this->recordUndo('ADD');
        $this->dictionary[$word] = $frequency;
        unset($this->ignored[$word]);
        $this->emit('ADD', $word, (string) $frequency);
    }

    private function cmdRemove(array $args): void
    {
        $word = wordArgument($args[0]);
        $frequency = $this->requireEntry($word);
        $this->recordUndo('REMOVE');
        unset($this->dictionary[$word]);
        $this->emit('REMOVE', $word, (string) $frequency);
    }

    private function cmdIgnore(array $args): void
    {
        $word = wordArgument($args[0]);
        if (isset($this->dictionary[$word])) throw new CommandError("IN DICTIONARY $word");
        if (isset($this->ignored[$word])) throw new CommandError("ALREADY IGNORED $word");
        $this->recordUndo('IGNORE');
        $this->ignored[$word] = true;
        $this->emit('IGNORE', $word);
    }

    private function cmdUnignore(array $args): void
    {
        $word = wordArgument($args[0]);
        if (!isset($this->ignored[$word])) throw new CommandError("NOT IGNORED $word");
        $this->recordUndo('UNIGNORE');
        unset($this->ignored[$word]);
        $this->emit('UNIGNORE', $word);
    }

    private function cmdRule(array $args): void
    {
        $source = wordArgument($args[0]);
        $target = wordArgument($args[1]);
        if (isset($this->dictionary[$source])) throw new CommandError("IN DICTIONARY $source");
        if (!isset($this->dictionary[$target])) throw new CommandError("NOT FOUND $target");
        $this->recordUndo('RULE');
        $previous = $this->rules[$source] ?? null;
        $this->rules[$source] = $target;
        if ($previous === null) $this->emit('RULE', $source, $target);
        else $this->emit('RULE', $source, $target, 'REPLACED', $previous);
    }

    private function cmdUnrule(array $args): void
    {
        $word = wordArgument($args[0]);
        if (!isset($this->rules[$word])) throw new CommandError("NO RULE $word");
        $this->recordUndo('UNRULE');
        $target = $this->rules[$word];
        unset($this->rules[$word]);
        $this->emit('UNRULE', $word, $target);
    }

    private function cmdRules(): void
    {
        $rules = $this->rules;
        ksort($rules, SORT_STRING);
        $items = ['RULES', 'count=' . count($rules)];
        foreach ($rules as $source => $target) $items[] = $source . '>' . $target;
        $this->emit(...$items);
    }

    private function cmdKeyboard(array $args): void
    {
        $mode = $args[0];
        if ($mode !== 'ON' && $mode !== 'OFF') throw new CommandError("BAD MODE $mode");
        $this->keyboard = $mode === 'ON';
        $this->emit('KEYBOARD', $mode);
    }

    private function cmdSet(array $args): void
    {
        $option = $args[0];
        if ($option !== 'LIMIT' && $option !== 'SUGGESTIONS') {
            throw new CommandError("BAD OPTION $option");
        }
        $value = numberArgument($args[1], 1, $option === 'LIMIT' ? 3 : 10);
        if ($option === 'LIMIT') $this->baseLimit = $value;
        else $this->suggestionCount = $value;
        $this->emit('SET', $option, (string) $value);
    }

    private function cmdUndo(): void
    {
        if (!$this->undoHistory) throw new CommandError('NOTHING TO UNDO');
        [$name, $this->dictionary, $this->ignored, $this->rules] = array_pop($this->undoHistory);
        $this->emit('UNDO', $name);
    }

    private function cmdReport(): void
    {
        $entries = array_keys($this->unknownLog);
        usort($entries, fn(string $a, string $b): int =>
            ($this->unknownLog[$b] <=> $this->unknownLog[$a]) ?: strcmp($a, $b));
        $items = ['REPORT', 'distinct=' . count($entries)];
        foreach (array_slice($entries, 0, 10) as $word) {
            $items[] = $word . ':' . $this->unknownLog[$word];
        }
        $this->emit(...$items);
    }

    private function cmdHistory(): void
    {
        $entries = array_keys($this->correctionLog);
        usort($entries, fn(string $a, string $b): int =>
            ($this->correctionLog[$b] <=> $this->correctionLog[$a]) ?: strcmp($a, $b));
        $items = ['HISTORY', 'distinct=' . count($entries)];
        foreach (array_slice($entries, 0, 10) as $pair) {
            $items[] = $pair . ':' . $this->correctionLog[$pair];
        }
        $this->emit(...$items);
    }

    private function cmdStats(): void
    {
        $order = $this->frequencyOrder();
        $top = $order[0];
        $characters = array_sum(array_map('strlen', array_keys($this->dictionary)));
        $this->emit('STATS', 'words=' . count($this->dictionary),
            'total=' . array_sum($this->dictionary),
            'avglen=' . decimalText($characters, count($this->dictionary), 2),
            'top=' . $top . ':' . $this->dictionary[$top],
            'ignored=' . count($this->ignored), 'rules=' . count($this->rules),
            'keyboard=' . ($this->keyboard ? 'ON' : 'OFF'),
            'limit=' . $this->limit(), 'suggestions=' . $this->suggestionCount,
            'undo=' . count($this->undoHistory));
        $items = ['SESSION'];
        foreach (COUNTERS as $name) $items[] = $name . '=' . $this->counters[$name];
        $this->emit(...$items);
    }

    public function execute(string $line): void
    {
        $parts = explode(' ', $line, 2);
        $name = $parts[0];
        $hasArguments = count($parts) === 2;
        $rest = $parts[1] ?? '';
        try {
            if (!in_array($name, TEXT_COMMANDS, true) && !array_key_exists($name, ARITIES)) {
                throw new CommandError("UNKNOWN COMMAND $name");
            }
            if (in_array($name, TEXT_COMMANDS, true)) {
                if (!$hasArguments) throw new CommandError("BAD ARGUMENTS $name");
                match ($name) {
                    'CHECK' => $this->cmdCheck($rest),
                    'CORRECT' => $this->cmdCorrect($rest),
                    'FIX' => $this->cmdFix($rest),
                    'PROFILE' => $this->cmdProfile($rest),
                    'LEARN' => $this->cmdLearn($rest),
                };
                return;
            }
            $args = $hasArguments ? explode(' ', $rest) : [];
            if (count($args) !== ARITIES[$name]) throw new CommandError("BAD ARGUMENTS $name");
            match ($name) {
                'SUGGEST' => $this->cmdSuggest($args),
                'DIST' => $this->cmdDist($args),
                'SOUNDEX' => $this->cmdSoundex($args),
                'SOUNDS' => $this->cmdSounds($args),
                'SPLIT' => $this->cmdSplit($args),
                'PREFIX' => $this->cmdPrefix($args),
                'COMPLETE' => $this->cmdComplete($args),
                'LIST' => $this->cmdList($args),
                'WORD' => $this->cmdWord($args),
                'ADD' => $this->cmdAdd($args),
                'REMOVE' => $this->cmdRemove($args),
                'IGNORE' => $this->cmdIgnore($args),
                'UNIGNORE' => $this->cmdUnignore($args),
                'RULE' => $this->cmdRule($args),
                'UNRULE' => $this->cmdUnrule($args),
                'RULES' => $this->cmdRules(),
                'KEYBOARD' => $this->cmdKeyboard($args),
                'SET' => $this->cmdSet($args),
                'UNDO' => $this->cmdUndo(),
                'REPORT' => $this->cmdReport(),
                'HISTORY' => $this->cmdHistory(),
                'STATS' => $this->cmdStats(),
            };
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }
}

$count = (int) fgets(STDIN);
$dictionary = [];
for ($i = 0; $i < $count; ++$i) {
    [$word, $frequency] = explode(' ', trim(fgets(STDIN)));
    $dictionary[$word] = (int) $frequency;
}
$checker = new SpellChecker($dictionary);
$commands = (int) fgets(STDIN);
for ($i = 0; $i < $commands; ++$i) {
    $checker->execute(rtrim(fgets(STDIN), "\r\n"));
}
echo implode("\n", $checker->output) . "\n";
