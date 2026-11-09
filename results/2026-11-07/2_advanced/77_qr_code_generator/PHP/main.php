<?php

require_once __DIR__ . '/bitstream.php';
require_once __DIR__ . '/reed_solomon.php';
require_once __DIR__ . '/matrix.php';
require_once __DIR__ . '/masking.php';
require_once __DIR__ . '/render.php';

const MODES = ['NUMERIC', 'ALPHANUMERIC', 'BYTE'];
const LEVELS = ['L', 'M', 'Q', 'H'];
const INDICATORS = ['NUMERIC' => 1, 'ALPHANUMERIC' => 2, 'BYTE' => 4];

function readLines(string $path): array
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function hexadecimal(array $values): string
{
    $text = '';
    foreach ($values as $value) {
        $text .= sprintf('%02x', $value);
    }
    return $text;
}

function writeLines(string $path, array $lines): void
{
    file_put_contents($path, $lines ? implode("\n", $lines) . "\n" : '');
}

function placementOrder(array $lengths, int $degree): array
{
    $order = [];
    for ($i = 0; $i < max($lengths); $i++) {
        foreach ($lengths as $block => $length) {
            if ($i < $length) {
                $order[] = [$block, $i];
            }
        }
    }
    for ($i = 0; $i < $degree; $i++) {
        foreach ($lengths as $block => $length) {
            $order[] = [$block, $length + $i];
        }
    }
    return $order;
}

function readInputs(): object
{
    $requests = [];
    foreach (readLines('input/requests.txt') as $line) {
        $separator = strpos($line, ':');
        [$id, $level, $mode, $version, $mask] = explode(' ', substr($line, 0, $separator));
        $requests[] = (object) ['id' => $id, 'level' => $level, 'mode' => $mode, 'version' => $version,
            'mask' => $mask, 'text' => substr($line, $separator + 1)];
    }
    $settings = readLines('input/params.txt');
    $quiet = (int) explode(' ', $settings[0])[1];
    $scale = (int) explode(' ', $settings[1])[1];
    $tables = [];
    for ($version = 0; $version <= 10; $version++) {
        $tables[] = (object) ['blocks' => [], 'centers' => []];
    }
    foreach (readLines('input/tables.txt') as $line) {
        $fields = explode(' ', $line);
        $version = (int) $fields[1];
        if ($fields[0] === 'align') {
            $tables[$version]->centers = array_map('intval', array_slice($fields, 2));
        } else {
            [$e, $b1, $k1, $b2, $k2] = array_map('intval', array_slice($fields, 3));
            $lengths = array_merge(array_fill(0, $b1, $k1), array_fill(0, $b2, $k2));
            $data = $b1 * $k1 + $b2 * $k2;
            $tables[$version]->blocks[$fields[2]] = (object) ['e' => $e, 'lengths' => $lengths, 'data' => $data,
                'total' => $data + $e * count($lengths), 'placement' => placementOrder($lengths, $e)];
        }
    }
    for ($version = 1; $version <= 10; $version++) {
        $tables[$version]->layout = createMatrix($version, $tables[$version]->centers);
    }
    $damage = [];
    foreach (readLines('input/damage.txt') as $line) {
        $parts = explode(' ', $line);
        $id = array_shift($parts);
        $kind = array_shift($parts);
        $damage['#' . $id][] = (object) ['kind' => $kind, 'args' => $parts];
    }
    $scanLines = readLines('input/scans.txt');
    $scans = [];
    for ($i = 0; $i < count($scanLines);) {
        $name = explode(' ', $scanLines[$i++])[1];
        $size = strlen($scanLines[$i]);
        $grid = [];
        for ($y = 0; $y < $size; $y++) {
            $row = [];
            for ($x = 0; $x < $size; $x++) {
                $row[] = $scanLines[$i + $y][$x] === '#' ? 1 : 0;
            }
            $grid[] = $row;
        }
        $scans[] = (object) ['name' => $name, 'grid' => $grid];
        $i += $size;
    }
    return (object) ['requests' => $requests, 'quiet' => $quiet, 'scale' => $scale,
        'tables' => $tables, 'damage' => $damage, 'scans' => $scans];
}

function encodable(string $character, string $mode): bool
{
    if ($mode === 'NUMERIC') {
        return ord($character) >= 48 && ord($character) <= 57;
    }
    return $mode !== 'ALPHANUMERIC' || strpos(ALPHANUMERIC, $character) !== false;
}

function countWidth(string $mode, int $version): int
{
    return $version <= 9 ? ['NUMERIC' => 10, 'ALPHANUMERIC' => 9, 'BYTE' => 8][$mode]
        : ['NUMERIC' => 12, 'ALPHANUMERIC' => 11, 'BYTE' => 16][$mode];
}

function dataWidth(string $mode, int $count): int
{
    if ($mode === 'NUMERIC') {
        return 10 * intdiv($count, 3) + [0, 4, 7][$count % 3];
    }
    if ($mode === 'ALPHANUMERIC') {
        return 11 * intdiv($count, 2) + 6 * ($count % 2);
    }
    return 8 * $count;
}

