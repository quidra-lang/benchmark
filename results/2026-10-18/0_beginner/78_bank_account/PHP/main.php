<?php
$balances = ['Nina'=>12000,'Leo'=>3500,'Emma'=>800];
$transactions = ['deposit Emma 1200','withdraw Leo 4000','transfer Nina Leo 5000','withdraw Leo 4000','transfer Emma Nina 2500','transfer Emma Nina 2000','withdraw Emma 300','deposit Nina 750','transfer Leo Emma 3200','withdraw Nina 9800'];
foreach ($transactions as $number => $transaction) {
    $parts = explode(' ',$transaction);
    [$operation,$name] = $parts;
    $amount = (int)$parts[count($parts)-1];
    $success = $operation === 'deposit' || $balances[$name] >= $amount;
    if ($success) {
        if ($operation === 'deposit') $balances[$name] += $amount;
        else {
            $balances[$name] -= $amount;
            if ($operation === 'transfer') $balances[$parts[2]] += $amount;
        }
    }
    printf("op %d: %s %s\n",$number+1,$transaction,$success ? 'ok' : 'failed (insufficient funds)');
}
ksort($balances,SORT_STRING);
foreach ($balances as $name => $balance) printf("%s: %d\n",$name,$balance);
