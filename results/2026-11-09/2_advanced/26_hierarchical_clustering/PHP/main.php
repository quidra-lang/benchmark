<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/distances.php';
require_once __DIR__ . '/agglomerative.php';
require_once __DIR__ . '/dendrogram.php';
require_once __DIR__ . '/validation.php';

function formatReal(?float $value): string
{
    if ($value === null) {
        return '-';
    }
    $text = sprintf('%.4f', $value);
    return $text === '-0.0000' ? '0.0000' : $text;
}

function reals(array $values): string
{
    return implode(' ', array_map('formatReal', $values));
}

function words(mixed ...$values): string
{
    return implode(' ', $values);
}

function fourDigit(float $value): float
{
    return (float)formatReal($value);
}

function ariValue(array $ari): float
{
    return $ari[0] / $ari[1];
}

function ariText(array $ari): string
{
    return $ari[0] . '/' . $ari[1] . ' ' . formatReal(ariValue($ari));
}

function ariGreater(array $first, array $second): bool
{
    return $first[0] * $second[1] > $second[0] * $first[1];
}

function pairValues(array $matrix): array
{
    $values = [];
    for ($i = 0; $i < count($matrix); ++$i) {
        for ($j = $i + 1; $j < count($matrix); ++$j) {
            $values[] = $matrix[$i][$j];
        }
    }
    return $values;
}

function histogramBin(float $value, float $maximum): int
{
    return min(9, (int)floor(10 * $value / $maximum));
}

function centroid(array $vectors): array
{
    $center = [];
    for ($f = 0; $f < count($vectors[0]); ++$f) {
        $center[] = sequentialSum(array_column($vectors, $f)) / count($vectors);
    }
    return $center;
}

function clusterMembers(array $partition, int $groups): array
{
    $members = array_fill(0, $groups, []);
    foreach ($partition as $i => $number) {
        $members[$number - 1][] = $i;
    }
    return $members;
}

function majorityClass(array $row): int
{
    $best = 0;
    for ($t = 1; $t < count($row); ++$t) {
        if ($row[$t] > $row[$best]) {
            $best = $t;
        }
    }
    return $best;
}

function joinParts(array $parts): array
{
    $lines = [];
    foreach ($parts as $part) {
        if ($lines !== []) {
            $lines[] = '';
        }
        array_push($lines, ...$part);
    }
    return $lines;
}

final class Tree
{
    public array $heights;
    public array $children;
    public array $order;
    public array $members;
    public array $depths;
    public array $subtreeHeights = [];

    public function __construct(public array $merges, public int $count)
    {
        $this->heights = array_map(fn($merge) => $merge->height, $merges);
        $this->children = orderedChildren($merges, $count);
        $this->order = leafOrder($this->children, $count);
        $this->members = array_map(fn($u) => [$u], range(0, $count - 1));
        $this->depths = array_fill(0, $count, 0);
        foreach ($merges as $merge) {
            $this->members[] = array_merge($this->members[$merge->a], $this->members[$merge->b]);
            $this->depths[] = 1 + max($this->depths[$merge->a], $this->depths[$merge->b]);
            $this->subtreeHeights[] = max($merge->height, $this->subtreeHeight($merge->a), $this->subtreeHeight($merge->b));
        }
    }

    public function heightOf(int $node): float
    {
        return $node < $this->count ? 0.0 : $this->heights[$node - $this->count];
    }

    public function subtreeHeight(int $node): float
    {
        return $node < $this->count ? 0.0 : $this->subtreeHeights[$node - $this->count];
    }

    public function partition(array $selected): array
    {
        $owner = range(0, $this->count - 1);
        foreach ($selected as $step => $chosen) {
            if ($chosen) {
                $node = $this->count + $step;
                foreach ($this->members[$node] as $u) {
                    $owner[$u] = $node;
                }
            }
        }
        $numbers = array_fill(0, 2 * $this->count - 1, 0);
        $groups = 0;
        foreach ($this->order as $u) {
            if ($numbers[$owner[$u]] === 0) {
                $numbers[$owner[$u]] = ++$groups;
            }
        }
        return array_map(fn($node) => $numbers[$node], $owner);
    }

    public function cutHeight(float $height): array
    {
        return $this->partition(array_map(fn($value) => $value <= $height, $this->subtreeHeights));
    }

    public function cutInto(int $k): array
    {
        $selected = [];
        foreach ($this->merges as $step => $merge) {
            $selected[] = $step < $this->count - $k;
        }
        return $this->partition($selected);
    }

    public function cophenetic(): array
    {
        $matrix = array_fill(0, $this->count, array_fill(0, $this->count, 0.0));
        foreach ($this->merges as $merge) {
            foreach ($this->members[$merge->a] as $i) {
                foreach ($this->members[$merge->b] as $j) {
                    $matrix[$i][$j] = $matrix[$j][$i] = $merge->height;
                }
            }
        }
        return $matrix;
    }

    public function joiningHeights(): array
    {
        $heights = array_fill(0, $this->count, 0.0);
        foreach ($this->merges as $merge) {
            foreach ([$merge->a, $merge->b] as $child) {
                if ($child < $this->count) {
                    $heights[$child] = $merge->height;
                }
            }
        }
        return $heights;
    }