function splitSegments(string $text, string $mode, int $version): object
{
    $length = strlen($text);
    if ($mode !== 'MIXED') {
        return (object) ['segments' => [(object) ['mode' => $mode, 'text' => $text]],
            'bits' => 4 + countWidth($mode, $version) + dataWidth($mode, $length)];
    }
    $invalid = [];
    foreach (MODES as $candidate) {
        $prefix = [0];
        for ($i = 0; $i < $length; $i++) {
            $prefix[] = $prefix[$i] + (encodable($text[$i], $candidate) ? 0 : 1);
        }
        $invalid[] = $prefix;
    }
    $costs = [0];
    $choices = [null];
    for ($i = 1; $i <= $length; $i++) {
        $best = null;
        $choice = null;
        for ($j = 0; $j < $i; $j++) {
            foreach (MODES as $m => $candidate) {
                if ($invalid[$m][$i] !== $invalid[$m][$j]) {
                    continue;
                }
                $cost = $costs[$j] + 4 + countWidth($candidate, $version) + dataWidth($candidate, $i - $j);
                if ($best === null || $cost < $best) {
                    $best = $cost;
                    $choice = (object) ['start' => $j, 'mode' => $candidate];
                }
            }
        }
        $costs[] = $best;
        $choices[] = $choice;
    }
    $segments = [];
    for ($i = $length; $i > 0;) {
        $choice = $choices[$i];
        $segments[] = (object) ['mode' => $choice->mode, 'text' => substr($text, $choice->start, $i - $choice->start)];
        $i = $choice->start;
    }
    return (object) ['segments' => array_reverse($segments), 'bits' => $costs[$length]];
}

function resolveRequest(object $request, array $tables): object
{
    $validLevel = false;
    foreach (LEVELS as $level) {
        if ($request->level === $level || $request->level === $level . '+') {
            $validLevel = true;
        }
    }
    if (!$validLevel) {
        return (object) ['error' => 'level ' . $request->level];
    }
    if (!in_array($request->mode, array_merge(MODES, ['AUTO', 'MIXED']), true)) {
        return (object) ['error' => 'mode ' . $request->mode];
    }
    if (!preg_match('/\A(?:AUTO|[1-9]|10)\z/', $request->version)) {
        return (object) ['error' => 'version ' . $request->version];
    }
    if (!preg_match('/\A(?:AUTO|[0-7])\z/', $request->mask)) {
        return (object) ['error' => 'mask ' . $request->mask];
    }
    if ($request->text === '') {
        return (object) ['error' => 'text'];
    }
    if ($request->mode === 'NUMERIC' || $request->mode === 'ALPHANUMERIC') {
        for ($i = 0; $i < strlen($request->text); $i++) {
            if (!encodable($request->text[$i], $request->mode)) {
                return (object) ['error' => 'charset position ' . $i];
            }
        }
    }
    $mode = $request->mode;
    if ($mode === 'AUTO') {
        foreach (MODES as $candidate) {
            $valid = true;
            for ($i = 0; $i < strlen($request->text); $i++) {
                if (!encodable($request->text[$i], $candidate)) {
                    $valid = false;
                    break;
                }
            }
            if ($valid) {
                $mode = $candidate;
                break;
            }
        }
    }
    $cache = [];
    $split = function (string $candidate, int $version) use (&$cache, $request): object {
        $key = $candidate . '/' . ($version === 10 ? 10 : 1);
        if (!isset($cache[$key])) {
            $cache[$key] = splitSegments($request->text, $candidate, $version);
        }
        return $cache[$key];
    };
    $candidates = $request->version === 'AUTO' ? range(1, 10) : [(int) $request->version];
    $base = $request->level[0];
    $version = null;
    foreach ($candidates as $candidate) {
        if ($split($mode, $candidate)->bits <= 8 * $tables[$candidate]->blocks[$base]->data) {
            $version = $candidate;
            break;
        }
    }
    if ($version === null) {
        $last = $candidates[count($candidates) - 1];
        return (object) ['error' => 'capacity bits ' . $split($mode, $last)->bits . ' capacity ' . (8 * $tables[$last]->blocks[$base]->data)];
    }
    $selected = $split($mode, $version);
    $level = $base;
    if (str_ends_with($request->level, '+')) {
        foreach (array_slice(LEVELS, array_search($base, LEVELS, true)) as $candidate) {
            if ($selected->bits <= 8 * $tables[$version]->blocks[$candidate]->data) {
                $level = $candidate;
            }
        }
    }
    return (object) ['request' => $request, 'mode' => $mode, 'version' => $version, 'level' => $level, 'split' => $split,
        'segments' => $selected->segments, 'bits' => $selected->bits, 'table' => $tables[$version]->blocks[$level],
        'layout' => $tables[$version]->layout];
}

