<?php

require_once __DIR__ . '/hexdump.php';
require_once __DIR__ . '/link_network.php';
require_once __DIR__ . '/transport.php';
require_once __DIR__ . '/dns_app.php';
require_once __DIR__ . '/flows.php';

const FIELD_ORDER = [
    ['frame.number', 'integer'], ['frame.time', 'integer'], ['frame.len', 'integer'],
    ['frame.protocols', 'string'], ['frame.malformed', 'string'], ['frame.bad_checksum', 'presence'],
    ['eth.dst', 'MAC'], ['eth.src', 'MAC'], ['eth.type', 'hex4'],
    ['arp.opcode', 'integer'], ['arp.src.hw', 'MAC'], ['arp.src.ip', 'IPv4'], ['arp.dst.hw', 'MAC'], ['arp.dst.ip', 'IPv4'],
    ['ip.hdr_len', 'integer'], ['ip.tos', 'hex2'], ['ip.len', 'integer'], ['ip.id', 'hex4'],
    ['ip.flags.df', 'integer'], ['ip.flags.mf', 'integer'], ['ip.frag_offset', 'integer'],
    ['ip.ttl', 'integer'], ['ip.proto', 'integer'], ['ip.checksum', 'hex4'], ['ip.checksum.status', 'string'],
    ['ip.src', 'IPv4'], ['ip.dst', 'IPv4'], ['ip.fragment', 'presence'],
    ['icmp.type', 'integer'], ['icmp.code', 'integer'], ['icmp.checksum', 'hex4'],
    ['icmp.checksum.status', 'string'], ['icmp.id', 'integer'], ['icmp.seq', 'integer'],
    ['udp.srcport', 'integer'], ['udp.dstport', 'integer'], ['udp.length', 'integer'],
    ['udp.checksum', 'hex4'], ['udp.checksum.status', 'string'],
    ['tcp.srcport', 'integer'], ['tcp.dstport', 'integer'], ['tcp.stream', 'integer'],
    ['tcp.seq', 'integer'], ['tcp.seq_raw', 'integer'], ['tcp.ack', 'integer'], ['tcp.ack_raw', 'integer'],
    ['tcp.hdr_len', 'integer'], ['tcp.flags', 'hex2'], ['tcp.flags.fin', 'integer'], ['tcp.flags.syn', 'integer'],
    ['tcp.flags.rst', 'integer'], ['tcp.flags.psh', 'integer'], ['tcp.flags.ack', 'integer'], ['tcp.flags.urg', 'integer'],
    ['tcp.window', 'integer'], ['tcp.window.calc', 'integer'], ['tcp.checksum', 'hex4'],
    ['tcp.checksum.status', 'string'], ['tcp.urgent', 'integer'], ['tcp.option', 'string'],
    ['tcp.options.mss', 'integer'], ['tcp.options.wscale', 'integer'], ['tcp.options.malformed', 'presence'],
    ['tcp.len', 'integer'], ['tcp.analysis.retransmission', 'presence'], ['tcp.analysis.out_of_order', 'presence'],
    ['tcp.analysis.lost_segment', 'presence'], ['tcp.analysis.duplicate_ack', 'presence'],
    ['dns.id', 'hex4'], ['dns.flags', 'hex4'], ['dns.flags.response', 'integer'],
    ['dns.flags.opcode', 'integer'], ['dns.flags.rcode', 'integer'], ['dns.count.queries', 'integer'],
    ['dns.count.answers', 'integer'], ['dns.count.auth_rr', 'integer'], ['dns.count.add_rr', 'integer'],
    ['dns.qry.name', 'string'], ['dns.qry.type', 'integer'], ['dns.answer', 'string'],
    ['dns.authority', 'string'], ['dns.additional', 'string'], ['dns.a', 'IPv4'], ['data.len', 'integer']
];
const ALIASES = ['eth.addr' => ['eth.dst', 'eth.src'], 'ip.addr' => ['ip.src', 'ip.dst'],
    'udp.port' => ['udp.srcport', 'udp.dstport'], 'tcp.port' => ['tcp.srcport', 'tcp.dstport']];
