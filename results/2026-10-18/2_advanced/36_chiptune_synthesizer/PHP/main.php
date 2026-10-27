<?php

require_once __DIR__ . '/song_parser.php';
require_once __DIR__ . '/instruments.php';
require_once __DIR__ . '/sequencer.php';
require_once __DIR__ . '/mixer.php';
require_once __DIR__ . '/report.php';

const EFFECTS = ['0', '1', '2', '3', '4', '5', '6', '7', 'A', 'B', 'C', 'D', 'E1', 'E2', 'E9', 'EA', 'EB', 'EC', 'ED', 'EE', 'F', 'P', 'Q', 'R', 'V'];
const KEY_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const KEY_WEIGHTS = [[64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29], [64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32]];

function clamp(int $value, int $low, int $high): int
{
    return min($high, max($low, $value));
}

function pad(mixed $value, int $width): string
{
    return str_pad((string) $value, $width, ' ', STR_PAD_LEFT);
}

function address(int $position, int $row): string
{
    return hex2($position) . ':' . hex2($row);
}

function newChannel(): object
{
    return (object) ['instrument' => null, 'note' => null, 'base' => 0, 'target' => 0, 'portamento' => 0, 'slide' => 0, 'detune' => 0,
        'vibratoSpeed' => 0, 'vibratoDepth' => 0, 'vibratoPosition' => 0, 'tremoloSpeed' => 0, 'tremoloDepth' => 0, 'tremoloPosition' => 0,
        'volume' => 15, 'mode' => 0, 'phase' => 0, 'register' => 1, 'age' => 0, 'keyedOff' => false, 'offAge' => 0, 'offEnvelope' => 0,
        'envelope' => 0, 'outputFrequency' => 0, 'outputVolume' => 0, 'amplitude' => 0, 'increment' => 0, 'effect' => null, 'cell' => null,
        'sounding' => false, 'activeRecord' => null, 'counters' => (object) ['notes' => 0, 'retriggers' => 0, 'cuts' => 0, 'active' => 0, 'audible' => 0]];
}

function keyOff(object $channel): void
{
    $channel->offAge = $channel->age;
    $channel->offEnvelope = $channel->envelope;
    $channel->keyedOff = true;
}

function computeOutput(object $channel, int $tick, int $rate): void
{
    $channel->sounding = $channel->note !== null;
    if (!$channel->sounding) {
        return;
    }
    $effect = $channel->effect;
    $instrument = $channel->instrument;
    $semitones = 0;
    if (($effect->name ?? null) === '0') {
        $semitones = $tick % 3 === 1 ? $effect->x : ($tick % 3 === 2 ? $effect->y : 0);
    }
    if ($instrument->arpeggio !== null) {
        $semitones += $instrument->arpeggio[$channel->age % count($instrument->arpeggio)];
    }
    $output = transpose($channel->base, $semitones) + $channel->detune;
    if (($effect->name ?? null) === '4' || ($effect->name ?? null) === '6') {
        $output += oscillation($channel->vibratoPosition, $channel->vibratoDepth, 4);
    }
    if ($instrument->vibrato !== null) {
        [$delay, $speed, $depth] = $instrument->vibrato;
        if ($channel->age >= $delay) {
            $output += oscillation(($channel->age - $delay) * $speed % 64, $depth, 4);
        }
    }
    $channel->outputFrequency = clamp($output, 1000, 50 * $rate);
    $channel->envelope = envelope($channel);
    $channel->outputVolume = ($effect->name ?? null) === '7'
        ? clamp($channel->volume + oscillation($channel->tremoloPosition, $channel->tremoloDepth, 255), 0, 15) : $channel->volume;
    $channel->amplitude = $channel->envelope * $channel->outputVolume;
    $channel->increment = intdiv($channel->outputFrequency * 65536, 100 * $rate);
}

function approach(object $channel, int $step): void
{
    $channel->base = $channel->base < $channel->target ? min($channel->base + $step, $channel->target) : max($channel->base - $step, $channel->target);
}

