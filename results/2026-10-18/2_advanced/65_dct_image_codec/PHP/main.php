<?php

require_once __DIR__ . '/image_io.php';
require_once __DIR__ . '/color.php';
require_once __DIR__ . '/dct.php';
require_once __DIR__ . '/entropy.php';
require_once __DIR__ . '/bitstream.php';

const COMPONENT_NAMES = ['Y', 'Cb', 'Cr'];
const TABLE_NAMES = ['dc_luma', 'ac_luma', 'dc_chroma', 'ac_chroma'];
const TABLE_KEYS = [[0, 0], [1, 0], [0, 1], [1, 1]];

function word(int $value): array { return [intdiv($value, 256), $value % 256]; }
function tableKey(int $tableClass, int $id): int { return 16 * $tableClass + $id; }

function geometry(int $width, int $height, array $components, int $restart): object
{
    $hMax = max(array_map(fn($component) => $component->h, $components));
    $vMax = max(array_map(fn($component) => $component->v, $components));
    $mx = intdiv($width + 8 * $hMax - 1, 8 * $hMax);
    $my = intdiv($height + 8 * $vMax - 1, 8 * $vMax);
    $blocks = [];
    for ($mcu = 0; $mcu < $mx * $my; $mcu++) foreach ($components as $k => $component) {
        for ($v = 0; $v < $component->v; $v++) for ($h = 0; $h < $component->h; $h++) {
            $blocks[] = (object) ['number' => count($blocks), 'mcu' => $mcu, 'component' => $k,
                'bx' => $component->h * ($mcu % $mx) + $h, 'by' => $component->v * intdiv($mcu, $mx) + $v, 'z' => array_fill(0, 64, 0)];
        }
    }
    $perMCU = intdiv(count($blocks), $mx * $my);
    $intervalSize = $restart ?: $mx * $my;
    $intervals = [];
    for ($first = 0; $first < $mx * $my; $first += $intervalSize) {
        $count = min($intervalSize, $mx * $my - $first);
        $intervals[] = (object) ['number' => count($intervals), 'first' => $first, 'count' => $count,
            'start' => $first * $perMCU, 'end' => ($first + $count) * $perMCU];
    }
    return (object) compact('width', 'height', 'components', 'restart', 'hMax', 'vMax', 'mx', 'my', 'blocks', 'intervals');
}

function standardComponents(int $h, int $v): array
{
    $result = [];
    for ($k = 0; $k < 3; $k++) $result[] = (object) ['id' => $k + 1, 'h' => $k === 0 ? $h : 1, 'v' => $k === 0 ? $v : 1,
        'quant' => $k === 0 ? 0 : 1, 'dc' => $k === 0 ? 0 : 1, 'ac' => $k === 0 ? 0 : 1];
    return $result;
}

function encode(object $image, int $quality, string $sampling, string $mode, int $restart, object $tables): object
{
    $h = $sampling === '444' ? 1 : 2;
    $v = $sampling === '420' ? 2 : 1;
    $layout = geometry($image->width, $image->height, standardComponents($h, $v), $restart);
    $quant = quantizationTables($tables->base, $quality);
    $planes = componentPlanes($image, $layout);
    $blocks = [];
    foreach ($layout->blocks as $item) {
        $block = clone $item;
        $pixels = [];
        for ($y = 0; $y < 8; $y++) for ($x = 0; $x < 8; $x++) $pixels[] = $planes[$block->component][8 * $block->by + $y][8 * $block->bx + $x];
        $block->z = quantize(forward($pixels, $tables->C), $quant[$layout->components[$block->component]->quant]);
        $blocks[] = $block;
    }
    $result = assemble($layout, $quant, $blocks, $mode, $tables->huffman);
    $result->planes = $planes;
    return $result;
}