function groups(string $text, string $mode): array
{
    $size = $mode === 'NUMERIC' ? 3 : ($mode === 'ALPHANUMERIC' ? 2 : 1);
    $result = [];
    for ($i = 0; $i < strlen($text); $i += $size) {
        $characters = substr($text, $i, $size);
        if ($mode === 'NUMERIC') {
            $value = (int) $characters;
        } elseif ($mode === 'ALPHANUMERIC') {
            $value = strpos(ALPHANUMERIC, $characters[0]);
            if (strlen($characters) === 2) {
                $value = 45 * $value + strpos(ALPHANUMERIC, $characters[1]);
            }
        } else {
            $value = ord($characters[0]);
        }
        $result[] = (object) ['characters' => $characters, 'value' => $value, 'width' => dataWidth($mode, strlen($characters))];
    }
    return $result;
}

function padBits(array $bits, int $capacity): object
{
    $padded = $bits;
    $terminator = min(4, $capacity - count($bits));
    for ($i = 0; $i < $terminator; $i++) {
        $padded[] = 0;
    }
    $zeroFill = 0;
    $padBytes = 0;
    while (count($padded) % 8 !== 0) {
        $padded[] = 0;
        $zeroFill++;
    }
    while (count($padded) < $capacity) {
        appendBits($padded, $padBytes % 2 === 0 ? 0xec : 0x11, 8);
        $padBytes++;
    }
    return (object) ['bits' => $padded, 'terminator' => $terminator, 'zeroFill' => $zeroFill, 'padBytes' => $padBytes];
}

function encodeRequest(object $resolved): object
{
    $request = $resolved->request;
    $version = $resolved->version;
    $level = $resolved->level;
    $table = $resolved->table;
    $layout = $resolved->layout;
    $capacity = 8 * $table->data;
    $bits = [];
    $bitLines = ['request ' . $request->id . ' version ' . $version . ' bits ' . $resolved->bits . ' capacity ' . $capacity];
    foreach ($resolved->segments as $segment) {
        $width = countWidth($segment->mode, $version);
        $indicator = INDICATORS[$segment->mode];
        appendBits($bits, $indicator, 4);
        appendBits($bits, strlen($segment->text), $width);
        $bitLines[] = 'segment ' . $segment->mode . ' indicator ' . binary($indicator, 4) . ' count ' . strlen($segment->text)
            . ' ' . binary(strlen($segment->text), $width);
        foreach (groups($segment->text, $segment->mode) as $group) {
            appendBits($bits, $group->value, $group->width);
            $bitLines[] = 'group ' . $group->value . ' ' . binary($group->value, $group->width) . ' "' . $group->characters . '"';
        }
    }
    $padded = padBits($bits, $capacity);
    $data = toCodewords($padded->bits);
    $bitLines[] = 'terminator ' . $padded->terminator . ' zero_fill ' . $padded->zeroFill . ' pad_bytes ' . $padded->padBytes;
    $blocks = [];
    $offset = 0;
    foreach ($table->lengths as $length) {
        $blockData = array_slice($data, $offset, $length);
        $ec = rsEncode($blockData, $table->e);
        $blocks[] = (object) ['data' => $blockData, 'ec' => $ec, 'words' => array_merge($blockData, $ec)];
        $offset += $length;
    }
    $interleaved = [];
    foreach ($table->placement as [$block, $position]) {
        $interleaved[] = $blocks[$block]->words[$position];
    }
    $placedBits = fromCodewords($interleaved);
    $unmasked = $layout->grid;
    foreach ($layout->order as $i => [$x, $y]) {
        $unmasked[$y][$x] = $i < count($placedBits) ? $placedBits[$i] : 0;
    }
    $symbols = [];
    $penalties = [];
    for ($mask = 0; $mask < 8; $mask++) {
        $grid = applyMask($unmasked, $layout->areas, $mask);
        $information = formatInformation($level, $mask);
        foreach ($layout->locations->format as $locations) {
            writeValue($grid, $locations, $information);
        }
        $symbols[] = $grid;
        $penalties[] = penalties($grid);
    }
    $mask = $request->mask === 'AUTO' ? 0 : (int) $request->mask;
    if ($request->mask === 'AUTO') {
        for ($candidate = 1; $candidate < 8; $candidate++) {
            if ($penalties[$candidate]->total < $penalties[$mask]->total) {
                $mask = $candidate;
            }
        }
    }
    $encoded = clone $resolved;
    $encoded->blocks = $blocks;
    $encoded->interleaved = $interleaved;
    $encoded->bitLines = $bitLines;
    $encoded->penalties = $penalties;
    $encoded->mask = $mask;
    $encoded->grid = $symbols[$mask];
    $encoded->dark = $penalties[$mask]->dark;
    return $encoded;
}

