<?php

require_once __DIR__ . '/data_io.php';
require_once __DIR__ . '/models.php';
require_once __DIR__ . '/integrator.php';
require_once __DIR__ . '/fitting.php';
require_once __DIR__ . '/report.php';

function sumValues(array $values, int $first = 0, ?int $end = null)
{
    $end = $end ?? count($values);
    $total = 0;
    for ($i = $first; $i < $end; $i++) {
        $total += $values[$i];
    }
    return $total;
}

function dot(array $left, array $right): float
{
    $total = 0.0;
    for ($i = 0; $i < count($left); $i++) {
        $total += $left[$i] * $right[$i];
    }
    return $total;
}

function squaredError(array $series, float $coefficient, array $observed): float
{
    $total = 0.0;
    foreach ($series as $i => $value) {
        $difference = $coefficient * $value - $observed[$i];
        $total += $difference * $difference;
    }
    return $total;
}

function rmse(float $error, int $count): float
{
    return sqrt($error / $count);
}

function incidence(array $states): array
{
    return array_map(fn($state) => $state[5], $states);
}

function maximumIndex(array $values): int
{
    $best = 0;
    for ($i = 1; $i < count($values); $i++) {
        if ($values[$i] > $values[$best]) {
            $best = $i;
        }
    }
    return $best;
}

function cumulative(array $values): array
{
    $total = 0;
    $result = [];
    foreach ($values as $value) {
        $total += $value;
        $result[] = $total;
    }
    return $result;
}

function multiplierSequence(array $interventions, int $count): array
{
    $multipliers = [];
    $active = 0;
    for ($day = 1; $day <= $count; $day++) {
        while ($active + 1 < count($interventions) && $interventions[$active + 1]->day <= $day) {
            $active++;
        }
        $multipliers[] = $interventions[$active]->multiplier;
    }
    return $multipliers;
}

function prepare(object $data): object
{
    $N = 0;
    $fatalityTotal = 0.0;
    foreach ($data->groups as $group) {
        $N += $group->population;
        $fatalityTotal += $group->population * $group->fatality;
    }
    $data->N = $N;
    $data->T = count($data->cases);
    $data->fatality = $fatalityTotal / $N;
    $data->caseTotal = sumValues($data->cases);
    $data->deathTotal = sumValues($data->deaths);
    $data->multipliers = multiplierSequence($data->interventions, $data->T);
    $data->betaSpacing = ($data->params->betaMax - $data->params->betaMin) / ($data->params->betaCount - 1);
    $data->rhoSpacing = ($data->params->rhoMax - $data->params->rhoMin) / ($data->params->rhoCount - 1);
    return $data;
}

function trajectory(object $data, float $beta, float $gamma, ?array $multipliers = null, ?float $sigma = null): array
{
    return simulate(seird($data, $beta, $gamma, $sigma), $multipliers ?? $data->multipliers);
}

function objective(object $data, float $beta, float $gamma, float $rho): float
{
    return squaredError(incidence(trajectory($data, $beta, $gamma)), $rho, $data->cases);
}

function goldenLines(array &$lines, object $result, int $round, string $name, int $count): void
{
    foreach ($result->records as $i => $record) {
        $lines[] = 'golden ' . $round . ' ' . $name . ' ' . $i . ' a ' . formatReal($record->a, 6) . ' b ' . formatReal($record->b, 6)
            . ' c ' . formatReal($record->c, 6) . ' d ' . formatReal($record->d, 6) . ' rmse ' . formatReal(rmse($record->fc, $count)) . ' ' . formatReal(rmse($record->fd, $count));
    }
    $lines[] = 'golden_result ' . $round . ' ' . $name . ' ' . formatReal($result->point, 6) . ' sse ' . formatReal($result->value, 1);
}

