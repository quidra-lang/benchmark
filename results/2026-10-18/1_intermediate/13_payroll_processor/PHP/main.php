<?php

declare(strict_types=1);

const RATE_SETTINGS = [
    'STATE', 'SUPP', 'SSRATE', 'MEDRATE', 'ADDMED',
    'UIRATE', 'MATCH', 'MATCHMAX', 'GARNCAP',
];
const INITIAL_SETTINGS = [
    'STATE' => 500, 'SUPP' => 2200, 'SSRATE' => 620, 'MEDRATE' => 145,
    'ADDMED' => 90, 'UIRATE' => 270, 'MATCH' => 5000, 'MATCHMAX' => 600,
    'GARNCAP' => 2500, 'SSBASE' => 16860000, 'ADDBASE' => 20000000,
    'UIBASE' => 700000, 'RETIRECAP' => 2300000, 'ALLOWANCE' => 15000,
    'NIGHT' => 100,
];
const FIELDS = [
    'R', 'O', 'D', 'N', 'P', 'accrued', 'salary', 'leave', 'deduction',
    'sales', 'commission', 'earnings', 'bonus', 'gross', 'retirement', 'health',
    'federal', 'supplemental', 'state', 'social', 'medicare', 'garnishment', 'net',
    'employer_social', 'employer_medicare', 'unemployment', 'match', 'employer',
    'W', 'Y', 'F', 'J',
];
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

function cents(string $text): int
{
    [$whole, $fraction] = explode('.', $text);
    return (int) $whole * 100 + (int) $fraction;
}

function money(int $value): string
{
    return intdiv($value, 100) . '.' . str_pad((string) ($value % 100), 2, '0', STR_PAD_LEFT);
}

function rateText(int $value): string
{
    return money($value) . '%';
}

function duration(int $minutes): string
{
    return intdiv($minutes, 60) . ':' . str_pad((string) ($minutes % 60), 2, '0', STR_PAD_LEFT);
}

function clockText(int $minutes): string
{
    return str_pad((string) intdiv($minutes, 60), 2, '0', STR_PAD_LEFT) .
        ':' . str_pad((string) ($minutes % 60), 2, '0', STR_PAD_LEFT);
}

function weekday(int $day): string
{
    return WEEKDAYS[($day - 1) % 7];
}

function periodOf(int $day): int
{
    return intdiv($day - 1, 14) + 1;
}

function emptyTotals(): array
{
    return array_fill_keys(FIELDS, 0);
}

function sumStubs(array $stubs): array
{
    $totals = emptyTotals();
    foreach ($stubs as $stub) {
        foreach (FIELDS as $field) {
            $totals[$field] += $stub[$field];
        }
    }
    return $totals;
}

function progressive(array $table, int $amount): int
{
    ksort($table, SORT_NUMERIC);
    $bounds = array_keys($table);
    $numerator = 0;
    foreach ($bounds as $i => $lower) {
        if ($lower >= $amount) {
            break;
        }
        $upper = $bounds[$i + 1] ?? $amount;
        $numerator += $table[$lower] * (min($amount, $upper) - $lower);
    }
    return intdiv($numerator, 10000);
}

final class CommandError extends RuntimeException
{
}

final class Employee
{
    public bool $active = true;
    public int $retirement = 0;
    public int $health = 0;
    public int $allowances = 0;
    public int $extra = 0;
    public int $bonus = 0;
    public int $ptoBalance = 0;
    public array $garnishments = [];
    public array $shifts = [];
    public array $pto = [];
    public array $leave = [];
    public array $sales = [];
    public array $stubs = [];
    public array $ytd;
    public int $periods = 0;

    public function __construct(
        public int $id,
        public string $department,
        public string $kind,
        public int $base
    ) {
        $this->ytd = emptyTotals();
    }

    public function garnishmentBalance(): int
    {
        $total = 0;
        foreach ($this->garnishments as [$rate, $balance]) {
            $total += $balance;
        }
        return $total;
    }
}

final class Payroll
{
    private array $settings = INITIAL_SETTINGS;
    private array $brackets = [];
    private array $tiers = [];
    private array $holidays = [];
    private array $employees = [];
    private int $closed = 0;
    private array $output = [];

