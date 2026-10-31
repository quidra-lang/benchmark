<?php
declare(strict_types=1);

namespace TowerDefense;

require_once __DIR__ . '/grid_map.php';
require_once __DIR__ . '/pathing.php';
require_once __DIR__ . '/combat.php';
require_once __DIR__ . '/towers.php';
require_once __DIR__ . '/enemies.php';

const INCOME_FIELDS = ['bounty', 'reward', 'interest', 'early', 'refund'];
const WAVE_COLUMNS = 'wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives';

function readLines(string $name): array { return file('input/' . $name, FILE_IGNORE_NEW_LINES); }
function writeLines(string $name, array $lines): void { file_put_contents('output/' . $name, $lines === [] ? '' : implode("\n", $lines) . "\n"); }

function oneDecimal(int $numerator, int $denominator): string
{
    if ($denominator === 0) {
        return '-';
    }
    $rounded = intdiv(20 * $numerator + $denominator, 2 * $denominator);
    return intdiv($rounded, 10) . '.' . ($rounded % 10);
}

function digit(int $count): string { return $count === 0 ? '.' : ($count <= 9 ? (string)$count : '*'); }

function ruled(array $rows): array
{
    $ruler = '  ';
    for ($x = 0; $x < count($rows[0]); $x++) {
        $ruler .= $x % 10;
    }
    $lines = [$ruler];
    foreach ($rows as $y => $row) {
        $lines[] = ($y % 10) . ' ' . implode('', $row);
    }
    return $lines;
}

final class Params
{
    public int $gold;
    public int $lives;
    public int $interestRate;
    public int $interestCap;
    public int $sellRate;
    public int $start;
    public int $interval;
    public int $early;
    public array $snapshots = [];

    public function __construct(array $lines)
    {
        $fields = array_map(static fn(string $line): array => explode(' ', $line), $lines);
        $this->gold = (int)$fields[0][1];
        $this->lives = (int)$fields[1][1];
        $this->interestRate = (int)$fields[2][1];
        $this->interestCap = (int)$fields[2][2];
        $this->sellRate = (int)$fields[3][1];
        $this->start = (int)$fields[4][1];
        $this->interval = (int)$fields[4][2];
        $this->early = (int)$fields[5][1];
        foreach (array_slice($fields[6], 1) as $tick) {
            $this->snapshots[(int)$tick] = true;
        }
    }
}

final class Action
{
    public int $tick;
    public string $command;
    public array $arguments;

    public function __construct(string $line)
    {
        $fields = explode(' ', $line);
        $this->tick = (int)$fields[0];
        $this->command = $fields[1];
        $this->arguments = array_slice($fields, 2);
    }
}

final class WaveRecord
{
    public int $end = 0;
    public string $status = '';
    public array $released;
    public int $spawned = 0;
    public int $peak = 0;
    public int $kills = 0;
    public int $leaks = 0;
    public int $livesLost = 0;
    public int $bounty = 0;
    public int $reward = 0;
    public int $interest = 0;
    public int $gold = 0;
    public int $lives = 0;
    public array $towerDamage = [];

    public function __construct(public int $number, public Wave $plan, public int $start)
    {
        $this->released = array_fill(0, count($plan->groups), 0);
    }

    public function allReleased(): bool
    {
        foreach ($this->plan->groups as $index => $group) {
            if ($this->released[$index] !== $group->count) {
                return false;
            }
        }
        return true;
    }

    public function close(string $status, int $tick, int $gold, int $lives): void
    {
        $this->status = $status;
        $this->end = $tick;
        $this->gold = $gold;
        $this->lives = $lives;
    }

    public function csvRow(int $towerCount): string
    {
        $values = [$this->number, $this->start, $this->end, $this->status, $this->spawned, $this->peak, $this->kills,
            $this->leaks, $this->livesLost, $this->bounty, $this->reward, $this->interest, $this->gold, $this->lives];
        for ($number = 1; $number <= $towerCount; $number++) {
            $values[] = $this->towerDamage[$number] ?? 0;
        }
        return implode(',', $values);
    }
}

