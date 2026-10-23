<?php

declare(strict_types=1);

const OPERATORS = ['AND', 'OR', 'NOT'];
const PARENTHESES = ['(', ')'];
const CONJUNCTION_CONTINUATIONS = ['AND', 'NOT', '(', 'term', 'prefix'];
const VOWELS = 'aeiou';
const STEP_NAMES = ['1a', '1b', '1c', '2', '3', '4', '5a', '5b'];
const STEP_4_SUFFIXES = [
    'al', 'ance', 'ence', 'er', 'ic', 'able', 'ible', 'ant', 'ement', 'ment',
    'ent', 'ion', 'ou', 'ism', 'ate', 'iti', 'ous', 'ive', 'ize',
];
const KWIC_WIDTH = 30;
const MAX_COUNT = 100;
const MAX_DOCUMENT_NUMBER = 999;
const MAX_LINE_NUMBER = 999;

final class CommandError extends Exception
{
}

function letterPattern(string $word): string
{
    $kinds = '';
    for ($index = 0; $index < strlen($word); $index++) {
        $letter = $word[$index];
        $consonantBefore = $index > 0 && $kinds[$index - 1] === 'C';
        $isVowel = str_contains(VOWELS, $letter) || ($letter === 'y' && $consonantBefore);
        $kinds .= $isVowel ? 'V' : 'C';
    }
    return $kinds;
}

function measure(string $word): int
{
    return substr_count(letterPattern($word), 'VC');
}

function hasVowel(string $word): bool
{
    return str_contains(letterPattern($word), 'V');
}

function endsDouble(string $word): bool
{
    return str_ends_with(letterPattern($word), 'CC') && $word[-1] === $word[-2];
}

function endsCvc(string $word): bool
{
    return str_ends_with(letterPattern($word), 'CVC') && !str_contains('wxy', $word[-1]);
}

function always(string $remainder): bool
{
    return true;
}

function measureAboveZero(string $remainder): bool
{
    return measure($remainder) > 0;
}

function measureAboveOne(string $remainder): bool
{
    return measure($remainder) > 1;
}

function ionCondition(string $remainder): bool
{
    return measure($remainder) > 1
        && (str_ends_with($remainder, 's') || str_ends_with($remainder, 't'));
}

function finalECondition(string $remainder): bool
{
    $value = measure($remainder);
    return $value > 1 || ($value === 1 && !endsCvc($remainder));
}

function rulesWith(callable $condition, array $replacements): array
{
    $rules = [];
    foreach ($replacements as $suffix => $replacement) {
        $rules[] = [$suffix, $replacement, $condition];
    }
    return $rules;
}

function ruleTables(): array
{
    static $tables = null;
    $tables ??= [
        '1a' => rulesWith(always(...), ['sses' => 'ss', 'ies' => 'i', 'ss' => 'ss', 's' => '']),
        '1b' => [
            ['eed', 'ee', measureAboveZero(...)],
            ['ed', '', hasVowel(...)],
            ['ing', '', hasVowel(...)],
        ],
        '1c' => [['y', 'i', hasVowel(...)]],
        '2' => rulesWith(measureAboveZero(...), [
            'ational' => 'ate', 'tional' => 'tion', 'enci' => 'ence', 'anci' => 'ance',
            'izer' => 'ize', 'abli' => 'able', 'alli' => 'al', 'entli' => 'ent', 'eli' => 'e',
            'ousli' => 'ous', 'ization' => 'ize', 'ation' => 'ate', 'ator' => 'ate',
            'alism' => 'al', 'iveness' => 'ive', 'fulness' => 'ful', 'ousness' => 'ous',
            'aliti' => 'al', 'iviti' => 'ive', 'biliti' => 'ble',
        ]),
        '3' => rulesWith(measureAboveZero(...), [
            'icate' => 'ic', 'ative' => '', 'alize' => 'al', 'iciti' => 'ic',
            'ical' => 'ic', 'ful' => '', 'ness' => '',
        ]),
        '4' => array_map(
            fn(string $suffix): array => [
                $suffix, '', $suffix === 'ion' ? ionCondition(...) : measureAboveOne(...),
            ],
            STEP_4_SUFFIXES,
        ),
        '5a' => [['e', '', finalECondition(...)]],
    ];
    return $tables;
}

