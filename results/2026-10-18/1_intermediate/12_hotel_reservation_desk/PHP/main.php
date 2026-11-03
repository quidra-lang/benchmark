<?php

declare(strict_types=1);

const ROOM_TYPES = ['SINGLE', 'DOUBLE', 'SUITE'];
const WEEKDAYS = ['SAT', 'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI'];

final class CommandError extends RuntimeException {}

function leap(int $year): bool
{
    return $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
}

function month_lengths(int $year): array
{
    return [31, leap($year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
}

function day_number(string $text): int
{
    [$year, $month, $day] = array_map('intval', explode('-', $text));
    if ($year < 2000 || $year > 2099 || $month < 1 || $month > 12) {
        throw new CommandError("invalid date $text");
    }
    $lengths = month_lengths($year);
    if ($day < 1 || $day > $lengths[$month - 1]) {
        throw new CommandError("invalid date $text");
    }
    $number = 0;
    for ($previous = 2000; $previous < $year; ++$previous) {
        $number += leap($previous) ? 366 : 365;
    }
    for ($previous = 1; $previous < $month; ++$previous) {
        $number += $lengths[$previous - 1];
    }
    return $number + $day - 1;
}

function date_text(int $number): string
{
    $year = 2000;
    while ($number >= ($days = leap($year) ? 366 : 365)) {
        $number -= $days;
        ++$year;
    }
    $month = 1;
    foreach (month_lengths($year) as $days) {
        if ($number < $days) {
            break;
        }
        $number -= $days;
        ++$month;
    }
    return sprintf('%04d-%02d-%02d', $year, $month, $number + 1);
}

function date_weekday(int $number): string
{
    return date_text($number) . ' ' . WEEKDAYS[$number % 7];
}

function cents(string $text): int
{
    [$whole, $fraction] = explode('.', $text);
    return (int) $whole * 100 + (int) $fraction;
}

function money(int $cents): string
{
    return intdiv($cents, 100) . '.' . sprintf('%02d', $cents % 100);
}

final class Room
{
    public bool $clean = true;

    public function __construct(
        public int $number,
        public string $kind,
        public int $rate,
    ) {}
}

final class Reservation
{
    public string $status = 'booked';
    public array $extras = [];
    public int $deposit = 0;
    public int $paid = 0;
    public ?int $posting = null;
    public int $fee = 0;
    public ?array $penalty = null;
    public ?array $bill = null;

    public function __construct(
        public string $identifier,
        public string $guest,
        public Room $room,
        public int $arrival,
        public int $departure,
        public array $nights,
    ) {}

    public function lodging(): int
    {
        return array_sum(array_column($this->nights, 2));
    }

    public function first_rate(): int
    {
        return $this->nights[0][2];
    }
}

final class WaitingEntry
{
    public function __construct(
        public string $identifier,
        public string $guest,
        public string $kind,
        public int $arrival,
        public int $departure,
    ) {}
}

final class HotelDesk
{
    private int $today;
    private array $rooms = [];
    private array $seasons = [];
    private array $blocks = [];
    private array $reservations = [];
    private array $waitlist = [];
    private array $used_ids = [];
    private array $occupied = [];
    private array $output = [];

    public function __construct()
    {
        $this->today = day_number('2026-01-01');
    }

    private function emit(array $parts, int $indent = 0): void
    {
        $this->output[] = str_repeat(' ', $indent) . implode(' ', $parts);
    }

    private function require_room(string $text): Room
    {
        $number = (int) $text;
        if (!isset($this->rooms[$number])) {
            throw new CommandError("unknown room $text");
        }
        return $this->rooms[$number];
    }

    private function require_type(string $kind): void
    {
        if (!in_array($kind, ROOM_TYPES, true)) {
            throw new CommandError("invalid type $kind");
        }
    }

    private function require_unused(string $identifier): void
    {
        if (isset($this->used_ids[$identifier])) {
            throw new CommandError("duplicate reservation $identifier");
        }
    }

    private function reservation(string $identifier, ?string $status = null): Reservation
    {
        $r = $this->reservations[$identifier] ?? null;
        if ($r === null) {
            throw new CommandError("unknown reservation $identifier");
        }
        if ($status !== null && $r->status !== $status) {
            throw new CommandError("invalid status $identifier $r->status");
        }
        return $r;
    }

    private function stay(string $first, string $last): array
    {
        $arrival = day_number($first);
        $departure = day_number($last);
        if ($arrival < $this->today) {
            throw new CommandError("past date $first");
        }
        if ($departure <= $arrival) {
            throw new CommandError("invalid range $first $last");
        }
        if ($departure - $arrival > 30) {
            throw new CommandError('too long ' . ($departure - $arrival));
        }
        return [$arrival, $departure];
    }

    private function period(
        string $first, string $last, bool $past_restricted = false, bool $limited = true,
    ): array {
        $start = day_number($first);
        $end = day_number($last);
        if ($past_restricted && $start < $this->today) {
            throw new CommandError("past date $first");
        }
        if ($end < $start) {
            throw new CommandError("invalid range $first $last");
        }
        if ($limited && $end - $start + 1 > 31) {
            throw new CommandError('too long ' . ($end - $start + 1));
        }
        return [$start, $end];
    }

    private function night_rate(Room $room, int $day): int
    {
        $percentage = 100;
        for ($i = count($this->seasons) - 1; $i >= 0; --$i) {
            [$start, $end, $value] = $this->seasons[$i];
            if ($start <= $day && $day <= $end) {
                $percentage = $value;
                break;
            }
        }
        return intdiv($room->rate * $percentage, 100);
    }

    private function price(Room $room, int $arrival, int $departure): array
    {
        $nights = [];
        for ($day = $arrival; $day < $departure; ++$day) {
            $nights[] = [$day, $room->number, $this->night_rate($room, $day)];
        }
        return $nights;
    }

    private static function night_key(int $day, int $number): string
    {
        return "$day:$number";
    }

    private function first_unavailable(
        Room $room, int $arrival, int $departure, ?Reservation $except_for = null,
    ): ?int {
        for ($day = $arrival; $day < $departure; ++$day) {
            $key = self::night_key($day, $room->number);
            if (isset($this->blocks[$key])) {
                return $day;
            }
            $occupied = $this->occupied[$key] ?? null;
            if ($occupied !== null && $occupied[0] !== $except_for) {
                return $day;
            }
        }
        return null;
    }

    private function free_room(
        string $kind, int $arrival, int $departure, ?Reservation $except_for = null,
    ): ?Room {
        $rooms = $this->rooms;
        ksort($rooms, SORT_NUMERIC);
        foreach ($rooms as $room) {
            if ($room->kind === $kind &&
                $this->first_unavailable($room, $arrival, $departure, $except_for) === null) {
                return $room;
            }
        }
        return null;
    }

    private function inhouse(Room $room): ?Reservation
    {
        foreach ($this->reservations as $reservation) {
            if ($reservation->status === 'inhouse' && $reservation->room === $room) {
                return $reservation;
            }
        }
        return null;
    }

    private function occupy(Reservation $reservation, array $nights): void
    {
        foreach ($nights as [$day, $number, $rate]) {
            $this->occupied[self::night_key($day, $number)] = [$reservation, $rate];
        }
    }

    private function release(Reservation $reservation, ?int $first = null): void
    {
        foreach ($reservation->nights as [$day, $number, $rate]) {
            if ($first === null || $day >= $first) {
                unset($this->occupied[self::night_key($day, $number)]);
            }
        }
    }

    private function create_reservation(
        string $identifier, string $guest, Room $room,
        int $arrival, int $departure, int $indent = 0,
    ): void {
        $nights = $this->price($room, $arrival, $departure);
        $reservation = new Reservation($identifier, $guest, $room, $arrival, $departure, $nights);
        $this->reservations[$identifier] = $reservation;
        $this->used_ids[$identifier] = true;
        $this->occupy($reservation, $nights);
        $this->emit([
            'BOOK', $identifier, $guest, 'room', $room->number, $room->kind,
            date_text($arrival), '->', date_text($departure), 'nights',
            $departure - $arrival, 'total', money($reservation->lodging()),
        ], $indent);
    }

    private function guest_total(string $guest): int
    {
        $total = 0;
        foreach ($this->reservations as $reservation) {
            if ($reservation->guest === $guest) {
                $total += $reservation->paid;
            }
        }
        return $total;
    }

    private function tier(string $guest): string
    {
        $points = intdiv($this->guest_total($guest), 100);
        return $points >= 2000 ? 'GOLD' : ($points >= 500 ? 'SILVER' : 'BRONZE');
    }

    private function calculate_bill(Reservation $reservation): array
    {
        $lodging = $reservation->lodging();
        $percentage = match ($this->tier($reservation->guest)) {
            'GOLD' => 10,
            'SILVER' => 5,
            default => 0,
        };
        $discount = intdiv($lodging * $percentage, 100);
        $penalty = $reservation->penalty === null ? 0 : $reservation->penalty[1];
        $extras = array_sum(array_column($reservation->extras, 1));
        $subtotal = $lodging - $discount + $penalty + $extras;
        $tax = intdiv($subtotal, 10);
        return [$lodging, $discount, $penalty, $extras, $tax, $subtotal + $tax];
    }

    private function deposit_parts(Reservation $reservation, int $total): array
    {
        if ($total >= $reservation->deposit) {
            return ['deposit', money($reservation->deposit), 'due', money($total - $reservation->deposit)];
        }
        return ['deposit', money($reservation->deposit), 'refund', money($reservation->deposit - $total)];
    }

    private function check_out(Reservation $reservation, int $day, int $indent = 0): void
    {
        if ($day < $reservation->departure) {
            foreach ($reservation->nights as [$night, $number, $rate]) {
                if ($night === $day) {
                    $reservation->penalty = [$day, $rate];
                    break;
                }
            }
            $this->release($reservation, $day);
            $reservation->nights = array_values(array_filter(
                $reservation->nights,
                static fn (array $night): bool => $night[0] < $day,
            ));
            $reservation->departure = $day;
        }
        [$lodging, $discount, $penalty, $extras, $tax, $total] =
            $this->calculate_bill($reservation);
        $reservation->bill = [$lodging, $discount, $penalty, $extras, $tax, $total];
        $reservation->paid = $total;
        $reservation->status = 'checkedout';
        $reservation->posting = $day;
        $reservation->room->clean = false;
        $this->emit([
            'CHECKOUT', $reservation->identifier, 'nights', count($reservation->nights),
            'lodging', money($lodging), 'discount', money($discount), 'penalty', money($penalty),
            'extras', money($extras), 'tax', money($tax), 'total', money($total),
            ...$this->deposit_parts($reservation, $total),
        ], $indent);
    }

    private function process_waitlist(): void
    {
        $remaining = [];
        foreach ($this->waitlist as $entry) {
            if ($entry->arrival < $this->today) {
                $this->emit(['WAITLIST', $entry->identifier, 'expired'], 2);
                continue;
            }
            $room = $this->free_room($entry->kind, $entry->arrival, $entry->departure);
            if ($room === null) {
                $remaining[] = $entry;
            } else {
                $this->create_reservation(
                    $entry->identifier, $entry->guest, $room, $entry->arrival, $entry->departure, 2,
                );
            }
        }
        $this->waitlist = $remaining;
    }

    private function cmd_room(string $number, string $kind, string $amount): void
    {
        if (isset($this->rooms[(int) $number])) {
            throw new CommandError("duplicate room $number");
        }
        $this->require_type($kind);
        $room = new Room((int) $number, $kind, cents($amount));
        $this->rooms[$room->number] = $room;
        $this->emit(['ROOM', $number, $kind, $amount]);
    }

    private function cmd_rate(string $number, string $amount): void
    {
        $room = $this->require_room($number);
        $previous = $room->rate;
        $room->rate = cents($amount);
        $this->emit(['RATE', $number, money($previous), '->', $amount]);
    }

    private function cmd_season(string $first, string $last, string $percentage): void
    {
        [$start, $end] = $this->period($first, $last, limited: false);
        $this->seasons[] = [$start, $end, (int) $percentage];
        $this->emit(['SEASON', count($this->seasons), $first, '->', $last, $percentage . '%']);
    }

    private function cmd_block(string $number, string $first, string $last): void
    {
        $room = $this->require_room($number);
        [$start, $end] = $this->period($first, $last, past_restricted: true);
        for ($day = $start; $day <= $end; ++$day) {
            if (isset($this->occupied[self::night_key($day, $room->number)])) {
                throw new CommandError("room unavailable $number " . date_text($day));
            }
        }
        $added = 0;
        for ($day = $start; $day <= $end; ++$day) {
            $key = self::night_key($day, $room->number);
            if (!isset($this->blocks[$key])) {
                $this->blocks[$key] = true;
                ++$added;
            }
        }
        $this->emit(['BLOCK', $number, $first, '->', $last, 'added', $added]);
    }

    private function cmd_unblock(string $number, string $first, string $last): void
    {
        $room = $this->require_room($number);
        [$start, $end] = $this->period($first, $last, past_restricted: true);
        $removed = 0;
        for ($day = $start; $day <= $end; ++$day) {
            $key = self::night_key($day, $room->number);
            if (isset($this->blocks[$key])) {
                unset($this->blocks[$key]);
                ++$removed;
            }
        }
        $this->emit(['UNBLOCK', $number, $first, '->', $last, 'removed', $removed]);
    }

    private function cmd_clean(string $number): void
    {
        $room = $this->require_room($number);
        if ($room->clean) {
            throw new CommandError("already clean $number");
        }
        $room->clean = true;
        $this->emit(['CLEAN', $number]);
    }

    private function cmd_today(string $text): void
    {
        $day = day_number($text);
        if ($day < $this->today) {
            throw new CommandError("past date $text");
        }
        $this->emit(['TODAY', date_weekday($day)]);
        $departing = array_values(array_filter(
            $this->reservations,
            static fn (Reservation $r): bool => $r->status === 'inhouse' && $r->departure < $day,
        ));
        usort($departing, static fn (Reservation $a, Reservation $b): int =>
            ($a->departure <=> $b->departure) ?: strcmp($a->identifier, $b->identifier));
        foreach ($departing as $reservation) {
            $this->check_out($reservation, $reservation->departure, 2);
        }
        $absent = array_values(array_filter(
            $this->reservations,
            static fn (Reservation $r): bool => $r->status === 'booked' && $r->arrival < $day,
        ));
        usort($absent, static fn (Reservation $a, Reservation $b): int =>
            ($a->arrival <=> $b->arrival) ?: strcmp($a->identifier, $b->identifier));
        foreach ($absent as $reservation) {
            $this->release($reservation);
            $reservation->fee = $reservation->first_rate();
            $reservation->paid = $reservation->fee;
            $reservation->status = 'noshow';
            $reservation->posting = $reservation->arrival;
            $this->emit([
                'NOSHOW', $reservation->identifier, $reservation->guest, 'fee',
                money($reservation->fee),
                ...$this->deposit_parts($reservation, $reservation->fee),
            ], 2);
        }
        $this->today = $day;
    }

    private function cmd_book(
        string $identifier, string $guest, string $kind, string $first, string $last,
    ): void {
        $this->require_unused($identifier);
        $this->require_type($kind);
        [$arrival, $departure] = $this->stay($first, $last);
        $room = $this->free_room($kind, $arrival, $departure);
        if ($room === null) {
            throw new CommandError("no availability $kind $first $last");
        }
        $this->create_reservation($identifier, $guest, $room, $arrival, $departure);
    }

    private function cmd_bookroom(
        string $identifier, string $guest, string $number, string $first, string $last,
    ): void {
        $this->require_unused($identifier);
        $room = $this->require_room($number);
        [$arrival, $departure] = $this->stay($first, $last);
        $unavailable = $this->first_unavailable($room, $arrival, $departure);
        if ($unavailable !== null) {
            throw new CommandError("room unavailable $number " . date_text($unavailable));
        }
        $this->create_reservation($identifier, $guest, $room, $arrival, $departure);
    }

    private function cmd_waitlist(
        string $identifier, string $guest, string $kind, string $first, string $last,
    ): void {
        $this->require_unused($identifier);
        $this->require_type($kind);
        [$arrival, $departure] = $this->stay($first, $last);
        $room = $this->free_room($kind, $arrival, $departure);
        if ($room !== null) {
            $this->create_reservation($identifier, $guest, $room, $arrival, $departure);
        } else {
            $this->waitlist[] = new WaitingEntry($identifier, $guest, $kind, $arrival, $departure);
            $this->used_ids[$identifier] = true;
            $this->emit(['WAITLIST', $identifier, 'queued position', count($this->waitlist)]);
        }
    }

    private function cmd_modify(string $identifier, string $first, string $last): void
    {
        $reservation = $this->reservation($identifier, 'booked');
        [$arrival, $departure] = $this->stay($first, $last);
        $room = $reservation->room;
        $choice = 'kept';
        if ($this->first_unavailable($room, $arrival, $departure, $reservation) !== null) {
            $room = $this->free_room($room->kind, $arrival, $departure, $reservation);
            if ($room === null) {
                throw new CommandError(
                    "no availability {$reservation->room->kind} $first $last",
                );
            }
            $choice = 'reassigned';
        }
        $nights = $this->price($room, $arrival, $departure);
        $this->release($reservation);
        $reservation->room = $room;
        $reservation->arrival = $arrival;
        $reservation->departure = $departure;
        $reservation->nights = $nights;
        $this->occupy($reservation, $nights);
        $this->emit([
            'MODIFY', $identifier, 'room', $room->number, $choice, $first, '->',
            $last, 'nights', $departure - $arrival, 'total', money($reservation->lodging()),
        ]);
    }

    private function cmd_cancel(string $identifier): void
    {
        foreach ($this->waitlist as $index => $entry) {
            if ($entry->identifier === $identifier) {
                array_splice($this->waitlist, $index, 1);
                $this->emit(['CANCEL', $identifier, 'waitlist removed']);
                return;
            }
        }
        $reservation = $this->reservation($identifier, 'booked');
        $days = $reservation->arrival - $this->today;
        $first_rate = $reservation->first_rate();
        $fee = $days >= 7 ? 0 : ($days >= 1 ? intdiv($first_rate, 2) : $first_rate);
        $this->release($reservation);
        $reservation->fee = $fee;
        $reservation->paid = $fee;
        $reservation->status = 'cancelled';
        $reservation->posting = $this->today;
        $this->emit([
            'CANCEL', $identifier, 'days', $days, 'fee', money($fee),
            ...$this->deposit_parts($reservation, $fee),
        ]);
    }

    private function cmd_checkin(string $identifier): void
    {
        $reservation = $this->reservation($identifier, 'booked');
        if ($reservation->arrival !== $this->today) {
            throw new CommandError(
                "not arrival date $identifier " . date_text($reservation->arrival),
            );
        }
        $occupant = $this->inhouse($reservation->room);
        if ($occupant !== null) {
            throw new CommandError(
                "room occupied {$reservation->room->number} $occupant->identifier",
            );
        }
        if (!$reservation->room->clean) {
            throw new CommandError("room dirty {$reservation->room->number}");
        }
        $reservation->status = 'inhouse';
        $this->emit([
            'CHECKIN', $identifier, $reservation->guest, 'room', $reservation->room->number,
            'until', date_text($reservation->departure),
        ]);
    }

    private function cmd_move(string $identifier, string $number): void
    {
        $reservation = $this->reservation($identifier, 'inhouse');
        $room = $this->require_room($number);
        $previous = $reservation->room;
        if ($room === $previous) {
            throw new CommandError("same room $number");
        }
        $remaining = array_values(array_filter(
            $reservation->nights,
            fn (array $night): bool => $night[0] >= $this->today,
        ));
        if (!$remaining) {
            throw new CommandError("no remaining nights $identifier");
        }
        $unavailable = $this->first_unavailable(
            $room, $remaining[0][0], $reservation->departure, $reservation,
        );
        if ($unavailable !== null) {
            throw new CommandError("room unavailable $number " . date_text($unavailable));
        }
        $occupant = $this->inhouse($room);
        if ($occupant !== null) {
            throw new CommandError("room occupied $number $occupant->identifier");
        }
        if (!$room->clean) {
            throw new CommandError("room dirty $number");
        }
        $this->release($reservation, $this->today);
        foreach ($reservation->nights as &$night) {
            if ($night[0] >= $this->today) {
                $night[1] = $room->number;
            }
        }
        unset($night);
        $future_nights = array_values(array_filter(
            $reservation->nights,
            fn (array $night): bool => $night[0] >= $this->today,
        ));
        $this->occupy($reservation, $future_nights);
        $previous->clean = false;
        $reservation->room = $room;
        $this->emit([
            'MOVE', $identifier, $previous->number, '->', $number,
            'nights', count($remaining),
        ]);
    }

    private function cmd_extend(string $identifier, string $text): void
    {
        $reservation = $this->reservation($identifier, 'inhouse');
        $departure = day_number($text);
        if ($departure <= $reservation->departure) {
            throw new CommandError(
                "invalid range " . date_text($reservation->departure) . " $text",
            );
        }
        if ($departure - $reservation->arrival > 30) {
            throw new CommandError('too long ' . ($departure - $reservation->arrival));
        }
        $unavailable = $this->first_unavailable(
            $reservation->room, $reservation->departure, $departure, $reservation,
        );
        if ($unavailable !== null) {
            throw new CommandError(
                'room unavailable ' . $reservation->room->number . ' ' . date_text($unavailable),
            );
        }
        $nights = $this->price($reservation->room, $reservation->departure, $departure);
        array_push($reservation->nights, ...$nights);
        $this->occupy($reservation, $nights);
        $reservation->departure = $departure;
        $this->emit([
            'EXTEND', $identifier, 'until', $text, 'nights', count($reservation->nights),
            'total', money($reservation->lodging()),
        ]);
    }

    private function cmd_charge(string $identifier, string $amount, string $item): void
    {
        $reservation = $this->reservation($identifier, 'inhouse');
        $value = cents($amount);
        if ($value === 0) {
            throw new CommandError('invalid amount');
        }
        $reservation->extras[] = [$item, $value];
        $extras = array_sum(array_column($reservation->extras, 1));
        $this->emit(['CHARGE', $identifier, $item, $amount, 'extras', money($extras)]);
    }

    private function cmd_pay(string $identifier, string $amount): void
    {
        $reservation = $this->reservation($identifier);
        if (!in_array($reservation->status, ['booked', 'inhouse'], true)) {
            throw new CommandError("invalid status $identifier $reservation->status");
        }
        $value = cents($amount);
        if ($value === 0) {
            throw new CommandError('invalid amount');
        }
        $reservation->deposit += $value;
        $this->emit(['PAY', $identifier, $amount, 'deposit', money($reservation->deposit)]);
    }

    private function cmd_checkout(string $identifier): void
    {
        $this->check_out($this->reservation($identifier, 'inhouse'), $this->today);
    }

    private function cmd_invoice(string $identifier): void
    {
        $reservation = $this->reservation($identifier);
        $room = $reservation->room;
        $this->emit([
            'INVOICE', $identifier, $reservation->guest, 'room', $room->number,
            $room->kind, $reservation->status,
        ]);
        if (in_array($reservation->status, ['cancelled', 'noshow'], true)) {
            $label = $reservation->status === 'cancelled' ? 'cancellation' : 'noshow';
            $this->emit([$label, 'fee', money($reservation->fee)], 2);
            $this->emit(['total', money($reservation->fee)], 2);
            $this->emit($this->deposit_parts($reservation, $reservation->fee), 2);
            return;
        }
        foreach ($reservation->nights as [$day, $number, $rate]) {
            $this->emit([date_weekday($day), 'room', $number, money($rate)], 2);
        }
        [$lodging, $discount, $penalty, $extras, $tax, $total] =
            $reservation->bill ?? $this->calculate_bill($reservation);
        $this->emit(['lodging', money($lodging)], 2);
        $this->emit(['discount', money($discount)], 2);
        if ($reservation->penalty !== null) {
            $this->emit([
                'penalty', date_weekday($reservation->penalty[0]), money($penalty),
            ], 2);
        }
        foreach ($reservation->extras as [$item, $value]) {
            $this->emit(['extra', $item, money($value)], 2);
        }
        $this->emit(['tax', money($tax)], 2);
        $this->emit(['total', money($total)], 2);
        $this->emit($this->deposit_parts($reservation, $total), 2);
    }

    private function cmd_avail(string $kind, string $first, string $last): void
    {
        $this->require_type($kind);
        [$start, $end] = $this->period($first, $last);
        $rooms = array_keys(array_filter(
            $this->rooms,
            static fn (Room $room): bool => $room->kind === $kind,
        ));
        sort($rooms, SORT_NUMERIC);
        $this->emit(['AVAIL', $kind, $first, '->', $last]);
        for ($day = $start; $day <= $end; ++$day) {
            $free = [];
            foreach ($rooms as $number) {
                $key = self::night_key($day, $number);
                if (!isset($this->blocks[$key]) && !isset($this->occupied[$key])) {
                    $free[] = $number;
                }
            }
            $this->emit([date_weekday($day), 'free', count($free), ...$free], 2);
        }
    }

    private function occupancy_parts(array $numbers, int $day): array
    {
        $blocked = 0;
        $occupied = 0;
        foreach ($numbers as $number) {
            $key = self::night_key($day, $number);
            $blocked += (int) isset($this->blocks[$key]);
            $occupied += (int) isset($this->occupied[$key]);
        }
        $available = count($numbers) - $blocked;
        return [
            'rooms', count($numbers), 'blocked', $blocked, 'occupied', $occupied,
            'rate', $available > 0 ? intdiv($occupied * 100, $available) . '%' : 'n/a',
        ];
    }

    private function cmd_occupancy(string $text): void
    {
        $day = day_number($text);
        $this->emit([
            'OCCUPANCY', date_weekday($day),
            ...$this->occupancy_parts(array_keys($this->rooms), $day),
        ]);
        foreach (ROOM_TYPES as $kind) {
            $numbers = array_keys(array_filter(
                $this->rooms,
                static fn (Room $room): bool => $room->kind === $kind,
            ));
            if ($numbers) {
                $this->emit([$kind, ...$this->occupancy_parts($numbers, $day)], 2);
            }
        }
    }

    private function daily_values(int $day): array
    {
        $blocked = 0;
        $occupied = 0;
        $revenue = 0;
        foreach ($this->rooms as $number => $room) {
            $key = self::night_key($day, $number);
            $blocked += (int) isset($this->blocks[$key]);
            if (isset($this->occupied[$key])) {
                ++$occupied;
                $revenue += $this->occupied[$key][1];
            }
        }
        return [count($this->rooms) - $blocked, $occupied, $revenue];
    }

    private function metrics_parts(int $available, int $occupied, int $revenue): array
    {
        return [
            'sold', "$occupied/$available",
            'rate', $available > 0 ? intdiv($occupied * 100, $available) . '%' : 'n/a',
            'revenue', money($revenue),
            'adr', $occupied > 0 ? money(intdiv($revenue, $occupied)) : 'n/a',
            'revpar', $available > 0 ? money(intdiv($revenue, $available)) : 'n/a',
        ];
    }

    private function cmd_stats(string $first, string $last): void
    {
        [$start, $end] = $this->period($first, $last);
        $totals = [0, 0, 0];
        $this->emit(['STATS', $first, '->', $last]);
        for ($day = $start; $day <= $end; ++$day) {
            $values = $this->daily_values($day);
            for ($i = 0; $i < 3; ++$i) {
                $totals[$i] += $values[$i];
            }
            $this->emit([date_weekday($day), ...$this->metrics_parts(...$values)], 2);
        }
        $this->emit(['total', ...$this->metrics_parts(...$totals)], 2);
    }

    private function cmd_rooms(): void
    {
        $this->emit(['ROOMS', date_weekday($this->today), 'rooms', count($this->rooms)]);
        $rooms = $this->rooms;
        ksort($rooms, SORT_NUMERIC);
        foreach ($rooms as $number => $room) {
            $parts = [
                $number, $room->kind, 'base', money($room->rate),
                'tonight', money($this->night_rate($room, $this->today)),
                $room->clean ? 'clean' : 'dirty',
            ];
            $occupant = $this->inhouse($room);
            if ($occupant !== null) {
                array_push($parts, 'occupied', $occupant->identifier);
            } elseif (isset($this->blocks[self::night_key($this->today, $number)])) {
                $parts[] = 'blocked';
            } else {
                $parts[] = 'vacant';
            }
            $upcoming = null;
            foreach ($this->reservations as $r) {
                if ($r->status === 'booked' && $r->room === $room &&
                    ($upcoming === null || $r->arrival < $upcoming->arrival)) {
                    $upcoming = $r;
                }
            }
            if ($upcoming !== null) {
                array_push($parts, 'next', $upcoming->identifier, date_text($upcoming->arrival));
            }
            $this->emit($parts, 2);
        }
    }

    private function cmd_list(string $status): void
    {
        $selected = array_values(array_filter(
            $this->reservations,
            static fn (Reservation $r): bool => $r->status === $status,
        ));
        usort($selected, static fn (Reservation $a, Reservation $b): int =>
            ($a->arrival <=> $b->arrival) ?: strcmp($a->identifier, $b->identifier));
        $this->emit(['LIST', $status, count($selected)]);
        foreach ($selected as $r) {
            $this->emit([
                $r->identifier, $r->guest, 'room', $r->room->number,
                date_text($r->arrival), '->', date_text($r->departure),
            ], 2);
        }
    }

    private function cmd_queue(): void
    {
        $this->emit(['QUEUE', count($this->waitlist)]);
        foreach ($this->waitlist as $index => $entry) {
            $this->emit([
                $index + 1, $entry->identifier, $entry->guest, $entry->kind,
                date_text($entry->arrival), '->', date_text($entry->departure),
            ], 2);
        }
    }

    private function cmd_schedule(string $text): void
    {
        $day = day_number($text);
        $arrivals = array_values(array_filter(
            $this->reservations,
            static fn (Reservation $r): bool =>
                $r->arrival === $day && $r->status !== 'cancelled',
        ));
        $departures = array_values(array_filter(
            $this->reservations,
            static fn (Reservation $r): bool =>
                $r->departure === $day &&
                in_array($r->status, ['booked', 'inhouse', 'checkedout'], true),
        ));
        $by_id = static fn (Reservation $a, Reservation $b): int =>
            strcmp($a->identifier, $b->identifier);
        usort($arrivals, $by_id);
        usort($departures, $by_id);
        $this->emit([
            'SCHEDULE', date_weekday($day),
            'arrivals', count($arrivals), 'departures', count($departures),
        ]);
        foreach (['arrival' => $arrivals, 'departure' => $departures] as $label => $selected) {
            foreach ($selected as $r) {
                $this->emit([
                    $label, $r->identifier, $r->guest, 'room', $r->room->number, $r->status,
                ], 2);
            }
        }
    }

    private function cmd_guest(string $guest): void
    {
        $selected = array_values(array_filter(
            $this->reservations,
            static fn (Reservation $r): bool => $r->guest === $guest,
        ));
        if (!$selected) {
            throw new CommandError("unknown guest $guest");
        }
        $this->emit(['GUEST', $guest]);
        foreach ($selected as $r) {
            $deposit = in_array($r->status, ['booked', 'inhouse'], true);
            $this->emit([
                $r->identifier, 'room', $r->room->number, $r->room->kind,
                date_text($r->arrival), '->', date_text($r->departure),
                $r->status, $deposit ? 'deposit' : 'paid',
                money($deposit ? $r->deposit : $r->paid),
            ], 2);
        }
        $total = $this->guest_total($guest);
        $this->emit([
            'total paid', money($total), 'points', intdiv($total, 100), 'tier', $this->tier($guest),
        ], 2);
    }

    private function cmd_revenue(string $first, string $last): void
    {
        [$start, $end] = $this->period($first, $last, limited: false);
        $lodging = $discount = $penalty = $extras = $tax = 0;
        $cancellations = $noshows = 0;
        $checkouts = $cancelled = $absent = 0;
        foreach ($this->reservations as $r) {
            if ($r->posting === null || $r->posting < $start || $r->posting > $end) {
                continue;
            }
            if ($r->status === 'checkedout') {
                ++$checkouts;
                $lodging += $r->bill[0];
                $discount += $r->bill[1];
                $penalty += $r->bill[2];
                $extras += $r->bill[3];
                $tax += $r->bill[4];
            } elseif ($r->status === 'cancelled') {
                ++$cancelled;
                $cancellations += $r->fee;
            } elseif ($r->status === 'noshow') {
                ++$absent;
                $noshows += $r->fee;
            }
        }
        $this->emit(['REVENUE', $first, '->', $last]);
        foreach ([
            'lodging' => $lodging, 'discount' => $discount, 'penalty' => $penalty,
            'extras' => $extras, 'tax' => $tax, 'cancellation' => $cancellations,
            'noshow' => $noshows,
        ] as $label => $amount) {
            $this->emit([$label, money($amount)], 2);
        }
        $total = $lodging - $discount + $penalty + $extras + $tax + $cancellations + $noshows;
        $this->emit(['total', money($total)], 2);
        $this->emit([
            'checkouts', $checkouts, 'cancellations', $cancelled, 'noshows', $absent,
        ], 2);
    }

    public function execute(string $line): void
    {
        $words = explode(' ', trim($line));
        $command = array_shift($words);
        $handler = 'cmd_' . strtolower($command);
        try {
            $this->$handler(...$words);
        } catch (CommandError $error) {
            $this->emit(['ERROR', $error->getMessage()]);
        }
        $this->process_waitlist();
    }

    public function output(): string
    {
        return implode("\n", $this->output) . "\n";
    }
}

$count = (int) trim((string) fgets(STDIN));
$desk = new HotelDesk();
for ($i = 0; $i < $count; ++$i) {
    $desk->execute((string) fgets(STDIN));
}
echo $desk->output();