    private function emit(array $parts, int $indent = 0): void
    {
        $this->output[] = str_repeat(' ', $indent) . implode(' ', array_map('strval', $parts));
    }

    private function employee(string $text, bool $active = false, ?string $kind = null): Employee
    {
        $id = (int) $text;
        if (!isset($this->employees[$id])) {
            throw new CommandError('unknown employee ' . $text);
        }
        $employee = $this->employees[$id];
        if ($active && !$employee->active) {
            throw new CommandError('terminated employee ' . $text);
        }
        if ($kind !== null && $employee->kind !== $kind) {
            throw new CommandError('not ' . strtolower($kind) . ' ' . $text);
        }
        return $employee;
    }

    private function dayCheck(string $text): int
    {
        $day = (int) $text;
        if ($day < 1 || $day > 364) {
            throw new CommandError('invalid day ' . $text);
        }
        $period = periodOf($day);
        if ($period <= $this->closed) {
            throw new CommandError('period closed ' . $period);
        }
        return $day;
    }

    private function periodCheck(string $text): int
    {
        $period = (int) $text;
        if ($period < 1 || $period > 26) {
            throw new CommandError('invalid period ' . $text);
        }
        return $period;
    }

    private function rateCheck(string $text): int
    {
        $value = cents($text);
        if ($value > 10000) {
            throw new CommandError('invalid rate ' . $text);
        }
        return $value;
    }

    private function amountCheck(string $text): int
    {
        $value = cents($text);
        if ($value === 0) {
            throw new CommandError('invalid amount');
        }
        return $value;
    }

    private function timeCheck(string $text): int
    {
        [$hour, $minute] = array_map('intval', explode(':', $text));
        if ($hour > 23 || $minute > 59) {
            throw new CommandError('invalid time ' . $text);
        }
        return 60 * $hour + $minute;
    }

    private function daily(Employee $employee, int $day): array
    {
        $shifts = $employee->shifts[$day] ?? [];
        $worked = 0;
        $night = 0;
        foreach ($shifts as [$start, $end]) {
            $worked += $end - $start;
            $night += max(0, min($end, 360) - $start) +
                max(0, $end - max($start, 1320));
        }
        $pto = $employee->pto[$day] ?? 0;
        if ($day % 7 === 0 || isset($this->holidays[$day])) {
            [$regular, $overtime, $double] = [0, 0, $worked];
        } else {
            $regular = min($worked, 480);
            $overtime = min(max($worked - 480, 0), 240);
            $double = max($worked - 720, 0);
        }
        return [$worked, $regular, $overtime, $double, $night, $pto];
    }

    private function weekly(Employee $employee, int $week): array
    {
        $totals = [0, 0, 0, 0, 0];
        for ($day = 7 * $week - 6; $day <= 7 * $week; ++$day) {
            $daily = $this->daily($employee, $day);
            for ($i = 0; $i < 5; ++$i) {
                $totals[$i] += $daily[$i + 1];
            }
        }
        $weeklyOvertime = max(0, $totals[0] - 2400);
        $totals[0] -= $weeklyOvertime;
        $totals[1] += $weeklyOvertime;
        return [$totals, $weeklyOvertime];
    }

    private function breakdown(Employee $employee, int $period): array
    {
        [$first] = $this->weekly($employee, 2 * $period - 1);
        [$second] = $this->weekly($employee, 2 * $period);
        $result = [];
        for ($i = 0; $i < 5; ++$i) {
            $result[] = $first[$i] + $second[$i];
        }
        return $result;
    }

