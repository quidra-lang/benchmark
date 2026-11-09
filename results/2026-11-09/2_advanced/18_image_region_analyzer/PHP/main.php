<?php
declare(strict_types=1);

namespace ImageRegions;

require_once __DIR__ . '/pgm_reader.php';
require_once __DIR__ . '/threshold.php';
require_once __DIR__ . '/morphology.php';
require_once __DIR__ . '/labeling.php';
require_once __DIR__ . '/report.php';

const SYMBOLS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const ORIENTATIONS = ['none', 'horizontal', 'vertical', 'falling', 'rising'];
const DIRECTIONS = [
    4 => [[1, 0], [0, -1], [-1, 0], [0, 1]],
    8 => [[1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1], [1, 1]],
];
const CSV_HEADER = 'image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes';

final class Rational
{
    public int $numerator;
    public int $denominator;

    public function __construct(int $numerator, int $denominator = 1)
    {
        $a = abs($numerator);
        $b = $denominator;
        while ($b !== 0) {
            [$a, $b] = [$b, $a % $b];
        }
        $this->numerator = intdiv($numerator, $a);
        $this->denominator = intdiv($denominator, $a);
    }

    public static function parse(string $text): self
    {
        $parts = explode('/', $text);
        return new self((int)$parts[0], isset($parts[1]) ? (int)$parts[1] : 1);
    }

    public function compare(self $other): int
    {
        return ($this->numerator * $other->denominator) <=> ($other->numerator * $this->denominator);
    }

    public function text(int $digits): string
    {
        return decimal($this->numerator, $this->denominator, $digits);
    }
}

final class Setting
{
    public function __construct(
        public string $name,
        public int $connectivity,
        public string $threshold,
        public string $polarity,
        public array $operations
    ) {}

    public function method(): string
    {
        return in_array($this->threshold, ['otsu', 'isodata'], true) ? $this->threshold : 'fixed';
    }
}

final class Parameters
{
    public int $otsuTop = 0;
    public int $sweepStep = 0;
    public Rational $isotropy;
    public int $bayMin = 0;
    public array $elements = [];
    public array $settings = [];
}

final class Condition
{
    public Rational|string $value;

    public function __construct(public string $feature, public string $comparison, public string $original)
    {
        $this->value = $feature === 'orientation' ? $original : Rational::parse($original);
    }

    public function holds(array $features): bool
    {
        $value = $features[$this->feature];
        if ($this->feature === 'orientation') {
            $order = strcmp($value, $this->value);
        } else {
            if (is_int($value)) {
                $value = new Rational($value);
            }
            $order = $value->compare($this->value);
        }
        return match ($this->comparison) {
            '<' => $order < 0,
            '<=' => $order <= 0,
            '>' => $order > 0,
            '>=' => $order >= 0,
            '=' => $order === 0,
            '!=' => $order !== 0,
        };
    }

    public function words(): string
    {
        return $this->feature . ' ' . $this->comparison . ' ' . $this->original;
    }
}

final class Rule
{
    public function __construct(public string $name, public array $conditions) {}

    public function matches(array $features): bool
    {
        foreach ($this->conditions as $condition) {
            if (!$condition->holds($features)) {
                return false;
            }
        }
        return true;
    }
}

final class Rules
{
    public array $filters = [];
    public array $classes = [];
    public array $flags = [];

    public function classNames(): array
    {
        $names = [];
        $seen = [];
        foreach ($this->classes as $rule) {
            if (!isset($seen['#' . $rule->name])) {
                $seen['#' . $rule->name] = true;
                $names[] = $rule->name;
            }
        }
        $names[] = 'other';
        return $names;
    }
}

final class Hole
{
    public function __construct(public int $number, public array $pixels, public int $owner) {}

    public function box(): array
    {
        $xs = array_column($this->pixels, 0);
        $ys = array_column($this->pixels, 1);
        return [min($xs), min($ys), max($xs), max($ys)];
    }
}

final class Region
{
    public array $features = [];
    public array $codes = [];
    public array $skeleton = [];
    public int $hullDoubled = 0;
    public ?int $parent = null;
    public int $depth = 0;
    public array $children = [];
    public bool $kept = false;
    public ?int $droppedBy = null;
    public string $className = 'other';
    public array $flags = [];
    public ?int $neighbor = null;
    public int $distance = 0;

    public function __construct(public int $number, public array $pixels) {}
}

