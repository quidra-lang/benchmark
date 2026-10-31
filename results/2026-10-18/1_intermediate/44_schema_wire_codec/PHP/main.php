<?php
declare(strict_types=1);

enum Kind
{
    case UInt32; case UInt64; case SInt32; case SInt64; case Boolean;
    case Fixed32; case SFixed32; case Fixed64; case Text; case Bytes;
    case Enumeration; case Message;
}

final class CodecError extends RuntimeException {}

final class SchemaType
{
    public array $fields = [];
    public array $namedFields = [];
    public array $members = [];
    public array $numbers = [];

    public function __construct(public readonly string $name, public readonly Kind $kind) {}

    public function wire(): int
    {
        return match ($this->kind) {
            Kind::Fixed32, Kind::SFixed32 => 5,
            Kind::Fixed64 => 1,
            Kind::Text, Kind::Bytes, Kind::Message => 2,
            default => 0,
        };
    }

    public function inRange(int $value): bool
    {
        return match ($this->kind) {
            Kind::UInt32, Kind::Fixed32 => $value >= 0 && $value <= 4294967295,
            Kind::UInt64, Kind::Fixed64 => $value >= 0 && $value <= 9007199254740991,
            Kind::SInt32, Kind::SFixed32 => $value >= -2147483648 && $value <= 2147483647,
            Kind::SInt64 => $value >= -4503599627370496 && $value <= 4503599627370495,
            default => true,
        };
    }
}

final class Field
{
    public SchemaType $type;

    public function __construct(
        public readonly int $number,
        public readonly string $typeName,
        public readonly string $name,
        public readonly bool $required,
        public readonly bool $repeated,
        public readonly bool $packed,
        public readonly ?string $group,
    ) {}
}

final class Schema
{
    public array $types = [];

    public function __construct()
    {
        $kinds = [
            'uint32' => Kind::UInt32, 'uint64' => Kind::UInt64,
            'sint32' => Kind::SInt32, 'sint64' => Kind::SInt64, 'bool' => Kind::Boolean,
            'fixed32' => Kind::Fixed32, 'sfixed32' => Kind::SFixed32,
            'fixed64' => Kind::Fixed64, 'string' => Kind::Text, 'bytes' => Kind::Bytes,
        ];
        foreach ($kinds as $name => $kind) $this->types[$name] = new SchemaType($name, $kind);
        $current = null;
        while (($line = inputLine()) !== 'END SCHEMA') {
            $words = explode(' ', $line);
            switch ($words[0]) {
                case 'ENUM':
                case 'MESSAGE':
                    $current = new SchemaType($words[1], $words[0] === 'ENUM' ? Kind::Enumeration : Kind::Message);
                    $this->types[$current->name] = $current;
                    break;
                case 'VALUE':
                    $current->members[(int)$words[2]] = $words[1];
                    $current->numbers[$words[1]] = (int)$words[2];
                    break;
                case 'FIELD':
                    $mode = $words[4] ?? '';
                    $field = new Field((int)$words[1], $words[2], $words[3], $mode === 'REQUIRED',
                        $mode === 'REPEATED', ($words[5] ?? '') === 'PACKED',
                        $mode === 'ONEOF' ? $words[5] : null);
                    $current->fields[$field->number] = $field;
                    $current->namedFields[$field->name] = $field;
                    break;
            }
        }
        foreach ($this->types as $type) {
            ksort($type->fields, SORT_NUMERIC);
            ksort($type->members, SORT_NUMERIC);
            foreach ($type->fields as $field) $field->type = $this->types[$field->typeName];
        }
    }
}

final readonly class Unknown
{
    public function __construct(public int $number, public int $wire, public int|string $value) {}
}

final class Message
{
    public array $fields = [];
    public array $unknown = [];

    public function __construct(public readonly SchemaType $type) {}

    public function values(Field $field): array
    {
        return $this->fields[$field->number] ?? [];
    }