    private function calculate(Employee $employee, int $period): ?array
    {
        $stub = emptyTotals();
        $settings = $this->settings;
        $ytd = $employee->ytd;
        if ($employee->kind === 'HOURLY') {
            $amounts = $this->breakdown($employee, $period);
            foreach (['R', 'O', 'D', 'N', 'P'] as $i => $field) {
                $stub[$field] = $amounts[$i];
            }
            [$regular, $overtime, $double, $night, $pto] = $amounts;
            $weighted = 2 * ($regular + $pto) + 3 * $overtime + 4 * $double;
            $stub['earnings'] = intdiv(
                $weighted * $employee->base + 2 * $night * $settings['NIGHT'], 120
            );
        } elseif ($employee->kind === 'SALARIED') {
            if ($employee->active) {
                $stub['salary'] = intdiv($employee->base, 26);
                foreach ($employee->leave as $day => $present) {
                    if (periodOf($day) === $period && !isset($this->holidays[$day])) {
                        ++$stub['leave'];
                    }
                }
                $stub['deduction'] = $stub['leave'] * intdiv($employee->base, 260);
                $stub['earnings'] = $stub['salary'] - $stub['deduction'];
            }
        } else {
            $stub['sales'] = $employee->sales[$period] ?? 0;
            $stub['commission'] = progressive($this->tiers, $stub['sales']);
            $stub['earnings'] = $stub['commission'] + ($employee->active ? $employee->base : 0);
        }
        $stub['bonus'] = $employee->bonus;
        $gross = $stub['earnings'] + $stub['bonus'];
        if ($gross === 0) {
            return null;
        }
        $stub['gross'] = $gross;
        $remaining = $gross;
        $deduct = static function (string $field, int $amount) use (&$remaining, &$stub): void {
            $stub[$field] = min($amount, $remaining);
            $remaining -= $stub[$field];
        };
        $room = max(0, $settings['RETIRECAP'] - $ytd['retirement']);
        $deduct('retirement', min(intdiv($gross * $employee->retirement, 10000), $room));
        $deduct('health', $employee->health);
        $stub['W'] = $remaining;
        $baseTaxable = max(0, $stub['earnings'] - $stub['retirement'] - $stub['health']);
        $allowanceTaxable = max(0, $baseTaxable - $employee->allowances * $settings['ALLOWANCE']);
        $deduct('federal', progressive($this->brackets, $allowanceTaxable) + $employee->extra);
        $deduct('supplemental', intdiv(($stub['W'] - $baseTaxable) * $settings['SUPP'], 10000));
        $deduct('state', intdiv($stub['W'] * $settings['STATE'], 10000));
        $medicareWages = $gross - $stub['health'];
        $socialWages = min($medicareWages, max(0, $settings['SSBASE'] - $ytd['Y']));
        $additional = max(
            0,
            min($medicareWages, $ytd['F'] + $medicareWages - $settings['ADDBASE'])
        );
        $stub['F'] = $medicareWages;
        $stub['Y'] = $socialWages;
        $deduct('social', intdiv($socialWages * $settings['SSRATE'], 10000));
        $deduct('medicare', intdiv($medicareWages * $settings['MEDRATE'], 10000) +
            intdiv($additional * $settings['ADDMED'], 10000));
        $disposable = $remaining;
        $cap = intdiv($disposable * $settings['GARNCAP'], 10000);
        $balances = [];
        $garnishment = 0;
        foreach ($employee->garnishments as [$rate, $balance]) {
            $taken = min(intdiv($disposable * $rate, 10000), $balance, $cap - $garnishment);
            $garnishment += $taken;
            $balances[] = $balance - $taken;
        }
        $stub['garnishment'] = $garnishment;
        $stub['garnishment_balance'] = array_sum($balances);
        $stub['net'] = $remaining - $garnishment;
        $stub['employer_social'] = intdiv($socialWages * $settings['SSRATE'], 10000);
        $stub['employer_medicare'] = intdiv($medicareWages * $settings['MEDRATE'], 10000);
        $stub['J'] = min($medicareWages, max(0, $settings['UIBASE'] - $ytd['J']));
        $stub['unemployment'] = intdiv($stub['J'] * $settings['UIRATE'], 10000);
        $eligibleMatch = min($stub['retirement'], intdiv($gross * $settings['MATCHMAX'], 10000));
        $stub['match'] = intdiv($eligibleMatch * $settings['MATCH'], 10000);
        $stub['employer'] = $stub['employer_social'] + $stub['employer_medicare'] +
            $stub['unemployment'] + $stub['match'];
        if ($employee->kind === 'HOURLY') {
            $stub['accrued'] = min(
                960 - $employee->ptoBalance,
                intdiv($stub['R'] + $stub['O'] + $stub['D'], 20)
            );
        }
        $stub['pto_balance'] = $employee->ptoBalance + $stub['accrued'];
        return [$stub, $balances];
    }

