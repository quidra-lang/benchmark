<?php

declare(strict_types=1);

const PATTERNS = [
    'NEW' => 'iiii', 'OUTPUT' => '', 'INVERT' => '', 'BRIGHTNESS' => 'i',
    'CONTRAST' => 'ii', 'THRESHOLD' => 'i', 'LEVELS' => 'ii',
    'POSTERIZE' => 'i', 'MAXVAL' => 'i', 'FLIPH' => '', 'FLIPV' => '',
    'ROTATE' => 'i', 'CROP' => 'iiii', 'PAD' => 'ii', 'SCALE' => 'ii',
    'SHIFT' => 'iii', 'TILE' => 'ii', 'BLUR' => '', 'GAUSS' => '',
    'SHARPEN' => '', 'CONVOLVE' => 'iiiiiiiiii', 'SOBEL' => '',
    'MEDIAN' => '', 'ERODE' => '', 'DILATE' => '', 'OPEN' => '',
    'CLOSE' => '', 'GRADIENT' => '', 'LINE' => 'iiiii', 'RECT' => 'iiiii',
    'CIRCLE' => 'iiii', 'FLOOD' => 'iii', 'HISTOGRAM' => '',
    'EQUALIZE' => '', 'LABEL' => 'i', 'DISTANCE' => 'i', 'STATS' => '',
    'REGION' => 'iiii', 'DITHER' => '', 'ASCIIART' => '',
    'STORE' => 'n', 'RECALL' => 'n', 'DROP' => 'n', 'BLEND' => 'nii',
    'DIFF' => 'n', 'PASTE' => 'nii', 'SLOTS' => '', 'INFO' => '',
    'UNDO' => '', 'REDO' => '',
];
const IMAGELESS = ['NEW', 'RECALL', 'DROP', 'SLOTS', 'INFO', 'UNDO', 'REDO'];
const NEED_SLOT = ['RECALL', 'DROP', 'BLEND', 'DIFF', 'PASTE'];
const SHADES = '@#*+=~-:,.';
const KERNELS = [
    'BLUR' => [[1, 1, 1, 1, 1, 1, 1, 1, 1], 9],
    'GAUSS' => [[1, 2, 1, 2, 4, 2, 1, 2, 1], 16],
    'SHARPEN' => [[0, -1, 0, -1, 5, -1, 0, -1, 0], 1],
];
const NEIGHBORS4 = [[0, -1], [-1, 0], [1, 0], [0, 1]];

final class CommandError extends RuntimeException {}

function requireValue(bool $condition, string $reason = 'bad value'): void
{
    if (!$condition) {
        throw new CommandError($reason);
    }
}

function clamp(int $value, int $low, int $high): int
{
    return max($low, min($high, $value));
}

function floorDiv(int $value, int $denominator): int
{
    $quotient = intdiv($value, $denominator);
    return $value < 0 && $value % $denominator !== 0 ? $quotient - 1 : $quotient;
}

final class GrayImage
{
    public function __construct(
        public int $width,
        public int $height,
        public int $maxval,
        public array $pixels,
    ) {}

    public function get(int $x, int $y): int
    {
        return $this->pixels[$y * $this->width + $x];
    }

    public function contains(int $x, int $y): bool
    {
        return $x >= 0 && $y >= 0 && $x < $this->width && $y < $this->height;
    }

    public function row(int $y): array
    {
        return array_slice($this->pixels, $y * $this->width, $this->width);
    }

    public function withPixels(array $pixels): self
    {
        return new self($this->width, $this->height, $this->maxval, $pixels);
    }

    public function limit(int $value): int
    {
        return clamp($value, 0, $this->maxval);
    }

    public function neighborhood(int $x, int $y): array
    {
        $result = [];
        for ($dy = -1; $dy <= 1; ++$dy) {
            for ($dx = -1; $dx <= 1; ++$dx) {
                $result[] = $this->get(
                    clamp($x + $dx, 0, $this->width - 1),
                    clamp($y + $dy, 0, $this->height - 1)
                );
            }
        }
        return $result;
    }

    public function summary(): string
    {
        $checksum = 0;
        foreach ($this->pixels as $index => $value) {
            $checksum += ($index + 1) * $value;
        }
        return "{$this->width}x{$this->height} maxval {$this->maxval} checksum $checksum";
    }
}

