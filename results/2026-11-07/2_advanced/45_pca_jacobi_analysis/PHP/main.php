<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/matrix.php';
require_once __DIR__ . '/eigen.php';
require_once __DIR__ . '/pca.php';
require_once __DIR__ . '/plot.php';

function realNumber(float $value, int $digits = 4): string
{
    $text = number_format($value, $digits, '.', '');
    return $text === ('-0.' . str_repeat('0', $digits)) ? substr($text, 1) : $text;
}

function realList(array $values): string
{
    return implode(' ', array_map(fn($value) => realNumber($value), $values));
}

function sumValues(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) $total += $value;
    return $total;
}

function componentNames(string $prefix, int $count): array
{
    $names = [];
    for ($i = 1; $i <= $count; $i++) $names[] = $prefix . $i;
    return $names;
}

function sections(array $parts): array
{
    $lines = [];
    foreach ($parts as $index => $part) {
        if ($index > 0) $lines[] = '';
        foreach ($part as $line) $lines[] = $line;
    }
    return $lines;
}

function topItems(array $items, callable $measure, int $count): array
{
    $entries = [];
    foreach ($items as $index => $item) $entries[] = ['item' => $item, 'index' => $index, 'value' => $measure($item)];
    usort($entries, fn($a, $b) => ($b['value'] <=> $a['value']) ?: ($a['index'] <=> $b['index']));
    return array_map(fn($entry) => $entry['item'], array_slice($entries, 0, $count));
}

function maximumIndex(array $values): int
{
    $index = 0;
    for ($i = 1; $i < count($values); $i++) if ($values[$i] > $values[$index]) $index = $i;
    return $index;
}

function summarize(array $data): array
{
    $summary = [];
    foreach ($data['names'] as $feature => $name) {
        $observed = [];
        foreach ($data['rows'] as $row) if ($row['values'][$feature] !== null) $observed[] = $row['values'][$feature];
        $mean = sumValues($observed) / count($observed);
        $square = 0.0;
        foreach ($observed as $value) $square += ($value - $mean) * ($value - $mean);
        $summary[] = ['name' => $name, 'observed' => count($observed), 'missing' => count($data['rows']) - count($observed),
            'mean' => $mean, 'deviation' => sqrt($square / (count($observed) - 1)), 'minimum' => min($observed), 'maximum' => max($observed)];
    }
    return $summary;
}

function analysisData(array $data, array $summary, string $missing, string $scaling): array
{
    $rows = [];
    foreach ($data['rows'] as $row) {
        if ($missing === 'listwise' && in_array(null, $row['values'], true)) continue;
        if ($missing === 'mean') {
            foreach ($row['values'] as $j => $value) if ($value === null) $row['values'][$j] = $summary[$j]['mean'];
        }
        $rows[] = $row;
    }
    $prepared = prepareData(array_map(fn($row) => $row['values'], $rows), $scaling);
    return ['rows' => $rows, 'prepared' => $prepared, 'eigen' => jacobi($prepared['matrix'])];
}

function adequacy(array $correlation, int $count): array
{
    $dimension = count($correlation);
    $result = inverseDeterminant($correlation);
    $inverse = $result['inverse'];
    $correlations = [];
    $partials = [];
    $msa = [];
    for ($j = 0; $j < $dimension; $j++) {
        $squared = 0.0;
        $partialSquared = 0.0;
        for ($k = 0; $k < $dimension; $k++) {
            if ($j === $k) continue;
            $partial = -$inverse[$j][$k] / sqrt($inverse[$j][$j] * $inverse[$k][$k]);
            $squared += $correlation[$j][$k] * $correlation[$j][$k];
            $partialSquared += $partial * $partial;
        }
        $correlations[] = $squared;
        $partials[] = $partialSquared;
        $msa[] = $squared / ($squared + $partialSquared);
    }
    $numerator = sumValues($correlations);
    $determinant = $result['determinant'];
    return ['msa' => $msa, 'kmo' => $numerator / ($numerator + sumValues($partials)), 'determinant' => $determinant,
        'bartlett' => -($count - 1 - (2 * $dimension + 5) / 6) * log($determinant),
        'degrees' => intdiv($dimension * ($dimension - 1), 2)];
}

