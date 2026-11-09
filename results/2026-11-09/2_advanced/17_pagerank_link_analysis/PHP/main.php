<?php
namespace LinkAnalysis;

require_once __DIR__.'/graph_io.php';
require_once __DIR__.'/components.php';
require_once __DIR__.'/pagerank.php';
require_once __DIR__.'/hits.php';
require_once __DIR__.'/report.php';

const REGIONS = ['CORE', 'IN', 'OUT', 'TUBE', 'IN_TENDRIL', 'OUT_TENDRIL', 'OTHER'];
const QUANTITIES = ['in_degree', 'pagerank', 'cheirank', 'authority', 'hub', 'trustrank', 'harmonic'];

function indices(int $count, ?callable $predicate = null): array
{
    $values = [];
    for ($i = 0; $i < $count; $i++) if ($predicate === null || $predicate($i)) $values[] = $i;
    return $values;
}

function total(array $values): float
{
    $result = 0.0;
    foreach ($values as $value) $result += $value;
    return $result;
}

function joined(string $prefix, array $values): string
{
    return $prefix.($values ? ' '.implode(' ', $values) : '');
}

function blocks(array $sections): array
{
    $lines = [];
    foreach ($sections as $index => $section) {
        if ($index > 0) $lines[] = '';
        array_push($lines, ...$section);
    }
    return $lines;
}

function rank_order(array $values): array
{
    $order = array_keys($values);
    usort($order, fn($a, $b) => (scaled($values[$b]) <=> scaled($values[$a])) ?: ($a <=> $b));
    return $order;
}

function positions(array $order): array
{
    $rank = array_fill(0, count($order), 0);
    foreach ($order as $position => $node) $rank[$node] = $position + 1;
    return $rank;
}

function top_list(array $values, int $limit): array
{
    return array_slice(array_values(array_filter(rank_order($values), fn($node) => scaled($values[$node]) > 0)), 0, $limit);
}

function ranked_counts(array $counts, int $limit): array
{
    $order = indices(count($counts), fn($node) => $counts[$node] > 0);
    usort($order, fn($a, $b) => ($counts[$b] <=> $counts[$a]) ?: ($a <=> $b));
    return array_slice($order, 0, $limit);
}

function distribution(array $values): array
{
    $counts = array_count_values($values);
    ksort($counts, SORT_NUMERIC);
    $lines = [];
    foreach ($counts as $value => $count) $lines[] = "$value $count";
    return $lines;
}

function kendall(array $first, array $second): string
{
    $result = 0;
    for ($i = 0; $i < count($first); $i++) for ($j = $i + 1; $j < count($first); $j++) {
        $x = $first[$i] - $first[$j];
        $y = $second[$i] - $second[$j];
        if ($x !== 0 && $y !== 0) $result += (($x > 0) === ($y > 0)) ? 1 : -1;
    }
    return fraction($result, intdiv(count($first) * (count($first) - 1), 2));
}

class Graph
{
    public array $successors, $predecessors, $present;
    public int $n;

    public function __construct(public array $pages, public array $links)
    {
        usort($this->links, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));
        $this->n = count($pages);
        $this->successors = $this->predecessors = $this->present = array_fill(0, $this->n, []);
        foreach ($this->links as [$source, $target]) {
            $this->successors[$source][] = $target;
            $this->predecessors[$target][] = $source;
            $this->present[$source][$target] = true;
        }
    }

    public function intra(int $source, int $target): bool
    {
        return $this->pages[$source]['host'] === $this->pages[$target]['host'];
    }

    public function edges(bool $reverse = false): array
    {
        return array_map(fn($group) => array_map(fn($source) => [$source, 1], $group), $reverse ? $this->successors : $this->predecessors);
    }

    public function ids(array $nodes): array
    {
        return array_map(fn($node) => $this->pages[$node]['id'], $nodes);
    }

    public function describe(int $rank, int $node, string|int $value): string
    {
        $page = $this->pages[$node];
        return "$rank {$page['id']} $value {$page['host']} {$page['title']}";
    }

    public function dangling(): array
    {
        return indices($this->n, fn($node) => !$this->successors[$node]);
    }
}