function generationReports(object $encoded, array $tables, object $output): void
{
    $request = $encoded->request;
    $version = $encoded->version;
    $table = $encoded->table;
    $layout = $encoded->layout;
    $split = $encoded->split;
    $alternatives = [];
    foreach (MODES as $candidate) {
        $valid = true;
        for ($i = 0; $i < strlen($request->text); $i++) {
            if (!encodable($request->text[$i], $candidate)) {
                $valid = false;
                break;
            }
        }
        $alternatives[] = $valid ? 4 + countWidth($candidate, $version) + dataWidth($candidate, strlen($request->text)) : '-';
    }
    $fits = [];
    foreach (LEVELS as $level) {
        $fit = '-';
        for ($v = 1; $v <= 10; $v++) {
            if ($split($encoded->mode, $v)->bits <= 8 * $tables[$v]->blocks[$level]->data) {
                $fit = $v;
                break;
            }
        }
        $fits[] = $fit;
    }
    $segmentText = [];
    foreach ($encoded->segments as $segment) {
        $segmentText[] = $segment->mode . ':' . strlen($segment->text);
    }
    $output->codes[] = 'symbol version ' . $version . ' level ' . $encoded->level . ' mask ' . $encoded->mask . ' size ' . $layout->size;
    $output->codes[] = 'segments ' . count($encoded->segments) . ' ' . implode(' ', $segmentText);
    $output->codes[] = 'bits data ' . $encoded->bits . ' capacity ' . (8 * $table->data) . ' alternatives NUMERIC ' . $alternatives[0]
        . ' ALPHANUMERIC ' . $alternatives[1] . ' BYTE ' . $alternatives[2] . ' MIXED ' . $split('MIXED', $version)->bits;
    $output->codes[] = 'fits L ' . $fits[0] . ' M ' . $fits[1] . ' Q ' . $fits[2] . ' H ' . $fits[3];
    $output->codes[] = 'modules function ' . $layout->functionCount . ' data ' . count($layout->order)
        . ' remainder ' . (count($layout->order) - 8 * $table->total) . ' dark ' . $encoded->dark;
    $output->codes[] = 'format ' . binary(formatInformation($encoded->level, $encoded->mask), 15)
        . ' version ' . ($version >= 7 ? binary(versionInformation($version), 18) : 'none');
    foreach ($encoded->penalties as $mask => $penalty) {
        $output->codes[] = 'penalty ' . $mask . ' n1 ' . $penalty->n1 . ' n2 ' . $penalty->n2 . ' n3 ' . $penalty->n3
            . ' n4 ' . $penalty->n4 . ' total ' . $penalty->total;
    }
    array_push($output->codes, ...symbolLines($encoded->grid));
    $output->codewords[] = 'request ' . $request->id . ' version ' . $version . ' level ' . $encoded->level
        . ' blocks ' . count($encoded->blocks) . ' data ' . $table->data . ' ec_per_block ' . $table->e . ' total ' . $table->total;
    foreach ($encoded->blocks as $b => $block) {
        $output->codewords[] = 'block ' . $b . ' data ' . hexadecimal($block->data);
        $output->codewords[] = 'block ' . $b . ' ec ' . hexadecimal($block->ec);
    }
    $output->codewords[] = 'interleaved ' . hexadecimal($encoded->interleaved);
    array_push($output->bitstream, ...$encoded->bitLines);
}

function readImage(string $text): object
{
    $lines = explode("\n", $text);
    [$width, $height] = array_map('intval', explode(' ', $lines[1]));
    $pixels = array_slice($lines, 2, $height);
    $left = $width;
    $right = -1;
    $top = $height;
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            if ($pixels[$y][$x] === '1') {
                $left = min($left, $x);
                $right = max($right, $x);
                $top = min($top, $y);
            }
        }
    }
    $run = 0;
    while ($left + $run < $width && $pixels[$top][$left + $run] === '1') {
        $run++;
    }
    $scale = intdiv($run, 7);
    $size = intdiv($right - $left + 1, $scale);
    $grid = [];
    for ($y = 0; $y < $size; $y++) {
        $row = [];
        for ($x = 0; $x < $size; $x++) {
            $row[] = $pixels[$top + $scale * $y][$left + $scale * $x] === '1' ? 1 : 0;
        }
        $grid[] = $row;
    }
    $wellFormed = true;
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $expected = $x >= $left && $x < $left + $scale * $size && $y >= $top && $y < $top + $scale * $size
                ? $grid[intdiv($y - $top, $scale)][intdiv($x - $left, $scale)] : 0;
            if ((int) $pixels[$y][$x] !== $expected) {
                $wellFormed = false;
            }
        }
    }
    return (object) ['width' => $width, 'height' => $height, 'quiet' => intdiv($left, $scale), 'scale' => $scale,
        'size' => $size, 'grid' => $grid, 'wellFormed' => $wellFormed];
}

function rotate(array $grid): array
{
    $size = count($grid);
    $result = array_fill(0, $size, array_fill(0, $size, 0));
    for ($y = 0; $y < $size; $y++) {
        for ($x = 0; $x < $size; $x++) {
            $result[$y][$x] = $grid[$size - 1 - $x][$y];
        }
    }
    return $result;
}

function transpose(array $grid): array
{
    $size = count($grid);
    $result = array_fill(0, $size, array_fill(0, $size, 0));
    for ($y = 0; $y < $size; $y++) {
        for ($x = 0; $x < $size; $x++) {
            $result[$y][$x] = $grid[$x][$y];
        }
    }
    return $result;
}