function buildSymbols(object $layout, array $inputBlocks): object
{
    $frequencies = array_fill(0, 4, array_fill(0, 256, 0));
    $blocks = [];
    foreach ($inputBlocks as $item) {
        $block = clone $item;
        $block->symbols = [];
        $block->bits = 0;
        $blocks[] = $block;
    }
    $add = function (object $block, int $table, int $symbol, int $value = 0, int $length = 0) use (&$frequencies): void {
        $block->symbols[] = (object) ['table' => $table, 'symbol' => $symbol, 'length' => $length, 'extra' => extra($value, $length)];
        $frequencies[$table][$symbol]++;
    };
    foreach ($layout->intervals as $interval) {
        $predictors = [0, 0, 0];
        for ($index = $interval->start; $index < $interval->end; $index++) {
            $block = $blocks[$index];
            $k = $block->component;
            $base = $k === 0 ? 0 : 2;
            $block->diff = $block->z[0] - $predictors[$k];
            $predictors[$k] = $block->z[0];
            $category = category($block->diff);
            $add($block, $base, $category, $block->diff, $category);
            $run = 0;
            for ($i = 1; $i < 64; $i++) {
                if ($block->z[$i] === 0) { $run++; continue; }
                while ($run >= 16) { $add($block, $base + 1, 240); $run -= 16; }
                $length = category($block->z[$i]);
                $add($block, $base + 1, 16 * $run + $length, $block->z[$i], $length);
                $run = 0;
            }
            if ($run > 0) $add($block, $base + 1, 0);
        }
    }
    return (object) compact('blocks', 'frequencies');
}

function assemble(object $layout, array $quant, array $inputBlocks, string $mode, array $standard): object
{
    $symbols = buildSymbols($layout, $inputBlocks);
    $blocks = $symbols->blocks;
    $frequencies = $symbols->frequencies;
    $huffman = [];
    foreach (TABLE_KEYS as $i => [$tableClass, $id]) $huffman[] = $mode === 'standard'
        ? assignCodes($standard[$i]) : optimized($frequencies[$i], $tableClass, $id);
    $header = [255, 216];
    $segment = function (int $marker, array $contents) use (&$header): void {
        array_push($header, 255, $marker, ...word(count($contents) + 2), ...$contents);
    };
    $order = zigzag();
    $segment(219, array_merge([0], array_map(fn($i) => $quant[0][$i], $order), [1], array_map(fn($i) => $quant[1][$i], $order)));
    $frame = array_merge([8], word($layout->height), word($layout->width), [3]);
    foreach ($layout->components as $component) array_push($frame, $component->id, 16 * $component->h + $component->v, $component->quant);
    $segment(192, $frame);
    $definitions = [];
    foreach ($huffman as $table) $definitions = array_merge($definitions, [tableKey($table->tableClass, $table->id)], $table->bits, $table->values);
    $segment(196, $definitions);
    if ($layout->restart > 0) $segment(221, word($layout->restart));
    array_push($header, 255, 218, 0, 12, 3, 1, 0, 2, 17, 3, 17, 0, 63, 0);
    $writer = new Writer();
    $intervals = [];
    foreach ($layout->intervals as $item) {
        $interval = clone $item;
        if ($interval->number > 0) $writer->marker(208 + ($interval->number - 1) % 8);
        $start = count($writer->bytes);
        for ($index = $interval->start; $index < $interval->end; $index++) {
            $block = $blocks[$index];
            foreach ($block->symbols as $symbol) {
                $code = $huffman[$symbol->table]->codes[$symbol->symbol];
                $writer->write($code->code, $code->length);
                $writer->write($symbol->extra, $symbol->length);
                $block->bits += $code->length + $symbol->length;
            }
        }
        $writer->pad();
        $interval->position = count($header) + $start;
        $interval->length = count($writer->bytes) - $start;
        $intervals[] = $interval;
    }
    return (object) ['layout' => $layout, 'quant' => $quant, 'blocks' => $blocks, 'frequencies' => $frequencies, 'huffman' => $huffman,
        'intervals' => $intervals, 'headerBytes' => count($header), 'scanBytes' => count($writer->bytes), 'padding' => $writer->padding,
        'stuffed' => $writer->stuffed, 'bytes' => array_merge($header, $writer->bytes, [255, 217])];
}

