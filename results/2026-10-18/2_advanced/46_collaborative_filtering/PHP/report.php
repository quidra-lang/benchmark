<?php

function formatReal($value): string
{
    if ($value === null) {
        return '-';
    }
    $text = sprintf('%.4F', $value);
    return $text === '-0.0000' ? '0.0000' : $text;
}

function writeLines(string $filename, array $lines): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
}