function parallelAnalysis(int $count, int $dimension, array $settings): array
{
    $state = $settings['seed'];
    $totals = array_fill(0, $dimension, 0.0);
    for ($iteration = 0; $iteration < $settings['parallel']; $iteration++) {
        $rows = matZeros($count, $dimension);
        for ($i = 0; $i < $count; $i++) {
            for ($j = 0; $j < $dimension; $j++) {
                $state = (48271 * $state) % 2147483647;
                $rows[$i][$j] = $state / 2147483647;
            }
        }
        $values = jacobi(prepareData($rows, 'correlation')['correlation'])['values'];
        $total = sumValues($values);
        for ($k = 0; $k < $dimension; $k++) $totals[$k] += $values[$k] / $total;
    }
    return array_map(fn($total) => $total / $settings['parallel'], $totals);
}

function retention(array $values, int $count, array $parallel, array $settings): array
{
    $dimension = count($values);
    $total = sumValues($values);
    $average = $total / $dimension;
    $ratios = [];
    $cumulative = [];
    $broken = [];
    $errors = [];
    $separated = [];
    $accumulated = 0.0;
    foreach ($values as $index => $value) {
        $ratios[] = $value / $total;
        $accumulated += $ratios[$index];
        $cumulative[] = $accumulated;
        $stick = 0.0;
        for ($i = $index + 1; $i <= $dimension; $i++) $stick += 1 / $i;
        $broken[] = $stick / $dimension;
        $errors[] = $value * sqrt(2 / $count);
    }
    foreach ($values as $index => $value) {
        $separated[] = ($index === 0 || abs($value - $values[$index - 1]) > $errors[$index]) &&
            ($index === $dimension - 1 || abs($value - $values[$index + 1]) > $errors[$index]);
    }
    $kaiser = 0;
    foreach ($values as $value) if ($value > $average) $kaiser++;
    $brokenCount = $dimension;
    $parallelCount = $dimension;
    $cumulativeCount = $dimension;
    $cumulativeFound = false;
    foreach ($ratios as $index => $ratio) {
        if ($brokenCount === $dimension && $ratio <= $broken[$index]) $brokenCount = $index;
        if ($parallelCount === $dimension && $ratio <= $parallel[$index]) $parallelCount = $index;
        if (!$cumulativeFound && $cumulative[$index] >= $settings['target']) {
            $cumulativeCount = $index + 1;
            $cumulativeFound = true;
        }
    }
    $criteria = ['kaiser' => $kaiser, 'broken_stick' => $brokenCount, 'parallel' => $parallelCount, 'cumulative' => $cumulativeCount];
    $selected = is_numeric($settings['components']) ? (int)$settings['components'] : $criteria[$settings['components']];
    return compact('total', 'average', 'ratios', 'cumulative', 'broken', 'parallel', 'errors', 'separated', 'criteria') +
        ['retained' => max(1, $selected)];
}

function varimaxCriterion(array $values): float
{
    $variables = count($values);
    $total = 0.0;
    for ($k = 0; $k < count($values[0]); $k++) {
        $fourth = 0.0;
        $second = 0.0;
        foreach ($values as $row) {
            $value = $row[$k];
            $fourth += ($value * $value) * ($value * $value);
            $second += $value * $value;
        }
        $total += $fourth / $variables - ($second / $variables) * ($second / $variables);
    }
    return $total;
}

function rotateVarimax(array &$values, int $first, int $second): void
{
    $sa = $sb = $sc = $sd = 0.0;
    foreach ($values as $row) {
        $phi = $row[$first] * $row[$first] - $row[$second] * $row[$second];
        $psi = 2 * $row[$first] * $row[$second];
        $sa += $phi;
        $sb += $psi;
        $sc += $phi * $phi - $psi * $psi;
        $sd += 2 * $phi * $psi;
    }
    $numerator = $sd - 2 * $sa * $sb / count($values);
    $denominator = $sc - ($sa * $sa - $sb * $sb) / count($values);
    $omega = sqrt($numerator * $numerator + $denominator * $denominator);
    if ($omega == 0.0) return;
    $cosine4 = $denominator / $omega;
    $sine4 = $numerator / $omega;
    $cosine2 = sqrt((1 + $cosine4) / 2);
    $sine2 = $cosine2 == 0.0 ? 1 : $sine4 / (2 * $cosine2);
    $cosine1 = sqrt((1 + $cosine2) / 2);
    $sine1 = $sine2 / (2 * $cosine1);
    foreach ($values as &$row) {
        $x = $row[$first];
        $y = $row[$second];
        $row[$first] = $cosine1 * $x + $sine1 * $y;
        $row[$second] = -$sine1 * $x + $cosine1 * $y;
    }
    unset($row);
}

