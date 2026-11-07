<?php

require_once __DIR__ . '/config_io.php';
require_once __DIR__ . '/cache.php';
require_once __DIR__ . '/protocol.php';
require_once __DIR__ . '/bus.php';
require_once __DIR__ . '/stats.php';

const DISTANCE_LABELS = ['1', '2-4', '5-16', '17-64', '65-256', '257+'];
const LATENCY_LABELS = ['1', '2-9', '10-29', '30-99', '100-299', '300+'];

function category(int $value, array $limits): int
{
    foreach ($limits as $index => $limit) if ($value <= $limit) return $index;
    return count($limits);
}

function validateTrace(array $lines, array $config): array
{
    $events = $rejected = [];
    $byCore = array_fill(0, $config['cores'], []);
    $previousCycle = 0;
    foreach ($lines as $index => $line) {
        $fields = explode(' ', $line);
        $count = count($fields);
        $reason = null;
        if (($count !== 3 && $count !== 4) || in_array('', $fields, true)) $reason = 'fields';
        elseif (!decimalInteger($fields[0]) || strlen($fields[0]) > 7) $reason = 'cycle';
        elseif (!decimalInteger($fields[1]) || (int)$fields[1] >= $config['cores']) $reason = 'core';
        elseif (!in_array($fields[2], ['R', 'W', 'FENCE'], true) ||
            ($fields[2] === 'FENCE' ? $count !== 3 : $count !== 4)) $reason = 'op';
        elseif ($fields[2] !== 'FENCE' && (!hexadecimal($fields[3]) ||
            hexdec($fields[3]) % 4 !== 0 || hexdec($fields[3]) > 0x7fffffff)) $reason = 'address';
        elseif ((int)$fields[0] < $previousCycle) $reason = 'order';
        if ($reason !== null) {
            $rejected[] = ['line' => $index + 1, 'reason' => $reason];
            continue;
        }
        $event = ['number' => count($events) + 1, 'cycle' => (int)$fields[0],
            'core' => (int)$fields[1], 'operation' => $fields[2]];
        if ($event['operation'] !== 'FENCE') {
            $event['address'] = (int)hexdec($fields[3]);
            $event['block'] = intdiv($event['address'], $config['line']);
            $event['word'] = intdiv($event['address'] % $config['line'], 4);
        }
        $previousCycle = $event['cycle'];
        $events[] = $event;
        $byCore[$event['core']][] = $event;
    }
    return ['events' => $events, 'rejected' => $rejected, 'byCore' => $byCore, 'lineCount' => count($lines)];
}

function later(array $a, array $b): bool
{
    return $a[0] > $b[0] || ($a[0] === $b[0] && $a[1] < $b[1]);
}

function heapPush(array &$heap, array $value): void
{
    $heap[] = $value;
    $index = count($heap) - 1;
    while ($index > 0) {
        $parent = intdiv($index - 1, 2);
        if (!later($heap[$index], $heap[$parent])) break;
        [$heap[$index], $heap[$parent]] = [$heap[$parent], $heap[$index]];
        $index = $parent;
    }
}

function heapPop(array &$heap): array
{
    $result = $heap[0];
    $last = array_pop($heap);
    if (!$heap) return $result;
    $heap[0] = $last;
    $index = 0;
    while (true) {
        $left = 2 * $index + 1;
        $right = $left + 1;
        $best = $index;
        if ($left < count($heap) && later($heap[$left], $heap[$best])) $best = $left;
        if ($right < count($heap) && later($heap[$right], $heap[$best])) $best = $right;
        if ($best === $index) break;
        [$heap[$index], $heap[$best]] = [$heap[$best], $heap[$index]];
        $index = $best;
    }
    return $result;
}

function optimalMisses(array $accesses, int $capacity): int
{
    $future = $next = [];
    for ($index = count($accesses) - 1; $index >= 0; $index--) {
        $block = $accesses[$index]['block'];
        $next[$index] = $future[$block] ?? count($accesses);
        $future[$block] = $index;
    }
    $resident = $heap = [];
    $misses = 0;
    foreach ($accesses as $index => $access) {
        $block = $access['block'];
        if (!isset($resident[$block])) {
            $misses++;
            if (count($resident) === $capacity) {
                do {
                    $victim = heapPop($heap);
                } while (!isset($resident[$victim[1]]) || $resident[$victim[1]] !== $victim[0]);
                unset($resident[$victim[1]]);
            }
        }
        $resident[$block] = $next[$index];
        heapPush($heap, [$next[$index], $block]);
    }
    return $misses;
}

