<?php

require_once __DIR__ . '/link_network.php';

function typeName(int $type): string
{
    $names = [1 => 'A', 2 => 'NS', 5 => 'CNAME', 6 => 'SOA', 12 => 'PTR', 15 => 'MX', 16 => 'TXT', 28 => 'AAAA'];
    return $names[$type] ?? 'TYPE' . $type;
}

function rcodeName(int $code): string
{
    $names = ['NoError', 'FormErr', 'ServFail', 'NXDomain', 'NotImp', 'Refused'];
    return $names[$code] ?? 'RCODE' . $code;
}

function ipv6(array $bytes): string
{
    $groups = [];
    for ($index = 0; $index < 16; $index += 2) {
        $groups[] = uint($bytes, $index);
    }
    $bestStart = -1;
    $bestLength = 1;
    for ($index = 0; $index < 8;) {
        if ($groups[$index] !== 0) {
            $index++;
            continue;
        }
        $end = $index;
        while ($end < 8 && $groups[$end] === 0) {
            $end++;
        }
        if ($end - $index > $bestLength) {
            $bestStart = $index;
            $bestLength = $end - $index;
        }
        $index = $end;
    }
    $text = array_map(fn($value) => dechex($value), $groups);
    if ($bestStart < 0) {
        return implode(':', $text);
    }
    return implode(':', array_slice($text, 0, $bestStart)) . '::' . implode(':', array_slice($text, $bestStart + $bestLength));
}

class DnsReader
{
    private array $message;

    public function __construct(array $message)
    {
        $this->message = $message;
    }

    private function requireBytes(int $position, int $count): void
    {
        if ($position < 0 || $position + $count > count($this->message)) {
            throw new Malformed('dns: truncated');
        }
    }

    private function read(int $position, int $count = 2): int
    {
        $this->requireBytes($position, $count);
        return uint($this->message, $position, $count);
    }

    private function name(int $position): object
    {
        $labels = [];
        $after = null;
        $pointers = 0;
        while (true) {
            $length = $this->read($position, 1);
            if ($length === 0) {
                return (object) ['text' => $labels ? implode('.', $labels) : '<root>', 'after' => $after ?? $position + 1];
            }
            if ($length >= 192) {
                $low = $this->read($position + 1, 1);
                $after = $after ?? $position + 2;
                $pointers++;
                if ($pointers > 16) {
                    throw new Malformed('dns: compression loop');
                }
                $target = ($length - 192) * 256 + $low;
                if ($target >= count($this->message)) {
                    throw new Malformed('dns: pointer out of range');
                }
                $position = $target;
            } elseif ($length >= 64) {
                throw new Malformed('dns: bad label type');
            } else {
                $this->requireBytes($position + 1, $length);
                $label = '';
                for ($index = $position + 1; $index <= $position + $length; $index++) {
                    $byte = $this->message[$index];
                    $label .= $byte >= 33 && $byte <= 126 && $byte !== 46 && $byte !== 92 ? chr($byte) : '\\' . sprintf('%03d', $byte);
                }
                $labels[] = $label;
                $position += $length + 1;
            }
        }
    }

    private function rdata(int $type, int $start, int $length): object
    {
        if ($type === 1) {
            $address = $this->read($start, 4);
            return (object) ['text' => ipv4($address), 'after' => $start + 4, 'address' => $address];
        }
        if ($type === 28) {
            $this->requireBytes($start, 16);
            return (object) ['text' => ipv6(array_slice($this->message, $start, 16)), 'after' => $start + 16];
        }
        if ($type === 2 || $type === 5 || $type === 12) {
            return $this->name($start);
        }
        if ($type === 15) {
            $preference = $this->read($start);
            $target = $this->name($start + 2);
            return (object) ['text' => $preference . ' ' . $target->text, 'after' => $target->after];
        }
        if ($type === 6) {
            $primary = $this->name($start);
            $mailbox = $this->name($primary->after);
            $parts = [$primary->text, $mailbox->text];
            $position = $mailbox->after;
            for ($index = 0; $index < 5; $index++) {
                $parts[] = $this->read($position, 4);
                $position += 4;
            }
            return (object) ['text' => implode(' ', $parts), 'after' => $position];
        }
        return (object) ['text' => $length . ' bytes', 'after' => $start + $length];
    }

    public function dissect(): object
    {
        $this->requireBytes(0, 12);
        $flags = $this->read(2);
        $questions = $this->read(4);
        $counts = [$this->read(6), $this->read(8), $this->read(10)];
        $fields = ['dns.id' => [$this->read(0)], 'dns.flags' => [$flags], 'dns.flags.response' => [intdiv($flags, 32768) % 2],
            'dns.flags.opcode' => [intdiv($flags, 2048) % 16], 'dns.flags.rcode' => [$flags % 16],
            'dns.count.queries' => [$questions], 'dns.count.answers' => [$counts[0]],
            'dns.count.auth_rr' => [$counts[1]], 'dns.count.add_rr' => [$counts[2]]];
        $answers = [];
        $position = 12;
        for ($index = 0; $index < $questions; $index++) {
            $question = $this->name($position);
            $this->requireBytes($question->after, 4);
            $fields['dns.qry.name'][] = $question->text;
            $fields['dns.qry.type'][] = $this->read($question->after);
            $position = $question->after + 4;
        }
        $sections = ['dns.answer', 'dns.authority', 'dns.additional'];
        for ($section = 0; $section < 3; $section++) {
            for ($index = 0; $index < $counts[$section]; $index++) {
                $owner = $this->name($position);
                $this->requireBytes($owner->after, 10);
                $type = $this->read($owner->after);
                $recordClass = $this->read($owner->after + 2);
                $ttl = $this->read($owner->after + 4, 4);
                $length = $this->read($owner->after + 8);
                $start = $owner->after + 10;
                $this->requireBytes($start, $length);
                $value = $this->rdata($type, $start, $length);
                if ($value->after !== $start + $length) {
                    throw new Malformed('dns: bad rdata length');
                }
                $className = $recordClass === 1 ? 'IN' : 'CLASS' . $recordClass;
                $fields[$sections[$section]][] = $owner->text . ' ' . typeName($type) . ' ' . $className . ' ' . $ttl . ' ' . $value->text;
                if ($section === 0) {
                    $answers[] = (object) ['type' => $type, 'text' => $value->text];
                    if ($type === 1) {
                        $fields['dns.a'][] = $value->address;
                    }
                }
                $position = $start + $length;
            }
        }
        return (object) ['fields' => $fields, 'payload' => [], 'answers' => $answers];
    }
}