function parseHeader(array $bytes): object
{
    $quant = $huffman = [];
    $segments = [(object) ['position' => 0, 'name' => 'SOI', 'length' => 0]];
    $width = $height = $restart = 0;
    $components = [];
    $position = 2;
    $names = [192 => 'SOF0', 196 => 'DHT', 219 => 'DQT', 221 => 'DRI', 218 => 'SOS', 254 => 'COM'];
    while (true) {
        $marker = $bytes[$position + 1];
        $length = $bytes[$position + 2] * 256 + $bytes[$position + 3];
        $contents = array_slice($bytes, $position + 4, $length - 2);
        $segments[] = (object) ['position' => $position, 'name' => $names[$marker] ?? 'APP' . ($marker - 224), 'length' => $length];
        $position += $length + 2;
        if ($marker === 219) {
            $order = zigzag();
            for ($offset = 0; $offset < count($contents); $offset += 65) {
                $table = array_fill(0, 64, 0);
                for ($i = 0; $i < 64; $i++) $table[$order[$i]] = $contents[$offset + 1 + $i];
                $quant[$contents[$offset]] = $table;
            }
        } elseif ($marker === 196) {
            $offset = 0;
            while ($offset < count($contents)) {
                $key = $contents[$offset++];
                $bits = array_slice($contents, $offset, 16);
                $offset += 16;
                $count = array_sum($bits);
                $values = array_slice($contents, $offset, $count);
                $offset += $count;
                $huffman[$key] = assignCodes((object) ['tableClass' => intdiv($key, 16), 'id' => $key % 16, 'bits' => $bits, 'values' => $values]);
            }
        } elseif ($marker === 192) {
            $height = $contents[1] * 256 + $contents[2];
            $width = $contents[3] * 256 + $contents[4];
            for ($k = 0; $k < 3; $k++) $components[] = (object) ['id' => $contents[6 + 3 * $k],
                'h' => intdiv($contents[7 + 3 * $k], 16), 'v' => $contents[7 + 3 * $k] % 16, 'quant' => $contents[8 + 3 * $k]];
        } elseif ($marker === 221) $restart = $contents[0] * 256 + $contents[1];
        elseif ($marker === 218) {
            foreach ($components as $k => $component) {
                $component->dc = intdiv($contents[2 + 2 * $k], 16);
                $component->ac = $contents[2 + 2 * $k] % 16;
            }
            break;
        }
    }
    $segments[] = (object) ['position' => count($bytes) - 2, 'name' => 'EOI', 'length' => 0];
    return (object) ['layout' => geometry($width, $height, $components, $restart), 'quant' => $quant, 'huffman' => $huffman,
        'segments' => $segments, 'scanStart' => $position, 'scanBytes' => count($bytes) - 2 - $position];
}

function readSymbol(Reader $reader, object $table): int
{
    $code = 0;
    for ($length = 1; $length <= 16; $length++) {
        $code = $code * 2 + $reader->bit();
        if (isset($table->decode[$length][$code])) return $table->decode[$length][$code];
    }
    throw new DecodeError('code');
}

function readBlock(Reader $reader, object $component, int $k, array &$predictors, array $huffman): array
{
    $z = array_fill(0, 64, 0);
    $n = readSymbol($reader, $huffman[tableKey(0, $component->dc)]);
    $predictors[$k] += restore($reader->read($n), $n);
    $z[0] = $predictors[$k];
    $index = 1;
    while ($index <= 63) {
        $symbol = readSymbol($reader, $huffman[tableKey(1, $component->ac)]);
        if ($symbol === 0) break;
        $run = intdiv($symbol, 16);
        $length = $symbol % 16;
        $index += $run;
        if ($index > 63) throw new DecodeError('index');
        if ($length > 0) $z[$index] = restore($reader->read($length), $length);
        $index++;
    }
    return $z;
}