function readPGM(array $lines): GrayImage
{
    $words = [];
    foreach ($lines as $line) {
        $text = trim(explode('#', $line, 2)[0]);
        if ($text !== '') {
            array_push($words, ...preg_split('/\s+/', $text));
        }
    }
    requireValue($words && $words[0] === 'P2', 'bad magic');
    $header = static function (int $position, int $limit, string $error) use ($words): int {
        requireValue(isset($words[$position]), 'truncated header');
        requireValue((bool) preg_match('/^[0-9]+$/D', $words[$position]), 'bad number');
        $value = (int) $words[$position];
        requireValue($value >= 1 && $value <= $limit, $error);
        return $value;
    };
    $width = $header(1, 64, 'bad size');
    $height = $header(2, 64, 'bad size');
    $maxval = $header(3, 255, 'bad maxval');
    $values = array_slice($words, 4);
    $needed = $width * $height;
    $pixels = [];
    for ($i = 0; $i < $needed; ++$i) {
        $x = $i % $width;
        $y = intdiv($i, $width);
        requireValue(isset($values[$i]), 'too few pixels (' . count($values) . " of $needed)");
        requireValue((bool) preg_match('/^[0-9]+$/D', $values[$i]), "bad pixel at $x,$y");
        $pixel = (int) $values[$i];
        requireValue($pixel <= $maxval, "pixel out of range at $x,$y");
        $pixels[] = $pixel;
    }
    requireValue(count($values) === $needed, 'too many pixels (' . count($values) . " of $needed)");
    return new GrayImage($width, $height, $maxval, $pixels);
}

function transform(GrayImage $image, int $width, int $height, callable $valueAt): GrayImage
{
    $pixels = [];
    for ($y = 0; $y < $height; ++$y) {
        for ($x = 0; $x < $width; ++$x) {
            $pixels[] = $valueAt($x, $y);
        }
    }
    return new GrayImage($width, $height, $image->maxval, $pixels);
}

function convolve(GrayImage $image, array $kernel, int $divisor): GrayImage
{
    return transform($image, $image->width, $image->height,
        static function (int $x, int $y) use ($image, $kernel, $divisor): int {
            $near = $image->neighborhood($x, $y);
            $sum = 0;
            foreach ($kernel as $index => $coefficient) {
                $sum += $coefficient * $near[$index];
            }
            return $image->limit(floorDiv($sum, $divisor));
        }
    );
}

function rankFilter(GrayImage $image, int $rank): GrayImage
{
    return transform($image, $image->width, $image->height,
        static function (int $x, int $y) use ($image, $rank): int {
            $near = $image->neighborhood($x, $y);
            sort($near, SORT_NUMERIC);
            return $near[$rank];
        }
    );
}

function sobel(GrayImage $image): GrayImage
{
    return transform($image, $image->width, $image->height,
        static function (int $x, int $y) use ($image): int {
            $q = $image->neighborhood($x, $y);
            $gx = $q[2] + 2 * $q[5] + $q[8] - $q[0] - 2 * $q[3] - $q[6];
            $gy = $q[6] + 2 * $q[7] + $q[8] - $q[0] - 2 * $q[1] - $q[2];
            return $image->limit(abs($gx) + abs($gy));
        }
    );
}

function linePoints(int $x, int $y, int $toX, int $toY): array
{
    $dx = abs($toX - $x);
    $dy = -abs($toY - $y);
    $sx = $x < $toX ? 1 : -1;
    $sy = $y < $toY ? 1 : -1;
    $error = $dx + $dy;
    $points = [];
    while (true) {
        $points[] = [$x, $y];
        if ($x === $toX && $y === $toY) {
            break;
        }
        $twice = 2 * $error;
        if ($twice >= $dy) {
            $error += $dy;
            $x += $sx;
        }
        if ($twice <= $dx) {
            $error += $dx;
            $y += $sy;
        }
    }
    return $points;
}

function rectanglePoints(GrayImage $image, int $x, int $y, int $width, int $height, bool $fill): array
{
    $right = $x + $width - 1;
    $bottom = $y + $height - 1;
    $points = [];
    for ($j = max($y, 0); $j <= min($bottom, $image->height - 1); ++$j) {
        for ($i = max($x, 0); $i <= min($right, $image->width - 1); ++$i) {
            if ($fill || $i === $x || $i === $right || $j === $y || $j === $bottom) {
                $points[] = [$i, $j];
            }
        }
    }
    return $points;
}

