<?php

function decimal($value, $digits = 3)
{
    $result = sprintf('%.' . $digits . 'F', $value);
    return $result === ('-0.' . str_repeat('0', $digits)) ? substr($result, 1) : $result;
}
function named($items)
{
    $result = [];
    foreach ($items as $key => $value) $result[] = $key . '=' . $value;
    return implode(' ', $result);
}
function chart($lines)
{
    $border = '+' . str_repeat('-', strlen($lines[0])) . '+'; $result = [$border];
    foreach ($lines as $line) $result[] = '|' . $line . '|';
    $result[] = $border;
    return $result;
}
function signed($value) { return $value > 0 ? '+' . $value : (string) $value; }
function write_lines($filename, $lines)
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    file_put_contents('output/' . $filename, $lines ? implode("\n", $lines) . "\n" : '');
}
