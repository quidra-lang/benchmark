<?php
require __DIR__ . '/dates_calendar.php';
require __DIR__ . '/daycount.php';
require __DIR__ . '/schedule.php';
require __DIR__ . '/pricing.php';
require __DIR__ . '/curve.php';

const BOND_TYPES = ['FIXED', 'ZERO', 'AMORT', 'FRN'];
const FREQUENCIES = [1, 2, 4, 12];
const OPTION_KEYS = ['FIXED' => ['EOM', 'LONG', 'CALL'], 'ZERO' => ['EOM', 'LONG'], 'AMORT' => ['EOM', 'LONG', 'SINK'], 'FRN' => ['EOM', 'LONG', 'LAG', 'CAP', 'FLOOR']];
const BUCKETS = ['0-1Y', '1-3Y', '3-5Y', '5-10Y', '10Y+'];
class InputError extends RuntimeException {}

function round_half_up(int $a, int $b): int { return intdiv(2 * $a + $b, 2 * $b); }
function hundredths(int $value): string { return ($value < 0 ? '-' : '') . intdiv($value < 0 ? -$value : $value, 100) . '.' . sprintf('%02d', ($value < 0 ? -$value : $value) % 100); }
function decimals(float $value, int $digits): string {
    $scale = 1; for ($index = 0; $index < $digits; $index++) $scale *= 10;
    $rounded = (int)(($value < 0 ? -$value : $value) * $scale + 0.5);
    return ($value < 0 && $rounded !== 0 ? '-' : '') . intdiv($rounded, $scale) . '.' . str_pad((string)($rounded % $scale), $digits, '0', STR_PAD_LEFT);
}
function percent(float $value): string { return decimals($value * 100, 4); }
function amount(float $cents): string { return decimals($cents / 100, 2); }
function thousandths(string $price): int { [$whole, $fraction] = explode('.', $price); return (int)$whole * 1000 + (int)$fraction; }
function read_lines(string $name): array { $lines = explode("\n", file_get_contents("input/$name")); array_pop($lines); return $lines; }
function rows(string $name): array { $rows = []; foreach (array_slice(read_lines($name), 1) as $index => $line) $rows[] = [$index + 2, explode(',', $line)]; return $rows; }
function write_lines(string $name, array $lines): void { file_put_contents("output/$name", $lines ? implode("\n", $lines) . "\n" : ''); }
function record_error(array &$errors, string $file, int $line, string $key, string $message): void { $errors[] = "$file:$line: $key: $message"; }

function parse_options(string $kind, string $text): array {
    $options = ['EOM' => false, 'LONG' => false, 'sinks' => [], 'calls' => []]; $seen = [];
    foreach ($text === '-' ? [] : explode(';', $text) as $item) {
        $pieces = explode('=', $item, 2); $key = $pieces[0]; $value = $pieces[1] ?? '';
        if (!in_array($key, OPTION_KEYS[$kind], true) || (isset($seen[$key]) && !in_array($key, ['SINK', 'CALL'], true))) throw new InputError('invalid option');
        $seen[$key] = true;
        if ($key === 'EOM' || $key === 'LONG') $options[$key] = true;
        elseif ($key === 'SINK' || $key === 'CALL') { [$date, $number] = explode(':', $value); $options[$key === 'SINK' ? 'sinks' : 'calls'][] = [$date, $key === 'SINK' ? (int)$number : thousandths($number)]; }
        else $options[$key] = (int)$value;
    }
    if ($kind === 'FRN' && (!isset($options['LAG']) || $options['LAG'] < 1 || $options['LAG'] > 5 || ($options['CAP'] ?? 1200) > 1200 || ($options['FLOOR'] ?? 0) > ($options['CAP'] ?? 1200))) throw new InputError('invalid option');
    return $options;
}

function schedule_days(array $items, array $schedule, string $error): array {
    $inner = array_fill_keys(array_slice($schedule, 1, -1), true); $result = []; $last = -1;
    foreach ($items as [$text, $value]) {
        if (!valid_date($text)) throw new InputError($error);
        $day = parse_date($text);
        if (!isset($inner[$day]) || $day <= $last) throw new InputError($error);
        $result[] = [$day, $value]; $last = $day;
    }
    return $result;
}

