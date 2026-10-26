<?php
namespace Segments;

require_once __DIR__.'/transactions.php';
require_once __DIR__.'/features.php';
require_once __DIR__.'/kmeans.php';
require_once __DIR__.'/validation.php';
require_once __DIR__.'/profiles.php';
require_once __DIR__.'/report.php';

function blocks(array $sections): array
{
    $lines = [];
    foreach ($sections as $index => $section) {
        if ($index > 0) $lines[] = '';
        array_push($lines, ...$section);
    }
    return $lines;
}

function yes_no(bool $value): string
{
    return $value ? 'yes' : 'no';
}

class Minstd
{
    public function __construct(private int $state) {}

    public function draw(): int
    {
        return $this->state = (48271 * $this->state) % 2147483647;
    }
}

function initial_indices(array $points, int $k, string $method, int $restart, Minstd $generator): array
{
    $chosen = [];
    if ($method === 'forgy') {
        while (count($chosen) < $k) {
            $index = $generator->draw() % count($points);
            if (!in_array($index, $chosen, true)) $chosen[] = $index;
        }
        return $chosen;
    }
    if ($method === 'maximin') {
        $center = mean_point($points);
        $distances = array_map(fn($point) => squared_distance($point, $center), $points);
        $order = array_keys($points);
        usort($order, fn($a, $b) => ($distances[$a] <=> $distances[$b]) ?: ($a <=> $b));
        $chosen[] = $order[$restart - 1];
    } else {
        $chosen[] = $generator->draw() % count($points);
    }
    while (count($chosen) < $k) {
        $gaps = [];
        foreach ($points as $point) {
            $best = squared_distance($point, $points[$chosen[0]]);
            foreach (array_slice($chosen, 1) as $index) $best = min($best, squared_distance($point, $points[$index]));
            $gaps[] = $best;
        }
        $selected = 0;
        if ($method === 'maximin') {
            for ($index = 1; $index < count($gaps); $index++) if ($gaps[$index] > $gaps[$selected]) $selected = $index;
        } else {
            $threshold = ($generator->draw() / 2147483647) * ordered_sum($gaps);
            $cumulative = 0.0;
            $selected = -1;
            foreach ($gaps as $index => $gap) {
                $cumulative += $gap;
                if ($cumulative > $threshold) {
                    $selected = $index;
                    break;
                }
            }
            if ($selected < 0) foreach ($gaps as $index => $gap) if ($gap > 0) $selected = $index;
        }
        $chosen[] = $selected;
    }
    return $chosen;
}

function refine(array $points, array $labels, int $k, int $limit): array
{
    $sizes = array_map('count', cluster_groups($labels, $k));
    $centers = cluster_centers($points, $labels, $k);
    $passes = $transfers = 0;
    while ($passes < $limit) {
        $changes = 0;
        foreach ($points as $index => $point) {
            $own = $labels[$index];
            if ($sizes[$own] === 1) continue;
            $removal = ($sizes[$own] / ($sizes[$own] - 1)) * squared_distance($point, $centers[$own]);
            $target = -1;
            $cost = 0.0;
            for ($label = 0; $label < $k; $label++) if ($label !== $own) {
                $insertion = ($sizes[$label] / ($sizes[$label] + 1)) * squared_distance($point, $centers[$label]);
                if ($target < 0 || $insertion < $cost) [$target, $cost] = [$label, $insertion];
            }
            if ($cost < $removal) {
                $labels[$index] = $target;
                $sizes[$own]--;
                $sizes[$target]++;
                $centers[$own] = cluster_center($points, $labels, $own);
                $centers[$target] = cluster_center($points, $labels, $target);
                $changes++;
                $transfers++;
            }
        }
        $passes++;
        if ($changes === 0) break;
    }
    return ['labels' => $labels, 'passes' => $passes, 'transfers' => $transfers,
        'sse' => sum_squared($points, $labels, cluster_centers($points, $labels, $k))];
}

function clustering_run(array $points, int $k, string $method, int $restart, int $limit, Minstd $generator): array
{
    $seeds = initial_indices($points, $k, $method, $restart, $generator);
    $result = lloyd($points, array_map(fn($index) => $points[$index], $seeds), $limit);
    return ['method' => $method, 'restart' => $restart, 'seeds' => $seeds, 'result' => $result,
        'refined' => refine($points, $result['labels'], $k, $limit)];
}

