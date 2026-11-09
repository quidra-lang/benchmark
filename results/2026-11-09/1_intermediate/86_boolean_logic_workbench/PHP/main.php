<?php
class LogicError extends Exception
{
}

const PRECEDENCE = ['<->' => 1, '->' => 2, '|' => 3, '^' => 4, '&' => 5];

function boolVar(string $name): array
{
    return ['variable', $name];
}

function boolConst(int $value): array
{
    return ['constant', $value];
}

function boolNot(array $node): array
{
    return ['not', $node];
}

function boolBinary(string $op, array $left, array $right): array
{
    return [$op, $left, $right];
}

function isBinary(array $node): bool
{
    return isset(PRECEDENCE[$node[0]]);
}

function notation(array $node): string
{
    if ($node[0] === 'variable' || $node[0] === 'constant') {
        return (string)$node[1];
    }
    if ($node[0] === 'not') {
        $text = notation($node[1]);
        return '~' . (isBinary($node[1]) ? '(' . $text . ')' : $text);
    }
    [$op, $a, $b] = $node;
    $left = notation($a);
    $right = notation($b);
    if (isBinary($a) && (PRECEDENCE[$a[0]] < PRECEDENCE[$op] || ($a[0] === '->' && $op === '->'))) {
        $left = '(' . $left . ')';
    }
    if (isBinary($b) && (PRECEDENCE[$b[0]] < PRECEDENCE[$op] || ($b[0] === $op && $op !== '->'))) {
        $right = '(' . $right . ')';
    }
    return $left . ' ' . $op . ' ' . $right;
}

function variableNames(array $node): array
{
    if ($node[0] === 'variable') {
        return [$node[1]];
    }
    if ($node[0] === 'constant') {
        return [];
    }
    if ($node[0] === 'not') {
        return variableNames($node[1]);
    }
    $names = array_values(array_unique(array_merge(variableNames($node[1]), variableNames($node[2]))));
    sort($names, SORT_STRING);
    return $names;
}

function measures(array $node): array
{
    if ($node[0] === 'variable' || $node[0] === 'constant') {
        return [1, 1];
    }
    $a = measures($node[1]);
    if ($node[0] === 'not') {
        return [$a[0] + 1, $a[1] + 1];
    }
    $b = measures($node[2]);
    return [$a[0] + $b[0] + 1, max($a[1], $b[1]) + 1];
}

class FormulaParser
{
    private array $tokens = [];
    private int $position = 0;

    public function __construct(string $text, int $start, private array $definitions)
    {
        $i = 0;
        while ($i < strlen($text)) {
            $c = $text[$i];
            if ($c === ' ') {
                $i++;
                continue;
            }
            $from = $i;
            if (substr($text, $i, 3) === '<->') {
                $i += 3;
            } elseif (substr($text, $i, 2) === '->') {
                $i += 2;
            } elseif ($c >= 'a' && $c <= 'z') {
                $i++;
                while ($i < strlen($text) && preg_match('/[a-z0-9]/', $text[$i])) {
                    $i++;
                }
            } elseif (str_contains('ABCDEFGHIJKLMNOPQRSTUVWXYZ01~&^|()', $c)) {
                $i++;
            } else {
                throw new LogicError("invalid character '" . $c . "' at " . ($start + $i));
            }
            $this->tokens[] = [substr($text, $from, $i - $from), $start + $from];
        }
        $this->tokens[] = ['', $start + strlen($text)];
    }

    private function peek(): string
    {
        return $this->tokens[$this->position][0];
    }

    private function advance(): string
    {
        return $this->tokens[$this->position++][0];
    }

    private function unexpected(): never
    {
        [$text, $position] = $this->tokens[$this->position];
        throw new LogicError($text === '' ? 'unexpected end of formula at ' . $position : "unexpected '" . $text . "' at " . $position);
    }

    private function unary(): array
    {
        if ($this->peek() === '~') {
            $this->advance();
            return boolNot($this->unary());
        }
        if ($this->peek() === '(') {
            $this->advance();
            $result = $this->expression(0);
            if ($this->peek() !== ')') {
                $this->unexpected();
            }
            $this->advance();
            return $result;
        }
        if (preg_match('/\A[A-Z]\z/', $this->peek())) {
            return boolVar($this->advance());
        }
        if ($this->peek() === '0' || $this->peek() === '1') {
            return boolConst((int)$this->advance());
        }
        if (preg_match('/\A[a-z][a-z0-9]*\z/', $this->peek())) {
            [$text, $position] = $this->tokens[$this->position];
            if (!isset($this->definitions[$text])) {
                throw new LogicError("undefined name '" . $text . "' at " . $position);
            }
            $this->advance();
            return $this->definitions[$text];
        }
        $this->unexpected();
    }

