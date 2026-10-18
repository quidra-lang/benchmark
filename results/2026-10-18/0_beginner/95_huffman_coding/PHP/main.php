<?php
$text = 'she sells sea shells by the sea shore';
$frequencies = array_count_values(str_split($text));
ksort($frequencies,SORT_STRING);
$trees = new SplPriorityQueue();
foreach ($frequencies as $symbol => $frequency) {
    $node = ['weight'=>$frequency,'smallest'=>ord($symbol),'symbol'=>$symbol];
    $trees->insert($node,[-$frequency,-ord($symbol)]);
}
while (count($trees) > 1) {
    $left = $trees->extract();
    $right = $trees->extract();
    $node = ['weight'=>$left['weight']+$right['weight'],'smallest'=>min($left['smallest'],$right['smallest']),'left'=>$left,'right'=>$right];
    $trees->insert($node,[-$node['weight'],-$node['smallest']]);
}
function visit(array $node, string $prefix, array &$codes): void {
    if (isset($node['symbol'])) $codes[$node['symbol']] = $prefix;
    else {
        visit($node['left'],$prefix.'0',$codes);
        visit($node['right'],$prefix.'1',$codes);
    }
}
$codes = [];
visit($trees->extract(),'',$codes);
$bits = 0;
foreach ($frequencies as $symbol => $frequency) {
    printf("'%s' freq=%d code=%s\n",$symbol,$frequency,$codes[$symbol]);
    $bits += $frequency*strlen($codes[$symbol]);
}
printf("encoded bits: %d\nfixed 8-bit: %d\n",$bits,strlen($text)*8);
