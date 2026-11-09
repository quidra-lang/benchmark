<?php
declare(strict_types=1);

enum Phase: string
{
    case Setup = "SETUP";
    case Battle = "BATTLE";
    case Over = "OVER";
}
enum Strategy: string
{
    case Hunt = "HUNT";
    case Prob = "PROB";
    case Random = "RANDOM";
}
enum ViewKind: string
{
    case Reef = "~";
    case Unattacked = ".";
    case Miss = "o";
    case Hit = "x";
    case Sunk = "#";
}
enum ShotKind: string
{
    case Already = "ALREADY";
    case Miss = "MISS";
    case Hit = "HIT";
    case Sunk = "SUNK";
}
enum LogMode
{
    case Normal;
    case Sinks;
    case Silent;
}

const SHIP_NAMES = ["CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"];
const SHIP_LENGTHS = [5, 4, 3, 3, 2];
const SHIP_SYMBOLS = "CBRSD";
const LINE_DIRECTIONS = [[0, 1], [1, 0]];
const STACK_DIRECTIONS = [[0, -1], [1, 0], [0, 1], [-1, 0]];

final class CommandError extends RuntimeException {}
final readonly class Choice
{
    public function __construct(public int $cell, public string $info) {}
}
final readonly class Shot
{
    public function __construct(public ShotKind $kind, public int $ship = -1) {}
    public function isHit(): bool
    {
        return $this->kind === ShotKind::Hit || $this->kind === ShotKind::Sunk;
    }
    public function text(): string
    {
        return $this->kind === ShotKind::Sunk
            ? "SUNK " . SHIP_NAMES[$this->ship]
            : $this->kind->value;
    }
}

function coordinate(int $cell): string
{
    return chr(65 + intdiv($cell, 10)) . (($cell % 10) + 1);
}
function parseCell(string $text): int
{
    return (ord($text[0]) - 65) * 10 + (int) substr($text, 1) - 1;
}
function shipRange(array $cells): string
{
    return coordinate($cells[0]) . "-" . coordinate($cells[count($cells) - 1]);
}
function advance(int $state): int
{
    return (48271 * $state) % 2147483647;
}
function switchName(bool $enabled): string
{
    return $enabled ? "ON" : "OFF";
}
function step(int $cell, int $dr, int $dc): int
{
    $row = intdiv($cell, 10) + $dr;
    $column = ($cell % 10) + $dc;
    return $row >= 0 && $row < 10 && $column >= 0 && $column < 10 ? $row * 10 + $column : -1;
}
function surroundings(int $cell): array
{
    static $cache = null;
    if ($cache === null) {
        $cache = array_fill(0, 100, []);
        for ($at = 0; $at < 100; $at++) {
            for ($dr = -1; $dr <= 1; $dr++) {
                for ($dc = -1; $dc <= 1; $dc++) {
                    if ($dr === 0 && $dc === 0) {
                        continue;
                    }
                    $neighbor = step($at, $dr, $dc);
                    if ($neighbor >= 0) {
                        $cache[$at][] = $neighbor;
                    }
                }
            }
        }
    }
    return $cache[$cell];
}
function positions(int $start, bool $horizontal, int $length): ?array
{
    if (($horizontal ? $start % 10 : intdiv($start, 10)) + $length > 10) {
        return null;
    }
    $cells = [];
    for ($i = 0; $i < $length; $i++) {
        $cells[] = $start + $i * ($horizontal ? 1 : 10);
    }
    return $cells;
}
function touching(array $first, array $second): bool
{
    foreach ($first as $cell) {
        foreach (surroundings($cell) as $neighbor) {
            if (in_array($neighbor, $second, true)) {
                return true;
            }
        }
    }
    return false;
}

