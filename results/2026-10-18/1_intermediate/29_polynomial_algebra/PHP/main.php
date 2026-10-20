<?php
declare(strict_types=1);

final class CommandError extends RuntimeException {}

function integerGcd(int $a, int $b): int {
    $a = abs($a); $b = abs($b);
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    return $a;
}

final readonly class Fraction {
    public int $n;
    public int $d;
    public function __construct(int $n, int $d = 1) {
        if ($d < 0) { $n = -$n; $d = -$d; }
        $divisor = integerGcd($n, $d);
        $this->n = intdiv($n, $divisor);
        $this->d = intdiv($d, $divisor);
    }
    public static function zero(): self { static $value; return $value ??= new self(0); }
    public static function one(): self { static $value; return $value ??= new self(1); }
    public static function parse(string $text): self {
        $parts = explode('/', $text);
        $denominator = count($parts) === 1 ? 1 : (int)$parts[1];
        if ($denominator === 0) throw new CommandError('ERROR ZERO DENOMINATOR');
        return new self((int)$parts[0], $denominator);
    }
    public function isZero(): bool { return $this->n === 0; }
    public function sign(): int { return $this->n <=> 0; }
    public function add(self $b): self { return new self($this->n * $b->d + $b->n * $this->d, $this->d * $b->d); }
    public function sub(self $b): self { return new self($this->n * $b->d - $b->n * $this->d, $this->d * $b->d); }
    public function mul(self $b): self { return new self($this->n * $b->n, $this->d * $b->d); }
    public function div(self $b): self { return new self($this->n * $b->d, $this->d * $b->n); }
    public function neg(): self { return new self(-$this->n, $this->d); }
    public function absolute(): self { return new self(abs($this->n), $this->d); }
    public function equals(self $b): bool { return $this->n === $b->n && $this->d === $b->d; }
    public function compare(self $b): int { return ($this->n * $b->d) <=> ($b->n * $this->d); }
    public function power(int $exponent): self {
        $result = self::one();
        for ($i = 0; $i < $exponent; $i++) $result = $result->mul($this);
        return $result;
    }
    public function __toString(): string { return $this->d === 1 ? (string)$this->n : $this->n . '/' . $this->d; }
}