function treeSum(array $tree, int $position): int
{
    $sum = 0;
    for ($i = $position; $i > 0; $i -= $i & -$i) $sum += $tree[$i];
    return $sum;
}

function treeAdd(array &$tree, int $position, int $value): void
{
    for ($i = $position; $i < count($tree); $i += $i & -$i) $tree[$i] += $value;
}

function reuseAnalysis(array &$byCore, int $capacity): array
{
    $result = [];
    $capacities = [intdiv($capacity, 4), intdiv($capacity, 2), $capacity, 2 * $capacity, 4 * $capacity];
    foreach ($byCore as &$events) {
        $accessCount = 0;
        foreach ($events as $event) if ($event['operation'] !== 'FENCE') $accessCount++;
        $tree = array_fill(0, $accessCount + 1, 0);
        $previous = $accesses = [];
        $histogram = array_fill(0, 6, 0);
        $misses = array_fill(0, 5, 0);
        $cold = 0;
        $index = 0;
        foreach ($events as &$event) {
            if ($event['operation'] === 'FENCE') continue;
            $block = $event['block'];
            if (!isset($previous[$block])) {
                $event['distance'] = null;
                $cold++;
            } else {
                $old = $previous[$block];
                $event['distance'] = treeSum($tree, $index) - treeSum($tree, $old - 1);
                $histogram[category($event['distance'], [1, 4, 16, 64, 256])]++;
                treeAdd($tree, $old, -1);
            }
            foreach ($capacities as $i => $limit) {
                if ($event['distance'] === null || $event['distance'] > $limit) $misses[$i]++;
            }
            treeAdd($tree, $index + 1, 1);
            $previous[$block] = $index + 1;
            $accesses[] = $event;
            $index++;
        }
        unset($event);
        $result[] = ['accesses' => $accessCount, 'lines' => count($previous), 'histogram' => $histogram,
            'cold' => $cold, 'capacities' => $capacities, 'misses' => $misses, 'opt' => optimalMisses($accesses, $capacity)];
    }
    unset($events);
    return $result;
}

function staticSharing(array $events): array
{
    $lines = [];
    foreach ($events as $event) {
        if ($event['operation'] === 'FENCE') continue;
        $block = $event['block'];
        $word = $event['word'];
        $core = $event['core'];
        if (!isset($lines[$block])) $lines[$block] = ['cores' => [], 'writers' => [], 'words' => [], 'reads' => 0, 'writes' => 0];
        $lines[$block]['cores'][$core] = true;
        if (!isset($lines[$block]['words'][$word])) $lines[$block]['words'][$word] = ['readers' => [], 'writers' => []];
        if ($event['operation'] === 'W') {
            $lines[$block]['writes']++;
            $lines[$block]['writers'][$core] = true;
            $lines[$block]['words'][$word]['writers'][$core] = true;
        } else {
            $lines[$block]['reads']++;
            $lines[$block]['words'][$word]['readers'][$core] = true;
        }
    }
    foreach ($lines as &$line) {
        $line['shared'] = count($line['cores']) >= 2 && count($line['writers']) > 0;
        $line['true'] = false;
        foreach ($line['words'] as $word) {
            if ($word['writers'] && count($word['readers'] + $word['writers']) >= 2) $line['true'] = true;
        }
    }
    unset($line);
    return $lines;
}

class Simulation
{
    public array $config;
    public array $scenario;
    public bool $primary;
    public array $l1 = [];
    public Cache $l2;
    public Bus $bus;
    public array $cores = [];
    public array $total;
    public array $l2Stats;
    public int $snoopHits = 0;
    public array $fanout;
    public array $histogram;
    public array $lineData = [];
    public array $communication;
    public array $accesses = [];
    public array $watchLines = [];
    private array $byCore;
    private array $ready;
    private array $writeComplete;
    private array $invalidations;
    private array $wordData = [];

