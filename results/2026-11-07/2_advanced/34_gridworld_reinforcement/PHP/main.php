<?php

require_once __DIR__ . '/environment.php';
require_once __DIR__ . '/dynamic_programming.php';
require_once __DIR__ . '/td_learning.php';
require_once __DIR__ . '/monte_carlo.php';
require_once __DIR__ . '/report.php';

const METHODS = ['mc', 'sarsa', 'q_learning', 'expected_sarsa', 'dyna_q'];
const ABSORPTION_SCALE = 100000000;

function pairs(array $values): array
{
    $result = [];
    for ($index = 0; $index < count($values); $index += 2) {
        $result[] = [$values[$index], $values[$index + 1]];
    }
    return $result;
}

function scheduleValue(array $schedule, int $episode): int
{
    $value = $schedule[0][1];
    foreach ($schedule as [$start, $numerator]) {
        if ($start > $episode) {
            break;
        }
        $value = $numerator;
    }
    return $value;
}

function readSettings(): object
{
    $parameters = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $name = array_shift($parts);
        $parameters[$name] = array_map('intval', $parts);
    }
    [$denominator, $floorSlip, $iceSlip] = $parameters['SLIP'];
    $settings = (object) ['gamma' => $parameters['GAMMA'][0], 'stepReward' => $parameters['STEP_REWARD'][0],
        'denominator' => $denominator, 'floorSlip' => $floorSlip, 'iceSlip' => $iceSlip, 'theta' => $parameters['THETA'][0],
        'gammaSweep' => $parameters['GAMMA_SWEEP'], 'slipSweep' => pairs($parameters['SLIP_SWEEP']),
        'episodes' => $parameters['EPISODES'][0], 'limit' => $parameters['STEP_LIMIT'][0], 'blockSize' => $parameters['BLOCK_SIZE'][0],
        'alpha' => pairs($parameters['ALPHA']), 'epsilon' => pairs($parameters['EPSILON']), 'planning' => $parameters['PLANNING_STEPS'][0],
        'seed' => $parameters['SEED'][0], 'rollouts' => $parameters['ROLLOUTS'][0], 'rolloutSeed' => $parameters['ROLLOUT_SEED'][0]];
    $starts = [];
    foreach (array_merge($settings->alpha, $settings->epsilon) as [$start]) {
        $starts[$start] = true;
    }
    $starts = array_keys($starts);
    sort($starts, SORT_NUMERIC);
    $settings->phases = [];
    foreach ($starts as $index => $first) {
        $settings->phases[] = (object) ['first' => $first, 'last' => isset($starts[$index + 1]) ? $starts[$index + 1] - 1 : $settings->episodes];
    }
    $settings->finalEpsilon = scheduleValue($settings->epsilon, $settings->episodes);
    return $settings;
}

function agreement(array $first, array $second): int
{
    $count = 0;
    foreach ($first as $state => $action) {
        if ($action === $second[$state]) {
            $count++;
        }
    }
    return $count;
}

function largestEntry(array $values): object
{
    $at = 0;
    for ($index = 1; $index < count($values); $index++) {
        if ($values[$index] > $values[$at]) {
            $at = $index;
        }
    }
    return (object) ['at' => $at, 'value' => $values[$at]];
}

function distanceAnalysis(World $world, TransitionModel $model): object
{
    $distances = array_fill(0, count($world->cells), -1);
    $distances[$world->start] = 0;
    $frontier = [$world->start];
    $distance = 0;
    while ($frontier) {
        $next = [];
        foreach ($frontier as $position) {
            foreach ($model->transitions[$world->index[$position]] as $transitions) {
                foreach ($transitions as $transition) {
                    if ($distances[$transition->cell] >= 0) {
                        continue;
                    }
                    $distances[$transition->cell] = $distance + 1;
                    if ($transition->next >= 0) {
                        $next[] = $transition->cell;
                    }
                }
            }
        }
        sort($next, SORT_NUMERIC);
        $frontier = $next;
        $distance++;
    }
    $reachable = 0;
    foreach ($world->states as $position) {
        if ($distances[$position] >= 0) {
            $reachable++;
        }
    }
    return (object) compact('distances', 'reachable');
}

