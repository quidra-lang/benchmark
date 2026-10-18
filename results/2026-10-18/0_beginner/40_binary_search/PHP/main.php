<?php
$numbers = [3,8,11,15,19,24,27,31,36,42,47,53,58,64,70,77];
foreach ([42,3,77,31,50,1] as $target) {
    $lo = 0;
    $hi = count($numbers)-1;
    $found = -1;
    $probes = [];
    while ($lo <= $hi) {
        $mid = intdiv($lo+$hi,2);
        $probes[] = $mid;
        if ($numbers[$mid] === $target) {
            $found = $mid;
            break;
        }
        elseif ($numbers[$mid] < $target) $lo = $mid+1;
        else $hi = $mid-1;
    }
    $result = $found >= 0 ? 'index '.$found : 'not found';
    printf("%d: probes %s -> %s\n",$target,implode(' ',$probes),$result);
}