    public function choose(Field $field): void
    {
        if ($field->group === null) return;
        foreach ($this->type->fields as $other) {
            if ($other !== $field && $other->group === $field->group) unset($this->fields[$other->number]);
        }
    }

    public function apply(Field $field, array $values): void
    {
        if ($values === []) return;
        $this->choose($field);
        $old = $this->values($field);
        if ($field->repeated) $this->fields[$field->number] = array_merge($old, $values);
        elseif ($field->type->kind === Kind::Message && $old !== []) $old[0]->merge($values[0]);
        else $this->fields[$field->number] = $values;
    }

    public function merge(Message $source): void
    {
        foreach ($this->type->fields as $field) $this->apply($field, $source->values($field));
        $this->unknown = array_merge($this->unknown, $source->unknown);
    }
}

function inputLine(): string
{
    return rtrim(fgets(STDIN), "\r\n");
}

function zigzag(int $value): int
{
    return $value >= 0 ? 2 * $value : -2 * $value - 1;
}

function varint(int $value): string
{
    $bytes = '';
    while ($value >= 128) {
        $bytes .= chr($value % 128 + 128);
        $value = intdiv($value, 128);
    }
    return $bytes . chr($value);
}

function hexText(string $bytes): string
{
    return $bytes === '' ? '-' : bin2hex($bytes);
}

function wireName(int $wire): string
{
    return match ($wire) { 0 => 'varint', 1 => 'i64', 2 => 'len', 5 => 'i32' };
}

function quoted(string $value, bool $json = false): string
{
    $text = '"';
    for ($i = 0; $i < strlen($value); ++$i) {
        $byte = ord($value[$i]);
        $text .= match ($byte) {
            34 => '\\"', 92 => '\\\\', 10 => '\\n', 9 => '\\t',
            default => $byte >= 32 && $byte <= 126 ? $value[$i] :
                ($json ? '\\u00' : '\\x') . sprintf('%02x', $byte),
        };
    }
    return $text . '"';
}

function valueText(SchemaType $type, int|bool|string|Message $value, bool $json = false): string
{
    return match ($type->kind) {
        Kind::Message => messageText($value, $json),
        Kind::Boolean => $value ? 'true' : 'false',
        Kind::Enumeration => $json ? quoted($type->members[$value]) : $type->members[$value],
        Kind::Text => quoted($value, $json),
        Kind::Bytes => $json ? '"' . base64_encode($value) . '"' : '<' . bin2hex($value) . '>',
        Kind::UInt64, Kind::SInt64, Kind::Fixed64 => $json ? '"' . $value . '"' : (string)$value,
        default => (string)$value,
    };
}

function sequenceText(SchemaType $type, array $values, bool $json = false): string
{
    $items = array_map(fn($value) => valueText($type, $value, $json), $values);
    return '[' . implode($json ? ',' : ', ', $items) . ']';
}

function messageText(Message $message, bool $json = false): string
{
    $items = [];
    foreach ($message->type->fields as $field) {
        $values = $message->values($field);
        if ($values === []) continue;
        $key = $field->name;
        if ($json) {
            $key = preg_replace_callback('/_([a-z0-9])/', fn($match) => strtoupper($match[1]), $key);
            $key = quoted($key);
        }
        $value = $field->repeated ? sequenceText($field->type, $values, $json) :
            valueText($field->type, $values[0], $json);
        $items[] = $key . ($json ? ':' : ': ') . $value;
    }
    return '{' . implode($json ? ',' : ', ', $items) . '}';
}

function rawText(Unknown $unknown): string
{
    return $unknown->wire === 0 ? (string)$unknown->value : '<' . bin2hex($unknown->value) . '>';
}

function textContents(Message $message, int $depth, array &$lines): void
{
    $indent = str_repeat(' ', 2 * $depth);
    foreach ($message->type->fields as $field) {
        foreach ($message->values($field) as $value) {
            if ($field->type->kind === Kind::Message) {
                $lines[] = $indent . $field->name . ' {';
                textContents($value, $depth + 1, $lines);
                $lines[] = $indent . '}';
            } else $lines[] = $indent . $field->name . ': ' . valueText($field->type, $value);
        }
    }
    foreach ($message->unknown as $unknown)
        $lines[] = $indent . $unknown->number . ': ' . wireName($unknown->wire) . ' ' . rawText($unknown);
}

