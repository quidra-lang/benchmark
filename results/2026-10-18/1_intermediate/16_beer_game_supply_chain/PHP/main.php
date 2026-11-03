<?php

declare(strict_types=1);

const STAGE_NAMES = ['RETAILER', 'WHOLESALER', 'DISTRIBUTOR', 'FACTORY'];

const POLICY_PARAMETERS = [
    'FIXED' => 1, 'PASS' => 0, 'BASESTOCK' => 1, 'MINMAX' => 2,
    'MOVAVG' => 2, 'SMOOTH' => 2, 'STERMAN' => 4,
];

final class CommandError extends RuntimeException {}

function fail(string $message): never
{
    throw new CommandError($message);
}

function money(int $cents): string
{
    return intdiv($cents, 100) . '.' . str_pad((string) ($cents % 100), 2, '0', STR_PAD_LEFT);
}

function decimal(int $numerator, int $denominator, int $places): string
{
    $whole = intdiv($numerator, $denominator);
    $remainder = $numerator % $denominator;
    $fraction = '';
    for ($i = 0; $i < $places; ++$i) {
        $remainder *= 10;
        $fraction .= (string) intdiv($remainder, $denominator);
        $remainder %= $denominator;
    }
    return $whole . '.' . $fraction;
}

function floorDiv(int $numerator, int $denominator): int
{
    $quotient = intdiv($numerator, $denominator);
    return $numerator % $denominator < 0 ? $quotient - 1 : $quotient;
}

function variation(array $values): int
{
    $sum = array_sum($values);
    $squares = 0;
    foreach ($values as $value) {
        $squares += $value * $value;
    }
    return count($values) * $squares - $sum * $sum;
}

function parsePolicy(array $tokens): array
{
    $name = $tokens[0];
    if (!array_key_exists($name, POLICY_PARAMETERS)) {
        fail('unknown policy ' . $name);
    }
    $count = POLICY_PARAMETERS[$name];
    if (count($tokens) - 1 !== $count) {
        fail($name . ' needs ' . $count . ' parameters');
    }
    $values = [];
    foreach (array_slice($tokens, 1) as $i => $token) {
        $values[] = (int) ($name === 'STERMAN' && $i < 3
            ? str_replace('.', '', $token) : $token);
    }
    $valid = match ($name) {
        'FIXED' => 0 <= $values[0] && $values[0] <= 1000,
        'PASS' => true,
        'BASESTOCK' => 0 <= $values[0] && $values[0] <= 10000,
        'MINMAX' => 0 <= $values[0] && $values[0] < $values[1] && $values[1] <= 10000,
        'MOVAVG' => 1 <= $values[0] && $values[0] <= 52 &&
            0 <= $values[1] && $values[1] <= 10000,
        'SMOOTH' => 1 <= $values[0] && $values[0] <= 10 &&
            0 <= $values[1] && $values[1] <= 10000,
        'STERMAN' => max(array_slice($values, 0, 3)) <= 100 &&
            min(array_slice($values, 0, 3)) >= 0 &&
            0 <= $values[3] && $values[3] <= 10000,
    };
    if (!$valid) {
        fail('invalid parameter for ' . $name);
    }
    return ['name' => $name, 'args' => $values, 'text' => implode(' ', $tokens)];
}

final class Stage
{
    public int $inventory;
    public int $backlog = 0;
    public array $shipping;
    public array $orders;
    public array $policy;
    public int $expected;
    public int $holding;
    public int $backlogRate;
    public int $lot = 1;
    public ?int $capacity = null;
    public array $records = [];

    public function __construct(array $initial)
    {
        $this->inventory = $initial['inventory'];
        $this->shipping = array_fill(0, $initial['shipping'], $initial['quantity']);
        $this->orders = array_fill(0, $initial['orders'], $initial['quantity']);
        $this->policy = $initial['policy'];
        $this->expected = 100 * $initial['quantity'];
        $this->holding = $initial['holding'];
        $this->backlogRate = $initial['backlog'];
    }

    public function totalCost(): int
    {
        return array_sum(array_column($this->records, 'cost'));
    }
}

final class Simulation
{
    public int $week = 0;
    public array $demands;
    public array $stages;
    public int $plantBacklog = 0;
    public ?int $plantCapacity = null;
    public array $plantRecords = [];
    public string $visibility = 'OFF';

    public function __construct(public array $initials, array $demands)
    {
        $this->demands = $demands;
        $this->stages = array_map(static fn(array $initial): Stage => new Stage($initial), $initials);
    }

    public function signal(int $index, int $week, ?array $current = null): int
    {
        if ($this->visibility === 'ON') {
            return $this->demands[$week - 1];
        }
        if ($current !== null && $week === $this->week + 1) {
            return $current[$index];
        }
        return $this->stages[$index]->records[$week - 1]['incoming'];
    }

