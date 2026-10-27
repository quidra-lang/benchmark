<?php

class Minstd
{
    public $state;

    public function __construct($seed)
    {
        $this->state = $seed;
    }

    public function next()
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }
}

function shuffleBag(&$bag, $random)
{
    for ($i = count($bag) - 1; $i >= 1; $i--) {
        $j = $random->next() % ($i + 1);
        [$bag[$i], $bag[$j]] = [$bag[$j], $bag[$i]];
    }
}

function makeBag($table, $random)
{
    $bag = [];
    foreach ($table as $letter => $tile) {
        for ($i = 0; $i < $tile['count']; $i++) {
            $bag[] = $letter;
        }
    }
    shuffleBag($bag, $random);
    return $bag;
}

function draw(&$bag, $count)
{
    $tiles = '';
    for ($i = 0; $i < $count && $bag; $i++) {
        $tiles .= array_pop($bag);
    }
    return $tiles;
}

function exchange(&$bag, $returned, $random)
{
    $drawn = draw($bag, strlen($returned));
    $tiles = str_split($returned);
    sort($tiles, SORT_STRING);
    foreach ($tiles as $tile) {
        $bag[] = $tile;
    }
    shuffleBag($bag, $random);
    return $drawn;
}

function tileValue($tiles, $table)
{
    $total = 0;
    foreach (str_split($tiles) as $tile) {
        $total += $table[$tile]['value'];
    }
    return $total;
}
