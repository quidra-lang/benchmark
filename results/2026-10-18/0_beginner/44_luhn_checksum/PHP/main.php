<?php
foreach (['688126340316','0128469655154','92181914514156','177332430060552','7982377590420309','9884593615513906'] as $number) {
    $total = 0;
    for ($position = 1; $position <= strlen($number); $position++) {
        $digit = (int)$number[strlen($number)-$position];
        if ($position%2 === 0) {
            $digit *= 2;
            if ($digit > 9) $digit -= 9;
        }
        $total += $digit;
    }
    if ($total%10 === 0) printf("%s: valid\n",$number);
    else {
        $expected = (10-($total-(int)$number[strlen($number)-1])%10)%10;
        printf("%s: invalid (expected check digit %d)\n",$number,$expected);
    }
}