function circlePoints(int $cx, int $cy, int $radius): array
{
    $a = $radius;
    $b = 0;
    $error = 1 - $radius;
    $points = [];
    while ($a >= $b) {
        $points[] = [$cx + $a, $cy + $b];
        $points[] = [$cx + $b, $cy + $a];
        $points[] = [$cx - $b, $cy + $a];
        $points[] = [$cx - $a, $cy + $b];
        $points[] = [$cx - $a, $cy - $b];
        $points[] = [$cx - $b, $cy - $a];
        $points[] = [$cx + $b, $cy - $a];
        $points[] = [$cx + $a, $cy - $b];
        ++$b;
        if ($error < 0) {
            $error += 2 * $b + 1;
        } else {
            --$a;
            $error += 2 * ($b - $a) + 1;
        }
    }
    return $points;
}

function filledCircle(GrayImage $image, array $outline): array
{
    $rows = [];
    foreach ($outline as [$x, $y]) {
        if (isset($rows[$y])) {
            $rows[$y][0] = min($rows[$y][0], $x);
            $rows[$y][1] = max($rows[$y][1], $x);
        } else {
            $rows[$y] = [$x, $x];
        }
    }
    $points = [];
    foreach ($rows as $y => [$lo, $hi]) {
        if ($y < 0 || $y >= $image->height) {
            continue;
        }
        for ($x = max(0, $lo); $x <= min($hi, $image->width - 1); ++$x) {
            $points[] = [$x, $y];
        }
    }
    return $points;
}

function floodPoints(GrayImage $image, int $x, int $y): array
{
    $target = $image->get($x, $y);
    $stack = [[$x, $y]];
    $visited = [$y * $image->width + $x => true];
    $points = [];
    while ($stack) {
        [$cx, $cy] = array_pop($stack);
        $points[] = [$cx, $cy];
        foreach (NEIGHBORS4 as [$dx, $dy]) {
            $nx = $cx + $dx;
            $ny = $cy + $dy;
            if (!$image->contains($nx, $ny) || $image->get($nx, $ny) !== $target) {
                continue;
            }
            $index = $ny * $image->width + $nx;
            if (!isset($visited[$index])) {
                $visited[$index] = true;
                $stack[] = [$nx, $ny];
            }
        }
    }
    return $points;
}

function equalize(GrayImage $image): GrayImage
{
    $counts = array_fill(0, $image->maxval + 1, 0);
    foreach ($image->pixels as $pixel) {
        ++$counts[$pixel];
    }
    $cdf = [];
    $total = 0;
    foreach ($counts as $count) {
        $total += $count;
        $cdf[] = $total;
    }
    $minimum = $cdf[min($image->pixels)];
    $size = count($image->pixels);
    if ($minimum === $size) {
        return $image->withPixels($image->pixels);
    }
    $span = $size - $minimum;
    return $image->withPixels(array_map(
        static fn(int $p): int => intdiv(2 * ($cdf[$p] - $minimum) * $image->maxval + $span, 2 * $span),
        $image->pixels
    ));
}

function components(GrayImage $image, int $threshold): array
{
    $visited = array_fill(0, count($image->pixels), false);
    $groups = [];
    foreach ($image->pixels as $start => $value) {
        if ($visited[$start] || $value < $threshold) {
            continue;
        }
        $visited[$start] = true;
        $stack = [[$start % $image->width, intdiv($start, $image->width)]];
        $group = [];
        while ($stack) {
            [$x, $y] = array_pop($stack);
            $group[] = [$x, $y];
            for ($dy = -1; $dy <= 1; ++$dy) {
                for ($dx = -1; $dx <= 1; ++$dx) {
                    if ($dx === 0 && $dy === 0) {
                        continue;
                    }
                    $nx = $x + $dx;
                    $ny = $y + $dy;
                    if (!$image->contains($nx, $ny)) {
                        continue;
                    }
                    $index = $ny * $image->width + $nx;
                    if (!$visited[$index] && $image->pixels[$index] >= $threshold) {
                        $visited[$index] = true;
                        $stack[] = [$nx, $ny];
                    }
                }
            }
        }
        $groups[] = $group;
    }
    return $groups;
}

