<?php
declare(strict_types=1);

namespace IniValidator;

const MASK = '********';

function stringNotation(string $text): string
{
    return '"' . strtr($text, ['\\' => '\\\\', '"' => '\\"', "\n" => '\\n', "\t" => '\\t']) . '"';
}

function valueNotation(string $kind, ?string $itemKind, mixed $value): string
{
    if ($kind === 'list') {
        $items = array_map(static fn ($item) => valueNotation($itemKind, null, $item), $value);
        return '[' . implode(', ', $items) . ']';
    }
    if ($kind === 'string') {
        return stringNotation($value);
    }
    if ($kind === 'bool') {
        return $value ? 'true' : 'false';
    }
    return (string) $value;
}

function shown(OutputKey $output): string
{
    return $output->secret ? MASK : $output->notation;
}

function originText(array $origin): string
{
    return $origin[0] . ':' . $origin[1];
}

function normalizedBlock(Profile $profile): array
{
    $lines = ['profile ' . $profile->name];
    $previous = null;
    foreach (orderedKeys(array_keys($profile->outputs)) as $key) {
        [$section, $name] = splitKey($key);
        if ($section !== $previous) {
            $lines[] = "[$section]";
            $previous = $section;
        }
        $lines[] = $name . ' = ' . shown($profile->outputs[$key]);
    }
    return $lines;
}

function diagnosticsBlock(Profile $profile): array
{
    $lines = ["profile {$profile->name} errors {$profile->errors} warnings {$profile->warnings}"];
    foreach ($profile->diagnostics as [$document, $line, $code, $message]) {
        $lines[] = "$document:$line $code $message";
    }
    return $lines;
}

function diffBlock(ProfileDiff $diff): array
{
    $lines = ["diff {$diff->first} -> {$diff->second}: {$diff->added} added, " .
        "{$diff->removed} removed, {$diff->changed} changed"];
    foreach ($diff->entries as [$sign, $key, $before, $after]) {
        $lines[] = match ($sign) {
            '+' => "+ $key = " . shown($after),
            '-' => "- $key = " . shown($before),
            '~' => "~ $key: " . shown($before) . ' -> ' . shown($after),
        };
    }
    return $lines;
}

function reportBlock(Profile $profile): array
{
    $lines = ['profile ' . $profile->name, 'includes'];
    foreach ($profile->tree as [$depth, $text]) {
        $lines[] = str_repeat('  ', $depth + 1) . $text;
    }
    $lines[] = 'overridden';
    foreach ($profile->overridden as [$key, $history]) {
        $lines[] = "  $key: " . implode(' -> ', array_map(originText(...), $history));
    }
    if ($profile->overridden === []) {
        $lines[] = '  (none)';
    }
    $lines[] = 'keys ' . count($profile->outputs) . " documents {$profile->documentKeys} " .
        "manifest {$profile->manifestKeys} defaults {$profile->defaultKeys}";
    $lines[] = "dropped {$profile->dropped}";
    $lines[] = "errors {$profile->errors} warnings {$profile->warnings}";
    return $lines;
}

function writeBlocks(string $path, array $blocks): void
{
    $text = implode("\n\n", array_map(static fn (array $lines) => implode("\n", $lines), $blocks));
    file_put_contents($path, $text . "\n");
}

function writeOutputs(string $directory, array $profiles, array $diffs): void
{
    if (!is_dir($directory)) {
        mkdir($directory, 0777, true);
    }
    writeBlocks($directory . '/normalized.txt', array_map(normalizedBlock(...), $profiles));
    writeBlocks($directory . '/diagnostics.txt', array_map(diagnosticsBlock(...), $profiles));
    writeBlocks($directory . '/diff.txt', array_map(diffBlock(...), $diffs));
    writeBlocks($directory . '/report.txt', array_map(reportBlock(...), $profiles));
}
