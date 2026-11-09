<?php

declare(strict_types=1);

const SETTING_RANGES = [
    'CAPACITY' => [1, 100000], 'INITIAL' => [0, 100],
    'CHARGE' => [1, 20000], 'DISCHARGE' => [1, 20000],
    'CEFF' => [1, 100], 'DEFF' => [1, 100],
    'RESERVE' => [0, 100], 'COST' => [0, 100000],
    'EXPORT' => [0, 100000], 'FEEDIN' => [0, 10000],
    'FIXED' => [0, 100000], 'DEMAND' => [0, 100000],
    'PVSCALE' => [0, 300],
];
const STRATEGY_RANGES = [
    'TOU' => [1, 100], 'PEAKSHAVE' => [0, 100000], 'BACKUP' => [0, 100],
];
const FLOW_NAMES = [
    'PV>LOAD', 'PV>BATTERY', 'PV>GRID', 'PV>CURTAIL',
    'BATTERY>LOAD', 'BATTERY>GRID', 'GRID>LOAD', 'GRID>BATTERY',
];
const TOTAL_FIELDS = [
    'load', 'pv', 'charge', 'discharge', 'imported', 'exported',
    'curtailed', 'drawn', 'loss', 'shortfall', 'importCost', 'exportIncome',
];
const DAY_NAMES = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

final class CommandError extends RuntimeException {}

function money(int $value): string
{
    $amount = abs($value);
    return ($value < 0 ? '-' : '') . intdiv($amount, 100) . '.' .
        str_pad((string) ($amount % 100), 2, '0', STR_PAD_LEFT);
}

function percentage(int $numerator, int $denominator): string
{
    $value = $denominator === 0 ? 0 : intdiv(10000 * $numerator, $denominator);
    return intdiv($value, 100) . '.' . str_pad((string) ($value % 100), 2, '0', STR_PAD_LEFT);
}

function ceiling(int $number, int $denominator): int
{
    return intdiv($number + $denominator - 1, $denominator);
}

function tableRow(array $values, array $widths): string
{
    $result = '';
    foreach ($values as $index => $value) {
        $result .= str_pad((string) $value, $widths[$index], ' ', STR_PAD_LEFT);
    }
    return $result;
}

function bar(int $width): string
{
    return '|' . str_repeat('#', $width) . str_repeat('.', 20 - $width) . '|';
}

function tariffExtremes(array $prices): array
{
    $cheapest = $peak = array_key_first($prices);
    foreach ($prices as $name => $value) {
        if ($value < $prices[$cheapest]) $cheapest = $name;
        if ($value > $prices[$peak]) $peak = $name;
    }
    return [$cheapest, $peak];
}

function strategyText(array $strategy): string
{
    return $strategy[0] . ($strategy[1] === null ? '' : ' ' . $strategy[1]);
}

function readStrategies(array $tokens): array
{
    $strategies = [];
    for ($index = 0; $index < count($tokens);) {
        $name = $tokens[$index++];
        if ($name === 'SELF' || $name === 'EXPORTPEAK') {
            $strategies[] = [$name, null];
            continue;
        }
        if (!isset(STRATEGY_RANGES[$name])) throw new CommandError('unknown strategy ' . $name);
        if ($index === count($tokens)) throw new CommandError('missing parameter for ' . $name);
        $parameter = (int) $tokens[$index++];
        [$low, $high] = STRATEGY_RANGES[$name];
        if ($parameter < $low || $parameter > $high) {
            throw new CommandError('invalid parameter for ' . $name);
        }
        $strategies[] = [$name, $parameter];
    }
    return $strategies;
}

function requireCount(array $values, int $count): void
{
    if (count($values) !== $count) throw new CommandError('wrong number of arguments');
}

function oneStrategy(array $arguments): array
{
    $strategies = readStrategies($arguments);
    requireCount($strategies, 1);
    return $strategies[0];
}

function checkedRange(int $low, int $high, int $step, array $bounds): array
{
    [$minimum, $maximum] = $bounds;
    if ($low < $minimum || $high > $maximum || $high < $low || $step < 1 ||
        intdiv(max(0, $high - $low), max(1, $step)) + 1 > 20) {
        throw new CommandError('invalid range');
    }
    $values = [];
    for ($value = $low; $value <= $high; $value += $step) $values[] = $value;
    return $values;
}

final class InputData
{
    public array $initialSettings;
    public array $initialPrices;
    public int $dayCount;
    public array $loads = [];
    public array $basePV = [];
    public array $dayNames = [];
    public array $weekendDays = [];
    public array $periods = [];
    public array $commands;
    private array $lines;
    private int $position = 0;