function latest_fixing(array $fixings, int $day): ?int {
    $low = 0; $high = count($fixings);
    while ($low < $high) { $middle = intdiv($low + $high, 2); if ($fixings[$middle][0] <= $day) $low = $middle + 1; else $high = $middle; }
    return $low === 0 ? null : $fixings[$low - 1][1];
}

class Bond {
    public array $options, $schedule, $sinks = [], $calls = [], $periods = [];
    public function __construct(public string $code, public string $kind, public int $issue, public int $maturity, public int $coupon, public int $frequency, public string $daycount, public string $bdc, public int $face) {}
}

function parse_bond(array $fields, array $seen, Calendar $calendar, array $fixings): Bond {
    [$code, $kind, $issueText, $maturityText, $coupon, $frequency, $daycount, $bdc, $face, $optionText] = $fields;
    $coupon = (int)$coupon; $frequency = (int)$frequency; $face = (int)$face;
    if (isset($seen[$code])) throw new InputError('duplicate id');
    if (!in_array($kind, BOND_TYPES, true)) throw new InputError('unknown type');
    if (!valid_date($issueText) || !valid_date($maturityText)) throw new InputError('invalid date');
    $issue = parse_date($issueText); $maturity = parse_date($maturityText);
    if ($maturity <= $issue) throw new InputError('maturity not after issue');
    if (!in_array($frequency, FREQUENCIES, true)) throw new InputError('invalid frequency');
    if (!in_array($daycount, DAY_COUNTS, true)) throw new InputError('unknown day count');
    if (!in_array($bdc, BUSINESS_DAY_RULES, true)) throw new InputError('unknown business day rule');
    if ($face % 100000 !== 0 || $face > 10000000) throw new InputError('invalid face');
    if ($coupon > 1200 || ($kind === 'ZERO' && $coupon !== 0)) throw new InputError('invalid coupon');
    $bond = new Bond($code, $kind, $issue, $maturity, $coupon, $frequency, $daycount, $bdc, $face);
    $bond->options = parse_options($kind, $optionText);
    $bond->schedule = coupon_schedule($issue, $maturity, $frequency, $bond->options['EOM'], $bond->options['LONG']);
    $total = 0;
    foreach (schedule_days($bond->options['sinks'], $bond->schedule, 'invalid sinking fund') as [$day, $value]) {
        if ($value === 0) throw new InputError('invalid sinking fund');
        $bond->sinks[$day] = $value; $total += $value;
    }
    if ($kind === 'AMORT' && ($total === 0 || $total >= $face)) throw new InputError('invalid sinking fund');
    $bond->calls = schedule_days($bond->options['calls'], $bond->schedule, 'invalid call schedule');
    foreach ($bond->calls as [, $price]) if ($price < 100000 || $price > 110000) throw new InputError('invalid call schedule');
    $opening = $face; $last = count($bond->schedule) - 1;
    for ($number = 1; $number <= $last; $number++) {
        $start = $bond->schedule[$number - 1]; $end = $bond->schedule[$number];
        [$n, $m] = year_fraction($daycount, $start, $end);
        $rate = $kind === 'ZERO' ? 0 : $coupon;
        if ($kind === 'FRN') {
            $fixing = latest_fixing($fixings, $calendar->move($calendar->adjust($start, $bdc), -$bond->options['LAG']));
            if ($fixing === null) throw new InputError('missing fixing');
            $rate = $fixing + $coupon;
            if (isset($bond->options['FLOOR'])) $rate = max($rate, $bond->options['FLOOR']);
            if (isset($bond->options['CAP'])) $rate = min($rate, $bond->options['CAP']);
        }
        $principal = $number === $last ? $opening : ($bond->sinks[$end] ?? 0);
        $couponAmount = round_half_up($opening * $rate * $n, 10000 * $m);
        $bond->periods[] = ['number' => $number, 'start' => $start, 'end' => $end, 'payment' => $calendar->adjust($end, $bdc), 'n' => $n, 'm' => $m,
            'rate' => $rate, 'opening' => $opening, 'coupon' => $couponAmount, 'principal' => $principal, 'cash' => $couponAmount + $principal];
        $opening -= $principal;
    }
    return $bond;
}

