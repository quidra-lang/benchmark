<?php
declare(strict_types=1);

namespace TimezoneRules;

function localText(int $time): string { return sprintf('%04d-%02d-%02dT%02d:%02d:%02d', ...splitTime($time)); }
function utText(int $time): string { return localText($time) . 'Z'; }

function offsetText(int $value): string
{
    $sign = $value < 0 ? '-' : '+';
    $value = abs($value);
    $text = sprintf('%s%02d:%02d', $sign, intdiv($value, 3600), intdiv($value, 60) % 60);
    return $value % 60 === 0 ? $text : $text . sprintf(':%02d', $value % 60);
}

function durationText(int $value): string
{
    $sign = $value < 0 ? '-' : '';
    $value = abs($value);
    return sprintf('%s%d:%02d:%02d', $sign, intdiv($value, 3600), intdiv($value, 60) % 60, $value % 60);
}

function clockText(int $value): string
{
    $text = sprintf('%d:%02d', intdiv($value, 3600), intdiv($value, 60) % 60);
    return $value % 60 === 0 ? $text : $text . sprintf(':%02d', $value % 60);
}

function stateText(Period $period): string { return offsetText($period->offset) . ' ' . ($period->dst ? 'DST' : 'STD') . ' ' . $period->abbreviation; }
function changeText(int $time, Period $before, Period $after): string { return utText($time) . ' ' . stateText($before) . ' -> ' . stateText($after); }
function writeLines(string $path, array $lines): void { file_put_contents($path, $lines === [] ? '' : implode("\n", $lines) . "\n"); }

function writeBlocks(string $path, array $blocks): void
{
    $lines = [];
    foreach ($blocks as $index => $block) {
        if ($index > 0) {
            $lines[] = '';
        }
        array_push($lines, ...$block);
    }
    writeLines($path, $lines);
}
