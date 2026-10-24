<?php

declare(strict_types=1);

const METHODS = [
    'NEXTFIT', 'FIRSTFIT', 'BESTFIT', 'WORSTFIT', 'ALMOSTWORST',
    'HARMONIC', 'KBOUNDED', 'FFD', 'BFD', 'WFD',
];
const PARAMETERIZED = ['HARMONIC', 'KBOUNDED'];

final class CommandError extends RuntimeException {}

function fail(string $reason): never
{
    throw new CommandError($reason);
}

function ceiling(int $number, int $denominator): int
{
    return intdiv($number + $denominator - 1, $denominator);
}

function itemText(array $item): string
{
    return $item[0] . ':' . $item[1];
}

function descending(array $items): array
{
    usort($items, static function (array $a, array $b): int {
        return ($b[1] <=> $a[1]) ?: ($a[0] <=> $b[0]);
    });
    return $items;
}

final class Bin
{
    public array $items = [];
    public int $load = 0;

    public function __construct(public ?int $category = null) {}

    public function put(array $item): void
    {
        $this->items[] = $item;
        $this->load += $item[1];
    }

    public function duplicate(): self
    {
        $copy = new self($this->category);
        $copy->items = $this->items;
        $copy->load = $this->load;
        return $copy;
    }
}

final class Packing
{
    public array $bins = [];
    public array $steps = [];
    public int $inspections = 0;
    public int $closes = 0;

    public function __construct(
        public string $method,
        public int $parameter
    ) {}

    public function name(): string
    {
        return $this->method . (in_array($this->method, PARAMETERIZED, true)
            ? ' k=' . $this->parameter : '');
    }

    public function header(int $capacity, int $total): string
    {
        $header = $this->name() .
            ' bins=' . count($this->bins) .
            ' inspections=' . $this->inspections .
            ' waste=' . (count($this->bins) * $capacity - $total);
        if ($this->method === 'KBOUNDED') {
            $header .= ' closes=' . $this->closes;
        }
        return $header;
    }
}

function pack(array $items, int $capacity, string $method, int $parameter = 0): Packing
{
    $result = new Packing($method, $parameter);
    $order = in_array($method, ['FFD', 'BFD', 'WFD'], true)
        ? descending($items) : $items;
    $active = [];
    $current = [];
    foreach ($order as $item) {
        $size = $item[1];
        $previous = $result->inspections;
        $chosen = null;
        $closed = null;
        $category = null;

        if ($method === 'NEXTFIT') {
            if ($result->bins) {
                ++$result->inspections;
                $last = count($result->bins) - 1;
                if ($result->bins[$last]->load + $size <= $capacity) {
                    $chosen = $last;
                }
            }
        } elseif (in_array($method, ['FIRSTFIT', 'FFD', 'KBOUNDED'], true)) {
            $candidates = $method === 'KBOUNDED'
                ? $active : array_keys($result->bins);
            foreach ($candidates as $index) {
                ++$result->inspections;
                if ($result->bins[$index]->load + $size <= $capacity) {
                    $chosen = $index;
                    break;
                }
            }
        } elseif ($method === 'HARMONIC') {
            $category = min(intdiv($capacity, $size), $parameter);
            if (isset($current[$category])) {
                ++$result->inspections;
                $index = $current[$category];
                if ($result->bins[$index]->load + $size <= $capacity) {
                    $chosen = $index;
                }
            }
        } else {
            $result->inspections += count($result->bins);
            $fitting = [];
            foreach ($result->bins as $index => $bin) {
                if ($bin->load + $size <= $capacity) $fitting[] = $index;
            }
            if ($fitting) {
                if (in_array($method, ['BESTFIT', 'BFD'], true)) {
                    $chosen = $fitting[0];
                    foreach (array_slice($fitting, 1) as $index) {
                        if ($result->bins[$index]->load > $result->bins[$chosen]->load) {
                            $chosen = $index;
                        }
                    }
                } else {
                    usort($fitting, static function (int $a, int $b) use ($result): int {
                        return ($result->bins[$a]->load <=> $result->bins[$b]->load)
                            ?: ($a <=> $b);
                    });
                    $chosen = ($method === 'ALMOSTWORST' && count($fitting) >= 2)
                        ? $fitting[1] : $fitting[0];
                }
            }
        }

        $opened = $chosen === null;
        if ($opened) {
            if ($method === 'KBOUNDED' && count($active) === $parameter) {
                $closed = $active[0];
                foreach (array_slice($active, 1) as $index) {
                    if ($result->bins[$index]->load > $result->bins[$closed]->load) {
                        $closed = $index;
                    }
                }
                array_splice($active, array_search($closed, $active, true), 1);
                ++$result->closes;
            }
            $chosen = count($result->bins);
            $result->bins[] = new Bin($category);
            if ($method === 'KBOUNDED') {
                $active[] = $chosen;
            } elseif ($method === 'HARMONIC') {
                $current[$category] = $chosen;
            }
        }
        $result->bins[$chosen]->put($item);
        $result->steps[] = [
            $item, $chosen, $result->inspections - $previous,
            $opened, $closed, $category,
        ];
    }
    return $result;
}