    public function setPolicy(int $index, array $policy): void
    {
        $stage = $this->stages[$index];
        $stage->policy = $policy;
        if ($policy['name'] === 'STERMAN') {
            $signal = $this->week
                ? $this->signal($index, $this->week)
                : $this->initials[$index]['quantity'];
            $stage->expected = 100 * $signal;
        }
    }

    public function positions(): array
    {
        $supply = [];
        $position = [];
        foreach ($this->stages as $index => $stage) {
            $upstream = $index < 3
                ? $this->stages[$index + 1]->backlog : $this->plantBacklog;
            $line = array_sum($stage->orders) + $upstream + array_sum($stage->shipping);
            $supply[] = $line;
            $position[] = $stage->inventory + $line - $stage->backlog;
        }
        return [$supply, $position];
    }

    private function policyOrder(int $index, array $incoming, int $line, int $position): int
    {
        $stage = $this->stages[$index];
        $name = $stage->policy['name'];
        $a = $stage->policy['args'];
        $week = $this->week + 1;
        $demand = $this->signal($index, $week, $incoming);

        if ($name === 'FIXED') {
            return $a[0];
        }
        if ($name === 'PASS') {
            return $incoming[$index];
        }
        if ($name === 'BASESTOCK') {
            return max(0, $a[0] - $position);
        }
        if ($name === 'MINMAX') {
            return $position <= $a[0] ? $a[1] - $position : 0;
        }
        if ($name === 'MOVAVG') {
            $count = min($a[0], $week);
            $total = 0;
            for ($u = $week - $count + 1; $u <= $week; ++$u) {
                $total += $this->signal($index, $u, $incoming);
            }
            $forecast = intdiv($total, $count);
            $delay = $this->initials[$index]['shipping'] +
                     $this->initials[$index]['orders'];
            return max(0, $a[1] + $forecast * $delay - $position);
        }
        if ($name === 'SMOOTH') {
            return max(0, $demand + floorDiv($a[1] - $position, $a[0]));
        }

        [$theta, $alpha, $beta, $target] = $a;
        $stage->expected = floorDiv(
            100 * $theta * $demand + (100 - $theta) * $stage->expected, 100
        );
        $net = $stage->inventory - $stage->backlog;
        return max(0, floorDiv(
            100 * $stage->expected + $alpha * (100 * ($target - $net) - $beta * $line),
            10000
        ));
    }

    public function step(): array
    {
        $received = [];
        foreach ($this->stages as $stage) {
            $quantity = array_shift($stage->shipping);
            $stage->inventory += $quantity;
            $received[] = $quantity;
        }

        $incoming = [
            $this->demands[$this->week],
            $this->stages[0]->orders[0],
            $this->stages[1]->orders[0],
            $this->stages[2]->orders[0],
        ];
        $plantIncoming = $this->stages[3]->orders[0];
        foreach ($this->stages as $stage) {
            array_shift($stage->orders);
        }

        $records = [];
        foreach ($this->stages as $index => $stage) {
            $before = $stage->backlog;
            $requested = $before + $incoming[$index];
            $shipped = min($stage->inventory, $requested);
            if ($stage->capacity !== null) {
                $shipped = min($shipped, $stage->capacity);
            }
            $stage->inventory -= $shipped;
            $stage->backlog = $requested - $shipped;
            if ($index > 0) {
                $this->stages[$index - 1]->shipping[] = $shipped;
            }
            $records[] = [
                'received' => $received[$index], 'incoming' => $incoming[$index],
                'shipped' => $shipped, 'before' => $before,
                'ontime' => min(max(0, $shipped - $before), $incoming[$index]),
                'inventory' => $stage->inventory, 'backlog' => $stage->backlog,
            ];
        }

        $requested = $this->plantBacklog + $plantIncoming;
        $produced = $this->plantCapacity === null
            ? $requested : min($requested, $this->plantCapacity);
        $this->plantBacklog = $requested - $produced;
        $this->stages[3]->shipping[] = $produced;

        [$supply, $positions] = $this->positions();
        $orders = [];
        foreach ($this->stages as $index => $stage) {
            $orders[] = $this->policyOrder(
                $index, $incoming, $supply[$index], $positions[$index]
            );
        }
        foreach ($this->stages as $index => $stage) {
            $quantity = intdiv($orders[$index] + $stage->lot - 1, $stage->lot) * $stage->lot;
            $stage->orders[] = $quantity;
            $record = &$records[$index];
            $record['order'] = $quantity;
            $record['holding'] = $stage->holding * $stage->inventory;
            $record['backlog_cost'] = $stage->backlogRate * $stage->backlog;
            $record['cost'] = $record['holding'] + $record['backlog_cost'];
            $stage->records[] = $record;
            unset($record);
        }
        $this->plantRecords[] = [
            'incoming' => $plantIncoming,
            'produced' => $produced, 'backlog' => $this->plantBacklog,
        ];
        ++$this->week;
        return $records;
    }

