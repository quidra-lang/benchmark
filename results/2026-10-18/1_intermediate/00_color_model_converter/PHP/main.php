<?php
const BUILTIN_NAMES = [
    'black', 'maroon', 'green', 'olive', 'navy', 'purple', 'teal', 'silver',
    'gray', 'red', 'lime', 'yellow', 'blue', 'magenta', 'cyan', 'white',
    'orange', 'pink', 'brown', 'gold', 'coral', 'salmon', 'violet', 'indigo'
];
const BUILTIN_HEX = [
    '000000', '800000', '008000', '808000', '000080', '800080', '008080', 'C0C0C0',
    '808080', 'FF0000', '00FF00', 'FFFF00', '0000FF', 'FF00FF', '00FFFF', 'FFFFFF',
    'FFA500', 'FFC0CB', 'A52A2A', 'FFD700', 'FF7F50', 'FA8072', 'EE82EE', '4B0082'
];
const SIGNATURES = [
    'PARSE' => 'c',
    'DEFINE' => 'name c',
    'UNDEFINE' => 'name',
    'LIST' => '',
    'HSL' => 'c',
    'HSV' => 'c',
    'HWB' => 'c',
    'CMYK' => 'c',
    'YCBCR' => 'c',
    'YIQ' => 'c',
    'FROMHSL' => '0:359 0:100 0:100',
    'FROMHSV' => '0:359 0:100 0:100',
    'FROMHWB' => '0:359 0:100 0:100',
    'FROMCMYK' => '0:100 0:100 0:100 0:100',
    'FROMYCBCR' => '0:255 0:255 0:255',
    'FROMYIQ' => '0:255 -255:255 -255:255',
    'RGB565' => 'c',
    'FROM565' => 'code',
    'ANSI' => 'c',
    'FROMANSI' => '0:255',
    'WEBSAFE' => 'c',
    'GRAY' => 'c gray',
    'INVERT' => 'c',
    'MIX' => 'c c 0:100',
    'MIXHSL' => 'c c 0:100',
    'GRADIENT' => 'c c 2:16',
    'TINTS' => 'c 1:10',
    'SHADES' => 'c 1:10',
    'TONES' => 'c 1:10',
    'BLEND' => 'blend c c',
    'ALPHA' => 'c 0:100 c 0:100',
    'SIMULATE' => 'c simulation',
    'ROTATE' => 'c -720:720',
    'COMPLEMENT' => 'c',
    'TRIADIC' => 'c',
    'TETRADIC' => 'c',
    'SPLITCOMP' => 'c',
    'ANALOGOUS' => 'c 1:6 1:60',
    'LIGHTEN' => 'c 0:100',
    'DARKEN' => 'c 0:100',
    'SATURATE' => 'c 0:100',
    'DESATURATE' => 'c 0:100',
    'NEAREST' => 'c',
    'DISTANCE' => 'c c',
    'CONTRAST' => 'c c',
    'ACCESSIBLE' => 'c c',
    'DESCRIBE' => 'c',
    'RANDOM' => '1:999999999 1:16',
];
const KEYWORDS = [
    'gray' => ['LUMA', 'AVERAGE', 'LIGHTNESS', 'HSP'],
    'blend' => [
        'MULTIPLY', 'SCREEN', 'OVERLAY', 'HARDLIGHT', 'SOFTLIGHT', 'DARKEN',
        'LIGHTEN', 'DIFFERENCE', 'EXCLUSION', 'ADD', 'SUBTRACT', 'COLORDODGE',
        'COLORBURN', 'HUE', 'SATURATION', 'COLOR', 'LUMINOSITY'
    ],
    'simulation' => ['PROTANOPIA', 'DEUTERANOPIA', 'TRITANOPIA', 'ACHROMATOPSIA']
];
$builtinColors = [];
foreach (BUILTIN_HEX as $text) {
    $builtinColors[] = [hexdec(substr($text, 0, 2)), hexdec(substr($text, 2, 2)), hexdec(substr($text, 4, 2))];
}

function require_valid(bool $condition): void
{
    if (!$condition) {
        throw new InvalidArgumentException('INVALID');
    }
}

function floor_div(int $n, int $d): int
{
    $quotient = intdiv($n, $d);
    if ($n < 0 && $n % $d !== 0) {
        --$quotient;
    }
    return $quotient;
}

