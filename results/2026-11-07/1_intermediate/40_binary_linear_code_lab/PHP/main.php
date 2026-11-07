<?php
declare(strict_types=1);

final class CommandError extends RuntimeException {}

function fail(string $reason): never
{
    throw new CommandError($reason);
}
function yes(bool $value): string
{
    return $value ? "yes" : "no";
}
function bit(int $word, int $length, int $column): int
{
    return ($word >> ($length - $column - 1)) & 1;
}
function bits(int $word, int $length): string
{
    return str_pad(decbin($word), $length, "0", STR_PAD_LEFT);
}
function weight(int $word): int
{
    $count = 0;
    while ($word !== 0) {
        $word &= $word - 1;
        ++$count;
    }
    return $count;
}
function degree(int $word): int
{
    $degree = -1;
    while ($word !== 0) {
        $word >>= 1;
        ++$degree;
    }
    return $degree;
}
function dividePolynomial(int $dividend, int $divisor): array
{
    $quotient = 0;
    $degree = degree($divisor);
    while ($dividend !== 0 && degree($dividend) >= $degree) {
        $shift = degree($dividend) - $degree;
        $quotient ^= 1 << $shift;
        $dividend ^= $divisor << $shift;
    }
    return [$quotient, $dividend];
}
function basis(array $rows, int $length): array
{
    $pivots = array_fill(0, $length, 0);
    $kept = [];
    foreach ($rows as $original) {
        $row = $original;
        for ($column = 0; $column < $length; ++$column) {
            if (bit($row, $length, $column) === 0) {
                continue;
            }
            if ($pivots[$column] !== 0) {
                $row ^= $pivots[$column];
            } else {
                $pivots[$column] = $row;
                $kept[] = $original;
                break;
            }
        }
    }
    return $kept;
}
function rref(array $rows, int $length): array
{
    $columns = [];
    for ($column = 0; $column < $length; ++$column) {
        $pivot = count($columns);
        $found = $pivot;
        while ($found < count($rows) && bit($rows[$found], $length, $column) === 0) {
            ++$found;
        }
        if ($found === count($rows)) {
            continue;
        }
        [$rows[$pivot], $rows[$found]] = [$rows[$found], $rows[$pivot]];
        foreach ($rows as $index => $row) {
            if ($index !== $pivot && bit($row, $length, $column) !== 0) {
                $rows[$index] ^= $rows[$pivot];
            }
        }
        $columns[] = $column;
    }
    return [array_slice($rows, 0, count($columns)), $columns];
}
function nullspace(array $original, int $length): array
{
    [$rows, $columns] = rref($original, $length);
    $result = [];
    for ($column = 0; $column < $length; ++$column) {
        if (in_array($column, $columns, true)) {
            continue;
        }
        $word = 1 << ($length - $column - 1);
        foreach ($rows as $index => $row) {
            if (bit($row, $length, $column) !== 0) {
                $word |= 1 << ($length - $columns[$index] - 1);
            }
        }
        $result[] = $word;
    }
    return $result;
}
function span(array $rows): array
{
    $words = [0];
    foreach ($rows as $row) {
        $count = count($words);
        for ($index = 0; $index < $count; ++$index) {
            $words[] = $words[$index] ^ $row;
        }
    }
    return $words;
}
function distribution(array $words, int $length): array
{
    $counts = array_fill(0, $length + 1, 0);
    foreach ($words as $word) {
        ++$counts[weight($word)];
    }
    return $counts;
}
function weightList(array $counts): string
{
    $items = [];
    foreach ($counts as $index => $count) {
        if ($count !== 0) {
            $items[] = "$index:$count";
        }
    }
    return implode(" ", $items);
}
function checkDimension(int $n, int $k): void
{
    if ($k < 1 || $k > 12 || $n - $k < 1 || $n - $k > 12) {
        fail("bad dimension $n $k");
    }
}
function removeBit(int $word, int $length, int $column): int
{
    $low = $length - $column - 1;
    return (($word >> ($low + 1)) << $low) | ($word & ((1 << $low) - 1));
}
function reedMuller(int $order, int $variables): array
{
    $length = 1 << $variables;
    if ($order === 0) {
        return [(1 << $length) - 1];
    }
    $rows = [];
    foreach (reedMuller(min($order, $variables - 1), $variables - 1) as $row) {
        $rows[] = ($row << intdiv($length, 2)) | $row;
    }
    return array_merge($rows, reedMuller($order - 1, $variables - 1));
}
function gcd(int $a, int $b): int
{
    $a = abs($a);
    $b = abs($b);
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return $a;
}
function binomial(int $n, int $k): int
{
    if ($k < 0 || $k > $n) {
        return 0;
    }
    $result = 1;
    for ($j = 1; $j <= $k; ++$j) {
        $result = intdiv($result * ($n - $j + 1), $j);
    }
    return $result;
}
function volume(int $n, int $radius): int
{
    $result = 0;
    for ($i = 0; $i <= $radius; ++$i) {
        $result += binomial($n, $i);
    }
    return $result;
}
function krawtchouk(int $n, int $j, int $x): int
{
    $result = 0;
    for ($y = 0; $y <= $j; ++$y) {
        $result += ($y % 2 === 0 ? 1 : -1) * binomial($x, $y) * binomial($n - $x, $j - $y);
    }
    return $result;
}

