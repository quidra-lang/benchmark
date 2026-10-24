<?php
declare(strict_types=1);

enum Strategy: string { case Kind = 'KIND'; case Straight = 'STRAIGHT'; case High = 'HIGH'; case Upper = 'UPPER'; }
enum JokerRule: string { case Forced = 'FORCED'; case Free = 'FREE'; case Off = 'OFF'; }
final class CommandError extends RuntimeException {}

function positive(string $word, int $maximum): int {
    if (preg_match('/\A[1-9][0-9]*\z/', $word) !== 1 || (int)$word > $maximum) throw new CommandError("bad value $word");
    return (int)$word;
}

function checkName(string $word): void {
    if (preg_match('/\A[A-Z]{1,8}\z/', $word) !== 1) throw new CommandError("bad name $word");
}

function parsePattern(string $word): int {
    if (preg_match('/\A[01]{5}\z/', $word) !== 1) throw new CommandError("bad pattern $word");
    return intval($word, 2);
}

function parseCategory(string $word): int {
    $category = array_search($word, Dice::CATEGORIES, true);
    if ($category === false) throw new CommandError("bad category $word");
    return $category;
}

function parseStrategy(string $word): Strategy {
    return Strategy::tryFrom($word) ?? throw new CommandError("bad strategy $word");
}

final readonly class Outcome {
    public function __construct(public int $code, public int $weight) {}
}

final readonly class Candidates {
    public function __construct(public array $points, public int $allowed, public bool $joker, public int $best) {}
}

final class Dice {
    public const CATEGORIES = ['ONES', 'TWOS', 'THREES', 'FOURS', 'FIVES', 'SIXES', 'THREEKIND', 'FOURKIND', 'FULLHOUSE', 'SMALL', 'LARGE', 'YAHTZEE', 'CHANCE'];
    public const POWERS = [1, 6, 36, 216, 1296, 7776];
    private const LOWER_MASK = 0x1fc0;

    public static function outcomes(): array {
        static $outcomes = null;
        if ($outcomes !== null) return $outcomes;
        $factorial = [1, 1, 2, 6, 24, 120];
        $outcomes = array_fill(0, 6, []);
        for ($size = 0; $size <= 5; $size++) {
            $add = function(int $face, int $remaining, int $code, int $divisor) use (&$add, &$outcomes, $factorial, $size): void {
                if ($face === 6) {
                    if ($remaining === 0) $outcomes[$size][] = new Outcome($code, intdiv($factorial[$size], $divisor));
                    return;
                }
                for ($n = 0; $n <= $remaining; $n++) $add($face + 1, $remaining - $n, $code + $n * self::POWERS[$face], $divisor * $factorial[$n]);
            };
            $add(0, $size, 0, 1);
        }
        return $outcomes;
    }