    public function __construct(array $config, array $scenario, array $byCore)
    {
        $this->config = $config;
        $this->scenario = $scenario;
        $this->primary = $scenario['name'] === $config['primary'];
        $this->byCore = $byCore;
        for ($core = 0; $core < $config['cores']; $core++) {
            $this->l1[] = new Cache($config['l1'], $scenario['l1Policy']);
            $this->cores[] = newCounters();
        }
        $this->l2 = new Cache($config['l2'], $scenario['l2Policy']);
        $this->bus = new Bus($config['latencies'][3]);
        $this->ready = $this->writeComplete = array_fill(0, $config['cores'], 0);
        $this->invalidations = array_fill(0, $config['cores'], []);
        $this->fanout = array_fill(0, $config['cores'], 0);
        $this->histogram = array_fill(0, 6, 0);
        $this->communication = array_fill(0, $config['cores'], array_fill(0, $config['cores'], 0));
        $this->l2Stats = array_fill_keys(['lookups', 'hits', 'misses', 'flushes', 'writebacks', 'evictions', 'dirtyEvictions'], 0);
    }

    private function ensureLine(int $block): void
    {
        if (!isset($this->lineData[$block])) {
            $this->lineData[$block] = ['bus' => array_fill_keys(BUS_TYPES, 0), 'cores' => [],
                'misses' => 0, 'coherence' => 0, 'invalidations' => 0, 'trueSharing' => 0,
                'falseSharing' => 0, 'handoffs' => 0, 'lastWriter' => null];
        }
    }

    private function assign(int $request, int $core, string $type, int $block): int
    {
        $index = $this->bus->assign($request, $core, $type, $block);
        $this->cores[$core]['bus'][$type]++;
        if ($this->primary) {
            $this->ensureLine($block);
            $this->lineData[$block]['bus'][$type]++;
            $this->lineData[$block]['cores'][$core] = true;
        }
        return $index;
    }

    private function watchedState(int $block): array
    {
        $states = [];
        foreach ($this->l1 as $cache) $states[] = $cache->state($block);
        $states[] = $this->l2->state($block);
        return $states;
    }

    private function sharingEvent(array $event): void
    {
        if (!$this->primary) return;
        $block = $event['block'];
        $core = $event['core'];
        $key = $block . ':' . $event['word'];
        if (!isset($this->wordData[$key])) $this->wordData[$key] = ['writer' => null, 'readers' => []];
        if ($event['operation'] === 'W') {
            $last = $this->lineData[$block]['lastWriter'];
            if ($last !== null && $last !== $core) $this->lineData[$block]['handoffs']++;
            $this->lineData[$block]['lastWriter'] = $core;
            $this->wordData[$key] = ['writer' => $core, 'readers' => []];
        } else {
            $writer = $this->wordData[$key]['writer'];
            if ($writer !== null && $writer !== $core && !isset($this->wordData[$key]['readers'][$core])) {
                $this->communication[$writer][$core]++;
                $this->wordData[$key]['readers'][$core] = true;
            }
        }
    }