class Valuation {
    public array $remaining, $cashflows, $flows, $risk = [];
    public int $outstanding, $accruedAmount, $cleanAmount, $unitValue, $workout, $nextPayment;
    public float $accrued, $target, $fraction, $ytm = 0.0, $ytw = 0.0, $wal = 0.0, $curveClean = 0.0, $spread = 0.0;
    public YieldPricer $pricer;
    public function __construct(public Bond $bond, public int $clean, int $settlement) {
        $index = 0; while ($bond->periods[$index]['end'] <= $settlement) $index++;
        $current = $bond->periods[$index]; $this->remaining = array_slice($bond->periods, $index); $this->outstanding = $current['opening'];
        [$n, $m] = year_fraction($bond->daycount, $current['start'], $settlement);
        $this->accrued = $current['rate'] * $n / (100 * $m);
        $this->accruedAmount = round_half_up($this->outstanding * $current['rate'] * $n, 10000 * $m);
        $this->cleanAmount = round_half_up($this->outstanding * $clean, 100000); $this->unitValue = $this->cleanAmount + $this->accruedAmount;
        $this->target = $clean / 1000 + $this->accrued;
        [$n, $m] = year_fraction($bond->daycount, $settlement, $current['end']);
        $this->fraction = $bond->frequency * $n / $m;
        $this->cashflows = array_values(array_filter($this->remaining, fn($period) => $period['cash'] >= 1));
        $this->flows = array_map(fn($period) => [$period['payment'] - $settlement, $period['cash']], $this->cashflows);
        $this->pricer = new YieldPricer(array_column($this->remaining, 'cash'), $this->fraction, $bond->frequency, $this->outstanding);
        $this->workout = $bond->maturity; $this->nextPayment = $this->cashflows[0]['payment'];
    }
    public function analyze(ZeroCurve $curve, int $settlement): void {
        $this->ytm = $this->pricer->solve($this->target); $this->risk = $this->pricer->risk($this->ytm); $this->ytw = $this->ytm;
        foreach ($this->bond->calls as [$day, $price]) if ($day > $settlement) {
            $flows = [];
            foreach ($this->remaining as $period) {
                $flows[] = $period['coupon'];
                if ($period['end'] === $day) { $flows[count($flows) - 1] += round_half_up($period['opening'] * $price, 100000); break; }
            }
            $yield = (new YieldPricer($flows, $this->fraction, $this->bond->frequency, $this->outstanding))->solve($this->target);
            if ($yield < $this->ytw) { $this->ytw = $yield; $this->workout = $day; }
        }
        $principalDays = 0;
        foreach ($this->cashflows as $index => $period) $principalDays += $period['principal'] * $this->flows[$index][0];
        $this->wal = $principalDays / (365 * $this->outstanding);
        $this->curveClean = $curve->presentValue($this->flows) * 100 / $this->outstanding - $this->accrued;
        $this->spread = z_spread($curve, $this->flows, $this->unitValue);
    }
}

class Position {
    public int $units = 0, $book = 0;
    public function __construct(public Valuation $valuation) {}
    public function value(): int { return $this->units * $this->valuation->unitValue; }
    public function face(): int { return $this->units * $this->valuation->bond->face; }
    public function outstanding(): int { return $this->units * $this->valuation->outstanding; }
    public function gain(): int { return $this->units * $this->valuation->cleanAmount - $this->book; }
    public function dv01(): float { return $this->valuation->risk['dv01'] * $this->units * $this->valuation->outstanding / 10000; }
    public function pv(ZeroCurve $curve): float { return $this->units * $curve->presentValue($this->valuation->flows, $this->valuation->spread); }
}