function componentText(GrayImage $image, int $threshold, array $group): string
{
    $minX = $image->width;
    $minY = $image->height;
    $maxX = -1;
    $maxY = -1;
    $sumX = 0;
    $sumY = 0;
    $perimeter = 0;
    foreach ($group as [$x, $y]) {
        $minX = min($minX, $x);
        $minY = min($minY, $y);
        $maxX = max($maxX, $x);
        $maxY = max($maxY, $y);
        $sumX += $x;
        $sumY += $y;
        foreach (NEIGHBORS4 as [$dx, $dy]) {
            if (!$image->contains($x + $dx, $y + $dy) ||
                $image->get($x + $dx, $y + $dy) < $threshold) {
                ++$perimeter;
                break;
            }
        }
    }
    $area = count($group);
    return "area $area perimeter $perimeter box $minX $minY $maxX $maxY center " .
        intdiv($sumX, $area) . ' ' . intdiv($sumY, $area);
}

function distanceMap(GrayImage $image, int $threshold): GrayImage
{
    $w = $image->width;
    $h = $image->height;
    $far = $w + $h;
    $distances = [];
    $hasBackground = false;
    foreach ($image->pixels as $pixel) {
        if ($pixel < $threshold) {
            $hasBackground = true;
            $distances[] = 0;
        } else {
            $distances[] = $far;
        }
    }
    if (!$hasBackground) {
        return $image->withPixels(array_fill(0, $w * $h, $image->maxval));
    }
    for ($y = 0; $y < $h; ++$y) {
        for ($x = 0; $x < $w; ++$x) {
            $i = $y * $w + $x;
            if ($x > 0) $distances[$i] = min($distances[$i], $distances[$i - 1] + 1);
            if ($y > 0) $distances[$i] = min($distances[$i], $distances[$i - $w] + 1);
        }
    }
    for ($y = $h - 1; $y >= 0; --$y) {
        for ($x = $w - 1; $x >= 0; --$x) {
            $i = $y * $w + $x;
            if ($x < $w - 1) $distances[$i] = min($distances[$i], $distances[$i + 1] + 1);
            if ($y < $h - 1) $distances[$i] = min($distances[$i], $distances[$i + $w] + 1);
        }
    }
    return $image->withPixels(array_map(static fn(int $n): int => min($n, $image->maxval), $distances));
}

function statistics(array $pixels, int $maxval): string
{
    $sorted = $pixels;
    sort($sorted, SORT_NUMERIC);
    $counts = array_fill(0, $maxval + 1, 0);
    foreach ($pixels as $pixel) ++$counts[$pixel];
    $mode = 0;
    for ($i = 1; $i <= $maxval; ++$i) {
        if ($counts[$i] > $counts[$mode]) $mode = $i;
    }
    $size = count($pixels);
    return 'min ' . $sorted[0] . ' max ' . $sorted[$size - 1] .
        ' mean ' . intdiv(array_sum($pixels), $size) .
        ' median ' . $sorted[intdiv($size - 1, 2)] . " mode $mode";
}

function dither(GrayImage $image): GrayImage
{
    $errors = $image->pixels;
    $pixels = array_fill(0, count($errors), 0);
    $diffusion = [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]];
    for ($y = 0; $y < $image->height; ++$y) {
        for ($x = 0; $x < $image->width; ++$x) {
            $index = $y * $image->width + $x;
            $old = $errors[$index];
            $new = 2 * $old >= $image->maxval ? $image->maxval : 0;
            $pixels[$index] = $new;
            $difference = $old - $new;
            foreach ($diffusion as [$dx, $dy, $weight]) {
                if ($image->contains($x + $dx, $y + $dy)) {
                    $neighbor = ($y + $dy) * $image->width + $x + $dx;
                    $errors[$neighbor] += floorDiv($difference * $weight, 16);
                }
            }
        }
    }
    return $image->withPixels($pixels);
}

final class ImageEditor
{
    private ?GrayImage $current = null;
    private array $undo = [];
    private array $redo = [];
    private array $slots = [];
    public array $output = [];

    private function emit(string $line): void
    {
        $this->output[] = $line;
    }

