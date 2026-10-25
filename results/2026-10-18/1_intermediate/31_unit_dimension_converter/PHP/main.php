<?php
declare(strict_types=1);

final class CommandError extends Exception {
    public function __construct(string $message) { parent::__construct('ERROR ' . $message); }
}

final readonly class Fraction {
    public int $n;
    public int $d;
    public function __construct(int $n, int $d = 1) {
        if ($d < 0) { $n = -$n; $d = -$d; }
        $a = abs($n); $b = $d;
        while ($b !== 0) [$a, $b] = [$b, $a % $b];
        $this->n = intdiv($n, $a);
        $this->d = intdiv($d, $a);
    }
    public static function parse(string $text): self {
        if (!preg_match('/\A-?[0-9]+(?:[.\/][0-9]+)?\z/', $text)) throw new CommandError("BAD NUMBER $text");
        $negative = str_starts_with($text, '-');
        $body = $negative ? substr($text, 1) : $text;
        $separator = strcspn($body, './');
        $first = substr($body, 0, $separator);
        $n = (int)$first; $d = 1;
        if ($separator < strlen($body)) {
            $second = substr($body, $separator + 1);
            if ($body[$separator] === '/') {
                $d = (int)$second;
                if ($d === 0) throw new CommandError("BAD NUMBER $text");
            } else {
                for ($i = 0; $i < strlen($second); $i++) $d *= 10;
                $n = $n * $d + (int)$second;
            }
        }
        return new self($negative ? -$n : $n, $d);
    }
    public function add(self $b): self { return new self($this->n * $b->d + $b->n * $this->d, $this->d * $b->d); }
    public function sub(self $b): self { return new self($this->n * $b->d - $b->n * $this->d, $this->d * $b->d); }
    public function mul(self $b): self { return new self($this->n * $b->n, $this->d * $b->d); }
    public function div(self $b): self { return new self($this->n * $b->d, $this->d * $b->n); }
    public function neg(): self { return new self(-$this->n, $this->d); }
    public function magnitude(): self { return new self(abs($this->n), $this->d); }
    public function same(self $b): bool { return $this->n === $b->n && $this->d === $b->d; }
    public function compare(self $b): int { return ($this->n * $b->d) <=> ($b->n * $this->d); }
    public function power(int $exponent): self {
        $factor = $exponent < 0 ? (new self(1))->div($this) : $this;
        $result = new self(1);
        for ($i = 0; $i < abs($exponent); $i++) $result = $result->mul($factor);
        return $result;
    }
    public function decimal(): string {
        $magnitude = abs($this->n);
        $whole = intdiv($magnitude, $this->d);
        $places = str_pad((string)intdiv($magnitude % $this->d * 1000000, $this->d), 6, '0', STR_PAD_LEFT);
        return ($this->n < 0 ? '-' : '') . "$whole.$places";
    }
    public function __toString(): string { return $this->d === 1 ? (string)$this->n : "$this->n/$this->d"; }
}

final readonly class Dimension {
    public function __construct(public array $exponents = [0, 0, 0, 0, 0, 0, 0]) {}
    public function same(self $b): bool { return $this->exponents === $b->exponents; }
    public function isZero(): bool { return $this->exponents === [0, 0, 0, 0, 0, 0, 0]; }
    public function isEven(): bool {
        foreach ($this->exponents as $value) if ($value % 2 !== 0) return false;
        return true;
    }
    public function add(self $b): self {
        $result = [];
        foreach ($this->exponents as $i => $value) $result[] = $value + $b->exponents[$i];
        return new self($result);
    }
    public function sub(self $b): self {
        $result = [];
        foreach ($this->exponents as $i => $value) $result[] = $value - $b->exponents[$i];
        return new self($result);
    }
    public function scale(int $factor): self { return new self(array_map(fn(int $x): int => $x * $factor, $this->exponents)); }
    public function half(): self { return new self(array_map(fn(int $x): int => intdiv($x, 2), $this->exponents)); }
    public function __toString(): string {
        $symbols = ['kg', 'm', 's', 'A', 'K', 'mol', 'cd'];
        $parts = [];
        foreach ($this->exponents as $i => $value) {
            if ($value !== 0) $parts[] = $value === 1 ? $symbols[$i] : $symbols[$i] . "^$value";
        }
        return $parts === [] ? '1' : implode(' ', $parts);
    }
}
final readonly class Quantity {
    public function __construct(public Fraction $value, public Dimension $dimension) {}
}
final readonly class Definition {
    public function __construct(public Fraction $value, public string $expression) {}
}
final readonly class Unit {
    public function __construct(public string $symbol, public Quantity $quantity, public bool $prefix,
                                public ?Definition $definition = null) {}
}

