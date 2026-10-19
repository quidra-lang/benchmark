<?php
declare(strict_types=1);

enum Mode: string { case RNE = 'RNE'; case RNA = 'RNA'; case RTZ = 'RTZ'; case RUP = 'RUP'; case RDN = 'RDN'; }
enum Operation: string { case ADD = 'ADD'; case SUB = 'SUB'; case MUL = 'MUL'; case DIV = 'DIV'; case SQRT = 'SQRT'; case FMA = 'FMA'; }
enum RealKind { case Finite; case Infinity; case NaN; }

final class CommandError extends RuntimeException {}
function fail(string $message): never { throw new CommandError($message); }

final class Flags
{
    public const INVALID = 1, DIVBYZERO = 2, OVERFLOW = 4, UNDERFLOW = 8, INEXACT = 16;

    public static function text(int $flags): string
    {
        $names = [];
        foreach (['invalid', 'divbyzero', 'overflow', 'underflow', 'inexact'] as $i => $name) {
            if (($flags & (1 << $i)) !== 0) $names[] = $name;
        }
        return 'flags=' . ($names === [] ? 'none' : implode(',', $names));
    }
}

final readonly class Result
{
    public function __construct(public int $pattern, public int $flags = 0) {}
}
final readonly class Units
{
    public function __construct(public int $whole, public bool $inexact) {}
}
final readonly class Fields
{
    public function __construct(public bool $negative, public int $exponent, public int $fraction, public int $q) {}
}

function bitLength(int $value): int
{
    $length = 0;
    for (; $value !== 0; $value >>= 1) $length++;
    return $length;
}

/** @return array{int, int} */
function scaled(int $n, int $d, int $exponent): array
{
    return $exponent >= 0 ? [$n << $exponent, $d] : [$n, $d << -$exponent];
}

function gcd(int $a, int $b): int
{
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    return $a;
}

function integerSqrt(int $value): int
{
    if ($value === 0) return 0;
    $root = 1 << intdiv(bitLength($value) + 1, 2);
    while (true) {
        $next = intdiv($root + intdiv($value, $root), 2);
        if ($next >= $root) return $root;
        $root = $next;
    }
}

function increment(Mode $mode, bool $negative, int $whole, bool $inexact, int $halfway): bool
{
    if (!$inexact) return false;
    return match ($mode) {
        Mode::RNE => $halfway > 0 || $halfway === 0 && $whole % 2 !== 0,
        Mode::RNA => $halfway >= 0,
        Mode::RTZ => false,
        Mode::RUP => !$negative,
        Mode::RDN => $negative,
    };
}

function roundUnits(Exact $value, int $exponent, Mode $mode): Units
{
    [$n, $d] = scaled($value->numerator, $value->denominator, $value->exponent - $exponent);
    $whole = intdiv($n, $d);
    $remainder = $n % $d;
    if (increment($mode, $value->negative, $whole, $remainder !== 0, 2 * $remainder - $d)) $whole++;
    return new Units($whole, $remainder !== 0);
}

function roundSqrtUnits(Exact $value, int $exponent, Mode $mode): Units
{
    [$n, $d] = scaled($value->numerator, $value->denominator, $value->exponent - 2 * $exponent);
    $whole = integerSqrt(intdiv($n, $d));
    $inexact = $whole * $whole * $d !== $n;
    $midpoint = 2 * $whole + 1;
    if (increment($mode, false, $whole, $inexact, 4 * $n - $d * $midpoint * $midpoint)) $whole++;
    return new Units($whole, $inexact);
}