    private function hoursParts(array $values): array
    {
        $parts = [];
        foreach (['reg', 'ot', 'dbl', 'night', 'pto'] as $i => $label) {
            $parts[] = $label;
            $parts[] = duration($values[$i]);
        }
        return $parts;
    }

    private function stubBlock(Employee $employee, array $stub, int $indent): void
    {
        if ($employee->kind === 'HOURLY') {
            $this->emit(array_merge(
                ['hours'],
                $this->hoursParts(array_map(
                    static fn(string $field): int => $stub[$field],
                    ['R', 'O', 'D', 'N', 'P']
                ))
            ), $indent);
            $this->emit(
                ['pto', 'accrued', duration($stub['accrued']),
                    'balance', duration($stub['pto_balance'])], $indent
            );
        } elseif ($employee->kind === 'SALARIED') {
            $this->emit(
                ['salary', money($stub['salary']), 'leave', $stub['leave'],
                    'deduction', money($stub['deduction'])], $indent
            );
        } else {
            $this->emit(['sales', money($stub['sales']),
                         'commission', money($stub['commission'])], $indent);
        }
        foreach (['earnings', 'bonus', 'gross', 'retirement', 'health', 'federal',
                  'supplemental', 'state', 'social', 'medicare'] as $field) {
            $this->emit([$field === 'social' ? 'social-security' : $field,
                         money($stub[$field])], $indent);
        }
        $this->emit(
            ['garnishment', money($stub['garnishment']),
                'balance', money($stub['garnishment_balance'])], $indent
        );
        $this->emit(['net', money($stub['net'])], $indent);
        $this->emit([
            'employer', 'social-security', money($stub['employer_social']),
            'medicare', money($stub['employer_medicare']),
            'unemployment', money($stub['unemployment']),
            'match', money($stub['match']),
        ], $indent);
    }

    private function printStub(Employee $employee, int $period, array $stub, string $department): void
    {
        $this->emit(['STUB', $employee->id, $department, $employee->kind, 'period', $period], 2);
        $this->stubBlock($employee, $stub, 4);
    }

    private function showHours(Employee $employee, int $period): void
    {
        $this->emit(['HOURS', $employee->id, 'period', $period]);
        $found = false;
        for ($day = 14 * $period - 13; $day <= 14 * $period; ++$day) {
            $shifts = $employee->shifts[$day] ?? [];
            usort($shifts, static fn(array $a, array $b): int => $a <=> $b);
            if (!$shifts && !isset($employee->pto[$day])) {
                continue;
            }
            [$worked, $regular, $overtime, $double, $night, $pto] = $this->daily($employee, $day);
            $parts = ['day', $day, weekday($day)];
            if (isset($this->holidays[$day])) {
                $parts[] = 'holiday';
            }
            foreach ($shifts as [$start, $end]) {
                $parts[] = clockText($start) . '-' . clockText($end);
            }
            $this->emit(
                array_merge(
                    $parts,
                    ['total', duration($worked)],
                    $this->hoursParts([$regular, $overtime, $double, $night, $pto])
                ),
                2
            );
            $found = true;
        }
        if (!$found) {
            $this->emit(['(none)'], 2);
        }
        foreach ([2 * $period - 1, 2 * $period] as $week) {
            [$values, $overtime] = $this->weekly($employee, $week);
            $this->emit(
                array_merge(['week', $week], $this->hoursParts($values),
                            ['weekly-ot', duration($overtime)]), 2
            );
        }
        $this->emit(array_merge(['total'], $this->hoursParts($this->breakdown($employee, $period))), 2);
    }

