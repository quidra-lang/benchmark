<?php

class DecodeError extends Exception
{
    public string $kind;
    public function __construct(string $kind) { parent::__construct($kind); $this->kind = $kind; }
}

class Writer
{
    public array $bytes = [];
    public int $buffer = 0;
    public int $count = 0;
    public int $padding = 0;
    public int $stuffed = 0;

    public function write(int $value, int $length): void
    {
        for ($i = $length - 1; $i >= 0; $i--) {
            $this->buffer = $this->buffer * 2 + intdiv($value, 1 << $i) % 2;
            $this->count++;
            if ($this->count === 8) {
                $this->bytes[] = $this->buffer;
                if ($this->buffer === 255) { $this->bytes[] = 0; $this->stuffed++; }
                $this->buffer = $this->count = 0;
            }
        }
    }

    public function pad(): void { while ($this->count !== 0) { $this->write(1, 1); $this->padding++; } }
    public function marker(int $value): void { $this->bytes[] = 255; $this->bytes[] = $value; }
}

class Reader
{
    public array $bytes;
    public int $position;
    private int $buffer = 0;
    private int $remaining = 0;

    public function __construct(array $bytes, int $position) { $this->bytes = $bytes; $this->position = $position; }
    public function clear(): void { $this->buffer = $this->remaining = 0; }

    public function bit(): int
    {
        if ($this->remaining === 0) {
            $value = $this->bytes[$this->position];
            if ($value === 255) {
                if ($this->bytes[$this->position + 1] !== 0) throw new DecodeError('marker');
                $this->position += 2;
            } else $this->position++;
            $this->buffer = $value;
            $this->remaining = 8;
        }
        $this->remaining--;
        return intdiv($this->buffer, 1 << $this->remaining) % 2;
    }

    public function read(int $length): int
    {
        $value = 0;
        for ($i = 0; $i < $length; $i++) $value = $value * 2 + $this->bit();
        return $value;
    }

    public function resync(): int
    {
        for ($q = $this->position; $q + 1 < count($this->bytes); $q++) {
            $marker = $this->bytes[$q + 1];
            if ($this->bytes[$q] === 255 && (($marker >= 208 && $marker <= 215) || $marker === 217)) return $q;
        }
        return -1;
    }
}