final readonly class Polynomial {
    public array $coefficients;
    public function __construct(array $values = []) {
        while ($values !== [] && $values[count($values) - 1]->isZero()) array_pop($values);
        $this->coefficients = $values;
    }
    public static function zero(): self { static $value; return $value ??= new self(); }
    public static function one(): self { static $value; return $value ??= new self([Fraction::one()]); }
    public static function variable(): self { static $value; return $value ??= new self([Fraction::zero(), Fraction::one()]); }
    public function degree(): int { return count($this->coefficients) - 1; }
    public function isZero(): bool { return $this->coefficients === []; }
    public function leading(): Fraction { return $this->coefficients[$this->degree()]; }
    public function at(int $index): Fraction { return $this->coefficients[$index] ?? Fraction::zero(); }
    public function add(self $b): self {
        $result = [];
        for ($i = 0; $i <= max($this->degree(), $b->degree()); $i++) $result[] = $this->at($i)->add($b->at($i));
        return new self($result);
    }
    public function sub(self $b): self {
        $result = [];
        for ($i = 0; $i <= max($this->degree(), $b->degree()); $i++) $result[] = $this->at($i)->sub($b->at($i));
        return new self($result);
    }
    public function neg(): self { return new self(array_map(static fn(Fraction $c): Fraction => $c->neg(), $this->coefficients)); }
    public function mul(self $b): self {
        if ($this->isZero() || $b->isZero()) return self::zero();
        $result = array_fill(0, $this->degree() + $b->degree() + 1, Fraction::zero());
        foreach ($this->coefficients as $i => $left) {
            foreach ($b->coefficients as $j => $right) $result[$i + $j] = $result[$i + $j]->add($left->mul($right));
        }
        return new self($result);
    }
    public function scale(Fraction $factor): self {
        return new self(array_map(static fn(Fraction $c): Fraction => $c->mul($factor), $this->coefficients));
    }
    public function divideScalar(Fraction $divisor): self {
        return new self(array_map(static fn(Fraction $c): Fraction => $c->div($divisor), $this->coefficients));
    }
    public function monic(): self { return $this->isZero() ? self::zero() : $this->divideScalar($this->leading()); }
    public function power(int $exponent): self {
        if ($exponent === 0) return self::one();
        if ($this->isZero()) return self::zero();
        if ($this->degree() === 0 && $this->leading()->d === 1 && abs($this->leading()->n) === 1) {
            return $this->leading()->n === 1 || $exponent % 2 === 0 ? self::one() : $this;
        }
        $result = self::one();
        for ($i = 0; $i < $exponent; $i++) $result = $result->mul($this);
        return $result;
    }
    public function evaluate(Fraction $point): Fraction {
        $result = Fraction::zero();
        for ($i = $this->degree(); $i >= 0; $i--) $result = $result->mul($point)->add($this->at($i));
        return $result;
    }
    public function compose(self $inner): self {
        $result = self::zero();
        for ($i = $this->degree(); $i >= 0; $i--) $result = $result->mul($inner)->add(new self([$this->at($i)]));
        return $result;
    }
    public function derivative(int $order = 1): self {
        $result = $this;
        for ($step = 0; $step < $order; $step++) {
            $values = [];
            for ($i = 1; $i <= $result->degree(); $i++) $values[] = (new Fraction($i))->mul($result->at($i));
            $result = new self($values);
        }
        return $result;
    }
    public function integral(): self {
        $result = [Fraction::zero()];
        foreach ($this->coefficients as $i => $value) $result[] = $value->div(new Fraction($i + 1));
        return new self($result);
    }
    public function divide(self $divisor): array {
        $quotient = array_fill(0, max(0, $this->degree() - $divisor->degree() + 1), Fraction::zero());
        $remainder = $this->coefficients;
        while ($remainder !== [] && count($remainder) >= count($divisor->coefficients)) {
            $factor = $remainder[count($remainder) - 1]->div($divisor->leading());
            $shift = count($remainder) - count($divisor->coefficients);
            $quotient[$shift] = $factor;
            foreach ($divisor->coefficients as $j => $value) $remainder[$shift + $j] = $remainder[$shift + $j]->sub($factor->mul($value));
            while ($remainder !== [] && $remainder[count($remainder) - 1]->isZero()) array_pop($remainder);
        }
        return [new self($quotient), new self($remainder)];
    }
    public static function gcd(self $a, self $b): self {
        while (!$b->isZero()) [$a, $b] = [$b, $a->divide($b)[1]];
        return $a->monic();
    }
    public static function extendedGcd(self $a, self $b): array {
        $r0 = $a; $r1 = $b; $s0 = self::one(); $s1 = self::zero(); $t0 = self::zero(); $t1 = self::one();
        while (!$r1->isZero()) {
            [$quotient, $remainder] = $r0->divide($r1);
            [$r0, $r1] = [$r1, $remainder];
            [$s0, $s1] = [$s1, $s0->sub($quotient->mul($s1))];
            [$t0, $t1] = [$t1, $t0->sub($quotient->mul($t1))];
        }
        return $r0->isZero() ? [$r0, $s0, $t0]
            : [$r0->monic(), $s0->divideScalar($r0->leading()), $t0->divideScalar($r0->leading())];
    }
    public function content(): Fraction {
        $denominator = 1; $numerator = 0;
        foreach ($this->coefficients as $value) {
            $denominator = intdiv($denominator * $value->d, integerGcd($denominator, $value->d));
            $numerator = integerGcd($numerator, $value->n);
        }
        return new Fraction($this->leading()->n < 0 ? -$numerator : $numerator, $denominator);
    }
    public function primitive(): self { return $this->divideScalar($this->content()); }
    public function squareFreePart(): self {
        return $this->degree() < 1 ? $this : $this->divide(self::gcd($this, $this->derivative()))[0];
    }
    public function format(string $variable = 'x'): string {
        $result = '';
        for ($i = $this->degree(); $i >= 0; $i--) {
            $value = $this->at($i);
            if ($value->isZero()) continue;
            $result .= $result === '' ? ($value->n < 0 ? '-' : '') : ($value->n < 0 ? ' - ' : ' + ');
            $magnitude = $value->absolute();
            if ($i === 0 || !$magnitude->equals(Fraction::one())) $result .= $magnitude;
            if ($i > 0) $result .= $variable;
            if ($i > 1) $result .= '^' . $i;
        }
        return $result === '' ? '0' : $result;
    }
}

