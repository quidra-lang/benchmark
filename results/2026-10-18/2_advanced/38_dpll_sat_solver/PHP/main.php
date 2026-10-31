<?php

require_once __DIR__ . '/cnf_io.php';
require_once __DIR__ . '/encoders.php';
require_once __DIR__ . '/preprocess.php';
require_once __DIR__ . '/dpll.php';
require_once __DIR__ . '/report.php';

const ARGUMENTS = ['SOLVE' => ['file'], 'ENUM' => ['file', 'limit'], 'CORE' => ['file'],
    'QUEENS' => ['size', 'limit'], 'PIGEON' => ['pigeons', 'holes', 'limit'],
    'COLOR' => ['graph', 'colors', 'limit'], 'CHROMATIC' => ['graph', 'maximum']];
const NUMBER_LIMITS = ['size' => 8, 'pigeons' => 8, 'holes' => 8, 'colors' => 6, 'maximum' => 6, 'limit' => 200];
const STAT_COLUMNS = ['job', 'command', 'status', 'variables', 'clauses', 'removed_clauses',
    'decisions', 'propagations', 'conflicts', 'max_depth', 'models', 'rounds'];

function emptyStatistics(): object
{
    return (object) ['decisions' => 0, 'propagations' => 0, 'conflicts' => 0, 'maxDepth' => 0];
}

function addStatistics(object $total, object $part): void
{
    $total->decisions += $part->decisions;
    $total->propagations += $part->propagations;
    $total->conflicts += $part->conflicts;
    $total->maxDepth = max($total->maxDepth, $part->maxDepth);
}

function analyzeGraph(object $graph): void
{
    $adjacent = array_fill(0, $graph->vertices + 1, []);
    foreach ($graph->edges as [$first, $second]) {
        $adjacent[$first][] = $second;
        $adjacent[$second][] = $first;
    }
    $order = range(1, $graph->vertices);
    usort($order, fn($first, $second) => (count($adjacent[$second]) <=> count($adjacent[$first])) ?: ($first <=> $second));
    $colors = array_fill(0, $graph->vertices + 1, 0);
    $maximumDegree = $used = 0;
    foreach ($order as $vertex) {
        $maximumDegree = max($maximumDegree, count($adjacent[$vertex]));
        $unavailable = [];
        foreach ($adjacent[$vertex] as $neighbor) $unavailable[$colors[$neighbor]] = true;
        $color = 1;
        while (isset($unavailable[$color])) $color++;
        $colors[$vertex] = $color;
        $used = max($used, $color);
    }
    $graph->maximumDegree = $maximumDegree;
    $graph->greedy = (object) ['used' => $used, 'colors' => array_slice($colors, 1)];
}

function readGraphs(): array
{
    $graphs = [];
    $graph = null;
    $seen = [];
    foreach (file('input/graphs.txt', FILE_IGNORE_NEW_LINES) as $index => $line) {
        if ($graph === null) {
            if ($line === '' || str_starts_with($line, '#')) continue;
            [, $name, $vertices] = explode(' ', $line);
            $graph = (object) ['name' => $name, 'vertices' => (int) $vertices, 'edges' => [], 'reason' => null];
            $graphs[$name] = $graph;
            $seen = [];
            continue;
        }
        if ($line === 'END') {
            if ($graph->reason === null) {
                usort($graph->edges, fn($first, $second) => ($first[0] <=> $second[0]) ?: ($first[1] <=> $second[1]));
                analyzeGraph($graph);
            }
            $graph = null;
            continue;
        }
        if ($graph->reason !== null) continue;
        $tokens = explode(' ', $line);
        $reason = null;
        if (count($tokens) !== 2 || !wellFormedNumber($tokens[0]) || !wellFormedNumber($tokens[1])) $reason = 'bad edge line';
        else {
            $first = (int) $tokens[0];
            $second = (int) $tokens[1];
            $edge = [min($first, $second), max($first, $second)];
            $key = implode(',', $edge);
            if ($first < 1 || $first > $graph->vertices || $second < 1 || $second > $graph->vertices) $reason = 'vertex out of range';
            elseif ($first === $second) $reason = 'self loop';
            elseif (isset($seen[$key])) $reason = 'duplicate edge';
            else {
                $graph->edges[] = $edge;
                $seen[$key] = true;
            }
        }
        if ($reason !== null) $graph->reason = $reason . ' at line ' . ($index + 1);
    }
    return $graphs;
}