enum TokenKind { case Number; case Identifier; case Unit; case Symbol; case Invalid; case End; }
final readonly class Token {
    public function __construct(public TokenKind $kind, public string $text, public int $position) {}
}
abstract class Parser {
    private array $tokens = [];
    private int $index = 0;
    public function __construct(private readonly string $source, bool $quantity) {
        for ($i = 0; $i < strlen($source);) {
            $start = $i++;
            $c = $source[$start];
            if (self::letter($c)) {
                while ($i < strlen($source) && self::letter($source[$i])) $i++;
                $kind = TokenKind::Identifier;
            } elseif (self::digit($c)) {
                while ($i < strlen($source) && self::digit($source[$i])) $i++;
                if ($quantity && $i + 1 < strlen($source) && $source[$i] === '.' && self::digit($source[$i + 1])) {
                    $i += 2;
                    while ($i < strlen($source) && self::digit($source[$i])) $i++;
                }
                $kind = TokenKind::Number;
            } else {
                $end = $quantity && $c === '[' ? strpos($source, ']', $i) : false;
                if ($end !== false && $end > $i) {
                    $i = $end + 1;
                    $kind = TokenKind::Unit;
                } else {
                    $kind = str_contains($quantity ? '+-*/^(),' : '*/^()-', $c) ? TokenKind::Symbol : TokenKind::Invalid;
                }
            }
            $this->tokens[] = new Token($kind, substr($source, $start, $i - $start), $start + 1);
        }
        $this->tokens[] = new Token(TokenKind::End, '', strlen($source) + 1);
    }
    public static function letter(string $c): bool {
        $n = ord($c);
        return ($n >= 65 && $n <= 90) || ($n >= 97 && $n <= 122);
    }
    private static function digit(string $c): bool { $n = ord($c); return $n >= 48 && $n <= 57; }
    protected function current(): Token { return $this->tokens[$this->index]; }
    protected function advance(): Token { return $this->tokens[$this->index++]; }
    protected function take(string $text): bool {
        if ($this->current()->text !== $text) return false;
        $this->index++;
        return true;
    }
    protected function syntax(): CommandError {
        $token = $this->current();
        $position = $token->kind === TokenKind::End ? 'END' : (string)$token->position;
        return new CommandError("SYNTAX $this->source AT $position");
    }
    protected function expect(string $text): void { if (!$this->take($text)) throw $this->syntax(); }
    protected function finish(): void { if ($this->current()->kind !== TokenKind::End) throw $this->syntax(); }
    protected function exponent(): string {
        $sign = $this->take('-') ? '-' : '';
        if ($this->current()->kind !== TokenKind::Number || str_contains($this->current()->text, '.')) throw $this->syntax();
        return $sign . $this->advance()->text;
    }
}

interface UnitNode {}
final readonly class UnitName implements UnitNode {
    public function __construct(public string $name) {}
}
final readonly class UnitNumber implements UnitNode {
    public function __construct(public string $text) {}
}
final readonly class UnitPower implements UnitNode {
    public function __construct(public UnitNode $atom, public string $exponent) {}
}
final readonly class UnitProduct implements UnitNode {
    public function __construct(public array $terms) {}
}
final class UnitParser extends Parser {
    public function __construct(string $source) { parent::__construct($source, false); }
    public function parse(): UnitNode { $node = $this->expression(); $this->finish(); return $node; }
    private function expression(): UnitNode {
        $terms = [['*', $this->term()]];
        while (in_array($this->current()->text, ['*', '/'], true)) {
            $op = $this->advance()->text;
            $terms[] = [$op, $this->term()];
        }
        return new UnitProduct($terms);
    }
    private function term(): UnitNode {
        $token = $this->current();
        if ($token->kind === TokenKind::Identifier) {
            $atom = new UnitName($this->advance()->text);
        } elseif ($token->kind === TokenKind::Number && $token->text[0] !== '0') {
            $atom = new UnitNumber($this->advance()->text);
        } elseif ($this->take('(')) {
            $atom = $this->expression();
            $this->expect(')');
        } else throw $this->syntax();
        return $this->take('^') ? new UnitPower($atom, $this->exponent()) : $atom;
    }
}

