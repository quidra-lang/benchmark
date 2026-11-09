<?php
const CALENDARS = [
    'GREGORIAN', 'JULIAN', 'ISO', 'ISLAMIC', 'HEBREW', 'PERSIAN',
    'COPTIC', 'ETHIOPIC', 'FRENCH', 'MAYAN', 'JD', 'FIXED'
];
const YMD = ['GREGORIAN', 'JULIAN', 'ISLAMIC', 'HEBREW', 'PERSIAN', 'COPTIC', 'ETHIOPIC', 'FRENCH'];
const YEAR_CALENDARS = [...YMD, 'ISO'];
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const TZ = [
    'Imix', 'Ik', 'Akbal', 'Kan', 'Chicchan', 'Cimi', 'Manik', 'Lamat', 'Muluc', 'Oc',
    'Chuen', 'Eb', 'Ben', 'Ix', 'Men', 'Cib', 'Caban', 'Etznab', 'Cauac', 'Ahau'
];
const HB = [
    'Pop', 'Uo', 'Zip', 'Zotz', 'Tzec', 'Xul', 'Yaxkin', 'Mol', 'Chen', 'Yax',
    'Zac', 'Ceh', 'Mac', 'Kankin', 'Muan', 'Pax', 'Kayab', 'Cumku', 'Uayeb'
];
const DC = ['Primidi', 'Duodi', 'Tridi', 'Quartidi', 'Quintidi', 'Sextidi', 'Septidi', 'Octidi', 'Nonidi', 'Decadi'];
const FS = ['Vertu', 'Genie', 'Travail', 'Opinion', 'Recompenses', 'Revolution'];
const MAX_FIXED = 3652059;
const MONTH_NAMES = [
    'GREGORIAN' => [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ],
    'JULIAN' => [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ],
    'ISLAMIC' => [
        'Muharram', 'Safar', 'RabiI', 'RabiII', 'JumadaI', 'JumadaII',
        'Rajab', 'Shaban', 'Ramadan', 'Shawwal', 'DhuAlQidah', 'DhuAlHijjah'
    ],
    'HEBREW' => [
        'Tishri', 'Heshvan', 'Kislev', 'Tevet', 'Shevat', 'Adar',
        'Nisan', 'Iyyar', 'Sivan', 'Tammuz', 'Av', 'Elul'
    ],
    'PERSIAN' => [
        'Farvardin', 'Ordibehesht', 'Khordad', 'Tir', 'Mordad', 'Shahrivar',
        'Mehr', 'Aban', 'Azar', 'Dey', 'Bahman', 'Esfand'
    ],
    'COPTIC' => [
        'Thout', 'Paopi', 'Hathor', 'Koiak', 'Tobi', 'Meshir', 'Paremhat',
        'Parmouti', 'Pashons', 'Paoni', 'Epip', 'Mesori', 'Nasie'
    ],
    'ETHIOPIC' => [
        'Meskerem', 'Tekemt', 'Hedar', 'Tahsas', 'Ter', 'Yekatit', 'Megabit',
        'Miazia', 'Genbot', 'Sene', 'Hamle', 'Nehase', 'Pagume'
    ],
    'FRENCH' => [
        'Vendemiaire', 'Brumaire', 'Frimaire', 'Nivose', 'Pluviose', 'Ventose', 'Germinal',
        'Floreal', 'Prairial', 'Messidor', 'Thermidor', 'Fructidor', 'Sansculottides'
    ]
];
const HEBREW_LEAP_NAMES = [
    'Tishri', 'Heshvan', 'Kislev', 'Tevet', 'Shevat', 'AdarI', 'AdarII',
    'Nisan', 'Iyyar', 'Sivan', 'Tammuz', 'Av', 'Elul'
];

class DateValidationError extends Exception
{
}

class CommandError extends Exception
{
}

function require_valid(bool $condition): void
{
    if (!$condition) {
        throw new CommandError();
    }
}

function floor_div(int $n, int $d): int
{
    $quotient = intdiv($n, $d);
    if ($n < 0 && $n % $d !== 0) {
        --$quotient;
    }
    return $quotient;
}

function positive_mod(int $n, int $d): int
{
    return ($n % $d + $d) % $d;
}

function in_range(int $fixed): bool
{
    return $fixed >= 1 && $fixed <= MAX_FIXED;
}