    public function __construct(array $lines)
    {
        $this->lines = $lines;
        $battery = array_map('intval', array_slice($this->read(), 1));
        $grid = array_map('intval', array_slice($this->read(), 1));
        $this->initialSettings = array_combine(array_keys(SETTING_RANGES),
                                                array_merge($battery, $grid, [100]));
        $periodCount = (int) $this->read()[1];
        $this->initialPrices = [];
        for ($i = 0; $i < $periodCount; ++$i) {
            [$name, $price] = $this->read();
            $this->initialPrices[$name] = (int) $price;
        }
        $weekday = $this->readPeriodHours(array_slice($this->read(), 1));
        $weekend = $this->readPeriodHours(array_slice($this->read(), 1));
        $profileCount = (int) $this->read()[1];
        $profiles = [];
        for ($i = 0; $i < $profileCount; ++$i) {
            [$kind, $name, $values] = $this->splitProfile($this->read());
            $profiles[$kind . '/' . $name] = $values;
        }
        $this->dayCount = (int) $this->read()[1];
        for ($i = 0; $i < $this->dayCount; ++$i) {
            [$loadName, $loadPct, $pvName, $pvPct] = $this->read();
            foreach ($profiles['LOAD/' . $loadName] as $value) {
                $this->loads[] = intdiv($value * (int) $loadPct, 100);
            }
            foreach ($profiles['PV/' . $pvName] as $value) {
                $this->basePV[] = intdiv($value * (int) $pvPct, 100);
            }
        }
        $holidays = array_fill_keys(array_map('intval', array_slice($this->read(), 2)), true);
        $overrideCount = (int) $this->read()[1];
        for ($i = 0; $i < $overrideCount; ++$i) {
            [$day, $hour, $load, $pv] = array_map('intval', $this->read());
            $index = ($day - 1) * 24 + $hour;
            $this->loads[$index] = $load;
            $this->basePV[$index] = $pv;
        }
        for ($day = 1; $day <= $this->dayCount; ++$day) {
            $holiday = isset($holidays[$day]);
            $weekendDay = $holiday || ($day - 1) % 7 >= 5;
            $this->dayNames[] = $holiday ? 'HOL' : DAY_NAMES[($day - 1) % 7];
            $this->weekendDays[] = $weekendDay;
            array_push($this->periods, ...($weekendDay ? $weekend : $weekday));
        }
        $this->commands = array_slice($this->lines, $this->position);
    }

    private function read(): array
    {
        return explode(' ', $this->lines[$this->position++]);
    }

    private function splitProfile(array $tokens): array
    {
        return [$tokens[0], $tokens[1], array_map('intval', array_slice($tokens, 2))];
    }

    private function readPeriodHours(array $tokens): array
    {
        $hours = [];
        for ($i = 0; $i < count($tokens); $i += 2) {
            $start = (int) $tokens[$i];
            $end = isset($tokens[$i + 2]) ? (int) $tokens[$i + 2] : 24;
            for ($hour = $start; $hour < $end; ++$hour) $hours[] = $tokens[$i + 1];
        }
        return $hours;
    }
}

final class HourRecord
{
    public int $day;
    public int $hour;
    public int $charge;
    public int $discharge;
    public int $imported;
    public int $exported;
    public int $curtailed;
    public int $importCost;
    public int $exportIncome;
    public int $netCost;

    public function __construct(
        public int $index, public string $period, public int $load, public int $pv,
        public int $soc, public array $flows, public int $drawn, public int $shortfall,
        public int $loss, int $price, int $feedin
    ) {
        $this->day = intdiv($index, 24) + 1;
        $this->hour = $index % 24;
        $this->charge = $flows[1] + $flows[7];
        $this->discharge = $flows[4] + $flows[5];
        $this->imported = $flows[6] + $flows[7];
        $this->exported = $flows[2] + $flows[5];
        $this->curtailed = $flows[3];
        $this->importCost = intdiv($this->imported * $price, 100000);
        $this->exportIncome = intdiv($this->exported * $feedin, 100000);
        $this->netCost = $this->importCost - $this->exportIncome;
    }
}

final class Totals
{
    public int $count;
    public int $load = 0;
    public int $pv = 0;
    public int $charge = 0;
    public int $discharge = 0;
    public int $imported = 0;
    public int $exported = 0;
    public int $curtailed = 0;
    public int $drawn = 0;
    public int $loss = 0;
    public int $shortfall = 0;
    public int $importCost = 0;
    public int $exportIncome = 0;
    public int $netCost;
    public array $flows;

    public function __construct(array $records)
    {
        $this->count = count($records);
        $this->flows = array_fill(0, count(FLOW_NAMES), 0);
        foreach ($records as $record) {
            foreach (TOTAL_FIELDS as $field) $this->$field += $record->$field;
            foreach ($record->flows as $index => $value) $this->flows[$index] += $value;
        }
        $this->netCost = $this->importCost - $this->exportIncome;
    }
}

