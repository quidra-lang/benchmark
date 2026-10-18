<?php
function toRoman(int $number): string {
    $result = '';
    foreach ([[1000,'M'],[900,'CM'],[500,'D'],[400,'CD'],[100,'C'],[90,'XC'],[50,'L'],[40,'XL'],[10,'X'],[9,'IX'],[5,'V'],[4,'IV'],[1,'I']] as [$value,$symbol]) {
        while ($number >= $value) {
            $result .= $symbol;
            $number -= $value;
        }
    }
    return $result;
}
function fromRoman(string $roman): int {
    $values = ['I'=>1,'V'=>5,'X'=>10,'L'=>50,'C'=>100,'D'=>500,'M'=>1000];
    $total = 0;
    for ($i = 0; $i < strlen($roman); $i++) {
        $value = $values[$roman[$i]];
        $total += $i+1 < strlen($roman) && $value < $values[$roman[$i+1]] ? -$value : $value;
    }
    return $total;
}
foreach ([9,14,49,94,444,1994,2768,3999] as $number) {
    $roman = toRoman($number);
    printf("%d -> %s -> %d\n",$number,$roman,fromRoman($roman));
}