    private function expression(int $level): array
    {
        if ($level === 5) {
            return $this->unary();
        }
        $op = ['<->', '->', '|', '^', '&'][$level];
        $result = $this->expression($level + 1);
        while ($this->peek() === $op) {
            $this->advance();
            $result = boolBinary($op, $result, $this->expression($op === '->' ? $level : $level + 1));
        }
        return $result;
    }

    public function parse(): array
    {
        $result = $this->expression(0);
        if ($this->peek() !== '') {
            $this->unexpected();
        }
        return $result;
    }
}

function nnf(array $node, bool $positive = true): array
{
    $memo = [];
    $serial = 0;
    $visit = function (array $current, bool $sign) use (&$visit, &$memo, &$serial): array {
        $key = ($sign ? 'p' : 'n') . serialize($current);
        if (isset($memo[$key])) {
            return $memo[$key];
        }
        if ($current[0] === 'variable') {
            $result = $sign ? $current : boolNot($current);
        } elseif ($current[0] === 'constant') {
            $result = boolConst($sign ? $current[1] : 1 - $current[1]);
        } elseif ($current[0] === 'not') {
            $result = $visit($current[1], !$sign);
        } elseif ($current[0] === '&' || $current[0] === '|') {
            $op = $sign ? $current[0] : ($current[0] === '&' ? '|' : '&');
            $result = boolBinary($op, $visit($current[1], $sign), $visit($current[2], $sign));
        } elseif ($current[0] === '->') {
            $result = boolBinary($sign ? '|' : '&', $visit($current[1], !$sign), $visit($current[2], $sign));
        } else {
            $same = $current[0] === '<->' ? $sign : !$sign;
            $result = boolBinary('|',
                boolBinary('&', $visit($current[1], true), $visit($current[2], $same)),
                boolBinary('&', $visit($current[1], false), $visit($current[2], !$same)));
        }
        $result['memo_id'] = ++$serial;
        $memo[$key] = $result;
        return $result;
    };
    return $visit($node, $positive);
}

function dual(array $node): array
{
    return match ($node[0]) {
        'variable' => $node,
        'constant' => boolConst(1 - $node[1]),
        'not' => boolNot(dual($node[1])),
        '->' => boolBinary('&', boolNot(dual($node[1])), dual($node[2])),
        default => boolBinary(['&' => '|', '|' => '&', '^' => '<->', '<->' => '^'][$node[0]], dual($node[1]), dual($node[2]))
    };
}

function reduceNegation(array $node): array
{
    if ($node[0] === 'constant') {
        return boolConst(1 - $node[1]);
    }
    return $node[0] === 'not' ? $node[1] : boolNot($node);
}

function simplifyBinary(string $op, array $a, array $b): array
{
    $zero = boolConst(0);
    $one = boolConst(1);
    $equal = $a === $b;
    $complementary = $a === boolNot($b) || $b === boolNot($a);
    switch ($op) {
        case '&':
            if ($a === $zero || $b === $zero) {
                return $zero;
            }
            if ($a === $one) {
                return $b;
            }
            if ($b === $one || $equal) {
                return $a;
            }
            if ($complementary) {
                return $zero;
            }
            break;
        case '|':
            if ($a === $one || $b === $one) {
                return $one;
            }
            if ($a === $zero) {
                return $b;
            }
            if ($b === $zero || $equal) {
                return $a;
            }
            if ($complementary) {
                return $one;
            }
            break;
        case '^':
            if ($a === $zero) {
                return $b;
            }
            if ($b === $zero) {
                return $a;
            }
            if ($a === $one) {
                return reduceNegation($b);
            }
            if ($b === $one) {
                return reduceNegation($a);
            }
            if ($equal) {
                return $zero;
            }
            if ($complementary) {
                return $one;
            }
            break;
        case '->':
            if ($a === $zero || $b === $one) {
                return $one;
            }
            if ($a === $one) {
                return $b;
            }
            if ($b === $zero) {
                return reduceNegation($a);
            }
            if ($equal) {
                return $one;
            }
            if ($complementary) {
                return $b;
            }
            break;
        case '<->':
            if ($a === $one) {
                return $b;
            }
            if ($b === $one) {
                return $a;
            }
            if ($a === $zero) {
                return reduceNegation($b);
            }
            if ($b === $zero) {
                return reduceNegation($a);
            }
            if ($equal) {
                return $one;
            }
            if ($complementary) {
                return $zero;
            }
            break;
    }
    return boolBinary($op, $a, $b);
}

