package main

import (
	"fmt"
)

func main() {
	balance, month, totalInterest, totalPaid := 1000000, 0, 0, 0;
	for balance > 0 {
		month++;
		interest := balance / 100;
		payment := min(50000, balance + interest);
		principal := payment - interest;
		balance -= principal;
		totalInterest += interest;
		totalPaid += payment;
		fmt.Printf("month %d: interest=%d principal=%d balance=%d\n", month, interest, principal, balance)
	};
	fmt.Printf("total interest: %d\ntotal paid: %d\n", totalInterest, totalPaid)
}