function symmetry(World $world, object $optimal): object
{
    $mirrorActions = [0, 3, 2, 1];
    $pairs = 0;
    $values = 0;
    $actions = 0;
    foreach ($world->states as $state => $position) {
        $column = $position % $world->width;
        if ($column >= $world->width - 1 - $column) {
            continue;
        }
        $mirror = $world->index[$position + $world->width - 1 - 2 * $column];
        if ($mirror < 0) {
            continue;
        }
        $pairs++;
        if ($optimal->values[$state] === $optimal->values[$mirror]) {
            $values++;
        }
        if ($optimal->policy[$mirror] === $mirrorActions[$optimal->policy[$state]]) {
            $actions++;
        }
    }
    return (object) compact('pairs', 'values', 'actions');
}

function prepareData(): object
{
    $world = readWorld();
    $settings = readSettings();
    $model = new TransitionModel($world, $settings->denominator, $settings->floorSlip, $settings->iceSlip, $settings->stepReward);
    $optimal = valueIteration($model, $settings->gamma, $settings->theta);
    $optimal->table = actionValues($model, $optimal->values, $settings->gamma);
    $optimal->policy = greedyPolicy($optimal->table);
    $optimal->actions = [];
    foreach ($optimal->table as $row) {
        $actions = [];
        foreach ($row as $action => $value) {
            if ($value === max($row)) {
                $actions[] = $action;
            }
        }
        $optimal->actions[] = $actions;
    }
    return (object) ['world' => $world, 'settings' => $settings, 'model' => $model, 'optimal' => $optimal,
        'inPlace' => inPlaceValueIteration($model, $settings->gamma, $settings->theta),
        'iteration' => policyIteration($model, $settings->gamma, $settings->theta),
        'distance' => distanceAnalysis($world, $model), 'symmetry' => symmetry($world, $optimal)];
}

function episodeStatistics(array $episodes): object
{
    $result = (object) ['count' => count($episodes), 'totalReturn' => 0, 'totalSteps' => 0, 'goals' => 0, 'pits' => 0, 'timeouts' => 0];
    foreach ($episodes as $episode) {
        $result->totalReturn += $episode->totalReturn;
        $result->totalSteps += $episode->steps;
        if ($episode->ending === 'goal') {
            $result->goals++;
        } elseif ($episode->ending === 'pit') {
            $result->pits++;
        } else {
            $result->timeouts++;
        }
    }
    return $result;
}

function blockRecord(object $data, array $table, array $visits, array $episodes, int $number): object
{
    $statistics = episodeStatistics(array_slice($episodes, -$data->settings->blockSize));
    $policy = greedyPolicy($table);
    $error = 0;
    $coverage = 0;
    foreach ($table as $state => $row) {
        $error += abs(max($row) - $data->optimal->values[$state]);
        if (array_sum($visits[$state]) > 0) {
            $coverage++;
        }
    }
    return (object) array_merge((array) $statistics, ['number' => $number, 'agree' => agreement($policy, $data->optimal->policy),
        'valueError' => floorDivide($error, count($table)), 'coverage' => $coverage]);
}

