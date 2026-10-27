<?php

require_once __DIR__ . '/mesh.php';
require_once __DIR__ . '/materials.php';
require_once __DIR__ . '/transient.php';
require_once __DIR__ . '/steady.php';
require_once __DIR__ . '/report.php';

function sumValues(array $values): float
{
    if (!$values) return 0;
    $result = $values[0];
    for ($i = 1; $i < count($values); $i++) $result += $values[$i];
    return $result;
}

function readParams(object $plate): object
{
    $result = (object) ['probes' => [], 'runs' => []];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $fields = explode(' ', $line);
        switch ($fields[0]) {
            case 'initial': $result->initial = (float) $fields[1]; break;
            case 'end_time': $result->endTime = (int) $fields[1]; break;
            case 'snapshots': $result->snapshotTimes = array_map('intval', array_slice($fields, 1)); break;
            case 'probe_every': $result->probeEvery = (int) $fields[1]; break;
            case 'probe': $result->probes[] = (object) ['name' => $fields[1], 'p' => (int) $fields[2] * $plate->width + (int) $fields[3]]; break;
            case 'run': $result->runs[] = (object) ['name' => $fields[1], 'method' => $fields[2], 'D' => (int) $fields[3]]; break;
            case 'reference': $result->reference = $fields[1]; break;
            case 'tolerance': $result->tolerance = (float) $fields[1]; break;
            case 'max_iterations': $result->maxIterations = (int) $fields[1]; break;
            case 'omega': $result->omega = (float) $fields[1]; break;
            case 'bands': $result->bands = array_map('floatval', array_slice($fields, 1)); break;
            case 'alarm': $result->alarm = (float) $fields[1]; break;
            case 'limit': $result->limit = (float) $fields[1]; break;
        }
    }
    return $result;
}