function undirected(Graph $graph): array
{
    $adjacent = $neighbors = array_fill(0, $graph->n, []);
    foreach ($graph->links as [$source, $target]) $adjacent[$source][$target] = $adjacent[$target][$source] = true;
    $closed = $possible = $eligible = $edgeCount = 0;
    $localSum = 0.0;
    for ($node = 0; $node < $graph->n; $node++) {
        $neighbors[$node] = array_keys($adjacent[$node]);
        sort($neighbors[$node], SORT_NUMERIC);
        $degree = count($neighbors[$node]);
        $edgeCount += $degree;
        if ($degree < 2) continue;
        $triangles = 0;
        foreach ($neighbors[$node] as $position => $first) for ($j = $position + 1; $j < $degree; $j++) {
            if (isset($adjacent[$first][$neighbors[$node][$j]])) $triangles++;
        }
        $pairs = intdiv($degree * ($degree - 1), 2);
        $closed += $triangles;
        $possible += $pairs;
        $eligible++;
        $localSum += $triangles / $pairs;
    }
    $remaining = array_map('count', $neighbors);
    $removed = array_fill(0, $graph->n, false);
    $core = array_fill(0, $graph->n, 0);
    $level = 0;
    $left = $graph->n;
    while ($left > 0) {
        $candidate = -1;
        for ($node = 0; $node < $graph->n; $node++) if (!$removed[$node] && $remaining[$node] <= $level) {
            $candidate = $node;
            break;
        }
        if ($candidate < 0) {
            $level++;
            continue;
        }
        $removed[$candidate] = true;
        $core[$candidate] = $level;
        $left--;
        foreach ($neighbors[$candidate] as $neighbor) if (!$removed[$neighbor]) $remaining[$neighbor]--;
    }
    $labels = weak_components($neighbors);
    $sizes = array_count_values($labels);
    return ['neighbors' => $neighbors, 'edges' => intdiv($edgeCount, 2), 'closed' => $closed,
        'possible' => $possible, 'eligible' => $eligible, 'average' => $localSum / $eligible,
        'core' => $core, 'degeneracy' => max($core), 'weak_count' => count($sizes), 'weak_largest' => max($sizes)];
}

function component_table(Graph $graph): array
{
    $groups = strong_components($graph->successors);
    foreach ($groups as &$group) sort($group, SORT_NUMERIC);
    unset($group);
    usort($groups, fn($a, $b) => $a[0] <=> $b[0]);
    $count = count($groups);
    $labels = array_fill(0, $graph->n, 0);
    foreach ($groups as $label => $group) foreach ($group as $node) $labels[$node] = $label;
    $incoming = $outgoing = $pending = $depth = array_fill(0, $count, 0);
    $present = $successors = array_fill(0, $count, []);
    $edges = 0;
    foreach ($graph->links as [$source, $target]) {
        $a = $labels[$source];
        $b = $labels[$target];
        if ($a === $b) continue;
        $outgoing[$a]++;
        $incoming[$b]++;
        if (!isset($present[$a][$b])) {
            $present[$a][$b] = true;
            $successors[$a][] = $b;
            $pending[$b]++;
            $edges++;
        }
    }
    $ready = indices($count, fn($node) => $pending[$node] === 0);
    while ($ready) {
        $node = array_pop($ready);
        foreach ($successors[$node] as $target) {
            $depth[$target] = max($depth[$target], $depth[$node] + 1);
            if (--$pending[$target] === 0) $ready[] = $target;
        }
    }
    $core = $singletons = 0;
    foreach ($groups as $index => $group) {
        if (count($group) > count($groups[$core])) $core = $index;
        if (count($group) === 1) $singletons++;
    }
    return ['groups' => $groups, 'labels' => $labels, 'incoming' => $incoming, 'outgoing' => $outgoing,
        'edges' => $edges, 'depth' => max($depth), 'core' => $core, 'singletons' => $singletons];
}

function bowtie(Graph $graph, array $core): array
{
    $forward = reachable($graph->successors, $core);
    $backward = reachable($graph->predecessors, $core);
    $inCore = array_fill(0, $graph->n, false);
    foreach ($core as $node) $inCore[$node] = true;
    $regions = array_fill(0, $graph->n, 6);
    for ($node = 0; $node < $graph->n; $node++) {
        if ($inCore[$node]) $regions[$node] = 0;
        elseif ($backward[$node]) $regions[$node] = 1;
        elseif ($forward[$node]) $regions[$node] = 2;
    }
    $fromIn = reachable($graph->successors, indices($graph->n, fn($node) => $regions[$node] === 1));
    $toOut = reachable($graph->predecessors, indices($graph->n, fn($node) => $regions[$node] === 2));
    for ($node = 0; $node < $graph->n; $node++) if ($regions[$node] === 6) {
        if ($fromIn[$node] && $toOut[$node]) $regions[$node] = 3;
        elseif ($fromIn[$node]) $regions[$node] = 4;
        elseif ($toOut[$node]) $regions[$node] = 5;
    }
    return $regions;
}

