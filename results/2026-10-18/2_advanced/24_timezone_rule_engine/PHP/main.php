<?php
declare(strict_types=1);

namespace TimezoneRules;

require_once __DIR__ . '/day_rules.php';
require_once __DIR__ . '/tz_parser.php';
require_once __DIR__ . '/transitions.php';
require_once __DIR__ . '/resolver.php';
require_once __DIR__ . '/report.php';

const FIELD_COUNTS = ['Rule' => [10, 10], 'Zone' => [5, 9], 'continuation' => [3, 7], 'Link' => [3, 3]];
const ARGUMENT_KINDS = ['TOUTC' => ['zone', 'local'], 'TOLOCAL' => ['zone', 'ut'], 'CONVERT' => ['zone', 'zone', 'local'],
    'OFFSET' => ['zone', 'ut'], 'TRANSITIONS' => ['zone', 'year', 'year'], 'DURATION' => ['zone', 'local', 'local']];

function readLines(string $path): array { return file($path, FILE_IGNORE_NEW_LINES); }
function yearStart(int $year): int { return dayNumber($year, 1, 1) * 86400; }
function clockSeconds(string $text): int { return (int)substr($text, 0, 2) * 3600 + (int)substr($text, 3, 2) * 60; }
function namesOrNone(array $names, string $separator): string { return $names === [] ? 'none' : implode($separator, $names); }

function indented(array $lines): array
{
    foreach ($lines as $index => $line) {
        if ($index > 0) {
            $lines[$index] = '  ' . $line;
        }
    }
    return $lines;
}

function mergeIntervals(array $intervals): array
{
    usort($intervals, static fn(array $a, array $b): int => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));
    $merged = [];
    foreach ($intervals as [$low, $high]) {
        $last = count($merged) - 1;
        if ($last >= 0 && $low <= $merged[$last][1]) {
            $merged[$last][1] = max($merged[$last][1], $high);
        } else {
            $merged[] = [$low, $high];
        }
    }
    return $merged;
}

function intersectIntervals(array $first, array $second): array
{
    $pieces = [];
    foreach ($first as [$firstLow, $firstHigh]) {
        foreach ($second as [$secondLow, $secondHigh]) {
            $low = max($firstLow, $secondLow);
            $high = min($firstHigh, $secondHigh);
            if ($low < $high) {
                $pieces[] = [$low, $high];
            }
        }
    }
    return mergeIntervals($pieces);
}

final class SourceLine
{
    public array $fields;
    public string $kind;
    public ?Block $block = null;
    public int $position = 0;
    public ?ZoneLine $zoneLine = null;
    public bool $fieldError = false;
    public ?string $error = null;

    public function __construct(public int $number, string $content)
    {
        $this->fields = splitFields($content);
        $this->kind = isContinuation($content) ? 'continuation' : (in_array($this->fields[0], ['Rule', 'Zone', 'Link'], true) ? $this->fields[0] : 'unknown');
    }

    public function acceptsContinuation(): bool
    {
        return $this->kind === 'Zone' && count($this->fields) >= 6 || $this->kind === 'continuation' && count($this->fields) >= 4;
    }
}

final class Block
{
    public string $name;
    public int $number;
    public array $lines = [];
    public bool $defined = false;

    public function __construct(SourceLine $first)
    {
        $this->name = $first->fields[1];
        $this->number = $first->number;
        $this->add($first);
    }

    public function add(SourceLine $line): void
    {
        $line->block = $this;
        $line->position = count($this->lines);
        $this->lines[] = $line;
    }
}

final class ZoneLine
{
    public int $stdoff;
    public string $rulesText;
    public ?string $ruleSet = null;
    public int $save = 0;
    public string $format;
    public ?UntilSpec $until = null;
    public int $start = NEG_INFINITY;
    public int $end = POS_INFINITY;

    public function __construct(array $fields)
    {
        $this->stdoff = parseStdoff($fields[0]);
        $this->rulesText = $fields[1];
        if ($this->rulesText[0] >= '0' && $this->rulesText[0] <= '9') {
            $this->save = parseSave($this->rulesText);
        } elseif ($this->rulesText !== '-') {
            $this->ruleSet = $this->rulesText;
        }
        $this->format = $fields[2];
        checkFormat($this->format, $this->ruleSet !== null);
        if (count($fields) > 3) {
            $this->until = parseUntil(array_slice($fields, 3));
        }
    }

