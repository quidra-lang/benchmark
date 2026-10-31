<?php
declare(strict_types=1);
const SEATS = "NESW";
const SUITS = "CDSH";
const RANKS = "23456789TJQKA";
const STRATEGIES = ["BASIC", "LOW", "HIGH", "SMART", "MOON"];
const DIRECTIONS = ["L" => "LEFT", "R" => "RIGHT", "A" => "ACROSS", "H" => "HOLD"];
const DEFAULT_RULES = [
    "TARGET" => 100,
    "LIMIT" => 100,
    "MOON" => "ADD",
    "JACK" => "OFF",
    "QSBREAK" => "OFF",
    "BLOOD" => "OFF",
    "PASS" => "LRAH",
];
const QS = 36,
    KS = 37,
    AS_CARD = 38,
    JD = 22;
class CommandError extends RuntimeException {}
function failCommand(string $reason): never
{
    throw new CommandError($reason);
}
function suit(int $card): int
{
    return intdiv($card, 13);
}
function cardText(int $card): string
{
    return RANKS[$card % 13] . SUITS[suit($card)];
}
function cardsText(array $cards): string
{
    sort($cards, SORT_NUMERIC);
    return $cards ? implode(" ", array_map("cardText", $cards)) : "-";
}
function seatValue(string $word): int
{
    $seat = strpos(SEATS, $word);
    if (strlen($word) !== 1 || $seat === false) {
        failCommand("bad seat $word");
    }
    return $seat;
}
function cardValue(string $word): int
{
    if (
        strlen($word) !== 2 ||
        strpos(RANKS, $word[0]) === false ||
        strpos(SUITS, $word[1]) === false
    ) {
        failCommand("bad card $word");
    }
    return strpos(SUITS, $word[1]) * 13 + strpos(RANKS, $word[0]);
}
function bounded(string $word, int $low, int $high): int
{
    $value = (int) $word;
    if ($value < $low || $value > $high) {
        failCommand("bad value $word");
    }
    return $value;
}
function ordered(array $cards, bool $high = false): array
{
    usort(
        $cards,
        fn(int $a, int $b): int => ($high ? -1 : 1) * ($a % 13 <=> $b % 13) ?:
        suit($a) <=> suit($b),
    );
    return $cards;
}
function lowest(array $cards): int
{
    return ordered($cards)[0];
}
function highest(array $cards): int
{
    return ordered($cards, true)[0];
}
function penalty(int $card): bool
{
    return $card === QS || suit($card) === 3;
}
function pairs(string $label, array $values): string
{
    $parts = [$label];
    foreach ($values as $seat => $value) {
        $parts[] = SEATS[$seat];
        $parts[] = (string) $value;
    }
    return implode(" ", $parts);
}
function duplicateCards(array $cards): void
{
    $seen = [];
    foreach ($cards as $card) {
        if (isset($seen[$card])) {
            failCommand("duplicate card " . cardText($card));
        }
        $seen[$card] = true;
    }
}
class HeartsGenerator
{
    public function __construct(private int $state) {}
    public function shuffle(array &$deck): void
    {
        for ($i = count($deck) - 1; $i > 0; --$i) {
            $this->state = (48271 * $this->state) % 2147483647;
            $j = $this->state % ($i + 1);
            [$deck[$i], $deck[$j]] = [$deck[$j], $deck[$i]];
        }
    }
}
class Game
{
    public string $state = "between";
    public int $number = 0;
    public array $scores = [0, 0, 0, 0];
    public array $stats = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];
    public array $stacked = [],
        $history = [],
        $log = [],
        $record = [];
    public array $hands = [],
        $passes = [],
        $taken = [],
        $tricks = [],
        $current = [],
        $undo = [];
    private array $trickCounts = [];
    private int $leader = 0;
    private bool $broken = false;
    private string $passCode = "L";
    public function __construct(
        public array $rules,
        public array $bots,
        private HeartsGenerator $generator,
    ) {}
    public function point(int $card): int
    {
        if ($card === QS) {
            return 13;
        }
        if (suit($card) === 3) {
            return 1;
        }
        return $card === JD && $this->rules["JACK"] === "ON" ? -10 : 0;
    }
    public function points(array $cards): int
    {
        return array_sum(array_map($this->point(...), $cards));
    }
    private function write(int $level, string $line): void
    {
        $this->log[] = [$level, $line];
        if ($level > 0) {
            $this->record[] = $line;
        }
    }
    public function deal(): void
    {
        ++$this->number;
        $cycle = $this->rules["PASS"];
        $this->passCode = $cycle[($this->number - 1) % strlen($cycle)];
        $this->hands = [];
        for ($seat = 0; $seat < 4; ++$seat) {
            $this->hands[] = $this->stacked[$seat] ?? [];
        }
        $used = array_merge(...$this->hands);
        $deck = array_values(array_diff(range(0, 51), $used));
        $this->generator->shuffle($deck);
        $free = [];
        for ($seat = 0; $seat < 4; ++$seat) {
            if (!isset($this->stacked[$seat])) {
                $free[] = $seat;
            }
        }
        foreach ($deck as $i => $card) {
            $this->hands[$free[$i % count($free)]][] = $card;
        }
        $this->stacked = $this->passes = [];
        $this->taken = [[], [], [], []];
        $this->tricks = $this->current = $this->undo = $this->record = [];
        $this->trickCounts = [0, 0, 0, 0];
        $this->broken = false;
        $this->write(1, "hand {$this->number} pass " . DIRECTIONS[$this->passCode]);
        for ($seat = 0; $seat < 4; ++$seat) {
            $this->write(2, SEATS[$seat] . ": " . cardsText($this->hands[$seat]));
        }
        if ($this->passCode === "H") {
            $this->beginPlay();
        } else {
            $this->state = "passing";
        }
    }
    private function beginPlay(): void
    {
        $this->state = "playing";
        for ($seat = 0; $seat < 4; ++$seat) {
            if (in_array(0, $this->hands[$seat], true)) {
                $this->leader = $seat;
            }
        }
        $this->write(2, "lead " . SEATS[$this->leader]);
    }
    public function passCards(int $seat, array $cards): void
    {
        $this->hands[$seat] = array_values(array_diff($this->hands[$seat], $cards));
        $this->passes[$seat] = $cards;
        $this->write(2, SEATS[$seat] . " passes " . cardsText($cards));
        if (count($this->passes) !== 4) {
            return;
        }
        $offset = ["L" => 1, "R" => 3, "A" => 2][$this->passCode];
        foreach ($this->passes as $source => $passed) {
            $target = ($source + $offset) % 4;
            $this->hands[$target] = array_merge($this->hands[$target], $passed);
        }
        $this->beginPlay();
    }
    public function actor(): int
    {
        return ($this->leader + count($this->current)) % 4;
    }
    public function legal(): array
    {
        $hand = $this->hands[$this->actor()];
        if (!$this->current) {
            if (!$this->tricks) {
                return [0];
            }
            $safe = array_values(array_filter($hand, fn(int $c): bool => suit($c) !== 3));
            return !$this->broken && $safe ? $safe : $hand;
        }
        $led = suit($this->current[0][1]);
        $followers = array_values(array_filter($hand, fn(int $c): bool => suit($c) === $led));
        if ($followers) {
            return $followers;
        }
        if (!$this->tricks && $this->rules["BLOOD"] === "OFF") {
            $safe = array_values(array_filter($hand, fn(int $c): bool => !penalty($c)));
            if ($safe) {
                return $safe;
            }
        }
        return $hand;
    }
    public function choosePass(int $seat): array
    {
        $hand = $this->hands[$seat];
        $low = ordered($hand);
        $high = ordered($hand, true);
        $hearts = array_values(array_filter($high, fn(int $c): bool => suit($c) === 3));
        $special = array_values(
            array_filter([QS, KS, AS_CARD], fn(int $c): bool => in_array($c, $hand, true)),
        );
        switch ($this->bots[$seat]) {
            case "LOW":
                $order = $high;
                break;
            case "HIGH":
                $order = $low;
                break;
            case "MOON":
                $order = array_merge(
                    array_filter($low, fn(int $c): bool => suit($c) !== 3),
                    array_filter($low, fn(int $c): bool => suit($c) === 3),
                );
                break;
            case "SMART":
                $protected =
                    in_array(QS, $hand, true) &&
                    count(array_filter($hand, fn(int $c): bool => suit($c) === 2)) >= 5;
                $order = $protected ? [] : $special;
                $counts = [0, 0];
                foreach ($hand as $card) {
                    if (suit($card) < 2) {
                        ++$counts[suit($card)];
                    }
                }
                $chosen =
                    $counts[0] > 0 && ($counts[1] === 0 || $counts[0] <= $counts[1])
                        ? 0
                        : ($counts[1] > 0
                            ? 1
                            : -1);
                if ($chosen >= 0) {
                    $order = array_merge(
                        $order,
                        array_filter($high, fn(int $c): bool => suit($c) === $chosen),
                    );
                }
                $order = array_merge($order, $hearts, $high);
                break;
            default:
                $order = array_merge($special, $hearts, $high);
        }
        return array_slice(array_values(array_unique($order)), 0, 3);
    }
    private function queenPlayed(): bool
    {
        foreach ($this->taken as $cards) {
            if (in_array(QS, $cards, true)) {
                return true;
            }
        }
        foreach ($this->current as [$seat, $card]) {
            if ($card === QS) {
                return true;
            }
        }
        return false;
    }
    public function choosePlay(): int
    {
        $seat = $this->actor();
        $hand = $this->hands[$seat];
        $choices = $this->legal();
        $strategy = $this->bots[$seat];
        if ($strategy === "LOW") {
            return lowest($choices);
        }
        if ($strategy === "HIGH") {
            return highest($choices);
        }
        if ($strategy === "MOON") {
            for ($other = 0; $other < 4; ++$other) {
                if ($other !== $seat && array_filter($this->taken[$other], "penalty")) {
                    $strategy = "BASIC";
                }
            }
        }
        if (!$this->current) {
            if ($strategy === "SMART" && !$this->queenPlayed() && !in_array(QS, $hand, true)) {
                $small = array_filter($choices, fn(int $c): bool => suit($c) === 2 && $c % 13 < 10);
                if ($small) {
                    return lowest($small);
                }
            }
            $counts = [0, 0, 0, 0];
            foreach ($choices as $card) {
                ++$counts[suit($card)];
            }
            $suits = array_values(array_filter(range(0, 3), fn(int $s): bool => $counts[$s] > 0));
            usort(
                $suits,
                fn(int $a, int $b): int => ($strategy === "MOON" ? -1 : 1) *
                ($counts[$a] <=> $counts[$b]) ?:
                $a <=> $b,
            );
            $suited = array_filter($choices, fn(int $c): bool => suit($c) === $suits[0]);
            return $strategy === "MOON" ? highest($suited) : lowest($suited);
        }
        $led = suit($this->current[0][1]);
        if (array_filter($hand, fn(int $c): bool => suit($c) === $led)) {
            $winning = -1;
            foreach ($this->current as [$s, $c]) {
                if (suit($c) === $led) {
                    $winning = max($winning, $c % 13);
                }
            }
            $lower = array_filter($choices, fn(int $c): bool => $c % 13 < $winning);
            if ($strategy === "MOON") {
                $high = highest($choices);
                return $high % 13 > $winning ? $high : lowest($choices);
            }
            if ($lower) {
                return highest($lower);
            }
            if ($strategy === "SMART" && count($this->current) === 3) {
                $safe = array_diff($choices, [QS]);
                return $safe ? highest($safe) : QS;
            }
            return lowest($choices);
        }
        if ($strategy === "MOON") {
            $safe = array_filter($choices, fn(int $c): bool => !penalty($c));
            return lowest($safe ?: $choices);
        }
        if (in_array(QS, $choices, true)) {
            return QS;
        }
        if ($strategy === "SMART" && !$this->queenPlayed()) {
            if (in_array(AS_CARD, $choices, true)) {
                return AS_CARD;
            }
            if (in_array(KS, $choices, true)) {
                return KS;
            }
        }
        $hearts = array_filter($choices, fn(int $c): bool => suit($c) === 3);
        return highest($hearts ?: $choices);
    }
    public function winner(array $plays): int
    {
        $led = suit($plays[0][1]);
        $winner = $plays[0][0];
        $rank = -1;
        foreach ($plays as [$seat, $card]) {
            if (suit($card) === $led && $card % 13 > $rank) {
                $winner = $seat;
                $rank = $card % 13;
            }
        }
        return $winner;
    }
    public function trickLine(array $plays, int $number): string
    {
        $sequence = implode(
            " ",
            array_map(fn(array $p): string => SEATS[$p[0]] . " " . cardText($p[1]), $plays),
        );
        return "trick $number: $sequence -> " .
            SEATS[$this->winner($plays)] .
            " " .
            $this->points(array_column($plays, 1));
    }
    public function play(int $card): void
    {
        $seat = $this->actor();
        $fields = [
            $this->hands,
            $this->taken,
            $this->tricks,
            $this->trickCounts,
            $this->current,
            $this->leader,
            $this->broken,
            $this->record,
        ];
        $this->undo[] = [$fields, count($this->log), $seat, $card];
        $this->hands[$seat] = array_values(array_diff($this->hands[$seat], [$card]));
        $this->current[] = [$seat, $card];
        if (suit($card) === 3 || ($card === QS && $this->rules["QSBREAK"] === "ON")) {
            $this->broken = true;
        }
        if (count($this->current) !== 4) {
            return;
        }
        $winner = $this->winner($this->current);
        $this->taken[$winner] = array_merge($this->taken[$winner], array_column($this->current, 1));
        ++$this->trickCounts[$winner];
        $this->tricks[] = $this->current;
        $this->write(2, $this->trickLine($this->current, count($this->tricks)));
        $this->current = [];
        $this->leader = $winner;
        if (count($this->tricks) === 13) {
            $this->finishHand();
        }
    }
    public function undoCard(): array
    {
        [$fields, $length, $seat, $card] = array_pop($this->undo);
        [
            $this->hands,
            $this->taken,
            $this->tricks,
            $this->trickCounts,
            $this->current,
            $this->leader,
            $this->broken,
            $this->record,
        ] = $fields;
        $this->log = array_slice($this->log, 0, $length);
        return [$seat, $card];
    }
    public function claim(int $seat): void
    {
        $remaining = array_merge(...$this->hands);
        $count = 13 - count($this->tricks);
        $this->taken[$seat] = array_merge($this->taken[$seat], $remaining);
        $this->trickCounts[$seat] += $count;
        $this->hands = [[], [], [], []];
        $this->write(
            2,
            "claim " . SEATS[$seat] . " tricks $count points " . $this->points($remaining),
        );
        $this->finishHand();
    }
    public function ranking(): array
    {
        $seats = range(0, 3);
        usort(
            $seats,
            fn(int $a, int $b): int => $this->scores[$a] <=> $this->scores[$b] ?: $a <=> $b,
        );
        return $seats;
    }
    public function statsLines(): array
    {
        $output = [];
        foreach ($this->stats as $seat => $s) {
            $output[] =
                "stats " . SEATS[$seat] . " tricks $s[0] hearts $s[1] queens $s[2] moons $s[3]";
        }
        return $output;
    }
    private function finishHand(): void
    {
        $points = array_map($this->points(...), $this->taken);
        $shooter = null;
        for ($seat = 0; $seat < 4; ++$seat) {
            if (count(array_filter($this->taken[$seat], "penalty")) === 14) {
                $shooter = $seat;
            }
        }
        if ($shooter !== null) {
            $points[$shooter] -= 26;
            $method = $this->rules["MOON"];
            if ($method === "AUTO") {
                $add = [];
                for ($seat = 0; $seat < 4; ++$seat) {
                    $add[] = $this->scores[$seat] + $points[$seat] + ($seat === $shooter ? 0 : 26);
                }
                $ended =
                    $this->number >= $this->rules["LIMIT"] || max($add) >= $this->rules["TARGET"];
                $winner = 0;
                for ($seat = 1; $seat < 4; ++$seat) {
                    if ($add[$seat] < $add[$winner]) {
                        $winner = $seat;
                    }
                }
                $method = $ended && $winner !== $shooter ? "SUB" : "ADD";
            }
            if ($method === "SUB") {
                $points[$shooter] -= 26;
            } else {
                for ($seat = 0; $seat < 4; ++$seat) {
                    if ($seat !== $shooter) {
                        $points[$seat] += 26;
                    }
                };
            }
            $this->write(1, "moon " . SEATS[$shooter] . " $method");
        }
        for ($seat = 0; $seat < 4; ++$seat) {
            $this->scores[$seat] += $points[$seat];
            $this->stats[$seat][0] += $this->trickCounts[$seat];
            $this->stats[$seat][1] += count(
                array_filter($this->taken[$seat], fn(int $c): bool => suit($c) === 3),
            );
            $this->stats[$seat][2] += (int) in_array(QS, $this->taken[$seat], true);
            $this->stats[$seat][3] += (int) ($shooter === $seat);
        }
        $this->write(1, pairs("points", $points));
        $this->write(1, pairs("scores", $this->scores));
        $this->history[] = [
            "number" => $this->number,
            "direction" => DIRECTIONS[$this->passCode],
            "points" => $points,
            "shooter" => $shooter,
            "record" => $this->record,
        ];
        $ended =
            $this->number >= $this->rules["LIMIT"] || max($this->scores) >= $this->rules["TARGET"];
        $this->state = $ended ? "none" : "between";
        if (!$ended) {
            return;
        }
        $this->write(0, "game over hands {$this->number}");
        foreach ($this->ranking() as $i => $seat) {
            $this->write(0, "rank " . ($i + 1) . " " . SEATS[$seat] . " " . $this->scores[$seat]);
        }
        foreach ($this->statsLines() as $line) {
            $this->write(0, $line);
        }
    }
    public function autoPass(): void
    {
        for ($seat = 0; $seat < 4; ++$seat) {
            if (!isset($this->passes[$seat])) {
                $this->passCards($seat, $this->choosePass($seat));
            }
        }
    }
    public function autoHand(): void
    {
        if ($this->state === "passing") {
            $this->autoPass();
        }
        while ($this->state === "playing") {
            $this->play($this->choosePlay());
        }
    }
    public function autoGame(): void
    {
        if (in_array($this->state, ["passing", "playing"], true)) {
            $this->autoHand();
        }
        while ($this->state !== "none") {
            $this->deal();
            $this->autoHand();
        }
    }
}
class Table
{
    private array $rules = DEFAULT_RULES,
        $bots = ["BASIC", "BASIC", "BASIC", "BASIC"];
    private ?Game $game = null;
    private function active(): bool
    {
        return $this->game !== null && $this->game->state !== "none";
    }
    private function requireState(string $kind): void
    {
        if ($kind === "game" || $kind === "between") {
            if (!$this->active()) {
                failCommand("no game");
            }
            if ($kind === "between" && $this->game->state !== "between") {
                failCommand("hand in progress");
            }
        } elseif ($kind === "hand") {
            if (!$this->active() || !in_array($this->game->state, ["passing", "playing"], true)) {
                failCommand("no hand");
            }
        } elseif (!$this->active() || $this->game->state !== $kind) {
            failCommand("not $kind");
        }
    }
    private function ruleValue(string $name, string $word): int|string
    {
        if (!array_key_exists($name, $this->rules)) {
            failCommand("unknown rule $name");
        }
        if ($name === "TARGET" || $name === "LIMIT") {
            if (!preg_match('/^-?\d+$/D', $word)) {
                failCommand("bad value $word");
            }
            return bounded($word, 1, $name === "TARGET" ? 1000 : 100);
        }
        $good =
            $name === "PASS"
                ? (bool) preg_match('/^[LRAH]{1,8}$/D', $word)
                : in_array($word, $name === "MOON" ? ["ADD", "SUB", "AUTO"] : ["ON", "OFF"], true);
        if (!$good) {
            failCommand("bad value $word");
        }
        return $word;
    }
    private function simulate(string $command, int $seed, int $count): array
    {
        $generator = new HeartsGenerator($seed);
        if ($command === "GAME") {
            $game = new Game($this->rules, $this->bots, $generator);
            $game->autoGame();
            return array_merge(
                ["game seed $seed"],
                array_column(
                    array_filter($game->log, fn(array $entry): bool => $entry[0] <= $count),
                    1,
                ),
            );
        }
        $rounds = $command === "ROTATE" ? 4 : 1;
        $places = $stats = array_fill(0, 4, [0, 0, 0, 0]);
        $totals = [0, 0, 0, 0];
        $hands = 0;
        for ($rotation = 0; $rotation < $rounds; ++$rotation) {
            $strategies = array_fill(0, 4, "");
            for ($seat = 0; $seat < 4; ++$seat) {
                $strategies[($seat + $rotation) % 4] = $this->bots[$seat];
            }
            for ($i = 0; $i < $count; ++$i) {
                $game = new Game($this->rules, $strategies, $generator);
                $game->autoGame();
                $hands += $game->number;
                $ranking = $game->ranking();
                for ($original = 0; $original < 4; ++$original) {
                    $actual = ($original + $rotation) % 4;
                    ++$places[$original][array_search($actual, $ranking, true)];
                    $totals[$original] += $game->scores[$actual];
                    for ($k = 0; $k < 4; ++$k) {
                        $stats[$original][$k] += $game->stats[$actual][$k];
                    }
                }
            }
        }
        $games = $rounds * $count;
        $output = [strtolower($command) . " seed $seed games $games hands $hands"];
        for ($seat = 0; $seat < 4; ++$seat) {
            $numerator = 100 * $totals[$seat];
            $cents = intdiv($numerator, $games);
            if ($numerator < 0 && $numerator % $games !== 0) {
                --$cents;
            }
            $average =
                ($cents < 0 ? "-" : "") .
                intdiv(abs($cents), 100) .
                "." .
                sprintf("%02d", abs($cents) % 100);
            $name = SEATS[$seat] . ($command === "ROTATE" ? " " . $this->bots[$seat] : "");
            $s = $stats[$seat];
            $output[] =
                $name .
                " places " .
                implode(" ", $places[$seat]) .
                " total {$totals[$seat]} average $average tricks $s[0] hearts $s[1] queens $s[2] moons $s[3]";
        }
        return $output;
    }
    public function command(array $words): array
    {
        $command = array_shift($words);
        $args = $words;
        $known = explode(
            " ",
            "RULE BOT SETTINGS GAME MATCH ROTATE NEW ABANDON STACK DEAL SHOW PASS PLAY AUTO UNDO CLAIM LEGAL PREVIEW SCORE TAKEN TRICKS VOIDS UNSEEN STATS HISTORY REPLAY",
        );
        if (!in_array($command, $known, true)) {
            failCommand("unknown command $command");
        }
        switch ($command) {
            case "RULE":
                $value = $this->ruleValue($args[0], $args[1]);
                if ($this->active()) {
                    failCommand("game in progress");
                }
                $this->rules[$args[0]] = $value;
                return ["rule " . implode(" ", $args)];
            case "BOT":
                $seat = seatValue($args[0]);
                if (!in_array($args[1], STRATEGIES, true)) {
                    failCommand("bad value $args[1]");
                }
                $this->bots[$seat] = $args[1];
                if ($this->game !== null) {
                    $this->game->bots = $this->bots;
                }
                return ["bot " . implode(" ", $args)];
            case "SETTINGS":
                $parts = ["rules"];
                foreach ($this->rules as $key => $value) {
                    $parts[] = $key;
                    $parts[] = (string) $value;
                }
                return [implode(" ", $parts), pairs("bots", $this->bots)];
            case "GAME":
            case "MATCH":
            case "ROTATE":
                $seed = bounded($args[0], 1, 2147483646);
                [$low, $high] = ["GAME" => [0, 2], "MATCH" => [1, 50], "ROTATE" => [1, 10]][
                    $command
                ];
                return $this->simulate($command, $seed, bounded($args[1], $low, $high));
            case "NEW":
                $seed = bounded($args[0], 1, 2147483646);
                if ($this->active()) {
                    failCommand("game in progress");
                }
                $this->game = new Game($this->rules, $this->bots, new HeartsGenerator($seed));
                return ["new game seed $seed"];
            case "ABANDON":
                $this->requireState("game");
                $this->game = null;
                return ["game abandoned"];
        }
        $seat = null;
        $cards = [];
        if (in_array($command, ["STACK", "PASS", "PLAY", "CLAIM"], true)) {
            $seat = seatValue($args[0]);
        }
        if (in_array($command, ["STACK", "PASS", "PLAY"], true)) {
            $cards = array_map("cardValue", array_slice($args, 1));
        }
        if ($command === "STACK" && count($cards) !== 13) {
            failCommand("need 13 cards");
        }
        if (
            $command === "AUTO" &&
            !in_array($args[0], ["PASS", "CARD", "TRICK", "HAND", "GAME"], true)
        ) {
            failCommand("bad value $args[0]");
        }
        $kind = match ($command) {
            "STACK", "DEAL" => "between",
            "SHOW" => "hand",
            "PASS" => "passing",
            "SCORE", "STATS", "HISTORY", "REPLAY" => "game",
            "AUTO" => [
                "PASS" => "passing",
                "CARD" => "playing",
                "TRICK" => "playing",
                "HAND" => "hand",
                "GAME" => "game",
            ][$args[0]],
            default => "playing",
        };
        $this->requireState($kind);
        $game = $this->game;
        $before = count($game->log);
        $prefix = [];
        switch ($command) {
            case "STACK":
                duplicateCards($cards);
                foreach ($cards as $card) {
                    for ($other = 0; $other < 4; ++$other) {
                        if (
                            $other !== $seat &&
                            in_array($card, $game->stacked[$other] ?? [], true)
                        ) {
                            failCommand(cardText($card) . " stacked for " . SEATS[$other]);
                        }
                    };
                }
                $game->stacked[$seat] = $cards;
                return ["stacked " . SEATS[$seat]];
            case "DEAL":
                $game->deal();
                break;
            case "SHOW":
                return array_map(
                    fn(int $s): string => SEATS[$s] . ": " . cardsText($game->hands[$s]),
                    range(0, 3),
                );
            case "PASS":
                if (isset($game->passes[$seat])) {
                    failCommand(SEATS[$seat] . " already passed");
                }
                duplicateCards($cards);
                foreach ($cards as $card) {
                    if (!in_array($card, $game->hands[$seat], true)) {
                        failCommand(SEATS[$seat] . " does not hold " . cardText($card));
                    }
                }
                $game->passCards($seat, $cards);
                break;
            case "PLAY":
                $card = $cards[0];
                if ($seat !== $game->actor()) {
                    failCommand("waiting for " . SEATS[$game->actor()]);
                }
                if (!in_array($card, $game->hands[$seat], true)) {
                    failCommand(SEATS[$seat] . " does not hold " . cardText($card));
                }
                if (!in_array($card, $game->legal(), true)) {
                    if (!$game->current) {
                        failCommand(!$game->tricks ? "must lead 2C" : "hearts not broken");
                    }
                    $led = suit($game->current[0][1]);
                    if (array_filter($game->hands[$seat], fn(int $c): bool => suit($c) === $led)) {
                        failCommand("must follow " . SUITS[$led]);
                    }
                    failCommand("no points on first trick");
                }
                $prefix[] = SEATS[$seat] . " plays " . cardText($card);
                $game->play($card);
                break;
            case "AUTO":
                switch ($args[0]) {
                    case "PASS":
                        $game->autoPass();
                        break;
                    case "CARD":
                        $card = $game->choosePlay();
                        $prefix[] = SEATS[$game->actor()] . " plays " . cardText($card);
                        $game->play($card);
                        break;
                    case "TRICK":
                        $count = count($game->tricks);
                        while ($game->state === "playing" && count($game->tricks) === $count) {
                            $game->play($game->choosePlay());
                        }
                        break;
                    case "HAND":
                        $game->autoHand();
                        break;
                    case "GAME":
                        $game->autoGame();
                        break;
                }
                break;
            case "UNDO":
                if (!$game->undo) {
                    failCommand("nothing to undo");
                }
                [$s, $card] = $game->undoCard();
                return ["undo " . SEATS[$s] . " " . cardText($card)];
            case "CLAIM":
                if ($seat !== $game->actor()) {
                    failCommand("waiting for " . SEATS[$game->actor()]);
                }
                if ($game->current) {
                    failCommand("trick in progress");
                }
                foreach ($game->hands[$seat] as $card) {
                    for ($other = 0; $other < 4; ++$other) {
                        if ($other === $seat) {
                            continue;
                        }
                        foreach ($game->hands[$other] as $held) {
                            if (suit($held) === suit($card) && $held % 13 > $card % 13) {
                                failCommand("claim rejected");
                            }
                        }
                    };
                }
                $game->claim($seat);
                break;
            case "LEGAL":
                return [
                    "legal " .
                    SEATS[$game->actor()] .
                    ": " .
                    cardsText($game->legal()) .
                    " bot " .
                    cardText($game->choosePlay()),
                ];
            case "PREVIEW":
                $output = [];
                $choices = $game->legal();
                sort($choices, SORT_NUMERIC);
                foreach ($choices as $card) {
                    $copy = clone $game;
                    $count = count($copy->tricks);
                    $copy->play($card);
                    while ($copy->state === "playing" && count($copy->tricks) === $count) {
                        $copy->play($copy->choosePlay());
                    }
                    $trick = $copy->tricks[count($copy->tricks) - 1];
                    $output[] =
                        "preview " .
                        cardText($card) .
                        " -> " .
                        SEATS[$copy->winner($trick)] .
                        " " .
                        $copy->points(array_column($trick, 1));
                }
                return $output;
            case "SCORE":
                $output = [pairs("scores", $game->scores)];
                if ($game->state === "playing") {
                    $output[] = pairs("taken", array_map($game->points(...), $game->taken));
                }
                return $output;
            case "TAKEN":
                return array_map(
                    fn(int $s): string => SEATS[$s] .
                        ": " .
                        cardsText(
                            array_filter(
                                $game->taken[$s],
                                fn(int $c): bool => $game->point($c) !== 0,
                            ),
                        ),
                    range(0, 3),
                );
            case "TRICKS":
                $output = [];
                foreach ($game->tricks as $i => $trick) {
                    $output[] = $game->trickLine($trick, $i + 1);
                }
                if ($game->current) {
                    $output[] =
                        "current: " .
                        implode(
                            " ",
                            array_map(
                                fn(array $p): string => SEATS[$p[0]] . " " . cardText($p[1]),
                                $game->current,
                            ),
                        );
                }
                return $output ?: ["no tricks"];
            case "VOIDS":
                $voids = [[], [], [], []];
                $tricks = $game->tricks;
                if ($game->current) {
                    $tricks[] = $game->current;
                }
                foreach ($tricks as $trick) {
                    $led = suit($trick[0][1]);
                    foreach ($trick as [$s, $card]) {
                        if (suit($card) !== $led) {
                            $voids[$s][$led] = true;
                        }
                    }
                }
                $values = [];
                foreach ($voids as $missing) {
                    ksort($missing);
                    $values[] = $missing
                        ? implode(
                            "",
                            array_map(fn(int $s): string => SUITS[$s], array_keys($missing)),
                        )
                        : "-";
                }
                return [pairs("voids", $values)];
            case "UNSEEN":
                $played = array_merge(...$game->taken);
                $played = array_merge($played, array_column($game->current, 1));
                return [
                    "unseen " .
                    SEATS[$game->actor()] .
                    ": " .
                    cardsText(
                        array_values(
                            array_diff(range(0, 51), $game->hands[$game->actor()], $played),
                        ),
                    ),
                ];
            case "STATS":
                return $game->statsLines();
            case "HISTORY":
                $output = [];
                foreach ($game->history as $hand) {
                    $line =
                        "hand {$hand["number"]} pass {$hand["direction"]} " .
                        pairs("points", $hand["points"]);
                    if ($hand["shooter"] !== null) {
                        $line .= " moon " . SEATS[$hand["shooter"]];
                    }
                    $output[] = $line;
                }
                return $output ?: ["no hands"];
            case "REPLAY":
                $hand = (int) $args[0];
                if ($hand < 1 || $hand > count($game->history)) {
                    failCommand("bad value $args[0]");
                }
                return $game->history[$hand - 1]["record"];
        }
        return array_merge($prefix, array_column(array_slice($game->log, $before), 1));
    }
}
$table = new Table();
$count = (int) trim(fgets(STDIN));
for ($i = 0; $i < $count; ++$i) {
    try {
        $output = $table->command(explode(" ", rtrim(fgets(STDIN), "\r\n")));
    } catch (CommandError $error) {
        $output = ["error: " . $error->getMessage()];
    }
    foreach ($output as $line) {
        echo $line, "\n";
    }
}
