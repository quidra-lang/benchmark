<?php
const POLICIES = [
    "FIFO",
    "LRU",
    "LFU",
    "NRU",
    "AGING",
    "CLOCK",
    "ECLOCK",
    "WSCLOCK",
    "RANDOM",
    "OPT",
];
const DEFAULTS = [
    "page" => 256,
    "frames" => 4,
    "tlb" => 4,
    "sets" => 1,
    "policy" => "FIFO",
    "scope" => "GLOBAL",
    "asid" => "OFF",
    "tick" => 0,
    "tau" => 8,
    "seed" => 1,
];
function out(string $line): void
{
    echo $line, "\n";
}
function addr(int $n): string
{
    return "0x" . strtoupper(dechex($n));
}
function ratio(int $x, int $y): string
{
    $v = $y > 0 ? intdiv(10000 * $x, $y) : 0;
    return sprintf("%d.%02d%%", intdiv($v, 100), $v % 100);
}
function sortedKeys(array $a): array
{
    $keys = array_keys($a);
    sort($keys, SORT_NUMERIC);
    return $keys;
}
function fail(string $message): never
{
    throw new RuntimeException($message);
}

class Simulation
{
    public array $c,
        $procs = [],
        $frames = [],
        $tlb = [],
        $swap = [],
        $events = [],
        $history = [];
    public int $time = 0,
        $faults = 0,
        $writebacks = 0,
        $tlbhits = 0,
        $zero = 0,
        $swapin = 0,
        $switches = 0;
    private array $refs;
    private int $cursor = 0,
        $hand = 0,
        $random;
    private ?int $previous = null;
    private bool $fixed = false,
        $trace = false;
    public function __construct(array $config, array $refs)
    {
        $this->c = $config;
        $this->refs = $refs;
        $this->random = $config["seed"];
        $this->frames = array_fill(0, $config["frames"], null);
        $this->tlb = array_fill(0, $config["sets"], []);
    }
    public function declareProcess(int $pid, int $count): void
    {
        if ($this->fixed) {
            fail("processes are fixed");
        }
        if (isset($this->procs[$pid])) {
            fail("duplicate process $pid");
        }
        if ($count < 1 || $count > 256) {
            fail("invalid page count");
        }
        $n = count($this->procs);
        if ($n >= 8 || ($this->c["scope"] === "LOCAL" && $n >= $this->c["frames"])) {
            fail("too many processes");
        }
        $p = (object) [
            "pages" => [],
            "accesses" => 0,
            "faults" => 0,
            "writebacks" => 0,
            "segfaults" => 0,
            "protfaults" => 0,
            "peak" => 0,
            "hand" => 0,
            "refs" => [],
            "exited" => false,
        ];
        for ($i = 0; $i < $count; $i++) {
            $p->pages[] = (object) [
                "pid" => $pid,
                "p" => $i,
                "frame" => null,
                "slot" => null,
                "ro" => false,
                "locked" => false,
                "r" => 0,
                "m" => 0,
                "load" => 0,
                "last" => 0,
                "uses" => 0,
                "age" => 0,
                "ever" => false,
            ];
        }
        $this->procs[$pid] = $p;
    }
    private function process(int $pid): object
    {
        if (!isset($this->procs[$pid])) {
            fail("unknown process $pid");
        }
        $p = $this->procs[$pid];
        if ($p->exited) {
            fail("process $pid exited");
        }
        return $p;
    }
    private function resident(int $pid): int
    {
        return count(array_filter($this->frames, fn($p) => $p !== null && $p->pid === $pid));
    }
    private function quota(int $pid): int
    {
        $ids = sortedKeys($this->procs);
        $n = count($ids);
        return intdiv($this->c["frames"], $n) +
            (array_search($pid, $ids, true) < $this->c["frames"] % $n ? 1 : 0);
    }
    private function invalidate(object $page): void
    {
        foreach ($this->tlb as &$set) {
            $set = array_values(array_filter($set, fn($p) => $p !== $page));
        }
        unset($set);
    }
    private function writeback(object $page): void
    {
        $this->writebacks++;
        $this->procs[$page->pid]->writebacks++;
        $page->m = 0;
        if ($page->slot === null) {
            $slot = 0;
            while (isset($this->swap[$slot])) {
                $slot++;
            }
            $page->slot = $slot;
            $this->swap[$slot] = $page;
        }
    }
    private function victim(int $pid): int
    {
        $candidates = [];
        $unlocked = [];
        foreach ($this->frames as $i => $p) {
            if ($p !== null && ($this->c["scope"] === "GLOBAL" || $p->pid === $pid)) {
                $candidates[] = $i;
                if (!$p->locked) {
                    $unlocked[] = $i;
                }
            }
        }
        if ($unlocked) {
            $candidates = $unlocked;
        }
        $policy = $this->c["policy"];
        if ($policy === "RANDOM") {
            $this->random = (48271 * $this->random) % 2147483647;
            return $candidates[$this->random % count($candidates)];
        }
        if ($policy === "OPT") {
            $chosen = null;
            $best = -1;
            foreach ($candidates as $i) {
                $p = $this->frames[$i];
                $pos = PHP_INT_MAX;
                for ($j = $this->cursor; $j < count($this->refs); $j++) {
                    $r = $this->refs[$j];
                    if ($r[0] === $p->pid && intdiv($r[2], $this->c["page"]) === $p->p) {
                        $pos = $j;
                        break;
                    }
                }
                if ($chosen === null || $pos > $best) {
                    $chosen = $i;
                    $best = $pos;
                }
            }
            return $chosen;
        }
        $fields = ["FIFO" => "load", "LRU" => "last", "LFU" => "uses", "AGING" => "age"];
        if (isset($fields[$policy]) || $policy === "NRU") {
            $chosen = null;
            $best = 0;
            $bestTie = 0;
            foreach ($candidates as $i) {
                $p = $this->frames[$i];
                $value = $policy === "NRU" ? 2 * $p->r + $p->m : $p->{$fields[$policy]};
                $tie = $policy === "NRU" ? $i : $p->load;
                if ($chosen === null || $value < $best || ($value === $best && $tie < $bestTie)) {
                    $chosen = $i;
                    $best = $value;
                    $bestTie = $tie;
                }
            }
            return $chosen;
        }
        $hand = $this->c["scope"] === "GLOBAL" ? $this->hand : $this->procs[$pid]->hand;
        $frames = $this->c["frames"];
        usort(
            $candidates,
            fn($a, $b) => ($a - $hand + $frames) % $frames <=> ($b - $hand + $frames) % $frames,
        );
        $chosen = null;
        if ($policy === "CLOCK") {
            while ($chosen === null) {
                foreach ($candidates as $i) {
                    if ($this->frames[$i]->r === 0) {
                        $chosen = $i;
                        break;
                    }
                    $this->frames[$i]->r = 0;
                }
            }
        } elseif ($policy === "ECLOCK") {
            while ($chosen === null) {
                foreach ($candidates as $i) {
                    $p = $this->frames[$i];
                    if ($p->r === 0 && $p->m === 0) {
                        $chosen = $i;
                        break;
                    }
                }
                if ($chosen !== null) {
                    break;
                }
                foreach ($candidates as $i) {
                    $p = $this->frames[$i];
                    if ($p->r === 0 && $p->m === 1) {
                        $chosen = $i;
                        break;
                    }
                    $p->r = 0;
                }
            }
        } else {
            foreach ($candidates as $i) {
                $p = $this->frames[$i];
                if ($p->r === 1) {
                    $p->r = 0;
                    $p->last = $this->time;
                } elseif ($this->time - $p->last > $this->c["tau"]) {
                    if ($p->m === 0) {
                        $chosen = $i;
                        break;
                    }
                    $this->writeback($p);
                }
            }
            if ($chosen === null) {
                foreach ($candidates as $i) {
                    if ($this->frames[$i]->m === 0) {
                        $chosen = $i;
                        break;
                    }
                }
                $chosen ??= $candidates[0];
            }
        }
        if ($this->c["scope"] === "GLOBAL") {
            $this->hand = ($chosen + 1) % $frames;
        } else {
            $this->procs[$pid]->hand = ($chosen + 1) % $frames;
        }
        return $chosen;
    }
    public function access(int $pid, string $op, int $address, bool $silent = false): void
    {
        $this->fixed = true;
        $this->cursor++;
        $proc = $this->process($pid);
        if ($address >= count($proc->pages) * $this->c["page"]) {
            $proc->segfaults++;
            if (!$silent) {
                out("SEGFAULT P$pid " . addr($address));
            }
            return;
        }
        $page = $proc->pages[intdiv($address, $this->c["page"])];
        if ($op === "W" && $page->ro) {
            $proc->protfaults++;
            if (!$silent) {
                out("PROTFAULT P$pid " . addr($address));
            }
            return;
        }
        $this->events[] = ["access", $pid, $op, $address];
        $this->time++;
        $proc->accesses++;
        $proc->refs[] = $page->p;
        $switched = $this->previous !== null && $this->previous !== $pid;
        if ($switched) {
            $this->switches++;
            if ($this->c["asid"] === "OFF") {
                $this->tlb = array_fill(0, $this->c["sets"], []);
            }
        }
        $this->previous = $pid;
        $set = &$this->tlb[$page->p % $this->c["sets"]];
        $hit = array_search($page, $set, true);
        $fault = false;
        $victim = null;
        $wrote = false;
        if ($hit !== false) {
            $result = "TLBHIT";
            $this->tlbhits++;
            array_splice($set, $hit, 1);
        } else {
            if ($page->frame !== null) {
                $result = "HIT";
            } else {
                $fault = true;
                $this->faults++;
                $proc->faults++;
                if ($page->slot !== null) {
                    $this->swapin++;
                    $result = "FAULT SWAPIN";
                } else {
                    $this->zero++;
                    $result = "FAULT ZERO";
                }
                $free = array_search(null, $this->frames, true);
                $useFree =
                    $this->c["scope"] === "GLOBAL"
                        ? $free !== false
                        : $this->resident($pid) < $this->quota($pid);
                $frame = $useFree ? $free : $this->victim($pid);
                $victim = $this->frames[$frame];
                if ($victim !== null) {
                    $this->invalidate($victim);
                    $wrote = $victim->m === 1;
                    if ($wrote) {
                        $this->writeback($victim);
                    }
                    $victim->frame = null;
                }
                $this->frames[$frame] = $page;
                $page->frame = $frame;
                $page->load = $this->time;
                $page->uses = $page->m = $page->age = 0;
                $proc->peak = max($proc->peak, $this->resident($pid));
            }
            if (count($set) === intdiv($this->c["tlb"], $this->c["sets"])) {
                array_shift($set);
            }
        }
        $set[] = $page;
        unset($set);
        $page->r = 1;
        if ($op === "W") {
            $page->m = 1;
        }
        $page->last = $this->time;
        $page->uses++;
        $page->ever = true;
        $this->history[] = $fault;
        $tick = $this->c["tick"] > 0 && $this->time % $this->c["tick"] === 0;
        if ($tick) {
            foreach ($this->frames as $p) {
                if ($p !== null) {
                    $p->age = intdiv($p->age, 2) + 128 * $p->r;
                    $p->r = 0;
                }
            }
        }
        if ($this->trace && !$silent) {
            $line =
                "t={$this->time} P$pid $op " .
                addr($address) .
                " page={$page->p} frame={$page->frame} phys=" .
                addr($page->frame * $this->c["page"] + ($address % $this->c["page"])) .
                " $result";
            if ($victim !== null) {
                $line .= " evict=P{$victim->pid}:{$victim->p}";
            }
            if ($wrote) {
                $line .= " writeback";
            }
            if ($switched) {
                $line .= " switch";
            }
            out($line);
            if ($tick) {
                out("t={$this->time} tick");
            }
        }
    }
    public function exitProcess(int $pid, bool $silent = false): void
    {
        $p = $this->process($pid);
        $freed = $this->resident($pid);
        $slots = 0;
        foreach ($p->pages as $page) {
            if ($page->frame !== null) {
                $this->frames[$page->frame] = null;
            }
            $page->frame = null;
            $this->invalidate($page);
            if ($page->slot !== null) {
                unset($this->swap[$page->slot]);
                $page->slot = null;
                $slots++;
            }
        }
        $p->exited = true;
        $this->events[] = ["exit", $pid];
        if (!$silent) {
            out("EXIT P$pid freed=$freed slots=$slots");
        }
    }
    public function attributes(
        string $cmd,
        int $pid,
        int $first,
        int $last,
        ?string $protection = null,
    ): void {
        $p = $this->process($pid);
        if ($first > $last || $last >= count($p->pages)) {
            fail("invalid page range");
        }
        for ($i = $first; $i <= $last; $i++) {
            if ($cmd === "PROTECT") {
                $p->pages[$i]->ro = $protection === "RO";
            } else {
                $p->pages[$i]->locked = $cmd === "LOCK";
            }
        }
        if ($cmd !== "PROTECT") {
            $this->events[] = ["attribute", $cmd, $pid, $first, $last];
        }
    }
    public function clean(bool $silent = false): void
    {
        $count = 0;
        foreach ($this->frames as $p) {
            if ($p !== null && $p->m === 1) {
                $this->writeback($p);
                $count++;
            }
        }
        $this->events[] = ["clean"];
        if (!$silent) {
            out("CLEAN written=$count");
        }
    }
    private function rerun(string $policy, int $frames): Simulation
    {
        $config = $this->c;
        $config["policy"] = $policy;
        $config["frames"] = $frames;
        $refs = [];
        foreach ($this->events as $e) {
            if ($e[0] === "access") {
                $refs[] = array_slice($e, 1);
            }
        }
        $s = new Simulation($config, $refs);
        foreach ($this->procs as $pid => $p) {
            $s->declareProcess($pid, count($p->pages));
        }
        foreach ($this->events as $e) {
            switch ($e[0]) {
                case "access":
                    $s->access($e[1], $e[2], $e[3], true);
                    break;
                case "exit":
                    $s->exitProcess($e[1], true);
                    break;
                case "clean":
                    $s->clean(true);
                    break;
                case "attribute":
                    $s->attributes($e[1], $e[2], $e[3], $e[4]);
                    break;
            }
        }
        return $s;
    }
    public function command(array $w): void
    {
        $cmd = $w[0];
        $pid = (int) ($w[1] ?? 0);
        switch ($cmd) {
            case "PROCESS":
                $this->declareProcess($pid, (int) $w[2]);
                break;
            case "EXIT":
                $this->exitProcess($pid);
                break;
            case "PROTECT":
            case "LOCK":
            case "UNLOCK":
                $this->attributes($cmd, $pid, (int) $w[2], (int) $w[3], $w[4] ?? null);
                break;
            case "TRACE":
                $this->trace = $w[1] === "ON";
                break;
            case "CLEAN":
                $this->clean();
                break;
            case "SUMMARY":
                out(
                    "SUMMARY policy={$this->c["policy"]} scope={$this->c["scope"]} time={$this->time}",
                );
                $seg = $prot = 0;
                foreach ($this->procs as $p) {
                    $seg += $p->segfaults;
                    $prot += $p->protfaults;
                }
                out(
                    "total faults={$this->faults} zero={$this->zero} swapin={$this->swapin} faultrate=" .
                        ratio($this->faults, $this->time) .
                        " tlbhits={$this->tlbhits} tlbrate=" .
                        ratio($this->tlbhits, $this->time) .
                        " writebacks={$this->writebacks} switches={$this->switches} segfaults=$seg protfaults=$prot",
                );
                foreach (sortedKeys($this->procs) as $id) {
                    $p = $this->procs[$id];
                    $line =
                        "P$id accesses={$p->accesses} faults={$p->faults} writebacks={$p->writebacks} segfaults={$p->segfaults} protfaults={$p->protfaults} resident=" .
                        $this->resident($id) .
                        " peak={$p->peak}";
                    if ($this->c["scope"] === "LOCAL") {
                        $line .= " quota=" . $this->quota($id);
                    }
                    if ($p->exited) {
                        $line .= " exited";
                    }
                    out($line);
                }
                break;
            case "FRAMES":
                out("FRAMES used=" . count(array_filter($this->frames)) . "/" . $this->c["frames"]);
                foreach ($this->frames as $i => $p) {
                    if ($p === null) {
                        out("$i free");
                    } else {
                        out(
                            "$i P{$p->pid}:{$p->p} R={$p->r} M={$p->m} load={$p->load} last={$p->last} uses={$p->uses} age={$p->age}" .
                                ($p->locked ? " locked" : ""),
                        );
                    }
                }
                if (in_array($this->c["policy"], ["CLOCK", "ECLOCK", "WSCLOCK"], true)) {
                    if ($this->c["scope"] === "GLOBAL") {
                        out("hand={$this->hand}");
                    } else {
                        $line = "hand";
                        foreach (sortedKeys($this->procs) as $id) {
                            $line .= " P$id=" . $this->procs[$id]->hand;
                        }
                        out($line);
                    }
                }
                break;
            case "PAGETABLE":
                $p = $this->process($pid);
                out(
                    "PAGETABLE P$pid pages=" .
                        count($p->pages) .
                        " resident=" .
                        $this->resident($pid),
                );
                foreach ($p->pages as $page) {
                    if (!$page->ever) {
                        continue;
                    }
                    if ($page->frame !== null) {
                        $state = "frame={$page->frame} R={$page->r} M={$page->m}";
                    } elseif ($page->slot !== null) {
                        $state = "swap={$page->slot}";
                    } else {
                        $state = "zero";
                    }
                    out(
                        "{$page->p} $state" .
                            ($page->ro ? " RO" : "") .
                            ($page->locked ? " locked" : ""),
                    );
                }
                break;
            case "TLB":
                $used = array_sum(array_map("count", $this->tlb));
                out("TLB used=$used/{$this->c["tlb"]} sets={$this->c["sets"]}");
                foreach ($this->tlb as $i => $set) {
                    $line = "set $i:";
                    foreach (array_reverse($set) as $p) {
                        $line .= " P{$p->pid}:{$p->p}->{$p->frame}";
                    }
                    out($line);
                }
                break;
            case "SWAP":
                out("SWAP used=" . count($this->swap));
                foreach (sortedKeys($this->swap) as $slot) {
                    $p = $this->swap[$slot];
                    out("$slot P{$p->pid}:{$p->p}");
                }
                break;
            case "COMPARE":
                out("COMPARE accesses={$this->time} frames={$this->c["frames"]}");
                $results = [];
                foreach (POLICIES as $i => $policy) {
                    $s = $this->rerun($policy, $this->c["frames"]);
                    out(
                        "$policy faults={$s->faults} writebacks={$s->writebacks} tlbhits={$s->tlbhits}",
                    );
                    $results[] = [$s->faults, $s->writebacks, $i, $policy];
                }
                sort($results);
                out("ranking " . implode(" ", array_column($results, 3)));
                break;
            case "CURVE":
                [$policy, $lo, $hi] = [$w[1], (int) $w[2], (int) $w[3]];
                if (!in_array($policy, POLICIES, true)) {
                    fail("unknown policy");
                }
                if (
                    $lo < 1 ||
                    $lo > $hi ||
                    $hi > 16 ||
                    ($this->c["scope"] === "LOCAL" && $lo < count($this->procs))
                ) {
                    fail("invalid frame range");
                }
                out("CURVE $policy frames=$lo..$hi");
                $previous = null;
                for ($f = $lo; $f <= $hi; $f++) {
                    $faults = $this->rerun($policy, $f)->faults;
                    out(
                        "F=$f faults=$faults" .
                            ($previous !== null && $faults > $previous ? " ANOMALY" : ""),
                    );
                    $previous = $faults;
                }
                break;
            case "EAT":
                if ($this->time === 0) {
                    out("EAT accesses=0");
                } else {
                    $total =
                        (int) $w[1] * $this->time +
                        (int) $w[2] * (2 * $this->time - $this->tlbhits) +
                        (int) $w[3] * ($this->swapin + $this->writebacks);
                    $v = intdiv(100 * $total, $this->time);
                    out(
                        "EAT accesses={$this->time} total=$total average=" .
                            sprintf("%d.%02d", intdiv($v, 100), $v % 100),
                    );
                }
                break;
            case "TIMELINE":
                if ($pid < 1) {
                    fail("invalid window");
                }
                $line = "TIMELINE window=$pid";
                foreach (array_chunk($this->history, $pid) as $slice) {
                    $line .= " " . count(array_filter($slice));
                }
                out($line);
                break;
            case "WSET":
            case "HOT":
                $p = $this->process($pid);
                $n = (int) $w[2];
                if ($n < 1) {
                    fail($cmd === "WSET" ? "invalid window" : "invalid count");
                }
                $refs = $cmd === "WSET" ? array_slice($p->refs, -$n) : $p->refs;
                $counts = array_count_values($refs);
                $pages = array_keys($counts);
                if ($cmd === "WSET") {
                    sort($pages, SORT_NUMERIC);
                    out(
                        "WSET P$pid window=$n size=" .
                            count($pages) .
                            ($pages ? " " . implode(" ", $pages) : ""),
                    );
                } else {
                    usort($pages, fn($a, $b) => $counts[$b] <=> $counts[$a] ?: $a <=> $b);
                    $line = "HOT P$pid";
                    foreach (array_slice($pages, 0, $n) as $page) {
                        $line .= " $page:{$counts[$page]}";
                    }
                    out($line);
                }
                break;
            default:
                $this->access((int) $w[0], $w[1], intval($w[2], 16));
                break;
        }
    }
}
function settings(array $w): array
{
    $c = DEFAULTS;
    $seen = [];
    foreach (array_slice($w, 1) as $pair) {
        [$key, $value] = explode("=", $pair);
        if (!array_key_exists($key, $c)) {
            fail("unknown key $key");
        }
        if (isset($seen[$key])) {
            fail("duplicate key $key");
        }
        $seen[$key] = true;
        $n = (int) $value;
        $ranges = [
            "frames" => [1, 16],
            "tlb" => [1, 8],
            "sets" => [1, 8],
            "tick" => [0, 1000],
            "tau" => [1, 1000],
            "seed" => [1, 2147483646],
        ];
        if ($key === "policy") {
            $valid = in_array($value, POLICIES, true);
        } elseif ($key === "scope") {
            $valid = in_array($value, ["GLOBAL", "LOCAL"], true);
        } elseif ($key === "asid") {
            $valid = in_array($value, ["ON", "OFF"], true);
        } elseif ($key === "page") {
            $valid = $n >= 16 && $n <= 4096 && ($n & ($n - 1)) === 0;
        } else {
            $valid = $n >= $ranges[$key][0] && $n <= $ranges[$key][1];
        }
        if (!$valid) {
            fail("invalid $key");
        }
        $c[$key] = in_array($key, ["policy", "scope", "asid"], true) ? $value : $n;
    }
    if ($c["tlb"] % $c["sets"] !== 0) {
        fail("invalid sets");
    }
    return $c;
}
$commands = [];
$n = (int) trim(fgets(STDIN));
for ($i = 0; $i < $n; $i++) {
    $w = explode(" ", trim(fgets(STDIN)));
    if ($w[0] === "LOOP") {
        for ($r = 0; $r < (int) $w[6]; $r++) {
            for ($j = 0; $j < (int) $w[5]; $j++) {
                $commands[] = [$w[1], $w[2], addr(intval($w[3], 16) + $j * (int) $w[4])];
            }
        }
    } elseif ($w[0] === "RAND") {
        [$lo, $hi, $x] = [intval($w[2], 16), intval($w[3], 16), (int) $w[5]];
        for ($j = 0; $j < (int) $w[4]; $j++) {
            $x = (48271 * $x) % 2147483647;
            $address = $lo + ($x % ($hi - $lo));
            $x = (48271 * $x) % 2147483647;
            $commands[] = [$w[1], $x % 100 < (int) $w[6] ? "W" : "R", addr($address)];
        }
    } else {
        $commands[] = $w;
    }
}
$simulation = null;
foreach ($commands as $i => $w) {
    try {
        if ($w[0] === "SYSTEM") {
            $simulation = null;
            $config = settings($w);
            $refs = [];
            for ($j = $i + 1; $j < count($commands); $j++) {
                $q = $commands[$j];
                if ($q[0] === "SYSTEM") {
                    break;
                }
                if (ctype_digit($q[0][0])) {
                    $refs[] = [(int) $q[0], $q[1], intval($q[2], 16)];
                }
            }
            $simulation = new Simulation($config, $refs);
            $parts = ["SYSTEM"];
            foreach ($config as $key => $value) {
                $parts[] = "$key=$value";
            }
            out(implode(" ", $parts));
        } elseif ($simulation !== null) {
            $simulation->command($w);
        } else {
            out("ERROR no system");
        }
    } catch (RuntimeException $e) {
        out("ERROR " . $e->getMessage());
    }
}
