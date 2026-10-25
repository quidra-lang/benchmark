<?php
declare(strict_types=1);

enum GameState: string { case Ready = 'ready'; case Playing = 'playing'; case Won = 'won'; case Lost = 'lost'; }
enum Mark: string { case None = 'none'; case Flag = 'flag'; case Question = 'question'; }
enum Safety: string { case Block = 'block'; case Cell = 'cell'; case None = 'none'; }
enum MoveKind: string
{
    case Reveal = 'reveal'; case Flag = 'flag'; case Unflag = 'unflag'; case Question = 'question';
    case Chord = 'chord'; case AutoReveal = 'auto-reveal'; case AutoFlag = 'auto-flag'; case Guess = 'guess';
}
final readonly class Move
{
    public function __construct(public MoveKind $kind, public int $cell) {}
}
final readonly class UndoRecord
{
    public function __construct(public string $name, public array $revealed, public array $marks, public int $moveCount) {}
}
final readonly class Constraint
{
    public function __construct(public int $cell, public array $unknown, public int $remaining) {}
}
final class CommandError extends RuntimeException {}
function fail(string $message): never { throw new CommandError($message); }
function emit(string|int ...$parts): void { echo implode(' ', $parts), "\n"; }
function inputLine(): string { return rtrim(fgets(STDIN), "\r\n"); }
function fraction(int $numerator, int $denominator): string
{
    $a = $numerator; $b = $denominator;
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a);
}

final class Deduction
{
    public array $safe;
    public array $mines;
    public function __construct(int $size)
    {
        $this->safe = $this->mines = array_fill(0, $size, null);
    }
    public function any(): bool
    {
        foreach ($this->safe as $reason) if ($reason !== null) return true;
        foreach ($this->mines as $reason) if ($reason !== null) return true;
        return false;
    }
}

final class Totals
{
    public int $rounds = 0, $flagged = 0, $opened = 0, $guesses = 0;
    public function add(self $other): void
    {
        $this->rounds += $other->rounds;
        $this->flagged += $other->flagged;
        $this->opened += $other->opened;
    }
}

final class Component
{
    public int $configurations = 0, $maximum = 0, $minimum;
    public array $mineCounts;
    private bool $counted = false;
    private array $index = [], $links = [], $order = [], $remaining = [], $sums = [], $assignment = [];

    public function __construct(public readonly array $cells, private readonly array $constraints)
    {
        $this->minimum = count($cells);
        $this->mineCounts = array_fill(0, count($cells), 0);
    }
    public function count(): void
    {
        if ($this->counted) return;
        $this->counted = true;
        foreach ($this->constraints as $constraint)
            if ($constraint->remaining < 0 || $constraint->remaining > count($constraint->unknown)) return;
        $this->index = array_flip($this->cells);
        $this->links = array_fill(0, count($this->cells), []);
        foreach ($this->constraints as $c => $constraint)
            foreach ($constraint->unknown as $cell) $this->links[$this->index[$cell]][] = $c;
        $this->order = array_keys($this->cells);
        usort($this->order, fn(int $a, int $b): int =>
            (count($this->links[$b]) <=> count($this->links[$a])) ?: ($a <=> $b));
        $this->remaining = array_map(fn(Constraint $c): int => count($c->unknown), $this->constraints);
        $this->sums = array_fill(0, count($this->constraints), 0);
        $this->assignment = array_fill(0, count($this->cells), 0);
        $this->search(0, 0);
    }
    private function search(int $depth, int $mines): void
    {
        if ($depth === count($this->cells)) {
            $this->configurations++;
            $this->minimum = min($this->minimum, $mines);
            $this->maximum = max($this->maximum, $mines);
            foreach ($this->assignment as $i => $value) $this->mineCounts[$i] += $value;
            return;
        }
        $variable = $this->order[$depth];
        for ($value = 0; $value <= 1; $value++) {
            $this->assignment[$variable] = $value;
            $possible = true;
            foreach ($this->links[$variable] as $c) {
                $this->remaining[$c]--;
                $this->sums[$c] += $value;
                $required = $this->constraints[$c]->remaining;
                if ($this->sums[$c] > $required || $this->sums[$c] + $this->remaining[$c] < $required) $possible = false;
            }
            if ($possible) $this->search($depth + 1, $mines + $value);
            foreach ($this->links[$variable] as $c) { $this->sums[$c] -= $value; $this->remaining[$c]++; }
        }
    }
    public function mineCount(int $cell): int { return $this->mineCounts[$this->index[$cell]]; }
}

