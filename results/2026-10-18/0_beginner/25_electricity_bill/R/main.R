names <- c("Sato", "Suzuki", "Takahashi", "Tanaka", "Ito", "Watanabe")
usages <- c(85, 120, 254, 300, 438, 176)
total <- 0
for (i in seq_along(names)) {
    usage <- usages[i]
    bill <- 900 + min(usage, 120)*30 + min(max(usage-120, 0), 180)*36 + max(usage-300, 0)*40
    total <- total + bill
    cat(sprintf("%s: %d kWh, %d yen\n", names[i], usage, bill))
}
cat(sprintf("total: %d yen\n", total))