function checkProduct(Polynomial $a, Polynomial $b): void {
    if (!$a->isZero() && !$b->isZero() && $a->degree() + $b->degree() > 30) throw new CommandError('ERROR DEGREE LIMIT');
}
function checkPower(Polynomial $a, int $exponent): void {
    if (!$a->isZero() && $a->degree() * $exponent > 30) throw new CommandError('ERROR DEGREE LIMIT');
}
function checkComposition(Polynomial $a, Polynomial $b): void {
    if ($a->degree() >= 1 && $b->degree() >= 1 && $a->degree() * $b->degree() > 30) throw new CommandError('ERROR DEGREE LIMIT');
}
function checkNonzero(Polynomial $value): void { if ($value->isZero()) throw new CommandError('ERROR ZERO POLYNOMIAL'); }
function checkDivisor(Polynomial $value): void { if ($value->isZero()) throw new CommandError('ERROR DIVISION BY ZERO'); }
function checkPositiveDegree(Polynomial $value): void { if ($value->degree() === 0) throw new CommandError('ERROR DEGREE TOO LOW'); }

enum NodeKind { case Number; case Variable; case Name; case Negative; case Add; case Subtract; case Multiply; case Divide; case Power; case Call; }
final readonly class Expression {
    public function __construct(
        public NodeKind $kind,
        public ?Polynomial $literal = null,
        public string $name = '',
        public int $count = 0,
        public ?self $left = null,
        public ?self $right = null,
    ) {}
    public function evaluate(array $storage): Polynomial {
        switch ($this->kind) {
            case NodeKind::Number: return $this->literal;
            case NodeKind::Variable: return Polynomial::variable();
            case NodeKind::Name:
                $value = $storage[$this->name] ?? throw new CommandError('ERROR UNKNOWN ' . $this->name);
                return $value->derivative($this->count);
            case NodeKind::Negative: return $this->left->evaluate($storage)->neg();
            case NodeKind::Power:
                $value = $this->left->evaluate($storage);
                checkPower($value, $this->count);
                return $value->power($this->count);
            default: break;
        }
        $a = $this->left->evaluate($storage);
        $b = $this->right->evaluate($storage);
        switch ($this->kind) {
            case NodeKind::Add: return $a->add($b);
            case NodeKind::Subtract: return $a->sub($b);
            case NodeKind::Multiply: checkProduct($a, $b); return $a->mul($b);
            case NodeKind::Call: checkComposition($a, $b); return $a->compose($b);
            default:
                checkDivisor($b);
                if ($b->degree() >= 1) throw new CommandError('ERROR NONCONSTANT DIVISOR');
                return $a->divideScalar($b->at(0));
        }
    }
}
enum TokenKind { case Number; case Name; case Symbol; case End; }
final readonly class Token {
    public function __construct(public TokenKind $kind, public string $text, public int $position) {}
}
final class Parser {
    private array $tokens = [];
    private int $position = 0;
    private static function digit(string $ch): bool { return ord($ch) >= 48 && ord($ch) <= 57; }
    private static function upper(string $ch): bool { return ord($ch) >= 65 && ord($ch) <= 90; }
    public function __construct(string $source) {
        $length = strlen($source);
        for ($i = 0; $i < $length;) {
            if ($source[$i] === ' ') { $i++; continue; }
            $start = $i++;
            if (self::digit($source[$start])) {
                $kind = TokenKind::Number;
                while ($i < $length && self::digit($source[$i])) $i++;
            } elseif (self::upper($source[$start])) {
                $kind = TokenKind::Name;
                while ($i < $length && (self::upper($source[$i]) || self::digit($source[$i]))) $i++;
            } else $kind = TokenKind::Symbol;
            $this->tokens[] = new Token($kind, substr($source, $start, $i - $start), $start + 1);
        }
        $this->tokens[] = new Token(TokenKind::End, '', $length + 1);
    }
    private function current(): Token { return $this->tokens[$this->position]; }
    private function at(string $symbol): bool { return $this->current()->kind === TokenKind::Symbol && $this->current()->text === $symbol; }
    private function syntax(): never {
        throw new CommandError('ERROR SYNTAX AT ' . ($this->current()->kind === TokenKind::End ? 'END' : $this->current()->position));
    }
    private function expect(string $symbol): void {
        if (!$this->at($symbol)) $this->syntax();
        $this->position++;
    }
    public function parse(): Expression {
        $result = $this->expression();
        if ($this->current()->kind !== TokenKind::End) $this->syntax();
        return $result;
    }
    private function expression(): Expression {
        $negative = $this->at('-');
        if ($negative) $this->position++;
        $result = $this->term();
        if ($negative) $result = new Expression(NodeKind::Negative, left: $result);
        while ($this->at('+') || $this->at('-')) {
            $kind = $this->at('+') ? NodeKind::Add : NodeKind::Subtract;
            $this->position++;
            $right = $this->term();
            $result = new Expression($kind, left: $result, right: $right);
        }
        return $result;
    }
    private function term(): Expression {
        $result = $this->factor();
        while (true) {
            $kind = NodeKind::Multiply;
            if ($this->at('*') || $this->at('/')) {
                if ($this->at('/')) $kind = NodeKind::Divide;
                $this->position++;
            } elseif (!$this->at('x') && !$this->at('(') && $this->current()->kind !== TokenKind::Name) break;
            $right = $this->factor();
            $result = new Expression($kind, left: $result, right: $right);
        }
        return $result;
    }
    private function factor(): Expression {
        $result = $this->primary();
        if ($this->at('^')) {
            $this->position++;
            if ($this->current()->kind !== TokenKind::Number) $this->syntax();
            $exponent = (int)$this->current()->text;
            $this->position++;
            $result = new Expression(NodeKind::Power, count: $exponent, left: $result);
        }
        return $result;
    }
    private function primary(): Expression {
        $token = $this->current();
        if ($token->kind === TokenKind::Number) {
            $this->position++;
            return new Expression(NodeKind::Number, literal: new Polynomial([new Fraction((int)$token->text)]));
        }
        if ($this->at('x')) { $this->position++; return new Expression(NodeKind::Variable); }
        if ($token->kind === TokenKind::Name) {
            $this->position++;
            $order = 0;
            while ($this->at("'")) { $order++; $this->position++; }
            $reference = new Expression(NodeKind::Name, name: $token->text, count: $order);
            if (!$this->at('(')) return $reference;
            $this->position++;
            $argument = $this->expression();
            $this->expect(')');
            return new Expression(NodeKind::Call, left: $reference, right: $argument);
        }
        if ($this->at('(')) {
            $this->position++;
            $result = $this->expression();
            $this->expect(')');
            return $result;
        }
        $this->syntax();
    }
}

