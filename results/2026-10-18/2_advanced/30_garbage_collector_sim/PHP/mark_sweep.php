<?php

require_once __DIR__ . '/heap.php';

function mark(object $heap, object $record): array
{
    $marked = [];
    $stack = [];
    $record->work += count($heap->roots);
    $push = function (?object $object) use (&$marked, &$stack, $record): void {
        if ($object === null || isset($marked[$object->number])) {
            return;
        }
        $marked[$object->number] = true;
        $stack[] = $object;
        $record->stack = max($record->stack, count($stack));
    };
    foreach ($heap->roots as $root) {
        $push($root);
        while ($stack) {
            $object = array_pop($stack);
            addObject($record->live, $object);
            $record->work += 1 + $object->pointers;
            foreach ($object->fields as $value) {
                $push($value);
            }
        }
    }
    return $marked;
}

function sweep(object $heap, array $marked, object $record, ?callable $selected = null): array
{
    $objects = $selected === null ? array_values($heap->objects) : array_values(array_filter($heap->objects, $selected));
    $record->work += count($objects);
    $freed = [];
    foreach ($objects as $object) {
        if (isset($marked[$object->number])) {
            continue;
        }
        unset($heap->objects[$object->number]);
        addObject($record->freed, $object);
        $freed[] = $object;
    }
    return $freed;
}

class MarkSweep
{
    public string $kind = 'sweep';

    public function __construct(public object $heap) {}

    public function freeList(): array
    {
        return freeBlocks($this->heap->objects, 0, $this->heap->size);
    }

    public function claim(int $size): ?int
    {
        return firstFit($this->freeList(), $size);
    }

    public function collect(object $record): void
    {
        $marked = mark($this->heap, $record);
        sweep($this->heap, $marked, $record);
    }

    public function allocate(int $size, int $line, callable $recordCollection): ?int
    {
        $address = $this->claim($size);
        if ($address !== null) {
            return $address;
        }
        $record = collectionRecord($line, $size, $this->kind, $this->freeList());
        $this->collect($record);
        $record->after = freeAmount($this->freeList());
        $recordCollection($record);
        return $this->claim($size);
    }
}

class MarkCompact extends MarkSweep
{
    public int $top = 0;
    public string $kind = 'compact';

    public function freeList(): array
    {
        return $this->top < $this->heap->size ? [(object) ['address' => $this->top, 'length' => $this->heap->size - $this->top]] : [];
    }

    public function claim(int $size): ?int
    {
        if ($this->top + $size > $this->heap->size) {
            return null;
        }
        $address = $this->top;
        $this->top += $size;
        return $address;
    }

    public function collect(object $record): void
    {
        $marked = mark($this->heap, $record);
        $objects = array_values($this->heap->objects);
        usort($objects, fn($a, $b) => $a->address <=> $b->address);
        $record->work += count($objects) + count($this->heap->roots);
        $destination = 0;
        foreach ($objects as $object) {
            if (!isset($marked[$object->number])) {
                unset($this->heap->objects[$object->number]);
                addObject($record->freed, $object);
                continue;
            }
            $record->work += $object->pointers;
            if ($object->address !== $destination) {
                addObject($record->moved, $object);
                $record->work += $object->size;
                $object->address = $destination;
                $object->moves++;
            }
            $destination += $object->size;
        }
        $this->top = $destination;
    }
}
