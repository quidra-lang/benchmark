<?php
declare(strict_types=1);

enum Mode: string
{
    case CHAIN = 'CHAIN';
    case LINEAR = 'LINEAR';
    case QUADRATIC = 'QUADRATIC';
    case DOUBLE = 'DOUBLE';
    case ROBINHOOD = 'ROBINHOOD';
    case CUCKOO = 'CUCKOO';

    public function parts(): int { return $this === self::CUCKOO ? 2 : 1; }
    public function usesTombstones(): bool
    {
        return $this === self::LINEAR || $this === self::QUADRATIC || $this === self::DOUBLE;
    }
}

final class CommandError extends Exception
{
    public function __construct(string $message) { parent::__construct('ERROR ' . $message); }
}
final readonly class Item
{
    public function __construct(public string $key, public int $value) {}
    public function __toString(): string { return "$this->key=$this->value"; }
}
final readonly class Slot
{
    public function __construct(public ?Item $item = null, public bool $deleted = false) {}
    public function empty(): bool { return $this->item === null && !$this->deleted; }
    public function content(): string { return $this->item?->key ?? ($this->deleted ? 'D' : '-'); }
}
final class Counters
{
    public int $probes = 0, $rehashes = 0, $inserts = 0, $updates = 0;
    public int $hits = 0, $misses = 0, $deletes = 0, $absent = 0;
}
final class SearchResult
{
    public ?Item $item = null;
    public int $position = -1, $chainIndex = -1, $probes = 0;
    public ?int $available = null;
    public array $path = [];
}
final class Placement
{
    public bool $success = false, $reused = false;
    public int $position = -1, $shifted = 0, $kicks = 0;
    public ?Item $homeless = null;
    public array $moves = [];
}
final readonly class Removal
{
    public function __construct(public int $shifted, public array $moves) {}
}
final readonly class Mutation
{
    public function __construct(public bool $changed, public array $lines, public array $rehashes) {}
}
final readonly class Cost
{
    public function __construct(public string $key, public int $probes, public int $position) {}
}
final readonly class Metrics
{
    public function __construct(public int $longest, public string $average) {}
}

function checkedMode(string $text): Mode
{
    return Mode::tryFrom($text) ?? throw new CommandError('BAD MODE ' . $text);
}
function hashKey(string $key, int $base, int $modulus): int
{
    $value = 0;
    for ($i = 0; $i < strlen($key); $i++) $value = ($value * $base + ord($key[$i])) % $modulus;
    return $value;
}
function prime(int $value): int
{
    for ($candidate = max($value, 2); ; $candidate++) {
        $valid = true;
        for ($divisor = 2; $divisor * $divisor <= $candidate; $divisor++) {
            if ($candidate % $divisor === 0) { $valid = false; break; }
        }
        if ($valid) return $candidate;
    }
}
function ratio(int $numerator, int $denominator): string
{
    $value = $denominator === 0 ? 0 : intdiv(100 * $numerator, $denominator);
    return sprintf('%d.%02d', intdiv($value, 100), $value % 100);
}
function gauge(int $value): string { return $value >= 10 ? '+' : (string)$value; }
function generatedKeys(int $count, int $length, int $seed): Generator
{
    for ($i = 0; $i < $count; $i++) {
        $key = '';
        for ($j = 0; $j < $length; $j++) {
            $seed = 48271 * $seed % 2147483647;
            $key .= chr(97 + $seed % 26);
        }
        yield $key;
    }
}
function histogram(array $values): array
{
    $counts = array_count_values($values);
    ksort($counts, SORT_NUMERIC);
    $rows = [];
    foreach ($counts as $value => $count) {
        $rows[] = "$value $count " . str_repeat('#', min($count, 50)) . ($count > 50 ? '+' : '');
    }
    return $rows;
}
function checkCapacity(int $capacity): void
{
    if ($capacity < 2 || $capacity > 10000) throw new CommandError('BAD CAPACITY');
}
function checkGeneration(int $count, int $length, int $seed): void
{
    if ($count < 1 || $count > 500 || $length < 1 || $length > 10 || $seed < 1 || $seed > 2147483646) {
        throw new CommandError('BAD ARGUMENT');
    }
}

final class HashTable
{
    private array $buckets, $slots;
    public int $size = 0, $tombstones = 0;
    public readonly Counters $counters;

