<?php

class DecodingError extends Exception
{
    public string $kind;

    public function __construct(string $kind)
    {
        parent::__construct($kind);
        $this->kind = $kind;
    }
}

function bits(int $value): int
{
    $width = 0;
    while ($value > 0) {
        $width++;
        $value >>= 1;
    }
    return $width;
}

class BitWriter
{
    public int $length = 0;
    private string $bytes = '';
    private int $current = 0;
    private int $used = 0;

    public function write(int $value, int $width): void
    {
        for ($shift = $width - 1; $shift >= 0; $shift--) {
            $this->current = ($this->current << 1) | (($value >> $shift) & 1);
            $this->used++;
            $this->length++;
            if ($this->used === 8) {
                $this->bytes .= chr($this->current);
                $this->current = 0;
                $this->used = 0;
            }
        }
    }

    public function finish(): string
    {
        if ($this->used > 0) {
            $this->bytes .= chr($this->current << (8 - $this->used));
            $this->current = 0;
            $this->used = 0;
        }
        return $this->bytes;
    }
}

class BitReader
{
    private string $data;
    private int $position = 0;
    private bool $zeroFill;

    public function __construct(string $data, bool $zeroFill = false)
    {
        $this->data = $data;
        $this->zeroFill = $zeroFill;
    }

    public function read(int $width): int
    {
        $total = strlen($this->data) * 8;
        if (!$this->zeroFill && $this->position + $width > $total) {
            throw new DecodingError('end_of_data');
        }
        $value = 0;
        for ($i = 0; $i < $width; $i++) {
            $byte = $this->position < $total ? ord($this->data[intdiv($this->position, 8)]) : 0;
            $value = ($value << 1) | (($byte >> (7 - $this->position % 8)) & 1);
            $this->position++;
        }
        return $value;
    }
}