// The magnitude is numerator * 2^exponent / denominator; sign also preserves -0.
final readonly class Exact
{
    public function __construct(
        public int $numerator,
        public int $exponent = 0,
        public int $denominator = 1,
        public bool $negative = false,
    ) {}

    public function negated(): self
    {
        return new self($this->numerator, $this->exponent, $this->denominator, !$this->negative);
    }

    public function log2Floor(): int
    {
        $t = bitLength($this->numerator) - bitLength($this->denominator) + $this->exponent;
        [$n, $d] = scaled($this->numerator, $this->denominator, $this->exponent - $t);
        return $n < $d ? $t - 1 : $t;
    }

    public function fraction(): string
    {
        if ($this->numerator === 0) return '0';
        [$n, $d] = scaled($this->numerator, $this->denominator, $this->exponent);
        $factor = gcd($n, $d);
        $n = intdiv($n, $factor);
        $d = intdiv($d, $factor);
        return ($this->negative ? '-' : '') . $n . ($d === 1 ? '' : '/' . $d);
    }

    public function decimal(bool $keepZeroSign = false): string
    {
        [$n, $d] = scaled($this->numerator, $this->denominator, $this->exponent);
        $text = ($this->negative && ($this->numerator !== 0 || $keepZeroSign) ? '-' : '') . intdiv($n, $d);
        $remainder = $n % $d;
        if ($remainder !== 0) {
            $text .= '.';
            while ($remainder !== 0) {
                $remainder *= 10;
                $text .= chr(48 + intdiv($remainder, $d));
                $remainder %= $d;
            }
        }
        return $text;
    }

    public static function product(self $a, self $b): self
    {
        return new self($a->numerator * $b->numerator, $a->exponent + $b->exponent,
            $a->denominator * $b->denominator, $a->negative !== $b->negative);
    }

    /** @param list<Exact> $terms */
    public static function sum(array $terms, Mode $mode): self
    {
        $exponent = null;
        foreach ($terms as $term) {
            if ($term->numerator !== 0 && ($exponent === null || $term->exponent < $exponent)) $exponent = $term->exponent;
        }
        if ($exponent === null) {
            $same = true;
            foreach ($terms as $term) $same = $same && $term->negative === $terms[0]->negative;
            return new self(0, negative: $same ? $terms[0]->negative : $mode === Mode::RDN);
        }
        // Every sum and difference here consists of dyadic terms, with denominator 1.
        $numerator = 0;
        foreach ($terms as $term) {
            if ($term->numerator === 0) continue;
            $aligned = $term->numerator << ($term->exponent - $exponent);
            $numerator += $term->negative ? -$aligned : $aligned;
        }
        return new self(abs($numerator), $exponent, negative: $numerator < 0 || $numerator === 0 && $mode === Mode::RDN);
    }
}

function binary(int $value, int $width): string { return str_pad(decbin($value), $width, '0', STR_PAD_LEFT); }
function relation(int $a, int $b): string { return $a < $b ? 'LT' : ($a > $b ? 'GT' : 'EQ'); }

