<?php
declare(strict_types=1);

namespace Roguelike;

require_once __DIR__ . '/minstd.php';
require_once __DIR__ . '/combat.php';
require_once __DIR__ . '/entities.php';
require_once __DIR__ . '/dungeon_gen.php';
require_once __DIR__ . '/fov.php';

const COMMAND_CLASSES = ['quaff' => 'potion', 'read' => 'scroll', 'wield' => 'weapon', 'wear' => 'armor', 'eat' => 'food'];
const HUNGER_MESSAGES = ['hungry' => 'You are getting hungry.', 'weak' => 'You feel weak from hunger.', 'starving' => 'You are starving.'];
const USAGE_FIELDS = ['picked', 'quaffed', 'read', 'eaten', 'wielded', 'worn'];

function readRows(string $name): array
{
    return array_map(static fn(string $line): array => explode(' ', $line), file('input/' . $name, FILE_IGNORE_NEW_LINES));
}

function dec1(int $a, int $b): string
{
    if ($b === 0) {
        return '-';
    }
    $z = intdiv(20 * $a + $b, 2 * $b);
    return intdiv($z, 10) . '.' . ($z % 10);
}

function exploration(Level $level): array
{
    $explored = $total = 0;
    for ($y = 0; $y < $level->height; $y++) {
        for ($x = 0; $x < $level->width; $x++) {
            if ($level->terrain[$y][$x] !== ' ') {
                $total++;
                $explored += (int)($level->memory[$y][$x] !== ' ');
            }
        }
    }
    return [$explored, $total];
}

function removeObject(array &$values, object $object): void
{
    foreach ($values as $index => $value) {
        if ($value === $object) {
            array_splice($values, $index, 1);
            return;
        }
    }
}

final class Config
{
    public int $generationSeed;
    public int $gameSeed;
    public int $width;
    public int $height;
    public int $minSize;
    public int $maxSplit;
    public int $roomMin;
    public int $roomMax;
    public int $levels;
    public int $monsterBase;
    public int $monsterStep;
    public int $itemBase;
    public int $itemStep;
    public int $sleepChance;
    public int $wakeChance;
    public int $fovRadius;
    public int $maxHp;
    public int $regenInterval;
    public Dice $hitDie;
    public int $foodStart;
    public int $foodMax;
    public int $foodHungry;
    public int $foodWeak;
    public int $packLimit;
    public array $startItems;
    public array $xpLevels;
    public array $checkpoints;

    public function __construct(array $rows)
    {
        $values = [];
        foreach ($rows as $row) {
            $values[$row[0]] = array_slice($row, 1);
        }
        [$this->generationSeed, $this->gameSeed] = array_map('intval', $values['seed']);
        [$this->width, $this->height] = array_map('intval', $values['map']);
        [$this->minSize, $this->maxSplit] = array_map('intval', $values['bsp']);
        [$this->roomMin, $this->roomMax] = array_map('intval', $values['room']);
        $this->levels = (int)$values['levels'][0];
        [$this->monsterBase, $this->monsterStep] = array_map('intval', $values['monsters']);
        [$this->itemBase, $this->itemStep] = array_map('intval', $values['items']);
        [$this->sleepChance, $this->wakeChance] = array_map('intval', $values['sleep']);
        $this->fovRadius = (int)$values['fov'][0];
        [$this->maxHp, $this->regenInterval] = array_map('intval', $values['player']);
        $this->hitDie = parseDice($values['hitdie'][0]);
        [$this->foodStart, $this->foodMax, $this->foodHungry, $this->foodWeak] = array_map('intval', $values['food']);
        $this->packLimit = (int)$values['pack'][0];
        $this->startItems = $values['start'];
        $this->xpLevels = array_map('intval', $values['xp']);
        $this->checkpoints = array_fill_keys(array_map('intval', $values['checkpoints']), true);
    }
}

function expandCommands(array $rows): array
{
    $commands = [];
    foreach ($rows as $tokens) {
        $name = $tokens[0];
        if ($name === 'wait') {
            $argument = null;
            $count = isset($tokens[1]) ? (int)$tokens[1] : 1;
        } else {
            $argument = $tokens[1] ?? null;
            $count = isset($tokens[2]) ? (int)$tokens[2] : 1;
        }
        for ($index = 0; $index < $count; $index++) {
            $commands[] = [$name, $argument];
        }
    }
    return $commands;
}