function readParameters(string $path): Parameters
{
    $parameters = new Parameters();
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
        $words = explode(' ', $line);
        switch ($words[0]) {
            case 'otsu_top':
                $parameters->otsuTop = (int)$words[1];
                break;
            case 'sweep':
                $parameters->sweepStep = (int)$words[1];
                break;
            case 'isotropy':
                $parameters->isotropy = Rational::parse($words[1]);
                break;
            case 'bay_min':
                $parameters->bayMin = (int)$words[1];
                break;
            case 'element':
                $ox = (int)$words[4];
                $oy = (int)$words[5];
                $offsets = [];
                foreach (array_slice($words, 6) as $y => $row) {
                    for ($x = 0; $x < strlen($row); $x++) {
                        if ($row[$x] === '#') {
                            $offsets[] = [$x - $ox, $y - $oy];
                        }
                    }
                }
                $parameters->elements['#' . $words[1]] = $offsets;
                break;
            case 'image':
                $parameters->settings['#' . $words[1]] = new Setting(
                    $words[1], (int)$words[2], $words[3], $words[4], array_slice($words, 5)
                );
                break;
        }
    }
    return $parameters;
}

function readRules(string $path): Rules
{
    $rules = new Rules();
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
        $words = explode(' ', $line);
        if ($words[0] === 'filter') {
            $rules->filters[] = new Condition($words[1], $words[2], $words[3]);
        } else {
            $conditions = [];
            for ($index = 2; $index < count($words); $index += 3) {
                $conditions[] = new Condition($words[$index], $words[$index + 1], $words[$index + 2]);
            }
            $rule = new Rule($words[1], $conditions);
            if ($words[0] === 'class') {
                $rules->classes[] = $rule;
            } elseif ($words[0] === 'flag') {
                $rules->flags[] = $rule;
            }
        }
    }
    return $rules;
}

function countForeground(array $mask): int
{
    $count = 0;
    foreach ($mask as $row) {
        foreach ($row as $flag) {
            if ($flag) {
                $count++;
            }
        }
    }
    return $count;
}

function groupPixels(array $labels, int $count): array
{
    $groups = array_fill(0, $count + 1, []);
    foreach ($labels as $y => $row) {
        foreach ($row as $x => $label) {
            $groups[$label][] = [$x, $y];
        }
    }
    return $groups;
}

function enclosedComponents(array $mask, int $connectivity): array
{
    $height = count($mask);
    $width = count($mask[0]);
    $background = [];
    foreach ($mask as $row) {
        $background[] = array_map(static fn(bool $value): bool => !$value, $row);
    }
    $components = labelComponents($background, $connectivity);
    $enclosed = [];
    foreach (array_slice(groupPixels($components->labels, $components->count), 1) as $pixels) {
        $onEdge = false;
        foreach ($pixels as [$x, $y]) {
            if ($x === 0 || $y === 0 || $x === $width - 1 || $y === $height - 1) {
                $onEdge = true;
                break;
            }
        }
        if (!$onEdge) {
            $enclosed[] = $pixels;
        }
    }
    return $enclosed;
}

function fillHoles(array $mask, int $connectivity): array
{
    foreach (enclosedComponents($mask, $connectivity) as $pixels) {
        foreach ($pixels as [$x, $y]) {
            $mask[$y][$x] = true;
        }
    }
    return $mask;
}

function cross(array $a, array $b, array $point): int
{
    return ($b[0] - $a[0]) * ($point[1] - $a[1]) - ($b[1] - $a[1]) * ($point[0] - $a[0]);
}

function squaredDistance(array $a, array $b): int
{
    $dx = $a[0] - $b[0];
    $dy = $a[1] - $b[1];
    return $dx * $dx + $dy * $dy;
}

function halfHull(array $points): array
{
    $chain = [];
    foreach ($points as $point) {
        while (count($chain) >= 2 && cross($chain[count($chain) - 2], $chain[count($chain) - 1], $point) <= 0) {
            array_pop($chain);
        }
        $chain[] = $point;
    }
    array_pop($chain);
    return $chain;
}

function convexHull(array $pixels): array
{
    $unique = [];
    foreach ($pixels as [$x, $y]) {
        for ($dy = 0; $dy <= 1; $dy++) {
            for ($dx = 0; $dx <= 1; $dx++) {
                $unique[pixelKey($x + $dx, $y + $dy)] = [$x + $dx, $y + $dy];
            }
        }
    }
    $ordered = array_values($unique);
    usort($ordered, static fn(array $a, array $b): int => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));
    return array_merge(halfHull($ordered), halfHull(array_reverse($ordered)));
}