function learn(object $data, string $name): object
{
    $world = $data->world;
    $settings = $data->settings;
    $model = $data->model;
    $table = array_fill(0, count($world->states), array_fill(0, 4, 0));
    $visits = array_fill(0, count($world->states), array_fill(0, 4, 0));
    $generator = new Minstd($settings->seed);
    $monteCarlo = $name === 'mc' ? new FirstVisit(count($table)) : null;
    $dyna = $name === 'dyna_q' ? new DynaModel() : null;
    $episodes = [];
    $blocks = [];
    for ($episode = 1; $episode <= $settings->episodes; $episode++) {
        $alpha = scheduleValue($settings->alpha, $episode);
        $epsilon = scheduleValue($settings->epsilon, $episode);
        $trajectory = [];
        $path = $episode === $settings->episodes ? [$world->start] : null;
        $state = $world->startIndex;
        $action = $name === 'sarsa' ? choose($table, $state, $epsilon, $generator) : 0;
        $totalReturn = 0;
        $steps = 0;
        $ending = 'timeout';
        for ($step = 1; $step <= $settings->limit; $step++) {
            if ($name !== 'sarsa') {
                $action = choose($table, $state, $epsilon, $generator);
            }
            $result = $model->step($state, $action, $generator);
            $visits[$state][$action]++;
            if ($monteCarlo !== null) {
                $trajectory[] = (object) ['state' => $state, 'action' => $action, 'reward' => $result->reward];
            } else {
                $future = 0;
                $nextAction = $action;
                if ($name === 'sarsa') {
                    if ($result->next >= 0) {
                        $nextAction = choose($table, $result->next, $epsilon, $generator);
                        $future = $table[$result->next][$nextAction];
                    }
                } else {
                    $future = nextValue($table, $result->next, $name === 'expected_sarsa' ? $epsilon : null);
                }
                update($table, $state, $action, $result->reward, $result->next, $future, $settings->gamma, $alpha);
                if ($dyna !== null) {
                    $dyna->record($state, $action, $result->reward, $result->next);
                    $dyna->plan($table, $settings->planning, $settings->gamma, $alpha, $generator);
                }
                if ($name === 'sarsa') {
                    $action = $nextAction;
                }
            }
            $totalReturn += $result->reward;
            $steps++;
            if ($path !== null) {
                $path[] = $result->cell;
            }
            if ($result->next < 0) {
                $ending = $world->terminalAt[$result->cell]->ending;
                break;
            }
            $state = $result->next;
        }
        if ($monteCarlo !== null) {
            $monteCarlo->update($table, $trajectory, $settings->gamma);
        }
        $episodes[] = (object) compact('totalReturn', 'steps', 'ending', 'path');
        if ($episode % $settings->blockSize === 0) {
            $blocks[] = blockRecord($data, $table, $visits, $episodes, intdiv($episode, $settings->blockSize));
        }
    }
    return (object) ['name' => $name, 'table' => $table, 'visits' => $visits, 'episodes' => $episodes, 'blocks' => $blocks,
        'policy' => greedyPolicy($table), 'visitTotals' => array_map('array_sum', $visits)];
}

function nominalPath(World $world, array $policy, int $origin, int $limit): object
{
    $path = [$world->states[$origin]];
    $seen = [$path[0] => true];
    $state = $origin;
    for ($steps = 1; $steps <= $limit; $steps++) {
        $reached = $world->moves[$state][$policy[$state]];
        $repeated = isset($seen[$reached]);
        $path[] = $reached;
        $terminal = $world->terminalAt[$reached];
        if ($terminal !== null) {
            return (object) ['path' => $path, 'steps' => $steps, 'ending' => $terminal->ending, 'last' => $reached];
        }
        if ($repeated) {
            return (object) ['path' => $path, 'steps' => $steps, 'ending' => 'loop', 'last' => $reached];
        }
        if ($steps === $limit) {
            return (object) ['path' => $path, 'steps' => $steps, 'ending' => 'limit', 'last' => $reached];
        }
        $seen[$reached] = true;
        $state = $world->index[$reached];
    }
}

function describePolicy(object $data, array $policy): object
{
    $world = $data->world;
    $actions = [0, 0, 0, 0];
    $risk = 0;
    $basins = [];
    foreach ($world->states as $state => $position) {
        $actions[$policy[$state]]++;
        foreach ($data->model->transitions[$state][$policy[$state]] as $transition) {
            if ($world->cells[$transition->cell] === 'P') {
                $risk++;
                break;
            }
        }
        $path = nominalPath($world, $policy, $state, $data->settings->limit);
        $basins[] = $path->ending === 'goal' || $path->ending === 'pit' ? $world->terminalAt[$path->last]->symbol : '*';
    }
    return (object) ['actions' => $actions, 'risk' => $risk, 'basins' => $basins,
        'path' => nominalPath($world, $policy, $world->startIndex, $data->settings->limit)];
}