final class Player
{
    public array $ships = [[], [], [], [], []];
    public array $owner;
    public array $attacked;
    public array $candidates = [];
    public ?Strategy $controller = null;
    public bool $torpedoUsed = false,
        $sonarUsed = false;
    public int $shots = 0,
        $hits = 0,
        $sinks = 0,
        $turns = 0,
        $streak = 0,
        $bestStreak = 0,
        $wins = 0;
    public function __construct(public int $random)
    {
        $this->owner = array_fill(0, 100, -1);
        $this->attacked = array_fill(0, 100, false);
    }
    public function sunk(int $ship): bool
    {
        if ($this->ships[$ship] === []) {
            return false;
        }
        foreach ($this->ships[$ship] as $cell) {
            if (!$this->attacked[$cell]) {
                return false;
            }
        }
        return true;
    }
    public function placed(): int
    {
        return count(array_filter($this->ships, static fn(array $cells): bool => $cells !== []));
    }
    public function afloat(): int
    {
        $count = 0;
        for ($ship = 0; $ship < 5; $ship++) {
            if ($this->ships[$ship] !== [] && !$this->sunk($ship)) {
                $count++;
            }
        }
        return $count;
    }
    public function setShip(int $ship, array $cells): void
    {
        foreach ($this->ships[$ship] as $cell) {
            $this->owner[$cell] = -1;
        }
        $this->ships[$ship] = $cells;
        foreach ($cells as $cell) {
            $this->owner[$cell] = $ship;
        }
    }
    public function clearFleet(): void
    {
        $this->ships = [[], [], [], [], []];
        $this->owner = array_fill(0, 100, -1);
    }
    public function record(Shot $result): void
    {
        $this->shots++;
        if ($result->isHit()) {
            $this->hits++;
            $this->streak++;
            $this->bestStreak = max($this->bestStreak, $this->streak);
        } else {
            $this->streak = 0;
        }
        if ($result->kind === ShotKind::Sunk) {
            $this->sinks++;
        }
    }
}

final readonly class View
{
    public function __construct(
        public array $cells,
        public array $excluded,
        public array $remaining,
    ) {}
    public function candidate(int $cell): bool
    {
        return $cell >= 0 &&
            $cell < 100 &&
            $this->cells[$cell] === ViewKind::Unattacked &&
            !$this->excluded[$cell];
    }
}