final readonly class Endpoint {
    public function __construct(public int $infinity, public Fraction $value) {}
    public static function parse(string $text): self {
        return match ($text) {
            '-inf' => new self(-1, Fraction::zero()), 'inf' => new self(1, Fraction::zero()),
            default => new self(0, Fraction::parse($text)),
        };
    }
    public function compare(self $other): int {
        return $this->infinity === 0 && $other->infinity === 0
            ? $this->value->compare($other->value) : $this->infinity <=> $other->infinity;
    }
    public function __toString(): string { return $this->infinity === 0 ? (string)$this->value : ($this->infinity < 0 ? '-inf' : 'inf'); }
}
final readonly class Root {
    public function __construct(public Fraction $value, public int $multiplicity) {}
}
final readonly class Factor {
    public function __construct(public Polynomial $value, public int $multiplicity) {}
}

function rationalRoots(Polynomial $value): array {
    $content = $value->content();
    $remaining = $value->divideScalar($content);
    $zeros = 0;
    while ($remaining->at(0)->isZero()) {
        $remaining = new Polynomial(array_slice($remaining->coefficients, 1));
        $zeros++;
    }
    $divisors = static function(int $number): array {
        $result = [];
        for ($i = 1; $i <= $number; $i++) if ($number % $i === 0) $result[] = $i;
        return $result;
    };
    $numerators = $divisors(abs($remaining->at(0)->n));
    $denominators = $divisors($remaining->leading()->n);
    $candidates = [];
    foreach ($numerators as $numerator) {
        foreach ($denominators as $denominator) {
            if (integerGcd($numerator, $denominator) !== 1) continue;
            $candidates[] = new Fraction($numerator, $denominator);
            $candidates[] = new Fraction(-$numerator, $denominator);
        }
    }
    usort($candidates, static fn(Fraction $a, Fraction $b): int => $a->compare($b));
    $roots = [];
    foreach ($candidates as $candidate) {
        $count = 0;
        $divisor = new Polynomial([new Fraction(-$candidate->n), new Fraction($candidate->d)]);
        while ($remaining->degree() >= 1 && $remaining->evaluate($candidate)->isZero()) {
            $remaining = $remaining->divide($divisor)[0];
            $count++;
        }
        if ($count > 0) $roots[] = new Root($candidate, $count);
    }
    if ($zeros > 0) $roots[] = new Root(Fraction::zero(), $zeros);
    usort($roots, static fn(Root $a, Root $b): int => $a->value->compare($b->value));
    return [$content, $remaining, $roots];
}

function squareFreeFactors(Polynomial $value): array {
    $result = [];
    if ($value->degree() < 1) return $result;
    $monic = $value->monic();
    $c = Polynomial::gcd($monic, $monic->derivative());
    $w = $monic->divide($c)[0];
    for ($i = 1; $w->degree() >= 1; $i++) {
        $y = Polynomial::gcd($w, $c);
        $factor = $w->divide($y)[0];
        if ($factor->degree() >= 1) $result[] = new Factor($factor->primitive(), $i);
        $c = $c->divide($y)[0];
        $w = $y;
    }
    return $result;
}

