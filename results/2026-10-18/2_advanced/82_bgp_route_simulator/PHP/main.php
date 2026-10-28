<?php

foreach (['topology', 'policy', 'decision', 'simulator', 'report'] as $module)
    require_once __DIR__ . "/$module.php";
const CONVERGENCE_HEADER = 'event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration';

function collapseRuns(array $path): array
{
    $result = [];
    foreach ($path as $as)
        if (!$result || $result[count($result) - 1] !== $as)
            $result[] = $as;
    return $result;
}

function valleyPosition(string $pattern): int
{
    $i = 0;
    $n = strlen($pattern);
    while ($i < $n && $pattern[$i] === 'U')
        ++$i;
    if ($i < $n && $pattern[$i] === 'P')
        ++$i;
    while ($i < $n && $pattern[$i] === 'D')
        ++$i;
    return $i;
}

function messageText(Message $m): string
{
    return "#{$m->serial} {$m->sender}->{$m->receiver} {$m->link->name} {$m->prefix}";
}

final class Simulation
{
    private array
        $routers = [],
        $sessions = [],
        $bySession = [],
        $logs = [],
        $periods = [],
        $changed = [],
        $traceRecords = [],
        $ongoingTraces = [],
        $ringRecords = [],
        $ongoingRings = []
    ;
    private MessageQueue $messages;
    private int $time = 0;
    private object $period;

    public function __construct(
        private Topology $network,
        private Policies $policies,
        private array $defaults,
        private int $stepcap,
        private array $traces,
    ) {
        foreach ($network->ases as $owner) {
            $router = (object) [
                'owner' => $owner,
                'origination' => [],
                'rib' => [],
                'sessions' => [],
                'changes' => 0,
            ];
            foreach ($network->atAS[$owner] as $link) {
                $s = (object) [
                    'owner' => $owner,
                    'link' => $link,
                    'incoming' => [],
                    'outgoing' => [],
                    'pending' => [],
                    'timer' => null,
                    'sent' => 0,
                    'received' => 0,
                ];
                $router->sessions[] = $s;
                $this->sessions[] = $s;
                $this->bySession[$owner . ':' . $link->number] = $s;
            }
            $this->routers[$owner] = $router;
        }
        $this->messages = new MessageQueue();
    }

    private function log(string $content): void
    {
        $this->logs[] = $this->time . ' ' . $content;
    }

    private function importRoute(object $session, string $prefix, Attribute $attribute): array
    {
        $r = $this->policies->applied(
            'IMPORT',
            $session->owner,
            $session->link,
            $prefix,
            $attribute->path,
            $attribute->communities,
        );
        $localPref = $this->defaults[$session->link->role($session->owner)];
        if ($r !== null && $r->has('DENY'))
            return [null, $r];
        $med = $attribute->med;
        $communities = $attribute->communities;
        if ($r !== null) {
            $localPref = $r->value('LOCALPREF', $localPref);
            $med = $r->value('MED', $med);
            $communities = editCommunities($communities, $r);
        }
        return [
            new Route($attribute->path, $attribute->origin, $med, $communities, $localPref, $session->link),
            $r,
        ];
    }

    private function candidates(int $owner, string $prefix): array
    {
        $routes = [];
        foreach ($this->routers[$owner]->sessions as $s)
            if (isset($s->incoming[$prefix])) {
                [$r] = $this->importRoute($s, $prefix, $s->incoming[$prefix]);
                if ($r !== null)
                    $routes[] = $r;
            }
        return $routes;
    }