    public function heightSequence(int $step, int $depth): array
    {
        if ($depth === 0) {
            return [];
        }
        $merge = $this->merges[$step];
        $sequence = [$merge->height];
        foreach ([$merge->a, $merge->b] as $child) {
            if ($child >= $this->count) {
                array_push($sequence, ...$this->heightSequence($child - $this->count, $depth - 1));
            }
        }
        return $sequence;
    }

    public function newick(int $node, array $idents): string
    {
        if ($node < $this->count) {
            return $idents[$node];
        }
        $height = $this->heightOf($node);
        $branches = [];
        foreach ($this->children[$node - $this->count] as $child) {
            $branches[] = $this->newick($child, $idents) . ':' . formatReal($height - $this->heightOf($child));
        }
        return '(' . implode(',', $branches) . ')';
    }
}

final class Evaluation
{
    public function __construct(public array $partition, public array $sizes, public ?float $silhouette, public ?float $dunn, public float $wss, public ?float $ch, public array $ari) {}

    public function text(): string
    {
        return words('sizes', implode(' ', $this->sizes), 'silhouette', formatReal($this->silhouette), 'dunn', formatReal($this->dunn), 'wss', formatReal($this->wss), 'ch', formatReal($this->ch), 'ari', ariText($this->ari));
    }
}

final class LinkageResult
{
    public function __construct(public string $method, public Tree $tree, public array $cophenetic, public float $correlation, public array $heightCuts, public array $countCuts, public array $labelPartition) {}
}

final class Study
{
    public int $count;
    public array $idents;
    public array $labels;
    public array $classes;
    public array $targets;
    public array $raw;
    public array $means;
    public array $deviations;
    public array $vectors;
    public array $distances;
    public array $distancePairs;
    public float $distanceMax;
    public array $neighbors;
    public array $results;
    public LinkageResult $chosen;
    public int $kappa;
    public Evaluation $selectedCut;
    public array $selected;
    public array $members;
    public array $silhouettes;
    public array $table;
    public array $majority;

    public function __construct(public array $names, array $observations, public Settings $settings)
    {
        $this->count = count($observations);
        $this->idents = array_column($observations, 'ident');
        $this->labels = array_column($observations, 'label');
        $this->classes = array_values(array_unique($this->labels, SORT_STRING));
        usort($this->classes, 'strcmp');
        $this->targets = array_map(fn($label) => array_search($label, $this->classes, true), $this->labels);
        $this->raw = array_column($observations, 'values');
        [$this->means, $this->deviations] = featureStatistics($this->raw);
        $this->vectors = $settings->standardize === 'yes' ? standardize($this->raw, $this->means, $this->deviations) : $this->raw;
        $this->distances = distanceMatrix($this->vectors, $settings->distance);
        $this->distancePairs = pairValues($this->distances);
        $this->distanceMax = max($this->distancePairs);
        $this->neighbors = array_map(fn($i) => $this->nearestNeighbor($i), range(0, $this->count - 1));
        $this->results = array_map(fn($method) => $this->analyse($method), $settings->linkages);
        $this->chosen = $this->results[0];
        $position = 0;
        foreach ($this->results as $result) {
            foreach ($result->countCuts as $index => $cut) {
                if (ariGreater($cut->ari, $this->chosen->countCuts[$position]->ari)) {
                    $this->chosen = $result;
                    $position = $index;
                }
            }
        }
        $this->kappa = $settings->cutCounts[$position];
        $this->selectedCut = $this->chosen->countCuts[$position];
        $this->selected = $this->selectedCut->partition;
        $this->members = clusterMembers($this->selected, $this->kappa);
        $this->silhouettes = silhouetteValues($this->selected, $this->kappa, $this->distances);
        $this->table = $this->classTable($this->selected);
        $this->majority = array_map('majorityClass', $this->table);
    }

    public function nearestNeighbor(int $i): int
    {
        $best = -1;
        for ($j = 0; $j < $this->count; ++$j) {
            if ($j !== $i && ($best < 0 || $this->distances[$i][$j] < $this->distances[$i][$best])) {
                $best = $j;
            }
        }
        return $best;
    }

    public function classTable(array $partition): array
    {
        return contingencyTable(array_map(fn($g) => $g - 1, $partition), $this->targets, max($partition), count($this->classes));
    }

    public function labelAri(array $partition): array
    {
        return adjustedRandIndex($this->classTable($partition));
    }

    public function matches(array $partition): int
    {
        return array_sum(array_map('max', $this->classTable($partition)));
    }

    public function partitionAri(array $first, array $second): array
    {
        return adjustedRandIndex(contingencyTable(array_map(fn($g) => $g - 1, $first), array_map(fn($g) => $g - 1, $second), max($first), max($second)));
    }

    public function meanSilhouette(array $partition, array $delta): ?float
    {
        $groups = max($partition);
        return $groups < 2 ? null : sequentialSum(silhouetteValues($partition, $groups, $delta)) / count($partition);
    }