function leap(string $calendar, int $year): bool
{
    if ($calendar === 'GREGORIAN') {
        return $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
    }
    if ($calendar === 'JULIAN') {
        return $year % 4 === 0;
    }
    if ($calendar === 'ISLAMIC') {
        return in_array(positive_mod($year, 30), [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29], true);
    }
    if ($calendar === 'HEBREW') {
        return positive_mod(7 * $year + 1, 19) < 7;
    }
    if ($calendar === 'PERSIAN') {
        $b = positive_mod($year - 474, 2820) + 474;
        return ($b + 38) * 682 % 2816 < 682;
    }
    if ($calendar === 'COPTIC' || $calendar === 'ETHIOPIC') {
        return positive_mod($year, 4) === 3;
    }
    if ($calendar === 'FRENCH') {
        return $year % 4 === 0 && !in_array(positive_mod($year, 400), [100, 200, 300], true) && $year % 4000 !== 0;
    }
    return intdiv(start('ISO', $year + 1) - start('ISO', $year), 7) === 53;
}

function months_before(int $year): int
{
    return floor_div(235 * $year - 234, 19);
}

function molad(int $year): array
{
    $quantity = 5604 + 765433 * months_before($year);
    $day = floor_div($quantity, 25920);
    $parts = positive_mod($quantity, 25920);
    $weekday = positive_mod($day - 1373427, 7);
    $rules = [];
    $postponed = $day;
    if ($parts >= 19440) {
        ++$postponed;
        $rules[] = 'ZAKEN';
    } elseif (!leap('HEBREW', $year) && $weekday === 2 && $parts >= 9924) {
        $postponed += 2;
        $rules[] = 'GATARAD';
    } elseif (leap('HEBREW', $year - 1) && $weekday === 1 && $parts >= 16789) {
        ++$postponed;
        $rules[] = 'BETUTAKPAT';
    }
    if (in_array(positive_mod($postponed - 1373427, 7), [0, 3, 5], true)) {
        ++$postponed;
        $rules[] = 'ADU';
    }
    return [$day, $parts, $postponed - 1373427, $rules];
}

function start(string $calendar, int $year): int
{
    $previous = $year - 1;
    if ($calendar === 'GREGORIAN') {
        return 365 * $previous + floor_div($previous, 4) - floor_div($previous, 100) + floor_div($previous, 400) + 1;
    }
    if ($calendar === 'JULIAN') {
        return 365 * $previous + floor_div($previous, 4) - 1;
    }
    if ($calendar === 'ISLAMIC') {
        return 227015 + 354 * $previous + floor_div(3 + 11 * $year, 30);
    }
    if ($calendar === 'HEBREW') {
        return molad($year)[2];
    }
    if ($calendar === 'PERSIAN') {
        $a = $year - 474;
        $b = positive_mod($a, 2820) + 474;
        return 226896 + 1029983 * floor_div($a, 2820) + 365 * ($b - 1) + floor_div(682 * $b - 110, 2816);
    }
    if ($calendar === 'COPTIC') {
        return 103605 + 365 * $previous + floor_div($year, 4);
    }
    if ($calendar === 'ETHIOPIC') {
        return 2796 + 365 * $previous + floor_div($year, 4);
    }
    if ($calendar === 'FRENCH') {
        return 654415 + 365 * $previous + floor_div($previous, 4) - floor_div($previous, 100)
            + floor_div($previous, 400) - floor_div($previous, 4000);
    }
    $januaryFour = start('GREGORIAN', $year) + 3;
    return $januaryFour - positive_mod($januaryFour - 1, 7);
}

function year_type(int $year): string
{
    return match (start('HEBREW', $year + 1) - start('HEBREW', $year)) {
        353, 383 => 'DEFICIENT',
        354, 384 => 'REGULAR',
        default => 'COMPLETE',
    };
}

function names(string $calendar, int $year): array
{
    if ($calendar === 'HEBREW' && leap($calendar, $year)) {
        return HEBREW_LEAP_NAMES;
    }
    return MONTH_NAMES[$calendar];
}