class Player
{
    public object $song;
    public object $settings;
    public array $channels;
    public array $samples = [];
    public array $lanes = [[], [], [], []];
    public array $records = [];
    public array $warnings = [];
    public array $rows = [];
    public array $log = [];
    public array $visits = [];
    public array $effectCounts = [];
    public array $instrumentTicks = [];
    public int $speed;
    public int $tempo;
    public int $position = 0;
    public int $row = 0;
    public int $ticks = 0;
    public int $clipped = 0;
    public ?object $ending = null;
    private int $delay = 0;

    public function __construct(object $song, object $settings)
    {
        $this->song = $song;
        $this->settings = $settings;
        $this->channels = [newChannel(), newChannel(), newChannel(), newChannel()];
        foreach ($song->instruments as $number => $instrument) {
            $this->instrumentTicks[$number] = 0;
        }
        $this->speed = $song->speed;
        $this->tempo = $song->tempo;
    }

    private function warn(int $channel, string $message): void
    {
        $this->warnings[] = 'warning ' . address($this->position, $this->row) . ' ch' . ($channel + 1) . ' ' . $message;
    }

    private function closeRecord(object $channel, string $reason): void
    {
        if ($channel->activeRecord === null) {
            return;
        }
        $channel->activeRecord->length = count($this->samples) - $channel->activeRecord->start;
        $channel->activeRecord->reason = $reason;
        $channel->activeRecord = null;
    }

    private function noteOn(object $channel, int $index, int $note): void
    {
        $this->closeRecord($channel, 'next');
        $channel->note = $note;
        $channel->base = $channel->target = frequency($note);
        $channel->phase = $channel->age = $channel->vibratoPosition = $channel->tremoloPosition = 0;
        $channel->keyedOff = false;
        $record = (object) ['serial' => count($this->records) + 1, 'channel' => $index, 'position' => $this->position, 'row' => $this->row,
            'instrument' => $channel->instrument->number, 'note' => $note, 'start' => count($this->samples), 'release' => null];
        $this->records[] = $record;
        $channel->activeRecord = $record;
        $channel->counters->notes++;
    }

    private function cellContent(object $channel, int $index, bool $portamento): void
    {
        $cell = $channel->cell;
        if ($cell->instrument !== null) {
            $instrument = $this->song->instruments[$cell->instrument] ?? null;
            if ($instrument === null) {
                $this->warn($index, 'undefined instrument ' . hex2($cell->instrument));
            } else {
                $channel->instrument = $instrument;
                $channel->volume = 15;
                $channel->mode = $instrument->mode;
            }
        }
        if ($cell->volume !== null) {
            $channel->volume = $cell->volume;
        }
        if ($cell->note === 'OFF') {
            if ($channel->note !== null && !$channel->keyedOff) {
                keyOff($channel);
                $channel->activeRecord->release = count($this->samples) - $channel->activeRecord->start;
            } else {
                $this->warn($index, 'key off without note');
            }
        } elseif ($cell->note !== null) {
            if ($channel->instrument === null) {
                $this->warn($index, 'note without instrument');
            } elseif ($portamento && $channel->note !== null) {
                $channel->target = frequency($cell->note);
                $channel->note = $cell->note;
            } else {
                if ($portamento) {
                    $this->warn($index, 'portamento without note');
                }
                $this->noteOn($channel, $index, $cell->note);
            }
        }
    }