/** Apply the rule with the longest matching suffix; return the word and the applied suffix. */
function applyRules(string $word, array $rules): array
{
    $matching = array_filter($rules, fn(array $rule): bool => str_ends_with($word, $rule[0]));
    if ($matching === []) {
        return [$word, null];
    }
    usort(
        $matching,
        fn(array $first, array $second): int => strlen($second[0]) <=> strlen($first[0]),
    );
    [$suffix, $replacement, $condition] = $matching[0];
    $remainder = substr($word, 0, -strlen($suffix));
    if (!$condition($remainder)) {
        return [$word, null];
    }
    return [$remainder . $replacement, $suffix];
}

function tidyStep1b(string $word): string
{
    if (str_ends_with($word, 'at') || str_ends_with($word, 'bl') || str_ends_with($word, 'iz')) {
        return $word . 'e';
    }
    if (endsDouble($word) && !str_contains('lsz', $word[-1])) {
        return substr($word, 0, -1);
    }
    if (measure($word) === 1 && endsCvc($word)) {
        return $word . 'e';
    }
    return $word;
}

function applyStep(string $name, string $word): string
{
    if ($name === '5b') {
        if (measure($word) > 1 && endsDouble($word) && str_ends_with($word, 'l')) {
            return substr($word, 0, -1);
        }
        return $word;
    }
    [$result, $suffix] = applyRules($word, ruleTables()[$name]);
    if ($name === '1b' && ($suffix === 'ed' || $suffix === 'ing')) {
        return tidyStep1b($result);
    }
    return $result;
}

function stemmingSteps(string $word): array
{
    $changes = [];
    if (strlen($word) > 2) {
        foreach (STEP_NAMES as $name) {
            $result = applyStep($name, $word);
            if ($result !== $word) {
                $changes[] = "$name:$result";
            }
            $word = $result;
        }
    }
    return [$word, $changes];
}

function porterStem(string $word): string
{
    static $cache = [];
    return $cache[$word] ??= stemmingSteps($word)[0];
}

function yesNo(bool $flag): string
{
    return $flag ? 'YES' : 'NO';
}

function isWord(string $text): bool
{
    return preg_match('/^[A-Za-z]{1,30}$/', $text) === 1;
}

function wordArgument(string $text): string
{
    if (!isWord($text)) {
        throw new CommandError("BAD WORD $text");
    }
    return strtolower($text);
}

function numberArgument(string $text, int $minimum, int $maximum): int
{
    if (preg_match('/^[0-9]{1,7}$/', $text) !== 1) {
        throw new CommandError("BAD NUMBER $text");
    }
    $value = (int) $text;
    if ($value < $minimum || $value > $maximum) {
        throw new CommandError("BAD NUMBER $text");
    }
    return $value;
}

function splitArguments(string $name, string $rest): array
{
    return match ($name) {
        'SEARCH' => [$rest],
        'APPEND' => explode(' ', $rest, 2),
        default => explode(' ', $rest),
    };
}

function sortedByCount(array $counts): array
{
    uksort(
        $counts,
        fn(string $first, string $second): int =>
            [$counts[$second], $first] <=> [$counts[$first], $second],
    );
    return $counts;
}

function documentCount(array $occurrences): int
{
    $numbers = array_map(fn(array $found): int => $found[0]->number, $occurrences);
    return count(array_unique($numbers));
}

function closestDistance(array $positions, array $others, bool $sameStem): ?int
{
    $gaps = [];
    if ($sameStem) {
        for ($index = 1; $index < count($positions); $index++) {
            $gaps[] = $positions[$index] - $positions[$index - 1];
        }
    } else {
        // The closest pair of different stems is adjacent in the merged order.
        $merged = array_merge(
            array_map(fn(int $position): array => [$position, 0], $positions),
            array_map(fn(int $other): array => [$other, 1], $others),
        );
        sort($merged);
        for ($index = 1; $index < count($merged); $index++) {
            if ($merged[$index][1] !== $merged[$index - 1][1]) {
                $gaps[] = $merged[$index][0] - $merged[$index - 1][0];
            }
        }
    }
    return $gaps === [] ? null : min($gaps);
}

function reducedFraction(int $numerator, int $denominator): array
{
    [$a, $b] = [$numerator, $denominator];
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return [intdiv($numerator, $a), intdiv($denominator, $a)];
}

