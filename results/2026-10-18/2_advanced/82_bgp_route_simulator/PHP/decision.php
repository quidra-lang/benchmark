<?php

final readonly class RouteAttributes
{
    public function __construct(
        public array $path,
        public string $origin,
        public int $med,
        public array $communities,
    ) {}
}

final readonly class Route
{
    public function __construct(
        public array $path,
        public string $origin,
        public int $med,
        public array $communities,
        public ?int $localPref,
        public ?Link $link,
    ) {}

    public static function originated(string $origin, array $communities): self
    {
        return new self([], $origin, 0, $communities, null, null);
    }

    public function local(): bool
    {
        return $this->link === null;
    }

    public function neighbor(): int
    {
        return $this->path[0];
    }
}

function bestRoute(array $routes, array $routerIds): array
{
    if (count($routes) === 1)
        return [$routes[0], 'ONLY'];
    $origin = ['IGP' => 0, 'EGP' => 1, 'INCOMPLETE' => 2];
    $stages = [
        'LOCALPREF' => fn($r) => -$r->localPref,
        'ASPATH' => fn($r) => count($r->path),
        'ORIGIN' => fn($r) => $origin[$r->origin],
        'MED' => null,
        'ROUTERID' => fn($r) => $routerIds[$r->neighbor()],
        'LINK' => fn($r) => $r->link->number,
    ];
    foreach ($stages as $reason => $key) {
        if ($reason === 'MED') {
            $minima = [];
            foreach ($routes as $r)
                $minima[$r->neighbor()] = min($minima[$r->neighbor()] ?? $r->med, $r->med);
            $routes = array_values(array_filter($routes, fn($r) => $r->med === $minima[$r->neighbor()]));
        } else {
            $minimum = min(array_map($key, $routes));
            $routes = array_values(array_filter($routes, fn($r) => $key($r) === $minimum));
        }
        if (count($routes) === 1)
            return [$routes[0], $reason];
    }
    throw new LogicException('No unique route');
}