final readonly class MiniFormat
{
    public int $width, $bias, $minExponent, $maxExponent, $hidden, $exponentMask, $signBit, $infinity;

    public function __construct(public string $name, public int $e, public int $m)
    {
        $this->width = 1 + $e + $m;
        $this->bias = (1 << ($e - 1)) - 1;
        $this->minExponent = 1 - $this->bias;
        $this->maxExponent = $this->bias;
        $this->hidden = 1 << $m;
        $this->exponentMask = (1 << $e) - 1;
        $this->signBit = 1 << ($e + $m);
        $this->infinity = $this->exponentMask * $this->hidden;
    }

    public function fields(int $pattern): Fields
    {
        $exponent = ($pattern >> $this->m) & $this->exponentMask;
        return new Fields(($pattern & $this->signBit) !== 0, $exponent, $pattern & ($this->hidden - 1),
            ($exponent === 0 ? $this->minExponent : $exponent - $this->bias) - $this->m);
    }
    public function isNaN(int $pattern): bool { return $this->fields($pattern)->exponent === $this->exponentMask && $this->fields($pattern)->fraction !== 0; }
    public function isSignaling(int $pattern): bool { return $this->isNaN($pattern) && $this->fields($pattern)->fraction < intdiv($this->hidden, 2); }
    public function isInfinity(int $pattern): bool { return ($pattern & ($this->signBit - 1)) === $this->infinity; }
    public function isZero(int $pattern): bool { return ($pattern & ($this->signBit - 1)) === 0; }
    public function isFinite(int $pattern): bool { return $this->fields($pattern)->exponent !== $this->exponentMask; }
    public function nan(): int { return $this->infinity + intdiv($this->hidden, 2); }
    public function zero(bool $negative): int { return $negative ? $this->signBit : 0; }
    public function inf(bool $negative): int { return $this->zero($negative) + $this->infinity; }
    public function flip(int $pattern): int { return $pattern ^ $this->signBit; }

    public function exact(int $pattern): Exact
    {
        $f = $this->fields($pattern);
        return new Exact($f->exponent === 0 ? $f->fraction : $this->hidden + $f->fraction, $f->q, negative: $f->negative);
    }
    public function bits(int $pattern): string
    {
        $f = $this->fields($pattern);
        return ($f->negative ? '1' : '0') . '|' . binary($f->exponent, $this->e) . '|' . binary($f->fraction, $this->m);
    }
    public function hex(int $pattern): string
    {
        return '0x' . str_pad(strtoupper(dechex($pattern)), intdiv($this->width + 3, 4), '0', STR_PAD_LEFT);
    }
    public function value(int $pattern): string
    {
        if ($this->isNaN($pattern)) return 'nan';
        if ($this->isInfinity($pattern)) return $this->fields($pattern)->negative ? '-inf' : 'inf';
        return $this->exact($pattern)->decimal(true);
    }
    public function patternText(int $pattern): string { return $this->bits($pattern) . ' ' . $this->hex($pattern) . ' ' . $this->value($pattern); }
    public function resultText(Result $result): string { return $this->patternText($result->pattern) . ' ' . Flags::text($result->flags); }

    private function overflow(bool $negative, Mode $mode): Result
    {
        $infinity = $mode === Mode::RNE || $mode === Mode::RNA || $mode === Mode::RUP && !$negative || $mode === Mode::RDN && $negative;
        return new Result($this->zero($negative) + ($infinity ? $this->infinity : $this->infinity - 1), Flags::OVERFLOW | Flags::INEXACT);
    }

    private function roundNonzero(bool $negative, int $t, Mode $mode, Closure $unitsAt): Result
    {
        if ($t > $this->maxExponent) return $this->overflow($negative, $mode);
        $exponent = max($t, $this->minExponent) - $this->m;
        $units = $unitsAt($exponent);
        $n = $units->whole;
        if ($n === 2 * $this->hidden) { $n = $this->hidden; $exponent++; }
        if ($exponent > $this->maxExponent - $this->m) return $this->overflow($negative, $mode);
        $magnitude = $n >= $this->hidden ? ($exponent + $this->m + $this->bias) * $this->hidden + $n - $this->hidden : $n;
        $flags = $units->inexact ? Flags::INEXACT : 0;
        if ($units->inexact && $t < $this->minExponent &&
            ($t < $this->minExponent - 1 || $unitsAt($t - $this->m)->whole < 2 * $this->hidden)) $flags |= Flags::UNDERFLOW;
        return new Result($this->zero($negative) + $magnitude, $flags);
    }

    public function round(Exact $value, Mode $mode): Result
    {
        if ($value->numerator === 0) return new Result($this->zero($value->negative));
        return $this->roundNonzero($value->negative, $value->log2Floor(), $mode,
            static fn(int $q): Units => roundUnits($value, $q, $mode));
    }
    public function sqrt(Exact $value, Mode $mode): Result
    {
        $log = $value->log2Floor();
        $t = $log >= 0 ? intdiv($log, 2) : -intdiv(-$log + 1, 2);
        return $this->roundNonzero(false, $t, $mode, static fn(int $q): Units => roundSqrtUnits($value, $q, $mode));
    }
}

final readonly class RealInput
{
    public function __construct(public RealKind $kind, public Exact $number) {}
    public function text(): string
    {
        return match ($this->kind) {
            RealKind::Finite => $this->number->fraction(), RealKind::NaN => 'nan',
            RealKind::Infinity => $this->number->negative ? '-inf' : 'inf',
        };
    }
    public function encoded(MiniFormat $f, Mode $mode): Result
    {
        return match ($this->kind) {
            RealKind::Finite => $f->round($this->number, $mode), RealKind::NaN => new Result($f->nan()),
            RealKind::Infinity => new Result($f->inf($this->number->negative)),
        };
    }
}

function modeAt(array $words, int $index): Mode
{
    return $index === count($words) ? Mode::RNE : (Mode::tryFrom($words[$index]) ?? fail('BAD MODE ' . $words[$index]));
}

