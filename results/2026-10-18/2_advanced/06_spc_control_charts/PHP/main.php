<?php
require __DIR__ . '/dataset.php';
require __DIR__ . '/variable_charts.php';
require __DIR__ . '/attribute_charts.php';
require __DIR__ . '/run_rules.php';
require __DIR__ . '/capability.php';
require __DIR__ . '/plot.php';

const CHART_ORDER = ['XBAR_R','R','XBAR_S','S','I','MR','CUSUM','EWMA','MA'];
const SHEWHART_CHARTS = ['XBAR_R','R','XBAR_S','S','I','MR'];
const RULE_ORDER = ['1','2','3','4','5','6','7','8','UPPER','LOWER'];
const FAMILIES = ['XBAR_R' => [['XBAR','R'],['XBAR_R','R']], 'XBAR_S' => [['XBAR','S'],['XBAR_S','S']], 'I_MR' => [['I','MR'],['I','MR']]];
const LOCATION_CHARTS = ['XBAR_R','XBAR_S','I','CUSUM','EWMA','MA'];
const EVENT_TYPES = ['SHIFT_UP','SHIFT_DOWN','SPREAD_UP','SPREAD_DOWN','PATTERN'];
function real(float $value): string { $text = sprintf('%.4f',$value); return $text === '-0.0000' ? '0.0000' : $text; }
function number_list(array $numbers): string { sort($numbers,SORT_NUMERIC); return $numbers ? implode(' ',$numbers) : 'none'; }
function limits_text(string $label, array $limits): string { return "$label lcl " . real($limits[0]) . ' cl ' . real($limits[1]) . ' ucl ' . real($limits[2]); }
function pair_text(string $family, array $limits): string { return limits_text(FAMILIES[$family][0][0],$limits[0]) . ' ' . limits_text(FAMILIES[$family][0][1],$limits[1]); }
function status(bool $converged): string { return $converged ? 'converged' : 'stopped'; }
function sequences(string $family, array $numbers, array $groups, array $values): array {
    if ($family === 'I_MR') { $points = array_map(fn($i) => $values[$i - 1],$numbers); return [[$numbers,$points],[array_slice($numbers,1),moving_ranges($points)]]; }
    return [[$numbers,array_map(fn($i) => $groups[$i]['mean'],$numbers)],[$numbers,array_map(fn($i) => $groups[$i][$family === 'XBAR_R' ? 'range' : 'sd'],$numbers)]];
}
function estimate_family(string $family, array $groups, array $values, array $settings): array {
    $size = $settings['subgroup_size']; $initial = range(1,$settings['phase1_subgroups'] * ($family === 'I_MR' ? $size : 1)); $retained = $initial; $passes = []; $converged = false;
    for ($pass = 1; $pass <= $settings['max_passes']; $pass++) {
        $limits = variable_limits($family,$retained,$groups,$values,$size); $series = sequences($family,$retained,$groups,$values); $out = [];
        foreach ($series as $index => [$numbers,$points]) foreach ($numbers as $j => $number) if (outside($points[$j],$limits[$index])) $out[$number] = true;
        $outliers = array_keys($out); sort($outliers,SORT_NUMERIC); $passes[] = [count($retained),$limits,$outliers];
        if (!$outliers) { $converged = true; break; } if ($pass === $settings['max_passes']) break;
        $retained = array_values(array_diff($retained,$outliers));
    }
    return ['passes' => $passes,'converged' => $converged,'limits' => $limits,'retained' => $retained,'removed' => array_values(array_diff($initial,$retained))];
}
function signal(string $chart, string $rule, int $start, int $end, float $value, string $direction): array { return compact('chart','rule','start','end','value','direction'); }
function monitor(array &$analysis): void {
    $s = $analysis['settings']; $m = $s['phase1_subgroups']; $n = $s['subgroup_size']; $groups = $analysis['groups']; $values = $analysis['values']; $signals = [];
    foreach (FAMILIES as $family => [, $charts]) {
        $numbers = range($m * ($family === 'I_MR' ? $n : 1) + 1,$family === 'I_MR' ? count($values) : count($groups));
        $series = sequences($family,$numbers,$groups,$values);
        if ($family === 'I_MR') $series[1] = [$numbers,array_map(fn($t) => abs($values[$t - 1] - $values[$t - 2]),$numbers)];
        foreach ($charts as $index => $chart) array_push($signals,...check_rules($chart,$series[$index][0],$series[$index][1],$analysis['estimates'][$family]['limits'][$index],$s['rules'][$chart]));
    }
    $mu = $analysis['estimates']['XBAR_R']['limits'][0][1]; $sigma = $analysis['estimates']['XBAR_R']['limits'][1][1] / CONTROL_CONSTANTS[$n][6] / sqrt($n);
    $reference = $s['cusum_k'] * $sigma; $interval = $s['cusum_h'] * $sigma; $lambda = $s['ewma_lambda']; $rho = $lambda / (2 - $lambda); $q = (1 - $lambda) * (1 - $lambda);
    $ewmaWidth = $s['ewma_l'] * $sigma * sqrt($rho); $maWidth = 3 * $sigma / sqrt($s['ma_span']);
    $upper = $lower = 0.0; $etaUpper = $etaLower = 0; $z = $mu; $factor = 1.0; $cusum = $ewma = $ma = [];
    for ($i = $m + 1; $i <= count($groups); $i++) {
        $mean = $groups[$i]['mean']; $upper = max(0.0,$upper + ($mean - $mu - $reference)); $lower = max(0.0,$lower + ($mu - $mean - $reference));
        $etaUpper = $upper > 0 ? $etaUpper + 1 : 0; $etaLower = $lower > 0 ? $etaLower + 1 : 0; $cusum[$i] = [$upper,$lower];
        if ($upper > $interval) { $signals[] = signal('CUSUM','UPPER',$i - $etaUpper + 1,$i,$upper,'UP'); $upper = 0.0; $etaUpper = 0; }
        if ($lower > $interval) { $signals[] = signal('CUSUM','LOWER',$i - $etaLower + 1,$i,$lower,'DOWN'); $lower = 0.0; $etaLower = 0; }
        $z = $lambda * $mean + (1 - $lambda) * $z; $factor *= $q; $width = $s['ewma_l'] * $sigma * sqrt($rho * (1 - $factor)); $ewma[$i] = [$z,$width];
        if ($z > $mu + $width) $signals[] = signal('EWMA','UPPER',$i,$i,$z,'UP'); elseif ($z < $mu - $width) $signals[] = signal('EWMA','LOWER',$i,$i,$z,'DOWN');
        $start = max($m + 1,$i - $s['ma_span'] + 1); $count = $i - $start + 1; $total = 0; for ($j = $start; $j <= $i; $j++) $total += $groups[$j]['total'];
        $average = $total / ($n * $count); $width = 3 * $sigma / sqrt($count); $ma[$i] = [$average,$width];
        if ($average > $mu + $width) $signals[] = signal('MA','UPPER',$start,$i,$average,'UP'); elseif ($average < $mu - $width) $signals[] = signal('MA','LOWER',$start,$i,$average,'DOWN');
    }
    usort($signals,fn($a,$b) => (array_search($a['chart'],CHART_ORDER,true) <=> array_search($b['chart'],CHART_ORDER,true)) ?: ($a['end'] <=> $b['end']) ?: (array_search($a['rule'],RULE_ORDER,true) <=> array_search($b['rule'],RULE_ORDER,true)));
    foreach ($signals as &$point) $point['subgroup'] = in_array($point['chart'],['I','MR'],true) ? intdiv($point['end'] - 1,$n) + 1 : $point['end']; unset($point);
    $analysis += ['mu' => $mu,'sigma' => $sigma,'reference' => $reference,'interval' => $interval,'ewmaWidth' => $ewmaWidth,'maWidth' => $maWidth,'cusum' => $cusum,'ewma' => $ewma,'ma' => $ma,'signals' => $signals];
}
function group_events(array $analysis): array {
    $s = $analysis['settings']; $numbers = array_values(array_unique(array_column($analysis['signals'],'subgroup'))); sort($numbers,SORT_NUMERIC); $events = [];
    foreach ($numbers as $number) {
        $last = count($events) - 1;
        if ($last < 0 || $number - $events[$last]['end'] - 1 > $s['event_gap']) $events[] = ['start' => $number,'end' => $number]; else $events[$last]['end'] = $number;
    }
    foreach ($events as &$event) {
        $signals = array_values(array_filter($analysis['signals'],fn($point) => $point['subgroup'] >= $event['start'] && $point['subgroup'] <= $event['end'])); $counts = [0,0,0,0,0]; $onsets = [];
        foreach ($signals as $point) {
            $index = $point['direction'] === 'NONE' ? 4 : (in_array($point['chart'],LOCATION_CHARTS,true) ? 0 : 2) + ($point['direction'] === 'DOWN' ? 1 : 0); $counts[$index]++;
            if ($point['chart'] === 'CUSUM') $onsets[] = $point['start'];
        }
        $total = 0; $deviation = 0.0; $out = 0; $length = $event['end'] - $event['start'] + 1;
        for ($i = $event['start']; $i <= $event['end']; $i++) { $group = $analysis['groups'][$i]; $total += $group['total']; $deviation += $group['sd']; foreach ($group['values'] as $value) if ($value < $s['lsl'] || $value > $s['usl']) $out++; }
        $detection = []; foreach (CHART_ORDER as $chart) { $ends = array_column(array_filter($signals,fn($point) => $point['chart'] === $chart),'subgroup'); $detection[$chart] = $ends ? min($ends) : '-'; }
        $event += ['signals' => $signals,'counts' => $counts,'kind' => EVENT_TYPES[array_search(max($counts),$counts,true)],'onset' => $onsets ? min($onsets) : $event['start'],'shift' => ($total / ($s['subgroup_size'] * $length) - $analysis['mu']) / $analysis['sigma'],'spread' => ($deviation / $length) / $analysis['estimates']['XBAR_S']['limits'][1][1],'out' => $out,'detection' => $detection];
    } unset($event);
    return $events;
}
function event_number(array $events, int $subgroup): ?int { foreach ($events as $index => $event) if ($event['start'] <= $subgroup && $subgroup <= $event['end']) return $index + 1; return null; }
function attribute_estimates(array $lots, array $settings): array {
    $charts = [];
    foreach (ATTRIBUTE_CHARTS as $chart) {
        $retained = $lots; $passes = []; $converged = false;
        for ($pass = 1; $pass <= $settings['max_passes']; $pass++) {
            $center = center_line($chart,$retained); $out = [];
            foreach ($retained as $lot) if (lot_point($chart,$lot,$center)['status'] !== 'ok') $out[] = $lot[0];
            $passes[] = [count($retained),$center[0],$out];
            if (!$out) { $converged = true; break; } if ($pass === $settings['max_passes']) break;
            $retained = array_values(array_filter($retained,fn($lot) => !in_array($lot[0],$out,true)));
        }
        $points = array_map(fn($lot) => lot_point($chart,$lot,$center),$lots); $removed = array_values(array_diff(array_column($lots,0),array_column($retained,0)));
        $signals = check_rules($chart,array_column($lots,0),array_column($points,'z'),[-3.0,0.0,3.0],$settings['rules']['STD']);
        $charts[$chart] = ['passes' => $passes,'converged' => $converged,'retained' => count($retained),'removed' => $removed,'points' => $points,'signals' => $signals];
    }
    return $charts;
}
function analyze(): array {
    $settings = read_settings(); $values = array_column(read_rows('measurements.csv'),2); $lots = read_rows('attributes.csv'); $groups = subgroup_statistics($values,$settings['subgroup_size']);
    $a = compact('settings','values','lots','groups'); $a['estimates'] = []; $a['checks'] = [];
    foreach (FAMILIES as $family => [, $charts]) {
        $estimate = $a['estimates'][$family] = estimate_family($family,$groups,$values,$settings); $series = sequences($family,$estimate['retained'],$groups,$values);
        foreach ($charts as $index => $chart) $a['checks'][$chart] = [count($series[$index][0]),check_rules($chart,$series[$index][0],$series[$index][1],$estimate['limits'][$index],$settings['rules'][$chart])];
    }
    monitor($a); $a['events'] = group_events($a); $a['proposed'] = [];
    foreach (FAMILIES as $family => $_) {
        $numbers = $a['estimates'][$family]['retained'];
        for ($i = $settings['phase1_subgroups'] + 1; $i <= count($groups); $i++) if (event_number($a['events'],$i) === null) { if ($family === 'I_MR') array_push($numbers,...range(($i - 1) * $settings['subgroup_size'] + 1,$i * $settings['subgroup_size'])); else $numbers[] = $i; }
        $a['proposed'][$family] = [count($numbers),variable_limits($family,$numbers,$groups,$values,$settings['subgroup_size'])];
    }
    $a['attributes'] = attribute_estimates($lots,$settings);
    $phase2 = range($settings['phase1_subgroups'] + 1,count($groups));
    $a['capability'] = [];
    foreach (['phase1' => $a['estimates']['XBAR_R']['retained'],'phase2' => $phase2] as $name => $numbers) { $selected = array_map(fn($i) => $groups[$i],$numbers); $a['capability'][$name] = [$numbers,capability($selected,$settings)]; }
    $a['rolling'] = [];
    for ($first = $settings['phase1_subgroups'] + 1; $first + $settings['rolling_window'] - 1 <= count($groups); $first += $settings['rolling_step']) { $last = $first + $settings['rolling_window'] - 1; $a['rolling'][] = [$first,$last,capability(array_map(fn($i) => $groups[$i],range($first,$last)),$settings)]; }
    return $a;
}
function limits_lines(array $a): array {
    $s = $a['settings']; $lines = ['characteristic ' . $s['characteristic'],'subgroup_size ' . $s['subgroup_size'],'subgroups ' . count($a['groups']),'samples ' . count($a['values']),'phase1_subgroups ' . $s['phase1_subgroups']];
    foreach ($a['estimates'] as $family => $estimate) {
        $lines[] = "family $family";
        foreach ($estimate['passes'] as $index => [$points,$limits,$out]) $lines[] = 'pass ' . ($index + 1) . " points $points " . pair_text($family,$limits) . ' out ' . number_list($out);
        $lines[] = 'result ' . status($estimate['converged']) . ' passes ' . count($estimate['passes']) . ' retained ' . count($estimate['retained']) . ' removed ' . number_list($estimate['removed']);
    }
    foreach ($a['checks'] as $chart => [$points,$signals]) {
        foreach ($signals as $signal) $lines[] = "phase1_signal $chart {$signal['rule']} {$signal['start']} {$signal['end']} " . real($signal['value']);
        $lines[] = "phase1_check $chart points $points signals " . count($signals);
    }
    foreach ($a['proposed'] as $family => [$points,$limits]) $lines[] = "proposed $family points $points " . pair_text($family,$limits);
    $lines[] = 'cusum target ' . real($a['mu']) . ' sigma ' . real($a['sigma']) . ' k ' . real($a['reference']) . ' h ' . real($a['interval']);
    $lines[] = 'ewma target ' . real($a['mu']) . ' sigma ' . real($a['sigma']) . ' lcl ' . real($a['mu'] - $a['ewmaWidth']) . ' ucl ' . real($a['mu'] + $a['ewmaWidth']);
    $lines[] = 'ma target ' . real($a['mu']) . ' sigma ' . real($a['sigma']) . ' span ' . $s['ma_span'] . ' lcl ' . real($a['mu'] - $a['maWidth']) . ' ucl ' . real($a['mu'] + $a['maWidth']);
    foreach (CHART_ORDER as $chart) {
        $signals = array_values(array_filter($a['signals'],fn($point) => $point['chart'] === $chart)); $ends = array_unique(array_column($signals,'end')); $first = $ends ? min($ends) : 'none';
        $rules = in_array($chart,SHEWHART_CHARTS,true) ? array_map('strval',$s['rules'][$chart]) : ['UPPER','LOWER']; $counts = [];
        foreach ($rules as $rule) $counts[] = "$rule:" . count(array_filter($signals,fn($point) => $point['rule'] === $rule));
        $points = (count($a['groups']) - $s['phase1_subgroups']) * (in_array($chart,['I','MR'],true) ? $s['subgroup_size'] : 1);
        $lines[] = "phase2 $chart points $points signals " . count($signals) . ' signalled ' . count($ends) . " first $first by_rule " . implode(' ',$counts);
    }
    return $lines;
}
function signal_lines(array $signals): array {
    $lines = ['chart,rule,start,end,value,direction'];
    foreach ($signals as $point) $lines[] = implode(',',[$point['chart'],$point['rule'],$point['start'],$point['end'],real($point['value']),$point['direction']]);
    return $lines;
}
function event_lines(array $events): array {
    $lines = ['events ' . count($events)];
    foreach ($events as $index => $event) {
        $number = $index + 1; $parts = []; $charts = [];
        foreach (['location_up','location_down','spread_up','spread_down','pattern'] as $i => $name) $parts[] = "$name {$event['counts'][$i]}";
        foreach ($event['detection'] as $chart => $detection) if ($detection !== '-') $charts[] = $chart;
        $lines[] = "event $number start {$event['start']} end {$event['end']} length " . ($event['end'] - $event['start'] + 1) . ' signals ' . count($event['signals']) . ' charts ' . implode(',',$charts) . ' ' . implode(' ',$parts) . " onset {$event['onset']} shift " . real($event['shift']) . ' spread ' . real($event['spread']) . " out_of_spec {$event['out']} type {$event['kind']}";
        $parts = []; foreach ($event['detection'] as $chart => $detection) $parts[] = "$chart:$detection"; $lines[] = "detection $number " . implode(' ',$parts);
    }
    return $lines;
}
function zone_name(float $value, array $zone): string {
    [$lcl,$cl,$ucl,$u1,$u2,$l1,$l2] = $zone;
    return $value > $ucl ? 'OUT+' : ($value < $lcl ? 'OUT-' : ($value > $u2 ? 'A+' : ($value > $u1 ? 'B+' : ($value > $cl ? 'C+' : ($value < $l2 ? 'A-' : ($value < $l1 ? 'B-' : ($value < $cl ? 'C-' : 'C0')))))));
}
function subgroup_lines(array $a): array {
    $lines = ['subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event']; $zone = zones($a['estimates']['XBAR_R']['limits'][0]);
    foreach ($a['groups'] as $i => $group) {
        $phase = $i > $a['settings']['phase1_subgroups'] ? 'phase2' : (in_array($i,$a['estimates']['XBAR_R']['removed'],true) ? 'excluded' : 'phase1');
        $trace = $phase === 'phase2' ? [real($a['cusum'][$i][0]),real($a['cusum'][$i][1]),real($a['ewma'][$i][0]),real($a['ma'][$i][0])] : ['-','-','-','-'];
        $count = count(array_filter($a['signals'],fn($point) => $point['subgroup'] === $i));
        $lines[] = implode(',',[$i,$phase,real($group['mean']),zone_name($group['mean'],$zone),$group['range'],real($group['sd']),...$trace,$count,event_number($a['events'],$i) ?? '-']);
    }
    return $lines;
}
function attribute_lines(array $a): array {
    $lines = [];
    foreach ($a['attributes'] as $chart => $result) {
        $lines[] = "chart $chart";
        foreach ($result['passes'] as $i => [$count,$center,$out]) $lines[] = 'pass ' . ($i + 1) . " lots $count center " . real($center) . ' out ' . number_list($out);
        $lines[] = 'result ' . status($result['converged']) . ' passes ' . count($result['passes']) . " retained {$result['retained']} removed " . number_list($result['removed']);
        foreach ($result['points'] as $i => $point) {
            $value = in_array($chart,['np','c'],true) ? (string)$point['value'] : real($point['value']); $lot = $a['lots'][$i];
            $lines[] = "lot {$lot[0]} size {$lot[1]} value $value lcl " . real($point['lcl']) . ' ucl ' . real($point['ucl']) . ' z ' . real($point['z']) . " status {$point['status']}";
        }
        foreach ($result['signals'] as $point) $lines[] = "signal {$point['rule']} {$point['start']} {$point['end']} " . real($point['value']);
        $lines[] = 'signals ' . count($result['signals']);
    }
    return $lines;
}
function capability_lines(array $a): array {
    $s = $a['settings']; $lines = [];
    foreach ($a['capability'] as $name => [$numbers,$result]) {
        $lines[] = "group $name subgroups " . count($numbers) . " values {$result['count']}";
        foreach ($result['metrics'] as $label => $value) $lines[] = "$label " . real($value);
        foreach (['cpk_ci','ppk_ci'] as $label) $lines[] = "$label " . real($result[$label][0]) . ' ' . real($result[$label][1]);
        $lines[] = "below_lsl {$result['below']}"; $lines[] = "above_usl {$result['above']}"; $lines[] = 'ppm ' . real($result['ppm']);
        foreach ($numbers as $i) foreach ($a['groups'][$i]['values'] as $j => $value) if ($value < $s['lsl'] || $value > $s['usl']) $lines[] = 'out_of_spec sample ' . (($i - 1) * $s['subgroup_size'] + $j + 1) . " subgroup $i value $value side " . ($value < $s['lsl'] ? 'low' : 'high');
        $lines[] = 'verdict ' . $result['verdict'];
        foreach ($result['bins'] as [$lower,$upper,$frequency,$length,$marks]) $lines[] = "bin $lower $upper $frequency" . ($length ? ' ' . str_repeat('#',$length) : '') . ($marks ? ' ' . implode(' ',$marks) : '');
    }
    foreach ($a['rolling'] as [$first,$last,$result]) {
        $parts = []; foreach (['mean','sigma_within','sigma_overall','cpk','ppk'] as $label) $parts[] = "$label " . real($result['metrics'][$label]);
        $lines[] = "rolling $first $last " . implode(' ',$parts) . ' verdict ' . $result['verdict'];
    }
    return $lines;
}
function has_signal(array $a, string $chart, int $end, ?string $rule = null): bool { foreach ($a['signals'] as $point) if ($point['chart'] === $chart && $point['end'] === $end && ($rule === null || $point['rule'] === $rule)) return true; return false; }
function chart_lines(array $a): array {
    $lines = []; $s = $a['settings'];
    foreach ([['XBAR','XBAR_R',0,'mean','XBAR_R'],['R','XBAR_R',1,'range','R'],['S','XBAR_S',1,'sd','S']] as [$picture,$family,$index,$field,$chart]) {
        $limits = $a['estimates'][$family]['limits'][$index]; $lines[] = limits_text("chart $picture",$limits);
        foreach ($a['groups'] as $i => $group) {
            $mark = $i > $s['phase1_subgroups'] ? '2' : (in_array($i,$a['estimates'][$family]['removed'],true) ? 'x' : '1');
            $lines[] = sprintf('%3d',$i) . " $mark " . limits_band($limits,$group[$field],$mark === '2' && has_signal($a,$chart,$i)) . ' ' . real($group[$field]);
        }
    }
    $lines[] = 'chart CUSUM h ' . real($a['interval']);
    foreach ($a['cusum'] as $i => [$upper,$lower]) $lines[] = sprintf('%3d',$i) . ' ' . cusum_band($upper,$lower,$a['interval'],has_signal($a,'CUSUM',$i,'UPPER'),has_signal($a,'CUSUM',$i,'LOWER')) . ' ' . real($upper) . ' ' . real($lower);
    foreach (['EWMA' => ['ewma','ewmaWidth'],'MA' => ['ma','maWidth']] as $chart => [$trace,$widthKey]) {
        $scale = $a[$widthKey]; $lines[] = limits_text("chart $chart",[$a['mu'] - $scale,$a['mu'],$a['mu'] + $scale]);
        foreach ($a[$trace] as $i => [$value,$width]) $lines[] = sprintf('%3d',$i) . ' ' . width_band($scale,$width,$value,$a['mu'],has_signal($a,$chart,$i)) . ' ' . real($value) . ' ' . real($a['mu'] - $width) . ' ' . real($a['mu'] + $width);
    }
    foreach ($a['attributes'] as $chart => $result) {
        $lines[] = 'chart ' . strtoupper($chart) . '_STD lcl -3.0000 cl 0.0000 ucl 3.0000';
        foreach ($result['points'] as $i => $point) $lines[] = sprintf('%3d',$a['lots'][$i][0]) . ' ' . standard_band($point['z'],$point['status'] === 'ok') . ' ' . real($point['z']);
    }
    return $lines;
}

$analysis = analyze();
if (!is_dir('output')) mkdir('output',0777,true);
foreach (['limits.txt' => limits_lines($analysis),'signals.csv' => signal_lines($analysis['signals']),'events.txt' => event_lines($analysis['events']),'subgroups.csv' => subgroup_lines($analysis),'attribute_charts.txt' => attribute_lines($analysis),'capability.txt' => capability_lines($analysis),'charts.txt' => chart_lines($analysis)] as $name => $lines) file_put_contents("output/$name",implode("\n",$lines) . "\n");