function render(object $layout, array $blocks, array $quant, array $C, int $keep = 64): object
{
    $componentPlanes = [];
    foreach ($layout->components as $component) $componentPlanes[] = array_fill(0, 8 * $component->v * $layout->my,
        array_fill(0, 8 * $component->h * $layout->mx, 128));
    foreach ($blocks as $block) {
        $table = $quant[$layout->components[$block->component]->quant];
        $pixels = inverse(dequantize($block->z, $table, $block->component === 0 ? $keep : 64), $C);
        for ($y = 0; $y < 8; $y++) for ($x = 0; $x < 8; $x++) $componentPlanes[$block->component][8 * $block->by + $y][8 * $block->bx + $x] = $pixels[8 * $y + $x];
    }
    $result = upsample($componentPlanes, $layout);
    $result->componentPlanes = $componentPlanes;
    return $result;
}

function decode(array $bytes, array $C): object
{
    $parsed = parseHeader($bytes);
    $layout = $parsed->layout;
    $reader = new Reader($bytes, $parsed->scanStart);
    $blocks = $layout->blocks;
    $intervals = [];
    foreach ($layout->intervals as $item) {
        $interval = clone $item;
        $interval->state = 'lost';
        $intervals[] = $interval;
    }
    $j = 0;
    while ($j < count($intervals)) {
        $interval = $intervals[$j];
        $predictors = [0, 0, 0];
        $decoded = [];
        $currentMCU = $interval->first;
        try {
            for ($index = $interval->start; $index < $interval->end; $index++) {
                $block = $blocks[$index];
                $currentMCU = $block->mcu;
                $decoded[] = readBlock($reader, $layout->components[$block->component], $block->component, $predictors, $parsed->huffman);
            }
            $reader->clear();
            $expected = $j < count($intervals) - 1 ? 208 + $j % 8 : 217;
            if ($bytes[$reader->position] !== 255 || $bytes[$reader->position + 1] !== $expected) throw new DecodeError('sync');
            foreach ($decoded as $i => $z) $blocks[$interval->start + $i]->z = $z;
            $interval->state = 'ok';
            $reader->position += 2;
            $j++;
        } catch (DecodeError $error) {
            $offset = $reader->position;
            $reader->clear();
            $resync = $reader->resync();
            $marker = $bytes[$resync + 1];
            $interval->state = 'damaged';
            $interval->kind = $error->kind;
            $interval->mcu = $currentMCU;
            $interval->offset = $offset;
            $interval->resync = $resync;
            if ($marker === 217) break;
            $number = $marker - 208;
            $next = $j + 1 + (($number - $j) % 8 + 8) % 8;
            $reader->position = $resync + 2;
            $j = $next;
        }
    }
    $rendered = render($layout, $blocks, $parsed->quant, $C);
    $parsed->blocks = $blocks;
    $parsed->intervals = $intervals;
    $parsed->componentPlanes = $rendered->componentPlanes;
    $parsed->planes = $rendered->planes;
    $parsed->image = $rendered->image;
    return $parsed;
}

function psnr(array $first, array $second): string
{
    $error = 0;
    foreach ($first as $i => $value) {
        $difference = $value - $second[$i];
        $error += $difference * $difference;
    }
    return $error === 0 ? 'inf' : number_format(10 * log10(65025 * count($first) / $error), 2, '.', '');
}

function fraction(int $numerator, int $denominator): string
{
    $a = $numerator;
    $b = $denominator;
    while ($b !== 0) { $remainder = $a % $b; $a = $b; $b = $remainder; }
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a);
}

function flattenPlane(array $plane): array
{
    $result = [];
    foreach ($plane as $row) foreach ($row as $value) $result[] = $value;
    return $result;
}

function flattenPixels(array $pixels): array
{
    $result = [];
    foreach ($pixels as $row) foreach ($row as $pixel) foreach ($pixel as $value) $result[] = $value;
    return $result;
}

