<?php
$text = 'she sells sea shells by the sea shore';
$frequencies = array_count_values(str_split($text));
ksort($frequencies,SORT_STRING);
$trees = [];
foreach ($frequencies as $symbol => $frequency) $trees[] = ['weight'=>$frequency,'smallest'=>ord($symbol),'symbol'=>$symbol];
while (count($trees) > 1) {
    usort($trees,fn($a,$b) => ($a['weight']<=>$b['weight']) ?: ($a['smallest']<=>$b['smallest']));
    $left = array_shift($trees);
    $right = array_shift($trees);
    $trees[] = ['weight'=>$left['weight']+$right['weight'],'smallest'=>min($left['smallest'],$right['smallest']),'left'=>$left,'right'=>$right];
}
function visit(array $node, string $prefix, array &$codes): void {
    if (isset($node['symbol'])) $codes[$node['symbol']] = $prefix;
    else {
        visit($node['left'],$prefix.'0',$codes);
        visit($node['right'],$prefix.'1',$codes);
    }
}
$codes = [];
visit($trees[0],'',$codes);
$bits = 0;
foreach ($frequencies as $symbol => $frequency) {
    printf("'%s' freq=%d code=%s\n",$symbol,$frequency,$codes[$symbol]);
    $bits += $frequency*strlen($codes[$symbol]);
}
printf("encoded bits: %d\nfixed 8-bit: %d\n",$bits,strlen($text)*8);
