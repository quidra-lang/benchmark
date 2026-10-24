<?php
class RouteError extends Exception
{
}

class RouteWorkbench
{
    private ?array $depot = null;
    private int $departure = 480;
    private array $stops = [];
    private ?array $tour = null;
    private ?array $routes = null;
    private ?int $capacity = null;

    private function ids(): array
    {
        $ids = array_keys($this->stops);
        sort($ids, SORT_NUMERIC);
        return $ids;
    }

    private function name(int $id): string
    {
        return $id === 0 ? 'D' : (string)$id;
    }

    private function point(int $id): array
    {
        return $id === 0 ? $this->depot : [$this->stops[$id]['x'], $this->stops[$id]['y']];
    }

    private function distance(int $a, int $b): int
    {
        [$x, $y] = $this->point($a);
        [$u, $v] = $this->point($b);
        return abs($x - $u) + abs($y - $v);
    }

    private function length(array $route): int
    {
        $result = 0;
        $previous = 0;
        foreach ($route as $id) {
            $result += $this->distance($previous, $id);
            $previous = $id;
        }
        return $result + $this->distance($previous, 0);
    }

    private function load(array $route): int
    {
        $result = 0;
        foreach ($route as $id) {
            $result += $this->stops[$id]['demand'];
        }
        return $result;
    }

    private function notation(array $route): string
    {
        return implode('-', array_merge(['D'], $route, ['D']));
    }

    private function planLength(?array $routes = null): int
    {
        $result = 0;
        foreach ($routes ?? $this->routes as $route) {
            $result += $this->length($route);
        }
        return $result;
    }

    private function normalize(): void
    {
        $routes = [];
        foreach ($this->routes as $route) {
            if ($route === []) {
                continue;
            }
            if ($route[0] > $route[count($route) - 1]) {
                $route = array_reverse($route);
            }
            $routes[] = $route;
        }
        usort($routes, fn($a, $b) => min($a) <=> min($b));
        $this->routes = $routes;
    }

    private function routeLines(): void
    {
        foreach ($this->routes as $i => $route) {
            echo 'route ', $i + 1, ': ', $this->notation($route), ' load ', $this->load($route), ' length ', $this->length($route), "\n";
        }
    }

    private function clock(int $time): string
    {
        return sprintf('%02d:%02d', intdiv($time, 60), $time % 60);
    }

    private function minutes(string $text): int
    {
        [$hour, $minute] = array_map('intval', explode(':', $text));
        return $hour * 60 + $minute;
    }

    private function requireData(): void
    {
        if ($this->depot === null) {
            throw new RouteError('no depot');
        }
        if ($this->stops === []) {
            throw new RouteError('no stops');
        }
    }

    private function requireTour(): void
    {
        if ($this->tour === null) {
            throw new RouteError('no tour');
        }
    }

    private function requirePlan(): void
    {
        if ($this->routes === null) {
            throw new RouteError('no plan');
        }
    }

    private function checkCapacity(int $capacity): void
    {
        foreach ($this->ids() as $id) {
            if ($this->stops[$id]['demand'] > $capacity) {
                throw new RouteError("stop $id demand {$this->stops[$id]['demand']} exceeds capacity $capacity");
            }
        }
    }

    private function simulate(array $route, bool $output = false): array
    {
        $time = $this->departure;
        $previous = 0;
        $waiting = $service = $violations = $lateness = 0;
        foreach ($route as $id) {
            $stop = $this->stops[$id];
            $arrival = $time + $this->distance($previous, $id);
            $wait = $stop['open'] === null ? 0 : max(0, $stop['open'] - $arrival);
            $late = $stop['close'] === null ? 0 : max(0, $arrival - $stop['close']);
            $begin = $arrival + $wait;
            $time = $begin + $stop['service'];
            $waiting += $wait;
            $service += $stop['service'];
            $violations += $late > 0 ? 1 : 0;
            $lateness += $late;
            if ($output) {
                echo "$id arrive ", $this->clock($arrival), " wait $wait begin ", $this->clock($begin), ' leave ', $this->clock($time), ' ', $late > 0 ? "late $late" : 'ok', "\n";
            }
            $previous = $id;
        }
        $time += $this->distance($previous, 0);
        if ($output) {
            echo 'return ', $this->clock($time), ', travel ', $this->length($route), ", wait $waiting, service $service, violations $violations, lateness $lateness\n";
        }
        return [$time, $violations, $lateness];
    }

