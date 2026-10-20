<?php
declare(strict_types=1);

final class CommandFailure extends RuntimeException {
    public readonly array $lines;
    public function __construct(string|array $reason) {
        $this->lines = is_array($reason) ? $reason : [$reason];
        parent::__construct(implode("\n", $this->lines));
    }
}
function fail(string|array $reason): never { throw new CommandFailure($reason); }
function normalized(string $line): array {
    return array_values(array_filter(explode(' ', strtolower($line)), fn(string $word): bool => $word !== '' && !in_array($word, ['the', 'a', 'an'], true)));
}

enum Direction: int {
    case North = 0; case South = 1; case East = 2; case West = 3; case Up = 4; case Down = 5;
    public function word(): string { return ['north', 'south', 'east', 'west', 'up', 'down'][$this->value]; }
    public function opposite(): self { return self::from($this->value ^ 1); }
    public static function parse(string $word): ?self {
        foreach (self::cases() as $direction) if ($word === $direction->word() || $word === $direction->word()[0]) return $direction;
        return null;
    }
}
enum Verb: string {
    case Go = 'go'; case Look = 'look'; case Examine = 'examine'; case Take = 'take'; case Drop = 'drop'; case Put = 'put';
    case Inventory = 'inventory'; case Open = 'open'; case Close = 'close'; case Unlock = 'unlock'; case Lock = 'lock';
    case Use = 'use'; case Light = 'light'; case Extinguish = 'extinguish'; case Wait = 'wait'; case Score = 'score';
    case Save = 'save'; case Restore = 'restore'; case Verbose = 'verbose'; case Brief = 'brief';
    public static function parse(string $word): ?self {
        $canonical = match ($word) {
            'go', 'walk', 'run' => 'go', 'look', 'l' => 'look', 'examine', 'x', 'inspect', 'read' => 'examine',
            'take', 'get', 'grab' => 'take', 'drop', 'discard' => 'drop', 'put', 'insert', 'place' => 'put',
            'inventory', 'inv', 'i' => 'inventory', 'open' => 'open', 'close', 'shut' => 'close', 'unlock' => 'unlock', 'lock' => 'lock',
            'use', 'apply' => 'use', 'light', 'ignite' => 'light', 'extinguish', 'douse', 'snuff' => 'extinguish', 'wait', 'z' => 'wait',
            'score' => 'score', 'save' => 'save', 'restore', 'load' => 'restore', 'verbose' => 'verbose', 'brief' => 'brief', default => null,
        };
        return $canonical === null ? null : self::from($canonical);
    }
    public function noObjects(): bool { return in_array($this, [self::Look, self::Inventory, self::Wait, self::Score, self::Save, self::Restore, self::Verbose, self::Brief], true); }
    public function action(): bool { return in_array($this, [self::Go, self::Take, self::Drop, self::Put, self::Open, self::Close, self::Unlock, self::Lock, self::Use, self::Light, self::Extinguish, self::Wait], true); }
}
enum PlaceKind { case Room; case Player; case Inside; case Nowhere; }
enum ContainerState: string { case Open = 'open'; case Closed = 'closed'; case Locked = 'locked'; }
enum EndStatus { case None; case Won; case Dead; }
final readonly class Place {
    public function __construct(public PlaceKind $kind, public string $id = '') {}
    public function key(): string { return $this->kind->name . ':' . $this->id; }
    public function equals(self $other): bool { return $this->kind === $other->kind && $this->id === $other->id; }
}
final readonly class ExitLink {
    public function __construct(public string $destination, public ?string $key, public bool $locked) {}
}
final class Room {
    public array $description = [];
    public function __construct(public string $name, public bool $dark) {}
}
final class Item {
    public string $name = '';
    public int $points = 0;
    public bool $light = false, $fixed = false;
    public ?int $capacity = null;
    public ?string $key = null;
    public array $nouns, $nameWords = [], $details = [];
    public function __construct(public string $id, public int $weight) { $this->nouns = [$id => true]; }
}
interface Effect {}
final readonly class MessageEffect implements Effect { public function __construct(public string $text) {} }
final readonly class OpenEffect implements Effect { public function __construct(public string $room, public Direction $direction, public string $destination) {} }
final readonly class MoveEffect implements Effect { public function __construct(public string $item, public Place $place) {} }
final readonly class FlagEffect implements Effect { public function __construct(public string $flag, public bool $on) {} }
final readonly class PointsEffect implements Effect { public function __construct(public int $amount) {} }
final readonly class Rule {
    public function __construct(public string $first, public string $second, public ?string $flag, public bool $whenOn, public Effect $effect) {}
}
final class GameState {
    public string $room = '';
    public array $places = [], $containers = [], $fuel = [], $lit = [], $exits = [], $flags = [], $visited = [];
    public int $bonus = 0, $moves = 0, $darkness = 0;
    public EndStatus $ended = EndStatus::None;
}
final readonly class Score {
    public function __construct(public int $stored, public int $treasures, public int $points, public int $total) {}
}

