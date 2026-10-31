balance = 1000000
month = total_interest = total_paid = 0
while balance > 0:
    month += 1
    interest = balance // 100
    payment = min(50000, balance + interest)
    principal = payment - interest
    balance -= principal
    total_interest += interest
    total_paid += payment
    print(f"month {month}: interest={interest} principal={principal} balance={balance}")
print(f"total interest: {total_interest}")
print(f"total paid: {total_paid}")
