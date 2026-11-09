<?php

function readPgm(string $path): array
{
    $lines = file($path, FILE_IGNORE_NEW_LINES);
    [$width, $height] = array_map('intval', explode(' ', $lines[1]));
    $pixels = [];
    foreach (array_slice($lines, 3) as $line) foreach (explode(' ', $line) as $value) $pixels[] = (int)$value;
    return compact('width', 'height', 'pixels');
}

function readParameters(string $path): array
{
    $params = ['samplePixels' => []];
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
        $values = explode(' ', $line);
        $key = array_shift($values);
        if ($key === 'sample') $params['samplePixels'][] = array_map('intval', $values);
        elseif (in_array($key, ['wta_cost', 'sgm_cost'], true)) $params[$key] = $values[0];
        elseif (in_array($key, ['sad_windows', 'ssd_windows', 'census_windows'], true)) $params[$key] = array_map('intval', $values);
        else $params[$key] = (int)$values[0];
    }
    return $params;
}

function writePgm(string $path, int $width, int $height, array $pixels): void
{
    $lines = ['P2', $width . ' ' . $height, '255'];
    for ($y = 0; $y < $height; $y++) $lines[] = implode(' ', array_slice($pixels, $y * $width, $width));
    file_put_contents($path, implode("\n", $lines) . "\n");
}
