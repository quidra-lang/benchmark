<?php

const T = [26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388];
const S = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
    255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24];

function floorDiv(int $value, int $divisor): int
{
    $quotient = intdiv($value, $divisor);
    return $value < 0 && $value % $divisor !== 0 ? $quotient - 1 : $quotient;
}

function frequency(int $note): int
{
    $octave = intdiv($note, 12);
    return $octave >= 4 ? T[$note % 12] * (2 ** ($octave - 4)) : intdiv(T[$note % 12], 2 ** (4 - $octave));
}

function transpose(int $value, int $semitones): int
{
    return intdiv($value * T[$semitones % 12], T[0]) * (2 ** intdiv($semitones, 12));
}

function oscillation(int $position, int $depth, int $divisor): int
{
    $value = intdiv(S[$position % 32] * $depth, $divisor);
    return $position < 32 ? $value : -$value;
}

function envelope(object $channel): int
{
    [$attack, $decay, $sustain, $release] = $channel->instrument->envelope;
    $age = $channel->age;
    if ($channel->keyedOff) {
        $elapsed = $age - $channel->offAge;
        return $elapsed < $release ? intdiv($channel->offEnvelope * ($release - 1 - $elapsed), $release) : 0;
    }
    if ($age < $attack) {
        return intdiv(15 * ($age + 1), $attack);
    }
    if ($age < $attack + $decay) {
        return 15 - intdiv((15 - $sustain) * ($age - $attack + 1), $decay);
    }
    return $sustain;
}

function waveform(object $channel): int
{
    $instrument = $channel->instrument;
    if ($instrument->wave === 'PULSE') {
        return intdiv($channel->phase, 8192) < [1, 2, 4, 6][$channel->mode] ? 15 : 0;
    }
    if ($instrument->wave === 'TRIANGLE') {
        $step = intdiv($channel->phase, 2048);
        return $step < 16 ? 15 - $step : $step - 16;
    }
    if ($instrument->wave === 'SAW') {
        return intdiv($channel->phase, 4096);
    }
    if ($instrument->wave === 'TABLE') {
        return $instrument->table[intdiv($channel->phase, 2048)];
    }
    return $channel->register % 2 === 0 ? 15 : 0;
}

function clockNoise(int $register, int $mode): int
{
    $bit = ($register & 1) ^ (($register >> ($mode === 0 ? 1 : 6)) & 1);
    return intdiv($register, 2) + $bit * 16384;
}
