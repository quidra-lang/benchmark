<?php
foreach ([84,9973,15625,1001,123456,48000,999958,999999] as $original) {
    $remaining = $original; $divisor = 2; $factors = [];
    while ($divisor*$divisor <= $remaining) {
        $exponent = 0;
        while ($remaining%$divisor === 0) { $remaining = intdiv($remaining,$divisor); $exponent++; }
        if ($exponent > 0) $factors[] = $exponent === 1 ? (string)$divisor : $divisor.'^'.$exponent;
        $divisor++;
    }
    if ($remaining > 1) $factors[] = (string)$remaining;
    printf("%d = %s\n",$original,implode(' * ',$factors));
}