function fitModel(object $data, array &$lines): object
{
    $p = $data->params;
    $betas = [];
    $rhos = [];
    for ($i = 0; $i < $p->betaCount; $i++) {
        $betas[] = $p->betaMin + ($p->betaMax - $p->betaMin) * $i / ($p->betaCount - 1);
    }
    for ($i = 0; $i < $p->rhoCount; $i++) {
        $rhos[] = $p->rhoMin + ($p->rhoMax - $p->rhoMin) * $i / ($p->rhoCount - 1);
    }
    $lines[] = 'data days ' . $data->T . ' cases ' . $data->caseTotal . ' deaths ' . $data->deathTotal . ' population ' . $data->N . ' fatality ' . formatReal($data->fatality, 6);
    $lines[] = 'grid gamma ' . formatReal($p->gamma) . ' rho ' . implode(' ', array_map(fn($value) => formatReal($value), $rhos));
    $grid = null;
    foreach ($betas as $beta) {
        $series = incidence(trajectory($data, $beta, $p->gamma));
        $errors = [];
        foreach ($rhos as $rho) {
            $error = squaredError($series, $rho, $data->cases);
            $errors[] = $error;
            if ($grid === null || $error < $grid->error) {
                $grid = (object) ['beta' => $beta, 'gamma' => $p->gamma, 'rho' => $rho, 'error' => $error];
            }
        }
        $lines[] = 'grid beta ' . formatReal($beta) . ' rmse ' . implode(' ', array_map(fn($error) => formatReal(rmse($error, $data->T), 2), $errors));
    }
    $lines[] = 'grid_best beta ' . formatReal($grid->beta) . ' rho ' . formatReal($grid->rho) . ' sse ' . formatReal($grid->error, 1) . ' rmse ' . formatReal(rmse($grid->error, $data->T));
    $beta = $grid->beta;
    $rho = $grid->rho;
    $goldenError = $grid->error;
    for ($round = 1; $round <= $p->rounds; $round++) {
        $betaSearch = goldenSearch(fn($x) => objective($data, $x, $p->gamma, $rho), $beta - $data->betaSpacing, $beta + $data->betaSpacing, $p->goldenIterations);
        goldenLines($lines, $betaSearch, $round, 'beta', $data->T);
        $beta = $betaSearch->point;
        $series = incidence(trajectory($data, $beta, $p->gamma));
        $rhoSearch = goldenSearch(fn($x) => squaredError($series, $x, $data->cases), $rho - $data->rhoSpacing, $rho + $data->rhoSpacing, $p->goldenIterations);
        goldenLines($lines, $rhoSearch, $round, 'rho', $data->T);
        $rho = $rhoSearch->point;
        $goldenError = $rhoSearch->value;
    }
    $golden = (object) ['beta' => $beta, 'gamma' => $p->gamma, 'rho' => $rho, 'error' => $goldenError];
    $simplex = nelderMead(fn($x, $y) => objective($data, $x, $y, $rho), $beta, $p->gamma, $p);
    $vertexText = fn($vertex) => 'beta ' . formatReal($vertex->point[0], 6) . ' gamma ' . formatReal($vertex->point[1], 6) . ' rmse ' . formatReal(rmse($vertex->value, $data->T));
    foreach ($simplex->initial as $vertex) {
        $lines[] = 'simplex ' . $vertex->number . ' ' . $vertexText($vertex);
    }
    foreach ($simplex->records as $record) {
        $lines[] = 'nelder_mead ' . $record->iteration . ' ' . $record->operation . ' ' . $vertexText($record->best);
    }
    foreach ($simplex->vertices as $i => $vertex) {
        $lines[] = 'final_simplex ' . ($i + 1) . ' ' . $vertexText($vertex);
    }
    $best = $simplex->vertices[0];
    $fit = (object) ['beta' => $best->point[0], 'gamma' => $best->point[1], 'rho' => $rho, 'error' => $best->value];
    $fit->r0 = $fit->beta / $fit->gamma;
    $mean = $data->caseTotal / $data->T;
    $sst = 0.0;
    foreach ($data->cases as $cases) {
        $difference = $cases - $mean;
        $sst += $difference * $difference;
    }
    $lines[] = 'fitted beta ' . formatReal($fit->beta, 6) . ' gamma ' . formatReal($fit->gamma, 6) . ' rho ' . formatReal($rho, 6)
        . ' sigma ' . formatReal($p->sigma, 6) . ' r0 ' . formatReal($fit->r0);
    $lines[] = 'sse grid ' . formatReal($grid->error, 1) . ' golden ' . formatReal($golden->error, 1) . ' nelder_mead ' . formatReal($fit->error, 1)
        . ' rmse ' . formatReal(rmse($fit->error, $data->T)) . ' r2 ' . formatReal(1 - $fit->error / $sst);
    foreach ([['grid', $grid], ['golden', $golden], ['nelder_mead', $fit]] as [$name, $stage]) {
        $lines[] = 'stage ' . $name . ' beta ' . formatReal($stage->beta, 6) . ' gamma ' . formatReal($stage->gamma, 6) . ' rho ' . formatReal($stage->rho, 6)
            . ' r0 ' . formatReal($stage->beta / $stage->gamma) . ' rmse ' . formatReal(rmse($stage->error, $data->T));
    }
    return $fit;
}

function fittedCourse(object $data, object $fit): object
{
    $model = seird($data, $fit->beta, $fit->gamma);
    $states = simulate($model, $data->multipliers);
    $infections = incidence($states);
    $reported = $residuals = $deaths = $average7 = [];
    foreach ($states as $i => $state) {
        $reported[] = $fit->rho * $infections[$i];
        $residuals[] = $data->cases[$i] - $reported[$i];
        $deaths[] = $state[4] - ($i === 0 ? 0.0 : $states[$i - 1][4]);
        $average7[] = sumValues($data->cases, max(0, $i - 6), $i + 1) / min($i + 1, 7);
    }
    $cumulativeObserved = cumulative($data->cases);
    $cumulativeReported = cumulative($reported);
    return (object) compact('model', 'states', 'infections', 'reported', 'residuals', 'deaths', 'average7', 'cumulativeObserved', 'cumulativeReported');
}