function sturmSequence(Polynomial $value): array {
    $previous = $value->squareFreePart();
    $current = $previous->derivative();
    $result = [$previous];
    while (!$current->isZero()) {
        $result[] = $current;
        $next = $previous->divide($current)[1]->neg();
        $previous = $current;
        $current = $next;
    }
    return $result;
}
function variations(array $sequence, Endpoint $point): int {
    $previous = 0; $changes = 0;
    foreach ($sequence as $value) {
        $sign = $point->infinity === 0 ? $value->evaluate($point->value)->sign() : $value->leading()->sign();
        if ($point->infinity < 0 && $value->degree() % 2 !== 0) $sign = -$sign;
        if ($sign === 0) continue;
        if ($previous !== 0 && $previous !== $sign) $changes++;
        $previous = $sign;
    }
    return $changes;
}
function rootCount(array $sequence, Endpoint $left, Endpoint $right): int {
    $leftCount = variations($sequence, $left);
    $rightCount = variations($sequence, $right);
    return $leftCount - $rightCount;
}
function isolate(Polynomial $value, int $precision): array {
    $sequence = sturmSequence($value);
    $first = $sequence[0];
    $maximum = Fraction::zero();
    for ($i = 0; $i < $first->degree(); $i++) {
        $candidate = $first->at($i)->div($first->leading())->absolute();
        if ($candidate->compare($maximum) > 0) $maximum = $candidate;
    }
    $bound = Fraction::one()->add($maximum);
    $width = new Fraction(1, 1 << $precision);
    $intervals = [];
    $count = static fn(Fraction $left, Fraction $right): int => rootCount($sequence, new Endpoint(0, $left), new Endpoint(0, $right));
    $examine = static function(Fraction $left, Fraction $right) use (&$examine, &$intervals, $count, $width): void {
        $roots = $count($left, $right);
        if ($roots >= 2) {
            $middle = $left->add($right)->div(new Fraction(2));
            $examine($left, $middle);
            $examine($middle, $right);
        } elseif ($roots === 1) {
            while ($right->sub($left)->compare($width) > 0) {
                $middle = $left->add($right)->div(new Fraction(2));
                if ($count($left, $middle) >= 1) $right = $middle;
                else $left = $middle;
            }
            $intervals[] = [$left, $right];
        }
    };
    $examine($bound->neg(), $bound);
    return $intervals;
}
function resultant(Polynomial $p, Polynomial $q): Fraction {
    $result = Fraction::one();
    while ($q->degree() >= 1) {
        $remainder = $p->divide($q)[1];
        if ($remainder->isZero()) return Fraction::zero();
        $result = $result->mul($q->leading()->power($p->degree() - $remainder->degree()));
        if ($p->degree() * $q->degree() % 2 !== 0) $result = $result->neg();
        $p = $q;
        $q = $remainder;
    }
    return $result->mul($q->at(0)->power($p->degree()));
}
function descartes(Polynomial $value, bool $negative): int {
    $previous = 0; $count = 0;
    for ($i = $value->degree(); $i >= 0; $i--) {
        $sign = $value->at($i)->sign();
        if ($negative && $i % 2 !== 0) $sign = -$sign;
        if ($sign === 0) continue;
        if ($previous !== 0 && $previous !== $sign) $count++;
        $previous = $sign;
    }
    return $count;
}
function interpolate(array $values): Polynomial {
    $count = intdiv(count($values), 2);
    $points = []; $differences = [];
    for ($i = 0; $i < $count; $i++) { $points[] = $values[2 * $i]; $differences[] = $values[2 * $i + 1]; }
    for ($j = 1; $j < $count; $j++) {
        for ($i = 0; $i < $j; $i++) {
            if ($points[$j]->equals($points[$i])) throw new CommandError('ERROR DUPLICATE X ' . $points[$j]);
        }
    }
    for ($j = 1; $j < $count; $j++) {
        for ($i = $count - 1; $i >= $j; $i--) {
            $differences[$i] = $differences[$i]->sub($differences[$i - 1])->div($points[$i]->sub($points[$i - $j]));
        }
    }
    $result = Polynomial::zero();
    for ($i = $count - 1; $i >= 0; $i--) {
        $result = $result->mul(new Polynomial([$points[$i]->neg(), Fraction::one()]))->add(new Polynomial([$differences[$i]]));
    }
    return $result;
}
function special(string $kind, int $degree): Polynomial {
    if (!in_array($kind, ['chebyshev', 'chebyshev2', 'legendre', 'hermite', 'laguerre'], true)) {
        throw new CommandError('ERROR UNKNOWN KIND ' . $kind);
    }
    if ($degree > 30) throw new CommandError('ERROR DEGREE LIMIT');
    $previous = Polynomial::one();
    if ($degree === 0) return $previous;
    $current = match ($kind) {
        'chebyshev2', 'hermite' => new Polynomial([Fraction::zero(), new Fraction(2)]),
        'laguerre' => new Polynomial([Fraction::one(), new Fraction(-1)]), default => Polynomial::variable(),
    };
    for ($j = 1; $j < $degree; $j++) {
        $factor = match ($kind) {
            'legendre' => new Polynomial([Fraction::zero(), new Fraction(2 * $j + 1)]),
            'laguerre' => new Polynomial([new Fraction(2 * $j + 1), new Fraction(-1)]),
            default => new Polynomial([Fraction::zero(), new Fraction(2)]),
        };
        $scale = $kind === 'legendre' || $kind === 'laguerre' ? $j : ($kind === 'hermite' ? 2 * $j : 1);
        $next = $factor->mul($current)->sub($previous->scale(new Fraction($scale)));
        if ($kind === 'legendre' || $kind === 'laguerre') $next = $next->scale(new Fraction(1, $j + 1));
        $previous = $current;
        $current = $next;
    }
    return $current;
}