const PROTOCOLS = ['eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns', 'data'];
const CHECKSUMS = [['ip', 'IPv4'], ['icmp', 'ICMP'], ['udp', 'UDP'], ['tcp', 'TCP']];
const COMPARISONS = ['==', '!=', '<', '>', '<=', '>='];

function fieldTypes(): array
{
    static $types = null;
    if ($types === null) {
        $types = [];
        foreach (FIELD_ORDER as [$name, $type]) {
            $types[$name] = $type;
        }
        foreach (ALIASES as $name => $members) {
            $types[$name] = $types[$members[0]];
        }
        foreach (PROTOCOLS as $name) {
            $types[$name] = 'presence';
        }
    }
    return $types;
}

function seconds(int $time): string
{
    return intdiv($time, 1000000) . '.' . sprintf('%06d', $time % 1000000);
}

function notation(string $type, mixed $value): string
{
    if ($type === 'hex2' || $type === 'hex4') {
        return '0x' . str_pad(dechex($value), $type === 'hex2' ? 2 : 4, '0', STR_PAD_LEFT);
    }
    if ($type === 'MAC') {
        return mac($value);
    }
    if ($type === 'IPv4') {
        return ipv4($value);
    }
    return (string) $value;
}

function dissectPacket(object $packet, int $firstTime): void
{
    $packet->fields = [];
    $packet->layers = [];
    $packet->remaining = [];
    $packet->dnsAnswers = [];
    $payload = $packet->bytes;
    $layer = $packet->reason === null ? 'eth' : null;
    while ($layer !== null) {
        $packet->layers[] = $layer;
        try {
            if ($layer === 'eth') {
                $result = ethernet($payload);
            } elseif ($layer === 'arp') {
                $result = arp($payload);
            } elseif ($layer === 'ip') {
                $result = ip($payload);
            } elseif ($layer === 'icmp') {
                $result = icmp($payload);
            } elseif ($layer === 'udp') {
                $result = udp($payload, getField($packet, 'ip.src'), getField($packet, 'ip.dst'));
            } elseif ($layer === 'tcp') {
                $result = tcp($payload, getField($packet, 'ip.src'), getField($packet, 'ip.dst'));
            } else {
                $result = (new DnsReader($payload))->dissect();
            }
        } catch (Malformed $error) {
            $packet->reason = $error->getMessage();
            break;
        }
        $packet->fields = array_merge($packet->fields, $result->fields);
        $payload = $result->payload;
        if ($layer === 'eth') {
            $type = getField($packet, 'eth.type');
            $layer = $type === 2054 ? 'arp' : ($type === 2048 ? 'ip' : null);
        } elseif ($layer === 'ip') {
            $protocol = getField($packet, 'ip.proto');
            $layer = getField($packet, 'ip.fragment') !== null ? null
                : ($protocol === 1 ? 'icmp' : ($protocol === 17 ? 'udp' : ($protocol === 6 ? 'tcp' : null)));
        } elseif ($layer === 'udp') {
            $layer = getField($packet, 'udp.srcport') === 53 || getField($packet, 'udp.dstport') === 53 ? 'dns' : null;
        } else {
            if ($layer === 'dns') {
                $packet->dnsAnswers = $result->answers;
            }
            $layer = null;
        }
    }
    if ($packet->reason === null && count($payload) > 0) {
        $packet->layers[] = 'data';
        $packet->fields['data.len'] = [count($payload)];
        $packet->remaining = $payload;
    }
    $packet->fields['frame.number'] = [$packet->number];
    $packet->fields['frame.time'] = [$packet->time - $firstTime];
    $packet->fields['frame.len'] = [$packet->length];
    if ($packet->layers) {
        $packet->fields['frame.protocols'] = [implode(':', $packet->layers)];
    }
    if ($packet->reason !== null) {
        $packet->fields['frame.malformed'] = [$packet->reason];
    }
    foreach (CHECKSUMS as [$name]) {
        if (getField($packet, $name . '.checksum.status') === 'bad') {
            $packet->fields['frame.bad_checksum'] = [true];
            break;
        }
    }
}

