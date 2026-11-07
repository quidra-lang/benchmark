<?php

require_once __DIR__ . '/bitio.php';
require_once __DIR__ . '/lzw.php';
require_once __DIR__ . '/lz77.php';
require_once __DIR__ . '/huffman.php';
require_once __DIR__ . '/arith_coder.php';

const METHODS = ['STORE', 'LZW', 'LZ77', 'LZH', 'ARITH'];
const STATUSES = ['ok', 'repaired', 'checksum', 'error', 'unsupported', 'truncated', 'bad_header'];

function readLines(string $filename): array
{
    $text = file_get_contents($filename);
    return $text === '' ? [] : explode("\n", substr($text, 0, -1));
}

function ratio(int $compressed, int $original): string
{
    return $original === 0 ? '-' : (string) intdiv(1000 * $compressed, $original);
}

function hex32(int $value): string
{
    return sprintf('%08x', $value);
}

function methodName(int $method): string
{
    return $method < count(METHODS) ? METHODS[$method] : '#' . $method;
}

function fixedLengths(int $symbols): array
{
    $width = bits($symbols - 1);
    $shorter = (1 << $width) - $symbols;
    $lengths = [];
    for ($symbol = 0; $symbol < $symbols; $symbol++) {
        $lengths[] = $symbol < $shorter ? $width - 1 : $width;
    }
    return $lengths;
}

function codebook(array $lengths): array
{
    $codes = huffmanCanonical($lengths);
    $byLength = array_fill(0, 16, []);
    $maximum = 0;
    $used = 0;
    foreach ($lengths as $symbol => $length) {
        if ($length > 0) {
            $byLength[$length][$codes[$symbol]] = $symbol;
            $maximum = max($maximum, $length);
            $used++;
        }
    }
    return ['lengths' => $lengths, 'codes' => $codes, 'byLength' => $byLength, 'maximum' => $maximum, 'used' => $used];
}

function writeTable(BitWriter $writer, array $lengths): void
{
    $symbol = 0;
    $count = count($lengths);
    while ($symbol < $count) {
        if ($lengths[$symbol] > 0) {
            $writer->write($lengths[$symbol++], 4);
        } else {
            $run = 1;
            while ($run < 256 && $symbol + $run < $count && $lengths[$symbol + $run] === 0) {
                $run++;
            }
            $writer->write(0, 4);
            $writer->write($run - 1, 8);
            $symbol += $run;
        }
    }
}

function readTable(BitReader $reader, int $symbols): array
{
    $lengths = [];
    while (count($lengths) < $symbols) {
        $length = $reader->read(4);
        if ($length > 0) {
            $lengths[] = $length;
        } else {
            $run = $reader->read(8) + 1;
            if (count($lengths) + $run > $symbols) {
                throw new DecodingError('bad_table');
            }
            for ($i = 0; $i < $run; $i++) {
                $lengths[] = 0;
            }
        }
    }
    $used = 0;
    $singleLength = 0;
    $kraft = 0;
    foreach ($lengths as $length) {
        if ($length > 0) {
            $used++;
            $singleLength = $length;
            $kraft += 1 << (15 - $length);
        }
    }
    if (($used === 1 && $singleLength !== 1) || ($used >= 2 && $kraft !== 32768)) {
        throw new DecodingError('bad_table');
    }
    return codebook($lengths);
}

function readSymbol(BitReader $reader, array $table): int
{
    if ($table['used'] === 0) {
        throw new DecodingError('bad_code');
    }
    $value = 0;
    for ($width = 1; $width <= $table['maximum']; $width++) {
        $value = ($value << 1) | $reader->read(1);
        if (isset($table['byLength'][$width][$value])) {
            return $table['byLength'][$width][$value];
        }
    }
    throw new DecodingError('bad_code');
}

function writeLzhTokens(BitWriter $writer, array $tokens, array $literalTable, array $distanceTable): void
{
    foreach ($tokens as $token) {
        $symbol = $token['literal'] ?? 256 + $token['length'] - 3;
        $writer->write($literalTable['codes'][$symbol], $literalTable['lengths'][$symbol]);
        if (isset($token['literal'])) {
            continue;
        }
        $offset = $token['distance'] - 1;
        $slot = bits($offset);
        $writer->write($distanceTable['codes'][$slot], $distanceTable['lengths'][$slot]);
        if ($slot >= 2) {
            $writer->write($offset - (1 << ($slot - 1)), $slot - 1);
        }
    }
}

