<?php
const TYPES = ["AND", "OR", "NAND", "NOR", "XOR", "XNOR", "NOT", "BUF", "MUX2", "DFF"];
const COUNTS = [
    "BUILD" => 1,
    "RESET" => 0,
    "SET" => 3,
    "APPLY" => 2,
    "PULSE" => 3,
    "CLOCK" => 4,
    "RUN" => 1,
    "WATCH" => 1,
    "UNWATCH" => 1,
    "SHOW" => 0,
    "CHECK" => 2,
    "PROBE" => 1,
    "WAVE" => 2,
    "HISTORY" => 1,
    "ACTIVITY" => 1,
    "STATUS" => 0,
    "MODULES" => 0,
    "NETLIST" => 1,
    "HIERARCHY" => 1,
    "STATS" => 1,
    "TRUTHTABLE" => 1,
    "EQUIV" => 2,
    "FAULTS" => 1,
    "CRITICAL" => 1,
    "PERIOD" => 1,
];
const SIM = [
    "RESET",
    "SET",
    "APPLY",
    "PULSE",
    "CLOCK",
    "RUN",
    "WATCH",
    "UNWATCH",
    "SHOW",
    "CHECK",
    "PROBE",
    "WAVE",
    "HISTORY",
    "ACTIVITY",
    "STATUS",
];
function fail(string $s): never
{
    throw new RuntimeException($s);
}
function emit(string $s): void
{
    echo $s, "\n";
}
function nameOK(string $s): bool
{
    return (bool) preg_match("/\A[a-z][a-z0-9_]{0,15}\z/", $s);
}
function numberOK(string $s): bool
{
    return (bool) preg_match("/\A(?:0|[1-9][0-9]{0,8})\z/", $s);
}
function parseNumber(string $s, bool $positive = false): int
{
    if (!numberOK($s) || ($positive && $s === "0")) {
        fail("bad number " . $s);
    }
    return (int) $s;
}
function parseValue(string $s): string
{
    if (!in_array($s, ["0", "1", "X"], true)) {
        fail("bad value " . $s);
    }
    return $s;
}
function bits(int $r, int $n): string
{
    $s = "";
    for ($i = 0; $i < $n; $i++) {
        $s .= ($r >> ($n - 1 - $i)) & 1;
    }
    return $s;
}
function logic(string $kind, array $a): string
{
    $y = $a[0];
    if ($kind === "AND" || $kind === "NAND") {
        $y = in_array("0", $a, true) ? "0" : (in_array("X", $a, true) ? "X" : "1");
    } elseif ($kind === "OR" || $kind === "NOR") {
        $y = in_array("1", $a, true) ? "1" : (in_array("X", $a, true) ? "X" : "0");
    } elseif ($kind === "XOR" || $kind === "XNOR") {
        $y = in_array("X", $a, true) ? "X" : (string) (count(array_keys($a, "1", true)) % 2);
    } elseif ($kind === "MUX2") {
        $y = $a[0] === "X" ? ($a[1] === $a[2] ? $a[1] : "X") : $a[$a[0] === "0" ? 1 : 2];
    }
    return in_array($kind, ["NAND", "NOR", "XNOR", "NOT"], true)
        ? ["0" => "1", "1" => "0", "X" => "X"][$y]
        : $y;
}
class Gate
{
    public function __construct(
        public string $name,
        public string $kind,
        public array $inputs,
        public string $output,
        public int $delay,
    ) {}
}
class Instance
{
    public function __construct(
        public string $name,
        public Mod $module,
        public array $connections,
    ) {}
}
class Mod
{
    public function __construct(
        public string $name,
        public array $inputs,
        public array $outputs,
        public array $body,
    ) {}
}
class Circuit
{
    public string $name;
    public array $inputs,
        $outputs,
        $signals,
        $gates = [],
        $driver = [],
        $readers = [],
        $flops = [],
        $order = [];
    public bool $loop;
    public function __construct(Mod $m)
    {
        $this->name = $m->name;
        $this->inputs = $m->inputs;
        $this->outputs = $m->outputs;
        $this->expand($m, "", []);
        $this->signals = array_merge($this->inputs, array_map(fn($g) => $g->output, $this->gates));
        foreach ($this->signals as $s) {
            $this->readers[$s] = [];
        }
        foreach ($this->gates as $i => $g) {
            $this->driver[$g->output] = $i;
            if ($g->kind === "DFF") {
                $this->flops[] = $i;
            }
            foreach (array_unique($g->inputs) as $s) {
                $this->readers[$s][] = $i;
            }
        }
        $waiting = [];
        $ready = [];
        foreach ($this->gates as $i => $g) {
            if ($g->kind === "DFF") {
                continue;
            }
            $n = 0;
            foreach (array_unique($g->inputs) as $s) {
                if (isset($this->driver[$s]) && $this->gates[$this->driver[$s]]->kind !== "DFF") {
                    $n++;
                }
            }
            $waiting[$i] = $n;
            if ($n === 0) {
                $ready[] = $i;
            }
        }
        while ($ready) {
            $i = array_pop($ready);
            $this->order[] = $i;
            foreach ($this->readers[$this->gates[$i]->output] as $r) {
                if ($this->gates[$r]->kind !== "DFF") {
                    if (--$waiting[$r] === 0) {
                        $ready[] = $r;
                    }
                }
            }
        }
        $this->loop = count($this->order) !== count($waiting);
    }
    private function expand(Mod $m, string $prefix, array $ports): void
    {
        $actual = fn($s) => $ports[$s] ?? $prefix . $s;
        foreach ($m->body as $x) {
            if ($x instanceof Gate) {
                $this->gates[] = new Gate(
                    $prefix . $x->name,
                    $x->kind,
                    array_map($actual, $x->inputs),
                    $actual($x->output),
                    $x->delay,
                );
            } else {
                $mapping = [];
                foreach ($x->connections as $p => $s) {
                    $mapping[$p] = $actual($s);
                }
                $this->expand($x->module, $prefix . $x->name . ".", $mapping);
            }
        }
    }
    public function combinational(): void
    {
        if ($this->flops) {
            fail($this->name . " is not combinational");
        }
        if ($this->loop) {
            fail($this->name . " has a combinational loop");
        }
        if (count($this->inputs) > 8) {
            fail("too many inputs " . count($this->inputs));
        }
    }
    public function evaluate(string $b, string $stuck = "", string $v = "X"): string
    {
        $values = [];
        foreach ($this->inputs as $i => $s) {
            $values[$s] = $s === $stuck ? $v : $b[$i];
        }
        foreach ($this->order as $i) {
            $g = $this->gates[$i];
            $values[$g->output] =
                $g->output === $stuck
                    ? $v
                    : logic($g->kind, array_map(fn($s) => $values[$s], $g->inputs));
        }
        return implode("", array_map(fn($s) => $values[$s], $this->outputs));
    }
    public function arrivals(bool $period): array
    {
        $late = [];
        $early = [];
        $prev = [];
        if ($period) {
            foreach ($this->flops as $i) {
                $g = $this->gates[$i];
                $late[$g->output] = $early[$g->output] = $g->delay;
            };
        } else {
            foreach ($this->inputs as $s) {
                $late[$s] = $early[$s] = 0;
            };
        }
        foreach ($this->order as $i) {
            $g = $this->gates[$i];
            $a = array_values(array_filter($g->inputs, fn($s) => isset($late[$s])));
            if (!$a) {
                continue;
            }
            $best = $a[0];
            foreach ($a as $s) {
                if ($late[$s] > $late[$best]) {
                    $best = $s;
                }
            }
            $late[$g->output] = $late[$best] + $g->delay;
            $early[$g->output] = min(array_map(fn($s) => $early[$s], $a)) + $g->delay;
            $prev[$g->output] = $best;
        }
        return [$late, $early, $prev];
    }
}
class Simulation
{
    public array $values = [],
        $watch = [],
        $history = [];
    public int $time = 0,
        $sequence = 0,
        $processed = 0;
    public bool $halted = false;
    public SplPriorityQueue $queue;
    public function __construct(public Circuit $c)
    {
        $this->reset();
    }
    public function reset(): void
    {
        $this->values = [];
        $this->history = [];
        foreach ($this->c->signals as $s) {
            $this->values[$s] = "X";
            $this->history[$s] = [];
        }
        $this->time = $this->sequence = $this->processed = 0;
        $this->queue = new SplPriorityQueue();
        $this->queue->setExtractFlags(SplPriorityQueue::EXTR_DATA);
        $this->halted = false;
    }
    public function schedule(int $t, string $s, string $v): void
    {
        $this->queue->insert([$t, $s, $v], [-$t, -$this->sequence++]);
    }
    public function describe(array $a): array
    {
        return array_map(fn($s) => $s . "=" . $this->values[$s], $a);
    }
    public function run(int $end): void
    {
        $total = 0;
        $glitches = 0;
        while (!$this->queue->isEmpty() && $this->queue->top()[0] < $end) {
            $t = $this->queue->top()[0];
            $original = [];
            $count = 0;
            while (!$this->queue->isEmpty() && $this->queue->top()[0] === $t) {
                if ($count === 1000) {
                    emit("halted: oscillation at time " . $t);
                    $this->queue = new SplPriorityQueue();
                    $this->time = $t;
                    $this->halted = true;
                    return;
                }
                [$_, $s, $v] = $this->queue->extract();
                $count++;
                $this->processed++;
                $old = $this->values[$s];
                if ($old === $v) {
                    continue;
                }
                if (!isset($original[$s])) {
                    $original[$s] = $old;
                }
                $this->values[$s] = $v;
                foreach ($this->c->readers[$s] as $i) {
                    $g = $this->c->gates[$i];
                    if ($g->kind !== "DFF") {
                        $this->schedule(
                            $t + $g->delay,
                            $g->output,
                            logic($g->kind, array_map(fn($x) => $this->values[$x], $g->inputs)),
                        );
                    } elseif ($s === $g->inputs[0] && $old === "0" && $v === "1") {
                        $this->schedule($t + $g->delay, $g->output, $this->values[$g->inputs[1]]);
                    }
                }
            }
            $total += $count;
            foreach ($original as $s => $v) {
                if ($this->values[$s] === $v) {
                    $glitches++;
                } else {
                    $this->history[$s][] = [$t, $this->values[$s]];
                }
            }
            foreach ($this->watch as $s) {
                if (isset($original[$s]) && $this->values[$s] !== $original[$s]) {
                    emit($t . " " . $s . " " . $this->values[$s]);
                }
            }
        }
        $this->time = $end;
        emit("run $end events $total glitches $glitches pending " . count($this->queue));
    }
}
class Simulator
{
    public array $modules = [];
    public ?Simulation $sim = null;
    public function lookup(string $s): Mod
    {
        if (!isset($this->modules[$s])) {
            fail("unknown module " . $s);
        }
        return $this->modules[$s];
    }
    public function signal(string $s): void
    {
        if (!isset($this->sim->values[$s])) {
            fail("unknown signal " . $s);
        }
    }
    public function input(string $s): void
    {
        if (!in_array($s, $this->sim->c->inputs, true)) {
            fail("not an input " . $s);
        }
    }
    public function time(string $s): int
    {
        $t = parseNumber($s);
        if ($t < $this->sim->time) {
            fail("time " . $t . " is in the past");
        }
        return $t;
    }
    public function define(int $header, array $lines): void
    {
        $line = $header;
        try {
            $w = explode(" ", $lines[0]);
            if (
                count($w) < 5 ||
                $w[2] !== "IN" ||
                count(array_keys(array_slice($w, 3), "OUT", true)) !== 1 ||
                end($w) === "OUT"
            ) {
                fail("bad module header");
            }
            $name = $w[1];
            if (!preg_match("/\A[A-Z][A-Z0-9_]{0,15}\z/", $name)) {
                fail("bad module name " . $name);
            }
            if (isset($this->modules[$name])) {
                fail("duplicate module " . $name);
            }
            $split = array_search("OUT", array_slice($w, 3), true) + 3;
            $ins = array_slice($w, 3, $split - 3);
            $outs = array_slice($w, $split + 1);
            $seen = [];
            foreach (array_merge($ins, $outs) as $p) {
                if (!nameOK($p)) {
                    fail("bad name " . $p);
                }
                if (isset($seen[$p])) {
                    fail("duplicate port " . $p);
                }
                $seen[$p] = true;
            }
            $driven = array_fill_keys($ins, true);
            $used = [];
            $body = [];
            $reads = [];
            $gates = 0;
            foreach (array_slice($lines, 1) as $i => $text) {
                $line = $header + $i + 1;
                $a = explode(" ", $text);
                $kind = $a[0];
                if (in_array($kind, TYPES, true)) {
                    if (
                        count($a) < 5 ||
                        $a[count($a) - 3] !== "->" ||
                        count(array_keys($a, "->", true)) !== 1
                    ) {
                        fail("bad gate syntax");
                    }
                    $n = $a[1];
                    if (!nameOK($n)) {
                        fail("bad name " . $n);
                    }
                    $inputs = array_slice($a, 2, count($a) - 5);
                    $output = $a[count($a) - 2];
                    $delay = $a[count($a) - 1];
                    $lo = in_array($kind, ["NOT", "BUF"], true) ? 1 : ($kind === "MUX2" ? 3 : 2);
                    $hi = array_search($kind, TYPES, true) < 6 ? 8 : $lo;
                    if (count($inputs) < $lo || count($inputs) > $hi) {
                        fail("bad input count " . count($inputs) . " for " . $kind);
                    }
                    foreach (array_merge($inputs, [$output]) as $s) {
                        if (!nameOK($s)) {
                            fail("bad name " . $s);
                        }
                    }
                    if (!numberOK($delay) || (int) $delay > 1000) {
                        fail("bad delay " . $delay);
                    }
                    if (isset($used[$n])) {
                        fail("duplicate name " . $n);
                    }
                    if (isset($driven[$output])) {
                        fail("multiple drivers for " . $output);
                    }
                    $used[$n] = $driven[$output] = true;
                    $body[] = new Gate($n, $kind, $inputs, $output, (int) $delay);
                    $gates++;
                    foreach ($inputs as $s) {
                        $reads[] = [$line, $s];
                    }
                } elseif ($kind === "INST") {
                    if (count($a) < 3) {
                        fail("bad instance syntax");
                    }
                    $n = $a[1];
                    if (!nameOK($n)) {
                        fail("bad name " . $n);
                    }
                    $m = $this->lookup($a[2]);
                    $connections = [];
                    foreach (array_slice($a, 3) as $word) {
                        $p = explode("=", $word);
                        if (count($p) !== 2 || $p[0] === "" || $p[1] === "") {
                            fail("bad connection " . $word);
                        }
                        [$port, $s] = $p;
                        if (
                            !in_array($port, $m->inputs, true) &&
                            !in_array($port, $m->outputs, true)
                        ) {
                            fail("unknown port " . $port);
                        }
                        if (isset($connections[$port])) {
                            fail("duplicate connection " . $port);
                        }
                        if (!nameOK($s)) {
                            fail("bad name " . $s);
                        }
                        $connections[$port] = $s;
                    }
                    foreach ($m->inputs as $p) {
                        if (!isset($connections[$p])) {
                            fail("unconnected input " . $p);
                        }
                    }
                    if (isset($used[$n])) {
                        fail("duplicate name " . $n);
                    }
                    foreach ($connections as $p => $s) {
                        if (in_array($p, $m->outputs, true)) {
                            if (isset($driven[$s])) {
                                fail("multiple drivers for " . $s);
                            }
                            $driven[$s] = true;
                        }
                    }
                    $used[$n] = true;
                    $body[] = new Instance($n, $m, $connections);
                    foreach ($connections as $p => $s) {
                        if (in_array($p, $m->inputs, true)) {
                            $reads[] = [$line, $s];
                        }
                    }
                } else {
                    fail("unknown statement " . $kind);
                }
            }
            foreach ($outs as $s) {
                $reads[] = [$header, $s];
            }
            foreach ($reads as [$n, $s]) {
                if (!isset($driven[$s])) {
                    $line = $n;
                    fail("undriven signal " . $s);
                }
            }
            $this->modules[$name] = new Mod($name, $ins, $outs, $body);
            emit(
                "defined " .
                    $name .
                    " inputs " .
                    count($ins) .
                    " outputs " .
                    count($outs) .
                    " gates " .
                    $gates .
                    " instances " .
                    (count($body) - $gates),
            );
        } catch (RuntimeException $e) {
            emit("error: line " . $line . ": " . $e->getMessage());
        }
    }
    public function hierarchy(Mod $m, int $depth): void
    {
        foreach ($m->body as $x) {
            if ($x instanceof Instance) {
                emit(str_repeat("  ", $depth) . $x->name . " " . $x->module->name);
                $this->hierarchy($x->module, $depth + 1);
            }
        }
    }
    public function execute(int $line, array $w): void
    {
        try {
            $cmd = $w[0];
            $a = array_slice($w, 1);
            if (!array_key_exists($cmd, COUNTS)) {
                fail("unknown command " . $cmd);
            }
            $n = COUNTS[$cmd];
            if (
                count($a) < $n ||
                (!in_array($cmd, ["WATCH", "UNWATCH", "SHOW"], true) && count($a) !== $n)
            ) {
                fail("wrong argument count");
            }
            if (in_array($cmd, SIM, true) && $this->sim === null) {
                fail("no circuit");
            }
            $s = $this->sim;
            if (in_array($cmd, ["SET", "APPLY", "PULSE", "CLOCK", "RUN"], true) && $s->halted) {
                fail("simulation halted");
            }
            if ($cmd === "MODULES") {
                emit("modules " . count($this->modules));
                foreach ($this->modules as $m) {
                    emit(
                        $m->name .
                            " inputs " .
                            count($m->inputs) .
                            " outputs " .
                            count($m->outputs) .
                            " gates " .
                            count(new Circuit($m)->gates),
                    );
                }
                return;
            }
            if (
                in_array(
                    $cmd,
                    [
                        "BUILD",
                        "NETLIST",
                        "HIERARCHY",
                        "STATS",
                        "TRUTHTABLE",
                        "EQUIV",
                        "FAULTS",
                        "CRITICAL",
                        "PERIOD",
                    ],
                    true,
                )
            ) {
                $m = $this->lookup($a[0]);
                if ($cmd === "EQUIV") {
                    $m2 = $this->lookup($a[1]);
                }
                $c = new Circuit($m);
                switch ($cmd) {
                    case "BUILD":
                        $this->sim = new Simulation($c);
                        emit(
                            "built " .
                                $c->name .
                                " signals " .
                                count($c->signals) .
                                " gates " .
                                count($c->gates),
                        );
                        break;
                    case "NETLIST":
                        emit(
                            "netlist " .
                                $c->name .
                                " gates " .
                                count($c->gates) .
                                " signals " .
                                count($c->signals),
                        );
                        foreach ($c->gates as $g) {
                            emit(
                                $g->name .
                                    " " .
                                    $g->kind .
                                    " " .
                                    implode(" ", $g->inputs) .
                                    " -> " .
                                    $g->output .
                                    " " .
                                    $g->delay,
                            );
                        }
                        break;
                    case "HIERARCHY":
                        emit($m->name);
                        $this->hierarchy($m, 1);
                        break;
                    case "STATS":
                        $levels = [];
                        $depth = 0;
                        foreach ($c->order as $i) {
                            $g = $c->gates[$i];
                            $levels[$g->output] =
                                max(array_map(fn($x) => $levels[$x] ?? 0, $g->inputs)) + 1;
                            $depth = max($depth, $levels[$g->output]);
                        }
                        emit(
                            "stats " .
                                $c->name .
                                " gates " .
                                count($c->gates) .
                                " signals " .
                                count($c->signals) .
                                " depth " .
                                ($c->loop ? "-" : $depth),
                        );
                        $words = ["types"];
                        foreach (TYPES as $t) {
                            $n = count(array_filter($c->gates, fn($g) => $g->kind === $t));
                            if ($n) {
                                $words[] = $t;
                                $words[] = $n;
                            }
                        }
                        emit(implode(" ", $words));
                        $best = $c->signals[0];
                        foreach ($c->signals as $x) {
                            if (count($c->readers[$x]) > count($c->readers[$best])) {
                                $best = $x;
                            }
                        }
                        emit("max fanout " . $best . " " . count($c->readers[$best]));
                        break;
                    case "CRITICAL":
                    case "PERIOD":
                        $period = $cmd === "PERIOD";
                        if ($period && !$c->flops) {
                            fail($c->name . " has no flip-flops");
                        }
                        if ($c->loop) {
                            fail($c->name . " has a combinational loop");
                        }
                        [$late, $early, $prev] = $c->arrivals($period);
                        $ends = $period
                            ? array_map(fn($i) => $c->gates[$i]->inputs[1], $c->flops)
                            : $c->outputs;
                        $heading = $period
                            ? "flip-flops " . count($c->flops) . " period"
                            : "critical";
                        $best = null;
                        foreach ($ends as $x) {
                            if (!$period) {
                                emit(
                                    isset($late[$x])
                                        ? $x . " min " . $early[$x] . " max " . $late[$x]
                                        : $x . " unreachable",
                                );
                            }
                            if (isset($late[$x]) && ($best === null || $late[$x] > $late[$best])) {
                                $best = $x;
                            }
                        }
                        if ($best === null) {
                            emit($heading . " none");
                        } else {
                            $path = [$best];
                            $x = $best;
                            while (isset($prev[$x])) {
                                $x = $prev[$x];
                                $path[] = $x;
                            }
                            emit(
                                $heading .
                                    " " .
                                    $late[$best] .
                                    ": " .
                                    implode(" -> ", array_reverse($path)),
                            );
                        }
                        break;
                    default:
                        $c->combinational();
                        $rows = [];
                        $expected = [];
                        for ($r = 0; $r < 1 << count($c->inputs); $r++) {
                            $b = bits($r, count($c->inputs));
                            $rows[] = $b;
                            $expected[] = $c->evaluate($b);
                        }
                        if ($cmd === "TRUTHTABLE") {
                            emit(implode(" ", array_merge($c->inputs, ["|"], $c->outputs)));
                            foreach ($rows as $r => $b) {
                                emit(
                                    implode(
                                        " ",
                                        array_merge(str_split($b), ["|"], str_split($expected[$r])),
                                    ),
                                );
                            }
                        } elseif ($cmd === "EQUIV") {
                            $d = new Circuit($m2);
                            $d->combinational();
                            if (
                                count($c->inputs) !== count($d->inputs) ||
                                count($c->outputs) !== count($d->outputs)
                            ) {
                                fail("port mismatch");
                            }
                            $found = false;
                            foreach ($rows as $r => $b) {
                                $v = $d->evaluate($b);
                                if ($v !== $expected[$r]) {
                                    emit(
                                        "not equivalent at " .
                                            $b .
                                            ": " .
                                            $expected[$r] .
                                            " vs " .
                                            $v,
                                    );
                                    $found = true;
                                    break;
                                }
                            }
                            if (!$found) {
                                emit("equivalent");
                            }
                        } else {
                            $undetected = [];
                            $tests = [];
                            foreach ($c->signals as $x) {
                                foreach (["0", "1"] as $v) {
                                    $found = -1;
                                    foreach ($rows as $r => $b) {
                                        if ($c->evaluate($b, $x, $v) !== $expected[$r]) {
                                            $found = $r;
                                            break;
                                        }
                                    }
                                    if ($found < 0) {
                                        $undetected[] = $x . "/" . $v;
                                    } else {
                                        $tests[$found] = true;
                                    }
                                };
                            }
                            $total = 2 * count($c->signals);
                            emit("faults " . $total . " detected " . ($total - count($undetected)));
                            foreach ($undetected as $f) {
                                emit("undetected " . $f);
                            }
                            ksort($tests, SORT_NUMERIC);
                            $words = ["tests"];
                            foreach ($tests as $r => $_) {
                                $words[] = $rows[$r];
                            }
                            emit(implode(" ", $words));
                        }
                }
                return;
            }
            switch ($cmd) {
                case "RESET":
                    $s->reset();
                    emit("reset");
                    break;
                case "SET":
                    $t = $this->time($a[0]);
                    $this->input($a[1]);
                    parseValue($a[2]);
                    $s->schedule($t, $a[1], $a[2]);
                    emit("set " . $a[1] . " " . $a[2] . " at " . $t);
                    break;
                case "APPLY":
                    $t = $this->time($a[0]);
                    $b = $a[1];
                    if (strlen($b) !== count($s->c->inputs) || !preg_match("/\A[01X]*\z/", $b)) {
                        fail("bad vector " . $b);
                    }
                    foreach ($s->c->inputs as $i => $x) {
                        $s->schedule($t, $x, $b[$i]);
                    }
                    emit("apply " . $b . " at " . $t);
                    break;
                case "PULSE":
                case "CLOCK":
                    $this->input($a[0]);
                    $t = $this->time($a[1]);
                    $width = parseNumber($a[2], true);
                    if ($cmd === "PULSE") {
                        $s->schedule($t, $a[0], "1");
                        $s->schedule($t + $width, $a[0], "0");
                        emit("pulse " . $a[0] . " " . $t . " " . ($t + $width));
                    } else {
                        $count = parseNumber($a[3], true);
                        for ($i = 0; $i < $count; $i++) {
                            $s->schedule($t + $i * $width, $a[0], (string) ($i % 2));
                        }
                        emit(
                            "clock " .
                                $a[0] .
                                " events " .
                                $count .
                                " last " .
                                ($t + ($count - 1) * $width),
                        );
                    }
                    break;
                case "RUN":
                    $t = parseNumber($a[0]);
                    if ($t <= $s->time) {
                        fail("time " . $t . " is not after " . $s->time);
                    }
                    $s->run($t);
                    break;
                case "WATCH":
                case "UNWATCH":
                    $seen = [];
                    foreach ($a as $x) {
                        $this->signal($x);
                        $watched = in_array($x, $s->watch, true);
                        if (
                            $cmd === "WATCH"
                                ? $watched || isset($seen[$x])
                                : !$watched || isset($seen[$x])
                        ) {
                            fail(($cmd === "WATCH" ? "already watched " : "not watched ") . $x);
                        }
                        $seen[$x] = true;
                    }
                    $s->watch =
                        $cmd === "WATCH"
                            ? array_merge($s->watch, $a)
                            : array_values(array_diff($s->watch, $a));
                    emit("watching " . ($s->watch ? implode(" ", $s->watch) : "nothing"));
                    break;
                case "SHOW":
                    foreach ($a as $x) {
                        $this->signal($x);
                    }
                    emit(
                        implode(
                            " ",
                            $a
                                ? $s->describe($a)
                                : array_merge(
                                    $s->describe($s->c->inputs),
                                    ["|"],
                                    $s->describe($s->c->outputs),
                                ),
                        ),
                    );
                    break;
                case "CHECK":
                    $this->signal($a[0]);
                    parseValue($a[1]);
                    emit(
                        "check " .
                            $a[0] .
                            "=" .
                            $a[1] .
                            " " .
                            ($s->values[$a[0]] === $a[1]
                                ? "ok"
                                : "failed (" . $s->values[$a[0]] . ")"),
                    );
                    break;
                case "PROBE":
                    $x = $a[0];
                    $this->signal($x);
                    $text = "input";
                    if (isset($s->c->driver[$x])) {
                        $g = $s->c->gates[$s->c->driver[$x]];
                        $text =
                            $g->name .
                            " " .
                            $g->kind .
                            " " .
                            implode(" ", $s->describe($g->inputs)) .
                            " delay " .
                            $g->delay;
                    }
                    emit($x . "=" . $s->values[$x] . " driven by " . $text);
                    $readers = $s->c->readers[$x];
                    emit(
                        implode(
                            " ",
                            array_merge(
                                ["fanout", count($readers)],
                                array_map(fn($i) => $s->c->gates[$i]->name, $readers),
                            ),
                        ),
                    );
                    break;
                case "WAVE":
                    $start = parseNumber($a[0]);
                    $end = parseNumber($a[1]);
                    if (!($start < $end && $end <= $s->time)) {
                        fail("bad range $start $end");
                    }
                    if (!$s->watch) {
                        fail("nothing watched");
                    }
                    foreach ($s->watch as $x) {
                        $h = $s->history[$x];
                        $i = 0;
                        $v = "X";
                        $wave = "";
                        for ($t = $start; $t < $end; $t++) {
                            while ($i < count($h) && $h[$i][0] <= $t) {
                                $v = $h[$i++][1];
                            }
                            $wave .= $v;
                        }
                        emit($x . " " . $wave);
                    }
                    break;
                case "HISTORY":
                    $x = $a[0];
                    $this->signal($x);
                    $h = $s->history[$x];
                    emit(
                        implode(
                            " ",
                            array_merge(
                                ["history", $x, "changes", count($h)],
                                array_map(fn($v) => $v[0] . ":" . $v[1], $h),
                            ),
                        ),
                    );
                    break;
                case "ACTIVITY":
                    $k = parseNumber($a[0], true);
                    $ranked = $s->c->signals;
                    usort(
                        $ranked,
                        fn($x, $y) => count($s->history[$y]) <=> count($s->history[$x]) ?:
                        strcmp($x, $y),
                    );
                    foreach (array_slice($ranked, 0, $k) as $x) {
                        emit($x . " " . count($s->history[$x]));
                    }
                    break;
                case "STATUS":
                    emit(
                        "circuit " .
                            $s->c->name .
                            " time " .
                            $s->time .
                            " pending " .
                            count($s->queue) .
                            " events " .
                            $s->processed .
                            " halted " .
                            ($s->halted ? "yes" : "no"),
                    );
                    $v = array_count_values($s->values);
                    emit(
                        "values 0:" .
                            ($v["0"] ?? 0) .
                            " 1:" .
                            ($v["1"] ?? 0) .
                            " X:" .
                            ($v["X"] ?? 0),
                    );
                    break;
            }
        } catch (RuntimeException $e) {
            emit("error: line " . $line . ": " . $e->getMessage());
        }
    }
}
$lines = file("php://stdin", FILE_IGNORE_NEW_LINES);
$simulator = new Simulator();
for ($i = 0; $i < count($lines) && $lines[$i] !== "END"; $i++) {
    $w = explode(" ", $lines[$i]);
    if ($w[0] === "MODULE") {
        $end = $i + 1;
        while ($lines[$end] !== "ENDMODULE") {
            $end++;
        }
        $simulator->define($i + 1, array_slice($lines, $i, $end - $i));
        $i = $end;
    } else {
        $simulator->execute($i + 1, $w);
    }
}