    public function costs(): array
    {
        return array_map(static fn(Stage $stage): int => $stage->totalCost(), $this->stages);
    }
}

final class Game
{
    private array $initials = [];
    private array $base = [];
    private Simulation $simulation;
    private array $snapshots = [];
    private array $output = [];

    public function __construct(array $settings)
    {
        foreach ($settings as $tokens) {
            $this->initials[] = [
                'inventory' => (int) $tokens[1],
                'quantity' => (int) $tokens[2],
                'shipping' => (int) $tokens[3],
                'orders' => (int) $tokens[4],
                'holding' => (int) $tokens[5],
                'backlog' => (int) $tokens[6],
                'policy' => parsePolicy(array_slice($tokens, 7)),
            ];
        }
        $this->initialize();
    }

    private function emit(string|int ...$parts): void
    {
        $this->output[] = implode(' ', $parts);
    }

    private function stageIndex(string $name): int
    {
        $index = array_search($name, STAGE_NAMES, true);
        if ($index === false) {
            fail('unknown stage ' . $name);
        }
        return $index;
    }

    private function target(string $name): array
    {
        return $name === 'ALL' ? [0, 1, 2, 3] : [$this->stageIndex($name)];
    }

    private function requireWeeks(): void
    {
        if ($this->simulation->week === 0) {
            fail('no weeks simulated');
        }
    }

    private function rangeCheck(array $args, int $limit): array
    {
        if ($args === []) {
            return [1, $limit];
        }
        $first = (int) $args[0];
        $last = (int) $args[1];
        if (!(1 <= $first && $first <= $last && $last <= $limit)) {
            fail('bad range ' . $args[0] . ' ' . $args[1]);
        }
        return [$first, $last];
    }

    private function modeCheck(string $mode): void
    {
        if (!in_array($mode, ['ORDERS', 'INV', 'BACK', 'NET'], true)) {
            fail('unknown mode ' . $mode);
        }
    }

    private function values(int $index, string $mode): array
    {
        $records = $this->simulation->stages[$index]->records;
        if ($mode === 'NET') {
            return array_map(static fn(array $r): int => $r['inventory'] - $r['backlog'], $records);
        }
        $field = match ($mode) {
            'ORDERS' => 'order', 'INV' => 'inventory', 'BACK' => 'backlog',
        };
        return array_column($records, $field);
    }

    private function initialize(?array $demands = null): void
    {
        if ($demands !== null) {
            $this->base = $demands;
        }
        $this->simulation = new Simulation($this->initials, $this->base);
    }

    private function trial(array $policies): Simulation
    {
        $current = $this->simulation;
        $trial = new Simulation($this->initials, $current->demands);
        $trial->visibility = $current->visibility;
        $trial->plantCapacity = $current->plantCapacity;
        foreach ($trial->stages as $index => $stage) {
            $previous = $current->stages[$index];
            $stage->lot = $previous->lot;
            $stage->capacity = $previous->capacity;
            $stage->holding = $previous->holding;
            $stage->backlogRate = $previous->backlogRate;
            $trial->setPolicy($index, $policies[$index]);
        }
        while ($trial->week < count($trial->demands)) {
            $trial->step();
        }
        return $trial;
    }

    private function demand(array $values): void
    {
        $this->initialize($values);
        $this->emit(
            'DEMAND', 'weeks', count($values),
            'total', array_sum($values), 'min', min($values), 'max', max($values)
        );
    }

    private function generate(array $arguments): void
    {
        [$weeks, $base, $spread, $seed] = array_map('intval', array_slice($arguments, 0, 4));
        $changes = [];
        for ($i = 4; $i < count($arguments); $i += 3) {
            $change = [
                'kind' => $arguments[$i],
                'week' => (int) $arguments[$i + 1],
                'amount' => (int) $arguments[$i + 2],
            ];
            if ($change['week'] < 1 || $change['week'] > $weeks) {
                fail('week ' . $change['week'] . ' outside horizon');
            }
            $changes[] = $change;
        }
        $levels = [];
        for ($week = 1; $week <= $weeks; ++$week) {
            $level = $base;
            foreach ($changes as $change) {
                switch ($change['kind']) {
                    case 'STEP':
                        if ($week >= $change['week']) {
                            $level += $change['amount'];
                        }
                        break;
                    case 'PULSE':
                        if ($week === $change['week']) {
                            $level += $change['amount'];
                        }
                        break;
                    case 'RAMP':
                        if ($week >= $change['week']) {
                            $level += $change['amount'] * ($week - $change['week'] + 1);
                        }
                        break;
                }
            }
            if ($level < 0) {
                fail('negative level at week ' . $week);
            }
            $levels[] = $level;
        }
        $values = [];
        foreach ($levels as $level) {
            $seed = 48271 * $seed % 2147483647;
            $values[] = $level + $seed % $spread;
        }
        $this->demand($values);
    }