function varimax(array $loadings, int $retained, int $cycles): array
{
    $eta = [];
    $normalized = [];
    foreach ($loadings as $row) {
        $square = 0.0;
        for ($k = 0; $k < $retained; $k++) $square += $row[$k] * $row[$k];
        $scale = sqrt($square);
        $eta[] = $scale;
        $normalized[] = array_map(fn($value) => $value / $scale, array_slice($row, 0, $retained));
    }
    $criteria = [varimaxCriterion($normalized)];
    for ($cycle = 0; $cycle < $cycles; $cycle++) {
        for ($a = 0; $a < $retained - 1; $a++) {
            for ($b = $a + 1; $b < $retained; $b++) rotateVarimax($normalized, $a, $b);
        }
        $criteria[] = varimaxCriterion($normalized);
    }
    $columns = [];
    for ($k = 0; $k < $retained; $k++) {
        $vector = [];
        foreach ($normalized as $j => $row) $vector[] = $row[$k] * $eta[$j];
        $vector = vecOrient($vector);
        $columns[] = ['index' => $k, 'vector' => $vector, 'square' => vecDot($vector, $vector)];
    }
    usort($columns, fn($a, $b) => ($b['square'] <=> $a['square']) ?: ($a['index'] <=> $b['index']));
    foreach ($columns as &$column) {
        $largest = -1.0;
        $closest = 0;
        for ($k = 0; $k < $retained; $k++) {
            $original = matColumn($loadings, $k);
            $congruence = abs(vecDot($column['vector'], $original) /
                sqrt(vecDot($column['vector'], $column['vector']) * vecDot($original, $original)));
            if ($congruence > $largest) {
                $largest = $congruence;
                $closest = $k;
            }
        }
        $column['closest'] = $closest;
        $column['congruence'] = $largest;
    }
    unset($column);
    return compact('criteria', 'columns');
}

function diagnostics(array $row, array $standardized, array $result, int $retained, array $settings, bool $includeQuality): array
{
    $scores = pcaScores($standardized, $result['vectors']);
    $residuals = pcaResiduals($standardized, $scores, $result['vectors'], $retained);
    $t2 = pcaTSquared($scores, $result['values'], $retained);
    $spe = vecDot($residuals, $residuals);
    $flag = ($t2 > $settings['t2Limit'] ? 'T' : '') . ($spe > $settings['speLimit'] ? 'Q' : '');
    $item = compact('row', 'standardized', 'scores', 'residuals', 't2', 'spe') + ['flag' => $flag === '' ? '-' : $flag];
    if ($includeQuality) {
        $explained = 0.0;
        for ($k = 0; $k < $retained; $k++) $explained += $scores[$k] * $scores[$k];
        $item['quality'] = $explained / vecDot($standardized, $standardized);
        $item['t2Contributions'] = [];
        foreach ($standardized as $j => $value) {
            $weighted = 0.0;
            for ($k = 0; $k < $retained; $k++) $weighted += ($scores[$k] / $result['values'][$k]) * $result['vectors'][$k][$j];
            $item['t2Contributions'][] = $value * $weighted;
        }
        $item['speContributions'] = array_map(fn($value) => $value * $value, $residuals);
    }
    return $item;
}