function containsCenter(array $hull, int $x, int $y): bool
{
    $center = [2 * $x + 1, 2 * $y + 1];
    foreach ($hull as $index => $a) {
        $b = $hull[($index + 1) % count($hull)];
        if (cross([2 * $a[0], 2 * $a[1]], [2 * $b[0], 2 * $b[1]], $center) < 0) {
            return false;
        }
    }
    return true;
}

function meanText(int $total, int $count): string
{
    return $count > 0 ? decimal($total, $count, 2) : '-';
}

function orientationLine(array $regions): string
{
    $parts = ['orientations'];
    foreach (ORIENTATIONS as $name) {
        $count = 0;
        foreach ($regions as $region) {
            if ($region->features['orientation'] === $name) {
                $count++;
            }
        }
        array_push($parts, $name, (string)$count);
    }
    return implode(' ', $parts);
}

final class ImageAnalysis
{
    public int $width;
    public int $height;
    public int $connectivity;
    public int $complement;
    public Histogram $histogram;
    public OtsuResult $otsu;
    public int $isodataCutoff;
    public int $isodataIterations;
    public int $cutoff;
    public array $initial;
    public array $final;
    public array $morphCounts = [];
    public array $sweep = [];
    public array $labels;
    public int $provisional;
    public array $regions = [];
    public array $holes = [];
    public array $holeOf;
    public int $fourComponents;
    public int $eightComponents;
    public int $bitQuad;

    public function __construct(public Image $image, public Setting $setting, public Parameters $parameters)
    {
        $this->width = $image->width;
        $this->height = $image->height;
        $this->connectivity = $setting->connectivity;
        $this->complement = 12 - $setting->connectivity;
        $this->histogram = new Histogram($image->maxval, $image->pixels);
        $this->otsu = otsu($this->histogram);
        [$this->isodataCutoff, $this->isodataIterations] = isodata($this->histogram);
        $this->cutoff = match ($setting->threshold) {
            'otsu' => $this->otsu->cutoff,
            'isodata' => $this->isodataCutoff,
            default => (int)$setting->threshold,
        };
        $this->initial = $this->binarize($this->cutoff);
        $this->final = $this->initial;
        foreach ($setting->operations as $operation) {
            if ($operation === 'fill') {
                $this->final = fillHoles($this->final, $this->complement);
            } else {
                [$kind, $name] = explode(':', $operation);
                $offsets = $parameters->elements['#' . $name];
                $this->final = match ($kind) {
                    'erode' => erode($this->final, $offsets),
                    'dilate' => dilate($this->final, $offsets),
                    'open' => opening($this->final, $offsets),
                    'close' => closing($this->final, $offsets),
                };
            }
            $this->morphCounts[] = countForeground($this->final);
        }
        for ($cutoff = $parameters->sweepStep; $cutoff < $image->maxval; $cutoff += $parameters->sweepStep) {
            $mask = $this->binarize($cutoff);
            $this->sweep[] = [$cutoff, countForeground($mask), labelComponents($mask, $this->connectivity)->count];
        }
        $components = labelComponents($this->final, $this->connectivity);
        $this->labels = $components->labels;
        $this->provisional = $components->provisional;
        $groups = groupPixels($this->labels, $components->count);
        for ($number = 1; $number <= $components->count; $number++) {
            $this->regions[] = new Region($number, $groups[$number]);
        }
        $this->fourComponents = labelComponents($this->final, 4)->count;
        $this->eightComponents = labelComponents($this->final, 8)->count;
        $this->bitQuad = bitQuadEuler($this->final, $this->connectivity);
        $this->holeOf = array_fill(0, $this->height, array_fill(0, $this->width, 0));
        foreach (enclosedComponents($this->final, $this->complement) as $pixels) {
            [$x, $y] = $pixels[0];
            $hole = new Hole(count($this->holes) + 1, $pixels, $this->labels[$y - 1][$x]);
            foreach ($pixels as [$x, $y]) {
                $this->holeOf[$y][$x] = $hole->number;
            }
            $this->holes[] = $hole;
        }
        foreach ($this->regions as $region) {
            [$x, $y] = $region->pixels[0];
            if ($y >= 1 && $this->holeOf[$y - 1][$x] > 0) {
                $owner = $this->holes[$this->holeOf[$y - 1][$x] - 1]->owner;
                $region->parent = $owner;
                $parent = $this->regions[$owner - 1];
                $region->depth = $parent->depth + 1;
                $parent->children[] = $region;
            }
        }
        foreach ($this->regions as $region) {
            $this->measure($region);
        }
    }

