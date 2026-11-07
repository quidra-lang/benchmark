<?php

require_once __DIR__ . '/trace_io.php';
require_once __DIR__ . '/hazards.php';
require_once __DIR__ . '/pipeline.php';
require_once __DIR__ . '/predictors.php';
require_once __DIR__ . '/report.php';

const CLASSES = ['ALU', 'MUL', 'LOAD', 'STORE', 'BRANCH', 'JUMP', 'NOP'];
const CAUSES = ['control', 'structural', 'load_use', 'raw'];
const KINDS = ['direction', 'btb_miss', 'wrong_target'];
const STAGES = ['IF', 'ID', 'EX', 'MEM', 'WB'];
const OPERANDS = [
    'ALU' => ['required', 'required', 'optional'], 'MUL' => ['required', 'required', 'required'],
    'LOAD' => ['required', 'required', 'none'], 'STORE' => ['none', 'required', 'required'],
    'BRANCH' => ['none', 'required', 'optional'], 'JUMP' => ['optional', 'optional', 'none'],
    'NOP' => ['none', 'none', 'none']
];

function zeros(array $names): array
{
    return array_fill_keys($names, 0);
}

function namedCounts(array $names, array $counts): string
{
    $parts = [];
    foreach ($names as $name) $parts[] = $name . ' ' . $counts[$name];
    return implode(' ', $parts);
}

function registerText(?int $register): string
{
    return $register === null ? '-' : 'r' . $register;
}

function validateTrace(string $line, array $statics): array
{
    $fields = explode(' ', $line);
    if (count($fields) !== 8 || in_array('', $fields, true)) return ['reason' => 'fields'];
    [$pcText, $className, $rdText, $rs1Text, $rs2Text, $outcome, $targetText, $addressText] = $fields;
    $pc = parseHex($pcText);
    if ($pc === null || $pc % 4 !== 0) return ['reason' => 'pc'];
    if (!in_array($className, CLASSES, true)) return ['reason' => 'class'];
    $registers = array_map('parseRegister', [$rdText, $rs1Text, $rs2Text]);
    foreach ($registers as $register) if ($register === -1) return ['reason' => 'register'];
    foreach (OPERANDS[$className] as $i => $mode) {
        if (($mode === 'required' && $registers[$i] === null) || ($mode === 'none' && $registers[$i] !== null)) return ['reason' => 'operands'];
    }
    if ($className === 'BRANCH' ? ($outcome !== 'T' && $outcome !== 'N') :
        ($className === 'JUMP' ? $outcome !== 'T' : $outcome !== '-')) return ['reason' => 'taken'];
    $control = $className === 'BRANCH' || $className === 'JUMP';
    $target = null;
    if ($control) {
        $target = parseHex($targetText);
        if ($target === null || $target % 4 !== 0 || $target === $pc + 4) return ['reason' => 'target'];
    } elseif ($targetText !== '-') return ['reason' => 'target'];
    $address = null;
    if ($className === 'LOAD' || $className === 'STORE') {
        $address = parseHex($addressText);
        if ($address === null || $address % 4 !== 0) return ['reason' => 'address'];
    } elseif ($addressText !== '-') return ['reason' => 'address'];
    [$rd, $rs1, $rs2] = $registers;
    if (isset($statics[$pc])) {
        $first = $statics[$pc];
        if ($first['className'] !== $className || $first['rd'] !== $rd || $first['rs1'] !== $rs1 || $first['rs2'] !== $rs2 ||
            (($className === 'BRANCH' || ($className === 'JUMP' && $rs1 === null)) && $first['target'] !== $target)) return ['reason' => 'conflict'];
    }
    return ['instruction' => compact('pc', 'className', 'rd', 'rs1', 'rs2', 'outcome', 'target', 'address', 'control') +
        ['nextPC' => $outcome === 'T' ? $target : $pc + 4]];
}

function checkTrace(array $lines): array
{
    $instructions = $statics = $rejected = $gaps = [];
    foreach ($lines as $index => $line) {
        $result = validateTrace($line, $statics);
        if (isset($result['reason'])) {
            $rejected[] = ['line' => $index + 1, 'reason' => $result['reason']];
            continue;
        }
        $instruction = $result['instruction'] + ['line' => $index + 1, 'number' => count($instructions) + 1];
        if ($instructions) {
            $previous = $instructions[count($instructions) - 1];
            if ($instruction['pc'] !== $previous['nextPC']) {
                $gaps[] = ['line' => $instruction['line'], 'expected' => $previous['nextPC'], 'found' => $instruction['pc']];
            }
        }
        if (!isset($statics[$instruction['pc']])) $statics[$instruction['pc']] = $instruction + ['executions' => []];
        $statics[$instruction['pc']]['executions'][] = count($instructions);
        $instructions[] = $instruction;
    }
    attachSources($instructions);
    return ['lineCount' => count($lines), 'instructions' => $instructions, 'statics' => $statics, 'rejected' => $rejected, 'gaps' => $gaps];
}