function absorption(object $data, array $policy): array
{
    $world = $data->world;
    $model = $data->model;
    $goals = array_fill(0, count($policy), 0);
    $pits = array_fill(0, count($policy), 0);
    $expected = array_fill(0, count($policy), 0);
    for ($step = 1; $step <= $data->settings->limit; $step++) {
        $nextGoals = [];
        $nextPits = [];
        $nextExpected = [];
        foreach ($policy as $state => $action) {
            $goalTotal = 0;
            $pitTotal = 0;
            $stepTotal = 0;
            foreach ($model->transitions[$state][$action] as $transition) {
                if ($transition->next < 0) {
                    if ($world->cells[$transition->cell] === 'G') {
                        $goalTotal += $transition->weight * ABSORPTION_SCALE;
                    } else {
                        $pitTotal += $transition->weight * ABSORPTION_SCALE;
                    }
                } else {
                    $goalTotal += $transition->weight * $goals[$transition->next];
                    $pitTotal += $transition->weight * $pits[$transition->next];
                    $stepTotal += $transition->weight * $expected[$transition->next];
                }
            }
            $nextGoals[] = floorDivide($goalTotal, $model->denominator);
            $nextPits[] = floorDivide($pitTotal, $model->denominator);
            $nextExpected[] = ABSORPTION_SCALE + floorDivide($stepTotal, $model->denominator);
        }
        $goals = $nextGoals;
        $pits = $nextPits;
        $expected = $nextExpected;
    }
    $start = $world->startIndex;
    return [$goals[$start], $pits[$start], ABSORPTION_SCALE - $goals[$start] - $pits[$start], $expected[$start]];
}

function behaviourValue(object $data, array $policy): object
{
    $model = $data->model;
    $settings = $data->settings;
    $values = array_fill(0, count($policy), 0);
    $epsilon = $settings->finalEpsilon;
    $sweeps = 0;
    while (true) {
        $delta = 0;
        foreach ($policy as $state => $choice) {
            $actions = rowValues($model, $values, $state, $settings->gamma);
            $total = 0;
            foreach ($actions as $action => $value) {
                $weight = $epsilon + ($action === $choice ? 4 * (1000 - $epsilon) : 0);
                $total += $weight * $value;
            }
            $next = floorDivide($total, 4000);
            $delta = max($delta, abs($next - $values[$state]));
            $values[$state] = $next;
        }
        $sweeps++;
        if ($delta <= $settings->theta) {
            return (object) ['start' => $values[$data->world->startIndex], 'sweeps' => $sweeps];
        }
    }
}

function rollouts(object $data, array $policy): object
{
    $world = $data->world;
    $settings = $data->settings;
    $generator = new Minstd($settings->rolloutSeed);
    $episodes = [];
    $terminals = array_fill(0, count($world->terminals), 0);
    $totalDiscounted = 0;
    for ($rollout = 0; $rollout < $settings->rollouts; $rollout++) {
        $state = $world->startIndex;
        $rewards = [];
        $totalReturn = 0;
        $ending = 'timeout';
        for ($step = 1; $step <= $settings->limit; $step++) {
            $result = $data->model->step($state, $policy[$state], $generator);
            $rewards[] = $result->reward;
            $totalReturn += $result->reward;
            if ($result->next < 0) {
                $terminal = $world->terminalAt[$result->cell];
                $terminals[$terminal->number]++;
                $ending = $terminal->ending;
                break;
            }
            $state = $result->next;
        }
        $totalDiscounted += discountedReturn($rewards, $settings->gamma);
        $episodes[] = (object) ['totalReturn' => $totalReturn, 'steps' => count($rewards), 'ending' => $ending];
    }
    $returns = array_map(fn($episode) => $episode->totalReturn, $episodes);
    sort($returns, SORT_NUMERIC);
    return (object) array_merge((array) episodeStatistics($episodes), ['totalDiscounted' => $totalDiscounted, 'terminals' => $terminals,
        'minimum' => $returns[0], 'median' => $returns[intdiv($settings->rollouts + 1, 2) - 1], 'maximum' => $returns[count($returns) - 1]]);
}

