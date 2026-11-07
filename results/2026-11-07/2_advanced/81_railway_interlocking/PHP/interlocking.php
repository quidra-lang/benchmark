<?php

function nameList(string $text): array
{
    return $text === '-' ? [] : explode(',', $text);
}

final class Interlocking
{
    public array $routes = [];

    public function __construct(
        public Layout $layout,
    ) {
        foreach (file('input/routes.txt', FILE_IGNORE_NEW_LINES) as $line) {
            $f = explode(' ', $line);
            array_shift($f);
            $positions = fn($s) => array_map(fn($part) => explode(':', $part), nameList($s));
            $route = (object) [
                'name' => $f[0],
                'start' => $f[1],
                'finish' => $f[2],
                'points' => $positions($f[3]),
                'sections' => nameList($f[4]),
                'overlap' => nameList($f[5]),
                'flank' => $positions($f[6]),
                'conflicts' => nameList($f[7]),
                'approachTime' => (int) $f[8],
                'direction' => $layout->signals[$f[1]]->direction,
                'state' => null,
                'releaseTime' => null,
                'passed' => [],
                'overlapLocked' => false,
                'overlapCounter' => 0,
                'requests' => 0,
                'grants' => 0,
                'uses' => 0,
                'cancels' => 0,
                'wait' => 0,
                'maxwait' => 0,
                'lockedSeconds' => 0,
            ];
            $route->requirements = [...$route->points, ...$route->flank];
            $this->routes[$route->name] = $route;
        }
    }

    public function lock(object $route): void
    {
        $route->state = 'LOCKED';
        $route->releaseTime = null;
        $route->passed = [];
        $route->overlapLocked = true;
        $route->overlapCounter = 0;
        foreach ($route->sections as $name)
            $this->layout->sections[$name]->routeLock = $route->name;
        foreach ($route->overlap as $name)
            $this->layout->sections[$name]->overlapLocks[$route->name] = true;
        foreach ($route->requirements as [$name, $position])
            $this->layout->points[$name]->locks[$route->name . ':' . $position] = [$route->name, $position];
    }

    public function unlockPoints(object $route, ?array $sections = null): void
    {
        foreach ($this->layout->points as $point)
            if ($sections === null || in_array($point->common, $sections, true)) {
                foreach ($point->locks as $key => [$name, $position])
                    if ($name === $route->name)
                        unset($point->locks[$key]);
            }
    }

    public function unlockSection(object $route, string $name): void
    {
        $section = $this->layout->sections[$name];
        if ($section->routeLock === $route->name)
            $section->routeLock = null;
        $this->unlockPoints($route, [$name]);
    }

    public function unlockOverlap(object $route): void
    {
        foreach ($route->overlap as $name)
            unset($this->layout->sections[$name]->overlapLocks[$route->name]);
        $this->unlockPoints($route, $route->overlap);
        $route->overlapLocked = false;
    }

    public function release(object $route): void
    {
        foreach ($route->sections as $name)
            if ($this->layout->sections[$name]->routeLock === $route->name)
                $this->layout->sections[$name]->routeLock = null;
        if ($route->overlapLocked)
            $this->unlockOverlap($route);
        $this->unlockPoints($route);
        $route->state = null;
        $route->releaseTime = null;
    }
}
