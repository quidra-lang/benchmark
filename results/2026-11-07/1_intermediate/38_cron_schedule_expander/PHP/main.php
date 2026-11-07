<?php
declare(strict_types=1);

final class CommandError extends RuntimeException {}
const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];
const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
function isDigits(string $text, int $minimum, int $maximum): bool
{
    $length = strlen($text);
    return $length >= $minimum && $length <= $maximum && strspn($text, "0123456789") === $length;
}
function leapYear(int $year): bool
{
    return $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
}
function monthLength(int $year, int $month): int
{
    return $month === 2 && leapYear($year) ? 29 : MONTH_DAYS[$month - 1];
}

final readonly class CivilDate
{
    public function __construct(public int $year, public int $month, public int $day) {}
    public function number(): int
    {
        $result = $this->day - 1;
        for ($year = 2000; $year < $this->year; $year++) {
            $result += leapYear($year) ? 366 : 365;
        }
        for ($month = 1; $month < $this->month; $month++) {
            $result += monthLength($this->year, $month);
        }
        return $result;
    }
    public function weekday(): int
    {
        return ($this->number() + 6) % 7;
    }
    public function dateText(): string
    {
        return sprintf("%04d-%02d-%02d", $this->year, $this->month, $this->day);
    }
    public function __toString(): string
    {
        return $this->dateText() . " " . substr(WEEKDAYS[$this->weekday()], 0, 3);
    }
    public static function fromNumber(int $number): self
    {
        $year = 2000;
        $month = 1;
        while ($number >= (leapYear($year) ? 366 : 365)) {
            $number -= leapYear($year) ? 366 : 365;
            $year++;
        }
        while ($number >= monthLength($year, $month)) {
            $number -= monthLength($year, $month);
            $month++;
        }
        return new self($year, $month, $number + 1);
    }
    public static function parse(string $text): ?self
    {
        if (
            strlen($text) !== 10 ||
            $text[4] !== "-" ||
            $text[7] !== "-" ||
            !isDigits(substr($text, 0, 4), 4, 4) ||
            !isDigits(substr($text, 5, 2), 2, 2) ||
            !isDigits(substr($text, 8), 2, 2)
        ) {
            return null;
        }
        $year = (int) substr($text, 0, 4);
        $month = (int) substr($text, 5, 2);
        $day = (int) substr($text, 8);
        if (
            $year < 2001 ||
            $year > 2098 ||
            $month < 1 ||
            $month > 12 ||
            $day < 1 ||
            $day > monthLength($year, $month)
        ) {
            return null;
        }
        return new self($year, $month, $day);
    }
}
function readDate(string $text): CivilDate
{
    return CivilDate::parse($text) ?? throw new CommandError("invalid date");
}
function readMinute(string $dateText, string $time): int
{
    $date = CivilDate::parse($dateText);
    if (
        $date === null ||
        strlen($time) !== 5 ||
        $time[2] !== ":" ||
        !isDigits(substr($time, 0, 2), 2, 2) ||
        !isDigits(substr($time, 3), 2, 2)
    ) {
        throw new CommandError("invalid datetime");
    }
    $hour = (int) substr($time, 0, 2);
    $minute = (int) substr($time, 3);
    if ($hour > 23 || $minute > 59) {
        throw new CommandError("invalid datetime");
    }
    return $date->number() * 1440 + $hour * 60 + $minute;
}
function readMonth(string $text): array
{
    if (
        strlen($text) !== 7 ||
        $text[4] !== "-" ||
        !isDigits(substr($text, 0, 4), 4, 4) ||
        !isDigits(substr($text, 5), 2, 2)
    ) {
        throw new CommandError("invalid month");
    }
    $year = (int) substr($text, 0, 4);
    $month = (int) substr($text, 5);
    if ($year < 2001 || $year > 2098 || $month < 1 || $month > 12) {
        throw new CommandError("invalid month");
    }
    return [$year, $month];
}
function minuteText(int $minute): string
{
    $date = CivilDate::fromNumber(intdiv($minute, 1440));
    return $date->dateText() .
        sprintf(" %02d:%02d ", intdiv($minute % 1440, 60), $minute % 60) .
        substr(WEEKDAYS[$date->weekday()], 0, 3);
}
function spanText(int $minutes): string
{
    return sprintf(
        "%dd%02dh%02dm",
        intdiv($minutes, 1440),
        intdiv($minutes % 1440, 60),
        $minutes % 60,
    );
}
function checkWindow(int $low, int $high): void
{
    if ($low > $high) {
        throw new CommandError("invalid window");
    }
    if ($high - $low > 44640) {
        throw new CommandError("window too long");
    }
}