function readBoundary(object $plate, int $endTime): object
{
    $segments = $sources = [];
    $directions = ['left' => 0, 'right' => 1, 'top' => 2, 'bottom' => 3];
    foreach (file('input/boundary.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $fields = explode(' ', $line);
        if ($fields[0] === 'segment') {
            $name = $fields[1];
            $edge = $fields[2];
            $kind = $fields[5];
            $segments[] = (object) ['name' => $name, 'edge' => $edge, 'kind' => $kind, 'direction' => $directions[$edge],
                'cells' => segmentCells($plate, $edge, (int) $fields[3], (int) $fields[4]),
                'h' => $kind === 'convective' ? (float) $fields[6] : null,
                'theta' => $kind === 'fixed' ? (float) $fields[6] : ($kind === 'convective' ? (float) $fields[7] : null)];
        } else {
            $power = (float) $fields[6];
            $cells = sourceCells($plate, (int) $fields[2], (int) $fields[3], (int) $fields[4], (int) $fields[5]);
            $intervals = $durations = [];
            for ($i = 7; $i < count($fields); $i += 2) {
                $on = (int) $fields[$i];
                $off = (int) $fields[$i + 1];
                $intervals[] = [$on, $off];
                $durations[] = min($off, $endTime) - min($on, $endTime);
            }
            $sources[] = (object) ['name' => $fields[1], 'power' => $power, 'cells' => $cells, 'intervals' => $intervals,
                'duty' => sumValues($durations) / $endTime, 'weight' => $power / count($cells)];
        }
    }
    return (object) compact('segments', 'sources');
}

function buildModel(object $plate, array $materialList, array $segments): object
{
    $indices = [];
    foreach ($materialList as $index => $material) $indices[$material->code] = $index;
    $materialIndex = array_map(fn($code) => $indices[$code], $plate->codes);
    $cellOrder = range(0, $plate->count - 1);
    foreach ($cellOrder as $p) $materialList[$materialIndex[$p]]->cells[] = $p;
    $cellMaterials = array_map(fn($i) => $materialList[$i], $materialIndex);
    $capacities = array_map(fn($material) => capacity($material, $plate->dx, $plate->depth), $cellMaterials);
    $faces = [];
    foreach ($cellOrder as $p) {
        $row = [];
        foreach ($plate->neighbors[$p] as $q) $row[] = (object) ['q' => $q,
            'g' => $q >= 0 ? interior($cellMaterials[$p]->k, $cellMaterials[$q]->k, $plate->depth) : 0, 'theta' => null];
        $faces[] = $row;
    }
    foreach ($segments as $segment) foreach ($segment->cells as $p) {
        $face = $faces[$p][$segment->direction];
        if ($segment->kind === 'fixed') $face->g = fixedConductance($cellMaterials[$p]->k, $plate->depth);
        elseif ($segment->kind === 'convective') $face->g = convective($cellMaterials[$p]->k, $segment->h, $plate->dx, $plate->depth);
        $face->theta = $segment->theta;
    }
    $diagonal = array_map(fn($cellFaces) => sumValues(array_map(fn($face) => $face->g, $cellFaces)), $faces);
    $model = clone $plate;
    foreach (compact('materialList', 'materialIndex', 'cellOrder', 'capacities', 'faces', 'diagonal') as $name => $value) $model->$name = $value;
    return $model;
}

function sourceState(object $model, array $sources, ?int $at = null): object
{
    $field = array_fill(0, $model->count, 0);
    $occupied = array_fill(0, $model->count, false);
    $powers = [];
    foreach ($sources as $source) {
        $active = $at === null;
        if ($at !== null) foreach ($source->intervals as [$on, $off]) if ($on <= $at && $at < $off) {
            $active = true;
            break;
        }
        if (!$active) continue;
        $powers[] = $source->power;
        foreach ($source->cells as $p) {
            $field[$p] = $occupied[$p] ? $field[$p] + $source->weight : $source->weight;
            $occupied[$p] = true;
        }
    }
    return (object) ['field' => $field, 'power' => sumValues($powers)];
}

function statistics(array $field, array $cells): object
{
    $first = $cells[0];
    $hottest = $first;
    $minimum = $total = $field[$first];
    for ($i = 1; $i < count($cells); $i++) {
        $p = $cells[$i];
        if ($field[$p] > $field[$hottest]) $hottest = $p;
        if ($field[$p] < $minimum) $minimum = $field[$p];
        $total += $field[$p];
    }
    return (object) ['hottest' => $hottest, 'maximum' => $field[$hottest], 'minimum' => $minimum, 'mean' => $total / count($cells)];
}

function cell(object $model, int $p): string
{
    return intdiv($p, $model->width) . ' ' . ($p % $model->width);
}

function describeField(object $model, array $field): string
{
    $stats = statistics($field, $model->cellOrder);
    return 'max ' . formatFixed($stats->maximum, 2) . ' at ' . cell($model, $stats->hottest)
        . ' min ' . formatFixed($stats->minimum, 2) . ' mean ' . formatFixed($stats->mean, 2);
}

function storedEnergy(object $model, array $field, float $initial, ?array $cells = null): float
{
    $values = [];
    foreach ($cells ?? $model->cellOrder as $p) $values[] = $model->capacities[$p] * ($field[$p] - $initial);
    return sumValues($values);
}

function segmentSum(object $model, object $segment, callable $term): float
{
    if ($segment->kind === 'insulated') return 0;
    $values = [];
    foreach ($segment->cells as $p) $values[] = $term($model->faces[$p][$segment->direction], $p);
    return sumValues($values);
}

function maxDifference(array $first, array $second): float
{
    $maximum = 0;
    foreach ($first as $p => $value) $maximum = max($maximum, abs($value - $second[$p]));
    return $maximum;
}

function acceptRuns(object $model, object $params, array $sources): object
{
    $maxDt = $model->capacities[0] / $model->diagonal[0];
    for ($p = 1; $p < $model->count; $p++) $maxDt = min($maxDt, $model->capacities[$p] / $model->diagonal[$p]);
    $times = array_merge([$params->endTime, $params->probeEvery], $params->snapshotTimes);
    foreach ($sources as $source) foreach ($source->intervals as $interval) foreach ($interval as $value) $times[] = $value;
    $runs = [];
    foreach ($params->runs as $descriptor) {
        $run = clone $descriptor;
        $run->status = 'accepted';
        foreach ($times as $value) if ($value % $run->D !== 0) {
            $run->status = 'step';
            break;
        }
        if ($run->status === 'accepted' && $run->method === 'ftcs' && $run->D / 1000 > $maxDt) $run->status = 'unstable';
        $runs[] = $run;
    }
    return (object) compact('runs', 'maxDt');
}

function observe(object $model, object $params, object $run, int $n): void
{
    $at = $n * $run->D;
    $stats = statistics($run->field, $model->cellOrder);
    if ($run->peak === null || $stats->maximum > $run->peak->temperature) $run->peak = (object) ['temperature' => $stats->maximum, 'time' => $at, 'p' => $stats->hottest];
    if ($run->alarm === null && $stats->maximum >= $params->alarm) $run->alarm = (object) ['time' => $at, 'p' => $stats->hottest];
    if ($n > 0 && $stats->maximum >= $params->alarm) $run->above += $run->D;
    if ($at % $params->probeEvery === 0) {
        $values = array_map(fn($probe) => $run->field[$probe->p], $params->probes);
        $run->probeRecords[] = (object) ['time' => $at, 'values' => $values];
    }
    if (in_array($at, $params->snapshotTimes, true)) {
        $run->snapshots[$at] = (object) ['field' => $run->field, 'stored' => storedEnergy($model, $run->field, $params->initial),
            'boundary' => sumValues($run->energyBySegment), 'source' => $run->sourceEnergy];
    }
}

function runTransient(object $model, object $params, array $segments, array $sources, object $descriptor): object
{
    $run = clone $descriptor;
    $run->steps = intdiv($params->endTime, $run->D);
    $run->field = array_fill(0, $model->count, $params->initial);
    $run->snapshots = $run->probeRecords = [];
    $run->peak = $run->alarm = null;
    $run->above = $run->sourceEnergy = 0;
    $run->energyBySegment = array_fill(0, count($segments), 0);
    $dt = $run->D / 1000;
    $advance = ['ftcs' => 'ftcs', 'backward_euler' => 'backwardEuler', 'crank_nicolson' => 'crankNicolson'][$run->method];
    observe($model, $params, $run, 0);
    for ($n = 0; $n < $run->steps; $n++) {
        $old = $run->field;
        $active = sourceState($model, $sources, $n * $run->D);
        $next = $advance($model, $old, $active->field, $dt);
        foreach ($segments as $j => $segment) {
            $horizontal = $segment->direction < 2;
            $energy = $dt * segmentSum($model, $segment, function ($face, $p) use ($run, $old, $next, $horizontal) {
                if ($run->method === 'ftcs') $temperature = $old[$p];
                elseif ($horizontal) $temperature = $next->intermediate[$p];
                elseif ($run->method === 'backward_euler') $temperature = $next->field[$p];
                else $temperature = ($old[$p] + $next->field[$p]) / 2;
                return $face->g * ($face->theta - $temperature);
            });
            $run->energyBySegment[$j] = $n === 0 ? $energy : $run->energyBySegment[$j] + $energy;
        }
        $supplied = $dt * $active->power;
        $run->sourceEnergy = $n === 0 ? $supplied : $run->sourceEnergy + $supplied;
        $run->field = $next->field;
        observe($model, $params, $run, $n + 1);
    }
    $run->energy = (object) ['stored' => storedEnergy($model, $run->field, $params->initial),
        'boundary' => sumValues($run->energyBySegment), 'source' => $run->sourceEnergy];
    $run->materialEnergy = array_map(fn($material) => storedEnergy($model, $run->field, $params->initial, $material->cells), $model->materialList);
    return $run;
}

function solveSteady(object $model, object $params, array $sources): object
{
    $source = sourceState($model, $sources)->field;
    $beta = [];
    foreach ($model->faces as $faces) {
        $terms = [];
        foreach ($faces as $face) if ($face->theta !== null) $terms[] = $face->g * $face->theta;
        $beta[] = sumValues($terms);
    }
    $rhs = [];
    foreach ($beta as $p => $value) $rhs[] = $value + $source[$p];
    $unitSources = [];
    foreach ($sources as $heatSource) {
        $vector = array_fill(0, $model->count, 0);
        foreach ($heatSource->cells as $p) $vector[$p] = 1 / count($heatSource->cells);
        $unitSources[] = $vector;
    }
    $solutions = bandSolve($model, array_merge([$rhs, $beta], $unitSources));
    $field = $solutions[0];
    $base = $solutions[1];
    $responses = array_slice($solutions, 2);
    $solveIteration = function (string $name, float $omega = 1) use ($model, $source, $params, $field, $rhs): object {
        $result = iterateSteady($model, $source, $name, $params->initial, $params->tolerance, $params->maxIterations, $omega);
        $iterations = count($result->deltas);
        $rate = sqrt($result->deltas[$iterations - 1] / $result->deltas[$iterations - 3]);
        $milestones = [];
        foreach ([1000, 100, 10, 1] as $factor) {
            $found = 'never';
            foreach ($result->deltas as $index => $delta) if ($delta < $params->tolerance * $factor) {
                $found = $index + 1;
                break;
            }
            $milestones[] = $found;
        }
        $result->name = $name;
        $result->omega = $omega;
        $result->iterations = $iterations;
        $result->rate = $rate;
        $result->milestones = $milestones;
        $result->error = maxDifference($result->field, $field);
        $result->residual = maxResidual($model, $rhs, $result->field);
        return $result;
    };
    $jacobi = $solveIteration('jacobi');
    $rho = $jacobi->rate;
    $omega = 2 / (1 + sqrt(1 - $rho * $rho));
    $solvers = [$jacobi, $solveIteration('gauss_seidel'), $solveIteration('sor', $params->omega), $solveIteration('sor_estimated', $omega)];
    return (object) compact('field', 'base', 'responses', 'rhs', 'rho', 'omega', 'solvers');
}

function analyzeSteady(object $model, object $params, array $segments, array $sources, object $solution): object
{
    $field = $solution->field;
    $reconstructed = $dutyField = [];
    foreach ($model->cellOrder as $p) {
        $combined = $duty = $solution->base[$p];
        foreach ($sources as $s => $source) {
            $combined += $source->power * $solution->responses[$s][$p];
            $duty += ($source->duty * $source->power) * $solution->responses[$s][$p];
        }
        $reconstructed[] = $combined;
        $dutyField[] = $duty;
    }
    $headrooms = [];
    foreach ($sources as $s => $source) {
        $power = null;
        $limiting = 0;
        foreach ($model->cellOrder as $p) {
            $candidate = ($params->limit - ($field[$p] - $source->power * $solution->responses[$s][$p])) / $solution->responses[$s][$p];
            if ($power === null || $candidate < $power) {
                $power = $candidate;
                $limiting = $p;
            }
        }
        $headrooms[] = (object) ['power' => $power, 'p' => $limiting];
    }
    $interfaces = [];
    $gradient = null;
    foreach ($model->cellOrder as $p) foreach ([1, 3] as $direction) {
        $face = $model->faces[$p][$direction];
        if ($face->q < 0) continue;
        $q = $face->q;
        $slope = abs($field[$p] - $field[$q]) / $model->dx;
        if ($gradient === null || $slope > $gradient->value) $gradient = (object) ['value' => $slope, 'p' => $p, 'q' => $q];
        $first = min($model->materialIndex[$p], $model->materialIndex[$q]);
        $second = max($model->materialIndex[$p], $model->materialIndex[$q]);
        if ($first === $second) continue;
        $key = $first . ',' . $second;
        if (!isset($interfaces[$key])) $interfaces[$key] = (object) ['first' => $first, 'second' => $second, 'faces' => 0, 'forward' => [], 'backward' => []];
        $record = $interfaces[$key];
        $phi = $face->g * ($field[$p] - $field[$q]);
        $signed = $model->materialIndex[$p] === $first ? $phi : -$phi;
        $record->faces++;
        if ($signed > 0) $record->forward[] = $signed;
        if ($signed < 0) $record->backward[] = -$signed;
    }
    $flows = array_map(fn($segment) => segmentSum($model, $segment, fn($face, $p) => $face->g * ($face->theta - $field[$p])), $segments);
    $power = sumValues(array_map(fn($source) => $source->power, $sources));
    $balance = abs(sumValues($flows) + $power) <= 0.000001 * (sumValues(array_map('abs', $flows)) + $power);
    return (object) ['dutyField' => $dutyField, 'headrooms' => $headrooms, 'interfaces' => $interfaces, 'gradient' => $gradient,
        'flows' => $flows, 'power' => $power, 'balance' => $balance, 'superposition' => maxDifference($reconstructed, $field) <= 0.000001];
}

function steadyLines(object $model, object $params, array $segments, array $sources, object $solution, object $analysis): array
{
    $field = $solution->field;
    $responses = $solution->responses;
    $lines = array_merge(['steady ' . describeField($model, $field)], temperatureRows($model, $field));
    foreach ($model->materialList as $material) {
        $stats = statistics($field, $material->cells);
        $lines[] = 'material ' . $material->code . ' ' . $material->name . ' cells ' . count($material->cells)
            . ' min ' . formatFixed($stats->minimum, 2) . ' max ' . formatFixed($stats->maximum, 2) . ' mean ' . formatFixed($stats->mean, 2);
    }
    foreach ($sources as $source) {
        $stats = statistics($field, $source->cells);
        $lines[] = 'source ' . $source->name . ' power ' . formatFixed($source->power, 4) . ' duty ' . formatFixed($source->duty, 4)
            . ' mean ' . formatFixed($stats->mean, 2) . ' max ' . formatFixed($stats->maximum, 2);
    }
    foreach ($sources as $recipient) foreach ($sources as $s => $source) {
        $values = [];
        foreach ($recipient->cells as $p) $values[] = $responses[$s][$p];
        $lines[] = 'influence ' . $recipient->name . ' ' . $source->name . ' ' . formatFixed(sumValues($values) / count($recipient->cells), 4);
    }
    $lines[] = 'superposition ' . ($analysis->superposition ? 'ok' : 'failed');
    foreach ($sources as $s => $source) foreach ($segments as $segment) {
        $escape = segmentSum($model, $segment, fn($face, $p) => $face->g * $responses[$s][$p]);
        $lines[] = 'path ' . $source->name . ' ' . $segment->name . ' ' . formatFixed($escape, 4);
    }
    $lines[] = 'duty_steady ' . describeField($model, $analysis->dutyField);
    foreach ($sources as $s => $source) {
        $headroom = $analysis->headrooms[$s];
        $lines[] = 'headroom ' . $source->name . ' max_power ' . formatFixed($headroom->power, 4) . ' at ' . cell($model, $headroom->p);
    }
    for ($first = 0; $first < count($model->materialList); $first++) for ($second = $first + 1; $second < count($model->materialList); $second++) {
        $pair = $analysis->interfaces[$first . ',' . $second] ?? null;
        if ($pair === null) continue;
        $lines[] = 'interface ' . $model->materialList[$first]->code . ' ' . $model->materialList[$second]->code
            . ' faces ' . $pair->faces . ' forward ' . formatFixed(sumValues($pair->forward), 4) . ' backward ' . formatFixed(sumValues($pair->backward), 4);
    }
    foreach ($segments as $j => $segment) $lines[] = 'segment ' . $segment->name . ' ' . $segment->edge . ' ' . $segment->kind . ' flow ' . formatFixed($analysis->flows[$j], 4);
    $lines[] = 'sources ' . formatFixed($analysis->power, 4);
    $lines[] = 'balance ' . ($analysis->balance ? 'ok' : 'failed');
    $lines[] = 'max_gradient ' . formatFixed($analysis->gradient->value, 2) . ' between '
        . cell($model, $analysis->gradient->p) . ' and ' . cell($model, $analysis->gradient->q);
    foreach ($solution->solvers as $solver) {
        $relaxation = str_starts_with($solver->name, 'sor') ? ' omega ' . formatFixed($solver->omega, 4) : '';
        $lines[] = 'solver ' . $solver->name . $relaxation . ' iterations ' . $solver->iterations
            . ' converged ' . ($solver->converged ? 'yes' : 'no') . ' rate ' . formatFixed($solver->rate, 6)
            . ' milestones ' . implode(' ', $solver->milestones);
    }
    return $lines;
}

function runHeading(object $run): string
{
    return 'run ' . $run->name . ' ' . $run->method . ' dt ' . formatTime($run->D);
}

function snapshotLines(object $model, object $params, array $runs, float $maxDt): array
{
    $lines = [];
    foreach ($runs as $run) {
        if ($run->status !== 'accepted') {
            $extra = $run->status === 'unstable' ? ' max_dt ' . formatFixed($maxDt, 4) : '';
            $lines[] = runHeading($run) . ' rejected ' . $run->status . $extra;
            continue;
        }
        foreach ($params->snapshotTimes as $at) {
            $field = $run->snapshots[$at]->field;
            $lines[] = runHeading($run) . ' time ' . formatTime($at) . ' ' . describeField($model, $field);
            foreach (temperatureRows($model, $field) as $line) $lines[] = $line;
        }
    }
    return $lines;
}

function probeLines(object $params, array $runs): array
{
    $lines = ['run,time,probe,temperature'];
    foreach ($runs as $run) {
        if ($run->status !== 'accepted') continue;
        foreach ($run->probeRecords as $record) foreach ($params->probes as $p => $probe) {
            $lines[] = implode(',', [$run->name, formatTime($record->time), $probe->name, formatFixed($record->values[$p], 3)]);
        }
    }
    return $lines;
}

function energyText(object $energy): string
{
    return 'stored ' . formatFixed($energy->stored, 2) . ' boundary ' . formatFixed($energy->boundary, 2) . ' source ' . formatFixed($energy->source, 2);
}

function probeSummary(object $run, int $index): string
{
    $initial = $run->probeRecords[0];
    $maximum = $minimum = $initial->values[$index];
    $maxTime = $minTime = $initial->time;
    foreach (array_slice($run->probeRecords, 1) as $record) {
        $temperature = $record->values[$index];
        if ($temperature > $maximum) {
            $maximum = $temperature;
            $maxTime = $record->time;
        }
        if ($temperature < $minimum) {
            $minimum = $temperature;
            $minTime = $record->time;
        }
    }
    return 'max ' . formatFixed($maximum, 3) . ' time ' . formatTime($maxTime) . ' min ' . formatFixed($minimum, 3) . ' time ' . formatTime($minTime);
}

function comparisonLines(object $model, object $params, array $segments, array $runs, object $reference, float $maxDt, object $solution): array
{
    $lines = ['ftcs_max_dt ' . formatFixed($maxDt, 4)];
    foreach ($runs as $run) {
        if ($run->status !== 'accepted') {
            $lines[] = runHeading($run) . ' rejected ' . $run->status;
            continue;
        }
        $alarm = $run->alarm === null ? 'never' : formatTime($run->alarm->time) . ' at ' . cell($model, $run->alarm->p);
        $lines[] = runHeading($run) . ' steps ' . $run->steps . ' peak ' . formatFixed($run->peak->temperature, 2)
            . ' time ' . formatTime($run->peak->time) . ' at ' . cell($model, $run->peak->p) . ' alarm ' . $alarm . ' above ' . formatTime($run->above);
        $energy = $run->energy;
        $balance = abs($energy->stored - $energy->boundary - $energy->source)
            <= 0.000001 * (abs($energy->stored) + abs($energy->boundary) + abs($energy->source));
        $lines[] = 'energy ' . $run->name . ' ' . energyText($energy) . ' balance ' . ($balance ? 'ok' : 'failed');
        foreach ($params->snapshotTimes as $at) $lines[] = 'energy_at ' . $run->name . ' time ' . formatTime($at) . ' ' . energyText($run->snapshots[$at]);
        foreach ($model->materialList as $m => $material) $lines[] = 'energy_material ' . $run->name . ' ' . $material->code . ' ' . formatFixed($run->materialEnergy[$m], 2);
        foreach ($segments as $j => $segment) $lines[] = 'energy_segment ' . $run->name . ' ' . $segment->name . ' ' . formatFixed($run->energyBySegment[$j], 2);
        foreach ($params->probes as $p => $probe) $lines[] = 'probe_summary ' . $run->name . ' ' . $probe->name . ' ' . probeSummary($run, $p);
        if ($run->name !== $reference->name) foreach ($params->snapshotTimes as $at) {
            $field = $run->snapshots[$at]->field;
            $other = $reference->snapshots[$at]->field;
            $squared = [];
            foreach ($field as $p => $value) {
                $error = abs($value - $other[$p]);
                $squared[] = $error * $error;
            }
            $lines[] = 'compare ' . $run->name . ' ' . $reference->name . ' time ' . formatTime($at)
                . ' max_diff ' . formatFixed(maxDifference($field, $other), 6) . ' rms_diff ' . formatFixed(sqrt(sumValues($squared) / $model->count), 6);
        }
        $lines[] = 'final ' . $run->name . ' steady_max_diff ' . formatFixed(maxDifference($run->field, $solution->field), 6);
    }
    $lines[] = 'steady direct max_residual ' . formatFixed(maxResidual($model, $solution->rhs, $solution->field), 6);
    foreach ($solution->solvers as $solver) $lines[] = 'steady ' . $solver->name . ' iterations ' . $solver->iterations
        . ' max_diff ' . formatFixed($solver->error, 6) . ' max_residual ' . formatFixed($solver->residual, 6);
    $lines[] = 'jacobi_spectral_radius ' . formatFixed($solution->rho, 6) . ' squared ' . formatFixed($solution->rho * $solution->rho, 6);
    $lines[] = 'omega_estimated ' . formatFixed($solution->omega, 4);
    return $lines;
}

function isothermLines(object $model, object $params, object $reference, array $field): array
{
    $initial = isothermRows($model, $field, $params->bands);
    $lines = array_merge(['isotherms steady counts ' . implode(' ', $initial->counts)], $initial->lines);
    foreach ($params->snapshotTimes as $at) {
        $map = isothermRows($model, $reference->snapshots[$at]->field, $params->bands);
        $lines[] = 'isotherms ' . $reference->name . ' time ' . formatTime($at) . ' counts ' . implode(' ', $map->counts);
        foreach ($map->lines as $line) $lines[] = $line;
    }
    return $lines;
}

$plate = readPlate();
$params = readParams($plate);
$boundary = readBoundary($plate, $params->endTime);
$model = buildModel($plate, readMaterials(), $boundary->segments);
$accepted = acceptRuns($model, $params, $boundary->sources);
$solution = solveSteady($model, $params, $boundary->sources);
$analysis = analyzeSteady($model, $params, $boundary->segments, $boundary->sources, $solution);
$runs = [];
foreach ($accepted->runs as $run) $runs[] = $run->status === 'accepted' ? runTransient($model, $params, $boundary->segments, $boundary->sources, $run) : $run;
$reference = null;
foreach ($runs as $run) if ($run->name === $params->reference) {
    $reference = $run;
    break;
}
writeFiles([
    'snapshots.txt' => snapshotLines($model, $params, $runs, $accepted->maxDt),
    'probes.csv' => probeLines($params, $runs),
    'steady_state.txt' => steadyLines($model, $params, $boundary->segments, $boundary->sources, $solution, $analysis),
    'solver_comparison.txt' => comparisonLines($model, $params, $boundary->segments, $runs, $reference, $accepted->maxDt, $solution),
    'isotherms.txt' => isothermLines($model, $params, $reference, $solution->field),
]);
