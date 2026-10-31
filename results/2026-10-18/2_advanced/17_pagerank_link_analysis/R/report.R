integer_text <- function(value) sprintf("%.0f", value)
fixed <- function(value, places = 6L) {
  text <- sprintf(paste0("%.", places, "f"), value)
  negative_zero <- startsWith(text, "-") & as.numeric(text) == 0
  text[negative_zero] <- substring(text[negative_zero], 2L)
  text
}
scaled <- function(value, places = 6L) as.numeric(gsub(".", "", fixed(value, places), fixed = TRUE))
fraction <- function(numerator, denominator) {
  first <- abs(numerator)
  second <- denominator
  while (second != 0) {
    remainder <- first %% second
    first <- second
    second <- remainder
  }
  numerator <- numerator / first
  denominator <- denominator / first
  paste0(integer_text(numerator), "/", integer_text(denominator), " ", fixed(numerator / denominator, 4L))
}
write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