enum SpecialKind
{
    case Last;
    case LastWeekday;
    case BeforeLast;
    case NearestWeekday;
    case NthWeekday;
    case LastOccurrence;
}
final readonly class Special
{
    public function __construct(
        public SpecialKind $kind,
        public int $value = 0,
        public int $occurrence = 0,
    ) {}
    public function __toString(): string
    {
        return match ($this->kind) {
            SpecialKind::Last => "L",
            SpecialKind::LastWeekday => "LW",
            SpecialKind::BeforeLast => "L-{$this->value}",
            SpecialKind::NearestWeekday => "{$this->value}W",
            SpecialKind::NthWeekday => "{$this->value}#{$this->occurrence}",
            SpecialKind::LastOccurrence => "{$this->value}L",
        };
    }
}
final readonly class CronField
{
    public function __construct(
        public int $index,
        public array $values,
        public array $specials,
        public bool $restricted,
    ) {}
    public function contains(int $value): bool
    {
        return in_array($value, $this->values, true);
    }
}
final readonly class Cron
{
    public const FIELD_NAMES = ["minute", "hour", "day-of-month", "month", "day-of-week"];
    private const MINIMUM = [0, 0, 1, 1, 0],
        MAXIMUM = [59, 23, 31, 12, 7];
    private const MONTH_NAMES = [
        "JAN",
        "FEB",
        "MAR",
        "APR",
        "MAY",
        "JUN",
        "JUL",
        "AUG",
        "SEP",
        "OCT",
        "NOV",
        "DEC",
    ];
    private const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    private const MACROS = [
        "@yearly" => "0 0 1 1 *",
        "@annually" => "0 0 1 1 *",
        "@monthly" => "0 0 1 * *",
        "@weekly" => "0 0 * * 0",
        "@daily" => "0 0 * * *",
        "@midnight" => "0 0 * * *",
        "@hourly" => "0 * * * *",
    ];
    public array $daily;
    public string $expanded;
    private function __construct(array $words, public array $fields)
    {
        $daily = [];
        foreach ($fields[1]->values as $hour) {
            foreach ($fields[0]->values as $minute) {
                $daily[] = $hour * 60 + $minute;
            };
        }
        $this->daily = $daily;
        $this->expanded = implode(" ", $words);
    }
    public function orRule(): bool
    {
        return $this->fields[2]->restricted && $this->fields[4]->restricted;
    }
    public function rule(): string
    {
        return $this->orRule() ? "OR" : "AND";
    }
    private static function fieldError(int $index, string $reason): CommandError
    {
        return new CommandError(self::FIELD_NAMES[$index] . " " . $reason);
    }
    private static function value(string $text, int $index): int
    {
        $named =
            $index === 3
                ? array_search($text, self::MONTH_NAMES, true)
                : ($index === 4
                    ? array_search($text, self::DAY_NAMES, true)
                    : false);
        if ($named !== false) {
            return $named + ($index === 3 ? 1 : 0);
        }
        if (!isDigits($text, 1, 2)) {
            throw self::fieldError($index, "invalid value");
        }
        $value = (int) $text;
        if ($value < self::MINIMUM[$index] || $value > self::MAXIMUM[$index]) {
            throw self::fieldError($index, "out of range");
        }
        return $value;
    }
    private static function specialNumber(
        string $text,
        int $index,
        int $maximum,
        int $size = 2,
    ): int {
        if (!isDigits($text, 1, $size)) {
            throw self::fieldError($index, "invalid value");
        }
        $value = (int) $text;
        if ($value < 1 || $value > $maximum) {
            throw self::fieldError($index, "out of range");
        }
        return $value;
    }
    private static function field(string $text, int $index): CronField
    {
        $values = [];
        $specials = [];
        $seen = [];
        foreach (explode(",", $text) as $item) {
            if ($item === "") {
                throw self::fieldError($index, "empty item");
            }
            $special = null;
            $hash = strpos($item, "#");
            if ($index === 2 && (str_starts_with($item, "L") || str_ends_with($item, "W"))) {
                if ($item === "L") {
                    $special = new Special(SpecialKind::Last);
                } elseif ($item === "LW") {
                    $special = new Special(SpecialKind::LastWeekday);
                } elseif (str_starts_with($item, "L-")) {
                    $special = new Special(
                        SpecialKind::BeforeLast,
                        self::specialNumber(substr($item, 2), $index, 30),
                    );
                } elseif (str_ends_with($item, "W")) {
                    $special = new Special(
                        SpecialKind::NearestWeekday,
                        self::specialNumber(substr($item, 0, -1), $index, 31),
                    );
                } else {
                    throw self::fieldError($index, "invalid value");
                }
            } elseif ($index === 4 && $hash !== false) {
                $weekday = self::value(substr($item, 0, $hash), $index);
                $occurrence = self::specialNumber(substr($item, $hash + 1), $index, 5, 1);
                $special = new Special(SpecialKind::NthWeekday, $weekday % 7, $occurrence);
            } elseif ($index === 4 && strlen($item) >= 2 && str_ends_with($item, "L")) {
                $special = new Special(
                    SpecialKind::LastOccurrence,
                    self::value(substr($item, 0, -1), $index) % 7,
                );
            }
            if ($special !== null) {
                $canonical = (string) $special;
                if (!isset($seen[$canonical])) {
                    $seen[$canonical] = true;
                    $specials[] = $special;
                }
                continue;
            }
            $slash = strpos($item, "/");
            $base = $slash === false ? $item : substr($item, 0, $slash);
            $dash = strpos($base, "-");
            if ($base === "*") {
                $low = self::MINIMUM[$index];
                $high = self::MAXIMUM[$index];
            } elseif ($dash !== false) {
                $low = self::value(substr($base, 0, $dash), $index);
                $high = self::value(substr($base, $dash + 1), $index);
                if ($low > $high) {
                    throw self::fieldError($index, "invalid range");
                }
            } else {
                $low = self::value($base, $index);
                $high = $slash === false ? $low : self::MAXIMUM[$index];
            }
            $step = 1;
            if ($slash !== false) {
                $part = substr($item, $slash + 1);
                if (!isDigits($part, 1, 2) || (int) $part === 0) {
                    throw self::fieldError($index, "invalid step");
                }
                $step = (int) $part;
            }
            for ($value = $low; $value <= $high; $value += $step) {
                $values[$index === 4 ? $value % 7 : $value] = true;
            }
        }
        $numbers = array_keys($values);
        sort($numbers, SORT_NUMERIC);
        return new CronField($index, $numbers, $specials, $text[0] !== "*");
    }
    public static function parse(array $words): self
    {
        if (count($words) === 1 && str_starts_with($words[0], "@")) {
            $replacement = self::MACROS[$words[0]] ?? throw new CommandError("unknown macro");
            $words = explode(" ", $replacement);
        }
        if (count($words) !== 5) {
            throw new CommandError("field count");
        }
        $fields = [];
        foreach ($words as $index => $word) {
            $fields[] = self::field($word, $index);
        }
        return new self($words, $fields);
    }
    private static function nearest(CivilDate $date, int $day): int
    {
        $weekday = ($date->number() - $date->day + $day + 6) % 7;
        if ($weekday === 6) {
            return $day === 1 ? 3 : $day - 1;
        }
        if ($weekday === 0) {
            return $day === monthLength($date->year, $date->month) ? $day - 2 : $day + 1;
        }
        return $day;
    }
    public function matchDay(CivilDate $date): array
    {
        $last = monthLength($date->year, $date->month);
        $day = $date->day;
        $weekday = $date->weekday();
        $monthDay = $this->fields[2]->contains($day);
        $weekDay = $this->fields[4]->contains($weekday);
        foreach ($this->fields[2]->specials as $special) {
            $matches = match ($special->kind) {
                SpecialKind::Last => $day === $last,
                SpecialKind::LastWeekday => $day === self::nearest($date, $last),
                SpecialKind::BeforeLast => $day === $last - $special->value,
                default => $special->value <= $last &&
                    $day === self::nearest($date, $special->value),
            };
            $monthDay = $monthDay || $matches;
        }
        foreach ($this->fields[4]->specials as $special) {
            $matches =
                $weekday === $special->value &&
                ($special->kind === SpecialKind::NthWeekday
                    ? intdiv($day - 1, 7) + 1 === $special->occurrence
                    : $day + 7 > $last);
            $weekDay = $weekDay || $matches;
        }
        return [
            $monthDay,
            $weekDay,
            $this->orRule() ? $monthDay || $weekDay : $monthDay && $weekDay,
        ];
    }
    public function scheduled(CivilDate $date): bool
    {
        return $this->fields[3]->contains($date->month) && $this->matchDay($date)[2];
    }
    public function fireTimes(
        int $low,
        int $high,
        array $holidays,
        bool $reverse = false,
    ): Generator {
        $first = intdiv($low, 1440);
        $last = intdiv($high, 1440);
        $count = count($this->daily);
        for (
            $day = $reverse ? $last : $first;
            $reverse ? $day >= $first : $day <= $last;
            $day += $reverse ? -1 : 1
        ) {
            if (isset($holidays[$day]) || !$this->scheduled(CivilDate::fromNumber($day))) {
                continue;
            }
            for (
                $i = $reverse ? $count - 1 : 0;
                $reverse ? $i >= 0 : $i < $count;
                $i += $reverse ? -1 : 1
            ) {
                $time = $day * 1440 + $this->daily[$i];
                if ($low <= $time && $time <= $high) {
                    yield $time;
                }
            }
        }
    }
    public function reasons(int $time, array $holidays): array
    {
        $date = CivilDate::fromNumber(intdiv($time, 1440));
        [$monthDay, $weekDay, $condition] = $this->matchDay($date);
        $reasons = [];
        if (!$this->fields[0]->contains($time % 60)) {
            $reasons[] = "minute";
        }
        if (!$this->fields[1]->contains(intdiv($time % 1440, 60))) {
            $reasons[] = "hour";
        }
        if (!$condition && !$monthDay) {
            $reasons[] = "day-of-month";
        }
        if (!$this->fields[3]->contains($date->month)) {
            $reasons[] = "month";
        }
        if (!$condition && !$weekDay) {
            $reasons[] = "day-of-week";
        }
        if (isset($holidays[$date->number()])) {
            $reasons[] = "excluded";
        }
        return $reasons;
    }
    private static function listJoin(array $parts, bool $either = false): string
    {
        if (count($parts) < 2) {
            return $parts[0] ?? "";
        }
        return implode(", ", array_slice($parts, 0, -1)) .
            ($either ? " or " : " and ") .
            $parts[count($parts) - 1];
    }
    private static function valueName(int $index, int $value): string
    {
        return match ($index) {
            3 => MONTHS[$value - 1],
            4 => WEEKDAYS[$value],
            default => (string) $value,
        };
    }
    private static function valueList(CronField $field, bool $either = false): string
    {
        $parts = [];
        $values = $field->values;
        $count = count($values);
        for ($start = 0; $start < $count; ) {
            $end = $start;
            while ($end + 1 < $count && $values[$end + 1] === $values[$end] + 1) {
                $end++;
            }
            if ($end - $start >= 2) {
                $parts[] =
                    self::valueName($field->index, $values[$start]) .
                    " through " .
                    self::valueName($field->index, $values[$end]);
            } else {
                for ($i = $start; $i <= $end; $i++) {
                    $parts[] = self::valueName($field->index, $values[$i]);
                };
            }
            $start = $end + 1;
        }
        return self::listJoin($parts, $either);
    }
    private static function stepped(CronField $field): int
    {
        $values = $field->values;
        if (count($values) < 2 || $values[0] !== 0 || $values[1] < 2) {
            return 0;
        }
        $step = $values[1];
        if (count($values) !== intdiv(self::MAXIMUM[$field->index], $step) + 1) {
            return 0;
        }
        foreach ($values as $i => $value) {
            if ($value !== $i * $step) {
                return 0;
            }
        }
        return $step;
    }
    private function dayClause(bool $weekday, bool $either = false): string
    {
        $field = $this->fields[$weekday ? 4 : 2];
        $parts = [];
        if ($field->values !== []) {
            $parts[] = $weekday
                ? self::valueList($field, $either)
                : (count($field->values) === 1 ? "day " : "days ") . self::valueList($field);
        }
        $ordinals = ["1st", "2nd", "3rd", "4th", "5th"];
        foreach ($field->specials as $special) {
            $parts[] = match ($special->kind) {
                SpecialKind::Last => "the last day",
                SpecialKind::LastWeekday => "the last weekday",
                SpecialKind::BeforeLast => $special->value .
                    ($special->value === 1 ? " day" : " days") .
                    " before the last day",
                SpecialKind::NearestWeekday => "the weekday nearest day " . $special->value,
                SpecialKind::NthWeekday => "the " .
                    $ordinals[$special->occurrence - 1] .
                    " " .
                    WEEKDAYS[$special->value],
                SpecialKind::LastOccurrence => "the last " . WEEKDAYS[$special->value],
            };
        }
        return self::listJoin($parts, $either) .
            (!$weekday || $field->specials !== [] ? " of the month" : "");
    }
    public function describe(): string
    {
        $minute = $this->fields[0];
        $hour = $this->fields[1];
        if (count($this->daily) <= 4) {
            $text =
                "At " .
                self::listJoin(
                    array_map(
                        static fn(int $time): string => sprintf(
                            "%02d:%02d",
                            intdiv($time, 60),
                            $time % 60,
                        ),
                        $this->daily,
                    ),
                );
        } else {
            $minuteStep = self::stepped($minute);
            $hourStep = self::stepped($hour);
            $text = match (true) {
                count($minute->values) === 60 => "Every minute",
                $minuteStep !== 0 => "Every $minuteStep minutes",
                count($minute->values) === 1 => "At minute " . $minute->values[0],
                default => "At minutes " . self::valueList($minute),
            };
            if (count($hour->values) === 24) {
                if (str_starts_with($text, "At minute")) {
                    $text .= " of every hour";
                }
            } elseif ($hourStep !== 0) {
                $text .= ", every $hourStep hours";
            } elseif (
                $hour->values[count($hour->values) - 1] - $hour->values[0] + 1 ===
                count($hour->values)
            ) {
                $text .= sprintf(
                    ", between %02d:00 and %02d:59",
                    $hour->values[0],
                    $hour->values[count($hour->values) - 1],
                );
            } else {
                $text .= ", during hours " . self::valueList($hour);
            }
        }
        $monthFull = count($this->fields[2]->values) === 31;
        $weekFull = count($this->fields[4]->values) === 7;
        if ($this->orRule()) {
            if (!$monthFull && !$weekFull) {
                $text .= ", on " . $this->dayClause(false) . " or on " . $this->dayClause(true);
            }
        } elseif (!$monthFull && !$weekFull) {
            $text .=
                ", on " . $this->dayClause(false) . " if it is " . $this->dayClause(true, true);
        } elseif (!$monthFull) {
            $text .= ", on " . $this->dayClause(false);
        } elseif (!$weekFull) {
            $text .= ", on " . $this->dayClause(true);
        }
        if (count($this->fields[3]->values) !== 12) {
            $text .= ", in " . self::valueList($this->fields[3]);
        }
        return $text;
    }
}