final class SimulationResult
{
    public array $days = [];
    public array $daily = [];
    public array $byPeriod = [];
    public Totals $total;
    public int $peak;
    public int $demandCharge;
    public int $bill;
    public int $endSoc;
    public string $sufficiency;

    public function __construct(
        public array $strategy, public array $settings, public array $prices,
        public int $startSoc, public int $reserve, public array $hours
    ) {
        $this->days = array_chunk($hours, 24);
        foreach ($this->days as $day) $this->daily[] = new Totals($day);
        foreach ($prices as $period => $_) {
            $this->byPeriod[$period] = new Totals(array_values(array_filter(
                $hours, static fn(HourRecord $record): bool => $record->period === $period
            )));
        }
        $this->total = new Totals($hours);
        $this->peak = max(array_map(static fn(HourRecord $record): int => $record->imported, $hours));
        $this->demandCharge = intdiv($this->peak * $settings['DEMAND'], 1000);
        $this->bill = $this->total->netCost + $settings['FIXED'] + $this->demandCharge;
        $this->endSoc = end($hours)->soc;
        $this->sufficiency = percentage(max(0, $this->total->load - $this->total->imported),
                                        $this->total->load);
    }
}

final class Simulator
{
    private string $name;
    private ?int $parameter;
    private int $capacity;
    private int $ceff;
    private int $deff;
    private int $reserve;
    private int $startSoc;
    private int $soc;
    private string $cheapest;
    private string $peak;
    private bool $arbitrage;

    public function __construct(
        private InputData $data, private array $strategy,
        private array $settings, private array $prices, private ?array $outage = null
    ) {
        [$this->name, $this->parameter] = $strategy;
        $this->capacity = $settings['CAPACITY'];
        $this->ceff = $settings['CEFF'];
        $this->deff = $settings['DEFF'];
        $reservePercent = $this->name === 'BACKUP'
            ? max($settings['RESERVE'], $this->parameter) : $settings['RESERVE'];
        $this->reserve = intdiv($this->capacity * $reservePercent, 100);
        $this->startSoc = intdiv($this->capacity * $settings['INITIAL'], 100);
        $this->soc = $this->startSoc;
        [$this->cheapest, $this->peak] = tariffExtremes($prices);
        $this->arbitrage = $this->name === 'EXPORTPEAK'
            && $settings['FEEDIN'] > $prices[$this->cheapest];
    }

    private function dischargeTarget(int $deficit, string $period): int
    {
        if ($this->name === 'TOU') return $period === $this->peak ? $deficit : 0;
        if ($this->name === 'PEAKSHAVE') return max(0, $deficit - $this->parameter);
        if ($this->arbitrage && $period === $this->cheapest && $period !== $this->peak) return 0;
        return $deficit;
    }

    private function gridCharge(string $period, int $pvCharge, int $gridLoad): int
    {
        $headroom = $this->settings['CHARGE'] - $pvCharge;
        $target = null;
        if ($this->name === 'TOU' && $period === $this->cheapest && $period !== $this->peak) {
            $target = intdiv($this->capacity * $this->parameter, 100);
        } elseif ($this->name === 'PEAKSHAVE' && $period === $this->cheapest) {
            $target = $this->capacity;
            $headroom = min($headroom, max(0, $this->parameter - $gridLoad));
        } elseif ($this->name === 'BACKUP' && $period === $this->cheapest) {
            $target = $this->reserve;
        } elseif ($this->arbitrage && $period === $this->cheapest && $period !== $this->peak) {
            $target = $this->capacity;
        }
        if ($target === null) return 0;
        $amount = min($headroom, ceiling(100 * max(0, $target - $this->soc), $this->ceff));
        $this->soc += intdiv($amount * $this->ceff, 100);
        return $amount;
    }

