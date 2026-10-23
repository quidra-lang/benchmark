<?php
class RouterFault extends Exception {}

class Router
{
    private array $interfaces = [];
    private array $routes = [];
    private array $static = [];
    private array $forwards = [];
    private array $pat = [];
    private array $connections = [];
    private array $timeouts = ['TCP' => 300, 'UDP' => 60, 'ICMP' => 30];
    private array $counts = [];
    private int $clock = 0;
    private int $packetNumber = 0;
    private int $connectionNumber = 0;
    private const DROPS = ['down', 'martian', 'rpf', 'invalid', 'acl_in', 'ttl', 'noroute', 'acl_out', 'exhausted'];

    public function __construct()
    {
        $this->resetCounters();
    }

    private function fail(string $message): never
    {
        throw new RouterFault($message);
    }

    private function find(array $items, callable $predicate): ?object
    {
        foreach ($items as $item) {
            if ($predicate($item)) {
                return $item;
            }
        }
        return null;
    }

    private function address(string $word): int
    {
        if (!preg_match('/\A(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}\z/', $word)) {
            $this->fail("bad address $word");
        }
        $value = 0;
        foreach (explode('.', $word) as $part) {
            if ((int)$part > 255) {
                $this->fail("bad address $word");
            }
            $value = $value * 256 + (int)$part;
        }
        return $value;
    }

    private function ip(int $value): string
    {
        return implode('.', array_map(fn($shift) => ($value >> $shift) & 255, [24, 16, 8, 0]));
    }

    private function network(int $address, int $length): int
    {
        $size = 2 ** (32 - $length);
        return intdiv($address, $size) * $size;
    }

    private function prefix(string $word, bool $hosts = false): array
    {
        $parts = explode('/', $word);
        try {
            if (count($parts) !== 2 || !preg_match('/\A(?:0|[1-9][0-9]?)\z/', $parts[1]) || (int)$parts[1] > 32) {
                $this->fail('invalid');
            }
            $address = $this->address($parts[0]);
        } catch (RouterFault $error) {
            $this->fail("bad prefix $word");
        }
        $length = (int)$parts[1];
        if (!$hosts && $address !== $this->network($address, $length)) {
            $this->fail("host bits set in $word");
        }
        return [$address, $length];
    }

    private function contains(array $prefix, int $address): bool
    {
        return $this->network($prefix[0], $prefix[1]) === $this->network($address, $prefix[1]);
    }

    private function iface(string $name): object
    {
        if (!isset($this->interfaces[$name])) {
            $this->fail("no interface $name");
        }
        return $this->interfaces[$name];
    }

    private function local(int $address): ?string
    {
        foreach ($this->interfaces as $name => $item) {
            if ($item->address === $address) {
                return $name;
            }
        }
        return null;
    }

    private function route(int $address): ?object
    {
        $best = null;
        foreach ($this->routes as $item) {
            if ($this->interfaces[$item->dev]->up && $this->contains($item->prefix, $address) &&
                ($best === null || $item->prefix[1] > $best->prefix[1] || ($item->prefix[1] === $best->prefix[1] && $item->metric < $best->metric))) {
                $best = $item;
            }
        }
        return $best;
    }

    private function routeText(object $item): string
    {
        return $item->type . ' ' . $this->ip($item->prefix[0]) . '/' . $item->prefix[1] .
            ($item->hop === null ? '' : ' via ' . $this->ip($item->hop)) . " dev $item->dev metric $item->metric";
    }

    private function portRange(string $word): array
    {
        if ($word === 'ANY') {
            return [0, 65535, true];
        }
        $parts = explode('-', $word);
        $low = (int)$parts[0];
        $high = (int)($parts[1] ?? $parts[0]);
        if ($low > 65535 || $high > 65535 || $low > $high) {
            $this->fail("bad port range $word");
        }
        return [$low, $high, false];
    }

    private function rangeText(array $range): string
    {
        return $range[2] ? 'any' : ($range[0] === $range[1] ? (string)$range[0] : "$range[0]-$range[1]");
    }