function residualReport(object $data, object $course, array &$lines): void
{
    $residuals = $course->residuals;
    $reported = $course->reported;
    $absolute = $squares = $differences = 0.0;
    $positive = 0;
    $runs = 1;
    for ($i = 0; $i < $data->T; $i++) {
        $value = $residuals[$i];
        $absolute += abs($value);
        $squares += $value * $value;
        if ($value > 0) {
            $positive++;
        }
        if ($i > 0) {
            $change = $value - $residuals[$i - 1];
            $differences += $change * $change;
            if (($value > 0) !== ($residuals[$i - 1] > 0)) {
                $runs++;
            }
        }
    }
    $maximum = maximumIndex(array_map('abs', $residuals));
    $lines[] = 'residuals sum ' . formatReal(sumValues($residuals), 1) . ' mae ' . formatReal($absolute / $data->T, 1)
        . ' max ' . formatReal($residuals[$maximum], 1) . ' day ' . ($maximum + 1) . ' positive ' . $positive . ' runs ' . $runs
        . ' durbin_watson ' . formatReal($differences / $squares);
    $correlations = [];
    for ($lag = 1; $lag <= 7; $lag++) {
        $product = 0.0;
        for ($i = 0; $i < $data->T - $lag; $i++) {
            $product += $residuals[$i] * $residuals[$i + $lag];
        }
        $correlations[] = formatReal($product / $squares);
    }
    $lines[] = 'autocorrelation ' . implode(' ', $correlations);
    $outliers = 0;
    for ($i = 0; $i < $data->T; $i++) {
        $z = $residuals[$i] / sqrt($reported[$i]);
        if (abs($z) > $data->params->outlier) {
            $lines[] = 'outlier ' . ($i + 1) . ' observed ' . $data->cases[$i] . ' fitted ' . formatReal($reported[$i], 1) . ' z ' . formatReal($z);
            $outliers++;
        }
    }
    $lines[] = 'outliers ' . $outliers;
    $observed = array_fill(0, 7, 0);
    $expected = array_fill(0, 7, 0.0);
    for ($i = 0; $i < $data->T; $i++) {
        $observed[$i % 7] += $data->cases[$i];
        $expected[$i % 7] += $reported[$i];
    }
    $factors = [];
    for ($i = 0; $i < 7; $i++) {
        $factors[] = $observed[$i] / $expected[$i];
        $lines[] = 'weekday ' . ($i + 1) . ' observed ' . $observed[$i] . ' fitted ' . formatReal($expected[$i], 1) . ' factor ' . formatReal($factors[$i]);
    }
    $adjusted = [];
    foreach ($reported as $i => $value) {
        $adjusted[] = $value * $factors[$i % 7];
    }
    $lines[] = 'weekday_adjusted rmse ' . formatReal(rmse(squaredError($adjusted, 1.0, $data->cases), $data->T));
    $burden = sumValues($course->infections);
    $lines[] = 'burden infections ' . formatReal($burden, 1) . ' ascertainment ' . formatReal($data->caseTotal / $burden)
        . ' deaths_per_infection ' . formatReal($data->deathTotal / $burden, 6);
}

function deathReport(object $data, object $course, array &$lines): void
{
    $scale = dot($course->deaths, $data->deaths) / dot($course->deaths, $course->deaths);
    $last = $course->states[count($course->states) - 1];
    $lines[] = 'deaths observed ' . $data->deathTotal . ' model ' . formatReal($last[4], 1)
        . ' rmse ' . formatReal(rmse(squaredError($course->deaths, 1.0, $data->deaths), $data->T)) . ' scale ' . formatReal($scale)
        . ' implied_fatality ' . formatReal($data->fatality * $scale, 6) . ' cfr ' . formatReal($data->deathTotal / $data->caseTotal);
    $correlations = [];
    for ($lag = 0; $lag <= $data->params->deathLag; $lag++) {
        $cross = $caseSquares = $deathSquares = 0;
        for ($i = 0; $i < $data->T - $lag; $i++) {
            $cross += $data->cases[$i] * $data->deaths[$i + $lag];
            $caseSquares += $data->cases[$i] * $data->cases[$i];
            $deathSquares += $data->deaths[$i + $lag] * $data->deaths[$i + $lag];
        }
        $correlation = $cross / sqrt((float) $caseSquares * $deathSquares);
        $correlations[] = $correlation;
        $fatality = sumValues($data->deaths, $lag) / sumValues($data->cases, 0, $data->T - $lag);
        $lines[] = 'death_lag ' . $lag . ' correlation ' . formatReal($correlation) . ' cfr ' . formatReal($fatality);
    }
    $lines[] = 'death_best_lag ' . maximumIndex($correlations);
}

function weeklyReport(object $data, object $course, array &$lines): void
{
    $previous = null;
    for ($start = 0, $week = 1; $start < $data->T; $start += 7, $week++) {
        $end = min($start + 7, $data->T);
        $cases = sumValues($data->cases, $start, $end);
        $growth = $previous === null ? '-' : formatReal($cases / $previous);
        $lines[] = 'weekly ' . $week . ' days ' . ($start + 1) . ' ' . $end . ' observed ' . $cases . ' fitted ' . formatReal(sumValues($course->reported, $start, $end), 1)
            . ' deaths_observed ' . sumValues($data->deaths, $start, $end) . ' deaths_model ' . formatReal(sumValues($course->deaths, $start, $end), 1) . ' growth ' . $growth;
        $previous = $cases;
    }
}

function parameterProfiles(object $data, object $fit, array &$lines): object
{
    $standardErrors = (object) [];
    foreach (['beta', 'gamma', 'rho'] as $name) {
        $scores = [];
        for ($k = -5; $k <= 5; $k++) {
            $value = $fit->$name * (1 + $k / 100);
            $parameters = clone $fit;
            $parameters->$name = $value;
            $score = objective($data, $parameters->beta, $parameters->gamma, $parameters->rho);
            $scores[] = $score;
            $lines[] = 'profile ' . $name . ' ' . $k . ' value ' . formatReal($value, 6) . ' rmse ' . formatReal(rmse($score, $data->T));
        }
        $h = $fit->$name / 100;
        $curvature = ($scores[6] - 2 * $scores[5] + $scores[4]) / ($h * $h);
        $variance = $fit->error / ($data->T - 3);
        $standardErrors->$name = sqrt(2 * $variance / $curvature);
        $lines[] = 'profile_se ' . $name . ' ' . formatReal($standardErrors->$name, 6);
    }
    return $standardErrors;
}