    private function advertised(object $session, string $prefix): array
    {
        $owner = $session->owner;
        $link = $session->link;
        $route = $this->routers[$owner]->rib[$prefix] ?? null;
        if (
            $route === null
            || !$route->local() && $route->neighbor() === $link->other($owner)
            || in_array(NO_EXPORT, $route->communities, true)
        )
            return [null, null];
        $r = $this->policies->applied('EXPORT', $owner, $link, $prefix, $route->path, $route->communities);
        if ($r !== null && $r->has('DENY'))
            return [null, $r];
        if (
            !($r?->has('ALLOW') ?? false)
            && !$route->local()
            && $route->link->role($owner) !== 'customer'
            && $link->role($owner) !== 'customer'
        )
            return [null, $r];
        $prepend = $r?->value('PREPEND', 0) ?? 0;
        $med = $r?->value('MED', 0) ?? 0;
        $communities = $r === null ? $route->communities : editCommunities($route->communities, $r);
        return [
            new Attribute(
                [...array_fill(0, 1 + $prepend, $owner), ...$route->path],
                $route->origin,
                $med,
                $communities,
            ),
            $r,
        ];
    }

    private function redecide(int $owner, string $prefix): void
    {
        $router = $this->routers[$owner];
        $route = $router->origination[$prefix] ?? null;
        if ($route === null) {
            $candidates = $this->candidates($owner, $prefix);
            $route = $candidates ? bestRoute($candidates, $this->network->routerIds)[0] : null;
        }
        if (($router->rib[$prefix] ?? null) == $route)
            return;
        if ($route === null)
            unset($router->rib[$prefix]);
        else
            $router->rib[$prefix] = $route;
        $this->log("BEST $owner $prefix " . routeText($route));
        ++$router->changes;
        ++$this->period->counters['best_changes'];
        $key = $owner . ':' . $prefix;
        $this->period->exploration[$key] = ($this->period->exploration[$key] ?? 0) + 1;
        $this->period->bestLines[] = [$this->time, $owner, $prefix, $route];
        $this->changed[$prefix] = true;
        foreach ($router->sessions as $s)
            if ($s->link->up) {
                $s->pending[$prefix] = true;
                if ($s->timer === null)
                    $this->processPending($s);
            }
    }

    private function processPending(object $session): void
    {
        $sent = 0;
        foreach (orderedPrefixes(array_keys($session->pending)) as $prefix) {
            [$content, $rule] = $this->advertised($session, $prefix);
            if (($session->outgoing[$prefix] ?? null) == $content)
                continue;
            if ($content === null)
                unset($session->outgoing[$prefix]);
            else
                $session->outgoing[$prefix] = $content;
            $m = $this->messages->send(
                $this->time,
                $session->owner,
                $session->link->other($session->owner),
                $session->link,
                $prefix,
                $content,
            );
            $this->log(
                'SEND '
                . messageText($m)
                . ' '
                . ($content === null ? 'WITHDRAW' : 'ANNOUNCE ' . attributeText($content)),
            );
            ++$session->sent;
            ++$sent;
            ++$this->period->counters['updates'];
            if ($content === null)
                ++$this->period->counters['withdrawals'];
            if ($rule !== null)
                ++$rule->hits;
        }
        $session->pending = [];
        $session->timer = $sent && $session->link->mrai >= 1 ? $this->time + $session->link->mrai : null;
    }

    private function receive(Message $m): void
    {
        $s = $this->bySession[$m->receiver . ':' . $m->link->number];
        $prefix = $m->prefix;
        $content = $m->content;
        ++$s->received;
        $this->period->convergenceTime = $this->time - $this->period->event->time;
        if ($content === null) {
            unset($s->incoming[$prefix]);
            $result = 'WITHDRAW';
        } elseif (in_array($m->receiver, $content->path, true)) {
            unset($s->incoming[$prefix]);
            $result = 'ANNOUNCE loop';
        } else {
            $s->incoming[$prefix] = $content;
            [$route, $rule] = $this->importRoute($s, $prefix, $content);
            if ($rule !== null)
                ++$rule->hits;
            $result = $route === null
                ? 'ANNOUNCE deny ' . $rule->name
                : 'ANNOUNCE accept' . ($rule !== null ? ' ' . $rule->name : '');
        }
        $this->log('RECV ' . messageText($m) . ' ' . $result);
        $this->redecide($m->receiver, $prefix);
    }

