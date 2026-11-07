<?php
class Station
{
    public int $transfer = 0;
    public bool $closed = false;
    public function __construct(public int $zone, public string $name) {}
}

class MetroLine
{
    public int $delay = 0;
    public bool $suspended = false;
    public function __construct(public string $id, public int $first, public int $last,
        public int $headway, public array $stops, public array $offsets) {}

    public function trips(): int
    {
        return intdiv($this->last - $this->first, $this->headway) + 1;
    }

    public function duration(): int
    {
        return $this->offsets[count($this->offsets) - 1];
    }

    public function directions(): array
    {
        return [[$this->stops, $this->offsets], [array_reverse($this->stops),
            array_map(fn($c) => $this->duration() - $c, array_reverse($this->offsets))]];
    }

    public function nextTrain(int $offset, int $ready): ?int
    {
        $difference = max(0, $ready - $this->first - $this->delay - $offset);
        $q = intdiv($difference + $this->headway - 1, $this->headway);
        return $q < $this->trips() ? $q : null;
    }

    public function time(int $q, int $offset): int
    {
        return $this->first + $this->delay + $q * $this->headway + $offset;
    }
}

class MetroError extends Exception {}

class Metro
{
    private array $stations = [];
    private array $lines = [];
    private array $walks = [];
    private array $closed = [];
    private ?array $tariff = null;

    private function minutes(string $text): int
    {
        [$hour, $minute] = array_map('intval', explode(':', $text));
        return $hour * 60 + $minute;
    }

    private function clock(int $value): string
    {
        return sprintf('%02d:%02d', intdiv($value, 60), $value % 60);
    }

    private function sortedKeys(array $map): array
    {
        $keys = array_keys($map);
        sort($keys, SORT_STRING);
        return $keys;
    }

    private function segment(string $a, string $b): string
    {
        return strcmp($a, $b) < 0 ? "$a-$b" : "$b-$a";
    }

    private function blocked(string $a, string $b): bool
    {
        return isset($this->closed[$this->segment($a, $b)]);
    }

    private function stationCheck(string $id): void
    {
        if (!isset($this->stations[$id])) {
            throw new MetroError("unknown station $id");
        }
    }

    private function lineCheck(string $id): void
    {
        if (!isset($this->lines[$id])) {
            throw new MetroError("unknown line $id");
        }
    }

    private function openCheck(string $id): void
    {
        if ($this->stations[$id]->closed) {
            throw new MetroError("station $id is closed");
        }
    }

    private function journeyCheck(string $origin, string $destination): void
    {
        $this->stationCheck($origin);
        $this->stationCheck($destination);
        if ($origin === $destination) {
            throw new MetroError('origin and destination are the same');
        }
        $this->openCheck($origin);
        $this->openCheck($destination);
    }

    private function runningLines(): array
    {
        $result = [];
        foreach ($this->sortedKeys($this->lines) as $id) {
            if (!$this->lines[$id]->suspended) {
                $result[] = $this->lines[$id];
            }
        }
        return $result;
    }

    private function update(array &$labels, string $destination, int $time, array $journey): bool
    {
        if (isset($labels[$destination]) && $labels[$destination][0] <= $time) {
            return false;
        }
        $labels[$destination] = [$time, $journey];
        return true;
    }

