<?php

declare(strict_types=1);

const STATIONS = ['GRILL', 'FRY', 'COLD', 'BAR'];
const COURSES = ['DRINK', 'STARTER', 'MAIN', 'DESSERT'];

final class CommandError extends RuntimeException {}

function cents(string $value): int
{
    return (int) str_replace('.', '', $value);
}

function money(int $value): string
{
    return intdiv($value, 100) . '.' . str_pad((string) ($value % 100), 2, '0', STR_PAD_LEFT);
}

function clockTime(int $time): string
{
    $minutes = 660 + $time;
    return sprintf('%02d:%02d', intdiv($minutes, 60), $minutes % 60);
}

function rounded(int $value, int $rate): int
{
    return intdiv($value * $rate + 50, 100);
}

function lineAmount(object $line): int
{
    return $line->reason === null ? $line->price * $line->quantity : 0;
}

function activeLines(object $check): array
{
    return array_values(array_filter(
        $check->lines,
        static fn(object $line): bool => $line->state !== 'VOID'
    ));
}

final class Restaurant
{
    public array $output = [];

    private int $now = 0;
    private array $tables = [];
    private array $servers = [];
    private array $waiting = [];
    private array $menu = [];
    private array $lines = [];
    private array $stations = [];

    private int $happyRate = 0;
    private int $happyEnd = 0;
    private int $covers = 0;
    private int $parties = 0;
    private int $turns = 0;
    private int $stay = 0;
    private array $sales = ['DRINK' => 0, 'STARTER' => 0, 'MAIN' => 0, 'DESSERT' => 0];
    private array $totals = [
        'subtotal' => 0, 'discount' => 0, 'service' => 0, 'tax' => 0, 'total' => 0,
    ];
    private array $payments = ['CASH' => 0, 'CARD' => 0];
    private int $tips = 0;
    private int $comps = 0;
    private int $compAmount = 0;
    private int $voids = 0;
    private array $served = [];

    public function __construct()
    {
        foreach (STATIONS as $name) {
            $this->stations[$name] = (object) [
                'name' => $name, 'capacity' => $name === 'BAR' ? 2 : 1,
                'up' => true, 'queue' => [], 'cooking' => [],
                'tickets' => [], 'remakes' => 0,
            ];
        }
    }

    private function emit(string|int ...$parts): void
    {
        $this->output[] = implode(' ', $parts);
    }

    private function table(string $text): object
    {
        $number = (int) $text;
        if (!isset($this->tables[$number])) {
            throw new CommandError('unknown table ' . $text);
        }
        return $this->tables[$number];
    }

    private function check(string $text): object
    {
        $table = $this->table($text);
        if ($table->check === null) {
            throw new CommandError('table ' . $text . ' is free');
        }
        return $table->check;
    }

    private function unlocked(object $check): void
    {
        if ($check->paid > 0) {
            throw new CommandError('check for table ' . $check->table->number . ' is locked');
        }
    }

    private function line(string $text): object
    {
        $number = (int) $text;
        if ($number < 1 || $number > count($this->lines)) {
            throw new CommandError('unknown line ' . $text);
        }
        return $this->lines[$number - 1];
    }

    private function modifiable(object $line): void
    {
        if ($line->state === 'VOID') {
            throw new CommandError('#' . $line->id . ' is void');
        }
        if ($line->check->closed) {
            throw new CommandError('#' . $line->id . ' is on a closed check');
        }
        $this->unlocked($line->check);
    }

    private function unserved(object $check): void
    {
        $count = 0;
        foreach (activeLines($check) as $line) {
            if ($line->state !== 'SERVED') {
                ++$count;
            }
        }
        if ($count > 0) {
            throw new CommandError(
                'table ' . $check->table->number . ' has ' . $count . ' unserved items'
            );
        }
    }

    private function station(string $name): object
    {
        if (!isset($this->stations[$name])) {
            throw new CommandError('unknown station ' . $name);
        }
        return $this->stations[$name];
    }

