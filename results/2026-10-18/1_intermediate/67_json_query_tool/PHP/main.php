<?php
class JsonValue
{
    public function __construct(public string $kind = 'null', public mixed $data = null) {
    }
}
class ParseFault extends Exception
{
    public function __construct(string $message, public int $position) {
        parent::__construct($message);
    }
}
function quoted(string $text, string $quote = '"'): string
{
    $output = $quote;
    $escapes = [8 => '\\b', 12 => '\\f', 10 => '\\n', 13 => '\\r', 9 => '\\t'];
    foreach (str_split($text) as $char) {
        $code = ord($char);
        if ($char === $quote || $char === '\\') $output .= '\\' . $char;
        elseif (isset($escapes[$code])) $output .= $escapes[$code];
        elseif ($code < 32 || $code === 127) $output .= sprintf('\\u%04x', $code);
        else $output .= $char;
    }
    return $output . $quote;
}
function member(JsonValue $value, string $key): int
{
    if ($value->kind === 'object') foreach ($value->data as $index => $pair) if ($pair[0] === $key) return $index;
    return -1;
}
function compact_json(JsonValue $value): string
{
    return match ($value->kind) {
        'null' => 'null', 'number' => (string)$value->data, 'boolean' => $value->data ? 'true' : 'false', 'string' => quoted($value->data),
        'array' => '[' . implode(',', array_map('compact_json', $value->data)) . ']',
        'object' => '{' . implode(',', array_map(fn($pair) => quoted($pair[0]) . ':' . compact_json($pair[1]), $value->data)) . '}'
    };
}
function pretty(JsonValue $value, string $indent = ''): string
{
    if (!in_array($value->kind, ['object', 'array'], true) || $value->data === []) return compact_json($value);
    $next = $indent . '  ';
    $items = $value->kind === 'object' ? array_map(fn($pair) => $next . quoted($pair[0]) . ': ' . pretty($pair[1], $next), $value->data)
    : array_map(fn($item) => $next . pretty($item, $next), $value->data);
    return ($value->kind === 'object' ? '{' : '[') . "\n" . implode(",\n", $items) . "\n" . $indent . ($value->kind === 'object' ? '}' : ']');
}
class StrictJson
{
    private int $position = 0;
    public function __construct(private string $text) {
    }
    private function char(): string {
        return $this->text[$this->position] ?? '';
    }
    private function fail(string $reason, ?int $position = null): never {
        throw new ParseFault($reason, $position ?? $this->position);
    }
    private function whitespace(): void {
        while (in_array($this->char(), [' ', "\n"], true)) $this->position++;
    }
    private function string(): string
    {
        $this->position++;
        $output = '';
        while (true) {
            $char = $this->char();
            if ($char === '' || $char === "\n") $this->fail('unterminated string');
            if ($char === '"') {
                $this->position++;
                return $output;
            }
            if ($char === '\\') {
                $start = $this->position;
                $escaped = $this->text[$start + 1] ?? '';
                if ($escaped === '' || $escaped === "\n") $this->fail('unterminated string', $start + 1);
                if ($escaped === 'u') {
                    $hex = substr($this->text, $start + 2, 4);
                    if (!preg_match('/\A[0-9A-Fa-f]{4}\z/', $hex)) $this->fail('bad unicode escape', $start);
                    if (hexdec($hex) > 127) $this->fail('non-ascii escape', $start);
                    $output .= chr(hexdec($hex));
                    $this->position += 6;
                }
                else {
                    $escapes = ['"' => '"', '\\' => '\\', '/' => '/', 'b' => "\x08", 'f' => "\x0c", 'n' => "\n", 'r' => "\r", 't' => "\t"];
                    if (!isset($escapes[$escaped])) $this->fail("invalid escape '\\$escaped'", $start);
                    $output .= $escapes[$escaped];
                    $this->position += 2;
                }
            }
            else {
                $output .= $char;
                $this->position++;
            }
        }
    }
    private function value(): JsonValue
    {
        $this->whitespace();
        $char = $this->char();
        if ($char === '') $this->fail('unexpected end of input');
        if ($char === '{' || $char === '[') {
            $object = $char === '{';
            $ending = $object ? '}' : ']';
            $result = new JsonValue($object ? 'object' : 'array', []);
            $this->position++;
            $this->whitespace();
            if ($this->char() === $ending) {
                $this->position++;
                return $result;
            }
            while (true) {
                if ($object) {
                    $this->whitespace();
                    if ($this->char() === '') $this->fail('unexpected end of input');
                    if ($this->char() !== '"') $this->fail('expected key');
                    $start = $this->position;
                    $key = $this->string();
                    if (member($result, $key) >= 0) $this->fail('duplicate key ' . quoted($key), $start);
                    $this->whitespace();
                    if ($this->char() === '') $this->fail('unexpected end of input');
                    if ($this->char() !== ':') $this->fail("expected ':'");
                    $this->position++;
                    $result->data[] = [$key, $this->value()];
                }
                else $result->data[] = $this->value();
                $this->whitespace();
                if ($this->char() === $ending) {
                    $this->position++;
                    return $result;
                }
                if ($this->char() === '') $this->fail('unexpected end of input');
                if ($this->char() !== ',') $this->fail("expected ',' or '$ending'");
                $this->position++;
                $this->whitespace();
                if ($this->char() === $ending) $this->fail('trailing comma');
            }
        }
        if ($char === '"') return new JsonValue('string', $this->string());
        if ($char === '-' || ctype_digit($char)) {
            $start = $this->position;
            if ($char === '-') $this->position++;
            $digitsStart = $this->position;
            while ($this->char() !== '' && ctype_digit($this->char())) $this->position++;
            $digits = substr($this->text, $digitsStart, $this->position - $digitsStart);
            if ($digits === '') $this->fail('invalid number', $start);
            if (strlen($digits) > 1 && $digits[0] === '0') $this->fail('leading zero', $digitsStart);
            if ($this->char() === '.') $this->fail('fraction not allowed');
            if (in_array($this->char(), ['e', 'E'], true)) $this->fail('exponent not allowed');
            if (strlen($digits) >= 10) $this->fail('number out of range', $start);
            return new JsonValue('number', (int)substr($this->text, $start, $this->position - $start));
        }
        if (preg_match('/[A-Za-z]/', $char)) {
            $start = $this->position;
            while ($this->char() !== '' && preg_match('/[A-Za-z]/', $this->char())) $this->position++;
            $word = substr($this->text, $start, $this->position - $start);
            if (!in_array($word, ['true', 'false', 'null'], true)) $this->fail("invalid literal '$word'", $start);
            return $word === 'null' ? new JsonValue() : new JsonValue('boolean', $word === 'true');
        }
        $this->fail("unexpected character '$char'");
    }
    public function read(): JsonValue
    {
        $result = $this->value();
        $this->whitespace();
        if ($this->position < strlen($this->text)) $this->fail('trailing characters');
        return $result;
    }
}
class JsonTool
{
    private JsonValue $document;
    private array $history = [];
    private const INTEGER = '/\A(?:0|-?[1-9][0-9]{0,8})\z/';
    private const IDENTIFIER = '/\A[A-Za-z_][A-Za-z0-9_]*\z/';
    public function __construct() {
        $this->document = new JsonValue();
    }
    private function copy(JsonValue $value): JsonValue {
        return unserialize(serialize($value));
    }
    private function fail(string $message): never {
        throw new RuntimeException($message);
    }
    private function quotedKey(string $text, int &$position): string
    {
        if (($text[$position] ?? '') !== "'") $this->fail('bad');
        $position++;
        $output = '';
        while ($position < strlen($text)) {
            $char = $text[$position];
            if ($char === "'") {
                $position++;
                return $output;
            }
            if ($char === '\\') {
                $escaped = $text[$position + 1] ?? '';
                if ($escaped === 'u') {
                    $hex = substr($text, $position + 2, 4);
                    if (!preg_match('/\A[0-9A-Fa-f]{4}\z/', $hex) || hexdec($hex) > 127) $this->fail('bad');
                    $output .= chr(hexdec($hex));
                    $position += 6;
                }
                else {
                    $escapes = ["'" => "'", '\\' => '\\', '/' => '/', 'b' => "\x08", 'f' => "\x0c", 'n' => "\n", 'r' => "\r", 't' => "\t"];
                    if (!isset($escapes[$escaped])) $this->fail('bad');
                    $output .= $escapes[$escaped];
                    $position += 2;
                }
            }
            else {
                $output .= $char;
                $position++;
            }
        }
        $this->fail('bad');
    }
    private function path(string $text, bool $field = false): array
    {
        try {
            if (($text[0] ?? '') !== ($field ? '@' : '$')) $this->fail('bad');
            $position = 1;
            $selectors = [];
            while ($position < strlen($text)) {
                $descendant = false;
                if (!$field && substr($text, $position, 2) === '..') {
                    $descendant = true;
                    $position += 2;
                }
                elseif ($text[$position] === '.') {
                    $position++;
                    if (!preg_match('/\A(?:[A-Za-z_][A-Za-z0-9_]*|\*)/', substr($text, $position), $match) || ($field && $match[0] === '*')) $this->fail('bad');
                    $selectors[] = [false, $match[0] === '*' ? 'all' : 'key', $match[0]];
                    $position += strlen($match[0]);
                    continue;
                }
                elseif ($text[$position] !== '[') $this->fail('bad');
                if (($text[$position] ?? '') === '[') {
                    $position++;
                    if (($text[$position] ?? '') === "'") {
                        $key = $this->quotedKey($text, $position);
                        $kind = 'key';
                    }
                    else {
                        $finish = strpos($text, ']', $position);
                        if ($finish === false) $this->fail('bad');
                        $word = substr($text, $position, $finish - $position);
                        $position = $finish;
                        if (preg_match(self::INTEGER, $word)) {
                            $kind = 'index';
                            $key = (int)$word;
                        }
                        elseif (!$field && $word === '*') {
                            $kind = 'all';
                            $key = null;
                        }
                        elseif (!$field && substr_count($word, ':') === 1) {
                            $bounds = explode(':', $word);
                            foreach ($bounds as $bound) if ($bound !== '' && !preg_match(self::INTEGER, $bound)) $this->fail('bad');
                            $kind = 'slice';
                            $key = array_map(fn($bound) => $bound === '' ? null : (int)$bound, $bounds);
                        }
                        else $this->fail('bad');
                    }
                    if (($text[$position] ?? '') !== ']') $this->fail('bad');
                    $position++;
                }
                elseif ($descendant) {
                    if (!preg_match('/\A(?:[A-Za-z_][A-Za-z0-9_]*|\*)/', substr($text, $position), $match)) $this->fail('bad');
                    $key = $match[0];
                    $kind = $key === '*' ? 'all' : 'key';
                    $position += strlen($key);
                }
                else $this->fail('bad');
                $selectors[] = [$descendant, $kind, $key];
            }
            return $selectors;
        }
        catch (RuntimeException $error) {
            $this->fail($field ? 'ERROR bad field' : 'ERROR bad path');
        }
    }
    private function location(array $steps): string
    {
        $output = '$';
        foreach ($steps as $step) $output .= is_int($step) ? "[$step]" : (preg_match(self::IDENTIFIER, $step) ? '.' . $step : '[' . quoted($step, "'") . ']');
        return $output;
    }
    private function children(array $match): array
    {
        [$value, $steps, $positions] = $match;
        $output = [];
        if ($value->kind === 'object') foreach ($value->data as $i => [$key, $child]) $output[] = [$child, [...$steps, $key], [...$positions, $i]];
        elseif ($value->kind === 'array') foreach ($value->data as $i => $child) $output[] = [$child, [...$steps, $i], [...$positions, $i]];
        return $output;
    }
    private function preorder(array $match): array
    {
        $output = [$match];
        foreach ($this->children($match) as $child) array_push($output, ...$this->preorder($child));
        return $output;
    }
    private function select(array $match, array $selector): array
    {
        [, $kind, $key] = $selector;
        $value = $match[0];
        $all = $this->children($match);
        if ($kind === 'all') return $all;
        if ($kind === 'key') return $value->kind === 'object' ? array_values(array_filter($all, fn($item) => $item[1][array_key_last($item[1])] === $key)) : [];
        if ($value->kind !== 'array') return [];
        $n = count($value->data);
        if ($kind === 'index') {
            $index = $key < 0 ? $n + $key : $key;
            return $index >= 0 && $index < $n ? [$all[$index]] : [];
        }
        $bounds = [$key[0] ?? 0, $key[1] ?? $n];
        $bounds = array_map(fn($bound) => min($n, max(0, $bound < 0 ? $n + $bound : $bound)), $bounds);
        return $bounds[0] < $bounds[1] ? array_slice($all, $bounds[0], $bounds[1] - $bounds[0]) : [];
    }
    private function evaluate(array $selectors, ?array $initial = null): array
    {
        $matches = $initial ?? [[$this->document, [], []]];
        foreach ($selectors as $selector) {
            $next = [];
            foreach ($matches as $match) foreach ($selector[0] ? $this->preorder($match) : [$match] as $item) array_push($next, ...$this->select($item, $selector));
            $matches = $next;
        }
        return $matches;
    }
    private function field(JsonValue $value, array $selectors): ?JsonValue
    {
        $result = $this->evaluate($selectors, [[$value, [], []]]);
        return $result === [] ? null : $result[0][0];
    }
    private function at(array $steps): JsonValue
    {
        $value = $this->document;
        foreach ($steps as $step) $value = is_int($step) ? $value->data[$step] : $value->data[member($value, $step)][1];
        return $value;
    }
    private function assign(array $steps, JsonValue $value): void
    {
        if ($steps === []) {
            $this->document = $value;
            return;
        }
        $last = array_pop($steps);
        $parent = $this->at($steps);
        if (is_int($last)) $parent->data[$last] = $value;
        else {
            $index = member($parent, $last);
            if ($index < 0) $parent->data[] = [$last, $value];
            else $parent->data[$index][1] = $value;
        }
    }
    private function merge(JsonValue $target, JsonValue $source): void
    {
        foreach ($source->data as [$key, $child]) {
            $index = member($target, $key);
            if ($index >= 0 && $target->data[$index][1]->kind === 'object' && $child->kind === 'object') $this->merge($target->data[$index][1], $child);
            elseif ($index >= 0) $target->data[$index][1] = $this->copy($child);
            else $target->data[] = [$key, $this->copy($child)];
        }
    }
    private function equal(?JsonValue $left, JsonValue $right): bool
    {
        if ($left === null || $left->kind !== $right->kind) return false;
        if ($left->kind === 'object') {
            if (count($left->data) !== count($right->data)) return false;
            foreach ($left->data as [$key, $item]) {
                $index = member($right, $key);
                if ($index < 0 || !$this->equal($item, $right->data[$index][1])) return false;
            }
            return true;
        }
        if ($left->kind === 'array') {
            if (count($left->data) !== count($right->data)) return false;
            foreach ($left->data as $index => $item) if (!$this->equal($item, $right->data[$index])) return false;
            return true;
        }
        return $left->data === $right->data;
    }
    private function checkKinds(array $matches, array $kinds, string $reason): void
    {
        foreach ($matches as $match) if (!in_array($match[0]->kind, $kinds, true)) $this->fail('ERROR ' . $reason . ' at ' . $this->location($match[1]));
    }
    private function parse(string $text): JsonValue
    {
        try {
            return (new StrictJson($text))->read();
        }
        catch (ParseFault $error) {
            $this->fail('PARSE ERROR col ' . ($error->position + 1) . ': ' . $error->getMessage());
        }
    }
    private function comparePositions(array $left, array $right): int
    {
        for ($i = 0; $i < min(count($left), count($right)); $i++) if ($left[$i] !== $right[$i]) return $left[$i] <=> $right[$i];
        return count($left) <=> count($right);
    }
    public function command(string $line): void
    {
        [$command, $argument] = array_pad(explode(' ', $line, 2), 2, null);
        try {
            $names = ['GET', 'COMPACT', 'PRETTY', 'TYPE', 'LENGTH', 'KEYS', 'FLATTEN', 'COUNT', 'SUM', 'MIN', 'MAX', 'AVG', 'FILTER', 'SET', 'DELETE', 'INSERT', 'MERGE', 'SORT', 'RENAME', 'UNDO'];
            if (!in_array($command, $names, true)) $this->fail("ERROR unknown command '$command'");
            $limit = ['SET' => 2, 'MERGE' => 2, 'INSERT' => 3, 'FILTER' => 4][$command] ?? PHP_INT_MAX;
            $args = $argument === null ? [] : explode(' ', $argument, $limit);
            $count = count($args);
            $shape = match ($command) {
                'SET', 'MERGE' => $count === 2, 'INSERT' => $count === 3,
                'FILTER' => $count >= 3 && ($args[2] === 'EXISTS' ? $count === 3 : $count === 4),
                'SORT' => $count >= 1 && $count <= 3 && ($count < 3 || ($args[1] !== 'DESC' && $args[2] === 'DESC')),
                'COMPACT', 'PRETTY', 'FLATTEN' => $count <= 1, 'UNDO' => $count === 0, 'RENAME' => $count === 2, default => $count === 1
            };
            if (!$shape) $this->fail('ERROR bad arguments');
            if ($command === 'UNDO') {
                if ($this->history === []) $this->fail('ERROR nothing to undo');
                $this->document = array_pop($this->history);
                echo 'UNDO ' . count($this->history) . "\n";
                return;
            }
            $selectors = $this->path($args[0] ?? '$');
            $field = [];
            if ($command === 'FILTER') {
                $field = $this->path($args[1], true);
                if (!in_array($args[2], ['==', '!=', '<', '<=', '>', '>=', 'EXISTS'], true)) $this->fail('ERROR bad operator');
            }
            elseif ($command === 'SORT') $field = $this->path($count >= 2 && $args[1] !== 'DESC' ? $args[1] : '@', true);
            elseif ($command === 'INSERT' && !preg_match(self::INTEGER, $args[1])) $this->fail('ERROR bad index');
            elseif ($command === 'RENAME') {
                try {
                    if (preg_match(self::IDENTIFIER, $args[1])) $newKey = $args[1];
                    else {
                        $position = 0;
                        $newKey = $this->quotedKey($args[1], $position);
                        if ($position !== strlen($args[1])) $this->fail('bad');
                    }
                }
                catch (RuntimeException $error) {
                    $this->fail('ERROR bad key');
                }
            }
            elseif ($command === 'DELETE' && $selectors === []) $this->fail('ERROR cannot delete root');
            $replacement = new JsonValue();
            if (in_array($command, ['SET', 'MERGE', 'INSERT'], true) || ($command === 'FILTER' && $args[2] !== 'EXISTS')) $replacement = $this->parse($args[$count - 1]);
            if ($command === 'MERGE' && $replacement->kind !== 'object') $this->fail('ERROR merge value is not an object');
            $matches = $this->evaluate($selectors);
            if ($command === 'LENGTH') $this->checkKinds($matches, ['object', 'array', 'string'], 'no length');
            if (in_array($command, ['KEYS', 'MERGE'], true)) $this->checkKinds($matches, ['object'], 'not an object');
            if (in_array($command, ['FILTER', 'INSERT', 'SORT'], true)) $this->checkKinds($matches, ['array'], 'not an array');
            if ($command === 'RENAME') foreach ($matches as $match) if ($match[1] === [] || !is_string($match[1][array_key_last($match[1])])) $this->fail('ERROR not a member at ' . $this->location($match[1]));
            if ($command === 'INSERT') {
                $index = (int)$args[1];
                foreach ($matches as $match) if ($index < -count($match[0]->data) - 1 || $index > count($match[0]->data)) $this->fail('ERROR index out of range at ' . $this->location($match[1]));
            }
            if (in_array($command, ['SET', 'DELETE', 'INSERT', 'MERGE', 'SORT', 'RENAME'], true)) {
                if ($command === 'SET' && $selectors !== [] && !$selectors[array_key_last($selectors)][0] && $selectors[array_key_last($selectors)][1] === 'key') {
                    $key = $selectors[array_key_last($selectors)][2];
                    $matches = [];
                    foreach ($this->evaluate(array_slice($selectors, 0, -1)) as $parent) {
                        if ($parent[0]->kind !== 'object') continue;
                        $position = member($parent[0], $key);
                        $matches[] = [null, [...$parent[1], $key], [...$parent[2], $position < 0 ? count($parent[0]->data) : $position]];
                    }
                }
                $targets = [];
                $seen = [];
                foreach ($matches as $match) {
                    $key = serialize($match[1]);
                    if (!isset($seen[$key])) $targets[] = $match;
                    $seen[$key] = true;
                }
                usort($targets, fn($a, $b) => $this->comparePositions($b[2], $a[2]));
                $original = $this->copy($this->document);
                try {
                    foreach ($targets as [, $steps]) {
                        $value = $command === 'SET' ? null : $this->at($steps);
                        switch ($command) {
                            case 'SET':
                                $this->assign($steps, $this->copy($replacement));
                                break;
                            case 'DELETE':
                                $last = array_pop($steps);
                                $parent = $this->at($steps);
                                array_splice($parent->data, is_int($last) ? $last : member($parent, $last), 1);
                                break;
                            case 'INSERT':
                                array_splice($value->data, $index < 0 ? count($value->data) + 1 + $index : $index, 0, [$this->copy($replacement)]);
                                break;
                            case 'MERGE':
                                $this->merge($value, $replacement);
                                break;
                            case 'SORT':
                                $decorated = [];
                                foreach ($value->data as $i => $item) $decorated[] = [$this->field($item, $field), $i, $item];
                                $descending = $args[$count - 1] === 'DESC';
                                usort($decorated, function ($a, $b) use ($descending) {
                                    $rank = fn($v) => $v === null ? 3 : match ($v->kind) {
                                        'null' => 0, 'number' => 1, 'string' => 2, default => 3
                                    };
                                    $ra = $rank($a[0]);
                                    $rb = $rank($b[0]);
                                    $comparison = $ra <=> $rb;
                                    if ($comparison === 0 && $ra === 1) $comparison = $a[0]->data <=> $b[0]->data;
                                    if ($comparison === 0 && $ra === 2) $comparison = strcmp($a[0]->data, $b[0]->data);
                                    if ($descending) $comparison = -$comparison;
                                    return $comparison === 0 ? $a[1] <=> $b[1] : $comparison;
                                });
                                $value->data = array_map(fn($item) => $item[2], $decorated);
                                break;
                            case 'RENAME':
                                $last = array_pop($steps);
                                $parent = $this->at($steps);
                                if ($last !== $newKey && member($parent, $newKey) >= 0) $this->fail('ERROR key exists at ' . $this->location([...$steps, $last]));
                                $parent->data[member($parent, $last)][0] = $newKey;
                                break;
                        }
                    }
                }
                catch (RuntimeException $error) {
                    $this->document = $original;
                    throw $error;
                }
                $this->history[] = $original;
                echo "$command " . count($targets) . "\n";
                return;
            }
            if (in_array($command, ['COUNT', 'SUM', 'MIN', 'MAX', 'AVG'], true)) {
                $numbers = array_map(fn($match) => $match[0]->data, array_filter($matches, fn($match) => $match[0]->kind === 'number'));
                if ($command === 'COUNT') $result = (string)count($matches);
                elseif ($command === 'SUM') $result = (string)array_sum($numbers);
                elseif ($numbers === []) $result = 'null';
                elseif ($command === 'MIN') $result = (string)min($numbers);
                elseif ($command === 'MAX') $result = (string)max($numbers);
                else {
                    $sum = array_sum($numbers);
                    $rounded = intdiv(abs($sum) * 200 + count($numbers), 2 * count($numbers));
                    $result = sprintf('%s%d.%02d', $sum < 0 && $rounded > 0 ? '-' : '', intdiv($rounded, 100), $rounded % 100);
                }
                echo "$command $result\n";
                return;
            }
            $output = [];
            foreach ($matches as $match) {
                [$value, $steps] = $match;
                $where = $this->location($steps);
                switch ($command) {
                    case 'GET':
                        $output[] = "$where = " . compact_json($value);
                        break;
                    case 'COMPACT':
                        $output[] = compact_json($value);
                        break;
                    case 'PRETTY':
                        $output[] = pretty($value);
                        break;
                    case 'TYPE':
                        $output[] = "$where $value->kind";
                        break;
                    case 'LENGTH':
                        $output[] = "$where " . ($value->kind === 'string' ? strlen($value->data) : count($value->data));
                        break;
                    case 'KEYS':
                        $output[] = "$where [" . implode(',', array_map(fn($pair) => quoted($pair[0]), $value->data)) . ']';
                        break;
                    case 'FLATTEN':
                        foreach ($this->preorder($match) as $item) if ($this->children($item) === []) $output[] = $this->location($item[1]) . ' = ' . compact_json($item[0]);
                        break;
                    case 'FILTER':
                        foreach ($this->children($match) as $item) {
                            $f = $this->field($item[0], $field);
                            $operator = $args[2];
                            $equal = $this->equal($f, $replacement);
                            $pass = false;
                            if ($operator === 'EXISTS') $pass = $f !== null;
                            elseif ($operator === '==') $pass = $equal;
                            elseif ($operator === '!=') $pass = !$equal;
                            elseif ($f !== null && $f->kind === $replacement->kind && in_array($f->kind, ['number', 'string'], true)) {
                                $comparison = $f->kind === 'string' ? strcmp($f->data, $replacement->data) : ($f->data <=> $replacement->data);
                                $pass = match ($operator) {
                                    '<' => $comparison < 0, '<=' => $comparison <= 0, '>' => $comparison > 0, '>=' => $comparison >= 0
                                };
                            }
                            if ($pass) $output[] = $this->location($item[1]) . ' = ' . compact_json($item[0]);
                        }
                        break;
                }
            }
            echo $output === [] ? "no match\n" : implode("\n", $output) . "\n";
        }
        catch (RuntimeException $error) {
            echo $error->getMessage() . "\n";
        }
    }
    private function load(array $lines): void
    {
        $text = implode("\n", $lines);
        try {
            $value = (new StrictJson($text))->read();
            $this->history[] = $this->copy($this->document);
            $this->document = $value;
            $stats = function ($item) use (&$stats) {
                $children = $item->kind === 'object' ? array_column($item->data, 1) : ($item->kind === 'array' ? $item->data : []);
                $count = 1;
                $depth = 1;
                foreach ($children as $child) {
                    [$n, $d] = $stats($child);
                    $count += $n;
                    $depth = max($depth, $d + 1);
                }
                return [$count, $depth];
            };
            [$count, $depth] = $stats($value);
            echo "LOADED nodes=$count depth=$depth\n";
        }
        catch (ParseFault $error) {
            $prefix = substr($text, 0, $error->position);
            $line = substr_count($prefix, "\n") + 1;
            $last = strrpos($prefix, "\n");
            $column = $error->position - ($last === false ? -1 : $last);
            echo "PARSE ERROR line $line col $column: {$error->getMessage()}\n";
        }
    }
    public function run(): void
    {
        $input = [];
        while (($line = fgets(STDIN)) !== false) $input[] = rtrim($line, "\r\n");
        $position = 0;
        while (true) {
            $block = [];
            while ($input[$position] !== '%%') $block[] = $input[$position++];
            $position++;
            $this->load($block);
            while ($input[$position] !== 'LOAD' && $input[$position] !== 'END') $this->command($input[$position++]);
            if ($input[$position] === 'END') break;
            $position++;
        }
    }
}
(new JsonTool())->run();