function textMessage(Message $message): array
{
    $lines = [$message->type->name . ' {'];
    textContents($message, 1, $lines);
    $lines[] = '}';
    return $lines;
}

function encodeValue(SchemaType $type, int|bool|string|Message $value): string
{
    if ($type->wire() === 2) {
        $payload = $type->kind === Kind::Message ? encode($value) : $value;
        return varint(strlen($payload)) . $payload;
    }
    if ($type->wire() === 0) {
        $number = match ($type->kind) {
            Kind::SInt32, Kind::SInt64 => zigzag($value),
            Kind::Boolean => $value ? 1 : 0,
            default => $value,
        };
        return varint($number);
    }
    if ($value < 0) $value += 4294967296;
    $bytes = '';
    $length = $type->wire() === 1 ? 8 : 4;
    for ($i = 0; $i < $length; ++$i) {
        $bytes .= chr($value % 256);
        $value = intdiv($value, 256);
    }
    return $bytes;
}

function encodeField(Field $field, array $values): string
{
    if ($values === []) return '';
    $bytes = '';
    if ($field->packed) {
        foreach ($values as $value) $bytes .= encodeValue($field->type, $value);
        return varint($field->number * 8 + 2) . varint(strlen($bytes)) . $bytes;
    }
    foreach ($values as $value)
        $bytes .= varint($field->number * 8 + $field->type->wire()) . encodeValue($field->type, $value);
    return $bytes;
}

function encode(Message $message): string
{
    $bytes = '';
    foreach ($message->type->fields as $field) $bytes .= encodeField($field, $message->values($field));
    foreach ($message->unknown as $unknown) {
        $bytes .= varint($unknown->number * 8 + $unknown->wire);
        $bytes .= match ($unknown->wire) {
            0 => varint($unknown->value),
            2 => varint(strlen($unknown->value)) . $unknown->value,
            default => $unknown->value,
        };
    }
    return $bytes;
}

final readonly class RawValue
{
    public function __construct(public int|string $value, public int $position, public int $payload) {}
}

final class ByteReader
{
    public function __construct(public readonly string $data, public int $position, public readonly int $end) {}

    public function varint(): int
    {
        $start = $this->position;
        $value = 0;
        for ($i = 0; $i < 8; ++$i) {
            if ($this->position === $this->end) throw new CodecError("truncated varint at byte $start");
            $byte = ord($this->data[$this->position++]);
            $value |= ($byte & 127) << (7 * $i);
            if ($byte < 128) {
                if ($value > 9007199254740991) throw new CodecError("varint too large at byte $start");
                return $value;
            }
        }
        throw new CodecError("varint too long at byte $start");
    }

    public function read(int $wire): RawValue
    {
        $start = $this->position;
        if ($wire === 0) return new RawValue($this->varint(), $start, $start);
        $length = match ($wire) { 1 => 8, 5 => 4, 2 => $this->varint() };
        $payload = $this->position;
        if ($length > $this->end - $payload) {
            $reason = $wire === 2 ? 'length past end' : 'truncated ' . wireName($wire);
            throw new CodecError("$reason at byte $start");
        }
        $this->position += $length;
        return new RawValue(substr($this->data, $payload, $length), $start, $payload);
    }
}

final readonly class Token
{
    public function __construct(public string $kind, public int|string|null $value, public int $column) {}

    public function shape(): string
    {
        return match ($this->kind) {
            '{' => 'message', '[' => 'list', 'integer' => 'integer',
            'string' => 'string', 'bytes' => 'bytes',
            'name' => $this->value === 'true' || $this->value === 'false' ? 'boolean' : 'name',
            default => '',
        };
    }
}

final class Literal
{
    private array $tokens = [];
    private int $position = 0;