function realInput(string $word): RealInput
{
    if ($word === 'nan') return new RealInput(RealKind::NaN, new Exact(0));
    if ($word === 'inf' || $word === '-inf') return new RealInput(RealKind::Infinity, new Exact(0, negative: $word === '-inf'));
    if (str_starts_with($word, '0b') || str_starts_with($word, '0x')) fail('BAD OPERAND ' . $word);
    $negative = $word[0] === '-';
    $body = $negative ? substr($word, 1) : $word;
    $slash = strpos($body, '/');
    if ($slash !== false) {
        $n = (int)substr($body, 0, $slash);
        $d = (int)substr($body, $slash + 1);
        if ($d === 0) fail('BAD OPERAND ' . $word);
        return new RealInput(RealKind::Finite, new Exact($n, denominator: $d, negative: $negative));
    }
    $dot = strpos($body, '.');
    $denominator = 1;
    if ($dot !== false) {
        for ($i = $dot + 1; $i < strlen($body); $i++) $denominator *= 10;
        $body = str_replace('.', '', $body);
    }
    return new RealInput(RealKind::Finite, new Exact((int)$body, denominator: $denominator, negative: $negative));
}

function operand(MiniFormat $f, string $word): int
{
    $bits = str_starts_with($word, '0b');
    $hex = str_starts_with($word, '0x');
    if ($bits || $hex) {
        if (strlen($word) - 2 !== ($bits ? $f->width : intdiv($f->width + 3, 4))) fail('BAD OPERAND ' . $word);
        $pattern = intval(substr($word, 2), $bits ? 2 : 16);
        if ($pattern >= (1 << $f->width)) fail('BAD OPERAND ' . $word);
        return $pattern;
    }
    return realInput($word)->encoded($f, Mode::RNE)->pattern;
}

/** @param list<int> $inputs */
function calculate(MiniFormat $f, Operation $operation, Mode $mode, array $inputs): Result
{
    $anyNaN = false;
    $signaling = false;
    foreach ($inputs as $pattern) {
        $anyNaN = $anyNaN || $f->isNaN($pattern);
        $signaling = $signaling || $f->isSignaling($pattern);
    }
    if ($anyNaN) return new Result($f->nan(), $signaling ? Flags::INVALID : 0);
    $a = $inputs[0];
    $negative = $f->fields($a)->negative;
    $invalid = new Result($f->nan(), Flags::INVALID);
    if ($operation === Operation::SQRT) {
        if ($f->isZero($a)) return new Result($a);
        if ($negative) return $invalid;
        if ($f->isInfinity($a)) return new Result($a);
        return $f->sqrt($f->exact($a), $mode);
    }
    $b = $operation === Operation::SUB ? $f->flip($inputs[1]) : $inputs[1];
    $sigma = $negative !== $f->fields($b)->negative;
    if ($operation === Operation::ADD || $operation === Operation::SUB) {
        if ($f->isInfinity($a) && $f->isInfinity($b) && $sigma) return $invalid;
        if ($f->isInfinity($a)) return new Result($a);
        if ($f->isInfinity($b)) return new Result($b);
        return $f->round(Exact::sum([$f->exact($a), $f->exact($b)], $mode), $mode);
    }
    if ($operation === Operation::MUL) {
        if ($f->isInfinity($a) || $f->isInfinity($b)) return $f->isZero($a) || $f->isZero($b) ? $invalid : new Result($f->inf($sigma));
        if ($f->isZero($a) || $f->isZero($b)) return new Result($f->zero($sigma));
        return $f->round(Exact::product($f->exact($a), $f->exact($b)), $mode);
    }
    if ($operation === Operation::DIV) {
        if ($f->isInfinity($a)) return $f->isInfinity($b) ? $invalid : new Result($f->inf($sigma));
        if ($f->isInfinity($b)) return new Result($f->zero($sigma));
        if ($f->isZero($b)) return $f->isZero($a) ? $invalid : new Result($f->inf($sigma), Flags::DIVBYZERO);
        if ($f->isZero($a)) return new Result($f->zero($sigma));
        $x = $f->exact($a);
        $y = $f->exact($b);
        return $f->round(new Exact($x->numerator * $y->denominator, $x->exponent - $y->exponent,
            $x->denominator * $y->numerator, $sigma), $mode);
    }
    $c = $inputs[2];
    if ($f->isInfinity($a) || $f->isInfinity($b)) {
        if ($f->isZero($a) || $f->isZero($b) || $f->isInfinity($c) && $f->fields($c)->negative !== $sigma) return $invalid;
        return new Result($f->inf($sigma));
    }
    if ($f->isInfinity($c)) return new Result($c);
    return $f->round(Exact::sum([Exact::product($f->exact($a), $f->exact($b)), $f->exact($c)], $mode), $mode);
}