function encodeLzh(array $tokens, array $parameters): array
{
    $literalCount = 256 + (1 << $parameters['lengthBits']);
    $distanceCount = $parameters['offsetBits'] + 1;
    $literalFrequency = array_fill(0, $literalCount, 0);
    $distanceFrequency = array_fill(0, $distanceCount, 0);
    foreach ($tokens as $token) {
        $symbol = $token['literal'] ?? 256 + $token['length'] - 3;
        $literalFrequency[$symbol]++;
        if (!isset($token['literal'])) {
            $distanceFrequency[bits($token['distance'] - 1)]++;
        }
    }
    $literalLengths = huffmanLimitedLengths($literalFrequency, $parameters['maxCodeLength']);
    $distanceLengths = huffmanLimitedLengths($distanceFrequency, $parameters['maxCodeLength']);
    $literalTable = codebook($literalLengths['lengths']);
    $distanceTable = codebook($distanceLengths['lengths']);
    $dynamic = new BitWriter();
    $dynamic->write(1, 1);
    writeTable($dynamic, $literalTable['lengths']);
    writeTable($dynamic, $distanceTable['lengths']);
    $tableBits = $dynamic->length - 1;
    writeLzhTokens($dynamic, $tokens, $literalTable, $distanceTable);
    $codeBits = $dynamic->length - 1 - $tableBits;
    $fixed = new BitWriter();
    $fixed->write(0, 1);
    writeLzhTokens($fixed, $tokens, codebook(fixedLengths($literalCount)), codebook(fixedLengths($distanceCount)));
    $fixedBits = $fixed->length - 1;
    $useFixed = $fixedBits <= $tableBits + $codeBits;
    $statistics = ['mode' => $useFixed ? 'fixed' : 'dynamic', 'fixedBits' => $fixedBits,
        'tableBits' => $tableBits, 'codeBits' => $codeBits,
        'halvings' => $literalLengths['halvings'] + $distanceLengths['halvings'],
        'literalUsed' => $literalTable['used'], 'literalMaximum' => $literalTable['maximum'],
        'distanceUsed' => $distanceTable['used'], 'distanceMaximum' => $distanceTable['maximum'],
        'slots' => $distanceFrequency];
    return ['payload' => ($useFixed ? $fixed : $dynamic)->finish(), 'statistics' => $statistics];
}

function encodeLz77(array $tokens, array $parameters): string
{
    $writer = new BitWriter();
    foreach ($tokens as $token) {
        if (isset($token['literal'])) {
            $writer->write(0, 1);
            $writer->write($token['literal'], 8);
        } else {
            $writer->write(1, 1);
            $writer->write($token['distance'] - 1, $parameters['offsetBits']);
            $writer->write($token['length'] - 3, $parameters['lengthBits']);
        }
    }
    return $writer->finish();
}

function decodeLz77(string $payload, int $originalLength, array $parameters, string &$output): void
{
    $reader = new BitReader($payload);
    while (strlen($output) < $originalLength) {
        if ($reader->read(1) === 0) {
            $output .= chr($reader->read(8));
        } else {
            $distance = $reader->read($parameters['offsetBits']) + 1;
            $length = $reader->read($parameters['lengthBits']) + 3;
            lz77CopyMatch($output, $distance, $length, $originalLength);
        }
    }
}

function decodeLzh(string $payload, int $originalLength, array $parameters, string &$output): void
{
    $reader = new BitReader($payload);
    $dynamic = $reader->read(1) === 1;
    $literalCount = 256 + (1 << $parameters['lengthBits']);
    $distanceCount = $parameters['offsetBits'] + 1;
    $literalTable = $dynamic ? readTable($reader, $literalCount) : codebook(fixedLengths($literalCount));
    $distanceTable = $dynamic ? readTable($reader, $distanceCount) : codebook(fixedLengths($distanceCount));
    while (strlen($output) < $originalLength) {
        $symbol = readSymbol($reader, $literalTable);
        if ($symbol < 256) {
            $output .= chr($symbol);
        } else {
            $slot = readSymbol($reader, $distanceTable);
            $offset = $slot >= 2 ? (1 << ($slot - 1)) + $reader->read($slot - 1) : $slot;
            lz77CopyMatch($output, $offset + 1, $symbol - 253, $originalLength);
        }
    }
}