    public function __construct(public Mode $mode, public int $capacity)
    {
        $this->buckets = $mode === Mode::CHAIN ? array_fill(0, $capacity, []) : [];
        $this->slots = $mode === Mode::CHAIN ? [] : array_fill(0, $this->slotCount(), new Slot());
        $this->counters = new Counters();
    }
    public function slotCount(): int { return $this->capacity * $this->mode->parts(); }
    public function position(int $index): string
    {
        return $this->mode === Mode::CUCKOO ? 'T' . (intdiv($index, $this->capacity) + 1) . '.' . ($index % $this->capacity) : (string)$index;
    }
    private function distance(string $key, int $index): int
    {
        return ($index + $this->capacity - hashKey($key, 31, $this->capacity)) % $this->capacity;
    }
    public function items(): array
    {
        $result = [];
        if ($this->mode === Mode::CHAIN) {
            foreach ($this->buckets as $bucket) foreach ($bucket as $item) $result[] = $item;
        } else {
            foreach ($this->slots as $slot) if ($slot->item !== null) $result[] = $slot->item;
        }
        return $result;
    }
    public function search(string $key, bool $trace = false): SearchResult
    {
        $result = new SearchResult();
        $first = hashKey($key, 31, $this->capacity);
        $examine = function (int $index, string $content) use ($result, $trace): void {
            $result->probes++;
            if ($trace) $result->path[] = $this->position($index) . ':' . $content;
        };
        $found = static function (Item $item, int $index, int $chainIndex = -1) use ($result): void {
            $result->item = $item;
            $result->position = $index;
            $result->chainIndex = $chainIndex;
        };
        if ($this->mode === Mode::CHAIN) {
            foreach ($this->buckets[$first] as $index => $item) {
                $examine($first, $item->key);
                if ($item->key === $key) { $found($item, $first, $index); break; }
            }
            return $result;
        }
        if ($this->mode === Mode::CUCKOO) {
            foreach ([$first, $this->capacity + hashKey($key, 37, $this->capacity)] as $index) {
                $slot = $this->slots[$index];
                $examine($index, $slot->content());
                if ($slot->item !== null && $slot->item->key === $key) { $found($slot->item, $index); break; }
            }
            return $result;
        }
        $step = $this->mode === Mode::DOUBLE ? 1 + hashKey($key, 37, $this->capacity - 1) : 1;
        for ($i = 0; $i < $this->capacity; $i++) {
            $offset = $this->mode === Mode::QUADRATIC ? $i * $i : $i * $step;
            $index = ($first + $offset) % $this->capacity;
            $slot = $this->slots[$index];
            $examine($index, $slot->content());
            if ($slot->empty()) { $result->available ??= $index; break; }
            if ($slot->deleted) { $result->available ??= $index; continue; }
            $item = $slot->item;
            if ($item->key === $key) { $found($item, $index); break; }
            if ($this->mode === Mode::ROBINHOOD && $this->distance($item->key, $index) < $i) break;
        }
        return $result;
    }
    private function place(Item $item, ?SearchResult $initial = null, bool $trace = false): Placement
    {
        $result = new Placement();
        if ($this->mode === Mode::CHAIN) {
            $result->position = hashKey($item->key, 31, $this->capacity);
            $this->buckets[$result->position][] = $item;
            $result->success = true;
            return $result;
        }
        if ($this->mode->usesTombstones()) {
            $found = $initial ?? $this->search($item->key);
            $index = $found->available;
            if ($index === null) { $result->homeless = $item; return $result; }
            $result->position = $index;
            $result->reused = $this->slots[$index]->deleted;
            $this->slots[$index] = new Slot($item);
            if ($result->reused) $this->tombstones--;
            $result->success = true;
            return $result;
        }
        $current = $item;
        if ($this->mode === Mode::ROBINHOOD) {
            $index = hashKey($item->key, 31, $this->capacity);
            $distance = 0;
            $from = null;
            while (true) {
                $resident = $this->slots[$index]->item;
                if ($resident === null) {
                    $this->slots[$index] = new Slot($current);
                    if ($trace && $from !== null) $result->moves[] = "SHIFT $current->key $from -> $index";
                    if ($result->position < 0) $result->position = $index;
                    $result->success = true;
                    return $result;
                }
                $residentDistance = $this->distance($resident->key, $index);
                if ($residentDistance < $distance) {
                    $this->slots[$index] = new Slot($current);
                    if ($trace && $from !== null) $result->moves[] = "SHIFT $current->key $from -> $index";
                    if ($result->position < 0) $result->position = $index;
                    $current = $resident;
                    $from = $index;
                    $distance = $residentDistance;
                    $result->shifted++;
                }
                $index = ($index + 1) % $this->capacity;
                $distance++;
            }
        }
        $part = 0;
        while (true) {
            $index = $part * $this->capacity + hashKey($current->key, $part === 0 ? 31 : 37, $this->capacity);
            $resident = $this->slots[$index]->item;
            if ($resident === null) {
                $this->slots[$index] = new Slot($current);
                $result->success = true;
                $result->position = $this->search($item->key)->position;
                return $result;
            }
            if ($result->kicks === $this->capacity) { $result->homeless = $current; return $result; }
            $this->slots[$index] = new Slot($current);
            $result->kicks++;
            if ($trace) $result->moves[] = "KICK $resident->key " . $this->position($index);
            $current = $resident;
            $part = 1 - $part;
        }
    }
    private function remove(SearchResult $found, bool $trace): Removal
    {
        $shifted = 0;
        $moves = [];
        if ($this->mode === Mode::CHAIN) {
            array_splice($this->buckets[$found->position], $found->chainIndex, 1);
        } elseif ($this->mode->usesTombstones()) {
            $this->slots[$found->position] = new Slot(null, true);
            $this->tombstones++;
        } else {
            $this->slots[$found->position] = new Slot();
            if ($this->mode === Mode::ROBINHOOD) {
                $next = ($found->position + 1) % $this->capacity;
                while (($item = $this->slots[$next]->item) !== null && $this->distance($item->key, $next) > 0) {
                    $destination = ($next + $this->capacity - 1) % $this->capacity;
                    $this->slots[$destination] = new Slot($item);
                    $this->slots[$next] = new Slot();
                    if ($trace) $moves[] = "SHIFT $item->key $next -> $destination";
                    $shifted++;
                    $next = ($next + 1) % $this->capacity;
                }
            }
        }
        $this->size--;
        return new Removal($shifted, $moves);
    }
    public static function rebuild(array $items, Mode $mode, int $capacity): ?self
    {
        $trial = new self($mode, $capacity);
        foreach ($items as $item) {
            if (!$trial->place($item)->success) return null;
            $trial->size++;
        }
        return $trial;
    }
    public function adopt(self $replacement): void
    {
        $this->mode = $replacement->mode;
        $this->capacity = $replacement->capacity;
        $this->size = $replacement->size;
        $this->tombstones = $replacement->tombstones;
        $this->buckets = $replacement->buckets;
        $this->slots = $replacement->slots;
    }
    private function automatic(string $reason, int $capacity, ?Item $pending = null): string
    {
        $items = $this->items();
        if ($pending !== null) $items[] = $pending;
        $old = $this->capacity;
        while (true) {
            $trial = self::rebuild($items, $this->mode, $capacity);
            if ($trial !== null) {
                $this->adopt($trial);
                $this->counters->rehashes++;
                return "REHASH $reason $old -> $capacity";
            }
            $capacity = prime(2 * $capacity);
        }
    }
    private function loadCheck(int $maxLoad): array
    {
        $threshold = $maxLoad * $this->slotCount();
        if (100 * ($this->size + $this->tombstones) <= $threshold) return [];
        $grow = 200 * $this->size > $threshold;
        return [$this->automatic($grow ? 'load' : 'tomb', $grow ? prime(2 * $this->capacity) : $this->capacity)];
    }
    private function shrinkCheck(int $minLoad, int $maxLoad): array
    {
        $capacity = prime(intdiv($this->capacity, 2));
        if (100 * $this->size >= $minLoad * $this->slotCount() || $capacity >= $this->capacity ||
            100 * $this->size > $maxLoad * $capacity * $this->mode->parts()) return [];
        $trial = self::rebuild($this->items(), $this->mode, $capacity);
        if ($trial === null) return [];
        $old = $this->capacity;
        $this->adopt($trial);
        $this->counters->rehashes++;
        return ["REHASH shrink $old -> $capacity"];
    }
    public function put(string $key, int $value, int $maxLoad, string $command = 'PUT', bool $trace = false): Mutation
    {
        $found = $this->search($key, $trace);
        $path = $trace ? ['PATH ' . ($found->path === [] ? 'none' : implode(' ', $found->path))] : [];
        $this->counters->probes += $found->probes;
        if ($found->item !== null) {
            $old = $found->item->value;
            $item = new Item($key, $command === 'ADD' ? $old + $value : $value);
            if ($this->mode === Mode::CHAIN) $this->buckets[$found->position][$found->chainIndex] = $item;
            else $this->slots[$found->position] = new Slot($item);
            $this->counters->updates++;
            $row = "$command $item UPDATED old=$old at=" . $this->position($found->position) . " probes=$found->probes";
            return new Mutation(false, [$row, ...$path], []);
        }
        $item = new Item($key, $value);
        $placed = $this->place($item, $found, $trace);
        $this->size++;
        $this->counters->inserts++;
        $row = "$command $item NEW";
        if ($placed->success) {
            $row .= ' at=' . $this->position($placed->position) . " probes=$found->probes";
            if ($placed->reused) $row .= ' reused';
            if ($this->mode === Mode::ROBINHOOD) $row .= " shifted=$placed->shifted";
            if ($this->mode === Mode::CUCKOO) $row .= " kicks=$placed->kicks";
        } else {
            $row .= " probes=$found->probes" . ($this->mode === Mode::CUCKOO ? " kicks=$placed->kicks failed" : ' full');
        }
        $rehashes = [];
        if (!$placed->success) {
            $rehashes[] = $this->automatic($this->mode === Mode::CUCKOO ? 'kicks' : 'full', prime(2 * $this->capacity), $placed->homeless);
        }
        array_push($rehashes, ...$this->loadCheck($maxLoad));
        return new Mutation(true, [$row, ...$path, ...$placed->moves, ...$rehashes], $rehashes);
    }
    public function get(string $key, bool $trace): array
    {
        $found = $this->search($key, $trace);
        $this->counters->probes += $found->probes;
        if ($found->item !== null) {
            $this->counters->hits++;
            $row = 'GET ' . $found->item . ' at=' . $this->position($found->position) . " probes=$found->probes";
        } else {
            $this->counters->misses++;
            $row = "GET $key NOT FOUND probes=$found->probes";
        }
        return [$row, ...($trace ? ['PATH ' . ($found->path === [] ? 'none' : implode(' ', $found->path))] : [])];
    }
    public function delete(string $key, int $minLoad, int $maxLoad, bool $trace = false): Mutation
    {
        $found = $this->search($key, $trace);
        $path = $trace ? ['PATH ' . ($found->path === [] ? 'none' : implode(' ', $found->path))] : [];
        $this->counters->probes += $found->probes;
        if ($found->item === null) {
            $this->counters->absent++;
            return new Mutation(false, ["DEL $key NOT FOUND probes=$found->probes", ...$path], []);
        }
        $removed = $this->remove($found, $trace);
        $this->counters->deletes++;
        $row = "DEL $key OK at=" . $this->position($found->position) . " probes=$found->probes";
        if ($this->mode === Mode::ROBINHOOD) $row .= " shifted=$removed->shifted";
        $rehashes = $this->shrinkCheck($minLoad, $maxLoad);
        return new Mutation(true, [$row, ...$path, ...$removed->moves, ...$rehashes], $rehashes);
    }
    public function costs(): array
    {
        $records = [];
        if ($this->mode === Mode::CHAIN) {
            foreach ($this->buckets as $index => $bucket) {
                foreach ($bucket as $i => $item) $records[] = new Cost($item->key, $i + 1, $index);
            }
        } else {
            foreach ($this->slots as $index => $slot) {
                if ($slot->item === null) continue;
                $key = $slot->item->key;
                $cost = match ($this->mode) {
                    Mode::CUCKOO => intdiv($index, $this->capacity) + 1,
                    Mode::LINEAR, Mode::ROBINHOOD => $this->distance($key, $index) + 1,
                    default => $this->search($key)->probes,
                };
                $records[] = new Cost($key, $cost, $index);
            }
        }
        return $records;
    }
    public function metrics(): Metrics
    {
        $total = $longest = 0;
        foreach ($this->costs() as $cost) { $total += $cost->probes; $longest = max($longest, $cost->probes); }
        return new Metrics($longest, ratio($total, $this->size));
    }
    public function dump(): array
    {
        $rows = ["DUMP {$this->mode->value} cap=$this->capacity size=$this->size tomb=$this->tombstones"];
        if ($this->mode === Mode::CHAIN) {
            foreach ($this->buckets as $index => $bucket) $rows[] = "$index " . ($bucket === [] ? '-' : implode(' ', $bucket));
        } else {
            foreach ($this->slots as $index => $slot) {
                $position = $this->mode === Mode::CUCKOO ? 'T' . (intdiv($index, $this->capacity) + 1) . ' ' . ($index % $this->capacity) : (string)$index;
                $value = $slot->item !== null ? (string)$slot->item : $slot->content();
                if ($this->mode === Mode::ROBINHOOD && $slot->item !== null) $value .= ' d=' . $this->distance($slot->item->key, $index);
                $rows[] = "$position $value";
            }
        }
        return $rows;
    }
    public function map(): array
    {
        $rows = ["MAP {$this->mode->value} cap=$this->capacity"];
        $costBySlot = array_fill(0, $this->slotCount(), 0);
        if ($this->mode !== Mode::CHAIN) foreach ($this->costs() as $cost) $costBySlot[$cost->position] = $cost->probes;
        for ($part = 0; $part < $this->mode->parts(); $part++) {
            $characters = '';
            for ($index = 0; $index < $this->capacity; $index++) {
                if ($this->mode === Mode::CHAIN) {
                    $count = count($this->buckets[$index]);
                    $characters .= $count === 0 ? '.' : gauge($count);
                } else {
                    $flat = $part * $this->capacity + $index;
                    $slot = $this->slots[$flat];
                    $characters .= $slot->empty() ? '.' : ($slot->deleted ? 'D' : ($this->mode === Mode::CUCKOO ? '#' : gauge($costBySlot[$flat] - 1)));
                }
            }
            for ($index = 0; $index < $this->capacity; $index += 40) {
                $prefix = $this->mode === Mode::CUCKOO ? 'T' . ($part + 1) . ' ' : '';
                $rows[] = $prefix . sprintf('%05d ', $index) . substr($characters, $index, 40);
            }
        }
        return $rows;
    }
    public function statistics(): array
    {
        $values = $this->metrics();
        $count = $this->counters;
        $slots = $this->slotCount();
        return ["STATS {$this->mode->value} size=$this->size cap=$this->capacity slots=$slots tomb=$this->tombstones " .
            'load=' . ratio(100 * $this->size, $slots) . "% longest=$values->longest avg=$values->average probes=$count->probes rehashes=$count->rehashes",
            "OPS inserts=$count->inserts updates=$count->updates hits=$count->hits misses=$count->misses deletes=$count->deletes absent=$count->absent"];
    }
    public function scan(int $cursor, int $limit): array
    {
        $keys = [];
        while ($cursor < $this->slotCount() && count($keys) < $limit) {
            if ($this->mode === Mode::CHAIN) {
                foreach ($this->buckets[$cursor] as $item) $keys[] = $item->key;
            } elseif ($this->slots[$cursor]->item !== null) $keys[] = $this->slots[$cursor]->item->key;
            $cursor++;
        }
        if ($cursor === $this->slotCount()) $cursor = 0;
        return [implode(' ', ["SCAN next=$cursor", ...$keys])];
    }
    private function runs(int $start, int $count): array
    {
        $empty = null;
        for ($i = 0; $i < $count; $i++) if ($this->slots[$start + $i]->empty()) { $empty = $i; break; }
        if ($empty === null) return [$count];
        $lengths = [];
        $length = 0;
        for ($offset = 1; $offset <= $count; $offset++) {
            if (!$this->slots[$start + ($empty + $offset) % $count]->empty()) $length++;
            elseif ($length > 0) { $lengths[] = $length; $length = 0; }
        }
        return $lengths;
    }
    public function clusters(): array
    {
        $lengths = [];
        if ($this->mode === Mode::CHAIN) {
            foreach ($this->buckets as $bucket) if ($bucket !== []) $lengths[] = count($bucket);
        } else {
            for ($part = 0; $part < $this->mode->parts(); $part++) array_push($lengths, ...$this->runs($part * $this->capacity, $this->capacity));
        }
        return ['CLUSTERS runs=' . count($lengths) . ' longest=' . ($lengths === [] ? 0 : max($lengths)), ...histogram($lengths)];
    }
    public function distribution(): array
    {
        $values = array_map(static fn(Cost $cost): int => $cost->probes, $this->costs());
        return ["DIST keys=$this->size longest=" . ($values === [] ? 0 : max($values)), ...histogram($values)];
    }
}