function organize(array $points, array $labels, int $k): array
{
    $groups = cluster_groups($labels, $k);
    usort($groups, fn($a, $b) => (count($b) <=> count($a)) ?: ($a[0] <=> $b[0]));
    $ordered = array_fill(0, count($points), 0);
    foreach ($groups as $label => $members) foreach ($members as $index) $ordered[$index] = $label;
    $centers = cluster_centers($points, $ordered, $k);
    return ['k' => $k, 'labels' => $ordered, 'members' => $groups, 'centers' => $centers,
        'sse' => sum_squared($points, $ordered, $centers)];
}

function gini(array $spends): float
{
    sort($spends, SORT_NUMERIC);
    $total = $weighted = 0;
    foreach ($spends as $index => $spend) {
        $total += $spend;
        $weighted += ($index + 1) * $spend;
    }
    return (2 * $weighted - (count($spends) + 1) * $total) / (count($spends) * $total);
}

function category_totals(array $customers): array
{
    $totals = [];
    foreach ($customers as $customer) foreach ($customer['category_spend'] as $category => $spend) {
        $totals[$category] = ($totals[$category] ?? 0) + $spend;
    }
    return $totals;
}

class Analysis
{
    private array $p, $data, $rules, $orders, $orderGroups, $customers, $numbers, $scaling, $points;
    private array $solutions, $votes, $voteCounts, $final, $distances, $others, $scores, $codes;
    private array $categories, $categoryNames, $segmentSpends, $segmentCategories, $rankings, $segmentSSE, $jaccards;
    private int $n, $k, $totalSpend;
    private Minstd $generator;
    private const CRITERIA = ['elbow', 'silhouette', 'calinski_harabasz', 'davies_bouldin', 'hartigan'];

    public function __construct()
    {
        $this->p = read_params('input/params.txt');
        $this->data = read_transactions('input/transactions.csv');
        $this->rules = read_rules('input/segment_rules.txt');
        $this->orders = group_orders($this->data['rows'], 1, $this->p['REFERENCE_DAY']);
        $this->orderGroups = orders_by_customer($this->orders);
        $this->customers = customer_features($this->orders, $this->p['REFERENCE_DAY']);
        $this->n = count($this->customers);
        $this->numbers = [];
        foreach ($this->customers as $index => $customer) $this->numbers['#'.$customer['id']] = $index;
        $this->scaling = fit_scaling($this->customers);
        $this->points = array_map(fn($customer) => standardize($customer['transformed'], $this->scaling), $this->customers);
        $this->generator = new Minstd($this->p['SEED']);
        $this->solutions = [];
        $this->fit();
        $this->details();
        $this->jaccards = $this->subsamples();
    }

    private function ids(array $indices): string
    {
        return implode(' ', array_map(fn($index) => $this->customers[$index]['id'], $indices));
    }