function round_ratio(int $n, int $d): int
{
    return floor_div(2 * $n + $d, 2 * $d);
}

function away_ratio(int $n, int $d): int
{
    return $n < 0 ? -round_ratio(-$n, $d) : round_ratio($n, $d);
}

function positive_mod(int $n, int $d): int
{
    return ($n % $d + $d) % $d;
}

function byte_clamp(int $value): int
{
    return min(255, max(0, $value));
}

function hex_color(array $color): string
{
    return sprintf('#%02X%02X%02X', ...$color);
}

function color_sequence(array $colors): string
{
    return implode(' ', array_map('hex_color', $colors));
}

function color_distance(array $a, array $b): int
{
    $total = 0;
    for ($i = 0; $i < 3; ++$i) {
        $difference = $a[$i] - $b[$i];
        $total += $difference * $difference;
    }
    return $total;
}

function integer_arg(string $text, int $low, int $high): int
{
    require_valid(preg_match('/^-?[0-9]{1,9}$/D', $text) === 1);
    $value = (int) $text;
    require_valid($value >= $low && $value <= $high);
    return $value;
}

function parse_color(string $text, array $registry): array
{
    global $builtinColors;
    if (preg_match('/^#[0-9a-fA-F]{6}$/D', $text) === 1) {
        return [hexdec(substr($text, 1, 2)), hexdec(substr($text, 3, 2)), hexdec(substr($text, 5, 2))];
    }
    if (preg_match('/^#[0-9a-fA-F]{3}$/D', $text) === 1) {
        return [17 * hexdec($text[1]), 17 * hexdec($text[2]), 17 * hexdec($text[3])];
    }
    if (preg_match('/^rgb\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\)$/D', $text, $matches) === 1) {
        $color = [(int) $matches[1], (int) $matches[2], (int) $matches[3]];
        require_valid(max($color) <= 255);
        return $color;
    }
    $index = array_search($text, BUILTIN_NAMES, true);
    if ($index !== false) {
        return $builtinColors[$index];
    }
    require_valid(array_key_exists($text, $registry['colors']));
    return $registry['colors'][$text];
}

function typed_arg(string $text, string $kind, array $registry): mixed
{
    if ($kind === 'c') {
        return parse_color($text, $registry);
    }
    if ($kind === 'name') {
        require_valid(preg_match('/^[a-z]{1,12}$/D', $text) === 1);
        return $text;
    }
    if ($kind === 'code') {
        require_valid(preg_match('/^0x[0-9a-fA-F]{4}$/D', $text) === 1);
        return hexdec(substr($text, 2));
    }
    if (array_key_exists($kind, KEYWORDS)) {
        require_valid(in_array($text, KEYWORDS[$kind], true));
        return $text;
    }
    [$low, $high] = array_map('intval', explode(':', $kind));
    return integer_arg($text, $low, $high);
}

function hue(array $color): int
{
    [$r, $g, $b] = $color;
    $high = max($color);
    $delta = $high - min($color);
    if ($delta === 0) {
        return 0;
    }
    if ($high === $r) {
        $numerator = 60 * ($g - $b);
        if ($numerator < 0) {
            $numerator += 360 * $delta;
        }
    } elseif ($high === $g) {
        $numerator = 60 * ($b - $r) + 120 * $delta;
    } else {
        $numerator = 60 * ($r - $g) + 240 * $delta;
    }
    return round_ratio($numerator, $delta) % 360;
}

function hsl(array $color): array
{
    $high = max($color);
    $low = min($color);
    $delta = $high - $low;
    $saturation = $delta === 0 ? 0 : round_ratio(100 * $delta, 255 - abs($high + $low - 255));
    return [hue($color), $saturation, round_ratio(100 * ($high + $low), 510)];
}

function base60(int $h): array
{
    $sector = intdiv($h, 60);
    $fraction = $h % 60;
    $x = $sector % 2 === 0 ? $fraction : 60 - $fraction;
    return [[60, $x, 0], [$x, 60, 0], [0, 60, $x], [0, $x, 60], [$x, 0, 60], [60, 0, $x]][$sector];
}

function from_hsl(int $h, int $s, int $l): array
{
    $chroma = (100 - abs(2 * $l - 100)) * $s;
    $offset = 6000 * $l - 30 * $chroma;
    return array_map(fn($u) => round_ratio(255 * ($u * $chroma + $offset), 600000), base60($h));
}