class Portfolio {
    public int $total, $income = 0;
    public float $ytm = 0.0, $modified = 0.0, $convexity = 0.0, $spread = 0.0, $dv01 = 0.0, $cashYield = 0.0, $base = 0.0, $effective = 0.0;
    public array $baseValues = [], $keyRates = [], $types = [], $buckets = [], $ladder = [], $results = [];
    public function __construct(public string $name, public array $positions) { $this->total = array_sum(array_map(fn($position) => $position->value(), $positions)); }
    public function weight(int $value): float { return $value * 100 / $this->total; }
    public function pv(ZeroCurve $curve): float { $total = 0.0; foreach ($this->positions as $position) $total += $position->pv($curve); return $total; }
    public function duration(ZeroCurve $curve, ?int $pillar): float {
        $down = $up = array_fill(0, count($curve->rates), 0.0);
        foreach ($curve->rates as $index => $_) if ($pillar === null || $pillar === $index) { $down[$index] = -BP; $up[$index] = BP; }
        return ($this->pv($curve->shifted($down)) - $this->pv($curve->shifted($up))) / (2 * BP * $this->base);
    }
    public function analyze(ZeroCurve $curve, array $scenarios, int $settlement): void {
        $flows = [];
        $empty = ['count' => 0, 'value' => 0, 'duration' => 0.0, 'dv01' => 0.0];
        $this->types = array_fill_keys(BOND_TYPES, $empty); $this->buckets = array_fill_keys(BUCKETS, $empty);
        foreach ($this->positions as $position) {
            $v = $position->valuation; $value = $position->value();
            $this->ytm += $value * $v->ytm; $this->modified += $value * $v->risk['modified']; $this->convexity += $value * $v->risk['convexity'];
            $this->spread += $value * $v->spread; $this->dv01 += $position->dv01();
            $days = $v->bond->maturity - $settlement; $bucket = $days < 365 ? 0 : ($days < 1095 ? 1 : ($days < 1825 ? 2 : ($days < 3650 ? 3 : 4)));
            foreach ([['types', $v->bond->kind], ['buckets', BUCKETS[$bucket]]] as [$field, $group]) {
                $this->{$field}[$group]['count']++; $this->{$field}[$group]['value'] += $value;
                $this->{$field}[$group]['duration'] += $value * $v->risk['modified']; $this->{$field}[$group]['dv01'] += $position->dv01();
            }
            foreach ($v->cashflows as $index => $period) {
                $flow = $v->flows[$index]; $flows[] = [$flow[0], $position->units * $flow[1]];
                if ($flow[0] <= 365) $this->income += $position->units * $period['coupon'];
                $year = civil_date($period['payment'])[0];
                if (!isset($this->ladder[$year])) $this->ladder[$year] = [0, 0];
                $this->ladder[$year][0] += $position->units * $period['coupon']; $this->ladder[$year][1] += $position->units * $period['principal'];
            }
            $this->baseValues[] = $position->pv($curve);
        }
        $this->ytm /= $this->total; $this->modified /= $this->total; $this->convexity /= $this->total; $this->spread /= $this->total;
        $this->cashYield = bisection(fn($rate) => (new ZeroCurve([0], [$rate]))->presentValue($flows), 0.0, 1.0, (float)$this->total);
        foreach ($this->baseValues as $value) $this->base += $value;
        $this->effective = $this->duration($curve, null);
        foreach ($curve->rates as $index => $_) $this->keyRates[] = $this->duration($curve, $index);
        ksort($this->ladder, SORT_NUMERIC);
        foreach ([['BASE', array_fill(0, count($curve->rates), 0.0)], ...$scenarios] as [$name, $deltas]) {
            $shifted = $curve->shifted($deltas); $values = $pnls = []; $total = 0.0;
            foreach ($this->positions as $index => $position) { $value = $position->pv($shifted); $values[] = $value; $pnls[] = $value - $this->baseValues[$index]; $total += $value; }
            $this->results[] = ['name' => $name, 'values' => $values, 'pnls' => $pnls, 'total' => $total, 'pnl' => $total - $this->base];
        }
    }
    public function report(): array {
        $lines = ["portfolio $this->name"]; $face = $outstanding = $book = $gain = 0;
        foreach ($this->positions as $position) {
            $v = $position->valuation;
            $lines[] = 'position ' . $v->bond->code . ' face ' . hundredths($position->face()) . ' outstanding ' . hundredths($position->outstanding()) . ' clean ' . decimals($v->clean / 1000, 6)
                . ' value ' . hundredths($position->value()) . ' weight ' . decimals($this->weight($position->value()), 4) . ' book ' . hundredths($position->book) . ' gain ' . hundredths($position->gain())
                . ' ytm ' . percent($v->ytm) . ' modified ' . decimals($v->risk['modified'], 4) . ' dv01 ' . decimals($position->dv01(), 2);
            $face += $position->face(); $outstanding += $position->outstanding(); $book += $position->book; $gain += $position->gain();
        }
        $lines[] = 'total positions ' . count($this->positions) . ' face ' . hundredths($face) . ' outstanding ' . hundredths($outstanding) . ' value ' . hundredths($this->total) . ' book ' . hundredths($book) . ' gain ' . hundredths($gain) . ' income ' . hundredths($this->income);
        $lines[] = 'risk ytm ' . percent($this->ytm) . ' yield ' . percent($this->cashYield) . ' modified ' . decimals($this->modified, 4) . ' convexity ' . decimals($this->convexity, 4) . ' zspread ' . percent($this->spread) . ' dv01 ' . decimals($this->dv01, 2);
        $lines[] = 'curve effective ' . decimals($this->effective, 4) . ' krd ' . implode(' ', array_map(fn($duration) => decimals($duration, 4), $this->keyRates));
        foreach (['type' => $this->types, 'bucket' => $this->buckets] as $label => $groups) foreach ($groups as $name => $group) $lines[] = "$label $name positions " . $group['count'] . ' value ' . hundredths($group['value']) . ' weight ' . decimals($this->weight($group['value']), 4) . ' duration ' . decimals($group['duration'] / $this->total, 4) . ' dv01 ' . decimals($group['dv01'], 2);
        $coupon = $principal = 0;
        foreach ($this->ladder as $year => [$c, $p]) { $lines[] = "ladder $year coupon " . hundredths($c) . ' principal ' . hundredths($p) . ' total ' . hundredths($c + $p); $coupon += $c; $principal += $p; }
        $lines[] = 'ladder total coupon ' . hundredths($coupon) . ' principal ' . hundredths($principal) . ' total ' . hundredths($coupon + $principal);
        $worst = null;
        foreach (array_slice($this->results, 1) as $result) if ($worst === null || $result['pnl'] < $worst['pnl']) $worst = $result;
        if ($worst !== null) {
            $indices = array_keys($this->positions);
            usort($indices, fn($a, $b) => ($worst['pnls'][$a] <=> $worst['pnls'][$b]) ?: strcmp($this->positions[$a]->valuation->bond->code, $this->positions[$b]->valuation->bond->code));
            $parts = ['stress worst', $worst['name'], 'pnl', amount($worst['pnl']), 'losers'];
            foreach (array_slice($indices, 0, 3) as $index) { $parts[] = $this->positions[$index]->valuation->bond->code; $parts[] = amount($worst['pnls'][$index]); }
            $lines[] = implode(' ', $parts);
        }
        return $lines;
    }
    public function scenarioLines(): array {
        $lines = [];
        foreach ($this->results as $result) {
            foreach ($this->positions as $index => $position) $lines[] = implode(',', [$this->name, $result['name'], $position->valuation->bond->code, amount($result['values'][$index]), amount($result['pnls'][$index])]);
            $lines[] = implode(',', [$this->name, $result['name'], '*', amount($result['total']), amount($result['pnl'])]);
        }
        return $lines;
    }
    public function compliance(array $limits, int $settlement): array {
        $lines = []; $breaches = 0;
        foreach ($limits as $words) {
            $kind = $words[0]; $limit = (int)$words[1];
            if ($kind === 'position_weight') {
                $largest = $this->positions[0]; foreach ($this->positions as $position) if ($position->value() > $largest->value()) $largest = $position;
                $value = $largest->value(); $detail = $largest->valuation->bond->code . ' ' . decimals($this->weight($value), 4) . ' limit ' . hundredths($limit); $breach = $value * 10000 > $limit * $this->total;
            } elseif ($kind === 'type_weight') {
                $limit = (int)$words[2]; $value = $this->types[$words[1]]['value']; $detail = $words[1] . ' ' . decimals($this->weight($value), 4) . ' limit ' . hundredths($limit); $breach = $value * 10000 > $limit * $this->total;
            } elseif ($kind === 'max_maturity') {
                $count = count(array_filter($this->positions, fn($position) => $position->valuation->bond->maturity - $settlement > 365 * $limit)); $detail = $limit . "Y positions $count"; $breach = $count > 0;
            } elseif ($kind === 'min_yield') { $detail = percent($this->ytm) . ' limit ' . hundredths($limit); $breach = $this->ytm * 10000 < $limit; }
            elseif ($kind === 'duration') { $high = (int)$words[2]; $detail = decimals($this->modified, 4) . ' range ' . hundredths($limit) . ' ' . hundredths($high); $breach = $this->modified < $limit / 100 || $this->modified > $high / 100; }
            else { $detail = decimals($this->dv01, 2) . ' limit ' . hundredths($limit); $breach = $this->dv01 * 100 > $limit; }
            $lines[] = "$this->name $kind $detail " . ($breach ? 'BREACH' : 'PASS');
            if ($breach) $breaches++;
        }
        $lines[] = "$this->name breaches $breaches";
        return $lines;
    }
}