final class Simulator
{
    private ?HashTable $table = null;
    private int $maxLoad = 75, $minLoad = 0;
    private bool $tracing = false;
    private const COMMANDS = ['CREATE', 'MAXLOAD', 'MINLOAD', 'TRACE', 'HASH', 'PUT', 'ADD',
        'GET', 'DEL', 'PROBE', 'GEN', 'GENDEL', 'RESIZE', 'CONVERT', 'CLEAR', 'DUMP', 'MAP',
        'STATS', 'KEYS', 'TOP', 'SCAN', 'CLUSTERS', 'DIST', 'COMPARE', 'BENCH'];

    private function compare(int $capacity): array
    {
        $items = $this->table->items();
        usort($items, static fn(Item $a, Item $b): int => strcmp($a->key, $b->key));
        $rows = ['COMPARE keys=' . count($items) . " cap=$capacity"];
        foreach (Mode::cases() as $mode) {
            $trial = new HashTable($mode, $capacity);
            foreach ($items as $item) $trial->put($item->key, $item->value, $this->maxLoad);
            $values = $trial->metrics();
            $rows[] = "$mode->value cap=$trial->capacity longest=$values->longest avg=$values->average probes={$trial->counters->probes} rehashes={$trial->counters->rehashes}";
        }
        return $rows;
    }
    private function bench(int $capacity, int $count, int $length, int $seed): array
    {
        $keys = iterator_to_array(generatedKeys(2 * $count, $length, $seed), false);
        $rows = ["BENCH cap=$capacity count=$count len=$length seed=$seed"];
        foreach (Mode::cases() as $mode) {
            $trial = new HashTable($mode, $capacity);
            for ($i = 0; $i < $count; $i++) $trial->put($keys[$i], $i + 1, $this->maxLoad);
            $misses = $probes = 0;
            for ($i = $count; $i < 2 * $count; $i++) {
                $found = $trial->search($keys[$i]);
                if ($found->item === null) { $misses++; $probes += $found->probes; }
            }
            $values = $trial->metrics();
            $rows[] = "$mode->value cap=$trial->capacity keys=$trial->size hit=$values->average misses=$misses miss=" .
                ratio($probes, $misses) . " rehashes={$trial->counters->rehashes}";
        }
        return $rows;
    }
    public function execute(string $line): array
    {
        $words = explode(' ', $line);
        $command = $words[0];
        if (!in_array($command, self::COMMANDS, true)) throw new CommandError('UNKNOWN COMMAND ' . $command);
        switch ($command) {
            case 'CREATE':
                $mode = checkedMode($words[1]);
                $capacity = (int)$words[2];
                checkCapacity($capacity);
                $this->table = new HashTable($mode, prime($capacity));
                return ["CREATE $mode->value cap={$this->table->capacity}"];
            case 'MAXLOAD':
            case 'MINLOAD':
                $value = (int)$words[1];
                $maximum = $command === 'MAXLOAD';
                if ($maximum ? $value < 10 || $value > 95 : $value < 0 || $value > 40) throw new CommandError('BAD LOAD');
                if ($maximum) $this->maxLoad = $value; else $this->minLoad = $value;
                return ["$command $value"];
            case 'TRACE':
                if ($words[1] !== 'ON' && $words[1] !== 'OFF') throw new CommandError('BAD ARGUMENT');
                $this->tracing = $words[1] === 'ON';
                return ['TRACE ' . $words[1]];
            case 'HASH':
                $key = $words[1];
                $capacity = (int)$words[2];
                checkCapacity($capacity);
                return ["HASH $key m=$capacity h31=" . hashKey($key, 31, $capacity) . ' h37=' . hashKey($key, 37, $capacity) . ' step=' . (1 + hashKey($key, 37, $capacity - 1))];
            case 'BENCH':
                $capacity = (int)$words[1];
                checkCapacity($capacity);
                [$count, $length, $seed] = array_map('intval', array_slice($words, 2));
                checkGeneration($count, $length, $seed);
                return $this->bench(prime($capacity), $count, $length, $seed);
        }
        $table = $this->table;
        if ($table === null) throw new CommandError('NO TABLE');
        switch ($command) {
            case 'PUT':
            case 'ADD': return $table->put($words[1], (int)$words[2], $this->maxLoad, $command, $this->tracing)->lines;
            case 'GET': return $table->get($words[1], $this->tracing);
            case 'DEL': return $table->delete($words[1], $this->minLoad, $this->maxLoad, $this->tracing)->lines;
            case 'PROBE':
                $found = $table->search($words[1], true);
                return [implode(' ', ['PROBE ' . $words[1], ...$found->path, ($found->item === null ? 'MISS' : 'FOUND') . " probes=$found->probes"])];
            case 'GEN':
            case 'GENDEL':
                [$count, $length, $seed] = array_map('intval', array_slice($words, 1));
                checkGeneration($count, $length, $seed);
                $rows = [];
                $changed = $index = 0;
                foreach (generatedKeys($count, $length, $seed) as $key) {
                    $index++;
                    $result = $command === 'GEN' ? $table->put($key, $index, $this->maxLoad) : $table->delete($key, $this->minLoad, $this->maxLoad);
                    if ($result->changed) $changed++;
                    array_push($rows, ...$result->rehashes);
                }
                $rows[] = $command === 'GEN' ? "GEN $count new=$changed updated=" . ($count - $changed)
                    : "GENDEL $count deleted=$changed missing=" . ($count - $changed);
                return $rows;
            case 'RESIZE':
            case 'CONVERT':
                $mode = $table->mode;
                $capacity = $table->capacity;
                if ($command === 'RESIZE') { $capacity = (int)$words[1]; checkCapacity($capacity); $capacity = prime($capacity); }
                else $mode = checkedMode($words[1]);
                if (100 * $table->size > $this->maxLoad * $capacity * $mode->parts()) throw new CommandError('TOO SMALL');
                $trial = HashTable::rebuild($table->items(), $mode, $capacity);
                if ($trial === null) throw new CommandError('REBUILD FAILED');
                $row = $command === 'RESIZE' ? "RESIZE $table->capacity -> $capacity" : "CONVERT {$table->mode->value} -> $mode->value cap=$capacity";
                $table->adopt($trial);
                return [$row];
            case 'CLEAR':
                $size = $table->size;
                $table->adopt(new HashTable($table->mode, $table->capacity));
                return ["CLEAR $size"];
            case 'DUMP': return $table->dump();
            case 'MAP': return $table->map();
            case 'STATS': return $table->statistics();
            case 'KEYS':
                $keys = array_map(static fn(Item $item): string => $item->key, $table->items());
                sort($keys, SORT_STRING);
                return [implode(' ', ["KEYS $table->size", ...$keys])];
            case 'TOP':
                $limit = (int)$words[1];
                if ($limit < 1 || $limit > 100) throw new CommandError('BAD ARGUMENT');
                $records = $table->costs();
                usort($records, static fn(Cost $a, Cost $b): int => ($b->probes <=> $a->probes) ?: strcmp($a->key, $b->key));
                $selected = array_slice($records, 0, $limit);
                return ['TOP ' . count($selected), ...array_map(fn(Cost $cost): string => "$cost->key cost=$cost->probes at=" . $table->position($cost->position), $selected)];
            case 'SCAN':
                $cursor = (int)$words[1];
                $limit = (int)$words[2];
                if ($limit < 1 || $limit > 100) throw new CommandError('BAD ARGUMENT');
                if ($cursor >= $table->slotCount()) throw new CommandError('BAD CURSOR');
                return $table->scan($cursor, $limit);
            case 'CLUSTERS': return $table->clusters();
            case 'DIST': return $table->distribution();
            case 'COMPARE':
                $capacity = (int)$words[1];
                checkCapacity($capacity);
                return $this->compare(prime($capacity));
            default: throw new LogicException('Unhandled command ' . $command);
        }
    }
}

$count = (int)fgets(STDIN);
$simulator = new Simulator();
for ($i = 0; $i < $count; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try { echo implode("\n", $simulator->execute($line)), "\n"; }
    catch (CommandError $error) { echo $error->getMessage(), "\n"; }
}