    public static function held(int $mask, int $die): bool { return ($mask & (1 << (4 - $die))) !== 0; }
    public static function pattern(int $mask): string { return str_pad(decbin($mask), 5, '0', STR_PAD_LEFT); }
    public static function faces(?array $faces, int $mask = 31): string {
        $selected = [];
        if ($faces !== null) for ($i = 0; $i < 5; $i++) if (self::held($mask, $i)) $selected[] = $faces[$i];
        return $selected === [] ? '-' : implode(' ', $selected);
    }
    public static function counts(array $faces): array {
        $counts = array_fill(0, 6, 0);
        foreach ($faces as $face) $counts[$face - 1]++;
        return $counts;
    }
    public static function decode(int $code): array {
        $counts = [];
        for ($i = 0; $i < 6; $i++) { $counts[] = $code % 6; $code = intdiv($code, 6); }
        return $counts;
    }
    public static function heldCode(array $faces, int $mask): int {
        $code = 0;
        for ($i = 0; $i < 5; $i++) if (self::held($mask, $i)) $code += self::POWERS[$faces[$i] - 1];
        return $code;
    }
    public static function frequent(array $counts): int {
        $face = 0;
        for ($i = 1; $i < 6; $i++) if ($counts[$i] >= $counts[$face]) $face = $i;
        return $face;
    }
    public static function yahtzee(array $counts): bool { return in_array(5, $counts, true); }
    public static function normal(int $category, array $counts): int {
        if ($category < 6) return ($category + 1) * $counts[$category];
        $total = 0; $largest = 0; $bits = 0;
        foreach ($counts as $i => $count) {
            $total += ($i + 1) * $count;
            $largest = max($largest, $count);
            if ($count > 0) $bits |= 1 << $i;
        }
        return match ($category) {
            6 => $largest >= 3 ? $total : 0,
            7 => $largest >= 4 ? $total : 0,
            8 => in_array(3, $counts, true) && in_array(2, $counts, true) ? 25 : 0,
            9 => ($bits & 15) === 15 || ($bits & 30) === 30 || ($bits & 60) === 60 ? 30 : 0,
            10 => $bits === 31 || $bits === 62 ? 40 : 0,
            11 => $largest === 5 ? 50 : 0,
            default => $total,
        };
    }
    public static function evaluate(Player $player, array $counts, JokerRule $rule): Candidates {
        $allowed = 0;
        for ($c = 0; $c < 13; $c++) if ($player->scores[$c] === null) $allowed |= 1 << $c;
        $joker = $rule !== JokerRule::Off && self::yahtzee($counts) && $player->scores[11] !== null;
        if ($joker && $rule === JokerRule::Forced) {
            $upper = self::frequent($counts);
            if (($allowed & (1 << $upper)) !== 0) $allowed = 1 << $upper;
            elseif (($allowed & self::LOWER_MASK) !== 0) $allowed &= self::LOWER_MASK;
        }
        $points = array_fill(0, 13, -1);
        $best = -1;
        for ($c = 0; $c < 13; $c++) {
            if ($player->scores[$c] !== null) continue;
            $points[$c] = ($allowed & (1 << $c)) === 0 ? 0
                : ($joker && $c >= 8 && $c <= 10 ? [25, 30, 40][$c - 8] : self::normal($c, $counts));
            if ($best < 0 || $points[$c] > $points[$best]) $best = $c;
        }
        return new Candidates($points, $allowed, $joker, $best);
    }
    public static function fraction(int $numerator, int $denominator): string {
        $a = $numerator; $b = $denominator;
        while ($b !== 0) { [$a, $b] = [$b, $a % $b]; }
        $numerator = intdiv($numerator, $a);
        $denominator = intdiv($denominator, $a);
        return $denominator === 1 ? (string)$numerator : "$numerator/$denominator";
    }
    public static function average(int $sum, int $count): string {
        $value = $count === 0 ? 0 : intdiv(100 * $sum, $count);
        return sprintf('%d.%02d', intdiv($value, 100), $value % 100);
    }
}

final class Player {
    /** @var array<int, ?int> */
    public array $scores;
    public int $yahtzeeBonus = 0;
    public function __construct(public readonly string $name, public Strategy $strategy = Strategy::Kind) {
        $this->scores = array_fill(0, 13, null);
    }
    public function upper(): int {
        $sum = 0;
        for ($c = 0; $c < 6; $c++) $sum += $this->scores[$c] ?? 0;
        return $sum;
    }
    public function upperBonus(): int { return $this->upper() >= 63 ? 35 : 0; }
    public function total(): int {
        $sum = $this->upperBonus() + $this->yahtzeeBonus;
        foreach ($this->scores as $score) $sum += $score ?? 0;
        return $sum;
    }
    public function round(): int {
        $round = 1;
        foreach ($this->scores as $score) if ($score !== null) $round++;
        return $round;
    }
}