function lengths(string $calendar, int $year): array
{
    $extra = leap($calendar, $year) ? 1 : 0;
    if ($calendar === 'GREGORIAN' || $calendar === 'JULIAN') {
        return [31, 28 + $extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    }
    if ($calendar === 'ISLAMIC') {
        return [30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + $extra];
    }
    if ($calendar === 'PERSIAN') {
        return [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + $extra];
    }
    if (in_array($calendar, ['COPTIC', 'ETHIOPIC', 'FRENCH'], true)) {
        return [...array_fill(0, 12, 30), 5 + $extra];
    }
    $kind = year_type($year);
    $heshvan = $kind === 'COMPLETE' ? 30 : 29;
    $kislev = $kind === 'DEFICIENT' ? 29 : 30;
    if ($extra === 1) {
        return [30, $heshvan, $kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29];
    }
    return [30, $heshvan, $kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29];
}

function fixed_date(string $calendar, int $year, int $month, int $day): int
{
    if ($calendar === 'ISO') {
        return start($calendar, $year) + 7 * ($month - 1) + $day - 1;
    }
    return start($calendar, $year) + array_sum(array_slice(lengths($calendar, $year), 0, $month - 1)) + $day - 1;
}

function year_of(string $calendar, int $fixed): int
{
    if ($fixed < start($calendar, 1)) {
        return 0;
    }
    $low = 1;
    $high = 100000;
    while ($low + 1 < $high) {
        $middle = intdiv($low + $high, 2);
        if (start($calendar, $middle) <= $fixed) {
            $low = $middle;
        } else {
            $high = $middle;
        }
    }
    return $low;
}

function parts_of(string $calendar, int $fixed): ?array
{
    $year = year_of($calendar, $fixed);
    if ($year === 0) {
        return null;
    }
    $offset = $fixed - start($calendar, $year);
    if ($calendar === 'ISO') {
        return [$year, intdiv($offset, 7) + 1, $offset % 7 + 1];
    }
    foreach (lengths($calendar, $year) as $index => $days) {
        if ($offset < $days) {
            return [$year, $index + 1, $offset + 1];
        }
        $offset -= $days;
    }
    throw new LogicException('calendar year length');
}

function format_date(string $calendar, int $fixed): string
{
    if (!in_range($fixed)) {
        return 'OUT OF RANGE';
    }
    if (in_array($calendar, YEAR_CALENDARS, true)) {
        $parts = parts_of($calendar, $fixed);
        if ($parts === null) {
            return 'OUT OF RANGE';
        }
        if ($calendar === 'ISO') {
            return sprintf('%04d-W%02d-%d', ...$parts);
        }
        return sprintf('%04d-%02d-%02d', ...$parts);
    }
    if ($calendar === 'JD') {
        return (string) ($fixed + 1721425);
    }
    if ($calendar === 'FIXED') {
        return (string) $fixed;
    }
    $count = $fixed + 1137142;
    $longCount = [
        intdiv($count, 144000),
        intdiv($count, 7200) % 20,
        intdiv($count, 360) % 20,
        intdiv($count, 20) % 18,
        $count % 20
    ];
    $tzNumber = ($count + 3) % 13 + 1;
    $tzName = TZ[($count + 19) % 20];
    $haab = ($count + 348) % 365;
    return sprintf('%s %d %s %d %s', implode('.', $longCount), $tzNumber, $tzName, $haab % 20, HB[intdiv($haab, 20)]);
}

function parse_date(string $calendar, string $text): int
{
    if (in_array($calendar, YMD, true)) {
        if (preg_match('/^[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}$/D', $text) !== 1) {
            throw new DateValidationError('FORMAT');
        }
        [$year, $month, $day] = array_map('intval', explode('-', $text));
        if ($year === 0) {
            throw new DateValidationError('YEAR');
        }
        $days = lengths($calendar, $year);
        if ($month < 1 || $month > count($days)) {
            throw new DateValidationError('MONTH');
        }
        if ($day < 1 || $day > $days[$month - 1]) {
            throw new DateValidationError('DAY');
        }
        $fixed = fixed_date($calendar, $year, $month, $day);
    } elseif ($calendar === 'ISO') {
        if (preg_match('/^[0-9]{1,5}-W[0-9]{1,2}-[0-9]$/D', $text) !== 1) {
            throw new DateValidationError('FORMAT');
        }
        [$yearText, $weekText, $dayText] = explode('-', $text);
        $year = (int) $yearText;
        $week = (int) substr($weekText, 1);
        $day = (int) $dayText;
        if ($year === 0) {
            throw new DateValidationError('YEAR');
        }
        $weeks = intdiv(start($calendar, $year + 1) - start($calendar, $year), 7);
        if ($week < 1 || $week > $weeks) {
            throw new DateValidationError('WEEK');
        }
        if ($day < 1 || $day > 7) {
            throw new DateValidationError('DAY');
        }
        $fixed = fixed_date($calendar, $year, $week, $day);
    } elseif ($calendar === 'MAYAN') {
        if (preg_match('/^[0-9]{1,2}(?:\.[0-9]{1,2}){4}$/D', $text) !== 1) {
            throw new DateValidationError('FORMAT');
        }
        [$b, $k, $t, $u, $n] = array_map('intval', explode('.', $text));
        if ($k > 19 || $t > 19 || $u > 17 || $n > 19) {
            throw new DateValidationError('FIELD');
        }
        $fixed = ((($b * 20 + $k) * 20 + $t) * 18 + $u) * 20 + $n - 1137142;
    } else {
        if (preg_match('/^-?[0-9]{1,8}$/D', $text) !== 1) {
            throw new DateValidationError('FORMAT');
        }
        $fixed = (int) $text - ($calendar === 'JD' ? 1721425 : 0);
    }
    if (!in_range($fixed)) {
        throw new DateValidationError('RANGE');
    }
    return $fixed;
}

function month_index(string $calendar, int $year): int
{
    if ($calendar === 'HEBREW') {
        return months_before($year);
    }
    $count = in_array($calendar, ['COPTIC', 'ETHIOPIC', 'FRENCH'], true) ? 13 : 12;
    return $count * ($year - 1);
}

function shift(string $calendar, int $fixed, int $years, int $months): ?int
{
    [$year, $month, $day] = parts_of($calendar, $fixed);
    $targetYear = $year + $years;
    if ($calendar === 'ISO') {
        if ($targetYear < 1 || $targetYear > 99999) {
            return null;
        }
        $weeks = intdiv(start($calendar, $targetYear + 1) - start($calendar, $targetYear), 7);
        return fixed_date($calendar, $targetYear, min($month, $weeks), $day);
    }
    if ($calendar === 'HEBREW') {
        $oldName = names($calendar, $year)[$month - 1];
        $newNames = names($calendar, $targetYear);
        if (!in_array($oldName, $newNames, true)) {
            $oldName = $oldName === 'Adar' ? 'AdarII' : 'Adar';
        }
        $month = array_search($oldName, $newNames, true) + 1;
    }
    $absolute = month_index($calendar, $targetYear) + $month - 1 + $months;
    if ($calendar === 'HEBREW') {
        $finalYear = floor_div(19 * $absolute + 234, 235);
        while (month_index($calendar, $finalYear) > $absolute) {
            --$finalYear;
        }
        while (month_index($calendar, $finalYear + 1) <= $absolute) {
            ++$finalYear;
        }
    } else {
        $finalYear = floor_div($absolute, count(names($calendar, $targetYear))) + 1;
    }
    if ($finalYear < 1 || $finalYear > 99999) {
        return null;
    }
    $finalMonth = $absolute - month_index($calendar, $finalYear) + 1;
    $finalDay = min($day, lengths($calendar, $finalYear)[$finalMonth - 1]);
    return fixed_date($calendar, $finalYear, $finalMonth, $finalDay);
}

function month_bounds(string $calendar, int $year, int $month): array
{
    $days = lengths($calendar, $year);
    if ($month < 1 || $month > count($days)) {
        throw new DateValidationError('MONTH');
    }
    $first = fixed_date($calendar, $year, $month, 1);
    return [$first, $first + $days[$month - 1] - 1];
}

function new_years(string $calendar, int $first, int $last): array
{
    $year = max(1, year_of($calendar, $first));
    while (start($calendar, $year) < $first) {
        ++$year;
    }
    $result = [];
    while (start($calendar, $year) <= $last) {
        $result[] = [$year, start($calendar, $year)];
        ++$year;
    }
    return $result;
}

function easter(int $year, string $calendar): array
{
    $golden = $year % 19;
    if ($calendar === 'GREGORIAN') {
        $century = intdiv($year, 100) + 1;
        $epact = positive_mod(14 + 11 * $golden - intdiv(3 * $century, 4) + intdiv(5 + 8 * $century, 25), 30);
        if ($epact === 0 || ($epact === 1 && $golden > 10)) {
            ++$epact;
        }
    } else {
        $epact = (14 + 11 * $golden) % 30;
    }
    $moon = fixed_date($calendar, $year, 4, 19) - $epact;
    $sunday = $moon + 7 - positive_mod($moon, 7);
    $index = positive_mod(-start($calendar, $year), 7);
    $letters = 'ABCDEFG'[$index];
    if (leap($calendar, $year)) {
        $letters .= 'ABCDEFG'[positive_mod($index - 1, 7)];
    }
    return [$epact, $letters, $moon, $sunday];
}

const HOLIDAYS = [
    ['Christmas', 'GREGORIAN', 'December', 25],
    ['OrthodoxChristmas', 'JULIAN', 'December', 25],
    ['RoshHashanah', 'HEBREW', 'Tishri', 1],
    ['YomKippur', 'HEBREW', 'Tishri', 10],
    ['Sukkot', 'HEBREW', 'Tishri', 15],
    ['Hanukkah', 'HEBREW', 'Kislev', 25],
    ['Purim', 'HEBREW', 'Adar', 14],
    ['Passover', 'HEBREW', 'Nisan', 15],
    ['Shavuot', 'HEBREW', 'Sivan', 6],
    ['IslamicNewYear', 'ISLAMIC', 'Muharram', 1],
    ['Ashura', 'ISLAMIC', 'Muharram', 10],
    ['Mawlid', 'ISLAMIC', 'RabiI', 12],
    ['RamadanStart', 'ISLAMIC', 'Ramadan', 1],
    ['EidAlFitr', 'ISLAMIC', 'Shawwal', 1],
    ['EidAlAdha', 'ISLAMIC', 'DhuAlHijjah', 10],
    ['Nowruz', 'PERSIAN', 'Farvardin', 1],
    ['SizdahBedar', 'PERSIAN', 'Farvardin', 13],
    ['Yalda', 'PERSIAN', 'Azar', 30],
    ['Nayrouz', 'COPTIC', 'Thout', 1],
    ['CopticChristmas', 'COPTIC', 'Koiak', 29],
    ['Enkutatash', 'ETHIOPIC', 'Meskerem', 1],
    ['Meskel', 'ETHIOPIC', 'Meskerem', 17],
    ['Timkat', 'ETHIOPIC', 'Ter', 11],
    ['RepublicDay', 'FRENCH', 'Vendemiaire', 1],
    ['RevolutionDay', 'FRENCH', 'Sansculottides', 6]
];

function holiday_lines(int $year): array
{
    $first = start('GREGORIAN', $year);
    $last = start('GREGORIAN', $year + 1) - 1;
    $gregorianEaster = easter($year, 'GREGORIAN')[3];
    $orthodoxEaster = easter($year, 'JULIAN')[3];
    $entries = [];
    $movable = [['AshWednesday', -46], ['GoodFriday', -2], ['Easter', 0], ['Ascension', 39], ['Pentecost', 49]];
    foreach ($movable as $order => [$name, $offset]) {
        $entries[] = [$gregorianEaster + $offset, $order, $name, 'GREGORIAN'];
    }
    $entries[] = [$orthodoxEaster, 5, 'OrthodoxEaster', 'JULIAN'];
    foreach (HOLIDAYS as $index => [$name, $calendar, $monthName, $day]) {
        $candidateYear = max(1, year_of($calendar, $first));
        while (start($calendar, $candidateYear) <= $last) {
            $actualName = $monthName;
            if ($calendar === 'HEBREW' && $monthName === 'Adar' && leap($calendar, $candidateYear)) {
                $actualName = 'AdarII';
            }
            $month = array_search($actualName, names($calendar, $candidateYear), true) + 1;
            if ($day <= lengths($calendar, $candidateYear)[$month - 1]) {
                $fixed = fixed_date($calendar, $candidateYear, $month, $day);
                if ($first <= $fixed && $fixed <= $last) {
                    $entries[] = [$fixed, $index + 6, $name, $calendar];
                }
            }
            ++$candidateYear;
        }
    }
    usort($entries, fn($a, $b) => [$a[0], $a[1]] <=> [$b[0], $b[1]]);
    $lines = [];
    foreach ($entries as [$fixed, , $name, $calendar]) {
        $lines[] = sprintf('%s %s %s %s %s', format_date('GREGORIAN', $fixed), WEEKDAYS[$fixed % 7], $name, $calendar, format_date($calendar, $fixed));
    }
    return $lines;
}

const ARITY = [
    'CONVERT' => 4, 'ALL' => 2, 'VALID' => 2, 'WEEKDAY' => 2, 'INFO' => 2,
    'LEAP' => 2, 'MONTHS' => 2, 'MONTHCAL' => 3, 'NTH' => 5, 'NEWYEAR' => 2,
    'DIFF' => 4, 'COUNT' => 4, 'ADD' => 4, 'SPAN' => 3, 'EASTER' => 2,
    'COMPUTUS' => 2, 'PASSOVER' => 1, 'HOLIDAYS' => 1, 'MOLAD' => 1, 'ROUND' => 6
];

function valid_year(string $text): bool
{
    return preg_match('/^[0-9]{1,5}$/D', $text) === 1 && (int) $text >= 1;
}

function validate_arguments(string $command, array $args): void
{
    if ($command === 'EASTER' || $command === 'COMPUTUS') {
        require_valid(valid_year($args[0]) && in_array($args[1], ['GREGORIAN', 'JULIAN'], true));
        return;
    }
    if (in_array($command, ['PASSOVER', 'HOLIDAYS', 'MOLAD'], true)) {
        require_valid(valid_year($args[0]));
        return;
    }
    $calendar = $args[0];
    $allowed = match ($command) {
        'INFO', 'MONTHS', 'MONTHCAL', 'NTH', 'SPAN' => YMD,
        'LEAP', 'NEWYEAR' => YEAR_CALENDARS,
        default => CALENDARS,
    };
    require_valid(in_array($calendar, $allowed, true));
    if ($command === 'CONVERT') {
        require_valid($args[2] === 'TO' && in_array($args[3], CALENDARS, true));
    } elseif ($command === 'DIFF') {
        require_valid(in_array($args[2], CALENDARS, true));
    } elseif (in_array($command, ['LEAP', 'MONTHS', 'MONTHCAL', 'NTH', 'NEWYEAR'], true)) {
        require_valid(valid_year($args[1]));
        if ($command === 'MONTHCAL' || $command === 'NTH') {
            require_valid(preg_match('/^[0-9]{1,2}$/D', $args[2]) === 1);
        }
        if ($command === 'NTH') {
            require_valid(in_array($args[3], ['1', '2', '3', '4', '5', 'LAST'], true));
            require_valid(in_array($args[4], WEEKDAYS, true));
        }
    } elseif ($command === 'COUNT') {
        require_valid(in_array($args[3], WEEKDAYS, true));
    } elseif ($command === 'ADD') {
        require_valid(preg_match('/^-?[0-9]{1,7}$/D', $args[2]) === 1);
        require_valid(in_array($args[3], ['DAYS', 'WEEKS', 'MONTHS', 'YEARS'], true));
        if ($args[3] === 'MONTHS') {
            require_valid(in_array($calendar, YMD, true));
        }
        if ($args[3] === 'YEARS') {
            require_valid(in_array($calendar, YEAR_CALENDARS, true));
        }
    } elseif ($command === 'ROUND') {
        require_valid(preg_match('/^[0-9]{1,2}$/D', $args[2]) === 1);
        require_valid((int) $args[2] >= 1 && (int) $args[2] <= 13 && in_array($args[3], TZ, true));
        require_valid(preg_match('/^[0-9]{1,2}$/D', $args[4]) === 1);
        require_valid(in_array($args[5], HB, true));
        require_valid((int) $args[4] <= ($args[5] === 'Uayeb' ? 4 : 19));
    }
}

function calendar_lines(string $calendar, int $year, int $month): array
{
    [$first, $last] = month_bounds($calendar, $year, $month);
    if (!in_range($first) || !in_range($last)) {
        return ['OUT OF RANGE'];
    }
    $title = sprintf('%s %d (%s to %s)', names($calendar, $year)[$month - 1], $year,
        format_date('GREGORIAN', $first), format_date('GREGORIAN', $last));
    $result = [$title, 'Mo Tu We Th Fr Sa Su'];
    for ($cursor = $first - ($first - 1) % 7; $cursor <= $last; $cursor += 7) {
        $fields = [];
        for ($fixed = $cursor; $fixed < $cursor + 7; ++$fixed) {
            $fields[] = $first <= $fixed && $fixed <= $last ? sprintf('%2d', $fixed - $first + 1) : '  ';
        }
        $result[] = rtrim(implode(' ', $fields));
    }
    return $result;
}

function span_text(string $calendar, int $first, int $last): string
{
    $negative = $first > $last;
    if ($negative) {
        [$first, $last] = [$last, $first];
    }
    $startYear = parts_of($calendar, $first)[0];
    $endYear = parts_of($calendar, $last)[0];
    $low = 0;
    $high = $endYear - $startYear + 2;
    while ($low + 1 < $high) {
        $middle = intdiv($low + $high, 2);
        $shifted = shift($calendar, $first, $middle, 0);
        if ($shifted !== null && $shifted <= $last) {
            $low = $middle;
        } else {
            $high = $middle;
        }
    }
    $years = $low;
    $low = 0;
    $high = 32;
    while ($low + 1 < $high) {
        $middle = intdiv($low + $high, 2);
        $shifted = shift($calendar, $first, $years, $middle);
        if ($shifted !== null && $shifted <= $last) {
            $low = $middle;
        } else {
            $high = $middle;
        }
    }
    $months = $low;
    $days = $last - shift($calendar, $first, $years, $months);
    return sprintf('%s%dy %dm %dd', $negative ? '-' : '', $years, $months, $days);
}

function round_date(string $calendar, int $fixed, int $number, string $tzName, int $day, string $month): string
{
    $targetTz = array_search($tzName, TZ, true);
    $targetHaab = array_search($month, HB, true) * 20 + $day;
    $candidate = $fixed;
    while (true) {
        $count = $candidate + 1137142;
        if (($count + 3) % 13 + 1 === $number && ($count + 19) % 20 === $targetTz) {
            break;
        }
        ++$candidate;
    }
    while ($candidate <= $fixed + 18979) {
        if (($candidate + 1137142 + 348) % 365 === $targetHaab) {
            return format_date($calendar, $candidate);
        }
        $candidate += 260;
    }
    return 'NONE';
}

function execute(string $command, array $args): array
{
    validate_arguments($command, $args);
    if ($command === 'EASTER' || $command === 'COMPUTUS') {
        $year = (int) $args[0];
        if ($year > 9999) {
            return ['OUT OF RANGE'];
        }
        $kind = $args[1];
        [$epact, $letters, $moon, $sunday] = easter($year, $kind);
        if ($command === 'EASTER') {
            return [format_date('GREGORIAN', $sunday)];
        }
        return [sprintf('golden=%d epact=%d letters=%s moon=%s easter=%s', $year % 19 + 1, $epact, $letters,
            format_date($kind, $moon), format_date($kind, $sunday))];
    }
    if (in_array($command, ['PASSOVER', 'HOLIDAYS', 'MOLAD'], true)) {
        $year = (int) $args[0];
        if ($command === 'MOLAD') {
            [$day, $parts, $fixed, $rules] = molad($year);
            if (!in_range($fixed)) {
                return ['OUT OF RANGE'];
            }
            $applied = $rules === [] ? 'NONE' : implode('+', $rules);
            return [sprintf('%s %dh %dp %s %s %s', WEEKDAYS[positive_mod($day - 1373427, 7)], intdiv($parts, 1080),
                $parts % 1080, $applied, WEEKDAYS[$fixed % 7], format_date('GREGORIAN', $fixed))];
        }
        if ($year > 9999) {
            return ['OUT OF RANGE'];
        }
        if ($command === 'HOLIDAYS') {
            return holiday_lines($year);
        }
        $hebrewYear = $year + 3760;
        $month = array_search('Nisan', names('HEBREW', $hebrewYear), true) + 1;
        $fixed = fixed_date('HEBREW', $hebrewYear, $month, 15);
        return [format_date('GREGORIAN', $fixed) . ' ' . WEEKDAYS[$fixed % 7]];
    }
    $calendar = $args[0];
    if (in_array($command, ['LEAP', 'MONTHS', 'MONTHCAL', 'NTH', 'NEWYEAR'], true)) {
        $year = (int) $args[1];
        if ($command === 'LEAP') {
            $text = (leap($calendar, $year) ? 'YES' : 'NO') . ' ' . (start($calendar, $year + 1) - start($calendar, $year));
            if ($calendar === 'HEBREW') {
                $text .= ' ' . year_type($year);
            }
            return [$text];
        }
        if ($command === 'MONTHS') {
            $items = array_map(fn($name, $days) => "$name=$days", names($calendar, $year), lengths($calendar, $year));
            return [implode(' ', $items)];
        }
        if ($command === 'NEWYEAR') {
            if ($year > 9999) {
                return ['OUT OF RANGE'];
            }
            $entries = new_years($calendar, start('GREGORIAN', $year), start('GREGORIAN', $year + 1) - 1);
            if ($entries === []) {
                return ['NONE'];
            }
            return [implode(' ', array_map(fn($entry) => $entry[0] . ':' . format_date('GREGORIAN', $entry[1]), $entries))];
        }
        $month = (int) $args[2];
        if ($command === 'MONTHCAL') {
            return calendar_lines($calendar, $year, $month);
        }
        [$first, $last] = month_bounds($calendar, $year, $month);
        $weekday = array_search($args[4], WEEKDAYS, true);
        if ($args[3] === 'LAST') {
            $fixed = $last - positive_mod($last - $weekday, 7);
        } else {
            $fixed = $first + positive_mod($weekday - $first, 7) + 7 * ((int) $args[3] - 1);
        }
        return [$fixed > $last ? 'NONE' : format_date($calendar, $fixed)];
    }
    if ($command === 'VALID') {
        try {
            $fixed = parse_date($calendar, $args[1]);
        } catch (DateValidationError $error) {
            return ['NO ' . $error->getMessage()];
        }
        return ['YES ' . format_date($calendar, $fixed)];
    }
    $first = parse_date($calendar, $args[1]);
    if ($command === 'DIFF') {
        $last = parse_date($args[2], $args[3]);
        return [(string) ($last - $first)];
    }
    if ($command === 'COUNT' || $command === 'SPAN') {
        $last = parse_date($calendar, $args[2]);
        if ($command === 'SPAN') {
            return [span_text($calendar, $first, $last)];
        }
        $low = min($first, $last);
        $high = max($first, $last);
        $occurrence = $low + positive_mod(array_search($args[3], WEEKDAYS, true) - $low, 7);
        return [(string) ($occurrence > $high ? 0 : intdiv($high - $occurrence, 7) + 1)];
    }
    if ($command === 'CONVERT') {
        return [format_date($args[3], $first)];
    }
    if ($command === 'WEEKDAY') {
        return [WEEKDAYS[$first % 7]];
    }
    if ($command === 'ALL') {
        $result = [];
        foreach (CALENDARS as $target) {
            $text = format_date($target, $first);
            if (in_array($target, YMD, true) && $text !== 'OUT OF RANGE') {
                [$year, $month] = parts_of($target, $first);
                $text .= ' ' . names($target, $year)[$month - 1];
            }
            $result[] = "$target $text";
        }
        return $result;
    }
    if ($command === 'INFO') {
        [$year, $month, $day] = parts_of($calendar, $first);
        $weekday = WEEKDAYS[$first % 7];
        if ($calendar === 'FRENCH') {
            $weekday = $month <= 12 ? DC[($day - 1) % 10] : FS[$day - 1];
        }
        $ordinal = $first - start($calendar, $year) + 1;
        $length = start($calendar, $year + 1) - start($calendar, $year);
        return [sprintf('%s %d %s %d day=%d/%d', $weekday, $day, names($calendar, $year)[$month - 1], $year, $ordinal, $length)];
    }
    if ($command === 'ROUND') {
        return [round_date($calendar, $first, (int) $args[2], $args[3], (int) $args[4], $args[5])];
    }
    $amount = (int) $args[2];
    $result = match ($args[3]) {
        'DAYS' => $first + $amount,
        'WEEKS' => $first + 7 * $amount,
        'YEARS' => shift($calendar, $first, $amount, 0),
        default => shift($calendar, $first, 0, $amount),
    };
    return [$result === null ? 'OUT OF RANGE' : format_date($calendar, $result)];
}

$count = (int) fgets(STDIN);
$output = [];
for ($index = 0; $index < $count; ++$index) {
    $args = explode(' ', rtrim(fgets(STDIN), "\r\n"));
    $command = array_shift($args);
    if (!array_key_exists($command, ARITY) || count($args) !== ARITY[$command]) {
        $output[] = 'INVALID COMMAND';
        continue;
    }
    try {
        array_push($output, ...execute($command, $args));
    } catch (CommandError) {
        $output[] = 'INVALID COMMAND';
    } catch (DateValidationError $error) {
        $output[] = $error->getMessage() === 'RANGE' ? 'OUT OF RANGE' : 'INVALID DATE';
    }
}
echo implode("\n", $output), "\n";
