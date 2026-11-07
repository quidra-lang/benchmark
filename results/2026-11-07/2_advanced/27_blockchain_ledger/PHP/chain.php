<?php

require_once __DIR__ . '/blocks.php';

class StoredBlock
{
    public int $work;

    public function __construct(
        public Block $block, public ?StoredBlock $parent, public array $utxo,
        public int $fees, public array $transactionFees, public string $source
    ) {
        $this->work = $parent === null ? 1 : $parent->work + 16 ** $block->difficulty;
    }
}

function reward(int $height, array $settings): int
{
    $value = $settings['reward'];
    for ($i = 0; $i < intdiv($height, $settings['halving']); $i++) {
        $value = intdiv($value, 2);
    }
    return $value;
}

function ancestor(StoredBlock $block, int $height): StoredBlock
{
    while ($block->block->height > $height) {
        $block = $block->parent;
    }
    return $block;
}

function chainSequence(StoredBlock $tip): array
{
    $chain = [];
    for ($current = $tip; $current !== null; $current = $current->parent) {
        $chain[] = $current;
    }
    return array_reverse($chain);
}

function forkPoint(StoredBlock $first, StoredBlock $second): StoredBlock
{
    $height = min($first->block->height, $second->block->height);
    $first = ancestor($first, $height);
    $second = ancestor($second, $height);
    while ($first->block->hash !== $second->block->hash) {
        $first = $first->parent;
        $second = $second->parent;
    }
    return $first;
}

function medianTime(StoredBlock $block): int
{
    $times = [];
    for ($i = 0; $i < 3 && $block !== null; $i++, $block = $block->parent) {
        $times[] = $block->block->timestamp;
    }
    sort($times, SORT_NUMERIC);
    return $times[intdiv(count($times) - 1, 2)];
}

function requiredDifficulty(StoredBlock $parent, array $settings): int
{
    $height = $parent->block->height + 1;
    if ($height === 1) {
        return $settings['difficulty'];
    }
    if ($height % $settings['retarget'] !== 0) {
        return $parent->block->difficulty;
    }
    $earlier = ancestor($parent, $height - $settings['retarget']);
    $span = $parent->block->timestamp - $earlier->block->timestamp;
    $expected = $settings['targetTime'] * ($settings['retarget'] - 1);
    if (2 * $span < $expected) {
        return min($parent->block->difficulty + 1, 2);
    }
    if ($span > 2 * $expected) {
        return max($parent->block->difficulty - 1, 0);
    }
    return $parent->block->difficulty;
}
