<?php
const CHANNELS = [
    "NOTE_OFF",
    "NOTE_ON",
    "POLY_PRESSURE",
    "CONTROL",
    "PROGRAM",
    "CHANNEL_PRESSURE",
    "PITCH_BEND",
];
const TEXTS = [
    "TEXT_EVENT",
    "COPYRIGHT",
    "TRACK_NAME",
    "INSTRUMENT_NAME",
    "LYRIC",
    "MARKER",
    "CUE_POINT",
];
const METAS = [
    0 => "SEQUENCE_NUMBER",
    1 => "TEXT_EVENT",
    2 => "COPYRIGHT",
    3 => "TRACK_NAME",
    4 => "INSTRUMENT_NAME",
    5 => "LYRIC",
    6 => "MARKER",
    7 => "CUE_POINT",
    32 => "CHANNEL_PREFIX",
    47 => "END_OF_TRACK",
    81 => "TEMPO",
    84 => "SMPTE_OFFSET",
    88 => "TIME_SIGNATURE",
    89 => "KEY_SIGNATURE",
    127 => "SEQUENCER_SPECIFIC",
];
const MAJOR = ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"];
const MINOR = ["Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"];
function out(string $s): void
{
    echo $s, "\n";
}
function ensure($valid, string $reason): void
{
    if (!$valid) {
        throw new RuntimeException($reason);
    }
}
function inRange($s, int $lo, int $hi): bool
{
    return $s !== null &&
        preg_match('/^-?\d+$/D', (string) $s) &&
        (int) $s >= $lo &&
        (int) $s <= $hi;
}
function noteName(int $p): string
{
    return ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][$p % 12] .
        (intdiv($p, 12) - 1);
}
function noteNumber($s): ?int
{
    for ($p = 0; $p < 128; ++$p) {
        if (noteName($p) === $s) {
            return $p;
        }
    }
    return null;
}
function integer(array $a): int
{
    $n = 0;
    foreach ($a as $x) {
        $n = $n * 256 + $x;
    }
    return $n;
}
function big(int $n, int $count): array
{
    $a = [];
    for ($i = $count - 1; $i >= 0; --$i) {
        $a[] = ($n >> (8 * $i)) & 255;
    }
    return $a;
}
function vlq(int $n): array
{
    $a = [$n & 127];
    while (($n >>= 7) > 0) {
        array_unshift($a, ($n & 127) | 128);
    }
    return $a;
}
function bytes(string $s): array
{
    return $s === "" ? [] : array_values(unpack("C*", $s));
}
function event(int $t, int $s, array $d = [], ?int $m = null): object
{
    return (object) ["t" => $t, "s" => $s, "d" => $d, "m" => $m];
}
function eventType(object $e): string
{
    if ($e->s < 240) {
        return CHANNELS[($e->s >> 4) - 8];
    }
    if ($e->s !== 255) {
        return $e->s === 240 ? "SYSEX" : "SYSEX_ESCAPE";
    }
    return METAS[$e->m] ?? "META";
}
function eventFields(object $e): array
{
    $d = $e->d;
    $s = $e->s;
    if ($s < 240) {
        $ch = ($s & 15) + 1;
        $kind = $s >> 4;
        if ($kind <= 10) {
            return [$ch, noteName($d[0]), $d[1]];
        }
        if ($kind === 14) {
            return [$ch, $d[0] + 128 * $d[1] - 8192];
        }
        return array_merge([$ch], $d);
    }
    if ($s !== 255 || $e->m === 127 || !isset(METAS[$e->m])) {
        $a = $s === 255 && !isset(METAS[$e->m]) ? [sprintf("%02X", $e->m)] : [];
        $a[] = count($d);
        if ($d) {
            $a[] = strtoupper(bin2hex(pack("C*", ...$d)));
        }
        return $a;
    }
    switch ($e->m) {
        case 0:
        case 81:
            return [integer($d)];
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
            return ['"' . pack("C*", ...$d) . '"'];
        case 32:
            return [$d[0] + 1];
        case 47:
            return [];
        case 84:
            return $d;
        case 88:
            return [$d[0] . "/" . (1 << $d[1]), $d[2], $d[3]];
        case 89:
            $sf = $d[0] >= 128 ? $d[0] - 256 : $d[0];
            return [($d[1] === 0 ? MAJOR : MINOR)[$sf + 7], $d[1] === 0 ? "major" : "minor"];
    }
    return [];
}
function eventLine(object $e, int $track): string
{
    return implode(" ", array_merge([$e->t, $track, eventType($e)], eventFields($e)));
}
function ordered(array $song): array
{
    $a = [];
    foreach ($song["tracks"] as $i => $tr) {
        foreach ($tr as $j => $e) {
            $a[] = [$e, $i, $j];
        };
    }
    usort($a, fn($x, $y) => $x[0]->t <=> $y[0]->t ?: $x[1] <=> $y[1] ?: $x[2] <=> $y[2]);
    return $a;
}
function songLength(array $song): int
{
    $n = 0;
    foreach ($song["tracks"] as $tr) {
        $n = max($n, $tr[count($tr) - 1]->t);
    }
    return $n;
}
function summary(array $song): string
{
    $count = 0;
    foreach ($song["tracks"] as $tr) {
        $count += count($tr);
    }
    return "format {$song["f"]} tracks " .
        count($song["tracks"]) .
        " division {$song["div"]} events $count";
}
class Reader
{
    private int $p = 0,
        $limit,
        $start = 0;
    public function __construct(private array $data)
    {
        $this->limit = count($data);
    }
    private function fail(string $reason, int $at): never
    {
        throw new RuntimeException("byte $at: $reason");
    }
    private function read(): int
    {
        if ($this->p >= $this->limit) {
            $this->fail("truncated event", $this->start);
        }
        return $this->data[$this->p++];
    }
    private function variable(): int
    {
        $at = $this->p;
        $n = 0;
        for ($i = 0; $i < 4; ++$i) {
            $b = $this->read();
            $n = $n * 128 + ($b & 127);
            if ($b < 128) {
                return $n;
            }
        }
        $this->fail("variable-length value too long", $at);
    }
    private function chunk(string $id): int
    {
        $at = $this->p;
        if (count($this->data) - $at < 8) {
            $this->fail("truncated chunk", $at);
        }
        if (pack("C*", ...array_slice($this->data, $at, 4)) !== $id) {
            $this->fail("bad chunk id", $at);
        }
        $n = integer(array_slice($this->data, $at + 4, 4));
        if ($at + 8 + $n > count($this->data)) {
            $this->fail("truncated chunk", $at);
        }
        $this->p = $at + 8;
        return $n;
    }
    public function parse(): array
    {
        $n = $this->chunk("MThd");
        if ($n !== 6) {
            $this->fail("bad header length", 4);
        }
        $f = integer(array_slice($this->data, 8, 2));
        $count = integer(array_slice($this->data, 10, 2));
        $division = integer(array_slice($this->data, 12, 2));
        if ($f > 2) {
            $this->fail("bad format", 8);
        }
        if ($count === 0 || ($f === 0 && $count !== 1)) {
            $this->fail("bad track count", 10);
        }
        if ($division >= 32768) {
            $this->fail("smpte timing not supported", 12);
        }
        if ($division === 0) {
            $this->fail("bad division", 12);
        }
        $this->p = 14;
        $tracks = [];
        for ($i = 0; $i < $count; ++$i) {
            if ($this->p === count($this->data)) {
                $this->fail("missing track", $this->p);
            }
            $size = $this->chunk("MTrk");
            $this->limit = $this->p + $size;
            $track = [];
            $tick = 0;
            $running = null;
            $ended = false;
            while ($this->p < $this->limit) {
                if ($ended) {
                    $this->fail("event after end of track", $this->p);
                }
                $this->start = $this->p;
                $tick += $this->variable();
                if ($this->p >= $this->limit) {
                    $this->fail("truncated event", $this->start);
                }
                $at = $this->p;
                $s = $this->data[$this->p];
                if ($s < 128) {
                    if ($running === null) {
                        $this->fail("data byte without running status", $this->p);
                    }
                    $s = $running;
                } else {
                    ++$this->p;
                }
                $e = event($tick, $s);
                if ($s < 240) {
                    $running = $s;
                    $kind = $s >> 4;
                    $countData = $kind === 12 || $kind === 13 ? 1 : 2;
                    for ($j = 0; $j < $countData; ++$j) {
                        $pos = $this->p;
                        $b = $this->read();
                        if ($b >= 128) {
                            $this->fail("bad data byte", $pos);
                        }
                        $e->d[] = $b;
                    }
                } elseif (in_array($s, [240, 247, 255], true)) {
                    $running = null;
                    if ($s === 255) {
                        $e->m = $this->read();
                    }
                    $n = $this->variable();
                    if ($this->p + $n > $this->limit) {
                        $this->fail("truncated event", $this->start);
                    }
                    $e->d = array_slice($this->data, $this->p, $n);
                    $this->p += $n;
                    if ($s === 255) {
                        $fixed = [0 => 2, 32 => 1, 47 => 0, 81 => 3, 84 => 5, 88 => 4, 89 => 2];
                        if (isset($fixed[$e->m]) && $fixed[$e->m] !== $n) {
                            $this->fail("bad meta length", $at);
                        }
                        $d = $e->d;
                        $bad = match ($e->m) {
                            32 => $d[0] > 15,
                            81 => integer($d) === 0,
                            88 => $d[0] === 0 || $d[1] > 6,
                            89 => ($d[0] > 7 && $d[0] < 249) || $d[1] > 1,
                            default => false,
                        };
                        if ($bad) {
                            $this->fail("bad meta data", $at);
                        }
                        $ended = $e->m === 47;
                    }
                } else {
                    $this->fail("unknown status byte", $at);
                }
                $track[] = $e;
            }
            if (!$ended) {
                $this->fail("missing end of track", $this->limit);
            }
            $tracks[] = $track;
            $this->limit = count($this->data);
        }
        if ($this->p < count($this->data)) {
            $this->fail("extra data", $this->p);
        }
        return ["f" => $f, "div" => $division, "tracks" => $tracks];
    }
}
function textEvent(string $line): array
{
    $a = explode(" ", $line, 4);
    [$tick, $tr, $type] = $a;
    $rest = $a[3] ?? "";
    $ci = array_search($type, CHANNELS, true);
    $mi = array_search($type, METAS, true);
    ensure(
        $ci !== false || $mi !== false || in_array($type, ["SYSEX", "SYSEX_ESCAPE", "META"], true),
        "unknown event type",
    );
    $f = $rest === "" ? [] : explode(" ", $rest);
    $e = event((int) $tick, 255, [], $mi === false ? null : $mi);
    $good = true;
    if ($ci !== false) {
        $kind = $ci + 8;
        $good =
            count($f) === (in_array($kind, [12, 13, 14], true) ? 2 : 3) &&
            inRange($f[0] ?? null, 1, 16);
        if ($kind <= 10) {
            $note = noteNumber($f[1] ?? null);
            $good = $good && $note !== null && inRange($f[2] ?? null, 0, 127);
            $e->d = [$note, (int) ($f[2] ?? 0)];
        } elseif ($kind === 14) {
            $good = $good && inRange($f[1] ?? null, -8192, 8191);
            $v = (int) ($f[1] ?? 0) + 8192;
            $e->d = [$v % 128, intdiv($v, 128)];
        } else {
            foreach (array_slice($f, 1) as $x) {
                $good = $good && inRange($x, 0, 127);
                $e->d[] = (int) $x;
            }
        }
        $e->s = $kind * 16 + (int) ($f[0] ?? 1) - 1;
    } elseif (in_array($type, TEXTS, true)) {
        $good =
            strlen($rest) >= 2 &&
            $rest[0] === '"' &&
            substr($rest, -1) === '"' &&
            !str_contains(substr($rest, 1, -1), '"');
        if ($good) {
            $e->d = bytes(substr($rest, 1, -1));
        }
    } elseif (in_array($type, ["SYSEX", "SYSEX_ESCAPE", "SEQUENCER_SPECIFIC", "META"], true)) {
        if ($type === "META") {
            $tt = array_shift($f);
            $good =
                $tt !== null && preg_match('/^[0-9A-F]{2}$/D', $tt) && !isset(METAS[hexdec($tt)]);
            $e->m = $tt === null ? null : hexdec($tt);
        } elseif ($type !== "SEQUENCER_SPECIFIC") {
            $e->s = $type === "SYSEX" ? 240 : 247;
        }
        $n = (int) ($f[0] ?? -1);
        $good = $good && inRange($f[0] ?? null, 0, 1000000) && count($f) === ($n === 0 ? 1 : 2);
        if ($n > 0) {
            $good =
                $good &&
                isset($f[1]) &&
                strlen($f[1]) === 2 * $n &&
                preg_match('/^[0-9A-F]+$/D', $f[1]);
        }
        if ($good && $n > 0) {
            $e->d = bytes(hex2bin($f[1]));
        }
    } else {
        switch ($type) {
            case "SEQUENCE_NUMBER":
            case "TEMPO":
            case "CHANNEL_PREFIX":
                [$lo, $hi] = match ($type) {
                    "TEMPO" => [1, 16777215],
                    "CHANNEL_PREFIX" => [1, 16],
                    default => [0, 65535],
                };
                $good = count($f) === 1 && inRange($f[0] ?? null, $lo, $hi);
                $v = (int) ($f[0] ?? 0);
                $e->d = $type === "CHANNEL_PREFIX" ? [$v - 1] : big($v, $type === "TEMPO" ? 3 : 2);
                break;
            case "END_OF_TRACK":
                $good = count($f) === 0;
                break;
            case "SMPTE_OFFSET":
                $good = count($f) === 5;
                foreach ($f as $x) {
                    $good = $good && inRange($x, 0, 255);
                }
                $e->d = array_map("intval", $f);
                break;
            case "TIME_SIGNATURE":
                $parts = explode("/", $f[0] ?? "");
                $nn = (int) ($parts[0] ?? 0);
                $dd = (int) ($parts[1] ?? 0);
                $ex = array_search($dd, [1, 2, 4, 8, 16, 32, 64], true);
                $good =
                    count($f) === 3 &&
                    $nn >= 1 &&
                    $nn <= 255 &&
                    $ex !== false &&
                    inRange($f[1] ?? null, 0, 255) &&
                    inRange($f[2] ?? null, 0, 255);
                if ($good) {
                    $e->d = [$nn, $ex, (int) $f[1], (int) $f[2]];
                }
                break;
            case "KEY_SIGNATURE":
                $mode = $f[1] ?? "";
                $i = array_search($f[0] ?? "", $mode === "major" ? MAJOR : MINOR, true);
                $good =
                    count($f) === 2 && in_array($mode, ["major", "minor"], true) && $i !== false;
                if ($good) {
                    $e->d = [($i - 7 + 256) % 256, $mode === "major" ? 0 : 1];
                }
                break;
        }
    }
    ensure($good, "bad value");
    return [$e, (int) $tr];
}
function parseText(array $lines): array
{
    $h = explode(" ", $lines[0]);
    ensure(
        count($h) === 4 &&
            $h[0] === "HEADER" &&
            inRange($h[1] ?? null, 0, 2) &&
            inRange($h[2] ?? null, 1, 65535) &&
            inRange($h[3] ?? null, 1, 32767) &&
            ((int) $h[1] !== 0 || (int) $h[2] === 1),
        "line 1: bad header",
    );
    $count = (int) $h[2];
    $tracks = [[]];
    $c = 0;
    for ($i = 1; $i < count($lines); ++$i) {
        try {
            [$e, $tr] = textEvent($lines[$i]);
            ensure($tr < $count, "bad track");
            $track = $tracks[$c];
            $ended = $track && eventType($track[count($track) - 1]) === "END_OF_TRACK";
            ensure($tr >= $c, "out of order");
            ensure($tr <= $c || ($ended && $tr === $c + 1), "missing end of track");
            ensure($tr !== $c || !$ended, "event after end of track");
            if ($tr === $c + 1) {
                ++$c;
                $tracks[] = [];
            }
            $track = $tracks[$c];
            ensure(!$track || $e->t >= $track[count($track) - 1]->t, "out of order");
            $tracks[$c][] = $e;
        } catch (RuntimeException $e) {
            throw new RuntimeException("line " . ($i + 1) . ": " . $e->getMessage());
        }
    }
    $track = $tracks[$c];
    ensure(
        $c + 1 === $count && $track && eventType($track[count($track) - 1]) === "END_OF_TRACK",
        "line " . (count($lines) + 1) . ": missing end of track",
    );
    return ["f" => (int) $h[1], "div" => (int) $h[3], "tracks" => $tracks];
}
function pairing(array $song): array
{
    $queues = [];
    $notes = [];
    $unmatched = [];
    foreach (ordered($song) as $order => [$e, $tr, $_]) {
        $kind = $e->s >> 4;
        if ($kind !== 8 && $kind !== 9) {
            continue;
        }
        $key = ($e->s & 15) * 128 + $e->d[0];
        $on = $kind === 9 && $e->d[1] > 0;
        $item = [$e, $tr, $order, $on];
        $queues[$key] ??= [];
        if ($on) {
            $queues[$key][] = $item;
        } elseif (!$queues[$key]) {
            $unmatched[] = $item;
        } else {
            $first = array_shift($queues[$key]);
            $notes[] = [
                "on" => $first[0],
                "off" => $e,
                "order" => $first[2],
                "start" => $first[0]->t,
                "length" => $e->t - $first[0]->t,
                "ch" => ($e->s & 15) + 1,
                "p" => $e->d[0],
                "v" => $first[0]->d[1],
            ];
        }
    }
    foreach ($queues as $q) {
        $unmatched = array_merge($unmatched, $q);
    }
    usort(
        $notes,
        fn($a, $b) => $a["start"] <=> $b["start"] ?:
        $a["ch"] <=> $b["ch"] ?:
        $a["p"] <=> $b["p"] ?:
        $a["order"] <=> $b["order"],
    );
    usort($unmatched, fn($a, $b) => $a[2] <=> $b[2]);
    return [$notes, $unmatched];
}
function floorDiv(int $a, int $b): int
{
    $q = intdiv($a, $b);
    return $a < 0 && $a % $b !== 0 ? $q - 1 : $q;
}
function timePosition(array $song, int $tick): array
{
    $sum = 0;
    $last = 0;
    $v = 500000;
    $st = 0;
    $bar = 1;
    $nn = 4;
    $beat = $song["div"];
    foreach (ordered($song) as [$e, $_, $j]) {
        if ($e->t > $tick) {
            break;
        }
        if ($e->s === 255 && $e->m === 81) {
            $sum += ($e->t - $last) * $v;
            $last = $e->t;
            $v = integer($e->d);
        } elseif ($e->s === 255 && $e->m === 88) {
            $size = $nn * $beat;
            $bar += intdiv($e->t - $st + $size - 1, $size);
            $st = $e->t;
            $nn = $e->d[0];
            $beat = max(1, intdiv($song["div"] * 4, 1 << $e->d[1]));
        }
    }
    $micro = intdiv($sum + ($tick - $last) * $v, $song["div"]);
    $x = $tick - $st;
    return [
        intdiv($micro, 1000) . "." . sprintf("%03d", $micro % 1000),
        $bar +
        intdiv($x, $nn * $beat) .
        ":" .
        (intdiv($x % ($nn * $beat), $beat) + 1) .
        ":" .
        $x % $beat,
    ];
}
function encode(array $song, bool $running, string $noteoff): void
{
    $result = array_merge(
        bytes("MThd"),
        big(6, 4),
        big($song["f"], 2),
        big(count($song["tracks"]), 2),
        big($song["div"], 2),
    );
    foreach ($song["tracks"] as $tr) {
        $data = [];
        $last = 0;
        $status = null;
        foreach ($tr as $e) {
            $data = array_merge($data, vlq($e->t - $last));
            $last = $e->t;
            $s = $e->s;
            $d = $e->d;
            if ($noteoff === "ZERO" && $s >> 4 === 8) {
                $s += 16;
                $d[1] = 0;
            }
            if ($s < 240) {
                if (!$running || $status !== $s) {
                    $data[] = $s;
                }
                $data = array_merge($data, $d);
                $status = $s;
            } else {
                $status = null;
                $data[] = $s;
                if ($s === 255) {
                    $data[] = $e->m;
                }
                $data = array_merge($data, vlq(count($d)), $d);
            }
        }
        $result = array_merge($result, bytes("MTrk"), big(count($data), 4), $data);
    }
    foreach (array_chunk($result, 16) as $i => $part) {
        out(
            sprintf("%04X: ", $i * 16) .
                implode(" ", array_map(fn($b) => sprintf("%02X", $b), $part)),
        );
    }
    out(count($result) . " bytes");
}
$songs = [];
$running = true;
$noteoff = "KEEP";
$known = explode(
    " ",
    "HEX TEXT DECODE ENCODE TIMING NOTES STATS ROLL TRANSPOSE QUANTIZE VELOCITY TEMPO FILTER MERGE SPLIT COPY LIST RUNNING NOTEOFF",
);
$n = (int) trim(fgets(STDIN));
for ($command = 0; $command < $n; ++$command) {
    $a = explode(" ", rtrim(fgets(STDIN), "\r\n"));
    $cmd = array_shift($a);
    $name = $a[0] ?? "";
    try {
        ensure(in_array($cmd, $known, true), "unknown command");
        if ($cmd === "HEX" || $cmd === "TEXT") {
            $lines = [];
            for ($i = 0; $i < (int) $a[1]; ++$i) {
                $lines[] = rtrim(fgets(STDIN), "\r\n");
            }
            $song =
                $cmd === "TEXT"
                    ? parseText($lines)
                    : new Reader(array_map("hexdec", explode(" ", implode(" ", $lines))))->parse();
            $songs[$name] = $song;
            out("loaded $name " . summary($song));
            continue;
        }
        if (!in_array($cmd, ["LIST", "RUNNING", "NOTEOFF"], true)) {
            ensure(isset($songs[$name]), "no song $name");
        }
        $song = $songs[$name] ?? null;
        switch ($cmd) {
            case "LIST":
                $names = array_keys($songs);
                sort($names, SORT_STRING);
                if (!$names) {
                    out("no songs");
                }
                foreach ($names as $key) {
                    out($key . " " . summary($songs[$key]));
                }
                break;
            case "RUNNING":
            case "NOTEOFF":
                ensure(
                    in_array($name, $cmd === "RUNNING" ? ["ON", "OFF"] : ["ZERO", "KEEP"], true),
                    "bad argument",
                );
                if ($cmd === "RUNNING") {
                    $running = $name === "ON";
                } else {
                    $noteoff = $name;
                }
                out(strtolower($cmd) . " " . strtolower($name));
                break;
            case "COPY":
                $songs[$a[1]] = unserialize(serialize($song));
                out("copied $name to {$a[1]}");
                break;
            case "DECODE":
                out("HEADER {$song["f"]} " . count($song["tracks"]) . " {$song["div"]}");
                foreach ($song["tracks"] as $i => $tr) {
                    foreach ($tr as $e) {
                        out(eventLine($e, $i));
                    };
                }
                break;
            case "ENCODE":
                encode($song, $running, $noteoff);
                break;
            case "TIMING":
                ensure($song["f"] !== 2, "format 2 not supported");
                foreach (ordered($song) as [$e, $tr, $_]) {
                    out(
                        "$e->t $tr " .
                            eventType($e) .
                            " " .
                            implode(" ", timePosition($song, $e->t)),
                    );
                }
                out(
                    "end " .
                        songLength($song) .
                        " " .
                        implode(" ", timePosition($song, songLength($song))),
                );
                break;
            case "NOTES":
            case "STATS":
            case "ROLL":
                if ($cmd === "ROLL") {
                    [$from, $to, $step] = array_map("intval", array_slice($a, 1));
                    ensure(
                        inRange($from, 0, 10000000) &&
                            inRange($to, 1, 10000000) &&
                            inRange($step, 1, 10000000) &&
                            $to > $from &&
                            intdiv($to - $from + $step - 1, $step) <= 64,
                        "bad argument",
                    );
                } elseif ($cmd === "STATS") {
                    ensure($song["f"] !== 2, "format 2 not supported");
                }
                [$ns, $unmatched] = pairing($song);
                if ($cmd === "NOTES") {
                    out("notes " . count($ns) . " unmatched " . count($unmatched));
                    foreach ($ns as $v) {
                        out(
                            "{$v["start"]} {$v["length"]} {$v["ch"]} " .
                                noteName($v["p"]) .
                                " {$v["v"]}",
                        );
                    }
                    foreach ($unmatched as [$e, $tr, $_, $on]) {
                        out(
                            "unmatched " .
                                ($on ? "on" : "off") .
                                " $e->t $tr " .
                                (($e->s & 15) + 1) .
                                " " .
                                noteName($e->d[0]),
                        );
                    }
                } elseif ($cmd === "ROLL") {
                    $found = false;
                    for ($p = 127; $p >= 0; --$p) {
                        $chars = "";
                        for ($i = 0; $i < intdiv($to - $from + $step - 1, $step); ++$i) {
                            $at = $from + $i * $step;
                            $c = ".";
                            foreach ($ns as $v) {
                                if (
                                    $v["p"] === $p &&
                                    $v["start"] <= $at &&
                                    $at < $v["start"] + $v["length"]
                                ) {
                                    $c = "=";
                                }
                            }
                            foreach ($ns as $v) {
                                if (
                                    $v["p"] === $p &&
                                    $at <= $v["start"] &&
                                    $v["start"] < $at + $step
                                ) {
                                    $c = "#";
                                }
                            }
                            $chars .= $c;
                        }
                        if (strpbrk($chars, "#=") !== false) {
                            out(str_pad(noteName($p), 4) . " " . $chars);
                            $found = true;
                        }
                    }
                    if (!$found) {
                        out("empty");
                    }
                } else {
                    out(summary($song));
                    out("notes " . count($ns) . " unmatched " . count($unmatched));
                    $lo = 128;
                    $hi = -1;
                    for ($ch = 1; $ch <= 16; ++$ch) {
                        $group = array_values(array_filter($ns, fn($v) => $v["ch"] === $ch));
                        if ($group) {
                            $low = min(array_column($group, "p"));
                            $high = max(array_column($group, "p"));
                            $lo = min($lo, $low);
                            $hi = max($hi, $high);
                            out(
                                "channel $ch notes " .
                                    count($group) .
                                    " range " .
                                    noteName($low) .
                                    " " .
                                    noteName($high),
                            );
                        }
                    }
                    out($ns ? "range " . noteName($lo) . " " . noteName($hi) : "range none");
                    out(
                        "length " .
                            songLength($song) .
                            " ticks " .
                            timePosition($song, songLength($song))[0] .
                            " ms",
                    );
                    $changes = [];
                    foreach ($ns as $v) {
                        if ($v["length"] > 0) {
                            $end = $v["start"] + $v["length"];
                            $changes[$v["start"]] = ($changes[$v["start"]] ?? 0) + 1;
                            $changes[$end] = ($changes[$end] ?? 0) - 1;
                        }
                    }
                    ksort($changes, SORT_NUMERIC);
                    $active = 0;
                    $max = 0;
                    $at = 0;
                    foreach ($changes as $t => $delta) {
                        $active += $delta;
                        if ($active > $max) {
                            $max = $active;
                            $at = $t;
                        }
                    }
                    out($max ? "polyphony $max at $at" : "polyphony 0");
                }
                break;
            case "TRANSPOSE":
                $amount = (int) $a[1];
                $ch = isset($a[2]) ? (int) $a[2] : null;
                ensure(
                    inRange($amount, -127, 127) && ($ch === null || inRange($ch, 1, 16)),
                    "bad argument",
                );
                $kept = 0;
                $dropped = [];
                foreach ($song["tracks"] as $i => $tr) {
                    $new = [];
                    foreach ($tr as $e) {
                        $kind = $e->s >> 4;
                        if (
                            $kind >= 8 &&
                            $kind <= 10 &&
                            ($ch === null || ($e->s & 15) + 1 === $ch)
                        ) {
                            $p = $e->d[0] + $amount;
                            if ($p < 0 || $p > 127) {
                                $dropped[] =
                                    "dropped $e->t $i " .
                                    eventType($e) .
                                    " " .
                                    (($e->s & 15) + 1) .
                                    " " .
                                    noteName($e->d[0]);
                                continue;
                            }
                            $e->d[0] = $p;
                            ++$kept;
                        }
                        $new[] = $e;
                    }
                    $song["tracks"][$i] = $new;
                }
                $songs[$name] = $song;
                out("transposed $kept dropped " . count($dropped));
                foreach ($dropped as $s) {
                    out($s);
                }
                break;
            case "QUANTIZE":
                $grid = (int) $a[1];
                $strength = (int) $a[2];
                ensure(inRange($grid, 1, 1000000) && inRange($strength, 0, 100), "bad argument");
                [$ns, $unmatched] = pairing($song);
                $targets = [];
                $moved = 0;
                foreach ($ns as $v) {
                    $targets[] = [$v["on"], $v["off"]];
                }
                foreach ($unmatched as $u) {
                    if ($u[3]) {
                        $targets[] = [$u[0]];
                    }
                }
                foreach ($targets as $events) {
                    $t = $events[0]->t;
                    $lower = intdiv($t, $grid) * $grid;
                    $g = $t - $lower <= $lower + $grid - $t ? $lower : $lower + $grid;
                    $delta = floorDiv(2 * ($g - $t) * $strength + 100, 200);
                    if ($delta !== 0) {
                        ++$moved;
                    }
                    foreach ($events as $e) {
                        $e->t += $delta;
                    }
                }
                foreach ($song["tracks"] as $i => $tr) {
                    $ending = array_pop($tr);
                    foreach ($tr as $j => $e) {
                        $e->order = $j;
                    }
                    usort($tr, fn($x, $y) => $x->t <=> $y->t ?: $x->order <=> $y->order);
                    foreach ($tr as $e) {
                        $ending->t = max($ending->t, $e->t);
                        unset($e->order);
                    }
                    $tr[] = $ending;
                    $song["tracks"][$i] = $tr;
                }
                $songs[$name] = $song;
                out("quantized " . count($targets) . " moved $moved");
                break;
            case "VELOCITY":
                $percent = (int) $a[1];
                $offset = (int) $a[2];
                ensure(inRange($percent, 0, 1000) && inRange($offset, -127, 127), "bad argument");
                $count = 0;
                $clamped = 0;
                foreach (ordered($song) as [$e, $_, $j]) {
                    if ($e->s >> 4 === 9 && $e->d[1] > 0) {
                        ++$count;
                        $v = intdiv($e->d[1] * $percent + 50, 100) + $offset;
                        if ($v < 1 || $v > 127) {
                            ++$clamped;
                        }
                        $e->d[1] = max(1, min(127, $v));
                    }
                }
                out("velocity $count clamped $clamped");
                break;
            case "TEMPO":
                $num = (int) $a[1];
                $den = (int) $a[2];
                ensure(inRange($num, 1, 1000) && inRange($den, 1, 1000), "bad argument");
                $converted = [];
                $insert = true;
                foreach (ordered($song) as [$e, $_, $j]) {
                    if ($e->s === 255 && $e->m === 81) {
                        $v = intdiv(2 * integer($e->d) * $den + $num, 2 * $num);
                        ensure(inRange($v, 1, 16777215), "tempo out of range");
                        $converted[] = [$e, $v];
                        if ($e->t === 0) {
                            $insert = false;
                        }
                    }
                }
                $v = intdiv(1000000 * $den + $num, 2 * $num);
                ensure(!$insert || inRange($v, 1, 16777215), "tempo out of range");
                foreach ($converted as [$e, $value]) {
                    $e->d = big($value, 3);
                }
                out("scaled " . count($converted));
                if ($insert) {
                    array_unshift($song["tracks"][0], event(0, 255, big($v, 3), 81));
                    out("inserted 0 0 TEMPO $v");
                }
                $songs[$name] = $song;
                break;
            case "FILTER":
                $allowed = array_map("intval", array_slice($a, 1));
                foreach ($allowed as $ch) {
                    ensure(inRange($ch, 1, 16), "bad argument");
                }
                $count = 0;
                foreach ($song["tracks"] as $i => $tr) {
                    $new = [];
                    foreach ($tr as $e) {
                        if ($e->s < 240 && !in_array(($e->s & 15) + 1, $allowed, true)) {
                            ++$count;
                        } else {
                            $new[] = $e;
                        }
                    }
                    $song["tracks"][$i] = $new;
                }
                $songs[$name] = $song;
                out("removed $count");
                break;
            case "MERGE":
                ensure($song["f"] === 1, "not format 1");
                $count = count($song["tracks"]);
                $end = songLength($song);
                $tr = [];
                foreach (ordered($song) as [$e, $_, $j]) {
                    if (eventType($e) !== "END_OF_TRACK") {
                        $tr[] = $e;
                    }
                }
                $tr[] = event($end, 255, [], 47);
                $song["f"] = 0;
                $song["tracks"] = [$tr];
                $songs[$name] = $song;
                out("merged $count tracks events " . count($tr));
                break;
            case "SPLIT":
                ensure($song["f"] === 0, "not format 0");
                $tr = $song["tracks"][0];
                $end = array_pop($tr);
                $groups = [-1 => []];
                foreach ($tr as $e) {
                    $key = $e->s < 240 ? $e->s & 15 : -1;
                    $groups[$key][] = $e;
                }
                ksort($groups, SORT_NUMERIC);
                $result = [];
                $count = 0;
                foreach ($groups as $group) {
                    $group[] = clone $end;
                    $result[] = $group;
                    $count += count($group);
                }
                $song["f"] = 1;
                $song["tracks"] = $result;
                $songs[$name] = $song;
                out("split tracks " . count($result) . " events $count");
                break;
        }
    } catch (RuntimeException $e) {
        out("error: " . $e->getMessage());
    }
}
