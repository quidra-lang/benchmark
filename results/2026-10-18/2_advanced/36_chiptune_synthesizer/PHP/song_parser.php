<?php

const PITCHES = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-'];

function noteNumber(string $text): int
{
    return 12 * (int) $text[2] + array_search(substr($text, 0, 2), PITCHES, true);
}

function noteName(int $number): string
{
    return PITCHES[$number % 12] . intdiv($number, 12);
}

function parseCell(string $text): object
{
    [$note, $instrument, $volume, $effectText] = explode(' ', $text);
    $effect = null;
    if ($effectText !== '...') {
        $command = $effectText[0];
        $effect = (object) ['text' => $effectText, 'command' => $command, 'name' => $command === 'E' ? substr($effectText, 0, 2) : $command,
            'argument' => hexdec($command === 'E' ? $effectText[2] : substr($effectText, 1)),
            'x' => hexdec($effectText[1]), 'y' => hexdec($effectText[2])];
    }
    return (object) ['note' => $note === '...' ? null : ($note === 'OFF' ? 'OFF' : noteNumber($note)),
        'instrument' => $instrument === '..' ? null : hexdec($instrument), 'volume' => $volume === '.' ? null : hexdec($volume), 'effect' => $effect];
}

function readSong(): object
{
    $lines = array_values(array_filter(file('input/song.txt', FILE_IGNORE_NEW_LINES), fn($line) => $line !== '' && !str_starts_with($line, '#')));
    $value = fn($index) => (int) explode(' ', $lines[$index])[1];
    $song = (object) ['title' => substr($lines[0], 6), 'rate' => $value(1), 'speed' => $value(2), 'tempo' => $value(3),
        'gain' => $value(4), 'instruments' => [], 'patterns' => [], 'order' => []];
    for ($i = 5; $i < count($lines); $i++) {
        $words = explode(' ', $lines[$i]);
        if ($words[0] === 'ORDER') {
            $song->order = array_map('hexdec', array_slice($words, 1));
        } elseif ($words[0] === 'INSTRUMENT') {
            $instrument = (object) ['number' => hexdec($words[1]), 'name' => $words[2], 'vibrato' => null,
                'arpeggio' => null, 'sweep' => 0, 'mode' => 0];
            while ($lines[++$i] !== 'END') {
                $attributes = explode(' ', $lines[$i]);
                $name = array_shift($attributes);
                if ($name === 'WAVE') {
                    $instrument->wave = $attributes[0];
                    if ($instrument->wave === 'PULSE') {
                        $instrument->mode = array_search((int) $attributes[1], [12, 25, 50, 75], true);
                    } elseif ($instrument->wave === 'NOISE') {
                        $instrument->mode = (int) ($attributes[1] === 'SHORT');
                    } elseif ($instrument->wave === 'TABLE') {
                        $instrument->table = array_map('hexdec', str_split($attributes[1]));
                    }
                } elseif ($name === 'ENVELOPE') {
                    $instrument->envelope = array_map('intval', $attributes);
                } elseif ($name === 'VIBRATO') {
                    $instrument->vibrato = array_map('intval', $attributes);
                } elseif ($name === 'ARPEGGIO') {
                    $instrument->arpeggio = array_map('intval', $attributes);
                } else {
                    $instrument->sweep = (int) $attributes[0];
                }
            }
            $song->instruments[$instrument->number] = $instrument;
        } else {
            $number = hexdec($words[1]);
            $rows = [];
            for ($row = 0; $row < 64; $row++) {
                $rows[] = array_map('parseCell', array_fill(0, 4, '... .. . ...'));
            }
            while ($lines[++$i] !== 'END') {
                $row = hexdec(substr($lines[$i], 0, 2));
                $rows[$row] = array_map('parseCell', explode(' | ', substr($lines[$i], 3)));
            }
            $song->patterns[$number] = $rows;
        }
    }
    $params = array_map(fn($line) => explode(' ', $line), file('input/params.txt', FILE_IGNORE_NEW_LINES));
    $traces = [];
    foreach (array_slice($params, 7) as $words) {
        $traces[hexdec($words[1]) . ',' . hexdec($words[2])] = true;
    }
    $settings = (object) ['maximum' => (int) $params[0][1], 'loops' => (int) $params[1][1], 'fade' => (int) $params[2][1],
        'mute' => array_map('intval', array_slice($params[3], 1)), 'window' => array_map('intval', array_slice($params[4], 1)),
        'roll' => array_map('intval', array_slice($params[5], 1)),
        'preview' => (object) ['note' => noteNumber($params[6][1]), 'ticks' => (int) $params[6][2], 'release' => (int) $params[6][3]],
        'traces' => $traces];
    return (object) compact('song', 'settings');
}