function predictTrace(array $instructions, array $specification, array $config): array
{
    $btb = new BTB($config['btb']);
    $ras = new RAS($config['ras']);
    $direction = new DirectionPredictor($specification);
    $results = $flags = $byPC = [];
    $counts = zeros(['control', 'mis', 'branches', 'branchMis', 'jumps', 'jumpMis', 'hits', 'calls', 'returns', 'rasPredicted', 'rasCorrect']);
    $kinds = zeros(KINDS);
    foreach ($instructions as $instruction) {
        if (!$instruction['control']) {
            $results[] = ['mispredicted' => false, 'predictedNext' => $instruction['nextPC'], 'kind' => null];
            $flags[] = false;
            continue;
        }
        $branch = $instruction['className'] === 'BRANCH';
        $taken = $instruction['outcome'] === 'T';
        $counts['control']++;
        $counts[$branch ? 'branches' : 'jumps']++;
        $candidate = $btb->lookup($instruction['pc']);
        if ($candidate !== null) $counts['hits']++;
        if ($instruction['className'] === 'JUMP' && $instruction['rd'] === null && $instruction['rs1'] === 31) {
            $counts['returns']++;
            $returned = $ras->pop();
            if ($returned !== null) {
                $candidate = $returned;
                $counts['rasPredicted']++;
                if ($returned === $instruction['target']) $counts['rasCorrect']++;
            }
        }
        if ($instruction['className'] === 'JUMP' && $instruction['rd'] === 31) {
            $counts['calls']++;
            $ras->push($instruction['pc'] + 4);
        }
        $perfect = $specification['scheme'] === 'PERFECT';
        $outcomePrediction = $branch && !$perfect ? $direction->predict($instruction['pc'], $instruction['target']) : null;
        $predictedNext = $instruction['pc'] + 4;
        if ($perfect) $predictedNext = $instruction['nextPC'];
        elseif (!$branch || $outcomePrediction['taken']) $predictedNext = $candidate ?? $predictedNext;
        $mispredicted = $predictedNext !== $instruction['nextPC'];
        $kind = null;
        if ($mispredicted) {
            $kind = $branch && $outcomePrediction['taken'] !== $taken ? 'direction' : ($candidate === null ? 'btb_miss' : 'wrong_target');
            $counts['mis']++;
            $counts[$branch ? 'branchMis' : 'jumpMis']++;
            $kinds[$kind]++;
        }
        $results[] = compact('mispredicted', 'predictedNext', 'kind');
        $flags[] = $mispredicted;
        $pc = $instruction['pc'];
        if (!isset($byPC[$pc])) $byPC[$pc] = ['executions' => 0, 'taken' => 0, 'mis' => 0];
        $byPC[$pc]['executions']++;
        if ($taken) $byPC[$pc]['taken']++;
        if ($mispredicted) $byPC[$pc]['mis']++;
        if ($branch && !$perfect) $direction->update($outcomePrediction, $taken);
        if ($taken) $btb->insert($instruction['pc'], $instruction['target']);
    }
    return compact('specification', 'results', 'flags', 'byPC', 'counts', 'kinds') + ['bits' => predictorStorage($specification)];
}

function aggregateTiming(array $timing): array
{
    $stallCycles = zeros(CAUSES);
    $stallEvents = zeros(CAUSES);
    $totalStalls = 0;
    foreach ($timing['records'] as $record) {
        $stallCycles[$record['cause']] += $record['cycles'];
        $stallEvents[$record['cause']]++;
        $totalStalls += $record['cycles'];
    }
    return compact('stallCycles', 'stallEvents', 'totalStalls');
}

function allTimings(array $instructions, array $predictions, array $config): array
{
    $combinations = [];
    $primary = null;
    foreach ($config['variants'] as $variant) {
        foreach ($predictions as $prediction) {
            $timing = simulate($instructions, $variant, $prediction['flags']);
            $combination = ['variant' => $variant, 'prediction' => $prediction, 'cycles' => $timing['cycles']] + aggregateTiming($timing);
            $combinations[] = $combination;
            if ($variant['name'] === $config['primaryVariant'] && $prediction['specification']['name'] === $config['primaryPredictor']) {
                $primary = $combination + ['timing' => $timing];
            }
        }
    }
    return compact('combinations', 'primary');
}