function readJobs(): array
{
    $jobs = [];
    foreach (file('input/jobs.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || str_starts_with($line, '#')) continue;
        $arguments = explode(' ', $line);
        $command = array_shift($arguments);
        $jobs[] = (object) ['number' => count($jobs) + 1, 'line' => $line, 'command' => $command, 'arguments' => $arguments, 'error' => null];
    }
    return $jobs;
}

function validateJob(object $job, array $graphs): void
{
    if (!isset(ARGUMENTS[$job->command])) throw new InputError('unknown command ' . $job->command);
    $kinds = ARGUMENTS[$job->command];
    if (count($job->arguments) !== count($kinds)) throw new InputError('wrong argument count');
    foreach ($kinds as $index => $kind) {
        $token = $job->arguments[$index];
        if ($kind === 'file') {
            if (!preg_match('/\A[a-z0-9_]{1,20}\.cnf\z/', $token)) throw new InputError('bad file name ' . $token);
            $job->file = $token;
        } elseif ($kind === 'graph') {
            if (!isset($graphs[$token])) throw new InputError('unknown graph ' . $token);
            $job->graph = $graphs[$token];
            if ($job->graph->reason !== null) throw new InputError('invalid graph ' . $token . ': ' . $job->graph->reason);
        } else {
            if (!wellFormedNumber($token)) throw new InputError('bad number ' . $token);
            $value = (int) $token;
            if ($value < 1 || $value > NUMBER_LIMITS[$kind]) throw new InputError('out of range ' . $token);
            $job->$kind = $value;
        }
    }
    if (!isset($job->limit)) $job->limit = 1;
}

function originalFormula(object $job): object
{
    if (isset($job->file)) return readDimacs('input/' . $job->file);
    if ($job->command === 'QUEENS') return queens($job->size);
    if ($job->command === 'PIGEON') return pigeon($job->pigeons, $job->holes);
    return coloring($job->graph, $job->colors);
}

function solveFormula(object $formula, int $limit): object
{
    $simplified = preprocess($formula, $limit === 1);
    $result = (object) ['formula' => $formula, 'preprocessing' => $simplified, 'models' => [], 'rounds' => 0,
        'stop' => 'limit', 'status' => 'UNSAT', 'statistics' => emptyStatistics(), 'trace' => [], 'removed' => $simplified->removed];
    if ($simplified->emptyClause !== null) {
        $result->stop = 'preprocess';
        return $result;
    }
    $blocking = [];
    while (count($result->models) < $limit) {
        $round = solveRound($formula->variables, array_merge($simplified->clauses, $blocking));
        $result->rounds++;
        if ($result->rounds === 1) $result->trace = $round->events;
        addStatistics($result->statistics, $round->statistics);
        if (!$round->satisfiable) {
            $result->stop = 'all';
            break;
        }
        $model = array_fill(0, $formula->variables + 1, false);
        for ($variable = 1; $variable <= $formula->variables; $variable++) {
            $model[$variable] = $simplified->fixed[$variable] === null ? $round->model[$variable] : $simplified->fixed[$variable];
        }
        $result->models[] = $model;
        $blocking[] = array_map(fn($variable) => $model[$variable] ? -$variable : $variable, $simplified->active);
    }
    if ($result->models) $result->status = 'SAT';
    return $result;
}

function literalTrue(int $literal, array $model, int $flipped = 0): bool
{
    $variable = abs($literal);
    $value = $variable === $flipped ? !$model[$variable] : $model[$variable];
    return $literal > 0 ? $value : !$value;
}

function clauseSatisfied(array $clause, array $model, int $flipped = 0): bool
{
    foreach ($clause as $literal) if (literalTrue($literal, $model, $flipped)) return true;
    return false;
}

function analyzeModels(object $result): ?object
{
    $formula = $result->formula;
    $models = $result->models;
    if (!$models) return null;
    $failure = null;
    foreach ($models as $index => $model) {
        foreach ($formula->clauses as $clause => $literals) {
            if (!clauseSatisfied($literals, $model)) {
                $failure = (object) ['model' => $index + 1, 'clause' => $clause + 1];
                break 2;
            }
        }
    }
    $distribution = [];
    foreach ($formula->clauses as $clause) {
        $count = 0;
        foreach ($clause as $literal) if (literalTrue($literal, $models[0])) $count++;
        $distribution[] = $count;
    }
    $safe = [];
    for ($variable = 1; $variable <= $formula->variables; $variable++) {
        $valid = true;
        foreach ($formula->clauses as $clause) {
            if (!clauseSatisfied($clause, $models[0], $variable)) {
                $valid = false;
                break;
            }
        }
        if ($valid) $safe[] = $variable;
    }
    $diversity = null;
    if (count($models) >= 2) {
        $diversity = (object) ['pairs' => 0, 'minimum' => $formula->variables, 'maximum' => 0];
        for ($first = 0; $first < count($models); $first++) {
            for ($second = $first + 1; $second < count($models); $second++) {
                $distance = 0;
                for ($variable = 1; $variable <= $formula->variables; $variable++) {
                    if ($models[$first][$variable] !== $models[$second][$variable]) $distance++;
                }
                $diversity->pairs++;
                $diversity->minimum = min($diversity->minimum, $distance);
                $diversity->maximum = max($diversity->maximum, $distance);
            }
        }
    }
    $backbone = null;
    if ($result->stop === 'all') {
        $backbone = [];
        for ($variable = 1; $variable <= $formula->variables; $variable++) {
            $same = true;
            foreach ($models as $model) if ($model[$variable] !== $models[0][$variable]) {
                $same = false;
                break;
            }
            if ($same) $backbone[] = $models[0][$variable] ? $variable : -$variable;
        }
    }
    return (object) compact('failure', 'distribution', 'safe', 'diversity', 'backbone');
}

function unsatisfiableCore(object $formula): object
{
    $retained = array_fill(1, count($formula->clauses), true);
    $decisions = $conflicts = 0;
    for ($number = 1; $number <= count($formula->clauses); $number++) {
        $clauses = [];
        foreach ($formula->clauses as $index => $clause) if (isset($retained[$index + 1]) && $index + 1 !== $number) $clauses[] = $clause;
        $result = solveFormula((object) ['variables' => $formula->variables, 'clauses' => $clauses], 1);
        $decisions += $result->statistics->decisions;
        $conflicts += $result->statistics->conflicts;
        if ($result->status === 'UNSAT') unset($retained[$number]);
    }
    return (object) ['clauses' => array_keys($retained), 'decisions' => $decisions, 'conflicts' => $conflicts];
}

function solveChromatic(object $job): object
{
    $attempts = [];
    $statistics = emptyStatistics();
    $rounds = $removed = 0;
    for ($colors = 1; $colors <= $job->maximum; $colors++) {
        $attempt = solveFormula(coloring($job->graph, $colors), 1);
        $attempts[] = (object) ['colors' => $colors, 'result' => $attempt];
        addStatistics($statistics, $attempt->statistics);
        $rounds += $attempt->rounds;
        $removed += $attempt->removed;
        $job->colors = $colors;
        if ($attempt->status === 'SAT') break;
    }
    $result = clone $attempts[count($attempts) - 1]->result;
    $result->attempts = $attempts;
    $result->statistics = $statistics;
    $result->rounds = $rounds;
    $result->removed = $removed;
    return $result;
}

function runJob(object $job, array $graphs): void
{
    try {
        validateJob($job, $graphs);
        $job->result = $job->command === 'CHROMATIC' ? solveChromatic($job) : solveFormula(originalFormula($job), $job->limit);
    } catch (InputError $error) {
        $job->error = $error->getMessage();
        return;
    }
    $job->analysis = analyzeModels($job->result);
    if ($job->command === 'CORE' && $job->result->status === 'UNSAT') $job->core = unsatisfiableCore($job->result->formula);
}

function statisticsValues(object $job): array
{
    $result = $job->result;
    return [$job->number, $job->command, $result->status, $result->formula->variables, count($result->formula->clauses),
        $result->removed, $result->statistics->decisions, $result->statistics->propagations, $result->statistics->conflicts,
        $result->statistics->maxDepth, count($result->models), $result->rounds];
}

function graphLine(object $graph): string
{
    return items('graph', ['vertices' => $graph->vertices, 'edges' => count($graph->edges), 'max_degree' => $graph->maximumDegree, 'greedy' => $graph->greedy->used]);
}

function formulaLine(object $formula): string
{
    $lengths = array_map('count', $formula->clauses);
    return items('formula', ['variables' => $formula->variables, 'clauses' => count($formula->clauses),
        'literals' => array_sum($lengths), 'lengths' => frequencyList($lengths)]);
}

function preprocessingLines(object $simplified): array
{
    $statistics = $simplified->statistics;
    $records = $simplified->records;
    $lines = [items('preprocess', ['pure' => $simplified->pure ? 'on' : 'off', 'tautologies' => $statistics->tautologies,
        'duplicate_literals' => $statistics->duplicateLiterals, 'unit_fixed' => $statistics->unitFixed, 'unit_removed' => $statistics->unitRemoved,
        'subsumed' => $statistics->subsumed, 'pure_fixed' => $statistics->pureFixed, 'pure_removed' => $statistics->pureRemoved, 'removed' => $simplified->removed]),
        items('removed_clauses', ['tautology' => numberList($records->tautology), 'unit' => numberList($records->unit),
            'subsumed' => numberList($records->subsumed), 'pure' => numberList($records->pure)])];
    if ($simplified->emptyClause !== null) $lines[] = items('simplified', ['empty_clause' => $simplified->emptyClause]);
    else {
        $lengths = array_map('count', $simplified->clauses);
        $lines[] = items('simplified', ['clauses' => count($simplified->clauses), 'literals' => array_sum($lengths),
            'lengths' => frequencyList($lengths), 'fixed' => count($simplified->fixedLiterals), 'active' => count($simplified->active)]);
        $lines[] = items('fixed', ['literals' => numberList($simplified->fixedLiterals)]);
    }
    return $lines;
}

function searchLine(object $statistics): string
{
    return items('search', ['decisions' => $statistics->decisions, 'propagations' => $statistics->propagations,
        'conflicts' => $statistics->conflicts, 'max_depth' => $statistics->maxDepth]);
}

function analysisLines(object $job, bool $full = true): array
{
    $result = $job->result;
    $analysis = $job->analysis;
    if ($analysis === null) return [];
    if ($analysis->failure === null) $lines = [items('verify ok', ['models' => count($result->models),
        'clauses' => count($result->formula->clauses), 'true_literals' => frequencyList($analysis->distribution)])];
    else $lines = [items('verify failed', (array) $analysis->failure)];
    $lines[] = items('flips', ['safe' => count($analysis->safe), 'variables' => numberList($analysis->safe)]);
    if ($full && $analysis->diversity !== null) {
        $diversity = $analysis->diversity;
        $lines[] = items('diversity', ['pairs' => $diversity->pairs, 'min_distance' => $diversity->minimum, 'max_distance' => $diversity->maximum]);
    }
    if ($full && $analysis->backbone !== null) $lines[] = items('backbone', ['size' => count($analysis->backbone), 'literals' => numberList($analysis->backbone)]);
    return $lines;
}

function jobHeading(object $job): string
{
    return 'JOB ' . $job->number . ' ' . $job->line;
}

function jobParagraph(object $job): array
{
    $lines = [jobHeading($job)];
    if ($job->error !== null) return array_merge($lines, ['error ' . $job->error]);
    $result = $job->result;
    if ($job->command === 'CHROMATIC') {
        $lines[] = graphLine($job->graph);
        foreach ($result->attempts as $attempt) {
            $current = $attempt->result;
            $stats = $current->statistics;
            $lines[] = items('attempt', ['k' => $attempt->colors, 'clauses' => count($current->formula->clauses),
                'removed' => $current->removed, 'result' => $current->status, 'stop' => $current->stop,
                'decisions' => $stats->decisions, 'propagations' => $stats->propagations, 'conflicts' => $stats->conflicts, 'max_depth' => $stats->maxDepth]);
        }
        $lines[] = items('result ' . $result->status, ['chromatic' => $result->status === 'SAT' ? $job->colors : '-', 'attempts' => count($result->attempts)]);
        return array_merge($lines, [searchLine($result->statistics)], analysisLines($job, false));
    }
    if ($job->command === 'COLOR') $lines[] = graphLine($job->graph);
    $lines = array_merge($lines, [formulaLine($result->formula)], preprocessingLines($result->preprocessing));
    $lines[] = items('result ' . $result->status, ['models' => count($result->models), 'rounds' => $result->rounds, 'stop' => $result->stop]);
    $lines[] = searchLine($result->statistics);
    if ($result->rounds > 0) {
        $trace = $result->trace ? implode(' ', array_slice($result->trace, 0, 12)) : '-';
        if (count($result->trace) > 12) $trace .= ' +' . (count($result->trace) - 12);
        $lines[] = 'trace ' . $trace;
    }
    $lines = array_merge($lines, analysisLines($job));
    if (isset($job->core)) $lines[] = items('core', ['size' => count($job->core->clauses), 'decisions' => $job->core->decisions,
        'conflicts' => $job->core->conflicts, 'clauses' => numberList($job->core->clauses)]);
    return $lines;
}

function summaryParagraph(array $jobs): array
{
    $valid = array_values(array_filter($jobs, fn($job) => $job->error === null));
    $sat = count(array_filter($valid, fn($job) => $job->result->status === 'SAT'));
    $lines = [items('SUMMARY', ['jobs' => count($jobs), 'sat' => $sat, 'unsat' => count($valid) - $sat, 'error' => count($jobs) - count($valid)])];
    $models = $rounds = $decisions = $propagations = $conflicts = $removed = 0;
    foreach ($valid as $job) {
        $models += count($job->result->models);
        $rounds += $job->result->rounds;
        $decisions += $job->result->statistics->decisions;
        $propagations += $job->result->statistics->propagations;
        $conflicts += $job->result->statistics->conflicts;
        $removed += $job->result->removed;
    }
    $lines[] = items('totals', ['models' => $models, 'rounds' => $rounds, 'decisions' => $decisions,
        'propagations' => $propagations, 'conflicts' => $conflicts, 'removed_clauses' => $removed]);
    foreach (array_keys(ARGUMENTS) as $command) {
        $group = array_values(array_filter($valid, fn($job) => $job->command === $command));
        if (!$group) continue;
        $satisfiable = $decisions = $propagations = $conflicts = 0;
        foreach ($group as $job) {
            if ($job->result->status === 'SAT') $satisfiable++;
            $decisions += $job->result->statistics->decisions;
            $propagations += $job->result->statistics->propagations;
            $conflicts += $job->result->statistics->conflicts;
        }
        $lines[] = items('command ' . $command, ['jobs' => count($group), 'sat' => $satisfiable, 'unsat' => count($group) - $satisfiable,
            'decisions' => $decisions, 'propagations' => $propagations, 'conflicts' => $conflicts]);
    }
    if ($valid) {
        foreach ([['hardest', 'conflicts', 'conflicts'], ['deepest', 'maxDepth', 'max_depth'], ['busiest', 'propagations', 'propagations']] as [$label, $field, $output]) {
            $best = $valid[0];
            foreach ($valid as $job) if ($job->result->statistics->$field > $best->result->statistics->$field) $best = $job;
            $lines[] = items($label, ['job' => $best->number, $output => $best->result->statistics->$field]);
        }
    }
    return $lines;
}

function modelParagraph(object $job): array
{
    $lines = [jobHeading($job)];
    foreach ($job->result->models as $index => $model) {
        $lines[] = 'model ' . ($index + 1);
        $lines = array_merge($lines, modelLines($model));
    }
    return $lines;
}

function compareSequences(array $first, array $second): int
{
    foreach ($first as $index => $value) if ($value !== $second[$index]) return $value <=> $second[$index];
    return 0;
}

function queenCanonical(array $columns): object
{
    $size = count($columns);
    $transforms = array_fill(0, 8, array_fill(0, $size, 0));
    for ($row = 1; $row <= $size; $row++) {
        $column = $columns[$row - 1];
        $images = [[$row, $column], [$column, $size + 1 - $row], [$size + 1 - $row, $size + 1 - $column],
            [$size + 1 - $column, $row], [$row, $size + 1 - $column], [$size + 1 - $row, $column],
            [$column, $row], [$size + 1 - $column, $size + 1 - $row]];
        foreach ($images as $index => [$nextRow, $nextColumn]) $transforms[$index][$nextRow - 1] = $nextColumn;
    }
    $canonical = $transforms[0];
    $distinct = [];
    foreach ($transforms as $transform) {
        if (compareSequences($transform, $canonical) < 0) $canonical = $transform;
        $distinct[implode(',', $transform)] = true;
    }
    return (object) ['canonical' => $canonical, 'orbit' => count($distinct)];
}

function registerClass(object $classes, array $canonical, int $model, array $extra = []): object
{
    $key = implode(',', $canonical);
    if (!isset($classes->lookup[$key])) {
        $entry = (object) array_merge(['number' => count($classes->sequence) + 1, 'canonical' => $canonical, 'first' => $model, 'found' => 0], $extra);
        $classes->sequence[] = $entry;
        $classes->lookup[$key] = $entry;
    }
    $entry = $classes->lookup[$key];
    $entry->found++;
    return $entry;
}

function queensParagraph(object $job): array
{
    $lines = [items('QUEENS', ['job' => $job->number, 'n' => $job->size])];
    $classes = (object) ['sequence' => [], 'lookup' => []];
    foreach ($job->result->models as $index => $model) {
        $columns = positions($model, $job->size, $job->size);
        $symmetry = queenCanonical($columns);
        $entry = registerClass($classes, $symmetry->canonical, $index + 1, ['orbit' => $symmetry->orbit]);
        $lines[] = items('solution ' . ($index + 1), ['columns' => numberList($columns), 'class' => $entry->number]);
        if ($entry->first === $index + 1) $lines = array_merge($lines, boardLines($columns));
    }
    foreach ($classes->sequence as $entry) {
        $lines[] = items('class ' . $entry->number, ['orbit' => $entry->orbit, 'found' => $entry->found,
            'first' => $entry->first, 'canonical' => numberList($entry->canonical)]);
    }
    $lines[] = items('summary', ['solutions' => count($job->result->models), 'stop' => $job->result->stop, 'classes' => count($classes->sequence)]);
    return $lines;
}

function pigeonParagraph(object $job): array
{
    $lines = [items('PIGEON', ['job' => $job->number, 'pigeons' => $job->pigeons, 'holes' => $job->holes])];
    foreach ($job->result->models as $index => $model) {
        $holes = positions($model, $job->pigeons, $job->holes);
        $occupied = array_fill_keys($holes, true);
        $empty = [];
        for ($hole = 1; $hole <= $job->holes; $hole++) if (!isset($occupied[$hole])) $empty[] = $hole;
        $lines[] = items('assignment ' . ($index + 1), ['holes' => numberList($holes), 'empty' => numberList($empty)]);
    }
    $expected = 0;
    if ($job->pigeons <= $job->holes) {
        $expected = 1;
        for ($pigeon = 0; $pigeon < $job->pigeons; $pigeon++) $expected *= $job->holes - $pigeon;
    }
    $lines[] = items('summary', ['assignments' => count($job->result->models), 'stop' => $job->result->stop, 'expected' => $expected]);
    return $lines;
}

function colorCanonical(array $colors): array
{
    $mapping = [];
    $canonical = [];
    foreach ($colors as $color) {
        if (!isset($mapping[$color])) $mapping[$color] = count($mapping) + 1;
        $canonical[] = $mapping[$color];
    }
    return $canonical;
}

function coloringParagraph(object $job): array
{
    $graph = $job->graph;
    $lines = [items($job->command, ['job' => $job->number, 'graph' => $graph->name, 'vertices' => $graph->vertices,
        'edges' => count($graph->edges), 'colors' => $job->colors])];
    $lines[] = items('greedy', ['used' => $graph->greedy->used, 'colors' => numberList($graph->greedy->colors)]);
    $classes = (object) ['sequence' => [], 'lookup' => []];
    foreach ($job->result->models as $index => $model) {
        $colors = positions($model, $graph->vertices, $job->colors);
        $sizes = array_fill(0, $job->colors, 0);
        foreach ($colors as $color) $sizes[$color - 1]++;
        $entry = registerClass($classes, colorCanonical($colors), $index + 1);
        $lines[] = items('coloring ' . ($index + 1), ['colors' => numberList($colors), 'used' => count(array_unique($colors)),
            'sizes' => numberList($sizes), 'class' => $entry->number]);
    }
    foreach ($classes->sequence as $entry) {
        $lines[] = items('class ' . $entry->number, ['found' => $entry->found, 'first' => $entry->first, 'canonical' => numberList($entry->canonical)]);
    }
    $lines[] = items('summary', ['colorings' => count($job->result->models), 'stop' => $job->result->stop, 'classes' => count($classes->sequence)]);
    return $lines;
}

function boardParagraph(object $job): array
{
    if ($job->command === 'QUEENS') return queensParagraph($job);
    if ($job->command === 'PIGEON') return pigeonParagraph($job);
    return coloringParagraph($job);
}

$graphs = readGraphs();
$jobs = readJobs();
foreach ($jobs as $job) runJob($job, $graphs);
$valid = array_values(array_filter($jobs, fn($job) => $job->error === null));
$results = array_map('jobParagraph', $jobs);
$results[] = summaryParagraph($jobs);
$models = array_map('modelParagraph', array_values(array_filter($valid, fn($job) => count($job->result->models) > 0)));
$boards = array_map('boardParagraph', array_values(array_filter($valid, fn($job) => in_array($job->command, ['QUEENS', 'PIGEON', 'COLOR', 'CHROMATIC'], true))));
$statistics = [STAT_COLUMNS];
foreach ($valid as $job) $statistics[] = statisticsValues($job);
if (!is_dir('output')) mkdir('output', 0777, true);
writeParagraphs('results.txt', $results);
writeParagraphs('models.txt', $models);
writeParagraphs('boards.txt', $boards);
writeCsv('stats.csv', $statistics);
