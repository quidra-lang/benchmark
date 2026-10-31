<?php

$households = [['Sato', 85], ['Suzuki', 120], ['Takahashi', 254], ['Tanaka', 300], ['Ito', 438], ['Watanabe', 176]];
$total = 0;
foreach ($households as [$name, $usage]) {
    $bill = 900 + min($usage, 120) * 30 + min(max($usage - 120, 0), 180) * 36 + max($usage - 300, 0) * 40;
    $total += $bill;
    printf("%s: %d kWh, %d yen\n", $name, $usage, $bill);
}
printf("total: %d yen\n", $total);