function lowerBounds(array $items, int $capacity): array
{
    $total = array_sum(array_column($items, 1));
    $thresholds = [0 => true];
    foreach ($items as $item) {
        if ($item[1] * 2 <= $capacity) $thresholds[$item[1]] = true;
    }
    $values = array_keys($thresholds);
    sort($values, SORT_NUMERIC);
    $rows = [];
    $lower = 0;
    foreach ($values as $alpha) {
        $j1 = $j2 = $j3 = $sum2 = $sum3 = 0;
        foreach ($items as $item) {
            $size = $item[1];
            if ($size > $capacity - $alpha) {
                ++$j1;
            } elseif (2 * $size > $capacity) {
                ++$j2;
                $sum2 += $size;
            } elseif ($size >= $alpha) {
                ++$j3;
                $sum3 += $size;
            }
        }
        $excess = $sum3 - ($j2 * $capacity - $sum2);
        $bound = $j1 + $j2 + ($excess > 0 ? ceiling($excess, $capacity) : 0);
        $rows[] = [$alpha, $j1, $j2, $j3, $bound];
        $lower = max($lower, $bound);
    }
    return [ceiling($total, $capacity), $lower, $rows];
}

final class ExactSearch
{
    public array $best;
    public array $live = [];
    public array $events = [];
    public int $nodes = 0;
    public ?string $status = null;
    private array $items;
    private array $remaining;

    public function __construct(
        array $items,
        private int $capacity,
        private int $limit,
        private int $lower,
        array $incumbent
    ) {
        $this->items = descending($items);
        $this->best = array_map(static fn(Bin $bin): Bin => $bin->duplicate(), $incumbent);
        $n = count($this->items);
        $this->remaining = array_fill(0, $n + 1, 0);
        for ($i = $n - 1; $i >= 0; --$i) {
            $this->remaining[$i] = $this->remaining[$i + 1] + $this->items[$i][1];
        }
    }

    public function visit(int $index): void
    {
        if ($this->nodes === $this->limit) {
            $this->status = 'limit';
            return;
        }
        ++$this->nodes;
        $count = count($this->live);
        $used = $this->remaining[0] - $this->remaining[$index];
        $free = $count * $this->capacity - $used;
        $excess = $this->remaining[$index] - $free;
        $minimum = $count + ($excess > 0 ? ceiling($excess, $this->capacity) : 0);
        if ($minimum >= count($this->best)) return;

        if ($index === count($this->items)) {
            $this->best = array_map(
                static fn(Bin $bin): Bin => $bin->duplicate(), $this->live
            );
            $this->events[] = 'IMPROVE bins=' . $count . ' nodes=' . $this->nodes;
            if ($count === $this->lower) $this->status = 'bound';
            return;
        }

        $item = $this->items[$index];
        $seenLoads = [];
        foreach ($this->live as $bin) {
            $load = $bin->load;
            if (isset($seenLoads[$load])) continue;
            $seenLoads[$load] = true;
            if ($load + $item[1] > $this->capacity) continue;
            $bin->put($item);
            $this->visit($index + 1);
            array_pop($bin->items);
            $bin->load = $load;
            if ($this->status !== null) return;
        }
        if ($count + 1 < count($this->best)) {
            $bin = new Bin();
            $bin->put($item);
            $this->live[] = $bin;
            $this->visit($index + 1);
            array_pop($this->live);
        }
    }
}

final class PackingLab
{
    private ?array $items = null;
    private int $capacity = 0;
    private array $output = [];

    private function emit(string $line): void
    {
        $this->output[] = $line;
    }

    private function total(): int
    {
        return array_sum(array_column($this->items, 1));
    }

    private function binLine(int $number, Bin $bin, int $capacity,
                             bool $classes = false, bool $over = false): void
    {
        $text = 'BIN ' . $number . ' load=' . $bin->load . '/' . $capacity .
                ' items=' . implode(' ', array_map('itemText', $bin->items));
        if ($classes) $text .= ' class=' . $bin->category;
        if ($over) $text .= ' OVER';
        $this->emit($text);
    }