    private function exact(): array
    {
        $stops = $this->ids();
        $full = (1 << count($stops)) - 1;
        $memo = [];
        $solve = function (int $mask, int $previous) use (&$solve, &$memo, $stops, $full): int {
            if ($mask === $full) {
                return $this->distance($previous, 0);
            }
            $key = "$mask,$previous";
            if (isset($memo[$key])) {
                return $memo[$key];
            }
            $best = null;
            foreach ($stops as $i => $id) {
                if (($mask & (1 << $i)) === 0) {
                    $cost = $this->distance($previous, $id) + $solve($mask | (1 << $i), $id);
                    $best = $best === null ? $cost : min($best, $cost);
                }
            }
            return $memo[$key] = $best;
        };
        $route = [];
        $mask = $previous = 0;
        while ($mask !== $full) {
            $best = $solve($mask, $previous);
            foreach ($stops as $i => $id) {
                if (($mask & (1 << $i)) === 0 && $this->distance($previous, $id) + $solve($mask | (1 << $i), $id) === $best) {
                    $route[] = $id;
                    $mask |= 1 << $i;
                    $previous = $id;
                    break;
                }
            }
        }
        return $route;
    }

    private function tourMove(array $route, string $method): ?array
    {
        $old = $this->length($route);
        $n = count($route);
        if ($method === 'OROPT') {
            for ($size = 1; $size <= 3; $size++) {
                for ($i = 0; $i + $size <= $n; $i++) {
                    $segment = array_slice($route, $i, $size);
                    $remaining = $route;
                    array_splice($remaining, $i, $size);
                    for ($j = 0; $j <= count($remaining); $j++) {
                        if ($j === $i) {
                            continue;
                        }
                        $candidate = $remaining;
                        array_splice($candidate, $j, 0, $segment);
                        $gain = $old - $this->length($candidate);
                        if ($gain > 0) {
                            $after = $j === 0 ? 'D' : $remaining[$j - 1];
                            return [$candidate, 'move ' . implode('-', $segment) . " after $after gain $gain"];
                        }
                    }
                }
            }
        } else {
            for ($i = 0; $i < $n; $i++) {
                for ($j = $i + 1; $j < $n; $j++) {
                    $candidate = $route;
                    if ($method === 'TWOOPT') {
                        array_splice($candidate, $i, $j - $i + 1, array_reverse(array_slice($route, $i, $j - $i + 1)));
                    } else {
                        [$candidate[$i], $candidate[$j]] = [$candidate[$j], $candidate[$i]];
                    }
                    $gain = $old - $this->length($candidate);
                    if ($gain > 0) {
                        $message = $method === 'TWOOPT' ? "reverse {$route[$i]}..{$route[$j]} gain $gain" : "swap {$route[$i]} and {$route[$j]} gain $gain";
                        return [$candidate, $message];
                    }
                }
            }
        }
        return null;
    }

    private function improveTour(array $route, string $method, bool $output = true): array
    {
        $count = 0;
        while (($move = $this->tourMove($route, $method)) !== null) {
            [$route, $message] = $move;
            if ($output) {
                echo $message, "\n";
            }
            $count++;
        }
        return [$route, $count];
    }