final readonly class Decoded
{
    public function __construct(public int $error, public int $word, public int $message) {}
}

final class BinaryCode
{
    public readonly int $k;
    public readonly array $h;
    public readonly array $words;
    private array $messages = [];
    private ?array $leaders = null;

    public function __construct(
        public readonly int $n,
        public readonly array $g,
        ?array $check = null,
        public readonly ?int $polynomial = null,
    ) {
        $this->k = count($g);
        checkDimension($n, $this->k);
        $this->h = $check ?? nullspace($g, $n);
        $words = [];
        for ($message = 0; $message < 1 << $this->k; ++$message) {
            $word = $this->encode($message);
            $words[] = $word;
            $this->messages[$word] = $message;
        }
        sort($words, SORT_NUMERIC);
        $this->words = $words;
    }
    public function encoder(): string
    {
        return $this->polynomial === null ? "matrix" : "polynomial";
    }
    public function encode(int $message): int
    {
        if ($this->polynomial !== null) {
            $shifted = $message << ($this->n - $this->k);
            return $shifted | dividePolynomial($shifted, $this->polynomial)[1];
        }
        $result = 0;
        foreach ($this->g as $row => $word) {
            if (bit($message, $this->k, $row) !== 0) {
                $result ^= $word;
            }
        }
        return $result;
    }
    public function syndrome(int $word): int
    {
        $result = 0;
        foreach ($this->h as $row) {
            $result = ($result << 1) | weight($word & $row) % 2;
        }
        return $result;
    }
    public function message(int $word): int
    {
        return $this->messages[$word];
    }
    public function contains(int $word): bool
    {
        return isset($this->messages[$word]);
    }
    public function leaders(): array
    {
        if ($this->leaders !== null) {
            return $this->leaders;
        }
        $leaders = array_fill(0, 1 << ($this->n - $this->k), -1);
        $leaders[0] = 0;
        $remaining = count($leaders) - 1;
        for ($count = 1; $remaining > 0; ++$count) {
            for ($word = (1 << $count) - 1; $word < 1 << $this->n; ) {
                $syndrome = $this->syndrome($word);
                if ($leaders[$syndrome] === -1) {
                    $leaders[$syndrome] = $word;
                    if (--$remaining === 0) {
                        break;
                    }
                }
                $lowest = $word & -$word;
                $next = $word + $lowest;
                $word = $next | intdiv(($next ^ $word) >> 2, $lowest);
            }
        }
        return $this->leaders = $leaders;
    }
    public function decode(int $received): Decoded
    {
        $error = $this->leaders()[$this->syndrome($received)];
        $word = $received ^ $error;
        return new Decoded($error, $word, $this->messages[$word]);
    }
    public function decodedText(Decoded $result): string
    {
        return "codeword " .
            bits($result->word, $this->n) .
            " message " .
            bits($result->message, $this->k) .
            " error " .
            bits($result->error, $this->n) .
            " weight " .
            weight($result->error);
    }
}

enum Argument
{
    case Name;
    case Code;
    case Number;
    case Bits;
    case Erasure;
}
final readonly class Format
{
    public function __construct(
        public array $fixed,
        public ?Argument $repeated = null,
        public int $maximum = 0,
        public bool $defining = false,
    ) {}
}

final class Laboratory
{
    private array $codes = [];
    private array $formats;