    private function transact(array $event, string $type, int $request): array
    {
        $core = $event['core'];
        $block = $event['block'];
        $index = $this->assign($request, $core, $type, $block);
        $tx = &$this->bus->transactions[$index];
        $flushed = false;
        for ($other = 0; $other < $this->config['cores']; $other++) {
            if ($other === $core) continue;
            $old = $this->l1[$other]->state($block);
            if ($old === 'I') continue;
            [$new, $supply, $flush] = snoopTransition($this->scenario['protocol'], $old, $type);
            $tx['snoops'][] = 'c' . $other . ':' . $old . '>' . $new;
            if ($new === 'I') {
                $this->l1[$other]->remove($block);
                $this->cores[$core]['invalidationsSent']++;
                $this->cores[$other]['invalidationsReceived']++;
                $this->invalidations[$other][$block] = [$event['word'] => true];
                $tx['invalidations']++;
            } else {
                $this->l1[$other]->setState($block, $new);
            }
            if ($supply) {
                $tx['supplier'] = $other;
                $this->cores[$other]['supplied']++;
            }
            if ($flush) $flushed = true;
        }
        $this->snoopHits += count($tx['snoops']);
        if ($this->primary) $this->lineData[$block]['invalidations'] += $tx['invalidations'];
        if ($type !== 'BusRd') $this->fanout[$tx['invalidations']]++;
        if ($type !== 'BusUpgr') {
            $this->l2Stats['lookups']++;
            if ($this->l2->state($block) !== 'I') {
                $tx['l2'] = 'hit';
                $this->l2Stats['hits']++;
                $this->l2->touch($block);
            } else {
                $tx['l2'] = 'miss';
                $this->l2Stats['misses']++;
                $evicted = $this->l2->fill($block, 'C');
                if ($evicted !== null) {
                    $this->l2Stats['evictions']++;
                    $eviction = ['block' => $evicted['block'], 'copies' => [], 'dirty' => $evicted['state'] === 'D'];
                    for ($other = 0; $other < $this->config['cores']; $other++) {
                        $old = $this->l1[$other]->state($evicted['block']);
                        if ($old === 'I') continue;
                        $eviction['copies'][] = 'c' . $other . ':' . $old;
                        if (dirtyState($old)) $eviction['dirty'] = true;
                        $this->l1[$other]->remove($evicted['block']);
                        $this->cores[$other]['backInvalidations']++;
                    }
                    if ($eviction['dirty']) $this->l2Stats['dirtyEvictions']++;
                    $tx['eviction'] = $eviction;
                }
            }
            if ($flushed || $type === 'BusWr') $this->l2->setState($block, 'D');
        }
        if ($flushed) $this->l2Stats['flushes']++;
        $completion = $tx['start'] + $this->config['latencies'][3];
        if ($type === 'BusUpgr') {
            $service = 'upgrade';
        } elseif ($type !== 'BusWr' && $tx['supplier'] !== null) {
            $service = 'cache';
        } else {
            $completion += $this->config['latencies'][1];
            if ($tx['l2'] === 'miss') $completion += $this->config['latencies'][2];
            $service = $type === 'BusWr' ? 'through' : ($tx['l2'] === 'hit' ? 'l2' : 'memory');
        }
        return [$completion, $service];
    }

    private function access(array $event, int $issue): void
    {
        $core = $event['core'];
        $block = $event['block'];
        $word = $event['word'];
        $operation = $event['operation'];
        $cache = $this->l1[$core];
        $counter = &$this->cores[$core];
        $before = [];
        if ($this->primary) {
            $this->ensureLine($block);
            foreach ($this->config['watches'] as $watched) $before[] = $this->watchedState($watched);
        }
        $old = $cache->state($block);
        [$type, $new] = requestTransition($this->scenario['protocol'], $old, $operation);
        $hit = $old !== 'I';
        $counter['accesses']++;
        $counter[$operation === 'R' ? 'reads' : 'writes']++;
        $classification = null;
        if ($hit) {
            $counter['hits']++;
            $cache->touch($block);
        } else {
            $counter['misses']++;
            if ($this->primary) $this->lineData[$block]['misses']++;
            if ($event['distance'] === null) {
                $classification = 'compulsory';
            } elseif (isset($this->invalidations[$core][$block])) {
                $classification = 'coherence';
                $sharing = isset($this->invalidations[$core][$block][$word]) ? 'trueSharing' : 'falseSharing';
                $counter[$sharing]++;
                if ($this->primary) {
                    $this->lineData[$block]['coherence']++;
                    $this->lineData[$block][$sharing]++;
                }
            } else {
                $classification = $event['distance'] > $this->config['capacity'] ? 'capacity' : 'conflict';
            }
            $counter[$classification]++;
        }
        if ($operation === 'W') {
            for ($other = 0; $other < $this->config['cores']; $other++) {
                if ($other !== $core && isset($this->invalidations[$other][$block])) {
                    $this->invalidations[$other][$block][$word] = true;
                }
            }
        }
        $this->sharingEvent($event);
        if ($new === 'ES') {
            $new = 'E';
            foreach ($this->l1 as $other => $otherCache) {
                if ($other !== $core && $otherCache->state($block) !== 'I') {
                    $new = 'S';
                    break;
                }
            }
        }
        $completion = $issue + $this->config['latencies'][0];
        $service = 'l1';
        if ($type !== null) [$completion, $service] = $this->transact($event, $type, $completion);
        if ($old !== 'I') {
            $cache->setState($block, $new);
        } elseif ($new !== 'I') {
            $evicted = $cache->fill($block, $new);
            unset($this->invalidations[$core][$block]);
            if ($evicted !== null && dirtyState($evicted['state'])) {
                $this->assign($this->bus->free, $core, 'WB', $evicted['block']);
                $this->l2Stats['writebacks']++;
                $this->l2->touch($evicted['block']);
                $this->l2->setState($evicted['block'], 'D');
            }
        }
        $latency = $completion - $issue;
        $counter['latency'] += $latency;
        $counter[$operation === 'R' ? 'readLatency' : 'writeLatency'] += $latency;
        $counter['service'][$service]++;
        $counter['finish'] = max($counter['finish'], $completion);
        $this->histogram[category($latency, [1, 9, 29, 99, 299])]++;
        if ($operation === 'R') {
            $this->ready[$core] = $completion;
        } else {
            $this->ready[$core] = $issue + $this->config['latencies'][0];
            $this->writeComplete[$core] = max($this->writeComplete[$core], $completion);
        }
        if ($this->primary) {
            $this->accesses[] = $event + compact('issue', 'latency', 'service', 'hit', 'classification');
            foreach ($this->config['watches'] as $index => $watched) {
                $after = $this->watchedState($watched);
                if ($block !== $watched && $after === $before[$index]) continue;
                $states = [];
                for ($i = 0; $i < $this->config['cores']; $i++) $states[] = 'c' . $i . ':' . $after[$i];
                $this->watchLines[] = $event['number'] . ' ' . $issue . ' c' . $core . ' ' . $operation . ' ' .
                    hexAddress($event['address']) . ' line ' . hexAddress($watched * $this->config['line']) . ' ' .
                    implode(' ', $states) . ' L2:' . $after[$this->config['cores']];
            }
        }
        unset($counter);
    }

