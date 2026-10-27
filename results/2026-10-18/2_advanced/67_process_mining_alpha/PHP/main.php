<?php

require_once __DIR__ . '/eventlog.php';
require_once __DIR__ . '/dfg.php';
require_once __DIR__ . '/alpha_miner.php';
require_once __DIR__ . '/heuristic_miner.php';
require_once __DIR__ . '/conformance.php';
require_once __DIR__ . '/report.php';

function fields(...$values) { return implode(' ', $values); }
function increment(&$map, $key, $amount = 1) { $map[$key] = ($map[$key] ?? 0) + $amount; }
function sum_values($values) { $total = 0; foreach ($values as $value) $total += $value; return $total; }
function unique_names($names) { $names = array_values(array_unique($names, SORT_STRING)); sort($names, SORT_STRING); return $names; }
function pair_order($a, $b) { return strcmp($a['from'], $b['from']) ?: strcmp($a['to'], $b['to']); }
function append_lines(&$target, $source) { foreach ($source as $line) $target[] = $line; }

function parameters($values)
{
    $getRatio = fn($key) => array_map('intval', explode('/', $values[$key]));
    return ['filter' => (int) $values['filter_min_follows'], 'sla' => (int) $values['sla_minutes'],
        'observations' => (int) $values['positive_observations'], 'dependency' => $getRatio('dependency_threshold'),
        'relative' => $getRatio('relative_to_best'), 'loop1' => $getRatio('loop1_threshold'), 'loop2' => $getRatio('loop2_threshold'), 'and' => $getRatio('and_threshold')];
}

function validate_rows($rows)
{
    $events = []; $errors = []; $adopted = [];
    foreach ($rows as $row) {
        $time = timestamp_minutes($row['timestamp']);
        $key = implode("\0", [$row['caseId'], $row['activity'], $row['timestamp']]);
        if ($time === null) $errors[] = fields('ERROR line', $row['line'] . ':', 'bad timestamp', $row['timestamp']);
        elseif (isset($adopted[$key])) $errors[] = fields('ERROR line', $row['line'] . ':', 'duplicate event', $row['caseId'], $row['activity'], $row['timestamp']);
        else { $adopted[$key] = true; $row['time'] = $time; $events[] = $row; }
    }
    return compact('events', 'errors');
}