final class Calculator {
    private array $storage = [];
    private function lookup(string $name): Polynomial {
        return $this->storage[$name] ?? throw new CommandError('ERROR UNKNOWN ' . $name);
    }
    private static function nameArguments(string $command): array {
        return match ($command) {
            'PRINT', 'DELETE', 'DEGREE', 'AREA', 'TAYLOR', 'EVAL', 'ROOTS', 'FACTOR',
            'SQFREE', 'DESCARTES', 'STURM', 'ISOLATE', 'DISCRIM', 'POWERSUM' => [1],
            'ADD', 'SUB', 'MUL', 'GCD', 'LCM', 'INVMOD', 'COMPOSE' => [2, 3],
            'POW', 'DERIV', 'INTEG', 'TANGENT' => [2], 'DIV' => [3, 4], 'XGCD' => [4, 5],
            'CRT' => [2, 3, 4, 5], 'MODPOW' => [2, 4], 'RESULTANT' => [1, 2], default => [],
        };
    }
    public function execute(string $line): array {
        $output = []; $pending = []; $deletion = null;
        $save = static function(string $name, Polynomial $value) use (&$output, &$pending): void {
            $pending[] = [$name, $value];
            $output[] = $name . ' = ' . $value->format();
        };
        if (str_starts_with($line, 'DEF ')) {
            $definition = explode(' ', $line, 3);
            $expression = (new Parser($definition[2]))->parse();
            $save($definition[1], $expression->evaluate($this->storage));
        } else {
            $words = explode(' ', $line);
            $command = $words[0];
            if ($command === 'DIV' && $words[1] === $words[2] || $command === 'XGCD' &&
                ($words[1] === $words[2] || $words[1] === $words[3] || $words[2] === $words[3])) {
                throw new CommandError('ERROR SAME NAME');
            }
            $operands = [];
            foreach (self::nameArguments($command) as $index) $operands[] = $this->lookup($words[$index]);
            $literalArguments = match ($command) {
                'AREA' => [2, 3], 'TANGENT' => [3], 'TAYLOR' => [2],
                'EVAL', 'INTERP' => range(2, count($words) - 1), default => [],
            };
            $literals = [];
            foreach ($literalArguments as $index) $literals[] = Fraction::parse($words[$index]);
            $left = $right = null;
            if ($command === 'STURM') {
                $left = Endpoint::parse($words[2]);
                $right = Endpoint::parse($words[3]);
            }
            $a = $operands[0] ?? Polynomial::zero();
            $b = $operands[1] ?? Polynomial::zero();
            switch ($command) {
                case 'PRINT': $output[] = $words[1] . ' = ' . $a->format(); break;
                case 'DELETE': $deletion = $words[1]; $output[] = 'deleted ' . $words[1]; break;
                case 'LIST':
                    $sorted = $this->storage;
                    ksort($sorted, SORT_STRING);
                    foreach ($sorted as $name => $value) $output[] = $name . ' = ' . $value->format();
                    if ($sorted === []) $output[] = 'no polynomials';
                    break;
                case 'DEGREE': $output[] = 'deg(' . $words[1] . ') = ' . ($a->isZero() ? '-inf' : $a->degree()); break;
                case 'ADD': $save($words[1], $a->add($b)); break;
                case 'SUB': $save($words[1], $a->sub($b)); break;
                case 'MUL': checkProduct($a, $b); $save($words[1], $a->mul($b)); break;
                case 'POW':
                    $exponent = (int)$words[3];
                    checkPower($a, $exponent);
                    $save($words[1], $a->power($exponent));
                    break;
                case 'DIV':
                    checkDivisor($b);
                    [$quotient, $remainder] = $a->divide($b);
                    $save($words[1], $quotient);
                    $save($words[2], $remainder);
                    break;
                case 'GCD': $save($words[1], Polynomial::gcd($a, $b)); break;
                case 'XGCD':
                    [$g, $s, $t] = Polynomial::extendedGcd($a, $b);
                    $save($words[1], $g); $save($words[2], $s); $save($words[3], $t);
                    break;
                case 'LCM':
                    if ($a->isZero() || $b->isZero()) $save($words[1], Polynomial::zero());
                    else {
                        $gcd = Polynomial::gcd($a, $b);
                        if ($a->degree() + $b->degree() - $gcd->degree() > 30) throw new CommandError('ERROR DEGREE LIMIT');
                        $save($words[1], $a->divide($gcd)[0]->mul($b)->monic());
                    }
                    break;
                case 'INVMOD':
                    checkDivisor($b); checkPositiveDegree($b);
                    [$g, $s] = Polynomial::extendedGcd($a, $b);
                    if ($g->degree() !== 0 || !$g->at(0)->equals(Fraction::one())) throw new CommandError('ERROR NOT COPRIME');
                    $save($words[1], $s->divide($b)[1]);
                    break;
                case 'CRT':
                    $a2 = $operands[2]; $m2 = $operands[3];
                    checkDivisor($b); checkDivisor($m2);
                    if ($b->degree() + $m2->degree() > 30) throw new CommandError('ERROR DEGREE LIMIT');
                    [$g, $s] = Polynomial::extendedGcd($b, $m2);
                    if ($g->degree() !== 0 || !$g->at(0)->equals(Fraction::one())) throw new CommandError('ERROR NOT COPRIME');
                    $r1 = $a->divide($b)[1]; $r2 = $a2->divide($m2)[1];
                    $u = $r2->sub($r1)->mul($s)->divide($m2)[1];
                    $save($words[1], $r1->add($b->mul($u)));
                    break;
                case 'MODPOW':
                    checkDivisor($b);
                    if (2 * $b->degree() - 2 > 30) throw new CommandError('ERROR DEGREE LIMIT');
                    $x = Polynomial::one()->divide($b)[1]; $y = $a->divide($b)[1]; $exponent = (int)$words[3];
                    while ($exponent > 0) {
                        if ($exponent % 2 !== 0) $x = $x->mul($y)->divide($b)[1];
                        $exponent = intdiv($exponent, 2);
                        if ($exponent !== 0) $y = $y->mul($y)->divide($b)[1];
                    }
                    $save($words[1], $x);
                    break;
                case 'DERIV': $save($words[1], $a->derivative((int)$words[3])); break;
                case 'INTEG':
                    if ($a->degree() === 30) throw new CommandError('ERROR DEGREE LIMIT');
                    $save($words[1], $a->integral());
                    break;
                case 'AREA':
                    $integral = $a->integral();
                    $upper = $integral->evaluate($literals[1]); $lower = $integral->evaluate($literals[0]);
                    $output[] = 'integral(' . $words[1] . ', ' . $literals[0] . ', ' . $literals[1] . ') = ' . $upper->sub($lower);
                    break;
                case 'TANGENT':
                    $point = $literals[0]; $value = $a->evaluate($point); $slope = $a->derivative()->evaluate($point);
                    $save($words[1], new Polynomial([$value->sub($slope->mul($point)), $slope]));
                    break;
                case 'TAYLOR':
                    $point = $literals[0];
                    $shifted = $a->compose(new Polynomial([$point, Fraction::one()]));
                    $variable = $point->isZero() ? 'x' : ($point->n > 0 ? '(x - ' . $point . ')' : '(x + ' . $point->neg() . ')');
                    $output[] = 'taylor(' . $words[1] . ', ' . $point . ') = ' . $shifted->format($variable);
                    break;
                case 'COMPOSE': checkComposition($a, $b); $save($words[1], $a->compose($b)); break;
                case 'EVAL':
                    foreach ($literals as $point) $output[] = $words[1] . '(' . $point . ') = ' . $a->evaluate($point);
                    break;
                case 'ROOTS':
                    checkNonzero($a);
                    [, , $roots] = rationalRoots($a);
                    $parts = array_map(static fn(Root $root): string => $root->value . ' (' . $root->multiplicity . ')', $roots);
                    $output[] = 'roots(' . $words[1] . ') = ' . ($parts === [] ? 'none' : implode(', ', $parts));
                    break;
                case 'FACTOR':
                    checkNonzero($a);
                    [$content, $remaining, $roots] = rationalRoots($a);
                    $result = 'factor(' . $words[1] . ') = ' . $content;
                    foreach ($roots as $root) {
                        $factor = $root->value->isZero() ? 'x'
                            : '(' . (new Polynomial([new Fraction(-$root->value->n), new Fraction($root->value->d)]))->format() . ')';
                        $result .= ' * ' . $factor;
                        if ($root->multiplicity >= 2) $result .= '^' . $root->multiplicity;
                    }
                    if ($remaining->degree() >= 1) $result .= ' * (' . $remaining->format() . ')';
                    $output[] = $result;
                    break;
                case 'SQFREE':
                    checkNonzero($a);
                    $factors = squareFreeFactors($a);
                    $result = 'sqfree(' . $words[1] . ') = ' . $a->content();
                    foreach ($factors as $factor) {
                        $value = $factor->value;
                        $isX = $value->degree() === 1 && $value->at(0)->isZero() && $value->at(1)->equals(Fraction::one());
                        $result .= ' * ' . ($isX ? 'x' : '(' . $value->format() . ')');
                        if ($factor->multiplicity >= 2) $result .= '^' . $factor->multiplicity;
                    }
                    $output[] = $result;
                    break;
                case 'DESCARTES':
                    checkNonzero($a);
                    $output[] = 'descartes(' . $words[1] . ') = positive ' . descartes($a, false) . ', negative ' . descartes($a, true);
                    break;
                case 'STURM':
                    checkNonzero($a);
                    if ($left->compare($right) >= 0) throw new CommandError('ERROR BAD INTERVAL');
                    $sequence = sturmSequence($a);
                    $output[] = 'sturm(' . $words[1] . ', ' . $left . ', ' . $right . ') = ' . rootCount($sequence, $left, $right);
                    break;
                case 'ISOLATE':
                    checkNonzero($a);
                    $precision = (int)$words[2]; $intervals = isolate($a, $precision);
                    $parts = array_map(static fn(array $interval): string => '(' . $interval[0] . ', ' . $interval[1] . ']', $intervals);
                    $output[] = 'isolate(' . $words[1] . ', ' . $precision . ') = ' . ($parts === [] ? 'none' : implode(', ', $parts));
                    break;
                case 'RESULTANT':
                    checkNonzero($a); checkNonzero($b);
                    $output[] = 'res(' . $words[1] . ', ' . $words[2] . ') = ' . resultant($a, $b);
                    break;
                case 'DISCRIM':
                    checkNonzero($a); checkPositiveDegree($a);
                    $value = resultant($a, $a->derivative())->div($a->leading());
                    if (intdiv($a->degree() * ($a->degree() - 1), 2) % 2 !== 0) $value = $value->neg();
                    $output[] = 'disc(' . $words[1] . ') = ' . $value;
                    break;
                case 'POWERSUM':
                    checkNonzero($a); checkPositiveDegree($a);
                    $count = (int)$words[2]; $monic = $a->monic(); $sums = array_fill(0, $count + 1, Fraction::zero());
                    for ($j = 1; $j <= $count; $j++) {
                        $value = $j <= $a->degree() ? (new Fraction($j))->mul($monic->at($a->degree() - $j)) : Fraction::zero();
                        for ($i = 1; $i <= min($j - 1, $a->degree()); $i++) $value = $value->add($monic->at($a->degree() - $i)->mul($sums[$j - $i]));
                        $sums[$j] = $value->neg();
                    }
                    $output[] = 'powersum(' . $words[1] . ') = ' . implode(', ', array_slice($sums, 1));
                    break;
                case 'INTERP': $save($words[1], interpolate($literals)); break;
                case 'SPECIAL': $save($words[1], special($words[2], (int)$words[3])); break;
            }
        }
        if ($deletion !== null) unset($this->storage[$deletion]);
        foreach ($pending as [$name, $value]) $this->storage[$name] = $value;
        return $output;
    }
}

$count = (int)trim(fgets(STDIN));
$calculator = new Calculator();
for ($i = 0; $i < $count; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        foreach ($calculator->execute($line) as $output) echo $output, "\n";
    } catch (CommandError $error) {
        echo $error->getMessage(), "\n";
    }
}