function backtestReport(object $data, object $fit, object $course, array &$lines): void
{
    $count = $data->T - $data->params->holdout;
    $multipliers = array_slice($data->multipliers, 0, $count);
    $observed = array_slice($data->cases, 0, $count);
    $betaSearch = goldenSearch(fn($beta) => squaredError(incidence(trajectory($data, $beta, $fit->gamma, $multipliers)), $fit->rho, $observed),
        $fit->beta - $data->betaSpacing, $fit->beta + $data->betaSpacing, $data->params->goldenIterations);
    $beta = $betaSearch->point;
    $training = incidence(trajectory($data, $beta, $fit->gamma, $multipliers));
    $rhoSearch = goldenSearch(fn($rho) => squaredError($training, $rho, $observed), $fit->rho - $data->rhoSpacing, $fit->rho + $data->rhoSpacing, $data->params->goldenIterations);
    $rho = $rhoSearch->point;
    $forecast = array_map(fn($value) => $rho * $value, array_slice(incidence(trajectory($data, $beta, $fit->gamma)), $count));
    $heldOut = array_slice($data->cases, $count);
    $testError = squaredError($forecast, 1.0, $heldOut);
    $fullError = squaredError(array_slice($course->reported, $count), 1.0, $heldOut);
    $lines[] = 'backtest train_days ' . $count . ' beta ' . formatReal($beta, 6) . ' rho ' . formatReal($rho, 6)
        . ' train_rmse ' . formatReal(rmse($rhoSearch->value, $count)) . ' test_rmse ' . formatReal(rmse($testError, $data->params->holdout))
        . ' full_fit_test_rmse ' . formatReal(rmse($fullError, $data->params->holdout));
    foreach ($forecast as $i => $value) {
        $lines[] = 'backtest_day ' . ($count + $i + 1) . ' observed ' . $heldOut[$i] . ' forecast ' . formatReal($value, 1) . ' error ' . formatReal($heldOut[$i] - $value, 1);
    }
}

function interventionEffects(object $data, object $fit, array &$lines): void
{
    $estimated = array_map(fn($line) => clone $line, $data->interventions);
    $error = $fit->error;
    for ($k = 1; $k < count($estimated); $k++) {
        $original = $data->interventions[$k];
        $search = goldenSearch(function ($multiplier) use ($estimated, $k, $data, $fit) {
            $changed = array_map(fn($line) => clone $line, $estimated);
            $changed[$k]->multiplier = $multiplier;
            $sequence = multiplierSequence($changed, $data->T);
            return squaredError(incidence(trajectory($data, $fit->beta, $fit->gamma, $sequence)), $fit->rho, $data->cases);
        }, $original->multiplier - $data->params->effectWidth, $original->multiplier + $data->params->effectWidth, $data->params->goldenIterations);
        $estimated[$k]->multiplier = $search->point;
        $error = $search->value;
        $lines[] = 'effect ' . ($k + 1) . ' day ' . $original->day . ' given ' . formatReal($original->multiplier)
            . ' estimated ' . formatReal($search->point, 6) . ' sse ' . formatReal($error, 1);
    }
    $lines[] = 'effect_sse before ' . formatReal($fit->error, 1) . ' after ' . formatReal($error, 1) . ' rmse ' . formatReal(rmse($error, $data->T));
}

function sensitivityReport(object $data, object $fit, array &$lines): void
{
    foreach (['beta', 'gamma', 'sigma', 'rho'] as $name) {
        foreach ([0.9, 1.1] as $factor) {
            $parameters = (object) ['beta' => $fit->beta, 'gamma' => $fit->gamma, 'sigma' => $data->params->sigma, 'rho' => $fit->rho];
            $parameters->$name *= $factor;
            $states = trajectory($data, $parameters->beta, $parameters->gamma, $data->multipliers, $parameters->sigma);
            $series = incidence($states);
            $peak = maximumIndex($series);
            $error = squaredError($series, $parameters->rho, $data->cases);
            $last = $states[count($states) - 1];
            $lines[] = 'sensitivity ' . $name . ' ' . formatReal($factor, 2) . ' r0 ' . formatReal($parameters->beta / $parameters->gamma)
                . ' rmse ' . formatReal(rmse($error, $data->T)) . ' peak_day ' . ($peak + 1) . ' peak ' . formatReal($parameters->rho * $series[$peak], 1)
                . ' attack ' . formatReal(($data->N - $last[0]) / $data->N);
        }
    }
}

function ageIncidence(array $states, int $count): array
{
    $result = [];
    foreach ($states as $state) {
        $total = 0.0;
        for ($g = 0; $g < $count; $g++) {
            $total += $state[6 * $g + 5];
        }
        $result[] = $total;
    }
    return $result;
}