function classify(string $lexeme): array
{
    if (in_array($lexeme, OPERATORS, true) || in_array($lexeme, PARENTHESES, true)) {
        return [$lexeme, $lexeme];
    }
    if (isWord($lexeme)) {
        return ['term', strtolower($lexeme)];
    }
    $letters = substr($lexeme, 0, -1);
    if (str_ends_with($lexeme, '*') && isWord($letters)) {
        return ['prefix', strtolower($letters)];
    }
    throw new CommandError("BAD TERM $lexeme");
}

final class Token
{
    public readonly string $form;

    public function __construct(
        public readonly string $text,
        public readonly int $line,
        public readonly int $position,
        public readonly int $start,
    ) {
        $this->form = strtolower($text);
    }

    public function end(): int
    {
        return $this->start + strlen($this->text);
    }
}

final class Document
{
    public array $lines = [];
    public array $tokens = [];

    public function __construct(public readonly int $number)
    {
    }

    public function addLine(string $text): array
    {
        $this->lines[] = $text;
        preg_match_all('/[A-Za-z]+/', $text, $matches, PREG_OFFSET_CAPTURE);
        $added = [];
        foreach ($matches[0] as [$word, $start]) {
            $token = new Token($word, count($this->lines), count($this->tokens) + 1, $start);
            $this->tokens[] = $token;
            $added[] = $token;
        }
        return $added;
    }

    public function lineTokens(int $lineNumber): array
    {
        return array_values(
            array_filter($this->tokens, fn(Token $token): bool => $token->line === $lineNumber),
        );
    }

    public function reference(Token $token): string
    {
        return "{$this->number}:{$token->line}:{$token->position}";
    }
}

final class QueryParser
{
    private int $position = 0;

    public function __construct(private readonly array $items, private readonly array $stemSets)
    {
    }

    private function peek(): ?string
    {
        return $this->items[$this->position][0] ?? null;
    }

    private function take(): array
    {
        if ($this->position >= count($this->items)) {
            throw new CommandError('SYNTAX');
        }
        return $this->items[$this->position++];
    }

    public function parse(): array
    {
        $result = $this->expression();
        if ($this->position < count($this->items)) {
            throw new CommandError('SYNTAX');
        }
        return $result;
    }

    private function expression(): array
    {
        [$canonical, $documents] = $this->conjunction();
        while ($this->peek() === 'OR') {
            $this->position++;
            [$right, $rightDocuments] = $this->conjunction();
            $canonical = "($canonical OR $right)";
            $documents += $rightDocuments;
        }
        return [$canonical, $documents];
    }

    private function conjunction(): array
    {
        [$canonical, $documents] = $this->negation();
        while (in_array($this->peek(), CONJUNCTION_CONTINUATIONS, true)) {
            if ($this->peek() === 'AND') {
                $this->position++;
            }
            [$right, $rightDocuments] = $this->negation();
            $canonical = "($canonical AND $right)";
            $documents = array_intersect_key($documents, $rightDocuments);
        }
        return [$canonical, $documents];
    }

    private function negation(): array
    {
        if ($this->peek() === 'NOT') {
            $this->position++;
            [$canonical, $documents] = $this->negation();
            return ["(NOT $canonical)", array_diff_key($this->stemSets, $documents)];
        }
        return $this->element();
    }

    private function element(): array
    {
        [$kind, $spelling] = $this->take();
        if ($kind === '(') {
            $result = $this->expression();
            if ($this->take()[0] !== ')') {
                throw new CommandError('SYNTAX');
            }
            return $result;
        }
        if ($kind === 'term') {
            $stem = porterStem($spelling);
            $documents = array_filter(
                $this->stemSets,
                fn(array $stems): bool => isset($stems[$stem]),
            );
            return [$stem, $documents];
        }
        if ($kind === 'prefix') {
            $documents = array_filter(
                $this->stemSets,
                function (array $stems) use ($spelling): bool {
                    foreach (array_keys($stems) as $stem) {
                        if (str_starts_with($stem, $spelling)) {
                            return true;
                        }
                    }
                    return false;
                },
            );
            return ["$spelling*", $documents];
        }
        throw new CommandError('SYNTAX');
    }
}

final class SearchEngine
{
    private array $documents = [];
    private array $output = [];
    private array $handlers;

