<?php
declare(strict_types=1);

const METHODS = ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'];
const REASONS = ['fields', 'date', 'time', 'ip', 'method', 'path', 'status', 'bytes', 'latency'];
const CLASSES = ['1xx', '2xx', '3xx', '4xx', '5xx'];
const FILTER_KEYS = ['METHOD', 'STATUS', 'IP', 'PATH'];
const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const FORMS = [
    'SUMMARY' => [], 'MALFORMED' => [], 'STATUS' => [], 'METHODS' => [],
    'TOP' => ['kind', 'limit'], 'HOURLY' => [], 'TIMELINE' => ['minutes'],
    'BANDWIDTH' => [], 'VISITORS' => [], 'LATENCY' => ['path'],
    'HISTOGRAM' => ['width'], 'APDEX' => ['threshold'], 'ERRORS' => [],
    'SLOWEST' => ['limit'], 'SESSIONS' => ['ip', 'minutes'],
    'BURST' => ['length', 'times'], 'PEAK' => ['length'], 'GAPS' => ['length'],
    'IP' => ['ip'], 'RANGE' => ['date', 'time', 'date', 'time'],
    'FILTER' => ['key', 'value'], 'UNFILTER' => ['subject'],
    'RESET' => [], 'STATE' => []
];
const REQUIRES_RECORDS = [
    'STATUS', 'METHODS', 'TOP', 'HOURLY', 'TIMELINE', 'BANDWIDTH',
    'VISITORS', 'HISTOGRAM', 'APDEX', 'ERRORS', 'SLOWEST', 'BURST', 'PEAK', 'GAPS'
];
const RANGES = [
    'limit' => [1, 100], 'minutes' => [1, 1440],
    'width' => [1, 100000], 'threshold' => [1, 100000],
    'length' => [1, 86400], 'times' => [1, 1000]
];
const ERRORS = [
    'limit' => 'invalid number', 'minutes' => 'invalid number',
    'width' => 'invalid number', 'threshold' => 'invalid number',
    'length' => 'invalid number', 'times' => 'invalid number',
    'kind' => 'invalid kind', 'path' => 'invalid path', 'ip' => 'invalid ip',
    'date' => 'invalid timestamp', 'time' => 'invalid timestamp',
    'key' => 'invalid key', 'subject' => 'invalid key', 'value' => 'invalid value'
];

final class QueryError extends RuntimeException {}

function require_condition(bool $ok, string $message): void
{
    if (!$ok) {
        throw new QueryError($message);
    }
}

function tokens(string $line): array
{
    $line = trim($line);
    return $line === '' ? [] : preg_split('/\s+/', $line);
}

function digits(string $value): bool
{
    return preg_match('/^[0-9]+$/D', $value) === 1;
}

function canonical(string $value, int $maximum): bool
{
    return $value !== '' && strlen($value) <= $maximum && digits($value) &&
        (strlen($value) === 1 || $value[0] !== '0');
}

function leap_year(int $year): bool
{
    return $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
}

function year_days(int $year): int
{
    return leap_year($year) ? 366 : 365;
}

function month_days(int $year, int $month): int
{
    return $month === 2 && leap_year($year) ? 29 : MONTH_DAYS[$month - 1];
}

function valid_date(string $value): bool
{
    if (preg_match('/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/D', $value) !== 1) {
        return false;
    }
    $year = (int)substr($value, 0, 4);
    $month = (int)substr($value, 5, 2);
    $day = (int)substr($value, 8, 2);
    return $year >= 2000 && $year <= 2059 && $month >= 1 && $month <= 12 &&
        $day >= 1 && $day <= month_days($year, $month);
}

function valid_time(string $value): bool
{
    return preg_match('/^[0-9]{2}:[0-9]{2}:[0-9]{2}$/D', $value) === 1 &&
        (int)substr($value, 0, 2) <= 23 &&
        (int)substr($value, 3, 2) <= 59 &&
        (int)substr($value, 6, 2) <= 59;
}