    private function earliest(string $origin, int $departure): array
    {
        $labels = [$origin => [$departure, []]];
        $settled = [];
        $lines = $this->runningLines();
        while (true) {
            $u = null;
            foreach ($this->sortedKeys($labels) as $id) {
                if (!isset($settled[$id]) && ($u === null || $labels[$id][0] < $labels[$u][0])) {
                    $u = $id;
                }
            }
            if ($u === null) {
                break;
            }
            $settled[$u] = true;
            [$arrival, $journey] = $labels[$u];
            $ready = $arrival + ($u === $origin ? 0 : $this->stations[$u]->transfer);
            foreach ($lines as $line) {
                if (!in_array($u, $line->stops, true)) {
                    continue;
                }
                foreach ($line->directions() as [$stops, $offsets]) {
                    $i = array_search($u, $stops, true);
                    if ($i === count($stops) - 1) {
                        continue;
                    }
                    $q = $line->nextTrain($offsets[$i], $ready);
                    if ($q === null) {
                        continue;
                    }
                    $boarding = $line->time($q, $offsets[$i]);
                    for ($j = $i + 1; $j < count($stops); $j++) {
                        if ($this->blocked($stops[$j - 1], $stops[$j])) {
                            break;
                        }
                        if ($this->stations[$stops[$j]]->closed) {
                            continue;
                        }
                        $time = $line->time($q, $offsets[$j]);
                        $leg = ['ride', $line->id, $stops[count($stops) - 1], $u, $boarding, $stops[$j], $time, $j - $i];
                        $this->update($labels, $stops[$j], $time, [...$journey, $leg]);
                    }
                }
            }
            foreach ($this->sortedKeys($this->walks[$u]) as $v) {
                $time = $arrival + $this->walks[$u][$v];
                if (!$this->stations[$v]->closed && $time <= 1440) {
                    $this->update($labels, $v, $time, [...$journey, ['walk', $u, $arrival, $v, $time]]);
                }
            }
        }
        return $labels;
    }

    private function walkStep(array &$labels, array $selected, array &$marked): void
    {
        $snapshot = [];
        foreach ($this->sortedKeys($selected) as $u) {
            $snapshot[$u] = $labels[$u];
        }
        foreach ($snapshot as $u => [$arrival, $journey]) {
            foreach ($this->sortedKeys($this->walks[$u]) as $v) {
                $time = $arrival + $this->walks[$u][$v];
                if (!$this->stations[$v]->closed && $time <= 1440 &&
                    $this->update($labels, $v, $time, [...$journey, ['walk', $u, $arrival, $v, $time]])) {
                    $marked[$v] = true;
                }
            }
        }
    }

    private function rounds(string $origin, int $departure): array
    {
        $labels = [$origin => [$departure, []]];
        $marked = [$origin => true];
        $this->walkStep($labels, [$origin => true], $marked);
        $result = [$labels];
        $lines = $this->runningLines();
        while ($marked) {
            $previous = $labels;
            $previousMarked = $marked;
            $labels = $previous;
            $marked = [];
            $selected = [];
            foreach ($lines as $line) {
                foreach ($line->directions() as [$stops, $offsets]) {
                    $boarded = null;
                    $b = null;
                    $boarding = null;
                    $journey = [];
                    foreach ($stops as $j => $u) {
                        if ($j > 0 && $this->blocked($stops[$j - 1], $u)) {
                            $boarded = null;
                        }
                        if ($this->stations[$u]->closed) {
                            continue;
                        }
                        if ($boarded !== null) {
                            $time = $line->time($boarded, $offsets[$j]);
                            $leg = ['ride', $line->id, $stops[count($stops) - 1], $stops[$b], $boarding, $u, $time, $j - $b];
                            if ($this->update($labels, $u, $time, [...$journey, $leg])) {
                                $selected[$u] = true;
                                $marked[$u] = true;
                            }
                        }
                        if ($j === count($stops) - 1 || !isset($previousMarked[$u])) {
                            continue;
                        }
                        [$arrival, $candidateJourney] = $previous[$u];
                        $ready = $arrival + ($u === $origin ? 0 : $this->stations[$u]->transfer);
                        $candidate = $line->nextTrain($offsets[$j], $ready);
                        if ($candidate !== null && ($boarded === null || $candidate < $boarded)) {
                            $boarded = $candidate;
                            $b = $j;
                            $boarding = $line->time($candidate, $offsets[$j]);
                            $journey = $candidateJourney;
                        }
                    }
                }
            }
            $this->walkStep($labels, $selected, $marked);
            $result[] = $labels;
        }
        return $result;
    }

    private function rideCount(array $journey): int
    {
        return count(array_filter($journey, fn($leg) => $leg[0] === 'ride'));
    }