    private function binarize(int $cutoff): array
    {
        $mask = [];
        foreach ($this->image->pixels as $row) {
            $mask[] = array_map(
                fn(int $value): bool => $this->setting->polarity === 'bright' ? $value > $cutoff : $value <= $cutoff,
                $row
            );
        }
        return $mask;
    }

    private function labelAt(int $x, int $y): int
    {
        return $x >= 0 && $x < $this->width && $y >= 0 && $y < $this->height ? $this->labels[$y][$x] : -1;
    }

    private function chainCode(Region $region): array
    {
        $moves = DIRECTIONS[$this->connectivity];
        $visited = [$region->pixels[0]];
        $codes = [];
        $heading = count($moves) - 1;
        while (true) {
            [$x, $y] = $visited[count($visited) - 1];
            $start = $this->connectivity === 4 ? ($heading + 3) % 4 : ($heading + ($heading % 2 === 0 ? 7 : 6)) % 8;
            $found = null;
            for ($offset = 0; $offset < count($moves); $offset++) {
                $direction = ($start + $offset) % count($moves);
                [$dx, $dy] = $moves[$direction];
                if ($this->labelAt($x + $dx, $y + $dy) === $region->number) {
                    $found = $direction;
                    break;
                }
            }
            if ($found === null) {
                return [];
            }
            [$dx, $dy] = $moves[$found];
            $visited[] = [$x + $dx, $y + $dy];
            $codes[] = $found;
            $heading = $found;
            $count = count($codes);
            if ($count >= 2 && $visited[$count] === $visited[1] && $visited[$count - 1] === $visited[0]) {
                array_pop($codes);
                return $codes;
            }
        }
    }