final class Adventure {
    private array $rooms = [], $items = [], $ids = [], $rules = [], $enterRules = [], $vocabulary = [];
    private GameState $state;
    private ?GameState $saved = null;
    private ?string $pronoun = null, $previous = null;
    private bool $verbose = false;
    private string $trophy = '';
    private int $maxWeight = 0;

    public function __construct(array $definitions) {
        $this->state = new GameState();
        foreach ($definitions as $line) $this->define($line);
        ksort($this->items, SORT_STRING);
        $this->ids = array_keys($this->items);
        foreach ($this->items as $item) $this->vocabulary += $item->nouns + $item->nameWords;
        $this->state->visited[$this->state->room] = true;
    }
    private function setExit(string $room, Direction $direction, string $destination, ?string $key = null): void {
        $this->state->exits[$room][$direction->value] = new ExitLink($destination, $key, $key !== null);
    }
    private function define(string $line): void {
        $words = explode(' ', $line); $kind = $words[0]; $id = $words[1];
        $text = fn(int $index): string => implode(' ', array_slice($words, $index));
        switch ($kind) {
            case 'ROOM':
                $dark = $words[2] === 'DARK';
                $this->rooms[$id] = new Room($text($dark ? 3 : 2), $dark);
                break;
            case 'DESC': $this->rooms[$id]->description[] = $text(2); break;
            case 'EXIT': $this->setExit($id, Direction::parse($words[2]), $words[3], count($words) > 4 ? $words[5] : null); break;
            case 'ITEM':
                $item = new Item($id, (int) $words[3]);
                $this->state->places[$id] = match ($words[2]) {
                    'PLAYER' => new Place(PlaceKind::Player), 'NOWHERE' => new Place(PlaceKind::Nowhere), default => new Place(PlaceKind::Room, $words[2]),
                };
                $this->state->fuel[$id] = 0; $this->state->lit[$id] = false; $this->state->containers[$id] = ContainerState::Open;
                $index = 4;
                if ($words[$index] === 'TREASURE') { $item->points = (int) $words[$index + 1]; $index += 2; }
                if ($words[$index] === 'LIGHT') { $item->light = true; $this->state->fuel[$id] = (int) $words[$index + 1]; $index += 2; }
                if ($words[$index] === 'CONTAINER') {
                    $item->capacity = (int) $words[$index + 1]; $index += 2;
                    if ($words[$index] === 'CLOSED') { $this->state->containers[$id] = ContainerState::Closed; $index++; }
                    if ($words[$index] === 'LOCKED') { $item->key = $words[$index + 1]; $this->state->containers[$id] = ContainerState::Locked; $index += 2; }
                }
                if ($words[$index] === 'FIXED') { $item->fixed = true; $index++; }
                $item->name = $text($index); $item->nameWords = array_fill_keys(array_slice($words, $index), true);
                $this->items[$id] = $item;
                break;
            case 'INSIDE': $this->state->places[$id] = new Place(PlaceKind::Inside, $words[2]); break;
            case 'ALIAS': $this->items[$id]->nouns[$words[2]] = true; break;
            case 'DETAIL': $this->items[$id]->details[] = $text(2); break;
            case 'RULE': case 'ENTER':
                $index = $kind === 'RULE' ? 3 : 2; $flag = null; $whenOn = true;
                if ($words[$index] === 'IF' || $words[$index] === 'UNLESS') {
                    $whenOn = $words[$index] === 'IF'; $flag = $words[$index + 1]; $index += 2;
                }
                $effectName = $words[$index++];
                $effect = match ($effectName) {
                    'MESSAGE' => new MessageEffect($text($index)),
                    'OPEN' => new OpenEffect($words[$index], Direction::parse($words[$index + 1]), $words[$index + 2]),
                    'REMOVE' => new MoveEffect($words[$index], new Place(PlaceKind::Nowhere)),
                    'ADD' => new MoveEffect($words[$index], new Place(PlaceKind::Room, $words[$index + 1])),
                    'SET', 'CLEAR' => new FlagEffect($words[$index], $effectName === 'SET'),
                    default => new PointsEffect((int) $words[$index]),
                };
                $rule = new Rule($id, $kind === 'RULE' ? $words[2] : '', $flag, $whenOn, $effect);
                if ($kind === 'RULE') $this->rules[] = $rule; else $this->enterRules[] = $rule;
                break;
            case 'TROPHY': $this->trophy = $id; break;
            case 'START': $this->state->room = $id; break;
            case 'MAXWEIGHT': $this->maxWeight = (int) $id; break;
        }
    }
    private function contents(Place $place): array {
        return array_values(array_filter($this->ids, fn(string $id): bool => $this->state->places[$id]->equals($place)));
    }
    private function children(): array {
        $result = [];
        foreach ($this->ids as $id) $result[$this->state->places[$id]->key()][] = $id;
        return $result;
    }
    private function isOpen(string $id): bool { return $this->items[$id]->capacity !== null && $this->state->containers[$id] === ContainerState::Open; }
    private function reachable(Place $place): array {
        $children = $this->children(); $result = [];
        $visit = function (Place $place) use ($children, &$result, &$visit): void {
            foreach ($children[$place->key()] ?? [] as $id) {
                $result[$id] = true;
                if ($this->isOpen($id)) $visit(new Place(PlaceKind::Inside, $id));
            }
        };
        $visit($place);
        return $result;
    }
    private function carried(): array { return $this->reachable(new Place(PlaceKind::Player)); }
    private function isCarried(string $id): bool { $carried = $this->carried(); return isset($carried[$id]); }
    private function roomItems(): array { return $this->reachable(new Place(PlaceKind::Room, $this->state->room)); }
    private function isLit(): bool {
        if (!$this->rooms[$this->state->room]->dark) return true;
        foreach ($this->carried() + $this->roomItems() as $id => $_) if ($this->state->lit[$id]) return true;
        return false;
    }
    private function visible(): array { return $this->isLit() ? $this->carried() + $this->roomItems() : $this->carried(); }
    private function weights(): array {
        $children = $this->children(); $result = [];
        $total = function (string $id) use ($children, &$result, &$total): int {
            if (isset($result[$id])) return $result[$id];
            $weight = $this->items[$id]->weight;
            foreach ($children[(new Place(PlaceKind::Inside, $id))->key()] ?? [] as $child) $weight += $total($child);
            return $result[$id] = $weight;
        };
        foreach ($this->ids as $id) $total($id);
        return $result;
    }
    private function totalWeight(string $id): int { return $this->weights()[$id]; }
    private function contentWeight(string $id): int { return $this->totalWeight($id) - $this->items[$id]->weight; }
    private function carriedWeight(): int {
        $weights = $this->weights(); $result = 0;
        foreach ($this->contents(new Place(PlaceKind::Player)) as $id) $result += $weights[$id];
        return $result;
    }
    private function nestedIn(string $id, string $ancestor): bool {
        for ($place = $this->state->places[$id]; $place->kind === PlaceKind::Inside; $place = $this->state->places[$place->id]) if ($place->id === $ancestor) return true;
        return false;
    }
    private function score(): Score {
        $stored = 0; $treasures = 0; $points = 0;
        foreach ($this->items as $id => $item) if ($item->points > 0) {
            $treasures++;
            $place = $this->state->places[$id];
            while ($place->kind === PlaceKind::Inside) $place = $this->state->places[$place->id];
            if ($place->kind === PlaceKind::Room && $place->id === $this->trophy) { $stored++; $points += $item->points; }
        }
        return new Score($stored, $treasures, $points, $points + $this->state->bonus);
    }
    private function display(string $id): string {
        $item = $this->items[$id]; $annotations = [];
        if ($item->capacity !== null) $annotations[] = $this->state->containers[$id]->value;
        if ($item->light && $this->state->lit[$id]) $annotations[] = 'lit';
        return $item->name . ($annotations === [] ? '' : ' (' . implode(', ', $annotations) . ')');
    }
    private function tree(Place $place): array {
        $children = $this->children(); $lines = [];
        $visit = function (Place $place, int $depth) use ($children, &$lines, &$visit): void {
            foreach ($children[$place->key()] ?? [] as $id) {
                $lines[] = str_repeat('  ', $depth) . $this->display($id);
                if ($this->isOpen($id)) $visit(new Place(PlaceKind::Inside, $id), $depth + 1);
            }
        };
        $visit($place, 1);
        return $lines;
    }
    public function describe(bool $full = true): array {
        if (!$this->isLit()) return ['It is pitch dark.'];
        $room = $this->rooms[$this->state->room]; $lines = [$room->name];
        if ($full) array_push($lines, ...$room->description);
        $exits = [];
        foreach (Direction::cases() as $direction) {
            $exit = $this->state->exits[$this->state->room][$direction->value] ?? null;
            if ($exit !== null) $exits[] = $direction->word() . ($exit->locked ? ' (locked)' : '');
        }
        $lines[] = 'Exits: ' . ($exits === [] ? 'none' : implode(', ', $exits));
        $floor = new Place(PlaceKind::Room, $this->state->room);
        if ($this->contents($floor) !== []) array_push($lines, 'You see:', ...$this->tree($floor));
        return $lines;
    }
    private function resolve(array $phrase): string {
        $visible = $this->visible();
        if ($phrase === ['it']) {
            if ($this->pronoun === null) fail('I don\'t know what "it" refers to.');
            if (!isset($visible[$this->pronoun])) fail("You can't see any such thing.");
            return $this->pronoun;
        }
        foreach ($phrase as $word) if (!isset($this->vocabulary[$word])) fail('I don\'t know the word "' . $word . '".');
        $matches = []; $last = $phrase[count($phrase) - 1];
        foreach ($this->items as $id => $item) {
            if (!isset($visible[$id]) || !isset($item->nouns[$last])) continue;
            foreach (array_slice($phrase, 0, -1) as $word) if (!isset($item->nameWords[$word])) continue 2;
            $matches[] = $id;
        }
        if ($matches === []) fail("You can't see any such thing.");
        if (count($matches) > 1) fail('Which do you mean: ' . implode(', ', array_map(fn(string $id): string => $this->items[$id]->name, $matches)) . '?');
        return $this->pronoun = $matches[0];
    }
    private function runRules(array $rules, string $first, string $second = ''): array {
        $lines = []; $executed = 0;
        foreach ($rules as $rule) {
            if ($rule->first !== $first || $rule->second !== $second || ($rule->flag !== null && isset($this->state->flags[$rule->flag]) !== $rule->whenOn)) continue;
            $executed++; $effect = $rule->effect;
            if ($effect instanceof MessageEffect) $lines[] = $effect->text;
            elseif ($effect instanceof OpenEffect) $this->setExit($effect->room, $effect->direction, $effect->destination);
            elseif ($effect instanceof MoveEffect) $this->state->places[$effect->item] = $effect->place;
            elseif ($effect instanceof FlagEffect) {
                if ($effect->on) $this->state->flags[$effect->flag] = true; else unset($this->state->flags[$effect->flag]);
            } elseif ($effect instanceof PointsEffect) $this->state->bonus += $effect->amount;
        }
        return [$lines, $executed];
    }
    private function requireContainer(string $id): void {
        $name = $this->items[$id]->name;
        if ($this->items[$id]->capacity === null) fail("The $name is not a container.");
        if (!$this->isOpen($id)) fail("The $name is closed.");
    }
    private function take(array $first, ?array $second): array {
        if (!$this->isLit()) fail('It is pitch dark.');
        $container = null; $source = new Place(PlaceKind::Room, $this->state->room);
        if ($second !== null) {
            $container = $this->resolve($second); $this->requireContainer($container);
            $source = new Place(PlaceKind::Inside, $container);
        }
        if ($first === ['all']) {
            $candidates = array_values(array_filter($this->contents($source), fn(string $id): bool => !$this->items[$id]->fixed));
            if ($candidates === []) fail($container === null ? 'There is nothing here to take.' : 'There is nothing in the ' . $this->items[$container]->name . ' to take.');
            $lines = []; $taken = false;
            foreach ($candidates as $id) {
                $outcome = "You can't carry any more.";
                if ($this->isCarried($id) || $this->carriedWeight() + $this->totalWeight($id) <= $this->maxWeight) {
                    $this->state->places[$id] = new Place(PlaceKind::Player); $outcome = 'Taken.'; $taken = true;
                }
                $lines[] = $this->items[$id]->name . ': ' . $outcome;
            }
            if (!$taken) fail($lines);
            return $lines;
        }
        $id = $this->resolve($first); $name = $this->items[$id]->name;
        if ($container !== null && !$this->state->places[$id]->equals($source)) fail("The $name is not in the " . $this->items[$container]->name . '.');
        if ($this->state->places[$id]->kind === PlaceKind::Player) fail("You already have the $name.");
        if ($this->items[$id]->fixed) fail("The $name is fixed in place.");
        if (!$this->isCarried($id) && $this->carriedWeight() + $this->totalWeight($id) > $this->maxWeight) fail("You can't carry any more.");
        $this->state->places[$id] = new Place(PlaceKind::Player);
        return ['Taken.'];
    }
    private function drop(array $phrase): array {
        if ($phrase === ['all']) {
            $candidates = $this->contents(new Place(PlaceKind::Player));
            if ($candidates === []) fail('You are empty-handed.');
            $lines = [];
            foreach ($candidates as $id) { $this->state->places[$id] = new Place(PlaceKind::Room, $this->state->room); $lines[] = $this->items[$id]->name . ': Dropped.'; }
            return $lines;
        }
        $id = $this->resolve($phrase);
        if (!$this->isCarried($id)) fail("You aren't carrying the " . $this->items[$id]->name . '.');
        $this->state->places[$id] = new Place(PlaceKind::Room, $this->state->room);
        return ['Dropped.'];
    }
    private function putItem(string $id, string $container): ?string {
        $name = $this->items[$id]->name; $target = $this->items[$container];
        if ($this->nestedIn($container, $id)) return "The {$target->name} is inside the $name.";
        if ($this->state->places[$id]->equals(new Place(PlaceKind::Inside, $container))) return "The $name is already in the {$target->name}.";
        $weight = $this->contentWeight($container) + ($this->nestedIn($id, $container) ? 0 : $this->totalWeight($id));
        if ($weight > $target->capacity) return "The $name doesn't fit in the {$target->name}.";
        $this->state->places[$id] = new Place(PlaceKind::Inside, $container);
        return null;
    }
    private function put(array $first, array $second): array {
        if ($first === ['all']) {
            $target = $this->resolve($second); $this->requireContainer($target);
            $candidates = array_values(array_filter($this->contents(new Place(PlaceKind::Player)), fn(string $id): bool => $id !== $target));
            if ($candidates === []) fail('You have nothing to put in the ' . $this->items[$target]->name . '.');
            $lines = []; $succeeded = false;
            foreach ($candidates as $id) {
                $reason = $this->putItem($id, $target);
                if ($reason === null) $succeeded = true;
                $lines[] = $this->items[$id]->name . ': ' . ($reason ?? 'Done.');
            }
            if (!$succeeded) fail($lines);
            return $lines;
        }
        $id = $this->resolve($first); $target = $this->resolve($second); $name = $this->items[$id]->name;
        if (!$this->isCarried($id)) fail("You aren't carrying the $name.");
        if ($id === $target) fail("You can't put the $name inside itself.");
        $this->requireContainer($target);
        $reason = $this->putItem($id, $target);
        if ($reason !== null) fail($reason);
        return ["You put the $name in the " . $this->items[$target]->name . '.'];
    }
    private function keyCheck(string $key, ?array $phrase): array {
        if ($phrase !== null) {
            $id = $this->resolve($phrase); $name = $this->items[$id]->name;
            if (!$this->isCarried($id)) fail("You aren't carrying the $name.");
            if ($id !== $key) fail("The $name doesn't fit.");
            return [];
        }
        if (!$this->isCarried($key)) fail("You don't have the right key.");
        return ['(with the ' . $this->items[$key]->name . ')'];
    }
    private function lockObject(array $first, ?array $second, bool $locking): array {
        $direction = count($first) === 1 ? Direction::parse($first[0]) : null;
        if ($direction !== null) {
            $room = $this->state->room; $name = $direction->word();
            $exit = $this->state->exits[$room][$direction->value] ?? null;
            if ($exit === null) fail("There is no exit $name.");
            if ($exit->key === null) fail("The way $name has no lock.");
            if ($exit->locked === $locking) fail("The way $name is " . ($locking ? 'already locked.' : 'not locked.'));
            $lines = $this->keyCheck($exit->key, $second);
            $this->state->exits[$room][$direction->value] = new ExitLink($exit->destination, $exit->key, $locking);
            $opposite = $direction->opposite(); $back = $this->state->exits[$exit->destination][$opposite->value] ?? null;
            if ($back !== null && $back->destination === $room && $back->key === $exit->key) {
                $this->state->exits[$exit->destination][$opposite->value] = new ExitLink($back->destination, $back->key, $locking);
            }
        } else {
            $id = $this->resolve($first); $item = $this->items[$id]; $value = $this->state->containers[$id];
            if ($item->capacity === null || $item->key === null) fail("The {$item->name} has no lock.");
            if (($value === ContainerState::Locked) === $locking) fail("The {$item->name} is " . ($locking ? 'already locked.' : 'not locked.'));
            if ($locking && $value === ContainerState::Open) fail("You must close the {$item->name} first.");
            $lines = $this->keyCheck($item->key, $second);
            $this->state->containers[$id] = $locking ? ContainerState::Locked : ContainerState::Closed;
        }
        $lines[] = $locking ? 'Locked.' : 'Unlocked.';
        return $lines;
    }
    private function execute(Verb $verb, array $first, ?array $second): array {
        switch ($verb) {
            case Verb::Look: return $this->describe();
            case Verb::Inventory:
                $player = new Place(PlaceKind::Player);
                if ($this->contents($player) === []) return ['You are empty-handed.'];
                return array_merge(['You are carrying:'], $this->tree($player), ['Total weight: ' . $this->carriedWeight() . '/' . $this->maxWeight]);
            case Verb::Wait: return ['Time passes.'];
            case Verb::Score:
                $score = $this->score();
                return ["You have scored {$score->total} points (treasure {$score->points}, bonus {$this->state->bonus}) in {$this->state->moves} moves.", "Treasures stored: {$score->stored} of {$score->treasures}."];
            case Verb::Save: $this->saved = clone $this->state; return ['Game saved.'];
            case Verb::Restore:
                if ($this->saved === null) fail('There is no saved game.');
                $this->state = clone $this->saved;
                return array_merge(['Game restored.'], $this->describe());
            case Verb::Verbose: $this->verbose = true; return ['Verbose mode.'];
            case Verb::Brief: $this->verbose = false; return ['Brief mode.'];
            case Verb::Take: return $this->take($first, $second);
            case Verb::Drop: return $this->drop($first);
            case Verb::Put: return $this->put($first, $second);
            case Verb::Unlock: case Verb::Lock: return $this->lockObject($first, $second, $verb === Verb::Lock);
            case Verb::Use:
                $id = $this->resolve($first); $target = $this->resolve($second);
                if (!$this->isCarried($id)) fail("You aren't carrying the " . $this->items[$id]->name . '.');
                [$lines, $executed] = $this->runRules($this->rules, $id, $target);
                if ($executed === 0) fail('Nothing happens.');
                return $lines === [] ? ['Done.'] : $lines;
            default: break;
        }
        $id = $this->resolve($first); $item = $this->items[$id]; $value = $this->state->containers[$id];
        switch ($verb) {
            case Verb::Examine:
                $lines = $item->details === [] ? ["You see nothing special about the {$item->name}."] : $item->details;
                if ($item->light) $lines[] = 'It is ' . ($this->state->lit[$id] ? 'lit' : 'unlit') . ' (fuel ' . $this->state->fuel[$id] . ').';
                if ($item->capacity !== null) {
                    if ($value !== ContainerState::Open) $lines[] = "It is {$value->value}.";
                    elseif ($this->contents(new Place(PlaceKind::Inside, $id)) === []) $lines[] = 'It is empty.';
                    else array_push($lines, 'It contains:', ...$this->tree(new Place(PlaceKind::Inside, $id)));
                }
                if ($item->points > 0) $lines[] = "It is a treasure worth {$item->points} points.";
                $lines[] = 'It weighs ' . $this->totalWeight($id) . '.';
                return $lines;
            case Verb::Open:
                if ($item->capacity === null) fail("You can't open the {$item->name}.");
                if ($value === ContainerState::Open) fail("The {$item->name} is already open.");
                if ($value === ContainerState::Locked) fail("The {$item->name} is locked.");
                $this->state->containers[$id] = ContainerState::Open;
                $names = array_map(fn(string $child): string => $this->items[$child]->name, $this->contents(new Place(PlaceKind::Inside, $id)));
                return $names === [] ? ['Opened.'] : ["Opening the {$item->name} reveals " . implode(', ', $names) . '.'];
            case Verb::Close:
                if ($item->capacity === null) fail("You can't close the {$item->name}.");
                if ($value !== ContainerState::Open) fail("The {$item->name} is already closed.");
                $this->state->containers[$id] = ContainerState::Closed;
                return ['Closed.'];
            case Verb::Light:
                if (!$item->light) fail("You can't light the {$item->name}.");
                if ($this->state->lit[$id]) fail("The {$item->name} is already lit.");
                if ($this->state->fuel[$id] === 0) fail("The {$item->name} has no fuel.");
                $this->state->lit[$id] = true;
                return ["The {$item->name} is now lit."];
            case Verb::Extinguish:
                if (!$item->light) fail("You can't extinguish the {$item->name}.");
                if (!$this->state->lit[$id]) fail("The {$item->name} is not lit.");
                $this->state->lit[$id] = false;
                return ["The {$item->name} is now out."];
            default: return [];
        }
    }
    private function endTurn(bool $baseline): array {
        $this->state->moves++; $nearby = $this->carried() + $this->roomItems(); $lines = [];
        foreach ($this->ids as $id) if ($this->state->lit[$id]) {
            $this->state->fuel[$id]--;
            if ($this->state->fuel[$id] === 0) {
                $this->state->lit[$id] = false;
                if (isset($nearby[$id])) $lines[] = 'The ' . $this->items[$id]->name . ' goes out.';
            }
        }
        $lit = $this->isLit();
        if ($baseline && !$lit) $lines[] = 'It is now pitch dark.';
        elseif (!$baseline && $lit) array_push($lines, ...$this->describe());
        $this->state->darkness = $lit ? 0 : $this->state->darkness + 1;
        if ($this->state->darkness === 2) $lines[] = 'You hear something moving in the dark.';
        if ($this->state->darkness === 3) $this->state->ended = EndStatus::Dead;
        $score = $this->score();
        if ($this->state->ended === EndStatus::None && $score->treasures > 0 && $score->stored === $score->treasures) $this->state->ended = EndStatus::Won;
        if ($this->state->ended !== EndStatus::None) {
            $lines[] = $this->state->ended === EndStatus::Dead ? '*** You have died ***' : '*** You have won ***';
            $lines[] = "You scored {$score->total} points in {$this->state->moves} moves.";
        }
        return $lines;
    }
    private function interpret(string $line): array {
        $words = normalized($line);
        if ($words === []) fail('I beg your pardon?');
        if (Direction::parse($words[0]) !== null) array_unshift($words, 'go');
        $verb = Verb::parse($words[0]);
        if ($verb === null) fail('I don\'t know the verb "' . $words[0] . '".');
        if ($this->state->ended !== EndStatus::None && $verb !== Verb::Restore) fail('The game is over.');
        $rest = array_slice($words, 1);
        if ($verb === Verb::Look && $rest !== []) {
            if ($rest[0] !== 'at') fail("I don't understand that.");
            $verb = Verb::Examine; $rest = array_slice($rest, 1);
        }
        $first = $rest; $second = null;
        if ($verb->noObjects()) {
            if ($rest !== []) fail("I don't understand that.");
        } else {
            if ($rest === []) fail($verb === Verb::Go ? 'Which way do you want to go?' : 'What do you want to ' . $verb->value . '?');
            if ($verb === Verb::Go) {
                if (count($rest) !== 1 || Direction::parse($rest[0]) === null) fail("I don't understand that.");
            } else {
                $prepositions = [];
                if ($verb === Verb::Put) $prepositions = ['in', 'into'];
                elseif ($verb === Verb::Use) $prepositions = ['on', 'with'];
                elseif (($verb === Verb::Unlock || $verb === Verb::Lock) && in_array('with', $rest, true)) $prepositions = ['with'];
                elseif ($verb === Verb::Take && in_array('from', $rest, true)) $prepositions = ['from'];
                if ($prepositions !== []) {
                    $index = 0;
                    while ($index < count($rest) && !in_array($rest[$index], $prepositions, true)) $index++;
                    if ($index === 0 || $index + 1 >= count($rest)) fail("I don't understand that.");
                    $first = array_slice($rest, 0, $index); $second = array_slice($rest, $index + 1);
                }
            }
        }
        $baseline = $this->isLit();
        if ($verb === Verb::Go) {
            $direction = Direction::parse($rest[0]); $exit = $this->state->exits[$this->state->room][$direction->value] ?? null;
            if ($exit === null) fail("You can't go that way.");
            if ($exit->locked) fail('The way ' . $direction->word() . ' is locked.');
            $this->state->room = $exit->destination; $baseline = $this->isLit();
            $lines = $this->describe($this->verbose || !isset($this->state->visited[$this->state->room]));
            $this->state->visited[$this->state->room] = true;
            [$extra] = $this->runRules($this->enterRules, $this->state->room);
            array_push($lines, ...$extra);
        } else $lines = $this->execute($verb, $first, $second);
        if ($verb->action()) array_push($lines, ...$this->endTurn($baseline));
        return $lines;
    }
    public function command(string $line): array {
        try {
            $words = normalized($line);
            if ($words !== [] && ($words[0] === 'again' || $words[0] === 'g')) {
                if (count($words) !== 1) fail("I don't understand that.");
                if ($this->previous === null) fail('There is nothing to repeat.');
                return $this->interpret($this->previous);
            }
            $this->previous = $line;
            return $this->interpret($line);
        } catch (CommandFailure $failure) { return $failure->lines; }
    }
    public function finalScore(): string { return 'Final score: ' . $this->score()->total . ' points in ' . $this->state->moves . ' moves.'; }
}

$definitions = [];
while (($line = fgets(STDIN)) !== false) {
    $line = rtrim($line, "\r\n");
    if ($line === 'BEGIN') break;
    $definitions[] = $line;
}
$adventure = new Adventure($definitions);
foreach ($adventure->describe() as $line) echo $line, "\n";
while (($line = fgets(STDIN)) !== false) {
    $line = rtrim($line, "\r\n");
    if ($line === 'QUIT') { echo $adventure->finalScore(), "\n"; break; }
    echo '> ', $line, "\n";
    foreach ($adventure->command($line) as $output) echo $output, "\n";
}
