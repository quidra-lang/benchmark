<?php

function level($model, $time) {
    $value = $model->mean;
    foreach ($model->constituents as $constituent) {
        $theta = angle($constituent->speed, $time);
        $value += $constituent->a * cos($theta) + $constituent->b * sin($theta);
    }
    return $value;
}

function gridExtrema($model, $start, $hours, $spacing) {
    $count = intdiv($hours * 60, $spacing);
    $values = [];
    for ($index = 0; $index <= $count; $index++) $values[] = level($model, (60 * $start + $index * $spacing) / 60);
    $extrema = [];
    for ($index = 1; $index < $count; $index++) {
        $previous = $values[$index - 1];
        $current = $values[$index];
        $next = $values[$index + 1];
        if ($previous < $current && $current > $next) $kind = 'high';
        elseif ($previous > $current && $current < $next) $kind = 'low';
        else continue;
        $delta = ($previous - $next) / (2 * ($previous - 2 * $current + $next));
        $extrema[] = (object)['kind' => $kind, 'refinedMinute' => 60 * $start + $index * $spacing + $delta * $spacing,
            'height' => $current - ($previous - $next) * $delta / 4];
    }
    return $extrema;
}
