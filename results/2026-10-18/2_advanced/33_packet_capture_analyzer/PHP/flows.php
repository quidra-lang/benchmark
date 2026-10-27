<?php

const MARKS = ['retransmission', 'out_of_order', 'lost_segment', 'duplicate_ack'];
const MODULUS = 4294967296;

function getField(object $packet, string $field): mixed
{
    return $packet->fields[$field][0] ?? null;
}

function endpointKey(array $endpoint): string
{
    return $endpoint[0] . ':' . $endpoint[1];
}

function pairKey(array $first, array $second): string
{
    $a = endpointKey($first);
    $b = endpointKey($second);
    return strcmp($a, $b) <= 0 ? $a . '|' . $b : $b . '|' . $a;
}

function newSide(): object
{
    return (object) ['isn' => null, 'mss' => null, 'ws' => null, 'base' => null, 'expected' => null, 'advanced' => null,
        'intervals' => [], 'previousAck' => null, 'packets' => 0, 'payload' => 0, 'counts' => array_fill_keys(MARKS, 0)];
}

function recordSyn(object $stream, string $side, object $packet): void
{
    $target = $stream->sides[$side];
    $target->isn = getField($packet, 'tcp.seq_raw');
    $target->mss = getField($packet, 'tcp.options.mss');
    $target->ws = getField($packet, 'tcp.options.wscale');
    $stream->handshake[$side === 'client' ? 'syn' : 'syn_ack'] = $packet->number;
}

function relativeSequence(int $value, int $base): int
{
    $difference = $value - $base;
    return ($difference < 0 ? $difference + MODULUS : $difference) % MODULUS;
}

function trackTcp(array $packets): array
{
    $streams = [];
    $latest = [];
    foreach ($packets as $packet) {
        if (getField($packet, 'tcp.srcport') === null) {
            continue;
        }
        $source = [getField($packet, 'ip.src'), getField($packet, 'tcp.srcport')];
        $destination = [getField($packet, 'ip.dst'), getField($packet, 'tcp.dstport')];
        $syn = getField($packet, 'tcp.flags.syn') === 1;
        $ackSet = getField($packet, 'tcp.flags.ack') === 1;
        $fin = getField($packet, 'tcp.flags.fin') === 1;
        $rst = getField($packet, 'tcp.flags.rst') === 1;
        $seq = getField($packet, 'tcp.seq_raw');
        $ack = getField($packet, 'tcp.ack_raw');
        $key = pairKey($source, $destination);
        $stream = $latest[$key] ?? null;
        if ($stream === null || (in_array($stream->state, ['CLOSED', 'RESET'], true) && $syn && !$ackSet)) {
            $state = $syn ? ($ackSet ? 'SYN_RECEIVED' : 'SYN_SENT') : 'ESTABLISHED';
            $stream = (object) ['number' => count($streams), 'client' => $syn && $ackSet ? $destination : $source,
                'server' => $syn && $ackSet ? $source : $destination, 'state' => $state, 'history' => [[$state, $packet->number]],
                'start' => $packet->time, 'end' => $packet->time, 'packets' => 0, 'bytes' => 0,
                'handshake' => ['syn' => null, 'syn_ack' => null, 'ack' => null], 'events' => [], 'firstCloser' => null, 'f2' => null,
                'sides' => ['client' => newSide(), 'server' => newSide()]];
            if ($syn) {
                recordSyn($stream, $ackSet ? 'server' : 'client', $packet);
            }
            $streams[] = $stream;
            $latest[$key] = $stream;
        }
        $packet->fields['tcp.stream'] = [$stream->number];
        $sideName = endpointKey($source) === endpointKey($stream->client) ? 'client' : 'server';
        $side = $stream->sides[$sideName];
        $other = $stream->sides[$sideName === 'client' ? 'server' : 'client'];
        if ($side->base === null) {
            $side->base = $seq;
        }
        if ($ackSet && $other->base === null) {
            $other->base = $ack;
        }
        $r = relativeSequence($seq, $side->base);
        $packet->fields['tcp.seq'] = [$r];
        if ($ackSet) {
            $packet->fields['tcp.ack'] = [relativeSequence($ack, $other->base)];
        }
        $length = getField($packet, 'tcp.len');
        $n = $length + (int) $syn + (int) $fin;
        $window = getField($packet, 'tcp.window');
        $mark = null;
        if ($n >= 1) {
            $interval = $r . ':' . $n;
            if ($side->expected !== null && $r > $side->expected) {
                $mark = 'lost_segment';
            }
            if ($side->expected !== null && $r < $side->expected) {
                $mark = isset($side->intervals[$interval]) || $packet->time - $side->advanced >= 3000 ? 'retransmission' : 'out_of_order';
            }
            $side->intervals[$interval] = true;
            if ($side->expected === null || $r + $n > $side->expected) {
                $side->expected = $r + $n;
                $side->advanced = $packet->time;
            }
        } elseif ($ackSet && !$rst && $side->previousAck !== null) {
            if ($ack === $side->previousAck->ack && $window === $side->previousAck->window) {
                $mark = 'duplicate_ack';
                $side->previousAck->count++;
                $packet->duplicateAck = (object) ['original' => $side->previousAck->original, 'count' => $side->previousAck->count];
            }
        }
        if ($ackSet && $mark !== 'duplicate_ack') {
            $side->previousAck = (object) ['ack' => $ack, 'window' => $window, 'original' => $packet->number, 'count' => 0];
        }
        $packet->mark = $mark;
        if ($mark !== null) {
            $packet->fields['tcp.analysis.' . $mark] = [true];
            $side->counts[$mark]++;
            $stream->events[] = [$packet->number, $sideName, $mark, $r, $n];
        }
        $packet->fields['tcp.window.calc'] = [$side->ws !== null && $other->ws !== null && !$syn ? $window * (2 ** $side->ws) : $window];
        $next = $stream->state;
        if ($rst) {
            if ($stream->state !== 'CLOSED' && $stream->state !== 'RESET') {
                $next = 'RESET';
            }
        } elseif ($stream->state === 'SYN_SENT' && $sideName === 'server' && $syn && $ackSet && $ack === ($stream->sides['client']->isn + 1) % MODULUS) {
            $next = 'SYN_RECEIVED';
            recordSyn($stream, 'server', $packet);
        } elseif ($stream->state === 'SYN_RECEIVED' && $sideName === 'client' && $ackSet && !$syn && $ack === ($stream->sides['server']->isn + 1) % MODULUS) {
            $next = 'ESTABLISHED';
            $stream->handshake['ack'] = $packet->number;
        } elseif ($stream->state === 'ESTABLISHED' && $fin) {
            $next = 'FIN_WAIT';
            $stream->firstCloser = $sideName;
        } elseif ($stream->state === 'FIN_WAIT' && $fin && $sideName !== $stream->firstCloser) {
            $next = 'CLOSING';
            $stream->f2 = ($seq + $length + 1) % MODULUS;
        } elseif ($stream->state === 'CLOSING' && $sideName === $stream->firstCloser && $ackSet && $ack === $stream->f2) {
            $next = 'CLOSED';
        }
        if ($next !== $stream->state) {
            $stream->state = $next;
            $stream->history[] = [$next, $packet->number];
        }
        $side->packets++;
        $side->payload += $length;
        $stream->packets++;
        $stream->bytes += $packet->length;
        $stream->end = $packet->time;
    }
    return $streams;
}