    private function showStatus(): void
    {
        $s = $this->simulation;
        $this->emit('STATUS', 'week', $s->week, 'of', count($s->demands));
        [$supply, $positions] = $s->positions();
        foreach ($s->stages as $index => $stage) {
            $text = STAGE_NAMES[$index] . ' inv ' . $stage->inventory .
                    ' back ' . $stage->backlog .
                    ' transit ' . implode(',', $stage->shipping) .
                    ' pending ' . implode(',', $stage->orders) .
                    ' supply ' . $supply[$index] .
                    ' position ' . $positions[$index] .
                    ' policy ' . $stage->policy['text'];
            if ($stage->policy['name'] === 'STERMAN') {
                $text .= ' expect ' . money($stage->expected);
            }
            $this->emit($text);
        }
        $this->emit('PLANT', 'back', $s->plantBacklog);
    }

    private function showWeek(int $week): void
    {
        $s = $this->simulation;
        $this->emit('WEEK', $week, 'demand', $s->demands[$week - 1]);
        foreach ($s->stages as $index => $stage) {
            $r = $stage->records[$week - 1];
            $this->emit(
                STAGE_NAMES[$index], 'recv', $r['received'], 'in', $r['incoming'],
                'ship', $r['shipped'], 'inv', $r['inventory'],
                'back', $r['backlog'], 'order', $r['order'], 'cost', money($r['cost'])
            );
        }
        $plant = $s->plantRecords[$week - 1];
        $this->emit(
            'PLANT', 'in', $plant['incoming'],
            'made', $plant['produced'], 'back', $plant['backlog']
        );
    }

    private function showTable(int $index, int $first, int $last): void
    {
        $this->emit('TABLE', STAGE_NAMES[$index], $first . '-' . $last);
        $labels = ['week', 'in', 'ship', 'recv', 'inv', 'back', 'order', 'cost'];
        $widths = [4, 6, 6, 6, 6, 6, 6, 9];
        $fields = [];
        foreach ($labels as $i => $label) {
            $fields[] = str_pad($label, $widths[$i], ' ', STR_PAD_LEFT);
        }
        $this->emit(implode(' ', $fields));
        for ($week = $first; $week <= $last; ++$week) {
            $r = $this->simulation->stages[$index]->records[$week - 1];
            $values = [
                $week, $r['incoming'], $r['shipped'], $r['received'],
                $r['inventory'], $r['backlog'], $r['order'], money($r['cost']),
            ];
            foreach ($values as $i => $value) {
                $fields[$i] = str_pad((string) $value, $widths[$i], ' ', STR_PAD_LEFT);
            }
            $this->emit(implode(' ', $fields));
        }
    }

    private function showCosts(): void
    {
        $s = $this->simulation;
        $this->emit('COSTS', 'week', $s->week);
        $totalHolding = 0;
        $totalBacklog = 0;
        foreach ($s->stages as $index => $stage) {
            $holding = array_sum(array_column($stage->records, 'holding'));
            $backlog = array_sum(array_column($stage->records, 'backlog_cost'));
            $totalHolding += $holding;
            $totalBacklog += $backlog;
            $this->emit(
                STAGE_NAMES[$index], 'holding', money($holding),
                'backlog', money($backlog), 'total', money($holding + $backlog)
            );
        }
        $this->emit(
            'TOTAL', 'holding', money($totalHolding),
            'backlog', money($totalBacklog), 'total', money($totalHolding + $totalBacklog)
        );
    }

    private static function fillText(array $records): array
    {
        $ordered = array_sum(array_column($records, 'incoming'));
        $ontime = array_sum(array_column($records, 'ontime'));
        $fill = $ordered === 0 ? 'n/a' : decimal($ontime * 100, $ordered, 2) . '%';
        return [$ordered, $ontime, $fill];
    }

    private function showBullwhip(): void
    {
        $s = $this->simulation;
        $n = $s->week;
        $demands = array_slice($s->demands, 0, $n);
        $demandVariation = variation($demands);
        $this->emit(
            'BULLWHIP', 'weeks', '1-' . $n, 'demand',
            'mean', decimal(array_sum($demands), $n, 4),
            'var', decimal($demandVariation, $n * $n, 4)
        );
        $previous = $demandVariation;
        foreach ($s->stages as $index => $stage) {
            $orders = array_column($stage->records, 'order');
            $current = variation($orders);
            $this->emit(
                STAGE_NAMES[$index], 'mean', decimal(array_sum($orders), $n, 4),
                'var', decimal($current, $n * $n, 4),
                'ratio', $demandVariation === 0 ? 'n/a' : decimal($current, $demandVariation, 4),
                'step', $previous === 0 ? 'n/a' : decimal($current, $previous, 4)
            );
            $previous = $current;
        }
    }