interface QuantityNode {}
final readonly class Literal implements QuantityNode {
    public function __construct(public string $number, public ?string $unit = null) {}
}
final readonly class Variable implements QuantityNode {
    public function __construct(public string $name) {}
}
final readonly class Binary implements QuantityNode {
    public function __construct(public string $op, public QuantityNode $left, public QuantityNode $right) {}
}
final readonly class Power implements QuantityNode {
    public function __construct(public QuantityNode $base, public string $exponent) {}
}
final readonly class Negative implements QuantityNode {
    public function __construct(public QuantityNode $operand) {}
}
final readonly class Call implements QuantityNode {
    public function __construct(public string $name, public array $arguments) {}
}
final class QuantityParser extends Parser {
    public function __construct(string $source) { parent::__construct($source, true); }
    public function parse(): QuantityNode { $node = $this->expression(); $this->finish(); return $node; }
    private function expression(): QuantityNode {
        $node = $this->product();
        while (in_array($this->current()->text, ['+', '-'], true)) {
            $op = $this->advance()->text;
            $node = new Binary($op, $node, $this->product());
        }
        return $node;
    }
    private function product(): QuantityNode {
        $node = $this->unary();
        while (in_array($this->current()->text, ['*', '/'], true)) {
            $op = $this->advance()->text;
            $node = new Binary($op, $node, $this->unary());
        }
        return $node;
    }
    private function unary(): QuantityNode {
        if ($this->take('-')) return new Negative($this->unary());
        $node = $this->primary();
        return $this->take('^') ? new Power($node, $this->exponent()) : $node;
    }
    private function primary(): QuantityNode {
        if ($this->current()->kind === TokenKind::Number) {
            $number = $this->advance()->text;
            return new Literal($number, $this->current()->kind === TokenKind::Unit ? $this->unitString() : null);
        }
        if ($this->current()->kind === TokenKind::Unit) return new Literal('1', $this->unitString());
        if ($this->current()->kind === TokenKind::Identifier) {
            $name = $this->advance()->text;
            if (!$this->take('(')) return new Variable($name);
            $arguments = [$this->expression()];
            while ($this->take(',')) $arguments[] = $this->expression();
            $this->expect(')');
            return new Call($name, $arguments);
        }
        if ($this->take('(')) {
            $node = $this->expression();
            $this->expect(')');
            return $node;
        }
        throw $this->syntax();
    }
    private function unitString(): string { return substr($this->advance()->text, 1, -1); }
}
final readonly class ParsedUnit {
    public function __construct(public UnitNode $tree, public Quantity $quantity, public array $names) {}
}
final readonly class Reduced {
    public function __construct(public Fraction $coefficient, public array $exponents) {}
}

final class Calculator {
    private const KIND_EXPONENTS = [
        'dimensionless' => [0, 0, 0, 0, 0, 0, 0], 'length' => [0, 1, 0, 0, 0, 0, 0], 'mass' => [1, 0, 0, 0, 0, 0, 0],
        'time' => [0, 0, 1, 0, 0, 0, 0], 'current' => [0, 0, 0, 1, 0, 0, 0], 'temperature' => [0, 0, 0, 0, 1, 0, 0],
        'amount' => [0, 0, 0, 0, 0, 1, 0], 'luminous_intensity' => [0, 0, 0, 0, 0, 0, 1], 'area' => [0, 2, 0, 0, 0, 0, 0],
        'volume' => [0, 3, 0, 0, 0, 0, 0], 'speed' => [0, 1, -1, 0, 0, 0, 0], 'acceleration' => [0, 1, -2, 0, 0, 0, 0],
        'density' => [1, -3, 0, 0, 0, 0, 0], 'momentum' => [1, 1, -1, 0, 0, 0, 0],
        'force' => [1, 1, -2, 0, 0, 0, 0], 'energy' => [1, 2, -2, 0, 0, 0, 0],
        'power' => [1, 2, -3, 0, 0, 0, 0], 'pressure' => [1, -1, -2, 0, 0, 0, 0],
        'frequency' => [0, 0, -1, 0, 0, 0, 0], 'charge' => [0, 0, 1, 1, 0, 0, 0],
        'voltage' => [1, 2, -3, -1, 0, 0, 0], 'resistance' => [1, 2, -3, -2, 0, 0, 0],
        'conductance' => [-1, -2, 3, 2, 0, 0, 0], 'capacitance' => [-1, -2, 4, 2, 0, 0, 0],
        'magnetic_flux' => [1, 2, -2, -1, 0, 0, 0], 'flux_density' => [1, 0, -2, -1, 0, 0, 0],
        'inductance' => [1, 2, -2, -2, 0, 0, 0], 'illuminance' => [0, -2, 0, 0, 0, 0, 1],
        'catalytic_activity' => [0, 0, -1, 0, 0, 1, 0],
    ];
    private array $units = [];
    private array $variables = [];
    private array $prefixes;

