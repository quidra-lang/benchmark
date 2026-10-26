<?php
$kinds = ["I", "O", "T", "S", "Z", "J", "L"];
$movements = ["L", "R", "LL", "RR", "SD", "DD", "CW", "CCW"];
$operationNames = array_merge($movements, ["HD", "LOCK", "HOLD"]);
$commandNames = explode(
    " ",
    "NEW PRINT NEXT PREVIEW STATUS ANALYZE ROW GARBAGE ATTACK TICK UNDO SAVE LOAD SPINS HINT AUTO",
);
$afterEnd = ["PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "LOAD"];
$states = ["0", "R", "2", "L"];
$clearNames = [
    "SINGLE",
    "DOUBLE",
    "TRIPLE",
    "TETRIS",
    "TSPIN_MINI",
    "TSPIN_MINI_SINGLE",
    "TSPIN_MINI_DOUBLE",
    "TSPIN",
    "TSPIN_SINGLE",
    "TSPIN_DOUBLE",
    "TSPIN_TRIPLE",
];
$frames = [
    "I" => ["....", "####", "....", "...."],
    "O" => ["##", "##"],
    "T" => [".#.", "###", "..."],
    "S" => [".##", "##.", "..."],
    "Z" => ["##.", ".##", "..."],
    "J" => ["#..", "###", "..."],
    "L" => ["..#", "###", "..."],
];
$shapes = [];
foreach ($kinds as $kind) {
    $blocks = [];
    foreach ($frames[$kind] as $j => $line) {
        for ($i = 0; $i < strlen($line); $i++) {
            if ($line[$i] === "#") {
                $blocks[] = [$i, $j];
            }
        };
    }
    $shapes[$kind] = [$blocks];
    for ($s = 1; $s < 4; $s++) {
        $blocks = array_map(fn($b) => [count($frames[$kind]) - 1 - $b[1], $b[0]], $blocks);
        $shapes[$kind][] = $blocks;
    }
}
$ordinaryKicks = [
    "01" => [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    "10" => [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    "12" => [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    "21" => [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    "23" => [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    "32" => [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    "30" => [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    "03" => [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
];
$iKicks = [
    "01" => [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    "10" => [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    "12" => [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
    "21" => [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    "23" => [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    "32" => [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    "30" => [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    "03" => [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
];
$output = [];
function emit(string $line): void
{
    global $output;
    $output[] = $line;
}
function seedStep(int $value): int
{
    return ($value * 48271) % 2147483647;
}
function startPosition(string $kind): array
{
    return [0, $kind === "O" ? 5 : 4, 22];
}
function positionKey(array $p): string
{
    return implode(",", $p);
}
function cells(string $kind, array $p): array
{
    global $shapes;
    return array_map(fn($c) => [$p[1] + $c[0], $p[2] - $c[1]], $shapes[$kind][$p[0]]);
}
function lowest(string $kind, array $p): int
{
    return min(array_column(cells($kind, $p), 1));
}
function bag(int $seed): array
{
    global $kinds;
    $pieces = $kinds;
    for ($i = 6; $i >= 1; $i--) {
        $seed = seedStep($seed);
        $j = $seed % ($i + 1);
        [$pieces[$i], $pieces[$j]] = [$pieces[$j], $pieces[$i]];
    }
    return [$seed, $pieces];
}
function fits(array $board, string $kind, array $p): bool
{
    foreach (cells($kind, $p) as [$c, $r]) {
        if ($c < 1 || $c > 10 || $r < 1 || $r > 22 || ($board[$r - 1] & (1 << ($c - 1))) !== 0) {
            return false;
        }
    }
    return true;
}
function movePiece(array $board, string $kind, array $p, string $operation): ?array
{
    global $iKicks, $ordinaryKicks;
    [$s, $x, $y] = $p;
    if ($operation === "CW" || $operation === "CCW") {
        $b = ($s + ($operation === "CW" ? 1 : 3)) % 4;
        $offsets = $kind === "O" ? [[0, 0]] : ($kind === "I" ? $iKicks : $ordinaryKicks)["$s$b"];
        foreach ($offsets as $i => $delta) {
            $q = [$b, $x + $delta[0], $y + $delta[1]];
            if (fits($board, $kind, $q)) {
                return ["p" => $q, "test" => $i + 1];
            }
        }
        return null;
    }
    $dx =
        $operation === "L" || $operation === "LL"
            ? -1
            : ($operation === "R" || $operation === "RR"
                ? 1
                : 0);
    $dy = $dx === 0 ? -1 : 0;
    $repeat = in_array($operation, ["LL", "RR", "DD"], true);
    $position = $p;
    $changed = false;
    do {
        $q = [$s, $position[1] + $dx, $position[2] + $dy];
        if (!fits($board, $kind, $q)) {
            break;
        }
        $position = $q;
        $changed = true;
    } while ($repeat);
    return $changed ? ["p" => $position, "test" => 0] : null;
}
function landing(array $board, string $kind, array $p): array
{
    return movePiece($board, $kind, $p, "DD")["p"] ?? $p;
}
function placed(array $board, string $kind, array $p): array
{
    foreach (cells($kind, $p) as [$c, $r]) {
        $board[$r - 1] |= 1 << ($c - 1);
    }
    $remaining = array_values(array_filter($board, fn($row) => $row !== 1023));
    $lines = 22 - count($remaining);
    return ["board" => array_merge($remaining, array_fill(0, $lines, 0)), "lines" => $lines];
}
function evaluateWell(array $board, int $cleared): array
{
    $heights = array_fill(0, 10, 0);
    $holes = 0;
    $bumpiness = 0;
    for ($c = 0; $c < 10; $c++) {
        for ($r = 21; $r >= 0; $r--) {
            if (($board[$r] & (1 << $c)) !== 0) {
                $heights[$c] = $r + 1;
                break;
            }
        }
        for ($r = 0; $r < $heights[$c]; $r++) {
            if (($board[$r] & (1 << $c)) === 0) {
                $holes++;
            }
        }
    }
    for ($c = 0; $c < 9; $c++) {
        $bumpiness += abs($heights[$c] - $heights[$c + 1]);
    }
    return [
        "heights" => $heights,
        "holes" => $holes,
        "bumpiness" => $bumpiness,
        "value" => 76 * $cleared - 51 * array_sum($heights) - 36 * $holes - 18 * $bumpiness,
    ];
}
function routes(array $board, string $kind, array $start, ?array $target = null): array
{
    global $movements;
    if (!fits($board, $kind, $start)) {
        return [];
    }
    $entries = [["position" => $start, "keys" => []]];
    $seen = [positionKey($start) => true];
    for ($i = 0; $i < count($entries); $i++) {
        $entry = $entries[$i];
        if ($target !== null && landing($board, $kind, $entry["position"]) === $target) {
            return [$entry];
        }
        foreach ($movements as $op) {
            $r = movePiece($board, $kind, $entry["position"], $op);
            if ($r === null) {
                continue;
            }
            $key = positionKey($r["p"]);
            if (isset($seen[$key])) {
                continue;
            }
            $seen[$key] = true;
            $entries[] = ["position" => $r["p"], "keys" => array_merge($entry["keys"], [$op])];
        }
    }
    return $target !== null ? [] : $entries;
}
function tSpin(array $board, array $p, int $test): string
{
    [$s, $x, $y] = $p;
    $corners = [[$x, $y], [$x + 2, $y], [$x + 2, $y - 2], [$x, $y - 2]];
    $blocked = [];
    foreach ($corners as [$c, $r]) {
        $blocked[] =
            $c < 1 || $c > 10 || $r < 1 || $r > 22 || ($board[$r - 1] & (1 << ($c - 1))) !== 0;
    }
    if (count(array_filter($blocked)) < 3) {
        return "";
    }
    return ($blocked[$s] && $blocked[($s + 1) % 4]) || $test === 5 ? "full" : "mini";
}
function clearInfo(string $spin, int $lines): array
{
    if ($spin === "full") {
        return [
            "name" => ["TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE"][$lines],
            "points" => [400, 800, 1200, 1600][$lines],
            "sent" => [0, 2, 4, 6][$lines],
        ];
    }
    if ($spin === "mini") {
        return [
            "name" => ["TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE"][$lines],
            "points" => [100, 200, 400][$lines],
            "sent" => [0, 0, 1][$lines],
        ];
    }
    return [
        "name" => ["", "SINGLE", "DOUBLE", "TRIPLE", "TETRIS"][$lines],
        "points" => [0, 100, 300, 500, 800][$lines],
        "sent" => [0, 0, 1, 2, 4][$lines],
    ];
}
class GameOver extends Exception {}
class Game
{
    public array $s;
    public array $history = [];
    public array $start = [];
    public array $saves = [];
    public function __construct(public int $number, int $seed, int $level)
    {
        global $kinds, $clearNames;
        $this->s = [
            "board" => array_fill(0, 22, 0),
            "random" => $seed,
            "queue" => [],
            "hold" => null,
            "usedHold" => false,
            "kind" => "I",
            "position" => startPosition("I"),
            "last" => "none",
            "test" => 0,
            "keys" => 0,
            "drop" => 0,
            "fall" => 0,
            "ground" => 0,
            "resets" => 0,
            "lowest" => 0,
            "initialLevel" => $level,
            "level" => $level,
            "score" => 0,
            "lines" => 0,
            "pieces" => 0,
            "streak" => 0,
            "chain" => 0,
            "pending" => [],
            "ended" => false,
            "stats" => [
                "drops" => 0,
                "holds" => 0,
                "operations" => 0,
                "faults" => 0,
                "perfect" => 0,
                "sent" => 0,
                "cancelled" => 0,
                "received" => 0,
                "combo" => 0,
                "chain" => 0,
                "kinds" => array_fill_keys($kinds, 0),
                "clears" => array_fill_keys($clearNames, 0),
            ],
        ];
        $this->addBag();
        $this->spawnPiece($this->takeNext());
        $this->start = $this->s;
    }
    private function addBag(): void
    {
        [$this->s["random"], $pieces] = bag($this->s["random"]);
        array_push($this->s["queue"], ...$pieces);
    }
    private function takeNext(): string
    {
        $kind = array_shift($this->s["queue"]);
        if (count($this->s["queue"]) < 5) {
            $this->addBag();
        }
        return $kind;
    }
    private function spawnPiece(string $kind): void
    {
        $s = &$this->s;
        $s["kind"] = $kind;
        $s["position"] = startPosition($kind);
        $s["last"] = "none";
        $s["test"] = 0;
        $s["keys"] = 0;
        $s["drop"] = 0;
        $s["fall"] = 0;
        $s["ground"] = 0;
        $s["resets"] = 0;
        $s["lowest"] = lowest($kind, $s["position"]);
        if (!fits($s["board"], $kind, $s["position"])) {
            $this->over("block out");
        }
    }
    private function over(string $reason): never
    {
        emit("game over " . $reason);
        $this->summary();
        $this->s["ended"] = true;
        throw new GameOver();
    }
    private function updatePosition(array $position, string $last, int $test = 0): void
    {
        $s = &$this->s;
        $s["position"] = $position;
        $s["last"] = $last;
        $s["test"] = $test;
        $row = lowest($s["kind"], $position);
        if ($row < $s["lowest"]) {
            $s["lowest"] = $row;
            $s["resets"] = 0;
        }
    }
    private function grounded(): bool
    {
        return movePiece($this->s["board"], $this->s["kind"], $this->s["position"], "SD") === null;
    }
    private function drops(int $points): void
    {
        $this->s["score"] += $points;
        $this->s["drop"] += $points;
        $this->s["stats"]["drops"] += $points;
    }
    private function insertGarbage(int $rows, int $hole): void
    {
        $s = &$this->s;
        foreach (array_slice($s["board"], 22 - $rows) as $row) {
            if ($row !== 0) {
                $this->over("top out");
            }
        }
        $s["board"] = array_merge(
            array_fill(0, $rows, 1023 ^ (1 << ($hole - 1))),
            array_slice($s["board"], 0, 22 - $rows),
        );
    }
    public function operation(string $op): void
    {
        global $movements;
        $s = &$this->s;
        if (in_array($op, $movements, true)) {
            $s["keys"]++;
            $r = movePiece($s["board"], $s["kind"], $s["position"], $op);
            if ($r === null) {
                emit("fail " . $op);
                return;
            }
            if ($op === "SD" || $op === "DD") {
                $this->drops($s["position"][2] - $r["p"][2]);
                $this->updatePosition($r["p"], "move");
                $s["fall"] = 0;
                $s["ground"] = 0;
            } else {
                $this->updatePosition(
                    $r["p"],
                    $op === "CW" || $op === "CCW" ? "rotation" : "move",
                    $r["test"],
                );
                if ($s["ground"] > 0 && $s["resets"] < 15) {
                    $s["ground"] = 0;
                    $s["resets"]++;
                }
            }
            return;
        }
        if ($op === "HD") {
            $p = landing($s["board"], $s["kind"], $s["position"]);
            $rows = $s["position"][2] - $p[2];
            $this->drops(2 * $rows);
            if ($rows > 0) {
                $this->updatePosition($p, "move");
            }
            $this->lock();
            return;
        }
        if ($op === "LOCK") {
            if ($this->grounded()) {
                $this->lock();
            } else {
                emit("fail LOCK");
            }
            return;
        }
        if ($s["usedHold"]) {
            emit("fail HOLD");
            return;
        }
        $s["usedHold"] = true;
        $s["stats"]["holds"]++;
        $previous = $s["hold"];
        $s["hold"] = $s["kind"];
        $this->spawnPiece($previous ?? $this->takeNext());
    }
    private function tick(): void
    {
        $s = &$this->s;
        if (!$this->grounded()) {
            $s["ground"] = 0;
            $s["fall"]++;
            $interval =
                $s["level"] >= 13
                    ? 1
                    : [60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2][$s["level"] - 1];
            if ($s["fall"] >= $interval) {
                $this->updatePosition(
                    [$s["position"][0], $s["position"][1], $s["position"][2] - 1],
                    "move",
                );
                $s["fall"] = 0;
            }
        } else {
            $s["ground"]++;
            if ($s["ground"] >= 30) {
                $this->lock();
            }
        }
    }
    private function lock(): void
    {
        global $states;
        $s = &$this->s;
        $kind = $s["kind"];
        $position = $s["position"];
        $oldCells = cells($kind, $position);
        $routes = routes($s["board"], $kind, startPosition($kind), $position);
        $shortest = $routes[0] ?? null;
        $spin =
            $kind === "T" && $s["last"] === "rotation"
                ? tSpin($s["board"], $position, $s["test"])
                : "";
        $placed = placed($s["board"], $kind, $position);
        $n = $placed["lines"];
        $s["board"] = $placed["board"];
        $this->history[] = $this->start;
        $s["pieces"]++;
        $s["stats"]["kinds"][$kind]++;
        $s["stats"]["operations"] += $s["keys"];
        $info = clearInfo($spin, $n);
        $level = $s["level"];
        $points = $info["points"] * $level;
        $sent = $info["sent"];
        $back = false;
        if ($n > 0) {
            $s["streak"]++;
            if ($n === 4 || $spin !== "") {
                $s["chain"]++;
                $back = $s["chain"] >= 2;
            } else {
                $s["chain"] = 0;
            }
        } else {
            $s["streak"] = 0;
        }
        if ($back) {
            $points = intdiv($points * 3, 2);
            $sent++;
        }
        $combo = $s["streak"] - 1;
        $comboPoints = $combo >= 1 ? 50 * $combo * $level : 0;
        if ($combo >= 0) {
            $sent += [0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5][min($combo, 10)];
        }
        $perfect = $n > 0 && count(array_filter($s["board"], fn($row) => $row !== 0)) === 0;
        $perfectPoints = $perfect
            ? ($n === 4 && $back ? 3200 : [800, 1200, 1800, 2000][$n - 1]) * $level
            : 0;
        if ($perfect) {
            $sent += 10;
            $s["stats"]["perfect"]++;
        }
        $gained = $points + $comboPoints + $perfectPoints;
        $s["score"] += $gained;
        $s["lines"] += $n;
        $s["stats"]["sent"] += $sent;
        $s["stats"]["combo"] = max($s["stats"]["combo"], $combo);
        $s["stats"]["chain"] = max($s["stats"]["chain"], $s["chain"]);
        emit(
            "lock " .
                $s["pieces"] .
                " " .
                $kind .
                " " .
                $states[$position[0]] .
                " " .
                $position[1] .
                " " .
                $position[2] .
                " keys " .
                $s["keys"] .
                " " .
                ($shortest === null ? "-" : count($shortest["keys"])) .
                " drop " .
                $s["drop"] .
                " lines " .
                $n .
                " sent " .
                $sent .
                " +" .
                $gained .
                " total " .
                $s["score"],
        );
        if ($shortest !== null && $s["keys"] > count($shortest["keys"])) {
            $s["stats"]["faults"]++;
            emit(
                "finesse " . (count($shortest["keys"]) ? implode(" ", $shortest["keys"]) : "none"),
            );
        }
        if ($info["name"] !== "") {
            $s["stats"]["clears"][$info["name"]]++;
            emit(
                "clear " .
                    $info["name"] .
                    " " .
                    $points .
                    ($back ? " b2b" : "") .
                    ($combo >= 1 ? " combo " . $combo . " " . $comboPoints : "") .
                    ($perfect ? " perfect " . $perfectPoints : ""),
            );
        }
        $nextLevel = $s["initialLevel"] + intdiv($s["lines"], 10);
        if ($nextLevel > $level) {
            $s["level"] = $nextLevel;
            emit("level " . $s["level"]);
        }
        $lockOut = true;
        foreach ($oldCells as [$c, $r]) {
            if ($r < 21) {
                $lockOut = false;
                break;
            }
        }
        if ($lockOut) {
            $this->over("lock out");
        }
        $cancelled = min($sent, array_sum($s["pending"]));
        $remaining = $cancelled;
        while ($remaining > 0) {
            $count = min($remaining, $s["pending"][0]);
            $remaining -= $count;
            $s["pending"][0] -= $count;
            if ($s["pending"][0] === 0) {
                array_shift($s["pending"]);
            }
        }
        if ($cancelled > 0) {
            $s["stats"]["cancelled"] += $cancelled;
            emit("cancel " . $cancelled . " pending " . array_sum($s["pending"]));
        }
        if ($n === 0) {
            $risen = 0;
            while (count($s["pending"]) > 0 && $risen < 8) {
                $count = min($s["pending"][0], 8 - $risen);
                $s["random"] = seedStep($s["random"]);
                $hole = ($s["random"] % 10) + 1;
                $this->insertGarbage($count, $hole);
                $s["stats"]["received"] += $count;
                $risen += $count;
                $s["pending"][0] -= $count;
                if ($s["pending"][0] === 0) {
                    array_shift($s["pending"]);
                }
                emit("rise " . $count . " hole " . $hole . " pending " . array_sum($s["pending"]));
            }
        }
        $s["usedHold"] = false;
        $this->spawnPiece($this->takeNext());
        $this->start = $s;
    }
    private function candidates(string $kind, array $start, array $prefix): array
    {
        $s = &$this->s;
        $result = [];
        $seen = [];
        foreach ([[], ["CW"], ["CW", "CW"], ["CCW"]] as $turns) {
            $p = $start;
            $valid = true;
            foreach ($turns as $turn) {
                $step = movePiece($s["board"], $kind, $p, $turn);
                if ($step === null) {
                    $valid = false;
                    break;
                }
                $p = $step["p"];
            }
            if (!$valid) {
                continue;
            }
            $add = function (array $q, array $shifts) use (
                &$result,
                &$seen,
                $s,
                $kind,
                $prefix,
                $turns,
            ): void {
                $landed = landing($s["board"], $kind, $q);
                $indexes = [];
                foreach (cells($kind, $landed) as [$c, $r]) {
                    $indexes[] = ($r - 1) * 10 + $c - 1;
                }
                sort($indexes);
                $key = implode(",", $indexes);
                if (isset($seen[$key])) {
                    return;
                }
                $seen[$key] = true;
                $r = placed($s["board"], $kind, $landed);
                $result[] = [
                    "value" => evaluateWell($r["board"], $r["lines"])["value"],
                    "kind" => $kind,
                    "keys" => array_merge($prefix, $turns, $shifts, ["HD"]),
                ];
            };
            $add($p, []);
            foreach (["L", "R"] as $direction) {
                $q = $p;
                $shifts = [];
                while (true) {
                    $step = movePiece($s["board"], $kind, $q, $direction);
                    if ($step === null) {
                        break;
                    }
                    $q = $step["p"];
                    $shifts[] = $direction;
                    $add($q, $shifts);
                }
            }
        }
        return $result;
    }
    private function ranked(): array
    {
        $s = &$this->s;
        $result = $this->candidates($s["kind"], $s["position"], []);
        $held = $s["hold"] ?? $s["queue"][0];
        if (!$s["usedHold"] && fits($s["board"], $held, startPosition($held))) {
            $result = array_merge(
                $result,
                $this->candidates($held, startPosition($held), ["HOLD"]),
            );
        }
        foreach ($result as $i => &$candidate) {
            $candidate["order"] = $i;
        }
        unset($candidate);
        usort($result, fn($a, $b) => $b["value"] <=> $a["value"] ?: $a["order"] <=> $b["order"]);
        return $result;
    }
    private function spins(): void
    {
        global $states;
        $s = &$this->s;
        if ($s["kind"] !== "T") {
            emit("spins 0");
            return;
        }
        $found = [];
        foreach (routes($s["board"], $s["kind"], $s["position"]) as $route) {
            foreach (["CW", "CCW"] as $turn) {
                $r = movePiece($s["board"], "T", $route["position"], $turn);
                if ($r === null || movePiece($s["board"], "T", $r["p"], "SD") !== null) {
                    continue;
                }
                $spin = tSpin($s["board"], $r["p"], $r["test"]);
                $key = positionKey($r["p"]);
                if ($spin !== "" && (!isset($found[$key]) || $spin === "full")) {
                    $found[$key] = ["p" => $r["p"], "spin" => $spin];
                }
            };
        }
        $candidates = array_values($found);
        usort(
            $candidates,
            fn($a, $b) => $a["p"][2] <=> $b["p"][2] ?:
            $a["p"][1] <=> $b["p"][1] ?:
            $a["p"][0] <=> $b["p"][0],
        );
        foreach ($candidates as $candidate) {
            [$state, $x, $y] = $candidate["p"];
            $info = clearInfo(
                $candidate["spin"],
                placed($s["board"], "T", $candidate["p"])["lines"],
            );
            emit("spin " . $states[$state] . " " . $x . " " . $y . " " . $info["name"]);
        }
        emit("spins " . count($candidates));
    }
    public function summary(): void
    {
        global $kinds;
        $s = &$this->s;
        $a = $s["stats"];
        $c = $a["clears"];
        $ratio = fn($x, $y) => $y === 0
            ? "0.00"
            : sprintf("%d.%02d", intdiv(intdiv(100 * $x, $y), 100), intdiv(100 * $x, $y) % 100);
        emit(
            "summary game " .
                $this->number .
                " score " .
                $s["score"] .
                " level " .
                $s["level"] .
                " lines " .
                $s["lines"] .
                " pieces " .
                $s["pieces"],
        );
        emit(
            "clears single " .
                $c["SINGLE"] .
                " double " .
                $c["DOUBLE"] .
                " triple " .
                $c["TRIPLE"] .
                " tetris " .
                $c["TETRIS"] .
                " perfect " .
                $a["perfect"],
        );
        emit(
            "tspins mini " .
                $c["TSPIN_MINI"] .
                " mini_single " .
                $c["TSPIN_MINI_SINGLE"] .
                " mini_double " .
                $c["TSPIN_MINI_DOUBLE"] .
                " zero " .
                $c["TSPIN"] .
                " single " .
                $c["TSPIN_SINGLE"] .
                " double " .
                $c["TSPIN_DOUBLE"] .
                " triple " .
                $c["TSPIN_TRIPLE"],
        );
        $kindCounts = [];
        foreach ($kinds as $k) {
            $kindCounts[] = $k . " " . $a["kinds"][$k];
        }
        emit("pieces " . implode(" ", $kindCounts));
        emit(
            "best combo " .
                $a["combo"] .
                " chain " .
                $a["chain"] .
                " holds " .
                $a["holds"] .
                " drops " .
                $a["drops"] .
                " faults " .
                $a["faults"],
        );
        emit(
            "garbage sent " .
                $a["sent"] .
                " cancelled " .
                $a["cancelled"] .
                " received " .
                $a["received"],
        );
        emit(
            "rates app " .
                $ratio($a["sent"], $s["pieces"]) .
                " apl " .
                $ratio($a["sent"], $s["lines"]) .
                " kpp " .
                $ratio($a["operations"], $s["pieces"]),
        );
    }
    public function command(string $command, array $args): void
    {
        global $kinds, $states;
        $s = &$this->s;
        switch ($command) {
            case "PRINT":
                $current = [];
                $ghost = [];
                if (!$s["ended"]) {
                    foreach (cells($s["kind"], $s["position"]) as [$c, $r]) {
                        $current[$r * 10 + $c] = true;
                    }
                    foreach (
                        cells($s["kind"], landing($s["board"], $s["kind"], $s["position"]))
                        as [$c, $r]
                    ) {
                        $ghost[$r * 10 + $c] = true;
                    }
                }
                for ($r = 22; $r >= 1; $r--) {
                    $line = str_pad((string) $r, 2, " ", STR_PAD_LEFT) . " ";
                    for ($c = 1; $c <= 10; $c++) {
                        if ($s["board"][$r - 1] & (1 << ($c - 1))) {
                            $line .= "#";
                        } elseif (isset($current[$r * 10 + $c])) {
                            $line .= "@";
                        } elseif (isset($ghost[$r * 10 + $c])) {
                            $line .= "+";
                        } else {
                            $line .= ".";
                        }
                    }
                    emit($line);
                }
                break;
            case "NEXT":
                emit(
                    "hold " .
                        ($s["hold"] ?? "-") .
                        " next " .
                        implode("", array_slice($s["queue"], 0, 5)),
                );
                break;
            case "PREVIEW":
                $count = (int) $args[0];
                $queue = $s["queue"];
                $random = $s["random"];
                while (count($queue) < $count) {
                    [$random, $pieces] = bag($random);
                    array_push($queue, ...$pieces);
                }
                emit("preview " . implode("", array_slice($queue, 0, $count)));
                break;
            case "STATUS":
                emit(
                    "score " .
                        $s["score"] .
                        " level " .
                        $s["level"] .
                        " lines " .
                        $s["lines"] .
                        " pieces " .
                        $s["pieces"],
                );
                $piece = $s["ended"]
                    ? "-"
                    : $s["kind"] .
                        " " .
                        $states[$s["position"][0]] .
                        " " .
                        $s["position"][1] .
                        " " .
                        $s["position"][2];
                emit(
                    "piece " .
                        $piece .
                        " streak " .
                        $s["streak"] .
                        " chain " .
                        $s["chain"] .
                        " pending " .
                        array_sum($s["pending"]),
                );
                break;
            case "ANALYZE":
                $e = evaluateWell($s["board"], 0);
                emit("heights " . implode(" ", $e["heights"]));
                emit(
                    "holes " .
                        $e["holes"] .
                        " bumpiness " .
                        $e["bumpiness"] .
                        " value " .
                        $e["value"],
                );
                break;
            case "ROW":
                $r = (int) $args[0];
                $pattern = $args[1];
                $overlap = false;
                foreach (cells($s["kind"], $s["position"]) as [$c, $row]) {
                    if ($row === $r && $pattern[$c - 1] === "#") {
                        $overlap = true;
                    }
                }
                if ($overlap) {
                    emit("ERROR overlap");
                    break;
                }
                $mask = 0;
                for ($i = 0; $i < 10; $i++) {
                    if ($pattern[$i] === "#") {
                        $mask |= 1 << $i;
                    }
                }
                $s["board"][$r - 1] = $mask;
                emit("OK");
                break;
            case "GARBAGE":
                $count = (int) $args[0];
                $hole = (int) $args[1];
                $this->insertGarbage($count, $hole);
                for ($j = 0; $j <= $count; $j++) {
                    $p = [$s["position"][0], $s["position"][1], $s["position"][2] + $j];
                    if (fits($s["board"], $s["kind"], $p)) {
                        $s["position"] = $p;
                        emit("OK");
                        return;
                    }
                }
                $this->over("top out");
            case "ATTACK":
                $s["pending"][] = (int) $args[0];
                emit("pending " . array_sum($s["pending"]));
                break;
            case "TICK":
                for ($i = 0; $i < (int) $args[0]; $i++) {
                    $this->tick();
                }
                break;
            case "UNDO":
                if (!count($this->history)) {
                    emit("ERROR nothing to undo");
                } else {
                    $this->s = array_pop($this->history);
                    $this->start = $this->s;
                    emit("undo " . $this->s["pieces"] . " " . $this->s["kind"]);
                }
                break;
            case "SAVE":
                $this->saves[$args[0]] = [
                    "state" => $s,
                    "history" => $this->history,
                    "start" => $this->start,
                ];
                emit("OK");
                break;
            case "LOAD":
                if (!isset($this->saves[$args[0]])) {
                    emit("ERROR unknown save");
                } else {
                    $copy = $this->saves[$args[0]];
                    $this->s = $copy["state"];
                    $this->history = $copy["history"];
                    $this->start = $copy["start"];
                    emit("load " . $this->s["pieces"] . " " . $this->s["kind"]);
                }
                break;
            case "SPINS":
                $this->spins();
                break;
            case "HINT":
                foreach (array_slice($this->ranked(), 0, (int) $args[0]) as $i => $c) {
                    emit(
                        "hint " .
                            ($i + 1) .
                            " " .
                            $c["kind"] .
                            " " .
                            implode(" ", $c["keys"]) .
                            " value " .
                            $c["value"],
                    );
                }
                break;
            case "AUTO":
                for ($i = 0; $i < (int) $args[0]; $i++) {
                    $c = $this->ranked()[0];
                    emit("auto " . $c["kind"] . " " . implode(" ", $c["keys"]));
                    foreach ($c["keys"] as $op) {
                        $this->operation($op);
                    }
                }
                break;
        }
    }
}
function validArgs(string $command, array $args): bool
{
    $number = fn($text, $low, $high) => preg_match('/^(0|[1-9][0-9]*)$/D', $text) &&
        ((int) $text) >= $low &&
        ((int) $text) <= $high;
    if ($command === "NEW") {
        return count($args) === 2 && $number($args[0], 1, 2147483646) && $number($args[1], 1, 15);
    }
    if ($command === "ROW") {
        return count($args) === 2 &&
            $number($args[0], 1, 22) &&
            preg_match('/^[#.]{10}$/D', $args[1]) &&
            str_contains($args[1], ".");
    }
    if ($command === "GARBAGE") {
        return count($args) === 2 && $number($args[0], 1, 10) && $number($args[1], 1, 10);
    }
    if ($command === "SAVE" || $command === "LOAD") {
        return count($args) === 1 && preg_match('/^[a-z]{1,8}$/D', $args[0]);
    }
    $limits = ["PREVIEW" => 14, "ATTACK" => 20, "TICK" => 1000, "HINT" => 10, "AUTO" => 50];
    if (isset($limits[$command])) {
        return count($args) === 1 && $number($args[0], 1, $limits[$command]);
    }
    return count($args) === 0;
}
$lines = preg_split('/\r?\n/', stream_get_contents(STDIN));
$game = null;
$serial = 0;
foreach (array_slice($lines, 1, (int) $lines[0]) as $line) {
    $words = explode(" ", $line);
    $command = array_shift($words);
    $args = $words;
    try {
        if (in_array($command, $commandNames, true)) {
            if (!validArgs($command, $args)) {
                emit("ERROR bad arguments");
            } elseif ($command === "NEW") {
                if ($game !== null && !$game->s["ended"]) {
                    emit("game stopped");
                    $game->summary();
                }
                emit(
                    "game " .
                        ++$serial .
                        " seed " .
                        ((int) $args[0]) .
                        " level " .
                        ((int) $args[1]),
                );
                $game = new Game($serial, (int) $args[0], (int) $args[1]);
            } elseif ($game === null) {
                emit("ERROR no game");
            } elseif ($game->s["ended"] && !in_array($command, $afterEnd, true)) {
                emit("ERROR game over");
            } else {
                $game->command($command, $args);
            }
        } else {
            $invalid = null;
            foreach (array_merge([$command], $args) as $word) {
                if (!in_array($word, $operationNames, true)) {
                    $invalid = $word;
                    break;
                }
            }
            if ($invalid !== null) {
                emit("ERROR unknown " . $invalid);
            } elseif ($game === null) {
                emit("ERROR no game");
            } elseif ($game->s["ended"]) {
                emit("ERROR game over");
            } else {
                foreach (array_merge([$command], $args) as $word) {
                    $game->operation($word);
                };
            }
        }
    } catch (GameOver $e) {
    }
}
if ($game !== null && !$game->s["ended"]) {
    emit("game stopped");
    $game->summary();
}
echo implode("\n", $output), "\n";