final class Player
{
    public int $depth = 1;
    public int $hp;
    public int $maxHp;
    public int $level = 1;
    public int $xp = 0;
    public int $gold = 0;
    public int $satiation;
    public int $poison = 0;
    public array $pack = [];
    public ?Item $weapon = null;
    public ?Item $armor = null;

    public function __construct(Config $config, public int $x, public int $y)
    {
        $this->hp = $this->maxHp = $config->maxHp;
        $this->satiation = $config->foodStart;
    }

    public function defense(): int
    {
        return 10 + ($this->armor === null ? 0 : $this->armor->kind->armor + $this->armor->bonus);
    }
}

final class AttackStats
{
    public int $count = 0;
    public int $hits = 0;
    public int $criticals = 0;
    public int $damage = 0;

    public function record(string $outcome, int $damage): void
    {
        $this->count++;
        if ($outcome !== 'miss') {
            $this->hits++;
            $this->damage += $damage;
        }
        $this->criticals += (int)($outcome === 'critical');
    }

    public function line(string $label): string
    {
        return "{$label} {$this->count} hits {$this->hits} criticals {$this->criticals} damage {$this->damage} accuracy " . dec1(100 * $this->hits, $this->count);
    }
}

final class Game
{
    private Minstd $generationRng;
    private Minstd $rng;
    private array $levels = [];
    private Player $player;
    private int $turn = 1;
    public array $messages = [];
    public array $mapLines = [];
    private array $visible;
    private array $distance;
    private ?string $result = null;
    private ?string $cause = null;
    private int $succeeded = 0;
    private int $failed = 0;
    private int $unused = 0;
    private int $moves = 0;
    private AttackStats $playerAttacks;
    private AttackStats $monsterAttacks;
    private int $poisonDamage = 0;
    private int $starvationDamage = 0;
    private array $usage;
    private array $kills = [];

    public function __construct(private Config $config, private array $monsterTypes, private array $itemTypes, private array $commands)
    {
        $this->generationRng = new Minstd($config->generationSeed);
        $this->rng = new Minstd($config->gameSeed);
        $this->playerAttacks = new AttackStats();
        $this->monsterAttacks = new AttackStats();
        $this->usage = array_fill_keys(USAGE_FIELDS, 0);
        foreach ($monsterTypes as $kind) {
            $this->kills[$kind->name] = 0;
        }
        $generator = new LevelGenerator($this->generationRng, $config->minSize, $config->maxSplit, $config->roomMin, $config->roomMax);
        for ($depth = 1; $depth <= $config->levels; $depth++) {
            $level = $generator->generate($depth, $config->width, $config->height);
            [$x, $y] = $level->target;
            if ($depth < $config->levels) {
                $level->terrain[$y][$x] = '>';
            } else {
                $level->items[] = new Item(new ItemType('amulet', 'amulet', 0, 0, 0), $x, $y);
            }
            $this->placeMonsters($level);
            $this->placeItems($level);
            $this->levels[] = $level;
        }
        [$x, $y] = $this->levels[0]->arrival;
        $this->player = new Player($config, $x, $y);
        $typesByName = [];
        foreach ($itemTypes as $kind) {
            $typesByName[$kind->name] = $kind;
        }
        foreach ($config->startItems as $name) {
            $item = new Item($typesByName[$name], $x, $y);
            $this->player->pack[] = $item;
            if ($item->kind->category === 'weapon' && $this->player->weapon === null) {
                $this->player->weapon = $item;
            }
            if ($item->kind->category === 'armor' && $this->player->armor === null) {
                $this->player->armor = $item;
            }
        }
    }

    private function placeMonsters(Level $level): void
    {
        $count = $this->config->monsterBase + $this->config->monsterStep * ($level->depth - 1);
        $candidates = $weights = [];
        foreach ($this->monsterTypes as $kind) {
            if ($kind->minDepth <= $level->depth && $level->depth <= $kind->maxDepth) {
                $candidates[] = $kind;
                $weights[] = $kind->weight;
            }
        }
        for ($number = 1; $number <= $count; $number++) {
            $kind = $candidates[$this->generationRng->select($weights)];
            do {
                [$room, $x, $y] = $level->drawRoomCell($this->generationRng);
            } while ($room === $level->arrivalRoom || $level->terrain[$y][$x] !== '.' || $level->monsterAt($x, $y) !== null);
            $hp = $kind->hp->roll($this->generationRng);
            $asleep = $this->generationRng->draw() % 100 < $this->config->sleepChance;
            $level->monsters[] = new Monster($number, $kind, $x, $y, $hp, $asleep);
        }
        $level->monstersCreated = $count;
    }