    private function binLines(array $bins, bool $classes = false): void
    {
        foreach ($bins as $index => $bin) {
            $this->binLine($index + 1, $bin, $this->capacity, $classes);
        }
    }

    private function method(string $method, array $args): Packing
    {
        $parameter = in_array($method, PARAMETERIZED, true) ? (int) $args[0] : 0;
        if (in_array($method, PARAMETERIZED, true) && $parameter === 0) {
            fail('BAD PARAMETER');
        }
        return pack($this->items, $this->capacity, $method, $parameter);
    }

    private function cmdItems(array $args): void
    {
        $capacity = (int) array_shift($args);
        if ($capacity === 0) fail('BAD CAPACITY');
        $items = [];
        foreach ($args as $index => $text) {
            $size = (int) $text;
            if ($size === 0 || $size > $capacity) fail('BAD ITEM ' . ($index + 1));
            $items[] = [$index + 1, $size];
        }
        $this->items = $items;
        $this->capacity = $capacity;
        $this->emit('ITEMS count=' . count($items) . ' capacity=' . $capacity .
                    ' total=' . $this->total());
    }

    private function cmdRandom(array $args): void
    {
        [$count, $capacity, $seed] = array_map('intval', $args);
        if ($count === 0 || $count > 40) fail('BAD COUNT');
        if ($capacity === 0) fail('BAD CAPACITY');
        if ($seed === 0 || $seed >= 2147483647) fail('BAD SEED');
        $items = [];
        $sizes = [];
        for ($number = 1; $number <= $count; ++$number) {
            $seed = (48271 * $seed) % 2147483647;
            $size = $seed % $capacity + 1;
            $items[] = [$number, $size];
            $sizes[] = $size;
        }
        $this->capacity = $capacity;
        $this->items = $items;
        $this->emit('RANDOM count=' . $count . ' capacity=' . $capacity .
                    ' total=' . $this->total());
        $this->emit('SIZES ' . implode(' ', $sizes));
    }

    private function showMethod(string $method, array $args): void
    {
        $result = $this->method($method, $args);
        $this->emit($result->header($this->capacity, $this->total()));
        $this->binLines($result->bins, $method === 'HARMONIC');
    }

    private function cmdTrace(array $args): void
    {
        $method = array_shift($args);
        $result = $this->method($method, $args);
        $this->emit('TRACE ' . $result->header($this->capacity, $this->total()));
        foreach ($result->steps as $index => $step) {
            [$item, $bin, $inspected, $opened, $closed, $category] = $step;
            $line = 'STEP ' . ($index + 1) . ' item=' . itemText($item) .
                    ' bin=' . ($bin + 1) . ' inspected=' . $inspected;
            if ($opened) $line .= ' new';
            if ($closed !== null) $line .= ' closed=' . ($closed + 1);
            if ($category !== null) $line .= ' class=' . $category;
            $this->emit($line);
        }
    }

    private function cmdReduce(array $args): void
    {
        $method = array_shift($args);
        $result = $this->method($method, $args);
        $bins = $result->bins;
        $before = count($bins);
        $events = [];
        while (true) {
            $eliminated = false;
            $sources = array_keys($bins);
            usort($sources, static function (int $a, int $b) use (&$bins): int {
                return ($bins[$a]->load <=> $bins[$b]->load) ?: ($a <=> $b);
            });
            foreach ($sources as $source) {
                $loads = array_map(static fn(Bin $bin): int => $bin->load, $bins);
                $moves = [];
                $success = true;
                foreach (descending($bins[$source]->items) as $item) {
                    $destination = null;
                    foreach ($bins as $index => $bin) {
                        if ($index === $source || $loads[$index] + $item[1] > $this->capacity) {
                            continue;
                        }
                        if ($destination === null || $loads[$index] > $loads[$destination]) {
                            $destination = $index;
                        }
                    }
                    if ($destination === null) {
                        $success = false;
                        break;
                    }
                    $loads[$destination] += $item[1];
                    $moves[] = [$item, $destination];
                }
                if ($success) {
                    $descriptions = [];
                    foreach ($moves as [$item, $destination]) {
                        $descriptions[] = itemText($item) . '->' . ($destination + 1);
                        $bins[$destination]->put($item);
                    }
                    $events[] = 'ELIMINATE bin=' . ($source + 1) .
                                ' load=' . $bins[$source]->load .
                                ' moves=' . implode(' ', $descriptions);
                    array_splice($bins, $source, 1);
                    $eliminated = true;
                    break;
                }
            }
            if (!$eliminated) break;
        }
        $this->emit('REDUCE ' . $result->name() . ' before=' . $before .
                    ' after=' . count($bins) . ' eliminated=' . ($before - count($bins)));
        foreach ($events as $event) $this->emit($event);
        $this->binLines($bins, $method === 'HARMONIC');
    }

