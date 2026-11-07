<?php

function sign_value($value) { return $value > 0 ? 1 : -1; }

function fixed($value, $digits)
{
    $text = sprintf('%.' . $digits . 'F', $value);
    return $text === ('-0.' . str_repeat('0', $digits)) ? substr($text, 1) : $text;
}

function ratio($a, $b) { return $b > 0 ? fixed($a / $b, 4) : '-'; }

function folds($count, $k)
{
    $result = [];
    for ($fold = 0; $fold < $k; $fold++) {
        $train = [];
        $test = [];
        for ($i = 0; $i < $count; $i++) {
            if ($i % $k === $fold) $test[] = $i;
            else $train[] = $i;
        }
        $result[] = compact('train', 'test');
    }
    return $result;
}

function binary($labels, $decisions)
{
    $tp = 0; $fp = 0; $tn = 0; $fn = 0;
    foreach ($labels as $i => $label) {
        if (sign_value($decisions[$i]) === 1) {
            if ($label === 1) $tp++; else $fp++;
        } elseif ($label === -1) $tn++; else $fn++;
    }
    return ['tp' => $tp, 'fp' => $fp, 'tn' => $tn, 'fn' => $fn, 'correct' => $tp + $tn];
}

function auc($labels, $decisions)
{
    $sum = 0.0; $positives = 0; $negatives = 0;
    foreach ($labels as $label) { if ($label === 1) $positives++; else $negatives++; }
    foreach ($labels as $i => $label) if ($label === 1) foreach ($labels as $j => $other) if ($other === -1) {
        if ($decisions[$i] > $decisions[$j]) $sum += 1;
        elseif ($decisions[$i] == $decisions[$j]) $sum += 0.5;
    }
    return $sum / ($positives * $negatives);
}

function confusion($classes, $predictions)
{
    $counts = array_fill(0, 3, [0, 0, 0]);
    foreach ($classes as $i => $class) $counts[$class - 1][$predictions[$i] - 1]++;
    return $counts;
}

function write_output($path, $lines)
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    file_put_contents('output/' . $path, implode("\n", $lines) . "\n");
}
