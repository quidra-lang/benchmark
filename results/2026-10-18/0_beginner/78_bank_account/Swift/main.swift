let transactions = ["deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",
    "withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",
    "withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800"]
var balances = ["Nina": 12000, "Leo": 3500, "Emma": 800]
for (i, transaction) in transactions.enumerated() {
    let parts = transaction.split(separator: " ").map(String.init)
    let name = parts[1], amount = Int(parts.last!)!
    let success = parts[0] == "deposit" || balances[name]! >= amount
    if success {
        if parts[0] == "deposit" {
            balances[name]! += amount
        } else {
            balances[name]! -= amount
            if parts[0] == "transfer" { balances[parts[2]]! += amount }
        }
    }
    print("op \(i + 1): \(transaction)" + (success ? " ok" : " failed (insufficient funds)"))
}
for name in balances.keys.sorted() { print("\(name): \(balances[name]!)") }
