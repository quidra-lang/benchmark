<?php

declare(strict_types=1);

const METHODS = ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'];
const REASONS = ['fields', 'date', 'time', 'ip', 'method', 'path', 'status', 'bytes', 'latency'];
const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const STATUS_CLASSES = ['1xx', '2xx', '3xx', '4xx', '5xx'];
const FILTER_KEYS = ['METHOD', 'STATUS', 'IP', 'PATH'];
const QUERY_FORMS = [
    'SUMMARY' => [], 'MALFORMED' => [], 'STATUS' => [], 'METHODS' => [],
    'TOP' => ['kind', 'limit'], 'HOURLY' => [], 'TIMELINE' => ['minutes'],
    'BANDWIDTH' => [], 'VISITORS' => [], 'LATENCY' => ['path'],
    'HISTOGRAM' => ['width'], 'APDEX' => ['threshold'], 'ERRORS' => [],
    'SLOWEST' => ['limit'], 'SESSIONS' => ['ip', 'minutes'],
    'BURST' => ['length', 'times'], 'PEAK' => ['length'],
    'GAPS' => ['length'], 'IP' => ['ip'],
    'RANGE' => ['date', 'time', 'date', 'time'], 'FILTER' => ['key', 'value'],
    'UNFILTER' => ['subject'], 'RESET' => [], 'STATE' => [],
];
const ARGUMENT_RANGES = [
    'limit' => [1, 100], 'minutes' => [1, 1440], 'width' => [1, 100000],
    'threshold' => [1, 100000], 'length' => [1, 86400], 'times' => [1, 1000],
];
const ARGUMENT_ERRORS = [
    'limit' => 'invalid number', 'minutes' => 'invalid number',
    'width' => 'invalid number', 'threshold' => 'invalid number',
    'length' => 'invalid number', 'times' => 'invalid number',
    'kind' => 'invalid kind', 'path' => 'invalid path', 'ip' => 'invalid ip',
    'date' => 'invalid timestamp', 'time' => 'invalid timestamp',
    'key' => 'invalid key', 'subject' => 'invalid key', 'value' => 'invalid value',
];
const OPTIONAL_LAST = ['LATENCY', 'SESSIONS'];
const NEEDS_TARGETS = [
    'STATUS', 'METHODS', 'TOP', 'HOURLY', 'TIMELINE', 'BANDWIDTH',
    'VISITORS', 'HISTOGRAM', 'APDEX', 'ERRORS', 'SLOWEST', 'BURST',
    'PEAK', 'GAPS',
];

final class CommandError extends RuntimeException {}

function check(bool $condition, string $reason): void
{
    if (!$condition) throw new CommandError($reason);
}

function validDigits(string $text): bool
{
    return preg_match('/\A[0-9]+\z/', $text) === 1;
}

function canonicalInteger(string $text, int $maxLength): bool
{
    return validDigits($text) && strlen($text) <= $maxLength &&
        (strlen($text) === 1 || $text[0] !== '0');
}

function leapYear(int $year): bool
{
    return $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
}

function daysInYear(int $year): int
{
    return leapYear($year) ? 366 : 365;
}

function daysInMonth(int $year, int $month): int
{
    return $month === 2 && leapYear($year) ? 29 : MONTH_DAYS[$month - 1];
}

function validDate(string $text): bool
{
    if (preg_match('/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/', $text) !== 1) return false;
    [$year, $month, $day] = array_map('intval', explode('-', $text));
    return $year >= 2000 && $year <= 2059 && $month >= 1 && $month <= 12 &&
        $day >= 1 && $day <= daysInMonth($year, $month);
}

function validTime(string $text): bool
{
    if (preg_match('/\A[0-9]{2}:[0-9]{2}:[0-9]{2}\z/', $text) !== 1) return false;
    [$hour, $minute, $second] = array_map('intval', explode(':', $text));
    return $hour <= 23 && $minute <= 59 && $second <= 59;
}

function validIP(string $text): bool
{
    $parts = explode('.', $text);
    if (count($parts) !== 4) return false;
    foreach ($parts as $part) {
        if (!canonicalInteger($part, 3) || (int)$part > 255) return false;
    }
    return true;
}

function validStatus(string $text): bool
{
    return preg_match('/\A[0-9]{3}\z/', $text) === 1 &&
        (int)$text >= 100 && (int)$text <= 599;
}