function decodePayload(int $method, string $payload, int $originalLength, array $parameters): array
{
    $output = '';
    try {
        if ($method === 0) {
            if (strlen($payload) < $originalLength) {
                $output = $payload;
                throw new DecodingError('end_of_data');
            }
            $output = substr($payload, 0, $originalLength);
        } elseif ($method === 1) {
            lzwDecode($payload, $originalLength, $output);
        } elseif ($method === 2) {
            decodeLz77($payload, $originalLength, $parameters, $output);
        } elseif ($method === 3) {
            decodeLzh($payload, $originalLength, $parameters, $output);
        } else {
            arithDecode($payload, $originalLength, $output);
        }
    } catch (DecodingError $error) {
        return ['error' => $error->kind, 'position' => strlen($output)];
    }
    return ['data' => $output];
}

function adler32(string $data): int
{
    $low = 1;
    $high = 0;
    $length = strlen($data);
    for ($i = 0; $i < $length; $i++) {
        $low = ($low + ord($data[$i])) % 65521;
        $high = ($high + $low) % 65521;
    }
    return $high * 65536 + $low;
}

function modularPower(int $base, int $exponent): int
{
    $result = 1;
    while ($exponent > 0) {
        if ($exponent % 2 === 1) {
            $result = ($result * $base) % 65521;
        }
        $base = ($base * $base) % 65521;
        $exponent = intdiv($exponent, 2);
    }
    return $result;
}

function repairByte(string $data, int $stored, int $computed): ?array
{
    $deltaA = (($stored % 65536 - $computed % 65536) % 65521 + 65521) % 65521;
    $deltaB = ((intdiv($stored, 65536) - intdiv($computed, 65536)) % 65521 + 65521) % 65521;
    if ($deltaA >= 1 && $deltaA <= 255) {
        $delta = $deltaA;
    } elseif ($deltaA >= 65266 && $deltaA <= 65520) {
        $delta = $deltaA - 65521;
    } else {
        return null;
    }
    $inverse = modularPower($deltaA, 65519);
    $distance = ($deltaB * $inverse) % 65521;
    if ($distance < 1 || $distance > strlen($data)) {
        return null;
    }
    $position = strlen($data) - $distance;
    $before = ord($data[$position]);
    $after = $before + $delta;
    if ($after < 0 || $after > 255) {
        return null;
    }
    $data[$position] = chr($after);
    if (adler32($data) !== $stored) {
        return null;
    }
    return ['data' => $data, 'position' => $position, 'before' => $before, 'after' => $after];
}

function buildArchive(array $entries, array $parameters): string
{
    $archive = 'TXAR' . pack('CCn', $parameters['offsetBits'], $parameters['lengthBits'], count($entries));
    foreach ($entries as $entry) {
        $header = chr(strlen($entry['name'])) . $entry['name'] . pack('CNNN', $entry['method'],
            strlen($entry['data']), strlen($entry['payload']), adler32($entry['data']));
        $check = 0;
        $length = strlen($header);
        for ($i = 0; $i < $length; $i++) {
            $check += ord($header[$i]);
        }
        $archive .= $header . chr($check % 256) . $entry['payload'];
    }
    return $archive;
}

function readUint32(string $data, int $offset): int
{
    return unpack('Nvalue', substr($data, $offset, 4))['value'];
}