    public function centroids(array $partition): array
    {
        return array_map(fn($group) => centroid(array_map(fn($i) => $this->vectors[$i], $group)), clusterMembers($partition, max($partition)));
    }

    public function within(array $partition): float
    {
        $centers = $this->centroids($partition);
        $total = 0.0;
        foreach ($partition as $i => $g) {
            $total += squaredDistance($this->vectors[$i], $centers[$g - 1]);
        }
        return $total;
    }

    public function evaluate(array $partition): Evaluation
    {
        $groups = max($partition);
        $sizes = array_map('count', clusterMembers($partition, $groups));
        $wss = $this->within($partition);
        $diameter = 0.0;
        $separation = null;
        for ($i = 0; $i < $this->count; ++$i) {
            for ($j = $i + 1; $j < $this->count; ++$j) {
                $value = $this->distances[$i][$j];
                if ($partition[$i] === $partition[$j]) {
                    $diameter = max($diameter, $value);
                } elseif ($separation === null || $value < $separation) {
                    $separation = $value;
                }
            }
        }
        $ch = null;
        if (2 <= $groups && $groups < $this->count) {
            $overall = centroid($this->vectors);
            $bss = 0.0;
            foreach ($this->centroids($partition) as $g => $center) {
                $bss += $sizes[$g] * squaredDistance($center, $overall);
            }
            $ch = ($bss / ($groups - 1)) / ($wss / ($this->count - $groups));
        }
        return new Evaluation($partition, $sizes, $this->meanSilhouette($partition, $this->distances), $groups >= 2 && $diameter > 0 ? $separation / $diameter : null, $wss, $ch, $this->labelAri($partition));
    }

    public function analyse(string $method): LinkageResult
    {
        $tree = new Tree(agglomerate($this->distances, $method), $this->count);
        $cophenetic = pairValues($tree->cophenetic());
        return new LinkageResult($method, $tree, $cophenetic, correlation($this->distancePairs, $cophenetic), array_map(fn($height) => $this->evaluate($tree->cutHeight($height)), $this->settings->cutHeights), array_map(fn($k) => $this->evaluate($tree->cutInto($k)), $this->settings->cutCounts), $tree->cutInto(count($this->classes)));
    }

    public function linkageTable(): array
    {
        $lines = ['method,step,a,b,height,size'];
        foreach ($this->results as $result) {
            foreach ($result->tree->merges as $step => $merge) {
                $lines[] = implode(',', [$result->method, $step + 1, $merge->a, $merge->b, formatReal($merge->height), $merge->size]);
            }
        }
        return $lines;
    }

    public function clustersTable(): array
    {
        $header = ['id', 'label'];
        foreach ($this->results as $result) {
            foreach ($this->settings->cutHeights as $j => $height) {
                $header[] = $result->method . '_h' . ($j + 1);
            }
            foreach ($this->settings->cutCounts as $k) {
                $header[] = $result->method . '_k' . $k;
            }
        }
        $lines = [implode(',', $header)];
        for ($i = 0; $i < $this->count; ++$i) {
            $fields = [$this->idents[$i], $this->labels[$i]];
            foreach ($this->results as $result) {
                foreach (array_merge($result->heightCuts, $result->countCuts) as $cut) {
                    $fields[] = $cut->partition[$i];
                }
            }
            $lines[] = implode(',', $fields);
        }
        return $lines;
    }

    public function dendrogramReport(): array
    {
        $blocks = [];
        $width = $this->settings->width;
        foreach ($this->results as $result) {
            $tree = $result->tree;
            $maximum = max($tree->heights);
            $cuts = array_map(fn($height) => heightColumn($height, $maximum, $width), $this->settings->cutHeights);
            $lines = [words('dendrogram', $result->method, 'height_max', formatReal($maximum), 'width', $width)];
            array_push($lines, ...dendrogramRows($tree, $this->idents, $this->labels, $maximum, $cuts, $width));
            foreach ($this->settings->cutHeights as $j => $height) {
                $lines[] = words('cut', formatReal($height), 'column', $cuts[$j] <= $width ? $cuts[$j] : '-');
            }
            $blocks[] = $lines;
        }
        return joinParts($blocks);
    }

    public function treesReport(): array
    {
        return array_map(fn($result) => $result->method . ' ' . $result->tree->newick(2 * $this->count - 2, $this->idents) . ';', $this->results);
    }

    public function pairText(int $i, int $j): string
    {
        return words(formatReal($this->distances[$i][$j]), $this->idents[$i], $this->idents[$j]);
    }

