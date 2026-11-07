<?php
declare(strict_types=1);

namespace MailThreads;

const WEEKDAYS = ['mon' => 0, 'tue' => 1, 'wed' => 2, 'thu' => 3, 'fri' => 4, 'sat' => 5, 'sun' => 6];
const MONTHS = ['jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4, 'may' => 5, 'jun' => 6, 'jul' => 7, 'aug' => 8, 'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12];
const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const NAMED_ZONES = ['ut' => 0, 'gmt' => 0, 'z' => 0, 'est' => -300, 'edt' => -240, 'cst' => -360, 'cdt' => -300, 'mst' => -420, 'mdt' => -360, 'pst' => -480, 'pdt' => -420];
final class DateError extends \RuntimeException {}

function isLeap(int $year): bool { return $year % 4 === 0 && $year % 100 !== 0 || $year % 400 === 0; }
function daysInMonth(int $year, int $month): int { return $month === 2 && isLeap($year) ? 29 : MONTH_DAYS[$month - 1]; }
function daysInYear(int $year): int { return isLeap($year) ? 366 : 365; }
function hasDigits(string $text, array $lengths): bool
{
    return in_array(strlen($text), $lengths, true) && preg_match('/\A[0-9]+\z/', $text) === 1;
}

function parseDate(string $value): int
{
    $text = removeComments($value);
    if ($text === null) {
        throw new DateError('bad Date syntax');
    }
    $tokens = splitWords(str_replace(',', ' , ', $text));
    $weekday = null;
    if (count($tokens) >= 3 && array_key_exists(strtolower($tokens[0]), WEEKDAYS) && $tokens[1] === ',') {
        $weekday = WEEKDAYS[strtolower($tokens[0])];
        $tokens = array_slice($tokens, 2);
    }
    if (count($tokens) !== 5) {
        throw new DateError('bad Date syntax');
    }
    [$dayText, $monthText, $yearText, $timeText, $zoneText] = $tokens;
    $pieces = explode(':', $timeText);
    $numericZone = preg_match('/\A[+-][0-9]{4}\z/', $zoneText) === 1;
    if (!hasDigits($dayText, [1, 2]) || !array_key_exists(strtolower($monthText), MONTHS) || !hasDigits($yearText, [2, 4])
        || !in_array(count($pieces), [2, 3], true) || !$numericZone && !array_key_exists(strtolower($zoneText), NAMED_ZONES)) {
        throw new DateError('bad Date syntax');
    }
    foreach ($pieces as $piece) {
        if (!hasDigits($piece, [2])) {
            throw new DateError('bad Date syntax');
        }
    }
    $day = (int)$dayText;
    $month = MONTHS[strtolower($monthText)];
    $year = (int)$yearText;
    if (strlen($yearText) === 2) {
        $year += $year < 50 ? 2000 : 1900;
    }
    $hour = (int)$pieces[0];
    $minute = (int)$pieces[1];
    $second = isset($pieces[2]) ? (int)$pieces[2] : 0;
    if ($numericZone) {
        $zoneHour = (int)substr($zoneText, 1, 2);
        $zoneMinute = (int)substr($zoneText, 3, 2);
        if ($zoneHour > 23 || $zoneMinute > 59) {
            throw new DateError('Date out of range');
        }
        $offset = ($zoneHour * 60 + $zoneMinute) * ($zoneText[0] === '-' ? -1 : 1);
    } else {
        $offset = NAMED_ZONES[strtolower($zoneText)];
    }
    if ($year < 1970 || $year > 2099 || $day < 1 || $day > daysInMonth($year, $month) || $hour > 23 || $minute > 59 || $second > 59) {
        throw new DateError('Date out of range');
    }
    $days = $day - 1;
    for ($current = 1970; $current < $year; $current++) {
        $days += daysInYear($current);
    }
    for ($current = 1; $current < $month; $current++) {
        $days += daysInMonth($year, $current);
    }
    $seconds = $days * 86400 + $hour * 3600 + $minute * 60 + $second - $offset * 60;
    if ($seconds < 0) {
        throw new DateError('Date out of range');
    }
    if ($weekday !== null && ($days + 3) % 7 !== $weekday) {
        throw new DateError('Date weekday mismatch');
    }
    return $seconds;
}

function formatUtc(int $seconds): string
{
    $days = intdiv($seconds, 86400);
    $rest = $seconds % 86400;
    $year = 1970;
    while ($days >= daysInYear($year)) {
        $days -= daysInYear($year);
        $year++;
    }
    $month = 1;
    while ($days >= daysInMonth($year, $month)) {
        $days -= daysInMonth($year, $month);
        $month++;
    }
    return sprintf('%04d-%02d-%02d %02d:%02d:%02d', $year, $month, $days + 1, intdiv($rest, 3600), intdiv($rest % 3600, 60), $rest % 60);
}
