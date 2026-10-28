<?php

final readonly class Bid
{
    public int $size;

    public function __construct(
        public int $number,
        public string $bidder,
        public int $bundle,
        public int $amount,
        public bool $xor,
    ) {
        $this->size = bitCount($bundle);
    }
}

function bitCount(int $mask): int
{
    return substr_count(decbin($mask), '1');
}

function inputRecords(string $name): array
{
    return array_map(fn($line) => explode(' ', $line), file('input/' . $name, FILE_IGNORE_NEW_LINES));
}

function readInputs(): array
{
    $names = $reserves = $indices = [];
    foreach (inputRecords('items.txt') as [$name, $reserve]) {
        $indices[$name] = count($names);
        $names[] = $name;
        $reserves[] = (int) $reserve;
    }
    $auctions = [];
    foreach (inputRecords('bids.txt') as $f) {
        if ($f[0] === 'auction') {
            $auction = (object) [
                'name' => $f[1],
                'items' => array_map(fn($s) => $indices[$s], array_slice($f, 2)),
                'lines' => [],
            ];
            $auctions[$f[1]] = $auction;
        } else
            $auction->lines[] = [$f[1], $f[2], array_slice($f, 3)];
    }
    $groups = [];
    foreach (inputRecords('single_item.txt') as $f) {
        if ($f[0] === 'lot' || $f[0] === 'slots') {
            $group = (object) [
                'kind' => $f[0],
                'name' => $f[1],
                'arguments' => array_slice($f, 2),
                'participants' => [],
            ];
            $groups[] = $group;
        } else
            $group->participants[] = ['name' => $f[1], 'value' => (int) $f[2], 'bid' => (int) $f[3]];
    }
    $parameters = [];
    foreach (inputRecords('params.txt') as $f)
        $parameters[$f[0]] = $f[0] === 'run' ? array_slice($f, 1) : (int) $f[1];
    return [$names, $reserves, $indices, $auctions, $groups, $parameters];
}