function simplify(array $node, array $assignments = []): array
{
    if ($node[0] === 'variable') {
        return isset($assignments[$node[1]]) ? boolConst($assignments[$node[1]]) : $node;
    }
    if ($node[0] === 'constant') {
        return $node;
    }
    if ($node[0] === 'not') {
        return reduceNegation(simplify($node[1], $assignments));
    }
    return simplifyBinary($node[0], simplify($node[1], $assignments), simplify($node[2], $assignments));
}

function evaluate(array $node, array $assignments): int
{
    if ($node[0] === 'variable') {
        return $assignments[$node[1]];
    }
    if ($node[0] === 'constant') {
        return $node[1];
    }
    if ($node[0] === 'not') {
        return 1 - evaluate($node[1], $assignments);
    }
    $a = evaluate($node[1], $assignments);
    $b = evaluate($node[2], $assignments);
    return match ($node[0]) {
        '&' => $a & $b, '|' => $a | $b, '^' => $a ^ $b,
        '->' => $a === 1 && $b === 0 ? 0 : 1,
        '<->' => $a === $b ? 1 : 0
    };
}

function pattern(int $row, int $size): string
{
    return $size === 0 ? '' : str_pad(decbin($row), $size, '0', STR_PAD_LEFT);
}

function patternKey(string $text): string
{
    return strtr($text, '10-', '012');
}

function literalCount(string $text): int
{
    return substr_count($text, '1') + substr_count($text, '0');
}

function complementPattern(string $text): string
{
    return strtr($text, '01', '10');
}

function containsRow(string $text, string $row): bool
{
    for ($i = 0; $i < strlen($text); $i++) {
        if ($text[$i] !== '-' && $text[$i] !== $row[$i]) {
            return false;
        }
    }
    return true;
}

function patternPart(string $text, array $names, bool $product = true): string
{
    $literals = [];
    for ($i = 0; $i < strlen($text); $i++) {
        if ($text[$i] !== '-') {
            $literals[] = ($text[$i] === '1' ? '' : '~') . $names[$i];
        }
    }
    return $literals === [] ? ($product ? '1' : '0') : implode($product ? ' & ' : ' | ', $literals);
}

function coverText(array $patterns, array $names, bool $product = true): string
{
    if ($patterns === []) {
        return $product ? '0' : '1';
    }
    $parts = [];
    foreach ($patterns as $text) {
        $part = patternPart($text, $names, $product);
        $parts[] = !$product && count($patterns) >= 2 && literalCount($text) >= 2 ? '(' . $part . ')' : $part;
    }
    return implode($product ? ' | ' : ' & ', $parts);
}

function sortPatterns(array $patterns): array
{
    usort($patterns, fn($a, $b) => strcmp(patternKey($a), patternKey($b)));
    return $patterns;
}

function coefficients(array $values, int $size): array
{
    for ($i = 0; $i < $size; $i++) {
        $bit = 1 << $i;
        for ($row = 0; $row < count($values); $row++) {
            if (($row & $bit) !== 0) {
                $values[$row] ^= $values[$row ^ $bit];
            }
        }
    }
    return $values;
}

function coverKeyCompare(array $a, array $b): int
{
    if ($a[0] !== $b[0]) {
        return $a[0] <=> $b[0];
    }
    if ($a[1] !== $b[1]) {
        return $a[1] <=> $b[1];
    }
    foreach ($a[2] as $i => $key) {
        $comparison = strcmp($key, $b[2][$i]);
        if ($comparison !== 0) {
            return $comparison;
        }
    }
    return 0;
}