    public function __construct(string $source)
    {
        $length = strlen($source);
        for ($i = 0; $i < $length;) {
            $c = $source[$i];
            if ($c === ' ') { ++$i; continue; }
            $column = $i + 1;
            if (str_contains('{}[]:,', $c)) {
                $this->tokens[] = new Token($c, null, $column);
                ++$i;
            } elseif ($c === '"') {
                ++$i;
                $value = '';
                while ($i < $length && $source[$i] !== '"') {
                    $c = $source[$i++];
                    if ($c !== '\\') { $value .= $c; continue; }
                    if ($i === $length) $this->problem('syntax error', $column);
                    $escape = $source[$i++];
                    if ($escape === '"' || $escape === '\\') $value .= $escape;
                    elseif ($escape === 'n') $value .= "\n";
                    elseif ($escape === 't') $value .= "\t";
                    elseif ($escape === 'x' && $i + 2 <= $length &&
                        preg_match('/\A[0-7][0-9a-f]\z/', substr($source, $i, 2))) {
                        $value .= chr(hexdec(substr($source, $i, 2)));
                        $i += 2;
                    } else $this->problem('syntax error', $column);
                }
                if ($i === $length) $this->problem('syntax error', $column);
                ++$i;
                $this->tokens[] = new Token('string', $value, $column);
            } elseif ($c === '<') {
                $end = strpos($source, '>', $i + 1);
                if ($end === false) $this->problem('syntax error', $column);
                $hex = substr($source, $i + 1, $end - $i - 1);
                if (!validHex($hex)) $this->problem('syntax error', $column);
                $this->tokens[] = new Token('bytes', hex2bin($hex), $column);
                $i = $end + 1;
            } elseif ($c === '-' || asciiDigit($c)) {
                $start = $i;
                if ($c === '-') ++$i;
                $digits = $i;
                while ($i < $length && asciiDigit($source[$i])) ++$i;
                if ($digits === $i) $this->problem('syntax error', $column);
                $this->tokens[] = new Token('integer', (int)substr($source, $start, $i - $start), $column);
            } elseif (asciiLetter($c) || $c === '_') {
                $start = $i++;
                while ($i < $length && (asciiLetter($source[$i]) || asciiDigit($source[$i]) || $source[$i] === '_')) ++$i;
                $this->tokens[] = new Token('name', substr($source, $start, $i - $start), $column);
            } else $this->problem('syntax error', $column);
        }
        $this->tokens[] = new Token('end', null, $length + 1);
    }

    private function problem(string $reason, int $column): never
    {
        throw new CodecError("$reason at column $column");
    }

    private function expect(string $kind): Token
    {
        $token = $this->tokens[$this->position];
        if ($token->kind !== $kind) $this->problem('syntax error', $token->column);
        ++$this->position;
        return $token;
    }

    public function finish(): void { $this->expect('end'); }

    public function message(SchemaType $type): Message
    {
        $this->expect('{');
        $message = new Message($type);
        $seen = $groups = [];
        if ($this->tokens[$this->position]->kind !== '}') {
            while (true) {
                $token = $this->tokens[$this->position];
                if ($token->kind !== 'name') $this->problem('syntax error', $token->column);
                $field = $type->namedFields[$token->value] ?? null;
                if ($field === null) $this->problem('unknown field', $token->column);
                if (isset($seen[$field->number])) $this->problem('duplicate field', $token->column);
                if ($field->group !== null && isset($groups[$field->group])) $this->problem('oneof conflict', $token->column);
                $seen[$field->number] = true;
                if ($field->group !== null) $groups[$field->group] = true;
                ++$this->position;
                $this->expect(':');
                $message->fields[$field->number] = $this->fieldValue($field);
                if ($this->tokens[$this->position]->kind !== ',') break;
                ++$this->position;
            }
        }
        $closing = $this->expect('}');
        foreach ($type->fields as $field)
            if ($field->required && !isset($seen[$field->number]))
                $this->problem('missing required field ' . $field->name, $closing->column);
        return $message;
    }

