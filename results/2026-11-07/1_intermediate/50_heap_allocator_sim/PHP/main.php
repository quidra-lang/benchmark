<?php

declare(strict_types=1);

const MODES = ['FIRST', 'NEXT', 'BEST', 'WORST', 'SEGFIT', 'BUDDY'];
const COUNTERS = ['allocs', 'frees', 'reallocs', 'moves', 'failures', 'collected'];
const UNIT = 8;
const HEADER = 8;
const MIN_BLOCK = 16;
const MIN_BUDDY_BLOCK = 32;
const MAX_HEAP = 65536;
const UNINITIALIZED = -1;
const RANDOM_MULTIPLIER = 48271;
const RANDOM_MODULUS = 2147483647;

final class CommandError extends RuntimeException {}

function isPowerOfTwo(int $number): bool
{
    return $number > 0 && ($number & ($number - 1)) === 0;
}

function sizeClass(int $size): int
{
    return strlen(decbin($size)) - 1;
}

function fragmentationPercent(int $free, int $largest): int
{
    return $free > 0 ? intdiv(($free - $largest) * 100, $free) : 0;
}

function total(array $values): int
{
    return array_sum($values);
}

final class Block
{
    public bool $used = false;
    public ?string $owner = null;
    public int $requested = 0;
    public array $contents = [];
    public int $stamp = 0;

    public function __construct(public int $start, public int $size) {}

    public function end(): int { return $this->start + $this->size; }
    public function payload(): int { return $this->start + HEADER; }
    public function area(): string { return $this->start . '+' . $this->size; }

    public function mapUnits(): string
    {
        $count = intdiv($this->size, UNIT) - 1;
        if (!$this->used) return 'F' . str_repeat('.', $count);
        $out = 'H';
        for ($i = 0; $i < $count; ++$i) {
            $out .= UNIT * $i < $this->requested ? '#' : '-';
        }
        return $out;
    }
}

final class Heap
{
    public int $rover = 0;
    public int $registrations = 0;
    public array $blocks;

    public function __construct(public string $mode, public int $size)
    {
        $this->blocks = [$this->register(new Block(0, $size))];
    }

    public function register(Block $block): Block
    {
        $block->stamp = ++$this->registrations;
        return $block;
    }

    public function isBuddy(): bool { return $this->mode === 'BUDDY'; }

    public function requiredLength(int $request): int
    {
        $length = intdiv($request + UNIT - 1, UNIT) * UNIT + HEADER;
        if (!$this->isBuddy()) return $length;
        $power = MIN_BUDDY_BLOCK;
        while ($power < $length) $power *= 2;
        return $power;
    }

    public function indexOf(Block $block): int
    {
        return array_search($block, $this->blocks, true);
    }

    public function locate(int $address): int
    {
        foreach ($this->blocks as $index => $block) {
            if ($block->end() > $address) return $index;
        }
        throw new LogicException('address is outside the heap');
    }

    public function usedBlocks(): array
    {
        return array_values(array_filter($this->blocks, static fn(Block $b): bool => $b->used));
    }

    public function freeBlocks(): array
    {
        return array_values(array_filter($this->blocks, static fn(Block $b): bool => !$b->used));
    }

    public function usedTotal(): int
    {
        return total(array_map(static fn(Block $b): int => $b->size, $this->usedBlocks()));
    }

    public function fragmentation(): int
    {
        $sizes = array_map(static fn(Block $b): int => $b->size, $this->freeBlocks());
        return fragmentationPercent(total($sizes), $sizes ? max($sizes) : 0);
    }

    public function placement(Block $block, int $alignment): int
    {
        $place = intdiv($block->start + HEADER + $alignment - 1, $alignment)
            * $alignment - HEADER;
        if ($place > $block->start && $place - $block->start < MIN_BLOCK) $place += $alignment;
        return $place;
    }

    public function rank(int $index, int $roverIndex): array
    {
        $block = $this->blocks[$index];
        return match ($this->mode) {
            'NEXT' => [($index - $roverIndex + count($this->blocks)) % count($this->blocks), 0],
            'BEST', 'BUDDY' => [$block->size, $block->start],
            'WORST' => [-$block->size, $block->start],
            'SEGFIT' => [sizeClass($block->size), -$block->stamp],
            default => [$block->start, 0]
        };
    }