function stageSegment(int $stage, int $from, int $to, string $first, ?string $rest = null): array
{
    return compact('stage', 'from', 'to', 'first') + ['rest' => $rest ?? $first];
}

function buildRows(array $instructions, array $primary): array
{
    $waiting = array_fill(0, count($instructions), []);
    foreach ($primary['timing']['records'] as $record) if ($record['waiting'] !== null) $waiting[$record['waiting']][] = $record;
    $rows = [];
    $refetch = 0;
    foreach ($instructions as $i => $instruction) {
        $time = $primary['timing']['times'][$i];
        $prediction = $primary['prediction']['results'][$i];
        $annotation = '';
        foreach ($waiting[$i] as $record) $annotation .= ' ' . $record['cause'] . ' ' . $record['cycles'];
        if ($prediction['mispredicted']) $annotation .= ' mispredict ' . $prediction['kind'];
        $rows[] = ['number' => $i + 1, 'pc' => $instruction['pc'], 'className' => $instruction['className'], 'wrong' => false,
            'segments' => [stageSegment(0, $time['F'], $time['D'] - 1, 'F', '*'), stageSegment(1, $time['D'], $time['X'] - 1, 'D', '*'),
                stageSegment(2, $time['X'], $time['M'] - 1, 'X'), stageSegment(3, $time['M'], $time['M'], 'M'), stageSegment(4, $time['W'], $time['W'], 'W')],
            'cancel' => null, 'annotation' => $annotation];
        if (!$prediction['mispredicted']) continue;
        $early = idResolved($instruction, $primary['variant']);
        $segments = [stageSegment(0, $time['D'], $time['X'] - 1, 'F', '*')];
        if (!$early) $segments[] = stageSegment(1, $time['X'], $time['X'], 'D');
        $rows[] = ['number' => null, 'pc' => $prediction['predictedNext'], 'className' => 'FLUSH', 'wrong' => true,
            'segments' => $segments, 'cancel' => $time['X'] + ($early ? 0 : 1), 'annotation' => ''];
        $refetch++;
        if (!$early) {
            $rows[] = ['number' => null, 'pc' => $prediction['predictedNext'] + 4, 'className' => 'FLUSH', 'wrong' => true,
                'segments' => [stageSegment(0, $time['X'], $time['X'], 'F')], 'cancel' => $time['X'] + 1, 'annotation' => ''];
            $refetch++;
        }
    }
    $occupancy = array_fill(0, count(STAGES), ['correct' => 0, 'wrong' => 0]);
    foreach ($rows as $row) {
        foreach ($row['segments'] as $segment) $occupancy[$segment['stage']][$row['wrong'] ? 'wrong' : 'correct'] += $segment['to'] - $segment['from'] + 1;
    }
    return compact('rows', 'occupancy', 'refetch');
}

function diagramReport(array $primary, array $diagram, array $config): array
{
    $lines = ['pipeline variant=' . $primary['variant']['name'] . ' predictor=' . $primary['prediction']['specification']['name'] .
        ' cycles ' . $config['start'] . '-' . $config['end'], cycleHeader($config['start'], $config['end'])];
    $contents = array_fill(0, $config['end'] - $config['start'] + 1, array_fill(0, count(STAGES), '.'));
    $count = $stallCells = $flushed = 0;
    foreach ($diagram['rows'] as $row) {
        $rendered = diagramRow($row, $config['start'], $config['end']);
        if ($rendered !== null) {
            $lines[] = $rendered['line'];
            $count++;
            $stallCells += $rendered['stallCells'];
            $flushed += $rendered['flushed'];
        }
        foreach ($row['segments'] as $segment) {
            for ($cycle = max($config['start'], $segment['from']); $cycle <= min($config['end'], $segment['to']); $cycle++) {
                $contents[$cycle - $config['start']][$segment['stage']] = $row['wrong'] ? 'w' : (string)$row['number'];
            }
        }
    }
    $completed = count(array_filter($primary['timing']['times'], fn($time) => $time['W'] >= $config['start'] && $time['W'] <= $config['end']));
    $lines[] = 'rows ' . $count . ' completed ' . $completed . ' stall_cells ' . $stallCells . ' flushed ' . $flushed;
    $lines[] = '';
    $lines[] = 'stages';
    $lines[] = 'cycle IF ID EX MEM WB';
    foreach ($contents as $i => $stages) $lines[] = ($config['start'] + $i) . ' ' . implode(' ', $stages);
    return $lines;
}

