<?php
function before(array $a, array $b): bool {
    return $a[0] < $b[0] || ($a[0] === $b[0] && $a[1] < $b[1]);
}
function heapPush(array &$heap, array $task): void {
    $heap[] = $task;
    $child = count($heap)-1;
    while ($child > 0) {
        $parent = intdiv($child-1,2);
        if (!before($heap[$child],$heap[$parent])) break;
        [$heap[$child],$heap[$parent]] = [$heap[$parent],$heap[$child]];
        $child = $parent;
    }
}
function heapPop(array &$heap): array {
    $task = $heap[0];
    $last = array_pop($heap);
    if ($heap) {
        $heap[0] = $last;
        $parent = 0;
        while (2*$parent+1 < count($heap)) {
            $child = 2*$parent+1;
            if ($child+1 < count($heap) && before($heap[$child+1],$heap[$child])) $child++;
            if (!before($heap[$child],$heap[$parent])) break;
            [$heap[$child],$heap[$parent]] = [$heap[$parent],$heap[$child]];
            $parent = $child;
        }
    }
    return $task;
}
$operations = ['add email 3','add backup 5','add deploy 1','run','add report 3','add test 2','add lint 3','run','run','add cleanup 5','add review 2','run','add build 1','add docs 4','run','run'];
$heap = [];
foreach ($operations as $sequence => $operation) {
    $parts = explode(' ',$operation);
    if ($parts[0] === 'add') heapPush($heap,[(int)$parts[2],$sequence,$parts[1]]);
    else {
        [$priority,$ignored,$name] = heapPop($heap);
        printf("run: %s (priority %d)\n",$name,$priority);
    }
}
$remaining = [];
while ($heap) $remaining[] = heapPop($heap)[2];
echo 'remaining: ', implode(' ',$remaining), "\n";