    public function dataPart(): array
    {
        $n = $this->count;
        $lines = [words('data n', $n, 'features', count($this->names), 'classes', count($this->classes), 'distance', $this->settings->distance, 'standardize', $this->settings->standardize)];
        foreach ($this->names as $f => $name) {
            $lines[] = words('feature', $name, 'mean', formatReal($this->means[$f]), 'sd', formatReal($this->deviations[$f]));
        }
        $smallest = $largest = [0, 1];
        for ($i = 0; $i < $n; ++$i) {
            for ($j = $i + 1; $j < $n; ++$j) {
                if ($this->distances[$i][$j] < $this->distances[$smallest[0]][$smallest[1]]) {
                    $smallest = [$i, $j];
                }
                if ($this->distances[$i][$j] > $this->distances[$largest[0]][$largest[1]]) {
                    $largest = [$i, $j];
                }
            }
        }
        $lines[] = words('distances pairs', count($this->distancePairs), 'min', $this->pairText(...$smallest), 'max', $this->pairText(...$largest), 'mean', formatReal(sequentialSum($this->distancePairs) / count($this->distancePairs)));
        $nearest = 0.0;
        $reciprocal = 0;
        for ($i = 0; $i < $n; ++$i) {
            $nearest += $this->distances[$i][$this->neighbors[$i]];
            if ($i < $this->neighbors[$i] && $this->neighbors[$this->neighbors[$i]] === $i) {
                ++$reciprocal;
            }
        }
        $lines[] = words('nearest_neighbors mean', formatReal($nearest / $n), 'reciprocal_pairs', $reciprocal);
        $lines[] = 'labels ' . $this->evaluate(array_map(fn($t) => $t + 1, $this->targets))->text();
        return $lines;
    }

    public function correlationPart(): array
    {
        $columns = [];
        foreach ($this->names as $f => $name) {
            $columns[] = array_column($this->raw, $f);
        }
        $lines = ['correlation ' . implode(' ', $this->names)];
        foreach ($this->names as $f => $name) {
            $lines[] = $name . ' ' . reals(array_map(fn($column) => correlation($columns[$f], $column), $columns));
        }
        return $lines;
    }

    public function histogramPart(): array
    {
        $counts = array_fill(0, 10, 0);
        foreach ($this->distancePairs as $value) {
            ++$counts[histogramBin($value, $this->distanceMax)];
        }
        $highest = max($counts);
        $lines = ['histogram'];
        foreach ($counts as $b => $count) {
            $line = words(formatReal($b * $this->distanceMax / 10), formatReal(($b + 1) * $this->distanceMax / 10), $count);
            $length = intdiv($count * 50, $highest);
            $lines[] = $line . ($length > 0 ? ' ' . str_repeat('#', $length) : '');
        }
        return $lines;
    }

    public function linkagePart(LinkageResult $result): array
    {
        $tree = $result->tree;
        $settings = $this->settings;
        $n = $this->count;
        $path = 0.0;
        for ($r = 0; $r < $n - 1; ++$r) {
            $path += $this->distances[$tree->order[$r]][$tree->order[$r + 1]];
        }
        $inversions = [];
        for ($step = 1; $step < $n - 1; ++$step) {
            if ($tree->heights[$step] < $tree->heights[$step - 1]) {
                $inversions[] = $step;
            }
        }
        $lines = ['linkage ' . $result->method, words('cophenetic', formatReal($result->correlation), 'leaf_path', formatReal($path)), words('heights min', formatReal(min($tree->heights)), 'max', formatReal(max($tree->heights)), 'inversions', count($inversions))];
        foreach ($inversions as $step) {
            $lines[] = words('inversion step', $step + 1, 'height', formatReal($tree->heights[$step]), 'previous', formatReal($tree->heights[$step - 1]));
        }
        $ordered = $tree->subtreeHeights;
        sort($ordered, SORT_NUMERIC);
        $gaps = [];
        for ($k = 2; $k <= $settings->gapMaxK; ++$k) {
            $gaps[] = $ordered[$n - $k] - $ordered[$n - $k - 1];
        }
        $suggested = 2;
        for ($k = 3; $k <= $settings->gapMaxK; ++$k) {
            if (fourDigit($gaps[$k - 2]) > fourDigit($gaps[$suggested - 2])) {
                $suggested = $k;
            }
        }
        $lines[] = 'gaps ' . reals($gaps);
        $lines[] = 'suggested_k ' . $suggested;
        $joining = $tree->joiningHeights();
        $late = range(0, $n - 1);
        usort($late, fn($a, $b) => ($joining[$b] <=> $joining[$a]) ?: ($a <=> $b));
        $lines[] = 'late_joiners ' . implode(' ', array_map(fn($i) => $this->idents[$i] . ':' . formatReal($joining[$i]), array_slice($late, 0, $settings->listSize)));
        $kinds = [0, 0, 0];
        foreach ($tree->merges as $merge) {
            $leaves = (int)($merge->a < $n) + (int)($merge->b < $n);
            ++$kinds[2 - $leaves];
        }
        $lines[] = words('merges leaf_leaf', $kinds[0], 'leaf_cluster', $kinds[1], 'cluster_cluster', $kinds[2], 'depth', $tree->depths[2 * $n - 2]);
        $matches = $this->matches($result->labelPartition);
        $lines[] = words('label_cut k', count($this->classes), 'purity', $matches . '/' . $n, formatReal($matches / $n));
        $lines[] = 'inconsistency depth ' . $settings->inconsistencyDepthText;
        for ($step = $n - $settings->inconsistencyCount - 1; $step < $n - 1; ++$step) {
            $sequence = $tree->heightSequence($step, $settings->inconsistencyDepth);
            $mean = sequentialSum($sequence) / count($sequence);
            $sd = $coefficient = 0.0;
            if (count($sequence) >= 2) {
                $sd = sqrt(sequentialSum(array_map(fn($value) => ($value - $mean) * ($value - $mean), $sequence)) / (count($sequence) - 1));
                $coefficient = ($tree->heights[$step] - $mean) / $sd;
            }
            $lines[] = words('step', $step + 1, 'height', formatReal($tree->heights[$step]), 'mean', formatReal($mean), 'sd', formatReal($sd), 'count', count($sequence), 'coefficient', formatReal($coefficient));
        }
        foreach ($settings->cutHeights as $j => $height) {
            $lines[] = words('cut height', formatReal($height), 'clusters', count($result->heightCuts[$j]->sizes), $result->heightCuts[$j]->text());
        }
        foreach ($settings->cutCounts as $j => $k) {
            $lines[] = words('cut k', $k, $result->countCuts[$j]->text());
        }
        return $lines;
    }