    private function aclPrefix(string $word): array
    {
        return $word === 'ANY' ? [0, 0] : $this->prefix($word);
    }

    private function prefixText(array $prefix): string
    {
        return $prefix[1] === 0 ? 'any' : $this->ip($prefix[0]) . '/' . $prefix[1];
    }

    private function acl(string $name, string $direction, string $protocol, int $source, int $sport, int $destination, int $dport, bool $established): ?string
    {
        $pair = $this->interfaces[$name]->acl[$direction];
        if ($pair->rules === []) {
            return null;
        }
        $rules = $pair->rules;
        usort($rules, fn($a, $b) => $a->seq <=> $b->seq);
        foreach ($rules as $rule) {
            if (($rule->proto !== 'ANY' && $rule->proto !== $protocol) || !$this->contains($rule->src, $source) || !$this->contains($rule->dst, $destination) ||
                (in_array($rule->proto, ['TCP', 'UDP'], true) && ($sport < $rule->sports[0] || $sport > $rule->sports[1] || $dport < $rule->dports[0] || $dport > $rule->dports[1])) ||
                ($rule->established && !$established)) {
                continue;
            }
            $rule->hits++;
            return match ($rule->action) {
                'PERMIT' => null,
                'DENY' => "DROP acl $name $direction $rule->seq",
                default => "REJECT acl $name $direction $rule->seq " . ($protocol === 'TCP' ? 'tcp-reset' : 'icmp-prohibited')
            };
        }
        $pair->default++;
        return "DROP acl $name $direction default";
    }

