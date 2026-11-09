<?php

$operations = [
    'add email 3', 'add backup 5', 'add deploy 1', 'run', 'add report 3', 'add test 2',
    'add lint 3', 'run', 'run', 'add cleanup 5', 'add review 2', 'run', 'add build 1', 'add docs 4',
    'run', 'run',
];
$queue = new SplPriorityQueue();
foreach ($operations as $sequence => $operation) {
    $parts = explode(' ', $operation);
    if ($parts[0] === 'add') {
        $queue->insert([$parts[1], (int) $parts[2]], [-(int) $parts[2], -$sequence]);
    } else {
        [$name, $priority] = $queue->extract();
        printf("run: %s (priority %d)\n", $name, $priority);
    }
}
$remaining = [];
while (!$queue->isEmpty()) {
    $remaining[] = $queue->extract()[0];
}
echo 'remaining: ', implode(' ', $remaining), "\n";