    private function originate(int $owner, string $prefix, string $origin, array $communities): void
    {
        $this->routers[$owner]->origination[$prefix] = Route::originated(
            $origin,
            parseCommunities($communities),
        );
        $this->redecide($owner, $prefix);
    }

    private function linkDown(Link $link): void
    {
        $link->up = false;
        ++$link->downCount;
        foreach ($this->messages->removeLink($link) as $m) {
            $this->log('DROP ' . messageText($m));
            ++$this->period->counters['drops'];
        }
        $endpoints = [$link->first, $link->second];
        sort($endpoints, SORT_NUMERIC);
        $remembered = [];
        foreach ($endpoints as $owner) {
            $s = $this->bySession[$owner . ':' . $link->number];
            $remembered[$owner] = orderedPrefixes(array_keys($s->incoming));
            $s->incoming = $s->outgoing = $s->pending = [];
            $s->timer = null;
        }
        foreach ($endpoints as $owner)
            foreach ($remembered[$owner] as $prefix)
                $this->redecide($owner, $prefix);
    }

    private function linkUp(Link $link): void
    {
        $link->up = true;
        $endpoints = [$link->first, $link->second];
        sort($endpoints, SORT_NUMERIC);
        foreach ($endpoints as $owner) {
            $s = $this->bySession[$owner . ':' . $link->number];
            $s->pending = array_fill_keys(array_keys($this->routers[$owner]->rib), true);
            $this->processPending($s);
        }
    }

    private function changePolicy(Rule $rule, bool $active): void
    {
        $rule->active = $active;
        $router = $this->routers[$rule->owner];
        if ($rule->direction === 'IMPORT') {
            $prefixes = [];
            foreach ($router->sessions as $s)
                array_push($prefixes, ...array_keys($s->incoming));
            foreach (orderedPrefixes($prefixes) as $p)
                $this->redecide($rule->owner, $p);
        } else
            foreach ($router->sessions as $s)
                if ($s->link->up) {
                    foreach ([...array_keys($router->rib), ...array_keys($s->outgoing)] as $p)
                        $s->pending[$p] = true;
                    if ($s->timer === null)
                        $this->processPending($s);
                }
    }

    private function executeEvent(object $event): void
    {
        $this->log("EVENT {$this->period->number} {$event->text}");
        $f = $event->fields;
        switch ($event->kind) {
            case 'INITIAL':
                foreach ($this->network->initial as [$owner, $p, $origin, $comm])
                    $this->originate($owner, $p, $origin, $comm);
                break;
            case 'ANNOUNCE':
                $this->originate((int) $f[1], $f[2], $f[3], array_slice($f, 4));
                break;
            case 'WITHDRAW':
                unset($this->routers[(int) $f[1]]->origination[$f[2]]);
                $this->redecide((int) $f[1], $f[2]);
                break;
            case 'LINK_DOWN':
                $this->linkDown($this->network->byName[$f[2]]);
                break;
            case 'LINK_UP':
                $this->linkUp($this->network->byName[$f[2]]);
                break;
            default:
                $this->changePolicy($this->policies->byName[$f[2]], $event->kind === 'POLICY_ON');
        }
    }

    private function globalState(): string
    {
        $sessions = [];
        foreach ($this->sessions as $s) {
            $incoming = $outgoing = [];
            foreach (orderedPrefixes(array_keys($s->incoming)) as $p)
                $incoming[] = [$p, $s->incoming[$p]];
            foreach (orderedPrefixes(array_keys($s->outgoing)) as $p)
                $outgoing[] = [$p, $s->outgoing[$p]];
            $sessions[] = [
                $incoming,
                $outgoing,
                orderedPrefixes(array_keys($s->pending)),
                $s->timer === null ? null : $s->timer - $this->time,
            ];
        }
        return json_encode([$sessions, $this->messages->state($this->time)], JSON_THROW_ON_ERROR);
    }