function qErrors(object $data, object $method): object
{
    $errors = [];
    $unvisited = 0;
    $tied = 0;
    foreach ($method->table as $state => $row) {
        $maximum = max($row);
        $errors[] = abs($maximum - $data->optimal->values[$state]);
        if ($method->visitTotals[$state] === 0) {
            $unvisited++;
        }
        if (count(array_filter($row, fn($value) => $value === $maximum)) > 1) {
            $tied++;
        }
    }
    $perAction = [];
    for ($action = 0; $action < 4; $action++) {
        $total = 0;
        $count = 0;
        foreach ($method->table as $state => $row) {
            if ($method->visits[$state][$action] === 0) {
                continue;
            }
            $total += abs($row[$action] - $data->optimal->table[$state][$action]);
            $count++;
        }
        $perAction[] = $count === 0 ? null : floorDivide($total, $count);
    }
    return (object) array_merge((array) largestEntry($errors), ['mean' => floorDivide(array_sum($errors), count($errors)),
        'perAction' => $perAction, 'unvisited' => $unvisited, 'tied' => $tied]);
}

function assessPolicy(object $data, object $source): void
{
    $model = $data->model;
    $settings = $data->settings;
    $optimal = $data->optimal;
    $world = $data->world;
    $evaluation = evaluatePolicy($model, $source->policy, $settings->gamma, $settings->theta);
    $improved = greedyPolicy(actionValues($model, $evaluation->values, $settings->gamma));
    $improvedValue = evaluatePolicy($model, $improved, $settings->gamma, $settings->theta);
    $optimalActions = 0;
    $gaps = [];
    foreach ($source->policy as $state => $action) {
        if (in_array($action, $optimal->actions[$state], true)) {
            $optimalActions++;
        }
        $gaps[] = $optimal->values[$state] - $evaluation->values[$state];
    }
    $source->assessment = (object) ['agree' => agreement($source->policy, $optimal->policy), 'optimalActions' => $optimalActions,
        'start' => $evaluation->values[$world->startIndex], 'sweeps' => $evaluation->sweeps, 'gap' => largestEntry($gaps)];
    $source->improvement = (object) ['changed' => count($source->policy) - agreement($source->policy, $improved),
        'start' => $improvedValue->values[$world->startIndex], 'agree' => agreement($improved, $optimal->policy)];
    $source->description = describePolicy($data, $source->policy);
    $source->absorption = absorption($data, $source->policy);
    $source->rollouts = rollouts($data, $source->policy);
    if (isset($source->table)) {
        $source->behaviour = behaviourValue($data, $source->policy);
        $source->errors = qErrors($data, $source);
    }
}

function trainingSummary(object $data, object $method, int $optimalReturn): object
{
    $best = $method->blocks[0];
    $reach = '-';
    foreach ($method->blocks as $block) {
        if ($block->totalReturn > $best->totalReturn) {
            $best = $block;
        }
        if ($reach === '-' && 10 * $data->settings->rollouts * $block->totalReturn >= 9 * $data->settings->blockSize * $optimalReturn) {
            $reach = $block->number;
        }
    }
    $visited = [];
    foreach ($method->visitTotals as $state => $visits) {
        $visited[] = (object) compact('state', 'visits');
    }
    usort($visited, fn($a, $b) => ($b->visits <=> $a->visits) ?: ($a->state <=> $b->state));
    $visited = array_slice($visited, 0, 3);
    $phases = [];
    foreach ($data->settings->phases as $phase) {
        $statistics = episodeStatistics(array_slice($method->episodes, $phase->first - 1, $phase->last - $phase->first + 1));
        $phases[] = (object) array_merge((array) $phase, (array) $statistics,
            ['alpha' => scheduleValue($data->settings->alpha, $phase->first), 'epsilon' => scheduleValue($data->settings->epsilon, $phase->first)]);
    }
    return (object) array_merge((array) episodeStatistics($method->episodes), ['best' => $best,
        'last' => $method->blocks[count($method->blocks) - 1], 'reach' => $reach, 'visited' => $visited, 'phases' => $phases]);
}

function analyzeSensitivity(object $data, TransitionModel $model, int $gamma): object
{
    $result = valueIteration($model, $gamma, $data->settings->theta);
    $policy = greedyPolicy(actionValues($model, $result->values, $gamma));
    return (object) ['iterations' => $result->iterations, 'start' => $result->values[$data->world->startIndex],
        'path' => nominalPath($data->world, $policy, $data->world->startIndex, $data->settings->limit),
        'differences' => count($policy) - agreement($policy, $data->optimal->policy)];
}