function nextUp(MiniFormat $f, int $pattern): int
{
    if ($pattern === $f->infinity) return $pattern;
    if ($f->isZero($pattern)) return 1;
    return $pattern + ($f->fields($pattern)->negative ? -1 : 1);
}

function difference(MiniFormat $f, int $pattern, Exact $exact): string
{
    return !$f->isFinite($pattern) ? $f->value($pattern)
        : Exact::sum([$f->exact($pattern), $exact->negated()], Mode::RNE)->fraction();
}

final class Laboratory
{
    /** @var array<string, MiniFormat> */
    private array $formats;
    /** @var list<string> */
    private array $output = [];
    private const INTEGER_TYPES = [
        'I8' => [-128, 127], 'U8' => [0, 255], 'I16' => [-32768, 32767],
        'U16' => [0, 65535], 'I32' => [-2147483648, 2147483647], 'U32' => [0, 4294967295],
    ];

    public function __construct()
    {
        $this->formats = ['HALF' => new MiniFormat('HALF', 5, 10), 'E5M2' => new MiniFormat('E5M2', 5, 2), 'E4M3' => new MiniFormat('E4M3', 4, 3)];
    }

    private function emit(string $line): void { $this->output[] = $line; }
    private function format(string $name): MiniFormat { return $this->formats[$name] ?? fail('UNKNOWN FORMAT ' . $name); }

    /** @param list<string> $words @return list<int> */
    private function operands(MiniFormat $f, array $words, int $begin, int $end): array
    {
        $patterns = [];
        for ($i = $begin; $i < $end; $i++) $patterns[] = operand($f, $words[$i]);
        return $patterns;
    }

    private function summary(MiniFormat $f, Mode $mode, array $patterns, Result $result): void
    {
        $terms = [];
        foreach ($patterns as $pattern) $terms[] = $f->exact($pattern);
        $exact = Exact::sum($terms, $mode);
        $this->emit('RESULT ' . $f->resultText($result));
        $this->emit('EXACT ' . $exact->decimal());
        $this->emit('ROUNDED ' . $f->resultText($f->round($exact, $mode)));
        $this->emit('DIFF ' . difference($f, $result->pattern, $exact));
    }

    private function summation(string $command, MiniFormat $f, Mode $mode, array $patterns): void
    {
        foreach ($patterns as $pattern) if (!$f->isFinite($pattern)) fail('NOT FINITE');
        $count = count($patterns);
        $this->emit("$command {$f->name} {$mode->value} count=$count");
        $sum = $patterns[0];
        $compensation = 0;
        $flags = 0;
        for ($i = 1; $i < $count; $i++) {
            $stepNumber = $i + 1;
            if ($command === 'SUM') {
                $added = calculate($f, Operation::ADD, $mode, [$sum, $patterns[$i]]);
                $sum = $added->pattern;
                $flags |= $added->flags;
                $this->emit("PARTIAL $stepNumber " . $f->resultText($added));
            } else {
                $y = calculate($f, Operation::SUB, $mode, [$patterns[$i], $compensation]);
                $t = calculate($f, Operation::ADD, $mode, [$sum, $y->pattern]);
                $d = calculate($f, Operation::SUB, $mode, [$t->pattern, $sum]);
                $c = calculate($f, Operation::SUB, $mode, [$d->pattern, $y->pattern]);
                $sum = $t->pattern;
                $compensation = $c->pattern;
                $step = $y->flags | $t->flags | $d->flags | $c->flags;
                $flags |= $step;
                $this->emit("KSTEP $stepNumber sum=" . $f->value($sum) . ' comp=' . $f->value($compensation) . ' ' . Flags::text($step));
            }
        }
        $this->summary($f, $mode, $patterns, new Result($sum, $flags));
    }