final class Game
{
    public array $towerTypes = [];
    public array $exitCenter;
    public int $tick = 0;
    public int $gold;
    public int $lives;
    public array $towers = [];
    public array $enemies = [];
    public array $allEnemies = [];
    public array $projectiles = [];
    public int $projectileCount = 0;
    public array $records = [];
    public ?WaveRecord $active = null;
    public ?int $nextStart;
    public ?string $outcome = null;
    public DistanceField $field;
    public array $killCounts;
    public array $income;
    public int $spent = 0;
    public int $done = 0;
    public int $refused = 0;
    public array $events = [];
    public array $snapshots = [];

    public function __construct(public GridMap $grid, array $towerTypes, public array $enemyTypes, public array $waves, public Params $params)
    {
        foreach ($towerTypes as $kind) {
            $this->towerTypes['#' . $kind->name] = $kind;
        }
        $this->exitCenter = cellCenter($grid->exit);
        $this->gold = $params->gold;
        $this->lives = $params->lives;
        $this->nextStart = $params->start;
        $this->field = new DistanceField($grid, []);
        $this->killCounts = array_fill(0, $grid->height, array_fill(0, $grid->width, 0));
        $this->income = array_fill_keys(INCOME_FIELDS, 0);
    }

    private function record(int|string ...$parts): void
    {
        $this->events[] = $this->tick . ' ' . implode(' ', $parts);
    }

    public function run(array $actions): void
    {
        $index = 0;
        while (true) {
            $this->tick++;
            while ($index < count($actions) && $actions[$index]->tick === $this->tick) {
                $this->perform($actions[$index++]);
            }
            $this->spawnEnemies();
            $this->moveEnemies();
            if ($this->outcome !== null) {
                break;
            }
            $this->fireTowers();
            $this->moveProjectiles();
            $this->checkWaveEnd();
            if (isset($this->params->snapshots[$this->tick])) {
                array_push($this->snapshots, ...$this->block('SNAPSHOT'));
            }
            if ($this->outcome !== null) {
                break;
            }
        }
        array_push($this->snapshots, ...$this->finalBlock());
    }

    private function standingTowers(): array { return array_values(array_filter($this->towers, static fn(Tower $tower): bool => $tower->standing())); }

    private function towerCells(): array
    {
        $cells = [];
        foreach ($this->standingTowers() as $tower) {
            $cells[cellKey($tower->cell)] = true;
        }
        return $cells;
    }

    private function towerAt(array $cell): ?Tower
    {
        foreach ($this->standingTowers() as $tower) {
            if ($tower->cell === $cell) {
                return $tower;
            }
        }
        return null;
    }

    private function standingTower(string $text): ?Tower
    {
        $number = (int)$text;
        return isset($this->towers[$number - 1]) && $this->towers[$number - 1]->standing() ? $this->towers[$number - 1] : null;
    }

    private function groundEnemies(): array { return array_values(array_filter($this->enemies, static fn(Enemy $enemy): bool => !$enemy->flying())); }

    private function perform(Action $action): void
    {
        $succeeded = match ($action->command) {
            'BUILD' => $this->build($action->arguments), 'UPGRADE' => $this->upgrade($action->arguments),
            'SELL' => $this->sell($action->arguments), 'TARGET' => $this->setTarget($action->arguments),
            'CALL' => $this->callWave(),
        };
        if ($succeeded) {
            $this->done++;
        } else {
            $this->refused++;
        }
    }

    private function buildRefusal(string $name, array $cell): ?string
    {
        if (!isset($this->towerTypes['#' . $name])) {
            return 'type';
        }
        if (!$this->grid->inside($cell)) {
            return 'bounds';
        }
        if (!$this->grid->buildable($cell)) {
            return 'terrain';
        }
        if ($this->towerAt($cell) !== null) {
            return 'tower';
        }
        if ($this->gold < $this->towerTypes['#' . $name]->levels[0]->cost) {
            return 'gold';
        }
        $walkers = $this->groundEnemies();
        foreach ($walkers as $enemy) {
            if ($enemy->cell === $cell || $enemy->nextCell === $cell) {
                return 'enemy';
            }
        }
        $occupied = $this->towerCells();
        $occupied[cellKey($cell)] = true;
        $trial = new DistanceField($this->grid, $occupied);
        foreach ($this->grid->spawns as $spawn) {
            if ($trial->at($spawn) < 0) {
                return 'blocked';
            }
        }
        foreach ($walkers as $enemy) {
            if ($trial->at($enemy->nextCell) < 0) {
                return 'blocked';
            }
        }
        return null;
    }