function minimize(array $on, array $dc, array $names, bool $pos = false): array
{
    $rows = [];
    $stage = [];
    foreach (array_unique(array_merge($on, $dc)) as $row) {
        $stage[pattern($row, count($names))] = true;
    }
    foreach ($on as $row) {
        $rows[$row] = pattern($row, count($names));
    }
    $primes = [];
    $lines = [];
    $number = 0;
    while (true) {
        $used = [];
        $next = [];
        foreach ($stage as $raw => $ignored) {
            $text = (string)$raw;
            for ($i = 0; $i < strlen($text); $i++) {
                if ($text[$i] !== '0') {
                    continue;
                }
                $partner = $text;
                $partner[$i] = '1';
                if (!isset($stage[$partner])) {
                    continue;
                }
                $combined = $text;
                $combined[$i] = '-';
                $used[$text] = $used[$partner] = true;
                $next[$combined] = true;
            }
        }
        $fresh = array_diff_key($stage, $used);
        $primes += $fresh;
        if (!$pos) {
            $lines[] = 'stage ' . $number . ': implicants ' . count($stage) . ' primes ' . count($fresh);
        }
        if ($next === []) {
            break;
        }
        $stage = $next;
        $number++;
    }
    $targets = [];
    foreach (array_keys($primes) as $raw) {
        $text = (string)$raw;
        foreach ($rows as $row) {
            if (containsRow($text, $row)) {
                $targets[] = $text;
                break;
            }
        }
    }
    $targets = sortPatterns($targets);
    $coverage = [];
    foreach ($targets as $text) {
        $covered = [];
        foreach ($on as $row) {
            if (containsRow($text, $rows[$row])) {
                $covered[$row] = true;
            }
        }
        $coverage[] = $covered;
    }
    $essential = [];
    foreach ($on as $row) {
        $candidates = [];
        foreach ($coverage as $i => $covered) {
            if (isset($covered[$row])) {
                $candidates[] = $i;
            }
        }
        if (count($candidates) === 1) {
            $essential[$candidates[0]] = true;
        }
    }
    $optional = [];
    foreach ($targets as $i => $text) {
        if (!isset($essential[$i])) {
            $optional[] = $i;
        }
    }
    $best = null;
    $bestKey = null;
    for ($mask = 0; $mask < (1 << count($optional)); $mask++) {
        $chosen = array_keys($essential);
        foreach ($optional as $i => $index) {
            if (($mask & (1 << $i)) !== 0) {
                $chosen[] = $index;
            }
        }
        $covered = [];
        foreach ($chosen as $i) {
            $covered += $coverage[$i];
        }
        $complete = true;
        foreach ($on as $row) {
            if (!isset($covered[$row])) {
                $complete = false;
                break;
            }
        }
        if (!$complete) {
            continue;
        }
        $texts = sortPatterns(array_map(fn($i) => $pos ? complementPattern($targets[$i]) : $targets[$i], $chosen));
        $key = [count($texts), array_sum(array_map('literalCount', $texts)), array_map('patternKey', $texts)];
        if ($bestKey === null || coverKeyCompare($key, $bestKey) < 0) {
            $bestKey = $key;
            $best = $texts;
        }
    }
    if ($pos) {
        return ['minimal: ' . coverText($best, $names, false), 'clauses ' . count($best) . ' literals ' . $bestKey[1]];
    }
    $terms = array_map(fn($text) => patternPart($text, $names), $targets);
    $indices = array_keys($essential);
    sort($indices, SORT_NUMERIC);
    $essentials = array_map(fn($i) => patternPart($targets[$i], $names), $indices);
    return array_merge($lines, ['primes: ' . ($terms === [] ? 'none' : implode(', ', $terms)),
        'essential: ' . ($essentials === [] ? 'none' : implode(', ', $essentials)),
        'minimal: ' . coverText($best, $names), 'terms ' . count($best) . ' literals ' . $bestKey[1]]);
}

function mergeClause(string $a, string $b): ?string
{
    $result = '';
    for ($i = 0; $i < strlen($a); $i++) {
        if ($a[$i] !== '-' && $b[$i] !== '-' && $a[$i] !== $b[$i]) {
            return null;
        }
        $result .= $a[$i] === '-' ? $b[$i] : $a[$i];
    }
    return $result;
}

function tidy(array $clauses): array
{
    $unique = array_values(array_unique($clauses));
    $result = [];
    foreach ($unique as $clause) {
        $absorbed = false;
        foreach ($unique as $other) {
            if ($clause === $other) {
                continue;
            }
            $subset = true;
            for ($i = 0; $i < strlen($other); $i++) {
                if ($other[$i] !== '-' && $other[$i] !== $clause[$i]) {
                    $subset = false;
                    break;
                }
            }
            if ($subset) {
                $absorbed = true;
                break;
            }
        }
        if (!$absorbed) {
            $result[] = $clause;
        }
    }
    return sortPatterns($result);
}

