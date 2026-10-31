<?php

require_once __DIR__ . '/mutator.php';
require_once __DIR__ . '/heap.php';
require_once __DIR__ . '/mark_sweep.php';
require_once __DIR__ . '/copying.php';
require_once __DIR__ . '/generational.php';

function pairText(array $pair): string
{
    return $pair[0] . ' ' . $pair[1];
}

function sumBy(iterable $values, callable $valueOf): int
{
    $total = 0;
    foreach ($values as $value) {
        $total += $valueOf($value);
    }
    return $total;
}

function sumPairs(iterable $values, callable $pairOf): array
{
    $total = [0, 0];
    foreach ($values as $value) {
        $pair = $pairOf($value);
        $total[0] += $pair[0];
        $total[1] += $pair[1];
    }
    return $total;
}

function slotValue(array $roots, ?int $slot): ?object
{
    return $slot === null ? null : $roots[$slot];
}

function reachable(array $roots): array
{
    $seen = [];
    $pending = [];
    foreach ($roots as $root) {
        if ($root !== null && !isset($seen[$root->number])) {
            $seen[$root->number] = $root;
            $pending[] = $root;
        }
    }
    while ($pending) {
        $object = array_pop($pending);
        foreach ($object->fields as $value) {
            if ($value !== null && !isset($seen[$value->number])) {
                $seen[$value->number] = $value;
                $pending[] = $value;
            }
        }
    }
    return $seen;
}

function stateError(object $command, array $roots, array $labels): ?string
{
    $op = $command->op;
    if (in_array($op, ['ALLOC', 'PUSH', 'LOAD'], true) && count($roots) === 64) {
        return 'stack';
    }
    if ((isset($command->i) && $command->i >= count($roots)) ||
        (isset($command->r) && $command->r >= count($roots)) ||
        ($op === 'POP' && $command->n > count($roots))) {
        return 'stack';
    }
    if (($op === 'LOAD' || $op === 'SET') && $roots[$command->i] === null) {
        return 'null';
    }
    if (($op === 'LOAD' || $op === 'SET') && $command->f >= $roots[$command->i]->pointers) {
        return 'field';
    }
    if ($op === 'CHECKPOINT' && isset($labels[$command->label])) {
        return 'duplicate';
    }
    return null;
}

function executeReference(object $state, object $command): void
{
    switch ($command->op) {
        case 'ALLOC':
            $object = createObject(count($state->objects) + 1, $command->p, $command->d);
            $object->birth = $state->clock;
            $object->death = null;
            $object->lifetime = null;
            $state->clock += $object->size;
            $state->objects[] = $object;
            $state->roots[] = $object;
            $command->number = $object->number;
            break;
        case 'PUSH':
            $state->roots[] = slotValue($state->roots, $command->r);
            break;
        case 'LOAD':
            $state->roots[] = $state->roots[$command->i]->fields[$command->f];
            break;
        case 'POP':
            array_splice($state->roots, count($state->roots) - $command->n, $command->n);
            break;
        case 'SET':
            $state->roots[$command->i]->fields[$command->f] = slotValue($state->roots, $command->r);
            break;
        case 'OVERWRITE':
            $state->roots[$command->i] = slotValue($state->roots, $command->r);
            break;
        case 'CHECKPOINT':
            $state->labels[$command->label] = true;
            break;
    }
}

