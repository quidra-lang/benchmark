<?php
function capability_indices(float $mean, float $sigma, array $settings): array {
    $potential = ($settings['usl'] - $settings['lsl']) / (6 * $sigma); $upper = ($settings['usl'] - $mean) / (3 * $sigma); $lower = ($mean - $settings['lsl']) / (3 * $sigma);
    return [$potential,$upper,$lower,min($upper,$lower)];
}
function confidence_interval(float $index, int $count, float $z): array { $delta = $z * sqrt(1 / (9 * $count) + $index * $index / (2 * ($count - 1))); return [$index - $delta,$index + $delta]; }
function capability(array $groups, array $settings): array {
    $values = []; foreach ($groups as $group) array_push($values, ...$group['values']); $count = count($values); $mean = array_sum($values) / $count;
    $rbar = array_sum(array_column($groups, 'range')) / count($groups); $sbar = real_sum(array_column($groups, 'sd')) / count($groups); $constants = CONTROL_CONSTANTS[$settings['subgroup_size']];
    $within = $rbar / $constants[6]; $sdev = $sbar / $constants[7]; $squares = 0.0; foreach ($values as $value) $squares += ($value - $mean) * ($value - $mean); $overall = sqrt($squares / ($count - 1));
    [$cp,$cpu,$cpl,$cpk] = capability_indices($mean, $within, $settings); [$pp,$ppu,$ppl,$ppk] = capability_indices($mean, $overall, $settings);
    $offset = $mean - $settings['target']; $cpm = ($settings['usl'] - $settings['lsl']) / (6 * sqrt($overall * $overall + $offset * $offset));
    $below = count(array_filter($values, fn($v) => $v < $settings['lsl'])); $above = count(array_filter($values, fn($v) => $v > $settings['usl'])); $ppm = 1000000 * ($below + $above) / $count;
    $verdict = $cpk >= 1.33 ? 'capable' : ($cpk >= 1.0 ? 'marginal' : 'incapable');
    $metrics = ['mean' => $mean,'sigma_within' => $within,'sigma_sbar' => $sdev,'sigma_overall' => $overall,'cp' => $cp,'cpu' => $cpu,'cpl' => $cpl,'cpk' => $cpk,'pp' => $pp,'ppu' => $ppu,'ppl' => $ppl,'ppk' => $ppk,'cpm' => $cpm];
    return ['count' => $count,'metrics' => $metrics,'cpk_ci' => confidence_interval($cpk,$count,$settings['ci_z']),'ppk_ci' => confidence_interval($ppk,$count,$settings['ci_z']),'below' => $below,'above' => $above,'ppm' => $ppm,'verdict' => $verdict,'bins' => histogram($values,$settings)];
}
function histogram(array $values, array $settings): array {
    $width = $settings['histogram_bin']; $low = intdiv(min(min($values),$settings['lsl']),$width) * $width; $high = intdiv(max(max($values),$settings['usl']),$width) * $width + $width;
    $frequencies = array_fill(0,intdiv($high - $low,$width),0); foreach ($values as $value) $frequencies[intdiv($value - $low,$width)]++;
    $top = max($frequencies); $bins = [];
    foreach ($frequencies as $index => $frequency) {
        $lower = $low + $index * $width; $upper = $lower + $width - 1; $marks = [];
        foreach (['lsl' => $settings['lsl'],'target' => $settings['target'],'usl' => $settings['usl']] as $name => $point) if ($lower <= $point && $point <= $upper) $marks[] = $name;
        $bins[] = [$lower,$upper,$frequency,intdiv(50 * $frequency + $top - 1,$top),$marks];
    }
    return $bins;
}
