<?php

declare(strict_types=1);

const DIRECTIONS = ['u', 'd', 'l', 'r'];
const TURNS = [
    'ROT90' => 'rlud', 'ROT180' => 'durl', 'ROT270' => 'lrdu',
    'FLIPH' => 'udrl', 'FLIPV' => 'dulr',
];
const LEVEL_CHARACTERS = '#-.$*@+';
const STEP_CHARACTERS = 'udlrUDLR';
const COMMANDS = [
    'IMPORT' => ['text'], 'VALID' => [], 'INFO' => [], 'SHOW' => [], 'EXPORT' => [],
    'MOVE' => ['steps'], 'PUSH' => ['number', 'number', 'direction'],
    'BRING' => ['number', 'number', 'number', 'number'], 'PATH' => ['number', 'number'],
    'UNDO' => ['number'], 'REDO' => ['number'], 'RESET' => [], 'STATUS' => [],
    'HISTORY' => [], 'BOXES' => [], 'REACH' => [], 'DEADSQUARES' => [],
    'DEADLOCK' => [], 'BOUND' => [], 'SAVE' => ['name'], 'RESTORE' => ['name'],
    'CHECK' => ['steps'], 'SOLVE' => ['number'], 'HINT' => ['number'], 'PLAY' => [],
    'TRANSFORM' => ['transform'],
];

final class CommandError extends RuntimeException {}
final class StepFailure extends RuntimeException {}

final readonly class Position
{
    public function __construct(public ?int $player, public array $boxes) {}
}

final readonly class SearchNode
{
    public function __construct(
        public array $boxes,
        public int $representative,
        public ?int $parent,
        public ?array $push,
    ) {}
}

final readonly class SearchResult
{
    public function __construct(
        public string $outcome,
        public int $expanded,
        public int $states,
        public ?string $notation = null,
    ) {}
}

function decode(string $text, string $allowed): ?string
{
    $result = '';
    for ($index = 0; $index < strlen($text); $index++) {
        $start = $index;
        while ($index < strlen($text) && ctype_digit($text[$index])) {
            $index++;
        }
        $count = substr($text, $start, $index - $start);
        if (strlen($count) > 2 || str_starts_with($count, '0') || $index === strlen($text)) {
            return null;
        }
        if (!str_contains($allowed, $text[$index])) {
            return null;
        }
        $result .= str_repeat($text[$index], $count === '' ? 1 : (int) $count);
    }
    return $result;
}

function encode(string $text): string
{
    $result = '';
    for ($start = 0; $start < strlen($text); $start = $end) {
        $end = $start + 1;
        while ($end < strlen($text) && $text[$end] === $text[$start]) {
            $end++;
        }
        $count = $end - $start;
        $result .= ($count > 1 ? (string) $count : '') . $text[$start];
    }
    return $result;
}

function validArgument(string $kind, string $text): bool
{
    return match ($kind) {
        'number' => preg_match('/\A(?:0|[1-9][0-9]{0,5})\z/', $text) === 1,
        'steps' => decode($text, STEP_CHARACTERS) !== null,
        'direction' => in_array($text, DIRECTIONS, true),
        'name' => preg_match('/\A[a-z]{1,8}\z/', $text) === 1,
        'transform' => array_key_exists($text, TURNS),
        default => true,
    };
}

function pushCount(string $letters): int
{
    return preg_match_all('/[UDLR]/', $letters);
}

function movedBoxes(array $boxes, int $source, int $destination): array
{
    $moved = array_map(fn(int $box): int => $box === $source ? $destination : $box, $boxes);
    sort($moved, SORT_NUMERIC);
    return $moved;
}

function turnLetters(string $letters, string $kind): string
{
    return strtr($letters, 'udlrUDLR', TURNS[$kind] . strtoupper(TURNS[$kind]));
}