function sensitivity(object $data): object
{
    $gamma = [];
    foreach ($data->settings->gammaSweep as $value) {
        $result = analyzeSensitivity($data, $data->model, $value);
        $result->gamma = $value;
        $gamma[] = $result;
    }
    $slip = [];
    foreach ($data->settings->slipSweep as [$floorSlip, $iceSlip]) {
        $model = new TransitionModel($data->world, $data->settings->denominator, $floorSlip, $iceSlip, $data->settings->stepReward);
        $result = analyzeSensitivity($data, $model, $data->settings->gamma);
        $result->floorSlip = $floorSlip;
        $result->iceSlip = $iceSlip;
        $slip[] = $result;
    }
    return (object) compact('gamma', 'slip');
}

function sections(array $parts): array
{
    $lines = [];
    foreach ($parts as $part) {
        if ($lines) {
            $lines[] = '';
        }
        foreach ($part as $line) {
            $lines[] = $line;
        }
    }
    return $lines;
}

function worldLines(object $data): array
{
    $world = $data->world;
    $count = fn($symbols) => count(array_filter($world->cells, fn($terrain) => str_contains($symbols, $terrain)));
    $lines = ['world rows ' . $world->height . ' cols ' . $world->width . ' states ' . count($world->states)
        . ' walls ' . $count('#') . ' floor ' . $count('.S') . ' ice ' . $count('~') . ' goals ' . $count('G') . ' pits ' . $count('P'),
        'start ' . cell($world, $world->start) . ' reachable ' . $data->distance->reachable];
    foreach ($world->terminals as $terminal) {
        $distance = $data->distance->distances[$terminal->cell];
        $lines[] = 'terminal ' . cell($world, $terminal->cell) . ' ' . $terminal->ending . ' reward ' . $terminal->reward
            . ' distance ' . ($distance < 0 ? '-' : $distance);
    }
    return $lines;
}

function sensitivityDetail(World $world, object $result): string
{
    return 'iterations ' . $result->iterations . ' value_start ' . fixed($result->start) . ' path ' . $result->path->ending
        . ' steps ' . $result->path->steps . ' last ' . cell($world, $result->path->last) . ' differences ' . $result->differences;
}

function valuesReport(object $data, object $sweep): array
{
    $world = $data->world;
    $settings = $data->settings;
    $optimal = $data->optimal;
    $iteration = $data->iteration;
    $valueLines = ['value_iteration gamma ' . $settings->gamma . ' theta ' . fixed($settings->theta) . ' iterations ' . $optimal->iterations];
    foreach ($optimal->changes as $index => $change) {
        $valueLines[] = 'iteration ' . ($index + 1) . ' max_change ' . fixed($change);
    }
    $ties = count(array_filter($optimal->actions, fn($actions) => count($actions) > 1));
    $tieLines = ['ties ' . $ties];
    foreach ($optimal->actions as $state => $actions) {
        if (count($actions) > 1) {
            $names = array_map(fn($action) => ACTIONS[$action], $actions);
            $tieLines[] = 'tie ' . cell($world, $world->states[$state]) . ' ' . implode('', $names);
        }
    }
    $tieLines[] = 'symmetry pairs ' . $data->symmetry->pairs . ' equal_values ' . $data->symmetry->values
        . ' mirrored_actions ' . $data->symmetry->actions;
    $iterationLines = ['policy_iteration rounds ' . count($iteration->rounds)];
    $sweeps = 0;
    foreach ($iteration->rounds as $round) {
        $iterationLines[] = 'round ' . $round->number . ' sweeps ' . $round->sweeps . ' changed ' . $round->changed . ' value_start ' . fixed($round->start);
        $sweeps += $round->sweeps;
    }
    $differences = [];
    foreach ($optimal->values as $state => $value) {
        $differences[] = abs($iteration->values[$state] - $value);
    }
    $difference = largestEntry($differences);
    $states = count($world->states);
    $backups = $sweeps * $states + count($iteration->rounds) * $states * 4;
    $comparison = ['comparison policy_differences ' . ($states - agreement($iteration->policy, $optimal->policy))
        . ' max_value_difference ' . fixed($difference->value) . ' at ' . cell($world, $world->states[$difference->at]),
        'backups value_iteration ' . ($optimal->iterations * $states * 4) . ' in_place_iterations ' . $data->inPlace->iterations
        . ' in_place ' . ($data->inPlace->iterations * $states * 4) . ' policy_iteration ' . $backups];
    $gammaLines = ['gamma_sweep'];
    foreach ($sweep->gamma as $result) {
        $gammaLines[] = 'gamma ' . $result->gamma . ' ' . sensitivityDetail($world, $result);
    }
    $slipLines = ['slip_sweep'];
    foreach ($sweep->slip as $result) {
        $slipLines[] = 'slip ' . $result->floorSlip . ' ' . $result->iceSlip . ' ' . sensitivityDetail($world, $result);
    }
    return sections([worldLines($data), $valueLines,
        array_merge(['optimal_values'], grid($world, fn($state) => fixed($optimal->values[$state]), true)),
        array_merge(['optimal_action_counts'], grid($world, fn($state) => count($optimal->actions[$state]))),
        $tieLines, $iterationLines,
        array_merge(['policy_iteration_values'], grid($world, fn($state) => fixed($iteration->values[$state]), true)),
        $comparison, $gammaLines, $slipLines]);
}

