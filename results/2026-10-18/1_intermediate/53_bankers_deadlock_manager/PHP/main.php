<?php
class Manager
{
    private array $total = [], $available = [], $processes = [], $queue = [], $history = [], $snapshots = [];
    private string $mode = 'AVOID', $policy = 'ALLOC';
    private bool $trace = false, $auto = false;
    private int $time = 0;
    private const KINDS = ['granted', 'blocked', 'unblocked', 'released', 'finished', 'aborted', 'cancelled'];

    private function out(string $s): void { echo $s, "\n"; }
    private function vec(array $v): string { return '(' . implode(',', $v) . ')'; }
    private function names(array $ids): string { return implode(' ', array_map(fn($p) => "P$p", $ids)); }
    private function zero(): array { return array_fill(0, count($this->total), 0); }
    private function add(array $a, array $b): array { return array_map(fn($x, $y) => $x + $y, $a, $b); }
    private function sub(array $a, array $b): array { return array_map(fn($x, $y) => $x - $y, $a, $b); }
    private function fits(array $a, array $b): bool
    {
        foreach ($a as $i => $x) {
            if ($x > $b[$i]) return false;
        }
        return true;
    }
    private function ids(?array $ps = null): array
    {
        $ids = array_keys($ps ?? $this->processes);
        sort($ids, SORT_NUMERIC);
        return $ids;
    }
    private function need(int $id, ?array $ps = null): array
    {
        $p = ($ps ?? $this->processes)[$id];
        return $this->sub($p['max'], $p['alloc']);
    }
    private function blocked(int $id, ?array $queue = null): ?array
    {
        foreach ($queue ?? $this->queue as $q) {
            if ($q[0] === $id) return $q;
        }
        return null;
    }
    private function check(bool $detect = false, bool $trace = false, ?array $av = null, ?array $ps = null, ?array $queue = null): array
    {
        $ps ??= $this->processes;
        $queue ??= $this->queue;
        $work = $av ?? $this->available;
        $idle = []; $remaining = [];
        foreach ($this->ids($ps) as $p) {
            if ($detect && array_sum($ps[$p]['alloc']) === 0) $idle[] = $p;
            else $remaining[] = $p;
        }
        $sequence = [];
        $label = $detect ? 'detect' : 'safety';
        if ($trace) {
            $suffix = $idle ? ' idle ' . $this->names($idle) : '';
            $this->out("[$label] start work=" . $this->vec($work) . $suffix);
        }
        while (true) {
            $chosen = null;
            foreach ($remaining as $p) {
                $q = $this->blocked($p, $queue);
                $required = $detect ? ($q ? $q[1] : $this->zero()) : $this->need($p, $ps);
                if ($this->fits($required, $work)) { $chosen = $p; break; }
            }
            if ($chosen === null) break;
            $work = $this->add($work, $ps[$chosen]['alloc']);
            $remaining = array_values(array_diff($remaining, [$chosen]));
            $sequence[] = $chosen;
            if ($trace) $this->out("[$label] P$chosen can finish, work=" . $this->vec($work));
        }
        if ($trace && $remaining) $this->out("[$label] stuck work=" . $this->vec($work) . ' remaining ' . $this->names($remaining));
        return [!$remaining, $sequence, $remaining];
    }
    private function reject(int $id, array $v): ?string
    {
        if ($this->blocked($id)) return "process P$id is blocked";
        if (array_sum($v) === 0) return 'zero vector';
        if (!$this->fits($v, $this->need($id))) return 'request exceeds need';
        $last = -1;
        foreach ($this->processes[$id]['alloc'] as $i => $x) if ($x > 0) $last = $i;
        if ($this->mode === 'ORDER') {
            foreach ($v as $i => $x) if ($x > 0 && $i <= $last) return 'resource order violation';
        }
        return null;
    }
    private function decision(int $id, array $v, ?bool $trace = null): array
    {
        if (!$this->fits($v, $this->available)) return [false, 'insufficient resources', []];
        if ($this->mode === 'AVOID') {
            $ps = $this->processes;
            $ps[$id]['alloc'] = $this->add($ps[$id]['alloc'], $v);
            [$safe, $sequence] = $this->check(false, $trace ?? $this->trace, $this->sub($this->available, $v), $ps);
            if (!$safe) return [false, 'unsafe state', []];
            return [true, '', $sequence];
        }
        return [true, '', []];
    }
    private function record(string $kind, int $id, array $v, ?int $wait = null): void
    {
        $this->history[] = [$this->time, $kind, $id, $v, $wait];
    }
    private function grant(int $id, array $v): void
    {
        $this->available = $this->sub($this->available, $v);
        $this->processes[$id]['alloc'] = $this->add($this->processes[$id]['alloc'], $v);
    }
    private function retryQueue(): void
    {
        $old = $this->queue; $this->queue = [];
        foreach ($old as [$id, $v, $since]) {
            if ($this->decision($id, $v)[0]) {
                $this->grant($id, $v);
                $this->out("unblocked P$id " . $this->vec($v));
                $this->record('unblocked', $id, $v, $this->time - $since);
            } else $this->queue[] = [$id, $v, $since];
        }
    }
    private function terminate(int $id, string $kind, bool $retry = true): void
    {
        $v = $this->processes[$id]['alloc'];
        $this->available = $this->add($this->available, $v);
        unset($this->processes[$id]);
        $this->queue = array_values(array_filter($this->queue, fn($q) => $q[0] !== $id));
        $this->out("$kind P$id released " . $this->vec($v));
        $this->record($kind, $id, $v);
        if ($retry) $this->retryQueue();
    }
    private function requireThat(bool $valid, string $message): void
    {
        if (!$valid) throw new RuntimeException($message);
    }
    public function run(string $line, int $time): void
    {
        $this->time = $time;
        $args = explode(' ', $line); $cmd = array_shift($args);
        $id = isset($args[0]) ? (int)$args[0] : 0;
        $withId = in_array($cmd, ['PROCESS','CLAIM','REQUEST','WHATIF','RELEASE'], true);
        $v = array_map('intval', $withId ? array_slice($args, 1) : $args);
        try {
            if ($withId || in_array($cmd, ['ADD','REMOVE'], true)) $this->requireThat(count($v) === count($this->total), 'wrong vector length');
            if (in_array($cmd, ['CLAIM','REQUEST','WHATIF','RELEASE','FINISH','ABORT','CANCEL','MAXGRANT'], true)) {
                $this->requireThat(isset($this->processes[$id]), "unknown process P$id");
            }
            switch ($cmd) {
            case 'RESOURCES':
                $this->total = $this->available = $v;
                $this->processes = $this->queue = $this->history = [];
                $this->out('resources ' . $this->vec($v));
                break;
            case 'MODE': case 'POLICY': case 'TRACE': case 'AUTODETECT':
                if ($cmd === 'MODE') $this->mode = $args[0];
                elseif ($cmd === 'POLICY') $this->policy = $args[0];
                elseif ($cmd === 'TRACE') $this->trace = $args[0] === 'ON';
                else $this->auto = $args[0] === 'ON';
                $this->out(strtolower($cmd) . ' ' . $args[0]);
                break;
            case 'PROCESS':
                $this->requireThat(!isset($this->processes[$id]), "duplicate process P$id");
                $this->requireThat($this->fits($v, $this->total), 'max exceeds total');
                $this->processes[$id] = ['max'=>$v, 'alloc'=>$this->zero(), 'born'=>$time];
                $this->out("process P$id max " . $this->vec($v));
                break;
            case 'CLAIM':
                $this->requireThat(!$this->blocked($id), "process P$id is blocked");
                $this->requireThat($this->fits($this->processes[$id]['alloc'], $v), 'claim below allocation');
                $this->requireThat($this->fits($v, $this->total), 'max exceeds total');
                $ps = $this->processes; $ps[$id]['max'] = $v;
                $this->requireThat($this->mode !== 'AVOID' || $this->check(false, $this->trace, null, $ps)[0], 'claim makes state unsafe');
                $this->processes[$id]['max'] = $v;
                $this->out("claim P$id max " . $this->vec($v));
                $this->retryQueue();
                break;
            case 'ADD': case 'REMOVE':
                $this->requireThat(array_sum($v) !== 0, 'zero vector');
                if ($cmd === 'ADD') {
                    $this->total = $this->add($this->total, $v);
                    $this->available = $this->add($this->available, $v);
                    $this->out('added ' . $this->vec($v) . ' total ' . $this->vec($this->total));
                    $this->retryQueue();
                } else {
                    $this->requireThat($this->fits($v, $this->available), 'remove exceeds available');
                    $total = $this->sub($this->total, $v);
                    $this->requireThat(!in_array(0, $total, true), 'total must stay positive');
                    foreach ($this->processes as $p) $this->requireThat($this->fits($p['max'], $total), 'max exceeds total');
                    $av = $this->sub($this->available, $v);
                    $this->requireThat($this->mode !== 'AVOID' || $this->check(false, $this->trace, $av)[0], 'removal makes state unsafe');
                    $this->total = $total; $this->available = $av;
                    $this->out('removed ' . $this->vec($v) . ' total ' . $this->vec($total));
                }
                break;
            case 'REQUEST': case 'WHATIF':
                $reason = $this->reject($id, $v);
                if ($reason !== null) {
                    if ($cmd === 'REQUEST') throw new RuntimeException($reason);
                    $this->out("whatif P$id " . $this->vec($v) . ": rejected ($reason)");
                    break;
                }
                [$granted, $reason, $sequence] = $this->decision($id, $v);
                if ($cmd === 'WHATIF') {
                    $result = $granted ? 'granted' : "blocked ($reason)";
                    if ($granted && $this->mode === 'AVOID') $result .= ', safe sequence ' . $this->names($sequence);
                    $this->out("whatif P$id " . $this->vec($v) . ": $result");
                } elseif ($granted) {
                    $this->grant($id, $v);
                    $this->out("granted P$id " . $this->vec($v));
                    $this->record('granted', $id, $v);
                } else {
                    $this->queue[] = [$id, $v, $time];
                    $this->out("blocked P$id " . $this->vec($v) . ": $reason");
                    $this->record('blocked', $id, $v);
                    if ($this->auto) {
                        $dead = $this->check(true, $this->trace)[2];
                        if ($dead) $this->out('deadlock detected: ' . $this->names($dead));
                    }
                }
                break;
            case 'RELEASE':
                $this->requireThat(!$this->blocked($id), "process P$id is blocked");
                $this->requireThat(array_sum($v) !== 0, 'zero vector');
                $this->requireThat($this->fits($v, $this->processes[$id]['alloc']), 'release exceeds allocation');
                $this->available = $this->add($this->available, $v);
                $this->processes[$id]['alloc'] = $this->sub($this->processes[$id]['alloc'], $v);
                $this->out("released P$id " . $this->vec($v));
                $this->record('released', $id, $v);
                $this->retryQueue();
                break;
            case 'FINISH': case 'ABORT':
                $this->requireThat($cmd !== 'FINISH' || !$this->blocked($id), "process P$id is blocked");
                $this->terminate($id, $cmd === 'FINISH' ? 'finished' : 'aborted');
                break;
            case 'CANCEL':
                $q = $this->blocked($id);
                $this->requireThat($q !== null, "process P$id is not blocked");
                $this->queue = array_values(array_filter($this->queue, fn($q) => $q[0] !== $id));
                $this->out("cancelled P$id " . $this->vec($q[1]));
                $this->record('cancelled', $id, $q[1]);
                break;
            case 'MAXGRANT':
                $this->requireThat(!$this->blocked($id), "process P$id is blocked");
                $result = $this->zero();
                foreach ($this->need($id) as $i => $n) {
                    for ($x = $n; $x > 0; --$x) {
                        $w = $this->zero(); $w[$i] = $x;
                        if ($this->reject($id, $w) === null && $this->decision($id, $w, false)[0]) break;
                    }
                    $result[$i] = $x;
                }
                $this->out("maxgrant P$id: " . $this->vec($result));
                break;
            case 'SAFE':
                if (!$this->processes) $this->out('safe: no processes');
                else {
                    [$safe, $seq, $remaining] = $this->check(false, $this->trace);
                    $this->out($safe ? 'safe: ' . $this->names($seq) : 'unsafe: ' . $this->names($remaining) . ' cannot finish');
                }
                break;
            case 'SEQUENCES':
                if (!$this->processes) { $this->out('safe sequences: no processes'); break; }
                $count = 0; $first = [];
                $visit = function ($work, $remaining, $path) use (&$visit, &$count, &$first, $id) {
                    if (!$remaining) {
                        ++$count;
                        if (count($first) < $id) $first[] = $path;
                        return;
                    }
                    foreach ($remaining as $p) {
                        if ($this->fits($this->need($p), $work)) $visit($this->add($work, $this->processes[$p]['alloc']), array_values(array_diff($remaining, [$p])), [...$path, $p]);
                    }
                };
                $visit($this->available, $this->ids(), []);
                $this->out("safe sequences: $count");
                foreach ($first as $path) $this->out($this->names($path));
                break;
            case 'DEFICIT':
                $result = [];
                foreach ($this->total as $i => $_) {
                    $limit = 0;
                    foreach ($this->ids() as $p) $limit += $this->need($p)[$i];
                    $answer = '-';
                    for ($x = 0; $x <= $limit; ++$x) {
                        $av = $this->available; $av[$i] += $x;
                        if ($this->check(false, false, $av)[0]) { $answer = $x; break; }
                    }
                    $result[] = $answer;
                }
                $this->out('deficit: ' . $this->vec($result));
                break;
            case 'STATE': $this->stateTable(); break;
            case 'STATS': $this->statistics(); break;
            case 'DETECT':
                $dead = $this->check(true, $this->trace)[2];
                $this->out($dead ? 'deadlocked: ' . $this->names($dead) : 'no deadlock');
                break;
            case 'VICTIMS':
                $dead = $this->check(true)[2];
                if (!$dead) { $this->out('no deadlock'); break; }
                $candidates = [];
                for ($mask = 1; $mask < (1 << count($dead)); ++$mask) {
                    $set = []; $sum = 0;
                    foreach ($dead as $i => $p) if ($mask & (1 << $i)) { $set[] = $p; $sum += array_sum($this->processes[$p]['alloc']); }
                    $candidates[] = [$set, $sum];
                }
                usort($candidates, fn($a, $b) => (count($a[0]) <=> count($b[0])) ?: ($a[1] <=> $b[1]) ?: ($a[0] <=> $b[0]));
                foreach ($candidates as [$set, $_]) {
                    $ps = $this->processes; $av = $this->available;
                    foreach ($set as $p) { $av = $this->add($av, $ps[$p]['alloc']); unset($ps[$p]); }
                    $queue = array_values(array_filter($this->queue, fn($q) => !in_array($q[0], $set, true)));
                    if ($this->check(true, false, $av, $ps, $queue)[0]) { $this->out('victims: ' . $this->names($set)); break; }
                }
                break;
            case 'RECOVER':
                $count = 0;
                while (true) {
                    $dead = $this->check(true, $this->trace)[2];
                    if (!$dead) break;
                    if (($args[0] ?? '') === 'ALL') {
                        foreach ($dead as $p) $this->terminate($p, 'aborted', false);
                        $count += count($dead); $this->retryQueue(); break;
                    }
                    usort($dead, function ($a, $b) {
                        if ($this->policy === 'ALLOC') return (array_sum($this->processes[$a]['alloc']) <=> array_sum($this->processes[$b]['alloc'])) ?: ($b <=> $a);
                        if ($this->policy === 'NEED') return (array_sum($this->need($b)) <=> array_sum($this->need($a))) ?: ($b <=> $a);
                        return $this->processes[$b]['born'] <=> $this->processes[$a]['born'];
                    });
                    $this->terminate($dead[0], 'aborted'); ++$count;
                }
                $this->out($count ? "recovered: $count aborted" : 'no deadlock');
                break;
            case 'WAITGRAPH': case 'GRAPH': $this->graph($cmd === 'GRAPH'); break;
            case 'HISTORY':
                $found = false;
                foreach ($this->history as [$t,$kind,$p,$w,$wait]) {
                    if ($args && $args[0] !== $kind && !(ctype_digit($args[0]) && $p === $id)) continue;
                    $this->out("t=$t $kind P$p " . $this->vec($w) . ($kind === 'unblocked' ? " waited $wait" : ''));
                    $found = true;
                }
                if (!$found) $this->out('no events');
                break;
            case 'SNAPSHOT':
                $this->snapshots[$args[0]] = [$this->total,$this->available,$this->processes,$this->queue,$this->history];
                $this->out('saved ' . $args[0]); break;
            case 'RESTORE':
                $this->requireThat(isset($this->snapshots[$args[0]]), 'unknown snapshot ' . $args[0]);
                [$this->total,$this->available,$this->processes,$this->queue,$this->history] = $this->snapshots[$args[0]];
                $this->out('restored ' . $args[0]); break;
            }
        } catch (RuntimeException $e) { $this->out('error: ' . $e->getMessage()); }
    }
    private function stateTable(): void
    {
        $widths = array_map(fn($x) => strlen((string)$x), $this->total);
        $table = function ($v) use ($widths) {
            $a = []; foreach ($v as $i => $x) $a[] = str_pad((string)$x, $widths[$i], ' ', STR_PAD_LEFT);
            return implode(' ', $a);
        };
        $name = $table(array_map(fn($i) => chr(65+$i), array_keys($this->total)));
        $columns = array_map(fn($w) => max($w, strlen($name)), [10,3,4,7]);
        $row = function ($heading, $content) use ($columns) {
            $s = str_pad($heading, 9);
            foreach ($content as $i => $x) $s .= '  ' . str_pad($x, $columns[$i]);
            $this->out(rtrim($s));
        };
        $row('Process', ['Allocation','Max','Need','Request']);
        $row('', array_fill(0, 4, $name));
        foreach ($this->ids() as $p) {
            $q = $this->blocked($p);
            $row("P$p", array_map($table, [$this->processes[$p]['alloc'],$this->processes[$p]['max'],$this->need($p),$q ? $q[1] : $this->zero()]));
        }
        $row('Available', [$table($this->available),'','','']);
        $row('Total', [$table($this->total),'','','']);
        $requests = array_map(fn($q) => "P{$q[0]} " . $this->vec($q[1]) . " since t={$q[2]}", $this->queue);
        $this->out('blocked queue: ' . ($requests ? implode(', ', $requests) : 'empty'));
    }
    private function statistics(): void
    {
        foreach ($this->total as $i => $total) {
            $used = $total - $this->available[$i]; $p = intdiv($used * 1000, $total); $q = 0;
            foreach ($this->queue as $request) $q += $request[1][$i];
            $this->out(chr(65+$i) . ": allocated $used/$total (" . intdiv($p,10) . '.' . ($p%10) . "%), requested $q");
        }
        $counts = array_fill_keys(self::KINDS, 0); $waits = [];
        foreach ($this->history as $e) { ++$counts[$e[1]]; if ($e[1] === 'unblocked') $waits[] = $e[4]; }
        $parts = []; foreach ($counts as $k => $n) $parts[] = "$k $n";
        $this->out('events: ' . implode(', ', $parts));
        if (!$waits) $this->out('waits: none');
        else {
            $n = count($waits); $sum = array_sum($waits); $avg = intdiv($sum*100,$n);
            $this->out("waits: $n unblocked, total $sum, average " . intdiv($avg,100) . '.' . str_pad((string)($avg%100),2,'0',STR_PAD_LEFT));
        }
    }
    private function graph(bool $single): void
    {
        $this->requireThat(!$single || count(array_filter($this->total, fn($x) => $x !== 1)) === 0, 'not single-instance');
        $ids = $this->ids(); $edges = array_fill_keys($ids, []); $edgeCount = 0;
        if ($single) {
            foreach ($this->total as $i => $_) foreach ($ids as $p) if ($this->processes[$p]['alloc'][$i]) $this->out('assign ' . chr(65+$i) . " -> P$p");
            foreach ($ids as $p) {
                $q = $this->blocked($p); if (!$q) continue;
                foreach ($q[1] as $i => $x) if ($x) {
                    $this->out("request P$p -> " . chr(65+$i));
                    foreach ($ids as $j) if ($this->processes[$j]['alloc'][$i]) $edges[$p][] = [$i,$j];
                }
            }
            foreach ($ids as $p) {
                $q = $this->blocked($p);
                foreach ($this->need($p) as $i => $x) if ($x && (!$q || !$q[1][$i])) $this->out("claim P$p -> " . chr(65+$i));
            }
        } else {
            foreach ($ids as $p) {
                $q = $this->blocked($p); if (!$q) continue;
                foreach ($ids as $j) {
                    if ($p === $j) continue;
                    $labels = [];
                    foreach ($q[1] as $i => $x) if ($x > $this->available[$i] && $this->processes[$j]['alloc'][$i] > 0) $labels[] = chr(65+$i);
                    if (!$labels) continue;
                    $this->out("P$p -> P$j on " . implode(',', $labels));
                    $edges[$p][] = [$j,$j]; ++$edgeCount;
                }
            }
            if (!$edgeCount) $this->out('no wait edges');
        }
        $cycles = [];
        foreach ($ids as $start) {
            $visit = function ($p, $seen, $path) use (&$visit, &$cycles, $edges, $single, $start) {
                foreach ($edges[$p] as [$label,$next]) {
                    $extension = $single ? [$label,$next] : [$next];
                    if ($next === $start) {
                        if ($single || count($seen) >= 2) $cycles[] = array_merge($path,$extension);
                    } elseif ($next > $start && !in_array($next,$seen,true)) $visit($next,[...$seen,$next],array_merge($path,$extension));
                }
            };
            $visit($start,[$start],[$start]);
        }
        usort($cycles, function ($a, $b) {
            for ($i = 0; $i < min(count($a), count($b)); ++$i) {
                if ($a[$i] !== $b[$i]) return $a[$i] <=> $b[$i];
            }
            return count($a) <=> count($b);
        });
        foreach ($cycles as $path) {
            $text = []; foreach ($path as $i => $x) $text[] = $single && $i%2 ? chr(65+$x) : "P$x";
            $this->out('cycle: ' . implode(' -> ', $text));
        }
        if (!$cycles) $this->out('no cycles');
    }
}
$manager = new Manager();
$n = (int)trim(fgets(STDIN));
for ($i = 1; $i <= $n; ++$i) $manager->run(rtrim(fgets(STDIN), "\r\n"), $i);