function model_values(string $model, array $color): array
{
    [$r, $g, $b] = $color;
    $high = max($color);
    $low = min($color);
    if ($model === 'HSL') {
        return hsl($color);
    }
    if ($model === 'HSV') {
        $saturation = $high === 0 ? 0 : round_ratio(100 * ($high - $low), $high);
        return [hue($color), $saturation, round_ratio(100 * $high, 255)];
    }
    if ($model === 'HWB') {
        return [hue($color), round_ratio(100 * $low, 255), round_ratio(100 * (255 - $high), 255)];
    }
    if ($model === 'CMYK') {
        if ($high === 0) {
            return [0, 0, 0, 100];
        }
        return [
            round_ratio(100 * ($high - $r), $high),
            round_ratio(100 * ($high - $g), $high),
            round_ratio(100 * ($high - $b), $high),
            round_ratio(100 * (255 - $high), 255)
        ];
    }
    if ($model === 'YCBCR') {
        return [
            byte_clamp(round_ratio(299 * $r + 587 * $g + 114 * $b, 1000)),
            byte_clamp(round_ratio(128000 - 169 * $r - 331 * $g + 500 * $b, 1000)),
            byte_clamp(round_ratio(128000 + 500 * $r - 419 * $g - 81 * $b, 1000))
        ];
    }
    return [
        round_ratio(299 * $r + 587 * $g + 114 * $b, 1000),
        round_ratio(596 * $r - 274 * $g - 322 * $b, 1000),
        round_ratio(211 * $r - 523 * $g + 312 * $b, 1000)
    ];
}

function model_text(string $model, array $color): string
{
    $values = model_values($model, $color);
    if (in_array($model, ['HSL', 'HSV', 'HWB'], true)) {
        return sprintf('%s(%d,%d%%,%d%%)', strtolower($model), ...$values);
    }
    if ($model === 'CMYK') {
        return sprintf('cmyk(%d%%,%d%%,%d%%,%d%%)', ...$values);
    }
    return sprintf('%s(%d,%d,%d)', strtolower($model), ...$values);
}

function ansi_color(int $number): array
{
    global $builtinColors;
    if ($number < 16) {
        return $builtinColors[$number];
    }
    if ($number >= 232) {
        return array_fill(0, 3, 8 + 10 * ($number - 232));
    }
    $value = $number - 16;
    $levels = [0, 95, 135, 175, 215, 255];
    return [$levels[intdiv($value, 36)], $levels[intdiv($value, 6) % 6], $levels[$value % 6]];
}

function root_ratio(int $n, int $d): int
{
    $low = 0;
    $high = 1;
    while ($d * $high * $high <= $n) {
        $high *= 2;
    }
    while ($high - $low > 1) {
        $middle = intdiv($low + $high, 2);
        if ($d * $middle * $middle <= $n) {
            $low = $middle;
        } else {
            $high = $middle;
        }
    }
    return $low;
}

function nearest_index(array $color, array $colors): int
{
    $selected = 0;
    for ($i = 1; $i < count($colors); ++$i) {
        if (color_distance($color, $colors[$i]) < color_distance($color, $colors[$selected])) {
            $selected = $i;
        }
    }
    return $selected;
}

function contrast(array $a, array $b): array
{
    $luminance = fn($c) => 2126 * $c[0] * $c[0] + 7152 * $c[1] * $c[1] + 722 * $c[2] * $c[2];
    $y1 = $luminance($a);
    $y2 = $luminance($b);
    $high = max($y1, $y2) + 32512500;
    $low = min($y1, $y2) + 32512500;
    if ($high >= 7 * $low) {
        $verdict = 'AAA';
    } elseif (2 * $high >= 9 * $low) {
        $verdict = 'AA';
    } else {
        $verdict = 'FAIL';
    }
    return [round_ratio(100 * $high, $low), $verdict];
}

function contrast_text(array $a, array $b): string
{
    [$ratio, $verdict] = contrast($a, $b);
    return sprintf('%d.%02d %s', intdiv($ratio, 100), $ratio % 100, $verdict);
}