    private function parse(array $words): array
    {
        $name = array_shift($words);
        requireValue(array_key_exists($name, PATTERNS), "unknown command $name");
        $pattern = PATTERNS[$name];
        $fill = in_array($name, ['RECT', 'CIRCLE'], true) &&
            count($words) === strlen($pattern) + 1 && end($words) === 'FILL';
        if ($fill) array_pop($words);
        requireValue(count($words) === strlen($pattern), 'bad arguments');
        $values = [];
        $slot = null;
        foreach (str_split($pattern) as $i => $kind) {
            if ($kind === 'i') {
                requireValue((bool) preg_match('/^(?:0|-?[1-9][0-9]{0,6})$/D', $words[$i]), 'bad arguments');
                $values[] = (int) $words[$i];
            } else {
                requireValue((bool) preg_match('/^[a-z]{1,8}$/D', $words[$i]), 'bad arguments');
                $slot = $words[$i];
            }
        }
        return [$name, $values, $slot, $fill];
    }

    public function execute(array $words): void
    {
        try {
            [$name, $args, $slot, $fill] = $this->parse($words);
            if (!in_array($name, IMAGELESS, true)) {
                requireValue($this->current !== null, 'no image');
            }
            if (in_array($name, NEED_SLOT, true)) {
                requireValue(isset($this->slots[$slot]), "no slot $slot");
            }
            $this->run($name, $args, $slot, $fill);
        } catch (CommandError $error) {
            $this->emit('error: ' . $error->getMessage());
        }
    }

    public function load(array $lines): void
    {
        try {
            $this->replace(readPGM($lines), 'loaded');
        } catch (CommandError $error) {
            $this->emit('error: load: ' . $error->getMessage());
        }
    }

    private function replace(GrayImage $image, string $label): void
    {
        $this->current = $image;
        $this->undo = [];
        $this->redo = [];
        $this->emit("$label " . $image->summary());
    }

    private function commit(GrayImage $image, ?int $painted = null): void
    {
        $this->undo[] = $this->current;
        $this->redo = [];
        $this->current = $image;
        $this->emit('ok ' . $image->summary() .
            ($painted === null ? '' : " painted $painted"));
    }

    private function paint(array $points, int $value): void
    {
        $image = $this->current;
        $marked = [];
        foreach ($points as [$x, $y]) {
            if ($image->contains($x, $y)) $marked[$y * $image->width + $x] = true;
        }
        $pixels = $image->pixels;
        foreach ($marked as $index => $_) $pixels[$index] = $value;
        $this->commit($image->withPixels($pixels), count($marked));
    }

    private function cropArea(array $a): array
    {
        [$x, $y, $w, $h] = $a;
        requireValue($x >= 0 && $y >= 0 && $w >= 1 && $h >= 1);
        requireValue($x + $w <= $this->current->width && $y + $h <= $this->current->height);
        return $a;
    }

    private function matchingSlot(string $name): GrayImage
    {
        $other = $this->slots[$name];
        $image = $this->current;
        requireValue($other->width === $image->width && $other->height === $image->height, 'size mismatch');
        requireValue($other->maxval === $image->maxval, 'maxval mismatch');
        return $other;
    }