    private function course(string $name): void
    {
        if (!in_array($name, COURSES, true)) {
            throw new CommandError('unknown course ' . $name);
        }
    }

    private function item(string $name): object
    {
        if (!isset($this->menu[$name])) {
            throw new CommandError('unknown item ' . $name);
        }
        return $this->menu[$name];
    }

    private function load(object $server): int
    {
        $count = 0;
        foreach ($this->tables as $table) {
            if ($table->check !== null && $table->check->server === $server) {
                ++$count;
            }
        }
        return $count;
    }

    private function selectTable(int $size): ?object
    {
        $best = null;
        foreach ($this->tables as $table) {
            if ($table->check !== null || $table->seats < $size) {
                continue;
            }
            if ($best === null || $table->seats < $best->seats ||
                ($table->seats === $best->seats && $table->number < $best->number)) {
                $best = $table;
            }
        }
        return $best;
    }

    private function seat(string $party, int $size, object $table): object
    {
        $server = $this->servers[0];
        foreach ($this->servers as $candidate) {
            if ($this->load($candidate) < $this->load($server)) {
                $server = $candidate;
            }
        }
        $check = (object) [
            'party' => $party, 'size' => $size, 'table' => $table,
            'server' => $server, 'seated' => $this->now, 'lines' => [],
            'paid' => 0, 'discount' => 0, 'closed' => false,
        ];
        $table->check = $check;
        ++$server->parties;
        $this->covers += $size;
        ++$this->parties;
        return $check;
    }

    private function processWaiting(): void
    {
        $remaining = [];
        foreach ($this->waiting as $entry) {
            $table = $this->selectTable($entry->size);
            if ($table === null) {
                $remaining[] = $entry;
                continue;
            }
            $check = $this->seat($entry->party, $entry->size, $table);
            $this->emit(
                'SEATED', $entry->party, $entry->size, 'table', $table->number,
                'server', $check->server->name, 'waited', $this->now - $entry->joined
            );
        }
        $this->waiting = $remaining;
    }

    private function amounts(object $check): array
    {
        $subtotal = 0;
        foreach (activeLines($check) as $line) {
            $subtotal += lineAmount($line);
        }
        $discount = rounded($subtotal, $check->discount);
        $after = $subtotal - $discount;
        $service = $check->size >= 6 ? rounded($after, 18) : 0;
        $tax = rounded($after, 8);
        $total = $after + $service + $tax;
        return compact('subtotal', 'discount', 'service', 'tax', 'total') +
               ['due' => $total - $check->paid];
    }

    private function close(object $check): void
    {
        $amounts = $this->amounts($check);
        ++$this->turns;
        $this->stay += $this->now - $check->seated;
        foreach (activeLines($check) as $line) {
            $this->sales[$line->course] += lineAmount($line);
        }
        foreach (['subtotal', 'discount', 'service', 'tax', 'total'] as $key) {
            $this->totals[$key] += $amounts[$key];
        }
        $check->server->sales += $amounts['total'];
        $check->closed = true;
        $check->table->check = null;
        $this->emit(
            'FREE', 'table', $check->table->number, $check->party,
            'stayed', $this->now - $check->seated
        );
        $this->processWaiting();
    }

    private function start(object $station, int $time): void
    {
        while ($station->up && $station->queue !== [] &&
               count($station->cooking) < $station->capacity) {
            $line = array_shift($station->queue);
            $line->state = 'COOKING';
            $line->ready = $time + $line->prep;
            $line->started = true;
            $station->cooking[] = $line;
        }
    }