    public function run(): void
    {
        $positions = array_fill(0, $this->config['cores'], 0);
        while (true) {
            $selected = null;
            $issue = null;
            for ($core = 0; $core < $this->config['cores']; $core++) {
                if ($positions[$core] >= count($this->byCore[$core])) continue;
                $candidate = max($this->byCore[$core][$positions[$core]]['cycle'], $this->ready[$core]);
                if ($issue === null || $candidate < $issue) {
                    $selected = $core;
                    $issue = $candidate;
                }
            }
            if ($selected === null) break;
            $event = $this->byCore[$selected][$positions[$selected]++];
            if ($event['operation'] === 'FENCE') {
                $completion = max($issue, $this->writeComplete[$selected]);
                $this->cores[$selected]['fences']++;
                $this->cores[$selected]['fenceStall'] += $completion - $issue;
                $this->cores[$selected]['finish'] = max($this->cores[$selected]['finish'], $completion);
                $this->ready[$selected] = $completion;
            } else {
                $this->access($event, $issue);
            }
        }
        $this->total = totalCounters($this->cores);
    }
}

function scenarioReport(Simulation $sim): array
{
    $config = $sim->config;
    $scenario = $sim->scenario;
    $total = $sim->total;
    $l2 = $sim->l2Stats;
    $count = count($sim->bus->transactions);
    $lines = ['scenario ' . $scenario['name'] . ' ' . $scenario['protocol'] . ' ' .
        $scenario['l1Policy'] . ' ' . $scenario['l2Policy']];
    foreach ($sim->cores as $core => $counters) array_push($lines, ...sixLines('c' . $core, $counters));
    array_push($lines, ...sixLines('total', $total));
    $lines[] = 'l2 lookups ' . $l2['lookups'] . ' hits ' . $l2['hits'] . ' misses ' . $l2['misses'] .
        ' flushes ' . $l2['flushes'] . ' writebacks ' . $l2['writebacks'] . ' evictions ' . $l2['evictions'] .
        ' dirty_evictions ' . $l2['dirtyEvictions'];
    $lines[] = 'bus transactions ' . $count . ' busy ' . $sim->bus->busy . ' wait ' . $sim->bus->wait .
        ' utilization ' . decimalNotation(100 * $sim->bus->busy, $total['finish']);
    $data = $config['line'] * ($total['bus']['BusRd'] + $total['bus']['BusRdX'] + $total['bus']['WB']) + 4 * $total['bus']['BusWr'];
    $memory = $config['line'] * ($l2['misses'] + $l2['dirtyEvictions']);
    $lines[] = 'traffic command_bytes ' . (8 * $count) . ' data_bytes ' . $data . ' memory_bytes ' . $memory;
    $labels = range(0, $config['cores'] - 1);
    $lines[] = 'snoops probes ' . (($config['cores'] - 1) * ($count - $total['bus']['WB'])) . ' hits ' .
        $sim->snoopHits . ' fanout ' . rangeCounts($labels, $sim->fanout);
    $lines[] = 'latencies reads ' . $total['readLatency'] . ' writes ' . $total['writeLatency'] .
        ' histogram ' . rangeCounts(LATENCY_LABELS, $sim->histogram);
    return $lines;
}