    public function rulesNotation(): string { return $this->ruleSet ?? ($this->rulesText === '-' ? '-' : clockText($this->save)); }

    public function untilNotation(): string
    {
        $until = $this->until;
        return $until->yearText . ' ' . $until->monthText . ' ' . $until->dayText . ' ' . clockText($until->time) . $until->timeType;
    }
}

final class Zone
{
    public array $aliases = [];
    public array $applied = [];
    public Timeline $timeline;

    public function __construct(public string $name, public array $lines) {}

    public function ruleSets(): array
    {
        $names = [];
        foreach ($this->lines as $line) {
            if ($line->ruleSet !== null && !in_array($line->ruleSet, $names, true)) {
                $names[] = $line->ruleSet;
            }
        }
        return $names;
    }

    public function lineNumberAt(int $time): ?int
    {
        foreach ($this->lines as $index => $line) {
            if ($line->start <= $time && $time < $line->end) {
                return $index + 1;
            }
        }
        return null;
    }
}

function parseRule(SourceLine $line): Rule
{
    $fields = $line->fields;
    $from = parseYear($fields[2]);
    $to = parseTo($fields[3], $from);
    if ($fields[4] !== '-') {
        throw new FieldError('syntax error');
    }
    $month = parseMonth($fields[5]);
    $day = parseDaySpec($fields[6], $month);
    [$at, $atType] = parseTime($fields[7]);
    $save = parseSave($fields[8]);
    $letter = parseLetter($fields[9]);
    return new Rule($line->number, $fields, $from, $to, $month, $day, $at, $atType, $save, $letter);
}

function standardLetter(array $instances): string
{
    foreach ($instances as $instance) {
        if ($instance->rule->save === 0) {
            return $instance->rule->letter;
        }
    }
    return '';
}

final class Database
{
    public array $lines = [];
    public array $blocks = [];
    public array $rules = [];
    public array $sequences = [];
    public array $zones = [];
    public array $aliases = [];

    public function __construct(array $rawLines)
    {
        foreach ($rawLines as $index => $raw) {
            $content = lineContent($raw);
            if ($content !== '') {
                $this->lines[] = new SourceLine($index + 1, $content);
            }
        }
        $this->assembleBlocks();
        foreach ($this->lines as $line) {
            try {
                $this->parseFields($line);
            } catch (FieldError $error) {
                $line->fieldError = true;
                $line->error = $error->getMessage();
            }
        }
        $zoneNames = [];
        foreach ($this->lines as $line) {
            if ($line->zoneLine !== null) {
                $line->error = $this->structuralError($line, $zoneNames);
            }
        }
        foreach ($this->rules as $name => $rules) {
            $this->sequences[$name] = instanceSequence($rules);
        }
        foreach ($this->blocks as $block) {
            $block->defined = true;
            foreach ($block->lines as $line) {
                if ($line->error !== null) {
                    $block->defined = false;
                }
            }
            if ($block->defined) {
                $this->defineZone($block);
            }
        }
        foreach ($this->lines as $line) {
            if ($line->kind === 'Link' && $line->error === null) {
                $this->registerLink($line);
            }
        }
    }

    private function assembleBlocks(): void
    {
        $previous = null;
        foreach ($this->lines as $line) {
            if ($line->kind === 'Zone') {
                $this->blocks[] = new Block($line);
            } elseif ($line->kind === 'continuation' && $previous !== null && $previous->block !== null && $previous->acceptsContinuation()) {
                $previous->block->add($line);
            }
            $previous = $line;
        }
    }

    private function parseFields(SourceLine $line): void
    {
        if ($line->kind === 'unknown' || $line->kind === 'continuation' && $line->block === null) {
            throw new FieldError('syntax error');
        }
        [$low, $high] = FIELD_COUNTS[$line->kind];
        if (count($line->fields) < $low || count($line->fields) > $high) {
            throw new FieldError('syntax error');
        }
        if ($line->kind === 'Rule') {
            $rule = parseRule($line);
            $this->rules[$rule->name][] = $rule;
        } elseif ($line->kind === 'Zone') {
            $line->zoneLine = new ZoneLine(array_slice($line->fields, 2));
        } elseif ($line->kind === 'continuation') {
            $line->zoneLine = new ZoneLine($line->fields);
        }
    }