    private function tick(int $minutes): void
    {
        $end = $this->now + $minutes;
        $this->emit('TICK', clockTime($end));
        while (true) {
            $earliest = null;
            foreach (STATIONS as $name) {
                foreach ($this->stations[$name]->cooking as $line) {
                    if ($earliest === null || $line->ready < $earliest) {
                        $earliest = $line->ready;
                    }
                }
            }
            if ($earliest === null || $earliest > $end) {
                break;
            }
            foreach (STATIONS as $name) {
                $station = $this->stations[$name];
                $finished = [];
                $remaining = [];
                foreach ($station->cooking as $line) {
                    if ($line->ready === $earliest) {
                        $finished[] = $line;
                    } else {
                        $remaining[] = $line;
                    }
                }
                $station->cooking = $remaining;
                usort($finished, static fn(object $a, object $b): int => $a->id <=> $b->id);
                foreach ($finished as $line) {
                    $line->state = 'READY';
                    $station->tickets[] = $earliest - $line->fire;
                    $this->emit(
                        'READY', clockTime($earliest), $name, '#' . $line->id,
                        $line->item, 'x' . $line->quantity, 'table',
                        $line->check->table->number, 'seat', $line->seat
                    );
                }
            }
            foreach (STATIONS as $name) {
                $this->start($this->stations[$name], $earliest);
            }
        }
        $this->now = $end;
    }

    private function seatSubtotals(object $check): array
    {
        $subtotals = [];
        foreach (activeLines($check) as $line) {
            $subtotals[$line->seat] = ($subtotals[$line->seat] ?? 0) + lineAmount($line);
        }
        ksort($subtotals, SORT_NUMERIC);
        return $subtotals;
    }

    private function allocate(array $values, int $rate): array
    {
        $allocated = [];
        foreach ($values as $seat => $subtotal) {
            $allocated[$seat] = intdiv($subtotal * $rate, 100);
        }
        $left = rounded(array_sum($values), $rate) - array_sum($allocated);
        $order = array_keys($values);
        usort($order, static function (int $a, int $b) use ($values, $rate): int {
            $first = ($values[$a] * $rate) % 100;
            $second = ($values[$b] * $rate) % 100;
            return ($second <=> $first) ?: ($a <=> $b);
        });
        for ($i = 0; $i < $left; ++$i) {
            ++$allocated[$order[$i]];
        }
        return $allocated;
    }

    private function bill(object $check): void
    {
        $this->emit('BILL', 'table', $check->table->number, $check->party, 'guests', $check->size);
        foreach ($this->seatSubtotals($check) as $seat => $subtotal) {
            $this->emit('SEAT', (int) $seat, money($subtotal));
            foreach (activeLines($check) as $line) {
                if ($line->seat !== $seat) {
                    continue;
                }
                $parts = ['#' . $line->id, $line->item, 'x' . $line->quantity, money(lineAmount($line))];
                if ($line->reason !== null) {
                    $parts[] = 'COMP';
                    $parts[] = $line->reason;
                }
                $this->emit(...$parts);
            }
        }
        $amounts = $this->amounts($check);
        $this->emit('SUBTOTAL', money($amounts['subtotal']));
        if ($check->discount !== 0) {
            $this->emit('DISCOUNT', $check->discount . '%', money($amounts['discount']));
        }
        if ($check->size >= 6) {
            $this->emit('SERVICE', money($amounts['service']));
        }
        $this->emit('TAX', money($amounts['tax']));
        $this->emit('TOTAL', money($amounts['total']));
        if ($check->paid > 0) {
            $this->emit('PAID', money($check->paid));
            $this->emit('DUE', money($amounts['due']));
        }
    }