    private function measure(Region $region): void
    {
        $f =& $region->features;
        $area = count($region->pixels);
        $sx = $sy = $sxx = $syy = $sxy = $intensity = $squares = 0;
        $x0 = $this->width;
        $y0 = $this->height;
        $x1 = $y1 = -1;
        $minimum = $this->image->maxval;
        $maximum = 0;
        $surrounding = [];
        $perimeter = $runs = 0;
        foreach ($region->pixels as [$x, $y]) {
            $value = $this->image->pixels[$y][$x];
            $sx += $x;
            $sy += $y;
            $sxx += $x * $x;
            $syy += $y * $y;
            $sxy += $x * $y;
            $intensity += $value;
            $squares += $value * $value;
            $x0 = min($x0, $x);
            $y0 = min($y0, $y);
            $x1 = max($x1, $x);
            $y1 = max($y1, $y);
            $minimum = min($minimum, $value);
            $maximum = max($maximum, $value);
            foreach (DIRECTIONS[8] as [$dx, $dy]) {
                $nx = $x + $dx;
                $ny = $y + $dy;
                if ($this->labelAt($nx, $ny) === 0) {
                    $surrounding[pixelKey($nx, $ny)] = $this->image->pixels[$ny][$nx];
                }
            }
            foreach (DIRECTIONS[$this->complement] as [$dx, $dy]) {
                if ($this->labelAt($x + $dx, $y + $dy) !== $region->number) {
                    $perimeter++;
                    break;
                }
            }
            if ($this->labelAt($x - 1, $y) !== $region->number) {
                $runs++;
            }
        }
        $f['area'] = $area;
        $f['x0'] = $x0;
        $f['y0'] = $y0;
        $f['x1'] = $x1;
        $f['y1'] = $y1;
        $f['width'] = $x1 - $x0 + 1;
        $f['height'] = $y1 - $y0 + 1;
        $f['border'] = (int)($x0 === 0 || $y0 === 0 || $x1 === $this->width - 1 || $y1 === $this->height - 1);
        $f['mean'] = new Rational($intensity, $area);
        $f['variance'] = new Rational($area * $squares - $intensity * $intensity, $area * $area);
        $f['min'] = $minimum;
        $f['max'] = $maximum;
        $surroundingCount = count($surrounding);
        $f['contrast'] = $surroundingCount > 0
            ? new Rational($intensity * $surroundingCount - array_sum($surrounding) * $area, $area * $surroundingCount)
            : new Rational(0);
        $region->codes = $this->chainCode($region);
        $straight = $diagonal = $turns = 0;
        $codeCount = count($region->codes);
        foreach ($region->codes as $index => $code) {
            if ($this->connectivity === 4 || $code % 2 === 0) {
                $straight++;
            } else {
                $diagonal++;
            }
            if ($code !== $region->codes[($index + $codeCount - 1) % $codeCount]) {
                $turns++;
            }
        }
        $f['perimeter'] = $perimeter;
        $f['runs'] = $runs;
        $f['chain'] = $codeCount;
        $f['straight'] = $straight;
        $f['diagonal'] = $diagonal;
        $f['turns'] = $turns;
        $contour = 5 * $straight + 7 * $diagonal;
        $f['compactness'] = new Rational($contour * $contour, 25 * $area);
        $f['holes'] = $f['hole_area'] = 0;
        foreach ($this->holes as $hole) {
            if ($hole->owner === $region->number) {
                $f['holes']++;
                $f['hole_area'] += count($hole->pixels);
            }
        }
        $f['euler'] = 1 - $f['holes'];
        $f['depth'] = $region->depth;
        $m20 = $area * $sxx - $sx * $sx;
        $m02 = $area * $syy - $sy * $sy;
        $m11 = $area * $sxy - $sx * $sy;
        $f['cx'] = new Rational($sx, $area);
        $f['cy'] = new Rational($sy, $area);
        $f['var_x'] = new Rational($m20, $area * $area);
        $f['var_y'] = new Rational($m02, $area * $area);
        $f['cov_xy'] = new Rational($m11, $area * $area);
        $f['hu1'] = new Rational($m20 + $m02, $area * $area * $area);
        $f['anisotropy'] = $m20 + $m02 > 0 ? new Rational(abs($m20 - $m02) + 2 * abs($m11), $m20 + $m02) : new Rational(0);
        $f['orientation'] = 'none';
        if ($f['anisotropy']->compare($this->parameters->isotropy) > 0) {
            $u = $m20 - $m02;
            $v = 2 * $m11;
            $f['orientation'] = abs($v) >= abs($u) ? ($v > 0 ? 'falling' : 'rising') : ($u > 0 ? 'horizontal' : 'vertical');
        }
        $mirrorLr = $mirrorTb = 0;
        foreach ($region->pixels as [$x, $y]) {
            $mirrorLr += (int)($this->labelAt($x0 + $x1 - $x, $y) === $region->number);
            $mirrorTb += (int)($this->labelAt($x, $y0 + $y1 - $y) === $region->number);
        }
        $f['extent'] = new Rational($area, $f['width'] * $f['height']);
        $f['mirror_lr'] = new Rational($mirrorLr, $area);
        $f['mirror_tb'] = new Rational($mirrorTb, $area);
        $this->measureHull($region);
        $region->skeleton = thin($region->pixels);
        $f['skeleton'] = count($region->skeleton);
        $f['endpoints'] = $f['branches'] = 0;
        foreach ($region->skeleton as [$x, $y]) {
            $crossing = crossingNumber($region->skeleton, $x, $y);
            $f['endpoints'] += (int)($crossing === 1);
            $f['branches'] += (int)($crossing >= 3);
        }
    }

    private function measureHull(Region $region): void
    {
        $f =& $region->features;
        $hull = convexHull($region->pixels);
        $doubled = $feret2 = 0;
        $width2 = null;
        foreach ($hull as $index => $a) {
            $b = $hull[($index + 1) % count($hull)];
            $doubled += $a[0] * $b[1] - $b[0] * $a[1];
            $reach = 0;
            foreach ($hull as $point) {
                $feret2 = max($feret2, squaredDistance($a, $point));
                $reach = max($reach, abs(cross($a, $b, $point)));
            }
            $candidate = new Rational($reach * $reach, squaredDistance($a, $b));
            if ($width2 === null || $candidate->compare($width2) < 0) {
                $width2 = $candidate;
            }
        }
        $region->hullDoubled = abs($doubled);
        $f['solidity'] = new Rational(2 * count($region->pixels), $region->hullDoubled);
        $f['feret2'] = $feret2;
        $f['width2'] = $width2;
        $f['elongation'] = new Rational($feret2 * $width2->denominator, $width2->numerator);
        $mask = [];
        for ($y = $f['y0']; $y <= $f['y1']; $y++) {
            $row = [];
            for ($x = $f['x0']; $x <= $f['x1']; $x++) {
                $row[] = $this->labels[$y][$x] === 0 && $this->holeOf[$y][$x] === 0 && containsCenter($hull, $x, $y);
            }
            $mask[] = $row;
        }
        $bays = labelComponents($mask, $this->complement);
        $f['bays'] = $f['bay_area'] = 0;
        foreach (array_slice(groupPixels($bays->labels, $bays->count), 1) as $pixels) {
            $size = count($pixels);
            $f['bay_area'] += $size;
            $f['bays'] += (int)($size >= $this->parameters->bayMin);
        }
    }