function supplementaryRows(array $data, array $main, int $retained, array $training): array
{
    $result = [];
    foreach ($data['supplementary'] as $row) {
        $standardized = standardize($row['values'], $main['prepared']['means'], $main['prepared']['scales']);
        $item = diagnostics($row, $standardized, $main['eigen'], $retained, $data['settings'], false);
        $nearest = 0;
        $distance = null;
        foreach ($training as $index => $other) {
            $value = 0.0;
            for ($k = 0; $k < $retained; $k++) {
                $difference = $item['scores'][$k] - $other['scores'][$k];
                $value += $difference * $difference;
            }
            if ($distance === null || $value < $distance) {
                $distance = $value;
                $nearest = $index;
            }
        }
        $item['nearest'] = $training[$nearest]['row']['id'];
        $item['distance'] = sqrt($distance);
        $result[] = $item;
    }
    return $result;
}

function scoreSummary(array $data, array $main, array $training, int $retained): array
{
    $lines = ['scores', 'component sd min min_id max max_id contributors'];
    for ($k = 0; $k < $retained; $k++) {
        $squared = 0.0;
        $minimum = $maximum = $training[0];
        $contributions = [];
        foreach ($training as $item) {
            $score = $item['scores'][$k];
            $squared += $score * $score;
            if ($score < $minimum['scores'][$k]) $minimum = $item;
            if ($score > $maximum['scores'][$k]) $maximum = $item;
            $contributions[] = ['id' => $item['row']['id'],
                'value' => $score * $score / ((count($training) - 1) * $main['eigen']['values'][$k])];
        }
        $leaders = topItems($contributions, fn($item) => $item['value'], $data['settings']['top']);
        $pairs = array_map(fn($item) => $item['id'] . ':' . realNumber($item['value']), $leaders);
        $lines[] = implode(' ', array_merge(['pc' . ($k + 1), realNumber(sqrt($squared / (count($training) - 1))),
            realNumber($minimum['scores'][$k]), $minimum['row']['id'], realNumber($maximum['scores'][$k]), $maximum['row']['id']], $pairs));
    }
    return $lines;
}

function sensitivityReport(array $data, array $summary, array $main, int $retained): array
{
    $lines = ['sensitivity', 'missing scaling rows sweeps eigenvalues cumulative congruence'];
    foreach (['listwise', 'mean'] as $missing) {
        foreach (['covariance', 'correlation'] as $scaling) {
            $other = analysisData($data, $summary, $missing, $scaling);
            $total = sumValues($other['eigen']['values']);
            $cumulative = 0.0;
            $congruence = [];
            for ($k = 0; $k < $retained; $k++) {
                $cumulative += $other['eigen']['values'][$k] / $total;
                $congruence[] = abs(vecDot($other['eigen']['vectors'][$k], $main['eigen']['vectors'][$k]));
            }
            $lines[] = implode(' ', [$missing, $scaling, count($other['rows']), $other['eigen']['sweeps'],
                realList(array_slice($other['eigen']['values'], 0, $retained)), realNumber($cumulative), realList($congruence)]);
        }
    }
    return $lines;
}

