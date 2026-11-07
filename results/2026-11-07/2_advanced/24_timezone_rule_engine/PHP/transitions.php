<?php
declare(strict_types=1);

namespace TimezoneRules;

final class Rule
{
    public string $name;

    public function __construct(public int $number, public array $fields, public int $fromYear, public int $toYear,
        public int $month, public DaySpec $day, public int $at, public string $atType, public int $save, public string $letter)
    {
        $this->name = $fields[1];
    }
}

final class RuleInstance
{
    public function __construct(public Rule $rule, public int $nominal) {}
}

final class LineRun
{
    public array $preStart = [];
    public array $applied = [];
    public int $end = POS_INFINITY;
}

function instanceSequence(array $rules): array
{
    $instances = [];
    foreach ($rules as $rule) {
        for ($year = $rule->fromYear; $year <= $rule->toYear; $year++) {
            $instances[] = new RuleInstance($rule, $rule->day->value($year, $rule->month) * 86400 + $rule->at);
        }
    }
    usort($instances, static fn(RuleInstance $a, RuleInstance $b): int => ($a->nominal <=> $b->nominal) ?: ($a->rule->number <=> $b->rule->number));
    return $instances;
}

function adjustment(string $timeType, int $stdoff, int $save): int
{
    return match ($timeType) { 'u' => 0, 's' => $stdoff, default => $stdoff + $save };
}

function runInstances(array $instances, int $stdoff, int $start, ?UntilSpec $until): LineRun
{
    $run = new LineRun();
    $save = 0;
    foreach ($instances as $instance) {
        $rule = $instance->rule;
        $time = $instance->nominal - adjustment($rule->atType, $stdoff, $save);
        if ($until !== null && $time >= $until->value - adjustment($until->timeType, $stdoff, $save)) {
            break;
        }
        if ($time <= $start) {
            $run->preStart[] = $rule;
        } else {
            $run->applied[] = [$time, $rule];
        }
        $save = $rule->save;
    }
    if ($until !== null) {
        $run->end = $until->value - adjustment($until->timeType, $stdoff, $save);
    }
    return $run;
}

function abbreviation(string $format, int $save, string $letter): string
{
    if (str_contains($format, '/')) {
        [$standard, $daylight] = explode('/', $format, 2);
        return $save === 0 ? $standard : $daylight;
    }
    return str_replace('%s', $letter, $format);
}