    public function __construct(private array $stopwords)
    {
        $this->handlers = [
            'STEM' => [1, 10, $this->stemWords(...)],
            'STEPS' => [1, 1, $this->showSteps(...)],
            'MEASURE' => [1, 1, $this->showMeasure(...)],
            'INDEX' => [0, 1, $this->showIndex(...)],
            'SEARCH' => [1, 1, $this->search(...)],
            'PHRASE' => [2, 10, $this->phrase(...)],
            'NEAR' => [3, 3, $this->near(...)],
            'TOP' => [1, 2, $this->top(...)],
            'KWIC' => [1, 1, $this->kwic(...)],
            'TF' => [2, 2, $this->termFrequency(...)],
            'DF' => [1, 1, $this->documentFrequency(...)],
            'VARIANTS' => [1, 1, $this->variants(...)],
            'SIMILAR' => [2, 2, $this->similar(...)],
            'RANK' => [2, 11, $this->rank(...)],
            'INFO' => [1, 1, $this->info(...)],
            'LINE' => [2, 2, $this->showLine(...)],
            'STATS' => [0, 0, $this->stats(...)],
            'STOP' => [1, 1, $this->stop(...)],
            'UNSTOP' => [1, 1, $this->unstop(...)],
            'APPEND' => [2, 2, $this->append(...)],
            'DELETE' => [1, 1, $this->delete(...)],
        ];
    }

    public function output(): array
    {
        return $this->output;
    }

    private function emit(string|int ...$parts): void
    {
        $this->output[] = implode(' ', $parts);
    }

    public function addDocument(int $number): Document
    {
        return $this->documents[$number] = new Document($number);
    }

    private function orderedDocuments(): array
    {
        $documents = $this->documents;
        ksort($documents);
        return $documents;
    }

    private function isIndexed(Token $token): bool
    {
        return !isset($this->stopwords[$token->form]);
    }

    private function indexedTokens(Document $document): array
    {
        return array_values(array_filter($document->tokens, $this->isIndexed(...)));
    }

    private function termFrequencies(Document $document): array
    {
        $stems = array_map(
            fn(Token $token): string => porterStem($token->form),
            $this->indexedTokens($document),
        );
        return array_count_values($stems);
    }

    private function stemSet(Document $document): array
    {
        return array_fill_keys(array_keys($this->termFrequencies($document)), true);
    }

    private function totalFrequencies(): array
    {
        $totals = [];
        foreach ($this->documents as $document) {
            foreach ($this->termFrequencies($document) as $stem => $count) {
                $totals[$stem] = ($totals[$stem] ?? 0) + $count;
            }
        }
        return $totals;
    }

    private function occurrenceMap(): array
    {
        $occurrences = [];
        foreach ($this->orderedDocuments() as $document) {
            foreach ($this->indexedTokens($document) as $token) {
                $occurrences[porterStem($token->form)][] = [$document, $token];
            }
        }
        return $occurrences;
    }

    private function stemPositions(Document $document, string $stem): array
    {
        $positions = [];
        foreach ($this->indexedTokens($document) as $token) {
            if (porterStem($token->form) === $stem) {
                $positions[] = $token->position;
            }
        }
        return $positions;
    }

    private function formCount(string $form): int
    {
        $count = 0;
        foreach ($this->documents as $document) {
            foreach ($document->tokens as $token) {
                if ($token->form === $form) {
                    $count++;
                }
            }
        }
        return $count;
    }

    private function tokenMatches(Token $token, string $target): bool
    {
        return $target === '?'
            || ($this->isIndexed($token) && porterStem($token->form) === $target);
    }

    private function describeToken(Token $token): string
    {
        if ($this->isIndexed($token)) {
            return $token->form . '/' . porterStem($token->form);
        }
        return $token->form . '/-';
    }

    private function termArgument(string $text): string
    {
        $word = wordArgument($text);
        if (isset($this->stopwords[$word])) {
            throw new CommandError("STOPWORD $word");
        }
        return porterStem($word);
    }

    private function documentArgument(string $text): Document
    {
        $number = numberArgument($text, 1, MAX_DOCUMENT_NUMBER);
        if (!isset($this->documents[$number])) {
            throw new CommandError("NO DOC $number");
        }
        return $this->documents[$number];
    }

    private function stemWords(array $arguments): void
    {
        $words = array_map(wordArgument(...), $arguments);
        $items = array_map(fn(string $word): string => "$word:" . porterStem($word), $words);
        $this->emit('STEM', ...$items);
    }