final readonly class Turn {
    public function __construct(public int $seat = 0, public int $rolls = 0, public ?array $faces = null, public int $hold = 0, public bool $finished = false) {}
}
final readonly class ScoreEntry {
    public function __construct(public Turn $before, public int $category, public int $points, public int $bonus, public bool $joker) {}
}
final readonly class RedoEntry {
    public function __construct(public Turn $after, public ScoreEntry $entry) {}
}

final class Game {
    public readonly SplQueue $loaded;
    public array $faceTotals = [0, 0, 0, 0, 0, 0];
    /** @var list<ScoreEntry> */
    public array $entries = [];
    /** @var list<RedoEntry> */
    public array $redoList = [];
    public Turn $state;
    /** @param list<Player> $players */
    public function __construct(public int $randomState, public readonly array $players, public readonly int $maxRolls,
                                public readonly JokerRule $joker, private readonly ?Closure $output = null) {
        $this->loaded = new SplQueue();
        $this->state = new Turn();
    }
    public function current(): Player { return $this->players[$this->state->seat]; }
    private function emit(string $format, mixed ...$args): void {
        if ($this->output !== null) ($this->output)($args === [] ? $format : sprintf($format, ...$args));
    }
    public function checkTurn(): void {
        if ($this->state->finished) throw new CommandError('game over');
    }
    public function checkRolled(): void {
        $this->checkTurn();
        if ($this->state->rolls === 0) throw new CommandError('not rolled');
    }
    public function checkRollsLeft(): void {
        $this->checkRolled();
        if ($this->state->rolls === $this->maxRolls) throw new CommandError('no rolls left');
    }
    public function roll(): void {
        $this->checkTurn();
        $turn = $this->state;
        if ($turn->rolls === $this->maxRolls) throw new CommandError('no rolls left');
        if ($turn->hold === 31) throw new CommandError('all dice held');
        $this->redoList = [];
        $faces = $turn->faces ?? array_fill(0, 5, 0);
        for ($i = 0; $i < 5; $i++) {
            if ($turn->rolls > 0 && Dice::held($turn->hold, $i)) continue;
            if (!$this->loaded->isEmpty()) $faces[$i] = $this->loaded->dequeue();
            else {
                $this->randomState = 48271 * $this->randomState % 2147483647;
                $faces[$i] = $this->randomState % 6 + 1;
            }
            $this->faceTotals[$faces[$i] - 1]++;
        }
        $this->state = new Turn($turn->seat, $turn->rolls + 1, $faces, $turn->hold);
        $this->emit('%s roll %d: %s', $this->current()->name, $this->state->rolls, Dice::faces($faces));
    }
    public function hold(int $mask): void {
        $this->checkRollsLeft();
        $this->redoList = [];
        $turn = $this->state;
        $this->state = new Turn($turn->seat, $turn->rolls, $turn->faces, $mask);
        $this->emit('%s holds %s: %s', $this->current()->name, Dice::pattern($mask), Dice::faces($turn->faces, $mask));
    }
    public function keep(array $values): void {
        $this->checkRollsLeft();
        $mask = 0;
        foreach ($values as $value) {
            $die = -1;
            for ($i = 0; $i < 5; $i++) if (!Dice::held($mask, $i) && $this->state->faces[$i] === $value) { $die = $i; break; }
            if ($die < 0) throw new CommandError("not showing $value");
            $mask |= 1 << (4 - $die);
        }
        $this->hold($mask);
    }
    public function score(int $category, bool $preview = false): void {
        $this->checkRolled();
        $player = $this->current();
        if ($player->scores[$category] !== null) throw new CommandError(Dice::CATEGORIES[$category] . ' already used');
        $counts = Dice::counts($this->state->faces);
        $candidates = Dice::evaluate($player, $counts, $this->joker);
        if (($candidates->allowed & (1 << $category)) === 0) {
            $upper = Dice::frequent($counts);
            throw new CommandError('joker requires ' . ($player->scores[$upper] === null ? Dice::CATEGORIES[$upper] : 'lower box'));
        }
        $points = $candidates->points[$category];
        $bonus = Dice::yahtzee($counts) && $player->scores[11] === 50 ? 100 : 0;
        $upperBonus = $category < 6 && $player->upper() < 63 && $player->upper() + $points >= 63 ? 35 : 0;
        $line = sprintf('%s %s %d in %s', $player->name, $preview ? 'would score' : 'scores', $points, Dice::CATEGORIES[$category]);
        if ($candidates->joker) $line .= ' joker';
        if ($bonus !== 0) $line .= ' ybonus 100';
        if ($upperBonus !== 0) $line .= ' ubonus 35';
        $line .= ' total ' . ($player->total() + $points + $bonus + $upperBonus);
        if ($preview) { $this->emit($line); return; }
        $this->redoList = [];
        $this->entries[] = new ScoreEntry($this->state, $category, $points, $bonus, $candidates->joker);
        $player->scores[$category] = $points;
        $player->yahtzeeBonus += $bonus;
        $this->state = count($this->entries) === 13 * count($this->players) ? new Turn(finished: true)
            : new Turn(seat: ($this->state->seat + 1) % count($this->players));
        $this->emit($line);
        if ($this->state->finished) $this->emit('game over');
        else $this->emit('turn %d %s', $this->current()->round(), $this->current()->name);
    }
    public function undo(): void {
        if ($this->entries === []) throw new CommandError('nothing to undo');
        $entry = array_pop($this->entries);
        $this->redoList[] = new RedoEntry($this->state, $entry);
        $player = $this->players[$entry->before->seat];
        $player->scores[$entry->category] = null;
        $player->yahtzeeBonus -= $entry->bonus;
        $this->state = $entry->before;
        $this->emit('undo %s %s %d', $player->name, Dice::CATEGORIES[$entry->category], $entry->points);
    }
    public function redo(): void {
        if ($this->redoList === []) throw new CommandError('nothing to redo');
        $saved = array_pop($this->redoList);
        $entry = $saved->entry;
        $player = $this->players[$entry->before->seat];
        $player->scores[$entry->category] = $entry->points;
        $player->yahtzeeBonus += $entry->bonus;
        $this->entries[] = $entry;
        $this->state = $saved->after;
        $this->emit('redo %s %s %d', $player->name, Dice::CATEGORIES[$entry->category], $entry->points);
    }
    private function botHold(Strategy $strategy): int {
        $faces = $this->state->faces;
        $counts = Dice::counts($faces);
        $frequent = Dice::frequent($counts);
        $mask = 0;
        if ($strategy === Strategy::Straight) {
            $bestStart = 0; $bestLength = 0;
            for ($start = 0; $start < 6; $start++) {
                $end = $start;
                while ($end < 6 && $counts[$end] > 0) $end++;
                if ($end - $start >= $bestLength) { $bestStart = $start; $bestLength = $end - $start; }
            }
            if ($bestLength >= 3) {
                for ($face = $bestStart + 1; $face <= $bestStart + $bestLength; $face++) $mask |= 1 << (4 - array_search($face, $faces, true));
                return $mask;
            }
        }
        for ($i = 0; $i < 5; $i++) if ($strategy === Strategy::High ? $faces[$i] >= 5 : $faces[$i] === $frequent + 1) $mask |= 1 << (4 - $i);
        return $mask;
    }
    public function botTurn(): void {
        $strategy = $this->current()->strategy;
        if ($this->state->rolls === 0) $this->roll();
        while ($this->state->rolls < $this->maxRolls) {
            $mask = $this->botHold($strategy);
            if ($mask === 31) break;
            $this->hold($mask);
            $this->roll();
        }
        $counts = Dice::counts($this->state->faces);
        $candidates = Dice::evaluate($this->current(), $counts, $this->joker);
        $frequent = Dice::frequent($counts);
        $category = $strategy === Strategy::Upper && $counts[$frequent] >= 3 && ($candidates->allowed & (1 << $frequent)) !== 0
            ? $frequent : $candidates->best;
        $this->score($category);
    }
    public function ranking(): array {
        $seats = array_keys($this->players);
        usort($seats, fn(int $a, int $b): int => ($this->players[$b]->total() <=> $this->players[$a]->total()) ?: ($a <=> $b));
        return $seats;
    }
}