final class Level
{
    public int $height;
    public int $width;
    public array $walls;
    public array $goals;
    public array $interior;
    public array $goalCells;
    public array $offsets;
    public array $distances = [];
    public array $dead = [];
    public ?string $reason;
    public Position $loadedPosition;

    public function __construct(array $rows)
    {
        $this->height = count($rows);
        $this->width = strlen($rows[0]);
        $cells = str_split(implode('', $rows));
        $this->walls = array_map(fn(string $letter): bool => $letter === '#', $cells);
        $this->goals = array_map(fn(string $letter): bool => str_contains('.*+', $letter), $cells);
        $this->goalCells = array_keys(array_filter($this->goals));
        $players = array_keys(array_filter($cells, fn(string $letter): bool => str_contains('@+', $letter)));
        $boxes = array_keys(array_filter($cells, fn(string $letter): bool => str_contains('$*', $letter)));
        $this->offsets = ['u' => -$this->width, 'd' => $this->width, 'l' => -1, 'r' => 1];
        $this->interior = array_fill(0, $this->size(), false);
        if (count($players) === 1) {
            $this->interior[$players[0]] = true;
            $stack = [$players[0]];
            while ($stack !== []) {
                $cell = array_pop($stack);
                $row = intdiv($cell, $this->width);
                $column = $cell % $this->width;
                foreach ([[$row - 1, $column], [$row + 1, $column], [$row, $column - 1], [$row, $column + 1]] as [$r, $c]) {
                    if ($r < 0 || $r >= $this->height || $c < 0 || $c >= $this->width) {
                        continue;
                    }
                    $neighbor = $r * $this->width + $c;
                    if (!$this->walls[$neighbor] && !$this->interior[$neighbor]) {
                        $this->interior[$neighbor] = true;
                        $stack[] = $neighbor;
                    }
                }
            }
        }
        $this->reason = $this->invalidity(count($players), $boxes);
        if ($this->reason === null) {
            $this->analyze();
        }
        $this->loadedPosition = new Position($players[0] ?? null, $boxes);
    }

    public function size(): int
    {
        return $this->height * $this->width;
    }

    public function cellText(int $cell): string
    {
        return (intdiv($cell, $this->width) + 1) . ' ' . ($cell % $this->width + 1);
    }

    public function cellAt(int $row, int $column): int
    {
        return ($row - 1) * $this->width + $column - 1;
    }

    public function contains(int $row, int $column): bool
    {
        return $row >= 1 && $row <= $this->height && $column >= 1 && $column <= $this->width;
    }

    public function boxesOnGoals(array $boxes): int
    {
        return count(array_filter($boxes, fn(int $box): bool => $this->goals[$box]));
    }

    public function solved(array $boxes): bool
    {
        return $this->boxesOnGoals($boxes) === count($boxes);
    }

    private function invalidity(int $players, array $boxes): ?string
    {
        if ($players !== 1) {
            return "players $players";
        }
        if ($boxes === []) {
            return 'no boxes';
        }
        if (count($boxes) !== count($this->goalCells)) {
            return 'boxes ' . count($boxes) . ' goals ' . count($this->goalCells);
        }
        for ($cell = 0; $cell < $this->size(); $cell++) {
            $row = intdiv($cell, $this->width);
            $column = $cell % $this->width;
            if ($this->interior[$cell] && ($row === 0 || $row === $this->height - 1 || $column === 0 || $column === $this->width - 1)) {
                return 'open ' . $this->cellText($cell);
            }
        }
        for ($cell = 0; $cell < $this->size(); $cell++) {
            if (($this->goals[$cell] || in_array($cell, $boxes, true)) && !$this->interior[$cell]) {
                return 'outside ' . $this->cellText($cell);
            }
        }
        return null;
    }