    private function tickZero(object $channel, int $index): void
    {
        $effect = $channel->effect;
        if ($effect === null) {
            return;
        }
        $name = $effect->name;
        $argument = $effect->argument;
        $x = $effect->x;
        $y = $effect->y;
        if ($name === '3') {
            if ($argument > 0) {
                $channel->portamento = $argument;
            }
        } elseif ($name === '4') {
            if ($x > 0) $channel->vibratoSpeed = $x;
            if ($y > 0) $channel->vibratoDepth = $y;
        } elseif ($name === '7') {
            if ($x > 0) $channel->tremoloSpeed = $x;
            if ($y > 0) $channel->tremoloDepth = $y;
        } elseif ($name === 'C') {
            $channel->volume = min($argument, 15);
        } elseif ($name === 'E1') {
            $channel->base = clamp($channel->base + 10 * $argument, 1000, 50 * $this->song->rate);
        } elseif ($name === 'E2') {
            $channel->base = clamp($channel->base - 10 * $argument, 1000, 50 * $this->song->rate);
        } elseif ($name === 'EA') {
            $channel->volume = min($channel->volume + $argument, 15);
        } elseif ($name === 'EB') {
            $channel->volume = max($channel->volume - $argument, 0);
        } elseif ($name === 'EE') {
            $this->delay = $argument;
        } elseif ($name === 'F') {
            if ($argument >= 1 && $argument <= 31) $this->speed = $argument;
            elseif ($argument >= 32) $this->tempo = $argument;
        } elseif ($name === 'P') {
            $channel->detune = $argument - 128;
        } elseif ($name === 'Q' || $name === 'R') {
            if ($channel->note === null) {
                $this->warn($index, 'slide without note');
            } else {
                $channel->note = $name === 'Q' ? min($channel->note + $y, 95) : max($channel->note - $y, 12);
                $channel->target = frequency($channel->note);
                $channel->slide = 2 * $x + 1;
            }
        } elseif ($name === 'V') {
            $wave = $channel->instrument->wave ?? null;
            if (($wave === 'PULSE' && $argument <= 3) || ($wave === 'NOISE' && $argument <= 1)) {
                $channel->mode = $argument;
            } else {
                $this->warn($index, 'invalid mode ' . hex2($argument));
            }
        }
    }

    private function startRow(array $cells): int
    {
        $this->delay = 0;
        foreach ($this->channels as $index => $channel) {
            $channel->cell = $cells[$index];
            $channel->effect = $cells[$index]->effect;
            $channel->slide = 0;
            $effect = $channel->effect;
            if ($effect !== null) {
                $this->effectCounts[$effect->name] = ($this->effectCounts[$effect->name] ?? 0) + 1;
            }
            if (!(($effect->name ?? null) === 'ED' && $effect->argument >= 1)) {
                $this->cellContent($channel, $index, ($effect->name ?? null) === '3' || ($effect->name ?? null) === '5');
            }
            $this->tickZero($channel, $index);
        }
        $ticks = $this->speed * (1 + $this->delay);
        foreach ($this->channels as $index => $channel) {
            $effect = $channel->effect;
            if (($effect->name ?? null) === 'EC' && $effect->argument >= $ticks) {
                $this->warn($index, 'cut beyond row');
            }
            if (($effect->name ?? null) === 'ED' && $effect->argument >= $ticks) {
                $this->warn($index, 'delay beyond row');
            }
        }
        return $ticks;
    }

    private function tickEffect(object $channel): void
    {
        $effect = $channel->effect;
        if ($effect === null) {
            return;
        }
        $name = $effect->name;
        $argument = $effect->argument;
        if ($name === '1') {
            $channel->base = clamp($channel->base + 10 * $argument, 1000, 50 * $this->song->rate);
        } elseif ($name === '2') {
            $channel->base = clamp($channel->base - 10 * $argument, 1000, 50 * $this->song->rate);
        } elseif ($name === '3' || $name === '5') {
            approach($channel, 10 * $channel->portamento);
        } elseif (($name === 'Q' || $name === 'R') && $channel->slide !== 0) {
            approach($channel, 10 * $channel->slide);
        }
        if ($name === '5' || $name === '6' || $name === 'A') {
            $channel->volume = clamp($channel->volume + $effect->x - $effect->y, 0, 15);
        }
    }