    private function runHour(int $index): HourRecord
    {
        $settings = $this->settings;
        $load = $this->data->loads[$index];
        $pv = intdiv($this->data->basePV[$index] * $settings['PVSCALE'], 100);
        $period = $this->data->periods[$index];
        $direct = min($load, $pv);
        $surplus = $pv - $direct;
        $deficit = $load - $direct;
        $pvCharge = min($surplus, $settings['CHARGE'],
                        ceiling(100 * ($this->capacity - $this->soc), $this->ceff));
        $this->soc += intdiv($pvCharge * $this->ceff, 100);
        $surplus -= $pvCharge;
        $isOutage = $this->outage !== null
                    && $this->outage[0] <= $index && $index <= $this->outage[1];
        $target = $isOutage ? $deficit : $this->dischargeTarget($deficit, $period);
        $lowerBound = $isOutage ? 0 : $this->reserve;
        $loadDrawn = min(ceiling(100 * $target, $this->deff), $settings['DISCHARGE'],
                         max(0, $this->soc - $lowerBound));
        $loadDischarge = intdiv($loadDrawn * $this->deff, 100);
        $this->soc -= $loadDrawn;
        $deficit -= $loadDischarge;
        $exportDrawn = $batteryExport = 0;
        if ($isOutage) {
            $gridLoad = 0;
            $shortfall = $deficit;
            $pvExport = 0;
            $curtailed = $surplus;
            $gridCharge = 0;
        } else {
            $gridLoad = $deficit;
            $shortfall = 0;
            $pvExport = min($surplus, $settings['EXPORT']);
            $curtailed = $surplus - $pvExport;
            $gridCharge = $this->gridCharge($period, $pvCharge, $gridLoad);
            if ($this->arbitrage && $period === $this->peak && $pvCharge === 0) {
                $exportDrawn = min(ceiling(100 * ($settings['EXPORT'] - $pvExport), $this->deff),
                                   $settings['DISCHARGE'] - $loadDrawn,
                                   max(0, $this->soc - $this->reserve));
                $batteryExport = intdiv($exportDrawn * $this->deff, 100);
                $this->soc -= $exportDrawn;
            }
        }
        $loss = $pvCharge - intdiv($pvCharge * $this->ceff, 100)
              + $gridCharge - intdiv($gridCharge * $this->ceff, 100)
              + $loadDrawn - $loadDischarge + $exportDrawn - $batteryExport;
        $flows = [$direct, $pvCharge, $pvExport, $curtailed, $loadDischarge,
                  $batteryExport, $gridLoad, $gridCharge];
        return new HourRecord($index, $period, $load, $pv, $this->soc, $flows,
                              $loadDrawn + $exportDrawn, $shortfall, $loss,
                              $this->prices[$period], $settings['FEEDIN']);
    }

    public function run(): SimulationResult
    {
        $records = [];
        foreach ($this->data->loads as $index => $_) $records[] = $this->runHour($index);
        return new SimulationResult($this->strategy, $this->settings, $this->prices,
                                    $this->startSoc, $this->reserve, $records);
    }
}

final class DispatchDesk
{
    private array $settings;
    private array $prices;
    private ?SimulationResult $current = null;

    private const COMMANDS = [
        'RUN' => 'cmdRun', 'SET' => 'cmdSet', 'PRICE' => 'cmdPrice',
        'RESET' => 'cmdReset', 'CONFIG' => 'cmdConfig',
        'NOBATTERY' => 'cmdNoBattery', 'COMPARE' => 'cmdCompare',
        'SIZE' => 'cmdSize', 'SWEEP' => 'cmdSweep', 'OUTAGE' => 'cmdOutage',
        'DIFF' => 'cmdDiff', 'HOURLY' => 'cmdHourly', 'DAILY' => 'cmdDaily',
        'BILL' => 'cmdBill', 'SAVINGS' => 'cmdSavings',
        'BYPERIOD' => 'cmdByPeriod', 'DAYTYPE' => 'cmdDayType',
        'PEAKS' => 'cmdPeaks', 'PROFILE' => 'cmdProfile',
        'FLOWS' => 'cmdFlows', 'SELFSUFF' => 'cmdSelfSuff',
        'CYCLES' => 'cmdCycles', 'USAGE' => 'cmdUsage',
        'HISTOGRAM' => 'cmdHistogram', 'CHART' => 'cmdChart',
    ];

    public function __construct(private InputData $data)
    {
        $this->settings = $data->initialSettings;
        $this->prices = $data->initialPrices;
    }

    public function execute(array $tokens): array
    {
        $command = array_shift($tokens);
        if (!isset(self::COMMANDS[$command])) return ['ERROR unknown command ' . $command];
        try {
            return $this->{self::COMMANDS[$command]}($tokens);
        } catch (CommandError $error) {
            return ['ERROR ' . $error->getMessage()];
        }
    }

    private function requireResult(): SimulationResult
    {
        if ($this->current === null) throw new CommandError('no run');
        return $this->current;
    }

    private function checkedDay(string $text): int
    {
        $day = (int) $text;
        if ($day < 1 || $day > $this->data->dayCount) throw new CommandError('invalid day');
        return $day;
    }

    private function resultWithoutArguments(array $args): SimulationResult
    {
        requireCount($args, 0);
        return $this->requireResult();
    }

    private function resultForDay(array $args): array
    {
        requireCount($args, 1);
        $day = $this->checkedDay($args[0]);
        return [$day, $this->requireResult()];
    }