function analyzeScript(array $lines): object
{
    $state = (object) ['lines' => count($lines), 'roots' => [], 'objects' => [], 'clock' => 0, 'labels' => [],
        'commands' => [], 'errors' => [], 'checkpoints' => [], 'live' => [],
        'counts' => array_fill_keys(COMMANDS, 0), 'peak' => (object) ['pair' => [0, -1], 'line' => 0]];
    $previousCount = $previousClock = 0;
    foreach ($lines as $index => $text) {
        $command = parseCommand($text, $index + 1);
        $reason = $command->reason ?? stateError($command, $state->roots, $state->labels);
        if ($reason !== null) {
            $state->errors[] = (object) ['line' => $index + 1, 'reason' => $reason];
            continue;
        }
        executeReference($state, $command);
        $state->commands[] = $command;
        $state->counts[$command->op]++;
        $live = reachable($state->roots);
        foreach ($state->live as $number => $object) {
            if (!isset($live[$number])) {
                $object->death = $command->line;
                $object->lifetime = $state->clock - $object->birth - $object->size;
            }
        }
        $state->live = $live;
        $amount = objectPair($live);
        if ($amount[1] > $state->peak->pair[1]) {
            $state->peak = (object) ['pair' => $amount, 'line' => $command->line];
        }
        if ($command->op === 'CHECKPOINT') {
            $survivors = objectPair(array_filter($live, fn($object) => $object->number > $previousCount));
            $ids = array_fill_keys(array_keys($live), true);
            $state->checkpoints[] = (object) ['label' => $command->label, 'line' => $command->line,
                'stack' => count($state->roots), 'live' => $amount, 'ids' => $ids,
                'allocated' => [count($state->objects), $state->clock],
                'phase' => [count($state->objects) - $previousCount, $state->clock - $previousClock], 'survivors' => $survivors];
            $previousCount = count($state->objects);
            $previousClock = $state->clock;
        }
    }
    $state->checkpointByLine = [];
    foreach ($state->checkpoints as $checkpoint) {
        $state->checkpointByLine[$checkpoint->line] = $checkpoint;
    }
    return $state;
}

function mutatorReport(object $reference): array
{
    $lines = ['script lines ' . $reference->lines . ' valid ' . count($reference->commands) . ' errors ' . count($reference->errors)];
    foreach ($reference->errors as $error) {
        $lines[] = 'error line ' . $error->line . ' ' . $error->reason;
    }
    $commands = [];
    foreach (COMMANDS as $command) {
        $commands[] = $command . ' ' . $reference->counts[$command];
    }
    $lines[] = 'commands ' . implode(' ', $commands);
    $sizes = array_map(fn($object) => $object->size, $reference->objects);
    $lines[] = 'allocated objects ' . count($reference->objects) . ' words ' . $reference->clock . ' sizes ' . classTable($sizes);
    $lines[] = 'peak_live objects ' . $reference->peak->pair[0] . ' words ' . $reference->peak->pair[1] . ' line ' . $reference->peak->line;
    $end = objectPair($reference->live);
    $lines[] = 'end_live objects ' . $end[0] . ' words ' . $end[1] . ' stack ' . count($reference->roots);
    $lifetimes = array_fill(0, 6, 0);
    foreach ($reference->objects as $object) {
        $value = $object->lifetime;
        $index = $value === null ? 5 : ($value <= 63 ? 0 : ($value <= 255 ? 1 : ($value <= 1023 ? 2 : ($value <= 4095 ? 3 : 4))));
        $lifetimes[$index]++;
    }
    $labels = ['0-63', '64-255', '256-1023', '1024-4095', '4096+', 'live'];
    $entries = [];
    foreach ($labels as $index => $label) {
        $entries[] = $label . ' ' . $lifetimes[$index];
    }
    $lines[] = 'lifetimes ' . implode(' ', $entries);
    foreach ($reference->checkpoints as $checkpoint) {
        $lines[] = 'checkpoint ' . $checkpoint->label . ' line ' . $checkpoint->line . ' stack ' . $checkpoint->stack .
            ' live ' . pairText($checkpoint->live) . ' allocated ' . pairText($checkpoint->allocated) .
            ' phase ' . pairText($checkpoint->phase) . ' survivors ' . pairText($checkpoint->survivors) .
            ' survival ' . pct($checkpoint->survivors[1], $checkpoint->phase[1]);
    }
    return $lines;
}

function leakGraph(array $objects): object
{
    $members = [];
    $outgoing = $incoming = $adjacent = [];
    foreach ($objects as $object) {
        $members[$object->number] = $object;
        $outgoing[$object->number] = [];
        $incoming[$object->number] = [];
        $adjacent[$object->number] = [];
    }
    foreach ($objects as $object) {
        foreach ($object->fields as $value) {
            if ($value === null || !isset($members[$value->number])) {
                continue;
            }
            $outgoing[$object->number][] = $value->number;
            $incoming[$value->number][] = $object->number;
            $adjacent[$object->number][] = $value->number;
            $adjacent[$value->number][] = $object->number;
        }
    }
    return (object) compact('members', 'outgoing', 'incoming', 'adjacent');
}