    private function packet(string $name, string $protocol, string $flags, int $source, int $sport, int $destination, int $dport, int $ttl): array
    {
        $input = $this->interfaces[$name];
        if (!$input->up) return ['DROP down', 'down'];
        foreach ([$source, $destination] as $address) {
            if ($this->contains([0, 8], $address) || $this->contains([127 * 2 ** 24, 8], $address) || $this->contains([224 * 2 ** 24, 3], $address)) {
                return ['DROP martian', 'martian'];
            }
        }
        if ($this->local($source) !== null) return ['DROP martian', 'martian'];
        if ($input->rpf !== 'off') {
            $reverse = $this->route($source);
            if ($reverse === null || ($input->rpf === 'strict' && $reverse->dev !== $name)) return ['DROP rpf', 'rpf'];
        }
        $tuple = [$protocol, $source, $sport, $destination, $dport];
        $pureSyn = $protocol === 'TCP' && $flags === 'S';
        $connection = $this->find($this->connections, fn($item) => $item->orig === $tuple || $item->reply === $tuple);
        $direction = $connection === null ? null : ($connection->orig === $tuple ? 'orig' : 'reply');
        if ($connection !== null && $connection->state === 'CLOSED' && $pureSyn) {
            $this->connections = array_values(array_filter($this->connections, fn($item) => $item !== $connection));
            $connection = null;
        }
        if ($protocol === 'TCP' && $connection === null && !$pureSyn) return ['DROP invalid', 'invalid'];
        $verdict = $this->acl($name, 'in', $protocol, $source, $sport, $destination, $dport, $connection !== null);
        if ($verdict !== null) return [$verdict, 'acl_in'];
        $translatedDestination = $destination;
        $translatedDport = $dport;
        $mapping = null;
        if ($input->role === 'outside') {
            $static = $this->find($this->static, fn($item) => $item->outside === $destination);
            $forward = $destination === $input->address ? $this->find($this->forwards, fn($item) => $item->dev === $name && $item->proto === $protocol && $item->port === $dport) : null;
            if ($static !== null) {
                $translatedDestination = $static->inside;
            } elseif ($forward !== null) {
                $translatedDestination = $forward->inside;
                $translatedDport = $forward->inport;
            } elseif ($destination === $input->address) {
                $mapping = $this->find($this->pat, fn($item) => $item->dev === $name && $item->proto === $protocol && $item->port === $dport);
                if ($mapping !== null) {
                    $translatedDestination = $mapping->inside;
                    $translatedDport = $mapping->inport;
                }
            }
        }
        $local = $this->local($translatedDestination);
        if ($local !== null) return ["LOCAL $local", 'local'];
        if ($ttl === 1) return ['DROP ttl', 'ttl'];
        $selected = $this->route($translatedDestination);
        if ($selected === null) return ['DROP noroute', 'noroute'];
        $outputName = $selected->dev;
        $output = $this->interfaces[$outputName];
        $verdict = $this->acl($outputName, 'out', $protocol, $source, $sport, $translatedDestination, $translatedDport, $connection !== null);
        if ($verdict !== null) return [$verdict, 'acl_out'];
        $translatedSource = $source;
        $translatedSport = $sport;
        if ($input->role === 'inside' && $output->role === 'outside') {
            $static = $this->find($this->static, fn($item) => $item->inside === $source);
            $forward = $this->find($this->forwards, fn($item) => $item->dev === $outputName && $item->proto === $protocol && $item->inside === $source && $item->inport === $sport);
            if ($static !== null) {
                $translatedSource = $static->outside;
            } elseif ($forward !== null) {
                $translatedSource = $output->address;
                $translatedSport = $forward->port;
            } elseif ($output->pool !== null) {
                $mapping = $this->find($this->pat, fn($item) => $item->dev === $outputName && $item->proto === $protocol && $item->inside === $source && $item->inport === $sport);
                if ($mapping === null) {
                    $used = [];
                    foreach ([...$this->pat, ...$this->forwards] as $item) {
                        if ($item->dev === $outputName) $used[$item->port] = true;
                    }
                    $port = 20000;
                    while ($port < 20000 + $output->pool && isset($used[$port])) $port++;
                    if ($port === 20000 + $output->pool) return ['DROP exhausted', 'exhausted'];
                    $mapping = (object)['dev' => $outputName, 'proto' => $protocol, 'inside' => $source, 'inport' => $sport, 'port' => $port, 'last' => $this->clock];
                    $this->pat[] = $mapping;
                }
                $translatedSource = $output->address;
                $translatedSport = $mapping->port;
            }
        }
        if ($mapping !== null) $mapping->last = $this->clock;
        if ($connection === null) {
            $connection = (object)['number' => ++$this->connectionNumber, 'proto' => $protocol, 'orig' => $tuple,
                'reply' => [$protocol, $translatedDestination, $translatedDport, $translatedSource, $translatedSport],
                'input' => $name, 'output' => $outputName, 'state' => $protocol === 'TCP' ? 'SYN_SENT' : 'UNREPLIED',
                'origPackets' => 0, 'replyPackets' => 0, 'origFin' => false, 'replyFin' => false, 'last' => $this->clock];
            $this->connections[] = $connection;
            $direction = 'new';
        }
        $side = $direction === 'reply' ? 'reply' : 'orig';
        $packetField = $side . 'Packets';
        $connection->{$packetField}++;
        $connection->last = $this->clock;
        if ($protocol !== 'TCP') {
            if ($direction === 'reply') $connection->state = 'REPLIED';
        } elseif (str_contains($flags, 'R')) {
            $connection->state = 'CLOSED';
        } else {
            if ($connection->state === 'SYN_SENT' && $direction === 'reply' && str_contains($flags, 'S') && str_contains($flags, 'A')) $connection->state = 'ESTABLISHED';
            if (str_contains($flags, 'F') && in_array($connection->state, ['ESTABLISHED', 'FIN_WAIT'], true)) {
                $finField = $side . 'Fin';
                $connection->{$finField} = true;
                $connection->state = $connection->origFin && $connection->replyFin ? 'CLOSED' : 'FIN_WAIT';
            }
        }
        $output->tx++;
        $selected->hits++;
        $nextHop = $selected->hop === null ? 'direct' : 'via ' . $this->ip($selected->hop);
        $text = "FORWARD $outputName $nextHop ttl=" . ($ttl - 1);
        if ([$translatedDestination, $translatedDport] !== [$destination, $dport]) $text .= ' dnat=' . $this->ip($translatedDestination) . ":$translatedDport";
        if ([$translatedSource, $translatedSport] !== [$source, $sport]) $text .= ' snat=' . $this->ip($translatedSource) . ":$translatedSport";
        return [$text . " conn=$connection->number $direction", 'forwarded'];
    }

