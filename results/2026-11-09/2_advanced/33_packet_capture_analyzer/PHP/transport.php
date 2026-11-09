<?php

require_once __DIR__ . '/link_network.php';

function pseudoHeader(int $source, int $destination, int $protocol, int $length): array
{
    return array_merge(integerBytes($source, 4), integerBytes($destination, 4), [0, $protocol], integerBytes($length, 2));
}

function icmp(array $bytes): object
{
    if (count($bytes) < 8) {
        throw new Malformed('icmp: truncated');
    }
    $fields = ['icmp.type' => [$bytes[0]], 'icmp.code' => [$bytes[1]], 'icmp.checksum' => [uint($bytes, 2)],
        'icmp.checksum.status' => [checksum($bytes)]];
    if ($bytes[0] === 0 || $bytes[0] === 8) {
        $fields['icmp.id'] = [uint($bytes, 4)];
        $fields['icmp.seq'] = [uint($bytes, 6)];
    }
    return (object) ['fields' => $fields, 'payload' => array_slice($bytes, 8)];
}

function udp(array $bytes, int $source, int $destination): object
{
    if (count($bytes) < 8) {
        throw new Malformed('udp: truncated');
    }
    $length = uint($bytes, 4);
    if ($length < 8 || $length > count($bytes)) {
        throw new Malformed('udp: bad length ' . $length);
    }
    $stored = uint($bytes, 6);
    $status = $stored === 0 ? 'none' : checksum(array_merge(pseudoHeader($source, $destination, 17, $length), array_slice($bytes, 0, $length)));
    return (object) ['fields' => ['udp.srcport' => [uint($bytes, 0)], 'udp.dstport' => [uint($bytes, 2)], 'udp.length' => [$length],
        'udp.checksum' => [$stored], 'udp.checksum.status' => [$status]], 'payload' => array_slice($bytes, 8, $length - 8)];
}

function tcpOptions(array $bytes, array &$fields): void
{
    $allowed = [2 => [4], 3 => [3], 4 => [2], 5 => [10, 18, 26, 34], 8 => [10]];
    $recorded = [];
    $index = 0;
    while ($index < count($bytes)) {
        $kind = $bytes[$index];
        if ($kind === 0) {
            $recorded[] = 'EOL';
            break;
        }
        if ($kind === 1) {
            $recorded[] = 'NOP';
            $index++;
            continue;
        }
        $length = $bytes[$index + 1] ?? 0;
        if ($length < 2 || $index + $length > count($bytes) || (isset($allowed[$kind]) && !in_array($length, $allowed[$kind], true))) {
            $fields['tcp.options.malformed'] = [true];
            break;
        }
        $body = array_slice($bytes, $index + 2, $length - 2);
        if ($kind === 2) {
            $value = uint($body, 0);
            $text = 'MSS ' . $value;
            $fields['tcp.options.mss'] = [$value];
        } elseif ($kind === 3) {
            $text = 'WS ' . $body[0];
            $fields['tcp.options.wscale'] = [$body[0]];
        } elseif ($kind === 4) {
            $text = 'SACK_PERM';
        } elseif ($kind === 5) {
            $text = 'SACK';
            for ($position = 0; $position < count($body); $position += 8) {
                $text .= ' ' . uint($body, $position, 4) . '-' . uint($body, $position + 4, 4);
            }
        } elseif ($kind === 8) {
            $text = 'TS ' . uint($body, 0, 4) . ' ' . uint($body, 4, 4);
        } else {
            $text = 'kind ' . $kind . ' len ' . $length;
        }
        $recorded[] = $text;
        $index += $length;
    }
    if ($recorded) {
        $fields['tcp.option'] = $recorded;
    }
}

function tcp(array $bytes, int $source, int $destination): object
{
    if (count($bytes) < 20) {
        throw new Malformed('tcp: truncated header');
    }
    $header = intdiv($bytes[12], 16) * 4;
    if ($header < 20) {
        throw new Malformed('tcp: bad header length ' . $header);
    }
    if ($header > count($bytes)) {
        throw new Malformed('tcp: truncated header');
    }
    $flags = $bytes[13];
    $fields = ['tcp.srcport' => [uint($bytes, 0)], 'tcp.dstport' => [uint($bytes, 2)], 'tcp.seq_raw' => [uint($bytes, 4, 4)],
        'tcp.hdr_len' => [$header], 'tcp.flags' => [$flags], 'tcp.window' => [uint($bytes, 14)], 'tcp.checksum' => [uint($bytes, 16)],
        'tcp.checksum.status' => [checksum(array_merge(pseudoHeader($source, $destination, 6, count($bytes)), $bytes))],
        'tcp.urgent' => [uint($bytes, 18)], 'tcp.len' => [count($bytes) - $header]];
    foreach (['fin', 'syn', 'rst', 'psh', 'ack', 'urg'] as $index => $name) {
        $fields['tcp.flags.' . $name] = [intdiv($flags, 2 ** $index) % 2];
    }
    if ($fields['tcp.flags.ack'][0] === 1) {
        $fields['tcp.ack_raw'] = [uint($bytes, 8, 4)];
    }
    tcpOptions(array_slice($bytes, 20, $header - 20), $fields);
    return (object) ['fields' => $fields, 'payload' => array_slice($bytes, $header)];
}
