<?php

require_once __DIR__ . '/heap.php';

class Copying
{
    public int $half;
    public int $base = 0;
    public int $top = 0;

    public function __construct(public object $heap)
    {
        $this->half = intdiv($heap->size, 2);
    }

    public function freeList(): array
    {
        $length = $this->base + $this->half - $this->top;
        return $length > 0 ? [(object) ['address' => $this->top, 'length' => $length]] : [];
    }

    public function claim(int $size): ?int
    {
        if ($this->top + $size > $this->base + $this->half) {
            return null;
        }
        $address = $this->top;
        $this->top += $size;
        return $address;
    }

    public function collect(object $record): void
    {
        $this->base = $this->half - $this->base;
        $this->top = $this->base;
        $copied = [];
        $queue = [];
        $copy = function (?object $object) use (&$copied, &$queue, $record): void {
            if ($object === null || isset($copied[$object->number])) {
                return;
            }
            $copied[$object->number] = true;
            $object->address = $this->top;
            $this->top += $object->size;
            $object->moves++;
            addObject($record->live, $object);
            addObject($record->moved, $object);
            $queue[] = $object;
        };
        $record->work += count($this->heap->roots);
        foreach ($this->heap->roots as $root) {
            $copy($root);
        }
        for ($index = 0; $index < count($queue); $index++) {
            $object = $queue[$index];
            $record->work += $object->size + $object->pointers;
            foreach ($object->fields as $value) {
                $copy($value);
            }
        }
        foreach ($this->heap->objects as $object) {
            if (!isset($copied[$object->number])) {
                unset($this->heap->objects[$object->number]);
                addObject($record->freed, $object);
            }
        }
    }

    public function allocate(int $size, int $line, callable $recordCollection): ?int
    {
        $address = $this->claim($size);
        if ($address !== null) {
            return $address;
        }
        $record = collectionRecord($line, $size, 'copy', $this->freeList());
        $this->collect($record);
        $record->after = freeAmount($this->freeList());
        $recordCollection($record);
        return $this->claim($size);
    }
}