function policiesReport(object $data, array $policies): array
{
    $world = $data->world;
    $parts = [];
    foreach ($policies as $policy) {
        $description = $policy->description;
        $path = $description->path;
        $pathText = implode(' ', array_map(fn($position) => cell($world, $position), $path->path));
        $lines = array_merge([$policy->name], policyGrid($world, $policy->policy),
            ['path ' . $path->ending . ' steps ' . $path->steps . ' ' . $pathText,
                'actions N ' . $description->actions[0] . ' E ' . $description->actions[1] . ' S ' . $description->actions[2]
                    . ' W ' . $description->actions[3] . ' risk ' . $description->risk,
                'basins'], grid($world, fn($state) => $description->basins[$state]));
        if (isset($policy->visits)) {
            $lines[] = 'visits';
            $lines = array_merge($lines, grid($world, fn($state) => $policy->visitTotals[$state] === 0 ? 0 : strlen((string) $policy->visitTotals[$state])));
        }
        $parts[] = $lines;
    }
    return sections($parts);
}

function learningReport(object $data, array $methods): array
{
    $lines = ['method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage'];
    foreach ($methods as $method) {
        foreach ($method->blocks as $block) {
            $lines[] = implode(',', [$method->name, $block->number, average($block->totalReturn, $data->settings->blockSize),
                average($block->totalSteps, $data->settings->blockSize), $block->goals, $block->pits, $block->timeouts,
                $block->agree, fixed($block->valueError), $block->coverage]);
        }
    }
    return $lines;
}

