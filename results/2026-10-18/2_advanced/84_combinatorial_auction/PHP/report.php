<?php

function gcd(int $a, int $b): int
{
    $a = abs($a);
    $b = abs($b);
    while ($b)
        [$a, $b] = [$b, $a % $b];
    return $a;
}

final readonly class Rational
{
    public int $n, $d;

    public function __construct(int $n = 0, int $d = 1)
    {
        if ($d < 0) {
            $n = -$n;
            $d = -$d;
        }
        $g = gcd($n, $d);
        $this->n = intdiv($n, $g);
        $this->d = intdiv($d, $g);
    }

    private static function of(int|self $x): self
    {
        return $x instanceof self ? $x : new self($x);
    }

    public function add(int|self $x): self
    {
        $x = self::of($x);
        $g = gcd($this->d, $x->d);
        return new self(
            ($this->n * intdiv($x->d, $g)) + ($x->n * intdiv($this->d, $g)),
            intdiv($this->d, $g) * $x->d,
        );
    }

    public function sub(int|self $x): self
    {
        $x = self::of($x);
        return $this->add(new self(-$x->n, $x->d));
    }

    public function mul(int|self $x): self
    {
        $x = self::of($x);
        $a = gcd($this->n, $x->d);
        $b = gcd($x->n, $this->d);
        return new self(intdiv($this->n, $a) * intdiv($x->n, $b), intdiv($this->d, $b) * intdiv($x->d, $a));
    }

    public function div(int|self $x): self
    {
        $x = self::of($x);
        return $this->mul(new self($x->d, $x->n));
    }

    public function cmp(int|self $x): int
    {
        $x = self::of($x);
        $g = gcd($this->d, $x->d);
        return ($this->n * intdiv($x->d, $g)) <=> ($x->n * intdiv($this->d, $g));
    }

    public function __toString(): string
    {
        return $this->d === 1 ? (string) $this->n : $this->n . '/' . $this->d;
    }
}

function bundleText(int $mask, array $names): string
{
    $parts = [];
    foreach ($names as $i => $name)
        if ($mask & (1 << $i))
            $parts[] = $name;
    return $parts ? implode('+', $parts) : '-';
}

function numberList(array $numbers): string
{
    sort($numbers, SORT_NUMERIC);
    return $numbers ? implode('+', $numbers) : '-';
}

function lexCompare(array $a, array $b): int
{
    for ($i = 0; $i < min(count($a), count($b)); ++$i)
        if ($a[$i] !== $b[$i])
            return $a[$i] <=> $b[$i];
    return count($a) <=> count($b);
}

function writeReports(array $reports): void
{
    if (!is_dir('output'))
        mkdir('output');
    foreach ($reports as $name => $lines)
        file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
}