    private function printJourney(string $heading, int $departure, array $label): void
    {
        [$arrival, $journey] = $label;
        $rides = $this->rideCount($journey);
        $walks = count(array_filter($journey, fn($leg) => $leg[0] === 'walk'));
        echo "$heading ", $this->clock($departure), ' -> ', $this->clock($arrival),
            ' total ', $arrival - $departure, " rides $rides walks $walks\n";
        $previousEnd = $departure;
        foreach ($journey as $leg) {
            if ($leg[0] === 'ride') {
                [, $line, $toward, $from, $start, $to, $finish, $count] = $leg;
                echo "RIDE $line toward $toward $from ", $this->clock($start), " -> $to ", $this->clock($finish),
                    ' wait ', $start - $previousEnd, " stops $count\n";
                $previousEnd = $finish;
            } elseif ($leg[0] === 'walk') {
                [, $from, $start, $to, $finish] = $leg;
                echo "WALK $from ", $this->clock($start), " -> $to ", $this->clock($finish), "\n";
                $previousEnd = $finish;
            } else {
                [, $station, $start, $finish] = $leg;
                echo "STAY $station ", $this->clock($start), ' -> ', $this->clock($finish), "\n";
                $previousEnd = $finish;
            }
        }
    }

    private function printFare(string $origin, string $destination, string $timeText, string $class, array $journey): void
    {
        [$discountCap, $window, $prices] = $this->tariff;
        $half = fn($x) => intdiv($x + 19, 20) * 10;
        $cap = $class === 'CHILD' ? $half($discountCap) : $discountCap;
        $tickets = [];
        $previousEnd = null;
        foreach ($journey as $leg) {
            if ($leg[0] !== 'ride') {
                continue;
            }
            [, $lineId, $toward, $from, $boarding, $to, $arrival] = $leg;
            $line = $this->lines[$lineId];
            foreach ($line->directions() as [$stops, $_]) {
                if ($stops[count($stops) - 1] === $toward) {
                    break;
                }
            }
            $start = array_search($from, $stops, true);
            $finish = array_search($to, $stops, true);
            $zones = [];
            for ($i = $start; $i <= $finish; $i++) {
                $zones[$this->stations[$stops[$i]]->zone] = true;
            }
            $zoneCount = count($zones);
            $price = $prices[min($zoneCount, count($prices)) - 1];
            if ($class === 'CHILD') {
                $price = $half($price);
            }
            $discount = $previousEnd !== null && $boarding - $previousEnd <= $window ? min($cap, $price) : 0;
            $tickets[] = [$lineId, $from, $to, $zoneCount, $price, $discount, $price - $discount];
            $previousEnd = $arrival;
        }
        echo "FARE $origin $destination $timeText $class rides ", count($tickets),
            ' total ', array_sum(array_column($tickets, 6)), "\n";
        foreach ($tickets as [$line, $from, $to, $zones, $price, $discount, $pay]) {
            echo "TICKET $line $from $to zones $zones price $price discount $discount pay $pay\n";
        }
    }