    private function placeItems(Level $level): void
    {
        $count = $this->config->itemBase + $this->config->itemStep * ($level->depth - 1);
        $candidates = $weights = [];
        foreach ($this->itemTypes as $kind) {
            if ($kind->minDepth <= $level->depth && $level->depth <= $kind->maxDepth) {
                $candidates[] = $kind;
                $weights[] = $kind->weight;
            }
        }
        for ($index = 0; $index < $count; $index++) {
            $kind = $candidates[$this->generationRng->select($weights)];
            do {
                [$room, $x, $y] = $level->drawRoomCell($this->generationRng);
            } while ($level->terrain[$y][$x] !== '.' || $level->itemAt($x, $y) !== null);
            $amount = $kind->category === 'gold' ? $kind->dice->roll($this->generationRng) : 0;
            $level->items[] = new Item($kind, $x, $y, $amount);
        }
        $level->itemsPlaced = count($level->items);
    }

    private function currentLevel(): Level { return $this->levels[$this->player->depth - 1]; }
    private function say(string $text): void { $this->messages[] = sprintf('%04d %s', $this->turn, $text); }

    private function hungerState(): string
    {
        $food = $this->player->satiation;
        if ($food > $this->config->foodHungry) {
            return 'normal';
        }
        if ($food > $this->config->foodWeak) {
            return 'hungry';
        }
        return $food > 0 ? 'weak' : 'starving';
    }

    private function finish(string $result, string $cause): void { $this->result = $result; $this->cause = $cause; }
    private function die(string $cause): void { $this->say('You die.'); $this->finish('died', $cause); }

    private function updateView(): void
    {
        $level = $this->currentLevel();
        $player = $this->player;
        $this->visible = fieldOfView($level, $player->x, $player->y, $this->config->fovRadius);
        for ($y = 0; $y < $level->height; $y++) {
            for ($x = 0; $x < $level->width; $x++) {
                if ($this->visible[$y][$x]) {
                    $item = $level->itemAt($x, $y);
                    $level->memory[$y][$x] = $item === null ? $level->terrain[$y][$x] : $item->symbol();
                }
            }
        }
        foreach ($level->monsters as $monster) {
            $seen = $this->visible[$monster->y][$monster->x];
            if ($seen && !$monster->wasVisible) {
                $this->say('You see the ' . $monster->kind->name . '.');
            }
            $monster->wasVisible = $seen;
        }
    }

    public function run(): void
    {
        $this->updateView();
        foreach ($this->commands as $command) {
            if ($this->result !== null) {
                $this->unused++;
            } elseif (!$this->execute($command)) {
                $this->failed++;
            } else {
                $this->succeeded++;
                if ($this->result === null) {
                    $this->advanceTurn();
                }
            }
        }
        if ($this->result === null) {
            $this->finish('alive', 'commands_exhausted');
        }
    }

    private function advanceTurn(): void
    {
        $this->updateView();
        $this->monstersAct();
        if ($this->result !== null) {
            return;
        }
        $this->endTurn();
        if ($this->result !== null) {
            return;
        }
        if (isset($this->config->checkpoints[$this->turn])) {
            $this->writeCheckpoint();
        }
        $this->turn++;
    }

    private function execute(array $command): bool
    {
        [$name, $argument] = $command;
        if ($name === 'move') {
            [$dx, $dy] = DIRECTIONS[array_search($argument, DIRECTION_NAMES, true)];
            return $this->move($dx, $dy);
        }
        return match ($name) {
            'wait' => true,
            'pickup' => $this->pickup(),
            'descend' => $this->descend(),
            default => $this->useItem($name, (int)$argument),
        };
    }