function hamming(int $first, int $second): int
{
    $value = $first ^ $second;
    $distance = 0;
    while ($value !== 0) {
        $distance += $value & 1;
        $value >>= 1;
    }
    return $distance;
}

function formatValues(): array
{
    static $values = null;
    if ($values === null) {
        $values = [];
        foreach (LEVELS as $level) {
            for ($mask = 0; $mask < 8; $mask++) {
                $values[] = (object) ['level' => $level, 'mask' => $mask, 'value' => formatInformation($level, $mask)];
            }
        }
    }
    return $values;
}

function versionValues(): array
{
    static $values = null;
    if ($values === null) {
        $values = [];
        for ($version = 7; $version <= 40; $version++) {
            $values[] = (object) ['version' => $version, 'value' => versionInformation($version)];
        }
    }
    return $values;
}

function nearest(int $value, array $candidates): object
{
    $best = null;
    foreach ($candidates as $candidate) {
        $distance = hamming($value, $candidate->value);
        if ($best === null || $distance < $best->distance) {
            $best = clone $candidate;
            $best->distance = $distance;
        }
    }
    return $best;
}

function parseData(array $bits, int $version): object
{
    $reader = new BitReader($bits);
    $lines = [];
    $characters = '';
    $end = 0;
    while ($reader->remaining() >= 4) {
        $indicator = $reader->read(4);
        if ($indicator === 0) {
            break;
        }
        $modes = [1 => 'NUMERIC', 2 => 'ALPHANUMERIC', 4 => 'BYTE'];
        if (!isset($modes[$indicator])) {
            $lines[] = 'parse failed indicator ' . binary($indicator, 4);
            return (object) ['success' => false, 'lines' => $lines];
        }
        $mode = $modes[$indicator];
        $width = countWidth($mode, $version);
        if ($reader->remaining() < $width) {
            $lines[] = 'parse failed length ' . $mode;
            return (object) ['success' => false, 'lines' => $lines];
        }
        $count = $reader->read($width);
        if ($reader->remaining() < dataWidth($mode, $count)) {
            $lines[] = 'parse failed length ' . $mode;
            return (object) ['success' => false, 'lines' => $lines];
        }
        $remaining = $count;
        $segment = '';
        while ($remaining > 0) {
            $size = min($remaining, $mode === 'NUMERIC' ? 3 : ($mode === 'ALPHANUMERIC' ? 2 : 1));
            $value = $reader->read(dataWidth($mode, $size));
            if ($mode === 'NUMERIC') {
                $limit = $size === 3 ? 1000 : ($size === 2 ? 100 : 10);
                $valid = $value < $limit;
                $group = $valid ? str_pad((string) $value, $size, '0', STR_PAD_LEFT) : '';
            } elseif ($mode === 'ALPHANUMERIC') {
                $valid = $value < ($size === 2 ? 2025 : 45);
                $group = !$valid ? '' : ($size === 2 ? ALPHANUMERIC[intdiv($value, 45)] . ALPHANUMERIC[$value % 45] : ALPHANUMERIC[$value]);
            } else {
                $valid = $value >= 32 && $value <= 126;
                $group = $valid ? chr($value) : '';
            }
            if (!$valid) {
                $lines[] = 'parse failed value ' . $mode;
                return (object) ['success' => false, 'lines' => $lines];
            }
            $segment .= $group;
            $remaining -= $size;
        }
        $characters .= $segment;
        $end = $reader->position;
        $lines[] = 'segment ' . $mode . ' ' . $count;
    }
    $expected = padBits(array_slice($bits, 0, $end), count($bits))->bits;
    $lines[] = 'padding ' . ($expected === $bits ? 'ok' : 'bad');
    $lines[] = 'text "' . $characters . '"';
    return (object) ['success' => true, 'text' => $characters, 'lines' => $lines];
}