    private function structuralError(SourceLine $line, array &$zoneNames): ?string
    {
        $zoneLine = $line->zoneLine;
        if ($line->kind === 'Zone') {
            $name = $line->fields[1];
            if (isset($zoneNames[$name])) {
                return 'duplicate zone ' . $name;
            }
            $zoneNames[$name] = true;
        }
        if ($zoneLine->ruleSet !== null && !isset($this->rules[$zoneLine->ruleSet])) {
            return 'unknown rule ' . $zoneLine->ruleSet;
        }
        if ($zoneLine->until === null) {
            return null;
        }
        if ($line->kind === 'continuation') {
            $previous = $line->block->lines[$line->position - 1];
            if (!$previous->fieldError && $zoneLine->until->value <= $previous->zoneLine->until->value) {
                return 'until not increasing';
            }
        }
        return $line->position === count($line->block->lines) - 1 ? 'missing continuation' : null;
    }

    private function lineSwitches(Zone $zone, ZoneLine $line): array
    {
        $until = $line->until;
        if ($line->ruleSet === null) {
            if ($until !== null) {
                $line->end = $until->value - adjustment($until->timeType, $line->stdoff, $line->save);
            }
            return [[$line->start, $line->save, '']];
        }
        $instances = $this->sequences[$line->ruleSet];
        $run = runInstances($instances, $line->stdoff, $line->start, $until);
        $line->end = $run->end;
        if ($run->preStart !== []) {
            $last = $run->preStart[count($run->preStart) - 1];
            $switches = [[$line->start, $last->save, $last->letter]];
        } else {
            $switches = [[$line->start, 0, standardLetter($instances)]];
        }
        foreach ($run->applied as [$time, $rule]) {
            $switches[] = [$time, $rule->save, $rule->letter];
            $zone->applied[$rule->number] = ($zone->applied[$rule->number] ?? 0) + 1;
        }
        return $switches;
    }

    private function defineZone(Block $block): void
    {
        $zone = new Zone($block->name, array_map(static fn(SourceLine $line): ZoneLine => $line->zoneLine, $block->lines));
        $periods = [];
        $start = NEG_INFINITY;
        foreach ($zone->lines as $line) {
            $line->start = $start;
            foreach ($this->lineSwitches($zone, $line) as [$time, $save, $letter]) {
                $period = new Period($time, $line->stdoff + $save, $save !== 0, abbreviation($line->format, $save, $letter));
                if ($periods === [] || $periods[count($periods) - 1]->state() !== $period->state()) {
                    $periods[] = $period;
                }
            }
            $start = $line->end;
        }
        $zone->timeline = new Timeline($periods);
        $this->zones[$zone->name] = $zone;
    }

    private function registerLink(SourceLine $line): void
    {
        [$target, $alias] = array_slice($line->fields, 1);
        if (!isset($this->zones[$target])) {
            $line->error = 'unknown link target ' . $target;
        } elseif (isset($this->zones[$alias]) || isset($this->aliases[$alias])) {
            $line->error = 'duplicate link ' . $alias;
        } else {
            $this->aliases[$alias] = $this->zones[$target];
            $this->zones[$target]->aliases[] = $alias;
        }
    }

    public function findZone(string $word): ?Zone { return $this->zones[$word] ?? $this->aliases[$word] ?? null; }

    public function errorLines(): array
    {
        $lines = [];
        foreach ($this->lines as $line) {
            if ($line->error !== null) {
                $lines[] = 'line ' . $line->number . ': ' . $line->error;
            }
        }
        return $lines;
    }
}

function offsetShift(Timeline $timeline, int $index): int { return $timeline->periods[$index]->offset - $timeline->periods[$index - 1]->offset; }