function distance_stats(Graph $graph): array
{
    $stats = ['pairs' => 0, 'total' => 0, 'diameter' => 0, 'histogram' => array_fill(0, $graph->n, 0), 'harmonic' => array_fill(0, $graph->n, 0.0)];
    for ($source = 0; $source < $graph->n; $source++) {
        foreach (bfs_distances($graph->successors, [$source]) as $target => $steps) {
            if ($target === $source || $steps < 0) continue;
            $stats['pairs']++;
            $stats['total'] += $steps;
            $stats['histogram'][$steps]++;
            $stats['harmonic'][$target] += 1 / $steps;
            if ($steps > $stats['diameter']) [$stats['diameter'], $stats['source'], $stats['target']] = [$steps, $source, $target];
        }
    }
    $reached = 0;
    for ($steps = 1; $steps <= $stats['diameter']; $steps++) {
        $reached += $stats['histogram'][$steps];
        if (10 * $reached >= 9 * $stats['pairs']) {
            $stats['effective'] = $steps;
            break;
        }
    }
    return $stats;
}

function salsa(int $count, array $links): array
{
    $degree = $sizes = $mass = array_fill(0, $count, 0);
    $targets = $neighbors = array_fill(0, $count, []);
    foreach ($links as [$source, $target]) {
        $degree[$target]++;
        $targets[$source][] = $target;
    }
    foreach ($targets as $group) for ($i = 0; $i + 1 < count($group); $i++) {
        $neighbors[$group[$i]][] = $group[$i + 1];
        $neighbors[$group[$i + 1]][] = $group[$i];
    }
    $labels = weak_components($neighbors);
    $side = 0;
    foreach ($degree as $node => $value) if ($value > 0) {
        $side++;
        $sizes[$labels[$node]]++;
        $mass[$labels[$node]] += $value;
    }
    $scores = array_fill(0, $count, 0.0);
    foreach ($degree as $node => $value) if ($value > 0) $scores[$node] = ($sizes[$labels[$node]] * $value) / ($side * $mass[$labels[$node]]);
    return $scores;
}

class Analysis
{
    private array $pages, $records, $queries, $p, $index, $ignored, $undirected, $table, $regions, $distance;
    private array $trusted, $pr, $chei, $trust, $order, $rank, $cheiRank, $ratio, $trustDistance, $authority, $hub;
    private array $sweeps, $suspects, $suspectHosts, $demotedRank, $results, $hosts;
    private ?array $demoted = null;
    private int $removed = 0;
    private Graph $graph;

    public function __construct()
    {
        [$this->pages, $this->records, $this->queries, $this->p] = read_input();
        $this->index = $this->ignored = [];
        foreach ($this->pages as $node => $page) $this->index[$page['id']] = $node;
        $seen = $accepted = [];
        foreach ($this->records as $record) {
            $a = $this->index[$record['source']] ?? -1;
            $b = $this->index[$record['target']] ?? -1;
            $reason = null;
            if ($a < 0 || $b < 0) $reason = 'unknown';
            elseif ($a === $b) $reason = 'self';
            elseif (isset($seen[$a][$b])) $reason = 'duplicate';
            else {
                $seen[$a][$b] = true;
                $accepted[] = [$a, $b];
            }
            if ($reason !== null) $this->ignored[] = [$record, $reason];
        }
        $this->graph = new Graph($this->pages, $accepted);
        $this->undirected = undirected($this->graph);
        $this->table = component_table($this->graph);
        $this->regions = bowtie($this->graph, $this->table['groups'][$this->table['core']]);
        $this->distance = distance_stats($this->graph);
        $p = $this->p;
        $everyone = indices(count($this->pages));
        $this->trusted = array_map(fn($id) => $this->index[$id], $p['TRUSTED']);
        sort($this->trusted, SORT_NUMERIC);
        $this->pr = $this->power($this->graph->edges(), $everyone, $p['DAMPING']);
        $this->chei = $this->power($this->graph->edges(true), $everyone, $p['DAMPING']);
        $this->trust = $this->power($this->graph->edges(), $this->trusted, $p['DAMPING']);
        $this->order = rank_order($this->pr['values']);
        $this->rank = positions($this->order);
        $this->cheiRank = positions(rank_order($this->chei['values']));
        $this->ratio = array_map(fn($node) => $this->trust['values'][$node] / $this->pr['values'][$node], $everyone);
        $this->trustDistance = bfs_distances($this->graph->successors, $this->trusted);
        $inter = array_values(array_filter($this->graph->links, fn($edge) => !$this->graph->intra(...$edge)));
        [$this->authority, $this->hub] = hits($this->graph->n, $everyone, $inter, $p['HITS_ITERATIONS']);
        $this->sweeps = [];
        foreach ($p['DAMPING_SWEEP'] as $damping) {
            $trial = $this->power($this->graph->edges(), $everyone, $damping);
            $order = rank_order($trial['values']);
            $rank = positions($order);
            $overlap = $footrule = $shift = 0;
            foreach ($everyone as $node) {
                if ($rank[$node] <= $p['TOP_K'] && $this->rank[$node] <= $p['TOP_K']) $overlap++;
                $footrule += abs($rank[$node] - $this->rank[$node]);
                if (abs($rank[$node] - $this->rank[$node]) > abs($rank[$shift] - $this->rank[$shift])) $shift = $node;
            }
            $this->sweeps[] = ['damping' => $damping, 'run' => $trial, 'overlap' => $overlap, 'footrule' => $footrule,
                'shift' => $shift, 'shift_rank' => $rank[$shift], 'top' => array_slice($order, 0, $p['TOP_K']),
                'correlation' => kendall(array_map(fn($value) => scaled($value), $this->pr['values']), array_map(fn($value) => scaled($value), $trial['values']))];
        }
        $this->suspects = $this->suspectHosts = [];
        foreach (array_slice($this->order, 0, $p['SPAM_TOP']) as $node) if (scaled($this->ratio[$node], 4) / 10000 < $p['SPAM_THRESHOLD']) {
            $this->suspects[] = $node;
            $this->suspectHosts['#'.$this->pages[$node]['host']] = $this->pages[$node]['host'];
        }
        if ($this->suspects) {
            $kept = [];
            foreach ($this->graph->links as $edge) {
                if ($this->graph->intra(...$edge) && isset($this->suspectHosts['#'.$this->pages[$edge[0]]['host']])) $this->removed++;
                else $kept[] = $edge;
            }
            $graph = new Graph($this->pages, $kept);
            $this->demoted = $this->power($graph->edges(), $everyone, $p['DAMPING']);
            $this->demotedRank = positions(rank_order($this->demoted['values']));
        }
        $this->results = array_map(fn($query) => $this->query($query), $this->queries);
        $this->hosts = $this->hostGraph();
    }