    private function run(int $period): void
    {
        $this->closed = $period;
        $this->emit(['RUN', $period, 'days',
                     (14 * $period - 13) . '-' . (14 * $period)]);
        $paid = 0;
        $skipped = 0;
        $stubs = [];
        $ids = array_keys($this->employees);
        sort($ids, SORT_NUMERIC);
        foreach ($ids as $id) {
            $employee = $this->employees[$id];
            $calculated = $this->calculate($employee, $period);
            if ($calculated === null) {
                if ($employee->active) {
                    ++$skipped;
                }
                continue;
            }
            [$stub, $balances] = $calculated;
            $this->printStub($employee, $period, $stub, $employee->department);
            $employee->bonus = 0;
            $employee->ptoBalance = $stub['pto_balance'];
            foreach ($balances as $i => $balance) {
                $employee->garnishments[$i][1] = $balance;
            }
            foreach (FIELDS as $field) {
                $employee->ytd[$field] += $stub[$field];
            }
            ++$employee->periods;
            $employee->stubs[$period] = ['stub' => $stub, 'department' => $employee->department];
            $stubs[] = $stub;
            ++$paid;
        }
        $total = sumStubs($stubs);
        $this->emit(
            ['TOTAL', 'paid', $paid, 'skipped', $skipped,
             'gross', money($total['gross']),
             'deductions', money($total['gross'] - $total['net']),
             'net', money($total['net']),
             'employer', money($total['employer'])], 2
        );
    }

    private function journal(int $period): void
    {
        $stubs = [];
        foreach ($this->employees as $employee) {
            if (isset($employee->stubs[$period])) {
                $stubs[] = $employee->stubs[$period]['stub'];
            }
        }
        $total = sumStubs($stubs);
        $rows = [
            ['debit', 'wages', $total['gross']],
            ['debit', 'employer-tax',
             $total['employer_social'] + $total['employer_medicare'] + $total['unemployment']],
            ['debit', 'retirement-match', $total['match']],
            ['credit', 'retirement', $total['retirement'] + $total['match']],
            ['credit', 'health', $total['health']],
            ['credit', 'federal', $total['federal'] + $total['supplemental']],
            ['credit', 'state', $total['state']],
            ['credit', 'fica', $total['social'] + $total['medicare'] +
             $total['employer_social'] + $total['employer_medicare']],
            ['credit', 'unemployment', $total['unemployment']],
            ['credit', 'garnishment', $total['garnishment']],
            ['credit', 'net-pay', $total['net']],
        ];
        $this->emit(['JOURNAL', $period, 'stubs', count($stubs)]);
        $debit = 0;
        $credit = 0;
        foreach ($rows as [$side, $label, $amount]) {
            $this->emit([$side, $label, money($amount)], 2);
            if ($side === 'debit') {
                $debit += $amount;
            } else {
                $credit += $amount;
            }
        }
        $this->emit(['total', 'debit', money($debit), 'credit', money($credit)], 2);
    }

    private function reportLine(string $department, array $stubs): void
    {
        $total = sumStubs($stubs);
        $taxes = 0;
        foreach (['federal', 'supplemental', 'state', 'social', 'medicare'] as $field) {
            $taxes += $total[$field];
        }
        $this->emit([
            $department, 'stubs', count($stubs), 'gross', money($total['gross']),
            'pretax', money($total['retirement'] + $total['health']),
            'taxes', money($taxes), 'garnishment', money($total['garnishment']),
            'net', money($total['net']), 'employer', money($total['employer']),
        ], 2);
    }