    public function fieldValue(Field $field): array
    {
        if (!$field->repeated) return [$this->element($field->type)];
        $token = $this->tokens[$this->position];
        if ($token->shape() === '') $this->problem('syntax error', $token->column);
        if ($token->shape() !== 'list') $this->problem('type mismatch', $token->column);
        ++$this->position;
        $values = [];
        if ($this->tokens[$this->position]->kind !== ']') {
            $values[] = $this->element($field->type);
            while ($this->tokens[$this->position]->kind === ',') {
                ++$this->position;
                $values[] = $this->element($field->type);
            }
        }
        $this->expect(']');
        return $values;
    }

    public function element(SchemaType $type): int|bool|string|Message
    {
        $token = $this->tokens[$this->position];
        $shape = match ($type->kind) {
            Kind::Boolean => 'boolean', Kind::Text => 'string', Kind::Bytes => 'bytes',
            Kind::Enumeration => 'name', Kind::Message => 'message', default => 'integer',
        };
        if ($token->shape() === '') $this->problem('syntax error', $token->column);
        if ($token->shape() !== $shape) $this->problem('type mismatch', $token->column);
        if ($shape === 'message') return $this->message($type);
        ++$this->position;
        if ($shape === 'integer' && !$type->inRange($token->value)) $this->problem('out of range', $token->column);
        if ($shape === 'name') {
            if (!isset($type->numbers[$token->value])) $this->problem('unknown enum value', $token->column);
            return $type->numbers[$token->value];
        }
        return $shape === 'boolean' ? $token->value === 'true' : $token->value;
    }
}

function asciiDigit(string $character): bool
{
    $code = ord($character);
    return $code >= 48 && $code <= 57;
}

function asciiLetter(string $character): bool
{
    $code = ord($character);
    return ($code >= 65 && $code <= 90) || ($code >= 97 && $code <= 122);
}

function validHex(string $source): bool
{
    return strlen($source) % 2 === 0 && preg_match('/\A[0-9a-f]*\z/', $source) === 1;
}

final readonly class Segment
{
    public function __construct(public Field $field, public ?int $index) {}
    public function wholeList(): bool { return $this->field->repeated && $this->index === null; }
}

final class Codec
{
    private array $explanation = [];

    public function __construct(private readonly Schema $schema) {}

    private function convert(SchemaType $type, RawValue $raw): int|bool|string
    {
        if ($type->kind === Kind::Text || $type->kind === Kind::Bytes) {
            if ($type->kind === Kind::Text) {
                for ($i = 0; $i < strlen($raw->value); ++$i)
                    if (ord($raw->value[$i]) >= 128)
                        throw new CodecError('invalid string at byte ' . ($raw->payload + $i));
            }
            return $raw->value;
        }
        if ($type->wire() === 0) $number = $raw->value;
        else {
            if ($type->kind === Kind::Fixed64 && (ord($raw->value[7]) !== 0 || ord($raw->value[6]) >= 32))
                throw new CodecError('value out of range at byte ' . $raw->position);
            $number = 0;
            for ($i = strlen($raw->value) - 1; $i >= 0; --$i) $number = $number * 256 + ord($raw->value[$i]);
        }
        if ($type->kind === Kind::SInt32 || $type->kind === Kind::SInt64)
            $number = $number % 2 === 0 ? intdiv($number, 2) : -intdiv($number, 2) - 1;
        elseif ($type->kind === Kind::SFixed32 && $number >= 2147483648) $number -= 4294967296;
        if (!$type->inRange($number) || ($type->kind === Kind::Boolean && $number > 1))
            throw new CodecError('value out of range at byte ' . $raw->position);
        if ($type->kind === Kind::Enumeration && !isset($type->members[$number]))
            throw new CodecError('unknown enum number at byte ' . $raw->position);
        return $type->kind === Kind::Boolean ? $number === 1 : $number;
    }

