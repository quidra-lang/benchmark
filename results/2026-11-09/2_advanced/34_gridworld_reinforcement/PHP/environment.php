<?php

const ACTIONS = ['N', 'E', 'S', 'W'];

class World
{
    public int $height;
    public int $width;
    public array $cells;
    public array $wind;
    public array $states = [];
    public array $terminals = [];
    public array $index;
    public array $terminalAt;
    public int $start;
    public int $startIndex;
    public array $moves = [];

    public function __construct(int $height, int $width, array $rows, array $wind, array $rewards)
    {
        $this->height = $height;
        $this->width = $width;
        $this->cells = str_split(implode('', $rows));
        $this->wind = $wind;
        $this->index = array_fill(0, count($this->cells), -1);
        $this->terminalAt = array_fill(0, count($this->cells), null);
        foreach ($this->cells as $cell => $terrain) {
            if ($terrain === '#') {
                continue;
            }
            if ($terrain === 'G' || $terrain === 'P') {
                $number = count($this->terminals);
                $terminal = (object) ['cell' => $cell, 'number' => $number, 'reward' => $rewards[$number],
                    'ending' => $terrain === 'G' ? 'goal' : 'pit', 'symbol' => chr(97 + $number)];
                $this->terminals[] = $terminal;
                $this->terminalAt[$cell] = $terminal;
            } else {
                $this->index[$cell] = count($this->states);
                $this->states[] = $cell;
                if ($terrain === 'S') {
                    $this->start = $cell;
                }
            }
        }
        $this->startIndex = $this->index[$this->start];
        foreach ($this->states as $cell) {
            $moves = [];
            for ($action = 0; $action < 4; $action++) {
                $moves[] = $this->move($cell, $action);
            }
            $this->moves[] = $moves;
        }
    }

    public function move(int $cell, int $action): int
    {
        $offsets = [-$this->width, 1, $this->width, -1];
        $reached = $cell + $offsets[$action];
        if ($this->cells[$reached] === '#') {
            $reached = $cell;
        }
        if ($this->terminalAt[$reached] !== null) {
            return $reached;
        }
        for ($step = 0; $step < $this->wind[$cell % $this->width]; $step++) {
            if ($this->cells[$reached - $this->width] === '#') {
                break;
            }
            $reached -= $this->width;
            if ($this->terminalAt[$reached] !== null) {
                break;
            }
        }
        return $reached;
    }
}

function readWorld(): World
{
    $lines = file('input/world.txt', FILE_IGNORE_NEW_LINES);
    $height = (int) explode(' ', $lines[0])[1];
    $width = (int) explode(' ', $lines[1])[1];
    $wind = array_map('intval', str_split(explode(' ', $lines[$height + 2])[1]));
    $rewards = array_map('intval', array_slice(explode(' ', $lines[$height + 3]), 1));
    return new World($height, $width, array_slice($lines, 2, $height), $wind, $rewards);
}

class Minstd
{
    private int $state;

    public function __construct(int $seed)
    {
        $this->state = $seed;
    }

    public function draw(): int
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }
}

class TransitionModel
{
    public World $world;
    public int $denominator;
    public int $floorSlip;
    public int $iceSlip;
    public int $stepReward;
    public array $transitions = [];

    public function __construct(World $world, int $denominator, int $floorSlip, int $iceSlip, int $stepReward)
    {
        $this->world = $world;
        $this->denominator = $denominator;
        $this->floorSlip = $floorSlip;
        $this->iceSlip = $iceSlip;
        $this->stepReward = $stepReward;
        foreach ($world->states as $state => $cell) {
            $row = [];
            for ($action = 0; $action < 4; $action++) {
                $slip = $this->slip($state);
                $outcomes = [[$action, $denominator - 2 * $slip], [($action + 1) % 4, $slip], [($action + 3) % 4, $slip]];
                $transitions = [];
                foreach ($outcomes as [$direction, $weight]) {
                    if ($weight > 0) {
                        $arrival = $this->arrival($state, $direction);
                        $arrival->weight = $weight;
                        $transitions[] = $arrival;
                    }
                }
                $row[] = $transitions;
            }
            $this->transitions[] = $row;
        }
    }

    public function slip(int $state): int
    {
        return $this->world->cells[$this->world->states[$state]] === '~' ? $this->iceSlip : $this->floorSlip;
    }

    public function arrival(int $state, int $direction): object
    {
        $cell = $this->world->moves[$state][$direction];
        $terminal = $this->world->terminalAt[$cell];
        return (object) ['cell' => $cell, 'next' => $this->world->index[$cell], 'reward' => $terminal === null ? $this->stepReward : $terminal->reward];
    }

    public function step(int $state, int $action, Minstd $generator): object
    {
        $value = $generator->draw() % $this->denominator;
        $slip = $this->slip($state);
        $direction = $value < $this->denominator - 2 * $slip ? $action
            : ($value < $this->denominator - $slip ? ($action + 1) % 4 : ($action + 3) % 4);
        return $this->arrival($state, $direction);
    }
}