final class Game
{
    public array $players;
    public array $reefs;
    public bool $salvo = false,
        $chain = false,
        $touch = false;
    public Phase $phase = Phase::Setup;
    public int $current = 0,
        $winner = -1;
    public function __construct()
    {
        $this->players = [new Player(1), new Player(2)];
        $this->reefs = array_fill(0, 100, false);
    }
    public function allowance(int $player): int
    {
        return $this->salvo ? $this->players[$player]->afloat() : 1;
    }
    public function setupCheck(): void
    {
        if ($this->phase !== Phase::Setup) {
            throw new CommandError("setup closed");
        }
    }
    public function turnCheck(int $player): void
    {
        if ($this->phase === Phase::Over) {
            throw new CommandError("game over");
        }
        if (
            $this->phase === Phase::Setup &&
            ($this->players[0]->placed() !== 5 || $this->players[1]->placed() !== 5)
        ) {
            throw new CommandError("fleets not ready");
        }
        if ($player !== $this->current) {
            throw new CommandError("not your turn");
        }
    }
    public function placementProblem(int $player, ?array $cells): ?string
    {
        if ($cells === null) {
            return "out of bounds";
        }
        foreach ($cells as $cell) {
            if ($this->reefs[$cell]) {
                return "on reef";
            }
        }
        $first = 5;
        foreach ($cells as $cell) {
            $ship = $this->players[$player]->owner[$cell];
            if ($ship >= 0) {
                $first = min($first, $ship);
            }
        }
        if ($first < 5) {
            return "overlaps " . SHIP_NAMES[$first];
        }
        if (!$this->touch) {
            foreach ($cells as $cell) {
                foreach (surroundings($cell) as $neighbor) {
                    $ship = $this->players[$player]->owner[$neighbor];
                    if ($ship >= 0) {
                        $first = min($first, $ship);
                    }
                }
            }
            if ($first < 5) {
                return "touches " . SHIP_NAMES[$first];
            }
        }
        return null;
    }
    public function autoPlace(int $player, int $seed): int
    {
        $owner = $this->players[$player];
        $owner->random = $seed;
        $owner->clearFleet();
        $attempts = 0;
        for ($ship = 0; $ship < 5; $ship++) {
            while (true) {
                $attempts++;
                $length = SHIP_LENGTHS[$ship];
                $owner->random = advance($owner->random);
                $horizontal = $owner->random % 2 === 0;
                $owner->random = advance($owner->random);
                $k = $owner->random % (10 * (11 - $length));
                $start = $horizontal ? intdiv($k, 11 - $length) * 10 + ($k % (11 - $length)) : $k;
                $cells = positions($start, $horizontal, $length);
                if ($this->placementProblem($player, $cells) !== null) {
                    continue;
                }
                $owner->setShip($ship, $cells);
                break;
            }
        }
        return $attempts;
    }
    public function layout(int $player, string $text): void
    {
        $grid = str_replace("/", "", $text);
        $fleet = [];
        for ($ship = 0; $ship < 5; $ship++) {
            $cells = [];
            for ($cell = 0; $cell < 100; $cell++) {
                if ($grid[$cell] === SHIP_SYMBOLS[$ship]) {
                    $cells[] = $cell;
                }
            }
            $name = SHIP_NAMES[$ship];
            $length = SHIP_LENGTHS[$ship];
            if (count($cells) !== $length) {
                throw new CommandError("$name has " . count($cells) . " cells");
            }
            $horizontal = true;
            $vertical = true;
            for ($i = 0; $i < $length; $i++) {
                $horizontal =
                    $horizontal &&
                    $cells[$i] === $cells[0] + $i &&
                    intdiv($cells[$i], 10) === intdiv($cells[0], 10);
                $vertical = $vertical && $cells[$i] === $cells[0] + 10 * $i;
            }
            if (!$horizontal && !$vertical) {
                throw new CommandError("$name not straight");
            }
            foreach ($cells as $cell) {
                if ($this->reefs[$cell]) {
                    throw new CommandError("$name on reef");
                }
            }
            $fleet[] = $cells;
        }
        if (!$this->touch) {
            for ($first = 0; $first < 5; $first++) {
                for ($second = $first + 1; $second < 5; $second++) {
                    if (touching($fleet[$first], $fleet[$second])) {
                        throw new CommandError(
                            SHIP_NAMES[$first] . " touches " . SHIP_NAMES[$second],
                        );
                    }
                }
            }
        }
        $this->players[$player]->clearFleet();
        foreach ($fleet as $ship => $cells) {
            $this->players[$player]->setShip($ship, $cells);
        }
    }
    public function placedLines(int $player, array &$output): void
    {
        foreach ($this->players[$player]->ships as $ship => $cells) {
            $output[] =
                "PLACED " . ($player + 1) . " " . SHIP_NAMES[$ship] . " " . shipRange($cells);
        }
    }
    public function view(int $player): View
    {
        $opponent = $this->players[1 - $player];
        $sunk = [];
        $remaining = [];
        for ($ship = 0; $ship < 5; $ship++) {
            $sunk[$ship] = $opponent->sunk($ship);
            if (!$sunk[$ship]) {
                $remaining[] = $ship;
            }
        }
        $cells = [];
        for ($cell = 0; $cell < 100; $cell++) {
            $ship = $opponent->owner[$cell];
            $cells[] = $this->reefs[$cell]
                ? ViewKind::Reef
                : (!$opponent->attacked[$cell]
                    ? ViewKind::Unattacked
                    : ($ship < 0
                        ? ViewKind::Miss
                        : ($sunk[$ship]
                            ? ViewKind::Sunk
                            : ViewKind::Hit)));
        }
        $excluded = array_fill(0, 100, false);
        if (!$this->touch) {
            foreach ($cells as $cell => $kind) {
                if ($kind === ViewKind::Sunk) {
                    foreach (surroundings($cell) as $neighbor) {
                        $excluded[$neighbor] = true;
                    };
                }
            }
        }
        return new View($cells, $excluded, $remaining);
    }
    public static function scores(View $view): array
    {
        $scores = array_fill(0, 100, 0);
        foreach ($view->remaining as $ship) {
            for ($start = 0; $start < 100; $start++) {
                foreach ([true, false] as $horizontal) {
                    $cells = positions($start, $horizontal, SHIP_LENGTHS[$ship]);
                    if ($cells === null) {
                        continue;
                    }
                    $possible = true;
                    $hits = 0;
                    foreach ($cells as $cell) {
                        if (
                            $view->excluded[$cell] ||
                            ($view->cells[$cell] !== ViewKind::Unattacked &&
                                $view->cells[$cell] !== ViewKind::Hit)
                        ) {
                            $possible = false;
                        }
                        if ($view->cells[$cell] === ViewKind::Hit) {
                            $hits++;
                        }
                    }
                    if ($possible) {
                        foreach ($cells as $cell) {
                            $scores[$cell] += 1 + 10 * $hits;
                        };
                    }
                }
            }
        }
        return $scores;
    }
    public static function best(View $view, array $scores): int
    {
        $chosen = -1;
        foreach ($view->cells as $cell => $kind) {
            if (
                $kind === ViewKind::Unattacked &&
                ($chosen < 0 || $scores[$cell] > $scores[$chosen])
            ) {
                $chosen = $cell;
            }
        }
        return $chosen;
    }
    public function choose(int $player, Strategy $strategy, bool $advanceRandom = true): Choice
    {
        $view = $this->view($player);
        if ($strategy === Strategy::Prob) {
            $scores = self::scores($view);
            $cell = self::best($view, $scores);
            return new Choice($cell, (string) $scores[$cell]);
        }
        if ($strategy === Strategy::Random) {
            $candidates = [];
            for ($cell = 0; $cell < 100; $cell++) {
                if ($view->candidate($cell)) {
                    $candidates[] = $cell;
                }
            }
            $random = advance($this->players[$player]->random);
            if ($advanceRandom) {
                $this->players[$player]->random = $random;
            }
            return new Choice(
                $candidates[$random % count($candidates)],
                (string) count($candidates),
            );
        }
        foreach ($view->cells as $cell => $kind) {
            if ($kind !== ViewKind::Hit) {
                continue;
            }
            foreach (LINE_DIRECTIONS as [$dr, $dc]) {
                $front = step($cell, $dr, $dc);
                if ($front < 0 || $view->cells[$front] !== ViewKind::Hit) {
                    continue;
                }
                while ($front >= 0 && $view->cells[$front] === ViewKind::Hit) {
                    $front = step($front, $dr, $dc);
                }
                $back = step($cell, -$dr, -$dc);
                if ($view->candidate($front)) {
                    return new Choice($front, "LINE");
                }
                if ($view->candidate($back)) {
                    return new Choice($back, "LINE");
                }
            }
        }
        $stack = $this->players[$player]->candidates;
        for ($i = count($stack) - 1; $i >= 0; $i--) {
            if ($view->candidate($stack[$i])) {
                return new Choice($stack[$i], "STACK");
            }
        }
        $shortest = min(
            array_map(static fn(int $ship): int => SHIP_LENGTHS[$ship], $view->remaining),
        );
        for ($cell = 0; $cell < 100; $cell++) {
            if ($view->candidate($cell) && (intdiv($cell, 10) + ($cell % 10)) % $shortest === 0) {
                return new Choice($cell, "PARITY");
            }
        }
        throw new LogicException("No strategy candidate");
    }
    public function shoot(int $player, int $cell): Shot
    {
        $owner = $this->players[$player];
        $opponent = $this->players[1 - $player];
        if ($opponent->attacked[$cell]) {
            $result = new Shot(ShotKind::Already);
        } else {
            $opponent->attacked[$cell] = true;
            $ship = $opponent->owner[$cell];
            $result =
                $ship < 0
                    ? new Shot(ShotKind::Miss)
                    : ($opponent->sunk($ship)
                        ? new Shot(ShotKind::Sunk, $ship)
                        : new Shot(ShotKind::Hit));
            if ($result->kind === ShotKind::Hit) {
                foreach (STACK_DIRECTIONS as [$dr, $dc]) {
                    $neighbor = step($cell, $dr, $dc);
                    if ($neighbor >= 0) {
                        $owner->candidates[] = $neighbor;
                    }
                }
            }
        }
        $owner->record($result);
        return $result;
    }
    private function finishTurn(int $player, bool $hit, LogMode $mode, array &$output): void
    {
        $this->players[$player]->turns++;
        if ($this->players[1 - $player]->afloat() === 0) {
            $this->phase = Phase::Over;
            $this->winner = $player;
            $this->players[$player]->wins++;
            if ($mode === LogMode::Normal) {
                $output[] = "WINNER " . ($player + 1);
            }
        } else {
            $this->current = $this->chain && $hit ? $player : 1 - $player;
        }
    }
    public function shootingTurn(
        int $player,
        ?Strategy $strategy,
        array $targets,
        LogMode $mode,
        array &$output,
    ): void {
        $count = $this->allowance($player);
        $this->phase = Phase::Battle;
        $hit = false;
        for ($i = 0; $i < $count; $i++) {
            $cell = $strategy === null ? $targets[$i] : $this->choose($player, $strategy)->cell;
            $result = $this->shoot($player, $cell);
            $hit = $hit || $result->isHit();
            if ($mode === LogMode::Normal) {
                $output[] =
                    "SHOT " . ($player + 1) . " " . coordinate($cell) . " " . $result->text();
            }
            if ($mode === LogMode::Sinks && $result->kind === ShotKind::Sunk) {
                $output[] =
                    "SINK " .
                    ($player + 1) .
                    " " .
                    SHIP_NAMES[$result->ship] .
                    " " .
                    $this->players[$player]->shots;
            }
            if ($this->players[1 - $player]->afloat() === 0) {
                break;
            }
        }
        $this->finishTurn($player, $hit, $mode, $output);
    }
    public function torpedo(int $player, int $row, bool $west, array &$output): void
    {
        $this->phase = Phase::Battle;
        $this->players[$player]->torpedoUsed = true;
        $opponent = $this->players[1 - $player];
        $result = "MISS";
        $stoppedAtShip = false;
        $hit = false;
        for ($i = 0; $i < 10; $i++) {
            $cell = $row * 10 + ($west ? $i : 9 - $i);
            if ($this->reefs[$cell]) {
                $result = "REEF " . coordinate($cell);
                break;
            }
            if ($opponent->owner[$cell] >= 0) {
                $shot = $this->shoot($player, $cell);
                $result = $shot->text() . " " . coordinate($cell);
                $hit = $shot->isHit();
                $stoppedAtShip = true;
                break;
            }
            $opponent->attacked[$cell] = true;
        }
        if (!$stoppedAtShip) {
            $this->players[$player]->record(new Shot(ShotKind::Miss));
        }
        $output[] =
            "TORPEDO " .
            ($player + 1) .
            " " .
            chr(65 + $row) .
            " " .
            ($west ? "W" : "E") .
            " " .
            $result;
        $this->finishTurn($player, $hit, LogMode::Normal, $output);
    }
    public function sonar(int $player, int $cell, array &$output): void
    {
        $this->phase = Phase::Battle;
        $this->players[$player]->sonarUsed = true;
        $opponent = $this->players[1 - $player];
        $count = 0;
        foreach ([$cell, ...surroundings($cell)] as $at) {
            if ($opponent->owner[$at] >= 0 && !$opponent->attacked[$at]) {
                $count++;
            }
        }
        $output[] = "SONAR " . ($player + 1) . " " . coordinate($cell) . " " . $count;
        $this->finishTurn($player, false, LogMode::Normal, $output);
    }
    public function automatic(array &$output): void
    {
        while (
            $this->phase === Phase::Battle &&
            $this->players[$this->current]->controller !== null
        ) {
            $this->shootingTurn(
                $this->current,
                $this->players[$this->current]->controller,
                [],
                LogMode::Normal,
                $output,
            );
        }
    }
    public function show(int $player, bool $radar, array &$output): void
    {
        $output[] = ($radar ? "RADAR " : "BOARD ") . ($player + 1);
        $output[] = "  1 2 3 4 5 6 7 8 9 10";
        $view = $radar ? $this->view($player) : null;
        $owner = $this->players[$player];
        for ($row = 0; $row < 10; $row++) {
            $symbols = [];
            for ($column = 0; $column < 10; $column++) {
                $cell = $row * 10 + $column;
                $ship = $owner->owner[$cell];
                if ($view !== null) {
                    $symbol = $view->cells[$cell]->value;
                } elseif ($this->reefs[$cell]) {
                    $symbol = "~";
                } elseif ($ship >= 0) {
                    $symbol = $owner->attacked[$cell]
                        ? strtolower(SHIP_SYMBOLS[$ship])
                        : SHIP_SYMBOLS[$ship];
                } else {
                    $symbol = $owner->attacked[$cell] ? "o" : ".";
                }
                $symbols[] = $symbol;
            }
            $output[] = chr(65 + $row) . " " . implode(" ", $symbols);
        }
    }
    public function density(int $player, array &$output): void
    {
        $view = $this->view($player);
        $scores = self::scores($view);
        $output[] = "DENSITY " . ($player + 1);
        $header = " ";
        for ($column = 1; $column <= 10; $column++) {
            $header .= str_pad((string) $column, 5, " ", STR_PAD_LEFT);
        }
        $output[] = $header;
        for ($row = 0; $row < 10; $row++) {
            $text = chr(65 + $row);
            for ($column = 0; $column < 10; $column++) {
                $cell = $row * 10 + $column;
                $value =
                    $view->cells[$cell] === ViewKind::Unattacked
                        ? (string) $scores[$cell]
                        : ($view->cells[$cell] === ViewKind::Reef
                            ? "~"
                            : "-");
                $text .= str_pad($value, 5, " ", STR_PAD_LEFT);
            }
            $output[] = $text;
        }
        $cell = self::best($view, $scores);
        $output[] = "BEST " . coordinate($cell) . " " . $scores[$cell];
    }
    public function fleet(int $player, array &$output): void
    {
        $owner = $this->players[$player];
        $output[] = "FLEET " . ($player + 1) . " afloat " . $owner->afloat();
        foreach ($owner->ships as $ship => $cells) {
            if ($cells === []) {
                $output[] = SHIP_NAMES[$ship] . " unplaced";
            } else {
                $count = 0;
                foreach ($cells as $cell) {
                    if ($owner->attacked[$cell]) {
                        $count++;
                    }
                }
                $output[] =
                    SHIP_NAMES[$ship] .
                    " " .
                    shipRange($cells) .
                    " $count/" .
                    SHIP_LENGTHS[$ship] .
                    " " .
                    ($owner->sunk($ship) ? "SUNK" : "AFLOAT");
            }
        }
    }
    public function exportFleet(int $player): string
    {
        $rows = [];
        for ($row = 0; $row < 10; $row++) {
            $text = "";
            for ($column = 0; $column < 10; $column++) {
                $ship = $this->players[$player]->owner[$row * 10 + $column];
                $text .= $ship < 0 ? "." : SHIP_SYMBOLS[$ship];
            }
            $rows[] = $text;
        }
        return implode("/", $rows);
    }
    public function status(): string
    {
        $text =
            "STATUS " .
            $this->phase->value .
            " salvo " .
            switchName($this->salvo) .
            " chain " .
            switchName($this->chain) .
            " touch " .
            switchName($this->touch) .
            " reefs " .
            count(array_filter($this->reefs));
        if ($this->phase === Phase::Setup) {
            return $text .
                " placed " .
                $this->players[0]->placed() .
                " " .
                $this->players[1]->placed();
        }
        $turn =
            $this->phase === Phase::Battle
                ? " turn " . ($this->current + 1) . " shots " . $this->allowance($this->current)
                : " winner " . ($this->winner + 1);
        return $text .
            $turn .
            " afloat " .
            $this->players[0]->afloat() .
            " " .
            $this->players[1]->afloat();
    }
    public function stats(array &$output): void
    {
        foreach ($this->players as $i => $player) {
            $accuracy =
                $player->shots === 0 ? "-" : intdiv($player->hits * 100, $player->shots) . "%";
            $output[] =
                "STATS " .
                ($i + 1) .
                " shots {$player->shots} hits {$player->hits} sunk {$player->sinks} turns {$player->turns} streak {$player->bestStreak} accuracy $accuracy wins {$player->wins}";
        }
    }
    public function playMatch(
        int $firstSeed,
        int $secondSeed,
        Strategy $first,
        Strategy $second,
        array &$output,
        LogMode $mode = LogMode::Silent,
    ): Game {
        $game = new Game();
        $game->salvo = $this->salvo;
        $game->chain = $this->chain;
        $game->touch = $this->touch;
        $game->reefs = $this->reefs;
        $game->autoPlace(0, $firstSeed);
        $game->autoPlace(1, $secondSeed);
        $game->phase = Phase::Battle;
        $strategies = [$first, $second];
        while ($game->phase === Phase::Battle) {
            $game->shootingTurn($game->current, $strategies[$game->current], [], $mode, $output);
        }
        return $game;
    }
}