    private function simulate(array $strategy, ?array $settings = null,
                              ?array $prices = null, ?array $outage = null): SimulationResult
    {
        return (new Simulator($this->data, $strategy, $settings ?? $this->settings,
                              $prices ?? $this->prices, $outage))->run();
    }

    private function baseline(array $settings, array $prices): SimulationResult
    {
        $settings['CAPACITY'] = 0;
        return $this->simulate(['SELF', null], $settings, $prices);
    }

    private function cmdRun(array $args): array
    {
        $strategy = oneStrategy($args);
        $result = $this->simulate($strategy);
        $this->current = $result;
        $total = $result->total;
        return ['RUN ' . strategyText($strategy) . ' bill ' . money($result->bill) .
                ' import ' . $total->imported . ' export ' . $total->exported .
                ' soc ' . $result->endSoc];
    }

    private function cmdSet(array $args): array
    {
        requireCount($args, 2);
        [$item, $text] = $args;
        if (!isset(SETTING_RANGES[$item])) throw new CommandError('unknown parameter ' . $item);
        $value = (int) $text;
        [$low, $high] = SETTING_RANGES[$item];
        if ($value < $low || $value > $high) throw new CommandError('invalid value for ' . $item);
        $previous = $this->settings[$item];
        $this->settings[$item] = $value;
        return ["SET $item $previous -> $value"];
    }

    private function cmdPrice(array $args): array
    {
        requireCount($args, 2);
        [$period, $text] = $args;
        if (!array_key_exists($period, $this->prices)) {
            throw new CommandError('unknown period ' . $period);
        }
        $value = (int) $text;
        if ($value < 0 || $value > 10000) throw new CommandError('invalid value for ' . $period);
        $previous = $this->prices[$period];
        $this->prices[$period] = $value;
        [$cheapest, $peak] = tariffExtremes($this->prices);
        return ["PRICE $period $previous -> $value cheapest $cheapest peak $peak"];
    }

    private function cmdReset(array $args): array
    {
        requireCount($args, 0);
        $this->settings = $this->data->initialSettings;
        $this->prices = $this->data->initialPrices;
        return ['RESET'];
    }

    private function cmdConfig(array $args): array
    {
        requireCount($args, 0);
        $names = array_keys(SETTING_RANGES);
        $settings = $this->settings;
        $battery = implode(' ', array_map(static fn(string $item): string =>
            strtolower($item) . ' ' . $settings[$item], array_slice($names, 0, 8)));
        $grid = implode(' ', array_map(static fn(string $item): string =>
            strtolower($item) . ' ' . $settings[$item], array_slice($names, 8, 4)));
        $tariff = [];
        foreach ($this->prices as $period => $price) $tariff[] = "$period $price";
        [$cheapest, $peak] = tariffExtremes($this->prices);
        return ['BATTERY ' . $battery, 'GRID ' . $grid,
                'SOLAR pvscale ' . $settings['PVSCALE'],
                'TARIFF ' . implode(' ', $tariff) . " cheapest $cheapest peak $peak"];
    }

    private function cmdNoBattery(array $args): array
    {
        requireCount($args, 0);
        $result = $this->baseline($this->settings, $this->prices);
        $total = $result->total;
        return ['NOBATTERY bill ' . money($result->bill) . ' import ' . $total->imported .
                ' export ' . $total->exported . ' curtailed ' . $total->curtailed .
                ' peak ' . $result->peak];
    }

    private function cmdCompare(array $args): array
    {
        $strategies = readStrategies($args);
        if (!$strategies) throw new CommandError('wrong number of arguments');
        $baseline = $this->baseline($this->settings, $this->prices);
        $trials = array_map(fn(array $strategy): SimulationResult => $this->simulate($strategy),
                            $strategies);
        usort($trials, static fn(SimulationResult $a, SimulationResult $b): int =>
            $a->bill <=> $b->bill);
        $output = ['COMPARE baseline ' . money($baseline->bill)];
        foreach ($trials as $i => $result) {
            $output[] = ($i + 1) . '. ' . strategyText($result->strategy) .
                        ' bill ' . money($result->bill) .
                        ' saving ' . money($baseline->bill - $result->bill) .
                        ' sufficiency ' . $result->sufficiency . '%';
        }
        return $output;
    }