final readonly class Frontier
{
    public function __construct(public array $components, public array $at) {}
}

final class Game
{
    public readonly int $size;
    public ?array $mines = null;
    public array $numbers, $neighbors = [], $revealed, $marks, $moves = [], $undo = [];
    public GameState $state = GameState::Ready;
    public ?int $exploded = null;

    public function __construct(public readonly int $width, public readonly int $height,
        public readonly int $mineCount, public readonly int $seed, ?array $placement = null)
    {
        $this->size = $width * $height;
        $this->revealed = array_fill(0, $this->size, false);
        $this->marks = array_fill(0, $this->size, Mark::None);
        $this->numbers = array_fill(0, $this->size, 0);
        for ($cell = 0; $cell < $this->size; $cell++) {
            $nearby = [];
            $x = $cell % $width; $y = intdiv($cell, $width);
            for ($dy = -1; $dy <= 1; $dy++)
                for ($dx = -1; $dx <= 1; $dx++)
                    if (($dx !== 0 || $dy !== 0) && $x + $dx >= 0 && $x + $dx < $width && $y + $dy >= 0 && $y + $dy < $height)
                        $nearby[] = ($y + $dy) * $width + $x + $dx;
            $this->neighbors[] = $nearby;
        }
        if ($placement !== null) $this->setPlacement($placement);
    }
    public function finished(): bool { return $this->state === GameState::Won || $this->state === GameState::Lost; }
    public function remaining(): int { return $this->mineCount - count(array_filter($this->marks, fn(Mark $mark): bool => $mark === Mark::Flag)); }
    public function openCount(): int { return count(array_filter($this->revealed)); }
    public function cell(int $cell): string { return ($cell % $this->width) . ',' . intdiv($cell, $this->width); }
    public function unknown(int $cell): bool { return !$this->revealed[$cell] && $this->marks[$cell] !== Mark::Flag; }
    public function flags(int $cell): int
    {
        return count(array_filter($this->neighbors[$cell], fn(int $other): bool => $this->marks[$other] === Mark::Flag));
    }
    public function unknownNeighbors(int $cell): array
    {
        return array_values(array_filter($this->neighbors[$cell], fn(int $other): bool => $this->unknown($other)));
    }
    public function copy(bool $reset = false): self
    {
        $copy = clone $this;
        $copy->undo = [];
        if ($reset) $copy->restart();
        return $copy;
    }
    private function setPlacement(array $mines): void
    {
        $this->mines = $mines;
        foreach ($this->neighbors as $cell => $nearby)
            $this->numbers[$cell] = count(array_filter($nearby, fn(int $other): bool => $mines[$other]));
        $this->state = GameState::Playing;
    }
    private function place(int $first, Safety $safety): void
    {
        $sx = $first % $this->width; $sy = intdiv($first, $this->width);
        $candidates = [];
        for ($cell = 0; $cell < $this->size; $cell++)
            if ($safety === Safety::None || $safety === Safety::Cell && $cell !== $first ||
                $safety === Safety::Block && (abs($cell % $this->width - $sx) >= 2 || abs(intdiv($cell, $this->width) - $sy) >= 2))
                $candidates[] = $cell;
        $mines = array_fill(0, $this->size, false);
        $random = $this->seed;
        for ($i = 0; $i < $this->mineCount; $i++) {
            $random = 48271 * $random % 2147483647;
            $index = $random % count($candidates);
            $mines[$candidates[$index]] = true;
            array_splice($candidates, $index, 1);
        }
        $this->setPlacement($mines);
    }
    public function restart(): void
    {
        $this->revealed = array_fill(0, $this->size, false);
        $this->marks = array_fill(0, $this->size, Mark::None);
        $this->moves = $this->undo = [];
        $this->exploded = null;
        $this->state = $this->mines === null ? GameState::Ready : GameState::Playing;
    }
    public function snapshot(string $name): UndoRecord
    {
        return new UndoRecord($name, $this->revealed, $this->marks, count($this->moves));
    }
    public function restore(UndoRecord $saved): void
    {
        $this->revealed = $saved->revealed; $this->marks = $saved->marks;
        $this->moves = array_slice($this->moves, 0, $saved->moveCount);
    }
    public function reveal(int $first, Safety $safety): int
    {
        if ($this->mines === null) $this->place($first, $safety);
        if ($this->mines[$first]) { $this->state = GameState::Lost; $this->exploded = $first; return 0; }
        $queue = new SplQueue();
        $this->revealed[$first] = true; $this->marks[$first] = Mark::None; $queue->enqueue($first);
        $opened = 1;
        while (!$queue->isEmpty()) {
            $cell = $queue->dequeue();
            if ($this->numbers[$cell] === 0)
                foreach ($this->neighbors[$cell] as $other)
                    if ($this->unknown($other)) {
                        $this->revealed[$other] = true; $this->marks[$other] = Mark::None;
                        $queue->enqueue($other); $opened++;
                    }
        }
        return $opened;
    }
    public function chord(int $cell, Safety $safety): int
    {
        $opened = 0;
        foreach ($this->neighbors[$cell] as $other)
            if ($this->unknown($other)) {
                $opened += $this->reveal($other, $safety);
                if ($this->state === GameState::Lost) break;
            }
        return $opened;
    }
    public function checkWin(): bool
    {
        if ($this->state !== GameState::Playing || $this->openCount() !== $this->size - $this->mineCount) return false;
        $this->state = GameState::Won;
        foreach ($this->mines as $cell => $mine) if ($mine) $this->marks[$cell] = Mark::Flag;
        return true;
    }
    public function display(): void
    {
        for ($y = 0; $y < $this->height; $y++) {
            $row = '';
            for ($x = 0; $x < $this->width; $x++) {
                $cell = $y * $this->width + $x;
                if ($this->state === GameState::Lost && $this->mines[$cell])
                    $row .= $cell === $this->exploded ? '!' : ($this->marks[$cell] === Mark::Flag ? 'F' : '*');
                elseif ($this->state === GameState::Lost && $this->marks[$cell] === Mark::Flag) $row .= 'X';
                elseif ($this->revealed[$cell]) $row .= $this->numbers[$cell] === 0 ? '.' : (string)$this->numbers[$cell];
                else $row .= match ($this->marks[$cell]) { Mark::Flag => 'F', Mark::Question => '?', Mark::None => '#' };
            }
            emit($row);
        }
    }
    public function ending(): void
    {
        if ($this->state === GameState::Lost) { emit('boom', $this->cell($this->exploded)); $this->display(); }
        elseif ($this->state === GameState::Won) emit('win moves', count($this->moves));
    }
    private function constraints(): array
    {
        $constraints = [];
        for ($cell = 0; $cell < $this->size; $cell++)
            if ($this->revealed[$cell] && $this->numbers[$cell] > 0) {
                $unknown = $this->unknownNeighbors($cell);
                if ($unknown !== []) $constraints[] = new Constraint($cell, $unknown, $this->numbers[$cell] - $this->flags($cell));
            }
        return $constraints;
    }
    public function deduce(): Deduction
    {
        $result = new Deduction($this->size);
        $constraints = $this->constraints();
        foreach ($constraints as $c) if ($c->remaining === 0)
            foreach ($c->unknown as $cell) $result->safe[$cell] ??= 'single ' . $this->cell($c->cell);
        if ($result->any()) return $result;
        foreach ($constraints as $c) if ($c->remaining === count($c->unknown))
            foreach ($c->unknown as $cell) $result->mines[$cell] ??= 'single ' . $this->cell($c->cell);
        if ($result->any()) return $result;
        foreach ($constraints as $a)
            foreach ($constraints as $b) {
                if (count($a->unknown) >= count($b->unknown) || array_diff($a->unknown, $b->unknown) !== []) continue;
                $difference = array_diff($b->unknown, $a->unknown);
                $remaining = $b->remaining - $a->remaining;
                $reason = 'subset ' . $this->cell($a->cell) . ' ' . $this->cell($b->cell);
                if ($remaining === 0) foreach ($difference as $cell) $result->safe[$cell] ??= $reason;
                if ($remaining === count($difference)) foreach ($difference as $cell) $result->mines[$cell] ??= $reason;
            }
        if ($result->any()) return $result;
        if ($this->state === GameState::Playing && $this->remaining() === 0)
            for ($cell = 0; $cell < $this->size; $cell++) if ($this->unknown($cell)) $result->safe[$cell] = 'count';
        return $result;
    }
    public function frontier(): Frontier
    {
        $constraints = $this->constraints();
        $links = array_fill(0, $this->size, []);
        foreach ($constraints as $i => $c) foreach ($c->unknown as $cell) $links[$cell][] = $i;
        $seen = array_fill(0, $this->size, false);
        $at = array_fill(0, $this->size, null); $components = [];
        for ($start = 0; $start < $this->size; $start++) {
            if ($seen[$start] || $links[$start] === []) continue;
            $cells = [$start]; $selected = []; $picked = [];
            $seen[$start] = true;
            for ($head = 0; $head < count($cells); $head++)
                foreach ($links[$cells[$head]] as $c) {
                    if (isset($picked[$c])) continue;
                    $picked[$c] = true; $selected[] = $constraints[$c];
                    foreach ($constraints[$c]->unknown as $cell)
                        if (!$seen[$cell]) { $seen[$cell] = true; $cells[] = $cell; }
                }
            sort($cells, SORT_NUMERIC);
            $component = new Component($cells, $selected);
            $components[] = $component;
            foreach ($cells as $cell) $at[$cell] = $component;
        }
        return new Frontier($components, $at);
    }
    public function auto(Safety $safety): Totals
    {
        $total = new Totals();
        while ($this->state === GameState::Playing) {
            $deduction = $this->deduce();
            if (!$deduction->any()) break;
            $total->rounds++;
            foreach ($deduction->safe as $cell => $reason)
                if ($reason !== null && !$this->revealed[$cell]) {
                    $this->moves[] = new Move(MoveKind::AutoReveal, $cell);
                    $total->opened += $this->reveal($cell, $safety);
                    $this->checkWin();
                    if ($this->finished()) return $total;
                }
            foreach ($deduction->mines as $cell => $reason)
                if ($reason !== null && $this->unknown($cell)) {
                    $this->marks[$cell] = Mark::Flag; $total->flagged++;
                    $this->moves[] = new Move(MoveKind::AutoFlag, $cell);
                }
        }
        return $total;
    }
    public function solve(Safety $safety): Totals
    {
        $total = new Totals();
        while (!$this->finished()) {
            $total->add($this->auto($safety));
            if ($this->finished()) break;
            $frontier = $this->frontier();
            foreach ($frontier->components as $component) $component->count();
            $unknownCount = 0;
            for ($cell = 0; $cell < $this->size; $cell++) if ($this->unknown($cell)) $unknownCount++;
            $background = max($this->remaining(), 0);
            $best = null; $bestNumerator = 0; $bestDenominator = 1;
            for ($cell = 0; $cell < $this->size; $cell++) {
                if (!$this->unknown($cell)) continue;
                $component = $frontier->at[$cell];
                if ($component !== null) {
                    if ($component->configurations === 0) continue;
                    $numerator = $component->mineCount($cell); $denominator = $component->configurations;
                } else { $numerator = $background; $denominator = $unknownCount; }
                if ($best === null || $numerator * $bestDenominator < $bestNumerator * $denominator) {
                    $best = $cell; $bestNumerator = $numerator; $bestDenominator = $denominator;
                }
            }
            if ($best === null) break;
            $total->guesses++; $this->moves[] = new Move(MoveKind::Guess, $best);
            $total->opened += $this->reveal($best, $safety);
            $this->checkWin();
        }
        return $total;
    }
    public function replay(int $count, Safety $safety): self
    {
        $copy = $this->copy(true);
        for ($i = 0; $i < $count; $i++) {
            $move = $this->moves[$i]; $cell = $move->cell;
            switch ($move->kind) {
                case MoveKind::Reveal: case MoveKind::AutoReveal: case MoveKind::Guess: $copy->reveal($cell, $safety); break;
                case MoveKind::Chord: $copy->chord($cell, $safety); break;
                case MoveKind::Flag: case MoveKind::AutoFlag: $copy->marks[$cell] = Mark::Flag; break;
                case MoveKind::Unflag: $copy->marks[$cell] = Mark::None; break;
                case MoveKind::Question: $copy->marks[$cell] = $copy->marks[$cell] === Mark::Question ? Mark::None : Mark::Question; break;
            }
            $copy->checkWin();
        }
        return $copy;
    }
    public function boardInfo(): void
    {
        $blank = [];
        for ($cell = 0; $cell < $this->size; $cell++) $blank[] = !$this->mines[$cell] && $this->numbers[$cell] === 0;
        $seen = array_fill(0, $this->size, false);
        $openings = 0; $largest = 0; $isolated = 0;
        for ($start = 0; $start < $this->size; $start++) {
            if ($blank[$start] && !$seen[$start]) {
                $openings++; $queue = [$start]; $seen[$start] = true;
                $area = [$start => true];
                for ($head = 0; $head < count($queue); $head++)
                    foreach ($this->neighbors[$queue[$head]] as $cell) {
                        $area[$cell] = true;
                        if ($blank[$cell] && !$seen[$cell]) { $seen[$cell] = true; $queue[] = $cell; }
                    }
                $largest = max($largest, count($area));
            }
            if (!$this->mines[$start] && !$blank[$start] && !array_filter($this->neighbors[$start], fn(int $cell): bool => $blank[$cell])) $isolated++;
        }
        emit('3bv', $openings + $isolated, 'openings', $openings, 'largest', $largest, 'mines', $this->mineCount, 'safe', $this->size - $this->mineCount);
    }
}