function validFilter(string $key, string $value): bool
{
    return match ($key) {
        'METHOD' => in_array($value, METHODS, true),
        'STATUS' => in_array($value, STATUS_CLASSES, true) || validStatus($value),
        'IP' => validIP($value),
        default => str_starts_with($value, '/'),
    };
}

function validArgument(string $type, string $text, array $arguments): bool
{
    if (isset(ARGUMENT_RANGES[$type])) {
        [$low, $high] = ARGUMENT_RANGES[$type];
        return canonicalInteger($text, 6) && (int)$text >= $low && (int)$text <= $high;
    }
    return match ($type) {
        'kind' => in_array($text, ['PATHS', 'IPS'], true),
        'path' => str_starts_with($text, '/'),
        'ip' => validIP($text),
        'date' => validDate($text),
        'time' => validTime($text),
        'key' => in_array($text, FILTER_KEYS, true),
        'subject' => $text === 'RANGE' || in_array($text, FILTER_KEYS, true),
        default => validFilter($arguments[0], $text),
    };
}

function malformedReason(array $fields): ?string
{
    if (count($fields) !== 8) return 'fields';
    [$date, $clock, $ip, $method, $path, $status, $bytes, $latency] = $fields;
    if (!validDate($date)) return 'date';
    if (!validTime($clock)) return 'time';
    if (!validIP($ip)) return 'ip';
    if (!in_array($method, METHODS, true)) return 'method';
    if (!str_starts_with($path, '/')) return 'path';
    if (!validStatus($status)) return 'status';
    if (!canonicalInteger($bytes, 8)) return 'bytes';
    if (!canonicalInteger($latency, 6)) return 'latency';
    return null;
}

function secondsOf(string $date, string $clock): int
{
    [$year, $month, $day] = array_map('intval', explode('-', $date));
    [$hour, $minute, $second] = array_map('intval', explode(':', $clock));
    $days = $day - 1;
    for ($y = 2000; $y < $year; ++$y) $days += daysInYear($y);
    for ($m = 1; $m < $month; ++$m) $days += daysInMonth($year, $m);
    return $days * 86400 + $hour * 3600 + $minute * 60 + $second;
}

function intervalLabel(int $seconds): string
{
    $days = intdiv($seconds, 86400);
    $rest = $seconds % 86400;
    $year = 2000;
    while ($days >= daysInYear($year)) $days -= daysInYear($year++);
    $month = 1;
    while ($days >= daysInMonth($year, $month)) $days -= daysInMonth($year, $month++);
    return sprintf('%d-%02d-%02d %02d:%02d', $year, $month, $days + 1,
        intdiv($rest, 3600), intdiv($rest % 3600, 60));
}

function normalizePath(string $raw): string
{
    $parts = [];
    foreach (explode('/', explode('?', $raw, 2)[0]) as $part) {
        if ($part === '..') array_pop($parts);
        elseif ($part !== '' && $part !== '.') $parts[] = $part;
    }
    return '/' . implode('/', array_map(static function (string $part): string {
        if (validDigits($part)) return '{id}';
        if (strlen($part) >= 8 && preg_match('/\A[0-9a-f]+\z/', $part) === 1 &&
            preg_match('/[0-9]/', $part) === 1) return '{hex}';
        return $part;
    }, $parts));
}

function compareIP(string $a, string $b): int
{
    $left = array_map('intval', explode('.', $a));
    $right = array_map('intval', explode('.', $b));
    for ($i = 0; $i < 4; ++$i) {
        if ($left[$i] !== $right[$i]) return $left[$i] <=> $right[$i];
    }
    return 0;
}

function decimal(int $numerator, int $denominator, int $places): string
{
    $scale = 10 ** $places;
    $value = intdiv($numerator * $scale, $denominator);
    return intdiv($value, $scale) . '.' . str_pad((string)($value % $scale), $places, '0', STR_PAD_LEFT);
}

function percentage(int $numerator, int $denominator): string
{
    return decimal($numerator * 100, $denominator, 2) . '%';
}

function bar(int $count, int $maximum): string
{
    return str_repeat('#', intdiv($count * 30 + $maximum - 1, $maximum));
}

