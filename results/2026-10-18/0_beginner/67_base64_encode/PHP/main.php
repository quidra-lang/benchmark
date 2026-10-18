<?php
function encode64(string $source): string {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    $output = '';
    for ($first = 0; $first < strlen($source); $first += 3) {
        $remaining = min(3,strlen($source)-$first);
        $value = 0;
        for ($offset = 0; $offset < 3; $offset++) $value = $value*256+($offset < $remaining ? ord($source[$first+$offset]) : 0);
        foreach ([262144,4096,64,1] as $i => $divisor) $output .= $i < $remaining+1 ? $alphabet[intdiv($value,$divisor)%64] : '=';
    }
    return $output;
}
foreach (['Man','Hello, World!','','<b>bold</b>','a+b=c?'] as $source) printf("\"%s\" -> \"%s\"\n",$source,encode64($source));
