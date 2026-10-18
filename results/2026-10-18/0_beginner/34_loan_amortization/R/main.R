balance <- 1000000; month <- 0; total_interest <- 0; total_paid <- 0
while (balance > 0) {
    month <- month + 1
    interest <- balance %/% 100
    payment <- min(50000, balance + interest)
    principal <- payment - interest
    balance <- balance - principal
    total_interest <- total_interest + interest
    total_paid <- total_paid + payment
    cat(sprintf("month %d: interest=%d principal=%d balance=%d\n", month, interest, principal, balance))
}
cat(sprintf("total interest: %d\ntotal paid: %d\n", total_interest, total_paid))