    private function detectDivergence(): void
    {
        $p = $this->period;
        if ($p->divergence !== null || $p->deliveryTimes > $this->stepcap)
            return;
        $state = $this->globalState();
        if (isset($p->states[$state])) {
            $first = $p->states[$state];
            $cycle = array_values(array_filter(
                $p->bestLines,
                fn($b) => $first < $b[0] && $b[0] <= $this->time,
            ));
            $p->divergence = [$first, $this->time, $cycle];
        } else
            $p->states[$state] = $this->time;
    }

    private function quiet(): bool
    {
        return $this->messages->nextTime() === null && array_all($this->sessions, fn($s) => !$s->pending);
    }

    private function nextMoment(?int $boundary): int
    {
        $times = [];
        $delivery = $this->messages->nextTime();
        if ($delivery !== null)
            $times[] = $delivery;
        foreach ($this->sessions as $s)
            if ($s->timer !== null)
                $times[] = $s->timer;
        if ($boundary !== null)
            $times[] = $boundary;
        return min($times);
    }

    private function trace(int $source, int $address): object
    {
        $visits = [$source];
        $visited = [$source => true];
        $hops = [];
        $owner = $source;
        while (true) {
            $matches = array_values(array_filter(
                array_keys($this->routers[$owner]->rib),
                fn($p) => prefixContains($p, $address),
            ));
            if (!$matches) {
                $result = $hops ? 'BLACKHOLE' : 'UNREACHABLE';
                break;
            }
            usort($matches, fn($a, $b) => parsePrefix($b)[1] <=> parsePrefix($a)[1]);
            $prefix = $matches[0];
            $route = $this->routers[$owner]->rib[$prefix];
            if ($route->local()) {
                $hops[] = [$owner, $prefix, null];
                $result = 'DELIVERED';
                break;
            }
            $hops[] = [$owner, $prefix, $route->link];
            $owner = $route->link->other($owner);
            $visits[] = $owner;
            if (isset($visited[$owner])) {
                $result = 'LOOP';
                break;
            }
            $visited[$owner] = true;
        }
        return (object) [
            'result' => $result,
            'visits' => $visits,
            'hops' => $hops,
            'count' => count(array_filter($hops, fn($h) => $h[2] !== null)),
            'arrival' => $result === 'DELIVERED' ? $owner : null,
        ];
    }

    private function prefixLoops(string $prefix): array
    {
        $arrows = [];
        foreach ($this->routers as $owner => $router) {
            $r = $router->rib[$prefix] ?? null;
            if ($r !== null && !$r->local())
                $arrows[$owner] = $r->link->other($owner);
        }
        $finished = $loops = [];
        foreach ($this->network->ases as $start) {
            if (isset($finished[$start]))
                continue;
            $path = $positions = [];
            $current = $start;
            while (isset($arrows[$current]) && !isset($finished[$current]) && !isset($positions[$current])) {
                $positions[$current] = count($path);
                $path[] = $current;
                $current = $arrows[$current];
            }
            if (isset($positions[$current])) {
                $cycle = array_slice($path, $positions[$current]);
                $i = array_search(min($cycle), $cycle, true);
                $cycle = [...array_slice($cycle, $i), ...array_slice($cycle, 0, $i)];
                $loops[implode(',', $cycle)] = $cycle;
            }
            foreach ($path as $owner)
                $finished[$owner] = true;
        }
        return $loops;
    }

