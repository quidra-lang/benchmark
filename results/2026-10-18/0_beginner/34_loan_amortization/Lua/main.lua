local balance, month, total_interest, total_paid = 1000000, 0, 0, 0
while balance > 0 do
    month = month + 1
    local interest = balance // 100
    local payment = math.min(50000, balance + interest)
    local principal = payment - interest
    balance = balance - principal
    total_interest = total_interest + interest
    total_paid = total_paid + payment
    io.write(string.format("month %d: interest=%d principal=%d balance=%d\n", month, interest, principal, balance))
end
io.write(string.format("total interest: %d\ntotal paid: %d\n", total_interest, total_paid))