    private function dot(MiniFormat $f, Mode $mode, array $a, array $b): void
    {
        if (count($a) !== count($b)) fail('LENGTH MISMATCH');
        foreach ($a as $pattern) if (!$f->isFinite($pattern)) fail('NOT FINITE');
        foreach ($b as $pattern) if (!$f->isFinite($pattern)) fail('NOT FINITE');
        $count = count($a);
        $naive = calculate($f, Operation::MUL, $mode, [$a[0], $b[0]]);
        $chained = $naive;
        for ($i = 1; $i < $count; $i++) {
            $product = calculate($f, Operation::MUL, $mode, [$a[$i], $b[$i]]);
            $added = calculate($f, Operation::ADD, $mode, [$naive->pattern, $product->pattern]);
            $naive = new Result($added->pattern, $naive->flags | $product->flags | $added->flags);
            $fused = calculate($f, Operation::FMA, $mode, [$a[$i], $b[$i], $chained->pattern]);
            $chained = new Result($fused->pattern, $chained->flags | $fused->flags);
        }
        $terms = [];
        for ($i = 0; $i < $count; $i++) $terms[] = Exact::product($f->exact($a[$i]), $f->exact($b[$i]));
        $exact = Exact::sum($terms, $mode);
        $this->emit("DOT {$f->name} {$mode->value} n=$count");
        $this->emit('NAIVE ' . $f->resultText($naive));
        $this->emit('CHAINED ' . $f->resultText($chained));
        $this->emit('EXACT ' . $exact->decimal());
        $this->emit('FUSED ' . $f->resultText($f->round($exact, $mode)));
        $this->emit('DIFF naive=' . difference($f, $naive->pattern, $exact) . ' chained=' . difference($f, $chained->pattern, $exact));
    }

    private function table(MiniFormat $f): void
    {
        if ($f->width > 8) fail('TABLE TOO LARGE');
        $count = $f->infinity;
        $this->emit("TABLE {$f->name} count=$count");
        for ($pattern = 0; $pattern < $count; $pattern++) {
            $gap = $pattern === $count - 1 ? '-'
                : Exact::sum([$f->exact($pattern + 1), $f->exact($pattern)->negated()], Mode::RNE)->decimal();
            $this->emit("ENTRY $pattern " . $f->patternText($pattern) . " gap=$gap");
        }
        $this->emit('MAX ' . $f->patternText($f->infinity - 1));
        $this->emit('MINNORMAL ' . $f->patternText($f->hidden));
        $this->emit('MINSUBNORMAL ' . $f->patternText(1));
        $this->emit('EPSILON ' . (new Exact(1, -$f->m))->decimal());
        $this->emit('PATTERNS finite=' . (2 * $count) . ' infinite=2 nan=' . (2 * ($f->hidden - 1)) . ' total=' . (1 << $f->width));
    }

