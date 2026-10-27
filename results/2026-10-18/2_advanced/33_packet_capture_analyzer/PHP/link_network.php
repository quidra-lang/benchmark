<?php

class Malformed extends RuntimeException {}

function uint(array $bytes, int $offset, int $count = 2): int
{
    $value = 0;
    for ($index = $offset; $index < $offset + $count; $index++) {
        $value = $value * 256 + $bytes[$index];
    }
    return $value;
}

function integerBytes(int $value, int $count): array
{
    $bytes = array_fill(0, $count, 0);
    for ($index = $count - 1; $index >= 0; $index--) {
        $bytes[$index] = $value % 256;
        $value = intdiv($value, 256);
    }
    return $bytes;
}

function checksum(array $bytes): string
{
    $total = 0;
    for ($index = 0; $index < count($bytes); $index += 2) {
        $total += $bytes[$index] * 256 + ($bytes[$index + 1] ?? 0);
    }
    while ($total > 65535) {
        $total = $total % 65536 + intdiv($total, 65536);
    }
    return $total === 65535 ? 'good' : 'bad';
}

function mac(int $value): string
{
    return implode(':', array_map(fn($byte) => sprintf('%02x', $byte), integerBytes($value, 6)));
}

function ipv4(int $value): string
{
    return implode('.', integerBytes($value, 4));
}

function ethernet(array $bytes): object
{
    if (count($bytes) < 14) {
        throw new Malformed('eth: truncated');
    }
    return (object) ['fields' => ['eth.dst' => [uint($bytes, 0, 6)], 'eth.src' => [uint($bytes, 6, 6)],
        'eth.type' => [uint($bytes, 12)]], 'payload' => array_slice($bytes, 14)];
}

function arp(array $bytes): object
{
    if (count($bytes) < 28) {
        throw new Malformed('arp: truncated');
    }
    if (uint($bytes, 0) !== 1 || uint($bytes, 2) !== 2048 || $bytes[4] !== 6 || $bytes[5] !== 4) {
        throw new Malformed('arp: unsupported format');
    }
    return (object) ['fields' => ['arp.opcode' => [uint($bytes, 6)], 'arp.src.hw' => [uint($bytes, 8, 6)],
        'arp.src.ip' => [uint($bytes, 14, 4)], 'arp.dst.hw' => [uint($bytes, 18, 6)], 'arp.dst.ip' => [uint($bytes, 24, 4)]], 'payload' => []];
}

function ip(array $bytes): object
{
    if (count($bytes) < 20) {
        throw new Malformed('ip: truncated header');
    }
    $version = intdiv($bytes[0], 16);
    if ($version !== 4) {
        throw new Malformed('ip: bad version ' . $version);
    }
    $header = ($bytes[0] % 16) * 4;
    if ($header < 20) {
        throw new Malformed('ip: bad header length ' . $header);
    }
    if (count($bytes) < $header) {
        throw new Malformed('ip: truncated header');
    }
    $length = uint($bytes, 2);
    if ($length < $header) {
        throw new Malformed('ip: bad total length ' . $length);
    }
    if ($length > count($bytes)) {
        throw new Malformed('ip: truncated (total length ' . $length . ', available ' . count($bytes) . ')');
    }
    $flags = uint($bytes, 6);
    $more = intdiv($flags, 8192) % 2;
    $offset = ($flags % 8192) * 8;
    $fields = ['ip.hdr_len' => [$header], 'ip.tos' => [$bytes[1]], 'ip.len' => [$length], 'ip.id' => [uint($bytes, 4)],
        'ip.flags.df' => [intdiv($flags, 16384) % 2], 'ip.flags.mf' => [$more], 'ip.frag_offset' => [$offset],
        'ip.ttl' => [$bytes[8]], 'ip.proto' => [$bytes[9]], 'ip.checksum' => [uint($bytes, 10)],
        'ip.checksum.status' => [checksum(array_slice($bytes, 0, $header))], 'ip.src' => [uint($bytes, 12, 4)], 'ip.dst' => [uint($bytes, 16, 4)]];
    if ($more === 1 || $offset !== 0) {
        $fields['ip.fragment'] = [true];
    }
    return (object) ['fields' => $fields, 'payload' => array_slice($bytes, $header, $length - $header)];
}