enum Policy: string
{
    case Allow = "ALLOW";
    case Forbid = "FORBID";
    case Replace = "REPLACE";
}
final class Job
{
    public bool $enabled = true;
    public int $duration = 1;
    public Policy $policy = Policy::Allow;
    public function __construct(
        public string $id,
        public readonly Cron $cron,
        public readonly string $text,
    ) {}
}
final class Scheduler
{
    private array $jobs = [],
        $holidays = [];
    private const ARITY = [
        "JOB" => -2,
        "VALIDATE" => -1,
        "REMOVE" => 1,
        "RENAME" => 2,
        "ENABLE" => 1,
        "DISABLE" => 1,
        "RUNTIME" => 3,
        "LIST" => 0,
        "EXPAND" => 2,
        "DESCRIBE" => 1,
        "MATCH" => 3,
        "NEXT" => 4,
        "PREV" => 4,
        "COUNT" => 5,
        "GAP" => 3,
        "OVERLAP" => 6,
        "TIMELINE" => 4,
        "CONFLICTS" => 4,
        "WEEK" => 1,
        "CALENDAR" => 2,
        "SIMULATE" => 4,
        "EXCLUDE" => 1,
        "INCLUDE" => 1,
        "HOLIDAYS" => 0,
    ];
    private function getJob(string $id): Job
    {
        return $this->jobs[$id] ?? throw new CommandError("unknown job");
    }
    private function newId(string $id): void
    {
        if (
            strlen($id) < 1 ||
            strlen($id) > 16 ||
            $id[0] < "a" ||
            $id[0] > "z" ||
            strspn($id, "abcdefghijklmnopqrstuvwxyz0123456789_") !== strlen($id)
        ) {
            throw new CommandError("invalid id");
        }
        if (isset($this->jobs[$id])) {
            throw new CommandError("duplicate job");
        }
    }
    private static function positive(string $text, int $size, int $maximum, string $reason): int
    {
        if (!isDigits($text, 1, $size) || $text[0] === "0" || (int) $text > $maximum) {
            throw new CommandError($reason);
        }
        return (int) $text;
    }
    private function ordered(bool $enabledOnly = false): array
    {
        $jobs = array_values(
            array_filter($this->jobs, static fn(Job $job): bool => !$enabledOnly || $job->enabled),
        );
        usort($jobs, static fn(Job $a, Job $b): int => strcmp($a->id, $b->id));
        return $jobs;
    }
    private function schedule(int $low, int $high): array
    {
        $result = [];
        foreach ($this->ordered(true) as $job) {
            foreach ($job->cron->fireTimes($low, $high, $this->holidays) as $time) {
                $result[$time][] = $job->id;
            };
        }
        ksort($result, SORT_NUMERIC);
        return $result;
    }
    private function timeline(int $low, int $high, bool $conflicts): array
    {
        $times = $this->schedule($low, $high);
        $rows = [];
        if ($conflicts) {
            $times = array_filter($times, static fn(array $ids): bool => count($ids) >= 2);
            $peak = 0;
            foreach ($times as $ids) {
                $peak = max($peak, count($ids));
            }
            $rows[] = "CONFLICTS " . count($times) . " peak $peak";
            foreach (array_slice($times, 0, 100, true) as $time => $ids) {
                $rows[] = minuteText($time) . " " . count($ids) . " " . implode(" ", $ids);
            }
            if (count($times) > 100) {
                $rows[] = "... " . (count($times) - 100) . " more";
            }
        } else {
            $count = 0;
            $written = 0;
            foreach ($times as $ids) {
                $count += count($ids);
            }
            $rows[] = "TIMELINE $count";
            foreach ($times as $time => $ids) {
                foreach ($ids as $id) {
                    if ($written === 100) {
                        break 2;
                    }
                    $rows[] = minuteText($time) . " $id";
                    $written++;
                }
            }
            if ($count > 100) {
                $rows[] = "... " . ($count - 100) . " more";
            }
        }
        return $rows;
    }
    private function week(string $input, CivilDate $start): array
    {
        $counts = array_fill(0, 7, array_fill(0, 24, 0));
        $low = $start->number() * 1440;
        $total = 0;
        foreach ($this->ordered(true) as $job) {
            foreach ($job->cron->fireTimes($low, $low + 7 * 1440 - 1, $this->holidays) as $time) {
                $counts[intdiv($time - $low, 1440)][intdiv($time % 1440, 60)]++;
                $total++;
            }
        }
        $rows = ["WEEK $input $total"];
        foreach ($counts as $day => $hours) {
            $marks = "";
            foreach ($hours as $count) {
                $marks .= $count === 0 ? "." : ($count >= 10 ? "+" : (string) $count);
            }
            $rows[] =
                CivilDate::fromNumber($start->number() + $day) . " $marks " . array_sum($hours);
        }
        return $rows;
    }
    private function calendar(Job $job, string $input, int $year, int $month): array
    {
        $first = new CivilDate($year, $month, 1);
        $cells = array_fill(0, $first->weekday(), "...");
        $count = 0;
        for ($day = 1; $day <= monthLength($year, $month); $day++) {
            $date = new CivilDate($year, $month, $day);
            $mark = $job->cron->scheduled($date)
                ? (isset($this->holidays[$date->number()])
                    ? "x"
                    : "*")
                : "-";
            if ($mark === "*") {
                $count++;
            }
            $cells[] = sprintf("%02d%s", $day, $mark);
        }
        while (count($cells) % 7 !== 0) {
            $cells[] = "...";
        }
        $rows = [
            "CALENDAR {$job->id} $input days $count runs " . $count * count($job->cron->daily),
            "Sun Mon Tue Wed Thu Fri Sat",
        ];
        foreach (array_chunk($cells, 7) as $week) {
            $rows[] = implode(" ", $week);
        }
        return $rows;
    }
    private function simulate(int $low, int $high): array
    {
        $jobs = $this->ordered(true);
        $events = [];
        $details = [];
        foreach ($jobs as $job) {
            $started = 0;
            $skipped = 0;
            $replaced = 0;
            $busy = 0;
            $lastEnd = 0;
            foreach ($job->cron->fireTimes($low, $high, $this->holidays) as $time) {
                if ($lastEnd > $time) {
                    if ($job->policy === Policy::Forbid) {
                        $skipped++;
                        continue;
                    }
                    if ($job->policy === Policy::Replace) {
                        $events[$lastEnd] = ($events[$lastEnd] ?? 0) + 1;
                        $events[$time] = ($events[$time] ?? 0) - 1;
                        $busy -= $lastEnd - $time;
                        $replaced++;
                    }
                }
                $lastEnd = $time + $job->duration;
                $events[$time] = ($events[$time] ?? 0) + 1;
                $events[$lastEnd] = ($events[$lastEnd] ?? 0) - 1;
                $busy += $job->duration;
                $started++;
            }
            $details[] = "{$job->id} {$job->policy->value} started $started skipped $skipped replaced $replaced busy $busy";
        }
        ksort($events, SORT_NUMERIC);
        $running = 0;
        $peak = 0;
        $at = 0;
        foreach ($events as $time => $delta) {
            $running += $delta;
            if ($running > $peak) {
                $peak = $running;
                $at = $time;
            }
        }
        return array_merge(
            [
                "SIMULATE " .
                count($jobs) .
                " peak $peak" .
                ($peak === 0 ? "" : " at " . minuteText($at)),
            ],
            $details,
        );
    }
    public function execute(array $words): array
    {
        $command = $words[0];
        $expected = self::ARITY[$command] ?? throw new CommandError("unknown command");
        $count = count($words) - 1;
        if ($expected < 0 ? $count < -$expected : $count !== $expected) {
            throw new CommandError("wrong arguments");
        }
        switch ($command) {
            case "JOB":
                $id = $words[1];
                $this->newId($id);
                $expression = array_slice($words, 2);
                $cron = Cron::parse($expression);
                $this->jobs[$id] = new Job($id, $cron, implode(" ", $expression));
                return ["JOB $id added"];
            case "VALIDATE":
                $cron = Cron::parse(array_slice($words, 1));
                return ["VALID {$cron->expanded} " . $cron->rule() . " " . count($cron->daily)];
            case "REMOVE":
                $job = $this->getJob($words[1]);
                unset($this->jobs[$job->id]);
                return ["REMOVE {$job->id}"];
            case "RENAME":
                $job = $this->getJob($words[1]);
                $this->newId($words[2]);
                unset($this->jobs[$job->id]);
                $job->id = $words[2];
                $this->jobs[$job->id] = $job;
                return ["RENAME {$words[1]} {$job->id}"];
            case "ENABLE":
            case "DISABLE":
                $job = $this->getJob($words[1]);
                $enable = $command === "ENABLE";
                if ($job->enabled === $enable) {
                    throw new CommandError($enable ? "already enabled" : "already disabled");
                }
                $job->enabled = $enable;
                return ["$command {$job->id}"];
            case "RUNTIME":
                $job = $this->getJob($words[1]);
                $duration = self::positive($words[2], 4, 1440, "invalid duration");
                $policy = Policy::tryFrom($words[3]) ?? throw new CommandError("invalid policy");
                $job->duration = $duration;
                $job->policy = $policy;
                return ["RUNTIME {$job->id} $duration {$policy->value}"];
            case "LIST":
                $rows = ["LIST " . count($this->jobs)];
                foreach ($this->ordered() as $job) {
                    $rows[] =
                        $job->id .
                        ($job->enabled ? " on " : " off ") .
                        "{$job->duration} {$job->policy->value} {$job->text}";
                }
                return $rows;
            case "EXPAND":
                $job = $this->getJob($words[1]);
                $index = array_search($words[2], Cron::FIELD_NAMES, true);
                if ($index === false) {
                    throw new CommandError("invalid field");
                }
                $field = $job->cron->fields[$index];
                $items = array_merge(
                    $field->values,
                    array_map(
                        static fn(Special $special): string => (string) $special,
                        $field->specials,
                    ),
                );
                return [
                    "EXPAND {$job->id} {$words[2]} " .
                    count($field->values) .
                    ($items === [] ? "" : " " . implode(" ", $items)),
                ];
            case "DESCRIBE":
                $job = $this->getJob($words[1]);
                return ["DESCRIBE {$job->id} " . $job->cron->describe()];
            case "MATCH":
                $job = $this->getJob($words[1]);
                $time = readMinute($words[2], $words[3]);
                $reasons = $job->cron->reasons($time, $this->holidays);
                return [
                    "MATCH {$job->id} " .
                    minuteText($time) .
                    ($reasons === [] ? " yes" : " no " . implode(" ", $reasons)),
                ];
            case "NEXT":
            case "PREV":
                $job = $this->getJob($words[1]);
                $start = readMinute($words[2], $words[3]);
                $limit = self::positive($words[4], 2, 50, "invalid count");
                $reverse = $command === "PREV";
                $times = [];
                foreach (
                    $job->cron->fireTimes(
                        $reverse ? $start - 527040 : $start + 1,
                        $reverse ? $start - 1 : $start + 527040,
                        $this->holidays,
                        $reverse,
                    )
                    as $time
                ) {
                    $times[] = $time;
                    if (count($times) === $limit) {
                        break;
                    }
                }
                $rows = ["$command {$job->id} " . count($times)];
                foreach ($times as $time) {
                    $rows[] =
                        minuteText($time) .
                        ($reverse ? " -" : " +") .
                        spanText(abs($time - $start));
                }
                if (count($times) < $limit) {
                    $rows[] = "NONE";
                }
                return $rows;
            case "COUNT":
                $job = $this->getJob($words[1]);
                $low = readMinute($words[2], $words[3]);
                $high = readMinute($words[4], $words[5]);
                checkWindow($low, $high);
                $runs = 0;
                $days = [];
                foreach ($job->cron->fireTimes($low, $high, $this->holidays) as $time) {
                    $runs++;
                    $days[intdiv($time, 1440)] = true;
                }
                return ["COUNT {$job->id} runs $runs days " . count($days)];
            case "GAP":
                $job = $this->getJob($words[1]);
                $start = readMinute($words[2], $words[3]);
                $times = iterator_to_array(
                    $job->cron->fireTimes($start, $start + 44640, $this->holidays),
                    false,
                );
                $runs = count($times);
                if ($runs < 2) {
                    return ["GAP {$job->id} runs $runs none"];
                }
                $frequencies = [];
                $shortest = 44641;
                $longest = 0;
                $from = 0;
                for ($i = 1; $i < $runs; $i++) {
                    $gap = $times[$i] - $times[$i - 1];
                    $shortest = min($shortest, $gap);
                    if ($gap > $longest) {
                        $longest = $gap;
                        $from = $i - 1;
                    }
                    $frequencies[$gap] = ($frequencies[$gap] ?? 0) + 1;
                }
                $rows = [
                    "GAP {$job->id} runs $runs shortest " .
                    spanText($shortest) .
                    " longest " .
                    spanText($longest) .
                    " from " .
                    minuteText($times[$from]) .
                    " to " .
                    minuteText($times[$from + 1]),
                ];
                ksort($frequencies, SORT_NUMERIC);
                foreach ($frequencies as $gap => $frequency) {
                    $rows[] = spanText($gap) . " $frequency";
                }
                return $rows;
            case "OVERLAP":
                $a = $this->getJob($words[1]);
                $b = $this->getJob($words[2]);
                $low = readMinute($words[3], $words[4]);
                $high = readMinute($words[5], $words[6]);
                checkWindow($low, $high);
                $other = [];
                foreach ($b->cron->fireTimes($low, $high, $this->holidays) as $time) {
                    $other[$time] = true;
                }
                $times = [];
                foreach ($a->cron->fireTimes($low, $high, $this->holidays) as $time) {
                    if (isset($other[$time])) {
                        $times[] = $time;
                    }
                }
                return [
                    "OVERLAP {$a->id} {$b->id} " .
                    count($times) .
                    ($times === []
                        ? ""
                        : " first " .
                            minuteText($times[0]) .
                            " last " .
                            minuteText($times[count($times) - 1])),
                ];
            case "TIMELINE":
            case "CONFLICTS":
            case "SIMULATE":
                $low = readMinute($words[1], $words[2]);
                $high = readMinute($words[3], $words[4]);
                checkWindow($low, $high);
                return $command === "SIMULATE"
                    ? $this->simulate($low, $high)
                    : $this->timeline($low, $high, $command === "CONFLICTS");
            case "WEEK":
                $date = readDate($words[1]);
                return $this->week($words[1], $date);
            case "CALENDAR":
                $job = $this->getJob($words[1]);
                [$year, $month] = readMonth($words[2]);
                return $this->calendar($job, $words[2], $year, $month);
            case "EXCLUDE":
            case "INCLUDE":
                $date = readDate($words[1]);
                $day = $date->number();
                if ($command === "EXCLUDE") {
                    if (isset($this->holidays[$day])) {
                        throw new CommandError("already excluded");
                    }
                    $this->holidays[$day] = true;
                } else {
                    if (!isset($this->holidays[$day])) {
                        throw new CommandError("not excluded");
                    }
                    unset($this->holidays[$day]);
                }
                return ["$command $date holidays " . count($this->holidays)];
            case "HOLIDAYS":
                $days = array_keys($this->holidays);
                sort($days, SORT_NUMERIC);
                return array_merge(
                    ["HOLIDAYS " . count($days)],
                    array_map(
                        static fn(int $day): string => (string) CivilDate::fromNumber($day),
                        $days,
                    ),
                );
        }
        throw new LogicException("Unknown command");
    }
}

$first = fgets(STDIN);
if ($first === false) {
    exit();
}
$scheduler = new Scheduler();
$count = (int) $first;
for ($i = 0; $i < $count; $i++) {
    $words = array_values(
        array_filter(
            explode(" ", rtrim(fgets(STDIN), "\r\n")),
            static fn(string $word): bool => $word !== "",
        ),
    );
    try {
        foreach ($scheduler->execute($words) as $row) {
            echo $row, "\n";
        }
    } catch (CommandError $error) {
        echo "ERROR ", $error->getMessage(), "\n";
    }
}