    private function cmdBounds(): void
    {
        [$l1, $l2, $rows] = lowerBounds($this->items, $this->capacity);
        $this->emit('BOUNDS total=' . $this->total() . ' L1=' . $l1 . ' L2=' . $l2);
        foreach ($rows as [$alpha, $j1, $j2, $j3, $bound]) {
            $this->emit('ALPHA ' . $alpha . ' j1=' . $j1 . ' j2=' . $j2 .
                        ' j3=' . $j3 . ' bound=' . $bound);
        }
    }

    private function cmdCompare(array $args): void
    {
        $parameter = (int) $args[0];
        if ($parameter === 0) fail('BAD PARAMETER');
        [$l1, $l2] = lowerBounds($this->items, $this->capacity);
        $results = array_map(
            fn(string $method): Packing => pack($this->items, $this->capacity, $method, $parameter),
            METHODS
        );
        usort($results, static function (Packing $a, Packing $b): int {
            return (count($a->bins) <=> count($b->bins)) ?: strcmp($a->method, $b->method);
        });
        $this->emit('COMPARE k=' . $parameter . ' L1=' . $l1 . ' L2=' . $l2);
        foreach ($results as $result) {
            $count = count($result->bins);
            $this->emit($result->method . ' bins=' . $count . ' gap=' . ($count - $l2) .
                        ' waste=' . ($count * $this->capacity - $this->total()) .
                        ' inspections=' . $result->inspections);
        }
    }

    private function cmdExact(array $args): void
    {
        $limit = (int) $args[0];
        if ($limit === 0) fail('BAD PARAMETER');
        if (count($this->items) >= 21) fail('TOO MANY ITEMS');
        $incumbent = pack($this->items, $this->capacity, 'FFD')->bins;
        [, $lower] = lowerBounds($this->items, $this->capacity);
        $this->emit('EXACT ffd=' . count($incumbent) . ' L2=' . $lower);
        $search = new ExactSearch($this->items, $this->capacity, $limit, $lower, $incumbent);
        if (count($incumbent) === $lower) {
            $search->status = 'bound';
        } else {
            $search->visit(0);
        }
        foreach ($search->events as $event) $this->emit($event);
        $this->emit('RESULT bins=' . count($search->best) .
                    ' nodes=' . $search->nodes .
                    ' status=' . ($search->status ?? 'complete'));
        $this->binLines($search->best);
    }

    private function cmdCheck(array $args): void
    {
        $labels = array_map('intval', $args);
        if (count($labels) !== count($this->items) || in_array(0, $labels, true)) {
            fail('BAD ASSIGNMENT');
        }
        $bins = [];
        foreach ($this->items as $index => $item) {
            $label = $labels[$index];
            if (!isset($bins[$label])) $bins[$label] = new Bin();
            $bins[$label]->put($item);
        }
        $over = 0;
        foreach ($bins as $bin) $over += (int) ($bin->load > $this->capacity);
        [, $lower] = lowerBounds($this->items, $this->capacity);
        $this->emit('CHECK bins=' . count($bins) . ' over=' . $over .
                    ' L2=' . $lower . ' status=' . ($over ? 'invalid' : 'valid'));
        ksort($bins, SORT_NUMERIC);
        foreach ($bins as $label => $bin) {
            $this->binLine($label, $bin, $this->capacity, false,
                           $bin->load > $this->capacity);
        }
    }

    private function coverLines(string $name, array $bins): void
    {
        $covered = [];
        $rest = null;
        foreach ($bins as $bin) {
            if ($bin->load >= $this->capacity) $covered[] = $bin;
            else $rest = $bin;
        }
        $this->emit($name . ' covered=' . count($covered) .
                    ' rest=' . ($rest === null ? 0 : $rest->load));
        $this->binLines($covered);
        if ($rest !== null) {
            $this->emit('REST items=' . implode(' ', array_map('itemText', $rest->items)));
        }
    }

