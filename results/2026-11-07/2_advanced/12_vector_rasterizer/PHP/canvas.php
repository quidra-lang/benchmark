<?php
declare(strict_types=1);

function floorRatio(int $n, int $d): int { $q = intdiv($n, $d); return $q - ($n < 0 && $n % $d !== 0 ? 1 : 0); }
function roundRatio(int $n, int $d): int { if ($d < 0) { $n = -$n; $d = -$d; } return floorRatio(2 * $n + $d, 2 * $d); }
function effectiveAlpha(int $alpha, int $opacity): int { return roundRatio($alpha * $opacity, 255); }

final class Layer {
    public array $colors, $lines;
    public function __construct(public int $width, public int $height, public int $opacity, public string $mode) {
        $this->colors = array_fill(0, $height, array_fill(0, $width, null)); $this->lines = array_fill(0, $height, array_fill(0, $width, 0));
    }
    public function paint(int $x, int $y, array $color, int $line): void { $this->colors[$y][$x] = $color; $this->lines[$y][$x] = $line; }
    public function erase(int $x, int $y): bool { $painted = $this->colors[$y][$x] !== null; $this->colors[$y][$x] = null; return $painted; }
    public function alphaAt(int $x, int $y): int { $color = $this->colors[$y][$x]; return $color === null ? 0 : effectiveAlpha($color[3], $this->opacity); }
    public function blend(int $x, int $y, array $current): array {
        $color = $this->colors[$y][$x]; if ($color === null) return $current; $alpha = effectiveAlpha($color[3], $this->opacity);
        for ($i = 0; $i < 3; $i++) { $s = $color[$i]; $v = $current[$i]; $source = match ($this->mode) { 'multiply' => roundRatio($s * $v, 255), 'screen' => 255 - roundRatio((255 - $s) * (255 - $v), 255), default => $s }; $current[$i] = roundRatio($alpha * $source + (255 - $alpha) * $v, 255); } return $current;
    }
}
function composite(array $layers, array $background, int $width, int $height): array {
    $image = []; for ($y = 0; $y < $height; $y++) { $row = []; for ($x = 0; $x < $width; $x++) { $color = array_slice($background, 0, 3); foreach ($layers as $layer) $color = $layer->blend($x, $y, $color); $row[] = $color; } $image[] = $row; } return $image;
}