function imageMetrics(object $original, array $originalPlanes, object $decoded): object
{
    $channels = [];
    foreach ($originalPlanes as $k => $plane) $channels[] = psnr(flattenPlane($plane), flattenPlane($decoded->planes[$k]));
    $first = flattenPixels($original->pixels);
    $second = flattenPixels($decoded->image->pixels);
    $maximum = 0;
    foreach ($first as $i => $value) $maximum = max($maximum, abs($value - $second[$i]));
    return (object) ['channels' => $channels, 'rgb' => psnr($first, $second), 'maximum' => $maximum];
}

function blockStatistics(object $reference, object $decoded): object
{
    $nonzero = array_fill(0, 64, 0);
    $components = [];
    for ($k = 0; $k < 3; $k++) $components[] = (object) ['bits' => 0, 'nonzero' => 0, 'error' => 0];
    $lines = ['blocks ' . count($reference->blocks)];
    $zeroAC = 0;
    foreach ($reference->blocks as $block) {
        $ac = $last = $error = 0;
        for ($i = 0; $i < 64; $i++) if ($block->z[$i] !== 0) {
            $nonzero[$i]++;
            $components[$block->component]->nonzero++;
            $last = $i;
            if ($i > 0) $ac++;
        }
        if ($ac === 0) $zeroAC++;
        for ($y = 0; $y < 8; $y++) for ($x = 0; $x < 8; $x++) {
            $row = 8 * $block->by + $y;
            $column = 8 * $block->bx + $x;
            $difference = $reference->planes[$block->component][$row][$column] - $decoded->componentPlanes[$block->component][$row][$column];
            $error += $difference * $difference;
        }
        $components[$block->component]->bits += $block->bits;
        $components[$block->component]->error += $error;
        $lines[] = 'block ' . $block->number . ' ' . COMPONENT_NAMES[$block->component] . ' ' . $block->bx . ' ' . $block->by
            . ' dc ' . $block->z[0] . ' diff ' . $block->diff . ' nonzero ' . $ac . ' last ' . $last . ' bits ' . $block->bits . ' sse ' . $error;
    }
    return (object) compact('lines', 'nonzero', 'components', 'zeroAC');
}

function huffmanLines(object $reference): array
{
    $lines = [];
    foreach ($reference->huffman as $i => $table) {
        $coded = $bits = 0;
        foreach ($table->values as $symbol) {
            $coded += $reference->frequencies[$i][$symbol];
            $bits += $reference->frequencies[$i][$symbol] * $table->codes[$symbol]->length;
        }
        $lines[] = 'table ' . TABLE_NAMES[$i] . ' class ' . $table->tableClass . ' id ' . $table->id . ' symbols ' . count($table->values) . ' coded ' . $coded . ' bits ' . $bits;
        $lines[] = 'counts ' . implode(' ', $table->bits);
        foreach ($table->values as $symbol) {
            $code = $table->codes[$symbol];
            $lines[] = 'symbol ' . str_pad(dechex($symbol), 2, '0', STR_PAD_LEFT) . ' length ' . $code->length
                . ' code ' . str_pad(decbin($code->code), $code->length, '0', STR_PAD_LEFT) . ' count ' . $reference->frequencies[$i][$symbol];
        }
    }
    return $lines;
}

function thumbnail(object $decoded): object
{
    $layout = $decoded->layout;
    $width = intdiv($layout->width + 7, 8);
    $height = intdiv($layout->height + 7, 8);
    $byPosition = [];
    foreach ($decoded->blocks as $block) $byPosition[$block->component . ',' . $block->bx . ',' . $block->by] = $block;
    $pixels = [];
    for ($y = 0; $y < $height; $y++) {
        $row = [];
        for ($x = 0; $x < $width; $x++) {
            $values = [];
            foreach ($layout->components as $k => $component) {
                $bx = intdiv($x * $component->h, $layout->hMax);
                $by = intdiv($y * $component->v, $layout->vMax);
                $block = $byPosition[$k . ',' . $bx . ',' . $by];
                $weight = $decoded->quant[$component->quant][0];
                $values[] = clamp(floorDiv($block->z[0] * $weight + 4, 8) + 128);
            }
            $row[] = toRGB($values);
        }
        $pixels[] = $row;
    }
    return (object) compact('width', 'height', 'pixels');
}