function tcpInfo(object $packet): string
{
    $prefix = match ($packet->mark) {
        'retransmission' => '[TCP Retransmission] ',
        'out_of_order' => '[TCP Out-Of-Order] ',
        'lost_segment' => '[TCP Previous segment not captured] ',
        'duplicate_ack' => '[TCP Dup ACK ' . $packet->duplicateAck->original . '#' . $packet->duplicateAck->count . '] ',
        default => ''
    };
    $flags = [];
    foreach (['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECE', 'CWR'] as $index => $name) {
        if (intdiv(getField($packet, 'tcp.flags'), 2 ** $index) % 2 === 1) {
            $flags[] = $name;
        }
    }
    $text = $prefix . getField($packet, 'tcp.srcport') . ' -> ' . getField($packet, 'tcp.dstport') . ' ['
        . ($flags ? implode(', ', $flags) : '<None>') . '] Seq=' . getField($packet, 'tcp.seq');
    if (getField($packet, 'tcp.flags.ack') === 1) {
        $text .= ' Ack=' . getField($packet, 'tcp.ack');
    }
    $text .= ' Win=' . getField($packet, 'tcp.window.calc') . ' Len=' . getField($packet, 'tcp.len');
    foreach ($packet->fields['tcp.option'] ?? [] as $option) {
        $parts = explode(' ', $option);
        if ($parts[0] === 'MSS') {
            $text .= ' MSS=' . $parts[1];
        } elseif ($parts[0] === 'WS') {
            $text .= ' WS=' . (2 ** (int) $parts[1]);
        } elseif ($parts[0] === 'SACK_PERM') {
            $text .= ' SACK_PERM';
        } elseif ($parts[0] === 'TS') {
            $text .= ' TSval=' . $parts[1] . ' TSecr=' . $parts[2];
        }
    }
    return $text;
}

function dnsInfo(object $packet): string
{
    $text = getField($packet, 'dns.flags.response') === 1 ? 'Response' : 'Query';
    $text .= ' ' . notation('hex4', getField($packet, 'dns.id'));
    $rcode = getField($packet, 'dns.flags.rcode');
    if ($rcode !== 0) {
        $text .= ' ' . rcodeName($rcode);
    }
    $names = $packet->fields['dns.qry.name'] ?? [];
    $types = $packet->fields['dns.qry.type'] ?? [];
    foreach ($names as $index => $name) {
        $text .= ' ' . typeName($types[$index]) . ' ' . $name;
    }
    foreach ($packet->dnsAnswers as $answer) {
        $text .= ' ' . typeName($answer->type) . ' ' . $answer->text;
    }
    return $text;
}