    private function build(array $arguments): bool
    {
        [$name, $xText, $yText] = $arguments;
        $cell = [(int)$xText, (int)$yText];
        $reason = $this->buildRefusal($name, $cell);
        if ($reason !== null) {
            $this->record('BUILD_REFUSED', $name, $xText, $yText, $reason);
            return false;
        }
        $kind = $this->towerTypes['#' . $name];
        $cost = $kind->levels[0]->cost;
        $tower = new Tower(count($this->towers) + 1, $kind, $cell, $this->tick);
        $this->towers[] = $tower;
        $this->gold -= $cost;
        $this->spent += $cost;
        $this->record('BUILD', 'T' . $tower->number, $name, ...array_merge($cell, ['cost', $cost, 'gold', $this->gold]));
        $this->updateField();
        return true;
    }

    private function upgrade(array $arguments): bool
    {
        $tower = $this->standingTower($arguments[0]);
        if ($tower === null) {
            $reason = 'notower';
        } elseif ($tower->level === count($tower->kind->levels)) {
            $reason = 'maxlevel';
        } elseif ($this->gold < $tower->kind->levels[$tower->level]->cost) {
            $reason = 'gold';
        } else {
            $cost = $tower->kind->levels[$tower->level]->cost;
            $this->gold -= $cost;
            $this->spent += $cost;
            $tower->level++;
            $tower->investment += $cost;
            $this->record('UPGRADE', 'T' . $tower->number, 'level', $tower->level, 'cost', $cost, 'gold', $this->gold);
            return true;
        }
        $this->record('UPGRADE_REFUSED', 'T' . $arguments[0], $reason);
        return false;
    }

    private function sell(array $arguments): bool
    {
        $tower = $this->standingTower($arguments[0]);
        if ($tower === null) {
            $this->record('SELL_REFUSED', 'T' . $arguments[0], 'notower');
            return false;
        }
        $rate = $this->tick === $tower->built ? 100 : $this->params->sellRate;
        $refund = intdiv($tower->investment * $rate, 100);
        $tower->sold = $this->tick;
        $this->gold += $refund;
        $this->income['refund'] += $refund;
        $this->record('SELL', 'T' . $tower->number, 'refund', $refund, 'gold', $this->gold);
        $this->updateField();
        return true;
    }

    private function setTarget(array $arguments): bool
    {
        [$number, $mode] = $arguments;
        $tower = $this->standingTower($number);
        if ($tower === null) {
            $reason = 'notower';
        } elseif (!in_array($mode, TARGET_MODES, true)) {
            $reason = 'mode';
        } else {
            $tower->mode = $mode;
            $this->record('TARGET', 'T' . $tower->number, $mode);
            return true;
        }
        $this->record('TARGET_REFUSED', 'T' . $number, $reason);
        return false;
    }

    private function callWave(): bool
    {
        if ($this->active !== null) {
            $this->record('CALL_REFUSED', 'active');
            return false;
        }
        $bonus = ($this->nextStart - $this->tick) * $this->params->early;
        $this->gold += $bonus;
        $this->income['early'] += $bonus;
        $this->nextStart = $this->tick;
        $this->record('CALL', count($this->records) + 1, 'bonus', $bonus, 'gold', $this->gold);
        return true;
    }

    private function updateField(): void
    {
        $before = $this->field;
        $this->field = new DistanceField($this->grid, $this->towerCells());
        foreach ($this->grid->spawns as $index => $spawn) {
            $old = $before->at($spawn);
            $new = $this->field->at($spawn);
            if ($old !== $new) {
                $this->record('REPATH', $index + 1, $old, $new);
            }
        }
    }

    private function startWave(): void
    {
        $plan = $this->waves[count($this->records)];
        $wave = new WaveRecord(count($this->records) + 1, $plan, $this->tick);
        $this->records[] = $wave;
        $this->active = $wave;
        $this->nextStart = null;
        $this->record('WAVE_START', $wave->number, 'enemies', $plan->enemyCount());
    }

    private function addEnemy(Enemy $enemy): void
    {
        $this->enemies[] = $enemy;
        $this->allEnemies[] = $enemy;
        $this->active->spawned++;
        $enemy->kind->spawned++;
    }