    private function forwardingChecks(): void
    {
        foreach (orderedPrefixes(array_keys($this->changed)) as $prefix) {
            $loops = $this->prefixLoops($prefix);
            foreach ($this->ongoingRings as $key => $r)
                if ($r->prefix === $prefix && !isset($loops[implode(',', $r->path)])) {
                    $r->end = $this->time;
                    unset($this->ongoingRings[$key]);
                }
            $ordered = array_values($loops);
            usort($ordered, fn($a, $b) => $a <=> $b);
            foreach ($ordered as $loop) {
                $key = $prefix . ':' . implode(',', $loop);
                if (!isset($this->ongoingRings[$key])) {
                    $r = (object) [
                        'prefix' => $prefix,
                        'path' => $loop,
                        'start' => $this->time,
                        'end' => null,
                    ];
                    $this->ringRecords[] = $r;
                    $this->ongoingRings[$key] = $r;
                }
            }
        }
        foreach ($this->traces as $i => [$source, $address, $value]) {
            $path = $this->trace($source, $value);
            $status = in_array($path->result, ['LOOP', 'BLACKHOLE'], true)
                ? [$path->result, $path->visits]
                : null;
            $r = $this->ongoingTraces[$i] ?? null;
            if ($r !== null && $r->status !== $status) {
                $r->end = $this->time;
                unset($this->ongoingTraces[$i]);
            }
            if ($status !== null && !isset($this->ongoingTraces[$i])) {
                $r = (object) ['index' => $i, 'status' => $status, 'start' => $this->time, 'end' => null];
                $this->traceRecords[] = $r;
                $this->ongoingTraces[$i] = $r;
            }
        }
    }

    private function runPeriod(int $number, object $event, ?int $boundary): void
    {
        $before = [];
        foreach ($this->routers as $owner => $router)
            $before[$owner] = $router->rib;
        $p = (object) [
            'number' => $number,
            'event' => $event,
            'before' => $before,
            'counters' => array_fill_keys(['updates', 'withdrawals', 'drops', 'best_changes'], 0),
            'exploration' => [],
            'bestLines' => [],
            'convergenceTime' => 0,
            'deliveryTimes' => 0,
            'states' => [],
            'divergence' => null,
            'status' => null,
            'routesChanged' => 0,
        ];
        $this->period = $p;
        $this->periods[] = $p;
        $this->time = $event->time;
        $this->changed = [];
        $this->executeEvent($event);
        while (true) {
            $delivered = false;
            while ($this->messages->nextTime() === $this->time) {
                $this->receive($this->messages->take());
                $delivered = true;
            }
            foreach ($this->sessions as $s)
                if ($s->timer === $this->time) {
                    $s->timer = null;
                    if ($s->pending)
                        $this->processPending($s);
                }
            if ($this->changed)
                $this->forwardingChecks();
            if ($delivered) {
                ++$p->deliveryTimes;
                $this->detectDivergence();
            }
            $quiet = $this->quiet();
            if (
                $boundary === null
                    ? $quiet || $p->divergence !== null || $p->deliveryTimes >= $this->stepcap
                    : $this->time === $boundary
            )
                break;
            $this->time = $this->nextMoment($boundary);
            $this->changed = [];
        }
        $p->status = $p->divergence !== null
            ? 'DIVERGENT'
            : ($quiet ? 'CONVERGED' : ($boundary === null ? 'CAPPED' : 'UNSETTLED'));
        foreach ($this->routers as $owner => $router)
            foreach (array_unique([...array_keys($before[$owner]), ...array_keys($router->rib)]) as $prefix)
                if (($before[$owner][$prefix] ?? null) != ($router->rib[$prefix] ?? null))
                    ++$p->routesChanged;
        $p->states = [];
    }

    private function ribLines(): array
    {
        $lines = [];
        foreach ($this->routers as $owner => $router) {
            $local = count(array_filter($router->rib, fn($r) => $r->local()));
            $sent = array_sum(array_column($router->sessions, 'sent'));
            $received = array_sum(array_column($router->sessions, 'received'));
            $lines[] =
                "AS $owner routes "
                . count($router->rib)
                . " local $local sent $sent received $received changes {$router->changes}";
            foreach ($router->sessions as $s) {
                $accepted = 0;
                foreach ($s->incoming as $p => $a)
                    if ($this->importRoute($s, $p, $a)[0] !== null)
                        ++$accepted;
                $l = $s->link;
                $lines[] =
                    "SESSION {$l->name} "
                    . $l->other($owner)
                    . ' '
                    . $l->role($owner)
                    . ' '
                    . ($l->up ? 'UP' : 'DOWN')
                    . ' in '
                    . count($s->incoming)
                    . " accepted $accepted out "
                    . count($s->outgoing)
                    . " sent {$s->sent} received {$s->received} flaps {$l->downCount}";
            }
            foreach (orderedPrefixes(array_keys($router->rib)) as $prefix) {
                $route = $router->rib[$prefix];
                $candidates = $this->candidates($owner, $prefix);
                $line = $prefix . ' ' . routeText($route) . ' candidates ' . count($candidates);
                if (!$route->local())
                    $line .= ' reason ' . bestRoute($candidates, $this->network->routerIds)[1];
                $lines[] = $line;
                $remaining = array_values(array_filter($candidates, fn($r) => $r != $route));
                while ($remaining) {
                    [$r] = bestRoute($remaining, $this->network->routerIds);
                    $lines[] = 'ALT ' . routeText($r);
                    $index = array_search($r, $remaining, true);
                    array_splice($remaining, $index, 1);
                }
            }
        }
        return $lines;
    }

