<?php

require_once __DIR__ . '/mark_sweep.php';

class Generational
{
    public int $half;
    public int $base = 0;
    public int $top = 0;
    public array $remembered = [];
    public int $barriers = 0;
    public int $remembers = 0;

    public function __construct(public object $heap, public int $young, public int $promotionAge)
    {
        $this->half = intdiv($young, 2);
    }

    public function oldBlocks(): array
    {
        return freeBlocks($this->heap->objects, $this->young, $this->heap->size);
    }

    public function freeList(): array
    {
        $blocks = $this->oldBlocks();
        $length = $this->base + $this->half - $this->top;
        if ($length > 0) {
            array_unshift($blocks, (object) ['address' => $this->top, 'length' => $length]);
        }
        return $blocks;
    }

    public function writeBarrier(object $object, ?object $value): void
    {
        if ($object->address < $this->young) {
            return;
        }
        $this->barriers++;
        if ($value !== null && $value->address < $this->young && !isset($this->remembered[$object->number])) {
            $this->remembered[$object->number] = $object;
            $this->remembers++;
        }
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

    public function collect(object $record): bool
    {
        $major = $record->kind === 'major' || $record->kind === 'full';
        if ($major) {
            $marked = mark($this->heap, $record);
            $freed = sweep($this->heap, $marked, $record, fn($object) => $object->address >= $this->young);
            foreach ($freed as $object) {
                unset($this->remembered[$object->number]);
            }
        }
        $remaining = [];
        foreach ($this->heap->objects as $object) {
            if ($object->address < $this->young) {
                $remaining[$object->number] = $object;
            }
        }
        $destination = $this->half - $this->base;
        $top = $destination;
        $queue = [];
        $evacuate = function (?object $object) use (&$remaining, &$top, &$queue, $record, $major): bool {
            if ($object === null || !isset($remaining[$object->number])) {
                return true;
            }
            unset($remaining[$object->number]);
            $object->age++;
            $object->moves++;
            if ($record->kind === 'tenure' || $record->kind === 'full' || $object->age >= $this->promotionAge) {
                $address = firstFit($this->oldBlocks(), $object->size);
                if ($address === null) {
                    return false;
                }
                $object->address = $address;
                addObject($record->promoted, $object);
            } else {
                $object->address = $top;
                $top += $object->size;
            }
            addObject($record->moved, $object);
            if (!$major) {
                addObject($record->live, $object);
            }
            $queue[] = $object;
            return true;
        };
        $record->work += count($this->heap->roots);
        foreach ($this->heap->roots as $root) {
            if (!$evacuate($root)) {
                return false;
            }
        }
        $remembered = array_values($this->remembered);
        usort($remembered, fn($a, $b) => $a->address <=> $b->address);
        foreach ($remembered as $object) {
            $record->work += 1 + $object->pointers;
            foreach ($object->fields as $value) {
                if (!$evacuate($value)) {
                    return false;
                }
            }
        }
        for ($index = 0; $index < count($queue); $index++) {
            $object = $queue[$index];
            $record->work += $object->size + $object->pointers;
            foreach ($object->fields as $value) {
                if (!$evacuate($value)) {
                    return false;
                }
            }
        }
        foreach ($remaining as $object) {
            unset($this->heap->objects[$object->number]);
            addObject($record->freed, $object);
        }
        $this->base = $destination;
        $this->top = $top;
        $this->remembered = [];
        foreach ($this->heap->objects as $object) {
            if ($object->address >= $this->young) {
                foreach ($object->fields as $value) {
                    if ($value !== null && $value->address < $this->young) {
                        $this->remembered[$object->number] = $object;
                        break;
                    }
                }
            }
        }
        return true;
    }

    public function allocate(int $size, int $line, callable $recordCollection): ?int
    {
        $address = $this->claim($size);
        if ($address !== null) {
            return $address;
        }
        for ($attempt = 0; $attempt < 2; $attempt++) {
            $largest = freeAmount($this->oldBlocks())[1];
            $sweepOld = $largest < $this->top - $this->base;
            $kind = $attempt === 0 ? ($sweepOld ? 'major' : 'minor') : ($sweepOld ? 'full' : 'tenure');
            $record = collectionRecord($line, $size, $kind, $this->freeList());
            if (!$this->collect($record)) {
                return null;
            }
            $record->after = freeAmount($this->freeList());
            $recordCollection($record);
            $address = $this->claim($size);
            if ($address !== null) {
                return $address;
            }
        }
        return null;
    }
}