function hotReport(Simulation $sim): array
{
    $hot = [];
    foreach ($sim->lineData as $block => $data) {
        $count = array_sum($data['bus']);
        if ($count > 0) $hot[] = ['block' => $block, 'data' => $data, 'count' => $count];
    }
    usort($hot, fn($a, $b) => ($b['count'] <=> $a['count']) ?: ($a['block'] <=> $b['block']));
    $lines = ['hot ' . $sim->config['primary']];
    foreach (array_slice($hot, 0, $sim->config['top']) as $index => $row) {
        $data = $row['data'];
        $types = [];
        foreach (BUS_TYPES as $type) $types[] = $type . ' ' . $data['bus'][$type];
        $lines[] = ($index + 1) . ' ' . hexAddress($row['block'] * $sim->config['line']) . ' transactions ' .
            $row['count'] . ' ' . implode(' ', $types) . ' misses ' . $data['misses'] . ' coherence ' . $data['coherence'] .
            ' invalidations ' . $data['invalidations'] . ' cores ' . coreString($data['cores']);
    }
    return $lines;
}

function intervalReport(Simulation $sim): array
{
    $config = $sim->config;
    $width = $config['interval'];
    $count = intdiv($sim->total['finish'], $width) + 1;
    $intervals = array_fill(0, $count, ['accesses' => array_fill(0, $config['cores'], 0), 'misses' => 0, 'transactions' => 0, 'busy' => 0]);
    foreach ($sim->accesses as $access) {
        $index = intdiv($access['issue'], $width);
        $intervals[$index]['accesses'][$access['core']]++;
        if (!$access['hit']) $intervals[$index]['misses']++;
    }
    foreach ($sim->bus->transactions as $tx) {
        $first = intdiv($tx['start'], $width);
        $last = intdiv($tx['start'] + $config['latencies'][3] - 1, $width);
        if ($first < $count) $intervals[$first]['transactions']++;
        for ($index = $first; $index <= $last && $index < $count; $index++) {
            $intervals[$index]['busy'] += min($tx['start'] + $config['latencies'][3], ($index + 1) * $width) -
                max($tx['start'], $index * $width);
        }
    }
    $lines = ['intervals ' . $config['primary'] . ' ' . $width];
    foreach ($intervals as $index => $interval) {
        $lines[] = $index . ' ' . ($index * $width) . '-' . (($index + 1) * $width - 1) . ' accesses ' .
            implode(' ', $interval['accesses']) . ' misses ' . $interval['misses'] . ' transactions ' . $interval['transactions'] .
            ' busy ' . $interval['busy'] . ' utilization ' . decimalNotation(100 * $interval['busy'], $width);
    }
    return $lines;
}

function regionIndex(array $config, int $address): int
{
    foreach ($config['regions'] as $index => $region) {
        if ($region['first'] <= $address && $address <= $region['last']) return $index;
    }
    return count($config['regions']);
}

function regionReport(Simulation $sim): array
{
    $config = $sim->config;
    $regions = $config['regions'];
    $regions[] = ['name' => 'other'];
    $keys = ['accesses', 'reads', 'writes', 'hits', 'compulsory', 'capacity', 'conflict', 'coherence', 'transactions', 'latency'];
    foreach ($regions as &$region) foreach ($keys as $key) $region[$key] = 0;
    unset($region);
    foreach ($sim->accesses as $access) {
        $index = regionIndex($config, $access['address']);
        $regions[$index]['accesses']++;
        $regions[$index][$access['operation'] === 'R' ? 'reads' : 'writes']++;
        if ($access['hit']) $regions[$index]['hits']++;
        else $regions[$index][$access['classification']]++;
        $regions[$index]['latency'] += $access['latency'];
    }
    foreach ($sim->bus->transactions as $tx) $regions[regionIndex($config, $tx['block'] * $config['line'])]['transactions']++;
    $lines = ['regions ' . $config['primary']];
    foreach ($regions as $region) {
        $parts = [$region['name']];
        foreach ($keys as $key) {
            $parts[] = $key;
            $parts[] = $region[$key];
        }
        $amat = $region['accesses'] === 0 ? '-' : fraction($region['latency'], $region['accesses']) . ' ' .
            decimalNotation($region['latency'], $region['accesses']);
        $lines[] = implode(' ', $parts) . ' amat ' . $amat;
    }
    return $lines;
}

