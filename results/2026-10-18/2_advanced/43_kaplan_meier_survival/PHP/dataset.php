<?php

function readDataset()
{
    $lines = file('input/subjects.csv', FILE_IGNORE_NEW_LINES);
    $subjects = [];
    foreach (array_slice($lines, 1) as $line) {
        [$id, $group, $time, $event, $age, $sex, $stage] = explode(',', $line);
        $subjects[] = [
            'id' => (int)$id, 'group' => $group, 'time' => (int)$time,
            'event' => (int)$event, 'age' => (int)$age, 'sex' => $sex, 'stage' => (int)$stage
        ];
    }
    usort($subjects, fn($a, $b) => $a['id'] <=> $b['id']);
    $fields = array_map(fn($line) => array_slice(explode(' ', $line), 1), file('input/params.txt', FILE_IGNORE_NEW_LINES));
    return [$subjects, [
        'groups' => $fields[0],
        'reportTimes' => array_map('intval', $fields[1]),
        'tau' => (int)$fields[2][0],
        'lifeWidth' => (int)$fields[3][0],
        'lifeCount' => (int)$fields[3][1],
        'strata' => $fields[4][0],
        'subgroups' => $fields[5],
        'landmark' => (int)$fields[6][0],
        'covariates' => $fields[7],
        'residuals' => (int)$fields[8][0],
        'plot' => [
            'width' => (int)$fields[9][0], 'height' => (int)$fields[9][1],
            'time' => (int)$fields[9][2], 'divisions' => (int)$fields[9][3]
        ]
    ]];
}