function traceSummary(array $trace): array
{
    $mix = zeros(CLASSES);
    $distances = array_fill(0, 5, 0);
    $addresses = [];
    $taken = $backward = $indirect = $link = $operands = $withProducer = 0;
    foreach ($trace['instructions'] as $i => $instruction) {
        $mix[$instruction['className']]++;
        if ($instruction['className'] === 'BRANCH') {
            if ($instruction['outcome'] === 'T') $taken++;
            if ($instruction['target'] < $instruction['pc']) $backward++;
        }
        if ($instruction['className'] === 'JUMP') {
            if ($instruction['rs1'] !== null) $indirect++;
            if ($instruction['rd'] !== null) $link++;
        }
        if ($instruction['address'] !== null) $addresses[$instruction['address']] = true;
        foreach ($instruction['sources'] as $source) {
            $operands++;
            if ($source['producer'] !== null) {
                $withProducer++;
                $distances[min(5, $i - $source['producer']) - 1]++;
            }
        }
    }
    $staticBranches = $staticJumps = 0;
    foreach ($trace['statics'] as $instruction) {
        if ($instruction['className'] === 'BRANCH') $staticBranches++;
        if ($instruction['className'] === 'JUMP') $staticJumps++;
    }
    return compact('mix', 'distances', 'taken', 'backward', 'indirect', 'link', 'operands', 'withProducer', 'staticBranches', 'staticJumps') +
        ['addresses' => count($addresses)];
}

function analyzePrimary(array $instructions, array $primary, array $config): array
{
    $finish = [];
    $height = 0;
    $forwarding = zeros(['regfile', 'ex_mem', 'mem_wb']);
    foreach ($instructions as $i => $instruction) {
        $start = 0;
        foreach ($instruction['sources'] as $source) {
            if ($source['producer'] !== null) $start = max($start, $finish[$source['producer']]);
            $path = forwardingPath($source, $i, $primary['variant'], $instructions, $primary['timing']['times']);
            $forwarding[$path]++;
        }
        $latency = $instruction['className'] === 'LOAD' ? 2 : ($instruction['className'] === 'MUL' ? $primary['variant']['latency'] : 1);
        $finish[] = $start + $latency;
        $height = max($height, $finish[$i]);
    }
    $lengths = array_fill(0, 5, 0);
    for ($i = 1; $i < count($instructions); $i++) {
        $gap = $primary['timing']['times'][$i]['X'] - $primary['timing']['times'][$i - 1]['X'] - 1;
        if ($gap > 0) $lengths[min($gap, 5) - 1]++;
    }
    $byPC = [];
    $classStalls = zeros(CLASSES);
    $dependencyMap = [];
    foreach ($primary['timing']['records'] as $record) {
        $responsible = $instructions[$record['responsible']];
        $classStalls[$responsible['className']] += $record['cycles'];
        $pc = $responsible['pc'];
        if (!isset($byPC[$pc])) $byPC[$pc] = ['pc' => $pc, 'className' => $responsible['className'], 'total' => 0] + zeros(CAUSES);
        $byPC[$pc]['total'] += $record['cycles'];
        $byPC[$pc][$record['cause']] += $record['cycles'];
        if ($record['cause'] !== 'load_use' && $record['cause'] !== 'raw') continue;
        $producer = $instructions[$record['producer']];
        $waiting = $instructions[$record['waiting']];
        $key = $producer['pc'] . '/' . $waiting['pc'] . '/' . $record['cause'];
        if (!isset($dependencyMap[$key])) $dependencyMap[$key] = ['producer' => $producer, 'waiting' => $waiting,
            'cause' => $record['cause'], 'cycles' => 0, 'events' => 0];
        $dependencyMap[$key]['cycles'] += $record['cycles'];
        $dependencyMap[$key]['events']++;
    }
    $hotspots = array_values($byPC);
    usort($hotspots, fn($a, $b) => ($b['total'] <=> $a['total']) ?: ($a['pc'] <=> $b['pc']));
    $dependencies = array_values($dependencyMap);
    usort($dependencies, fn($a, $b) => ($b['cycles'] <=> $a['cycles']) ?: ($a['producer']['pc'] <=> $b['producer']['pc']) ?:
        ($a['waiting']['pc'] <=> $b['waiting']['pc']) ?: (array_search($a['cause'], CAUSES, true) <=> array_search($b['cause'], CAUSES, true)));
    $intervals = [];
    for ($start = 0; $start < count($instructions); $start += $config['interval']) {
        $end = min(count($instructions), $start + $config['interval']) - 1;
        $cycles = $primary['timing']['times'][$end]['W'] - ($start === 0 ? 0 : $primary['timing']['times'][$start - 1]['W']);
        $intervals[] = ['start' => $start + 1, 'end' => $end + 1, 'cycles' => $cycles];
    }
    return compact('height', 'forwarding', 'lengths', 'byPC', 'classStalls', 'hotspots', 'dependencies', 'intervals');
}