function eigenReport(array $data, array $summary, array $main, array $measures, array $retention,
    array $power, array $rotation, array $training): array
{
    $settings = $data['settings'];
    $dimension = count($data['names']);
    $incomplete = array_values(array_filter($data['rows'], fn($row) => in_array(null, $row['values'], true)));
    $incompleteIds = $incomplete ? implode(' ', array_map(fn($row) => $row['id'], $incomplete)) : '-';
    $parts = [['pca rows ' . count($data['rows']) . ' used ' . count($main['rows']) . ' variables ' . $dimension .
        ' missing ' . $settings['missing'] . ' scaling ' . $settings['scaling'], 'incomplete ' . count($incomplete) . ' ' . $incompleteIds]];
    $variables = ['variable observed missing mean sd min max msa'];
    foreach ($summary as $j => $item) {
        $variables[] = implode(' ', [$item['name'], $item['observed'], $item['missing'], realNumber($item['mean']),
            realNumber($item['deviation']), realNumber($item['minimum']), realNumber($item['maximum']), realNumber($measures['msa'][$j])]);
    }
    $variables[] = implode(' ', ['adequacy kmo', realNumber($measures['kmo']), 'determinant', realNumber($measures['determinant'], 6),
        'bartlett', realNumber($measures['bartlett']), 'df', $measures['degrees']]);
    $parts[] = $variables;
    $correlations = [];
    for ($j = 0; $j < $dimension; $j++) {
        for ($k = $j + 1; $k < $dimension; $k++) {
            $correlations[] = ['first' => $j, 'second' => $k, 'value' => $main['prepared']['correlation'][$j][$k]];
        }
    }
    $strongest = topItems($correlations, fn($item) => abs($item['value']), $settings['top']);
    $pairs = array_map(fn($item) => $data['names'][$item['first']] . ':' . $data['names'][$item['second']] . ':' . realNumber($item['value']), $strongest);
    $matrixLines = ['matrix ' . $settings['scaling']];
    foreach ($main['prepared']['matrix'] as $j => $row) $matrixLines[] = $data['names'][$j] . ' ' . realList($row);
    $matrixLines[] = 'strongest ' . implode(' ', $pairs);
    $parts[] = $matrixLines;
    $spectrum = ['jacobi sweeps ' . $main['eigen']['sweeps'], 'eigenvalues total ' . realNumber($retention['total']) .
        ' average ' . realNumber($retention['average']), 'k eigenvalue ratio cumulative broken_stick parallel se separated'];
    foreach ($main['eigen']['values'] as $index => $value) {
        $spectrum[] = implode(' ', [$index + 1, realNumber($value), realNumber($retention['ratios'][$index]),
            realNumber($retention['cumulative'][$index]), realNumber($retention['broken'][$index]), realNumber($retention['parallel'][$index]),
            realNumber($retention['errors'][$index]), $retention['separated'][$index] ? 'yes' : 'no']);
    }
    $criteria = $retention['criteria'];
    $spectrum[] = 'retention kaiser ' . $criteria['kaiser'] . ' broken_stick ' . $criteria['broken_stick'] .
        ' parallel ' . $criteria['parallel'] . ' cumulative ' . $criteria['cumulative'] . ' target ' . realNumber($settings['target']);
    $spectrum[] = 'components ' . $retention['retained'] . ' rule ' . $settings['components'];
    $parts[] = $spectrum;
    $vectors = ['eigenvectors', 'variable ' . implode(' ', componentNames('pc', $dimension))];
    foreach ($data['names'] as $j => $name) $vectors[] = $name . ' ' . realList(array_map(fn($vector) => $vector[$j], $main['eigen']['vectors']));
    $parts[] = $vectors;
    $crosscheck = ['power_iteration iterations 1000', 'k jacobi power agree_at match'];
    $matches = 0;
    foreach ($power as $k => $item) {
        if ($item['match']) $matches++;
        $crosscheck[] = implode(' ', [$k + 1, realNumber($main['eigen']['values'][$k]), realNumber($item['value']),
            $item['agreement'] ?? '-', $item['match'] ? 'yes' : 'no']);
    }
    $crosscheck[] = 'cross_check ' . $matches . '/' . $dimension;
    $parts[] = $crosscheck;
    $parts[] = scoreSummary($data, $main, $training, $retention['retained']);
    $rotated = ['varimax components ' . $retention['retained'] . ' cycles ' . $settings['cycles']];
    foreach ($rotation['criteria'] as $cycle => $value) $rotated[] = 'cycle ' . $cycle . ' criterion ' . realNumber($value, 6);
    foreach ($rotation['columns'] as $k => $column) {
        $rotated[] = 'rc' . ($k + 1) . ' ss ' . realNumber($column['square']) . ' ratio ' . realNumber($column['square'] / $retention['total']) .
            ' closest pc' . ($column['closest'] + 1) . ' congruence ' . realNumber($column['congruence']);
    }
    $parts[] = $rotated;
    $parts[] = sensitivityReport($data, $summary, $main, $retention['retained']);
    return sections($parts);
}

function loadingReport(array $data, array $main, array $loadings, int $retained, array $rotation): array
{
    $lines = [implode(',', array_merge(['variable'], componentNames('pc', $retained), ['communality'], componentNames('rc', $retained)))];
    foreach ($data['names'] as $j => $name) {
        $square = 0.0;
        for ($k = 0; $k < $retained; $k++) $square += $loadings[$j][$k] * $loadings[$j][$k];
        $values = array_slice($loadings[$j], 0, $retained);
        $values[] = $square / $main['prepared']['matrix'][$j][$j];
        foreach ($rotation['columns'] as $column) $values[] = $column['vector'][$j];
        $lines[] = implode(',', array_merge([$name], array_map(fn($value) => realNumber($value), $values)));
    }
    return $lines;
}