function transitionsBetween(Timeline $timeline, int $low, int $high): array
{
    $indices = [];
    for ($index = 1; $index < count($timeline->periods); $index++) {
        if ($low <= $timeline->periods[$index]->start && $timeline->periods[$index]->start < $high) {
            $indices[] = $index;
        }
    }
    return $indices;
}

function changeAt(Timeline $timeline, int $index): string { return changeText($timeline->periods[$index]->start, $timeline->periods[$index - 1], $timeline->periods[$index]); }

function transitionLine(Timeline $timeline, int $index): string
{
    $time = $timeline->periods[$index]->start;
    $shift = offsetShift($timeline, $index);
    $kind = $shift > 0 ? 'gap ' . durationText($shift) : ($shift < 0 ? 'overlap ' . durationText(-$shift) : 'no shift');
    return changeAt($timeline, $index) . ' (local ' . localText($time + $timeline->periods[$index - 1]->offset)
        . ' -> ' . localText($time + $timeline->periods[$index]->offset) . ", $kind)";
}

function shiftsText(Timeline $timeline, array $indices): string
{
    $gaps = $overlaps = $unchanged = 0;
    foreach ($indices as $index) {
        $shift = offsetShift($timeline, $index);
        $gaps += (int)($shift > 0);
        $overlaps += (int)($shift < 0);
        $unchanged += (int)($shift === 0);
    }
    return "gaps $gaps, overlaps $overlaps, no shift $unchanged";
}

function candidateText(Timeline $timeline, int $local, int $index): string
{
    $period = $timeline->periods[$index];
    return utText($local - $period->offset) . ' (' . stateText($period) . ')';
}

function chosenCandidate(array $candidates, ?string $option): ?int
{
    if (count($candidates) === 1 || count($candidates) === 2 && $option === 'EARLIER') {
        return $candidates[0];
    }
    return count($candidates) === 2 && $option === 'LATER' ? $candidates[1] : null;
}

function unresolvedText(Timeline $timeline, int $local, array $candidates): string
{
    if ($candidates !== []) {
        return 'AMBIGUOUS ' . implode(' or ', array_map(static fn(int $index): string => candidateText($timeline, $local, $index), $candidates));
    }
    $index = $timeline->skippingTransition($local);
    $time = $timeline->periods[$index]->start;
    return 'NONEXISTENT gap ' . localText($time + $timeline->periods[$index - 1]->offset) . ' to '
        . localText($time + $timeline->periods[$index]->offset) . ' at ' . utText($time);
}

function workingHours(Timeline $timeline, int $start, int $end): array
{
    $pieces = [];
    [$first, $last] = $timeline->nearby($start, $end);
    for ($index = $first; $index <= $last; $index++) {
        $period = $timeline->periods[$index];
        $low = max($start - $period->offset, $period->start);
        $high = min($end - $period->offset, $timeline->endOf($index));
        if ($low < $high) {
            $pieces[] = [$low, $high];
        }
    }
    return mergeIntervals($pieces);
}

function parseValue(string $kind, string $word): ?int
{
    $year = (int)substr($word, 0, 4);
    if ($year < 1800 || $year > 2099) {
        return null;
    }
    if ($kind === 'year') {
        return $year;
    }
    $month = (int)substr($word, 5, 2);
    $day = (int)substr($word, 8, 2);
    if ($month < 1 || $month > 12 || $day < 1 || $day > daysInMonth($year, $month)) {
        return null;
    }
    if ($kind === 'date') {
        return dayNumber($year, $month, $day);
    }
    $hour = (int)substr($word, 11, 2);
    $minute = (int)substr($word, 14, 2);
    $second = (int)substr($word, 17, 2);
    if ($hour > 23 || $minute > 59 || $second > 59) {
        return null;
    }
    return timeValue($year, $month, $day, $hour, $minute, $second);
}

final class QueryError extends \Exception {}

final class QueryRunner
{
    public array $answers = [];
    public array $transitionBlocks = [];

    public function __construct(private Database $database, private int $workStart, private int $workEnd) {}

    private function argument(string $kind, string $word): Zone|int
    {
        if ($kind === 'zone') {
            $zone = $this->database->findZone($word);
            if ($zone === null) {
                throw new QueryError('unknown zone ' . $word);
            }
            return $zone;
        }
        $value = parseValue($kind, $word);
        if ($value === null) {
            throw new QueryError('invalid value ' . $word);
        }
        return $value;
    }