function leakGroups(array $objects, object $graph): array
{
    $groups = $seen = [];
    foreach ($objects as $start) {
        if (isset($seen[$start->number])) {
            continue;
        }
        $group = [];
        $stack = [$start->number];
        $seen[$start->number] = true;
        while ($stack) {
            $number = array_pop($stack);
            $group[] = $graph->members[$number];
            foreach ($graph->adjacent[$number] as $neighbor) {
                if (!isset($seen[$neighbor])) {
                    $seen[$neighbor] = true;
                    $stack[] = $neighbor;
                }
            }
        }
        usort($group, fn($a, $b) => $a->number <=> $b->number);
        $groups[] = $group;
    }
    return $groups;
}

function cycleObjects(array $objects, object $graph): array
{
    $seen = $finished = [];
    foreach ($objects as $start) {
        if (isset($seen[$start->number])) {
            continue;
        }
        $stack = [(object) ['number' => $start->number, 'next' => 0]];
        $seen[$start->number] = true;
        while ($stack) {
            $frame = $stack[count($stack) - 1];
            $edges = $graph->outgoing[$frame->number];
            if ($frame->next === count($edges)) {
                $finished[] = $frame->number;
                array_pop($stack);
                continue;
            }
            $number = $edges[$frame->next++];
            if (!isset($seen[$number])) {
                $seen[$number] = true;
                $stack[] = (object) ['number' => $number, 'next' => 0];
            }
        }
    }
    $seen = $cycles = [];
    for ($index = count($finished) - 1; $index >= 0; $index--) {
        $start = $finished[$index];
        if (isset($seen[$start])) {
            continue;
        }
        $component = [];
        $stack = [$start];
        $seen[$start] = true;
        while ($stack) {
            $number = array_pop($stack);
            $component[] = $number;
            foreach ($graph->incoming[$number] as $value) {
                if (!isset($seen[$value])) {
                    $seen[$value] = true;
                    $stack[] = $value;
                }
            }
        }
        if (count($component) > 1 || in_array($start, $graph->outgoing[$start], true)) {
            foreach ($component as $number) {
                $cycles[$number] = true;
            }
        }
    }
    return $cycles;
}

function leakReport(string $title, array $objects, object $reference): array
{
    $objects = array_values($objects);
    usort($objects, fn($a, $b) => $a->number <=> $b->number);
    $graph = leakGraph($objects);
    $groups = leakGroups($objects, $graph);
    $cycles = cycleObjects($objects, $graph);
    $amount = objectPair($objects);
    $lines = [$title . ' groups ' . count($groups) . ' objects ' . $amount[0] . ' words ' . $amount[1]];
    foreach ($groups as $index => $group) {
        $pair = objectPair($group);
        $died = $cyclic = 0;
        $ids = [];
        foreach ($group as $object) {
            $died = max($died, $reference->objects[$object->number - 1]->death);
            if (isset($cycles[$object->number])) {
                $cyclic++;
            }
            $ids[] = $object->number . (isset($cycles[$object->number]) ? '*' : '');
        }
        $lines[] = 'group ' . ($index + 1) . ' objects ' . $pair[0] . ' words ' . $pair[1] .
            ' cycle ' . $cyclic . ' died ' . $died . ' ids ' . implode(' ', $ids);
    }
    return $lines;
}

class ReferenceCount extends MarkSweep
{
    public int $increments = 0;
    public int $decrements = 0;
    public array $cascades = [];
    public array $leaks = [];

    public function __construct(object $heap, public object $run, public object $reference)
    {
        parent::__construct($heap);
        $this->kind = 'backup';
    }

    public function retain(?object $value): void
    {
        if ($value !== null) {
            $value->references++;
            $this->increments++;
        }
    }

    public function release(?object $value, object $cascade): void
    {
        $pending = [$value];
        while ($pending) {
            $object = array_pop($pending);
            if ($object === null) {
                continue;
            }
            $object->references--;
            $this->decrements++;
            if ($object->references !== 0) {
                continue;
            }
            unset($this->heap->objects[$object->number]);
            addObject($cascade->freed, $object);
            $cascade->work += 1 + $object->pointers;
            for ($field = count($object->fields) - 1; $field >= 0; $field--) {
                $pending[] = $object->fields[$field];
            }
        }
    }

