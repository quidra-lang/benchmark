integer_text <- function(values) sprintf("%.0f", values)
real_text <- function(values) {
  text <- sprintf("%.4f", values)
  text[text == "-0.0000"] <- "0.0000"
  text
}
reals <- function(values) paste(real_text(values), collapse = " ")
four_decimal <- function(value) as.numeric(real_text(value))
amount <- function(cents) {
  absolute <- abs(cents)
  paste0(ifelse(cents < 0, "-", ""), integer_text(absolute %/% 100), ".", sprintf("%02d", as.integer(absolute %% 100)))
}
write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
