<?php
class TemplateFault extends Exception
{
    public ?int $sourceLine;

    public function __construct(string $message, ?int $sourceLine = null)
    {
        parent::__construct($message);
        $this->sourceLine = $sourceLine;
    }
}

class TemplateEngine
{
    private object $root;
    private array $partials = [];
    private array $templates = [];
    private bool $strict = false;
    private const IDENTIFIER = '/\A[A-Za-z_][A-Za-z0-9_]*\z/';
    private const NAME = '/\A(?:\.|@(?:index|number|first|last)|(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*)(?:\.(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*))*)\z/';
    private const NO_ARGS = ['upper', 'lower', 'title', 'trim', 'length', 'first', 'last', 'reverse', 'items', 'comma', 'sum', 'min', 'max'];
    private const WITH_ARGS = ['default', 'eq', 'pad', 'lpad', 'truncate', 'replace', 'join', 'sort', 'pluck', 'add', 'sub', 'mul', 'div', 'mod', 'gt', 'lt'];

    public function __construct()
    {
        $this->root = new stdClass();
    }

    private function fail(string $message, ?int $line = null): never
    {
        throw new TemplateFault($message, $line);
    }

    private function keyParts(string $key): ?array
    {
        if (!preg_match('/\A[A-Za-z_][A-Za-z0-9_]*(?:(?:\.[A-Za-z_][A-Za-z0-9_]*)|(?:\[(?:0|[1-9][0-9]*)\]))*\z/', $key)) {
            return null;
        }
        preg_match_all('/[A-Za-z_][A-Za-z0-9_]*|\[(0|[1-9][0-9]*)\]/', $key, $matches, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
        $parts = [];
        foreach ($matches as $match) {
            $part = isset($match[1]) && $match[1][1] >= 0 ? (int)$match[1][0] : $match[0][0];
            $parts[] = [$part, substr($key, 0, $match[0][1] + strlen($match[0][0]))];
        }
        return $parts;
    }

    private function scalar(string $text, int &$position): mixed
    {
        if (($text[$position] ?? '') === '"') {
            $position++;
            $result = '';
            while ($position < strlen($text)) {
                $char = $text[$position++];
                if ($char === '"') {
                    return $result;
                }
                if ($char === '\\') {
                    $escaped = $text[$position++] ?? '';
                    $char = match ($escaped) {
                        '"' => '"', '\\' => '\\', 'n' => "\n", default => null
                    };
                    if ($char === null) {
                        throw new InvalidArgumentException();
                    }
                }
                $result .= $char;
            }
            throw new InvalidArgumentException();
        }
        if (!preg_match('/\A(?:0|-?[1-9][0-9]*|true|false)/', substr($text, $position), $match)) {
            throw new InvalidArgumentException();
        }
        $position += strlen($match[0]);
        return match ($match[0]) {
            'true' => true, 'false' => false, default => (int)$match[0]
        };
    }

    private function value(string $text): mixed
    {
        if ($text === '[]') {
            return [];
        }
        if ($text === '{}') {
            return new stdClass();
        }
        if (str_starts_with($text, '[')) {
            $result = [];
            $position = 1;
            while (true) {
                $result[] = $this->scalar($text, $position);
                if (($text[$position] ?? '') === ']' && $position === strlen($text) - 1) {
                    return $result;
                }
                if (substr($text, $position, 2) !== ', ') {
                    throw new InvalidArgumentException();
                }
                $position += 2;
            }
        }
        $position = 0;
        $result = $this->scalar($text, $position);
        if ($position !== strlen($text)) {
            throw new InvalidArgumentException();
        }
        return $result;
    }

    private function has(mixed $value, mixed $part): bool
    {
        return is_string($part) ? is_object($value) && property_exists($value, $part)
            : is_array($value) && array_key_exists($part, $value);
    }

    private function get(mixed $value, mixed $part): mixed
    {
        return is_object($value) ? $value->{$part} : $value[$part];
    }

    private function assign(mixed &$container, array $parts, mixed $value, int $index = 0): void
    {
        [$part, $prefix] = $parts[$index];
        if (is_int($part) && $part > count($container)) {
            $this->fail("index gap at '$prefix'");
        }
        if ($index === count($parts) - 1) {
            if (is_object($container)) {
                $container->{$part} = $value;
            } else {
                $container[$part] = $value;
            }
            return;
        }
        $list = is_int($parts[$index + 1][0]);
        if ($this->has($container, $part)) {
            $child = $this->get($container, $part);
            if (($list && !is_array($child)) || (!$list && !is_object($child))) {
                $this->fail("type conflict at '$prefix'");
            }
        } else {
            $child = $list ? [] : new stdClass();
        }
        $this->assign($child, $parts, $value, $index + 1);
        if (is_object($container)) {
            $container->{$part} = $child;
        } else {
            $container[$part] = $child;
        }
    }

    private function remove(mixed &$container, array $parts, string $key, int $index = 0): void
    {
        $part = $parts[$index][0];
        if (!$this->has($container, $part)) {
            $this->fail("no value at '$key'");
        }
        if ($index === count($parts) - 1) {
            if (is_object($container)) {
                unset($container->{$part});
            } else {
                array_splice($container, $part, 1);
            }
        } else {
            $child = $this->get($container, $part);
            $this->remove($child, $parts, $key, $index + 1);
            if (is_object($container)) {
                $container->{$part} = $child;
            } else {
                $container[$part] = $child;
            }
        }
    }

    private function data(array $body): void
    {
        $set = 0;
        $unset = 0;
        $errors = [];
        foreach ($body as [$text, $line]) {
            if ($text === '' || str_starts_with($text, '#')) {
                continue;
            }
            try {
                $deleting = str_starts_with($text, 'UNSET ');
                if ($deleting) {
                    $key = substr($text, 6);
                } else {
                    if (!str_contains($text, ' = ')) {
                        $this->fail('bad line');
                    }
                    [$key, $notation] = explode(' = ', $text, 2);
                }
                $parts = $this->keyParts($key);
                if ($parts === null) {
                    $this->fail("bad key '$key'");
                }
                if (!$deleting) {
                    try {
                        $value = $this->value($notation);
                    } catch (InvalidArgumentException $error) {
                        $this->fail("bad value '$notation'");
                    }
                }
                $changed = unserialize(serialize($this->root));
                if ($deleting) {
                    $this->remove($changed, $parts, $key);
                    $unset++;
                } else {
                    $this->assign($changed, $parts, $value);
                    $set++;
                }
                $this->root = $changed;
            } catch (TemplateFault $error) {
                $errors[] = "ERROR line $line: {$error->getMessage()}";
            }
        }
        echo "DATA set=$set unset=$unset errors=" . count($errors) . "\n";
        foreach ($errors as $error) {
            echo "$error\n";
        }
    }

    private function splitQuoted(string $text, string $separator): array
    {
        $parts = [];
        $quoted = false;
        $start = 0;
        for ($index = 0; $index < strlen($text); $index++) {
            if ($text[$index] === "'") {
                $quoted = !$quoted;
            }
            if ($text[$index] === $separator && !$quoted) {
                $parts[] = substr($text, $start, $index - $start);
                $start = $index + 1;
            }
        }
        $parts[] = substr($text, $start);
        return $parts;
    }

    private function expression(string $text, int $line): array
    {
        $pieces = array_map(fn($part) => trim($part, ' '), $this->splitQuoted($text, '|'));
        $name = array_shift($pieces);
        if (!preg_match(self::NAME, $name)) {
            $this->fail("invalid name '$name'", $line);
        }
        $filters = [];
        foreach ($pieces as $piece) {
            $arguments = $this->splitQuoted($piece, ':');
            $filter = array_shift($arguments);
            if (!in_array($filter, self::NO_ARGS, true) && !in_array($filter, self::WITH_ARGS, true)) {
                $this->fail("unknown filter '$filter'", $line);
            }
            $args = [];
            $valid = true;
            foreach ($arguments as $argument) {
                if (preg_match("/\A'[^']*'\z/", $argument)) {
                    $args[] = substr($argument, 1, -1);
                } elseif (preg_match('/\A-?[0-9]{1,9}\z/', $argument)) {
                    $args[] = (int)$argument;
                } else {
                    $valid = false;
                }
            }
            $count = count($args);
            $integers = count(array_filter($args, 'is_int')) === $count;
            $strings = count(array_filter($args, 'is_string')) === $count;
            if (in_array($filter, self::NO_ARGS, true)) {
                $valid = $valid && $count === 0;
            } elseif (in_array($filter, ['default', 'eq'], true)) {
                $valid = $valid && $count === 1;
            } elseif (in_array($filter, ['pad', 'lpad'], true)) {
                $valid = $valid && ($count === 1 || $count === 2) && is_int($args[0]) && $args[0] >= 0 &&
                    ($count === 1 || (is_string($args[1]) && strlen($args[1]) === 1));
            } elseif ($filter === 'truncate') {
                $valid = $valid && $count === 1 && $integers && $args[0] >= 0;
            } elseif ($filter === 'replace') {
                $valid = $valid && $count === 2 && $strings && $args[0] !== '';
            } elseif (in_array($filter, ['join', 'pluck'], true)) {
                $valid = $valid && $count === 1 && $strings;
            } elseif ($filter === 'sort') {
                $valid = $valid && $count <= 1 && $strings;
            } else {
                $valid = $valid && $count === 1 && $integers && (!in_array($filter, ['div', 'mod'], true) || $args[0] !== 0);
            }
            if (!$valid) {
                $this->fail("bad arguments for '$filter'", $line);
            }
            $filters[] = [$filter, $args];
        }
        return [$name, $filters];
    }

    private function tree(array $tokens, int &$index): array
    {
        $nodes = [];
        while ($index < count($tokens)) {
            $token = $tokens[$index++];
            if ($token['kind'] === 'close') {
                break;
            }
            if (in_array($token['kind'], ['section', 'inverted'], true)) {
                $token['children'] = $this->tree($tokens, $index);
            }
            $nodes[] = $token;
        }
        return $nodes;
    }

    private function analyze(array $body): array
    {
        $opening = '{{';
        $closing = '}}';
        $tokens = [];
        $sections = [];
        $kinds = ['#' => 'section', '^' => 'inverted', '/' => 'close', '!' => 'comment', '>' => 'partial', '&' => 'raw', '=' => 'delimiter'];
        foreach ($body as [$text, $line]) {
            $local = [];
            $position = 0;
            while (true) {
                $start = strpos($text, $opening, $position);
                if ($start === false) {
                    $local[] = ['kind' => 'text', 'text' => substr($text, $position), 'line' => $line];
                    break;
                }
                $local[] = ['kind' => 'text', 'text' => substr($text, $position, $start - $position), 'line' => $line];
                $contentStart = $start + strlen($opening);
                $triple = ($text[$contentStart] ?? '') === '{';
                if ($triple) {
                    $contentStart++;
                }
                $endDelimiter = ($triple ? '}' : '') . $closing;
                $finish = strpos($text, $endDelimiter, $contentStart);
                if ($finish === false) {
                    $this->fail('unclosed tag', $line);
                }
                $content = trim(substr($text, $contentStart, $finish - $contentStart), ' ');
                $position = $finish + strlen($endDelimiter);
                $kind = $triple ? 'raw' : ($kinds[$content[0] ?? ''] ?? 'variable');
                $argument = $triple || $kind === 'variable' ? $content : trim(substr($content, 1), ' ');
                $token = ['kind' => $kind, 'text' => $argument, 'line' => $line, 'indent' => ''];
                if (in_array($kind, ['variable', 'raw', 'section', 'inverted'], true)) {
                    $token['expression'] = $this->expression($argument, $line);
                    if (in_array($kind, ['section', 'inverted'], true)) {
                        $sections[] = [$token['expression'][0], $line];
                    }
                } elseif ($kind === 'close') {
                    if (!preg_match(self::NAME, $argument)) {
                        $this->fail("invalid name '$argument'", $line);
                    }
                    if ($sections === []) {
                        $this->fail("unexpected closing '$argument'", $line);
                    }
                    $expected = $sections[array_key_last($sections)][0];
                    if ($expected !== $argument) {
                        $this->fail("mismatched closing '$argument', expected '$expected'", $line);
                    }
                    array_pop($sections);
                } elseif ($kind === 'partial') {
                    if (!preg_match(self::IDENTIFIER, $argument)) {
                        $this->fail("invalid name '$argument'", $line);
                    }
                } elseif ($kind === 'delimiter') {
                    $delimiters = strlen($content) >= 2 && str_ends_with($content, '=')
                        ? preg_split('/ +/', trim(substr($content, 1, -1), ' '), -1, PREG_SPLIT_NO_EMPTY) : [];
                    if (count($delimiters) !== 2 || str_contains(implode('', $delimiters), '=')) {
                        $this->fail('invalid delimiters', $line);
                    }
                    [$opening, $closing] = $delimiters;
                }
                $local[] = $token;
            }
            $tags = array_values(array_filter($local, fn($token) => $token['kind'] !== 'text'));
            $onlySpaces = true;
            foreach ($local as $token) {
                if ($token['kind'] === 'text' && trim($token['text'], ' ') !== '') {
                    $onlySpaces = false;
                }
            }
            if (count($tags) === 1 && in_array($tags[0]['kind'], ['section', 'inverted', 'close', 'comment', 'partial', 'delimiter'], true) && $onlySpaces) {
                if ($tags[0]['kind'] === 'partial') {
                    $tags[0]['indent'] = $local[0]['text'];
                }
                $tokens[] = $tags[0];
            } else {
                array_push($tokens, ...$local);
                $tokens[] = ['kind' => 'text', 'text' => "\n", 'line' => $line];
            }
        }
        if ($sections !== []) {
            [$name, $line] = $sections[array_key_last($sections)];
            $this->fail("unclosed section '$name'", $line);
        }
        $index = 0;
        return $this->tree($tokens, $index);
    }

    private function stringify(mixed $value): string
    {
        if ($value === null) {
            return '';
        }
        if (is_object($value)) {
            $this->fail('cannot render map');
        }
        if (is_array($value)) {
            return implode(', ', array_map(fn($item) => $this->stringify($item), $value));
        }
        if (is_bool($value)) {
            return $value ? 'true' : 'false';
        }
        return (string)$value;
    }

    private function truthy(mixed $value): bool
    {
        return !($value === null || $value === false || $value === 0 || $value === '' || $value === [] || (is_object($value) && get_object_vars($value) === []));
    }

    private function number(mixed $value, string $filter): int
    {
        if ($value === null) {
            return 0;
        }
        if (is_int($value) || (is_string($value) && preg_match('/\A-?[0-9]{1,9}\z/', $value))) {
            return (int)$value;
        }
        $this->fail("not a number for '$filter'");
    }

    private function sortKey(mixed $value): array
    {
        return match (true) {
            $value === null => [0, 0], is_int($value) => [1, $value], is_string($value) => [2, $value],
            is_bool($value) => [3, $value ? 1 : 0], default => [4, 0]
        };
    }

    private function filter(mixed $value, string $filter, array $args): mixed
    {
        switch ($filter) {
            case 'upper': return strtoupper($this->stringify($value));
            case 'lower': return strtolower($this->stringify($value));
            case 'title': return preg_replace_callback('/\A.|(?<= )./', fn($match) => strtoupper($match[0]), strtolower($this->stringify($value)));
            case 'trim': return trim($this->stringify($value), ' ');
            case 'length': return is_array($value) || is_object($value) ? count((array)$value) : strlen($this->stringify($value));
            case 'first': return is_array($value) ? ($value[0] ?? null) : $value;
            case 'last': return is_array($value) ? ($value === [] ? null : $value[array_key_last($value)]) : $value;
            case 'reverse': return is_array($value) ? array_reverse($value) : (is_string($value) ? strrev($value) : $value);
            case 'items':
                if (!is_object($value)) {
                    return $value;
                }
                $map = get_object_vars($value);
                ksort($map, SORT_STRING);
                $items = [];
                foreach ($map as $key => $item) {
                    $items[] = (object)['key' => (string)$key, 'value' => $item];
                }
                return $items;
            case 'comma': return number_format($this->number($value, $filter), 0, '.', ',');
            case 'sum':
            case 'min':
            case 'max':
                if (!is_array($value)) {
                    return $this->number($value, $filter);
                }
                $numbers = array_map(fn($item) => $this->number($item, $filter), $value);
                return $filter === 'sum' ? array_sum($numbers) : ($numbers === [] ? null : ($filter === 'min' ? min($numbers) : max($numbers)));
            case 'default': return $this->truthy($value) ? $value : $args[0];
            case 'eq': return $this->stringify($value) === $this->stringify($args[0]);
            case 'pad': return str_pad($this->stringify($value), $args[0], $args[1] ?? ' ', STR_PAD_RIGHT);
            case 'lpad': return str_pad($this->stringify($value), $args[0], $args[1] ?? ' ', STR_PAD_LEFT);
            case 'truncate':
                $text = $this->stringify($value);
                return strlen($text) > $args[0] ? substr($text, 0, $args[0]) . '...' : $text;
            case 'replace': return str_replace($args[0], $args[1], $this->stringify($value));
            case 'join': return is_array($value) ? implode($args[0], array_map(fn($item) => $this->stringify($item), $value)) : $this->stringify($value);
            case 'sort':
                if (!is_array($value)) {
                    return $value;
                }
                $items = [];
                foreach ($value as $index => $item) {
                    $key = $args === [] ? $item : (is_object($item) && property_exists($item, $args[0]) ? $item->{$args[0]} : null);
                    $items[] = [$this->sortKey($key), $index, $item];
                }
                usort($items, function ($a, $b) {
                    $comparison = $a[0][0] <=> $b[0][0];
                    if ($comparison === 0) {
                        $comparison = $a[0][0] === 2 ? strcmp($a[0][1], $b[0][1]) : ($a[0][1] <=> $b[0][1]);
                    }
                    return $comparison !== 0 ? $comparison : ($a[1] <=> $b[1]);
                });
                return array_map(fn($item) => $item[2], $items);
            case 'pluck': return is_array($value) ? array_map(fn($item) => is_object($item) && property_exists($item, $args[0]) ? $item->{$args[0]} : null, $value) : $value;
            case 'add': return $this->number($value, $filter) + $args[0];
            case 'sub': return $this->number($value, $filter) - $args[0];
            case 'mul': return $this->number($value, $filter) * $args[0];
            case 'div': return (int)floor($this->number($value, $filter) / $args[0]);
            case 'mod':
                $number = $this->number($value, $filter);
                return $number - $args[0] * (int)floor($number / $args[0]);
            case 'gt': return $this->number($value, $filter) > $args[0];
            case 'lt': return $this->number($value, $filter) < $args[0];
        }
        return $value;
    }

    private function resolve(string $name, array $contexts, array $loops): array
    {
        if ($name === '.') {
            return [true, $contexts[array_key_last($contexts)]];
        }
        if (str_starts_with($name, '@')) {
            if ($loops === []) {
                return [false, null];
            }
            [$index, $count] = $loops[array_key_last($loops)];
            return [true, match ($name) {
                '@index' => $index, '@number' => $index + 1, '@first' => $index === 0, '@last' => $index === $count - 1
            }];
        }
        $parts = array_map(fn($part) => ctype_digit($part) ? (int)$part : $part, explode('.', $name));
        $found = false;
        foreach (array_reverse($contexts) as $context) {
            if ($this->has($context, $parts[0])) {
                $found = true;
                break;
            }
        }
        if (!$found) {
            return [false, null];
        }
        foreach ($parts as $part) {
            if (!$this->has($context, $part)) {
                return [false, null];
            }
            $context = $this->get($context, $part);
        }
        return [true, $context];
    }

    private function evaluate(array $token, array $contexts, array $loops): mixed
    {
        [$name, $filters] = $token['expression'];
        [$found, $value] = $this->resolve($name, $contexts, $loops);
        if ($this->strict && in_array($token['kind'], ['variable', 'raw'], true) && !$found) {
            $this->fail("missing '$name'");
        }
        foreach ($filters as [$filter, $args]) {
            $value = $this->filter($value, $filter, $args);
        }
        return $value;
    }

    private function html(string $text): string
    {
        return strtr($text, ['&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;']);
    }

    private function render(array $nodes, array $contexts, array $loops, int $depth): string
    {
        $output = '';
        foreach ($nodes as $token) {
            try {
                switch ($token['kind']) {
                    case 'text':
                        $output .= $token['text'];
                        break;
                    case 'variable':
                    case 'raw':
                        $text = $this->stringify($this->evaluate($token, $contexts, $loops));
                        $output .= $token['kind'] === 'variable' ? $this->html($text) : $text;
                        break;
                    case 'section':
                        $value = $this->evaluate($token, $contexts, $loops);
                        if (is_array($value)) {
                            foreach ($value as $index => $item) {
                                $output .= $this->render($token['children'], [...$contexts, $item], [...$loops, [$index, count($value)]], $depth);
                            }
                        } elseif ($this->truthy($value)) {
                            $output .= $this->render($token['children'], [...$contexts, $value], $loops, $depth);
                        }
                        break;
                    case 'inverted':
                        if (!$this->truthy($this->evaluate($token, $contexts, $loops))) {
                            $output .= $this->render($token['children'], $contexts, $loops, $depth);
                        }
                        break;
                    case 'partial':
                        $name = $token['text'];
                        if (!array_key_exists($name, $this->partials)) {
                            $this->fail("unknown partial '$name'");
                        }
                        if ($depth === 8) {
                            $this->fail("partial depth exceeded at '$name'");
                        }
                        $body = array_map(fn($entry) => [$entry[0] === '' ? '' : $token['indent'] . $entry[0], $entry[1]], $this->partials[$name]);
                        $output .= $this->render($this->analyze($body), $contexts, $loops, $depth + 1);
                        break;
                }
            } catch (TemplateFault $error) {
                $error->sourceLine ??= $token['line'];
                throw $error;
            }
        }
        return $output;
    }

    private function renderTemplate(string $name, int $line): void
    {
        if (!array_key_exists($name, $this->templates)) {
            echo "TEMPLATE $name ERROR line $line: unknown template '$name'\n";
            return;
        }
        try {
            $result = $this->render($this->analyze($this->templates[$name]), [$this->root], [], 0);
            $count = $result === '' ? 0 : substr_count($result, "\n") + (str_ends_with($result, "\n") ? 0 : 1);
            echo "TEMPLATE $name OK lines=$count chars=" . strlen($result) . "\n";
            echo $result;
            if ($result !== '' && !str_ends_with($result, "\n")) {
                echo "\n";
            }
        } catch (TemplateFault $error) {
            echo "TEMPLATE $name ERROR line {$error->sourceLine}: {$error->getMessage()}\n";
        }
    }

    private function leaves(mixed $value, string $path, array &$output): void
    {
        if (is_object($value) && get_object_vars($value) !== []) {
            $map = get_object_vars($value);
            ksort($map, SORT_STRING);
            foreach ($map as $key => $item) {
                $this->leaves($item, $path === '' ? $key : "$path.$key", $output);
            }
        } elseif (is_array($value) && $value !== []) {
            foreach ($value as $index => $item) {
                $this->leaves($item, $path . "[$index]", $output);
            }
        } elseif ($path !== '') {
            $notation = match (true) {
                is_string($value) => '"' . strtr($value, ['\\' => '\\\\', '"' => '\\"', "\n" => '\\n']) . '"',
                is_object($value) => '{}', is_array($value) => '[]', default => $this->stringify($value)
            };
            $output[] = "$path = $notation";
        }
    }

    public function run(): void
    {
        $input = [];
        while (($line = fgets(STDIN)) !== false) {
            $input[] = rtrim($line, "\r\n");
        }
        $index = 0;
        while ($index < count($input)) {
            $command = $input[$index];
            $line = ++$index;
            if ($command === 'END') {
                break;
            }
            $words = explode(' ', $command, 2);
            $kind = $words[0];
            $name = $words[1] ?? '';
            if (in_array($kind, ['DATA', 'PARTIAL', 'TEMPLATE'], true)) {
                $body = [];
                $ending = ['DATA' => 'ENDDATA', 'PARTIAL' => 'ENDPARTIAL', 'TEMPLATE' => 'ENDTEMPLATE'][$kind];
                while ($input[$index] !== $ending) {
                    $body[] = [$input[$index], $index + 1];
                    $index++;
                }
                $index++;
                if ($kind === 'DATA') {
                    $this->data($body);
                } elseif ($kind === 'PARTIAL') {
                    try {
                        $this->analyze($body);
                        $action = array_key_exists($name, $this->partials) ? 'REPLACED' : 'DEFINED';
                        $this->partials[$name] = $body;
                        echo "PARTIAL $name $action lines=" . count($body) . "\n";
                    } catch (TemplateFault $error) {
                        echo "PARTIAL $name ERROR line {$error->sourceLine}: {$error->getMessage()}\n";
                    }
                } else {
                    $this->templates[$name] = $body;
                    $this->renderTemplate($name, $line);
                }
            } elseif ($kind === 'RENDER') {
                $this->renderTemplate($name, $line);
            } elseif ($kind === 'DUMP') {
                $leaves = [];
                $this->leaves($this->root, '', $leaves);
                echo 'DUMP leaves=' . count($leaves) . "\n";
                foreach ($leaves as $leaf) {
                    echo "$leaf\n";
                }
            } elseif ($kind === 'STRICT') {
                $this->strict = $name === 'ON';
                echo "$command\n";
            } elseif ($kind === 'RESET') {
                $this->root = new stdClass();
                $this->partials = [];
                $this->templates = [];
                echo "RESET\n";
            }
        }
    }
}

(new TemplateEngine())->run();