    private function report(): void
    {
        $this->emit('REPORT', clockTime($this->now));
        $this->emit('COVERS', $this->covers, 'parties', $this->parties);
        $average = $this->turns ? intdiv($this->stay, $this->turns) : '-';
        $this->emit('TURNS', $this->turns, 'avg_stay', $average);
        $parts = ['SALES'];
        foreach (COURSES as $course) {
            $parts[] = $course;
            $parts[] = money($this->sales[$course]);
        }
        $this->emit(...$parts);
        $parts = ['TOTALS'];
        foreach (['subtotal', 'discount', 'service', 'tax', 'total'] as $field) {
            $parts[] = $field;
            $parts[] = money($this->totals[$field]);
        }
        $this->emit(...$parts);
        $this->emit(
            'PAYMENTS', 'cash', money($this->payments['CASH']),
            'card', money($this->payments['CARD']), 'tips', money($this->tips)
        );
        $this->emit('COMPS', $this->comps, money($this->compAmount), 'VOIDS', $this->voids);
        $names = array_keys(array_filter($this->served, static fn(int $count): bool => $count > 0));
        usort($names, function (string $a, string $b): int {
            return ($this->served[$b] <=> $this->served[$a]) ?: strcmp($a, $b);
        });
        foreach (array_slice($names, 0, 3) as $index => $name) {
            $this->emit('TOP', $index + 1, $name, $this->served[$name]);
        }
        foreach (STATIONS as $name) {
            $station = $this->stations[$name];
            $count = count($station->tickets);
            $this->emit(
                $name, 'tickets', $count, 'avg', $count ? intdiv(array_sum($station->tickets), $count) : '-',
                'max', $count ? max($station->tickets) : '-', 'remakes', $station->remakes
            );
        }
        foreach ($this->servers as $server) {
            $this->emit(
                'SERVER', $server->name, 'tables', $this->load($server),
                'parties', $server->parties, 'sales', money($server->sales),
                'tips', money($server->tips)
            );
        }
    }