function parseArchive(string $data): array
{
    $length = strlen($data);
    $archive = ['length' => $length, 'entries' => [], 'stopped' => false, 'trailing' => 0, 'error' => null];
    if ($length < 8 || substr($data, 0, 4) !== 'TXAR') {
        $archive['error'] = 'bad_magic';
        return $archive;
    }
    $archive['offsetBits'] = ord($data[4]);
    $archive['lengthBits'] = ord($data[5]);
    if ($archive['offsetBits'] < 6 || $archive['offsetBits'] > 12 || $archive['lengthBits'] < 2 || $archive['lengthBits'] > 5) {
        $archive['error'] = 'bad_params';
        return $archive;
    }
    $archive['expected'] = ord($data[6]) * 256 + ord($data[7]);
    $position = 8;
    for ($number = 1; $number <= $archive['expected']; $number++) {
        $entry = ['number' => $number, 'offset' => $position, 'validHeader' => false];
        if ($position >= $length || $position + 15 + ord($data[$position]) > $length) {
            $entry['status'] = 'truncated';
            $archive['entries'][] = $entry;
            $archive['stopped'] = true;
            break;
        }
        $nameLength = ord($data[$position]);
        $entry['name'] = substr($data, $position + 1, $nameLength);
        $entry['method'] = ord($data[$position + 1 + $nameLength]);
        $entry['original'] = readUint32($data, $position + 2 + $nameLength);
        $entry['compressed'] = readUint32($data, $position + 6 + $nameLength);
        $entry['adler'] = readUint32($data, $position + 10 + $nameLength);
        $entry['start'] = $position + 15 + $nameLength;
        $next = $entry['start'] + $entry['compressed'];
        $check = 0;
        for ($i = $position; $i < $entry['start'] - 1; $i++) {
            $check += ord($data[$i]);
        }
        $validName = $nameLength >= 1 && $nameLength <= 32 && !preg_match('/[^a-z0-9._-]/', $entry['name']);
        if ($check % 256 !== ord($data[$entry['start'] - 1]) || !$validName) {
            $entry['status'] = 'bad_header';
            $archive['entries'][] = $entry;
            $position = $next;
            if ($position > $length) {
                $archive['stopped'] = true;
                break;
            }
            continue;
        }
        $entry['validHeader'] = true;
        if ($next > $length) {
            $entry['status'] = 'truncated';
            $archive['entries'][] = $entry;
            $archive['stopped'] = true;
            break;
        }
        if ($entry['method'] >= count(METHODS)) {
            $entry['status'] = 'unsupported';
        } else {
            $decoded = decodePayload($entry['method'], substr($data, $entry['start'], $entry['compressed']), $entry['original'], $archive);
            if (isset($decoded['error'])) {
                $entry['status'] = 'error';
                $entry['error'] = $decoded['error'];
                $entry['errorPosition'] = $decoded['position'];
            } else {
                $entry['data'] = $decoded['data'];
                $entry['computed'] = adler32($entry['data']);
                if ($entry['computed'] === $entry['adler']) {
                    $entry['status'] = 'ok';
                } else {
                    $entry['repair'] = repairByte($entry['data'], $entry['adler'], $entry['computed']);
                    $entry['status'] = $entry['repair'] === null ? 'checksum' : 'repaired';
                    if ($entry['repair'] !== null) {
                        $entry['data'] = $entry['repair']['data'];
                    }
                }
            }
        }
        $archive['entries'][] = $entry;
        $position = $next;
    }
    if (!$archive['stopped']) {
        $archive['trailing'] = $length - $position;
    }
    return $archive;
}

function tokenStatistics(array $tokens): array
{
    $statistics = ['tokens' => count($tokens), 'literals' => 0, 'matches' => 0, 'matched' => 0, 'longest' => 0, 'farthest' => 0];
    foreach ($tokens as $token) {
        if (isset($token['literal'])) {
            $statistics['literals']++;
        } else {
            $statistics['matches']++;
            $statistics['matched'] += $token['length'];
            $statistics['longest'] = max($statistics['longest'], $token['length']);
            $statistics['farthest'] = max($statistics['farthest'], $token['distance']);
        }
    }
    return $statistics;
}

function compress(string $data, array $parameters): array
{
    $tokens = lz77Tokens($data, $parameters['offsetBits'], $parameters['lengthBits']);
    $dictionary = lzwEncode($data);
    $sliding = encodeLz77($tokens, $parameters);
    $hybrid = encodeLzh($tokens, $parameters);
    $arithmetic = arithEncode($data);
    $payloads = [$data, $dictionary['payload'], $sliding, $hybrid['payload'], $arithmetic['payload']];
    $method = 0;
    for ($i = 1; $i < count(METHODS); $i++) {
        if (strlen($payloads[$i]) < strlen($payloads[$method])) {
            $method = $i;
        }
    }
    return ['payloads' => $payloads, 'method' => $method, 'payload' => $payloads[$method],
        'lzw' => $dictionary['statistics'], 'lz77' => tokenStatistics($tokens),
        'lzh' => $hybrid['statistics'], 'arith' => $arithmetic['statistics']];
}