    public function applyRules(Rules $rules): void
    {
        foreach ($this->regions as $region) {
            foreach ($rules->filters as $index => $condition) {
                if (!$condition->holds($region->features)) {
                    $region->droppedBy = $index;
                    break;
                }
            }
            if ($region->droppedBy !== null) {
                continue;
            }
            $region->kept = true;
            foreach ($rules->classes as $rule) {
                if ($rule->matches($region->features)) {
                    $region->className = $rule->name;
                    break;
                }
            }
            foreach ($rules->flags as $rule) {
                if ($rule->matches($region->features)) {
                    $region->flags[] = $rule->name;
                }
            }
        }
    }

    public function keptRegions(): array
    {
        return array_values(array_filter($this->regions, static fn(Region $region): bool => $region->kept));
    }

    public function findNeighbors(): void
    {
        $kept = $this->keptRegions();
        foreach ($kept as $region) {
            foreach ($kept as $other) {
                if ($other === $region) {
                    continue;
                }
                $a = $region->features;
                $b = $other->features;
                $dx = $a['x0'] + $a['x1'] - $b['x0'] - $b['x1'];
                $dy = $a['y0'] + $a['y1'] - $b['y0'] - $b['y1'];
                $distance = $dx * $dx + $dy * $dy;
                if ($region->neighbor === null || $distance < $region->distance) {
                    $region->distance = $distance;
                    $region->neighbor = $other->number;
                }
            }
        }
    }

    private function treeText(Region $region): string
    {
        if ($region->children === []) {
            return (string)$region->number;
        }
        $inner = array_map(fn(Region $child): string => $this->treeText($child), $region->children);
        return $region->number . '(' . implode(' ', $inner) . ')';
    }

    public function thresholdLines(): array
    {
        $image = $this->image;
        $h = $this->histogram;
        $lines = [
            "image {$image->name} size {$this->width} {$this->height} maxval {$image->maxval}",
            "histogram pixels {$h->pixels} min {$h->minimum} max {$h->maximum} mean " . meanText($h->total, $h->pixels)
                . " median {$h->median} mode {$h->mode} levels {$h->levels}",
            'bins ' . implode(' ', array_merge([$h->binWidth], $h->bins)),
            "otsu threshold {$this->otsu->cutoff} upper {$this->otsu->upper} candidates " . count($this->otsu->candidates),
        ];
        foreach (array_slice($this->otsu->candidates, 0, $this->parameters->otsuTop) as $index => $candidate) {
            $rank = $index + 1;
            $gap = decimal(
                $candidate->sumAbove * $candidate->below - $candidate->sumBelow * $candidate->above,
                $candidate->below * $candidate->above,
                2
            );
            $lines[] = "rank {$rank} t {$candidate->cutoff} below {$candidate->below} above {$candidate->above}"
                . ' mean_below ' . meanText($candidate->sumBelow, $candidate->below)
                . ' mean_above ' . meanText($candidate->sumAbove, $candidate->above) . ' gap ' . $gap;
        }
        $lines[] = "isodata threshold {$this->isodataCutoff} iterations {$this->isodataIterations}";
        $lines[] = "threshold {$this->cutoff} " . $this->setting->method() . " {$this->setting->polarity} foreground " . countForeground($this->initial);
        foreach ($this->setting->operations as $index => $operation) {
            $lines[] = "morph {$operation} foreground {$this->morphCounts[$index]}";
        }
        foreach ($this->sweep as [$cutoff, $foreground, $regions]) {
            $lines[] = "sweep {$cutoff} foreground {$foreground} regions {$regions}";
        }
        return $lines;
    }

    private function regionSymbol(int $x, int $y, bool $skeletonOnly): string
    {
        $number = $this->labels[$y][$x];
        if ($number === 0) {
            return $this->holeOf[$y][$x] > 0 ? ':' : '.';
        }
        $region = $this->regions[$number - 1];
        if ($skeletonOnly && !isset($region->skeleton[pixelKey($x, $y)])) {
            return '+';
        }
        return $region->kept ? SYMBOLS[$number % strlen(SYMBOLS)] : '#';
    }

