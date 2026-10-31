days <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
amounts <- c(7, 12, 4, 15, 9, 18, 11)
cat(sprintf("%s | %s %d\n", days, strrep("*", amounts), amounts), sep = "")