    private function traceLines(int $source, string $address, int $value): array
    {
        $p = $this->trace($source, $value);
        $lines = ["TRACE $source $address {$p->result} hops {$p->count}"];
        foreach ($p->hops as [$owner, $prefix, $link])
            $lines[] =
                "HOP $owner $prefix "
                . ($link === null ? 'LOCAL' : 'next ' . $link->other($owner) . ' link ' . $link->name);
        $last = $p->visits[count($p->visits) - 1];
        if ($p->result === 'LOOP')
            $lines[] = "HOP $last REVISIT";
        elseif ($p->result !== 'DELIVERED')
            $lines[] = "HOP $last NOROUTE";
        if (!$p->hops)
            $lines[] = 'CONTROL NONE';
        else {
            $r = $this->routers[$source]->rib[$p->hops[0][1]];
            $notation = $r->local() ? 'LOCAL' : pathText($r->path);
            $match = $p->result === 'DELIVERED' && collapseRuns($r->path) === array_slice($p->visits, 1);
            $lines[] = "CONTROL $notation " . ($match ? 'MATCH' : 'MISMATCH');
        }
        if ($p->count) {
            $pattern = '';
            foreach ($p->hops as [$owner, $prefix, $link])
                if ($link !== null)
                    $pattern .= $link->direction($owner);
            $lines[] =
                "PATTERN $pattern "
                . (valleyPosition($pattern) === strlen($pattern) ? 'VALLEYFREE' : 'VALLEY');
        }
        return $lines;
    }

    private function pathLines(): array
    {
        $lines = [];
        foreach ($this->traces as [$source, $address, $value])
            array_push($lines, ...$this->traceLines($source, $address, $value));
        $prefixes = [];
        foreach ($this->routers as $router)
            array_push($prefixes, ...array_keys($router->origination));
        $prefixes = orderedPrefixes($prefixes);
        $lines[] = 'PREFIXES' . ($prefixes ? ' ' . implode(',', $prefixes) : '');
        foreach ($this->network->ases as $source) {
            $symbols = '';
            foreach ($prefixes as $prefix) {
                $p = $this->trace($source, parsePrefix($prefix)[0]);
                $symbols .= $p->result === 'DELIVERED'
                    ? (
                        $p->count === 0
                            ? '*'
                            : (isset($this->routers[$p->arrival]->origination[$prefix]) ? '+' : 'X')
                    )
                    : ['LOOP' => 'L', 'BLACKHOLE' => 'B', 'UNREACHABLE' => 'U'][$p->result];
            }
            $lines[] = "REACH $source" . ($symbols !== '' ? ' ' . $symbols : '');
        }
        return $lines;
    }