    private function cmdCover(): void
    {
        $this->emit('COVER total=' . $this->total() .
                    ' upper=' . intdiv($this->total(), $this->capacity));
        $sequential = [];
        foreach ($this->items as $item) {
            if (!$sequential || end($sequential)->load >= $this->capacity) {
                $sequential[] = new Bin();
            }
            $sequential[count($sequential) - 1]->put($item);
        }
        $this->coverLines('DNF', $sequential);

        $available = descending($this->items);
        $paired = [];
        while ($available) {
            $bin = new Bin();
            $bin->put(array_shift($available));
            while ($bin->load < $this->capacity && $available) {
                $bin->put(array_pop($available));
            }
            $paired[] = $bin;
        }
        $this->coverLines('BIGSMALL', $paired);
    }

    private function machineLines(array $machines): void
    {
        foreach ($machines as $index => $bin) {
            $items = implode(' ', array_map('itemText', $bin->items));
            $this->emit('MACHINE ' . ($index + 1) . ' load=' . $bin->load .
                        ' items=' . ($items === '' ? '-' : $items));
        }
    }

    private function cmdMultifit(array $args): void
    {
        $count = (int) $args[0];
        if ($count === 0) fail('BAD PARAMETER');
        $total = $this->total();
        $largest = max(array_column($this->items, 1));
        $low = max(ceiling($total, $count), $largest);
        $high = max(ceiling(2 * $total, $count), $largest);
        $this->emit('MULTIFIT m=' . $count . ' lower=' . $low . ' upper=' . $high);
        while ($low < $high) {
            $middle = intdiv($low + $high, 2);
            $bins = count(pack($this->items, $middle, 'FFD')->bins);
            $success = $bins <= $count;
            $this->emit('TRY cap=' . $middle . ' bins=' . $bins .
                        ($success ? ' ok' : ' fail'));
            if ($success) $high = $middle;
            else $low = $middle + 1;
        }
        $machines = pack($this->items, $high, 'FFD')->bins;
        while (count($machines) < $count) $machines[] = new Bin();
        $makespan = max(array_map(static fn(Bin $bin): int => $bin->load, $machines));
        $this->emit('RESULT cap=' . $high . ' makespan=' . $makespan);
        $this->machineLines($machines);

        $lpt = array_fill(0, $count, null);
        for ($i = 0; $i < $count; ++$i) $lpt[$i] = new Bin();
        foreach (descending($this->items) as $item) {
            $chosen = 0;
            for ($i = 1; $i < $count; ++$i) {
                if ($lpt[$i]->load < $lpt[$chosen]->load) $chosen = $i;
            }
            $lpt[$chosen]->put($item);
        }
        $makespan = max(array_map(static fn(Bin $bin): int => $bin->load, $lpt));
        $this->emit('LPT makespan=' . $makespan);
        $this->machineLines($lpt);
    }

    private function maximalPatterns(int $length, array $pieces): array
    {
        $patterns = [];
        $enumerate = function (int $index, int $remaining, array $prefix)
            use (&$enumerate, &$patterns, $pieces): void {
            $size = $pieces[$index][0];
            $maximum = intdiv($remaining, $size);
            if ($index === count($pieces) - 1) {
                $patterns[] = [
                    array_merge($prefix, [$maximum]),
                    $remaining - $maximum * $size,
                ];
                return;
            }
            for ($count = $maximum; $count >= 0; --$count) {
                $enumerate($index + 1, $remaining - $count * $size,
                           array_merge($prefix, [$count]));
            }
        };
        $enumerate(0, $length, []);
        return $patterns;
    }