    private function command(string $command, array $a): void
    {
        if ($command === 'SET') {
            $name = $a[0];
            if (!array_key_exists($name, $this->settings)) {
                throw new CommandError('unknown setting ' . $name);
            }
            $rate = in_array($name, RATE_SETTINGS, true);
            $value = $rate ? $this->rateCheck($a[1]) : cents($a[1]);
            $format = $rate ? 'rateText' : 'money';
            $old = $this->settings[$name];
            $this->settings[$name] = $value;
            $this->emit(['SET', $name, $format($old), '->', $format($value)]);
        } elseif ($command === 'BRACKET' || $command === 'TIER') {
            $rate = $this->rateCheck($a[1]);
            $lower = cents($a[0]);
            $table = $command === 'BRACKET' ? 'brackets' : 'tiers';
            $action = array_key_exists($lower, $this->$table) ? 'replaced' : 'added';
            $this->{$table}[$lower] = $rate;
            $this->emit([$command, money($lower), rateText($rate), $action]);
        } elseif ($command === 'EMP') {
            $id = (int) $a[0];
            if (isset($this->employees[$id])) {
                throw new CommandError('duplicate employee ' . $a[0]);
            }
            $base = $this->amountCheck($a[3]);
            $this->employees[$id] = new Employee($id, $a[1], $a[2], $base);
            $this->emit(['EMP', $id, $a[1], $a[2], money($base)]);
        } elseif (in_array($command, ['RATE', 'DEPT', 'BENEFIT', 'W4', 'GARNISH', 'TERM', 'BONUS'], true)) {
            $employee = $this->employee($a[0], true);
            if ($command === 'RATE') {
                $base = $this->amountCheck($a[1]);
                $old = $employee->base;
                $employee->base = $base;
                $this->emit(['RATE', $employee->id, money($old), '->', money($base)]);
            } elseif ($command === 'DEPT') {
                if ($a[1] === $employee->department) {
                    throw new CommandError('same department ' . $a[1]);
                }
                $old = $employee->department;
                $employee->department = $a[1];
                $this->emit(['DEPT', $employee->id, $old, '->', $a[1]]);
            } elseif ($command === 'BENEFIT') {
                $employee->retirement = $this->rateCheck($a[1]);
                $employee->health = cents($a[2]);
                $this->emit([
                    'BENEFIT', $employee->id, 'retirement', rateText($employee->retirement),
                    'health', money($employee->health),
                ]);
            } elseif ($command === 'W4') {
                $employee->allowances = (int) $a[1];
                $employee->extra = cents($a[2]);
                $this->emit([
                    'W4', $employee->id, 'allowances', $employee->allowances,
                    'extra', money($employee->extra),
                ]);
            } elseif ($command === 'GARNISH') {
                $rate = $this->rateCheck($a[1]);
                $amount = $this->amountCheck($a[2]);
                $employee->garnishments[] = [$rate, $amount];
                $this->emit([
                    'GARNISH', $employee->id, 'order', count($employee->garnishments),
                    rateText($rate), 'balance', money($amount),
                ]);
            } elseif ($command === 'TERM') {
                $employee->active = false;
                $this->emit(['TERM', $employee->id]);
            } else {
                $amount = $this->amountCheck($a[1]);
                $employee->bonus += $amount;
                $this->emit([
                    'BONUS', $employee->id, money($amount),
                    'pending', money($employee->bonus),
                ]);
            }
        } elseif ($command === 'HOLIDAY') {
            $day = $this->dayCheck($a[0]);
            if (isset($this->holidays[$day])) {
                throw new CommandError('duplicate holiday ' . $a[0]);
            }
            $this->holidays[$day] = true;
            $this->emit(['HOLIDAY', $day, weekday($day)]);
        } elseif (in_array($command, ['TIME', 'UNTIME', 'PTO', 'LEAVE', 'SALES'], true)) {
            $kind = $command === 'LEAVE' ? 'SALARIED' :
                ($command === 'SALES' ? 'COMMISSION' : 'HOURLY');
            $employee = $this->employee($a[0], true, $kind);
            $day = $this->dayCheck($a[1]);
            if ($command === 'TIME') {
                $start = $this->timeCheck($a[2]);
                $end = $this->timeCheck($a[3]);
                if ($start >= $end) {
                    throw new CommandError('invalid shift ' . $a[2] . '-' . $a[3]);
                }
                $shifts = $employee->shifts[$day] ?? [];
                usort($shifts, static fn(array $x, array $y): int => $x <=> $y);
                foreach ($shifts as [$oldStart, $oldEnd]) {
                    if ($start < $oldEnd && $oldStart < $end) {
                        throw new CommandError(
                            'overlapping shift ' . clockText($oldStart) . '-' . clockText($oldEnd)
                        );
                    }
                }
                $minutes = 0;
                foreach ($shifts as [$oldStart, $oldEnd]) {
                    $minutes += $oldEnd - $oldStart;
                }
                if ($minutes + $end - $start > 960) {
                    throw new CommandError('daily limit ' . $a[0] . ' ' . $a[1]);
                }
                $employee->shifts[$day][] = [$start, $end];
                $this->emit([
                    'TIME', $employee->id, 'day', $day,
                    clockText($start) . '-' . clockText($end), duration($end - $start),
                ]);
            } elseif ($command === 'UNTIME') {
                $start = $this->timeCheck($a[2]);
                $found = null;
                foreach (($employee->shifts[$day] ?? []) as $i => $shift) {
                    if ($shift[0] === $start) {
                        $found = [$i, $shift];
                        break;
                    }
                }
                if ($found === null) {
                    throw new CommandError('no shift ' . $a[0] . ' ' . $a[1] . ' ' . $a[2]);
                }
                [$i, [$begin, $end]] = $found;
                array_splice($employee->shifts[$day], $i, 1);
                $this->emit([
                    'UNTIME', $employee->id, 'day', $day,
                    clockText($begin) . '-' . clockText($end),
                ]);
            } elseif ($command === 'PTO') {
                [$hour, $minute] = array_map('intval', explode(':', $a[2]));
                $length = 60 * $hour + $minute;
                if ($minute > 59 || $length < 1 || $length > 480) {
                    throw new CommandError('invalid duration ' . $a[2]);
                }
                if (isset($employee->pto[$day])) {
                    throw new CommandError('duplicate pto ' . $a[0] . ' ' . $a[1]);
                }
                if ($length > $employee->ptoBalance) {
                    throw new CommandError(
                        'insufficient pto ' . $a[0] . ' ' . duration($employee->ptoBalance)
                    );
                }
                $employee->pto[$day] = $length;
                $employee->ptoBalance -= $length;
                $this->emit([
                    'PTO', $employee->id, 'day', $day, duration($length),
                    'balance', duration($employee->ptoBalance),
                ]);
            } elseif ($command === 'LEAVE') {
                if ($day % 7 === 0 || $day % 7 === 6 || isset($this->holidays[$day])) {
                    throw new CommandError('not workday ' . $a[1]);
                }
                if (isset($employee->leave[$day])) {
                    throw new CommandError('duplicate leave ' . $a[0] . ' ' . $a[1]);
                }
                $employee->leave[$day] = true;
                $this->emit(['LEAVE', $employee->id, 'day', $day, weekday($day)]);
            } else {
                $amount = $this->amountCheck($a[2]);
                $period = periodOf($day);
                $employee->sales[$period] = ($employee->sales[$period] ?? 0) + $amount;
                $this->emit([
                    'SALES', $employee->id, 'day', $day,
                    money($amount), 'period', $period, 'total', money($employee->sales[$period]),
                ]);
            }
        } elseif ($command === 'HOURS') {
            $employee = $this->employee($a[0], false, 'HOURLY');
            $period = $this->periodCheck($a[1]);
            $this->showHours($employee, $period);
        } elseif ($command === 'RUN') {
            $period = (int) $a[0];
            if ($period !== $this->closed + 1 || $period > 26) {
                throw new CommandError('invalid period ' . $a[0]);
            }
            $this->run($period);
        } elseif ($command === 'PREVIEW') {
            $employee = $this->employee($a[0]);
            $period = $this->closed + 1;
            $calculated = $this->calculate($employee, $period);
            $this->emit(['PREVIEW', $employee->id, 'period', $period]);
            if ($calculated === null) {
                $this->emit(['no pay'], 2);
            } else {
                $this->printStub($employee, $period, $calculated[0], $employee->department);
            }
        } elseif ($command === 'REPRINT') {
            $employee = $this->employee($a[0]);
            $period = $this->periodCheck($a[1]);
            if (!isset($employee->stubs[$period])) {
                throw new CommandError('no stub ' . $a[0] . ' ' . $a[1]);
            }
            $saved = $employee->stubs[$period];
            $this->emit(['REPRINT', $employee->id, $period]);
            $this->printStub($employee, $period, $saved['stub'], $saved['department']);
        } elseif ($command === 'YTD') {
            $employee = $this->employee($a[0]);
            $this->emit([
                'YTD', $employee->id, $employee->department, $employee->kind,
                $employee->active ? 'active' : 'terminated',
                'periods', $employee->periods,
            ]);
            $totals = $employee->ytd;
            $totals['pto_balance'] = $employee->ptoBalance;
            $totals['garnishment_balance'] = $employee->garnishmentBalance();
            $this->stubBlock($employee, $totals, 2);
            $this->emit([
                'wages', 'federal', money($totals['W']),
                'social-security', money($totals['Y']),
                'medicare', money($totals['F']),
                'unemployment', money($totals['J']),
            ], 2);
            $this->emit([
                'retirement-room', money(max(0, $this->settings['RETIRECAP'] - $totals['retirement'])),
                'pending-bonus', money($employee->bonus),
            ], 2);
        } elseif ($command === 'JOURNAL') {
            $period = (int) $a[0];
            if ($period < 1 || $period > $this->closed) {
                throw new CommandError('no run ' . $a[0]);
            }
            $this->journal($period);
        } elseif ($command === 'REPORT') {
            $departments = [];
            $allStubs = [];
            foreach ($this->employees as $employee) {
                foreach ($employee->stubs as $saved) {
                    $departments[$saved['department']][] = $saved['stub'];
                    $allStubs[] = $saved['stub'];
                }
            }
            $this->emit(['REPORT', 'period', $this->closed]);
            ksort($departments, SORT_STRING);
            foreach ($departments as $department => $stubs) {
                $this->reportLine($department, $stubs);
            }
            $this->reportLine('total', $allStubs);
        } elseif ($command === 'TOP') {
            $count = (int) $a[0];
            $employees = array_values(array_filter(
                $this->employees,
                static fn(Employee $employee): bool => $employee->periods > 0
            ));
            usort($employees, static fn(Employee $x, Employee $y): int =>
                ($y->ytd['gross'] <=> $x->ytd['gross']) ?: ($x->id <=> $y->id)
            );
            $this->emit(['TOP', $count]);
            foreach (array_slice($employees, 0, $count) as $rank => $employee) {
                $this->emit([
                    $rank + 1, $employee->id, $employee->department,
                    'gross', money($employee->ytd['gross']),
                    'net', money($employee->ytd['net']),
                ], 2);
            }
            if (!$employees) {
                $this->emit(['(none)'], 2);
            }
        } elseif ($command === 'EMPLOYEES') {
            $this->emit(['EMPLOYEES']);
            $ids = array_keys($this->employees);
            sort($ids, SORT_NUMERIC);
            foreach ($ids as $id) {
                $employee = $this->employees[$id];
                $this->emit([
                    $id, $employee->department, $employee->kind, money($employee->base),
                    $employee->active ? 'active' : 'terminated',
                    'retirement', rateText($employee->retirement),
                    'health', money($employee->health),
                    'allowances', $employee->allowances,
                    'extra', money($employee->extra),
                    'bonus', money($employee->bonus),
                ], 2);
                foreach ($employee->garnishments as $i => [$rate, $balance]) {
                    $this->emit([
                        'garnish', $i + 1, rateText($rate), 'balance', money($balance),
                    ], 4);
                }
            }
            if (!$ids) {
                $this->emit(['(none)'], 2);
            }
        } elseif ($command === 'CONFIG') {
            $this->emit(['CONFIG']);
            foreach ($this->settings as $name => $value) {
                $this->emit([
                    $name, in_array($name, RATE_SETTINGS, true) ? rateText($value) : money($value),
                ], 2);
            }
            foreach (['bracket' => $this->brackets, 'tier' => $this->tiers] as $label => $table) {
                ksort($table, SORT_NUMERIC);
                foreach ($table as $lower => $rate) {
                    $this->emit([$label, money((int) $lower), rateText($rate)], 2);
                }
            }
        }
    }

    public function execute(string $line): void
    {
        $tokens = explode(' ', $line);
        $command = array_shift($tokens);
        try {
            $this->command($command, $tokens);
        } catch (CommandError $error) {
            $this->emit(['ERROR', $error->getMessage()]);
        }
    }

    public function output(): string
    {
        return implode("\n", $this->output) . "\n";
    }
}

$count = (int) trim((string) fgets(STDIN));
$payroll = new Payroll();
for ($i = 0; $i < $count; ++$i) {
    $payroll->execute(rtrim((string) fgets(STDIN), "\r\n"));
}
echo $payroll->output();