function whatifRuns(array $instructions, array $primary): array
{
    $variant = $primary['variant'];
    $oppositeStage = $variant['resolution'] === 'ID' ? 'EX' : 'ID';
    $single = $variant;
    $single['latency'] = 1;
    $oppositeForwarding = $variant;
    $oppositeForwarding['forwarding'] = !$variant['forwarding'];
    $oppositeVariant = $variant;
    $oppositeVariant['resolution'] = $oppositeStage;
    $experiments = [
        ['name' => 'perfect_prediction', 'variant' => $variant, 'flags' => array_fill(0, count($instructions), false)],
        ['name' => 'single_cycle_mul', 'variant' => $single, 'flags' => $primary['prediction']['flags']],
        ['name' => $variant['forwarding'] ? 'forwarding_off' : 'forwarding_on', 'variant' => $oppositeForwarding, 'flags' => $primary['prediction']['flags']],
        ['name' => 'branch_stage_' . $oppositeStage, 'variant' => $oppositeVariant, 'flags' => $primary['prediction']['flags']]
    ];
    $runs = [];
    foreach ($experiments as $experiment) {
        $timing = simulate($instructions, $experiment['variant'], $experiment['flags']);
        $runs[] = ['name' => $experiment['name'], 'cycles' => $timing['cycles']];
    }
    return $runs;
}

function joinSections(array $parts): array
{
    $lines = [];
    foreach ($parts as $i => $part) {
        if ($i > 0) $lines[] = '';
        foreach ($part as $line) $lines[] = $line;
    }
    return $lines;
}