    /** @return list<string> */
    public function execute(string $line): array
    {
        $this->output = [];
        $words = explode(' ', $line);
        $command = $words[0];
        if ($command === 'FORMAT') {
            $name = $words[1];
            $e = (int)$words[2];
            $m = (int)$words[3];
            if (isset($this->formats[$name])) fail('FORMAT EXISTS ' . $name);
            if ($e < 2 || $e > 5 || $m < 1 || $m > 10) fail('BAD FORMAT');
            $f = new MiniFormat($name, $e, $m);
            $this->formats[$name] = $f;
            $this->emit("FORMAT $name e=$e m=$m bits={$f->width} bias={$f->bias} emin={$f->minExponent} emax={$f->maxExponent}");
            return $this->output;
        }
        $f = $this->format($words[1]);
        $operation = Operation::tryFrom($command);
        if ($command === 'ENCODE') {
            $input = realInput($words[2]);
            $mode = modeAt($words, 3);
            $this->emit("ENCODE {$f->name} {$mode->value} " . $input->text() . ' ' . $f->resultText($input->encoded($f, $mode)));
        } elseif ($command === 'CONVERT') {
            $g = $this->format($words[2]);
            $a = operand($f, $words[3]);
            $mode = modeAt($words, 4);
            if ($f->isNaN($a)) $result = new Result($g->nan(), $f->isSignaling($a) ? Flags::INVALID : 0);
            elseif ($f->isInfinity($a)) $result = new Result($g->inf($f->fields($a)->negative));
            else $result = $g->round($f->exact($a), $mode);
            $this->emit("CONVERT {$f->name} {$g->name} {$mode->value} " . $g->resultText($result));
        } elseif ($command === 'SUM' || $command === 'KAHAN' || $command === 'DOT') {
            $mode = modeAt($words, 2);
            if ($command === 'DOT') {
                $separator = array_search('|', $words, true);
                $a = $this->operands($f, $words, 3, $separator);
                $b = $this->operands($f, $words, $separator + 1, count($words));
                $this->dot($f, $mode, $a, $b);
            } else $this->summation($command, $f, $mode, $this->operands($f, $words, 3, count($words)));
        } elseif ($command === 'TABLE') {
            $this->table($f);
        } elseif ($operation !== null) {
            $count = $operation === Operation::SQRT ? 1 : ($operation === Operation::FMA ? 3 : 2);
            $patterns = $this->operands($f, $words, 2, 2 + $count);
            $mode = modeAt($words, 2 + $count);
            $this->emit("$command {$f->name} {$mode->value} " . $f->resultText(calculate($f, $operation, $mode, $patterns)));
        } else {
            $a = operand($f, $words[2]);
            $fields = $f->fields($a);
            if ($command === 'DECODE') {
                if ($f->isNaN($a)) $classification = $f->isSignaling($a) ? 'snan' : 'qnan';
                elseif ($f->isInfinity($a)) $classification = 'infinity';
                elseif ($f->isZero($a)) $classification = 'zero';
                else $classification = $fields->exponent === 0 ? 'subnormal' : 'normal';
                $this->emit("DECODE {$f->name} " . $f->bits($a) . ' ' . $f->hex($a) . " $classification sign=" . ($fields->negative ? 1 : 0));
                $heading = "FIELDS exponent={$fields->exponent} fraction={$fields->fraction}";
                if ($f->isFinite($a)) {
                    $this->emit($heading . ' unbiased=' . ($fields->q + $f->m) . ' significand=' . ($fields->exponent === 0 ? '0.' : '1.') . binary($fields->fraction, $f->m));
                    $this->emit('VALUE ' . $f->exact($a)->fraction() . ' ' . $f->value($a));
                } else $this->emit($f->isNaN($a) ? $heading . ' payload=' . ($fields->fraction % intdiv($f->hidden, 2)) : $heading);
            } elseif ($command === 'COMPARE') {
                $b = operand($f, $words[3]);
                $key = static fn(int $p): int => $f->fields($p)->negative ? -($p - $f->signBit) - 1 : $p;
                $order = relation($key($a), $key($b));
                $numeric = $f->isNaN($a) || $f->isNaN($b) ? 'UN' : ($f->isZero($a) && $f->isZero($b) ? 'EQ' : $order);
                $flags = $f->isSignaling($a) || $f->isSignaling($b) ? Flags::INVALID : 0;
                $this->emit("COMPARE {$f->name} " . $f->hex($a) . ' ' . $f->hex($b) . " $numeric total=$order " . Flags::text($flags));
            } elseif ($command === 'TOINT') {
                [$minimum, $maximum] = self::INTEGER_TYPES[$words[3]] ?? fail('BAD TYPE ' . $words[3]);
                $mode = modeAt($words, 4);
                $prefix = "TOINT {$f->name} {$words[3]} {$mode->value}";
                if (!$f->isFinite($a)) $this->emit($prefix . ' invalid flags=invalid');
                else {
                    $units = roundUnits($f->exact($a), 0, $mode);
                    $integer = $fields->negative ? -$units->whole : $units->whole;
                    $this->emit($integer < $minimum || $integer > $maximum ? $prefix . ' invalid flags=invalid'
                        : $prefix . " $integer " . Flags::text($units->inexact ? Flags::INEXACT : 0));
                }
            } else {
                if ($f->isNaN($a)) $result = new Result($f->nan(), $f->isSignaling($a) ? Flags::INVALID : 0);
                elseif ($command === 'NEXTUP') $result = new Result(nextUp($f, $a));
                elseif ($command === 'NEXTDOWN') $result = new Result($f->flip(nextUp($f, $f->flip($a))));
                else $result = new Result($f->isInfinity($a) ? $f->infinity : $f->round(new Exact(1, $fields->q), Mode::RNE)->pattern);
                $this->emit("$command {$f->name} " . $f->resultText($result));
            }
        }
        return $this->output;
    }
}

$count = (int)trim(fgets(STDIN));
$laboratory = new Laboratory();
for ($i = 0; $i < $count; $i++) {
    try {
        $lines = $laboratory->execute(rtrim(fgets(STDIN), "\r\n"));
        fwrite(STDOUT, implode("\n", $lines) . "\n");
    } catch (CommandError $error) {
        fwrite(STDOUT, 'ERROR ' . $error->getMessage() . "\n");
    }
}