    private function fit(): void
    {
        [$first, $last] = $this->p['K_RANGE'];
        $table = distance_table($this->points);
        for ($k = $first; $k <= $last; $k++) {
            $runs = $bests = [];
            $best = null;
            foreach ($this->p['METHODS'] as $method) {
                $methodBest = null;
                for ($restart = 1; $restart <= $this->p['RESTARTS']; $restart++) {
                    $run = clustering_run($this->points, $k, $method, $restart, $this->p['MAX_ITERATIONS'], $this->generator);
                    $runs[] = $run;
                    if ($methodBest === null || rounded_key($run['refined']['sse']) < rounded_key($methodBest['refined']['sse'])) $methodBest = $run;
                }
                $bests[] = $methodBest;
                if ($best === null || rounded_key($methodBest['refined']['sse']) < rounded_key($best['refined']['sse'])) $best = $methodBest;
            }
            $solution = organize($this->points, $best['refined']['labels'], $k);
            $solution['runs'] = $runs;
            $solution['bests'] = $bests;
            $solution['best'] = $best;
            $solution['indices'] = cluster_indices($this->points, $solution, $table);
            $solution['names'] = $solution['rules'] = [];
            $used = [];
            foreach ($solution['centers'] as $center) {
                $rule = rule_number($center, $this->rules);
                $used[$rule] = ($used[$rule] ?? 0) + 1;
                $solution['rules'][] = $rule + 1;
                $solution['names'][] = $this->rules[$rule]['name'].($used[$rule] === 1 ? '' : '_'.$used[$rule]);
            }
            $this->solutions[$k] = $solution;
        }
        for ($k = $first; $k <= $last; $k++) {
            $solution = &$this->solutions[$k];
            $solution['indices']['elbow'] = elbow($k, $first, $last, $solution['sse'], $this->solutions[$first]['sse'], $this->solutions[$last]['sse']);
            $solution['hartigan'] = $k < $last ? hartigan($solution['sse'], $this->solutions[$k + 1]['sse'], $this->n, $k) : null;
            unset($solution);
        }
        $this->votes = $this->voteCounts = [];
        foreach (self::CRITERIA as $criterion) {
            if ($criterion === 'hartigan') {
                $chosen = $last;
                for ($k = $first; $k < $last; $k++) if ($this->solutions[$k]['hartigan'] <= 10) {
                    $chosen = $k;
                    break;
                }
            } else {
                $start = $first + ($criterion === 'elbow' ? 1 : 0);
                $end = $last - ($criterion === 'elbow' ? 1 : 0);
                $chosen = $start;
                for ($k = $start + 1; $k <= $end; $k++) {
                    $value = rounded_key($this->solutions[$k]['indices'][$criterion]);
                    $current = rounded_key($this->solutions[$chosen]['indices'][$criterion]);
                    if ($criterion === 'davies_bouldin' ? $value < $current : $value > $current) $chosen = $k;
                }
            }
            $this->votes[] = $chosen;
            $this->voteCounts[$chosen] = ($this->voteCounts[$chosen] ?? 0) + 1;
        }
        $this->k = $first;
        for ($k = $first + 1; $k <= $last; $k++) {
            $count = $this->voteCounts[$k] ?? 0;
            $previous = $this->voteCounts[$this->k] ?? 0;
            if ($count > $previous || ($count === $previous && rounded_key($this->solutions[$k]['indices']['silhouette']) > rounded_key($this->solutions[$this->k]['indices']['silhouette']))) $this->k = $k;
        }
        $this->final = $this->solutions[$this->k];
    }

    private function details(): void
    {
        $this->distances = $this->others = $this->scores = $this->codes = [];
        foreach ($this->customers as $index => $customer) {
            $own = $this->final['labels'][$index];
            $this->distances[] = sqrt(squared_distance($this->points[$index], $this->final['centers'][$own]));
            $other = -1;
            $best = 0.0;
            foreach ($this->final['centers'] as $label => $center) if ($label !== $own) {
                $distance = squared_distance($this->points[$index], $center);
                if ($other < 0 || $distance < $best) [$other, $best] = [$label, $distance];
            }
            $this->others[] = [$other, sqrt($best)];
            $ranks = [0, 0, 0];
            foreach ($this->customers as $candidate) {
                if ($candidate['raw'][0] > $customer['raw'][0]) $ranks[0]++;
                if ($candidate['raw'][1] < $customer['raw'][1]) $ranks[1]++;
                if ($candidate['spend'] < $customer['spend']) $ranks[2]++;
            }
            $scores = array_map(fn($rank) => 1 + intdiv(5 * $rank, $this->n), $ranks);
            $this->scores[] = $scores;
            $this->codes[] = implode('', $scores);
        }
        $this->totalSpend = array_sum(array_column($this->customers, 'spend'));
        $this->categories = category_totals($this->customers);
        $this->categoryNames = array_keys($this->categories);
        usort($this->categoryNames, 'strcmp');
        $this->segmentSpends = $this->segmentCategories = $this->rankings = $this->segmentSSE = [];
        foreach ($this->final['members'] as $label => $members) {
            $customers = array_map(fn($index) => $this->customers[$index], $members);
            $this->segmentSpends[] = array_sum(array_column($customers, 'spend'));
            $totals = category_totals($customers);
            $this->segmentCategories[] = $totals;
            $ranking = array_keys(array_filter($totals, fn($amount) => $amount > 0));
            usort($ranking, fn($a, $b) => ($totals[$b] <=> $totals[$a]) ?: strcmp($a, $b));
            $this->rankings[] = $ranking;
            $this->segmentSSE[] = ordered_sum(array_map(fn($index) => squared_distance($this->points[$index], $this->final['centers'][$label]), $members));
        }
    }