    private function processTick(int $tick): void
    {
        foreach ($this->channels as $index => $channel) {
            if ($channel->note !== null && $channel->age >= 1 && $channel->instrument->sweep !== 0) {
                $channel->base = clamp($channel->base + 10 * $channel->instrument->sweep, 1000, 50 * $this->song->rate);
            }
            if ($tick >= 1) {
                $this->tickEffect($channel);
            }
            $effect = $channel->effect;
            if (($effect->name ?? null) === 'ED' && $effect->argument >= 1 && $tick === $effect->argument) {
                $this->cellContent($channel, $index, false);
            }
            if (($effect->name ?? null) === 'E9' && $effect->argument >= 1 && $tick >= 1 && $tick % $effect->argument === 0 && $channel->note !== null) {
                $channel->phase = $channel->age = 0;
                $channel->keyedOff = false;
                $channel->counters->retriggers++;
            }
            if (($effect->name ?? null) === 'EC' && $tick === $effect->argument && $channel->note !== null) {
                $this->closeRecord($channel, 'cut');
                $channel->note = null;
                $channel->counters->cuts++;
            }
            computeOutput($channel, $tick, $this->song->rate);
            if ($channel->sounding) {
                $channel->counters->active++;
                if ($channel->amplitude > 0) {
                    $channel->counters->audible++;
                }
                $this->instrumentTicks[$channel->instrument->number]++;
            }
        }
    }

    private function rowLine(object $record): string
    {
        $channels = [];
        foreach ($this->channels as $channel) {
            $effect = $channel->effect->text ?? '...';
            $channels[] = $channel->note === null ? '--- --       - - ' . hex1($channel->volume) . ' ' . $effect
                : noteName($channel->note) . ' ' . hex2($channel->instrument->number) . ' ' . pad($channel->outputFrequency, 7)
                    . ' ' . hex1($channel->envelope) . ' ' . hex1($channel->outputVolume) . ' ' . $effect;
        }
        return hex2($record->position) . ' ' . hex2($record->pattern) . ' ' . hex2($record->row) . ' ' . pad($record->start, 7)
            . ' ' . pad($record->speed, 2) . ' ' . pad($record->tempo, 3) . ' | ' . implode(' | ', $channels);
    }

    private function tickLine(int $tick): string
    {
        $channels = [];
        foreach ($this->channels as $channel) {
            $channels[] = $channel->sounding ? pad($channel->outputFrequency, 7) . ' ' . pad($channel->increment, 5) . ' '
                . hex1($channel->envelope) . hex1($channel->outputVolume) : '      -     - --';
        }
        return '  tick ' . pad($tick, 3) . ' ' . pad(count($this->samples), 7) . ' | ' . implode(' | ', $channels);
    }

    public function play(): void
    {
        while ($this->ending === null) {
            $pattern = $this->song->order[$this->position];
            $cells = $this->song->patterns[$pattern][$this->row];
            $rowTicks = $this->startRow($cells);
            $record = (object) ['position' => $this->position, 'pattern' => $pattern, 'row' => $this->row,
                'start' => count($this->samples), 'speed' => $this->speed, 'tempo' => $this->tempo];
            $this->rows[] = $record;
            $key = $this->position . ',' . $this->row;
            if (!isset($this->visits[$key])) {
                $this->visits[$key] = (object) ['count' => 0, 'start' => $record->start];
            }
            $this->visits[$key]->count++;
            $perTick = samplesPerTick($this->song->rate, $this->tempo);
            for ($tick = 0; $tick < $rowTicks; $tick++) {
                $this->processTick($tick);
                if ($tick === 0) {
                    $record->notes = array_map(fn($channel) => $channel->note, $this->channels);
                    $this->log[] = $this->rowLine($record);
                }
                if (isset($this->settings->traces[$key])) {
                    $this->log[] = $this->tickLine($tick);
                }
                $count = min($perTick, $this->settings->maximum - count($this->samples));
                $this->clipped += generate($this->channels, $count, $this->song->gain, $this->settings->mute, $this->samples, $this->lanes);
                $this->ticks++;
                foreach ($this->channels as $channel) {
                    if ($channel->note !== null) {
                        $channel->age++;
                    }
                    if (($channel->effect->name ?? null) === '4' || ($channel->effect->name ?? null) === '6') {
                        $channel->vibratoPosition = ($channel->vibratoPosition + $channel->vibratoSpeed) % 64;
                    }
                    if (($channel->effect->name ?? null) === '7') {
                        $channel->tremoloPosition = ($channel->tremoloPosition + $channel->tremoloSpeed) % 64;
                    }
                }
                if (count($this->samples) === $this->settings->maximum) {
                    $this->ending = (object) ['reason' => 'limit'];
                    break;
                }
            }
            if ($this->ending !== null) {
                break;
            }
            $next = nextRow($this->song, $this->position, $this->row);
            if (isset($next->reason)) {
                $this->ending = $next;
            } else {
                $visit = $this->visits[$next->position . ',' . $next->row] ?? null;
                if ($visit !== null && $visit->count >= $this->settings->loops) {
                    $this->ending = (object) ['position' => $next->position, 'row' => $next->row, 'reason' => 'loop', 'start' => $visit->start];
                } else {
                    $this->position = $next->position;
                    $this->row = $next->row;
                }
            }
        }
        foreach ($this->channels as $channel) {
            $this->closeRecord($channel, 'end');
        }
        if (($this->ending->reason === 'limit' || $this->ending->reason === 'loop') && $this->settings->fade > 0) {
            fadeOut($this->samples, $this->settings->fade);
        }
    }
}