function verifiedEntries(array $archive, array $sources): int
{
    $verified = 0;
    foreach ($archive['entries'] as $entry) {
        if ($entry['status'] === 'ok' && $entry['data'] === $sources[$entry['number'] - 1]['data']) {
            $verified++;
        }
    }
    return $verified;
}

function creationReports(array $files, array $parameters, string $archiveData, array $verification): array
{
    $sizes = ['params offset_bits ' . $parameters['offsetBits'] . ' length_bits ' . $parameters['lengthBits']
        . ' window ' . (1 << $parameters['offsetBits']) . ' lookahead ' . ((1 << $parameters['lengthBits']) + 2)
        . ' max_code_length ' . $parameters['maxCodeLength']];
    $analysis = [];
    $totals = array_fill(0, 5, 0);
    $chosen = array_fill(0, 5, 0);
    $original = 0;
    $best = 0;
    foreach ($files as $file) {
        $encoded = $file['encoded'];
        $length = strlen($file['data']);
        $methods = [];
        foreach (METHODS as $method => $name) {
            $value = strlen($encoded['payloads'][$method]);
            $methods[] = $name . ' ' . $value . ' ' . ratio($value, $length);
            $totals[$method] += $value;
        }
        $sizes[] = 'file ' . $file['name'] . ' original ' . $length . ' ' . implode(' ', $methods)
            . ' best ' . METHODS[$encoded['method']];
        $original += $length;
        $best += strlen($encoded['payload']);
        $chosen[$encoded['method']]++;
        $dictionary = $encoded['lzw'];
        $analysis[] = 'lzw ' . $file['name'] . ' codes ' . $dictionary['codes'] . ' clears ' . $dictionary['clears']
            . ' widths ' . implode(' ', $dictionary['widths']) . ' longest ' . $dictionary['longest'];
        $tokens = $encoded['lz77'];
        $analysis[] = 'lz77 ' . $file['name'] . ' tokens ' . $tokens['tokens'] . ' literals ' . $tokens['literals']
            . ' matches ' . $tokens['matches'] . ' matched ' . $tokens['matched'] . ' longest ' . $tokens['longest']
            . ' farthest ' . $tokens['farthest'];
        $hybrid = $encoded['lzh'];
        $analysis[] = 'lzh ' . $file['name'] . ' mode ' . $hybrid['mode'] . ' fixed_bits ' . $hybrid['fixedBits']
            . ' table_bits ' . $hybrid['tableBits'] . ' code_bits ' . $hybrid['codeBits'] . ' halvings ' . $hybrid['halvings']
            . ' litlen_used ' . $hybrid['literalUsed'] . ' litlen_max ' . $hybrid['literalMaximum']
            . ' offset_used ' . $hybrid['distanceUsed'] . ' offset_max ' . $hybrid['distanceMaximum'];
        $analysis[] = 'slots ' . $file['name'] . ' ' . implode(' ', $hybrid['slots']);
        $arithmetic = $encoded['arith'];
        $analysis[] = 'arith ' . $file['name'] . ' bits ' . $arithmetic['bits'] . ' contexts ' . $arithmetic['contexts']
            . ' rescales ' . $arithmetic['rescales'];
    }
    $methodTotals = [];
    $choiceCounts = [];
    foreach (METHODS as $method => $name) {
        $methodTotals[] = $name . ' ' . $totals[$method] . ' ' . ratio($totals[$method], $original);
        $choiceCounts[] = $name . ' ' . $chosen[$method];
    }
    $sizes[] = 'total original ' . $original . ' ' . implode(' ', $methodTotals) . ' best ' . $best . ' ' . ratio($best, $original);
    $sizes[] = 'chosen ' . implode(' ', $choiceCounts);
    $sizes[] = 'archive bytes ' . strlen($archiveData) . ' entries ' . count($files) . ' ratio ' . ratio(strlen($archiveData), $original);
    $sizes[] = 'verify entries ' . count($verification['entries']) . ' ok ' . verifiedEntries($verification, $files);
    return ['sizes' => $sizes, 'analysis' => $analysis];
}

