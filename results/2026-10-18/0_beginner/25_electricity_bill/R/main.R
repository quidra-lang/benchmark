names <- c("Sato", "Suzuki", "Takahashi", "Tanaka", "Ito", "Watanabe")
usages <- c(85, 120, 254, 300, 438, 176)
bills <- 900 + pmin(usages, 120)*30 + pmin(pmax(usages-120, 0), 180)*36 + pmax(usages-300, 0)*40
cat(sprintf("%s: %d kWh, %d yen\n", names, usages, bills), sep = "")
cat(sprintf("total: %d yen\n", sum(bills)))
