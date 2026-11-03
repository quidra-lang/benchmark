<?php
declare(strict_types=1);

require_once __DIR__ . '/charset.php';
require_once __DIR__ . '/formatter.php';
require_once __DIR__ . '/backtrack_vm.php';
require_once __DIR__ . '/pike_vm.php';

final class PatternError extends RuntimeException
{
    public function __construct(string $message, public int $column)
    {
        parent::__construct($message);
    }
}

function quantifier(?string $character): bool
{
    return in_array($character, ['*', '+', '?', '{'], true);
}

final class PatternParser
{
    public int $groups = 0;
    public array $names = [];
    private array $references = [];
    private int $index = 0;

    public function __construct(private string $source) {}

    private function peek(): ?string
    {
        return $this->source[$this->index] ?? null;
    }

    private function code(): ?int
    {
        return $this->peek() === null ? null : ord($this->peek());
    }

    private function fail(string $message, ?int $column = null): never
    {
        throw new PatternError($message, $column ?? $this->index + 1);
    }

    private function take(string $character): bool
    {
        if ($this->peek() !== $character) {
            return false;
        }
        ++$this->index;
        return true;
    }

    public function parse(): object
    {
        $root = $this->alternation();
        if ($this->index < strlen($this->source)) {
            $this->fail('unmatched )');
        }
        foreach ($this->references as $reference) {
            if (isset($reference->name)) {
                if (!isset($this->names[$reference->name])) {
                    $this->fail('unknown group name', $reference->column);
                }
                $reference->group = $this->names[$reference->name];
            } elseif ($reference->group > $this->groups) {
                $this->fail('invalid group reference', $reference->column);
            }
        }
        return $root;
    }

    private function alternation(): object
    {
        $elements = [$this->concatenation()];
        while ($this->take('|')) {
            $elements[] = $this->concatenation();
        }
        return count($elements) === 1 ? $elements[0] : (object)['kind' => 'alternation', 'elements' => $elements];
    }

    private function concatenation(): object
    {
        $elements = [];
        while ($this->peek() !== null && $this->peek() !== '|' && $this->peek() !== ')') {
            $elements[] = $this->quantified();
        }
        return count($elements) === 1 ? $elements[0] : (object)['kind' => 'concatenation', 'elements' => $elements];
    }

    private function quantified(): object
    {
        if (quantifier($this->peek())) {
            $this->fail('nothing to repeat');
        }
        $content = $this->element();
        if (!quantifier($this->peek())) {
            return $content;
        }
        if (in_array($content->kind, ['assertion', 'lookahead'], true)) {
            $this->fail('nothing to repeat');
        }
        if ($this->take('*')) {
            [$minimum, $maximum] = [0, null];
        } elseif ($this->take('+')) {
            [$minimum, $maximum] = [1, null];
        } elseif ($this->take('?')) {
            [$minimum, $maximum] = [0, 1];
        } else {
            [$minimum, $maximum] = $this->bounds();
        }
        $mode = $this->take('?') ? 'lazy' : ($this->take('+') ? 'possessive' : 'greedy');
        if (quantifier($this->peek())) {
            $this->fail('nested quantifier');
        }
        return (object)['kind' => 'repetition', 'content' => $content, 'minimum' => $minimum,
            'maximum' => $maximum, 'mode' => $mode];
    }

    private function number(int $column): int
    {
        $start = $this->index;
        while (digit($this->code())) {
            ++$this->index;
        }
        if ($start === $this->index) {
            $this->fail('invalid quantifier', $column);
        }
        return (int)substr($this->source, $start, $this->index - $start);
    }

    private function bounds(): array
    {
        $column = ++$this->index;
        $minimum = $this->number($column);
        $maximum = $minimum;
        if ($this->take(',')) {
            $maximum = $this->peek() === '}' ? null : $this->number($column);
        }
        if (!$this->take('}')) {
            $this->fail('invalid quantifier', $column);
        }
        if ($minimum > 100 || ($maximum !== null && $maximum > 100)) {
            $this->fail('quantifier too large', $column);
        }
        if ($maximum !== null && $minimum > $maximum) {
            $this->fail('quantifier range out of order', $column);
        }
        return [$minimum, $maximum];
    }