function statsReport(array $trace, array $config, array $predictions, array $combinations, array $primary,
    array $summary, array $analysis, array $diagram, array $whatifs): array
{
    $n = count($trace['instructions']);
    $C = $primary['cycles'];
    $input = ['input lines ' . $trace['lineCount'] . ' accepted ' . $n . ' rejected ' . count($trace['rejected']) . ' gaps ' . count($trace['gaps'])];
    foreach ($trace['rejected'] as $rejection) $input[] = 'reject line ' . $rejection['line'] . ' ' . $rejection['reason'];
    foreach ($trace['gaps'] as $gap) $input[] = 'gap line ' . $gap['line'] . ' expected ' . hexText($gap['expected']) . ' found ' . hexText($gap['found']);
    $parts = [$input];
    $distanceText = [];
    foreach (['1', '2', '3', '4', '5+'] as $i => $name) $distanceText[] = $name . ' ' . $summary['distances'][$i];
    $parts[] = ['trace', 'instructions ' . $n, 'static_instructions ' . count($trace['statics']), 'mix ' . namedCounts(CLASSES, $summary['mix']),
        'branches ' . $summary['mix']['BRANCH'] . ' taken ' . $summary['taken'] . ' backward ' . $summary['backward'],
        'jumps ' . $summary['mix']['JUMP'] . ' indirect ' . $summary['indirect'] . ' link ' . $summary['link'],
        'static_control branches ' . $summary['staticBranches'] . ' jumps ' . $summary['staticJumps'],
        'memory loads ' . $summary['mix']['LOAD'] . ' stores ' . $summary['mix']['STORE'] . ' distinct_addresses ' . $summary['addresses'],
        'operands ' . $summary['operands'] . ' with_producer ' . $summary['withProducer'] . ' distance ' . implode(' ', $distanceText)];
    $predictionLines = ['prediction'];
    foreach ($predictions as $prediction) {
        $count = $prediction['counts'];
        $predictionLines[] = $prediction['specification']['name'] . ' ' . $prediction['specification']['scheme'] . ' bits ' . $prediction['bits'] .
            ' control ' . $count['control'] . ' mispredicted ' . $count['mis'] . ' accuracy ' . percentage($count['control'] - $count['mis'], $count['control']) .
            ' branches ' . percentage($count['branches'] - $count['branchMis'], $count['branches']) .
            ' jumps ' . percentage($count['jumps'] - $count['jumpMis'], $count['jumps']) . ' ' . namedCounts(KINDS, $prediction['kinds']);
    }
    $common = $predictions[0]['counts'];
    $predictionLines[] = 'btb entries ' . $config['btb'] . ' lookups ' . $common['control'] . ' hits ' . $common['hits'] . ' misses ' . ($common['control'] - $common['hits']);
    $predictionLines[] = 'ras depth ' . $config['ras'] . ' calls ' . $common['calls'] . ' returns ' . $common['returns'] .
        ' predicted ' . $common['rasPredicted'] . ' correct ' . $common['rasCorrect'];
    $parts[] = $predictionLines;
    $stack = [];
    foreach (CAUSES as $cause) $stack[] = $cause . ' ' . decimal($primary['stallCycles'][$cause], $n);
    $lengthText = [];
    foreach (['1', '2', '3', '4', '5+'] as $i => $name) $lengthText[] = $name . ' ' . $analysis['lengths'][$i];
    $parts[] = ['timing variant=' . $primary['variant']['name'] . ' predictor=' . $primary['prediction']['specification']['name'],
        'forwarding ' . ($primary['variant']['forwarding'] ? 'on' : 'off') . ' branch_stage ' . $primary['variant']['resolution'] . ' mul_latency ' . $primary['variant']['latency'],
        'cycles ' . $C, 'cpi ' . fraction($C, $n) . ' ' . decimal($C, $n), 'ipc ' . decimal($n, $C),
        'stall_cycles total ' . $primary['totalStalls'] . ' ' . namedCounts(CAUSES, $primary['stallCycles']),
        'stall_events ' . namedCounts(CAUSES, $primary['stallEvents']), 'flushed ' . $diagram['refetch'],
        'cycle_check ' . $n . ' + 4 + ' . $primary['totalStalls'] . ' = ' . ($n + 4 + $primary['totalStalls']),
        'cpi_stack base 1.0000 fill ' . decimal(4, $n) . ' ' . implode(' ', $stack), 'stall_lengths ' . implode(' ', $lengthText),
        'dataflow height ' . $analysis['height'] . ' ilp ' . decimal($n, $analysis['height'])];
    $whatifLines = ['whatif'];
    foreach ($whatifs as $run) $whatifLines[] = $run['name'] . ' cycles ' . $run['cycles'] . ' saved ' . ($C - $run['cycles']) . ' speedup ' . decimal($C, $run['cycles']);
    $parts[] = $whatifLines;
    $classLines = ['classes'];
    foreach (CLASSES as $name) {
        $count = $summary['mix'][$name];
        $classLines[] = $name . ' count ' . $count . ' stall_cycles ' . $analysis['classStalls'][$name] .
            ' per_instruction ' . ($count === 0 ? '-' : decimal($analysis['classStalls'][$name], $count));
    }
    $parts[] = $classLines;
    $parts[] = ['forwarding ' . namedCounts(['regfile', 'ex_mem', 'mem_wb'], $analysis['forwarding'])];
    $occupancy = ['occupancy cycles ' . $C];
    foreach (STAGES as $i => $name) {
        $correct = $diagram['occupancy'][$i]['correct'];
        $wrong = $diagram['occupancy'][$i]['wrong'];
        $occupancy[] = $name . ' correct ' . $correct . ' wrong ' . $wrong . ' idle ' . ($C - $correct - $wrong) . ' busy ' . percentage($correct + $wrong, $C);
    }
    $parts[] = $occupancy;
    $hotspotLines = ['hotspots'];
    foreach (array_slice($analysis['hotspots'], 0, $config['top']) as $i => $hotspot) {
        $hotspotLines[] = ($i + 1) . ' ' . hexText($hotspot['pc']) . ' ' . $hotspot['className'] .
            ' stall_cycles ' . $hotspot['total'] . ' ' . namedCounts(CAUSES, $hotspot);
    }
    $parts[] = $hotspotLines;
    $dependencyLines = ['dependencies total ' . count($analysis['dependencies'])];
    foreach (array_slice($analysis['dependencies'], 0, $config['top']) as $i => $dependency) {
        $dependencyLines[] = ($i + 1) . ' ' . hexText($dependency['producer']['pc']) . ' ' . $dependency['producer']['className'] .
            ' -> ' . hexText($dependency['waiting']['pc']) . ' ' . $dependency['waiting']['className'] . ' ' . $dependency['cause'] .
            ' stall_cycles ' . $dependency['cycles'] . ' events ' . $dependency['events'];
    }
    $parts[] = $dependencyLines;
    $intervalLines = ['intervals size ' . $config['interval']];
    foreach ($analysis['intervals'] as $interval) $intervalLines[] = $interval['start'] . '-' . $interval['end'] . ' cycles ' . $interval['cycles'] .
        ' cpi ' . decimal($interval['cycles'], $interval['end'] - $interval['start'] + 1);
    $parts[] = $intervalLines;
    $tableLines = ['cycles_table ' . implode(' ', array_map(fn($prediction) => $prediction['specification']['name'], $predictions))];
    foreach ($config['variants'] as $variant) {
        $row = [];
        foreach ($combinations as $combination) if ($combination['variant']['name'] === $variant['name']) $row[] = $combination['cycles'];
        $tableLines[] = $variant['name'] . ' ' . implode(' ', $row);
    }
    $parts[] = $tableLines;
    return joinSections($parts);
}