    public function run(string $line): void
    {
        $words = explode(' ', $line);
        $command = array_shift($words);
        $option = null;
        if (in_array($command, ['TOUTC', 'CONVERT'], true) && in_array($words[count($words) - 1], ['EARLIER', 'LATER'], true)) {
            $option = array_pop($words);
        }
        $kinds = $command === 'MEETING' ? array_merge(['date'], array_fill(0, count($words) - 1, 'zone')) : ARGUMENT_KINDS[$command];
        try {
            $values = [];
            foreach ($kinds as $index => $kind) {
                $values[] = $this->argument($kind, $words[$index]);
            }
            $result = $this->answer($line, $command, $values, $words, $option);
        } catch (QueryError $error) {
            $result = 'ERROR ' . $error->getMessage();
        }
        $this->answers[] = $line . ' => ' . $result;
    }

    private function answer(string $line, string $command, array $values, array $words, ?string $option): string
    {
        return match ($command) {
            'TOUTC' => $this->toUtc($values[0], $values[1], $option),
            'TOLOCAL' => $this->toLocal($values[0], $values[1]),
            'CONVERT' => $this->convert($values[0], $values[1], $values[2], $option),
            'OFFSET' => $this->offset($values[0], $values[1]),
            'TRANSITIONS' => $this->transitions($line, $values[0], $values[1], $values[2]),
            'DURATION' => $this->duration($values[0], array_slice($values, 1), array_slice($words, 1)),
            default => $this->meeting($values[0], array_slice($values, 1), array_slice($words, 1)),
        };
    }

    private function toUtc(Zone $zone, int $local, ?string $option): string
    {
        $candidates = $zone->timeline->candidates($local);
        $index = chosenCandidate($candidates, $option);
        return $index === null ? unresolvedText($zone->timeline, $local, $candidates) : candidateText($zone->timeline, $local, $index);
    }

    private function toLocal(Zone $zone, int $time): string
    {
        $period = $zone->timeline->periodAt($time);
        return localText($time + $period->offset) . ' (' . stateText($period) . ')';
    }

    private function convert(Zone $source, Zone $target, int $local, ?string $option): string
    {
        $candidates = $source->timeline->candidates($local);
        $index = chosenCandidate($candidates, $option);
        if ($index === null) {
            return unresolvedText($source->timeline, $local, $candidates);
        }
        $time = $local - $source->timeline->periods[$index]->offset;
        $period = $target->timeline->periodAt($time);
        $targetLocal = $time + $period->offset;
        $shift = floorDiv($targetLocal, 86400) - floorDiv($local, 86400);
        $shiftText = $shift > 0 ? '+' . $shift : (string)$shift;
        return localText($targetLocal) . ' (' . stateText($period) . ') at ' . utText($time) . ", day shift $shiftText";
    }

    private function offset(Zone $zone, int $time): string
    {
        $timeline = $zone->timeline;
        $index = $timeline->indexAt($time);
        $text = stateText($timeline->periods[$index]);
        if ($index >= 1) {
            $text .= ' since ' . utText($timeline->periods[$index]->start);
        }
        if ($index + 1 < count($timeline->periods)) {
            $text .= ' until ' . utText($timeline->periods[$index + 1]->start);
        }
        return $text;
    }

    private function transitions(string $line, Zone $zone, int $firstYear, int $lastYear): string
    {
        if ($firstYear > $lastYear) {
            throw new QueryError('invalid range');
        }
        $timeline = $zone->timeline;
        $selected = transitionsBetween($timeline, yearStart($firstYear), yearStart($lastYear + 1));
        $block = [$line];
        foreach ($selected as $index) {
            $block[] = transitionLine($timeline, $index);
        }
        $block[] = shiftsText($timeline, $selected);
        $this->transitionBlocks[] = $block;
        return 'transitions: ' . count($selected);
    }

