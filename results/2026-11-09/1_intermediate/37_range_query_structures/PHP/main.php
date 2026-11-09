<?php
declare(strict_types=1);

enum Operation: string
{
    case SUM = 'SUM'; case MIN = 'MIN'; case MAX = 'MAX'; case GCD = 'GCD';
    public function combine(int $a, int $b): int
    {
        return match ($this) { self::SUM => $a + $b, self::MIN => min($a, $b), self::MAX => max($a, $b), self::GCD => gcd($a, $b) };
    }
}

final class CommandError extends RuntimeException {}

function gcd(int $a, int $b): int
{
    $a = abs($a); $b = abs($b);
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    return $a;
}
function integerSqrt(int $n): int
{
    $result = 1;
    while (($result + 1) * ($result + 1) <= $n) $result++;
    return $result;
}
function floorLog2(int $n): int
{
    $result = 0;
    while ((1 << ($result + 1)) <= $n) $result++;
    return $result;
}

final readonly class Interval
{
    public function __construct(public int $left, public int $right) {}
    public function leaf(): bool { return $this->left === $this->right; }
    public function middle(): int { return intdiv($this->left + $this->right, 2); }
    public function length(): int { return $this->right - $this->left + 1; }
    public function covered(int $left, int $right): bool { return $left <= $this->left && $this->right <= $right; }
}

final readonly class Layout
{
    public array $ranges;
    public int $count, $maxNode;
    public function __construct(int $n)
    {
        $ranges = array_fill(0, 4 * $n, null);
        $maxNode = 0;
        $build = function (int $node, int $left, int $right) use (&$build, &$ranges, &$maxNode): void {
            $ranges[$node] = new Interval($left, $right);
            $maxNode = max($maxNode, $node);
            if ($left === $right) return;
            $middle = intdiv($left + $right, 2);
            $build(2 * $node, $left, $middle);
            $build(2 * $node + 1, $middle + 1, $right);
        };
        $build(1, 0, $n - 1);
        $this->ranges = $ranges;
        $this->count = 2 * $n - 1;
        $this->maxNode = $maxNode;
    }
    public function nodes(): iterable
    {
        foreach ($this->ranges as $node => $range) if ($range !== null) yield $node => $range;
    }
}

final readonly class ScalarAnswer
{
    public function __construct(public int $value, public int $visited) {}
    public function __toString(): string { return "sum={$this->value} visited={$this->visited}"; }
}

final class SegmentTree
{
    public readonly Layout $shape;
    private array $values;
    public function __construct(array $contents, public readonly Operation $operation)
    {
        $this->shape = new Layout(count($contents));
        $this->values = array_fill(0, 4 * count($contents), 0);
        $this->build(1, $contents);
    }
    private function build(int $node, array $contents): void
    {
        $range = $this->shape->ranges[$node];
        if ($range->leaf()) {
            $this->values[$node] = $this->operation === Operation::GCD ? abs($contents[$range->left]) : $contents[$range->left];
        } else {
            $this->build(2 * $node, $contents);
            $this->build(2 * $node + 1, $contents);
            $this->pull($node);
        }
    }
    private function pull(int $node): void { $this->values[$node] = $this->operation->combine($this->values[2 * $node], $this->values[2 * $node + 1]); }
    public function root(): int { return $this->values[1]; }
    public function query(int $left, int $right, int $node = 1): ScalarAnswer
    {
        $range = $this->shape->ranges[$node];
        if ($range->covered($left, $right)) return new ScalarAnswer($this->values[$node], 1);
        if ($right <= $range->middle() || $left > $range->middle()) {
            $child = $this->query($left, $right, $right <= $range->middle() ? 2 * $node : 2 * $node + 1);
            return new ScalarAnswer($child->value, $child->visited + 1);
        }
        $a = $this->query($left, $right, 2 * $node);
        $b = $this->query($left, $right, 2 * $node + 1);
        return new ScalarAnswer($this->operation->combine($a->value, $b->value), $a->visited + $b->visited + 1);
    }
    public function update(int $index, int $value, int $node = 1): int
    {
        $range = $this->shape->ranges[$node];
        if ($range->leaf()) {
            $this->values[$node] = $this->operation === Operation::GCD ? abs($value) : $value;
            return 1;
        }
        $visited = $this->update($index, $value, $index <= $range->middle() ? 2 * $node : 2 * $node + 1);
        $this->pull($node);
        return $visited + 1;
    }
    public function describe(ScalarAnswer $answer): string { return strtolower($this->operation->value) . "={$answer->value} visited={$answer->visited}"; }
    public function dump(): array
    {
        $rows = ["SEG DUMP {$this->operation->value} nodes={$this->shape->count}"];
        foreach ($this->shape->nodes() as $node => $range) $rows[] = "NODE $node {$range->left} {$range->right} {$this->values[$node]}";
        return $rows;
    }
}