    public function mstPart(LinkageResult $single): array
    {
        $edges = minimumSpanningTree($this->distances);
        $weights = array_map(fn($edge) => $edge->weight, $edges);
        $total = sequentialSum($weights);
        sort($weights, SORT_NUMERIC);
        $match = true;
        $linked = array_fill(0, $this->count, array_fill(0, $this->count, false));
        foreach ($edges as $i => $edge) {
            if (abs($weights[$i] - $single->tree->heights[$i]) > 0.000000001) {
                $match = false;
            }
            $linked[$edge->parent][$edge->child] = $linked[$edge->child][$edge->parent] = true;
        }
        $nearest = 0;
        foreach ($this->neighbors as $i => $j) {
            if ($linked[$i][$j]) {
                ++$nearest;
            }
        }
        $lines = [words('mst total', formatReal($total), 'heights', $match ? 'match' : 'mismatch', 'nn_edges', $nearest . '/' . $this->count)];
        $numbers = range(0, count($edges) - 1);
        usort($numbers, fn($a, $b) => ($edges[$a]->weight <=> $edges[$b]->weight) ?: ($a <=> $b));
        foreach ($this->settings->cutCounts as $position => $k) {
            $component = range(0, $this->count - 1);
            for ($s = 0; $s < $this->count - $k; ++$s) {
                $edge = $edges[$numbers[$s]];
                $old = $component[$edge->child];
                $new = $component[$edge->parent];
                foreach ($component as $u => $value) {
                    if ($value === $old) {
                        $component[$u] = $new;
                    }
                }
            }
            $agrees = true;
            $partition = $single->countCuts[$position]->partition;
            for ($i = 0; $i < $this->count; ++$i) {
                for ($j = $i + 1; $j < $this->count; ++$j) {
                    if (($component[$i] === $component[$j]) !== ($partition[$i] === $partition[$j])) {
                        $agrees = false;
                    }
                }
            }
            $lines[] = words('mst partition k', $k, $agrees ? 'match' : 'mismatch');
        }
        return $lines;
    }

    public function comparePart(): array
    {
        $method = $this->settings->compareLinkage;
        $labels = count($this->classes);
        $lines = [words('compare linkage', $method, 'k', $labels)];
        foreach (DISTANCE_TYPES as $kind) {
            $delta = distanceMatrix($this->vectors, $kind);
            $tree = new Tree(agglomerate($delta, $method), $this->count);
            $partition = $tree->cutInto($labels);
            $lines[] = words('metric', $kind, 'cophenetic', formatReal(correlation(pairValues($delta), pairValues($tree->cophenetic()))), 'silhouette', formatReal($this->meanSilhouette($partition, $delta)), 'ari', ariText($this->labelAri($partition)));
        }
        return $lines;
    }

    public function comparisonParts(): array
    {
        $methods = implode(' ', array_map(fn($result) => $result->method, $this->results));
        $cophenetic = ['cophenetic_matrix', 'linkage ' . $methods];
        $agreement = ['agreement k ' . count($this->classes), 'linkage ' . $methods];
        foreach ($this->results as $first) {
            $cophenetic[] = $first->method . ' ' . reals(array_map(fn($second) => correlation($first->cophenetic, $second->cophenetic), $this->results));
            $agreement[] = $first->method . ' ' . reals(array_map(fn($second) => ariValue($this->partitionAri($first->labelPartition, $second->labelPartition)), $this->results));
        }
        return [$cophenetic, $agreement];
    }