function evaluationReport(object $data, array $policies, array $methods): array
{
    $world = $data->world;
    $settings = $data->settings;
    $stateCell = fn($state) => cell($world, $world->states[$state]);
    $values = ['policies', 'policy agree optimal_actions value_start sweeps max_gap at'];
    $improvement = ['improvement', 'policy changed value_start agree'];
    $absorbed = ['absorption', 'policy p_goal p_pit p_timeout expected_steps'];
    $rolloutLines = ['rollouts', 'policy mean_return mean_discounted mean_steps goals pits timeouts min median max'];
    $terminalLines = ['terminals', 'policy ' . implode(' ', array_map(fn($terminal) => cell($world, $terminal->cell), $world->terminals))];
    $agreementLines = ['agreement', 'policy ' . implode(' ', array_map(fn($policy) => $policy->name, $policies))];
    foreach ($policies as $policy) {
        $evaluation = $policy->assessment;
        $values[] = implode(' ', [$policy->name, $evaluation->agree, $evaluation->optimalActions, fixed($evaluation->start),
            $evaluation->sweeps, fixed($evaluation->gap->value), $stateCell($evaluation->gap->at)]);
        $improvement[] = implode(' ', [$policy->name, $policy->improvement->changed, fixed($policy->improvement->start), $policy->improvement->agree]);
        $absorbed[] = $policy->name . ' ' . implode(' ', array_map(fn($value) => fixed(floorDivide($value, 10000)), $policy->absorption));
        $trials = $policy->rollouts;
        $rolloutLines[] = implode(' ', [$policy->name, average($trials->totalReturn, $settings->rollouts),
            fixed(floorDivide($trials->totalDiscounted, $settings->rollouts)), average($trials->totalSteps, $settings->rollouts),
            $trials->goals, $trials->pits, $trials->timeouts, $trials->minimum, $trials->median, $trials->maximum]);
        $terminalLines[] = $policy->name . ' ' . implode(' ', $trials->terminals);
        $agreementLines[] = $policy->name . ' ' . implode(' ', array_map(fn($other) => agreement($policy->policy, $other->policy), $policies));
    }
    $behaviour = ['behaviour', 'method epsilon value_start sweeps'];
    $errors = ['q_errors', 'method mean_abs max_abs at unvisited tied'];
    $actionErrors = ['q_action_errors', 'method N E S W'];
    $training = ['training', 'method steps goals pits timeouts best_block best_mean last_mean reach'];
    $visited = ['visited'];
    $lastEpisodes = ['last_episodes'];
    $phases = ['phases'];
    foreach ($methods as $method) {
        $behaviour[] = implode(' ', [$method->name, $settings->finalEpsilon, fixed($method->behaviour->start), $method->behaviour->sweeps]);
        $error = $method->errors;
        $errors[] = implode(' ', [$method->name, fixed($error->mean), fixed($error->value), $stateCell($error->at), $error->unvisited, $error->tied]);
        $actionErrors[] = $method->name . ' ' . implode(' ', array_map('fixed', $error->perAction));
        $summary = $method->training;
        $training[] = implode(' ', [$method->name, $summary->totalSteps, $summary->goals, $summary->pits, $summary->timeouts,
            $summary->best->number, average($summary->best->totalReturn, $settings->blockSize),
            average($summary->last->totalReturn, $settings->blockSize), $summary->reach]);
        $visited[] = $method->name . ' ' . implode(' ', array_map(fn($item) => $stateCell($item->state) . ':' . $item->visits, $summary->visited));
        $last = $method->episodes[count($method->episodes) - 1];
        $lastEpisodes[] = $method->name . ' return ' . $last->totalReturn . ' steps ' . $last->steps . ' end ' . $last->ending
            . ' ' . implode(' ', array_map(fn($position) => cell($world, $position), $last->path));
        foreach ($summary->phases as $phase) {
            $phases[] = $method->name . ' ' . $phase->first . '-' . $phase->last . ' alpha ' . $phase->alpha . ' epsilon ' . $phase->epsilon
                . ' mean_return ' . average($phase->totalReturn, $phase->count) . ' mean_steps ' . average($phase->totalSteps, $phase->count)
                . ' goals ' . $phase->goals;
        }
    }
    return sections([['summary states ' . count($world->states) . ' start ' . cell($world, $world->start)
        . ' rollouts ' . $settings->rollouts . ' step_limit ' . $settings->limit], $values, $improvement, $absorbed, $behaviour,
        $errors, $actionErrors, $rolloutLines, $terminalLines, $agreementLines, $training, $visited, $lastEpisodes, $phases]);
}

$data = prepareData();
$methods = [];
foreach (METHODS as $name) {
    $methods[] = learn($data, $name);
}
$policies = array_merge([(object) ['name' => 'value_iteration', 'policy' => $data->optimal->policy],
    (object) ['name' => 'policy_iteration', 'policy' => $data->iteration->policy]], $methods);
foreach ($policies as $policy) {
    assessPolicy($data, $policy);
}
foreach ($methods as $method) {
    $method->training = trainingSummary($data, $method, $policies[0]->rollouts->totalReturn);
}
$qTable = array_merge(['method,row,col,action,value,visits'], qRows('value_iteration', $data->world, $data->optimal->table));
foreach ($methods as $method) {
    $qTable = array_merge($qTable, qRows($method->name, $data->world, $method->table, $method->visits));
}
writeReports(['values.txt' => valuesReport($data, sensitivity($data)), 'policies.txt' => policiesReport($data, $policies),
    'q_tables.csv' => $qTable, 'learning_curves.csv' => learningReport($data, $methods),
    'evaluation.txt' => evaluationReport($data, $policies, $methods)]);