    private function move(int $dx, int $dy): bool
    {
        $level = $this->currentLevel();
        $player = $this->player;
        $x = $player->x + $dx;
        $y = $player->y + $dy;
        if (!passable($level, $x, $y)) {
            $this->say('You bump into a wall.');
            return false;
        }
        if (!canMove($level, $player->x, $player->y, $dx, $dy)) {
            $this->say('You cannot move diagonally through a door.');
            return false;
        }
        $monster = $level->monsterAt($x, $y);
        if ($monster !== null) {
            $this->playerAttack($level, $monster);
            return true;
        }
        $player->x = $x;
        $player->y = $y;
        $this->moves++;
        $item = $level->itemAt($x, $y);
        if ($item !== null) {
            $this->say('You see ' . $item->referenceName() . ' here.');
        } elseif ($level->terrain[$y][$x] === '>') {
            $this->say('There is a staircase down here.');
        }
        return true;
    }

    private function pickup(): bool
    {
        $level = $this->currentLevel();
        $player = $this->player;
        $item = $level->itemAt($player->x, $player->y);
        if ($item === null) {
            $this->say('There is nothing here.');
            return false;
        }
        if ($item->kind->category === 'gold') {
            $player->gold += $item->amount;
            $this->say('You pick up ' . $item->displayName() . '.');
        } elseif ($item->kind->category === 'amulet') {
            $this->say('You pick up the amulet.');
            $this->say('You win!');
            $this->finish('won', 'amulet');
        } elseif (count($player->pack) >= $this->config->packLimit) {
            $this->say('Your pack is full.');
            return false;
        } else {
            $player->pack[] = $item;
            $this->say('You pick up the ' . $item->displayName() . ' (' . count($player->pack) . ').');
        }
        removeObject($level->items, $item);
        $level->picked++;
        $this->usage['picked']++;
        return true;
    }

    private function descend(): bool
    {
        $player = $this->player;
        if ($this->currentLevel()->terrain[$player->y][$player->x] !== '>') {
            $this->say('There are no stairs here.');
            return false;
        }
        $player->depth++;
        [$player->x, $player->y] = $this->currentLevel()->arrival;
        $this->say('You descend to depth ' . $player->depth . '.');
        return true;
    }

    private function useItem(string $name, int $number): bool
    {
        $player = $this->player;
        if ($number > count($player->pack)) {
            $this->say('You do not have that item.');
            return false;
        }
        $item = $player->pack[$number - 1];
        if ($item->kind->category !== COMMAND_CLASSES[$name]) {
            $this->say('You cannot ' . $name . ' that.');
            return false;
        }
        if ($name === 'quaff') {
            return $this->quaff($item);
        }
        if ($name === 'read') {
            return $this->read($item);
        }
        if ($name === 'wield') {
            if ($item === $player->weapon) {
                $this->say('You are already wielding that.');
                return false;
            }
            $player->weapon = $item;
            $this->usage['wielded']++;
            $this->say('You are now wielding the ' . $item->displayName() . '.');
        } elseif ($name === 'wear') {
            if ($item === $player->armor) {
                $this->say('You are already wearing that.');
                return false;
            }
            $player->armor = $item;
            $this->usage['worn']++;
            $this->say('You are now wearing the ' . $item->displayName() . '.');
        } else {
            removeObject($player->pack, $item);
            $this->usage['eaten']++;
            $player->satiation = min($player->satiation + $item->kind->nutrition, $this->config->foodMax);
            $this->say('You eat the ' . $item->displayName() . '.');
        }
        return true;
    }

    private function quaff(Item $item): bool
    {
        $player = $this->player;
        removeObject($player->pack, $item);
        $this->usage['quaffed']++;
        $this->say('You quaff the ' . $item->displayName() . '.');
        if ($item->kind->effect === 'heal') {
            $player->hp += $item->kind->dice->roll($this->rng);
            if ($player->hp > $player->maxHp) {
                $player->maxHp++;
                $player->hp = $player->maxHp;
            }
            $player->poison = 0;
            $this->say('You feel better.');
        } elseif ($item->kind->effect === 'poison') {
            $player->poison += $item->kind->poisonTurns;
            $this->say('You feel very sick.');
        } elseif ($item->kind->effect === 'level') {
            $this->say('You feel more experienced.');
            if ($player->level <= count($this->config->xpLevels)) {
                $this->gainXp($this->config->xpLevels[$player->level - 1] - $player->xp);
            }
        }
        return true;
    }