    public function collect(object $record): void
    {
        $marked = mark($this->heap, $record);
        $garbage = array_values(array_filter($this->heap->objects, fn($object) => !isset($marked[$object->number])));
        $this->leaks[] = leakReport('backup ' . (count($this->run->records) + 1) . ' line ' . $record->line, $garbage, $this->reference);
        $freed = sweep($this->heap, $marked, $record);
        foreach ($freed as $object) {
            foreach ($object->fields as $value) {
                if ($value !== null && isset($marked[$value->number])) {
                    $value->references--;
                    $this->decrements++;
                }
            }
        }
    }

    public function finish(): void
    {
        $live = reachable($this->heap->roots);
        $garbage = array_values(array_filter($this->heap->objects, fn($object) => !isset($live[$object->number])));
        $this->leaks[] = leakReport('end', $garbage, $this->reference);
    }
}

class Timeline
{
    public array $segments = [];
    public int $length = 0;
    public int $mutator = 0;

    public function append(int $length, bool $mutator): void
    {
        if ($length === 0) {
            return;
        }
        $index = count($this->segments) - 1;
        if ($index >= 0 && $this->segments[$index]->mutator === $mutator) {
            $this->segments[$index]->end += $length;
        } else {
            $this->segments[] = (object) ['start' => $this->length, 'end' => $this->length + $length,
                'before' => $this->mutator, 'mutator' => $mutator];
        }
        $this->length += $length;
        if ($mutator) {
            $this->mutator += $length;
        }
    }

    public function prefix(int $time): int
    {
        if ($time === $this->length) {
            return $this->mutator;
        }
        $low = 0;
        $high = count($this->segments);
        while ($low < $high) {
            $middle = intdiv($low + $high, 2);
            if ($this->segments[$middle]->end <= $time) {
                $low = $middle + 1;
            } else {
                $high = $middle;
            }
        }
        $segment = $this->segments[$low];
        return $segment->before + ($segment->mutator ? $time - $segment->start : 0);
    }

    public function minimum(int $width): string
    {
        if ($width > $this->length) {
            return '-';
        }
        $last = $this->length - $width;
        $starts = [0 => true, $last => true];
        foreach ($this->segments as $segment) {
            foreach ([$segment->end, $segment->end - $width] as $start) {
                if ($start >= 0 && $start <= $last) {
                    $starts[$start] = true;
                }
            }
        }
        $minimum = $width;
        foreach (array_keys($starts) as $start) {
            $minimum = min($minimum, $this->prefix($start + $width) - $this->prefix($start));
        }
        return pct($minimum, $width);
    }
}

function observe(object $run, object $checkpoint, object $settings): array
{
    $objects = array_values($run->heap->objects);
    $live = array_values(array_filter($objects, fn($object) => isset($checkpoint->ids[$object->number])));
    $garbage = array_values(array_filter($objects, fn($object) => !isset($checkpoint->ids[$object->number])));
    $blocks = $run->collector->freeList();
    [$total, $largest] = freeAmount($blocks);
    $sizes = array_map(fn($block) => $block->length, $blocks);
    $lines = ['heap objects ' . pairText(objectPair($objects)) . ' reachable ' . pairText(objectPair($live)) . ' garbage ' . pairText(objectPair($garbage)),
        'free total ' . $total . ' largest ' . $largest . ' blocks ' . count($blocks) .
            ' sizes ' . classTable($sizes) . ' fragmentation ' . pct($total - $largest, $total)];
    $pointers = $forward = $backward = $distance = 0;
    foreach ($live as $object) {
        foreach ($object->fields as $value) {
            if ($value === null) {
                continue;
            }
            $pointers++;
            $forward += (int) ($value->address > $object->address);
            $backward += (int) ($value->address < $object->address);
            $distance += abs($value->address - $object->address);
        }
    }
    $lines[] = 'locality pointers ' . $pointers . ' forward ' . $forward . ' backward ' . $backward .
        ' mean_distance ' . ($pointers === 0 ? '-' : dec2($distance, $pointers));
    if ($run->definition->type === 'GENERATIONAL') {
        $young = array_values(array_filter($objects, fn($object) => $object->address < $run->definition->young));
        $old = array_values(array_filter($objects, fn($object) => $object->address >= $run->definition->young));
        $ages = [0, 0, 0, 0];
        foreach ($young as $object) {
            $ages[min($object->age, 3)]++;
        }
        $lines[] = 'generations young ' . pairText(objectPair($young)) . ' old ' . pairText(objectPair($old)) .
            ' remembered ' . count($run->collector->remembered) . ' ages 0:' . $ages[0] . ' 1:' . $ages[1] . ' 2:' . $ages[2] . ' 3+:' . $ages[3];
    }
    if (isset($settings->maps[$checkpoint->label])) {
        array_push($lines, ...heapMap($run->heap, $run->collector, $checkpoint->ids, $settings->width));
    }
    return $lines;
}