    private function subsamples(): array
    {
        $size = intdiv($this->n * $this->p['SUBSAMPLE_PERCENT'], 100);
        $values = array_fill(0, $this->k, []);
        for ($b = 0; $b < $this->p['SUBSAMPLES']; $b++) {
            $order = range(0, $this->n - 1);
            for ($position = 0; $position < $size; $position++) {
                $other = $position + $this->generator->draw() % ($this->n - $position);
                [$order[$position], $order[$other]] = [$order[$other], $order[$position]];
            }
            $sample = array_slice($order, 0, $size);
            sort($sample, SORT_NUMERIC);
            $result = lloyd(array_map(fn($index) => $this->points[$index], $sample), $this->final['centers'], $this->p['MAX_ITERATIONS']);
            for ($segment = 0; $segment < $this->k; $segment++) {
                $best = 0.0;
                for ($label = 0; $label < $this->k; $label++) {
                    $both = $either = 0;
                    foreach ($sample as $position => $index) {
                        $member = $this->final['labels'][$index] === $segment;
                        $assigned = $result['labels'][$position] === $label;
                        if ($member && $assigned) $both++;
                        if ($member || $assigned) $either++;
                    }
                    if ($either > 0) $best = max($best, $both / $either);
                }
                $values[$segment][] = $best;
            }
        }
        return $values;
    }

    public function featuresLines(): array
    {
        $lines = ['customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure'];
        foreach ($this->customers as $index => $customer) {
            $raw = $customer['raw'];
            $fields = [$customer['id'], $raw[0], $raw[1], amount($customer['spend']), real_text($raw[3]), $raw[4], $raw[5]];
            array_push($fields, ...array_map(__NAMESPACE__.'\\real_text', $this->points[$index]));
            $lines[] = implode(',', $fields);
        }
        return $lines;
    }

    public function runsLines(): array
    {
        $sections = [];
        foreach ($this->solutions as $k => $solution) {
            $lines = ["k $k"];
            foreach ($solution['runs'] as $run) {
                $ll = $run['result'];
                $refined = $run['refined'];
                $lines[] = "run {$run['method']} {$run['restart']} seeds ".$this->ids($run['seeds'])." iterations {$ll['iterations']} converged ".yes_no($ll['converged'])." reseeds {$ll['reseeds']} sse ".real_text($ll['sse'])." passes {$refined['passes']} transfers {$refined['transfers']} refined ".real_text($refined['sse']);
            }
            foreach ($solution['bests'] as $run) $lines[] = "best {$run['method']} restart {$run['restart']} sse ".real_text($run['refined']['sse']);
            $chosen = $solution['best'];
            $lines[] = "chosen {$chosen['method']} restart {$chosen['restart']} sse ".real_text($chosen['refined']['sse']);
            $lines[] = 'sizes '.implode(' ', array_map('count', $solution['members']));
            $sections[] = $lines;
        }
        return blocks($sections);
    }

    public function selectionLines(): array
    {
        $indices = ['indices'];
        $names = ['segments'];
        $stability = ['stability'];
        foreach ($this->solutions as $k => $solution) {
            $ix = $solution['indices'];
            $hartiganText = $solution['hartigan'] === null ? '-' : real_text($solution['hartigan']);
            $indices[] = "k=$k sse ".real_text($solution['sse']).' elbow '.real_text($ix['elbow']).' silhouette '.real_text($ix['silhouette']).' calinski_harabasz '.real_text($ix['calinski_harabasz']).' davies_bouldin '.real_text($ix['davies_bouldin'])." hartigan $hartiganText";
            $parts = [];
            foreach ($solution['members'] as $label => $members) $parts[] = $solution['names'][$label].':'.count($members);
            $names[] = "k=$k ".implode(' ', $parts);
            $parts = ["k=$k"];
            foreach ($solution['bests'] as $index => $first) for ($j = $index + 1; $j < count($solution['bests']); $j++) {
                $second = $solution['bests'][$j];
                $parts[] = $first['method'].':'.$second['method'].' '.real_text(adjusted_rand($first['refined']['labels'], $second['refined']['labels']));
            }
            $parts[] = 'final';
            foreach ($solution['bests'] as $run) $parts[] = $run['method'].' '.real_text(adjusted_rand($run['refined']['labels'], $solution['labels']));
            $parts[] = 'next '.($k === $this->p['K_RANGE'][1] ? '-' : real_text(adjusted_rand($solution['labels'], $this->solutions[$k + 1]['labels'])));
            $stability[] = implode(' ', $parts);
        }
        $votes = ['votes'];
        foreach (self::CRITERIA as $index => $name) $votes[] = $name.' k='.$this->votes[$index];
        $votes[] = "chosen k={$this->k} votes ".$this->voteCounts[$this->k];
        return blocks([$indices, $votes, $names, $stability]);
    }