    private function removeEnemy(Enemy $enemy): void
    {
        $enemy->alive = false;
        $this->enemies = array_values(array_filter($this->enemies, static fn(Enemy $current): bool => $current !== $enemy));
    }

    private function spawnEnemies(): void
    {
        if ($this->tick === $this->nextStart) {
            $this->startWave();
        }
        $wave = $this->active;
        if ($wave === null) {
            return;
        }
        foreach ($wave->plan->groups as $index => $group) {
            $released = $wave->released[$index];
            if ($released === $group->count || $group->spawnTick($wave->start, $released) !== $this->tick) {
                continue;
            }
            $wave->released[$index]++;
            $spawn = $this->grid->spawns[$group->spawn - 1];
            $enemy = new Enemy(count($this->allEnemies) + 1, $group->kind, $group->multiplier);
            if ($enemy->flying()) {
                $enemy->point = cellCenter($spawn);
            } else {
                $enemy->cell = $spawn;
                $enemy->nextCell = $this->field->nextCell($spawn);
            }
            $this->addEnemy($enemy);
            $this->record('SPAWN', 'E' . $enemy->number, $enemy->kind->name, $group->spawn, 'hp', $enemy->hp);
        }
        $wave->peak = max($wave->peak, count($this->enemies));
    }

    private function moveEnemies(): void
    {
        $moving = $this->enemies;
        foreach ($moving as $enemy) {
            $this->moveEnemy($enemy);
            if ($this->outcome !== null) {
                return;
            }
        }
    }

    private function moveEnemy(Enemy $enemy): void
    {
        if ($enemy->burn->active()) {
            $source = $this->towers[$enemy->burn->source - 1];
            $damage = min($enemy->hp, $enemy->burn->strength);
            $enemy->hp -= $damage;
            $this->credit($source, $enemy, $damage);
            $enemy->burn->advanceTime();
            if ($enemy->hp === 0) {
                $this->kill($enemy, $source);
                return;
            }
        }
        $enemy->hp = min($enemy->hp + $enemy->kind->regen, $enemy->maxHp);
        $speed = $enemy->slowedSpeed();
        if ($enemy->slow->active()) {
            $enemy->slow->advanceTime();
        }
        if ($enemy->flying()) {
            [$enemy->point, $arrived] = advance($enemy->point, $this->exitCenter, $speed);
        } else {
            $arrived = $this->walk($enemy, $speed);
        }
        if ($arrived) {
            $this->leak($enemy);
        }
    }

    private function walk(Enemy $enemy, int $speed): bool
    {
        if ($this->grid->isWater($enemy->occupiedCell())) {
            $speed = intdiv($speed, 2);
        }
        while ($speed > 0) {
            $rest = 100 - $enemy->progress;
            if ($speed < $rest) {
                $enemy->progress += $speed;
                $speed = 0;
            } else {
                $speed -= $rest;
                $enemy->cell = $enemy->nextCell;
                $enemy->progress = 0;
                if ($enemy->cell === $this->grid->exit) {
                    return true;
                }
                $enemy->nextCell = $this->field->nextCell($enemy->cell);
            }
        }
        return false;
    }

    private function leak(Enemy $enemy): void
    {
        $this->removeEnemy($enemy);
        $lost = min($this->lives, $enemy->kind->lives);
        $this->lives -= $lost;
        $wave = $this->active;
        $wave->leaks++;
        $wave->livesLost += $lost;
        $enemy->kind->leaks++;
        $this->record('LEAK', 'E' . $enemy->number, $enemy->kind->name, 'lives', $this->lives);
        if ($this->lives === 0) {
            $this->record('DEFEAT');
            $this->outcome = 'defeat';
            $wave->close('lost', $this->tick, $this->gold, $this->lives);
            $this->active = null;
        }
    }

    private function fireTowers(): void
    {
        foreach ($this->standingTowers() as $tower) {
            if ($this->tick < $tower->ready) {
                continue;
            }
            $target = $tower->selectTarget($this->enemies, $this->field);
            if ($target !== null) {
                $this->fire($tower, $target);
            }
        }
    }