    private function cmdSize(array $args): array
    {
        requireCount($args, 3);
        $capacities = checkedRange((int) $args[0], (int) $args[1], (int) $args[2],
                                   SETTING_RANGES['CAPACITY']);
        $baseline = $this->baseline($this->settings, $this->prices);
        $output = [];
        $best = null;
        foreach ($capacities as $capacity) {
            $settings = $this->settings;
            $settings['CAPACITY'] = $capacity;
            $result = $this->simulate(['SELF', null], $settings);
            $saving = $baseline->bill - $result->bill;
            $cost = intdiv($capacity * $settings['COST'], 1000);
            $payback = 'never';
            if ($saving > 0) {
                $tenths = intdiv(10 * $cost, $saving);
                $payback = intdiv($tenths, 10) . '.' . ($tenths % 10);
                if ($best === null || $cost * $best[2] < $best[1] * $saving) {
                    $best = [$capacity, $cost, $saving];
                }
            }
            $output[] = "SIZE $capacity bill " . money($result->bill) .
                        ' saving ' . money($saving) . ' cost ' . money($cost) .
                        ' payback ' . $payback;
        }
        $output[] = $best === null ? 'BEST none' : 'BEST ' . $best[0];
        return $output;
    }

    private function cmdSweep(array $args): array
    {
        if (count($args) < 5) throw new CommandError('wrong number of arguments');
        $item = $args[0];
        if (!isset(SETTING_RANGES[$item])) throw new CommandError('unknown parameter ' . $item);
        $values = checkedRange((int) $args[1], (int) $args[2], (int) $args[3],
                               SETTING_RANGES[$item]);
        $strategy = oneStrategy(array_slice($args, 4));
        $output = [];
        $best = null;
        foreach ($values as $value) {
            $settings = $this->settings;
            $settings[$item] = $value;
            $result = $this->simulate($strategy, $settings);
            $baseline = $this->baseline($settings, $this->prices);
            if ($best === null || $result->bill < $best[1]) $best = [$value, $result->bill];
            $output[] = "SWEEP $item $value bill " . money($result->bill) .
                        ' saving ' . money($baseline->bill - $result->bill) .
                        ' sufficiency ' . $result->sufficiency . '%';
        }
        $output[] = 'BEST ' . $best[0];
        return $output;
    }

    private function cmdOutage(array $args): array
    {
        requireCount($args, 3);
        $day = $this->checkedDay($args[0]);
        $start = (int) $args[1];
        $end = (int) $args[2];
        if ($start < 0 || $start > $end || $end > 23) throw new CommandError('invalid hours');
        $current = $this->requireResult();
        $first = ($day - 1) * 24 + $start;
        $last = ($day - 1) * 24 + $end;
        $result = $this->simulate($current->strategy, $current->settings, $current->prices,
                                  [$first, $last]);
        $before = $first ? $result->hours[$first - 1]->soc : $result->startSoc;
        $output = ["OUTAGE day $day hours $start-$end strategy " .
                   strategyText($result->strategy) . " soc $before",
                   'hour   load     pv  disch    soc  short   curt'];
        $records = array_slice($result->hours, $first, $last - $first + 1);
        foreach ($records as $record) {
            $output[] = tableRow([$record->hour, $record->load, $record->pv,
                                  $record->discharge, $record->soc, $record->shortfall,
                                  $record->curtailed], array_merge([4], array_fill(0, 6, 7)));
        }
        $total = new Totals($records);
        $served = $total->load === 0 ? '100.00'
            : percentage($total->load - $total->shortfall, $total->load);
        $output[] = "TOTAL load $total->load unserved $total->shortfall served $served% bill " .
                    money($result->bill);
        return $output;
    }

    private function cmdDiff(array $args): array
    {
        if (count($args) < 2) throw new CommandError('wrong number of arguments');
        $day = $this->checkedDay($args[0]);
        $strategy = oneStrategy(array_slice($args, 1));
        $current = $this->requireResult();
        $comparison = $this->simulate($strategy, $current->settings, $current->prices);
        $output = ["DIFF day $day " . $this->data->dayNames[$day - 1] . ' ' .
                   strategyText($current->strategy) . ' vs ' . strategyText($strategy),
                   'hour   imp1   imp2   exp1   exp2   soc1   soc2'];
        foreach ($current->days[$day - 1] as $i => $first) {
            $second = $comparison->days[$day - 1][$i];
            $output[] = tableRow([$first->hour, $first->imported, $second->imported,
                                  $first->exported, $second->exported,
                                  $first->soc, $second->soc], array_merge([4], array_fill(0, 6, 7)));
        }
        $cost1 = $current->daily[$day - 1]->netCost;
        $cost2 = $comparison->daily[$day - 1]->netCost;
        $output[] = 'TOTAL cost1 ' . money($cost1) . ' cost2 ' . money($cost2) .
                    ' difference ' . money($cost2 - $cost1);
        return $output;
    }