function referenceReport(object $reference, object $stats, object $original, object $decoded, object $params): array
{
    $layout = $reference->layout;
    $quant = $reference->quant;
    $counts = array_map('array_sum', $reference->frequencies);
    $eob = $reference->frequencies[1][0] + $reference->frequencies[3][0];
    $zrl = $reference->frequencies[1][240] + $reference->frequencies[3][240];
    $componentCounts = [];
    foreach ($layout->components as $component) $componentCounts[] = $component->h * $component->v * $layout->mx * $layout->my;
    $order = zigzag();
    $lines = [
        'image ' . $layout->width . ' ' . $layout->height,
        'sampling ' . $params->sampling . ' mcu ' . (8 * $layout->hMax) . ' ' . (8 * $layout->vMax) . ' grid ' . $layout->mx . ' ' . $layout->my,
        'padded ' . (8 * $layout->hMax * $layout->mx) . ' ' . (8 * $layout->vMax * $layout->my),
        'blocks ' . implode(' ', $componentCounts),
        'restart_interval ' . $layout->restart . ' markers ' . (count($layout->intervals) - 1),
        'huffman ' . $params->huffman, 'quality ' . $params->qualities[0],
        'quant 0 ' . implode(' ', array_map(fn($i) => $quant[0][$i], $order)),
        'quant 1 ' . implode(' ', array_map(fn($i) => $quant[1][$i], $order)),
        'symbols ' . implode(' ', $counts), 'eob ' . $eob . ' zrl ' . $zrl, 'zero_ac_blocks ' . $stats->zeroAC,
        'nonzero ' . implode(' ', $stats->nonzero)];
    foreach ($stats->components as $k => $component) $lines[] = 'component ' . COMPONENT_NAMES[$k] . ' bits ' . $component->bits
        . ' nonzero ' . $component->nonzero . ' sse ' . $component->error;
    $lines[] = 'padding_bits ' . $reference->padding;
    $lines[] = 'stuffed_bytes ' . $reference->stuffed;
    $lines[] = 'header_bytes ' . $reference->headerBytes;
    $lines[] = 'scan_bytes ' . $reference->scanBytes;
    $lines[] = 'total_bytes ' . count($reference->bytes);
    foreach ($reference->intervals as $interval) $lines[] = 'interval ' . $interval->number . ' ' . $interval->first . ' ' . $interval->count
        . ' ' . $interval->position . ' ' . $interval->length;
    $histogram = array_fill(0, 8, 0);
    $upper = [0, 1, 3, 7, 15, 31, 63, 255];
    $first = flattenPixels($original->pixels);
    $second = flattenPixels($decoded->image->pixels);
    foreach ($first as $i => $value) {
        $error = abs($value - $second[$i]);
        $bin = 0;
        while ($error > $upper[$bin]) $bin++;
        $histogram[$bin]++;
    }
    $lines[] = 'error_histogram ' . implode(' ', $histogram);
    return $lines;
}

function compareSampling(object $original, array $originalPlanes, object $params, object $tables): array
{
    $lines = [];
    foreach (['444', '422', '420'] as $sampling) {
        $encoded = encode($original, $params->qualities[0], $sampling, $params->huffman, $params->restart_interval, $tables);
        $decoded = decode($encoded->bytes, $tables->C);
        $metrics = imageMetrics($original, $originalPlanes, $decoded);
        $lines[] = 'sampling_compare ' . $sampling . ' ' . count($encoded->bytes) . ' ' . $metrics->channels[1] . ' ' . $metrics->channels[2] . ' ' . $metrics->rgb;
    }
    return $lines;
}