    private function readMessage(SchemaType $type, ByteReader $reader, bool $explain, int $depth): Message
    {
        $message = new Message($type);
        while ($reader->position < $reader->end) {
            $offset = $reader->position;
            $tag = $reader->varint();
            $number = intdiv($tag, 8);
            $wire = $tag % 8;
            if ($number === 0) throw new CodecError("invalid field number at byte $offset");
            if (!in_array($wire, [0, 1, 2, 5], true)) throw new CodecError("invalid wire type at byte $offset");
            $field = $type->fields[$number] ?? null;
            $packed = $field !== null && $field->repeated && $field->type->wire() !== 2 && $wire === 2;
            if ($field !== null && $wire !== $field->type->wire() && !$packed)
                throw new CodecError("wire type mismatch at byte $offset");
            $raw = $reader->read($wire);
            $header = str_repeat(' ', 2 * $depth) . "$offset $number " . ($field?->name ?? '?') . ' ' . wireName($wire);
            if ($wire === 2) $header .= ' ' . strlen($raw->value);
            if ($field === null) {
                $unknown = new Unknown($number, $wire, $raw->value);
                if ($explain) $this->explanation[] = $header . ' ' . rawText($unknown);
                else $message->unknown[] = $unknown;
                continue;
            }
            $values = [];
            if ($field->type->kind === Kind::Message) {
                if ($explain) $this->explanation[] = $header;
                $child = new ByteReader($reader->data, $raw->payload, $raw->payload + strlen($raw->value));
                $values[] = $this->readMessage($field->type, $child, $explain, $depth + 1);
            } elseif ($packed) {
                $elements = new ByteReader($reader->data, $raw->payload, $raw->payload + strlen($raw->value));
                $header .= ' packed';
                while ($elements->position < $elements->end) {
                    $value = $this->convert($field->type, $elements->read($field->type->wire()));
                    $values[] = $value;
                    if ($explain) $header .= ' ' . valueText($field->type, $value);
                }
                if ($explain) $this->explanation[] = $header;
            } else {
                $values[] = $this->convert($field->type, $raw);
                if ($explain) $this->explanation[] = $header . ' ' . valueText($field->type, $values[0]);
            }
            if (!$explain) $message->apply($field, $values);
        }
        return $message;
    }

    private function required(Message $message, string $prefix = ''): void
    {
        foreach ($message->type->fields as $field) {
            $values = $message->values($field);
            $path = $prefix . $field->name;
            if ($field->required && $values === []) throw new CodecError("missing required field $path");
            if ($field->type->kind === Kind::Message) {
                foreach ($values as $i => $child)
                    $this->required($child, $path . ($field->repeated ? "[$i]" : '') . '.');
            }
        }
    }

    private function decode(SchemaType $type, string $bytes, bool $explain = false): Message
    {
        $message = $this->readMessage($type, new ByteReader($bytes, 0, strlen($bytes)), $explain, 0);
        if (!$explain) $this->required($message);
        elseif ($bytes === '') $this->explanation[] = '(empty)';
        return $message;
    }

    private function decodeSide(SchemaType $type, string $bytes, string $side): Message
    {
        try { return $this->decode($type, $bytes); }
        catch (CodecError $error) { throw new CodecError($error->getMessage() . " in $side"); }
    }

    private function path(SchemaType $type, string $source): array
    {
        $parts = explode('.', $source);
        $path = [];
        foreach ($parts as $i => $part) {
            if (!preg_match('/\A([a-z][a-z0-9]*(?:_[a-z0-9]+)*)(?:\[([0-9]{1,6})\])?\z/', $part, $match))
                throw new CodecError('invalid path');
            $field = $type->namedFields[$match[1]] ?? null;
            $index = isset($match[2]) ? (int)$match[2] : null;
            if ($field === null || ($index !== null && !$field->repeated))
                throw new CodecError('invalid path');
            if ($i + 1 < count($parts) && ($field->type->kind !== Kind::Message || ($field->repeated && $index === null)))
                throw new CodecError('invalid path');
            $path[] = new Segment($field, $index);
            $type = $field->type;
        }
        return $path;
    }

