<?php
$strings = ['(a + b) * [c - d]','{x = [1, 2, (3 + 4)]}','f(a[i] + g(b)}','(1 + 2)) * 3','if (a < b) { c = d[0]; }','((a + b] * c','[{(x * y) - z}'];
$matching = [')'=>'(',']'=>'[','}'=>'{'];
foreach ($strings as $text) {
    $stack = []; $error = -1;
    for ($position = 0; $position < strlen($text); $position++) {
        $c = $text[$position];
        if (str_contains('([{',$c)) $stack[] = $c;
        elseif (isset($matching[$c])) {
            if (!$stack || $stack[count($stack)-1] !== $matching[$c]) { $error = $position; break; }
            array_pop($stack);
        }
    }
    if ($error < 0 && $stack) $error = strlen($text);
    printf("%s -> %s\n",$text,$error < 0 ? 'balanced' : 'error at index '.$error);
}