    private function read(Item $item): bool
    {
        $level = $this->currentLevel();
        $player = $this->player;
        removeObject($player->pack, $item);
        $this->usage['read']++;
        $this->say('You read the ' . $item->displayName() . '.');
        if ($item->kind->effect === 'mapping') {
            for ($y = 0; $y < $level->height; $y++) {
                for ($x = 0; $x < $level->width; $x++) {
                    if ($level->terrain[$y][$x] !== ' ' && $level->memory[$y][$x] === ' ') {
                        $level->memory[$y][$x] = $level->terrain[$y][$x];
                    }
                }
            }
            $this->say('A map forms in your mind.');
        } elseif ($item->kind->effect === 'teleport') {
            do {
                [$room, $x, $y] = $level->drawRoomCell($this->rng);
            } while ($x === $player->x && $y === $player->y || $level->monsterAt($x, $y) !== null);
            $player->x = $x;
            $player->y = $y;
            $this->say('You are teleported.');
        } elseif ($item->kind->effect === 'enchant_weapon') {
            if ($player->weapon === null) {
                $this->say('Your hands twitch.');
            } else {
                $this->say('Your ' . $player->weapon->displayName() . ' glows blue.');
                $player->weapon->bonus++;
            }
        } elseif ($item->kind->effect === 'enchant_armor') {
            if ($player->armor === null) {
                $this->say('Your skin tingles.');
            } else {
                $this->say('Your ' . $player->armor->displayName() . ' glows silver.');
                $player->armor->bonus++;
            }
        }
        return true;
    }

    private function playerAttack(Level $level, Monster $monster): void
    {
        $player = $this->player;
        $weapon = $player->weapon;
        $monster->asleep = false;
        if ($weapon === null) {
            $toHit = $player->level;
            $dice = new Dice(1, 2);
            $bonus = 0;
        } else {
            $toHit = $player->level + $weapon->kind->toHit + $weapon->bonus;
            $dice = $weapon->kind->dice;
            $bonus = $weapon->bonus;
        }
        if (in_array($this->hungerState(), ['weak', 'starving'], true)) {
            $toHit -= 2;
        }
        $name = $monster->kind->name;
        [$outcome, $damage] = resolveAttack($this->rng, $toHit, $monster->kind->defense, $dice, $bonus);
        $this->playerAttacks->record($outcome, $damage);
        if ($outcome === 'miss') {
            $this->say('You miss the ' . $name . '.');
            return;
        }
        $this->say('You hit the ' . $name . ($outcome === 'critical' ? ' hard' : '') . ' for ' . $damage . '.');
        $monster->hp -= $damage;
        if ($monster->hp <= 0) {
            $this->say('You kill the ' . $name . '.');
            removeObject($level->monsters, $monster);
            $level->kills++;
            $this->kills[$name]++;
            $this->gainXp($monster->kind->xp);
        }
    }

    private function gainXp(int $amount): void
    {
        $player = $this->player;
        $thresholds = $this->config->xpLevels;
        $player->xp += $amount;
        while ($player->level <= count($thresholds) && $player->xp >= $thresholds[$player->level - 1]) {
            $player->level++;
            $gained = $this->config->hitDie->roll($this->rng);
            $player->maxHp += $gained;
            $player->hp += $gained;
            $this->say('Welcome to level ' . $player->level . '.');
        }
    }

    private function monsterAttack(Monster $monster): void
    {
        $player = $this->player;
        $kind = $monster->kind;
        [$outcome, $damage] = resolveAttack($this->rng, $kind->toHit, $player->defense(), $kind->damage, 0);
        $this->monsterAttacks->record($outcome, $damage);
        if ($outcome === 'miss') {
            $this->say('The ' . $kind->name . ' misses you.');
            return;
        }
        $this->say('The ' . $kind->name . ' hits you' . ($outcome === 'critical' ? ' hard' : '') . ' for ' . $damage . '.');
        $player->hp -= $damage;
        if ($player->hp <= 0) {
            $this->die('killed_by ' . $kind->name);
        } elseif ($kind->poisonous) {
            $player->poison += 5;
            $this->say('You are poisoned.');
        }
    }

    private function monstersAct(): void
    {
        $level = $this->currentLevel();
        $this->distance = distances($level, $this->player->x, $this->player->y);
        foreach ($level->monsters as $monster) {
            $monster->energy += $monster->kind->speed;
            while ($monster->energy >= 2) {
                $monster->energy -= 2;
                $this->monsterAction($level, $monster);
                if ($this->result !== null) {
                    return;
                }
            }
        }
    }