final class Program
{
    private Game $game;
    private const SETUP_COMMANDS = [
        "PLACE",
        "REMOVE",
        "AUTOPLACE",
        "LAYOUT",
        "REEF",
        "SALVO",
        "CHAIN",
        "TOUCH",
    ];
    private const TURN_COMMANDS = ["FIRE", "AI", "TORPEDO", "SONAR"];
    public function __construct()
    {
        $this->game = new Game();
    }
    public function execute(array $words): array
    {
        $command = $words[0];
        $output = [];
        $game = $this->game;
        if (in_array($command, self::SETUP_COMMANDS, true)) {
            $game->setupCheck();
        }
        if (in_array($command, self::TURN_COMMANDS, true)) {
            $player = (int) $words[1] - 1;
            $game->turnCheck($player);
            switch ($command) {
                case "FIRE":
                    $cells = array_map("parseCell", array_slice($words, 2));
                    if (count($cells) !== $game->allowance($player)) {
                        throw new CommandError("expected " . $game->allowance($player) . " shots");
                    }
                    foreach ($cells as $cell) {
                        if ($game->reefs[$cell]) {
                            throw new CommandError("reef at " . coordinate($cell));
                        }
                    }
                    $game->shootingTurn($player, null, $cells, LogMode::Normal, $output);
                    break;
                case "AI":
                    $game->shootingTurn(
                        $player,
                        Strategy::from($words[2]),
                        [],
                        LogMode::Normal,
                        $output,
                    );
                    break;
                case "TORPEDO":
                    if ($game->players[$player]->torpedoUsed) {
                        throw new CommandError("torpedo used");
                    }
                    $game->torpedo($player, ord($words[2]) - 65, $words[3] === "W", $output);
                    break;
                case "SONAR":
                    if ($game->players[$player]->sonarUsed) {
                        throw new CommandError("sonar used");
                    }
                    $game->sonar($player, parseCell($words[2]), $output);
                    break;
            }
            $game->automatic($output);
            return $output;
        }
        switch ($command) {
            case "NEW":
                $wins = [$game->players[0]->wins, $game->players[1]->wins];
                $this->game = new Game();
                foreach ($wins as $i => $count) {
                    $this->game->players[$i]->wins = $count;
                }
                $output[] = "NEW";
                break;
            case "PLACE":
                $player = (int) $words[1] - 1;
                $ship = array_search($words[2], SHIP_NAMES, true);
                if ($game->players[$player]->ships[$ship] !== []) {
                    throw new CommandError($words[2] . " already placed");
                }
                $cells = positions(parseCell($words[3]), $words[4] === "H", SHIP_LENGTHS[$ship]);
                $problem = $game->placementProblem($player, $cells);
                if ($problem !== null) {
                    throw new CommandError($problem);
                }
                $game->players[$player]->setShip($ship, $cells);
                $output[] = "PLACED " . ($player + 1) . " " . $words[2] . " " . shipRange($cells);
                break;
            case "REMOVE":
                $player = (int) $words[1] - 1;
                $ship = array_search($words[2], SHIP_NAMES, true);
                if ($game->players[$player]->ships[$ship] === []) {
                    throw new CommandError($words[2] . " not placed");
                }
                $game->players[$player]->setShip($ship, []);
                $output[] = "REMOVED " . ($player + 1) . " " . $words[2];
                break;
            case "AUTOPLACE":
                $player = (int) $words[1] - 1;
                $attempts = $game->autoPlace($player, (int) $words[2]);
                $output[] = "AUTOPLACE " . ($player + 1) . " attempts " . $attempts;
                $game->placedLines($player, $output);
                break;
            case "LAYOUT":
                $player = (int) $words[1] - 1;
                $game->layout($player, $words[2]);
                $output[] = "LAYOUT " . ($player + 1);
                $game->placedLines($player, $output);
                break;
            case "REEF":
                $cell = parseCell($words[1]);
                if ($game->reefs[$cell]) {
                    throw new CommandError("reef exists at " . coordinate($cell));
                }
                for ($player = 0; $player < 2; $player++) {
                    $ship = $game->players[$player]->owner[$cell];
                    if ($ship >= 0) {
                        throw new CommandError(
                            coordinate($cell) .
                                " occupied by " .
                                ($player + 1) .
                                " " .
                                SHIP_NAMES[$ship],
                        );
                    }
                }
                $game->reefs[$cell] = true;
                $output[] = "REEF " . coordinate($cell);
                break;
            case "SALVO":
            case "CHAIN":
            case "TOUCH":
                $game->{strtolower($command)} = $words[1] === "ON";
                $output[] = $command . " " . $words[1];
                break;
            case "CONTROL":
                $player = (int) $words[1] - 1;
                $game->players[$player]->controller =
                    $words[2] === "HUMAN" ? null : Strategy::from($words[2]);
                $output[] = "CONTROL " . ($player + 1) . " " . $words[2];
                break;
            case "SEED":
                $player = (int) $words[1] - 1;
                $seed = (int) $words[2];
                $game->players[$player]->random = $seed;
                $output[] = "SEED " . ($player + 1) . " " . $seed;
                break;
            case "RESIGN":
                if ($game->phase !== Phase::Battle) {
                    throw new CommandError("not in battle");
                }
                $player = (int) $words[1] - 1;
                $game->winner = 1 - $player;
                $game->phase = Phase::Over;
                $game->players[$game->winner]->wins++;
                $output[] = "RESIGN " . ($player + 1);
                $output[] = "WINNER " . ($game->winner + 1);
                break;
            case "HINT":
                if ($game->phase === Phase::Over) {
                    throw new CommandError("game over");
                }
                $player = (int) $words[1] - 1;
                $choice = $game->choose($player, Strategy::from($words[2]), false);
                $output[] =
                    "HINT " .
                    ($player + 1) .
                    " " .
                    $words[2] .
                    " " .
                    coordinate($choice->cell) .
                    " " .
                    $choice->info;
                break;
            case "DENSITY":
                if ($game->phase === Phase::Over) {
                    throw new CommandError("game over");
                }
                $game->density((int) $words[1] - 1, $output);
                break;
            case "SHOW":
            case "RADAR":
                $game->show((int) $words[1] - 1, $command === "RADAR", $output);
                break;
            case "EXPORT":
                $player = (int) $words[1] - 1;
                $output[] = "EXPORT " . ($player + 1) . " " . $game->exportFleet($player);
                break;
            case "FLEET":
                $game->fleet((int) $words[1] - 1, $output);
                break;
            case "STATUS":
                $output[] = $game->status();
                break;
            case "STATS":
                $game->stats($output);
                break;
            case "MATCH":
            case "SERIES":
            case "TOURNEY":
                $this->simulation($words, $output);
                break;
        }
        return $output;
    }
    private function simulation(array $words, array &$output): void
    {
        if ($words[0] === "MATCH") {
            $output[] = "MATCH 1 {$words[3]} 2 {$words[4]}";
            $match = $this->game->playMatch(
                (int) $words[1],
                (int) $words[2],
                Strategy::from($words[3]),
                Strategy::from($words[4]),
                $output,
                LogMode::Sinks,
            );
            $output[] =
                "RESULT winner " .
                ($match->winner + 1) .
                " shots " .
                $match->players[0]->shots .
                " " .
                $match->players[1]->shots .
                " hits " .
                $match->players[0]->hits .
                " " .
                $match->players[1]->hits;
            return;
        }
        $count = (int) $words[1];
        $random = (int) $words[2];
        if ($words[0] === "SERIES") {
            $wins = [0, 0];
            $shots = [0, 0];
            $fastest = [null, null];
            for ($i = 0; $i < $count; $i++) {
                $random = advance($random);
                $first = $random;
                $random = advance($random);
                $match = $this->game->playMatch(
                    $first,
                    $random,
                    Strategy::from($words[3]),
                    Strategy::from($words[4]),
                    $output,
                );
                $wins[$match->winner]++;
                for ($player = 0; $player < 2; $player++) {
                    $shots[$player] += $match->players[$player]->shots;
                }
                $winningShots = $match->players[$match->winner]->shots;
                $fastest[$match->winner] = min(
                    $fastest[$match->winner] ?? $winningShots,
                    $winningShots,
                );
            }
            $output[] =
                "SERIES $count wins {$wins[0]} {$wins[1]} shots {$shots[0]} {$shots[1]} fastest " .
                ($fastest[0] ?? "-") .
                " " .
                ($fastest[1] ?? "-");
            return;
        }
        $wins = [0, 0, 0];
        $shots = [0, 0, 0];
        $strategies = Strategy::cases();
        for ($first = 0; $first < 3; $first++) {
            for ($second = 0; $second < 3; $second++) {
                if ($first === $second) {
                    continue;
                }
                for ($i = 0; $i < $count; $i++) {
                    $random = advance($random);
                    $firstSeed = $random;
                    $random = advance($random);
                    $match = $this->game->playMatch(
                        $firstSeed,
                        $random,
                        $strategies[$first],
                        $strategies[$second],
                        $output,
                    );
                    $wins[$match->winner === 0 ? $first : $second]++;
                    $shots[$first] += $match->players[0]->shots;
                    $shots[$second] += $match->players[1]->shots;
                }
            }
        }
        $ranking = [0, 1, 2];
        usort(
            $ranking,
            static fn(int $a, int $b): int => $wins[$b] <=> $wins[$a] ?:
            ($shots[$a] <=> $shots[$b] ?:
            $a <=> $b),
        );
        $output[] = "TOURNEY $count";
        foreach ($ranking as $rank => $strategy) {
            $output[] =
                $rank +
                1 .
                " " .
                $strategies[$strategy]->value .
                " wins {$wins[$strategy]} shots {$shots[$strategy]}";
        }
    }
}

$count = (int) fgets(STDIN);
$program = new Program();
for ($i = 0; $i < $count; $i++) {
    $words = explode(" ", rtrim(fgets(STDIN), "\r\n"));
    try {
        echo implode("\n", $program->execute($words)), "\n";
    } catch (CommandError $error) {
        echo "ERROR ", $error->getMessage(), "\n";
    }
}