function attempt(array $grid, array $tables): object
{
    $version = intdiv(count($grid) - 17, 4);
    $locations = positions(count($grid));
    $lines = [];
    $blocks = [];
    $format = [readValue($grid, $locations->format[0]), readValue($grid, $locations->format[1])];
    $formats = [nearest($format[0], formatValues()), nearest($format[1], formatValues())];
    $chosen = $formats[1]->distance < $formats[0]->distance ? $formats[1] : $formats[0];
    $prefix = 'format ' . binary($format[0], 15) . ' ' . binary($format[1], 15)
        . ' distance ' . $formats[0]->distance . ' ' . $formats[1]->distance;
    if ($chosen->distance > 3) {
        $lines[] = $prefix . ' unreadable';
        return (object) ['success' => false, 'lines' => $lines, 'blocks' => $blocks];
    }
    $lines[] = $prefix . ' level ' . $chosen->level . ' mask ' . $chosen->mask;
    if ($version >= 7) {
        $information = [readValue($grid, $locations->version[0]), readValue($grid, $locations->version[1])];
        $versions = [nearest($information[0], versionValues()), nearest($information[1], versionValues())];
        $decoded = $versions[1]->distance < $versions[0]->distance ? $versions[1] : $versions[0];
        $prefix = 'version ' . binary($information[0], 18) . ' ' . binary($information[1], 18)
            . ' distance ' . $versions[0]->distance . ' ' . $versions[1]->distance;
        if ($decoded->distance > 3) {
            $lines[] = $prefix . ' unreadable';
            return (object) ['success' => false, 'lines' => $lines, 'blocks' => $blocks];
        }
        $lines[] = $prefix . ' decoded ' . $decoded->version;
        if ($decoded->version !== $version) {
            return (object) ['success' => false, 'lines' => $lines, 'blocks' => $blocks];
        }
    }
    $layout = $tables[$version]->layout;
    $table = $tables[$version]->blocks[$chosen->level];
    $unmasked = applyMask($grid, $layout->areas, $chosen->mask);
    $bits = [];
    for ($i = 0; $i < 8 * $table->total; $i++) {
        [$x, $y] = $layout->order[$i];
        $bits[] = $unmasked[$y][$x];
    }
    $codewords = toCodewords($bits);
    $received = [];
    foreach ($table->lengths as $length) {
        $received[] = array_fill(0, $length + $table->e, 0);
    }
    foreach ($table->placement as $i => [$block, $position]) {
        $received[$block][$position] = $codewords[$i];
    }
    foreach ($received as $block => $words) {
        $result = rsCorrect($words, $table->e);
        $blocks[] = $result;
        $suffix = $result->status;
        if ($result->status === 'corrected') {
            $suffix .= ' ' . implode(' ', $result->positions);
        }
        $lines[] = 'block ' . $block . ' syndromes ' . hexadecimal($result->syndromes) . ' ' . $suffix;
    }
    foreach ($blocks as $block) {
        if ($block->status === 'failed') {
            return (object) ['success' => false, 'lines' => $lines, 'blocks' => $blocks];
        }
    }
    $data = [];
    foreach ($blocks as $b => $block) {
        array_push($data, ...array_slice($block->codewords, 0, $table->lengths[$b]));
    }
    $parsed = parseData(fromCodewords($data), $version);
    array_push($lines, ...$parsed->lines);
    return (object) ['success' => $parsed->success, 'text' => $parsed->text ?? null, 'lines' => $lines, 'blocks' => $blocks];
}

function decode(array $grid, array $tables): object
{
    $size = count($grid);
    $corners = [[$size - 7, $size - 7], [$size - 7, 0], [0, 0], [0, $size - 7]];
    $scores = [];
    foreach ($corners as [$x0, $y0]) {
        $score = 0;
        for ($y = 0; $y < 7; $y++) {
            for ($x = 0; $x < 7; $x++) {
                $expected = max(abs($x - 3), abs($y - 3)) === 2 ? 0 : 1;
                if ($grid[$y0 + $y][$x0 + $x] === $expected) {
                    $score++;
                }
            }
        }
        $scores[] = $score;
    }
    $rotations = 0;
    for ($k = 1; $k < 4; $k++) {
        if ($scores[$k] < $scores[$rotations]) {
            $rotations = $k;
        }
    }
    $oriented = $grid;
    for ($k = 0; $k < $rotations; $k++) {
        $oriented = rotate($oriented);
    }
    $adopted = attempt($oriented, $tables);
    $mirrored = false;
    if (!$adopted->success) {
        $retry = attempt(transpose($oriented), $tables);
        if ($retry->success) {
            $adopted = $retry;
            $mirrored = true;
        }
    }
    array_unshift($adopted->lines, 'orientation rotations ' . $rotations . ' mirrored ' . ($mirrored ? 'yes' : 'no'));
    return $adopted;
}

function damageSymbol(object $encoded, array $operations): object
{
    $grid = $encoded->grid;
    foreach ($operations as $operation) {
        if ($operation->kind === 'flip') {
            [$x, $y] = array_map('intval', $operation->args);
            $grid[$y][$x] ^= 1;
        } elseif ($operation->kind === 'fill') {
            [$x, $y, $width, $height] = array_map('intval', array_slice($operation->args, 0, 4));
            $color = $operation->args[4] === 'dark' ? 1 : 0;
            for ($dy = 0; $dy < $height; $dy++) {
                for ($dx = 0; $dx < $width; $dx++) {
                    $grid[$y + $dy][$x + $dx] = $color;
                }
            }
        }
    }
    $layout = $encoded->layout;
    $table = $encoded->table;
    $indices = array_fill(0, $layout->size, array_fill(0, $layout->size, -1));
    foreach ($layout->order as $i => [$x, $y]) {
        $indices[$y][$x] = $i;
    }
    $counts = ['changed' => 0, 'function' => 0, 'format' => 0, 'version' => 0, 'data' => 0, 'remainder' => 0];
    $errors = array_fill(0, count($table->lengths), []);
    for ($y = 0; $y < $layout->size; $y++) {
        for ($x = 0; $x < $layout->size; $x++) {
            if ($grid[$y][$x] === $encoded->grid[$y][$x]) {
                continue;
            }
            $counts['changed']++;
            $area = $layout->areas[$y][$x];
            if ($area !== 'data') {
                $counts[$area]++;
            } elseif ($indices[$y][$x] >= 8 * $table->total) {
                $counts['remainder']++;
            } else {
                $counts['data']++;
                [$block, $position] = $table->placement[intdiv($indices[$y][$x], 8)];
                $errors[$block][$position] = true;
            }
        }
    }
    foreach ($operations as $operation) {
        if ($operation->kind === 'rotate') {
            $grid = rotate($grid);
        } elseif ($operation->kind === 'mirror') {
            $grid = transpose($grid);
        }
    }
    return (object) ['grid' => $grid, 'counts' => $counts, 'errors' => array_map('count', $errors)];
}