function valid_ip(string $ip): bool
{
    $parts = explode('.', $ip);
    if (count($parts) !== 4) {
        return false;
    }
    foreach ($parts as $part) {
        if (!canonical($part, 3) || (int)$part > 255) {
            return false;
        }
    }
    return true;
}

function valid_status(string $value): bool
{
    return preg_match('/^[0-9]{3}$/D', $value) === 1 &&
        (int)$value >= 100 && (int)$value <= 599;
}

function filter_value(string $key, string $value): bool
{
    return match ($key) {
        'METHOD' => in_array($value, METHODS, true),
        'STATUS' => in_array($value, CLASSES, true) || valid_status($value),
        'IP' => valid_ip($value),
        default => str_starts_with($value, '/')
    };
}

function valid_argument(string $type, string $value, array $args): bool
{
    if (array_key_exists($type, RANGES)) {
        [$lower, $upper] = RANGES[$type];
        return canonical($value, 6) && (int)$value >= $lower && (int)$value <= $upper;
    }
    return match ($type) {
        'kind' => $value === 'PATHS' || $value === 'IPS',
        'path' => str_starts_with($value, '/'),
        'ip' => valid_ip($value),
        'date' => valid_date($value),
        'time' => valid_time($value),
        'key' => in_array($value, FILTER_KEYS, true),
        'subject' => $value === 'RANGE' || in_array($value, FILTER_KEYS, true),
        default => filter_value($args[0], $value)
    };
}

function malformed_reason(array $fields): ?string
{
    if (count($fields) !== 8) return 'fields';
    if (!valid_date($fields[0])) return 'date';
    if (!valid_time($fields[1])) return 'time';
    if (!valid_ip($fields[2])) return 'ip';
    if (!in_array($fields[3], METHODS, true)) return 'method';
    if (!str_starts_with($fields[4], '/')) return 'path';
    if (!valid_status($fields[5])) return 'status';
    if (!canonical($fields[6], 8)) return 'bytes';
    if (!canonical($fields[7], 6)) return 'latency';
    return null;
}

function seconds_of(string $date, string $clock): int
{
    $year = (int)substr($date, 0, 4);
    $month = (int)substr($date, 5, 2);
    $days = (int)substr($date, 8, 2) - 1;
    for ($y = 2000; $y < $year; $y++) $days += year_days($y);
    for ($m = 1; $m < $month; $m++) $days += month_days($year, $m);
    return $days * 86400 + (int)substr($clock, 0, 2) * 3600 +
        (int)substr($clock, 3, 2) * 60 + (int)substr($clock, 6, 2);
}

function interval_label(int $seconds): string
{
    $days = intdiv($seconds, 86400);
    $minutes = intdiv($seconds % 86400, 60);
    $year = 2000;
    while ($days >= year_days($year)) {
        $days -= year_days($year);
        $year++;
    }
    $month = 1;
    while ($days >= month_days($year, $month)) {
        $days -= month_days($year, $month);
        $month++;
    }
    return sprintf('%04d-%02d-%02d %02d:%02d', $year, $month,
        $days + 1, intdiv($minutes, 60), $minutes % 60);
}

function normalize_path(string $path): string
{
    $parts = [];
    foreach (explode('/', explode('?', $path, 2)[0]) as $part) {
        if ($part === '..') {
            array_pop($parts);
        } elseif ($part !== '' && $part !== '.') {
            $parts[] = $part;
        }
    }
    foreach ($parts as &$part) {
        if (digits($part)) {
            $part = '{id}';
        } elseif (strlen($part) >= 8 &&
            preg_match('/^[0-9a-f]+$/D', $part) === 1 &&
            preg_match('/[0-9]/', $part) === 1) {
            $part = '{hex}';
        }
    }
    unset($part);
    return '/' . implode('/', $parts);
}

function compare_ip(string $a, string $b): int
{
    $x = array_map('intval', explode('.', $a));
    $y = array_map('intval', explode('.', $b));
    for ($i = 0; $i < 4; $i++) {
        if ($x[$i] !== $y[$i]) return $x[$i] <=> $y[$i];
    }
    return 0;
}