    public function summaryPart(): array
    {
        $ranking = range(0, count($this->results) - 1);
        usort($ranking, fn($a, $b) => (fourDigit($this->results[$b]->correlation) <=> fourDigit($this->results[$a]->correlation)) ?: ($a <=> $b));
        $lines = ['summary', 'cophenetic_ranking ' . implode(' ', array_map(fn($i) => $this->results[$i]->method, $ranking))];
        foreach ($this->settings->cutCounts as $position => $k) {
            $best = $this->results[0];
            foreach (array_slice($this->results, 1) as $result) {
                if (ariGreater($result->countCuts[$position]->ari, $best->countCuts[$position]->ari)) {
                    $best = $result;
                }
            }
            $lines[] = words('best_ari k', $k, $best->method, ariText($best->countCuts[$position]->ari));
        }
        foreach ($this->results as $result) {
            $best = 0;
            for ($position = 1; $position < count($this->settings->cutCounts); ++$position) {
                if (fourDigit($result->countCuts[$position]->silhouette) > fourDigit($result->countCuts[$best]->silhouette)) {
                    $best = $position;
                }
            }
            $lines[] = words('best_silhouette', $result->method, 'k', $this->settings->cutCounts[$best], formatReal($result->countCuts[$best]->silhouette));
        }
        $lines[] = words('selected', $this->chosen->method, 'k', $this->kappa);
        return $lines;
    }

    public function validationReport(): array
    {
        $parts = [$this->dataPart(), $this->correlationPart(), $this->histogramPart()];
        foreach ($this->results as $result) {
            $parts[] = $this->linkagePart($result);
        }
        foreach ($this->results as $result) {
            if ($result->method === 'single') {
                $parts[] = $this->mstPart($result);
            }
        }
        $parts[] = $this->comparePart();
        array_push($parts, ...$this->comparisonParts());
        $parts[] = $this->summaryPart();
        return joinParts($parts);
    }

    public function separation(array $first, array $second): float
    {
        $best = INF;
        foreach ($first as $i) {
            foreach ($second as $j) {
                $best = min($best, $this->distances[$i][$j]);
            }
        }
        return $best;
    }

    public function clusterLines(int $g): array
    {
        $group = $this->members[$g];
        $size = count($group);
        $majority = $this->majority[$g];
        $majorityCount = $this->table[$g][$majority];
        $silhouette = sequentialSum(array_map(fn($i) => $this->silhouettes[$i], $group)) / $size;
        $means = [];
        foreach ($this->names as $f => $name) {
            $means[] = sequentialSum(array_map(fn($i) => $this->raw[$i][$f], $group)) / $size;
        }
        $medoid = -1;
        $medoidSum = 0.0;
        $widest = null;
        foreach ($group as $position => $i) {
            $total = sequentialSum(array_map(fn($j) => $this->distances[$i][$j], $group));
            if ($medoid < 0 || $total < $medoidSum) {
                $medoid = $i;
                $medoidSum = $total;
            }
            for ($other = $position + 1; $other < count($group); ++$other) {
                $j = $group[$other];
                if ($widest === null || $this->distances[$i][$j] > $this->distances[$widest[0]][$widest[1]]) {
                    $widest = [$i, $j];
                }
            }
        }
        $nearest = -1;
        $separation = 0.0;
        foreach ($this->members as $h => $other) {
            if ($h === $g) {
                continue;
            }
            $value = $this->separation($group, $other);
            if ($nearest < 0 || $value < $separation) {
                $nearest = $h;
                $separation = $value;
            }
        }
        return [words('cluster', $g + 1, 'size', $size, 'silhouette', formatReal($silhouette), 'majority', $this->classes[$majority], 'purity', $majorityCount . '/' . $size, formatReal($majorityCount / $size)), '  mean ' . reals($means), words('  medoid', $this->idents[$medoid], 'diameter', $widest === null ? '0.0000 - -' : $this->pairText(...$widest), 'nearest', $nearest + 1, 'separation', formatReal($separation))];
    }

    public function selectionPart(): array
    {
        $lines = [words('selected linkage', $this->chosen->method, 'k', $this->kappa, 'ari', ariText($this->selectedCut->ari), 'silhouette', formatReal($this->selectedCut->silhouette))];
        foreach ($this->members as $g => $group) {
            array_push($lines, ...$this->clusterLines($g));
        }
        return $lines;
    }

    public function centroidPart(): array
    {
        $centers = $this->centroids($this->selected);
        $lines = ['centroid_distances'];
        foreach ($centers as $g => $first) {
            $lines[] = ($g + 1) . ' ' . reals(array_map(fn($second) => sqrt(squaredDistance($first, $second)), $centers));
        }
        return $lines;
    }

    public function profilePart(): array
    {
        $width = max(array_map('strlen', $this->names));
        $lines = ['profile_bars'];
        foreach ($this->members as $g => $group) {
            $lines[] = 'cluster ' . ($g + 1);
            foreach ($this->names as $f => $name) {
                $zeta = sequentialSum(array_map(fn($i) => ($this->raw[$i][$f] - $this->means[$f]) / $this->deviations[$f], $group)) / count($group);
                $bar = str_repeat('#', min(10, (int)floor(abs($zeta) * 4)));
                $left = $zeta < 0 ? str_pad($bar, 10, ' ', STR_PAD_LEFT) : str_repeat(' ', 10);
                $right = $zeta < 0 ? str_repeat(' ', 10) : str_pad($bar, 10);
                $lines[] = str_pad($name, $width) . ' ' . $left . '|' . $right . ' ' . formatReal($zeta);
            }
        }
        return $lines;
    }

