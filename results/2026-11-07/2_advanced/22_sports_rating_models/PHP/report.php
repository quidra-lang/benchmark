<?php
declare(strict_types=1);

namespace SportsRatings;

function gcd(int $a, int $b): int
{
    $a = abs($a);
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return $a;
}

final class Fraction
{
    public int $numerator;
    public int $denominator;

    public function __construct(int $numerator, int $denominator = 1)
    {
        if ($denominator < 0) {
            $numerator = -$numerator;
            $denominator = -$denominator;
        }
        $divisor = gcd($numerator, $denominator);
        $this->numerator = intdiv($numerator, $divisor);
        $this->denominator = intdiv($denominator, $divisor);
    }

    public function add(self $other): self
    {
        $common = gcd($this->denominator, $other->denominator);
        return new self(
            $this->numerator * intdiv($other->denominator, $common) + $other->numerator * intdiv($this->denominator, $common),
            intdiv($this->denominator, $common) * $other->denominator
        );
    }

    public function subtract(self $other): self { return $this->add(new self(-$other->numerator, $other->denominator)); }

    public function multiply(self $other): self
    {
        $first = gcd($this->numerator, $other->denominator);
        $second = gcd($other->numerator, $this->denominator);
        return new self(
            intdiv($this->numerator, $first) * intdiv($other->numerator, $second),
            intdiv($this->denominator, $second) * intdiv($other->denominator, $first)
        );
    }

    public function divide(self $other): self { return $this->multiply(new self($other->denominator, $other->numerator)); }
    public function compare(self $other): int { return ($this->numerator * $other->denominator) <=> ($other->numerator * $this->denominator); }
    public function real(): float { return $this->numerator / $this->denominator; }
}

function compareValues(Fraction|int|float $a, Fraction|int|float $b): int
{
    if ($a instanceof Fraction || $b instanceof Fraction) {
        $a = $a instanceof Fraction ? $a : new Fraction((int)$a);
        $b = $b instanceof Fraction ? $b : new Fraction((int)$b);
        return $a->compare($b);
    }
    return $a <=> $b;
}

function fixed(Fraction|int|float $value, int $places = 4): string
{
    if ($value instanceof Fraction) {
        $magnitude = abs($value->numerator);
        $whole = intdiv($magnitude, $value->denominator);
        $remainder = $magnitude % $value->denominator;
        $scale = 1;
        $fraction = 0;
        for ($index = 0; $index < $places; $index++) {
            $remainder *= 10;
            $fraction = $fraction * 10 + intdiv($remainder, $value->denominator);
            $remainder %= $value->denominator;
            $scale *= 10;
        }
        if (2 * $remainder >= $value->denominator) {
            $fraction++;
        }
        if ($fraction === $scale) {
            $whole++;
            $fraction = 0;
        }
        $sign = $value->numerator < 0 && ($whole > 0 || $fraction > 0) ? '-' : '';
        return $sign . $whole . '.' . str_pad((string)$fraction, $places, '0', STR_PAD_LEFT);
    }
    if (is_int($value)) {
        return $value . '.' . str_repeat('0', $places);
    }
    $rounded = round($value, $places, PHP_ROUND_HALF_UP);
    return number_format($rounded == 0 ? 0 : $rounded, $places, '.', '');
}

function fractionText(Fraction $value): string { return $value->numerator . '/' . $value->denominator; }
function fractionWithReal(Fraction $value): string { return fractionText($value) . ' ' . fixed($value); }
function decimalValue(float $value, int $places): int
{
    $scale = 1;
    for ($index = 0; $index < $places; $index++) {
        $scale *= 10;
    }
    return (int)round($value * $scale, 0, PHP_ROUND_HALF_UP);
}

function writeLines(string $path, array $lines): void
{
    file_put_contents($path, $lines === [] ? '' : implode("\n", $lines) . "\n");
}