    public function choose(int $length, int $alignment): ?array
    {
        $roverIndex = $this->locate($this->rover);
        $chosen = null;
        foreach ($this->blocks as $index => $block) {
            if ($block->used) continue;
            $place = $this->placement($block, $alignment);
            if ($place + $length > $block->end()) continue;
            $rank = $this->rank($index, $roverIndex);
            if ($chosen === null || $rank < $chosen[0]) $chosen = [$rank, $index, $place];
        }
        return $chosen;
    }

    public function allocate(int $length, int $alignment): ?Block
    {
        $choice = $this->choose($length, $alignment);
        if ($choice === null) return null;
        [, $index, $place] = $choice;
        $block = $this->isBuddy()
            ? $this->halve($index, $length) : $this->carve($index, $place, $length);
        $block->used = true;
        if ($this->mode === 'NEXT') {
            $this->rover = $block->end() === $this->size ? 0 : $block->end();
        }
        return $block;
    }

    public function carve(int $index, int $place, int $length): Block
    {
        $original = $this->blocks[$index];
        $parts = [];
        if ($place > $original->start) {
            $parts[] = $this->register(new Block($original->start, $place - $original->start));
        }
        $block = new Block($place, $original->end() - $place);
        $parts[] = $block;
        if ($block->size - $length >= MIN_BLOCK) {
            $parts[] = $this->register(new Block($place + $length, $block->size - $length));
            $block->size = $length;
        }
        array_splice($this->blocks, $index, 1, $parts);
        return $block;
    }

    public function halve(int $index, int $length): Block
    {
        $block = $this->blocks[$index];
        while ($block->size > $length) {
            $block->size = intdiv($block->size, 2);
            array_splice($this->blocks, $index + 1, 0,
                [$this->register(new Block($block->end(), $block->size))]);
        }
        return $block;
    }

    public function mergeNext(int $index): void
    {
        $removed = array_splice($this->blocks, $index + 1, 1)[0];
        $this->blocks[$index]->size += $removed->size;
    }

    public function buddyIndex(int $index): int
    {
        $block = $this->blocks[$index];
        return $block->start % (2 * $block->size) === 0 ? $index + 1 : $index - 1;
    }

    public function coalesce(int $index): array
    {
        $merges = 0;
        if ($this->isBuddy()) {
            while ($this->blocks[$index]->size < $this->size) {
                $partner = $this->buddyIndex($index);
                $other = $this->blocks[$partner];
                if ($other->used || $other->size !== $this->blocks[$index]->size) break;
                $index = min($index, $partner);
                $this->mergeNext($index);
                ++$merges;
            }
        } else {
            if ($index + 1 < count($this->blocks) && !$this->blocks[$index + 1]->used) {
                $this->mergeNext($index);
                ++$merges;
            }
            if ($index > 0 && !$this->blocks[$index - 1]->used) {
                --$index;
                $this->mergeNext($index);
                ++$merges;
            }
        }
        return [$this->register($this->blocks[$index]), $merges];
    }

    public function release(Block $block): array
    {
        $block->used = false;
        $block->owner = null;
        $block->requested = 0;
        $block->contents = [];
        return $this->coalesce($this->indexOf($block));
    }

    public function shrink(int $index, int $length): string
    {
        $block = $this->blocks[$index];
        if ($this->isBuddy()) {
            if ($length === $block->size) return 'kept';
            $this->halve($index, $length);
            return 'shrunk';
        }
        if ($block->size - $length < MIN_BLOCK) return 'kept';
        array_splice($this->blocks, $index + 1, 0,
            [new Block($block->start + $length, $block->size - $length)]);
        $block->size = $length;
        $this->coalesce($index + 1);
        return 'shrunk';
    }

    public function growIntoNext(int $index, int $length): ?string
    {
        $block = $this->blocks[$index];
        if ($index + 1 === count($this->blocks) || $this->blocks[$index + 1]->used) return null;
        $total = $block->size + $this->blocks[$index + 1]->size;
        if ($total < $length) return null;
        array_splice($this->blocks, $index + 1, 1);
        if ($total - $length >= MIN_BLOCK) {
            $block->size = $length;
            array_splice($this->blocks, $index + 1, 0,
                [$this->register(new Block($block->end(), $total - $length))]);
        } else $block->size = $total;
        return 'grown';
    }

