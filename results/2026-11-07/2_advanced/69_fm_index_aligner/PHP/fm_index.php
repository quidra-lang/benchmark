<?php

class FMIndex
{
    public string $text;
    public array $sa;
    public int $interval;
    public string $bwt = '';
    public array $checkpoints = [];
    public array $counts;
    public array $C;
    public array $samples = [];

    public function __construct(string $text, array $sa, int $interval, ?int $sampleInterval = null)
    {
        $this->text = $text;
        $this->sa = $sa;
        $this->interval = $interval;
        $length = strlen($text);
        foreach ($sa as $position) {
            $this->bwt .= $text[$position > 0 ? $position - 1 : $length - 1];
        }
        $counts = array_fill(0, 6, 0);
        for ($i = 0; $i <= $length; $i++) {
            if ($i % $interval === 0) {
                $this->checkpoints[] = $counts;
            }
            if ($i < $length) {
                $counts[strpos(SYMBOLS, $this->bwt[$i])]++;
            }
        }
        $this->counts = $counts;
        $this->C = array_fill(0, 6, 0);
        for ($i = 1; $i < 6; $i++) {
            $this->C[$i] = $this->C[$i - 1] + $counts[$i - 1];
        }
        if ($sampleInterval !== null) {
            foreach ($sa as $row => $position) {
                if ($position % $sampleInterval === 0) {
                    $this->samples[$row] = $position;
                }
            }
        }
    }

    public function occ(string $symbol, int $position): int
    {
        $checkpoint = intdiv($position, $this->interval);
        $index = strpos(SYMBOLS, $symbol);
        $count = $this->checkpoints[$checkpoint][$index];
        for ($i = $checkpoint * $this->interval; $i < $position; $i++) {
            if ($this->bwt[$i] === $symbol) {
                $count++;
            }
        }
        return $count;
    }

    public function lf(int $row): int
    {
        $symbol = $this->bwt[$row];
        return $this->C[strpos(SYMBOLS, $symbol)] + $this->occ($symbol, $row);
    }

    public function extend(int $lo, int $hi, string $base): array
    {
        if ($base === 'N') {
            return [0, 0];
        }
        $start = $this->C[strpos(SYMBOLS, $base)];
        return [$start + $this->occ($base, $lo), $start + $this->occ($base, $hi)];
    }

    public function backward(string $sequence): array
    {
        $lo = 0;
        $hi = strlen($this->text);
        for ($i = strlen($sequence) - 1; $i >= 0; $i--) {
            [$lo, $hi] = $this->extend($lo, $hi, $sequence[$i]);
            if ($lo >= $hi) {
                break;
            }
        }
        return [$lo, $hi];
    }

    public function locate(int $row): object
    {
        $steps = 0;
        while (!isset($this->samples[$row])) {
            $row = $this->lf($row);
            $steps++;
        }
        return (object) ['position' => $this->samples[$row] + $steps, 'steps' => $steps];
    }

    public function inverse(): string
    {
        $length = strlen($this->text);
        $result = str_repeat("\0", $length);
        $result[$length - 1] = '$';
        $row = 0;
        for ($i = $length - 2; $i >= 0; $i--) {
            $result[$i] = $this->bwt[$row];
            $row = $this->lf($row);
        }
        return $result;
    }
}