    private function analyze(): void
    {
        foreach ($this->goalCells as $goal) {
            $distance = array_fill(0, $this->size(), null);
            $distance[$goal] = 0;
            $queue = [$goal];
            for ($head = 0; $head < count($queue); $head++) {
                $cell = $queue[$head];
                foreach ($this->offsets as $offset) {
                    $box = $cell - $offset;
                    if ($this->interior[$box] && $this->interior[$box - $offset] && $distance[$box] === null) {
                        $distance[$box] = $distance[$cell] + 1;
                        $queue[] = $box;
                    }
                }
            }
            $this->distances[] = $distance;
        }
        $this->dead = array_fill(0, $this->size(), false);
        for ($cell = 0; $cell < $this->size(); $cell++) {
            $defined = array_filter($this->distances, fn(array $distance): bool => $distance[$cell] !== null);
            $this->dead[$cell] = $this->interior[$cell] && $defined === [];
        }
    }

    public function reachable(int $player, array $boxes): array
    {
        $seen = array_fill(0, $this->size(), false);
        $seen[$player] = true;
        $queue = [$player];
        for ($head = 0; $head < count($queue); $head++) {
            foreach ($this->offsets as $offset) {
                $neighbor = $queue[$head] + $offset;
                if ($this->interior[$neighbor] && !$seen[$neighbor] && !in_array($neighbor, $boxes, true)) {
                    $seen[$neighbor] = true;
                    $queue[] = $neighbor;
                }
            }
        }
        return $seen;
    }

    public function representative(int $player, array $boxes): int
    {
        return array_search(true, $this->reachable($player, $boxes), true);
    }

    public function walkPath(int $start, int $target, array $boxes): string
    {
        $parents = array_fill(0, $this->size(), null);
        $queue = [$start];
        for ($head = 0; $head < count($queue); $head++) {
            $cell = $queue[$head];
            foreach ($this->offsets as $direction => $offset) {
                $neighbor = $cell + $offset;
                if ($this->interior[$neighbor] && $neighbor !== $start && $parents[$neighbor] === null && !in_array($neighbor, $boxes, true)) {
                    $parents[$neighbor] = [$cell, $direction];
                    $queue[] = $neighbor;
                }
            }
        }
        $path = '';
        while ($target !== $start) {
            [$target, $direction] = $parents[$target];
            $path .= $direction;
        }
        return strrev($path);
    }

    public function step(Position $position, string $direction): array
    {
        $offset = $this->offsets[$direction];
        $target = $position->player + $offset;
        if ($this->walls[$target]) {
            throw new StepFailure('wall');
        }
        if (!in_array($target, $position->boxes, true)) {
            return [new Position($target, $position->boxes), $direction];
        }
        $beyond = $target + $offset;
        if ($this->walls[$beyond] || in_array($beyond, $position->boxes, true)) {
            throw new StepFailure('blocked');
        }
        return [new Position($target, movedBoxes($position->boxes, $target, $beyond)), strtoupper($direction)];
    }

    public function pushable(int $box, string $direction, array $boxes, array $reach): bool
    {
        $offset = $this->offsets[$direction];
        return $reach[$box - $offset] && $this->interior[$box + $offset] && !in_array($box + $offset, $boxes, true);
    }

    private function sideBlocked(int $box, array $sides, array $boxes, array $assumed): bool
    {
        foreach ($sides as $side) {
            if ($this->walls[$side] || in_array($side, $assumed, true)) {
                return true;
            }
        }
        if ($this->dead[$sides[0]] && $this->dead[$sides[1]]) {
            return true;
        }
        $assumed[] = $box;
        foreach ($sides as $side) {
            if (in_array($side, $boxes, true) && $this->frozen($side, $boxes, $assumed)) {
                return true;
            }
        }
        return false;
    }

    public function frozen(int $box, array $boxes, array $assumed = []): bool
    {
        return $this->sideBlocked($box, [$box - 1, $box + 1], $boxes, $assumed)
            && $this->sideBlocked($box, [$box - $this->width, $box + $this->width], $boxes, $assumed);
    }