    private function showPeaks(): void
    {
        $s = $this->simulation;
        $this->emit('PEAKS', 'weeks', '1-' . $s->week);
        foreach ($s->stages as $index => $stage) {
            $inventories = array_column($stage->records, 'inventory');
            $backlogs = array_column($stage->records, 'backlog');
            $maxInventory = max($inventories);
            $maxBacklog = max($backlogs);
            $longest = 0;
            $run = 0;
            $start = 0;
            $bestStart = 0;
            $bestEnd = 0;
            foreach ($backlogs as $indexOfWeek => $backlog) {
                $week = $indexOfWeek + 1;
                if ($backlog > 0) {
                    if ($run === 0) {
                        $start = $week;
                    }
                    ++$run;
                    if ($run > $longest) {
                        $longest = $run;
                        $bestStart = $start;
                        $bestEnd = $week;
                    }
                } else {
                    $run = 0;
                }
            }
            $stockout = $longest ? $longest . ' weeks ' . $bestStart . '-' . $bestEnd : '0';
            $invWeek = $maxInventory ? array_search($maxInventory, $inventories, true) + 1 : '-';
            $backWeek = $maxBacklog ? array_search($maxBacklog, $backlogs, true) + 1 : '-';
            $this->emit(
                STAGE_NAMES[$index], 'max_inv', $maxInventory, 'week', $invWeek,
                'max_back', $maxBacklog, 'week', $backWeek, 'longest_stockout', $stockout
            );
        }
    }

    private function showLeadtime(int $index): void
    {
        $stage = $this->simulation->stages[$index];
        $initial = $this->initials[$index];
        $nominal = $initial['shipping'] + $initial['orders'];
        $received = 0;
        $cumulative = [];
        foreach ($stage->records as $record) {
            $received += $record['received'];
            $cumulative[] = $received - $nominal * $initial['quantity'];
        }
        $ordered = 0;
        $count = 0;
        $leads = [];
        foreach ($stage->records as $t => $record) {
            $ordered += $record['order'];
            if ($record['order'] === 0) {
                continue;
            }
            ++$count;
            for ($u = $t + 1; $u < count($stage->records); ++$u) {
                if ($cumulative[$u] >= $ordered) {
                    $leads[] = $u - $t;
                    break;
                }
            }
        }
        $this->emit(
            'LEADTIME', STAGE_NAMES[$index], 'nominal', $nominal,
            'orders', $count, 'completed', count($leads),
            'open', $count - count($leads),
            'min', $leads ? min($leads) : '-',
            'avg', $leads ? decimal(array_sum($leads), count($leads), 2) : '-',
            'max', $leads ? max($leads) : '-'
        );
    }

    private function valuesSlice(int $index, string $mode, int $first, int $last): array
    {
        return array_slice($this->values($index, $mode), $first - 1, $last - $first + 1);
    }

    private function showPlot(int $index, string $mode, int $first, int $last): void
    {
        $values = $this->valuesSlice($index, $mode, $first, $last);
        $maximum = max($values);
        if ($mode === 'NET') {
            $this->emit(
                'PLOT', STAGE_NAMES[$index], $mode, $first . '-' . $last,
                'min', min($values), 'max', $maximum
            );
            $scale = max(array_map('abs', $values));
            foreach ($values as $i => $value) {
                $width = $scale ? intdiv(abs($value) * 25, $scale) : 0;
                $left = $value < 0
                    ? str_repeat(' ', 25 - $width) . str_repeat('-', $width)
                    : str_repeat(' ', 25);
                $right = $value > 0 ? str_repeat('+', $width) : '';
                $this->emit(sprintf('%3d %s|%s %d', $first + $i, $left, $right, $value));
            }
        } else {
            $this->emit(
                'PLOT', STAGE_NAMES[$index], $mode, $first . '-' . $last, 'max', $maximum
            );
            foreach ($values as $i => $value) {
                $width = $maximum ? intdiv($value * 50, $maximum) : 0;
                $this->emit(sprintf('%3d |%s %d', $first + $i, str_repeat('#', $width), $value));
            }
        }
    }

    private function showHistogram(int $index, string $mode, int $width): void
    {
        $counts = [];
        foreach ($this->values($index, $mode) as $value) {
            $bin = floorDiv($value, $width);
            $counts[$bin] = ($counts[$bin] ?? 0) + 1;
        }
        $this->emit(
            'HISTOGRAM', STAGE_NAMES[$index], $mode,
            'width', $width, 'weeks', '1-' . $this->simulation->week
        );
        for ($bin = min(array_keys($counts)); $bin <= max(array_keys($counts)); ++$bin) {
            $count = $counts[$bin] ?? 0;
            $text = ($bin * $width) . '..' . ($bin * $width + $width - 1) . ' ' . $count;
            if ($count) {
                $text .= ' ' . str_repeat('*', $count);
            }
            $this->emit($text);
        }
    }