function summaryLine(object $packet): string
{
    $types = fieldTypes();
    $value = fn($name) => notation($types[$name], getField($packet, $name));
    $source = '-';
    $destination = '-';
    if (getField($packet, 'ip.src') !== null) {
        $source = $value('ip.src');
        $destination = $value('ip.dst');
    } elseif (getField($packet, 'eth.src') !== null) {
        $source = $value('eth.src');
        $destination = $value('eth.dst');
    }
    $layers = array_values(array_filter($packet->layers, fn($name) => $name !== 'data'));
    $lastLayer = $layers ? $layers[count($layers) - 1] : null;
    $protocol = ['eth' => 'ETH', 'arp' => 'ARP', 'ip' => 'IPv4', 'icmp' => 'ICMP', 'udp' => 'UDP', 'tcp' => 'TCP', 'dns' => 'DNS'][$lastLayer] ?? 'DUMP';
    $info = $packet->reason;
    if ($info === null) {
        if ($lastLayer === 'eth') {
            $info = 'EtherType ' . $value('eth.type');
        } elseif ($lastLayer === 'arp') {
            $opcode = getField($packet, 'arp.opcode');
            $info = $opcode === 1 ? 'Who has ' . $value('arp.dst.ip') . '? Tell ' . $value('arp.src.ip')
                : ($opcode === 2 ? $value('arp.src.ip') . ' is at ' . $value('arp.src.hw') : 'Opcode ' . $opcode);
        } elseif ($lastLayer === 'ip') {
            $info = getField($packet, 'ip.fragment') === null ? 'Protocol ' . $value('ip.proto')
                : 'Fragment id=' . $value('ip.id') . ' off=' . $value('ip.frag_offset') . (getField($packet, 'ip.flags.mf') === 1 ? ' MF' : '');
        } elseif ($lastLayer === 'icmp') {
            $type = getField($packet, 'icmp.type');
            $info = $type === 0 || $type === 8 ? 'Echo ' . ($type === 8 ? 'request' : 'reply') . ' id=' . $value('icmp.id') . ' seq=' . $value('icmp.seq')
                : 'Type ' . $type . ' code ' . $value('icmp.code');
        } elseif ($lastLayer === 'udp') {
            $info = $value('udp.srcport') . ' -> ' . $value('udp.dstport') . ' Len=' . (getField($packet, 'udp.length') - 8);
        } elseif ($lastLayer === 'tcp') {
            $info = tcpInfo($packet);
        } elseif ($lastLayer === 'dns') {
            $info = dnsInfo($packet);
        }
    }
    if (getField($packet, 'tcp.options.malformed') !== null) {
        $info .= ' [bad TCP options]';
    }
    foreach (CHECKSUMS as [$name, $label]) {
        if (getField($packet, $name . '.checksum.status') === 'bad') {
            $info .= ' [bad ' . $label . ' checksum]';
        }
    }
    return $packet->number . ' ' . seconds(getField($packet, 'frame.time')) . ' ' . $source . ' -> ' . $destination . ' ' . $protocol . ' ' . $packet->length . ' ' . $info;
}

class FilterError extends RuntimeException {}

function tokenizeFilter(string $expression): array
{
    $tokens = [];
    $keywords = ['and' => '&&', 'or' => '||', 'not' => '!'];
    $pairs = ['==', '!=', '<=', '>=', '&&', '||'];
    $index = 0;
    $length = strlen($expression);
    while ($index < $length) {
        $character = $expression[$index];
        if ($character === ' ') {
            $index++;
            continue;
        }
        $column = $index + 1;
        $pair = substr($expression, $index, 2);
        if (in_array($pair, $pairs, true)) {
            $tokens[] = ['kind' => $pair, 'text' => $pair, 'column' => $column];
            $index += 2;
        } elseif (str_contains('()!<>', $character)) {
            $tokens[] = ['kind' => $character, 'text' => $character, 'column' => $column];
            $index++;
        } elseif ($character === '"') {
            $end = strpos($expression, '"', $index + 1);
            if ($end === false) {
                throw new FilterError('unterminated string at column ' . $column);
            }
            $tokens[] = ['kind' => 'string', 'text' => substr($expression, $index, $end - $index + 1), 'column' => $column];
            $index = $end + 1;
        } elseif (preg_match('/[A-Za-z0-9._:]/', $character)) {
            $start = $index;
            while ($index < $length && preg_match('/[A-Za-z0-9._:]/', $expression[$index])) {
                $index++;
            }
            $text = substr($expression, $start, $index - $start);
            $tokens[] = ['kind' => $keywords[$text] ?? 'word', 'text' => $text, 'column' => $column];
        } else {
            throw new FilterError("invalid character '" . $character . "' at column " . $column);
        }
    }
    return $tokens;
}