function status_matches(string $filter, int $status): bool
{
    return in_array($filter, CLASSES, true) ?
        intdiv($status, 100) === (int)$filter[0] : $status === (int)$filter;
}

function decimal_value(int $numerator, int $denominator, int $places): string
{
    $scale = 10 ** $places;
    $value = intdiv($numerator * $scale, $denominator);
    return intdiv($value, $scale) . '.' .
        str_pad((string)($value % $scale), $places, '0', STR_PAD_LEFT);
}

function percentage(int $part, int $total): string
{
    return decimal_value($part * 100, $total, 2) . '%';
}

function bar(int $count, int $max): string
{
    return str_repeat('#', intdiv($count * 30 + $max - 1, $max));
}

function bytes_text(int $bytes): string
{
    foreach ([[1073741824, 'GB'], [1048576, 'MB'], [1024, 'KB']] as [$unit, $label]) {
        if ($bytes >= $unit) return decimal_value($bytes, $unit, 1) . $label;
    }
    return $bytes . 'B';
}

function sum_property(array $rows, string $key): int
{
    $sum = 0;
    foreach ($rows as $row) $sum += $row[$key];
    return $sum;
}

function tallied(array $values): array
{
    $result = [];
    foreach ($values as $value) {
        $result[$value] = ($result[$value] ?? 0) + 1;
    }
    return $result;
}

function field_values(array $rows, string $field): array
{
    return array_map(static fn($row) => $row[$field], $rows);
}

function grouped(array $rows, callable $key): array
{
    $result = [];
    foreach ($rows as $row) {
        $value = $key($row);
        $result[$value][] = $row;
    }
    return $result;
}

function by_count(array $counts, ?callable $compare = null): array
{
    $keys = array_keys($counts);
    $compare ??= 'strcmp';
    usort($keys, static function ($a, $b) use ($counts, $compare): int {
        $n = $counts[$b] <=> $counts[$a];
        return $n !== 0 ? $n : $compare((string)$a, (string)$b);
    });
    return $keys;
}

function class_counts(array $rows): array
{
    $counts = [0, 0, 0, 0, 0];
    foreach ($rows as $row) $counts[intdiv($row['status'], 100) - 1]++;
    return $counts;
}

function buckets(array $numbers): array
{
    $first = min($numbers);
    $length = max($numbers) - $first + 1;
    require_condition($length <= 60, 'too many buckets');
    $counts = array_fill(0, $length, 0);
    foreach ($numbers as $number) $counts[$number - $first]++;
    return [$first, $counts];
}

function percentile(array $sorted, int $rank): int
{
    return $sorted[intdiv($rank * count($sorted) + 99, 100) - 1];
}

function window_peak(array $rows, int $length): array
{
    $best = 0;
    $start = 0;
    $end = 0;
    $first = 0;
    $size = count($rows);
    for ($i = 0; $i < $size; $i++) {
        while ($rows[$i]['seconds'] - $rows[$first]['seconds'] >= $length) $first++;
        if ($i - $first + 1 > $best) {
            $best = $i - $first + 1;
            $start = $first;
            $end = $i;
        }
    }
    return ['count' => $best, 'start' => $rows[$start], 'end' => $rows[$end]];
}

function apdex_score(array $rows, int $threshold): array
{
    $satisfied = 0;
    $tolerating = 0;
    foreach ($rows as $row) {
        if ($row['status'] >= 500) continue;
        if ($row['latency'] <= $threshold) $satisfied++;
        elseif ($row['latency'] <= 4 * $threshold) $tolerating++;
    }
    $size = count($rows);
    $points = 2 * $satisfied + $tolerating;
    $total = 2 * $size;
    $rating = match (true) {
        $points * 100 >= 94 * $total => 'excellent',
        $points * 100 >= 85 * $total => 'good',
        $points * 100 >= 70 * $total => 'fair',
        $points * 100 >= 50 * $total => 'poor',
        default => 'unacceptable'
    };
    return [
        'count' => $size, 'satisfied' => $satisfied, 'tolerating' => $tolerating,
        'frustrated' => $size - $satisfied - $tolerating, 'points' => $points,
        'total' => $total, 'notation' => decimal_value($points, $total, 3),
        'rating' => $rating
    ];
}