function listingLines(array $archive): array
{
    if ($archive['error'] !== null) {
        return ['archive bytes ' . $archive['length'] . ' error ' . $archive['error']];
    }
    $lines = ['archive bytes ' . $archive['length'] . ' offset_bits ' . $archive['offsetBits']
        . ' length_bits ' . $archive['lengthBits'] . ' entries ' . $archive['expected']];
    $totals = array_fill(0, 5, ['entries' => 0, 'original' => 0, 'compressed' => 0]);
    $listed = 0;
    foreach ($archive['entries'] as $entry) {
        $prefix = 'entry ' . $entry['number'] . ' offset ' . $entry['offset'];
        if (!$entry['validHeader']) {
            $lines[] = $prefix . ($entry['status'] === 'bad_header' ? ' bad_header' : ' truncated header');
            continue;
        }
        $listed++;
        $lines[] = $prefix . ' method ' . methodName($entry['method']) . ' original ' . $entry['original']
            . ' compressed ' . $entry['compressed'] . ' ratio ' . ratio($entry['compressed'], $entry['original'])
            . ' adler ' . hex32($entry['adler']) . ' name ' . $entry['name'];
        if ($entry['method'] < 5) {
            $totals[$entry['method']]['entries']++;
            $totals[$entry['method']]['original'] += $entry['original'];
            $totals[$entry['method']]['compressed'] += $entry['compressed'];
        }
    }
    foreach (METHODS as $method => $name) {
        $total = $totals[$method];
        $lines[] = 'method ' . $name . ' entries ' . $total['entries'] . ' original ' . $total['original']
            . ' compressed ' . $total['compressed'] . ' ratio ' . ratio($total['compressed'], $total['original']);
    }
    $lines[] = 'end listed ' . $listed . ' of ' . $archive['expected'] . ' stop '
        . ($archive['stopped'] ? 'truncated' : 'complete') . ' trailing ' . $archive['trailing'];
    return $lines;
}

function testLines(array $archive, array $salvaged, string $salvageData, array $salvageVerification): array
{
    $lines = [];
    if ($archive['error'] !== null) {
        $lines[] = 'archive error ' . $archive['error'];
    } else {
        $counts = array_fill_keys(STATUSES, 0);
        foreach ($archive['entries'] as $entry) {
            $counts[$entry['status']]++;
            $prefix = 'entry ' . $entry['number'] . ' offset ' . $entry['offset'];
            if (!$entry['validHeader']) {
                $lines[] = $prefix . ($entry['status'] === 'bad_header' ? ' status bad_header' : ' status truncated header');
                continue;
            }
            $details = '';
            if ($entry['status'] === 'repaired') {
                $details = ' byte ' . $entry['repair']['position'] . ' from ' . $entry['repair']['before'] . ' to ' . $entry['repair']['after'];
            } elseif ($entry['status'] === 'checksum') {
                $details = ' stored ' . hex32($entry['adler']) . ' computed ' . hex32($entry['computed']);
            } elseif ($entry['status'] === 'error') {
                $details = ' ' . $entry['error'] . ' at ' . $entry['errorPosition'];
            } elseif ($entry['status'] === 'truncated') {
                $details = ' payload have ' . ($archive['length'] - $entry['start']) . ' need ' . $entry['compressed'];
            }
            $lines[] = $prefix . ' name ' . $entry['name'] . ' method ' . methodName($entry['method'])
                . ' status ' . $entry['status'] . $details;
        }
        $statuses = [];
        foreach (STATUSES as $status) {
            $statuses[] = $status . ' ' . $counts[$status];
        }
        $lines[] = 'summary entries ' . $archive['expected'] . ' checked ' . count($archive['entries']) . ' '
            . implode(' ', $statuses) . ' missing ' . ($archive['expected'] - count($archive['entries'])) . ' trailing ' . $archive['trailing'];
    }
    $original = 0;
    foreach ($salvaged as $entry) {
        $original += strlen($entry['data']);
        $lines[] = 'salvage ' . $entry['name'] . ' method ' . METHODS[$entry['method']] . ' compressed ' . strlen($entry['payload'])
            . ' was ' . methodName($entry['source']['method']) . ' ' . $entry['source']['compressed'];
    }
    $lines[] = 'salvaged entries ' . count($salvaged) . ' bytes ' . strlen($salvageData) . ' original ' . $original
        . ' verified ' . verifiedEntries($salvageVerification, $salvaged);
    return $lines;
}