function addConversation(array &$conversations, string $kind, string $key, mixed $source, mixed $destination, object $packet): void
{
    $id = $kind . '|' . $key;
    if (!isset($conversations[$id])) {
        $conversations[$id] = (object) ['kind' => $kind, 'a' => $source, 'b' => $destination, 'first' => $packet->number,
            'start' => $packet->time, 'end' => $packet->time, 'packets' => 0, 'bytes' => 0,
            'abPackets' => 0, 'abBytes' => 0, 'baPackets' => 0, 'baBytes' => 0];
    }
    $item = $conversations[$id];
    $forward = $kind === 'ipv4' ? $source === $item->a : endpointKey($source) === endpointKey($item->a);
    $packetField = $forward ? 'abPackets' : 'baPackets';
    $byteField = $forward ? 'abBytes' : 'baBytes';
    $item->$packetField++;
    $item->$byteField += $packet->length;
    $item->packets++;
    $item->bytes += $packet->length;
    $item->end = $packet->time;
}

function addEndpoint(array &$endpoints, int $address, string $direction, int $length): void
{
    if (!isset($endpoints[$address])) {
        $endpoints[$address] = (object) ['address' => $address, 'packets' => 0, 'bytes' => 0,
            'txPackets' => 0, 'txBytes' => 0, 'rxPackets' => 0, 'rxBytes' => 0];
    }
    $item = $endpoints[$address];
    $packetField = $direction . 'Packets';
    $byteField = $direction . 'Bytes';
    $item->$packetField++;
    $item->$byteField += $length;
    $item->packets++;
    $item->bytes += $length;
}

function aggregate(array $packets): object
{
    $conversations = [];
    $endpoints = [];
    foreach ($packets as $packet) {
        $source = getField($packet, 'ip.src');
        if ($source === null) {
            continue;
        }
        $destination = getField($packet, 'ip.dst');
        addConversation($conversations, 'ipv4', min($source, $destination) . ':' . max($source, $destination), $source, $destination, $packet);
        addEndpoint($endpoints, $source, 'tx', $packet->length);
        addEndpoint($endpoints, $destination, 'rx', $packet->length);
        if (getField($packet, 'tcp.stream') !== null) {
            addConversation($conversations, 'tcp', (string) getField($packet, 'tcp.stream'), [$source, getField($packet, 'tcp.srcport')],
                [$destination, getField($packet, 'tcp.dstport')], $packet);
        }
        if (getField($packet, 'udp.srcport') !== null) {
            $first = [$source, getField($packet, 'udp.srcport')];
            $second = [$destination, getField($packet, 'udp.dstport')];
            addConversation($conversations, 'udp', pairKey($first, $second), $first, $second, $packet);
        }
    }
    $conversations = array_values($conversations);
    $endpoints = array_values($endpoints);
    $kinds = ['ipv4' => 0, 'tcp' => 1, 'udp' => 2];
    usort($conversations, fn($a, $b) => ($b->bytes <=> $a->bytes) ?: ($b->packets <=> $a->packets)
        ?: ($kinds[$a->kind] <=> $kinds[$b->kind]) ?: ($a->first <=> $b->first));
    usort($endpoints, fn($a, $b) => ($b->bytes <=> $a->bytes) ?: ($b->packets <=> $a->packets) ?: ($a->address <=> $b->address));
    return (object) ['conversations' => $conversations, 'endpoints' => $endpoints];
}
