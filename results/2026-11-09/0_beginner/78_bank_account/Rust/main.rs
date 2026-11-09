fn main() {
    let mut balances =
        std::collections::BTreeMap::from([("Nina", 12000), ("Leo", 3500), ("Emma", 800)]);
    for (k, transaction) in [
        "deposit Emma 1200",
        "withdraw Leo 4000",
        "transfer Nina Leo 5000",
        "withdraw Leo 4000",
        "transfer Emma Nina 2500",
        "transfer Emma Nina 2000",
        "withdraw Emma 300",
        "deposit Nina 750",
        "transfer Leo Emma 3200",
        "withdraw Nina 9800",
    ]
    .into_iter()
    .enumerate()
    {
        let parts: Vec<&str> = transaction.split(' ').collect();
        let op = parts[0];
        let from = parts[1];
        let amount: i32 = parts.last().unwrap().parse().unwrap();
        let ok = op == "deposit" || balances[from] >= amount;
        if ok {
            if op == "deposit" {
                *balances.get_mut(from).unwrap() += amount;
            } else {
                *balances.get_mut(from).unwrap() -= amount;
                if op == "transfer" {
                    *balances.get_mut(parts[2]).unwrap() += amount;
                }
            }
        }
        println!(
            "op {}: {} {}",
            k + 1,
            transaction,
            if ok {
                "ok"
            } else {
                "failed (insufficient funds)"
            }
        );
    }
    for (name, balance) in balances {
        println!("{}: {}", name, balance);
    }
}