function noteRange(array $records): string
{
    if (!$records) {
        return 'none';
    }
    $low = 95;
    $high = 12;
    foreach ($records as $record) {
        $low = min($low, $record->note);
        $high = max($high, $record->note);
    }
    return noteName($low) . '..' . noteName($high);
}

function noteLines(Player $player): array
{
    $lines = [];
    foreach ($player->records as $record) {
        $lane = $player->lanes[$record->channel];
        $peak = $cycles = 0;
        for ($i = $record->start; $i < $record->start + $record->length; $i++) {
            $peak = max($peak, abs($lane[$i]));
            if ($i > $record->start && $lane[$i - 1] < 0 && $lane[$i] >= 0) {
                $cycles++;
            }
        }
        $lines[] = pad($record->serial, 4) . ' ch=' . ($record->channel + 1) . ' at=' . address($record->position, $record->row)
            . ' ins=' . hex2($record->instrument) . ' note=' . noteName($record->note) . ' start=' . $record->start . ' length=' . $record->length
            . ' release=' . ($record->release ?? '-') . ' end=' . $record->reason . ' peak=' . $peak . ' cycles=' . $cycles;
    }
    return $lines;
}

function rollLines(Player $player): array
{
    [$start, $count] = $player->settings->roll;
    $rows = array_slice($player->rows, $start, $count);
    $pitchSet = [];
    foreach ($rows as $row) {
        foreach ($row->notes as $note) {
            if ($note !== null) {
                $pitchSet[$note] = true;
            }
        }
    }
    $pitches = array_keys($pitchSet);
    rsort($pitches, SORT_NUMERIC);
    $lines = ['ROLL start=' . $start . ' rows=' . count($rows) . ' pitches=' . count($pitches)];
    foreach ($pitches as $pitch) {
        $columns = '';
        foreach ($rows as $row) {
            $channels = [];
            foreach ($row->notes as $index => $note) {
                if ($note === $pitch) {
                    $channels[] = (string) ($index + 1);
                }
            }
            $columns .= !$channels ? ' ' : (count($channels) === 1 ? $channels[0] : '*');
        }
        $lines[] = noteName($pitch) . ' |' . $columns . '|';
    }
    $axis = '';
    foreach ($rows as $index => $row) {
        $axis .= $index % 16 === 0 ? '+' : '-';
    }
    $lines[] = '    +' . $axis . '+';
    return $lines;
}

