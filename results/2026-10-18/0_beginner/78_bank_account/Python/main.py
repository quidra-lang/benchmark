balances = {"Nina": 12000, "Leo": 3500, "Emma": 800}
transactions = [
    "deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",
    "withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",
    "withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800",
]
for number, transaction in enumerate(transactions, 1):
    parts = transaction.split()
    operation, name, amount = parts[0], parts[1], int(parts[-1])
    success = operation == "deposit" or balances[name] >= amount
    if success:
        if operation == "deposit":
            balances[name] += amount
        else:
            balances[name] -= amount
            if operation == "transfer":
                balances[parts[2]] += amount
    result = "ok" if success else "failed (insufficient funds)"
    print(f"op {number}: {transaction} {result}")
for name in sorted(balances):
    print(f"{name}: {balances[name]}")