    private function element(): object
    {
        if ($this->peek() === '(') {
            return $this->group();
        }
        if ($this->peek() === '[') {
            return $this->character_class();
        }
        if ($this->peek() === '\\') {
            return $this->escape();
        }
        $character = $this->source[$this->index++];
        return match ($character) {
            '.' => (object)['kind' => 'any'],
            '^', '$' => (object)['kind' => 'assertion', 'assertion' => $character === '^' ? 'BOL' : 'EOL'],
            default => (object)['kind' => 'literal', 'character' => ord($character)]
        };
    }

    private function name(): array
    {
        $start = $this->index;
        if (letter($this->code()) || $this->peek() === '_') {
            ++$this->index;
            while (word($this->code())) {
                ++$this->index;
            }
        }
        if ($this->index === $start || $this->peek() !== '>') {
            $this->fail('invalid group name');
        }
        $name = substr($this->source, $start, $this->index - $start);
        ++$this->index;
        return [$name, $start + 1];
    }

    private function group(): object
    {
        $column = ++$this->index;
        $kind = 'capture';
        $name = null;
        if ($this->take('?')) {
            $kind = match ($this->peek()) {
                ':' => 'noncapture', '=' => 'positive', '!' => 'negative', '<' => 'named',
                default => $this->fail('invalid group', $column)
            };
            ++$this->index;
        }
        if ($kind === 'named') {
            [$name, $name_column] = $this->name();
            if (isset($this->names[$name])) {
                $this->fail('duplicate group name', $name_column);
            }
        }
        $group = null;
        if ($kind === 'capture' || $kind === 'named') {
            $group = ++$this->groups;
            if ($name !== null) {
                $this->names[$name] = $group;
            }
        }
        $content = $this->alternation();
        if (!$this->take(')')) {
            $this->fail('missing )', $column);
        }
        if ($kind === 'noncapture') {
            return $content;
        }
        return in_array($kind, ['positive', 'negative'], true)
            ? (object)['kind' => 'lookahead', 'positive' => $kind === 'positive', 'content' => $content]
            : (object)['kind' => 'group', 'group' => $group, 'content' => $content];
    }

    private function class_item(): array
    {
        $column = $this->index + 1;
        $character = $this->source[$this->index++];
        if ($character !== '\\') {
            return ['character' => ord($character)];
        }
        if ($this->index === strlen($this->source)) {
            $this->fail('trailing backslash', $column);
        }
        $escaped = $this->source[$this->index++];
        if (str_contains('dDwWsS', $escaped)) {
            $item = shorthand($escaped);
            return ['set' => $item['negated'] ? complement($item['set']) : $item['set']];
        }
        if ($escaped === 'n' || $escaped === 't') {
            return ['character' => $escaped === 'n' ? 10 : 9];
        }
        if (letter(ord($escaped)) || digit(ord($escaped))) {
            $this->fail('invalid escape', $column);
        }
        return ['character' => ord($escaped)];
    }

    private function character_class(): object
    {
        $column = ++$this->index;
        $negated = $this->take('^');
        if ($this->peek() === ']') {
            $this->fail('empty class');
        }
        $set = [];
        while (true) {
            if ($this->peek() === null) {
                $this->fail('missing ]', $column);
            }
            if ($this->take(']')) {
                break;
            }
            $first = $this->class_item();
            if ($this->peek() === '-' && $this->index + 1 < strlen($this->source) && $this->source[$this->index + 1] !== ']') {
                $dash = ++$this->index;
                if (isset($first['set'])) {
                    $this->fail('invalid range', $dash);
                }
                $last = $this->class_item();
                if (isset($last['set']) || $first['character'] > $last['character']) {
                    $this->fail('invalid range', $dash);
                }
                for ($code = $first['character']; $code <= $last['character']; ++$code) {
                    $set[$code] = true;
                }
            } elseif (isset($first['set'])) {
                $set += $first['set'];
            } else {
                $set[$first['character']] = true;
            }
        }
        return (object)['kind' => 'class', 'set' => $set, 'negated' => $negated];
    }