final readonly class Aggregate
{
    public function __construct(public int $sum, public int $min, public int $max) {}
    public static function merge(self $a, self $b): self { return new self($a->sum + $b->sum, min($a->min, $b->min), max($a->max, $b->max)); }
    public function __toString(): string { return "sum={$this->sum} min={$this->min} max={$this->max}"; }
}
final readonly class LazyAnswer
{
    public function __construct(public Aggregate $value, public int $visited, public int $pushes) {}
    public function __toString(): string { return "{$this->value} visited={$this->visited} pushes={$this->pushes}"; }
}
final class Work
{
    public int $visited = 0, $covered = 0, $pushes = 0;
    public function __toString(): string { return "visited={$this->visited} covered={$this->covered} pushes={$this->pushes}"; }
}

final class LazyTree
{
    public readonly Layout $shape;
    private array $values, $assign, $add;
    public function __construct(array $contents)
    {
        $this->shape = new Layout(count($contents));
        $this->values = $this->assign = array_fill(0, 4 * count($contents), null);
        $this->add = array_fill(0, 4 * count($contents), 0);
        $this->build(1, $contents);
    }
    private function build(int $node, array $contents): void
    {
        $range = $this->shape->ranges[$node];
        if ($range->leaf()) {
            $value = $contents[$range->left];
            $this->values[$node] = new Aggregate($value, $value, $value);
        } else {
            $this->build(2 * $node, $contents);
            $this->build(2 * $node + 1, $contents);
            $this->pull($node);
        }
    }
    private function pull(int $node): void { $this->values[$node] = Aggregate::merge($this->values[2 * $node], $this->values[2 * $node + 1]); }
    public function root(): Aggregate { return $this->values[1]; }
    private function apply(int $node, int $value, bool $assignment): void
    {
        $range = $this->shape->ranges[$node];
        $old = $this->values[$node];
        $this->values[$node] = $assignment ? new Aggregate($value * $range->length(), $value, $value)
            : new Aggregate($old->sum + $value * $range->length(), $old->min + $value, $old->max + $value);
        if ($range->leaf()) return;
        if ($assignment) { $this->assign[$node] = $value; $this->add[$node] = 0; }
        else $this->add[$node] += $value;
    }
    private function push(int $node): int
    {
        if ($this->assign[$node] === null && $this->add[$node] === 0) return 0;
        for ($child = 2 * $node; $child <= 2 * $node + 1; $child++) {
            if ($this->assign[$node] !== null) $this->apply($child, $this->assign[$node], true);
            if ($this->add[$node] !== 0) $this->apply($child, $this->add[$node], false);
        }
        $this->assign[$node] = null;
        $this->add[$node] = 0;
        return 1;
    }
    public function update(int $left, int $right, int $value, bool $assignment): Work
    {
        $work = new Work();
        $visit = function (int $node) use (&$visit, $left, $right, $value, $assignment, $work): void {
            $work->visited++;
            $range = $this->shape->ranges[$node];
            if ($range->covered($left, $right)) {
                $work->covered++;
                $this->apply($node, $value, $assignment);
                return;
            }
            $work->pushes += $this->push($node);
            if ($left <= $range->middle()) $visit(2 * $node);
            if ($right > $range->middle()) $visit(2 * $node + 1);
            $this->pull($node);
        };
        $visit(1);
        return $work;
    }
    public function query(int $left, int $right, int $node = 1): LazyAnswer
    {
        $range = $this->shape->ranges[$node];
        if ($range->covered($left, $right)) return new LazyAnswer($this->values[$node], 1, 0);
        $pushes = $this->push($node);
        if ($right <= $range->middle() || $left > $range->middle()) {
            $child = $this->query($left, $right, $right <= $range->middle() ? 2 * $node : 2 * $node + 1);
            return new LazyAnswer($child->value, $child->visited + 1, $child->pushes + $pushes);
        }
        $a = $this->query($left, $right, 2 * $node);
        $b = $this->query($left, $right, 2 * $node + 1);
        return new LazyAnswer(Aggregate::merge($a->value, $b->value), $a->visited + $b->visited + 1, $a->pushes + $b->pushes + $pushes);
    }
    public function dump(): array
    {
        $rows = ["LAZY DUMP nodes={$this->shape->count}"];
        foreach ($this->shape->nodes() as $node => $range) {
            $assignment = $this->assign[$node] ?? '-';
            $rows[] = "NODE $node {$range->left} {$range->right} {$this->values[$node]} assign=$assignment add={$this->add[$node]}";
        }
        return $rows;
    }
}