final class Adviser {
    private array $values = [], $expectations = [];
    private readonly array $outcomes;
    public function __construct(private readonly Player $player, private readonly JokerRule $joker) { $this->outcomes = Dice::outcomes(); }
    // Values at depth j share the denominator 7776^j, including the all-held choice.
    private function value(int $code, int $depth): int {
        $key = $depth * 46656 + $code;
        if (isset($this->values[$key])) return $this->values[$key];
        $counts = Dice::decode($code);
        if ($depth === 0) {
            $candidates = Dice::evaluate($this->player, $counts, $this->joker);
            $best = $candidates->points[$candidates->best];
        } else $best = $this->choose($counts, $depth, 0, 0);
        return $this->values[$key] = $best;
    }
    private function choose(array $counts, int $depth, int $face, int $kept): int {
        if ($face === 6) return $this->expected($kept, $depth);
        $best = -1;
        for ($n = 0; $n <= $counts[$face]; $n++) $best = max($best, $this->choose($counts, $depth, $face + 1, $kept + $n * Dice::POWERS[$face]));
        return $best;
    }
    public function expected(int $kept, int $depth): int {
        $key = $depth * 46656 + $kept;
        if (isset($this->expectations[$key])) return $this->expectations[$key];
        $rerolled = 5 - array_sum(Dice::decode($kept));
        $sum = 0;
        foreach ($this->outcomes[$rerolled] as $outcome) $sum += $outcome->weight * $this->value($kept + $outcome->code, $depth - 1);
        return $this->expectations[$key] = $sum * Dice::POWERS[5 - $rerolled];
    }
}