    private function run(string $name, array $a, ?string $slot, bool $fill): void
    {
        $image = $this->current;
        $w = $image?->width;
        $h = $image?->height;
        $m = $image?->maxval;
        switch ($name) {
            case 'NEW':
                [$width, $height, $maxval, $value] = $a;
                requireValue($width >= 1 && $width <= 64 && $height >= 1 && $height <= 64);
                requireValue($maxval >= 1 && $maxval <= 255 && $value >= 0 && $value <= $maxval);
                $this->replace(new GrayImage($width, $height, $maxval,
                    array_fill(0, $width * $height, $value)), 'created');
                break;
            case 'OUTPUT':
                $this->emit('P2');
                $this->emit("$w $h");
                $this->emit((string) $m);
                for ($y = 0; $y < $h; ++$y) $this->emit(implode(' ', $image->row($y)));
                break;
            case 'INVERT':
                $this->commit($image->withPixels(array_map(static fn(int $p): int => $m - $p, $image->pixels)));
                break;
            case 'BRIGHTNESS':
                requireValue($a[0] >= -255 && $a[0] <= 255);
                $this->commit($image->withPixels(array_map(
                    static fn(int $p): int => $image->limit($p + $a[0]), $image->pixels
                )));
                break;
            case 'CONTRAST':
                [$num, $den] = $a;
                requireValue($num >= 0 && $num <= 100 && $den >= 1 && $den <= 100);
                $center = intdiv($m + 1, 2);
                $this->commit($image->withPixels(array_map(
                    static fn(int $p): int => $image->limit($center + floorDiv(($p - $center) * $num, $den)),
                    $image->pixels
                )));
                break;
            case 'THRESHOLD':
                requireValue($a[0] >= 0 && $a[0] <= $m);
                $this->commit($image->withPixels(array_map(
                    static fn(int $p): int => $p >= $a[0] ? $m : 0, $image->pixels
                )));
                break;
            case 'LEVELS':
                [$lo, $hi] = $a;
                requireValue(0 <= $lo && $lo < $hi && $hi <= $m);
                $this->commit($image->withPixels(array_map(
                    static fn(int $p): int => $image->limit(floorDiv(($p - $lo) * $m, $hi - $lo)),
                    $image->pixels
                )));
                break;
            case 'POSTERIZE':
                $levels = $a[0];
                requireValue($levels >= 2 && $levels <= $m + 1);
                $this->commit($image->withPixels(array_map(
                    static fn(int $p): int => intdiv(intdiv($p * $levels, $m + 1) * $m, $levels - 1),
                    $image->pixels
                )));
                break;
            case 'MAXVAL':
                $newMax = $a[0];
                requireValue($newMax >= 1 && $newMax <= 255);
                $pixels = array_map(static fn(int $p): int => intdiv(2 * $p * $newMax + $m, 2 * $m),
                    $image->pixels);
                $this->commit(new GrayImage($w, $h, $newMax, $pixels));
                break;
            case 'FLIPH':
                $this->commit(transform($image, $w, $h,
                    static fn(int $x, int $y): int => $image->get($w - $x - 1, $y)));
                break;
            case 'FLIPV':
                $this->commit(transform($image, $w, $h,
                    static fn(int $x, int $y): int => $image->get($x, $h - $y - 1)));
                break;
            case 'ROTATE':
                $angle = $a[0];
                requireValue(in_array($angle, [90, 180, 270], true));
                if ($angle === 90) {
                    $result = transform($image, $h, $w,
                        static fn(int $x, int $y): int => $image->get($y, $h - 1 - $x));
                } elseif ($angle === 180) {
                    $result = transform($image, $w, $h,
                        static fn(int $x, int $y): int => $image->get($w - 1 - $x, $h - 1 - $y));
                } else {
                    $result = transform($image, $h, $w,
                        static fn(int $x, int $y): int => $image->get($w - 1 - $y, $x));
                }
                $this->commit($result);
                break;
            case 'CROP':
                [$x, $y, $width, $height] = $this->cropArea($a);
                $this->commit(transform($image, $width, $height,
                    static fn(int $i, int $j): int => $image->get($x + $i, $y + $j)));
                break;
            case 'PAD':
                [$n, $value] = $a;
                requireValue($n >= 1 && $value >= 0 && $value <= $m);
                requireValue($w + 2 * $n <= 64 && $h + 2 * $n <= 64, 'too large');
                $this->commit(transform($image, $w + 2 * $n, $h + 2 * $n,
                    static fn(int $x, int $y): int =>
                        $image->contains($x - $n, $y - $n) ? $image->get($x - $n, $y - $n) : $value));
                break;
            case 'SCALE':
                [$num, $den] = $a;
                requireValue($num >= 1 && $num <= 16 && $den >= 1 && $den <= 16);
                $width = intdiv($w * $num, $den);
                $height = intdiv($h * $num, $den);
                requireValue($width >= 1 && $height >= 1, 'too small');
                requireValue($width <= 64 && $height <= 64, 'too large');
                $this->commit(transform($image, $width, $height,
                    static fn(int $x, int $y): int =>
                        $image->get(intdiv((2 * $x + 1) * $den, 2 * $num),
                                    intdiv((2 * $y + 1) * $den, 2 * $num))));
                break;
            case 'SHIFT':
                [$dx, $dy, $value] = $a;
                requireValue($dx >= -1000 && $dx <= 1000 && $dy >= -1000 && $dy <= 1000);
                requireValue($value >= 0 && $value <= $m);
                $this->commit(transform($image, $w, $h,
                    static fn(int $x, int $y): int =>
                        $image->contains($x - $dx, $y - $dy) ?
                            $image->get($x - $dx, $y - $dy) : $value));
                break;
            case 'TILE':
                [$nx, $ny] = $a;
                requireValue($nx >= 1 && $ny >= 1);
                requireValue($w * $nx <= 64 && $h * $ny <= 64, 'too large');
                $this->commit(transform($image, $w * $nx, $h * $ny,
                    static fn(int $x, int $y): int => $image->get($x % $w, $y % $h)));
                break;
            case 'BLUR':
            case 'GAUSS':
            case 'SHARPEN':
                [$kernel, $divisor] = KERNELS[$name];
                $this->commit(convolve($image, $kernel, $divisor));
                break;
            case 'CONVOLVE':
                requireValue(!array_filter(array_slice($a, 0, 9), static fn(int $n): bool => $n < -16 || $n > 16)
                    && $a[9] >= 1 && $a[9] <= 256);
                $this->commit(convolve($image, array_slice($a, 0, 9), $a[9]));
                break;
            case 'SOBEL':
                $this->commit(sobel($image));
                break;
            case 'MEDIAN':
                $this->commit(rankFilter($image, 4));
                break;
            case 'ERODE':
                $this->commit(rankFilter($image, 0));
                break;
            case 'DILATE':
                $this->commit(rankFilter($image, 8));
                break;
            case 'OPEN':
                $this->commit(rankFilter(rankFilter($image, 0), 8));
                break;
            case 'CLOSE':
                $this->commit(rankFilter(rankFilter($image, 8), 0));
                break;
            case 'GRADIENT':
                $lower = rankFilter($image, 0)->pixels;
                $upper = rankFilter($image, 8)->pixels;
                $pixels = array_map(static fn(int $hi, int $lo): int => $hi - $lo, $upper, $lower);
                $this->commit($image->withPixels($pixels));
                break;
            case 'LINE':
                [$x0, $y0, $x1, $y1, $value] = $a;
                requireValue(!array_filter(array_slice($a, 0, 4),
                    static fn(int $n): bool => $n < -1000 || $n > 1000) && $value >= 0 && $value <= $m);
                $this->paint(linePoints($x0, $y0, $x1, $y1), $value);
                break;
            case 'RECT':
                [$x, $y, $width, $height, $value] = $a;
                requireValue($x >= -1000 && $x <= 1000 && $y >= -1000 && $y <= 1000);
                requireValue($width >= 1 && $width <= 1000 && $height >= 1 && $height <= 1000);
                requireValue($value >= 0 && $value <= $m);
                $this->paint(rectanglePoints($image, $x, $y, $width, $height, $fill), $value);
                break;
            case 'CIRCLE':
                [$cx, $cy, $radius, $value] = $a;
                requireValue($cx >= -1000 && $cx <= 1000 && $cy >= -1000 && $cy <= 1000);
                requireValue($radius >= 0 && $radius <= 1000 && $value >= 0 && $value <= $m);
                $points = circlePoints($cx, $cy, $radius);
                $this->paint($fill ? filledCircle($image, $points) : $points, $value);
                break;
            case 'FLOOD':
                [$x, $y, $value] = $a;
                requireValue($image->contains($x, $y) && $value >= 0 && $value <= $m);
                $this->paint(floodPoints($image, $x, $y), $value);
                break;
            case 'HISTOGRAM':
                $lower = array_fill(0, 16, null);
                $upper = array_fill(0, 16, 0);
                $counts = array_fill(0, 16, 0);
                for ($value = 0; $value <= $m; ++$value) {
                    $bin = intdiv($value * 16, $m + 1);
                    if ($lower[$bin] === null) $lower[$bin] = $value;
                    $upper[$bin] = $value;
                }
                foreach ($image->pixels as $pixel) ++$counts[intdiv($pixel * 16, $m + 1)];
                $top = max($counts);
                for ($bin = 0; $bin < 16; ++$bin) {
                    if ($lower[$bin] === null) continue;
                    $this->emit(sprintf('%3d-%3d %4d |%s', $lower[$bin], $upper[$bin],
                        $counts[$bin], str_repeat('#', intdiv($counts[$bin] * 32, $top))));
                }
                break;
            case 'EQUALIZE':
                $this->commit(equalize($image));
                break;
            case 'LABEL':
                requireValue($a[0] >= 0 && $a[0] <= $m);
                $groups = components($image, $a[0]);
                $this->emit('labels ' . count($groups));
                foreach ($groups as $i => $group) {
                    $this->emit('label ' . ($i + 1) . ' ' . componentText($image, $a[0], $group));
                }
                break;
            case 'DISTANCE':
                requireValue($a[0] >= 0 && $a[0] <= $m);
                $this->commit(distanceMap($image, $a[0]));
                break;
            case 'STATS':
                $this->emit(statistics($image->pixels, $m));
                break;
            case 'REGION':
                [$x, $y, $width, $height] = $this->cropArea($a);
                $region = transform($image, $width, $height,
                    static fn(int $i, int $j): int => $image->get($x + $i, $y + $j));
                $this->emit(statistics($region->pixels, $m));
                break;
            case 'DITHER':
                $this->commit(dither($image));
                break;
            case 'ASCIIART':
                for ($y = 0; $y < $h; ++$y) {
                    $this->emit(implode('', array_map(
                        static fn(int $p): string => SHADES[intdiv($p * 10, $m + 1)], $image->row($y))));
                }
                break;
            case 'STORE':
                $this->slots[$slot] = $image;
                $this->emit("stored $slot " . $image->summary());
                break;
            case 'RECALL':
                $this->replace($this->slots[$slot], "recalled $slot");
                break;
            case 'DROP':
                unset($this->slots[$slot]);
                $this->emit("dropped $slot");
                break;
            case 'BLEND':
                [$num, $den] = $a;
                requireValue($num >= 0 && $den >= 1 && $den <= 100 && $num <= $den);
                $other = $this->matchingSlot($slot);
                $pixels = array_map(static fn(int $p, int $q): int =>
                    intdiv($p * ($den - $num) + $q * $num, $den), $image->pixels, $other->pixels);
                $this->commit($image->withPixels($pixels));
                break;
            case 'DIFF':
                $other = $this->matchingSlot($slot);
                $pixels = array_map(static fn(int $p, int $q): int => abs($p - $q),
                    $image->pixels, $other->pixels);
                $this->commit($image->withPixels($pixels));
                break;
            case 'PASTE':
                [$x, $y] = $a;
                requireValue($x >= -1000 && $x <= 1000 && $y >= -1000 && $y <= 1000);
                $other = $this->slots[$slot];
                requireValue($other->maxval === $m, 'maxval mismatch');
                $pixels = $image->pixels;
                $painted = 0;
                for ($j = 0; $j < $other->height; ++$j) {
                    for ($i = 0; $i < $other->width; ++$i) {
                        if ($image->contains($x + $i, $y + $j)) {
                            $pixels[($y + $j) * $w + $x + $i] = $other->get($i, $j);
                            ++$painted;
                        }
                    }
                }
                $this->commit($image->withPixels($pixels), $painted);
                break;
            case 'SLOTS':
                if (!$this->slots) $this->emit('no slots');
                $sorted = $this->slots;
                ksort($sorted, SORT_STRING);
                foreach ($sorted as $key => $stored) $this->emit("$key " . $stored->summary());
                break;
            case 'INFO':
                $summary = $image === null ? 'none' : $image->summary();
                $this->emit("image $summary undo " . count($this->undo) .
                    ' redo ' . count($this->redo) . ' slots ' . count($this->slots));
                break;
            case 'UNDO':
                requireValue((bool) $this->undo, 'nothing to undo');
                $this->redo[] = $image;
                $this->current = array_pop($this->undo);
                $this->emit('undo ' . $this->current->summary());
                break;
            case 'REDO':
                requireValue((bool) $this->redo, 'nothing to redo');
                $this->undo[] = $image;
                $this->current = array_pop($this->redo);
                $this->emit('redo ' . $this->current->summary());
                break;
        }
    }
}

$lines = preg_split('/\n/', str_replace("\r", '', stream_get_contents(STDIN)));
$commands = (int) array_shift($lines);
$editor = new ImageEditor();
for ($i = 0; $i < $commands; ++$i) {
    $words = explode(' ', array_shift($lines));
    if ($words[0] === 'LOAD') {
        $editor->load(array_splice($lines, 0, (int) $words[1]));
    } else {
        $editor->execute($words);
    }
}
echo implode("\n", $editor->output), "\n";