    private function escape(): object
    {
        $column = ++$this->index;
        if ($this->peek() === null) {
            $this->fail('trailing backslash', $column);
        }
        $character = $this->source[$this->index++];
        if (str_contains('dDwWsS', $character)) {
            return (object)(['kind' => 'class'] + shorthand($character));
        }
        if ($character === 'b' || $character === 'B') {
            return (object)['kind' => 'assertion', 'assertion' => $character === 'b' ? 'WORD' : 'NOTWORD'];
        }
        if ($character === 'n' || $character === 't') {
            return (object)['kind' => 'literal', 'character' => $character === 'n' ? 10 : 9];
        }
        if ($character >= '1' && $character <= '9') {
            $start = $this->index - 1;
            while (digit($this->code())) {
                ++$this->index;
            }
            $reference = (object)['kind' => 'backreference',
                'group' => (int)substr($this->source, $start, $this->index - $start), 'column' => $column];
        } elseif ($character === 'k') {
            if (!$this->take('<')) {
                $this->fail('invalid escape', $column);
            }
            [$name] = $this->name();
            $reference = (object)['kind' => 'backreference', 'name' => $name, 'column' => $column];
        } else {
            if (letter(ord($character)) || digit(ord($character))) {
                $this->fail('invalid escape', $column);
            }
            return (object)['kind' => 'literal', 'character' => ord($character)];
        }
        $this->references[] = $reference;
        return $reference;
    }
}

function compile_pattern(object $root): array
{
    $program = [];
    $emit = static function (string $op, array $fields = []) use (&$program): int {
        $program[] = ['op' => $op] + $fields;
        return count($program) - 1;
    };
    $split = static function (int $index, int $repeat, int $stop, string $mode) use (&$program): void {
        $program[$index]['x'] = $mode === 'lazy' ? $stop : $repeat;
        $program[$index]['y'] = $mode === 'lazy' ? $repeat : $stop;
    };
    $visit = static function (object $node) use (&$visit, &$program, $emit, $split): void {
        switch ($node->kind) {
            case 'literal': $emit('CHAR', ['character' => $node->character]); break;
            case 'any': $emit('ANY'); break;
            case 'class': $emit('CLASS', ['set' => $node->set, 'negated' => $node->negated]); break;
            case 'assertion': $emit('ASSERT', ['assertion' => $node->assertion]); break;
            case 'backreference': $emit('BACKREF', ['group' => $node->group]); break;
            case 'group':
                $emit('SAVE', ['group' => 2 * $node->group]);
                $visit($node->content);
                $emit('SAVE', ['group' => 2 * $node->group + 1]);
                break;
            case 'lookahead':
                $look = $emit('LOOK', ['kind' => $node->positive ? 'AHEAD' : 'NOT']);
                $visit($node->content);
                $emit('MATCH');
                $program[$look]['x'] = count($program);
                break;
            case 'concatenation':
                foreach ($node->elements as $element) {
                    $visit($element);
                }
                break;
            case 'alternation':
                $jumps = [];
                for ($i = 0; $i + 1 < count($node->elements); ++$i) {
                    $branch = $emit('SPLIT');
                    $program[$branch]['x'] = count($program);
                    $visit($node->elements[$i]);
                    $jumps[] = $emit('JMP');
                    $program[$branch]['y'] = count($program);
                }
                $visit($node->elements[count($node->elements) - 1]);
                foreach ($jumps as $jump) {
                    $program[$jump]['x'] = count($program);
                }
                break;
            case 'repetition':
                if ($node->mode === 'possessive') {
                    $look = $emit('LOOK', ['kind' => 'ATOMIC']);
                    $greedy = clone $node;
                    $greedy->mode = 'greedy';
                    $visit($greedy);
                    $emit('MATCH');
                    $program[$look]['x'] = count($program);
                } elseif ($node->maximum === null && $node->minimum === 0) {
                    $head = $emit('SPLIT');
                    $visit($node->content);
                    $emit('JMP', ['x' => $head]);
                    $split($head, $head + 1, count($program), $node->mode);
                } elseif ($node->maximum === null) {
                    for ($i = 0; $i < $node->minimum - 1; ++$i) {
                        $visit($node->content);
                    }
                    $head = count($program);
                    $visit($node->content);
                    $branch = $emit('SPLIT');
                    $split($branch, $head, count($program), $node->mode);
                } else {
                    for ($i = 0; $i < $node->minimum; ++$i) {
                        $visit($node->content);
                    }
                    $branches = [];
                    for ($i = $node->minimum; $i < $node->maximum; ++$i) {
                        $branches[] = $emit('SPLIT');
                        $visit($node->content);
                    }
                    foreach ($branches as $branch) {
                        $split($branch, $branch + 1, count($program), $node->mode);
                    }
                }
        }
    };
    $emit('SAVE', ['group' => 0]);
    $visit($root);
    $emit('SAVE', ['group' => 1]);
    $emit('MATCH');
    return $program;
}