    public function growBuddy(int $index, int $length): ?string
    {
        $block = $this->blocks[$index];
        $size = $block->size;
        $last = $index;
        while ($size < $length) {
            ++$last;
            if ($block->start % (2 * $size) !== 0 || $last === count($this->blocks)) return null;
            $partner = $this->blocks[$last];
            if ($partner->used || $partner->size !== $size) return null;
            $size *= 2;
        }
        array_splice($this->blocks, $index + 1, $last - $index);
        $block->size = $length;
        return 'grown';
    }

    public function resize(Block $block, int $length): ?string
    {
        $index = $this->indexOf($block);
        if ($length <= $block->size) return $this->shrink($index, $length);
        return $this->isBuddy()
            ? $this->growBuddy($index, $length) : $this->growIntoNext($index, $length);
    }

    public function extend(int $amount): Block
    {
        $this->blocks[] = new Block($this->size, $amount);
        $this->size += $amount;
        return $this->coalesce(count($this->blocks) - 1)[0];
    }

    public function trim(): int
    {
        $released = 0;
        if ($this->isBuddy()) {
            while (!$this->blocks[array_key_last($this->blocks)]->used &&
                   2 * $this->blocks[array_key_last($this->blocks)]->size === $this->size) {
                $released += array_pop($this->blocks)->size;
                $this->size = intdiv($this->size, 2);
            }
        } elseif (count($this->blocks) >= 2 && !$this->blocks[array_key_last($this->blocks)]->used) {
            $last = array_pop($this->blocks);
            $released = $last->size;
            $this->size = $last->start;
        }
        if ($this->rover >= $this->size) $this->rover = 0;
        return $released;
    }

    public function compact(): array
    {
        $moved = [];
        $address = 0;
        $packed = $this->usedBlocks();
        foreach ($packed as $block) {
            if ($block->start !== $address) {
                $moved[] = [$block, $block->payload()];
                $block->start = $address;
            }
            $address += $block->size;
        }
        if ($address < $this->size) {
            $packed[] = $this->register(new Block($address, $this->size - $address));
        }
        $this->blocks = $packed;
        $this->rover = 0;
        return [$moved, $address];
    }
}

function experiment(string $mode, int $size, int $seed, int $operations, int $maxRequest): string
{
    $heap = new Heap($mode, $size);
    $state = $seed;
    $live = [];
    $used = $peak = $success = $failures = 0;
    for ($i = 0; $i < $operations; ++$i) {
        $state = RANDOM_MULTIPLIER * $state % RANDOM_MODULUS;
        $allocating = !$live || $state % 3 !== 0;
        $state = RANDOM_MULTIPLIER * $state % RANDOM_MODULUS;
        if ($allocating) {
            $requested = 1 + $state % $maxRequest;
            $block = $heap->allocate($heap->requiredLength($requested), UNIT);
            if ($block === null) ++$failures;
            else {
                ++$success;
                $live[] = $block;
                $used += $block->size;
            }
        } else {
            $block = array_splice($live, $state % count($live), 1)[0];
            $used -= $block->size;
            $heap->release($block);
        }
        $peak = max($peak, $used);
    }
    return 'BENCH ' . $mode . ' ok=' . $success . ' fail=' . $failures .
        ' peak=' . $peak . ' used=' . $used . ' frag=' . $heap->fragmentation() .
        ' blocks=' . count($heap->blocks);
}

final class Allocator
{
    public array $output = [];
    private ?Heap $heap = null;
    private array $allocations = [];
    private array $freed = [];
    private array $roots = [];
    private array $references = [];
    private array $histories = [];
    private array $counters = [];
    private int $peak = 0;

    private const METHODS = [
        'HEAP' => 'createHeap', 'MALLOC' => 'malloc', 'CALLOC' => 'calloc',
        'MEMALIGN' => 'memalign', 'REALLOC' => 'realloc', 'FREE' => 'free',
        'FILL' => 'fill', 'COPY' => 'copy', 'READ' => 'read',
        'ROOT' => 'root', 'UNROOT' => 'unroot', 'LINK' => 'link', 'UNLINK' => 'unlink',
        'GC' => 'collect', 'SBRK' => 'sbrk', 'TRIM' => 'trim', 'COMPACT' => 'compact',
        'WHO' => 'who', 'DUMP' => 'dump', 'MAP' => 'showMap', 'FREELIST' => 'freelist',
        'TREE' => 'tree', 'STATS' => 'stats', 'LEAKS' => 'leaks',
        'HISTORY' => 'history', 'BENCH' => 'bench'
    ];