final class GameRecord { public int $games = 0, $wins = 0, $best = 0, $sum = 0; }
final class SimulationTotal { public int $wins = 0, $sum = 0, $best = 0, $bonus = 0, $yahtzee = 0; }

final class Program {
    private int $rolls = 3;
    private JokerRule $joker = JokerRule::Forced;
    private ?Game $game = null;
    /** @var array<string, GameRecord> */
    private array $records = [];
    public array $output = [];
    public function emit(string $format, mixed ...$args): void { $this->output[] = $args === [] ? $format : sprintf($format, ...$args); }
    private function table(): Game { return $this->game ?? throw new CommandError('no game'); }

    private function odds(Game $table, int $mask): void {
        $table->checkRollsLeft();
        $kept = Dice::heldCode($table->state->faces, $mask);
        $rerolled = 5 - array_sum(Dice::decode($kept));
        $count = Dice::POWERS[$rerolled];
        $totals = array_fill(0, 13, 0); $chances = array_fill(0, 13, 0); $best = 0;
        foreach (Dice::outcomes()[$rerolled] as $outcome) {
            $candidates = Dice::evaluate($table->current(), Dice::decode($kept + $outcome->code), $table->joker);
            for ($c = 0; $c < 13; $c++) {
                if ($candidates->points[$c] < 0) continue;
                $totals[$c] += $outcome->weight * $candidates->points[$c];
                if ($candidates->points[$c] > 0) $chances[$c] += $outcome->weight;
            }
            $best += $outcome->weight * $candidates->points[$candidates->best];
        }
        $this->emit('odds %s outcomes %d', Dice::pattern($mask), $count);
        for ($c = 0; $c < 13; $c++) if ($table->current()->scores[$c] === null) {
            $this->emit('%s expect %s chance %s', Dice::CATEGORIES[$c], Dice::fraction($totals[$c], $count), Dice::fraction($chances[$c], $count));
        }
        $this->emit('best expect %s', Dice::fraction($best, $count));
    }
    private function advise(Game $table): void {
        $table->checkRollsLeft();
        $depth = $table->maxRolls - $table->state->rolls;
        $chosen = 0; $best = -1; $denominator = 1;
        for ($i = 0; $i < $depth; $i++) $denominator *= 7776;
        $adviser = new Adviser($table->current(), $table->joker);
        for ($mask = 0; $mask < 32; $mask++) {
            $value = $adviser->expected(Dice::heldCode($table->state->faces, $mask), $depth);
            if ($value > $best) { $best = $value; $chosen = $mask; }
        }
        $this->emit('advise %s: %s expect %s', Dice::pattern($chosen), Dice::faces($table->state->faces, $chosen), Dice::fraction($best, $denominator));
    }
    private function card(Game $table): void {
        $row = function(string $heading, Closure $cell) use ($table): void {
            $line = str_pad($heading, 9);
            foreach ($table->players as $player) $line .= ' ' . str_pad($cell($player), max(4, strlen($player->name)), ' ', STR_PAD_LEFT);
            $this->emit($line);
        };
        $row('CATEGORY', fn(Player $p): string => $p->name);
        for ($c = 0; $c < 13; $c++) $row(Dice::CATEGORIES[$c], fn(Player $p): string => $p->scores[$c] === null ? '-' : (string)$p->scores[$c]);
        $row('UPPER', fn(Player $p): string => (string)$p->upper());
        $row('BONUS', fn(Player $p): string => (string)$p->upperBonus());
        $row('YBONUS', fn(Player $p): string => (string)$p->yahtzeeBonus);
        $row('TOTAL', fn(Player $p): string => (string)$p->total());
    }
    private function simulate(int $seed, int $count, array $strategies): void {
        $totals = array_map(fn(Strategy $strategy): SimulationTotal => new SimulationTotal(), $strategies);
        $state = $seed;
        for ($n = 0; $n < $count; $n++) {
            $players = [];
            foreach ($strategies as $i => $strategy) $players[] = new Player('BOT' . ($i + 1), $strategy);
            $table = new Game($state, $players, $this->rolls, $this->joker);
            while (!$table->state->finished) $table->botTurn();
            $state = $table->randomState;
            $totals[$table->ranking()[0]]->wins++;
            foreach ($players as $i => $player) {
                $total = $totals[$i];
                $total->sum += $player->total();
                $total->best = max($total->best, $player->total());
                if ($player->upperBonus() === 35) $total->bonus++;
                if ($player->scores[11] === 50) $total->yahtzee++;
            }
        }
        $this->emit('sim seed %d games %d players %d', $seed, $count, count($strategies));
        foreach ($strategies as $i => $strategy) {
            $total = $totals[$i];
            $this->emit('seat %d %s wins %d average %s best %d bonus %d yahtzee %d', $i + 1, $strategy->value, $total->wins,
                Dice::average($total->sum, $count), $total->best, $total->bonus, $total->yahtzee);
        }
    }
    public function execute(array $words): void {
        switch ($words[0]) {
            case 'RULE':
                if ($words[1] !== 'ROLLS' && $words[1] !== 'JOKER') throw new CommandError('unknown rule ' . $words[1]);
                $rolls = $this->rolls; $joker = $this->joker;
                if ($words[1] === 'ROLLS') $rolls = positive($words[2], 4);
                else $joker = JokerRule::tryFrom($words[2]) ?? throw new CommandError('bad value ' . $words[2]);
                if ($this->game !== null) throw new CommandError('game in progress');
                $this->rolls = $rolls; $this->joker = $joker;
                $this->emit('rule %s %s', $words[1], $words[2]);
                return;
            case 'GAME':
                $seed = positive($words[1], 2147483646);
                $names = array_slice($words, 2);
                foreach ($names as $name) checkName($name);
                if (count($names) > 6) throw new CommandError('too many players');
                if ($this->game !== null) throw new CommandError('game in progress');
                $seen = [];
                foreach ($names as $name) {
                    if (isset($seen[$name])) throw new CommandError("duplicate name $name");
                    $seen[$name] = true;
                }
                $this->game = new Game($seed, array_map(fn(string $name): Player => new Player($name), $names), $this->rolls, $this->joker, $this->emit(...));
                $this->emit('game seed %d players %s', $seed, implode(' ', $names));
                $this->emit('turn 1 %s', $names[0]);
                return;
            case 'BOT':
                checkName($words[1]);
                $strategy = parseStrategy($words[2]);
                $table = $this->table();
                $selected = null;
                foreach ($table->players as $player) if ($player->name === $words[1]) { $selected = $player; break; }
                if ($selected === null) throw new CommandError('no player ' . $words[1]);
                $selected->strategy = $strategy;
                $this->emit('bot %s %s', $words[1], $words[2]);
                return;
            case 'LOAD':
            case 'KEEP':
                $values = [];
                foreach (array_slice($words, 1) as $word) $values[] = positive($word, 6);
                $table = $this->table();
                if ($words[0] === 'KEEP') $table->keep($values);
                else { foreach ($values as $value) $table->loaded->enqueue($value); $this->emit('loaded %d', $table->loaded->count()); }
                return;
            case 'ROLL': $this->table()->roll(); return;
            case 'HOLD':
            case 'ODDS':
                $mask = parsePattern($words[1]);
                $table = $this->table();
                if ($words[0] === 'HOLD') $table->hold($mask); else $this->odds($table, $mask);
                return;
            case 'SCORE':
            case 'WHATIF':
                $category = parseCategory($words[1]);
                $this->table()->score($category, $words[0] === 'WHATIF');
                return;
            case 'UNDO': $this->table()->undo(); return;
            case 'REDO': $this->table()->redo(); return;
            case 'SUGGEST':
                $table = $this->table();
                $table->checkRolled();
                $candidates = Dice::evaluate($table->current(), Dice::counts($table->state->faces), $table->joker);
                $line = 'suggest';
                foreach (Dice::CATEGORIES as $c => $category) if ($candidates->points[$c] >= 0) $line .= " $category " . $candidates->points[$c];
                $this->emit('%s best %s %d', $line, Dice::CATEGORIES[$candidates->best], $candidates->points[$candidates->best]);
                return;
            case 'ADVISE': $this->advise($this->table()); return;
            case 'AUTO':
                $count = positive($words[1], 100);
                $table = $this->table();
                $table->checkTurn();
                $table->redoList = [];
                for ($i = 0; $i < $count && !$table->state->finished; $i++) $table->botTurn();
                return;
            case 'STATUS':
                $table = $this->table(); $turn = $table->state;
                if ($turn->finished) $this->emit('status game over');
                else $this->emit('status round %d player %s rolls %d dice %s holds %s', $table->current()->round(), $table->current()->name,
                    $turn->rolls, Dice::faces($turn->faces), Dice::pattern($turn->hold));
                return;
            case 'CARD': $this->card($this->table()); return;
            case 'BONUS':
                foreach ($this->table()->players as $player) {
                    $maximum = $player->upper();
                    for ($c = 0; $c < 6; $c++) if ($player->scores[$c] === null) $maximum += 5 * ($c + 1);
                    $status = $player->upper() >= 63 ? 'made' : ($maximum < 63 ? 'lost' : 'open');
                    $this->emit('bonus %s upper %d need %d max %d %s', $player->name, $player->upper(), max(63 - $player->upper(), 0), $maximum, $status);
                }
                return;
            case 'STATS':
                $table = $this->table();
                foreach ($table->players as $seat => $player) {
                    $turns = 0; $rolls = 0; $zeros = 0; $yahtzees = 0; $sum = 0;
                    foreach ($table->entries as $entry) {
                        if ($entry->before->seat !== $seat) continue;
                        $turns++; $rolls += $entry->before->rolls; $sum += $entry->points;
                        if ($entry->points === 0) $zeros++;
                        if (Dice::yahtzee(Dice::counts($entry->before->faces))) $yahtzees++;
                    }
                    $this->emit('stats %s turns %d rolls %d zeros %d yahtzees %d average %s', $player->name, $turns, $rolls, $zeros, $yahtzees, Dice::average($sum, $turns));
                }
                return;
            case 'LOG':
                $table = $this->table();
                foreach ($table->entries as $i => $entry) {
                    $this->emit('log %d %s %s %s %d%s%s', $i + 1, $table->players[$entry->before->seat]->name, Dice::faces($entry->before->faces),
                        Dice::CATEGORIES[$entry->category], $entry->points, $entry->joker ? ' joker' : '', $entry->bonus !== 0 ? ' ybonus 100' : '');
                }
                if ($table->entries === []) $this->emit('no scores');
                return;
            case 'FACES':
                $counts = $this->table()->faceTotals;
                $total = array_sum($counts);
                $numerator = 6 * array_sum(array_map(fn(int $c): int => $c * $c, $counts)) - $total * $total;
                $this->emit('faces %s total %d chi2 %s', implode(' ', $counts), $total, Dice::fraction($numerator, $total === 0 ? 1 : $total));
                return;
            case 'STANDINGS':
            case 'END':
                $table = $this->table(); $ranking = $table->ranking(); $end = $words[0] === 'END';
                if ($end) $this->emit($table->state->finished ? 'end final' : 'end abandoned');
                foreach ($ranking as $rank => $seat) {
                    $player = $table->players[$seat];
                    if (!$end) $this->emit('standing %d %s %d behind %d', $rank + 1, $player->name, $player->total(), $table->players[$ranking[0]]->total() - $player->total());
                    else {
                        $this->emit('rank %d %s %d', $rank + 1, $player->name, $player->total());
                        if ($table->state->finished) {
                            $record = $this->records[$player->name] ??= new GameRecord();
                            $record->games++; $record->sum += $player->total(); $record->best = max($record->best, $player->total());
                            if ($rank === 0) $record->wins++;
                        }
                    }
                }
                if ($end) $this->game = null;
                return;
            case 'RECORDS':
                $names = array_keys($this->records);
                usort($names, function(string $a, string $b): int {
                    $first = $this->records[$a]; $second = $this->records[$b];
                    return ($second->wins <=> $first->wins) ?: (($second->best <=> $first->best) ?: strcmp($a, $b));
                });
                foreach ($names as $name) {
                    $record = $this->records[$name];
                    $this->emit('record %s games %d wins %d best %d average %s', $name, $record->games, $record->wins, $record->best, Dice::average($record->sum, $record->games));
                }
                if ($names === []) $this->emit('no records');
                return;
            case 'SIM':
                $seed = positive($words[1], 2147483646);
                $count = positive($words[2], 50);
                $strategies = [];
                foreach (array_slice($words, 3) as $word) $strategies[] = parseStrategy($word);
                if (count($strategies) > 6) throw new CommandError('too many players');
                $this->simulate($seed, $count, $strategies);
                return;
            default: throw new CommandError('unknown command ' . $words[0]);
        }
    }
}

$count = (int)trim(fgets(STDIN));
$program = new Program();
for ($i = 0; $i < $count; $i++) {
    $words = explode(' ', rtrim(fgets(STDIN), "\r\n"));
    try { $program->execute($words); }
    catch (CommandError $error) { $program->emit('error: %s', $error->getMessage()); }
}
if ($program->output !== []) echo implode("\n", $program->output), "\n";