    public function segmentsLines(): array
    {
        $lines = ['customer,segment,name,distance,other,other_distance,silhouette,recommend'];
        foreach ($this->customers as $index => $customer) {
            $label = $this->final['labels'][$index];
            $recommend = '-';
            foreach ($this->rankings[$label] as $category) if (($customer['category_spend'][$category] ?? 0) <= 0) {
                $recommend = $category;
                break;
            }
            $lines[] = implode(',', [$customer['id'], $label + 1, $this->final['names'][$label], real_text($this->distances[$index]),
                $this->others[$index][0] + 1, real_text($this->others[$index][1]), real_text($this->final['indices']['silhouettes'][$index]), $recommend]);
        }
        return $lines;
    }

    private function related(array $members, int $k): string
    {
        if ($k < $this->p['K_RANGE'][0] || $k > $this->p['K_RANGE'][1]) return "k=$k -";
        $counts = array_fill(0, $k, 0);
        foreach ($members as $index) $counts[$this->solutions[$k]['labels'][$index]]++;
        $best = 0;
        for ($label = 1; $label < $k; $label++) if ($counts[$label] > $counts[$best]) $best = $label;
        return "k=$k segment ".($best + 1).' shared '.$counts[$best];
    }

    private function profileLines(int $segment): array
    {
        $members = $this->final['members'][$segment];
        $center = $this->final['centers'][$segment];
        $customers = array_map(fn($index) => $this->customers[$index], $members);
        $size = count($members);
        $spend = $this->segmentSpends[$segment];
        $lines = ['segment '.($segment + 1).' '.$this->final['names'][$segment].' rule '.$this->final['rules'][$segment]." size $size share ".real_text($size / $this->n).' revenue '.amount($spend).' revenue_share '.real_text($spend / $this->totalSpend)];
        $lines[] = '  center '.reals($center);
        $values = original_center($center, $this->scaling);
        $parts = [];
        foreach (FEATURE_NAMES as $feature => $name) $parts[] = $name.' '.real_text($values[$feature]);
        $lines[] = '  value '.implode(' ', $parts);
        $order = range(0, 5);
        usort($order, fn($a, $b) => (abs($center[$b]) <=> abs($center[$a])) ?: ($a <=> $b));
        $traits = array_map(fn($feature) => ($center[$feature] > 0 ? 'high_' : 'low_').FEATURE_NAMES[$feature], array_slice($order, 0, 2));
        $lines[] = '  traits '.implode(' ', $traits);
        $medians = [];
        foreach (FEATURE_NAMES as $feature => $name) {
            $column = array_map(fn($customer) => $feature === 2 ? $customer['spend'] : $customer['raw'][$feature], $customers);
            sort($column, SORT_NUMERIC);
            $medians[] = $column[intdiv($size - 1, 2)];
        }
        $lines[] = "  median recency {$medians[0]} frequency {$medians[1]} monetary ".amount($medians[2]).' basket '.real_text($medians[3])." categories {$medians[4]} tenure {$medians[5]}";
        $lines[] = '  related '.$this->related($members, $this->k - 1).' '.$this->related($members, $this->k + 1);
        $top = $members;
        usort($top, fn($a, $b) => ($this->customers[$b]['spend'] <=> $this->customers[$a]['spend']) ?: ($a <=> $b));
        $parts = ['  top_customers'];
        foreach (array_slice($top, 0, $this->p['TOP_CUSTOMERS']) as $index) $parts[] = $this->customers[$index]['id'].' '.amount($this->customers[$index]['spend']);
        $lines[] = implode(' ', $parts);
        $gaps = [];
        $overdue = $gross = $returned = $cancelled = 0;
        $bins = array_fill(0, count($this->p['ORDER_BINS']) + 1, 0);
        foreach ($customers as $customer) {
            $raw = $customer['raw'];
            if ($raw[1] >= 2) {
                $gaps[] = ($raw[5] - $raw[0]) / ($raw[1] - 1);
                if ($raw[0] * ($raw[1] - 1) > $this->p['OVERDUE_FACTOR'] * ($raw[5] - $raw[0])) $overdue++;
            }
            foreach ($customer['orders'] as $order) {
                $bin = count(array_filter($this->p['ORDER_BINS'], fn($bound) => $order['net'] >= $bound * 100));
                $bins[$bin]++;
            }
            foreach ($this->orderGroups['#'.$customer['id']] as $order) {
                if ($order['net'] <= 0) $cancelled++;
                foreach ($order['rows'] as $row) {
                    if ($row['amount'] > 0) $gross += $row['amount'];
                    else $returned -= $row['amount'];
                }
            }
        }
        $lines[] = '  cadence customers '.count($gaps).' mean_gap '.($gaps ? real_text(mean($gaps)) : '-')." overdue $overdue";
        $lines[] = '  order_sizes '.implode(' ', $bins);
        $lines[] = '  sse '.real_text($this->segmentSSE[$segment]).' share '.real_text($this->segmentSSE[$segment] / $this->final['sse']);
        $lines[] = '  gini '.real_text(gini(array_column($customers, 'spend')));
        $lines[] = '  returns rate '.real_text($returned / $gross).' returned '.amount($returned)." cancelled $cancelled";
        $silhouettes = array_map(fn($index) => $this->final['indices']['silhouettes'][$index], $members);
        $lines[] = '  silhouette '.real_text(mean($silhouettes)).' negative '.count(array_filter($silhouettes, fn($value) => $value < 0));
        $scores = [0, 0, 0];
        $counts = [];
        foreach ($members as $index) {
            for ($part = 0; $part < 3; $part++) $scores[$part] += $this->scores[$index][$part];
            $key = '#'.$this->codes[$index];
            $counts[$key] = ($counts[$key] ?? 0) + 1;
        }
        $codes = array_keys($counts);
        usort($codes, fn($a, $b) => ($counts[$b] <=> $counts[$a]) ?: strcmp(substr($a, 1), substr($b, 1)));
        $lines[] = '  rfm r '.real_text($scores[0] / $size).' f '.real_text($scores[1] / $size).' m '.real_text($scores[2] / $size).' mode '.substr($codes[0], 1).' '.$counts[$codes[0]];
        $parts = ['  categories'];
        foreach (array_slice($this->rankings[$segment], 0, $this->p['TOP_CATEGORIES']) as $category) {
            $share = $this->segmentCategories[$segment][$category] / $spend;
            $parts[] = $category.' '.real_text($share).' '.real_text($share / ($this->categories[$category] / $this->totalSpend));
        }
        $lines[] = implode(' ', $parts);
        $outliers = [];
        if ($size >= 2) {
            $distances = array_map(fn($index) => $this->distances[$index], $members);
            $limit = mean($distances) + $this->p['OUTLIER_SD'] * sample_sd($distances);
            foreach ($members as $index) if ($this->distances[$index] > $limit) $outliers[] = $this->customers[$index]['id'];
        }
        $lines[] = '  outliers '.count($outliers).($outliers ? ' '.implode(' ', $outliers) : '');
        return $lines;
    }