function gradient(array $a, array $b, int $n): array
{
    $output = [];
    for ($i = 0; $i < $n; ++$i) {
        $color = [];
        for ($j = 0; $j < 3; ++$j) {
            $color[] = $a[$j] + away_ratio(($b[$j] - $a[$j]) * $i, $n - 1);
        }
        $output[] = $color;
    }
    return $output;
}

function mean_color(array $colors): array
{
    $total = [0, 0, 0];
    foreach ($colors as $color) {
        for ($j = 0; $j < 3; ++$j) {
            $total[$j] += $color[$j];
        }
    }
    return array_map(fn($value) => round_ratio($value, count($colors)), $total);
}

function widths(array $colors): array
{
    $low = $colors[0];
    $high = $colors[0];
    foreach ($colors as $color) {
        for ($j = 0; $j < 3; ++$j) {
            $low[$j] = min($low[$j], $color[$j]);
            $high[$j] = max($high[$j], $color[$j]);
        }
    }
    return [$high[0] - $low[0], $high[1] - $low[1], $high[2] - $low[2]];
}

function palette(array $colors, int $k): array
{
    $boxes = [$colors];
    while (count($boxes) < $k) {
        $selected = 0;
        $bestWidth = -1;
        foreach ($boxes as $i => $box) {
            if (count($box) >= 2) {
                $width = max(widths($box));
                if ($width > $bestWidth) {
                    $selected = $i;
                    $bestWidth = $width;
                }
            }
        }
        $box = $boxes[$selected];
        $ranges = widths($box);
        $axis = array_search(max($ranges), $ranges, true);
        $indexed = [];
        foreach ($box as $i => $color) {
            $indexed[] = ['color' => $color, 'index' => $i];
        }
        usort($indexed, function($a, $b) use ($axis) {
            $comparison = $a['color'][$axis] <=> $b['color'][$axis];
            return $comparison !== 0 ? $comparison : $a['index'] <=> $b['index'];
        });
        $ordered = array_column($indexed, 'color');
        $middle = intdiv(count($box), 2);
        array_splice($boxes, $selected, 1, [array_slice($ordered, 0, $middle), array_slice($ordered, $middle)]);
    }
    return $boxes;
}

function blend_component(string $mode, int $x, int $y): int
{
    $multiply = intdiv($x * $y, 255);
    $screen = 255 - intdiv((255 - $x) * (255 - $y), 255);
    if ($mode === 'MULTIPLY') {
        return $multiply;
    }
    if ($mode === 'SCREEN') {
        return $screen;
    }
    if ($mode === 'OVERLAY' || $mode === 'HARDLIGHT') {
        $lower = $mode === 'OVERLAY' ? $x < 128 : $y < 128;
        if ($lower) {
            return intdiv(2 * $x * $y, 255);
        }
        return 255 - intdiv(2 * (255 - $x) * (255 - $y), 255);
    }
    if ($mode === 'SOFTLIGHT') {
        return intdiv((255 - $x) * $multiply + $x * $screen, 255);
    }
    if ($mode === 'DARKEN') {
        return min($x, $y);
    }
    if ($mode === 'LIGHTEN') {
        return max($x, $y);
    }
    if ($mode === 'DIFFERENCE') {
        return abs($x - $y);
    }
    if ($mode === 'EXCLUSION') {
        return $x + $y - intdiv(2 * $x * $y, 255);
    }
    if ($mode === 'ADD') {
        return min(255, $x + $y);
    }
    if ($mode === 'SUBTRACT') {
        return max(0, $x - $y);
    }
    if ($mode === 'COLORDODGE') {
        return $y === 255 ? 255 : min(255, intdiv(255 * $x, 255 - $y));
    }
    return $y === 0 ? 0 : max(0, 255 - intdiv(255 * (255 - $x), $y));
}