    private function showSteps(array $arguments): void
    {
        $word = wordArgument($arguments[0]);
        [, $changes] = stemmingSteps($word);
        if ($changes === []) {
            $this->emit('STEPS', $word, 'NONE');
        } else {
            $this->emit('STEPS', $word, ...$changes);
        }
    }

    private function showMeasure(array $arguments): void
    {
        $word = wordArgument($arguments[0]);
        $this->emit(
            'MEASURE',
            $word,
            letterPattern($word),
            'm=' . measure($word),
            'vowel=' . yesNo(hasVowel($word)),
            'double=' . yesNo(endsDouble($word)),
            'cvc=' . yesNo(endsCvc($word)),
        );
    }

    private function showIndex(array $arguments): void
    {
        $prefix = $arguments === [] ? '' : wordArgument($arguments[0]);
        $occurrences = $this->occurrenceMap();
        $stems = array_filter(
            array_keys($occurrences),
            fn(string $stem): bool => str_starts_with($stem, $prefix),
        );
        sort($stems, SORT_STRING);
        $this->emit('INDEX', 'stems=' . count($stems));
        foreach ($stems as $stem) {
            $found = $occurrences[$stem];
            $references = array_map(
                fn(array $occurrence): string => $occurrence[0]->reference($occurrence[1]),
                $found,
            );
            $this->emit($stem, 'df=' . documentCount($found), ...$references);
        }
    }

    private function search(array $arguments): void
    {
        preg_match_all('/[()]|[^ ()]+/', $arguments[0], $matches);
        $items = array_map(classify(...), $matches[0]);
        $stemSets = array_map($this->stemSet(...), $this->documents);
        [$canonical, $found] = (new QueryParser($items, $stemSets))->parse();
        foreach ($items as [$kind, $spelling]) {
            if ($kind === 'term' && isset($this->stopwords[$spelling])) {
                throw new CommandError("STOPWORD $spelling");
            }
        }
        $numbers = array_keys($found);
        sort($numbers);
        $this->emit('SEARCH', $canonical, 'count=' . count($numbers), ...$numbers);
    }

    private function phrase(array $arguments): void
    {
        $words = array_map(wordArgument(...), $arguments);
        $stopwords = array_filter($words, fn(string $word): bool => isset($this->stopwords[$word]));
        if (count($stopwords) === count($words)) {
            throw new CommandError('STOPWORDS ONLY');
        }
        $targets = array_map(
            fn(string $word): string => isset($this->stopwords[$word]) ? '?' : porterStem($word),
            $words,
        );
        $matches = [];
        foreach ($this->orderedDocuments() as $document) {
            $tokens = $document->tokens;
            for ($start = 0; $start + count($targets) <= count($tokens); $start++) {
                $matched = true;
                foreach ($targets as $offset => $target) {
                    if (!$this->tokenMatches($tokens[$start + $offset], $target)) {
                        $matched = false;
                        break;
                    }
                }
                if ($matched) {
                    $matches[] = $document->reference($tokens[$start]);
                }
            }
        }
        $phraseText = implode(' ', $targets);
        $this->emit("PHRASE \"$phraseText\"", 'matches=' . count($matches), ...$matches);
    }

    private function near(array $arguments): void
    {
        $first = $this->termArgument($arguments[0]);
        $second = $this->termArgument($arguments[1]);
        $limit = numberArgument($arguments[2], 1, MAX_COUNT);
        $found = [];
        foreach ($this->orderedDocuments() as $document) {
            $distance = closestDistance(
                $this->stemPositions($document, $first),
                $this->stemPositions($document, $second),
                $first === $second,
            );
            if ($distance !== null && $distance <= $limit) {
                $found[] = "{$document->number}:$distance";
            }
        }
        $this->emit('NEAR', $first, $second, $limit, 'count=' . count($found), ...$found);
    }

    private function top(array $arguments): void
    {
        $limit = numberArgument($arguments[0], 1, MAX_COUNT);
        if (count($arguments) === 2) {
            $document = $this->documentArgument($arguments[1]);
            $counts = $this->termFrequencies($document);
            $header = "TOP $limit doc={$document->number}";
        } else {
            $counts = $this->totalFrequencies();
            $header = "TOP $limit";
        }
        $ranked = array_slice(sortedByCount($counts), 0, $limit, true);
        $items = array_map(
            fn(string $stem, int $count): string => "$stem:$count",
            array_keys($ranked),
            $ranked,
        );
        $this->emit($header, ...$items);
    }

