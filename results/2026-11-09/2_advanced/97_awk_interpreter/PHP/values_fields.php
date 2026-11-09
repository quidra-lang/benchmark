<?php

final readonly class AwkValue
{
    public function __construct(
        public string $kind,
        public ?string $text = null,
        public int $numeric = 0,
    ) {}
}

function uninitialized(): AwkValue
{
    static $v = new AwkValue('uninitialized');
    return $v;
}

function vNumber(int $n): AwkValue
{
    return new AwkValue('number', numeric: $n);
}

function vString(string $s): AwkValue
{
    return new AwkValue('string', $s);
}

function numericPrefix(string $s): int
{
    return preg_match('/^[ \t\n]*([+-]?[0-9]+)/D', $s, $m) ? (int) $m[1] : 0;
}

function inputValue(string $s): AwkValue
{
    return preg_match('/^[ \t\n]*[+-]?[0-9]+[ \t\n]*$/D', $s)
        ? new AwkValue('strnum', $s, numericPrefix($s))
        : vString($s);
}

function toNumber(AwkValue $v): int
{
    return $v->kind === 'string' ? numericPrefix($v->text) : $v->numeric;
}

function toString(AwkValue $v): string
{
    return $v->kind === 'number' ? (string) $v->numeric : $v->text ?? '';
}

function truth(AwkValue $v): bool
{
    return $v->kind === 'string' ? $v->text !== '' : $v->numeric !== 0;
}

function compareAwk(AwkValue $a, AwkValue $b): int
{
    return $a->kind !== 'string' && $b->kind !== 'string'
        ? toNumber($a) <=> toNumber($b)
        : strcmp(toString($a), toString($b));
}

function subscriptCompare(string $a, string $b): int
{
    $x = preg_match('/^(?:0|-?[1-9][0-9]*)$/D', $a) === 1;
    $y = preg_match('/^(?:0|-?[1-9][0-9]*)$/D', $b) === 1;
    return $x !== $y ? ($x ? -1 : 1) : ($x ? (int) $a <=> (int) $b : strcmp($a, $b));
}

function splitPieces(string $text, string $separator): array
{
    if ($text === '')
        return [];
    if ($separator === '')
        return str_split($text);
    if ($separator !== ' ')
        return explode($separator, $text);
    return preg_split('/[ \t\n]+/', trim($text, " \t\n"), -1, PREG_SPLIT_NO_EMPTY);
}

final class AwkArray
{
    public array $elements = [];

    public function read(string $key): AwkValue
    {
        return $this->elements['@' . $key] ??= uninitialized();
    }

    public function put(string $key, AwkValue $v): void
    {
        $this->elements['@' . $key] = $v;
    }

    public function has(string $key): bool
    {
        return isset($this->elements['@' . $key]);
    }

    public function remove(string $key): void
    {
        unset($this->elements['@' . $key]);
    }

    public function keys(): array
    {
        return array_map(fn($k) => substr($k, 1), array_keys($this->elements));
    }
}

final class Record
{
    public AwkValue $zero;
    public array $fields = [];

    public function __construct(
        private Closure $special,
    ) {
        $this->zero = vString('');
    }

    public function set(string $text): void
    {
        $this->zero = inputValue($text);
        $this->fields = array_map(inputValue(...), splitPieces($text, toString(($this->special)('FS'))));
    }

    public function read(int $index): AwkValue
    {
        return $index === 0 ? $this->zero : $this->fields[$index - 1] ?? uninitialized();
    }

    private function rebuild(): void
    {
        $this->zero = inputValue(implode(
            toString(($this->special)('OFS')),
            array_map(toString(...), $this->fields),
        ));
    }

    public function write(int $index, AwkValue $v): void
    {
        if ($index === 0) {
            $this->set(toString($v));
            return;
        }
        while (count($this->fields) < $index)
            $this->fields[] = vString('');
        $this->fields[$index - 1] = $v;
        $this->rebuild();
    }

    public function resize(int $size): void
    {
        $this->fields = array_slice($this->fields, 0, $size);
        while (count($this->fields) < $size)
            $this->fields[] = vString('');
        $this->rebuild();
    }
}

function quoted(string $s): string
{
    $out = '"';
    $escapes = ['"' => '\\"', '\\' => '\\\\', "\n" => '\\n', "\t" => '\\t'];
    foreach (str_split($s) as $c) {
        $code = ord($c);
        $out .=
            $escapes[$c]
            ?? ($code >= 32 && $code <= 126 ? $c : '\\' . str_pad(decoct($code), 3, '0', STR_PAD_LEFT));
    }
    return $out . '"';
}

function describe(AwkValue $v): string
{
    return match ($v->kind) {
        'number' => (string) $v->numeric,
        'uninitialized' => '(uninitialized)',
        default => quoted($v->text) . ($v->kind === 'strnum' ? ' (strnum)' : ''),
    };
}