    private function cmdHourly(array $args): array
    {
        [$day, $result] = $this->resultForDay($args);
        $output = ["HOURLY day $day " . $this->data->dayNames[$day - 1] .
                   ' strategy ' . strategyText($result->strategy),
                   'hour   load     pv charge  disch    soc import export   curt'];
        $widths = array_merge([4], array_fill(0, 8, 7));
        foreach ($result->days[$day - 1] as $record) {
            $output[] = tableRow([$record->hour, $record->load, $record->pv,
                                  $record->charge, $record->discharge, $record->soc,
                                  $record->imported, $record->exported, $record->curtailed], $widths);
        }
        $total = $result->daily[$day - 1];
        $output[] = tableRow(['sum', $total->load, $total->pv, $total->charge,
                              $total->discharge, '', $total->imported, $total->exported,
                              $total->curtailed], $widths);
        return $output;
    }

    private function cmdDaily(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $output = ['DAILY strategy ' . strategyText($result->strategy),
                   'day name    load      pv  import  export    curt     soc      cost'];
        foreach ($result->daily as $index => $total) {
            $output[] = tableRow([$index + 1, $this->data->dayNames[$index],
                                  $total->load, $total->pv, $total->imported,
                                  $total->exported, $total->curtailed,
                                  end($result->days[$index])->soc, money($total->netCost)],
                                 [3, 5, 8, 8, 8, 8, 8, 8, 10]);
        }
        $total = $result->total;
        $output[] = "TOTAL load $total->load pv $total->pv import $total->imported " .
                    "export $total->exported curtailed $total->curtailed cost " .
                    money($total->netCost);
        return $output;
    }

    private function cmdBill(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $output = ['BILL strategy ' . strategyText($result->strategy) .
                   ' days ' . $this->data->dayCount];
        foreach ($result->byPeriod as $period => $total) {
            $output[] = "IMPORT $period $total->imported Wh " . money($total->importCost);
        }
        $output[] = 'EXPORT ' . $result->total->exported . ' Wh ' .
                    money(-$result->total->exportIncome);
        $output[] = 'FIXED ' . money($result->settings['FIXED']);
        $output[] = 'DEMAND ' . $result->peak . ' Wh ' . money($result->demandCharge);
        $output[] = 'TOTAL ' . money($result->bill);
        return $output;
    }

    private function cmdSavings(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $baseline = $this->baseline($result->settings, $result->prices);
        $rows = [];
        foreach ($result->byPeriod as $period => $total) {
            $rows[] = [$period, $baseline->byPeriod[$period]->importCost, $total->importCost];
        }
        $rows[] = ['EXPORT', -$baseline->total->exportIncome, -$result->total->exportIncome];
        $rows[] = ['DEMAND', $baseline->demandCharge, $result->demandCharge];
        $rows[] = ['TOTAL', $baseline->bill, $result->bill];
        $output = ['SAVINGS strategy ' . strategyText($result->strategy)];
        foreach ($rows as [$name, $before, $after]) {
            $output[] = "$name " . money($before) . ' -> ' . money($after) .
                        ' saving ' . money($before - $after);
        }
        return $output;
    }

    private function cmdByPeriod(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $output = ['BYPERIOD strategy ' . strategyText($result->strategy)];
        foreach ($result->byPeriod as $period => $total) {
            $output[] = "$period hours $total->count load $total->load pv $total->pv " .
                        "charge $total->charge discharge $total->discharge " .
                        "import $total->imported export $total->exported";
        }
        return $output;
    }

    private function cmdDayType(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $output = ['DAYTYPE strategy ' . strategyText($result->strategy)];
        foreach ([['WEEKDAY', false], ['WEEKEND', true]] as [$label, $weekend]) {
            $records = [];
            $count = 0;
            foreach ($this->data->weekendDays as $day => $flag) {
                if ($flag !== $weekend) continue;
                ++$count;
                array_push($records, ...$result->days[$day]);
            }
            $total = new Totals($records);
            $output[] = "$label days $count load " . intdiv($total->load, $count) .
                        ' pv ' . intdiv($total->pv, $count) .
                        ' import ' . intdiv($total->imported, $count) .
                        ' export ' . intdiv($total->exported, $count) .
                        ' cost ' . money(intdiv($total->netCost, $count));
        }
        return $output;
    }

    private function cmdPeaks(array $args): array
    {
        requireCount($args, 1);
        $count = (int) $args[0];
        if ($count < 1) throw new CommandError('invalid count');
        $result = $this->requireResult();
        $records = array_values(array_filter($result->hours,
            static fn(HourRecord $record): bool => $record->imported > 0));
        usort($records, static fn(HourRecord $a, HourRecord $b): int =>
            ($b->imported <=> $a->imported) ?: ($a->index <=> $b->index));
        $output = ['PEAKS strategy ' . strategyText($result->strategy)];
        foreach (array_slice($records, 0, $count) as $index => $record) {
            $number = $index + 1;
            $output[] = "$number. day $record->day hour $record->hour $record->period " .
                        "import $record->imported load $record->load soc $record->soc";
        }
        if (!$records) $output[] = 'none';
        return $output;
    }