final class LogAnalyzer
{
    private array $records = [];
    private array $malformed = [];
    private int $lineCount;
    private array $conditions = ['METHOD' => null, 'STATUS' => null, 'IP' => null, 'PATH' => null];
    private ?int $rangeStart = null;
    private ?int $rangeEnd = null;
    private ?string $startLabel = null;
    private ?string $endLabel = null;
    public array $output = [];

    public function __construct(array $lines)
    {
        $this->lineCount = count($lines);
        foreach ($lines as $i => $line) {
            $fields = tokens($line);
            $reason = malformed_reason($fields);
            if ($reason !== null) {
                $this->malformed[] = ['line' => $i + 1, 'reason' => $reason];
                continue;
            }
            $this->records[] = [
                'line' => $i + 1, 'date' => $fields[0],
                'timestamp' => $fields[0] . ' ' . $fields[1],
                'hour' => (int)substr($fields[1], 0, 2),
                'seconds' => seconds_of($fields[0], $fields[1]),
                'ip' => $fields[2], 'method' => $fields[3],
                'path' => normalize_path($fields[4]), 'status' => (int)$fields[5],
                'bytes' => (int)$fields[6], 'latency' => (int)$fields[7]
            ];
        }
        usort($this->records, static fn($a, $b) =>
            ($a['seconds'] <=> $b['seconds']) ?: ($a['line'] <=> $b['line']));
    }

    private function emit(mixed ...$parts): void
    {
        $this->output[] = implode(' ', array_map('strval', $parts));
    }

    private function selected(): array
    {
        return array_values(array_filter($this->records, function ($row): bool {
            if ($this->rangeStart !== null &&
                ($row['seconds'] < $this->rangeStart ||
                 $row['seconds'] > $this->rangeEnd)) return false;
            if ($this->conditions['METHOD'] !== null &&
                $row['method'] !== $this->conditions['METHOD']) return false;
            if ($this->conditions['STATUS'] !== null &&
                !status_matches($this->conditions['STATUS'], $row['status'])) return false;
            if ($this->conditions['IP'] !== null &&
                $row['ip'] !== $this->conditions['IP']) return false;
            return $this->conditions['PATH'] === null ||
                $row['path'] === $this->conditions['PATH'];
        }));
    }

    private function barLine(string $label, int $count, int $maximum): void
    {
        if ($count === 0) $this->emit($label, $count);
        else $this->emit($label, $count, bar($count, $maximum));
    }