function statsLines(Player $player): array
{
    $song = $player->song;
    $samples = $player->samples;
    $rows = $player->rows;
    $records = $player->records;
    $ending = $player->ending;
    $instruments = array_values($song->instruments);
    usort($instruments, fn($a, $b) => $a->number <=> $b->number);
    $patterns = array_keys($song->patterns);
    sort($patterns, SORT_NUMERIC);
    $mix = statistics($samples);
    $end = $ending->reason === 'stop' || $ending->reason === 'loop'
        ? $ending->reason . ' order=' . hex2($ending->position) . ' row=' . hex2($ending->row) : $ending->reason;
    $lines = ['title=' . $song->title, 'rate=' . $song->rate, 'samples=' . count($samples),
        'duration_ms=' . intdiv(count($samples) * 1000, $song->rate), 'end=' . $end,
        'loop_start=' . ($ending->reason === 'loop' ? $ending->start : '-'),
        'loop_length=' . ($ending->reason === 'loop' ? count($samples) - $ending->start : '-'),
        'rows=' . count($rows), 'ticks=' . $player->ticks, 'clipped=' . $player->clipped,
        'peak=' . $mix->peak, 'min=' . $mix->minimum, 'max=' . $mix->maximum, 'rms=' . $mix->rms,
        'zero_crossings=' . $mix->crossings, 'adler32=' . adler32($samples)];
    $path = [];
    foreach ($rows as $index => $row) {
        if ($index === 0 || $rows[$index - 1]->position !== $row->position) {
            $path[] = hex2($row->position);
        }
    }
    $lines[] = 'path ' . implode(' ', $path);
    foreach ($rows as $index => $row) {
        if ($index === 0 || $row->speed !== $rows[$index - 1]->speed || $row->tempo !== $rows[$index - 1]->tempo) {
            $lines[] = 'timing sample=' . $row->start . ' order=' . hex2($row->position) . ' row=' . hex2($row->row)
                . ' speed=' . $row->speed . ' tempo=' . $row->tempo;
        }
    }
    foreach ($player->channels as $index => $channel) {
        $counters = $channel->counters;
        $lane = statistics($player->lanes[$index], 0);
        $lines[] = 'channel ' . ($index + 1) . ' notes=' . $counters->notes . ' retriggers=' . $counters->retriggers . ' cuts=' . $counters->cuts
            . ' active=' . $counters->active . ' audible=' . $counters->audible . ' peak=' . $lane->peak . ' rms=' . $lane->rms;
    }
    foreach ($instruments as $instrument) {
        $selected = array_values(array_filter($records, fn($record) => $record->instrument === $instrument->number));
        $total = 0;
        foreach ($selected as $record) {
            $total += $record->length;
        }
        $average = $selected ? intdiv($total, count($selected)) : '-';
        $lines[] = 'instrument ' . hex2($instrument->number) . ' ' . $instrument->name . ' ' . $instrument->wave . ' notes=' . count($selected)
            . ' ticks=' . $player->instrumentTicks[$instrument->number] . ' range=' . noteRange($selected) . ' average=' . $average;
    }
    foreach ($patterns as $pattern) {
        $contents = $song->patterns[$pattern];
        $populated = $notes = 0;
        foreach ($contents as $cells) {
            $isPopulated = false;
            foreach ($cells as $cell) {
                if ($cell->note !== null || $cell->instrument !== null || $cell->volume !== null || $cell->effect !== null) {
                    $isPopulated = true;
                }
                if ($cell->note !== null) {
                    $notes++;
                }
            }
            if ($isPopulated) {
                $populated++;
            }
        }
        $orders = count(array_filter($song->order, fn($number) => $number === $pattern));
        $lines[] = 'pattern ' . hex2($pattern) . ' rows=' . $populated . ' notes=' . $notes . ' orders=' . $orders;
    }
    $reachable = reachableRows($song);
    foreach ($song->order as $position => $pattern) {
        $played = array_values(array_filter($rows, fn($row) => $row->position === $position));
        $dead = 0;
        foreach ($song->patterns[$pattern] as $rowNumber => $cells) {
            if (isset($reachable[$position . ',' . $rowNumber])) {
                continue;
            }
            foreach ($cells as $cell) {
                if ($cell->note !== null) {
                    $dead++;
                    break;
                }
            }
        }
        $lines[] = 'order ' . hex2($position) . ' pattern=' . hex2($pattern) . ' rows=' . count($played)
            . ' first=' . ($played ? $played[0]->start : '-') . ' dead=' . $dead;
    }
    $notes = [];
    foreach ($records as $record) {
        $notes[$record->note] = ($notes[$record->note] ?? 0) + 1;
    }
    ksort($notes, SORT_NUMERIC);
    foreach ($notes as $note => $count) {
        $lines[] = 'note ' . noteName($note) . ' count=' . $count;
    }
    $effects = [];
    foreach (EFFECTS as $name) {
        if (isset($player->effectCounts[$name])) {
            $effects[] = $name . '=' . $player->effectCounts[$name];
        }
    }
    $lines[] = 'effects ' . ($effects ? implode(' ', $effects) : 'none');
    $usedInstruments = [];
    foreach ($records as $record) {
        $usedInstruments[$record->instrument] = true;
    }
    $unusedInstruments = [];
    foreach ($instruments as $instrument) {
        if (!isset($usedInstruments[$instrument->number])) {
            $unusedInstruments[] = hex2($instrument->number);
        }
    }
    $unusedPatterns = [];
    foreach ($patterns as $pattern) {
        if (!in_array($pattern, $song->order, true)) {
            $unusedPatterns[] = hex2($pattern);
        }
    }
    $unreachedOrders = [];
    foreach ($song->order as $position => $pattern) {
        $played = false;
        foreach ($rows as $row) {
            if ($row->position === $position) {
                $played = true;
                break;
            }
        }
        if (!$played) {
            $unreachedOrders[] = hex2($position);
        }
    }
    $lines[] = 'unused_instruments=' . ($unusedInstruments ? implode(' ', $unusedInstruments) : 'none');
    $lines[] = 'unused_patterns=' . ($unusedPatterns ? implode(' ', $unusedPatterns) : 'none');
    $lines[] = 'unreached_orders=' . ($unreachedOrders ? implode(' ', $unreachedOrders) : 'none');
    $durations = array_fill(0, 12, 0);
    foreach ($records as $record) {
        if ($song->instruments[$record->instrument]->wave !== 'NOISE') {
            $durations[$record->note % 12] += $record->length;
        }
    }
    $pitchClasses = [];
    foreach (KEY_NAMES as $index => $name) {
        $pitchClasses[] = $name . '=' . $durations[$index];
    }
    $lines[] = 'pitch_classes ' . implode(' ', $pitchClasses);
    $keys = [];
    foreach (KEY_WEIGHTS as $mode => $weights) {
        foreach (KEY_NAMES as $tonic => $name) {
            $score = 0;
            foreach ($durations as $pitch => $duration) {
                $score += $weights[($pitch - $tonic + 12) % 12] * $duration;
            }
            $keys[] = (object) ['name' => $name . ($mode === 0 ? ' major' : ' minor'), 'order' => $mode * 12 + $tonic, 'score' => $score];
        }
    }
    usort($keys, fn($a, $b) => ($b->score <=> $a->score) ?: ($a->order <=> $b->order));
    $lines[] = 'key=' . $keys[0]->name . ' score=' . $keys[0]->score . ' runner_up=' . $keys[1]->name . ' score=' . $keys[1]->score;
    foreach ($player->channels as $index => $channel) {
        $selected = array_values(array_filter($records, fn($record) => $record->channel === $index));
        $line = 'usage ch' . ($index + 1) . ' range=' . noteRange($selected);
        foreach ($instruments as $instrument) {
            $count = count(array_filter($selected, fn($record) => $record->instrument === $instrument->number));
            $line .= ' ' . hex2($instrument->number) . '=' . $count;
        }
        $lines[] = $line;
    }
    return array_merge($lines, $player->warnings);
}