    public function hasFrozenBox(array $boxes): bool
    {
        foreach ($boxes as $box) {
            if (!$this->goals[$box] && $this->frozen($box, $boxes)) {
                return true;
            }
        }
        return false;
    }

    public function render(?Position $position = null): array
    {
        $symbols = '';
        for ($cell = 0; $cell < $this->size(); $cell++) {
            $symbols .= match (true) {
                $this->walls[$cell] => '#',
                $position === null => $this->goals[$cell] ? '.' : ($this->dead[$cell] ? 'x' : '-'),
                $cell === $position->player => $this->goals[$cell] ? '+' : '@',
                in_array($cell, $position->boxes, true) => $this->goals[$cell] ? '*' : '$',
                default => $this->goals[$cell] ? '.' : '-',
            };
        }
        return str_split($symbols, $this->width);
    }

    public function mapCell(string $kind, int $cell): int
    {
        $row = intdiv($cell, $this->width);
        $column = $cell % $this->width;
        return match ($kind) {
            'ROT90' => $column * $this->height + $this->height - 1 - $row,
            'ROT180' => ($this->height - 1 - $row) * $this->width + $this->width - 1 - $column,
            'ROT270' => ($this->width - 1 - $column) * $this->height + $row,
            'FLIPH' => $row * $this->width + $this->width - 1 - $column,
            default => ($this->height - 1 - $row) * $this->width + $column,
        };
    }

    public function mapPosition(string $kind, Position $position): Position
    {
        $boxes = array_map(fn(int $box): int => $this->mapCell($kind, $box), $position->boxes);
        sort($boxes, SORT_NUMERIC);
        return new Position($this->mapCell($kind, $position->player), $boxes);
    }

    public function transformed(string $kind): self
    {
        $width = in_array($kind, ['ROT90', 'ROT270'], true) ? $this->height : $this->width;
        $symbols = array_fill(0, $this->size(), '');
        foreach (str_split(implode('', $this->render($this->loadedPosition))) as $cell => $letter) {
            $symbols[$this->mapCell($kind, $cell)] = $letter;
        }
        return new self(str_split(implode('', $symbols), $width));
    }
}

function pushSearch(Level $level, Position $start, array $fixed = [], ?int $target = null, bool $pruning = true, ?int $limit = null): SearchResult
{
    $first = new SearchNode($start->boxes, $level->representative($start->player, $start->boxes), null, null);
    $nodes = [$first];
    $key = static fn(array $boxes, int $representative): string => implode(',', $boxes) . ':' . $representative;
    $known = [$key($first->boxes, $first->representative) => true];
    $expanded = 0;
    while ($expanded < count($nodes)) {
        if ($expanded === $limit) {
            return new SearchResult('limit', $expanded, count($nodes));
        }
        $parent = $expanded;
        $node = $nodes[$expanded++];
        $reach = $level->reachable($node->representative, $node->boxes);
        foreach ($node->boxes as $box) {
            if (in_array($box, $fixed, true)) {
                continue;
            }
            foreach (DIRECTIONS as $direction) {
                if (!$level->pushable($box, $direction, $node->boxes, $reach)) {
                    continue;
                }
                $destination = $box + $level->offsets[$direction];
                $boxes = movedBoxes($node->boxes, $box, $destination);
                if ($pruning && ($level->dead[$destination] || $level->hasFrozenBox($boxes))) {
                    continue;
                }
                $representative = $level->representative($box, $boxes);
                $state = $key($boxes, $representative);
                if (isset($known[$state])) {
                    continue;
                }
                $known[$state] = true;
                $nodes[] = new SearchNode($boxes, $representative, $parent, [$box, $direction]);
                if (!($target === null ? $level->solved($boxes) : $destination === $target)) {
                    continue;
                }
                $pushes = [];
                $cursor = $nodes[array_key_last($nodes)];
                while ($cursor->parent !== null) {
                    $pushes[] = $cursor->push;
                    $cursor = $nodes[$cursor->parent];
                }
                $position = $start;
                $notation = '';
                foreach (array_reverse($pushes) as [$source, $step]) {
                    $offset = $level->offsets[$step];
                    $notation .= $level->walkPath($position->player, $source - $offset, $position->boxes) . strtoupper($step);
                    $position = new Position($source, movedBoxes($position->boxes, $source, $source + $offset));
                }
                return new SearchResult('found', $expanded, count($nodes), $notation);
            }
        }
    }
    return new SearchResult('no solution', $expanded, count($nodes));
}