class Run
{
    public object $heap;
    public object $collector;
    public ?ReferenceCount $refcount = null;
    public array $created = [];
    public array $records = [];
    public array $pauses = [];
    public Timeline $timeline;
    public array $observations = [];
    public ?object $outOfMemory = null;
    public int $peakUsed = 0;

    public function __construct(public object $settings, public object $definition, public object $reference)
    {
        $this->heap = (object) ['size' => $settings->heap, 'objects' => [], 'roots' => []];
        $this->timeline = new Timeline();
        $this->collector = match ($definition->type) {
            'MARK_SWEEP' => new MarkSweep($this->heap),
            'MARK_COMPACT' => new MarkCompact($this->heap),
            'COPYING' => new Copying($this->heap),
            'GENERATIONAL' => new Generational($this->heap, $definition->young, $definition->age),
            'REFCOUNT' => new ReferenceCount($this->heap, $this, $reference)
        };
        if ($definition->type === 'REFCOUNT') {
            $this->refcount = $this->collector;
        }
    }

    public function recordCollection(object $record): void
    {
        $record->number = count($this->records) + 1;
        $this->records[] = $record;
        $this->pauses[] = (object) ['line' => $record->line, 'work' => $record->work, 'freed' => $record->freed, 'collection' => true];
        $this->timeline->append($record->work, false);
    }

    public function push(?object $value): void
    {
        if ($this->refcount !== null) {
            $this->refcount->retain($value);
        }
        $this->heap->roots[] = $value;
    }

    public function release(?object $value, object $cascade): void
    {
        if ($this->refcount !== null) {
            $this->refcount->release($value, $cascade);
        }
    }

    public function execute(object $command): bool
    {
        $cascade = (object) ['line' => $command->line, 'freed' => [0, 0], 'work' => 0, 'collection' => false];
        $units = 1;
        switch ($command->op) {
            case 'ALLOC':
                $units = 1 + $command->p + $command->d;
                $address = $this->collector->allocate($units, $command->line, function ($record): void { $this->recordCollection($record); });
                if ($address === null) {
                    $this->outOfMemory = (object) ['line' => $command->line, 'request' => $units];
                    return false;
                }
                $object = createObject($command->number, $command->p, $command->d);
                $object->address = $address;
                $this->heap->objects[$object->number] = $object;
                $this->created[] = $object;
                $this->push($object);
                $this->peakUsed = max($this->peakUsed, objectPair($this->heap->objects)[1]);
                break;
            case 'PUSH':
                $this->push(slotValue($this->heap->roots, $command->r));
                break;
            case 'LOAD':
                $this->push($this->heap->roots[$command->i]->fields[$command->f]);
                break;
            case 'POP':
                for ($index = 0; $index < $command->n; $index++) {
                    $this->release(array_pop($this->heap->roots), $cascade);
                }
                break;
            case 'SET':
                $object = $this->heap->roots[$command->i];
                $before = $object->fields[$command->f];
                $value = slotValue($this->heap->roots, $command->r);
                if ($this->definition->type === 'GENERATIONAL') {
                    $this->collector->writeBarrier($object, $value);
                }
                if ($this->refcount !== null) {
                    $this->refcount->retain($value);
                }
                $object->fields[$command->f] = $value;
                $this->release($before, $cascade);
                break;
            case 'OVERWRITE':
                $before = $this->heap->roots[$command->i];
                $value = slotValue($this->heap->roots, $command->r);
                if ($this->refcount !== null) {
                    $this->refcount->retain($value);
                }
                $this->heap->roots[$command->i] = $value;
                $this->release($before, $cascade);
                break;
            case 'CHECKPOINT':
                break;
        }
        $this->timeline->append($units, true);
        if ($cascade->freed[0] > 0) {
            $this->refcount->cascades[] = $cascade;
            $this->pauses[] = $cascade;
            $this->timeline->append($cascade->work, false);
        }
        if ($command->op === 'CHECKPOINT') {
            $checkpoint = $this->reference->checkpointByLine[$command->line];
            $this->observations[$command->label] = observe($this, $checkpoint, $this->settings);
        }
        return true;
    }