function prepareAge(object $data, object $fit): object
{
    $contacts = 0.0;
    foreach ($data->groups as $g => $group) {
        $contacts += $group->population * sumValues($data->contacts[$g]);
    }
    $meanContacts = $contacts / $data->N;
    $matrix = [];
    foreach ($data->contacts as $row) {
        $matrix[] = array_map(fn($value) => $value / $meanContacts, $row);
    }
    $model = ageSeird($data, $fit->beta, $fit->gamma, $matrix);
    $states = simulate($model, $data->multipliers);
    $infections = ageIncidence($states, count($data->groups));
    return (object) compact('meanContacts', 'matrix', 'model', 'states', 'infections');
}

function modelReport(object $data, object $fit, object $course, object $age, array &$lines): void
{
    $sirIncidence = fn($beta) => array_map(fn($state) => $state[3], simulate(sir($data, $beta, $fit->gamma), $data->multipliers));
    $sirSeries = $sirIncidence($fit->beta);
    foreach ([['sir', $sirSeries], ['seir', $course->infections], ['age', $age->infections]] as [$name, $series]) {
        $optimalRho = dot($data->cases, $series) / dot($series, $series);
        $lines[] = 'model ' . $name . ' rmse ' . formatReal(rmse(squaredError($series, $fit->rho, $data->cases), $data->T))
            . ' peak_day ' . (maximumIndex($series) + 1) . ' rho_opt ' . formatReal($optimalRho, 6)
            . ' rmse_opt ' . formatReal(rmse(squaredError($series, $optimalRho, $data->cases), $data->T));
    }
    $search = goldenSearch(fn($beta) => squaredError($sirIncidence($beta), $fit->rho, $data->cases),
        $data->params->betaMin, $data->params->betaMax, $data->params->goldenIterations);
    $lines[] = 'model sir_fit beta ' . formatReal($search->point, 6) . ' rmse ' . formatReal(rmse($search->value, $data->T))
        . ' peak_day ' . (maximumIndex($sirIncidence($search->point)) + 1);
}

function finalSize(float $reproduction): float
{
    if ($reproduction <= 1) {
        return 0.0;
    }
    $low = 1 - 1 / $reproduction;
    $high = 1.0;
    for ($iteration = 0; $iteration < 20; $iteration++) {
        $middle = ($low + $high) / 2;
        $value = 1 - $middle - exp(-$reproduction * $middle);
        if ($value > 0) {
            $low = $middle;
        } else {
            $high = $middle;
        }
    }
    return ($low + $high) / 2;
}

function largestEigenpair(array $matrix): object
{
    $vector = array_fill(0, count($matrix), 1 / count($matrix));
    $value = 0.0;
    for ($iteration = 0; $iteration < 200; $iteration++) {
        $product = [];
        foreach ($matrix as $row) {
            $product[] = dot($row, $vector);
        }
        $value = sumValues($product);
        $vector = array_map(fn($component) => $component / $value, $product);
    }
    return (object) compact('value', 'vector');
}

function generationAnalysis(object $data, object $fit, object $course): object
{
    $states = simulate(generationModel($data->params->sigma, $fit->gamma), array_fill(0, $data->params->generation, 1.0));
    $inflows = array_map(fn($state) => $state[2], $states);
    $coverage = sumValues($inflows);
    $weights = array_map(fn($value) => $value / $coverage, $inflows);
    $mean = 0.0;
    foreach ($weights as $s => $value) {
        $mean += ($s + 1 - 0.5) * $value;
    }
    $rt = [];
    foreach ($data->multipliers as $i => $multiplier) {
        $susceptible = $i === 0 ? $course->model->initial[0] : $course->states[$i - 1][0];
        $rt[] = $fit->r0 * $multiplier * $susceptible / $data->N;
    }
    $pressure = [];
    for ($i = 0; $i < $data->T; $i++) {
        $total = 0.0;
        for ($s = 1; $s <= min(count($weights), $i); $s++) {
            $total += $weights[$s - 1] * $data->cases[$i - $s];
        }
        $pressure[] = $total;
    }
    $empirical = [];
    for ($i = 0; $i < $data->T; $i++) {
        $empirical[] = $i + 1 < count($weights) + 7 ? null : sumValues($data->cases, $i - 6, $i + 1) / sumValues($pressure, $i - 6, $i + 1);
    }
    $theory = 1 / $data->params->sigma + 1 / $fit->gamma;
    return (object) compact('coverage', 'weights', 'mean', 'theory', 'rt', 'empirical');
}

function counterfactualReport(object $data, object $fit, object $course, array &$lines): void
{
    $totalFitted = sumValues($course->reported);
    $reported = fn($interventions) => array_map(fn($value) => $fit->rho * $value,
        incidence(trajectory($data, $fit->beta, $fit->gamma, multiplierSequence($interventions, $data->T))));
    $withoutAll = $reported([$data->interventions[0]]);
    $total = sumValues($withoutAll);
    $peak = maximumIndex($withoutAll);
    $lines[] = 'counterfactual none reported ' . formatReal($total, 1) . ' peak_day ' . ($peak + 1) . ' peak ' . formatReal($withoutAll[$peak], 1)
        . ' averted ' . formatReal($total - $totalFitted, 1);
    for ($k = 1; $k < count($data->interventions); $k++) {
        $reduced = $data->interventions;
        array_splice($reduced, $k, 1);
        $value = sumValues($reported($reduced));
        $lines[] = 'counterfactual without ' . ($k + 1) . ' reported ' . formatReal($value, 1) . ' averted ' . formatReal($value - $totalFitted, 1);
    }
    for ($k = 1; $k < count($data->interventions); $k++) {
        foreach ([-7, 7] as $shift) {
            $changed = array_map(fn($line) => clone $line, $data->interventions);
            $changed[$k]->day += $shift;
            $value = sumValues($reported($changed));
            $lines[] = 'timing ' . ($k + 1) . ' shift ' . $shift . ' reported ' . formatReal($value, 1) . ' change ' . formatReal($value - $totalFitted, 1);
        }
    }
}