    private function duration(Zone $zone, array $locals, array $words): string
    {
        $periods = [];
        foreach ($locals as $index => $local) {
            $candidates = $zone->timeline->candidates($local);
            if (count($candidates) === 2) {
                return 'AMBIGUOUS ' . $words[$index];
            }
            if ($candidates === []) {
                return 'NONEXISTENT ' . $words[$index];
            }
            $periods[] = $zone->timeline->periods[$candidates[0]];
        }
        $elapsed = ($locals[1] - $periods[1]->offset) - ($locals[0] - $periods[0]->offset);
        return $elapsed . ' s (' . durationText($elapsed) . '), wall clock ' . durationText($locals[1] - $locals[0])
            . ', offset change ' . offsetText($periods[1]->offset - $periods[0]->offset);
    }

    private function meeting(int $day, array $zones, array $words): string
    {
        $start = $day * 86400 + $this->workStart;
        $end = $day * 86400 + $this->workEnd;
        $common = workingHours($zones[0]->timeline, $start, $end);
        foreach (array_slice($zones, 1) as $zone) {
            $common = intersectIntervals($common, workingHours($zone->timeline, $start, $end));
        }
        if ($common === []) {
            return 'NONE';
        }
        $parts = [];
        foreach ($common as [$low, $high]) {
            $members = [];
            foreach ($zones as $index => $zone) {
                $period = $zone->timeline->periodAt($low);
                $members[] = $words[$index] . ' ' . localText($low + $period->offset) . ' ' . $period->abbreviation;
            }
            $parts[] = utText($low) . ' to ' . utText($high) . ' (' . durationText($high - $low) . ') [' . implode(', ', $members) . ']';
        }
        return implode('; ', $parts);
    }
}

function ruleText(Rule $rule): string
{
    $fields = $rule->fields;
    return 'rule ' . $rule->name . ' ' . $fields[2] . ' ' . $fields[3] . ' ' . $fields[5] . ' ' . $fields[6]
        . ' ' . clockText($rule->at) . $rule->atType . ' ' . clockText($rule->save) . ' ' . $fields[9];
}

function databaseBlock(Database $database): array
{
    $ruleCount = $validRules = $linkCount = $validLinks = 0;
    foreach ($database->lines as $line) {
        if ($line->kind === 'Rule') {
            $ruleCount++;
            $validRules += (int)($line->error === null);
        }
        if ($line->kind === 'Link') {
            $linkCount++;
            $validLinks += (int)($line->error === null);
        }
    }
    $used = $usage = $unused = $invalid = [];
    $zoneLines = 0;
    foreach ($database->zones as $zone) {
        $zoneLines += count($zone->lines);
        foreach ($zone->ruleSets() as $name) {
            $used[$name] = true;
            $usage[$name] = ($usage[$name] ?? 0) + 1;
        }
    }
    foreach ($database->rules as $name => $rules) {
        if (!isset($used[$name])) {
            $unused[] = $name;
        }
    }
    foreach ($database->blocks as $block) {
        if (!$block->defined) {
            $invalid[] = $block->name . ' (line ' . $block->number . ')';
        }
    }
    $defined = count($database->zones);
    $lines = ['DATABASE', "rule lines: $validRules valid, " . ($ruleCount - $validRules) . ' invalid',
        "zones: $defined defined, " . (count($database->blocks) - $defined) . ' invalid', "zone lines: $zoneLines in defined zones",
        "links: $validLinks defined, " . ($linkCount - $validLinks) . ' invalid', 'errors: ' . count($database->errorLines()),
        'unused rules: ' . namesOrNone($unused, ' '), 'invalid zones: ' . namesOrNone($invalid, ', ')];
    foreach ($database->rules as $name => $rules) {
        $first = 2099;
        $last = 1800;
        $maximum = false;
        foreach ($rules as $rule) {
            $first = min($first, $rule->fromYear);
            $last = max($last, $rule->toYear);
            $maximum = $maximum || $rule->fields[3] === 'max';
        }
        $lastText = $maximum ? 'max' : (string)$last;
        $lines[] = "rule set $name: lines " . count($rules) . ", years $first-$lastText, zones " . ($usage[$name] ?? 0);
    }
    return $lines;
}