function statisticsReport(array $config, array $trace, array $reuse, array $reports, Simulation $primary): array
{
    $first = ['trace lines ' . $trace['lineCount'] . ' accepted ' . count($trace['events']) . ' rejected ' . count($trace['rejected'])];
    foreach ($trace['rejected'] as $rejected) $first[] = 'reject line ' . $rejected['line'] . ' ' . $rejected['reason'];
    $first[] = 'geometry cores ' . $config['cores'] . ' line ' . $config['line'] . ' l1 ' . $config['l1']['size'] . ' ' .
        $config['l1']['ways'] . ' sets ' . $config['l1']['sets'] . ' l2 ' . $config['l2']['size'] . ' ' .
        $config['l2']['ways'] . ' sets ' . $config['l2']['sets'];
    $first[] = 'latency l1 ' . $config['latencies'][0] . ' l2 ' . $config['latencies'][1] . ' memory ' .
        $config['latencies'][2] . ' bus ' . $config['latencies'][3];
    $parts = [$first];
    $reuseLines = [];
    foreach ($reuse as $core => $data) {
        $reuseLines[] = 'reuse c' . $core . ' accesses ' . $data['accesses'] . ' lines ' . $data['lines'] .
            ' distance ' . rangeCounts(DISTANCE_LABELS, $data['histogram']) . ' cold ' . $data['cold'];
        $pairs = [];
        foreach ($data['capacities'] as $index => $capacity) $pairs[] = $capacity . ':' . $data['misses'][$index];
        $reuseLines[] = 'mrc c' . $core . ' lru ' . implode(' ', $pairs) . ' opt ' . $config['capacity'] . ':' . $data['opt'];
    }
    $parts[] = $reuseLines;
    foreach ($reports as $report) $parts[] = $report['lines'];
    $ranking = $reports;
    usort($ranking, fn($a, $b) => ($a['total']['finish'] <=> $b['total']['finish']) ?:
        ($a['transactions'] <=> $b['transactions']) ?: ($a['scenario']['order'] <=> $b['scenario']['order']));
    $rankLines = ['ranking'];
    foreach ($ranking as $index => $report) {
        $total = $report['total'];
        $rankLines[] = ($index + 1) . ' ' . $report['scenario']['name'] . ' finish ' . $total['finish'] .
            ' transactions ' . $report['transactions'] . ' amat ' . fraction($total['latency'], $total['accesses']) . ' ' .
            decimalNotation($total['latency'], $total['accesses']);
    }
    $parts[] = $rankLines;
    $parts[] = hotReport($primary);
    $parts[] = intervalReport($primary);
    $accesses = $primary->accesses;
    usort($accesses, fn($a, $b) => ($b['latency'] <=> $a['latency']) ?: ($a['number'] <=> $b['number']));
    $slow = ['slowest ' . $config['primary']];
    foreach (array_slice($accesses, 0, $config['top']) as $index => $access) {
        $slow[] = ($index + 1) . ' event ' . $access['number'] . ' cycle ' . $access['issue'] . ' c' . $access['core'] .
            ' ' . $access['operation'] . ' ' . hexAddress($access['address']) . ' latency ' . $access['latency'] . ' service ' . $access['service'];
    }
    $parts[] = $slow;
    $parts[] = regionReport($primary);
    $lines = [];
    foreach ($parts as $index => $part) {
        if ($index) $lines[] = '';
        array_push($lines, ...$part);
    }
    return $lines;
}