function repeatedCompression(object $original, object $params, object $tables): array
{
    $previous = $original;
    $lines = [];
    $originalValues = flattenPixels($original->pixels);
    for ($generation = 1; $generation <= $params->generations; $generation++) {
        $encoded = encode($previous, $params->qualities[0], $params->sampling, $params->huffman, $params->restart_interval, $tables);
        $next = decode($encoded->bytes, $tables->C)->image;
        $changed = 0;
        for ($y = 0; $y < $original->height; $y++) for ($x = 0; $x < $original->width; $x++) {
            if ($previous->pixels[$y][$x] !== $next->pixels[$y][$x]) $changed++;
        }
        $lines[] = 'generation ' . $generation . ' ' . count($encoded->bytes) . ' ' . psnr($originalValues, flattenPixels($next->pixels)) . ' ' . $changed;
        $previous = $next;
    }
    return $lines;
}

function qualitySearch(object $original, object $params, object $tables): array
{
    $lines = [];
    $lo = 1;
    $hi = 100;
    while ($lo < $hi) {
        $mid = intdiv($lo + $hi + 1, 2);
        $encoded = encode($original, $mid, $params->sampling, $params->huffman, $params->restart_interval, $tables);
        $lines[] = 'rate_control_step ' . $mid . ' ' . count($encoded->bytes);
        if (count($encoded->bytes) <= $params->target_bytes) $lo = $mid;
        else $hi = $mid - 1;
    }
    $encoded = encode($original, $lo, $params->sampling, $params->huffman, $params->restart_interval, $tables);
    $decoded = decode($encoded->bytes, $tables->C);
    $lines[] = 'rate_control ' . $lo . ' ' . count($encoded->bytes) . ' ' . (count($encoded->bytes) <= $params->target_bytes ? 'yes' : 'no')
        . ' ' . psnr(flattenPixels($original->pixels), flattenPixels($decoded->image->pixels));
    return $lines;
}

function repairStream(object $decoded, object $tables): object
{
    $originalLayout = $decoded->layout;
    $first = $originalLayout->components[0];
    $layout = geometry($originalLayout->width, $originalLayout->height, standardComponents($first->h, $first->v), $originalLayout->restart);
    $quant = [$decoded->quant[$first->quant], $decoded->quant[$originalLayout->components[1]->quant]];
    $blocks = [];
    foreach ($layout->blocks as $i => $item) {
        $block = clone $item;
        $block->z = $decoded->blocks[$i]->z;
        $blocks[] = $block;
    }
    $encoded = assemble($layout, $quant, $blocks, 'optimized', $tables->huffman);
    $repaired = decode($encoded->bytes, $tables->C);
    $encoded->identical = flattenPixels($repaired->image->pixels) === flattenPixels($decoded->image->pixels);
    return $encoded;
}