    public function profilesLines(): array
    {
        $sections = [["segments k={$this->k} customers {$this->n} revenue ".amount($this->totalSpend).' gini '.real_text(gini(array_column($this->customers, 'spend')))]];
        for ($label = 0; $label < $this->k; $label++) $sections[] = $this->profileLines($label);
        $numbers = implode(' ', range(1, $this->k));
        $mix = ['category_mix '.$numbers];
        foreach ($this->categoryNames as $category) {
            $shares = [];
            foreach ($this->segmentSpends as $label => $spend) $shares[] = ($this->segmentCategories[$label][$category] ?? 0) / $spend;
            $mix[] = $category.' '.reals($shares);
        }
        $recency = ['rfm_recency '.$numbers];
        for ($score = 5; $score >= 1; $score--) {
            $counts = array_fill(0, $this->k, 0);
            foreach ($this->scores as $index => $scores) if ($scores[0] === $score) $counts[$this->final['labels'][$index]]++;
            $recency[] = "r=$score ".implode(' ', $counts);
        }
        $recency[] = 'ari rfm_codes '.real_text(adjusted_rand($this->codes, $this->final['labels']));
        $centers = ['center_distances'];
        foreach ($this->final['centers'] as $label => $center) $centers[] = ($label + 1).' '.reals(array_map(fn($other) => sqrt(squared_distance($center, $other)), $this->final['centers']));
        array_push($sections, $mix, $recency, $centers);
        return blocks($sections);
    }