    private function fire(Tower $tower, Enemy $target): void
    {
        $stats = $tower->stats();
        $this->projectileCount++;
        $this->projectiles[] = new Projectile($this->projectileCount, $tower->number, $target->number, $tower->center(), $target->position(), $tower->kind->targets, $stats);
        $tower->shots++;
        $tower->ready = $this->tick + $stats->interval;
        $this->record('SHOT', 'T' . $tower->number, 'E' . $target->number);
    }

    private function moveProjectiles(): void
    {
        $flying = [];
        foreach ($this->projectiles as $projectile) {
            $target = $this->allEnemies[$projectile->target - 1];
            if ($target->alive) {
                $projectile->aim = $target->position();
            }
            if ($projectile->fly()) {
                $this->impact($projectile);
            } else {
                $flying[] = $projectile;
            }
        }
        $this->projectiles = $flying;
    }

    private function impact(Projectile $projectile): void
    {
        $tower = $this->towers[$projectile->tower - 1];
        $target = $this->allEnemies[$projectile->target - 1];
        if ($projectile->splash === 0) {
            $victims = $target->alive ? [$target] : [];
        } else {
            $reach = $projectile->splash * $projectile->splash;
            $victims = array_values(array_filter($this->enemies, static fn(Enemy $enemy): bool => canAim($projectile->targets, $enemy) && squaredDistance($enemy->position(), $projectile->aim) <= $reach));
        }
        if ($victims === []) {
            $tower->fizzles++;
        }
        foreach ($victims as $enemy) {
            $tower->hits++;
            $damage = damageDealt($enemy->hp, $projectile->power, $enemy->kind->armor);
            $enemy->hp -= $damage;
            $this->credit($tower, $enemy, $damage);
            if ($enemy->hp === 0) {
                $this->kill($enemy, $tower);
                continue;
            }
            if ($projectile->slowRate > 0) {
                $enemy->slow->receive($projectile->slowRate, $projectile->slowTime);
            }
            if ($projectile->burnAmount > 0) {
                $enemy->burn->receive($projectile->burnAmount, $projectile->burnTime, $tower->number);
            }
        }
    }

    private function credit(Tower $tower, Enemy $enemy, int $damage): void
    {
        $tower->damage += $damage;
        $enemy->kind->damage += $damage;
        $this->active->towerDamage[$tower->number] = ($this->active->towerDamage[$tower->number] ?? 0) + $damage;
    }

    private function kill(Enemy $enemy, Tower $tower): void
    {
        $this->removeEnemy($enemy);
        [$x, $y] = $enemy->occupiedCell();
        $this->killCounts[$y][$x]++;
        $wave = $this->active;
        $bounty = $enemy->kind->bounty;
        $tower->kills++;
        $wave->kills++;
        $enemy->kind->kills++;
        $this->gold += $bounty;
        $wave->bounty += $bounty;
        $this->income['bounty'] += $bounty;
        $this->record('KILL', 'E' . $enemy->number, $enemy->kind->name, 'T' . $tower->number, 'bounty', $bounty, 'gold', $this->gold);
        for ($index = 0; $index < $enemy->kind->splitCount; $index++) {
            $child = $enemy->split(count($this->allEnemies) + 1);
            $this->addEnemy($child);
            $this->record('SPAWN', 'E' . $child->number, $child->kind->name, 'E' . $enemy->number, 'hp', $child->hp);
        }
    }

    private function checkWaveEnd(): void
    {
        $wave = $this->active;
        if ($wave === null || $this->enemies !== [] || !$wave->allReleased()) {
            return;
        }
        $this->gold += $wave->plan->reward;
        $interest = min($this->params->interestCap, intdiv($this->gold * $this->params->interestRate, 100));
        $this->gold += $interest;
        $wave->reward = $wave->plan->reward;
        $wave->interest = $interest;
        $this->income['reward'] += $wave->reward;
        $this->income['interest'] += $interest;
        $this->active = null;
        $this->record('WAVE_END', $wave->number, 'reward', $wave->reward, 'interest', $interest, 'gold', $this->gold);
        if ($wave->number === count($this->waves)) {
            $this->record('VICTORY');
            $this->outcome = 'victory';
        } else {
            $this->nextStart = $this->tick + $this->params->interval;
        }
        $wave->close('cleared', $this->tick, $this->gold, $this->lives);
    }