function reproductionReport(object $data, object $fit, object $course, array &$lines): array
{
    $analysis = generationAnalysis($data, $fit, $course);
    $longRun = trajectory($data, $fit->beta, $fit->gamma, array_fill(0, 730, 1.0));
    $last = $longRun[count($longRun) - 1];
    $lines[] = 'r0 ' . formatReal($fit->r0) . ' herd_immunity ' . formatReal(1 - 1 / $fit->r0);
    $lines[] = 'final_size equation ' . formatReal(finalSize($fit->r0)) . ' simulated ' . formatReal(($data->N - $last[0]) / $data->N);
    $lines[] = 'generation mean ' . formatReal($analysis->mean) . ' theory ' . formatReal($analysis->theory) . ' coverage ' . formatReal($analysis->coverage);
    foreach ($analysis->weights as $i => $value) {
        $lines[] = 'generation_weight ' . ($i + 1) . ' ' . formatReal($value, 6);
    }
    $peak = maximumIndex($course->infections);
    $infectious = maximumIndex(array_map(fn($state) => $state[2], $course->states));
    $observed = maximumIndex($data->cases);
    $average = maximumIndex($course->average7);
    $lines[] = 'peak model day ' . ($peak + 1) . ' incidence ' . formatReal($course->infections[$peak], 1) . ' reported ' . formatReal($course->reported[$peak], 1)
        . ' infectious_day ' . ($infectious + 1) . ' infectious ' . formatReal($course->states[$infectious][2], 1);
    $lines[] = 'peak observed day ' . ($observed + 1) . ' cases ' . $data->cases[$observed] . ' average7_day ' . ($average + 1)
        . ' average7 ' . formatReal($course->average7[$average], 2);
    foreach ($data->interventions as $k => $line) {
        $start = $line->day - 1;
        $end = $k + 1 < count($data->interventions) ? $data->interventions[$k + 1]->day - 1 : $data->T;
        $errors = array_slice($course->residuals, $start, $end - $start);
        $lines[] = 'period ' . ($k + 1) . ' days ' . ($start + 1) . ' ' . $end . ' multiplier ' . formatReal($line->multiplier)
            . ' rt_start ' . formatReal($analysis->rt[$start]) . ' rt_end ' . formatReal($analysis->rt[$end - 1])
            . ' observed ' . sumValues($data->cases, $start, $end) . ' fitted ' . formatReal(sumValues($course->reported, $start, $end), 1)
            . ' rmse ' . formatReal(rmse(dot($errors, $errors), $end - $start)) . ' bias ' . formatReal(sumValues($errors) / ($end - $start), 1);
    }
    foreach ($data->params->milestones as $target) {
        $observedDay = $fittedDay = 'never';
        foreach ($course->cumulativeObserved as $i => $value) {
            if ($value >= $target) {
                $observedDay = $i + 1;
                break;
            }
        }
        foreach ($course->cumulativeReported as $i => $value) {
            if ($value >= $target) {
                $fittedDay = $i + 1;
                break;
            }
        }
        $lines[] = 'milestone ' . $target . ' observed ' . $observedDay . ' fitted ' . $fittedDay;
    }
    counterfactualReport($data, $fit, $course, $lines);
    for ($i = 1; $i < $data->T; $i++) {
        if (($analysis->rt[$i] < 1) !== ($analysis->rt[$i - 1] < 1)) {
            $lines[] = 'rt_cross day ' . ($i + 1) . ' ' . ($analysis->rt[$i] < 1 ? 'down' : 'up');
        }
    }
    for ($i = 0; $i < $data->T; $i++) {
        $lines[] = 'rt ' . ($i + 1) . ' model ' . formatReal($analysis->rt[$i]) . ' empirical ' . formatReal($analysis->empirical[$i]);
    }
    return $analysis->rt;
}

function nextGenerationMatrix(object $data, float $r0, array $contacts): array
{
    $matrix = [];
    foreach ($contacts as $g => $row) {
        $values = [];
        foreach ($row as $h => $value) {
            $values[] = $r0 * $value * $data->groups[$g]->population / $data->groups[$h]->population;
        }
        $matrix[] = $values;
    }
    return $matrix;
}