    private function auditLines(): array
    {
        $lines = [];
        $totals = ['LOOP' => 0, 'BLACKHOLE' => 0];
        $records = $this->traceRecords;
        usort($records, fn($a, $b) => [$a->start, $a->index] <=> [$b->start, $b->index]);
        foreach ($records as $r) {
            [$source, $address] = $this->traces[$r->index];
            [$result, $visits] = $r->status;
            ++$totals[$result];
            $end = $r->end ?? 'END';
            $line = "$result $source $address from {$r->start} to $end";
            if ($result === 'BLACKHOLE')
                $line .= ' at ' . $visits[count($visits) - 1];
            $lines[] = $line . ' path ' . pathText($visits);
        }
        $rings = $this->ringRecords;
        usort(
            $rings,
            fn($a, $b) => (
                $a->start <=> $b->start ?: prefixCompare($a->prefix, $b->prefix)
                ?: $a->path[0] <=> $b->path[0]
            ),
        );
        foreach ($rings as $r)
            $lines[] =
                "RING {$r->prefix} from {$r->start} to " . ($r->end ?? 'END') . ' path ' . pathText($r->path);
        $routes = $valleys = 0;
        foreach ($this->routers as $owner => $router)
            foreach (orderedPrefixes(array_keys($router->rib)) as $prefix) {
                $r = $router->rib[$prefix];
                if ($r->local())
                    continue;
                ++$routes;
                $path = collapseRuns([$owner, ...$r->path]);
                $pattern = '';
                for ($i = 0; $i < (count($path) - 1); ++$i)
                    $pattern .= $this->network->connecting($path[$i], $path[$i + 1])[0]->direction($path[$i]);
                $violation = valleyPosition($pattern);
                if ($violation !== strlen($pattern)) {
                    ++$valleys;
                    $lines[] =
                        "VALLEY $owner $prefix path "
                        . pathText($r->path)
                        . " pattern $pattern leaker {$path[$violation]}";
                }
            }
        foreach ($this->policies->rules as $r)
            $lines[] = "RULE {$r->name} {$r->direction} " . ($r->active ? 'ON' : 'OFF') . " hits {$r->hits}";
        $divergent = 0;
        foreach ($this->periods as $p)
            if ($p->divergence !== null) {
                ++$divergent;
                [$first, $repeat, $cycle] = $p->divergence;
                $lines[] =
                    "DIVERGENT event {$p->number} first $first repeat $repeat period " . ($repeat - $first);
                $counts = [];
                foreach ($cycle as [$time, $owner, $prefix, $route]) {
                    $lines[] = "CYCLE $time $owner $prefix " . routeText($route);
                    $counts[$owner][$prefix] = ($counts[$owner][$prefix] ?? 0) + 1;
                }
                ksort($counts, SORT_NUMERIC);
                foreach ($counts as $owner => $prefixCounts)
                    foreach (orderedPrefixes(array_keys($prefixCounts)) as $prefix)
                        $lines[] = "OSCILLATE $owner $prefix changes {$prefixCounts[$prefix]}";
            }
        $lines[] =
            "SUMMARY loops {$totals['LOOP']} blackholes {$totals['BLACKHOLE']} rings "
            . count($rings)
            . " routes $routes valleys $valleys divergent $divergent end {$this->time}";
        return $lines;
    }

    public function run(array $events): void
    {
        foreach ($events as $number => $event)
            $this->runPeriod(
                $number,
                $event,
                isset($events[$number + 1]) ? $events[$number + 1]->time - 1 : null,
            );
        $convergence = [CONVERGENCE_HEADER];
        foreach ($this->periods as $p)
            $convergence[] = implode(',', [
                $p->number,
                $p->event->time,
                $p->event->kind,
                $p->status,
                $p->convergenceTime,
                $p->counters['updates'],
                $p->counters['withdrawals'],
                $p->counters['drops'],
                $p->counters['best_changes'],
                $p->routesChanged,
                $p->exploration ? max($p->exploration) : 0,
            ]);
        writeReports([
            'updates.txt' => $this->logs,
            'convergence.csv' => $convergence,
            'ribs.txt' => $this->ribLines(),
            'paths.txt' => $this->pathLines(),
            'audit.txt' => $this->auditLines(),
        ]);
    }
}

[$defaults, $stepcap, $traces] = readParams();
new Simulation(new Topology(), new Policies(), $defaults, $stepcap, $traces)->run(readEvents());