function branchesReport(array $statics, array $predictions): array
{
    $lines = ['predictor,pc,class,executions,taken,mispredictions,accuracy'];
    foreach ($predictions as $prediction) {
        foreach ($statics as $instruction) {
            if (!$instruction['control']) continue;
            $count = $prediction['byPC'][$instruction['pc']];
            $lines[] = implode(',', [$prediction['specification']['name'], hexText($instruction['pc']), $instruction['className'],
                $count['executions'], $count['taken'], $count['mis'], percentage($count['executions'] - $count['mis'], $count['executions'])]);
        }
    }
    return $lines;
}

function comparisonReport(array $combinations, array $primary, int $n): array
{
    usort($combinations, fn($a, $b) => ($a['cycles'] <=> $b['cycles']) ?: strcmp($a['variant']['name'], $b['variant']['name']) ?:
        strcmp($a['prediction']['specification']['name'], $b['prediction']['specification']['name']));
    $lines = ['rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw'];
    foreach ($combinations as $i => $combination) {
        $count = $combination['prediction']['counts'];
        $fields = [$i + 1, $combination['variant']['name'], $combination['prediction']['specification']['name'], $combination['cycles'],
            decimal($combination['cycles'], $n), decimal($primary['cycles'], $combination['cycles']),
            percentage($count['control'] - $count['mis'], $count['control']), $count['mis']];
        foreach (CAUSES as $cause) $fields[] = $combination['stallCycles'][$cause];
        $lines[] = implode(',', $fields);
    }
    return $lines;
}

function branchProfile(array $instructions, array $statics, array $predictions): array
{
    $branches = ['branches'];
    $loops = ['loops'];
    $candidates = array_values(array_filter($predictions, fn($prediction) => $prediction['specification']['scheme'] !== 'PERFECT'));
    foreach ($statics as $instruction) {
        if ($instruction['className'] !== 'BRANCH') continue;
        $previous = null;
        $run = $taken = $transitions = $longestTaken = $longestNotTaken = $trips = $tripLength = $maxTrip = 0;
        foreach ($instruction['executions'] as $i) {
            $outcome = $instructions[$i]['outcome'];
            if ($outcome === $previous) $run++;
            else {
                if ($previous !== null) $transitions++;
                $run = 1;
            }
            $previous = $outcome;
            if ($outcome === 'T') {
                $taken++;
                $longestTaken = max($longestTaken, $run);
            } else {
                $longestNotTaken = max($longestNotTaken, $run);
            }
            $tripLength++;
            if ($outcome === 'N') {
                $trips++;
                $maxTrip = max($maxTrip, $tripLength);
                $tripLength = 0;
            }
        }
        if ($tripLength > 0) {
            $trips++;
            $maxTrip = max($maxTrip, $tripLength);
        }
        $best = $candidates[0];
        foreach (array_slice($candidates, 1) as $candidate) {
            if ($candidate['byPC'][$instruction['pc']]['mis'] < $best['byPC'][$instruction['pc']]['mis']) $best = $candidate;
        }
        $direction = $instruction['target'] < $instruction['pc'] ? 'backward' : 'forward';
        $executions = count($instruction['executions']);
        $branches[] = hexText($instruction['pc']) . ' ' . $direction . ' executions ' . $executions . ' taken ' . $taken . ' transitions ' . $transitions .
            ' longest_taken ' . $longestTaken . ' longest_not_taken ' . $longestNotTaken . ' best ' . $best['specification']['name'] .
            ' ' . $best['byPC'][$instruction['pc']]['mis'];
        if ($direction === 'backward') {
            $body = intdiv($instruction['pc'] - $instruction['target'], 4) + 1;
            $loops[] = hexText($instruction['target']) . '-' . hexText($instruction['pc']) . ' body ' . $body . ' entries ' . $trips .
                ' iterations ' . $executions . ' avg_trip ' . decimal($executions, $trips) . ' max_trip ' . $maxTrip;
        }
    }
    return [$branches, $loops];
}