    public function execute(string $line): void
    {
        $fields = tokens($line);
        $name = array_shift($fields) ?? '';
        $args = $fields;
        try {
            require_condition(array_key_exists($name, FORMS), 'unknown query');
            $form = FORMS[$name];
            $optional = ($name === 'LATENCY' || $name === 'SESSIONS') &&
                count($args) === count($form) - 1;
            require_condition(count($args) === count($form) || $optional, 'wrong arguments');
            foreach ($args as $i => $arg) {
                require_condition(valid_argument($form[$i], $arg, $args), ERRORS[$form[$i]]);
            }
            $rows = $this->selected();
            if (in_array($name, REQUIRES_RECORDS, true) && $rows === []) {
                $this->emit($name, 'no records');
                return;
            }
            $this->run($name, $args, $rows);
        } catch (QueryError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }

    private function run(string $name, array $a, array $rows): void
    {
        switch ($name) {
            case 'SUMMARY':
                $this->emit('SUMMARY', 'lines', $this->lineCount, 'valid',
                    count($this->records), 'malformed', count($this->malformed));
                $this->emit('requests', count($rows), 'bytes', sum_property($rows, 'bytes'),
                    'ips', count(array_unique(field_values($rows, 'ip'))),
                    'paths', count(array_unique(field_values($rows, 'path'))));
                if ($rows === []) $this->emit('span', 'none');
                else $this->emit('span', $rows[0]['timestamp'], $rows[count($rows)-1]['timestamp'],
                    $rows[count($rows)-1]['seconds'] - $rows[0]['seconds']);
                break;

            case 'MALFORMED':
                $this->emit('MALFORMED', count($this->malformed));
                foreach (REASONS as $reason) {
                    $lines = array_column(array_values(array_filter($this->malformed,
                        static fn($row) => $row['reason'] === $reason)), 'line');
                    if ($lines !== []) $this->emit($reason, count($lines), ...$lines);
                }
                break;

            case 'STATUS':
                $this->emit('STATUS', count($rows));
                $classes = class_counts($rows);
                foreach (CLASSES as $i => $label) {
                    $this->emit($label, $classes[$i], percentage($classes[$i], count($rows)));
                }
                $statuses = tallied(field_values($rows, 'status'));
                ksort($statuses, SORT_NUMERIC);
                foreach ($statuses as $status => $count) {
                    $this->emit($status, $count, percentage($count, count($rows)));
                }
                break;

            case 'METHODS':
                $counts = tallied(field_values($rows, 'method'));
                $this->emit('METHODS', count($rows));
                foreach (by_count($counts) as $method) {
                    $this->emit($method, $counts[$method],
                        percentage($counts[$method], count($rows)));
                }
                break;

            case 'TOP':
                $kind = $a[0];
                $counts = tallied(array_map(
                    static fn($row) => $kind === 'PATHS' ? $row['path'] : $row['ip'], $rows));
                $keys = by_count($counts, $kind === 'IPS' ? 'compare_ip' : null);
                $limit = min((int)$a[1], count($keys));
                $this->emit('TOP', $kind, $limit, 'of', count($keys));
                $rank = 0;
                for ($i = 0; $i < $limit; $i++) {
                    if ($i === 0 || $counts[$keys[$i]] !== $counts[$keys[$i-1]]) $rank = $i+1;
                    $this->emit($rank, $keys[$i], $counts[$keys[$i]],
                        percentage($counts[$keys[$i]], count($rows)));
                }
                break;

            case 'HOURLY':
                $counts = array_fill(0, 24, 0);
                foreach ($rows as $row) $counts[$row['hour']]++;
                $maximum = max($counts);
                $this->emit('HOURLY', count($rows), 'peak',
                    sprintf('%02d', array_search($maximum, $counts, true)), $maximum);
                foreach ($counts as $h => $count) {
                    $this->barLine(sprintf('%02d', $h), $count, $maximum);
                }
                break;

            case 'TIMELINE':
                $minutes = (int)$a[0];
                $width = $minutes * 60;
                [$first, $counts] = buckets(array_map(
                    static fn($r) => intdiv($r['seconds'], $width), $rows));
                $this->emit('TIMELINE', $minutes, count($counts));
                $maximum = max($counts);
                foreach ($counts as $i => $count) {
                    $this->barLine(interval_label(($first+$i)*$width), $count, $maximum);
                }
                break;

            case 'BANDWIDTH':
                $days = grouped($rows, static fn($r) => $r['date']);
                $total = sum_property($rows, 'bytes');
                $this->emit('BANDWIDTH', count($days), $total, bytes_text($total));
                ksort($days, SORT_STRING);
                foreach ($days as $date => $items) {
                    $bytes = sum_property($items, 'bytes');
                    $this->emit($date, count($items), $bytes, bytes_text($bytes));
                }
                break;

            case 'VISITORS':
                $first = [];
                foreach ($rows as $row) {
                    if (!isset($first[$row['ip']]) ||
                        strcmp($row['date'], $first[$row['ip']]) < 0) {
                        $first[$row['ip']] = $row['date'];
                    }
                }
                $days = grouped($rows, static fn($r) => $r['date']);
                $this->emit('VISITORS', count($days), count($first));
                ksort($days, SORT_STRING);
                foreach ($days as $date => $items) {
                    $ips = array_unique(field_values($items, 'ip'));
                    $new = 0;
                    foreach ($ips as $ip) if ($first[$ip] === $date) $new++;
                    $this->emit($date, 'unique', count($ips), 'new', $new,
                        'returning', count($ips) - $new);
                }
                break;

            case 'LATENCY':
                $label = $a === [] ? 'all' : normalize_path($a[0]);
                $selected = $a === [] ? $rows : array_values(array_filter(
                    $rows, static fn($r) => $r['path'] === $label));
                if ($selected === []) {
                    $this->emit('LATENCY', 'no records');
                    break;
                }
                $values = field_values($selected, 'latency');
                sort($values, SORT_NUMERIC);
                $count = count($values);
                $trim = intdiv($count, 10);
                $trimmed = array_slice($values, $trim, $count-2*$trim);
                $this->emit('LATENCY', $label, 'count', $count,
                    'min', $values[0], 'p50', percentile($values, 50),
                    'p90', percentile($values, 90), 'p99', percentile($values, 99),
                    'max', $values[$count-1],
                    'mean', decimal_value(array_sum($values), $count, 2),
                    'trimmed', decimal_value(array_sum($trimmed), count($trimmed), 2));
                break;

            case 'HISTOGRAM':
                $width = (int)$a[0];
                [$first, $counts] = buckets(array_map(
                    static fn($r) => intdiv($r['latency'], $width), $rows));
                $this->emit('HISTOGRAM', $width, count($counts));
                $maximum = max($counts);
                foreach ($counts as $i => $count) {
                    $lo = ($first+$i)*$width;
                    $this->barLine($lo . '-' . ($lo+$width-1), $count, $maximum);
                }
                break;

            case 'APDEX':
                $threshold = (int)$a[0];
                $overall = apdex_score($rows, $threshold);
                $this->emit('APDEX', $threshold, $overall['notation'], $overall['rating'],
                    'satisfied', $overall['satisfied'], 'tolerating',
                    $overall['tolerating'], 'frustrated', $overall['frustrated']);
                $paths = [];
                foreach (grouped($rows, static fn($r) => $r['path']) as $path => $items) {
                    $paths[] = ['path' => $path] + apdex_score($items, $threshold);
                }
                usort($paths, static function ($x, $y) {
                    $order = $x['points']*$y['total'] <=> $y['points']*$x['total'];
                    return $order ?: (($y['count'] <=> $x['count']) ?:
                        strcmp($x['path'], $y['path']));
                });
                foreach ($paths as $row) {
                    $this->emit($row['path'], $row['notation'], $row['rating'], $row['count']);
                }
                break;

            case 'ERRORS':
                $failed = count(array_filter($rows, static fn($r) => $r['status'] >= 400));
                $this->emit('ERRORS', $failed, 'of', count($rows),
                    percentage($failed, count($rows)));
                $paths = [];
                foreach (grouped($rows, static fn($r) => $r['path']) as $path => $items) {
                    $client = 0;
                    $server = 0;
                    foreach ($items as $row) {
                        if (intdiv($row['status'], 100) === 4) $client++;
                        if (intdiv($row['status'], 100) === 5) $server++;
                    }
                    if ($client+$server > 0) {
                        $paths[] = ['path'=>$path, 'count'=>count($items),
                            'client'=>$client, 'server'=>$server];
                    }
                }
                usort($paths, static function ($x, $y) {
                    $xf = $x['client'] + $x['server'];
                    $yf = $y['client'] + $y['server'];
                    return ($yf*$x['count'] <=> $xf*$y['count']) ?:
                        (($yf <=> $xf) ?: strcmp($x['path'], $y['path']));
                });
                foreach ($paths as $row) {
                    $this->emit($row['path'], $row['count'], $row['client'],
                        $row['server'], percentage(
                            $row['client']+$row['server'], $row['count']));
                }
                break;

            case 'SLOWEST':
                $endpointGroups = grouped($rows, static fn($r) =>
                    $r['method'] . "\x01" . $r['path']);
                $endpoints = [];
                foreach ($endpointGroups as $name => $items) {
                    [$method, $path] = explode("\x01", $name, 2);
                    $endpoints[] = ['method'=>$method, 'path'=>$path,
                        'count'=>count($items), 'sum'=>sum_property($items, 'latency'),
                        'maximum'=>max(field_values($items, 'latency'))];
                }
                usort($endpoints, static function ($x, $y) {
                    $n = $y['sum']*$x['count'] <=> $x['sum']*$y['count'];
                    if ($n !== 0) return $n;
                    $n = $y['maximum'] <=> $x['maximum'];
                    if ($n !== 0) return $n;
                    return strcmp($x['path'], $y['path']) ?:
                        strcmp($x['method'], $y['method']);
                });
                $limit = min((int)$a[0], count($endpoints));
                $this->emit('SLOWEST', $limit, 'of', count($endpoints));
                for ($i=0; $i<$limit; $i++) {
                    $row=$endpoints[$i];
                    $this->emit($i+1, $row['method'], $row['path'],
                        'count', $row['count'],
                        'avg', decimal_value($row['sum'], $row['count'], 2),
                        'max', $row['maximum']);
                }
                break;

            case 'SESSIONS':
                $ip = $a[0];
                $minutes = count($a)>1 ? (int)$a[1] : 30;
                $found = array_values(array_filter($rows,
                    static fn($r) => $r['ip'] === $ip));
                if ($found === []) {
                    $this->emit('SESSIONS', 'no records');
                    break;
                }
                $sessions = [[$found[0]]];
                for ($i=1; $i<count($found); $i++) {
                    $j = count($sessions)-1;
                    if ($found[$i]['seconds']-$found[$i-1]['seconds'] <= $minutes*60) {
                        $sessions[$j][] = $found[$i];
                    } else $sessions[] = [$found[$i]];
                }
                $duration = 0;
                foreach ($sessions as $session) {
                    $duration += $session[count($session)-1]['seconds']-$session[0]['seconds'];
                }
                $this->emit('SESSIONS', $ip, 'timeout', $minutes,
                    'count', count($sessions), 'requests', count($found),
                    'avg_duration', decimal_value($duration, count($sessions), 1),
                    'avg_requests', decimal_value(count($found), count($sessions), 1));
                foreach ($sessions as $i => $session) {
                    $first = $session[0];
                    $last = $session[count($session)-1];
                    $this->emit($i+1, $first['timestamp'], $last['timestamp'],
                        $last['seconds']-$first['seconds'], count($session),
                        count(array_unique(field_values($session, 'path'))));
                }
                break;

            case 'BURST':
                $length = (int)$a[0];
                $threshold = (int)$a[1];
                $groups = grouped(array_values(array_filter($rows,
                    static fn($r) => $r['status'] >= 400)), static fn($r) => $r['ip']);
                $peaks = [];
                foreach ($groups as $ip => $items) {
                    $window = window_peak($items, $length);
                    if ($window['count'] >= $threshold) {
                        $peaks[] = ['ip'=>$ip] + $window;
                    }
                }
                usort($peaks, static fn($x, $y) =>
                    ($y['count'] <=> $x['count']) ?: compare_ip($x['ip'], $y['ip']));
                $this->emit('BURST', $length, $threshold, count($peaks));
                foreach ($peaks as $p) {
                    $this->emit($p['ip'], $p['count'],
                        $p['start']['timestamp'], $p['end']['timestamp']);
                }
                break;

            case 'PEAK':
                $length = (int)$a[0];
                $peak = window_peak($rows, $length);
                $this->emit('PEAK', $length, $peak['count'],
                    $peak['start']['timestamp'], $peak['end']['timestamp']);
                break;

            case 'GAPS':
                $length = (int)$a[0];
                $gaps = [];
                for ($i=1; $i<count($rows); $i++) {
                    if ($rows[$i]['seconds']-$rows[$i-1]['seconds'] >= $length) {
                        $gaps[] = [$rows[$i-1], $rows[$i]];
                    }
                }
                $this->emit('GAPS', $length, count($gaps));
                foreach ($gaps as [$before, $after]) {
                    $this->emit($before['timestamp'], $after['timestamp'],
                        $after['seconds']-$before['seconds']);
                }
                break;

            case 'IP':
                $ip = $a[0];
                $found = array_values(array_filter($rows,
                    static fn($r) => $r['ip'] === $ip));
                if ($found === []) {
                    $this->emit('IP', 'no records');
                    break;
                }
                $paths = tallied(field_values($found, 'path'));
                $this->emit('IP', $ip, 'requests', count($found),
                    'bytes', sum_property($found, 'bytes'),
                    'errors', count(array_filter($found, static fn($r) => $r['status'] >= 400)),
                    'paths', count($paths));
                $this->emit('first', $found[0]['timestamp'], 'last',
                    $found[count($found)-1]['timestamp']);
                $methods = tallied(field_values($found, 'method'));
                $line = ['methods'];
                foreach (by_count($methods) as $method) {
                    $line[] = $method;
                    $line[] = $methods[$method];
                }
                $this->emit(...$line);
                $line = ['classes'];
                foreach (class_counts($found) as $i=>$count) {
                    $line[] = CLASSES[$i];
                    $line[] = $count;
                }
                $this->emit(...$line);
                foreach (array_slice(by_count($paths), 0, 3) as $path) {
                    $this->emit('path', $path, $paths[$path]);
                }
                break;

            case 'RANGE':
                $from = seconds_of($a[0], $a[1]);
                $to = seconds_of($a[2], $a[3]);
                require_condition($from <= $to, 'invalid range');
                $this->rangeStart = $from;
                $this->rangeEnd = $to;
                $this->startLabel = $a[0] . ' ' . $a[1];
                $this->endLabel = $a[2] . ' ' . $a[3];
                $this->emit('RANGE', $this->startLabel, $this->endLabel,
                    'active', count($this->selected()));
                break;

            case 'FILTER':
                $key = $a[0];
                $value = $key === 'PATH' ? normalize_path($a[1]) : $a[1];
                $this->conditions[$key] = $value;
                $this->emit('FILTER', $key, $value, 'active', count($this->selected()));
                break;

            case 'UNFILTER':
                $key = $a[0];
                if ($key === 'RANGE') {
                    require_condition($this->rangeStart !== null, 'not filtered');
                    $this->rangeStart = $this->rangeEnd = null;
                    $this->startLabel = $this->endLabel = null;
                } else {
                    require_condition($this->conditions[$key] !== null, 'not filtered');
                    $this->conditions[$key] = null;
                }
                $this->emit('UNFILTER', $key, 'active', count($this->selected()));
                break;

            case 'RESET':
                $this->rangeStart = $this->rangeEnd = null;
                $this->startLabel = $this->endLabel = null;
                foreach (FILTER_KEYS as $key) $this->conditions[$key] = null;
                $this->emit('RESET', 'active', count($this->selected()));
                break;

            case 'STATE':
                $parts = ['STATE', 'active', count($rows), 'range',
                    $this->rangeStart === null ? '-' :
                        $this->startLabel . ' ' . $this->endLabel];
                foreach (FILTER_KEYS as $key) {
                    $parts[] = strtolower($key);
                    $parts[] = $this->conditions[$key] ?? '-';
                }
                $this->emit(...$parts);
                break;
        }
    }
}

$lines = file('php://stdin', FILE_IGNORE_NEW_LINES);
$separator = array_search('---', $lines, true);
$end = array_search('END', $lines, true);
$analyzer = new LogAnalyzer(array_slice($lines, 0, $separator));
for ($i=$separator+1; $i<$end; $i++) $analyzer->execute($lines[$i]);
if ($analyzer->output !== []) {
    echo implode("\n", $analyzer->output), "\n";
}