    private function resetCounters(): void
    {
        $this->counts = array_fill_keys([...self::DROPS, 'forwarded', 'local', 'errors'], 0);
        foreach ($this->interfaces as $item) {
            $item->rx = $item->tx = $item->drop = 0;
            foreach ($item->acl as $pair) {
                $pair->default = 0;
                foreach ($pair->rules as $rule) $rule->hits = 0;
            }
        }
        foreach ($this->routes as $item) $item->hits = 0;
    }

    private function show(string $what): void
    {
        $names = array_keys($this->interfaces);
        sort($names, SORT_STRING);
        switch ($what) {
            case 'IFACES':
                echo 'show ifaces count=' . count($names) . "\n";
                foreach ($names as $name) {
                    $item = $this->interfaces[$name];
                    $text = $name . ' ' . $this->ip($item->address) . "/$item->length " . ($item->up ? 'up' : 'down') . " $item->role rpf=$item->rpf";
                    if ($item->pool !== null) $text .= ' pat=' . count(array_filter($this->pat, fn($mapping) => $mapping->dev === $name)) . "/$item->pool";
                    echo "$text\n";
                }
                break;
            case 'ROUTES':
                echo 'show routes count=' . count($this->routes) . "\n";
                $routes = $this->routes;
                usort($routes, fn($a, $b) => [$a->prefix[0], $a->prefix[1], $a->metric] <=> [$b->prefix[0], $b->prefix[1], $b->metric]);
                foreach ($routes as $item) echo $this->routeText($item) . " hits=$item->hits" . ($this->interfaces[$item->dev]->up ? '' : ' inactive') . "\n";
                break;
            case 'ACL':
                $count = 0;
                foreach ($this->interfaces as $item) foreach ($item->acl as $pair) $count += count($pair->rules);
                echo "show acl count=$count\n";
                foreach ($names as $name) {
                    foreach (['in', 'out'] as $direction) {
                        $pair = $this->interfaces[$name]->acl[$direction];
                        if ($pair->rules === []) continue;
                        $rules = $pair->rules;
                        usort($rules, fn($a, $b) => $a->seq <=> $b->seq);
                        foreach ($rules as $rule) {
                            echo "acl $name $direction $rule->seq $rule->action $rule->proto " . $this->prefixText($rule->src) . ' ' . $this->rangeText($rule->sports) . ' ' .
                                $this->prefixText($rule->dst) . ' ' . $this->rangeText($rule->dports) . ($rule->established ? ' established' : '') . " hits=$rule->hits\n";
                        }
                        echo "acl $name $direction default DENY hits=$pair->default\n";
                    }
                }
                break;
            case 'NAT':
                echo 'show nat static=' . count($this->static) . ' forward=' . count($this->forwards) . ' pat=' . count($this->pat) . "\n";
                $static = $this->static;
                usort($static, fn($a, $b) => $a->inside <=> $b->inside);
                foreach ($static as $item) echo 'static ' . $this->ip($item->inside) . ' ' . $this->ip($item->outside) . "\n";
                $forwards = $this->forwards;
                usort($forwards, fn($a, $b) => strcmp($a->dev, $b->dev) ?: ($a->port <=> $b->port) ?: strcmp($a->proto, $b->proto));
                foreach ($forwards as $item) echo "forward $item->dev $item->proto $item->port " . $this->ip($item->inside) . ":$item->inport\n";
                $pat = $this->pat;
                usort($pat, fn($a, $b) => strcmp($a->dev, $b->dev) ?: ($a->port <=> $b->port));
                foreach ($pat as $item) echo "pat $item->dev $item->port $item->proto " . $this->ip($item->inside) . ":$item->inport idle=" . ($this->clock - $item->last) . "\n";
                break;
            case 'CONNS':
                echo 'show conns count=' . count($this->connections) . "\n";
                foreach ($this->connections as $item) {
                    [, $source, $sport, $destination, $dport] = $item->orig;
                    [, $replySource, $replySport, $replyDestination, $replyDport] = $item->reply;
                    echo "conn $item->number $item->proto " . $this->ip($source) . ":$sport > " . $this->ip($destination) . ":$dport reply " . $this->ip($replySource) . ":$replySport > " .
                        $this->ip($replyDestination) . ":$replyDport in=$item->input out=$item->output state=$item->state pkts=$item->origPackets/$item->replyPackets idle=" . ($this->clock - $item->last) . "\n";
                }
                break;
            case 'COUNTERS':
                $dropped = array_sum(array_map(fn($reason) => $this->counts[$reason], self::DROPS));
                echo 'show counters packets=' . ($this->counts['forwarded'] + $this->counts['local'] + $dropped) . ' forwarded=' . $this->counts['forwarded'] . ' local=' . $this->counts['local'] . " dropped=$dropped errors=" . $this->counts['errors'] . "\n";
                echo 'drops ' . implode(' ', array_map(fn($reason) => "$reason=" . $this->counts[$reason], self::DROPS)) . "\n";
                foreach ($names as $name) {
                    $item = $this->interfaces[$name];
                    echo "iface $name rx=$item->rx tx=$item->tx drop=$item->drop\n";
                }
                break;
        }
    }