function plot(array $values, int $low, int $high, int $middle, int $height, int $width): array
{
    $rowOf = fn($value) => intdiv(2 * ($high - $value) * ($height - 1) + $high - $low, 2 * ($high - $low));
    $middleRow = $rowOf($middle);
    $columns = [];
    for ($column = 0; $column < $width; $column++) {
        $start = intdiv($column * count($values), $width);
        $end = intdiv(($column + 1) * count($values), $width);
        $bottom = $top = $values[$start];
        for ($i = $start + 1; $i < $end; $i++) {
            $bottom = min($bottom, $values[$i]);
            $top = max($top, $values[$i]);
        }
        $columns[] = [$rowOf($top), $rowOf($bottom)];
    }
    $lines = [];
    for ($row = 0; $row < $height; $row++) {
        $label = $row === 0 ? $high : ($row === $middleRow ? $middle : ($row === $height - 1 ? $low : ''));
        $cells = '';
        foreach ($columns as [$top, $bottom]) {
            $cells .= $row >= $top && $row <= $bottom ? '#' : ($row === $middleRow ? '-' : ' ');
        }
        $lines[] = pad($label, 5) . ' |' . $cells . '|';
    }
    return $lines;
}

function waveformLines(Player $player): array
{
    [$start, $length, $width, $height, $scope] = $player->settings->window;
    $axis = '      +';
    for ($column = 0; $column < $width; $column++) {
        $axis .= $column % 10 === 0 ? '+' : '-';
    }
    $axis .= '+';
    $milliseconds = '    ms';
    for ($column = 0; $column < $width; $column += 10) {
        $value = intdiv(($start + intdiv($column * $length, $width)) * 1000, $player->song->rate);
        $milliseconds = str_pad($milliseconds, 7 + $column) . $value;
    }
    $lines = array_merge(['MIX start=' . $start . ' length=' . $length . ' width=' . $width . ' height=' . $height],
        plot(array_slice($player->samples, $start, $length), 0, 255, 128, $height, $width), [$axis, $milliseconds]);
    for ($index = 0; $index < 4; $index++) {
        $lines[] = 'CHANNEL ' . ($index + 1);
        $lines = array_merge($lines, plot(array_slice($player->lanes[$index], $start, $length), -3375, 3375, 0, $scope, $width));
    }
    $lines[] = $axis;
    $lines[] = $milliseconds;
    return $lines;
}

