<?php

class ArithmeticModel
{
    public array $contexts = [];
    public int $rescales = 0;

    public function &table(int $context): array
    {
        if (!isset($this->contexts[$context])) {
            $this->contexts[$context] = ['frequencies' => array_fill(0, 257, 1), 'total' => 257];
        }
        return $this->contexts[$context];
    }

    public function update(array &$table, int $symbol): void
    {
        $table['frequencies'][$symbol] += 32;
        $table['total'] += 32;
        if ($table['total'] >= 8192) {
            $table['total'] = 0;
            foreach ($table['frequencies'] as &$frequency) {
                $frequency = intdiv($frequency + 1, 2);
                $table['total'] += $frequency;
            }
            unset($frequency);
            $this->rescales++;
        }
    }
}

function arithEncode(string $data): array
{
    $model = new ArithmeticModel();
    $writer = new BitWriter();
    $low = 0;
    $high = 65535;
    $follow = 0;
    $context = 10;
    $emit = function (int $bit) use ($writer, &$follow): void {
        $writer->write($bit, 1);
        for ($i = 0; $i < $follow; $i++) {
            $writer->write(1 - $bit, 1);
        }
        $follow = 0;
    };
    $size = strlen($data);
    for ($i = 0; $i <= $size; $i++) {
        $symbol = $i === $size ? 256 : ord($data[$i]);
        $table =& $model->table($context);
        $cumulative = 0;
        for ($earlier = 0; $earlier < $symbol; $earlier++) {
            $cumulative += $table['frequencies'][$earlier];
        }
        $range = $high - $low + 1;
        $high = $low + intdiv($range * ($cumulative + $table['frequencies'][$symbol]), $table['total']) - 1;
        $low += intdiv($range * $cumulative, $table['total']);
        while (true) {
            if ($high < 32768) {
                $emit(0);
            } elseif ($low >= 32768) {
                $emit(1);
                $low -= 32768;
                $high -= 32768;
            } elseif ($low >= 16384 && $high < 49152) {
                $follow++;
                $low -= 16384;
                $high -= 16384;
            } else {
                break;
            }
            $low *= 2;
            $high = $high * 2 + 1;
        }
        if ($symbol !== 256) {
            $model->update($table, $symbol);
            $context = $symbol;
        }
        unset($table);
    }
    $follow++;
    $emit($low < 16384 ? 0 : 1);
    $statistics = ['bits' => $writer->length, 'contexts' => count($model->contexts), 'rescales' => $model->rescales];
    return ['payload' => $writer->finish(), 'statistics' => $statistics];
}

function arithDecode(string $payload, int $originalLength, string &$output): void
{
    $model = new ArithmeticModel();
    $reader = new BitReader($payload, true);
    $low = 0;
    $high = 65535;
    $value = $reader->read(16);
    $context = 10;
    while (true) {
        $table =& $model->table($context);
        $range = $high - $low + 1;
        $quotient = intdiv(($value - $low + 1) * $table['total'] - 1, $range);
        $symbol = 0;
        $cumulative = 0;
        while ($cumulative + $table['frequencies'][$symbol] <= $quotient) {
            $cumulative += $table['frequencies'][$symbol++];
        }
        $high = $low + intdiv($range * ($cumulative + $table['frequencies'][$symbol]), $table['total']) - 1;
        $low += intdiv($range * $cumulative, $table['total']);
        while (true) {
            if ($high < 32768) {
            } elseif ($low >= 32768) {
                $low -= 32768;
                $high -= 32768;
                $value -= 32768;
            } elseif ($low >= 16384 && $high < 49152) {
                $low -= 16384;
                $high -= 16384;
                $value -= 16384;
            } else {
                break;
            }
            $low *= 2;
            $high = $high * 2 + 1;
            $value = $value * 2 + $reader->read(1);
        }
        if ($symbol === 256) {
            if (strlen($output) < $originalLength) {
                throw new DecodingError('early_end');
            }
            return;
        }
        if (strlen($output) === $originalLength) {
            throw new DecodingError('overrun');
        }
        $output .= chr($symbol);
        $model->update($table, $symbol);
        $context = $symbol;
        unset($table);
    }
}