    private function planMove(string $method): ?array
    {
        $before = $this->planLength();
        $k = count($this->routes);
        foreach ($this->routes as $r => $a) {
            if ($method === 'RELOCATE') {
                foreach ($a as $p => $c) {
                    foreach ($this->routes as $t => $b) {
                        if ($r === $t || $this->load($b) + $this->stops[$c]['demand'] > $this->capacity) {
                            continue;
                        }
                        for ($j = 0; $j <= count($b); $j++) {
                            $candidate = $this->routes;
                            array_splice($candidate[$r], $p, 1);
                            array_splice($candidate[$t], $j, 0, [$c]);
                            $gain = $before - $this->planLength($candidate);
                            if ($gain > 0) {
                                $after = $j === 0 ? 'D' : $b[$j - 1];
                                return [$candidate, 'relocate ' . $c . ' from route ' . ($r + 1) . ' to route ' . ($t + 1) . " after $after gain $gain"];
                            }
                        }
                    }
                }
            } else {
                for ($t = $r + 1; $t < $k; $t++) {
                    $b = $this->routes[$t];
                    if ($method === 'EXCHANGE') {
                        foreach ($a as $p => $c) {
                            foreach ($b as $j => $e) {
                                if ($this->load($a) - $this->stops[$c]['demand'] + $this->stops[$e]['demand'] > $this->capacity || $this->load($b) - $this->stops[$e]['demand'] + $this->stops[$c]['demand'] > $this->capacity) {
                                    continue;
                                }
                                $candidate = $this->routes;
                                $candidate[$r][$p] = $e;
                                $candidate[$t][$j] = $c;
                                $gain = $before - $this->planLength($candidate);
                                if ($gain > 0) {
                                    return [$candidate, "exchange $c (route " . ($r + 1) . ") with $e (route " . ($t + 1) . ") gain $gain"];
                                }
                            }
                        }
                    } else {
                        for ($i = 0; $i <= count($a); $i++) {
                            for ($j = 0; $j <= count($b); $j++) {
                                $left = array_merge(array_slice($a, 0, $i), array_slice($b, $j));
                                $right = array_merge(array_slice($b, 0, $j), array_slice($a, $i));
                                if ($this->load($left) > $this->capacity || $this->load($right) > $this->capacity) {
                                    continue;
                                }
                                $candidate = $this->routes;
                                $candidate[$r] = $left;
                                $candidate[$t] = $right;
                                $gain = $before - $this->planLength($candidate);
                                if ($gain > 0) {
                                    $x = $i === 0 ? 'D' : $a[$i - 1];
                                    $y = $j === 0 ? 'D' : $b[$j - 1];
                                    return [$candidate, 'cross route ' . ($r + 1) . " after $x with route " . ($t + 1) . " after $y gain $gain"];
                                }
                            }
                        }
                    }
                }
            }
        }
        return null;
    }

    private function bounds(): void
    {
        $tree = [0];
        $remaining = $this->ids();
        $edges = [];
        $mst = 0;
        while ($remaining !== []) {
            $best = null;
            foreach ($remaining as $id) {
                foreach ($tree as $i => $parent) {
                    $choice = [$this->distance($parent, $id), $id, $i];
                    if ($best === null || $choice < $best) {
                        $best = $choice;
                    }
                }
            }
            [$weight, $c, $order] = $best;
            $edges[] = $this->name($tree[$order]) . "-$c";
            $mst += $weight;
            $tree[] = $c;
            $remaining = array_values(array_diff($remaining, [$c]));
        }
        echo 'mst: ', implode(' ', $edges), " (length $mst)\n";
        $ids = $this->ids();
        if (count($ids) === 1) {
            $oneTree = 2 * $this->distance(0, $ids[0]);
        } else {
            $tree = [$ids[0]];
            $remaining = array_slice($ids, 1);
            $cost = 0;
            while ($remaining !== []) {
                $best = null;
                foreach ($remaining as $id) {
                    foreach ($tree as $parent) {
                        $choice = [$this->distance($parent, $id), $id];
                        if ($best === null || $choice < $best) {
                            $best = $choice;
                        }
                    }
                }
                [$weight, $c] = $best;
                $cost += $weight;
                $tree[] = $c;
                $remaining = array_values(array_diff($remaining, [$c]));
            }
            $distances = array_map(fn($id) => $this->distance(0, $id), $ids);
            sort($distances, SORT_NUMERIC);
            $oneTree = $cost + $distances[0] + $distances[1];
        }
        $best = max($mst, $oneTree);
        echo "bound: mst $mst, one-tree $oneTree, best $best\n";
        if ($this->tour === null) {
            echo "gap: no tour\n";
        } else {
            $value = $this->length($this->tour);
            $u = $best > 0 ? intdiv(2000 * ($value - $best) + $best, 2 * $best) : 0;
            echo "gap: tour $value, ", intdiv($u, 10), '.', $u % 10, "%\n";
        }
    }