final class Fenwick
{
    public array $tree;
    public function __construct(public readonly int $n) { $this->tree = array_fill(0, $n + 1, 0); }
    public function add(int $position, int $value): int
    {
        $visited = 0;
        for (; $position <= $this->n; $position += $position & -$position) { $this->tree[$position] += $value; $visited++; }
        return $visited;
    }
    public function prefix(int $position): ScalarAnswer
    {
        $sum = $visited = 0;
        for (; $position > 0; $position -= $position & -$position) { $sum += $this->tree[$position]; $visited++; }
        return new ScalarAnswer($sum, $visited);
    }
    public function dump(string $name): string { return $name . ' ' . implode(' ', array_slice($this->tree, 1)); }
}

final class PointFenwick
{
    public array $contents;
    public readonly Fenwick $bits;
    public function __construct(array $contents)
    {
        $this->contents = $contents;
        $this->bits = new Fenwick(count($contents));
        foreach ($contents as $i => $value) $this->bits->add($i + 1, $value);
    }
    public function add(int $index, int $value): int { $this->contents[$index] += $value; return $this->bits->add($index + 1, $value); }
    public function query(int $left, int $right): ScalarAnswer
    {
        $a = $this->bits->prefix($right + 1);
        $b = $this->bits->prefix($left);
        return new ScalarAnswer($a->value - $b->value, $a->visited + $b->visited);
    }
    public function lower(int $rest): array
    {
        $position = $visited = 0;
        for ($step = 1 << floorLog2(count($this->contents)); $step >= 1; $step = intdiv($step, 2)) {
            if ($position + $step > count($this->contents)) continue;
            $visited++;
            $value = $this->bits->tree[$position + $step];
            if ($value < $rest) { $rest -= $value; $position += $step; }
        }
        return [$position === count($this->contents) ? null : $position, $visited];
    }
}

final class RangeFenwick
{
    public readonly Fenwick $b1, $b2;
    public function __construct(array $contents)
    {
        $this->b1 = new Fenwick(count($contents));
        $this->b2 = new Fenwick(count($contents));
        foreach ($contents as $i => $value) {
            $difference = $value - ($i === 0 ? 0 : $contents[$i - 1]);
            $this->b1->add($i + 1, $difference);
            $this->b2->add($i + 1, $i * $difference);
        }
    }
    public function add(int $left, int $right, int $value): int
    {
        $visited = $this->b1->add($left + 1, $value);
        $visited += $this->b1->add($right + 2, -$value);
        $visited += $this->b2->add($left + 1, $value * $left);
        $visited += $this->b2->add($right + 2, -$value * ($right + 1));
        return $visited;
    }
    private function prefix(int $position): ScalarAnswer
    {
        $a = $this->b1->prefix($position);
        $b = $this->b2->prefix($position);
        return new ScalarAnswer($position * $a->value - $b->value, $a->visited + $b->visited);
    }
    public function query(int $left, int $right): ScalarAnswer
    {
        $a = $this->prefix($right + 1);
        $b = $this->prefix($left);
        return new ScalarAnswer($a->value - $b->value, $a->visited + $b->visited);
    }
}

final readonly class SparseAnswer
{
    public function __construct(public int $min, public int $minPosition, public int $max, public int $maxPosition, public int $level) {}
    public function __toString(): string { return "min={$this->min} minpos={$this->minPosition} max={$this->max} maxpos={$this->maxPosition} level={$this->level}"; }
}

final class SparseTable
{
    private array $minimum, $maximum;
    public readonly int $levels, $entries;
    public function __construct(private readonly array $contents)
    {
        $n = count($contents);
        $this->levels = floorLog2($n) + 1;
        $this->minimum = $this->maximum = [range(0, $n - 1)];
        $entries = $n;
        for ($level = 1; $level < $this->levels; $level++) {
            $width = 1 << $level;
            $small = $large = [];
            for ($i = 0; $i + $width <= $n; $i++) {
                $small[] = $this->choose($this->minimum[$level - 1][$i], $this->minimum[$level - 1][$i + intdiv($width, 2)], true);
                $large[] = $this->choose($this->maximum[$level - 1][$i], $this->maximum[$level - 1][$i + intdiv($width, 2)], false);
            }
            $this->minimum[] = $small;
            $this->maximum[] = $large;
            $entries += count($small);
        }
        $this->entries = $entries;
    }
    private function choose(int $a, int $b, bool $minimum): int
    {
        return ($minimum ? $this->contents[$b] < $this->contents[$a] : $this->contents[$b] > $this->contents[$a]) ? $b : $a;
    }
    public function query(int $left, int $right): SparseAnswer
    {
        $level = floorLog2($right - $left + 1);
        $end = $right + 1 - (1 << $level);
        $small = $this->choose($this->minimum[$level][$left], $this->minimum[$level][$end], true);
        $large = $this->choose($this->maximum[$level][$left], $this->maximum[$level][$end], false);
        return new SparseAnswer($this->contents[$small], $small, $this->contents[$large], $large, $level);
    }
    public function dump(): array
    {
        $rows = ["SPARSE DUMP levels={$this->levels}"];
        for ($level = 0; $level < $this->levels; $level++) {
            $rows[] = "MIN $level " . implode(' ', $this->minimum[$level]);
            $rows[] = "MAX $level " . implode(' ', $this->maximum[$level]);
        }
        return $rows;
    }
}