    public function contingencyPart(): array
    {
        $lines = ['contingency', 'cluster ' . implode(' ', $this->classes) . ' total'];
        foreach ($this->table as $g => $row) {
            $lines[] = words($g + 1, implode(' ', $row), array_sum($row));
        }
        $totals = [];
        foreach ($this->classes as $t => $class) {
            $totals[] = array_sum(array_column($this->table, $t));
        }
        $lines[] = words('total', implode(' ', $totals), $this->count);
        $matches = $this->matches($this->selected);
        $lines[] = words('purity', $matches . '/' . $this->count, formatReal($matches / $this->count));
        return $lines;
    }

    public function misplacedPart(): array
    {
        $lines = ['misplaced'];
        $count = 0;
        foreach ($this->selected as $i => $g) {
            $majority = $this->majority[$g - 1];
            if ($this->targets[$i] !== $majority) {
                ++$count;
                $lines[] = words($this->idents[$i], 'label', $this->labels[$i], 'cluster', $g, 'majority', $this->classes[$majority]);
            }
        }
        $lines[] = 'count ' . $count;
        return $lines;
    }

    public function weakestPart(): array
    {
        $order = range(0, $this->count - 1);
        usort($order, fn($a, $b) => ($this->silhouettes[$a] <=> $this->silhouettes[$b]) ?: ($a <=> $b));
        $lines = ['weakest'];
        foreach (array_slice($order, 0, $this->settings->listSize) as $i) {
            $lines[] = words($this->idents[$i], 'label', $this->labels[$i], 'cluster', $this->selected[$i], 'silhouette', formatReal($this->silhouettes[$i]));
        }
        return $lines;
    }

    public function featurePart(): array
    {
        $ratios = [];
        foreach ($this->names as $f => $name) {
            $values = array_column($this->vectors, $f);
            $overall = sequentialSum($values) / $this->count;
            $means = array_map(fn($group) => sequentialSum(array_map(fn($i) => $values[$i], $group)) / count($group), $this->members);
            $between = $within = 0.0;
            foreach ($this->members as $g => $group) {
                $between += count($group) * ($means[$g] - $overall) * ($means[$g] - $overall);
            }
            foreach ($this->selected as $i => $g) {
                $within += ($values[$i] - $means[$g - 1]) * ($values[$i] - $means[$g - 1]);
            }
            $ratios[] = ($between / ($this->kappa - 1)) / ($within / ($this->count - $this->kappa));
        }
        $ranking = range(0, count($this->names) - 1);
        usort($ranking, fn($a, $b) => (fourDigit($ratios[$b]) <=> fourDigit($ratios[$a])) ?: ($a <=> $b));
        $lines = ['features'];
        foreach ($ranking as $rank => $f) {
            $lines[] = words($rank + 1, $this->names[$f], 'f_ratio', formatReal($ratios[$f]));
        }
        return $lines;
    }

    public function classCounts(Tree $tree, int $node): string
    {
        $counts = array_fill(0, count($this->classes), 0);
        foreach ($tree->members[$node] as $i) {
            ++$counts[$this->targets[$i]];
        }
        return implode('/', $counts);
    }

    public function topMergesPart(): array
    {
        $tree = $this->chosen->tree;
        $lines = ['top_merges'];
        for ($step = $this->count - $this->settings->inconsistencyCount - 1; $step < $this->count - 1; ++$step) {
            $merge = $tree->merges[$step];
            $lines[] = words('step', $step + 1, 'height', formatReal($merge->height), 'a', $merge->a, count($tree->members[$merge->a]), $this->classCounts($tree, $merge->a), 'b', $merge->b, count($tree->members[$merge->b]), $this->classCounts($tree, $merge->b));
        }
        return $lines;
    }

    public function dropFeaturePart(): array
    {
        $lines = ['drop_feature'];
        foreach ($this->names as $f => $name) {
            $reduced = array_map(fn($row) => array_merge(array_slice($row, 0, $f), array_slice($row, $f + 1)), $this->vectors);
            $tree = new Tree(agglomerate(distanceMatrix($reduced, $this->settings->distance), $this->chosen->method), $this->count);
            $partition = $tree->cutInto($this->kappa);
            $lines[] = words($name, 'ari_selected', ariText($this->partitionAri($partition, $this->selected)), 'ari_labels', ariText($this->labelAri($partition)));
        }
        return $lines;
    }