function scoresReport(array $training, array $supplementary, int $retained): array
{
    $lines = [implode(',', array_merge(['id', 'set'], componentNames('pc', $retained)))];
    foreach (['data' => $training, 'supplementary' => $supplementary] as $name => $items) {
        foreach ($items as $item) {
            $values = array_map(fn($value) => realNumber($value), array_slice($item['scores'], 0, $retained));
            $lines[] = implode(',', array_merge([$item['row']['id'], $name], $values));
        }
    }
    return $lines;
}

function outlierReport(array $data, array $main, array $training, array $supplementary, int $retained): array
{
    $lines = ['diagnostics components ' . $retained . ' t2_limit ' . realNumber($data['settings']['t2Limit']) .
        ' spe_limit ' . realNumber($data['settings']['speLimit']), 'id t2 spe quality flag'];
    $tCount = $qCount = $both = $any = 0;
    foreach ($training as $item) {
        $lines[] = implode(' ', [$item['row']['id'], realNumber($item['t2']), realNumber($item['spe']), realNumber($item['quality']), $item['flag']]);
        if (str_contains($item['flag'], 'T')) $tCount++;
        if (str_contains($item['flag'], 'Q')) $qCount++;
        if ($item['flag'] === 'TQ') $both++;
        if ($item['flag'] !== '-') $any++;
    }
    $lines[] = 'flagged t2 ' . $tCount . ' spe ' . $qCount . ' both ' . $both . ' any ' . $any;
    $parts = [$lines];
    foreach (['t2', 'spe'] as $statistic) {
        $header = ['top ' . $statistic, 'rank id ' . $statistic . ' variable contribution'];
        $top = topItems($training, fn($item) => $item[$statistic], $data['settings']['top']);
        foreach ($top as $rank => $item) {
            $contributions = $statistic === 't2' ? $item['t2Contributions'] : $item['speContributions'];
            $feature = maximumIndex($contributions);
            $header[] = implode(' ', [$rank + 1, $item['row']['id'], realNumber($item[$statistic]),
                $data['names'][$feature], realNumber($contributions[$feature])]);
        }
        $parts[] = $header;
    }
    $reconstruction = ['reconstruction', 'k mean_spe max_spe max_id'];
    for ($components = 1; $components < count($data['names']); $components++) {
        $total = 0.0;
        $maximum = -1.0;
        $id = '';
        foreach ($training as $item) {
            $residuals = pcaResiduals($item['standardized'], $item['scores'], $main['eigen']['vectors'], $components);
            $spe = vecDot($residuals, $residuals);
            $total += $spe;
            if ($spe > $maximum) {
                $maximum = $spe;
                $id = $item['row']['id'];
            }
        }
        $reconstruction[] = implode(' ', [$components, realNumber($total / count($training)), realNumber($maximum), $id]);
    }
    $parts[] = $reconstruction;
    $supplementaryLines = ['supplementary', 'id ' . implode(' ', componentNames('pc', $retained)) . ' t2 spe flag nearest distance'];
    foreach ($supplementary as $item) {
        $supplementaryLines[] = implode(' ', [$item['row']['id'], realList(array_slice($item['scores'], 0, $retained)),
            realNumber($item['t2']), realNumber($item['spe']), $item['flag'], $item['nearest'], realNumber($item['distance'])]);
    }
    $parts[] = $supplementaryLines;
    return sections($parts);
}

function drawAxes(array &$grid, array $position): void
{
    for ($column = 0; $column < count($grid[0]); $column++) $grid[$position['row']][$column] = '-';
    for ($row = 0; $row < count($grid); $row++) $grid[$row][$position['column']] = '|';
    $grid[$position['row']][$position['column']] = '+';
}

function drawDensity(array &$grid, array $positions): void
{
    $counts = matZeros(count($grid), count($grid[0]));
    foreach ($positions as $position) $counts[$position['row']][$position['column']]++;
    foreach ($counts as $row => $cells) {
        foreach ($cells as $column => $count) {
            if ($count > 0) $grid[$row][$column] = $count == 1 ? '.' : ($count <= 3 ? 'o' : '@');
        }
    }
}