    private function createPlan(string $command, array $args): void
    {
        $capacity = (int)$args[0];
        if ($command === 'SPLIT') {
            $this->requireTour();
        } else {
            $this->requireData();
        }
        $this->checkCapacity($capacity);
        $limit = $command === 'VRP' && isset($args[1]) ? (int)$args[1] : null;
        if ($limit !== null) {
            foreach ($this->ids() as $id) {
                if (2 * $this->distance(0, $id) > $limit) {
                    throw new RouteError("stop $id too far for limit $limit");
                }
            }
        }
        $merges = 0;
        if ($command === 'VRP') {
            $ids = $this->ids();
            $routes = array_map(fn($id) => [$id], $ids);
            $savings = [];
            foreach ($ids as $p => $i) {
                for ($q = $p + 1; $q < count($ids); $q++) {
                    $j = $ids[$q];
                    $saving = $this->distance(0, $i) + $this->distance(0, $j) - $this->distance($i, $j);
                    if ($saving > 0) {
                        $savings[] = [-$saving, $i, $j];
                    }
                }
            }
            usort($savings, fn($a, $b) => $a <=> $b);
            foreach ($savings as [, $i, $j]) {
                $r = $t = null;
                foreach ($routes as $index => $route) {
                    if (in_array($i, $route, true)) {
                        $r = $index;
                    }
                    if (in_array($j, $route, true)) {
                        $t = $index;
                    }
                }
                $a = $routes[$r];
                $b = $routes[$t];
                if ($r === $t || !in_array($i, [$a[0], $a[count($a) - 1]], true) || !in_array($j, [$b[0], $b[count($b) - 1]], true) || $this->load($a) + $this->load($b) > $capacity) {
                    continue;
                }
                $joined = array_merge($a[0] === $i ? array_reverse($a) : $a, $b[count($b) - 1] === $j ? array_reverse($b) : $b);
                if ($limit !== null && $this->length($joined) > $limit) {
                    continue;
                }
                $routes[$r] = $joined;
                array_splice($routes, $t, 1);
                $merges++;
            }
        } elseif ($command === 'SPLIT') {
            $values = [0];
            $parents = [];
            for ($j = 1; $j <= count($this->tour); $j++) {
                $best = null;
                for ($i = 0; $i < $j; $i++) {
                    $segment = array_slice($this->tour, $i, $j - $i);
                    if ($this->load($segment) <= $capacity) {
                        $choice = [$values[$i] + $this->length($segment), $i];
                        if ($best === null || $choice < $best) {
                            $best = $choice;
                        }
                    }
                }
                [$values[$j], $parents[$j]] = $best;
            }
            $routes = [];
            for ($j = count($this->tour); $j > 0; $j = $parents[$j]) {
                $routes[] = array_slice($this->tour, $parents[$j], $j - $parents[$j]);
            }
        } else {
            $sweep = $this->ids();
            usort($sweep, function ($a, $b) {
                [$ax, $ay] = $this->point($a);
                [$bx, $by] = $this->point($b);
                $ax -= $this->depot[0];
                $ay -= $this->depot[1];
                $bx -= $this->depot[0];
                $by -= $this->depot[1];
                $az = $ax === 0 && $ay === 0;
                $bz = $bx === 0 && $by === 0;
                if ($az || $bz) {
                    return $az === $bz ? $a <=> $b : ($az ? -1 : 1);
                }
                $ah = $ay > 0 || ($ay === 0 && $ax > 0) ? 0 : 1;
                $bh = $by > 0 || ($by === 0 && $bx > 0) ? 0 : 1;
                $cross = $ax * $by - $ay * $bx;
                if ($ah !== $bh) {
                    return $ah <=> $bh;
                }
                return $cross !== 0 ? 0 <=> $cross : [$this->distance(0, $a), $a] <=> [$this->distance(0, $b), $b];
            });
            $routes = [[]];
            foreach ($sweep as $id) {
                $last = count($routes) - 1;
                if ($this->load($routes[$last]) + $this->stops[$id]['demand'] > $capacity) {
                    $routes[] = [];
                    $last++;
                }
                $routes[$last][] = $id;
            }
        }
        $this->capacity = $capacity;
        $this->routes = $routes;
        $this->normalize();
        echo strtolower($command), ": capacity $capacity,", $command === 'VRP' ? " merges $merges," : '', ' routes ', count($this->routes), ', length ', $this->planLength(), "\n";
        $this->routeLines();
    }