    public function __construct() {
        $this->prefixes = [
            ['G', new Fraction(1000000000)], ['M', new Fraction(1000000)], ['k', new Fraction(1000)],
            ['h', new Fraction(100)], ['da', new Fraction(10)], ['d', new Fraction(1, 10)], ['c', new Fraction(1, 100)],
            ['m', new Fraction(1, 1000)], ['u', new Fraction(1, 1000000)], ['n', new Fraction(1, 1000000000)],
        ];
        $add = function(string $symbol, int $n, int $d, string $kind, bool $prefix): void {
            $this->units[] = new Unit($symbol, new Quantity(new Fraction($n, $d), new Dimension(self::KIND_EXPONENTS[$kind])), $prefix);
        };
        $add('m', 1, 1, 'length', true); $add('g', 1, 1000, 'mass', true);
        $add('s', 1, 1, 'time', true); $add('A', 1, 1, 'current', true); $add('K', 1, 1, 'temperature', true);
        $add('mol', 1, 1, 'amount', true); $add('cd', 1, 1, 'luminous_intensity', true);
        $add('N', 1, 1, 'force', true); $add('J', 1, 1, 'energy', true); $add('W', 1, 1, 'power', true);
        $add('Pa', 1, 1, 'pressure', true); $add('Hz', 1, 1, 'frequency', true); $add('C', 1, 1, 'charge', true);
        $add('V', 1, 1, 'voltage', true); $add('ohm', 1, 1, 'resistance', true);
        $add('S', 1, 1, 'conductance', true); $add('F', 1, 1, 'capacitance', true);
        $add('Wb', 1, 1, 'magnetic_flux', true); $add('T', 1, 1, 'flux_density', true);
        $add('H', 1, 1, 'inductance', true); $add('lx', 1, 1, 'illuminance', true);
        $add('kat', 1, 1, 'catalytic_activity', true); $add('L', 1, 1000, 'volume', true);
        $add('t', 1000, 1, 'mass', false); $add('min', 60, 1, 'time', false);
        $add('h', 3600, 1, 'time', false); $add('day', 86400, 1, 'time', false);
        $add('in', 127, 5000, 'length', false); $add('ft', 381, 1250, 'length', false);
        $add('yd', 1143, 1250, 'length', false); $add('mi', 201168, 125, 'length', false);
        $add('nmi', 1852, 1, 'length', false); $add('ha', 10000, 1, 'area', false);
        $add('kn', 463, 900, 'speed', false); $add('bar', 100000, 1, 'pressure', true);
        $add('atm', 101325, 1, 'pressure', false); $add('Torr', 20265, 152, 'pressure', false);
        $add('cal', 523, 125, 'energy', true); $add('Wh', 3600, 1, 'energy', true);
        $add('Ah', 3600, 1, 'charge', true); $add('dC', 1, 1, 'temperature', false); $add('dF', 5, 9, 'temperature', false);
    }
    private function resolve(string $name): ?Quantity {
        foreach ($this->units as $unit) if ($unit->symbol === $name) return $unit->quantity;
        foreach ($this->prefixes as [$symbol, $factor]) {
            foreach ($this->units as $unit) {
                if ($unit->definition === null && $unit->prefix && $name === ($symbol . $unit->symbol)) {
                    return new Quantity($factor->mul($unit->quantity->value), $unit->quantity->dimension);
                }
            }
        }
        return null;
    }
    private static function kind(Dimension $dimension): string {
        foreach (self::KIND_EXPONENTS as $name => $exponents) if ($dimension->exponents === $exponents) return $name;
        return '-';
    }
    private function simplified(Dimension $dimension): string {
        foreach ($this->units as $unit) {
            if ($unit->quantity->dimension->same($dimension) && $unit->quantity->value->same(new Fraction(1))) return $unit->symbol;
        }
        return (string)$dimension;
    }
    private static function format(Fraction $value, string $unit): string { return "$value $unit (" . $value->decimal() . ')'; }
    private function formatQuantity(Quantity $quantity): string { return self::format($quantity->value, $this->simplified($quantity->dimension)); }
    private static function matchDimensions(Dimension $a, Dimension $b): void {
        if (!$a->same($b)) throw new CommandError("DIMENSION MISMATCH $a vs $b");
    }
    private static function checkExponent(string $text): int {
        $value = (int)$text;
        if ($value < -3 || $value === 0 || $value > 3) throw new CommandError("BAD EXPONENT $text");
        return $value;
    }
    private static function checkName(string $name, bool $variable): void {
        if (!preg_match('/\A[A-Za-z]{1,12}\z/', $name) || $variable && in_array($name, ['abs', 'sqrt', 'min', 'max'], true)) {
            throw new CommandError("BAD NAME $name");
        }
    }
    private function parseUnit(string $text): ParsedUnit {
        $tree = (new UnitParser($text))->parse();
        $names = [];
        $this->validateUnit($tree, $names);
        return new ParsedUnit($tree, $this->unitValue($tree), $names);
    }
    private function validateUnit(UnitNode $node, array &$names): void {
        if ($node instanceof UnitName) {
            if ($this->resolve($node->name) === null) throw new CommandError("UNKNOWN UNIT $node->name");
            if (!in_array($node->name, $names, true)) $names[] = $node->name;
        } elseif ($node instanceof UnitPower) {
            $this->validateUnit($node->atom, $names);
            self::checkExponent($node->exponent);
        } elseif ($node instanceof UnitProduct) {
            foreach ($node->terms as [$op, $term]) $this->validateUnit($term, $names);
        }
    }
    private function unitValue(UnitNode $node): Quantity {
        if ($node instanceof UnitName) return $this->resolve($node->name);
        if ($node instanceof UnitNumber) return new Quantity(new Fraction((int)$node->text), new Dimension());
        if ($node instanceof UnitPower) {
            $atom = $this->unitValue($node->atom);
            $exponent = (int)$node->exponent;
            return new Quantity($atom->value->power($exponent), $atom->dimension->scale($exponent));
        }
        if ($node instanceof UnitProduct) {
            $result = new Quantity(new Fraction(1), new Dimension());
            foreach ($node->terms as [$op, $term]) {
                $value = $this->unitValue($term);
                $result = $op === '*'
                    ? new Quantity($result->value->mul($value->value), $result->dimension->add($value->dimension))
                    : new Quantity($result->value->div($value->value), $result->dimension->sub($value->dimension));
            }
            return $result;
        }
        throw new LogicException('Unknown unit node');
    }
    private static function reduce(UnitNode $node): Reduced {
        if ($node instanceof UnitName) return new Reduced(new Fraction(1), [$node->name => 1]);
        if ($node instanceof UnitNumber) return new Reduced(new Fraction((int)$node->text), []);
        if ($node instanceof UnitPower) {
            $atom = self::reduce($node->atom);
            $exponent = (int)$node->exponent;
            $powers = [];
            foreach ($atom->exponents as $name => $value) $powers[$name] = $value * $exponent;
            return new Reduced($atom->coefficient->power($exponent), $powers);
        }
        if ($node instanceof UnitProduct) {
            $coefficient = new Fraction(1); $exponents = [];
            foreach ($node->terms as [$op, $term]) {
                $value = self::reduce($term);
                $coefficient = $op === '*' ? $coefficient->mul($value->coefficient) : $coefficient->div($value->coefficient);
                foreach ($value->exponents as $name => $power) $exponents[$name] = ($exponents[$name] ?? 0) + ($op === '*' ? $power : -$power);
            }
            return new Reduced($coefficient, $exponents);
        }
        throw new LogicException('Unknown unit node');
    }
    private static function reducedText(ParsedUnit $parsed): string {
        $reduced = self::reduce($parsed->tree);
        $parts = [];
        if (!$reduced->coefficient->same(new Fraction(1))) $parts[] = (string)$reduced->coefficient;
        foreach ($parsed->names as $name) {
            $exponent = $reduced->exponents[$name];
            if ($exponent !== 0) $parts[] = $exponent === 1 ? $name : "$name^$exponent";
        }
        return $parts === [] ? '1' : implode(' ', $parts);
    }
    private static function integerRoot(int $number): int {
        $low = 0; $high = $number + 1;
        while ($high - $low > 1) {
            $middle = $low + intdiv($high - $low, 2);
            if ($middle <= intdiv($number, $middle)) $low = $middle;
            else $high = $middle;
        }
        return $low;
    }
    private function evaluate(QuantityNode $node): Quantity {
        if ($node instanceof Literal) {
            if ($node->unit === null) return new Quantity(Fraction::parse($node->number), new Dimension());
            $unit = $this->parseUnit($node->unit)->quantity;
            return new Quantity(Fraction::parse($node->number)->mul($unit->value), $unit->dimension);
        }
        if ($node instanceof Variable) return $this->variables[$node->name] ?? throw new CommandError("UNKNOWN VARIABLE $node->name");
        if ($node instanceof Negative) {
            $operand = $this->evaluate($node->operand);
            return new Quantity($operand->value->neg(), $operand->dimension);
        }
        if ($node instanceof Power) {
            $base = $this->evaluate($node->base);
            $exponent = self::checkExponent($node->exponent);
            if ($base->value->n === 0 && $exponent < 0) throw new CommandError('DIVISION BY ZERO');
            return new Quantity($base->value->power($exponent), $base->dimension->scale($exponent));
        }
        if ($node instanceof Binary) {
            $a = $this->evaluate($node->left);
            $b = $this->evaluate($node->right);
            if ($node->op === '+' || $node->op === '-') {
                self::matchDimensions($a->dimension, $b->dimension);
                return new Quantity($node->op === '+' ? $a->value->add($b->value) : $a->value->sub($b->value), $a->dimension);
            }
            if ($node->op === '*') return new Quantity($a->value->mul($b->value), $a->dimension->add($b->dimension));
            if ($b->value->n === 0) throw new CommandError('DIVISION BY ZERO');
            return new Quantity($a->value->div($b->value), $a->dimension->sub($b->dimension));
        }
        if ($node instanceof Call) {
            if (!in_array($node->name, ['abs', 'sqrt', 'min', 'max'], true)) throw new CommandError("UNKNOWN FUNCTION $node->name");
            $count = in_array($node->name, ['abs', 'sqrt'], true) ? 1 : 2;
            if (count($node->arguments) !== $count) throw new CommandError("BAD ARGUMENTS $node->name");
            $a = $this->evaluate($node->arguments[0]);
            if ($node->name === 'abs') return new Quantity($a->value->magnitude(), $a->dimension);
            if ($node->name === 'sqrt') {
                if ($a->value->n < 0) throw new CommandError('NEGATIVE ROOT');
                if (!$a->dimension->isEven()) throw new CommandError("ODD DIMENSION $a->dimension");
                $p = self::integerRoot($a->value->n); $q = self::integerRoot($a->value->d);
                if ($p * $p !== $a->value->n || $q * $q !== $a->value->d) throw new CommandError('NOT EXACT');
                return new Quantity(new Fraction($p, $q), $a->dimension->half());
            }
            $b = $this->evaluate($node->arguments[1]);
            self::matchDimensions($a->dimension, $b->dimension);
            $comparison = $a->value->compare($b->value);
            return $node->name === 'min' ? ($comparison <= 0 ? $a : $b) : ($comparison >= 0 ? $a : $b);
        }
        throw new LogicException('Unknown quantity node');
    }
    private function matching(Dimension $dimension): array {
        $selected = array_values(array_filter($this->units, fn(Unit $unit): bool => $unit->quantity->dimension->same($dimension)));
        usort($selected, function(Unit $a, Unit $b): int {
            $comparison = $a->quantity->value->compare($b->quantity->value);
            return $comparison !== 0 ? $comparison : strcmp($a->symbol, $b->symbol);
        });
        return $selected;
    }