    private function get(Message $message, array $path): string
    {
        $current = $message;
        foreach ($path as $step => $segment) {
            $values = $current?->values($segment->field) ?? [];
            $index = $segment->index ?? 0;
            if ($step + 1 === count($path)) {
                if ($segment->wholeList()) return sequenceText($segment->field->type, $values);
                return $index < count($values) ? valueText($segment->field->type, $values[$index]) : '(none)';
            }
            $current = $index < count($values) ? $values[$index] : null;
        }
        throw new LogicException();
    }

    private function edit(Message $message, array $path, ?array $replacement): void
    {
        $current = $message;
        foreach (array_slice($path, 0, -1) as $segment) {
            $values = $current->values($segment->field);
            $index = $segment->index ?? 0;
            if ($index >= count($values)) {
                if ($replacement === null) return;
                if ($segment->index !== null) throw new CodecError('index out of range');
                $current->choose($segment->field);
                $values = [new Message($segment->field->type)];
                $current->fields[$segment->field->number] = $values;
            }
            $current = $values[$index];
        }
        $last = $path[count($path) - 1];
        $number = $last->field->number;
        if ($last->index !== null) {
            $values = $current->values($last->field);
            if ($last->index >= count($values)) {
                if ($replacement !== null) throw new CodecError('index out of range');
            } else {
                if ($replacement === null) array_splice($values, $last->index, 1);
                else $values[$last->index] = $replacement[0];
                $current->fields[$number] = $values;
            }
        } elseif ($replacement === null) unset($current->fields[$number]);
        else {
            $current->choose($last->field);
            $current->fields[$number] = $replacement;
        }
    }

    private function differences(Message $a, Message $b, string $prefix, array &$lines): void
    {
        foreach ($a->type->fields as $field) {
            $x = $a->values($field);
            $y = $b->values($field);
            for ($i = 0; $i < max(count($x), count($y)); ++$i) {
                $path = $prefix . $field->name . ($field->repeated ? "[$i]" : '');
                if ($i < count($x) && $i < count($y) && $field->type->kind === Kind::Message)
                    $this->differences($x[$i], $y[$i], $path . '.', $lines);
                elseif ($i >= count($x) || $i >= count($y) || $x[$i] !== $y[$i]) {
                    $old = $i < count($x) ? valueText($field->type, $x[$i]) : '(none)';
                    $new = $i < count($y) ? valueText($field->type, $y[$i]) : '(none)';
                    $lines[] = "$path: $old -> $new";
                }
            }
        }
    }

    private function schemaFields(SchemaType $type, array $chain, int $depth, array &$lines): void
    {
        foreach ($type->fields as $field) {
            $kind = $field->required ? 'required ' : ($field->packed ? 'repeated packed ' :
                ($field->repeated ? 'repeated ' : ($field->group !== null ? "oneof $field->group " : '')));
            $line = str_repeat(' ', 2 * $depth) . "$field->number $field->name: $kind" . $field->type->name;
            if ($field->type->kind === Kind::Enumeration) {
                $members = [];
                foreach ($field->type->members as $number => $name) $members[] = "$name=$number";
                $line .= ' (' . implode(', ', $members) . ')';
            }
            $recursive = $field->type->kind === Kind::Message && in_array($field->type, $chain, true);
            $lines[] = $line . ($recursive ? ' (recursive)' : '');
            if ($field->type->kind === Kind::Message && !$recursive)
                $this->schemaFields($field->type, [...$chain, $field->type], $depth + 1, $lines);
        }
    }

    private function hex(string $source): string
    {
        if ($source === '-') return '';
        if ($source === '' || !validHex($source)) throw new CodecError('invalid hex');
        return hex2bin($source);
    }

