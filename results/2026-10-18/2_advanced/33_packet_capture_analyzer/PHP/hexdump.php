<?php

function readCapture(string $filename): array
{
    $packets = [];
    $packet = null;
    $finish = function () use (&$packet, &$packets): void {
        if ($packet === null) {
            return;
        }
        if ($packet->reason === null && count($packet->bytes) !== $packet->length) {
            $packet->reason = 'dump: length mismatch (header ' . $packet->length . ', data ' . count($packet->bytes) . ')';
        }
        $packets[] = $packet;
    };
    foreach (file($filename, FILE_IGNORE_NEW_LINES) as $index => $line) {
        if (str_starts_with($line, 'PACKET ')) {
            $finish();
            [, $number, $time, $length] = explode(' ', $line);
            $packet = (object) ['number' => (int) $number, 'time' => (int) $time, 'length' => (int) $length,
                'bytes' => [], 'reason' => null];
        } elseif ($line !== '' && $packet->reason === null) {
            if (!preg_match('/\A([0-9a-f]{4})  ([0-9a-f]{2}(?: [0-9a-f]{2}){0,15})\z/', $line, $match)) {
                $packet->reason = 'dump: bad line ' . ($index + 1);
            } elseif (hexdec($match[1]) !== count($packet->bytes)) {
                $packet->reason = 'dump: offset mismatch at line ' . ($index + 1);
            } else {
                foreach (explode(' ', $match[2]) as $byte) {
                    $packet->bytes[] = hexdec($byte);
                }
            }
        }
    }
    $finish();
    return $packets;
}

function dumpLines(array $bytes): array
{
    $lines = [];
    for ($offset = 0; $offset < count($bytes); $offset += 16) {
        $piece = array_slice($bytes, $offset, 16);
        $hex = implode(' ', array_map(fn($byte) => sprintf('%02x', $byte), $piece));
        $characters = '';
        foreach ($piece as $byte) {
            $characters .= $byte >= 32 && $byte <= 126 ? chr($byte) : '.';
        }
        $lines[] = sprintf('%04x', $offset) . '  ' . str_pad($hex, 47) . '  |' . $characters . '|';
    }
    return $lines;
}