    public function simulate(): void
    {
        foreach ($this->reference->commands as $command) {
            if (!$this->execute($command)) {
                break;
            }
        }
        if ($this->outOfMemory === null && $this->refcount !== null) {
            $this->refcount->finish();
        }
    }
}

function pauseStatistics(array $pauses): object
{
    $work = array_map(fn($pause) => $pause->work, $pauses);
    sort($work, SORT_NUMERIC);
    $quantile = fn($percent) => $work ? $work[intdiv($percent * count($work) + 99, 100) - 1] : '-';
    return (object) ['work' => sumBy($pauses, fn($pause) => $pause->work),
        'freed' => sumBy($pauses, fn($pause) => $pause->freed[1]), 'p50' => $quantile(50), 'p90' => $quantile(90),
        'maximum' => $work ? $work[count($work) - 1] : 0];
}

function collectorStatistics(Run $run): array
{
    $stats = pauseStatistics($run->pauses);
    $lines = ['totals collections ' . count($run->records) . ' pauses ' . count($run->pauses) . ' work ' . $stats->work .
        ' freed ' . $stats->freed . ' pause p50 ' . $stats->p50 . ' p90 ' . $stats->p90 . ' max ' . $stats->maximum];
    $windows = [];
    foreach ($run->settings->windows as $width) {
        $windows[] = $width . ':' . $run->timeline->minimum($width);
    }
    $lines[] = 'utilization ' . pct($run->timeline->mutator, $run->timeline->length) . ' mmu ' . implode(' ', $windows);
    if ($run->definition->type === 'GENERATIONAL') {
        $kinds = [];
        foreach (['minor', 'major', 'tenure', 'full'] as $kind) {
            $records = array_values(array_filter($run->records, fn($record) => $record->kind === $kind));
            $kinds[] = $kind . ' ' . count($records) . ' ' . sumBy($records, fn($record) => $record->work);
        }
        $promoted = sumPairs($run->records, fn($record) => $record->promoted);
        $lines[] = 'generational ' . implode(' ', $kinds) . ' promoted ' . pairText($promoted) .
            ' barrier ' . $run->collector->barriers . ' remembered ' . $run->collector->remembers;
    }
    if ($run->refcount !== null) {
        $rc = $run->refcount;
        $freed = sumPairs($rc->cascades, fn($cascade) => $cascade->freed);
        $largest = null;
        foreach ($rc->cascades as $cascade) {
            if ($largest === null || $cascade->work > $largest->work) {
                $largest = $cascade;
            }
        }
        $detail = $largest === null ? '0 0 line -' : $largest->freed[0] . ' ' . $largest->work . ' line ' . $largest->line;
        $lines[] = 'refcount increments ' . $rc->increments . ' decrements ' . $rc->decrements .
            ' cascades ' . count($rc->cascades) . ' freed ' . pairText($freed) . ' max_cascade ' . $detail;
    }
    $previous = 0;
    foreach ($run->reference->checkpoints as $checkpoint) {
        if (!isset($run->observations[$checkpoint->label])) {
            $lines[] = 'phase ' . $checkpoint->label . ' out_of_memory';
        } else {
            $pauses = array_values(array_filter($run->pauses, fn($pause) => $pause->line > $previous && $pause->line <= $checkpoint->line));
            $phase = pauseStatistics($pauses);
            $collections = count(array_filter($pauses, fn($pause) => $pause->collection));
            $lines[] = 'phase ' . $checkpoint->label . ' collections ' . $collections . ' pauses ' . count($pauses) .
                ' work ' . $phase->work . ' freed ' . $phase->freed . ' max_pause ' . $phase->maximum;
        }
        $previous = $checkpoint->line;
    }
    $lines[] = $run->outOfMemory === null ? 'status completed' :
        'status out_of_memory line ' . $run->outOfMemory->line . ' size ' . $run->outOfMemory->request;
    return $lines;
}

