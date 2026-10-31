function main()
    balance, month, total_interest, total_paid = 1000000, 0, 0, 0
    while balance > 0
        month += 1
        interest = div(balance, 100)
        payment = min(50000, balance + interest)
        principal = payment - interest
        balance -= principal
        total_interest += interest
        total_paid += payment
        println("month $month: interest=$interest principal=$principal balance=$balance")
    end
    println("total interest: ", total_interest)
    println("total paid: ", total_paid)
end

main()
