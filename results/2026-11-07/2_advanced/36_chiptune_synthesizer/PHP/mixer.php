<?php

function generate(array $channels, int $count, int $gain, array $mute, array &$samples, ?array &$lanes = null): int
{
    $clipped = 0;
    for ($i = 0; $i < $count; $i++) {
        $mixed = 0;
        foreach ($channels as $k => $channel) {
            $value = 0;
            if ($channel->sounding) {
                $value = (2 * waveform($channel) - 15) * $channel->amplitude;
                $channel->phase += $channel->increment;
                if ($channel->phase >= 65536) {
                    $channel->phase -= 65536;
                    if ($channel->instrument->wave === 'NOISE') {
                        $channel->register = clockNoise($channel->register, $channel->mode);
                    }
                }
            }
            if ($lanes !== null) {
                $lanes[$k][] = $value;
            }
            if ($mute[$k] === 0) {
                $mixed += $value;
            }
        }
        $sample = 128 + floorDiv($gain * $mixed, 4096);
        if ($sample < 0 || $sample > 255) {
            $clipped++;
            $sample = min(255, max(0, $sample));
        }
        $samples[] = $sample;
    }
    return $clipped;
}

function fadeOut(array &$samples, int $length): void
{
    $count = min($length, count($samples));
    for ($i = count($samples) - $count; $i < count($samples); $i++) {
        $samples[$i] = 128 + floorDiv(($samples[$i] - 128) * (count($samples) - 1 - $i), $count);
    }
}