    private function command(string $command, array $a): void
    {
        switch ($command) {
            case 'TABLE':
                $number = (int) $a[0];
                if (isset($this->tables[$number])) {
                    throw new CommandError('table ' . $a[0] . ' already exists');
                }
                $this->tables[$number] = (object) [
                    'number' => $number, 'seats' => (int) $a[1], 'check' => null,
                ];
                $this->emit('TABLE', $number, 'seats', (int) $a[1]);
                $this->processWaiting();
                break;

            case 'STAFF':
                foreach ($this->servers as $server) {
                    if ($server->name === $a[0]) {
                        throw new CommandError($a[0] . ' is already on duty');
                    }
                }
                $this->servers[] = (object) [
                    'name' => $a[0], 'parties' => 0, 'sales' => 0, 'tips' => 0,
                ];
                $this->emit('STAFF', $a[0]);
                break;

            case 'SEAT':
                foreach ($this->tables as $table) {
                    if ($table->check !== null && $table->check->party === $a[0]) {
                        throw new CommandError(
                            $a[0] . ' is already seated at table ' . $table->number
                        );
                    }
                }
                foreach ($this->waiting as $entry) {
                    if ($entry->party === $a[0]) {
                        throw new CommandError($a[0] . ' is already waiting');
                    }
                }
                $size = (int) $a[1];
                $accommodates = false;
                foreach ($this->tables as $table) {
                    if ($table->seats >= $size) {
                        $accommodates = true;
                        break;
                    }
                }
                if (!$accommodates) {
                    throw new CommandError('no table for party of ' . $size);
                }
                if ($this->servers === []) {
                    throw new CommandError('no server on duty');
                }
                $table = $this->selectTable($size);
                if ($table === null) {
                    $this->waiting[] = (object) [
                        'party' => $a[0], 'size' => $size, 'joined' => $this->now,
                    ];
                    $this->emit('WAIT', $a[0], $size, 'position', count($this->waiting));
                } else {
                    $check = $this->seat($a[0], $size, $table);
                    $this->emit(
                        'SEAT', $a[0], $size, 'table', $table->number,
                        'server', $check->server->name
                    );
                }
                break;

            case 'CANCEL':
                foreach ($this->waiting as $i => $entry) {
                    if ($entry->party === $a[0]) {
                        array_splice($this->waiting, $i, 1);
                        $this->emit(
                            'CANCEL', $entry->party, $entry->size,
                            'waited', $this->now - $entry->joined
                        );
                        return;
                    }
                }
                throw new CommandError($a[0] . ' is not waiting');

            case 'MOVE':
                $source = $this->table($a[0]);
                $destination = $this->table($a[1]);
                if ($source->check === null) {
                    throw new CommandError('table ' . $a[0] . ' is free');
                }
                if ($destination->check !== null) {
                    throw new CommandError('table ' . $a[1] . ' is occupied');
                }
                $check = $source->check;
                if ($destination->seats < $check->size) {
                    throw new CommandError('table ' . $a[1] . ' is too small for ' . $check->party);
                }
                $source->check = null;
                $destination->check = $check;
                $check->table = $destination;
                $this->emit(
                    'MOVE', $check->party, 'table', $source->number, '->', $destination->number
                );
                $this->processWaiting();
                break;

            case 'MENU':
                $this->station($a[1]);
                $this->course($a[4]);
                $old = $this->menu[$a[0]] ?? null;
                $this->menu[$a[0]] = (object) [
                    'name' => $a[0], 'station' => $a[1], 'prep' => (int) $a[2],
                    'price' => cents($a[3]), 'course' => $a[4],
                    'stock' => $old?->stock,
                ];
                $this->emit(
                    'MENU', $old === null ? 'ADD' : 'UPDATE', $a[0], $a[1],
                    (int) $a[2], money(cents($a[3])), $a[4]
                );
                break;

            case 'STOCK':
                $item = $this->item($a[0]);
                $item->stock = (int) $a[1];
                $this->emit('STOCK', $item->name, $item->stock);
                break;

            case 'HAPPY':
                $this->happyRate = (int) $a[0];
                $this->happyEnd = $this->now + (int) $a[1];
                $this->emit(
                    'HAPPY', $this->happyRate . '%', 'until', clockTime($this->happyEnd)
                );
                break;

            case 'ITEMS':
                $items = array_values($this->menu);
                usort($items, static function (object $a, object $b): int {
                    return (array_search($a->course, COURSES, true) <=>
                            array_search($b->course, COURSES, true)) ?: strcmp($a->name, $b->name);
                });
                $this->emit('ITEMS', count($items));
                foreach ($items as $item) {
                    $this->emit(
                        $item->course, $item->name, $item->station, $item->prep,
                        money($item->price), $item->stock === null ? '-' : $item->stock
                    );
                }
                break;

            case 'ORDER':
                $check = $this->check($a[0]);
                $this->unlocked($check);
                $seat = (int) $a[1];
                if ($seat > $check->size) {
                    throw new CommandError(
                        'seat ' . $seat . ' out of range for table ' . $a[0]
                    );
                }
                $item = $this->item($a[2]);
                $quantity = (int) $a[3];
                if ($item->stock !== null && $item->stock < $quantity) {
                    throw new CommandError('only ' . $item->stock . ' ' . $item->name . ' left');
                }
                $happy = $item->course === 'DRINK' && $this->now < $this->happyEnd;
                $price = $item->price - ($happy ? rounded($item->price, $this->happyRate) : 0);
                $line = (object) [
                    'id' => count($this->lines) + 1, 'check' => $check,
                    'seat' => $seat, 'item' => $item->name, 'quantity' => $quantity,
                    'station' => $item->station, 'prep' => $item->prep,
                    'price' => $price, 'course' => $item->course,
                    'state' => 'ORDERED', 'reason' => null,
                    'fire' => 0, 'ready' => 0, 'started' => false,
                ];
                $this->lines[] = $line;
                $check->lines[] = $line;
                $parts = [
                    'ORDER', '#' . $line->id, 'table', $check->table->number,
                    'seat', $seat, $item->name, 'x' . $quantity, money(lineAmount($line)),
                ];
                if ($happy) {
                    $parts[] = 'HAPPY';
                }
                $this->emit(...$parts);
                if ($item->stock !== null) {
                    $item->stock -= $quantity;
                    if ($item->stock === 0) {
                        $this->emit('SOLDOUT', $item->name);
                    }
                }
                break;

            case 'FIRE':
                $check = $this->check($a[0]);
                $this->course($a[1]);
                $lines = [];
                foreach ($check->lines as $line) {
                    if ($line->course === $a[1] && $line->state === 'ORDERED') {
                        $lines[] = $line;
                    }
                }
                if ($lines === []) {
                    throw new CommandError(
                        'nothing to fire for ' . $a[1] . ' at table ' . $a[0]
                    );
                }
                $priorCourses = ['STARTER', 'MAIN', 'DESSERT'];
                $position = array_search($a[1], $priorCourses, true);
                if ($position !== false) {
                    foreach (array_slice($priorCourses, 0, $position) as $earlier) {
                        foreach ($check->lines as $line) {
                            if ($line->course === $earlier && $line->state === 'ORDERED') {
                                throw new CommandError('fire ' . $earlier . ' first');
                            }
                        }
                    }
                }
                $parts = ['FIRE', 'table', $check->table->number, $a[1]];
                foreach ($lines as $line) {
                    $line->state = 'QUEUED';
                    $line->fire = $this->now;
                    $this->stations[$line->station]->queue[] = $line;
                    $parts[] = '#' . $line->id;
                }
                $this->emit(...$parts);
                foreach (STATIONS as $station) {
                    $this->start($this->stations[$station], $this->now);
                }
                break;

            case 'TICK':
                $this->tick((int) $a[0]);
                break;

            case 'SERVE':
                $check = $this->check($a[0]);
                $lines = array_values(array_filter(
                    $check->lines,
                    static fn(object $line): bool => $line->state === 'READY'
                ));
                if ($lines === []) {
                    throw new CommandError('nothing ready for table ' . $a[0]);
                }
                $parts = ['SERVE', 'table', $check->table->number];
                foreach ($lines as $line) {
                    $line->state = 'SERVED';
                    $this->served[$line->item] = ($this->served[$line->item] ?? 0) +
                                                  $line->quantity;
                    $parts[] = '#' . $line->id;
                }
                $this->emit(...$parts);
                break;

            case 'RUSH':
                $line = $this->line($a[0]);
                if ($line->state !== 'QUEUED') {
                    throw new CommandError('#' . $line->id . ' is not queued');
                }
                $station = $this->stations[$line->station];
                $station->queue = array_merge(
                    [$line],
                    array_values(array_filter(
                        $station->queue,
                        static fn(object $candidate): bool => $candidate !== $line
                    ))
                );
                $this->emit('RUSH', '#' . $line->id, $line->station);
                break;

            case 'REMAKE':
                $line = $this->line($a[0]);
                if ($line->check->closed) {
                    throw new CommandError('#' . $line->id . ' is on a closed check');
                }
                if ($line->state !== 'READY' && $line->state !== 'SERVED') {
                    throw new CommandError('#' . $line->id . ' is not ready or served');
                }
                $line->state = 'QUEUED';
                $line->fire = $this->now;
                $station = $this->stations[$line->station];
                array_unshift($station->queue, $line);
                ++$station->remakes;
                $this->emit('REMAKE', '#' . $line->id, $line->item, $line->station);
                $this->start($station, $this->now);
                break;

            case 'VOID':
                $line = $this->line($a[0]);
                if ($line->state === 'VOID') {
                    throw new CommandError('#' . $line->id . ' is already void');
                }
                if ($line->started) {
                    throw new CommandError('#' . $line->id . ' has already started');
                }
                if ($line->state === 'QUEUED') {
                    $station = $this->stations[$line->station];
                    $station->queue = array_values(array_filter(
                        $station->queue,
                        static fn(object $candidate): bool => $candidate !== $line
                    ));
                }
                $line->state = 'VOID';
                $item = $this->menu[$line->item];
                if ($item->stock !== null) {
                    $item->stock += $line->quantity;
                }
                ++$this->voids;
                $this->emit('VOID', '#' . $line->id, $line->item, 'x' . $line->quantity);
                break;

            case 'STATION':
                $station = $this->station($a[0]);
                if ($a[1] === 'DOWN' && !$station->up) {
                    throw new CommandError('station ' . $station->name . ' is already down');
                }
                if ($a[1] === 'UP' && $station->up) {
                    throw new CommandError('station ' . $station->name . ' is not down');
                }
                $station->up = $a[1] === 'UP';
                if ($station->up) {
                    $this->start($station, $this->now);
                }
                $this->emit('STATION', $station->name, $a[1]);
                break;

            case 'COMP':
            case 'TRANSFER':
                $line = $this->line($a[0]);
                $this->modifiable($line);
                if ($command === 'COMP') {
                    if ($line->reason !== null) {
                        throw new CommandError('#' . $line->id . ' is already comped');
                    }
                    $value = lineAmount($line);
                    $this->emit('COMP', '#' . $line->id, $line->item, money($value), $a[1]);
                    ++$this->comps;
                    $this->compAmount += $value;
                    $line->reason = $a[1];
                } else {
                    $seat = (int) $a[1];
                    if ($seat > $line->check->size) {
                        throw new CommandError(
                            'seat ' . $seat . ' out of range for table ' . $line->check->table->number
                        );
                    }
                    if ($seat === $line->seat) {
                        throw new CommandError('#' . $line->id . ' is already on seat ' . $seat);
                    }
                    $this->emit('TRANSFER', '#' . $line->id, 'seat', $line->seat, '->', $seat);
                    $line->seat = $seat;
                }
                break;

            case 'DISCOUNT':
                $check = $this->check($a[0]);
                $this->unlocked($check);
                $check->discount = (int) $a[1];
                $this->emit('DISCOUNT', 'table', $check->table->number, $check->discount . '%');
                break;

            case 'BILL':
                $this->bill($this->check($a[0]));
                break;

            case 'SPLIT':
                $check = $this->check($a[0]);
                $amounts = $this->amounts($check);
                if ($amounts['due'] === 0) {
                    throw new CommandError('nothing to split for table ' . $a[0]);
                }
                if ($a[1] === 'EVEN') {
                    $count = (int) $a[2];
                    if ($count > $check->size) {
                        throw new CommandError(
                            'cannot split table ' . $a[0] . ' ' . $count . ' ways'
                        );
                    }
                    $this->emit(
                        'SPLIT', 'table', $check->table->number, 'EVEN', $count,
                        'due', money($amounts['due'])
                    );
                    $quotient = intdiv($amounts['due'], $count);
                    $remainder = $amounts['due'] % $count;
                    for ($i = 1; $i <= $count; ++$i) {
                        $this->emit('PAYER', $i, money($quotient + (int) ($i <= $remainder)));
                    }
                } else {
                    if ($check->paid > 0) {
                        throw new CommandError('table ' . $a[0] . ' has payments');
                    }
                    $values = $this->seatSubtotals($check);
                    $discounts = $this->allocate($values, $check->discount);
                    $after = [];
                    foreach ($values as $seat => $value) {
                        $after[$seat] = $value - $discounts[$seat];
                    }
                    $services = $this->allocate($after, $check->size >= 6 ? 18 : 0);
                    $taxes = $this->allocate($after, 8);
                    $this->emit(
                        'SPLIT', 'table', $check->table->number, 'BYSEAT',
                        'total', money($amounts['total'])
                    );
                    foreach ($values as $seat => $value) {
                        $this->emit(
                            'SEAT', (int) $seat, 'subtotal', money($value),
                            'discount', money($discounts[$seat]),
                            'service', money($services[$seat]),
                            'tax', money($taxes[$seat]),
                            'total', money($after[$seat] + $services[$seat] + $taxes[$seat])
                        );
                    }
                }
                break;

            case 'PAY':
                $check = $this->check($a[0]);
                if (!in_array($a[1], ['CASH', 'CARD'], true)) {
                    throw new CommandError('unknown method ' . $a[1]);
                }
                $this->unserved($check);
                $due = $this->amounts($check)['due'];
                if ($due === 0) {
                    throw new CommandError('nothing to pay for table ' . $a[0]);
                }
                $value = cents($a[2]);
                $applied = min($value, $due);
                $check->paid += $applied;
                $this->payments[$a[1]] += $applied;
                if ($value < $due) {
                    $this->emit(
                        'PAY', 'table', $check->table->number, $a[1],
                        money($value), 'remaining', money($due - $value)
                    );
                } else {
                    $this->emit(
                        'PAY', 'table', $check->table->number, $a[1],
                        money($value), $a[1] === 'CASH' ? 'change' : 'tip',
                        money($value - $due)
                    );
                    if ($a[1] === 'CARD') {
                        $this->tips += $value - $due;
                        $check->server->tips += $value - $due;
                    }
                    $this->close($check);
                }
                break;

            case 'CLOSE':
                $check = $this->check($a[0]);
                $this->unserved($check);
                $due = $this->amounts($check)['due'];
                if ($due !== 0) {
                    throw new CommandError(
                        'table ' . $a[0] . ' still owes ' . money($due)
                    );
                }
                $this->close($check);
                break;

            case 'STATUS':
                $check = $this->check($a[0]);
                $this->emit(
                    'STATUS', 'table', $check->table->number, $check->party,
                    'guests', $check->size, 'since', clockTime($check->seated)
                );
                foreach ($check->lines as $line) {
                    $parts = [
                        '#' . $line->id, 'seat', $line->seat, $line->item,
                        'x' . $line->quantity, $line->course, $line->state,
                    ];
                    if ($line->state === 'COOKING') {
                        $parts[] = 'until';
                        $parts[] = clockTime($line->ready);
                    }
                    if ($line->reason !== null) {
                        $parts[] = 'COMP';
                        $parts[] = $line->reason;
                    }
                    $this->emit(...$parts);
                }
                break;

            case 'KITCHEN':
                $this->emit('KITCHEN', clockTime($this->now));
                foreach (STATIONS as $name) {
                    $station = $this->stations[$name];
                    $cooking = $station->cooking;
                    usort($cooking, static fn(object $a, object $b): int =>
                        ($a->ready <=> $b->ready) ?: ($a->id <=> $b->id)
                    );
                    $ready = [];
                    foreach ($cooking as $line) {
                        $ready[] = '#' . $line->id . '@' . clockTime($line->ready);
                    }
                    $queue = [];
                    foreach ($station->queue as $line) {
                        $queue[] = '#' . $line->id;
                    }
                    $this->emit(
                        $name, $station->up ? 'up' : 'down', 'cooking',
                        $ready ? implode(' ', $ready) : '-', 'queue',
                        $queue ? implode(' ', $queue) : '-'
                    );
                }
                break;

            case 'FLOOR':
                $tables = array_values($this->tables);
                usort($tables, static fn(object $a, object $b): int => $a->number <=> $b->number);
                $free = count(array_filter(
                    $tables, static fn(object $table): bool => $table->check === null
                ));
                $this->emit(
                    'FLOOR', clockTime($this->now), 'free', $free,
                    'seated', count($tables) - $free, 'waiting', count($this->waiting)
                );
                foreach ($tables as $table) {
                    $check = $table->check;
                    if ($check === null) {
                        $this->emit('table', $table->number, 'seats', $table->seats, 'free');
                    } else {
                        $parts = [
                            'table', $table->number, 'seats', $table->seats,
                            $check->party, 'guests', $check->size, 'server',
                            $check->server->name, 'since', clockTime($check->seated),
                            'items', count(activeLines($check)), 'total',
                            money($this->amounts($check)['total']),
                        ];
                        if ($check->paid > 0) {
                            $parts[] = 'paid';
                            $parts[] = money($check->paid);
                        }
                        $this->emit(...$parts);
                    }
                }
                foreach ($this->waiting as $index => $entry) {
                    $this->emit(
                        'WAITING', $index + 1, $entry->party, $entry->size,
                        'since', clockTime($entry->joined)
                    );
                }
                break;

            case 'REPORT':
                $this->report();
                break;
        }
    }

    public function execute(string $text): void
    {
        $tokens = explode(' ', $text);
        $command = array_shift($tokens);
        try {
            $this->command($command, $tokens);
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }
}

$count = (int) trim((string) fgets(STDIN));
$restaurant = new Restaurant();
for ($i = 0; $i < $count; ++$i) {
    $restaurant->execute(rtrim((string) fgets(STDIN), "\r\n"));
}
if ($restaurant->output !== []) {
    echo implode("\n", $restaurant->output), "\n";
}