    private function command(string $command, array $a): void
    {
        $s = $this->simulation;
        switch ($command) {
            case 'DEMAND':
                $this->demand(array_map('intval', $a));
                break;
            case 'GENERATE':
                $this->generate($a);
                break;
            case 'RUN':
                if ($s->week === count($s->demands)) {
                    fail('horizon reached at week ' . count($s->demands));
                }
                $first = $s->week + 1;
                $count = min((int) $a[0], count($s->demands) - $s->week);
                $cost = 0;
                for ($t = 0; $t < $count; ++$t) {
                    $records = $s->step();
                    foreach ($records as $index => $record) {
                        $cost += $record['cost'];
                        if ($record['before'] === 0 && $record['backlog'] > 0) {
                            $this->emit(
                                'STOCKOUT', STAGE_NAMES[$index], 'week', $s->week,
                                'backlog', $record['backlog']
                            );
                        } elseif ($record['before'] > 0 && $record['backlog'] === 0) {
                            $this->emit('RECOVER', STAGE_NAMES[$index], 'week', $s->week);
                        }
                    }
                }
                $demand = array_sum(array_slice(
                    $s->demands, $first - 1, $s->week - $first + 1
                ));
                $this->emit('RUN', $first . '-' . $s->week, 'demand', $demand, 'cost', money($cost));
                if ($s->week === count($s->demands)) {
                    $this->emit('HORIZON', $s->week);
                }
                break;
            case 'RESET':
                $this->initialize();
                $this->emit('RESET', 'week', 0);
                break;
            case 'SAVE':
                $this->snapshots[$a[0]] = unserialize(serialize($s));
                $this->emit('SAVE', $a[0], 'week', $s->week);
                break;
            case 'LOAD':
                if (!array_key_exists($a[0], $this->snapshots)) {
                    fail('no snapshot ' . $a[0]);
                }
                $this->simulation = unserialize(serialize($this->snapshots[$a[0]]));
                $this->emit('LOAD', $a[0], 'week', $this->simulation->week);
                break;
            case 'SET':
                $indices = $this->target($a[0]);
                $policy = parsePolicy(array_slice($a, 1));
                foreach ($indices as $index) {
                    $s->setPolicy($index, $policy);
                }
                $this->emit('SET', $a[0], $policy['text']);
                break;
            case 'BATCH':
                $index = $this->stageIndex($a[0]);
                $lot = (int) $a[1];
                if ($lot < 1 || $lot > 100) {
                    fail('invalid batch size ' . $a[1]);
                }
                $s->stages[$index]->lot = $lot;
                $this->emit('BATCH', $a[0], $lot);
                break;
            case 'CAPACITY':
                $index = $a[0] === 'PLANT' ? null : $this->stageIndex($a[0]);
                $capacity = $a[1] === 'OFF' ? null : (int) $a[1];
                if ($capacity !== null && $capacity > 10000) {
                    fail('invalid capacity ' . $a[1]);
                }
                if ($index === null) {
                    $s->plantCapacity = $capacity;
                } else {
                    $s->stages[$index]->capacity = $capacity;
                }
                $this->emit('CAPACITY', $a[0], $a[1]);
                break;
            case 'COST':
                $index = $this->stageIndex($a[0]);
                $holding = (int) $a[1];
                $backlog = (int) $a[2];
                if ($holding > 1000 || $backlog > 1000) {
                    fail('invalid cost');
                }
                $s->stages[$index]->holding = $holding;
                $s->stages[$index]->backlogRate = $backlog;
                $this->emit('COST', $a[0], 'holding', $holding, 'backlog', $backlog);
                break;
            case 'VISIBILITY':
                if (!in_array($a[0], ['ON', 'OFF'], true)) {
                    fail('unknown visibility ' . $a[0]);
                }
                $s->visibility = $a[0];
                $this->emit('VISIBILITY', $a[0]);
                break;
            case 'SHOCK':
                $week = (int) $a[0];
                $demand = (int) $a[1];
                if ($week < 1 || $week > count($s->demands)) {
                    fail('week ' . $a[0] . ' outside horizon');
                }
                if ($week <= $s->week) {
                    fail('week ' . $a[0] . ' already simulated');
                }
                $old = $s->demands[$week - 1];
                $s->demands[$week - 1] = $demand;
                $this->emit('SHOCK', 'week', $week, $old, '->', $demand);
                break;
            case 'STATUS':
                $this->showStatus();
                break;
            case 'SETTINGS':
                $this->emit('SETTINGS');
                foreach ($s->stages as $index => $stage) {
                    $initial = $this->initials[$index];
                    $this->emit(
                        STAGE_NAMES[$index], 'holding', $stage->holding,
                        'backlog', $stage->backlogRate, 'batch', $stage->lot,
                        'capacity', $stage->capacity ?? 'OFF',
                        'delays', $initial['shipping'], $initial['orders']
                    );
                }
                $this->emit('PLANT', 'capacity', $s->plantCapacity ?? 'OFF');
                $this->emit('VISIBILITY', $s->visibility);
                break;
            case 'WEEK':
                $this->requireWeeks();
                $week = (int) $a[0];
                if ($week < 1 || $week > $s->week) {
                    fail('bad week ' . $a[0]);
                }
                $this->showWeek($week);
                break;
            case 'TABLE':
                $index = $this->stageIndex($a[0]);
                $this->requireWeeks();
                [$first, $last] = $this->rangeCheck(array_slice($a, 1), $s->week);
                $this->showTable($index, $first, $last);
                break;
            case 'CHAIN':
                $this->requireWeeks();
                [$first, $last] = $this->rangeCheck($a, $s->week);
                $this->emit('CHAIN', $first . '-' . $last);
                $header = [
                    str_pad('week', 4, ' ', STR_PAD_LEFT),
                    str_pad('demand', 6, ' ', STR_PAD_LEFT),
                ];
                foreach (STAGE_NAMES as $stage) {
                    $header[] = str_pad($stage, 11, ' ', STR_PAD_LEFT);
                }
                $this->emit(implode(' ', $header));
                for ($week = $first; $week <= $last; ++$week) {
                    $fields = [
                        str_pad((string) $week, 4, ' ', STR_PAD_LEFT),
                        str_pad((string) $s->demands[$week - 1], 6, ' ', STR_PAD_LEFT),
                    ];
                    foreach ($s->stages as $stage) {
                        $fields[] = str_pad((string) $stage->records[$week - 1]['order'],
                                            11, ' ', STR_PAD_LEFT);
                    }
                    $this->emit(implode(' ', $fields));
                }
                break;
            case 'DEMANDS':
                [$first, $last] = $this->rangeCheck($a, count($s->demands));
                $values = array_slice($s->demands, $first - 1, $last - $first + 1);
                $this->emit(
                    'DEMANDS', $first . '-' . $last,
                    'total', array_sum($values), 'min', min($values), 'max', max($values)
                );
                $this->emit(implode(' ', $values));
                break;
            case 'COSTS':
                $this->showCosts();
                break;
            case 'SUMMARY':
                $this->requireWeeks();
                $this->emit('SUMMARY', 'weeks', '1-' . $s->week);
                foreach ($s->stages as $index => $stage) {
                    $inventories = array_column($stage->records, 'inventory');
                    $backlogs = array_column($stage->records, 'backlog');
                    $orders = array_column($stage->records, 'order');
                    $this->emit(
                        STAGE_NAMES[$index],
                        'avg_inv', decimal(array_sum($inventories), $s->week, 2),
                        'avg_back', decimal(array_sum($backlogs), $s->week, 2),
                        'orders', array_sum($orders), 'min', min($orders),
                        'max', max($orders), 'zero_weeks', count(array_filter(
                            $orders, static fn(int $v): bool => $v === 0
                        ))
                    );
                }
                break;
            case 'BALANCE':
                $this->emit('BALANCE', 'week', $s->week);
                $initialGoods = 0;
                $produced = 0;
                $delivered = 0;
                $stock = 0;
                $transit = 0;
                foreach ($s->stages as $index => $stage) {
                    $initial = $this->initials[$index];
                    $received = array_sum(array_column($stage->records, 'received'));
                    $shipped = array_sum(array_column($stage->records, 'shipped'));
                    $this->emit(
                        STAGE_NAMES[$index], 'start', $initial['inventory'],
                        'received', $received, 'shipped', $shipped,
                        'end', $stage->inventory, 'owed', $stage->backlog
                    );
                    $initialGoods += $initial['inventory'] +
                                     $initial['quantity'] * $initial['shipping'];
                    if ($index === 0) {
                        $delivered = $shipped;
                    }
                    $stock += $stage->inventory;
                    $transit += array_sum($stage->shipping);
                }
                $produced = array_sum(array_column($s->plantRecords, 'produced'));
                $this->emit(
                    'SYSTEM', 'initial', $initialGoods, 'produced', $produced,
                    'delivered', $delivered, 'stock', $stock, 'transit', $transit
                );
                break;
            case 'FILLRATE':
                $this->requireWeeks();
                $this->emit('FILLRATE', 'weeks', '1-' . $s->week);
                foreach ($s->stages as $index => $stage) {
                    [$ordered, $ontime, $fill] = self::fillText($stage->records);
                    $stockouts = count(array_filter(
                        $stage->records,
                        static fn(array $r): bool => $r['backlog'] > 0
                    ));
                    $this->emit(
                        STAGE_NAMES[$index], 'fill', $fill, 'ontime', $ontime,
                        'ordered', $ordered, 'stockout_weeks', $stockouts,
                        'service', decimal(($s->week - $stockouts) * 100, $s->week, 2) . '%'
                    );
                }
                break;
            case 'BULLWHIP':
                $this->requireWeeks();
                $this->showBullwhip();
                break;
            case 'PEAKS':
                $this->requireWeeks();
                $this->showPeaks();
                break;
            case 'LEADTIME':
                $index = $this->stageIndex($a[0]);
                $this->requireWeeks();
                $this->showLeadtime($index);
                break;
            case 'PLOT':
            case 'HISTOGRAM':
                $index = $this->stageIndex($a[0]);
                $this->modeCheck($a[1]);
                if ($command === 'HISTOGRAM') {
                    $width = (int) $a[2];
                    if ($width < 1 || $width > 100) {
                        fail('invalid width ' . $a[2]);
                    }
                }
                $this->requireWeeks();
                if ($command === 'PLOT') {
                    [$first, $last] = $this->rangeCheck(array_slice($a, 2), $s->week);
                    $this->showPlot($index, $a[1], $first, $last);
                } else {
                    $this->showHistogram($index, $a[1], $width);
                }
                break;
            case 'COMPARE':
                $policies = [];
                $start = 0;
                for ($end = 0; $end <= count($a); ++$end) {
                    if ($end === count($a) || $a[$end] === '/') {
                        $policies[] = parsePolicy(array_slice($a, $start, $end - $start));
                        $start = $end + 1;
                    }
                }
                $rows = [];
                foreach ($policies as $index => $policy) {
                    $trial = $this->trial(array_fill(0, 4, $policy));
                    $cost = array_sum($trial->costs());
                    [, , $fill] = self::fillText($trial->stages[0]->records);
                    $demandVariation = variation($trial->demands);
                    $factoryVariation = variation(array_column($trial->stages[3]->records, 'order'));
                    $ratio = $demandVariation === 0
                        ? 'n/a' : decimal($factoryVariation, $demandVariation, 4);
                    $rows[] = [
                        'cost' => $cost, 'index' => $index, 'policy' => $policy['text'],
                        'fill' => $fill, 'ratio' => $ratio,
                    ];
                }
                usort($rows, static fn(array $a, array $b): int =>
                    ($a['cost'] <=> $b['cost']) ?: ($a['index'] <=> $b['index']));
                $this->emit('COMPARE', count($policies), 'weeks', count($s->demands));
                foreach ($rows as $rank => $row) {
                    $this->emit(
                        $rank + 1, $row['policy'], 'total', money($row['cost']),
                        'fill', $row['fill'], 'bullwhip', $row['ratio']
                    );
                }
                break;
            case 'OPTIMIZE':
                $indices = $this->target($a[0]);
                $low = (int) $a[1];
                $high = (int) $a[2];
                if ($low > $high) {
                    fail('bad range ' . $a[1] . ' ' . $a[2]);
                }
                if ($high - $low > 200) {
                    fail('range too large');
                }
                $best = null;
                for ($target = $low; $target <= $high; ++$target) {
                    $policies = array_map(
                        static fn(Stage $stage): array => $stage->policy, $s->stages
                    );
                    $replacement = [
                        'name' => 'BASESTOCK', 'args' => [$target],
                        'text' => 'BASESTOCK ' . $target,
                    ];
                    foreach ($indices as $index) {
                        $policies[$index] = $replacement;
                    }
                    $trial = $this->trial($policies);
                    $costs = $trial->costs();
                    $objective = 0;
                    foreach ($indices as $index) {
                        $objective += $costs[$index];
                    }
                    if ($best === null || $objective < $best[0]) {
                        $best = [$objective, $target, array_sum($costs)];
                    }
                }
                $this->emit(
                    'OPTIMIZE', $a[0], 'BASESTOCK', $best[1],
                    'cost', money($best[0]), 'total', money($best[2])
                );
                break;
            default:
                fail('unknown command ' . $command);
        }
    }

    public function execute(string $line): void
    {
        $parts = explode(' ', $line);
        $command = array_shift($parts);
        try {
            $this->command($command, $parts);
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }

    public function output(): string
    {
        return $this->output ? implode("\n", $this->output) . "\n" : '';
    }
}

$settings = [];
for ($i = 0; $i < 4; ++$i) {
    $settings[] = explode(' ', trim((string) fgets(STDIN)));
}
$game = new Game($settings);
while (($line = fgets(STDIN)) !== false) {
    $line = rtrim($line, "\r\n");
    if ($line === 'END') {
        break;
    }
    $game->execute($line);
}
echo $game->output();