function biplotReport(array $data, array $training, array $supplementary, array $loadings): array
{
    $width = $data['settings']['biplotWidth'];
    $height = $data['settings']['biplotHeight'];
    $maximumX = $maximumY = 0.0;
    foreach (array_merge($training, $supplementary) as $item) {
        $maximumX = max($maximumX, abs($item['scores'][0]));
        $maximumY = max($maximumY, abs($item['scores'][1]));
    }
    $loadingX = $loadingY = 0.0;
    foreach ($loadings as $row) {
        $loadingX = max($loadingX, abs($row[0]));
        $loadingY = max($loadingY, abs($row[1]));
    }
    $scale = 0.9 * min($maximumX / $loadingX, $maximumY / $loadingY);
    $position = fn($x, $y) => biplotCell($x, $y, $maximumX, $maximumY, $width, $height);
    $origin = $position(0.0, 0.0);
    $grid = plotGrid($width, $height);
    drawAxes($grid, $origin);
    $tips = [];
    foreach ($loadings as $row) {
        $tip = $position($scale * $row[0], $scale * $row[1]);
        $tips[] = $tip;
        foreach (plotShaft($origin, $tip) as $point) $grid[$point['row']][$point['column']] = $point['character'];
    }
    $points = [];
    foreach ($training as $item) $points[] = $position($item['scores'][0], $item['scores'][1]);
    drawDensity($grid, $points);
    foreach ($training as $index => $item) {
        if ($item['flag'] !== '-') $grid[$points[$index]['row']][$points[$index]['column']] = 'X';
    }
    foreach ($supplementary as $item) {
        $point = $position($item['scores'][0], $item['scores'][1]);
        $grid[$point['row']][$point['column']] = '*';
    }
    foreach ($tips as $index => $tip) $grid[$tip['row']][$tip['column']] = chr(65 + $index);
    $lines = ['biplot pc1 pc2 width ' . $width . ' height ' . $height,
        'x ' . realNumber(-$maximumX) . ' ' . realNumber($maximumX) . ' y ' . realNumber(-$maximumY) . ' ' . realNumber($maximumY) .
        ' arrow_scale ' . realNumber($scale)];
    foreach (plotFrame($grid) as $line) $lines[] = $line;
    foreach ($data['names'] as $j => $name) {
        $lines[] = chr(65 + $j) . ' ' . $name . ' ' . realNumber($loadings[$j][0]) . ' ' . realNumber($loadings[$j][1]);
    }
    return $lines;
}

function circleReport(array $data, array $main, array $loadings): array
{
    $radius = $data['settings']['radius'];
    $centerRow = intdiv($radius, 2) + 1;
    $centerColumn = $radius + 1;
    $grid = plotGrid(2 * $radius + 3, $radius + 3);
    drawAxes($grid, ['row' => $centerRow, 'column' => $centerColumn]);
    $inside = fn($row, $column) => ($column - $centerColumn) * ($column - $centerColumn) +
        (2 * ($row - $centerRow)) * (2 * ($row - $centerRow)) <= $radius * $radius;
    for ($row = 0; $row < count($grid); $row++) {
        for ($column = 0; $column < count($grid[0]); $column++) {
            if ($inside($row, $column) && (!$inside($row - 1, $column) || !$inside($row + 1, $column) ||
                !$inside($row, $column - 1) || !$inside($row, $column + 1))) $grid[$row][$column] = '.';
        }
    }
    $correlations = [];
    foreach ($loadings as $j => $loading) {
        $scale = sqrt($main['prepared']['matrix'][$j][$j]);
        $point = [$loading[0] / $scale, $loading[1] / $scale];
        $correlations[] = $point;
        $row = $centerRow - (int)floor($point[1] * ($radius / 2) + 0.5);
        $column = $centerColumn + (int)floor($point[0] * $radius + 0.5);
        $grid[$row][$column] = chr(65 + $j);
    }
    $lines = ['circle radius ' . $radius];
    foreach (plotFrame($grid) as $line) $lines[] = $line;
    foreach ($correlations as $j => $point) {
        $lines[] = chr(65 + $j) . ' ' . $data['names'][$j] . ' ' . realNumber($point[0]) . ' ' . realNumber($point[1]) .
            ' ' . realNumber($point[0] * $point[0] + $point[1] * $point[1]);
    }
    return $lines;
}

