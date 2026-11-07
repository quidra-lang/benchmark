<?php

final readonly class Rational
{
    public int $n, $d;

    public function __construct(int $n = 0, int $d = 1)
    {
        if ($d < 0) {
            $n = -$n;
            $d = -$d;
        }
        $a = abs($n);
        $b = $d;
        while ($b)
            [$a, $b] = [$b, $a % $b];
        $this->n = intdiv($n, $a);
        $this->d = intdiv($d, $a);
    }

    public function add(self $v): self
    {
        return new self(($this->n * $v->d) + ($v->n * $this->d), $this->d * $v->d);
    }

    public function sub(self $v): self
    {
        return $this->add($v->neg());
    }

    public function mul(self $v): self
    {
        return new self($this->n * $v->n, $this->d * $v->d);
    }

    public function div(self $v): self
    {
        return new self($this->n * $v->d, $this->d * $v->n);
    }

    public function scale(int $v): self
    {
        return new self($this->n * $v, $this->d);
    }

    public function neg(): self
    {
        return new self(-$this->n, $this->d);
    }

    public function magnitude(): self
    {
        return new self(abs($this->n), $this->d);
    }

    public function cmp(self $v): int
    {
        return ($this->n * $v->d) <=> ($v->n * $this->d);
    }

    public function floorValue(): int
    {
        $q = intdiv($this->n, $this->d);
        return $this->n < 0 && ($this->n % $this->d) !== 0 ? $q - 1 : $q;
    }

    public function ceilValue(): int
    {
        return -$this->neg()->floorValue();
    }

    public function __toString(): string
    {
        return $this->d === 1 ? (string) $this->n : $this->n . '/' . $this->d;
    }

    public function approximate(): string
    {
        $t = intdiv((2 * abs($this->n) * 1000000) + $this->d, 2 * $this->d);
        return (
            ($this->n < 0 && $t > 0 ? '-' : '')
            . intdiv($t, 1000000)
            . '.'
            . str_pad((string) ($t % 1000000), 6, '0', STR_PAD_LEFT)
        );
    }
}

function readNumber(string $text, bool $signed = false): ?Rational
{
    if (!preg_match(
        $signed ? '/^-?[0-9]+(?:\.[0-9]+|\/[0-9]+)?$/D' : '/^[0-9]+(?:\.[0-9]+|\/[0-9]+)?$/D',
        $text,
    ))
        return null;
    if (str_contains($text, '/')) {
        [$a, $b] = explode('/', $text);
        return (int) $b === 0 ? null : new Rational((int) $a, (int) $b);
    }
    if (str_contains($text, '.')) {
        [$a, $b] = explode('.', $text);
        $den = 1;
        for ($i = 0; $i < strlen($b); ++$i)
            $den *= 10;
        return new Rational((int) ($a . $b), $den);
    }
    return new Rational((int) $text);
}

function endpoint(?Rational $v, bool $lower): string
{
    return $v === null ? ($lower ? '-inf' : 'inf') : (string) $v;
}
