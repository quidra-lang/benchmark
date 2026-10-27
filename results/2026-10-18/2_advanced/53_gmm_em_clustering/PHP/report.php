<?php

function real($value, $places = 4) {
    if ($value === null) return '-';
    $text = sprintf('%.' . $places . 'F', abs($value));
    return $value < 0 && (float)$text != 0.0 ? '-' . $text : $text;
}

function frame($rows) {
    $border = '+' . str_repeat('-', count($rows[0])) . '+';
    $lines = [$border];
    foreach ($rows as $row) $lines[] = '|' . implode('', $row) . '|';
    $lines[] = $border;
    return $lines;
}

function writeLines($name, $lines) {
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