    public function __construct() { $this->reset(null); }

    private function reset(?Heap $heap): void
    {
        $this->heap = $heap;
        $this->allocations = $this->freed = $this->roots = [];
        $this->references = $this->histories = [];
        $this->counters = array_fill_keys(COUNTERS, 0);
        $this->peak = 0;
    }

    private function emit(string ...$parts): void { $this->output[] = implode(' ', $parts); }

    private function record(string $name, string $line): void
    {
        $this->emit($line);
        $this->histories[$name][] = $line;
    }

    private function outOfMemory(string $name): CommandError
    {
        ++$this->counters['failures'];
        return new CommandError('OUT OF MEMORY ' . $name);
    }

    private function requireLive(string $name): Block
    {
        if (isset($this->allocations[$name])) return $this->allocations[$name];
        if (isset($this->freed[$name])) throw new CommandError('USE AFTER FREE ' . $name);
        throw new CommandError('UNKNOWN ID ' . $name);
    }

    private function requireRange(string $name, int $offset, int $length): Block
    {
        $block = $this->requireLive($name);
        if ($offset + $length > $block->requested) throw new CommandError('OUT OF BOUNDS ' . $name);
        return $block;
    }

    private function requireFreeList(): void
    {
        if ($this->heap->isBuddy()) throw new CommandError('UNSUPPORTED IN BUDDY MODE');
    }

    private function reachable(): array
    {
        $found = $this->roots;
        $pending = array_keys($this->roots);
        while ($pending) {
            $name = array_pop($pending);
            foreach ($this->references[$name] ?? [] as $target => $_) {
                if (isset($found[$target])) continue;
                $found[$target] = true;
                $pending[] = $target;
            }
        }
        return $found;
    }

    private function createHeap(array $args): void
    {
        $size = (int)$args[0];
        $mode = $args[1];
        if ($size % UNIT !== 0 || $size < 32 || $size > MAX_HEAP ||
            ($mode === 'BUDDY' && !isPowerOfTwo($size))) {
            throw new CommandError('BAD HEAP SIZE');
        }
        $this->reset(new Heap($mode, $size));
        $this->emit("HEAP size=$size mode=$mode");
    }

    private function allocateId(string $word, string $name, int $request,
                                int $alignment, int $fill): void
    {
        if ($request === 0) throw new CommandError('BAD SIZE');
        if (isset($this->allocations[$name])) throw new CommandError('DUPLICATE ID ' . $name);
        $block = $this->heap->allocate($this->heap->requiredLength($request), $alignment);
        if ($block === null) throw $this->outOfMemory($name);
        $block->owner = $name;
        $block->requested = $request;
        $block->contents = array_fill(0, $request, $fill);
        $this->allocations[$name] = $block;
        unset($this->freed[$name]);
        ++$this->counters['allocs'];
        $this->record($name, "$word $name addr={$block->payload()} block={$block->size}");
    }

    private function malloc(array $args): void
    {
        $this->allocateId('MALLOC', $args[0], (int)$args[1], UNIT, UNINITIALIZED);
    }

    private function calloc(array $args): void
    {
        $this->allocateId('CALLOC', $args[0], (int)$args[1] * (int)$args[2], UNIT, 0);
    }

    private function memalign(array $args): void
    {
        [$name, $alignment, $request] = [$args[0], (int)$args[1], (int)$args[2]];
        $this->requireFreeList();
        if (!isPowerOfTwo($alignment) || $alignment < UNIT || $alignment > 4096) {
            throw new CommandError('BAD ALIGNMENT');
        }
        $this->allocateId('MEMALIGN', $name, $request, $alignment, UNINITIALIZED);
    }