function sizeNotation(int $bytes): string
{
    foreach ([[1073741824, 'GB'], [1048576, 'MB'], [1024, 'KB']] as [$base, $unit]) {
        if ($bytes >= $base) return decimal($bytes, $base, 1) . $unit;
    }
    return $bytes . 'B';
}

function statusCounts(array $records): array
{
    $counts = array_fill(0, 5, 0);
    foreach ($records as $r) ++$counts[intdiv($r->status, 100) - 1];
    return $counts;
}

function tally(array $records, callable $key): array
{
    $counts = [];
    foreach ($records as $r) {
        $value = $key($r);
        $counts[$value] = ($counts[$value] ?? 0) + 1;
    }
    return $counts;
}

function grouped(array $records, callable $key): array
{
    $groups = [];
    foreach ($records as $r) $groups[$key($r)][] = $r;
    return $groups;
}

function orderedByCount(array $counts, ?callable $tie = null): array
{
    $keys = array_keys($counts);
    usort($keys, static function ($a, $b) use ($counts, $tie): int {
        $cmp = $counts[$b] <=> $counts[$a];
        if ($cmp !== 0) return $cmp;
        return $tie ? $tie((string)$a, (string)$b) : strcmp((string)$a, (string)$b);
    });
    return $keys;
}

function buckets(array $numbers): array
{
    $first = min($numbers);
    $last = max($numbers);
    check($last - $first + 1 <= 60, 'too many buckets');
    $counts = array_fill(0, $last - $first + 1, 0);
    foreach ($numbers as $n) ++$counts[$n - $first];
    return [$first, $counts];
}

function percentile(array $sorted, int $rank): int
{
    return $sorted[intdiv($rank * count($sorted) + 99, 100) - 1];
}

function bestWindow(array $records, int $length): array
{
    $size = 0;
    $start = $end = null;
    $first = 0;
    foreach ($records as $last => $r) {
        while ($r->seconds - $records[$first]->seconds >= $length) ++$first;
        if ($last - $first + 1 > $size) {
            $size = $last - $first + 1;
            $start = $records[$first];
            $end = $r;
        }
    }
    return [$size, $start, $end];
}

function apdex(array $records, int $threshold): array
{
    $sat = $tol = 0;
    foreach ($records as $r) {
        if ($r->status >= 500) continue;
        if ($r->latency <= $threshold) ++$sat;
        elseif ($r->latency <= 4 * $threshold) ++$tol;
    }
    $count = count($records);
    $frustrated = $count - $sat - $tol;
    $points = 2 * $sat + $tol;
    $total = 2 * $count;
    $rating = 'unacceptable';
    foreach ([[94, 'excellent'], [85, 'good'], [70, 'fair'], [50, 'poor']] as [$minimum, $name]) {
        if ($points * 100 >= $minimum * $total) { $rating = $name; break; }
    }
    return [decimal($points, $total, 3), $rating, $sat, $tol,
        $frustrated, $count, $points, $total];
}

final class LogRecord
{
    public string $date;
    public string $timestamp;
    public string $ip;
    public string $method;
    public string $path;
    public int $hour;
    public int $seconds;
    public int $status;
    public int $size;
    public int $latency;

    public function __construct(public int $line, array $fields)
    {
        [$date, $clock, $this->ip, $this->method, $rawPath, $status, $size, $latency] = $fields;
        $this->date = $date;
        $this->timestamp = $date . ' ' . $clock;
        $this->hour = (int)substr($clock, 0, 2);
        $this->seconds = secondsOf($date, $clock);
        $this->path = normalizePath($rawPath);
        $this->status = (int)$status;
        $this->size = (int)$size;
        $this->latency = (int)$latency;
    }
}

final class LogAnalyzer
{
    private array $records = [];
    private array $malformed = [];
    private array $conditions = [];
    private ?array $range = null;
    private array $output = [];
    private int $lineCount;

    public function __construct(array $lines)
    {
        $this->lineCount = count($lines);
        foreach ($lines as $index => $line) {
            $fields = preg_split('/\s+/', trim($line));
            $reason = malformedReason($fields);
            if ($reason === null) $this->records[] = new LogRecord($index + 1, $fields);
            else $this->malformed[] = [$index + 1, $reason];
        }
        usort($this->records, static fn(LogRecord $a, LogRecord $b): int =>
            ($a->seconds <=> $b->seconds) ?: ($a->line <=> $b->line));
        foreach (FILTER_KEYS as $key) $this->conditions[$key] = null;
    }

