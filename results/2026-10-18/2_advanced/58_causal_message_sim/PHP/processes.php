<?php

function parseAction($words, $names) {
    $type = $words[0];
    if ($type === 'LOCAL') return ['type' => $type, 'label' => $words[1]];
    if ($type === 'BROADCAST') return ['type' => $type, 'tag' => $words[1]];
    if ($type === 'SNAPSHOT') return ['type' => $type, 'name' => $words[1]];
    $destination = $words[1] === 'SENDER' ? 'SENDER' : array_search($words[1], $names, true);
    return $type === 'SEND' ? ['type' => $type, 'destination' => $destination, 'tag' => $words[2]]
        : ['type' => $type, 'destination' => $destination, 'amount' => (int)$words[2]];
}

function readPrograms($names) {
    $programs = [];
    foreach (file('input/programs.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $words = explode(' ', $line);
        if ($words[0] === 'PROCESS') {
            $programs[] = ['index' => array_search($words[1], $names, true), 'balance' => (int)$words[3], 'scheduled' => [], 'reactions' => []];
            $current = count($programs) - 1;
        } elseif ($words[0] === 'ON') {
            $programs[$current]['reactions'][] = ['tag' => $words[1], 'action' => parseAction(array_slice($words, 2), $names)];
        } elseif ($words[0] === 'AT') {
            $recurring = $words[2] === 'EVERY';
            $programs[$current]['scheduled'][] = ['time' => (int)$words[1], 'period' => $recurring ? (int)$words[3] : 0,
                'action' => parseAction(array_slice($words, $recurring ? 4 : 2), $names)];
        }
    }
    return $programs;
}

class ProcessState {
    public $index;
    public $initial;
    public $balance;
    public $minimum;
    public $L = 0;
    public $V;
    public $B;
    public $next;
    public $reorder;
    public $hold = [];
    public $reactions;
    public $events = [];
    public $deliveries = [];
    public $maxHeld = 0;
    public $received = 0;
    public $sent = 0;
    public $counts = ['LOCAL' => 0, 'NOFUNDS' => 0, 'SEND' => 0, 'BCAST' => 0, 'RECV' => 0];

    public function __construct($program, $size) {
        $this->index = $program['index'];
        $this->initial = $this->balance = $this->minimum = $program['balance'];
        $this->V = $this->B = array_fill(0, $size, 0);
        $this->next = array_fill(0, $size, 1);
        $this->reorder = array_fill(0, $size, []);
        $this->reactions = $program['reactions'];
    }
}

function expandScheduled($programs, $end) {
    $items = [];
    foreach ($programs as $program) foreach ($program['scheduled'] as $line) {
        for ($time = $line['time']; $time <= $end; $time += $line['period']) {
            $items[] = (object)['time' => $time, 'process' => $program['index'], 'action' => $line['action']];
            if ($line['period'] === 0) break;
        }
    }
    return $items;
}

function balanceAt($process, $count) {
    return $count === 0 ? $process->initial : $process->events[$count - 1]->balance;
}
