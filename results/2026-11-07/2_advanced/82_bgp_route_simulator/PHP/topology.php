<?php

function addressValue(string $text): int
{
    $value = 0;
    foreach (explode('.', $text) as $octet)
        $value = ($value << 8) + (int) $octet;
    return $value;
}

function addressText(int $value): string
{
    return implode('.', array_map(fn($s) => ($value >> $s) & 255, [24, 16, 8, 0]));
}

function parsePrefix(string $text): array
{
    static $cache = [];
    if (!isset($cache[$text])) {
        [$address, $length] = explode('/', $text);
        $cache[$text] = [addressValue($address), (int) $length];
    }
    return $cache[$text];
}

function prefixContains(string $prefix, int $address): bool
{
    [$value, $length] = parsePrefix($prefix);
    return ($address >> (32 - $length)) === ($value >> (32 - $length));
}

function prefixCompare(string $a, string $b): int
{
    return parsePrefix($a) <=> parsePrefix($b);
}

function orderedPrefixes(array $names): array
{
    $names = array_values(array_unique($names));
    usort($names, prefixCompare(...));
    return $names;
}

final class Link
{
    public bool $up = true;
    public int $downCount = 0;

    public function __construct(
        public int $number,
        public string $name,
        public int $first,
        public int $second,
        public string $relationship,
        public int $delay,
        public int $mrai,
    ) {}

    public function other(int $owner): int
    {
        return $owner === $this->first ? $this->second : $this->first;
    }

    public function role(int $owner): string
    {
        return $this->relationship === 'P2P' ? 'peer' : ($owner === $this->first ? 'customer' : 'provider');
    }

    public function direction(int $owner): string
    {
        return ['customer' => 'D', 'peer' => 'P', 'provider' => 'U'][$this->role($owner)];
    }
}

final class Topology
{
    public array
        $routerIds = [],
        $ases = [],
        $links = [],
        $byName = [],
        $atAS = [],
        $between = [],
        $initial = []
    ;

    public function __construct()
    {
        foreach (file('input/topology.txt', FILE_IGNORE_NEW_LINES) as $line) {
            $f = explode(' ', $line);
            if ($f[0] === 'AS')
                $this->routerIds[(int) $f[1]] = addressValue($f[2]);
            elseif ($f[0] === 'LINK') {
                $link = new Link(
                    count($this->links),
                    $f[1],
                    (int) $f[2],
                    (int) $f[3],
                    $f[4],
                    (int) $f[5],
                    (int) $f[6],
                );
                $this->links[] = $link;
                $this->byName[$link->name] = $link;
                $this->atAS[$link->first][] = $link;
                $this->atAS[$link->second][] = $link;
                $this->between[min($link->first, $link->second) . ':' . max($link->first, $link->second)][] =
                    $link;
            } else
                $this->initial[] = [(int) $f[1], $f[2], $f[3], array_slice($f, 4)];
        }
        $this->ases = array_keys($this->routerIds);
        sort($this->ases, SORT_NUMERIC);
    }

    public function connecting(int $a, int $b): array
    {
        return $this->between[min($a, $b) . ':' . max($a, $b)];
    }
}