function execute(string $command, array $raw, array &$registry): string
{
    global $builtinColors;
    if ($command === 'PALETTE' || $command === 'KMEANS') {
        require_valid(count($raw) >= 2 && count($raw) <= 33);
        $k = integer_arg($raw[0], 1, count($raw) - 1);
        $colors = array_map(fn($token) => parse_color($token, $registry), array_slice($raw, 1));
        $args = [$k, $colors];
    } elseif (in_array($command, ['BEST', 'SORT', 'DITHER'], true)) {
        $minimum = $command === 'BEST' ? 2 : 1;
        $maximum = $command === 'BEST' ? 33 : 32;
        require_valid(count($raw) >= $minimum && count($raw) <= $maximum);
        $args = [array_map(fn($token) => parse_color($token, $registry), $raw)];
    } else {
        require_valid(array_key_exists($command, SIGNATURES));
        $kinds = SIGNATURES[$command] === '' ? [] : explode(' ', SIGNATURES[$command]);
        require_valid(count($raw) === count($kinds));
        $args = [];
        foreach ($raw as $i => $token) {
            $args[] = typed_arg($token, $kinds[$i], $registry);
        }
    }
    if ($command === 'DEFINE') {
        [$name, $color] = $args;
        require_valid(!in_array($name, BUILTIN_NAMES, true));
        if (!array_key_exists($name, $registry['colors'])) {
            $registry['order'][] = $name;
        }
        $registry['colors'][$name] = $color;
        return $name . ' ' . hex_color($color);
    }
    if ($command === 'UNDEFINE') {
        $name = $args[0];
        require_valid(array_key_exists($name, $registry['colors']));
        unset($registry['colors'][$name]);
        $registry['order'] = array_values(array_filter($registry['order'], fn($other) => $other !== $name));
        return $name . ' removed';
    }
    if ($command === 'LIST') {
        if ($registry['colors'] === []) {
            return 'NONE';
        }
        $names = array_keys($registry['colors']);
        sort($names, SORT_STRING);
        return implode(' ', array_map(fn($name) => $name . '=' . hex_color($registry['colors'][$name]), $names));
    }
    if ($command === 'PARSE' || $command === 'NEAREST') {
        $color = $args[0];
        $names = BUILTIN_NAMES;
        $colors = $builtinColors;
        foreach ($registry['order'] as $name) {
            $names[] = $name;
            $colors[] = $registry['colors'][$name];
        }
        if ($command === 'NEAREST') {
            $i = nearest_index($color, $colors);
            return sprintf('%s %s %d', $names[$i], hex_color($colors[$i]), color_distance($color, $colors[$i]));
        }
        $exact = '-';
        foreach ($colors as $i => $other) {
            if ($other === $color) {
                $exact = $names[$i];
                break;
            }
        }
        $parts = [hex_color($color), sprintf('rgb(%d,%d,%d)', ...$color)];
        foreach (['HSL', 'HSV', 'HWB', 'CMYK', 'YCBCR', 'YIQ'] as $model) {
            $parts[] = model_text($model, $color);
        }
        $parts[] = $exact;
        return implode(' ', $parts);
    }
    if (in_array($command, ['HSL', 'HSV', 'HWB', 'CMYK', 'YCBCR', 'YIQ'], true)) {
        return model_text($command, $args[0]);
    }
    if ($command === 'FROMHSL') {
        $result = from_hsl(...$args);
    } elseif ($command === 'FROMHSV') {
        [$h, $s, $v] = $args;
        $chroma = $v * $s;
        $result = array_map(fn($u) => round_ratio(255 * ($u * $chroma + 6000 * $v - 60 * $chroma), 600000), base60($h));
    } elseif ($command === 'FROMHWB') {
        [$h, $w, $k] = $args;
        if ($w + $k >= 100) {
            $result = array_fill(0, 3, round_ratio(255 * $w, $w + $k));
        } else {
            $result = array_map(fn($u) => round_ratio(255 * ($u * (100 - $w - $k) + 60 * $w), 6000), base60($h));
        }
    } elseif ($command === 'FROMCMYK') {
        $result = [];
        for ($i = 0; $i < 3; ++$i) {
            $result[] = round_ratio(255 * (100 - $args[$i]) * (100 - $args[3]), 10000);
        }
    } elseif ($command === 'FROMYCBCR') {
        [$y, $cb, $cr] = $args;
        $result = [
            byte_clamp(round_ratio(1000 * $y + 1402 * ($cr - 128), 1000)),
            byte_clamp(round_ratio(1000 * $y - 344 * ($cb - 128) - 714 * ($cr - 128), 1000)),
            byte_clamp(round_ratio(1000 * $y + 1772 * ($cb - 128), 1000))
        ];
    } elseif ($command === 'FROMYIQ') {
        [$y, $i, $q] = $args;
        $result = [
            byte_clamp(round_ratio(1000 * $y + 956 * $i + 619 * $q, 1000)),
            byte_clamp(round_ratio(1000 * $y - 272 * $i - 647 * $q, 1000)),
            byte_clamp(round_ratio(1000 * $y - 1106 * $i + 1703 * $q, 1000))
        ];
    } elseif ($command === 'RGB565') {
        [$r, $g, $b] = $args[0];
        $value = 2048 * round_ratio(31 * $r, 255) + 32 * round_ratio(63 * $g, 255) + round_ratio(31 * $b, 255);
        return sprintf('0x%04X', $value);
    } elseif ($command === 'FROM565') {
        $value = $args[0];
        $result = [round_ratio(255 * intdiv($value, 2048), 31), round_ratio(255 * (intdiv($value, 32) % 64), 63), round_ratio(255 * ($value % 32), 31)];
    } elseif ($command === 'ANSI') {
        $colors = array_map('ansi_color', range(16, 255));
        $i = nearest_index($args[0], $colors);
        return sprintf('%d %s %d', $i + 16, hex_color($colors[$i]), color_distance($args[0], $colors[$i]));
    } elseif ($command === 'FROMANSI') {
        $result = ansi_color($args[0]);
    } elseif ($command === 'WEBSAFE') {
        $result = array_map(fn($x) => 51 * round_ratio($x, 51), $args[0]);
    } elseif ($command === 'GRAY') {
        [$color, $method] = $args;
        [$r, $g, $b] = $color;
        if ($method === 'LUMA') {
            $value = round_ratio(299 * $r + 587 * $g + 114 * $b, 1000);
        } elseif ($method === 'AVERAGE') {
            $value = round_ratio($r + $g + $b, 3);
        } elseif ($method === 'LIGHTNESS') {
            $value = round_ratio(max($color) + min($color), 2);
        } else {
            $value = root_ratio(299 * $r * $r + 587 * $g * $g + 114 * $b * $b, 1000);
        }
        $result = array_fill(0, 3, $value);
    } elseif ($command === 'INVERT') {
        $result = array_map(fn($x) => 255 - $x, $args[0]);
    } elseif ($command === 'MIX') {
        [$a, $b, $p] = $args;
        $result = [];
        for ($i = 0; $i < 3; ++$i) {
            $result[] = round_ratio($a[$i] * (100 - $p) + $b[$i] * $p, 100);
        }
    } elseif ($command === 'MIXHSL') {
        [$a, $b, $p] = $args;
        [$h1, $s1, $l1] = hsl($a);
        [$h2, $s2, $l2] = hsl($b);
        $delta = positive_mod($h2 - $h1, 360);
        if ($delta > 180) {
            $delta -= 360;
        }
        $result = from_hsl(positive_mod($h1 + away_ratio($delta * $p, 100), 360),
            $s1 + away_ratio(($s2 - $s1) * $p, 100), $l1 + away_ratio(($l2 - $l1) * $p, 100));
    } elseif ($command === 'GRADIENT') {
        return color_sequence(gradient(...$args));
    } elseif (in_array($command, ['TINTS', 'SHADES', 'TONES'], true)) {
        $value = ['TINTS' => 255, 'SHADES' => 0, 'TONES' => 128][$command];
        return color_sequence(array_slice(gradient($args[0], array_fill(0, 3, $value), $args[1] + 2), 1, $args[1]));
    } elseif ($command === 'BLEND') {
        [$mode, $a, $b] = $args;
        if (in_array($mode, ['HUE', 'SATURATION', 'COLOR', 'LUMINOSITY'], true)) {
            [$h1, $s1, $l1] = hsl($a);
            [$h2, $s2, $l2] = hsl($b);
            if ($mode === 'HUE') {
                $result = from_hsl($h2, $s1, $l1);
            } elseif ($mode === 'SATURATION') {
                $result = from_hsl($h1, $s2, $l1);
            } elseif ($mode === 'COLOR') {
                $result = from_hsl($h2, $s2, $l1);
            } else {
                $result = from_hsl($h1, $s1, $l2);
            }
        } else {
            $result = [];
            for ($i = 0; $i < 3; ++$i) {
                $result[] = blend_component($mode, $a[$i], $b[$i]);
            }
        }
    } elseif ($command === 'ALPHA') {
        [$a, $p, $b, $q] = $args;
        $opacity = 100 * $p + $q * (100 - $p);
        $result = [0, 0, 0];
        if ($opacity > 0) {
            for ($i = 0; $i < 3; ++$i) {
                $result[$i] = round_ratio(100 * $p * $a[$i] + $q * (100 - $p) * $b[$i], $opacity);
            }
        }
        return sprintf('%s %d%%', hex_color($result), round_ratio($opacity, 100));
    } elseif ($command === 'SIMULATE') {
        [$color, $kind] = $args;
        $matrices = [
            'PROTANOPIA' => [[567, 433, 0], [558, 442, 0], [0, 242, 758]],
            'DEUTERANOPIA' => [[625, 375, 0], [700, 300, 0], [0, 300, 700]],
            'TRITANOPIA' => [[950, 50, 0], [0, 433, 567], [0, 475, 525]],
            'ACHROMATOPSIA' => [[299, 587, 114], [299, 587, 114], [299, 587, 114]]
        ];
        $result = [];
        foreach ($matrices[$kind] as $row) {
            $result[] = round_ratio($row[0] * $color[0] + $row[1] * $color[1] + $row[2] * $color[2], 1000);
        }
    } elseif (in_array($command, ['ROTATE', 'COMPLEMENT', 'TRIADIC', 'TETRADIC', 'SPLITCOMP', 'ANALOGOUS'], true)) {
        [$h, $s, $l] = hsl($args[0]);
        if ($command === 'ROTATE') {
            $offsets = [$args[1]];
        } elseif ($command === 'ANALOGOUS') {
            $offsets = [];
            for ($i = -$args[1]; $i <= $args[1]; ++$i) {
                if ($i !== 0) {
                    $offsets[] = $i * $args[2];
                }
            }
        } else {
            $offsets = ['COMPLEMENT' => [180], 'TRIADIC' => [120, 240], 'TETRADIC' => [90, 180, 270], 'SPLITCOMP' => [150, 210]][$command];
        }
        return color_sequence(array_map(fn($d) => from_hsl(positive_mod($h + $d, 360), $s, $l), $offsets));
    } elseif (in_array($command, ['LIGHTEN', 'DARKEN', 'SATURATE', 'DESATURATE'], true)) {
        [$h, $s, $l] = hsl($args[0]);
        $p = $args[1];
        if ($command === 'LIGHTEN') {
            $l = min(100, $l + $p);
        } elseif ($command === 'DARKEN') {
            $l = max(0, $l - $p);
        } elseif ($command === 'SATURATE') {
            $s = min(100, $s + $p);
        } else {
            $s = max(0, $s - $p);
        }
        $result = from_hsl($h, $s, $l);
    } elseif ($command === 'DISTANCE') {
        [$a, $b] = $args;
        $dr = $a[0] - $b[0];
        $dg = $a[1] - $b[1];
        $db = $a[2] - $b[2];
        $weighted = (1024 + $a[0] + $b[0]) * $dr * $dr + 2048 * $dg * $dg + (1534 - $a[0] - $b[0]) * $db * $db;
        return sprintf('%d %d', color_distance($a, $b), root_ratio($weighted, 512));
    } elseif ($command === 'CONTRAST') {
        return contrast_text(...$args);
    } elseif ($command === 'ACCESSIBLE') {
        [$result, $bg] = $args;
        if (contrast($result, $bg)[1] === 'FAIL') {
            [$h, $s, $l] = hsl($result);
            $found = false;
            for ($step = 1; $step <= 100; ++$step) {
                foreach ([$l - $step, $l + $step] as $lightness) {
                    if ($lightness >= 0 && $lightness <= 100) {
                        $candidate = from_hsl($h, $s, $lightness);
                        if (contrast($candidate, $bg)[1] !== 'FAIL') {
                            $result = $candidate;
                            $found = true;
                            break;
                        }
                    }
                }
                if ($found) {
                    break;
                }
            }
        }
        return hex_color($result) . ' ' . contrast_text($result, $bg);
    } elseif ($command === 'BEST') {
        $colors = $args[0];
        $bg = $colors[0];
        $selected = 1;
        for ($i = 2; $i < count($colors); ++$i) {
            if (contrast($colors[$i], $bg)[0] > contrast($colors[$selected], $bg)[0]) {
                $selected = $i;
            }
        }
        return hex_color($colors[$selected]) . ' ' . contrast_text($colors[$selected], $bg);
    } elseif ($command === 'DESCRIBE') {
        [$h, $s, $l] = hsl($args[0]);
        if ($l <= 5) {
            return 'black';
        }
        if ($l >= 95) {
            return 'white';
        }
        if ($l <= 20) {
            $lightness = 'very dark';
        } elseif ($l <= 40) {
            $lightness = 'dark';
        } elseif ($l <= 60) {
            $lightness = 'medium';
        } elseif ($l <= 80) {
            $lightness = 'light';
        } else {
            $lightness = 'very light';
        }
        if ($s < 10) {
            return $lightness . ' gray';
        }
        if ($s < 40) {
            $saturation = 'muted';
        } elseif ($s < 80) {
            $saturation = 'moderate';
        } else {
            $saturation = 'vivid';
        }
        $names = explode(' ', 'red orange yellow chartreuse green spring-green cyan azure blue violet magenta rose');
        return $lightness . ' ' . $saturation . ' ' . $names[intdiv(($h + 15) % 360, 30)];
    } elseif ($command === 'PALETTE' || $command === 'KMEANS') {
        [$k, $colors] = $args;
        $boxes = palette($colors, $k);
        $representatives = array_map('mean_color', $boxes);
        $counts = array_map('count', $boxes);
        $iterations = 0;
        if ($command === 'KMEANS') {
            for ($iteration = 1; $iteration <= 20; ++$iteration) {
                $assigned = array_fill(0, $k, []);
                foreach ($colors as $color) {
                    $j = nearest_index($color, $representatives);
                    $assigned[$j][] = $color;
                }
                $updated = [];
                $unchanged = true;
                for ($j = 0; $j < $k; ++$j) {
                    $counts[$j] = count($assigned[$j]);
                    $updated[$j] = $counts[$j] === 0 ? $representatives[$j] : mean_color($assigned[$j]);
                    if ($updated[$j] !== $representatives[$j]) {
                        $unchanged = false;
                    }
                }
                $representatives = $updated;
                $iterations = $iteration;
                if ($unchanged) {
                    break;
                }
            }
        }
        $output = [];
        for ($j = 0; $j < $k; ++$j) {
            $output[] = hex_color($representatives[$j]) . ':' . $counts[$j];
        }
        return ($command === 'KMEANS' ? $iterations . ' ' : '') . implode(' ', $output);
    } elseif ($command === 'SORT') {
        $indexed = [];
        foreach ($args[0] as $i => $color) {
            $indexed[] = ['color' => $color, 'value' => hsl($color), 'index' => $i];
        }
        usort($indexed, function($a, $b) {
            $comparison = $a['value'] <=> $b['value'];
            return $comparison !== 0 ? $comparison : $a['index'] <=> $b['index'];
        });
        return color_sequence(array_column($indexed, 'color'));
    } elseif ($command === 'DITHER') {
        $error = [0, 0, 0];
        $colors = array_slice($builtinColors, 0, 16);
        $output = [];
        foreach ($args[0] as $color) {
            $adjusted = [];
            for ($j = 0; $j < 3; ++$j) {
                $adjusted[$j] = byte_clamp($color[$j] + $error[$j]);
            }
            $selected = nearest_index($adjusted, $colors);
            $output[] = BUILTIN_NAMES[$selected];
            for ($j = 0; $j < 3; ++$j) {
                $error[$j] = $adjusted[$j] - $colors[$selected][$j];
            }
        }
        return implode(' ', $output);
    } elseif ($command === 'RANDOM') {
        [$state, $n] = $args;
        $output = [];
        for ($i = 0; $i < $n; ++$i) {
            $state = (48271 * $state) % 2147483647;
            $u = $state;
            $state = (48271 * $state) % 2147483647;
            $v = $state;
            $state = (48271 * $state) % 2147483647;
            $output[] = from_hsl($u % 360, 40 + $v % 61, 25 + $state % 51);
        }
        return color_sequence($output);
    }
    return hex_color($result);
}

$count = (int) fgets(STDIN);
$registry = ['colors' => [], 'order' => []];
for ($i = 0; $i < $count; ++$i) {
    $parts = explode(' ', rtrim(fgets(STDIN), "\r\n"));
    $command = array_shift($parts);
    try {
        echo execute($command, $parts, $registry), "\n";
    } catch (InvalidArgumentException $exception) {
        echo "INVALID\n";
    }
}