    public function robustnessLines(): array
    {
        $subsamples = ['subsamples '.$this->p['SUBSAMPLES'].' size '.intdiv($this->n * $this->p['SUBSAMPLE_PERCENT'], 100)];
        foreach ($this->jaccards as $label => $values) $subsamples[] = 'segment '.($label + 1).' '.$this->final['names'][$label].' mean_jaccard '.real_text(mean($values)).' min_jaccard '.real_text(min($values));
        $ablation = ['ablation'];
        foreach (FEATURE_NAMES as $feature => $name) {
            $points = array_map(fn($point) => array_merge(array_slice($point, 0, $feature), array_slice($point, $feature + 1)), $this->points);
            $run = clustering_run($points, $this->k, 'maximin', 1, $this->p['MAX_ITERATIONS'], $this->generator);
            $ll = $run['result'];
            $refined = $run['refined'];
            $ablation[] = "without $name seeds ".$this->ids($run['seeds'])." iterations {$ll['iterations']} converged ".yes_no($ll['converged'])." transfers {$refined['transfers']} sse ".real_text($refined['sse']).' ari '.real_text(adjusted_rand($refined['labels'], $this->final['labels']));
        }
        $members = $this->final['members'][0];
        $points = array_map(fn($index) => $this->points[$index], $members);
        $run = clustering_run($points, 2, 'maximin', 1, $this->p['MAX_ITERATIONS'], $this->generator);
        $parts = organize($points, $run['refined']['labels'], 2);
        $ll = $run['result'];
        $refined = $run['refined'];
        $seedIDs = $this->ids(array_map(fn($index) => $members[$index], $run['seeds']));
        $drilldown = ['drilldown segment 1 '.$this->final['names'][0].' size '.count($members)." seeds $seedIDs iterations {$ll['iterations']} converged ".yes_no($ll['converged'])." transfers {$refined['transfers']}",
            'sse before '.real_text($this->segmentSSE[0]).' after '.real_text($refined['sse']).' gain '.real_text($this->segmentSSE[0] - $refined['sse'])];
        foreach ($parts['members'] as $label => $group) $drilldown[] = 'part '.($label + 1).' size '.count($group).' center '.reals($parts['centers'][$label]);
        return blocks([$subsamples, $ablation, $drilldown]);
    }

    public function trackingLines(): array
    {
        $p = $this->p;
        $periods = ["periods {$p['PERIODS']} days {$p['PERIOD_DAYS']}"];
        for ($period = 1; $period <= $p['PERIODS']; $period++) {
            $first = $p['REFERENCE_DAY'] - $period * $p['PERIOD_DAYS'] + 1;
            $last = $p['REFERENCE_DAY'] - ($period - 1) * $p['PERIOD_DAYS'];
            $revenue = $active = $acquired = array_fill(0, $this->k, 0);
            foreach ($this->customers as $index => $customer) {
                $label = $this->final['labels'][$index];
                $used = false;
                foreach ($customer['orders'] as $order) if ($first <= $order['day'] && $order['day'] <= $last) {
                    $revenue[$label] += $order['net'];
                    $used = true;
                }
                if ($used) $active[$label]++;
                $initialDay = $p['REFERENCE_DAY'] - $customer['raw'][5];
                if ($first <= $initialDay && $initialDay <= $last) $acquired[$label]++;
            }
            $periods[] = "period $period days $first $last revenue ".implode(' ', array_map(__NAMESPACE__.'\\amount', $revenue)).' active '.implode(' ', $active).' acquired '.implode(' ', $acquired);
        }
        $snapshot = customer_features(group_orders($this->data['rows'], 1, $p['SNAPSHOT_DAY']), $p['SNAPSHOT_DAY']);
        $previous = [];
        foreach ($snapshot as $customer) {
            [$labels] = assign([standardize($customer['transformed'], $this->scaling)], $this->final['centers']);
            $previous['#'.$customer['id']] = $labels[0];
        }
        $table = array_fill(0, $this->k + 1, array_fill(0, $this->k, 0));
        $moved = [];
        $stayed = $fresh = $lost = 0;
        foreach ($this->customers as $index => $customer) {
            $current = $this->final['labels'][$index];
            $old = $previous['#'.$customer['id']] ?? $this->k;
            $table[$old][$current]++;
            if ($old === $this->k) $fresh++;
            elseif ($old === $current) $stayed++;
            else $moved[] = $customer['id'].' '.($old + 1).' '.($current + 1);
        }
        foreach ($previous as $key => $label) if (!isset($this->numbers[$key])) $lost++;
        $migration = ['migration day '.$p['SNAPSHOT_DAY'].' customers '.count($snapshot), 'from\\to '.implode(' ', range(1, $this->k))];
        foreach ($table as $label => $row) $migration[] = ($label === $this->k ? 'none' : $label + 1).' '.implode(' ', $row);
        $migration[] = 'moved_customers';
        array_push($migration, ...$moved);
        $migration[] = "stayed $stayed moved ".count($moved)." new $fresh lost $lost";
        $purchases = [];
        foreach (group_orders($this->data['rows'], $p['REFERENCE_DAY'] + 1, $p['REFERENCE_DAY'] + $p['OUTCOME_DAYS']) as $order) {
            if ($order['net'] > 0) $purchases['#'.$order['customer']] = ($purchases['#'.$order['customer']] ?? 0) + $order['net'];
        }
        $outcome = ['outcome days '.($p['REFERENCE_DAY'] + 1).' '.($p['REFERENCE_DAY'] + $p['OUTCOME_DAYS'])];
        foreach ($this->final['members'] as $label => $members) {
            $buyers = $spend = 0;
            foreach ($members as $index) {
                $key = '#'.$this->customers[$index]['id'];
                if (isset($purchases[$key])) {
                    $buyers++;
                    $spend += $purchases[$key];
                }
            }
            $size = count($members);
            $outcome[] = 'segment '.($label + 1).' '.$this->final['names'][$label]." size $size buyers $buyers rate ".real_text($buyers / $size).' revenue '.amount($spend).' per_customer '.real_text(($spend / 100) / $size);
        }
        $outsiders = $spend = 0;
        foreach ($purchases as $key => $value) if (!isset($this->numbers[$key])) {
            $outsiders++;
            $spend += $value;
        }
        $outcome[] = "unsegmented buyers $outsiders revenue ".amount($spend);
        return blocks([$periods, $migration, $outcome]);
    }

