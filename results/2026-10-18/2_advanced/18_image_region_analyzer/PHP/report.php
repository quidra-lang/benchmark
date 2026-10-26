<?php
declare(strict_types=1);

namespace ImageRegions;

function decimal(int $numerator, int $denominator, int $digits): string
{
    $scale = 1;
    for ($index = 0; $index < $digits; $index++) {
        $scale *= 10;
    }
    $scaled = intdiv(2 * $scale * abs($numerator) + $denominator, 2 * $denominator);
    $sign = $numerator < 0 && $scaled > 0 ? '-' : '';
    return $sign . intdiv($scaled, $scale) . '.' . str_pad((string)($scaled % $scale), $digits, '0', STR_PAD_LEFT);
}

function hullAreaText(int $doubled): string
{
    return intdiv($doubled, 2) . '.' . ($doubled % 2 === 1 ? '5' : '0');
}

function writeFiles(string $directory, array $files): void
{
    if (!is_dir($directory)) {
        mkdir($directory, 0777, true);
    }
    foreach ($files as $name => $lines) {
        file_put_contents($directory . '/' . $name, implode("\n", $lines) . "\n");
    }
}