final class Sokoban
{
    private Level $level;
    private Position $initial;
    private Position $current;
    private string $history = '';
    private string $redo = '';
    private array $snapshots = [];
    private ?array $solution = null;

    public function __construct(array $rows)
    {
        $this->load($rows);
    }

    private function load(array $rows): void
    {
        $this->level = new Level($rows);
        $this->initial = $this->current = $this->level->loadedPosition;
        $this->history = $this->redo = '';
        $this->snapshots = [];
        $this->solution = null;
    }

    private function emit(string|int ...$parts): void
    {
        echo implode(' ', $parts), "\n";
    }

    private function cell(array $arguments, int $index = 0): int
    {
        return $this->level->cellAt((int) $arguments[$index], (int) $arguments[$index + 1]);
    }

    private function simulate(string $directions): array
    {
        $position = $this->current;
        $letters = '';
        try {
            foreach (str_split($directions) as $direction) {
                [$position, $letter] = $this->level->step($position, $direction);
                $letters .= $letter;
            }
        } catch (StepFailure $error) {
            return [$position, $letters, 'step ' . (strlen($letters) + 1) . ' ' . $error->getMessage()];
        }
        return [$position, $letters, null];
    }

    private function takeSteps(string $directions): array
    {
        [$this->current, $letters, $failure] = $this->simulate($directions);
        $this->history .= $letters;
        if ($letters !== '') {
            $this->redo = '';
        }
        return [$letters, $failure];
    }

    private function progress(array $boxes): string
    {
        $count = $this->level->boxesOnGoals($boxes);
        return "goals $count/" . count($boxes) . ($count === count($boxes) ? ' solved' : '');
    }

    private function counted(string $label, string $letters): void
    {
        if ($letters === '') {
            $this->emit($label, 0);
        } else {
            $this->emit($label, strlen($letters), $letters);
        }
    }

    private function searchSolution(int $limit): array
    {
        if ($this->level->solved($this->current->boxes)) {
            return ['already solved', null];
        }
        $result = pushSearch($this->level, $this->current, limit: $limit);
        $counts = "expanded {$result->expanded} states {$result->states}";
        if ($result->outcome !== 'found') {
            return ["{$result->outcome} $counts", null];
        }
        $notation = $result->notation;
        return ['solution pushes ' . pushCount($notation) . ' moves ' . strlen($notation) . " $counts", $notation];
    }

    public function execute(array $words, array $rows = []): void
    {
        $name = $words[0];
        $arguments = array_slice($words, 1);
        try {
            if ($name === 'LOAD') {
                foreach ($rows as $index => $row) {
                    if (strlen($row) !== (int) $arguments[1] || strspn($row, LEVEL_CHARACTERS) !== strlen($row)) {
                        throw new CommandError('bad row ' . ($index + 1));
                    }
                }
                $this->load($rows);
                $this->emit('loaded', "{$this->level->height}x{$this->level->width}");
                return;
            }
            if (!array_key_exists($name, COMMANDS)) {
                throw new CommandError("unknown command $name");
            }
            $kinds = COMMANDS[$name];
            if (count($arguments) !== count($kinds)) {
                throw new CommandError('bad arguments');
            }
            foreach ($kinds as $index => $kind) {
                if (!validArgument($kind, $arguments[$index])) {
                    throw new CommandError('bad arguments');
                }
            }
            if (!in_array($name, ['IMPORT', 'VALID'], true)) {
                if ($this->level->reason !== null) {
                    throw new CommandError('invalid level');
                }
                $cells = ['PATH' => 1, 'PUSH' => 1, 'BRING' => 2][$name] ?? 0;
                for ($index = 0; $index < 2 * $cells; $index += 2) {
                    if (!$this->level->contains((int) $arguments[$index], (int) $arguments[$index + 1])) {
                        throw new CommandError('bad value');
                    }
                }
                if (in_array($name, ['UNDO', 'REDO'], true) && (int) $arguments[0] < 1) {
                    throw new CommandError('bad value');
                }
                if (in_array($name, ['SOLVE', 'HINT'], true) && ((int) $arguments[0] < 1 || (int) $arguments[0] > 100000)) {
                    throw new CommandError('bad value');
                }
            }
            $this->process($name, $arguments);
        } catch (CommandError $error) {
            $this->emit('error:', $error->getMessage());
        }
    }