    private function cmdProfile(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $output = ['PROFILE strategy ' . strategyText($result->strategy) .
                   ' days ' . $this->data->dayCount,
                   'hour   load     pv import export    soc'];
        for ($hour = 0; $hour < 24; ++$hour) {
            $averages = [];
            foreach (['load', 'pv', 'imported', 'exported', 'soc'] as $field) {
                $total = 0;
                foreach ($result->days as $day) $total += $day[$hour]->$field;
                $averages[] = intdiv($total, $this->data->dayCount);
            }
            $output[] = tableRow(array_merge([$hour], $averages),
                                 array_merge([4], array_fill(0, 5, 7)));
        }
        return $output;
    }

    private function cmdFlows(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $output = ['FLOWS strategy ' . strategyText($result->strategy)];
        foreach (FLOW_NAMES as $i => $name) $output[] = "$name " . $result->total->flows[$i];
        $output[] = 'LOSSES ' . $result->total->loss;
        $output[] = 'STORED ' . ($result->endSoc - $result->startSoc);
        return $output;
    }

    private function cmdSelfSuff(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $flows = $result->total->flows;
        return ['SELFSUFF sufficiency ' . $result->sufficiency . '% consumption ' .
                percentage($flows[0] + $flows[1], $result->total->pv) . '%'];
    }

    private function cmdCycles(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $drawn = $result->total->drawn;
        $capacity = $result->settings['CAPACITY'];
        $a = $drawn;
        $b = $capacity;
        while ($b !== 0) {
            [$a, $b] = [$b, $a % $b];
        }
        $numerator = intdiv($drawn, $a);
        $denominator = intdiv($capacity, $a);
        $thousandths = intdiv(1000 * $drawn, $capacity);
        $decimal = intdiv($thousandths, 1000) . '.' .
                   str_pad((string) ($thousandths % 1000), 3, '0', STR_PAD_LEFT);
        return ["CYCLES $numerator/$denominator $decimal drawn $drawn losses " .
                $result->total->loss];
    }

    private function cmdUsage(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $charging = $discharging = $idle = $full = $low = 0;
        $runLength = $longest = 0;
        $first = null;
        foreach ($result->hours as $record) {
            if ($record->charge > 0) ++$charging;
            if ($record->drawn > 0) ++$discharging;
            if ($record->charge === 0 && $record->drawn === 0) ++$idle;
            if ($record->soc === $result->settings['CAPACITY']) ++$full;
            if ($record->soc <= $result->reserve) {
                ++$low;
                ++$runLength;
                if ($runLength > $longest) {
                    $longest = $runLength;
                    $first = $result->hours[$record->index - $runLength + 1];
                }
            } else {
                $runLength = 0;
            }
        }
        $line = "USAGE charging $charging discharging $discharging idle $idle " .
                "full $full low $low longest $longest";
        if ($first !== null) $line .= " from day $first->day hour $first->hour";
        return [$line];
    }

    private function cmdHistogram(array $args): array
    {
        $result = $this->resultWithoutArguments($args);
        $capacity = $result->settings['CAPACITY'];
        $counts = array_fill(0, 10, 0);
        foreach ($result->hours as $record) {
            ++$counts[min(9, intdiv(10 * $record->soc, $capacity))];
        }
        $output = ['HISTOGRAM strategy ' . strategyText($result->strategy)];
        foreach ($counts as $index => $count) {
            $width = intdiv(20 * $count, count($result->hours));
            $output[] = str_pad((string) (10 * $index), 3, ' ', STR_PAD_LEFT) .
                        '% ' . bar($width) . " $count";
        }
        return $output;
    }

    private function cmdChart(array $args): array
    {
        [$day, $result] = $this->resultForDay($args);
        $capacity = $result->settings['CAPACITY'];
        $output = ["CHART day $day " . $this->data->dayNames[$day - 1] .
                   ' strategy ' . strategyText($result->strategy)];
        foreach ($result->days[$day - 1] as $record) {
            $width = intdiv(20 * $record->soc, $capacity);
            $output[] = str_pad((string) $record->hour, 2, ' ', STR_PAD_LEFT) .
                        ' ' . bar($width) . ' ' . percentage($record->soc, $capacity) . '%';
        }
        return $output;
    }
}

$lines = file('php://stdin', FILE_IGNORE_NEW_LINES);
$data = new InputData($lines);
$desk = new DispatchDesk($data);
$output = [];
foreach ($data->commands as $line) {
    $tokens = explode(' ', $line);
    if ($tokens[0] === 'END') break;
    array_push($output, ...$desk->execute($tokens));
}
if ($output) echo implode("\n", $output) . "\n";
