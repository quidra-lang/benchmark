<?php

class BTB
{
    private array $entries;

    public function __construct(int $size)
    {
        $this->entries = array_fill(0, $size, null);
    }

    public function lookup(int $pc): ?int
    {
        $entry = $this->entries[intdiv($pc, 4) % count($this->entries)];
        return $entry !== null && $entry['pc'] === $pc ? $entry['target'] : null;
    }

    public function insert(int $pc, int $target): void
    {
        $this->entries[intdiv($pc, 4) % count($this->entries)] = compact('pc', 'target');
    }
}

class RAS
{
    private array $stack = [];

    public function __construct(private int $depth) {}

    public function push(int $value): void
    {
        if ($this->depth === 0) return;
        if (count($this->stack) === $this->depth) array_shift($this->stack);
        $this->stack[] = $value;
    }

    public function pop(): ?int
    {
        return $this->stack ? array_pop($this->stack) : null;
    }
}

function updateCounter(int $value, bool $taken): int
{
    return $taken ? min(3, $value + 1) : max(0, $value - 1);
}

class DirectionPredictor
{
    private string $scheme;
    private int $history = 0;
    private int $historyLimit = 1;
    private array $table = [];
    private array $local = [];
    private array $global = [];
    private array $chooser = [];

    public function __construct(array $specification)
    {
        $this->scheme = $specification['scheme'];
        $p = $specification['parameters'];
        if ($this->scheme === 'ONEBIT') $this->table = array_fill(0, $p[0], 0);
        if ($this->scheme === 'TWOBIT' || $this->scheme === 'GSHARE') $this->table = array_fill(0, $p[0], 1);
        if ($this->scheme === 'GSHARE') $this->historyLimit = 1 << $p[1];
        if ($this->scheme === 'TOURNAMENT') {
            $this->local = array_fill(0, $p[0], 1);
            $this->global = array_fill(0, $p[1], 1);
            $this->historyLimit = 1 << $p[2];
            $this->chooser = array_fill(0, $p[3], 1);
        }
    }

    public function predict(int $pc, int $target): array
    {
        if ($this->scheme === 'STATIC_NT') return ['taken' => false];
        if ($this->scheme === 'BTFN') return ['taken' => $target < $pc];
        $word = intdiv($pc, 4);
        if ($this->scheme === 'TOURNAMENT') {
            $localIndex = $word % count($this->local);
            $globalIndex = ($word ^ $this->history) % count($this->global);
            $chooserIndex = $word % count($this->chooser);
            $local = $this->local[$localIndex] >= 2;
            $global = $this->global[$globalIndex] >= 2;
            return ['taken' => $this->chooser[$chooserIndex] >= 2 ? $global : $local,
                'local' => $local, 'global' => $global, 'localIndex' => $localIndex,
                'globalIndex' => $globalIndex, 'chooserIndex' => $chooserIndex];
        }
        $index = ($this->scheme === 'GSHARE' ? ($word ^ $this->history) : $word) % count($this->table);
        return ['taken' => $this->scheme === 'ONEBIT' ? $this->table[$index] === 1 : $this->table[$index] >= 2, 'index' => $index];
    }

    public function update(array $prediction, bool $taken): void
    {
        if ($this->scheme === 'ONEBIT') $this->table[$prediction['index']] = $taken ? 1 : 0;
        elseif ($this->scheme === 'TWOBIT' || $this->scheme === 'GSHARE') {
            $index = $prediction['index'];
            $this->table[$index] = updateCounter($this->table[$index], $taken);
            if ($this->scheme === 'GSHARE') $this->history = (2 * $this->history + ($taken ? 1 : 0)) % $this->historyLimit;
        } elseif ($this->scheme === 'TOURNAMENT') {
            if ($prediction['local'] !== $prediction['global']) {
                $index = $prediction['chooserIndex'];
                $this->chooser[$index] = updateCounter($this->chooser[$index], $prediction['global'] === $taken);
            }
            $local = $prediction['localIndex'];
            $global = $prediction['globalIndex'];
            $this->local[$local] = updateCounter($this->local[$local], $taken);
            $this->global[$global] = updateCounter($this->global[$global], $taken);
            $this->history = (2 * $this->history + ($taken ? 1 : 0)) % $this->historyLimit;
        }
    }
}

function predictorStorage(array $specification): int
{
    $p = $specification['parameters'];
    return match ($specification['scheme']) {
        'ONEBIT' => $p[0],
        'TWOBIT' => 2 * $p[0],
        'GSHARE' => 2 * $p[0] + $p[1],
        'TOURNAMENT' => 2 * ($p[0] + $p[1] + $p[3]) + $p[2],
        default => 0
    };
}