    public function summaryLines(): array
    {
        $used = $returns = $later = $valid = 0;
        foreach ($this->data['rows'] as $row) {
            if ($row['day'] <= $this->p['REFERENCE_DAY']) {
                $used++;
                if ($row['amount'] < 0) $returns++;
            } else $later++;
        }
        foreach ($this->orders as $order) if ($order['net'] > 0) $valid++;
        $excluded = [];
        foreach ($this->data['customers'] as $key => $id) if (!isset($this->numbers[$key])) $excluded[] = $id;
        usort($excluded, 'strcmp');
        $data = ['rows '.$this->data['count'].' duplicates '.$this->data['duplicates'].' zero '.$this->data['zero']." used $used returns $returns later $later",
            'orders '.count($this->orders)." valid $valid cancelled ".(count($this->orders) - $valid),
            'customers '.count($this->data['customers'])." clustered {$this->n} excluded ".count($excluded),
            'excluded_ids '.($excluded ? implode(' ', $excluded) : '-')];
        $categories = [];
        foreach ($this->categoryNames as $category) {
            $buyers = count(array_filter($this->customers, fn($customer) => ($customer['category_spend'][$category] ?? 0) > 0));
            $categories[] = 'category '.$category.' revenue '.amount($this->categories[$category]).' share '.real_text($this->categories[$category] / $this->totalSpend)." customers $buyers";
        }
        $features = [];
        $correlations = ['correlation '.implode(' ', FEATURE_NAMES)];
        foreach (FEATURE_NAMES as $feature => $name) {
            $scale = $this->scaling[$feature];
            $features[] = "feature $name transform ".(root_feature($feature) ? 'sqrt' : 'none').' raw_mean '.real_text($scale['raw_mean']).' raw_sd '.real_text($scale['raw_sd']).' mean '.real_text($scale['mean']).' sd '.real_text($scale['sd']);
            $values = [];
            for ($other = 0; $other < 6; $other++) $values[] = correlation($this->points, $feature, $other);
            $correlations[] = $name.' '.reals($values);
        }
        return blocks([$data, $categories, $features, $correlations]);
    }
}

$analysis = new Analysis();
if (!is_dir('output')) mkdir('output', 0777, true);
write_lines('features.csv', $analysis->featuresLines());
write_lines('runs.txt', $analysis->runsLines());
write_lines('selection.txt', $analysis->selectionLines());
write_lines('segments.csv', $analysis->segmentsLines());
write_lines('profiles.txt', $analysis->profilesLines());
write_lines('robustness.txt', $analysis->robustnessLines());
write_lines('tracking.txt', $analysis->trackingLines());
write_lines('summary.txt', $analysis->summaryLines());