function collectionReport(Run $run): array
{
    $lines = ['collector ' . $run->definition->name . ' ' . $run->definition->type];
    foreach ($run->records as $record) {
        $lines[] = $record->number . ' line ' . $record->line . ' size ' . $record->request . ' kind ' . $record->kind .
            ' live ' . pairText($record->live) . ' freed ' . pairText($record->freed) . ' moved ' . pairText($record->moved) .
            ' promoted ' . pairText($record->promoted) . ' stack ' . $record->stack . ' work ' . $record->work .
            ' before ' . pairText($record->before) . ' after ' . pairText($record->after);
    }
    array_push($lines, ...collectorStatistics($run));
    return $lines;
}

function summaryRow(Run $run): string
{
    $stats = pauseStatistics($run->pauses);
    $movedObjects = $maxMoves = 0;
    foreach ($run->created as $object) {
        if ($object->moves > 0) {
            $movedObjects++;
        }
        $maxMoves = max($maxMoves, $object->moves);
    }
    $row = [$run->definition->name, $run->definition->type, $run->outOfMemory === null ? 'completed' : 'out_of_memory',
        count($run->records), count($run->pauses), sumBy($run->records, fn($record) => $record->live[0]),
        sumBy($run->records, fn($record) => $record->moved[0]), $movedObjects, $maxMoves,
        $stats->freed, $stats->work, $stats->p50, $stats->p90, $stats->maximum, $run->peakUsed];
    if ($run->outOfMemory !== null) {
        array_push($row, '-', '-', '-', '-');
    } else {
        [$total, $largest] = freeAmount($run->collector->freeList());
        array_push($row, objectPair($run->heap->objects)[1], $total, $largest, pct($total - $largest, $total));
    }
    return implode(',', $row);
}

function writeReports(object $reference, array $runs): void
{
    $maps = [];
    foreach ($reference->checkpoints as $checkpoint) {
        foreach ($runs as $run) {
            $header = 'checkpoint ' . $checkpoint->label . ' line ' . $checkpoint->line . ' collector ' . $run->definition->name;
            $maps[] = implode("\n", array_merge([$header], $run->observations[$checkpoint->label] ?? ['out_of_memory']));
        }
    }
    $leaks = [];
    foreach ($runs as $run) {
        if ($run->refcount === null) {
            continue;
        }
        $lines = ['collector ' . $run->definition->name];
        foreach ($run->refcount->leaks as $report) {
            array_push($lines, ...$report);
        }
        if ($run->outOfMemory !== null) {
            $lines[] = 'status out_of_memory';
        }
        $leaks[] = implode("\n", $lines);
    }
    $header = 'collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation';
    $collections = array_map(fn($run) => implode("\n", collectionReport($run)), $runs);
    $summary = array_map(fn($run) => summaryRow($run), $runs);
    $reports = ['mutator.txt' => implode("\n", mutatorReport($reference)), 'heap_maps.txt' => implode("\n\n", $maps),
        'collections.txt' => implode("\n\n", $collections), 'summary.csv' => implode("\n", array_merge([$header], $summary)),
        'leaks.txt' => $leaks ? implode("\n\n", $leaks) : 'none'];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($reports as $name => $text) {
        file_put_contents('output/' . $name, $text === '' ? '' : $text . "\n");
    }
}

$input = readInputs();
$reference = analyzeScript($input->lines);
$runs = [];
foreach ($input->settings->collectors as $definition) {
    $run = new Run($input->settings, $definition, $reference);
    $run->simulate();
    $runs[] = $run;
}
writeReports($reference, $runs);
