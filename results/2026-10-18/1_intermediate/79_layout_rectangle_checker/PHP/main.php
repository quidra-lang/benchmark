<?php
class LayoutError extends Exception
{
}

class Rectangle
{
    public function __construct(public string $name, public string $layer, public int $x1, public int $y1, public int $x2, public int $y2)
    {
    }

    public function box(): array
    {
        return [$this->x1, $this->y1, $this->x2, $this->y2];
    }

    public function width(): int
    {
        return $this->x2 - $this->x1;
    }

    public function height(): int
    {
        return $this->y2 - $this->y1;
    }
}

class CoverageGrid
{
    public array $xs;
    public array $ys;
    public array $cells;

    public function __construct(array $rectangles)
    {
        $xs = $ys = [];
        foreach ($rectangles as $r) {
            $xs[] = $r->x1;
            $xs[] = $r->x2;
            $ys[] = $r->y1;
            $ys[] = $r->y2;
        }
        $this->xs = array_values(array_unique($xs, SORT_NUMERIC));
        $this->ys = array_values(array_unique($ys, SORT_NUMERIC));
        sort($this->xs, SORT_NUMERIC);
        sort($this->ys, SORT_NUMERIC);
        $this->cells = array_fill(0, count($this->ys) - 1, array_fill(0, count($this->xs) - 1, 0));
        foreach ($rectangles as $r) {
            $left = array_search($r->x1, $this->xs, true);
            $right = array_search($r->x2, $this->xs, true);
            $bottom = array_search($r->y1, $this->ys, true);
            $top = array_search($r->y2, $this->ys, true);
            for ($j = $bottom; $j < $top; $j++) {
                for ($i = $left; $i < $right; $i++) {
                    $this->cells[$j][$i]++;
                }
            }
        }
    }

    public function area(int $k = 1, ?array $window = null): int
    {
        $result = 0;
        foreach ($this->cells as $j => $row) {
            foreach ($row as $i => $count) {
                if ($count < $k) {
                    continue;
                }
                $dx = $window === null ? $this->xs[$i + 1] - $this->xs[$i] : max(0, min($this->xs[$i + 1], $window[2]) - max($this->xs[$i], $window[0]));
                $dy = $window === null ? $this->ys[$j + 1] - $this->ys[$j] : max(0, min($this->ys[$j + 1], $window[3]) - max($this->ys[$j], $window[1]));
                $result += $dx * $dy;
            }
        }
        return $result;
    }

    public function perimeter(): int
    {
        $result = 0;
        foreach ($this->cells as $j => $row) {
            foreach ($row as $i => $count) {
                if ($count === 0) {
                    continue;
                }
                $dy = $this->ys[$j + 1] - $this->ys[$j];
                $dx = $this->xs[$i + 1] - $this->xs[$i];
                if ($i === 0 || $row[$i - 1] === 0) {
                    $result += $dy;
                }
                if ($i + 1 === count($row) || $row[$i + 1] === 0) {
                    $result += $dy;
                }
                if ($j === 0 || $this->cells[$j - 1][$i] === 0) {
                    $result += $dx;
                }
                if ($j + 1 === count($this->cells) || $this->cells[$j + 1][$i] === 0) {
                    $result += $dx;
                }
            }
        }
        return $result;
    }

    public function largestEmpty(): ?array
    {
        $best = null;
        for ($left = 0; $left + 1 < count($this->xs); $left++) {
            $blocked = array_fill(0, count($this->ys) - 1, false);
            for ($right = $left; $right + 1 < count($this->xs); $right++) {
                foreach ($blocked as $j => $value) {
                    $blocked[$j] = $value || $this->cells[$j][$right] > 0;
                }
                for ($j = 0; $j < count($blocked);) {
                    if ($blocked[$j]) {
                        $j++;
                        continue;
                    }
                    $start = $j;
                    while ($j < count($blocked) && !$blocked[$j]) {
                        $j++;
                    }
                    $width = $this->xs[$right + 1] - $this->xs[$left];
                    $area = $width * ($this->ys[$j] - $this->ys[$start]);
                    $choice = [-$area, $this->xs[$left], $this->ys[$start], $width, $this->xs[$right + 1], $this->ys[$j]];
                    if ($best === null || $choice < $best) {
                        $best = $choice;
                    }
                }
            }
        }
        return $best === null ? null : [[$best[1], $best[2], $best[4], $best[5]], -$best[0]];
    }

