<?php
function visit(string $prefix, array $used, int &$counter): void {
    $characters = 'ABCD';
    if (strlen($prefix) === 4) { $counter++; printf("%d: %s\n",$counter,$prefix); return; }
    for ($i = 0; $i < 4; $i++) if (!$used[$i]) {
        $used[$i] = true;
        visit($prefix.$characters[$i],$used,$counter);
        $used[$i] = false;
    }
}
$counter = 0;
visit('',array_fill(0,4,false),$counter);