function properties(object $node, string $flags): array
{
    if ($node->kind === 'assertion' || $node->kind === 'lookahead') {
        return ['minimum' => 0, 'maximum' => 0, 'first' => [], 'nullable' => true];
    }
    if ($node->kind === 'group') {
        return properties($node->content, $flags);
    }
    if (in_array($node->kind, ['literal', 'any', 'class', 'backreference'], true)) {
        $first = [];
        for ($code = 0; $code < 128; ++$code) {
            $present = match ($node->kind) {
                'literal' => same($code, $node->character, $flags),
                'any' => str_contains($flags, 's') || $code !== 10,
                'class' => class_matches($node->set, $node->negated, $code, $flags),
                default => true
            };
            if ($present) {
                $first[$code] = true;
            }
        }
        $reference = $node->kind === 'backreference';
        return ['minimum' => $reference ? 0 : 1, 'maximum' => $reference ? null : 1,
            'first' => $first, 'nullable' => $reference];
    }
    if ($node->kind === 'repetition') {
        $content = properties($node->content, $flags);
        $maximum = $content['maximum'] === 0 ? 0 : ($content['maximum'] === null || $node->maximum === null
            ? null : $node->maximum * $content['maximum']);
        return ['minimum' => $node->minimum * $content['minimum'], 'maximum' => $maximum,
            'first' => $node->maximum === 0 ? [] : $content['first'],
            'nullable' => $node->maximum === 0 || $node->minimum === 0 || $content['nullable']];
    }
    $elements = array_map(static fn(object $element): array => properties($element, $flags), $node->elements);
    $first = [];
    if ($node->kind === 'concatenation') {
        $minimum = $maximum = 0;
        $nullable = true;
        foreach ($elements as $element) {
            $minimum += $element['minimum'];
            $maximum = $maximum === null || $element['maximum'] === null ? null : $maximum + $element['maximum'];
            if ($nullable) {
                $first += $element['first'];
                $nullable = $element['nullable'];
            }
        }
    } else {
        $minimum = $elements[0]['minimum'];
        $maximum = $elements[0]['maximum'];
        $nullable = false;
        foreach ($elements as $element) {
            $minimum = min($minimum, $element['minimum']);
            $maximum = $maximum === null || $element['maximum'] === null ? null : max($maximum, $element['maximum']);
            $nullable = $nullable || $element['nullable'];
            $first += $element['first'];
        }
    }
    return compact('minimum', 'maximum', 'first', 'nullable');
}

function decode_quoted(string $source): string
{
    $result = '';
    $escapes = ['n' => "\n", 't' => "\t", '\\' => '\\', '"' => '"'];
    for ($i = 1; $i + 1 < strlen($source); ++$i) {
        $result .= $source[$i] === '\\' ? $escapes[$source[++$i]] : $source[$i];
    }
    return $result;
}