function segmentProfile(array $instructions, array $primary, int $top): array
{
    $groups = [];
    $start = 0;
    foreach ($instructions as $end => $instruction) {
        if (!$instruction['control'] && $end !== count($instructions) - 1) continue;
        $pc = $instructions[$start]['pc'];
        if (!isset($groups[$pc])) $groups[$pc] = ['pc' => $pc, 'instances' => 0, 'instructions' => 0, 'cycles' => 0];
        $groups[$pc]['instances']++;
        $groups[$pc]['instructions'] += $end - $start + 1;
        $groups[$pc]['cycles'] += $primary['timing']['times'][$end]['W'] - ($start === 0 ? 0 : $primary['timing']['times'][$start - 1]['W']);
        $start = $end + 1;
    }
    $ranked = array_values($groups);
    usort($ranked, fn($a, $b) => ($b['cycles'] <=> $a['cycles']) ?: ($a['pc'] <=> $b['pc']));
    $lines = ['segments total ' . count($groups)];
    foreach (array_slice($ranked, 0, $top) as $i => $group) {
        $lines[] = ($i + 1) . ' ' . hexText($group['pc']) . ' instances ' . $group['instances'] . ' instructions ' . $group['instructions'] .
            ' cycles ' . $group['cycles'] . ' cpi ' . decimal($group['cycles'], $group['instructions']);
    }
    return $lines;
}

function profileReport(array $instructions, array $statics, array $predictions, array $primary, array $analysis, array $config): array
{
    $parts = branchProfile($instructions, $statics, $predictions);
    $parts[] = segmentProfile($instructions, $primary, $config['top']);
    $indirect = ['indirect'];
    $staticLines = ['instructions'];
    foreach ($statics as $instruction) {
        if ($instruction['className'] === 'JUMP' && $instruction['rs1'] !== null) {
            $counts = [];
            foreach ($instruction['executions'] as $i) {
                $target = $instructions[$i]['target'];
                $counts[$target] = ($counts[$target] ?? 0) + 1;
            }
            $targets = [];
            foreach ($counts as $target => $count) $targets[] = ['target' => $target, 'count' => $count];
            usort($targets, fn($a, $b) => ($b['count'] <=> $a['count']) ?: ($a['target'] <=> $b['target']));
            $items = array_map(fn($item) => hexText($item['target']) . ':' . $item['count'], $targets);
            $indirect[] = hexText($instruction['pc']) . ' executions ' . count($instruction['executions']) . ' distinct ' . count($counts) .
                ' targets ' . implode(' ', $items);
        }
        $stalls = $analysis['byPC'][$instruction['pc']]['total'] ?? 0;
        $staticLines[] = hexText($instruction['pc']) . ' ' . $instruction['className'] . ' ' . registerText($instruction['rd']) .
            ' ' . registerText($instruction['rs1']) . ' ' . registerText($instruction['rs2']) .
            ' executions ' . count($instruction['executions']) . ' stall_cycles ' . $stalls;
    }
    $parts[] = $indirect;
    $parts[] = $staticLines;
    return joinSections($parts);
}

function main(): void
{
    $input = readInput();
    $config = $input['config'];
    $trace = checkTrace($input['lines']);
    $instructions = $trace['instructions'];
    $predictions = [];
    foreach ($config['predictors'] as $specification) $predictions[] = predictTrace($instructions, $specification, $config);
    $timings = allTimings($instructions, $predictions, $config);
    $combinations = $timings['combinations'];
    $primary = $timings['primary'];
    $summary = traceSummary($trace);
    $analysis = analyzePrimary($instructions, $primary, $config);
    $diagram = buildRows($instructions, $primary);
    $whatifs = whatifRuns($instructions, $primary);
    $statics = array_values($trace['statics']);
    usort($statics, fn($a, $b) => $a['pc'] <=> $b['pc']);
    writeReport('pipeline.txt', diagramReport($primary, $diagram, $config));
    writeReport('stats.txt', statsReport($trace, $config, $predictions, $combinations, $primary, $summary, $analysis, $diagram, $whatifs));
    writeReport('branches.csv', branchesReport($statics, $predictions));
    writeReport('comparison.csv', comparisonReport($combinations, $primary, count($instructions)));
    writeReport('profile.txt', profileReport($instructions, $statics, $predictions, $primary, $analysis, $config));
}

main();