    public function __construct()
    {
        $name = Argument::Name;
        $code = Argument::Code;
        $number = Argument::Number;
        $bits = Argument::Bits;
        $this->formats = [
            "GEN" => new Format([$name], $bits, 24, true),
            "PCHECK" => new Format([$name], $bits, 24, true),
            "HAMMING" => new Format([$name, $number], defining: true),
            "SIMPLEX" => new Format([$name, $number], defining: true),
            "REPETITION" => new Format([$name, $number], defining: true),
            "PARITY" => new Format([$name, $number], defining: true),
            "RM" => new Format([$name, $number, $number], defining: true),
            "CYCLIC" => new Format([$name, $number, $bits], defining: true),
            "DUAL" => new Format([$name, $code], defining: true),
            "EXTEND" => new Format([$name, $code], defining: true),
            "PUNCTURE" => new Format([$name, $code, $number], defining: true),
            "SHORTEN" => new Format([$name, $code, $number], defining: true),
            "AUGMENT" => new Format([$name, $code], defining: true),
            "EXPURGATE" => new Format([$name, $code], defining: true),
            "PERMUTE" => new Format([$name, $code], $number, 24, true),
            "DIRECTSUM" => new Format([$name, $code, $code], defining: true),
            "UUV" => new Format([$name, $code, $code], defining: true),
            "PRODUCT" => new Format([$name, $code, $code], defining: true),
            "LIST" => new Format([]),
            "DELETE" => new Format([$code]),
            "SHOW" => new Format([$code]),
            "INFO" => new Format([$code]),
            "SYSTEMATIC" => new Format([$code]),
            "WEIGHTS" => new Format([$code]),
            "COVERING" => new Format([$code]),
            "BURST" => new Format([$code]),
            "TRELLIS" => new Format([$code]),
            "STDARRAY" => new Format([$code]),
            "EQUAL" => new Format([$code, $code]),
            "ENCODE" => new Format([$code, $bits]),
            "SYNDROME" => new Format([$code, $bits]),
            "DECODE" => new Format([$code, $bits]),
            "BOUNDED" => new Format([$code, $number, $bits]),
            "COSET" => new Format([$code, $bits]),
            "ERASURE" => new Format([$code, Argument::Erasure]),
            "INTERLEAVE" => new Format([$code, $number, $number], $bits, 8),
            "CRC" => new Format([$bits, $bits]),
            "CRCCHECK" => new Format([$bits, $bits]),
            "FACTOR" => new Format([$number]),
            "MACWILLIAMS" => new Format([$number], $number, 25),
            "BOUNDS" => new Format([$number, $number]),
        ];
    }
    private static function valid(string $word, Argument $kind): bool
    {
        $pattern = match ($kind) {
            Argument::Name, Argument::Code => '/^[A-Za-z][A-Za-z0-9]{0,7}$/D',
            Argument::Number => '/^(0|[1-9][0-9]{0,3})$/D',
            Argument::Bits => '/^[01]{1,30}$/D',
            Argument::Erasure => '/^[01?]{1,30}$/D',
        };
        return preg_match($pattern, $word) === 1;
    }
    private function parse(string $line): array
    {
        $words = explode(" ", $line);
        $verb = array_shift($words);
        $format = $this->formats[$verb] ?? null;
        if ($format === null) {
            fail("unknown command $verb");
        }
        $extra = count($words) - count($format->fixed);
        if ($format->repeated === null ? $extra !== 0 : $extra < 1 || $extra > $format->maximum) {
            fail("bad arguments");
        }
        foreach ($words as $index => $word) {
            if (!self::valid($word, $format->fixed[$index] ?? $format->repeated)) {
                fail("bad arguments");
            }
        }
        foreach ($format->fixed as $index => $kind) {
            if ($kind === Argument::Code && !isset($this->codes[$words[$index]])) {
                fail("no code " . $words[$index]);
            }
        }
        return [$verb, $words, $format];
    }
    private function define(string $verb, array $args): array
    {
        $name = $args[0];
        $n = 0;
        $g = [];
        $h = null;
        $polynomial = null;
        switch ($verb) {
            case "GEN":
            case "PCHECK":
                $n = strlen($args[1]);
                $rows = [];
                foreach (array_slice($args, 1) as $word) {
                    if (strlen($word) !== $n) {
                        fail("bad length");
                    }
                    $rows[] = (int) bindec($word);
                }
                $rows = basis($rows, $n);
                if ($verb === "GEN") {
                    $g = $rows;
                } else {
                    $h = $rows;
                    $g = nullspace($h, $n);
                }
                break;
            case "HAMMING":
            case "SIMPLEX":
                $r = (int) $args[1];
                if ($r < 2 || $r > 4) {
                    fail("bad parameter");
                }
                $n = (1 << $r) - 1;
                $rows = array_fill(0, $r, 0);
                for ($column = 1; $column <= $n; ++$column) {
                    for ($row = 0; $row < $r; ++$row) {
                        $rows[$row] = ($rows[$row] << 1) | bit($column, $r, $row);
                    };
                }
                if ($verb === "HAMMING") {
                    $h = $rows;
                    $g = nullspace($h, $n);
                } else {
                    $g = $rows;
                }
                break;
            case "REPETITION":
            case "PARITY":
                $n = (int) $args[1];
                if ($n < 2 || $n > 24) {
                    fail("bad parameter");
                }
                if ($verb === "REPETITION") {
                    $g = [(1 << $n) - 1];
                } else {
                    for ($row = 0; $row < $n - 1; ++$row) {
                        $g[] = (1 << ($n - $row - 1)) | 1;
                    };
                }
                break;
            case "RM":
                $order = (int) $args[1];
                $variables = (int) $args[2];
                if ($variables < 1 || $variables > 4 || $order > $variables) {
                    fail("bad parameter");
                }
                $n = 1 << $variables;
                $g = reedMuller($order, $variables);
                break;
            case "CYCLIC":
                $n = (int) $args[1];
                $text = $args[2];
                if (
                    $n < 2 ||
                    $n > 24 ||
                    $text[0] === "0" ||
                    strlen($text) < 2 ||
                    strlen($text) > $n
                ) {
                    fail("bad parameter");
                }
                $polynomial = (int) bindec($text);
                if (dividePolynomial((1 << $n) | 1, $polynomial)[1] !== 0) {
                    fail("not a divisor");
                }
                $d = strlen($text) - 1;
                $k = $n - $d;
                for ($row = 0; $row < $k; ++$row) {
                    $g[] = $polynomial << ($k - $row - 1);
                }
                $h = array_fill(0, $d, 0);
                for ($column = 0; $column < $n; ++$column) {
                    $remainder = dividePolynomial(1 << ($n - $column - 1), $polynomial)[1];
                    for ($row = 0; $row < $d; ++$row) {
                        $h[$row] = ($h[$row] << 1) | bit($remainder, $d, $row);
                    }
                }
                break;
            case "DUAL":
                $source = $this->codes[$args[1]];
                $n = $source->n;
                $g = $source->h;
                $h = $source->g;
                break;
            case "EXTEND":
                $source = $this->codes[$args[1]];
                $n = $source->n + 1;
                foreach ($source->g as $row) {
                    $g[] = ($row << 1) | weight($row) % 2;
                }
                break;
            case "PUNCTURE":
            case "SHORTEN":
                $source = $this->codes[$args[1]];
                $column = (int) $args[2] - 1;
                if ($column < 0 || $column >= $source->n) {
                    fail("bad position");
                }
                $rows = $source->g;
                if ($verb === "SHORTEN") {
                    foreach ($rows as $pivot => $z) {
                        if (bit($z, $source->n, $column) === 0) {
                            continue;
                        }
                        array_splice($rows, $pivot, 1);
                        foreach ($rows as $index => $row) {
                            if (bit($row, $source->n, $column) !== 0) {
                                $rows[$index] ^= $z;
                            }
                        }
                        break;
                    }
                }
                $n = $source->n - 1;
                foreach ($rows as $row) {
                    $g[] = removeBit($row, $source->n, $column);
                }
                if ($verb === "PUNCTURE") {
                    $g = basis($g, $n);
                }
                break;
            case "AUGMENT":
                $source = $this->codes[$args[1]];
                $n = $source->n;
                $g = basis([...$source->g, (1 << $n) - 1], $n);
                break;
            case "EXPURGATE":
                $source = $this->codes[$args[1]];
                $n = $source->n;
                $g = $source->g;
                foreach ($g as $pivot => $z) {
                    if (weight($z) % 2 === 0) {
                        continue;
                    }
                    array_splice($g, $pivot, 1);
                    foreach ($g as $index => $row) {
                        if (weight($row) % 2 !== 0) {
                            $g[$index] ^= $z;
                        }
                    }
                    break;
                }
                break;
            case "PERMUTE":
                $source = $this->codes[$args[1]];
                $n = $source->n;
                $permutation = array_map(intval(...), array_slice($args, 2));
                $ordered = $permutation;
                sort($ordered, SORT_NUMERIC);
                if ($ordered !== range(1, $n)) {
                    fail("bad permutation");
                }
                foreach ($source->g as $row) {
                    $word = 0;
                    foreach ($permutation as $column) {
                        $word = ($word << 1) | bit($row, $n, $column - 1);
                    }
                    $g[] = $word;
                }
                break;
            case "DIRECTSUM":
            case "UUV":
            case "PRODUCT":
                $a = $this->codes[$args[1]];
                $b = $this->codes[$args[2]];
                if ($verb === "UUV" && $a->n !== $b->n) {
                    fail("bad length");
                }
                $n = $verb === "PRODUCT" ? $a->n * $b->n : $a->n + $b->n;
                checkDimension($n, $verb === "PRODUCT" ? $a->k * $b->k : $a->k + $b->k);
                if ($verb === "PRODUCT") {
                    foreach ($a->g as $x) {
                        foreach ($b->g as $y) {
                            $word = 0;
                            for ($column = 0; $column < $a->n; ++$column) {
                                $word = ($word << $b->n) | (bit($x, $a->n, $column) !== 0 ? $y : 0);
                            }
                            $g[] = $word;
                        };
                    }
                } else {
                    foreach ($a->g as $row) {
                        $g[] = ($row << $b->n) | ($verb === "UUV" ? $row : 0);
                    }
                    $g = array_merge($g, $b->g);
                }
                break;
        }
        $code = new BinaryCode($n, $g, $h, $polynomial);
        $action = isset($this->codes[$name]) ? "redefined" : "defined";
        $this->codes[$name] = $code;
        return ["$action $name n $n k {$code->k}"];
    }
    private static function systematic(string $name, BinaryCode $code): array
    {
        $n = $code->n;
        $k = $code->k;
        $rows = $code->g;
        $permutation = range(1, $n);
        for ($pivot = 0; $pivot < $k; ++$pivot) {
            $column = $pivot;
            while (true) {
                $found = $pivot;
                while ($found < $k && bit($rows[$found], $n, $column) === 0) {
                    ++$found;
                }
                if ($found < $k) {
                    break;
                }
                ++$column;
            }
            if ($column !== $pivot) {
                $mask = (1 << ($n - $pivot - 1)) | (1 << ($n - $column - 1));
                foreach ($rows as $index => $row) {
                    if (bit($row, $n, $pivot) !== bit($row, $n, $column)) {
                        $rows[$index] ^= $mask;
                    }
                }
                [$permutation[$pivot], $permutation[$column]] = [
                    $permutation[$column],
                    $permutation[$pivot],
                ];
            }
            [$rows[$pivot], $rows[$found]] = [$rows[$found], $rows[$pivot]];
            foreach ($rows as $index => $row) {
                if ($index !== $pivot && bit($row, $n, $pivot) !== 0) {
                    $rows[$index] ^= $rows[$pivot];
                }
            }
        }
        $output = ["systematic $name perm " . implode(" ", $permutation)];
        foreach ($rows as $row) {
            $output[] = "G " . bits($row, $n);
        }
        for ($column = $k; $column < $n; ++$column) {
            $word = 0;
            foreach ($rows as $row) {
                $word = ($word << 1) | bit($row, $n, $column);
            }
            $word = ($word << ($n - $k)) | (1 << ($n - $column - 1));
            $output[] = "H " . bits($word, $n);
        }
        return $output;
    }
    private static function burst(string $name, BinaryCode $code): array
    {
        $detect = $code->n;
        foreach ($code->words as $word) {
            if ($word !== 0) {
                $detect = min($detect, degree($word) - degree($word & -$word));
            }
        }
        $seen = [0 => true];
        for ($length = 1; $length <= $code->n; ++$length) {
            for ($start = 0; $start + $length <= $code->n; ++$start) {
                $limit = $length === 1 ? 1 : 1 << ($length - 2);
                for ($middle = 0; $middle < $limit; ++$middle) {
                    $pattern = $length === 1 ? 1 : (1 << ($length - 1)) | ($middle << 1) | 1;
                    $syndrome = $code->syndrome($pattern << ($code->n - $start - $length));
                    if (isset($seen[$syndrome])) {
                        return ["burst $name detect $detect correct " . ($length - 1)];
                    }
                    $seen[$syndrome] = true;
                }
            }
        }
        throw new LogicException("A nonzero codeword has zero syndrome");
    }
    private static function interleave(string $name, BinaryCode $code, array $args): array
    {
        $start = (int) $args[1];
        $length = (int) $args[2];
        $depth = count($args) - 3;
        foreach (array_slice($args, 3) as $word) {
            if (strlen($word) !== $code->k) {
                fail("bad length");
            }
        }
        if ($start < 1 || $length < 1 || $start + $length - 1 > $depth * $code->n) {
            fail("bad burst");
        }
        $sentWords = [];
        foreach (array_slice($args, 3) as $word) {
            $sentWords[] = $code->encode((int) bindec($word));
        }
        $receivedWords = array_fill(0, $depth, 0);
        $sent = "";
        $received = "";
        for ($column = 0; $column < $code->n; ++$column) {
            for ($row = 0; $row < $depth; ++$row) {
                $position = $column * $depth + $row + 1;
                $original = bit($sentWords[$row], $code->n, $column);
                $changed = $original ^ (int) ($position >= $start && $position < $start + $length);
                $sent .= (string) $original;
                $received .= (string) $changed;
                $receivedWords[$row] = ($receivedWords[$row] << 1) | $changed;
            };
        }
        $output = [
            "interleave $name depth $depth burst $start $length",
            "sent $sent",
            "recv $received",
        ];
        $correct = 0;
        foreach ($receivedWords as $row => $receivedWord) {
            $decoded = $code->decode($receivedWord);
            $message = bits($decoded->message, $code->k);
            $ok = $message === $args[$row + 3];
            if ($ok) {
                ++$correct;
            }
            $output[] =
                "row " .
                ($row + 1) .
                " errors " .
                weight($receivedWord ^ $sentWords[$row]) .
                " corrected " .
                weight($decoded->error) .
                " message $message " .
                ($ok ? "ok" : "wrong");
        }
        $output[] = "result ok $correct wrong " . ($depth - $correct);
        return $output;
    }
    private static function independent(string $verb, array $args): array
    {
        if ($verb === "CRC" || $verb === "CRCCHECK") {
            [$generator, $text] = $args;
            if ($generator[0] === "0" || strlen($generator) < 2 || strlen($generator) > 17) {
                fail("bad parameter");
            }
            $degree = strlen($generator) - 1;
            if ($verb === "CRC" && strlen($text) + $degree > 30) {
                fail("bad length");
            }
            $word = (int) bindec($text);
            $remainder = dividePolynomial(
                $verb === "CRC" ? $word << $degree : $word,
                (int) bindec($generator),
            )[1];
            $suffix = bits($remainder, $degree);
            return [
                $verb === "CRC"
                    ? "crc remainder $suffix frame $text$suffix"
                    : "crccheck " . ($remainder === 0 ? "ok" : "error") . " remainder $suffix",
            ];
        }
        $n = (int) $args[0];
        if ($verb === "BOUNDS") {
            $distance = (int) $args[1];
            if ($distance < 1 || $distance > $n || $n > 24) {
                fail("bad parameter");
            }
            $volume = volume($n, intdiv($distance - 1, 2));
            $hamming = 0;
            $griesmer = 0;
            $sum = 0;
            for ($k = 0; $k <= $n; ++$k) {
                if ((1 << $k) * $volume <= 1 << $n) {
                    $hamming = $k;
                }
            }
            for ($k = 1; $k <= $n; ++$k) {
                $denominator = 1 << ($k - 1);
                $sum += intdiv($distance + $denominator - 1, $denominator);
                if ($sum <= $n) {
                    $griesmer = $k;
                }
            }
            return [
                "bounds n $n d $distance singleton " .
                ($n - $distance + 1) .
                " hamming $hamming griesmer $griesmer",
            ];
        }
        if ($n < 1 || $n > 24) {
            fail("bad parameter");
        }
        if ($verb === "FACTOR") {
            $remaining = (1 << $n) | 1;
            $divisors = 1;
            $factors = [];
            for ($candidate = 2; 2 * degree($candidate) <= degree($remaining); ++$candidate) {
                $exponent = 0;
                while (true) {
                    [$quotient, $remainder] = dividePolynomial($remaining, $candidate);
                    if ($remainder !== 0) {
                        break;
                    }
                    $remaining = $quotient;
                    ++$exponent;
                }
                if ($exponent > 0) {
                    $factors[] = decbin($candidate) . "^$exponent";
                    $divisors *= $exponent + 1;
                }
            }
            if ($remaining > 1) {
                $factors[] = decbin($remaining) . "^1";
                $divisors *= 2;
            }
            return ["factor $n " . implode(" ", $factors) . " divisors $divisors"];
        }
        if (count($args) !== $n + 2) {
            fail("bad length");
        }
        if ((int) $args[1] !== 1) {
            fail("bad parameter");
        }
        $counts = array_map(intval(...), array_slice($args, 1));
        $size = array_sum($counts);
        $feasible = ($size & ($size - 1)) === 0;
        $transformed = [];
        for ($j = 0; $j <= $n; ++$j) {
            $numerator = 0;
            for ($x = 0; $x <= $n; ++$x) {
                $numerator += $counts[$x] * krawtchouk($n, $j, $x);
            }
            $divisor = gcd($numerator, $size);
            $p = intdiv($numerator, $divisor);
            $q = intdiv($size, $divisor);
            $transformed[] = $q === 1 ? (string) $p : "$p/$q";
            if ($q !== 1 || $p < 0) {
                $feasible = false;
            }
        }
        return [
            "macwilliams n $n size $size",
            "dual " . implode(" ", $transformed),
            "feasible " . yes($feasible),
        ];
    }
    public function process(string $line): array
    {
        [$verb, $args, $format] = $this->parse($line);
        if ($format->defining) {
            return $this->define($verb, $args);
        }
        if (in_array($verb, ["CRC", "CRCCHECK", "FACTOR", "MACWILLIAMS", "BOUNDS"], true)) {
            return self::independent($verb, $args);
        }
        if ($verb === "LIST") {
            $names = array_keys($this->codes);
            sort($names, SORT_STRING);
            $output = ["codes " . count($names)];
            foreach ($names as $name) {
                $code = $this->codes[$name];
                $output[] = "$name n {$code->n} k {$code->k} encoder " . $code->encoder();
            }
            return $output;
        }
        $name = $args[0];
        if ($verb === "DELETE") {
            unset($this->codes[$name]);
            return ["deleted $name"];
        }
        $code = $this->codes[$name];
        $n = $code->n;
        $k = $code->k;
        switch ($verb) {
            case "SHOW":
                $output = ["code $name n $n k $k encoder " . $code->encoder()];
                if ($code->polynomial !== null) {
                    $output[] =
                        "poly g " .
                        bits($code->polynomial, $n - $k + 1) .
                        " h " .
                        bits(dividePolynomial((1 << $n) | 1, $code->polynomial)[0], $k + 1);
                }
                foreach ($code->g as $row) {
                    $output[] = "G " . bits($row, $n);
                }
                foreach ($code->h as $row) {
                    $output[] = "H " . bits($row, $n);
                }
                return $output;
            case "INFO":
                $distance = $n;
                foreach ($code->words as $word) {
                    if ($word !== 0) {
                        $distance = min($distance, weight($word));
                    }
                }
                $t = intdiv($distance - 1, 2);
                $divisor = gcd($n, $k);
                $cyclic = true;
                foreach ($code->g as $row) {
                    if (!$code->contains((($row << 1) & ((1 << $n) - 1)) | ($row >> ($n - 1)))) {
                        $cyclic = false;
                    }
                }
                $generator = $cyclic ? decbin($code->words[1]) : "no";
                return [
                    "info $name n $n k $k rate " .
                    intdiv($k, $divisor) .
                    "/" .
                    intdiv($n, $divisor) .
                    " d $distance t $t perfect " .
                    yes(volume($n, $t) === 1 << ($n - $k)) .
                    " mds " .
                    yes($distance === $n - $k + 1) .
                    " cyclic $generator",
                ];
            case "SYSTEMATIC":
                return self::systematic($name, $code);
            case "WEIGHTS":
                $a = distribution($code->words, $n);
                $b = distribution(span($code->h), $n);
                $orthogonal = true;
                foreach ($code->g as $x) {
                    foreach ($code->g as $y) {
                        if (weight($x & $y) % 2 !== 0) {
                            $orthogonal = false;
                        }
                    };
                }
                return [
                    "weights $name " . weightList($a),
                    "dual $name " . weightList($b),
                    "duality $name self-orthogonal " .
                    yes($orthogonal) .
                    " self-dual " .
                    yes($orthogonal && $n === 2 * $k) .
                    " formally-self-dual " .
                    yes($a === $b),
                ];
            case "COVERING":
                $counts = distribution($code->leaders(), $n);
                $radius = $n;
                while ($counts[$radius] === 0) {
                    --$radius;
                }
                $items = [];
                for ($i = 0; $i <= $radius; ++$i) {
                    $items[] = "$i:{$counts[$i]}";
                }
                return ["covering $name radius $radius leaders " . implode(" ", $items)];
            case "BURST":
                return self::burst($name, $code);
            case "TRELLIS":
                $profile = [];
                for ($cut = 0; $cut <= $n; ++$cut) {
                    $right = $n - $cut;
                    $prefix = [];
                    $suffix = [];
                    foreach ($code->g as $row) {
                        $prefix[] = $row >> $right;
                        $suffix[] = $row & ((1 << $right) - 1);
                    }
                    $profile[] = count(basis($prefix, $cut)) + count(basis($suffix, $right)) - $k;
                }
                return [
                    "trellis $name profile " . implode(" ", $profile) . " max " . max($profile),
                ];
            case "STDARRAY":
                if ($n - $k > 6 || $k > 4) {
                    fail("too large");
                }
                $leaders = $code->leaders();
                $syndromes = array_keys($leaders);
                usort(
                    $syndromes,
                    fn(int $a, int $b): int => weight($leaders[$a]) <=> weight($leaders[$b]) ?:
                    $leaders[$a] <=> $leaders[$b],
                );
                $output = [
                    "stdarray $name rows " . count($leaders) . " columns " . count($code->words),
                ];
                foreach ($syndromes as $syndrome) {
                    $row = [];
                    foreach ($code->words as $word) {
                        $row[] = bits($word ^ $leaders[$syndrome], $n);
                    }
                    $output[] = bits($syndrome, $n - $k) . ": " . implode(" ", $row);
                }
                return $output;
            case "EQUAL":
                $other = $this->codes[$args[1]];
                if ($n !== $other->n) {
                    return ["equal $name {$args[1]} no lengths $n {$other->n}"];
                }
                $common = $k + $other->k - count(basis(array_merge($code->g, $other->g), $n));
                return [
                    "equal $name {$args[1]} " .
                    yes($k === $common && $other->k === $common) .
                    " intersection $common",
                ];
            case "ENCODE":
                if (strlen($args[1]) !== $k) {
                    fail("bad length");
                }
                return [
                    "encode $name message {$args[1]} codeword " .
                    bits($code->encode((int) bindec($args[1])), $n),
                ];
            case "SYNDROME":
            case "DECODE":
            case "BOUNDED":
            case "COSET":
                $text = $args[$verb === "BOUNDED" ? 2 : 1];
                if (strlen($text) !== $n) {
                    fail("bad length");
                }
                $word = (int) bindec($text);
                $syndrome = $code->syndrome($word);
                if ($verb === "SYNDROME") {
                    return [
                        "syndrome $name " .
                        bits($syndrome, $n - $k) .
                        " codeword " .
                        yes($syndrome === 0),
                    ];
                }
                $decoded = $code->decode($word);
                if ($verb === "COSET") {
                    $coset = array_map(fn(int $value): int => $value ^ $word, $code->words);
                    return [
                        "coset $name syndrome " .
                        bits($syndrome, $n - $k) .
                        " leader " .
                        bits($decoded->error, $n) .
                        " weights " .
                        weightList(distribution($coset, $n)),
                    ];
                }
                if ($verb === "BOUNDED" && weight($decoded->error) > (int) $args[1]) {
                    return ["bounded $name fail weight " . weight($decoded->error)];
                }
                return [strtolower($verb) . " $name " . $code->decodedText($decoded)];
            case "ERASURE":
                $text = $args[1];
                if (strlen($text) !== $n) {
                    fail("bad length");
                }
                $mask = 0;
                $known = 0;
                $erased = 0;
                foreach (str_split($text) as $digit) {
                    $mask = ($mask << 1) | (int) ($digit !== "?");
                    $known = ($known << 1) | (int) ($digit === "1");
                    if ($digit === "?") {
                        ++$erased;
                    }
                }
                $candidates = array_values(
                    array_filter($code->words, fn(int $word): bool => ($word & $mask) === $known),
                );
                $output = "erasure $name erased $erased candidates " . count($candidates);
                if (count($candidates) === 1) {
                    $output .=
                        " codeword " .
                        bits($candidates[0], $n) .
                        " message " .
                        bits($code->message($candidates[0]), $k);
                }
                return [$output];
            case "INTERLEAVE":
                return self::interleave($name, $code, $args);
        }
        throw new LogicException("Unreachable command");
    }
}

$count = (int) trim(fgets(STDIN));
$laboratory = new Laboratory();
for ($i = 0; $i < $count; ++$i) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        foreach ($laboratory->process($line) as $output) {
            echo $output, "\n";
        }
    } catch (CommandError $error) {
        echo "error: ", $error->getMessage(), "\n";
    }
}