    private function mapPicture(): array
    {
        $rows = array_map('str_split', $this->grid->rows);
        foreach ($this->grid->spawns as $spawn) {
            foreach ($this->field->path($spawn) as $cell) {
                $terrain = $this->grid->terrain($cell);
                if ($terrain === '.' || $terrain === '~') {
                    $rows[$cell[1]][$cell[0]] = '+';
                }
            }
        }
        foreach ($this->standingTowers() as $tower) {
            $rows[$tower->cell[1]][$tower->cell[0]] = $tower->kind->symbol;
        }
        $occupants = [];
        foreach ($this->enemies as $enemy) {
            $cell = $enemy->occupiedCell();
            $key = cellKey($cell);
            $occupants[$key] = ($occupants[$key] ?? 0) + 1;
            $rows[$cell[1]][$cell[0]] = $occupants[$key] === 1 ? $enemy->kind->symbol : '*';
        }
        return $rows;
    }

    private function flowPicture(): array
    {
        $rows = [];
        for ($y = 0; $y < $this->grid->height; $y++) {
            $row = [];
            for ($x = 0; $x < $this->grid->width; $x++) {
                $cell = [$x, $y];
                $terrain = $this->grid->terrain($cell);
                $tower = $this->towerAt($cell);
                if ($terrain === '#' || $terrain === 'E') {
                    $row[] = $terrain;
                } elseif ($tower !== null) {
                    $row[] = $tower->kind->symbol;
                } elseif ($this->field->at($cell) < 0) {
                    $row[] = '?';
                } else {
                    $row[] = '^>v<'[$this->field->direction($cell)];
                }
            }
            $rows[] = $row;
        }
        return $rows;
    }

    private function coveragePicture(): array
    {
        $standing = $this->standingTowers();
        $rows = [];
        for ($y = 0; $y < $this->grid->height; $y++) {
            $row = [];
            for ($x = 0; $x < $this->grid->width; $x++) {
                $cell = [$x, $y];
                $tower = $this->towerAt($cell);
                if ($this->grid->isRock($cell)) {
                    $row[] = '#';
                } elseif ($tower !== null) {
                    $row[] = $tower->kind->symbol;
                } else {
                    $count = 0;
                    foreach ($standing as $other) {
                        $count += (int)$other->inRange(cellCenter($cell));
                    }
                    $row[] = digit($count);
                }
            }
            $rows[] = $row;
        }
        return $rows;
    }

    private function killsPicture(): array
    {
        $rows = [];
        for ($y = 0; $y < $this->grid->height; $y++) {
            $row = [];
            for ($x = 0; $x < $this->grid->width; $x++) {
                $count = $this->killCounts[$y][$x];
                $row[] = $count > 0 ? digit($count) : ($this->grid->isRock([$x, $y]) ? '#' : '.');
            }
            $rows[] = $row;
        }
        return $rows;
    }

    private function block(string $label): array
    {
        $next = $this->active === null && $this->outcome === null ? (string)$this->nextStart : '-';
        $lines = ["$label " . $this->tick . ' wave ' . count($this->records) . " next $next gold " . $this->gold . ' lives ' . $this->lives];
        array_push($lines, ...ruled($this->mapPicture()));
        foreach ($this->grid->spawns as $index => $spawn) {
            $lines[] = 'PATH ' . ($index + 1) . ' length ' . $this->field->at($spawn);
        }
        foreach ($this->standingTowers() as $tower) {
            $lines[] = 'T' . $tower->number . ' ' . $tower->kind->name . ' ' . $tower->cell[0] . ' ' . $tower->cell[1]
                . ' level ' . $tower->level . ' mode ' . $tower->mode . ' ready ' . $tower->ready;
        }
        foreach ($this->enemies as $enemy) {
            [$x, $y] = $enemy->position();
            $lines[] = 'E' . $enemy->number . ' ' . $enemy->kind->name . " $x $y hp " . $enemy->hp . '/' . $enemy->maxHp
                . ' slow ' . $enemy->slow->strength . ' ' . $enemy->slow->remaining . ' burn ' . $enemy->burn->strength . ' ' . $enemy->burn->remaining;
        }
        foreach ($this->projectiles as $projectile) {
            $lines[] = 'P' . $projectile->number . ' T' . $projectile->tower . ' E' . $projectile->target . ' ' . $projectile->position[0] . ' ' . $projectile->position[1];
        }
        return $lines;
    }