    private function cmdCutstock(array $args): void
    {
        $length = (int) array_shift($args);
        if ($length === 0) fail('BAD CAPACITY');
        $pieces = [];
        $seen = [];
        foreach ($args as $index => $token) {
            [$size, $demand] = array_map('intval', explode(':', $token));
            if ($size === 0 || $size > $length || $demand === 0)
                fail('BAD PIECE ' . ($index + 1));
            if (isset($seen[$size])) fail('DUPLICATE PIECE ' . ($index + 1));
            $seen[$size] = true;
            $pieces[] = [$size, $demand];
        }
        usort($pieces, static fn(array $a, array $b): int => $b[0] <=> $a[0]);

        $patterns = $this->maximalPatterns($length, $pieces);
        $remaining = array_column($pieces, 1);
        $uses = array_fill(0, count($patterns), 0);
        while (array_sum($remaining) > 0) {
            $best = -1;
            $chosen = null;
            foreach ($patterns as $index => [$counts, $trim]) {
                $useful = 0;
                foreach ($counts as $i => $count) {
                    $useful += min($count, $remaining[$i]);
                }
                if ($useful > $best) {
                    $best = $useful;
                    $chosen = $index;
                }
            }
            ++$uses[$chosen];
            foreach ($patterns[$chosen][0] as $i => $count)
                $remaining[$i] = max(0, $remaining[$i] - $count);
        }

        $cut = array_fill(0, count($pieces), 0);
        $quantity = 0;
        $demanded = 0;
        foreach ($pieces as [$size, $demand]) {
            $quantity += $size * $demand;
            $demanded += $demand;
        }
        $trim = 0;
        foreach ($patterns as $index => [$counts, $rest]) {
            $trim += $uses[$index] * $rest;
            foreach ($counts as $i => $count) {
                $cut[$i] += $uses[$index] * $count;
            }
        }
        $bars = array_sum($uses);
        $this->emit('CUTSTOCK L=' . $length .
                    ' pieces=' . count($pieces) .
                    ' patterns=' . count($patterns));
        foreach ($patterns as $index => [$counts, $rest]) {
            $description = [];
            foreach ($counts as $i => $count) {
                if ($count > 0) {
                    $description[] = $count . 'x' . $pieces[$i][0];
                }
            }
            $this->emit('PATTERN ' . ($index + 1) . ' ' .
                        implode('+', $description) . ' rest=' . $rest);
        }
        foreach ($uses as $index => $use) {
            if ($use > 0) $this->emit('USE ' . ($index + 1) . ' bars=' . $use);
        }
        foreach ($pieces as $index => [$size, $demand]) {
            $this->emit('PIECE ' . $size . ' demand=' . $demand . ' cut=' . $cut[$index]);
        }
        $this->emit('TOTAL bars=' . $bars . ' trim=' . $trim .
                    ' surplus=' . (array_sum($cut) - $demanded) .
                    ' waste=' . ($bars * $length - $quantity));

        $comparison = [];
        foreach ($pieces as [$size, $demand]) {
            for ($i = 0; $i < $demand; ++$i) {
                $comparison[] = [count($comparison) + 1, $size];
            }
        }
        $ffd = count(pack($comparison, $length, 'FIRSTFIT')->bins);
        $this->emit('FFD bars=' . $ffd . ' waste=' . ($ffd * $length - $quantity));
        $this->emit('LOWER bars=' . ceiling($quantity, $length));
    }

    private function rectangles(array $tokens): array
    {
        $rectangles = [];
        foreach ($tokens as $index => $token) {
            [$width, $height] = array_map('intval', explode('x', $token));
            $rectangles[] = [$index + 1, $width, $height];
        }
        return $rectangles;
    }

    private function drawing(int $width, int $height, array $placements): void
    {
        $cells = array_fill(0, $height, array_fill(0, $width, '.'));
        foreach ($placements as [$number, $x, $y, $placedWidth, $placedHeight, $rotated]) {
            $letter = chr(64 + $number);
            for ($row = $y; $row < $y + $placedHeight; ++$row) {
                for ($column = $x; $column < $x + $placedWidth; ++$column) {
                    $cells[$row][$column] = $letter;
                }
            }
        }
        for ($row = $height - 1; $row >= 0; --$row) {
            $this->emit(implode('', $cells[$row]));
        }
    }

    private function shelfMethod(string $method, int $width,
                                 array $rectangles, int $area): void
    {
        $shelves = [];
        $placements = [];
        foreach ($rectangles as [$number, $w, $h]) {
            $chosen = null;
            if ($method === 'NFDH') {
                if ($shelves && end($shelves)->used + $w <= $width) {
                    $chosen = count($shelves) - 1;
                }
            } else {
                foreach ($shelves as $index => $shelf) {
                    if ($shelf->used + $w > $width) continue;
                    if ($method === 'FFDH') {
                        $chosen = $index;
                        break;
                    }
                    if ($chosen === null || $shelf->used > $shelves[$chosen]->used) {
                        $chosen = $index;
                    }
                }
            }
            if ($chosen === null) {
                $bottom = $shelves ?
                    end($shelves)->bottom + end($shelves)->height : 0;
                $shelves[] = (object) [
                    'bottom' => $bottom, 'height' => $h, 'used' => 0, 'items' => [],
                ];
                $chosen = count($shelves) - 1;
            }
            $shelf = $shelves[$chosen];
            $shelf->items[] = [$number, $shelf->used];
            $placements[] = [$number, $shelf->used, $shelf->bottom, $w, $h, false];
            $shelf->used += $w;
        }
        $height = end($shelves)->bottom + end($shelves)->height;
        $this->emit($method . ' height=' . $height .
                    ' shelves=' . count($shelves) .
                    ' util=' . intdiv($area * 100, $width * $height));
        foreach ($shelves as $index => $shelf) {
            $items = [];
            foreach ($shelf->items as [$number, $x]) {
                $items[] = chr(64 + $number) . '@' . $x;
            }
            $this->emit('LEVEL ' . ($index + 1) . ' y=' . $shelf->bottom .
                        ' h=' . $shelf->height . ' used=' . $shelf->used .
                        ' items=' . implode(' ', $items));
        }
        $this->drawing($width, $height, $placements);
    }