    public function mapLines(): array
    {
        $size = "{$this->image->name} {$this->width} {$this->height}";
        $lines = ['morphology ' . $size];
        for ($y = 0; $y < $this->height; $y++) {
            $row = '';
            for ($x = 0; $x < $this->width; $x++) {
                $before = $this->initial[$y][$x];
                $after = $this->final[$y][$x];
                $row .= $after ? ($before ? '#' : '+') : ($before ? '-' : '.');
            }
            $lines[] = $row;
        }
        foreach (['labels', 'skeleton'] as $heading) {
            $lines[] = $heading . ' ' . $size;
            for ($y = 0; $y < $this->height; $y++) {
                $row = '';
                for ($x = 0; $x < $this->width; $x++) {
                    $row .= $this->regionSymbol($x, $y, $heading === 'skeleton');
                }
                $lines[] = $row;
            }
        }
        return $lines;
    }

    public function csvRows(): array
    {
        $rows = [];
        foreach ($this->keptRegions() as $region) {
            $f = $region->features;
            $columns = [
                $this->image->name, $region->number, $region->className, $region->flags === [] ? '-' : implode('+', $region->flags),
                $f['area'], $f['x0'], $f['y0'], $f['x1'], $f['y1'], $f['cx']->text(3), $f['cy']->text(3),
                $f['mean']->text(2), $f['variance']->text(2), $f['min'], $f['max'], $f['contrast']->text(2),
                $f['border'], $f['perimeter'], $f['chain'], $f['straight'], $f['diagonal'], $f['turns'],
                $f['compactness']->text(3), $f['runs'], $f['holes'], $f['hole_area'], $f['euler'],
                $region->parent ?? '-', $f['depth'], $f['var_x']->text(3), $f['var_y']->text(3), $f['cov_xy']->text(3),
                $f['hu1']->text(4), $f['orientation'], $f['anisotropy']->text(3), $f['extent']->text(3),
                $f['mirror_lr']->text(3), $f['mirror_tb']->text(3), hullAreaText($region->hullDoubled),
                $f['solidity']->text(3), $f['feret2'], $f['width2']->text(3), $f['elongation']->text(3),
                $f['bays'], $f['bay_area'], $f['skeleton'], $f['endpoints'], $f['branches'], $region->neighbor ?? '-',
                $region->neighbor === null ? '-' : decimal($region->distance, 4, 2),
                $region->codes === [] ? '-' : implode('', $region->codes),
            ];
            $rows[] = implode(',', $columns);
        }
        return $rows;
    }

    private function intensityText(bool $foreground): string
    {
        $total = $count = 0;
        foreach ($this->image->pixels as $y => $row) {
            foreach ($row as $x => $value) {
                if ($this->final[$y][$x] === $foreground) {
                    $total += $value;
                    $count++;
                }
            }
        }
        return meanText($total, $count);
    }

    private function areaLine(array $kept): string
    {
        if ($kept === []) {
            return 'area total 0 mean - largest - smallest -';
        }
        $total = 0;
        $largest = $smallest = $kept[0];
        foreach ($kept as $region) {
            $total += $region->features['area'];
            if ($region->features['area'] > $largest->features['area']) {
                $largest = $region;
            }
            if ($region->features['area'] < $smallest->features['area']) {
                $smallest = $region;
            }
        }
        return "area total {$total} mean " . meanText($total, count($kept))
            . " largest {$largest->number} {$largest->features['area']} smallest {$smallest->number} {$smallest->features['area']}";
    }