function ageFinalSizes(object $data, object $fit, object $age): object
{
    $equation = array_fill(0, count($data->groups), 1.0);
    for ($iteration = 0; $iteration < 100; $iteration++) {
        $updated = [];
        foreach ($age->matrix as $row) {
            $total = 0.0;
            foreach ($row as $h => $value) {
                $total += $fit->r0 * $value * $equation[$h];
            }
            $updated[] = 1 - exp(-$total);
        }
        $equation = $updated;
    }
    $states = simulate($age->model, array_fill(0, 730, 1.0));
    $final = $states[count($states) - 1];
    $simulated = [];
    $equationTotal = $simulatedTotal = 0.0;
    foreach ($data->groups as $g => $group) {
        $simulated[] = ($group->population - $final[6 * $g]) / $group->population;
        $equationTotal += $group->population * $equation[$g];
        $simulatedTotal += $group->population * $simulated[$g];
    }
    $equationTotal /= $data->N;
    $simulatedTotal /= $data->N;
    return (object) compact('equation', 'simulated', 'equationTotal', 'simulatedTotal');
}

function contactChangeReport(object $data, object $fit, object $age, array &$lines): void
{
    foreach ($data->contactChanges as $change) {
        $target = 0;
        foreach ($data->groups as $g => $group) {
            if ($group->name === $change->group) {
                $target = $g;
                break;
            }
        }
        $matrix = [];
        foreach ($age->matrix as $g => $row) {
            $values = [];
            foreach ($row as $h => $value) {
                $values[] = $value * ($g === $target ? $change->factor : 1) * ($h === $target ? $change->factor : 1);
            }
            $matrix[] = $values;
        }
        $eigenpair = largestEigenpair(nextGenerationMatrix($data, $fit->r0, $matrix));
        $model = ageSeird($data, $fit->beta, $fit->gamma, $matrix);
        $states = simulate($model, $data->multipliers);
        $infections = sumValues(ageIncidence($states, count($data->groups)));
        $final = $states[count($states) - 1];
        $deaths = $affected = 0.0;
        foreach ($data->groups as $g => $group) {
            $deaths += $final[6 * $g + 4];
            $affected += $group->population - $final[6 * $g];
        }
        $lines[] = 'contact_change ' . $change->name . ' group ' . $change->group . ' factor ' . formatReal($change->factor) . ' r0_age ' . formatReal($eigenpair->value)
            . ' infections ' . formatReal($infections, 1) . ' deaths ' . formatReal($deaths, 1) . ' attack ' . formatReal($affected / $data->N);
    }
}

function ageReport(object $data, object $fit, object $age, array $homogeneousRt, array &$lines): void
{
    $matrix = nextGenerationMatrix($data, $fit->r0, $age->matrix);
    $eigenpair = largestEigenpair($matrix);
    foreach ($matrix as $g => $row) {
        $lines[] = 'ngm ' . $data->groups[$g]->name . ' ' . implode(' ', array_map(fn($value) => formatReal($value), $row));
    }
    $lines[] = 'r0_age ' . formatReal($eigenpair->value) . ' ratio ' . formatReal($eigenpair->value / $fit->r0) . ' kbar ' . formatReal($age->meanContacts)
        . ' eigenvector ' . implode(' ', array_map(fn($value) => formatReal($value), $eigenpair->vector));
    $sizes = ageFinalSizes($data, $fit, $age);
    foreach ($data->groups as $g => $group) {
        $lines[] = 'final_size_age ' . $group->name . ' equation ' . formatReal($sizes->equation[$g]) . ' simulated ' . formatReal($sizes->simulated[$g]);
    }
    $lines[] = 'final_size_age total equation ' . formatReal($sizes->equationTotal) . ' simulated ' . formatReal($sizes->simulatedTotal);
    for ($i = 0; $i < $data->T; $i += 7) {
        $previous = $i === 0 ? $age->model->initial : $age->states[$i - 1];
        $effective = [];
        foreach ($age->matrix as $g => $row) {
            $values = [];
            foreach ($row as $h => $value) {
                $values[] = $data->multipliers[$i] * $fit->r0 * $value * $previous[6 * $g] / $data->groups[$h]->population;
            }
            $effective[] = $values;
        }
        $eigenvalue = largestEigenpair($effective)->value;
        $lines[] = 'age_rt ' . ($i + 1) . ' ' . formatReal($eigenvalue) . ' homogeneous ' . formatReal($homogeneousRt[$i]);
    }
    for ($start = 0, $week = 1; $start < $data->T; $start += 7, $week++) {
        $end = min($start + 7, $data->T);
        $totals = [];
        foreach ($data->groups as $g => $group) {
            $total = 0.0;
            for ($i = $start; $i < $end; $i++) {
                $total += $age->states[$i][6 * $g + 5];
            }
            $totals[] = formatReal($total, 1);
        }
        $lines[] = 'age_weekly ' . $week . ' days ' . ($start + 1) . ' ' . $end . ' ' . implode(' ', $totals);
    }
    $groupIncidence = [];
    $totals = [];
    foreach ($data->groups as $g => $group) {
        $series = array_map(fn($state) => $state[6 * $g + 5], $age->states);
        $groupIncidence[] = $series;
        $totals[] = sumValues($series);
    }
    $allInfections = sumValues($totals);
    $final = $age->states[count($age->states) - 1];
    foreach ($data->groups as $g => $group) {
        $peak = maximumIndex($groupIncidence[$g]);
        $lines[] = 'age ' . $group->name . ' attack ' . formatReal(($group->population - $final[6 * $g]) / $group->population)
            . ' infections ' . formatReal($totals[$g], 1) . ' share ' . formatReal($totals[$g] / $allInfections) . ' deaths ' . formatReal($final[6 * $g + 4], 1)
            . ' peak_day ' . ($peak + 1) . ' peak ' . formatReal($groupIncidence[$g][$peak], 1);
    }
    contactChangeReport($data, $fit, $age, $lines);
}

