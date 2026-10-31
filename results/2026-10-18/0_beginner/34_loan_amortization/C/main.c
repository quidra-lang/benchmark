#include <stdio.h>

int main(void) {
    int balance = 1000000, month = 0, total_interest = 0, total_paid = 0;
    while (balance > 0) {
        month++;
        int interest = balance / 100;
        int payment = balance + interest < 50000 ? balance + interest : 50000;
        int principal = payment - interest;
        balance -= principal;
        total_interest += interest;
        total_paid += payment;
        printf("month %d: interest=%d principal=%d balance=%d\n", month, interest, principal, balance);
    }
    printf("total interest: %d\ntotal paid: %d\n", total_interest, total_paid);
    return 0;
}