    private function monsterAction(Level $level, Monster $monster): void
    {
        $sees = $this->visible[$monster->y][$monster->x];
        if ($monster->asleep) {
            if ($sees && $this->rng->draw() % 100 < $this->config->wakeChance) {
                $monster->asleep = false;
                $this->say('The ' . $monster->kind->name . ' wakes up.');
            }
        } elseif ($monster->kind->stationary) {
            if ($this->canAttack($level, $monster)) {
                $this->monsterAttack($monster);
            }
        } elseif ($monster->kind->erratic && $this->rng->draw() % 2 === 0) {
            $this->wander($level, $monster);
        } elseif ($sees) {
            $this->chase($level, $monster);
        } else {
            $this->wander($level, $monster);
        }
    }

    private function canAttack(Level $level, Monster $monster): bool
    {
        $dx = $this->player->x - $monster->x;
        $dy = $this->player->y - $monster->y;
        return max(abs($dx), abs($dy)) === 1 && canMove($level, $monster->x, $monster->y, $dx, $dy);
    }

    private function wander(Level $level, Monster $monster): void
    {
        [$dx, $dy] = DIRECTIONS[$this->rng->draw() % 8];
        if (!canMove($level, $monster->x, $monster->y, $dx, $dy)) {
            return;
        }
        $x = $monster->x + $dx;
        $y = $monster->y + $dy;
        if ($x === $this->player->x && $y === $this->player->y) {
            $this->monsterAttack($monster);
        } elseif ($level->monsterAt($x, $y) === null) {
            $monster->x = $x;
            $monster->y = $y;
        }
    }

    private function chase(Level $level, Monster $monster): void
    {
        if ($this->canAttack($level, $monster)) {
            $this->monsterAttack($monster);
            return;
        }
        $here = $this->distance[$monster->y][$monster->x];
        $best = null;
        $bestDistance = 0;
        foreach (DIRECTIONS as [$dx, $dy]) {
            if (!canMove($level, $monster->x, $monster->y, $dx, $dy)) {
                continue;
            }
            $x = $monster->x + $dx;
            $y = $monster->y + $dy;
            $distance = $this->distance[$y][$x];
            if ($distance < 0 || $here >= 0 && $distance >= $here) {
                continue;
            }
            if ($level->monsterAt($x, $y) !== null || $x === $this->player->x && $y === $this->player->y) {
                continue;
            }
            if ($best === null || $distance < $bestDistance) {
                $best = [$x, $y];
                $bestDistance = $distance;
            }
        }
        if ($best !== null) {
            [$monster->x, $monster->y] = $best;
        }
    }

    private function endTurn(): void
    {
        $level = $this->currentLevel();
        $player = $this->player;
        foreach ($level->monsters as $monster) {
            if ($monster->kind->regenerates && $monster->hp < $monster->maxHp) {
                $monster->hp++;
            }
        }
        if ($player->poison > 0) {
            $player->hp--;
            $this->poisonDamage++;
            if ($player->hp <= 0) {
                $this->die('poison');
                return;
            }
            $player->poison--;
            if ($player->poison === 0) {
                $this->say('You feel less sick.');
            }
        }
        if ($player->satiation === 0) {
            $player->hp--;
            $this->starvationDamage++;
            if ($player->hp <= 0) {
                $this->die('starvation');
                return;
            }
        } else {
            $before = $this->hungerState();
            $player->satiation--;
            $after = $this->hungerState();
            if ($after !== $before) {
                $this->say(HUNGER_MESSAGES[$after]);
            }
        }
        if ($this->turn % $this->config->regenInterval === 0 && $player->poison === 0 && $player->satiation > 0 && $player->hp < $player->maxHp) {
            $player->hp++;
        }
    }

    private function viewSymbol(Level $level, int $x, int $y): string
    {
        if ($x === $this->player->x && $y === $this->player->y) {
            return '@';
        }
        $monster = $level->monsterAt($x, $y);
        if ($monster !== null) {
            return $monster->kind->symbol;
        }
        $item = $level->itemAt($x, $y);
        return $item === null ? $level->terrain[$y][$x] : $item->symbol();
    }

    private function mapRows(Level $level, bool $current): array
    {
        $border = '+' . str_repeat('-', $level->width) . '+';
        $rows = [$border];
        for ($y = 0; $y < $level->height; $y++) {
            $symbols = '';
            for ($x = 0; $x < $level->width; $x++) {
                $symbols .= $current && $this->visible[$y][$x] ? $this->viewSymbol($level, $x, $y) : $level->memory[$y][$x];
            }
            $rows[] = '|' . $symbols . '|';
        }
        $rows[] = $border;
        return $rows;
    }

