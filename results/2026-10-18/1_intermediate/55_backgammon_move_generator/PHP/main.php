<?php
function out(string $s): void
{
    echo $s, "\n";
}
function ensure($valid, string $message): void
{
    if (!$valid) {
        throw new RuntimeException($message);
    }
}
function initial(array $score = [0, 0]): array
{
    $own = array_fill(0, 26, 0);
    $own[24] = 2;
    $own[13] = 5;
    $own[8] = 3;
    $own[6] = 5;
    return [
        "pos" => [$own, $own],
        "side" => 0,
        "cube" => 1,
        "owner" => -1,
        "pending" => false,
        "over" => false,
        "score" => $score,
    ];
}
function color(int $x): string
{
    return $x === 0 ? "W" : "B";
}
function positionKey(array $pos): string
{
    return implode(",", array_merge($pos[0], $pos[1]));
}
function pairCompare(array $a, array $b): int
{
    return $b[0] <=> $a[0] ?: $b[1] <=> $a[1];
}
function keyCompare(array $a, array $b): int
{
    for ($i = 0; $i < min(count($a), count($b)); ++$i) {
        $c = pairCompare($a[$i], $b[$i]);
        if ($c !== 0) {
            return $c;
        }
    }
    return count($b) <=> count($a);
}
function notation(array $moves, array $hits): array
{
    $key = $moves;
    usort($key, "pairCompare");
    while (true) {
        $ai = null;
        $bi = null;
        foreach ($key as $i => $a) {
            if ($a[1] === 0 || isset($hits[$a[1]])) {
                continue;
            }
            foreach ($key as $j => $b) {
                if ($b[0] === $a[1]) {
                    $ai = $i;
                    $bi = $j;
                    break;
                }
            }
            if ($ai !== null) {
                break;
            }
        }
        if ($ai === null) {
            break;
        }
        $a = $key[$ai];
        $b = $key[$bi];
        unset($key[$ai], $key[$bi]);
        $key = array_values($key);
        $key[] = [$a[0], $b[1]];
        usort($key, "pairCompare");
    }
    $parts = [];
    $marked = [];
    for ($i = 0; $i < count($key); $i = $j) {
        [$s, $t] = $key[$i];
        $j = $i + 1;
        while ($j < count($key) && $key[$j] === $key[$i]) {
            ++$j;
        }
        $text = ($s === 25 ? "bar" : $s) . "/" . ($t === 0 ? "off" : $t);
        if (isset($hits[$t]) && !isset($marked[$t])) {
            $text .= "*";
            $marked[$t] = true;
        }
        if ($j - $i > 1) {
            $text .= "(" . ($j - $i) . ")";
        }
        $parts[] = $text;
    }
    return [$key, $parts ? implode(" ", $parts) : "none"];
}
function enumerate(array $pos, int $side, int $d1, int $d2): array
{
    $all = [];
    $dice = $d1 === $d2 ? [$d1, $d1, $d1, $d1] : [$d1, $d2];
    $visit = function ($board, $remaining, $moves, $hits, $used) use (&$visit, &$all, $side) {
        [$key, $text] = notation($moves, $hits);
        $all[] = [
            "pos" => $board,
            "key" => $key,
            "text" => $text,
            "count" => count($moves),
            "used" => $used,
            "id" => positionKey($board),
        ];
        $own = $board[$side];
        $opp = $board[1 - $side];
        $tried = [];
        foreach ($remaining as $di => $d) {
            if (isset($tried[$d])) {
                continue;
            }
            $tried[$d] = true;
            $sources = [];
            if ($own[25] > 0) {
                $sources = [25];
            } else {
                for ($p = 1; $p <= 24; ++$p) {
                    if ($own[$p] > 0) {
                        $sources[] = $p;
                    }
                };
            }
            foreach ($sources as $s) {
                $t = max(0, $s - $d);
                $valid = true;
                if ($t > 0) {
                    $valid = $opp[25 - $t] < 2;
                } else {
                    if ($own[25] > 0) {
                        $valid = false;
                    }
                    for ($p = 7; $p <= 24; ++$p) {
                        if ($own[$p] > 0) {
                            $valid = false;
                        }
                    }
                    if ($s < $d) {
                        for ($p = $s + 1; $p <= 6; ++$p) {
                            if ($own[$p] > 0) {
                                $valid = false;
                            }
                        };
                    }
                }
                if (!$valid) {
                    continue;
                }
                $next = $board;
                --$next[$side][$s];
                ++$next[$side][$t];
                $nextHits = $hits;
                if ($t > 0 && $opp[25 - $t] === 1) {
                    $next[1 - $side][25 - $t] = 0;
                    ++$next[1 - $side][25];
                    $nextHits[$t] = true;
                }
                $rest = $remaining;
                array_splice($rest, $di, 1);
                $visit($next, $rest, [...$moves, [$s, $t]], $nextHits, [...$used, $d]);
            }
        }
    };
    $visit($pos, $dice, [], [], []);
    $maximum = 0;
    foreach ($all as $p) {
        $maximum = max($maximum, $p["count"]);
    }
    $larger = false;
    if ($maximum === 1 && $d1 !== $d2) {
        foreach ($all as $p) {
            if ($p["count"] === 1 && $p["used"][0] === max($d1, $d2)) {
                $larger = true;
            }
        };
    }
    $unique = [];
    $legal = [];
    foreach ($all as $p) {
        if (
            $p["count"] !== $maximum ||
            ($larger && $p["used"][0] !== max($d1, $d2)) ||
            isset($unique[$p["id"]])
        ) {
            continue;
        }
        $unique[$p["id"]] = true;
        $legal[] = $p;
    }
    usort($legal, fn($a, $b) => keyCompare($a["key"], $b["key"]));
    return [$legal, $all, $maximum];
}
function pips(array $own): int
{
    $n = 0;
    for ($p = 1; $p <= 25; ++$p) {
        $n += $p * $own[$p];
    }
    return $n;
}
function evaluation(array $pos, int $side): array
{
    $own = $pos[$side];
    $opp = $pos[1 - $side];
    $p = pips($opp) - pips($own);
    $s = 0;
    $h = 0;
    $r = 0;
    $a = 0;
    $run = 0;
    for ($point = 1; $point <= 24; ++$point) {
        if ($own[$point] === 1) {
            $distances = [];
            for ($q = 0; $q < $point; ++$q) {
                if ($opp[25 - $q] > 0) {
                    $distances[$point - $q] = true;
                }
            }
            for ($d1 = 1; $d1 <= 6; ++$d1) {
                for ($d2 = 1; $d2 <= 6; ++$d2) {
                    if (
                        isset($distances[$d1]) ||
                        isset($distances[$d2]) ||
                        isset($distances[$d1 + $d2]) ||
                        ($d1 === $d2 && (isset($distances[3 * $d1]) || isset($distances[4 * $d1])))
                    ) {
                        ++$s;
                    }
                };
            }
        }
        if ($own[$point] >= 2) {
            if ($point <= 6) {
                ++$h;
            }
            if ($point >= 19) {
                ++$a;
            }
            $r = max($r, ++$run);
        } else {
            $run = 0;
        }
    }
    $g = $opp[25] - $own[25];
    return [2 * $p - $s + 4 * $h + 3 * $r + 3 * $a + 6 * $g, $p, $s, $h, $r, $a, $g];
}
function keith(array $own): int
{
    $n = pips($own) + 2 * max($own[1] - 1, 0) + max($own[2] - 1, 0) + max($own[3] - 3, 0);
    for ($p = 4; $p <= 6; ++$p) {
        if ($own[$p] === 0) {
            ++$n;
        }
    }
    return $n;
}
function contact(array $pos): bool
{
    $w = 0;
    $b = 25;
    for ($p = 1; $p <= 24; ++$p) {
        if ($pos[0][$p] > 0) {
            $w = max($w, $p);
        }
        if ($pos[1][$p] > 0) {
            $b = min($b, 25 - $p);
        }
    }
    if ($pos[0][25] > 0) {
        $w = 25;
    }
    if ($pos[1][25] > 0) {
        $b = 0;
    }
    return $w > $b;
}
function cubeDecision(array $state, bool $forbidden = false): string
{
    $x = $state["side"];
    if ($state["owner"] === 1 - $x || $state["cube"] === 64 || $forbidden) {
        return "unavailable";
    }
    if (contact($state["pos"])) {
        $e = evaluation($state["pos"], $x)[0];
        if ($e < 60) {
            return "no double";
        }
        return $e <= 100 ? "double take" : "double drop";
    }
    $v = 8 * keith($state["pos"][$x]) - 7 * keith($state["pos"][1 - $x]);
    $limit = $state["owner"] === -1 ? 28 : 21;
    if ($v > $limit) {
        return "no double";
    }
    return $v >= 14 ? "double take" : "double drop";
}
function endGame(array &$state, int $winner, ?string $kind = null): array
{
    if ($kind === null) {
        $opp = $state["pos"][1 - $winner];
        $back = $opp[25] > 0;
        for ($p = 19; $p <= 24; ++$p) {
            if ($opp[$p] > 0) {
                $back = true;
            }
        }
        $kind = $opp[0] > 0 ? "single" : ($back ? "backgammon" : "gammon");
    }
    $multiplier = ["single" => 1, "gammon" => 2, "backgammon" => 3, "drop" => 1][$kind];
    $points = $state["cube"] * $multiplier;
    $state["over"] = true;
    $state["pending"] = false;
    $state["score"][$winner] += $points;
    return [$winner, $kind, $points];
}
function applyPlay(array &$state, array $play): ?array
{
    $state["pos"] = $play["pos"];
    if ($state["pos"][$state["side"]][0] === 15) {
        return endGame($state, $state["side"]);
    }
    $state["side"] = 1 - $state["side"];
    return null;
}
function ranked(array $legal, int $side): array
{
    $a = [];
    foreach ($legal as $i => $p) {
        $a[] = [evaluation($p["pos"], $side)[0], $i, $p];
    }
    usort($a, fn($x, $y) => $y[0] <=> $x[0] ?: $x[1] <=> $y[1]);
    return $a;
}
function parsePlay(array $tokens): array
{
    if ($tokens === ["none"]) {
        return [];
    }
    $moves = [];
    foreach ($tokens as $token) {
        ensure(preg_match('/^(.+?)(?:\(([234])\))?$/D', $token, $match), "ILLEGAL syntax");
        $path = explode("/", $match[1]);
        $k = (int) ($match[2] ?? 1);
        ensure(count($path) >= 2, "ILLEGAL syntax");
        $values = [];
        foreach ($path as $i => $word) {
            if ($i === 0) {
                if ($word === "bar") {
                    $value = 25;
                } else {
                    ensure(preg_match('/^(?:[1-9]|1[0-9]|2[0-4])$/D', $word), "ILLEGAL syntax");
                    $value = (int) $word;
                }
            } else {
                if ($word === "off") {
                    $value = 0;
                } else {
                    ensure(preg_match('/^(?:[1-9]|1[0-9]|2[0-4])\*?$/D', $word), "ILLEGAL syntax");
                    $value = (int) $word;
                }
                ensure($values[$i - 1] > $value, "ILLEGAL syntax");
            }
            $values[] = $value;
        }
        for ($i = 0; $i < count($values) - 1; ++$i) {
            for ($j = 0; $j < $k; ++$j) {
                $moves[] = [$values[$i], $values[$i + 1]];
            };
        }
    }
    return $moves;
}
class RandomStream
{
    public function __construct(private int $value) {}
    public function nextValue(): int
    {
        return $this->value = ($this->value * 48271) % 2147483647;
    }
    public function die(): int
    {
        return ($this->nextValue() % 6) + 1;
    }
}
function resultLine(array $result): string
{
    return "result " . color($result[0]) . " {$result[1]} {$result[2]}";
}
function simulate(
    array $state,
    RandomStream $rng,
    array $strategies,
    bool $opening = false,
    ?int $target = null,
    ?array $scores = null,
    bool $crawford = false,
    bool $verbose = false,
): array {
    $dice = null;
    if ($opening) {
        do {
            $dice = [$rng->die(), $rng->die()];
        } while ($dice[0] === $dice[1]);
        $state["side"] = $dice[0] > $dice[1] ? 0 : 1;
    }
    $first = $state["side"];
    $turn = 1;
    $plays = 0;
    while (true) {
        $x = $state["side"];
        if (!$opening || $turn !== 1) {
            $forbidden = $target !== null && ($crawford || $scores[$x] + $state["cube"] >= $target);
            $decision = cubeDecision($state, $forbidden);
            if (str_starts_with($decision, "double")) {
                if ($verbose) {
                    out("$turn " . color($x) . " doubles " . $state["cube"] * 2);
                }
                if ($decision === "double drop") {
                    if ($verbose) {
                        out("$turn " . color(1 - $x) . " drops");
                    }
                    return [endGame($state, $x, "drop"), $plays, $first];
                }
                if ($verbose) {
                    out("$turn " . color(1 - $x) . " takes");
                }
                $state["cube"] *= 2;
                $state["owner"] = 1 - $x;
            }
            $dice = [$rng->die(), $rng->die()];
        }
        $legal = enumerate($state["pos"], $x, $dice[0], $dice[1])[0];
        $play = match ($strategies[$x]) {
            "FIRST" => $legal[0],
            "RANDOM" => $legal[$rng->nextValue() % count($legal)],
            default => ranked($legal, $x)[0][2],
        };
        if ($verbose) {
            out("$turn " . color($x) . " {$dice[0]}-{$dice[1]} {$play["text"]}");
        }
        $result = applyPlay($state, $play);
        ++$plays;
        if ($result !== null) {
            return [$result, $plays, $first];
        }
        ++$turn;
    }
}
function numeric($s, int $lo, int $hi): bool
{
    return $s !== null && preg_match('/^\d+$/D', (string) $s) && (int) $s >= $lo && (int) $s <= $hi;
}
$noargs = explode(" ", "NEW SHOW BOARD PIPS RACE EVAL SHOTS CUBE DOUBLE TAKE DROP SCORE HISTORY");
$known = array_merge(
    $noargs,
    explode(" ", "POS MOVES PLAY AUTO HINT RESIGN UNDO REDO GAME MATCH STATS"),
);
$limited = explode(" ", "RACE MOVES PLAY AUTO HINT EVAL SHOTS CUBE DOUBLE TAKE DROP RESIGN GAME");
$pendingLimited = explode(" ", "PLAY AUTO CUBE DOUBLE RESIGN GAME");
$state = initial();
$history = [];
$redo = [];
$n = (int) trim(fgets(STDIN));
for ($command = 0; $command < $n; ++$command) {
    $a = explode(" ", rtrim(fgets(STDIN), "\r\n"));
    $cmd = array_shift($a);
    try {
        ensure(in_array($cmd, $known, true), "ERROR unknown command");
        $valid = true;
        if (in_array($cmd, $noargs, true)) {
            $valid = count($a) === 0;
        } else {
            switch ($cmd) {
                case "POS":
                    $points = array_map("intval", explode(",", $a[0] ?? ""));
                    $valid =
                        count($a) === 4 &&
                        count($points) === 24 &&
                        numeric($a[1] ?? null, 0, 15) &&
                        numeric($a[2] ?? null, 0, 15) &&
                        in_array($a[3] ?? "", ["W", "B"], true);
                    if ($valid) {
                        $pos = [array_fill(0, 26, 0), array_fill(0, 26, 0)];
                        foreach ($points as $i => $v) {
                            if ($v > 0) {
                                $pos[0][$i + 1] = $v;
                            } else {
                                $pos[1][24 - $i] = -$v;
                            }
                        }
                        $pos[0][25] = (int) $a[1];
                        $pos[1][25] = (int) $a[2];
                        for ($x = 0; $x < 2; ++$x) {
                            $pos[$x][0] = 15 - array_sum($pos[$x]);
                            if ($pos[$x][0] < 0 || $pos[$x][0] > 14) {
                                $valid = false;
                            }
                        }
                    }
                    break;
                case "MOVES":
                case "AUTO":
                case "PLAY":
                case "HINT":
                    $valid = numeric($a[0] ?? null, 1, 6) && numeric($a[1] ?? null, 1, 6);
                    $valid =
                        $valid &&
                        match ($cmd) {
                            "PLAY" => count($a) >= 3,
                            "HINT" => count($a) === 3 && numeric($a[2] ?? null, 1, 1000),
                            default => count($a) === 2,
                        };
                    break;
                case "RESIGN":
                    $valid =
                        count($a) === 1 &&
                        in_array($a[0], ["single", "gammon", "backgammon"], true);
                    break;
                case "UNDO":
                case "REDO":
                    $valid = count($a) === 1 && numeric($a[0] ?? null, 1, 1000);
                    break;
                case "GAME":
                    $valid =
                        count($a) === 3 &&
                        numeric($a[0] ?? null, 1, 2147483646) &&
                        in_array($a[1] ?? "", ["BEST", "FIRST", "RANDOM"], true) &&
                        in_array($a[2] ?? "", ["BEST", "FIRST", "RANDOM"], true);
                    break;
                case "MATCH":
                case "STATS":
                    $valid =
                        count($a) === 2 &&
                        numeric($a[0] ?? null, 1, $cmd === "MATCH" ? 15 : 50) &&
                        numeric($a[1] ?? null, 1, 2147483646);
                    break;
            };
        }
        ensure($valid, $cmd === "POS" ? "ERROR bad position" : "ERROR bad arguments");
        ensure(!in_array($cmd, $limited, true) || !$state["over"], "ERROR game over");
        ensure(
            !in_array($cmd, $pendingLimited, true) || !$state["pending"],
            "ERROR double pending",
        );
        $side = $state["side"];
        switch ($cmd) {
            case "NEW":
            case "POS":
                $state = initial($state["score"]);
                if ($cmd === "POS") {
                    $state["pos"] = $pos;
                    $state["side"] = $a[3] === "W" ? 0 : 1;
                }
                $history = [];
                $redo = [];
                out("OK");
                break;
            case "SHOW":
                $points = [];
                for ($p = 1; $p <= 24; ++$p) {
                    $points[] = $state["pos"][0][$p] - $state["pos"][1][25 - $p];
                }
                out(
                    "POS " .
                        implode(",", $points) .
                        " {$state["pos"][0][25]} {$state["pos"][1][25]} " .
                        color($side),
                );
                break;
            case "BOARD":
                $line = function ($top, $row = null) use ($state) {
                    $s = "";
                    for ($i = 1; $i <= 12; ++$i) {
                        $p = $top ? $i + 12 : 13 - $i;
                        $value = $p;
                        if ($row !== null) {
                            $w = $state["pos"][0][$p];
                            $b = $state["pos"][1][25 - $p];
                            $count = max($w, $b);
                            $value =
                                $row === 5 && $count > 5
                                    ? $count
                                    : ($count >= $row
                                        ? ($w > 0
                                            ? "W"
                                            : "B")
                                        : ".");
                        }
                        $s .= str_pad((string) $value, 3, " ", STR_PAD_LEFT);
                        if ($i === 6) {
                            $s .= " |";
                        }
                    }
                    out($s);
                };
                $line(true);
                for ($r = 1; $r <= 5; ++$r) {
                    $line(true, $r);
                }
                $owner = $state["owner"] === -1 ? "center" : color($state["owner"]);
                $status = $state["over"]
                    ? "game over"
                    : color($side) . ($state["pending"] ? " doubles" : " to move");
                out(
                    "bar W{$state["pos"][0][25]} B{$state["pos"][1][25]} | off W{$state["pos"][0][0]} B{$state["pos"][1][0]} | cube {$state["cube"]} $owner | $status",
                );
                for ($r = 5; $r >= 1; --$r) {
                    $line(false, $r);
                }
                $line(false);
                break;
            case "PIPS":
                out("pips W " . pips($state["pos"][0]) . " B " . pips($state["pos"][1]));
                break;
            case "RACE":
                out(
                    contact($state["pos"])
                        ? "contact"
                        : "race W " . keith($state["pos"][0]) . " B " . keith($state["pos"][1]),
                );
                break;
            case "EVAL":
                $values = evaluation($state["pos"], $side);
                $parts = [];
                foreach (
                    ["eval", "pips", "blots", "home", "prime", "anchors", "bar"]
                    as $i => $label
                ) {
                    $parts[] = "$label {$values[$i]}";
                }
                out(implode(" ", $parts));
                break;
            case "MOVES":
            case "HINT":
            case "AUTO":
            case "PLAY":
                $d1 = (int) $a[0];
                $d2 = (int) $a[1];
                [$legal, $all, $maximum] = enumerate($state["pos"], $side, $d1, $d2);
                if ($cmd === "MOVES") {
                    foreach ($legal as $p) {
                        out($p["text"]);
                    }
                    out("total " . count($legal));
                } elseif ($cmd === "HINT") {
                    foreach (
                        array_slice(ranked($legal, $side), 0, (int) $a[2])
                        as [$value, $_, $play]
                    ) {
                        out("$value {$play["text"]}");
                    };
                } else {
                    $play = null;
                    $value = null;
                    if ($cmd === "AUTO") {
                        [$value, $_, $play] = ranked($legal, $side)[0];
                    } else {
                        $moves = parsePlay(array_slice($a, 2));
                        $final = $state["pos"];
                        $destinations = [];
                        foreach ($moves as [$s, $t]) {
                            --$final[$side][$s];
                            ++$final[$side][$t];
                            if ($t > 0) {
                                $destinations[$t] = true;
                            }
                        }
                        foreach ($destinations as $t => $_) {
                            if ($state["pos"][1 - $side][25 - $t] === 1) {
                                $final[1 - $side][25 - $t] = 0;
                                ++$final[1 - $side][25];
                            }
                        }
                        for ($p = 1; $p <= 25; ++$p) {
                            ensure($final[$side][$p] >= 0, "ILLEGAL no checker");
                        }
                        if ($final[$side][25] > 0) {
                            foreach ($moves as [$s, $t]) {
                                ensure($s === 25, "ILLEGAL bar");
                            };
                        }
                        foreach ($destinations as $t => $_) {
                            ensure($state["pos"][1 - $side][25 - $t] < 2, "ILLEGAL blocked");
                        }
                        $bearing = false;
                        foreach ($moves as [$s, $t]) {
                            if ($t === 0) {
                                $bearing = true;
                            }
                        }
                        if ($bearing) {
                            ensure($final[$side][25] === 0, "ILLEGAL bear-off");
                            for ($p = 7; $p <= 24; ++$p) {
                                ensure($final[$side][$p] === 0, "ILLEGAL bear-off");
                            }
                        }
                        $key = positionKey($final);
                        foreach ($legal as $p) {
                            if ($p["id"] === $key) {
                                $play = $p;
                                break;
                            }
                        }
                        if ($play === null) {
                            $possible = false;
                            $fewer = false;
                            foreach ($all as $p) {
                                if ($p["id"] === $key) {
                                    $possible = true;
                                    if ($p["count"] < $maximum) {
                                        $fewer = true;
                                    }
                                }
                            }
                            ensure($possible, "ILLEGAL impossible");
                            throw new RuntimeException(
                                $fewer ? "ILLEGAL too few dice" : "ILLEGAL larger die required",
                            );
                        }
                    }
                    $before = $state;
                    $result = applyPlay($state, $play);
                    out("OK " . $play["text"] . ($cmd === "AUTO" ? " eval $value" : ""));
                    if ($result !== null) {
                        out(resultLine($result));
                    }
                    $history[] = [color($side) . " $d1-$d2 {$play["text"]}", $before, $state];
                    $redo = [];
                }
                break;
            case "SHOTS":
                $blots = [];
                $counts = [];
                for ($p = 24; $p >= 1; --$p) {
                    if ($state["pos"][$side][$p] === 1) {
                        $blots[] = $p;
                        $counts[$p] = 0;
                    }
                }
                $total = 0;
                $rolls = [];
                for ($d1 = 6; $d1 >= 1; --$d1) {
                    for ($d2 = $d1; $d2 >= 1; --$d2) {
                        $legal = enumerate($state["pos"], 1 - $side, $d1, $d2)[0];
                        $hit = [];
                        foreach ($blots as $p) {
                            foreach ($legal as $play) {
                                if ($play["pos"][$side][$p] === 0) {
                                    $hit[] = $p;
                                    break;
                                }
                            };
                        }
                        if ($hit) {
                            $weight = $d1 === $d2 ? 1 : 2;
                            $total += $weight;
                            $rolls[] = "$d1-$d2";
                            foreach ($hit as $p) {
                                $counts[$p] += $weight;
                            }
                        }
                    };
                }
                out("shots $total/36" . ($rolls ? " " . implode(" ", $rolls) : ""));
                foreach ($blots as $p) {
                    out("blot $p {$counts[$p]}/36");
                }
                break;
            case "CUBE":
                out("cube " . cubeDecision($state));
                break;
            case "DOUBLE":
                ensure(
                    $state["owner"] !== 1 - $side && $state["cube"] !== 64,
                    "ERROR cube unavailable",
                );
                $state["pending"] = true;
                $redo = [];
                out("OK double " . $state["cube"] * 2);
                break;
            case "TAKE":
            case "DROP":
                ensure($state["pending"], "ERROR no double");
                $state["pending"] = false;
                $redo = [];
                if ($cmd === "TAKE") {
                    $state["cube"] *= 2;
                    $state["owner"] = 1 - $side;
                    out("OK take {$state["cube"]} " . color($state["owner"]));
                } else {
                    out("OK drop");
                    out(resultLine(endGame($state, $side, "drop")));
                }
                break;
            case "RESIGN":
                $redo = [];
                out("OK resign");
                out(resultLine(endGame($state, 1 - $side, $a[0])));
                break;
            case "SCORE":
                out("score W {$state["score"][0]} B {$state["score"][1]}");
                break;
            case "HISTORY":
                out("history " . count($history));
                foreach ($history as $i => $e) {
                    out($i + 1 . " " . $e[0]);
                }
                break;
            case "UNDO":
            case "REDO":
                $count = (int) $a[0];
                if ($cmd === "UNDO") {
                    ensure($count <= count($history), "ERROR cannot undo");
                    $entries = array_splice($history, count($history) - $count);
                    $state = $entries[0][1];
                    $redo = array_merge($entries, $redo);
                } else {
                    ensure($count <= count($redo), "ERROR cannot redo");
                    $entries = array_splice($redo, 0, $count);
                    $state = $entries[count($entries) - 1][2];
                    $history = array_merge($history, $entries);
                }
                out("OK");
                break;
            case "GAME":
                [$result] = simulate(
                    $state,
                    new RandomStream((int) $a[0]),
                    [$a[1], $a[2]],
                    false,
                    null,
                    null,
                    false,
                    true,
                );
                out(resultLine($result));
                break;
            case "MATCH":
            case "STATS":
                $count = (int) $a[0];
                $rng = new RandomStream((int) $a[1]);
                $points = [0, 0];
                $turns = 0;
                $game = 0;
                $crawfordUsed = false;
                $outcomes = [
                    "single" => [0, 0],
                    "gammon" => [0, 0],
                    "backgammon" => [0, 0],
                    "drop" => [0, 0],
                ];
                while ($cmd === "STATS" ? $game < $count : max($points) < $count) {
                    ++$game;
                    $crawford = $cmd === "MATCH" && !$crawfordUsed && max($points) === $count - 1;
                    $crawfordUsed = $crawfordUsed || $crawford;
                    [$result, $played, $first] = simulate(
                        initial(),
                        $rng,
                        ["BEST", "BEST"],
                        true,
                        $cmd === "MATCH" ? $count : null,
                        $points,
                        $crawford,
                    );
                    [$winner, $kind, $value] = $result;
                    $points[$winner] += $value;
                    ++$outcomes[$kind][$winner];
                    $turns += $played;
                    if ($cmd === "MATCH") {
                        out(
                            "game $game" .
                                ($crawford ? " crawford" : "") .
                                " start " .
                                color($first) .
                                " turns $played " .
                                resultLine($result) .
                                " score {$points[0]}-{$points[1]}",
                        );
                    }
                }
                if ($cmd === "MATCH") {
                    out(
                        "match " .
                            color($points[0] >= $count ? 0 : 1) .
                            " {$points[0]}-{$points[1]}",
                    );
                } else {
                    foreach ($outcomes as $kind => $values) {
                        out("$kind W {$values[0]} B {$values[1]}");
                    }
                    out("points W {$points[0]} B {$points[1]}");
                    out("turns $turns");
                }
                break;
        }
    } catch (RuntimeException $e) {
        out($e->getMessage());
    }
}
