<?php

class Snapshot {
    public $name;
    public $started;
    public $completed = null;
    public $records;
    public $channels;
    public $dispatched;
    public $accepted;
    public $remaining;
    public $ignored = [];

    public function __construct($name, $time, $size) {
        $this->name = $name;
        $this->started = $time;
        $this->records = array_fill(0, $size, null);
        $this->channels = array_fill(0, $size, array_fill(0, $size, []));
        $this->dispatched = $this->accepted = array_fill(0, $size, array_fill(0, $size, null));
        $this->remaining = $size * ($size - 1);
    }

    public function record($process, $time, $reason) {
        $record = (object)['process' => $process->index, 'time' => $time, 'reason' => $reason, 'balance' => $process->balance,
            'L' => $process->L, 'V' => $process->V, 'pending' => $process->hold, 'snapshot' => $this];
        $this->records[$process->index] = $record;
        return $record;
    }

    public function cut() {
        $cut = [];
        foreach ($this->records as $i => $record) $cut[] = $record->V[$i];
        return $cut;
    }
}

function inspectCut($processes, $copies, $cut) {
    $orphans = $transit = [];
    foreach ($copies as $copy) {
        $sent = $copy->message->event->local <= $cut[$copy->source];
        $received = $copy->received !== null && $copy->received->local <= $cut[$copy->destination];
        if ($received && !$sent) $orphans[] = $copy;
        if ($sent && !$received) $transit[] = $copy;
    }
    $balances = 0;
    foreach ($processes as $i => $process) $balances += balanceAt($process, $cut[$i]);
    $money = $balances;
    foreach ($transit as $copy) $money += $copy->message->amount;
    return compact('orphans', 'transit', 'balances', 'money');
}