function tolerance(object $encoded, array $tables, int $color): int
{
    $size = $encoded->layout->size;
    for ($side = 1; $side <= $size; $side++) {
        $start = intdiv($size - $side, 2);
        $grid = $encoded->grid;
        for ($y = $start; $y < $start + $side; $y++) {
            for ($x = $start; $x < $start + $side; $x++) {
                $grid[$y][$x] = $color;
            }
        }
        $result = decode($grid, $tables);
        if (!$result->success || $result->text !== $encoded->request->text) {
            return $side - 1;
        }
    }
    return $size;
}

function capacityReport(array $tables): array
{
    $lines = [];
    for ($version = 1; $version <= 10; $version++) {
        $layout = $tables[$version]->layout;
        $centers = $tables[$version]->centers;
        $blocks = $tables[$version]->blocks;
        $total = $blocks['L']->total;
        $lines[] = 'version ' . $version . ' size ' . $layout->size . ' data_modules ' . count($layout->order)
            . ' codewords ' . $total . ' remainder ' . (count($layout->order) - 8 * $total)
            . ' alignment ' . ($centers ? implode(' ', $centers) : 'none');
        foreach (LEVELS as $level) {
            $table = $blocks[$level];
            $capacity = 8 * $table->data;
            $maxima = [];
            foreach (MODES as $mode) {
                $count = 0;
                while (4 + countWidth($mode, $version) + dataWidth($mode, $count + 1) <= $capacity) {
                    $count++;
                }
                $maxima[] = $count;
            }
            $lines[] = 'level ' . $level . ' blocks ' . count($table->lengths) . ' data ' . $table->data
                . ' ec_per_block ' . $table->e . ' numeric ' . $maxima[0] . ' alphanumeric ' . $maxima[1] . ' byte ' . $maxima[2];
        }
    }
    return $lines;
}

function newSummary(): object
{
    return (object) ['encoded' => 0, 'errorCount' => 0,
        'errors' => ['level' => 0, 'mode' => 0, 'version' => 0, 'mask' => 0, 'text' => 0, 'charset' => 0, 'capacity' => 0],
        'modes' => ['NUMERIC' => 0, 'ALPHANUMERIC' => 0, 'BYTE' => 0, 'MIXED' => 0],
        'levels' => ['L' => 0, 'M' => 0, 'Q' => 0, 'H' => 0], 'boosted' => 0,
        'versions' => array_fill(0, 10, 0), 'masks' => array_fill(0, 8, 0), 'segments' => 0,
        'dataCodewords' => 0, 'ecCodewords' => 0, 'modules' => 0, 'dark' => 0,
        'checks' => ['total' => 0, 'ok' => 0, 'mismatch' => 0, 'failed' => 0],
        'blocks' => ['ok' => 0, 'corrected' => 0, 'failed' => 0, 'codewords' => 0],
        'scans' => ['decoded' => 0, 'failed' => 0]];
}

function countEncoding(object $encoded, object $summary): void
{
    $summary->encoded++;
    $summary->modes[$encoded->mode]++;
    $summary->levels[$encoded->level]++;
    if ($encoded->level !== $encoded->request->level[0]) {
        $summary->boosted++;
    }
    $summary->versions[$encoded->version - 1]++;
    $summary->masks[$encoded->mask]++;
    $summary->segments += count($encoded->segments);
    $summary->dataCodewords += $encoded->table->data;
    $summary->ecCodewords += $encoded->table->e * count($encoded->table->lengths);
    $summary->modules += $encoded->layout->size * $encoded->layout->size;
    $summary->dark += $encoded->dark;
}

function countCheck(object $decoded, string $expected, object $summary): string
{
    $result = !$decoded->success ? 'failed' : ($decoded->text === $expected ? 'ok' : 'mismatch');
    $summary->checks['total']++;
    $summary->checks[$result]++;
    foreach ($decoded->blocks as $block) {
        $summary->blocks[$block->status]++;
        if ($block->status === 'corrected') {
            $summary->blocks['codewords'] += count($block->positions);
        }
    }
    return $result;
}