function textLines(string $data): array
{
    return $data === '' ? [] : explode("\n", substr($data, 0, -1));
}

function extractionLines(array $intact): array
{
    $result = [];
    foreach ($intact as $entry) {
        $lines = textLines($entry['data']);
        $words = 0;
        $longest = 0;
        foreach ($lines as $line) {
            $words += preg_match_all('/[^ ]+/', $line);
            $longest = max($longest, strlen($line));
        }
        $result[] = 'file ' . $entry['name'] . ' bytes ' . strlen($entry['data']) . ' lines ' . count($lines)
            . ' words ' . $words . ' longest ' . $longest;
        foreach ($lines as $line) {
            $result[] = $line;
        }
    }
    return $result;
}

function lineEdits(array $oldLines, array $newLines, int $prefix): array
{
    $oldCount = count($oldLines);
    $newCount = count($newLines);
    $remainingNew = $newCount - $prefix;
    $blockSize = 1024;
    $boundaries = [];
    if ($oldCount - $prefix > $blockSize && $remainingNew > 0) {
        $later = array_fill(0, $remainingNew + 1, 0);
        for ($row = $oldCount - 1; $row >= $prefix + $blockSize; $row--) {
            $current = array_fill(0, $remainingNew + 1, 0);
            for ($column = $remainingNew - 1; $column >= 0; $column--) {
                $current[$column] = $oldLines[$row] === $newLines[$prefix + $column]
                    ? $later[$column + 1] + 1 : max($later[$column], $current[$column + 1]);
            }
            if (($row - $prefix) % $blockSize === 0) {
                $boundaries[$row] = pack('v*', ...$current);
            }
            $later = $current;
        }
    }
    $old = $prefix;
    $next = $prefix;
    $removed = 0;
    $added = 0;
    $edits = [];
    while ($old < $oldCount && $next < $newCount) {
        $end = min($oldCount, $old + $blockSize);
        $later = $end === $oldCount ? array_fill(0, $remainingNew + 1, 0) : array_values(unpack('v*', $boundaries[$end]));
        $deletion = [];
        for ($row = $end - 1; $row >= $old; $row--) {
            $current = array_fill(0, $remainingNew + 1, 0);
            $decisions = str_repeat("\0", intdiv($remainingNew + 7, 8));
            for ($column = $remainingNew - 1; $column >= $next - $prefix; $column--) {
                if ($oldLines[$row] === $newLines[$prefix + $column]) {
                    $current[$column] = $later[$column + 1] + 1;
                } elseif ($later[$column] >= $current[$column + 1]) {
                    $current[$column] = $later[$column];
                    $byte = intdiv($column, 8);
                    $decisions[$byte] = chr(ord($decisions[$byte]) | (1 << ($column % 8)));
                } else {
                    $current[$column] = $current[$column + 1];
                }
            }
            $deletion[$row] = $decisions;
            $later = $current;
        }
        while ($old < $end && $next < $newCount) {
            $column = $next - $prefix;
            if ($oldLines[$old] === $newLines[$next]) {
                $old++;
                $next++;
            } elseif ((ord($deletion[$old][intdiv($column, 8)]) & (1 << ($column % 8))) !== 0) {
                $edits[] = '-' . ($old + 1) . ':' . $oldLines[$old];
                $old++;
                $removed++;
            } else {
                $edits[] = '+' . ($next + 1) . ':' . $newLines[$next];
                $next++;
                $added++;
            }
        }
    }
    while ($old < $oldCount) {
        $edits[] = '-' . ($old + 1) . ':' . $oldLines[$old];
        $old++;
        $removed++;
    }
    while ($next < $newCount) {
        $edits[] = '+' . ($next + 1) . ':' . $newLines[$next];
        $next++;
        $added++;
    }
    return ['edits' => $edits, 'removed' => $removed, 'added' => $added];
}