    private function searchCommand(string $command, array $args): void
    {
        [$origin, $destination] = $args;
        $this->journeyCheck($origin, $destination);
        $departure = isset($args[2]) ? $this->minutes($args[2]) : null;
        if ($command === 'FARE') {
            if (!in_array($args[3], ['ADULT', 'CHILD'], true)) {
                throw new MetroError("unknown fare class {$args[3]}");
            }
            if ($this->tariff === null) {
                throw new MetroError('no tariff');
            }
        } elseif ($command === 'PROFILE' && $departure > $this->minutes($args[3])) {
            throw new MetroError("empty interval {$args[2]} {$args[3]}");
        }
        if ($command === 'ROUTE' || $command === 'FARE') {
            $label = $this->earliest($origin, $departure)[$destination] ?? null;
            if ($label === null) {
                echo "$command ", implode(' ', $args), " unreachable\n";
            } elseif ($command === 'ROUTE') {
                $this->printJourney("ROUTE $origin $destination", $departure, $label);
            } else {
                $this->printFare($origin, $destination, $args[2], $args[3], $label[1]);
            }
        } elseif ($command === 'FEWEST' || $command === 'PARETO') {
            $all = $this->rounds($origin, $departure);
            $options = [];
            foreach ($all as $k => $labels) {
                if (isset($labels[$destination]) && ($k === 0 || !isset($all[$k - 1][$destination]) ||
                    $labels[$destination][0] < $all[$k - 1][$destination][0])) {
                    $options[] = $k;
                }
            }
            if ($command === 'FEWEST') {
                if ($options) {
                    $k = $options[0];
                    $this->printJourney("FEWEST $origin $destination trips $k", $departure, $all[$k][$destination]);
                } else {
                    echo 'FEWEST ', implode(' ', $args), " unreachable\n";
                }
            } else {
                echo 'PARETO ', implode(' ', $args), ' options ', count($options), "\n";
                foreach ($options as $k) {
                    $this->printJourney("OPTION trips $k", $departure, $all[$k][$destination]);
                }
            }
        } elseif ($command === 'LASTTRAIN' || $command === 'ARRIVEBY') {
            $start = $command === 'LASTTRAIN' ? 1439 : $departure - 1;
            $heading = "$command $origin $destination" . ($command === 'ARRIVEBY' ? " by {$args[2]}" : '');
            for ($time = $start; $time >= 0; $time--) {
                $label = $this->earliest($origin, $time)[$destination] ?? null;
                if ($label !== null && ($command === 'LASTTRAIN' || $label[0] <= $departure)) {
                    $this->printJourney($heading, $time, $label);
                    return;
                }
            }
            echo "$heading none\n";
        } elseif ($command === 'PROFILE') {
            $finish = $this->minutes($args[3]);
            $arrivals = [];
            for ($time = $departure; $time <= $finish; $time++) {
                $arrivals[$time] = $this->earliest($origin, $time)[$destination][0] ?? null;
            }
            $selected = [];
            for ($time = $departure; $time <= $finish; $time++) {
                if ($arrivals[$time] !== null && ($time === $finish || $arrivals[$time + 1] === null ||
                    $arrivals[$time] < $arrivals[$time + 1])) {
                    $selected[] = $time;
                }
            }
            echo 'PROFILE ', implode(' ', $args), ' count ', count($selected), "\n";
            foreach ($selected as $time) {
                echo $this->clock($time), ' -> ', $this->clock($arrivals[$time]), ' total ', $arrivals[$time] - $time, "\n";
            }
        }
    }