function selfCheck(object $encoded, object $input, object $summary, array &$lines): void
{
    $path = 'output/qr_' . $encoded->request->id . '.pbm';
    file_put_contents($path, pbm($encoded->grid, $input->quiet, $input->scale));
    $image = readImage(file_get_contents($path));
    $clean = decode($image->grid, $input->tables);
    $lines[] = 'request ' . $encoded->request->id;
    $lines[] = 'image ' . $image->width . ' ' . $image->height . ' quiet ' . $image->quiet . ' scale ' . $image->scale
        . ' size ' . $image->size . ' ' . ($image->wellFormed ? 'ok' : 'bad');
    $lines[] = 'check clean';
    array_push($lines, ...$clean->lines);
    $lines[] = 'result ' . countCheck($clean, $encoded->request->text, $summary);
    $key = '#' . $encoded->request->id;
    if (isset($input->damage[$key])) {
        $operations = $input->damage[$key];
        $damaged = damageSymbol($encoded, $operations);
        $result = decode($damaged->grid, $input->tables);
        $counts = $damaged->counts;
        $lines[] = 'check damaged operations ' . count($operations);
        $lines[] = 'damage changed ' . $counts['changed'] . ' function ' . $counts['function'] . ' format ' . $counts['format']
            . ' version ' . $counts['version'] . ' data ' . $counts['data'] . ' remainder ' . $counts['remainder'];
        $lines[] = 'errors ' . implode(' ', $damaged->errors) . ' limit ' . intdiv($encoded->table->e, 2);
        array_push($lines, ...$result->lines);
        $lines[] = 'result ' . countCheck($result, $encoded->request->text, $summary);
    }
    $light = tolerance($encoded, $input->tables, 0);
    $dark = tolerance($encoded, $input->tables, 1);
    $lines[] = 'tolerance light ' . $light . ' dark ' . $dark;
}

function summaryReport(object $input, object $summary): array
{
    $errorKinds = ['level', 'mode', 'version', 'mask', 'text', 'charset', 'capacity'];
    $errors = [];
    foreach ($errorKinds as $kind) {
        $errors[] = $kind . ' ' . $summary->errors[$kind];
    }
    $modes = [];
    foreach (array_merge(MODES, ['MIXED']) as $mode) {
        $modes[] = $mode . ' ' . $summary->modes[$mode];
    }
    $levels = [];
    foreach (LEVELS as $level) {
        $levels[] = $level . ' ' . $summary->levels[$level];
    }
    $checks = $summary->checks;
    $blocks = $summary->blocks;
    $scans = $summary->scans;
    return ['requests ' . count($input->requests) . ' encoded ' . $summary->encoded . ' errors ' . $summary->errorCount,
        'error_kinds ' . implode(' ', $errors), 'modes ' . implode(' ', $modes),
        'levels ' . implode(' ', $levels) . ' boosted ' . $summary->boosted,
        'versions ' . implode(' ', $summary->versions), 'masks ' . implode(' ', $summary->masks),
        'segments ' . $summary->segments . ' data_codewords ' . $summary->dataCodewords . ' ec_codewords ' . $summary->ecCodewords,
        'modules ' . $summary->modules . ' dark ' . $summary->dark,
        'checks ' . $checks['total'] . ' ok ' . $checks['ok'] . ' mismatch ' . $checks['mismatch'] . ' failed ' . $checks['failed'],
        'blocks ok ' . $blocks['ok'] . ' corrected ' . $blocks['corrected'] . ' failed ' . $blocks['failed'] . ' codewords ' . $blocks['codewords'],
        'scans ' . count($input->scans) . ' decoded ' . $scans['decoded'] . ' failed ' . $scans['failed']];
}

function main(): void
{
    $input = readInputs();
    $summary = newSummary();
    $output = (object) ['codes' => [], 'codewords' => [], 'bitstream' => [], 'selfcheck' => [], 'scans' => [],
        'capacity' => [], 'summary' => []];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($input->requests as $request) {
        $output->codes[] = 'request ' . $request->id;
        $resolved = resolveRequest($request, $input->tables);
        if (isset($resolved->error)) {
            $output->codes[] = 'error ' . $resolved->error;
            $summary->errorCount++;
            $kind = explode(' ', $resolved->error)[0];
            $summary->errors[$kind]++;
            continue;
        }
        $encoded = encodeRequest($resolved);
        generationReports($encoded, $input->tables, $output);
        countEncoding($encoded, $summary);
        selfCheck($encoded, $input, $summary, $output->selfcheck);
    }
    foreach ($input->scans as $scan) {
        $decoded = decode($scan->grid, $input->tables);
        $result = $decoded->success ? 'decoded' : 'failed';
        $output->scans[] = 'scan ' . $scan->name . ' size ' . count($scan->grid);
        array_push($output->scans, ...$decoded->lines);
        $output->scans[] = 'result ' . $result;
        $summary->scans[$result]++;
    }
    $output->capacity = capacityReport($input->tables);
    $output->summary = summaryReport($input, $summary);
    foreach (['codes', 'codewords', 'bitstream', 'selfcheck', 'scans', 'capacity', 'summary'] as $name) {
        writeLines('output/' . $name . '.txt', $output->$name);
    }
}

main();
