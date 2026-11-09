<?php
declare(strict_types=1);

namespace Roguelike;

const ITEM_SYMBOLS = ['weapon' => ')', 'armor' => '[', 'potion' => '!', 'scroll' => '?', 'food' => '%', 'gold' => '$', 'amulet' => '"'];

final class MonsterType
{
    public string $name;
    public string $symbol;
    public int $minDepth;
    public int $maxDepth;
    public int $weight;
    public Dice $hp;
    public int $toHit;
    public int $defense;
    public Dice $damage;
    public int $speed;
    public int $xp;
    public bool $erratic;
    public bool $stationary;
    public bool $regenerates;
    public bool $poisonous;

    public function __construct(array $tokens)
    {
        $this->name = $tokens[0];
        $this->symbol = $tokens[1];
        $this->minDepth = (int)$tokens[2];
        $this->maxDepth = (int)$tokens[3];
        $this->weight = (int)$tokens[4];
        $this->hp = parseDice($tokens[5]);
        $this->toHit = (int)$tokens[6];
        $this->defense = (int)$tokens[7];
        $this->damage = parseDice($tokens[8]);
        $this->speed = (int)$tokens[9];
        $this->xp = (int)$tokens[10];
        $this->erratic = str_contains($tokens[11], 'E');
        $this->stationary = str_contains($tokens[11], 'S');
        $this->regenerates = str_contains($tokens[11], 'R');
        $this->poisonous = str_contains($tokens[11], 'P');
    }
}

final class ItemType
{
    public ?Dice $dice = null;
    public int $toHit = 0;
    public int $armor = 0;
    public ?string $effect = null;
    public int $poisonTurns = 0;
    public int $nutrition = 0;

    public function __construct(public string $category, public string $name, public int $minDepth, public int $maxDepth, public int $weight) {}
}

function parseItemType(array $tokens): ItemType
{
    $category = $tokens[0];
    $kind = new ItemType($category, $tokens[1], (int)$tokens[2], (int)$tokens[3], (int)$tokens[4]);
    if ($category === 'weapon') {
        $kind->dice = parseDice($tokens[5]);
        $kind->toHit = (int)$tokens[6];
    } elseif ($category === 'armor') {
        $kind->armor = (int)$tokens[5];
    } elseif ($category === 'potion') {
        $kind->effect = $tokens[5];
        if ($kind->effect === 'heal') {
            $kind->dice = parseDice($tokens[6]);
        } elseif ($kind->effect === 'poison') {
            $kind->poisonTurns = (int)$tokens[6];
        }
    } elseif ($category === 'scroll') {
        $kind->effect = $tokens[5];
    } elseif ($category === 'food') {
        $kind->nutrition = (int)$tokens[5];
    } elseif ($category === 'gold') {
        $kind->dice = parseDice($tokens[5]);
    }
    return $kind;
}

final class Monster
{
    public int $maxHp;
    public int $energy = 0;
    public bool $wasVisible = false;

    public function __construct(public int $number, public MonsterType $kind, public int $x, public int $y, public int $hp, public bool $asleep)
    {
        $this->maxHp = $hp;
    }
}

final class Item
{
    public int $bonus = 0;
    public function __construct(public ItemType $kind, public int $x, public int $y, public int $amount = 0) {}
    public function symbol(): string { return ITEM_SYMBOLS[$this->kind->category]; }

    public function displayName(): string
    {
        $name = str_replace('_', ' ', $this->kind->name);
        if ($this->kind->category === 'weapon' || $this->kind->category === 'armor') {
            return '+' . $this->bonus . ' ' . $name;
        }
        return $this->kind->category === 'gold' ? $this->amount . ' gold' : $name;
    }

    public function referenceName(): string
    {
        return ($this->kind->category === 'gold' ? '' : 'the ') . $this->displayName();
    }
}