    private function power(array $edges, array $teleport, float $damping): array
    {
        return power_iteration($edges, $teleport, $damping, $this->p['PAGERANK_ITERATIONS'], $this->p['TOLERANCE']);
    }

    private function query(array $query): array
    {
        $graph = $this->graph;
        $p = $this->p;
        $result = ['query' => $query, 'matches' => []];
        foreach ($this->order as $node) {
            $words = array_fill_keys($this->pages[$node]['words'], true);
            $matches = true;
            foreach ($query['words'] as $word) {
                if (str_starts_with($word, '-')) {
                    if (isset($words[substr($word, 1)])) $matches = false;
                } elseif (!isset($words[$word])) $matches = false;
            }
            if ($matches) $result['matches'][] = $node;
        }
        $root = array_slice($result['matches'], 0, $p['ROOT_LIMIT']);
        $base = array_fill(0, $graph->n, false);
        foreach ($root as $node) {
            $base[$node] = true;
            foreach (array_slice($graph->successors[$node], 0, $p['NEIGHBOR_LIMIT']) as $neighbor) $base[$neighbor] = true;
            foreach (array_slice($graph->predecessors[$node], 0, $p['NEIGHBOR_LIMIT']) as $neighbor) $base[$neighbor] = true;
        }
        $result['root_size'] = count($root);
        $result['base'] = indices($graph->n, fn($node) => $base[$node]);
        $result['links'] = [];
        $result['dropped'] = 0;
        foreach ($graph->links as $edge) if ($base[$edge[0]] && $base[$edge[1]]) {
            if ($graph->intra(...$edge)) $result['dropped']++;
            else $result['links'][] = $edge;
        }
        $seeds = array_map(fn($id) => $this->index[$id], $query['seeds']);
        sort($seeds, SORT_NUMERIC);
        $result['personalized'] = $this->power($graph->edges(), $seeds, $p['DAMPING']);
        $result['reach'] = count(array_filter(reachable($graph->successors, $seeds)));
        $result['seed_mass'] = total(array_map(fn($node) => $result['personalized']['values'][$node], $seeds));
        $result['personal_top'] = top_list($result['personalized']['values'], $p['TOP_K']);
        $result['global_overlap'] = count(array_filter($result['personal_top'], fn($node) => $this->rank[$node] <= $p['TOP_K']));
        if (!$result['links']) return $result;
        [$result['authority'], $result['hub']] = hits($graph->n, $result['base'], $result['links'], $p['HITS_ITERATIONS']);
        $result['salsa_authority'] = salsa($graph->n, $result['links']);
        $result['salsa_hub'] = salsa($graph->n, array_map(fn($edge) => [$edge[1], $edge[0]], $result['links']));
        $result['authority_top'] = top_list($result['authority'], $p['TOP_K']);
        $result['hub_top'] = top_list($result['hub'], $p['TOP_K']);
        $result['sa_top'] = top_list($result['salsa_authority'], $p['TOP_K']);
        $result['sh_top'] = top_list($result['salsa_hub'], $p['TOP_K']);
        $result['authority_overlap'] = count(array_intersect($result['authority_top'], $result['sa_top']));
        $result['hub_overlap'] = count(array_intersect($result['hub_top'], $result['sh_top']));
        $hosts = [];
        foreach ($result['authority_top'] as $node) $hosts['#'.$this->pages[$node]['host']] = true;
        $result['authority_hosts'] = count($hosts);
        $result['cited'] = $result['authority_top'][0];
        $result['citing'] = $result['hub_top'][0];
        $result['cocitation'] = $result['coupling'] = array_fill(0, $graph->n, 0);
        foreach ($graph->predecessors[$result['cited']] as $source) foreach ($graph->successors[$source] as $target) {
            if ($target !== $result['cited']) $result['cocitation'][$target]++;
        }
        foreach ($graph->successors[$result['citing']] as $target) foreach ($graph->predecessors[$target] as $source) {
            if ($source !== $result['citing']) $result['coupling'][$source]++;
        }
        $result['related'] = ranked_counts($result['cocitation'], $p['TOP_K']);
        $result['similar'] = ranked_counts($result['coupling'], $p['TOP_K']);
        return $result;
    }