function convertValue(array $token, string $type, string $field): mixed
{
    $text = $token['text'];
    if ($type === 'string' && $token['kind'] === 'string') {
        return substr($text, 1, -1);
    }
    if ($token['kind'] === 'word') {
        if (in_array($type, ['integer', 'hex2', 'hex4'], true)) {
            if (preg_match('/\A[0-9]{1,15}\z/', $text)) {
                return (int) $text;
            }
            if (preg_match('/\A0x[0-9a-fA-F]{1,12}\z/', $text)) {
                return hexdec(substr($text, 2));
            }
        }
        if ($type === 'IPv4') {
            $parts = explode('.', $text);
            if (count($parts) === 4) {
                $value = 0;
                $valid = true;
                foreach ($parts as $part) {
                    if (!preg_match('/\A[0-9]{1,3}\z/', $part) || (int) $part > 255) {
                        $valid = false;
                        break;
                    }
                    $value = $value * 256 + (int) $part;
                }
                if ($valid) {
                    return $value;
                }
            }
        }
        if ($type === 'MAC') {
            $parts = explode(':', $text);
            if (count($parts) === 6) {
                $value = 0;
                $valid = true;
                foreach ($parts as $part) {
                    if (!preg_match('/\A[0-9a-fA-F]{2}\z/', $part)) {
                        $valid = false;
                        break;
                    }
                    $value = $value * 256 + hexdec($part);
                }
                if ($valid) {
                    return $value;
                }
            }
        }
    }
    throw new FilterError('invalid value ' . $text . ' for ' . $field);
}

class FilterParser
{
    private array $tokens;
    private int $index = 0;

    public function __construct(string $expression)
    {
        $this->tokens = tokenizeFilter($expression);
    }

    private function take(): array
    {
        if ($this->index === count($this->tokens)) {
            throw new FilterError('unexpected end of filter');
        }
        return $this->tokens[$this->index++];
    }

    private function unexpected(array $token): void
    {
        throw new FilterError("unexpected '" . $token['text'] . "' at column " . $token['column']);
    }

    private function expression(): object
    {
        $node = $this->product();
        while (($this->tokens[$this->index]['kind'] ?? null) === '||') {
            $this->index++;
            $node = (object) ['kind' => 'or', 'left' => $node, 'right' => $this->product()];
        }
        return $node;
    }

    private function product(): object
    {
        $node = $this->negation();
        while (($this->tokens[$this->index]['kind'] ?? null) === '&&') {
            $this->index++;
            $node = (object) ['kind' => 'and', 'left' => $node, 'right' => $this->negation()];
        }
        return $node;
    }

    private function negation(): object
    {
        if (($this->tokens[$this->index]['kind'] ?? null) === '!') {
            $this->index++;
            return (object) ['kind' => 'not', 'child' => $this->negation()];
        }
        $token = $this->take();
        if ($token['kind'] === '(') {
            $node = $this->expression();
            $close = $this->take();
            if ($close['kind'] !== ')') {
                $this->unexpected($close);
            }
            return $node;
        }
        if ($token['kind'] !== 'word') {
            $this->unexpected($token);
        }
        $field = $token['text'];
        $types = fieldTypes();
        if (!isset($types[$field])) {
            throw new FilterError('unknown field ' . $field);
        }
        $type = $types[$field];
        if (!in_array($this->tokens[$this->index]['kind'] ?? null, COMPARISONS, true)) {
            return (object) ['kind' => 'test', 'field' => $field, 'operator' => null];
        }
        $operator = $this->take()['kind'];
        if ($type === 'presence' || ($type === 'string' && $operator !== '==' && $operator !== '!=')) {
            throw new FilterError('operator ' . $operator . ' not allowed for ' . $field);
        }
        $literal = $this->take();
        if ($literal['kind'] !== 'word' && $literal['kind'] !== 'string') {
            $this->unexpected($literal);
        }
        return (object) ['kind' => 'test', 'field' => $field, 'operator' => $operator, 'value' => convertValue($literal, $type, $field)];
    }

    public function parse(): object
    {
        $result = $this->expression();
        if ($this->index < count($this->tokens)) {
            $this->unexpected($this->tokens[$this->index]);
        }
        return $result;
    }
}

function fieldValues(object $packet, string $field): array
{
    if (isset(ALIASES[$field])) {
        return array_merge($packet->fields[ALIASES[$field][0]] ?? [], $packet->fields[ALIASES[$field][1]] ?? []);
    }
    if (in_array($field, PROTOCOLS, true)) {
        return in_array($field, $packet->layers, true) ? [true] : [];
    }
    return $packet->fields[$field] ?? [];
}