function streamReport(object $decoded, object $repair): array
{
    $lines = [];
    foreach ($decoded->segments as $segment) $lines[] = 'stream_segment ' . $segment->position . ' ' . $segment->name . ' ' . $segment->length;
    $lines[] = 'stream_image ' . $decoded->layout->width . ' ' . $decoded->layout->height;
    foreach ($decoded->layout->components as $component) $lines[] = 'stream_component ' . $component->id . ' ' . $component->h . ' ' . $component->v
        . ' ' . $component->quant . ' ' . $component->dc . ' ' . $component->ac;
    $order = zigzag();
    $ids = array_keys($decoded->quant);
    sort($ids, SORT_NUMERIC);
    foreach ($ids as $id) $lines[] = 'stream_quant ' . $id . ' ' . implode(' ', array_map(fn($i) => $decoded->quant[$id][$i], $order));
    $keys = array_keys($decoded->huffman);
    sort($keys, SORT_NUMERIC);
    foreach ($keys as $key) {
        $table = $decoded->huffman[$key];
        $longest = 16;
        while ($longest > 0 && $table->bits[$longest - 1] === 0) $longest--;
        $lines[] = 'stream_huffman ' . $table->tableClass . ' ' . $table->id . ' symbols ' . count($table->values) . ' longest ' . $longest;
    }
    $counts = ['ok' => 0, 'damaged' => 0, 'lost' => 0];
    foreach ($decoded->intervals as $interval) $counts[$interval->state]++;
    $lines[] = 'stream_restart ' . $decoded->layout->restart . ' intervals ' . count($decoded->intervals)
        . ' ok ' . $counts['ok'] . ' damaged ' . $counts['damaged'] . ' lost ' . $counts['lost'];
    foreach ($decoded->intervals as $interval) {
        $state = $interval->state === 'damaged' ? 'damaged ' . $interval->kind . ' mcu ' . $interval->mcu
            . ' offset ' . $interval->offset . ' resync ' . $interval->resync : $interval->state;
        $lines[] = 'stream_interval ' . $interval->number . ' ' . $interval->first . ' ' . $interval->count . ' ' . $state;
    }
    $lines[] = 'stream_scan_bytes ' . $decoded->scanBytes;
    $lines[] = 'repair ' . count($repair->bytes) . ' ' . $repair->headerBytes . ' ' . $repair->scanBytes . ' identical ' . ($repair->identical ? 'yes' : 'no');
    return $lines;
}

$image = readPPM('input/image.ppm');
$params = readParams('input/params.txt');
$tables = readTables('input/tables.txt');
$originalPlanes = planes($image);
$rates = ['quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error'];
$reference = $referenceDecoded = null;
foreach ($params->qualities as $quality) {
    $standard = encode($image, $quality, $params->sampling, 'standard', $params->restart_interval, $tables);
    $optimized = encode($image, $quality, $params->sampling, 'optimized', $params->restart_interval, $tables);
    $encoded = $params->huffman === 'standard' ? $standard : $optimized;
    $decoded = decode($encoded->bytes, $tables->C);
    $metrics = imageMetrics($image, $originalPlanes, $decoded);
    $rates[] = implode(',', array_merge([$quality, count($standard->bytes), count($optimized->bytes),
        fraction(8 * count($encoded->bytes), $image->width * $image->height)], $metrics->channels, [$metrics->rgb, $metrics->maximum]));
    if ($reference === null) { $reference = $encoded; $referenceDecoded = $decoded; }
}
$stats = blockStatistics($reference, $referenceDecoded);
$report = referenceReport($reference, $stats, $image, $referenceDecoded, $params);
foreach ($params->truncate as $keep) {
    $truncated = render($referenceDecoded->layout, $referenceDecoded->blocks, $referenceDecoded->quant, $tables->C, $keep);
    $report[] = 'truncate ' . $keep . ' ' . psnr(flattenPlane($originalPlanes[0]), flattenPlane($truncated->planes[0]));
}
foreach (compareSampling($image, $originalPlanes, $params, $tables) as $line) $report[] = $line;
foreach (repeatedCompression($image, $params, $tables) as $line) $report[] = $line;
foreach (qualitySearch($image, $params, $tables) as $line) $report[] = $line;
$stream = decode(readHex('input/stream.hex'), $tables->C);
$repair = repairStream($stream, $tables);
foreach (streamReport($stream, $repair) as $line) $report[] = $line;
if (!is_dir('output')) mkdir('output', 0777, true);
writeLines('output/rate_distortion.csv', $rates);
writePPM('output/decoded.ppm', $referenceDecoded->image);
writeHex('output/bitstream.hex', $reference->bytes);
writePPM('output/thumbnail.ppm', thumbnail($referenceDecoded));
writeLines('output/huffman_tables.txt', huffmanLines($reference));
writeLines('output/blocks.txt', $stats->lines);
writePPM('output/stream_decoded.ppm', $stream->image);
writeHex('output/repaired.hex', $repair->bytes);
writeLines('output/report.txt', $report);
