<?php
const FILES = "abcdefgh";
const RANKS = "12345678";
const INITIAL = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
const ROOK = [[0, 1], [0, -1], [-1, 0], [1, 0]];
const BISHOP = [[1, 1], [-1, 1], [1, -1], [-1, -1]];
const KING = [[0, 1], [0, -1], [-1, 0], [1, 0], [1, 1], [-1, 1], [1, -1], [-1, -1]];
const KNIGHT = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]];
const RULES = [
    "K" => [4, 7, 6, 5, [5, 6]],
    "Q" => [4, 0, 2, 3, [1, 2, 3]],
    "k" => [60, 63, 62, 61, [61, 62]],
    "q" => [60, 56, 58, 59, [57, 58, 59]],
];
function fail(string $reason): never
{
    throw new RuntimeException($reason);
}
function emit(string $s): void
{
    echo $s, "\n";
}
function opposite(string $c): string
{
    return $c === "w" ? "b" : "w";
}
function color(string $p): string
{
    return $p === strtoupper($p) ? "w" : "b";
}
function colored(string $p, string $c): string
{
    return $c === "w" ? $p : strtolower($p);
}
function step(string $c): int
{
    return $c === "w" ? 8 : -8;
}
function square(string $s): int
{
    return preg_match("/\A[a-h][1-8]\z/", $s) ? ord($s[0]) - 97 + 8 * (ord($s[1]) - 49) : -1;
}
function squareName(int $s): string
{
    return FILES[$s % 8] . RANKS[intdiv($s, 8)];
}
function number(string $s, int $lo, int $hi): int
{
    return preg_match("/\A(?:0|[1-9][0-9]*)\z/", $s) && (int) $s >= $lo && (int) $s <= $hi
        ? (int) $s
        : -1;
}
function shiftSquare(int $s, int $dx, int $dy): int
{
    $x = ($s % 8) + $dx;
    $y = intdiv($s, 8) + $dy;
    return $x >= 0 && $x < 8 && $y >= 0 && $y < 8 ? 8 * $y + $x : -1;
}
function targets(array $board, int $s): array
{
    $piece = $board[$s];
    $kind = strtoupper($piece);
    $result = [];
    if (in_array($kind, ["P", "N", "K"], true)) {
        $dirs =
            $kind === "P"
                ? [[-1, color($piece) === "w" ? 1 : -1], [1, color($piece) === "w" ? 1 : -1]]
                : ($kind === "N"
                    ? KNIGHT
                    : KING);
        foreach ($dirs as [$dx, $dy]) {
            $t = shiftSquare($s, $dx, $dy);
            if ($t >= 0) {
                $result[] = $t;
            }
        }
        return $result;
    }
    $dirs = $kind === "Q" ? KING : ($kind === "R" ? ROOK : BISHOP);
    foreach ($dirs as [$dx, $dy]) {
        for ($t = shiftSquare($s, $dx, $dy); $t >= 0; $t = shiftSquare($t, $dx, $dy)) {
            $result[] = $t;
            if ($board[$t] !== ".") {
                break;
            }
        };
    }
    return $result;
}
function attackers(array $board, int $t, string $c): array
{
    $a = [];
    for ($s = 0; $s < 64; $s++) {
        if (
            $board[$s] !== "." &&
            color($board[$s]) === $c &&
            in_array($t, targets($board, $s), true)
        ) {
            $a[] = $s;
        }
    }
    return $a;
}
class Move
{
    public function __construct(
        public int $source,
        public int $target,
        public string $promotion = "",
    ) {}
}
class Position
{
    private ?array $cached = null;
    public function __construct(
        public array $board,
        public string $side,
        public string $rights,
        public int $ep,
        public int $half,
        public int $full,
    ) {}
    public function check(?string $c = null): bool
    {
        $c ??= $this->side;
        return count(
            attackers(
                $this->board,
                array_search(colored("K", $c), $this->board, true),
                opposite($c),
            ),
        ) > 0;
    }
    public function castle(Move $m): bool
    {
        return strtoupper($this->board[$m->source]) === "K" && abs($m->target - $m->source) === 2;
    }
    public function enpassant(Move $m): bool
    {
        return strtoupper($this->board[$m->source]) === "P" &&
            $m->source % 8 !== $m->target % 8 &&
            $this->board[$m->target] === ".";
    }
    public function capture(Move $m): bool
    {
        return $this->board[$m->target] !== "." || $this->enpassant($m);
    }
    public function captured(Move $m): string
    {
        return $this->board[$m->target] !== "."
            ? strtolower($this->board[$m->target])
            : ($this->enpassant($m)
                ? "p"
                : "-");
    }
    public function play(Move $m): Position
    {
        $b = $this->board;
        $piece = $b[$m->source];
        $kind = strtoupper($piece);
        if ($this->enpassant($m)) {
            $b[$m->target - step($this->side)] = ".";
        }
        if ($this->castle($m)) {
            $r = RULES[colored($m->target > $m->source ? "K" : "Q", $this->side)];
            $b[$r[3]] = $b[$r[1]];
            $b[$r[1]] = ".";
        }
        $b[$m->target] = $m->promotion !== "" ? colored($m->promotion, $this->side) : $piece;
        $b[$m->source] = ".";
        $rights = "";
        foreach (str_split($this->rights) as $r) {
            if (
                ($kind !== "K" || color($r) !== $this->side) &&
                !in_array(RULES[$r][1], [$m->source, $m->target], true)
            ) {
                $rights .= $r;
            }
        }
        return new Position(
            $b,
            opposite($this->side),
            $rights,
            $kind === "P" && abs($m->target - $m->source) === 16
                ? intdiv($m->source + $m->target, 2)
                : -1,
            $kind === "P" || $this->capture($m) ? 0 : $this->half + 1,
            $this->full + ($this->side === "b" ? 1 : 0),
        );
    }
    public function pseudo(): array
    {
        $result = [];
        foreach ($this->board as $s => $piece) {
            if ($piece === "." || color($piece) !== $this->side) {
                continue;
            }
            $pawn = strtoupper($piece) === "P";
            $a = [];
            if ($pawn) {
                $d = step($this->side);
                if ($this->board[$s + $d] === ".") {
                    $a[] = $s + $d;
                    if (
                        intdiv($s, 8) === ($this->side === "w" ? 1 : 6) &&
                        $this->board[$s + 2 * $d] === "."
                    ) {
                        $a[] = $s + 2 * $d;
                    }
                }
                foreach (targets($this->board, $s) as $t) {
                    if (
                        ($this->board[$t] !== "." && color($this->board[$t]) !== $this->side) ||
                        $t === $this->ep
                    ) {
                        $a[] = $t;
                    }
                }
            } else {
                foreach (targets($this->board, $s) as $t) {
                    if ($this->board[$t] === "." || color($this->board[$t]) !== $this->side) {
                        $a[] = $t;
                    }
                };
            }
            foreach ($a as $t) {
                foreach (
                    $pawn && intdiv($t, 8) === ($this->side === "w" ? 7 : 0)
                        ? ["Q", "R", "B", "N"]
                        : [""]
                    as $p
                ) {
                    $result[] = new Move($s, $t, $p);
                };
            }
        }
        return $result;
    }
    public function castlingMove(bool $kingside): Move
    {
        $r = RULES[colored($kingside ? "K" : "Q", $this->side)];
        return new Move($r[0], $r[2]);
    }
    public function castlingProblem(bool $kingside): string
    {
        $right = colored($kingside ? "K" : "Q", $this->side);
        $r = RULES[$right];
        if (!str_contains($this->rights, $right)) {
            return "no castling right";
        }
        foreach ($r[4] as $s) {
            if ($this->board[$s] !== ".") {
                return "path blocked";
            }
        }
        if ($this->check()) {
            return "in check";
        }
        if (attackers($this->board, $r[3], opposite($this->side))) {
            return "through check";
        }
        if ($this->play($this->castlingMove($kingside))->check($this->side)) {
            return "into check";
        }
        return "";
    }
    public function legal(): array
    {
        if ($this->cached !== null) {
            return $this->cached;
        }
        $a = [];
        foreach ($this->pseudo() as $m) {
            if (!$this->play($m)->check($this->side)) {
                $a[] = $m;
            }
        }
        foreach ([true, false] as $k) {
            if ($this->castlingProblem($k) === "") {
                $a[] = $this->castlingMove($k);
            }
        }
        return $this->cached = $a;
    }
    public function mark(Move $m): string
    {
        $q = $this->play($m);
        return $q->check() ? ($q->legal() ? "+" : "#") : "";
    }
    public function disambiguation(Move $m): string
    {
        $a = [];
        foreach ($this->legal() as $x) {
            if (
                !$this->castle($x) &&
                $x->target === $m->target &&
                $x->source !== $m->source &&
                $this->board[$x->source] === $this->board[$m->source]
            ) {
                $a[] = $x->source;
            }
        }
        if (!$a) {
            return "";
        }
        $file = true;
        $rank = true;
        foreach ($a as $s) {
            $file = $file && $s % 8 !== $m->source % 8;
            $rank = $rank && intdiv($s, 8) !== intdiv($m->source, 8);
        }
        return $file
            ? FILES[$m->source % 8]
            : ($rank
                ? RANKS[intdiv($m->source, 8)]
                : squareName($m->source));
    }
    public function san(Move $m): string
    {
        $kind = strtoupper($this->board[$m->source]);
        if ($this->castle($m)) {
            $text = $m->target > $m->source ? "O-O" : "O-O-O";
        } elseif ($kind === "P") {
            $text =
                ($this->capture($m) ? FILES[$m->source % 8] . "x" : "") .
                squareName($m->target) .
                ($m->promotion !== "" ? "=" . $m->promotion : "");
        } else {
            $text =
                $kind .
                $this->disambiguation($m) .
                ($this->capture($m) ? "x" : "") .
                squareName($m->target);
        }
        return $text . $this->mark($m);
    }
    public function key(): string
    {
        $ep = -1;
        if ($this->ep >= 0) {
            foreach ($this->legal() as $m) {
                if ($this->enpassant($m)) {
                    $ep = $this->ep;
                    break;
                }
            };
        }
        return implode("", $this->board) . " " . $this->side . " " . $this->rights . " " . $ep;
    }
    public function state(): string
    {
        return $this->check()
            ? ($this->legal()
                ? "check"
                : "checkmate")
            : ($this->legal()
                ? "normal"
                : "stalemate");
    }
    public function insufficient(): bool
    {
        $a = [];
        foreach ($this->board as $s => $p) {
            if ($p !== "." && strtoupper($p) !== "K") {
                if (str_contains("PRQ", strtoupper($p))) {
                    return false;
                }
                $a[] = $s;
            }
        }
        if (count($a) <= 1) {
            return true;
        }
        $shade = (($a[0] % 8) + intdiv($a[0], 8)) % 2;
        foreach ($a as $s) {
            if (strtoupper($this->board[$s]) !== "B" || (($s % 8) + intdiv($s, 8)) % 2 !== $shade) {
                return false;
            }
        }
        return true;
    }
    public function pins(): array
    {
        $king = array_search(colored("K", $this->side), $this->board, true);
        $found = [];
        foreach (KING as [$dx, $dy]) {
            $first = -1;
            for ($t = shiftSquare($king, $dx, $dy); $t >= 0; $t = shiftSquare($t, $dx, $dy)) {
                $p = $this->board[$t];
                if ($p === ".") {
                    continue;
                }
                if ($first < 0) {
                    if (color($p) !== $this->side) {
                        break;
                    }
                    $first = $t;
                } else {
                    if (
                        color($p) !== $this->side &&
                        str_contains("Q" . ($dx === 0 || $dy === 0 ? "R" : "B"), strtoupper($p))
                    ) {
                        $found[] = [$first, $t];
                    }
                    break;
                }
            }
        }
        usort($found, fn($a, $b) => $a[0] <=> $b[0]);
        return $found;
    }
    public function fen(): string
    {
        $rows = [];
        for ($r = 7; $r >= 0; $r--) {
            $rows[] = preg_replace_callback(
                "/\.+/",
                fn($m) => (string) strlen($m[0]),
                implode("", array_slice($this->board, 8 * $r, 8)),
            );
        }
        return implode(" ", [
            implode("/", $rows),
            $this->side,
            $this->rights !== "" ? $this->rights : "-",
            $this->ep < 0 ? "-" : squareName($this->ep),
            $this->half,
            $this->full,
        ]);
    }
}
function parseFen(array $a): Position
{
    if (count($a) !== 6) {
        fail("fields");
    }
    $ranks = explode("/", $a[0]);
    if (count($ranks) !== 8) {
        fail("placement");
    }
    $board = array_fill(0, 64, ".");
    foreach ($ranks as $i => $row) {
        $f = 0;
        $digit = false;
        foreach (str_split($row) as $c) {
            if (str_contains("12345678", $c)) {
                if ($digit) {
                    fail("placement");
                }
                $f += (int) $c;
                $digit = true;
            } else {
                if (!str_contains("KQRBNPkqrbnp", $c) || $f >= 8) {
                    fail("placement");
                }
                $board[(7 - $i) * 8 + $f++] = $c;
                $digit = false;
            }
        }
        if ($f !== 8) {
            fail("placement");
        }
    }
    if (count(array_keys($board, "K", true)) !== 1 || count(array_keys($board, "k", true)) !== 1) {
        fail("kings");
    }
    foreach (array_merge(array_slice($board, 0, 8), array_slice($board, 56)) as $p) {
        if ($p === "P" || $p === "p") {
            fail("pawns");
        }
    }
    $side = $a[1];
    if ($side !== "w" && $side !== "b") {
        fail("side");
    }
    if ($a[2] !== "-" && !preg_match("/\A(?=.)K?Q?k?q?\z/", $a[2])) {
        fail("castling");
    }
    $rights = $a[2] === "-" ? "" : $a[2];
    foreach (str_split($rights) as $r) {
        if (
            $board[RULES[$r][0]] !== colored("K", color($r)) ||
            $board[RULES[$r][1]] !== colored("R", color($r))
        ) {
            fail("castling");
        }
    }
    $ep = -1;
    if ($a[3] !== "-") {
        $ep = square($a[3]);
        $d = step($side);
        if (
            $ep < 0 ||
            intdiv($ep, 8) !== ($side === "w" ? 5 : 2) ||
            $board[$ep] !== "." ||
            $board[$ep + $d] !== "." ||
            $board[$ep - $d] !== colored("P", opposite($side))
        ) {
            fail("en passant");
        }
    }
    $half = number($a[4], 0, 999);
    $full = number($a[5], 1, 999);
    if ($half < 0 || $full < 0 || ($ep >= 0 && $half !== 0)) {
        fail("clocks");
    }
    $p = new Position($board, $side, $rights, $ep, $half, $full);
    if ($p->check(opposite($side))) {
        fail("check");
    }
    return $p;
}
function readSan(Position $pos, string $text): Move
{
    $mark = str_ends_with($text, "+") || str_ends_with($text, "#") ? substr($text, -1) : "";
    $body = $mark !== "" ? substr($text, 0, -1) : $text;
    $castling = $body === "O-O" || $body === "O-O-O";
    $promotion = "";
    $target = -1;
    $capture = false;
    $kind = "P";
    $file = "";
    $rank = "";
    if (!$castling) {
        if (strlen($body) >= 2 && $body[strlen($body) - 2] === "=") {
            $promotion = substr($body, -1);
            if (!str_contains("QRBN", $promotion)) {
                fail("syntax");
            }
            $body = substr($body, 0, -2);
        }
        $target = square(substr($body, -2));
        if ($target < 0) {
            fail("syntax");
        }
        $body = substr($body, 0, -2);
        $capture = str_ends_with($body, "x");
        if ($capture) {
            $body = substr($body, 0, -1);
        }
        if ($body !== "" && str_contains("KQRBN", $body[0])) {
            $kind = $body[0];
            if ($promotion !== "" || !preg_match("/\A([a-h]?)([1-8]?)\z/", substr($body, 1), $h)) {
                fail("syntax");
            }
            $file = $h[1];
            $rank = $h[2];
        } else {
            if (!preg_match($capture ? "/\A[a-h]\z/" : "/\A\z/", $body)) {
                fail("syntax");
            }
            $file = $body;
        }
    }
    $legal = $pos->legal();
    if (!$legal) {
        fail("game over");
    }
    if ($castling) {
        $k = $body === "O-O";
        $problem = $pos->castlingProblem($k);
        if ($problem !== "") {
            fail($problem);
        }
        $move = $pos->castlingMove($k);
    } else {
        $matches = fn($m) => strtoupper($pos->board[$m->source]) === $kind &&
            $m->target === $target &&
            !$pos->castle($m) &&
            ($file === "" || FILES[$m->source % 8] === $file) &&
            ($rank === "" || RANKS[intdiv($m->source, 8)] === $rank) &&
            ($kind !== "P" || ($m->source % 8 !== $m->target % 8) === $capture);
        $candidates = array_values(array_filter($legal, $matches));
        if (!$candidates) {
            fail(array_filter($pos->pseudo(), $matches) ? "leaves king in check" : "no such move");
        }
        if (count(array_unique(array_map(fn($m) => $m->source, $candidates))) > 1) {
            fail("ambiguous");
        }
        $move = $candidates[0];
        if ($pos->capture($move) !== $capture) {
            fail("capture mark");
        }
        if ($move->promotion !== "" && $promotion === "") {
            fail("missing promotion");
        }
        if ($promotion !== "" && $move->promotion === "") {
            fail("invalid promotion");
        }
        if ($kind !== "P" && $file . $rank !== $pos->disambiguation($move)) {
            fail("disambiguation");
        }
        $move = new Move($move->source, $move->target, $promotion);
    }
    if ($pos->mark($move) !== $mark) {
        fail("check mark");
    }
    return $move;
}
function readUci(Position $pos, string $text): Move
{
    if (!preg_match("/\A[a-h][1-8][a-h][1-8][qrbn]?\z/", $text)) {
        fail("syntax");
    }
    $s = square(substr($text, 0, 2));
    $t = square(substr($text, 2, 2));
    $p = strtoupper(substr($text, 4));
    $legal = $pos->legal();
    if (!$legal) {
        fail("game over");
    }
    if ($pos->board[$s] === "." || color($pos->board[$s]) !== $pos->side) {
        fail("no piece");
    }
    foreach ($legal as $m) {
        if ($m->source === $s && $m->target === $t) {
            if ($m->promotion !== "" && $p === "") {
                fail("missing promotion");
            }
            if ($p !== "" && $m->promotion === "") {
                fail("invalid promotion");
            }
            return new Move($s, $t, $p);
        }
    }
    foreach ($pos->pseudo() as $m) {
        if ($m->source === $s && $m->target === $t) {
            fail("leaves king in check");
        }
    }
    fail("no such move");
}
function perft(Position $p, int $depth, ?array &$stats = null): int
{
    if ($depth === 0) {
        return 1;
    }
    $total = 0;
    foreach ($p->legal() as $m) {
        $q = $p->play($m);
        $total += perft($q, $depth - 1, $stats);
        if ($depth === 1 && $stats !== null) {
            $stats[0]++;
            $stats[1] += (int) $p->capture($m);
            $stats[2] += (int) $p->enpassant($m);
            $stats[3] += (int) $p->castle($m);
            $stats[4] += (int) ($m->promotion !== "");
            if ($q->check()) {
                $stats[5]++;
                $stats[6] += (int) !$q->legal();
            }
        }
    }
    return $total;
}
class Game
{
    public array $positions,
        $records = [];
    public function __construct(?Position $start = null, public bool $loaded = false)
    {
        $this->positions = [$start ?? parseFen(explode(" ", INITIAL))];
    }
    public function current(): Position
    {
        return $this->positions[count($this->positions) - 1];
    }
    public function play(Move $m): void
    {
        $p = $this->current();
        $this->records[] = [
            "san" => $p->san($m),
            "uci" => squareName($m->source) . squareName($m->target) . strtolower($m->promotion),
            "captured" => $p->captured($m),
        ];
        $this->positions[] = $p->play($m);
    }
    public function repetition(): int
    {
        $key = $this->current()->key();
        return count(array_filter($this->positions, fn($p) => $p->key() === $key));
    }
    public function draws(): array
    {
        $p = $this->current();
        $a = [];
        if ($p->half >= 100) {
            $a[] = "fifty";
        }
        if ($this->repetition() >= 3) {
            $a[] = "threefold";
        }
        if ($p->insufficient()) {
            $a[] = "insufficient";
        }
        return $a;
    }
    public function result(): string
    {
        $p = $this->current();
        $state = $p->state();
        return $state === "checkmate"
            ? ($p->side === "b"
                ? "1-0"
                : "0-1")
            : ($state === "stalemate" || $this->draws()
                ? "1/2-1/2"
                : "*");
    }
}
function execute(Game &$game, string $line): void
{
    $w = explode(" ", $line);
    $cmd = array_shift($w);
    $a = $w;
    $commands = explode(
        " ",
        "NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN",
    );
    if (!in_array($cmd, $commands, true)) {
        emit("ERROR unknown command");
        return;
    }
    $bad =
        in_array($cmd, ["NEW", "FEN", "BOARD", "STATUS", "PINS", "HISTORY", "PGN"], true) &&
        count($a) !== 0;
    if ($cmd === "MOVE" || $cmd === "UCI") {
        $bad = !$a;
    }
    if ($cmd === "LEGAL") {
        $bad = count($a) > 1 || (count($a) === 1 && square($a[0]) < 0);
    }
    if ($cmd === "ATTACKS") {
        $bad = count($a) !== 1 || (count($a) === 1 && square($a[0]) < 0);
    }
    $n = -1;
    if (in_array($cmd, ["UNDO", "PERFT", "DIVIDE"], true)) {
        $n = count($a) === 1 ? number($a[0], 1, $cmd === "UNDO" ? 9999 : 3) : -1;
        $bad = $n < 0;
    }
    if ($bad) {
        emit("ERROR bad arguments");
        return;
    }
    $p = $game->current();
    switch ($cmd) {
        case "NEW":
            $game = new Game();
            emit("OK");
            break;
        case "LOAD":
            try {
                $q = parseFen($a);
                $game = new Game($q, true);
                emit("OK");
            } catch (RuntimeException $e) {
                emit("ERROR bad fen (" . $e->getMessage() . ")");
            }
            break;
        case "FEN":
            emit($p->fen());
            break;
        case "BOARD":
            for ($r = 7; $r >= 0; $r--) {
                emit(implode(" ", array_merge([$r + 1], array_slice($p->board, 8 * $r, 8))));
            }
            emit("  a b c d e f g h");
            break;
        case "MOVE":
        case "UCI":
            $played = [];
            $failure = "";
            foreach ($a as $i => $text) {
                try {
                    $m =
                        $cmd === "MOVE"
                            ? readSan($game->current(), $text)
                            : readUci($game->current(), $text);
                    $game->play($m);
                    $played[] = $game->records[count($game->records) - 1]["san"];
                } catch (RuntimeException $e) {
                    $failure =
                        "ILLEGAL move " . ($i + 1) . ": " . $text . " (" . $e->getMessage() . ")";
                    break;
                }
            }
            if ($cmd === "UCI" && $played) {
                emit("san " . implode(" ", $played));
            }
            if ($failure !== "") {
                emit($failure);
            } elseif ($cmd === "MOVE") {
                emit("OK");
            }
            break;
        case "LEGAL":
            $from = $a ? square($a[0]) : -1;
            $list = [];
            foreach ($p->legal() as $m) {
                if ($from < 0 || $m->source === $from) {
                    $list[] = $p->san($m);
                }
            }
            sort($list, SORT_STRING);
            emit(implode(" ", array_merge(["legal", count($list)], $list)));
            break;
        case "STATUS":
            emit(
                implode(
                    " ",
                    array_merge(
                        [
                            "status",
                            $p->side === "w" ? "white" : "black",
                            $p->state(),
                            "rep",
                            $game->repetition(),
                        ],
                        $game->draws(),
                    ),
                ),
            );
            break;
        case "UNDO":
            if ($n > count($game->records)) {
                emit("ERROR cannot undo");
            } else {
                array_splice($game->records, -$n);
                array_splice($game->positions, -$n);
                emit("OK");
            }
            break;
        case "PERFT":
            $stats = array_fill(0, 7, 0);
            perft($p, $n, $stats);
            $words = ["perft", $n];
            foreach (
                ["nodes", "captures", "ep", "castles", "promotions", "checks", "mates"]
                as $i => $f
            ) {
                $words[] = $f;
                $words[] = $stats[$i];
            }
            emit(implode(" ", $words));
            break;
        case "DIVIDE":
            $rows = [];
            foreach ($p->legal() as $m) {
                $rows[] = [$p->san($m), perft($p->play($m), $n - 1)];
            }
            usort($rows, fn($x, $y) => strcmp($x[0], $y[0]));
            $total = 0;
            foreach ($rows as [$san, $count]) {
                emit($san . " " . $count);
                $total += $count;
            }
            emit("total " . $total);
            break;
        case "ATTACKS":
            $words = ["attacks", $a[0]];
            foreach (["w" => "white", "b" => "black"] as $c => $label) {
                $found = attackers($p->board, square($a[0]), $c);
                $words[] = $label;
                $words[] = count($found);
                foreach ($found as $s) {
                    $words[] = squareName($s);
                }
            }
            emit(implode(" ", $words));
            break;
        case "PINS":
            $pins = $p->pins();
            $words = ["pins", count($pins)];
            foreach ($pins as [$s, $t]) {
                $words[] = squareName($s) . "-" . squareName($t);
            }
            emit(implode(" ", $words));
            break;
        case "HISTORY":
            emit("history " . count($game->records));
            foreach ($game->records as $i => $r) {
                emit($i + 1 . " " . $r["uci"] . " " . $r["san"] . " " . $r["captured"]);
            }
            break;
        case "PGN":
            $result = $game->result();
            emit('[Result "' . $result . '"]');
            if ($game->loaded) {
                emit('[SetUp "1"]');
                emit('[FEN "' . $game->positions[0]->fen() . '"]');
            }
            $words = [];
            foreach ($game->records as $i => $r) {
                $q = $game->positions[$i];
                if ($q->side === "w") {
                    $words[] = $q->full . ".";
                } elseif ($i === 0) {
                    $words[] = $q->full . "...";
                }
                $words[] = $r["san"];
            }
            $words[] = $result;
            emit(implode(" ", $words));
            break;
    }
}
$lines = file("php://stdin", FILE_IGNORE_NEW_LINES);
$game = new Game();
for ($i = 1; $i <= (int) $lines[0]; $i++) {
    execute($game, $lines[$i]);
}
