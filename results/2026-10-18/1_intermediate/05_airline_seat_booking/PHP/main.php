<?php
const CLASSES = ['F', 'J', 'Y'];
const TIERS = ['PLATINUM' => 0, 'GOLD' => 1, 'SILVER' => 2, 'NONE' => 3];
$aircraft = [];
$flights = [];
$flightOrder = [];
$bookings = [];
$usedPNR = [];
$people = [];
$statuses = [];
$definition = null;

function fail(string $message): never
{
    throw new InvalidArgumentException($message);
}
function tier(object $p): string
{
    global $statuses;
    return $statuses[$p->name] ?? 'NONE';
}
function members(object $booking): array
{
    global $people;
    return array_values(array_filter($booking->people, fn($id) => $people[$id]->active));
}
function passengers(object $flight): array
{
    global $people;
    return array_values(array_filter($flight->people, fn($id) => $people[$id]->active));
}
function get_flight(string $id, bool $open = false): object
{
    global $flights;
    if (!isset($flights[$id])) {
        fail("unknown flight $id");
    }
    $f = $flights[$id];
    if ($open && $f->closed) {
        fail("flight $id is closed");
    }
    return $f;
}
function get_booking(string $pnr, bool $open = false): object
{
    global $bookings;
    if (!isset($bookings[$pnr]) || members($bookings[$pnr]) === []) {
        fail("unknown PNR $pnr");
    }
    $b = $bookings[$pnr];
    get_flight($b->flight, $open);
    return $b;
}
function get_person(object $b, string $name): object
{
    global $people;
    foreach (members($b) as $id) {
        if ($people[$id]->name === $name) {
            return $people[$id];
        }
    }
    fail("no passenger $name in $b->pnr");
}
function result(object $p): string
{
    return $p->type === 'INFANT' ? 'LAP' : ($p->seat === '' ? 'UNASSIGNED' : $p->seat);
}
function cabin(object $f, string $class): object
{
    if (!isset($f->model->cabins[$class])) {
        fail("no cabin $class on $f->id");
    }
    return $f->model->cabins[$class];
}
function booked(object $f, string $class): int
{
    global $people;
    $count = 0;
    foreach (passengers($f) as $id) {
        $p = $people[$id];
        if ($p->type !== 'INFANT' && $p->class === $class) {
            ++$count;
        }
    }
    return $count;
}
function allowed(object $f, object $p, string $seat, string $class, array $vacated = [], array $assignments = []): bool
{
    global $people;
    $s = $f->model->seats[$seat] ?? null;
    if ($s === null || $s->class !== $class || isset($f->blocked[$seat])) {
        return false;
    }
    if (isset($f->occupied[$seat]) && !isset($vacated[$f->occupied[$seat]])) {
        return false;
    }
    if (($p->type === 'CHILD' || $p->infant !== 0) && isset($f->model->exits[$s->row])) {
        return false;
    }
    if ($p->infant !== 0) {
        foreach ($f->occupied as $otherSeat => $id) {
            if ($id === $p->id || isset($vacated[$id]) || $people[$id]->infant === 0) {
                continue;
            }
            $t = $f->model->seats[$otherSeat];
            if ($t->row === $s->row && $t->block === $s->block) {
                return false;
            }
        }
        foreach ($assignments as $id => $otherSeat) {
            if ($id !== $p->id && $people[$id]->infant !== 0) {
                $t = $f->model->seats[$otherSeat];
                if ($t->row === $s->row && $t->block === $s->block) {
                    return false;
                }
            }
        }
    }
    return true;
}
function select_seat(object $f, object $p, ?string $class = null): string
{
    $class ??= $p->class;
    $first = '';
    foreach ($f->model->cabins[$class]->seats as $seat) {
        if (allowed($f, $p, $seat, $class)) {
            if ($first === '') {
                $first = $seat;
            }
            if ($p->pref !== '' && $f->model->seats[$seat]->kind === $p->pref) {
                return $seat;
            }
        }
    }
    return $first;
}
function move_to(object $f, object $p, string $seat): void
{
    if ($p->seat !== '') {
        unset($f->occupied[$p->seat]);
    }
    $p->seat = $seat;
    if ($seat !== '') {
        $f->occupied[$seat] = $p->id;
    }
}
function reassign(object $f, array &$output): void
{
    global $people;
    foreach (passengers($f) as $id) {
        $p = $people[$id];
        if ($p->type !== 'INFANT' && $p->seat === '') {
            $seat = select_seat($f, $p);
            if ($seat !== '') {
                move_to($f, $p, $seat);
                $output[] = "REASSIGNED $p->pnr $p->name $seat";
            }
        }
    }
}
function fits(object $f, array $ids, array $seats, string $class): bool
{
    global $people;
    $assignments = array_combine($ids, $seats);
    foreach ($ids as $index => $id) {
        if (!allowed($f, $people[$id], $seats[$index], $class, [], $assignments)) {
            return false;
        }
    }
    return true;
}
function group_seats(object $f, array $ids, string $class): array
{
    $c = $f->model->cabins[$class];
    $count = count($ids);
    foreach (['BLOCK', 'ROW'] as $method) {
        for ($row = $c->from; $row <= $c->to; ++$row) {
            $blocks = $method === 'BLOCK' ? $c->blocks : [implode('', $c->blocks)];
            foreach ($blocks as $block) {
                for ($x = 0; $x + $count <= strlen($block); ++$x) {
                    $seats = [];
                    for ($j = 0; $j < $count; ++$j) {
                        $seats[] = $row . $block[$x + $j];
                    }
                    if (fits($f, $ids, $seats, $class)) {
                        return [$method, $seats];
                    }
                }
            }
        }
    }
    for ($height = 2; $height <= $count; ++$height) {
        $width = intdiv($count + $height - 1, $height);
        $rows = intdiv($count + $width - 1, $width);
        for ($row = $c->from; $row + $rows - 1 <= $c->to; ++$row) {
            foreach ($c->blocks as $block) {
                for ($x = 0; $x + $width <= strlen($block); ++$x) {
                    $seats = [];
                    for ($j = 0; $j < $count; ++$j) {
                        $seats[] = ($row + intdiv($j, $width)) . $block[$x + $j % $width];
                    }
                    if (fits($f, $ids, $seats, $class)) {
                        return ['STACK', $seats];
                    }
                }
            }
        }
    }
    return ['SPLIT', []];
}
function removal_targets(object $p): array
{
    return $p->infant === 0 ? [$p->id] : [$p->id, $p->infant];
}
function remove_people(object $f, array $ids): void
{
    global $people;
    foreach ($ids as $id) {
        $p = $people[$id];
        if (!$p->active) {
            continue;
        }
        move_to($f, $p, '');
        $p->active = false;
        $p->volunteer = false;
        if ($p->type === 'INFANT') {
            $people[$p->adult]->infant = 0;
        }
    }
}
function load_text(int $seated, int $seats): string
{
    $q = intdiv($seated * 1000, $seats);
    return intdiv($q, 10) . '.' . $q % 10 . '%';
}
function seat_key(object $f, object $p): array
{
    $s = $f->model->seats[$p->seat];
    return [$s->row, $s->letter];
}
function execute(string $line): array
{
    global $aircraft, $flights, $flightOrder, $bookings, $usedPNR, $people, $statuses, $definition;
    $t = explode(' ', $line);
    $command = $t[0];
    $output = [];
    if ($command === 'AIRCRAFT') {
        $definition = (object) ['id' => $t[1], 'base' => (int) $t[2], 'limit' => (int) $t[3], 'cabins' => [], 'seats' => [], 'exits' => [], 'blocked' => []];
    } elseif ($command === 'CABIN') {
        $class = $t[1];
        $blocks = array_slice($t, 4);
        $c = (object) ['from' => (int) $t[2], 'to' => (int) $t[3], 'blocks' => $blocks, 'seats' => []];
        for ($row = $c->from; $row <= $c->to; ++$row) {
            foreach ($blocks as $blockIndex => $block) {
                for ($position = 0; $position < strlen($block); ++$position) {
                    $letter = $block[$position];
                    if (($blockIndex === 0 && $position === 0) || ($blockIndex === count($blocks) - 1 && $position === strlen($block) - 1)) {
                        $kind = 'W';
                    } elseif ($position === 0 || $position === strlen($block) - 1) {
                        $kind = 'A';
                    } else {
                        $kind = 'M';
                    }
                    $seat = $row . $letter;
                    $definition->seats[$seat] = (object) ['row' => $row, 'letter' => $letter, 'class' => $class, 'block' => $blockIndex, 'kind' => $kind];
                    $c->seats[] = $seat;
                }
            }
        }
        $definition->cabins[$class] = $c;
    } elseif ($command === 'EXIT') {
        foreach (array_slice($t, 1) as $row) {
            $definition->exits[(int) $row] = true;
        }
    } elseif ($command === 'BLOCKED') {
        $definition->blocked = array_fill_keys(array_slice($t, 1), true);
    } elseif ($command === 'END') {
        $parts = ['AIRCRAFT', $definition->id];
        foreach (CLASSES as $class) {
            if (isset($definition->cabins[$class])) {
                $c = $definition->cabins[$class];
                $c->capacity = count(array_filter($c->seats, fn($seat) => !isset($definition->blocked[$seat])));
                $parts = [...$parts, $class, $c->capacity];
            }
        }
        $aircraft[$definition->id] = $definition;
        $output[] = implode(' ', $parts);
        $definition = null;
    } elseif ($command === 'FLIGHT') {
        if (isset($flights[$t[1]])) {
            fail("duplicate flight $t[1]");
        }
        if (!isset($aircraft[$t[2]])) {
            fail("unknown aircraft $t[2]");
        }
        $model = $aircraft[$t[2]];
        $f = (object) ['id' => $t[1], 'model' => $model, 'blocked' => $model->blocked, 'occupied' => [], 'limits' => [], 'closed' => false, 'bookings' => [], 'people' => [], 'volunteers' => []];
        $parts = ['FLIGHT', $f->id, $model->id];
        foreach (CLASSES as $class) {
            if (isset($model->cabins[$class])) {
                $capacity = $model->cabins[$class]->capacity;
                $f->limits[$class] = intdiv($capacity * (100 + (int) $t[3]), 100);
                $parts = [...$parts, $class, "$capacity/" . $f->limits[$class]];
            }
        }
        $flights[$f->id] = $f;
        $flightOrder[] = $f->id;
        $output[] = implode(' ', $parts);
    } elseif ($command === 'STATUS') {
        $statuses[$t[1]] = $t[2];
        $output[] = "STATUS $t[1] $t[2]";
    } elseif ($command === 'BOOK') {
        [$pnr, $flight, $class] = array_slice($t, 1, 3);
        if (isset($usedPNR[$pnr])) {
            fail("duplicate PNR $pnr");
        }
        $f = get_flight($flight, true);
        cabin($f, $class);
        $parsed = array_map(fn($token) => explode(':', $token), array_slice($t, 4));
        $names = [];
        foreach ($parsed as $parts) {
            if (isset($names[$parts[0]])) {
                fail("duplicate name $parts[0] in $pnr");
            }
            $names[$parts[0]] = true;
        }
        $aboard = [];
        foreach (passengers($f) as $id) {
            $aboard[$people[$id]->name] = true;
        }
        foreach ($parsed as $parts) {
            if (isset($aboard[$parts[0]])) {
                fail("$parts[0] already on $flight");
            }
        }
        $types = array_column($parsed, 1);
        $adults = count(array_filter($types, fn($type) => $type === 'ADULT'));
        $infants = count(array_filter($types, fn($type) => $type === 'INFANT'));
        if ($adults === 0) {
            fail("no adult in $pnr");
        }
        if ($infants > $adults) {
            fail("too many infants in $pnr");
        }
        if (booked($f, $class) + count($parsed) - $infants > $f->limits[$class]) {
            fail("limit exceeded for $flight $class");
        }
        $b = (object) ['pnr' => $pnr, 'flight' => $flight, 'people' => [], 'checked' => false];
        $adultIds = [];
        $infantIds = [];
        $seatIds = [];
        foreach ($parsed as $parts) {
            $id = count($people) + 1;
            $p = (object) ['id' => $id, 'pnr' => $pnr, 'name' => $parts[0], 'type' => $parts[1], 'pref' => $parts[2] ?? '', 'class' => $class, 'seat' => '', 'active' => true, 'infant' => 0, 'adult' => 0, 'volunteer' => false];
            $people[$id] = $p;
            $b->people[] = $id;
            $f->people[] = $id;
            if ($p->type === 'ADULT') {
                $adultIds[] = $id;
            }
            if ($p->type === 'INFANT') {
                $infantIds[] = $id;
            } else {
                $seatIds[] = $id;
            }
        }
        foreach ($infantIds as $index => $id) {
            $people[$id]->adult = $adultIds[$index];
            $people[$adultIds[$index]]->infant = $id;
        }
        $bookings[$pnr] = $b;
        $usedPNR[$pnr] = true;
        $f->bookings[] = $pnr;
        if (count($seatIds) === 1) {
            $method = 'SINGLE';
            move_to($f, $people[$seatIds[0]], select_seat($f, $people[$seatIds[0]]));
        } else {
            [$method, $seats] = group_seats($f, $seatIds, $class);
            foreach ($seatIds as $index => $id) {
                $seat = $method === 'SPLIT' ? select_seat($f, $people[$id]) : $seats[$index];
                move_to($f, $people[$id], $seat);
            }
        }
        $parts = ['BOOKED', $pnr, $flight, $class, $method];
        foreach ($b->people as $id) {
            $parts[] = $people[$id]->name . ':' . result($people[$id]);
        }
        $output[] = implode(' ', $parts);
    } elseif ($command === 'FIND') {
        $lines = [];
        foreach ($flightOrder as $flight) {
            $f = $flights[$flight];
            foreach (passengers($f) as $id) {
                $p = $people[$id];
                if ($p->name === $t[1]) {
                    $lines[] = "$flight $p->pnr $p->class " . result($p) . ' ' . ($f->closed ? 'CLOSED' : 'OPEN');
                }
            }
        }
        $output[] = "FIND $t[1] " . ($statuses[$t[1]] ?? 'NONE') . ' ' . count($lines);
        $output = [...$output, ...$lines];
    } elseif (in_array($command, ['SEAT', 'SWAP', 'CANCEL', 'CHECKIN', 'VOLUNTEER', 'INFO'], true)) {
        $b = get_booking($t[1], $command !== 'INFO');
        $f = $flights[$b->flight];
        if ($command === 'INFO') {
            $output[] = "INFO $b->pnr $b->flight " . count(members($b)) . ' ' . ($b->checked ? 'CHECKED' : 'NOT-CHECKED');
            foreach (members($b) as $id) {
                $p = $people[$id];
                $output[] = "$p->name $p->type $p->class " . result($p);
            }
        } elseif ($command === 'CHECKIN') {
            if ($b->checked) {
                fail("$b->pnr already checked in");
            }
            $b->checked = true;
            $output[] = "CHECKIN $b->pnr " . count(members($b));
        } elseif ($command === 'CANCEL') {
            $targets = members($b);
            if (isset($t[2])) {
                $p = get_person($b, $t[2]);
                $targets = removal_targets($p);
                $remaining = array_values(array_diff(members($b), $targets));
                if ($remaining !== [] && !array_filter($remaining, fn($id) => $people[$id]->type === 'ADULT')) {
                    fail("$b->pnr would have no adult");
                }
                $targets = array_values(array_intersect(members($b), $targets));
            }
            $names = array_map(fn($id) => $people[$id]->name, $targets);
            remove_people($f, $targets);
            $output[] = "CANCELLED $b->pnr " . implode(' ', $names);
            reassign($f, $output);
        } else {
            $p = get_person($b, $t[2]);
            if ($command === 'SWAP') {
                $b2 = get_booking($t[3], true);
                $q = get_person($b2, $t[4]);
                if ($p->id === $q->id) {
                    fail("cannot swap $p->name with itself");
                }
                foreach ([$p, $q] as $person) {
                    if ($person->type === 'INFANT') {
                        fail("infant $person->name has no seat");
                    }
                }
                if ($b->flight !== $b2->flight) {
                    fail("$b->pnr and $b2->pnr are on different flights");
                }
                if ($p->class !== $q->class) {
                    fail("$p->name and $q->name are in different cabins");
                }
                foreach ([$p, $q] as $person) {
                    if ($person->seat === '') {
                        fail("$person->name has no seat");
                    }
                }
                $vacated = [$p->id => true, $q->id => true];
                $assignments = [$p->id => $q->seat, $q->id => $p->seat];
                if (!allowed($f, $p, $q->seat, $p->class, $vacated, $assignments) || !allowed($f, $q, $p->seat, $q->class, $vacated, $assignments)) {
                    fail("swap of $p->name and $q->name breaks seating rules");
                }
                [$oldP, $oldQ] = [$p->seat, $q->seat];
                move_to($f, $p, '');
                move_to($f, $q, '');
                move_to($f, $p, $oldQ);
                move_to($f, $q, $oldP);
                $output[] = "SWAPPED $b->pnr $p->name $p->seat $b2->pnr $q->name $q->seat";
                reassign($f, $output);
            } elseif ($command === 'VOLUNTEER') {
                if ($p->type !== 'ADULT' || $p->infant !== 0) {
                    fail("$p->name cannot volunteer");
                }
                if ($p->seat === '') {
                    fail("$p->name has no seat");
                }
                if ($p->volunteer) {
                    fail("$p->name already volunteered");
                }
                $p->volunteer = true;
                $f->volunteers[] = $p->id;
                $output[] = "VOLUNTEER $p->pnr $p->name $p->seat";
            } else {
                $seat = $t[3];
                if ($p->type === 'INFANT') {
                    fail("infant $p->name has no seat");
                }
                $s = $f->model->seats[$seat] ?? null;
                if ($s === null || $s->class !== $p->class) {
                    fail("no seat $seat in cabin $p->class");
                }
                if (isset($f->blocked[$seat])) {
                    fail("seat $seat is blocked");
                }
                if (isset($f->occupied[$seat])) {
                    fail("seat $seat is occupied");
                }
                if (($p->type === 'CHILD' || $p->infant !== 0) && isset($f->model->exits[$s->row])) {
                    fail("exit row $s->row not allowed for $p->name");
                }
                if (!allowed($f, $p, $seat, $p->class)) {
                    fail("infant limit reached at $seat");
                }
                $old = $p->seat;
                move_to($f, $p, $seat);
                $output[] = "MOVED $p->pnr $p->name $old -> $seat";
                reassign($f, $output);
            }
        }
    } else {
        $mutating = in_array($command, ['UPGRADE', 'CLOSE', 'BLOCK', 'UNBLOCK'], true);
        $f = get_flight($t[1], $mutating);
        $classes = array_values(array_filter(CLASSES, fn($class) => isset($f->model->cabins[$class])));
        if ($command === 'UPGRADE') {
            $count = 0;
            for ($index = 0; $index + 1 < count($classes); ++$index) {
                [$higher, $lower] = [$classes[$index], $classes[$index + 1]];
                $targets = array_values(array_filter(passengers($f), fn($id) => $people[$id]->class === $lower && $people[$id]->type === 'ADULT' && $people[$id]->infant === 0 && tier($people[$id]) !== 'NONE'));
                usort($targets, fn($a, $b) => [TIERS[tier($people[$a])], $a] <=> [TIERS[tier($people[$b])], $b]);
                foreach ($targets as $id) {
                    if (booked($f, $higher) >= $f->limits[$higher]) {
                        break;
                    }
                    $p = $people[$id];
                    $seat = select_seat($f, $p, $higher);
                    if ($seat === '') {
                        break;
                    }
                    $old = result($p);
                    move_to($f, $p, $seat);
                    $p->class = $higher;
                    ++$count;
                    $output[] = "UPGRADED $p->pnr $p->name $lower $old -> $higher $seat";
                }
            }
            reassign($f, $output);
            $output[] = "UPGRADE $f->id $count";
        } elseif ($command === 'CLOSE') {
            foreach ($f->bookings as $pnr) {
                $b = $bookings[$pnr];
                $ids = members($b);
                if ($ids !== [] && !$b->checked) {
                    $output[] = "NOSHOW $pnr " . count($ids);
                    remove_people($f, $ids);
                }
            }
            reassign($f, $output);
            $denied = 0;
            $total = 0;
            $rates = ['F' => 500, 'J' => 300, 'Y' => 150];
            foreach ($classes as $class) {
                $targets = array_values(array_filter($f->volunteers, fn($id) => $people[$id]->active && $people[$id]->volunteer && $people[$id]->seat !== '' && $people[$id]->class === $class));
                foreach ($targets as $id) {
                    $p = $people[$id];
                    $useful = false;
                    foreach (passengers($f) as $waitingId) {
                        $waiting = $people[$waitingId];
                        if ($waiting->type !== 'INFANT' && $waiting->class === $class && $waiting->seat === '' && allowed($f, $waiting, $p->seat, $class, [$id => true])) {
                            $useful = true;
                            break;
                        }
                    }
                    if ($useful) {
                        $amount = $rates[$class];
                        $output[] = "DENIED VOLUNTARY $p->pnr $p->name $class $amount";
                        remove_people($f, [$id]);
                        ++$denied;
                        $total += $amount;
                        reassign($f, $output);
                    }
                }
            }
            foreach (passengers($f) as $id) {
                $p = $people[$id];
                if ($p->active && $p->type !== 'INFANT' && $p->seat === '') {
                    $amount = $rates[$p->class] * 2;
                    if ($p->type === 'CHILD') {
                        $amount = intdiv($amount, 2);
                    }
                    $output[] = "DENIED INVOLUNTARY $p->pnr $p->name $p->class $amount";
                    remove_people($f, removal_targets($p));
                    ++$denied;
                    $total += $amount;
                }
            }
            $f->closed = true;
            $output[] = "CLOSED $f->id denied $denied compensation $total";
        } elseif ($command === 'BLOCK' || $command === 'UNBLOCK') {
            $seat = $t[2];
            if (!isset($f->model->seats[$seat])) {
                fail("no seat $seat on $f->id");
            }
            $blocked = isset($f->blocked[$seat]);
            if ($command === 'BLOCK' && $blocked) {
                fail("seat $seat is blocked");
            }
            if ($command === 'UNBLOCK' && !$blocked) {
                fail("seat $seat is not blocked");
            }
            $output[] = "$command $f->id $seat";
            if ($command === 'BLOCK') {
                $f->blocked[$seat] = true;
                if (isset($f->occupied[$seat])) {
                    $p = $people[$f->occupied[$seat]];
                    move_to($f, $p, '');
                    move_to($f, $p, select_seat($f, $p));
                    $output[] = "DISPLACED $p->pnr $p->name $seat -> " . result($p);
                }
            } else {
                unset($f->blocked[$seat]);
            }
            reassign($f, $output);
        } elseif ($command === 'MAP') {
            $output[] = "MAP $f->id";
            foreach ($classes as $class) {
                $c = $f->model->cabins[$class];
                $output[] = "CABIN $class";
                $output[] = '   ' . implode(' ', $c->blocks);
                for ($row = $c->from; $row <= $c->to; ++$row) {
                    $blocks = [];
                    foreach ($c->blocks as $block) {
                        $text = '';
                        foreach (str_split($block) as $letter) {
                            $seat = $row . $letter;
                            if (isset($f->blocked[$seat])) {
                                $text .= '#';
                            } elseif (isset($f->occupied[$seat])) {
                                $text .= 'X';
                            } else {
                                $text .= isset($f->model->exits[$row]) ? 'E' : '.';
                            }
                        }
                        $blocks[] = $text;
                    }
                    $output[] = sprintf('%2d ', $row) . implode(' ', $blocks);
                }
            }
        } elseif ($command === 'MANIFEST' || $command === 'BOARDING') {
            $seated = [];
            $unassigned = [];
            $infants = 0;
            foreach (passengers($f) as $id) {
                $p = $people[$id];
                if ($p->type === 'INFANT') {
                    ++$infants;
                } elseif ($p->seat === '') {
                    $unassigned[] = $id;
                } else {
                    $seated[] = $id;
                }
            }
            if ($command === 'MANIFEST') {
                usort($seated, fn($a, $b) => seat_key($f, $people[$a]) <=> seat_key($f, $people[$b]));
                $output[] = "MANIFEST $f->id seated " . count($seated) . ' unassigned ' . count($unassigned) . " infants $infants";
                foreach ([...$seated, ...$unassigned] as $id) {
                    $p = $people[$id];
                    $parts = [$p->seat === '' ? '---' : $p->seat, $p->class, $p->pnr, $p->name, $p->type];
                    if ($p->infant !== 0) {
                        $parts[] = '+' . $people[$p->infant]->name;
                    }
                    if (tier($p) !== 'NONE') {
                        $parts[] = tier($p);
                    }
                    if ($bookings[$p->pnr]->checked) {
                        $parts[] = 'CHECKED';
                    }
                    if ($p->volunteer) {
                        $parts[] = 'VOL';
                    }
                    $output[] = implode(' ', $parts);
                }
            } else {
                $groups = [];
                $keys = [];
                foreach ($seated as $id) {
                    $p = $people[$id];
                    $s = $f->model->seats[$p->seat];
                    $hasInfant = count(array_filter(members($bookings[$p->pnr]), fn($member) => $people[$member]->type === 'INFANT')) > 0;
                    if ($hasInfant) {
                        $group = 'PRE';
                        $key = [0, $s->row, $s->letter];
                    } elseif ($p->class !== 'Y') {
                        $group = 'CABIN';
                        $key = [1, $s->row, $s->letter];
                    } elseif (TIERS[tier($p)] <= 1) {
                        $group = 'TIER';
                        $key = [2, $s->row, $s->letter];
                    } else {
                        $zone = intdiv($s->row - $f->model->cabins['Y']->from, 5) + 1;
                        $group = "ZONE$zone";
                        $key = [3, -$zone, array_search($s->kind, ['W', 'M', 'A'], true), -$s->row, $s->letter];
                    }
                    $groups[$id] = $group;
                    $keys[$id] = $key;
                }
                usort($seated, fn($a, $b) => $keys[$a] <=> $keys[$b]);
                $output[] = "BOARDING $f->id " . count($seated);
                foreach ($seated as $index => $id) {
                    $p = $people[$id];
                    $output[] = ($index + 1) . " $groups[$id] $p->seat $p->pnr $p->name";
                }
            }
        } elseif ($command === 'LOADFACTOR') {
            $output[] = "LOADFACTOR $f->id";
            $totalSeated = 0;
            $totalSeats = 0;
            foreach ($classes as $class) {
                $seats = count(array_filter($f->model->cabins[$class]->seats, fn($seat) => !isset($f->blocked[$seat])));
                $seated = count(array_filter(passengers($f), fn($id) => $people[$id]->class === $class && $people[$id]->seat !== ''));
                $output[] = "$class $seated/$seats " . load_text($seated, $seats) . ' booked ' . booked($f, $class) . '/' . $f->limits[$class];
                $totalSeated += $seated;
                $totalSeats += $seats;
            }
            $output[] = "ALL $totalSeated/$totalSeats " . load_text($totalSeated, $totalSeats);
        } elseif ($command === 'BALANCE') {
            $weight = 0;
            $moment = 0;
            foreach (passengers($f) as $id) {
                $p = $people[$id];
                if ($p->seat !== '') {
                    $w = $p->type === 'ADULT' ? 80 : 40;
                    if ($p->infant !== 0) {
                        $w += 10;
                    }
                    $weight += $w;
                    $moment += $w * ($f->model->seats[$p->seat]->row - $f->model->base);
                }
            }
            $limit = $f->model->limit;
            if ($moment < -$limit) {
                $verdict = 'NOSE-HEAVY';
            } elseif ($moment > $limit) {
                $verdict = 'TAIL-HEAVY';
            } else {
                $verdict = 'OK';
            }
            $output[] = "BALANCE $f->id weight $weight moment $moment limit $limit $verdict";
        } elseif ($command === 'AVAIL') {
            $class = $t[2];
            $c = cabin($f, $class);
            $counts = ['W' => 0, 'M' => 0, 'A' => 0, 'EXIT' => 0];
            $free = 0;
            foreach ($c->seats as $seat) {
                if (!isset($f->blocked[$seat]) && !isset($f->occupied[$seat])) {
                    $s = $f->model->seats[$seat];
                    ++$free;
                    ++$counts[$s->kind];
                    if (isset($f->model->exits[$s->row])) {
                        ++$counts['EXIT'];
                    }
                }
            }
            $output[] = "AVAIL $f->id $class free $free W $counts[W] M $counts[M] A $counts[A] EXIT $counts[EXIT]";
        }
    }
    return $output;
}
$count = (int) fgets(STDIN);
for ($index = 0; $index < $count; ++$index) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        foreach (execute($line) as $output) {
            echo $output, "\n";
        }
    } catch (InvalidArgumentException $error) {
        echo 'ERROR ', $error->getMessage(), "\n";
    }
}