    public function execute(string $line): void
    {
        $args = explode(' ', $line);
        $command = array_shift($args);
        try {
            switch ($command) {
                case 'DEPOT':
                    $this->depot = array_map('intval', $args);
                    echo 'depot at (', implode(',', $this->depot), ")\n";
                    break;
                case 'START':
                    $this->departure = $this->minutes($args[0]);
                    echo 'start ', $this->clock($this->departure), "\n";
                    break;
                case 'STOP':
                    [$id, $x, $y, $demand, $service] = array_map('intval', array_slice($args, 0, 5));
                    if (isset($this->stops[$id])) {
                        throw new RouteError("stop $id already exists");
                    }
                    $opening = isset($args[5]) ? $this->minutes($args[5]) : null;
                    $closing = isset($args[6]) ? $this->minutes($args[6]) : null;
                    if ($opening !== null && $opening > $closing) {
                        throw new RouteError('invalid window');
                    }
                    $this->stops[$id] = ['x' => $x, 'y' => $y, 'demand' => $demand, 'service' => $service, 'open' => $opening, 'close' => $closing];
                    $this->tour = $this->routes = null;
                    echo "stop $id added\n";
                    break;
                case 'REMOVE':
                    $id = (int)$args[0];
                    if (!isset($this->stops[$id])) {
                        throw new RouteError("unknown stop $id");
                    }
                    unset($this->stops[$id]);
                    if ($this->stops === []) {
                        $this->tour = $this->routes = null;
                    } else {
                        if ($this->tour !== null) {
                            $this->tour = array_values(array_diff($this->tour, [$id]));
                        }
                        if ($this->routes !== null) {
                            $this->routes = array_map(fn($route) => array_values(array_diff($route, [$id])), $this->routes);
                            $this->normalize();
                        }
                    }
                    echo "stop $id removed\n";
                    break;
                case 'LIST':
                    echo $this->depot === null ? 'depot none' : 'depot (' . implode(',', $this->depot) . ')', "\n";
                    echo 'start ', $this->clock($this->departure), "\nstops ", count($this->stops), "\n";
                    foreach ($this->ids() as $id) {
                        $s = $this->stops[$id];
                        $window = $s['open'] === null ? 'none' : $this->clock($s['open']) . '-' . $this->clock($s['close']);
                        echo "$id at ({$s['x']},{$s['y']}) demand {$s['demand']} service {$s['service']} window $window\n";
                    }
                    break;
                case 'MATRIX':
                    if ($this->depot === null) {
                        throw new RouteError('no depot');
                    }
                    $locations = array_merge([0], $this->ids());
                    $cells = [array_merge([''], array_map(fn($id) => $this->name($id), $locations))];
                    foreach ($locations as $a) {
                        $cells[] = array_merge([$this->name($a)], array_map(fn($b) => (string)$this->distance($a, $b), $locations));
                    }
                    $width = 0;
                    foreach ($cells as $row) {
                        foreach ($row as $cell) {
                            $width = max($width, strlen($cell));
                        }
                    }
                    foreach ($cells as $row) {
                        echo implode(' ', array_map(fn($s) => str_pad($s, $width, ' ', STR_PAD_LEFT), $row)), "\n";
                    }
                    break;
                case 'ORDER':
                case 'NEAREST':
                case 'INSERTION':
                case 'EXACT':
                    $this->requireData();
                    if ($command === 'ORDER') {
                        $route = array_map('intval', $args);
                        foreach ($route as $id) {
                            if (!isset($this->stops[$id])) {
                                throw new RouteError("unknown stop $id");
                            }
                        }
                        $seen = [];
                        foreach ($route as $id) {
                            if (isset($seen[$id])) {
                                throw new RouteError("duplicate stop $id");
                            }
                            $seen[$id] = true;
                        }
                        if (count($route) !== count($this->stops)) {
                            throw new RouteError('order has ' . count($route) . ' stops, expected ' . count($this->stops));
                        }
                    } elseif ($command === 'EXACT') {
                        if (count($this->stops) > 10) {
                            throw new RouteError('too many stops for exact (' . count($this->stops) . ')');
                        }
                        $route = $this->exact();
                    } else {
                        $route = [];
                        while (count($route) < count($this->stops)) {
                            $remaining = array_values(array_diff($this->ids(), $route));
                            $best = null;
                            foreach ($remaining as $c) {
                                if ($command === 'NEAREST') {
                                    $choice = [$this->distance($route === [] ? 0 : $route[count($route) - 1], $c), $c];
                                    if ($best === null || $choice < $best) {
                                        $best = $choice;
                                    }
                                } else {
                                    for ($j = 0; $j <= count($route); $j++) {
                                        $candidate = $route;
                                        array_splice($candidate, $j, 0, [$c]);
                                        $choice = [$this->length($candidate) - $this->length($route), $c, $j];
                                        if ($best === null || $choice < $best) {
                                            $best = $choice;
                                        }
                                    }
                                }
                            }
                            if ($command === 'NEAREST') {
                                $route[] = $best[1];
                            } else {
                                array_splice($route, $best[2], 0, [$best[1]]);
                            }
                        }
                    }
                    $this->tour = $route;
                    echo strtolower($command), ': ', $this->notation($route), ' length ', $this->length($route), "\n";
                    break;
                case 'TOUR':
                    $this->requireTour();
                    echo 'tour: ', $this->notation($this->tour), ' length ', $this->length($this->tour), "\n";
                    break;
                case 'TWOOPT':
                case 'OROPT':
                case 'SWAP':
                    $this->requireTour();
                    $before = $this->length($this->tour);
                    [$this->tour, $count] = $this->improveTour($this->tour, $command);
                    echo strtolower($command), ": moves $count, length $before -> ", $this->length($this->tour), "\n";
                    break;
                case 'TIMECHECK':
                    if ($args === []) {
                        $this->requireTour();
                        echo 'timecheck tour depart ', $this->clock($this->departure), "\n";
                        $this->simulate($this->tour, true);
                    } else {
                        $this->requirePlan();
                        $r = (int)$args[0];
                        if ($r > count($this->routes)) {
                            throw new RouteError("no route $r");
                        }
                        echo "timecheck route $r depart ", $this->clock($this->departure), "\n";
                        $this->simulate($this->routes[$r - 1], true);
                    }
                    break;
                case 'BOUND':
                    $this->requireData();
                    $this->bounds();
                    break;
                case 'VRP':
                case 'SPLIT':
                case 'SWEEP':
                    $this->createPlan($command, $args);
                    break;
                case 'ROUTES':
                    $this->requirePlan();
                    echo 'plan: capacity ', $this->capacity, ', routes ', count($this->routes), ', length ', $this->planLength(), "\n";
                    $this->routeLines();
                    break;
                case 'RELOCATE':
                case 'EXCHANGE':
                case 'CROSS':
                    $this->requirePlan();
                    $before = $this->planLength();
                    $oldCount = count($this->routes);
                    $count = 0;
                    while (($move = $this->planMove($command)) !== null) {
                        [$this->routes, $message] = $move;
                        echo $message, "\n";
                        $this->normalize();
                        $count++;
                    }
                    echo strtolower($command), ": moves $count,", $command === 'EXCHANGE' ? '' : " routes $oldCount -> " . count($this->routes) . ',', " length $before -> ", $this->planLength(), "\n";
                    break;
                case 'ROUTEOPT':
                    $this->requirePlan();
                    $before = $this->planLength();
                    foreach ($this->routes as $r => $route) {
                        $old = $this->length($route);
                        [$this->routes[$r], $count] = $this->improveTour($route, 'TWOOPT', false);
                        echo 'route ', $r + 1, ": moves $count, length $old -> ", $this->length($this->routes[$r]), "\n";
                    }
                    $this->normalize();
                    echo "routeopt: length $before -> ", $this->planLength(), "\n";
                    break;
                case 'REPORT':
                    $demand = $service = $windows = 0;
                    foreach ($this->stops as $stop) {
                        $demand += $stop['demand'];
                        $service += $stop['service'];
                        $windows += $stop['open'] !== null ? 1 : 0;
                    }
                    echo 'report: stops ', count($this->stops), ", demand $demand, service $service, windows $windows\n";
                    if ($this->tour === null) {
                        echo "tour: none\n";
                    } else {
                        [$time, $violations, $late] = $this->simulate($this->tour);
                        echo 'tour: length ', $this->length($this->tour), ', return ', $this->clock($time), ", violations $violations, lateness $late\n";
                    }
                    if ($this->routes === null) {
                        echo "plan: none\n";
                    } else {
                        $runs = array_map(fn($route) => $this->simulate($route), $this->routes);
                        $denominator = count($this->routes) * $this->capacity;
                        $weight = array_sum(array_map(fn($route) => $this->load($route), $this->routes));
                        $u = intdiv(2000 * $weight + $denominator, 2 * $denominator);
                        echo 'plan: capacity ', $this->capacity, ', routes ', count($this->routes), ', length ', $this->planLength(), ', utilization ', intdiv($u, 10), '.', $u % 10, '%, return ', $this->clock(max(array_column($runs, 0))), ', violations ', array_sum(array_column($runs, 1)), ', lateness ', array_sum(array_column($runs, 2)), "\n";
                    }
                    break;
            }
        } catch (RouteError $error) {
            echo 'error: ', $error->getMessage(), "\n";
        }
    }
}

$workbench = new RouteWorkbench();
$count = (int)fgets(STDIN);
for ($i = 0; $i < $count; $i++) {
    $workbench->execute(rtrim(fgets(STDIN), "\r\n"));
}