    private function finalBlock(): array
    {
        $lines = $this->block('FINAL');
        $lines[] = 'FLOW';
        array_push($lines, ...ruled($this->flowPicture()));
        $lines[] = 'COVERAGE';
        array_push($lines, ...ruled($this->coveragePicture()));
        $lines[] = 'KILLS';
        array_push($lines, ...ruled($this->killsPicture()));
        return $lines;
    }

    public function waveLines(): array
    {
        $header = WAVE_COLUMNS;
        foreach ($this->towers as $tower) {
            $header .= ',T' . $tower->number;
        }
        return array_merge([$header], array_map(fn(WaveRecord $wave): string => $wave->csvRow(count($this->towers)), $this->records));
    }

    private function mvpLine(): string
    {
        $best = null;
        foreach ($this->towers as $tower) {
            if ($best === null || $tower->damage > $best->damage) {
                $best = $tower;
            }
        }
        return $best === null ? 'mvp -' : 'mvp T' . $best->number . ' damage ' . $best->damage;
    }

    private function towerLine(Tower $tower, int $totalDamage): string
    {
        $state = $tower->standing() ? 'active' : 'sold ' . $tower->sold;
        return 'TOWER T' . $tower->number . ' ' . $tower->kind->name . ' ' . $tower->cell[0] . ' ' . $tower->cell[1]
            . ' level ' . $tower->level . ' mode ' . $tower->mode . " $state shots " . $tower->shots . ' hits ' . $tower->hits
            . ' fizzles ' . $tower->fizzles . ' kills ' . $tower->kills . ' damage ' . $tower->damage
            . ' per_shot ' . oneDecimal($tower->damage, $tower->shots) . ' share ' . oneDecimal(100 * $tower->damage, $totalDamage) . ' invested ' . $tower->investment;
    }

    public function summaryLines(int $actionCount): array
    {
        $cleared = $perfect = $spawned = $killed = $leaked = $totalDamage = 0;
        foreach ($this->records as $wave) {
            if ($wave->status === 'cleared') {
                $cleared++;
                $perfect += (int)($wave->leaks === 0);
            }
        }
        foreach ($this->enemyTypes as $kind) {
            $spawned += $kind->spawned;
            $killed += $kind->kills;
            $leaked += $kind->leaks;
        }
        foreach ($this->towers as $tower) {
            $totalDamage += $tower->damage;
        }
        $income = [];
        foreach (INCOME_FIELDS as $name) {
            $income[] = $name . ' ' . $this->income[$name];
        }
        $score = 10 * $killed + 100 * $this->lives + 50 * $perfect + $this->gold;
        $unused = $actionCount - $this->done - $this->refused;
        $lines = ['outcome ' . $this->outcome, 'ticks ' . $this->tick, "waves $cleared/" . count($this->waves) . " perfect $perfect",
            'lives ' . $this->lives . '/' . $this->params->lives, 'gold ' . $this->gold, "enemies spawned $spawned killed $killed leaked $leaked",
            'income ' . implode(' ', $income), 'spent ' . $this->spent, "damage $totalDamage",
            "actions total $actionCount done " . $this->done . ' refused ' . $this->refused . " unused $unused", "score $score", $this->mvpLine()];
        foreach ($this->enemyTypes as $kind) {
            $lines[] = 'ENEMY ' . $kind->name . ' spawned ' . $kind->spawned . ' killed ' . $kind->kills . ' leaked ' . $kind->leaks . ' damage ' . $kind->damage;
        }
        foreach ($this->towers as $tower) {
            $lines[] = $this->towerLine($tower, $totalDamage);
        }
        return $lines;
    }
}

$grid = readMap('input/map.txt');
$towerTypes = parseTowerTypes(readLines('towers.txt'));
[$enemyTypes, $waves] = parseWaves(readLines('waves.txt'));
$actions = array_map(static fn(string $line): Action => new Action($line), readLines('actions.txt'));
$game = new Game($grid, $towerTypes, $enemyTypes, $waves, new Params(readLines('params.txt')));
$game->run($actions);
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
writeLines('events.txt', $game->events);
writeLines('waves.csv', $game->waveLines());
writeLines('snapshots.txt', $game->snapshots);
writeLines('summary.txt', $game->summaryLines(count($actions)));
