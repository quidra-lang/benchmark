const balances = new Map([["Nina", 12000], ["Leo", 3500], ["Emma", 800]]);
const transactions = [
  "deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",
  "withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",
  "withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800"
];
transactions.forEach((transaction, number) => {
  const parts = transaction.split(" ");
  const operation = parts[0], name = parts[1], amount = Number(parts.at(-1));
  const success = operation === "deposit" || balances.get(name)! >= amount;
  if (success) {
    if (operation === "deposit") balances.set(name, balances.get(name)! + amount);
    else {
      balances.set(name, balances.get(name)! - amount);
      if (operation === "transfer") balances.set(parts[2], balances.get(parts[2])! + amount);
    }
  }
  const result = success ? "ok" : "failed (insufficient funds)";
  console.log(`op ${number + 1}: ${transaction} ${result}`);
});
for (const name of [...balances.keys()].sort()) console.log(`${name}: ${balances.get(name)}`);