    private function command(array $words): void
    {
        $kind = array_shift($words);
        $a = $words;
        $name = $a[0];
        switch ($kind) {
            case 'IFACE':
                if (isset($this->interfaces[$name])) $this->fail("duplicate interface $name");
                [$address, $length] = $this->prefix($a[1], true);
                if ($length < 8 || $length > 30) $this->fail("bad prefix $a[1]");
                $base = $this->network($address, $length);
                if ($address === $base || $address === $base + 2 ** (32 - $length) - 1) $this->fail("bad host address $a[1]");
                foreach ($this->interfaces as $otherName => $item) {
                    $common = min($length, $item->length);
                    if ($this->network($address, $common) === $this->network($item->address, $common)) $this->fail("subnet overlaps $otherName");
                }
                $this->interfaces[$name] = (object)['address' => $address, 'length' => $length, 'up' => true, 'role' => 'inside', 'pool' => null, 'rpf' => 'off', 'rx' => 0, 'tx' => 0, 'drop' => 0,
                    'acl' => ['in' => (object)['rules' => [], 'default' => 0], 'out' => (object)['rules' => [], 'default' => 0]]];
                $this->routes[] = (object)['type' => 'C', 'prefix' => [$base, $length], 'dev' => $name, 'hop' => null, 'metric' => 0, 'hits' => 0];
                echo "ok iface $name $a[1] network " . $this->ip($base) . "/$length\n";
                break;
            case 'UP':
            case 'DOWN':
                $item = $this->iface($name);
                $state = $kind === 'UP';
                if ($item->up === $state) $this->fail("interface $name already " . ($state ? 'up' : 'down'));
                $item->up = $state;
                echo 'ok ' . strtolower($kind) . " $name\n";
                break;
            case 'ROUTE':
                $prefix = $this->prefix($name);
                $via = $a[1] === 'VIA';
                $hop = $via ? $this->address($a[2]) : null;
                if (!$via) $this->iface($a[2]);
                $metric = (int)$a[3];
                if ($metric < 1 || $metric > 255) $this->fail("bad metric $a[3]");
                $output = $a[2];
                if ($via) {
                    if ($this->local($hop) !== null) $this->fail("nexthop $a[2] is local");
                    $output = null;
                    foreach ($this->interfaces as $key => $item) if ($this->contains([$item->address, $item->length], $hop)) $output = $key;
                    if ($output === null) $this->fail("nexthop $a[2] unreachable");
                }
                if ($this->find($this->routes, fn($item) => $item->type === 'S' && $item->prefix === $prefix && $item->dev === $output && $item->hop === $hop)) $this->fail("duplicate route $name");
                $item = (object)['type' => 'S', 'prefix' => $prefix, 'dev' => $output, 'hop' => $hop, 'metric' => $metric, 'hits' => 0];
                $this->routes[] = $item;
                echo 'ok route ' . $this->routeText($item) . "\n";
                break;
            case 'NOROUTE':
                $prefix = $this->prefix($name);
                $remaining = array_values(array_filter($this->routes, fn($item) => $item->type !== 'S' || $item->prefix !== $prefix));
                $removed = count($this->routes) - count($remaining);
                if ($removed === 0) $this->fail("no static route $name");
                $this->routes = $remaining;
                echo "ok noroute $name removed=$removed\n";
                break;
            case 'LOOKUP':
                $selected = $this->route($this->address($name));
                echo "lookup $name " . ($selected === null ? 'none' : $this->routeText($selected)) . "\n";
                break;
            case 'ACL':
                $item = $this->iface($name);
                $direction = strtolower($a[1]);
                $seq = (int)$a[2];
                if ($seq < 1 || $seq > 9999) $this->fail("bad sequence $a[2]");
                $source = $this->aclPrefix($a[5]);
                $sports = $this->portRange($a[6]);
                $destination = $this->aclPrefix($a[7]);
                $dports = $this->portRange($a[8]);
                if (in_array($a[4], ['ICMP', 'ANY'], true) && ($a[6] !== 'ANY' || $a[8] !== 'ANY')) $this->fail("ports not allowed for $a[4]");
                $pair = $item->acl[$direction];
                if ($this->find($pair->rules, fn($rule) => $rule->seq === $seq)) $this->fail("duplicate sequence $a[2]");
                $pair->rules[] = (object)['seq' => $seq, 'action' => $a[3], 'proto' => $a[4], 'src' => $source, 'sports' => $sports, 'dst' => $destination, 'dports' => $dports, 'established' => count($a) === 10, 'hits' => 0];
                echo "ok acl $name $direction $seq\n";
                break;
            case 'NOACL':
                $pair = $this->iface($name)->acl[strtolower($a[1])];
                $seq = (int)$a[2];
                $rule = $this->find($pair->rules, fn($item) => $item->seq === $seq);
                $direction = strtolower($a[1]);
                if ($rule === null) $this->fail("no rule $a[2] on $name $direction");
                $pair->rules = array_values(array_filter($pair->rules, fn($item) => $item !== $rule));
                echo "ok noacl $name $direction $seq hits=$rule->hits\n";
                break;
            case 'NAT':
                if ($name === 'STATIC') {
                    $inside = $this->address($a[1]);
                    $outside = $this->address($a[2]);
                    if ($this->local($inside) !== null) $this->fail("address $a[1] is local");
                    if ($this->local($outside) !== null) $this->fail("address $a[2] is local");
                    if ($this->find($this->static, fn($item) => $item->inside === $inside)) $this->fail("duplicate static $a[1]");
                    if ($this->find($this->static, fn($item) => $item->outside === $outside)) $this->fail("duplicate static $a[2]");
                    $this->static[] = (object)['inside' => $inside, 'outside' => $outside];
                    echo "ok nat static $a[1] $a[2]\n";
                } elseif ($name === 'OUTSIDE') {
                    $item = $this->iface($a[1]);
                    if ($item->role === 'outside') $this->fail("interface $a[1] already outside");
                    $item->role = 'outside';
                    echo "ok nat outside $a[1]\n";
                } elseif ($name === 'PAT') {
                    $item = $this->iface($a[1]);
                    $count = (int)$a[2];
                    if ($count < 1 || $count > 1000) $this->fail("bad pool size $a[2]");
                    if ($item->pool !== null) $this->fail("pat already on $a[1]");
                    $item->pool = $count;
                    $item->role = 'outside';
                    echo "ok nat pat $a[1] " . $this->ip($item->address) . ' 20000-' . (19999 + $count) . "\n";
                } else {
                    $item = $this->iface($a[1]);
                    $port = (int)$a[3];
                    if ($port < 1 || $port > 65535) $this->fail("bad port $a[3]");
                    $inside = $this->address($a[4]);
                    $inport = (int)$a[5];
                    if ($inport < 1 || $inport > 65535) $this->fail("bad port $a[5]");
                    if ($item->role !== 'outside') $this->fail("interface $a[1] not outside");
                    if ($this->local($inside) !== null) $this->fail("address $a[4] is local");
                    if ($this->find($this->forwards, fn($rule) => $rule->dev === $a[1] && $rule->proto === $a[2] && $rule->port === $port)) $this->fail("duplicate forward $a[1] $a[2] $a[3]");
                    $this->forwards[] = (object)['dev' => $a[1], 'proto' => $a[2], 'port' => $port, 'inside' => $inside, 'inport' => $inport];
                    echo "ok nat forward $a[1] $a[2] $port $a[4]:$inport\n";
                }
                break;
            case 'RPF':
                $item = $this->iface($name);
                $item->rpf = strtolower($a[1]);
                echo "ok rpf $name $item->rpf\n";
                break;
            case 'TIMEOUT':
                $seconds = (int)$a[1];
                if ($seconds < 1 || $seconds > 86400) $this->fail("bad timeout $a[1]");
                $this->timeouts[$name] = $seconds;
                echo "ok timeout $name $seconds\n";
                break;
            case 'TICK':
                $seconds = (int)$name;
                if ($seconds < 1 || $seconds > 86400) $this->fail("bad tick $name");
                $this->clock += $seconds;
                $conns = count($this->connections);
                $mappings = count($this->pat);
                $this->connections = array_values(array_filter($this->connections, function ($item) {
                    $timeout = $item->proto === 'TCP' ? (['SYN_SENT' => 60, 'FIN_WAIT' => 60, 'CLOSED' => 10][$item->state] ?? $this->timeouts['TCP']) : $this->timeouts[$item->proto];
                    return $this->clock - $item->last < $timeout;
                }));
                $this->pat = array_values(array_filter($this->pat, fn($item) => $this->clock - $item->last < $this->timeouts[$item->proto]));
                echo "ok tick time=$this->clock expired conns=" . ($conns - count($this->connections)) . ' nat=' . ($mappings - count($this->pat)) . "\n";
                break;
            case 'PACKET':
                $item = $this->iface($name);
                $protocol = $a[1];
                $flags = $a[2];
                if ($protocol !== 'TCP' && $flags !== '-') $this->fail("flags not allowed for $protocol");
                if ($protocol === 'TCP' && $flags !== '-' && (!preg_match('/\A[SAFR]+\z/', $flags) || count(array_unique(str_split($flags))) !== strlen($flags))) $this->fail("bad flags $flags");
                $source = $this->address($a[3]);
                $sport = (int)$a[4];
                if ($sport > 65535) $this->fail("bad port $a[4]");
                $destination = $this->address($a[5]);
                $dport = (int)$a[6];
                if ($dport > 65535) $this->fail("bad port $a[6]");
                $ttl = (int)$a[7];
                if ($ttl < 1 || $ttl > 255) $this->fail("bad ttl $a[7]");
                $this->packetNumber++;
                $item->rx++;
                [$verdict, $reason] = $this->packet($name, $protocol, $flags, $source, $sport, $destination, $dport, $ttl);
                $this->counts[$reason]++;
                if (in_array($reason, self::DROPS, true)) $item->drop++;
                echo "#$this->packetNumber $protocol $flags $a[3]:$a[4] > $a[5]:$a[6] $verdict\n";
                break;
            case 'SHOW':
                $this->show($name);
                break;
            case 'CLEAR':
                if ($name === 'COUNTERS') {
                    $this->resetCounters();
                    echo "ok clear counters\n";
                } else {
                    echo 'ok clear conns=' . count($this->connections) . ' nat=' . count($this->pat) . "\n";
                    $this->connections = [];
                    $this->pat = [];
                }
                break;
        }
    }

    public function run(): void
    {
        $count = (int)fgets(STDIN);
        for ($index = 0; $index < $count; $index++) {
            try {
                $this->command(explode(' ', trim(fgets(STDIN))));
            } catch (RouterFault $error) {
                $this->counts['errors']++;
                echo 'error: ' . $error->getMessage() . "\n";
            }
        }
    }
}

(new Router())->run();