    private function statusLine(): string
    {
        $p = $this->player;
        return "STATUS hp {$p->hp}/{$p->maxHp} level {$p->level} xp {$p->xp} defense " . $p->defense()
            . " gold {$p->gold} food {$p->satiation} " . $this->hungerState() . " poison {$p->poison}";
    }

    private function writeCheckpoint(): void
    {
        $this->mapLines[] = "CHECKPOINT turn {$this->turn} depth {$this->player->depth}";
        array_push($this->mapLines, ...$this->mapRows($this->currentLevel(), true));
        $this->mapLines[] = $this->statusLine();
    }

    public function finalBlock(): array
    {
        $depth = $this->player->depth;
        $lines = ["FINAL turn {$this->succeeded} depth {$depth}"];
        for ($index = 0; $index < $depth; $index++) {
            $level = $this->levels[$index];
            [$explored, $total] = exploration($level);
            $lines[] = "LEVEL {$level->depth} explored {$explored}/{$total}";
            array_push($lines, ...$this->mapRows($level, $level->depth === $depth));
        }
        $lines[] = $this->statusLine();
        return $lines;
    }

    public function statsLines(): array
    {
        $p = $this->player;
        $lines = [
            'result ' . $this->result,
            'cause ' . $this->cause,
            'turns ' . $this->succeeded,
            'depth ' . $p->depth,
            'level ' . $p->level,
            'xp ' . $p->xp,
            "hp {$p->hp}/{$p->maxHp}",
            'defense ' . $p->defense(),
            'gold ' . $p->gold,
            'food ' . $p->satiation . ' ' . $this->hungerState(),
            'poison ' . $p->poison,
            'weapon ' . ($p->weapon === null ? '-' : $p->weapon->displayName()),
            'armor ' . ($p->armor === null ? '-' : $p->armor->displayName()),
            'commands ' . count($this->commands) . " executed {$this->succeeded} failed {$this->failed} unused {$this->unused}",
            'moves ' . $this->moves,
            $this->playerAttacks->line('player_attacks'),
            $this->monsterAttacks->line('monster_attacks'),
            "poison_damage {$this->poisonDamage} starvation_damage {$this->starvationDamage}",
        ];
        $usage = [];
        foreach (USAGE_FIELDS as $field) {
            $usage[] = $field . ' ' . $this->usage[$field];
        }
        $lines[] = implode(' ', $usage);
        $lines[] = 'kills ' . array_sum($this->kills);
        foreach ($this->monsterTypes as $kind) {
            if ($this->kills[$kind->name] > 0) {
                $lines[] = 'KILL ' . $kind->name . ' ' . $this->kills[$kind->name];
            }
        }
        foreach ($this->levels as $level) {
            [$explored, $total] = exploration($level);
            $lines[] = 'LEVEL ' . $level->depth . ' rooms ' . count($level->rooms) . " explored {$explored}/{$total} "
                . dec1(100 * $explored, $total) . " monsters {$level->kills}/{$level->monstersCreated} items {$level->picked}/{$level->itemsPlaced}";
        }
        foreach ($p->pack as $index => $item) {
            $line = 'INVENTORY ' . ($index + 1) . ' ' . $item->displayName();
            if ($item === $p->weapon) {
                $line .= ' (wielded)';
            } elseif ($item === $p->armor) {
                $line .= ' (worn)';
            }
            $lines[] = $line;
        }
        return $lines;
    }
}

function writeLines(string $name, array $lines): void
{
    file_put_contents('output/' . $name, $lines === [] ? '' : implode("\n", $lines) . "\n");
}

function main(): void
{
    $config = new Config(readRows('config.txt'));
    $monsterTypes = array_map(static fn(array $tokens): MonsterType => new MonsterType($tokens), readRows('monsters.txt'));
    $itemTypes = array_map(__NAMESPACE__ . '\\parseItemType', readRows('items.txt'));
    $game = new Game($config, $monsterTypes, $itemTypes, expandCommands(readRows('commands.txt')));
    $game->run();
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    writeLines('messages.txt', $game->messages);
    writeLines('maps.txt', array_merge($game->mapLines, $game->finalBlock()));
    writeLines('stats.txt', $game->statsLines());
}

main();
