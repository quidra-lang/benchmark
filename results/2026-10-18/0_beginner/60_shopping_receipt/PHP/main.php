<?php
$items = [['milk',198,2,'food'],['notebook',165,3,'general'],['bread',248,1,'food'],['apple',128,4,'food'],['detergent',437,1,'general'],['eggs',268,1,'food']];
$totals = ['food'=>0,'general'=>0];
foreach ($items as [$name,$price,$quantity,$category]) {
    $subtotal = $price*$quantity;
    $totals[$category] += $subtotal;
    printf("%s %d x %d = %d\n",$name,$price,$quantity,$subtotal);
}
$payment = 0;
foreach (['food'=>8,'general'=>10] as $category => $rate) {
    $tax = intdiv($totals[$category]*$rate,100);
    $payment += $totals[$category]+$tax;
    printf("%s: %d yen, tax %d yen\n",$category,$totals[$category],$tax);
}
printf("total: %d yen\n",$payment);
