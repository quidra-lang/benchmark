<?php

function readInput()
{
    $lines = file('input/signal.csv', FILE_IGNORE_NEW_LINES);
    [$sampleRate, $count] = array_map('intval', explode(',', $lines[0]));
    $first = $second = [];
    for ($i = 1; $i <= $count; $i++) {
        [$a, $b] = explode(',', $lines[$i]);
        $first[] = (float)$a;
        $second[] = (float)$b;
    }
    $fields = array_map(fn($line) => array_slice(explode(' ', $line), 1), file('input/params.txt', FILE_IGNORE_NEW_LINES));
    $params = [
        'mainLength' => (int)$fields[0][0], 'mainWindow' => $fields[1][0], 'threshold' => (float)$fields[2][0],
        'peakCount' => (int)$fields[3][0], 'fundamental' => (float)$fields[4][0], 'search' => (int)$fields[4][1],
        'welchLength' => (int)$fields[5][0], 'welchWindow' => $fields[5][1],
        'frameLength' => (int)$fields[6][0], 'hop' => (int)$fields[6][1], 'shadeWidth' => (int)$fields[6][2], 'frameWindow' => $fields[6][3],
        'onsetFactor' => (float)$fields[7][0], 'pitch' => array_map('intval', $fields[8]), 'bandpass' => array_map('intval', $fields[9]),
        'notch' => array_map('intval', $fields[10]), 'envelope' => array_map('intval', $fields[11]), 'zoom' => array_map('intval', $fields[12]),
        'fir' => array_map('floatval', $fields[13]), 'maxLag' => (int)$fields[14][0], 'bands' => array_map('intval', $fields[15]),
        'thirdOctave' => array_map('intval', $fields[16]), 'blockLength' => (int)$fields[17][0]
    ];
    return ['sampleRate' => $sampleRate, 'count' => $count, 'channels' => [$first, $second], 'params' => $params];
}