final readonly class Partition
{
    public function __construct(public array $cells, public array $whole) {}
    public function __toString(): string { return 'whole=' . count($this->whole) . ' cells=' . count($this->cells); }
}
final readonly class SqrtAnswer
{
    public function __construct(public int $value, public Partition $partition) {}
    public function __toString(): string { return "sum={$this->value} {$this->partition}"; }
}

final class SqrtBlocks
{
    private array $raw, $tags, $sums;
    public readonly int $blocks;
    public function __construct(array $contents, public readonly int $block)
    {
        $this->raw = $contents;
        $this->blocks = intdiv(count($contents) + $block - 1, $block);
        $this->tags = $this->sums = array_fill(0, $this->blocks, 0);
        foreach ($contents as $i => $value) $this->sums[intdiv($i, $block)] += $value;
    }
    private function split(int $left, int $right): Partition
    {
        $first = intdiv($left, $this->block);
        $last = intdiv($right, $this->block);
        if ($first === $last) return new Partition(range($left, $right), []);
        $cells = array_merge(range($left, ($first + 1) * $this->block - 1), range($last * $this->block, $right));
        return new Partition($cells, $first + 1 < $last ? range($first + 1, $last - 1) : []);
    }
    public function add(int $left, int $right, int $value): Partition
    {
        $parts = $this->split($left, $right);
        foreach ($parts->cells as $i) { $this->raw[$i] += $value; $this->sums[intdiv($i, $this->block)] += $value; }
        foreach ($parts->whole as $block) { $this->tags[$block] += $value; $this->sums[$block] += $value * $this->block; }
        return $parts;
    }
    public function query(int $left, int $right): SqrtAnswer
    {
        $parts = $this->split($left, $right);
        $sum = 0;
        foreach ($parts->cells as $i) $sum += $this->raw[$i] + $this->tags[intdiv($i, $this->block)];
        foreach ($parts->whole as $block) $sum += $this->sums[$block];
        return new SqrtAnswer($sum, $parts);
    }
    public function dump(): array
    {
        $rows = ["SQRT DUMP block={$this->block} blocks={$this->blocks}"];
        for ($block = 0; $block < $this->blocks; $block++) {
            $first = $block * $this->block;
            $last = min(count($this->raw) - 1, $first + $this->block - 1);
            $rows[] = "BLOCK $block $first $last add={$this->tags[$block]} sum={$this->sums[$block]} " . implode(' ', array_slice($this->raw, $first, $last - $first + 1));
        }
        return $rows;
    }
}

final readonly class PersistentNode
{
    public function __construct(public int $value, public ?self $left = null, public ?self $right = null) {}
    public static function build(array $contents, int $left, int $right): self
    {
        if ($left === $right) return new self($contents[$left]);
        $middle = intdiv($left + $right, 2);
        $a = self::build($contents, $left, $middle);
        $b = self::build($contents, $middle + 1, $right);
        return new self($a->value + $b->value, $a, $b);
    }
    public function change(int $left, int $right, int $index, int $value, bool $increment): array
    {
        if ($left === $right) return [new self($increment ? $this->value + $value : $value), 1];
        $middle = intdiv($left + $right, 2);
        $a = $this->left;
        $b = $this->right;
        if ($index <= $middle) [$a, $created] = $a->change($left, $middle, $index, $value, $increment);
        else [$b, $created] = $b->change($middle + 1, $right, $index, $value, $increment);
        return [new self($a->value + $b->value, $a, $b), $created + 1];
    }
    public function query(int $start, int $end, int $left, int $right): ScalarAnswer
    {
        if ($left <= $start && $end <= $right) return new ScalarAnswer($this->value, 1);
        $middle = intdiv($start + $end, 2);
        if ($right <= $middle || $left > $middle) {
            $answer = $right <= $middle ? $this->left->query($start, $middle, $left, $right) : $this->right->query($middle + 1, $end, $left, $right);
            return new ScalarAnswer($answer->value, $answer->visited + 1);
        }
        $a = $this->left->query($start, $middle, $left, $right);
        $b = $this->right->query($middle + 1, $end, $left, $right);
        return new ScalarAnswer($a->value + $b->value, $a->visited + $b->visited + 1);
    }
}

