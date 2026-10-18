<?php
function encode(string $source): string {
    $result = ''; $i = 0;
    while ($i < strlen($source)) {
        $j = $i+1;
        while ($j < strlen($source) && $source[$j] === $source[$i]) $j++;
        $result .= ($j-$i).$source[$i]; $i = $j;
    }
    return $result;
}
function decode(string $encoded): string {
    preg_match_all('/([0-9]+)([A-Z])/',$encoded,$runs,PREG_SET_ORDER);
    $result = '';
    foreach ($runs as $run) $result .= str_repeat($run[2],(int)$run[1]);
    return $result;
}
foreach (['AAABBBCCCD','WWWWWWWWWWWWBWWWWWWWWWWWWBBB','ALGORITHM','MISSISSIPPI','XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ'] as $source) {
    $encoded = encode($source);
    printf("%s -> %s -> %s\n",$source,$encoded,decode($encoded));
}
