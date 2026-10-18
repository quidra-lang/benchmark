days <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
amounts <- c(7, 12, 4, 15, 9, 18, 11)
for (i in seq_along(days)) cat(sprintf("%s | %s %d\n", days[i], strrep("*", amounts[i]), amounts[i]))
