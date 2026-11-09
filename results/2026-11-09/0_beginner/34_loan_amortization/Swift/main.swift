var balance = 1000000, month = 0, totalInterest = 0, totalPaid = 0
while balance > 0 {
    month += 1
    let interest = balance / 100
    let payment = min(50000, balance + interest)
    let principal = payment - interest
    balance -= principal
    totalInterest += interest
    totalPaid += payment
    print("month \(month): interest=\(interest) principal=\(principal) balance=\(balance)")
}
print("total interest: \(totalInterest)")
print("total paid: \(totalPaid)")
