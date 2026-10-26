<?php
declare(strict_types=1);

namespace TimezoneRules;

const MIN_YEAR = 1800;
const MAX_YEAR = 2099;

final class FieldError extends \Exception {}

final class UntilSpec
{
    public function __construct(public string $yearText, public string $monthText, public string $dayText, public int $time, public string $timeType, public int $value) {}
}

function lineContent(string $raw): string { return rtrim(explode('#', $raw, 2)[0], ' '); }
function isContinuation(string $content): bool { return str_starts_with($content, ' '); }
function splitFields(string $content): array { return preg_split('/ +/', trim($content, ' ')); }
function isNumber(string $text, int $minimum, int $maximum): bool { return strlen($text) >= $minimum && strlen($text) <= $maximum && preg_match('/\A[0-9]+\z/', $text) === 1; }

function hmsValue(string $text, int $maxParts = 3): ?int
{
    $parts = explode(':', $text);
    if (count($parts) > $maxParts || !isNumber($parts[0], 1, 2)) {
        return null;
    }
    $value = (int)$parts[0] * 3600;
    for ($index = 1; $index < count($parts); $index++) {
        if (!isNumber($parts[$index], 2, 2) || (int)$parts[$index] > 59) {
            return null;
        }
        $value += (int)$parts[$index] * ($index === 1 ? 60 : 1);
    }
    return $value;
}

function parseYear(string $text): int
{
    if (!isNumber($text, 4, 4) || (int)$text < 1800 || (int)$text > 2099) {
        throw new FieldError('bad year');
    }
    return (int)$text;
}

function parseTo(string $text, int $fromYear): int
{
    if ($text === 'only') {
        return $fromYear;
    }
    if ($text === 'max') {
        return 2099;
    }
    if (!isNumber($text, 4, 4) || (int)$text < $fromYear || (int)$text > 2099) {
        throw new FieldError('bad year');
    }
    return (int)$text;
}

function parseMonth(string $text): int
{
    $index = array_search($text, MONTH_NAMES, true);
    if ($index === false) {
        throw new FieldError('bad month');
    }
    return $index + 1;
}

function parseWeekday(string $text): int
{
    $index = array_search($text, WEEKDAY_NAMES, true);
    if ($index === false) {
        throw new FieldError('bad day spec');
    }
    return $index;
}

function parseDayOfMonth(string $text, int $month): int
{
    if (!isNumber($text, 1, 2) || $text[0] === '0' || (int)$text > COMMON_MONTH_DAYS[$month - 1]) {
        throw new FieldError('bad day spec');
    }
    return (int)$text;
}

function parseDaySpec(string $text, int $month): DaySpec
{
    if (str_starts_with($text, 'last')) {
        return new DaySpec('last', parseWeekday(substr($text, 4)), 0);
    }
    foreach ([['>=', 'after'], ['<=', 'before']] as [$operator, $kind]) {
        $position = strpos($text, $operator);
        if ($position !== false) {
            $weekday = parseWeekday(substr($text, 0, $position));
            $day = parseDayOfMonth(substr($text, $position + 2), $month);
            return new DaySpec($kind, $weekday, $day);
        }
    }
    return new DaySpec('day', 0, parseDayOfMonth($text, $month));
}

function parseTime(string $text): array
{
    $type = 'w';
    $suffix = substr($text, -1);
    if (in_array($suffix, ['w', 's', 'u'], true)) {
        $type = $suffix;
        $text = substr($text, 0, -1);
    }
    $value = hmsValue($text);
    if ($value === null || $value > 86400) {
        throw new FieldError('bad time');
    }
    return [$value, $type];
}

function parseSave(string $text): int
{
    $value = hmsValue($text, 2);
    if ($value === null || $value > 7200) {
        throw new FieldError('bad save');
    }
    return $value;
}

function parseLetter(string $text): string
{
    if ($text === '-') {
        return '';
    }
    if (preg_match('/\A[A-Z]{1,5}\z/', $text) !== 1) {
        throw new FieldError('bad letter');
    }
    return $text;
}

function parseStdoff(string $text): int
{
    $sign = 1;
    if (str_starts_with($text, '-')) {
        $sign = -1;
        $text = substr($text, 1);
    }
    $value = hmsValue($text);
    if ($value === null || $value >= 57600) {
        throw new FieldError('bad offset');
    }
    return $sign * $value;
}

function checkFormat(string $text, bool $usesRuleSet): void
{
    $placeholders = substr_count($text, '%s');
    $slashes = substr_count($text, '/');
    $valid = preg_match('/\A[A-Za-z0-9+%\/-]+\z/', $text) === 1 && substr_count($text, '%') === $placeholders
        && $placeholders <= 1 && $slashes <= 1 && !($placeholders > 0 && $slashes > 0) && ($usesRuleSet || $placeholders === 0);
    if ($slashes === 1) {
        $valid = $valid && !str_starts_with($text, '/') && !str_ends_with($text, '/');
    }
    if (!$valid) {
        throw new FieldError('bad format');
    }
}

function parseUntil(array $fields): UntilSpec
{
    $year = parseYear($fields[0]);
    $monthText = $fields[1] ?? 'Jan';
    $month = parseMonth($monthText);
    $dayText = $fields[2] ?? '1';
    $day = parseDaySpec($dayText, $month);
    [$time, $timeType] = isset($fields[3]) ? parseTime($fields[3]) : [0, 'w'];
    return new UntilSpec($fields[0], $monthText, $dayText, $time, $timeType, $day->value($year, $month) * 86400 + $time);
}