    private function kwic(array $arguments): void
    {
        $stem = $this->termArgument($arguments[0]);
        $found = $this->occurrenceMap()[$stem] ?? [];
        $this->emit('KWIC', $stem, 'count=' . count($found));
        foreach ($found as [$document, $token]) {
            $text = $document->lines[$token->line - 1];
            $from = max(0, $token->start - KWIC_WIDTH);
            $before = substr($text, $from, $token->start - $from);
            $before = str_pad($before, KWIC_WIDTH, ' ', STR_PAD_LEFT);
            $after = str_pad(substr($text, $token->end(), KWIC_WIDTH), KWIC_WIDTH);
            $this->emit("|{$before}[{$token->text}]{$after}|", $document->reference($token));
        }
    }

    private function termFrequency(array $arguments): void
    {
        $document = $this->documentArgument($arguments[0]);
        $stem = $this->termArgument($arguments[1]);
        $this->emit('TF', $document->number, $stem, $this->termFrequencies($document)[$stem] ?? 0);
    }

    private function documentFrequency(array $arguments): void
    {
        $stem = $this->termArgument($arguments[0]);
        $this->emit('DF', $stem, documentCount($this->occurrenceMap()[$stem] ?? []));
    }

    private function variants(array $arguments): void
    {
        $stem = $this->termArgument($arguments[0]);
        $found = $this->occurrenceMap()[$stem] ?? [];
        $forms = array_count_values(
            array_map(fn(array $occurrence): string => $occurrence[1]->form, $found),
        );
        ksort($forms, SORT_STRING);
        $items = array_map(
            fn(string $form, int $count): string => "$form:$count",
            array_keys($forms),
            $forms,
        );
        $this->emit('VARIANTS', $stem, 'count=' . count($forms), ...$items);
    }

    private function similar(array $arguments): void
    {
        $document = $this->documentArgument($arguments[0]);
        $limit = numberArgument($arguments[1], 1, MAX_COUNT);
        $stems = $this->stemSet($document);
        $scores = [];
        foreach ($this->documents as $other) {
            if ($other === $document) {
                continue;
            }
            $otherStems = $this->stemSet($other);
            $union = count($stems + $otherStems);
            $common = count(array_intersect_key($stems, $otherStems));
            [$numerator, $denominator] = $union > 0 ? reducedFraction($common, $union) : [0, 1];
            $scores[] = [$numerator, $denominator, $other->number];
        }
        usort(
            $scores,
            fn(array $first, array $second): int =>
                ($second[0] * $first[1] <=> $first[0] * $second[1]) ?: $first[2] <=> $second[2],
        );
        $items = [];
        foreach (array_slice($scores, 0, $limit) as [$numerator, $denominator, $number]) {
            $items[] = "$number:$numerator/$denominator";
        }
        $this->emit('SIMILAR', $document->number, ...$items);
    }

    private function rank(array $arguments): void
    {
        $limit = numberArgument($arguments[0], 1, MAX_COUNT);
        $query = [];
        foreach (array_slice($arguments, 1) as $argument) {
            $query[$this->termArgument($argument)] = true;
        }
        $ranked = [];
        foreach ($this->documents as $document) {
            $counts = $this->termFrequencies($document);
            $matched = 0;
            $total = 0;
            foreach (array_keys($query) as $stem) {
                $count = $counts[$stem] ?? 0;
                if ($count > 0) {
                    $matched++;
                }
                $total += $count;
            }
            if ($matched > 0) {
                $ranked[] = [$matched, $total, $document->number];
            }
        }
        usort(
            $ranked,
            fn(array $first, array $second): int =>
                [$second[0], $second[1], $first[2]] <=> [$first[0], $first[1], $second[2]],
        );
        $items = [];
        foreach (array_slice($ranked, 0, $limit) as [$matched, $total, $number]) {
            $items[] = "$number:$matched:$total";
        }
        $this->emit('RANK count=' . count($ranked), ...$items);
    }