function dstLines(Timeline $timeline, int $reference): array
{
    $indices = $years = [];
    foreach ($timeline->periods as $index => $period) {
        if ($period->dst) {
            $indices[] = $index;
            $years[] = splitTime($period->start)[0];
        }
    }
    $lines = [$years === [] ? 'dst years: none' : 'dst years: ' . min($years) . '-' . max($years)];
    $year = splitTime($reference)[0];
    $low = yearStart($year);
    $high = yearStart($year + 1);
    $pieces = [];
    foreach ($indices as $index) {
        $start = max($low, $timeline->periods[$index]->start);
        $end = min($high, $timeline->endOf($index));
        if ($start < $end) {
            $pieces[] = [$start, $end];
        }
    }
    $total = 0;
    foreach (mergeIntervals($pieces) as [$start, $end]) {
        $lines[] = 'dst period: ' . utText($start) . ' to ' . utText($end) . ' (' . durationText($end - $start) . ')';
        $total += $end - $start;
    }
    $lines[] = "dst total $year: " . durationText($total);
    return $lines;
}

function zoneBlock(Database $database, Zone $zone, int $reference): array
{
    $timeline = $zone->timeline;
    $periods = $timeline->periods;
    $lines = ['ZONE ' . $zone->name, 'aliases: ' . namesOrNone($zone->aliases, ' ')];
    foreach ($zone->lines as $index => $line) {
        $text = 'line ' . ($index + 1) . ': ' . offsetText($line->stdoff) . ' ' . $line->rulesNotation() . ' ' . $line->format;
        if ($index >= 1) {
            $text .= ' from ' . utText($line->start);
        }
        if ($line->until !== null) {
            $text .= ' until ' . $line->untilNotation() . ' = ' . utText($line->end);
        }
        $lines[] = $text . ', transitions ' . count(transitionsBetween($timeline, $line->start, $line->end));
    }
    foreach ($zone->ruleSets() as $name) {
        foreach ($database->rules[$name] as $rule) {
            $lines[] = ruleText($rule) . ', applied ' . ($zone->applied[$rule->number] ?? 0);
        }
    }
    $offsets = array_map(static fn(Period $period): int => $period->offset, $periods);
    $lines[] = 'offset range: ' . offsetText(min($offsets)) . ' to ' . offsetText(max($offsets));
    $stateCounts = $stateOrder = [];
    foreach ($periods as $period) {
        $state = stateText($period);
        $key = '#' . $state;
        if (!isset($stateCounts[$key])) {
            $stateCounts[$key] = 0;
            $stateOrder[] = $state;
        }
        $stateCounts[$key]++;
    }
    foreach ($stateOrder as $state) {
        $lines[] = "state $state, periods " . $stateCounts['#' . $state];
    }
    $index = $timeline->indexAt($reference);
    $period = $periods[$index];
    $lines[] = 'reference: ' . localText($reference + $period->offset) . ' (' . stateText($period) . '), line ' . $zone->lineNumberAt($reference);
    $lines[] = 'previous transition: ' . ($index >= 1 ? changeAt($timeline, $index) : 'none');
    $lines[] = 'next transition: ' . ($index + 1 < count($periods) ? changeAt($timeline, $index + 1) : 'none');
    $every = [];
    for ($position = 1; $position < count($periods); $position++) {
        $every[] = $position;
    }
    $lines[] = 'transitions: ' . count($every) . ', ' . shiftsText($timeline, $every);
    array_push($lines, ...dstLines($timeline, $reference));
    return $lines;
}

$database = new Database(readLines('input/tzdata.txt'));
$params = readLines('input/params.txt');
$reference = parseValue('ut', explode(' ', $params[0])[1]);
$workday = explode(' ', $params[1]);
$runner = new QueryRunner($database, clockSeconds($workday[1]), clockSeconds($workday[2]));
foreach (readLines('input/queries.txt') as $line) {
    $runner->run($line);
}
$blocks = [indented(databaseBlock($database))];
$names = array_keys($database->zones);
usort($names, 'strcmp');
foreach ($names as $name) {
    $blocks[] = indented(zoneBlock($database, $database->zones[$name], $reference));
}
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
writeLines('output/answers.txt', $runner->answers);
writeLines('output/errors.txt', $database->errorLines());
writeBlocks('output/transitions.txt', $runner->transitionBlocks);
writeBlocks('output/zone_summary.txt', $blocks);