final class PersistentTree
{
    private array $versions, $valueRoots, $values;
    public int $positionNodes, $valueNodes;
    public readonly int $n, $distinct;
    public function __construct(array $contents)
    {
        $this->n = count($contents);
        $this->versions = [PersistentNode::build($contents, 0, $this->n - 1)];
        $this->positionNodes = 2 * $this->n - 1;
        $sorted = $contents;
        sort($sorted, SORT_NUMERIC);
        $this->values = [];
        foreach ($sorted as $value) if ($this->values === [] || $this->values[count($this->values) - 1] !== $value) $this->values[] = $value;
        $this->distinct = count($this->values);
        $ranks = array_flip($this->values);
        $this->valueRoots = [PersistentNode::build(array_fill(0, $this->distinct, 0), 0, $this->distinct - 1)];
        $this->valueNodes = 2 * $this->distinct - 1;
        foreach ($contents as $i => $value) {
            [$root, $created] = $this->valueRoots[$i]->change(0, $this->distinct - 1, $ranks[$value], 1, true);
            $this->valueRoots[] = $root;
            $this->valueNodes += $created;
        }
    }
    public function versionCount(): int { return count($this->versions); }
    public function setValue(int $version, int $index, int $value): int
    {
        [$root, $created] = $this->versions[$version]->change(0, $this->n - 1, $index, $value, false);
        $this->versions[] = $root;
        $this->positionNodes += $created;
        return $created;
    }
    public function query(int $version, int $left, int $right): ScalarAnswer { return $this->versions[$version]->query(0, $this->n - 1, $left, $right); }
    public function kth(int $left, int $right, int $k): ScalarAnswer
    {
        $u = $this->valueRoots[$right + 1]; $w = $this->valueRoots[$left];
        $first = 0; $last = $this->distinct - 1; $visited = 1;
        while ($first < $last) {
            $middle = intdiv($first + $last, 2);
            $difference = $u->left->value - $w->left->value;
            if ($k <= $difference) { $u = $u->left; $w = $w->left; $last = $middle; }
            else { $k -= $difference; $u = $u->right; $w = $w->right; $first = $middle + 1; }
            $visited++;
        }
        return new ScalarAnswer($this->values[$first], $visited);
    }
}

final class GridFenwick
{
    private array $tree;
    public function __construct(public readonly int $height, public readonly int $width, array $contents)
    {
        $this->tree = array_fill(0, $height + 1, array_fill(0, $width + 1, 0));
        foreach ($contents as $index => $value) $this->add(intdiv($index, $width), $index % $width, $value);
    }
    public function add(int $row, int $column, int $value): int
    {
        $visited = 0;
        for ($y = $row + 1; $y <= $this->height; $y += $y & -$y)
            for ($z = $column + 1; $z <= $this->width; $z += $z & -$z) { $this->tree[$y][$z] += $value; $visited++; }
        return $visited;
    }
    private function prefix(int $row, int $column): ScalarAnswer
    {
        $sum = $visited = 0;
        for ($y = $row; $y > 0; $y -= $y & -$y)
            for ($z = $column; $z > 0; $z -= $z & -$z) { $sum += $this->tree[$y][$z]; $visited++; }
        return new ScalarAnswer($sum, $visited);
    }
    public function query(int $top, int $left, int $bottom, int $right): ScalarAnswer
    {
        $a = $this->prefix($bottom + 1, $right + 1);
        $b = $this->prefix($top, $right + 1);
        $c = $this->prefix($bottom + 1, $left);
        $d = $this->prefix($top, $left);
        return new ScalarAnswer($a->value - $b->value - $c->value + $d->value, $a->visited + $b->visited + $c->visited + $d->visited);
    }
    public function dump(): array
    {
        $rows = ["GRID DUMP rows={$this->height} cols={$this->width}"];
        for ($row = 1; $row <= $this->height; $row++) $rows[] = "ROW $row " . implode(' ', array_slice($this->tree[$row], 1));
        return $rows;
    }
}

final readonly class MoQuery
{
    public function __construct(public int $left, public int $right, public int $number) {}
}