function log_summary($rows, $events, $errors, $cases, $activities, $resources, $net, $settings)
{
    $lines = $errors;
    $chronological = $events;
    usort($chronological, fn($a, $b) => ($a['time'] <=> $b['time']) ?: ($a['line'] <=> $b['line']));
    $lines[] = fields('LOG rows', count($rows), 'adopted', count($events), 'rejected', count($errors), 'cases', count($cases),
        'activities', count($activities), 'resources', count($resources), 'first', $chronological[0]['timestamp'], 'last', $chronological[count($chronological) - 1]['timestamp']);
    $statistics = [];
    foreach ($activities as $name) $statistics[$name] = ['events' => 0, 'cases' => 0, 'start' => 0, 'end' => 0, 'rework' => 0, 'wait' => 0, 'waits' => 0, 'resources' => []];
    $weekdays = array_fill(0, 7, ['events' => 0, 'starts' => 0, 'ends' => 0]);
    $dayCounts = []; $late = 0;
    foreach ($cases as $item) {
        $frequencies = [];
        foreach ($item['events'] as $i => $event) {
            $activity = $event['activity'];
            $statistics[$activity]['events']++; $statistics[$activity]['resources'][$event['resource']] = true;
            increment($frequencies, $activity);
            $weekdays[(intdiv($event['time'], 1440) + 3) % 7]['events']++;
            if ($i > 0) { $statistics[$activity]['wait'] += $event['time'] - $item['events'][$i - 1]['time']; $statistics[$activity]['waits']++; }
        }
        foreach ($frequencies as $activity => $frequency) { $statistics[$activity]['cases']++; if ($frequency >= 2) $statistics[$activity]['rework']++; }
        $statistics[$item['trace'][0]]['start']++;
        $statistics[$item['trace'][count($item['trace']) - 1]]['end']++;
        $weekdays[(intdiv($item['events'][0]['time'], 1440) + 3) % 7]['starts']++;
        $weekdays[(intdiv($item['events'][count($item['events']) - 1]['time'], 1440) + 3) % 7]['ends']++;
        increment($dayCounts, intdiv($item['duration'], 1440));
        if ($item['duration'] > $settings['sla']) $late++;
    }
    foreach ($activities as $activity) {
        $value = $statistics[$activity];
        $lines[] = fields('ACTIVITY', $activity, 'events', $value['events'], 'cases', $value['cases'], 'start', $value['start'], 'end', $value['end'],
            'rework', $value['rework'], 'wait', $value['waits'] === 0 ? '-' : fraction($value['wait'], $value['waits']),
            'resources', count($value['resources']), 'model', isset($net->inputs[$activity]) ? 'yes' : 'no');
    }
    $lengths = []; $durations = [];
    foreach ($cases as $item) { $lengths[] = count($item['events']); $durations[] = $item['duration']; }
    foreach (['LENGTH' => $lengths, 'DURATION' => $durations] as $name => $values) $lines[] = fields($name, 'min', min($values), 'max', max($values),
        'mean', fraction(sum_values($values), count($values)), 'median', fraction(median($values)));
    for ($day = 0; $day <= max(array_keys($dayCounts)); $day++) {
        $count = $dayCounts[$day] ?? 0;
        $lines[] = fields('DAYS', $day, 'cases', $count, 'share', percentage($count, count($cases)));
    }
    $lines[] = fields('SLA limit', $settings['sla'], 'late', $late, 'share', percentage($late, count($cases)));
    foreach (['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as $i => $name) $lines[] = fields('WEEKDAY', $name, 'events', $weekdays[$i]['events'], 'starts', $weekdays[$i]['starts'], 'ends', $weekdays[$i]['ends']);
    return $lines;
}

function group_variants(&$cases, $follows, $settings)
{
    $groups = [];
    foreach ($cases as $index => $item) {
        $key = implode(',', $item['trace']);
        if (!isset($groups[$key])) $groups[$key] = ['trace' => $item['trace'], 'indices' => []];
        $groups[$key]['indices'][] = $index;
    }
    $variants = array_values($groups);
    usort($variants, fn($a, $b) => (count($b['indices']) <=> count($a['indices'])) ?: compare_sequences($a['trace'], $b['trace']));
    foreach ($variants as $i => &$variant) {
        $variant['number'] = $i + 1; $variant['keep'] = true;
        foreach ($variant['trace'] as $j => $activity) if ($j > 0 && follows_count($follows, $variant['trace'][$j - 1], $activity) < $settings['filter']) $variant['keep'] = false;
        foreach ($variant['indices'] as $index) $cases[$index]['variant'] = $i + 1;
    }
    unset($variant);
    return $variants;
}

function variant_report($variants, $cases, $eventCount, $settings, $referenceReplay)
{
    $lines = []; $keptVariants = 0; $keptCases = 0; $keptEvents = 0;
    foreach ($variants as $variant) {
        $count = count($variant['indices']); $first = $cases[$variant['indices'][0]]; $durations = []; $late = 0;
        foreach ($variant['indices'] as $index) { $duration = $cases[$index]['duration']; $durations[] = $duration; if ($duration > $settings['sla']) $late++; }
        $lines[] = fields('VARIANT', $variant['number'], 'count', $count, 'share', percentage($count, count($cases)), 'length', count($variant['trace']),
            'first', $first['id'], 'duration', fraction(sum_values($durations), $count), 'late', $late, 'fitness', fraction(fitness($referenceReplay['cases'][$first['id']])),
            $variant['keep'] ? 'KEEP' : 'DROP', implode(',', $variant['trace']));
        if ($variant['keep']) { $keptVariants++; $keptCases += $count; $keptEvents += $count * count($variant['trace']); }
    }
    $lines[] = fields('FILTER min_follows', $settings['filter'], 'variants', $keptVariants, 'of', count($variants), 'cases', $keptCases, 'of', count($cases), 'events', $keptEvents, 'of', $eventCount);
    return $lines;
}

function directly_follows_report($cases, $activities, $follows)
{
    $starts = []; $ends = []; $edges = [];
    foreach ($cases as $item) {
        increment($starts, $item['trace'][0]);
        $end = $item['trace'][count($item['trace']) - 1]; $ends[$end][] = $item['duration'];
        for ($i = 1; $i < count($item['events']); $i++) {
            $first = $item['events'][$i - 1]; $second = $item['events'][$i]; $key = pair_key($first['activity'], $second['activity']);
            if (!isset($edges[$key])) $edges[$key] = ['from' => $first['activity'], 'to' => $second['activity'], 'count' => 0, 'cases' => [], 'waits' => []];
            $edges[$key]['count']++; $edges[$key]['cases'][$item['id']] = true; $edges[$key]['waits'][] = $second['time'] - $first['time'];
        }
    }
    $lines = []; $sortedStarts = [];
    foreach ($starts as $activity => $count) $sortedStarts[] = ['name' => $activity, 'count' => $count];
    usort($sortedStarts, fn($a, $b) => ($b['count'] <=> $a['count']) ?: strcmp($a['name'], $b['name']));
    foreach ($sortedStarts as $item) $lines[] = fields('START', $item['name'], 'count', $item['count']);
    $sortedEnds = [];
    foreach ($ends as $activity => $values) $sortedEnds[] = ['name' => $activity, 'values' => $values];
    usort($sortedEnds, fn($a, $b) => (count($b['values']) <=> count($a['values'])) ?: strcmp($a['name'], $b['name']));
    foreach ($sortedEnds as $item) $lines[] = fields('END', $item['name'], 'count', count($item['values']), 'duration', fraction(sum_values($item['values']), count($item['values'])));
    $sortedEdges = array_values($edges);
    usort($sortedEdges, fn($a, $b) => ($b['count'] <=> $a['count']) ?: pair_order($a, $b));
    foreach ($sortedEdges as $edge) $lines[] = fields('EDGE', $edge['from'], $edge['to'], 'count', $edge['count'], 'cases', count($edge['cases']),
        'mean', fraction(sum_values($edge['waits']), count($edge['waits'])), 'min', min($edge['waits']), 'max', max($edge['waits']));
    return array_merge($lines, footprint($activities, fn($a, $b) => basic_relation($follows, $a, $b)));
}

function discover_alpha($log, $activities, $relation)
{
    $candidates = []; $known = [];
    $add = function ($pair) use (&$candidates, &$known) {
        $key = implode(',', $pair['A']) . '|' . implode(',', $pair['B']);
        if (!isset($known[$key])) { $known[$key] = true; $pair['maximal'] = true; $candidates[] = $pair; }
    };
    $causal = 0;
    foreach ($activities as $first) foreach ($activities as $second) {
        if ($relation($first, $second) !== '->') continue;
        $causal++;
        if ($relation($first, $first) === '#' && $relation($second, $second) === '#') $add(['A' => [$first], 'B' => [$second]]);
    }
    for ($i = 0; $i < count($candidates); $i++) {
        $pair = $candidates[$i];
        foreach ($activities as $activity) foreach (['A', 'B'] as $side) {
            $extended = extend_pair($pair, $activity, $side, $relation);
            if ($extended !== null) { $candidates[$i]['maximal'] = false; $add($extended); }
        }
    }
    $pairs = [];
    foreach ($candidates as $pair) if ($pair['maximal']) $pairs[] = $pair;
    usort($pairs, 'compare_pairs');
    $starts = []; $ends = [];
    foreach ($log as $entry) { $starts[] = $entry['trace'][0]; $ends[] = $entry['trace'][count($entry['trace']) - 1]; }
    $starts = unique_names($starts); $ends = unique_names($ends);
    $places = ['start'];
    foreach ($pairs as $i => $pair) $places[] = 'p' . ($i + 1);
    $places[] = 'end';
    $arcs = [];
    foreach ($starts as $activity) $arcs[] = ['start', $activity];
    foreach ($ends as $activity) $arcs[] = [$activity, 'end'];
    foreach ($pairs as $i => $pair) {
        foreach ($pair['A'] as $activity) $arcs[] = [$activity, $places[$i + 1]];
        foreach ($pair['B'] as $activity) $arcs[] = [$places[$i + 1], $activity];
    }
    return ['activities' => $activities, 'relation' => $relation, 'causal' => $causal, 'candidates' => count($candidates), 'pairs' => $pairs,
        'starts' => $starts, 'ends' => $ends, 'net' => new PetriNet($places, $activities, $arcs, 'start', 'end')];
}

function net_lines($discovery)
{
    $net = $discovery['net']; $lines = [fields('PLACE start -', list_names($discovery['starts']))];
    foreach ($discovery['pairs'] as $i => $pair) $lines[] = fields('PLACE', 'p' . ($i + 1), list_names($pair['A']), list_names($pair['B']));
    $lines[] = fields('PLACE end', list_names($discovery['ends']), '-');
    foreach ($net->transitions as $transition) {
        $inputs = []; $outputs = [];
        foreach ($net->inputs[$transition] as $i) $inputs[] = $net->places[$i];
        foreach ($net->outputs[$transition] as $i) $outputs[] = $net->places[$i];
        $lines[] = fields('TRANSITION', $transition, 'in', list_names($inputs), 'out', list_names($outputs));
    }
    $lines[] = fields('NET places', count($net->places), 'transitions', count($net->transitions), 'arcs', count($net->arcs));
    return $lines;
}

function alpha_mining($variants)
{
    $filtered = []; $all = [];
    foreach ($variants as $variant) if ($variant['keep']) {
        $filtered[] = ['trace' => $variant['trace'], 'weight' => count($variant['indices'])];
        foreach ($variant['trace'] as $activity) $all[] = $activity;
    }
    $activities = unique_names($all); $follows = count_follows($filtered); $loops = [];
    foreach ($activities as $activity) if (follows_count($follows, $activity, $activity) > 0) $loops[] = $activity;
    $alpha = discover_alpha($filtered, $activities, fn($a, $b) => basic_relation($follows, $a, $b));
    $reduced = [];
    foreach ($filtered as $entry) {
        $trace = [];
        foreach ($entry['trace'] as $activity) if (!in_array($activity, $loops, true)) $trace[] = $activity;
        $reduced[] = ['trace' => $trace, 'weight' => $entry['weight']];
    }
    $reducedActivities = [];
    foreach ($activities as $activity) if (!in_array($activity, $loops, true)) $reducedActivities[] = $activity;
    $triangles = triangle_counts($reduced);
    $plus = discover_alpha($reduced, $reducedActivities, alpha_plus_relation(count_follows($reduced), $triangles));
    $arcs = $plus['net']->arcs; $loopLines = [];
    foreach ($loops as $activity) {
        $before = []; $after = [];
        foreach ($reducedActivities as $other) {
            if (follows_count($follows, $other, $activity) > 0) $before[] = $other;
            if (follows_count($follows, $activity, $other) > 0) $after[] = $other;
        }
        $index = -1;
        foreach ($plus['pairs'] as $i => $pair) if (compare_sequences($pair['A'], $before) === 0 && compare_sequences($pair['B'], $after) === 0) { $index = $i; break; }
        $place = $index < 0 ? '-' : 'p' . ($index + 1);
        if ($index >= 0) { $arcs[] = [$place, $activity]; $arcs[] = [$activity, $place]; }
        $loopLines[] = fields('LOOP', $activity, 'before', list_names($before), 'after', list_names($after), 'place', $place);
    }
    $plus['net'] = new PetriNet($plus['net']->places, $activities, $arcs, 'start', 'end');
    $caseCount = 0; foreach ($filtered as $entry) $caseCount += $entry['weight'];
    $lines = [fields('LOG variants', count($filtered), 'cases', $caseCount, 'activities', list_names($activities)), 'LOOPS ' . list_names($loops), 'MINER alpha'];
    append_lines($lines, footprint($alpha['activities'], $alpha['relation']));
    $lines[] = fields('PAIRS causal', $alpha['causal'], 'candidates', $alpha['candidates'], 'maximal', count($alpha['pairs']));
    append_lines($lines, net_lines($alpha));
    $lines[] = 'MINER alpha_plus';
    foreach ($reducedActivities as $first) foreach ($reducedActivities as $second) {
        $count = follows_count($triangles, $first, $second);
        if ($count > 0) $lines[] = fields('TRIANGLE', $first, $second, 'count', $count);
    }
    append_lines($lines, footprint($plus['activities'], $plus['relation']));
    $lines[] = fields('PAIRS causal', $plus['causal'], 'candidates', $plus['candidates'], 'maximal', count($plus['pairs']));
    append_lines($lines, $loopLines);
    append_lines($lines, net_lines($plus));
    return ['alpha' => $alpha['net'], 'plus' => $plus['net'], 'lines' => $lines];
}

function heuristic_report($log, $activities, $follows, $settings)
{
    $lines = []; $triangles = triangle_counts($log); $loops1 = []; $loops2 = []; $edges = []; $loopPairs = 0;
    foreach ($activities as $activity) {
        $frequency = follows_count($follows, $activity, $activity);
        if ($frequency === 0) continue;
        $measure = loop_measure($frequency);
        $accepted = $frequency >= $settings['observations'] && compare_fractions($measure, $settings['loop1']) >= 0;
        $lines[] = fields('L1', $activity, 'count', $frequency, 'measure', fraction($measure), $accepted ? 'ACCEPT' : 'REJECT');
        if ($accepted) { $loops1[$activity] = true; $edges[pair_key($activity, $activity)] = true; }
    }
    for ($i = 0; $i < count($activities); $i++) for ($j = $i + 1; $j < count($activities); $j++) {
        $first = $activities[$i]; $second = $activities[$j];
        if (isset($loops1[$first]) || isset($loops1[$second])) continue;
        $frequency = follows_count($triangles, $first, $second) + follows_count($triangles, $second, $first);
        if ($frequency === 0) continue;
        $measure = loop_measure($frequency);
        $accepted = $frequency >= $settings['observations'] && compare_fractions($measure, $settings['loop2']) >= 0;
        $lines[] = fields('L2', $first, $second, 'count', $frequency, 'measure', fraction($measure), $accepted ? 'ACCEPT' : 'REJECT');
        if ($accepted) { $loops2[pair_key($first, $second)] = true; $loops2[pair_key($second, $first)] = true; $loopPairs++; }
    }
    $dependencies = []; $bestOut = []; $bestIn = [];
    foreach ($activities as $first) foreach ($activities as $second) {
        $frequency = follows_count($follows, $first, $second);
        if ($first === $second || $frequency === 0) continue;
        $measure = dependency($follows, $first, $second);
        $dependencies[] = compact('first', 'second', 'frequency', 'measure');
        if (!isset($bestOut[$first]) || compare_fractions($measure, $bestOut[$first]) > 0) $bestOut[$first] = $measure;
        if (!isset($bestIn[$second]) || compare_fractions($measure, $bestIn[$second]) > 0) $bestIn[$second] = $measure;
    }
    foreach ($dependencies as $item) {
        $first = $item['first']; $second = $item['second']; $frequency = $item['frequency']; $measure = $item['measure'];
        $verdict = 'ACCEPT';
        if (isset($loops2[pair_key($first, $second)])) $verdict = 'LOOP2';
        elseif ($frequency < $settings['observations']) $verdict = 'REJECT_COUNT';
        elseif (compare_fractions($measure, $settings['dependency']) < 0) $verdict = 'REJECT_MEASURE';
        elseif (compare_fractions(subtract_fractions($bestOut[$first], $measure), $settings['relative']) > 0 &&
            compare_fractions(subtract_fractions($bestIn[$second], $measure), $settings['relative']) > 0) $verdict = 'REJECT_BEST';
        if ($verdict === 'ACCEPT' || $verdict === 'LOOP2') $edges[pair_key($first, $second)] = true;
        $lines[] = fields('DEP', $first, $second, 'count', $frequency, 'reverse', follows_count($follows, $second, $first), 'measure', fraction($measure), $verdict);
    }
    $nodes = [];
    foreach ($activities as $activity) {
        $inputs = []; $outputs = [];
        foreach ($activities as $other) {
            if (isset($edges[pair_key($other, $activity)])) $inputs[] = $other;
            if (isset($edges[pair_key($activity, $other)])) $outputs[] = $other;
        }
        $nodes[] = compact('activity', 'inputs', 'outputs');
        $lines[] = fields('NODE', $activity, 'in', list_names($inputs), 'out', list_names($outputs));
    }
    foreach ($nodes as $node) foreach ([true, false] as $split) {
        $neighbors = [];
        foreach (($split ? $node['outputs'] : $node['inputs']) as $other) if ($other !== $node['activity']) $neighbors[] = $other;
        for ($i = 0; $i < count($neighbors); $i++) for ($j = $i + 1; $j < count($neighbors); $j++) {
            $measure = routing_measure($follows, $node['activity'], $neighbors[$i], $neighbors[$j], $split);
            $lines[] = fields($split ? 'SPLIT' : 'JOIN', $node['activity'], $neighbors[$i], $neighbors[$j], 'measure', fraction($measure),
                compare_fractions($measure, $settings['and']) >= 0 ? 'AND' : 'XOR');
        }
    }
    $lines[] = fields('GRAPH activities', count($activities), 'edges', count($edges), 'loops1', count($loops1), 'loops2', $loopPairs);
    return $lines;
}

function explore($net)
{
    $initial = $net->marking(); $states = [$initial]; $stateIds = [implode(',', $initial) => 0]; $reverseEdges = [[]];
    $finalKey = implode(',', $net->marking(true)); $dead = array_fill_keys($net->transitions, true); $follows = [];
    $edges = 0; $unsafe = 0; $deadlocks = 0;
    for ($index = 0; $index < count($states); $index++) {
        $marking = $states[$index]; $enabled = $net->enabledTransitions($marking);
        if (count($enabled) === 0 && implode(',', $marking) !== $finalKey) $deadlocks++;
        foreach ($enabled as $transition) {
            unset($dead[$transition]);
            $next = $net->fire($marking, $transition);
            $safe = true;
            foreach ($next as $tokens) if ($tokens > 1) { $safe = false; break; }
            if (!$safe) { $unsafe++; continue; }
            $edges++; $key = implode(',', $next);
            if (!array_key_exists($key, $stateIds)) { $stateIds[$key] = count($states); $states[] = $next; $reverseEdges[] = []; }
            $reverseEdges[$stateIds[$key]][] = $index;
            foreach ($net->enabledTransitions($next) as $successor) $follows[pair_key($transition, $successor)] = 1;
        }
    }
    $canFinish = [];
    if (array_key_exists($finalKey, $stateIds)) {
        $queue = [$stateIds[$finalKey]]; $canFinish[$queue[0]] = true;
        for ($i = 0; $i < count($queue); $i++) foreach ($reverseEdges[$queue[$i]] as $predecessor) {
            if (!isset($canFinish[$predecessor])) { $canFinish[$predecessor] = true; $queue[] = $predecessor; }
        }
    }
    $stuck = count($states) - count($canFinish); $deadNames = [];
    foreach ($net->transitions as $transition) if (isset($dead[$transition])) $deadNames[] = $transition;
    return ['markings' => count($states), 'edges' => $edges, 'unsafe' => $unsafe, 'deadlocks' => $deadlocks, 'stuck' => $stuck,
        'final' => array_key_exists($finalKey, $stateIds), 'dead' => $deadNames, 'sound' => $unsafe === 0 && $stuck === 0 && count($dead) === 0, 'follows' => $follows];
}

function footprint_fitness($activities, $follows, $net, $reachability)
{
    $names = unique_names(array_merge($activities, $net->transitions)); $differences = []; $differing = 0;
    foreach ($names as $first) foreach ($names as $second) {
        $observed = basic_relation($follows, $first, $second); $model = basic_relation($reachability['follows'], $first, $second);
        if ($observed !== $model) {
            $differing++;
            if (strcmp($first, $second) <= 0) $differences[] = fields('DIFF', $first, $second, 'log', $observed, 'model', $model);
        }
    }
    $cells = count($names) * count($names);
    return ['activities' => count($names), 'cells' => $cells, 'differing' => $differing, 'fitness' => [$cells - $differing, $cells], 'differences' => $differences];
}

function build_prefixes($cases)
{
    $prefixes = [];
    foreach ($cases as $item) for ($length = 0; $length <= count($item['trace']); $length++) {
        $trace = array_slice($item['trace'], 0, $length); $key = implode(',', $trace);
        if (!isset($prefixes[$key])) $prefixes[$key] = ['trace' => $trace, 'weight' => 0, 'followers' => []];
        $prefixes[$key]['weight']++;
        if ($length < count($item['trace'])) $prefixes[$key]['followers'][$item['trace'][$length]] = true;
    }
    return array_values($prefixes);
}

function precision($net, $prefixes)
{
    $fitting = 0; $allowed = 0; $escaping = 0; $escapes = [];
    foreach ($prefixes as $prefix) {
        $marking = $net->marking(); $fits = true;
        foreach ($prefix['trace'] as $transition) {
            if (!$net->enabled($marking, $transition)) { $fits = false; break; }
            $marking = $net->fire($marking, $transition);
        }
        if (!$fits) continue;
        $fitting++; $enabled = $net->enabledTransitions($marking);
        $allowed += $prefix['weight'] * count($enabled);
        foreach ($enabled as $transition) if (!isset($prefix['followers'][$transition])) {
            $escaping += $prefix['weight']; increment($escapes, $transition, $prefix['weight']);
        }
    }
    return ['prefixes' => $fitting, 'allowed' => $allowed, 'escaping' => $escaping, 'escapes' => $escapes,
        'value' => $allowed === 0 ? [1, 1] : [$allowed - $escaping, $allowed]];
}

function replay_case($net, $item)
{
    $record = replay_record($net); $tokens = array_fill(0, count($net->places), ['times' => [], 'consumed' => 0]);
    $tokens[$net->initial]['times'][] = $item['events'][0]['time']; $record['produced'] = 1;
    foreach ($item['events'] as $event) {
        $activity = $event['activity'];
        if (!isset($net->inputs[$activity])) { $record['skipped']++; continue; }
        foreach ($net->inputs[$activity] as $place) {
            $record['consumed']++;
            if ($tokens[$place]['consumed'] < count($tokens[$place]['times'])) {
                $waiting = $event['time'] - $tokens[$place]['times'][$tokens[$place]['consumed']++];
                $record['places'][$place]['waitingCount']++; $record['places'][$place]['waitingTotal'] += $waiting;
                $record['places'][$place]['waitingMaximum'] = max($record['places'][$place]['waitingMaximum'], $waiting);
                increment($record['places'][$place]['consumptions'], $activity);
            } else { $record['missing']++; $record['places'][$place]['missing']++; }
        }
        foreach ($net->outputs[$activity] as $place) { $tokens[$place]['times'][] = $event['time']; $record['produced']++; }
    }
    $record['consumed']++;
    if ($tokens[$net->final]['consumed'] < count($tokens[$net->final]['times'])) $tokens[$net->final]['consumed']++;
    else { $record['missing']++; $record['places'][$net->final]['missing']++; }
    foreach ($net->places as $place => $name) {
        $remaining = count($tokens[$place]['times']) - $tokens[$place]['consumed'];
        $record['remaining'] += $remaining; $record['places'][$place]['remaining'] = $remaining;
        $record['places'][$place]['deviating'] = $record['places'][$place]['missing'] > 0 || $remaining > 0 ? 1 : 0;
    }
    $record['fitting'] = $record['missing'] === 0 && $record['remaining'] === 0 ? 1 : 0;
    return $record;
}

function replay_all($net, $cases)
{
    $totals = replay_record($net); $records = [];
    foreach ($cases as $item) {
        $record = replay_case($net, $item); $records[$item['id']] = $record;
        foreach (['missing', 'remaining', 'consumed', 'produced', 'skipped', 'fitting'] as $field) $totals[$field] += $record[$field];
        foreach ($net->places as $place => $name) {
            foreach (['missing', 'remaining', 'deviating', 'waitingCount', 'waitingTotal'] as $field) $totals['places'][$place][$field] += $record['places'][$place][$field];
            $totals['places'][$place]['waitingMaximum'] = max($totals['places'][$place]['waitingMaximum'], $record['places'][$place]['waitingMaximum']);
            foreach ($record['places'][$place]['consumptions'] as $transition => $count) increment($totals['places'][$place]['consumptions'], $transition, $count);
        }
    }
    return ['totals' => $totals, 'cases' => $records];
}

function conformance_report($results, $cases)
{
    $reference = $results[0]['net'];
    $lines = [fields('MODEL places', count($reference->places), 'transitions', count($reference->transitions), 'arcs', count($reference->arcs))];
    foreach ($results as $result) {
        $name = $result['name']; $value = $result['reachability'];
        $lines[] = fields('REACHABILITY', $name, 'markings', $value['markings'], 'edges', $value['edges'], 'unsafe', $value['unsafe'],
            'deadlocks', $value['deadlocks'], 'stuck', $value['stuck'], 'final', $value['final'] ? 'yes' : 'no', 'dead', list_names($value['dead']), 'sound', $value['sound'] ? 'yes' : 'no');
    }
    foreach ($results as $result) {
        $value = $result['footprint'];
        $lines[] = fields('FOOTPRINT', $result['name'], 'activities', $value['activities'], 'cells', $value['cells'], 'differing', $value['differing'], 'fitness', fraction($value['fitness']));
        if ($result['name'] === 'reference') append_lines($lines, $value['differences']);
    }
    foreach ($results as $result) {
        $name = $result['name']; $value = $result['precision'];
        $lines[] = fields('PRECISION', $name, 'prefixes', $value['prefixes'], 'allowed', $value['allowed'], 'escaping', $value['escaping'], 'precision', fraction($value['value']));
        $escapes = [];
        foreach ($value['escapes'] as $transition => $weight) $escapes[] = ['name' => $transition, 'weight' => $weight];
        usort($escapes, fn($a, $b) => ($b['weight'] <=> $a['weight']) ?: strcmp($a['name'], $b['name']));
        foreach ($escapes as $entry) $lines[] = fields('ESCAPE', $name, $entry['name'], 'weight', $entry['weight']);
    }
    foreach ($results as $result) {
        $name = $result['name']; $net = $result['net']; $value = $result['replay']['totals'];
        $lines[] = fields('REPLAY', $name, 'cases', count($cases), 'fitting', $value['fitting'], 'skipped', $value['skipped'], 'missing', $value['missing'],
            'remaining', $value['remaining'], 'consumed', $value['consumed'], 'produced', $value['produced'], 'fitness', fraction(fitness($value)));
        foreach ($net->places as $place => $placeName) {
            $statistic = $value['places'][$place];
            $mean = $statistic['waitingCount'] === 0 ? '-' : fraction($statistic['waitingTotal'], $statistic['waitingCount']);
            $maximum = $statistic['waitingCount'] === 0 ? '-' : $statistic['waitingMaximum'];
            $lines[] = fields('PLACE', $name, $placeName, 'missing', $statistic['missing'], 'remaining', $statistic['remaining'],
                'deviating', $statistic['deviating'], 'tokens', $statistic['waitingCount'], 'mean', $mean, 'max', $maximum);
        }
        foreach ($net->places as $place => $placeName) {
            $outputs = [];
            foreach ($net->transitions as $transition) if (in_array($place, $net->inputs[$transition], true)) $outputs[] = $transition;
            if (count($outputs) < 2) continue;
            $routes = [];
            foreach ($outputs as $transition) $routes[] = $transition . '=' . ($value['places'][$place]['consumptions'][$transition] ?? 0);
            $lines[] = fields('ROUTE', $name, $placeName, implode(',', $routes));
        }
    }
    return $lines;
}

function conformance_csv($cases, $replay)
{
    $lines = ['case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness'];
    foreach ($cases as $item) {
        $value = $replay['cases'][$item['id']];
        $lines[] = implode(',', [$item['id'], $item['variant'], count($item['events']), $value['skipped'], $value['missing'], $value['remaining'],
            $value['consumed'], $value['produced'], fraction(fitness($value))]);
    }
    return $lines;
}

function sorted_pair_counts($counts)
{
    $result = [];
    foreach ($counts as $key => $count) {
        [$from, $to] = explode("\0", $key);
        $result[] = compact('from', 'to', 'count');
    }
    usort($result, fn($a, $b) => ($b['count'] <=> $a['count']) ?: pair_order($a, $b));
    return $result;
}

function resource_report($cases, $resources)
{
    $statistics = [];
    foreach ($resources as $resource) $statistics[$resource] = ['events' => 0, 'cases' => [], 'work' => []];
    $handovers = []; $subcontracting = []; $together = []; $total = 0; $self = 0;
    foreach ($cases as $item) {
        $present = [];
        foreach ($item['events'] as $event) {
            $resource = $event['resource']; $present[] = $resource;
            $statistics[$resource]['events']++; $statistics[$resource]['cases'][$item['id']] = true;
            increment($statistics[$resource]['work'], $event['activity']);
        }
        $present = unique_names($present);
        for ($i = 0; $i < count($present); $i++) for ($j = $i + 1; $j < count($present); $j++) increment($together, pair_key($present[$i], $present[$j]));
        for ($i = 1; $i < count($item['events']); $i++) {
            $from = $item['events'][$i - 1]['resource']; $to = $item['events'][$i]['resource']; $key = pair_key($from, $to);
            if (!isset($handovers[$key])) $handovers[$key] = ['from' => $from, 'to' => $to, 'count' => 0, 'cases' => []];
            $handovers[$key]['count']++; $handovers[$key]['cases'][$item['id']] = true; $total++;
            if ($from === $to) $self++;
            if ($i + 1 < count($item['events']) && $from !== $to && $from === $item['events'][$i + 1]['resource']) increment($subcontracting, $key);
        }
    }
    $lines = [];
    foreach ($resources as $i => $resource) {
        $statistic = $statistics[$resource]; $work = $statistic['work']; ksort($work, SORT_STRING); $items = [];
        foreach ($work as $activity => $count) $items[] = $activity . '=' . $count;
        $lines[] = fields('RESOURCE', $i + 1, $resource, 'events', $statistic['events'], 'cases', count($statistic['cases']), 'work', implode(',', $items));
    }
    $transfers = [];
    foreach ($handovers as $handover) if ($handover['from'] !== $handover['to']) $transfers[] = $handover;
    usort($transfers, fn($a, $b) => ($b['count'] <=> $a['count']) ?: pair_order($a, $b));
    foreach ($transfers as $value) $lines[] = fields('HANDOVER', $value['from'], $value['to'], 'count', $value['count'], 'cases', count($value['cases']));
    $cells = [];
    foreach ($resources as $from) {
        $row = [];
        foreach ($resources as $to) $row[] = $handovers[pair_key($from, $to)]['count'] ?? 0;
        $cells[] = $row;
    }
    append_lines($lines, format_table($cells, 5));
    foreach (sorted_pair_counts($subcontracting) as $value) $lines[] = fields('SUBCONTRACT', $value['from'], $value['to'], 'count', $value['count']);
    foreach (sorted_pair_counts($together) as $value) $lines[] = fields('TOGETHER', $value['from'], $value['to'], 'cases', $value['count']);
    $lines[] = fields('TOTAL handovers', $total, 'self', $self, 'other', $total - $self);
    return $lines;
}

function main()
{
    $input = read_inputs(); $settings = parameters($input['parameters']); $validated = validate_rows($input['rows']);
    $events = $validated['events']; $errors = $validated['errors']; $cases = build_cases($events);
    $activities = unique_names(array_column($events, 'activity')); $resources = unique_names(array_column($events, 'resource'));
    $reference = read_model(); $fullLog = [];
    foreach ($cases as $item) $fullLog[] = ['trace' => $item['trace'], 'weight' => 1];
    $follows = count_follows($fullLog); $variants = group_variants($cases, $follows, $settings); $discovered = alpha_mining($variants);
    $prefixes = build_prefixes($cases); $results = [];
    foreach ([['reference', $reference], ['alpha', $discovered['alpha']], ['alpha_plus', $discovered['plus']]] as [$name, $net]) {
        $reachability = explore($net);
        $results[] = ['name' => $name, 'net' => $net, 'reachability' => $reachability, 'footprint' => footprint_fitness($activities, $follows, $net, $reachability),
            'precision' => precision($net, $prefixes), 'replay' => replay_all($net, $cases)];
    }
    write_outputs(['log_summary.txt' => log_summary($input['rows'], $events, $errors, $cases, $activities, $resources, $reference, $settings),
        'variants.txt' => variant_report($variants, $cases, count($events), $settings, $results[0]['replay']),
        'dfg.txt' => directly_follows_report($cases, $activities, $follows), 'alpha_net.txt' => $discovered['lines'],
        'heuristic_net.txt' => heuristic_report($fullLog, $activities, $follows, $settings),
        'conformance.csv' => conformance_csv($cases, $results[0]['replay']), 'conformance.txt' => conformance_report($results, $cases),
        'resources.txt' => resource_report($cases, $resources)]);
}

main();