    private function releaseId(string $name): string
    {
        $block = $this->allocations[$name];
        unset($this->allocations[$name]);
        $size = $block->size;
        $this->freed[$name] = true;
        unset($this->roots[$name], $this->references[$name]);
        foreach ($this->references as &$targets) unset($targets[$name]);
        unset($targets);
        [$result, $merges] = $this->heap->release($block);
        return "block=$size merges=$merges free={$result->area()}";
    }

    private function freeId(string $name): void
    {
        if (isset($this->freed[$name])) throw new CommandError('DOUBLE FREE ' . $name);
        if (!isset($this->allocations[$name])) throw new CommandError('UNKNOWN ID ' . $name);
        $details = $this->releaseId($name);
        ++$this->counters['frees'];
        $this->record($name, "FREE $name $details");
    }

    private function free(array $args): void { $this->freeId($args[0]); }

    private function realloc(array $args): void
    {
        [$name, $request] = [$args[0], (int)$args[1]];
        if ($request === 0) { $this->freeId($name); return; }
        if (isset($this->freed[$name])) throw new CommandError('USE AFTER FREE ' . $name);
        if (!isset($this->allocations[$name])) {
            $this->allocateId('MALLOC', $name, $request, UNIT, UNINITIALIZED);
            return;
        }
        $block = $this->allocations[$name];
        $length = $this->heap->requiredLength($request);
        $contents = array_slice($block->contents, 0, $request);
        if (count($contents) < $request) {
            array_push($contents, ...array_fill(0, $request - count($contents), UNINITIALIZED));
        }
        $origin = $block->payload();
        $kind = $this->heap->resize($block, $length);
        if ($kind === null) {
            $moved = $this->heap->allocate($length, UNIT);
            if ($moved === null) throw $this->outOfMemory($name);
            $moved->owner = $name;
            $this->allocations[$name] = $moved;
            $this->heap->release($block);
            ++$this->counters['moves'];
            $block = $moved;
            $kind = "moved from=$origin";
        }
        $block->requested = $request;
        $block->contents = $contents;
        ++$this->counters['reallocs'];
        $this->record($name, "REALLOC $name addr={$block->payload()} block={$block->size} $kind");
    }

    private function fill(array $args): void
    {
        [$name, $offset, $length, $value] = [$args[0], (int)$args[1], (int)$args[2], (int)$args[3]];
        $block = $this->requireRange($name, $offset, $length);
        array_splice($block->contents, $offset, $length, array_fill(0, $length, $value));
        $this->emit("FILL $name $offset+$length = $value");
    }

    private function copy(array $args): void
    {
        [$targetName, $targetOffset, $sourceName, $sourceOffset, $length] =
            [$args[0], (int)$args[1], $args[2], (int)$args[3], (int)$args[4]];
        $target = $this->requireRange($targetName, $targetOffset, $length);
        $source = $this->requireRange($sourceName, $sourceOffset, $length);
        $values = array_slice($source->contents, $sourceOffset, $length);
        array_splice($target->contents, $targetOffset, $length, $values);
        $this->emit("COPY $targetName $targetOffset+$length from $sourceName $sourceOffset");
    }

    private function read(array $args): void
    {
        [$name, $offset, $length] = [$args[0], (int)$args[1], (int)$args[2]];
        $block = $this->requireRange($name, $offset, $length);
        $values = array_map(static fn(int $v): string => $v === UNINITIALIZED ? '?' : (string)$v,
                            array_slice($block->contents, $offset, $length));
        $this->emit("READ $name $offset+$length = " . implode(' ', $values));
    }

    private function root(array $args): void
    {
        $name = $args[0];
        $this->requireLive($name);
        $this->roots[$name] = true;
        $this->emit('ROOT', $name);
    }

    private function unroot(array $args): void
    {
        $name = $args[0];
        $this->requireLive($name);
        if (!isset($this->roots[$name])) throw new CommandError('NOT ROOT ' . $name);
        unset($this->roots[$name]);
        $this->emit('UNROOT', $name);
    }

    private function link(array $args): void
    {
        [$source, $target] = $args;
        $this->requireLive($source);
        $this->requireLive($target);
        $this->references[$source][$target] = true;
        $this->emit('LINK', $source, $target);
    }