    private function process(string $name, array $arguments): void
    {
        $level = $this->level;
        $position = $this->current;
        switch ($name) {
            case 'IMPORT':
                $rows = array_map(fn(string $part): ?string => decode($part, LEVEL_CHARACTERS), explode('|', $arguments[0]));
                if (in_array(null, $rows, true) || count($rows) > 10) {
                    throw new CommandError('bad level');
                }
                $width = strlen($rows[0]);
                if ($width < 1 || $width > 10 || array_filter($rows, fn(string $row): bool => strlen($row) !== $width) !== []) {
                    throw new CommandError('bad level');
                }
                $this->load($rows);
                $this->emit('loaded', "{$this->level->height}x{$this->level->width}");
                break;
            case 'VALID':
                $this->emit($level->reason === null ? 'valid' : "invalid {$level->reason}");
                break;
            case 'INFO':
                $this->emit('size', "{$level->height}x{$level->width}", 'walls', array_sum($level->walls), 'cells', array_sum($level->interior), 'boxes', count($position->boxes), 'dead', array_sum($level->dead));
                break;
            case 'SHOW':
                foreach ($level->render($position) as $row) {
                    $this->emit($row);
                }
                break;
            case 'EXPORT':
                $this->emit('level', implode('|', array_map(encode(...), $level->render($position))));
                break;
            case 'MOVE':
                [$letters, $failure] = $this->takeSteps(strtolower(decode($arguments[0], STEP_CHARACTERS)));
                if ($letters !== '') {
                    $this->emit('moved', $letters);
                }
                if ($failure !== null) {
                    throw new CommandError($failure);
                }
                break;
            case 'PUSH':
                $box = $this->cell($arguments);
                $direction = $arguments[2];
                $offset = $level->offsets[$direction];
                if (!in_array($box, $position->boxes, true)) {
                    throw new CommandError('no box');
                }
                if (!$level->interior[$box + $offset] || in_array($box + $offset, $position->boxes, true)) {
                    throw new CommandError('blocked');
                }
                if (!$level->reachable($position->player, $position->boxes)[$box - $offset]) {
                    throw new CommandError('unreachable');
                }
                [$letters] = $this->takeSteps($level->walkPath($position->player, $box - $offset, $position->boxes) . $direction);
                $this->emit('pushed', $letters);
                break;
            case 'BRING':
                $source = $this->cell($arguments);
                $target = $this->cell($arguments, 2);
                if (!in_array($source, $position->boxes, true)) {
                    throw new CommandError('no box');
                }
                if ($source === $target) {
                    $this->emit('brought', 0);
                    break;
                }
                $fixed = array_values(array_diff($position->boxes, [$source]));
                $result = pushSearch($level, $position, $fixed, $target, false);
                if ($result->outcome !== 'found') {
                    throw new CommandError('no route');
                }
                $this->takeSteps(strtolower($result->notation));
                $this->emit('brought', pushCount($result->notation), $result->notation);
                break;
            case 'PATH':
                $target = $this->cell($arguments);
                if (!$level->reachable($position->player, $position->boxes)[$target]) {
                    throw new CommandError('unreachable');
                }
                [$letters] = $this->takeSteps($level->walkPath($position->player, $target, $position->boxes));
                $this->counted('path', $letters);
                break;
            case 'UNDO':
                if ($this->history === '') {
                    throw new CommandError('nothing to undo');
                }
                $count = min((int) $arguments[0], strlen($this->history));
                for ($index = 0; $index < $count; $index++) {
                    $letter = substr($this->history, -1);
                    $this->history = substr($this->history, 0, -1);
                    $direction = strtolower($letter);
                    $offset = $level->offsets[$direction];
                    $boxes = $position->boxes;
                    if ($letter !== $direction) {
                        $boxes = movedBoxes($boxes, $position->player + $offset, $position->player);
                    }
                    $position = new Position($position->player - $offset, $boxes);
                    $this->redo .= $direction;
                }
                $this->current = $position;
                $this->emit('undone', $count);
                break;
            case 'REDO':
                if ($this->redo === '') {
                    throw new CommandError('nothing to redo');
                }
                $count = min((int) $arguments[0], strlen($this->redo));
                for ($index = 0; $index < $count; $index++) {
                    $direction = substr($this->redo, -1);
                    $this->redo = substr($this->redo, 0, -1);
                    [$this->current, $letter] = $level->step($this->current, $direction);
                    $this->history .= $letter;
                }
                $this->emit('redone', $count);
                break;
            case 'RESET':
                $this->current = $this->initial;
                $this->history = $this->redo = '';
                $this->emit('reset');
                break;
            case 'STATUS':
                $this->emit('moves', strlen($this->history), 'pushes', pushCount($this->history), $this->progress($position->boxes));
                break;
            case 'HISTORY':
                $this->counted('history', $this->history);
                break;
            case 'BOXES':
                $reach = $level->reachable($position->player, $position->boxes);
                $this->emit('boxes', count($position->boxes));
                foreach ($position->boxes as $box) {
                    $distances = array_filter(array_column($level->distances, $box), fn(?int $distance): bool => $distance !== null);
                    $directions = implode('', array_filter(DIRECTIONS, fn(string $direction): bool => $level->pushable($box, $direction, $position->boxes, $reach)));
                    $this->emit('box', $level->cellText($box), $distances === [] ? 'dead' : min($distances), $directions === '' ? '-' : $directions);
                }
                break;
            case 'REACH':
                $reach = $level->reachable($position->player, $position->boxes);
                $this->emit('reach', array_sum($reach), 'first', $level->cellText(array_search(true, $reach, true)));
                break;
            case 'DEADSQUARES':
                $this->emit('dead', array_sum($level->dead));
                foreach ($level->render() as $row) {
                    $this->emit($row);
                }
                break;
            case 'DEADLOCK':
                foreach ($position->boxes as $box) {
                    if ($level->dead[$box]) {
                        $this->emit('deadlock dead', $level->cellText($box));
                        return;
                    }
                }
                foreach ($position->boxes as $box) {
                    if (!$level->goals[$box] && $level->frozen($box, $position->boxes)) {
                        $this->emit('deadlock frozen', $level->cellText($box));
                        return;
                    }
                }
                $this->emit('no deadlock');
                break;
            case 'BOUND':
                $this->bound();
                break;
            case 'SAVE':
                $this->snapshots[$arguments[0]] = [$position, $this->history];
                $this->emit('saved', $arguments[0], 'moves', strlen($this->history));
                break;
            case 'RESTORE':
                if (!isset($this->snapshots[$arguments[0]])) {
                    throw new CommandError("no snapshot {$arguments[0]}");
                }
                [$this->current, $this->history] = $this->snapshots[$arguments[0]];
                $this->redo = '';
                $this->emit('restored', $arguments[0], 'moves', strlen($this->history));
                break;
            case 'CHECK':
                [$after, $letters, $failure] = $this->simulate(strtolower(decode($arguments[0], STEP_CHARACTERS)));
                if ($failure !== null) {
                    $this->emit('check fail', $failure);
                } else {
                    $this->emit('check ok moves', strlen($letters), 'pushes', pushCount($letters), $this->progress($after->boxes));
                }
                break;
            case 'SOLVE':
            case 'HINT':
                [$summary, $notation] = $this->searchSolution((int) $arguments[0]);
                if ($name === 'SOLVE') {
                    $this->emit($summary);
                    $this->solution = $notation === null ? null : [$notation, $position];
                    if ($notation !== null) {
                        $this->emit($notation);
                    }
                } elseif ($notation === null) {
                    $this->emit($summary);
                } else {
                    preg_match('/\A[udlr]*[UDLR]/', $notation, $match);
                    $this->takeSteps(strtolower($match[0]));
                    $this->emit('hint', $match[0]);
                }
                break;
            case 'PLAY':
                if ($this->solution === null || $this->solution[1] != $position) {
                    throw new CommandError('no solution');
                }
                $notation = $this->solution[0];
                $this->takeSteps(strtolower($notation));
                $this->emit('played pushes', pushCount($notation), 'moves', strlen($notation));
                break;
            case 'TRANSFORM':
                $kind = $arguments[0];
                $this->initial = $level->mapPosition($kind, $this->initial);
                $this->current = $level->mapPosition($kind, $position);
                $this->history = turnLetters($this->history, $kind);
                $this->redo = turnLetters($this->redo, $kind);
                $this->snapshots = array_map(
                    fn(array $snapshot): array => [$level->mapPosition($kind, $snapshot[0]), turnLetters($snapshot[1], $kind)],
                    $this->snapshots,
                );
                if ($this->solution !== null) {
                    $this->solution = [turnLetters($this->solution[0], $kind), $level->mapPosition($kind, $this->solution[1])];
                }
                $this->level = $level->transformed($kind);
                $this->emit('transformed', "{$this->level->height}x{$this->level->width}");
                break;
        }
    }