    public function summaryLines(Rules $rules): array
    {
        $kept = $this->keptRegions();
        $regionCount = count($this->regions);
        $holeCount = count($this->holes);
        $holePixels = 0;
        foreach ($this->holes as $hole) {
            $holePixels += count($hole->pixels);
        }
        $lines = [
            "image {$this->image->name}",
            "threshold {$this->cutoff} " . $this->setting->method() . " {$this->setting->polarity} conn {$this->connectivity}",
            'foreground ' . countForeground($this->initial) . ' ' . countForeground($this->final),
            "regions {$regionCount} provisional {$this->provisional} kept " . count($kept) . ' dropped ' . ($regionCount - count($kept)),
            "connectivity four {$this->fourComponents} eight {$this->eightComponents}",
            "holes {$holeCount} hole_pixels {$holePixels} euler " . ($regionCount - $holeCount) . " bitquad {$this->bitQuad}",
        ];
        foreach ($this->holes as $hole) {
            $lines[] = "hole {$hole->number} owner {$hole->owner} area " . count($hole->pixels) . ' box ' . implode(' ', $hole->box());
        }
        $depthMax = 0;
        $roots = ['tree'];
        foreach ($this->regions as $region) {
            $depthMax = max($depthMax, $region->depth);
            if ($region->parent === null) {
                $roots[] = $this->treeText($region);
            }
        }
        $lines[] = 'depth_max ' . $depthMax;
        $lines[] = implode(' ', $roots);
        $lines[] = 'intensity foreground ' . $this->intensityText(true) . ' background ' . $this->intensityText(false);
        $lines[] = $this->areaLine($kept);
        $classes = ['classes'];
        foreach ($rules->classNames() as $name) {
            $count = 0;
            foreach ($kept as $region) {
                $count += (int)($region->className === $name);
            }
            array_push($classes, $name, (string)$count);
        }
        $lines[] = implode(' ', $classes);
        $lines[] = orientationLine($kept);
        $flags = ['flags'];
        foreach ($rules->flags as $rule) {
            $count = 0;
            foreach ($kept as $region) {
                $count += (int)in_array($rule->name, $region->flags, true);
            }
            array_push($flags, $rule->name, (string)$count);
        }
        $lines[] = implode(' ', $flags);
        return $lines;
    }
}

function overallLines(array $analyses, Rules $rules): array
{
    $regions = $kept = [];
    $holeCount = 0;
    $largest = null;
    $largestImage = null;
    foreach ($analyses as $analysis) {
        array_push($regions, ...$analysis->regions);
        array_push($kept, ...$analysis->keptRegions());
        $holeCount += count($analysis->holes);
        foreach ($analysis->keptRegions() as $region) {
            if ($largest === null || $region->features['area'] > $largest->features['area']) {
                $largest = $region;
                $largestImage = $analysis->image->name;
            }
        }
    }
    $regionCount = count($regions);
    $lines = [
        'overall',
        'images ' . count($analyses),
        "regions {$regionCount} kept " . count($kept) . ' dropped ' . ($regionCount - count($kept)),
        "holes {$holeCount} euler " . ($regionCount - $holeCount),
    ];
    foreach ($rules->filters as $index => $condition) {
        $dropped = 0;
        foreach ($regions as $region) {
            $dropped += (int)($region->droppedBy === $index);
        }
        $lines[] = 'filter ' . ($index + 1) . ' ' . $condition->words() . ' dropped ' . $dropped;
    }
    foreach ($rules->classNames() as $name) {
        $count = $area = 0;
        foreach ($kept as $region) {
            if ($region->className === $name) {
                $count++;
                $area += $region->features['area'];
            }
        }
        $lines[] = "class {$name} count {$count} area {$area} mean " . meanText($area, $count);
    }
    foreach ($rules->flags as $rule) {
        $count = 0;
        foreach ($kept as $region) {
            $count += (int)in_array($rule->name, $region->flags, true);
        }
        $lines[] = "flag {$rule->name} count {$count}";
    }
    $lines[] = orientationLine($kept);
    $lines[] = $largest === null ? 'largest -' : "largest {$largestImage} {$largest->number} {$largest->features['area']}";
    return $lines;
}

function main(): void
{
    $parameters = readParameters('input/params.txt');
    $rules = readRules('input/rules.txt');
    $analyses = [];
    foreach (readImages('input/images.txt') as $image) {
        $analysis = new ImageAnalysis($image, $parameters->settings['#' . $image->name], $parameters);
        $analysis->applyRules($rules);
        $analysis->findNeighbors();
        $analyses[] = $analysis;
    }
    $thresholds = $maps = $summary = [];
    $rows = [CSV_HEADER];
    foreach ($analyses as $analysis) {
        array_push($thresholds, ...$analysis->thresholdLines());
        array_push($maps, ...$analysis->mapLines());
        array_push($rows, ...$analysis->csvRows());
        array_push($summary, ...$analysis->summaryLines($rules));
    }
    array_push($summary, ...overallLines($analyses, $rules));
    writeFiles('output', [
        'thresholds.txt' => $thresholds,
        'labels.txt' => $maps,
        'regions.csv' => $rows,
        'summary.txt' => $summary,
    ]);
}

main();