function scenarioReport(object $data, object $fit, object $course, object $age, object $standardErrors, array &$lines): array
{
    $csv = ['scenario,day,incidence,reported'];
    $reference = null;
    $betaLow = $fit->beta - 2 * $standardErrors->beta;
    $betaHigh = $fit->beta + 2 * $standardErrors->beta;
    foreach ($data->scenarios as $scenario) {
        $multipliers = array_fill(0, $data->params->horizon, $scenario->multiplier);
        $current = $course->states[count($course->states) - 1];
        $states = simulate($course->model, $multipliers, $current);
        $infections = incidence($states);
        $reported = array_map(fn($value) => $fit->rho * $value, $infections);
        foreach ($states as $i => $state) {
            $csv[] = $scenario->name . ',' . ($data->T + $i + 1) . ',' . formatReal($infections[$i], 1) . ',' . formatReal($reported[$i], 1);
        }
        $total = sumValues($reported);
        if ($reference === null) {
            $reference = $total;
        }
        $peak = maximumIndex($reported);
        $below = 'never';
        $daysAbove = 0;
        foreach ($reported as $i => $value) {
            if ($value < $data->params->threshold && $below === 'never') {
                $below = $data->T + $i + 1;
            }
            if ($value >= $data->params->threshold) {
                $daysAbove++;
            }
        }
        $rt = $fit->r0 * $scenario->multiplier * $current[0] / $data->N;
        $final = $states[count($states) - 1];
        $attack = ($data->N - $final[0]) / $data->N;
        $lines[] = 'scenario ' . $scenario->name . ' multiplier ' . formatReal($scenario->multiplier) . ' rt ' . formatReal($rt) . ' reported ' . formatReal($total, 1)
            . ' peak_day ' . ($data->T + $peak + 1) . ' peak ' . formatReal($reported[$peak], 1) . ' attack ' . formatReal($attack)
            . ' final_size ' . formatReal(finalSize($fit->r0 * $scenario->multiplier)) . ' averted ' . formatReal($reference - $total, 1)
            . ' below ' . $below . ' days_above ' . $daysAbove;
        $extended = array_merge($data->multipliers, $multipliers);
        $band = [];
        foreach ([$betaLow, $betaHigh] as $beta) {
            $extendedStates = trajectory($data, $beta, $fit->gamma, $extended);
            $reportedTotal = 0.0;
            for ($i = $data->T; $i < count($extendedStates); $i++) {
                $reportedTotal += $fit->rho * $extendedStates[$i][5];
            }
            $band[] = $reportedTotal;
        }
        $lines[] = 'scenario_band ' . $scenario->name . ' beta_low ' . formatReal($betaLow, 6) . ' reported_low ' . formatReal($band[0], 1)
            . ' beta_high ' . formatReal($betaHigh, 6) . ' reported_high ' . formatReal($band[1], 1);
        $currentAge = $age->states[count($age->states) - 1];
        $futureAge = simulate($age->model, $multipliers, $currentAge);
        $finalAge = $futureAge[count($futureAge) - 1];
        $fractions = [];
        $deaths = 0.0;
        foreach ($data->groups as $g => $group) {
            $fractions[] = formatReal(($group->population - $finalAge[6 * $g]) / $group->population);
            $deaths += $finalAge[6 * $g + 4];
        }
        $lines[] = 'scenario_age ' . $scenario->name . ' attack ' . implode(' ', $fractions) . ' deaths ' . formatReal($deaths, 1);
    }
    return $csv;
}

function trajectoryLines(object $data, object $course): array
{
    $lines = ['day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported'];
    foreach ($course->states as $i => $state) {
        $values = array_map(fn($value) => formatReal($value, 1), $state);
        $lines[] = implode(',', array_merge([$i + 1], $values, [formatReal($course->reported[$i], 1), $data->cases[$i], formatReal($course->average7[$i], 2),
            $course->cumulativeObserved[$i], formatReal($course->cumulativeReported[$i], 1)]));
    }
    return $lines;
}

function main(): void
{
    $data = prepare(readInputs());
    $fitLines = [];
    $fit = fitModel($data, $fitLines);
    $course = fittedCourse($data, $fit);
    $age = prepareAge($data, $fit);
    residualReport($data, $course, $fitLines);
    deathReport($data, $course, $fitLines);
    weeklyReport($data, $course, $fitLines);
    $standardErrors = parameterProfiles($data, $fit, $fitLines);
    backtestReport($data, $fit, $course, $fitLines);
    interventionEffects($data, $fit, $fitLines);
    sensitivityReport($data, $fit, $fitLines);
    modelReport($data, $fit, $course, $age, $fitLines);
    $reproduction = [];
    $rt = reproductionReport($data, $fit, $course, $reproduction);
    ageReport($data, $fit, $age, $rt, $reproduction);
    $scenarios = scenarioReport($data, $fit, $course, $age, $standardErrors, $reproduction);
    writeOutputs(['fit.txt' => $fitLines, 'trajectories.csv' => trajectoryLines($data, $course), 'scenarios.csv' => $scenarios,
        'reproduction.txt' => $reproduction, 'curve_plot.txt' => curvePlot($data->cases, $course->reported)]);
}

main();