    private function unlink(array $args): void
    {
        [$source, $target] = $args;
        $this->requireLive($source);
        $this->requireLive($target);
        if (!isset($this->references[$source][$target])) {
            throw new CommandError("NO LINK $source $target");
        }
        unset($this->references[$source][$target]);
        $this->emit('UNLINK', $source, $target);
    }

    private function collect(array $args): void
    {
        $reachable = $this->reachable();
        $garbage = [];
        foreach ($this->allocations as $name => $block) {
            if (!isset($reachable[$name])) $garbage[] = $block;
        }
        usort($garbage, static fn(Block $a, Block $b): int => $a->start <=> $b->start);
        $size = total(array_map(static fn(Block $b): int => $b->size, $garbage));
        $this->emit('GC collected=' . count($garbage) . ' bytes=' . $size);
        foreach ($garbage as $block) {
            $name = $block->owner;
            $this->record($name, "COLLECT $name " . $this->releaseId($name));
        }
        $this->counters['collected'] += count($garbage);
    }

    private function sbrk(array $args): void
    {
        $amount = (int)$args[0];
        $heap = $this->heap;
        $valid = $heap->isBuddy()
            ? $amount === $heap->size && 2 * $heap->size <= MAX_HEAP
            : $amount % UNIT === 0 && $amount >= MIN_BLOCK && $heap->size + $amount <= MAX_HEAP;
        if (!$valid) throw new CommandError('BAD SBRK SIZE');
        $result = $heap->extend($amount);
        $this->emit("SBRK heap={$heap->size} free={$result->area()}");
    }

    private function trim(array $args): void
    {
        $released = $this->heap->trim();
        $this->emit("TRIM heap={$this->heap->size} released=$released");
    }

    private function compact(array $args): void
    {
        $this->requireFreeList();
        [$moved, $used] = $this->heap->compact();
        $this->counters['moves'] += count($moved);
        $free = $used < $this->heap->size ? $used . '+' . ($this->heap->size - $used) : 'none';
        $this->emit('COMPACT moved=' . count($moved) . ' free=' . $free);
        foreach ($moved as [$block, $origin]) {
            $this->record($block->owner, "MOVE {$block->owner} $origin -> {$block->payload()}");
        }
    }

    private function who(array $args): void
    {
        $address = (int)$args[0];
        if ($address >= $this->heap->size) { $this->emit("WHO $address outside"); return; }
        $block = $this->heap->blocks[$this->heap->locate($address)];
        if (!$block->used) { $this->emit("WHO $address free {$block->area()}"); return; }
        if ($address < $block->payload()) {
            $this->emit("WHO $address header {$block->owner}");
            return;
        }
        $offset = $address - $block->payload();
        $region = $offset < $block->requested ? 'data' : 'slack';
        $this->emit("WHO $address $region {$block->owner}+$offset");
    }

    private function dump(array $args): void
    {
        $heap = $this->heap;
        $header = "DUMP mode={$heap->mode} heap={$heap->size} blocks=" . count($heap->blocks);
        if ($heap->mode === 'NEXT') $header .= " rover={$heap->rover}";
        $this->emit($header);
        foreach ($heap->blocks as $block) {
            $this->emit($block->used
                ? "{$block->start} {$block->size} USED {$block->owner} req={$block->requested}"
                : "{$block->start} {$block->size} FREE");
        }
    }

    private function showMap(array $args): void
    {
        $this->emit("MAP heap={$this->heap->size}");
        $units = implode('', array_map(static fn(Block $b): string => $b->mapUnits(),
                                       $this->heap->blocks));
        for ($first = 0; $first < strlen($units); $first += 64) {
            $this->emit(str_pad((string)($first * UNIT), 5, '0', STR_PAD_LEFT),
                        substr($units, $first, 64));
        }
    }

    private function freelist(array $args): void
    {
        $free = $this->heap->freeBlocks();
        if ($this->heap->mode === 'SEGFIT') {
            usort($free, static fn(Block $a, Block $b): int => $b->stamp <=> $a->stamp);
        }
        $this->emit('FREELIST count=' . count($free));
        $classes = [];
        foreach ($free as $block) $classes[sizeClass($block->size)] = true;
        ksort($classes, SORT_NUMERIC);
        foreach (array_keys($classes) as $power) {
            $members = [];
            foreach ($free as $block) {
                if (sizeClass($block->size) === $power) $members[] = $block->area();
            }
            $this->emit((2 ** $power) . '-' . (2 ** ($power + 1) - 1) . ':', ...$members);
        }
    }

