<?php
$cache = []; $hits = $misses = 0;
foreach (['B','A','C','B','D','A','B','E','A','D','D','C','A','E','B'] as $key) {
    $index = array_search($key,$cache,true);
    if ($index !== false) {
        $hits++;
        array_splice($cache,$index,1);
        $result = 'hit';
    } else {
        $misses++;
        $result = count($cache) === 3 ? 'miss, evict '.array_pop($cache) : 'miss';
    }
    array_unshift($cache,$key);
    printf("%s: %s [%s]\n",$key,$result,implode(' ',$cache));
}
printf("hits: %d misses: %d\n",$hits,$misses);