    public function execute(string $source): array
    {
        $words = preg_split('/ +/', $source);
        $command = $words[0];
        $minimum = match ($command) {
            'VARINT', 'ZIGZAG', 'SCHEMA' => 2,
            'ENCODE', 'SIZE', 'DECODE', 'LITERAL', 'JSON', 'CANON', 'EXPLAIN' => 3,
            'GET', 'CLEAR', 'MERGE', 'DIFF' => 4,
            'PATCH' => 5,
            default => throw new CodecError('unknown command'),
        };
        $flexible = in_array($command, ['ENCODE', 'SIZE', 'PATCH'], true);
        if (count($words) < $minimum || (!$flexible && count($words) !== $minimum))
            throw new CodecError('wrong number of arguments');
        if ($command === 'VARINT' || $command === 'ZIGZAG') {
            if (!preg_match('/\A-?[0-9]{1,18}\z/', $words[1])) throw new CodecError('invalid number');
            $number = (int)$words[1];
            $valid = $command === 'VARINT' ? $number >= 0 && $number <= 9007199254740991 :
                $number >= -4503599627370496 && $number <= 4503599627370495;
            if (!$valid) throw new CodecError('invalid number');
            $value = $command === 'ZIGZAG' ? zigzag($number) : $number;
            return [($command === 'ZIGZAG' ? "$value " : '') . hexText(varint($value))];
        }
        $type = $this->schema->types[$words[1]] ?? null;
        if ($type === null || $type->kind !== Kind::Message) throw new CodecError('unknown message type');
        $data = in_array($command, ['SCHEMA', 'ENCODE', 'SIZE'], true) ? '' : $this->hex($words[2]);
        $second = $command === 'MERGE' || $command === 'DIFF' ? $this->hex($words[3]) : '';
        $path = in_array($command, ['GET', 'PATCH', 'CLEAR'], true) ? $this->path($type, $words[3]) : [];
        if ($command === 'SCHEMA') {
            $lines = [$type->name];
            $this->schemaFields($type, [$type], 1, $lines);
            return $lines;
        }
        if ($command === 'ENCODE' || $command === 'SIZE') {
            $literal = new Literal(rest($source, 2));
            $message = $literal->message($type);
            $literal->finish();
            $encoded = encode($message);
            if ($command === 'ENCODE') return [hexText($encoded)];
            $line = (string)strlen($encoded);
            foreach ($type->fields as $field) {
                $values = $message->values($field);
                if ($values !== []) $line .= ' ' . $field->name . '=' . strlen(encodeField($field, $values));
            }
            return [$line];
        }
        if ($command === 'EXPLAIN') {
            $this->explanation = [];
            $this->decode($type, $data, true);
            return $this->explanation;
        }
        if ($command === 'MERGE') return textMessage($this->decode($type, $data . $second));
        if ($command === 'DIFF') {
            $a = $this->decodeSide($type, $data, 'first');
            $b = $this->decodeSide($type, $second, 'second');
            $lines = [];
            $this->differences($a, $b, '', $lines);
            return $lines === [] ? ['SAME'] : $lines;
        }
        $message = $this->decode($type, $data);
        if ($command === 'DECODE') return textMessage($message);
        if ($command === 'LITERAL' || $command === 'JSON') return [messageText($message, $command === 'JSON')];
        if ($command === 'GET') return [$this->get($message, $path)];
        if ($command === 'PATCH') {
            $literal = new Literal(rest($source, 4));
            $last = $path[count($path) - 1];
            $replacement = $last->wholeList() ? $literal->fieldValue($last->field) : [$literal->element($last->field->type)];
            $literal->finish();
            $this->edit($message, $path, $replacement);
            $this->required($message);
        } elseif ($command === 'CLEAR') {
            $this->edit($message, $path, null);
            $this->required($message);
        }
        return [hexText(encode($message))];
    }
}

function rest(string $source, int $separators): string
{
    $position = 0;
    for ($i = 0; $i < $separators; ++$i) $position = strpos($source, ' ', $position) + 1;
    return substr($source, $position);
}

$schema = new Schema();
$codec = new Codec($schema);
$count = (int)inputLine();
for ($i = 0; $i < $count; ++$i) {
    try { $lines = $codec->execute(inputLine()); }
    catch (CodecError $error) { $lines = ['ERROR ' . $error->getMessage()]; }
    foreach ($lines as $line) echo $line, "\n";
}
