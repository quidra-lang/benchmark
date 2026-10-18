<?php
$balance = 1000000; $month = $totalInterest = $totalPaid = 0;
while ($balance > 0) {
    $month++;
    $interest = intdiv($balance,100);
    $payment = min(50000,$balance+$interest);
    $principal = $payment-$interest;
    $balance -= $principal;
    $totalInterest += $interest; $totalPaid += $payment;
    printf("month %d: interest=%d principal=%d balance=%d\n",$month,$interest,$principal,$balance);
}
printf("total interest: %d\ntotal paid: %d\n",$totalInterest,$totalPaid);