    public function refinementPart(): array
    {
        $limit = $iterations = $this->settings->refineIterations;
        $centers = $this->centroids($this->selected);
        $previous = $this->selected;
        for ($t = 1; $t <= $limit; ++$t) {
            $assignment = [];
            foreach ($this->vectors as $vector) {
                $best = 0;
                $bestValue = squaredDistance($vector, $centers[0]);
                for ($g = 1; $g < count($centers); ++$g) {
                    $value = squaredDistance($vector, $centers[$g]);
                    if ($value < $bestValue) {
                        $best = $g;
                        $bestValue = $value;
                    }
                }
                $assignment[] = $best + 1;
            }
            if ($assignment === $previous) {
                $iterations = $t;
                break;
            }
            foreach (clusterMembers($assignment, $this->kappa) as $g => $group) {
                if ($group !== []) {
                    $centers[$g] = centroid(array_map(fn($i) => $this->vectors[$i], $group));
                }
            }
            $previous = $assignment;
        }
        $changed = 0;
        foreach ($this->selected as $i => $before) {
            if ($before !== $previous[$i]) {
                ++$changed;
            }
        }
        $sizes = array_map('count', clusterMembers($previous, $this->kappa));
        return [words('refinement max_iterations', $limit), words('iterations', $iterations, 'changed', $changed, 'wss', formatReal($this->within($this->selected)), '->', formatReal($this->within($previous))), words('sizes', implode(' ', $sizes), 'silhouette', formatReal($this->meanSilhouette($previous, $this->distances))), words('ari_selected', ariText($this->partitionAri($previous, $this->selected)), 'ari_labels', ariText($this->labelAri($previous)))];
    }

    public function jaccard(array $partition, array $restricted): array
    {
        $table = contingencyTable(array_map(fn($g) => $g - 1, $restricted), array_map(fn($g) => $g - 1, $partition), $this->kappa, max($partition));
        $columns = [];
        for ($h = 0; $h < count($table[0]); ++$h) {
            $columns[] = array_sum(array_column($table, $h));
        }
        $values = [];
        foreach ($table as $row) {
            $size = array_sum($row);
            $best = [0, 1];
            if ($size > 0) {
                foreach ($row as $h => $common) {
                    $candidate = [$common, $size + $columns[$h] - $common];
                    if (ariGreater($candidate, $best)) {
                        $best = $candidate;
                    }
                }
            }
            $values[] = ariValue($best);
        }
        return $values;
    }

    public function stabilityPart(): array
    {
        $settings = $this->settings;
        $n = $this->count;
        $size = intdiv($n * $settings->percent, 100);
        $state = $settings->seed;
        $aris = $jaccards = [];
        $lines = [words('stability replicates', $settings->replicates, 'percent', $settings->percent, 'seed', $settings->seed)];
        for ($b = 1; $b <= $settings->replicates; ++$b) {
            $order = range(0, $n - 1);
            for ($t = 0; $t < $size; ++$t) {
                $state = 48271 * $state % 2147483647;
                $j = $t + $state % ($n - $t);
                [$order[$t], $order[$j]] = [$order[$j], $order[$t]];
            }
            $sample = array_slice($order, 0, $size);
            sort($sample, SORT_NUMERIC);
            $delta = array_map(fn($i) => array_map(fn($j) => $this->distances[$i][$j], $sample), $sample);
            $tree = new Tree(agglomerate($delta, $this->chosen->method), $size);
            $partition = $tree->cutInto($this->kappa);
            $restricted = array_map(fn($i) => $this->selected[$i], $sample);
            $ari = $this->partitionAri($partition, $restricted);
            $jaccard = $this->jaccard($partition, $restricted);
            $aris[] = ariValue($ari);
            $jaccards[] = $jaccard;
            $lines[] = words('replicate', $b, 'size', $size, 'ari', ariText($ari), 'jaccard', reals($jaccard));
        }
        $means = [];
        for ($g = 0; $g < $this->kappa; ++$g) {
            $means[] = sequentialSum(array_column($jaccards, $g)) / $settings->replicates;
        }
        $lines[] = 'mean_ari ' . formatReal(sequentialSum($aris) / $settings->replicates);
        $lines[] = 'mean_jaccard ' . reals($means);
        return $lines;
    }

    public function distanceMapPart(): array
    {
        $order = $this->chosen->tree->order;
        $frame = '+' . str_repeat('-', $this->count) . '+';
        $lines = ['distance_map ' . $this->chosen->method, $frame];
        $shades = '@%#*+=-:. ';
        foreach ($order as $i) {
            $row = '';
            foreach ($order as $j) {
                $row .= $shades[histogramBin($this->distances[$i][$j], $this->distanceMax)];
            }
            $lines[] = '|' . $row . '|';
        }
        $lines[] = $frame;
        return $lines;
    }

    public function profilesReport(): array
    {
        return joinParts([$this->selectionPart(), $this->centroidPart(), $this->profilePart(), $this->contingencyPart(), $this->misplacedPart(), $this->weakestPart(), $this->featurePart(), $this->topMergesPart(), $this->dropFeaturePart(), $this->refinementPart(), $this->stabilityPart(), $this->distanceMapPart()]);
    }
}

[$names, $observations] = readObservations('input/data.csv');
$study = new Study($names, $observations, readSettings('input/params.txt'));
if (!is_dir('output')) {
    mkdir('output');
}
writeLines('output/linkage.csv', $study->linkageTable());
writeLines('output/clusters.csv', $study->clustersTable());
writeLines('output/dendrogram.txt', $study->dendrogramReport());
writeLines('output/trees.txt', $study->treesReport());
writeLines('output/validation.txt', $study->validationReport());
writeLines('output/profiles.txt', $study->profilesReport());