function read_patterns(): array
{
    $patterns = [];
    foreach (file('input/patterns.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$name, $flags, $source] = explode(' ', $line, 3);
        $pattern = (object)['name' => $name, 'flags' => $flags, 'source' => $source, 'error' => null];
        $parser = new PatternParser($source);
        try {
            $root = $parser->parse();
            $pattern->groups = $parser->groups;
            $pattern->names = $parser->names;
            $pattern->program = compile_pattern($root);
            $pattern->properties = properties($root, $flags);
            $pattern->pike = true;
            foreach ($pattern->program as $instruction) {
                if ($instruction['op'] === 'BACKREF' || $instruction['op'] === 'LOOK') {
                    $pattern->pike = false;
                    break;
                }
            }
        } catch (PatternError $error) {
            $pattern->error = $error;
        }
        $patterns[$name] = $pattern;
    }
    return $patterns;
}

function template_parts(string $template, object $pattern): ?array
{
    $parts = [];
    $literal = '';
    $index = 0;
    while ($index < strlen($template)) {
        if ($template[$index] !== '$') {
            $literal .= $template[$index++];
            continue;
        }
        if (($template[$index + 1] ?? null) === '$') {
            $literal .= '$';
            $index += 2;
            continue;
        }
        if ($literal !== '') {
            $parts[] = $literal;
            $literal = '';
        }
        $next = $template[$index + 1] ?? null;
        if ($next !== null && digit(ord($next))) {
            $group = (int)$next;
            $index += 2;
        } elseif ($next === '{') {
            $end = strpos($template, '}', $index + 2);
            if ($end === false) {
                return null;
            }
            $name = substr($template, $index + 2, $end - $index - 2);
            $numeric = $name !== '';
            for ($at = 0; $at < strlen($name); ++$at) {
                if (!digit(ord($name[$at]))) {
                    $numeric = false;
                }
            }
            if ($numeric) {
                $group = (int)$name;
            } elseif (isset($pattern->names[$name])) {
                $group = $pattern->names[$name];
            } else {
                return null;
            }
            $index = $end + 1;
        } else {
            return null;
        }
        if ($group > $pattern->groups) {
            return null;
        }
        $parts[] = $group;
    }
    if ($literal !== '') {
        $parts[] = $literal;
    }
    return $parts;
}

function set_group(array $captures, int $group): bool
{
    return $captures[2 * $group] !== null && $captures[2 * $group + 1] !== null;
}

function captured(string $text, array $captures, int $group): string
{
    return substr($text, $captures[2 * $group], $captures[2 * $group + 1] - $captures[2 * $group]);
}

function expand(array $parts, string $text, array $captures): string
{
    $result = '';
    foreach ($parts as $part) {
        $result .= is_string($part) ? $part : (set_group($captures, $part) ? captured($text, $captures, $part) : '');
    }
    return $result;
}

function sequence(BacktrackVM|PikeVM $vm, array $command, string $text): array
{
    if (in_array($command['kind'], ['MATCH', 'SEARCH'], true) || ($command['kind'] === 'REPLACE' && $command['mode'] === 'FIRST')) {
        $match = $vm->search(0, $command['kind'] === 'MATCH');
        return $match === null ? [] : [$match];
    }
    $matches = [];
    $start = 0;
    while ($start <= strlen($text)) {
        $match = $vm->search($start, false);
        if ($match === null) {
            break;
        }
        $matches[] = $match;
        $start = $match[1] > $match[0] ? $match[1] : $match[1] + 1;
    }
    return $matches;
}

function run_engines(object $pattern, string $text, array $command): array
{
    $backtrack = new BacktrackVM($pattern, $text);
    $first = null;
    $aborted = false;
    try {
        $first = sequence($backtrack, $command, $text);
    } catch (TooManySteps) {
        $aborted = true;
    }
    $steps = [['backtrack', $backtrack->steps]];
    if (!$pattern->pike) {
        return ['steps' => $steps, 'matches' => $first, 'label' => 'backtrack', 'failure' => $aborted ? 'TOO_MANY_STEPS' : null];
    }
    $pike = new PikeVM($pattern, $text);
    $second = sequence($pike, $command, $text);
    $steps[] = ['pike', $pike->steps];
    return ['steps' => $steps, 'matches' => $aborted ? $second : $first,
        'label' => $aborted ? 'pike (backtrack: TOO_MANY_STEPS)' : 'both',
        'failure' => $aborted || $first === $second ? null : 'MISMATCH'];
}

function append_match(array &$lines, object $pattern, string $text, array $captures): void
{
    for ($group = 0; $group <= $pattern->groups; ++$group) {
        $label = $group === 0 ? 'match' : "group $group";
        $span = set_group($captures, $group)
            ? $captures[2 * $group] . '-' . $captures[2 * $group + 1] . ' ' . quote(captured($text, $captures, $group)) : '-';
        $lines[] = "$label $span";
    }
}

function append_result(array &$lines, object $pattern, string $text, array $command, array $result): void
{
    if ($result['failure'] !== null) {
        $lines[] = $result['failure'];
        return;
    }
    $lines[] = 'engine ' . $result['label'];
    $matches = $result['matches'];
    if ($command['kind'] === 'MATCH' || $command['kind'] === 'SEARCH') {
        if (!$matches) {
            $lines[] = 'no match';
        } else {
            append_match($lines, $pattern, $text, $matches[0]);
        }
    } elseif ($command['kind'] === 'FINDALL') {
        $lines[] = 'matches ' . count($matches);
        foreach ($matches as $match) {
            append_match($lines, $pattern, $text, $match);
        }
    } elseif ($command['kind'] === 'REPLACE') {
        $replacement = '';
        $previous = 0;
        foreach ($matches as $match) {
            $replacement .= substr($text, $previous, $match[0] - $previous) . expand($command['template'], $text, $match);
            $previous = $match[1];
        }
        $replacement .= substr($text, $previous);
        $lines[] = 'replacements ' . count($matches);
        $lines[] = 'result ' . quote($replacement);
    } else {
        $lines[] = 'pieces ' . (count($matches) + 1);
        $lines[] = 'piece ' . quote(substr($text, 0, $matches ? $matches[0][0] : strlen($text)));
        foreach ($matches as $index => $match) {
            for ($group = 1; $group <= $pattern->groups; ++$group) {
                $lines[] = "group $group " . (set_group($match, $group) ? quote(captured($text, $match, $group)) : '-');
            }
            $end = $matches[$index + 1][0] ?? strlen($text);
            $lines[] = 'piece ' . quote(substr($text, $match[1], $end - $match[1]));
        }
    }
}

function append_program(array &$lines, object $pattern): void
{
    $properties = $pattern->properties;
    $names = [];
    foreach ($pattern->names as $name => $group) {
        $names[] = "$name:$group";
    }
    $name_list = $names ? implode(',', $names) : '-';
    $first = $properties['first'] ? set_notation($properties['first']) : '-';
    $maximum = $properties['maximum'] ?? 'inf';
    $pike = $pattern->pike ? 'yes' : 'no';
    $lines[] = '=== ' . $pattern->name;
    $lines[] = "flags={$pattern->flags} groups={$pattern->groups} names=$name_list length={$properties['minimum']}..$maximum first=$first pike=$pike size=" . count($pattern->program);
    foreach ($pattern->program as $index => $instruction) {
        $lines[] = $index . ' ' . instruction_notation($instruction);
    }
}

function main(): void
{
    $patterns = read_patterns();
    $subjects = [];
    foreach (file('input/subjects.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$name, $source] = explode(' ', $line, 2);
        $subjects[$name] = decode_quoted($source);
    }
    $outputs = ['results.txt' => [], 'programs.txt' => [], 'steps.csv' => ['command,engine,steps'], 'errors.txt' => []];
    foreach ($patterns as $pattern) {
        if ($pattern->error !== null) {
            $error = $pattern->error;
            $outputs['errors.txt'][] = $pattern->name . ': ' . $error->getMessage() . " at column {$error->column}";
            $outputs['errors.txt'][] = '  ' . $pattern->source;
            $outputs['errors.txt'][] = str_repeat(' ', $error->column + 1) . '^';
        }
    }
    foreach (file('input/commands.txt', FILE_IGNORE_NEW_LINES) as $index => $line) {
        $number = $index + 1;
        $words = explode(' ', $line);
        $command = ['kind' => $words[0], 'mode' => $words[0] === 'REPLACE' ? $words[1] : null];
        $pattern = $patterns[$words[$command['kind'] === 'REPLACE' ? 2 : 1]];
        $outputs['results.txt'][] = "#$number $line";
        if ($pattern->error !== null) {
            $outputs['results.txt'][] = 'invalid pattern';
            continue;
        }
        if ($command['kind'] === 'LIST') {
            $outputs['results.txt'][] = 'instructions ' . count($pattern->program);
            append_program($outputs['programs.txt'], $pattern);
            continue;
        }
        $text = $subjects[$words[$command['kind'] === 'REPLACE' ? 3 : 2]];
        if ($command['kind'] === 'REPLACE') {
            $parts = explode(' ', $line, 5);
            $command['template'] = template_parts(decode_quoted($parts[4]), $pattern);
            if ($command['template'] === null) {
                $outputs['results.txt'][] = 'invalid template';
                continue;
            }
        }
        $result = run_engines($pattern, $text, $command);
        foreach ($result['steps'] as [$engine, $steps]) {
            $outputs['steps.csv'][] = "$number,$engine,$steps";
        }
        append_result($outputs['results.txt'], $pattern, $text, $command, $result);
    }
    if (!$outputs['programs.txt']) {
        $outputs['programs.txt'][] = 'no programs';
    }
    if (!$outputs['errors.txt']) {
        $outputs['errors.txt'][] = 'no errors';
    }
    if (!is_dir('output')) {
        mkdir('output');
    }
    foreach ($outputs as $name => $lines) {
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
    }
}

main();