    public function execute(string $line): string {
        $w = explode(' ', $line); $command = $w[0];
        switch ($command) {
            case 'DEFINE':
                self::checkName($w[1], false);
                $value = Fraction::parse($w[3]);
                $unit = $this->parseUnit($w[4])->quantity;
                if (array_key_exists($w[1], self::KIND_EXPONENTS) || $this->resolve($w[1]) !== null) throw new CommandError("NAME TAKEN $w[1]");
                if ($value->n <= 0) throw new CommandError("NOT POSITIVE $w[3]");
                $defined = new Quantity($value->mul($unit->value), $unit->dimension);
                $this->units[] = new Unit($w[1], $defined, false, new Definition($value, $w[4]));
                return "DEFINE $w[1] factor=$defined->value dim=$defined->dimension kind=" . self::kind($defined->dimension);
            case 'UNDEF':
                $index = null;
                foreach ($this->units as $i => $unit) if ($unit->symbol === $w[1]) { $index = $i; break; }
                if ($index !== null && $this->units[$index]->definition === null) throw new CommandError("BUILTIN UNIT $w[1]");
                if ($index === null) throw new CommandError("NOT DEFINED $w[1]");
                array_splice($this->units, $index, 1);
                return "UNDEF $w[1]";
            case 'DEFS':
                $users = array_values(array_filter($this->units, fn(Unit $unit): bool => $unit->definition !== null));
                $lines = ['DEFS count=' . count($users)];
                foreach ($users as $unit) {
                    $definition = $unit->definition; $quantity = $unit->quantity;
                    $lines[] = "DEF $unit->symbol = $definition->value $definition->expression factor=$quantity->value dim=$quantity->dimension";
                }
                return implode("\n", $lines);
            case 'CONVERT': case 'INVERT':
                $value = Fraction::parse($w[1]);
                $a = $this->parseUnit($w[2])->quantity;
                $b = $this->parseUnit($w[4])->quantity;
                if ($command === 'CONVERT') self::matchDimensions($a->dimension, $b->dimension);
                else {
                    if ($a->dimension->isZero() || !$a->dimension->add($b->dimension)->isZero()) throw new CommandError("NOT RECIPROCAL $a->dimension vs $b->dimension");
                    if ($value->n === 0) throw new CommandError('DIVISION BY ZERO');
                }
                $result = $command === 'CONVERT' ? $value->mul($a->value)->div($b->value) : (new Fraction(1))->div($value->mul($a->value))->div($b->value);
                return "$command $value $w[2] = " . self::format($result, $w[4]);
            case 'DIM': case 'REDUCE': case 'SIMPLIFY':
                $parsed = $this->parseUnit($w[1]); $unit = $parsed->quantity;
                return match ($command) {
                    'DIM' => "DIM $w[1] = $unit->dimension factor=$unit->value kind=" . self::kind($unit->dimension),
                    'REDUCE' => "REDUCE $w[1] = " . self::reducedText($parsed),
                    default => "SIMPLIFY $w[1] = " . $this->formatQuantity($unit),
                };
            case 'ADD': case 'SUB': case 'MUL': case 'DIV': case 'COMPARE':
                $x = Fraction::parse($w[1]);
                $a = $this->parseUnit($w[2])->quantity;
                $y = Fraction::parse($w[3]);
                $b = $this->parseUnit($w[4])->quantity;
                $target = count($w) === 7 ? $this->parseUnit($w[6])->quantity : null;
                if ($command === 'COMPARE') {
                    self::matchDimensions($a->dimension, $b->dimension);
                    $left = $x->mul($a->value); $right = $y->mul($b->value);
                    $comparison = $left->compare($right);
                    $relation = $comparison < 0 ? '<' : ($comparison > 0 ? '>' : '=');
                    $ratio = $right->n === 0 ? 'undefined' : (string)$left->div($right);
                    return "COMPARE $x $w[2] $relation $y $w[4] ratio=$ratio";
                }
                $op = match ($command) { 'ADD' => '+', 'SUB' => '-', 'MUL' => '*', default => '/' };
                $prefix = "$command $x $w[2] $op $y $w[4] = ";
                if ($command === 'ADD' || $command === 'SUB') {
                    self::matchDimensions($a->dimension, $b->dimension);
                    if ($target !== null) self::matchDimensions($a->dimension, $target->dimension);
                    $left = $x->mul($a->value); $right = $y->mul($b->value);
                    $sum = $command === 'ADD' ? $left->add($right) : $left->sub($right);
                    return $prefix . self::format($sum->div($target?->value ?? $a->value), $target === null ? $w[2] : $w[6]);
                }
                $dimension = $command === 'MUL' ? $a->dimension->add($b->dimension) : $a->dimension->sub($b->dimension);
                if ($command === 'DIV' && $y->n === 0) throw new CommandError('DIVISION BY ZERO');
                if ($target !== null) self::matchDimensions($dimension, $target->dimension);
                $product = $command === 'MUL' ? $x->mul($y) : $x->div($y);
                $first = $x->mul($a->value); $second = $y->mul($b->value);
                $coherent = $command === 'MUL' ? $first->mul($second) : $first->div($second);
                if ($target !== null) return $prefix . self::format($coherent->div($target->value), $w[6]);
                $rightUnit = $command === 'DIV' && (str_contains($w[4], '*') || str_contains($w[4], '/')) ? "($w[4])" : $w[4];
                return "$prefix$product $w[2]$op$rightUnit = " . self::format($coherent, $this->simplified($dimension));
            case 'TEMP':
                $value = Fraction::parse($w[1]);
                foreach ([$w[2], $w[4]] as $scale) if (!in_array($scale, ['C', 'F', 'K', 'R'], true)) throw new CommandError("UNKNOWN SCALE $scale");
                $kelvin = match ($w[2]) {
                    'C' => $value->add(new Fraction(5463, 20)),
                    'F' => $value->add(new Fraction(45967, 100))->mul(new Fraction(5))->div(new Fraction(9)),
                    'R' => $value->mul(new Fraction(5))->div(new Fraction(9)), default => $value,
                };
                if ($kelvin->n < 0) throw new CommandError('BELOW ABSOLUTE ZERO');
                $result = match ($w[4]) {
                    'C' => $kelvin->sub(new Fraction(5463, 20)),
                    'F' => $kelvin->mul(new Fraction(9))->div(new Fraction(5))->sub(new Fraction(45967, 100)),
                    'R' => $kelvin->mul(new Fraction(9))->div(new Fraction(5)), default => $kelvin,
                };
                return "TEMP $value $w[2] = " . self::format($result, $w[4]);
            case 'LIST':
                $dimension = array_key_exists($w[1], self::KIND_EXPONENTS) ? new Dimension(self::KIND_EXPONENTS[$w[1]]) : $this->parseUnit($w[1])->quantity->dimension;
                $selected = $this->matching($dimension);
                $lines = ["LIST $w[1] dim=$dimension kind=" . self::kind($dimension) . ' count=' . count($selected)];
                foreach ($selected as $unit) {
                    $origin = $unit->definition === null ? 'builtin' : 'user'; $prefix = $unit->prefix ? 'yes' : 'no';
                    $factor = $unit->quantity->value;
                    $lines[] = "UNIT $unit->symbol factor=$factor origin=$origin prefix=$prefix";
                }
                return implode("\n", $lines);
            case 'TABLE': case 'AUTO': case 'SPLIT':
                $value = Fraction::parse($w[1]);
                $unit = $this->parseUnit($w[2])->quantity;
                if ($command === 'TABLE') {
                    $selected = $this->matching($unit->dimension);
                    $lines = ["TABLE $value $w[2] dim=$unit->dimension count=" . count($selected)];
                    foreach ($selected as $row) $lines[] = 'ROW ' . self::format($value->mul($unit->value)->div($row->quantity->value), $row->symbol);
                    return implode("\n", $lines);
                }
                if ($command === 'AUTO') {
                    $basis = null;
                    foreach ($this->units as $candidate) {
                        if ($candidate->definition === null && $candidate->prefix && $candidate->quantity->dimension->same($unit->dimension)) { $basis = $candidate; break; }
                    }
                    if ($basis === null) throw new CommandError("NO PREFIXABLE UNIT $unit->dimension");
                    $scaled = $value->mul($unit->value)->div($basis->quantity->value); $magnitude = $scaled->magnitude();
                    $exponent = 0;
                    if ($magnitude->compare(new Fraction(1)) >= 0) {
                        while ($exponent < 9 && $magnitude->compare((new Fraction(10))->power($exponent + 3)) >= 0) $exponent += 3;
                    } elseif ($magnitude->n !== 0) {
                        while ($exponent > -9 && $magnitude->compare((new Fraction(10))->power($exponent)) < 0) $exponent -= 3;
                    }
                    $prefix = match ($exponent) { 9 => 'G', 6 => 'M', 3 => 'k', -3 => 'm', -6 => 'u', -9 => 'n', default => '' };
                    return "AUTO $value $w[2] = " . self::format($scaled->div((new Fraction(10))->power($exponent)), $prefix . $basis->symbol);
                }
                $parts = explode(',', $w[4]); $destinations = [];
                foreach ($parts as $part) $destinations[] = $this->parseUnit($part)->quantity;
                if ($value->n < 0) throw new CommandError('NEGATIVE VALUE');
                foreach ($destinations as $destination) self::matchDimensions($unit->dimension, $destination->dimension);
                for ($i = 1; $i < count($destinations); $i++) {
                    if ($destinations[$i - 1]->value->compare($destinations[$i]->value) <= 0) throw new CommandError('UNIT ORDER');
                }
                $remaining = $value->mul($unit->value); $pieces = [];
                for ($i = 0; $i < count($parts) - 1; $i++) {
                    $quotient = $remaining->div($destinations[$i]->value);
                    $whole = intdiv($quotient->n, $quotient->d);
                    $remaining = $remaining->sub((new Fraction($whole))->mul($destinations[$i]->value));
                    $pieces[] = "$whole $parts[$i]";
                }
                $last = count($parts) - 1;
                $pieces[] = self::format($remaining->div($destinations[$last]->value), $parts[$last]);
                return "SPLIT $value $w[2] = " . implode(' ', $pieces);
            case 'LET':
                self::checkName($w[1], true);
                $value = $this->evaluate((new QuantityParser($w[3]))->parse());
                $this->variables[$w[1]] = $value;
                return "LET $w[1] = " . $this->formatQuantity($value);
            case 'EVAL':
                $value = $this->evaluate((new QuantityParser($w[1]))->parse());
                if (count($w) === 4) {
                    $unit = $this->parseUnit($w[3])->quantity;
                    self::matchDimensions($value->dimension, $unit->dimension);
                    return "EVAL $w[1] = " . self::format($value->value->div($unit->value), $w[3]);
                }
                return "EVAL $w[1] = " . $this->formatQuantity($value);
            case 'VARS':
                $names = array_keys($this->variables);
                sort($names, SORT_STRING);
                $lines = ['VARS count=' . count($names)];
                foreach ($names as $name) $lines[] = "VAR $name = " . $this->formatQuantity($this->variables[$name]);
                return implode("\n", $lines);
            default:
                throw new CommandError("UNKNOWN COMMAND $command");
        }
    }
}

$calculator = new Calculator();
$count = (int)trim(fgets(STDIN));
for ($i = 0; $i < $count; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try { echo $calculator->execute($line), "\n"; }
    catch (CommandError $error) { echo $error->getMessage(), "\n"; }
}