    private function cmdShelf(array $args): void
    {
        $width = (int) array_shift($args);
        if ($width === 0) fail('BAD CAPACITY');
        $rectangles = $this->rectangles($args);
        foreach ($rectangles as [$number, $w, $h]) {
            if ($w === 0 || $h === 0 || $w > $width) fail('BAD RECT ' . $number);
        }
        usort($rectangles, static function (array $a, array $b): int {
            return ($b[2] <=> $a[2]) ?: (($b[1] <=> $a[1]) ?: ($a[0] <=> $b[0]));
        });
        $area = 0;
        foreach ($rectangles as [, $w, $h]) $area += $w * $h;
        $this->emit('SHELF W=' . $width . ' rects=' . count($rectangles) . ' area=' . $area);

        foreach (['NFDH', 'FFDH', 'BFDH'] as $method) {
            $this->shelfMethod($method, $width, $rectangles, $area);
        }

        $heights = array_fill(0, $width, 0);
        $placements = [];
        foreach ($rectangles as [$number, $w, $h]) {
            $chosenX = null;
            $bestY = null;
            for ($x = 0; $x <= $width - $w; ++$x) {
                $y = max(array_slice($heights, $x, $w));
                if ($bestY === null || $y < $bestY) {
                    $chosenX = $x;
                    $bestY = $y;
                }
            }
            $placements[] = [$number, $chosenX, $bestY, $w, $h, false];
            for ($x = $chosenX; $x < $chosenX + $w; ++$x) {
                $heights[$x] = $bestY + $h;
            }
        }
        $height = max($heights);
        $this->emit('SKYLINE height=' . $height .
                    ' util=' . intdiv($area * 100, $width * $height));
        foreach ($placements as [$number, $x, $y, $w, $h, $rotated]) {
            $this->emit('PLACE ' . chr(64 + $number) . ' x=' . $x .
                        ' y=' . $y . ' w=' . $w . ' h=' . $h);
        }
        $this->drawing($width, $height, $placements);
    }

    private function selectFreeRectangle(array $sheets, int $width, int $height,
                                         bool $rotate, string $rule): ?array
    {
        $chosen = null;
        $best = null;
        foreach ($sheets as $sheetNumber => $sheet) {
            foreach ($sheet->free as $index => [$x, $y, $freeWidth, $freeHeight]) {
                $fits = $width <= $freeWidth && $height <= $freeHeight;
                $fitsRotated = $rotate && $height <= $freeWidth && $width <= $freeHeight;
                if (!$fits && !$fitsRotated) continue;
                if ($rule === 'FIRST') return [$sheetNumber, $index];
                $area = $freeWidth * $freeHeight;
                if ($best === null || $area < $best) {
                    $best = $area;
                    $chosen = [$sheetNumber, $index];
                }
            }
        }
        return $chosen;
    }