    private function treeNode(array $leaves, int $start, int $size, int $depth): void
    {
        $label = str_repeat(' ', 2 * $depth) . $start . '+' . $size;
        $block = $leaves[$start] ?? null;
        if ($block !== null && $block->size === $size) {
            $this->emit($block->used ? "$label USED {$block->owner}" : "$label FREE");
            return;
        }
        $this->emit("$label split");
        $half = intdiv($size, 2);
        $this->treeNode($leaves, $start, $half, $depth + 1);
        $this->treeNode($leaves, $start + $half, $half, $depth + 1);
    }

    private function tree(array $args): void
    {
        if (!$this->heap->isBuddy()) throw new CommandError('REQUIRES BUDDY MODE');
        $this->emit("TREE heap={$this->heap->size}");
        $leaves = [];
        foreach ($this->heap->blocks as $block) $leaves[$block->start] = $block;
        $this->treeNode($leaves, 0, $this->heap->size, 0);
    }

    private function stats(array $args): void
    {
        $used = $this->heap->usedBlocks();
        $free = $this->heap->freeBlocks();
        $freeTotal = total(array_map(static fn(Block $b): int => $b->size, $free));
        $largest = $free ? max(array_map(static fn(Block $b): int => $b->size, $free)) : 0;
        $usedTotal = total(array_map(static fn(Block $b): int => $b->size, $used));
        $requested = total(array_map(static fn(Block $b): int => $b->requested, $used));
        $this->emit('STATS used=' . $usedTotal . ' used_blocks=' . count($used) .
            ' free=' . $freeTotal . ' free_blocks=' . count($free) . ' largest=' . $largest .
            ' frag=' . fragmentationPercent($freeTotal, $largest) .
            ' requested=' . $requested . ' peak=' . $this->peak);
        $parts = ['OPS'];
        foreach (COUNTERS as $key) $parts[] = $key . '=' . $this->counters[$key];
        $this->emit(...$parts);
    }

    private function leaks(array $args): void
    {
        $reachable = $this->reachable();
        $names = array_keys($this->allocations);
        sort($names, SORT_STRING);
        $requested = 0; $lost = 0;
        foreach ($names as $name) {
            $requested += $this->allocations[$name]->requested;
            if (!isset($reachable[$name])) ++$lost;
        }
        $this->emit('LEAKS count=' . count($names) . " requested=$requested lost=$lost");
        foreach ($names as $name) {
            $block = $this->allocations[$name];
            $status = isset($reachable[$name]) ? 'reachable' : 'lost';
            $this->emit("LEAK $name addr={$block->payload()} block={$block->size} " .
                        "req={$block->requested} $status");
        }
    }

    private function history(array $args): void
    {
        $name = $args[0];
        $lines = $this->histories[$name] ?? [];
        $this->emit('HISTORY ' . $name . ' events=' . count($lines));
        array_push($this->output, ...$lines);
    }

    private function bench(array $args): void
    {
        [$size, $seed, $operations, $maxRequest] = array_map('intval', $args);
        if (!isPowerOfTwo($size) || $size < 32 || $size > MAX_HEAP) {
            throw new CommandError('BAD HEAP SIZE');
        }
        $this->emit("BENCH heap=$size seed=$seed ops=$operations maxreq=$maxRequest");
        foreach (MODES as $mode) {
            $this->emit(experiment($mode, $size, $seed, $operations, $maxRequest));
        }
    }

    public function execute(string $line): void
    {
        $words = explode(' ', $line);
        $command = array_shift($words);
        try {
            if ($this->heap === null && $command !== 'HEAP' && $command !== 'BENCH') {
                throw new CommandError('NO HEAP');
            }
            $this->{self::METHODS[$command]}($words);
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
        if ($this->heap !== null) $this->peak = max($this->peak, $this->heap->usedTotal());
    }
}

$allocator = new Allocator();
$count = (int)trim(fgets(STDIN));
for ($i = 0; $i < $count; ++$i) {
    $allocator->execute(rtrim(fgets(STDIN), "\r\n"));
}
echo implode("\n", $allocator->output) . "\n";
