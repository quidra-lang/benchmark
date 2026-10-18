<?php
foreach ([[1,-3,-10],[-2,5,4],[3,1,-2],[4,-12,9],[1,2,5],[-2,3,-4]] as [$a,$b,$c]) {
    $discriminant = $b*$b-4*$a*$c;
    printf('%d %d %d: ',$a,$b,$c);
    if ($discriminant > 0) {
        $first = (-$b+sqrt($discriminant))/(2*$a); $second = (-$b-sqrt($discriminant))/(2*$a);
        printf("x1 = %.4F, x2 = %.4F\n",round(max($first,$second),4,PHP_ROUND_HALF_UP),round(min($first,$second),4,PHP_ROUND_HALF_UP));
    } elseif ($discriminant === 0) printf("x = %.4F\n",round(-$b/(2*$a),4,PHP_ROUND_HALF_UP));
    else {
        $real = round(-$b/(2*$a),4,PHP_ROUND_HALF_UP); $imaginary = round(sqrt(-$discriminant)/(2*abs($a)),4,PHP_ROUND_HALF_UP);
        printf("x = %.4F + %.4Fi, %.4F - %.4Fi\n",$real,$imaginary,$real,$imaginary);
    }
}