function clauses(array $node, array $names): array
{
    $memo = [];
    $visit = function (array $current) use (&$visit, &$memo, $names): array {
        $key = $current['memo_id'] ?? null;
        if ($key !== null && isset($memo[$key])) {
            return $memo[$key];
        }
        if ($current[0] === 'variable' || $current[0] === 'not') {
            $name = $current[0] === 'variable' ? $current[1] : $current[1][1];
            $text = str_repeat('-', count($names));
            $text[array_search($name, $names, true)] = $current[0] === 'variable' ? '1' : '0';
            $result = [$text];
        } elseif ($current[0] === 'constant') {
            $result = $current[1] === 1 ? [] : [str_repeat('-', count($names))];
        } else {
            $left = $visit($current[1]);
            $right = $visit($current[2]);
            if ($current[0] === '&') {
                $result = tidy(array_merge($left, $right));
            } else {
                $result = [];
                foreach ($left as $a) {
                    foreach ($right as $b) {
                        $merged = mergeClause($a, $b);
                        if ($merged !== null) {
                            $result[] = $merged;
                        }
                    }
                }
                $result = tidy($result);
            }
        }
        if ($key !== null) {
            $memo[$key] = $result;
        }
        return $result;
    };
    return $visit($node);
}

function assignments(array $names, int $row): array
{
    $result = [];
    foreach ($names as $i => $name) {
        $result[$name] = ($row >> (count($names) - 1 - $i)) & 1;
    }
    return $result;
}

function assignmentText(array $names, int $row): string
{
    $parts = [];
    foreach (assignments($names, $row) as $name => $value) {
        $parts[] = $name . '=' . $value;
    }
    return '{' . implode(' ', $parts) . '}';
}

class Workbench
{
    private const COMMANDS = ['DEF', 'DEFSUM', 'DEL', 'LIST', 'PRINT', 'TABLE', 'MINTERMS', 'MAXTERMS', 'DNF', 'CNF', 'NNF', 'DUAL', 'ANF', 'SIMPLIFY', 'RESTRICT', 'COFACTOR', 'MINIMIZE', 'MINDC', 'MINPOS', 'KMAP', 'SAT', 'TAUT', 'COUNT', 'EQUIV', 'IMPLIES', 'PROPS', 'BDD', 'CLAUSES', 'DP'];
    private const SPLIT = ['RESTRICT', 'COFACTOR', 'MINDC', 'EQUIV', 'IMPLIES'];
    private const TABLE = ['TABLE', 'MINTERMS', 'MAXTERMS', 'DNF', 'CNF', 'ANF', 'SAT', 'TAUT', 'COUNT', 'EQUIV', 'IMPLIES', 'PROPS', 'KMAP', 'BDD', 'MINIMIZE', 'MINDC', 'MINPOS'];
    private array $definitions = [];

    private function validName(string $name): bool
    {
        return (bool)preg_match('/\A[a-z][a-z0-9]{0,7}\z/', $name);
    }

    private function parse(string $text, int $start): array
    {
        return (new FormulaParser($text, $start, $this->definitions))->parse();
    }

    private function words(string $text): array
    {
        return preg_split('/ +/', $text, -1, PREG_SPLIT_NO_EMPTY);
    }

    private function define(string $name, array $formula): array
    {
        $line = (isset($this->definitions[$name]) ? 'redefined ' : 'defined ') . $name . ' = ' . notation($formula);
        $this->definitions[$name] = $formula;
        return [$line];
    }

    private function bdd(array $values, array $names): array
    {
        $nodes = [];
        $unique = [];
        $build = function (int $i, array $table) use (&$build, &$nodes, &$unique, $names): int {
            if ($i === count($names)) {
                return $table[0];
            }
            $half = intdiv(count($table), 2);
            $low = $build($i + 1, array_slice($table, 0, $half));
            $high = $build($i + 1, array_slice($table, $half));
            if ($low === $high) {
                return $low;
            }
            $key = $i . ',' . $low . ',' . $high;
            if (!isset($unique[$key])) {
                $unique[$key] = count($nodes) + 2;
                $nodes[] = [$i, $low, $high];
            }
            return $unique[$key];
        };
        $root = $build(0, $values);
        $counts = [0 => 0, 1 => 1];
        $paths = function (int $id) use (&$paths, &$counts, $nodes): int {
            if (!isset($counts[$id])) {
                $counts[$id] = $paths($nodes[$id - 2][1]) + $paths($nodes[$id - 2][2]);
            }
            return $counts[$id];
        };
        $lines = ['nodes: ' . count($nodes)];
        foreach ($nodes as $j => [$i, $low, $high]) {
            $lines[] = ($j + 2) . ' = ite(' . $names[$i] . ', ' . $high . ', ' . $low . ')';
        }
        return array_merge($lines, ['root: ' . $root, 'paths: ' . $paths($root)]);
    }

