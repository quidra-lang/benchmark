values <- c(48, 73, 56, 91, 35, 62, 84)
mean_value <- sum(values) / length(values)
rounded <- floor(mean_value * 100 + 0.5) / 100
cat(sprintf("%.2f\n", rounded))