    public function holes(): array
    {
        $visited = $result = [];
        $nx = count($this->xs) - 1;
        $ny = count($this->ys) - 1;
        for ($j = 0; $j < $ny; $j++) {
            for ($i = 0; $i < $nx; $i++) {
                if ($this->cells[$j][$i] > 0 || isset($visited["$i,$j"])) {
                    continue;
                }
                $queue = [[$i, $j]];
                $visited["$i,$j"] = true;
                $area = $head = 0;
                $boundary = false;
                $x1 = $x2 = $this->xs[$i];
                $y1 = $y2 = $this->ys[$j];
                $anchor = [$y1, $x1];
                while ($head < count($queue)) {
                    [$x, $y] = $queue[$head++];
                    $area += ($this->xs[$x + 1] - $this->xs[$x]) * ($this->ys[$y + 1] - $this->ys[$y]);
                    $x1 = min($x1, $this->xs[$x]);
                    $x2 = max($x2, $this->xs[$x + 1]);
                    $y1 = min($y1, $this->ys[$y]);
                    $y2 = max($y2, $this->ys[$y + 1]);
                    $point = [$this->ys[$y], $this->xs[$x]];
                    if ($point < $anchor) {
                        $anchor = $point;
                    }
                    $boundary = $boundary || $x === 0 || $y === 0 || $x + 1 === $nx || $y + 1 === $ny;
                    foreach ([[$x - 1, $y], [$x + 1, $y], [$x, $y - 1], [$x, $y + 1]] as [$a, $b]) {
                        if ($a < 0 || $b < 0 || $a >= $nx || $b >= $ny || $this->cells[$b][$a] > 0 || isset($visited["$a,$b"])) {
                            continue;
                        }
                        $visited["$a,$b"] = true;
                        $queue[] = [$a, $b];
                    }
                }
                if (!$boundary) {
                    $result[] = [$anchor, $area, [$x1, $y1, $x2, $y2]];
                }
            }
        }
        usort($result, fn($a, $b) => $a[0] <=> $b[0]);
        return $result;
    }

    public function pieces(): array
    {
        $active = $result = [];
        foreach ($this->cells as $j => $row) {
            $current = [];
            for ($i = 0; $i < count($row);) {
                if ($row[$i] === 0) {
                    $i++;
                    continue;
                }
                $start = $i;
                while ($i < count($row) && $row[$i] > 0) {
                    $i++;
                }
                $left = $this->xs[$start];
                $right = $this->xs[$i];
                $key = "$left,$right";
                $current[$key] = [$left, $active[$key][1] ?? $this->ys[$j], $right];
                unset($active[$key]);
            }
            foreach ($active as [$left, $bottom, $right]) {
                $result[] = [$left, $bottom, $right, $this->ys[$j]];
            }
            $active = $current;
        }
        foreach ($active as [$left, $bottom, $right]) {
            $result[] = [$left, $bottom, $right, $this->ys[count($this->ys) - 1]];
        }
        usort($result, fn($a, $b) => [$a[1], $a[0]] <=> [$b[1], $b[0]]);
        return $result;
    }
}

class RectangleWorkbench
{
    private array $rectangles = [];
    private array $rules = [];
    private array $history = [];

    private function notation(array $box): string
    {
        return "({$box[0]},{$box[1]})-({$box[2]},{$box[3]})";
    }

    private function point(int $x, int $y): string
    {
        return "($x,$y)";
    }

    private function percent(int $area, int $denominator): string
    {
        $value = intdiv(10000 * $area, $denominator);
        return sprintf('%d.%02d', intdiv($value, 100), $value % 100);
    }

    private function sorted(): array
    {
        $result = array_values($this->rectangles);
        usort($result, fn($a, $b) => strcmp($a->name, $b->name));
        return $result;
    }

    private function onLayer(string $layer): array
    {
        return array_values(array_filter($this->sorted(), fn($r) => $r->layer === $layer));
    }

    private function requireLayer(string $layer): array
    {
        $rectangles = $this->onLayer($layer);
        if ($rectangles === []) {
            throw new LayoutError("no rectangles on $layer");
        }
        return $rectangles;
    }

    private function rectangle(string $name): Rectangle
    {
        if (!isset($this->rectangles[$name])) {
            throw new LayoutError("unknown rectangle $name");
        }
        return $this->rectangles[$name];
    }

