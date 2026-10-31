<?php
class DnsFault extends Exception {
}
class Resolver
{
    private array $roots = [];
    private array $zones = [];
    private ?object $current = null;
    private array $down = [];
    private array $cache = [];
    private array $settings = ['MINTTL' => 1, 'MAXTTL' => 86400, 'NEGTTL' => 3600];
    private int $clock = 0;
    private int $hits = 0;
    private array $queries = [];
    private array $resolutions = ['NOERROR' => 0, 'NODATA' => 0, 'NXDOMAIN' => 0, 'SERVFAIL' => 0];
    private const TYPES = ['A', 'NS', 'CNAME', 'SOA', 'PTR', 'MX', 'TXT', 'AAAA'];
    private const KINDS = ['ANSWER', 'CNAME', 'REFERRAL', 'NODATA', 'NXDOMAIN', 'LAME', 'TIMEOUT'];
    private function fail(string $message): never {
        throw new DnsFault($message);
    }
    private function labels(string $name): array {
        return $name === '.' ? [] : explode('.', substr($name, 0, -1));
    }
    private function nameKey(string $name): string {
        return implode("\0", array_reverse($this->labels($name)));
    }
    private function below(string $name, string $ancestor): bool {
        return $ancestor === '.' || $name === $ancestor || str_ends_with($name, '.' . $ancestor);
    }
    private function ancestors(string $name): array
    {
        $parts = $this->labels($name);
        $result = [];
        for ($index = 0; $index <= count($parts); $index++) $result[] = $index === count($parts) ? '.' : implode('.', array_slice($parts, $index)) . '.';
        return $result;
    }
    private function name(string $word, bool $wildcard = false, ?string $origin = null): string
    {
        if ($origin !== null && $word === '@') return $origin;
        if ($word === '.') return '.';
        $parts = explode('.', str_ends_with($word, '.') ? substr($word, 0, -1) : $word);
        foreach ($parts as $index => $part) {
            if ($wildcard && $index === 0 && $part === '*') continue;
            if (strlen($part) < 1 || strlen($part) > 63 || !preg_match('/\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\z/', $part)) $this->fail("bad name $word");
        }
        $result = strtolower(implode('.', $parts)) . '.';
        if ($origin !== null && $origin !== '.' && !str_ends_with($word, '.')) $result .= $origin;
        return $result;
    }
    private function address(string $word): int
    {
        if (!preg_match('/\A(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}\z/', $word)) $this->fail("bad address $word");
        $result = 0;
        foreach (explode('.', $word) as $part) {
            if ((int)$part > 255) $this->fail("bad address $word");
            $result = $result * 256 + (int)$part;
        }
        return $result;
    }
    private function ip(int $number): string {
        return implode('.', array_map(fn($shift) => ($number >> $shift) & 255, [24, 16, 8, 0]));
    }
    private function ipv6(string $word): array
    {
        $parts = explode('::', $word);
        if (count($parts) > 2) $this->fail("bad address $word");
        $sides = array_map(fn($part) => $part === '' ? [] : explode(':', $part), $parts);
        $groups = array_merge(...$sides);
        foreach ($groups as $group) if (!preg_match('/\A[0-9A-Fa-f]{1,4}\z/', $group)) $this->fail("bad address $word");
        $count = count($groups);
        if (count($parts) === 1 ? $count !== 8 : $count > 7) $this->fail("bad address $word");
        return count($parts) === 1 ? array_map('hexdec', $groups) : [...array_map('hexdec', $sides[0]), ...array_fill(0, 8 - $count, 0), ...array_map('hexdec', $sides[1])];
    }
    private function ipv6Text(array $groups): string
    {
        $bestStart = -1;
        $bestLength = 1;
        $index = 0;
        while ($index < 8) {
            if ($groups[$index] !== 0) {
                $index++;
                continue;
            }
            $finish = $index;
            while ($finish < 8 && $groups[$finish] === 0) $finish++;
            if ($finish - $index > $bestLength) {
                $bestStart = $index;
                $bestLength = $finish - $index;
            }
            $index = $finish;
        }
        $words = array_map('dechex', $groups);
        return $bestStart < 0 ? implode(':', $words) : implode(':', array_slice($words, 0, $bestStart)) . '::' . implode(':', array_slice($words, $bestStart + $bestLength));
    }
    private function integer(string $word): bool {
        return (bool)preg_match('/\A(?:0|[1-9][0-9]{0,8})\z/', $word);
    }
    private function ttl(string $word): int
    {
        if ($this->integer($word)) $seconds = (int)$word;
        else {
            $text = strtolower($word);
            if (!preg_match('/\A(?:(?:0|[1-9][0-9]{0,2})[wdhms])+\z/', $text)) $this->fail("bad ttl $word");
            preg_match_all('/([0-9]+)([wdhms])/', $text, $pairs, PREG_SET_ORDER);
            $previous = -1;
            $seconds = 0;
            $units = ['w' => 604800, 'd' => 86400, 'h' => 3600, 'm' => 60, 's' => 1];
            foreach ($pairs as $pair) {
                $rank = strpos('wdhms', $pair[2]);
                if ($rank <= $previous) $this->fail("bad ttl $word");
                $previous = $rank;
                $seconds += (int)$pair[1] * $units[$pair[2]];
            }
        }
        if ($seconds < 1 || $seconds > 604800) $this->fail("bad ttl $word");
        return $seconds;
    }
    private function checkType(string $type): string
    {
        if (!in_array($type, self::TYPES, true)) $this->fail("bad type $type");
        return $type;
    }
    private function compareData(array $a, array $b): int
    {
        return match ($a['type']) {
            'A', 'AAAA' => $a['data'] <=> $b['data'],
            'MX' => ($a['data'][0] <=> $b['data'][0]) ?: strcmp($this->nameKey($a['data'][1]), $this->nameKey($b['data'][1])),
            'TXT' => strcmp($a['data'], $b['data']), 'SOA' => 0,
            default => strcmp($this->nameKey($a['data']), $this->nameKey($b['data']))
        };
    }
    private function sorted(array $records): array {
        usort($records, fn($a, $b) => $this->compareData($a, $b));
        return $records;
    }
    private function recordText(array $record, ?int $ttl = null): string
    {
        $data = match ($record['type']) {
            'A' => $this->ip($record['data']), 'AAAA' => $this->ipv6Text($record['data']),
            'MX', 'SOA' => implode(' ', $record['data']), default => $record['data']
        };
        return $record['owner'] . ' ' . ($ttl ?? $record['ttl']) . ' ' . $record['type'] . ' ' . $data;
    }
    private function zoneLine(array $w, int $number): void
    {
        if ($w[0] === 'ROOT') {
            $added = [];
            foreach (array_slice($w, 1) as $word) {
                $value = $this->address($word);
                if (in_array($value, $this->roots, true) || in_array($value, $added, true)) $this->fail("duplicate root $word");
                $added[] = $value;
            }
            array_push($this->roots, ...$added);
        }
        elseif ($w[0] === 'ZONE') {
            $this->current = null;
            $origin = $this->name($w[1]);
            $server = $this->address($w[2]);
            foreach ($this->zones as $zone) if ($zone->origin === $origin && $zone->server === $server) $this->fail("duplicate zone $origin at $w[2]");
            $this->current = (object)['origin' => $origin, 'server' => $server, 'line' => $number, 'records' => []];
            $this->zones[] = $this->current;
        }
        else {
            if ($this->current === null) $this->fail('no current zone');
            $owner = $this->name($w[0], true, $this->current->origin);
            if (!$this->below($owner, $this->current->origin)) $this->fail("out of zone $owner");
            $ttl = $this->ttl($w[1]);
            $type = $this->checkType($w[2]);
            $fields = array_slice($w, 3);
            $count = ['MX' => 2, 'SOA' => 7][$type] ?? 1;
            if ($type !== 'TXT' && count($fields) !== $count) $this->fail('wrong field count');
            if ($type === 'A') $data = $this->address($fields[0]);
            elseif ($type === 'AAAA') $data = $this->ipv6($fields[0]);
            elseif (in_array($type, ['NS', 'CNAME', 'PTR'], true)) $data = $this->name($fields[0], false, $this->current->origin);
            elseif ($type === 'MX') {
                if (!$this->integer($fields[0]) || (int)$fields[0] > 65535) $this->fail("bad preference $fields[0]");
                $data = [(int)$fields[0], $this->name($fields[1], false, $this->current->origin)];
            }
            elseif ($type === 'TXT') {
                $data = implode(' ', $fields);
                if (!preg_match('/\A"[^"]*"\z/', $data)) $this->fail("bad text $data");
            }
            else {
                $data = [$this->name($fields[0], false, $this->current->origin), $this->name($fields[1], false, $this->current->origin)];
                for ($i = 2; $i <= 5; $i++) if (!$this->integer($fields[$i])) $this->fail("bad number $fields[$i]");
                if (!$this->integer($fields[6]) || (int)$fields[6] < 1 || (int)$fields[6] > 86400) $this->fail("bad minimum $fields[6]");
                array_push($data, ...array_map('intval', array_slice($fields, 2)));
            }
            if ($type === 'NS' && str_starts_with($owner, '*.')) $this->fail('ns at wildcard');
            if ($type === 'SOA' && $owner !== $this->current->origin) $this->fail('soa not at origin');
            if ($type === 'SOA') foreach ($this->current->records as $record) if ($record['type'] === 'SOA') $this->fail('duplicate soa');
            foreach ($this->current->records as $record) if ($record['owner'] === $owner && $record['type'] === $type && $record['data'] === $data) $this->fail('duplicate record');
            foreach ($this->current->records as $record) if ($record['owner'] === $owner && ($type === 'CNAME' || $record['type'] === 'CNAME')) $this->fail("cname conflict $owner");
            $this->current->records[] = ['owner' => $owner, 'ttl' => $ttl, 'type' => $type, 'data' => $data];
        }
    }
    private function response(string $kind, array $answer = [], array $authority = [], array $additional = [], ?string $cut = null): array
    {
        return ['kind' => $kind, 'answer' => $answer, 'authority' => $authority, 'additional' => $additional, 'cut' => $cut];
    }
    private function known(int $server): bool
    {
        foreach ($this->zones as $zone) if ($zone->server === $server) return true;
        return false;
    }
    private function authoritative(int $server, string $name, string $type, string $cut): array
    {
        if (isset($this->down[$server]) || !$this->known($server)) return $this->response('TIMEOUT');
        $chosen = null;
        foreach ($this->zones as $zone) if ($zone->server === $server && $this->below($name, $zone->origin) && ($chosen === null || count($this->labels($zone->origin)) > count($this->labels($chosen->origin)))) $chosen = $zone;
        if ($chosen === null || count($this->labels($chosen->origin)) < count($this->labels($cut))) return $this->response('LAME');
        $records = $chosen->records;
        $soa = array_values(array_filter($records, fn($record) => $record['type'] === 'SOA'))[0];
        foreach (array_reverse($this->ancestors($name)) as $ancestor) {
            if ($ancestor === $chosen->origin || !$this->below($ancestor, $chosen->origin)) continue;
            $authority = $this->sorted(array_values(array_filter($records, fn($record) => $record['owner'] === $ancestor && $record['type'] === 'NS')));
            if ($authority === []) continue;
            $glue = [];
            foreach ($authority as $record) array_push($glue, ...$this->sorted(array_values(array_filter($records, fn($item) => $item['owner'] === $record['data'] && $item['type'] === 'A'))));
            return $this->response('REFERRAL', [], $authority, $glue, $ancestor);
        }
        $found = array_values(array_filter($records, fn($record) => $record['owner'] === $name));
        if ($found === []) {
            $exists = function ($ancestor) use ($records) {
                foreach ($records as $record) if ($this->below($record['owner'], $ancestor)) return true;
                return false;
            };
            if ($exists($name)) return $this->response('NODATA', [], [$soa]);
            $closest = '.';
            foreach (array_slice($this->ancestors($name), 1) as $ancestor) if ($exists($ancestor)) {
                $closest = $ancestor;
                break;
            }
            $wildcard = $closest === '.' ? '*.' : '*.' . $closest;
            $found = array_values(array_filter($records, fn($record) => $record['owner'] === $wildcard));
            if ($found === []) return $this->response('NXDOMAIN', [], [$soa]);
        }
        $answer = array_values(array_filter($found, fn($record) => $record['type'] === $type));
        $kind = 'ANSWER';
        if ($answer === [] && $type !== 'CNAME') {
            $answer = array_values(array_filter($found, fn($record) => $record['type'] === 'CNAME'));
            $kind = 'CNAME';
        }
        if ($answer === []) return $this->response('NODATA', [], [$soa]);
        return $this->response($kind, array_map(fn($record) => [...$record, 'owner' => $name], $this->sorted($answer)));
    }
    private function describe(array $result): string
    {
        return match ($result['kind']) {
            'REFERRAL' => 'REFERRAL ' . $result['cut'], 'CNAME' => 'CNAME ' . $result['answer'][0]['data'], default => $result['kind']
        };
    }
    private function ask(int $server, string $name, string $type, string $cut): array
    {
        $result = $this->authoritative($server, $name, $type, $cut);
        $this->queries[$server] ??= array_fill_keys(self::KINDS, 0);
        $this->queries[$server][$result['kind']]++;
        return $result;
    }
    private function trace(int $depth, string $text): void {
        echo str_repeat('  ', $depth + 1) . $text . "\n";
    }
    private function key(string $name, string $type): string {
        return $name . '|' . $type;
    }
    private function store(array $records): array
    {
        $ttl = min(max(min(array_column($records, 'ttl')), $this->settings['MINTTL']), $this->settings['MAXTTL']);
        $first = $records[0];
        $this->cache[$this->key($first['owner'], $first['type'])] = ['name' => $first['owner'], 'type' => $first['type'], 'kind' => 'POS', 'records' => $this->sorted($records), 'expiry' => $this->clock + $ttl];
        return array_map(fn($record) => [...$record, 'ttl' => $ttl], $records);
    }
    private function cacheRecords(array $entry): array {
        return array_map(fn($record) => [...$record, 'ttl' => $entry['expiry'] - $this->clock], $entry['records']);
    }
    private function queryServers(string $name, string $type, string $cut, ?array $nameservers, int $depth, array $resolving): ?array
    {
        if ($nameservers === null) {
            foreach ($this->roots as $server) {
                $result = $this->ask($server, $name, $type, $cut);
                $this->trace($depth, 'ASK ' . $this->ip($server) . " $name $type -> " . $this->describe($result));
                if (!in_array($result['kind'], ['LAME', 'TIMEOUT'], true)) return $result;
            }
        }
        else {
            usort($nameservers, fn($a, $b) => strcmp($this->nameKey($a), $this->nameKey($b)));
            foreach ($nameservers as $host) {
                $entry = $this->cache[$this->key($host, 'A')] ?? null;
                if ($entry !== null && $entry['kind'] === 'POS') $addresses = array_column($entry['records'], 'data');
                elseif (in_array([$host, 'A'], $resolving, true)) {
                    $this->trace($depth, "GLUELESS $host -> LOOP");
                    $addresses = [];
                }
                else {
                    $this->trace($depth, "GLUELESS $host");
                    [$status, $answer] = $this->resolve($host, 'A', $depth + 1, $resolving);
                    $addresses = $status === 'NOERROR' ? array_column(array_filter($answer, fn($record) => $record['type'] === 'A'), 'data') : [];
                }
                $addresses = array_unique($addresses);
                sort($addresses, SORT_NUMERIC);
                foreach ($addresses as $server) {
                    $result = $this->ask($server, $name, $type, $cut);
                    $this->trace($depth, 'ASK ' . $this->ip($server) . " $name $type -> " . $this->describe($result));
                    if (!in_array($result['kind'], ['LAME', 'TIMEOUT'], true)) return $result;
                }
            }
        }
        return null;
    }
    private function lookup(string $name, string $type, int $depth, array $resolving): array
    {
        $entry = $this->cache[$this->key($name, $type)] ?? null;
        $result = null;
        if ($entry !== null) $result = $entry['kind'] === 'POS' ? $this->response('ANSWER', $this->cacheRecords($entry)) : $this->response($entry['kind']);
        else foreach ($this->cache as $item) if ($item['kind'] === 'NXDOMAIN' && $this->below($name, $item['name'])) {
            $result = $this->response('NXDOMAIN');
            break;
        }
        if ($result === null && $type !== 'CNAME') {
            $entry = $this->cache[$this->key($name, 'CNAME')] ?? null;
            if ($entry !== null && $entry['kind'] === 'POS') $result = $this->response('CNAME', $this->cacheRecords($entry));
        }
        if ($result !== null) {
            $this->hits++;
            $this->trace($depth, "CACHE HIT $name $type -> " . $this->describe($result));
            return $result;
        }
        $cut = '.';
        $servers = null;
        foreach ($this->ancestors($name) as $ancestor) {
            $entry = $this->cache[$this->key($ancestor, 'NS')] ?? null;
            if ($entry !== null && $entry['kind'] === 'POS') {
                $cut = $ancestor;
                $servers = array_column($entry['records'], 'data');
                $this->hits++;
                $this->trace($depth, "CACHE HIT $name $type -> REFERRAL $cut");
                break;
            }
        }
        while (true) {
            $result = $this->queryServers($name, $type, $cut, $servers, $depth, $resolving);
            if ($result === null) return $this->response("SERVFAIL no server for $cut");
            if ($result['kind'] === 'REFERRAL') {
                $this->store($result['authority']);
                $groups = [];
                foreach ($result['additional'] as $record) $groups[$record['owner']][] = $record;
                foreach ($groups as $records) $this->store($records);
                $cut = $result['cut'];
                $servers = array_column($result['authority'], 'data');
            }
            elseif (in_array($result['kind'], ['ANSWER', 'CNAME'], true)) {
                $result['answer'] = $this->store($result['answer']);
                return $result;
            }
            else {
                $soa = $result['authority'][0];
                $ttl = min($soa['ttl'], $soa['data'][6], $this->settings['NEGTTL']);
                $this->cache[$this->key($name, $type)] = ['name' => $name, 'type' => $type, 'kind' => $result['kind'], 'expiry' => $this->clock + $ttl];
                return $result;
            }
        }
    }
    private function resolve(string $name, string $type, int $depth = 0, array $resolving = []): array
    {
        $resolving[] = [$name, $type];
        $seen = [$name];
        $chain = [];
        $current = $name;
        while (true) {
            $result = $this->lookup($current, $type, $depth, $resolving);
            if ($result['kind'] === 'CNAME') {
                $record = $result['answer'][0];
                $chain[] = $record;
                $target = $record['data'];
                if (in_array($target, $seen, true)) {
                    $status = 'SERVFAIL cname loop';
                    $answer = [];
                    break;
                }
                if (count($chain) === 9) {
                    $status = 'SERVFAIL cname chain too long';
                    $answer = [];
                    break;
                }
                $seen[] = $target;
                $current = $target;
            }
            else {
                $status = $result['kind'] === 'ANSWER' ? 'NOERROR' : $result['kind'];
                $answer = str_starts_with($status, 'SERVFAIL') ? [] : [...$chain, ...$result['answer']];
                break;
            }
        }
        $this->resolutions[str_starts_with($status, 'SERVFAIL') ? 'SERVFAIL' : $status]++;
        return [$status, $answer];
    }
    private function printResult(array $result): void
    {
        [$status, $answer] = $result;
        foreach ($answer as $record) echo 'answer ' . $this->recordText($record) . "\n";
        echo "status $status\n";
    }
    private function addressResolution(string $host): string
    {
        $output = [];
        foreach (['A', 'AAAA'] as $type) {
            [$status, $answer] = $this->resolve($host, $type);
            if ($status !== 'NOERROR') continue;
            foreach ($answer as $record) if ($record['type'] === $type) $output[] = $type === 'A' ? $this->ip($record['data']) : $this->ipv6Text($record['data']);
        }
        return $output === [] ? 'no address' : implode(' ', $output);
    }
    private function command(array $w): void
    {
        $kind = $w[0];
        if ($kind === 'RESOLVE' || $kind === 'MX') {
            $name = $this->name($w[1], true);
            $type = $kind === 'MX' ? 'MX' : $this->checkType($w[2]);
            echo strtolower($kind) . " $name" . ($kind === 'MX' ? '' : " $type") . "\n";
            [$status, $answer] = $this->resolve($name, $type);
            $this->printResult([$status, $answer]);
            if ($kind === 'MX' && $status === 'NOERROR') foreach ($answer as $record) {
                if ($record['type'] !== 'MX') continue;
                [$preference, $host] = $record['data'];
                $addresses = $host === '.' ? 'null' : $this->addressResolution($host);
                echo "exchange $preference $host -> $addresses\n";
            }
            elseif ($kind === 'MX' && $status === 'NODATA') {
                $host = $name;
                foreach ($answer as $record) if ($record['type'] === 'CNAME') $host = $record['data'];
                $addresses = $this->addressResolution($host);
                echo "implicit $host -> $addresses\n";
            }
        }
        elseif ($kind === 'REVERSE') {
            if (str_contains($w[1], ':')) {
                $groups = $this->ipv6($w[1]);
                $text = $this->ipv6Text($groups);
                $digits = implode('', array_map(fn($group) => sprintf('%04x', $group), $groups));
                $reverse = implode('.', str_split(strrev($digits))) . '.ip6.arpa.';
            }
            else {
                $text = $this->ip($this->address($w[1]));
                $reverse = implode('.', array_reverse(explode('.', $text))) . '.in-addr.arpa.';
            }
            echo "reverse $text $reverse\n";
            $this->printResult($this->resolve($reverse, 'PTR'));
        }
        elseif ($kind === 'QUERY' || $kind === 'DUMP') {
            $server = $this->address($w[1]);
            $name = $this->name($w[2], $kind === 'QUERY');
            $serverText = $this->ip($server);
            if ($kind === 'QUERY') {
                $type = $this->checkType($w[3]);
                $result = $this->ask($server, $name, $type, '.');
                echo "query $serverText $name $type -> " . $this->describe($result) . "\n";
                foreach (['answer', 'authority', 'additional'] as $section) foreach ($result[$section] as $record) echo $section . ' ' . $this->recordText($record) . "\n";
            }
            else {
                $chosen = null;
                foreach ($this->zones as $zone) if ($zone->server === $server && $zone->origin === $name) $chosen = $zone;
                if (isset($this->down[$server]) || !$this->known($server)) echo "dump $serverText $name -> TIMEOUT\n";
                elseif ($chosen === null) echo "dump $serverText $name -> REFUSED\n";
                else {
                    echo "dump $serverText $name records=" . count($chosen->records) . "\n";
                    $records = $chosen->records;
                    usort($records, fn($a, $b) => strcmp($this->nameKey($a['owner']), $this->nameKey($b['owner'])) ?: (array_search($a['type'], self::TYPES, true) <=> array_search($b['type'], self::TYPES, true)) ?: $this->compareData($a, $b));
                    foreach ($records as $record) echo '  ' . $this->recordText($record) . "\n";
                }
            }
        }
        elseif ($kind === 'DOWN' || $kind === 'UP') {
            $server = $this->address($w[1]);
            if ($kind === 'DOWN' && isset($this->down[$server])) $this->fail("server $w[1] already down");
            if ($kind === 'UP' && !isset($this->down[$server])) $this->fail("server $w[1] not down");
            if ($kind === 'DOWN') $this->down[$server] = true;
            else unset($this->down[$server]);
            echo strtolower($kind) . ' ' . $this->ip($server) . "\n";
        }
        elseif ($kind === 'SET') {
            [$key, $word] = array_slice($w, 1);
            if (!isset($this->settings[$key])) $this->fail("bad setting $key");
            if (!$this->integer($word) || (int)$word < 1 || (int)$word > 604800) $this->fail("bad value $word");
            $settings = [...$this->settings, $key => (int)$word];
            if ($settings['MINTTL'] > $settings['MAXTTL']) $this->fail('minttl above maxttl');
            $this->settings = $settings;
            echo "set $key=" . (int)$word . "\n";
        }
        elseif ($kind === 'TIME') {
            if (!$this->integer($w[1]) || (int)$w[1] < 1 || (int)$w[1] > 1000000) $this->fail("bad time $w[1]");
            $this->clock += (int)$w[1];
            $before = count($this->cache);
            $this->cache = array_filter($this->cache, fn($entry) => $entry['expiry'] > $this->clock);
            echo "time now=$this->clock expired=" . ($before - count($this->cache)) . "\n";
        }
        elseif ($kind === 'CACHE' || $kind === 'FLUSH') {
            $name = isset($w[1]) ? $this->name($w[1]) : null;
            $entries = array_filter($this->cache, fn($entry) => $name === null || $this->below($entry['name'], $name));
            if ($kind === 'FLUSH') {
                foreach ($entries as $key => $entry) unset($this->cache[$key]);
                echo 'flush removed=' . count($entries) . "\n";
            }
            else {
                echo 'cache entries=' . count($entries) . "\n";
                usort($entries, fn($a, $b) => strcmp($this->nameKey($a['name']), $this->nameKey($b['name'])) ?: (array_search($a['type'], self::TYPES, true) <=> array_search($b['type'], self::TYPES, true)));
                foreach ($entries as $entry) {
                    $ttl = $entry['expiry'] - $this->clock;
                    if ($entry['kind'] === 'POS') foreach ($entry['records'] as $record) echo '  ' . $this->recordText($record, $ttl) . "\n";
                    else echo '  ' . $entry['name'] . " $ttl " . $entry['type'] . ' ' . $entry['kind'] . "\n";
                }
            }
        }
        elseif ($kind === 'STATS') {
            $total = array_sum(array_map('array_sum', $this->queries));
            echo "stats queries=$total hits=$this->hits\n";
            ksort($this->queries, SORT_NUMERIC);
            foreach ($this->queries as $server => $counts) echo '  ' . $this->ip($server) . ' sent=' . array_sum($counts) . ' ' . implode(' ', array_map(fn($response) => strtolower($response) . '=' . $counts[$response], self::KINDS)) . "\n";
            echo 'resolutions ' . implode(' ', array_map(fn($status) => strtolower($status) . '=' . $this->resolutions[$status], ['NOERROR', 'NODATA', 'NXDOMAIN', 'SERVFAIL'])) . "\n";
        }
    }
    public function run(): void
    {
        $zoneSection = true;
        $number = 0;
        while (($line = fgets(STDIN)) !== false) {
            $number++;
            $line = rtrim($line, "\r\n");
            if (!$zoneSection && $line === 'END') break;
            if ($zoneSection && $line === 'END ZONES') {
                $kept = [];
                foreach ($this->zones as $zone) {
                    $soa = array_filter($zone->records, fn($record) => $record['type'] === 'SOA');
                    if ($soa === []) echo "error line $zone->line: zone $zone->origin at " . $this->ip($zone->server) . " has no soa\n";
                    else {
                        $kept[] = $zone;
                        echo "zone $zone->origin at " . $this->ip($zone->server) . ' records=' . count($zone->records) . "\n";
                    }
                }
                $this->zones = $kept;
                echo 'loaded roots=' . count($this->roots) . ' zones=' . count($this->zones) . ' records=' . array_sum(array_map(fn($zone) => count($zone->records), $this->zones)) . "\n";
                $zoneSection = false;
                continue;
            }
            try {
                if ($zoneSection) $this->zoneLine(explode(' ', $line), $number);
                else $this->command(explode(' ', $line));
            }
            catch (DnsFault $error) {
                echo "error line $number: {$error->getMessage()}\n";
            }
        }
    }
}
(new Resolver())->run();