final class Program
{
    private const ARITY = [
        'NEW' => 4, 'PRESET' => 2, 'SAFETY' => 1, 'RESTART' => 0, 'REVEAL' => 2, 'FLAG' => 2,
        'UNFLAG' => 2, 'QUESTION' => 2, 'CHORD' => 2, 'UNDO' => 0, 'SHOW' => 0, 'STATUS' => 0,
        'CELL' => 2, 'HISTORY' => 1, 'REPLAY' => 1, 'HINT' => 0, 'AUTO' => 0, 'ANALYZE' => 0,
        'PROB' => 2, 'FRONTIER' => 0, 'SOLVE' => 0, 'BOARDINFO' => 0, 'STATS' => 0,
    ];
    private ?Game $game = null;
    private Safety $safety = Safety::Block;
    private int $played = 0, $won = 0, $lost = 0, $streak = 0, $bestStreak = 0;
    private ?int $fastest = null;

    private function layout(array $words): void
    {
        $width = (int)$words[1]; $height = (int)$words[2]; $rows = [];
        for ($i = 0; $i < $height; $i++) $rows[] = inputLine();
        $mines = [];
        foreach ($rows as $i => $row) {
            if (strlen($row) !== $width || strspn($row, '.*') !== $width) fail('bad row ' . ($i + 1));
            for ($x = 0; $x < $width; $x++) $mines[] = $row[$x] === '*';
        }
        $count = count(array_filter($mines));
        if ($count === 0 || $count === $width * $height) fail("bad mine count $count");
        $this->game = new Game($width, $height, $count, 1, $mines);
        emit('layout', "{$width}x{$height}", 'mines', $count);
    }
    private function number(string $word): int
    {
        if (!preg_match('/\A(?:0|[1-9][0-9]{0,9})\z/', $word)) fail('bad arguments');
        return (int)$word;
    }
    private function stats(): void
    {
        $rate = $this->played === 0 ? '-' : intdiv($this->won * 100, $this->played) . '%';
        emit('stats played', $this->played, 'won', $this->won, 'lost', $this->lost, 'rate', $rate,
            'streak', $this->streak, 'best', $this->bestStreak, 'fastest', $this->fastest ?? '-');
    }
    private function recordFinish(Game $game): void
    {
        $this->played++;
        if ($game->state === GameState::Won) {
            $this->won++; $this->streak++;
            $this->bestStreak = max($this->bestStreak, $this->streak);
            $this->fastest = min($this->fastest ?? count($game->moves), count($game->moves));
        } else { $this->lost++; $this->streak = 0; }
    }
    public function execute(array $words): void
    {
        $op = $words[0];
        if ($op === 'LAYOUT') { $this->layout($words); return; }
        if (!isset(self::ARITY[$op])) fail("unknown command $op");
        if (count($words) !== self::ARITY[$op] + 1) fail('bad arguments');
        $hasCell = in_array($op, ['REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'CELL', 'PROB'], true);
        $values = [];
        if ($op === 'NEW' || $hasCell || $op === 'HISTORY' || $op === 'REPLAY')
            $values = array_map($this->number(...), array_slice($words, 1));
        elseif ($op === 'PRESET') {
            if (!in_array($words[1], ['beginner', 'intermediate', 'expert'], true)) fail('bad arguments');
            $values = [$this->number($words[2])];
        } elseif ($op === 'SAFETY' && Safety::tryFrom($words[1]) === null) fail('bad arguments');

        if ($op === 'NEW' || $op === 'PRESET') {
            if ($op === 'NEW') [$width, $height, $mines, $seed] = $values;
            else {
                [$width, $height, $mines] = match ($words[1]) {
                    'beginner' => [9, 9, 10], 'intermediate' => [16, 16, 40], 'expert' => [30, 16, 99],
                };
                $seed = $values[0];
            }
            if ($width < 1 || $width > 30 || $height < 1 || $height > 30 || $mines < 1 || $mines > $width * $height - 9 || $seed < 1 || $seed > 2147483646) fail('bad value');
            $this->game = new Game($width, $height, $mines, $seed);
            emit('new', "{$width}x{$height}", 'mines', $mines); return;
        }
        if ($op === 'HISTORY' && $values[0] === 0) fail('bad value');
        if ($op === 'SAFETY') { $this->safety = Safety::from($words[1]); emit('safety', $words[1]); return; }
        if ($op === 'STATS') { $this->stats(); return; }
        $game = $this->game ?? fail('no game');
        if ($hasCell && ($values[0] >= $game->width || $values[1] >= $game->height)) fail('out of range');
        $cell = $hasCell ? $values[1] * $game->width + $values[0] : 0;
        if ($game->finished() && in_array($op, ['REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'UNDO', 'HINT', 'AUTO', 'ANALYZE', 'PROB', 'FRONTIER', 'SOLVE'], true)) fail('game over');
        if (($op === 'ANALYZE' || $op === 'BOARDINFO') && $game->mines === null) fail('not started');
        $wasFinished = $game->finished();
        $saved = in_array($op, ['REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'AUTO', 'SOLVE'], true) ? $game->snapshot(strtolower($op)) : null;

        switch ($op) {
            case 'RESTART':
                $game->restart(); emit('restart', "{$game->width}x{$game->height}", 'mines', $game->mineCount); break;
            case 'REVEAL':
                if ($game->revealed[$cell]) fail('already revealed');
                if ($game->marks[$cell] === Mark::Flag) fail('flagged');
                $game->moves[] = new Move(MoveKind::Reveal, $cell);
                $opened = $game->reveal($cell, $this->safety);
                if ($game->state !== GameState::Lost) { emit('revealed', $opened); $game->checkWin(); }
                $game->ending(); break;
            case 'FLAG': case 'UNFLAG': case 'QUESTION':
                if ($game->revealed[$cell]) fail('already revealed');
                if ($op === 'FLAG' && $game->marks[$cell] === Mark::Flag) fail('already flagged');
                if ($op === 'UNFLAG' && $game->marks[$cell] !== Mark::Flag) fail('not flagged');
                if ($op === 'FLAG') { $mark = Mark::Flag; $kind = MoveKind::Flag; $verb = 'flagged'; }
                elseif ($op === 'UNFLAG') { $mark = Mark::None; $kind = MoveKind::Unflag; $verb = 'unflagged'; }
                else {
                    $mark = $game->marks[$cell] === Mark::Question ? Mark::None : Mark::Question;
                    $kind = MoveKind::Question; $verb = $mark === Mark::None ? 'unmarked' : 'questioned';
                }
                $game->marks[$cell] = $mark; $game->moves[] = new Move($kind, $cell);
                emit($verb, $game->cell($cell), 'left', $game->remaining()); break;
            case 'CHORD':
                if (!$game->revealed[$cell]) fail('not revealed');
                if ($game->numbers[$cell] === 0) fail('no number');
                $flags = $game->flags($cell);
                if ($flags !== $game->numbers[$cell]) fail("flags $flags of {$game->numbers[$cell]}");
                if ($game->unknownNeighbors($cell) === []) fail('nothing to reveal');
                $game->moves[] = new Move(MoveKind::Chord, $cell);
                $opened = $game->chord($cell, $this->safety);
                if ($game->state !== GameState::Lost) { emit('chorded', $opened); $game->checkWin(); }
                $game->ending(); break;
            case 'UNDO':
                if ($game->undo === []) fail('nothing to undo');
                $record = array_pop($game->undo); $game->restore($record);
                emit('undo', $record->name, 'moves', count($game->moves)); break;
            case 'SHOW': $game->display(); break;
            case 'STATUS':
                emit('status', $game->state->value, 'left', $game->remaining(), 'moves', count($game->moves), 'revealed', $game->openCount() . '/' . ($game->size - $game->mineCount)); break;
            case 'CELL':
                if ($game->revealed[$cell]) emit('cell', $game->cell($cell), 'number', $game->numbers[$cell], 'flags', $game->flags($cell), 'unknown', count($game->unknownNeighbors($cell)));
                else emit('cell', $game->cell($cell), 'hidden mark', $game->marks[$cell]->value, 'open', count(array_filter($game->neighbors[$cell], fn(int $other): bool => $game->revealed[$other])));
                break;
            case 'HISTORY':
                $count = count($game->moves); emit('history', $count);
                for ($i = max(0, $count - $values[0]); $i < $count; $i++) {
                    $move = $game->moves[$i]; emit($i + 1, $move->kind->value, $game->cell($move->cell));
                }
                break;
            case 'REPLAY':
                if ($values[0] > count($game->moves)) fail("no move {$values[0]}");
                emit('replay', $values[0] . '/' . count($game->moves));
                $game->replay($values[0], $this->safety)->display(); break;
            case 'HINT':
                $deduction = $game->deduce(); $found = false;
                foreach (['safe' => $deduction->safe, 'mine' => $deduction->mines] as $kind => $reasons) {
                    foreach ($reasons as $at => $reason)
                        if ($reason !== null) { emit('hint', $kind, $game->cell($at), 'by', $reason); $found = true; break 2; }
                }
                if (!$found) emit('hint none');
                break;
            case 'AUTO': case 'SOLVE':
                $total = $op === 'AUTO' ? $game->auto($this->safety) : $game->solve($this->safety);
                if ($op === 'AUTO') emit('auto rounds', $total->rounds, 'flagged', $total->flagged, 'revealed', $total->opened);
                else emit('solve guesses', $total->guesses, 'rounds', $total->rounds, 'flagged', $total->flagged, 'revealed', $total->opened);
                $game->ending(); break;
            case 'ANALYZE':
                $copy = $game->copy(); $total = $copy->auto($this->safety);
                if ($copy->state === GameState::Lost) emit('analyze boom', $copy->cell($copy->exploded), 'rounds', $total->rounds);
                elseif ($copy->state === GameState::Won) emit('analyze clear rounds', $total->rounds);
                else emit('analyze stuck rounds', $total->rounds, 'revealed', $copy->openCount() . '/' . ($copy->size - $copy->mineCount));
                break;
            case 'PROB':
                if ($game->revealed[$cell]) fail('already revealed');
                if ($game->marks[$cell] === Mark::Flag) fail('flagged');
                $component = $game->frontier()->at[$cell];
                if ($component === null) emit('prob', $game->cell($cell), 'unconstrained');
                else {
                    $component->count();
                    if ($component->configurations === 0) emit('prob', $game->cell($cell), 'inconsistent');
                    else emit('prob', $game->cell($cell), fraction($component->mineCount($cell), $component->configurations), 'size', count($component->cells), 'configs', $component->configurations);
                }
                break;
            case 'FRONTIER':
                $frontier = $game->frontier();
                emit('frontier', count(array_filter($frontier->at)), 'components', count($frontier->components));
                foreach ($frontier->components as $component) {
                    $component->count(); $at = $game->cell($component->cells[0]); $size = count($component->cells);
                    if ($component->configurations === 0) emit('component', $at, 'size', $size, 'inconsistent');
                    else emit('component', $at, 'size', $size, 'configs', $component->configurations, 'min', $component->minimum, 'max', $component->maximum);
                }
                break;
            case 'BOARDINFO': $game->boardInfo(); break;
        }
        if ($saved !== null && count($game->moves) > $saved->moveCount) $game->undo[] = $saved;
        if (!$wasFinished && $game->finished()) $this->recordFinish($game);
    }
}

$program = new Program();
$commandCount = (int)inputLine();
for ($command = 0; $command < $commandCount; $command++) {
    try { $program->execute(explode(' ', inputLine())); }
    catch (CommandError $error) { emit('error:', $error->getMessage()); }
}