function diagnosticReport(array $data, array $training, array $supplementary): array
{
    $settings = $data['settings'];
    $width = $settings['diagnosticWidth'];
    $height = $settings['diagnosticHeight'];
    $maximumX = 2 * $settings['t2Limit'];
    $maximumY = 2 * $settings['speLimit'];
    $position = fn($t2, $spe) => diagnosticCell($t2, $spe, $maximumX, $maximumY, $width, $height);
    $grid = plotGrid($width, $height);
    drawAxes($grid, $position($settings['t2Limit'], $settings['speLimit']));
    $points = [];
    foreach ($training as $item) $points[] = $position($item['t2'], $item['spe']);
    drawDensity($grid, $points);
    foreach ($supplementary as $item) {
        $point = $position($item['t2'], $item['spe']);
        $grid[$point['row']][$point['column']] = '*';
    }
    return array_merge(['diagnostic width ' . $width . ' height ' . $height . ' t2_max ' . realNumber($maximumX) .
        ' spe_max ' . realNumber($maximumY)], plotFrame($grid));
}

function plotsReport(array $data, array $main, array $retention, array $training, array $supplementary, array $loadings): array
{
    $width = $data['settings']['screeWidth'];
    $largest = $main['eigen']['values'][0];
    $kaiser = (int)floor($retention['average'] / $largest * $width + 0.5);
    $scree = ['scree width ' . $width . ' kaiser_column ' . $kaiser];
    foreach ($main['eigen']['values'] as $k => $value) {
        $bar = (int)floor($value / $largest * $width + 0.5);
        $broken = (int)floor($retention['broken'][$k] * $retention['total'] / $largest * $width + 0.5);
        $scree[] = '|' . screeBar($width, $bar, $broken, $kaiser) . '| pc' . ($k + 1) . ' ' . realNumber($value);
    }
    return sections([$scree, biplotReport($data, $training, $supplementary, $loadings),
        circleReport($data, $main, $loadings), diagnosticReport($data, $training, $supplementary)]);
}

function writeLines(string $filename, array $lines): void
{
    file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
}

function main(): void
{
    $data = readDataset();
    $summary = summarize($data);
    $main = analysisData($data, $summary, $data['settings']['missing'], $data['settings']['scaling']);
    $measures = adequacy($main['prepared']['correlation'], count($main['rows']));
    $parallel = parallelAnalysis(count($main['rows']), count($data['names']), $data['settings']);
    $retention = retention($main['eigen']['values'], count($main['rows']), $parallel, $data['settings']);
    $count = $retention['retained'];
    $loadings = [];
    foreach ($data['names'] as $j => $_) {
        $row = [];
        foreach ($main['eigen']['values'] as $k => $value) $row[] = $main['eigen']['vectors'][$k][$j] * sqrt($value);
        $loadings[] = $row;
    }
    $rotation = varimax($loadings, $count, $data['settings']['cycles']);
    $training = [];
    foreach ($main['rows'] as $index => $row) {
        $training[] = diagnostics($row, $main['prepared']['standardized'][$index], $main['eigen'], $count, $data['settings'], true);
    }
    $supplementary = supplementaryRows($data, $main, $count, $training);
    $power = powerIteration($main['prepared']['matrix'], $main['eigen']);
    $eigenLines = eigenReport($data, $summary, $main, $measures, $retention, $power, $rotation, $training);
    $loadingLines = loadingReport($data, $main, $loadings, $count, $rotation);
    $scoreLines = scoresReport($training, $supplementary, $count);
    $outlierLines = outlierReport($data, $main, $training, $supplementary, $count);
    $plotLines = plotsReport($data, $main, $retention, $training, $supplementary, $loadings);
    if (!is_dir('output')) mkdir('output', 0777, true);
    writeLines('eigen.txt', $eigenLines);
    writeLines('loadings.csv', $loadingLines);
    writeLines('scores.csv', $scoreLines);
    writeLines('outliers.txt', $outlierLines);
    writeLines('plots.txt', $plotLines);
}

main();