    private function info(array $arguments): void
    {
        $document = $this->documentArgument($arguments[0]);
        $counts = $this->termFrequencies($document);
        $top = '-';
        if ($counts !== []) {
            $stem = array_key_first(sortedByCount($counts));
            $top = "$stem:{$counts[$stem]}";
        }
        $this->emit(
            'INFO',
            $document->number,
            'lines=' . count($document->lines),
            'tokens=' . count($document->tokens),
            'indexed=' . array_sum($counts),
            'stems=' . count($counts),
            "top=$top",
        );
    }

    private function showLine(array $arguments): void
    {
        $document = $this->documentArgument($arguments[0]);
        $lineNumber = numberArgument($arguments[1], 1, MAX_LINE_NUMBER);
        if ($lineNumber > count($document->lines)) {
            throw new CommandError("NO LINE {$document->number}:$lineNumber");
        }
        $tokens = $document->lineTokens($lineNumber);
        $this->emit(
            "LINE {$document->number}:$lineNumber",
            'tokens=' . count($tokens),
            ...array_map($this->describeToken(...), $tokens),
        );
    }

    private function stats(array $arguments): void
    {
        $lines = 0;
        $tokens = 0;
        $indexed = 0;
        foreach ($this->documents as $document) {
            $lines += count($document->lines);
            $tokens += count($document->tokens);
            $indexed += count($this->indexedTokens($document));
        }
        $this->emit(
            'STATS',
            'docs=' . count($this->documents),
            "lines=$lines",
            "tokens=$tokens",
            "indexed=$indexed",
            'stems=' . count($this->totalFrequencies()),
            'stopwords=' . count($this->stopwords),
        );
    }

    private function stop(array $arguments): void
    {
        $word = wordArgument($arguments[0]);
        if (isset($this->stopwords[$word])) {
            throw new CommandError("ALREADY STOPWORD $word");
        }
        $this->stopwords[$word] = true;
        $this->emit('STOP', $word, 'unindexed=' . $this->formCount($word));
    }

    private function unstop(array $arguments): void
    {
        $word = wordArgument($arguments[0]);
        if (!isset($this->stopwords[$word])) {
            throw new CommandError("NOT STOPWORD $word");
        }
        unset($this->stopwords[$word]);
        $this->emit('UNSTOP', $word, 'indexed=' . $this->formCount($word));
    }

    private function append(array $arguments): void
    {
        $number = numberArgument($arguments[0], 1, MAX_DOCUMENT_NUMBER);
        $created = !isset($this->documents[$number]);
        $document = $created ? $this->addDocument($number) : $this->documents[$number];
        $tokens = $document->addLine($arguments[1]);
        $indexed = count(array_filter($tokens, $this->isIndexed(...)));
        $this->emit(
            'APPEND',
            $number,
            'line=' . count($document->lines),
            'tokens=' . count($tokens),
            "indexed=$indexed",
            'new=' . yesNo($created),
        );
    }

    private function delete(array $arguments): void
    {
        $document = $this->documentArgument($arguments[0]);
        unset($this->documents[$document->number]);
        $this->emit(
            'DELETE',
            $document->number,
            'lines=' . count($document->lines),
            'tokens=' . count($document->tokens),
        );
    }

    public function execute(string $line): void
    {
        $parts = explode(' ', $line, 2);
        $name = $parts[0];
        try {
            if (!isset($this->handlers[$name])) {
                throw new CommandError("UNKNOWN COMMAND $name");
            }
            [$minimum, $maximum, $handler] = $this->handlers[$name];
            $arguments = count($parts) === 2 ? splitArguments($name, $parts[1]) : [];
            if (count($arguments) < $minimum || count($arguments) > $maximum) {
                throw new CommandError("BAD ARGUMENTS $name");
            }
            $handler($arguments);
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }
}

function main(): void
{
    $lines = file('php://stdin', FILE_IGNORE_NEW_LINES);
    $engine = new SearchEngine(array_fill_keys(array_slice(explode(' ', $lines[0]), 1), true));
    $index = 1;
    while (str_starts_with($lines[$index], 'DOC ')) {
        $document = $engine->addDocument((int) substr($lines[$index], 4));
        $index++;
        while ($lines[$index] !== 'ENDDOC') {
            $document->addLine($lines[$index]);
            $index++;
        }
        $index++;
    }
    foreach (array_slice($lines, $index) as $line) {
        if ($line === 'END') {
            break;
        }
        $engine->execute($line);
    }
    echo implode("\n", $engine->output()), "\n";
}

main();
