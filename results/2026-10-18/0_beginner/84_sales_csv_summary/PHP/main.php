<?php
$lines = ['date,region,product,quantity,unit_price','2026-04-01,north,notebook,10,200','2026-04-01,east,marker,6,150','2026-04-01,south,eraser,25,80','2026-04-02,west,stapler,4,600','2026-04-02,north,marker,8,150','2026-04-02,east,notebook,9,200','2026-04-03,south,stapler,3,600','2026-04-03,west,eraser,15,80','2026-04-03,north,eraser,20,80','2026-04-04,east,stapler,5,600','2026-04-04,south,notebook,6,200','2026-04-04,west,marker,8,150'];
$regions = $products = $days = [];
$total = 0;
foreach (array_slice($lines,1) as $line) {
    [$date,$region,$product,$quantity,$price] = explode(',',$line);
    $quantity = (int)$quantity;
    $price = (int)$price;
    $amount = $quantity*$price;
    $total += $amount;
    $regions[$region] = ($regions[$region] ?? 0)+$amount;
    $products[$product] = ($products[$product] ?? 0)+$quantity;
    $days[$date] = ($days[$date] ?? 0)+$amount;
}
printf("total: %d\n",$total);
$regionNames = array_keys($regions);
usort($regionNames,fn($a,$b) => ($regions[$b]<=>$regions[$a]) ?: strcmp($a,$b));
foreach ($regionNames as $region) printf("%s: %d\n",$region,$regions[$region]);
ksort($products,SORT_STRING);
foreach ($products as $product => $quantity) printf("%s: %d\n",$product,$quantity);
$dates = array_keys($days);
usort($dates,fn($a,$b) => ($days[$b]<=>$days[$a]) ?: strcmp($a,$b));
printf("best day: %s (%d)\n",$dates[0],$days[$dates[0]]);