final class Laboratory
{
    private array $a, $original;
    private ?SegmentTree $segment = null;
    private ?LazyTree $lazy = null;
    private ?PointFenwick $fenwick = null;
    private ?RangeFenwick $rangeFenwick = null;
    private ?SparseTable $sparse = null;
    private ?SqrtBlocks $sqrt = null;
    private ?PersistentTree $persistent = null;
    private ?GridFenwick $grid = null;
    public function __construct(array $contents) { $this->a = $this->original = $contents; }
    private function index(int $index): void
    {
        if ($index < 0 || $index >= count($this->a)) throw new CommandError("BAD INDEX $index");
    }
    private function range(int $left, int $right): void
    {
        $this->index($left); $this->index($right);
        if ($left > $right) throw new CommandError("BAD RANGE $left $right");
    }
    private function cell(int $row, int $column): void
    {
        if ($row < 0 || $row >= $this->grid->height || $column < 0 || $column >= $this->grid->width) throw new CommandError("BAD CELL $row $column");
    }
    private function version(int $version): void
    {
        if ($version < 0 || $version >= $this->persistent->versionCount()) throw new CommandError("BAD VERSION $version");
    }
    private function arrayCount(): int
    {
        return count(array_filter([$this->segment, $this->lazy, $this->fenwick, $this->rangeFenwick, $this->sparse, $this->sqrt, $this->persistent], static fn($tree) => $tree !== null));
    }
    private function updateArray(int $left, int $right, int $value, bool $assignment = false): void
    {
        for ($i = $left; $i <= $right; $i++) $this->a[$i] = $assignment ? $value : $this->a[$i] + $value;
    }
    private function reset(): array
    {
        $this->a = $this->original;
        if ($this->segment !== null) $this->segment = new SegmentTree($this->a, $this->segment->operation);
        if ($this->lazy !== null) $this->lazy = new LazyTree($this->a);
        if ($this->fenwick !== null) $this->fenwick = new PointFenwick($this->a);
        if ($this->rangeFenwick !== null) $this->rangeFenwick = new RangeFenwick($this->a);
        if ($this->sparse !== null) $this->sparse = new SparseTable($this->a);
        if ($this->sqrt !== null) $this->sqrt = new SqrtBlocks($this->a, $this->sqrt->block);
        if ($this->persistent !== null) $this->persistent = new PersistentTree($this->a);
        return ['RESET rebuilt=' . $this->arrayCount()];
    }
    private function build(string $kind, array $words): array
    {
        $n = count($this->a);
        switch ($kind) {
            case 'SEG':
                $operation = Operation::tryFrom($words[2]) ?? throw new CommandError("BAD OP {$words[2]}");
                $tree = new SegmentTree($this->a, $operation);
                $this->segment = $tree;
                return ["SEG BUILD {$operation->value} nodes={$tree->shape->count} maxnode={$tree->shape->maxNode} root=" . $tree->root()];
            case 'LAZY':
                $tree = new LazyTree($this->a); $this->lazy = $tree;
                return ["LAZY BUILD nodes={$tree->shape->count} " . $tree->root()];
            case 'FEN':
                $this->fenwick = new PointFenwick($this->a);
                return ["FEN BUILD n=$n total=" . array_sum($this->a)];
            case 'RFEN':
                $this->rangeFenwick = new RangeFenwick($this->a);
                return ["RFEN BUILD n=$n total=" . array_sum($this->a)];
            case 'SPARSE':
                $tree = new SparseTable($this->a); $this->sparse = $tree;
                return ["SPARSE BUILD levels={$tree->levels} entries={$tree->entries}"];
            case 'SQRT':
                $block = isset($words[2]) ? (int)$words[2] : integerSqrt($n);
                if ($block > $n) throw new CommandError("BAD BLOCK $block");
                $tree = new SqrtBlocks($this->a, $block); $this->sqrt = $tree;
                return ["SQRT BUILD block=$block blocks={$tree->blocks}"];
            case 'PERSIST':
                $tree = new PersistentTree($this->a); $this->persistent = $tree;
                return ["PERSIST BUILD nodes={$tree->positionNodes} distinct={$tree->distinct} valuenodes={$tree->valueNodes}"];
            case 'GRID':
                $height = (int)$words[2]; $width = (int)$words[3];
                $values = array_map('intval', array_slice($words, 4));
                $count = count($values); $expected = $height * $width;
                if ($count !== $expected) throw new CommandError("BAD COUNT $count $expected");
                $this->grid = new GridFenwick($height, $width, $values);
                return ["GRID BUILD rows=$height cols=$width total=" . array_sum($values)];
        }
        throw new LogicException('Unknown structure');
    }
    private function check(int $left, int $right): array
    {
        $this->range($left, $right);
        $sum = $gcd = 0; $min = $max = $this->a[$left];
        for ($i = $left; $i <= $right; $i++) {
            $sum += $this->a[$i]; $min = min($min, $this->a[$i]); $max = max($max, $this->a[$i]); $gcd = gcd($gcd, $this->a[$i]);
        }
        $rows = ["CHECK $left $right sum=$sum min=$min max=$max gcd=$gcd"];
        $ok = $diff = 0;
        $append = static function (string $kind, bool $same, string $items) use (&$rows, &$ok, &$diff): void {
            if ($same) $ok++; else $diff++;
            $rows[] = "$kind " . ($same ? 'OK' : 'DIFF') . " $items";
        };
        if ($this->segment !== null) {
            $answer = $this->segment->query($left, $right);
            $expected = match ($this->segment->operation) { Operation::SUM => $sum, Operation::MIN => $min, Operation::MAX => $max, Operation::GCD => $gcd };
            $append('SEG', $answer->value === $expected, $this->segment->describe($answer));
        }
        if ($this->lazy !== null) {
            $answer = $this->lazy->query($left, $right);
            $append('LAZY', $answer->value->sum === $sum && $answer->value->min === $min && $answer->value->max === $max, (string)$answer);
        }
        if ($this->fenwick !== null) {
            $answer = $this->fenwick->query($left, $right); $append('FEN', $answer->value === $sum, (string)$answer);
        }
        if ($this->rangeFenwick !== null) {
            $answer = $this->rangeFenwick->query($left, $right); $append('RFEN', $answer->value === $sum, (string)$answer);
        }
        if ($this->sparse !== null) {
            $answer = $this->sparse->query($left, $right); $append('SPARSE', $answer->min === $min && $answer->max === $max, (string)$answer);
        }
        if ($this->sqrt !== null) {
            $answer = $this->sqrt->query($left, $right); $append('SQRT', $answer->value === $sum, (string)$answer);
        }
        if ($this->persistent !== null) {
            $version = $this->persistent->versionCount() - 1;
            $answer = $this->persistent->query($version, $left, $right); $append('PERSIST', $answer->value === $sum, "version=$version $answer");
        }
        $rows[] = "RESULT ok=$ok diff=$diff";
        return $rows;
    }
    private function mo(array $words): array
    {
        $queries = [];
        for ($i = 1; $i < count($words); $i += 2) {
            $left = (int)$words[$i]; $right = (int)$words[$i + 1];
            $this->range($left, $right);
            $queries[] = new MoQuery($left, $right, count($queries) + 1);
        }
        $block = integerSqrt(count($this->a));
        $ordered = $queries;
        usort($ordered, static function (MoQuery $a, MoQuery $b) use ($block): int {
            $first = intdiv($a->left, $block); $second = intdiv($b->left, $block);
            return ($first <=> $second) ?: (($first % 2 === 0 ? $a->right <=> $b->right : $b->right <=> $a->right) ?: $a->number <=> $b->number);
        });
        $frequency = $answers = []; $distinct = $moves = $left = 0; $right = -1;
        $add = function (int $index) use (&$frequency, &$distinct, &$moves): void {
            $value = $this->a[$index];
            $old = $frequency[$value] ?? 0;
            if ($old === 0) $distinct++;
            $frequency[$value] = $old + 1; $moves++;
        };
        $remove = function (int $index) use (&$frequency, &$distinct, &$moves): void {
            $value = $this->a[$index];
            if (--$frequency[$value] === 0) $distinct--;
            $moves++;
        };
        foreach ($ordered as $query) {
            while ($left > $query->left) $add(--$left);
            while ($right < $query->right) $add(++$right);
            while ($left < $query->left) $remove($left++);
            while ($right > $query->right) $remove($right--);
            $answers[$query->number] = $distinct;
        }
        $rows = ['MO queries=' . count($queries) . " block=$block moves=$moves", 'ORDER ' . implode(' ', array_map(static fn(MoQuery $q) => $q->number, $ordered))];
        foreach ($queries as $query) $rows[] = "ANSWER {$query->number} {$query->left} {$query->right} distinct={$answers[$query->number]}";
        return $rows;
    }
    public function execute(array $words): array
    {
        $kind = $words[0];
        if ($kind === 'LOAD') {
            $removed = $this->arrayCount();
            $this->a = $this->original = array_map('intval', array_slice($words, 1));
            $this->segment = $this->lazy = $this->fenwick = $this->rangeFenwick = $this->sparse = $this->sqrt = $this->persistent = null;
            return ['LOAD n=' . count($this->a) . " removed=$removed"];
        }
        if ($kind === 'RESET') return $this->reset();
        if ($kind === 'MO') return $this->mo($words);
        if ($kind === 'CHECK') return $this->check((int)$words[1], (int)$words[2]);
        if ($kind === 'ARRAY') {
            $left = (int)$words[1]; $right = (int)$words[2]; $this->range($left, $right);
            return ["ARRAY $left $right " . implode(' ', array_slice($this->a, $left, $right - $left + 1))];
        }
        $action = $words[1];
        if ($action === 'BUILD') return $this->build($kind, $words);
        $tree = match ($kind) {
            'SEG' => $this->segment, 'LAZY' => $this->lazy, 'FEN' => $this->fenwick, 'RFEN' => $this->rangeFenwick,
            'SPARSE' => $this->sparse, 'SQRT' => $this->sqrt, 'PERSIST' => $this->persistent, 'GRID' => $this->grid
        };
        if ($tree === null) throw new CommandError("NOT BUILT $kind");
        $n = count($this->a);
        if ($action === 'DUMP') {
            if ($kind === 'FEN') return ["FEN DUMP n=$n", $tree->bits->dump('T')];
            if ($kind === 'RFEN') return ["RFEN DUMP n=$n", $tree->b1->dump('B1'), $tree->b2->dump('B2')];
            return $tree->dump();
        }
        if ($kind === 'PERSIST') {
            if ($action === 'NODES') return ['PERSIST NODES versions=' . $tree->versionCount() . " position={$tree->positionNodes} value={$tree->valueNodes}"];
            if ($action === 'KTH') {
                $left = (int)$words[2]; $right = (int)$words[3]; $k = (int)$words[4]; $this->range($left, $right);
                if ($k < 1 || $k > $right - $left + 1) throw new CommandError("BAD K $k");
                $answer = $tree->kth($left, $right, $k);
                return ["PERSIST KTH $left $right $k value={$answer->value} visited={$answer->visited}"];
            }
            $version = (int)$words[2]; $this->version($version);
            $index = (int)$words[3];
            if ($action === 'SET') {
                $this->index($index); $value = (int)$words[4]; $newVersion = $tree->versionCount();
                $created = $tree->setValue($version, $index, $value);
                return ["PERSIST SET $version $index $value version=$newVersion created=$created"];
            }
            $right = (int)$words[4]; $this->range($index, $right);
            return ["PERSIST QUERY $version $index $right " . $tree->query($version, $index, $right)];
        }
        if ($kind === 'GRID') {
            $row = (int)$words[2]; $column = (int)$words[3]; $this->cell($row, $column);
            if ($action === 'ADD') {
                $value = (int)$words[4]; $visited = $tree->add($row, $column, $value);
                return ["GRID ADD $row $column $value visited=$visited"];
            }
            $bottom = (int)$words[4]; $right = (int)$words[5]; $this->cell($bottom, $right);
            if ($row > $bottom || $column > $right) throw new CommandError("BAD RECT $row $column $bottom $right");
            return ["GRID SUM $row $column $bottom $right " . $tree->query($row, $column, $bottom, $right)];
        }
        if ($kind === 'FEN' && $action === 'LOWER') {
            foreach ($tree->contents as $i => $value) if ($value < 0) throw new CommandError("NEGATIVE $i");
            $k = (int)$words[2]; [$index, $visited] = $tree->lower($k); $text = $index ?? 'none';
            return ["FEN LOWER $k index=$text visited=$visited"];
        }
        $left = (int)$words[2];
        if ($kind === 'SEG' && $action === 'UPDATE') {
            $this->index($left); $value = (int)$words[3]; $visited = $tree->update($left, $value); $this->a[$left] = $value;
            return ["SEG UPDATE $left $value root=" . $tree->root() . " visited=$visited"];
        }
        if ($kind === 'FEN' && ($action === 'ADD' || $action === 'PREFIX')) {
            $this->index($left);
            if ($action === 'PREFIX') return ["FEN PREFIX $left " . $tree->bits->prefix($left + 1)];
            $value = (int)$words[3]; $visited = $tree->add($left, $value); $this->a[$left] += $value;
            return ["FEN ADD $left $value visited=$visited"];
        }
        $right = (int)$words[3]; $this->range($left, $right);
        if ($action === 'ADD' || $action === 'ASSIGN') {
            $value = (int)$words[4];
            if ($kind === 'LAZY') $items = (string)$tree->update($left, $right, $value, $action === 'ASSIGN');
            elseif ($kind === 'RFEN') $items = 'visited=' . $tree->add($left, $right, $value);
            else $items = (string)$tree->add($left, $right, $value);
            $this->updateArray($left, $right, $value, $action === 'ASSIGN');
            return ["$kind $action $left $right $value $items"];
        }
        $answer = $tree->query($left, $right);
        $items = $kind === 'SEG' ? $tree->describe($answer) : (string)$answer;
        return ["$kind $action $left $right $items"];
    }
}

$first = fgets(STDIN);
if ($first === false) exit;
$contents = array_map('intval', explode(' ', trim(fgets(STDIN))));
$laboratory = new Laboratory($contents);
$commands = (int)trim(fgets(STDIN));
for ($command = 0; $command < $commands; $command++) {
    $words = explode(' ', trim(fgets(STDIN)));
    try { echo implode("\n", $laboratory->execute($words)), "\n"; }
    catch (CommandError $error) { echo 'ERROR ', $error->getMessage(), "\n"; }
    flush();
}