    private function bounds(array $box): void
    {
        foreach ($box as $coordinate) {
            if (abs($coordinate) > 10000) {
                throw new LayoutError('out of bounds');
            }
        }
    }

    private function remember(string $line): void
    {
        $this->history[] = [array_map(fn($r) => clone $r, $this->rectangles), $line];
    }

    private function relation(Rectangle $a, Rectangle $b): array
    {
        $box = [max($a->x1, $b->x1), max($a->y1, $b->y1), min($a->x2, $b->x2), min($a->y2, $b->y2)];
        $ox = $box[2] - $box[0];
        $oy = $box[3] - $box[1];
        $kind = $ox < 0 || $oy < 0 ? 'separated' : ($ox === 0 && $oy === 0 ? 'corner' : ($ox === 0 || $oy === 0 ? 'edge' : 'overlap'));
        $direction = $ox < 0 && $oy < 0 ? 'diagonal' : ($ox < 0 ? 'x' : 'y');
        return [$kind, $box, $ox, $oy, max(0, -$ox, -$oy), $direction];
    }

    private function contains(Rectangle $a, Rectangle $b): bool
    {
        return $a->x1 <= $b->x1 && $a->y1 <= $b->y1 && $a->x2 >= $b->x2 && $a->y2 >= $b->y2;
    }

    private function connected(Rectangle $a, Rectangle $b): bool
    {
        return in_array($this->relation($a, $b)[0], ['overlap', 'edge'], true);
    }

    private function nets(array $rectangles): array
    {
        $remaining = $rectangles;
        $result = [];
        while ($remaining !== []) {
            $group = [array_shift($remaining)];
            for ($i = 0; $i < count($group); $i++) {
                $next = [];
                foreach ($remaining as $r) {
                    if ($this->connected($group[$i], $r)) {
                        $group[] = $r;
                    } else {
                        $next[] = $r;
                    }
                }
                $remaining = $next;
            }
            usort($group, fn($a, $b) => strcmp($a->name, $b->name));
            $result[] = $group;
        }
        return $result;
    }

    private function spacing(array $rectangles, int $minimum): array
    {
        $result = [];
        foreach ($rectangles as $i => $a) {
            for ($j = $i + 1; $j < count($rectangles); $j++) {
                $b = $rectangles[$j];
                [$kind, , , , $gap, $direction] = $this->relation($a, $b);
                if ($kind === 'corner' || ($kind === 'separated' && $gap < $minimum)) {
                    $result[] = [$gap, $a->name, $b->name, $kind === 'corner' ? 'corner' : $direction];
                }
            }
        }
        usort($result, fn($a, $b) => $a <=> $b);
        return $result;
    }

    private function spacingLines(array $violations): void
    {
        foreach ($violations as [$gap, $a, $b, $direction]) {
            echo "$a $b gap $gap $direction\n";
        }
    }

    private function bounding(array $rectangles): array
    {
        return [min(array_map(fn($r) => $r->x1, $rectangles)), min(array_map(fn($r) => $r->y1, $rectangles)), max(array_map(fn($r) => $r->x2, $rectangles)), max(array_map(fn($r) => $r->y2, $rectangles))];
    }