function comparisonLines(array $intact, array $files): array
{
    $manifest = [];
    foreach ($files as $file) {
        $manifest["\0" . $file['name']] = $file;
    }
    $present = [];
    $lines = [];
    foreach ($intact as $entry) {
        $key = "\0" . $entry['name'];
        $present[$key] = true;
        if (!isset($manifest[$key])) {
            $lines[] = 'archive_only ' . $entry['name'];
            continue;
        }
        $oldLines = textLines($entry['data']);
        $newLines = textLines($manifest[$key]['data']);
        $oldCount = count($oldLines);
        $newCount = count($newLines);
        $first = 0;
        while ($first < $oldCount && $first < $newCount && $oldLines[$first] === $newLines[$first]) {
            $first++;
        }
        if ($first === $oldCount && $first === $newCount) {
            $lines[] = 'same ' . $entry['name'] . ' lines ' . $oldCount;
        } else {
            $changes = lineEdits($oldLines, $newLines, $first);
            $lines[] = 'differs ' . $entry['name'] . ' first_line ' . ($first + 1) . ' archive_lines ' . $oldCount
                . ' manifest_lines ' . $newCount . ' removed ' . $changes['removed'] . ' added ' . $changes['added'];
            foreach ($changes['edits'] as $edit) {
                $lines[] = $edit;
            }
        }
    }
    foreach ($files as $file) {
        if (!isset($present["\0" . $file['name']])) {
            $lines[] = 'new ' . $file['name'];
        }
    }
    return $lines;
}

function hexLines(string $data): array
{
    return $data === '' ? [] : str_split(bin2hex($data), 64);
}

function writeLines(string $filename, array $lines): void
{
    file_put_contents('output/' . $filename, $lines ? implode("\n", $lines) . "\n" : '');
}

function main(): void
{
    $manifest = readLines('input/manifest.txt');
    $parameters = ['offsetBits' => (int) explode(' ', $manifest[0])[1],
        'lengthBits' => (int) explode(' ', $manifest[1])[1],
        'maxCodeLength' => (int) explode(' ', $manifest[2])[1]];
    $files = [];
    for ($i = 3; $i < count($manifest); $i++) {
        $name = substr($manifest[$i], 5);
        $data = file_get_contents('input/files/' . $name);
        $files[] = ['name' => $name, 'data' => $data, 'encoded' => compress($data, $parameters)];
    }
    $createdEntries = [];
    foreach ($files as $file) {
        $createdEntries[] = ['name' => $file['name'], 'data' => $file['data'], 'method' => $file['encoded']['method'],
            'payload' => $file['encoded']['payload']];
    }
    $archiveData = buildArchive($createdEntries, $parameters);
    $verification = parseArchive($archiveData);
    $reports = creationReports($files, $parameters, $archiveData, $verification);
    $supplied = hex2bin(implode('', readLines('input/archive.hex')));
    $archive = parseArchive($supplied);
    $intact = [];
    foreach ($archive['entries'] as $entry) {
        if ($entry['status'] === 'ok' || $entry['status'] === 'repaired') {
            $intact[] = $entry;
        }
    }
    $salvageParameters = $archive['error'] !== null ? $parameters : ['offsetBits' => $archive['offsetBits'],
        'lengthBits' => $archive['lengthBits'], 'maxCodeLength' => $parameters['maxCodeLength']];
    $salvaged = [];
    foreach ($intact as $entry) {
        $encoded = compress($entry['data'], $salvageParameters);
        $salvaged[] = ['name' => $entry['name'], 'data' => $entry['data'], 'method' => $encoded['method'],
            'payload' => $encoded['payload'], 'source' => $entry];
    }
    $salvageData = buildArchive($salvaged, $salvageParameters);
    $salvageVerification = parseArchive($salvageData);
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    writeLines('sizes.txt', $reports['sizes']);
    writeLines('analysis.txt', $reports['analysis']);
    writeLines('archive.hex', hexLines($archiveData));
    writeLines('listing.txt', listingLines($archive));
    writeLines('test_report.txt', testLines($archive, $salvaged, $salvageData, $salvageVerification));
    writeLines('extracted.txt', extractionLines($intact));
    writeLines('compare.txt', comparisonLines($intact, $files));
    writeLines('salvaged.hex', hexLines($salvageData));
}

main();