    private function cmdGuillotine(array $args): void
    {
        $width = (int) array_shift($args);
        $height = (int) array_shift($args);
        if ($width === 0 || $height === 0) fail('BAD CAPACITY');
        $mode = array_shift($args);
        $rule = array_shift($args);
        $rotate = $mode === 'ROTATE';
        $rectangles = $this->rectangles($args);
        foreach ($rectangles as [$number, $w, $h]) {
            $fits = $w <= $width && $h <= $height;
            $fitsRotated = $rotate && $h <= $width && $w <= $height;
            if ($w === 0 || $h === 0 || (!$fits && !$fitsRotated)) {
                fail('BAD RECT ' . $number);
            }
        }
        usort($rectangles, static function (array $a, array $b): int {
            return ($b[1] * $b[2] <=> $a[1] * $a[2]) ?: ($a[0] <=> $b[0]);
        });
        $sheets = [];
        $rotatedCount = 0;
        foreach ($rectangles as [$number, $w, $h]) {
            $chosen = $this->selectFreeRectangle($sheets, $w, $h, $rotate, $rule);
            if ($chosen === null) {
                $sheets[] = (object) [
                    'free' => [[0, 0, $width, $height]],
                    'placements' => [],
                    'area' => 0,
                ];
                $chosen = [count($sheets) - 1, 0];
            }
            [$sheetNumber, $index] = $chosen;
            $sheet = $sheets[$sheetNumber];
            [$x, $y, $fw, $fh] = array_splice($sheet->free, $index, 1)[0];
            $rotated = !($w <= $fw && $h <= $fh);
            [$pw, $ph] = $rotated ? [$h, $w] : [$w, $h];
            $rotatedCount += (int) $rotated;
            $sheet->placements[] = [$number, $x, $y, $pw, $ph, $rotated];
            $sheet->area += $w * $h;
            $rw = $fw - $pw;
            $rh = $fh - $ph;
            if ($rw <= $rh) {
                $children = [
                    [$x, $y + $ph, $fw, $rh],
                    [$x + $pw, $y, $rw, $ph],
                ];
            } else {
                $children = [
                    [$x, $y + $ph, $pw, $rh],
                    [$x + $pw, $y, $rw, $fh],
                ];
            }
            foreach ($children as $child) {
                if ($child[2] > 0 && $child[3] > 0) $sheet->free[] = $child;
            }
        }
        $area = 0;
        foreach ($sheets as $sheet) $area += $sheet->area;
        $util = intdiv($area * 100, count($sheets) * $width * $height);
        $this->emit('GUILLOTINE W=' . $width . ' H=' . $height .
                    ' mode=' . $mode . ' rule=' . $rule .
                    ' rects=' . count($rectangles) .
                    ' sheets=' . count($sheets) .
                    ' rotated=' . $rotatedCount . ' util=' . $util);
        foreach ($sheets as $index => $sheet) {
            $this->emit('SHEET ' . ($index + 1) .
                        ' placed=' . count($sheet->placements) .
                        ' area=' . $sheet->area);
            foreach ($sheet->placements as [$number, $x, $y, $w, $h, $rotated]) {
                $line = 'PLACE ' . chr(64 + $number) .
                        ' x=' . $x . ' y=' . $y . ' w=' . $w . ' h=' . $h;
                if ($rotated) $line .= ' rotated';
                $this->emit($line);
            }
            $free = [];
            foreach ($sheet->free as [$x, $y, $w, $h]) {
                $free[] = $x . ',' . $y . ',' . $w . 'x' . $h;
            }
            $this->emit('FREE ' . ($free ? implode(' ', $free) : 'none'));
            $this->drawing($width, $height, $sheet->placements);
        }
    }

    public function execute(string $line): void
    {
        $words = explode(' ', $line);
        $command = array_shift($words);
        try {
            if (!in_array($command, ['ITEMS', 'RANDOM', 'CUTSTOCK', 'SHELF', 'GUILLOTINE'], true)
                && $this->items === null) {
                fail('NO ITEMS');
            }
            if (in_array($command, METHODS, true)) {
                $this->showMethod($command, $words);
                return;
            }
            switch ($command) {
                case 'ITEMS': $this->cmdItems($words); break;
                case 'RANDOM': $this->cmdRandom($words); break;
                case 'TRACE': $this->cmdTrace($words); break;
                case 'REDUCE': $this->cmdReduce($words); break;
                case 'BOUNDS': $this->cmdBounds(); break;
                case 'COMPARE': $this->cmdCompare($words); break;
                case 'EXACT': $this->cmdExact($words); break;
                case 'CHECK': $this->cmdCheck($words); break;
                case 'COVER': $this->cmdCover(); break;
                case 'MULTIFIT': $this->cmdMultifit($words); break;
                case 'CUTSTOCK': $this->cmdCutstock($words); break;
                case 'SHELF': $this->cmdShelf($words); break;
                case 'GUILLOTINE': $this->cmdGuillotine($words); break;
            }
        } catch (CommandError $error) {
            $this->emit('ERROR ' . $error->getMessage());
        }
    }

    public function printOutput(): void
    {
        if ($this->output) echo implode("\n", $this->output) . "\n";
    }
}

$lines = (int) trim((string) fgets(STDIN));
$laboratory = new PackingLab();
for ($i = 0; $i < $lines; ++$i) {
    $laboratory->execute(rtrim((string) fgets(STDIN), "\r\n"));
}
$laboratory->printOutput();