    private function emit(...$parts): void
    {
        $this->output[] = implode(' ', array_map('strval', $parts));
    }

    private function barLine(string $label, int $count, int $maximum): void
    {
        if ($count) $this->emit($label, $count, bar($count, $maximum));
        else $this->emit($label, 0);
    }

    private function selected(): array
    {
        return array_values(array_filter($this->records, function (LogRecord $r): bool {
            if ($this->range !== null &&
                ($r->seconds < $this->range[2] || $r->seconds > $this->range[3])) return false;
            if ($this->conditions['METHOD'] !== null && $r->method !== $this->conditions['METHOD']) return false;
            if ($this->conditions['STATUS'] !== null) {
                $status = $this->conditions['STATUS'];
                if (in_array($status, STATUS_CLASSES, true)) {
                    if (intdiv($r->status, 100) !== (int)$status[0]) return false;
                } elseif ($r->status !== (int)$status) return false;
            }
            if ($this->conditions['IP'] !== null && $r->ip !== $this->conditions['IP']) return false;
            return $this->conditions['PATH'] === null || $r->path === $this->conditions['PATH'];
        }));
    }

    public function run(string $line): void
    {
        $tokens = preg_split('/\s+/', trim($line));
        $name = array_shift($tokens);
        try {
            check(array_key_exists($name, QUERY_FORMS), 'unknown query');
            $form = QUERY_FORMS[$name];
            $size = count($form);
            $optional = in_array($name, OPTIONAL_LAST, true) && count($tokens) === $size - 1;
            check(count($tokens) === $size || $optional, 'wrong arguments');
            foreach ($tokens as $i => $argument) {
                $kind = $form[$i];
                check(validArgument($kind, $argument, $tokens), ARGUMENT_ERRORS[$kind]);
            }
            $records = $this->selected();
            if (in_array($name, NEEDS_TARGETS, true) && !$records) {
                $this->emit($name, 'no records');
                return;
            }
            $this->command($name, $tokens, $records);
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }

    private function command(string $name, array $a, array $records): void
    {
        $count = count($records);
        switch ($name) {
            case 'SUMMARY':
                $this->emit('SUMMARY', 'lines', $this->lineCount, 'valid', count($this->records),
                    'malformed', count($this->malformed));
                $this->emit('requests', $count, 'bytes', array_sum(array_map(static fn($r) => $r->size, $records)),
                    'ips', count(array_unique(array_map(static fn($r) => $r->ip, $records))),
                    'paths', count(array_unique(array_map(static fn($r) => $r->path, $records))));
                if (!$records) $this->emit('span', 'none');
                else {
                    $last = $records[$count - 1];
                    $this->emit('span', $records[0]->timestamp, $last->timestamp, $last->seconds - $records[0]->seconds);
                }
                break;
            case 'MALFORMED':
                $this->emit('MALFORMED', count($this->malformed));
                foreach (REASONS as $reason) {
                    $numbers = [];
                    foreach ($this->malformed as [$index, $cause]) {
                        if ($cause === $reason) $numbers[] = $index;
                    }
                    if ($numbers) $this->emit($reason, count($numbers), ...$numbers);
                }
                break;
            case 'STATUS':
                $this->emit('STATUS', $count);
                foreach (statusCounts($records) as $i => $total) {
                    $this->emit(STATUS_CLASSES[$i], $total, percentage($total, $count));
                }
                $statuses = tally($records, static fn($r) => $r->status);
                ksort($statuses, SORT_NUMERIC);
                foreach ($statuses as $status => $total) $this->emit($status, $total, percentage($total, $count));
                break;
            case 'METHODS':
                $totals = tally($records, static fn($r) => $r->method);
                $this->emit('METHODS', $count);
                foreach (orderedByCount($totals) as $method) {
                    $this->emit($method, $totals[$method], percentage($totals[$method], $count));
                }
                break;
            case 'TOP':
                [$kind, $limit] = $a;
                $totals = tally($records, static fn($r) => $kind === 'PATHS' ? $r->path : $r->ip);
                $keys = orderedByCount($totals, $kind === 'IPS' ? 'compareIP' : null);
                $shown = min((int)$limit, count($keys));
                $this->emit('TOP', $kind, $shown, 'of', count($keys));
                $rank = 0;
                for ($i = 0; $i < $shown; ++$i) {
                    $key = $keys[$i];
                    if ($i === 0 || $totals[$key] !== $totals[$keys[$i - 1]]) $rank = $i + 1;
                    $this->emit($rank, $key, $totals[$key], percentage($totals[$key], $count));
                }
                break;
            case 'HOURLY':
                $totals = array_fill(0, 24, 0);
                foreach ($records as $r) ++$totals[$r->hour];
                $largest = max($totals);
                $this->emit('HOURLY', $count, 'peak', sprintf('%02d', array_search($largest, $totals, true)), $largest);
                foreach ($totals as $hour => $total) $this->barLine(sprintf('%02d', $hour), $total, $largest);
                break;
            case 'TIMELINE':
                $minutes = (int)$a[0];
                $width = $minutes * 60;
                [$first, $totals] = buckets(array_map(static fn($r) => intdiv($r->seconds, $width), $records));
                $this->emit('TIMELINE', $minutes, count($totals));
                $largest = max($totals);
                foreach ($totals as $i => $total) $this->barLine(intervalLabel(($first + $i) * $width), $total, $largest);
                break;
            case 'BANDWIDTH':
                $days = grouped($records, static fn($r) => $r->date);
                $bytes = array_sum(array_map(static fn($r) => $r->size, $records));
                $this->emit('BANDWIDTH', count($days), $bytes, sizeNotation($bytes));
                ksort($days, SORT_STRING);
                foreach ($days as $date => $items) {
                    $amount = array_sum(array_map(static fn($r) => $r->size, $items));
                    $this->emit($date, count($items), $amount, sizeNotation($amount));
                }
                break;
            case 'VISITORS':
                $first = [];
                foreach ($records as $r) {
                    if (!isset($first[$r->ip]) || strcmp($r->date, $first[$r->ip]) < 0) $first[$r->ip] = $r->date;
                }
                $days = grouped($records, static fn($r) => $r->date);
                $this->emit('VISITORS', count($days), count($first));
                ksort($days, SORT_STRING);
                foreach ($days as $date => $items) {
                    $ips = array_unique(array_map(static fn($r) => $r->ip, $items));
                    $new = count(array_filter($ips, static fn($ip) => $first[$ip] === $date));
                    $this->emit($date, 'unique', count($ips), 'new', $new, 'returning', count($ips) - $new);
                }
                break;
            case 'LATENCY':
                $label = $a ? normalizePath($a[0]) : 'all';
                $items = $a ? array_values(array_filter($records, static fn($r) => $r->path === $label)) : $records;
                if (!$items) { $this->emit('LATENCY', 'no records'); break; }
                $times = array_map(static fn($r) => $r->latency, $items);
                sort($times, SORT_NUMERIC);
                $n = count($times);
                $trim = intdiv($n, 10);
                $trimmed = array_slice($times, $trim, $n - 2 * $trim);
                $this->emit('LATENCY', $label, 'count', $n, 'min', $times[0],
                    'p50', percentile($times, 50), 'p90', percentile($times, 90),
                    'p99', percentile($times, 99), 'max', $times[$n - 1],
                    'mean', decimal(array_sum($times), $n, 2),
                    'trimmed', decimal(array_sum($trimmed), count($trimmed), 2));
                break;
            case 'HISTOGRAM':
                $width = (int)$a[0];
                [$first, $totals] = buckets(array_map(static fn($r) => intdiv($r->latency, $width), $records));
                $this->emit('HISTOGRAM', $width, count($totals));
                $largest = max($totals);
                foreach ($totals as $i => $total) {
                    $low = ($first + $i) * $width;
                    $this->barLine($low . '-' . ($low + $width - 1), $total, $largest);
                }
                break;
            case 'APDEX':
                $threshold = (int)$a[0];
                [$notation, $rating, $sat, $tol, $frustrated] = apdex($records, $threshold);
                $this->emit('APDEX', $threshold, $notation, $rating, 'satisfied', $sat,
                    'tolerating', $tol, 'frustrated', $frustrated);
                $groups = grouped($records, static fn($r) => $r->path);
                $scores = [];
                foreach ($groups as $path => $items) $scores[] = [$path, apdex($items, $threshold)];
                usort($scores, static function (array $a, array $b): int {
                    $x = $a[1]; $y = $b[1];
                    return ($x[6] * $y[7] <=> $y[6] * $x[7]) ?: ($y[5] <=> $x[5]) ?: strcmp($a[0], $b[0]);
                });
                foreach ($scores as [$path, $score]) $this->emit($path, $score[0], $score[1], $score[5]);
                break;
            case 'ERRORS':
                $failed = count(array_filter($records, static fn($r) => $r->status >= 400));
                $this->emit('ERRORS', $failed, 'of', $count, percentage($failed, $count));
                $groups = grouped($records, static fn($r) => $r->path);
                $rows = [];
                foreach ($groups as $path => $items) {
                    $client = count(array_filter($items, static fn($r) => intdiv($r->status, 100) === 4));
                    $server = count(array_filter($items, static fn($r) => intdiv($r->status, 100) === 5));
                    if ($client + $server > 0) $rows[] = [$path, count($items), $client, $server];
                }
                usort($rows, static function (array $a, array $b): int {
                    $f1 = $a[2] + $a[3];
                    $f2 = $b[2] + $b[3];
                    return ($f2 * $a[1] <=> $f1 * $b[1]) ?: ($f2 <=> $f1) ?: strcmp($a[0], $b[0]);
                });
                foreach ($rows as [$path, $n, $client, $server]) {
                    $this->emit($path, $n, $client, $server, percentage($client + $server, $n));
                }
                break;
            case 'SLOWEST':
                $groups = grouped($records, static fn($r) => $r->method . "\x1F" . $r->path);
                $rows = [];
                foreach ($groups as $key => $items) {
                    [$method, $path] = explode("\x1F", $key, 2);
                    $rows[] = [$method, $path, count($items),
                        array_sum(array_map(static fn($r) => $r->latency, $items)),
                        max(array_map(static fn($r) => $r->latency, $items))];
                }
                usort($rows, static fn(array $a, array $b): int =>
                    ($b[3] * $a[2] <=> $a[3] * $b[2]) ?: ($b[4] <=> $a[4]) ?:
                    strcmp($a[1], $b[1]) ?: strcmp($a[0], $b[0]));
                $shown = min((int)$a[0], count($rows));
                $this->emit('SLOWEST', $shown, 'of', count($rows));
                foreach (array_slice($rows, 0, $shown) as $i => [$method, $path, $n, $sum, $max]) {
                    $this->emit($i + 1, $method, $path, 'count', $n,
                        'avg', decimal($sum, $n, 2), 'max', $max);
                }
                break;
            case 'SESSIONS':
                $ip = $a[0];
                $minutes = isset($a[1]) ? (int)$a[1] : 30;
                $items = array_values(array_filter($records, static fn($r) => $r->ip === $ip));
                if (!$items) { $this->emit('SESSIONS', 'no records'); break; }
                $sessions = [[$items[0]]];
                for ($i = 1, $n = count($items); $i < $n; ++$i) {
                    $last = count($sessions) - 1;
                    if ($items[$i]->seconds - $items[$i - 1]->seconds <= $minutes * 60)
                        $sessions[$last][] = $items[$i];
                    else $sessions[] = [$items[$i]];
                }
                $durations = 0;
                foreach ($sessions as $session) $durations += end($session)->seconds - $session[0]->seconds;
                $this->emit('SESSIONS', $ip, 'timeout', $minutes, 'count', count($sessions),
                    'requests', count($items), 'avg_duration', decimal($durations, count($sessions), 1),
                    'avg_requests', decimal(count($items), count($sessions), 1));
                foreach ($sessions as $i => $session) {
                    $first = $session[0]; $last = end($session);
                    $paths = array_unique(array_map(static fn($r) => $r->path, $session));
                    $this->emit($i + 1, $first->timestamp, $last->timestamp,
                        $last->seconds - $first->seconds, count($session), count($paths));
                }
                break;
            case 'BURST':
                [$length, $times] = array_map('intval', $a);
                $groups = grouped(array_values(array_filter($records, static fn($r) => $r->status >= 400)),
                    static fn($r) => $r->ip);
                $rows = [];
                foreach ($groups as $ip => $items) {
                    [$size, $first, $last] = bestWindow($items, $length);
                    if ($size >= $times) $rows[] = [$ip, $size, $first, $last];
                }
                usort($rows, static fn(array $a, array $b): int =>
                    ($b[1] <=> $a[1]) ?: compareIP($a[0], $b[0]));
                $this->emit('BURST', $length, $times, count($rows));
                foreach ($rows as [$ip, $size, $first, $last]) {
                    $this->emit($ip, $size, $first->timestamp, $last->timestamp);
                }
                break;
            case 'PEAK':
                $length = (int)$a[0];
                [$size, $first, $last] = bestWindow($records, $length);
                $this->emit('PEAK', $length, $size, $first->timestamp, $last->timestamp);
                break;
            case 'GAPS':
                $length = (int)$a[0];
                $gaps = [];
                for ($i = 1; $i < $count; ++$i) {
                    if ($records[$i]->seconds - $records[$i - 1]->seconds >= $length)
                        $gaps[] = [$records[$i - 1], $records[$i]];
                }
                $this->emit('GAPS', $length, count($gaps));
                foreach ($gaps as [$before, $after]) {
                    $this->emit($before->timestamp, $after->timestamp, $after->seconds - $before->seconds);
                }
                break;
            case 'IP':
                $ip = $a[0];
                $items = array_values(array_filter($records, static fn($r) => $r->ip === $ip));
                if (!$items) { $this->emit('IP', 'no records'); break; }
                $paths = tally($items, static fn($r) => $r->path);
                $this->emit('IP', $ip, 'requests', count($items),
                    'bytes', array_sum(array_map(static fn($r) => $r->size, $items)),
                    'errors', count(array_filter($items, static fn($r) => $r->status >= 400)),
                    'paths', count($paths));
                $this->emit('first', $items[0]->timestamp, 'last', end($items)->timestamp);
                $methods = tally($items, static fn($r) => $r->method);
                $parts = ['methods'];
                foreach (orderedByCount($methods) as $method) array_push($parts, $method, $methods[$method]);
                $this->emit(...$parts);
                $parts = ['classes'];
                foreach (statusCounts($items) as $i => $total) array_push($parts, STATUS_CLASSES[$i], $total);
                $this->emit(...$parts);
                foreach (array_slice(orderedByCount($paths), 0, 3) as $path) {
                    $this->emit('path', $path, $paths[$path]);
                }
                break;
            case 'RANGE':
                $start = $a[0] . ' ' . $a[1];
                $end = $a[2] . ' ' . $a[3];
                $first = secondsOf($a[0], $a[1]);
                $last = secondsOf($a[2], $a[3]);
                check($first <= $last, 'invalid range');
                $this->range = [$start, $end, $first, $last];
                $this->emit('RANGE', $start, $end, 'active', count($this->selected()));
                break;
            case 'FILTER':
                [$key, $value] = $a;
                if ($key === 'PATH') $value = normalizePath($value);
                $this->conditions[$key] = $value;
                $this->emit('FILTER', $key, $value, 'active', count($this->selected()));
                break;
            case 'UNFILTER':
                $key = $a[0];
                if ($key === 'RANGE') {
                    check($this->range !== null, 'not filtered');
                    $this->range = null;
                } else {
                    check($this->conditions[$key] !== null, 'not filtered');
                    $this->conditions[$key] = null;
                }
                $this->emit('UNFILTER', $key, 'active', count($this->selected()));
                break;
            case 'RESET':
                $this->range = null;
                foreach (FILTER_KEYS as $key) $this->conditions[$key] = null;
                $this->emit('RESET', 'active', count($this->selected()));
                break;
            case 'STATE':
                $parts = ['STATE', 'active', $count, 'range'];
                if ($this->range === null) $parts[] = '-';
                else array_push($parts, $this->range[0], $this->range[1]);
                foreach (FILTER_KEYS as $key) {
                    array_push($parts, strtolower($key), $this->conditions[$key] ?? '-');
                }
                $this->emit(...$parts);
                break;
        }
    }

    public function output(): void
    {
        if ($this->output) echo implode("\n", $this->output) . "\n";
    }
}

$lines = file('php://stdin', FILE_IGNORE_NEW_LINES);
$separator = array_search('---', $lines, true);
$finish = array_search('END', array_slice($lines, $separator + 1), true) + $separator + 1;
$analyzer = new LogAnalyzer(array_slice($lines, 0, $separator));
for ($i = $separator + 1; $i < $finish; ++$i) $analyzer->run($lines[$i]);
$analyzer->output();