function matchesFilter(object $node, object $packet): bool
{
    if ($node->kind === 'or') {
        return matchesFilter($node->left, $packet) || matchesFilter($node->right, $packet);
    }
    if ($node->kind === 'and') {
        return matchesFilter($node->left, $packet) && matchesFilter($node->right, $packet);
    }
    if ($node->kind === 'not') {
        return !matchesFilter($node->child, $packet);
    }
    $values = fieldValues($packet, $node->field);
    if ($node->operator === null) {
        return count($values) > 0;
    }
    if (!$values) {
        return false;
    }
    if ($node->operator === '!=') {
        foreach ($values as $value) {
            if ($value === $node->value) {
                return false;
            }
        }
        return true;
    }
    foreach ($values as $value) {
        $match = match ($node->operator) {
            '==' => $value === $node->value,
            '<' => $value < $node->value,
            '>' => $value > $node->value,
            '<=' => $value <= $node->value,
            '>=' => $value >= $node->value
        };
        if ($match) {
            return true;
        }
    }
    return false;
}

function readRequests(string $filename): object
{
    $filters = [];
    $details = [];
    foreach (file($filename, FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }
        if (str_starts_with($line, 'FILTER ')) {
            $filters[] = substr($line, 7);
        } else {
            $details[] = (int) substr($line, 7);
        }
    }
    return (object) ['filters' => $filters, 'details' => $details];
}

function summaryLines(array $packets, array $filters): array
{
    $lines = array_map(fn($packet) => $packet->summary, $packets);
    foreach ($filters as $filter) {
        $lines[] = '';
        $lines[] = 'filter ' . $filter;
        try {
            $expression = (new FilterParser($filter))->parse();
        } catch (FilterError $error) {
            $lines[] = 'error: ' . $error->getMessage();
            continue;
        }
        $count = 0;
        foreach ($packets as $packet) {
            if (matchesFilter($expression, $packet)) {
                $lines[] = $packet->summary;
                $count++;
            }
        }
        $lines[] = 'matched ' . $count . ' of ' . count($packets);
    }
    return $lines;
}

function detailLines(array $packets, array $requests): array
{
    $lines = [];
    foreach ($requests as $number) {
        if ($lines) {
            $lines[] = '';
        }
        if ($number < 1 || $number > count($packets)) {
            $lines[] = 'packet ' . $number . ' not found';
            continue;
        }
        $packet = $packets[$number - 1];
        $lines[] = 'packet ' . $packet->number;
        foreach (array_merge(['frame'], $packet->layers) as $layer) {
            $lines[] = $layer;
            foreach (FIELD_ORDER as [$name, $type]) {
                if (!str_starts_with($name, $layer . '.')) {
                    continue;
                }
                foreach ($packet->fields[$name] ?? [] as $value) {
                    $lines[] = $type === 'presence' ? '  ' . $name : '  ' . $name . ' = ' . notation($type, $value);
                }
            }
            if ($layer === 'data') {
                foreach (dumpLines($packet->remaining) as $line) {
                    $lines[] = '  ' . $line;
                }
            }
        }
    }
    return $lines;
}

function dnsTransactions(array $packets): object
{
    $pending = [];
    $transactions = [];
    $names = [];
    $rcodes = array_fill(0, 16, 0);
    $queries = 0;
    $responses = 0;
    foreach ($packets as $packet) {
        if (getField($packet, 'dns.id') === null) {
            continue;
        }
        if (getField($packet, 'dns.flags.response') === 0) {
            $queries++;
            $pending[] = $packet;
            foreach ($packet->fields['dns.qry.name'] ?? [] as $name) {
                $names[$name] = ($names[$name] ?? 0) + 1;
            }
        } else {
            $responses++;
            $rcodes[getField($packet, 'dns.flags.rcode')]++;
            foreach ($pending as $index => $query) {
                if (getField($query, 'dns.id') === getField($packet, 'dns.id')
                    && getField($query, 'ip.src') === getField($packet, 'ip.dst')
                    && getField($query, 'udp.srcport') === getField($packet, 'udp.dstport')
                    && getField($query, 'ip.dst') === getField($packet, 'ip.src')
                    && getField($query, 'udp.dstport') === getField($packet, 'udp.srcport')) {
                    $transactions[] = $packet->time - $query->time;
                    array_splice($pending, $index, 1);
                    break;
                }
            }
        }
    }
    return (object) compact('queries', 'responses', 'pending', 'transactions', 'names', 'rcodes');
}