function previewLines(object $song, object $settings): array
{
    $lines = [];
    $instruments = array_values($song->instruments);
    usort($instruments, fn($a, $b) => $a->number <=> $b->number);
    $perTick = samplesPerTick($song->rate, $song->tempo);
    foreach ($instruments as $instrument) {
        $channel = newChannel();
        $channel->instrument = $instrument;
        $channel->mode = $instrument->mode;
        $channel->note = $settings->preview->note;
        $channel->base = $channel->target = frequency($channel->note);
        $samples = [];
        $envelopes = [];
        $frequencies = [];
        for ($tick = 0; $tick < $settings->preview->ticks; $tick++) {
            $channel->age = $tick;
            if ($tick === $settings->preview->release) {
                keyOff($channel);
            }
            if ($tick >= 1 && $instrument->sweep !== 0) {
                $channel->base = clamp($channel->base + 10 * $instrument->sweep, 1000, 50 * $song->rate);
            }
            computeOutput($channel, $tick, $song->rate);
            $envelopes[] = hex1($channel->envelope);
            $frequencies[] = $channel->outputFrequency;
            generate([$channel], $perTick, $song->gain, [0], $samples);
        }
        $stats = statistics($samples);
        $lines[] = 'instrument ' . hex2($instrument->number) . ' ' . $instrument->name . ' wave=' . $instrument->wave
            . ' samples=' . count($samples) . ' peak=' . $stats->peak . ' rms=' . $stats->rms . ' adler32=' . adler32($samples);
        $lines[] = '  env ' . implode('', $envelopes);
        $lines[] = '  freq ' . implode(' ', $frequencies);
    }
    return $lines;
}

$input = readSong();
$player = new Player($input->song, $input->settings);
$player->play();
$outputs = ['samples.txt' => hexDump($player->samples), 'channel_log.txt' => $player->log, 'notes.txt' => noteLines($player),
    'roll.txt' => rollLines($player), 'stats.txt' => statsLines($player), 'waveform.txt' => waveformLines($player),
    'instruments.txt' => previewLines($input->song, $input->settings)];
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
foreach ($outputs as $name => $lines) {
    file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
}