    private function hostGraph(): array
    {
        $unique = [];
        foreach ($this->pages as $page) $unique['#'.$page['host']] = $page['host'];
        $names = array_values($unique);
        usort($names, 'strcmp');
        $index = [];
        foreach ($names as $position => $name) $index['#'.$name] = $position;
        $count = count($names);
        $host = ['names' => $names, 'members' => array_fill(0, $count, []),
            'weight' => array_fill(0, $count, array_fill(0, $count, 0)),
            'internal' => array_fill(0, $count, 0), 'outgoing' => array_fill(0, $count, 0),
            'incoming' => array_fill(0, $count, 0), 'edges' => [], 'reciprocal' => 0];
        foreach ($this->pages as $node => $page) $host['members'][$index['#'.$page['host']]][] = $node;
        foreach ($this->graph->links as [$source, $target]) {
            $a = $index['#'.$this->pages[$source]['host']];
            $b = $index['#'.$this->pages[$target]['host']];
            if ($a === $b) $host['internal'][$a]++;
            else {
                $host['weight'][$a][$b]++;
                $host['outgoing'][$a]++;
                $host['incoming'][$b]++;
            }
        }
        $adjacency = $inEdges = array_fill(0, $count, []);
        for ($a = 0; $a < $count; $a++) for ($b = 0; $b < $count; $b++) if ($host['weight'][$a][$b] > 0) {
            $host['edges'][] = [$a, $b];
            $adjacency[$a][] = $b;
            $inEdges[$b][] = [$a, $host['weight'][$a][$b]];
            if ($host['weight'][$b][$a] > 0) $host['reciprocal']++;
        }
        $groups = strong_components($adjacency);
        $host['component_count'] = count($groups);
        $host['largest'] = max(array_map('count', $groups));
        $host['run'] = $this->power($inEdges, indices($count), $this->p['DAMPING']);
        $host['rank'] = positions(rank_order($host['run']['values']));
        $heavy = $host['edges'];
        usort($heavy, fn($a, $b) => ($host['weight'][$b[0]][$b[1]] <=> $host['weight'][$a[0]][$a[1]]) ?: (($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1])));
        $host['heavy'] = array_slice($heavy, 0, $this->p['TOP_K']);
        return $host;
    }

    private function rankLines(array $nodes, array $values): array
    {
        $lines = [];
        foreach ($nodes as $position => $node) $lines[] = $this->graph->describe($position + 1, $node, fixed($values[$node]));
        return $lines;
    }

    private function representative(array $nodes): int
    {
        $best = $nodes[0];
        foreach ($nodes as $node) if ($this->rank[$node] < $this->rank[$best]) $best = $node;
        return $best;
    }

    public function graphStats(): array
    {
        $graph = $this->graph;
        $u = $this->undirected;
        $t = $this->table;
        $d = $this->distance;
        $reasons = ['unknown' => 0, 'self' => 0, 'duplicate' => 0];
        foreach ($this->ignored as [$record, $reason]) $reasons[$reason]++;
        $intra = $reciprocal = 0;
        foreach ($graph->links as [$source, $target]) {
            if ($graph->intra($source, $target)) $intra++;
            if (isset($graph->present[$target][$source])) $reciprocal++;
        }
        $inDegree = array_map('count', $graph->predecessors);
        $outDegree = array_map('count', $graph->successors);
        $maxIn = max($inDegree);
        $maxOut = max($outDegree);
        $lines = ["pages {$graph->n}", 'hosts '.count($this->hosts['names']), 'link_rows '.count($this->records),
            'links '.count($graph->links), 'ignored_unknown '.$reasons['unknown'], 'ignored_self '.$reasons['self'], 'ignored_duplicate '.$reasons['duplicate']];
        foreach ($this->ignored as [$record, $reason]) $lines[] = "ignored line {$record['line']} {$record['source']},{$record['target']} $reason";
        array_push($lines, "intra_host_links $intra", 'inter_host_links '.(count($graph->links) - $intra),
            'mean_degree '.fixed(count($graph->links) / $graph->n, 4), 'reciprocity '.fraction($reciprocal, count($graph->links)));
        $dangling = $graph->dangling();
        $noIn = indices($graph->n, fn($node) => $inDegree[$node] === 0);
        array_push($lines, joined('dangling '.count($dangling), $graph->ids($dangling)),
            joined('no_in_links '.count($noIn), $graph->ids($noIn)),
            joined("max_in_degree $maxIn pages", $graph->ids(indices($graph->n, fn($node) => $inDegree[$node] === $maxIn))),
            joined("max_out_degree $maxOut pages", $graph->ids(indices($graph->n, fn($node) => $outDegree[$node] === $maxOut))));
        array_push($lines, '', 'in_degree_distribution', ...distribution($inDegree));
        array_push($lines, '', 'out_degree_distribution', ...distribution($outDegree));
        array_push($lines, '', 'undirected_links '.$u['edges'], 'transitivity '.fraction($u['closed'], $u['possible']),
            'average_clustering '.fixed($u['average'], 4).' pages '.$u['eligible'],
            'degeneracy '.$u['degeneracy'].' pages '.count(array_filter($u['core'], fn($value) => $value === $u['degeneracy'])), 'core_distribution', ...distribution($u['core']));
        array_push($lines, '', 'strong_components '.count($t['groups']).' largest '.count($t['groups'][$t['core']]).' singletons '.$t['singletons'].' condensation_links '.$t['edges'],
            'weak_components '.$u['weak_count'].' largest '.$u['weak_largest'], 'condensation_depth '.$t['depth']);
        foreach ($t['groups'] as $label => $group) if (count($group) >= 2) {
            $lines[] = 'scc '.($label + 1).' size '.count($group).' min '.$this->pages[$group[0]]['id'].' incoming '.$t['incoming'][$label].' outgoing '.$t['outgoing'][$label]
                .' pagerank '.fixed(total(array_map(fn($node) => $this->pr['values'][$node], $group))).($t['outgoing'][$label] === 0 ? ' sink' : '');
        }
        array_push($lines, '', 'bowtie core_scc '.($t['core'] + 1));
        foreach (REGIONS as $region => $name) {
            $members = indices($graph->n, fn($node) => $this->regions[$node] === $region);
            $text = $name.' '.count($members).' pagerank '.fixed(total(array_map(fn($node) => $this->pr['values'][$node], $members)));
            if ($members) $text .= ' top '.$this->pages[$this->representative($members)]['id'];
            if (count($members) >= 1 && count($members) <= 10) $text = joined($text.' pages', $graph->ids($members));
            $lines[] = $text;
        }
        $counts = array_fill(0, 7, array_fill(0, 7, 0));
        foreach ($graph->links as [$source, $target]) $counts[$this->regions[$source]][$this->regions[$target]]++;
        $lines[] = 'region_links';
        foreach (REGIONS as $a => $nameA) foreach (REGIONS as $b => $nameB) if ($counts[$a][$b] > 0) $lines[] = "$nameA $nameB {$counts[$a][$b]}";
        array_push($lines, '', 'distances', 'reachable_pairs '.$d['pairs'], 'average '.fraction($d['total'], $d['pairs']),
            'diameter '.$d['diameter'].' from '.$this->pages[$d['source']]['id'].' to '.$this->pages[$d['target']]['id'], 'effective_diameter '.$d['effective']);
        for ($steps = 1; $steps <= $d['diameter']; $steps++) $lines[] = "$steps {$d['histogram'][$steps]}";
        return $lines;
    }

    public function pagerankCSV(): array
    {
        $lines = ['id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance'];
        foreach ($this->pages as $node => $page) $lines[] = implode(',', [$page['id'], count($this->graph->predecessors[$node]), count($this->graph->successors[$node]),
            $this->table['labels'][$node] + 1, REGIONS[$this->regions[$node]], $this->undirected['core'][$node], fixed($this->distance['harmonic'][$node]),
            fixed($this->pr['values'][$node]), $this->rank[$node], fixed($this->chei['values'][$node]), $this->cheiRank[$node], fixed($this->authority[$node]),
            fixed($this->hub[$node]), fixed($this->trust['values'][$node]), fixed($this->ratio[$node], 4), $this->trustDistance[$node]]);
        return $lines;
    }

    public function rankings(): array
    {
        $graph = $this->graph;
        $p = $this->p;
        $sections = [];
        $scores = [$this->pr['values'], $this->chei['values'], $this->authority, $this->hub, $this->trust['values'], $this->distance['harmonic']];
        $names = ['pagerank', 'cheirank', 'authority', 'hub', 'trustrank', 'harmonic'];
        foreach ($names as $index => $name) {
            $nodes = top_list($scores[$index], $p['TOP_K']);
            $lines = [$name.' top '.$p['TOP_K'], ...$this->rankLines($nodes, $scores[$index])];
            if ($index === 0) {
                $lines[] = 'dangling_mass '.fixed(total(array_map(fn($node) => $this->pr['values'][$node], $graph->dangling())));
                foreach ($nodes as $node) {
                    $contribution = fn($source) => ($p['DAMPING'] * $this->pr['values'][$source]) / count($graph->successors[$source]);
                    $contributors = $graph->predecessors[$node];
                    usort($contributors, fn($a, $b) => (scaled($contribution($b)) <=> scaled($contribution($a))) ?: ($a <=> $b));
                    $parts = ['contributors', $this->pages[$node]['id']];
                    foreach (array_slice($contributors, 0, 3) as $source) array_push($parts, $this->pages[$source]['id'], fixed($contribution($source)));
                    $lines[] = implode(' ', $parts);
                }
            }
            $sections[] = $lines;
        }
        $series = [array_map('count', $graph->predecessors)];
        foreach ($scores as $values) $series[] = array_map(fn($value) => scaled($value), $values);
        $correlations = ['correlation'];
        for ($a = 0; $a < 7; $a++) for ($b = $a + 1; $b < 7; $b++) $correlations[] = QUANTITIES[$a].' '.QUANTITIES[$b].' '.kendall($series[$a], $series[$b]);
        $sections[] = $correlations;
        $sweeps = ['damping_sweep'];
        foreach ($this->sweeps as $sweep) {
            $sweeps[] = 'damping '.fixed($sweep['damping'], 4).' overlap '.$sweep['overlap'].' footrule '.$sweep['footrule'].' kendall '.$sweep['correlation']
                .' largest_shift '.$this->pages[$sweep['shift']]['id'].' '.$this->rank[$sweep['shift']].' '.$sweep['shift_rank'];
            $sweeps[] = joined('top', $graph->ids($sweep['top']));
        }
        $sections[] = $sweeps;
        $spam = ['spam top '.$p['SPAM_TOP'].' threshold '.fixed($p['SPAM_THRESHOLD'], 4)];
        foreach ($this->suspects as $node) $spam[] = 'suspect '.$this->pages[$node]['id'].' rank '.$this->rank[$node].' pagerank '.fixed($this->pr['values'][$node])
            .' trustrank '.fixed($this->trust['values'][$node]).' trust_ratio '.fixed($this->ratio[$node], 4).' trust_distance '.$this->trustDistance[$node]
            .' kcore '.$this->undirected['core'][$node].' '.$this->pages[$node]['host'];
        array_push($spam, 'count '.count($this->suspects), 'trust_by_distance');
        $distances = array_values(array_unique(array_filter($this->trustDistance, fn($value) => $value >= 0)));
        sort($distances, SORT_NUMERIC);
        if (in_array(-1, $this->trustDistance, true)) $distances[] = -1;
        foreach ($distances as $distance) {
            $members = indices($graph->n, fn($node) => $this->trustDistance[$node] === $distance);
            $spam[] = ($distance === -1 ? 'unreachable' : $distance).' pages '.count($members)
                .' trustrank '.fixed(total(array_map(fn($node) => $this->trust['values'][$node], $members)))
                .' pagerank '.fixed(total(array_map(fn($node) => $this->pr['values'][$node], $members)));
        }
        $sections[] = $spam;
        $demotion = ['demotion none'];
        if ($this->demoted !== null) {
            $hosts = array_values($this->suspectHosts);
            usort($hosts, 'strcmp');
            $demotion = ['demotion hosts '.implode(' ', $hosts).' removed_links '.$this->removed];
            foreach (top_list($this->demoted['values'], $p['TOP_K']) as $position => $node) $demotion[] = $graph->describe($position + 1, $node, fixed($this->demoted['values'][$node]).' was '.$this->rank[$node]);
            foreach ($this->suspects as $node) $demotion[] = 'suspect '.$this->pages[$node]['id'].' before '.$this->rank[$node].' after '.$this->demotedRank[$node];
        }
        $sections[] = $demotion;
        $host = $this->hosts;
        $hostLines = ['host_graph hosts '.count($host['names']).' links '.count($host['edges']).' reciprocal '.$host['reciprocal']
            .' strong_components '.$host['component_count'].' largest '.$host['largest'], 'host_links top '.$p['TOP_K']];
        foreach ($host['heavy'] as [$source, $target]) $hostLines[] = $host['names'][$source].' '.$host['names'][$target].' '.$host['weight'][$source][$target];
        $sections[] = $hostLines;
        return blocks($sections);
    }

    public function convergence(): array
    {
        $p = $this->p;
        $damping = fixed($p['DAMPING'], 4);
        $lines = ['iterations '.$p['PAGERANK_ITERATIONS'].' tolerance '.fixed($p['TOLERANCE'], 10)];
        $add = function (string $heading, array $run) use (&$lines): void {
            array_push($lines, '', $heading);
            for ($step = 10; $step <= count($run['changes']); $step += 10) $lines[] = "iteration $step l1 ".fixed($run['changes'][$step - 1], 10);
            $lines[] = 'converged_at '.($run['converged'] ?? 'none');
        };
        $add("pagerank damping $damping", $this->pr);
        $add("cheirank damping $damping", $this->chei);
        $add("trustrank damping $damping seeds ".count($p['TRUSTED']), $this->trust);
        foreach ($this->sweeps as $sweep) $add('sweep damping '.fixed($sweep['damping'], 4), $sweep['run']);
        if ($this->demoted !== null) $add("demoted damping $damping", $this->demoted);
        foreach ($this->results as $result) $add('personalized query '.$result['query']['number']." damping $damping", $result['personalized']);
        $add("host_pagerank damping $damping hosts ".count($this->hosts['names']), $this->hosts['run']);
        return $lines;
    }

    private function queryLines(array $result): array
    {
        $query = $result['query'];
        $graph = $this->graph;
        $lines = ['query '.$query['number'].' words '.implode(' ', $query['words']).' seeds '.implode(' ', $query['seeds']),
            'matched '.count($result['matches']).' root '.$result['root_size'].' base '.count($result['base']).' links '.count($result['links']).' dropped_intra_host '.$result['dropped'], 'results'];
        array_push($lines, ...$this->rankLines(array_slice($result['matches'], 0, $this->p['TOP_K']), $this->pr['values']));
        $lines[] = 'personalized reach '.$result['reach'].' seed_mass '.fixed($result['seed_mass']);
        array_push($lines, ...$this->rankLines($result['personal_top'], $result['personalized']['values']));
        $lines[] = 'overlap_with_global '.$result['global_overlap'];
        if (!$result['links']) {
            $lines[] = 'hits none';
            return $lines;
        }
        foreach ([['hits authorities', 'authority_top', 'authority'], ['hits hubs', 'hub_top', 'hub'],
            ['salsa authorities', 'sa_top', 'salsa_authority'], ['salsa hubs', 'sh_top', 'salsa_hub']] as [$heading, $nodes, $values]) {
            $lines[] = $heading;
            array_push($lines, ...$this->rankLines($result[$nodes], $result[$values]));
        }
        array_push($lines, 'hits_salsa_overlap authorities '.$result['authority_overlap'].' hubs '.$result['hub_overlap'].' authority_hosts '.$result['authority_hosts'],
            'related_to '.$this->pages[$result['cited']]['id'].' citing '.count($graph->predecessors[$result['cited']]));
        foreach ($result['related'] as $position => $node) $lines[] = $graph->describe($position + 1, $node, $result['cocitation'][$node]);
        $lines[] = 'coupled_to '.$this->pages[$result['citing']]['id'].' cited '.count($graph->successors[$result['citing']]);
        foreach ($result['similar'] as $position => $node) $lines[] = $graph->describe($position + 1, $node, $result['coupling'][$node]);
        return $lines;
    }

    public function queriesFile(): array
    {
        return blocks(array_map(fn($result) => $this->queryLines($result), $this->results));
    }

    public function hostsCSV(): array
    {
        $host = $this->hosts;
        $lines = ['host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank'];
        foreach ($host['names'] as $index => $name) {
            $members = $host['members'][$index];
            $size = count($members);
            $core = count(array_filter($members, fn($node) => $this->regions[$node] === 0));
            $dangling = count(array_filter($members, fn($node) => !$this->graph->successors[$node]));
            $density = $size >= 2 ? $host['internal'][$index] / ($size * ($size - 1)) : 0.0;
            $lines[] = implode(',', [$name, $size, $core, $host['internal'][$index], fixed($density, 4), $host['outgoing'][$index], $host['incoming'][$index], $dangling,
                fixed(total(array_map(fn($node) => $this->pr['values'][$node], $members))), $this->pages[$this->representative($members)]['id'], fixed($host['run']['values'][$index]), $host['rank'][$index]]);
        }
        return $lines;
    }
}

$analysis = new Analysis();
if (!is_dir('output')) mkdir('output', 0777, true);
write_lines('graph_stats.txt', $analysis->graphStats());
write_lines('pagerank.csv', $analysis->pagerankCSV());
write_lines('rankings.txt', $analysis->rankings());
write_lines('convergence.txt', $analysis->convergence());
write_lines('queries.txt', $analysis->queriesFile());
write_lines('hosts.csv', $analysis->hostsCSV());