function protocolLines(array $packets, object $dnsStats): array
{
    $hierarchy = [];
    foreach (PROTOCOLS as $name) {
        $hierarchy[$name] = ['packets' => 0, 'bytes' => 0];
    }
    $checksums = [];
    foreach (CHECKSUMS as [$name]) {
        $checksums[$name] = ['good' => 0, 'bad' => 0, 'none' => 0];
    }
    $malformed = array_fill_keys(['dump', 'eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns'], 0);
    $marks = array_fill_keys(MARKS, 0);
    $bytes = 0;
    foreach ($packets as $packet) {
        $bytes += $packet->length;
        foreach ($packet->layers as $layer) {
            $hierarchy[$layer]['packets']++;
            $hierarchy[$layer]['bytes'] += $packet->length;
        }
        foreach (CHECKSUMS as [$name]) {
            $status = getField($packet, $name . '.checksum.status');
            if ($status !== null) {
                $checksums[$name][$status]++;
            }
        }
        if ($packet->reason !== null) {
            $last = $packet->layers ? $packet->layers[count($packet->layers) - 1] : 'dump';
            $malformed[$last]++;
        }
        if (($packet->mark ?? null) !== null) {
            $marks[$packet->mark]++;
        }
    }
    $lines = ['packets ' . count($packets), 'bytes ' . $bytes,
        'duration ' . seconds($packets[count($packets) - 1]->time - $packets[0]->time), 'hierarchy'];
    foreach ([['eth', 0], ['arp', 2], ['ip', 2], ['icmp', 4], ['udp', 4], ['dns', 6], ['tcp', 4]] as [$name, $indent]) {
        $item = $hierarchy[$name];
        $lines[] = str_repeat(' ', $indent) . $name . ' ' . $item['packets'] . ' ' . $item['bytes'];
    }
    $lines[] = 'checksums';
    foreach (CHECKSUMS as [$name]) {
        $item = $checksums[$name];
        $lines[] = $name . ' good ' . $item['good'] . ' bad ' . $item['bad'] . ($name === 'udp' ? ' none ' . $item['none'] : '');
    }
    $lines[] = 'malformed';
    foreach (['dump', 'eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns'] as $name) {
        $lines[] = $name . ' ' . $malformed[$name];
    }
    $lines[] = 'tcp analysis';
    foreach (MARKS as $name) {
        $lines[] = $name . ' ' . $marks[$name];
    }
    $lines[] = 'dns';
    $lines[] = 'queries ' . $dnsStats->queries;
    $lines[] = 'responses ' . $dnsStats->responses;
    $lines[] = 'transactions ' . count($dnsStats->transactions);
    $lines[] = 'unanswered ' . count($dnsStats->pending);
    if ($dnsStats->transactions) {
        $lines[] = 'response_time min ' . seconds(min($dnsStats->transactions)) . ' max ' . seconds(max($dnsStats->transactions));
    } else {
        $lines[] = 'response_time -';
    }
    for ($code = 0; $code < 16; $code++) {
        if ($dnsStats->rcodes[$code] !== 0) {
            $lines[] = 'rcode ' . rcodeName($code) . ' ' . $dnsStats->rcodes[$code];
        }
    }
    $lines[] = 'names';
    $names = [];
    foreach ($dnsStats->names as $name => $count) {
        $names[] = [(string) $name, $count];
    }
    usort($names, fn($a, $b) => ($b[1] <=> $a[1]) ?: strcmp($a[0], $b[0]));
    foreach ($names as [$name, $count]) {
        $lines[] = $name . ' ' . $count;
    }
    return $lines;
}

function endpointNotation(array $endpoint): string
{
    return ipv4($endpoint[0]) . ':' . $endpoint[1];
}