    public function command(string $line): array
    {
        $separator = strpos($line, ' ');
        $command = $separator === false ? $line : substr($line, 0, $separator);
        $argument = $separator === false ? '' : substr($line, $separator + 1);
        if (!in_array($command, self::COMMANDS, true)) {
            throw new LogicError('unknown command ' . $command);
        }
        if ($command === 'LIST' && $separator !== false) {
            throw new LogicError('unexpected argument');
        }
        if ($command !== 'LIST' && $separator === false) {
            throw new LogicError('missing argument');
        }
        if ($command === 'LIST') {
            $names = array_keys($this->definitions);
            sort($names, SORT_STRING);
            return array_merge(['names: ' . count($names)], array_map(fn($name) => $name . ' = ' . notation($this->definitions[$name]), $names));
        }
        if ($command === 'DEF') {
            $split = strpos($argument, ' ');
            if ($split === false) {
                throw new LogicError('missing argument');
            }
            $name = substr($argument, 0, $split);
            if (!$this->validName($name)) {
                throw new LogicError("invalid name '" . $name . "'");
            }
            return $this->define($name, $this->parse(substr($argument, $split + 1), strlen($name) + 6));
        }
        if ($command === 'DEL') {
            if (!$this->validName($argument)) {
                throw new LogicError("invalid name '" . $argument . "'");
            }
            if (!isset($this->definitions[$argument])) {
                throw new LogicError("undefined name '" . $argument . "'");
            }
            unset($this->definitions[$argument]);
            return ['deleted ' . $argument];
        }
        if ($command === 'DEFSUM') {
            $split = strpos($argument, ';');
            if ($split === false) {
                throw new LogicError("missing ';'");
            }
            $words = $this->words(substr($argument, 0, $split));
            if ($words === []) {
                throw new LogicError('missing argument');
            }
            $name = array_shift($words);
            if (!$this->validName($name)) {
                throw new LogicError("invalid name '" . $name . "'");
            }
            $previous = '';
            if ($words === []) {
                throw new LogicError('bad variable list');
            }
            foreach ($words as $word) {
                if (!preg_match('/\A[A-Z]\z/', $word) || strcmp($previous, $word) >= 0) {
                    throw new LogicError('bad variable list');
                }
                $previous = $word;
            }
            if (count($words) >= 9) {
                throw new LogicError('too many variables: ' . count($words));
            }
            $rows = [];
            $previous = -1;
            foreach ($this->words(substr($argument, $split + 1)) as $word) {
                if (!preg_match('/\A(?:0|[1-9][0-9]*)\z/', $word) || (int)$word >= (1 << count($words)) || (int)$word <= $previous) {
                    throw new LogicError("bad minterm '" . $word . "'");
                }
                $rows[] = $previous = (int)$word;
            }
            $terms = [];
            foreach ($rows as $row) {
                $text = pattern($row, count($words));
                $term = null;
                foreach ($words as $i => $variable) {
                    $literal = $text[$i] === '1' ? boolVar($variable) : boolNot(boolVar($variable));
                    $term = $term === null ? $literal : boolBinary('&', $term, $literal);
                }
                $terms[] = $term;
            }
            $formula = null;
            foreach ($terms as $term) {
                $formula = $formula === null ? $term : boolBinary('|', $formula, $term);
            }
            return $this->define($name, $formula ?? boolConst(0));
        }
        $front = $argument;
        $second = null;
        $secondStart = null;
        if (in_array($command, self::SPLIT, true)) {
            $split = strpos($argument, ';');
            if ($split === false) {
                throw new LogicError("missing ';'");
            }
            $front = substr($argument, 0, $split);
            $second = substr($argument, $split + 1);
            $secondStart = strlen($command) + $split + 3;
        }
        $formula = $this->parse($front, strlen($command) + 2);
        if ($command === 'RESTRICT') {
            $words = $this->words($second);
            if ($words === []) {
                throw new LogicError('missing assignment');
            }
            $assignments = [];
            foreach ($words as $word) {
                if (!preg_match('/\A[A-Z]=[01]\z/', $word)) {
                    throw new LogicError("bad assignment '" . $word . "'");
                }
                if (isset($assignments[$word[0]])) {
                    throw new LogicError('duplicate variable ' . $word[0]);
                }
                $assignments[$word[0]] = (int)$word[2];
            }
            return ['restricted: ' . notation(simplify($formula, $assignments))];
        }
        if ($command === 'COFACTOR') {
            $words = $this->words($second);
            if (count($words) !== 1 || !preg_match('/\A[A-Z]\z/', $words[0])) {
                throw new LogicError('bad variable');
            }
            $name = $words[0];
            $high = simplify($formula, [$name => 1]);
            $low = simplify($formula, [$name => 0]);
            return ['cofactor ' . $name . '=1: ' . notation($high), 'cofactor ' . $name . '=0: ' . notation($low), 'difference: ' . notation(simplifyBinary('^', $high, $low))];
        }
        $other = $second === null ? null : $this->parse($second, $secondStart);
        $names = array_values(array_unique(array_merge(variableNames($formula), $other === null ? [] : variableNames($other))));
        sort($names, SORT_STRING);
        if (in_array($command, self::TABLE, true) && count($names) >= 9) {
            throw new LogicError('too many variables: ' . count($names));
        }
        if ($command === 'PRINT') {
            [$size, $depth] = measures($formula);
            return ['formula: ' . notation($formula), 'variables: ' . ($names === [] ? 'none' : implode(' ', $names)), 'size ' . $size . ' depth ' . $depth];
        }
        if ($command === 'NNF') {
            return ['nnf: ' . notation(nnf($formula))];
        }
        if ($command === 'DUAL') {
            return ['dual: ' . notation(dual($formula))];
        }
        if ($command === 'SIMPLIFY') {
            return ['simplified: ' . notation(simplify($formula))];
        }
        if ($command === 'CLAUSES' || $command === 'DP') {
            $set = clauses(nnf($formula), $names);
            if ($command === 'CLAUSES') {
                return ['clauses: ' . coverText($set, $names, false)];
            }
            $lines = ['start: clauses ' . count($set)];
            $empty = str_repeat('-', count($names));
            foreach ($names as $i => $name) {
                if ($set === [] || in_array($empty, $set, true)) {
                    break;
                }
                $positive = array_filter($set, fn($text) => $text[$i] === '1');
                $negative = array_filter($set, fn($text) => $text[$i] === '0');
                $resolvents = [];
                foreach ($positive as $a) {
                    foreach ($negative as $b) {
                        $a[$i] = $b[$i] = '-';
                        $merged = mergeClause($a, $b);
                        if ($merged !== null) {
                            $resolvents[$merged] = true;
                        }
                    }
                }
                $fresh = array_map('strval', array_keys($resolvents));
                $set = tidy(array_merge(array_values(array_filter($set, fn($text) => $text[$i] === '-')), $fresh));
                $lines[] = 'eliminate ' . $name . ': resolvents ' . count($resolvents) . ' clauses ' . count($set);
            }
            return array_merge($lines, [in_array($empty, $set, true) ? 'result: unsatisfiable' : 'result: satisfiable']);
        }
        $values = [];
        $otherValues = [];
        for ($row = 0; $row < (1 << count($names)); $row++) {
            $assignment = assignments($names, $row);
            $values[] = evaluate($formula, $assignment);
            if ($other !== null) {
                $otherValues[] = evaluate($other, $assignment);
            }
        }
        $on = $off = [];
        foreach ($values as $row => $value) {
            if ($value === 1) {
                $on[] = $row;
            } else {
                $off[] = $row;
            }
        }
        switch ($command) {
            case 'TABLE':
                $lines = [implode(' ', array_merge($names, ['|', 'F']))];
                foreach ($values as $row => $value) {
                    $lines[] = implode(' ', array_merge(str_split(pattern($row, count($names))), ['|', (string)$value]));
                }
                return $lines;
            case 'MINTERMS':
            case 'MAXTERMS':
                $rows = $command === 'MINTERMS' ? $on : $off;
                return [strtolower($command) . ': ' . ($rows === [] ? 'none' : implode(' ', $rows))];
            case 'DNF':
            case 'CNF':
                $texts = array_map(fn($row) => pattern($row, count($names)), $command === 'DNF' ? $on : $off);
                if ($command === 'CNF') {
                    $texts = array_map('complementPattern', $texts);
                }
                return [strtolower($command) . ': ' . coverText($texts, $names, $command === 'DNF')];
            case 'ANF':
                $texts = [];
                foreach (coefficients($values, count($names)) as $row => $value) {
                    if ($value === 1) {
                        $texts[] = strtr(pattern($row, count($names)), '0', '-');
                    }
                }
                usort($texts, fn($a, $b) => (literalCount($a) <=> literalCount($b)) ?: strcmp(patternKey($a), patternKey($b)));
                return ['anf: ' . ($texts === [] ? '0' : implode(' ^ ', array_map(fn($text) => patternPart($text, $names), $texts)))];
            case 'SAT':
                return [$on === [] ? 'unsatisfiable' : 'satisfiable: ' . assignmentText($names, $on[0])];
            case 'TAUT':
                return [$off === [] ? 'tautology' : 'not a tautology: ' . assignmentText($names, $off[0])];
            case 'COUNT':
                return ['models: ' . count($on) . ' of ' . count($values)];
            case 'EQUIV':
                foreach ($values as $row => $value) {
                    if ($value !== $otherValues[$row]) {
                        return ['not equivalent: ' . assignmentText($names, $row) . ' f=' . $value . ' g=' . $otherValues[$row]];
                    }
                }
                return ['equivalent'];
            case 'IMPLIES':
                foreach ($values as $row => $value) {
                    if ($value === 1 && $otherValues[$row] === 0) {
                        return ['does not imply: ' . assignmentText($names, $row)];
                    }
                }
                return ['implies'];
            case 'PROPS':
                $depends = [];
                foreach ($names as $i => $name) {
                    $bit = 1 << (count($names) - 1 - $i);
                    foreach ($values as $row => $value) {
                        if ($value !== $values[$row ^ $bit]) {
                            $depends[] = $name;
                            break;
                        }
                    }
                }
                $monotone = $selfDual = $symmetric = true;
                $weights = [];
                foreach ($values as $row => $value) {
                    if ($value === $values[count($values) - 1 - $row]) {
                        $selfDual = false;
                    }
                    foreach ($names as $i => $name) {
                        $bit = 1 << $i;
                        if (($row & $bit) === 0 && $value > $values[$row | $bit]) {
                            $monotone = false;
                        }
                    }
                    $weight = substr_count(decbin($row), '1');
                    if (isset($weights[$weight]) && $weights[$weight] !== $value) {
                        $symmetric = false;
                    }
                    $weights[$weight] = $value;
                }
                $linear = true;
                foreach (coefficients($values, count($names)) as $row => $value) {
                    if ($value === 1 && substr_count(decbin($row), '1') > 1) {
                        $linear = false;
                    }
                }
                $lines = ['depends: ' . ($depends === [] ? 'none' : implode(' ', $depends))];
                foreach (['zero-preserving' => $values[0] === 0, 'one-preserving' => $values[array_key_last($values)] === 1, 'self-dual' => $selfDual, 'monotone' => $monotone, 'linear' => $linear, 'symmetric' => $symmetric] as $label => $value) {
                    $lines[] = $label . ': ' . ($value ? 'yes' : 'no');
                }
                return $lines;
            case 'KMAP':
                if (count($names) < 2 || count($names) > 4) {
                    throw new LogicError('kmap needs 2 to 4 variables');
                }
                $p = intdiv(count($names), 2);
                $q = count($names) - $p;
                $rows = $columns = [];
                for ($i = 0; $i < (1 << $p); $i++) {
                    $rows[] = pattern($i ^ intdiv($i, 2), $p);
                }
                for ($i = 0; $i < (1 << $q); $i++) {
                    $columns[] = pattern($i ^ intdiv($i, 2), $q);
                }
                $lines = [implode('', array_slice($names, 0, $p)) . '\\' . implode('', array_slice($names, $p)) . ' ' . implode(' ', $columns)];
                foreach ($rows as $row) {
                    $text = str_pad($row, count($names) + 1);
                    foreach ($columns as $column) {
                        $text .= str_repeat(' ', $q) . $values[bindec($row . $column)];
                    }
                    $lines[] = $text;
                }
                return $lines;
            case 'BDD':
                return $this->bdd($values, $names);
            case 'MINIMIZE':
                return minimize($on, [], $names);
            case 'MINDC':
                $dc = [];
                foreach ($otherValues as $row => $value) {
                    if ($value === 1) {
                        $dc[] = $row;
                    }
                }
                return minimize(array_values(array_diff($on, $dc)), $dc, $names);
            case 'MINPOS':
                return minimize($off, [], $names, true);
        }
        return [];
    }

    public function run(): void
    {
        $count = (int)trim(fgets(STDIN));
        for ($i = 0; $i < $count; $i++) {
            $input = fgets(STDIN);
            $line = str_ends_with($input, "\n") ? substr($input, 0, -1) : $input;
            try {
                foreach ($this->command($line) as $text) {
                    echo $text, "\n";
                }
            } catch (LogicError $error) {
                echo 'error: ', $error->getMessage(), "\n";
            }
        }
    }
}

(new Workbench())->run();
