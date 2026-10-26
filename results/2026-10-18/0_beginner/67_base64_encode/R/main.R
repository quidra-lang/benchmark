encode64 <- function(source) {
  alphabet <- strsplit("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", "", fixed = TRUE)[[1]]
  bytes <- utf8ToInt(source)
  if (length(bytes) == 0) {
    return("")
  }
  output <- character(0)
  for (first in seq(1, length(bytes), by = 3)) {
    remaining <- min(3, length(bytes) - first + 1)
    value <- 0
    for (offset in 0:2) {
      value <- value * 256 + (if (offset < remaining) bytes[first + offset] else 0)
    }
    divisors <- c(262144, 4096, 64, 1)
    for (i in 1:4) {
      output <- c(output, if (i <= remaining + 1) alphabet[(value %/% divisors[i]) %% 64 + 1] else "=")
    }
  }
  paste(output, collapse = "")
}

for (source in c("Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?")) {
  cat(sprintf('"%s" -> "%s"\n', source, encode64(source)))
}