function conversationLines(array $conversations, int $firstTime): array
{
    $lines = ['type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration'];
    foreach ($conversations as $item) {
        $first = $item->kind === 'ipv4' ? ipv4($item->a) : endpointNotation($item->a);
        $second = $item->kind === 'ipv4' ? ipv4($item->b) : endpointNotation($item->b);
        $lines[] = implode(',', [$item->kind, $first, $second, $item->packets, $item->bytes, $item->abPackets, $item->abBytes,
            $item->baPackets, $item->baBytes, seconds($item->start - $firstTime), seconds($item->end - $item->start)]);
    }
    return $lines;
}

function endpointLines(array $endpoints): array
{
    $lines = ['address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes'];
    foreach ($endpoints as $item) {
        $lines[] = implode(',', [ipv4($item->address), $item->packets, $item->bytes, $item->txPackets, $item->txBytes, $item->rxPackets, $item->rxBytes]);
    }
    return $lines;
}

function streamLines(array $streams, array $packets): array
{
    $lines = [];
    foreach ($streams as $stream) {
        if ($lines) {
            $lines[] = '';
        }
        $lines[] = 'stream ' . $stream->number . ' ' . endpointNotation($stream->client) . ' -> ' . endpointNotation($stream->server);
        $lines[] = 'packets ' . $stream->packets . ' bytes ' . $stream->bytes . ' start ' . seconds($stream->start - $packets[0]->time)
            . ' duration ' . seconds($stream->end - $stream->start);
        $history = [];
        foreach ($stream->history as [$state, $number]) {
            $history[] = $state . ' ' . $number;
        }
        $lines[] = 'states ' . implode(', ', $history);
        $handshake = $stream->handshake;
        $rtt = $handshake['syn'] !== null && $handshake['ack'] !== null
            ? seconds($packets[$handshake['ack'] - 1]->time - $packets[$handshake['syn'] - 1]->time) : '-';
        $lines[] = 'handshake syn ' . ($handshake['syn'] ?? '-') . ' syn_ack ' . ($handshake['syn_ack'] ?? '-')
            . ' ack ' . ($handshake['ack'] ?? '-') . ' rtt ' . $rtt;
        $client = $stream->sides['client'];
        $server = $stream->sides['server'];
        $lines[] = 'options client mss ' . ($client->mss ?? '-') . ' wscale ' . ($client->ws ?? '-')
            . ' server mss ' . ($server->mss ?? '-') . ' wscale ' . ($server->ws ?? '-');
        foreach (['client', 'server'] as $name) {
            $side = $stream->sides[$name];
            $line = $name . ' packets ' . $side->packets . ' payload ' . $side->payload;
            foreach (MARKS as $mark) {
                $line .= ' ' . $mark . ' ' . $side->counts[$mark];
            }
            $lines[] = $line;
        }
        foreach ($stream->events as [$number, $name, $mark, $seq, $length]) {
            $lines[] = 'event ' . $number . ' ' . $name . ' ' . $mark . ' seq ' . $seq . ' len ' . $length;
        }
    }
    return $lines;
}

function writeLines(string $filename, array $lines): void
{
    file_put_contents('output/' . $filename, $lines ? implode("\n", $lines) . "\n" : '');
}

$packets = readCapture('input/capture.txt');
$requests = readRequests('input/filters.txt');
foreach ($packets as $packet) {
    dissectPacket($packet, $packets[0]->time);
}
$streams = trackTcp($packets);
$tables = aggregate($packets);
$dnsStats = dnsTransactions($packets);
foreach ($packets as $packet) {
    $packet->summary = summaryLine($packet);
}
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
writeLines('summary.txt', summaryLines($packets, $requests->filters));
writeLines('details.txt', detailLines($packets, $requests->details));
writeLines('conversations.csv', conversationLines($tables->conversations, $packets[0]->time));
writeLines('endpoints.csv', endpointLines($tables->endpoints));
writeLines('protocol_stats.txt', protocolLines($packets, $dnsStats));
writeLines('tcp_streams.txt', streamLines($streams, $packets));
