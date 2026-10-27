<?php

function readTopology() {
    $lines = file('input/topology.txt', FILE_IGNORE_NEW_LINES);
    $names = array_slice(explode(' ', array_shift($lines)), 1);
    $channels = [];
    foreach ($lines as $line) {
        $row = explode(' ', $line);
        $channels[] = ['source' => array_search($row[1], $names, true), 'destination' => array_search($row[2], $names, true),
            'type' => $row[3], 'low' => (int)$row[4], 'high' => (int)($row[5] ?? $row[4])];
    }
    usort($channels, fn($a, $b) => ($a['source'] <=> $b['source']) ?: ($a['destination'] <=> $b['destination']));
    return compact('names', 'channels');
}

class Minstd {
    public $state;
    public $draws = 0;

    public function __construct($seed) {
        $this->state = $seed;
    }

    public function next() {
        $this->state = (48271 * $this->state) % 2147483647;
        $this->draws++;
        return $this->state;
    }
}

class Channel {
    public $source;
    public $destination;
    public $type;
    public $low;
    public $high;
    public $sequence = 0;
    public $lastArrival = 0;
    public $messages = 0;
    public $markers = 0;
    public $buffered = 0;
    public $maxDelay = 0;
    public $entries = 0;
    public $previousVector;

    public function __construct($specification, $size) {
        $this->source = $specification['source'];
        $this->destination = $specification['destination'];
        $this->type = $specification['type'];
        $this->low = $specification['low'];
        $this->high = $specification['high'];
        $this->previousVector = array_fill(0, $size, 0);
    }

    public function dispatch($packet, $time, $generator) {
        $packet->sequence = ++$this->sequence;
        $packet->dispatched = $time;
        $delay = $this->low;
        if ($this->high !== $this->low) $delay += $generator->next() % ($this->high - $this->low + 1);
        $packet->arrival = $time + $delay;
        if ($this->type === 'FIFO') $packet->arrival = max($packet->arrival, $this->lastArrival);
        $this->lastArrival = max($this->lastArrival, $packet->arrival);
        $this->maxDelay = max($this->maxDelay, $packet->arrival - $time);
        if (isset($packet->marker)) $this->markers++;
        else {
            $this->messages++;
            $values = $packet->message->event->V;
            foreach ($values as $i => $value) if ($value !== $this->previousVector[$i]) $this->entries++;
            $this->previousVector = $values;
        }
    }
}