    public function execute(string $line): void
    {
        $args = explode(' ', $line);
        $command = array_shift($args);
        try {
            if ($command === 'ADD') {
                [$name, $layer] = array_slice($args, 0, 2);
                if (isset($this->rectangles[$name])) {
                    throw new LayoutError("duplicate rectangle $name");
                }
                [$x1, $y1, $x2, $y2] = array_map('intval', array_slice($args, 2));
                if ($x1 >= $x2 || $y1 >= $y2) {
                    throw new LayoutError('invalid rectangle');
                }
                $this->bounds([$x1, $y1, $x2, $y2]);
                $this->remember($line);
                $this->rectangles[$name] = new Rectangle($name, $layer, $x1, $y1, $x2, $y2);
                echo "added $name $layer ", $this->notation([$x1, $y1, $x2, $y2]), "\n";
            } elseif (in_array($command, ['COPY', 'MOVE', 'RESIZE', 'SPLIT', 'LAYER', 'DELETE'], true)) {
                $name = $args[0];
                $original = $this->rectangle($name);
                $changed = clone $original;
                if ($command === 'COPY' || $command === 'MOVE') {
                    $newName = $command === 'COPY' ? $args[1] : $name;
                    if ($command === 'COPY' && isset($this->rectangles[$newName])) {
                        throw new LayoutError("duplicate rectangle $newName");
                    }
                    [$dx, $dy] = array_map('intval', array_slice($args, $command === 'COPY' ? 2 : 1));
                    $changed->name = $newName;
                    $changed->x1 += $dx;
                    $changed->x2 += $dx;
                    $changed->y1 += $dy;
                    $changed->y2 += $dy;
                    $this->bounds($changed->box());
                    $message = $command === 'COPY' ? "copied $name to $newName " . $this->notation($changed->box()) : "moved $name to " . $this->notation($changed->box());
                } elseif ($command === 'RESIZE') {
                    [$width, $height] = array_map('intval', array_slice($args, 1));
                    if ($width <= 0 || $height <= 0) {
                        throw new LayoutError('invalid size');
                    }
                    $changed->x2 = $changed->x1 + $width;
                    $changed->y2 = $changed->y1 + $height;
                    $this->bounds($changed->box());
                    $message = "resized $name to " . $this->notation($changed->box());
                } elseif ($command === 'SPLIT') {
                    [$axis, $position, $newName] = array_slice($args, 1);
                    $position = (int)$position;
                    if (isset($this->rectangles[$newName])) {
                        throw new LayoutError("duplicate rectangle $newName");
                    }
                    $valid = $axis === 'x' ? $original->x1 < $position && $position < $original->x2 : $original->y1 < $position && $position < $original->y2;
                    if (!$valid) {
                        throw new LayoutError("cut outside $name");
                    }
                    $added = clone $original;
                    $added->name = $newName;
                    if ($axis === 'x') {
                        $changed->x2 = $added->x1 = $position;
                    } else {
                        $changed->y2 = $added->y1 = $position;
                    }
                    $message = "split $name at $axis=$position: $name " . $this->notation($changed->box()) . ", $newName " . $this->notation($added->box());
                } elseif ($command === 'LAYER') {
                    if ($original->layer === $args[1]) {
                        throw new LayoutError("already on {$args[1]}");
                    }
                    $changed->layer = $args[1];
                    $message = "layer $name {$original->layer} -> {$changed->layer}";
                } else {
                    $message = "deleted $name";
                }
                $this->remember($line);
                if ($command === 'DELETE') {
                    unset($this->rectangles[$name]);
                } else {
                    $this->rectangles[$changed->name] = $changed;
                    if ($command === 'SPLIT') {
                        $this->rectangles[$added->name] = $added;
                    }
                }
                echo $message, "\n";
            } elseif ($command === 'UNDO') {
                if ($this->history === []) {
                    throw new LayoutError('nothing to undo');
                }
                [$this->rectangles, $previous] = array_pop($this->history);
                echo "undo: $previous\n";
            } elseif ($command === 'LIST') {
                echo 'rectangles: ', count($this->rectangles), "\n";
                foreach ($this->sorted() as $r) {
                    echo "{$r->name} {$r->layer} ", $this->notation($r->box()), ' ', $r->width(), 'x', $r->height(), "\n";
                }
            } elseif ($command === 'INFO') {
                $a = $this->rectangle($args[0]);
                echo "{$a->name} {$a->layer} ", $this->notation($a->box()), ' ', $a->width(), 'x', $a->height(), ' area ', $a->width() * $a->height(), "\n";
                foreach (['overlaps', 'touches', 'corners', 'encloses', 'enclosed by'] as $i => $label) {
                    $names = [];
                    foreach ($this->sorted() as $b) {
                        if ($a->name === $b->name) {
                            continue;
                        }
                        $matches = $i < 3 ? $b->layer === $a->layer && $this->relation($a, $b)[0] === ['overlap', 'edge', 'corner'][$i] : ($i === 3 ? $this->contains($a, $b) : $this->contains($b, $a));
                        if ($matches) {
                            $names[] = $b->name;
                        }
                    }
                    echo "$label: ", $names === [] ? 'none' : implode(' ', $names), "\n";
                }
            } elseif ($command === 'LAYERS') {
                $layers = array_values(array_unique(array_map(fn($r) => $r->layer, $this->sorted()), SORT_STRING));
                sort($layers, SORT_STRING);
                echo 'layers: ', count($layers), "\n";
                foreach ($layers as $layer) {
                    $rectangles = $this->onLayer($layer);
                    echo "$layer: ", count($rectangles), ' rectangles, area ', (new CoverageGrid($rectangles))->area(), ', nets ', count($this->nets($rectangles)), "\n";
                }
            } elseif ($command === 'OVERLAPS') {
                $rectangles = $args === [] ? $this->sorted() : $this->requireLayer($args[0]);
                $pairs = [];
                foreach ($rectangles as $i => $a) {
                    for ($j = $i + 1; $j < count($rectangles); $j++) {
                        $b = $rectangles[$j];
                        [$kind, $box, $ox, $oy] = $this->relation($a, $b);
                        if ($a->layer === $b->layer && $kind === 'overlap') {
                            $pairs[] = [$a->layer, $a->name, $b->name, $box, $ox * $oy];
                        }
                    }
                }
                usort($pairs, fn($a, $b) => array_slice($a, 0, 3) <=> array_slice($b, 0, 3));
                echo 'overlaps ', $args === [] ? 'all layers' : $args[0], ': ', count($pairs), "\n";
                foreach ($pairs as [$layer, $a, $b, $box, $area]) {
                    echo $args === [] ? "$layer " : '', "$a $b ", $this->notation($box), " area $area\n";
                }
            } elseif (in_array($command, ['AREA', 'COVER', 'PERIMETER', 'BBOX', 'DENSITY', 'RENDER', 'EMPTY', 'HOLES', 'MERGE', 'NETS', 'DRC'], true)) {
                $layer = $command === 'COVER' ? $args[1] : $args[0];
                $rectangles = $this->requireLayer($layer);
                $grid = new CoverageGrid($rectangles);
                $box = $this->bounding($rectangles);
                if ($command === 'AREA') {
                    echo "area $layer: ", $grid->area(), "\n";
                } elseif ($command === 'COVER') {
                    echo "cover $layer >= {$args[0]}: ", $grid->area((int)$args[0]), "\n";
                } elseif ($command === 'PERIMETER') {
                    echo "perimeter $layer: ", $grid->perimeter(), "\n";
                } elseif ($command === 'BBOX') {
                    $width = $box[2] - $box[0];
                    $height = $box[3] - $box[1];
                    echo "bbox $layer: ", $this->notation($box), " {$width}x$height, ", count($rectangles), ' rectangles, density ', $this->percent($grid->area(), $width * $height), "%\n";
                } elseif ($command === 'DENSITY') {
                    $width = (int)$args[1];
                    $columns = intdiv($box[2] - $box[0] + $width - 1, $width);
                    $rows = intdiv($box[3] - $box[1] + $width - 1, $width);
                    if ($columns > 20 || $rows > 20) {
                        throw new LayoutError('too many windows');
                    }
                    $values = [];
                    for ($j = 0; $j < $rows; $j++) {
                        for ($i = 0; $i < $columns; $i++) {
                            $values[$j][$i] = $grid->area(1, [$box[0] + $i * $width, $box[1] + $j * $width, $box[0] + ($i + 1) * $width, $box[1] + ($j + 1) * $width]);
                        }
                    }
                    echo "density $layer window $width: {$columns}x$rows\n";
                    for ($j = $rows - 1; $j >= 0; $j--) {
                        echo implode(' ', array_map(fn($area) => intdiv(100 * $area, $width * $width), $values[$j])), "\n";
                    }
                    $flat = array_merge(...$values);
                    foreach ([['min', min($flat)], ['max', max($flat)]] as [$label, $value]) {
                        $index = array_search($value, $flat, true);
                        echo $label, ' ', $this->percent($value, $width * $width), '% at ', $this->point($box[0] + ($index % $columns) * $width, $box[1] + intdiv($index, $columns) * $width), "\n";
                    }
                } elseif ($command === 'RENDER') {
                    [$x1, $y1, $x2, $y2] = array_map('intval', array_slice($args, 1));
                    if ($x1 >= $x2 || $y1 >= $y2) {
                        throw new LayoutError('invalid window');
                    }
                    if ($x2 - $x1 > 60 || $y2 - $y1 > 40) {
                        throw new LayoutError('window too large');
                    }
                    echo "render $layer ", $this->notation([$x1, $y1, $x2, $y2]), "\n";
                    for ($y = $y2 - 1; $y >= $y1; $y--) {
                        $row = '';
                        for ($x = $x1; $x < $x2; $x++) {
                            $count = 0;
                            foreach ($rectangles as $r) {
                                if ($r->x1 <= $x && $x < $r->x2 && $r->y1 <= $y && $y < $r->y2) {
                                    $count++;
                                }
                            }
                            $row .= $count === 0 ? '.' : ($count >= 10 ? '*' : (string)$count);
                        }
                        echo $row, "\n";
                    }
                } elseif ($command === 'EMPTY') {
                    $empty = $grid->largestEmpty();
                    echo "empty $layer: ", $empty === null ? 'none' : $this->notation($empty[0]) . ' area ' . $empty[1], "\n";
                } elseif ($command === 'HOLES') {
                    $holes = $grid->holes();
                    echo "holes $layer: ", count($holes), "\n";
                    foreach ($holes as $i => [, $area, $bounds]) {
                        echo 'hole ', $i + 1, ": area $area, bbox ", $this->notation($bounds), "\n";
                    }
                } elseif ($command === 'MERGE') {
                    $pieces = $grid->pieces();
                    echo "merge $layer: ", count($pieces), " pieces\n";
                    foreach ($pieces as $piece) {
                        echo $this->notation($piece), "\n";
                    }
                } elseif ($command === 'NETS') {
                    $groups = $this->nets($rectangles);
                    echo "nets $layer: ", count($groups), "\n";
                    foreach ($groups as $i => $group) {
                        echo 'net ', $i + 1, ': ', implode(' ', array_map(fn($r) => $r->name, $group)), ' area ', (new CoverageGrid($group))->area(), "\n";
                    }
                } else {
                    $violations = $this->spacing($rectangles, (int)$args[1]);
                    echo "drc $layer spacing {$args[1]}: ", count($violations), " violations\n";
                    $this->spacingLines($violations);
                }
            } elseif (in_array($command, ['INTERSECT', 'ADJACENT', 'ENCLOSE', 'PATH'], true)) {
                $a = $this->rectangle($args[0]);
                $b = $this->rectangle($args[1]);
                if ($a->name === $b->name) {
                    throw new LayoutError("same rectangle {$a->name}");
                }
                [$kind, $box, $ox, $oy, $gap] = $this->relation($a, $b);
                $prefix = strtolower($command) . " {$a->name} {$b->name}: ";
                if ($command === 'ENCLOSE') {
                    $margins = [$b->x1 - $a->x1, $b->y1 - $a->y1, $a->x2 - $b->x2, $a->y2 - $b->y2];
                    echo $prefix, min($margins) >= 0 ? 'yes, ' : 'no, ', "margins left {$margins[0]} bottom {$margins[1]} right {$margins[2]} top {$margins[3]}", min($margins) >= 0 ? ', min ' . min($margins) : '', "\n";
                } elseif ($command === 'PATH') {
                    if ($a->layer !== $b->layer) {
                        throw new LayoutError('different layers');
                    }
                    $queue = [[$a->name]];
                    $seen = [$a->name => true];
                    $head = 0;
                    $path = null;
                    while ($head < count($queue)) {
                        $route = $queue[$head++];
                        $last = $route[count($route) - 1];
                        if ($last === $b->name) {
                            $path = $route;
                            break;
                        }
                        foreach ($this->onLayer($a->layer) as $r) {
                            if (!isset($seen[$r->name]) && $this->connected($this->rectangles[$last], $r)) {
                                $seen[$r->name] = true;
                                $queue[] = array_merge($route, [$r->name]);
                            }
                        }
                    }
                    echo $prefix, $path === null ? 'none' : implode(' -> ', $path) . ' (' . (count($path) - 1) . ' steps)', "\n";
                } elseif ($command === 'INTERSECT') {
                    $result = match ($kind) {
                        'overlap' => $this->notation($box) . ' area ' . ($ox * $oy),
                        'edge' => 'segment ' . $this->notation($box) . ' length ' . ($ox + $oy),
                        'corner' => 'point ' . $this->point($box[0], $box[1]),
                        default => "none, gap $gap"
                    };
                    echo $prefix, $result, "\n";
                } else {
                    if ($kind === 'edge') {
                        $direction = $ox === 0 ? ($a->x2 === $box[0] ? 'west' : 'east') : ($a->y2 === $box[1] ? 'south' : 'north');
                        $result = "{$a->name} is $direction of {$b->name}, edge " . $this->notation($box) . ', length ' . ($ox + $oy);
                    } else {
                        $result = $kind === 'overlap' ? 'overlapping' : ($kind === 'corner' ? 'corner only at ' . $this->point($box[0], $box[1]) : 'not adjacent');
                    }
                    echo $prefix, $result, "\n";
                }
            } elseif ($command === 'AT') {
                [$x, $y] = array_map('intval', $args);
                $found = [];
                foreach ($this->sorted() as $r) {
                    if ($r->x1 <= $x && $x <= $r->x2 && $r->y1 <= $y && $y <= $r->y2) {
                        $horizontal = $x === $r->x1 || $x === $r->x2;
                        $vertical = $y === $r->y1 || $y === $r->y2;
                        $found[] = "{$r->name} {$r->layer} " . ($horizontal && $vertical ? 'corner' : ($horizontal || $vertical ? 'edge' : 'inside'));
                    }
                }
                echo 'at ', $this->point($x, $y), ': ', $found === [] ? 'none' : implode(', ', $found), "\n";
            } elseif ($command === 'NEAREST') {
                $a = $this->rectangle($args[0]);
                $nearest = null;
                foreach ($this->onLayer($a->layer) as $r) {
                    if ($a->name !== $r->name) {
                        $choice = [$this->relation($a, $r)[4], $r->name];
                        if ($nearest === null || $choice < $nearest) {
                            $nearest = $choice;
                        }
                    }
                }
                echo "nearest {$a->name}: ", $nearest === null ? 'none' : "$nearest[1] gap $nearest[0]", "\n";
            } elseif ($command === 'RULE') {
                $kind = strtolower($args[0]);
                if ($kind === 'enclose' && $args[1] === $args[2]) {
                    throw new LayoutError("same layer {$args[1]}");
                }
                $key = $kind . ' ' . $args[1] . ($kind === 'enclose' ? ' ' . $args[2] : '');
                $this->rules[$key] = [$kind, $args[1], $kind === 'enclose' ? $args[2] : null, (int)$args[$kind === 'enclose' ? 3 : 2]];
                echo 'rule ', $kind, ' ', implode(' ', array_slice($args, 1)), "\n";
            } elseif ($command === 'CHECK') {
                if ($this->rules === []) {
                    throw new LayoutError('no rules');
                }
                $rules = $this->rules;
                ksort($rules, SORT_STRING);
                $total = 0;
                foreach ($rules as [$kind, $layer, $outer, $value]) {
                    $rectangles = $this->onLayer($layer);
                    if ($kind === 'spacing') {
                        $violations = $this->spacing($rectangles, $value);
                        echo "spacing $layer $value: ", count($violations), " violations\n";
                        $this->spacingLines($violations);
                    } elseif ($kind === 'width') {
                        $violations = array_values(array_filter($rectangles, fn($r) => min($r->width(), $r->height()) < $value));
                        echo "width $layer $value: ", count($violations), " violations\n";
                        foreach ($violations as $r) {
                            echo "{$r->name} width ", min($r->width(), $r->height()), "\n";
                        }
                    } else {
                        $enclosures = $this->onLayer($outer);
                        $violations = [];
                        foreach ($rectangles as $r) {
                            $best = null;
                            foreach ($enclosures as $u) {
                                $margin = min($r->x1 - $u->x1, $r->y1 - $u->y1, $u->x2 - $r->x2, $u->y2 - $r->y2);
                                $best = $best === null ? $margin : max($best, $margin);
                            }
                            if ($best === null || $best < $value) {
                                $violations[] = [$r->name, $best];
                            }
                        }
                        echo "enclose $layer $outer $value: ", count($violations), " violations\n";
                        foreach ($violations as [$name, $best]) {
                            echo "$name best margin ", $best === null ? 'none' : $best, "\n";
                        }
                    }
                    $total += count($violations);
                }
                echo "check: $total violations in ", count($this->rules), " rules\n";
            }
        } catch (LayoutError $error) {
            echo 'error: ', $error->getMessage(), "\n";
        }
    }
}

$workbench = new RectangleWorkbench();
$count = (int)fgets(STDIN);
for ($i = 0; $i < $count; $i++) {
    $workbench->execute(rtrim(fgets(STDIN), "\r\n"));
}