    public function execute(string $text): void
    {
        $args = explode(' ', $text);
        $command = array_shift($args);
        $a = $args[0] ?? null;
        $b = $args[1] ?? null;
        try {
            switch ($command) {
                case 'STATION':
                    if (isset($this->stations[$a])) {
                        throw new MetroError("station $a already exists");
                    }
                    $this->stations[$a] = new Station((int)$b, $args[2]);
                    $this->walks[$a] = [];
                    echo "STATION $a zone $b {$args[2]}\n";
                    break;
                case 'LINE':
                    if (isset($this->lines[$a])) {
                        throw new MetroError("line $a already exists");
                    }
                    $stops = [];
                    $offsets = [0];
                    for ($i = 4; $i < count($args); $i += 2) {
                        $stops[] = $args[$i];
                        $this->stationCheck($args[$i]);
                    }
                    $seen = [];
                    foreach ($stops as $id) {
                        if (isset($seen[$id])) {
                            throw new MetroError("station $id appears twice on line $a");
                        }
                        $seen[$id] = true;
                    }
                    $first = $this->minutes($b);
                    $last = $this->minutes($args[2]);
                    if ($first > $last) {
                        throw new MetroError("line $a first departure is after last departure");
                    }
                    for ($i = 5; $i < count($args); $i += 2) {
                        $offsets[] = $offsets[count($offsets) - 1] + (int)$args[$i];
                    }
                    if ($last + $offsets[count($offsets) - 1] > 1440) {
                        throw new MetroError("line $a runs past 24:00");
                    }
                    $line = new MetroLine($a, $first, $last, (int)$args[3], $stops, $offsets);
                    $this->lines[$a] = $line;
                    echo "LINE $a stops ", count($stops), ' time ', $line->duration(), ' trips ', $line->trips(), "\n";
                    break;
                case 'TRANSFER':
                    $this->stationCheck($a);
                    $this->stations[$a]->transfer = (int)$b;
                    echo "TRANSFER $a $b\n";
                    break;
                case 'WALK':
                    $this->stationCheck($a);
                    $this->stationCheck($b);
                    if ($a === $b) {
                        throw new MetroError("walk from $a to itself");
                    }
                    $old = $this->walks[$a][$b] ?? null;
                    $this->walks[$a][$b] = (int)$args[2];
                    $this->walks[$b][$a] = (int)$args[2];
                    echo 'WALK ', implode(' ', $args), $old !== null ? " was $old" : '', "\n";
                    break;
                case 'TARIFF':
                    $prices = array_map('intval', array_slice($args, 2));
                    for ($i = 1; $i < count($prices); $i++) {
                        if ($prices[$i] < $prices[$i - 1]) {
                            throw new MetroError('tariff prices must not decrease');
                        }
                    }
                    $this->tariff = [(int)$a, (int)$b, $prices];
                    echo 'TARIFF zones ', count($prices), " discount $a window $b\n";
                    break;
                case 'CLOSE':
                case 'OPEN':
                    $this->stationCheck($a);
                    if ($b !== null) {
                        $this->stationCheck($b);
                        $key = $this->segment($a, $b);
                        if ($command === 'CLOSE') {
                            $affected = [];
                            foreach ($this->sortedKeys($this->lines) as $id) {
                                $stops = $this->lines[$id]->stops;
                                for ($i = 1; $i < count($stops); $i++) {
                                    if ($this->segment($stops[$i - 1], $stops[$i]) === $key) {
                                        $affected[] = $id;
                                        break;
                                    }
                                }
                            }
                            if (!$affected) {
                                throw new MetroError("no segment $a-$b");
                            }
                            if (isset($this->closed[$key])) {
                                throw new MetroError("segment $a-$b is already closed");
                            }
                            $this->closed[$key] = [$a, $b];
                            echo "CLOSE $a-$b lines ", implode(' ', $affected), "\n";
                        } else {
                            if (!isset($this->closed[$key])) {
                                throw new MetroError("segment $a-$b is not closed");
                            }
                            unset($this->closed[$key]);
                            echo "OPEN $a-$b\n";
                        }
                    } else {
                        $current = $this->stations[$a]->closed;
                        if ($command === 'CLOSE' && $current) {
                            throw new MetroError("station $a is already closed");
                        }
                        if ($command === 'OPEN' && !$current) {
                            throw new MetroError("station $a is not closed");
                        }
                        $this->stations[$a]->closed = $command === 'CLOSE';
                        echo "$command $a\n";
                    }
                    break;
                case 'DELAY':
                    $this->lineCheck($a);
                    if ($this->lines[$a]->last + (int)$b + $this->lines[$a]->duration() > 1440) {
                        throw new MetroError("line $a runs past 24:00");
                    }
                    $this->lines[$a]->delay = (int)$b;
                    echo "DELAY $a $b\n";
                    break;
                case 'SUSPEND':
                case 'RESUME':
                    $this->lineCheck($a);
                    if ($command === 'SUSPEND' && $this->lines[$a]->suspended) {
                        throw new MetroError("line $a is already suspended");
                    }
                    if ($command === 'RESUME' && !$this->lines[$a]->suspended) {
                        throw new MetroError("line $a is not suspended");
                    }
                    $this->lines[$a]->suspended = $command === 'SUSPEND';
                    echo "$command $a\n";
                    break;
                case 'ROUTE':
                case 'FEWEST':
                case 'PARETO':
                case 'FARE':
                case 'LASTTRAIN':
                case 'ARRIVEBY':
                case 'PROFILE':
                    $this->searchCommand($command, $args);
                    break;
                case 'VIA':
                    [$origin, $via, $destination, $timeText] = $args;
                    foreach ([$origin, $via, $destination] as $id) {
                        $this->stationCheck($id);
                    }
                    if ($origin === $destination) {
                        throw new MetroError('origin and destination are the same');
                    }
                    if ($via === $origin || $via === $destination) {
                        throw new MetroError("via station $via must differ from origin and destination");
                    }
                    foreach ([$origin, $via, $destination] as $id) {
                        $this->openCheck($id);
                    }
                    $departure = $this->minutes($timeText);
                    $first = $this->earliest($origin, $departure)[$via] ?? null;
                    $second = null;
                    if ($first !== null) {
                        $ready = $first[0] + $this->stations[$via]->transfer;
                        $second = $this->earliest($via, $ready)[$destination] ?? null;
                    }
                    if ($second !== null) {
                        $journey = [...$first[1], ['stay', $via, $first[0], $ready], ...$second[1]];
                        $this->printJourney("VIA $origin $via $destination", $departure, [$second[0], $journey]);
                    } else {
                        echo 'VIA ', implode(' ', $args), " unreachable\n";
                    }
                    break;
                case 'REACH':
                    $this->stationCheck($a);
                    $this->openCheck($a);
                    $departure = $this->minutes($b);
                    $labels = $this->earliest($a, $departure);
                    $selected = array_keys(array_filter($labels, fn($label) => $label[0] <= $departure + (int)$args[2]));
                    usort($selected, fn($x, $y) => ($labels[$x][0] <=> $labels[$y][0]) ?: strcmp($x, $y));
                    echo 'REACH ', implode(' ', $args), ' count ', count($selected), "\n";
                    foreach ($selected as $id) {
                        [$arrival, $journey] = $labels[$id];
                        echo "$id {$this->stations[$id]->name} ", $this->clock($arrival), ' ', $arrival - $departure,
                            ' rides ', $this->rideCount($journey), "\n";
                    }
                    break;
                case 'TIMETABLE':
                    $this->stationCheck($a);
                    $this->lineCheck($b);
                    $line = $this->lines[$b];
                    if (!in_array($a, $line->stops, true)) {
                        throw new MetroError("station $a is not on line $b");
                    }
                    $toward = $args[2];
                    $direction = $this->direction($line, $toward);
                    if ($a === $toward) {
                        throw new MetroError("no departures from $a toward $toward");
                    }
                    if ($line->suspended) {
                        throw new MetroError("line $b is suspended");
                    }
                    $this->openCheck($a);
                    [$stops, $offsets] = $direction;
                    $offset = $offsets[array_search($a, $stops, true)];
                    $times = [];
                    for ($q = 0; $q < $line->trips() && count($times) < (int)$args[4]; $q++) {
                        $time = $line->time($q, $offset);
                        if ($time >= $this->minutes($args[3])) {
                            $times[] = $this->clock($time);
                        }
                    }
                    echo "TIMETABLE $a $b toward $toward {$args[3]} next ", count($times),
                        $times ? ' ' . implode(' ', $times) : '', "\n";
                    break;
                case 'DEPARTURES':
                case 'ARRIVALS':
                    $this->stationCheck($a);
                    $this->openCheck($a);
                    $entries = [];
                    foreach ($this->runningLines() as $line) {
                        if (!in_array($a, $line->stops, true)) {
                            continue;
                        }
                        foreach ($line->directions() as $direction => [$stops, $offsets]) {
                            $i = array_search($a, $stops, true);
                            if ($command === 'DEPARTURES' ? $i === count($stops) - 1 : $i === 0) {
                                continue;
                            }
                            for ($q = 0; $q < $line->trips(); $q++) {
                                $time = $line->time($q, $offsets[$i]);
                                if ($time >= $this->minutes($b)) {
                                    $entries[] = [$time, $line->id, $direction,
                                        $command === 'DEPARTURES' ? $stops[count($stops) - 1] : $stops[0]];
                                }
                            }
                        }
                    }
                    usort($entries, fn($x, $y) => ($x[0] <=> $y[0]) ?: (strcmp($x[1], $y[1]) ?: ($x[2] <=> $y[2])));
                    $entries = array_slice($entries, 0, (int)$args[2]);
                    echo "$command $a $b count ", count($entries), "\n";
                    foreach ($entries as [$time, $id, $_, $terminal]) {
                        echo $this->clock($time), " $id ", $command === 'DEPARTURES' ? 'toward' : 'from', " $terminal\n";
                    }
                    break;
                case 'TRIP':
                    $this->lineCheck($a);
                    $line = $this->lines[$a];
                    [$stops, $offsets] = $this->direction($line, $b);
                    if ($line->suspended) {
                        throw new MetroError("line $a is suspended");
                    }
                    $q = $line->nextTrain(0, $this->minutes($args[2]));
                    if ($q === null) {
                        echo "TRIP $a toward $b {$args[2]} none\n";
                    } else {
                        echo "TRIP $a toward $b {$args[2]} trip ", $q + 1, ' departs ', $this->clock($line->time($q, 0)), "\n";
                        foreach ($stops as $i => $id) {
                            $suffix = $this->stations[$id]->closed ? ' closed' : '';
                            if ($i > 0 && $this->blocked($stops[$i - 1], $id)) {
                                $suffix .= ' blocked';
                            }
                            echo $this->clock($line->time($q, $offsets[$i])), " $id$suffix\n";
                        }
                    }
                    break;
                case 'SHOWLINE':
                    $this->lineCheck($a);
                    $line = $this->lines[$a];
                    echo "SHOWLINE $a ", $line->suspended ? 'suspended' : 'running', ' first ', $this->clock($line->first),
                        ' last ', $this->clock($line->last), " headway {$line->headway} delay {$line->delay} trips ", $line->trips(), "\n";
                    foreach ($line->stops as $i => $id) {
                        $suffix = $this->stations[$id]->closed ? ' closed' : '';
                        if ($i > 0 && $this->blocked($line->stops[$i - 1], $id)) {
                            $suffix .= ' blocked';
                        }
                        echo "{$line->offsets[$i]} $id zone {$this->stations[$id]->zone}$suffix\n";
                    }
                    break;
                case 'INFO':
                    $this->stationCheck($a);
                    $station = $this->stations[$a];
                    echo "INFO $a {$station->name} zone {$station->zone} transfer {$station->transfer} ",
                        $station->closed ? 'closed' : 'open', "\n";
                    $lines = [];
                    foreach ($this->sortedKeys($this->lines) as $id) {
                        if (in_array($a, $this->lines[$id]->stops, true)) {
                            $lines[] = $id;
                        }
                    }
                    echo 'LINES ', $lines ? implode(' ', $lines) : 'none', "\n";
                    $walks = [];
                    foreach ($this->sortedKeys($this->walks[$a]) as $v) {
                        $walks[] = "$v {$this->walks[$a][$v]}";
                    }
                    echo 'WALKS ', $walks ? implode(' ', $walks) : 'none', "\n";
                    break;
                case 'STATUS':
                    echo 'STATUS stations ', count($this->stations), ' lines ', count($this->lines),
                        ' walks ', intdiv(array_sum(array_map('count', $this->walks)), 2), "\n";
                    foreach ($this->sortedKeys($this->stations) as $id) {
                        if ($this->stations[$id]->closed) {
                            echo "CLOSED $id\n";
                        }
                    }
                    $segments = [];
                    foreach ($this->closed as $key => $_) {
                        $segments[] = explode('-', $key);
                    }
                    usort($segments, fn($x, $y) => strcmp($x[0], $y[0]) ?: strcmp($x[1], $y[1]));
                    foreach ($segments as [$x, $y]) {
                        echo "CLOSED $x-$y\n";
                    }
                    foreach ($this->sortedKeys($this->lines) as $id) {
                        if ($this->lines[$id]->suspended) {
                            echo "SUSPENDED $id\n";
                        }
                    }
                    foreach ($this->sortedKeys($this->lines) as $id) {
                        if ($this->lines[$id]->delay !== 0) {
                            echo "DELAYED $id {$this->lines[$id]->delay}\n";
                        }
                    }
                    break;
            }
        } catch (MetroError $error) {
            echo 'ERROR ', $error->getMessage(), "\n";
        }
    }

    private function direction(MetroLine $line, string $toward): array
    {
        foreach ($line->directions() as $direction) {
            $stops = $direction[0];
            if ($stops[count($stops) - 1] === $toward) {
                return $direction;
            }
        }
        throw new MetroError("$toward is not a terminal of line {$line->id}");
    }
}

$metro = new Metro();
$count = (int)fgets(STDIN);
for ($i = 0; $i < $count; $i++) {
    $metro->execute(rtrim(fgets(STDIN), "\r\n"));
}