function sharingReport(array $config, array $sharing, Simulation $primary): array
{
    $blocks = [];
    foreach ($sharing as $block => $line) if ($line['shared']) $blocks[] = $block;
    sort($blocks, SORT_NUMERIC);
    $trueLines = $trueMisses = $falseMisses = 0;
    $lines = [];
    foreach ($blocks as $block) {
        $line = $sharing[$block];
        $dynamic = $primary->lineData[$block];
        if ($line['true']) $trueLines++;
        $trueMisses += $dynamic['trueSharing'];
        $falseMisses += $dynamic['falseSharing'];
        $words = $line['words'];
        ksort($words, SORT_NUMERIC);
        $parts = [];
        foreach ($words as $number => $word) {
            $parts[] = 'w' . $number . '=' . coreString($word['readers']) . '/' . coreString($word['writers']);
        }
        $lines[] = hexAddress($block * $config['line']) . ' ' . ($line['true'] ? 'true' : 'false') .
            ' cores ' . coreString($line['cores']) . ' writers ' . coreString($line['writers']) .
            ' reads ' . $line['reads'] . ' writes ' . $line['writes'] . ' handoffs ' . $dynamic['handoffs'] .
            ' coherence ' . ($dynamic['trueSharing'] + $dynamic['falseSharing']) . ' true ' . $dynamic['trueSharing'] .
            ' false ' . $dynamic['falseSharing'] . ' words ' . implode(' ', $parts);
    }
    $lines[] = 'lines ' . count($blocks) . ' true_lines ' . $trueLines . ' false_lines ' . (count($blocks) - $trueLines) .
        ' coherence ' . ($trueMisses + $falseMisses) . ' true ' . $trueMisses . ' false ' . $falseMisses;
    $lines[] = 'communication';
    foreach ($primary->communication as $core => $counts) $lines[] = 'c' . $core . ' ' . implode(' ', $counts);
    return $lines;
}

function cacheRows(Cache $cache, string $label, int $lineSize, array &$lines): array
{
    $held = [];
    foreach ($cache->entries as $set => $entries) {
        $ways = [];
        foreach ($entries as $entry) {
            if ($entry === null) {
                $ways[] = '-';
            } else {
                $ways[] = hexAddress($entry['block'] * $lineSize) . ':' . $entry['state'];
                $held[] = $entry;
            }
        }
        $lines[] = $label . ' ' . $set . ' ' . implode(' ', $ways) . ' ' . strtolower($cache->policy) . ' ' .
            $cache->order($set) . ' fills ' . $cache->fills[$set] . ' evictions ' . $cache->evictions[$set];
    }
    return $held;
}

function finalStateReport(Simulation $sim): array
{
    $lines = [];
    foreach ($sim->l1 as $core => $cache) {
        $held = cacheRows($cache, 'c' . $core, $sim->config['line'], $lines);
        $counts = array_fill_keys(['M', 'O', 'E', 'S', 'V'], 0);
        foreach ($held as $entry) $counts[$entry['state']]++;
        $parts = [];
        foreach ($counts as $state => $count) $parts[] = $state . ' ' . $count;
        $lines[] = 'c' . $core . ' lines ' . count($held) . ' ' . implode(' ', $parts);
    }
    $held = cacheRows($sim->l2, 'L2', $sim->config['line'], $lines);
    $dirty = $inL1 = 0;
    foreach ($held as $entry) {
        if ($entry['state'] === 'D') $dirty++;
        foreach ($sim->l1 as $cache) {
            if ($cache->state($entry['block']) !== 'I') {
                $inL1++;
                break;
            }
        }
    }
    $lines[] = 'L2 lines ' . count($held) . ' dirty ' . $dirty . ' clean ' . (count($held) - $dirty) . ' in_l1 ' . $inL1;
    return $lines;
}

function main(): void
{
    $input = readInput();
    $config = $input['config'];
    $trace = validateTrace($input['trace'], $config);
    $reuse = reuseAnalysis($trace['byCore'], $config['capacity']);
    $sharing = staticSharing($trace['events']);
    $reports = [];
    $primary = null;
    foreach ($config['scenarios'] as $scenario) {
        $sim = new Simulation($config, $scenario, $trace['byCore']);
        $sim->run();
        $reports[] = ['scenario' => $scenario, 'total' => $sim->total,
            'transactions' => count($sim->bus->transactions), 'lines' => scenarioReport($sim)];
        if ($sim->primary) $primary = $sim;
    }
    writeLines('stats.txt', statisticsReport($config, $trace, $reuse, $reports, $primary));
    writeLines('bus_log.txt', $primary->bus->lines($config['line']));
    writeLines('watch.txt', $primary->watchLines);
    writeLines('sharing.txt', sharingReport($config, $sharing, $primary));
    writeLines('final_state.txt', finalStateReport($primary));
}

main();