$valuationDate = $settlementDays = 0; $scenarioLines = $limits = [];
foreach (read_lines('params.txt') as $index => $line) {
    $words = explode(' ', $line); $kind = array_shift($words);
    if ($kind === 'valuation_date') $valuationDate = parse_date($words[0]);
    elseif ($kind === 'settlement_days') $settlementDays = (int)$words[0];
    elseif ($kind === 'scenario') { $name = array_shift($words); $scenarioLines[] = [$index + 1, $name, array_map('intval', $words)]; }
    else $limits[] = $words;
}
$calendar = new Calendar(array_map('parse_date', read_lines('calendar.txt')));
$fixings = []; foreach (rows('fixings.csv') as [, $fields]) $fixings[] = [parse_date($fields[0]), (int)$fields[1]];
$settlement = $calendar->move($valuationDate, $settlementDays); $errors = $pillars = $seen = [];
foreach (rows('curve_quotes.csv') as [$number, $fields]) {
    $text = $fields[0]; $frequency = (int)$fields[2]; $reason = null;
    if (isset($seen[$text])) $reason = 'duplicate pillar';
    elseif (!valid_date($text)) $reason = 'invalid date';
    elseif (parse_date($text) <= $settlement) $reason = 'pillar not after settlement';
    elseif (!in_array($frequency, FREQUENCIES, true)) $reason = 'invalid frequency';
    if ($reason !== null) record_error($errors, 'curve_quotes.csv', $number, $text, $reason);
    else $pillars[] = [parse_date($text), (int)$fields[1], $frequency];
    $seen[$text] = true;
}
usort($pillars, fn($a, $b) => $a[0] <=> $b[0]);
$scenarios = $seen = [];
foreach ($scenarioLines as [$number, $name, $shifts]) {
    if (isset($seen[$name])) record_error($errors, 'params.txt', $number, $name, 'duplicate scenario');
    elseif (count($shifts) !== count($pillars)) record_error($errors, 'params.txt', $number, $name, 'wrong number of shifts');
    else $scenarios[] = [$name, array_map(fn($shift) => $shift * BP, $shifts)];
    $seen[$name] = true;
}
$bonds = $seen = [];
foreach (rows('bonds.csv') as [$number, $fields]) {
    try { $bonds[$fields[0]] = parse_bond($fields, $seen, $calendar, $fixings); }
    catch (InputError $error) { record_error($errors, 'bonds.csv', $number, $fields[0], $error->getMessage()); }
    $seen[$fields[0]] = true;
}
ksort($bonds, SORT_STRING); $valuations = $seen = [];
foreach (rows('prices.csv') as [$number, $fields]) {
    [$code, $price] = $fields;
    try {
        if (!isset($bonds[$code])) throw new InputError('unknown bond');
        if (isset($seen[$code])) throw new InputError('duplicate price');
        $bond = $bonds[$code];
        if ($bond->issue > $settlement || $settlement >= $bond->maturity) throw new InputError('not outstanding');
        $value = new Valuation($bond, thousandths($price), $settlement);
        if (!$value->pricer->inRange($value->target)) throw new InputError('yield out of range');
        $valuations[$code] = $value;
    } catch (InputError $error) { record_error($errors, 'prices.csv', $number, $code, $error->getMessage()); }
    $seen[$code] = true;
}
ksort($valuations, SORT_STRING); $positions = [];
foreach (rows('holdings.csv') as [$number, $fields]) {
    [$portfolio, $code, $face, $bookPrice] = $fields; $face = (int)$face;
    try {
        if (!isset($bonds[$code])) throw new InputError('unknown bond');
        if (!isset($valuations[$code])) throw new InputError('no price');
        if ($face % $bonds[$code]->face !== 0) throw new InputError('invalid face');
        $units = intdiv($face, $bonds[$code]->face);
        if (!isset($positions[$portfolio][$code])) $positions[$portfolio][$code] = new Position($valuations[$code]);
        $positions[$portfolio][$code]->units += $units;
        $positions[$portfolio][$code]->book += round_half_up($units * $valuations[$code]->outstanding * thousandths($bookPrice), 100000);
    } catch (InputError $error) { record_error($errors, 'holdings.csv', $number, $code, $error->getMessage()); }
}
$curve = bootstrap($settlement, $pillars);
foreach ($valuations as $value) $value->analyze($curve, $settlement);
$cashflowRows = ['bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal'];
foreach ($bonds as $bond) foreach ($bond->periods as $period) if ($period['cash'] >= 1) $cashflowRows[] = implode(',', [$bond->code, $period['number'], format_date($period['start']), format_date($period['end']), format_date($period['payment']), decimals($period['n'] / $period['m'], 6), $period['rate'], $period['opening'], $period['coupon'], $period['principal']]);
$analytics = ['bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread'];
foreach ($valuations as $code => $v) $analytics[] = implode(',', [$code, decimals($v->clean / 1000, 6), decimals($v->accrued, 6), decimals($v->target, 6), percent($v->ytm), percent($v->ytw), format_date($v->workout), format_date($v->nextPayment), decimals($v->wal, 4), decimals($v->risk['macaulay'], 4), decimals($v->risk['modified'], 4), decimals($v->risk['convexity'], 4), decimals($v->risk['dv01'], 6), decimals($v->curveClean, 6), percent($v->spread)]);
$curveRows = ['valuation ' . format_date($valuationDate) . ' settlement ' . format_date($settlement)]; $previous = 0;
foreach ($pillars as $index => [$maturity, $coupon, $frequency]) {
    $days = $curve->days[$index];
    $curveRows[] = 'pillar ' . format_date($maturity) . " days $days frequency $frequency par " . hundredths($coupon) . ' zero ' . percent($curve->rates[$index]) . ' df ' . decimals($curve->discount($days), 6) . ' forward ' . percent($curve->forward($previous, $days));
    $previous = $days;
}
for ($year = 1; $year <= intdiv($curve->days[count($curve->days) - 1], 365); $year++) { $days = 365 * $year; $curveRows[] = "grid {$year}Y days $days zero " . percent($curve->zero($days)) . ' df ' . decimals($curve->discount($days), 6) . ' forward ' . percent($curve->forward($days - 365, $days)); }
ksort($positions, SORT_STRING); $report = $compliance = []; $scenarioRows = ['portfolio,scenario,bond,value,pnl'];
foreach ($positions as $name => $members) {
    ksort($members, SORT_STRING); $portfolio = new Portfolio((string)$name, array_values($members)); $portfolio->analyze($curve, $scenarios, $settlement);
    array_push($report, ...$portfolio->report()); array_push($scenarioRows, ...$portfolio->scenarioLines()); array_push($compliance, ...$portfolio->compliance($limits, $settlement));
}
if (!is_dir('output')) mkdir('output', 0777, true);
foreach (['errors.txt' => $errors, 'cashflows.csv' => $cashflowRows, 'analytics.csv' => $analytics, 'curve.txt' => $curveRows, 'portfolio.txt' => $report, 'scenarios.csv' => $scenarioRows, 'compliance.txt' => $compliance] as $name => $lines) write_lines($name, $lines);