    private function bound(): void
    {
        $boxes = $this->current->boxes;
        $best = null;
        $visit = function (array $order, array $distances, int $total) use (&$visit, &$best, $boxes): void {
            $index = count($order);
            if ($index === count($boxes)) {
                if ($best === null || $total < $best[0]) {
                    $best = [$total, $order, $distances];
                }
                return;
            }
            foreach ($this->level->goalCells as $goal => $_cell) {
                if (in_array($goal, $order, true)) {
                    continue;
                }
                $distance = $this->level->distances[$goal][$boxes[$index]];
                if ($distance !== null) {
                    $visit([...$order, $goal], [...$distances, $distance], $total + $distance);
                }
            }
        };
        $visit([], [], 0);
        if ($best === null) {
            $this->emit('bound none');
            return;
        }
        [$total, $order, $distances] = $best;
        $this->emit('bound', $total);
        foreach ($boxes as $index => $box) {
            $this->emit('box', $this->level->cellText($box), 'goal', $this->level->cellText($this->level->goalCells[$order[$index]]), 'pushes', $distances[$index]);
        }
    }
}

function inputLine(): string
{
    return rtrim(fgets(STDIN), "\r\n");
}

function main(): void
{
    [$height] = array_map(intval(...), explode(' ', inputLine()));
    $rows = [];
    for ($index = 0; $index < $height; $index++) {
        $rows[] = inputLine();
    }
    $game = new Sokoban($rows);
    $count = (int) inputLine();
    for ($command = 0; $command < $count; $command++) {
        $words = explode(' ', inputLine());
        $rows = [];
        if ($words[0] === 'LOAD') {
            for ($index = 0; $index < (int) $words[1]; $index++) {
                $rows[] = inputLine();
            }
        }
        $game->execute($words, $rows);
    }
}

main();
