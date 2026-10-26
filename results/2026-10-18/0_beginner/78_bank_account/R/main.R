balances <- c(Nina = 12000, Leo = 3500, Emma = 800)
transactions <- c(
  "deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000", "withdraw Leo 4000",
  "transfer Emma Nina 2500", "transfer Emma Nina 2000", "withdraw Emma 300", "deposit Nina 750",
  "transfer Leo Emma 3200", "withdraw Nina 9800"
)
for (number in seq_along(transactions)) {
  parts <- strsplit(transactions[number], " ", fixed = TRUE)[[1]]
  operation <- parts[1]
  name <- parts[2]
  amount <- as.integer(tail(parts, 1))
  success <- operation == "deposit" || balances[name] >= amount
  if (success) {
    if (operation == "deposit") {
      balances[name] <- balances[name] + amount
    } else {
      balances[name] <- balances[name] - amount
      if (operation == "transfer") balances[parts[3]] <- balances[parts[3]] + amount
    }
  }
  result <- if (success) "ok" else "failed (insufficient funds)"
  cat(sprintf("op %d: %s %s\n", number, transactions[number], result))
}
for (name in sort(names(balances), method = "radix")) cat(sprintf("%s: %d\n", name, balances[name]))
